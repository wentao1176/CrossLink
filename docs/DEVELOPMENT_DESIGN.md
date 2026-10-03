# 跨端文件与剪贴板同步软件开发设计文档

> 项目代号：**CrossLink**（可后续更名）  
> 第一阶段目标平台：**Windows PC + Android 手机 + 阿里云服务器**  
> 后续扩展：macOS / Linux / iOS / Web 管理端  
> 文档定位：产品需求 + 系统架构 + 接口设计 + 数据库设计 + 部署方案 + 开发路线，可直接作为 Codex / Claude Code / Cursor 的项目开发依据。

---

## 1. 项目背景

希望开发一套属于自己的跨端同步软件，使电脑与手机在登录同一账号后形成一个“个人设备网络”。

核心目标不是单纯的网盘，而是实现：

1. 手机与电脑之间快速互传文件；
2. 多设备共享剪贴板文字；
3. 手机触发操作后，电脑能够实时收到并弹出消息；
4. 电脑也可以主动向手机发送文字、文件、链接和通知；
5. 所有设备由自己的阿里云服务器统一管理；
6. 同一账号可以登录多台设备，并显示设备在线状态；
7. 后续可扩展成“个人跨设备协作中心”。

项目最终体验应接近：

- Apple Universal Clipboard；
- KDE Connect；
- LocalSend；
- Pushbullet；
- 微信“文件传输助手”；
- AirDrop 的部分体验；

但数据、账号体系、服务器和控制逻辑全部掌握在自己手中。

---

# 2. 产品定位

## 2.1 核心定位

CrossLink 是一个“以账号为中心的跨设备通信与同步工具”。

每台客户端安装后均作为一个独立 Device：

```text
User
├── Windows-PC
├── Android-Phone
├── Laptop
└── Future-iPad
```

所有设备登录同一个账号后：

- 自动发现账号下其他设备；
- 展示在线/离线状态；
- 可以给指定设备发送内容；
- 可以广播给账号下全部设备；
- 可以通过云端服务器进行消息中转；
- 文件可通过云端暂存并由其他设备下载；
- 文本消息可以实时同步；
- PC 客户端常驻系统托盘并接收实时事件。

---

# 3. 第一阶段开发范围

为了避免项目一开始过于复杂，建议按阶段实现。

## 3.1 MVP 必须实现

### 账号系统

- 用户注册；
- 用户登录；
- Token 自动刷新；
- 多设备同时登录；
- 查看当前登录设备；
- 给设备自定义名称；
- 退出指定设备；
- 当前设备注销。

### 设备系统

每台设备首次登录时生成：

```text
device_id
device_name
device_type
platform
os_version
app_version
```

设备状态：

```text
online
offline
last_seen
```

### 文件互传

支持：

```text
手机 → 电脑
电脑 → 手机
电脑 → 电脑
手机 → 手机
```

基础能力：

- 单文件发送；
- 多文件发送；
- 文件发送进度；
- 文件接收进度；
- 文件大小显示；
- 文件类型显示；
- 文件历史记录；
- 下载完成后打开；
- Windows 端打开文件所在目录；
- Android 保存至指定目录。

### 文本/剪贴板共享

支持：

- 复制文字后手动发送；
- 手机向电脑发送文字；
- 电脑向手机发送文字；
- 收到后“一键复制”；
- 可选自动写入剪贴板；
- 显示最近剪贴板历史。

### 实时消息

手机端执行：

```text
发送文字
发送文件
发送链接
发送通知
```

电脑端立即：

```text
收到 WebSocket 事件
        ↓
系统托盘客户端处理
        ↓
Windows Toast 弹窗
```

例如：

```text
来自 Mate 70 Pro

收到新的剪贴板内容：
https://example.com
```

点击通知：

```text
打开 CrossLink
```

或者：

```text
直接复制内容
```

---

# 4. 后续高级功能

MVP 完成后可逐步增加：

## 4.1 自动剪贴板同步

电脑：

```text
Ctrl + C
   ↓
监听系统剪贴板
   ↓
发现新内容
   ↓
上传服务器
   ↓
其他设备收到
```

手机端：

```text
复制文本
   ↓
CrossLink 获取内容
   ↓
同步到 PC
```

注意：

Android 新版本对后台读取剪贴板有限制，因此手机端自动读取能力需要根据系统权限单独设计。

建议默认策略：

```text
手动同步 = 默认
自动同步 = 用户主动开启
```

避免密码、验证码、密钥等敏感信息被无意上传。

---

## 4.2 链接快速打开

例如手机浏览网页：

```text
发送到 Windows-PC
```

电脑立即弹窗：

```text
来自手机的链接
```

点击：

```text
默认浏览器打开
```

---

## 4.3 远程通知

手机发送：

```text
type = notification
title = "提醒"
content = "记得提交作业"
```

Windows 直接弹系统通知。

未来可扩展：

```text
PC → 手机通知
服务器 → 所有设备通知
定时通知
```

---

## 4.4 图片快速同步

手机截图：

```text
分享
→ CrossLink
→ Windows-PC
```

电脑收到后：

