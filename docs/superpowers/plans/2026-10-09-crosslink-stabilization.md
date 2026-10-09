# CrossLink 稳定性修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 本次交付的是计划；实施按用户后续指令推进，不在规划阶段修改产品代码。

**Goal:** 修复 2026-10-09 审查确认的五项问题，为 Windows/Android 安装包和实机互传建立可靠基线。

**Architecture:** 保持单 API worker、PostgreSQL 持久状态、按账号归属投递、Android 单一原生连接/刷新拥有者。新增连接状态快照、发送端回执事件、保守文件对账和复合历史游标，兼容现有 REST 数据形状。

**Tech Stack:** 当前已锁定的 FastAPI / SQLAlchemy、Flutter / Dart、Kotlin / OkHttp，pytest、flutter_test、JUnit / MockWebServer。

**Spec:** `/home/CrossLink/docs/DEVELOPMENT_DESIGN.md`；本目录 `2026-10-09-crosslink-delivery-roadmap.md`；基线提交 `c9f12d8630c681b66306f91ca1dfb6f97030dd69`。本文所有相对文件路径相对于 `/home/CrossLink`。

## Global Constraints

- All development, installs, tests and builds run via SSH in /home/CrossLink. No local generated artifacts.
- API prefix /api/v1; database entity IDs are UUIDs.
- Check ownership on every device/message/receipt/file/transfer operation.
- Websocket events use event/event_id/timestamp/data; clients send auth after connection, never in the URL.
- Persist messages before publishing and keep receipts per device.
- No plaintext passwords or token/clipboard logging.
- Keep one API worker until a Redis message bus is implemented.
- No public listeners or firewall/security-group changes without the user's later request.
- 同一服务器上重型测试/构建顺序执行；测试数据与临时文件只放项目目录。修复不改用户已经选择的“账号密码登录、平台地址内置”模式。

## Review Focus

1. 已登录后台连接仍活着时重新附着界面，不应永久显示连接中；状态快照与异步事件乱序时不能倒退。S1。
2. 从另一台设备改名后，这台设备的旧本地名称不能覆盖服务端自定义值。S2。
3. 广播中只有部分设备送达/已读以及重复、乱序回执，发送端的聚合状态必须准确。S3。
4. 提交前进程退出产生孤儿，清理又恰遇活动上传，回收和保留边界必须互不混淆。S4。
5. 多条同秒消息跨页及不同账号的查询边界，应完整且不越权。S5。

## 0. 文件职责与证据约定

| 文件 | 职责 |
|---|---|
| `client/lib/controller.dart` | 用户会话、页面连接状态、设备名称、消息/回执协调 |
| `client/lib/platform_native.dart` | Flutter 与原生的连接快照协议 |
| `client/lib/protocol.dart` | 消息缓存及单调回执合并 |
| `client/android/app/src/main/kotlin/com/crosslink/crosslink/SyncClient.kt` | 单一后台连接、刷新、连接状态与版本 |
| `client/android/app/src/main/kotlin/com/crosslink/crosslink/MainActivity.kt` | 快照查询/启动桥接 |
| `client/android/app/src/main/kotlin/com/crosslink/crosslink/SyncService.kt` | 服务生命周期、owner 标记、状态转发 |
| `server/app/accounts.py` | 登陆已有设备时保留名称 |
| `server/app/messages.py`、`server/app/realtime.py` | ACK/read 持久化与回执推送、消息历史 |
| `server/app/files.py`、`server/app/main.py` | 上传活动登记、文件对账与后台清理 |
| `server/tests/test_api.py` | 现有 client/login/auth/send 等 fixture/helper；新增 API 回归放在此文件，避免复制 fixture |
| `client/test/controller_background_state_test.dart`、`client/test/receipt_test.dart` | 新增连接附着、回执合并用例 |
| `docs/API.md`、`docs/WEBSOCKET.md`、`CHANGELOG.md` | 对应接口和修复行为记录 |

每项实施采用“复现失败 → 最小修复 → 对应用例通过 → 相关回归 → 独立提交”。下面是目标行为和关键代码；实际修改必须同时接入所有列明的调用点，不能只新增未使用的辅助函数。不要批量重写无关文件。

