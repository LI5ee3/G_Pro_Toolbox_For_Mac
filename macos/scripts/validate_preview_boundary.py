#!/usr/bin/env python3
"""Fail if the safe preview can reach production hardware adapters."""
import json
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
manifest = json.loads(subprocess.check_output(
    ['swift', 'package', '--package-path', str(root), 'dump-package'], text=True))
targets = {target['name']: target for target in manifest['targets']}

def dependencies(name):
    found = set()
    pending = [name]
    while pending:
        current = pending.pop()
        if current in found:
            continue
        found.add(current)
        for dependency in targets[current]['dependencies']:
            for kind in ['byName', 'target']:
                if kind in dependency:
                    pending.append(dependency[kind][0])
    return found

reachable = dependencies('ToolboxPreviewHost')
assert 'ToolboxMacAdapters' not in reachable, reachable
assert 'ToolboxApp' not in reachable, reachable
assert 'ToolboxProcessExecution' not in reachable, reachable
for module in ['ToolboxConcurrency', 'ToolboxDomain', 'ToolboxApplication', 'MimonitorToolbox', 'ToolboxPreviewSupport', 'ToolboxPreviewHost']:
    for source in (root / 'Sources' / module).rglob('*.swift'):
        text = source.read_text()
        for forbidden in ['Process()', 'CGEvent.tapCreate(', 'AudioObjectSetPropertyData(',
                          'NSWorkspace.shared', 'UserDefaults.standard', 'NSApp.terminate(',
                          'FileManager.default', 'NSSavePanel()', 'NSOpenPanel()', 'PresetStore()', 'posix_spawn(', 'Darwin.kill(', 'import ServiceManagement', 'SMAppService.']:
            # Comments are not executable boundaries.
            executable_lines = '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('//'))
            assert forbidden not in executable_lines, (source, forbidden)
if len(sys.argv) > 1:
    app = Path(sys.argv[1])
    for binary in (app / 'Contents' / 'MacOS').iterdir():
        if not binary.is_file():
            continue
        symbols = subprocess.check_output(['nm', '-gjU', str(binary)], text=True, stderr=subprocess.DEVNULL)
        for forbidden in ['SystemProcessRunner', 'LiveHotkeyDriver', 'LiveToolboxRuntime', 'NetworkScan', 'ToolboxMacAdapters', 'ToolboxProcessExecution', 'LiveLoginItems', 'LegacyLoginItemFiles', 'SMAppService']:
            assert forbidden not in symbols, (binary, forbidden)
    resources = app / 'Contents' / 'Resources'
    assert not (resources / 'runtime').exists()
    assert not (resources / 'adb_guardian').exists()
print('PASS: safe preview dependency graph, source effects and optional binary/resources boundary')
