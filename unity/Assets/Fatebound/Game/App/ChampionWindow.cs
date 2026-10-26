// Ported from godot/scripts/app/champion_window.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;
using UI = Fatebound.Game.Ui;
using UI2 = Fatebound.Game.Ui2;
using Eco = Fatebound.Game.Economy;
using Champions = Fatebound.Game.Champions;
using Moba = Fatebound.Sim.Moba;
using Kits = Fatebound.Sim.MobaKits;
using Hud = Fatebound.Game.SiegeHud;
using Fx = Fatebound.Game.ChampionFx;

namespace Fatebound.Game
{
    // 0.31.187 (Kevin: "When clicking on a champion, make a customized window for them that pops up that is themed around them
    // and player can also zoom in and rotate them. Use art and effects that match each characters lore. Also put every skin
    // that character has into that page that allows players to purchase or preview what it looks like"): a champion's own
    // window, from the Locker's CHAMPIONS (screens.gd locker) and the Armory's nameplate. 0.31.204: from the ARMORY's HEROES
    // (owned_only: only the outfits of his you own, and MORE IN THE MARKET when there are others) and the Market's HEROES
    // and outfit cards (all of them, to buy).
    //   * his place painted behind him (Champions.art -- the Knight's castle bridge at dawn, the Necromancer's graveyard...),
    //     slowly breathing, his colour over it, and his effects in it (champion_fx.gd: embers, leaves, rain and lightning...);
    //   * he stands in it in 3D, in the skin he wears: drag to turn him, pinch (or + / -) to zoom;
    //   * his name, title, class and role; whether he's yours, free this week or at his launch price -- UNLOCK (the same
    //     choices as the 5v5 window: gold, gems, a shard, a Hero Token), or PLAY as him;
    //   * SKINS: his own look and every skin of his -- tap one to see him in it; WEAR one you own, BUY one you don't (gems,
    //     asked first; a skin of a hero still locked brings him, League's way);
    //   * his story and his line, and his kit (Q W E R) with its icons.
    public class ChampionWindow : Control
    {
        public const string COIN = "res://assets/ui/currency/coin.png";
        public const string GEM = "res://assets/ui/currency/gem.png";
        public const double STAGE_TOP = 0.16;            // the 3D stage, as fractions of the window's height (0.13-0.6, the panel under it, in
        public const double STAGE_BOTTOM = 0.98;         // portrait)
        public const double SPLIT = 0.5;                 // 0.31.216 (landscape, Honor of Kings' hero page): him on the left, the panel on the right

        public SiegeApp app;
        public string hero = "knight";
        public string preview = "";                  // the skin he's shown in ("" his own look) -- a skin you don't own is only a preview
        public bool owned_only = false;              // 0.31.204: opened from the Armory -- his outfits you own, no others
        public Showcase _show;
        public TextureRect _bg;
        public VBoxContainer _sheet;                 // the panel's content (rebuilt by _render)
        public ScrollContainer _scroll;
        public HBoxContainer _status;                // the chips over the stage
        public Control _preview_chip;
        public Control overlay;                      // the unlock chooser or a purchase question, over the window
        public GArray fx = new GArray();             // the effect layers (champion_fx.gd)

