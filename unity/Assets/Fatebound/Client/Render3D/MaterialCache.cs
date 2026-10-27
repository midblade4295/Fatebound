// Facade materials -> Unity materials, rebuilt when the facade's version changes.
//  * BaseMaterial3D (StandardMaterial3D / ORMMaterial3D) -> Fatebound/Standard3D with its settings as uniforms and
//    Godot's render state (blend mode, cull, depth draw, no depth test) and queue (opaque / alpha scissor /
//    transparent + render_priority).
//  * ShaderMaterial -> the ported shader registered for its .gdshader path (ShaderRegistry), every parameter set by
//    name: Color -> SetColor when the Unity property is a Color (source_color: linearised like Godot's), else SetVector.
//  * next_pass materials are appended for single-surface meshes (Unity draws extra materials on the last submesh).
using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using Fatebound.GUI;
using Fatebound.Sim;
using UnityEngine;
using UnityEngine.Rendering;
using Material = UnityEngine.Material;
using Shader = UnityEngine.Shader;
using Texture = UnityEngine.Texture;
using Texture2D = Fatebound.GUI.Texture2D;

namespace Fatebound.Client
{
    public sealed class MaterialCache
    {
        sealed class Entry
        {
            public WeakReference<GMaterial> Source;
            public Material Mat;
            public int Version = int.MinValue;
            public int Variant;
        }

        readonly ConditionalWeakTable<GMaterial, Entry>[] _tables = { new ConditionalWeakTable<GMaterial, Entry>(), new ConditionalWeakTable<GMaterial, Entry>() };
        readonly List<Entry> _all = new List<Entry>();
        Shader _standard;
        Material _default, _skyDefault;
        int _sweep;

        Shader Standard => _standard ??= Shader.Find("Fatebound/Standard3D") ?? Resources.Load<Shader>("Shaders/FateboundStandard3D");

        /// <summary>Godot's default material for a surface without one (a white StandardMaterial3D).</summary>
        Material Default
        {
            get
            {
                if (_default == null)
                {
                    _default = new Material(Standard) { name = "fb-default", hideFlags = HideFlags.DontSave };
                }
                return _default;
            }
        }

        /// <summary>The Unity material for a facade material (variant 1: a multimesh's -- instanced colours on).</summary>
        public Material Get(GMaterial m, int variant = 0)
        {
            if (m == null) return Default;
            var table = _tables[variant];
            if (!table.TryGetValue(m, out var e))
            {
                e = new Entry { Source = new WeakReference<GMaterial>(m), Variant = variant };
                table.Add(m, e);
                _all.Add(e);
            }
            if (e.Mat == null || e.Version != m.version)
            {
                e.Version = m.version;
                Build(e, m);
            }
            return e.Mat;
        }

        /// <summary>A canvas_item ShaderMaterial's Unity material, or null when its shader has no Unity port (the GUI
        /// then draws the item with its plain material, as a missing shader would show in Godot).</summary>
        public Material GetCanvas(ShaderMaterial sm)
        {
            if (sm == null || ShaderRegistry.Find(sm.Shader) == null) return null;
            return Get(sm);
        }

        void Build(Entry e, GMaterial m)
        {
            switch (m)
            {
                case BaseMaterial3D b: BuildStandard(e, b); break;
                case ShaderMaterial sm: BuildShader(e, sm); break;
                default:
                    if (e.Mat == null) e.Mat = new Material(Standard) { name = m.GetType().Name, hideFlags = HideFlags.DontSave };
                    break;
            }
        }

        // ------------------------------------------------------------------ BaseMaterial3D
        static Texture Tex(Texture2D t) => t?.GetHandle() as Texture;

        // the material's sampler (BaseMaterial3D texture_filter / texture_repeat) for the textures it binds; Unity keeps
        // sampler state on the texture, so the last material to bind a shared texture decides (they agree in the game)
        static bool _repeat = true;
        static int _filter = 3;

