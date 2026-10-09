import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

class LocalClipboard {
  const LocalClipboard({
    this.text,
    required this.sequence,
    this.available = true,
    this.reason,
  });
  final String? text;
  final int sequence;
  final bool available;
  final String? reason;
}

class ClipboardSync {
  ClipboardSync({
    required this.deviceId,
    required this.send,
    required this.read,
    required this.write,
    required this.fetchLatest,
    required this.persist,
    Map<String, dynamic>? initialState,
    int Function()? nowSeconds,
    this.onChanged,
  }) : nowSeconds =
           nowSeconds ?? (() => DateTime.now().millisecondsSinceEpoch ~/ 1000) {
    final state = initialState ?? const <String, dynamic>{};
    _seenRevision = (state['revision'] as num?)?.toInt() ?? 0;
    _lastHash = state['local_hash'] as String?;
    _lastSequence = (state['local_sequence'] as num?)?.toInt() ?? -1;
    _blockedLocal = state['blocked_local'] == true;
    final pending = state['pending'];
    if (pending is Map &&
        pending['text'] is String &&
        pending['id'] is String) {
      _pending = Map<String, dynamic>.from(pending);
    }
  }
  final String deviceId;
  final Future<Map<String, dynamic>> Function(String text, String operationId)
  send;
  final Future<LocalClipboard> Function() read;
  final Future<bool> Function(String text, int expectedSequence) write;
  final Future<Map<String, dynamic>?> Function() fetchLatest;
  final Future<void> Function(Map<String, dynamic> state) persist;
  final int Function() nowSeconds;
  final void Function()? onChanged;
  bool enabled = false;
  bool _snapshotReady = false;
  String status = '已关闭';
  int _epoch = 0, _localGeneration = 0, _seenRevision = 0, _lastSequence = -1;
  String? _lastHash, _writingHash;
  Map<String, dynamic>? _pending, _remote;
  Future<void>? _sending, _applying;
  Future<void> _persistTail = Future<void>.value();
  bool _blockedLocal = false;
  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();
  void _status(String value) {
    status = value;
    onChanged?.call();
  }

  Map<String, dynamic> _state() => {
    'revision': _seenRevision,
    'local_hash': _lastHash,
    'local_sequence': _lastSequence,
    'blocked_local': _blockedLocal,
    'pending': _pending == null ? null : Map.of(_pending!),
  };
  Future<bool> _save() async {
    final snapshot = _state();
    final job = _persistTail.catchError((_) {}).then((_) => persist(snapshot));
    _persistTail = job;
    try {
      await job;
      return true;
    } catch (_) {
      _status('同步记录暂时无法保存，稍后重试');
      return false;
    }
  }

  Future<void> enable({bool sendCurrent = false}) async {
    enabled = true;
    _snapshotReady = false;
    final epoch = ++_epoch;
    _status('连接剪贴板');
    final generation = _localGeneration;
    final local = await read();
    if (!enabled || epoch != _epoch) return;
    if (local.available && generation == _localGeneration) {
      final value = local.text;
      final hash = value == null ? null : _hash(value);
      final changed = _lastHash != null && hash != _lastHash;
      if (value != null && value.isNotEmpty && (sendCurrent || changed)) {
        if (sendCurrent) _lastSequence = -1;
        await onLocalChange(value, local.sequence);
      } else {
        // Native counters may restart with the process. Establish this watch's
        // baseline without replacing a persisted pending operation.
        if (_pending == null) _lastHash = hash;
        _lastSequence = local.sequence;
        await _save();
      }
    }
    if (enabled && epoch == _epoch) await reconcile();
    if (enabled && status == '连接剪贴板') _status('已启用，等待复制');
  }

  Future<void> pause() async {
    enabled = false;
    _snapshotReady = false;
    ++_epoch;
    _pending = null;
    _remote = null;
    _writingHash = null;
    _status('已暂停');
    await _save();
  }

  Future<void> dispose() async {
    enabled = false;
    _snapshotReady = false;
    ++_epoch;
    _remote = null;
    _writingHash = null;
    await _save();
  }

  void connectionLost() {
    ++_epoch;
    _snapshotReady = false;
    _status('等待连接恢复');
  }

  Future<void> localUnavailable(String reason, int sequence) async {
    if (!enabled) return;
    if (reason == 'too_large' || reason == 'unsupported') {
      _blockedLocal = true;
      _pending = null;
      _lastSequence = sequence;
      ++_localGeneration;
      await _save();
    }
    _status(
      reason == 'too_large'
          ? '剪贴板文字超过 100 KiB，保留在本机'
          : reason == 'unsupported'
          ? '图片或文件剪贴板暂保留在本机，可用文件发送'
          : '系统剪贴板暂不可用，稍后重试',
    );
  }

  Future<void> onLocalChange(String text, int sequence) async {
    if (!enabled) return;
    final hash = _hash(text);
    if (_writingHash == hash) {
      _lastHash = hash;
      _lastSequence = sequence;
      return;
    }
    if (_lastHash == hash && _lastSequence == sequence) return;
    _lastHash = hash;
    _lastSequence = sequence;
    ++_localGeneration;
    if (text.isEmpty) {
      _blockedLocal = true;
      _pending = null;
      _status('本机剪贴板已清空，等待下一次复制');
      await _save();
      return;
    }
    if (utf8.encode(text).length > 102400) {
      _blockedLocal = true;
      _pending = null;
      _status('剪贴板文字超过 100 KiB，已保留在本机');
      await _save();
      return;
    }
    _blockedLocal = false;
    _pending = {'text': text, 'id': const Uuid().v4()};
    if (!await _save()) return;
    await _flush();
    if (_applying == null && enabled) await _apply();
  }

