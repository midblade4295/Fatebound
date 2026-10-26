// Ported from godot/scripts/app/starter_offer.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;
using UI = Fatebound.Game.Ui;
using UI2 = Fatebound.Game.Ui2;
using Net = Fatebound.Game.SiegeNet;
using Platform = Fatebound.Game.Platform;

namespace Fatebound.Game
{
    // 0.31.214 (Kevin: "Show the starter pack on the front page and make sure it's eye-catching and has pretty graphics that
    // doesn't look like AI made it"): the STARTER PACK window, from Home's offer card. Its picture big (the 3D render,
    // tools/render_starter_pack.gd) in a warm card with light turning behind it, sparkles and a breathing glow; what's in it
    // -- the gems, the gold and a Hero Token (any locked hero), each with its own icon; ONE-TIME OFFER; the price on a
    // shining button (the store's purchase, as the Shop's: Screens._iap_button's rules -- live price, "PLAY STORE" /
    // "APP STORE" where the store isn't there). It closes itself once the pack is bought.
    public class StarterOffer : Control
    {
        public SiegeApp app;

        public void Open(SiegeApp a)
        {
            app = a;
            SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            var dim = new ColorRect();
            dim.Color = new Color(0.01, 0.02, 0.06, 0.8);
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            dim.GuiInput += (InputEvent ev) =>
            {
                if (ev is InputEventMouseButton && (ev as InputEventMouseButton).Pressed)
                    _Close();
            };
            AddChild(dim);
            var center = new CenterContainer();
            center.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            center.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(center);
            var holder = new MarginContainer();
            // 0.31.216 (landscape): the picture on the left, what's in it and the price on the right (one column in portrait)
            var cw = GD.Minf(660.0, app.Size.x - 40.0);
            holder.CustomMinimumSize = new Vector2(cw, 0);
            center.AddChild(holder);
            var v = UI2.Frame(holder, "ember", 14, 22.0, "gold");
            v.AddThemeConstantOverride("separation", 10);
            // the head: the name, ✕
            var head = UI.Row(v, 8);
            var tl = UI2.Text(head, "STARTER PACK", 26, UI2.GOLD);
            tl.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            tl.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            var x = UI2.Button(head, "✕", "ghost", () => _Close(), "starter_close", 18, 40.0, 12.0);
            var xm = x.CustomMinimumSize;
            xm.x = 44;
            x.CustomMinimumSize = xm;
            var cols = new HBoxContainer();
            cols.AddThemeConstantOverride("separation", 16);
            v.AddChild(cols);
            // the picture
            var aw = Math.Round(GD.Minf(300.0, cw * 0.46), MidpointRounding.AwayFromZero);
            var ah = Math.Round(aw * 0.81, MidpointRounding.AwayFromZero);
            var stage = new Control();
            stage.CustomMinimumSize = new Vector2(aw, ah);
            stage.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            stage.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            cols.AddChild(stage);
            var side = new VBoxContainer();
            side.AddThemeConstantOverride("separation", 10);
            side.Alignment = BoxContainer.ALIGNMENT_CENTER;
            side.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            cols.AddChild(side);
            var well = new Control();                      // (a dark well the light turns in)
            well.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            well.ClipContents = true;
            well.Position = new Vector2(0, 0);
            well.Size = new Vector2(aw, ah);
            stage.AddChild(well);
            UI2.Plate(well, "night", 18.0, "orange", GDict.Of("fill_top", new Color("#5a2208"), "fill_bottom", new Color("#140602")));
            var ry = UI2.Rays(well, aw * 1.5, new Color(1.0, 0.82, 0.45), 26.0, 0.55);
            ry.Position = new Vector2(aw * 0.5, ah * 0.45) - ry.Size * 0.5;
            UI2.Glow(well, new Rect2(aw * 0.1, ah * 0.05, aw * 0.8, ah * 0.85), new Color(1.0, 0.7, 0.3, 0.55));
            var art = new TextureRect();
            art.Texture = UI2.Tex(Screens.STARTER_ART);
            art.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            art.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            art.TextureFilter = TextureFilterMode.LinearWithMipmaps;
            art.Position = new Vector2(aw * 0.04, ah * 0.03);
            art.Size = new Vector2(aw * 0.92, ah * 0.94);
            art.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            stage.AddChild(art);
            UI2.Bob(art, 4.0, 1.7);
            var tw_box = new Control();
            tw_box.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            tw_box.Size = new Vector2(aw, ah);
            stage.AddChild(tw_box);
            Screens._Twinkles(tw_box, 7, new Color(1.0, 0.95, 0.78), new Rect2(0.15, 0.2, 0.7, 0.6), 26.0);
            var once = UI2.Chip(stage, "ONE-TIME OFFER", new Color("#e8443a"), Color.WHITE, new Color("#3a0805"));
            once.Position = new Vector2(10, 10);
            once.Rotation = GD.DegToRad(-6.0);
            // what's in it
            GDict sp = Net.IAP["starter_pack"].D;
            var items = new HBoxContainer();
            items.AddThemeConstantOverride("separation", 8);
            items.Alignment = BoxContainer.ALIGNMENT_CENTER;
            side.AddChild(items);
            // (the three in the picture's own light: tools/render_starter_pack.gd SHOT=gems | gold | token)
            _Item(items, UI2.V2 + "offer/gems.webp", GD.Fmt("%d", (int)sp["gems"]), "GEMS", new Color("#8fd0ff"));
            _Item(items, UI2.V2 + "offer/gold.webp", UI.Grouped((int)sp.Get("gold", 0)), "GOLD", UI2.GOLD);
            _Item(items, UI2.V2 + "offer/token.webp", "HERO", "TOKEN", new Color("#e2b8ff"));
            UI2.Center(UI2.Body(side, "A Hero Token unlocks any hero you don't have yet. Once per player.", 12, new Color("#ffe9c7")));
            // the price
            var bl = app.billing;
            bool live = bl != null && bl.Active();
            var label = Platform.StoreButton();
            if (live)
                label = GD.Str(bl.busy) == "starter_pack" ? "…" : GD.Str(bl.Price("starter_pack"));
            var b = UI2.Button(side, label, live ? "green" : "grey", () =>
            {
                app.Sfx("tap");
                if (bl != null)
                    bl.Buy("starter_pack");
                else
                    app.Toast(GD.Fmt("Gem packs are sold in the %s version of Fatebound", Platform.StoreShort()), UI.RED);
            }, "starter_buy", 22, 56.0, 16.0);
            b.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            if (live)
                b.Disabled = !bl.CanBuy("starter_pack");
            UI2.Sweep(b);
        }

