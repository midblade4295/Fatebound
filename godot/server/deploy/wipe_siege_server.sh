#!/usr/bin/env bash
# 0.31.198 (Kevin: "I want to wipe the server so everyone starts fresh"; purchases: "Wipe them too"): wipes the
# Fatebound Siege server's players after a full backup of its state directory.
#   Gone: every account (progress, gold and gems -- bought ones too --, heroes, outfits, titles, chests, the pass), the
#         Game Center links, clans, friends and parties, chat, the leaderboard and referrals.
#   Kept: purchase_tokens.json and iap_ledger.jsonl (no purchase is ever granted twice), analytics, diagnostics,
#         reports and the mute list, Godot's own data.
# Then it writes wipe.json, so the server (0.31.198 or later: server/eco_accounts.gd) takes in nothing a phone hands
# over: every phone finds its key unknown, asks for a new account and gets a fresh one -- named "Player", so the app's
# Royal Herald asks the name, says what the game is, walks them round Home and offers the tutorial.
#
# Run it AFTER install_siege_server.sh has put 0.31.198's server in place (it checks):
#   sudo bash godot/server/deploy/wipe_siege_server.sh --yes
# Undo (the backup it prints):
#   sudo systemctl stop fatebound-siege
#   sudo tar -xzf /var/backups/fatebound-siege/state-before-wipe-<UTC>.tgz -C <state dir>   (and delete <state dir>/wipe.json)
#   sudo systemctl start fatebound-siege
# Test mode (no systemd, no root):  NO_SYSTEMD=1 STATE=/tmp/s BACKUP_DIR=/tmp/b DEST=<godot dir> bash ... --yes
set -euo pipefail

NO_SYSTEMD="${NO_SYSTEMD:-0}"
DEST="${DEST:-/srv/fatebound-siege}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/fatebound-siege}"
PORT="${SIEGE_PORT:-8082}"
GODOT_BIN="${GODOT_BIN:-/opt/godot-4.7.2/godot}"

if [ "${1:-}" != "--yes" ]; then
  cat >&2 <<'MSG'
This deletes EVERY player's account, purchases included, and their clans, friends, chat, leaderboard and referrals
(after a full backup). To go ahead:
  sudo bash godot/server/deploy/wipe_siege_server.sh --yes
MSG
  exit 1
fi
if [ "$NO_SYSTEMD" != "1" ] && [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo (the server's state directory is root's)." >&2; exit 1
fi
# the installed server must refuse imports, or every phone hands its old progress straight back
if ! grep -q 'wipe.json' "$DEST/server/eco_accounts.gd" 2>/dev/null; then
  echo "The server in $DEST is older than 0.31.198 (it would take the old progress back from every phone)." >&2
  echo "Install it first:  sudo bash godot/server/deploy/install_siege_server.sh" >&2
  exit 1
fi
if [ -z "${STATE:-}" ]; then
  STATE=/var/lib/private/fatebound-siege
  [ -d "$STATE" ] || STATE=/var/lib/fatebound-siege
fi
[ -d "$STATE" ] || { echo "No state directory at $STATE" >&2; exit 1; }
STATE="$(cd "$STATE" && pwd -P)"

# ---- 1. stop the server (nothing written while it goes) ----
if [ "$NO_SYSTEMD" != "1" ]; then
  systemctl stop fatebound-siege
fi

# ---- 2. a full backup ----
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP="$BACKUP_DIR/state-before-wipe-$STAMP.tgz"
tar -czf "$BACKUP" -C "$STATE" .
chmod 600 "$BACKUP"
N_ACCTS="$(ls "$STATE/accounts" 2>/dev/null | grep -c '\.meta\.json$' || true)"

# ---- 3. the wipe ----
rm -rf "$STATE/accounts"
for f in gc_links.json clans.json social.json chat.json leaderboard.json referrals.json; do
  rm -f "$STATE/$f" "$STATE/$f.tmp"
done
printf '{"at":%d}\n' "$(date -u +%s)" > "$STATE/wipe.json"
chmod 644 "$STATE/wipe.json"
chown --reference="$STATE" "$STATE/wipe.json" 2>/dev/null || true

# ---- 4. start it again ----
if [ "$NO_SYSTEMD" != "1" ]; then
  systemctl start fatebound-siege
  sleep 3
  if SIEGE_PROBE_URL="ws://127.0.0.1:$PORT/fatebound/siege/ws" "$GODOT_BIN" --headless --path "$DEST" -s res://server/siege_probe.gd 2>/dev/null | grep -q PROBE_OK; then
    echo "PROBE_OK: the Siege server answers on 127.0.0.1:$PORT"
  else
    echo "PROBE FAILED -- the server isn't answering. Logs: sudo journalctl -u fatebound-siege -n 60" >&2
  fi
  journalctl -u fatebound-siege -n 40 --no-pager 2>/dev/null | grep -m1 "accounts: " || true
fi

echo "WIPED: $N_ACCTS accounts, the Game Center links, clans, friends, chat, the leaderboard and referrals ($STATE)."
echo "Kept: purchase records (no purchase granted twice), analytics, diagnostics, reports, the mute list."
echo "Backup of everything before the wipe: $BACKUP"
echo "Undo: sudo systemctl stop fatebound-siege; sudo rm -rf $STATE/accounts; sudo tar -xzf $BACKUP -C $STATE;"
echo "      sudo rm -f $STATE/wipe.json; sudo systemctl start fatebound-siege"
