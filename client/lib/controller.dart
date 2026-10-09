import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';
import 'protocol.dart';
import 'platform_bridge.dart';
import 'native_stub.dart' if (dart.library.io) 'native_io.dart' as native;

class CrossLinkController extends ChangeNotifier {
  final storage = const FlutterSecureStorage();
  final bridge = PlatformBridge();
  final cache = MessageCache();
  final text = TextEditingController();
  late SharedPreferences prefs;
  Api? api;
  WebSocketChannel? socket;
  StreamSubscription<dynamic>? subscription;
  Timer? heartbeat, retry;
  DateTime lastPong = DateTime.now();
  String endpoint = '',
      deviceUuid = '',
      deviceId = '',
      deviceName = '',
      error = '',
      connection = '未连接';
  String? target, downloadedPath;
  String type = 'text';
  List<Map<String, dynamic>> devices = [], transfers = [], clips = [];
  Map<String, dynamic>? shared;
  bool initializing = true,
      busy = false,
      disposed = false,
      _connecting = false,
      _pulling = false;
  int attempts = 0, _generation = 0, _sessionGeneration = 0;
  int _nativeRevision = -1;
  String? _nativeStateOwner;
  double? progress;
  CancelToken? cancelToken;
  bool get signedIn => api?.tokens != null;
  bool get windows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  bool get android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  void update() {
    if (!disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      await native.initializePlatformTrust();
      prefs = await SharedPreferences.getInstance();
      endpoint = kIsWeb
          ? Uri.base.origin
          : const String.fromEnvironment('CROSSLINK_API_URL');
      await prefs.remove('endpoint');
      deviceUuid = prefs.getString('device_uuid') ?? const Uuid().v4();
      await prefs.setString('device_uuid', deviceUuid);
      deviceName = await bridge.deviceName();
      await prefs.remove('device_name');
      bridge.onBackground = _handleBackground;
      bridge.onShare = (value) async {
        if (value['error'] != null) {
          error = value['error'];
          update();
          return;
        }
        shared = value;
        if (value['text'] != null) text.text = value['text'];
        update();
      };
      bridge.onClipboard = sendClipboard;
      bridge.onFiles = pickFiles;
      bridge.onExit = shutdown;
      try {
        await bridge.initialize();
      } catch (e) {
        error = '系统集成功能暂不可用：${userError(e)}';
      }
      if (!kIsWeb) {
        final nativeSession = android
            ? await bridge.backgroundSnapshot()
            : null;
        final saved = nativeSession == null
            ? await storage.read(key: 'crosslink_session')
            : jsonEncode(nativeSession);
        if (saved != null) {
          final value = Map<String, dynamic>.from(jsonDecode(saved));
          if (value['endpoint'] == endpoint) {
            _setupApi();
            api!.tokens = Map<String, dynamic>.from(value['tokens']);
            deviceId = api!.tokens!['device_id'];
            _loadCache();
            try {
              if (android) {
                await connect();
                await reload();
              } else {
                await api!.refresh();
                await reload();
                await connect();
              }
            } catch (e) {
              error = userError(e);
              _scheduleReconnect();
            }
          }
        }
      }
    } catch (e) {
      error = userError(e);
    } finally {
      initializing = false;
      update();
    }
  }

  void _setupApi() {
    api?.close();
    final sessionGeneration = ++_sessionGeneration;
    api = Api(
      endpoint,
      refreshProvider: android
          ? (tokens) async {
              try {
                return await bridge.refreshBackground(tokens);
              } on PlatformException catch (e) {
                if (e.code == 'SESSION_REVOKED' &&
                    sessionGeneration == _sessionGeneration) {
                  await _clearSession();
                  error = '登录已失效，请重新登录';
                  update();
                }
                rethrow;
              }
            }
          : null,
      onTokens: (tokens) async {
        if (disposed || sessionGeneration != _sessionGeneration) return;
        deviceId = tokens['device_id'];
        if (!kIsWeb) {
          await storage.write(
            key: 'crosslink_session',
            value: jsonEncode({'endpoint': endpoint, 'tokens': tokens}),
          );
        }
      },
      onRevoked: () async {
        if (sessionGeneration != _sessionGeneration) return;
        await _clearSession();
        error = '登录已失效，请重新登录';
        update();
      },
    );
  }

