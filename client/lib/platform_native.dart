import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'clipboard_sync.dart';
import 'desktop_bridge.dart';

import 'package:flutter/services.dart';

class PlatformBridge {
  static const channel = MethodChannel('crosslink/native');
  final DesktopBridge _desktop = desktopBridgeFactory();
  Future<void> Function(Map<String, dynamic>)? onShare;
  Future<void> Function(Map<String, dynamic>)? onBackground;
  Future<void> Function()? onClipboard;
  Future<void> Function()? onFiles;
  Future<void> Function()? onExit;
  Future<void> Function()? onTogglePause;
  Future<void> Function(int, String?)? onNavigate;
  Future<void> Function(Map<String, dynamic>)? onClipboardChange;
  Future<void> Function(Map<String, dynamic>)? onClipboardFocus;
  bool get clipboardSupported => windows || android;
  bool get windows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  bool get android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<String> deviceName() async {
    if (windows) return Platform.environment['COMPUTERNAME'] ?? 'Windows 电脑';
    if (android) {
      try {
        return await channel.invokeMethod<String>('deviceName') ?? 'Android 手机';
      } catch (_) {
        return 'Android 手机';
      }
    }
    return '设备';
  }

  Future<void> initialize() async {
    if (clipboardSupported) {
      channel.setMethodCallHandler((call) async {
        if (call.method == 'backgroundEvent' && call.arguments is String) {
          await onBackground?.call(
            Map<String, dynamic>.from(jsonDecode(call.arguments)),
          );
        }
        if (call.method == 'clipboardChanged' && call.arguments is Map) {
          await onClipboardChange?.call(
            Map<String, dynamic>.from(call.arguments),
          );
        }
        if (call.method == 'clipboardFocus' && call.arguments is Map) {
          await onClipboardFocus?.call(
            Map<String, dynamic>.from(call.arguments),
          );
        }
        if (call.method == 'share' && call.arguments is Map) {
          await onShare?.call(Map<String, dynamic>.from(call.arguments));
        }
      });
    }
    if (windows) {
      if (!_desktop.available) {
        throw const FormatException('当前 Windows 构建缺少桌面入口，请使用安装包');
      }
      _desktop.onClipboard = () async {
        await onClipboard?.call();
      };
      _desktop.onFiles = () async {
        await onFiles?.call();
      };
      _desktop.onExit = () async {
        await onExit?.call();
      };
      _desktop.onTogglePause = () async {
        await onTogglePause?.call();
      };
      _desktop.onNavigate = (index, messageId) async {
        await onNavigate?.call(index, messageId);
      };
      await _desktop.initialize();
    }
    if (android) {
      await channel.invokeMethod<void>('requestNotifications');
      final initial = await channel.invokeMethod<dynamic>('getInitialShare');
      if (initial is Map) {
        await onShare?.call(Map<String, dynamic>.from(initial));
      }
    }
  }

  void updateTray(bool paused, List<Map<String, dynamic>> devices) {
    if (windows) _desktop.updateTray(paused, devices);
  }

  Future<Map<String, dynamic>> startupSettings() async =>
      Map<String, dynamic>.from(
        await channel.invokeMethod<dynamic>('startupRead') ?? const {},
      );
  Future<void> setStartup(bool enabled, bool minimized) =>
      channel.invokeMethod<void>('startupWrite', {
        'enabled': enabled,
        'minimized': minimized,
      });
  Future<bool> notificationsEnabled() async =>
      await channel.invokeMethod<bool>('notificationsEnabled') ?? true;
  Future<void> pauseBackground() =>
      channel.invokeMethod<void>('backgroundPause');
  Future<void> resumeBackground() =>
      channel.invokeMethod<void>('backgroundResume');

  Future<bool> watchClipboard(bool enabled, String owner) async =>
      await channel.invokeMethod<bool>('clipboardWatch', {
        'enabled': enabled,
        'owner': owner,
      }) ??
      false;
  Future<LocalClipboard> readClipboard(String owner) async {
    final value = await channel.invokeMapMethod<String, dynamic>(
      'clipboardRead',
      {'owner': owner},
    );
    const notices = {
      'focus': '收到新内容，打开 CrossLink 后同步',
      'unsupported': '图片或文件剪贴板暂保留在本机',
      'too_large': '剪贴板文字超过 100 KiB，保留在本机',
      'busy': '剪贴板暂被其他应用占用，稍后重试',
    };
    return LocalClipboard(
      text: value?['text'] as String?,
      sequence: (value?['sequence'] as num?)?.toInt() ?? 0,
      available: value?['available'] == true,
      reason: notices[value?['reason']],
    );
  }

  Future<bool> writeClipboard(
    String owner,
    String text,
    int expectedSequence,
  ) async =>
      await channel.invokeMethod<bool>('clipboardWrite', {
        'owner': owner,
        'text': text,
        'expected_sequence': expectedSequence,
      }) ??
      false;

  Future<Map<String, dynamic>?> backgroundSnapshot() async {
    final value = await channel.invokeMethod<String>('backgroundSnapshot');
    return value == null ? null : Map<String, dynamic>.from(jsonDecode(value));
  }

  Future<Map<String, dynamic>> startBackground(
    String endpoint,
    Map<String, dynamic> tokens,
  ) async {
    final value = await channel.invokeMethod<String>('backgroundStart', {
      'endpoint': endpoint,
      'tokens': jsonEncode(tokens),
    });
    return Map<String, dynamic>.from(jsonDecode(value!));
  }

  Future<Map<String, dynamic>> refreshBackground(
    Map<String, dynamic> tokens,
  ) async {
    final value = await channel.invokeMethod<String>('backgroundRefresh', {
      'access_token': tokens['access_token'],
    });
    return Map<String, dynamic>.from(jsonDecode(value!));
  }

  Future<void> stopBackground() => channel.invokeMethod<void>('backgroundStop');

  Future<void> show() async {
    if (windows) await _desktop.show();
  }

  Future<void> notify(String title, String body, {String? messageId}) async {
    if (windows) {
      await _desktop.notify(title, body, messageId: messageId);
    } else if (android) {
      await channel.invokeMethod<void>('notify', {
        'title': title,
        'content': body,
      });
    }
  }

  void dispose() {
    _desktop.dispose();
  }
}
