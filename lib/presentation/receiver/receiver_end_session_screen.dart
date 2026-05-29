import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/security_lifecycle_mixin.dart';
import '../../data/repositories/cleanup_repository.dart';
import '../../data/repositories/key_repository.dart';
import '../../data/repositories/transfer_repository.dart';
import '../../data/services/encryption_service.dart';
import '../home/home_screen.dart';
import '../widgets/shared_widgets.dart';

class ReceiverEndSessionScreen extends StatefulWidget {
  final String transferId;
  final String fileName;
  final int fileSize;
  final String senderUsername;
  final String senderId;
  final String receiverId;
  final DateTime transferredAt;

  // No aesKey — plaintext already wiped in DecryptScreen._saveAndWipe()
  const ReceiverEndSessionScreen({
    super.key,
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.senderUsername,
    required this.senderId,
    required this.receiverId,
    required this.transferredAt,
  });

  @override
  State<ReceiverEndSessionScreen> createState() =>
      _ReceiverEndSessionScreenState();
}

// ─── Screen states ────────────────────────────────────────────────────────────

enum _Phase { ready, waitingForSender, cleaning, done }

// ─── Cleanup step descriptor ──────────────────────────────────────────────────

class _Step {
  final IconData icon;
  final String label;
  bool done = false;
  bool active = false;

  _Step({required this.icon, required this.label});
}

// ─── State ────────────────────────────────────────────────────────────────────

