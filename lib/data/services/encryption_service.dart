import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart' hide State, Padding;

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/utils/kill_switch_outbox.dart';
import '../../core/utils/security_lifecycle_mixin.dart';
import '../repositories/handshake_repository.dart';
import '../repositories/transfer_repository.dart';

// ─── Top-level isolate functions ──────────────────────────────────────────────
// These must be top-level (not instance methods) for Flutter's compute().

/// Generates a 2048-bit RSA keypair in a background isolate.
AsymmetricKeyPair<PublicKey, PrivateKey> _generateRsaKeyPairIsolate(void _) =>
    EncryptionService.generateRsaKeyPairSync();

Uint8List runAesGcmEncrypt(List<Uint8List> args) {
  final plaintext = args[0];
  final key = args[1]; // 32 bytes
  final iv = args[2]; // 12 bytes
  try {
    final params = AEADParameters(KeyParameter(key), 128, iv, Uint8List(0));
    final cipher = GCMBlockCipher(AESEngine())..init(true, params);
    return cipher.process(plaintext);
  } finally {
    // Zero inputs inside the isolate before it exits. These are copies of the
    // main-isolate buffers (isolates don't share memory), so this is the only
    // opportunity to wipe them — the main isolate cannot reach this heap.
    plaintext.fillRange(0, plaintext.length, 0);
    key.fillRange(0, key.length, 0);
    iv.fillRange(0, iv.length, 0);
  }
}

Uint8List runAesGcmDecrypt(List<Uint8List> args) {
  final ciphertext = args[0]; // ciphertext + 16-byte GCM tag
  final key = args[1]; // 32 bytes
  final iv = args[2]; // 12 bytes
  try {
    final params = AEADParameters(KeyParameter(key), 128, iv, Uint8List(0));
    final cipher = GCMBlockCipher(AESEngine())..init(false, params);
    return cipher.process(ciphertext);
  } finally {
    // Zero key and IV inside the isolate — plaintext is the return value and
    // cannot be zeroed here, but key material is more sensitive than plaintext.
    key.fillRange(0, key.length, 0);
    iv.fillRange(0, iv.length, 0);
    // ciphertext (input to decrypt) is less sensitive than the output plaintext;
    // zero it anyway to minimise lingering data on this isolate's heap.
    ciphertext.fillRange(0, ciphertext.length, 0);
  }
}

// ─── Result type for AES encryption ──────────────────────────────────────────

class AesEncryptResult {
  final Uint8List ciphertext;
  final Uint8List key;
  final Uint8List iv;

  const AesEncryptResult({
    required this.ciphertext,
    required this.key,
    required this.iv,
  });
}

// ─── EncryptionService ────────────────────────────────────────────────────────

class EncryptionService {
  const EncryptionService._();

  // ─── Secure random ──────────────────────────────────────────────────────

