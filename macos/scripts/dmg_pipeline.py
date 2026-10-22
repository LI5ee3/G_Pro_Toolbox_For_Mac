#!/usr/bin/env python3
"""Verified DMG/ZIP packaging; signed distribution additionally requires notarization."""
import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import plistlib
import release_pipeline as release
import runtime_assets as assets

def fingerprint(root):
    result = {}
    for path in sorted(Path(root).rglob('*')):
        key = str(path.relative_to(root))
        if path.is_symlink(): result[key] = {'link': os.readlink(path)}
        elif path.is_file(): result[key] = {'sha256': assets.digest(path), 'mode': path.stat().st_mode & 0o777}
        elif path.is_dir(): result[key] = {'directory': True}
    return result

@contextmanager
def mounted(image):
    point = Path(tempfile.mkdtemp(prefix='toolbox-dmg-mount-'))
    attached = False
    try:
        # Read-only and no Finder/LaunchServices launch. Never open mounted software.
        result = release.run(['hdiutil','attach',image,'-readonly','-nobrowse','-noautoopen','-mountpoint',point,'-plist'],capture_output=True)
        attached = True
        plistlib.loads(result.stdout)  # Reject malformed success output too.
        yield point
    finally:
        if attached or os.path.ismount(point):
            # Own explicit mountpoint only. Even successful forced cleanup leaves the
            # failed normal-detach operation visible to the caller.
            try: release.run(['hdiutil','detach',point],capture_output=True)
            except subprocess.CalledProcessError:
                release.run(['hdiutil','detach','-force',point],capture_output=True)
                raise
        if point.exists(): point.rmdir()

def verify_image(image, app, mode, team):
    release.run(['hdiutil','verify',image],capture_output=True)
    with mounted(image) as point:
        link = point/'Applications'
        release.require(link.is_symlink() and os.readlink(link) == '/Applications', 'DMG Applications 链接不正确')
        candidate = point/release.APP_NAME
        report = release.verify_app(candidate, mode, team)
        release.require(fingerprint(candidate) == fingerprint(app), 'DMG 内 App 与签名后原件不一致')
    return report

def notarize(path, profile, directory, label, keychain=None):
    auth = ['--keychain-profile', profile]
    if keychain: auth += ['--keychain', keychain]
    try:
        result = release.run(['xcrun','notarytool','submit',path,*auth,'--wait','--timeout','20m','--output-format','json'],capture_output=True,text=True)
    except subprocess.CalledProcessError as error:
        (directory/f'{label}-notary-result.json').write_text(error.stdout or '')
        (directory/f'{label}-notary-error.log').write_text(error.stderr or '')
        raise
    (directory/f'{label}-notary-result.json').write_text(result.stdout)
    data = json.loads(result.stdout)
    # Always retrieve the audit log, including an unsuccessful submission.
    release.run(['xcrun','notarytool','log',data['id'],*auth,directory/f'{label}-notary-log.json'],capture_output=True)
    release.require(data.get('status') == 'Accepted', f'公证未接受：{label}，见结果与日志')
    return data['id']

