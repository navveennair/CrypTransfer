import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pointycastle/export.dart' hide State, Padding;

import '../../core/utils/biometric_helper.dart';
import '../../data/repositories/key_repository.dart';
import '../../core/utils/security_lifecycle_mixin.dart';
import '../../data/services/transfer_service.dart';
import '../widgets/shared_widgets.dart';
import 'transfer_progress_screen.dart';

// ─── Isolate-safe AES-256-GCM encrypt ────────────────────────────────────────
// Must be a top-level function for Flutter compute().

Uint8List _runAesGcm(List<Uint8List> args) {
  final plaintext = args[0];
  final key = args[1];
  final iv = args[2];
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
  return cipher.process(plaintext);
}

// ─── Widget ──────────────────────────────────────────────────────────────────

class SenderScreen extends StatefulWidget {
  const SenderScreen({super.key});

  @override
  State<SenderScreen> createState() => _SenderScreenState();
}

class _SenderScreenState extends State<SenderScreen>
    with SecurityLifecycleMixin<SenderScreen> {
  final _connService = KeyRepository();

  // Step 0 — Receiver-Authorized connection (reactive stream)
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _handshakeSub;
  String? _selectedReceiverPublicKeyJson;

  // Step 1 — File
  PlatformFile? _file;

  // Step 2 — Crypto
  Uint8List? _encryptedBytes;
  Uint8List? _aesKey;
  Uint8List? _iv;

  // Step 3 — Receiver + RSA-encrypted AES key
  String? _receiverId;
  String? _receiverUsername;
  Uint8List? _encryptedAESKey;

  // UI flags
  bool _encrypting = false;
  bool _encryptingKey = false;

  bool get _receiverSelected => _receiverId != null;
  bool get _fileSelected => _file != null;
  bool get _fileEncrypted => _encryptedBytes != null;
  bool get _readyToSend => _encryptedAESKey != null;

  @override
  void initState() {
    super.initState();
    _startHandshakeListener();
  }

  @override
  void dispose() {
    _handshakeSub?.cancel();
    super.dispose(); // SecurityLifecycleMixin.dispose() → wipeAll()
  }

  // ─── Step 0: Receiver-Authorized connection ───────────────────────────────

  /// Subscribes to [rsa_key_transfers] docs where this sender is the
  /// recipient and the status is `handshake_complete`.
  ///
  /// When a doc appears the receiver has explicitly authorized this sender
  /// and published their RSA public key — the session unlocks automatically.
  ///
  /// When the doc disappears (receiver closes session / kill switch fires),
  /// [_revertToWaiting] is called: sensitive data is wiped and the UI
  /// reverts to the "Waiting for Secure Connection…" buffer.
  void _startHandshakeListener() {
    _handshakeSub =
        _connService.streamHandshakesForSender().listen(_onHandshakeUpdate);
  }

  void _onHandshakeUpdate(
      QuerySnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;
    if (snap.docs.isEmpty) {
      final wasConnected = _receiverId != null;
      _revertToWaiting();
      if (wasConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Secure connection closed by receiver.'),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      }
    } else {
      final doc = snap.docs.first.data();
      final fromUserId = doc['fromUserId'] as String? ?? '';
      final fromUsername = doc['fromUsername'] as String? ?? 'Unknown';
      final publicKey = doc['publicKey'] as String?;
      if (publicKey != null &&
          publicKey.isNotEmpty &&
          fromUserId.isNotEmpty) {
        setState(() {
          _receiverId = fromUserId;
          _receiverUsername = fromUsername;
          _selectedReceiverPublicKeyJson = publicKey;
        });
      }
    }
  }

  /// Wipes all in-progress sensitive data and reverts Step 0 to the waiting
  /// buffer.  Called when the receiver closes their session or fires the kill
  /// switch (stream emits an empty snapshot).
  void _revertToWaiting() {
    _wipeSensitiveData(); // zeroes aesKey/iv/encryptedBytes + wipeAll()
    if (mounted) {
      setState(() {
        _receiverId = null;
        _receiverUsername = null;
        _selectedReceiverPublicKeyJson = null;
        _file = null;
        _encryptedAESKey = null;
        _encrypting = false;
        _encryptingKey = false;
      });
    }
  }

  // ─── Step 1: File picker ─────────────────────────────────────────────────

  Future<void> _pickFile() async {
    _wipeSensitiveData();
    try {
      final result = await FilePicker.pickFiles(withData: true);
      if (result == null || result.files.isEmpty) return;
      setState(() {
        _file = result.files.first;
        _encryptedBytes = null;
        _aesKey = null;
        _iv = null;
        _encryptedAESKey = null;
      });
    } catch (e) {
      if (mounted) _showError('Could not open file picker: $e');
    }
  }

  // ─── Step 2: AES-256-GCM encrypt ─────────────────────────────────────────

  Future<void> _encryptFile() async {
    final file = _file;
    if (file == null || file.bytes == null) return;
    setState(() => _encrypting = true);

    try {
      final key = _secureBytes(32); // 256-bit AES key
      final iv = _secureBytes(12);  // 96-bit GCM nonce
      registerBuffer(key);
      registerBuffer(iv);

      // Kotlin sync: confirm FLAG_SECURE is active before sensitive bytes
      // enter the Dart heap.  Fails open (returns true) on non-Android
      // platforms and in test environments.
      if (!await SecurityLifecycleMixin.isFlagSecureActive()) {
        if (mounted) {
          _showError(
            'Screen is not protected (FLAG_SECURE inactive). '
            'Cannot process file on an unsecured window.',
          );
        }
        return;
      }

      // Read in 64 KB chunks on mobile/desktop; fall back to in-memory bytes on web.
      final plaintext = await TransferService.resolve(
        filePath: file.path,
        fallbackBytes: file.bytes,
      );
      // Register plaintext immediately so wipeAll/dispose zeroes it if anything
      // throws before we reach the explicit wipe below.
      registerBuffer(plaintext);

      final encrypted = await compute(_runAesGcm, [plaintext, key, iv]);
      registerBuffer(encrypted);

      // Explicit zero-wipe: erase the main-isolate plaintext buffer now that
      // compute() has finished.  compute() serialised a copy into the child
      // isolate — this zeroes the reference we still hold on the main heap.
      // unregisterBuffer removes it from the wipeAll list so there is no
      // redundant second pass over already-zero memory.
      plaintext.fillRange(0, plaintext.length, 0);
      unregisterBuffer(plaintext);

      if (mounted) {
        setState(() {
          _aesKey = key;
          _iv = iv;
          _encryptedBytes = encrypted;
          _encryptedAESKey = null;
          _encrypting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _encrypting = false);
        _showError('Encryption failed: $e');
      }
    }
  }

  Uint8List _secureBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }

  // ─── Step 3: RSA-OAEP encrypt AES key ────────────────────────────────────

  Future<void> _encryptAesKey() async {
    final aesKey = _aesKey;
    final publicKeyJson = _selectedReceiverPublicKeyJson;
    if (aesKey == null) {
      _showError('Encrypt the file first (Step 2).');
      return;
    }
    if (publicKeyJson == null) {
      _showError('Select a receiver first (Step 0).');
      return;
    }

    final ok = await BiometricHelper.authenticate(
        'Authenticate to encrypt the AES key for '
        '${_receiverUsername ?? "receiver"}');
    if (!ok || !mounted) return;

    setState(() => _encryptingKey = true);
    try {
      final rsaKey = _decodePublicKey(publicKeyJson);
      final encryptedAESKey = _rsaOaepEncrypt(aesKey, rsaKey);
      registerBuffer(encryptedAESKey);
      if (mounted) {
        setState(() {
          _encryptedAESKey = encryptedAESKey;
          _encryptingKey = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _encryptingKey = false);
        _showError('RSA encryption failed: $e');
      }
    }
  }

  RSAPublicKey _decodePublicKey(String encoded) {
    final map = jsonDecode(encoded) as Map<String, dynamic>;
    return RSAPublicKey(
      BigInt.parse(map['modulus'] as String, radix: 16),
      BigInt.parse(map['exponent'] as String, radix: 16),
    );
  }

  Uint8List _rsaOaepEncrypt(Uint8List data, RSAPublicKey publicKey) {
    final cipher = OAEPEncoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
    return cipher.process(data);
  }

  // ─── Step 4: Send ─────────────────────────────────────────────────────────

  void _send() {
    final file = _file;
    final encryptedBytes = _encryptedBytes;
    final encryptedAESKey = _encryptedAESKey;
    final iv = _iv;
    final receiverId = _receiverId;
    final receiverUsername = _receiverUsername;
    final senderId = FirebaseAuth.instance.currentUser?.uid;

    if (file == null ||
        encryptedBytes == null ||
        encryptedAESKey == null ||
        iv == null ||
        receiverId == null ||
        receiverUsername == null ||
        senderId == null) {
      return;
    }

    final transferId =
        FirebaseFirestore.instance.collection('transfers').doc().id;

    // Encode b64 strings before the wipe — once wiped these are unreadable.
    final encryptedAESKeyB64 = base64Encode(encryptedAESKey);
    final ivB64 = base64Encode(iv);
    // Defensive copy so TransferProgressScreen owns its own buffer.
    final encryptedBytesCopy = Uint8List.fromList(encryptedBytes);

    // Wipe all originals now — sender screen no longer holds key material.
    _wipeSensitiveData();

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, _) => TransferProgressScreen(
          transferId: transferId,
          encryptedBytes: encryptedBytesCopy,
          fileName: file.name,
          fileSize: file.size,
          receiverUsername: receiverUsername,
          receiverId: receiverId,
          senderId: senderId,
          encryptedAESKeyB64: encryptedAESKeyB64,
          ivB64: ivB64,
          // aesKey intentionally omitted — already wiped above.
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  void _wipeSensitiveData() {
    _aesKey?.fillRange(0, _aesKey!.length, 0);
    _iv?.fillRange(0, _iv!.length, 0);
    _encryptedBytes?.fillRange(0, _encryptedBytes!.length, 0);
    _aesKey = null;
    _iv = null;
    _encryptedBytes = null;

    // Unregister old buffers and clear
    wipeAll();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_encrypting && !_encryptingKey,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _wipeSensitiveData();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text('Send File',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Step 0: Receiver-Authorized Connection ──────────────────
            StepCard(
              step: 0,
              title: 'Secure Connection',
              done: _receiverSelected,
              child: _receiverSelected
                  ? _ConnectedBadge(username: _receiverUsername!)
                  : const _WaitingForConnectionWidget(),
            ),
            const SizedBox(height: 16),

            // ── Step 1: Select File ─────────────────────────────────────
            AnimatedOpacity(
              opacity: _receiverSelected ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 300),
              child: StepCard(
                step: 1,
                title: 'Select File',
                done: _fileSelected,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open_rounded),
                      label: Text(
                          _file == null ? 'Browse Files' : 'Change File'),
                      onPressed: _receiverSelected ? _pickFile : null,
                    ),
                    if (_file != null) ...[
                      const SizedBox(height: 12),
                      _FileCard(file: _file!),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Step 2: Encrypt ─────────────────────────────────────────
            AnimatedOpacity(
              opacity: _fileSelected ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 300),
              child: StepCard(
                step: 2,
                title: 'Encrypt File (AES-256-GCM)',
                done: _fileEncrypted,
                child: _fileEncrypted
                    ? _EncryptedBadge(
                        keyBits: _aesKey!.length * 8,
                        ivBytes: _iv!.length,
                        ciphertextBytes: _encryptedBytes!.length,
                      )
                    : CrypButton(
                        icon: _encrypting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.lock_rounded),
                        label: Text(_encrypting
                            ? 'Encrypting…'
                            : 'Generate AES Key & Encrypt'),
                        onPressed:
                            _fileSelected && !_encrypting ? _encryptFile : null,
                        color: Theme.of(context).colorScheme.secondary,
                        disabledColor: Theme.of(context).colorScheme.secondary,
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Step 3: RSA Key Manager ─────────────────────────────────
            AnimatedOpacity(
              opacity: _fileEncrypted ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 300),
              child: StepCard(
                step: 3,
                title: 'RSA Key Manager',
                done: _readyToSend,
                child: _readyToSend
                    ? _ReceiverBadge(username: _receiverUsername!)
                    : CrypButton(
                        icon: _encryptingKey
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.manage_accounts_rounded),
                        label: Text(_encryptingKey
                            ? 'Encrypting key…'
                            : 'Encrypt AES Key for '
                                '@${_receiverUsername ?? "receiver"}'),
                        onPressed: _fileEncrypted && !_encryptingKey
                            ? _encryptAesKey
                            : null,
                        color: Theme.of(context).colorScheme.tertiary,
                        disabledColor: Theme.of(context).colorScheme.tertiary,
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Step 4: Send ────────────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: _readyToSend
                  ? CrypButton(
                      key: const ValueKey('send-btn'),
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Send Encrypted File'),
                      onPressed: _send,
                      color: Colors.green.shade600,
                    )
                  : const SizedBox.shrink(key: ValueKey('send-empty')),
            ),
          ],
        ),
      ),
      ), // closes Scaffold
    ); // closes PopScope
  }
}