## S1：Android 连接状态真实回传

**Files:** 修改 `controller.dart`、`platform_native.dart`、`MainActivity.kt`、`SyncClient.kt`、`SyncService.kt`；新增 `client/test/controller_background_state_test.dart`；扩展 `client/android/app/src/test/kotlin/com/crosslink/crosslink/SyncClientTest.kt`。

**根因:** 现有 `backgroundStart` 复用已有连接时仅返回 tokens，不重发 auth_ok；Dart 先把连接状态设为“连接中”，此后没有事件将其恢复。实际复现文件及失败日志已在 `.tools/progress-review-20261009-background_test.dart` 与同名前缀 `.log`。

**Interfaces:** `backgroundStart` 与 `backgroundSnapshot` 统一返回如下 JSON；此接口是 App 内部通道，Kotlin 和 Dart 在同一提交中升级：

```json
{
  "endpoint": "https://127.0.0.1:8443",
  "owner": "test-owner",
  "tokens": {
    "device_id": "test-device",
    "access_token": "test-access",
    "refresh_token": "test-refresh",
    "_native_owner": "test-owner"
  },
  "connection": {"state": "connected", "revision": 4}
}
```

`state` 只取 connecting/connected/reconnecting/stopped；`revision` 在同一 owner 内单调递增。后台事件新增 `{type:connection.state,owner,state,revision}`。持久化凭据沿用 SessionStore；进程新建不能从旧磁盘数据推断 connected。

- [ ] **Step 1：纳入原始复现并确认失败。** 原始断言保持不变，先不要改生产代码。

```bash
cd /home/CrossLink
cp .tools/progress-review-20261009-background_test.dart client/test/controller_background_state_test.dart
. deploy/flutter-env.sh
cd client
flutter --no-version-check test --no-pub test/controller_background_state_test.dart
```

预期：`Expected: 实时连接; Actual: 连接中`。若行为已变，先核对提交，不能盲目继续原修复。

- [ ] **Step 2：让原生拥有明确状态快照。** 在 SyncClient 增加状态锁和版本，每次状态转换都更新再通知；只有 auth_ok 才进入 connected，失败/重连进入 reconnecting，stop 进入 stopped。下面的函数纳入 SyncClient，并在 start、auth_ok、reconnect、stop 调用。

```kotlin
private val stateLock = Any()
private var connectionState = "stopped"
private var stateRevision = 0L
fun connectionSnapshot(): JSONObject = synchronized(stateLock) {
    JSONObject().put("state", connectionState).put("revision", stateRevision)
}
private fun transition(next: String) {
    val value = synchronized(stateLock) {
        if (connectionState == next) return
        connectionState = next
        stateRevision += 1
        JSONObject().put("type", "connection.state")
            .put("state", next).put("revision", stateRevision)
    }
    event(value)
}
```

所有事件仍由 SyncService 添加 owner。MainActivity 对已有连接返回实际 `connectionSnapshot()`；新启动尚无 worker 时返回 connecting/revision=0，不能提前声称已认证。token 刷新返回仍是 tokens，避免混改 backgroundRefresh。

- [ ] **Step 3：客户端接入快照与事件。** `startBackground` 解析外层快照；controller 先校验当前 Api 与会话代次，再 accept(snapshot.tokens)，然后应用状态。对同 owner 只接收不小于当前 revision 的状态；新 owner 重置 revision。旧 owner、退出后的返回值继续拒绝。

```dart
const nativeConnectionLabels = <String, String>{
  'connecting': '连接中',
  'connected': '实时连接',
  'reconnecting': '离线 · 自动重连',
  'stopped': '未连接',
};
```

auth_ok 继续触发历史/设备刷新，但连接状态统一由带版本的状态通道更新，避免无版本回调覆盖新状态。已有复现测试的通道 mock 改为上述实际新协议结构，保留“成功附着后为实时连接”的行为断言。

