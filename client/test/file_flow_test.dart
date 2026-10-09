import 'test_paths.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'controller_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('one shared file failure retains it and does not prevent the next file send', () async {
    final root = transferTestRoot();
    await root.create(recursive: true);
    final directory = await root.createTemp('share-test-');
    final first = await File('${directory.path}/first').writeAsString('first');
    final second = await File('${directory.path}/second')
        .writeAsString('second');
    var uploads = 0;
    final h = await ControllerHarness.create((request) async {
      if (request.uri.path == '/api/v1/files/upload') {
        uploads++;
        request.response.statusCode = uploads == 1 ? 500 : 200;
        request.response.write(uploads == 1 ? '{}' : '{"id":"file2"}');
      } else {
        request.response.write('[]');
      }
    });
    try {
      h.controller.shared = {
        'files': [
          {'path': first.path, 'name': 'first.txt'},
          {'path': second.path, 'name': 'second.txt'},
        ],
      };
      await h.controller.sendShared();
      expect(uploads, 2);
      expect(
        (h.controller.shared!['files'] as List).single['name'],
        'first.txt',
      );
    } finally {
      await h.close();
      await directory.delete(recursive: true);
    }
  });
}
