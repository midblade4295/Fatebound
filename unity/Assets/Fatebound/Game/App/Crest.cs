// Ported from godot/scripts/app/crest.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;
using Eco = Fatebound.Game.Economy;

namespace Fatebound.Game
{
    // 0.31.196 (Kevin: "Do clan chest, clan camp, crest, ..."): a clan's crest -- its emblem (Eco.CLAN_EMBLEMS) in one colour
    // (CLAN_CHARGES) on a shield of another (CLAN_FIELDS), in an iron rim, or gold / silver / bronze for last week's League
    // podium ("fr"). Drawn from tools/build_clan_art.py's layers in assets/ui/clans/: the field tinted, the emblem tinted, the
    // rim on top. `code` is Eco.crest_code's "e.f.c" (cards, chat lines, the match's names and the boards carry it); "" draws
    // nothing. Its height is ASPECT x its width; SocialUI.crest() makes one of a given height.
    public class Crest : Control
    {
        public const string DIR = "res://assets/ui/clans/";
        public const double ASPECT = 280.0 / 256.0;          // the shield's height / width
        public const double EMBLEM_W = 0.56;                 // the emblem's size, of the shield's width
        public const double EMBLEM_Y = 0.48;                 // ... its middle, down the shield
        public static readonly GArray FRAMES = GArray.Of("gold", "silver", "bronze");

        public static GDict _tex = new GDict();

        public string code = "";
        public string frame = "";                        // "gold" / "silver" / "bronze" / "" (iron)

        public static Texture2D Tex(string name)
        {
            if (!_tex.Has(name))
            {
                var p = DIR + name + ".png";
                _tex[name] = ResourceLoader.Exists(p) ? Var.Of(ResourceLoader.Load(p)) : Var.Nil;
            }
            return _tex[name].As<Texture2D>();
        }

        public static GDict Colors(string c)
        {
            // {"e": emblem name, "field": Color, "charge": Color} ({} for no crest)
            var k = Eco.CrestOfCode(c);
            if (k.IsEmpty())
                return new GDict();
            return new GDict
            {
                { "e", GD.Str(Eco.CLAN_EMBLEMS[(int)k["e"]]) },
                { "field", Color.FromCode(GD.Str(Eco.CLAN_FIELDS[(int)k["f"]])) },
                { "charge", Color.FromCode(GD.Str(Eco.CLAN_CHARGES[(int)k["c"]])) },
            };
        }

        public Crest()
        {
            MouseFilter = Control.MOUSE_FILTER_IGNORE;
            TextureFilter = TextureFilterMode.LinearWithMipmaps;
        }

        public void SetCrest(string c, string fr = "")
        {
            code = c;
            frame = fr;
            QueueRedraw();
        }

        protected override void _Draw()
        {
            var w = GD.Minf(Size.x, Size.y / ASPECT);
            var h = w * ASPECT;
            DrawOn(this, code, new Rect2((Size.x - w) * 0.5, (Size.y - h) * 0.5, w, h), frame);
        }

        public static void DrawOn(CanvasItem ci, string code, Rect2 r, string frame = "", double alpha = 1.0)
        {
            // the crest drawn into r on any canvas item (the match's nameplates: scripts/siege/siege_hud.gd)
            var k = Colors(code);
            if (k.IsEmpty())
                return;
            var w = r.size.x;
            var h = r.size.y;
            var field = Tex("shield_field");
            var emblem = Tex("emblem_" + GD.Str(k["e"]));
            var rim = Tex("shield_rim_" + (FRAMES.Has(frame) ? frame : "iron"));
            if (field == null || rim == null)
            {
                // (no art: a plain shield shape in its colours)
                ci.DrawRect(new Rect2(r.position + new Vector2(w * 0.1, h * 0.08), new Vector2(w * 0.8, h * 0.6)), new Color((Color)k["field"], alpha));
                ci.DrawColoredPolygon(new[] { r.position + new Vector2(w * 0.1, h * 0.68), r.position + new Vector2(w * 0.9, h * 0.68),
                    r.position + new Vector2(w * 0.5, h * 0.95) }, new Color((Color)k["field"], alpha));
            }
            else
                ci.DrawTextureRect(field, r, false, new Color((Color)k["field"], alpha));
            if (emblem != null)
            {
                var es = w * EMBLEM_W;
                ci.DrawTextureRect(emblem, new Rect2(r.position.x + (w - es) * 0.5, r.position.y + h * EMBLEM_Y - es * 0.5, es, es), false, new Color((Color)k["charge"], alpha));
            }
            if (rim != null)
                ci.DrawTextureRect(rim, r, false, new Color(1, 1, 1, alpha));
        }
    }
}