// ─── Step 0: Waiting for receiver authorization ───────────────────────────────
// Shown when no receiver has selected this sender yet.

class _WaitingForConnectionWidget extends StatefulWidget {
  const _WaitingForConnectionWidget();

  @override
  State<_WaitingForConnectionWidget> createState() =>
      _WaitingForConnectionWidgetState();
}

class _WaitingForConnectionWidgetState
    extends State<_WaitingForConnectionWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: 8),
        ScaleTransition(
          scale: _scale,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primaryContainer.withValues(alpha: 0.6),
            ),
            child: Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: cs.primary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Waiting for Secure Connection…',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'A receiver must select you as their sender\nbefore file transfer can begin.',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Step 0: Receiver connected badge ────────────────────────────────────────
// Shown once a receiver has authorized this sender via the handshake.

class _ConnectedBadge extends StatelessWidget {
  final String username;

  const _ConnectedBadge({required this.username});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lock_open_rounded,
                color: Colors.green.shade700, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Secure Channel Established',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.green.shade800),
                ),
                const SizedBox(height: 2),
                Text(
                  'Key received from @$username',
                  style: TextStyle(
                      fontSize: 12, color: Colors.green.shade700),
                ),
              ],
            ),
          ),
          Icon(Icons.verified_rounded,
              color: Colors.green.shade600, size: 22),
        ],
      ),
    );
  }
}

