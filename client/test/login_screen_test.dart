import 'package:crosslink/controller.dart';
import 'package:crosslink/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'login requires only account and password, never platform configuration',
    (tester) async {
      final c = CrossLinkController();
      c.endpoint = 'https://internal-platform.example';
      c.deviceName = 'Automatically named device';
      await tester.pumpWidget(MaterialApp(home: LoginScreen(controller: c)));
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('服务器地址'), findsNothing);
      expect(find.text('设备名称'), findsNothing);
      await tester.tap(find.text('登录并连接'));
      await tester.pump();
      expect(find.text('请输入账号'), findsOneWidget);
      expect(find.text('请输入密码'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
