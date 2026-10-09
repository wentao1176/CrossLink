import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crosslink/clipboard_sync.dart';

Map<String, dynamic> clipMessage(
  int revision,
  String text, {
  String sender = 'peer',
  int expires = 1700002000,
}) => {
  'id': 'm$revision',
  'sender_device_id': sender,
  'type': 'clipboard',
  'payload': {
    'content': text,
    'content_hash': sha256.convert(utf8.encode(text)).toString(),
    'origin_device_id': sender,
    'clipboard_revision': revision,
    'expires_at': expires,
  },
};

class ClipboardFixture {
  String? text = 'baseline';
  int sequence = 0, serverVersion = 0;
  bool canRead = true, canWrite = true, offline = false, echo = false;
  Map<String, dynamic>? latest, saved;
  final sends = <Map<String, String>>[], writes = <String>[];
  Completer<Map<String, dynamic>>? heldSend;
  Future<LocalClipboard> Function()? customRead;
  Future<Map<String, dynamic>?> Function()? customLatest;
  late ClipboardSync sync;
  ClipboardFixture({Map<String, dynamic>? restored}) {
    sync = ClipboardSync(
      deviceId: 'self',
      send: (text, id) async {
        sends.add({'text': text, 'id': id});
        if (offline) throw StateError('offline');
        if (heldSend != null) return heldSend!.future;
        return clipMessage(++serverVersion, text, sender: 'self');
      },
      read: () async => customRead != null
          ? await customRead!()
          : LocalClipboard(text: text, sequence: sequence, available: canRead),
      write: (value, expectedSequence) async {
        if (!canWrite || expectedSequence != sequence) return false;
        text = value;
        sequence++;
        writes.add(value);
        if (echo) await sync.onLocalChange(value, sequence);
        return true;
      },
      fetchLatest: () async =>
          customLatest != null ? await customLatest!() : latest,
      persist: (state) async {
        saved = Map<String, dynamic>.from(jsonDecode(jsonEncode(state)));
      },
      initialState: restored,
      nowSeconds: () => 1700001000,
    );
  }
  Future<void> copy(String value) async {
    text = value;
    sequence++;
    await sync.onLocalChange(value, sequence);
  }

  Future<void> receive(int version, String value) async {
    serverVersion = version;
    latest = clipMessage(version, value);
    await sync.onRemoteClipboard(latest!);
  }
}