        public void Open(SiegeApp a, string hid, string show_skin = "__worn", bool only_owned = false)
        {
            app = a;
            owned_only = only_owned;
            hero = Moba.HEROES.ContainsKey(hid) ? hid : "knight";
            preview = show_skin == "__worn" ? app.profile.WornSkin(hero) : show_skin;
            SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            MouseFilter = Control.MOUSE_FILTER_STOP;
            GDict ch = Champions.Of(hero);
            Color acc = Champions.Accent(hero);
            app.Sfx("menuOpen");
            // ---- his place: the painting (cover), breathing slowly
            var back = new ColorRect();
            back.Color = new Color(0.02, 0.02, 0.04);
            back.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            AddChild(back);
            _bg = new TextureRect();
            var art = Champions.Art(hero);
            _bg.Texture = ResourceLoader.Exists(art) ? ResourceLoader.Load<Texture2D>(art) : null;
            _bg.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            _bg.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
            _bg.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            _bg.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(_bg);
            Resized += () => _bg.PivotOffset = _bg.Size * new Vector2(0.5, 0.45);
            UI2.WhenReady(_bg, () =>
            {
                var tw = _bg.CreateTween().SetLoops();
                tw.TweenProperty(_bg, "scale", Vector2.ONE * 1.05, 9.0).SetTrans(Tween.TRANS_SINE).SetEase(Tween.EASE_IN_OUT);
                tw.TweenProperty(_bg, "scale", Vector2.ONE, 9.0).SetTrans(Tween.TRANS_SINE).SetEase(Tween.EASE_IN_OUT);
            });
            // his colour: a dark band at the top for the name, the bottom into the panel, his colour at the edges
            AddChild(_Shade(GArray.Of(GArray.Of(0.0, new Color(0, 0, 0, 0.72)), GArray.Of(0.2, new Color(0, 0, 0, 0.0)), GArray.Of(0.8, new Color(0, 0, 0, 0.0)),
                GArray.Of(1.0, new Color(acc.Darkened(0.85), 0.6))), true));
            AddChild(_Shade(GArray.Of(GArray.Of(0.0, new Color(acc, 0.22)), GArray.Of(0.18, new Color(acc, 0.0)), GArray.Of(0.82, new Color(acc, 0.0)), GArray.Of(1.0, new Color(acc, 0.22))), false));
            // ---- his effects behind him
            fx = ch.Get("fx", new GArray()).A;
            foreach (var add in new[] { true, false })
                _FxLayer(false, add);
            // ---- he stands there in 3D
            var stage = new Control();
            stage.AnchorLeft = 0.0;
            stage.AnchorRight = SPLIT;
            stage.AnchorTop = STAGE_TOP;
            stage.AnchorBottom = STAGE_BOTTOM;
            stage.ClipContents = true;
            AddChild(stage);
            _show = new Showcase();
            _show.plinth = false;
            _show.interactive = true;
            _show.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            stage.AddChild(_show);
            _ShowLook();
            // ---- his effects in front of him (falling leaves, rain, blown embers)
            foreach (var add in new[] { true, false })
                _FxLayer(true, add);
            Control zs = new Control();                  // (the zoom buttons and hint over the stage, above the front effects)
            zs.AnchorRight = SPLIT;
            zs.AnchorTop = STAGE_TOP;
            zs.AnchorBottom = STAGE_BOTTOM;
            zs.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(zs);
            ZoomControls(zs, _show);
            _status = new HBoxContainer();
            _status.AddThemeConstantOverride("separation", 6);
            _status.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            _status.Position = new Vector2(12, 8);
            zs.AddChild(_status);
            // ---- the name
            var head = new VBoxContainer();
            head.AddThemeConstantOverride("separation", 0);
            head.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            head.AnchorRight = SPLIT;
            head.OffsetLeft = 14;
            head.OffsetRight = -8;
            head.OffsetTop = 10.0 + (double)app.safe_top;
            AddChild(head);
            var rr = new HBoxContainer();
            rr.AddThemeConstantOverride("separation", 6);
            rr.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            head.AddChild(rr);
            var role = Kits.RoleOf(hero);
            var badge = new TextureRect();
            badge.Texture = MobaPanel.RoleBadge(role);
            badge.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            badge.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            badge.CustomMinimumSize = new Vector2(22, 22);
            badge.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            rr.AddChild(badge);
            var cl = UI2.Text(rr, GD.Fmt("%s  ·  %s", GD.Str(Moba.HEROES[hero].name).ToUpperInvariant(), GD.Str(Kits.ROLE_NAMES.GetValueOrDefault(role, ""))), 13,
                Color.FromCode(GD.Str(MobaPanel.ROLE_COL.Get(role, "#ffffff"))).Lightened(0.3), new Color(0, 0, 0, 0.9), 4);
            cl.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            var nm = UI2.Text(head, GD.Str(ch.Get("name", hero)).ToUpperInvariant(), 27, Color.WHITE, acc.Darkened(0.7), 7);
            nm.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            nm.SetMeta("champ_name", true);
            var ep = UI.Label(head, GD.Str(ch.Get("title", "")), 15, acc.Lightened(0.55), UI.LORE_FONT, true);
            ep.AddThemeColorOverride("font_outline_color", new Color(0, 0, 0, 0.9));
            ep.AddThemeConstantOverride("outline_size", 5);
            var x = UI2.Button(this, "✕", "ghost", Close, "champ_close", 20, 44.0, 14.0);
            x.AnchorLeft = 1.0;
            x.AnchorRight = 1.0;
            x.OffsetLeft = -56;
            x.OffsetRight = -10;
            x.OffsetTop = 10.0 + (double)app.safe_top;
            x.OffsetBottom = 54.0 + (double)app.safe_top;
            // ---- the panel: status and UNLOCK / PLAY, SKINS, the story, the kit
            var panel = new Control();
            panel.AnchorLeft = SPLIT;
            panel.AnchorRight = 1.0;
            panel.AnchorTop = 0.0;
            panel.AnchorBottom = 1.0;
            panel.OffsetLeft = 4;
            panel.OffsetRight = -8;
            panel.OffsetTop = 62.0 + (double)app.safe_top;          // (under the ✕)
            panel.OffsetBottom = -8;
            AddChild(panel);
            UI2.Plate(panel, "glass", 20.0, "gold", GDict.Of("fill_top", new Color(acc.Darkened(0.82), 0.82), "fill_bottom", new Color(0.02, 0.02, 0.05, 0.92),
                "outline", 2.0, "outline_color", new Color(acc, 0.75)));
            _scroll = new ScrollContainer();
            _scroll.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            _scroll.OffsetLeft = 12;
            _scroll.OffsetRight = -12;
            _scroll.OffsetTop = 10;
            _scroll.OffsetBottom = -8;
            _scroll.HorizontalScrollMode = ScrollContainer.SCROLL_MODE_DISABLED;
            panel.AddChild(_scroll);
            _sheet = new VBoxContainer();
            _sheet.AddThemeConstantOverride("separation", 8);
            _sheet.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            _scroll.AddChild(_sheet);
            _Render();
        }

