#!/bin/sh
# Mesh building and 3D resources (GUI/Scene3D: PrimitiveMeshes, SurfaceTool + mikktspace, ImmediateMesh, material /
# ParticleProcessMaterial / FastNoiseLite / NoiseTexture2D / CurveTexture defaults and data) against Godot: the same
# cases printed by Godot (godot_mesh.gd) and by the port (guitest mesh), diffed. FB_MESH_FULL=1 prints every element.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
GODOT=${GODOT:-/root/godot/Godot_v4.7.2-stable_linux.x86_64}
DOTNET=${DOTNET:-dotnet}
command -v "$DOTNET" > /dev/null 2>&1 || DOTNET=/root/.dotnet/dotnet
OUT=${TMPDIR:-/tmp}/fb-mesh
mkdir -p "$OUT"
(cd "$HERE" && timeout 300 "$GODOT" --headless -s godot_mesh.gd 2>&1) | grep -v '^Godot Engine\|^$\|^   at: \|^   GDScript backtrace\|^       \[' > "$OUT/godot.txt"
"$DOTNET" build "$HERE/../guitest" -nologo -v q > /dev/null
"$DOTNET" /tmp/fb-guitest/bin/net8.0/guitest.dll mesh "$OUT/godot.txt" > "$OUT/cs.txt" 2>&1
if diff "$OUT/godot.txt" "$OUT/cs.txt" > "$OUT/diff.txt"; then echo "mesh: $(wc -l < "$OUT/cs.txt") lines identical"
else echo "mesh: $(grep -c '^<' "$OUT/diff.txt") lines differ (see $OUT/diff.txt)"; exit 1; fi
