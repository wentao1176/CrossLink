#!/usr/bin/env python3
import hashlib,json,os,signal,subprocess,sys,tarfile,time,uuid,shutil
from pathlib import Path
from sqlalchemy import create_engine,text,inspect
from sqlalchemy.engine import make_url
root=Path('/home/CrossLink');sys.path.insert(0,str(root/'server'))
from app.config import Settings
settings=Settings();url=make_url(settings.database_url)
assert url.drivername.startswith('postgresql')
backup_root=root/'backups';backup_root.mkdir(exist_ok=True);backup_root.chmod(0o700)
backup=backup_root/(time.strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:8]);backup.mkdir(exist_ok=False);backup.chmod(0o700)
if shutil.disk_usage(root).free < 3*1024**3:
 backup.rmdir();raise SystemExit('Insufficient backup headroom')
env=dict(os.environ);env['PGPASSWORD']=url.password or ''
connection=['-h',url.host or '127.0.0.1','-p',str(url.port or 5432),'-U',url.username or 'crosslink']
pid=int(subprocess.check_output(['systemctl','show','crosslink-api','--property=MainPID','--value'],text=True).strip())
assert pid>0 and Path(f'/proc/{pid}/cwd').resolve()==root/'server'
engine=create_engine(settings.database_url)
started=time.monotonic();stopped=False
try:
 os.kill(pid,signal.SIGSTOP);stopped=True
 with engine.connect() as db:
  files=[dict(row) for row in db.execute(text('SELECT storage_name,size,sha256 FROM files WHERE expires_at > :cutoff'),{'cutoff':int(time.time())}).mappings()]
  tables=inspect(db).get_table_names(schema='public')
  quote=engine.dialect.identifier_preparer.quote
  counts={table:db.execute(text(f'SELECT count(*) FROM {quote(table)}')).scalar_one() for table in tables}
 result=subprocess.run(['/usr/bin/pg_dump',*connection,'-d',url.database,'--format=custom','--no-owner','--no-acl','--schema=public','--file='+str(backup/'database.dump')],env=env,capture_output=True)
 (backup/'dump.log').write_bytes(result.stderr)
 if result.returncode:raise RuntimeError('Database backup failed; protected log retained')
 with tarfile.open(backup/'files.tar.gz','w:gz') as output:
  for entry in files:
   name=entry['storage_name'];assert str(uuid.UUID(name))==name
   file=settings.file_storage_path/name
   assert file.is_file() and not file.is_symlink()
   actual=hashlib.file_digest(file.open('rb'),'sha256').hexdigest()
   assert file.stat().st_size==entry['size'] and actual==entry['sha256'],'Stored file integrity mismatch'
   output.add(file,arcname=name,recursive=False)
 with tarfile.open(backup/'private-material.tar.gz','w:gz') as output:
  for name in ('.env','.tools/tls/ca.key','.tools/tls/ca.pem','.tools/signing/crosslink-release.jks','.tools/signing/key.properties'):
   output.add(root/name,arcname=name,recursive=False)
finally:
 if stopped:os.kill(pid,signal.SIGCONT)
 engine.dispose()
 if not any(backup.iterdir()):backup.rmdir()
freeze_seconds=round(time.monotonic()-started,3)
metadata={'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'freeze_seconds':freeze_seconds,'counts':counts,'files':files,'archives':{}}
for name in ('database.dump','files.tar.gz','private-material.tar.gz'):
 file=backup/name
 metadata['archives'][name]={'bytes':file.stat().st_size,'sha256':hashlib.file_digest(file.open('rb'),'sha256').hexdigest()}
(backup/'manifest.json').write_text(json.dumps(metadata,indent=2))
for path in backup.iterdir():path.chmod(0o600)
print(json.dumps({'backup':str(backup),'freeze_seconds':freeze_seconds,'counts':counts,'unexpired_files':len(files)}))
