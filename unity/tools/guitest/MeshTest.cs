// `guitest mesh [godot.txt]`: the port's primitive meshes, SurfaceTool, ImmediateMesh, material / noise / curve
// resources (GUI/Scene3D) printing the same lines as tools/parity/godot_mesh.gd; tools/parity/mesh.sh diffs the two.
// Mesh data is compared the way Godot hands it back (surface_get_arrays after the RenderingServer packed it:
// GpuPacking.AsStored) except SurfaceTool.commit_to_arrays, which is raw on both sides. The prop| lines take their
// property names from Godot's output (the optional argument) and print the C# defaults under the same names.
// FB_MESH_FULL=1 prints every element after each array line, like the Godot script.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using Fatebound.GUI;
using Fatebound.Sim;

namespace GuiTest
{
    public static class MeshTest
    {
        static readonly string[] ArrayNames = { "vertex", "normal", "tangent", "color", "uv", "uv2", "custom0", "custom1", "custom2", "custom3", "bones", "weights", "index" };
        static bool full;
        static readonly StringBuilder Out = new StringBuilder();

        static void P(params object[] parts)
        {
            foreach (var o in parts) Out.Append(o is string s ? s : Convert.ToString(o, CultureInfo.InvariantCulture));
            Out.Append('\n');
        }

        static string F6(double x)
        {
            string s = x.ToString("F6", CultureInfo.InvariantCulture);
            return s == "-0.000000" ? "0.000000" : s;
        }

        static string Fmt(object v)
        {
            switch (v)
            {
                case null: return "null";
                case Var var: return Fmt(var.Obj);
                case bool b: return b ? "true" : "false";
                case Enum e: return Convert.ToInt64(e).ToString(CultureInfo.InvariantCulture);
                case int i: return i.ToString(CultureInfo.InvariantCulture);
                case long l: return l.ToString(CultureInfo.InvariantCulture);
                case uint ui: return ui.ToString(CultureInfo.InvariantCulture);
                case float f: return F6(f);
                case double d: return F6(d);
                case string s: return s;
                case Vec2 v2: return "(" + F6(v2.x) + ", " + F6(v2.y) + ")";
                case Vec2i v2i: return "(" + v2i.x + ", " + v2i.y + ")";
                case Vec3 v3: return "(" + F6(v3.x) + ", " + F6(v3.y) + ", " + F6(v3.z) + ")";
                case Col c: return "(" + F6(c.r) + ", " + F6(c.g) + ", " + F6(c.b) + ", " + F6(c.a) + ")";
                case Aabb a: return "[" + Fmt(a.position) + ", " + Fmt(a.size) + "]";
            }
            return v.GetType().Name;
        }

        // ------------------------------------------------------------------ arrays as bytes (what to_byte_array gives)
        static (string type, int count, byte[] bytes, int elem) Bytes(object a)
        {
            var ms = new MemoryStream();
            var w = new BinaryWriter(ms);
            switch (a)
            {
                case Vec3[] v3: foreach (var v in v3) { w.Write(v.x); w.Write(v.y); w.Write(v.z); } return ("PackedVector3Array", v3.Length, ms.ToArray(), 12);
                case Vec2[] v2: foreach (var v in v2) { w.Write(v.x); w.Write(v.y); } return ("PackedVector2Array", v2.Length, ms.ToArray(), 8);
                case Col[] cs: foreach (var c in cs) { w.Write(c.r); w.Write(c.g); w.Write(c.b); w.Write(c.a); } return ("PackedColorArray", cs.Length, ms.ToArray(), 16);
                case float[] fs: foreach (var f in fs) w.Write(f); return ("PackedFloat32Array", fs.Length, ms.ToArray(), 4);
                case int[] ints: foreach (var i in ints) w.Write(i); return ("PackedInt32Array", ints.Length, ms.ToArray(), 4);
                case byte[] bs: return ("PackedByteArray", bs.Length, bs, 1);
            }
            throw new InvalidOperationException("array type " + a.GetType());
        }

