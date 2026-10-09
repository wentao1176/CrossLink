import 'dart:async';

import 'package:flutter/services.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart' as tray;

import 'build_info.dart';
import 'desktop_bridge.dart';

class WindowsDesktopBridge extends DesktopBridge with WindowListener {
  static const channel = MethodChannel('crosslink/native');
  tray.TrayIcon? _tray;
  tray.Menu? _menu;
  @override
  bool get available => true;
  @override
  Future<void> initialize() async {
    await windowManager.ensureInitialized();
    await windowManager.setTitle(appName);
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    await localNotifier.setup(
      appName: appName,
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

  @override
  void updateTray(bool paused, List<Map<String, dynamic>> devices) {
    if (_tray == null) return;
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

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  @override
  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onWindowClose() {
    unawaited(_safe(windowManager.hide));
  }

  @override
  Future<void> notify(String title, String body, {String? messageId}) async {
    final n = LocalNotification(title: title, body: body);
    n.onClick = () => unawaited(
      _safe(() async {
        await onNavigate?.call(2, messageId);
        await show();
      }),
    );
    await n.show();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _tray?.dispose();
  }
}