- [ ] **Step 4：扩展边界测试。** 同一测试文件增加以下断言，均通过现有 MethodChannel mock 注入：connected 快照立即正确；reconnecting 快照不能显示实时连接；revision=5 后到达 revision=4 不倒退；owner 变化后旧事件无效；backgroundStart 晚于 logout 返回不恢复会话。Kotlin 用 MockWebServer 核验 auth_ok 前后、关闭后与 stop 后快照。
- [ ] **Step 5：执行相关验证并提交。**

```bash
cd /home/CrossLink
. deploy/flutter-env.sh
cd client
flutter --no-version-check test --no-pub test/controller_background_state_test.dart test/controller_network_test.dart test/api_background_test.dart
cd ..
python3 deploy/test-android.py
```

原生源码/测试修改后应真实执行 JUnit，核对 XML 新时间与失败数；不能把 UP-TO-DATE 当作新运行。完成后只提交列明文件和 CHANGELOG，提交意图：`fix: restore Android connection state on UI reattach`。

## S2：设备自定义名称不被重新登录覆盖

**Files:** 修改 `server/app/accounts.py`、`client/lib/controller.dart`、`server/tests/test_api.py`、`CHANGELOG.md`。

**Interfaces:** 登录返回和 PATCH `/devices/{id}` 形状不变。新设备允许用系统自动名初始化；已有设备以服务端已保存的名称为准，修改名称统一走 PATCH。

- [ ] **Step 1：加入以下失败用例。** 所有 helper 均已在同一个 `test_api.py` 定义。

```python
def test_custom_device_name_survives_relogin(client):
    a = login(client)
    b = login(client, device="Phone", register=False)
    devices = client.get("/api/v1/devices", headers=auth(a)).json()
    phone = next(d for d in devices if d["id"] == b["device_id"])
    assert client.patch("/api/v1/devices/" + b["device_id"],
        headers=auth(a), json={"device_name": "My phone"}).status_code == 200
    result = client.post("/api/v1/auth/login", json={
        "account": "alice", "password": "LongPassword123!",
        "device": {"device_uuid": phone["device_uuid"],
                   "device_name": "Phone", "platform": "android"}})
    assert result.status_code == 200
    names = client.get("/api/v1/devices", headers=auth(result.json())).json()
    assert next(d for d in names if d["id"] == b["device_id"])["name"] == "My phone"
```

```bash
cd /home/CrossLink/server
../.venv/bin/python -m pytest -q tests/test_api.py -k custom_device_name_survives_relogin
```

预期修复前名称实际为 Phone。

- [ ] **Step 2：只改变已有设备的元数据更新。** 保留已有 revoked/session 处理；新设备分支不变。

```python
for key, value in body.device.model_dump(
        exclude={"device_uuid", "device_name"}).items():
    setattr(device, key, value)
```

- [ ] **Step 3：客户端名称显示跟随服务端。** reload 和设备事件读取当前 deviceId 的名称更新 `deviceName`；首次创建账号设备时用系统自动名，避免把上一账号的自定义名带入。自定义缓存按设备身份隔离，不依赖当前全局 `device_name` 作为最终权威。给异步刷新保留会话代次检查，防止退出后刷新旧账号。
- [ ] **Step 4：补充本机改名/另一端改名/注销重登/设备撤销后重登/切换账号五种情况。** API 测试验证服务器持久值，Dart 测试验证当前设备标题与设置同步；不重复添加只校验字符串赋值的实现镜像测试。
- [ ] **Step 5：相关测试通过后提交。** 提交意图：`fix: preserve device names across sign-in`。

## S3：发送端实时更新送达与已读

**Files:** 修改 `server/app/messages.py`、`server/app/realtime.py`、`server/tests/test_api.py`、`client/lib/controller.dart`、`client/lib/protocol.dart`、`docs/WEBSOCKET.md`、`docs/API.md`、`CHANGELOG.md`；新增 `client/test/receipt_test.dart`；扩展 `deploy/smoke_live.py`。

**Interfaces:** 新增 `message.receipt.updated`，仍使用标准 envelope。data 为：

```json
{
  "message_id": "message-uuid",
  "recipient_device_id": "recipient-uuid",
  "recipient_status": "read",
  "status": "delivered"
}
```

