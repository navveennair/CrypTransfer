import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/utils/security_lifecycle_mixin.dart';
import '../../core/utils/tofu_service.dart';
import '../../data/repositories/key_repository.dart';
import '../../data/repositories/transfer_repository.dart';
import '../../data/services/encryption_service.dart';
import '../../data/services/transfer_service.dart';

// ─── Isolate-safe RSA-OAEP encrypt ───────────────────────────────────────────

Uint8List _rsaOaepEncryptIsolate(List<dynamic> args) {
  final publicKeyJson = args[0] as String;
  final data = args[1] as Uint8List;
  final key = EncryptionService.decodePublicKey(publicKeyJson);
  return EncryptionService.rsaEncrypt(key, data);
}

// ─── State snapshot passed to the widget via ValueNotifier ───────────────────

class SenderState {
  final PlatformFile? file;
  final Uint8List? encryptedBytes;
  final Uint8List? aesKey;
  final Uint8List? iv;
  final String? receiverId;
  final String? receiverUsername;
  final Uint8List? encryptedAESKey;
  final bool encrypting;
  final bool encryptingKey;
  final double encryptionProgress;
  final bool receiverReady;
  final int secondsRemaining;
  final bool timerRunning;
  final TofuStatus? tofuStatus;
  final String? receiverFingerprint;

  const SenderState({
    this.file,
    this.encryptedBytes,
    this.aesKey,
    this.iv,
    this.receiverId,
    this.receiverUsername,
    this.encryptedAESKey,
    this.encrypting = false,
    this.encryptingKey = false,
    this.encryptionProgress = 0.0,
    this.receiverReady = false,
    this.secondsRemaining = 60,
    this.timerRunning = false,
    this.tofuStatus,
    this.receiverFingerprint,
  });

  bool get receiverSelected => receiverId != null;
  bool get fileSelected => file != null;
  bool get fileEncrypted => encryptedBytes != null;
  bool get readyToSend => encryptedAESKey != null;

  SenderState copyWith({
    Object? file = _sentinel,
    Object? encryptedBytes = _sentinel,
    Object? aesKey = _sentinel,
    Object? iv = _sentinel,
    Object? receiverId = _sentinel,
    Object? receiverUsername = _sentinel,
    Object? encryptedAESKey = _sentinel,
    bool? encrypting,
    bool? encryptingKey,
    double? encryptionProgress,
    bool? receiverReady,
    int? secondsRemaining,
    bool? timerRunning,
    Object? tofuStatus = _sentinel,
    Object? receiverFingerprint = _sentinel,
  }) {
    return SenderState(
      file: file == _sentinel ? this.file : file as PlatformFile?,
      encryptedBytes: encryptedBytes == _sentinel ? this.encryptedBytes : encryptedBytes as Uint8List?,
      aesKey: aesKey == _sentinel ? this.aesKey : aesKey as Uint8List?,
      iv: iv == _sentinel ? this.iv : iv as Uint8List?,
      receiverId: receiverId == _sentinel ? this.receiverId : receiverId as String?,
      receiverUsername: receiverUsername == _sentinel ? this.receiverUsername : receiverUsername as String?,
      encryptedAESKey: encryptedAESKey == _sentinel ? this.encryptedAESKey : encryptedAESKey as Uint8List?,
      encrypting: encrypting ?? this.encrypting,
      encryptingKey: encryptingKey ?? this.encryptingKey,
      encryptionProgress: encryptionProgress ?? this.encryptionProgress,
      receiverReady: receiverReady ?? this.receiverReady,
      secondsRemaining: secondsRemaining ?? this.secondsRemaining,
      timerRunning: timerRunning ?? this.timerRunning,
      tofuStatus: tofuStatus == _sentinel ? this.tofuStatus : tofuStatus as TofuStatus?,
      receiverFingerprint: receiverFingerprint == _sentinel ? this.receiverFingerprint : receiverFingerprint as String?,
    );
  }
}

// Sentinel used to distinguish "not provided" from explicit null in copyWith.
const _sentinel = Object();