```text
图片预览
复制图片
保存图片
打开图片
```

---

## 4.5 截图共享

Windows：

```text
Win + Shift + S
```

截图进入剪贴板后：

```text
CrossLink 检测图片
→ 上传
→ 手机收到
```

---

## 4.6 局域网高速传输

第一版文件：

```text
客户端 A
   ↓
阿里云
   ↓
客户端 B
```

后续可优化：

```text
客户端 A
   ↓
发现双方处于同一局域网
   ↓
局域网直传
   ↓
客户端 B
```

云端只负责：

```text
身份认证
设备发现
连接协商
```

这样大文件不会占服务器带宽。

---

# 5. 推荐技术架构

## 5.1 总体架构

```text
┌─────────────────────┐
│ Android App         │
│ Flutter             │
└──────────┬──────────┘
           │
           │ HTTPS / WebSocket
           │
┌──────────▼──────────┐
│                     │
│  Alibaba Cloud ECS  │
│                     │
│  Nginx              │
│       ↓             │
│  FastAPI Backend    │
│       │             │
│  ┌────┴─────┐       │
│  │          │       │
│ PostgreSQL Redis    │
│                     │
└──────────┬──────────┘
           │
           │ HTTPS / WebSocket
           │
┌──────────▼──────────┐
│ Windows Client      │
│ Flutter Desktop     │
│ System Tray         │
└─────────────────────┘
```

文件存储可以采用两种方案。

### 方案 A：服务器本地磁盘

适合：

- 初期；
- 自用；
- 文件量不大；
- 希望开发简单。

目录：

```text
/data/crosslink/files/
```

优点：

- 开发简单；
- 不需要额外服务。

缺点：

- ECS 硬盘空间有限；
- 大文件耗带宽；
- 后期迁移麻烦。

### 方案 B：阿里云 OSS

推荐正式版本使用。

架构：

```text
客户端
  │
  │ 请求上传
  ▼
CrossLink API
  │
  │ 获取临时上传凭证
  ▼
客户端 ───────→ OSS
```

下载同理。

优点：

- 文件不经过 Python 服务；
- 后端压力非常低；
- 支持大文件；
- 支持断点续传；
- 可配置生命周期自动删除；
- 更适合长期运行。

推荐：

```text
MVP：ECS 本地文件
V2：切换 OSS
```

---

# 6. 技术栈建议

## 6.1 客户端

推荐：

```text
Flutter
```

原因：

- Windows + Android 一套主要代码；
- UI 开发速度快；
- 支持桌面端；
- 支持系统托盘插件；
- 支持 WebSocket；
- 支持文件选择；
- 支持剪贴板；
- 后续可扩展 macOS / iOS。

建议模块：

```text
Riverpod / Bloc
Dio
WebSocket
GoRouter
SharedPreferences
SecureStorage
SQLite / Drift
```

如果项目以快速开发为核心，推荐：

```text
Flutter + Riverpod
```

---

# 7. 服务端技术栈

推荐：

```text
Python
FastAPI
PostgreSQL
Redis
Nginx
Docker Compose
```

架构：

```text
Nginx
 │
 ├── /api/*
 │       ↓
 │    FastAPI
 │
 └── /ws/*
         ↓
      FastAPI WebSocket
```

---

# 8. 为什么需要 Redis

如果未来后端只有一个 FastAPI 进程：

```text
WebSocket
```

可以直接存在内存。

但是如果后端运行：

```text
worker-1
worker-2
worker-3
```

设备 A 连接：

```text
worker-1
```

设备 B 发送消息进入：

```text
worker-2
```

worker-2 无法直接拿到 worker-1 的 WebSocket。

因此使用：

```text
Redis Pub/Sub
```

流程：

```text
Device A
   ↓
FastAPI Worker 1
   ↓
Redis Pub/Sub
   ↓
FastAPI Worker 2
   ↓
Device B
```

所以架构最好一开始就预留 Redis。

MVP 可先：

```text
单 worker + 内存 WebSocket 管理
```

后续再切 Redis。

---

# 9. 核心业务模型

## 9.1 User

```text
User
├── id
├── username
├── email
├── password_hash
├── created_at
└── status
```

---

## 9.2 Device

```text
Device
├── id
├── user_id
├── device_uuid
├── device_name
├── device_type
├── platform
├── os_version
├── app_version
├── last_seen
├── created_at
└── revoked
```

device_type：

```text
desktop
phone
tablet
web
```

platform：

```text
windows
android
macos
linux
ios
```

---

# 10. 数据库设计

## 10.1 users

```sql
users
----------------------------------
id                UUID PRIMARY KEY
username          VARCHAR
email             VARCHAR UNIQUE
password_hash     VARCHAR
created_at        TIMESTAMP
updated_at        TIMESTAMP
status            SMALLINT
```

---

## 10.2 devices

```sql
devices
----------------------------------
id                UUID PRIMARY KEY
user_id           UUID
device_uuid       VARCHAR UNIQUE
device_name       VARCHAR
device_type       VARCHAR
platform          VARCHAR
os_version        VARCHAR
app_version       VARCHAR
last_seen         TIMESTAMP
created_at        TIMESTAMP
revoked           BOOLEAN
```

