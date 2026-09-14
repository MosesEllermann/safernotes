import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final incomingLinksProvider = Provider<IncomingLinks>((ref) {
  final links = IncomingLinks();
  ref.onDispose(links.dispose);
  return links;
});

class IncomingLinks {
  IncomingLinks({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName) {
    if (_usesAndroidChannel) {
      _channel.setMethodCallHandler(_handleNativeCall);
    }
  }

  static const _channelName = 'at.ecrumedia.safernotes/incoming_links';

  final MethodChannel _channel;
  final StreamController<Uri> _links = StreamController<Uri>.broadcast();

  bool get _usesAndroidChannel =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Stream<Uri> get stream => _links.stream;

  Future<Uri?> initialUri() async {
    if (!_usesAndroidChannel) return null;
    try {
      return _parse(await _channel.invokeMethod<String>('getInitialLink'));
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'link' || _links.isClosed) return;
    final uri = _parse(call.arguments as String?);
    if (uri != null) _links.add(uri);
  }

  Uri? _parse(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return Uri.tryParse(value.trim());
  }

  void dispose() {
    if (_usesAndroidChannel) {
      _channel.setMethodCallHandler(null);
    }
    unawaited(_links.close());
  }
}
