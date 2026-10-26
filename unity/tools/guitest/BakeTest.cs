// The C# side of the baked-asset parity test (tools/parity/bake.sh; Godot's side: tools/parity/godot_bake.gd): loads each
// path through the port's ResourceLoader (the baked .bytes under Assets/Resources/res, GUI/Scene3D/BakedLoader.cs) and
// prints the same lines godot_bake.gd prints from Godot's own load(). Then the threaded API (load_threaded_request ->
// status -> get) on the same paths, and the classes/properties the loader couldn't map (stderr).
using System;
using System.Collections.Generic;
using System.Linq;
using Fatebound.GUI;
using Fatebound.Sim;

namespace GuiTest
{
    public static class BakeTest
    {
        static readonly string[] MatProps = { "albedo_color", "albedo_texture", "transparency", "cull_mode", "shading_mode", "diffuse_mode",
            "specular_mode", "metallic", "metallic_specular", "roughness", "vertex_color_use_as_albedo", "vertex_color_is_srgb",
            "emission_enabled", "emission", "emission_energy_multiplier", "emission_operator", "emission_texture", "normal_enabled",
            "normal_scale", "normal_texture", "billboard_mode", "billboard_keep_scale", "particles_anim_h_frames",
            "particles_anim_v_frames", "particles_anim_loop", "texture_filter", "texture_repeat", "depth_draw_mode", "no_depth_test",
            "alpha_scissor_threshold", "uv1_scale", "uv1_offset", "render_priority", "grow", "grow_amount" };
        static readonly string[] PpmProps = { "direction", "spread", "flatness", "gravity", "initial_velocity_min", "initial_velocity_max",
            "angular_velocity_min", "angular_velocity_max", "angle_min", "angle_max", "scale_min", "scale_max", "scale_curve", "color",
            "color_ramp", "alpha_curve", "emission_curve", "emission_shape", "emission_sphere_radius", "lifetime_randomness",
            "particle_flag_align_y", "velocity_pivot", "collision_mode", "collision_friction", "collision_bounce", "sub_emitter_mode",
            "sub_emitter_frequency", "damping_min", "damping_max" };
        static readonly string[] GpProps = { "amount", "lifetime", "one_shot", "emitting", "explosiveness", "randomness", "fixed_fps", "sub_emitter",
            "sorting_offset", "trail_lifetime", "local_coords", "draw_passes" };

        static Dictionary<object, int> _ids;
        static HashSet<object> _dumped;

        static void P(string k, string v) => Console.WriteLine(k + "|" + v);
        static string S(object v) => v is Resource r ? Rid(r) : v is Enum e ? Convert.ToInt64(e).ToString() : GD.Str(Var.Of(v));

        static string Md5(byte[] b)
        {
            using (var m = System.Security.Cryptography.MD5.Create())
                return string.Concat(m.ComputeHash(b).Select(x => x.ToString("x2"))).Substring(0, 16);
        }

        static string Rel(Node root, Node n)
        {
            if (n == root) return ".";
            var parts = new List<string>();
            while (n != null && n != root) { parts.Insert(0, n.Name); n = n.GetParent(); }
            return string.Join("/", parts);
        }

        static string Rid(Resource r)
        {
            if (r == null) return "-";
            if (!string.IsNullOrEmpty(r.ResourcePath) && !r.ResourcePath.Contains("::")) return "file:" + r.ResourcePath;
            if (!_ids.TryGetValue(r, out int id)) _ids[r] = id = _ids.Count;
            return "#" + id;
        }

        static object Get(object o, string name)
        {
            try { return PropertyPath.Get(o, name); }
            catch (Exception) { return "<missing " + name + ">"; }
        }

        static void Props(string key, object o, string[] names)
        {
            foreach (var n in names)
            {
                var v = Get(o, n);
                P(key + "|" + n, S(v));
                if (v is Resource r) Dres(r);
            }
        }

