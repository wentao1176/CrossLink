import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'controller.dart';
import 'protocol.dart';

final controllerProvider = Provider<CrossLinkController>((ref) {
  final controller = CrossLinkController();
  ref.onDispose(controller.dispose);
  unawaited(controller.initialize());
  return controller;
});
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: CrossLinkApp()));
}

class CrossLinkApp extends ConsumerWidget {
  const CrossLinkApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(controllerProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CrossLink',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff087f8c)),
        scaffoldBackgroundColor: const Color(0xfff5f7fa),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      home: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (controller.initializing) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return controller.signedIn
              ? HomeScreen(controller: controller)
              : LoginScreen(controller: controller);
        },
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});
  final CrossLinkController controller;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final form = GlobalKey<FormState>();
  final account = TextEditingController(),
      password = TextEditingController(),
      email = TextEditingController();
  bool register = false, obscure = true;
  @override
  void dispose() {
    for (final c in [account, password, email]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.hub_rounded, size: 40, color: Color(0xff087f8c)),
                    SizedBox(width: 12),
                    Text(
                      'CrossLink',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  '让文件与文字，在你的设备之间自由流动。',
                  style: TextStyle(color: Colors.blueGrey, fontSize: 16),
                ),
                const SizedBox(height: 28),
                Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            register ? '创建你的账号' : '连接你的设备',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 22),
                          TextFormField(
                            controller: account,
                            autofillHints: const [AutofillHints.username],
                            decoration: InputDecoration(
                              labelText: register ? '用户名（英文字母、数字、下划线）' : '用户名',
                              prefixIcon: const Icon(Icons.person_outline),
                            ),
                            validator: (s) =>
                                s == null || s.trim().isEmpty ? '请输入账号' : null,
                          ),
                          const SizedBox(height: 16),
                          if (register) ...[
                            TextFormField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: '邮箱',
                                prefixIcon: Icon(Icons.mail_outline),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            controller: password,
                            obscureText: obscure,
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: '密码',
                              helperText: register ? '至少 10 个字符' : null,
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () =>
                                    setState(() => obscure = !obscure),
                              ),
                            ),
                            validator: (s) =>
                                s == null || s.isEmpty ? '请输入密码' : null,
                          ),
                          if (c.error.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              c.error,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: c.busy
                                ? null
                                : () async {
                                    if (form.currentState!.validate()) {
                                      await c.login(
                                        account.text.trim(),
                                        password.text,
                                        email: register
                                            ? email.text.trim()
                                            : null,
                                      );
                                      if (c.signedIn) password.clear();
                                    }
                                  },
                            icon: c.busy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.arrow_forward),
                            label: Text(register ? '注册并连接' : '登录并连接'),
                          ),
                          TextButton(
                            onPressed: c.busy
                                ? null
                                : () => setState(() => register = !register),
                            child: Text(register ? '已有账号，去登录' : '还没有账号？创建账号'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '在设置中启用复制粘贴同步。文件暂存 7 天，单文件最大 100 MB。',
                  style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final CrossLinkController controller;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int page = 0;
  static const labels = ['发送内容', '我的设备', '消息记录', '剪贴板', '文件传输', '设置'];
  static const icons = [
    Icons.send_outlined,
    Icons.devices,
    Icons.forum_outlined,
    Icons.content_paste,
    Icons.folder_outlined,
    Icons.settings_outlined,
  ];
  CrossLinkController get c => widget.controller;
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 850;
    final content = Column(
      children: [
        if (c.error.isNotEmpty)
          MaterialBanner(
            content: Text(c.error),
            actions: [
              TextButton(
                onPressed: () {
                  c.error = '';
                  c.update();
                },
                child: const Text('关闭'),
              ),
            ],
          ),
        if (c.busy) ...[
          LinearProgressIndicator(value: c.progress),
          if (c.cancelToken != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => c.cancelToken?.cancel(),
                icon: const Icon(Icons.close),
                label: Text(
                  '取消传输${c.progress != null ? ' · ${(c.progress! * 100).round()}%' : ''}',
                ),
              ),
            ),
        ],
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(wide ? 32 : 16),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 950),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      labels[page],
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      c.connection,
                      style: TextStyle(
                        color: c.connection == '实时连接'
                            ? const Color(0xff087f8c)
                            : Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _body(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.hub_rounded, color: Color(0xff087f8c)),
            SizedBox(width: 10),
            Text('CrossLink', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: c.busy ? null : () => c.run(c.reload),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '退出登录',
            onPressed: c.busy ? null : c.logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  extended: true,
                  selectedIndex: page,
                  onDestinationSelected: (value) =>
                      setState(() => page = value),
                  destinations: List.generate(
                    labels.length,
                    (i) => NavigationRailDestination(
                      icon: Icon(icons[i]),
                      label: Text(labels[i]),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: page,
              onDestinationSelected: (value) => setState(() => page = value),
              destinations: List.generate(
                labels.length,
                (i) => NavigationDestination(
                  icon: Icon(icons[i]),
                  label: labels[i],
                ),
              ),
            ),
    );
  }

  Widget panel(Widget child) => Card(
    elevation: 0,
    child: Padding(padding: const EdgeInsets.all(22), child: child),
  );
  Widget empty(String text, IconData icon) => panel(
    Column(
      children: [
        Icon(icon, size: 44, color: Colors.blueGrey),
        const SizedBox(height: 16),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.blueGrey),
        ),
      ],
    ),
  );
  Widget _body() {
    switch (page) {
      case 0:
        return compose();
      case 1:
        return deviceList();
      case 2:
        return c.cache.items.isEmpty
            ? empty('还没有消息，选择设备发送第一条内容。', Icons.forum_outlined)
            : Column(children: c.cache.items.map(messageCard).toList());
      case 3:
        return c.clips.isEmpty
            ? empty('复制文字后点击「发送剪贴板」，这里会记录最近内容。', Icons.content_paste)
            : Column(
                children: c.clips
                    .map(
                      (clip) => panel(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(clip['content']),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Text(
                                  date(clip['created_at']),
                                  style: const TextStyle(
                                    color: Colors.blueGrey,
                                  ),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: () => c.copyText(clip['content']),
                                  icon: const Icon(Icons.copy),
                                  label: const Text('复制'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              );
      case 4:
        return transferList();
      default:
        return settings();
    }
  }

  Widget compose() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '发送给',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(c.target),
              initialValue: c.target ?? '',
              items: [
                const DropdownMenuItem(value: '', child: Text('全部其他设备')),
                ...c.devices
                    .where((d) => d['id'] != c.deviceId)
                    .map(
                      (d) => DropdownMenuItem<String>(
                        value: d['id'],
                        child: Text(
                          '${d['online'] ? '●' : '○'} ${d['name']} · ${d['platform']}',
                        ),
                      ),
                    ),
              ],
              onChanged: c.busy
                  ? null
                  : (value) {
                      c.target = value == '' ? null : value;
                      c.update();
                    },
            ),
            if (!c.hasPeers) ...[
              const SizedBox(height: 12),
              const Text('请在另一台设备登录同一账号'),
            ],
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in [
                  ('text', '文字'),
                  ('url', '链接'),
                  ('notification', '通知'),
                ])
                  ChoiceChip(
                    label: Text(item.$2),
                    selected: c.type == item.$1,
                    onSelected: c.busy
                        ? null
                        : (_) {
                            c.type = item.$1;
                            c.update();
                          },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: c.text,
              minLines: 4,
              maxLines: 10,
              maxLength: 100000,
              decoration: const InputDecoration(hintText: '写点什么，发送到你的另一台设备…'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: c.busy || !c.hasPeers
                  ? null
                  : () => c.run(() async {
                      await c.sendMessage(
                        c.type,
                        c.text.text,
                        title: c.type == 'notification'
                            ? '来自 ${c.deviceName}'
                            : null,
                      );
                    }),
              icon: const Icon(Icons.send),
              label: const Text('发送内容'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          OutlinedButton.icon(
            onPressed: c.busy || !c.hasPeers ? null : c.sendClipboard,
            icon: const Icon(Icons.content_paste_go),
            label: const Text('发送剪贴板'),
          ),
          OutlinedButton.icon(
            onPressed: c.busy || !c.hasPeers ? null : c.pickFiles,
            icon: const Icon(Icons.upload_file),
            label: const Text('发送文件'),
          ),
        ],
      ),
      if (c.shared != null) ...[
        const SizedBox(height: 16),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('来自 Android 分享'),
              Text(
                c.shared?['text'] ??
                    '已选择 ${(c.shared?['files'] as List?)?.length ?? 0} 个文件',
              ),
              FilledButton(
                onPressed: c.busy || !c.hasPeers ? null : c.sendShared,
                child: const Text('发送分享内容'),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 24),
      const Text(
        '对方离线也可以发送，重新连接后会自动补收。',
        style: TextStyle(color: Colors.blueGrey),
      ),
    ],
  );
  Widget deviceList() => Column(
    children: c.devices
        .map(
          (d) => panel(
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Icon(
                  d['platform'] == 'android'
                      ? Icons.phone_android
                      : Icons.computer,
                ),
              ),
              title: Text(
                '${d['name']}${d['id'] == c.deviceId ? ' · 当前设备' : ''}',
              ),
              subtitle: Text(
                '${d['platform']} · ${d['online'] ? '在线' : '离线'} · 最近活动 ${date(d['last_seen'])}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (action) async {
                  if (action == 'rename') {
                    final edit = TextEditingController(text: d['name']);
                    final value = await showDialog<String>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('修改设备名称'),
                        content: TextField(controller: edit),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, edit.text),
                            child: const Text('保存'),
                          ),
                        ],
                      ),
                    );
                    if (value != null) await c.rename(d['id'], value);
                    edit.dispose();
                  }
                  if (!mounted) return;
                  if (action == 'revoke') {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('退出这台设备？'),
                        content: Text('「${d['name']}」需要重新登录才能接收消息。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('退出设备'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) await c.revoke(d['id']);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'rename', child: Text('修改名称')),
                  const PopupMenuItem(value: 'revoke', child: Text('退出设备')),
                ],
              ),
            ),
          ),
        )
        .toList(),
  );
  Widget messageCard(Map<String, dynamic> m) {
    final p = Map<String, dynamic>.from(m['payload']);
    final file = p['file_id'] != null;
    final incoming = m['sender_device_id'] != c.deviceId;
    final sender = c.devices.where((d) => d['id'] == m['sender_device_id']);
    return panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                file
                    ? Icons.insert_drive_file_outlined
                    : Icons.chat_bubble_outline,
                size: 20,
                color: const Color(0xff087f8c),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  incoming
                      ? (sender.isEmpty ? '其他设备' : sender.first['name'])
                      : '我发送的',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${date(m['created_at'])} · ${messageStatusLabel(m['status'], incoming: incoming, file: file)}',
                style: const TextStyle(color: Colors.blueGrey, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SelectableText(
            file ? '${p['name']} · ${size(p['size'])}' : p['content'] ?? '',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              if (file)
                TextButton.icon(
                  onPressed: c.busy ? null : () => c.download(m),
                  icon: const Icon(Icons.download),
                  label: const Text('下载并保存'),
                )
              else
                TextButton.icon(
                  onPressed: c.busy ? null : () => c.copyMessage(m),
                  icon: const Icon(Icons.copy),
                  label: const Text('复制'),
                ),
              if (m['type'] == 'url')
                TextButton.icon(
                  onPressed: () => c.run(() async {
                    final uri = Uri.parse(p['content']);
                    if (['http', 'https'].contains(uri.scheme)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  }),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('打开链接'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget transferList() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (c.downloadedPath != null)
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('已保存：${c.downloadedPath}'),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: c.openDownloaded,
                    child: const Text('打开文件'),
                  ),
                  if (c.windows)
                    TextButton(
                      onPressed: c.openDownloadedFolder,
                      child: const Text('打开所在目录'),
                    ),
                ],
              ),
            ],
          ),
        ),
      if (c.transfers.isEmpty)
        empty('选择文件并发送后，传输记录会显示在这里。', Icons.folder_outlined),
      ...c.transfers.map(
        (t) => panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t['file']['name'],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${size(t['file']['size'])} · ${transferStatusLabel(t['status'], incoming: t['target_device_id'] == c.deviceId)} · ${date(t['created_at'])}',
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: (t['progress'] as num) / 100),
              if (t['target_device_id'] == c.deviceId)
                TextButton.icon(
                  onPressed: c.busy
                      ? null
                      : () => c.download({
                          'id': t['message_id'],
                          'sender_device_id': t['sender_device_id'],
                          'payload': {
                            ...Map<String, dynamic>.from(t['file']),
                            'file_id': t['file_id'],
                          },
                        }),
                  icon: const Icon(Icons.download),
                  label: const Text('下载'),
                ),
            ],
          ),
        ),
      ),
    ],
  );
  Widget settings() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CrossLink 0.2.0',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        const SizedBox(height: 20),
        Text('设备：${c.deviceName}'),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('复制粘贴同步'),
          subtitle: Text(
            c.clipboardSupported ? c.clipboardStatus : '浏览器预览支持手动发送与复制',
          ),
          value: c.clipboardSyncEnabled,
          onChanged: c.busy || !c.clipboardSupported
              ? null
              : c.setClipboardSyncEnabled,
        ),
        if (c.android)
          const Text('手机在其他 App 复制后，打开 CrossLink 即可同步。收到内容后可在其他 App 直接粘贴。')
        else if (c.windows)
          const Text('开启后，复制文字或链接会同步到同账号设备；电脑驻留托盘时也可同步。'),
        const SizedBox(height: 10),
        const Text('文件保留：7 天 · 最大 100 MB'),
        const SizedBox(height: 10),
        const Text('Android 关闭界面后继续接收消息，退出登录会停止同步。'),
        const SizedBox(height: 10),
        const Text('Windows 关闭窗口后继续驻留托盘，托盘菜单可完全退出。'),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: c.busy ? null : () => c.run(c.connect),
          icon: const Icon(Icons.sync),
          label: const Text('重新连接'),
        ),
      ],
    ),
  );
  String date(dynamic value) {
    if (value is! num) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000)
        .toLocal();
    return '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String size(dynamic value) {
    final n = (value as num?)?.toDouble() ?? 0;
    return n >= 1048576
        ? '${(n / 1048576).toStringAsFixed(1)} MB'
        : n >= 1024
        ? '${(n / 1024).toStringAsFixed(1)} KB'
        : '${n.toInt()} B';
  }
}