        public void _Item(Node parent, string icon, string big, string small, Color col)
        {
            var c = new VBoxContainer();
            c.AddThemeConstantOverride("separation", 0);
            c.CustomMinimumSize = new Vector2(96, 0);
            c.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(c);
            var box = new Control();
            box.CustomMinimumSize = new Vector2(96, 88);
            box.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            c.AddChild(box);
            UI2.Plate(box, "night", 14.0, "gold", GDict.Of("fill_top", new Color("#3a1a0a"), "fill_bottom", new Color("#150803")));
            var ic = UI2.Img(box, icon, 50.0);
            ic.Position = new Vector2(23, 3);
            UI2.Bob(ic, 2.0, 1.5, GD.Randf() * 0.8);
            var n = UI2.Text(box, big, 18, Color.WHITE, UI2.INK, 4);
            n.HorizontalAlignment = HorizontalAlignment.Center;
            n.Position = new Vector2(0, 50);
            n.Size = new Vector2(96, 20);
            var s = UI2.Text(box, small, 11, col, UI2.INK, 3);
            s.HorizontalAlignment = HorizontalAlignment.Center;
            s.Position = new Vector2(0, 68);
            s.Size = new Vector2(96, 14);
        }

        protected override void _Process(double _d)
        {
            if (app != null && app.profile != null && (bool)app.profile.d["iap"]["starter"])
                app.CloseModal();                          // (bought: the window goes, Home's card with it -- the app rebuilds)
        }

        public void _Close()
        {
            app.Sfx("menuClose");
            app.CloseModal();
        }
    }
}
