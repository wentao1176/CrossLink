import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crosslink/api.dart';

void main() {
  test(
    'expired access refreshes then replays an intact multipart upload',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var uploads = 0, refreshes = 0;
      final bodies = <String>[];
      final subscription = server.listen((request) async {
        final bytes = await request.fold<List<int>>([], (a, b) => a..addAll(b));
        if (request.uri.path == '/api/v1/files/upload') {
          uploads++;
          bodies.add(utf8.decode(bytes, allowMalformed: true));
          request.response.statusCode = uploads == 1 ? 401 : 201;
          request.response.headers.contentType = ContentType.json;
          request.response.write(uploads == 1 ? '{}' : '{"id":"stored-file"}');
        } else if (request.uri.path == '/api/v1/auth/refresh') {
          refreshes++;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '{"access_token":"new-access","refresh_token":"new-refresh","device_id":"device"}',
          );
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });
      final api = Api(
        'http://127.0.0.1:${server.port}',
        onTokens: (_) async {},
        onRevoked: () async {},
      );
      await api.accept({
        'access_token': 'expired-access',
        'refresh_token': 'old-refresh',
        'device_id': 'device',
      });
      try {
        final response = await api.dio.post<dynamic>(
          '/files/upload',
          data: FormData.fromMap({
            'file': MultipartFile.fromBytes(
              utf8.encode('actual file content'),
              filename: 'fixture.txt',
            ),
          }),
        );
        expect(response.statusCode, 201);
        expect(refreshes, 1);
        expect(uploads, 2);
        expect(
          bodies.every((body) => body.contains('actual file content')),
          isTrue,
        );
      } finally {
        api.close();
        await server.close(force: true);
        await subscription.cancel();
      }
    },
  );
}
