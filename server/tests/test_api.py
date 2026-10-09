import hashlib
import uuid
import pytest
from fastapi.testclient import TestClient
from app.main import create_app

@pytest.fixture
def client(tmp_path):
    app = create_app(app_env="test", database_url=f"sqlite:///{tmp_path}/test.db", file_storage_path=str(tmp_path / "files"), jwt_secret="test-secret-32-characters-minimum!!", max_file_size=1024)
    with TestClient(app) as c:
        yield c

def login(c, username="alice", device="PC", register=True):
    if register:
        response=c.post("/api/v1/auth/register", json={"username":username,"email":f"{username}@example.com","password":"LongPassword123!"})
        assert response.status_code == 201, response.text
    response=c.post("/api/v1/auth/login",json={"account":username,"password":"LongPassword123!","device":{"device_uuid":str(uuid.uuid4()),"device_name":device,"platform":"windows" if device=="PC" else "android"}})
    assert response.status_code==200, response.text
    return response.json()

def auth(t): return {"Authorization": "Bearer "+t["access_token"]}
def send(c,t,target=None,kind="text",payload=None,key=None):
    body={"target_device_id":target,"type":kind,"payload":payload or {"content":"hello pc"}}
    if key: body["client_message_id"]=key
    return c.post("/api/v1/messages",headers=auth(t),json=body)
def recv(ws,event):
    for _ in range(20):
        item=ws.receive_json()
        if item.get("event")==event:return item
    raise AssertionError(f"event {event} missing")
def ws_auth(ws,t):
    ws.send_json({"type":"auth","token":t["access_token"]})
    result=ws.receive_json()
    assert result["type"]=="auth_ok"
    assert result["device_id"]==t["device_id"]

def test_health(client):
    assert client.get("/health").json()=={"status":"ok"}

def test_login_device_names_and_rename(client):
    a=login(client); b=login(client,device="Phone",register=False)
    devices=client.get("/api/v1/devices",headers=auth(a)).json()
    assert {d["name"] for d in devices}=={"PC","Phone"}
    assert client.patch("/api/v1/devices/"+b["device_id"],headers=auth(a),json={"device_name":"Mate"}).status_code==200
    assert client.get("/api/v1/users/me",headers=auth(a)).json()["username"]=="alice"

def test_duplicate_registration_and_invalid_password(client):
    login(client)
    assert client.post("/api/v1/auth/register",json={"username":"alice","email":"second@example.com","password":"LongPassword123!"}).status_code==409
    assert client.post("/api/v1/auth/login",json={"account":"alice","password":"wrong","device":{"device_uuid":str(uuid.uuid4()),"device_name":"PC","platform":"windows"}}).status_code==401

def test_refresh_rotation_replay_and_logout(client):
    a=login(client)
    r=client.post("/api/v1/auth/refresh",json={"refresh_token":a["refresh_token"]})
    assert r.status_code==200
    fresh=r.json(); assert fresh["refresh_token"]!=a["refresh_token"]
    assert client.post("/api/v1/auth/refresh",json={"refresh_token":a["refresh_token"]}).status_code==401
    assert client.post("/api/v1/auth/logout",headers=auth(fresh)).status_code==204
    assert client.get("/api/v1/devices",headers=auth(fresh)).status_code==401
    assert client.post("/api/v1/auth/refresh",json={"refresh_token":fresh["refresh_token"]}).status_code==401

def test_device_revoke_invalidates_access_refresh(client):
    a=login(client);b=login(client,device="Phone",register=False)
    assert client.delete("/api/v1/devices/"+b["device_id"],headers=auth(a)).status_code==204
    assert client.get("/api/v1/devices",headers=auth(b)).status_code==401
    assert client.post("/api/v1/auth/refresh",json={"refresh_token":b["refresh_token"]}).status_code==401

def test_device_uuid_cannot_cross_accounts(client):
    a=login(client);login(client,"bob")
    devices=client.get("/api/v1/devices",headers=auth(a)).json()
    response=client.post("/api/v1/auth/login",json={"account":"bob","password":"LongPassword123!","device":{"device_uuid":devices[0]["device_uuid"],"device_name":"stolen","platform":"android"}})
    assert response.status_code==409

