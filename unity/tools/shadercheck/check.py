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


# FBFXC=1: compile with FXC instead (D3DCompiler_47.dll, Unity's first stage for Vulkan / GLES / Metal: its bytecode then
# goes through HLSLcc) -- fxc/fxcrun.exe (built with x86_64-w64-mingw32-gcc from fxc/fxcrun.c) run under Wine, with the
# DLL from the Unity editor (Editor/Data/Tools/D3DCompiler_47.dll) beside it in FB_FXC_DIR (default /root/tools).
FXC = os.environ.get("FBFXC", "") not in ("", "0")
FXC_DIR = os.environ.get("FB_FXC_DIR", "/root/tools")
# (CG programs under FXC: Unity's own CGIncludes, from the same editor -- setup.sh puts them beside the DLL)
CGINC_FXC = os.environ.get("FB_UNITY_CGINC", os.path.join(FXC_DIR, "Editor/Data/Resources/CGIncludes"))
WINE_ENV = dict(os.environ, WINEDEBUG="-all", WINEPREFIX=os.environ.get("WINEPREFIX", "/root/.wine-fxc"))


def preprocess_fxc(path, fn, stage, defs, cg):
    # Unity preprocesses a program itself and hands FXC the result: DXC's preprocessor (clang's) stands in for Unity's
    # here (FXC's own chokes on the URP includes' empty function-like macros); FXC then compiles the expanded source
    pre = fn + ".pre.hlsl"
    pargs = [DXC, "-P", "-Fi", pre, "-I", os.path.dirname(os.path.abspath(path)), "-I", INC]
    if cg:
        pargs += ["-I", CGINC_FXC if os.path.isdir(CGINC_FXC) else CGINC]
    for d in ("UNITY_COMPILER_HLSL", "UNITY_COMPILER_HLSLCC"):
        pargs += ["-D", d + "=1"]
    for a in FBAPI.split(","):
        pargs += ["-D", a]
    pargs += ["-D", "SHADER_TARGET=35", "-D", "UNITY_VERSION=60003",
              "-D", "SHADER_STAGE_VERTEX=1" if stage == "vs" else "SHADER_STAGE_FRAGMENT=1"]
    for d in defs:
        pargs += ["-D", d + "=1"]
        if d == "INSTANCING_ON":
            pargs += ["-D", "UNITY_DONT_INSTANCE_OBJECT_MATRICES=1"]
    pargs.append(fn)
    r = subprocess.run(pargs, env=ENV, capture_output=True, text=True)
    return pre, r.returncode, r.stderr


def run_fxc_batch(jobs):
    """jobs: [(file, entry, target)] -> [(rc, messages)], one Wine process for all (restarted after a crash: FXC
    crashing on a program is itself a result -- Unity then drops that pass from the build)."""
    results = []
    i = 0
    while i < len(jobs):
        lst = os.path.join(TMP, "fxc_jobs.txt")
        with open(lst, "w") as f:
            for (fn, entry, target) in jobs[i:]:
                f.write("%s\t%s\t%s\n" % (fn, entry, target))
        r = subprocess.run(["/usr/lib/wine/wine64", os.path.join(FXC_DIR, "fxcrun.exe"), "@" + lst], env=WINE_ENV,
                           capture_output=True, text=True, cwd=FXC_DIR)
        out = r.stdout.replace("\r", "")
        done = 0
        msg = []
        for line in out.split("\n"):
            m = re.match(r"### (\d+) rc=(\d)", line)
            if m:
                results.append((int(m.group(2)), "\n".join(msg)))
                msg = []
                done += 1
            else:
                msg.append(line)
        i += done
        if i < len(jobs):
            results.append((1, "\n".join(msg) + "\nerror: FXC crashed on this program (Unity then drops the pass from the build)"))
            i += 1
    return results


def compile_one(path, src, entry, stage, defs, cg):
    fn = os.path.join(TMP, os.path.basename(path) + "." + entry + "." + stage + ".hlsl")
    with open(fn, "w") as f:
        f.write(src)
    if FXC:
        return preprocess_fxc(path, fn, stage, defs, cg)
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


