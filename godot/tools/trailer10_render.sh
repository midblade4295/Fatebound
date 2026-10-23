#!/bin/bash
# Fatebound trailer 10: record one take of tools/trailer10_shots.gd with Movie Maker (30 fps) to $OUTDIR/<run>.avi
# (MJPEG 0.95 with the game's own sound), or with SNAP=t1,t2,... just PNG stills at those times (no Movie Maker).
#   tools/trailer10_render.sh <run> [W H]        (default 1080 1920, a 9:16 phone; e.g. 540 960 for a quick look)
# As a phone shows it: the window is W x H but the game's own design size stays (420 x 780, stretched to the window --
# the HUD and the menus their phone size), unlike trailer 8's films (their design size the window's own). A TEMPORARY
# godot/override.cfg sets the window size (the project's 420x780 phone window beats --resolution in Movie Maker) and a
# worker pool big enough not to stall on pipeline compiles; it is removed afterwards and must never be committed or
# exported. Godot hangs on exit after Movie Maker here, so the run is stopped once it prints SHOT_DONE.
# Needs an X display at least W x H (Xvfb :98 -screen 0 1920x1080x24) and GODOT (the editor binary).
set -u
GODOT=${GODOT:-$HOME/godot/Godot_v4.7.2-stable_linux.x86_64}
RUN=$1
W=${2:-1080}
H=${3:-1920}
OUTDIR=${OUTDIR:-/tmp/trailer10}
cd "$(dirname "$0")/.."
mkdir -p "$OUTDIR"
cat > override.cfg <<CFG
[display]
window/size/window_width_override=$W
window/size/window_height_override=$H
[threading]
worker_pool/max_threads=6
[editor]
movie_writer/mjpeg_quality=0.95
CFG
trap 'rm -f override.cfg' EXIT
HQENV=FB_FORCE_HQ=1
[ "${NOHQ:-0}" = 1 ] && HQENV=NOHQ=1
LOG=$OUTDIR/${RUN}${SUFFIX:-}.log
if [ -n "${SNAP:-}" ]; then
	MOVIE=()
	OUT=""
else
	OUT=$OUTDIR/${RUN}${SUFFIX:-}.avi
	MOVIE=(--write-movie "$OUT")
fi
env RUN=$RUN OUT_DIR=$OUTDIR $HQENV DISPLAY=${DISPLAY:-:98} "$GODOT" --rendering-method mobile --fixed-fps 30 "${MOVIE[@]}" \
	--path . -s "${SCRIPT:-res://tools/trailer10_shots.gd}" > "$LOG" 2>&1 &
PID=$!
while kill -0 $PID 2>/dev/null; do
	if grep -q SHOT_DONE "$LOG"; then sleep 4; kill $PID 2>/dev/null; break; fi
	sleep 2
done
wait $PID 2>/dev/null
grep -E "REC_START|SHOT_DONE|SCRIPT ERROR|Parse Error" "$LOG" | head -5
[ -n "$OUT" ] && ls -la "$OUT" 2>/dev/null
exit 0
