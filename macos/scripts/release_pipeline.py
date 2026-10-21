#!/usr/bin/env python3
"""Fail-closed build/sign/package entry point. Never installs or launches the app."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import runtime_assets as assets

MACOS = assets.MACOS
APP_NAME = '红米G Pro ToolBox.app'
EXECUTABLE = 'MimonitorToolbox'
BUNDLE_ID = 'com.mimonitor.toolbox'

class GateError(RuntimeError): pass

def require(condition, message):
    if not condition: raise GateError(message)

def run(args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, **kwargs)

def output(args):
    return run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True).stdout

def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')

def signing_identity(mode, identity, team):
    if mode == 'development':
        require(not identity and not team, 'development 明确使用 ad-hoc；固定身份请用 local 或 distribution')
        return '-'
    require(bool(identity) and identity != '-', '需要显式指定签名身份 SHA1，不允许降级')
    require(re.fullmatch(r'[0-9A-Fa-f]{40}', identity) is not None, '签名身份必须为唯一 SHA1')
    text = output(['security', 'find-identity', '-v', '-p', 'codesigning'])
    matches = re.findall(r'\b' + re.escape(identity) + r' "([^"]+)"', text, re.I)
    require(len(matches) == 1, '签名身份不可用；请准备有效证书及私钥')
    if mode == 'distribution':
        require(team and re.fullmatch(r'[A-Z0-9]{10}', team), '正式签名需要 10 位 Team ID')
        require(matches[0].startswith('Developer ID Application:') and matches[0].endswith(f'({team})'),
                '正式分发仅接受匹配 Team ID 的 Developer ID Application')
    return identity

def signature(path):
    run(['codesign', '--verify', '--deep', '--strict', path], capture_output=True)
    return run(['codesign', '-dvv', path], capture_output=True, text=True).stderr

def validate_version(version, build):
    require(re.fullmatch(r'\d+\.\d+\.\d+', version) is not None, '版本需为三段数字')
    require(re.fullmatch(r'\d+(?:\.\d+){0,2}', build) is not None, '构建号需为一至三段数字')

def macho_files(app):
    magic = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
    for path in app.rglob('*'):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as handle:
                if handle.read(4) in magic: yield path

def verify_app(app, mode='development', team=None, version=None, build=None):
    app = Path(app)
    require(not app.is_symlink(), 'App 不接受符号链接')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    require(info['CFBundleIdentifier'] == BUNDLE_ID and info['CFBundleExecutable'] == EXECUTABLE, '应用身份不匹配')
    require(info['LSMinimumSystemVersion'] == '27.0' and not info.get('LSUIElement', False), '最低版本或窗口身份不匹配')
    for key in ['NSLocalNetworkUsageDescription', 'NSAppleEventsUsageDescription']:
        require(bool(info.get(key)), f'缺少权限用途声明 {key}')
    if version: require(info['CFBundleShortVersionString'] == version, '版本不一致')
    if build: require(info['CFBundleVersion'] == build, '构建号不一致')
    resources = app / 'Contents/Resources'
    for relative, source in assets.inputs().items():
        target = resources / relative
        require(target.is_file() and not target.is_symlink(), f'缺少资源 {relative}')
        if relative == 'runtime/adb':
            require(assets.unsigned_arm64(target) == assets.load()['platform_tools']['arm64_unsigned_sha256'], 'adb 代码与锁定输入不一致')
        else: require(assets.digest(target) == assets.digest(source), f'资源变化 {relative}')
    main = app / 'Contents/MacOS' / EXECUTABLE
    binaries = list(macho_files(app))
    require(main in binaries and resources / 'runtime/adb' in binaries, '缺少主程序或 adb')
    details = {}
    for binary in binaries:
        require(output(['lipo', '-archs', binary]).strip() == 'arm64', f'非单 arm64: {binary}')
        relative = str(binary.relative_to(app))
        allowed = {'Contents/MacOS/MimonitorToolbox', 'Contents/Resources/runtime/adb'}
        if mode != 'distribution': allowed |= {'Contents/MacOS/MimonitorToolbox.debug.dylib', 'Contents/MacOS/__preview.dylib'}
        require(relative in allowed, f'尚未审查的嵌入原生代码: {relative}')
        minos = re.search(r'\bminos ([\d.]+)', output(['xcrun', 'vtool', '-show-build', binary]))
        require(minos is not None and tuple(map(int, minos[1].split('.'))) <= (27, 0, 0), f'不可用的 minOS: {relative}')
        if binary == main: require(minos[1] in ('27.0', '27.0.0'), '主程序 minOS 必须 27.0')
        for line in output(['otool', '-L', binary]).splitlines()[1:]:
            dep = line.strip().split(' (', 1)[0]
            require(dep.startswith(('/System/Library/', '/usr/lib/')) or
                    (dep.startswith('@rpath/') and mode != 'distribution' and (app/'Contents/MacOS'/dep.removeprefix('@rpath/')).exists()),
                    f'未允许的动态依赖 {dep}')
        sig = signature(binary)
        if mode == 'distribution':
            require('Authority=Developer ID Application:' in sig and f'TeamIdentifier={team}\n' in sig and 'runtime' in sig and 'Timestamp=' in sig,
                    f'正式签名缺少身份/Team/Runtime/timestamp: {relative}')
        elif mode == 'local': require('Signature=adhoc' not in sig, f'固定签名降级: {relative}')
        else: require('Signature=adhoc' in sig, f'开发产物身份不符合显式 ad-hoc 策略: {relative}')
        details[relative] = {'sha256': assets.digest(binary), 'minos': minos[1]}
    sig = signature(app)
    if mode == 'distribution':
        require('Authority=Developer ID Application:' in sig and f'TeamIdentifier={team}\n' in sig and 'runtime' in sig and 'Timestamp=' in sig, 'App 正式签名门禁失败')
    ent = plistlib.loads(run(['codesign', '-d', '--entitlements', ':-', app], capture_output=True).stdout)
    require(ent.get('com.apple.security.automation.apple-events') is True, '缺少 Terminal automation entitlement')
    require(not ent.get('com.apple.security.app-sandbox', False), '不可意外启用 Sandbox 改变 ADB 行为')
    if mode == 'distribution': require(not ent.get('com.apple.security.get-task-allow', False), '发布包不可调试')
    return {'bundle_id': BUNDLE_ID, 'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'], 'mode': mode, 'team': team, 'binaries': details}

def build_app(args):
    validate_version(args.version, args.build)
    identity = signing_identity(args.mode, args.identity, args.team)
    assets.inputs()
    require(output(['uname', '-m']).strip() == 'arm64', '需要 Apple Silicon 构建机')
    require(int(output(['sw_vers', '-productVersion']).split('.')[0]) >= 27, '需要 macOS 27+')
    sdk = output(['xcrun', '--sdk', 'macosx', '--show-sdk-version']).strip()
    require(int(sdk.split('.')[0]) >= 27, '需要 macOS 27 SDK 或更新版本')
    destination = args.output.resolve()
    require(not destination.exists(), '输出目录已存在；请选择新目录以保留回滚产物')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.toolbox-build-', dir=destination.parent) as tmp:
        stage = Path(tmp)
        command = ['xcodebuild', '-project', MACOS/'Toolbox.xcodeproj', '-scheme', 'ToolboxApp', '-configuration', 'Release',
                   '-derivedDataPath', args.derived_data.resolve(), '-destination', 'platform=macOS,arch=arm64',
                   f'CODE_SIGN_IDENTITY={identity}', 'CODE_SIGN_STYLE=Manual', 'ENABLE_HARDENED_RUNTIME=YES',
                   f'MARKETING_VERSION={args.version}', f'CURRENT_PROJECT_VERSION={args.build}',
                   f'TOOLBOX_DISTRIBUTION={int(args.mode == "distribution")}', 'build']
        if args.team: command += [f'DEVELOPMENT_TEAM={args.team}']
        if args.mode == 'distribution': command += ['OTHER_CODE_SIGN_FLAGS=--timestamp']
        try:
            with (stage/'build.log').open('w') as log: run(command, stdout=log, stderr=subprocess.STDOUT)
        except subprocess.CalledProcessError:
            failure = destination.parent / (stage.name + '-failure.log')
            shutil.copyfile(stage/'build.log', failure)
            print(f'构建失败，日志：{failure}', file=sys.stderr)
            raise
        source = args.derived_data.resolve()/'Build/Products/Release'/APP_NAME
        run(['ditto', source, stage/APP_NAME])
        report = verify_app(stage/APP_NAME, args.mode, args.team, args.version, args.build)
        report['toolchain'] = output(['xcodebuild', '-version']).strip()
        report['sdk'] = sdk
        report['source_head'] = output(['git', '-C', MACOS, 'rev-parse', 'HEAD']).strip()
        report['dirty_tree'] = bool(output(['git', '-C', MACOS, 'status', '--porcelain']))
        report['runtime_lock_sha256'] = assets.digest(assets.LOCK)
        write_json(stage/'app-verification.json', report)
        # Publish only a completely verified app. No previous app is ever removed.
        stage.rename(destination)
    print(f'PASS: {destination / APP_NAME} ({args.mode})')

def parser():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='action', required=True)
    b = sub.add_parser('build')
    b.add_argument('--mode', choices=['development','local','distribution'], default='development')
    b.add_argument('--identity'); b.add_argument('--team')
    b.add_argument('--version', default='0.1.0'); b.add_argument('--build', default='20261022.6')
    b.add_argument('--output', type=Path, default=MACOS/'.build/artifacts/development')
    b.add_argument('--derived-data', type=Path, default=MACOS/'.build/ReleaseDerivedData')
    b.set_defaults(handler=build_app)
    v = sub.add_parser('verify-app'); v.add_argument('app', type=Path)
    v.add_argument('--mode', choices=['development','local','distribution'], default='development'); v.add_argument('--team')
    v.set_defaults(handler=lambda a: print(json.dumps(verify_app(a.app,a.mode,a.team),ensure_ascii=False,indent=2)))
    return p

if __name__ == '__main__':
    try:
        args = parser().parse_args(); args.handler(args)
    except (GateError, ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'ERROR: {error}', file=sys.stderr); sys.exit(1)
