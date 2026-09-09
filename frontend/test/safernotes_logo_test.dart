import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safernotes_app/shared/widgets/safernotes_logo.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('uses the matching $brightness monochrome logo',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const SafernotesLogo(size: 40),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      final resized = image.image as ResizeImage;
      final asset = resized.imageProvider as AssetImage;
      expect(
        asset.assetName,
        brightness == Brightness.dark
            ? 'assets/safernotes-logo-white.png'
            : 'assets/safernotes-logo-black.png',
      );
      expect(
        resized.width,
        (40 * tester.view.devicePixelRatio).ceil(),
      );
      expect(resized.height, isNull);
      expect(image.fit, BoxFit.contain);
    });
  }
}