        public static int Run(string[] paths)
        {
            foreach (var path in paths)
            {
                _ids = new Dictionary<object, int>();
                _dumped = new HashSet<object>();
                var r = ResourceLoader.Load(path);
                if (r == null) { P("file", path + "|null"); continue; }
                P("file", path + "|" + (r is PackedScene ? "PackedScene" : r is BakedScriptResource ? "Resource" : r.GetType().Name));
                if (r is PackedScene ps)
                {
                    var inst = ps.Instantiate();
                    Walk(inst, inst);
                    inst.Free();
                }
                else Dres(r);
            }
            // the threaded API: request everything, poll, get (the baked ones decode on workers)
            GC.Collect();                   // (drop the cached ones: the requests below load on workers)
            GC.WaitForPendingFinalizers();
            var t0 = DateTime.UtcNow;
            int bad = 0;
            const string Missing = "res://assets/no_such_model.glb";
            ResourceLoader.LoadThreadedRequest(Missing);
            foreach (var path in paths) ResourceLoader.LoadThreadedRequest(path);
            foreach (var path in paths)
            {
                int st;
                while ((st = ResourceLoader.LoadThreadedGetStatus(path)) == ResourceLoader.THREAD_LOAD_IN_PROGRESS) System.Threading.Thread.Sleep(1);
                var got = ResourceLoader.LoadThreadedGet(path);
                if (st != ResourceLoader.THREAD_LOAD_LOADED || got != ResourceLoader.Load(path)) { bad++; Console.Error.WriteLine("threaded load: " + path + " status " + st); }
                if (!ResourceLoader.Exists(path)) { bad++; Console.Error.WriteLine("exists: false for " + path); }
            }
            while (ResourceLoader.LoadThreadedGetStatus(Missing) == ResourceLoader.THREAD_LOAD_IN_PROGRESS) System.Threading.Thread.Sleep(1);
            if (ResourceLoader.LoadThreadedGetStatus(Missing) != ResourceLoader.THREAD_LOAD_FAILED || ResourceLoader.LoadThreadedGet(Missing) != null)
            { bad++; Console.Error.WriteLine("threaded load of a missing file: not FAILED"); }
            if (ResourceLoader.LoadThreadedGetStatus(Missing) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE) { bad++; Console.Error.WriteLine("status after get: not INVALID_RESOURCE"); }
            if (ResourceLoader.Exists(Missing)) { bad++; Console.Error.WriteLine("exists: true for a missing file"); }
            Console.Error.WriteLine("threaded: " + paths.Length + " paths, " + bad + " problems, " + (int)(DateTime.UtcNow - t0).TotalMilliseconds + " ms");
            foreach (var u in BakedLoader.Unmapped) Console.Error.WriteLine("unmapped: " + u);
            return bad == 0 ? 0 : 1;
        }