        static string Hex(byte[] b, int start, int len)
        {
            var sb = new StringBuilder(len * 2);
            for (int i = start; i < start + len && i < b.Length; i++) sb.Append(b[i].ToString("x2"));
            return sb.ToString();
        }

        static string Md5Hex(byte[] b)
        {
            using var md5 = MD5.Create();
            byte[] h = md5.ComputeHash(Encoding.ASCII.GetBytes(Hex(b, 0, b.Length)));
            return Hex(h, 0, h.Length);
        }

        static void Arr(string prefix, string key, object a)
        {
            if (a == null) { P(prefix, "|", key, "|none"); return; }
            var (type, count, bytes, es) = Bytes(a);
            P(prefix, "|", key, "|", type, "|", count, "|", Md5Hex(bytes));
            if (full)
                for (int i = 0; i < count; i++) P(prefix, "|", key, "|", i, "|", Hex(bytes, i * es, es));
        }

        static void DumpArrays(string prefix, GArray arrays)
        {
            for (int k = 0; k < Mesh.ARRAY_MAX; k++) Arr(prefix, ArrayNames[k], k < arrays.Size() ? arrays[k].Obj : null);
        }

        static void DumpSurface(string prefix, MeshSurface s)
        {
            object[] a = { s.Vertices, s.Normals, s.Tangents, s.Colors, s.Uv, s.Uv2, s.Custom[0], s.Custom[1], s.Custom[2], s.Custom[3], s.Bones, s.Weights, s.Indices };
            for (int k = 0; k < a.Length; k++) Arr(prefix, ArrayNames[k], a[k]);
        }

        static void DumpMesh(string prefix, Mesh m)
        {
            var ss = m.GetSurfaces();
            P(prefix, "|surfaces|", ss.Count);
            for (int i = 0; i < ss.Count; i++)
            {
                var st = GpuPacking.AsStored(ss[i]);
                DumpSurface(prefix + "|s" + i, st);
                P(prefix, "|s", i, "|format|", st.Format & 8191);
                P(prefix, "|s", i, "|primitive|", (int)st.Primitive);
            }
            P(prefix, "|aabb|", Fmt(m.GetAabb()));
        }

        // ------------------------------------------------------------------ primitive meshes
        static void Prim(string name, PrimitiveMesh m)
        {
            string p = "prim|" + name;
            DumpSurface(p, GpuPacking.AsStored(m.GetSurfaces()[0]));
            P(p, "|aabb|", Fmt(m.GetAabb()));
            P(p, "|lightmap|", Fmt(m.LightmapSizeHint));
        }

        static Vec3 V(double x, double y, double z) => new Vec3((float)x, (float)y, (float)z);

        static void Primitives()
        {
            Prim("box_default", new BoxMesh());
            Prim("box_custom", new BoxMesh { Size = V(2, 1, 3), SubdivideWidth = 2, SubdivideHeight = 3, SubdivideDepth = 1 });
            Prim("box_flip", new BoxMesh { FlipFaces = true });
            Prim("box_uv2", new BoxMesh { AddUv2 = true, Uv2Padding = 4.0 });

            Prim("capsule_default", new CapsuleMesh());
            Prim("capsule_custom", new CapsuleMesh { Radius = 0.3, Height = 1.5, RadialSegments = 12, Rings = 3 });
            Prim("capsule_uv2", new CapsuleMesh { AddUv2 = true });

            Prim("cylinder_default", new CylinderMesh());
            Prim("cylinder_custom", new CylinderMesh { TopRadius = 0.2, BottomRadius = 0.6, Height = 1.2, RadialSegments = 10, Rings = 2, CapTop = false });
            Prim("cylinder_cone", new CylinderMesh { TopRadius = 0.0, CapBottom = false, FlipFaces = true });
            Prim("cylinder_uv2", new CylinderMesh { AddUv2 = true });

            Prim("plane_default", new PlaneMesh());
            Prim("plane_custom", new PlaneMesh { Size = new Vec2(3, 2), SubdivideWidth = 2, SubdivideDepth = 3, CenterOffset = V(0.1, 0.2, 0.3), Orientation = PlaneMesh.FACE_X });
            Prim("plane_z_uv2", new PlaneMesh { Orientation = PlaneMesh.FACE_Z, AddUv2 = true });

            Prim("quad_default", new QuadMesh());
            Prim("quad_custom", new QuadMesh { Size = new Vec2(2, 1), Orientation = PlaneMesh.FACE_Y, CenterOffset = V(0, 0.5, 0) });

            Prim("prism_default", new PrismMesh());
            Prim("prism_custom", new PrismMesh { LeftToRight = 0.2, Size = V(1, 2, 3), SubdivideWidth = 1, SubdivideHeight = 2, SubdivideDepth = 3 });
            Prim("prism_uv2", new PrismMesh { AddUv2 = true });

            Prim("sphere_default", new SphereMesh());
            Prim("sphere_custom", new SphereMesh { Radius = 0.7, Height = 1.0, RadialSegments = 16, Rings = 8, IsHemisphere = true });
            Prim("sphere_uv2", new SphereMesh { RadialSegments = 12, Rings = 6, AddUv2 = true });

            Prim("torus_default", new TorusMesh());
            Prim("torus_custom", new TorusMesh { InnerRadius = 0.3, OuterRadius = 0.8, Rings = 12, RingSegments = 6 });
            Prim("torus_uv2", new TorusMesh { Rings = 10, RingSegments = 5, AddUv2 = true });

            Prim("point_default", new PointMesh());
        }

