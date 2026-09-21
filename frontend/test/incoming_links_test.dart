import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safernotes_app/shared/app/incoming_links.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('safernotes.test/incoming_links');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('reads the cold-start invitation URL from Android', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getInitialLink');
      return 'safernotes://invite?invitation='
          '123e4567-e89b-42d3-a456-426614174000';
    });
    final links = IncomingLinks(channel: channel);
    addTearDown(links.dispose);

    expect(
      await links.initialUri(),
      Uri.parse(
        'safernotes://invite?invitation='
        '123e4567-e89b-42d3-a456-426614174000',
      ),
    );
  });

  test('delivers links received while Android is already running', () async {
    final links = IncomingLinks(channel: channel);
    addTearDown(links.dispose);
    final received = links.stream.first;
    final message = const StandardMethodCodec().encodeMethodCall(
      const MethodCall(
        'link',
        'safernotes://invite?invitation='
            '123e4567-e89b-42d3-a456-426614174000',
      ),
    );

    await messenger.handlePlatformMessage(
      channel.name,
      message,
      (ByteData? _) {},
    );

    expect(
      await received,
      Uri.parse(
        'safernotes://invite?invitation='
        '123e4567-e89b-42d3-a456-426614174000',
      ),
    );
  });
}
