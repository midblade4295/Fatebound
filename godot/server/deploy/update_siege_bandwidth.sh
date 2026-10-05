#!/usr/bin/env bash
# Narrow protocol-30 server update; keeps the installed simulation, downloads and service unit.
# Usage: bash update_siege_bandwidth.sh --check
#        sudo bash update_siege_bandwidth.sh
set -euo pipefail
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
LIVE=/srv/fatebound-siege
GODOT=/opt/godot-4.7.2/godot
CFG="$SRC/server/deploy/bandwidth-server.cfg"
EXPECTED_NET=40f1e7bc6646818c69271d39be0d6b704ab234d20b15466eb0825a280658231e
EXPECTED_SERVER=1bc4f5c412cd0ea7630aa24d9732c4917e8781034b8bd397525eb497db0735e8
EXPECTED_SIM=6780488f843b02e9df6879efb0cf0835594930d08f2c2f68c69754e8e0bb97e5
EXPECTED_PROJECT=54771746110c275009b97bc3c2222409c7c6ca6103546abbf928f0fe90e522dc
CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then CHECK_ONLY=1; elif [ "$#" -gt 0 ]; then echo "Usage: $0 [--check]" >&2; exit 2; fi
for file in "$SRC/scripts/siege/siege_net.gd" "$SRC/server/siege_server.gd" "$CFG" "$LIVE/project.godot"; do
  [ -f "$file" ] || { echo "Missing file: $file" >&2; exit 1; }
done
[ "$(sha256sum "$LIVE/scripts/siege/siege_net.gd" | cut -d ' ' -f1)" = "$EXPECTED_NET" ] ||
  { echo "Live protocol changed since this update was tested; inspect it before applying." >&2; exit 1; }
[ "$(sha256sum "$LIVE/server/siege_server.gd" | cut -d ' ' -f1)" = "$EXPECTED_SERVER" ] ||
  { echo "Live server changed since this update was tested; inspect it before applying." >&2; exit 1; }
[ "$(sha256sum "$LIVE/scripts/siege/siege_sim.gd" | cut -d ' ' -f1)" = "$EXPECTED_SIM" ] ||
  { echo "Live simulation changed since this update was tested; inspect it before applying." >&2; exit 1; }
[ "$(sha256sum "$LIVE/project.godot" | cut -d ' ' -f1)" = "$EXPECTED_PROJECT" ] ||
  { echo "Live startup settings changed since this update was tested." >&2; exit 1; }
[ ! -e "$LIVE/override.cfg" ] || { echo "An existing server override needs review first." >&2; exit 1; }
systemctl is-active --quiet fatebound-siege
CONNECTIONS="$(ss -Htn state established '( sport = :8082 )')"
[ -z "$CONNECTIONS" ] ||
  { echo "Fatebound players are connected; apply this update when the server is empty." >&2; exit 1; }
[ "$CHECK_ONLY" = 0 ] || { echo "BANDWIDTH_PREFLIGHT_OK"; exit 0; }
[ "$(id -u)" = 0 ] || { echo "Administrator access required; run this script with sudo." >&2; exit 1; }
BACKUP="/home/midblade4295/backups/fatebound-bandwidth-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BACKUP"
cp -p "$LIVE/scripts/siege/siege_net.gd" "$BACKUP/siege_net.gd"
cp -p "$LIVE/server/siege_server.gd" "$BACKUP/siege_server.gd"
cp -p "$LIVE/project.godot" "$BACKUP/project.godot"
OTHER_PIDS="$(systemctl show legionary caddy --no-pager -p MainPID --value)"
rollback() {
  trap - ERR
  set +e
  echo "Bandwidth update failed; restoring the prior Fatebound server." >&2
  cp -p "$BACKUP/siege_net.gd" "$LIVE/scripts/siege/siege_net.gd"
  cp -p "$BACKUP/siege_server.gd" "$LIVE/server/siege_server.gd"
  cp -p "$BACKUP/project.godot" "$LIVE/project.godot"
  rm -f "$LIVE/override.cfg"
  timeout --kill-after=5 60 "$GODOT" --headless --editor --path "$LIVE" --import > "$BACKUP/rollback-import.log" 2>&1 || true
  systemctl restart fatebound-siege
}
trap 'failure_status=$?; rollback; exit "$failure_status"' ERR
systemctl stop fatebound-siege
install -o root -g root -m 0644 "$SRC/scripts/siege/siege_net.gd" "$LIVE/scripts/siege/siege_net.gd"
install -o root -g root -m 0644 "$SRC/server/siege_server.gd" "$LIVE/server/siege_server.gd"
install -o root -g root -m 0644 "$CFG" "$LIVE/override.cfg"
timeout --kill-after=5 120 "$GODOT" --headless --editor --path "$LIVE" --import > "$BACKUP/import.log" 2>&1
if grep -q 'SCRIPT ERROR\|Parse Error' "$BACKUP/import.log"; then
  echo "Updated server import failed." >&2
  false
fi
[ "$(sha256sum "$LIVE/project.godot" | cut -d ' ' -f1)" = "$EXPECTED_PROJECT" ]
systemctl start fatebound-siege
sleep 2
systemctl is-active --quiet fatebound-siege
SIEGE_PROBE_URL=ws://127.0.0.1:8082/fatebound/siege/ws timeout --kill-after=2 20 "$GODOT" --headless --path "$LIVE" -s res://server/siege_probe.gd > "$BACKUP/local-probe.log" 2>&1
grep -q PROBE_OK "$BACKUP/local-probe.log"
SIEGE_PROBE_URL=wss://136-113-125-3.sslip.io/fatebound/siege/ws timeout --kill-after=2 20 "$GODOT" --headless --path "$LIVE" -s res://server/siege_probe.gd > "$BACKUP/public-probe.log" 2>&1
grep -q PROBE_OK "$BACKUP/public-probe.log"
[ "$(sha256sum "$LIVE/scripts/siege/siege_sim.gd" | cut -d ' ' -f1)" = "$EXPECTED_SIM" ]
[ "$(systemctl show legionary caddy --no-pager -p MainPID --value)" = "$OTHER_PIDS" ]
trap - ERR
echo "BANDWIDTH_DEPLOY_OK"
echo "Rollback files: $BACKUP"