        public void Close()
        {
            app.Sfx("menuClose");
            app.CloseModal();
        }

        public void Refresh()
        {
            // (app.rebuild calls this: the profile changed under the window)
            if (_sheet != null)
                _Render();
        }

        public TextureRect _Shade(GArray stops, bool vertical)
        {
            var g = new Gradient();
            g.SetOffsets(stops.Map(st => (double)st[0]).ToFloats());
            var cols = new List<Color>();
            foreach (var cv in stops.Map(st => st[1]))
                cols.Add((Color)cv);
            g.SetColors(cols);
            var gt = new GradientTexture2D();
            gt.Gradient = g;
            gt.Width = vertical ? 4 : 64;
            gt.Height = vertical ? 64 : 4;
            gt.FillFrom = new Vector2(0, 0);
            gt.FillTo = vertical ? new Vector2(0, 1) : new Vector2(1, 0);
            var t = new TextureRect();
            t.Texture = gt;
            t.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            t.StretchMode = TextureRect.STRETCH_SCALE;
            t.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            return t;
        }

        public void _FxLayer(bool in_front, bool add)
        {
            if (!fx.Any(l => Fx.Wants(l.A, in_front, add)))
                return;
            var f = new Fx();
            f.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            f.Name = GD.Fmt("ChampionFx_%s_%s", in_front ? "front" : "back", add ? "light" : "laid");
            AddChild(f);
            // (round him: the stage's middle, about his chest -- his feet are 78 % down the stage)
            f.Setup(fx, in_front, add, new Vector2(SPLIT * 0.5, STAGE_TOP + (STAGE_BOTTOM - STAGE_TOP) * 0.6));
        }

        public GDict _Look()
        {
            // the outfit shown -- its body and its own weapon (0.31.188); {} his own look
            return preview != "" ? GDict.Of("skin", preview) : new GDict();
        }

        public void _ShowLook()
        {
            if (_show != null)
                _show.ShowLook(hero, _Look());
        }

        public static void ZoomControls(Control stage, Showcase sh)
        {
            // + / - on the right of the stage, and the hint under him (the Locker's own, Screens.zoom_controls, keys champ_*)
            var zc = new VBoxContainer();
            zc.AddThemeConstantOverride("separation", 10);
            zc.SetAnchorsAndOffsetsPreset(Control.PRESET_CENTER_RIGHT);
            zc.OffsetLeft = -56;
            zc.OffsetRight = -10;
            zc.OffsetTop = -50;
            zc.OffsetBottom = 50;
            stage.AddChild(zc);
            foreach (var zb in GArray.Of(GArray.Of("+", 1.3, "champ_zoom_in"), GArray.Of("−", 1.0 / 1.3, "champ_zoom_out")))
            {
                double zf = (double)zb[1];
                var b = UI2.Button(zc, GD.Str(zb[0]), "blue", () => sh.ZoomBy(zf), GD.Str(zb[2]), 24, 44.0, 22.0);
                b.CustomMinimumSize = new Vector2(44, 44);
                b.AddThemeFontOverride("font", UI.HEAVY_FONT);
            }
            var hint = UI2.Chip(stage, "DRAG TO TURN  ·  PINCH TO ZOOM", new Color(0.02, 0.03, 0.1, 0.7), new Color(1, 1, 1, 0.85), new Color(UI2.GOLD, 0.45));
            hint.AnchorLeft = 0.5;
            hint.AnchorRight = 0.5;
            hint.AnchorTop = 1.0;
            hint.AnchorBottom = 1.0;
            hint.OffsetLeft = -100;
            hint.OffsetRight = 100;
            hint.OffsetTop = -26;
            hint.OffsetBottom = -8;
            hint.MouseFilter = Control.MOUSE_FILTER_IGNORE;
        }

