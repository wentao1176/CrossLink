import 'package:flutter/services.dart';

import 'clipboard_sync.dart';

class PlatformBridge {
  static const channel = MethodChannel('crosslink/native');
  Future<void> Function(Map<String, dynamic>)? onShare;
  Future<void> Function(Map<String, dynamic>)? onBackground;
  Future<void> Function()? onClipboard;
  Future<void> Function()? onFiles;
  Future<void> Function()? onExit;
  Future<void> Function()? onTogglePause;
  Future<void> Function(int, String?)? onNavigate;
  Future<void> Function(Map<String, dynamic>)? onClipboardChange;
  Future<void> Function(Map<String, dynamic>)? onClipboardFocus;
  bool get clipboardSupported => false;
  Future<bool> watchClipboard(bool enabled, String owner) async => false;
  Future<LocalClipboard> readClipboard(String owner) async =>
      const LocalClipboard(sequence: 0, available: false);
  Future<bool> writeClipboard(String owner, String text, int sequence) async =>
      false;
  Future<String> deviceName() async => '浏览器';
  Future<Map<String, dynamic>?> backgroundSnapshot() async => null;
  Future<Map<String, dynamic>> startBackground(
    String endpoint,
    Map<String, dynamic> tokens,
  ) async => tokens;
  Future<Map<String, dynamic>> refreshBackground(
    Map<String, dynamic> tokens,
  ) async => tokens;
  Future<void> stopBackground() async {}
  Future<void> pauseBackground() async {}
  Future<void> resumeBackground() async {}
  void updateTray(bool paused, List<Map<String, dynamic>> devices) {}
  Future<Map<String, dynamic>> startupSettings() async => {};
  Future<void> setStartup(bool enabled, bool minimized) async {}
  Future<bool> notificationsEnabled() async => true;
  Future<void> initialize() async {}
  Future<void> show() async {}
  Future<void> notify(String title, String body, {String? messageId}) async {}
  void dispose() {}
}