def package(args):
    release.require(args.mode != 'distribution' or (args.profile and args.team), '正式分发需要 Team ID 和 notarytool Keychain profile；不允许生成假正式包')
    identity = release.signing_identity(args.mode,args.identity,args.team,args.keychain) if args.mode == 'distribution' else None
    app = args.app.resolve()
    report = release.verify_app(app,args.mode,args.team)
    destination = args.output.resolve()
    release.require(not destination.exists(), '输出目录已存在；请选择新目录以保留上一版')
    destination.parent.mkdir(parents=True,exist_ok=True)
    # Keep failed submissions and build evidence in a separate directory without publishable names.
    work = Path(tempfile.mkdtemp(prefix='.toolbox-package-',dir=destination.parent))
    published = False
    try:
        staged_app = work/release.APP_NAME
        release.run(['ditto',app,staged_app])
        release.require(fingerprint(app) == fingerprint(staged_app),'App 复制发生变化')
        submissions = {}
        if args.mode == 'distribution':
            upload = work/'notary-upload.zip'
            release.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',staged_app,upload])
            submissions['app'] = notarize(upload,args.profile,work,'app',args.keychain)
            release.run(['xcrun','stapler','staple',staged_app])
            release.run(['xcrun','stapler','validate',staged_app])
            upload.unlink()
        suffix = '' if args.mode == 'distribution' else '-' + args.mode
        name = 'MimonitorToolbox-macos-arm64' + suffix
        image = work/(name+'.dmg')
        with tempfile.TemporaryDirectory(prefix='toolbox-image-stage-') as tmp:
            image_stage = Path(tmp)
            release.run(['ditto',staged_app,image_stage/release.APP_NAME])
            (image_stage/'Applications').symlink_to('/Applications')
            release.run(['hdiutil','create','-volname','红米G Pro ToolBox','-srcfolder',image_stage,'-format','UDZO',image],capture_output=True)
        verify_image(image,staged_app,args.mode,args.team)
        if args.mode == 'distribution':
            command = ['codesign','--sign',identity,'--timestamp']
            if args.keychain: command += ['--keychain',args.keychain]
            release.run([*command,image])
            sig = release.signature(image)
            release.require(f'TeamIdentifier={args.team}\n' in sig and 'Authority=Developer ID Application:' in sig and 'Timestamp=' in sig,'DMG 签名身份不匹配')
            submissions['dmg'] = notarize(image,args.profile,work,'dmg',args.keychain)
            release.run(['xcrun','stapler','staple',image])
            release.run(['xcrun','stapler','validate',image])
            release.signature(image)
            release.run(['spctl','--assess','--type','open','--context','context:primary-signature',image],capture_output=True)
            release.run(['spctl','--assess','--type','execute',staged_app],capture_output=True)
        # After ticket stapling: mount again; compare all app bytes, modes and links.
        verify_image(image,staged_app,args.mode,args.team)
        archive = work/(name+'.zip')
        release.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',staged_app,archive])
        with tempfile.TemporaryDirectory(prefix='toolbox-zip-check-') as tmp:
            release.run(['ditto','-x','-k',archive,tmp])
            extracted = Path(tmp)/release.APP_NAME
            release.require(fingerprint(extracted) == fingerprint(staged_app),'ZIP 回读不一致')
            release.verify_app(extracted,args.mode,args.team)
            if args.mode == 'distribution': release.run(['xcrun','stapler','validate',extracted])
        report.update({'distributable':args.mode == 'distribution','notarization':submissions,
                       'checksums':{image.name:assets.digest(image),archive.name:assets.digest(archive)},
                       'runtime_lock_sha256':assets.digest(assets.LOCK)})
        release.write_json(work/'release-manifest.json',report)
        (work/'SHA256SUMS').write_text(''.join(f'{sha}  {name}\n' for name,sha in report['checksums'].items()))
        work.rename(destination); published = True
        print(f'PASS: verified {args.mode} DMG/ZIP: {destination}')
    finally:
        if not published:
            # Preserve failure evidence, but strip publishable extensions/names.
            for path in work.glob('MimonitorToolbox-macos-arm64*'):
                path.rename(path.with_name('FAILED-'+path.name+'.partial'))
            print(f'打包未发布；诊断目录：{work}',file=sys.stderr)

def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--app',type=Path,default=assets.MACOS/'.build/artifacts/development'/release.APP_NAME)
    p.add_argument('--output',type=Path,default=assets.MACOS/'.build/artifacts/packages-development')
    p.add_argument('--mode',choices=['development','local','distribution'],default='development')
    p.add_argument('--identity');p.add_argument('--team');p.add_argument('--profile');p.add_argument('--keychain')
    return p

if __name__ == '__main__':
    def terminate(signum, frame): raise SystemExit(128 + signum)
    signal.signal(signal.SIGTERM, terminate)
    try: package(parser().parse_args())
    except (release.GateError,ValueError,OSError,subprocess.CalledProcessError) as error:
        print(f'ERROR: {error}',file=sys.stderr);sys.exit(1)