        // ---------------- the panel ----------------
        public void _Render()
        {
            var p = app.profile;
            Color acc = Champions.Accent(hero);
            GDict ch = Champions.Of(hero);
            var keep = _scroll.ScrollVertical;
            foreach (var c in _sheet.GetChildren())
            {
                _sheet.RemoveChild(c);
                c.QueueFree();
            }
            foreach (var c in _status.GetChildren())
            {
                _status.RemoveChild(c);
                c.QueueFree();
            }
            bool owned = p.OwnsHero(hero);
            bool plays = p.CanPlayHero(hero);
            GDict pr = p.HeroPrice(hero);
            // ---- the chips over the stage
            if (!owned && plays)
                UI2.Chip(_status, "FREE THIS WEEK", new Color("#2f8a3e"), Color.WHITE, new Color("#0a2006"));
            if (Eco.Launching(hero, p.Now()))
            {
                var left = (int)Math.Ceiling((double)((int)Eco.HERO_LAUNCH[hero] + Eco.LAUNCH_DAYS * 86400 - p.Now()) / 86400.0);
                UI2.Chip(_status, GD.Fmt("NEW  ·  %d DAY%s AT LAUNCH PRICE", left, left == 1 ? "" : "S"), new Color("#d9682a"), Color.WHITE, new Color("#3a1402"));
            }
            if (preview != "" && !p.OwnsSkin(preview))
                UI2.Chip(_status, "PREVIEW", new Color(acc.Darkened(0.45), 0.9), Color.WHITE, new Color(0, 0, 0, 0.8));
            // ---- yours? UNLOCK or PLAY
            var top = UI.Row(_sheet, 8);
            if (owned)
            {
                var yl = UI2.Text(top, "YOURS", 18, new Color("#9dff8a"), new Color("#0a2006"), 5);
                yl.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            }
            else if (!pr.IsEmpty() && !owned_only)          // (0.31.205: from the Armory, the Market says his price)
            {
                var pv = new VBoxContainer();
                pv.AddThemeConstantOverride("separation", 0);
                pv.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                top.AddChild(pv);
                var pl = UI.Row(pv, 4);
                UI2.Img(pl, COIN, 20.0);
                UI2.Text(pl, UI.Grouped((int)pr["gold"]), 17, UI2.GOLD, new Color("#201002"), 4);
                UI2.Body(pl, "or", 11, UI2.SOFT, false);
                UI2.Img(pl, GEM, 20.0);
                UI2.Text(pl, UI.Grouped((int)pr["gems"]), 17, new Color("#cfe9ff"), new Color("#0a1238"), 4);
                if (p.ShardsOf(hero) > 0)
                    UI2.Body(pv, GD.Fmt("◆ With the shard you hold: %s gold", UI.Grouped(Eco.ShardUnlockGold(hero, p.Now()))), 10, new Color("#c9f7bd"), false);
            }
            var sp = new Control();
            sp.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            top.AddChild(sp);
            if (!owned && !pr.IsEmpty() && owned_only)
            {
                // 0.31.205: a free one from the Armory -- he's kept in the Market (heroes are bought there, 0.31.204)
                var mb = UI2.Button(top, "OWN IN MARKET", "gold", () =>
                {
                    app.Sfx("tab");
                    app.OpenMarket("heroes", hero);
                }, "champ_to_market", 15, 46.0, 14.0, "res://assets/ui/v2/icons/stall.png");
                var mbm = mb.CustomMinimumSize;
                mbm.x = 150;
                mb.CustomMinimumSize = mbm;
                UI2.Sweep(mb);
            }
            else if (!owned && !pr.IsEmpty())
            {
                var ub = UI2.Button(top, "UNLOCK", "gold", OpenChooser, "champ_unlock", 17, 46.0, 14.0);
                var ubm = ub.CustomMinimumSize;
                ubm.x = 120;
                ub.CustomMinimumSize = ubm;
                UI2.Sweep(ub);
            }
            if (plays)
            {
                var pb = UI2.Button(top, "PLAY", "orange", _Play, "champ_play", 17, 46.0, 14.0);
                var pbm = pb.CustomMinimumSize;
                pbm.x = 100;
                pb.CustomMinimumSize = pbm;
            }
            // ---- SKINS
            GArray ids = GArray.Of("");
            ids.AppendArray(Eco.SkinsOf(hero));
            var mine = 1 + Eco.SkinsOf(hero).Filter(id => p.OwnsSkin(GD.Str(id))).Size();
            var others = ids.Size() - mine;
            if (owned_only)                                   // 0.31.204: the Armory's -- only what you own
            {
                ids = ids.Filter(id => GD.Str(id) == "" || p.OwnsSkin(GD.Str(id)));
                _Head(_sheet, "OUTFITS", GD.Fmt("%d yours  ·  tap one to wear it", mine), acc);
            }
            else
                _Head(_sheet, "OUTFITS", GD.Fmt("%d of %d yours  ·  tap one to try it on", mine, ids.Size()), acc);      // (0.31.188: whole outfits, weapon and all)
            var hs = new ScrollContainer();
            hs.VerticalScrollMode = ScrollContainer.SCROLL_MODE_DISABLED;
            hs.CustomMinimumSize = new Vector2(0, 124);
            _sheet.AddChild(hs);
            var strip = new HBoxContainer();
            strip.AddThemeConstantOverride("separation", 8);
            hs.AddChild(strip);
            foreach (var id0 in ids)
                _SkinTile(strip, GD.Str(id0), acc);
            _SkinAction(acc);
            if (owned_only && others > 0)
            {
                var mk = UI2.Button(_sheet, GD.Fmt("%d MORE OUTFIT%s IN THE MARKET  ▸", others, others == 1 ? "" : "S"), "purple", () =>
                {
                    app.Sfx("tab");
                    app.OpenMarket("outfits");
                }, "champ_more_market", 13, 36.0, 11.0, "res://assets/ui/v2/icons/stall.png");
                mk.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
            }
            // ---- the story
            _Head(_sheet, "THE STORY", "", acc);
            var lore = UI2.Body(_sheet, GD.Str(ch.Get("lore", "")), 12, new Color("#efe6d6"));
            var lm = lore.CustomMinimumSize;
            lm.x = 10;
            lore.CustomMinimumSize = lm;
            var q = UI.Label(_sheet, GD.Fmt("“%s”", GD.Str(ch.Get("quote", ""))), 14, acc.Lightened(0.45), UI.LORE_FONT, true);
            q.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            q.HorizontalAlignment = HorizontalAlignment.Center;
            q.AddThemeColorOverride("font_outline_color", new Color(0, 0, 0, 0.85));
            q.AddThemeConstantOverride("outline_size", 4);
            // ---- the kit
            _Head(_sheet, "ABILITIES", GD.Str(Kits.ROLE_TEXT.GetValueOrDefault(Kits.RoleOf(hero), "")), acc);
            var lines = MobaPanel.KitLines(hero);
            var slots = new[] { "q", "w", "e", "r" };
            for (int i = 0; i < 4; i++)
                _KitRow(slots[i], GD.Str(lines[i + 1]), acc);
            var pad = new Control();
            pad.CustomMinimumSize = new Vector2(0, 8);
            _sheet.AddChild(pad);
            _scroll.CallDeferred(() => _scroll.ScrollVertical = keep);
        }

