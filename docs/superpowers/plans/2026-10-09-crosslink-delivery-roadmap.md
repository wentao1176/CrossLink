# CrossLink 后续交付路线 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 本路线沿用用户已授权的 SSH 操作方式，按阶段执行；本次仅制定路线，不执行产品修改、采购、外部发布或公网开放。

**Goal:** Windows 与 Android 用户安装客户端后，仅输入同一账号的用户名和密码，就能自动发现设备，经隐式平台中转互传文字、剪贴板、链接、通知和文件。复制粘贴同步属于首版核心：启用后，将一端复制的文字/链接同步到另一端系统剪贴板，供用户直接粘贴；Android 后台读取限制必须先验证并明确可用路径。

**Architecture:** 沿用 Flutter Windows/Android 客户端、Android 原生后台接收服务、FastAPI 单 worker、PostgreSQL 和 HTTPS/WSS 网关。账号负责设备归属和投递权限，平台负责中转、离线保存与回执；平台地址和公开 CA 由构建过程内置。日常使用无需服务器地址、端口、配对码、SSH 或用户自行部署服务。

**Tech Stack:** 现有 Flutter 3.47.6 / Dart 3.13.5、Kotlin / OkHttp、FastAPI / SQLAlchemy、PostgreSQL、systemd / nginx；锁定当前工具链，新增依赖仅为明确交付需求引入。

**Spec:** `/home/CrossLink/docs/DEVELOPMENT_DESIGN.md`；补充约束来自用户关于 `/home/CrossLink`、全程 SSH、暂不开放安全组、用户名密码登录与同账号自动互传的说明。历史实施与验证见 `docs/IMPLEMENTATION.md`、`docs/VERIFICATION.md`。第一阶段的具体修复步骤见同目录 `2026-10-09-crosslink-stabilization.md`。

## 1. 当前基线：2026-10-09

基线提交：`c9f12d8630c681b66306f91ca1dfb6f97030dd69`。以下区分代码实现、自动验证和真实设备验收。

| 项目 | 已有证据 | 仍欠缺 |
|---|---|---|
| 账号、设备、消息、文件中转 | 本轮重新运行后端 30 项测试通过；真实 PostgreSQL、HTTPS/WSS 两模拟设备联调通过 | 审查发现的改名、回执、文件清理、历史分页问题 |
| 共享客户端 | 本轮 13 项测试通过，静态分析通过；账号密码登录，地址隐藏 | 安卓连接状态复现用例失败；下述体验补齐 |
| Android | 0.2.0 ARM64 debug APK 已生成，哈希一致；后台服务代码存在 | Release 签名、实际后台/权限/文件打开验收 |
| Android 原生 JVM | 10 月 4 日的 7 项测试记录通过 | 本轮未重跑，不视为 10 月 9 日新证据；后续原生修改必须重跑 |
| Windows | Flutter 原生工程、托盘和通知源码、源码构建包 | Windows 构建环境、可执行程序、安装包、实际运行证据 |
| 部署 | API、数据库、网关正常；HTTPS 健康检查通过 | 公网入口尚未开放，外部 App 不能直接连接 |

现有安装产物在 `/home/CrossLink/artifacts`。Android 测试包不是正式发布包，Windows build-kit 是源码而非可运行客户端。旧验证文档描述的是当时记录，不覆盖本次发现的新问题。

## 2. Global Constraints

以下沿用 `AGENTS.md` 的工程约束：

- All development, installs, tests and builds run via SSH in /home/CrossLink. No local generated artifacts.
- Preserve the user-provided docs/DEVELOPMENT_DESIGN.md as the requirements authority.
- API prefix /api/v1; database entity IDs are UUIDs.
- Check ownership on every device/message/receipt/file/transfer operation.
- Websocket events use event/event_id/timestamp/data; clients send auth after connection, never in the URL.
- Persist messages before publishing and keep receipts per device.
- No plaintext passwords or token/clipboard logging.
- Network operations require timeouts and websocket reconnection.
- Files require bounded upload, cancellation and cleanup.
- Platform endpoints are injected at build time, never entered or displayed in the user interface (user requirement 2026-10-04).
- Test new business behavior and update CHANGELOG.md.
- Keep one API worker until a Redis message bus is implemented.
- No public listeners or firewall/security-group changes without the user's later request.

