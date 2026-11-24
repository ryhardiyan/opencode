# 32-bit (armeabi-v7a) Android build

## Audit result

`opencode-mobile` v0.4.27 is an **Expo SDK 54 / React Native 0.81.5** app in the
bare workflow (committed `android/` tree), with the **New Architecture**
(`newArchEnabled=true`) and **Hermes** (`hermesEnabled=true`) enabled. Native
libraries come from npm dependencies (Hermes, React Native, Reanimated,
Worklets, Sentry, Fresco, etc.); there are no bundled binaries or project-local
`.so`/CMake files in the repository.

### Important: the reported root cause does not hold for v0.4.27

The published `app-release-fdroid.apk` was downloaded and inspected directly:

```bash
unzip -l app-release-fdroid.apk | grep -E 'lib/.*\.so' | awk '{print $4}' \
  | sed 's#lib/\([^/]*\)/.*#\1#' | sort | uniq -c
#       4 arm64-v8a
#       4 armeabi-v7a
#       4 x86
#       4 x86_64
```

All 22 `.so` files exist for every ABI (22 × 4 = 88 entries), and the 32-bit
files are valid `ELF 32-bit LSB shared object, ARM, EABI5`:

```bash
unzip -p app-release-fdroid.apk lib/armeabi-v7a/libhermes.so | file -
```

The manifest declares no `android.hardware.cpu.64bit` feature requirement.
`android/gradle.properties` at this tag already sets
`reactNativeArchitectures=armeabi-v7a,arm64-v8a,x86,x86_64`, and none of the
CI workflows pass a narrower `-PreactNativeArchitectures=` override.
Therefore the release APK is **not** 64-bit-only, and
`INSTALL_FAILED_NO_MATCHING_ABIS` on this exact artifact is not explained by
the source configuration. (A 32-bit install failure on a specific device can
still have other causes: a 64-bit-only device/OS, a corrupted download, or a
different APK being installed.)

## What changed anyway

The build path is now explicit, smaller, and regression-proof:

| File | Change |
|------|--------|
| `android/gradle.properties` | `reactNativeArchitectures=armeabi-v7a,arm64-v8a` (drops emulator-only x86 ABIs, ~halves APK size); heap 4 GB / metaspace 1 GB + `org.gradle.workers.max=2` to avoid OOM |
| `android/app/build.gradle` | explicit `ndk.abiFilters` from `enabledAbis`; optional `splits { abi { universalApk true } }` behind `-Pandroid.enableAbiSplits=true` (default off so `app-release.apk` paths in existing workflows/F-Droid metadata stay valid) |
| `plugins/withAbiSupport.js` | Expo config plugin that re-applies all of the above after `npx expo prebuild` |
| `app.json` | registers `./plugins/withAbiSupport` |
| `.github/workflows/build-arm32.yml` | secret-free CI build + ABI verification + artifact upload |
| `scripts/build-arm-apk.sh` | one-command local build with the same verification |

Signing needs no author secrets: `signingConfigs.release` falls back to
`signingConfigs.debug`, and the workflow/script generate the standard
`android/app/debug.keystore` (store password `android`, alias
`androiddebugkey`) when `RELEASE_STORE_FILE` is unset.

## Build locally

Prerequisites: JDK 17, Android SDK (API 35 + NDK auto-download), Node 20+.

```bash
export ANDROID_HOME=/path/to/Android/Sdk
npm install --legacy-peer-deps
npx expo prebuild --platform android --no-install   # plugin applies ABI config

# generate a local debug keystore (only if RELEASE_STORE_FILE is unset)
keytool -genkeypair -v -keystore android/app/debug.keystore \
  -storepass android -alias androiddebugkey -keypass android \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Android Debug,O=Android,C=US"

cd android && ./gradlew assembleRelease
```

Or all in one:

```bash
ANDROID_HOME=/path/to/Android/Sdk ./scripts/build-arm-apk.sh
```

Output (universal, installs on 32-bit and 64-bit ARM):

```
android/app/build/outputs/apk/release/app-release.apk
```

To also emit per-ABI APKs:

```bash
PER_ABI=1 ANDROID_HOME=/path/to/Android/Sdk ./scripts/build-arm-apk.sh
# or: cd android && ./gradlew assembleRelease -Pandroid.enableAbiSplits=true
```

```
android/app/build/outputs/apk/release/app-armeabi-v7a-release.apk   # 32-bit only
android/app/build/outputs/apk/release/app-arm64-v8a-release.apk     # 64-bit only
android/app/build/outputs/apk/release/app-universal-release.apk     # both
```

Verify before shipping:

```bash
unzip -l android/app/build/outputs/apk/release/app-release.apk \
  | grep -E 'lib/(armeabi-v7a|arm64-v8a)/libhermes.so'
```

## Build in GitHub Actions

Run **Actions → Build universal + 32-bit ARM APK → Run workflow** (no secrets
required). Artifacts: `app-release-arm-universal` and
`app-release-arm-per-abi`. The workflow also fails loudly if the generated
config or the built APK ever loses `armeabi-v7a`.