  Future<void> login(String account, String password, {String? email}) async {
    await run(() async {
      try {
        endpoint = normalizeEndpoint(endpoint);
      } on FormatException {
        throw const FormatException('平台暂时无法连接，请稍后重试');
      }
      deviceName = await bridge.deviceName();
      final identityKey = deviceProfileKey(endpoint, account);
      deviceUuid = prefs.getString(identityKey) ?? const Uuid().v4();
      await shutdown();
      if (android) await bridge.stopBackground();
      _setupApi();
      if (email != null) {
        await api!.dio.post<dynamic>(
          '/auth/register',
          data: {'username': account, 'email': email, 'password': password},
        );
      }
      final response = await api!.dio.post<dynamic>(
        '/auth/login',
        data: {
          'account': account,
          'password': password,
          'device': {
            'device_uuid': deviceUuid,
            'device_name': deviceName,
            'device_type': android
                ? 'phone'
                : kIsWeb
                ? 'web'
                : 'desktop',
            'platform': android
                ? 'android'
                : windows
                ? 'windows'
                : 'web',
            'app_version': '0.2.0',
          },
        },
      );
      await api!.accept(Map<String, dynamic>.from(response.data));
      await prefs.setString(identityKey, deviceUuid);
      await prefs.setString('device_name_$deviceId', deviceName);
      _loadCache();
      await reload();
      await connect();
    });
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = '';
    update();
    try {
      await action();
    } catch (e) {
      error = userError(e);
    } finally {
      busy = false;
      progress = null;
      cancelToken = null;
      update();
    }
  }

  void _loadCache() {
    deviceName = prefs.getString('device_name_$deviceId') ?? deviceName;
    cache.clear();
    final saved = prefs.getString('history_$deviceId');
    if (saved != null) {
      try {
        for (final item in (jsonDecode(saved) as List).reversed) {
          cache.put(Map<String, dynamic>.from(item));
        }
      } catch (_) {}
    }
  }

  Future<void> _saveCache() async {
    await prefs.setString('history_$deviceId', jsonEncode(cache.items));
  }

  void _applyDeviceList(List<Map<String, dynamic>> list) {
    devices = list;
    for (final device in list) {
      if (device['id'] == deviceId && device['name'] is String) {
        deviceName = device['name'];
        unawaited(prefs.setString('device_name_$deviceId', deviceName));
      }
    }
    if (target != null && !list.any((d) => d['id'] == target)) target = null;
  }

  Future<void> _refreshDevices() async {
    if (!signedIn) return;
    final activeApi = api!;
    final session = _sessionGeneration;
    final list = await activeApi.list('/devices');
    if (disposed ||
        !signedIn ||
        api != activeApi ||
        session != _sessionGeneration) {
      return;
    }
    _applyDeviceList(list);
    update();
  }

  Future<void> reload() async {
    if (!signedIn) return;
    final activeApi = api!;
    final session = _sessionGeneration;
    final data = await Future.wait([
      activeApi.list('/devices'),
      activeApi.list('/messages'),
      activeApi.list('/transfers'),
      activeApi.list('/clipboard'),
    ]);
    if (disposed ||
        !signedIn ||
        api != activeApi ||
        session != _sessionGeneration) {
      return;
    }
    _applyDeviceList(data[0]);
    transfers = data[2];
    clips = data[3];
    for (final m in data[1].reversed) {
      cache.put(m);
    }
    if (target != null && !devices.any((d) => d['id'] == target)) target = null;
    await _saveCache();
    update();
  }

  Future<void> pullPending() async {
    if (_pulling || !signedIn) return;
    _pulling = true;
    try {
      for (var page = 0; page < 20; page++) {
        final pending = await api!.list('/messages/pending?limit=500');
        for (final m in pending) {
          await _receive(m);
        }
        if (pending.length < 500) break;
      }
    } finally {
      _pulling = false;
    }
  }

