# Display Runtime Assets

The native Mac app bundles these helpers into `Contents/Resources/runtime/`,
then deploys them to the display over network ADB:

- `MtkDirectTool.jar`: MTK JNI calls for picture settings.
- `ColorfulLedTool.jar`: MiTV PM2 colorful LED HIDL calls.

These JAR files run on the display's Android system. They do not require a Java
runtime on the Mac. Their sources are in `tools/mtk_direct/` and
`tools/colorful_led/` respectively.

`macos/build_app.sh` downloads the macOS adb client from Google's official
platform-tools distribution and caches it under `macos/.cache/`. To use a fixed
version instead, place a macOS adb binary containing arm64 at `assets/runtime/adb`
before building. The packaged adb contains only arm64; a multi-architecture source
binary is thinned during packaging without changing the cache.
