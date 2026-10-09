import hashlib
from uuid import UUID
from urllib.parse import urlparse
from fastapi import APIRouter,Depends,Request,Query
from sqlalchemy import select,or_,and_
from sqlalchemy.exc import IntegrityError
from .models import Message,Receipt,Device,Clipboard,File,Transfer,now
from .schemas import SendMessage
from .security import fail
from .dependencies import get_db,principal
router=APIRouter(prefix="/api/v1")
EVENTS={"clipboard":"clipboard.updated","file":"file.created","image":"file.created","notification":"notification.created"}
def event_for(message):return EVENTS.get(message.message_type,"message.created")
def view(db,m,device_id):
    receipt=db.scalar(select(Receipt).where(Receipt.message_id==m.id,Receipt.device_id==device_id))
    status=receipt.status if receipt else "sent"
    if not receipt and m.sender_device_id==device_id:
        states=list(db.scalars(select(Receipt.status).where(Receipt.message_id==m.id)))
        if states:status="read" if all(s=="read" for s in states) else "delivered" if all(s!="pending" for s in states) else "pending"
    return {"id":m.id,"message_id":m.id,"sender_device_id":m.sender_device_id,"target_device_id":m.target_device_id,"type":m.message_type,"payload":m.payload,"status":status,"created_at":m.created_at}
def validate_payload(db,p,body):
    payload=body.payload
    if body.type in {"file","image"}:
        file_id=payload.get("file_id")
        if not isinstance(file_id,str):fail(422,"INVALID_PAYLOAD","file_id required")
        f=db.get(File,file_id)
        if not f or f.user_id!=p.user.id:fail(404,"FILE_NOT_FOUND","File not found")
        if f.expires_at<=now():fail(410,"FILE_EXPIRED","File expired")
        return {"file_id":f.id,"name":f.original_name,"size":f.size,"mime_type":f.mime_type,"sha256":f.sha256,"expires_at":f.expires_at}
    content=payload.get("content")
    if not isinstance(content,str) or not content.strip() or len(content.encode())>102400:fail(422,"INVALID_PAYLOAD","Content must contain 1–102400 UTF-8 bytes")
    result={"content":content}
    if body.type=="url":
        url=urlparse(content)
        if url.scheme not in {"http","https"} or not url.hostname:fail(422,"INVALID_URL","Only HTTP/HTTPS URLs are allowed")
    if body.type=="notification":
        title=payload.get("title","CrossLink")
        if not isinstance(title,str) or not title.strip() or len(title)>200:fail(422,"INVALID_PAYLOAD","Invalid notification title")
        result["title"]=title
    if body.type=="clipboard":
        result.update(content_type="text",content_hash=hashlib.sha256(content.encode()).hexdigest(),origin_device_id=p.device.id)
    return result

def create_message(db,p,body,settings):
    payload=validate_payload(db,p,body)
    if body.target_device_id:
        d=db.get(Device,body.target_device_id)
        if not d or d.user_id!=p.user.id or d.revoked:fail(404,"DEVICE_NOT_FOUND","Target device not found")
        if d.id==p.device.id:fail(422,"INVALID_TARGET","Choose another device")
        recipients=[d.id]
    else:
        recipients=list(db.scalars(select(Device.id).where(Device.user_id==p.user.id,Device.revoked==False,Device.id!=p.device.id)))
    if body.client_message_id:
        existing=db.scalar(select(Message).where(Message.sender_device_id==p.device.id,Message.client_message_id==body.client_message_id))
        if existing:
            if existing.target_device_id!=body.target_device_id or existing.message_type!=body.type or existing.payload!=payload:fail(409,"IDEMPOTENCY_CONFLICT","Message key already used for a different payload")
            return existing,[],False
    m=Message(user_id=p.user.id,sender_device_id=p.device.id,target_device_id=body.target_device_id,message_type=body.type,payload=payload,client_message_id=body.client_message_id)
    db.add(m);db.flush()
    for device_id in recipients:
        db.add(Receipt(message_id=m.id,device_id=device_id))
        if body.type in {"file","image"}:db.add(Transfer(message_id=m.id,file_id=payload["file_id"],sender_device_id=p.device.id,target_device_id=device_id))
    if body.type=="clipboard":db.add(Clipboard(user_id=p.user.id,device_id=p.device.id,content=payload["content"],content_hash=payload["content_hash"],expires_at=now()+settings.file_retention_seconds))
    db.commit()
    return m,recipients,True
