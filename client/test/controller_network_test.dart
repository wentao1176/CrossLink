import 'test_paths.dart';

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
  setUp(() {
    HttpOverrides.global = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });
  test('socket loss during a slow pending pull still reconnects', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var connections = 0;
    final sockets = <WebSocket>[];
    final subscription = server.listen((request) async {
      if (request.uri.path == '/ws') {
        final ws = await WebSocketTransformer.upgrade(request);
        sockets.add(ws);
        connections++;
        ws.listen((raw) async {
          final message = jsonDecode(raw);
          if (message['type'] == 'auth') {
            ws.add('{"type":"auth_ok","device_id":"receiver"}');
            if (connections == 1) {
              await Future<void>.delayed(const Duration(milliseconds: 30));
              await ws.close();
            }
          }
        });
        return;
      }
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/v1/auth/refresh') {
        request.response.write(
          '{"access_token":"access","refresh_token":"refresh","device_id":"receiver"}',
        );
      } else if (request.uri.path == '/api/v1/devices') {
        request.response.write('[{"id":"receiver","online":true}]');
      } else if (request.uri.path == '/api/v1/messages/pending') {
        await Future<void>.delayed(const Duration(milliseconds: 1600));
        request.response.write('[]');
      } else {
        request.response.write('[]');
      }
      await request.response.close();
    });
    final c = CrossLinkController();
    c.endpoint = 'http://127.0.0.1:${server.port}';
    c.deviceId = 'receiver';
    c.prefs = await SharedPreferences.getInstance();
    c.api = Api(c.endpoint, onTokens: (_) async {}, onRevoked: () async {});
    await c.api!.accept({
      'access_token': 'access',
      'refresh_token': 'refresh',
      'device_id': 'receiver',
    });
    try {
      await c.connect();
      await Future<void>.delayed(const Duration(milliseconds: 2300));
      expect(connections, greaterThanOrEqualTo(2));
      expect(c.devices.single['online'], isTrue);
    } finally {
      await c.shutdown();
      c.dispose();
      for (final ws in sockets) {
        await ws.close();
      }
      await server.close(force: true);
      await subscription.cancel();
    }
  });
  for (final cancelled in [false, true]) {
    test(
      cancelled
          ? 'cancelled save clears temporary data and sends no completion or read receipt'
          : 'download fetches uncached receipt, verifies hash and preserves complete Android URI',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var completed = 0, read = 0, saveCalls = 0;
        String? temporaryPath;
        const saved =
            'content://com.android.externalstorage.documents/document/primary%3ADownload%2Fhello.txt';
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('crosslink/native'), (
              call,
            ) async {
              if (call.method == 'transferDirectory') {
                final dir = transferTestRoot();
                await dir.create(recursive: true);
                return dir.path;
              }
              if (call.method == 'saveFile') {
                saveCalls++;
                expect(call.arguments['name'], 'hello.txt');
                expect(call.arguments['bytes'], isNull);
                temporaryPath = call.arguments['path'] as String;
                final temporary = File(temporaryPath!);
                expect(await temporary.readAsString(), 'hello');
                return cancelled ? null : saved;
              }
              return null;
            });
        final subscription = server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          if (request.uri.path.endsWith('/download')) {
            request.response.headers.set(
              'X-File-SHA256',
              '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
            );
            request.response.add(utf8.encode('hello'));
          } else {
            request.response.headers.contentType = ContentType.json;
            if (request.method == 'GET' &&
                request.uri.path == '/api/v1/transfers' &&
                request.uri.queryParameters['file_id'] == 'file') {
              request.response.write(
                '[{"id":"transfer","file_id":"file","target_device_id":"receiver","message_id":"message"}]',
              );
            } else if (request.method == 'PATCH') {
              expect(jsonDecode(body)['status'], 'completed');
              completed++;
              request.response.write('{}');
            } else if (request.uri.path.endsWith('/read')) {
              read++;
              request.response.write('{}');
            } else {
              request.response.write('[]');
            }
          }
          await request.response.close();
        });
        final c = CrossLinkController();
        c.endpoint = 'http://127.0.0.1:${server.port}';
        c.deviceId = 'receiver';
        c.prefs = await SharedPreferences.getInstance();
        c.api = Api(c.endpoint, onTokens: (_) async {}, onRevoked: () async {});
        await c.api!.accept({
          'access_token': 'access',
          'refresh_token': 'refresh',
          'device_id': 'receiver',
        });
        try {
          await c.download({
            'id': 'message',
            'sender_device_id': 'sender',
            'payload': {
              'file_id': 'file',
              'name': 'hello.txt',
              'sha256': '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
            },
          });
          expect(c.error, isEmpty);
          expect(c.downloadedPath, cancelled ? null : saved);
          expect(await File(temporaryPath!).exists(), isFalse);
          expect(saveCalls, 1);
          expect(completed, cancelled ? 0 : 1);
          expect(read, cancelled ? 0 : 1);
        } finally {
          c.dispose();
          await server.close(force: true);
          await subscription.cancel();
          debugDefaultTargetPlatformOverride = null;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('crosslink/native'),
                null,
              );
        }
      },
    );
  }
  test(
    'Android start result arriving after logout cannot restore credentials',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final started = Completer<void>();
      final response = Completer<String>();
      var persisted = 0;
      var stopped = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('crosslink/native'),
        (call) async {
          if (call.method == 'backgroundStart') {
            started.complete();
            return response.future;
          }
          if (call.method == 'backgroundStop') stopped++;
          return null;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (_) async => null,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write('{}');
        await request.response.close();
      });
      final c = CrossLinkController();
      c.endpoint = 'http://127.0.0.1:${server.port}';
      c.prefs = await SharedPreferences.getInstance();
      c.api = Api(
        c.endpoint,
        onTokens: (_) async {
          persisted++;
        },
        onRevoked: () async {},
      );
      c.api!.tokens = {
        'access_token': 'access',
        'refresh_token': 'refresh',
        'device_id': 'phone',
      };
      try {
        final connecting = c.connect();
        await started.future;
        await c.logout();
        response.complete(
          jsonEncode({
            'access_token': 'late',
            'refresh_token': 'late-refresh',
            'device_id': 'phone',
          }),
        );
        await connecting;
        expect(c.signedIn, isFalse);
        expect(persisted, 0);
        expect(stopped, 1);
      } finally {
        c.dispose();
        await server.close(force: true);
        await subscription.cancel();
        messenger.setMockMethodCallHandler(
          const MethodChannel('crosslink/native'),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
      }
    },
  );
}