def test_foreign_device_and_message_ownership(client):
    a=login(client);b=login(client,"bob")
    assert send(client,a,b["device_id"]).status_code==404
    assert client.patch("/api/v1/devices/"+b["device_id"],headers=auth(a),json={"device_name":"oops"}).status_code==404
    assert client.delete("/api/v1/devices/"+b["device_id"],headers=auth(a)).status_code==404

def test_offline_message_ack_read_idempotent(client):
    a=login(client);b=login(client,device="Phone",register=False)
    mid=send(client,a,b["device_id"]).json()["id"]
    pending=client.get("/api/v1/messages/pending",headers=auth(b)).json()
    assert [m["id"] for m in pending]==[mid]
    for _ in range(2):
        assert client.post(f"/api/v1/messages/{mid}/ack",headers=auth(b)).json()["status"]=="delivered"
    assert client.post(f"/api/v1/messages/{mid}/read",headers=auth(b)).json()["status"]=="read"
    assert client.post(f"/api/v1/messages/{mid}/ack",headers=auth(b)).json()["status"]=="read"
    assert client.get("/api/v1/messages/pending",headers=auth(b)).json()==[]
    assert client.post(f"/api/v1/messages/{mid}/ack",headers=auth(a)).status_code==404

def test_broadcast_receipts_are_independent(client):
    a=login(client);b=login(client,device="Phone",register=False);c=login(client,device="Tablet",register=False)
    mid=send(client,a).json()["id"]
    client.post(f"/api/v1/messages/{mid}/ack",headers=auth(b))
    assert client.get("/api/v1/messages/pending",headers=auth(b)).json()==[]
    assert client.get("/api/v1/messages/pending",headers=auth(c)).json()[0]["id"]==mid

def test_message_retry_deduplicates(client):
    a=login(client);b=login(client,device="Phone",register=False);key=str(uuid.uuid4())
    x=send(client,a,b["device_id"],key=key);y=send(client,a,b["device_id"],key=key)
    assert x.json()["id"]==y.json()["id"]
    assert len(client.get("/api/v1/messages/pending",headers=auth(b)).json())==1

def test_clipboard_has_hash_origin_and_history(client):
    a=login(client);b=login(client,device="Phone",register=False)
    r=send(client,a,b["device_id"],"clipboard",{"content":"hello"})
    assert r.status_code==201
    p=r.json()["payload"]
    assert p["content_hash"]=="2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
    assert p["origin_device_id"]==a["device_id"]
    assert client.get("/api/v1/clipboard",headers=auth(b)).json()[0]["content"]=="hello"

@pytest.mark.parametrize("kind,payload",[("url",{"content":"javascript:alert(1)"}),("text",{"content":""}),("command",{"content":"shutdown"}),("clipboard",{"content":"x"*102401})])
def test_invalid_message_payloads(client,kind,payload):
    a=login(client)
    assert send(client,a,kind=kind,payload=payload).status_code==422

def test_websocket_presence_delivery_heartbeat_and_replay(client):
    a=login(client);b=login(client,device="Phone",register=False)
    mid=send(client,a,b["device_id"]).json()["id"]
    with client.websocket_connect("/ws") as wa:
        ws_auth(wa,a)
        with client.websocket_connect("/ws") as wb:
            ws_auth(wb,b)
            assert recv(wa,"device.online")["data"]["device_id"]==b["device_id"]
            assert recv(wb,"message.created")["data"]["id"]==mid
            wb.send_json({"type":"ack","message_id":mid})
            assert recv(wb,"message.ack")["data"]["status"]=="delivered"
            wb.send_json({"type":"ping"})
            assert wb.receive_json()["type"]=="pong"
            r=send(client,a,b["device_id"],"notification",{"title":"提醒","content":"完成"})
            ev=recv(wb,"notification.created")
            assert ev["data"]["id"]==r.json()["id"]
            assert "event_id" in ev and "timestamp" in ev
        assert recv(wa,"device.offline")["data"]["device_id"]==b["device_id"]

def test_websocket_rejects_invalid_auth(client):
    from starlette.websockets import WebSocketDisconnect
    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("/ws") as w:
            w.send_json({"type":"auth","token":"invalid"})
            w.receive_json()

