import hashlib
import secrets
import jwt
from dataclasses import dataclass
from fastapi import HTTPException
from pwdlib import PasswordHash
from sqlalchemy import select
from .models import User, Device, Session, now
passwords=PasswordHash.recommended()
DUMMY_HASH=passwords.hash("dummy-password-not-used")
def digest(value): return hashlib.sha256(value.encode()).hexdigest()
def fail(status,code,message): raise HTTPException(status_code=status,detail={"code":code,"message":message,"details":{}})
@dataclass
class Principal:
    user: User
    device: Device
    session: Session
    expires_at: int

def authenticate(token,db,settings):
    try:
        claims=jwt.decode(token,settings.jwt_secret,algorithms=["HS256"],audience="crosslink",issuer="crosslink",options={"require":["exp","sub","sid","did","iat"]})
        session=db.get(Session,claims["sid"]);device=db.get(Device,claims["did"]);user=db.get(User,claims["sub"])
        if not session or not device or not user or session.revoked or device.revoked or not user.status or session.expires_at<=now() or session.user_id!=user.id or device.user_id!=user.id or session.device_id!=device.id:
            fail(401,"INVALID_SESSION","Session expired or revoked")
        return Principal(user,device,session,claims["exp"])
    except jwt.PyJWTError:
        fail(401,"INVALID_TOKEN","Invalid or expired access token")

def issue(db,user,device,settings,session=None):
    refresh=secrets.token_urlsafe(48)
    if session is None:
        session=Session(user_id=user.id,device_id=device.id,refresh_token_hash=digest(refresh),expires_at=now()+settings.refresh_token_expire)
        db.add(session)
    else:
        session.refresh_token_hash=digest(refresh)
        session.expires_at=now()+settings.refresh_token_expire
    db.commit()
    access=jwt.encode({"sub":user.id,"did":device.id,"sid":session.id,"iat":now(),"exp":now()+settings.access_token_expire,"aud":"crosslink","iss":"crosslink"},settings.jwt_secret,algorithm="HS256")
    return {"access_token":access,"refresh_token":refresh,"expires_in":settings.access_token_expire,"token_type":"bearer","device_id":device.id}