        public void _Head(Node parent, string title, string sub, Color acc)
        {
            var r = UI.Row(parent, 8);
            var bar = new ColorRect();
            bar.Color = acc;
            bar.CustomMinimumSize = new Vector2(4, 18);
            bar.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            r.AddChild(bar);
            var t = UI2.Text(r, title, 16, UI2.GOLD, UI2.INK, 4);
            t.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            if (sub != "")
            {
                var s = UI2.Body(r, sub, 10, UI2.SOFT, true);
                s.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                s.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                var sm = s.CustomMinimumSize;
                sm.x = 10;
                s.CustomMinimumSize = sm;
            }
        }

        public void _SkinTile(Node parent, string id, Color acc)
        {
            var p = app.profile;
            var b = new Button();
            b.Flat = true;
            b.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus" })
                b.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            b.CustomMinimumSize = new Vector2(92, 118);
            b.SetMeta("action_key", "champ_skin_" + (id != "" ? id : "default"));
            b.Pressed += () =>
            {
                preview = id;
                app.Sfx("tap");
                _ShowLook();
                _Render();
            };
            parent.AddChild(b);
            var on = preview == id;
            if (on)
                UI2.Skin(b, UI2.ButtonParams("gold", 14.0, 3.0).Merged(GDict.Of("glow", 7.0, "glow_color", new Color(acc.Lightened(0.3), 0.8)), true));
            else
            {
                var rar = id == "" ? "common" : GD.Str(Eco.SKINS[id]["rarity"]);
                UI2.Plate(b, id == "" ? "night" : (rar == "epic" ? "purple" : (rar == "legendary" ? "ember" : "royal")), 14.0,
                    id == "" ? "silver" : "purple", GDict.Of("rim", 2.0, "dim", 0.1));
            }
            var path = id != "" ? GD.Fmt("res://assets/ui/skins/%s.png", id) : MobaPanel.Portrait(hero);
            var ti = new TextureRect();
            ti.Texture = ResourceLoader.Exists(path) ? ResourceLoader.Load<Texture2D>(path) : null;
            ti.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            ti.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            ti.Position = new Vector2(8, 6);
            ti.Size = new Vector2(76, 76);
            ti.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.AddChild(ti);
            var label = id == "" ? "DEFAULT" : GD.Str(Eco.SKINS[id]["set"]).ToUpperInvariant();
            var l = UI2.Text(b, label, 11, Color.WHITE, UI2.INK, 4);
            l.HorizontalAlignment = HorizontalAlignment.Center;
            l.Position = new Vector2(0, 80);
            l.Size = new Vector2(92, 16);
            bool worn = p.WornSkin(hero) == id;
            var state = "";
            if (worn)
                state = "WORN";
            else if (id == "" || p.OwnsSkin(id))
                state = "OWNED";
            Label sl;
            if (state != "")
                sl = UI2.Text(b, state, 10, worn ? new Color("#9dff8a") : new Color("#cfe9ff"), new Color(0, 0, 0, 0.8), 3);
            else
            {
                var o = Eco.SkinOffer(id, p.Now());                 // 0.31.203: the weekly sale's price, and its cut
                sl = UI2.Text(b, (int)o["off"] > 0 ? GD.Fmt("◆ %d  -%d%%", (int)o["gems"], (int)o["off"]) : GD.Fmt("◆ %d", (int)o["gems"]), 11,
                    (int)o["off"] > 0 ? new Color("#ffd2c4") : new Color("#e8ccff"), (int)o["off"] > 0 ? new Color("#4a0306") : new Color("#1e0a45"), 3);
            }
            sl.HorizontalAlignment = HorizontalAlignment.Center;
            sl.Position = new Vector2(0, 97);
            sl.Size = new Vector2(92, 14);
        }

