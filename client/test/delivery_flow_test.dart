import 'dart:async';
import 'dart:convert';

import 'package:crosslink/controller.dart';
import 'package:crosslink/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('retry after a lost send response reuses the operation and stores one message', () async {
    late ControllerHarness h;
    final stored = <String, Map<String, dynamic>>{};
    var failed = false;
    h = await ControllerHarness.create((request) async {
      if (request.uri.path == '/api/v1/messages' && request.method == 'POST') {
        final body = h.requests.last['body'] as Map;
        final id = body['client_message_id'] as String;
        final message = stored.putIfAbsent(
          id,
          () => {
            ...outgoingMessage('pending'),
            'id': id,
            'payload': body['payload'],
          },
        );
        if (!failed) {
          failed = true;
          request.response.statusCode = 503;
          request.response.write('{"message":"response unavailable"}');
        } else {
          request.response.write(jsonEncode(message));
        }
      } else {
        request.response.write('[]');
      }
    });
    try {
      h.controller.text.text = 'draft';
      await expectLater(
        h.controller.sendMessage('text', 'draft'),
        throwsA(anything),
      );
      await h.controller.sendMessage('text', 'draft');
      expect(stored.length, 1);
      expect(h.controller.cache.items.length, 1);
      expect(h.controller.text.text, isEmpty);
      await h.controller.sendMessage('text', 'new draft');
      expect(stored.length, 2);
    } finally {
      await h.close();
    }
  });
  test('a late send response after logout does not restore history or clear a new draft', () async {
    late ControllerHarness h;
    final arrived = Completer<void>(), release = Completer<void>();
    h = await ControllerHarness.create((request) async {
      if (request.uri.path == '/api/v1/messages' && request.method == 'POST') {
        arrived.complete();
        await release.future;
        request.response.write(jsonEncode(outgoingMessage('pending')));
      } else {
        request.response.write(request.method == 'POST' ? '{}' : '[]');
      }
    });
    try {
      final sending = h.controller.sendMessage('text', 'old draft');
      await arrived.future;
      await h.controller.logout();
      h.controller.text.text = 'new account draft';
      release.complete();
      await sending;
      expect(h.controller.cache.items, isEmpty);
      expect(h.controller.text.text, 'new account draft');
    } finally {
      if (!release.isCompleted) release.complete();
      await h.close();
    }
  });
  testWidgets('no peers explains how to connect and disables manual send', (
    tester,
  ) async {
    final c = CrossLinkController();
    c.deviceId = 'self';
    c.deviceName = 'This device';
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
    expect(find.text('请在另一台设备登录同一账号'), findsOneWidget);
    final send = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '发送内容'),
    );
    expect(send.onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
