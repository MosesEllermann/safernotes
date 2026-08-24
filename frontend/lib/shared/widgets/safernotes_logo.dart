import 'package:flutter/material.dart';

class SafernotesLogo extends StatelessWidget {
  const SafernotesLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/safernotes-logo.png',
      width: size,
      height: size,
      excludeFromSemantics: true,
      filterQuality: FilterQuality.high,
    );
  }
}