        static void SetTex(Material mat, string prop, Texture2D t, Texture fallback)
        {
            var u = Tex(t);
            mat.SetTexture(prop, u != null ? u : fallback);
            if (u != null)
            {
                u.wrapMode = _repeat ? TextureWrapMode.Repeat : TextureWrapMode.Clamp;
                // Godot: 0 nearest, 1 linear, 2 nearest+mipmaps, 3 linear+mipmaps, 4/5 the anisotropic versions
                var fm = _filter == 0 || _filter == 2 || _filter == 4 ? FilterMode.Point : (_filter == 1 ? FilterMode.Bilinear : FilterMode.Trilinear);
                if (u.mipmapCount <= 1 && fm == FilterMode.Trilinear) fm = FilterMode.Bilinear;
                u.filterMode = fm;
                u.anisoLevel = _filter >= 4 ? 4 : 1;
            }
        }

        static Vector4 Channel(int ch)
        {
            switch (ch)
            {
                case 1: return new Vector4(0, 1, 0, 0);
                case 2: return new Vector4(0, 0, 1, 0);
                case 3: return new Vector4(0, 0, 0, 1);
                case 4: return new Vector4(0.299f, 0.587f, 0.114f, 0);     // grayscale
                default: return new Vector4(1, 0, 0, 0);
            }
        }

