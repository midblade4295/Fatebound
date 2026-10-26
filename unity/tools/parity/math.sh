#!/bin/sh
# Godot's math value types (Vector2/2i/3/3i/4/4i, Basis, Quaternion, Transform3D, AABB, Plane, Projection, Transform2D,
# Rect2, Color) against the C# ports (Sim/Core, GUI/Core/Math2DGodot.cs): the same cases printed by Godot (godot_math.gd)
# and by guitest (`math`, MathTest.cs), diffed. Results only (stdout); the engine's error/warning text is not compared.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
GODOT=${GODOT:-/root/godot/Godot_v4.7.2-stable_linux.x86_64}
DOTNET=${DOTNET:-$(command -v dotnet || echo /root/.dotnet/dotnet)}
OUT=${TMPDIR:-/tmp}/fb-math
mkdir -p "$OUT"
(cd "$HERE" && timeout 300 "$GODOT" --headless -s godot_math.gd 2>/dev/null) | grep '|' > "$OUT/godot.txt"
"$DOTNET" build "$HERE/../guitest" -nologo -v q > /dev/null
"$DOTNET" /tmp/fb-guitest/bin/net8.0/guitest.dll math 2>/dev/null > "$OUT/cs.txt"
if diff "$OUT/godot.txt" "$OUT/cs.txt" > "$OUT/diff.txt"; then echo "math: $(wc -l < "$OUT/cs.txt") lines identical"; else echo "math: $(grep -c '^<' "$OUT/diff.txt") lines differ (see $OUT/diff.txt)"; exit 1; fi
