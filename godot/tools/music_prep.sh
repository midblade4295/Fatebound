#!/usr/bin/env bash
# Prepare a song as the match music: loudness-normalised to -16 LUFS (MUSIC_GAIN in siege_mode.gd assumes it),
# stereo 44.1 kHz Ogg Vorbis q5, its last XF seconds crossfaded into its first so the loop doesn't jump.
#   tools/music_prep.sh Spooky_3.wav            -> godot/assets/music/match.ogg
set -euo pipefail
IN="${1:?song file}"; OUT="$(cd "$(dirname "$0")/.." && pwd)/assets/music/match.ogg"; XF="${XF:-1.5}"
TMP=$(mktemp -d)
ffmpeg -nostdin -v error -y -i "$IN" -ac 2 -ar 44100 -af loudnorm=I=-16:TP=-1.5:LRA=11 -c:a pcm_s16le "$TMP/n.wav"
python3 - "$TMP/n.wav" "$TMP/loop.wav" "$XF" <<'PY'
import sys, wave, numpy as np
src, dst, xf = sys.argv[1], sys.argv[2], float(sys.argv[3])
w = wave.open(src); sr = w.getframerate(); ch = w.getnchannels()
x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32).reshape(-1, ch)
n = int(xf * sr)
head, body = x[:n], x[n:]
t = np.linspace(0.0, 1.0, n)[:, None]
body[-n:] = body[-n:] * np.cos(t * np.pi / 2) + head * np.sin(t * np.pi / 2)     # equal-power seam
o = wave.open(dst, "wb"); o.setnchannels(ch); o.setsampwidth(2); o.setframerate(sr)
o.writeframes(np.clip(body, -32768, 32767).astype(np.int16).tobytes()); o.close()
PY
ffmpeg -nostdin -v error -y -i "$TMP/loop.wav" -c:a libvorbis -q:a 5 "$OUT"
echo "match music: $OUT ($(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT") s, from the $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TMP/n.wav") s song)"
rm -rf "$TMP"