        void BuildStandard(Entry e, BaseMaterial3D b)
        {
            if (e.Mat == null || e.Mat.shader != Standard) e.Mat = new Material(Standard) { name = "std", hideFlags = HideFlags.DontSave };
            var mat = e.Mat;
            var white = UnityEngine.Texture2D.whiteTexture;
            var ac = b.AlbedoColor;
            mat.SetColor("_Color", new Color(ac.r, ac.g, ac.b, ac.a));          // (sRGB -> linear by Unity, as Godot's source_color)
            _repeat = b.TextureRepeat;
            _filter = b.TextureFilter;
            SetTex(mat, "_MainTex", b.AlbedoTexture, white);
            mat.SetVector("_UV1Scale", new Vector4(b.Uv1Scale.x, b.Uv1Scale.y, b.Uv1Scale.z, 0));
            mat.SetVector("_UV1Offset", new Vector4(b.Uv1Offset.x, b.Uv1Offset.y, b.Uv1Offset.z, 0));
            mat.SetFloat("_Metallic", (float)b.Metallic);
            mat.SetFloat("_Roughness", (float)b.Roughness);
            mat.SetFloat("_Specular", (float)b.MetallicSpecular);
            SetTex(mat, "_MetallicTex", b.MetallicTexture, white);
            mat.SetVector("_MetallicChannel", Channel((int)b.MetallicTextureChannel));
            SetTex(mat, "_RoughnessTex", b.RoughnessTexture, white);
            mat.SetVector("_RoughnessChannel", Channel((int)b.RoughnessTextureChannel));
            bool normal = b.NormalEnabled && b.NormalTexture != null;
            mat.SetFloat("_NormalOn", normal ? 1 : 0);
            mat.SetFloat("_NormalScale", (float)b.NormalScale);
            SetTex(mat, "_NormalTex", b.NormalTexture, white);
            mat.SetFloat("_EmissionOn", b.EmissionEnabled ? 1 : 0);
            var em = b.Emission;
            mat.SetColor("_Emission", new Color(em.r, em.g, em.b, 1));
            mat.SetFloat("_EmissionEnergy", (float)b.EmissionEnergyMultiplier);
            SetTex(mat, "_EmissionTex", b.EmissionTexture, b.EmissionTexture == null ? (b.EmissionOperator == 1 ? white : UnityEngine.Texture2D.blackTexture) : white);
            mat.SetFloat("_EmissionOp", (int)b.EmissionOperator);
            mat.SetFloat("_AOOn", b.AoEnabled && b.AoTexture != null ? 1 : 0);
            SetTex(mat, "_AOTex", b.AoTexture, white);
            mat.SetVector("_AOChannel", Channel((int)b.AoTextureChannel));
            mat.SetFloat("_Unshaded", b.ShadingMode == BaseMaterial3D.SHADING_MODE_UNSHADED ? 1 : 0);
            mat.SetFloat("_DiffuseBurley", b.DiffuseMode == BaseMaterial3D.DIFFUSE_BURLEY ? 1 : 0);
            mat.SetFloat("_SpecularOn", b.SpecularMode == BaseMaterial3D.SPECULAR_DISABLED ? 0 : 1);
            mat.SetFloat("_VertexColor", b.VertexColorUseAsAlbedo ? 1 : 0);
            mat.SetFloat("_VertexColorSrgb", b.VertexColorIsSrgb ? 1 : 0);
            mat.SetFloat("_FogOff", b.DisableFog ? 1 : 0);
            mat.SetFloat("_ReceiveShadows", b.DisableReceiveShadows ? 0 : 1);
            mat.SetFloat("_Billboard", (int)b.BillboardMode);
            mat.SetFloat("_BillboardKeepScale", b.BillboardKeepScale ? 1 : 0);
            mat.SetVector("_ParticlesAnim", new Vector4(Math.Max(1, b.ParticlesAnimHFrames), Math.Max(1, b.ParticlesAnimVFrames), b.ParticlesAnimLoop ? 1 : 0, 0));
            mat.SetFloat("_Grow", b.Grow ? (float)b.GrowAmount : 0f);
            mat.SetFloat("_DistanceFade", (int)b.DistanceFadeMode);
            mat.SetFloat("_DistanceFadeMin", (float)b.DistanceFadeMinDistance);
            mat.SetFloat("_DistanceFadeMax", (float)b.DistanceFadeMaxDistance);
            if (e.Variant == 1) mat.EnableKeyword("FB_MULTIMESH");

            // ---- transparency, blending, render state (Godot's scene shader: a non-mix blend mode or alpha blending
            // draws in the transparent pass, depth written per depth_draw_mode)
            int transparency = (int)b.Transparency;
            int blend = (int)b.BlendMode;
            bool alphaBlend = transparency == BaseMaterial3D.TRANSPARENCY_ALPHA || transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS;
            bool transparentPass = alphaBlend || blend != BaseMaterial3D.BLEND_MODE_MIX || b.DistanceFadeMode == BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA;
            int alphaMode = transparency == BaseMaterial3D.TRANSPARENCY_ALPHA ? 1
                : transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR ? 2
                : transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH ? 3
                : transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS ? 4 : 0;
            if (blend != BaseMaterial3D.BLEND_MODE_MIX && alphaMode == 0) alphaMode = 1;
            mat.SetFloat("_AlphaMode", alphaMode);
            mat.SetFloat("_AlphaScissor", (float)b.AlphaScissorThreshold);
            mat.SetFloat("_BlendModeFog", blend == BaseMaterial3D.BLEND_MODE_ADD ? 1 : blend == BaseMaterial3D.BLEND_MODE_SUB ? 2 : blend == BaseMaterial3D.BLEND_MODE_MUL ? 3 : 0);
            BlendMode src = BlendMode.One, dst = BlendMode.Zero;
            BlendOp op = BlendOp.Add;
            if (transparentPass)
            {
                switch (blend)
                {
                    case BaseMaterial3D.BLEND_MODE_ADD: src = BlendMode.SrcAlpha; dst = BlendMode.One; break;
                    case BaseMaterial3D.BLEND_MODE_SUB: src = BlendMode.SrcAlpha; dst = BlendMode.One; op = BlendOp.ReverseSubtract; break;
                    case BaseMaterial3D.BLEND_MODE_MUL: src = BlendMode.DstColor; dst = BlendMode.Zero; break;
                    case BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA: src = BlendMode.One; dst = BlendMode.OneMinusSrcAlpha; break;
                    default: src = BlendMode.SrcAlpha; dst = BlendMode.OneMinusSrcAlpha; break;
                }
            }
            mat.SetFloat("_SrcBlend", (float)src);
            mat.SetFloat("_DstBlend", (float)dst);
            mat.SetFloat("_BlendOp", (float)op);
            int depthDraw = (int)b.DepthDrawMode;
            bool zwrite = depthDraw == BaseMaterial3D.DEPTH_DRAW_ALWAYS || (depthDraw == BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY && !transparentPass);
            mat.SetFloat("_ZWrite", zwrite ? 1 : 0);
            mat.SetFloat("_ZTest", b.NoDepthTest ? (float)CompareFunction.Always : (float)CompareFunction.LessEqual);
            int cull = (int)b.CullMode;
            mat.SetFloat("_Cull", cull == BaseMaterial3D.CULL_DISABLED ? (float)CullMode.Off : cull == BaseMaterial3D.CULL_FRONT ? (float)CullMode.Front : (float)CullMode.Back);
            int queue = transparentPass ? (int)RenderQueue.Transparent : alphaMode == 2 || alphaMode == 3 ? (int)RenderQueue.AlphaTest : (int)RenderQueue.Geometry;
            mat.renderQueue = queue + Math.Max(-50, Math.Min(50, b.RenderPriority));
            mat.SetOverrideTag("RenderType", transparentPass ? "Transparent" : "Opaque");
            mat.SetShaderPassEnabled("ShadowCaster", !transparentPass);
            mat.enableInstancing = true;
        }

