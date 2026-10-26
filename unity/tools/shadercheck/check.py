#!/usr/bin/env python3
# Compile check of Unity .shader HLSL/CG programs with DXC, outside Unity (an approximation of Unity's compile: DXC, not
# fxc; Unity's preprocessor quirks aside, it catches syntax, type and undeclared-identifier errors).
#
#   python3 check.py <file.shader> ...                     D3D11 API path (HLSL and CG programs)
#   FBAPI="SHADER_API_VULKAN=1,SHADER_API_MOBILE=1" python3 check.py <file.shader> ...
#                                                          Vulkan/mobile API path, SPIR-V (HLSL programs only: CG
#                                                          programs are skipped there -- the CGIncludes copy is old)
#   FBQUICK=1 ...                                          fewer variants (base, all-last, each keyword alone)
#
# Every program (HLSLPROGRAM / CGPROGRAM, with the HLSLINCLUDE / CGINCLUDE blocks before it) is compiled for its
# vertex and fragment entry points in every keyword combination of its multi_compile lines (multi_compile_vertex /
# _fragment only for that stage; multi_compile_instancing as INSTANCING_ON). Needs, next to this script:
#   dxc/x/bin/dxc + dxc/x/lib   DXC 1.8 linux release (github.com/microsoft/DirectXShaderCompiler, v1.8.2407)
#   inc/Packages/...            symlinks to the URP / core / universal-config / shadergraph packages
#   cginc/                      Unity's CGIncludes (UnityCG.cginc etc.) + fb_dxc_shim.hlsl (DX9 samplers for DXC)
import os, re, subprocess, sys, itertools

S = os.path.dirname(os.path.abspath(__file__))
# DXC lives outside the repo (a 47 MB binary): FB_DXC_DIR (default /root/tools/dxc) holds x/bin/dxc and x/lib;
# fetch.sh downloads it. The packages come from FB_UNITY_PKGS (the extracted Unity editor's built-in packages).
DXC_DIR = os.environ.get("FB_DXC_DIR", "/root/tools/dxc")
DXC = os.path.join(DXC_DIR, "x/bin/dxc")
ENV = dict(os.environ, LD_LIBRARY_PATH=os.path.join(DXC_DIR, "x/lib"))
PKGS = os.environ.get("FB_UNITY_PKGS", "/root/unity-pkgs/Editor/Data/Resources/PackageManager/BuiltInPackages")
INC = os.path.join(os.environ.get("TMPDIR", "/tmp"), "fb-shadercheck-inc")
os.makedirs(os.path.join(INC, "Packages"), exist_ok=True)
for _p in ("com.unity.render-pipelines.core", "com.unity.render-pipelines.universal",
           "com.unity.render-pipelines.universal-config", "com.unity.shadergraph"):
    _l = os.path.join(INC, "Packages", _p)
    if not os.path.exists(_l):
        os.symlink(os.path.join(PKGS, _p), _l)
CGINC = os.path.join(S, "cginc")
TMP = os.path.join(S, "tmp")
os.makedirs(TMP, exist_ok=True)

FBAPI = os.environ.get("FBAPI", "SHADER_API_D3D11=1")
VULKAN = "VULKAN" in FBAPI
API = [x for a in FBAPI.split(",") for x in ("-D", a)] + (["-spirv"] if VULKAN else [])
QUICK = os.environ.get("FBQUICK", "") not in ("", "0")

BLOCK = re.compile(r"\b(HLSLINCLUDE|HLSLPROGRAM|CGINCLUDE|CGPROGRAM)\b(.*?)\b(ENDHLSL|ENDCG)\b", re.S)


def keyword_sets(prog, stage):
    sets = []
    for m in re.finditer(r"#pragma[ \t]+(multi_compile\w*|shader_feature\w*)[ \t]*([^\n]*)", prog):
        kind, rest = m.group(1), m.group(2).split("//")[0].split()
        if kind == "multi_compile_instancing":
            sets.append(["", "INSTANCING_ON"])
            continue
        if kind.startswith("multi_compile_fog") or kind.startswith("multi_compile_fwd"):
            continue
        if kind.endswith("_vertex") and stage != "vs":
            continue
        if kind.endswith("_fragment") and stage != "ps":
            continue
        sets.append(["" if k == "_" or k.startswith("__") else k for k in rest])
    return sets


