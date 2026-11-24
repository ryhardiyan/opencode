#!/usr/bin/env bash
# Build an APK that installs on both 32-bit (armeabi-v7a) and 64-bit
# (arm64-v8a) Android devices. No author keystore/secrets required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

: "${ANDROID_HOME:?Set ANDROID_HOME to your Android SDK path}"
export ANDROID_HOME
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

if [[ ! -d node_modules ]]; then
  npm install --legacy-peer-deps
fi

# Regenerate the native project so plugins/withAbiSupport.js re-applies the
# ABI config. Set SKIP_PREBUILD=1 to build the committed android/ tree as-is.
if [[ "${SKIP_PREBUILD:-0}" != "1" ]]; then
  npx expo prebuild --platform android --no-install
fi

# The release build falls back to this debug keystore when RELEASE_STORE_FILE
# is not set (see signingConfigs in android/app/build.gradle).
if [[ ! -f android/app/debug.keystore ]]; then
  keytool -genkeypair -v -keystore android/app/debug.keystore \
    -storepass android -alias androiddebugkey -keypass android \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US"
fi

EXTRA_GRADLE_ARGS=()
if [[ "${PER_ABI:-0}" == "1" ]]; then
  EXTRA_GRADLE_ARGS+=("-Pandroid.enableAbiSplits=true")
fi

(cd android && ./gradlew assembleRelease "${EXTRA_GRADLE_ARGS[@]}")

UNIVERSAL="android/app/build/outputs/apk/release/app-release.apk"
echo "Verifying $UNIVERSAL ..."
LIBS="$(unzip -l "$UNIVERSAL")"
case "$LIBS" in
  *'lib/armeabi-v7a/libhermes.so'*) ;;
  *) echo "ERROR: missing 32-bit (armeabi-v7a) libs in $UNIVERSAL" >&2; exit 1 ;;
esac
case "$LIBS" in
  *'lib/arm64-v8a/libhermes.so'*) ;;
  *) echo "ERROR: missing 64-bit (arm64-v8a) libs in $UNIVERSAL" >&2; exit 1 ;;
esac
echo "OK: 32-bit and 64-bit ARM native libs are both present."
echo "APK: $ROOT/$UNIVERSAL"

if [[ "${PER_ABI:-0}" == "1" ]]; then
  echo "Also produced:"
  ls -lh android/app/build/outputs/apk/release/app-{armeabi-v7a,arm64-v8a,universal}-release.apk
fi