        static void Walk(Node n, Node root)
        {
            string path = Rel(root, n);
            P("node|" + path, n.GetClass() + "|owner=" + (n.Owner != null ? Rel(root, n.Owner) : "-") + "|children=" + n.GetChildCount());
            var metas = n.GetMetaList().ToList();
            metas.Sort(StringComparer.Ordinal);
            foreach (var k in metas) P("meta|" + path + "|" + k, S(n.GetMeta(k)));
            if (n is Node3D n3)
            {
                P("xf|" + path, S(n3.Transform));
                if (!n3.Visible) P("hidden|" + path, "");
            }
            if (n is MeshInstance3D mi)
            {
                P("mi|" + path, "skeleton=" + mi.Skeleton + "|mesh=" + Rid(mi.Mesh) + "|skin=" + Rid(mi.Skin) + "|override=" + Rid(mi.MaterialOverride) + "|cast=" + (int)mi.CastShadow);
                for (int i = 0; i < mi.GetSurfaceOverrideMaterialCount(); i++)
                    if (mi.GetSurfaceOverrideMaterial(i) != null) P("mi_so|" + path + "|" + i, Rid(mi.GetSurfaceOverrideMaterial(i)));
                if (mi.Mesh is ArrayMesh am)
                    for (int i = 0; i < am.GetBlendShapeCount(); i++) P("mi_bs|" + path + "|" + i, GD.Str(mi.GetBlendShapeValue(i)));
                Dres(mi.Mesh);
                Dres(mi.Skin);
                Dres(mi.MaterialOverride);
            }
            if (n is Skeleton3D sk)
            {
                P("skel|" + path, sk.GetBoneCount().ToString());
                for (int i = 0; i < sk.GetBoneCount(); i++)
                    P("bone|" + path + "|" + i, sk.GetBoneName(i) + "|" + sk.GetBoneParent(i) + "|" + S(sk.GetBoneRest(i)) + "|" + S(sk.GetBonePosePosition(i)) + "|" +
                        S(sk.GetBonePoseRotation(i)) + "|" + S(sk.GetBonePoseScale(i)) + "|" + S(sk.IsBoneEnabled(i)));
            }
            if (n is AnimationPlayer ap)
            {
                var libs = ap.GetAnimationLibraryList().ToList();
                libs.Sort(StringComparer.Ordinal);
                P("ap|" + path, "root=" + ap.RootNode + "|libs=" + string.Join(",", libs));
                foreach (var l in libs)
                {
                    P("ap_lib|" + path + "|" + l, Rid(ap.GetAnimationLibrary(l)));
                    Dres(ap.GetAnimationLibrary(l));
                }
            }
            if (n is BoneAttachment3D ba) P("ba|" + path, ba.GetBoneName() + "|" + ba.GetBoneIdx());
            if (n is GPUParticles3D gp)
            {
                Props("gp|" + path, gp, GpProps);
                P("gp|" + path + "|process_material", Rid(gp.ProcessMaterial));
                P("gp|" + path + "|draw_pass_1", Rid(gp.DrawPass1));
                Dres(gp.ProcessMaterial);
                Dres(gp.DrawPass1);
            }
            foreach (var c in n.GetChildren()) Walk(c, root);
        }

