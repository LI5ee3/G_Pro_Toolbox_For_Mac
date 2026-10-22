#!/usr/bin/env python3
"""Import a dedicated Developer ID P12 into an ephemeral keychain; never export login keys.
Run only on an isolated release runner. Secret values are read from environment, never logged.
"""
import base64
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shutil
import subprocess
import sys
import tempfile

def command(args):
    return subprocess.run(args, check=True, capture_output=True, text=True)

def clean(state):
    if not state.exists(): return
    info = json.loads(state.read_text())
    keychain = Path(info['keychain'])
    root = Path(info['directory'])
    if keychain.parent == root and root.name.startswith('toolbox-signing-'):
        if keychain.exists(): command(['security','delete-keychain',str(keychain)])
        shutil.rmtree(root)
    state.unlink()

def setup(state):
    if state.exists(): raise ValueError('credential state already exists')
    required = ['DEVELOPER_ID_P12_BASE64','DEVELOPER_ID_P12_PASSWORD','DEVELOPER_TEAM_ID','NOTARY_KEY_P8_BASE64','NOTARY_KEY_ID','NOTARY_ISSUER_ID','GITHUB_ENV','RUNNER_TEMP']
    if any(not os.environ.get(k) for k in required): raise ValueError('missing release credential')
    root = Path(tempfile.mkdtemp(prefix='toolbox-signing-',dir=os.environ['RUNNER_TEMP']))
    root.chmod(0o700)
    keychain = root/'release.keychain-db'
    state.write_text(json.dumps({'directory':str(root),'keychain':str(keychain)}))
    state.chmod(0o600)
    try:
        password = secrets.token_hex(32)
        command(['security','create-keychain','-p',password,str(keychain)])
        command(['security','set-keychain-settings','-lut','21600',str(keychain)])
        command(['security','unlock-keychain','-p',password,str(keychain)])
        p12 = root/'identity.p12';p12.write_bytes(base64.b64decode(os.environ['DEVELOPER_ID_P12_BASE64'],validate=True));p12.chmod(0o600)
        command(['security','import',str(p12),'-k',str(keychain),'-P',os.environ['DEVELOPER_ID_P12_PASSWORD'],'-T','/usr/bin/codesign'])
        command(['security','set-key-partition-list','-S','apple-tool:,apple:,codesign:','-s','-k',password,str(keychain)])
        identities = command(['security','find-identity','-v','-p','codesigning',str(keychain)]).stdout
        candidates = re.findall(r'\b([0-9A-F]{40}) "Developer ID Application:[^"]+ \('+re.escape(os.environ['DEVELOPER_TEAM_ID'])+r'\)"',identities)
        if len(candidates) != 1: raise ValueError('expected one matching Developer ID identity')
        p12.unlink()
        key = root/'AuthKey.p8';key.write_bytes(base64.b64decode(os.environ['NOTARY_KEY_P8_BASE64'],validate=True));key.chmod(0o600)
        profile = 'toolbox-release'
        command(['xcrun','notarytool','store-credentials',profile,'--keychain',str(keychain),'--key',str(key),'--key-id',os.environ['NOTARY_KEY_ID'],'--issuer',os.environ['NOTARY_ISSUER_ID']])
        key.unlink()
        with open(os.environ['GITHUB_ENV'],'a') as out:
            for name,value in [('TOOLBOX_SIGNING_KEYCHAIN',str(keychain)),('TOOLBOX_SIGNING_IDENTITY',candidates[0]),('TOOLBOX_NOTARY_PROFILE',profile)]: out.write(f'{name}={value}\n')
    except Exception:
        clean(state)
        raise

if __name__ == '__main__':
    try:
        action,state = sys.argv[1:];state=Path(state)
        if action == 'setup': setup(state)
        elif action == 'clean': clean(state)
        else: raise ValueError('unknown action')
    except Exception:
        # security arguments may contain secrets. Never print the exception or command.
        print('ERROR: release credential operation failed; no credentials were logged',file=sys.stderr)
        sys.exit(1)