---

## 10.3 sessions

记录登录会话。

```sql
sessions
----------------------------------
id                UUID
user_id           UUID
device_id         UUID
refresh_token_hash VARCHAR
created_at        TIMESTAMP
expires_at        TIMESTAMP
revoked           BOOLEAN
```

---

## 10.4 messages

统一保存消息。

```sql
messages
----------------------------------
id                UUID
user_id           UUID
sender_device_id  UUID
target_device_id  UUID NULL
message_type      VARCHAR
payload           JSONB
status            VARCHAR
created_at        TIMESTAMP
delivered_at      TIMESTAMP NULL
read_at           TIMESTAMP NULL
```

message_type：

```text
text
clipboard
file
image
url
notification
command
system
```

---

## 10.5 files

```sql
files
----------------------------------
id                UUID
user_id           UUID
sender_device_id  UUID
original_name     VARCHAR
storage_name      VARCHAR
storage_path      VARCHAR
mime_type         VARCHAR
size              BIGINT
sha256            VARCHAR
created_at        TIMESTAMP
expires_at        TIMESTAMP
```

---

## 10.6 transfers

```sql
transfers
----------------------------------
id                UUID
file_id           UUID
sender_device_id  UUID
target_device_id  UUID
status            VARCHAR
progress          INTEGER
created_at        TIMESTAMP
completed_at      TIMESTAMP NULL
```

status：

```text
pending
uploading
waiting
downloading
completed
failed
cancelled
expired
```

---

## 10.7 clipboard_history

```sql
clipboard_history
----------------------------------
id                UUID
user_id           UUID
device_id         UUID
content_type      VARCHAR
content           TEXT
content_hash      VARCHAR
created_at        TIMESTAMP
expires_at        TIMESTAMP
```

---

# 11. REST API 设计

统一前缀：

```text
/api/v1
```

---

## 11.1 注册

```http
POST /api/v1/auth/register
```

Request：

```json
{
  "username": "wentao",
  "email": "xxx@example.com",
  "password": "******"
}
```

---

## 11.2 登录

```http
POST /api/v1/auth/login
```

Request：

```json
{
  "account": "wentao",
  "password": "******",
  "device": {
    "device_uuid": "...",
    "device_name": "Wentao-PC",
    "platform": "windows"
  }
}
```

Response：

```json
{
  "access_token": "...",
  "refresh_token": "...",
  "expires_in": 1800,
  "device_id": "..."
}
```

---

## 11.3 Refresh Token

```http
POST /api/v1/auth/refresh
```

---

## 11.4 当前用户

```http
GET /api/v1/users/me
```

---

## 11.5 查询设备

```http
GET /api/v1/devices
```

Response：

```json
[
  {
    "id": "...",
    "name": "Wentao-PC",
    "platform": "windows",
    "online": true,
    "last_seen": "..."
  },
  {
    "id": "...",
    "name": "Mate-Phone",
    "platform": "android",
    "online": true
  }
]
```

---

## 11.6 修改设备名

```http
PATCH /api/v1/devices/{device_id}
```

---

## 11.7 注销设备

```http
DELETE /api/v1/devices/{device_id}
```

---

# 12. 消息发送 API

```http
POST /api/v1/messages
```

示例：

```json
{
  "target_device_id": "...",
  "type": "clipboard",
  "payload": {
    "content": "hello world"
  }
}
```

服务器：

```text
1. 验证目标设备是否属于当前用户
2. 保存消息
3. 检查目标设备 WebSocket 是否在线
4. 在线 → 实时推送
5. 离线 → 标记 pending
6. 目标设备上线后拉取 pending 消息
```

---

# 13. WebSocket 设计

连接：

```text
wss://api.example.com/ws
```

Authentication：

```text
Authorization Token
```

或：

```text
wss://api.example.com/ws?token=...
```

更推荐连接后发送认证消息。

---

## 13.1 客户端认证

```json
{
  "type": "auth",
  "token": "ACCESS_TOKEN"
}
```

服务器响应：

```json
{
  "type": "auth_ok",
  "device_id": "..."
}
```

---

# 14. WebSocket 事件协议

统一结构：

```json
{
  "event": "message.created",
  "event_id": "uuid",
  "timestamp": 1234567890,
  "data": {}
}
```

---

## 14.1 设备上线

```json
{
  "event": "device.online",
  "data": {
    "device_id": "...",
    "device_name": "Mate Phone"
  }
}
```

---

## 14.2 设备离线

```json
{
  "event": "device.offline",
  "data": {
    "device_id": "..."
  }
}
```

---

## 14.3 剪贴板同步

```json
{
  "event": "clipboard.updated",
  "data": {
    "message_id": "...",
    "sender_device_id": "...",
    "content_type": "text",
    "content": "hello",
    "content_hash": "..."
  }
}
```

---

## 14.4 新文件

```json
{
  "event": "file.created",
  "data": {
    "file_id": "...",
    "name": "report.pdf",
    "size": 1048576,
    "mime_type": "application/pdf"
  }
}
```