// ─── File card ────────────────────────────────────────────────────────────────

class _FileCard extends StatelessWidget {
  final PlatformFile file;

  const _FileCard({required this.file});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ext = (file.extension ?? '').toLowerCase();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _extColor(ext).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_extIcon(ext), color: _extColor(ext), size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _fmtSize(file.size),
                  style:
                      TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _extIcon(String ext) {
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
      return Icons.image_rounded;
    }
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) {
      return Icons.video_file_rounded;
    }
    if (['mp3', 'wav', 'flac', 'aac', 'm4a'].contains(ext)) {
      return Icons.audio_file_rounded;
    }
    if (ext == 'pdf') return Icons.picture_as_pdf_rounded;
    if (['doc', 'docx'].contains(ext)) return Icons.description_rounded;
    if (['xls', 'xlsx'].contains(ext)) return Icons.table_chart_rounded;
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      return Icons.folder_zip_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  Color _extColor(String ext) {
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
      return Colors.blue;
    }
    if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) return Colors.purple;
    if (['mp3', 'wav', 'flac'].contains(ext)) return Colors.orange;
    if (ext == 'pdf') return Colors.red;
    if (['doc', 'docx'].contains(ext)) return Colors.blue.shade700;
    if (['xls', 'xlsx'].contains(ext)) return Colors.green;
    if (['zip', 'rar', '7z'].contains(ext)) return Colors.brown;
    return Colors.grey;
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ─── Encrypted badge ──────────────────────────────────────────────────────────