        public void _SkinAction(Color acc)
        {
            // under the strip: the shown skin's name and what you can do with it
            var p = app.profile;
            var r = UI.Row(_sheet, 8);
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 0);
            v.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            v.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            r.AddChild(v);
            var nm = Champions.ShortOf(hero) + (preview == "" ? "  ·  original" : "");
            if (preview != "")
                nm = GD.Str(Eco.SKINS[preview]["name"]);
            UI2.Text(v, nm.ToUpperInvariant(), 14, Color.WHITE, UI2.INK, 4);
            if (preview != "")
            {
                var rar = GD.Str(Eco.SKINS[preview]["rarity"]);
                var what = Eco.SKINS[preview].Has("weapon") ? "a new look and its own weapon" : "a new look, the weapon repainted to match";
                UI2.Body(v, rar.ToUpperInvariant() + " OUTFIT  ·  " + (p.OwnsSkin(preview) ? "yours" : (!p.OwnsHero(hero) ? GD.Fmt("%s comes with it", Champions.ShortOf(hero)) : what)),
                    10, Color.FromCode(GD.Str(Eco.RARITY_COLOR.Get(rar, "#b8c4c9"))).Lightened(0.3), false);
            }
            else
                UI2.Body(v, "DEFAULT  ·  the original look", 10, UI2.SOFT, false);
            Button b;
            bool worn = p.WornSkin(hero) == preview;
            if (preview == "" || p.OwnsSkin(preview))
            {
                b = UI2.Button(r, worn ? "WORN" : "WEAR", worn ? "grey" : "blue", () =>
                {
                    p.WearSkin(hero, preview);
                    app.Sfx("equip");
                    app.Toast(GD.Fmt("%s wears %s", Champions.ShortOf(hero), preview == "" ? "the original look" : GD.Str(Eco.SKINS[preview]["name"])), UI.CYAN);
                    _Render();
                }, "champ_wear", 15, 42.0, 12.0);
                b.Disabled = worn;
            }
            else
            {
                var o = Eco.SkinOffer(preview, p.Now());             // 0.31.203: the weekly sale's price when it's on it
                var gems = (int)o["gems"];
                var gold = (int)o["gold"];
                b = UI2.Button(r, UI.Grouped(gems), "purple", _AskBuy, "champ_buy", 16, 42.0, 12.0, GEM);
                b.Disabled = (int)p.d["gems"] < gems && (gold <= 0 || (int)p.d["gold"] < gold);      // (0.31.189: or the gold)
                if ((int)o["off"] > 0)
                    UI2.Body(v, GD.Fmt("WEEKLY SALE  -%d%%  ·  was %s gems", (int)o["off"], UI.Grouped((int)o["was_gems"])), 10, new Color("#ff9c8a"), false);
                if (gold > 0)
                    UI2.Body(v, GD.Fmt("or %s gold", UI.Grouped(gold)), 10, new Color("#ffd86b"), false);
            }
            var bm = b.CustomMinimumSize;
            bm.x = 112;
            b.CustomMinimumSize = bm;
            b.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
        }

