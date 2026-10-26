// Ported from godot/scripts/siege/ground_cards.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    using Stage = Fatebound.Game.AssetCache;
    using Land = Fatebound.Sim.Land;

    // The Rift's painted plants and ground marks (0.31.216, Kevin: "use eleven to draw detailed paint on ground. Also need
    // new models for grass"): ElevenLabs painted the sheets (tools/ground_paint.py), this file cuts them into cards and the
    // view (siege_view.gd: _plan_foliage, _build_foliage, _build_brush, _build_ground_marks) places them.
    //   BLADES   grass clumps (4 x 2 on the sheet): two crossed cards, swaying -- the fields and the lanes' edges
    //   BRUSH    the tall lavender-tipped grass you hide in (2 on the sheet): three crossed cards, swaying more
    //   FLOWERS  patches of buttercups, daisies and blossoms (3 x 3): one card lying on the grass
    //   decals   the carved stone circles on the lanes and the pits' floors, the ring of carved stone round every tower's
    //            foot: a grid laid over the baked terrain (decal_mesh), drawn just above it
    public class GroundCards
    {
        public static readonly Shader SHADER = ResourceLoader.Load<Shader>("res://scripts/siege/ground_cards.gdshader");
        public const string DIR = "res://assets/terrain/paint/";

        // sheet, its grid, sway (card heights), cut, the mesh's cards
        public static readonly GDict KINDS = new GDict
        {
            { "blades", GDict.Of("sheet", "blades.png", "cells", new Vector2(4, 2), "sway", 0.09, "cards", 2, "aspect", 1.0, "hue", new Vector3(1.0, 1.0, 1.0)) },
            { "brush", GDict.Of("sheet", "brush.png", "cells", new Vector2(2, 1), "sway", 0.06, "cards", 3, "aspect", 0.5, "hue", new Vector3(1.0, 1.12, 0.84)) },
            { "flowers", GDict.Of("sheet", "flowers.png", "cells", new Vector2(3, 3), "sway", 0.0, "cards", 0, "aspect", 1.0, "hue", new Vector3(1.0, 1.0, 1.0)) },
        };

        public static GDict _mats = new GDict();
        public static GDict _meshes = new GDict();

        public static ShaderMaterial Material(string kind, Vector3 tint)
        {
            if (!_mats.Has(kind))
            {
                GDict k = KINDS[kind].D;
                var m = new ShaderMaterial();
                m.Shader = SHADER;
                m.SetShaderParameter("sheet", Stage.Texture(DIR + GD.Str(k["sheet"])));
                m.SetShaderParameter("cells", k["cells"]);
                m.SetShaderParameter("sway", (double)k["sway"]);
                m.SetShaderParameter("tint", tint * k["hue"].V3);     // (the brush's painted teal pulled toward green)
                _mats[kind] = Var.Of(m);
            }
            return _mats[kind].As<ShaderMaterial>();
        }

        public static ArrayMesh Mesh(string kind)
        {
            // A card is 1 tall (its width by the sheet's cell), its foot at y 0; UV v 0 at its top. "flowers": one card flat on
            // the ground, 1 x 1, centred.
            if (_meshes.Has(kind))
                return _meshes[kind].As<ArrayMesh>();
            GDict k = KINDS[kind].D;
            var verts = new List<Vector3>();
            var uvs = new List<Vector2>();
            var norms = new List<Vector3>();
            var idx = new List<int>();
            var n = (int)k["cards"];
            if (n == 0)
            {
                foreach (var c in new[] { new Vector2(-0.5, -0.5), new Vector2(0.5, -0.5), new Vector2(0.5, 0.5), new Vector2(-0.5, 0.5) })
                {
                    verts.Add(new Vector3(c.x, 0.02, c.y));
                    uvs.Add(new Vector2(c.x + 0.5, c.y + 0.5));
                    norms.Add(Vector3.UP);
                }
                idx.AddRange(new[] { 0, 1, 2, 0, 2, 3 });
            }
            else
            {
                var w = (double)k["aspect"] * 0.5;
                for (int i = 0; i < n; i++)
                {
                    var a = GD.PI * (double)i / (double)n;
                    var d = new Vector3(Math.Cos(a), 0.0, Math.Sin(a)) * w;
                    var b = verts.Count;
                    verts.AddRange(new[] { -d, d, d + Vector3.UP, -d + Vector3.UP });
                    uvs.AddRange(new[] { new Vector2(0, 1), new Vector2(1, 1), new Vector2(1, 0), new Vector2(0, 0) });
                    for (int _j = 0; _j < 4; _j++)
                        norms.Add(Vector3.UP);
                    idx.AddRange(new[] { b, b + 1, b + 2, b, b + 2, b + 3 });
                }
            }
            var arr = new GArray();
            arr.Resize(Fatebound.GUI.Mesh.ARRAY_MAX);
            arr[Fatebound.GUI.Mesh.ARRAY_VERTEX] = Var.Of(verts);
            arr[Fatebound.GUI.Mesh.ARRAY_TEX_UV] = Var.Of(uvs);
            arr[Fatebound.GUI.Mesh.ARRAY_NORMAL] = Var.Of(norms);
            arr[Fatebound.GUI.Mesh.ARRAY_INDEX] = Var.Of(idx);
            var am = new ArrayMesh();
            am.AddSurfaceFromArrays(Fatebound.GUI.Mesh.PRIMITIVE_TRIANGLES, arr);
            _meshes[kind] = Var.Of(am);
            return am;
        }

        public static Color Custom(int cell, Rng rng)
        {
            // INSTANCE_CUSTOM: the sheet's cell, a shade, a beat in the breeze
            return new Color((double)cell, rng.Randf(), rng.Randf(), 0.0);
        }

        // ---------- decals ----------
        public static GDict _decal_mats = new GDict();
        public const string DECAL_SHADER = @"
shader_type spatial;
// (ground_cards.gd) a painted mark laid over the ground: the picture's own alpha, lit as the ground is
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint = vec3(1.0);
uniform float spin = 0.0;
void fragment() {
	vec2 q = UV - 0.5;
	q = mat2(vec2(cos(spin), sin(spin)), vec2(-sin(spin), cos(spin))) * q + 0.5;
	vec4 c = texture(tex, q);
	ALBEDO = c.rgb * tint;
	ALPHA = c.a * step(0.0, q.x) * step(q.x, 1.0) * step(0.0, q.y) * step(q.y, 1.0);
	ROUGHNESS = 0.95;
}
";
        public static Shader _decal_shader = null;

        public static ShaderMaterial DecalMaterial(string pic, Vector3 tint)
        {
            if (!_decal_mats.Has(pic))
            {
                if (_decal_shader == null)
                {
                    _decal_shader = new Shader();
                    _decal_shader.Code = DECAL_SHADER;
                }
                var m = new ShaderMaterial();
                m.Shader = _decal_shader;
                m.SetShaderParameter("tex", Stage.Texture(DIR + pic));
                m.SetShaderParameter("tint", tint);
                m.RenderPriority = 1;
                _decal_mats[pic] = Var.Of(m);
            }
            return _decal_mats[pic].As<ShaderMaterial>();
        }

        public static ArrayMesh DecalMesh(Vector2 c, double size, Func<Vector2, double> height, double lift = 0.05)
        {
            // A size x size grid centred on c, every 0.75 m or less, each point just above the ground (height: Vector2 -> float).
            var n = GD.Maxi(4, (int)Math.Ceiling(size / 0.75));
            var verts = new List<Vector3>();
            var uvs = new List<Vector2>();
            var norms = new List<Vector3>();
            var idx = new List<int>();
            for (int j = 0; j < n + 1; j++)
            {
                for (int i = 0; i < n + 1; i++)
                {
                    var u = (double)i / n;
                    var v = (double)j / n;
                    var p = c + new Vector2(u - 0.5, v - 0.5) * size;
                    verts.Add(new Vector3(p.x, (double)height(p) + lift, p.y));
                    uvs.Add(new Vector2(u, v));
                    norms.Add(Vector3.UP);
                }
            }
            for (int j = 0; j < n; j++)
            {
                for (int i = 0; i < n; i++)
                {
                    var a = j * (n + 1) + i;
                    idx.AddRange(new[] { a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1 });
                }
            }
            var arr = new GArray();
            arr.Resize(Fatebound.GUI.Mesh.ARRAY_MAX);
            arr[Fatebound.GUI.Mesh.ARRAY_VERTEX] = Var.Of(verts);
            arr[Fatebound.GUI.Mesh.ARRAY_TEX_UV] = Var.Of(uvs);
            arr[Fatebound.GUI.Mesh.ARRAY_NORMAL] = Var.Of(norms);
            arr[Fatebound.GUI.Mesh.ARRAY_INDEX] = Var.Of(idx);
            var am = new ArrayMesh();
            am.AddSurfaceFromArrays(Fatebound.GUI.Mesh.PRIMITIVE_TRIANGLES, arr);
            return am;
        }
    }
}
