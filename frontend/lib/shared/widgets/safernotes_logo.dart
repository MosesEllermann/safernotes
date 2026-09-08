import 'package:flutter/material.dart';

class SafernotesLogo extends StatelessWidget {
  const SafernotesLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      dark
          ? 'assets/safernotes-logo-white.png'
          : 'assets/safernotes-logo-black.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      filterQuality: FilterQuality.high,
    );
  }
}
