import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app_theme.dart';
import '../../core/utils/session_manager.dart';

// ─── GlassContainer ───────────────────────────────────────────────────────────
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final Color? color;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 16,
    this.blur = AppTheme.glassBlur,
    this.color,
    this.borderColor,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin,
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: boxShadow ?? [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: color ?? (isDark ? AppTheme.glassBgDark : AppTheme.glassBgLight),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: borderColor ?? (isDark ? AppTheme.glassBorderDark : AppTheme.glassBorderLight),
                width: 1.5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ─── StepCard ─────────────────────────────────────────────────────────────────

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 16),
      child: GlassContainer(
        borderRadius: 24,
        padding: const EdgeInsets.all(20),
        borderColor: done ? cs.secondary.withValues(alpha: 0.3) : null,
        color: done ? cs.secondary.withValues(alpha: isDark ? 0.08 : 0.04) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? cs.secondary : cs.primary,
                    boxShadow: [
                      BoxShadow(
                        color: (done ? cs.secondary : cs.primary).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: done
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : Text(
                            '$step',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: done ? cs.secondary : cs.onSurface),
                ),
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
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
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: cs.primary.withValues(alpha: 0.3), width: 2),
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: cs.primary.withValues(alpha: 0.1),
        child: Text(
          username.isNotEmpty ? username[0].toUpperCase() : '?',
          style: TextStyle(
            color: cs.primary,
            fontWeight: FontWeight.bold,
            fontSize: radius * 0.85,
          ),
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
    final cs = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: _fade,
      child: GlassContainer(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: cs.tertiary.withValues(alpha: 0.2),
        borderColor: cs.tertiary.withValues(alpha: 0.3),
        child: Row(
          children: [
            Icon(Icons.file_download_rounded,
                color: cs.onSurface, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.message,
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            if (widget.onView != null)
              TextButton(
                onPressed: widget.onView,
                style: TextButton.styleFrom(
                    foregroundColor: cs.onSurface),
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.secondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.secondary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded,
              size: 13, color: cs.secondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: cs.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── CrypButton ───────────────────────────────────────────────────────────────

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

  // Returns black or white for maximum contrast against bg (W3C luminance threshold).
  static Color _contrastFg(Color bg) =>
      bg.computeLuminance() > 0.179 ? Colors.black87 : Colors.white;

  void _onTapDown(TapDownDetails _) {
    if (widget.onPressed != null) {
      HapticFeedback.lightImpact();
      setState(() => _pressed = true);
    }
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

    final sessionActive = widget.sessionState != null &&
        widget.sessionState != SessionState.open;
    final effectivelyEnabled = enabled && !sessionActive;

    Color face;
    Color shadow;
    Color fg;

    if (effectivelyEnabled) {
      face = widget.color ?? cs.primary;
      shadow = _shadowOf(face);
      fg = _contrastFg(face);
    } else if (widget.disabledColor != null && !sessionActive) {
      face = widget.disabledColor!;
      shadow = _shadowOf(face);
      fg = _contrastFg(face).withValues(alpha: 0.70);
    } else {
      face = cs.onSurface.withValues(alpha: 0.12);
      shadow = cs.onSurface.withValues(alpha: 0.06);
      fg = cs.onSurface.withValues(alpha: 0.38);
    }

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
    final scale = (_pressed && effectivelyEnabled) ? 0.98 : 1.0;

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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        transform: Matrix4.diagonal3Values(scale, scale, 1.0),
        transformAlignment: Alignment.center,
        child: SizedBox(
          height: h + d,
          child: Stack(
            children: [
            Positioned(
              left: 0,
              right: 0,
              top: d,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: shadow,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
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
                  borderRadius: BorderRadius.circular(16),
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
      ),
    );
  }
}
