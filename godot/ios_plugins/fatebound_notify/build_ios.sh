#!/usr/bin/env bash
# Builds FateboundNotifyIOS (src/, chest-ready notifications on iOS) and installs it as
# godot/addons/FateboundNotifyIOS/ -- two static xcframeworks (ours + godot-cpp, iPhone arm64 + Simulator) and the
# .gdextension that names them. macOS with Xcode only (the TestFlight workflow runs it; tools/ios_plugins.sh calls it).
# The addon is never committed (.gitignore): Android and desktop builds never see it.
#   bash godot/ios_plugins/fatebound_notify/build_ios.sh
# Env: WORK (scratch dir, default $RUNNER_TEMP or /tmp), JOBS.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT_DIR="$(cd "$HERE/../.." && pwd)"
OUT="$GODOT_DIR/addons/FateboundNotifyIOS"
WORK="${WORK:-${RUNNER_TEMP:-/tmp}}/fatebound_notify_build"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
# godot-cpp pinned: tag godot-4.5-stable (works with Godot 4.5 and later engines, 4.7.2 included)
GODOT_CPP_TAG="godot-4.5-stable"
GODOT_CPP_COMMIT="e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77"
MIN_IOS="17.0"
TARGET="template_release"

[ "$(uname -s)" = "Darwin" ] || { echo "build_ios.sh needs macOS with Xcode" >&2; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK"
# SCons in its own virtual environment (Homebrew's Python refuses system-wide pip installs, PEP 668)
SCONS="$(command -v scons || true)"
if [ -z "$SCONS" ]; then
  python3 -m venv "$WORK/venv"
  "$WORK/venv/bin/python" -m pip install --quiet scons
  SCONS="$WORK/venv/bin/scons"
fi
git clone --quiet --depth 1 --branch "$GODOT_CPP_TAG" https://github.com/godotengine/godot-cpp "$WORK/godot-cpp"
got="$(git -C "$WORK/godot-cpp" rev-parse HEAD)"
[ "$got" = "$GODOT_CPP_COMMIT" ] || { echo "godot-cpp $GODOT_CPP_TAG is $got, expected $GODOT_CPP_COMMIT" >&2; exit 1; }

mkdir -p "$WORK/ext"
cp -R "$HERE/src" "$HERE/SConstruct" "$HERE/build_profile.json" "$WORK/ext/"
cd "$WORK/ext"
export GODOT_CPP="$WORK/godot-cpp"
common=(platform=ios target="$TARGET" ios_min_version="$MIN_IOS" build_profile="$WORK/ext/build_profile.json" -j"$JOBS")
"$SCONS" arch=arm64 "${common[@]}"
"$SCONS" arch=universal ios_simulator=yes "${common[@]}"

rm -rf "$OUT"
mkdir -p "$OUT/bin"
xcodebuild -create-xcframework \
  -library "bin/libfatebound_notify.ios.$TARGET.a" \
  -library "bin/libfatebound_notify.ios.$TARGET.simulator.a" \
  -output "$OUT/bin/libfatebound_notify.ios.xcframework"
xcodebuild -create-xcframework \
  -library "$GODOT_CPP/bin/libgodot-cpp.ios.$TARGET.arm64.a" \
  -library "$GODOT_CPP/bin/libgodot-cpp.ios.$TARGET.universal.simulator.a" \
  -output "$OUT/bin/libgodot-cpp.ios.xcframework"

cat > "$OUT/fatebound_notify_ios.gdextension" <<'EOF'
; Built by godot/ios_plugins/fatebound_notify/build_ios.sh (never committed). iOS only.
[configuration]

entry_symbol = "fatebound_notify_ios_init"
compatibility_minimum = "4.5"

[libraries]

ios = "res://addons/FateboundNotifyIOS/bin/libfatebound_notify.ios.xcframework"

[dependencies]

ios = { "res://addons/FateboundNotifyIOS/bin/libgodot-cpp.ios.xcframework": "" }
EOF
echo "FateboundNotifyIOS -> $OUT"
