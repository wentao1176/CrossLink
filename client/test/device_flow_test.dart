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
  for (final logout in [false, true]) {
    test(
      logout
          ? 'a late history reload cannot repopulate a logged-out session'
          : 'remote rename updates the current device name',
      () async {
        HttpOverrides.global = null;
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        SharedPreferences.setMockInitialValues({});
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
        final arrived = Completer<void>();
        final release = Completer<void>();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final listener = server.listen((request) async {
          await request.drain<void>();
          request.response.headers.contentType = ContentType.json;
          if (request.uri.path == '/api/v1/devices') {
            if (!arrived.isCompleted) arrived.complete();
            if (logout) await release.future;
            request.response.write(
              jsonEncode([
                {'id': 'phone', 'name': 'My renamed phone', 'online': true},
              ]),
            );
          } else {
            request.response.write(request.method == 'POST' ? '{}' : '[]');
          }
          await request.response.close();
        });
        final c = CrossLinkController();
        c.endpoint = 'http://127.0.0.1:${server.port}';
        c.deviceId = 'phone';
        c.deviceName = 'Old system name';
        c.prefs = await SharedPreferences.getInstance();
        c.api = Api(c.endpoint, onTokens: (_) async {}, onRevoked: () async {});
        c.api!.tokens = {
          'access_token': 'access',
          'refresh_token': 'refresh',
          'device_id': 'phone',
        };
        try {
          final pending = c.reload();
          await arrived.future;
          if (logout) {
            await c.logout();
            release.complete();
          }
          await pending;
          if (logout) {
            expect(c.signedIn, isFalse);
            expect(c.devices, isEmpty);
            expect(c.cache.items, isEmpty);
          } else {
            expect(c.deviceName, 'My renamed phone');
          }
        } finally {
          if (!release.isCompleted) release.complete();
          c.dispose();
          await server.close(force: true);
          await listener.cancel();
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
