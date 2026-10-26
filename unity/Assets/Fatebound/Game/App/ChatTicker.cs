// Ported from godot/scripts/app/chat_ticker.gd (Fatebound 0.31.222).
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
    // 0.31.111 (Kevin: "Build a global chat"): the chat line over the tab bar on Home -- the newest global line (or what
    // the chat is doing), an unread count, and a tap opens the chat. It follows scripts/meta/social.gd as lines arrive.
    public class ChatTicker : Control
    {
        public const double BAR = 42.0;
        // 0.31.122 (Kevin: "The icons at bottom block chat"): the open tab's raised tile and its bobbing icon stood up to ~18 px
        // over the tab bar, so the chat line sat 22 px above it; 0.31.216 (landscape) the tabs are on a rail at the left, so the
        // line sits just over the screen's bottom edge (clear of the gesture bar)
        public const double GAP = 8.0;
        public const double H = BAR + GAP;
        public SiegeApp app;
        public Label _name;
        public Label _text;
        public PanelContainer _badge;
        public Label _badge_l;

        public void Setup(SiegeApp a)
        {
            app = a;
            CustomMinimumSize = new Vector2(0, H);
            var bg = new Panel();
            var sb = new StyleBoxFlat();
            sb.BgColor = new Color(0.02, 0.04, 0.12, 0.9);
            sb.BorderColor = new Color("#b9761b");
            sb.SetBorderWidthAll(2);                 // (0.31.122: a whole rounded bar now it stands clear of the tab bar)
            sb.SetCornerRadiusAll(14);
            sb.ShadowColor = new Color(0, 0, 0, 0.35);
            sb.ShadowSize = 4;
            sb.ShadowOffset = new Vector2(0, 2);
            bg.AddThemeStyleboxOverride("panel", sb);
            bg.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            bg.OffsetLeft = 6;
            bg.OffsetRight = -6;
            bg.OffsetBottom = -GAP;
            bg.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(bg);
            var r = new HBoxContainer();
            r.AddThemeConstantOverride("separation", 8);
            r.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            r.OffsetLeft = 14;
            r.OffsetRight = -14;
            r.OffsetTop = 3;
            r.OffsetBottom = -GAP;
            r.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(r);
            UI2.Icon(r, "chat", 32.0).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            _name = UI.Label(r, "", 14, UI2.GOLD, UI.HEAVY_FONT);
            _name.AutowrapMode = TextServer.AUTOWRAP_OFF;
            _name.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            _text = UI.Label(r, "", 14, Color.WHITE, UI.BODY_FONT);
            _text.AutowrapMode = TextServer.AUTOWRAP_OFF;
            _text.ClipText = true;
            _text.TextOverrunBehavior = TextServer.OVERRUN_TRIM_ELLIPSIS;
            _text.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            _text.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            _badge = new PanelContainer();
            var bs = new StyleBoxFlat();
            bs.BgColor = new Color("#e8443a");
            bs.BorderColor = new Color("#3a0805");
            bs.SetBorderWidthAll(2);
            bs.SetCornerRadiusAll(11);
            bs.ContentMarginLeft = 6;
            bs.ContentMarginRight = 6;
            _badge.AddThemeStyleboxOverride("panel", bs);
            _badge.CustomMinimumSize = new Vector2(24, 22);
            _badge.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            _badge.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            r.AddChild(_badge);
            _badge_l = UI.Label(_badge, "", 12, Color.WHITE, UI.HEAVY_FONT);
            _badge_l.AutowrapMode = TextServer.AUTOWRAP_OFF;
            _badge_l.HorizontalAlignment = HorizontalAlignment.Center;
            var go = UI2.Text(r, "›", 26, UI2.GOLD);
            go.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            var hit = new Button();
            hit.Flat = true;
            hit.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus", "hover_pressed" })
                hit.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            hit.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            hit.OffsetBottom = -GAP;
            hit.SetMeta("action_key", "chat_ticker");
            hit.Pressed += () =>
            {
                app.Sfx("menuOpen");
                app.OpenChat(app.social.unread["party"] > 0 || !app.social.show_global ? "party" : "global");
            };
            AddChild(hit);
            app.social.Changed += _Refresh;
            _Refresh();
        }

        public void _Refresh(string _what = "")
        {
            var s = app.social;
            int n = s.UnreadTotal();
            _badge.Visible = n > 0;
            _badge_l.Text = n < 100 ? GD.Str(n) : "99+";
            GArray lines = s.show_global ? s.lines.Get("global", new GArray()).A : s.lines.Get("party", new GArray()).A;
            var last = new GDict();
            for (int i = lines.Size() - 1; i > -1; i--)
            {
                if (!(bool)lines[i].Get("sys", false))
                {
                    last = lines[i].D;
                    break;
                }
            }
            if (s.Online() && !last.IsEmpty())
            {
                _name.Text = GD.Str(last.Get("n", "")) + ":";
                _text.Text = GD.Str(last.Get("x", ""));
                _text.Modulate = Color.WHITE;
                return;
            }
            _name.Text = s.show_global ? "CHAT" : "PARTY CHAT";
            _text.Modulate = new Color(0.75, 0.8, 0.92);
            switch (GD.Str(s.state))
            {
                case "online": _text.Text = s.show_global ? "Say hi to everyone online!" : "Global chat is off"; break;
                case "connecting": _text.Text = "Connecting..."; break;
                case "old": _text.Text = "Arrives with the next server update"; break;
                default: _text.Text = !s.HasAccount() ? "Connects when you're online" : "Reconnecting..."; break;
            }
        }
    }
}