def test_file_roundtrip_hash_and_ownership(client):
    a=login(client);b=login(client,device="Phone",register=False);foreign=login(client,"bob")
    response=client.post("/api/v1/files/upload",headers=auth(a),data={"target_device_id":b["device_id"]},files={"file":("../../hello.txt",b"hello","text/plain")})
    assert response.status_code==201,response.text
    f=response.json()
    assert f["name"]=="hello.txt" and f["size"]==5
    assert f["sha256"]=="2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
    assert client.get(f"/api/v1/files/{f['id']}/download",headers=auth(b)).content==b"hello"
    assert client.get(f"/api/v1/files/{f['id']}/download",headers=auth(foreign)).status_code==404
    msg=client.get("/api/v1/messages/pending",headers=auth(b)).json()[0]
    assert msg["type"]=="file" and msg["payload"]["file_id"]==f["id"]
    transfer=client.get("/api/v1/transfers",headers=auth(b)).json()[0]
    assert transfer["message_id"]==msg["id"]
    assert client.get("/api/v1/transfers?file_id="+str(uuid.uuid4()),headers=auth(b)).json()==[]
    assert client.patch(f"/api/v1/transfers/{transfer['id']}",headers=auth(b),json={"status":"completed","progress":100}).status_code==200
    assert client.patch(f"/api/v1/transfers/{transfer['id']}",headers=auth(foreign),json={"status":"completed","progress":100}).status_code==404

def test_file_size_limit_leaves_no_partial(client):
    a=login(client)
    r=client.post("/api/v1/files/upload",headers=auth(a),files={"file":("big.bin",b"x"*1025)})
    assert r.status_code==413
    assert list(client.app.state.settings.file_storage_path.iterdir())==[]

def test_foreign_file_cannot_be_forwarded(client):
    a=login(client);b=login(client,"bob")
    f=client.post("/api/v1/files/upload",headers=auth(a),files={"file":("a.txt",b"hello")}).json()
    assert send(client,b,kind="file",payload={"file_id":f["id"]}).status_code==404

def test_api_errors_have_uniform_envelope(client):
    r=client.get("/api/v1/devices")
    assert r.status_code==401
    assert {"code","message","details"}<=r.json().keys()


def test_file_expiration_and_cleanup(client):
    from app.models import File,Transfer
    from app.files import cleanup
    a=login(client);b=login(client,device="Phone",register=False)
    f=client.post("/api/v1/files/upload",headers=auth(a),data={"target_device_id":b["device_id"]},files={"file":("old.txt",b"old")}).json()
    with client.app.state.factory() as db:
        row=db.get(File,f["id"]);row.expires_at=1;db.commit()
    assert client.get(f"/api/v1/files/{f['id']}/download",headers=auth(b)).status_code==410
    cleanup(client.app.state.factory,client.app.state.settings)
    assert not (client.app.state.settings.file_storage_path/f["id"]).exists()
    assert client.get("/api/v1/transfers",headers=auth(b)).json()[0]["status"]=="expired"

def test_message_idempotency_rejects_different_content(client):
    a=login(client);b=login(client,device="Phone",register=False);key=str(uuid.uuid4())
    assert send(client,a,b["device_id"],key=key).status_code==201
    assert send(client,a,b["device_id"],payload={"content":"different"},key=key).status_code==409

def test_unauthorized_websocket_cannot_ack_another_device_message(client):
    a=login(client);b=login(client,device="Phone",register=False);c=login(client,device="Tablet",register=False)
    mid=send(client,a,b["device_id"]).json()["id"]
    with client.websocket_connect("/ws") as w:
        ws_auth(w,c);w.send_json({"type":"ack","message_id":mid})
        assert recv(w,"error")["data"]["code"]=="MESSAGE_NOT_FOUND"
    assert client.get("/api/v1/messages/pending",headers=auth(b)).json()[0]["id"]==mid

