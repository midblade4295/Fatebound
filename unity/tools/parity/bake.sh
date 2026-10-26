#!/bin/sh
# Baked assets (tools/bake -> GUI/Scene3D/BakedLoader.cs) against Godot: a representative set of the game's scenes and
# resources is baked, then dumped by Godot from its own load() (godot_bake.gd: the instantiated tree -- classes, names,
# owners, transforms, metadata -- mesh surfaces with an md5 of every surface_get_arrays() array, materials, skins,
# skeletons, animation libraries with track paths / key counts / first and last keys, particles with their curves and
# gradients, images, the terrain cache's script properties) and by the port from the .bytes (guitest bake, BakeTest.cs,
# which also runs the threaded load API over the set), diffed.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
GODOT=${GODOT:-/root/godot/Godot_v4.7.2-stable_linux.x86_64}
DOTNET=${DOTNET:-$(command -v dotnet || echo /root/.dotnet/dotnet)}
OUT=${TMPDIR:-/tmp}/fb-bake-parity
mkdir -p "$OUT"
SET="res://assets/kaykit/heroes/Knight.glb
res://assets/kaykit/heroes/Skeleton_Rogue.glb
res://assets/kaykit/anim/Rig_Medium_General.glb
res://assets/kaykit/weapons/bow_withString.gltf
res://assets/kaykit/forest/Rock_1_E_Color1.gltf
res://assets/meshy/knight/rigged.glb
res://assets/meshy/knight/anims_g.res
res://assets/meshy/knight/anims_mb.res
res://assets/meshy/weapons/ashwood_bow.glb
res://assets/meshy/towers/tower_king.glb
res://assets/meshy/castle/royal_gatehouse.glb
res://assets/meshy/wyrm/wyrm.glb
res://assets/kings/king_blue_fat.glb
res://assets/ui/v2/chests/gold.scn
res://assets/vfx/effectblocks/explosion_heavy.tscn
res://assets/vfx/effectblocks/explosion_light.tscn
res://assets/terrain/height.res
res://assets/terrain/pathmask.res
res://assets/terrain/cache.res"
# shellcheck disable=SC2086
"$HERE/../bake/bake.sh" $SET > "$OUT/bake.txt"
# shellcheck disable=SC2086
timeout 600 "$GODOT" --headless --path "$REPO/godot" -s "$HERE/godot_bake.gd" -- $SET 2> "$OUT/godot_err.txt" \
	| grep -v '^Godot Engine\|^$' > "$OUT/godot.txt"
"$DOTNET" build "$HERE/../guitest" -nologo -v q > /dev/null
# shellcheck disable=SC2086
"$DOTNET" /tmp/fb-guitest/bin/net8.0/guitest.dll bake $SET > "$OUT/cs.txt" 2> "$OUT/cs_err.txt" || { cat "$OUT/cs_err.txt"; exit 1; }
grep '^threaded\|^unmapped' "$OUT/cs_err.txt" || true
if diff "$OUT/godot.txt" "$OUT/cs.txt" > "$OUT/diff.txt"; then echo "bake: $(wc -l < "$OUT/cs.txt") lines identical ($(echo "$SET" | wc -l) files)"
else echo "bake: $(grep -c '^<' "$OUT/diff.txt") lines differ (see $OUT/diff.txt)"; exit 1; fi
