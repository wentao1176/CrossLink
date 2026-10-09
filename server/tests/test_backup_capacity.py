import importlib.util
from pathlib import Path
import pytest

def backup_module():
 path=Path(__file__).resolve().parents[2]/'deploy/backup-platform.py'
 spec=importlib.util.spec_from_file_location('crosslink_backup',path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

def test_backup_refuses_four_gib_files_with_only_three_gib_free(tmp_path):
 module=backup_module();reserve=2*1024**3
 with pytest.raises(module.BackupSpaceLow):
  module.check_capacity(tmp_path,file_bytes=4*1024**3,database_bytes=1024**2,private_bytes=4096,reserve=reserve,free_bytes=lambda:31*1024**3//10)

def test_backup_stops_on_midwrite_space_loss_and_removes_partial(tmp_path):
 module=backup_module();free=[10**9]
 output=tmp_path/'partial.tar.gz'
 with pytest.raises(module.BackupSpaceLow):
  with module.GuardedOutput(output,100,free_bytes=lambda:free[0]) as stream:
   stream.write(b'first')
   free[0]=102
   stream.write(b'longer than remaining space')
 assert not output.exists()
