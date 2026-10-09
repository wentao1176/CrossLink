import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crosslink/api.dart';
import 'package:crosslink/controller.dart';

class ControllerHarness {
  final controller = CrossLinkController();
  late HttpServer server;
  late StreamSubscription<HttpRequest> listener;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final tokens = <String, dynamic>{
    'access_token': 'access',
    'refresh_token': 'refresh',
    'device_id': 'phone',
    '_native_owner': 'owner',
  };
  String? clipboard;
  final List<Map<String, dynamic>> requests = [];
  static Future<ControllerHarness> create(
    Future<void> Function(HttpRequest) respond, {
    Map<String, Object> preferences = const {},
    Future<dynamic> Function(MethodCall)? nativeResponder,
  }) async {
    final h = ControllerHarness();
    HttpOverrides.global = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues(preferences);
    h.messenger.setMockMethodCallHandler(
      const MethodChannel('crosslink/native'),
      (call) async {
        if (nativeResponder != null) {
          final value = await nativeResponder(call);
          if (value != null) return value;
        }
        if (call.method == 'deviceName') return 'Phone';
        if (call.method == 'backgroundStart') {
          return jsonEncode({
            'endpoint': h.controller.endpoint,
            'owner': 'owner',
            'tokens': h.tokens,
            'connection': {'state': 'connected', 'revision': 1},
          });
        }
        return null;
      },
    );
    h.messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    h.messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        h.clipboard = call.arguments['text'];
      }
      return null;
    });
    h.server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    h.listener = h.server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      h.requests.add({
        'path': request.uri.path,
        'method': request.method,
        'body': body.isEmpty
            ? null
            : request.headers.contentType?.mimeType == 'application/json'
            ? jsonDecode(body)
            : body,
      });
      request.response.headers.contentType = ContentType.json;
      await respond(request);
      await request.response.close();
    });
    await h.controller.initialize();
    h.controller.error = '';
    h.controller.endpoint = 'http://127.0.0.1:${h.server.port}';
    h.controller.deviceId = 'phone';
    h.controller.api = Api(
      h.controller.endpoint,
      onTokens: (_) async {},
      onRevoked: () async {},
    );
    h.controller.api!.tokens = h.tokens;
    return h;
  }

  Future<void> event(String event, Map<String, dynamic> data) async {
    final done = Completer<void>();
    await messenger.handlePlatformMessage(
      'crosslink/native',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(
          'backgroundEvent',
          jsonEncode({'owner': 'owner', 'event': event, 'data': data}),
        ),
      ),
      (_) {
        done.complete();
      },
    );
    await done.future;
  }

  Future<void> close() async {
    await controller.shutdown();
    controller.dispose();
    await server.close(force: true);
    await listener.cancel();
    for (final channel in [
      const MethodChannel('crosslink/native'),
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      SystemChannels.platform,
    ]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    debugDefaultTargetPlatformOverride = null;
  }
}

Map<String, dynamic> outgoingMessage(String status) => {
  'id': 'm',
  'message_id': 'm',
  'sender_device_id': 'phone',
  'target_device_id': 'peer',
  'type': 'text',
  'payload': {'content': 'hello'},
  'status': status,
  'created_at': 1700000000,
};
