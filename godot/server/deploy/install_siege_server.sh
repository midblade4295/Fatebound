#!/usr/bin/env bash
# Installs or updates the Fatebound Siege online server on this machine (Linux + systemd).
# Run from a checkout of the Siege branch (claude/siege-dev-r6-local or later):
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

# The sim preloads the land and the keep (siege_land.gd, keep.gd -- 0.31.82: the land was missing here, so a fresh
# install could not compile the sim; 0.31.165: the Rift's keep) and the 5v5 (moba*.gd). Nothing else: the baked terrain
# files are only the client's. (0.31.169: Siege's castle layout, siege_castle.gd, went with Siege.)
SERVER_SCRIPTS="scripts/siege/siege_sim.gd scripts/siege/siege_net.gd scripts/siege/siege_land.gd scripts/siege/keep.gd scripts/siege/moba.gd scripts/siege/moba_vision.gd scripts/siege/moba_kits.gd"
# 0.31.108: the accounts -- the server replays every player's changes with the game's own economy and profile code
# 0.31.118: the analytics allow-list (events and their props), shared by the phone and the server
# 0.31.131: the App Store account token (UUIDv5 of the account id), shared by the phone and the purchase check
# (0.31.135-0.31.168: the war map, scripts/meta/war_map.gd, for server/world.gd -- Crown War went in 0.31.169)
META_SCRIPTS="scripts/meta/economy.gd scripts/meta/profile.gd scripts/meta/analytics_events.gd scripts/meta/apple_token.gd"
# 0.31.131: App Store purchase checks -- the verifier, its helper (python3 + the openssl command) and Apple's public root
SERVER_FILES="server/siege_server.gd server/siege_probe.gd server/clans.gd server/iap_verify.gd server/iap_verify_apple.gd server/apple_jws.py server/certs/AppleRootCA-G3.cer server/eco_accounts.gd server/match_ledger.gd server/social.gd server/analytics.gd server/leaderboard.gd server/referrals.gd server/diag_reports.gd"
for f in $SERVER_SCRIPTS $META_SCRIPTS $SERVER_FILES; do
  [ -f "$SRC/$f" ] || { echo "Missing $SRC/$f — run this from the Siege branch checkout." >&2; exit 1; }
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
# 0.31.131: App Store purchase checks run server/apple_jws.py (Python's standard library + the openssl command)
for tool in python3 openssl; do
  command -v "$tool" >/dev/null 2>&1 || echo "WARNING: $tool not found -- App Store purchases can't be checked until it is installed" >&2
done

# ---- 2. Port must be free or ours ----
if command -v ss >/dev/null 2>&1 && ss -ltnH "sport = :$PORT" | grep -q .; then
  if [ "$NO_SYSTEMD" = "1" ] || ! systemctl is-active --quiet fatebound-siege; then
    echo "Port $PORT is already in use by something else:" >&2; ss -ltnp "sport = :$PORT" >&2 || true; exit 1
  fi
fi

# ---- 3. Minimal server project ----
STAGE="$(mktemp -d)"
mkdir -p "$STAGE/scripts/siege" "$STAGE/scripts/meta" "$STAGE/server"
for f in $SERVER_SCRIPTS; do cp "$SRC/$f" "$STAGE/scripts/siege/"; done
for f in $META_SCRIPTS; do cp "$SRC/$f" "$STAGE/scripts/meta/"; done
mkdir -p "$STAGE/server/certs"
for f in $SERVER_FILES; do cp "$SRC/$f" "$STAGE/$f"; done
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
  # 0.31.90: Google Play purchase checks. The service runs as a throwaway user that can't read a root-only key, so
  # systemd hands the key over as a credential -- only when the file exists (a missing credential stops the unit).
  PLAY_KEY="${PLAY_KEY:-/etc/fatebound-siege/play-service-account.json}"
  if [ -f "$PLAY_KEY" ]; then
    sed -i "s|^# LoadCredential=play-key:.*|LoadCredential=play-key:$PLAY_KEY|" /etc/systemd/system/fatebound-siege.service
    echo "Purchase checks: key $PLAY_KEY handed to the service"
  else
    echo "Purchase checks: no key at $PLAY_KEY yet (purchases wait until it is there; see godot/PLAY_IAP_HANDOFF.md step 5)"
  fi
  # 0.31.131: App Store purchase checks -- the In-App Purchase key, handed over the same way (only when it exists)
  APPSTORE_KEY="${APPSTORE_KEY:-/etc/fatebound-siege/appstore-key.p8}"
  if [ -f "$APPSTORE_KEY" ]; then
    sed -i "s|^# LoadCredential=appstore-key:.*|LoadCredential=appstore-key:$APPSTORE_KEY|" /etc/systemd/system/fatebound-siege.service
    echo "App Store purchase checks: key $APPSTORE_KEY handed to the service (SIEGE_APPSTORE_ISSUER / SIEGE_APPSTORE_KEY_ID from /etc/fatebound-siege.env)"
  else
    echo "App Store purchase checks: no key at $APPSTORE_KEY yet (iPhone purchases wait until it is there; see godot/IOS_HANDOFF.md)"
  fi
  systemctl daemon-reload
  # 0.31.108: the players' accounts live in the service's state directory -- a copy before every update
  ACCT_DIR=/var/lib/private/fatebound-siege/accounts
  [ -d "$ACCT_DIR" ] || ACCT_DIR=/var/lib/fatebound-siege/accounts
  if [ -d "$ACCT_DIR" ]; then
    mkdir -p /var/backups/fatebound-siege
    # 0.31.118: plus the usage statistics of the last 7 days (and who opted out) -- older days stay only on the server
    AN_FILES=""
    for i in 0 1 2 3 4 5 6; do
      d="$(date -u -d "-$i day" +%F)"
      for f in "analytics/$d.jsonl" "analytics/$d.jsonl.gz"; do
        if [ -f "$(dirname "$ACCT_DIR")/$f" ]; then AN_FILES="$AN_FILES $f"; fi
      done
    done
    if [ -f "$(dirname "$ACCT_DIR")/analytics/opt_out.json" ]; then AN_FILES="$AN_FILES analytics/opt_out.json"; fi
    tar -czf "/var/backups/fatebound-siege/accounts-$(date -u +%Y%m%dT%H%M%SZ).tgz" -C "$(dirname "$ACCT_DIR")" \
      accounts $(cd "$(dirname "$ACCT_DIR")" && ls purchase_tokens.json iap_ledger.jsonl social.json reports.jsonl muted.txt leaderboard.json referrals.json 2>/dev/null) $AN_FILES
    chmod 600 /var/backups/fatebound-siege/*.tgz
    echo "Accounts backed up to /var/backups/fatebound-siege/ (analytics files:${AN_FILES:- none yet})"
  fi
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
