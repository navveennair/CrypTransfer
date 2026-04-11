import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── StepCard ─────────────────────────────────────────────────────────────────
// Shared step card used by SenderScreen and ReceiverScreen.
// Completed step → green border + green checkmark circle.
// Active step    → purple border + purple number circle.
// Locked step    → grey border + grey number circle.

class StepCard extends StatelessWidget {
  final int step;
  final String title;
  final bool done;
  final Widget child;

  const StepCard({
    super.key,
    required this.step,
    required this.title,
    required this.done,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done ? Colors.green.shade400 : cs.outlineVariant,
          width: done ? 1.5 : 1.0,
        ),
        color: done
            ? Colors.green.withValues(alpha: 0.05)
            : cs.surfaceContainerLow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? Colors.green.shade600 : cs.primary,
                ),
                child: Center(
                  child: done
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text(
                          '$step',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ─── UserAvatar ───────────────────────────────────────────────────────────────

class UserAvatar extends StatelessWidget {
  final String username;
  final double radius;

  const UserAvatar({
    super.key,
    required this.username,
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primaryContainer,
      child: Text(
        username.isNotEmpty ? username[0].toUpperCase() : '?',
        style: TextStyle(
          color: cs.onPrimaryContainer,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.85,
        ),
      ),
    );
  }
}

// ─── BottomSheetHandle ────────────────────────────────────────────────────────

class BottomSheetHandle extends StatelessWidget {
  const BottomSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// ─── StatusBanner ─────────────────────────────────────────────────────────────
// Animated fade-in banner for incoming file / session events.

class StatusBanner extends StatefulWidget {
  final String message;
  final VoidCallback? onView;

  const StatusBanner({super.key, required this.message, this.onView});

  @override
  State<StatusBanner> createState() => _StatusBannerState();
}

class _StatusBannerState extends State<StatusBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.deepPurple.shade700,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.file_download_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            if (widget.onView != null)
              TextButton(
                onPressed: widget.onView,
                style: TextButton.styleFrom(
                    foregroundColor: Colors.white70),
                child: const Text('View'),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── SecurityBadge ────────────────────────────────────────────────────────────

class SecurityBadge extends StatelessWidget {
  final String label;

  const SecurityBadge(
      {super.key, this.label = 'End-to-end encrypted'});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_outline_rounded,
            size: 13, color: Colors.green),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.green,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