        // ------------------------------------------------------------------ SurfaceTool
        static void QuadVerts(SurfaceTool st, bool withNormals)
        {
            Vec3[] pts = { V(0, 0, 0), V(1, 0, 0), V(1, 1, 0.2), V(0, 0, 0), V(1, 1, 0.2), V(0, 1, 0),
                V(1, 0, 0), V(2, 0, -0.3), V(2, 1, 0), V(1, 0, 0), V(2, 1, 0), V(1, 1, 0.2) };
            for (int i = 0; i < pts.Length; i++)
            {
                Vec3 v = pts[i];
                st.SetColor(new Col((float)(v.x * 0.4), (float)(v.y * 0.7), (float)(0.25 + v.z), (float)(1.0 - 0.05 * i)));
                st.SetUv(new Vec2((float)(v.x * 0.5), (float)(1.0 - v.y)));
                if (withNormals) st.SetNormal(V(0.1 * i, 0.3, 1.0).NormalizedChecked());
                st.AddVertex(v);
            }
        }

        static void GridVerts(SurfaceTool st, int n)
        {
            for (int y = 0; y < n; y++)
                for (int x = 0; x < n; x++)
                {
                    Vec2[] c = { new Vec2(x, y), new Vec2(x + 1, y), new Vec2(x + 1, y + 1), new Vec2(x, y), new Vec2(x + 1, y + 1), new Vec2(x, y + 1) };
                    foreach (var p in c)
                    {
                        double h = Math.Sin(p.x * 1.3) * 0.4 + Math.Cos(p.y * 0.7) * 0.3;
                        st.SetUv(new Vec2((float)((double)p.x / n), (float)((double)p.y / n)));
                        st.SetSmoothGroup(p.x < 2 ? 0 : 1);
                        st.AddVertex(new Vec3(p.x, (float)h, p.y));
                    }
                }
        }

