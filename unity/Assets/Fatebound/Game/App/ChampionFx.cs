// Ported from godot/scripts/app/champion_fx.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    // 0.31.187 (Kevin: "Use art and effects that match each characters lore"): a champion's effects over his painting in his
    // window (champion_window.gd) -- the layers Champions.CHAMPIONS[hid].fx names: the Barbarian's bonfire embers and the
    // snow, the Druid's leaves and fireflies, the Stormcaller's rain and lightning, the Archmage's stars and a meteor now and
    // then... Drawn here as sprites (assets/vfx/weapon/, the weapons' own effect sprites) moved by hand: a few dozen, cheap,
    // the same on every renderer. Two of these sit behind the champion (halo, orbit, twinkle, rise, flash, meteor) and two in
    // front (fall, rain, drift), each in one blend: glows added (light), smoke, leaves, feathers, stones and snow laid over.
    public class ChampionFx : Control
    {
        public const string SPRITE = "res://assets/vfx/weapon/%s.png";
        public static readonly GArray FRONT = GArray.Of("fall", "rain", "drift");
        public static readonly GArray LAID = GArray.Of("smoke", "leaf", "feather", "shard", "snowflake");      // (the rest add light)

        public bool front = false;
        public bool additive = true;
        public Vector2 center = new Vector2(0.5, 0.42);            // where the champion stands, as a fraction of the rect (orbit and halo round it)
        public GArray layers = new GArray();                      // [{tex, color, motion, n, size}]
        public GArray parts = new GArray();                       // every sprite: {l (its layer), p, v, life, age, rot, spin, s, ph}
        public GArray events = new GArray();                      // flash / meteor: {l, next, age, at, dir}
        public double _flash = 0.0;
        public double _t = 0.0;
        public Rng rng = new Rng();
        public static Shader _laid_shader;
        public const string LAID_SHADER = "shader_type canvas_item;\n" +
            "varying vec4 tint;\n" +
            "void vertex() { tint = COLOR; }\n" +
            "void fragment() {\n" +
            "\tfloat l = texture(TEXTURE, UV).r;\n" +
            "\tCOLOR = vec4(tint.rgb * (0.55 + 0.6 * l), tint.a * smoothstep(0.03, 0.45, l));\n" +
            "}\n";

        public static bool Wants(GArray layer, bool in_front, bool add)
        {
            return FRONT.Has(GD.Str(layer[2])) == in_front && (!LAID.Has(GD.Str(layer[0]))) == add;
        }

        public void Setup(GArray fx, bool in_front, bool add, Vector2? at = null)
        {
            front = in_front;
            additive = add;
            center = at ?? new Vector2(0.5, 0.42);
            MouseFilter = Control.MOUSE_FILTER_IGNORE;
            rng.Seed = (ulong)(GD.Hash(GD.Str(fx)) + (in_front ? 1 : 0) + (add ? 2 : 0));
            if (add)
            {
                var m = new CanvasItemMaterial();
                m.BlendMode = CanvasBlendMode.Add;
                Material = m;
            }
            else
            {
                // (the sprites are brightness only, white on black -- made to be added: laid over, the brightness is the shape)
                if (_laid_shader == null)
                {
                    _laid_shader = new Shader();
                    _laid_shader.Code = LAID_SHADER;
                }
                var sm = new ShaderMaterial();
                sm.Shader = _laid_shader;
                Material = sm;
            }
            foreach (var l in fx)
            {
                if (!Wants(l.A, in_front, add))
                    continue;
                var path = GD.Fmt(SPRITE, GD.Str(l[0]));
                Texture2D t = ResourceLoader.Exists(path) ? ResourceLoader.Load<Texture2D>(path) : null;
                if (t == null)
                    continue;
                layers.Append(GDict.Of("tex", Var.Of(t), "color", Color.FromCode(GD.Str(l[1])), "motion", GD.Str(l[2]), "n", (int)l[3], "size", (double)l[4]));
            }
            Resized += _SpawnAll;
            _SpawnAll();
        }

        public int Count()
        {
            return parts.Size() + events.Size();
        }

        public void _SpawnAll()
        {
            parts.Clear();
            events.Clear();
            if (Size.x < 8 || Size.y < 8)
                return;
            for (int li = 0; li < layers.Size(); li++)
            {
                GDict L = layers[li].D;
                switch (GD.Str(L["motion"]))
                {
                    case "flash":
                    case "meteor":
                        events.Append(GDict.Of("l", li, "next", rng.RandfRange(0.6, 2.5), "age", -1.0, "at", Vector2.ZERO, "dir", 1.0));
                        break;
                    case "halo":
                        parts.Append(GDict.Of("l", li, "p", Size * center, "v", Vector2.ZERO, "life", 1e9, "age", 0.0, "rot", 0.0,
                            "spin", 0.08, "s", 1.0, "ph", 0.0));
                        break;
                    default:
                        for (int i = 0; i < (int)L["n"]; i++)
                        {
                            var q = _NewPart(li, true);
                            parts.Append(q);
                        }
                        break;
                }
            }
        }

        public GDict _NewPart(int li, bool warm)
        {
            // a new sprite of layer li (warm: anywhere along its way, so the window opens already full)
            GDict L = layers[li].D;
            double w = Size.x;
            double h = Size.y;
            double s = rng.RandfRange(0.7, 1.3);
            var q = GDict.Of("l", li, "rot", rng.RandfRange(0, GD.TAU), "spin", rng.RandfRange(-1.2, 1.2), "s", s, "ph", rng.RandfRange(0, GD.TAU),
                "age", 0.0);
            switch (GD.Str(L["motion"]))
            {
                case "rise":
                {
                    double sp = rng.RandfRange(18.0, 46.0);
                    q["p"] = new Vector2(rng.RandfRange(0.05, 0.95) * w, h * rng.RandfRange(0.78, 1.0));
                    q["v"] = new Vector2(rng.RandfRange(-6, 6), -sp);
                    q["life"] = h * rng.RandfRange(0.45, 0.8) / sp;
                    q["spin"] = rng.RandfRange(-0.6, 0.6);
                    break;
                }
                case "fall":
                {
                    double fs = rng.RandfRange(24.0, 52.0);
                    q["p"] = new Vector2(rng.RandfRange(-0.05, 1.05) * w, -(double)L["size"] * 2.0);
                    q["v"] = new Vector2(rng.RandfRange(4, 18), fs);
                    q["life"] = (h + (double)L["size"] * 4.0) / fs;
                    break;
                }
                case "drift":
                {
                    var smoke = (double)L["size"] > 60.0;
                    double ds = smoke ? rng.RandfRange(10.0, 26.0) : rng.RandfRange(45.0, 95.0);
                    q["p"] = new Vector2(-(double)L["size"] * s, h * rng.RandfRange(0.18, 0.85));
                    q["v"] = new Vector2(ds, rng.RandfRange(-8, 4));
                    q["life"] = (w + (double)L["size"] * 2.6) / ds;
                    q["spin"] = smoke ? rng.RandfRange(-0.15, 0.15) : rng.RandfRange(-2.0, 2.0);
                    break;
                }
                case "twinkle":
                    q["p"] = new Vector2(rng.RandfRange(0.04, 0.96) * w, rng.RandfRange(0.06, 0.78) * h);
                    q["v"] = new Vector2(0, rng.RandfRange(-4, 0));
                    q["life"] = rng.RandfRange(1.6, 3.6);
                    q["spin"] = rng.RandfRange(-0.4, 0.4);
                    break;
                case "rain":
                {
                    double rs = rng.RandfRange(520.0, 760.0);
                    q["p"] = new Vector2(rng.RandfRange(-0.1, 1.2) * w, -30.0);
                    q["v"] = new Vector2(-rs * 0.28, rs);
                    q["life"] = (h + 60.0) / rs;
                    q["rot"] = Math.Atan2(q["v"].V2.y, q["v"].V2.x) - GD.PI * 0.5;
                    q["spin"] = 0.0;
                    break;
                }
                case "orbit":
                    q["p"] = Size * center;
                    q["v"] = Vector2.ZERO;
                    q["life"] = 1e9;
                    q["ph"] = GD.TAU * (double)parts.Filter(o => (int)o["l"] == li).Size() / GD.Maxf(1.0, (double)L["n"]);
                    q["spin"] = rng.RandfRange(-0.5, 0.5);
                    break;
                default:
                    q["p"] = new Vector2(rng.Randf() * w, rng.Randf() * h);
                    q["v"] = Vector2.ZERO;
                    q["life"] = 2.0;
                    break;
            }
            if (warm && (double)q["life"] < 1e8)
            {
                double a = rng.RandfRange(0.0, (double)q["life"]);
                q["age"] = a;
                q["p"] = q["p"].V2 + q["v"].V2 * a;
            }
            return q;
        }

        protected override void _Process(double delta)
        {
            if (!IsVisibleInTree() || layers.IsEmpty())
                return;
            delta = GD.Minf(delta, 0.1);
            _t += delta;
            for (int i = 0; i < parts.Size(); i++)
            {
                GDict q = parts[i].D;
                q["age"] = (double)q["age"] + delta;
                q["p"] = q["p"].V2 + q["v"].V2 * delta;
                q["rot"] = (double)q["rot"] + (double)q["spin"] * delta;
                if ((double)q["age"] >= (double)q["life"])
                    parts[i] = _NewPart((int)q["l"], false);
            }
            _flash = GD.Maxf(0.0, _flash - delta * 2.2);
            foreach (var ev in events)
            {
                GDict e = ev.D;
                GDict L = layers[(int)e["l"]].D;
                if ((double)e["age"] < 0.0)
                {
                    e["next"] = (double)e["next"] - delta;
                    if ((double)e["next"] <= 0.0)
                    {
                        e["age"] = 0.0;
                        e["dir"] = rng.Randf() < 0.5 ? -1.0 : 1.0;
                        if (GD.Str(L["motion"]) == "flash")
                        {
                            e["at"] = new Vector2((double)rng.RandfRange(0.15, 0.85) * Size.x, (double)rng.RandfRange(0.02, 0.2) * Size.y);
                            _flash = 1.0;
                        }
                        else
                            e["at"] = new Vector2((e["dir"] > 0 ? 0.1 : 0.9) * Size.x, (double)rng.RandfRange(0.02, 0.14) * Size.y);
                    }
                }
                else
                {
                    e["age"] = (double)e["age"] + delta;
                    var dur = GD.Str(L["motion"]) == "flash" ? 0.45 : 1.1;
                    if ((double)e["age"] > dur)
                    {
                        e["age"] = -1.0;
                        e["next"] = GD.Str(L["motion"]) == "flash" ? rng.RandfRange(2.5, 6.5) : rng.RandfRange(4.0, 8.0);
                    }
                }
            }
            QueueRedraw();
        }

        public void _Sprite(Texture2D tex, Vector2 at, double px, double rot, Color c, double sx = 1.0, double sy = 1.0)
        {
            DrawSetTransform(at, rot, new Vector2(sx, sy));
            DrawTextureRect(tex, new Rect2(-px * 0.5, -px * 0.5, px, px), false, c);
        }

        protected override void _Draw()
        {
            foreach (var qv in parts)
            {
                GDict q = qv.D;
                GDict L = layers[(int)q["l"]].D;
                Texture2D tex = L["tex"].As<Texture2D>();
                Color c = (Color)L["color"];
                var px = (double)L["size"] * (double)q["s"];
                var life = (double)q["life"];
                var u = life < 1e8 ? GD.Clampf((double)q["age"] / life, 0.0, 1.0) : 0.0;
                var a = 1.0;
                switch (GD.Str(L["motion"]))
                {
                    case "rise":
                    {
                        a = GD.Minf(u / 0.15, 1.0) * GD.Minf((1.0 - u) / 0.35, 1.0) * 0.85;
                        var sway = Math.Sin(_t * 1.6 + (double)q["ph"]) * 10.0;
                        _Sprite(tex, q["p"].V2 + new Vector2(sway, 0), px, (double)q["rot"], new Color(c, c.a * a));
                        break;
                    }
                    case "fall":
                    {
                        a = GD.Minf(u / 0.08, 1.0) * GD.Minf((1.0 - u) / 0.12, 1.0) * 0.95;
                        var sw = Math.Sin(_t * 1.3 + (double)q["ph"]) * 26.0;
                        _Sprite(tex, q["p"].V2 + new Vector2(sw, 0), px, (double)q["rot"], new Color(c, c.a * a), Math.Cos(_t * 2.6 + (double)q["ph"]), 1.0);
                        break;
                    }
                    case "drift":
                    {
                        a = GD.Minf(u / 0.12, 1.0) * GD.Minf((1.0 - u) / 0.12, 1.0) * ((double)L["size"] > 60.0 ? 0.32 : 0.85);
                        var wv = Math.Sin(_t * 0.9 + (double)q["ph"]) * 6.0;
                        _Sprite(tex, q["p"].V2 + new Vector2(0, wv), px, (double)q["rot"], new Color(c, c.a * a));
                        break;
                    }
                    case "twinkle":
                        a = Math.Sin(GD.PI * u);
                        _Sprite(tex, q["p"].V2, px * (0.7 + 0.3 * a), (double)q["rot"], new Color(c, c.a * a * 0.9));
                        break;
                    case "rain":
                        _Sprite(tex, q["p"].V2, px, (double)q["rot"], new Color(c, c.a * 0.32), 0.22, 3.4);
                        break;
                    case "orbit":
                    {
                        var ang = (double)q["ph"] + _t * 0.32;
                        var o = Size * center + new Vector2(Math.Cos(ang) * Size.x * 0.34, Math.Sin(ang) * Size.y * 0.035);
                        var near = 0.5 + 0.5 * Math.Sin(ang);           // (round the front: brighter and bigger)
                        a = (0.28 + 0.4 * near) * (0.8 + 0.2 * Math.Sin(_t * 2.0 + (double)q["ph"]));
                        _Sprite(tex, o, px * (0.8 + 0.3 * near), (double)q["rot"], new Color(c, c.a * a));
                        break;
                    }
                    case "halo":
                        a = 0.32 + 0.1 * Math.Sin(_t * 1.1);
                        _Sprite(tex, Size * center, px * (1.0 + 0.04 * Math.Sin(_t * 0.7)), _t * (double)q["spin"], new Color(c, c.a * a));
                        break;
                }
            }
            foreach (var ev in events)
            {
                GDict e = ev.D;
                if ((double)e["age"] < 0.0)
                    continue;
                GDict L2 = layers[(int)e["l"]].D;
                Color c2 = (Color)L2["color"];
                var px2 = (double)L2["size"];
                if (GD.Str(L2["motion"]) == "flash")
                {
                    var k = (double)e["age"] / 0.45;
                    var fl = k < 0.2 ? 1.0 : (k < 0.35 ? 0.35 : (k < 0.55 ? 0.9 : 1.0 - k));
                    _Sprite(L2["tex"].As<Texture2D>(), e["at"].V2 + new Vector2(0, px2 * 0.5), px2, 0.0, new Color(c2, GD.Clampf(fl, 0.0, 1.0)), (double)e["dir"], 1.0);
                }
                else
                {
                    var m = (double)e["age"] / 1.1;
                    var head = e["at"].V2 + new Vector2((double)e["dir"] * Size.x * 0.75 * m, Size.y * 0.3 * m);
                    var step = new Vector2(-(double)e["dir"] * 9.0, -3.6);
                    for (int j = 0; j < 9; j++)
                    {
                        var aa = (1.0 - (double)j / 9.0) * Math.Sin(GD.PI * m);
                        _Sprite(L2["tex"].As<Texture2D>(), head + step * (double)j, px2 * (1.0 - (double)j * 0.07), 0.0, new Color(c2, c2.a * aa));
                    }
                }
            }
            DrawSetTransform(Vector2.ZERO, 0.0, Vector2.ONE);
            if (_flash > 0.0)
                DrawRect(new Rect2(Vector2.ZERO, Size), new Color(0.75, 0.85, 1.0, 0.16 * _flash));
        }
    }
}
