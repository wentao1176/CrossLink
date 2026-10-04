import 'package:flutter/services.dart';

class PlatformBridge {
  static const channel = MethodChannel('crosslink/native');
  Future<void> Function(Map<String, dynamic>)? onShare;
  Future<void> Function(Map<String, dynamic>)? onBackground;
  Future<void> Function()? onClipboard;
  Future<void> Function()? onFiles;
  Future<void> Function()? onExit;
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
  Future<void> initialize() async {}
  Future<void> show() async {}
  Future<void> notify(String title, String body) async {}
  void dispose() {}
}