void main() {
  test('a local Unicode copy produces a stable relay operation', () async {
    final f = ClipboardFixture();
    await f.sync.enable();
    await f.copy('你好\nhttps://example.com 😀');
    expect(f.sends.single['text'], '你好\nhttps://example.com 😀');
    expect(f.sends.single['id'], isNotEmpty);
    expect(f.writes, isEmpty);
  });
  test('remote clipboard writes do not echo back and stale versions cannot overwrite them', () async {
    final f = ClipboardFixture();
    f.echo = true;
    await f.sync.enable();
    await f.receive(3, 'remote');
    await f.sync.onRemoteClipboard(clipMessage(3, 'remote'));
    await f.sync.onRemoteClipboard(clipMessage(2, 'old'));
    expect(f.text, 'remote');
    expect(f.writes, ['remote']);
    expect(f.sends, isEmpty);
    await f.copy('remote');
    expect(f.sends.length, 1);
  });
  test(
    'offline local copy survives restore and retries the same operation ID',
    () async {
      final f = ClipboardFixture();
      f.offline = true;
      await f.sync.enable();
      await f.copy('local newer');
      final id = f.sends.single['id'];
      final state = f.saved!;
      f.sync.pause();
      final restored = ClipboardFixture(restored: state);
      restored.text = 'local newer';
      restored.latest = clipMessage(1, 'old remote');
      restored.serverVersion = 1;
      await restored.sync.enable();
      expect(restored.sends.single['id'], id);
      expect(restored.text, 'local newer');
      expect(restored.writes, isEmpty);
    },
  );
  test('a new local copy wins while an older snapshot waits', () async {
    final f = ClipboardFixture();
    await f.sync.enable();
    f.offline = true;
    await f.copy('new local');
    await f.receive(4, 'older remote');
    expect(f.text, 'new local');
    expect(f.writes, isEmpty);
    f.offline = false;
    await f.sync.reconcile();
    expect(f.text, 'new local');
    expect(f.writes, isEmpty);
  });
  test('fast new copies are not cleared by an earlier send response', () async {
    final f = ClipboardFixture();
    await f.sync.enable();
    f.heldSend = Completer<Map<String, dynamic>>();
    final first = f.copy('first');
    await Future<void>.delayed(Duration.zero);
    final second = f.copy('second');
    f.heldSend!.complete(clipMessage(1, 'first', sender: 'self'));
    f.heldSend = null;
    f.serverVersion = 1;
    await Future.wait([first, second]);
    expect(f.sends.map((m) => m['text']).toList(), ['first', 'second']);
    expect(f.text, 'second');
  });
  test(
    'paused sessions do not write after an in-flight clipboard read',
    () async {
      final f = ClipboardFixture();
      await f.sync.enable();
      final read = Completer<LocalClipboard>();
      f.customRead = () => read.future;
      final applying = f.receive(2, 'late');
      await Future<void>.delayed(Duration.zero);
      f.sync.pause();
      read.complete(LocalClipboard(text: 'baseline', sequence: 0));
      await applying;
      expect(f.writes, isEmpty);
      await f.copy('after pause');
      expect(f.sends, isEmpty);
    },
  );
  test(
    'background snapshots wait for readable focus before applying',
    () async {
      final f = ClipboardFixture();
      await f.sync.enable();
      f.canRead = false;
      await f.receive(2, 'waiting');
      expect(f.writes, isEmpty);
      f.canRead = true;
      await f.sync.reconcile();
      expect(f.text, 'waiting');
      expect(f.writes, ['waiting']);
    },
  );
  test('expired or invalid-hash clipboard data is never applied', () async {
    final f = ClipboardFixture();
    await f.sync.enable();
    await f.sync.onRemoteClipboard(
      clipMessage(1, 'expired', expires: 1700000000),
    );
    final bad = clipMessage(2, 'wrong');
    (bad['payload'] as Map)['content_hash'] = 'invalid';
    await f.sync.onRemoteClipboard(bad);
    expect(f.writes, isEmpty);
  });
  test(
    'whitespace is preserved and UTF-8 oversized text stays local',
    () async {
      final f = ClipboardFixture();
      await f.sync.enable();
      await f.copy(' \t\r\n');
      expect(f.sends.single['text'], ' \t\r\n');
      await f.copy('界' * 40000);
      expect(f.sends.length, 1);
      expect(f.text, '界' * 40000);
    },
  );
  test(
    'a clipboard read begun before a new local copy cannot resend stale text',
    () async {
      final f = ClipboardFixture();
      await f.sync.enable();
      final held = Completer<LocalClipboard>();
      f.customRead = () => held.future;
      final applying = f.receive(2, 'remote');
      await Future<void>.delayed(Duration.zero);
      await f.copy('new local');
      held.complete(const LocalClipboard(text: 'baseline', sequence: 0));
      await applying;
      expect(f.sends.map((m) => m['text']).toList(), ['new local']);
      expect(f.writes, isEmpty);
    },
  );
  test(
    'an initial read cannot turn a new local copy into a duplicate operation',
    () async {
      final f = ClipboardFixture();
      final held = Completer<LocalClipboard>();
      f.customRead = () => held.future;
      final starting = f.sync.enable();
      await Future<void>.delayed(Duration.zero);
      await f.copy('new local');
      f.customRead = null;
      held.complete(const LocalClipboard(text: 'baseline', sequence: 0));
      await starting;
      expect(f.sends.map((m) => m['text']).toList(), ['new local']);
    },
  );
  test(
    'offline replay is held until the newest snapshot has been fetched',
    () async {
      final f = ClipboardFixture();
      await f.sync.enable();
      final snapshot = Completer<Map<String, dynamic>?>();
      f.customLatest = () => snapshot.future;
      f.sync.connectionLost();
      final recovering = f.sync.reconcile();
      await Future<void>.delayed(Duration.zero);
      await f.sync.onRemoteClipboard(clipMessage(2, 'old replay'));
      expect(f.writes, isEmpty);
      snapshot.complete(clipMessage(3, 'newest'));
      await recovering;
      expect(f.writes, ['newest']);
    },
  );

  test(
    'a cleared local clipboard does not spin while an older remote value waits',
    () async {
      final f = ClipboardFixture();
      await f.sync.enable();
      f.text = '';
      f.sequence = 1;
      var reads = 0;
      f.customRead = () async {
        reads++;
        return LocalClipboard(text: '', sequence: 1, available: reads < 4);
      };
      await f.sync.onLocalChange('', 1);
      await f.receive(2, 'remote');
      expect(f.writes, isEmpty);
      expect(reads, lessThanOrEqualTo(2));
    },
  );
}