def variants(prog, stage):
    sets = keyword_sets(prog, stage)
    if not QUICK:
        return [[k for k in combo if k] for combo in itertools.product(*sets)] if sets else [[]]
    out = [[]]
    out.append([o[-1] for o in sets if o and o[-1]])
    for o in sets:
        for k in o:
            if k and [k] not in out:
                out.append([k])
    return out


def compile_one(path, src, entry, stage, defs, cg):
    fn = os.path.join(TMP, os.path.basename(path) + "." + entry + "." + stage + ".hlsl")
    with open(fn, "w") as f:
        f.write(src)
    args = [DXC, "-T", ("vs_6_0" if stage == "vs" else "ps_6_0"), "-E", entry, "-HV", "2018",
            "-I", os.path.dirname(os.path.abspath(path)), "-I", INC, "-Wno-conversion",
            "-Wno-unused-value", "-Wno-ignored-attributes", "-Wno-parentheses-equality", "-Wno-sign-compare", "-Wno-for-redefinition",
            *API, "-D", "UNITY_COMPILER_DXC=1", "-D", "SHADER_TARGET=45", "-D", "UNITY_VERSION=60003",
            "-D", "SHADER_STAGE_VERTEX=1" if stage == "vs" else "SHADER_STAGE_FRAGMENT=1", "-Fo", os.devnull]
    if cg:
        args += ["-I", CGINC, "-D", "SV_Target=SV_Target", "-D", "SV_Target0=SV_Target0", "-D", "SV_Depth=SV_Depth"]
    for d in defs:
        args += ["-D", d + "=1"]
        if d == "INSTANCING_ON":
            args += ["-D", "UNITY_DONT_INSTANCE_OBJECT_MATRICES=1"]   # (harness: DXC's ## differs from Unity's preprocessor)
    args.append(fn)
    r = subprocess.run(args, env=ENV, capture_output=True, text=True)
    return r.returncode, r.stderr


def check(path):
    text = open(path).read()
    includes = []
    fails = 0
    n = 0
    compiled = 0
    for m in BLOCK.finditer(text):
        kind, body = m.group(1), m.group(2)
        cg = kind.startswith("CG")
        if kind.endswith("INCLUDE"):
            includes.append(body)
            continue
        n += 1
        if cg and VULKAN:
            print("skip %s pass#%d (CG program: D3D11 path only)" % (os.path.basename(path), n))
            continue
        prog = "\n".join(includes) + "\n" + body
        if cg:
            prog = "#include \"fb_dxc_shim.hlsl\"\n#include \"HLSLSupport.cginc\"\n#include \"UnityShaderVariables.cginc\"\n" + prog
        entries = (("vs", re.search(r"#pragma\s+vertex\s+(\w+)", body)), ("ps", re.search(r"#pragma\s+fragment\s+(\w+)", body)))
        for stage, ent in entries:
            if not ent:
                continue
            for defs in variants(body, stage):
                rc, err = compile_one(path, prog, ent.group(1), stage, defs, cg)
                compiled += 1
                if rc != 0:
                    fails += 1
                    if fails <= 3:
                        print("FAIL %s pass#%d %s %s %s" % (os.path.basename(path), n, stage, ent.group(1), defs))
                        lines = err.splitlines()
                        keep = [l for i, l in enumerate(lines) if "error" in l or (i > 0 and "error" in lines[i - 1])]
                        print("\n".join(keep[:20]))
    print(("ok   " if fails == 0 else "FAIL ") + "%s (%d programs, %d compiles%s)" % (path, n, compiled, ", %d failed" % fails if fails else ""))
    return fails == 0


if __name__ == "__main__":
    res = [check(p) for p in sys.argv[1:]]
    sys.exit(0 if all(res) else 1)
