#!/usr/bin/env bash
# Builds the Grapeshot prototype APK (package com.fatebound.grapeshot.proto, preset
# "Android Preview") and signs it with a DEBUG key you pass in. This is a throwaway prototype
# identity: never sign it with the Fatebound preview key or the Play upload key.
#
# Usage:
#   GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 ANDROID_HOME=/path/to/android-sdk \
#   KEYSTORE=/path/to/debug.keystore grapeshot/tools/build_preview.sh [output.apk]
#
# Needs: Godot 4.7.2 with its Android export templates in
# ~/.local/share/godot/export_templates/4.7.2.stable, a JDK, and Android build-tools
# (zipalign, apksigner) plus platform-tools under ANDROID_HOME.
# Make a debug key once with:
#   keytool -genkeypair -keystore debug.keystore -storepass android -keypass android \
#     -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Debug"
set -euo pipefail

GODOT="${GODOT:-godot}"
KEYSTORE="${KEYSTORE:?set KEYSTORE to a debug keystore (see the header of this script)}"
KS_ALIAS="${KS_ALIAS:-androiddebugkey}"
KS_PASS="${KS_PASS:-android}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"

ver=$(sed -n 's/^version\/name="\(.*\)"$/\1/p' export_presets.cfg | tail -1)
OUT="${1:-$HERE/build/Grapeshot-Prototype-${ver}.apk}"

[ -f "$KEYSTORE" ] || { echo "Keystore not found: $KEYSTORE" >&2; exit 2; }
"$GODOT" --version >/dev/null 2>&1 || { echo "Set GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64" >&2; exit 2; }

find_tool() {
  if command -v "$1" >/dev/null 2>&1; then command -v "$1"; return; fi
  ls -d "${ANDROID_HOME:-/nonexistent}"/build-tools/*/"$1" 2>/dev/null | sort -V | tail -1
}
ZIPALIGN=$(find_tool zipalign); APKSIGNER=$(find_tool apksigner)
[ -n "$ZIPALIGN" ] && [ -n "$APKSIGNER" ] || { echo "zipalign/apksigner not found (PATH or ANDROID_HOME/build-tools)" >&2; exit 2; }

# Godot refuses to export Android without SDK and JDK paths in its editor settings.
SETTINGS="$HOME/.config/godot/editor_settings-4.7.tres"
if [ ! -f "$SETTINGS" ] || ! grep -q 'export/android/android_sdk_path' "$SETTINGS"; then
  JDK="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"
  mkdir -p "$(dirname "$SETTINGS")"
  printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\nexport/android/java_sdk_path="%s"\nexport/android/android_sdk_path="%s"\n' \
    "$JDK" "${ANDROID_HOME:?set ANDROID_HOME to your Android SDK}" > "$SETTINGS"
  echo "Wrote $SETTINGS"
fi

mkdir -p build
echo "Importing..."
"$GODOT" --headless --editor --path . --import >/dev/null 2>&1 || true
echo "Exporting ${ver}..."
"$GODOT" --headless --path . --export-debug "Android Preview" "$HERE/build/unsigned.apk" >build/export.log 2>&1 \
  || { tail -20 build/export.log; exit 1; }
[ -s build/unsigned.apk ] || { echo "Export produced no APK:" >&2; tail -20 build/export.log; exit 1; }
"$ZIPALIGN" -f -p 4 build/unsigned.apk build/aligned.apk
"$APKSIGNER" sign --ks "$KEYSTORE" --ks-key-alias "$KS_ALIAS" --ks-pass "pass:$KS_PASS" --key-pass "pass:$KS_PASS" \
  --out "$OUT" build/aligned.apk
rm -f "$OUT.idsig" build/unsigned.apk build/aligned.apk
"$APKSIGNER" verify "$OUT" && echo "Built $OUT"