  Future<void> connect() async {
    if (!signedIn || disposed) return;
    if (android) {
      try {
        connection = '连接中';
        update();
        final activeApi = api!;
        final sessionGeneration = _sessionGeneration;
        final next = await bridge.startBackground(endpoint, activeApi.tokens!);
        if (disposed ||
            !signedIn ||
            sessionGeneration != _sessionGeneration ||
            api != activeApi) {
          return;
        }
        await activeApi.accept(Map<String, dynamic>.from(next['tokens']));
        _applyNativeConnection(next);
        // Capture transitions that occurred before Flutter accepted the owner.
        final current = await bridge.backgroundSnapshot();
        if (disposed ||
            sessionGeneration != _sessionGeneration ||
            api != activeApi ||
            !signedIn) {
          return;
        }
        if (current != null) _applyNativeConnection(current);
        await pullPending();
      } catch (e) {
        error = userError(e);
        connection = '离线 · 自动重连';
        _scheduleReconnect();
      }
      update();
      return;
    }
    if (_connecting) {
      _scheduleReconnect();
      return;
    }
    _connecting = true;
    retry?.cancel();
    connection = '连接中';
    update();
    final generation = ++_generation;
    try {
      await subscription?.cancel();
      await socket?.sink.close();
      heartbeat?.cancel();
      await api!.refresh();
      if (generation != _generation || !signedIn) return;
      final uri = Uri.parse(endpoint).replace(
        scheme: endpoint.startsWith('https:') ? 'wss' : 'ws',
        path: '/ws',
      );
      socket = WebSocketChannel.connect(uri);
      await socket!.ready.timeout(const Duration(seconds: 15));
      final authorized = Completer<void>();
      subscription = socket!.stream.listen(
        (raw) {
          if (generation != _generation) return;
          unawaited(_handleSocket(raw, authorized));
        },
        onDone: () {
          if (generation == _generation) {
            connection = '离线 · 自动重连';
            heartbeat?.cancel();
            _scheduleReconnect();
            update();
          }
        },
        onError: (Object e) {
          if (generation == _generation) {
            error = userError(e);
            _scheduleReconnect();
            update();
          }
        },
      );
      socket!.sink.add(
        jsonEncode({'type': 'auth', 'token': api!.tokens!['access_token']}),
      );
      await authorized.future.timeout(const Duration(seconds: 15));
      attempts = 0;
      lastPong = DateTime.now();
      connection = '实时连接';
      heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
        if (DateTime.now().difference(lastPong).inSeconds > 90) {
          unawaited(socket?.sink.close());
          _scheduleReconnect();
          return;
        }
        try {
          socket?.sink.add('{"type":"ping"}');
        } catch (_) {
          _scheduleReconnect();
        }
      });
      await pullPending();
      await _refreshDevices();
      update();
    } catch (e) {
      error = userError(e);
      connection = '离线 · 自动重连';
      _scheduleReconnect();
      update();
    } finally {
      _connecting = false;
    }
  }

  void _applyNativeConnection(Map<String, dynamic> snapshot) {
    final owner = snapshot['owner'];
    if (!signedIn || owner != api!.tokens!['_native_owner']) return;
    final raw = snapshot['connection'] ?? snapshot;
    if (raw is! Map) return;
    const labels = {
      'connecting': '连接中',
      'connected': '实时连接',
      'reconnecting': '离线 · 自动重连',
      'stopped': '未连接',
    };
    final label = labels[raw['state']];
    final revision = raw['revision'];
    if (label == null || revision is! num) return;
    if (_nativeStateOwner != owner) {
      _nativeStateOwner = owner as String?;
      _nativeRevision = -1;
    }
    if (revision < _nativeRevision) return;
    _nativeRevision = revision.toInt();
    connection = label;
    if (raw['state'] == 'connected') {
      attempts = 0;
      retry?.cancel();
    }
  }

  Future<void> _handleBackground(Map<String, dynamic> value) async {
    if (disposed ||
        !signedIn ||
        value['owner'] != api!.tokens!['_native_owner']) {
      return;
    }
    final kind = value['type'];
    if (kind == 'session.revoked') {
      await _clearSession();
      error = '登录已失效，请重新登录';
    } else if (kind == 'session.updated' && signedIn) {
      await api!.accept(Map<String, dynamic>.from(value['tokens']));
    } else if (kind == 'connection.state') {
      _applyNativeConnection(value);
    } else if (kind == 'auth_ok') {
      attempts = 0;
      retry?.cancel();
      await reload();
    } else if (kind == 'offline') {
      // The versioned native state event owns this label.
    } else if (signedIn) {
      final event = value['event']?.toString() ?? '';
      if ([
        'message.created',
        'clipboard.updated',
        'file.created',
        'notification.created',
      ].contains(event)) {
        await _receive(Map<String, dynamic>.from(value['data']));
      } else if (event.startsWith('device.')) {
        await _refreshDevices();
      }
    }
    update();
  }

  Future<void> _handleSocket(dynamic raw, Completer<void> authorized) async {
    try {
      final data = Map<String, dynamic>.from(jsonDecode(raw as String));
      if (data['type'] == 'pong') {
        lastPong = DateTime.now();
        return;
      }
      if (data['type'] == 'auth_ok') {
        if (!authorized.isCompleted) authorized.complete();
        return;
      }
      final event = data['event']?.toString() ?? '';
      if ([
        'message.created',
        'clipboard.updated',
        'file.created',
        'notification.created',
      ].contains(event)) {
        await _receive(Map<String, dynamic>.from(data['data']));
      } else if (event.startsWith('device.')) {
        await _refreshDevices();
        update();
      }
    } catch (e) {
      error = userError(e);
      update();
    }
  }

  Future<void> _receive(Map<String, dynamic> m) async {
    final fresh = cache.put(m);
    await _saveCache();
    final receipt = await api!.dio.post<dynamic>('/messages/${m['id']}/ack');
    cache.put({...m, 'status': receipt.data['status']});
    await _saveCache();
    if (fresh && !android) {
      final payload = Map<String, dynamic>.from(m['payload']);
      try {
        await bridge.notify(
          payload['title']?.toString() ?? 'CrossLink 收到新内容',
          payload['content']?.toString() ??
              payload['name']?.toString() ??
              '收到文件',
        );
      } catch (_) {}
    }
    if (m['type'] == 'file' || m['type'] == 'image') {
      transfers = await api!.list('/transfers');
    }
    if (m['type'] == 'clipboard') clips = await api!.list('/clipboard');
    update();
  }

  void _scheduleReconnect() {
    if (!signedIn || disposed || retry?.isActive == true) return;
    retry = Timer(Duration(seconds: reconnectSeconds(attempts++)), () {
      unawaited(connect());
    });
  }

  Future<void> sendMessage(String kind, String content, {String? title}) async {
    if (!signedIn) throw const FormatException('请先登录');
    if (content.trim().isEmpty) throw const FormatException('请输入要发送的内容');
    final response = await api!.dio.post<dynamic>(
      '/messages',
      data: {
        'target_device_id': target,
        'type': kind,
        'client_message_id': const Uuid().v4(),
        'payload': {'content': content, 'title': ?title},
      },
    );
    cache.put(Map<String, dynamic>.from(response.data));
    await _saveCache();
    text.clear();
    update();
  }

  Future<void> sendClipboard() async {
    await run(() async {
      final value = await Clipboard.getData(Clipboard.kTextPlain);
      await sendMessage('clipboard', value?.text ?? '');
    });
  }

  Future<void> copyText(String value) async {
    await run(() async {
      await Clipboard.setData(ClipboardData(text: value));
    });
  }

  Future<void> copyMessage(Map<String, dynamic> m) async {
    await run(() async {
      await Clipboard.setData(
        ClipboardData(text: m['payload']['content'] ?? ''),
      );
      if (m['sender_device_id'] != deviceId) {
        await api!.dio.post<dynamic>('/messages/${m['id']}/read');
      }
      cache.put({...m, 'status': 'read'});
      await _saveCache();
    });
  }

  Future<void> pickFiles() async {
    await run(() async {
      final result = await FilePicker.pickFiles();
      for (final file in result) {
        final length = await file.length();
        if (length == null || length > 100 * 1024 * 1024) {
          throw const FormatException('文件大小未知或超过 100 MB');
        }
        final multipart = MultipartFile.fromStream(
          file.readAsByteStream,
          length,
          filename: file.name,
        );
        await _upload(multipart);
      }
      await reload();
    });
  }

  Future<void> _upload(MultipartFile file) async {
    if (!signedIn) throw const FormatException('请先登录');
    cancelToken = CancelToken();
    progress = 0;
    update();
    await api!.dio.post<dynamic>(
      '/files/upload',
      data: FormData.fromMap({
        'file': file,
        if (target != null) 'target_device_id': target,
      }),
      cancelToken: cancelToken,
      onSendProgress: (sent, total) {
        progress = total > 0 ? sent / total : 0;
        update();
      },
    );
  }

  Future<void> sendShared() async {
    await run(() async {
      if (shared?['text'] != null) await sendMessage('text', shared!['text']);
      for (final entry in (shared?['files'] as List? ?? [])) {
        await _upload(
          await MultipartFile.fromFile(entry['path'], filename: entry['name']),
        );
      }
      shared = null;
      if (android) {
        await PlatformBridge.channel.invokeMethod<void>('clearShares');
      }
      await reload();
    });
  }

  Future<void> download(Map<String, dynamic> m) async {
    await run(() async {
      final payload = Map<String, dynamic>.from(m['payload']);
      final fileId = payload['file_id'];
      cancelToken = CancelToken();
      progress = 0;
      update();
      final response = await api!.dio.get<List<int>>(
        '/files/$fileId/download',
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 10),
        ),
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          progress = total > 0 ? received / total : 0;
          update();
        },
      );
      final bytes = Uint8List.fromList(response.data!);
      final expectedHash =
          payload['sha256'] ?? response.headers.value('x-file-sha256');
      if (expectedHash == null ||
          sha256.convert(bytes).toString() != expectedHash) {
        throw const FormatException('文件校验失败，请重新下载');
      }
      final Uri? uri;
      if (android) {
        final saved = await PlatformBridge.channel.invokeMethod<String>(
          'saveFile',
          {
            'name': payload['name'],
            'mime_type': payload['mime_type'] ?? 'application/octet-stream',
            'bytes': bytes,
          },
        );
        uri = saved == null ? null : Uri.parse(saved);
      } else {
        uri = await FilePicker.saveFile(
          dialogTitle: '保存收到的文件',
          fileName: payload['name'],
          bytes: bytes,
        );
      }
      if (uri == null) return;
      if (!kIsWeb) {
        downloadedPath = uri.scheme == 'file'
            ? uri.toFilePath()
            : uri.toString();
      }
      if (m['sender_device_id'] != deviceId &&
          m['id'] is String &&
          (m['id'] as String).isNotEmpty) {
        await api!.dio.post<dynamic>('/messages/${m['id']}/read');
      }
      final matching = (await api!.list('/transfers?file_id=$fileId')).where(
        (t) => t['file_id'] == fileId && t['target_device_id'] == deviceId,
      );
      for (final t in matching) {
        await api!.dio.patch<dynamic>(
          '/transfers/${t['id']}',
          data: {'status': 'completed', 'progress': 100},
        );
      }
      await reload();
    });
  }

  Future<void> rename(String id, String name) async {
    await run(() async {
      await api!.dio.patch<dynamic>(
        '/devices/$id',
        data: {'device_name': name},
      );
      await reload();
    });
  }

  Future<void> revoke(String id) async {
    await run(() async {
      await api!.dio.delete<dynamic>('/devices/$id');
      if (id == deviceId) {
        await _clearSession();
      } else {
        await reload();
      }
    });
  }

  Future<void> logout() async {
    await run(() async {
      try {
        await api?.dio.post<dynamic>('/auth/logout');
      } finally {
        await _clearSession();
      }
    });
  }

  Future<void> _clearSession() async {
    ++_sessionGeneration;
    _nativeStateOwner = null;
    _nativeRevision = -1;
    api?.tokens = null;
    await shutdown();
    if (android) await bridge.stopBackground();
    if (!kIsWeb) await storage.delete(key: 'crosslink_session');
    api?.tokens = null;
    cache.clear();
    devices = [];
    clips = [];
    transfers = [];
    deviceId = '';
    target = null;
    connection = '未连接';
    update();
  }

  Future<void> shutdown() async {
    ++_generation;
    retry?.cancel();
    heartbeat?.cancel();
    cancelToken?.cancel();
    await subscription?.cancel();
    subscription = null;
    await socket?.sink.close();
    socket = null;
  }

  Future<void> openDownloaded() async {
    if (downloadedPath != null) {
      await run(() async {
        await native.openSaved(downloadedPath!);
      });
    }
  }

  Future<void> openDownloadedFolder() async {
    if (downloadedPath != null) {
      await run(() async {
        await native.openFolder(downloadedPath!);
      });
    }
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(shutdown());
    api?.close();
    bridge.dispose();
    text.dispose();
    super.dispose();
  }
}
