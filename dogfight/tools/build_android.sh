#!/usr/bin/env bash
# Builds a sideloadable Android APK of the dogfight project (preset "Android Preview",
# package com.squadronskies.preview). This is a test build, not a store build.
#
#   GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 \
#   ANDROID_HOME=/path/to/android-sdk \
#   KEYSTORE=/path/to/your.keystore KS_ALIAS=alias KS_PASS=password \
#   tools/build_android.sh [output.apk]
#
# Needs: Godot + its matching Android export templates
# (~/.local/share/godot/export_templates/<version>), JDK 17+, and an Android SDK
# with platform-tools and build-tools.
#
# Signing: Android only installs an update over an existing install when both
# are signed with the same key. Keep one keystore and pass it every time. With
# no KEYSTORE set, a throwaway key is generated next to the APK (build/ is
# git-ignored); builds signed with it cannot update builds signed with another.
# Never use a Play upload key here.
set -euo pipefail

GODOT="${GODOT:-godot}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
OUT="${1:-$HERE/build/SquadronSkies-preview.apk}"
mkdir -p "$(dirname "$OUT")" build

"$GODOT" --version >/dev/null 2>&1 || { echo "Set GODOT=/path/to/godot" >&2; exit 2; }
: "${ANDROID_HOME:?set ANDROID_HOME to your Android SDK}"
APKSIGNER=$(ls -d "$ANDROID_HOME"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)
[ -n "$APKSIGNER" ] || { echo "apksigner not found under $ANDROID_HOME/build-tools" >&2; exit 2; }

KEYSTORE="${KEYSTORE:-$HERE/build/throwaway-preview.keystore}"
KS_ALIAS="${KS_ALIAS:-preview}"
KS_PASS="${KS_PASS:-preview-only}"
if [ ! -f "$KEYSTORE" ]; then
  echo "No keystore at $KEYSTORE: generating a throwaway one."
  keytool -genkeypair -keystore "$KEYSTORE" -alias "$KS_ALIAS" -storepass "$KS_PASS" -keypass "$KS_PASS" \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Squadron Skies Preview" >/dev/null 2>&1
fi

# Godot refuses to export for Android without SDK/JDK paths in its editor settings.
VERSION_MM=$("$GODOT" --version | cut -d. -f1,2)
SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/godot/editor_settings-${VERSION_MM}.tres"
JDK="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"
mkdir -p "$(dirname "$SETTINGS")"
if [ -f "$SETTINGS" ]; then
  sed -i -e "s|^export/android/java_sdk_path = .*|export/android/java_sdk_path = \"$JDK\"|" \
         -e "s|^export/android/android_sdk_path = .*|export/android/android_sdk_path = \"$ANDROID_HOME\"|" "$SETTINGS"
  grep -q '^export/android/android_sdk_path' "$SETTINGS" || \
    printf 'export/android/java_sdk_path = "%s"\nexport/android/android_sdk_path = "%s"\n' "$JDK" "$ANDROID_HOME" >> "$SETTINGS"
else
  printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\nexport/android/java_sdk_path = "%s"\nexport/android/android_sdk_path = "%s"\n' \
    "$JDK" "$ANDROID_HOME" > "$SETTINGS"
fi

echo "Importing assets..."
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
echo "Exporting (release template)..."
# Release template = real frame rates. The signing key comes from the environment
# so no credentials are ever written into export_presets.cfg.
GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE" \
GODOT_ANDROID_KEYSTORE_RELEASE_USER="$KS_ALIAS" \
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$KS_PASS" \
"$GODOT" --headless --path . --export-release "Android Preview" "$OUT" >build/export.log 2>&1 \
  || { tail -30 build/export.log; exit 1; }
[ -s "$OUT" ] || { echo "Export produced no APK:"; tail -30 build/export.log; exit 1; }
rm -f "$OUT.idsig"

"$APKSIGNER" verify --verbose "$OUT" | grep -E "^Verifie[sd]" | head -4
echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
