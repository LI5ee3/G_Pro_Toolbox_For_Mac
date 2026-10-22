# Display Runtime Assets

The native Mac app bundles these helpers into `Contents/Resources/runtime/`,
then deploys them to the display over network ADB:

- `MtkDirectTool.jar`: MTK JNI calls for picture settings.
- `ColorfulLedTool.jar`: MiTV PM2 colorful LED HIDL calls.

These JAR files run on the display's Android system. They do not require a Java
runtime on the Mac. Their sources are in `tools/mtk_direct/` and
`tools/colorful_led/` respectively.

Runtime inputs are pinned in `macos/Config/RuntimeAssets.lock.json`, including
Platform-Tools 37.0.1-15733141, its official versioned archive SHA-256, adb and NOTICE.
Run `python3 macos/scripts/runtime_assets.py prepare` explicitly to prepare a missing
cache. Building and Preview never download programs. A repository adb requires its own
matching `NOTICE-platform-tools.txt`; arbitrary substitutions fail the digest gate.
Only arm64 is packaged; the original binary/cache stays untouched. JAR/APK bytes are
preserved. Pin changes require deliberate provenance and regression review.

The bundled `Acknowledgements.txt` records upstream attribution and unresolved license /
Guardian source provenance; checksums do not establish redistribution rights.