def test_file_upload_invalid_target_removes_disk_and_metadata(client):
    a=login(client);b=login(client,"bob")
    response=client.post("/api/v1/files/upload",headers=auth(a),data={"target_device_id":b["device_id"]},files={"file":("secret.txt",b"secret")})
    assert response.status_code==404
    assert client.get("/api/v1/files",headers=auth(a)).json()==[]
    assert list(client.app.state.settings.file_storage_path.iterdir())==[]

def test_websocket_expires_without_heartbeat(tmp_path):
    from starlette.websockets import WebSocketDisconnect
    app=create_app(app_env="test",database_url=f"sqlite:///{tmp_path}/heartbeat.db",file_storage_path=tmp_path/"files",jwt_secret="test-secret-32-characters-minimum!!",heartbeat_timeout=1)
    with TestClient(app) as c:
        a=login(c)
        with pytest.raises(WebSocketDisconnect):
            with c.websocket_connect("/ws") as w:
                ws_auth(w,a);w.receive_json()

def test_file_at_exact_limit_is_allowed(client):
    a=login(client)
    r=client.post("/api/v1/files/upload",headers=auth(a),files={"file":("limit.bin",b"x"*1024)})
    assert r.status_code==201 and r.json()["size"]==1024

def test_foreign_message_read_rejected(client):
    a=login(client);b=login(client,device="Phone",register=False);foreign=login(client,"bob")
    mid=send(client,a,b["device_id"]).json()["id"]
    assert client.post(f"/api/v1/messages/{mid}/read",headers=auth(foreign)).status_code==404


def test_chunked_request_body_limit(client):
    a=login(client)
    def chunks():
        for _ in range(300):yield b"x"*1024
    response=client.post("/api/v1/messages",headers={**auth(a),"Content-Type":"application/json"},content=chunks())
    assert response.status_code==413


def test_unexpected_error_is_sanitized_and_has_request_id(tmp_path, caplog):
    app = create_app(app_env="test", database_url=f"sqlite:///{tmp_path}/error.db", file_storage_path=str(tmp_path / "files"), web_dist_path=str(tmp_path / "no-web"), jwt_secret="test-secret-32-characters-minimum!!")
    @app.get("/api/v1/testing-failure")
    async def broken():
        raise RuntimeError("SECRET_TOKEN_must_not_leak")
    with TestClient(app, raise_server_exceptions=False) as c:
        response = c.get("/api/v1/testing-failure")
    assert response.status_code == 500
    assert response.json() == {"code": "INTERNAL_ERROR", "message": "Internal server error", "details": {}}
    assert response.headers.get("X-Request-ID")
    assert "SECRET_TOKEN_must_not_leak" not in response.text + caplog.text

@pytest.mark.parametrize("revoked", [False, True])
def test_custom_device_name_survives_relogin(client, revoked):
    a = login(client)
    b = login(client, device="Phone", register=False)
    devices = client.get("/api/v1/devices", headers=auth(a)).json()
    phone = next(d for d in devices if d["id"] == b["device_id"])
    assert client.patch("/api/v1/devices/" + b["device_id"],
        headers=auth(a), json={"device_name": "My phone"}).status_code == 200
    if revoked:
        assert client.delete("/api/v1/devices/" + b["device_id"], headers=auth(a)).status_code == 204
    result = client.post("/api/v1/auth/login", json={
        "account": "alice", "password": "LongPassword123!",
        "device": {"device_uuid": phone["device_uuid"],
                   "device_name": "Phone", "platform": "android"}})
    assert result.status_code == 200
    names = client.get("/api/v1/devices", headers=auth(result.json())).json()
    assert next(d for d in names if d["id"] == b["device_id"])["name"] == "My phone"

@pytest.mark.parametrize("transport", ["rest", "websocket"])
def test_receipts_push_aggregate_state_to_sender(client, monkeypatch, transport):
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
        if transport == "rest":
            result = client.post(f"/api/v1/messages/{mid}/{action}", headers=auth(who))
            assert result.status_code == 200
        else:
            with client.websocket_connect("/ws") as ws:
                ws_auth(ws, who)
                ws.send_json({"type": action, "message_id": mid})
                assert recv(ws, "message.ack")["data"]["message_id"] == mid
        receipts = [e for e in events if e[1] == "message.receipt.updated"]
        assert receipts, "Sender did not receive a receipt event"
        target, kind, data = receipts[-1]
        events.clear()
        assert target == a["device_id"]
        assert kind == "message.receipt.updated"
        assert data["message_id"] == mid
        assert data["recipient_device_id"] == who["device_id"]
        assert data["status"] == expected

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