Windows 特殊依赖：当前阿里云主机是 Linux，现有 Flutter Windows 构建需要 Windows 与 Visual Studio C++ 工具链。工程、调度、归档中心仍在 `/home/CrossLink`；真正生成 Windows 二进制需使用获准的远端 Windows 构建节点，经 SSH 调度，将产物回传服务器。当前没有已确认可用的节点，也不假设可用账号、CI 仓库或付费资源。用户 2026-10-09 已追加授权使用本地电脑，并允许安装必要 C++ Build Tools 与确认 UAC。因此 Windows 构建改用受控本地目录 `D:/aliyun/CrossLink/.build`，源码与最终归档仍在服务器；该授权是此前不在本机安装开发环境的明确例外。没有可用工具链时不以 Web 或源码包替代。依据：[Flutter Windows 环境文档](https://docs.flutter.dev/platform-integration/windows/setup)。

第一轮交付边界：单文件上限暂保留 100 MiB、文件默认保留 7 天、文字/链接复制粘贴同步和手动剪贴板补充入口、固定平台中转。用户 2026-10-09 补充“不要忘记复制粘贴同步”，因此自动文本剪贴板能力调整为首版 C4，不再放在远期增强。原设计第 39 节建议的 2 GB 尚未实现，必须在流式收发、容量控制和续传能力成熟后提升；可选保留期也列入后续增强。不要将这些差距写成已经完成。

## 3. Review Focus

这五类情况必须获得明确测试证据，不能只跑正常登录发送：

1. 原生后台仍在线，Flutter 界面重建、重新附着或快速退出再登录：状态真实、只有一个刷新/连接拥有者，旧回调不能恢复会话。归属 S1、C2。
2. 发送后对方离线、广播中仅部分设备收到、回执重复或在重连期间丢失：状态可恢复且不倒退，不重复通知。归属 S3、C4、A1。
3. 上传在最终文件落盘与数据库提交之间中断，或取消/磁盘不足：不误删有效文件、不永久遗留孤儿。归属 S4、C3、O1。
4. 大文件、中文/空格文件名、同名保存、取消保存、下载中切网：数据一致，界面响应，失败有明确状态。归属 C3、A1。
5. 不同账号、目标设备撤销、凭据过期、升级安装、Windows 重启与安卓省电限制：账号隔离成立，恢复行为有实测边界。归属 C1、B1、B2、A1、O1。

## 4. 里程碑与完成定义

| 阶段 | 任务 | 出口条件 | 依赖 |
|---|---|---|---|
| M1 修复基线 | S1–S5 | 5 个审查问题有回归用例并修复；原测试无回退 | 当前环境即可 |
| M2 补齐使用体验 | C1–C4，优先 C4 | 复制→平台中转→目标系统剪贴板→粘贴完整通过，随后补齐托盘/分享与文件流程 | M1；原生剪贴板与 Windows 验证需真实设备 |
| M3 生成真实安装包 | B1、B2 | Windows exe/安装程序、Android release APK 均来自同一提交 | Windows 节点、签名配置 |
| M4 私有通道实机联调 | A1 | Windows 与安卓实机通过双向互传、离线补收和恢复矩阵 | M3、可操作测试设备 |
| M5 平台对外启用 | O1、O2 | 获得用户开放授权后，经外网验证内置地址可用 | M4、备份/回滚准备、用户授权 |
| M6 连续使用与交付 | R1 | 72 小时记录、升级/回滚演练、产物与限制清单齐全 | M5 |

交付门槛按验收结果判定，不用代码行数、完成百分比或测试数量代替。Windows 节点的只读环境核对尽早开展，避免其他阶段全部完成后才发现无法构建。服务器上的 Gradle/APK 与 Flutter 重任务仍顺序执行，防止小内存主机再次 OOM。

## 5. M1：修复已确认问题

详见配套修复计划，每项独立测试、独立提交、更新 CHANGELOG。

| ID | 任务 | 主要文件 | 验收 |
|---|---|---|---|
| S1 | Android 已有后台连接的状态回传 | `client/lib/controller.dart`、`platform_native.dart`、`MainActivity.kt`、`SyncClient.kt` | 重开界面/点重连时显示实际状态；不创建第二套连接 |
| S2 | 自定义设备名持久保持 | `server/app/accounts.py`、`client/lib/controller.dart` | 本机或另一端改名，注销重登后名称不恢复为旧值 |
| S3 | 发送端实时收到送达/已读回执 | `server/app/messages.py`、`realtime.py`、客户端两条事件路径 | 单播实时更新，广播按各接收设备聚合，重连可补齐 |
| S4 | 文件系统与数据库对账清理 | `server/app/files.py`、`main.py` | 回收过期孤儿；新上传/仍活动/有有效引用文件保留 |
| S5 | 同秒消息稳定分页 | `server/app/messages.py`、`docs/API.md` | 时间与 ID 复合游标，边界不漏、不重复、仍检查所有权 |

- [ ] 按 S1 → S2 → S3 → S4 → S5 执行；接口变化先落服务端兼容逻辑再接客户端。
- [ ] 完成已有后端、Dart、原生 JVM 测试及新增用例，不只报告旧的 50 项记录。
- [ ] 用 HTTPS/WSS 真实数据库联调验证新回执；测试账号和文件在 finally 中清理。
- [ ] 记录修复后提交与证据，建议标记为 0.2.1 内部稳定版；尚不宣称实机验收完成。

## 6. M2：把源码能力补成日常可用流程

### C1：账号、设备与消息状态体验

**Files:** 修改 `client/lib/controller.dart`、`client/lib/main.dart`、`client/lib/protocol.dart`；新增 `client/test/device_flow_test.dart`；复用 `client/test/login_screen_test.dart`。

**Interfaces:** 沿用 `/auth/*`、`/devices`、`/messages` 与 S3 回执事件。界面连接状态只有“连接中/已连接/网络中断，正在重连/登录失效”；原生状态不得由一次 HTTP 请求成功推定。

- [ ] 保持登录仅用户名和密码；注册沿用现有邮箱输入。先补齐首次登录、自动恢复登录、错误密码、会话撤销、退出后重新登录的可见结果。
- [ ] 账号下没有其他设备时提示“请在另一台设备登录同一账号”，不能表现成已向另一端送达；有其他设备时自动列出，支持选定目标或全部其他设备。
- [ ] 将 pending/delivered/read 和文件 waiting/completed/expired 等协议值转换为清晰中文；“对方收到文件通知”和“对方已下载完成”分别显示。
- [ ] 对同账号第三台设备登录、设备改名和撤销，实时更新列表及当前选中项；设备退出后恢复默认目标，避免发送到失效 ID。
- [ ] 文字发送重试保留该次操作的 `client_message_id`，确认发送成功或用户编辑后开始新操作才生成新 ID。测试“服务端已保存但客户端响应丢失”的重复发送不会创建第二条消息。
- [ ] 验证登录页/设置页/错误提示无平台地址输入、IP、端口或原始连接异常；开发运维文档可以记录地址。

测试必须覆盖：两个同账号设备自动互见、不同账号不可见、无其他设备提示、撤销当前设备返回登录页、目标撤销不导致下拉列表断言错误、重新登录不串历史。

```bash
cd /home/CrossLink
. deploy/flutter-env.sh
cd client
flutter --no-version-check test --no-pub test/login_screen_test.dart test/device_flow_test.dart
```

出口：不看操作手册也能理解当前是否连接、发给谁、是否送达。

### C2：Windows 常驻与 Android 系统入口

**Files:** 修改 `client/lib/platform_native.dart`、`client/lib/controller.dart`、`client/lib/main.dart`、`client/windows/runner/main.cpp`、`client/android/app/src/main/kotlin/com/crosslink/crosslink/MainActivity.kt`、`SyncService.kt`；新增 `client/test/platform_lifecycle_test.dart` 和 `docs/NATIVE_ACCEPTANCE.md`。

**Interfaces:** 保留现有 PlatformBridge；新增用户设置 `startWithWindows`、`startMinimized`、`syncPaused`。暂停关闭传输连接但保留账号；恢复走正常连接与补收流程；退出登录仍撤销/清除凭据。Android 新增 `pauseBackground()` 和 `resumeBackground()`：前者停止连接/服务并持久保存暂停标记，后者清除暂停标记并用原凭据恢复；现有 `backgroundStop()` 继续专用于退出并清除凭据，不能用它实现暂停。

- [ ] Windows 增加可选登录系统后启动、启动到托盘，设置可随时关闭；启动项只作用于当前用户，避免全机提权。检查重复打开只激活一个主窗口。
- [ ] 补齐托盘的设备列表、设置、暂停/恢复入口；区分关闭窗口驻留、暂停同步、完全退出。
- [ ] Windows 消息通知点击后定位对应记录；文本可复制、文件可进入下载操作。文件“忽略通知”不伪造下载完成，也不删除服务器文件。
- [ ] Android 分享文字、单个/多个文件可在未启动或已启动 App 两种情况下进入发送确认；未登录先登录，分享内容继续保留。
- [ ] Android 通知权限被拒绝时仍允许前台互传，界面解释通知能力；用户主动退出登录立即停止后台连接。
- [ ] Android 主动暂停/恢复、界面重建、系统回收后重进及切网均复用 S1 的真实状态；不承诺用户强制停止后仍持续接收。后台服务限制依据 [Android 官方说明](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)。
- [ ] 剪贴板控制统一由 C4 管理：用户可启用同步、暂停、选择仅手动；平台能力和权限导致的限制在设置中准确显示。自动监听、接收写入、去重、历史恢复由同一协调器处理，避免各入口重复实现。

测试分两层：Dart/通道测试校验动作和会话生命周期；原生实机测试核对托盘、开机启动、系统通知、分享、剪贴板和厂商省电行为。前一层通过不能把后一层勾成通过。

出口：电脑正常常驻，手机可从系统分享菜单发送；退出、暂停、后台状态符合用户能理解的含义。

### C3：文件操作与较大文件内存收敛

**Files:** 修改 `client/lib/controller.dart`、`client/lib/native_io.dart`、`client/lib/native_stub.dart`、`client/lib/main.dart`、Android `MainActivity.kt`；新增 `client/lib/file_transfer.dart`、`client/test/file_transfer_test.dart`，更新 `client/test/controller_network_test.dart`。

**Interfaces:** 保持服务端文件 API。原生客户端下载到应用私有临时路径，流式 SHA256 校验后保存；Android `saveFile` 接收 `{path, name, mime_type}`，返回完整 `content://` URI，不再通过 MethodChannel 传递整份文件字节。Web 的文件保存流程保留独立实现。

- [ ] 将原生“整文件读入内存再复制到通道”的下载方式改为流式临时文件，校验完成后再提供系统保存；取消、校验失败、保存失败均清理自身临时文件。
- [ ] 统一最大文件大小来源，由构建配置/平台能力返回当前值；首版为 100 MiB，UI 显示一致；超过限制在上传前给出明确提示，服务端仍独立校验。
- [ ] 显示名称、类型、大小、方向、目标、进度、状态；取消与失败后允许重新发送/下载，不把按钮点击视为完成。
- [ ] 多文件顺序发送，逐项展示结果；一个文件失败不会把其余文件显示成成功。保存对话框取消不写已读/完成回执。
- [ ] 保存后可打开文件；Windows 可打开所在目录；Android 保留完整 SAF URI 并正确授权文件查看器。
- [ ] 验证 UTF-8/中文/空格、同名文件、0 字节、1 MiB、10 MiB、100 MiB、超过上限、哈希错误、下载中切网、用户取消等场景。

出口：100 MiB 文件在目标手机上可收、可保存、可打开，过程中不因整文件跨通道复制导致崩溃；双方 SHA256 一致。2 GB 与断点续传归入后续增强。

### C4：首版核心——跨设备复制粘贴同步

用户补充要求优先于此前将自动监听后置的路线。本轮先确定文字和链接的完整同步；图片及“复制文件后跨端粘贴”的首版范围正在向用户核对，收到答案后更新本节，不能把普通文件发送误称为文件剪贴板同步。当前代码仍是手动发送/复制，下面是必须实施和验证的增量。

**Files:** 新增 `client/lib/clipboard_sync.dart`、`client/test/clipboard_sync_test.dart`、`docs/CLIPBOARD_ACCEPTANCE.md`；修改 `client/lib/controller.dart`、`client/lib/platform_native.dart`、`client/lib/main.dart`、`client/windows/runner/flutter_window.cpp`、`client/windows/runner/flutter_window.h`、Android `MainActivity.kt`/`SyncService.kt`、`server/app/messages.py`、`server/app/models.py`、`server/tests/test_api.py`；新增 `deploy/migrations/002_clipboard_revision.sql`；更新 `docs/API.md` 与 `docs/WEBSOCKET.md`。

**Interfaces:** 沿用 `POST /api/v1/messages` 的 `type=clipboard` 与 `clipboard.updated`；服务端生成 `origin_device_id`、`content_hash`，为新剪贴板事件分配账号内递增 `clipboard_revision`。版本通过数据库行锁/原子递增生成，不能信任客户端传入值；先检查 client_message_id 幂等命中，命中时复用原消息及原版本，不重复分配版本；旧消息缺少版本时仅展示历史，不自动覆盖系统剪贴板。新增 `GET /api/v1/clipboard/latest` 返回当前设备可见、尚在保留期内的最新版本或 null，用于重连收敛；仍做账号和消息可见性校验。

客户端协调器提供 `start()`、`pause()`、`dispose()`、`onLocalChange(text, localSequence)` 与 `onRemoteClipboard(message)`；只有一个模块负责本机监听和远端写入，按当前账号、设备、会话代次隔离。开关 `clipboardSyncEnabled` 由用户首次启用，之后持久保存；暂停、退出登录后卸载监听，不继续读取/发送。服务端投递成功和目标剪贴板写入成功分别记录，普通 delivered ACK 不等于粘贴能力已经验证。

- [ ] **先验证平台能力。** Windows 在有真实桌面会话的节点上验证 `AddClipboardFormatListener`/`WM_CLIPBOARDUPDATE`，读取 Unicode 文本，写入后在另一应用 Ctrl+V。Android 分别验证 App 获焦点时读取、失去焦点时读取、接收后前台写入、接收后后台写入；记录系统版本、机型和成功/拒绝结果。后台服务存在不能作为剪贴板访问权限的证据。
- [ ] **实现 Windows 自动收发。** 开启同步后，在其他应用复制文本，即使 CrossLink 驻留托盘也触发一次发送；收到可应用的新版本后写入系统剪贴板，用户在目标应用直接 Ctrl+V。不轮询全文日志，不自动执行链接或把文字当命令。
- [ ] **实现 Android 明确可用路径。** 非默认输入法的普通 App 在 Android 10 及以上不能在未获焦点时读取剪贴板；先保证 App 获焦点时读取并同步、接收后可用系统粘贴。手机在其他应用复制后，可在重新进入 CrossLink 时检测当前剪贴板并发送，或通过分享入口发送；这些额外动作应如实展示，不能称为任意应用下的全后台无感同步。手机后台接收并写入剪贴板单独实测，不把后台读限制直接推导成写入也一定不可用。若用户要求全后台无感，系统集成方案可行性必须先完成并说明所需能力，不能用一个前台服务承诺绕过系统限制。
- [ ] **防回传循环和重复。** 远端写入记录消息 ID、来源设备、内容哈希及对应本机剪贴板序列；该次写入触发的本机监听事件必须被消费，不能再次上传。重复事件/ACK 不重复写入，不出现 PC→手机→PC 无限循环；用户以后主动重新复制同样文字仍可构成新操作，不能永久按 hash 封锁。
- [ ] **处理旧内容与离线恢复。** 自动写入只接收大于本地已处理版本的事件；历史页面加载不修改剪贴板。重连时读取最新快照并合并，不按消息补发顺序轮流覆盖旧内容。离线期间本机已发生新的复制时，不用服务器旧快照覆盖它；将本地待同步事件保留稳定 client_message_id，再按服务端确认版本收敛。多端并发复制以平台提交顺序收敛，界面保留历史供用户找回其他内容。
- [ ] **保持内容一致。** 中文、Emoji、换行、URL、空格与制表符传输后粘贴结果一致；空剪贴板或暂时无法读取不误发为清空远端。继续遵循服务端 100 KiB UTF-8 文本上限，超限明确提示；不在日志记录原文。
- [ ] **补足自动化回归。** 用假剪贴板源/写入器和受控时钟验证：本机复制一次只发送一次；远端更新写入一次且不回传；重复/乱序版本不倒退；账号切换旧事件无效；暂停/注销停止监听；离线新本地复制不被旧快照覆盖；重连后内容收敛。服务端增加并发版本分配、幂等重发不增加第二条记录、latest 可见性和过期测试。
- [ ] **双向实机验收。** Windows 复制→Android 长按粘贴；Android 复制→Windows Ctrl+V；两个 Windows 设备后台互拷（具备第二台时）；中文/多行/URL；连续快速复制；同时复制；断网恢复；锁屏/后台/系统清理后的实际表现。分别记录“全自动”“需 App 获焦点”“需手动补充”，不把三者合并成一个通过结论。

Windows 原生监听依据：[Microsoft 剪贴板监听接口](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-addclipboardformatlistener)。Android 读取限制依据：[Android 10 剪贴板访问说明](https://developer.android.com/about/versions/10/privacy/changes#clipboard-data)。Android 系统写入/粘贴接口依据：[Copy and paste](https://developer.android.com/develop/ui/views/touch-and-input/copy-paste)。

**出口:** 开启同步后，受支持场景中实现“复制→平台中转→另一端系统剪贴板→直接粘贴”；两端均完成真实粘贴验证。Android 普通权限无法覆盖的后台读取情形必须有明确说明和可用补充入口；仅在 CrossLink 消息列表里看到文本不算复制粘贴同步验收通过。

## 7. M3：构建与安装交付

### B1：Windows 可执行程序与安装包

**Files:** 修改 `deploy/build-windows.ps1`、`deploy/package-windows-kit.py`；新增 `deploy/windows-installer.iss`、`docs/WINDOWS_BUILD.md`；必要时修改 `client/windows/runner/*`。

**Interfaces:** 构建脚本新增 `-Channel qa|production` 和 `-PackageInstaller` 参数。输入为已提交源码、锁定依赖、对应构建配置；输出 exe 与完整运行时 ZIP、用户级安装程序、版本/提交/哈希清单。所有产物回传 `/home/CrossLink/artifacts/0.3.0/`。

- [ ] 先核对已获准的本地 Windows 构建环境：Git、Visual Studio C++、Windows SDK、足够空间；记录 `flutter doctor -v`。当前缺少 C++ 工具链，用户已明确授权受控安装；不采购额外节点。
- [ ] 从阿里云提交打包源码，经 SSH/SCP 传入本地 `.build` 的受控工作目录；环境信息和构建日志回传服务器，产物清单记录源提交。
- [ ] 使用现有固定 Flutter 提交进行 analyze/test/release 构建，修复仅 Windows 编译或运行时才暴露的问题。
- [ ] 首先交付包含 `crosslink.exe`、DLL、data/assets 的完整 ZIP，在无 Flutter 开发环境的干净 Windows 中启动验证。
- [ ] 使用 Inno Setup 封装当前用户安装程序，创建开始菜单、卸载入口，升级保留配置；默认不索取管理员权限。设置依据：[PrivilegesRequired=lowest](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm)。
- [ ] 在 Windows 10/11 x64 验证安装、启动、托盘、通知、文件打开、升级和卸载；仅对实际通过的系统标记支持。Windows Authenticode 证书获取是正式广泛分发的独立事项，不把哈希校验称为可信发布者签名。

计划产物：`CrossLink-0.3.0-windows-x64.zip`、`CrossLink-0.3.0-windows-x64-setup.exe`。源码构建包继续作为开发材料，不能算作这两项的完成证据。

### B2：Android release 包与可持续签名

**Files:** 修改 `client/android/app/build.gradle.kts`、`deploy/build-android.py`、`deploy/build-clients.sh`、`.gitignore`、`.dockerignore`；新增 `docs/ANDROID_RELEASE.md`。

**Interfaces:** 构建脚本区分 qa/production 与 debug/release；生产配置仍内置平台地址。签名材料存 `/home/CrossLink/.tools/signing/`，权限收紧、独立备份，不进源码/构建套件/日志；密码通过环境或受保护文件注入。

- [ ] 固定包名、版本名和递增 versionCode；生产签名第一次生成后长期保留，记录公开签名指纹。
- [ ] release 配置必须使用发布签名，构建时缺少配置即失败，禁止悄悄退回 debug 签名。
- [ ] 生成 ARM64 release APK；仅按测试设备需要增加其他 ABI，不能宣称当前 ARM64 包支持所有设备。
- [ ] 验证 APK 签名、非 debuggable、公开 CA、原生服务、分享 Intent、版本和 SHA256；日志记录验证结果，不打印私钥或口令。
- [ ] 用同一发布密钥构建两个递增版本，验证覆盖升级后登录/设备标识仍可恢复。现有 debug 包与新 release 签名不匹配时，提供明确迁移步骤，清除旧 App 前先处理用户本地文件。签名及更新身份依据：[Android 应用签名文档](https://developer.android.com/studio/publish/app-signing)。
- [ ] APK/JVM 构建继续使用现有内存限制与单 Gradle worker；不要同时运行多个重构建。

计划产物：`CrossLink-0.3.0-android-arm64-release.apk`。QA 包使用独立 `applicationIdSuffix .qa`，便于与正式安装共存且隔离凭据；其内部平台配置不能混入正式产物。

## 8. M4：公网未开放时完成实机联调

### A1：两端真实系统行为及互传矩阵

**Files:** 新增 `docs/NATIVE_ACCEPTANCE.md`、`docs/acceptance/0.3.0.md`；扩展 `deploy/smoke_live.py` 和原生/客户端回归测试。截图、非敏感诊断和测量结果保存在 `/home/CrossLink/artifacts/acceptance/`，不把测试账号口令写进报告。

**Interfaces:** QA 构建内置 `https://127.0.0.1:8443`；Windows 测试节点通过 SSH 本地转发到平台；Android 经测试节点连接的 USB/ADB reverse 使用同一隧道。现有证书 SAN 包含 127.0.0.1；测试仍开启证书验证。普通用户的生产安装包始终使用内置平台地址。

在具有既有 SSH 凭据的受控 Windows 测试节点执行：

```powershell
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8443:127.0.0.1:8443 root@47.116.203.177
```

在另一受控终端中，对已经通过 USB 授权的测试手机执行：

```powershell
adb devices
adb reverse tcp:8443 tcp:8443
```

这是开发验收通道，不是 App 的日常使用步骤；不需要提前开放 ECS 安全组。无可操作手机/Windows 桌面时，自动化验证继续进行，实机项保持待验收，不伪造通过。

- [ ] 记录 Windows 版本、Android 型号/API、App 版本/提交、网络条件、前后台/省电设置。
- [ ] 每个场景至少在两个传输方向执行，结果记录通过/失败、证据、缺陷和复测提交。
- [ ] 消息延迟以服务端接受成功至对方实际显示计时，在双方在线、网络正常时目标 2 秒以内；每个方向至少测量 30 条消息，记录 p50/p95/最大值与是否漏收，不用单次最快结果。
- [ ] 接收端离线发送文字与文件，重新上线后自动补收，内容无缺失、界面与通知不重复；回执失败和重放仍能收敛。
- [ ] 用户退出/撤销后旧凭据不能发送/下载/接收；切换账号不展示上一账号历史。

| 编号 | 场景 | 必须看到的结果 |
|---|---|---|
| A01 | 同账号登录 | 两端自动互见，无地址/配对输入 |
| A02 | 不同账号登录 | 设备、消息、文件相互隔离 |
| A03 | 双向文字/链接/通知 | 内容一致，在线时及时到达，系统通知可打开 App |
| A04 | 双向复制粘贴同步 | 开启同步后，在一端复制文字/链接，另一端系统剪贴板更新并可直接粘贴；单独记录 Android 焦点/后台条件，手动操作只算补充验证 |
| A05 | PDF/图片/ZIP 双向传输 | 保存成功、哈希一致、可用系统应用打开 |
| A06 | 多文件/大文件/取消 | 逐项状态准确，取消不虚报完成，无长期临时残留 |
| A07 | 接收方离线后恢复 | 自动补收文字和文件通知，各设备独立回执 |
| A08 | Wi-Fi/移动网络切换 | 自动重连、刷新 Token，失败期间显示真实状态 |
| A09 | Windows 关闭窗口/重启 | 托盘继续接收；启用自启动后重启可恢复 |
| A10 | Android 返回桌面/锁屏/省电 | 分别记录实际接收行为，受限后重进能补收 |
| A11 | 拒绝通知权限 | 前台消息与文件仍可用，界面说明限制 |
| A12 | 改名/退出/撤销 | 名称持久，撤销即时生效，旧会话不能复活 |
| A13 | 升级安装 | 签名与版本正确，身份/账号状态按设计保留 |
| A14 | 第三台同账号设备广播 | 每台只收一份，单台未读不影响其他台回执 |
| A15 | 剪贴板重复/乱序/回传 | 一个远端写入不产生反向重发；重复不覆盖，旧版本不倒退 |
| A16 | 剪贴板离线与并发复制 | 不用旧补发内容覆盖新的本机复制；重连按平台版本收敛 |

出口：原设计第 50 节五个 MVP 场景全由真实 Windows 与 Android 完成。JVM MockWebServer、浏览器预览和 Linux 模拟客户端均属于补充证据。

## 9. M5：平台开放与可恢复部署

### O1：开放前准备

**Files:** 修改 `deploy/nginx-platform-public.conf.example`、`deploy/crosslink-api.service`、`server/app/files.py`、`server/app/config.py`；新增 `deploy/backup-platform.py`、`deploy/verify-backup.py`、`docs/OPERATIONS.md`、`server/tests/test_storage_guard.py`。

- [ ] 固定一个对外 HTTPS/WSS 入口，沿用 8443；API 8765 和数据库 55432 保持 loopback。保留现有平台 IP 与内置公开 CA，不以用户提供域名作为推进条件。
- [ ] 整理可审核的网关配置、证书有效期、客户端构建配置一致性与回滚步骤；先在 loopback 环境验证错误证书被拒绝，正确证书可建立 HTTPS/WSS。
- [ ] 增加上传前可用空间检查与并发预留，默认保留至少 2 GiB 系统余量；达阈值返回明确错误且清理本次部分文件。测试低空间与同时上传不会绕过预留；阈值可配置，不压测占满真实根盘。
- [ ] 为数据库与未过期文件做一致性备份；签名/平台私钥单独保护。备份落于 `/home/CrossLink/backups`，归档前检查剩余空间；同盘备份不能替代异机灾备，异机目标没有提供时如实记录。
- [ ] 在 `/home/CrossLink/.tools/restore-check/` 的隔离环境验证恢复，禁止覆盖正在运行的数据库；保存恢复耗时、账号/文件数量及文件哈希结果。
- [ ] 固定源提交、依赖和迁移版本；准备上一版工件/配置。若涉及不可逆数据迁移，部署计划明确恢复方式，不能只用 git reset 充当数据库回滚。
- [ ] 运行健康检查、文件生命周期清理和证书续期检查；日志只记录错误类别/请求 ID/耗时，不包含令牌、剪贴板和文件内容。

出口：开放配置、回滚和恢复证据齐全，既有其他服务不受影响。

### O2：用户授权后启用公网入口

本步骤的授权边界来自用户“如果要开放安全组的端口后面再说”以及 AGENTS.md 的公网约束。此前“自动完成开发”不等于授权开放安全组。

- [ ] 向用户呈现 O1 已准备好的具体入口：仅平台 TCP 8443；说明 API/数据库仍不直接暴露、失败如何撤回。
- [ ] 获得明确授权后，再改变 CrossLink 网关监听并开放对应安全组/必要防火墙规则；仅改本项目相关项。
- [ ] 在 Wi-Fi 与手机移动网络间，用 production 安装包、同账号直接登录互传，用户不设置任何服务器地址或证书。
- [ ] 验证外网 HTTPS/WSS、文件上传/下载、Token 刷新、离线补收、设备撤销；API/数据库端口仍不对外监听。
- [ ] 若外网验收失败且无法当场恢复，退回前一网关配置与对应新建规则，保留用户数据和前一可用产物。

出口：生产包脱离调试隧道后，两端只登录同账号即可互传。

## 10. M6：持续使用验收与版本交付

### R1：72 小时记录与交付清单

**Files:** 更新 `README.md`、`CHANGELOG.md`、`docs/VERIFICATION.md`、`docs/acceptance/0.3.0.md`；产物清单写入 `artifacts/0.3.0/manifest.json` 与 `SHA256SUMS`。

- [ ] 连续 72 小时保留两端测试使用记录，每天执行双向文字/文件、前后台切换和一次断网恢复；记录崩溃、重连次数、漏收/重复、耗电观察与服务端空间趋势。
- [ ] 观察到问题时记录复现条件，修复影响核心链路后重新计算该范围的观察期，不把人工重启掩盖成稳定运行。
- [ ] 至少完成一次生产签名版本升级演练和一次部署回滚/备份恢复演练；恢复演练使用隔离数据，不破坏用户正在使用的设备。
- [ ] 交付 Windows ZIP 与安装程序、Android release APK、版本/提交/ABI/签名指纹/哈希清单、简短安装说明、已知限制。
- [ ] 验证报告逐项标记“自动化通过/真实设备通过/尚未验证”；不得因测试数量增加而改变未验证项目的状态。

完成定义：用户拿到的是可运行 App；在验收过的 Windows/Android 环境下，仅同账号登录即可发现设备和互传；开启剪贴板同步后，在已声明的平台能力范围内完成一端复制、另一端实际粘贴，不依赖浏览器预览、开发工具或 SSH。

## 11. 后续增强：MVP 稳定后进入

| 顺序 | 能力 | 开始条件与验收方向 |
|---|---|---|
| E1 | 文件续传、分块、容量配额，逐步到 2 GB | 先验证原生流式下载和空间保护；断网/重启后续传，整文件哈希一致 |
| E2 | 默认下载目录、通知分类、1/7/30 天保留期等偏好 | 基础收发稳定；偏好按用户/设备正确持久化，过期状态清楚 |
| E3 | 更多剪贴板格式与 Android 深度系统集成 | 文字/链接自动同步已前移到 C4；图片及文件剪贴板格式按用户范围补充，跨 App 后台无感能力需有可行的系统级集成与实测证据 |
| E4 | 图片/截图共享与更强后台通知 | 以实机后台限制为依据评估系统推送；推送只负责唤醒/提示，平台继续作为中转 |
| E5 | 用户自助恢复账号、版本检查与升级分发 | 正式签名和发布流程稳定，升级失败可恢复，不让客户端使用者选择服务器 |
| E6 | OSS、Redis 多 worker、P2P/E2EE | 分别以容量、连接规模、传输效率或隐私需求触发；不影响同账号即用的界面原则 |

原设计里的完整托盘动作、剪贴板监听和自动写入、文件类型/进度/打开与保存、同账号多设备，分别由 C2/C4/C3/A1 覆盖；2 GB、可选保留期、自动更新、E2EE/P2P 等差距在本节显式保留，不归入当前“已实现”。文字/链接复制粘贴同步是首版验收门槛。

## 12. 执行顺序、依赖与记录

推荐顺序：S1/S2 → S3 → S4/S5 → C4 复制粘贴同步 → C1/C2/C3 → B1/B2 → A1 → O1 → 获授权后的 O2 → R1。Android 剪贴板能力验证与 Windows 节点核对尽早开始。

Windows 环境核对与签名方案准备可提前；产品接口变化先稳定再生成候选包；每次候选包从同一提交构建。缺失 Windows 节点、真实测试设备或公网授权时，仅相关任务停留待具备，其余已授权工作继续。不得把环境等待写成开发完成。

每项任务保存：变更文件、源提交、具体测试命令与退出码、实际产物、未通过事项。业务变更后完成对应测试与一次必要回归即可，不反复执行无变化的全量重构建。

第一执行批次固定为 S1、S2、S3：先让“连接是否正常、设备是谁、消息是否收到”三个最直接的用户判断可靠，再收敛文件清理和分页边界。
