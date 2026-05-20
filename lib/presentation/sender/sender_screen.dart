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

import '../../app_theme.dart';
import '../../core/utils/biometric_helper.dart';
import '../../data/repositories/key_repository.dart';
import '../../core/utils/security_lifecycle_mixin.dart';
import '../../data/services/transfer_service.dart';
import '../home/home_screen.dart';
import '../widgets/shared_widgets.dart';
import 'transfer_progress_screen.dart';

// ─── Isolate-safe AES-256-GCM encrypt ────────────────────────────────────────

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
  final String? preFilledPartnerUid;
  final String? preFilledPartnerUsername;

  const SenderScreen({
    super.key,
    this.preFilledPartnerUid,
    this.preFilledPartnerUsername,
  });

  @override
  State<SenderScreen> createState() => _SenderScreenState();
}

class _SenderScreenState extends State<SenderScreen>
    with SecurityLifecycleMixin<SenderScreen> {
  final _connService = KeyRepository();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _handshakeSub;
  String? _selectedReceiverPublicKeyJson;

  PlatformFile? _file;

  Uint8List? _encryptedBytes;
  Uint8List? _aesKey;
  Uint8List? _iv;

  String? _receiverId;
  String? _receiverUsername;
  Uint8List? _encryptedAESKey;

  bool _encrypting = false;
  bool _encryptingKey = false;
  double _encryptionProgress = 0.0;

  // Broadcast stream so the progress indicator always gets the latest value.
  final _progressCtrl = StreamController<double>.broadcast();
  StreamSubscription<double>? _progressSub;

  bool get _receiverSelected => _receiverId != null;
  bool get _fileSelected => _file != null;
  bool get _fileEncrypted => _encryptedBytes != null;
  bool get _readyToSend => _encryptedAESKey != null;

  // Phase 6 — receiver readiness gate
  bool _receiverReady = false;
  Timer? _readinessTimer;
  int _secondsRemaining = 60;
  bool _streamSettled = false;   // CR-01: suppress cold-start empty-snapshot eject

  @override
  void initState() {
    super.initState();
    _startHandshakeListener();
    if (widget.preFilledPartnerUid != null) {
      // Pre-fill from Active Connection role picker (D-13):
      // partner UID is already known; skip _FindSenderSheet.
      // The handshake stream still runs so the RSA key arrives
      // reactively when the partner opens ReceiverScreen.
      setState(() {
        _receiverId = widget.preFilledPartnerUid;
        _receiverUsername = widget.preFilledPartnerUsername ?? 'Partner';
      });
    }
    _progressSub = _progressCtrl.stream.listen((p) {
      if (mounted) setState(() => _encryptionProgress = p);
    });
  }

  @override
  void dispose() {
    _handshakeSub?.cancel();
    _progressSub?.cancel();
    _progressCtrl.close();
    _readinessTimer?.cancel();
    super.dispose();
  }

  void _startHandshakeListener() {
    _handshakeSub =
        _connService.streamHandshakesForSender().listen(_onHandshakeUpdate);
  }

  void _onHandshakeUpdate(
      QuerySnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;
    if (snap.docs.isEmpty) {
      // CR-01: skip the first empty snapshot (Firestore stream fires synchronously
      // on subscription before any data has loaded — treat it as settled and return).
      if (!_streamSettled) {
        _streamSettled = true;
        return;
      }
      // Phase 6: eject sender if waiting for readiness and session collapses (D-09)
      if (!_receiverReady) {
        _readinessTimer?.cancel();
        _readinessTimer = null;
        _ejectToHomeScreen();
        return;
      }
      final wasConnected = _receiverId != null;
      _revertToWaiting();
      if (wasConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Secure connection closed by receiver.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else {
      final doc = snap.docs.first.data();
      final receiverId = doc['receiverId'] as String? ?? '';
      // 'receiverUsername' is the canonical field (written by updated key_repository).
      // Fall back to legacy 'fromUsername' for documents created before this fix.
      final receiverUsername = doc['receiverUsername'] as String?
          ?? doc['fromUsername'] as String?
          ?? 'Unknown';
      final publicKey = doc['publicKey'] as String?;
      if (publicKey != null &&
          publicKey.isNotEmpty &&
          receiverId.isNotEmpty &&
          (widget.preFilledPartnerUid == null ||
           receiverId == widget.preFilledPartnerUid)) {
        setState(() {
          _receiverId = receiverId;
          _receiverUsername = receiverUsername;
          _selectedReceiverPublicKeyJson = publicKey;
        });
        _streamSettled = true;   // CR-01: stream has produced a non-empty doc; cold-start phase over

        // Phase 6: parse receiverReady field and gate/unlock steps (D-06)
        final receiverReady = doc['receiverReady'] as bool? ?? false;

        if (_receiverSelected && !_receiverReady && _readinessTimer == null) {
          _startReadinessTimer();
        }

        if (!_receiverReady && receiverReady) {
          _onReceiverBecameReady();
        } else if (_receiverReady != receiverReady) {
          // WR-03: receiverReady reverted to false after gate was unlocked.
          // Simply setting the flag leaves the timer cancelled and the countdown
          // frozen. _revertToWaiting() resets _receiverReady, _secondsRemaining,
          // cancels any lingering timer, and wipes sensitive data.
          _revertToWaiting();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Receiver readiness was reset — waiting for confirmation.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    }
  }

  void _revertToWaiting() {
    _readinessTimer?.cancel();  // Phase 6 addition
    _readinessTimer = null;     // Phase 6 addition
    _wipeSensitiveData();
    if (mounted) {
      setState(() {
        // Preserve pre-fill so the sender stays targeted at the intended partner
        // after the receiver temporarily closes their session (WR-07 fix).
        _receiverId = widget.preFilledPartnerUid;
        _receiverUsername = widget.preFilledPartnerUsername ?? 'Partner';
        _selectedReceiverPublicKeyJson = null;
        _file = null;
        _encryptedAESKey = null;
        _encrypting = false;
        _encryptingKey = false;
        _receiverReady = false;     // Phase 6 addition
        _secondsRemaining = 60;     // Phase 6 addition
        _streamSettled = false;   // CR-01: allow next reconnect to re-settle
      });
      _startReadinessTimer();
    }
  }

  Future<void> _pickFile() async {
    _wipeSensitiveData();
    try {
      final result = await FilePicker.pickFiles(withData: kIsWeb);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (!kIsWeb && file.path == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("This file type isn't supported — try saving it locally first."),
            ),
          );
        }
        return;
      }
      setState(() {
        _file = file;
        _encryptedBytes = null;
        _aesKey = null;
        _iv = null;
        _encryptedAESKey = null;
      });
    } catch (e) {
      if (mounted) _showError('Could not open file picker: $e');
    }
  }

  Future<void> _encryptFile() async {
    final file = _file;
    if (file == null) return;
    setState(() {
      _encrypting = true;
      _encryptionProgress = 0.0;
    });

    if (!await SecurityLifecycleMixin.isFlagSecureActive()) {
      if (mounted) {
        setState(() => _encrypting = false);
        _showError(
          'Screen is not protected. Cannot process file on an unsecured window.',
        );
      }
      return;
    }

    try {
      final key = _secureBytes(32);
      final iv = _secureBytes(12);
      registerBuffer(key);
      registerBuffer(iv);

      // ── Phase 1: read file (0 → 70%) ────────────────────────────────
      // readFileWithProgress uses explicit 64 KB RandomAccessFile reads,
      // yielding to the event loop between pages so the progress bar animates.
      Uint8List plaintext;
      if (!kIsWeb && file.path != null && file.path!.isNotEmpty) {
        plaintext = await TransferService.readFileWithProgress(
          file.path!,
          (p) => _progressCtrl.add(p * 0.7), // 0 → 70%
        );
      } else {
        // Web fallback: bytes are already in memory, jump straight to encrypt.
        plaintext = file.bytes ?? Uint8List(0);
        _progressCtrl.add(0.7);
      }
      registerBuffer(plaintext);

      // ── Phase 2: AES-256-GCM in compute() isolate (70 → 100%) ───────
      final encrypted = await compute(_runAesGcm, [plaintext, key, iv]);
      registerBuffer(encrypted);
      _progressCtrl.add(1.0); // encryption complete

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

    final encryptedAESKeyB64 = base64Encode(encryptedAESKey);
    final ivB64 = base64Encode(iv);
    final encryptedBytesCopy = Uint8List.fromList(encryptedBytes);

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
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  void _wipeSensitiveData() {
    _aesKey?.fillRange(0, _aesKey!.length, 0);
    _iv?.fillRange(0, _iv!.length, 0);
    _encryptedBytes?.fillRange(0, _encryptedBytes!.length, 0);
    _aesKey = null;
    _iv = null;
    _encryptedBytes = null;
    _encryptedAESKey = null;
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

  void _startReadinessTimer() {
    _secondsRemaining = 60;
    _readinessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsRemaining--);
      if (_secondsRemaining <= 0) {
        _readinessTimer?.cancel();
        _readinessTimer = null;
        _ejectToHomeScreen();
      }
    });
  }

  void _onReceiverBecameReady() {
    _readinessTimer?.cancel();
    _readinessTimer = null;
    setState(() => _receiverReady = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Secure channel established. Receiver is ready.'),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _ejectToHomeScreen() {
    _wipeSensitiveData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Session Terminated — receiver closed the session.'),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => HomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_encrypting && !_encryptingKey,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _wipeSensitiveData();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text('Send File', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Welcome banner ────────────────────────────────
            GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              color: cs.primary.withValues(alpha: 0.1),
              borderColor: cs.primary.withValues(alpha: 0.2),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.send_rounded, color: cs.primary, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'File Transfer',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Securely encrypt and transmit your data.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Step 0: Receiver-Authorized Connection ──────────────────
            StepCard(
              step: 0,
              title: 'Secure Connection',
              done: _receiverSelected && _receiverReady,
              child: _receiverSelected
                  ? (_receiverReady
                      ? _ConnectedBadge(username: _receiverUsername!)
                      : _WaitingForReceiverWidget(secondsRemaining: _secondsRemaining))
                  : const _WaitingForConnectionWidget(),
            ),
            const SizedBox(height: 16),

            // ── Steps 1-4: gated until receiver is ready (Phase 6) ─────
            AnimatedOpacity(
              opacity: _receiverReady ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: IgnorePointer(
                ignoring: !_receiverReady,
                child: Column(
                  children: [
                    // ── Step 1: Select File ───────────────────────────────
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
                            GlassButton(
                              icon: const Icon(Icons.folder_open_rounded, size: 20),
                              label: Text(_file == null ? 'Browse Files' : 'Change File'),
                              onPressed: _receiverSelected ? _pickFile : null,
                              color: cs.primary,
                            ),
                            if (_file != null) ...[
                              const SizedBox(height: 16),
                              _FileCard(file: _file!),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Step 2: Encrypt ───────────────────────────────────
                    AnimatedOpacity(
                      opacity: _fileSelected ? 1.0 : 0.4,
                      duration: const Duration(milliseconds: 300),
                      child: StepCard(
                        step: 2,
                        title: 'AES-256-GCM Encryption',
                        done: _fileEncrypted,
                        child: _fileEncrypted
                            ? _EncryptedBadge(
                                keyBits: _aesKey!.length * 8,
                                ivBytes: _iv!.length,
                                ciphertextBytes: _encryptedBytes!.length,
                              )
                            : _encrypting
                                ? _EncryptionProgressWidget(
                                    progress: _encryptionProgress)
                                : GlassButton(
                                    icon: const Icon(Icons.lock_rounded, size: 20),
                                    label: const Text('Encrypt with AES Key'),
                                    onPressed: _fileSelected ? _encryptFile : null,
                                    color: Colors.amber.shade700,
                                  ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Step 3: RSA Handshake ─────────────────────────────
                    AnimatedOpacity(
                      opacity: _fileEncrypted ? 1.0 : 0.4,
                      duration: const Duration(milliseconds: 300),
                      child: StepCard(
                        step: 3,
                        title: 'RSA Key Handshake',
                        done: _readyToSend,
                        child: _readyToSend
                            ? _ReceiverBadge(username: _receiverUsername!)
                            : GlassButton(
                                icon: _encryptingKey
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.security_rounded, size: 20),
                                label: Text(_encryptingKey
                                    ? 'Encrypting key…'
                                    : 'Encrypt Key for @${_receiverUsername ?? "receiver"}'),
                                onPressed: _fileEncrypted && !_encryptingKey
                                    ? _encryptAesKey
                                    : null,
                                color: cs.secondary,
                              ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Step 4: Send ──────────────────────────────────────
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: _readyToSend
                          ? GlassButton(
                              key: const ValueKey('send-btn'),
                              icon: const Icon(Icons.send_rounded, size: 20, color: Colors.white),
                              label: const Text('Send Encrypted File', style: TextStyle(color: Colors.white)),
                              onPressed: _send,
                              color: Colors.green.shade500,
                            )
                          : const SizedBox.shrink(key: ValueKey('send-empty')),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ─── Encryption progress ─────────────────────────────────────────────────────

class _EncryptionProgressWidget extends StatelessWidget {
  final double progress;
  const _EncryptionProgressWidget({required this.progress});

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).toInt();
    final isReading = progress < 0.7;
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      color: Colors.amber.withValues(alpha: 0.08),
      borderColor: Colors.amber.withValues(alpha: 0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.amber,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                isReading ? 'Reading file… $pct%' : 'Encrypting AES-256-GCM… $pct%',
                style: const TextStyle(fontSize: 13, color: Colors.amber),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.amber.withValues(alpha: 0.15),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}

class _WaitingForConnectionWidget extends StatefulWidget {
  const _WaitingForConnectionWidget();

  @override
  State<_WaitingForConnectionWidget> createState() =>
      _WaitingForConnectionWidgetState();
}

class _WaitingForConnectionWidgetState
    extends State<_WaitingForConnectionWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _fade = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 10),
          ScaleTransition(
            scale: _scale,
            child: FadeTransition(
              opacity: _fade,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withValues(alpha: 0.1),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.2), width: 2),
                ),
                child: Icon(Icons.wifi_tethering_rounded, color: cs.primary, size: 32),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Waiting for Secure Connection…',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'A receiver must authorize you to begin.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _ConnectedBadge extends StatelessWidget {
  final String username;

  const _ConnectedBadge({required this.username});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: Colors.green.withValues(alpha: 0.1),
      borderColor: Colors.green.withValues(alpha: 0.2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_user_rounded,
                color: Colors.green, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connection Verified',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.green),
                ),
                const SizedBox(height: 2),
                Text(
                  'Secure channel open with @$username',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.green),
                ),
              ],
            ),
          ),
          const Icon(Icons.lock_rounded, color: Colors.green, size: 18),
        ],
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  final PlatformFile file;

  const _FileCard({required this.file});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ext = (file.extension ?? '').toLowerCase();

    return GlassContainer(
      padding: const EdgeInsets.all(14),
      color: cs.surface.withValues(alpha: 0.05),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _extColor(ext).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_extIcon(ext), color: _extColor(ext), size: 24),
          ),
          const SizedBox(width: 14),
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
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return Icons.image_rounded;
    if (['mp4', 'mov', 'avi'].contains(ext)) return Icons.video_file_rounded;
    if (['mp3', 'wav', 'flac'].contains(ext)) return Icons.audio_file_rounded;
    if (ext == 'pdf') return Icons.picture_as_pdf_rounded;
    if (['zip', 'rar', '7z'].contains(ext)) return Icons.folder_zip_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _extColor(String ext) {
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return Colors.blue;
    if (['mp4', 'mov', 'avi'].contains(ext)) return Colors.purple;
    if (['mp3', 'wav', 'flac'].contains(ext)) return Colors.orange;
    if (ext == 'pdf') return Colors.red;
    return Colors.grey;
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

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
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      color: Colors.amber.withValues(alpha: 0.08),
      borderColor: Colors.amber.withValues(alpha: 0.2),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.enhanced_encryption_rounded,
                  color: Colors.amber, size: 20),
              const SizedBox(width: 10),
              Text('AES-256-GCM Locked',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade200)),
            ],
          ),
          const SizedBox(height: 12),
          _Row('Algorithm', 'AES-256-GCM'),
          _Row('Key Size', '$keyBits bits'),
          _Row('IV Size', '$ivBytes bytes'),
          _Row('Payload', _fmtSize(ciphertextBytes)),
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
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          Text(value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMain)),
        ],
      ),
    );
  }
}

