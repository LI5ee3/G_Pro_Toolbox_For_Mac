import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release_pipeline as release

class ReleaseGateTests(unittest.TestCase):
    def test_development_is_explicit_adhoc(self):
        self.assertEqual(release.signing_identity('development', None, None), '-')
        with self.assertRaises(release.GateError): release.signing_identity('development', 'a'*40, None)
    def test_formal_never_falls_back(self):
        for identity in [None, '-', 'name', 'a'*40]:
            with patch.object(release, 'output', return_value='0 valid identities found'):
                with self.assertRaises(release.GateError): release.signing_identity('distribution', identity, 'ABCDEFGHIJ')
    def test_formal_rejects_self_signed_and_wrong_team(self):
        identity = 'A'*40
        for name in ['MimonitorToolbox Local Signing', 'Developer ID Application: Example (ZZZZZZZZZZ)']:
            with patch.object(release, 'output', return_value=f'1) {identity} "{name}"'):
                with self.assertRaises(release.GateError): release.signing_identity('distribution', identity, 'ABCDEFGHIJ')
    def test_formal_accepts_only_exact_valid_identity(self):
        identity = 'A'*40
        with patch.object(release, 'output', return_value=f'1) {identity} "Developer ID Application: Example (ABCDEFGHIJ)"'):
            self.assertEqual(release.signing_identity('distribution', identity, 'ABCDEFGHIJ'), identity)
    def test_version_validation(self):
        release.validate_version('1.2.3','20261022.6')
        for v,b in [('bad','1'),('1.2.3','bad'),('1.2.3','1.2.3.4')]:
            with self.assertRaises(release.GateError): release.validate_version(v,b)
    def test_preview_is_never_accepted_as_production(self):
        with tempfile.TemporaryDirectory() as tmp:
            import plistlib
            app=Path(tmp)/'preview.app'; (app/'Contents').mkdir(parents=True)
            (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.mimonitor.toolbox.preview','CFBundleExecutable':'ToolboxPreviewHost'}))
            with self.assertRaises(release.GateError): release.verify_app(app)

if __name__ == '__main__': unittest.main()
