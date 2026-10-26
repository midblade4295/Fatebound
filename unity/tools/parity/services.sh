#!/bin/sh
# The engine services (Sim/Script/GMarshal.cs: var_to_bytes / var_to_str...; GUI/Services: Time, FileAccess, compression,
# ConfigFile, RegEx, OS, threads, WebSocketPeer, HTTPRequest) against Godot: the same cases printed by Godot
# (godot_services.gd) and by the C# services (guitest services), diffed.
#   1. guitest services-gen writes C#-compressed data and a ConfigFile for Godot to read back
#   2. Godot runs godot_services.gd (its WebSocket test against ws_server.gd in-process)
#   3. a Godot ws_server.gd and a python http.server serve the C# run (guitest services)
# --regen: rewrite the Godot bytes embedded in tools/guitest/ServicesTest.cs from this Godot run first (after changing
# the cases). Error/warning lines are left out of the diff (their wording is the engine's own business).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
GODOT=${GODOT:-/root/godot/Godot_v4.7.2-stable_linux.x86_64}
DOTNET=${DOTNET:-$(command -v dotnet || echo /root/.dotnet/dotnet)}
OUT=${TMPDIR:-/tmp}/fb-services
GT=/tmp/fb-guitest/bin/net8.0/guitest.dll
export FB_SERVICES_OUT="$OUT"
rm -rf "$OUT"
mkdir -p "$OUT/www"
HTTP_PID=
WS_PID=
cleanup() {
	[ -n "$HTTP_PID" ] && kill "$HTTP_PID" 2>/dev/null || true
	if [ -n "$WS_PID" ]; then touch "$OUT/ws.port.stop"; sleep 0.5; kill "$WS_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT
filter() { grep -v '^Godot Engine\|^$\|^ *at: \|^ *GDScript backtrace\|^ *\[[0-9]*\] \|^ERROR: \|^WARNING: \|^SCRIPT ERROR: \|^USER ERROR: \|^USER WARNING: \|^Unicode parsing error' || true; }

# files the HTTP cases fetch, and a local server for them
python3 -c "
import sys
open(sys.argv[1] + '/a.txt', 'w').write('hello http\n' * 100)
x = 5; b = bytearray()
for i in range(20000):
    x = (x * 1103515245 + 12345) & 0x7fffffff; b.append((x >> 16) & 255)
open(sys.argv[1] + '/data.bin', 'wb').write(bytes(b))
" "$OUT/www"
python3 -u -m http.server 0 --bind 127.0.0.1 --directory "$OUT/www" > "$OUT/http.log" 2>&1 &
HTTP_PID=$!
for i in $(seq 1 100); do grep -q "port" "$OUT/http.log" 2>/dev/null && break; sleep 0.1; done
HTTP_PORT=$(sed -n 's/.* port \([0-9]*\).*/\1/p' "$OUT/http.log" | head -1)
export FB_HTTP_URL="http://127.0.0.1:$HTTP_PORT"

"$DOTNET" build "$HERE/../guitest" -nologo -v q > /dev/null
"$DOTNET" "$GT" services-gen > "$OUT/gen.txt" 2>&1

(cd "$HERE" && timeout 300 "$GODOT" --headless -s godot_services.gd 2>&1) > "$OUT/godot_raw.txt"
filter < "$OUT/godot_raw.txt" > "$OUT/godot.txt"

if [ "$1" = "--regen" ]; then
	python3 - "$OUT/godot.txt" "$HERE/../guitest/ServicesTest.cs" <<'PYEOF'
import sys
lines = open(sys.argv[1], encoding='utf-8').read().split('\n')
def pick(prefix):
    r = []
    for l in lines:
        if l.startswith(prefix):
            rest = l[len(prefix):]
            key, _, hexs = rest.rpartition('|')
            r.append((key, hexs))
    return r
def block(name, items):
    body = ''.join('            { "%s", "%s" },\n' % (k, v) for k, v in items)
    return '        static readonly Dictionary<string, string> %s = new Dictionary<string, string>\n        {\n%s        };\n' % (name, body)
gen = ('    // BEGIN GODOT DATA (generated from godot_services.gd\'s output by tools/parity/services.sh --regen; do not edit)\n'
       '    public static partial class ServicesTest\n    {\n'
       + block('GodotBytes', pick('vb|')) + block('GodotOnly', pick('gvb|')) + block('GodotZ', pick('gz|'))
       + '    }\n    // END GODOT DATA\n')
src = open(sys.argv[2], encoding='utf-8').read()
a = src.index('    // BEGIN GODOT DATA')
b = src.index('    // END GODOT DATA\n') + len('    // END GODOT DATA\n')
open(sys.argv[2], 'w', encoding='utf-8').write(src[:a] + gen + src[b:])
print('regenerated Godot data in ServicesTest.cs')
PYEOF
	"$DOTNET" build "$HERE/../guitest" -nologo -v q > /dev/null
fi

# a Godot WebSocket server for the C# client
(cd "$HERE" && FB_WS_PORT_FILE="$OUT/ws.port" exec "$GODOT" --headless -s godot_ws_server.gd) > "$OUT/ws_server.log" 2>&1 &
WS_PID=$!
for i in $(seq 1 100); do [ -s "$OUT/ws.port" ] && break; sleep 0.1; done
export FB_WS_URL="ws://127.0.0.1:$(cat "$OUT/ws.port")/"

"$DOTNET" "$GT" services > "$OUT/cs_raw.txt" 2>&1
filter < "$OUT/cs_raw.txt" > "$OUT/cs.txt"

if diff "$OUT/godot.txt" "$OUT/cs.txt"; then echo "services: $(wc -l < "$OUT/cs.txt") lines identical"; else exit 1; fi
