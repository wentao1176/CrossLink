import asyncio
import logging
import time
from collections import defaultdict,deque
from contextlib import asynccontextmanager,suppress
from uuid import uuid4
from fastapi import FastAPI,Request,HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import create_engine,text
from sqlalchemy.orm import sessionmaker
from starlette.exceptions import HTTPException as StarletteHTTPException
from .config import Settings
from .models import Base
from .realtime import Hub,websocket_handler
from . import accounts,messages,files
logger=logging.getLogger("crosslink")
logging.basicConfig(level=logging.INFO,format="%(asctime)s %(levelname)s %(message)s")
class BodyLimit:
    def __init__(self,app,limit):self.app=app;self.limit=limit
    async def __call__(self,scope,receive,send):
        if scope["type"]!="http":return await self.app(scope,receive,send)
        maximum=self.limit+1024*1024 if scope.get("path")=="/api/v1/files/upload" else 256*1024
        headers=dict(scope.get("headers",[]))
        try:length=int(headers.get(b"content-length",b"0"))
        except ValueError:length=maximum+1
        if length>maximum:
            return await JSONResponse({"code":"BODY_TOO_LARGE","message":"Request body exceeds limit","details":{}},status_code=413)(scope,receive,send)
        received=0
        async def bounded():
            nonlocal received
            packet=await receive();received+=len(packet.get("body",b""))
            if received>maximum:raise HTTPException(413,detail={"code":"BODY_TOO_LARGE","message":"Request body exceeds limit","details":{}})
            return packet
        await self.app(scope,bounded,send)

def create_app(**overrides):
    settings=Settings(**overrides)
    settings.file_storage_path.mkdir(parents=True,exist_ok=True)
    options={"check_same_thread":False} if settings.database_url.startswith("sqlite") else {}
    engine=create_engine(settings.database_url,connect_args=options,pool_pre_ping=True)
    factory=sessionmaker(engine,expire_on_commit=False)
    hub=Hub()
    async def maintenance():
        while True:
            await asyncio.sleep(3600)
            try:await asyncio.to_thread(files.cleanup,factory,settings)
            except Exception:logger.exception("Storage cleanup failed")
    @asynccontextmanager
    async def lifespan(app):
        Base.metadata.create_all(engine)
        await asyncio.to_thread(files.cleanup,factory,settings)
        task=asyncio.create_task(maintenance())
        yield
        task.cancel()
        with suppress(asyncio.CancelledError):await task
        await hub.shutdown();engine.dispose()
    app=FastAPI(title="CrossLink",version="0.1.0",lifespan=lifespan)
    app.state.settings=settings;app.state.factory=factory;app.state.hub=hub
    app.add_middleware(BodyLimit,limit=settings.max_file_size)
    attempts=defaultdict(deque)
    @app.middleware("http")
    async def request_log(request:Request,call_next):
        request_id=str(uuid4());started=time.monotonic()
        if request.url.path in {"/api/v1/auth/login","/api/v1/auth/register","/api/v1/auth/refresh"} and settings.app_env!="test":
            key=(request.client.host,request.url.path);queue=attempts[key];clock=time.monotonic()
            while queue and queue[0]<clock-60:queue.popleft()
            if len(queue)>=20:return JSONResponse({"code":"RATE_LIMITED","message":"Too many attempts; retry in a minute","details":{}},status_code=429,headers={"Retry-After":"60"})
            queue.append(clock)
            if len(attempts)>1000:
                for k in list(attempts):
                    if not attempts[k] or attempts[k][-1]<clock-60:attempts.pop(k,None)
        response=await call_next(request)
        response.headers["X-Request-ID"]=request_id
        response.headers["X-Content-Type-Options"]="nosniff"
        logger.info("request_id=%s method=%s endpoint=%s status=%s duration_ms=%.1f",request_id,request.method,request.url.path,response.status_code,(time.monotonic()-started)*1000)
        return response
    @app.exception_handler(StarletteHTTPException)
    async def http_error(request,exc):
        detail=exc.detail if isinstance(exc.detail,dict) and "code" in exc.detail else {"code":"HTTP_ERROR","message":str(exc.detail),"details":{}}
        return JSONResponse(detail,status_code=exc.status_code)
    @app.exception_handler(RequestValidationError)
    async def validation_error(request,exc):
        return JSONResponse({"code":"VALIDATION_ERROR","message":"Invalid request data","details":{"fields":[{"location":list(e["loc"]),"message":e["msg"]} for e in exc.errors()]}},status_code=422)
    @app.get("/health")
    def health():
        with engine.connect() as c:c.execute(text("SELECT 1"))
        return {"status":"ok"}
    for router in [accounts.router,messages.router,files.router]:app.include_router(router)
    app.add_api_websocket_route("/ws",websocket_handler)
    if settings.web_dist_path.is_dir():app.mount("/",StaticFiles(directory=settings.web_dist_path,html=True),name="client")
    return app
