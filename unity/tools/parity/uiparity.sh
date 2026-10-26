#!/bin/bash
# Compares the C# GUI's layout with Godot's for each spec: ./uiparity.sh [spec.json ...] (default: all in ui/)
cd "$(dirname "$0")"
REPO=$(cd ../../.. && pwd)
GODOT=${GODOT:-/root/godot/Godot_v4.7.2-stable_linux.x86_64}
DLL=/tmp/fb-guitest/bin/net8.0/guitest.dll
specs=("$@"); [ ${#specs[@]} -eq 0 ] && specs=(ui/*.json)
fail=0
for s in "${specs[@]}"; do
  abs=$(cd "$(dirname "$s")" && pwd)/$(basename "$s")
  timeout 120 "$GODOT" --headless --path "$REPO/godot" -s "$PWD/godot_ui.gd" -- "$abs" 2>/dev/null | grep '^R ' > /tmp/fb-uip-g.txt
  /root/.dotnet/dotnet "$DLL" ui "$abs" > /tmp/fb-uip-c.txt
  python3 - "$s" <<'PY'
import sys
g=[l.split() for l in open('/tmp/fb-uip-g.txt')]; c=[l.split() for l in open('/tmp/fb-uip-c.txt')]
gd={l[1]:l[2:] for l in g}; cd={l[1]:l[2:] for l in c}
bad=0
for k in gd:
    if k not in cd: print("  missing", k); bad+=1; continue
    gv=[float(x) for x in gd[k][:4]]+[float(x) for x in gd[k][4][4:].split(',')]
    cv=[float(x) for x in cd[k][:4]]+[float(x) for x in cd[k][4][4:].split(',')]
    if any(abs(a-b)>0.02 for a,b in zip(gv,cv)):
        bad+=1; print("  %-40s godot %s\n  %-40s c#    %s"%(k,' '.join(gd[k]),'',' '.join(cd[k])))
print("%s: %d controls, %d differ"%(sys.argv[1],len(gd),bad))
sys.exit(1 if bad else 0)
PY
  [ $? -ne 0 ] && fail=1
done
exit $fail
