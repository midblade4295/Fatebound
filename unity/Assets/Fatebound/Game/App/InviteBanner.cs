// Ported from godot/scripts/app/invite_banner.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;
using UI = Fatebound.Game.Ui;
using UI2 = Fatebound.Game.Ui2;

namespace Fatebound.Game
{
    // 0.31.111 (Kevin: "They can then group up and form a party"): a party invite drops in under the top bar -- who, JOIN
    // and ✕ -- for as long as it lasts (social.gd INVITE_LIFE), then slides away.
    public class InviteBanner : PanelContainer
    {
        public SiegeApp app;
        public string party = "";
        public double _until = 0.0;

        public void ShowInvite(SiegeApp a, string pa, GDict card, double top)
        {
            app = a;
            party = pa;
            _until = Time.GetTicksMsec() / 1000.0 + 30.0;
            _Frame(new Color("#f7cd55"), top);
            var r = UI.Row(this, 8);
            UI2.Icon(r, "friends", 40.0).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 0);
            v.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            r.AddChild(v);
            var n = UI2.Text(v, GD.Str(card.Get("n", "A friend")), 16, UI2.GOLD);
            n.ClipText = true;
            n.TextOverrunBehavior = TextServer.OVERRUN_TRIM_ELLIPSIS;
            UI2.Body(v, "invited you to their party", 12, Color.WHITE, false);
            var j = UI2.Button(r, "JOIN", "green", () =>
            {
                app.Sfx("confirm");
                if (!app.social.Join(party))
                    app.Toast("Not connected to the server right now", UI.RED);
                QueueFree();
            }, "invite_banner_join", 15, 40.0, 12.0);
            var jm = j.CustomMinimumSize;
            jm.x = 76;
            j.CustomMinimumSize = jm;
            j.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            var x = UI2.Button(r, "✕", "ghost", () =>
            {
                app.Sfx("menuClose");
                app.social.NoJoin(party);
                QueueFree();
            }, "invite_banner_no", 15, 40.0, 12.0);
            var xm = x.CustomMinimumSize;
            xm.x = 44;
            x.CustomMinimumSize = xm;
            x.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            _DropIn(top);
        }

        public void _Frame(Color border, double top)
        {
            var sb = new StyleBoxFlat();
            sb.BgColor = new Color(0.05, 0.08, 0.2, 0.96);
            sb.BorderColor = border;
            sb.SetBorderWidthAll(2);
            sb.SetCornerRadiusAll(16);
            sb.ContentMarginLeft = 10;
            sb.ContentMarginRight = 10;
            sb.ContentMarginTop = 6;
            sb.ContentMarginBottom = 6;
            sb.ShadowColor = new Color(0, 0, 0, 0.5);
            sb.ShadowSize = 8;
            AddThemeStyleboxOverride("panel", sb);
            AnchorLeft = 0.0;
            AnchorRight = 1.0;
            OffsetLeft = 10;
            OffsetRight = -10;
            OffsetTop = top;
        }

        public void _DropIn(double top)
        {
            var m = Modulate;
            m.a = 0.0f;
            Modulate = m;
            var p = Position;
            p.y = (float)(top - 20.0);
            Position = p;
            var tw = CreateTween().SetParallel();
            tw.TweenProperty(this, "modulate:a", 1.0, 0.2);
            tw.TweenProperty(this, "position:y", top, 0.25).SetTrans(Tween.TRANS_BACK).SetEase(Tween.EASE_OUT);
        }

        protected override void _Process(double _delta)
        {
            if (Time.GetTicksMsec() / 1000.0 > _until || (app != null && party != "" && !app.social.invites.Has(party))
                    || (app != null && app.siege != null))
            {
                SetProcess(false);
                var tw = CreateTween();
                tw.TweenProperty(this, "modulate:a", 0.0, 0.25);
                tw.TweenCallback(QueueFree);
            }
        }
    }
}
