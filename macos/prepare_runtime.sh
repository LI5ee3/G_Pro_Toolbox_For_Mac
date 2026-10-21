#!/bin/bash
# Xcode production target only. PreviewHost has no runtime-copy phase.
set -euo pipefail
REPO_DIR="$(cd "${SRCROOT}/.." && pwd)"
RESOURCE_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
ADB_SOURCE="${REPO_DIR}/assets/runtime/adb"
if [ ! -x "$ADB_SOURCE" ]; then ADB_SOURCE="${SRCROOT}/.cache/platform-tools/adb"; fi
if [ ! -x "$ADB_SOURCE" ]; then
    echo 'error: 缺少 macOS adb。请先准备 macos/.cache/platform-tools/adb 或 assets/runtime/adb；PreviewHost 不需要这些资源。'
    exit 1
fi
mkdir -p "${RESOURCE_DIR}/runtime" "${RESOURCE_DIR}/adb_guardian"
ADB_ARCHS="$(lipo -archs "$ADB_SOURCE")"
if [ "$ADB_ARCHS" = arm64 ]; then cp "$ADB_SOURCE" "${RESOURCE_DIR}/runtime/adb";
else lipo "$ADB_SOURCE" -thin arm64 -output "${RESOURCE_DIR}/runtime/adb"; fi
chmod +x "${RESOURCE_DIR}/runtime/adb"
for JAR_NAME in MtkDirectTool.jar ColorfulLedTool.jar; do
    cp "${REPO_DIR}/assets/runtime/${JAR_NAME}" "${RESOURCE_DIR}/runtime/${JAR_NAME}"
done
cp "${REPO_DIR}/assets/adb_guardian/adbguardian-signed.apk" "${RESOURCE_DIR}/adb_guardian/adbguardian-signed.apk"
NOTICE_SOURCE="${REPO_DIR}/assets/runtime/NOTICE-platform-tools.txt"
if [ ! -f "$NOTICE_SOURCE" ]; then NOTICE_SOURCE="${SRCROOT}/.cache/platform-tools/NOTICE.txt"; fi
if [ ! -f "$NOTICE_SOURCE" ]; then echo 'error: 缺少与 adb 配套的 NOTICE'; exit 1; fi
cp "$NOTICE_SOURCE" "${RESOURCE_DIR}/runtime/NOTICE-platform-tools.txt"
cp "${SRCROOT}/assets/AppIcon.icns" "${RESOURCE_DIR}/AppIcon.icns"
# Thinning changes a Mach-O signature; sign that owned copy before Xcode signs the app.
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "${RESOURCE_DIR}/runtime/adb"
