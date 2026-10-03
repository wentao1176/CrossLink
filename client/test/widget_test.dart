import 'package:flutter_test/flutter_test.dart';
import 'package:crosslink/protocol.dart';

void main() {
  test('endpoint preserves custom port and strips trailing slash', () {
    expect(
      normalizeEndpoint(' http://127.0.0.1:8765/ '),
      'http://127.0.0.1:8765',
    );
    expect(
      normalizeEndpoint('https://sync.example.com/'),
      'https://sync.example.com',
    );
  });
  test(
    'endpoint rejects credentials, insecure public origin and wrong protocols',
    () {
      for (final value in [
        'http://public.example.com',
        'https://user:pass@example.com',
        'file:///tmp/a',
        'https://example.com/path',
        'https://example.com?token=secret',
      ]) {
        expect(() => normalizeEndpoint(value), throwsFormatException);
      }
    },
  );
  test('reconnection delay grows to bounded 30 seconds', () {
    expect(List.generate(8, reconnectSeconds), [1, 2, 4, 8, 16, 30, 30, 30]);
  });
  test('recipient messages merge once by durable message id', () {
    final cache = MessageCache();
    cache.put({
      'id': 'a',
      'payload': {'content': 'hello'},
      'status': 'pending',
    });
    cache.put({
      'id': 'a',
      'payload': {'content': 'hello'},
      'status': 'read',
    });
    expect(cache.items.length, 1);
    expect(cache.items.single['status'], 'read');
    expect(
      cache.put({
        'id': 'b',
        'payload': {'content': 'next'},
      }),
      isTrue,
    );
  });
  test('message cache bounds history without duplicating retries', () {
    final cache = MessageCache(maxItems: 2);
    for (final id in ['a', 'b', 'c']) {
      cache.put({'id': id});
    }
    expect(cache.items.map((e) => e['id']), ['c', 'b']);
  });
}