        // ------------------------------------------------------------------ ShaderMaterial
        void BuildShader(Entry e, ShaderMaterial sm)
        {
            var shader = ShaderRegistry.Find(sm.Shader);
            if (shader == null) shader = Standard;
            if (e.Mat == null || e.Mat.shader != shader) e.Mat = new Material(shader) { name = string.IsNullOrEmpty(sm.Shader?.ResourcePath) ? "shader" : sm.Shader.ResourcePath, hideFlags = HideFlags.DontSave };
            var mat = e.Mat;
            ShaderRegistry.ApplyDefaults(mat, sm.Shader);
            foreach (var kv in sm.Params) SetParam(mat, kv.Key, kv.Value);
            mat.renderQueue = ShaderRegistry.Queue(shader, sm.RenderPriority);
            mat.enableInstancing = true;
            if (e.Variant == 1) mat.EnableKeyword("FB_MULTIMESH");
        }

        /// <summary>One parameter onto a material or property block, Godot's value types to Unity's.</summary>
        public static void SetParam(Material mat, string name, object value) => SetParam(mat, null, name, value);

        public static void SetParam(Material mat, MaterialPropertyBlock mpb, string name, object value)
        {
            var shader = mat != null ? mat.shader : null;
            int id = Shader.PropertyToID(name);
            switch (value)
            {
                case Col c:
                    {
                        bool isColor = shader != null && IsColorProperty(shader, name);
                        var v = isColor ? (Vector4)new Color(c.r, c.g, c.b, c.a) : new Vector4(c.r, c.g, c.b, c.a);
                        if (mpb != null) { if (isColor) mpb.SetColor(id, new Color(c.r, c.g, c.b, c.a)); else mpb.SetVector(id, v); }
                        else if (isColor) mat.SetColor(id, new Color(c.r, c.g, c.b, c.a));
                        else mat.SetVector(id, v);
                        break;
                    }
                case double d: Set(mat, mpb, id, (float)d); break;
                case float f: Set(mat, mpb, id, f); break;
                case long l: Set(mat, mpb, id, l); break;
                case int i: Set(mat, mpb, id, i); break;
                case bool b: Set(mat, mpb, id, b ? 1f : 0f); break;
                case Vec2 v2: SetV(mat, mpb, id, new Vector4(v2.x, v2.y, 0, 0)); break;
                case Vec3 v3: SetV(mat, mpb, id, new Vector4(v3.x, v3.y, v3.z, 0)); break;
                case Vec4 v4: SetV(mat, mpb, id, new Vector4(v4.x, v4.y, v4.z, v4.w)); break;
                case Quat q: SetV(mat, mpb, id, new Vector4(q.x, q.y, q.z, q.w)); break;
                case Basis bs:
                    {
                        // mat3 in Godot's (column) layout, padded
                        var m = Matrix4x4.identity;
                        for (int c = 0; c < 3; c++) { var col = bs.GetColumn(c); m.SetColumn(c, new Vector4(col.x, col.y, col.z, 0)); }
                        if (mpb != null) mpb.SetMatrix(id, m); else mat.SetMatrix(id, m);
                        break;
                    }
                case Xform3 t:
                    {
                        var m = Matrix4x4.identity;
                        for (int c = 0; c < 3; c++) { var col = t.basis.GetColumn(c); m.SetColumn(c, new Vector4(col.x, col.y, col.z, 0)); }
                        m.SetColumn(3, new Vector4(t.origin.x, t.origin.y, t.origin.z, 1));
                        if (mpb != null) mpb.SetMatrix(id, m); else mat.SetMatrix(id, m);
                        break;
                    }
                case Texture2D t:
                    {
                        var u = t.GetHandle() as Texture;
                        if (u == null) break;
                        if (mpb != null) mpb.SetTexture(id, u); else mat.SetTexture(id, u);
                        break;
                    }
                case Projection pj:
                    {
                        // mat4, Godot's column layout
                        var m = new Matrix4x4(new Vector4(pj.x.x, pj.x.y, pj.x.z, pj.x.w), new Vector4(pj.y.x, pj.y.y, pj.y.z, pj.y.w),
                            new Vector4(pj.z.x, pj.z.y, pj.z.z, pj.z.w), new Vector4(pj.w.x, pj.w.y, pj.w.z, pj.w.w));
                        if (mpb != null) mpb.SetMatrix(id, m); else mat.SetMatrix(id, m);
                        break;
                    }
                default:
                    SetArray(mat, mpb, id, value);
                    break;
            }
        }