  static Uint8List secureRandomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }

  // ─── AES-256-GCM ────────────────────────────────────────────────────────

  /// Generates a fresh 256-bit AES key + 96-bit IV, then encrypts [plaintext]
  /// via AES-256-GCM in a compute() isolate.
  static Future<AesEncryptResult> encryptAesGcm(Uint8List plaintext) async {
    try {
      final key = secureRandomBytes(32);
      final iv = secureRandomBytes(12);
      final ciphertext = await compute(runAesGcmEncrypt, [plaintext, key, iv]);
      return AesEncryptResult(ciphertext: ciphertext, key: key, iv: iv);
    } catch (e) {
      throw CryptoException('AES encryption failed: $e');
    }
  }

  /// Decrypts [ciphertext] (with GCM tag) using [key] and [iv] in a
  /// compute() isolate.
  static Future<Uint8List> decryptAesGcm(
    Uint8List ciphertext,
    Uint8List key,
    Uint8List iv,
  ) async {
    try {
      return await compute(runAesGcmDecrypt, [ciphertext, key, iv]);
    } catch (e) {
      throw CryptoException('AES decryption failed: $e');
    }
  }

  // ─── RSA key generation ──────────────────────────────────────────────────

  /// Generates a 2048-bit RSA key pair. Runs on the calling isolate
  /// (caller should wrap in compute() if called from UI).
  static AsymmetricKeyPair<PublicKey, PrivateKey> generateRsaKeyPairSync() {
    final secureRandom = FortunaRandom();
    final seedSource = Random.secure();
    secureRandom.seed(
      KeyParameter(
        Uint8List.fromList(
          List<int>.generate(32, (_) => seedSource.nextInt(256)),
        ),
      ),
    );

    final keyGen = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
          secureRandom,
        ),
      );
    return keyGen.generateKeyPair();
  }

  // ─── RSA key encode / decode ─────────────────────────────────────────────

  static String encodePublicKey(RSAPublicKey key) => jsonEncode({
        'modulus': key.modulus!.toRadixString(16),
        'exponent': key.publicExponent!.toRadixString(16),
      });

  static String encodePrivateKey(RSAPrivateKey key) => jsonEncode({
        'modulus': key.modulus!.toRadixString(16),
        'privateExponent': key.privateExponent!.toRadixString(16),
        'p': key.p!.toRadixString(16),
        'q': key.q!.toRadixString(16),
      });

  static RSAPublicKey decodePublicKey(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return RSAPublicKey(
        BigInt.parse(map['modulus'] as String, radix: 16),
        BigInt.parse(map['exponent'] as String, radix: 16),
      );
    } catch (e) {
      throw CryptoException('Failed to decode public key: $e');
    }
  }

  static RSAPrivateKey decodePrivateKey(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return RSAPrivateKey(
        BigInt.parse(map['modulus'] as String, radix: 16),
        BigInt.parse(map['privateExponent'] as String, radix: 16),
        BigInt.parse(map['p'] as String, radix: 16),
        BigInt.parse(map['q'] as String, radix: 16),
      );
    } catch (e) {
      throw CryptoException('Failed to decode private key: $e');
    }
  }

  // ─── RSA-OAEP encrypt / decrypt ──────────────────────────────────────────

  /// RSA-OAEP encrypts [data] with [publicKey]. Used by the sender to wrap
  /// the AES session key.
  static Uint8List rsaEncrypt(RSAPublicKey publicKey, Uint8List data) {
    try {
      final cipher = OAEPEncoding(RSAEngine())
        ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
      return cipher.process(data);
    } catch (e) {
      throw CryptoException('RSA encryption failed: $e');
    }
  }

  /// RSA-OAEP decrypts [ciphertext] with [privateKey]. Used by the receiver
  /// to recover the AES session key.
  static Uint8List rsaDecrypt(RSAPrivateKey privateKey, Uint8List ciphertext) {
    try {
      final cipher = OAEPEncoding(RSAEngine())
        ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
      return cipher.process(ciphertext);
    } catch (e) {
      throw CryptoException('RSA decryption failed: $e');
    }
  }

  // ─── Convenience: decrypt AES key from private key JSON string ───────────

  /// Decodes the private key JSON then RSA-OAEP decrypts [encryptedAESKey].
  /// Convenience wrapper used by DecryptScreen.
  static Uint8List decryptAesKeyWithPrivateKeyJson(
    String privateKeyJson,
    Uint8List encryptedAESKey,
  ) {
    final privateKey = decodePrivateKey(privateKeyJson);
    return rsaDecrypt(privateKey, encryptedAESKey);
  }

  // ─── Receiver session lifecycle ──────────────────────────────────────────

  /// Opens the receiver's mailbox:
  /// Generates a fresh RSA-2048 keypair in an isolate, stores the private key
  /// on-device, and publishes the public key to Firestore.
  static Future<void> setupReceiverSession(String uid) async {
    try {
      final pair = await compute(_generateRsaKeyPairIsolate, null);

      final pubKey  = pair.publicKey  as RSAPublicKey;
      final privKey = pair.privateKey as RSAPrivateKey;

      final pubKeyJson  = encodePublicKey(pubKey);
      final privKeyJson = encodePrivateKey(privKey);

      // Store private key on device only.
      const storage = FlutterSecureStorage();
      await storage.write(
        key: FirebaseConstants.privateKeyStorageKey,
        value: privKeyJson,
      );

      // Publish public key to Firestore and mark user as ready.
      await FirebaseFirestore.instance
          .collection(FirebaseConstants.users)
          .doc(uid)
          .update({
        'publicKey': pubKeyJson,
        'publicKeyUploadedAt': FieldValue.serverTimestamp(),
        'isReadyToReceive': true,
        'sessionActive': true,
      });
    } catch (e) {
      _logSecurityEvent('setupReceiverSession_FAILED', uid, e.toString());
      rethrow;
    }
  }

  /// Closes the receiver's mailbox — the "Closed Mailbox" / Kill Switch rule:
  /// Deletes public key from Firestore, wipes private key from secure storage,
  /// purges all related key-transfer and notification records, and fully
  /// disconnects the paired sender (see step 3d) so a finished session — whether
  /// completed normally or aborted mid-transfer — always tears down the
  /// connection between the two users.
  static Future<void> closeReceiverSession(String uid) async {
    try {
      // 0. Persist outbox record BEFORE any network I/O — guarantees a resume
      //     record exists even if the device crashes during the read below.
      //     selectedSenderUid is unknown here; resumeIfPending() only needs uid.
      await KillSwitchOutbox.persist(uid, null);

      // 0a. Read user doc to capture selectedSenderUid for audit log before clearing it.
      final userSnap = await FirebaseFirestore.instance
          .collection(FirebaseConstants.users)
          .doc(uid)
          .get();
      final selectedSenderUid = userSnap.data()?['selectedSenderUid'] as String?;

      // 1. Remove public key from Firestore and mark user unavailable.
      await FirebaseFirestore.instance
          .collection(FirebaseConstants.users)
          .doc(uid)
          .update({
        'publicKey': FieldValue.delete(),
        'isReadyToReceive': false,
        'sessionActive': false,
        'lastSessionClosed': FieldValue.serverTimestamp(),
        // Clear the receiver-authorized sender so the sender's Firestore
        // stream sees the doc disappear and reverts to the waiting buffer.
        'selectedSenderUid': FieldValue.delete(),
      });

      // 2. Delete private key from secure storage.
      const storage = FlutterSecureStorage();
      await storage.delete(key: FirebaseConstants.privateKeyStorageKey);

      // 3. Delete all handshakes where this user is the receiver.
      final handshakes = await FirebaseFirestore.instance
          .collection(FirebaseConstants.roleHandshakes)
          .where('receiverId', isEqualTo: uid)
          .get();

      if (handshakes.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in handshakes.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      // 3b. Delete sender-side handshakes (sessions where this user was the file-sender).
      final senderHandshakes = await FirebaseFirestore.instance
          .collection(FirebaseConstants.roleHandshakes)
          .where('senderId', isEqualTo: uid)
          .get();

      if (senderHandshakes.docs.isNotEmpty) {
        final batchSender = FirebaseFirestore.instance.batch();
        for (final doc in senderHandshakes.docs) {
          batchSender.delete(doc.reference);
        }
        await batchSender.commit();
      }

      // 3c. Delete pending transfers for this receiver — prevents stale docs from a
      //     previous session auto-navigating the receiver on next mailbox open.
      final staleTransfers = await FirebaseFirestore.instance
          .collection(FirebaseConstants.transfers)
          .where('receiverId', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .get();

      if (staleTransfers.docs.isNotEmpty) {
        final batchTransfers = FirebaseFirestore.instance.batch();
        for (final doc in staleTransfers.docs) {
          batchTransfers.delete(doc.reference);
        }
        await batchTransfers.commit();
      }

      // 3d. Fully disconnect from the paired sender. This method is called by
      //     EVERY session-ending path — manual close, app lifecycle pause/detach,
      //     PopScope back-nav, the 120s sender-silence watchdogs in
      //     ReceiverTransferScreen/DecryptScreen, AND as the final step of
      //     ReceiverEndSessionScreen's post-transfer cleanup — so this single
      //     call covers both "transfer completed" and "disrupted mid-transfer"
      //     without each call site needing its own disconnect logic. Best-effort:
      //     a failure here must not block the rest of the kill switch.
      if (selectedSenderUid != null && selectedSenderUid.isNotEmpty) {
        try {
          await HandshakeRepository().disconnectPair(uid, selectedSenderUid);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('closeReceiverSession: pair disconnect failed: $e');
          }
        }
      }

      // 3e. Write a kill-switch audit log entry (best-effort) if an active
      //     session existed. Lands in audit_logs — the same collection every
      //     other transfer-lifecycle event uses — so it shows up in "Recent
      //     Transfers" / the admin dashboard's transfer-logs tab, instead of
      //     the removed write-only transfer_logs collection nothing displayed.
      if (selectedSenderUid != null && selectedSenderUid.isNotEmpty) {
        try {
          await TransferRepository().writeKillSwitchAuditLog(
            senderId: selectedSenderUid,
            receiverId: uid,
          );
        } catch (e) {
          if (kDebugMode) {
            debugPrint('closeReceiverSession: kill-switch audit log failed: $e');
          }
        }
      }

      // 4. Delete session-related notifications from this user's inbox (best-effort).
      final notifications = await FirebaseFirestore.instance
          .collection(FirebaseConstants.users)
          .doc(uid)
          .collection(FirebaseConstants.notifications)
          .where('type', whereIn: ['rsa_key_received', 'connection_request'])
          .get();

      if (notifications.docs.isNotEmpty) {
        final batch2 = FirebaseFirestore.instance.batch();
        for (final doc in notifications.docs) {
          batch2.delete(doc.reference);
        }
        await batch2.commit();
      }

      // 5. All Firestore cleanup complete — clear the outbox record.
      await KillSwitchOutbox.clear();

      // 6. Log security event (event names only — no key material).
      _logSecurityEvent(
        'Receiver_Session_Closed',
        uid,
        'Firestore_Key_Deleted & Local_Buffer_Zeroed',
      );

      // 7. Best-effort Kotlin GC hint — no key bytes are held natively.
      SecurityLifecycleMixin.requestNativeClear();
    } catch (e) {
      _logSecurityEvent('closeReceiverSession_FAILED', uid, e.toString());
      rethrow;
    }
  }

  // ─── Live-session tracker ────────────────────────────────────────────────
  // Tracks which uid currently holds private key material in secure storage.
  // Every code path that writes the private key calls markLiveSession; every
  // path that deletes it calls clearLiveSession. This lets the Clear Cache
  // sheet verify cleanup without re-reading secure storage after the fact.

  static String? _liveSessionUid;

  static void markLiveSession(String uid) => _liveSessionUid = uid;

  static bool isLiveSessionFor(String uid) => _liveSessionUid == uid;

  static void clearLiveSession(String uid) {
    if (_liveSessionUid == uid) _liveSessionUid = null;
  }

  // ─── Security event logger ───────────────────────────────────────────────

  /// Logs a security event to debugPrint and the Firestore audit collection.
  /// Never logs key material — event names and non-sensitive details only.
  static void _logSecurityEvent(
    String event,
    String userId,
    String details,
  ) {
    final timestamp = DateTime.now().toIso8601String();
    if (kDebugMode) debugPrint('🛡️ [$timestamp] $event | $details');

    FirebaseFirestore.instance
        .collection('security_audit_log')
        .add({
      'event': event,
      'userId': userId,
      'timestamp': FieldValue.serverTimestamp(),
      'details': details,
    }).ignore();
  }
}
