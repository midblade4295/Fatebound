// Ported from godot/scripts/siege/weapon_fx.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector3 = Fatebound.Sim.Vec3;
using Vector4 = Fatebound.Sim.Vec4;
using Color = Fatebound.GUI.Col;
using Transform3D = Fatebound.Sim.Xform3;
using AABB = Fatebound.Sim.Aabb;
using Material = Fatebound.GUI.GMaterial;

namespace Fatebound.Game
{
    using Root = Fatebound.Game.WeaponFxRoot;

    // Weapon effects (0.31.100). Kevin: "I want the effects to look better for the forge weapons. I also want to add effects
    // for all the legendary weapons." 0.31.188 (Kevin: "Remove the forge and the individual weapon skins. I only want the
    // cosmetics to be an entire outfit. Each outfit has its own specific looking weapon"): the Forge's stars and elements are
    // gone with the weapons; what's left is a signature weapon's own look (SIGNATURE) -- an outfit's weapon:
    //  - a glow pass over the weapon's own materials (forge_glow.gdshader): a fresnel rim, a glint running up the piece and
    //    its gems / lava / eye lit from its own texture (a colour key);
    //  - painted sprites (assets/vfx/weapon, cut from an ElevenLabs gpt-image-2 sheet by tools/cut_vfx_sheet.py) as
    //    particles, or pinned to the piece (rays behind a staff's head, a halo, a turning sigil, sparks circling it);
    //  - a ribbon behind the blade in a swing (a body's melee weapon only).
    // Cosmetic only. A match shows every live player's (with fewer effects on, theirs glow without particles).
    // Particle sizes in Godot ignore the emitter's scale, so the particles are built by weapon_fx_root.gd on its first frame
    // in the tree, in world units measured from the piece (everything below is in units of the piece's length).
    public class WeaponFx
    {
        public static readonly Shader GLOW = ResourceLoader.Load<Shader>("res://scripts/siege/forge_glow.gdshader");

