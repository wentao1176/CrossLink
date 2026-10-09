#!/usr/bin/env python3
import argparse
import hashlib,json,os,subprocess,sys,tarfile,time,uuid
from pathlib import Path
from sqlalchemy import create_engine,text,inspect
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session as DbSession
from pwdlib import PasswordHash
root=Path('/home/CrossLink');sys.path.insert(0,str(root/'server'))
from app.config import Settings
from app.models import Base,User,Device,File,Message,Receipt,Transfer
settings=Settings();url=make_url(settings.database_url)
env=dict(os.environ);env['PGPASSWORD']=url.password or ''
connection=['-h',url.host or '127.0.0.1','-p',str(url.port or 5432),'-U',url.username or 'crosslink']
workspace=root/'.tools/restore-check'/uuid.uuid4().hex;workspace.mkdir(parents=True);workspace.chmod(0o700)
databases=[]
def create_database():
 name='crosslink_restore_'+uuid.uuid4().hex[:16]
 subprocess.run(['runuser','-u','postgres','--','/usr/bin/createdb','-h',str(root/'data/pgsocket'),'-p',str(url.port),'-O',url.username,name],check=True,capture_output=True)
 databases.append(name);return name

def engine_for(name):return create_engine(url.set(database=name))
def count(engine):
 with engine.connect() as db:
  quote=engine.dialect.identifier_preparer.quote
  return {table:db.execute(text(f'SELECT count(*) FROM {quote(table)}')).scalar_one() for table in inspect(db).get_table_names(schema='public')}
def restore(dump,name):
 assert name in databases and name.startswith('crosslink_restore_')
 subprocess.run(['runuser','-u','postgres','--','/usr/bin/psql','-h',str(root/'data/pgsocket'),'-p',str(url.port),'-d',name,'--no-psqlrc','--command','DROP SCHEMA public CASCADE'],check=True,capture_output=True)
 result=subprocess.run(['/usr/bin/pg_restore',*connection,'-d',name,'--no-owner','--no-acl',str(dump)],env=env,capture_output=True)
 (workspace/(name+'.log')).write_bytes(result.stderr)
 assert result.returncode==0,'Restore failed; protected log retained'
parser=argparse.ArgumentParser();parser.add_argument('backup',type=Path);args=parser.parse_args()
backup=args.backup.resolve();assert backup.is_relative_to((root/'backups').resolve()) and backup!=root/'backups'
started=time.monotonic()
try:
 metadata=json.loads((backup/'manifest.json').read_text())
 for name,expected in metadata['archives'].items():
  with (backup/name).open('rb') as source:actual=hashlib.file_digest(source,'sha256').hexdigest()
  assert actual==expected['sha256']
 destination_platform=workspace/'platform-files';destination_platform.mkdir()
 with tarfile.open(backup/'files.tar.gz') as archive:archive.extractall(destination_platform,filter='data')
 for entry in metadata['files']:
  name=entry['storage_name'];assert str(uuid.UUID(name))==name
  file=destination_platform/name
  with file.open('rb') as source:actual=hashlib.file_digest(source,'sha256').hexdigest()
  assert actual==entry['sha256'] and file.stat().st_size==entry['size']
 name=create_database();restore(backup/'database.dump',name)
 engine=engine_for(name)
 try:assert count(engine)==metadata['counts']
 finally:engine.dispose()
 source_db=create_database();engine=engine_for(source_db);Base.metadata.create_all(engine)
 directory=workspace/'source-files';directory.mkdir()
 data=bytes(i%251 for i in range(65536))*16;digest=hashlib.sha256(data).hexdigest();storage=str(uuid.uuid4())
 (directory/storage).write_bytes(data)
 with DbSession(engine) as db:
  user=User(username='restore_fixture',email='restore@example.invalid',password_hash=PasswordHash.recommended().hash('Fixture-only-password-483'))
  db.add(user);db.flush()
  sender=Device(user_id=user.id,device_uuid=str(uuid.uuid4()),device_name='PC fixture',platform='windows')
  target=Device(user_id=user.id,device_uuid=str(uuid.uuid4()),device_name='Phone fixture',platform='android')
  db.add_all([sender,target]);db.flush()
  file=File(user_id=user.id,sender_device_id=sender.id,original_name='验收 文件.bin',storage_name=storage,mime_type='application/octet-stream',size=len(data),sha256=digest,expires_at=int(time.time())+86400)
  db.add(file);db.flush()
  message=Message(user_id=user.id,sender_device_id=sender.id,target_device_id=target.id,client_message_id=str(uuid.uuid4()),message_type='file',payload={'file_id':file.id,'name':file.original_name,'size':file.size,'sha256':digest})
  db.add(message);db.flush()
  db.add_all([Receipt(message_id=message.id,device_id=target.id,status='delivered'),Transfer(message_id=message.id,file_id=file.id,sender_device_id=sender.id,target_device_id=target.id)])
  db.commit()
 expected_counts=count(engine);engine.dispose()
 dump=workspace/'fixture.dump'
 subprocess.run(['/usr/bin/pg_dump',*connection,'-d',source_db,'--format=custom','--schema=public','--no-owner','--no-acl','--file='+str(dump)],env=env,check=True,capture_output=True)
 with tarfile.open(workspace/'fixture-files.tar.gz','w:gz') as archive:archive.add(directory/storage,arcname=storage,recursive=False)
 restored=create_database();restore(dump,restored);engine=engine_for(restored)
 destination=workspace/'restored-files';destination.mkdir()
 with tarfile.open(workspace/'fixture-files.tar.gz') as archive:archive.extractall(destination,filter='data')
 try:
  assert count(engine)==expected_counts
  with engine.connect() as db:
   row=db.execute(text('SELECT original_name,size,sha256,storage_name FROM files')).mappings().one()
   assert row['original_name']=='验收 文件.bin' and row['size']==1048576
   with (destination/row['storage_name']).open('rb') as source:actual=hashlib.file_digest(source,'sha256').hexdigest()
   assert actual==row['sha256']==digest
  report={'restored_platform_counts':metadata['counts'],'fixture_counts':expected_counts,'file_bytes':1048576,'file_sha256':digest,'seconds':round(time.monotonic()-started,3),'live_database_overwritten':False}
  (workspace/'report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))
 finally:engine.dispose()
finally:
 for name in reversed(databases):subprocess.run(['runuser','-u','postgres','--','/usr/bin/dropdb','-h',str(root/'data/pgsocket'),'-p',str(url.port),'--if-exists',name],check=True,capture_output=True)
 for path in workspace.iterdir():
  if path.is_file():path.chmod(0o600)