        static void Dres(Resource r)
        {
            if (r == null || Rid(r).StartsWith("file:") || !_dumped.Add(r)) return;
            string id = Rid(r);
            switch (r)
            {
                case ArrayMesh m:
                {
                    P("mesh" + id, "surfaces=" + m.GetSurfaceCount() + "|name=" + m.ResourceName + "|blend=" + string.Join(",", m.BlendShapeNames) + "|aabb=" + S(m.GetAabb()));
                    var ss = m.GetSurfaces();
                    for (int i = 0; i < ss.Count; i++)
                    {
                        var s = ss[i];
                        P("surf" + id + "|" + i, "prim=" + (int)s.Primitive + "|verts=" + m.SurfaceGetArrayLen(i) + "|idx=" + m.SurfaceGetArrayIndexLen(i) + "|fmt=" + s.Format +
                            "|mat=" + Rid(s.Material) + "|name=" + s.Name);
                        var arrays = m.SurfaceGetArrays(i);
                        for (int a = 0; a < arrays.Size(); a++)
                            if (!arrays[a].IsNil) P("arr" + id + "|" + i + "|" + a, Md5(GMarshal.VarToBytes(arrays[a])));
                        if (s.BlendShapes != null)
                            for (int b = 0; b < s.BlendShapes.Count; b++) P("bsarr" + id + "|" + i + "|" + b, Md5(GMarshal.VarToBytes(Var.Of(s.BlendShapes[b].Vertices))));
                        Dres(s.Material);
                    }
                    break;
                }
                case Skin sk:
                    P("skin" + id, sk.GetBindCount().ToString());
                    for (int i = 0; i < sk.GetBindCount(); i++) P("bind" + id + "|" + i, sk.GetBindName(i) + "|" + sk.GetBindBone(i) + "|" + S(sk.GetBindPose(i)));
                    break;
                case AnimationLibrary lib:
                {
                    var names = lib.GetAnimationList().ToList();
                    names.Sort(StringComparer.Ordinal);
                    P("lib" + id, names.Count.ToString());
                    foreach (var a in names)
                    {
                        P("lib" + id + "|" + a, Rid(lib.GetAnimation(a)));
                        Dres(lib.GetAnimation(a));
                    }
                    break;
                }
                case Animation an:
                    P("anim" + id, GD.Str(an.Length) + "|" + (int)an.LoopMode + "|" + an.GetTrackCount());
                    for (int t = 0; t < an.GetTrackCount(); t++)
                    {
                        int nk = an.TrackGetKeyCount(t);
                        P("track" + id + "|" + t, (int)an.TrackGetType(t) + "|" + an.TrackGetPath(t) + "|" + (int)an.TrackGetInterpolationType(t) + "|" +
                            S(an.TrackGetInterpolationLoopWrap(t)) + "|" + S(an.TrackIsEnabled(t)) + "|" + nk);
                        if (nk > 0 && an.TrackGetType(t) <= Animation.TrackType.BlendShape)
                        {
                            P("key" + id + "|" + t + "|first", GD.Str(an.TrackGetKeyTime(t, 0)) + "|" + KeyStr(an.TrackGetKeyValue(t, 0)));
                            P("key" + id + "|" + t + "|last", GD.Str(an.TrackGetKeyTime(t, nk - 1)) + "|" + KeyStr(an.TrackGetKeyValue(t, nk - 1)));
                        }
                    }
                    break;
                case BaseMaterial3D bm:
                    P("mat" + id, bm.GetType().Name);
                    Props("matp" + id, bm, MatProps);
                    break;
                case ParticleProcessMaterial pm:
                    P("mat" + id, "ParticleProcessMaterial");
                    Props("ppm" + id, pm, PpmProps);
                    break;
                case CurveTexture ct:
                    P("curvetex" + id, ct.Width + "|" + ct.TextureMode + "|" + Rid(ct.Curve));
                    Dres(ct.Curve);
                    break;
                case Curve c:
                    P("curve" + id, c.Points.Count + "|" + GD.Str(c.MinValue) + "|" + GD.Str(c.MaxValue));
                    for (int i = 0; i < c.Points.Count; i++)
                        P("cpt" + id + "|" + i, S(new Vec2(c.Points[i].x, c.Points[i].y)) + "|" + GD.Str((double)c.Points[i].leftTangent) + "|" + GD.Str((double)c.Points[i].rightTangent));
                    break;
                case GradientTexture1D gt:
                    P("gradtex" + id, gt.Width + "|" + S(gt.UseHdr) + "|" + Rid(gt.Gradient));
                    Dres(gt.Gradient);
                    break;
                case Gradient g:
                    P("grad" + id, g.GetPointCount() + "|" + (int)g.InterpolationMode);
                    for (int i = 0; i < g.GetPointCount(); i++) P("gpt" + id + "|" + i, GD.Str(g.GetOffset(i)) + "|" + S(g.GetColor(i)));
                    break;
                case Image img:
                    P("img" + id, img.Width + "|" + img.Height + "|" + (int)img.Format + "|" + Md5(img.Data));
                    break;
                case BakedScriptResource bs:
                {
                    P("script" + id, bs.Script);
                    var names = bs.Properties.Keys().Select(k => k.AsString()).ToList();
                    names.Sort(StringComparer.Ordinal);
                    foreach (var n in names) Dv("sp" + id + "|" + n, bs.Properties[n]);
                    break;
                }
                default:
                    P("res" + id, r.GetType().Name);
                    break;
            }
        }

        static string KeyStr(Var v) => v.Obj is Resource r ? Rid(r) : GD.Str(v);

        static void Dv(string key, Var v)
        {
            if (v.Obj is Resource r) { P(key, Rid(r)); Dres(r); }
            else if (v.AsArr() is GArray a)
            {
                P(key, "array|" + a.Size());
                for (int i = 0; i < a.Size(); i++)
                {
                    var e = a[i];
                    if (e.Obj is Resource || e.IsArr || e.IsDict) Dv(key + "/" + i, e);
                    else if (i == 0 || i == a.Size() - 1) P(key + "/" + i, GD.Str(e));
                }
            }
            else if (v.AsDict() is GDict d)
            {
                P(key, "dict|" + d.Size());
                foreach (var k in d.Keys()) Dv(key + "/" + GD.Str(k), d[k]);
            }
            else P(key, GD.Str(v));
        }
    }
}