class _EncryptedBadge extends StatelessWidget {
  final int keyBits;
  final int ivBytes;
  final int ciphertextBytes;

  const _EncryptedBadge({
    required this.keyBits,
    required this.ivBytes,
    required this.ciphertextBytes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: Colors.green.shade700, size: 18),
              const SizedBox(width: 8),
              Text('AES-256-GCM encrypted',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade800)),
            ],
          ),
          const SizedBox(height: 8),
          _Row('Key', '$keyBits bits'),
          _Row('IV (nonce)', '$ivBytes bytes'),
          _Row('Ciphertext', '${_fmtSize(ciphertextBytes)} + 16 B auth tag'),
        ],
      ),
    );
  }

  String _fmtSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  TextStyle(fontSize: 12, color: Colors.green.shade700)),
          Text(value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ─── Receiver badge (Step 3 done state) ──────────────────────────────────────

class _ReceiverBadge extends StatelessWidget {
  final String username;

  const _ReceiverBadge({required this.username});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.deepPurple.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.person_rounded,
              color: Colors.deepPurple.shade700, size: 18),
          const SizedBox(width: 8),
          Text('Encrypting for ',
              style:
                  TextStyle(fontSize: 13, color: Colors.deepPurple.shade700)),
          Text('@$username',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.deepPurple.shade700)),
          const Spacer(),
          Icon(Icons.check_circle_rounded,
              color: Colors.deepPurple.shade600, size: 18),
        ],
      ),
    );
  }
}
