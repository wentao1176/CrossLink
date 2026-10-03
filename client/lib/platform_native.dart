import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart' as tray;

class PlatformBridge with WindowListener {
  static const channel = MethodChannel('crosslink/native');
  tray.TrayIcon? _tray;
  tray.Menu? _menu;
  Future<void> Function(Map<String, dynamic>)? onShare;
  Future<void> Function()? onClipboard;
  Future<void> Function()? onFiles;
  Future<void> Function()? onExit;
  bool get windows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  bool get android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<void> initialize() async {
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
        _tray!.setVisible(true);
        _tray!.addListener((event) {
          if (event is tray.TrayIconClickedEvent) unawaited(_safe(show));
        });
      }
    }
    if (android) {
      channel.setMethodCallHandler((call) async {
        if (call.method == 'share' && call.arguments is Map) {
          await onShare?.call(Map<String, dynamic>.from(call.arguments));
        }
      });
      await channel.invokeMethod<void>('requestNotifications');
      final initial = await channel.invokeMethod<dynamic>('getInitialShare');
      if (initial is Map) {
        await onShare?.call(Map<String, dynamic>.from(initial));
      }
    }
  }

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

  Future<void> notify(String title, String body) async {
    if (windows) {
      final n = LocalNotification(title: title, body: body);
      n.onClick = () => unawaited(_safe(show));
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