        // Uniform arrays (float x[N], vec2/3/4 x[N]): Unity fixes an array's length the first time it's set, so every
        // array goes up padded to ARRAY_PAD (more than any the game declares; the shader reads its own N).
        const int ARRAY_PAD = 64;
        static readonly float[] _fpad = new float[ARRAY_PAD];
        static readonly Vector4[] _vpad = new Vector4[ARRAY_PAD];

        static void SetArray(Material mat, MaterialPropertyBlock mpb, int id, object value)
        {
            System.Collections.IEnumerable items;
            switch (value)
            {
                case string _: return;
                case System.Collections.IEnumerable e: items = e; break;
                default: return;
            }
            // floats or vectors? (decided by the first element)
            int n = 0;
            bool vectors = false, decided = false;
            foreach (var raw in items)
            {
                if (n >= ARRAY_PAD) break;
                object it = raw is Var vv ? vv.Obj : raw;
                Vector4 v4;
                float f;
                bool isVec = ToVector(it, out v4);
                bool isNum = !isVec && ToFloat(it, out f);
                if (!decided) { vectors = isVec; decided = true; }
                if (vectors) _vpad[n] = isVec ? v4 : Vector4.zero;
                else _fpad[n] = ToFloat(it, out f) ? f : 0f;
                n++;
            }
            if (!decided) return;
            if (vectors)
            {
                for (int i = n; i < ARRAY_PAD; i++) _vpad[i] = Vector4.zero;
                if (mpb != null) mpb.SetVectorArray(id, _vpad); else mat.SetVectorArray(id, _vpad);
            }
            else
            {
                for (int i = n; i < ARRAY_PAD; i++) _fpad[i] = 0f;
                if (mpb != null) mpb.SetFloatArray(id, _fpad); else mat.SetFloatArray(id, _fpad);
            }
        }