class _ReceiverEndSessionScreenState extends State<ReceiverEndSessionScreen>
    with SingleTickerProviderStateMixin,
        SecurityLifecycleMixin<ReceiverEndSessionScreen> {
  _Phase _phase = _Phase.ready;
  String? _error;

  late AnimationController _doneCtrl;
  late Animation<double> _doneScale;

  // 4 steps matching D-03 sequence — audit log FIRST, closeReceiverSession LAST
  late final List<_Step> _steps = [
    _Step(icon: Icons.receipt_long_rounded,   label: 'Write immutable audit log'),
    _Step(icon: Icons.cloud_off_rounded,      label: 'Delete encrypted file from storage'),
    _Step(icon: Icons.delete_forever_rounded, label: 'Delete transfer record and handshake'),
    _Step(icon: Icons.person_off_rounded,     label: 'Wipe RSA keys from device and Firestore'),
  ];

  final _cleanupRepo = CleanupRepository();
  final _transferRepo = TransferRepository();
  StreamSubscription<DocumentSnapshot>? _docListener;

  @override
  void initState() {
    super.initState();
    // No buffers to register — plaintext wiped upstream in DecryptScreen._saveAndWipe()
    // Mixin applied per D-14 as defensive safety net
    _doneCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _doneScale = CurvedAnimation(parent: _doneCtrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _docListener?.cancel();
    _doneCtrl.dispose();
    super.dispose();
  }

  // ─── Cleanup sequence ───────────────────────────────────────────────────────
  // D-03 security-critical order:
  //   Step 0: auditBatch.commit()  — MUST be first (immutable record before any deletion)
  //   Step 1: deleteStorageFile()  — Storage first (large asset, non-atomic)
  //   Step 2: endSessionCleanup()  — WriteBatch: transfers + handshakes + selectedSenderUid
  //                                  (This deletion fires the Firestore stream on sender side)
  //   Step 3: closeReceiverSession — RSA keys LAST (broader handshake sweep — idempotent after step 2)
  //
  // WARNING: Reversing steps 2 and 3 causes null handshakeId (Pitfall 2 — RESEARCH.md).

  // ─── Turn 1: Receiver initiates cleanup ────────────────────────────────────

  Future<void> _initiateCleanup() async {
    setState(() {
      _phase = _Phase.waitingForSender;
      _error = null;
    });
    try {
      // Turn 1: Write cleanup_initiated flag and receiver's audit log
      await _cleanupRepo.initiateReceiverCleanup(
        transferId: widget.transferId,
        receiverId: widget.receiverId,
        senderId: widget.senderId,
        senderUsername: widget.senderUsername,
        fileName: widget.fileName,
        fileSize: widget.fileSize,
      );

      // Watch for sender cleanup confirmation and doc deletion
      _docListener = _cleanupRepo
          .watchTransferForDeletion(widget.transferId)
          .listen(_onTransferDocUpdate);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.ready;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  // ─── Turn 3 trigger: stream listener waiting for sender wipe confirmation ──

  void _onTransferDocUpdate(DocumentSnapshot snapshot) {
    if (!snapshot.exists) return; // doc gone — Turn 4 cleanup already happened
    final data = snapshot.data()! as Map<String, dynamic>;
    final senderCleanedUp = data['senderCleanedUp'] as bool? ?? false;
    final aesKey = data['encryptedAESKey'] as String? ?? '';
    if (senderCleanedUp && aesKey.isEmpty) {
      _docListener?.cancel();
      _docListener = null;
      _runFinalCleanup();
    }
  }

  // ─── Turn 3: Run full cleanup sequence (was _endSession) ───────────────────
  // D-03 security-critical order:
  //   Step 0: auditBatch.commit()  — MUST be first (immutable record before any deletion)
  //   Step 1: deleteStorageFile()  — Storage first (large asset, non-atomic)
  //   Step 2: endSessionCleanup()  — WriteBatch: transfers + handshakes + selectedSenderUid
  //                                  (This deletion fires the Firestore stream on sender side)
  //   Step 3: closeReceiverSession — RSA keys LAST (broader handshake sweep — idempotent after step 2)
  //
  // WARNING: Reversing steps 2 and 3 causes null handshakeId (Pitfall 2 — RESEARCH.md).

  Future<void> _runFinalCleanup() async {
    setState(() {
      _phase = _Phase.cleaning;
      _error = null;
    });

    if (widget.transferId.isEmpty || widget.receiverId.isEmpty) {
      setState(() {
        _phase = _Phase.ready;
        _error = 'Missing session identifiers. Cleanup aborted.';
      });
      return;
    }

    Future<void> tick(int i) async {
      setState(() {
        _steps[i].active = true;
      });
      await Future.delayed(const Duration(milliseconds: 200));
    }

    Future<void> done(int i) async {
      setState(() {
        _steps[i].active = false;
        _steps[i].done = true;
      });
      await Future.delayed(const Duration(milliseconds: 150));
    }

    try {
      // ── Step 0: Write immutable audit log FIRST (D-03) ──
      await tick(0);
      final receiverUsername =
          FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown';
      await _transferRepo.writeFinalAuditLog(
        senderId: widget.senderId,
        receiverId: widget.receiverId,
        senderUsername: widget.senderUsername,
        receiverUsername: receiverUsername,
        fileName: widget.fileName,
        fileSize: widget.fileSize,
      );
      await done(0);

      // ── Step 1: Delete encrypted file from Firebase Storage ─────────────────
      await tick(1);
      await _transferRepo.deleteStorageFile(widget.transferId);
      await done(1);

      // ── Step 2: Atomic WriteBatch — delete transfer doc + handshake ────────
      await tick(2);
      final keyRepo = KeyRepository();
      final handshakeId = await keyRepo.getActiveHandshakeDocId(
        senderUid: widget.senderId,
        receiverUid: widget.receiverId,
      );
      await keyRepo.endSessionCleanup(
        transferId: widget.transferId,
        handshakeId: handshakeId,
        receiverId: widget.receiverId,
      );
      await done(2);

      // ── Step 3: Full RSA session close — LAST ────────────────────────────
      await tick(3);
      await EncryptionService.closeReceiverSession(widget.receiverId);
      await done(3);

      // ── Cleanup complete ────────────────────────────────────────────────────
      if (mounted) {
        setState(() {
          _phase = _Phase.done;
        });
        _doneCtrl.forward();

        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.ready;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';

  String _fmtTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: _phase == _Phase.ready,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Session Summary',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
          automaticallyImplyLeading: _phase != _Phase.cleaning && _phase != _Phase.waitingForSender,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: _phase == _Phase.done
              ? _buildDone(cs)
              : _phase == _Phase.cleaning
                  ? _buildCleaning(cs)
                  : _phase == _Phase.waitingForSender
                      ? _buildWaitingForSender(cs)
                      : _buildReady(cs),
        ),
      ),
    );
  }

  // ─── Ready view (summary + warning + button) ─────────────────────────────

  Widget _buildReady(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Session summary card ──────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.summarize_rounded, color: cs.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Transfer Summary',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SummaryRow(
                icon: Icons.insert_drive_file_rounded,
                label: 'File',
                value: widget.fileName,
                color: cs.primary,
              ),
              _SummaryRow(
                icon: Icons.data_usage_rounded,
                label: 'Size',
                value: _fmtSize(widget.fileSize),
                color: cs.primary,
              ),
              _SummaryRow(
                icon: Icons.calendar_today_rounded,
                label: 'Date',
                value: _fmtDate(widget.transferredAt),
                color: cs.primary,
              ),
              _SummaryRow(
                icon: Icons.access_time_rounded,
                label: 'Time',
                value: _fmtTime(widget.transferredAt),
                color: cs.primary,
              ),
              const Divider(height: 24),
              _SummaryRow(
                icon: Icons.upload_rounded,
                label: 'Sender',
                value: '@${widget.senderUsername}',
                color: cs.primary,
              ),
              _SummaryRow(
                icon: Icons.download_rounded,
                label: 'Receiver',
                value: '@${FirebaseAuth.instance.currentUser?.displayName ?? 'Me'}',
                color: cs.tertiary,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Warning banner ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.error.withValues(alpha: 0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: cs.error, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Permanent Deletion Warning',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: cs.error,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Once the session ends, all transfer data will be '
                      'permanently deleted — the encrypted file, RSA keys, '
                      'and transfer record cannot be recovered.',
                      style: TextStyle(
                          color: cs.error,
                          fontSize: 13,
                          height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Error (if retry) ──────────────────────────────────────────────
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .errorContainer
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── End Session button ────────────────────────────────────────────
        CrypButton(
          icon: const Icon(Icons.lock_clock_rounded),
          label: Text(_error != null ? 'Retry End Session' : 'End Session'),
          onPressed: _initiateCleanup,
          color: cs.error,
        ),
      ],
    );
  }

  // ─── Waiting for sender view ────────────────────────────────────────────

  Widget _buildWaitingForSender(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        Text(
          'Waiting for Sender…',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 22),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Waiting for sender to securely erase cryptographic keys…',
          style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ─── Cleaning view (step progress) ──────────────────────────────────────

  Widget _buildCleaning(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text(
          'Ending Session…',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700, fontSize: 22),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Securely wiping all transfer data.',
          style: TextStyle(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),

        // ── Step list ─────────────────────────────────────────────────────
        ...List.generate(_steps.length, (i) {
          final step = _steps[i];
          return _CleanStepTile(
            icon: step.icon,
            label: step.label,
            done: step.done,
            active: step.active,
          );
        }),
      ],
    );
  }

  // ─── Done view ──────────────────────────────────────────────────────────

  Widget _buildDone(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),

        // ── Animated success tick ─────────────────────────────────────────
        ScaleTransition(
          scale: _doneScale,
          child: Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.secondary,
              ),
              child: const Icon(Icons.shield_rounded,
                  color: Colors.white, size: 52),
            ),
          ),
        ),
        const SizedBox(height: 24),

        Text(
          'Session Ended',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 24,
            color: cs.secondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'All transfer data has been permanently deleted.\n'
          'A minimal audit log has been retained.',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant, height: 1.6),
        ),

        const SizedBox(height: 32),

        // ── Completed steps summary ───────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.secondary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.secondary.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: _steps
                .map((s) => _DoneStepRow(icon: s.icon, label: s.label))
                .toList(),
          ),
        ),

        const SizedBox(height: 32),

        CrypButton(
          icon: const Icon(Icons.home_rounded),
          label: const Text('Back to Home'),
          onPressed: () => Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (_) => false,
          ),
          color: cs.secondary,
        ),
      ],
    );
  }
}