        static void SurfaceTools()
        {
            var st = new SurfaceTool();
            st.Begin(PrimitiveType.Triangles);
            QuadVerts(st, true);
            DumpArrays("st|basic", st.CommitToArrays());
            P("st|basic|aabb|", Fmt(st.GetAabb()));
            st.Index();
            DumpArrays("st|basic_indexed", st.CommitToArrays());
            st.Deindex();
            DumpArrays("st|basic_deindexed", st.CommitToArrays());
            st.Index();
            DumpMesh("st|basic_commit", st.Commit());

            st = new SurfaceTool();
            st.Begin(PrimitiveType.Triangles);
            QuadVerts(st, false);
            st.GenerateNormals();
            DumpArrays("st|quad_normals", st.CommitToArrays());
            DumpMesh("st|quad_normals_commit", st.Commit());

            st = new SurfaceTool();
            st.Begin(PrimitiveType.Triangles);
            GridVerts(st, 4);
            st.GenerateNormals();
            DumpArrays("st|grid_normals", st.CommitToArrays());
            st.GenerateTangents();
            DumpArrays("st|grid_tangents", st.CommitToArrays());
            st.Index();
            DumpArrays("st|grid_indexed", st.CommitToArrays());
            DumpMesh("st|grid_commit", st.Commit());

            st = new SurfaceTool();
            st.Begin(PrimitiveType.Triangles);
            st.SetSmoothGroup(-1);
            GridVerts(st, 3);
            st.Index();
            st.GenerateNormals(true);
            st.GenerateTangents();
            DumpArrays("st|grid_flat_flip", st.CommitToArrays());

            var box = new BoxMesh { SubdivideWidth = 1 };
            st = new SurfaceTool();
            st.CreateFrom(box, 0);
            DumpArrays("st|from_box", st.CommitToArrays());
            st.GenerateNormals();
            st.GenerateTangents();
            DumpArrays("st|from_box_regen", st.CommitToArrays());
            DumpMesh("st|from_box_commit", st.Commit());

            var sph = new SphereMesh { RadialSegments = 8, Rings = 4 };
            st = new SurfaceTool();
            st.Begin(PrimitiveType.Triangles);
            st.AppendFrom(sph, 0, new Xform3(new Basis(V(0.3, 1, 0.2).NormalizedChecked(), 0.7).Scaled(V(1, 2, 0.5)), V(1, -2, 3)));
            st.AppendFrom(box, 0, new Xform3(Basis.IDENTITY, V(0, 0, 0)));
            DumpArrays("st|append", st.CommitToArrays());
            st.Deindex();
            st.GenerateNormals();
            st.Index();
            DumpArrays("st|append_renormal", st.CommitToArrays());

            st = new SurfaceTool();
            st.Begin(PrimitiveType.Triangles);
            st.AddTriangleFan(new[] { V(0, 0, 0), V(1, 0, 0), V(1, 1, 0), V(0, 1, 0), V(-0.5, 0.5, 0) },
                new[] { new Vec2(0, 0), new Vec2(1, 0), new Vec2(1, 1), new Vec2(0, 1), new Vec2(-0.5f, 0.5f) },
                new[] { new Col(1, 0, 0, 1), new Col(0, 1, 0, 1), new Col(0, 0, 1, 1), new Col(1, 1, 1, 1), new Col(0.2f, 0.3f, 0.4f, 0.5f) });
            DumpArrays("st|fan", st.CommitToArrays());

            st = new SurfaceTool();
            st.SetSkinWeightCount(SurfaceTool.SKIN_4_WEIGHTS);
            st.Begin(PrimitiveType.Triangles);
            st.SetCustomFormat(0, SurfaceTool.CUSTOM_RGBA8_UNORM);
            st.SetCustomFormat(1, SurfaceTool.CUSTOM_RGBA_FLOAT);
            st.SetCustomFormat(2, SurfaceTool.CUSTOM_RG_HALF);
            st.SetCustomFormat(3, SurfaceTool.CUSTOM_RGBA8_SNORM);
            for (int i = 0; i < 6; i++)
            {
                st.SetCustom(0, new Col((float)(0.1 * i), 0.5f, 1.2f, -0.1f));
                st.SetCustom(1, new Col(i, (float)(-i * 0.5), 0.25f, 7.0f));
                st.SetCustom(2, new Col((float)(0.333 * i), -1.5f, 0, 0));
                st.SetCustom(3, new Col(-0.7f, (float)(0.3 * i), 1.0f, -1.0f));
                st.SetBones(new[] { i, i + 1, 0, 3 });
                st.SetWeights(new[] { 0.5f, 0.3f, (float)(0.2 - 0.01 * i), (float)(0.01 * i) });
                st.AddVertex(V(i, i % 2, -i * 0.5));
            }
            DumpArrays("st|custom_skin", st.CommitToArrays());

            st = new SurfaceTool();
            st.Begin(PrimitiveType.Lines);
            for (int i = 0; i < 8; i++)
            {
                st.SetColor(new Col((float)(0.1 * i), 0.2f, 0.3f, 1f));
                st.AddVertex(V(i % 3, i % 2, 0.5 * (i % 4)));
            }
            st.Index();
            DumpArrays("st|lines", st.CommitToArrays());
            DumpMesh("st|lines_commit", st.Commit());
        }

