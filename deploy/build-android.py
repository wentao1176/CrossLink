#!/usr/bin/env python3
"""Build only this project's APK; cap resident memory on the small ECS (cgroup v1)."""
import os
from pathlib import Path
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[1]
assert root == Path('/home/CrossLink'), 'Run the SSH build from /home/CrossLink'
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
        ['flutter', 'build', 'apk', '--debug', '--split-per-abi', '--target-platform', 'android-arm64'],
        cwd=root / 'client', preexec_fn=constrain if cgroup else None,
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
sys.exit(result)
