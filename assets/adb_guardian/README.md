# AdbGuardian Runtime Asset

The bundled `adbguardian-signed.apk` is **versionCode 6 / versionName 3.2.1-local**.
It is a minimal local patch of upstream AdbGuardian 3.2 (versionCode 5), not a
replacement implementation.

## Behavior

- Preserve the original boot, wake, accessibility, alarm and ADB repair mechanisms.
- Maintain `adb_enabled` and legacy TCP port 5555; both USB and TCP remain usable.
- Stop forcing Android's separate `adb_wifi_enabled` setting through either
  `Settings.Global` or TvService. Its network authorization is tied to the AP's
  BSSID, which can change when the Mac Internet Sharing hotspot restarts.
- Do not treat disabled wireless debugging as a repair condition or health fault.
  This prevents that setting alone from causing repeated `adbd` restarts and
  network authorization dialogs. APK and Mac status checks use the same rule.

This does not add automatic USB/TCP switching to the Mac app or change the
display's video input selection. Explicit Android wireless-debugging choices
remain under the user's control.

## Provenance and patch

Base APK: [YiHoooong/Mimonitor_Toolbox at 56fa67e](https://github.com/YiHoooong/Mimonitor_Toolbox/blob/56fa67e8d990a2dd8d7ebe1b6865d3b18928d08d/assets/adb_guardian/adbguardian-signed.apk).

Base APK SHA-256:

```text
b910dab254ce4fd9b806a0f57693850c23bc0e8a566a41f808acc283f125a083
```

The upstream README points to `/home/hq/mitv/adb_guardian`; its Java/Kotlin source
is not present in the public repository. The local changes are preserved as
[no-wireless-prompt.patch](no-wireless-prompt.patch), against the Apktool 3.0.3
decoded base. Only four methods in two classes and the APK version change.
The original permissions, components, SDK requirements and resource definitions
are preserved. Existing provenance/licensing limitations still apply.

## Rebuilding

Use Java 17+, Apktool 3.0.3 and uber-apk-signer 1.3.0. Verify the base APK hash
above before decoding it. From the repository root, with the two JAR paths set
and the verified base saved as `original-v5.apk`:

```sh
java -jar "$APKTOOL_JAR" d -p validation/guardian-rebuild/framework -o validation/guardian-rebuild/work original-v5.apk
patch -d validation/guardian-rebuild/work -p1 < assets/adb_guardian/no-wireless-prompt.patch
java -jar "$APKTOOL_JAR" b -p validation/guardian-rebuild/framework validation/guardian-rebuild/work -o validation/guardian-rebuild/guardian-v6-unsigned.apk
java -jar "$GUARDIAN_SIGNER_JAR" --apks validation/guardian-rebuild/guardian-v6-unsigned.apk --ks "$HOME/.android/adbguardian-local.p12" --ksAlias adbguardian-local --out validation/guardian-rebuild/signed
```

Enter the signing passwords interactively. Preserve the local keystore
`~/.android/adbguardian-local.p12` and its password file
`~/.android/adbguardian-local.pass`; neither belongs in Git. Subsequent versions
must keep this signing identity and increment `versionCode`.

Local certificate SHA-256:

```text
b44d01bb2ed9ee595f1ada7d18093e448c4d3480ce2e8469f4e0d70d147487f7
```

After rebuilding, verify the signature, alignment, manifest, version and patch,
then update `macos/Config/RuntimeAssets.lock.json` for the final signed bytes.

## Installation boundary

The original signing key is unavailable. The local certificate differs from
upstream, so the first migration requires uninstalling the old Guardian APK;
`adb install -r` cannot perform that migration. Uninstalling clears Guardian's
private data and its old permissions. Back up the original APK, app data and
accessibility configuration before replacement, then restore the required
permissions without removing other accessibility services.

The Mac app does not silently uninstall an existing Guardian. Later local builds
signed with the same key can use the normal update path. Repository changes and
offline APK checks do not imply installation or hardware acceptance.
