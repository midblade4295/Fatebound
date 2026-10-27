#!/bin/sh
# Sets up check.py's FXC mode (FBFXC=1): Wine and MinGW from the distribution, fxcrun.exe built from fxcrun.c, and FXC
# itself -- D3DCompiler_47.dll, which Unity 6000.3's Linux editor ships in Editor/Data/Tools (the compiler Unity runs
# first for Vulkan, GLES and Metal shaders) -- streamed out of the editor archive, along with Unity's CGIncludes.
# Everything lands in ${FB_FXC_DIR:-/root/tools}; nothing of it goes into the repo.
set -e
D=${FB_FXC_DIR:-/root/tools}
mkdir -p "$D"
apt-get install -y -qq --no-install-recommends wine64 gcc-mingw-w64-x86-64
x86_64-w64-mingw32-gcc -O1 -Wl,--stack,134217728 -o "$D/fxcrun.exe" "$(dirname "$0")/fxcrun.c"
if [ ! -f "$D/D3DCompiler_47.dll" ]; then
  # (the changeset of 6000.3.27f1, from services.api.unity.com/unity/editor/release/v1/releases?version=6000.3.27f1)
  curl -s https://download.unity3d.com/download_unity/672d562a42a7/LinuxEditorInstaller/Unity-6000.3.27f1.tar.xz \
    | xz -dc -T0 | tar -x -C "$D" --wildcards 'Editor/Data/Tools/D3DCompiler_47.dll' 'Editor/Data/Resources/CGIncludes/*'
  mv "$D/Editor/Data/Tools/D3DCompiler_47.dll" "$D/"
fi
WINEDEBUG=-all WINEPREFIX=/root/.wine-fxc wine64 "$D/fxcrun.exe" 2>/dev/null || true
