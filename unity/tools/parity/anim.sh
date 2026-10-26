#!/bin/sh
# Skeletal animation (GUI/Scene3D: Skeleton3D, BoneAttachment3D, SkeletonModifier3D, Animation, AnimationLibrary,
# AnimationPlayer) against Godot: the same scene and frame sequence printed by Godot (godot_anim.gd, run in the game's
# project for its real Meshy knight rig and animation libraries, at --fixed-fps 60) and by the C# port (guitest anim,
# which also rebuilds the real libraries from the stored properties Godot dumps to $OUT/anim_dump.bin), diffed.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
GODOT=${GODOT:-/root/godot/Godot_v4.7.2-stable_linux.x86_64}
DOTNET=${DOTNET:-dotnet}
OUT=${TMPDIR:-/tmp}/fb-anim
mkdir -p "$OUT"
FB_ANIM_OUT="$OUT" timeout 300 "$GODOT" --headless --fixed-fps 60 --path "$REPO/godot" -s "$HERE/godot_anim.gd" 2> "$OUT/godot_err.txt" \
	| grep -v '^Godot Engine\|^$' > "$OUT/godot.txt"
"$DOTNET" build "$HERE/../guitest" -nologo -v q > /dev/null
FB_ANIM_OUT="$OUT" "$DOTNET" /tmp/fb-guitest/bin/net8.0/guitest.dll anim > "$OUT/cs.txt" 2> "$OUT/cs_err.txt"
if diff "$OUT/godot.txt" "$OUT/cs.txt"; then echo "anim: $(wc -l < "$OUT/cs.txt") lines identical"; else exit 1; fi
