import copy
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import runtime_assets as assets

class RuntimeAssetsTests(unittest.TestCase):
    def test_repository_inputs_match_all_pins(self):
        self.assertEqual(len(assets.inputs()), 7)
    def test_missing_and_modified_input_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'input'
            with self.assertRaises(ValueError): assets.checked(p, '0' * 64)
            p.write_text('tampered')
            with self.assertRaises(ValueError): assets.checked(p, '0' * 64)
    def test_each_resource_pin_is_enforced(self):
        lock = assets.load()
        for item in lock['resources']:
            broken = copy.deepcopy(lock)
            next(x for x in broken['resources'] if x['path'] == item['path'])['sha256'] = '0' * 64
            with self.assertRaises(ValueError): assets.inputs(broken)
    def test_custom_adb_never_borrows_cache_notice(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp); runtime = repo / 'assets/runtime'; runtime.mkdir(parents=True)
            (runtime / 'adb').write_text('other')
            with patch.object(assets, 'REPO', repo):
                with self.assertRaises(ValueError): assets.inputs()
    def test_validation_finishes_before_copy_writes(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / 'resources'
            with patch.object(assets, 'inputs', side_effect=ValueError('missing APK')):
                with self.assertRaises(ValueError): assets.copy_resources(target)
            self.assertFalse(target.exists())
    def test_resigning_runtime_preserves_locked_code(self):
        import shutil, subprocess
        with tempfile.TemporaryDirectory() as tmp:
            source = assets.inputs()['runtime/adb']; target = Path(tmp) / 'adb'
            subprocess.run(['lipo', str(source), '-thin', 'arm64', '-output', str(target)], check=True)
            subprocess.run(['codesign', '--force', '--sign', '-', '--options', 'runtime', str(target)], check=True, capture_output=True)
            self.assertEqual(assets.unsigned_arm64(target), assets.load()['platform_tools']['arm64_unsigned_sha256'])
    def test_signed_adb_code_normalizes_to_pinned_code(self):
        self.assertEqual(assets.unsigned_arm64(assets.inputs()['runtime/adb']), assets.load()['platform_tools']['arm64_unsigned_sha256'])

if __name__ == '__main__': unittest.main()
