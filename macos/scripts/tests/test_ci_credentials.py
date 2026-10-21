import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import ci_credentials as credentials

class CICredentialTests(unittest.TestCase):
    def test_missing_credentials_do_not_touch_keychains(self):
        with tempfile.TemporaryDirectory() as tmp,patch.dict(os.environ,{},clear=True),patch.object(credentials,'command') as command:
            with self.assertRaises(ValueError): credentials.setup(Path(tmp)/'state.json')
            command.assert_not_called()
    def test_import_failure_always_cleans_temp_keychain(self):
        with tempfile.TemporaryDirectory() as tmp:
            state=Path(tmp)/'state.json';calls=[]
            env={k:'dummy' for k in ['DEVELOPER_ID_P12_PASSWORD','DEVELOPER_TEAM_ID','NOTARY_KEY_ID','NOTARY_ISSUER_ID']}
            env.update({'DEVELOPER_ID_P12_BASE64':base64.b64encode(b'fake-p12').decode(),'NOTARY_KEY_P8_BASE64':base64.b64encode(b'fake-p8').decode(),'RUNNER_TEMP':tmp,'GITHUB_ENV':str(Path(tmp)/'env')})
            def run(args):
                calls.append(args)
                if 'create-keychain' in args: Path(args[-1]).touch()
                if 'import' in args: raise subprocess.CalledProcessError(1,args)
                return subprocess.CompletedProcess(args,0,'','')
            with patch.dict(os.environ,env,clear=True),patch.object(credentials,'command',side_effect=run):
                with self.assertRaises(subprocess.CalledProcessError):credentials.setup(state)
            self.assertTrue(any('delete-keychain' in x for x in calls))
            self.assertFalse(state.exists());self.assertFalse(list(Path(tmp).glob('toolbox-signing-*')))
    def test_cleanup_is_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(credentials,'command') as command:
            state=Path(tmp)/'missing.json';credentials.clean(state);credentials.clean(state);command.assert_not_called()
    def test_cleanup_does_not_delete_foreign_keychain(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(credentials,'command') as command:
            root=Path(tmp)/'foreign';root.mkdir();keychain=root/'login.keychain-db';keychain.touch()
            state=Path(tmp)/'state.json';state.write_text(json.dumps({'keychain':str(keychain),'directory':str(root)}))
            credentials.clean(state);command.assert_not_called();self.assertTrue(keychain.exists())

if __name__=='__main__':unittest.main()