// ─── Callbacks from controller → widget (require BuildContext) ────────────────

typedef SenderErrorCallback = void Function(
    String msg, {Duration? duration, bool clear});
typedef SenderSuccessCallback = void Function(String msg);
typedef SenderInfoCallback = void Function(String msg);
typedef SenderEjectCallback = void Function();
typedef SenderAbortNavigateCallback = void Function(String msg);
typedef SenderKeyChangedCallback = void Function(String uid, String keyJson);

// ─── SenderController ─────────────────────────────────────────────────────────

/// Owns all business logic for [SenderScreen].
///
/// Pattern mirrors [SessionManager]: plain Dart class, no Flutter imports,
/// exposes a [ValueNotifier<SenderState>] so the widget can call
/// `addListener(() => setState(() {}))` and read state from [stateNotifier.value].
///
/// Callbacks (all typed above) let the controller trigger UI-layer side-effects
/// (SnackBars, navigation) that require [BuildContext] without importing Flutter.
class SenderController {
  // ─── Dependencies ──────────────────────────────────────────────────────────

  final KeyRepository connService;
  final TransferRepository transferRepo;

  // Pre-fill values from the widget's constructor (set once on init).
  final String? preFilledPartnerUid;
  final String? preFilledPartnerUsername;

  // ─── Callbacks set by the widget ──────────────────────────────────────────

  /// Called when an error SnackBar should be shown.
  late SenderErrorCallback onError;

  /// Called when a success SnackBar should be shown.
  late SenderSuccessCallback onSuccess;

  /// Called when an info SnackBar should be shown.
  late SenderInfoCallback onInfo;

  /// Called to navigate the sender back to HomeScreen (session ejected).
  late SenderEjectCallback onEject;

  /// Called when the stale-key abort flow needs navigation to HomeScreen.
  /// The controller has already written the abort audit log; the widget must
  /// show [msg] and then navigate.
  late SenderAbortNavigateCallback onAbortNavigate;

  /// Called when TOFU detects a changed key — widget must show the warning dialog.
  late SenderKeyChangedCallback onKeyChanged;

  // ─── Buffer wipe callback (SecurityLifecycleMixin stays on widget) ─────────

  /// Callback into [SecurityLifecycleMixin.wipeAll] on the widget.
  /// Called whenever the controller needs to zero all registered buffers.
  late VoidCallback onBuffersWipe;

  // ─── Buffer registration callbacks ────────────────────────────────────────

  /// Registers a buffer with the widget's [SecurityLifecycleMixin].
  late void Function(Uint8List) onRegisterBuffer;

  /// Unregisters an already-wiped buffer from the widget's [SecurityLifecycleMixin].
  late void Function(Uint8List) onUnregisterBuffer;

  // ─── State ────────────────────────────────────────────────────────────────

  bool _disposed = false;

  final ValueNotifier<SenderState> stateNotifier =
      ValueNotifier(const SenderState());

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _handshakeSub;
  String? _selectedReceiverPublicKeyJson;

  final _progressCtrl = StreamController<double>.broadcast();
  StreamSubscription<double>? _progressSub;

  Timer? _readinessTimer;

  // CR-01: suppress cold-start empty-snapshot eject
  bool _streamSettled = false;
  // true after first successful handshake; used to detect reconnects
  bool _everConnected = false;

  String? _handshakeDocId;

  // ─── Constructor ──────────────────────────────────────────────────────────

  SenderController({
    required this.connService,
    required this.transferRepo,
    this.preFilledPartnerUid,
    this.preFilledPartnerUsername,
    required String? initialHandshakeDocId,
  }) {
    _handshakeDocId = initialHandshakeDocId;
  }

  // ─── Init ─────────────────────────────────────────────────────────────────

  void init() {
    _startHandshakeListener();
    if (preFilledPartnerUid != null) {
      _update(stateNotifier.value.copyWith(
        receiverId: preFilledPartnerUid,
        receiverUsername: preFilledPartnerUsername ?? 'Partner',
      ));
    }
    _progressSub = _progressCtrl.stream.listen((p) {
      _update(stateNotifier.value.copyWith(encryptionProgress: p));
    });
  }

