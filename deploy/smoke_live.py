"""Real loopback API/PostgreSQL/websocket/file/restart acceptance. Run via SSH."""
import hashlib,json,os,secrets,subprocess,time,uuid,ssl
from pathlib import Path
import httpx
from websockets.sync.client import connect
from sqlalchemy import create_engine,delete,select,update
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"server"))
from app.config import Settings
from app.models import User,Device,Session,Message,Receipt,File,Transfer,Clipboard
from sqlalchemy.orm import Session as DB
base=os.environ.get("CROSSLINK_URL","http://127.0.0.1:8765")
ca=os.environ.get("CROSSLINK_CA")
client=httpx.Client(base_url=base,timeout=20,verify=ca or True)
ws_options={"ssl":ssl.create_default_context(cafile=ca)} if base.startswith("https://") else {}
username="smoke_"+secrets.token_hex(5);password=secrets.token_urlsafe(20)
user_ids=[]
def check(r,code=200):
    assert r.status_code==code,(r.status_code,r.text)
    return r.json() if r.content else None

def register(name):
    value=check(client.post("/api/v1/auth/register",json={"username":name,"email":name+"@example.com","password":password}),201)
    user_ids.append(value["id"])
def login(name,device):
    return check(client.post("/api/v1/auth/login",json={"account":name,"password":password,"device":{"device_uuid":str(uuid.uuid4()),"device_name":device,"platform":"windows" if device=="PC" else "android"}}))
def headers(t):return {"Authorization":"Bearer "+t["access_token"]}
def recv(ws,event):
    for _ in range(20):
        value=json.loads(ws.recv(timeout=5))
        if value.get("event")==event:return value
    raise AssertionError(event)
def authenticate(ws,t):
    ws.send(json.dumps({"type":"auth","token":t["access_token"]}));assert json.loads(ws.recv(timeout=5))["type"]=="auth_ok"