---

## 14.5 通知

```json
{
  "event": "notification.created",
  "data": {
    "title": "来自手机",
    "content": "任务已经完成"
  }
}
```

---

# 15. 心跳机制

客户端每：

```text
30 秒
```

发送：

```json
{
  "type": "ping"
}
```

服务器：

```json
{
  "type": "pong"
}
```

如果：

```text
90 秒
```

未收到心跳：

```text
device → offline
```

---

# 16. 消息可靠性设计

不能只依赖 WebSocket。

正确架构：

```text
发送消息
   ↓
数据库保存
   ↓
尝试 WebSocket 推送
```

目标设备收到后：

```json
{
  "type": "ack",
  "message_id": "..."
}
```

服务器：

```text
status = delivered
```

用户查看后：

```text
status = read
```

状态变化：

```text
pending
   ↓
delivered
   ↓
read
```

这样即使设备断网也不会丢消息。

---

# 17. 剪贴板同步设计

## 17.1 防止无限循环

典型问题：

```text
PC 复制 A
↓
发给 Phone
↓
Phone 写入剪贴板 A
↓
Phone 检测剪贴板变化
↓
再次发给 PC
↓
循环
```

因此必须保存：

```text
content_hash
origin_device_id
event_id
```

客户端维护：

```text
last_remote_clipboard_hash
```

如果检测到：

```text
当前 clipboard hash == last_remote_clipboard_hash
```

则：

```text
不再次发送
```

---

# 18. 剪贴板安全策略

自动同步剪贴板有隐私风险。

用户可能复制：

```text
密码
验证码
API Key
Token
身份证号码
银行卡
```

建议设计三种模式：

### 模式 1：手动同步

最安全。

```text
复制
↓
点击 CrossLink
↓
发送剪贴板
```

### 模式 2：自动文本同步

仅同步：

```text
text/plain
```

限制：

```text
<= 100 KB
```

### 模式 3：完全自动

支持：

```text
文本
图片
```

必须主动开启。

---

# 19. 文件上传设计

小文件：

```text
POST /files/upload
```

可以直接 Multipart 上传。

但正式版本推荐：

```text
初始化上传
↓
分片上传
↓
完成上传
```

---

## 19.1 初始化

```http
POST /api/v1/files/init
```

Request：

```json
{
  "name": "video.mp4",
  "size": 104857600,
  "sha256": "..."
}
```

Response：

```json
{
  "upload_id": "...",
  "chunk_size": 5242880
}
```

---

## 19.2 分片

```text
5 MB / chunk
```

API：

```http
PUT /api/v1/files/{upload_id}/parts/{part_no}
```

---

## 19.3 完成

```http
POST /api/v1/files/{upload_id}/complete
```

服务器校验：

```text
file size
SHA256
parts
```

---

# 20. 文件秒传

客户端上传前计算：

```text
SHA256
```

服务器查询：

```text
是否已有同 hash 文件
```

如果存在：

```text
不需要重复上传
```

直接创建新的 transfer。

---

# 21. 断点续传

客户端保存：

```text
upload_id
uploaded_parts
```

断线后：

```text
GET /files/{upload_id}/parts
```

获取：

```text
已经完成的 chunk
```

仅继续剩余部分。

---

# 22. Windows 客户端设计

Windows 客户端应支持：

```text
系统启动
↓
CrossLink 自动启动
↓
最小化到系统托盘
↓
保持 WebSocket 连接
```

托盘菜单：

```text
CrossLink
----------------
打开主界面
发送文件
发送剪贴板
设备列表
暂停同步
设置
退出
```

---

# 23. Windows Toast 通知

例如手机发送：

```json
{
  "event": "clipboard.updated"
}
```

PC：

```text
CrossLink

Mate Phone 发送了一段文字

https://...
```

按钮：

```text
复制
打开
忽略
```

文件：

```text
Mate Phone 向你发送 report.pdf

[下载] [拒绝]
```

---

# 24. Android 客户端设计

首页：

```text
CrossLink
────────────────

我的设备

🟢 Wentao-PC
Windows · 在线

🟢 Mate Phone
当前设备
```

快捷操作：

```text
发送文件
发送文字
发送剪贴板
发送链接
```

---

# 25. Android 分享菜单

必须支持 Android Share Intent。

例如用户在：

```text
相册
文件管理器
浏览器
微信保存文件
```

点击：

```text
分享
```

出现：

```text
CrossLink
```

然后：

```text
选择目标设备
↓
发送
```

这是整个软件非常重要的体验。

---

# 26. Android 后台连接问题

Android 为节省电量会限制后台 App。

因此不能假设：

```text
WebSocket 永远在线
```

第一阶段可以采用：

```text
前台：
WebSocket 实时连接

后台：
周期性重连 / 系统允许时保持连接
```

若要实现稳定的后台手机通知，可以逐步加入：

```text
华为 Push Kit
FCM
厂商推送
```

对于“手机操作 → PC 弹通知”，由于 Windows 客户端可以长期在线，因此实现难度较低。

