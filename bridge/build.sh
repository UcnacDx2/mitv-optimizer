#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="${ANDROID_SDK_ROOT:-/opt/coding-tools-workspace/tools/android-sdk}"
PLATFORM="$SDK/platforms/android-35/android.jar"
TOOLS="$SDK/build-tools/35.0.0"
KEYSTORE="${HOME}/.android/debug.keystore"

cd "$ROOT"
rm -rf classes dex classes.dex unsigned.apk aligned.apk MiTVHomeBridge.apk
mkdir -p classes dex "$(dirname "$KEYSTORE")"

if [[ ! -f "$KEYSTORE" ]]; then
  keytool -genkeypair -v \
    -keystore "$KEYSTORE" \
    -storepass android -alias androiddebugkey -keypass android \
    -dname 'CN=Android Debug,O=Android,C=US' \
    -keyalg RSA -keysize 2048 -validity 10000 >/dev/null
fi

javac -source 8 -target 8 -classpath "$PLATFORM" -d classes \
  src/com/ucnacdx2/mitvhomebridge/MainActivity.java
"$TOOLS/d8" --lib "$PLATFORM" --min-api 21 --output dex \
  classes/com/ucnacdx2/mitvhomebridge/MainActivity.class
cp dex/classes.dex classes.dex

"$TOOLS/aapt" package -f -M AndroidManifest.xml -S res -I "$PLATFORM" -F unsigned.apk
"$TOOLS/aapt" add unsigned.apk classes.dex
"$TOOLS/zipalign" -f 4 unsigned.apk aligned.apk
"$TOOLS/apksigner" sign \
  --ks "$KEYSTORE" --ks-key-alias androiddebugkey \
  --ks-pass pass:android --key-pass pass:android \
  --out MiTVHomeBridge.apk aligned.apk

"$TOOLS/apksigner" verify --verbose --print-certs MiTVHomeBridge.apk
sha256sum MiTVHomeBridge.apk
