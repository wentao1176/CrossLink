#!/usr/bin/env python3
"""Build only this project's APK; cap resident memory on the small ECS (cgroup v1)."""
import argparse, hashlib, json, re, shutil
import os
from pathlib import Path
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[1]
assert root == Path('/home/CrossLink'), 'Run the SSH build from /home/CrossLink'
parser=argparse.ArgumentParser()
parser.add_argument('--channel',choices=['qa','production'],default='production')
parser.add_argument('--mode',choices=['debug','release'],default='release')
parser.add_argument('--build-number',type=int)
args=parser.parse_args()
configuration=root/('.tools/client-build-qa.json' if args.channel=='qa' else '.tools/client-build.json')
assert configuration.is_file(), 'Internal platform build configuration is required'
platform=json.loads(configuration.read_text())
assert platform['CROSSLINK_BUILD_CHANNEL']==args.channel and platform['CROSSLINK_API_URL'].startswith('https://')
environment=dict(os.environ)
environment.update(PUB_CACHE=str(root/'.tools/pub-cache'),GRADLE_USER_HOME=str(root/'.tools/gradle'),ANDROID_HOME=str(root/'.tools/android-sdk'),ANDROID_SDK_ROOT=str(root/'.tools/android-sdk'),JAVA_HOME='/usr/lib/jvm/java-17-openjdk',CROSSLINK_BUILD_CHANNEL=args.channel)
environment['PATH']=str(root/'.tools/flutter/bin')+':'+environment['JAVA_HOME']+'/bin:'+environment['PATH']
version=re.search(r'^version:\s*([0-9.]+)\+([0-9]+)',(root/'client/pubspec.yaml').read_text(),re.M).group(1)
command=['flutter','--no-version-check','build','apk','--'+args.mode,'--no-pub','--split-per-abi','--target-platform','android-arm64','--dart-define-from-file='+str(configuration)]
if args.build_number:command.append('--build-number='+str(args.build_number))
cgroup = None
controller = Path('/sys/fs/cgroup/memory')
if os.geteuid() == 0 and (controller / 'memory.limit_in_bytes').is_file():
    cgroup = controller / f'crosslink-build-{os.getpid()}'
    cgroup.mkdir()
    (cgroup / 'memory.limit_in_bytes').write_text(str(850 * 1024**2))
    (cgroup / 'memory.memsw.limit_in_bytes').write_text(str(2800 * 1024**2))
    (cgroup / 'memory.swappiness').write_text('100')
    print('CrossLink build isolated: 850 MiB resident cap; uses existing swap only.', flush=True)

def constrain():
    if cgroup is not None:
        (cgroup / 'cgroup.procs').write_text(str(os.getpid()))

try:
    result = subprocess.run(
        command,
        cwd=root / 'client', env=environment, preexec_fn=constrain if cgroup else None,
    ).returncode
finally:
    if cgroup is not None:
        for _ in range(10):
            try:
                cgroup.rmdir()
                break
            except OSError:
                time.sleep(.2)
        else:
            print(f'Build cgroup still has children: {cgroup}', file=sys.stderr)
if result==0:
 apk=root/f'client/build/app/outputs/flutter-apk/app-arm64-v8a-{args.mode}.apk'
 directory=root/f'artifacts/{version}/{args.channel}';directory.mkdir(parents=True,exist_ok=True)
 suffix='-qa' if args.channel=='qa' else ''
 name=f'CrossLink-{version}-android-arm64-{args.mode}{suffix}.apk';shutil.copy2(apk,directory/name)
 commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
 manifest={'version':version,'channel':args.channel,'mode':args.mode,'source_commit':commit,'configuration_sha256':hashlib.sha256(configuration.read_bytes()).hexdigest(),'files':[{'name':name,'bytes':apk.stat().st_size,'sha256':hashlib.sha256(apk.read_bytes()).hexdigest()}]}
 (directory/'android-manifest.json').write_text(json.dumps(manifest,indent=2))
 print('Android artifact ready:',directory/name)
sys.exit(result)
