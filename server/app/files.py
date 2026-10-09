import hashlib
import re
import stat
import threading
from uuid import UUID
from pathlib import Path
from fastapi import APIRouter,Depends,Request,UploadFile,File as Upload,Form,Query
from fastapi.responses import FileResponse
from sqlalchemy import select,or_,update
from .models import File,Transfer,Clipboard,now,uid
from .schemas import SendMessage,TransferUpdate
from .messages import create_message,push_message
from .dependencies import get_db,principal
from .security import fail
router=APIRouter(prefix="/api/v1")
_storage_lock=threading.RLock()
_active_uploads:set[str]=set()
def file_view(f):return {"id":f.id,"name":f.original_name,"size":f.size,"mime_type":f.mime_type,"sha256":f.sha256,"created_at":f.created_at,"expires_at":f.expires_at}
def safe_name(name):
    name=(name or "file").replace("\\","/").split("/")[-1]
    name=re.sub(r"[\x00-\x1f\x7f]","_",name).strip(" .")
    return name[:200] or "file"
@router.post("/files/upload",status_code=201)
async def upload(request:Request,file:UploadFile=Upload(...),target_device_id:str|None=Form(None),p=Depends(principal),db=Depends(get_db)):
    settings=request.app.state.settings
    file_id=uid();path=settings.file_storage_path/file_id;part=settings.file_storage_path/(file_id+".part")
    size=0;hasher=hashlib.sha256();committed=False
    with _storage_lock:_active_uploads.add(file_id)
    try:
        with part.open("xb") as out:
            while chunk:=await file.read(1024*1024):
                size+=len(chunk)
                if size>settings.max_file_size:fail(413,"FILE_TOO_LARGE","File exceeds configured maximum size")
                hasher.update(chunk);out.write(chunk)
        part.replace(path)
        f=File(id=file_id,user_id=p.user.id,sender_device_id=p.device.id,original_name=safe_name(file.filename),storage_name=file_id,mime_type=(file.content_type or "application/octet-stream")[:255],size=size,sha256=hasher.hexdigest(),expires_at=now()+settings.file_retention_seconds)
        db.add(f);db.flush()
        body=SendMessage(type="image" if f.mime_type.startswith("image/") else "file",target_device_id=target_device_id or None,payload={"file_id":file_id})
        m,recipients,_=create_message(db,p,body,settings)
        committed=True
        await push_message(request.app,db,m,recipients)
        return {**file_view(f),"message_id":m.id}
    finally:
        try:
            await file.close();part.unlink(missing_ok=True)
            if not committed:path.unlink(missing_ok=True);db.rollback()
        finally:
            with _storage_lock:_active_uploads.discard(file_id)
@router.get("/files")
def files(p=Depends(principal),db=Depends(get_db),limit:int=Query(100,ge=1,le=500)):
    return [file_view(f) for f in db.scalars(select(File).where(File.user_id==p.user.id).order_by(File.created_at.desc()).limit(limit))]
@router.get("/files/{file_id}/download")
def download(file_id:str,request:Request,p=Depends(principal),db=Depends(get_db)):
    f=db.get(File,file_id)
    if not f or f.user_id!=p.user.id:fail(404,"FILE_NOT_FOUND","File not found")
    if f.expires_at<=now():fail(410,"FILE_EXPIRED","File expired")
    path=request.app.state.settings.file_storage_path/f.storage_name
    if not path.is_file():fail(410,"FILE_UNAVAILABLE","File no longer available")
    return FileResponse(path,filename=f.original_name,media_type="application/octet-stream",headers={"X-Content-Type-Options":"nosniff","X-File-SHA256":f.sha256,"Cache-Control":"no-store"})
@router.get("/transfers")
def transfers(p=Depends(principal),db=Depends(get_db),limit:int=Query(100,ge=1,le=500),file_id:str|None=Query(default=None,max_length=36)):
    query=select(Transfer,File).join(File,Transfer.file_id==File.id).where(File.user_id==p.user.id,or_(Transfer.sender_device_id==p.device.id,Transfer.target_device_id==p.device.id))
    if file_id is not None:query=query.where(Transfer.file_id==file_id)
    rows=db.execute(query.order_by(Transfer.created_at.desc()).limit(limit))
    return [{"id":t.id,"message_id":t.message_id,"file_id":t.file_id,"sender_device_id":t.sender_device_id,"target_device_id":t.target_device_id,"status":t.status,"progress":t.progress,"created_at":t.created_at,"completed_at":t.completed_at,"file":file_view(f)} for t,f in rows]
@router.patch("/transfers/{transfer_id}")
def transfer(transfer_id:str,body:TransferUpdate,p=Depends(principal),db=Depends(get_db)):
    t=db.get(Transfer,transfer_id)
    if not t or t.target_device_id!=p.device.id:fail(404,"TRANSFER_NOT_FOUND","Recipient transfer not found")
    f=db.get(File,t.file_id)
    if f.user_id!=p.user.id:fail(404,"TRANSFER_NOT_FOUND","Transfer not found")
    if f.expires_at<=now():fail(410,"FILE_EXPIRED","File expired")
    if t.status=="completed" and body.status!="completed":fail(409,"TRANSFER_COMPLETED","Completed transfer cannot change state")
    t.status=body.status;t.progress=100 if body.status=="completed" else body.progress
    if body.status=="completed":t.completed_at=now()
    db.commit();return {"id":t.id,"status":t.status,"progress":t.progress}
def _regular_stat(path):
    try:
        info=path.lstat()
        return info if stat.S_ISREG(info.st_mode) else None
    except FileNotFoundError:return None

def cleanup(factory,settings):
    cutoff=now()-86400
    with factory() as db:
        for f in db.scalars(select(File).where(File.expires_at<=now())):
            with _storage_lock:
                if f.id in _active_uploads:continue
                path=settings.file_storage_path/f.storage_name
                if _regular_stat(path) is not None:path.unlink(missing_ok=True)
                db.execute(update(Transfer).where(Transfer.file_id==f.id,Transfer.status!="completed").values(status="expired"))
        for c in db.scalars(select(Clipboard).where(Clipboard.expires_at<=now())):db.delete(c)
        db.commit()
        for path in settings.file_storage_path.iterdir():
            partial=path.name.endswith(".part")
            file_id=path.name[:-5] if partial else path.name
            if not partial:
                try:
                    if str(UUID(file_id))!=file_id:continue
                except ValueError:continue
            with _storage_lock:
                if file_id in _active_uploads:continue
                info=_regular_stat(path)
                if info is None or info.st_mtime>=cutoff:continue
                if not partial and db.scalar(select(File.id).where(File.storage_name==file_id)) is not None:continue
                path.unlink(missing_ok=True)
