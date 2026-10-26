#!/bin/sh
# Downloads DXC 1.8.2407 (Microsoft's official Linux release) into ${FB_DXC_DIR:-/root/tools/dxc} for check.py.
set -e
D=${FB_DXC_DIR:-/root/tools/dxc}
mkdir -p "$D/x"
curl -sSL -o "$D/dxc.tar.gz" https://github.com/microsoft/DirectXShaderCompiler/releases/download/v1.8.2407/linux_dxc_2024_07_31.x86_64.tar.gz
tar -xzf "$D/dxc.tar.gz" -C "$D/x"
rm "$D/dxc.tar.gz"
"$D/x/bin/dxc" --version