class _ReceiverBadge extends StatelessWidget {
  final String username;

  const _ReceiverBadge({required this.username});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: Colors.indigo.withValues(alpha: 0.1),
      borderColor: Colors.indigo.withValues(alpha: 0.2),
      child: Row(
        children: [
          const Icon(Icons.person_pin_rounded,
              color: Colors.indigoAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Encrypted for ', style: TextStyle(fontSize: 13, color: Colors.white70)),
                  TextSpan(text: '@$username', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
            ),
          ),
          const Icon(Icons.check_circle_rounded,
              color: Colors.green, size: 20),
        ],
      ),
    );
  }
}

class _WaitingForReceiverWidget extends StatefulWidget {
  final int secondsRemaining;
  const _WaitingForReceiverWidget({required this.secondsRemaining});

  @override
  State<_WaitingForReceiverWidget> createState() =>
      _WaitingForReceiverWidgetState();
}

class _WaitingForReceiverWidgetState extends State<_WaitingForReceiverWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _fade = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mins = widget.secondsRemaining ~/ 60;
    final secs = widget.secondsRemaining % 60;
    final display =
        '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          ScaleTransition(
            scale: _scale,
            child: FadeTransition(
              opacity: _fade,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withValues(alpha: 0.1),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.2),
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.hourglass_top_rounded,
                  color: cs.primary,
                  size: 32,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Waiting for Receiver to prepare secure vault…',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Receiver must open the secure inbox to continue.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          GlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: cs.primary.withValues(alpha: 0.07),
            borderColor: cs.primary.withValues(alpha: 0.15),
            borderRadius: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  display,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
