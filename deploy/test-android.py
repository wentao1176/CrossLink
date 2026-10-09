#!/usr/bin/env python3
"""JVM tests for native transport, isolated like the APK build on this 2 GB host."""
import os, subprocess, sys, time
from pathlib import Path
root=Path(__file__).resolve().parents[1]
assert root == Path('/home/CrossLink')
environment = dict(os.environ)
environment.update(GRADLE_USER_HOME=str(root/'.tools/gradle'), ANDROID_HOME=str(root/'.tools/android-sdk'), ANDROID_SDK_ROOT=str(root/'.tools/android-sdk'), JAVA_HOME='/usr/lib/jvm/java-17-openjdk')
controller=Path('/sys/fs/cgroup/memory')
group=controller / f'crosslink-native-tests-{os.getpid()}'
group.mkdir()
(group/'memory.limit_in_bytes').write_text(str(850*1024**2))
(group/'memory.memsw.limit_in_bytes').write_text(str(2800*1024**2))
(group/'memory.swappiness').write_text('100')
def constrain(): (group/'cgroup.procs').write_text(str(os.getpid()))
try:
 result=subprocess.run(['./gradlew',':app:testDebugUnitTest','--tests','com.crosslink.crosslink.SyncClientTest','-x',':app:compileFlutterBuildDebug','--console=plain'],cwd=root/'client/android',env=environment,preexec_fn=constrain).returncode
finally:
 for _ in range(10):
  try: group.rmdir(); break
  except OSError: time.sleep(.2)
 else: print('Build children still exiting:',group)
sys.exit(result)
