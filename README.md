# CrossLink

跨设备文件、文字、剪贴板、链接和通知同步。根据 `docs/DEVELOPMENT_DESIGN.md` 实现首版 MVP，共用 Flutter 客户端 + FastAPI + PostgreSQL。

所有源码、工具缓存、数据和产物在阿里云 `/home/CrossLink`。只通过 SSH 操作；当前未开放公网服务、安全组或修改已有项目。

## 现在如何使用

Windows PowerShell 运行 SSH 隧道（保持这个终端打开；禁用配置中的远程代理转发）：

```powershell
ssh -F NUL -N -L 127.0.0.1:18765:127.0.0.1:8765 root@47.116.203.177
```

浏览器访问 `http://127.0.0.1:18765`，注册账号并登录。浏览器自动使用当前站点地址；客户端可在登录页配置服务器地址。原生客户端使用 HTTPS 公网地址，或者 `http://127.0.0.1:8765` SSH/ADB 隧道。连接同账号的另一台设备后选择目标，发送文字、剪贴板或文件；离线消息在重新连接时补收。

Android 安装包位于 `artifacts/CrossLink-0.1.0-arm64-debug.apk`（开发测试签名）。服务器侧下载方式可用 `scp`，本次开发没有把产物下载到本地。公网 HTTPS 未启用前，实机可通过电脑的 SSH 隧道与 `adb reverse tcp:8765 tcp:18765` 接入，再配置 `http://127.0.0.1:8765`。APK 不内置服务器地址。

Windows 需要 Windows 上的 Flutter 和 Visual Studio C++ 工具链编译（Linux ECS 无法生成 Windows exe）：

```powershell
cd client
flutter pub get
flutter build windows --release
```

Windows 启动后关闭窗口会驻留托盘，托盘菜单可打开、发文件、发剪贴板或退出。Android 支持系统分享、前台实时消息、通知和系统文件保存；未实现后台 foreground service/厂商保活，应用退出后会在下次连接补收。默认只手动发送剪贴板。客户端本地缓存最近 100 条消息（SharedPreferences），原生 Token 在系统 SecureStorage；浏览器 Token 只在内存，刷新页面后重新登录。

## 服务器服务

```bash
ssh -o ClearAllForwardings=yes aliyun
cd /home/CrossLink
systemctl status crosslink-api crosslink-postgres
curl http://127.0.0.1:8765/health
journalctl -u crosslink-api -n 50 --no-pager
```

API 专用账户 crosslink，PostgreSQL 专用账户 postgres；API 仅 `127.0.0.1:8765`，独立数据库仅 `127.0.0.1:55432`。数据在 `data/postgres`、`data/files`；随机密钥在 `.env`，Git 忽略。系统软件包和 `/etc/systemd/system` 两个必要服务定义由操作系统管理，业务代码和数据均在项目目录。当前发行版提供 PostgreSQL 13.23；Compose 模板使用 PostgreSQL 16，未来正式公网部署时可迁移到受支持新版。

验证：

```bash
cd /home/CrossLink/server
/home/CrossLink/.venv/bin/python -m pytest -q
cd /home/CrossLink/client
source /home/CrossLink/deploy/flutter-env.sh
flutter analyze
flutter test
cd /home/CrossLink
CROSSLINK_RESTART_TEST=1 .venv/bin/python deploy/smoke_live.py
```

最后一条会短暂重启 CrossLink API，创建并清理专属测试账户，验证真实 PostgreSQL、双设备 websocket、2 秒内推送、文件/权限、重启持久化和撤销 Token。

重新构建 `bash deploy/build-clients.sh` 后 `systemctl restart crosslink-api` 更新 Web。构建缓存在 `.tools`，日志在 `logs`。服务开机自动启动，支持失败重启。上传失败/取消清理半成品，文件到期每小时清理，启动时也清理；不代表备份。

## 部署与后续

`deploy/crosslink-*.service` 是当前 native 部署；`docker-compose.yml` 是替代方案模板，尚未启动 Docker。使用 Compose 前安装 Docker、停止 native 服务，填写 `.env` 中 POSTGRES_PASSWORD/JWT_SECRET，构建 Web，运行 `docker compose up -d --build`；原生 PostgreSQL 数据与 Docker 数据卷不能直接互用，应 pg_dump/pg_restore 迁移。

`deploy/nginx.conf.example` 是未来 HTTPS 配置，需确定域名、证书后才启用，之后再讨论安全组 443。当前没有域名、TLS、公开注册入口或 Redis 多进程消息总线。账号没有邮箱验证、找回密码、验证码功能；MVP 为自用测试版。首次启动创建 schema，后续 schema 变更需正式迁移工具。

下一阶段：Windows 构建与实机验收、Android 后台稳定性与正式签名、公网 HTTPS；之后再按路线做分片续传、OSS、自动剪贴板。
