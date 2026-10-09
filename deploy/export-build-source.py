#!/usr/bin/env python3
import io,json,subprocess,tarfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
if subprocess.check_output(['git','status','--porcelain'],cwd=root).strip():
 raise SystemExit('Commit source changes before exporting')
commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
archive=subprocess.check_output(['git','archive','HEAD'],cwd=root)
target=root/'.tools/windows-source.tar.gz'
metadata=json.dumps({'source_commit':commit,'flutter_commit':'5fc346839b5d0eef006ed8404392afb4dfae428d'}).encode()
with tarfile.open(fileobj=io.BytesIO(archive)) as source,tarfile.open(target,'w:gz') as output:
 for entry in source:
  output.addfile(entry,source.extractfile(entry) if entry.isfile() else None)
 for name,data in [('source.json',metadata)]+[(f'config/client-build-{channel}.json',(root/f'.tools/client-build{suffix}.json').read_bytes()) for channel,suffix in [('production',''),('qa','-qa')]]:
  entry=tarfile.TarInfo(name);entry.size=len(data);entry.mode=0o644;output.addfile(entry,io.BytesIO(data))
print('Committed source exported:',commit,target)