        // ------------------------------------------------------------------ ImmediateMesh
        static void Immediate()
        {
            var im = new ImmediateMesh();
            im.SurfaceBegin(PrimitiveType.Triangles);
            for (int i = 0; i < 9; i++)
            {
                double a = i * 0.7;
                im.SurfaceSetNormal(V(Math.Cos(a), 0.4, Math.Sin(a)).NormalizedChecked());
                im.SurfaceSetColor(new Col((float)(0.1 * i), (float)(1.0 - 0.1 * i), 0.5f, 1.0f));
                im.SurfaceSetUv(new Vec2((float)(0.1 * i), 0.2f));
                im.SurfaceAddVertex(V(Math.Cos(a) * 2.0, i * 0.25, Math.Sin(a)));
            }
            im.SurfaceEnd();
            im.SurfaceBegin(PrimitiveType.Lines);
            im.SurfaceAddVertex(V(0, 0, 0));
            im.SurfaceAddVertex(V(1, 2, 3));
            im.SurfaceSetColor(new Col(1f, 0.5f, 0.25f, 1f));
            im.SurfaceSetTangent(new Plane(V(1, 0, 0), -1f));
            im.SurfaceAddVertex(V(-1, 0.5, 2));
            im.SurfaceSetUv2(new Vec2(0.3f, 0.6f));
            im.SurfaceAddVertex(V(4, -1, 0));
            im.SurfaceEnd();
            DumpMesh("im|two", im);
            im.ClearSurfaces();
            P("im|cleared|", im.GetSurfaces().Count);
        }

        // ------------------------------------------------------------------ property defaults (names from Godot's output)
        static string Pascal(string snake)
        {
            var sb = new StringBuilder();
            bool up = true;
            foreach (char c in snake)
            {
                if (c == '_') { up = true; continue; }
                sb.Append(up ? char.ToUpperInvariant(c) : c);
                up = false;
            }
            return sb.ToString();
        }

        static void Props(string godotOut)
        {
            if (godotOut == null || !File.Exists(godotOut)) return;
            var objs = new Dictionary<string, object>();
            var asm = typeof(BoxMesh).Assembly;
            foreach (var line in File.ReadAllLines(godotOut))
            {
                if (!line.StartsWith("prop|")) continue;
                var f = line.Split('|');
                string cls = f[1], name = f[2];
                if (!objs.TryGetValue(cls, out var o))
                {
                    var t = asm.GetType("Fatebound.GUI." + cls);
                    o = t == null ? null : Activator.CreateInstance(t);
                    objs[cls] = o;
                }
                if (o == null) { P("prop|", cls, "|", name, "|NO CLASS"); continue; }
                string pn = Pascal(name);
                var type = o.GetType();
                object val;
                var pi = type.GetProperty(pn, BindingFlags.Public | BindingFlags.Instance);
                if (pi != null && pi.GetIndexParameters().Length == 0) val = pi.GetValue(o);
                else
                {
                    var fi = type.GetField(pn, BindingFlags.Public | BindingFlags.Instance);
                    if (fi == null) { P("prop|", cls, "|", name, "|MISSING"); continue; }
                    val = fi.GetValue(o);
                }
                P("prop|", cls, "|", name, "|", Fmt(val));
            }
        }

