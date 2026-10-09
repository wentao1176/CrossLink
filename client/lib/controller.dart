import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';
import 'clipboard_sync.dart';
import 'file_transfer.dart' as transfer;
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
  final List<Map<String, dynamic>> fileResults = [];
  bool initializing = true,
      busy = false,
      disposed = false,
      _connecting = false,
      _pulling = false;
  int attempts = 0, _generation = 0, _sessionGeneration = 0;
  int _deviceFetchRevision = 0;
  final Map<String, String> _earlyReceipts = {};
  int _nativeRevision = -1;
  String? _nativeStateOwner;
  ClipboardSync? _clipboard;
  String? _clipboardOwner;
  Timer? _clipboardRetry;
  bool clipboardSyncEnabled = false, syncPaused = false;
  bool startWithWindows = false, startMinimized = false;
  int pageIndex = 0;
  String? focusedMessageId;
  bool notificationsAllowed = true;
  String get clipboardStatus =>
      syncPaused ? '同步已暂停' : _clipboard?.status ?? '未开启';
  bool get clipboardSupported => bridge.clipboardSupported;
  double? progress;
  CancelToken? cancelToken;
  bool get signedIn => api?.tokens != null;
  bool get hasPeers => devices.any((d) => d['id'] != deviceId);
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
      bridge.onClipboardChange = (value) async {
        final clip = _clipboard;
        if (clip == null ||
            !clipboardSyncEnabled ||
            !signedIn ||
            value['owner'] != _clipboardOwner) {
          return;
        }
        final sequence = (value['sequence'] as num?)?.toInt() ?? 0;
        if (value['available'] == true) {
          await clip.onLocalChange(value['text'] as String? ?? '', sequence);
        } else {
          await clip.localUnavailable(
            value['reason'] as String? ?? 'busy',
            sequence,
          );
        }
      };
      bridge.onClipboardFocus = (value) async {
        if (value['owner'] == _clipboardOwner &&
            value['focused'] == true &&
            clipboardSyncEnabled) {
          await _clipboard?.reconcile();
        }
      };
      bridge.onClipboard = sendClipboard;
      bridge.onFiles = pickFiles;
      bridge.onExit = shutdown;
      bridge.onTogglePause = () => setSyncPaused(!syncPaused);
      bridge.onNavigate = (index, messageId) async {
        pageIndex = index;
        focusedMessageId = messageId;
        update();
      };
      try {
        await bridge.initialize();
        if (windows) {
          final settings = await bridge.startupSettings();
          startWithWindows = settings['enabled'] == true;
          startMinimized = settings['minimized'] == true;
        }
        if (android) notificationsAllowed = await bridge.notificationsEnabled();
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
            if (nativeSession?['paused'] == true) {
              syncPaused = true;
              await prefs.setBool('sync_paused_$deviceId', true);
            }
            try {
              if (syncPaused) {
                connection = '已暂停';
                return;
              }
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
    _earlyReceipts.clear();
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

  Future<void> _ensureClipboard() async {
    if (!clipboardSupported || !signedIn || syncPaused) return;
    if (_clipboard != null) {
      if (clipboardSyncEnabled) await _clipboard!.reconcile();
      return;
    }
    final activeApi = api!;
    final session = _sessionGeneration;
    final id = deviceId;
    final owner = const Uuid().v4();
    Map<String, dynamic>? restored;
    try {
      final saved = prefs.getString('clipboard_state_$id');
      if (saved != null) {
        restored = Map<String, dynamic>.from(jsonDecode(saved));
      }
    } catch (_) {}
    late ClipboardSync clip;
    clip = ClipboardSync(
      deviceId: id,
      send: (content, key) async {
        if (!_isActive(activeApi, session)) {
          throw StateError('Clipboard session stopped');
        }
        final response = await activeApi.dio.post<dynamic>(
          '/messages',
          data: {
            'type': 'clipboard',
            'target_device_id': null,
            'client_message_id': key,
            'payload': {'content': content},
          },
        );
        if (!_isActive(activeApi, session)) {
          throw StateError('Clipboard session stopped');
        }
        final message = Map<String, dynamic>.from(response.data);
        _putMessage(message);
        await _saveCache();
        update();
        return message;
      },
      read: () async => _isActive(activeApi, session)
          ? await bridge.readClipboard(owner)
          : const LocalClipboard(sequence: 0, available: false),
      write: (text, sequence) async => _isActive(activeApi, session)
          ? await bridge.writeClipboard(owner, text, sequence)
          : false,
      fetchLatest: () async {
        if (!_isActive(activeApi, session)) return null;
        final response = await activeApi.dio.get<dynamic>('/clipboard/latest');
        if (!_isActive(activeApi, session)) return null;
        return response.data == null
            ? null
            : Map<String, dynamic>.from(response.data);
      },
      persist: (state) async {
        await prefs.setString('clipboard_state_$id', jsonEncode(state));
      },
      initialState: restored,
      onChanged: () {
        if (_isActive(activeApi, session) && identical(_clipboard, clip)) {
          update();
        }
      },
    );
    _clipboard = clip;
    _clipboardOwner = owner;
    clipboardSyncEnabled = prefs.getBool('clipboard_enabled_$id') ?? false;
    if (clipboardSyncEnabled) await _activateClipboard(sendCurrent: false);
  }

  Future<void> _activateClipboard({required bool sendCurrent}) async {
    final clip = _clipboard, owner = _clipboardOwner;
    if (clip == null || owner == null || !signedIn) return;
    if (!await bridge.watchClipboard(true, owner)) {
      throw const FormatException('系统剪贴板同步暂不可用');
    }
    if (!signedIn ||
        !identical(_clipboard, clip) ||
        _clipboardOwner != owner ||
        !clipboardSyncEnabled) {
      return;
    }
    await clip.enable(sendCurrent: sendCurrent);
    if (!signedIn ||
        !identical(_clipboard, clip) ||
        _clipboardOwner != owner ||
        !clipboardSyncEnabled) {
      return;
    }
    _clipboardRetry?.cancel();
    _clipboardRetry = Timer.periodic(const Duration(seconds: 5), (_) {
      if (clipboardSyncEnabled && signedIn && identical(_clipboard, clip)) {
        unawaited(clip.reconcile());
      }
    });
    update();
  }

  Future<void> setClipboardSyncEnabled(bool enabled) async {
    await run(() async {
      if (!signedIn || !clipboardSupported) return;
      await _ensureClipboard();
      clipboardSyncEnabled = enabled;
      await prefs.setBool('clipboard_enabled_$deviceId', enabled);
      if (enabled && !syncPaused) {
        await _activateClipboard(sendCurrent: true);
      } else {
        _clipboardRetry?.cancel();
        await _clipboard?.pause();
        final owner = _clipboardOwner;
        if (owner != null) await bridge.watchClipboard(false, owner);
      }
    });
  }

  Future<void> setSyncPaused(bool value) async {
    await run(() async {
      if (!signedIn || syncPaused == value) return;
      syncPaused = value;
      await prefs.setBool('sync_paused_$deviceId', value);
      bridge.updateTray(syncPaused, devices);
      if (value) {
        final configuredClipboard = clipboardSyncEnabled;
        await shutdown();
        clipboardSyncEnabled = configuredClipboard;
        if (android) await bridge.pauseBackground();
        connection = '已暂停';
      } else {
        _nativeStateOwner = null;
        _nativeRevision = -1;
        if (android) await bridge.resumeBackground();
        await connect();
        await reload();
      }
      update();
    });
  }

  Future<void> setStartup({
    required bool enabled,
    required bool minimized,
  }) async {
    await run(() async {
      await bridge.setStartup(enabled, minimized);
      final current = await bridge.startupSettings();
      startWithWindows = current['enabled'] == true;
      startMinimized = current['minimized'] == true;
    });
  }

  Future<void> _stopClipboard({bool discardPending = false}) async {
    final owner = _clipboardOwner;
    _clipboardRetry?.cancel();
    if (discardPending) await _clipboard?.pause();
    await _clipboard?.dispose();
    _clipboard = null;
    _clipboardOwner = null;
    clipboardSyncEnabled = false;
    if (owner != null) {
      try {
        await bridge.watchClipboard(false, owner);
      } catch (_) {}
    }
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
      await shutdown(discardClipboard: true);
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
    syncPaused = prefs.getBool('sync_paused_$deviceId') ?? false;
    deviceName = prefs.getString('device_name_$deviceId') ?? deviceName;
    cache.clear();
    final saved = prefs.getString('history_$deviceId');
    if (saved != null) {
      try {
        for (final item in (jsonDecode(saved) as List).reversed) {
          final message = Map<String, dynamic>.from(item);
          if (prefs.getInt('history_format_$deviceId') != 2 &&
              message['sender_device_id'] == deviceId &&
              message['status'] == 'read') {
            message['status'] = 'unknown';
          }
          _putMessage(message);
        }
      } catch (_) {}
    }
  }

  Future<void> _saveCache() async {
    final id = deviceId;
    await prefs.setString('history_$id', jsonEncode(cache.items));
    await prefs.setInt('history_format_$id', 2);
  }

  void _applyDeviceList(List<Map<String, dynamic>> list) {
    devices = list;
    bridge.updateTray(syncPaused, devices);
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
    final revision = ++_deviceFetchRevision;
    final list = await activeApi.list('/devices');
    if (disposed ||
        !signedIn ||
        api != activeApi ||
        session != _sessionGeneration) {
      return;
    }
    if (revision == _deviceFetchRevision) _applyDeviceList(list);
    update();
  }

  Future<void> reload() async {
    if (!signedIn) return;
    final activeApi = api!;
    final session = _sessionGeneration;
    final revision = ++_deviceFetchRevision;
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
    if (revision == _deviceFetchRevision) _applyDeviceList(data[0]);
    transfers = data[2];
    clips = data[3];
    for (final m in data[1].reversed) {
      _putMessage(m);
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
    if (!signedIn || disposed || syncPaused) return;
    _clipboard?.connectionLost();
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
        await _ensureClipboard();
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
      await _ensureClipboard();
      await pullPending();
      await reload();
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
    final changed = connection != label;
    connection = label;
    if (raw['state'] == 'connected') {
      attempts = 0;
      retry?.cancel();
      if (changed && clipboardSyncEnabled) unawaited(_clipboard?.reconcile());
    } else if (changed) {
      _clipboard?.connectionLost();
    }
  }

  Future<void> _handleBackground(Map<String, dynamic> value) async {
    if (disposed ||
        !signedIn ||
        syncPaused ||
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
      } else if (event == 'message.receipt.updated') {
        await _receiveReceipt(Map<String, dynamic>.from(value['data']));
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
      } else if (event == 'message.receipt.updated') {
        await _receiveReceipt(Map<String, dynamic>.from(data['data']));
      } else if (event.startsWith('device.')) {
        await _refreshDevices();
        update();
      }
    } catch (e) {
      error = userError(e);
      update();
    }
  }

  bool _isActive(Api activeApi, int session) =>
      !disposed &&
      !syncPaused &&
      signedIn &&
      api == activeApi &&
      session == _sessionGeneration;

  bool _putMessage(Map<String, dynamic> message) {
    final fresh = cache.put(message);
    if (message['sender_device_id'] == deviceId) {
      final status = _earlyReceipts.remove(message['id']);
      if (status != null) cache.updateReceipt(message['id'], status);
    }
    return fresh;
  }

  Future<void> _receiveReceipt(Map<String, dynamic> receipt) async {
    if (!signedIn) return;
    final id = receipt['message_id'];
    final status = receipt['status'];
    const rank = {'pending': 0, 'delivered': 1, 'read': 2};
    if (id is! String || status is! String || !rank.containsKey(status)) return;
    final matches = cache.items.where((m) => m['id'] == id);
    if (matches.isEmpty) {
      final previous = _earlyReceipts[id];
      if ((rank[previous] ?? -1) <= rank[status]!) _earlyReceipts[id] = status;
      while (_earlyReceipts.length > 200) {
        _earlyReceipts.remove(_earlyReceipts.keys.first);
      }
    } else if (matches.first['sender_device_id'] == deviceId &&
        cache.updateReceipt(id, status)) {
      await _saveCache();
      update();
    }
  }

  Future<void> _receive(Map<String, dynamic> m) async {
    if (!signedIn) return;
    final activeApi = api!;
    final session = _sessionGeneration;
    final fresh = _putMessage(m);
    await _saveCache();
    if (!_isActive(activeApi, session)) return;
    final receipt = await activeApi.dio.post<dynamic>(
      '/messages/${m['id']}/ack',
    );
    if (!_isActive(activeApi, session)) return;
    cache.put({...m, 'status': receipt.data['status']});
    await _saveCache();
    if (!_isActive(activeApi, session)) return;
    if (fresh && !android) {
      final payload = Map<String, dynamic>.from(m['payload']);
      try {
        await bridge.notify(
          payload['title']?.toString() ?? 'CrossLink 收到新内容',
          payload['content']?.toString() ??
              payload['name']?.toString() ??
              '收到文件',
          messageId: m['id'] as String?,
        );
      } catch (_) {}
    }
    if (!_isActive(activeApi, session)) return;
    if (m['type'] == 'file' || m['type'] == 'image') {
      final list = await activeApi.list('/transfers');
      if (!_isActive(activeApi, session)) return;
      transfers = list;
    }
    if (m['type'] == 'clipboard') {
      if (clipboardSyncEnabled) await _clipboard?.onRemoteClipboard(m);
      if (!_isActive(activeApi, session)) return;
      final list = await activeApi.list('/clipboard');
      if (!_isActive(activeApi, session)) return;
      clips = list;
    }
    update();
  }

  void _scheduleReconnect() {
    _clipboard?.connectionLost();
    if (!signedIn || disposed || syncPaused || retry?.isActive == true) return;
    retry = Timer(Duration(seconds: reconnectSeconds(attempts++)), () {
      unawaited(connect());
    });
  }

  Future<void> sendMessage(String kind, String content, {String? title}) async {
    if (!signedIn) throw const FormatException('请先登录');
    if (syncPaused) throw const FormatException('同步已暂停，请先恢复');
    if (kind == 'clipboard' ? content.isEmpty : content.trim().isEmpty) {
      throw const FormatException('请输入要发送的内容');
    }
    final activeApi = api!;
    final session = _sessionGeneration;
    final id = deviceId;
    final command = {
      'target_device_id': target,
      'type': kind,
      'payload': {'content': content, 'title': ?title},
    };
    final signature = jsonEncode(command);
    final key = 'manual_pending_$id';
    Map<String, dynamic>? pending;
    try {
      final saved = prefs.getString(key);
      if (saved != null) pending = Map<String, dynamic>.from(jsonDecode(saved));
    } catch (_) {}
    if (pending?['signature'] != signature || pending?['id'] is! String) {
      pending = {'signature': signature, 'id': const Uuid().v4()};
      if (!await prefs.setString(key, jsonEncode(pending))) {
        throw const FormatException('发送记录暂时无法保存，请稍后重试');
      }
    }
    if (!_isActive(activeApi, session)) return;
    final response = await activeApi.dio.post<dynamic>(
      '/messages',
      data: {...command, 'client_message_id': pending!['id']},
    );
    if (!_isActive(activeApi, session)) return;
    _putMessage(Map<String, dynamic>.from(response.data));
    await _saveCache();
    if (!_isActive(activeApi, session)) return;
    if (prefs.getString(key) == jsonEncode(pending)) await prefs.remove(key);
    if (text.text == content) text.clear();
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
      final activeApi = api;
      final session = _sessionGeneration;
      await Clipboard.setData(
        ClipboardData(text: m['payload']['content'] ?? ''),
      );
      if (m['sender_device_id'] != deviceId &&
          activeApi != null &&
          _isActive(activeApi, session)) {
        final response = await activeApi.dio.post<dynamic>(
          '/messages/${m['id']}/read',
        );
        if (!_isActive(activeApi, session)) return;
        _putMessage({...m, 'status': response.data['status']});
        await _saveCache();
      }
    });
  }

  Future<bool> _tryUpload(
    String name,
    Future<MultipartFile> Function() create,
  ) async {
    final result = <String, dynamic>{'name': name, 'status': 'waiting'};
    fileResults.add(result);
    update();
    if (cancelToken?.isCancelled == true) {
      result['status'] = 'cancelled';
      update();
      return false;
    }
    try {
      final part = await create();
      if (part.length > transfer.maxFileBytes) {
        throw const FormatException('文件超过 100 MiB');
      }
      result['status'] = 'uploading';
      update();
      await _upload(part);
      result['status'] = 'sent';
      update();
      return true;
    } catch (e) {
      result['status'] = e is DioException && e.type == DioExceptionType.cancel
          ? 'cancelled'
          : 'failed';
      result['detail'] = userError(e);
      update();
      return false;
    }
  }

  Future<void> pickFiles() async {
    await run(() async {
      final files = await FilePicker.pickFiles();
      fileResults.clear();
      for (final file in files) {
        await _tryUpload(file.name, () async {
          final length = await file.length();
          if (length == null || length > transfer.maxFileBytes) {
            throw const FormatException('文件大小未知或超过 100 MiB');
          }
          return MultipartFile.fromStream(
            file.readAsByteStream,
            length,
            filename: file.name,
          );
        });
      }
      if (signedIn && !syncPaused) await reload();
    });
  }

  Future<void> _upload(MultipartFile file) async {
    if (!signedIn) throw const FormatException('请先登录');
    if (syncPaused) throw const FormatException('同步已暂停，请先恢复');
    final activeApi = api!, session = _sessionGeneration;
    cancelToken = CancelToken();
    progress = 0;
    update();
    await activeApi.dio.post<dynamic>(
      '/files/upload',
      data: FormData.fromMap({
        'file': file,
        if (target != null) 'target_device_id': target,
      }),
      cancelToken: cancelToken,
      onSendProgress: (sent, total) {
        if (_isActive(activeApi, session)) {
          progress = total > 0 ? sent / total : null;
          update();
        }
      },
    );
    if (!_isActive(activeApi, session)) {
      throw const FormatException('登录状态已变化，请重新发送');
    }
  }

  Future<void> sendShared() async {
    await run(() async {
      final share = shared;
      if (share == null) return;
      fileResults.clear();
      String? pendingText;
      if (share['text'] is String) {
        try {
          await sendMessage('text', share['text']);
        } catch (e) {
          pendingText = share['text'];
          error = userError(e);
        }
      }
      final pending = <dynamic>[], completedPaths = <String>[];
      for (final entry in (share['files'] as List? ?? const [])) {
        final sent = await _tryUpload(
          entry['name'],
          () => MultipartFile.fromFile(entry['path'], filename: entry['name']),
        );
        if (sent) {
          completedPaths.add(entry['path']);
        } else {
          pending.add(entry);
        }
      }
      shared = pending.isEmpty && pendingText == null
          ? null
          : {'files': pending, 'text': ?pendingText};
      if (android && completedPaths.isNotEmpty) {
        await PlatformBridge.channel.invokeMethod<void>('clearShares', {
          'paths': completedPaths,
        });
      }
      if (signedIn && !syncPaused) await reload();
    });
  }

  Future<void> download(Map<String, dynamic> m) async {
    await run(() async {
      if (!signedIn) throw const FormatException('请先登录');
      if (syncPaused) throw const FormatException('同步已暂停，请先恢复');
      final activeApi = api!, session = _sessionGeneration;
      final payload = Map<String, dynamic>.from(m['payload']);
      final fileId = payload['file_id'];
      cancelToken = CancelToken();
      progress = 0;
      update();
      final saved = await transfer.receiveFile(
        activeApi.dio,
        '/files/$fileId/download',
        name: payload['name'] as String? ?? 'file',
        mimeType: payload['mime_type'] as String? ?? 'application/octet-stream',
        expectedHash: payload['sha256'] as String?,
        expectedSize: (payload['size'] as num?)?.toInt(),
        cancelToken: cancelToken,
        onProgress: (received, total) {
          if (_isActive(activeApi, session)) {
            progress = total > 0 ? received / total : null;
            update();
          }
        },
      );
      if (saved == null || !_isActive(activeApi, session)) return;
      final uri = Uri.parse(saved);
      if (!kIsWeb) {
        downloadedPath = uri.scheme == 'file'
            ? uri.toFilePath()
            : uri.toString();
      }
      if (m['sender_device_id'] != deviceId &&
          m['id'] is String &&
          (m['id'] as String).isNotEmpty) {
        await activeApi.dio.post<dynamic>('/messages/${m['id']}/read');
        if (!_isActive(activeApi, session)) return;
      }
      final rows = await activeApi.list('/transfers?file_id=$fileId');
      if (!_isActive(activeApi, session)) return;
      for (final t in rows.where(
        (t) => t['file_id'] == fileId && t['target_device_id'] == deviceId,
      )) {
        await activeApi.dio.patch<dynamic>(
          '/transfers/${t['id']}',
          data: {'status': 'completed', 'progress': 100},
        );
        if (!_isActive(activeApi, session)) return;
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
    if (deviceId.isNotEmpty) await prefs.remove('manual_pending_$deviceId');
    _earlyReceipts.clear();
    _nativeStateOwner = null;
    _nativeRevision = -1;
    api?.tokens = null;
    await shutdown(discardClipboard: true);
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
    syncPaused = false;
    bridge.updateTray(false, const []);
    update();
  }

  Future<void> shutdown({bool discardClipboard = false}) async {
    await _stopClipboard(discardPending: discardClipboard);
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