对于“PC 操作 → 手机即使在后台也秒级弹通知”，则需要系统推送能力。

---

# 27. UI 页面规划

## 27.1 登录页

```text
CrossLink

账号
密码

[登录]

没有账号？注册
```

---

## 27.2 首页

```text
CrossLink

我的设备

┌─────────────────────────┐
│ 🖥 Wentao-PC            │
│ Windows · 在线          │
└─────────────────────────┘

┌─────────────────────────┐
│ 📱 Mate Phone           │
│ Android · 当前设备      │
└─────────────────────────┘

最近传输
```

---

## 27.3 设备详情

```text
Wentao-PC

状态：在线
系统：Windows
IP：***
最后在线：刚刚

发送：
[文件]
[文字]
[链接]
[通知]
```

---

## 27.4 传输历史

```text
今天

report.pdf
Mate Phone → Wentao-PC
12.5 MB
已完成

hello.txt
Wentao-PC → Mate Phone
2 KB
已完成
```

---

## 27.5 剪贴板历史

```text
Clipboard

https://github.com/...
来自 Mate Phone

ssh root@...
来自 Wentao-PC

[复制]
```

---

## 27.6 设置

```text
账号
设备名称

同步设置
[ ] 自动同步文本
[ ] 自动同步图片
[ ] 收到文字自动复制

文件
默认下载目录

通知
[ ] 文件通知
[ ] 剪贴板通知
[ ] 设备上线通知

安全
设备管理
退出登录
```

---

# 28. 客户端目录结构建议

```text
client/
├── lib/
│   ├── app/
│   ├── core/
│   │   ├── api/
│   │   ├── websocket/
│   │   ├── storage/
│   │   ├── auth/
│   │   └── utils/
│   │
│   ├── features/
│   │   ├── auth/
│   │   ├── devices/
│   │   ├── transfers/
│   │   ├── clipboard/
│   │   ├── messages/
│   │   ├── notifications/
│   │   └── settings/
│   │
│   ├── models/
│   ├── router/
│   └── main.dart
│
├── android/
├── windows/
└── pubspec.yaml
```

---

# 29. 后端目录结构

```text
server/
├── app/
│   ├── main.py
│   │
│   ├── api/
│   │   ├── auth.py
│   │   ├── users.py
│   │   ├── devices.py
│   │   ├── messages.py
│   │   └── files.py
│   │
│   ├── core/
│   │   ├── config.py
│   │   ├── security.py
│   │   └── dependencies.py
│   │
│   ├── models/
│   ├── schemas/
│   ├── services/
│   │   ├── auth_service.py
│   │   ├── websocket_service.py
│   │   ├── file_service.py
│   │   └── message_service.py
│   │
│   ├── websocket/
│   │   ├── manager.py
│   │   └── events.py
│   │
│   └── db/
│
├── migrations/
├── tests/
├── Dockerfile
├── requirements.txt
└── docker-compose.yml
```

---

# 30. Docker Compose

建议服务器运行：

```text
nginx
api
postgres
redis
```

结构：

```yaml
services:

  api:
    build: ./server

  postgres:
    image: postgres

  redis:
    image: redis

  nginx:
    image: nginx
```

数据卷：

```text
/data/crosslink/postgres
/data/crosslink/files
```

---

# 31. 阿里云部署架构

推荐：

```text
Internet
    │
    ▼
Alibaba Cloud Security Group
    │
    ▼
Nginx :443
    │
    ├── /api
    │     ↓
    │   FastAPI
    │
    └── /ws
          ↓
        WebSocket
```

只开放：

```text
80
443
22（建议限制来源 IP）
```

不要直接开放：

```text
5432
6379
8000
```

PostgreSQL / Redis 只允许 Docker 内网访问。

---

# 32. 域名建议

可以使用：

```text
api.example.com
```

客户端访问：

```text
https://api.example.com
```

WebSocket：

```text
wss://api.example.com/ws
```

必须使用：

```text
HTTPS
WSS
```

不要使用明文：

```text
HTTP
WS
```

---

# 33. Nginx WebSocket 配置重点

需要：

```nginx
proxy_http_version 1.1;

proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

否则 WebSocket 会失败。

---

# 34. 登录安全

密码必须：

```text
Argon2id
```

或者：

```text
bcrypt
```

严禁数据库保存：

```text
明文密码
```

---

# 35. Token 设计

推荐：

```text
Access Token
30 分钟

