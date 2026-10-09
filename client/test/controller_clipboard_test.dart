import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_harness.dart';

Map<String, dynamic> message(int version, String text, String sender) => {
  'id': 'clip$version',
  'message_id': 'clip$version',
  'sender_device_id': sender,
  'target_device_id': null,
  'type': 'clipboard',
  'status': 'pending',
  'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
  'payload': {
    'content': text,
    'origin_device_id': sender,
    'content_hash': sha256.convert(utf8.encode(text)).toString(),
    'clipboard_revision': version,
    'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  },
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'the controller connects local copy, relay, remote clipboard and pause',
    () async {
      late ControllerHarness h;
      String? owner;
      String text = 'baseline';
      var sequence = 0, version = 0;
      var watching = false;
      Map<String, dynamic>? latestSnapshot;
      Future<void> backgroundState(String state, int revision) async {
        final done = Completer<void>();
        await h.messenger.handlePlatformMessage(
          'crosslink/native',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(
              'backgroundEvent',
              jsonEncode({
                'owner': 'owner',
                'type': 'connection.state',
                'state': state,
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

      Future<void> nativeEvent() async {
        final done = Completer<void>();
        await h.messenger.handlePlatformMessage(
          'crosslink/native',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('clipboardChanged', {
              'owner': owner,
              'available': true,
              'text': text,
              'sequence': sequence,
            }),
          ),
          (_) {
            done.complete();
          },
        );
        await done.future;
      }

      h = await ControllerHarness.create(
        (request) async {
          if (request.uri.path == '/api/v1/messages' &&
              request.method == 'POST') {
            final body = h.requests.last['body'] as Map;
            expect(body['type'], 'clipboard');
            expect(body['target_device_id'], isNull);
            expect(body['client_message_id'], isNotEmpty);
            request.response.write(
              jsonEncode(
                message(++version, body['payload']['content'], 'phone'),
              ),
            );
          } else if (request.uri.path == '/api/v1/clipboard/latest') {
            request.response.write(jsonEncode(latestSnapshot));
          } else if (request.uri.path.endsWith('/ack')) {
            request.response.write('{"status":"delivered"}');
          } else {
            request.response.write('[]');
          }
        },
        nativeResponder: (call) async {
          if (call.method == 'clipboardWatch') {
            watching = call.arguments['enabled'];
            owner = call.arguments['owner'];
            return true;
          }
          if (call.method == 'clipboardRead') {
            return {'available': true, 'text': text, 'sequence': sequence};
          }
          if (call.method == 'clipboardWrite') {
            expect(call.arguments['owner'], owner);
            expect(call.arguments['expected_sequence'], sequence);
            text = call.arguments['text'];
            sequence++;
            await nativeEvent();
            return true;
          }
          return null;
        },
      );
      try {
        await h.controller.setClipboardSyncEnabled(true);
        expect(watching, isTrue);
        expect(h.controller.clipboardSyncEnabled, isTrue);
        text = '复制一段 URL https://example.com';
        sequence++;
        await nativeEvent();
        final sends = h.requests
            .where(
              (r) => r['method'] == 'POST' && r['path'] == '/api/v1/messages',
            )
            .toList();
        expect(sends.last['body']['payload']['content'], text);
        final before = sends.length;
        version++;
        await h.event(
          'clipboard.updated',
          message(version, '来自电脑，可以直接粘贴', 'peer'),
        );
        expect(text, '来自电脑，可以直接粘贴');
        expect(
          h.requests
              .where(
                (r) => r['method'] == 'POST' && r['path'] == '/api/v1/messages',
              )
              .length,
          before,
        );
        await backgroundState('reconnecting', 10);
        await h.event(
          'clipboard.updated',
          message(++version, 'old replay', 'peer'),
        );
        expect(text, '来自电脑，可以直接粘贴');
        latestSnapshot = message(++version, 'newest after reconnect', 'peer');
        await backgroundState('connected', 11);
        for (
          var attempt = 0;
          attempt < 30 && text != 'newest after reconnect';
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(text, 'newest after reconnect');
        await h.controller.setClipboardSyncEnabled(false);
        expect(watching, isFalse);
        text = '暂停后的复制';
        sequence++;
        await nativeEvent();
        expect(
          h.requests
              .where(
                (r) => r['method'] == 'POST' && r['path'] == '/api/v1/messages',
              )
              .length,
          before,
        );
      } finally {
        await h.close();
      }
    },
  );
}