async def push_message(app,db,m,recipients):
    for device_id in recipients:await app.state.hub.send(device_id,event_for(m),view(db,m,device_id))
async def publish_receipt(app,db,message_id,recipient_device_id):
    message=db.get(Message,message_id)
    receipt=db.scalar(select(Receipt).where(Receipt.message_id==message_id,Receipt.device_id==recipient_device_id))
    if message is not None and receipt is not None:
        await app.state.hub.send(message.sender_device_id,"message.receipt.updated",{"message_id":message.id,"recipient_device_id":recipient_device_id,"recipient_status":receipt.status,"status":view(db,message,message.sender_device_id)["status"]})
def acknowledge(db,p,message_id,read=False):
    row=db.scalar(select(Receipt).join(Message,Receipt.message_id==Message.id).where(Receipt.message_id==message_id,Receipt.device_id==p.device.id,Message.user_id==p.user.id).with_for_update())
    if not row:fail(404,"MESSAGE_NOT_FOUND","Recipient message not found")
    if row.status=="pending":row.status="delivered";row.delivered_at=now()
    if read:row.status="read";row.read_at=row.read_at or now()
    db.commit()
    return {"message_id":message_id,"status":row.status}
@router.post("/messages",status_code=201)
async def send(body:SendMessage,request:Request,p=Depends(principal),db=Depends(get_db)):
    try:m,recipients,_=create_message(db,p,body,request.app.state.settings)
    except IntegrityError:
        db.rollback()
        if not body.client_message_id:raise
        m,recipients,_=create_message(db,p,body,request.app.state.settings)
    await push_message(request.app,db,m,recipients)
    return view(db,m,p.device.id)
@router.get("/messages/pending")
def pending(p=Depends(principal),db=Depends(get_db),limit:int=Query(100,ge=1,le=500)):
    rows=db.scalars(select(Message).join(Receipt,Message.id==Receipt.message_id).where(Receipt.device_id==p.device.id,Receipt.status=="pending",Message.user_id==p.user.id).order_by(Message.created_at,Message.id).limit(limit))
    return [view(db,m,p.device.id) for m in rows]
@router.get("/messages")
def history(p=Depends(principal),db=Depends(get_db),limit:int=Query(100,ge=1,le=500),before:int|None=None,before_id:UUID|None=Query(default=None)):
    ids=select(Receipt.message_id).where(Receipt.device_id==p.device.id)
    query=select(Message).where(Message.user_id==p.user.id,or_(Message.sender_device_id==p.device.id,Message.id.in_(ids)))
    if before_id is not None and before is None:fail(422,"INVALID_CURSOR","before is required with before_id")
    if before is not None:
        boundary=Message.created_at<before
        if before_id is not None:boundary=or_(boundary,and_(Message.created_at==before,Message.id<str(before_id)))
        query=query.where(boundary)
    return [view(db,m,p.device.id) for m in db.scalars(query.order_by(Message.created_at.desc(),Message.id.desc()).limit(limit))]
@router.post("/messages/{message_id}/ack")
async def ack(message_id:str,request:Request,p=Depends(principal),db=Depends(get_db)):
    result=acknowledge(db,p,message_id)
    await publish_receipt(request.app,db,message_id,p.device.id)
    return result
@router.post("/messages/{message_id}/read")
async def read(message_id:str,request:Request,p=Depends(principal),db=Depends(get_db)):
    result=acknowledge(db,p,message_id,True)
    await publish_receipt(request.app,db,message_id,p.device.id)
    return result
@router.get("/clipboard")
def clipboard(p=Depends(principal),db=Depends(get_db),limit:int=Query(50,ge=1,le=100)):
    return [{"id":c.id,"device_id":c.device_id,"content":c.content,"content_hash":c.content_hash,"created_at":c.created_at,"expires_at":c.expires_at} for c in db.scalars(select(Clipboard).where(Clipboard.user_id==p.user.id,Clipboard.expires_at>now()).order_by(Clipboard.created_at.desc()).limit(limit))]