`recipient_status` 是该接收设备状态，`status` 是发送端所有收件设备的聚合状态；部分已读不等于全部已读。现有 REST ACK/read 返回和 WebSocket `message.ack` 响应保持不变，新增事件只发给原消息的发送设备。重复 ACK 可重复发布相同状态，客户端必须幂等。

- [ ] **Step 1：加入不阻塞等待 WebSocket 的回归测试。** 使用实际 REST/数据库路径，仅捕获 Hub 边界事件；修复前会明确断言失败而非挂起。

```python
def test_receipts_push_aggregate_state_to_sender(client, monkeypatch):
    events = []
    async def capture(device_id, event, data):
        events.append((device_id, event, data))
    monkeypatch.setattr(client.app.state.hub, "send", capture)
    a = login(client)
    b = login(client, device="Phone", register=False)
    c = login(client, device="Tablet", register=False)
    mid = send(client, a).json()["id"]
    events.clear()
    for who, action, expected in [
        (b, "ack", "pending"), (c, "ack", "delivered"),
        (b, "read", "delivered"), (c, "read", "read"),
        (b, "ack", "read")]:
        result = client.post(f"/api/v1/messages/{mid}/{action}", headers=auth(who))
        assert result.status_code == 200
        assert events, "Sender did not receive a receipt event"
        target, kind, data = events.pop()
        assert target == a["device_id"]
        assert kind == "message.receipt.updated"
        assert data["message_id"] == mid
        assert data["recipient_device_id"] == who["device_id"]
        assert data["status"] == expected
```

```bash
cd /home/CrossLink/server
../.venv/bin/python -m pytest -q tests/test_api.py -k receipts_push_aggregate_state_to_sender
```

- [ ] **Step 2：在持久化后统一推送。** 在 messages.py 定义 `async publish_receipt(app, db, message_id: str, recipient_device_id: str) -> None`：

```python
async def publish_receipt(app, db, message_id: str, recipient_device_id: str):
    message = db.get(Message, message_id)
    receipt = db.scalar(select(Receipt).where(
        Receipt.message_id == message_id,
        Receipt.device_id == recipient_device_id))
    if message is None or receipt is None:
        return
    await app.state.hub.send(message.sender_device_id,
        "message.receipt.updated", {
            "message_id": message.id,
            "recipient_device_id": recipient_device_id,
            "recipient_status": receipt.status,
            "status": view(db, message, message.sender_device_id)["status"]})
```

REST ACK/read 路由改为 async，在原 `acknowledge()` 成功提交后调用该函数；原返回值不变。realtime.py 的 ack/read 分支也在原持久化成功后调用。不能绕开原有所有权检查，不能在提交前对发送端声称已送达。

- [ ] **Step 3：客户端两条事件路径接入。** `_handleSocket` 和 `_handleBackground` 处理该事件，用 `MessageCache.updateReceipt(String messageId, String status) -> bool` 更新已存在的发送记录；不得调用 `_receive`，从而不触发多余 ACK/系统通知。该方法不插入缺失历史，并按 pending → delivered → read 保持单调。

```dart
test('receipt merge is monotonic and does not create messages', () {
  final cache = MessageCache();
  cache.put({'id': 'm', 'status': 'pending'});
  expect(cache.updateReceipt('m', 'delivered'), isTrue);
  expect(cache.items.single['status'], 'delivered');
  cache.updateReceipt('m', 'read');
  cache.updateReceipt('m', 'delivered');
  expect(cache.items.single['status'], 'read');
  expect(cache.updateReceipt('absent', 'read'), isFalse);
  expect(cache.items.length, 1);
});
```

新 `receipt_test.dart` 导入 `package:flutter_test/flutter_test.dart` 与 `package:crosslink/protocol.dart`，放入 `void main()`。另外用现有网络测试模式发入回执事件，检查界面缓存更新且 HTTP ACK 次数不增加。

- [ ] **Step 4：恢复丢失的回执状态。** Windows/Web 重连、Android auth_ok 后刷新服务器消息历史，使连接断开期间未收到的回执恢复。刷新结果仍检查 session generation；不能把回执更新当作新的入站消息，也不能重发通知。
- [ ] **Step 5：扩展真实 HTTPS/WSS 联调。** 两端在线时等待发送端收到事件；给所有 recv 设置 5 秒超时。发送端离线时由接收端 ACK/read，再重新上线查询真实状态；同时核验广播、重复 ACK、外账号 ACK 拒绝。测试全部通过后提交 `fix: propagate delivery receipts to sending devices`。

