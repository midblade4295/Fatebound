#!/usr/bin/env bash
# Builds the Siege preview APK (package com.fatebound.kaykitrebuild, preset "Android KayKit Rebuild")
# and signs it with Kevin's PREVIEW key so it installs over earlier preview builds without an
# uninstall. Never use this with the Play upload key.
#
# Usage (repo root or godot/):
#   GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 \
#   KEYSTORE=$HOME/keys/fatebound-siege-preview.jks \
#   godot/tools/build_siege_preview.sh [output.apk]
#
# Needs: Godot 4.7.2 + its Android export templates (~/.local/share/godot/export_templates/4.7.2.stable),
# JDK 17+, Android SDK (ANDROID_HOME) for Godot's export check, and zipalign/apksigner (build-tools).
set -euo pipefail

GODOT="${GODOT:-godot}"
KEYSTORE="${KEYSTORE:-$HOME/fatebound-siege-preview.jks}"
KS_ALIAS="${KS_ALIAS:-fbpreview}"
KS_PASS="${KS_PASS:-fbpreview}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"          # .../godot
cd "$HERE"

ver=$(sed -n 's/^version\/name="\(.*\)"$/\1/p' export_presets.cfg | tail -1)
OUT="${1:-$HERE/build/Fatebound-Siege-${ver}.apk}"

[ -f "$KEYSTORE" ] || { echo "Preview keystore not found: $KEYSTORE (set KEYSTORE=...)" >&2; exit 2; }
"$GODOT" --version >/dev/null 2>&1 || { echo "Set GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64" >&2; exit 2; }

find_tool() {  # zipalign / apksigner: PATH first, then the newest Android build-tools
  if command -v "$1" >/dev/null 2>&1; then command -v "$1"; return; fi
  ls -d "${ANDROID_HOME:-/nonexistent}"/build-tools/*/"$1" 2>/dev/null | sort -V | tail -1
}
ZIPALIGN=$(find_tool zipalign); APKSIGNER=$(find_tool apksigner)
[ -n "$ZIPALIGN" ] && [ -n "$APKSIGNER" ] || { echo "zipalign/apksigner not found (PATH or ANDROID_HOME/build-tools)" >&2; exit 2; }

# Godot refuses to export Android without SDK/JDK paths in its editor settings.
SETTINGS="$HOME/.config/godot/editor_settings-4.7.tres"
if [ ! -f "$SETTINGS" ] || ! grep -q 'export/android/android_sdk_path' "$SETTINGS"; then
  JDK="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"
  mkdir -p "$(dirname "$SETTINGS")"
  printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\nexport/android/java_sdk_path="%s"\nexport/android/android_sdk_path="%s"\n' \
    "$JDK" "${ANDROID_HOME:?set ANDROID_HOME to your Android SDK}" > "$SETTINGS"
  echo "Wrote $SETTINGS"
fi

mkdir -p build
echo "Importing assets..."
"$GODOT" --headless --editor --path . --import >/dev/null 2>&1 || true
echo "Exporting ${ver}..."
"$GODOT" --headless --path . --export-debug "Android KayKit Rebuild" "$HERE/build/unsigned.apk" >build/export.log 2>&1 \
  || { tail -20 build/export.log; exit 1; }
"$ZIPALIGN" -f -p 4 build/unsigned.apk build/aligned.apk
"$APKSIGNER" sign --ks "$KEYSTORE" --ks-key-alias "$KS_ALIAS" --ks-pass "pass:$KS_PASS" --key-pass "pass:$KS_PASS" \
  --out "$OUT" build/aligned.apk
rm -f "$OUT.idsig"
"$APKSIGNER" verify "$OUT"

# The Siege build must ship on Vulkan (Kevin's decision; the OpenGL build froze on his S21 Ultra).
unzip -p "$OUT" assets/project.binary | strings | grep -A1 'rendering_method.mobile' | tail -1 | grep -q gl_compat \
  && { echo "ERROR: APK renders with gl_compatibility; project.godot must keep rendering_method.mobile=\"mobile\"" >&2; exit 1; }
echo "OK  $OUT  ($(du -h "$OUT" | cut -f1), Vulkan, signed with $KS_ALIAS)"
sha256sum "$OUT"
