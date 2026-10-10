#!/bin/bash
# 0.31.91: the first start of a fresh install, on Vulkan (Mobile renderer), with an EMPTY shader cache -- the case that
# froze on the Godot splash (Kevin's S21, the testers' phones). Needs a display: Xvfb + lavapipe here.
#   GODOT=... DISPLAY=:98 bash tools/cold_start_check.sh [timeout_s]
# Moves this machine's shader cache aside, starts the app, waits for "BOOT OK" in user://boot_diag.log, puts the cache
# back. Prints COLD_START_PASS / COLD_START_FAIL with the start-up log.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
T="${1:-150}"
U="$HOME/.local/share/godot/app_userdata/Fatebound"
KEEP="$(mktemp -d)"
for d in shader_cache vulkan; do [ -e "$U/$d" ] && mv "$U/$d" "$KEEP/"; done
rm -f "$U/boot_diag.log"
"$GODOT" --rendering-driver vulkan --rendering-method mobile --path . > "$KEEP/out.log" 2>&1 &
PID=$!
ok=0
for _ in $(seq 1 "$T"); do
  sleep 1
  if grep -q "BOOT OK" "$U/boot_diag.log" 2>/dev/null; then ok=1; break; fi
done
kill "$PID" 2>/dev/null; sleep 1; kill -9 "$PID" 2>/dev/null
grep -E "SESSION|BOOT|STALL" "$U/boot_diag.log" 2>/dev/null | head -16
rm -rf "$U/shader_cache" "$U/vulkan"
for d in shader_cache vulkan; do [ -e "$KEEP/$d" ] && mv "$KEEP/$d" "$U/"; done
rm -rf "$KEEP"
if [ "$ok" = 1 ]; then echo "COLD_START_PASS"; else echo "COLD_START_FAIL (no menu within ${T}s on an empty shader cache)"; exit 1; fi
