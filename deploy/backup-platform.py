#!/usr/bin/env python3
import hashlib,json,os,signal,subprocess,sys,tarfile,time,uuid,shutil
from pathlib import Path
from sqlalchemy import create_engine,text,inspect
from sqlalchemy.engine import make_url

class BackupSpaceLow(Exception):
 pass

def check_capacity(folder,*,file_bytes,database_bytes,private_bytes,reserve,free_bytes=None):
 free=(free_bytes or (lambda:shutil.disk_usage(folder).free))()
 required=reserve+file_bytes+2*database_bytes+private_bytes+64*1024**2
 if free<required:raise BackupSpaceLow('Insufficient capacity for complete backup and system reserve')
 return required

class GuardedOutput:
 def __init__(self,path,reserve,free_bytes=None):
  self.path=Path(path);self.reserve=reserve;self.free_bytes=free_bytes or (lambda:shutil.disk_usage(self.path.parent).free)
  self.stream=None
 def __enter__(self):self.stream=self.path.open('xb');return self
 def write(self,data):
  if self.free_bytes()-len(data)-65536<self.reserve:raise BackupSpaceLow('Backup stopped to preserve system capacity')
  count=self.stream.write(data);self.stream.flush();return count
 def tell(self):return self.stream.tell()
 def flush(self):return self.stream.flush()
 def __exit__(self,kind,value,tb):
  self.stream.close()
  if kind is not None:self.path.unlink(missing_ok=True)

def main():
 root=Path('/home/CrossLink');sys.path.insert(0,str(root/'server'))
 from app.config import Settings
 settings=Settings();url=make_url(settings.database_url);assert url.drivername.startswith('postgresql')
 backup_root=root/'backups';backup_root.mkdir(exist_ok=True);backup_root.chmod(0o700)
 backup=backup_root/(time.strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:8]);backup.mkdir(exist_ok=False);backup.chmod(0o700)
 private_names=('.env','.tools/tls/ca.key','.tools/tls/ca.pem','.tools/signing/crosslink-release.jks','.tools/signing/key.properties')
 private_bytes=sum((root/name).stat().st_size for name in private_names)
 env=dict(os.environ);env['PGPASSWORD']=url.password or ''
 connection=['-h',url.host or '127.0.0.1','-p',str(url.port or 5432),'-U',url.username or 'crosslink']
 pid=int(subprocess.check_output(['systemctl','show','crosslink-api','--property=MainPID','--value'],text=True).strip())
 assert pid>0 and Path(f'/proc/{pid}/cwd').resolve()==root/'server'
 engine=create_engine(settings.database_url);started=time.monotonic();stopped=False;complete=False
 try:
  os.kill(pid,signal.SIGSTOP);stopped=True
  with engine.connect() as db:
   files=[dict(row) for row in db.execute(text('SELECT storage_name,size,sha256 FROM files WHERE expires_at > :cutoff'),{'cutoff':int(time.time())}).mappings()]
   quote=engine.dialect.identifier_preparer.quote
   counts={table:db.execute(text(f'SELECT count(*) FROM {quote(table)}')).scalar_one() for table in inspect(db).get_table_names(schema='public')}
   database_bytes=db.execute(text('SELECT pg_database_size(current_database())')).scalar_one()
  check_capacity(root,file_bytes=sum(entry['size'] for entry in files),database_bytes=database_bytes,private_bytes=private_bytes,reserve=settings.storage_min_free_bytes)
  with (backup/'dump.log').open('xb') as error_log:
   process=subprocess.Popen(['/usr/bin/pg_dump',*connection,'-d',url.database,'--format=custom','--no-owner','--no-acl','--schema=public'],env=env,stdout=subprocess.PIPE,stderr=error_log)
   try:
    with GuardedOutput(backup/'database.dump',settings.storage_min_free_bytes) as output:
     while chunk:=process.stdout.read(65536):output.write(chunk)
    if process.wait()!=0:raise RuntimeError('Database backup failed')
   finally:
    process.stdout.close()
    if process.poll() is None:process.kill();process.wait()
  with GuardedOutput(backup/'files.tar.gz',settings.storage_min_free_bytes) as output,tarfile.open(fileobj=output,mode='w|gz') as archive:
   for entry in files:
    name=entry['storage_name'];assert str(uuid.UUID(name))==name
    file=settings.file_storage_path/name;assert file.is_file() and not file.is_symlink()
    with file.open('rb') as source:actual=hashlib.file_digest(source,'sha256').hexdigest()
    assert file.stat().st_size==entry['size'] and actual==entry['sha256'],'Stored file integrity mismatch'
    archive.add(file,arcname=name,recursive=False)
  with GuardedOutput(backup/'private-material.tar.gz',settings.storage_min_free_bytes) as output,tarfile.open(fileobj=output,mode='w|gz') as archive:
   for name in private_names:archive.add(root/name,arcname=name,recursive=False)
  complete=True
 finally:
  if stopped:os.kill(pid,signal.SIGCONT)
  engine.dispose()
  if not complete:
   for name in ('database.dump','files.tar.gz','private-material.tar.gz','dump.log','manifest.json'):(backup/name).unlink(missing_ok=True)
   if not any(backup.iterdir()):backup.rmdir()
 freeze_seconds=round(time.monotonic()-started,3)
 metadata={'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'freeze_seconds':freeze_seconds,'counts':counts,'files':files,'archives':{}}
 for name in ('database.dump','files.tar.gz','private-material.tar.gz'):
  file=backup/name
  with file.open('rb') as source:digest=hashlib.file_digest(source,'sha256').hexdigest()
  metadata['archives'][name]={'bytes':file.stat().st_size,'sha256':digest}
 (backup/'manifest.json').write_text(json.dumps(metadata,indent=2))
 for path in backup.iterdir():path.chmod(0o600)
 print(json.dumps({'backup':str(backup),'freeze_seconds':freeze_seconds,'counts':counts,'unexpired_files':len(files)}))

if __name__=='__main__':main()
