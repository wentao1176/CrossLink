import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'controller_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a receipt arriving before the send response is merged when the message appears', () async {
    final arrived = Completer<void>(), release = Completer<void>();
    final h = await ControllerHarness.create((request) async {
      if (request.method == 'POST' && request.uri.path == '/api/v1/messages') {
        arrived.complete();
        await release.future;
        request.response.write(jsonEncode(outgoingMessage('pending')));
      } else {
        request.response.write('[]');
      }
    });
    try {
      final sending = h.controller.sendMessage('text', 'hello');
      await arrived.future;
      await h.event('message.receipt.updated', {
        'message_id': 'm',
        'recipient_device_id': 'peer',
        'recipient_status': 'read',
        'status': 'read',
      });
      expect(h.controller.cache.items, isEmpty);
      release.complete();
      await sending;
      expect(h.controller.cache.items.single['status'], 'read');
    } finally {
      if (!release.isCompleted) release.complete();
      await h.close();
    }
  });
  test(
    'copying an outgoing message does not claim its recipient has read it',
    () async {
      var reads = 0;
      final h = await ControllerHarness.create((request) async {
        if (request.uri.path.endsWith('/read')) reads++;
        request.response.write(
          request.uri.path == '/api/v1/messages'
              ? jsonEncode([outgoingMessage('pending')])
              : '[]',
        );
      });
      try {
        h.controller.cache.put(outgoingMessage('pending'));
        await h.controller.copyMessage(h.controller.cache.items.single);
        expect(h.clipboard, 'hello');
        expect(reads, 0);
        expect(h.controller.cache.items.single['status'], 'pending');
        await h.controller.reload();
        expect(h.controller.cache.items.single['status'], 'pending');
      } finally {
        await h.close();
      }
    },
  );
  test(
    'an older reload cannot overwrite a name fetched after a device event',
    () async {
      var deviceReads = 0;
      final arrived = Completer<void>(), release = Completer<void>();
      final h = await ControllerHarness.create((request) async {
        if (request.uri.path == '/api/v1/devices') {
          deviceReads++;
          request.response.write(
            jsonEncode([
              {
                'id': 'phone',
                'name': deviceReads == 1 ? 'Old name' : 'New name',
                'online': true,
              },
            ]),
          );
        } else if (request.uri.path == '/api/v1/messages') {
          arrived.complete();
          await release.future;
          request.response.write('[]');
        } else {
          request.response.write('[]');
        }
      });
      try {
        final old = h.controller.reload();
        await arrived.future;
        await h.event('device.updated', {'device_id': 'phone'});
        expect(h.controller.deviceName, 'New name');
        release.complete();
        await old;
        expect(h.controller.deviceName, 'New name');
        expect(h.controller.prefs.getString('device_name_phone'), 'New name');
      } finally {
        if (!release.isCompleted) release.complete();
        await h.close();
      }
    },
  );
  test('a legacy fabricated outgoing read status is replaced by authoritative history', () async {
    late ControllerHarness h;
    h = await ControllerHarness.create(
      (request) async {
        if (request.uri.path == '/api/v1/auth/login') {
          request.response.write(jsonEncode(h.tokens));
        } else if (request.uri.path == '/api/v1/messages') {
          request.response.write(jsonEncode([outgoingMessage('pending')]));
        } else if (request.uri.path == '/api/v1/devices') {
          request.response.write(
            '[{"id":"phone","name":"Phone","online":true}]',
          );
        } else {
          request.response.write('[]');
        }
      },
      preferences: {
        'history_phone': jsonEncode([outgoingMessage('read')]),
      },
    );
    try {
      await h.controller.login('alice', 'LongPassword123!');
      expect(h.controller.error, isEmpty);
      expect(h.controller.cache.items.single['status'], 'pending');
    } finally {
      await h.close();
    }
  });
}
