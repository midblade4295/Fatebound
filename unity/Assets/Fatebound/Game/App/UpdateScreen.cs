// Ported from godot/scripts/app/update_screen.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;
using UI = Fatebound.Game.Ui;
using Net = Fatebound.Game.SiegeNet;
using Diag = Fatebound.Game.SiegeDiag;
using Platform = Fatebound.Game.Platform;

namespace Fatebound.Game
{
    // "Update required" (0.31.73). Shown over everything when the Siege server speaks a newer protocol than this build
    // (Net.version_verdict == "update"). Full screen and input-blocking: the only ways out are UPDATE (the Play Store page)
    // and, if ALLOW_OFFLINE, "Play offline vs bots" -- online play stays locked (siege_app.gd re-shows this screen when
    // ONLINE / PLAY online is pressed). Android back quits the app instead of dismissing it.
    public class UpdateScreen : Control
    {
        public const string PACKAGE = Platform.PACKAGE;
        public const string MARKET_URL = Platform.PLAY_MARKET_URL;
        public const string WEB_URL = Platform.PLAY_WEB_URL;
        public const bool ALLOW_OFFLINE = true;      // false = a hard wall (no offline matches either)
        public const string TITLE = "UPDATE REQUIRED";
        public const string BODY = "A new version of Fatebound is available. Update to keep playing.";

        public event Action OfflineRequested;

        public int server_version = -1;
        // How URLs are opened (tests replace it). Returns an Error like OS.shell_open.
        public Func<string, int> open_url = (string u) => OS.ShellOpen(u);
        public GArray opened = new GArray();           // URLs tried, in order (diagnostics / tests)

        public static void OpenStore(Func<string, int> opener, GArray tried = null)
        {
            tried ??= new GArray();
            // Android: the Play Store app first (market://), the web page if that can't be opened (no Play Store). iOS: the App
            // Store page (0.31.130). Desktop: Google Play's web page.
            GArray urls = Platform.StoreUrls();
            for (int i = 0; i < urls.Size(); i++)
            {
                tried.Append(urls[i]);
                if ((int)opener(GD.Str(urls[i])) == GD.OK)
                    return;
            }
        }

        protected override void _Ready()
        {
            SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            MouseFilter = Control.MOUSE_FILTER_STOP;          // nothing underneath can be tapped
            var bg = new ColorRect();
            bg.Color = new Color(0.027, 0.043, 0.082, 1.0);       // opaque: nothing of the menu shows through
            bg.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            bg.MouseFilter = Control.MOUSE_FILTER_STOP;
            AddChild(bg);
            var glow = new TextureRect();
            var gg = new Gradient();
            gg.SetColor(0, new Color(1.0, 0.72, 0.3, 0.20));
            gg.SetColor(1, new Color(1.0, 0.72, 0.3, 0.0));
            var gt = new GradientTexture2D();
            gt.Gradient = gg;
            gt.Fill = GradientTexture2D.FillEnum.Radial;
            gt.FillFrom = new Vector2(0.5, 0.5);
            gt.FillTo = new Vector2(0.5, 1.0);
            gt.Width = 128;
            gt.Height = 128;
            glow.Texture = gt;
            glow.StretchMode = TextureRect.STRETCH_SCALE;
            glow.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            glow.AnchorRight = 1.0;
            glow.AnchorBottom = 0.6;
            glow.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(glow);
            var margin = new MarginContainer();
            margin.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            foreach (var side in new[] { "left", "right" })
                margin.AddThemeConstantOverride("margin_" + side, 28);
            margin.AddThemeConstantOverride("margin_top", 16);          // (40 in portrait)
            margin.AddThemeConstantOverride("margin_bottom", 12);
            margin.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(margin);
            var col = new VBoxContainer();
            col.Alignment = BoxContainer.ALIGNMENT_CENTER;
            col.AddThemeConstantOverride("separation", 14);
            col.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            margin.AddChild(col);
            var icon = UI.TexIcon(col, "res://assets/branding/icon.png", 104);   // the launcher icon (read only; 132 in portrait)
            icon.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
            var title = UI.Title(col, TITLE, 30, UI.GOLD);
            title.AddThemeColorOverride("font_outline_color", new Color("#2e1908"));
            title.AddThemeConstantOverride("outline_size", 8);
            title.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            var body = UI.Label(col, BODY, 18, UI.TEXT);
            body.HorizontalAlignment = HorizontalAlignment.Center;
            body.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            UI.Spacer(col, 10.0);
            var up = UI.Button(col, "UPDATE", "primary", _OnUpdate, "update_now", 30, 22);
            up.AddThemeFontOverride("font", UI.TITLE_FONT);
            up.CustomMinimumSize = new Vector2(420, 72);                // (0.31.216: landscape -- not the screen's width)
            up.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
            var sub = UI.Label(col, GD.Fmt("Opens Fatebound on %s", Platform.StoreName()), 12, UI.MUTED);   // (0.31.130: "the App Store" on iOS)
            sub.HorizontalAlignment = HorizontalAlignment.Center;
            if (ALLOW_OFFLINE)
            {
                UI.Spacer(col, 18.0);
                var off = UI.Button(col, "PLAY OFFLINE VS BOTS", "ghost", () => OfflineRequested?.Invoke(), "update_offline", 14);
                off.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
                off.CustomMinimumSize = new Vector2(240, 46);
                var note = UI.Label(col, "Online 16v16 needs the update.", 11, UI.MUTED);
                note.HorizontalAlignment = HorizontalAlignment.Center;
            }
            UI.Spacer(col, 10.0);
            var ver = UI.Label(col, GD.Fmt("Your version: %s (protocol %d)%s", _AppVersion(), Net.VERSION,
                server_version > 0 ? GD.Fmt("  ·  server: protocol %d", server_version) : ""), 10, new Color(UI.MUTED, 0.75));
            ver.HorizontalAlignment = HorizontalAlignment.Center;
            ver.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
        }

        public string _AppVersion()
        {
            var v = GD.Str(ProjectSettings.GetSetting("application/config/version", ""));
            return v != "" ? v : Diag.BUILD;
        }

        public void _OnUpdate()
        {
            OpenStore(open_url, opened);
        }
    }
}