  // ─── Convenience getters on current state ─────────────────────────────────

  SenderState get state => stateNotifier.value;

  String? get handshakeDocId => _handshakeDocId;

  // ─── State mutation ───────────────────────────────────────────────────────

  void _update(SenderState next) {
    if (_disposed) return;
    stateNotifier.value = next;
  }

  // ─── Handshake stream ─────────────────────────────────────────────────────

  void _startHandshakeListener() {
    _handshakeSub = connService.streamHandshakesForSender().listen(
      _onHandshakeUpdate,
      onError: (error) {
        onError('Stream error: $error', duration: const Duration(seconds: 5));
      },
    );
  }

  void _onHandshakeUpdate(QuerySnapshot<Map<String, dynamic>> snap) {
    if (_disposed) return;
    final s = state;

    // Once paired with a specific receiver, only process their doc.
    // Before pairing (discovery mode), accept the first doc in the snapshot.
    final knownReceiverId = s.receiverId ?? preFilledPartnerUid;
    final relevantDocs = knownReceiverId != null
        ? snap.docs
            .where((d) =>
                (d.data()['receiverId'] as String?) == knownReceiverId)
            .toList()
        : snap.docs;

    if (relevantDocs.isEmpty) {
      // CR-01: skip the first empty snapshot (Firestore stream fires synchronously
      // on subscription before any data has loaded — treat it as settled and return).
      if (!_streamSettled) {
        _streamSettled = true;
        return;
      }
      // Don't wipe mid-encryption — let the compute() isolate finish.
      if (s.encrypting || s.encryptingKey) return;
      _readinessTimer?.cancel();
      _readinessTimer = null;
      _ejectToHomeScreenInternal();
      return;
    } else {
      final docId = relevantDocs.first.id;
      final doc = relevantDocs.first.data();
      final receiverId = doc['receiverId'] as String? ?? '';
      final receiverUsername = doc['receiverUsername'] as String?
          ?? doc['fromUsername'] as String?
          ?? 'Unknown';
      final publicKey = doc['publicKey'] as String?;
      final status = doc['status'] as String? ?? '';

      // Role validation: verify senderUid matches current user if assigned
      final assignedSenderUid = doc['senderUid'] as String?;
      if (assignedSenderUid != null && assignedSenderUid.isNotEmpty) {
        final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
        if (assignedSenderUid != currentUid) {
          revertToWaiting();
          onError('Role conflict — partner also chose Sender. Go back and pick again.');
          return;
        }
      }

      if (publicKey != null &&
          publicKey.isNotEmpty &&
          status == 'handshake_complete' &&
          receiverId.isNotEmpty) {
        if (_handshakeDocId == null || _handshakeDocId!.isEmpty) {
          _handshakeDocId = docId;
        }
        final previousPublicKey = _selectedReceiverPublicKeyJson;
        final isReconnect = _everConnected && _selectedReceiverPublicKeyJson == null;
        _selectedReceiverPublicKeyJson = publicKey;
        _update(state.copyWith(
          receiverId: receiverId,
          receiverUsername: receiverUsername,
        ));
        _streamSettled = true;
        _everConnected = true;
        if (publicKey != previousPublicKey || s.tofuStatus == null) {
          _checkTofuStatus(receiverId, publicKey);
        }

        if (isReconnect) {
          onSuccess('Connection re-established with @$receiverUsername — new RSA key received.');
        }

        // Skip stale-key check if encryption is already in flight.
        if (state.encrypting || state.encryptingKey) return;

        // Receiver's public key rotated after we already encrypted — wipe stale AES key.
        if (previousPublicKey != null &&
            publicKey != previousPublicKey &&
            state.encryptedAESKey != null) {
          wipeSensitiveData();
          onError('Receiver key changed — re-encrypt required.',
              duration: const Duration(seconds: 6), clear: true);
        }

        // Parse receiverReady from handshake doc
        final receiverReady = doc['receiverReady'] as bool? ?? false;

        if (state.receiverSelected && !state.receiverReady && _readinessTimer == null) {
          _startReadinessTimer();
        }

        if (!state.receiverReady && receiverReady) {
          _onReceiverBecameReady();
        } else if (state.receiverReady != receiverReady) {
          if (state.encrypting || state.encryptingKey) return;
          revertToWaiting();
          onInfo('Receiver closed their mailbox — waiting for confirmation.');
        }
      }
    }
  }