        // ------------------------------------------------------------------ FastNoiseLite
        static void NoiseCase(string name, FastNoiseLite n)
        {
            var a = new List<float>();
            for (int y = 0; y < 12; y++)
                for (int x = 0; x < 12; x++)
                    a.Add((float)n.GetNoise2D(x * 7.3 - 40.0, y * 5.1 - 30.0));
            Arr("noise|" + name, "2d", a.ToArray());
            P("noise|", name, "|2d0|", F6(a[0]), "|", F6(a[77]));
            a.Clear();
            for (int z = 0; z < 4; z++)
                for (int y = 0; y < 6; y++)
                    for (int x = 0; x < 6; x++)
                        a.Add((float)n.GetNoise3D(x * 9.1 - 20.0, y * 4.7 + 3.0, z * 11.3 - 7.0));
            Arr("noise|" + name, "3d", a.ToArray());
            a.Clear();
            for (int x = 0; x < 20; x++) a.Add((float)n.GetNoise1D(x * 3.7 - 12.0));
            Arr("noise|" + name, "1d", a.ToArray());
        }

        static void Noises()
        {
            NoiseCase("default", new FastNoiseLite());
            for (int t = 0; t < 6; t++)
                for (int f = 0; f < 4; f++)
                {
                    var n = new FastNoiseLite();
                    n.NoiseType = t;
                    n.FractalType = f;
                    n.Seed = 1234 + t;
                    n.FractalOctaves = 3;
                    n.FractalWeightedStrength = f == 3 ? 0.4 : 0.0;
                    n.Frequency = 0.03;
                    NoiseCase("type" + t + "_fractal" + f, n);
                }
            for (int d = 0; d < 4; d++)
                for (int r = 0; r < 7; r++)
                {
                    var n = new FastNoiseLite();
                    n.NoiseType = FastNoiseLite.TYPE_CELLULAR;
                    n.CellularDistanceFunction = d;
                    n.CellularReturnType = r;
                    n.CellularJitter = 0.8;
                    n.FractalType = FastNoiseLite.FRACTAL_NONE;
                    n.Frequency = 0.05;
                    NoiseCase("cell_d" + d + "_r" + r, n);
                }
            for (int w = 0; w < 3; w++)
                for (int wf = 0; wf < 3; wf++)
                {
                    var n = new FastNoiseLite();
                    n.DomainWarpEnabled = true;
                    n.DomainWarpType = w;
                    n.DomainWarpFractalType = wf;
                    n.DomainWarpAmplitude = 20.0;
                    n.DomainWarpFrequency = 0.02;
                    n.DomainWarpFractalOctaves = 3;
                    n.Seed = -77;
                    NoiseCase("warp" + w + "_f" + wf, n);
                }
            var n2 = new FastNoiseLite();
            n2.Offset = V(10.5, -3.25, 7);
            n2.FractalLacunarity = 2.5;
            n2.FractalGain = 0.6;
            n2.FractalPingPongStrength = 3.0;
            n2.FractalType = FastNoiseLite.FRACTAL_PING_PONG;
            NoiseCase("offset_pingpong", n2);
        }

        // ------------------------------------------------------------------ curves
        static byte[] FloatBytes(float[] v)
        {
            var b = new byte[v.Length * 4];
            Buffer.BlockCopy(v, 0, b, 0, b.Length);
            return b;
        }

        static void Curves()
        {
            var c = new Curve();
            c.AddPoint(new Vec2(0.0f, 0.2f), 0.0, 1.5);
            c.AddPoint(new Vec2(0.35f, 0.9f), -0.5, 2.0);
            c.AddPoint(new Vec2(0.7f, 0.4f));
            c.AddPoint(new Vec2(1.0f, 1.0f), 0.8, 0.0);
            var c2 = new Curve();
            c2.AddPoint(new Vec2(0.1f, 0.5f));
            c2.AddPoint(new Vec2(0.6f, 0.0f), -1.0, 2.5);
            c2.AddPoint(new Vec2(0.9f, 0.75f), 3.0, -1.0);
            foreach (var (name, cv, w) in new[] { ("c_256", c, 256), ("c_64", c, 64), ("c2_100", c2, 100), ("c2_32", c2, 32) })
            {
                var ct = new CurveTexture { Width = w, TextureMode = CurveTexture.TEXTURE_MODE_RED, Curve = cv };
                Arr("curve|" + name, "texels", (float[])ct.GetValues().Clone());
            }
            {
                var ct = new CurveTexture { Curve = c };
                float[] v = ct.GetValues();
                var rgb = new float[v.Length * 3];
                for (int i = 0; i < v.Length; i++) rgb[i * 3] = rgb[i * 3 + 1] = rgb[i * 3 + 2] = v[i];
                P("curve|tex_image|10|", v.Length, "|", Md5Hex(FloatBytes(rgb)));
                var ct2 = new CurveTexture { TextureMode = CurveTexture.TEXTURE_MODE_RED };
                P("curve|tex_red_empty|8|", Md5Hex(FloatBytes(ct2.GetValues())));
            }
            var xyz = new CurveXYZTexture { Width = 50, CurveX = c, CurveY = c2 };
            Arr("curve|xyz_50", "texels", (float[])xyz.GetValues().Clone());
            var xyz2 = new CurveXYZTexture { CurveX = c };
            P("curve|xyz_image|10|", xyz2.Width, "|", Md5Hex(FloatBytes(xyz2.GetValues())));
        }

