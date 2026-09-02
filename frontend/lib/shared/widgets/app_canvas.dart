import 'package:flutter/material.dart';
import 'package:safernotes_app/shared/theme/app_theme.dart';

/// Full-screen ambient canvas: a base wash plus soft colour blooms that the
/// frosted surfaces on top blur into.
class AppCanvas extends StatelessWidget {
  const AppCanvas({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final mesh = ambientMeshColors(brightness);
    final dark = brightness == Brightness.dark;
    final intensity = dark ? 0.85 : 0.78;
    return DecoratedBox(
      decoration: appCanvasDecoration(context),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: Stack(
                  children: [
                    _Bloom(
                      color: mesh[0],
                      alignment: const Alignment(-0.85, -0.95),
                      diameter: 1.15,
                      opacity: intensity,
                    ),
                    _Bloom(
                      color: mesh[1],
                      alignment: const Alignment(1.0, -0.35),
                      diameter: 0.95,
                      opacity: intensity * 0.9,
                    ),
                    _Bloom(
                      color: mesh[2],
                      alignment: const Alignment(-0.6, 0.9),
                      diameter: 1.05,
                      opacity: intensity * 0.85,
                    ),
                    _Bloom(
                      color: mesh[3],
                      alignment: const Alignment(0.9, 1.0),
                      diameter: 1.2,
                      opacity: intensity * 0.8,
                    ),
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Bloom extends StatelessWidget {
  const _Bloom({
    required this.color,
    required this.alignment,
    required this.diameter,
    required this.opacity,
  });

  final Color color;
  final Alignment alignment;

  /// Size as a fraction of the shortest screen edge.
  final double diameter;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final base = constraints.biggest.shortestSide;
        final size = (base.isFinite ? base : 600) * diameter;
        return Align(
          alignment: alignment,
          child: SizedBox(
            width: size,
            height: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    color.withValues(alpha: opacity),
                    color.withValues(alpha: opacity * 0.45),
                    color.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.55, 1],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
