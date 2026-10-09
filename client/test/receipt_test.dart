import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crosslink/api.dart';
import 'package:crosslink/controller.dart';
import 'package:crosslink/protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a delayed history snapshot cannot regress an already read receipt', () {
    final cache = MessageCache();
    cache.put({
      'id': 'm',
      'status': 'read',
      'payload': {'content': 'old'},
    });
    cache.put({
      'id': 'm',
      'status': 'pending',
      'payload': {'content': 'old'},
    });
    expect(cache.items.single['status'], 'read');
  });
  for (final android in [true, false]) {
    test(
      'sender receipts update ${android ? 'Android background' : 'Windows socket'} without acknowledging them',
      () async {
        HttpOverrides.global = null;
        debugDefaultTargetPlatformOverride = android
            ? TargetPlatform.android
            : TargetPlatform.windows;
        SharedPreferences.setMockInitialValues({});
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          const MethodChannel('crosslink/native'),
          (call) async => call.method == 'deviceName' ? 'Phone' : null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        WebSocket? socket;
        var acknowledgements = 0;
        final tokens = {
          'access_token': 'access',
          'refresh_token': 'refresh',
          'device_id': 'phone',
          '_native_owner': 'owner',
        };
        final listener = server.listen((request) async {
          if (request.uri.path == '/ws') {
            socket = await WebSocketTransformer.upgrade(request);
            socket!.listen((raw) {
              final data = jsonDecode(raw);
              if (data['type'] == 'auth') socket!.add('{"type":"auth_ok"}');
            });
            return;
          }
          await request.drain<void>();
          request.response.headers.contentType = ContentType.json;
          if (request.uri.path == '/api/v1/auth/refresh') {
            request.response.write(jsonEncode(tokens));
          } else {
            if (request.uri.path.endsWith('/ack')) acknowledgements++;
            request.response.write('[]');
          }
          await request.response.close();
        });
        final c = CrossLinkController();
        await c.initialize();
        c.error = '';
        c.endpoint = 'http://127.0.0.1:${server.port}';
        c.deviceId = 'phone';
        c.api = Api(c.endpoint, onTokens: (_) async {}, onRevoked: () async {});
        c.api!.tokens = tokens;
        c.cache.put({
          'id': 'm',
          'sender_device_id': 'phone',
          'status': 'pending',
        });
        Future<void> inject(String state) async {
          final data = {
            'event': 'message.receipt.updated',
            'data': {
              'message_id': 'm',
              'recipient_device_id': 'peer',
              'recipient_status': state,
              'status': state,
            },
            'owner': 'owner',
          };
          if (android) {
            final done = Completer<void>();
            await messenger.handlePlatformMessage(
              'crosslink/native',
              const StandardMethodCodec().encodeMethodCall(
                MethodCall('backgroundEvent', jsonEncode(data)),
              ),
              (_) {
                done.complete();
              },
            );
            await done.future;
          } else {
            socket!.add(jsonEncode(data));
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }

        try {
          if (!android) await c.connect();
          await inject('delivered');
          expect(c.cache.items.single['status'], 'delivered');
          await inject('read');
          await inject('delivered');
          expect(c.cache.items.single['status'], 'read');
          expect(c.cache.items.length, 1);
          expect(acknowledgements, 0);
        } finally {
          await c.shutdown();
          c.dispose();
          await socket?.close();
          await server.close(force: true);
          await listener.cancel();
          messenger.setMockMethodCallHandler(
            const MethodChannel('crosslink/native'),
            null,
          );
          messenger.setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            null,
          );
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
  test('an acknowledgement finishing after logout cannot resurrect received history', () async {
    HttpOverrides.global = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('crosslink/native'),
      (call) async => call.method == 'deviceName' ? 'Phone' : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    final started = Completer<void>();
    final release = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final listener = server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/ack')) {
        started.complete();
        await release.future;
        request.response.write('{"status":"delivered"}');
      } else {
        request.response.write('{}');
      }
      await request.response.close();
    });
    final c = CrossLinkController();
    await c.initialize();
    c.endpoint = 'http://127.0.0.1:${server.port}';
    c.deviceId = 'phone';
    c.api = Api(c.endpoint, onTokens: (_) async {}, onRevoked: () async {});
    c.api!.tokens = {
      'access_token': 'access',
      'refresh_token': 'refresh',
      'device_id': 'phone',
      '_native_owner': 'owner',
    };
    final done = Completer<void>();
    try {
      final incoming = messenger.handlePlatformMessage(
        'crosslink/native',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(
            'backgroundEvent',
            jsonEncode({
              'owner': 'owner',
              'event': 'message.created',
              'data': {
                'id': 'incoming',
                'sender_device_id': 'peer',
                'type': 'text',
                'payload': {'content': 'hello'},
                'status': 'pending',
              },
            }),
          ),
        ),
        (_) {
          done.complete();
        },
      );
      await started.future;
      await c.logout();
      release.complete();
      await incoming;
      await done.future;
      expect(c.signedIn, isFalse);
      expect(c.cache.items, isEmpty);
    } finally {
      if (!release.isCompleted) release.complete();
      c.dispose();
      await server.close(force: true);
      await listener.cancel();
      messenger.setMockMethodCallHandler(
        const MethodChannel('crosslink/native'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        null,
      );
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
