from fastapi import APIRouter, Depends, Request, Response
from sqlalchemy import select, or_, update
from sqlalchemy.exc import IntegrityError
from .models import User,Device,Session,now
from .schemas import Register,Login,Refresh,Rename
from .security import passwords,DUMMY_HASH,digest,issue,fail
from .dependencies import get_db,principal
router=APIRouter(prefix="/api/v1")

def device_view(device,hub):
    return {"id":device.id,"device_uuid":device.device_uuid,"name":device.device_name,"device_name":device.device_name,"device_type":device.device_type,"platform":device.platform,"online":hub.online(device.id),"last_seen":device.last_seen,"revoked":device.revoked}
@router.post("/auth/register",status_code=201)
def register(body:Register,db=Depends(get_db)):
    user=User(username=body.username.lower(),email=str(body.email).lower(),password_hash=passwords.hash(body.password))
    db.add(user)
    try:db.commit()
    except IntegrityError:
        db.rollback();fail(409,"ACCOUNT_EXISTS","Username or email already registered")
    return {"id":user.id,"username":user.username,"email":user.email}
@router.post("/auth/login")
async def login(body:Login,request:Request,db=Depends(get_db)):
    user=db.scalar(select(User).where(or_(User.username==body.account.lower(),User.email==body.account.lower())))
    valid=passwords.verify(body.password,user.password_hash if user else DUMMY_HASH)
    if not user or not valid or not user.status:fail(401,"INVALID_CREDENTIALS","Invalid account or password")
    device=db.scalar(select(Device).where(Device.device_uuid==body.device.device_uuid))
    if device and device.user_id!=user.id:fail(409,"DEVICE_CONFLICT","Device already belongs to another account")
    if not device:
        device=Device(user_id=user.id,**body.device.model_dump());db.add(device)
    else:
        for k,v in body.device.model_dump(exclude={"device_uuid","device_name"}).items():setattr(device,k,v)
        device.revoked=False
        db.execute(update(Session).where(Session.device_id==device.id).values(revoked=True))
    device.last_seen=now()
    try:db.commit()
    except IntegrityError:
        db.rollback();fail(409,"DEVICE_CONFLICT","Device registered concurrently; please retry")
    await request.app.state.hub.close_device(device.id)
    return issue(db,user,device,request.app.state.settings)
@router.post("/auth/refresh")
def refresh(body:Refresh,request:Request,db=Depends(get_db)):
    session=db.scalar(select(Session).where(Session.refresh_token_hash==digest(body.refresh_token)).with_for_update())
    if not session or session.revoked or session.expires_at<=now():fail(401,"INVALID_REFRESH","Refresh token invalid, expired or already used")
    user=db.get(User,session.user_id);device=db.get(Device,session.device_id)
    if not user.status or device.revoked:fail(401,"INVALID_SESSION","Device revoked")
    return issue(db,user,device,request.app.state.settings,session)
@router.post("/auth/logout",status_code=204)
async def logout(request:Request,p=Depends(principal),db=Depends(get_db)):
    p.session.revoked=True;db.commit()
    await request.app.state.hub.close_session(p.session.id)
    return Response(status_code=204)
@router.get("/users/me")
def me(p=Depends(principal)):
    return {"id":p.user.id,"username":p.user.username,"email":p.user.email}
@router.get("/devices")
def devices(request:Request,p=Depends(principal),db=Depends(get_db)):
    return [device_view(d,request.app.state.hub) for d in db.scalars(select(Device).where(Device.user_id==p.user.id,Device.revoked==False).order_by(Device.created_at,Device.id))]
@router.patch("/devices/{device_id}")
async def rename(device_id:str,body:Rename,request:Request,p=Depends(principal),db=Depends(get_db)):
    d=db.get(Device,device_id)
    if not d or d.user_id!=p.user.id or d.revoked:fail(404,"DEVICE_NOT_FOUND","Device not found")
    d.device_name=body.device_name;db.commit()
    await request.app.state.hub.broadcast(p.user.id,"device.updated",device_view(d,request.app.state.hub))
    return device_view(d,request.app.state.hub)
@router.delete("/devices/{device_id}",status_code=204)
async def revoke(device_id:str,request:Request,p=Depends(principal),db=Depends(get_db)):
    d=db.get(Device,device_id)
    if not d or d.user_id!=p.user.id or d.revoked:fail(404,"DEVICE_NOT_FOUND","Device not found")
    d.revoked=True;db.execute(update(Session).where(Session.device_id==d.id).values(revoked=True));db.commit()
    await request.app.state.hub.close_device(d.id)
    await request.app.state.hub.broadcast(p.user.id,"device.revoked",{"device_id":d.id})
    return Response(status_code=204)
