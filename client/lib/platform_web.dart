import 'package:flutter/services.dart';

class PlatformBridge {
  static const channel = MethodChannel('crosslink/native');
  Future<void> Function(Map<String, dynamic>)? onShare;
  Future<void> Function()? onClipboard;
  Future<void> Function()? onFiles;
  Future<void> Function()? onExit;
  Future<void> initialize() async {}
  Future<void> show() async {}
  Future<void> notify(String title, String body) async {}
  void dispose() {}
}