def test_cleanup_preserves_inflight_final_file(client, monkeypatch):
    import os, threading
    from app import files
    from app.models import now
    a = login(client)
    entered, release = threading.Event(), threading.Event()
    original = files.create_message
    paths, results = [], []
    def pause(db, principal, body, settings):
        path = settings.file_storage_path / body.payload["file_id"]
        old = now() - 2 * 86400
        os.utime(path, (old, old))
        paths.append(path)
        entered.set()
        assert release.wait(10)
        return original(db, principal, body, settings)
    monkeypatch.setattr(files, "create_message", pause)
    worker = threading.Thread(target=lambda: results.append(client.post(
        "/api/v1/files/upload", headers=auth(a), files={"file": ("active.txt", b"active", "text/plain")})))
    worker.start()
    try:
        assert entered.wait(5)
        files.cleanup(client.app.state.factory, client.app.state.settings)
        assert paths[0].read_bytes() == b"active"
        assert worker.is_alive()
    finally:
        release.set()
        worker.join(timeout=10)
    assert not worker.is_alive()
    assert results[0].status_code == 201
    assert paths[0].read_bytes() == b"active"


def test_cleanup_does_not_follow_symlinks(client, tmp_path):
    import os
    from app.files import cleanup
    from app.models import now
    directory = client.app.state.settings.file_storage_path
    outside = tmp_path / "outside.txt"
    outside.write_bytes(b"outside")
    old = now() - 2 * 86400
    os.utime(outside, (old, old))
    links = [directory / str(uuid.uuid4()), directory / "abandoned.part"]
    for link in links: link.symlink_to(outside)
    cleanup(client.app.state.factory, client.app.state.settings)
    assert all(link.is_symlink() for link in links)
    assert outside.read_bytes() == b"outside"


def test_process_exit_before_commit_is_recovered_as_orphan(tmp_path):
    import os, sys, subprocess
    from sqlalchemy import select
    from app.files import cleanup
    from app.models import File, now
    database, directory = tmp_path / "crash.db", tmp_path / "files"
    program = """
import os, sys, uuid
from fastapi.testclient import TestClient
from app.main import create_app
from app import files
app=create_app(app_env='test',database_url='sqlite:///'+sys.argv[1],file_storage_path=sys.argv[2],jwt_secret='test-secret-32-characters-minimum!!')
with TestClient(app) as client:
 client.post('/api/v1/auth/register',json={'username':'crash_user','email':'crash@example.com','password':'LongPassword123!'})
 tokens=client.post('/api/v1/auth/login',json={'account':'crash_user','password':'LongPassword123!','device':{'device_uuid':str(uuid.uuid4()),'device_name':'Crash','platform':'windows'}}).json()
 def crash(*args,**kwargs): os._exit(77)
 files.create_message=crash
 client.post('/api/v1/files/upload',headers={'Authorization':'Bearer '+tokens['access_token']},files={'file':('orphan.txt',b'crash','text/plain')})
"""
    result = subprocess.run([sys.executable, "-c", program, str(database), str(directory)],
                            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}, capture_output=True, text=True)
    assert result.returncode == 77, result.stderr
    orphan = list(directory.iterdir())
    assert len(orphan) == 1 and orphan[0].suffix != ".part"
    app = create_app(app_env="test", database_url=f"sqlite:///{database}", file_storage_path=directory,
                     jwt_secret="test-secret-32-characters-minimum!!")
    with TestClient(app):
        with app.state.factory() as db: assert list(db.scalars(select(File))) == []
        old = now() - 2 * 86400
        os.utime(orphan[0], (old, old))
        cleanup(app.state.factory, app.state.settings)
        assert not orphan[0].exists()

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

@pytest.mark.parametrize("params", [
    {"before_id": "not-a-uuid", "before": 1700000000},
    {"before_id": "11111111-1111-1111-1111-111111111111"}])
