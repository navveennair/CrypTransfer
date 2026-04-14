import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/session_manager.dart';

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

// ─── CrypButton ───────────────────────────────────────────────────────────────
// Full-width primary action button with a pressed 3-D depth effect.
// Use in place of FilledButton / FilledButton.icon for all primary CTAs.
//
// Parameters:
//   color         — face colour when enabled (defaults to cs.primary)
//   disabledColor — face colour when onPressed == null but the button should
//                   remain coloured (e.g. loading spinners). Omit for the
//                   standard grey disabled appearance.
//   depth         — height of the 3-D shadow layer in logical pixels (default 4)
//   height        — total face height (default 52, matching Size.fromHeight(52))
//   sessionState  — when non-null (and != SessionState.open), overrides the
//                   button colour + content to reflect the live session state:
//                     locked     → amber  + lock icon
//                     decrypting → primary + spinner (no label)
//                     terminated → error   + block icon

class CrypButton extends StatefulWidget {
  final Widget label;
  final Widget? icon;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? disabledColor;
  final double depth;
  final double height;
  final SessionState? sessionState;

  const CrypButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.color,
    this.disabledColor,
    this.depth = 4.0,
    this.height = 52.0,
    this.sessionState,
  });

  @override
  State<CrypButton> createState() => _CrypButtonState();
}

class _CrypButtonState extends State<CrypButton> {
  bool _pressed = false;

  static Color _shadowOf(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0))
        .toColor();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.onPressed != null) setState(() => _pressed = true);
  }

  void _onTapUp(TapUpDetails _) {
    if (!mounted) return;
    setState(() => _pressed = false);
    widget.onPressed?.call();
  }

  void _onTapCancel() {
    if (mounted) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;

    // A non-open session state suppresses interaction regardless of onPressed.
    final sessionActive = widget.sessionState != null &&
        widget.sessionState != SessionState.open;
    final effectivelyEnabled = enabled && !sessionActive;

    Color face;
    Color shadow;
    Color fg;

    if (effectivelyEnabled) {
      face = widget.color ?? cs.primary;
      shadow = _shadowOf(face);
      fg = Colors.white;
    } else if (widget.disabledColor != null && !sessionActive) {
      face = widget.disabledColor!;
      shadow = _shadowOf(face);
      fg = Colors.white.withValues(alpha: 0.70);
    } else {
      face = cs.onSurface.withValues(alpha: 0.12);
      shadow = cs.onSurface.withValues(alpha: 0.06);
      fg = cs.onSurface.withValues(alpha: 0.38);
    }

    // Session-state colour overrides — applied after base colours so they
    // always win, even when the button has a custom [color].
    if (sessionActive) {
      switch (widget.sessionState!) {
        case SessionState.locked:
          face = Colors.amber.shade700;
          shadow = _shadowOf(face);
          fg = Colors.white;
        case SessionState.decrypting:
          face = cs.primary;
          shadow = _shadowOf(face);
          fg = Colors.white.withValues(alpha: 0.85);
        case SessionState.terminated:
          face = cs.error;
          shadow = _shadowOf(face);
          fg = Colors.white;
        case SessionState.open:
          break;
      }
    }

    final d = widget.depth;
    final h = widget.height;
    final shift = (_pressed && effectivelyEnabled) ? d : 0.0;

    // Content varies by session state.
    final Widget stateContent;
    switch (widget.sessionState) {
      case SessionState.decrypting:
        stateContent = SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
        );
      case SessionState.locked:
        stateContent = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, color: fg, size: 18),
            const SizedBox(width: 6),
            widget.label,
          ],
        );
      case SessionState.terminated:
        stateContent = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block_rounded, color: fg, size: 18),
            const SizedBox(width: 6),
            widget.label,
          ],
        );
      default:
        stateContent = widget.icon != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  widget.icon!,
                  const SizedBox(width: 8),
                  widget.label,
                ],
              )
            : widget.label;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: effectivelyEnabled ? _onTapDown : null,
      onTapUp: effectivelyEnabled ? _onTapUp : null,
      onTapCancel: effectivelyEnabled ? _onTapCancel : null,
      child: SizedBox(
        height: h + d,
        child: Stack(
          children: [
            // ── Shadow layer (stationary) ─────────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              top: d,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: shadow,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            // ── Face layer (slides down on press) ─────────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 70),
              curve: Curves.easeOut,
              top: shift,
              left: 0,
              right: 0,
              height: h,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: face,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: DefaultTextStyle.merge(
                    style: GoogleFonts.poppins(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    child: IconTheme(
                      data: IconThemeData(color: fg, size: 20),
                      child: stateContent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
