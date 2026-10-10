#!/bin/bash
# End-to-end check of the content packs on desktop (0.31.95). Builds desktop-format packs (the "Content Pack (desktop
# test)" preset: same files as the Android packs, textures for a PC), makes a copy of the project without the packs'
# files -- what the installed build holds -- serves the packs from a local server with byte ranges, and starts the
# game three times:
#   1. nothing on the "phone": every pack downloads (one dropped connection on the way), is checked and mounted, the
#      menu comes up and every model in the start-up list loads;
#   2. again: nothing downloads;
#   3. one pack half there (an interrupted download): it resumes from where it stopped.
#   GODOT=... godot/tools/content_e2e.sh        (prints CONTENT_E2E PASS or FAIL)
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
GODOT=${GODOT:-$HOME/godot/Godot_v4.7.2-stable_linux.x86_64}
W=${E2E_DIR:-/tmp/fb_content_e2e}
PORT=${E2E_PORT:-8765}
USERDIR=$HOME/.local/share/godot/app_userdata/FateboundContentE2E
fail() { echo "CONTENT_E2E FAIL: $*"; exit 1; }
rm -rf "$W"; mkdir -p "$W/packs" "$W/proj/assets"
echo "== desktop packs"
CONTENT_OUT=$W/packs CONTENT_MANIFEST=$W/manifest.json CONTENT_PACK_PRESET="Content Pack (desktop test)" GODOT=$GODOT \
	python3 "$G/tools/content_packs.py" build > "$W/build.log" 2>&1 || { tail -20 "$W/build.log"; fail "pack build"; }
grep -E '^(ui|world|heroes|weapons|audio|manifest)' "$W/build.log"
echo "== the base build (the project without the packs' files)"
tar -C "$G" --exclude=./.godot --exclude=./build --exclude=./assets --exclude=./reports --exclude=./store-listing --exclude=./tests --exclude=./tools --exclude=./server -cf - . | tar -C "$W/proj" -xf -
[ -f "$W/proj/project.godot" ] || fail "project copy"
for d in branding fonts vfx; do cp -r "$G/assets/$d" "$W/proj/assets/"; done
cp "$W/manifest.json" "$W/proj/content/manifest.json"
sed -i 's/^config\/name=.*/config\/name="FateboundContentE2E"/' "$W/proj/project.godot"
timeout 600 "$GODOT" --headless --path "$W/proj" --import > "$W/import.log" 2>&1
rm -rf "$USERDIR"
python3 "$G/tools/range_server.py" "$W/packs" "$PORT" --drop-after 30000000 > "$W/server.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null' EXIT
sleep 1
run() { FB_CONTENT_URL=http://127.0.0.1:$PORT/ FB_BOOT_GUARD=1 FB_QUIT_WHEN_UP=1 timeout 900 "$GODOT" --headless --path "$W/proj" > "$W/$1.log" 2>&1; }
errors() { grep -E 'SCRIPT ERROR|Failed loading resource|Cannot open file|Failed to load|Parse Error' "$W/$1.log" | grep -v 'boot_diag' | head -5; }
echo "== 1: first start"
run first
grep -q "5 to download" "$W/first.log" || fail "first start: $(grep CONTENT "$W/first.log" | head -3)"
[ "$(grep -c 'downloaded and checked' "$W/first.log")" = 5 ] || fail "not every pack downloaded: $(grep CONTENT "$W/first.log" | tail -5)"
grep -q "dropped the connection" "$W/server.log" || fail "the server never dropped a connection"
grep -q "CONTENT trouble" "$W/first.log" || fail "the dropped connection was not noticed"
grep -q "CONTENT mounted 5 packs" "$W/first.log" || fail "not mounted"
grep -q "all preloaded" "$W/first.log" || fail "the menu never finished loading: $(tail -5 "$W/first.log")"
E=$(errors first); [ -z "$E" ] || fail "errors on the first start: $E"
# (6 hero models' imports name an older UID for their texture -- also in the full project, before the packs; ignored)
U=$(grep "invalid UID" "$W/first.log" | grep -vc "rigged_Image_0.jpg"); [ "$U" = 0 ] || fail "$U resources were found by path, not UID (content/uids.json not registered?)"
echo "== 2: second start"
run second
grep -q "5 on the phone, 0 to download" "$W/second.log" || fail "second start: $(grep CONTENT "$W/second.log" | head -3)"
grep -q "all preloaded" "$W/second.log" || fail "second start never finished loading"
echo "== 3: an interrupted download"
P=$(python3 -c "import json;print([p['file'] for p in json.load(open('$W/manifest.json'))['packs'] if p['name']=='weapons'][0])")
head -c 10000000 "$USERDIR/packs/$P" > "$USERDIR/packs/$P.part"; rm "$USERDIR/packs/$P"
run third
grep -q "weapons: 9.5 MB of" "$W/third.log" || fail "no resume: $(grep CONTENT "$W/third.log" | head -4)"
grep -q "1 to download" "$W/third.log" && grep -q "weapons downloaded and checked" "$W/third.log" || fail "resume did not finish"
grep -q "all preloaded" "$W/third.log" || fail "third start never finished loading"
grep CONTENT "$W/first.log" | head -3
echo "CONTENT_E2E PASS"