def test_history_rejects_invalid_cursor(client, params):
    a = login(client)
    assert client.get("/api/v1/messages", headers=auth(a), params=params).status_code == 422


def test_history_pages_do_not_include_foreign_accounts(client):
    from sqlalchemy import update
    from app.models import Message
    a = login(client)
    b = login(client, username="bob")
    owned = [send(client, a).json()["id"] for _ in range(5)]
    foreign = [send(client, b).json()["id"] for _ in range(2)]
    with client.app.state.factory() as db:
        db.execute(update(Message).values(created_at=1700000000)); db.commit()
    seen = []
    params = {"limit": 2}
    for _ in range(5):
        page = client.get("/api/v1/messages", headers=auth(a), params=params).json()
        if not page:break
        seen.extend(m["id"] for m in page)
        params.update(before=page[-1]["created_at"], before_id=page[-1]["id"])
    assert seen == sorted(owned, reverse=True)
    assert not set(foreign).intersection(seen)
    assert len(seen) == len(set(seen))


def test_clipboard_revision_latest_and_client_fields_are_authoritative(client):
    a=login(client);b=login(client,device="Phone",register=False)
    first=send(client,a,b["device_id"],"clipboard",{"content":"你好\nhttps://example.com", "clipboard_revision":999, "origin_device_id":"forged"}).json()
    assert first["payload"].get("clipboard_revision")==1
    assert first["payload"]["origin_device_id"]==a["device_id"]
    second=send(client,a,b["device_id"],"clipboard",{"content":"next"}).json()
    assert second["payload"]["clipboard_revision"]==2
    latest=client.get("/api/v1/clipboard/latest",headers=auth(b))
    assert latest.status_code==200
    assert latest.json()["id"]==second["id"]


def test_clipboard_retry_reuses_revision_and_new_operation_advances(client):
    a=login(client);b=login(client,device="Phone",register=False);key=str(uuid.uuid4())
    first=send(client,a,b["device_id"],"clipboard",{"content":"same"},key=key).json()
    retry=send(client,a,b["device_id"],"clipboard",{"content":"same"},key=key).json()
    assert retry["id"]==first["id"]
    assert retry["payload"].get("clipboard_revision")==1
    next_message=send(client,a,b["device_id"],"clipboard",{"content":"same"},key=str(uuid.uuid4())).json()
    assert next_message["payload"]["clipboard_revision"]==2


def test_latest_clipboard_is_visible_only_to_snapshot_recipients(client):
    a=login(client);b=login(client,device="Phone",register=False);c=login(client,device="Tablet",register=False);foreign=login(client,username="bob")
    for who in (a,b,c,foreign):
        result=client.get("/api/v1/clipboard/latest",headers=auth(who))
        assert result.status_code==200 and result.json() is None
    first=send(client,a,b["device_id"],"clipboard",{"content":"for phone"}).json()
    second=send(client,a,c["device_id"],"clipboard",{"content":"for tablet"}).json()
    assert client.get("/api/v1/clipboard/latest",headers=auth(b)).json()["id"]==first["id"]
    assert client.get("/api/v1/clipboard/latest",headers=auth(c)).json()["id"]==second["id"]
    assert client.get("/api/v1/clipboard/latest",headers=auth(a)).json()["id"]==second["id"]
    assert client.get("/api/v1/clipboard/latest",headers=auth(foreign)).json() is None


def test_expired_clipboard_snapshot_is_not_applied(client):
    from sqlalchemy import update
    from app.models import Message,now
    a=login(client);b=login(client,device="Phone",register=False)
    message=send(client,a,b["device_id"],"clipboard",{"content":"expired"}).json()
    with client.app.state.factory() as db:
        db.execute(update(Message).where(Message.id==message["id"]).values(clipboard_expires_at=now()-1));db.commit()
    assert client.get("/api/v1/clipboard/latest",headers=auth(b)).json() is None


@pytest.mark.parametrize("content", [" \t ", "\r\n", "　"])
def test_clipboard_preserves_whitespace_content(client, content):
    a=login(client);b=login(client,device="Phone",register=False)
    response=send(client,a,b["device_id"],"clipboard",{"content":content})
    assert response.status_code==201
    assert response.json()["payload"]["content"]==content
