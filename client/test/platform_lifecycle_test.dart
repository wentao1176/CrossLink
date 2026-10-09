import 'package:flutter_test/flutter_test.dart';

import 'controller_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('pause keeps account credentials, suppresses reconnect and resumes pending delivery', () async {
    final calls = <String>[];
    final h = await ControllerHarness.create(
      (request) async {
        request.response.write(request.method == 'POST' ? '{}' : '[]');
      },
      nativeResponder: (call) async {
        calls.add(call.method);
        return null;
      },
    );
    try {
      await h.controller.connect();
      final starts = calls.where((v) => v == 'backgroundStart').length;
      await h.controller.setSyncPaused(true);
      expect(h.controller.signedIn, isTrue);
      expect(h.controller.prefs.getBool('sync_paused_phone'), isTrue);
      expect(calls, contains('backgroundPause'));
      expect(calls, isNot(contains('backgroundStop')));
      await h.controller.connect();
      expect(calls.where((v) => v == 'backgroundStart').length, starts);
      await h.controller.setSyncPaused(false);
      expect(h.controller.prefs.getBool('sync_paused_phone'), isFalse);
      expect(calls, contains('backgroundResume'));
      expect(calls.where((v) => v == 'backgroundStart').length, starts + 1);
      await h.controller.logout();
      expect(calls, contains('backgroundStop'));
      expect(h.controller.signedIn, isFalse);
    } finally {
      await h.close();
    }
  });
}
