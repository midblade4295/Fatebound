#!/usr/bin/env bash
# The iOS build's native plugins, put into godot/addons/ just before an iOS export (the TestFlight workflow runs this;
# so can anyone exporting iOS on a Mac). None of it is committed (.gitignore), so Android and desktop builds never
# carry or load it:
#   GodotApplePlugins (github.com/migueldeicaza/GodotApplePlugins, MIT): StoreKit 2 + Game Center + their Swift
#     runtime, as GDExtensions -- the pinned release zip, its SHA-256 checked. Used through ClassDB by
#     scripts/meta/billing_ios.gd and game_center.gd.
#   FateboundNotifyIOS (godot/ios_plugins/fatebound_notify): chest-ready notifications, built from source (macOS).
# Then re-import (the editor lists the new extensions in .godot/extension_list.cfg) before exporting.
#   bash godot/tools/ios_plugins.sh            (from the repository root or godot/)
#   bash godot/tools/ios_plugins.sh --remove   (take them out again)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"          # .../godot
ADDONS="$HERE/addons"
GAP_BUILD="a6d667dda4d4f7b008009d3704f679b06f81424f"   # GodotApplePlugins v1.11 (release "build-<commit>")
GAP_URL="https://github.com/migueldeicaza/GodotApplePlugins/releases/download/build-$GAP_BUILD/GodotApplePlugins-addons-$GAP_BUILD.zip"
GAP_SHA256="a5c48a9949fa0f96217c1b8900810098d27cf8d0ac77224d875780e34edc8166"
GAP_ADDONS="GodotApplePluginsStoreKit GodotApplePluginsGameCenter GodotApplePluginsRuntime"

remove() {
  for a in $GAP_ADDONS FateboundNotifyIOS; do rm -rf "${ADDONS:?}/$a"; done
}
if [ "${1:-}" = "--remove" ]; then
  remove
  echo "iOS plugins removed from $ADDONS"
  exit 0
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
curl -fsSL --retry 3 -o "$T/gap.zip" "$GAP_URL"
got="$( (command -v sha256sum >/dev/null && sha256sum "$T/gap.zip" || shasum -a 256 "$T/gap.zip") | cut -d' ' -f1)"
[ "$got" = "$GAP_SHA256" ] || { echo "GodotApplePlugins zip SHA-256 $got, expected $GAP_SHA256" >&2; exit 1; }
mkdir -p "$T/gap"
pats=()
for a in $GAP_ADDONS; do pats+=("dist/addons/$a/*"); done
unzip -q "$T/gap.zip" "${pats[@]}" -d "$T/gap"
remove
for a in $GAP_ADDONS; do
  cp -R "$T/gap/dist/addons/$a" "$ADDONS/$a"
  find "$ADDONS/$a" -name '*.dll' -delete                              # (the Windows stubs aren't needed)
done
echo "GodotApplePlugins $GAP_BUILD -> $ADDONS ($GAP_ADDONS)"

if [ "$(uname -s)" = "Darwin" ]; then
  bash "$HERE/ios_plugins/fatebound_notify/build_ios.sh"
else
  echo "FateboundNotifyIOS needs macOS + Xcode: not built here (the app then has no notifications)" >&2
fi