        // ------------------------------------------------------------------ images
        static void Img(string name, byte[] data, bool rgba, int w, int h)
        {
            if (data == null) { P("img|", name, "|null"); return; }
            P("img|", name, "|", rgba ? 5 : 0, "|", w, "x", h, "|", Md5Hex(data), "|", Hex(data, 0, 8));
            if (full)
            {
                int row = data.Length / h;
                for (int y = 0; y < h; y++) P("img|", name, "|row", y, "|", Hex(data, y * row, row));
            }
        }

        static FastNoiseLite MakeNoise() => new FastNoiseLite { Seed = 42, Frequency = 0.04, FractalOctaves = 4 };

        static Gradient MakeGradient()
        {
            var g = new Gradient();
            g.Colors[0] = new Col(0.1f, 0.0f, 0.3f, 1f);
            g.Colors[1] = new Col(1.0f, 0.9f, 0.2f, 1f);
            g.AddPoint(0.4, new Col(0.8f, 0.2f, 0.1f, 0.7f));
            return g;
        }

        static void Images()
        {
            var n = MakeNoise();
            Img("get_image", n.GetImageL8(40, 30), false, 40, 30);
            Img("get_image_inv3d", n.GetImageL8(33, 17, true, true, true), false, 33, 17);
            Img("get_image_nonorm", n.GetImageL8(24, 24, false, false, false), false, 24, 24);
            Img("seamless", n.GetSeamlessImageL8(32, 32), false, 32, 32);
            Img("seamless_skirt", n.GetSeamlessImageL8(40, 24, false, true, 0.3f, true), false, 40, 24);
            Img("seamless_nonorm", n.GetSeamlessImageL8(16, 20, true, false, 0.1f, false), false, 16, 20);
            var specs = new (string, Action<NoiseTexture2D>)[]
            {
                ("tex_default", t => { }),
                ("tex_inv3d", t => { t.Invert = true; t.In3dSpace = true; t.Normalize = false; }),
                ("tex_seamless", t => { t.Seamless = true; t.SeamlessBlendSkirt = 0.2; }),
                ("tex_normal", t => { t.AsNormalMap = true; t.BumpStrength = 4.0; }),
                ("tex_ramp", t => { t.ColorRamp = MakeGradient(); }),
                ("tex_seamless_ramp_normal", t => { t.Seamless = true; t.ColorRamp = MakeGradient(); t.AsNormalMap = true; }),
            };
            foreach (var (name, setup) in specs)
            {
                var t = new NoiseTexture2D { Width = 64, Height = 48 };
                setup(t);
                t.Noise = MakeNoise();
                byte[] d = t.GetRawData(out bool rgba);
                Img(name, d, rgba, 64, 48);
            }
        }

        public static void Run(string[] args)
        {
            full = System.Environment.GetEnvironmentVariable("FB_MESH_FULL") == "1";
            Primitives();
            SurfaceTools();
            Immediate();
            Props(args.Length > 1 ? args[1] : null);
            Noises();
            Curves();
            Images();
            Console.Write(Out.ToString());
        }
    }
}