Refresh Token
30 天
```

Access Token：

```text
JWT
```

Refresh Token：

```text
服务器保存 hash
```

支持：

```text
单设备退出
所有设备退出
```

---

# 36. 本地密钥保存

客户端禁止把 Token 明文放普通配置文件。

应使用：

Android：

```text
Android Keystore
```

Windows：

```text
Windows Credential Manager
```

Flutter 可以统一通过 Secure Storage 封装。

---

# 37. 文件安全

文件访问必须验证：

```text
当前 user 是否拥有 file
```

不能出现：

```text
/file/1
/file/2
/file/3
```

直接猜 ID 下载。

文件 ID 使用：

```text
UUID
```

下载接口检查：

```text
current_user.id == file.user_id
```

---

# 38. 文件生命周期

默认：

```text
文件保留 7 天
```

用户可以设置：

```text
1 天
7 天
30 天
永久
```

每天执行清理任务：

```text
删除过期文件
删除数据库记录
```

如果使用 OSS：

```text
使用 OSS Lifecycle
```

更简单。

---

# 39. 文件大小限制

第一版建议：

```text
默认最大 2 GB
```

服务器配置：

```text
MAX_FILE_SIZE
```

不要写死。

---

# 40. 设备身份

首次启动生成：

```text
device_uuid
```

保存在：

```text
Secure Storage
```

以后登录：

```text
同一 device_uuid
```

服务器认为是同一设备。

---

# 41. 在线状态

客户端：

```text
WebSocket connected
→ online
```

断开：

```text
offline
```

同时通过：

```text
last_seen
```

解决异常断电问题。

---

# 42. 消息目标

target_device_id：

```text
指定设备
```

如果：

```text
null
```

表示：

```text
发送给账号下所有其他设备
```

---

# 43. 本地数据库

客户端建议 SQLite。

保存：

```text
最近消息
最近传输
剪贴板历史
设备缓存
上传任务
下载任务
```

这样即使服务器短暂离线：

```text
客户端仍能显示历史记录
```

---

# 44. 网络断线恢复

WebSocket 断线后：

```text
1 秒
2 秒
4 秒
8 秒
16 秒
30 秒
```

指数退避重连。

最大：

```text
30 秒
```

重新连接成功：

```text
GET /messages/pending
```

补拉离线消息。

---

# 45. API 错误格式

统一：

```json
{
  "code": "DEVICE_NOT_FOUND",
  "message": "Target device not found",
  "details": {}
}
```

不要让客户端解析：

```text
HTTP 500 文本
```

---

# 46. 日志

服务端日志至少记录：

```text
request_id
user_id
device_id
endpoint
status
duration
```

注意：

不要记录：

```text
密码
完整 Token
完整剪贴板内容
```

---

# 47. 可观测性

后期可增加：

```text
Prometheus
Grafana
Sentry
```

监控：

```text
在线设备数量
WebSocket 数量
请求 QPS
错误率
文件流量
存储占用
```

---

# 48. 测试方案

## 单元测试

测试：

```text
登录
Token
消息权限
文件权限
hash
device ownership
```

---

## API 测试

覆盖：

```text
注册
登录
Refresh Token
设备
消息
文件
```

---

## WebSocket 测试

模拟：

```text
Device A
Device B
```

验证：

```text
A → Server → B
```

---

## 异常测试

必须测试：

```text
网络突然断开
服务器重启
客户端重启
文件上传中断
Token 过期
WebSocket 掉线
目标设备离线
重复消息
重复 ACK
```

---

# 49. MVP 开发顺序

强烈建议严格按照下面顺序开发。

## Phase 1：后端基础

完成：

```text
FastAPI
PostgreSQL
用户注册
登录
JWT
Device
```

验收：

```text
Windows 和 Android
可以登录同一账号
服务器显示两个设备
```

---

## Phase 2：WebSocket

实现：

```text
设备连接
在线状态
心跳
设备事件
```

验收：

```text
手机打开 App
PC 立即看到手机上线
```

---

## Phase 3：文字消息

实现：

```text
手机 → PC
PC → 手机
```

验收：

```text
手机输入：
hello

PC 立即弹出：
hello
```

这一步非常关键。

---

## Phase 4：剪贴板

实现：

```text
发送当前剪贴板
接收剪贴板
一键复制
```

先不要自动同步。

---

## Phase 5：文件传输

先支持：

```text
<= 100 MB
```

普通 Multipart。

实现完成后再做：

```text
分片
断点续传
秒传
```

---

## Phase 6：Windows 系统托盘

实现：

```text
后台常驻
托盘菜单
系统通知
```

---

## Phase 7：Android 分享

实现：

```text
系统分享
→ CrossLink
→ 指定 PC
```

---

## Phase 8：离线消息

实现：

```text
pending
delivered
read
```

---

## Phase 9：文件增强

加入：

```text
分片上传
SHA256
秒传
断点续传
```

---

## Phase 10：自动剪贴板

最后加入：

```text
PC 自动同步
Android 可实现范围内同步
```

---

# 50. MVP 验收标准

第一版完成时，至少满足：

### 场景 1

```text
PC 登录账号 A
手机登录账号 A
```

双方：

```text
均能看到对方设备
```

---

### 场景 2

手机：

```text
发送文字：
hello pc
```

PC：

```text
2 秒内收到
```

并弹系统通知。

---

### 场景 3

PC：

```text
选择 test.pdf
发送给手机
```

手机：

```text
收到通知
下载
成功打开
```

---

### 场景 4

手机：

```text
复制一段 URL
点击“发送剪贴板”
```

PC：

```text
收到
点击复制
```

---

### 场景 5

目标设备离线：

```text
发送消息
```

目标设备重新上线：

```text
自动收到离线消息
```

---

# 51. 推荐 Git 仓库结构

推荐 monorepo：

```text
crosslink/
├── client/
├── server/
├── deploy/
├── docs/
│   ├── API.md
│   ├── WEBSOCKET.md
│   └── ARCHITECTURE.md
├── docker-compose.yml
├── .env.example
└── README.md
```

---

# 52. 环境变量

后端：

```text
APP_ENV
DATABASE_URL
REDIS_URL