        // kind "p" (default): particles. tex: the sprite; n, life (s); size (x the piece's length); at: the stretch along the
        // piece they come from (0 = the grip end, 1 = the business end), w: how far out to the sides (x the piece's girth);
        // world: left behind in the world (rising flames, falling leaves) rather than riding the piece; vel (lengths/s), along
        // the piece unless spread; grav (lengths/s^2, world up for world ones); spin (deg/s), angle (deg, random start);
        // look over its life: pop (grow then shrink), shrink, grow; fade: slow, hot (white-hot first), flicker; turb: wander.
        // kind "bill"/"flat": one sprite pinned at "at", facing the camera / laid across the piece; spin (rad/s), pulse.
        // kind "orbit": n sprites circling the piece's axis at r (x length), speed rad/s.
        public static readonly GDict PRESETS = new GDict
        {
            { "glints", GDict.Of("tex", "sparkle", "n", 3, "life", 1.0, "size", 0.16, "at", GArray.Of(0.3, 1.0), "w", 0.5, "pop", true, "angle", 12.0, "core", 0.9) },
            { "sparkle", GDict.Of("tex", "sparkle", "n", 6, "life", 0.9, "size", 0.2, "at", GArray.Of(0.25, 1.0), "w", 0.6, "pop", true, "angle", 12.0, "core", 0.9) },
            { "twinkle", GDict.Of("tex", "stars", "n", 3, "life", 1.5, "size", 0.26, "at", GArray.Of(0.55, 1.0), "w", 1.3, "pop", true, "angle", 30.0, "core", 0.9) },
            { "runes", GDict.Of("tex", "runes", "grid", 2, "n", 4, "life", 2.6, "size", 0.12, "at", GArray.Of(0.15, 0.85), "w", 1.8, "vel", GArray.Of(0.03, 0.06), "spread", 10.0, "fade", "slow", "core", 0.7, "alpha", 0.9) },
            { "motes", GDict.Of("tex", "dot", "n", 14, "life", 1.8, "size", 0.045, "at", GArray.Of(0.3, 1.0), "w", 0.9, "world", true, "vel", GArray.Of(0.02, 0.06), "spread", 180.0, "grav", new Vector3(0, 0.1, 0), "fade", "slow", "core", 0.6) },
            { "embers", GDict.Of("tex", "dot", "n", 18, "life", 1.2, "size", 0.03, "at", GArray.Of(0.5, 1.0), "w", 0.8, "world", true, "vel", GArray.Of(0.05, 0.2), "spread", 180.0, "grav", new Vector3(0, 0.35, 0), "turb", 1.0, "fade", "hot", "core", 1.0) },
            { "flames", GDict.Of("tex", "flame", "n", 12, "life", 0.6, "size", 0.2, "at", GArray.Of(0.65, 1.0), "w", 0.5, "world", true, "vel", GArray.Of(0.0, 0.1), "spread", 180.0, "grav", new Vector3(0, 0.6, 0), "shrink", true, "fade", "hot", "core", 0.8) },
            { "smoke", GDict.Of("tex", "smoke", "n", 6, "life", 1.8, "size", 0.28, "at", GArray.Of(0.55, 1.0), "w", 0.6, "world", true, "vel", GArray.Of(0.0, 0.05), "spread", 180.0, "grav", new Vector3(0, 0.08, 0), "grow", true, "spin", 40.0, "angle", 180.0, "fade", "slow", "core", 0.0, "alpha", 0.3) },
            { "lightning", GDict.Of("tex", "lightning", "n", 4, "life", 0.16, "size", 0.3, "at", GArray.Of(0.5, 1.0), "w", 0.7, "angle", 180.0, "fade", "flicker", "core", 1.0) },
            { "sparks", GDict.Of("tex", "dot", "n", 12, "life", 0.45, "size", 0.022, "at", GArray.Of(0.6, 1.0), "w", 0.6, "world", true, "vel", GArray.Of(0.4, 0.9), "spread", 180.0, "grav", new Vector3(0, -1.5, 0), "fade", "hot", "core", 1.0) },
            { "snow", GDict.Of("tex", "snowflake", "n", 8, "life", 2.4, "size", 0.09, "at", GArray.Of(0.25, 1.0), "w", 1.3, "world", true, "vel", GArray.Of(0.0, 0.03), "spread", 180.0, "grav", new Vector3(0, -0.06, 0), "spin", 90.0, "angle", 180.0, "turb", 0.5, "fade", "slow", "core", 0.6) },
            { "mist", GDict.Of("tex", "smoke", "n", 5, "life", 2.2, "size", 0.32, "at", GArray.Of(0.3, 1.0), "w", 0.8, "vel", GArray.Of(0.0, 0.02), "spread", 180.0, "grow", true, "spin", 20.0, "angle", 180.0, "fade", "slow", "core", 0.0, "alpha", 0.2) },
            { "leaves", GDict.Of("tex", "leaf", "n", 7, "life", 2.6, "size", 0.1, "at", GArray.Of(0.1, 1.0), "w", 1.3, "world", true, "vel", GArray.Of(0.0, 0.04), "spread", 180.0, "grav", new Vector3(0, -0.06, 0), "spin", 120.0, "angle", 180.0, "turb", 0.6, "fade", "slow", "core", 0.3) },
            { "feathers", GDict.Of("tex", "feather", "n", 5, "life", 2.8, "size", 0.14, "at", GArray.Of(0.5, 1.0), "w", 1.1, "world", true, "vel", GArray.Of(0.0, 0.04), "spread", 180.0, "grav", new Vector3(0, -0.07, 0), "spin", 50.0, "angle", 180.0, "turb", 0.5, "fade", "slow", "core", 0.4) },
            { "wisps", GDict.Of("tex", "wisp", "n", 8, "life", 1.3, "size", 0.18, "at", GArray.Of(0.5, 1.0), "w", 0.6, "world", true, "vel", GArray.Of(0.0, 0.08), "spread", 180.0, "grav", new Vector3(0, 0.25, 0), "shrink", true, "core", 0.6, "alpha", 0.85) },
            { "crescents", GDict.Of("tex", "crescent", "n", 4, "life", 2.4, "size", 0.11, "at", GArray.Of(0.3, 1.0), "w", 1.4, "vel", GArray.Of(0.02, 0.05), "spread", 10.0, "spin", 25.0, "angle", 180.0, "fade", "slow", "core", 0.7) },
            { "rays", GDict.Of("kind", "bill", "tex", "rays", "at", 0.9, "size", 0.75, "spin", 0.25, "pulse", 0.35, "alpha", 0.7, "core", 0.5) },
            { "halo", GDict.Of("kind", "flat", "tex", "ring", "at", 1.08, "size", 0.42, "spin", 0.0, "pulse", 0.25, "alpha", 0.9, "core", 0.6) },
            { "sigil", GDict.Of("kind", "bill", "tex", "sigil", "at", 0.9, "size", 0.5, "spin", 0.35, "pulse", 0.3, "alpha", 0.45, "core", 0.3) },
            { "vortex", GDict.Of("kind", "bill", "tex", "vortex", "at", 0.9, "size", 0.45, "spin", -1.2, "pulse", 0.25, "alpha", 0.5, "core", 0.3) },
            { "orbit", GDict.Of("kind", "orbit", "tex", "sparkle", "n", 3, "at", 0.88, "r", 0.17, "size", 0.11, "speed", 1.8, "pulse", 0.4, "alpha", 1.0, "core", 0.9) },
        };
        // Each signature piece (by its mw/ model): col, its glow (rim, sweep), key [hue deg, +- deg, min saturation, min
        // brightness] and key_amt for the parts of its texture that light up, trail (a swing's ribbon), solo (a pair of the
        // same piece: the particles on the main hand only), fx (presets, with overrides; col defaults to the piece's), spin
        // (0.31.103: parts of the model cut into their own nodes by tools/weapon_spin_parts.py, turned about their own +Y at
        // speed rad/s and rocked +-wobble degrees about their X at wobble_speed).
        // (0.31.100-0.31.187: the legendary weapons' -- Kingsoath, the Eye of the Archon, the Astral Codex ...)
        public static readonly GDict SIGNATURE = new GDict
        {
            { "lion_sword", GDict.Of("col", "#ffd36b", "rim", 0.3, "sweep", 0.9, "trail", "#ffe08a", "fx", GArray.Of(GDict.Of("p", "sparkle", "n", 4, "col", "#fff2c4"))) },
            { "lion_shield", GDict.Of("col", "#ffd36b", "rim", 0.25, "sweep", 0.7) },
            { "mammoth_axe", GDict.Of("col", "#fff1d6", "rim", 0.2, "sweep", 0.4, "trail", "#e8dcc0", "fx", GArray.Of(GDict.Of("p", "snow", "n", 5))) },
            { "coin_dagger", GDict.Of("col", "#ffcf3a", "rim", 0.3, "sweep", 0.8, "trail", "#c47bff", "solo", true, "fx", GArray.Of(GDict.Of("p", "sparkle", "n", 3, "col", "#ffe08a"))) },
            { "orchard_bow", GDict.Of("col", "#ff8fb0", "rim", 0.25, "sweep", 0.5, "fx", GArray.Of(GDict.Of("p", "leaves", "n", 5, "col", "#ffb0c8"))) },
            { "phoenix_staff", GDict.Of("col", "#ff7a1a", "rim", 0.3, "sweep", 0.5, "fx", GArray.Of(GDict.Of("p", "flames", "col", "#ff7a1a", "at", GArray.Of(0.8, 1.0), "size", 0.16),
                GDict.Of("p", "embers", "col", "#ffb04a", "at", GArray.Of(0.75, 1.0)), GDict.Of("p", "feathers", "n", 3, "col", "#ff9a3a", "at", GArray.Of(0.8, 1.0)))) },
            { "bell_scepter", GDict.Of("col", "#ffd27a", "rim", 0.3, "sweep", 0.6, "fx", GArray.Of(GDict.Of("p", "motes", "n", 8, "col", "#fff3c8", "at", GArray.Of(0.6, 1.0)),
                GDict.Of("p", "rays", "col", "#ffe0a0", "size", 0.45, "alpha", 0.4))) },
            { "ember_hammer", GDict.Of("col", "#ff6a1a", "rim", 0.25, "sweep", 0.35, "key", GArray.Of(20, 16, 0.55, 0.5), "key_amt", 2.4, "trail", "#ff6a1a",
                "fx", GArray.Of(GDict.Of("p", "embers", "col", "#ff7a2a", "at", GArray.Of(0.6, 1.0)), GDict.Of("p", "smoke", "n", 3, "col", "#5a3020", "alpha", 0.2))) },
            { "ashen_shield", GDict.Of("col", "#ff6a1a", "rim", 0.2, "sweep", 0.3, "key", GArray.Of(20, 16, 0.55, 0.5), "key_amt", 2.2) },
            { "bloodmoon_greatsword", GDict.Of("col", "#ff3a2a", "rim", 0.35, "sweep", 0.4, "key", GArray.Of(5, 14, 0.5, 0.35), "key_amt", 2.0, "trail", "#ff3020",
                "fx", GArray.Of(GDict.Of("p", "embers", "n", 10, "col", "#ff4020"), GDict.Of("p", "smoke", "n", 3, "col", "#a01810", "alpha", 0.2))) },
            { "ribbon_dagger", GDict.Of("col", "#e0486a", "rim", 0.35, "sweep", 0.6, "trail", "#e0486a", "solo", true,
                "fx", GArray.Of(GDict.Of("p", "smoke", "n", 3, "col", "#7a2040", "alpha", 0.25))) },
            { "wolf_crossbow", GDict.Of("col", "#cfd6e0", "rim", 0.25, "sweep", 0.5, "fx", GArray.Of(GDict.Of("p", "mist", "col", "#cfd6e0", "alpha", 0.15))) },
            { "orrery_staff", GDict.Of("col", "#7fb8ff", "rim", 0.35, "sweep", 0.5, "key", GArray.Of(210, 20, 0.45, 0.45), "key_amt", 2.0,
                "fx", GArray.Of(GDict.Of("p", "orbit", "n", 3, "col", "#ffe08a"), GDict.Of("p", "twinkle", "col", "#c9d8ff"))) },
            { "starchart_tome", GDict.Of("col", "#ffd36b", "rim", 0.3, "sweep", 0.5, "fx", GArray.Of(GDict.Of("p", "twinkle", "col", "#ffe7a3", "at", GArray.Of(0.0, 1.0), "w", 1.0))) },
            { "lantern_shovel", GDict.Of("col", "#7dff9a", "rim", 0.3, "sweep", 0.3, "key", GArray.Of(120, 30, 0.4, 0.4), "key_amt", 2.2,
                "fx", GArray.Of(GDict.Of("p", "wisps", "n", 5, "col", "#8dffa8", "at", GArray.Of(0.75, 0.95)))) },
            { "geode_hammer", GDict.Of("col", "#b06bff", "rim", 0.3, "sweep", 0.4, "key", GArray.Of(275, 25, 0.35, 0.35), "key_amt", 2.2, "trail", "#b06bff",
                "fx", GArray.Of(GDict.Of("p", "sparkle", "col", "#d9b8ff", "at", GArray.Of(0.7, 1.0)))) },
            { "geode_shield", GDict.Of("col", "#b06bff", "rim", 0.25, "sweep", 0.3, "key", GArray.Of(275, 25, 0.35, 0.35), "key_amt", 2.0) },
            { "dragon_halberd", GDict.Of("col", "#ff6a3a", "rim", 0.3, "sweep", 0.5, "trail", "#ff6a3a", "fx", GArray.Of(GDict.Of("p", "embers", "n", 10, "col", "#ff8a3a", "at", GArray.Of(0.75, 1.0)))) },
            { "rose_rapier", GDict.Of("col", "#ffd36b", "rim", 0.3, "sweep", 0.9, "trail", "#ff5a7a", "fx", GArray.Of(GDict.Of("p", "leaves", "n", 4, "col", "#d0304a", "at", GArray.Of(0.0, 0.4)))) },
            { "thorn_stiletto", GDict.Of("col", "#8fd16f", "rim", 0.25, "sweep", 0.5) },
            { "lightning_rod_staff", GDict.Of("col", "#6fb6ff", "rim", 0.35, "sweep", 0.5, "key", GArray.Of(205, 18, 0.45, 0.45), "key_amt", 2.2,
                "fx", GArray.Of(GDict.Of("p", "lightning", "n", 4, "col", "#9fe6ff", "at", GArray.Of(0.8, 1.0)), GDict.Of("p", "sparks", "col", "#c8f2ff", "at", GArray.Of(0.8, 1.0)))) },
            { "brass_blunderbuss", GDict.Of("col", "#ffcf6a", "rim", 0.25, "sweep", 0.7, "fx", GArray.Of(GDict.Of("p", "smoke", "n", 3, "col", "#e8e2d6", "alpha", 0.2, "at", GArray.Of(0.85, 1.0)))) },
            { "blossom_staff", GDict.Of("col", "#ffb0d0", "rim", 0.3, "sweep", 0.4, "fx", GArray.Of(GDict.Of("p", "leaves", "n", 7, "col", "#ffb0c8", "at", GArray.Of(0.7, 1.0)),
                GDict.Of("p", "motes", "n", 6, "col", "#fff0f6", "at", GArray.Of(0.7, 1.0)))) },
        };
        public static readonly GArray NO_SWING = GArray.Of("bow", "staff", "wand", "spellbook", "book", "tome", "shield", "quiver", "orb", "lantern");

