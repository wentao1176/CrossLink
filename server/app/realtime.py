import asyncio
import json
import logging
from dataclasses import dataclass,field
from fastapi import WebSocket,WebSocketDisconnect,HTTPException
from sqlalchemy import select
from .models import Message,Receipt,Device,now,uid
from .security import authenticate
from .messages import event_for,view,acknowledge
logger=logging.getLogger("crosslink")
def envelope(event,data):return {"event":event,"event_id":uid(),"timestamp":now(),"data":data}
@dataclass(eq=False)
class Connection:
    ws: WebSocket
    user_id:str
    device_id:str
    session_id:str
    lock:asyncio.Lock=field(default_factory=asyncio.Lock)
    closed:bool=False
    async def emit(self,data):
        if self.closed:return
        async with self.lock:await asyncio.wait_for(self.ws.send_json(data),5)
class Hub:
    def __init__(self):self.connections={}
    def online(self,device_id):return any(not c.closed for c in self.connections.get(device_id,set()))
    async def send(self,device_id,event,data):
        for c in list(self.connections.get(device_id,set())):
            try:await c.emit(envelope(event,data))
            except (RuntimeError,WebSocketDisconnect,TimeoutError,OSError):await self.close(c)
    async def broadcast(self,user_id,event,data,exclude=None):
        for device_id,items in list(self.connections.items()):
            if device_id!=exclude and any(c.user_id==user_id for c in items):await self.send(device_id,event,data)
    async def close(self,c):
        c.closed=True
        self.connections.get(c.device_id,set()).discard(c)
        try:await c.ws.close(code=4001)
        except (RuntimeError,WebSocketDisconnect):pass
    async def close_device(self,device_id):
        for c in list(self.connections.get(device_id,set())):await self.close(c)
    async def close_session(self,session_id):
        for items in list(self.connections.values()):
            for c in list(items):
                if c.session_id==session_id:await self.close(c)
    async def shutdown(self):
        for device_id in list(self.connections):await self.close_device(device_id)

async def websocket_handler(ws:WebSocket):
    await ws.accept()
    app=ws.app;conn=None;token=None
    try:
        auth=await asyncio.wait_for(ws.receive_json(),10)
        if not isinstance(auth,dict) or auth.get("type")!="auth" or not isinstance(auth.get("token"),str):
            await ws.close(code=4001);return
        token=auth["token"]
        with app.state.factory() as db:
            p=authenticate(token,db,app.state.settings)
            device_id=p.device.id;user_id=p.user.id;expires=p.expires_at
            conn=Connection(ws,user_id,device_id,p.session.id)
            was_online=app.state.hub.online(device_id)
            app.state.hub.connections.setdefault(device_id,set()).add(conn)
            p.device.last_seen=now();db.commit()
            await conn.emit({"type":"auth_ok","device_id":device_id})
            if not was_online:await app.state.hub.broadcast(user_id,"device.online",{"device_id":device_id,"device_name":p.device.device_name},exclude=device_id)
            messages=list(db.scalars(select(Message).join(Receipt,Message.id==Receipt.message_id).where(Receipt.device_id==device_id,Receipt.status=="pending").order_by(Message.created_at,Message.id).limit(500)))
            for m in messages:await conn.emit(envelope(event_for(m),view(db,m,device_id)))
        while not conn.closed:
            timeout=min(app.state.settings.heartbeat_timeout,max(0,expires-now()))
            if timeout<=0:await ws.close(code=4001);break
            data=await asyncio.wait_for(ws.receive_json(),timeout)
            if not isinstance(data,dict):await ws.close(code=4002);break
            with app.state.factory() as db:
                p=authenticate(token,db,app.state.settings)
                p.device.last_seen=now();db.commit()
                if data.get("type")=="ping":await conn.emit({"type":"pong"})
                elif data.get("type") in {"ack","read"}:
                    try:
                        result=acknowledge(db,p,str(data.get("message_id","")),data["type"]=="read")
                        await conn.emit(envelope("message.ack",result))
                    except HTTPException as e:await conn.emit(envelope("error",e.detail))
                else:await conn.emit(envelope("error",{"code":"INVALID_EVENT","message":"Use ping, ack or read"}))
    except (TimeoutError,HTTPException):
        try:await ws.close(code=4001)
        except RuntimeError:pass
    except (WebSocketDisconnect,RuntimeError,OSError):pass
    except (ValueError,TypeError,json.JSONDecodeError):
        try:await ws.close(code=4002)
        except RuntimeError:pass
    finally:
        if conn:
            conn.closed=True
            app.state.hub.connections.get(conn.device_id,set()).discard(conn)
            if not app.state.hub.connections.get(conn.device_id):app.state.hub.connections.pop(conn.device_id,None)
            with app.state.factory() as db:
                d=db.get(Device,conn.device_id)
                if d:d.last_seen=now();db.commit()
            if not app.state.hub.online(conn.device_id):await app.state.hub.broadcast(conn.user_id,"device.offline",{"device_id":conn.device_id},exclude=conn.device_id)
