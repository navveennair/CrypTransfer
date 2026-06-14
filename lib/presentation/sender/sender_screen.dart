import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/firebase_constants.dart';
import '../../core/utils/biometric_helper.dart';
import '../../core/utils/tofu_service.dart';
import '../../data/repositories/key_repository.dart';
import '../../data/repositories/transfer_repository.dart';
import '../../core/utils/security_lifecycle_mixin.dart';
import '../../data/services/encryption_service.dart';
import '../../data/services/transfer_service.dart';
import '../home/home_screen.dart';
import '../widgets/shared_widgets.dart';
import 'sender_transfer_screen.dart';

// ─── Isolate-safe RSA-OAEP encrypt ───────────────────────────────────────────

Uint8List _rsaOaepEncryptIsolate(List<dynamic> args) {
  final publicKeyJson = args[0] as String;
  final data = args[1] as Uint8List;
  final key = EncryptionService.decodePublicKey(publicKeyJson);
  return EncryptionService.rsaEncrypt(key, data);
}

// ─── Widget ──────────────────────────────────────────────────────────────────

class SenderScreen extends StatefulWidget {
  final String? preFilledPartnerUid;
  final String? preFilledPartnerUsername;
  final String? handshakeDocId;

  const SenderScreen({
    super.key,
    this.preFilledPartnerUid,
    this.preFilledPartnerUsername,
    this.handshakeDocId,
  });

  @override
  State<SenderScreen> createState() => _SenderScreenState();
}

