from fastapi import Request, Depends
from .security import authenticate, fail

def get_db(request:Request):
    with request.app.state.factory() as db:
        yield db

def principal(request:Request,db=Depends(get_db)):
    header=request.headers.get("authorization","")
    if not header.startswith("Bearer "):fail(401,"AUTH_REQUIRED","Bearer token required")
    return authenticate(header[7:],db,request.app.state.settings)
