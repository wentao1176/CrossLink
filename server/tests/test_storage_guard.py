import shutil
import pytest
from test_api import client,login,auth

def test_low_space_rejects_upload_and_leaves_no_file(client,monkeypatch):
 token=login(client)
 monkeypatch.setattr(shutil,'disk_usage',lambda _:shutil._ntuple_diskusage(10**10,10**10,2*1024**3-1))
 response=client.post('/api/v1/files/upload',headers=auth(token),files={'file':('hello.txt',b'hello','text/plain')})
 assert response.status_code==507
 assert response.json()['code']=='STORAGE_LOW'
 assert list(client.app.state.settings.file_storage_path.iterdir())==[]

def test_concurrent_reservation_cannot_spend_the_same_free_bytes():
 from app.storage_budget import StorageBudget,StorageLow
 budget=StorageBudget('/unused',500,free_bytes=lambda:1000)
 first=budget.reserve(400)
 with pytest.raises(StorageLow):budget.reserve(101)
 first.release()
 second=budget.reserve(500);second.release()

def test_written_bytes_are_not_counted_twice_and_release_restores_capacity():
 from app.storage_budget import StorageBudget,StorageLow
 free=[1000];budget=StorageBudget('/unused',500,free_bytes=lambda:free[0])
 first=budget.reserve(400)
 free[0]-=100;first.consumed(100)
 with pytest.raises(StorageLow):budget.reserve(101)
 second=budget.reserve(100);second.release();first.release()
 third=budget.reserve(400);third.release()

def test_space_drop_during_upload_cleans_its_partial(client,monkeypatch):
 token=login(client);calls=[0]
 def space(_):
  calls[0]+=1
  free=10**10 if calls[0]==1 else 2*1024**3-1
  return shutil._ntuple_diskusage(10**10,0,free)
 monkeypatch.setattr(shutil,'disk_usage',space)
 response=client.post('/api/v1/files/upload',headers=auth(token),files={'file':('hello.txt',b'hello','text/plain')})
 assert response.status_code==507
 assert list(client.app.state.settings.file_storage_path.iterdir())==[]
 assert client.get('/api/v1/files',headers=auth(token)).json()==[]