try:
    check(client.get("/health"));register(username);register(username+"_foreign")
    a=login(username,"PC");b=login(username,"Phone");foreign=login(username+"_foreign","Other")
    assert len(check(client.get("/api/v1/devices",headers=headers(a))))==2
    socket_url=base.replace("http","ws",1)+"/ws"
    with connect(socket_url,**ws_options) as wa,connect(socket_url,**ws_options) as wb:
        authenticate(wa,a);authenticate(wb,b)
        assert recv(wa,"device.online")["data"]["device_id"]==b["device_id"]
        start=time.monotonic()
        mid=check(client.post("/api/v1/messages",headers=headers(b),json={"target_device_id":a["device_id"],"type":"clipboard","payload":{"content":"hello pc — 实时剪贴板"}}),201)["id"]
        event=recv(wa,"clipboard.updated");assert event["data"]["id"]==mid
        assert time.monotonic()-start<2
        wa.send(json.dumps({"type":"ack","message_id":mid}));assert recv(wa,"message.ack")["data"]["status"]=="delivered"
        receipt=recv(wb,"message.receipt.updated")["data"];assert receipt["message_id"]==mid and receipt["status"]=="delivered"
        wa.send(json.dumps({"type":"read","message_id":mid}));assert recv(wa,"message.ack")["data"]["status"]=="read"
        assert recv(wb,"message.receipt.updated")["data"]["status"]=="read"
    print("PASS: real PostgreSQL, two devices, presence, clipboard websocket under 2 seconds, ACK")
    data="CrossLink 文件传输测试\n".encode()
    f=check(client.post("/api/v1/files/upload",headers=headers(a),data={"target_device_id":b["device_id"]},files={"file":("验证.txt",data,"text/plain")}),201)
    received=client.get(f"/api/v1/files/{f['id']}/download",headers=headers(b));assert received.content==data and hashlib.sha256(data).hexdigest()==f["sha256"]
    check(client.get(f"/api/v1/files/{f['id']}/download",headers=headers(foreign)),404)
    print("PASS: real multipart upload, download, SHA256, ownership rejection")
    mid=check(client.post("/api/v1/messages",headers=headers(a),json={"target_device_id":b["device_id"],"type":"text","payload":{"content":"survive restart"}}),201)["id"]
    if os.environ.get("CROSSLINK_RESTART_TEST")=="1":
        subprocess.run(["systemctl","restart","crosslink-api"],check=True)
        for _ in range(40):
            try:
                if client.get("/health").status_code==200:break
            except httpx.HTTPError:pass
            time.sleep(.25)
        with connect(socket_url,**ws_options) as wb:
            authenticate(wb,b)
            seen=[]
            for _ in range(3):
                event=json.loads(wb.recv(timeout=5));seen.append(event["data"]["id"])
                if mid in seen:break
            assert mid in seen
        assert client.get(f"/api/v1/files/{f['id']}/download",headers=headers(b)).content==data
        print("PASS: API restart preserves credentials, pending replay and stored files")
    # Preserve an explicitly renamed device when its stale automatic name reappears at login.
    devices=check(client.get("/api/v1/devices",headers=headers(a)))
    phone=next(d for d in devices if d["id"]==b["device_id"])
    check(client.patch("/api/v1/devices/"+b["device_id"],headers=headers(a),json={"device_name":"Custom phone"}))
    b=check(client.post("/api/v1/auth/login",json={"account":username,"password":password,"device":{"device_uuid":phone["device_uuid"],"device_name":"Phone","platform":"android"}}))
    assert next(d for d in check(client.get("/api/v1/devices",headers=headers(b))) if d["id"]==b["device_id"])["name"]=="Custom phone"
    # Force only disposable test messages onto a same-second boundary; verify real PostgreSQL ordering.
    ids=[check(client.post("/api/v1/messages",headers=headers(a),json={"target_device_id":b["device_id"],"type":"text","payload":{"content":"cursor test"}}),201)["id"] for _ in range(3)]
    settings=Settings();test_engine=create_engine(settings.database_url)
    try:
        with DB(test_engine) as db:
            db.execute(update(Message).where(Message.id.in_(ids),Message.user_id==user_ids[0]).values(created_at=1700000000));db.commit()
    finally:test_engine.dispose()
    first=check(client.get("/api/v1/messages",headers=headers(a),params={"limit":2,"before":1700000001}))
    second=check(client.get("/api/v1/messages",headers=headers(a),params={"limit":2,"before":first[-1]["created_at"],"before_id":first[-1]["id"]}))
    assert [m["id"] for m in first+second]==sorted(ids,reverse=True)
    print("PASS: custom device name survives sign-in; real PostgreSQL same-second history cursor")
    # Atomic clipboard revisions and idempotent operations across real concurrent HTTP calls.
    from concurrent.futures import ThreadPoolExecutor
    key=str(uuid.uuid4());body={"target_device_id":b["device_id"],"type":"clipboard","client_message_id":key,"payload":{"content":" \t\r\n"}}
    clip=check(client.post("/api/v1/messages",headers=headers(a),json=body),201)
    duplicate=check(client.post("/api/v1/messages",headers=headers(a),json=body),201)
    assert clip["id"]==duplicate["id"] and clip["payload"]["clipboard_revision"]==2
    def concurrent_clip(index):
        return check(client.post("/api/v1/messages",headers=headers(a),json={"target_device_id":b["device_id"],"type":"clipboard","client_message_id":str(uuid.uuid4()),"payload":{"content":"concurrent clipboard "+str(index)}}),201)
    with ThreadPoolExecutor(max_workers=6) as pool:messages=list(pool.map(concurrent_clip,range(6)))
    assert sorted(m["payload"]["clipboard_revision"] for m in messages)==list(range(3,9))
    assert check(client.get("/api/v1/clipboard/latest",headers=headers(b)))["payload"]["clipboard_revision"]==8
    shared={"target_device_id":b["device_id"],"type":"clipboard","client_message_id":str(uuid.uuid4()),"payload":{"content":"same concurrent operation"}}
    with ThreadPoolExecutor(max_workers=2) as pool:duplicates=list(pool.map(lambda _:check(client.post("/api/v1/messages",headers=headers(a),json=shared),201),range(2)))
    assert duplicates[0]["id"]==duplicates[1]["id"] and all(m["payload"]["clipboard_revision"]==9 for m in duplicates)
    print("PASS: clipboard latest snapshot, whitespace, atomic concurrent revisions and retry idempotence")
    check(client.delete("/api/v1/devices/"+b["device_id"],headers=headers(a)),204)
    check(client.get("/api/v1/devices",headers=headers(b)),401)
    check(client.post("/api/v1/auth/refresh",json={"refresh_token":b["refresh_token"]}),401)
    print("PASS: device revoke invalidates access and refresh")
finally:
    client.close()
    # Delete only the test-created accounts and their rows, never touch user data.
    settings=Settings();engine=create_engine(settings.database_url)
    with DB(engine) as db:
        for user_id in user_ids:
            device_ids=select(Device.id).where(Device.user_id==user_id)
            message_ids=select(Message.id).where(Message.user_id==user_id)
            file_rows=list(db.scalars(select(File).where(File.user_id==user_id)))
            for f in file_rows:(settings.file_storage_path/f.storage_name).unlink(missing_ok=True)
            db.execute(delete(Transfer).where(Transfer.sender_device_id.in_(device_ids)))
            db.execute(delete(Receipt).where(Receipt.message_id.in_(message_ids)))
            db.execute(delete(Message).where(Message.user_id==user_id))
            db.execute(delete(Clipboard).where(Clipboard.user_id==user_id))
            db.execute(delete(File).where(File.user_id==user_id))
            db.execute(delete(Session).where(Session.user_id==user_id))
            db.execute(delete(Device).where(Device.user_id==user_id))
            db.execute(delete(User).where(User.id==user_id))
        db.commit()
    engine.dispose()
