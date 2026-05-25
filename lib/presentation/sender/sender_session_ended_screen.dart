import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
/// NO aesKey constructor arg — the AES key was zeroed by wipeAll() in
/// [TransferProgressScreen] before navigation (D-07).
class SenderSessionEndedScreen extends StatefulWidget {
  final String transferId; // D-10 edge-case check
  final String fileName;
  final int fileSize;
  final String receiverUsername;
  final String senderId;
  final String receiverId;
  final String? timeoutReason; // null = normal cleanup; non-null = timeout message

  const SenderSessionEndedScreen({
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
  State<SenderSessionEndedScreen> createState() =>
      _SenderSessionEndedScreenState();
}

class _SenderSessionEndedScreenState extends State<SenderSessionEndedScreen>
    with SecurityLifecycleMixin<SenderSessionEndedScreen> {
  final _transferRepo = TransferRepository();
  bool _aesCleanDone = false;

  @override
  void initState() {
    super.initState();
    // No buffers to register — AES already zeroed upstream in TransferProgressScreen.
    _checkAndMarkDone();
  }

  Future<void> _checkAndMarkDone() async {
    // D-10: edge-case safety net — verify transfer doc is already gone.
    // Normal path: doc is deleted by ReceiverEndSessionScreen step 2.
    // Edge case: receiver cleanup was interrupted before WriteBatch committed.
    try {
      final exists = await _transferRepo.getTransferDoc(widget.transferId);
      if (exists) {
        await _transferRepo.deleteTransfer(widget.transferId);
      }
    } catch (_) {
      // D-10 edge-case cleanup failed — doc may already be gone or network
      // is unavailable. AES key was already zeroed upstream in TransferProgressScreen.
    } finally {
      if (mounted) setState(() => _aesCleanDone = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false, // only exit is "Back to Home"
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Session Ended',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
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
                    color: Colors.green.shade600,
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Session Ended',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 22,
                  color: Colors.green.shade700,
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
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer_off_rounded, size: 16, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.timeoutReason!,
                          style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
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
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              if (widget.timeoutReason != null) ...[
                // Timeout path: receiver did NOT complete cleanup — show warning
                // instead of misleading "all done" checkmarks.
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.orange.shade300),
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
                    color: Colors.green.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.green.shade200),
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
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.green.shade200),
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
                              color: Colors.green.shade600,
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

              // ── Back to Home ───────────────────────────────────────────
              CrypButton(
                icon: const Icon(Icons.home_rounded),
                label: const Text('Back to Home'),
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (_) => false,
                ),
                color: Colors.green.shade600,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Done step row ─────────────────────────────────────────────────────────────
// Copied verbatim from end_session_screen.dart lines 679–703.

class _DoneStepRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DoneStepRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.green.shade600),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Icon(Icons.check_rounded, size: 16, color: Colors.green.shade600),
        ],
      ),
    );
  }
}
