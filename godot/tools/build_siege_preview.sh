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
grep -qx 'renderer/rendering_method="mobile"' project.godot \
  || { echo 'ERROR: project.godot must set renderer/rendering_method="mobile"' >&2; exit 1; }
grep -qx 'rendering_device/fallback_to_opengl3=true' project.godot \
  || { echo 'ERROR: project.godot must enable the OpenGL fallback (0.31.72)' >&2; exit 1; }
grep -qx 'config/project_settings_override="user://renderer.cfg"' project.godot \
  || { echo 'ERROR: project.godot must read user://renderer.cfg (BootGuard OpenGL switch)' >&2; exit 1; }

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

# The Siege build ships on Vulkan (Kevin's decision; the OpenGL build froze on his S21 Ultra), with an OpenGL fallback
# for phones whose Vulkan fails (0.31.72, Kevin: Godot's own fallback + BootGuard's switch via user://renderer.cfg).
# Decode Godot's binary project settings instead of relying on binutils `strings`, which is absent
# on the deployment VM. Malformed or missing settings fail closed.
python3 - "$OUT" <<'PY'
import struct
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as apk:
    packed = apk.read("assets/project.binary")

def u32(data, offset):
    if offset + 4 > len(data):
        raise ValueError("truncated uint32")
    return struct.unpack_from("<I", data, offset)[0]

if packed[:4] != b"ECFG" or len(packed) < 8:
    raise SystemExit("ERROR: malformed assets/project.binary header")

props = {}
offset = 8  # ECFG magic + binary format version
try:
    while offset < len(packed):
        key_len = u32(packed, offset)
        offset += 4
        key_end = offset + key_len
        if key_end > len(packed):
            raise ValueError("truncated key")
        key = packed[offset:key_end].decode("utf-8")
        offset = key_end
        value_len = u32(packed, offset)
        offset += 4
        value_end = offset + value_len
        if value_end > len(packed) or key in props:
            raise ValueError("truncated value or duplicate key")
        props[key] = packed[offset:value_end]
        offset = value_end
except (UnicodeDecodeError, ValueError) as exc:
    raise SystemExit(f"ERROR: malformed assets/project.binary: {exc}") from exc

def string_setting(key):
    value = props.get(key, b"")
    if len(value) < 8 or u32(value, 0) != 4:  # Godot Variant::STRING
        raise ValueError(f"{key} is missing or is not a String")
    size = u32(value, 4)
    padded = (size + 3) & ~3
    if len(value) != 8 + padded or any(value[8 + size:]):
        raise ValueError(f"{key} has malformed String data")
    return value[8:8 + size].decode("utf-8")

def bool_setting(key):
    value = props.get(key, b"")
    if len(value) != 8 or u32(value, 0) != 1:  # Godot Variant::BOOL
        raise ValueError(f"{key} is missing or is not a bool")
    raw = u32(value, 4)
    if raw not in (0, 1):
        raise ValueError(f"{key} has malformed bool data")
    return bool(raw)

try:
    renderer = string_setting("rendering/renderer/rendering_method")
    fallback = bool_setting("rendering/rendering_device/fallback_to_opengl3")
    override = string_setting("application/config/project_settings_override")
except (UnicodeDecodeError, ValueError) as exc:
    raise SystemExit(f"ERROR: APK renderer settings could not be verified: {exc}") from exc
if renderer != "mobile" or not fallback or override != "user://renderer.cfg":
    print(f"ERROR: APK renderer {renderer!r}, fallback {fallback}, override {override!r}; expected Vulkan mobile + "
          "OpenGL fallback + user://renderer.cfg", file=sys.stderr)
    raise SystemExit(1)
print("Verified APK renderer: Vulkan mobile, OpenGL fallback on, renderer switch file user://renderer.cfg")
PY
echo "OK  $OUT  ($(du -h "$OUT" | cut -f1), Vulkan + OpenGL fallback, signed with $KS_ALIAS)"
sha256sum "$OUT"
