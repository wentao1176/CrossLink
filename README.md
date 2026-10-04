# CrossLink

跨设备文件、文字、剪贴板、链接和通知同步。根据用户开发设计文档实现 Flutter Windows/Android 客户端、浏览器预览，以及 FastAPI/PostgreSQL 中转平台。

全部开发、构建、缓存和产物在阿里云 `/home/CrossLink`，通过 SSH 操作。

## App 的使用方式

Windows 和 Android 登录页仅填写用户名、密码；设备名称自动读取，平台地址在构建时内置。登录后自动连接、显示同账号设备。默认发送给该账号其他设备，也可选定目标。服务器在后台中转，用户无需配对、输入地址或选择服务器。注册另需邮箱。

Android 使用 remoteMessaging 前台服务维持后台连接，关闭界面不等于退出登录。凭据通过 Android Keystore 加密保存在应用私有目录；后台统一负责刷新 Token、补收离线消息、保存后 ACK 和通知。退出登录会停止服务并清除凭据。Android 系统强行停止、厂商省电限制、用户拒绝通知的实际表现仍需实机验证。剪贴板目前手动发送/复制，文件最大 100 MiB。

Windows 源码包含托盘、关闭窗口驻留、通知、文件选择和剪贴板。Linux ECS 无法编译 Flutter Windows exe；`artifacts/CrossLink-0.2.0-windows-build-kit.zip` 提供源码、内置平台配置和一键构建脚本。需要 Windows、Git、Visual Studio C++ 工具链，解压后执行：

```powershell
powershell -ExecutionPolicy Bypass -File deploy/build-windows.ps1
```

脚本将工具放在包内 `.tools`，校验官方 Flutter 3.47.6 的固定 Git 提交，分析、测试并构建完整 Windows ZIP。它不会提权或安装 C++ 编译器。该 ZIP 是构建包，不能当作现成 exe 安装。

Android 测试包：`artifacts/CrossLink-0.2.0-arm64-debug.apk`，开发签名、ARM64、minSdk 24。构建包和 APK 的校验值见 `artifacts/SHA256SUMS`。

## 平台连接状态

原生 App 已内置 HTTPS 平台地址，并携带平台公开 CA；证书的 IP/主机名校验保持启用，私钥仅在服务器。无需购买或填写域名。

API、PostgreSQL、TLS 网关服务已经部署；TLS 网关当前仅监听 `127.0.0.1:8443`，代理到 API 的 `127.0.0.1:8765`。数据库仅监听 `127.0.0.1:55432`。按用户此前要求，未开放安全组、防火墙或公网监听。因此原生 App 的内置公网连接在后续开放前尚不能从外部使用；服务功能可通过 SSH 隧道验证。公开监听样例已准备，尚未启用。

浏览器预览通过 SSH 隧道：

```powershell
ssh -F NUL -N -L 127.0.0.1:18765:127.0.0.1:8765 root@47.116.203.177
```

打开 `http://127.0.0.1:18765`；浏览器也只需账号密码，自动使用页面所在平台。

## 运维和验证

```bash
ssh -o ClearAllForwardings=yes aliyun
cd /home/CrossLink
systemctl status crosslink-api crosslink-postgres crosslink-gateway
curl --cacert client/assets/platform_ca.pem https://127.0.0.1:8443/health
source deploy/flutter-env.sh
cd client
flutter analyze
flutter test
cd ..
python3 deploy/test-android.py
cd server
../.venv/bin/python -m pytest -q
```

`deploy/smoke_live.py` 验证真实 PostgreSQL、两设备发现/推送、文件哈希、权限、撤销和重启持久化，并清理测试账户。API 保持单 worker。证书续期定时器由平台私有 CA 续签叶证书，公开 CA 无需随每次续期变更。

`bash deploy/build-clients.sh` 重新构建 Web 和 Android。小内存 ECS 的 JVM 构建单独限制内存、使用现有 swap。生产数据在 `data`，私钥、平台构建配置、Token 和日志不进入源码包。Docker Compose 是未启动的替代模板；当前使用专用 systemd 服务。

本版保留设计文档中的后续功能：分片续传、OSS、自动剪贴板、P2P、E2EE、Redis 多 worker，以及邮箱验证/密码找回。Windows 二进制、实机后台稳定性和正式签名仍需相应环境验收。具体测试证据见 `docs/VERIFICATION.md`。
