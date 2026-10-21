import argparse
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import dmg_pipeline as dmg
import release_pipeline as release

class DMGGateTests(unittest.TestCase):
    def test_missing_credentials_precede_any_packaging(self):
        args=dmg.parser().parse_args(['--mode','distribution'])
        with patch.object(release,'run') as runner:
            with self.assertRaises(release.GateError): dmg.package(args)
            runner.assert_not_called()
    def test_mount_detached_when_verification_raises(self):
        calls=[]
        def run(args,**kwargs):
            calls.append(args)
            return subprocess.CompletedProcess(args,0,plistlib.dumps({}),b'')
        with patch.object(release,'run',side_effect=run):
            with self.assertRaises(ValueError):
                with dmg.mounted(Path('fake.dmg')): raise ValueError('signature failure')
        self.assertEqual([x[1] for x in calls],['attach','detach'])
        self.assertIn('-readonly',calls[0]);self.assertIn('-nobrowse',calls[0])
    def test_detach_failure_is_not_ignored(self):
        def run(args,**kwargs):
            if args[1]=='detach': raise subprocess.CalledProcessError(1,args)
            return subprocess.CompletedProcess(args,0,plistlib.dumps({}),b'')
        with patch.object(release,'run',side_effect=run):
            with self.assertRaises(subprocess.CalledProcessError):
                with dmg.mounted(Path('fake.dmg')): pass
    def test_tree_comparison_catches_tamper_modes_and_links(self):
        with tempfile.TemporaryDirectory() as tmp:
            a=Path(tmp)/'a';b=Path(tmp)/'b';a.mkdir();b.mkdir()
            for root in [a,b]: (root/'file').write_text('original');(root/'link').symlink_to('/Applications')
            self.assertEqual(dmg.fingerprint(a),dmg.fingerprint(b))
            (b/'file').write_text('tampered');self.assertNotEqual(dmg.fingerprint(a),dmg.fingerprint(b))
            (b/'file').write_text('original');(b/'file').chmod(0o700);self.assertNotEqual(dmg.fingerprint(a),dmg.fingerprint(b))
    def test_notary_rejection_fetches_log_and_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            calls=[]
            def run(args,**kwargs):
                calls.append(args);return subprocess.CompletedProcess(args,0,'{"id":"fake-id","status":"Invalid"}','')
            with patch.object(release,'run',side_effect=run):
                with self.assertRaises(release.GateError): dmg.notarize(Path('fake.zip'),'fake-profile',Path(tmp),'app')
            self.assertEqual(calls[1][2],'log')
            self.assertTrue((Path(tmp)/'app-notary-result.json').exists())
    def test_notary_timeout_does_not_publish(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(release,'run',side_effect=subprocess.CalledProcessError(1,['notarytool'],output='{"status":"In Progress"}',stderr='timeout')):
                with self.assertRaises(subprocess.CalledProcessError): dmg.notarize(Path('fake.zip'),'fake',Path(tmp),'app')
            self.assertIn('In Progress',(Path(tmp)/'app-notary-result.json').read_text())

if __name__=='__main__':unittest.main()
