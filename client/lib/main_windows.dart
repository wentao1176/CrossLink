import 'desktop_bridge.dart';
import 'desktop_windows.dart';
import 'main.dart' as app;

void main() {
  desktopBridgeFactory = WindowsDesktopBridge.new;
  app.main();
}