  // ─── revertToWaiting ──────────────────────────────────────────────────────

  void revertToWaiting() {
    _readinessTimer?.cancel();
    _readinessTimer = null;
    wipeSensitiveData();
    _selectedReceiverPublicKeyJson = null;
    _streamSettled = false; // CR-01: allow next reconnect to re-settle
    _update(state.copyWith(
      // Preserve pre-fill so the sender stays targeted at the intended partner
      // after the receiver temporarily closes their session (WR-07 fix).
      receiverId: preFilledPartnerUid,
      receiverUsername: preFilledPartnerUsername ?? 'Partner',
      file: null,
      encryptedAESKey: null,
      encrypting: false,
      encryptingKey: false,
      receiverReady: false,
      secondsRemaining: 60,
      timerRunning: false,
      tofuStatus: null,
      receiverFingerprint: null,
    ));
    // Only restart the timer if we have a known receiver to wait for.
    if (state.receiverId != null) {
      _startReadinessTimer();
    }
  }

  // ─── pickFile ─────────────────────────────────────────────────────────────

  Future<void> pickFile() async {
    wipeSensitiveData();
    try {
      final result = await FilePicker.pickFiles(withData: kIsWeb);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.size > FirebaseConstants.maxDownloadBytes) {
        onError(
          'File too large — maximum is 100 MB '
          '(${(file.size / (1024 * 1024)).toStringAsFixed(1)} MB selected)',
        );
        return;
      }
      if (!kIsWeb && file.path == null) {
        onError("This file type isn't supported — try saving it locally first.");
        return;
      }
      _update(state.copyWith(
        file: file,
        encryptedBytes: null,
        aesKey: null,
        iv: null,
        encryptedAESKey: null,
      ));
    } catch (e) {
      onError('Could not open file picker: $e');
    }
  }

  // ─── encryptFile ──────────────────────────────────────────────────────────

  Future<void> encryptFile() async {
    final file = state.file;
    if (file == null) return;
    _update(state.copyWith(encrypting: true, encryptionProgress: 0.0));

    if (!await SecurityLifecycleMixin.isFlagSecureActive()) {
      if (_disposed) return;
      _update(state.copyWith(encrypting: false));
      onError('Screen is not protected. Cannot process file on an unsecured window.');
      return;
    }

    try {
      // ── Phase 1: read file (0 → 70%) ────────────────────────────────
      Uint8List plaintext;
      if (!kIsWeb && file.path != null && file.path!.isNotEmpty) {
        plaintext = await TransferService.readFileWithProgress(
          file.path!,
          (p) => _progressCtrl.add(p * 0.7), // 0 → 70%
        );
      } else {
        plaintext = file.bytes ?? Uint8List(0);
        _progressCtrl.add(0.7);
      }
      onRegisterBuffer(plaintext);

      // ── Phase 2: AES-256-GCM in compute() isolate (70 → 100%) ───────
      final result = await EncryptionService.encryptAesGcm(plaintext);
      onRegisterBuffer(result.key);
      onRegisterBuffer(result.iv);
      onRegisterBuffer(result.ciphertext);
      _progressCtrl.add(1.0);

      plaintext.fillRange(0, plaintext.length, 0);
      onUnregisterBuffer(plaintext);

      if (_disposed) return;
      _update(state.copyWith(
        aesKey: result.key,
        iv: result.iv,
        encryptedBytes: result.ciphertext,
        encryptedAESKey: null,
        encrypting: false,
      ));
    } catch (e) {
      if (_disposed) return;
      _update(state.copyWith(encrypting: false));
      onError('Encryption failed: $e');
    }
  }

  // ─── encryptAesKey ────────────────────────────────────────────────────────

  Future<void> encryptAesKey(
    Future<bool> Function(String prompt) biometricAuthenticate,
  ) async {
    if (state.encryptingKey) return;
    final aesKey = state.aesKey;
    final publicKeyJson = _selectedReceiverPublicKeyJson;
    final receiverId = state.receiverId;
    if (aesKey == null) {
      onError('Encrypt the file first (Step 2).');
      return;
    }
    if (publicKeyJson == null || receiverId == null) {
      onError('Select a receiver first (Step 0).');
      return;
    }

    // Pre-emptive freshness check: confirm the cached public key is still live
    // in Firestore before showing the biometric prompt.
    try {
      final liveKey = await connService.fetchHandshakePublicKey(receiverId);
      if (_disposed) return;
      if (liveKey == null || liveKey != publicKeyJson) {
        wipeSensitiveData();
        final msg = liveKey == null
            ? 'Session ended — receiver closed their mailbox.'
            : 'Receiver key changed — re-encrypt required.';
        // Write audit log then request navigation
        await _writeAbortAuditLog(
          receiverId: receiverId,
          receiverUsername: state.receiverUsername ?? 'Unknown',
        );
        onAbortNavigate(msg);
        return;
      }
    } catch (_) {
      if (_disposed) return;
      onError('Could not verify receiver key. Please try again.');
      return;
    }

    _update(state.copyWith(encryptingKey: true));
    final ok = await biometricAuthenticate(
        'Authenticate to encrypt the AES key for '
        '${state.receiverUsername ?? "receiver"}');
    if (_disposed) return;
    if (!ok) {
      _update(state.copyWith(encryptingKey: false));
      onError('Authentication failed or was cancelled. Tap to retry.');
      return;
    }
    try {
      final encryptedAESKey = await compute(
        _rsaOaepEncryptIsolate,
        [publicKeyJson, aesKey],
      );
      if (_disposed) return;
      onRegisterBuffer(encryptedAESKey);
      _update(state.copyWith(
        encryptedAESKey: encryptedAESKey,
        encryptingKey: false,
      ));
    } catch (e) {
      if (_disposed) return;
      _update(state.copyWith(encryptingKey: false));
      onError('RSA encryption failed: $e');
    }
  }

  // ─── buildSendArgs ────────────────────────────────────────────────────────

  /// Returns all data needed for [SenderTransferScreen] navigation, or null if
  /// any required field is missing (widget should guard against null).
  ({
    String transferId,
    Uint8List encryptedBytesCopy,
    String fileName,
    int fileSize,
    String receiverUsername,
    String receiverId,
    String senderId,
    String encryptedAESKeyB64,
    String ivB64,
  })? buildSendArgs() {
    final s = state;
    final file = s.file;
    final encryptedBytes = s.encryptedBytes;
    final encryptedAESKey = s.encryptedAESKey;
    final iv = s.iv;
    final receiverId = s.receiverId;
    final receiverUsername = s.receiverUsername;
    final senderId = FirebaseAuth.instance.currentUser?.uid;

    if (file == null ||
        encryptedBytes == null ||
        encryptedAESKey == null ||
        iv == null ||
        receiverId == null ||
        receiverUsername == null ||
        senderId == null) {
      return null;
    }

    final transferId = transferRepo.generateId();
    final encryptedAESKeyB64 = base64Encode(encryptedAESKey);
    final ivB64 = base64Encode(iv);
    final encryptedBytesCopy = Uint8List.fromList(encryptedBytes);

    wipeSensitiveData();

    return (
      transferId: transferId,
      encryptedBytesCopy: encryptedBytesCopy,
      fileName: file.name,
      fileSize: file.size,
      receiverUsername: receiverUsername,
      receiverId: receiverId,
      senderId: senderId,
      encryptedAESKeyB64: encryptedAESKeyB64,
      ivB64: ivB64,
    );
  }

  // ─── wipeSensitiveData ────────────────────────────────────────────────────

  void wipeSensitiveData() {
    state.aesKey?.fillRange(0, state.aesKey!.length, 0);
    state.iv?.fillRange(0, state.iv!.length, 0);
    state.encryptedBytes?.fillRange(0, state.encryptedBytes!.length, 0);
    _update(state.copyWith(
      aesKey: null,
      iv: null,
      encryptedBytes: null,
      encryptedAESKey: null,
    ));
    onBuffersWipe();
  }

  // ─── Readiness timer ──────────────────────────────────────────────────────

  void _startReadinessTimer() {
    _update(state.copyWith(secondsRemaining: 60, timerRunning: true));
    _readinessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.secondsRemaining - 1;
      _update(state.copyWith(secondsRemaining: remaining));
      if (remaining == 10) {
        onInfo('Receiver not ready — session closing in 10 seconds.');
      }
      if (remaining <= 0) {
        _readinessTimer?.cancel();
        _readinessTimer = null;
        _update(state.copyWith(timerRunning: false));
        _ejectToHomeScreenInternal();
      }
    });
  }

  void _onReceiverBecameReady() {
    _readinessTimer?.cancel();
    _readinessTimer = null;
    _update(state.copyWith(receiverReady: true, timerRunning: false));
    onSuccess('Secure channel established. Receiver is ready.');
  }

  // ─── Eject ────────────────────────────────────────────────────────────────

  void _ejectToHomeScreenInternal() {
    wipeSensitiveData();
    onEject();
  }

  // ─── Abort audit log ──────────────────────────────────────────────────────

  Future<void> _writeAbortAuditLog({
    required String receiverId,
    required String receiverUsername,
  }) async {
    final senderId = FirebaseAuth.instance.currentUser?.uid;
    final senderUsername = FirebaseAuth.instance.currentUser?.displayName ?? '';
    final fileName = state.file?.name ?? '';
    final fileSize = state.file?.size ?? 0;
    if (senderId != null && fileName.isNotEmpty) {
      try {
        await transferRepo.writeAbortAuditLog(
          senderId: senderId,
          receiverId: receiverId,
          senderUsername: senderUsername,
          receiverUsername: receiverUsername,
          fileName: fileName,
          fileSize: fileSize,
        );
      } catch (_) {
        // Best-effort — don't block navigation on a log write failure.
      }
    }
  }

  // ─── TOFU ─────────────────────────────────────────────────────────────────

  Future<void> _checkTofuStatus(String receiverUid, String publicKeyJson) async {
    final status = await TofuService.check(receiverUid, publicKeyJson);
    if (status == TofuStatus.firstContact) {
      await TofuService.pin(receiverUid, publicKeyJson);
    }
    if (_disposed) return;
    if (status == TofuStatus.keyChanged) {
      _update(state.copyWith(tofuStatus: TofuStatus.keyChanged));
      onKeyChanged(receiverUid, publicKeyJson);
    } else {
      final fp = TofuService.displayFingerprint(publicKeyJson);
      _update(state.copyWith(tofuStatus: status, receiverFingerprint: fp));
    }
  }

  /// Called by the widget when the user confirms a changed TOFU key in the
  /// dialog (both repin and markVerified have already been called by the widget).
  void onTofuKeyConfirmed(String fingerprint) {
    _update(state.copyWith(
      tofuStatus: TofuStatus.verified,
      receiverFingerprint: fingerprint,
    ));
  }

  /// Called by the widget when the user confirms identity in the verify dialog.
  void onTofuVerified() {
    _update(state.copyWith(tofuStatus: TofuStatus.verified));
  }

  // ─── Dispose ──────────────────────────────────────────────────────────────

  void dispose() {
    _disposed = true;
    _handshakeSub?.cancel();
    _progressSub?.cancel();
    _progressCtrl.close();
    _readinessTimer?.cancel();
    // If sender leaves before a handshake was created, clearTransferRoles is never
    // called — clear the Firestore claim directly so the partner's Send File unblocks.
    if (_handshakeDocId == null) {
      connService.clearSenderClaim();
    }
    stateNotifier.dispose();
  }
}