# ShaderLab's own words (case-insensitive): a property named like one stops Unity parsing the whole shader, which then
# imports nameless and draws pink on the device (fx_*.shader's "color" did) -- the ports call such uniforms gd_<name>
SHADERLAB_WORDS = set(w.lower() for w in """Float Int Integer Range Color Vector Any Shader Properties SubShader Pass Tags LOD
    Cull ZTest ZWrite ZClip Offset Blend BlendOp AlphaToMask ColorMask Conservative Stencil Name UsePass GrabPass Fallback
    CustomEditor Category Fog Lighting Material SetTexture Combine AlphaTest SeparateSpecular ColorMaterial BindChannels Bind
    Mode Density On Off Front Back Less Greater LEqual GEqual Equal NotEqual Always Never One Zero Add Sub RevSub Min Max Ref
    ReadMask WriteMask Comp PassOp FailOp ZFailOp Keep Replace Invert Primary Texture Previous Constant Lerp Double Quad Alpha
    Ambient Diffuse Specular Shininess Emission Matrix Vertex Normal Tangent Dependency True False Global Exp Exp2 Linear
    Multiply Screen Overlay Darken Lighten Clear Copy Set Or Xor""".split())


def lint_properties(path, text):
    m = re.search(r"\bProperties\s*\{", text)
    if not m:
        return 0
    depth, i = 0, text.index("{", m.start())
    for j in range(i, len(text)):
        depth += 1 if text[j] == "{" else -1 if text[j] == "}" else 0
        if depth == 0:
            break
    bad = 0
    for line in text[i + 1:j].splitlines():
        p = re.match(r"\s*((?:\[[^\]]*\]\s*)*)([A-Za-z_]\w*)\s*\(", line)
        if p and p.group(2).lower() in SHADERLAB_WORDS:
            print("FAIL %s: property '%s' is a ShaderLab keyword (Unity can't parse the shader)" % (os.path.basename(path), p.group(2)))
            bad += 1
    return bad


def check(path):
    text = open(path).read()
    if lint_properties(path, text):
        return False
    includes = []
    pending = []
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
        if cg and VULKAN and not FXC:
            print("skip %s pass#%d (CG program: D3D11 path only)" % (os.path.basename(path), n))
            continue
        prog = "\n".join(includes) + "\n" + body
        if cg:
            shim = "" if FXC else "#include \"fb_dxc_shim.hlsl\"\n"     # (FXC takes the DX9-style samplers itself)
            prog = shim + "#include \"HLSLSupport.cginc\"\n#include \"UnityShaderVariables.cginc\"\n" + prog
        entries = (("vs", re.search(r"#pragma\s+vertex\s+(\w+)", body)), ("ps", re.search(r"#pragma\s+fragment\s+(\w+)", body)))
        for stage, ent in entries:
            if not ent:
                continue
            for k, defs in enumerate(variants(body, stage)):
                if FXC:
                    # (each variant's expanded source kept under its own name for the batch)
                    fn_v = os.path.join(TMP, "%s.p%d.%s.%s.v%d.hlsl" % (os.path.basename(path), n, ent.group(1), stage, k))
                    with open(fn_v, "w") as f:
                        f.write(prog)
                    pre, rc, err = preprocess_fxc(path, fn_v, stage, defs, cg)
                    if rc != 0:
                        pending.append(("FAIL %s pass#%d %s %s %s (preprocess)" % (os.path.basename(path), n, stage, ent.group(1), defs), None, err))
                    else:
                        pending.append(("FAIL %s pass#%d %s %s %s" % (os.path.basename(path), n, stage, ent.group(1), defs),
                                        (pre, ent.group(1), "vs_5_0" if stage == "vs" else "ps_5_0"), ""))
                    continue
                rc, err = compile_one(path, prog, ent.group(1), stage, defs, cg)
                compiled += 1
                if rc != 0:
                    fails += 1
                    if fails <= 3:
                        print("FAIL %s pass#%d %s %s %s" % (os.path.basename(path), n, stage, ent.group(1), defs))
                        lines = err.splitlines()
                        keep = [l for i, l in enumerate(lines) if "error" in l or (i > 0 and "error" in lines[i - 1])]
                        print("\n".join(keep[:20]))
    if FXC and pending:
        jobs = [p[1] for p in pending if p[1] is not None]
        res = iter(run_fxc_batch(jobs))
        for label, job, err in pending:
            rc, msg = (1, err) if job is None else next(res)
            compiled += 1
            if rc != 0:
                fails += 1
                if fails <= 3:
                    print(label)
                    keep = [l for l in msg.splitlines() if "error" in l]
                    print("\n".join(keep[:12]))
    print(("ok   " if fails == 0 else "FAIL ") + "%s (%d programs, %d compiles%s)" % (path, n, compiled, ", %d failed" % fails if fails else ""), flush=True)
    return fails == 0


if __name__ == "__main__":
    res = [check(p) for p in sys.argv[1:]]
    sys.exit(0 if all(res) else 1)