JWT_SECRET
ACCESS_TOKEN_EXPIRE
REFRESH_TOKEN_EXPIRE

FILE_STORAGE_PATH
MAX_FILE_SIZE

PUBLIC_BASE_URL
```

如果使用 OSS：

```text
OSS_ENDPOINT
OSS_BUCKET
OSS_ACCESS_KEY_ID
OSS_ACCESS_KEY_SECRET
```

注意：

生产环境密钥禁止提交 Git。

---

# 53. 开发环境

本地：

```text
Flutter Client
      │
      ▼
localhost:8000
      │
FastAPI
      │
Docker
├── PostgreSQL
└── Redis
```

推荐：

```text
docker compose up -d postgres redis
```

然后：

```text
uvicorn app.main:app --reload
```

---

# 54. 生产环境

建议目录：

```text
/opt/crosslink/
```

结构：

```text
/opt/crosslink
├── docker-compose.yml
├── .env
├── nginx/
├── data/
│   ├── postgres/
│   └── files/
└── logs/
```

---

# 55. CI/CD

GitHub：

```text
main branch
    ↓
GitHub Actions
    ↓
build
test
    ↓
SSH Alibaba ECS
    ↓
docker compose pull
docker compose up -d
```

后期可做到：

```text
git push
→ 自动部署服务器
```

---

# 56. 客户端更新机制

Windows：

```text
检查版本 API
```

例如：

```http
GET /api/v1/app/version?platform=windows
```

返回：

```json
{
  "latest": "1.2.0",
  "minimum": "1.0.0",
  "download_url": "...",
  "force": false
}
```

Android：

可以提供：

```text
APK 下载
```

后续再接应用商店。

---

# 57. 安全增强路线

第一阶段：

```text
HTTPS
JWT
权限验证
密码 hash
```

第二阶段：

```text
文件加密存储
```

第三阶段：

```text
端到端加密 E2EE
```

---

# 58. 端到端加密设计方向

如果未来不希望服务器能看到剪贴板和文件内容：

每个设备生成：

```text
Ed25519 identity key
X25519 encryption key
```

账号设备之间交换公钥。

发送：

```text
plaintext
   ↓
随机 AES-256 key
   ↓
AES-GCM 加密
   ↓
使用目标设备 public key 加密 AES key
```

服务器只保存：

```text
ciphertext
```

这部分实现复杂，建议 MVP 不做。

---

# 59. 未来 P2P 传输

可增加：

```text
WebRTC DataChannel
```

服务器只做：

```text
Signaling Server
```

传输：

```text
PC ←────────→ Phone
```

如果 P2P 失败：

```text
fallback cloud
```

最终：

```text
同 LAN：局域网直传
公网可打洞：P2P
否则：云端中转
```

这是比较理想的最终架构。

---

# 60. 最终推荐架构

```text
                      ┌──────────────┐
                      │ PostgreSQL   │
                      └──────┬───────┘
                             │
┌─────────────┐      ┌───────▼────────┐      ┌─────────────┐
│ Android App │─────▶│ FastAPI Server │◀─────│ Windows App │
└──────┬──────┘      └───────┬────────┘      └──────┬──────┘
       │                     │                       │
       │                  Redis                      │
       │                     │                       │
       │             ┌───────▼───────┐               │
       │             │ Message Bus   │               │
       │             └───────────────┘               │
       │                                             │
       └──────────────── OSS ─────────────────────────┘
                    文件存储

实时消息：
WebSocket

文件：
HTTPS / OSS

登录：
JWT

设备：
Device Registry
```

---

# 61. 第一版推荐技术组合

综合开发难度、维护成本和可扩展性，第一版建议直接确定为：

```text
客户端：
Flutter

状态管理：
Riverpod

HTTP：
Dio

本地数据库：
SQLite / Drift

本地安全存储：
Flutter Secure Storage

后端：
FastAPI

数据库：
PostgreSQL

实时通信：
WebSocket

缓存 / 消息：
Redis

反向代理：
Nginx

部署：
Docker Compose

服务器：
Alibaba Cloud ECS

