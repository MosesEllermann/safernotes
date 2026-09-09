import 'package:flutter/material.dart';
import 'package:safernotes_app/shared/widgets/app_motion.dart';

class AppIconButton extends StatefulWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.size = 36,
    this.iconSize = 18,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final double size;
  final double iconSize;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  var _hovered = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = widget.selected || _hovered || _pressed;
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
            scale: _pressed ? 0.94 : (_hovered ? 1.04 : 1),
            duration: AppMotion.duration(
              context,
              const Duration(milliseconds: 140),
            ),
            curve: Curves.easeOutCubic,
            child: RepaintBoundary(
              child: AnimatedContainer(
                duration: AppMotion.duration(
                  context,
                  const Duration(milliseconds: 140),
                ),
                curve: Curves.easeOutCubic,
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: active
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                              .withValues(alpha: widget.selected ? 0.16 : 0.10)
                          : Colors.black
                              .withValues(alpha: widget.selected ? 0.10 : 0.06))
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.icon,
                  size: widget.iconSize,
                  color: widget.onPressed == null
                      ? scheme.onSurface.withValues(alpha: 0.38)
                      : widget.selected
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: 0.88),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppIconToggle extends StatelessWidget {
  const AppIconToggle({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      icon: icon,
      tooltip: tooltip,
      selected: selected,
      onPressed: onPressed,
    );
  }
}