class _SenderScreenState extends State<SenderScreen>
    with SecurityLifecycleMixin<SenderScreen> {
  final _connService = KeyRepository();
  final _transferRepo = TransferRepository();

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
  bool _everConnected = false;   // true after first successful handshake; used to detect reconnects

  TofuStatus? _tofuStatus;
  String? _receiverFingerprint;
  String? _handshakeDocId;

  @override
  void initState() {
    super.initState();
    _handshakeDocId = widget.handshakeDocId;
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
    // If sender leaves before a handshake was created, clearTransferRoles is never
    // called — clear the Firestore claim directly so the partner's Send File unblocks.
    if (_handshakeDocId == null) {
      _connService.clearSenderClaim();
    }
    super.dispose();
  }

  void _startHandshakeListener() {
    _handshakeSub = _connService.streamHandshakesForSender().listen(
      _onHandshakeUpdate,
      onError: (error) {
        _showError('Stream error: $error', duration: const Duration(seconds: 5));
      },
    );
  }

  void _onHandshakeUpdate(
      QuerySnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;

    // Once paired with a specific receiver, only process their doc.
    // Before pairing (discovery mode), accept the first doc in the snapshot.
    // This prevents a stale or concurrent handshake doc from a different
    // receiver being processed, and ensures TOFU checks target the right key.
    final knownReceiverId = _receiverId ?? widget.preFilledPartnerUid;
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
      // Don't wipe mid-encryption — let the compute() isolate finish so the
      // user doesn't lose their progress silently.
      if (_encrypting || _encryptingKey) return;
      _readinessTimer?.cancel();
      _readinessTimer = null;
      _ejectToHomeScreen();
      return;
    } else {
      final docId = relevantDocs.first.id;
      final doc = relevantDocs.first.data();
      final receiverId = doc['receiverId'] as String? ?? '';
      // 'receiverUsername' is the canonical field (written by updated key_repository).
      // Fall back to legacy 'fromUsername' for documents created before this fix.
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
          _revertToWaiting();
          _showError('Role conflict — partner also chose Sender. Go back and pick again.');
          return;
        }
      }

      if (publicKey != null &&
          publicKey.isNotEmpty &&
          status == 'handshake_complete' &&
          receiverId.isNotEmpty) {
        // FIX 2: assignTransferRole() now returns empty string (no Firestore write).
        // Accept the stream-discovered docId regardless of what we got from HomeScreen.
        if (_handshakeDocId == null || _handshakeDocId!.isEmpty) {
          _handshakeDocId = docId;
        }
        final previousPublicKey = _selectedReceiverPublicKeyJson;
        final isReconnect = _everConnected && _selectedReceiverPublicKeyJson == null;
        setState(() {
          _receiverId = receiverId;
          _receiverUsername = receiverUsername;
          _selectedReceiverPublicKeyJson = publicKey;
        });
        _streamSettled = true;   // CR-01: stream has produced a non-empty doc; cold-start phase over
        _everConnected = true;
        if (publicKey != previousPublicKey || _tofuStatus == null) {
          _checkTofuStatus(receiverId, publicKey);
        }

        if (isReconnect) {
          _showSuccess('Connection re-established with @$receiverUsername — new RSA key received.');
        }

        // Skip stale-key check if encryption is already in flight.
        if (_encrypting || _encryptingKey) return;

        // Receiver's public key rotated after we already encrypted — wipe stale AES key.
        if (previousPublicKey != null &&
            publicKey != previousPublicKey &&
            _encryptedAESKey != null) {
          _wipeSensitiveData();
          _showError('Receiver key changed — re-encrypt required.',
              duration: const Duration(seconds: 6), clear: true);
        }

        // Parse receiverReady from handshake doc (set automatically if mailbox is open)
        final receiverReady = doc['receiverReady'] as bool? ?? false;

        if (_receiverSelected && !_receiverReady && _readinessTimer == null) {
          _startReadinessTimer();
        }

        if (!_receiverReady && receiverReady) {
          _onReceiverBecameReady();
        } else if (_receiverReady != receiverReady) {
          // Don't wipe mid-encryption — compute() is in flight.
          if (_encrypting || _encryptingKey) return;
          _revertToWaiting();
          _showInfo('Receiver closed their mailbox — waiting for confirmation.');
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
        _tofuStatus = null;
        _receiverFingerprint = null;
      });
      // Only restart the timer if we have a known receiver to wait for.
      // In discovery mode (no pre-filled partner), don't start the timer.
      if (_receiverId != null) {
        _startReadinessTimer();
      }
    }
  }

  Future<void> _pickFile() async {
    _wipeSensitiveData();
    try {
      final result = await FilePicker.pickFiles(withData: kIsWeb);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.size > FirebaseConstants.maxDownloadBytes) {
        _showError(
          'File too large — maximum is 100 MB '
          '(${(file.size / (1024 * 1024)).toStringAsFixed(1)} MB selected)',
        );
        return;
      }
      if (!kIsWeb && file.path == null) {
        _showError("This file type isn't supported — try saving it locally first.");
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
      registerBuffer(plaintext);

      // ── Phase 2: AES-256-GCM in compute() isolate (70 → 100%) ───────
      final result = await EncryptionService.encryptAesGcm(plaintext);
      registerBuffer(result.key);
      registerBuffer(result.iv);
      registerBuffer(result.ciphertext);
      _progressCtrl.add(1.0);

      plaintext.fillRange(0, plaintext.length, 0);
      unregisterBuffer(plaintext);

      if (mounted) {
        setState(() {
          _aesKey = result.key;
          _iv = result.iv;
          _encryptedBytes = result.ciphertext;
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

  Future<void> _encryptAesKey() async {
    if (_encryptingKey) return;
    final aesKey = _aesKey;
    final publicKeyJson = _selectedReceiverPublicKeyJson;
    final receiverId = _receiverId;
    if (aesKey == null) {
      _showError('Encrypt the file first (Step 2).');
      return;
    }
    if (publicKeyJson == null || receiverId == null) {
      _showError('Select a receiver first (Step 0).');
      return;
    }

    // Pre-emptive freshness check: confirm the cached public key is still live
    // in Firestore before showing the biometric prompt.  The reactive stream has
    // ~1-2 s latency; without this gate the sender can encrypt with a stale key
    // in the window between the receiver closing their mailbox and the stream
    // delivering the null snapshot.
    try {
      final liveKey = await _connService.fetchHandshakePublicKey(receiverId);
      if (!mounted) return;
      if (liveKey == null || liveKey != publicKeyJson) {
        _wipeSensitiveData();
        final msg = liveKey == null
            ? 'Session ended — receiver closed their mailbox.'
            : 'Receiver key changed — re-encrypt required.';
        await _writeAbortAndNavigateHome(
          receiverId: receiverId,
          receiverUsername: _receiverUsername ?? 'Unknown',
          msg: msg,
        );
        return;
      }
    } catch (_) {
      if (!mounted) return;
      _showError('Could not verify receiver key. Please try again.');
      return;
    }

    setState(() => _encryptingKey = true);
    final ok = await BiometricHelper.authenticate(
        'Authenticate to encrypt the AES key for '
        '${_receiverUsername ?? "receiver"}');
    if (!mounted) return;
    if (!ok) {
      setState(() => _encryptingKey = false);
      _showError('Authentication failed or was cancelled. Tap to retry.');
      return;
    }
    try {
      final encryptedAESKey = await compute(
        _rsaOaepEncryptIsolate,
        [publicKeyJson, aesKey],
      );
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

    final transferId = _transferRepo.generateId();

    final encryptedAESKeyB64 = base64Encode(encryptedAESKey);
    final ivB64 = base64Encode(iv);
    final encryptedBytesCopy = Uint8List.fromList(encryptedBytes);

    _wipeSensitiveData();

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, _) => SenderTransferScreen(
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

  void _showError(String msg, {Duration? duration, bool clear = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (clear) messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Theme.of(context).colorScheme.error,
      duration: duration ?? const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showSuccess(String msg, {Duration duration = const Duration(seconds: 4)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Theme.of(context).colorScheme.secondary,
      duration: duration,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Theme.of(context).colorScheme.tertiary,
    ));
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
    setState(() {
      _receiverReady = true;
    });
    _showSuccess('Secure channel established. Receiver is ready.');
  }

  void _ejectToHomeScreen() {
    _wipeSensitiveData();
    _showError('Session Terminated — receiver closed the session.',
        duration: const Duration(seconds: 5));
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => HomeScreen()),
      (_) => false,
    );
  }

  /// Writes an aborted audit log to both users, shows an error snackbar, then
  /// navigates the sender back to HomeScreen.  Called from the pre-emptive
  /// stale-key gate in _encryptAesKey() — no transfer doc exists at this point.
  Future<void> _writeAbortAndNavigateHome({
    required String receiverId,
    required String receiverUsername,
    required String msg,
  }) async {
    final senderId = FirebaseAuth.instance.currentUser?.uid;
    final senderUsername =
        FirebaseAuth.instance.currentUser?.displayName ?? '';
    final fileName = _file?.name ?? '';
    final fileSize = _file?.size ?? 0;
    if (senderId != null && fileName.isNotEmpty) {
      try {
        await _transferRepo.writeAbortAuditLog(
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
    _showError(msg, duration: const Duration(seconds: 5), clear: true);
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => HomeScreen()),
      (_) => false,
    );
  }

  Future<void> _checkTofuStatus(String receiverUid, String publicKeyJson) async {
    final status = await TofuService.check(receiverUid, publicKeyJson);
    if (status == TofuStatus.firstContact) {
      await TofuService.pin(receiverUid, publicKeyJson);
    }
    if (!mounted) return;
    if (status == TofuStatus.keyChanged) {
      setState(() => _tofuStatus = TofuStatus.keyChanged);
      _showKeyChangedDialog(receiverUid, publicKeyJson);
    } else {
      final fp = TofuService.displayFingerprint(publicKeyJson);
      setState(() {
        _tofuStatus = status;
        _receiverFingerprint = fp;
      });
    }
  }

  void _showVerifyDialog() {
    final receiverId = _receiverId;
    final fp = _receiverFingerprint;
    if (receiverId == null || fp == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Verify Receiver Identity'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Compare this fingerprint with your receiver out-of-band (call, in person):',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                fp,
                style: GoogleFonts.robotoMono(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
            ),
          ],
        ),
        actions: [
          CrypButton(
            label: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 44,
          ),
          CrypButton(
            label: const Text('It Matches'),
            onPressed: () async {
              await TofuService.markVerified(receiverId);
              if (!mounted) return;
              setState(() => _tofuStatus = TofuStatus.verified);
              Navigator.pop(context);
            },
            color: Theme.of(context).colorScheme.tertiary,
            height: 48,
          ),
        ],
      ),
    );
  }

  void _showKeyChangedDialog(String uid, String keyJson) {
    final fp = TofuService.displayFingerprint(keyJson);
    final cs = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_rounded, color: cs.error),
            const SizedBox(width: 8),
            Text('Key Changed!', style: TextStyle(color: cs.error)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This receiver\'s public key has changed since your last session. '
              'This may indicate a man-in-the-middle attack.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text(
              'Call or meet your receiver and confirm the new fingerprint matches '
              'exactly before proceeding:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                fp,
                textAlign: TextAlign.center,
                style: GoogleFonts.robotoMono(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  letterSpacing: 2,
                  color: cs.onErrorContainer,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Only tap "It Matches" after confirming out-of-band.',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          CrypButton(
            label: const Text('Cancel'),
            onPressed: () {
              Navigator.pop(context);
              _revertToWaiting();
            },
            color: cs.onSurfaceVariant,
            height: 44,
          ),
          CrypButton(
            label: const Text('It Matches — Trust New Key'),
            onPressed: () async {
              // Repin AND mark verified in one step — no unverified trust path.
              await TofuService.repin(uid, keyJson);
              await TofuService.markVerified(uid);
              if (!mounted) return;
              setState(() {
                _tofuStatus = TofuStatus.verified;
                _receiverFingerprint = fp;
              });
              Navigator.pop(context);
            },
            color: cs.error,
            height: 48,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_encrypting && !_encryptingKey,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _wipeSensitiveData();
          // Clear transfer roles if assigned (returns user to role picker)
          if (_handshakeDocId != null) {
            _connService.clearTransferRoles(handshakeDocId: _handshakeDocId!);
          }
        } else if (_handshakeDocId != null && !_encrypting && !_encryptingKey) {
          // Show confirmation dialog for role clearing
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.all(24),
              content: GlassContainer(
                padding: const EdgeInsets.all(24),
                borderRadius: 28,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_rounded, size: 48, color: Theme.of(ctx).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Go Back?',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Going back will clear your role assignment. The connection will remain.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: CrypButton(
                            label: const Text('Cancel'),
                            onPressed: () => Navigator.pop(ctx),
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            height: 44,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CrypButton(
                            label: const Text('Clear & Go Back'),
                            color: Theme.of(ctx).colorScheme.primary,
                            onPressed: () async {
                              Navigator.pop(ctx);
                              final nav = Navigator.of(context);
                              await _connService.clearTransferRoles(
                                  handshakeDocId: _handshakeDocId!);
                              if (mounted) nav.pop();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Send File'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Welcome banner ────────────────────────────────
            GlassContainer(
              blur: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              borderRadius: 28,
              color: cs.primary.withValues(alpha: 0.1),
              borderColor: cs.primary.withValues(alpha: 0.2),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.send_rounded, color: cs.primary, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Secure Inbox',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          'Securely encrypt and transmit your data.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ── Step 0: Receiver-Authorized Connection ──────────────────
            StepCard(
              step: 0,
              title: 'Secure Connection',
              done: _receiverSelected && _receiverReady,
              currentStep: !(_receiverSelected && _receiverReady),
              child: _receiverSelected
                  ? (_receiverReady
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ConnectedBadge(username: _receiverUsername!),
                            if (_tofuStatus != null) ...[
                              const SizedBox(height: 8),
                              _TofuStatusBanner(
                                status: _tofuStatus!,
                                onVerify: _showVerifyDialog,
                              ),
                            ],
                          ],
                        )
                      : _WaitingForReceiverWidget(secondsRemaining: _secondsRemaining, timerRunning: _readinessTimer != null))
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
                      opacity: (_receiverSelected && !_fileEncrypted) ? 1.0 : 0.4,
                      duration: const Duration(milliseconds: 300),
                      child: IgnorePointer(
                        ignoring: _fileEncrypted,
                        child: StepCard(
                          step: 1,
                          title: 'Select File',
                          done: _fileSelected,
                          currentStep: _receiverReady && !_fileSelected,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              CrypButton(
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
                        currentStep: _fileSelected && !_fileEncrypted,
                        child: _fileEncrypted
                            ? _EncryptedBadge(
                                keyBits: _aesKey!.length * 8,
                                ivBytes: _iv!.length,
                                ciphertextBytes: _encryptedBytes!.length,
                              )
                            : _encrypting
                                ? _EncryptionProgressWidget(
                                    progress: _encryptionProgress)
                                : CrypButton(
                                    icon: const Icon(Icons.lock_rounded, size: 20),
                                    label: const Text('Encrypt with AES Key'),
                                    onPressed: _fileSelected ? _encryptFile : null,
                                    color: cs.tertiary,
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
                        currentStep: _fileEncrypted && !_readyToSend,
                        child: _readyToSend
                            ? _ReceiverBadge(username: _receiverUsername!)
                            : CrypButton(
                                icon: _encryptingKey
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.security_rounded, size: 20),
                                label: Text(_encryptingKey
                                    ? 'Encrypting key…'
                                    : 'Encrypt Key for @${_receiverUsername ?? "receiver"}'),
                                onPressed: _fileEncrypted &&
                                           !_encryptingKey &&
                                           _tofuStatus != null &&
                                           _tofuStatus != TofuStatus.keyChanged
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
                          ? CrypButton(
                              key: const ValueKey('send-btn'),
                              icon: const Icon(Icons.send_rounded, size: 20),
                              label: const Text('Send Encrypted File'),
                              onPressed: _send,
                              color: cs.secondary,
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
    final cs = Theme.of(context).colorScheme;
    final pct = (progress * 100).toInt();
    final isReading = progress < 0.7;
    return GlassContainer(
      blur: 0,
      padding: const EdgeInsets.all(16),
      color: cs.tertiary.withValues(alpha: 0.08),
      borderColor: cs.tertiary.withValues(alpha: 0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.tertiary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                isReading ? 'Reading file… $pct%' : 'Encrypting AES-256-GCM… $pct%',
                style: TextStyle(fontSize: 13, color: cs.tertiary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: cs.tertiary.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(cs.tertiary),
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
            style: Theme.of(context).textTheme.bodyMedium,
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
    final cs = Theme.of(context).colorScheme;
    return GlassContainer(
      blur: 0,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: cs.secondary.withValues(alpha: 0.1),
      borderColor: cs.secondary.withValues(alpha: 0.2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.secondary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.verified_user_rounded,
                color: cs.secondary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connection Verified',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.secondary),
                ),
                const SizedBox(height: 2),
                Text(
                  'Secure channel open with @$username',
                  style: TextStyle(
                      fontSize: 12, color: cs.secondary),
                ),
              ],
            ),
          ),
          Icon(Icons.lock_rounded, color: cs.secondary, size: 18),
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
      blur: 0,
      padding: const EdgeInsets.all(14),
      color: cs.surface.withValues(alpha: 0.05),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _extColor(ext, cs).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_extIcon(ext), color: _extColor(ext, cs), size: 24),
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

  Color _extColor(String ext, ColorScheme cs) {
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return cs.primary;
    if (['mp4', 'mov', 'avi'].contains(ext)) return cs.tertiary;
    if (['mp3', 'wav', 'flac'].contains(ext)) return cs.tertiary;
    if (ext == 'pdf') return cs.error;
    return cs.outline;
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GlassContainer(
      blur: 0,
      padding: const EdgeInsets.all(16),
      color: cs.tertiary.withValues(alpha: 0.08),
      borderColor: cs.tertiary.withValues(alpha: 0.2),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.enhanced_encryption_rounded,
                  color: cs.tertiary, size: 20),
              const SizedBox(width: 10),
              Text('AES-256-GCM Locked',
                  style: tt.bodyMedium?.copyWith(color: cs.tertiary)),
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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          Text(value,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
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
    final cs = Theme.of(context).colorScheme;
    return GlassContainer(
      blur: 0,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: cs.primary.withValues(alpha: 0.1),
      borderColor: cs.primary.withValues(alpha: 0.2),
      child: Row(
        children: [
          Icon(Icons.person_pin_rounded,
              color: cs.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Encrypted for ', style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.7))),
                  TextSpan(text: '@$username', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: cs.onSurface)),
                ],
              ),
            ),
          ),
          Icon(Icons.check_circle_rounded,
              color: cs.secondary, size: 20),
        ],
      ),
    );
  }
}

class _WaitingForReceiverWidget extends StatefulWidget {
  final int secondsRemaining;
  final bool timerRunning;
  const _WaitingForReceiverWidget({required this.secondsRemaining, required this.timerRunning});

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
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            widget.timerRunning
                ? 'Receiver must confirm readiness to continue.'
                : 'Waiting for receiver to connect…',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (widget.timerRunning) ...[
            const SizedBox(height: 16),
            GlassContainer(
              blur: 0,
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
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── TOFU status banner ──────────────────────────────────────────────────────

class _TofuStatusBanner extends StatelessWidget {
  final TofuStatus status;
  final VoidCallback onVerify;

  const _TofuStatusBanner({required this.status, required this.onVerify});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (status == TofuStatus.verified) {
      return GlassContainer(
        blur: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        color: cs.secondary.withValues(alpha: 0.08),
        borderColor: cs.secondary.withValues(alpha: 0.2),
        child: Row(
          children: [
            Icon(Icons.verified_rounded, color: cs.secondary, size: 16),
            const SizedBox(width: 8),
            Text(
              'Identity verified',
              style: TextStyle(fontSize: 12, color: cs.secondary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    // firstContact or trusted — tertiary nudge, transfer allowed
    return GlassContainer(
      blur: 0,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: cs.tertiary.withValues(alpha: 0.08),
      borderColor: cs.tertiary.withValues(alpha: 0.2),
      child: Row(
        children: [
          Icon(Icons.fingerprint_rounded, color: cs.tertiary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Identity not verified',
              style: TextStyle(fontSize: 12, color: cs.tertiary),
            ),
          ),
          Semantics(
            label: 'Verify receiver identity',
            button: true,
            child: InkWell(
              onTap: onVerify,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text(
                  'Verify',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.primary,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                    decorationColor: cs.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