文件：
MVP 本地磁盘
V2 Alibaba OSS
```

---

# 62. Codex 开发规则建议

如果使用 Codex 辅助开发，建议在仓库根目录创建：

```text
AGENTS.md
```

并规定：

```text
1. 前后端分离；
2. API 使用 /api/v1；
3. 所有数据库表使用 UUID；
4. 任何文件下载必须进行 user ownership 校验；
5. WebSocket 事件必须遵循统一 event envelope；
6. 客户端禁止保存明文密码；
7. 后端禁止打印 token；
8. 新功能必须补测试；
9. 所有网络请求必须处理超时；
10. 所有 WebSocket 必须实现重连；
11. 文件上传必须支持取消；
12. 所有异步任务必须处理异常；
13. 不允许在代码中硬编码服务器地址；
14. 配置全部来源于环境变量；
15. 每完成一个 Phase 更新 CHANGELOG。
```

---

# 63. 建议的首批开发任务

可以直接让 Codex 按以下任务开始：

## Task 1

创建 monorepo：

```text
crosslink/
├── client
├── server
└── deploy
```

---

## Task 2

创建 FastAPI：

```text
GET /health
```

返回：

```json
{
  "status": "ok"
}
```

---

## Task 3

创建数据库：

```text
users
devices
sessions
```

---

## Task 4

完成：

```text
register
login
refresh
logout
```

---

## Task 5

创建 Flutter：

```text
login page
home page
device list
```

---

## Task 6

Flutter 登录后：

```text
GET /devices
```

显示设备。

---

## Task 7

建立：

```text
WebSocket Manager
```

PC、手机可以同时连接。

---

## Task 8

完成第一个实时事件：

```text
notification.created
```

手机点击：

```text
向 PC 发送测试消息
```

Windows：

```text
立即显示通知
```

如果这一步跑通，项目最核心的链路就已经成立。

---

# 64. 推荐第一版暂时不要做的功能

为了防止项目失控，第一版不要急着加入：

```text
E2EE
P2P
WebRTC
局域网发现
视频传输优化
文件夹实时同步
远程桌面
远程控制
屏幕镜像
通话
多用户共享
群组
好友系统
```

先完成：

```text
账号
设备
消息
剪贴板
文件
通知
```

软件已经具有很高实用价值。

---

# 65. 产品后续演进方向

项目可以继续扩展成一个完整的：

```text
Personal Device Hub
```

例如：

### 文件能力

```text
文件互传
文件夹同步
网盘
版本历史
```

### 剪贴板能力

```text
文本
图片
代码
链接
历史搜索
```

### 通知能力

```text
电脑通知转手机
手机通知转电脑
```

### 设备能力

```text
查看电量
查看网络
查找设备
远程响铃
```

### 自动化能力

例如：

```text
手机连接校园 Wi-Fi
→ 通知电脑

电脑完成模型训练
→ 手机弹通知

服务器任务完成
→ 手机和电脑同时通知
```

这会让 CrossLink 从“文件传输工具”逐步变成“跨设备自动化平台”。

---

# 66. 建议的软件版本路线

## v0.1

```text
用户登录
设备管理
在线状态
WebSocket
文字消息
```

## v0.2

```text
剪贴板
Windows 通知
Android 分享
```

## v0.3

```text
文件上传
文件下载
传输记录
```

## v0.4

```text
分片上传
断点续传
秒传
```

## v0.5

```text
OSS
后台稳定性
消息可靠性
```

## v0.6

```text
自动剪贴板
图片剪贴板
```

## v0.7

```text
局域网直传
```

## v0.8

```text
WebRTC P2P
```

## v1.0

```text
稳定版
Windows + Android
```

---

# 67. 项目成功的关键

这个项目最关键的并不是 UI，而是四条基础链路一定要稳定：

```text
登录
↓
设备识别
↓
WebSocket 消息
↓
文件传输
```

建议优先把下面这个 Demo 做出来：

```text
Android

[发送到 Wentao-PC]

内容：
hello

[发送]
```

服务器：

```text
FastAPI
↓
WebSocket
```

Windows：

```text
CrossLink

Mate Phone:
hello
```

只要这个流程稳定跑通，后面的：

```text
剪贴板
链接
通知
文件
图片
```

本质上只是不同类型的 Message。

因此整个系统设计最核心的一层应该是：

```text
Unified Message System
```

统一消息结构：

```text
Message
├── sender
├── target
├── type
├── payload
├── timestamp
└── status
```

所有跨设备能力都基于它构建。

---

# 68. 最终 MVP 定义

第一版不要把它定义成“网盘”。

更准确的定义是：

> 一个登录同一账号后，可以让 Windows 与 Android 设备实时互相发送文字、剪贴板、链接、文件和通知的跨设备通信工具。

第一版必须做到：

```text
安装
↓
登录
↓
自动发现设备
↓
选择目标设备
↓
发送
↓
另一端立即收到
```

当这一体验足够稳定后，再继续增加自动同步、P2P、局域网发现、端到端加密等高级功能。

---

# 69. 推荐下一步落地方式

实际开发建议直接拆成三个并行但可独立运行的子项目：

```text
crosslink-server
crosslink-client
crosslink-deploy
```

优先完成服务器和 Windows / Android 共用客户端基础框架。

第一阶段的技术目标不是“把所有功能做全”，而是打通：

```text
同账号多设备登录
        ↓
设备实时在线
        ↓
手机发送消息
        ↓
服务器实时转发
        ↓
Windows 弹出通知
```

这一条链路完成后，再把 `message_type` 从 `text` 扩展为：

```text
clipboard
url
file
image
notification
```

这样整个项目会非常自然地扩展，而不需要反复推翻架构。
