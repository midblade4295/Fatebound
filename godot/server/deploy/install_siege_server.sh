#!/usr/bin/env bash
# Installs or updates the Fatebound Siege online server on this machine (Linux + systemd).
# Run from a checkout of branch claude/kaykit-3d-rebuild:
#   sudo bash godot/server/deploy/install_siege_server.sh
#
# What it does (nothing else):
#   1. Installs Godot 4.7.2 (official build, SHA-512 verified) to /opt/godot-4.7.2 if missing.
#   2. Builds a minimal server-only project (sim + protocol + server scripts, no assets) in
#      /srv/fatebound-siege (previous copy kept as /srv/fatebound-siege.prev).
#   3. Installs/updates the systemd service fatebound-siege (127.0.0.1:8082) and restarts it.
#   4. Probes it like a player (PROBE_OK or the script fails).
# It does NOT touch Caddy, Legionary, the dice arena (8081) or the web/save host (8080).
#
# Test mode (no systemd, no root):  NO_SYSTEMD=1 DEST=/tmp/fs GODOT_DIR=/tmp/godot bash ...
set -euo pipefail

GODOT_VER="4.7.2"
GODOT_DIR="${GODOT_DIR:-/opt/godot-$GODOT_VER}"
DEST="${DEST:-/srv/fatebound-siege}"
PORT="${SIEGE_PORT:-8082}"
NO_SYSTEMD="${NO_SYSTEMD:-0}"
SRC="$(cd "$(dirname "$0")/../.." && pwd)"                  # .../godot
SERVICE_SRC="$SRC/server/deploy/fatebound-siege.service"

for f in scripts/siege/siege_sim.gd scripts/siege/siege_net.gd server/siege_server.gd server/siege_probe.gd; do
  [ -f "$SRC/$f" ] || { echo "Missing $SRC/$f — run this from the claude/kaykit-3d-rebuild checkout." >&2; exit 1; }
done
if [ "$NO_SYSTEMD" != "1" ] && [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo (installs to /opt, /srv and systemd)." >&2; exit 1
fi

# ---- 1. Godot ----
case "$(uname -m)" in
  x86_64|amd64) GARCH="linux.x86_64" ;;
  aarch64|arm64) GARCH="linux.arm64" ;;
  *) echo "Unsupported CPU $(uname -m)" >&2; exit 1 ;;
esac
GODOT_BIN="$GODOT_DIR/godot"
if [ ! -x "$GODOT_BIN" ] || ! "$GODOT_BIN" --version 2>/dev/null | grep -q "^$GODOT_VER.stable"; then
  echo "Installing Godot $GODOT_VER ($GARCH) to $GODOT_DIR"
  TMPD="$(mktemp -d)"
  BASE="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VER}-stable"
  ZIP="Godot_v${GODOT_VER}-stable_${GARCH}.zip"
  curl -fsSL -o "$TMPD/$ZIP" "$BASE/$ZIP"
  curl -fsSL -o "$TMPD/SHA512-SUMS.txt" "$BASE/SHA512-SUMS.txt"
  (cd "$TMPD" && grep " $ZIP\$" SHA512-SUMS.txt | sha512sum -c -) || { echo "Godot download failed its SHA-512 check" >&2; exit 1; }
  (cd "$TMPD" && unzip -q "$ZIP")
  mkdir -p "$GODOT_DIR"
  install -m 0755 "$TMPD/Godot_v${GODOT_VER}-stable_${GARCH}" "$GODOT_BIN"
  rm -rf "$TMPD"
fi
"$GODOT_BIN" --version

# ---- 2. Port must be free or ours ----
if command -v ss >/dev/null 2>&1 && ss -ltnH "sport = :$PORT" | grep -q .; then
  if [ "$NO_SYSTEMD" = "1" ] || ! systemctl is-active --quiet fatebound-siege; then
    echo "Port $PORT is already in use by something else:" >&2; ss -ltnp "sport = :$PORT" >&2 || true; exit 1
  fi
fi

# ---- 3. Minimal server project ----
STAGE="$(mktemp -d)"
mkdir -p "$STAGE/scripts/siege" "$STAGE/server"
cp "$SRC/scripts/siege/siege_sim.gd" "$SRC/scripts/siege/siege_net.gd" "$STAGE/scripts/siege/"
cp "$SRC/server/siege_server.gd" "$SRC/server/siege_probe.gd" "$STAGE/server/"
cat > "$STAGE/project.godot" <<'PROJ'
; Fatebound Siege dedicated server: simulation + protocol only (no assets, no autoloads).
config_version=5

[application]
config/name="Fatebound Siege Server"

[debug]
file_logging/enable_file_logging=false
PROJ
# Build Godot's script cache once, so the service can run from a read-only directory.
"$GODOT_BIN" --headless --path "$STAGE" --import >/dev/null 2>&1 || true
if [ -d "$DEST" ]; then
  rm -rf "$DEST.prev"
  cp -a "$DEST" "$DEST.prev"
fi
mkdir -p "$DEST"
rm -rf "${DEST:?}/"*
cp -a "$STAGE/." "$DEST/"
chmod -R a+rX "$DEST"
rm -rf "$STAGE"
echo "Server project installed in $DEST"

# ---- 4. Service ----
if [ "$NO_SYSTEMD" = "1" ]; then
  echo "NO_SYSTEMD=1: starting the server in the background for the probe"
  SIEGE_PORT="$PORT" SIEGE_HOST=127.0.0.1 "$GODOT_BIN" --headless --path "$DEST" -s res://server/siege_server.gd > "$DEST/server.log" 2>&1 &
  SRV=$!
  trap 'kill $SRV 2>/dev/null || true' EXIT
else
  sed -e "s|/opt/godot-4.7.2/godot|$GODOT_BIN|" -e "s|/srv/fatebound-siege|$DEST|g" -e "s|SIEGE_PORT=8082|SIEGE_PORT=$PORT|" \
    "$SERVICE_SRC" > /etc/systemd/system/fatebound-siege.service
  systemctl daemon-reload
  systemctl enable --quiet fatebound-siege
  systemctl restart fatebound-siege
fi
sleep 3

# ---- 5. Probe ----
if SIEGE_PROBE_URL="ws://127.0.0.1:$PORT/fatebound/siege/ws" "$GODOT_BIN" --headless --path "$DEST" -s res://server/siege_probe.gd 2>/dev/null | grep -q PROBE_OK; then
  echo "PROBE_OK: the Siege server answers on 127.0.0.1:$PORT"
else
  echo "PROBE FAILED. Logs:" >&2
  if [ "$NO_SYSTEMD" = "1" ]; then tail -20 "$DEST/server.log" >&2; else journalctl -u fatebound-siege -n 30 --no-pager >&2; fi
  exit 1
fi

cat <<NEXT

Next (one-time, needs your OK — this is a Caddy change):
  1. sudo cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak.\$(date +%Y%m%d%H%M%S)
  2. Add the block from godot/server/deploy/caddy-route.fragment inside the
     136-113-125-3.sslip.io site, next to the /fatebound/arena/* block.
  3. sudo caddy validate --config /etc/caddy/Caddyfile && sudo systemctl reload caddy
  4. Public check:
     SIEGE_PROBE_URL=wss://136-113-125-3.sslip.io/fatebound/siege/ws \\
       $GODOT_BIN --headless --path $DEST -s res://server/siege_probe.gd
Logs: journalctl -u fatebound-siege -f
NEXT
