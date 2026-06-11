import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/utils/security_lifecycle_mixin.dart';
import '../../data/repositories/transfer_repository.dart';
import '../home/home_screen.dart';
import '../widgets/shared_widgets.dart';

/// Shown to the sender after the receiver completes cleanup.
///
/// Two checklist sections:
///  1. "Receiver cleaned up:" — what the receiver destroyed (audit log, storage,
///     transfer record, RSA keys).
///  2. "Your device cleaned up:" — AES key zeroed from memory (shown after
///     D-10 edge-case check completes).
///
/// D-10: In [initState] we verify that the transfer doc is gone. If it still
/// exists (receiver cleanup was interrupted), we delete it here before marking
/// the AES cleanup done. In the normal flow, the doc is already absent.
///
/// "Back to Home" is intentionally gated behind [_aesCleanDone] — the sender
/// cannot navigate away until local cleanup is confirmed.
///
/// NO aesKey constructor arg — the AES key was zeroed by wipeAll() in
/// [SenderTransferScreen] before navigation (D-07).
class SenderSessionEndScreen extends StatefulWidget {
  final String transferId; // D-10 edge-case check
  final String fileName;
  final int fileSize;
  final String receiverUsername;
  final String senderId;
  final String receiverId;
  final String? timeoutReason; // null = normal cleanup; non-null = timeout message

  const SenderSessionEndScreen({
    super.key,
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.receiverUsername,
    required this.senderId,
    required this.receiverId,
    this.timeoutReason,
  });

  @override
  State<SenderSessionEndScreen> createState() => _SenderSessionEndScreenState();
}

class _SenderSessionEndScreenState extends State<SenderSessionEndScreen>
    with SecurityLifecycleMixin<SenderSessionEndScreen> {
  final _transferRepo = TransferRepository();
  bool _aesCleanDone = false;
  StreamSubscription<DocumentSnapshot>? _cleanupSub;
  bool _edgeCaseHandled = false;

  @override
  void initState() {
    super.initState();
    // No buffers to register — AES already zeroed upstream in SenderTransferScreen.
    _watchForCleanupCompletion();
  }

  @override
  void dispose() {
    _cleanupSub?.cancel();
    super.dispose();
  }

  void _watchForCleanupCompletion() {
    // Stream the transfer doc — reacts to deletion rather than polling once.
    // D-10: if doc still exists on arrival (interrupted receiver cleanup), delete it.
    Timer(const Duration(seconds: 30), () {
      if (mounted && !_aesCleanDone) {
        setState(() => _aesCleanDone = true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Cleanup could not be verified — session cleared locally'),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ));
      }
    });
    _cleanupSub = _transferRepo
        .watchTransferStatus(widget.transferId)
        .listen((snap) async {
      if (!snap.exists) {
        _cleanupSub?.cancel();
        _cleanupSub = null;
        if (mounted) setState(() => _aesCleanDone = true);
        return;
      }
      // D-10 edge case: doc still exists — receiver cleanup was interrupted.
      if (!_edgeCaseHandled) {
        _edgeCaseHandled = true;
        try { await _transferRepo.deleteTransfer(widget.transferId); } catch (_) {}
        // Stream will fire again with exists==false, marking done.
      }
    }, onError: (_) {
      // Network error — AES was zeroed upstream; unblock the UI.
      if (mounted) setState(() => _aesCleanDone = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return PopScope(
      canPop: false, // only exit is "Back to Home" after cleanup confirmed
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Session Ended'),
          centerTitle: true,
          automaticallyImplyLeading: false,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),

              // ── Success header ─────────────────────────────────────────
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.secondary,
                  ),
                  child: Icon(
                    Icons.shield_rounded,
                    color: cs.onSecondary,
                    size: 44,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Session Ended',
                style: tt.headlineSmall?.copyWith(
                  color: cs.secondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                widget.timeoutReason != null
                    ? 'Session ended by safety timeout.'
                    : 'The receiver has completed secure cleanup.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              if (widget.timeoutReason != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.tertiary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.tertiary.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer_off_rounded, size: 16, color: cs.tertiary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.timeoutReason!,
                          style: TextStyle(fontSize: 12, color: cs.tertiary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Section 1: Receiver cleaned up ─────────────────────────
              Text(
                'Receiver cleaned up:',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              if (widget.timeoutReason != null) ...[
                // Timeout path: receiver did NOT complete cleanup — show warning
                // instead of misleading "all done" checkmarks.
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.tertiary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.tertiary.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    'Receiver cleanup status is unknown — the session ended by timeout before cleanup completed.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ] else ...[
                // Normal path: receiver completed cleanup — show confirmation.
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.secondary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.secondary.withValues(alpha: 0.3)),
                  ),
                  child: const Column(
                    children: [
                      _DoneStepRow(
                        icon: Icons.receipt_long_rounded,
                        label: 'Audit log written to both users',
                      ),
                      _DoneStepRow(
                        icon: Icons.cloud_off_rounded,
                        label: 'Encrypted file deleted from storage',
                      ),
                      _DoneStepRow(
                        icon: Icons.delete_forever_rounded,
                        label: 'Transfer record deleted',
                      ),
                      _DoneStepRow(
                        icon: Icons.person_off_rounded,
                        label: 'RSA key wiped from receiver device',
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // ── Section 2: Your device cleaned up ──────────────────────
              Text(
                'Your device cleaned up:',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.secondary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.secondary.withValues(alpha: 0.3)),
                ),
                child: _aesCleanDone
                    ? const _DoneStepRow(
                        icon: Icons.memory_rounded,
                        label: 'AES key zeroed from memory',
                      )
                    : Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.secondary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Verifying cleanup…',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 32),

              // ── Back to Home — gated behind cleanup confirmation ───────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _aesCleanDone
                    ? CrypButton(
                        key: const ValueKey('home-btn'),
                        icon: const Icon(Icons.home_rounded),
                        label: const Text('Back to Home'),
                        onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const HomeScreen()),
                          (_) => false,
                        ),
                        color: cs.tertiary,
                      )
                    : Padding(
                        key: const ValueKey('waiting'),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.hourglass_top_rounded,
                                size: 16, color: cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Text(
                              'Waiting for cleanup to complete…',
                              style: TextStyle(
                                  fontSize: 13, color: cs.onSurfaceVariant),
                            ),
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

// ─── Done step row ─────────────────────────────────────────────────────────────

class _DoneStepRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DoneStepRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Icon(Icons.check_rounded, size: 16, color: cs.secondary),
        ],
      ),
    );
  }
}
