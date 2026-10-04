import 'dart:io';

import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

Future<void> saveNative(String path, Uint8List bytes) async {
  if (Platform.isWindows) await File(path).writeAsBytes(bytes, flush: true);
}

Future<void> openFolder(String path) async {
  if (Platform.isWindows) await Process.run('explorer.exe', ['/select,', path]);
}

Future<bool> openSaved(String path) async {
  if (Platform.isAndroid) {
    return await const MethodChannel('crosslink/native')
            .invokeMethod<bool>('openFile', {'path': path}) ??
        false;
  }
  return launchUrl(Uri.file(path));
}

bool _trustInitialized = false;
Future<void> initializePlatformTrust() async {
  if (_trustInitialized) return;
  final ca = await rootBundle.load('assets/platform_ca.pem');
  SecurityContext.defaultContext.setTrustedCertificatesBytes(
    ca.buffer.asUint8List(ca.offsetInBytes, ca.lengthInBytes),
  );
  _trustInitialized = true;
}
