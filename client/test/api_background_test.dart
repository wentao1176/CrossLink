import 'dart:async';

import 'package:crosslink/api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android delegates rotation to its single native owner and persists results', () async {
    var calls = 0;
    Map<String, dynamic>? persisted;
    final api = Api(
      'https://platform.invalid',
      refreshProvider: (previous) async {
        calls++;
        expect(previous['access_token'], 'old');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return {
          'access_token': 'new',
          'refresh_token': 'rotated',
          'device_id': 'phone',
        };
      },
      onTokens: (tokens) async {
        persisted = tokens;
      },
      onRevoked: () async {
        fail('Unexpected revocation');
      },
    );
    api.tokens = {
      'access_token': 'old',
      'refresh_token': 'refresh',
      'device_id': 'phone',
    };
    try {
      await Future.wait([api.refresh(), api.refresh()]);
      expect(calls, 1);
      expect(api.tokens!['access_token'], 'new');
      expect(persisted!['refresh_token'], 'rotated');
    } finally {
      api.close();
    }
  });
  test('late native refresh cannot restore a cleared session', () async {
    final response = Completer<Map<String, dynamic>>();
    var persisted = false;
    final api = Api(
      'https://platform.invalid',
      refreshProvider: (_) => response.future,
      onTokens: (_) async {
        persisted = true;
      },
      onRevoked: () async {},
    );
    api.tokens = {'access_token': 'old', 'refresh_token': 'refresh'};
    final refresh = api.refresh();
    api.tokens = null;
    response.complete({'access_token': 'late', 'refresh_token': 'rotated'});
    await refresh;
    expect(api.tokens, isNull);
    expect(persisted, isFalse);
    api.close();
  });
}