        public static GDict _glow = new GDict();           // glow settings -> ShaderMaterial
        public static GDict _base = new GDict();           // base material id|glow key -> the base material with that glow as next_pass

        public static GDict Signature(string file)
        {
            return file.BeginsWith("mw/") ? SIGNATURE.Get(file.Substr(3), new GDict()).D : new GDict();
        }

        public static bool Wants(string file)
        {
            return !Signature(file).IsEmpty();
        }

        public static AABB BoxOf(Node3D model)
        {
            var box = new AABB();
            var first = true;
            foreach (var mi in model.FindChildren("*", "MeshInstance3D", true, false))
            {
                var m = mi as MeshInstance3D;
                if (m.Mesh == null)
                    continue;
                var xf = Transform3D.IDENTITY;
                Node n = m;
                while (n != null && n != model)
                {
                    xf = (n as Node3D).Transform * xf;
                    n = n.GetParent();
                }
                AABB b = xf * m.GetAabb();
                box = first ? b : box.Merge(b);
                first = false;
            }
            return box;
        }

        public static bool Swings(string template)
        {
            if (template == "")
                return false;
            var t = template.ToLowerInvariant();
            foreach (var w in NO_SWING)
            {
                if (t.Contains(w.AsString()))
                    return false;
            }
            return true;
        }

