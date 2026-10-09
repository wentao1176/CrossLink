import 'dart:io';

Directory transferTestRoot() => Directory(
  Platform.environment['CROSSLINK_TEST_TMP'] ??
      (Platform.isWindows
          ? '${Directory.current.parent.path}/.build/test-transfer-cache'
          : '/home/CrossLink/.tools/test-transfer-cache'),
);
