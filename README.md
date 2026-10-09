# CrossLink

Windows与Android的同账号文件、文字、链接和剪贴板中转同步App。两端只输入用户名、密码登录，平台地址已内置，登录后自动发现同账号设备，无须配对或配置服务器。注册额外填写邮箱。

## 0.3.0 安装包

| 平台 | 正式产物 |
|---|---|
| Windows x64 | `artifacts/0.3.0/production/CrossLink-0.3.0-windows-x64-setup.exe`，当前用户双击安装 |
| Windows便携包 | 同目录`CrossLink-0.3.0-windows-x64.zip`，完整解压后运行`crosslink.exe` |
| Android ARM64 | 同目录`CrossLink-0.3.0-android-arm64-release.apk`，专用发布签名，Android7.0及以上 |

版本/源码/签名/哈希见`artifacts/0.3.0/manifest.json`和`SHA256SUMS`。QA包在相邻`qa`目录，应用名称、身份和内置验收通道与正式版分开。旧0.2调试签名不能直接升级到正式签名，先保留已下载文件。完整安装说明、验证记录和待验收项见[0.3.0交付记录](docs/acceptance/0.3.0.md)。

**公网入口仍未开放。** 目前正式包可安装，外部网络登录/互传要在后续获授权开启平台入口后使用；手机实测由用户明确延后。当前用户Windows安装、启动、单实例、重复安装和卸载已检查；Android真实手机、两端实际粘贴/文件打开、后台恢复和72小时使用尚未验收。

## 使用流程与复制粘贴

登录同一账号后，设备自动列出，可向全部其他设备或选定设备发送文字、链接和文件。没有另一设备时界面会提示在另一端登录同账号。送达、已读、文件已保存是独立状态；离线后恢复会补收，重试保留操作身份。

在设置中开启“复制粘贴同步”，文字/链接将经平台同步到目标系统剪贴板。Windows可驻留托盘同步；Android从其他App复制后需打开CrossLink读取，远端写入也在CrossLink获得焦点后进行，再切到目标App粘贴。这与[Android10起的剪贴板读取限制](https://developer.android.com/about/versions/10/privacy/changes#clipboard-data)一致。图片/文件剪贴板格式尚未实现。

暂停同步保留登录状态，恢复后补收。Windows自启动需自行开启，安装默认关闭。Android后台接收服务已实现，强行停止、锁屏/省电和权限变化的实际表现等待手机验收。当前普通文件上限100MiB、保存7天；原生下载流式验证SHA256，按系统选择位置保存，支持取消与逐文件结果，尚无分块续传。

## 开发与运维

权威源码、部署、备份和归档在阿里云`/home/CrossLink`，通过SSH操控。用户已追加授权本机Windows构建；工具、源码导出、缓存和本机交付位于`D:/aliyun/CrossLink/.build`，最终包已回传服务器。SDK和依赖锁定；Windows须使用独立`main_windows.dart`入口，Android/web使用`main.dart`。

- [Windows构建](docs/WINDOWS_BUILD.md)、[Android发布与签名](docs/ANDROID_RELEASE.md)
- [平台运维、备份恢复与回退](docs/OPERATIONS.md)、[原生验收](docs/NATIVE_ACCEPTANCE.md)
- [当前验证与历史记录](docs/VERIFICATION.md)、[后续交付路线](docs/superpowers/plans/2026-10-09-crosslink-delivery-roadmap.md)

API与数据库只绑定loopback，单API worker；公开监听样例已准备，须另行取得用户授权。储存守护保留至少2GiB系统余量；数据库、文件与私密材料一致备份及隔离恢复已验证，同盘备份仍需要以后补充异机灾备。

后续增强包括分块/续传与2GB文件、更多剪贴板格式、保留期偏好、账号恢复/自动升级、推送、OSS、Redis、P2P/E2EE。它们不列入当前已完成的安装包验收。用户原始设计保留在`docs/DEVELOPMENT_DESIGN.md`。
