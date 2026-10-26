#!/bin/sh
# GPU particles: Godot's real particle simulation (Vulkan on llvmpipe under Xvfb -- the dummy renderer of --headless
# does not simulate) against ParticlesSim (GUI/Scene3D), for the setups in particles_cases.txt. Both print each frame's
# capture_aabb() (every particle with non-zero flags, node-local); the sequences of distinct states per case are
# compared with a tolerance, since the GPU's sin / cos / pow differ from the C library in the last bits.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
GODOT=${GODOT:-/root/godot/Godot_v4.7.2-stable_linux.x86_64}
DOTNET=${DOTNET:-dotnet}
command -v "$DOTNET" > /dev/null 2>&1 || DOTNET=/root/.dotnet/dotnet
OUT=${TMPDIR:-/tmp}/fb-particles
TOL=${TOL:-0.0001}
mkdir -p "$OUT"
(cd "$HERE" && timeout 300 xvfb-run -a -s "-screen 0 640x480x24" "$GODOT" --rendering-driver vulkan --fixed-fps 60 -s godot_particles.gd 2>&1) | grep '^pt|' > "$OUT/godot.txt"
"$DOTNET" build "$HERE/../guitest" -nologo -v q > /dev/null
"$DOTNET" /tmp/fb-guitest/bin/net8.0/guitest.dll particles-parity "$HERE/particles_cases.txt" > "$OUT/cs.txt" 2>&1
python3 - "$OUT/godot.txt" "$OUT/cs.txt" "$TOL" <<'EOF'
import sys
def load(p):
    seqs = {}
    for line in open(p):
        _, case, frame, vals = line.rstrip("\n").split("|")
        v = tuple(float(x) for x in vals.split())
        s = seqs.setdefault(case, [])
        if v == (0.0,) * 6 and not s:
            continue                      # nothing processed yet
        if not s or s[-1] != v:
            s.append(v)
    return seqs
g, c, tol = load(sys.argv[1]), load(sys.argv[2]), float(sys.argv[3])
bad = 0
for case in g:
    gs, cs = g[case], c.get(case, [])
    n = min(len(gs), len(cs))
    worst, at = 0.0, -1
    for i in range(n):
        d = max(abs(a - b) / max(1.0, abs(a)) for a, b in zip(gs[i], cs[i]))
        if d > worst:
            worst, at = d, i
    ok = worst <= tol and abs(len(gs) - len(cs)) <= 1
    bad += not ok
    print("%-14s %s states godot %d cs %d, max diff %.2e%s" % (case, "ok  " if ok else "FAIL", len(gs), len(cs), worst,
          "" if ok else " at state %d: godot %s cs %s" % (at, gs[at] if at >= 0 else "-", cs[at] if at >= 0 else "-")))
sys.exit(1 if bad else 0)
EOF