        static bool ToVector(object o, out Vector4 v)
        {
            switch (o)
            {
                case Vec2 a: v = new Vector4(a.x, a.y, 0, 0); return true;
                case Vec3 b: v = new Vector4(b.x, b.y, b.z, 0); return true;
                case Vec4 c: v = new Vector4(c.x, c.y, c.z, c.w); return true;
                case Col d: v = new Vector4(d.r, d.g, d.b, d.a); return true;
                case Quat q: v = new Vector4(q.x, q.y, q.z, q.w); return true;
            }
            v = default;
            return false;
        }

        static bool ToFloat(object o, out float f)
        {
            switch (o)
            {
                case float a: f = a; return true;
                case double b: f = (float)b; return true;
                case int c: f = c; return true;
                case long d: f = d; return true;
                case bool e: f = e ? 1f : 0f; return true;
            }
            f = 0f;
            return false;
        }

        static void Set(Material m, MaterialPropertyBlock p, int id, float v) { if (p != null) p.SetFloat(id, v); else m.SetFloat(id, v); }
        static void SetV(Material m, MaterialPropertyBlock p, int id, Vector4 v) { if (p != null) p.SetVector(id, v); else m.SetVector(id, v); }

        static readonly Dictionary<(Shader, string), bool> _isColor = new Dictionary<(Shader, string), bool>();

        static bool IsColorProperty(Shader s, string name)
        {
            if (_isColor.TryGetValue((s, name), out bool b)) return b;
            int i = s.FindPropertyIndex(name);
            b = i >= 0 && s.GetPropertyType(i) == ShaderPropertyType.Color;
            _isColor[(s, name)] = b;
            return b;
        }

        // ------------------------------------------------------------------ per node
        public Material[] ForMesh(MeshInstance3D mi, int[] submeshOf, int submeshCount)
        {
            var mesh = mi.Mesh;
            int surfaces = mesh?.GetSurfaceCount() ?? 0;
            var list = new List<Material>(submeshCount + 1);
            for (int s = 0; s < surfaces && list.Count < submeshCount; s++)
            {
                if (submeshOf == null || s >= submeshOf.Length || submeshOf[s] < 0) continue;
                list.Add(Get(mi.GetActiveMaterial(s)));
            }
            // next_pass: Unity draws materials past the submesh count on the last submesh -- right for one surface
            if (surfaces == 1 && list.Count == 1)
                for (var np = mi.GetActiveMaterial(0)?.NextPass; np != null; np = np.NextPass) list.Add(Get(np));
            return list.ToArray();
        }

        public Material[] ForMultiMesh(MultiMeshInstance3D mmi, int[] submeshOf)
        {
            var mesh = mmi.Multimesh?.Mesh;
            var r = new Material[submeshOf.Length];
            for (int s = 0; s < submeshOf.Length; s++)
            {
                var m = mmi.MaterialOverride ?? mesh?.SurfaceGetMaterial(s);
                r[s] = Get(m, 1);
            }
            return r;
        }

        readonly ConditionalWeakTable<Sprite3D, Material> _sprites = new ConditionalWeakTable<Sprite3D, Material>();

