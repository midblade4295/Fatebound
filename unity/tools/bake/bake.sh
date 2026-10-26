#!/bin/sh
# Bakes the Godot scenes/resources the game loads (.glb .gltf .scn .tscn .res .tres under godot/assets) into
# unity/Assets/Resources/res/<path>.bytes for GUI/Scene3D/BakedLoader.cs (format: the header of bake_resources.gd).
#   unity/tools/bake/bake.sh                       # everything (~420 files, ~150 MB, ~2 min)
#   unity/tools/bake/bake.sh res://assets/meshy/knight assets/kings/king_blue_fat.glb   # some files or folders
#   unity/tools/bake/bake.sh --dry --verbose       # report sizes and the classes/properties met, write nothing
# Runs Godot headless on the game's project with its import cache (.godot); one Godot at a time on this machine.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
GODOT=${GODOT:-/root/godot/Godot_v4.7.2-stable_linux.x86_64}
OUT="$REPO/unity/Assets/Resources/res"
case " $* " in *" --dry "*) ;; *)
	# the full bake writes ~150 MB: refuse when the disk is nearly full
	FREE=$(df -Pk "$REPO/unity" | awk 'NR==2 {print $4}')
	if [ "$FREE" -lt 1048576 ]; then echo "bake: less than 1 GB free on $(df -P "$REPO/unity" | awk 'NR==2 {print $6}'), not baking" >&2; exit 1; fi
esac
LOG=${TMPDIR:-/tmp}/fb-bake.log
ST=0
timeout 1800 "$GODOT" --headless --path "$REPO/godot" -s "$HERE/bake_resources.gd" -- --out "$OUT" "$@" > "$LOG" 2>&1 || ST=$?
grep -v '^Godot Engine\|^$' "$LOG" || true
echo "bake: $(du -sh "$OUT" | cut -f1) in Assets/Resources/res, $(df -h "$REPO/unity" | awk 'NR==2 {print $4}') free"
exit $ST
