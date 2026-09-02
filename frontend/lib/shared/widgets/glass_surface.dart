import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:safernotes_app/shared/theme/app_theme.dart';

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
    this.blur = 14,
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
  final double blur;
  final bool showBorder;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final design = context.safernotesTheme;
    final radius = borderRadius ?? BorderRadius.circular(design.controlRadius);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: fill ?? design.glassFill,
        borderRadius: radius,
        border: showBorder
            ? Border.all(color: borderColor ?? design.glassStroke)
            : null,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: design.glassShadow,
                  blurRadius: design.isApple ? 20 : 12,
                  offset: Offset(0, design.isApple ? 10 : 6),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ),
    );

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: radius,
        child: enabled && design.isApple
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: surface,
              )
            : surface,
      ),
    );
  }
}
