#!/usr/bin/env python3
from pathlib import Path
import grp, os, subprocess
r=Path('/home/CrossLink');d=r/'.tools/tls';target=r/'deploy/platform_tls/server.pem'
if subprocess.run(['openssl','x509','-checkend',str(90*86400),'-noout','-in',str(target)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode == 0:
    print('Platform certificate remains valid; no change required.')
else:
    temporary=d/'server-renewed.pem'
    subprocess.run(['openssl','x509','-req','-in',str(d/'server.csr'),'-CA',str(d/'ca.pem'),'-CAkey',str(d/'ca.key'),'-CAcreateserial','-days','365','-sha256','-extfile',str(d/'server.ext'),'-out',str(temporary)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    temporary.chmod(0o640);os.chown(temporary,0,grp.getgrnam('crosslink').gr_gid)
    os.replace(temporary,target)
    subprocess.run(['systemctl','reload','crosslink-gateway'],check=True)
    print('Platform certificate renewed and gateway reloaded.')
