// Ported from godot/scripts/app/orders_panel.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;
using UI = Fatebound.Game.Ui;
using UI2 = Fatebound.Game.Ui2;
using Eco = Fatebound.Game.Economy;
using SocialUI = Fatebound.Game.SocialUi;

namespace Fatebound.Game
{
    // 0.31.112 (Kevin: "for home screen I don't want it to scroll down, just have the chests at bottom and move the orders and
    // stuff to its own popup menu"): the ORDERS window from Home's ORDERS medallion -- the daily and weekly orders (CLAIM,
    // reroll), the Siege Pass summary and what's inside each chest. Redrawn after every claim (siege_app.rebuild calls
    // refresh), keeping its scroll.
    public class OrdersPanel : Control
    {
        public SiegeApp app;
        public VBoxContainer _list;
        public ScrollContainer _scroll;

        public void Open(SiegeApp a)
        {
            app = a;
            var w = SocialUI.Window(this, "ORDERS", "scroll", () =>
            {
                app.Sfx("menuClose");
                app.CloseModal();
            }, 56.0 + (double)app.safe_top, 24.0);
            _scroll = new ScrollContainer();
            _scroll.SizeFlagsVertical = Control.SIZE_EXPAND_FILL;
            _scroll.HorizontalScrollMode = ScrollContainer.SCROLL_MODE_DISABLED;
            _scroll.ScrollDeadzone = 1000000;                 // (drag-scrolled by the app, like the menus)
            w["body"].As<VBoxContainer>().AddChild(_scroll);
            SetMeta("drag_scroll", _scroll);
            _list = new VBoxContainer();
            _list.AddThemeConstantOverride("separation", 12);
            _list.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            _scroll.AddChild(_list);
            _Render();
        }

        public void Refresh()
        {
            var keep = _scroll.ScrollVertical;
            _Render();
            _scroll.CallDeferred(() => _scroll.ScrollVertical = keep);
        }

        public void _Render()
        {
            foreach (var c in _list.GetChildren())
            {
                _list.RemoveChild(c);
                c.QueueFree();
            }
            _DailyCard(_list);
            Screens.ChallengesCard(app, _list, "daily");
            Screens.ChallengesCard(app, _list, "weekly");
            Screens.PassCard(app, _list);
            // what's inside the chests (was a button on Home)
            var f = UI2.Frame(_list, "night", 12, 16.0, "gold");
            f.AddThemeConstantOverride("separation", 6);
            UI2.Text(f, "WHAT'S INSIDE THE CHESTS", 17, UI2.GOLD);
            foreach (var k in new[] { "wooden", "silver", "gold", "royal" })
            {
                var r = UI.Row(f, 8);
                var n = UI2.Text(r, GD.Str(Eco.CHESTS[k]["name"]).ToUpperInvariant(), 13, Color.WHITE);
                var nm = n.CustomMinimumSize;
                nm.x = 104;
                n.CustomMinimumSize = nm;
                n.SizeFlagsVertical = Control.SIZE_SHRINK_BEGIN;
                var b = UI2.Body(r, GD.Fmt("%s to unlock  ·  %s", UI.Duration((int)Eco.CHESTS[k]["unlock"]), Eco.ChestOdds(k)), 11, UI2.SOFT);
                b.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            }
        }

        public void _DailyCard(Node parent)
        {
            // 0.31.119: the daily login reward -- today's (CLAIM) or when the next one is ready; the card opens the calendar
            var p = app.profile;
            bool ready = p.LoginReady();
            int nxt = p.LoginNext();
            var f = UI2.Frame(parent, ready ? "ember" : "night", 10, 16.0, ready ? "orange" : "gold", GDict.Of("pattern_mix", 0.0));
            f.Name = "DailyCard";
            var r = UI.Row(f, 10);
            UI2.Img(r, UI2.V2 + "chests/gold_icon.png", 46.0).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            var col = new VBoxContainer();
            col.AddThemeConstantOverride("separation", 0);
            col.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            r.AddChild(col);
            UI2.Text(col, "DAILY REWARD", 17, UI2.GOLD);
            var parts = new GArray();
            foreach (var it in DailyReward.RewardText(Eco.LOGIN_REWARDS[nxt].D))
                parts.Append(GD.Str(it[1]));
            UI2.Body(col, ready ? GD.Fmt("Day %d of 7 ready: %s", nxt + 1, GStr.Join(" + ", parts)) : GD.Fmt("Claimed today -- day %d tomorrow", nxt + 1), 12, Color.WHITE);
            var b = UI2.Button(r, ready ? "CLAIM" : "VIEW", ready ? "green" : "blue", () =>
            {
                app.Sfx("menuOpen");
                app.OpenDaily();
            }, "orders_daily", 15, 40.0, 12.0);
            var bm = b.CustomMinimumSize;
            bm.x = 86;
            b.CustomMinimumSize = bm;
            b.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            if (ready)
                UI2.Sweep(b);
        }
    }
}
