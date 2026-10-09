DesktopBridge Function() desktopBridgeFactory = DesktopBridge.new;

class DesktopBridge {
  Future<void> Function()? onClipboard, onFiles, onExit, onTogglePause;
  Future<void> Function(int, String?)? onNavigate;
  bool get available => false;
  Future<void> initialize() async {}
  void updateTray(bool paused, List<Map<String, dynamic>> devices) {}
  Future<void> show() async {}
  Future<void> notify(String title, String body, {String? messageId}) async {}
  void dispose() {}
}
