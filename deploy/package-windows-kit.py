#!/usr/bin/env python3
"""Package committed source plus public, internal connection configuration; never private keys."""
import io, json, subprocess, zipfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
config=json.loads((root/'.tools/client-build.json').read_text())
assert config['CROSSLINK_API_URL'].startswith('https://')
commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,universal_newlines=True).strip()
source=subprocess.check_output(['git','archive','--format=zip','HEAD'],cwd=root)
destination=root/'artifacts/CrossLink-0.2.0-windows-build-kit.zip'
with zipfile.ZipFile(io.BytesIO(source)) as original, zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED) as output:
 for name in original.namelist():
  assert not name.startswith(('.tools/','data/','logs/','artifacts/','deploy/platform_tls/'))
  assert not name.endswith(('.key','.keystore')) and name != '.env'
  output.writestr(name,original.read(name))
 output.writestr('config/client-build.json',json.dumps(config))
 output.writestr('BUILD_INFO.txt','Source revision: '+commit+'\nVersion: 0.2.0\nWindows C++ and Git required; run deploy/build-windows.ps1.\nThis archive contains source, not an executable.\n')
with zipfile.ZipFile(destination) as archive:
 assert archive.testzip() is None
 assert 'client/assets/platform_ca.pem' in archive.namelist()
 assert 'deploy/build-windows.ps1' in archive.namelist()
print(destination, destination.stat().st_size, 'bytes; source commit',commit)
