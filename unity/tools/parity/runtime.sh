#!/bin/sh
# The GDScript runtime (Sim/Script: Var, GDict, GArray, str(), %, JSON, hash(), String methods, random) against Godot:
# the same cases printed by Godot (godot_runtime.gd) and by the C# runtime (guitest runtime), diffed.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
GODOT=${GODOT:-/root/godot/Godot_v4.7.2-stable_linux.x86_64}
OUT=${TMPDIR:-/tmp}/fb-runtime
mkdir -p "$OUT"
(cd "$HERE" && timeout 120 "$GODOT" --headless -s godot_runtime.gd 2>&1) | grep -v '^Godot Engine\|^$\|^   at: \|^   GDScript backtrace\|^       \[' > "$OUT/godot.txt"
dotnet build "$HERE/../guitest" -nologo -v q > /dev/null
dotnet /tmp/fb-guitest/bin/net8.0/guitest.dll runtime > "$OUT/cs.txt" 2>&1
if diff "$OUT/godot.txt" "$OUT/cs.txt"; then echo "runtime: $(wc -l < "$OUT/cs.txt") lines identical"; else exit 1; fi
