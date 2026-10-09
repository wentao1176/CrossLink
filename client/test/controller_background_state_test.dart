import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crosslink/api.dart';
import 'package:crosslink/controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final state in ['connected', 'reconnecting', 'starting']) {
    test(
      'reattaching an Android $state worker restores the actual state',
      () async {
        HttpOverrides.global = null;
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        SharedPreferences.setMockInitialValues({});
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        var started = false;
        final tokens = <String, dynamic>{
          'access_token': 'test-access',
          'refresh_token': 'test-refresh',
          'device_id': 'phone',
          '_native_owner': 'owner',
        };
        messenger.setMockMethodCallHandler(
          const MethodChannel('crosslink/native'),
          (call) async {
            if (call.method == 'backgroundSnapshot' &&
                started &&
                state == 'starting') {
              return jsonEncode({
                'endpoint': 'unused',
                'owner': 'owner',
                'tokens': tokens,
                'connection': {'state': 'connected', 'revision': 4},
              });
            }
            if (call.method == 'backgroundStart') {
              started = true;
              return jsonEncode({
                'endpoint': 'unused',
                'owner': 'owner',
                'tokens': tokens,
                'connection': {
                  'state': state == 'starting' ? 'connecting' : state,
                  'revision': state == 'starting' ? 0 : 4,
                },
              });
            }
            if (call.method == 'deviceName') return 'Phone';
            return null;
          },
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = server.listen((request) async {
          await request.drain<void>();
          request.response.headers.contentType = ContentType.json;
          request.response.write('[]');
          await request.response.close();
        });
        final c = CrossLinkController();
        await c.initialize();
        c.endpoint = 'http://127.0.0.1:${server.port}';
        c.deviceId = 'phone';
        c.api = Api(c.endpoint, onTokens: (_) async {}, onRevoked: () async {});
        c.api!.tokens = tokens;
        Future<void> event(String owner, String next, int revision) async {
          final done = Completer<void>();
          await messenger.handlePlatformMessage(
            'crosslink/native',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(
                'backgroundEvent',
                jsonEncode({
                  'type': 'connection.state',
                  'owner': owner,
                  'state': next,
                  'revision': revision,
                }),
              ),
            ),
            (_) {
              done.complete();
            },
          );
          await done.future;
        }

        try {
          await c.connect();
          expect(c.signedIn, isTrue);
          expect(c.error, isEmpty);
          expect(c.connection, state == 'reconnecting' ? '离线 · 自动重连' : '实时连接');
          await event('owner', 'connected', 5);
          expect(c.connection, '实时连接');
          await event('owner', 'reconnecting', 4);
          expect(c.connection, '实时连接');
          await event('obsolete-owner', 'stopped', 10);
          expect(c.connection, '实时连接');
        } finally {
          c.dispose();
          await server.close(force: true);
          await requests.cancel();
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
}