        public void _KitRow(string slot, string line, Color acc)
        {
            var row = new HBoxContainer();
            row.AddThemeConstantOverride("separation", 8);
            row.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            _sheet.AddChild(row);
            var ic = new TextureRect();
            ic.Texture = Hud.AbilityIcon(hero, slot);
            ic.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            ic.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            ic.CustomMinimumSize = new Vector2(38, 38);
            ic.SizeFlagsVertical = Control.SIZE_SHRINK_BEGIN;
            ic.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            row.AddChild(ic);
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 0);
            v.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            row.AddChild(v);
            // "Q BOULDER: ..." / "W STONESKIN (lv 2): ..." -> the name, then what it does
            var cut = line.Find(": ");
            var name = cut > 0 ? line.Substr(0, cut) : line;
            var what = cut > 0 ? line.Substr(cut + 2) : "";
            UI2.Text(v, name, 13, acc.Lightened(0.5), UI2.INK, 4);
            var w = UI2.Body(v, what, 11, new Color("#e8e2d6"));
            var wm = w.CustomMinimumSize;
            wm.x = 10;
            w.CustomMinimumSize = wm;
        }

        // ---------------- PLAY, UNLOCK and BUY ----------------
        public void _Play()
        {
            // (the 5v5 window with him picked)
            app.profile.d["settings"].D["moba_hero"] = hero;
            app.profile.Save();
            app.Sfx("confirm");
            app.OpenMoba();
        }

        public VBoxContainer _Overlay(string title, string sub)
        {
            CloseOverlay();
            app.Sfx("menuOpen");
            overlay = new ColorRect();
            (overlay as ColorRect).Color = new Color(0, 0, 0, 0.62);
            overlay.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            overlay.MouseFilter = Control.MOUSE_FILTER_STOP;
            AddChild(overlay);
            var cc = new CenterContainer();
            cc.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            overlay.AddChild(cc);
            var box = UI2.Frame(cc, "night", 14, 18.0, "gold");
            (box.GetParent() as Control).CustomMinimumSize = new Vector2(300, 0);
            box.AddThemeConstantOverride("separation", 8);
            var t = UI2.Center(UI2.Text(box, title, 21, UI2.GOLD));
            t.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            var tm = t.CustomMinimumSize;
            tm.x = 260;
            t.CustomMinimumSize = tm;
            var s = UI2.Center(UI2.Body(box, sub, 11, UI2.SOFT));
            var sm = s.CustomMinimumSize;
            sm.x = 260;
            s.CustomMinimumSize = sm;
            return box;
        }

        public void CloseOverlay()
        {
            if (GD.IsInstanceValid(overlay))
                overlay.QueueFree();
            overlay = null;
        }

        public void OpenChooser()
        {
            // UNLOCK <NAME>: each way to unlock him (the 5v5 window's chooser), those you can't pay dimmed; CANCEL
            var p = app.profile;
            GDict pr = p.HeroPrice(hero);
            if (pr.IsEmpty() || p.OwnsHero(hero))
                return;
            var box = _Overlay("UNLOCK " + Champions.NameOf(hero).ToUpperInvariant(), GD.Fmt("The %s, yours for good.%s", GD.Str(Moba.HEROES[hero].name),
                Eco.Launching(hero, p.Now()) ? "  Launch price for now." : ""));
            var opts = GArray.Of(GArray.Of(GD.Fmt("%s GOLD", UI.Grouped((int)pr["gold"])), "gold", COIN, "champ_unlock_gold", (int)p.d["gold"] >= (int)pr["gold"], "gold"),
                GArray.Of(GD.Fmt("%s GEMS", UI.Grouped((int)pr["gems"])), "blue", GEM, "champ_unlock_gems", (int)p.d["gems"] >= (int)pr["gems"], "gems"));
            if (p.ShardsOf(hero) > 0)
            {
                var sg = Eco.ShardUnlockGold(hero, p.Now());
                opts.Append(GArray.Of(GD.Fmt("SHARD + %s GOLD", UI.Grouped(sg)), "green", COIN, "champ_unlock_shard", (int)p.d["gold"] >= sg, "shard"));
            }
            if ((int)p.d.Get("tokens", 0) > 0)
                opts.Append(GArray.Of("HERO TOKEN", "purple", "", "champ_unlock_token", true, "token"));
            foreach (var o in opts)
            {
                string how = GD.Str(o[5]);
                var b = UI2.Button(box, GD.Str(o[0]), GD.Str(o[1]), () => _UnlockBy(how), GD.Str(o[3]), 17, 46.0, 14.0, GD.Str(o[2]));
                b.Disabled = !(bool)o[4];
            }
            UI2.Button(box, "CANCEL", "grey", () =>
            {
                app.Sfx("menuClose");
                CloseOverlay();
            }, "champ_cancel", 15, 40.0, 12.0);
        }

        public void _UnlockBy(string how)
        {
            var p = app.profile;
            GDict r;
            switch (how)
            {
                case "gold":
                    r = p.BuyHero(hero);
                    break;
                case "gems":
                    r = p.BuyHeroGems(hero);
                    break;
                case "shard":
                    r = p.UseShard(hero);
                    break;
                default:
                    r = p.UseToken(hero);
                    break;
            }
            if ((bool)r.Get("ok", false))
            {
                app.Sfx("purchase");
                app.Toast(GD.Fmt("%s joins you!", Champions.NameOf(hero)), UI2.GOLD);
                CloseOverlay();
                app.RefreshTop();
                app.Rebuild();                           // (the Locker under the window -- and refresh() here)
            }
            else
            {
                app.Sfx("error");
                app.Toast(GD.Str(r.Get("error", "Can't unlock")), new Color("#ff8a7a"));
            }
        }

        public void _AskBuy()
        {
            var p = app.profile;
            var id = preview;
            if (id == "" || p.OwnsSkin(id))
                return;
            GDict sk = Eco.SKINS[id].D;
            var o = Eco.SkinOffer(id, p.Now());                     // 0.31.203: at the weekly sale's price when it's on it
            var gems = (int)o["gems"];
            var gold = (int)o["gold"];
            bool with_hero = !p.OwnsHero(hero);
            var box = _Overlay(GD.Fmt("BUY %s?", GD.Str(sk["name"]).ToUpperInvariant()), GD.Fmt("%s%s gems%s. Worn at once.%s",
                (int)o["off"] > 0 ? GD.Fmt("Weekly sale: %d%% off. ", (int)o["off"]) : "", UI.Grouped(gems),
                gold > 0 ? GD.Fmt(" or %s gold", UI.Grouped(gold)) : "",
                with_hero ? GD.Fmt(" %s comes with it -- the %s is yours too.", Champions.ShortOf(hero), GD.Str(Moba.HEROES[hero].name)) : ""));
            Action<GDict> done = (GDict r) =>
            {
                if ((bool)r.Get("ok", false))
                {
                    app.Sfx("purchase");
                    app.Toast(GD.Fmt("%s is yours%s", GD.Str(sk["name"]), (bool)r.Get("hero", false) ? GD.Fmt(" -- and %s", Champions.ShortOf(hero)) : ""), UI.GOLD);
                    CloseOverlay();
                    app.RefreshTop();
                    app.Rebuild();
                }
                else
                {
                    app.Sfx("error");
                    app.Toast(GD.Str(r.Get("error", "Can't buy")), UI.RED);
                }
            };
            var bg = UI2.Button(box, GD.Fmt("BUY  %s", UI.Grouped(gems)), "purple", () => done(p.BuyOutfit(id, false)), "champ_buy_yes", 17, 46.0, 14.0, GEM);
            bg.Disabled = (int)p.d["gems"] < gems;
            if (gold > 0)                                       // 0.31.189 (Kevin: "Frostbound for gold")
            {
                var bo = UI2.Button(box, GD.Fmt("BUY  %s", UI.Grouped(gold)), "gold", () => done(p.BuyOutfit(id, true)), "champ_buy_gold", 17, 46.0, 14.0, COIN);
                bo.Disabled = (int)p.d["gold"] < gold;
            }
            UI2.Button(box, "CANCEL", "grey", () =>
            {
                app.Sfx("menuClose");
                CloseOverlay();
            }, "champ_cancel", 15, 40.0, 12.0);
        }
    }
}