        public Material ForSprite(Sprite3D s)
        {
            if (s.MaterialOverride != null) return Get(s.MaterialOverride);
            if (!_sprites.TryGetValue(s, out var mat))
            {
                mat = new Material(Standard) { name = "sprite", hideFlags = HideFlags.DontSave };
                _sprites.Add(s, mat);
            }
            // SpriteBase3D's own material: albedo = texture * modulate (vertex colour), alpha cut or blend, double sided
            mat.SetTexture("_MainTex", Tex(s.Texture) ?? UnityEngine.Texture2D.whiteTexture);
            mat.SetColor("_Color", Color.white);
            mat.SetFloat("_VertexColor", 1);
            mat.SetFloat("_Unshaded", s.Shaded ? 0 : 1);
            mat.SetFloat("_Billboard", (int)s.Billboard);
            mat.SetFloat("_Cull", s.DoubleSided ? (float)CullMode.Off : (float)CullMode.Back);
            bool blend = s.Transparent && s.AlphaCut == SpriteBase3D.ALPHA_CUT_DISABLED;
            mat.SetFloat("_AlphaMode", s.AlphaCut == SpriteBase3D.ALPHA_CUT_DISCARD ? 2 : blend ? 1 : 0);
            mat.SetFloat("_SrcBlend", blend ? (float)BlendMode.SrcAlpha : (float)BlendMode.One);
            mat.SetFloat("_DstBlend", blend ? (float)BlendMode.OneMinusSrcAlpha : (float)BlendMode.Zero);
            mat.SetFloat("_ZWrite", blend ? 0 : 1);
            mat.SetFloat("_ZTest", s.NoDepthTest ? (float)CompareFunction.Always : (float)CompareFunction.LessEqual);
            mat.renderQueue = (blend ? (int)RenderQueue.Transparent : (int)RenderQueue.AlphaTest) + s.RenderPriority;
            return mat;
        }

        public void ApplyInstanceParams(Renderer r, ref MaterialPropertyBlock mpb, GeometryInstance3D gi)
        {
            var ps = gi.InstanceShaderParameters;
            if (ps.Count == 0)
            {
                if (r != null && mpb != null) { r.SetPropertyBlock(null); }
                if (mpb != null) mpb.Clear();
                return;
            }
            if (mpb == null) mpb = new MaterialPropertyBlock();
            mpb.Clear();
            var mat = r != null ? r.sharedMaterial : null;
            foreach (var kv in ps) SetParam(mat, mpb, kv.Key, kv.Value);
            r?.SetPropertyBlock(mpb);
        }

        // ------------------------------------------------------------------ sky
        readonly ConditionalWeakTable<Sky, Material> _skies = new ConditionalWeakTable<Sky, Material>();

        public Material ForSky(Sky sky)
        {
            if (sky == null) return null;
            if (!_skies.TryGetValue(sky, out var mat))
            {
                var sh = Shader.Find("Fatebound/ProceduralSky") ?? Resources.Load<Shader>("Shaders/FateboundSky");
                if (sh == null) { Debug.LogError("Fatebound: no sky shader (Fatebound/ProceduralSky)"); return null; }
                mat = new Material(sh) { name = "sky", hideFlags = HideFlags.DontSave };
                _skies.Add(sky, mat);
            }
            if (sky.SkyMaterial is ProceduralSkyMaterial p)
            {
                mat.SetColor("_SkyTop", Conv.Color(p.SkyTopColor));
                mat.SetColor("_SkyHorizon", Conv.Color(p.SkyHorizonColor));
                mat.SetFloat("_SkyCurve", (float)p.SkyCurve);
                mat.SetFloat("_SkyEnergy", (float)p.SkyEnergyMultiplier);
                mat.SetColor("_GroundBottom", Conv.Color(p.GroundBottomColor));
                mat.SetColor("_GroundHorizon", Conv.Color(p.GroundHorizonColor));
                mat.SetFloat("_GroundCurve", (float)p.GroundCurve);
                mat.SetFloat("_GroundEnergy", (float)p.GroundEnergyMultiplier);
                mat.SetFloat("_SunAngleMax", (float)p.SunAngleMax);
                mat.SetFloat("_SunCurve", (float)p.SunCurve);
            }
            return mat;
        }

        public void Sweep()
        {
            if (++_sweep < 600) return;
            _sweep = 0;
            for (int i = _all.Count - 1; i >= 0; i--)
            {
                var e = _all[i];
                if (e.Source.TryGetTarget(out _)) continue;
                if (e.Mat != null) UnityEngine.Object.Destroy(e.Mat);
                _all.RemoveAt(i);
            }
        }
    }
}