## S4：上传提交窗口的孤儿文件回收

**Files:** 修改 `server/app/files.py`、`server/app/main.py`、`server/tests/test_api.py`、`CHANGELOG.md`；无需改变现有文件/消息表结构。

**Interfaces:** 保留 `cleanup(factory, settings)` 调用方式。在 files.py 内维护线程安全的活动上传 ID 集合和互斥锁，上传进入文件写入前登记，finally 中退出；对账只处理项目存储目录下一层、文件名符合标准 UUID、非符号链接的常规文件。

- [ ] **Step 1：加入孤儿与保留边界用例。**

```python
def test_cleanup_reclaims_only_old_orphan_files(client):
    import os
    from app.files import cleanup
    from app.models import now
    a = login(client)
    response = client.post("/api/v1/files/upload", headers=auth(a),
        files={"file": ("kept.txt", b"kept", "text/plain")})
    assert response.status_code == 201
    settings = client.app.state.settings
    directory = settings.file_storage_path
    known = directory / response.json()["id"]
    old = directory / str(uuid.uuid4())
    fresh = directory / str(uuid.uuid4())
    old.write_bytes(b"orphan")
    fresh.write_bytes(b"recent")
    cutoff = now() - 2 * 86400
    os.utime(old, (cutoff, cutoff))
    os.utime(known, (cutoff, cutoff))
    cleanup(client.app.state.factory, settings)
    assert not old.exists()
    assert fresh.read_bytes() == b"recent"
    assert known.read_bytes() == b"kept"
```

```bash
cd /home/CrossLink/server
../.venv/bin/python -m pytest -q tests/test_api.py -k cleanup_reclaims_only_old_orphan_files
```

预期修复前旧 orphan 仍存在。

- [ ] **Step 2：增加保守对账。** 原有过期文件和 `.part` 清理保留。新增扫描在 24 小时宽限期后清理没有数据库引用的 UUID 文件；阈值和时间读取在测试中可控制。删除前在同一互斥锁内重新检查活动集、文件类型/mtime 和数据库引用，上传登记也使用该锁；不递归、不跟随 symlink、不删除非 UUID 文件。

```python
# 放在 files.py；threading 与 stat 为标准库。
_storage_lock = threading.RLock()
_active_uploads: set[str] = set()
```

上传文件进入登记后再创建 `.part`，持有的标记涵盖最终重命名和 DB 提交全过程。正常异常清理与活动标记释放均在 finally，不能因新增对账移除现有失败回收。

- [ ] **Step 3：补充活动/符号链接/过期边界。** 测试活动 ID 即使 mtime 已旧也保留；symlink 指向存储目录外不触碰；有有效 File 引用保留；过期已入库文件仍被现有保留期清理。所有文件使用 pytest 项目临时目录。
- [ ] **Step 4：验证真正的进程中断。** 在隔离子进程、临时 SQLite 和临时存储中，将 files.create_message 注入以下故障点；它位于 part.replace 后。父进程检查返回码 77、没有 File 行、存在最终 UUID 文件；推进测试文件 mtime 超过宽限期后运行 cleanup，确认回收。不得终止线上 API。

```python
def crash_before_commit(*args, **kwargs):
    import os
    os._exit(77)
```

父进程还应断言正常成功上传的文件不被同一恢复扫描删除。主测试进程绝不能安装并调用上述退出函数。
- [ ] **Step 5：相关测试与真实上传/取消路径通过后提交。** 提交意图：`fix: reconcile abandoned upload files safely`。

## S5：时间与 ID 复合历史游标

**Files:** 修改 `server/app/messages.py`、`server/tests/test_api.py`、`docs/API.md`、`CHANGELOG.md`。

