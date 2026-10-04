import 'dart:async';

import 'package:dio/dio.dart';

class Api {
  Api(
    this.endpoint, {
    required this.onTokens,
    required this.onRevoked,
    this.refreshProvider,
  }) {
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
  Map<String, dynamic>? _tokens;
  int _sessionGeneration = 0;
  bool _closed = false;
  Map<String, dynamic>? get tokens => _tokens;
  set tokens(Map<String, dynamic>? value) {
    ++_sessionGeneration;
    _tokens = value;
  }

  final Future<void> Function(Map<String, dynamic>) onTokens;
  final Future<void> Function() onRevoked;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)?
  refreshProvider;
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
    final generation = _sessionGeneration;
    if (refreshProvider != null) {
      final next = await refreshProvider!(Map.of(tokens!));
      if (_closed || generation != _sessionGeneration) return;
      await accept(next);
      return;
    }
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
      if (_closed || generation != _sessionGeneration) return;
      await accept(Map<String, dynamic>.from(response.data));
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 &&
          !_closed &&
          generation == _sessionGeneration) {
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

  void close() {
    _closed = true;
    ++_sessionGeneration;
    dio.close(force: true);
  }
}

String userError(Object error) {
  if (error is DioException) {
    if (error.type == DioExceptionType.cancel) return '传输已取消';
    if (error.response?.data is Map) {
      return error.response!.data['message']?.toString() ?? '请求失败';
    }
    return '暂时无法连接平台，请检查网络后重试';
  }
  if (error is FormatException) return error.message.toString();
  return '操作暂时无法完成，请稍后重试';
}
