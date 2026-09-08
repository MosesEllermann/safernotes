import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:safernotes_app/shared/theme/app_theme.dart';

/// Frosted panel used for every raised surface in the app.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.margin,
    this.enabled = true,
    this.fill,
    this.borderColor,
    this.blur,
    this.showBorder = false,
    this.showShadow = true,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool enabled;
  final Color? fill;
  final Color? borderColor;
  final double? blur;
  final bool showBorder;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final design = context.safernotesTheme;
    final radius = borderRadius ?? BorderRadius.circular(design.controlRadius);
    final sigma = blur ?? design.glassBlur;
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: fill ?? design.glassFill,
        borderRadius: radius,
        border: showBorder
            ? Border.all(
                color: borderColor ?? design.glassStroke,
                width: 1,
              )
            : null,
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ),
    );

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: showShadow
              ? [
                  BoxShadow(
                    color: design.glassShadow,
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: enabled
              ? BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                  child: surface,
                )
              : surface,
        ),
      ),
    );
  }
}

/// Circular frosted control — the favourite/heart affordance on note cards and
/// the small round buttons in the header.
class GlassCircleButton extends StatefulWidget {
  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.size = 44,
    this.iconSize = 20,
    this.selectedColor,
    this.enableBlur = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final double size;
  final double iconSize;
  final Color? selectedColor;
  final bool enableBlur;

  @override
  State<GlassCircleButton> createState() => _GlassCircleButtonState();
}

class _GlassCircleButtonState extends State<GlassCircleButton> {
  var _hovered = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.selectedColor ?? brandLavender;
    final iconColor = widget.onPressed == null
        ? scheme.onSurface.withValues(alpha: 0.35)
        : widget.selected
            ? accent
            : dark
                ? Colors.white.withValues(alpha: 0.92)
                : scheme.onSurface.withValues(alpha: 0.82);
    final control = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.selected
            ? accent.withValues(alpha: dark ? 0.22 : 0.20)
            : _hovered
                ? (dark
                    ? Colors.white.withValues(alpha: 0.16)
                    : Colors.black.withValues(alpha: 0.07))
                : (dark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.04)),
      ),
      child: Icon(
        widget.icon,
        size: widget.iconSize,
        color: iconColor,
      ),
    );
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: widget.onPressed == null
              ? null
              : (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: widget.onPressed == null
              ? null
              : (_) {
                  setState(() => _pressed = false);
                  widget.onPressed?.call();
                },
          child: AnimatedScale(
            scale: _pressed ? 0.92 : (_hovered ? 1.05 : 1),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: ClipOval(
              child: widget.enableBlur
                  ? BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: control,
                    )
                  : control,
            ),
          ),
        ),
      ),
    );
  }
}
