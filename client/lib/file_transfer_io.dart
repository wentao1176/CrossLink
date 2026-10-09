import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'file_limits.dart';
export 'file_limits.dart';

void _checkCancelled(CancelToken? token) {
  if (token?.isCancelled == true) throw token!.cancelError!;
}

Future<File> downloadVerified(
  Dio dio,
  String path, {
  required Directory directory,
  String? expectedHash,
  int? expectedSize,
  int maxBytes = maxFileBytes,
  CancelToken? cancelToken,
  void Function(int, int)? onProgress,
}) async {
  final token = cancelToken ?? CancelToken();
  await directory.create(recursive: true);
  final file = File('${directory.path}/crosslink-${const Uuid().v4()}.part');
  RandomAccessFile? handle;
  var complete = false;
  try {
    _checkCancelled(token);
    final response = await dio.get<ResponseBody>(
      path,
      options: Options(
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(minutes: 10),
      ),
      cancelToken: token,
    );
    final declared = int.tryParse(
      response.headers.value('content-length') ?? '',
    );
    final hash = expectedHash ?? response.headers.value('x-file-sha256');
    if (hash == null || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('文件缺少有效校验信息，请重新下载');
    }
    if ((declared ?? 0) > maxBytes || (expectedSize ?? 0) > maxBytes) {
      throw const FormatException('文件超过 100 MB');
    }
    handle = await file.open(mode: FileMode.write);
    var received = 0;
    await for (final chunk in response.data!.stream.timeout(
      const Duration(seconds: 30),
    )) {
      _checkCancelled(token);
      received += chunk.length;
      if (received > maxBytes) throw const FormatException('文件超过 100 MB');
      await handle.writeFrom(chunk);
      onProgress?.call(received, declared ?? expectedSize ?? -1);
    }
    _checkCancelled(token);
    await handle.flush();
    await handle.close();
    handle = null;
    if ((expectedSize != null && received != expectedSize) ||
        (declared != null && received != declared)) {
      throw const FormatException('文件接收不完整，请重新下载');
    }
    final actual = await sha256.bind(file.openRead()).first;
    _checkCancelled(token);
    if (actual.toString() != hash.toLowerCase()) {
      throw const FormatException('文件校验失败，请重新下载');
    }
    complete = true;
    return file;
  } catch (_) {
    if (!token.isCancelled) token.cancel();
    rethrow;
  } finally {
    await handle?.close();
    if (!complete && await file.exists()) await file.delete();
  }
}

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
  const channel = MethodChannel('crosslink/native');
  final directory = await channel.invokeMethod<String>('transferDirectory');
  if (directory == null) throw const FormatException('文件临时目录暂不可用');
  final file = await downloadVerified(
    dio,
    path,
    directory: Directory(directory),
    expectedHash: expectedHash,
    expectedSize: expectedSize,
    cancelToken: cancelToken,
    onProgress: onProgress,
  );
  try {
    _checkCancelled(cancelToken);
    final safeName = name.replaceAll(RegExp(r'[/\\]'), '_');
    final destination = await channel.invokeMethod<String>('saveFile', {
      'path': file.path,
      'name': safeName,
      'mime_type': mimeType,
    });
    if (destination == null) return null;
    _checkCancelled(cancelToken);
    if (destination.startsWith('content://')) return destination;
    final target = File(destination);
    final stage = File(
      '${target.parent.path}/.crosslink-${const Uuid().v4()}.tmp',
    );
    try {
      await file.copy(stage.path);
      _checkCancelled(cancelToken);
      await stage.rename(target.path);
    } finally {
      if (await stage.exists()) await stage.delete();
    }
    return Uri.file(target.path).toString();
  } finally {
    if (await file.exists()) await file.delete();
  }
}
