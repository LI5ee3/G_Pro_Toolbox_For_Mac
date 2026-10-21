#!/usr/bin/env python3
"""Check the enforced R3 boundaries without creating any app runtime."""
import json
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
manifest = json.loads(subprocess.check_output(['swift', 'package', '--package-path', str(root), 'dump-package'], text=True))
targets = {item['name']: item for item in manifest['targets']}
def direct(name):
    return {value[0] for dependency in targets[name]['dependencies']
            for key, value in dependency.items() if key in ['byName', 'target']}
assert direct('ToolboxDomain') == set()
assert any(setting.get('kind', {}).get('swiftLanguageMode', {}).get('_0') == '6'
           for setting in targets['ToolboxDomain']['settings'])
assert direct('MimonitorPresetCore') == {'ToolboxDomain'}
assert direct('ToolboxApplication') == {'ToolboxDomain', 'MimonitorPresetCore'}
assert 'MimonitorToolbox' not in direct('ToolboxMacAdapters')
assert 'ToolboxMacAdapters' not in direct('MimonitorToolbox')
assert 'ToolboxMacAdapters' not in direct('ToolboxPreviewSupport')
visited, active = set(), set()
def visit(name):
    assert name not in active, ('dependency cycle', name)
    if name in visited:
        return
    active.add(name)
    for item in direct(name):
        visit(item)
    active.remove(name); visited.add(name)
for target in targets:
    visit(target)
for source in (root / 'Sources' / 'ToolboxDomain').glob('*.swift'):
    text = source.read_text()
    imports = re.findall(r'^import (\w+)', text, re.M)
    assert set(imports) <= {'Foundation'}, (source, imports)
for source in (root / 'Sources' / 'ToolboxApplication').rglob('*.swift'):
    text = source.read_text()
    assert 'import SwiftUI' not in text and 'import ToolboxMacAdapters' not in text, source
    assert 'ObservableObject' not in text and '@Published' not in text, source
for source in (root / 'Sources' / 'MimonitorToolbox').rglob('*.swift'):
    text = source.read_text()
    assert 'import ToolboxMacAdapters' not in text, source
    for forbidden in ['state.adb', 'state.environment', '@EnvironmentObject', 'objectWillChange']:
        assert forbidden not in text, (source, forbidden)
models = sorted((root / 'Sources' / 'ToolboxApplication' / 'StateModels').glob('*.swift'))
assert len(models) == 9, models
for source in models:
    text = source.read_text()
    assert '@MainActor @Observable' in text, source
    for handle in ['DispatchWorkItem', 'Task<', 'Timer(', 'RuntimeCancellation']:
        assert handle not in text, (source, handle)
assert not list((root / 'Sources').rglob('AppState*.swift'))
print('PASS: acyclic Domain/Core/Application/Adapters/UI graph; 9 MainActor Observation models; no global state relay')