**Interfaces:** `/messages` 保留返回数组、limit、before，新增 `before_id` UUID 参数。无游标取最新；同时传 before 与 before_id 获得无遗漏的下一页。仅 before 的旧请求继续保留旧的时间过滤语义；文档明确同秒无遗漏分页必须使用新参数。只传 before_id 或无效 UUID 返回 422。当前客户端仍默认最近 100 条，不在该修复中扩展全部历史 UI。

- [ ] **Step 1：加入受控同秒分页测试。**

```python
def test_history_composite_cursor_keeps_same_second_messages(client):
    from sqlalchemy import update
    from app.models import Message
    a = login(client)
    ids = [send(client, a).json()["id"] for _ in range(3)]
    with client.app.state.factory() as db:
        db.execute(update(Message).where(Message.id.in_(ids))
                   .values(created_at=1700000000))
        db.commit()
    page1 = client.get("/api/v1/messages", headers=auth(a),
                       params={"limit": 2}).json()
    page2 = client.get("/api/v1/messages", headers=auth(a), params={
        "limit": 2, "before": page1[-1]["created_at"],
        "before_id": page1[-1]["id"]}).json()
    assert len(page1) == 2
    assert len(page2) == 1
    found = [m["id"] for m in page1 + page2]
    assert found == sorted(ids, reverse=True)
```

```bash
cd /home/CrossLink/server
../.venv/bin/python -m pytest -q tests/test_api.py -k history_composite_cursor_keeps_same_second_messages
```

修复前 before_id 被忽略，第二页为空。

- [ ] **Step 2：实现严格的复合边界。** 引入 `and_` 和 `UUID`，将 history 路由签名扩展为 `def history(p=Depends(principal), db=Depends(get_db), limit: int = Query(100, ge=1, le=500), before: int | None = None, before_id: UUID | None = Query(default=None))`；在现有 user/device 可见性条件之后增加以下过滤；顺序继续是 created_at DESC、id DESC。

```python
if before_id is not None and before is None:
    fail(422, "INVALID_CURSOR", "before is required with before_id")
if before is not None:
    boundary = Message.created_at < before
    if before_id is not None:
        boundary = or_(boundary, and_(
            Message.created_at == before,
            Message.id < str(before_id)))
    query = query.where(boundary)
```

- [ ] **Step 3：覆盖空页、跨秒、多页连续遍历、无效 UUID 和外账号边界。** 外账号记录不能因为游标条件的 OR 分组而绕过既有所有权过滤；验证无游标与 before-only 的兼容响应。
- [ ] **Step 4：更新 API 示例。** 说明下一页使用上一页最后一条的 created_at 和 id，不能只复用时间值。测试通过后提交 `fix: preserve same-second messages across history pages`。

## 6. 阶段回归、联调与交接

- [ ] 所有新用例都有修复前失败和修复后通过证据；涉及的现有用例通过，不编造固定测试总数。
- [ ] 顺序运行以下检查，逐一核对退出码与输出；如果原生任务显示 UP-TO-DATE，仅引用它的历史记录或使用受控的新测试运行，不宣称新执行。

```bash
cd /home/CrossLink/server
../.venv/bin/python -m pytest -q
cd /home/CrossLink
. deploy/flutter-env.sh
cd client
flutter --no-version-check analyze --no-pub
flutter --no-version-check test --no-pub
cd ..
python3 deploy/test-android.py
CROSSLINK_URL=https://127.0.0.1:8443 CROSSLINK_CA=/home/CrossLink/client/assets/platform_ca.pem .venv/bin/python deploy/smoke_live.py
```

- [ ] 真实平台联调先在隔离候选实例完成；线上验证须在代码部署并健康检查后执行，不能对旧运行进程的通过结果宣称新代码已验证。重启持久化检查使用明确候选实例，避免为测试反复重启线上服务。
- [ ] 更新 `docs/VERIFICATION.md` 为按日期追加的证据记录；保留旧记录，清楚标记新的提交、测试时间和未覆盖的真实设备项。
- [ ] 汇总这五项修复为 0.2.1 内部稳定版本，优先进入总路线的 C4 复制粘贴同步，再完成 C1–C3；用户已明确提醒复制粘贴同步不能遗漏。若只完成修复，不宣称 Windows 二进制、Android release 或公网用户流程已经完成。