  Future<void> _flush() async {
    if (_sending != null) return _sending;
    final job = _flushLoop();
    _sending = job;
    try {
      await job;
    } finally {
      if (identical(_sending, job)) _sending = null;
    }
  }

  Future<void> _flushLoop() async {
    final epoch = _epoch;
    while (enabled && epoch == _epoch && _pending != null) {
      final pending = Map<String, dynamic>.from(_pending!);
      if (!await _save() || !enabled || epoch != _epoch) return;
      _status('正在同步');
      try {
        final result = await send(pending['text'], pending['id']);
        if (!enabled || epoch != _epoch) return;
        final version = (result['payload'] as Map?)?['clipboard_revision'];
        if (version is! num || version <= 0) {
          throw StateError('Missing clipboard revision');
        }
        if (version > _seenRevision) _seenRevision = version.toInt();
        if (_pending?['id'] == pending['id']) _pending = null;
        await _save();
        _status('已发送，等待其他设备接收');
      } catch (_) {
        if (enabled && epoch == _epoch) _status('等待网络恢复后同步');
        return;
      }
    }
  }

  bool _valid(Map<String, dynamic> message) {
    final payload = message['payload'];
    if (message['type'] != 'clipboard' || payload is! Map) return false;
    final text = payload['content'],
        version = payload['clipboard_revision'],
        expires = payload['expires_at'];
    return text is String &&
        text.isNotEmpty &&
        utf8.encode(text).length <= 102400 &&
        version is num &&
        version > 0 &&
        expires is num &&
        expires > nowSeconds() &&
        payload['content_hash'] == _hash(text);
  }

  Future<void> onRemoteClipboard(Map<String, dynamic> message) async {
    if (!enabled || !_valid(message)) return;
    final version = (message['payload']['clipboard_revision'] as num).toInt();
    if (version <= _seenRevision) return;
    if (_remote == null ||
        version > (_remote!['payload']['clipboard_revision'] as num)) {
      _remote = Map.of(message);
    }
    await _apply();
  }

  Future<void> _apply() async {
    if (_applying != null) return _applying;
    final job = _applyLoop();
    _applying = job;
    try {
      await job;
    } finally {
      if (identical(_applying, job)) _applying = null;
    }
  }

  Future<void> _applyLoop() async {
    final epoch = _epoch;
    while (enabled && _snapshotReady && epoch == _epoch && _remote != null) {
      if (_pending != null || _blockedLocal) return;
      final message = Map<String, dynamic>.from(_remote!);
      final payload = message['payload'] as Map;
      final version = (payload['clipboard_revision'] as num).toInt();
      if (version <= _seenRevision || !_valid(message)) {
        _remote = null;
        continue;
      }
      if (message['sender_device_id'] == deviceId) {
        _seenRevision = version;
        _remote = null;
        await _save();
        continue;
      }
      final generation = _localGeneration;
      final local = await read();
      if (!enabled || epoch != _epoch) return;
      if (generation != _localGeneration) continue;
      if (!local.available) {
        _status(local.reason ?? '收到新内容，打开 CrossLink 后同步');
        return;
      }
      if (local.text == null &&
          local.sequence != _lastSequence &&
          _lastHash != null) {
        await onLocalChange('', local.sequence);
        continue;
      }
      if (local.text != null &&
          _lastHash != null &&
          (_hash(local.text!) != _lastHash ||
              local.sequence != _lastSequence)) {
        await onLocalChange(local.text!, local.sequence);
        continue;
      }
      if (generation != _localGeneration || _pending != null) continue;
      final text = payload['content'] as String;
      _writingHash = _hash(text);
      bool written;
      try {
        written = await write(text, local.sequence);
      } catch (_) {
        written = false;
      } finally {
        _writingHash = null;
      }
      if (!enabled || epoch != _epoch) return;
      if (!written) {
        _status('收到新内容，等待系统剪贴板可用');
        return;
      }
      if (version > _seenRevision) _seenRevision = version;
      if (generation == _localGeneration) {
        final current = await read();
        if (!enabled || epoch != _epoch) return;
        if (current.available && current.text == text) {
          _lastHash = _hash(text);
          _lastSequence = current.sequence;
        }
      }
      if (_remote?['id'] == message['id']) _remote = null;
      await _save();
      _status('另一端内容已写入剪贴板，可直接粘贴');
    }
  }

  Future<void> reconcile() async {
    if (!enabled) return;
    final epoch = _epoch;
    try {
      await _flush();
      if (!enabled || epoch != _epoch || _pending != null) return;
      final generation = _localGeneration;
      final local = await read();
      if (!enabled || epoch != _epoch || generation != _localGeneration) return;
      if (local.available &&
          local.text != null &&
          _lastHash != null &&
          (_hash(local.text!) != _lastHash ||
              local.sequence != _lastSequence)) {
        await onLocalChange(local.text!, local.sequence);
      }
      if (!enabled || epoch != _epoch || _pending != null) return;
      final latest = await fetchLatest();
      if (!enabled || epoch != _epoch) return;
      _snapshotReady = true;
      if (latest != null) await onRemoteClipboard(latest);
      await _apply();
    } catch (_) {
      if (enabled && epoch == _epoch) _status('等待网络恢复后同步');
    }
  }
}
