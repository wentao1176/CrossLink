import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';

import 'file_limits.dart';
export 'file_limits.dart';

Future<String?> receiveFile(
  Dio dio,
  String path, {
  required String name,
  required String mimeType,
  String? expectedHash,
  int? expectedSize,
  CancelToken? cancelToken,
  void Function(int, int)? onProgress,
}) async {
  final response = await dio.get<List<int>>(
    path,
    options: Options(
      responseType: ResponseType.bytes,
      receiveTimeout: const Duration(minutes: 10),
    ),
    cancelToken: cancelToken,
    onReceiveProgress: onProgress,
  );
  final bytes = Uint8List.fromList(response.data!);
  if (bytes.length > maxFileBytes) throw const FormatException('文件超过 100 MB');
  final hash = expectedHash ?? response.headers.value('x-file-sha256');
  if (hash == null ||
      sha256.convert(bytes).toString() != hash.toLowerCase() ||
      (expectedSize != null && bytes.length != expectedSize)) {
    throw const FormatException('文件校验失败，请重新下载');
  }
  final uri = await FilePicker.saveFile(
    dialogTitle: '保存收到的文件',
    fileName: name,
    bytes: bytes,
  );
  return uri?.toString();
}
