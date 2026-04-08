import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../home/home_screen.dart';

class EndSessionScreen extends StatefulWidget {
  final String transferId;
  final String fileName;
  final int fileSize;
  final String senderUsername;
  final String receiverUsername;
  final String senderId;
  final String receiverId;
  final DateTime transferredAt;

  /// The raw AES key bytes — will be zeroed during cleanup.
  final Uint8List? aesKey;

  const EndSessionScreen({
    super.key,
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.senderUsername,
    required this.receiverUsername,
    required this.senderId,
    required this.receiverId,
    required this.transferredAt,
    this.aesKey,
  });

  @override
  State<EndSessionScreen> createState() => _EndSessionScreenState();
}

// ─── Screen states ────────────────────────────────────────────────────────────

enum _Phase { ready, cleaning, done }

// ─── Cleanup step descriptor ──────────────────────────────────────────────────

class _Step {
  final IconData icon;
  final String label;
  bool done = false;
  bool active = false;

  _Step({required this.icon, required this.label});
}

// ─── State ────────────────────────────────────────────────────────────────────

class _EndSessionScreenState extends State<EndSessionScreen>
    with SingleTickerProviderStateMixin {
  _Phase _phase = _Phase.ready;
  String? _error;

  late AnimationController _doneCtrl;
  late Animation<double> _doneScale;

  late final List<_Step> _steps = [
    _Step(icon: Icons.memory_rounded,        label: 'Zero AES key from memory'),
    _Step(icon: Icons.cloud_off_rounded,     label: 'Delete encrypted file from storage'),
    _Step(icon: Icons.receipt_long_rounded,  label: 'Write audit log'),
    _Step(icon: Icons.delete_forever_rounded,label: 'Delete transfer record'),
  ];

  @override
  void initState() {
    super.initState();
    _doneCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _doneScale = CurvedAnimation(parent: _doneCtrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _doneCtrl.dispose();
    super.dispose();
  }

  // ─── Cleanup sequence ───────────────────────────────────────────────────────

  Future<void> _endSession() async {
    setState(() {
      _phase = _Phase.cleaning;
      _error = null;
    });

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
      // ── Step 0: Zero AES key from memory ─────────────────────────────
      await tick(0);
      if (widget.aesKey != null) {
        widget.aesKey!.fillRange(0, widget.aesKey!.length, 0);
      }
      await done(0);

      // ── Step 1: Delete encrypted file from Firebase Storage ──────────
      await tick(1);
      try {
        await FirebaseStorage.instance
            .ref('transfers/${widget.transferId}/encrypted_file')
            .delete();
      } on FirebaseException catch (e) {
        // object-not-found is acceptable — file may already be deleted
        if (e.code != 'object-not-found') rethrow;
      }
      await done(1);

      // ── Step 2: Write minimal audit log ──────────────────────────────
      await tick(2);
      await FirebaseFirestore.instance.collection('transfers_log').add({
        'senderId': widget.senderId,
        'receiverId': widget.receiverId,
        'participants': [widget.senderId, widget.receiverId],
        'fileName': widget.fileName,
        'transferDate': _fmtDate(widget.transferredAt),
        'transferTime': _fmtTime(widget.transferredAt),
        'status': 'completed',
        'loggedAt': FieldValue.serverTimestamp(),
      });
      await done(2);

      // ── Step 3: Delete Firestore transfer document ───────────────────
      await tick(3);
      await FirebaseFirestore.instance
          .collection('transfers')
          .doc(widget.transferId)
          .delete();
      await done(3);

      // ── All done ──────────────────────────────────────────────────────
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        setState(() => _phase = _Phase.done);
        _doneCtrl.forward();
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
      canPop: _phase != _Phase.cleaning,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Session Summary',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
          automaticallyImplyLeading: _phase != _Phase.cleaning,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: _phase == _Phase.done
              ? _buildDone(cs)
              : _phase == _Phase.cleaning
                  ? _buildCleaning(cs)
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
                color: Colors.indigo.shade600,
              ),
              _SummaryRow(
                icon: Icons.download_rounded,
                label: 'Receiver',
                value: '@${widget.receiverUsername}',
                color: Colors.deepPurple.shade600,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Warning banner ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.red.shade300),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.red.shade700, size: 22),
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
                        color: Colors.red.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Once the session ends, all transfer data will be '
                      'permanently deleted — the encrypted file, AES key, '
                      'and transfer record cannot be recovered.',
                      style: TextStyle(
                          color: Colors.red.shade800,
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
        FilledButton.icon(
          icon: const Icon(Icons.lock_clock_rounded),
          label: Text(_error != null ? 'Retry End Session' : 'End Session'),
          onPressed: _endSession,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
          ),
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
                color: Colors.green.shade600,
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
            color: Colors.green.shade700,
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
            color: Colors.green.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
            children: _steps
                .map((s) => _DoneStepRow(icon: s.icon, label: s.label))
                .toList(),
          ),
        ),

        const SizedBox(height: 32),

        FilledButton.icon(
          icon: const Icon(Icons.home_rounded),
          label: const Text('Back to Home'),
          onPressed: () => Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (_) => false,
          ),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade600,
            minimumSize: const Size.fromHeight(52),
          ),
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
      bg = Colors.green.withValues(alpha: 0.1);
      fg = Colors.green.shade700;
      indicator = Icon(Icons.check_circle_rounded,
          color: Colors.green.shade600, size: 22);
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
              ? Colors.green.shade300
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.green.shade600),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13)),
          ),
          Icon(Icons.check_rounded,
              size: 16, color: Colors.green.shade600),
        ],
      ),
    );
  }
}
