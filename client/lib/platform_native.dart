import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'clipboard_sync.dart';

import 'package:flutter/services.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart' as tray;

class PlatformBridge with WindowListener {
  static const channel = MethodChannel('crosslink/native');
  tray.TrayIcon? _tray;
  tray.Menu? _menu;
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
      await windowManager.ensureInitialized();
      await windowManager.setTitle('CrossLink');
      await windowManager.setPreventClose(true);
      windowManager.addListener(this);
      await localNotifier.setup(
        appName: 'CrossLink',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _tray = tray.TrayIcon.create();
      if (_tray != null) {
        _tray!.icon = tray.ImageAsset.fromAsset('assets/tray.png');
        _tray!.setTooltip('CrossLink · 跨设备同步');
        updateTray(false, const []);
        _tray!.setVisible(true);
        _tray!.addListener((event) {
          if (event is tray.TrayIconClickedEvent) unawaited(_safe(show));
        });
      } else {
        await channel.invokeMethod<void>('showWindow');
      }
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
    if (!windows || _tray == null) return;
    final old = _menu;
    _menu = tray.Menu.create();
    void item(String label, Future<void> Function() action) {
      final entry = tray.MenuItem.createWithLabelAndType(
        label,
        tray.MenuItemType.normal,
      );
      if (entry != null) {
        entry.addListener((event) {
          if (event is tray.MenuItemClickedEvent) unawaited(_safe(action));
        });
        _menu!.addItem(entry);
      }
    }

    item('打开 CrossLink', show);
    item('我的设备（${devices.length}）', () async {
      await onNavigate?.call(1, null);
      await show();
    });
    for (final device in devices.take(8)) {
      item(
        '${device['online'] == true ? '●' : '○'} ${device['name']}',
        () async {
          await onNavigate?.call(1, null);
          await show();
        },
      );
    }
    item('设置', () async {
      await onNavigate?.call(5, null);
      await show();
    });
    item(paused ? '恢复同步' : '暂停同步', () async {
      await onTogglePause?.call();
    });
    item('发送剪贴板', () async {
      await onClipboard?.call();
    });
    item('发送文件', () async {
      await show();
      await onFiles?.call();
    });
    _menu!.addSeparator();
    item('退出', () async {
      await onExit?.call();
      await windowManager.destroy();
    });
    _tray!.setContextMenu(_menu!);
    old?.dispose();
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

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  Future<void> show() async {
    if (windows) {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  @override
  void onWindowClose() {
    unawaited(_safe(windowManager.hide));
  }

  Future<void> notify(String title, String body, {String? messageId}) async {
    if (windows) {
      final n = LocalNotification(title: title, body: body);
      n.onClick = () => unawaited(
        _safe(() async {
          await onNavigate?.call(2, messageId);
          await show();
        }),
      );
      await n.show();
    } else if (android) {
      await channel.invokeMethod<void>('notify', {
        'title': title,
        'content': body,
      });
    }
  }

  void dispose() {
    if (windows) windowManager.removeListener(this);
    _tray?.dispose();
  }
}
