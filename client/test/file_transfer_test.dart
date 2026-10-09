import 'test_paths.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crosslink/file_transfer_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fixture in [
    (0, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'),
    (
      1048576,
      'cc2cffa7208256c3d2e7fc44bc928e2b18c4390920e90bf087c97fcc4bec1f23',
    ),
    (
      10485760,
      '6b74142f132cc400bf88141d89fb521118fb8b3417bccafa241a61504afb0406',
    ),
    (
      104857600,
      '6928f6813359a1829125d59916ec425ead3075561d0e58737c4f38468d1738b8',
    ),
  ]) {
    test(
      'stream verified ${fixture.$1} bytes without a whole-file save payload',
      () async {
        HttpOverrides.global = null;
        final root = transferTestRoot();
        await root.create(recursive: true);
        final directory = await root.createTemp('transfer-test-');
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final chunk = Uint8List.fromList(
          List<int>.generate(65536, (i) => i % 251),
        );
        final listener = server.listen((request) async {
          request.response.contentLength = fixture.$1;
          try {
            for (var sent = 0; sent < fixture.$1; sent += chunk.length) {
              request.response.add(chunk);
              await request.response.flush();
            }
            await request.response.close();
          } catch (_) {}
        });
        final dio = Dio();
        try {
          final file = await downloadVerified(
            dio,
            'http://127.0.0.1:${server.port}/download',
            directory: directory,
            expectedHash: fixture.$2,
            expectedSize: fixture.$1,
          );
          expect(await file.length(), fixture.$1);
          if (fixture.$1 > 0) {
            final handle = await file.open();
            try {
              expect(await handle.read(16), List<int>.generate(16, (i) => i));
            } finally {
              await handle.close();
            }
          }
          await file.delete();
        } finally {
          dio.close(force: true);
          await server.close(force: true);
          await listener.cancel();
          await directory.delete(recursive: true);
        }
      },
    );
  }
  for (final mode in ['hash', 'limit', 'cancel']) {
    test('$mode failure removes its partial download', () async {
      HttpOverrides.global = null;
      final root = transferTestRoot();
      await root.create(recursive: true);
      final directory = await root.createTemp('failure-test-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final listener = server.listen((request) async {
        try {
          for (var i = 0; i < 10; i++) {
            request.response.add(List<int>.filled(65536, 65));
            await request.response.flush();
          }
          await request.response.close();
        } catch (_) {}
      });
      final dio = Dio(), token = CancelToken();
      try {
        await expectLater(
          downloadVerified(
            dio,
            'http://127.0.0.1:${server.port}/download',
            directory: directory,
            expectedHash: '0' * 64,
            maxBytes: mode == 'limit' ? 4 : 104857600,
            cancelToken: token,
            onProgress: (done, total) {
              if (mode == 'cancel' && done > 0) token.cancel();
            },
          ),
          throwsA(anything),
        );
        expect(await directory.list().toList(), isEmpty);
      } finally {
        dio.close(force: true);
        await server.close(force: true);
        await listener.cancel();
        await directory.delete(recursive: true);
      }
    });
  }
}
