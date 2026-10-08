#!/bin/bash
# Fatebound trailer 6: render one staged run of tools/trailer6_shots.gd with Movie Maker (30 fps) to /tmp/trailer6/<run>.avi.
#   tools/trailer6_render.sh <run> [W H]        (default 1920 1080; e.g. 640 360 for a quick look)
#   SCRIPT=res://tools/trailer4_shots.gd SHOT=golden tools/trailer6_render.sh golden     (trailer 4's gold title shot)
# A TEMPORARY godot/override.cfg sets the window size (the project's 420x780 phone window beats --resolution in Movie
# Maker) and a worker pool big enough not to stall on pipeline compiles; it is removed afterwards and must never be
# committed or exported. Godot hangs on exit after Movie Maker here, so the run is stopped once it prints SHOT_DONE.
# Needs an X display at least W x H (Xvfb :98 -screen 0 2560x1440x24) and GODOT (the editor binary).
set -u
GODOT=${GODOT:-$HOME/godot/Godot_v4.7.2-stable_linux.x86_64}
RUN=$1
W=${2:-1920}
H=${3:-1080}
cd "$(dirname "$0")/.."
mkdir -p /tmp/trailer6 /tmp/trailer4
cat > override.cfg <<CFG
[display]
window/size/viewport_width=$W
window/size/viewport_height=$H
window/size/window_width_override=$W
window/size/window_height_override=$H
window/handheld/orientation=0
[threading]
worker_pool/max_threads=6
[editor]
movie_writer/mjpeg_quality=0.95
CFG
trap 'rm -f override.cfg' EXIT
OUT=/tmp/trailer6/${RUN}${SUFFIX:-}.avi
LOG=/tmp/trailer6/${RUN}${SUFFIX:-}.log
RUN=$RUN FB_FORCE_HQ=1 DISPLAY=${DISPLAY:-:98} "$GODOT" --rendering-method mobile --fixed-fps 30 --write-movie "$OUT" \
	--path . -s "${SCRIPT:-res://tools/trailer6_shots.gd}" > "$LOG" 2>&1 &
PID=$!
while kill -0 $PID 2>/dev/null; do
	if grep -q SHOT_DONE "$LOG"; then sleep 4; kill $PID 2>/dev/null; break; fi
	sleep 2
done
wait $PID 2>/dev/null
grep -E "SHOT_DONE|SCRIPT ERROR|Parse Error" "$LOG" | head -5
ls -la "$OUT" 2>/dev/null