        public static GDict Spec(Var entry, Color col, double mul = 1.0)
        {
            // a preset with its overrides and colour
            GDict e = entry.IsString ? GDict.Of("p", entry) : entry.D;
            GDict @out = PRESETS.Get(GD.Str(e["p"]), new GDict()).D.Duplicate();
            foreach (var k in e)
            {
                if (k != "p")
                    @out[k] = e[k];
            }
            @out["col"] = e.Has("col") ? Color.FromCode(GD.Str(e["col"])) : col;
            if (@out.Has("n") && GD.Str(@out.Get("kind", "p")) == "p")
                @out["n"] = GD.Maxi(1, (int)GD.Round((double)@out["n"] * mul));
            return @out;
        }

        public static void Apply(Node3D model, string file, bool main = true, string template = "", bool lite = false)
        {
            // the glow on this piece, and its particles / ribbon (built on its first frame in the tree, weapon_fx_root.gd).
            // template: the KayKit file the piece is held like (a body's weapon); "" for a piece on show (no ribbon).
            // lite: the glow only (another player's weapon with fewer effects on, 0.31.101)
            var leg = Signature(file);
            if (leg.IsEmpty())
                return;
            var box = BoxOf(model);
            var leg_col = Color.FromCode(GD.Str(leg.Get("col", "#ffffff")));
            // ---- the glow
            GArray g = GArray.Of((double)leg.Get("rim", 0.3), (double)leg.Get("sweep", 0.6), 0.0, 1.0);
            var gcol = leg_col;
            GArray key = leg.Get("key", new GArray()).A;
            var key_amt = !key.IsEmpty() ? (double)leg.Get("key_amt", 1.6) : 0.0;
            var span = GD.Snappedf(GD.Maxf(box.size.y, 0.2), 0.05);
            var gk = GD.Fmt("%s|%.2f|%.2f|%.2f|%.2f|%.2f|%s|%.2f", gcol.ToHtmlExact(), g[0], g[1], g[2], g[3], span, GD.Str(key), key_amt);
            foreach (var mi in model.FindChildren("*", "MeshInstance3D", true, false))
            {
                var m = mi as MeshInstance3D;
                if (m.Mesh == null)
                    continue;
                for (int surf = 0; surf < m.Mesh.GetSurfaceCount(); surf++)
                {
                    var @base = m.GetActiveMaterial(surf);
                    if (@base == null)
                        continue;
                    Texture2D tex = @base is BaseMaterial3D ? (@base as BaseMaterial3D).AlbedoTexture : null;
                    var mk = gk + (key_amt > 0.0 && tex != null ? GD.Fmt("|%d", (long)tex.GetInstanceId()) : "");
                    if (!_glow.Has(mk))
                    {
                        var gm = new ShaderMaterial();
                        gm.Shader = GLOW;
                        gm.SetShaderParameter("tint", gcol);
                        gm.SetShaderParameter("rim", g[0]);
                        gm.SetShaderParameter("sweep", g[1]);
                        gm.SetShaderParameter("veins", g[2]);
                        gm.SetShaderParameter("boost", g[3]);
                        gm.SetShaderParameter("span", span);
                        if (key_amt > 0.0 && tex != null)
                        {
                            gm.SetShaderParameter("albedo_tex", tex);
                            gm.SetShaderParameter("key", new Vector4((double)key[0] / 360.0, (double)key[1] / 360.0, (double)key[2], (double)key[3]));
                            gm.SetShaderParameter("key_amt", key_amt);
                        }
                        _glow[mk] = Var.Of(gm);
                    }
                    var bk = GD.Fmt("%d|%s", (long)@base.GetInstanceId(), mk);
                    if (!_base.Has(bk))
                    {
                        Material dup = (Material)@base.Duplicate();
                        dup.NextPass = _glow[mk].As<Material>();
                        _base[bk] = Var.Of(dup);
                    }
                    m.SetSurfaceOverrideMaterial(surf, _base[bk].As<Material>());
                }
            }
            // ---- particles, pinned sprites, the ribbon
            if (lite)
                return;
            var specs = new GArray();
            if (main || !(bool)leg.Get("solo", false))
            {
                foreach (var e in leg.Get("fx", new GArray()))
                    specs.Append(Spec(e, leg_col));
            }
            var trail = new Color(0, 0, 0, 0);
            if (Swings(template) && leg.Has("trail"))
                trail = Color.FromCode(GD.Str(leg["trail"]));
            GArray spins = leg.Get("spin", new GArray()).A;
            if (specs.IsEmpty() && trail.a <= 0.0 && spins.IsEmpty())
                return;
            var root = new Root();
            root.Name = "WeaponFx";
            root.box = box;
            root.specs = specs;
            root.trail = trail;
            root.spins = spins;
            model.AddChild(root);
        }
    }
}
