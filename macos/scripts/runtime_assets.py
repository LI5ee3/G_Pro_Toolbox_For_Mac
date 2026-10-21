#!/usr/bin/env python3
"""Pinned inputs shared by Xcode and packaging; no network during resource copying."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import urllib.request
import zipfile

MACOS = Path(__file__).resolve().parents[1]
REPO = MACOS.parent
LOCK = MACOS / 'Config/RuntimeAssets.lock.json'

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def checked(path, expected):
    path = Path(path)
    if not path.is_file() or path.is_symlink() or digest(path) != expected:
        raise ValueError(f'缺失或摘要不匹配：{path}')
    return path

def load():
    return json.loads(LOCK.read_text())

def inputs(lock=None):
    lock = lock or load()
    adb = lock['platform_tools']
    # Never pair an arbitrary repository adb with the cache's NOTICE.
    if (REPO / 'assets/runtime/adb').exists():
        paths = [REPO / 'assets/runtime/adb', REPO / 'assets/runtime/NOTICE-platform-tools.txt']
    else:
        paths = [MACOS / '.cache/platform-tools/adb', MACOS / '.cache/platform-tools/NOTICE.txt']
    result = {'runtime/adb': checked(paths[0], adb['adb_sha256']),
              'runtime/NOTICE-platform-tools.txt': checked(paths[1], adb['notice_sha256'])}
    for entry in lock['resources']:
        result[entry['destination']] = checked(REPO / entry['path'], entry['sha256'])
    return result

def prepare():
    """Explicit, versioned download. Verify archive and individual bytes before publishing cache."""
    lock = load()['platform_tools']
    cache = MACOS / '.cache'
    cache.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='platform-tools-', dir=cache) as tmp:
        tmp = Path(tmp)
        archive = tmp / 'download.zip'
        with urllib.request.urlopen(lock['url'], timeout=60) as source, archive.open('wb') as out:
            shutil.copyfileobj(source, out)
        checked(archive, lock['archive_sha256'])
        stage = tmp / 'platform-tools'
        stage.mkdir()
        with zipfile.ZipFile(archive) as z:
            for member, sha in [('adb', lock['adb_sha256']), ('NOTICE.txt', lock['notice_sha256'])]:
                target = stage / member
                target.write_bytes(z.read('platform-tools/' + member))
                checked(target, sha)
        (stage / 'adb').chmod(0o755)
        target = cache / 'platform-tools'
        # Valid existing cache needs no replacement; unknown files are not silently overwritten.
        if target.exists():
            checked(target / 'adb', lock['adb_sha256'])
            checked(target / 'NOTICE.txt', lock['notice_sha256'])
        else:
            stage.rename(target)
    print('PASS: pinned platform-tools archive, adb and NOTICE')

def unsigned_arm64(path):
    with tempfile.TemporaryDirectory() as tmp:
        target = Path(tmp) / 'adb'
        arch = subprocess.check_output(['lipo', '-archs', str(path)], text=True).strip()
        if arch == 'arm64': shutil.copyfile(path, target)
        else: subprocess.run(['lipo', str(path), '-thin', 'arm64', '-output', str(target)], check=True)
        subprocess.run(['codesign', '--remove-signature', str(target)], check=True, capture_output=True)
        # Re-signing changes the signature-only __LINKEDIT virtual allocation. Normalize
        # that allocation after removing the signature; every other byte is compared.
        data = bytearray(target.read_bytes())
        if data[:4] != b'\xcf\xfa\xed\xfe': raise ValueError('Expected little-endian Mach-O 64')
        count = struct.unpack_from('<I', data, 16)[0]
        offset = 32
        for _ in range(count):
            command, size = struct.unpack_from('<II', data, offset)
            if command == 0x19 and data[offset+8:offset+24].rstrip(b'\0') == b'__LINKEDIT':
                filesize = struct.unpack_from('<Q', data, offset+48)[0]
                struct.pack_into('<Q', data, offset+32, (filesize + 0x3fff) & ~0x3fff)
            offset += size
        return hashlib.sha256(data).hexdigest()

def copy_resources(destination):
    sources = inputs()  # Validate all required files before writing any.
    destination = Path(destination)
    for relative, source in sources.items():
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if relative == 'runtime/adb':
            arch = subprocess.check_output(['lipo', '-archs', str(source)], text=True).strip()
            if arch == 'arm64': shutil.copyfile(source, target)
            else: subprocess.run(['lipo', str(source), '-thin', 'arm64', '-output', str(target)], check=True)
            target.chmod(0o755)
        else: shutil.copyfile(source, target)
    identity = os.environ.get('EXPANDED_CODE_SIGN_IDENTITY') or '-'
    args = ['codesign', '--force', '--sign', identity]
    if os.environ.get('ENABLE_HARDENED_RUNTIME') == 'YES': args += ['--options', 'runtime']
    if os.environ.get('TOOLBOX_DISTRIBUTION') == '1': args += ['--timestamp']
    subprocess.run([*args, str(destination / 'runtime/adb')], check=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['check', 'prepare', 'copy'])
    parser.add_argument('destination', nargs='?')
    args = parser.parse_args()
    if args.action == 'prepare': prepare()
    elif args.action == 'check': inputs(); print('PASS: all pinned resources')
    else:
        if not args.destination: parser.error('copy requires destination')
        copy_resources(args.destination)
