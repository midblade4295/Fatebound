#!/usr/bin/env bash
# Build + verify the signed Play release AAB (com.fatebound.game, preset "Android Play Store").
# Private signing only: the keystore must live OUTSIDE the repository. Never use the old
# android/keystore/upload.jks.b64 key from git history.
#
# Required env:
#   GODOT                        Godot 4.7.2 editor binary (matching Android templates installed)
#   VERSION_CODE, VERSION_NAME   e.g. 25 / 1.2.1-siege-r5 (must exceed every code already on Play)
#   PLAY_UPLOAD_KEYSTORE_PATH    PKCS12/JKS upload keystore (outside the repo)
#   PLAY_UPLOAD_KEY_ALIAS        key alias
#   PLAY_UPLOAD_KEY_PASSWORD     key password (Godot uses one password for store + key; PKCS12 has one)
# Optional: PLAY_GAMES_APP_ID (the Play Games Services Game ID, digits; or set godot_play_game_services/game_id on the
#           preset -- without either the bundle has no Google Play Games, see godot/PLAY_GAMES_HANDOFF.md),
#           EXPECTED_UPLOAD_CERT_SHA256 (defaults to the keystore's own certificate),
#           BUNDLETOOL_JAR, OUT (default godot/build/Fatebound-Siege-Play-vc$VERSION_CODE-release.aab)
set -euo pipefail
: "${GODOT:?}" "${VERSION_CODE:?}" "${VERSION_NAME:?}" "${PLAY_UPLOAD_KEYSTORE_PATH:?}" "${PLAY_UPLOAD_KEY_ALIAS:?}" "${PLAY_UPLOAD_KEY_PASSWORD:?}"
[[ "$VERSION_CODE" =~ ^[0-9]+$ ]] || { echo "VERSION_CODE must be an integer" >&2; exit 1; }
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KS="$(realpath "$PLAY_UPLOAD_KEYSTORE_PATH")"
case "$KS" in "$ROOT"/*) echo "Refusing a keystore inside the repository: $KS" >&2; exit 1;; esac
OUT="${OUT:-$ROOT/godot/build/Fatebound-Siege-Play-vc${VERSION_CODE}-release.aab}"
PRESETS="$ROOT/godot/export_presets.cfg"

# Set version on the Play preset (preset.0) only.
python3 - "$PRESETS" "$VERSION_CODE" "$VERSION_NAME" <<'PY'
import sys,re
path,code,name=sys.argv[1:]
s=open(path).read(); head,sep,rest=s.partition('[preset.1]')
assert 'name="Android Play Store"' in head and 'package/unique_name="com.fatebound.game"' in head
head=re.sub(r'(?m)^version/code=.*$','version/code='+code,head,count=1)
head=re.sub(r'(?m)^version/name=.*$','version/name="'+name+'"',head,count=1)
open(path,'w').write(head+sep+rest)
PY

if [ -z "${EXPECTED_UPLOAD_CERT_SHA256:-}" ]; then
  EXPECTED_UPLOAD_CERT_SHA256="$(keytool -list -v -keystore "$KS" -alias "$PLAY_UPLOAD_KEY_ALIAS" -storepass:env PLAY_UPLOAD_KEY_PASSWORD | sed -n 's/^\s*SHA256: *//p' | head -1)"
fi
export EXPECTED_VERSION_CODE="$VERSION_CODE" EXPECTED_VERSION_NAME="$VERSION_NAME" EXPECTED_UPLOAD_CERT_SHA256

export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KS"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$PLAY_UPLOAD_KEY_ALIAS"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$PLAY_UPLOAD_KEY_PASSWORD"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
"$GODOT" --headless --editor --path "$ROOT/godot" --import
"$GODOT" --headless --path "$ROOT/godot" --install-android-build-template --export-release "Android Play Store" "$OUT"
unset GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD

python3 "$ROOT/godot/tools/verify_play_bundle.py" "$OUT"
jarsigner -verify "$OUT"
keytool -printcert -jarfile "$OUT"
( cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
echo "BUILT $OUT"
