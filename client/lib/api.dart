import 'dart:async';

import 'package:dio/dio.dart';

class Api {
  Api(this.endpoint, {required this.onTokens, required this.onRevoked}) {
    dio = Dio(
      BaseOptions(
        baseUrl: '$endpoint/api/v1',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(minutes: 10),
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (tokens?['access_token'] != null) {
            options.headers['Authorization'] =
                'Bearer ${tokens!['access_token']}';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401 &&
              tokens != null &&
              error.requestOptions.extra['retried'] != true) {
            try {
              await refresh();
              final options = error.requestOptions;
              if (options.data is FormData) {
                options.data = (options.data as FormData).clone();
              }
              options.extra['retried'] = true;
              options.headers['Authorization'] =
                  'Bearer ${tokens!['access_token']}';
              handler.resolve(await dio.fetch<dynamic>(options));
              return;
            } catch (_) {
              handler.next(error);
              return;
            }
          }
          handler.next(error);
        },
      ),
    );
  }
  final String endpoint;
  late final Dio dio;
  Map<String, dynamic>? tokens;
  final Future<void> Function(Map<String, dynamic>) onTokens;
  final Future<void> Function() onRevoked;
  Future<void>? _refreshing;
  Future<void> accept(Map<String, dynamic> value) async {
    tokens = value;
    await onTokens(value);
  }

  Future<void> refresh() async {
    if (_refreshing != null) return _refreshing;
    _refreshing = _performRefresh();
    try {
      await _refreshing;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _performRefresh() async {
    final raw = Dio(
      BaseOptions(
        baseUrl: '$endpoint/api/v1',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    try {
      final response = await raw.post<dynamic>(
        '/auth/refresh',
        data: {'refresh_token': tokens?['refresh_token']},
      );
      await accept(Map<String, dynamic>.from(response.data));
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        tokens = null;
        await onRevoked();
      }
      rethrow;
    } finally {
      raw.close();
    }
  }

  Future<List<Map<String, dynamic>>> list(String path) async {
    final response = await dio.get<dynamic>(path);
    return (response.data as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  void close() => dio.close(force: true);
}

String userError(Object error) {
  if (error is DioException) {
    if (error.type == DioExceptionType.cancel) return '传输已取消';
    if (error.response?.data is Map) {
      return error.response!.data['message']?.toString() ?? '请求失败';
    }
    return '连接失败，请检查服务器地址与网络，稍后重试';
  }
  if (error is FormatException) return error.message.toString();
  return '操作失败：$error';
}
