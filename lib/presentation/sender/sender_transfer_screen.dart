import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../../core/utils/security_lifecycle_mixin.dart';
import '../../data/repositories/transfer_repository.dart';
import 'sender_session_end_screen.dart';
import '../home/home_screen.dart';
import '../widgets/shared_widgets.dart';

class SenderTransferScreen extends StatefulWidget {
  final String transferId;
  final Uint8List encryptedBytes;
  final String fileName;
  final int fileSize;
  final String receiverUsername;
  final String receiverId;
  final String senderId;
  final String encryptedAESKeyB64;
  final String ivB64;

  /// Raw AES key bytes — registered in initState and zeroed by wipeAll() on session end (D-07).
  final Uint8List? aesKey;

  const SenderTransferScreen({
    super.key,
    required this.transferId,
    required this.encryptedBytes,
    required this.fileName,
    required this.fileSize,
    required this.receiverUsername,
    required this.receiverId,
    required this.senderId,
    required this.encryptedAESKeyB64,
    required this.ivB64,
    this.aesKey,
  });

  @override
  State<SenderTransferScreen> createState() =>
      _SenderTransferScreenState();
}

class _SenderTransferScreenState extends State<SenderTransferScreen>
    with SingleTickerProviderStateMixin,
        SecurityLifecycleMixin<SenderTransferScreen> {
  final _transferRepo = TransferRepository();

  double _progress = 0.0;
  int _bytesTransferred = 0;
  int _totalBytes = 0;
  bool _done = false;
  String? _error;

  // ── Non-repudiation listener state ────────────────────────────────────────
  StreamSubscription<DocumentSnapshot>? _transferListener;
  bool _receiverDecrypted = false;
  bool _canEndSession = false;
  bool _sessionEnded = false; // D-06: guard against double-fire on stream reconnect
  bool _senderWipeSent = false; // guard against double-fire on Turn 2 AES key wipe
  bool _timeoutStarted = false; // guard: arm cleanup timeout exactly once
  Timer? _cleanupTimeoutTimer; // safety timeout — cancelled on Turn 2/Turn 4/dispose
  String? _statusMessage;
  bool _aborting = false; // true while our own abort is in flight — prevents double-fire from stream
  UploadTask? _uploadTask; // held so abort can cancel the in-flight Storage task

  static const _kWatchdogSeconds = 120;
  Timer? _watchdogTimer;

  late AnimationController _successCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _totalBytes = widget.encryptedBytes.length;
    // Register sensitive buffers — zeroed automatically on dispose.
    registerBuffer(widget.encryptedBytes);
    if (widget.aesKey != null) registerBuffer(widget.aesKey!);

    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scaleAnim = CurvedAnimation(
      parent: _successCtrl,
      curve: Curves.elasticOut,
    );

    _startUpload(); // _startTransferListener() is called inside _startUpload() after doc exists
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    _cleanupTimeoutTimer?.cancel();
    _transferListener?.cancel();
    _successCtrl.dispose();
    super.dispose();
  }

  // ─── Non-repudiation: real-time receiver status ───────────────────────────

  void _startTransferListener() {
    _transferListener = _transferRepo
        .watchTransferStatus(widget.transferId)
        .listen((snapshot) async {
      // Turn 4: doc deleted by receiver — session closed; notify sender and return home.
      if (!snapshot.exists) {
        if (_sessionEnded) return;
        if (!_done) return; // ignore spurious deletion before upload finishes
        _cleanupTimeoutTimer?.cancel();
        _sessionEnded = true;
        wipeAll(); // zeros widget.encryptedBytes + widget.aesKey (registered in initState)
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: const Text('✓ Receiver has securely closed the session'),
                backgroundColor: Theme.of(context).colorScheme.secondary,
                duration: const Duration(seconds: 4),
              ),
            );
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (_) => false,
          );
        }
        return;
      }

      _resetWatchdog();
      final data = snapshot.data()!;
      final status = data['status'] as String?;

      // Counter-party abort: receiver set status = 'failed' — wipe and return home.
      if (status == 'failed' && !_aborting && !_sessionEnded) {
        _cleanupTimeoutTimer?.cancel();
        _sessionEnded = true;
        try {
          await _transferRepo.deleteStorageFile(widget.transferId);
        } catch (_) {}
        wipeAll();
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: const Text('Transfer aborted — receiver terminated the tunnel'),
                backgroundColor: Theme.of(context).colorScheme.tertiary,
                duration: const Duration(seconds: 4),
              ),
            );
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (_) => false,
          );
        }
        return;
      }

      // Turn 2: receiver has initiated cleanup — wipe AES key from Firestore + RAM
      final cleanupInitiated = data['cleanup_initiated'] as bool? ?? false;
      if (cleanupInitiated && _done && !_senderWipeSent && !_sessionEnded) {
        _cleanupTimeoutTimer?.cancel();
        _senderWipeSent = true;
        try {
          await _transferRepo.senderWipeAESKey(widget.transferId);
        } catch (e) {
          // Remote AES key erasure failed — local wipe still runs below.
          // Log so the failure is visible in security review (no key material logged).
          debugPrint('[Security] Turn 2 Firestore key erasure failed: $e');
        }
        wipeAll(); // zeros widget.encryptedBytes + widget.aesKey registered in initState
        if (mounted) {
          setState(() {
            _statusMessage = 'Keys destroyed. Waiting for receiver to terminate session…';
            _canEndSession = false;
          });
        }
        return;
      }

      final receiverStatus = data['receiverStatus'] as String?;

      if (receiverStatus == 'decrypted' && mounted) {
        setState(() {
          _receiverDecrypted = true;
          _statusMessage = '✅ Receiver successfully decrypted file';
        });
        _clearSenderLocalMetadata();
      }

      if (receiverStatus == 'saved' && mounted) {
        _watchdogTimer?.cancel(); // cleanup timeout takes over from here
        setState(() {
          _statusMessage = '✅ Receiver saved the file securely';
          _canEndSession = true;
        });
        if (!_timeoutStarted) {           // guard: arm cleanup timeout exactly once
          _timeoutStarted = true;
          _startCleanupTimeout();
        }
      }
    });
  }

  // ─── Receiver-silence watchdog ───────────────────────────────────────────

  void _resetWatchdog() {
    if (_aborting || _sessionEnded) return;
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(
      const Duration(seconds: _kWatchdogSeconds),
      _onWatchdogFired,
    );
  }

  void _onWatchdogFired() => _abortDueToWatchdog();

  Future<void> _abortDueToWatchdog() async {
    if (_aborting || _sessionEnded || !mounted) return;
    _aborting = true;
    _sessionEnded = true;
    _watchdogTimer?.cancel();
    _cleanupTimeoutTimer?.cancel();
    _uploadTask?.cancel();
    try {
      await _transferRepo.markTransferInterrupted(widget.transferId, wipeAesKey: true);
      await _transferRepo.deleteStorageFile(widget.transferId);
      await _transferRepo.writeConnectionLostAuditLog(
        senderId: widget.senderId,
        receiverId: widget.receiverId,
        receiverUsername: widget.receiverUsername,
        fileName: widget.fileName,
        fileSize: widget.fileSize,
      );
    } catch (_) {}
    wipeAll();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: const Text('Transfer stalled — receiver connection lost'),
          backgroundColor: Theme.of(context).colorScheme.tertiary,
          duration: const Duration(seconds: 4),
        ));
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    }
  }

  Future<void> _clearSenderLocalMetadata() async {
    await _transferRepo.updateTransferField(
      widget.transferId,
      'senderStatus',
      'metadata_cleared',
    );
  }

  /// Starts a 300-second safety timeout after the receiver saves the file.
  /// If cleanup_initiated never fires (receiver crash / no connection), we auto-wipe
  /// and navigate to SenderSessionEndedScreen to unblock the sender.
  void _startCleanupTimeout() {
    _cleanupTimeoutTimer?.cancel(); // defensive: should not already be running
    _cleanupTimeoutTimer = Timer(const Duration(seconds: 300), () {
      if (!mounted || _senderWipeSent || _sessionEnded) return;
      _sessionEnded = true;
      wipeAll();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SenderSessionEndScreen(
              transferId: widget.transferId,
              fileName: widget.fileName,
              fileSize: widget.fileSize,
              receiverUsername: widget.receiverUsername,
              senderId: widget.senderId,
              receiverId: widget.receiverId,
              timeoutReason: 'Session ended by timeout — receiver did not complete cleanup',
            ),
          ),
        );
      }
    });
  }

  // ─── Abort dialog ────────────────────────────────────────────────────────────

  Future<void> _showAbortDialog() async {
    if (_aborting || _sessionEnded) return;
    final abort = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
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
              Icon(Icons.warning_rounded, size: 48, color: Theme.of(ctx).colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Abort Transfer?',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'This will destroy all cryptographic material and collapse the secure '
                'tunnel. The receiver will be notified that the transfer failed.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CrypButton(
                      label: const Text('Abort & Destroy'),
                      color: Theme.of(ctx).colorScheme.error,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (abort == true && mounted) {
      await _abortSessionDueToDisconnect();
    }
  }

  Future<void> _abortSessionDueToDisconnect() async {
    if (_aborting || _sessionEnded) return;
    _aborting = true;
    _sessionEnded = true;
    _cleanupTimeoutTimer?.cancel();
    _uploadTask?.cancel();
    try {
      await _transferRepo.markTransferInterrupted(widget.transferId, wipeAesKey: true);
    } catch (_) {
      // Doc may not exist yet if upload hadn't started — wipe proceeds regardless.
    }
    try {
      await _transferRepo.deleteStorageFile(widget.transferId);
    } catch (_) {}
    wipeAll();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: const Text('Transfer aborted — tunnel destroyed.'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 4),
          ),
        );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    }
  }

  Future<void> _startUpload() async {
    try {
      await _transferRepo
          .uploadAndCreate(
            transferId: widget.transferId,
            encryptedBytes: widget.encryptedBytes,
            fileName: widget.fileName,
            fileSize: widget.fileSize,
            senderId: widget.senderId,
            receiverId: widget.receiverId,
            encryptedAESKeyB64: widget.encryptedAESKeyB64,
            ivB64: widget.ivB64,
          )
          .forEach((progress) {
            if (mounted) {
              setState(() {
                _bytesTransferred = (progress * widget.encryptedBytes.length).toInt();
                _totalBytes = widget.encryptedBytes.length;
                _progress = progress;
              });
            }
          });

      // Start the non-repudiation listener NOW — doc exists, security rule can evaluate.
      // Starting before .set() would subscribe to a non-existent doc, causing
      // resource.data access in the Firestore rule to return false (null resource),
      // which silently cancels the subscription before any receiver updates arrive.
      _startTransferListener();

      // Notify receiver (non-critical)
      try {
        final senderUsername =
            FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown';
        await _transferRepo.notifyReceiver(
          receiverId: widget.receiverId,
          senderUsername: senderUsername,
          transferId: widget.transferId,
        );
      } catch (_) {}

      if (mounted) {
        setState(() {
          _progress = 1.0;
          _done = true;
        });
        _successCtrl.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) => _showAbortDialog(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(_done ? 'Transfer Complete' : 'Sending File'),
          centerTitle: true,
          automaticallyImplyLeading: false,
        ),
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),

              // ── File info card ────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Column(
                  children: [
                    Icon(
                      _done
                          ? Icons.lock_open_rounded
                          : Icons.lock_rounded,
                      size: 40,
                      color: _done ? cs.secondary : cs.primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.fileName,
                      style: Theme.of(context).textTheme.titleSmall,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _fmt(widget.fileSize),
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_forward_rounded,
                            size: 14, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          '@${widget.receiverUsername}',
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 48),

              // ── Progress / success / error ────────────────────────────
              if (_error != null) ...[
                Icon(Icons.error_rounded, size: 64, color: cs.error),
                const SizedBox(height: 16),
                Text(
                  'Upload Failed',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 18, color: cs.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: cs.onSurfaceVariant, height: 1.5),
                ),
                const SizedBox(height: 28),
                CrypButton(
                  label: const Text('Go Back'),
                  onPressed: () => Navigator.pop(context),
                ),
              ] else if (_done) ...[
                ScaleTransition(
                  scale: _scaleAnim,
                  child: Column(
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.secondary,
                        ),
                        child: Icon(Icons.check_rounded,
                            color: cs.onSecondary, size: 48),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'File Sent Successfully!',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: cs.secondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The encrypted file has been uploaded\nand the transfer record saved.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: cs.onSurfaceVariant, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Receiver status badge (live) ──────────────────────────
                if (_receiverDecrypted || _canEndSession)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Container(
                      key: ValueKey(_statusMessage),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: (_canEndSession ? cs.secondary : cs.tertiary)
                            .withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (_canEndSession ? cs.secondary : cs.tertiary)
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _canEndSession
                                ? Icons.verified_rounded
                                : Icons.lock_open_rounded,
                            size: 18,
                            color: _canEndSession ? cs.secondary : cs.tertiary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _statusMessage!,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: _canEndSession ? cs.secondary : cs.tertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Pulsing cleanup-wait indicator — shown after receiver saves, before Turn 2 fires
                if (_canEndSession && !_senderWipeSent) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Waiting for secure session close…',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],

              ] else ...[
                Text(
                  'Uploading encrypted file…',
                  style: Theme.of(context).textTheme.titleSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 14,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(cs.primary),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '${(_progress * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 28,
                    color: cs.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  '${_fmt(_bytesTransferred)} / ${_fmt(_totalBytes)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
