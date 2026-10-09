import shutil
import threading
from starlette.responses import JSONResponse

class StorageLow(Exception):
 pass

class StorageBudget:
 def __init__(self,path,minimum_free,free_bytes=None):
  self.path=path;self.minimum_free=minimum_free
  self.free_bytes=free_bytes or (lambda:shutil.disk_usage(path).free)
  self.lock=threading.Lock();self.reserved=0
 def reserve(self,amount):
  amount=max(0,int(amount))
  with self.lock:
   if self.free_bytes()-self.reserved-amount<self.minimum_free:raise StorageLow()
   self.reserved+=amount
  return Reservation(self,amount)

class Reservation:
 def __init__(self,budget,amount):self.budget=budget;self.amount=amount;self.closed=False
 def remaining(self,amount):
  with self.budget.lock:
   if self.closed:return
   assert 0<=amount<=self.amount
   self.budget.reserved-=self.amount-amount;self.amount=amount
 def consumed(self,count):self.remaining(max(0,self.amount-count))
 def ensure_space(self):
  with self.budget.lock:
   if self.budget.free_bytes()-self.budget.reserved<self.budget.minimum_free:raise StorageLow()
 def release(self):
  with self.budget.lock:
   if self.closed:return
   self.budget.reserved-=self.amount;self.amount=0;self.closed=True

class StorageSpace:
 def __init__(self,app,budget,maximum):self.app=app;self.budget=budget;self.maximum=maximum
 async def __call__(self,scope,receive,send):
  if scope['type']!='http' or scope.get('path')!='/api/v1/files/upload':return await self.app(scope,receive,send)
  headers=dict(scope.get('headers',[]))
  try:length=int(headers.get(b'content-length',b'0'))
  except ValueError:length=0
  amount=2*(min(length,self.maximum) if length>0 else self.maximum)
  try:reservation=self.budget.reserve(amount)
  except StorageLow:
   return await JSONResponse({'code':'STORAGE_LOW','message':'平台空间暂时不足，请稍后重试','details':{}},status_code=507)(scope,receive,send)
  scope['crosslink.storage_reservation']=reservation
  try:await self.app(scope,receive,send)
  finally:reservation.release()