// ─── Summary row ──────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Cleaning step tile ───────────────────────────────────────────────────────

class _CleanStepTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool done;
  final bool active;

  const _CleanStepTile({
    required this.icon,
    required this.label,
    required this.done,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color bg;
    Color fg;
    Widget indicator;

    if (done) {
      bg = cs.secondary.withValues(alpha: 0.1);
      fg = cs.secondary;
      indicator = Icon(Icons.check_circle_rounded,
          color: cs.secondary, size: 22);
    } else if (active) {
      bg = cs.primaryContainer.withValues(alpha: 0.5);
      fg = cs.primary;
      indicator = SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.primary),
      );
    } else {
      bg = cs.surfaceContainerLow;
      fg = cs.onSurfaceVariant;
      indicator = Icon(Icons.radio_button_unchecked,
          color: cs.outlineVariant, size: 22);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: done
              ? cs.secondary.withValues(alpha: 0.4)
              : active
                  ? cs.primary.withValues(alpha: 0.4)
                  : cs.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: done || active ? fg : cs.onSurfaceVariant,
                fontWeight: done || active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 8),
          indicator,
        ],
      ),
    );
  }
}

// ─── Done step row ────────────────────────────────────────────────────────────

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
            child: Text(label,
                style: const TextStyle(fontSize: 13)),
          ),
          Icon(Icons.check_rounded,
              size: 16, color: cs.secondary),
        ],
      ),
    );
  }
}
