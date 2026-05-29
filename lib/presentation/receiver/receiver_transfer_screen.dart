import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/security_lifecycle_mixin.dart';
import '../../core/utils/session_manager.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/transfer_repository.dart';
import '../home/home_screen.dart';
import 'decrypt_screen.dart';

// ─── ReceiverTransferScreen ───────────────────────────────────────────────────
// Shown between the incoming-file dialog and DecryptScreen.
// Displays animated status steps while loading transfer metadata.

class ReceiverTransferScreen extends StatefulWidget {
  final String transferId;
  final String fileName; // passed immediately from Firestore change doc
  final SessionManager sessionManager; // kill-switch propagation

  const ReceiverTransferScreen({
    super.key,
    required this.transferId,
    required this.fileName,
    required this.sessionManager,
  });

  @override
  State<ReceiverTransferScreen> createState() => _ReceiverTransferScreenState();
}

// ─── Status step ──────────────────────────────────────────────────────────────

class _StatusStep {
  final String label;
  bool done = false;
  bool active = false;

  _StatusStep(this.label);
}

// ─── State ────────────────────────────────────────────────────────────────────

class _ReceiverTransferScreenState extends State<ReceiverTransferScreen>
    with SingleTickerProviderStateMixin, SecurityLifecycleMixin<ReceiverTransferScreen> {
  final _repo = TransferRepository();
  final _auth = AuthRepository();

  // Bounce animation for the download icon
  late AnimationController _bounceCtrl;
  late Animation<double> _bounceAnim;

  String _senderUsername = '';
  int _fileSize = 0;
  bool _metadataLoaded = false;

  bool _allStepsDone = false;

  /// Set to true in [dispose] so that pending [Future.delayed] chains in
  /// [_runSteps] abort cleanly without touching a disposed widget or
  /// animation controller.
  bool _disposed = false;

  /// Set to true when [SessionState.terminated] fires mid-screen; blocks
  /// further UI progression and triggers immediate navigation away.
  bool _cancelled = false;

  bool _aborting = false; // true while our own abort is in flight
  StreamSubscription<DocumentSnapshot>? _failedStatusSub;

  late final List<_StatusStep> _steps = [
    _StatusStep('📡  Establishing secure connection…'),
    _StatusStep('🔐  Verifying encryption parameters…'),
    _StatusStep('✅  Ready to decrypt'),
  ];

  @override
  void initState() {
    super.initState();

    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _bounceAnim = Tween<double>(begin: 0, end: -12).animate(
      CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeInOut),
    );

    // Wire up kill-switch: pop immediately if SessionManager fires terminated.
    widget.sessionManager.stateNotifier.addListener(_onSessionStateChanged);

    _watchTransferStatus();
    _loadMetadata();
    _runSteps();
  }

  @override
  void dispose() {
    _disposed = true;
    _failedStatusSub?.cancel();
    widget.sessionManager.stateNotifier.removeListener(_onSessionStateChanged);
    _bounceCtrl.dispose();
    super.dispose(); // SecurityLifecycleMixin.dispose() → wipeAll()
  }

  // ─── Sender-abort stream watcher ────────────────────────────────────────

  void _watchTransferStatus() {
    _failedStatusSub = _repo
        .watchTransferStatus(widget.transferId)
        .listen((snap) {
      if (!snap.exists) return;
      final status = snap.data()?['status'] as String?;
      if (status == 'failed' && !_aborting && !_cancelled && mounted) {
        _cancelled = true;
        wipeAll();
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: const Text('Transfer aborted — sender terminated the tunnel'),
              backgroundColor: Theme.of(context).colorScheme.tertiary,
              duration: const Duration(seconds: 4),
            ),
          );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
        );
      }
    });
  }

  // ─── Abort dialog ────────────────────────────────────────────────────────

  Future<void> _showAbortDialog() async {
    if (_aborting || _cancelled) return;
    final abort = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Abort Transfer?'),
        content: const Text(
          'This will destroy all cryptographic material and collapse the secure '
          'tunnel. The sender will be notified that the transfer failed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Abort & Destroy'),
          ),
        ],
      ),
    );
    if (abort == true && mounted) {
      await _abortSessionDueToDisconnect();
    }
  }

  Future<void> _abortSessionDueToDisconnect() async {
    if (_aborting || _cancelled) return;
    _aborting = true;
    _cancelled = true;
    try {
      await _repo.updateTransferStatus(widget.transferId, 'failed');
    } catch (_) {
      // Wipe proceeds regardless.
    }
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

  // ─── Kill-switch handler ─────────────────────────────────────────────────

  void _onSessionStateChanged() {
    if (widget.sessionManager.state == SessionState.terminated && mounted) {
      _cancelled = true;
      wipeAll();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transfer cancelled — session wiped')),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // ─── Load transfer metadata ──────────────────────────────────────────────

  Future<void> _loadMetadata() async {
    try {
      final transfer = await _repo.getTransfer(widget.transferId);
      final profile = await _auth.getUserProfile(transfer.senderId);
      if (mounted) {
        setState(() {
          _senderUsername = profile?.username ?? 'Unknown';
          _fileSize = transfer.fileSize;
          _metadataLoaded = true;
        });
      }
    } catch (_) {
      // Non-fatal — metadata display degrades gracefully.
      if (mounted) setState(() => _metadataLoaded = true);
    }
  }

  // ─── Run status steps sequentially ──────────────────────────────────────

  Future<void> _runSteps() async {
    for (int i = 0; i < _steps.length; i++) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted || _disposed || _cancelled) return;
      setState(() => _steps[i].active = true);

      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || _disposed || _cancelled) return;
      setState(() {
        _steps[i].active = false;
        _steps[i].done = true;
      });
    }

    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted && !_disposed && !_cancelled) setState(() => _allStepsDone = true);
  }

  // ─── Navigate to DecryptScreen ───────────────────────────────────────────

  void _proceed() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DecryptScreen(transferId: widget.transferId),
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) => _showAbortDialog(),
      child: Scaffold(
        appBar: AppBar(
          title: Text('Incoming File',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          centerTitle: true,
          automaticallyImplyLeading: false,
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Bouncing download icon ──────────────────────────────────
              AnimatedBuilder(
                animation: _bounceAnim,
                builder: (_, child) => Transform.translate(
                  offset: Offset(0, _bounceAnim.value),
                  child: child,
                ),
                child: Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primaryContainer,
                    ),
                    child: Icon(Icons.file_download_rounded,
                        size: 46, color: cs.primary),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'Incoming File',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700, fontSize: 22),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 20),

              // ── File info card ──────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.insert_drive_file_rounded,
                      label: 'File',
                      value: widget.fileName,
                      cs: cs,
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.data_usage_rounded,
                      label: 'Size',
                      value: _metadataLoaded && _fileSize > 0
                          ? _fmtSize(_fileSize)
                          : '—',
                      cs: cs,
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.person_rounded,
                      label: 'From',
                      value: _metadataLoaded
                          ? '@$_senderUsername'
                          : '—',
                      cs: cs,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── Status steps ────────────────────────────────────────────
              ..._steps.map((step) => _StepTile(step: step, cs: cs)),

              const Spacer(),

              // ── Proceed button (appears after all steps complete) ───────
              AnimatedOpacity(
                opacity: _allStepsDone ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: FilledButton.icon(
                  icon: const Icon(Icons.lock_open_rounded),
                  label: const Text('Proceed to Decrypt'),
                  onPressed: _allStepsDone ? _proceed : null,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Step tile ────────────────────────────────────────────────────────────────

class _StepTile extends StatelessWidget {
  final _StatusStep step;
  final ColorScheme cs;

  const _StepTile({required this.step, required this.cs});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Widget indicator;

    if (step.done) {
      bg = cs.secondary.withValues(alpha: 0.08);
      fg = cs.secondary;
      indicator =
          Icon(Icons.check_circle_rounded, color: cs.secondary, size: 20);
    } else if (step.active) {
      bg = cs.primaryContainer.withValues(alpha: 0.5);
      fg = cs.primary;
      indicator = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.primary),
      );
    } else {
      bg = cs.surfaceContainerLow;
      fg = cs.onSurfaceVariant;
      indicator = Icon(Icons.radio_button_unchecked,
          color: cs.outlineVariant, size: 20);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: step.done
              ? cs.secondary.withValues(alpha: 0.4)
              : step.active
                  ? cs.primary.withValues(alpha: 0.4)
                  : cs.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              step.label,
              style: TextStyle(
                fontSize: 14,
                color: step.done || step.active ? fg : cs.onSurfaceVariant,
                fontWeight: step.done || step.active
                    ? FontWeight.w600
                    : FontWeight.normal,
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

// ─── Info row ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme cs;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 10),
        SizedBox(
          width: 52,
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
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
