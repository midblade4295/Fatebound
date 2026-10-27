// Fatebound (Unity port, Kevin on its first match log: "put a fps counter in screen so I can see"): the frame rate in
// the screen's top-right corner (left of a match's pause button), over everything the game builds (its layers go up to
// 90: the title, the toasts), in menus and matches: the frames of the last half second, coloured by the 60 fps cap
// (green from 55, amber from 30, red below). Taps go through it. (Godot 0.31.222 shows none: siege_diag.gd's fps_text
// hasn't been shown since 0.31.163.)
using System;
using Fatebound.GUI;
using Fatebound.Sim;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    public partial class FpsCounter : CanvasLayer
    {
        public const double EVERY = 0.5;        // s between readings
        public const int SIZE = 12;             // its text, in the 760x420 design's pixels
        public Label label;
        public int _frames = 0;
        public long _from = 0;
        public double fps = 0.0;

        public FpsCounter()
        {
            Name = "FpsCounter";
            Layer = 128;
            ProcessMode = ProcessModeEnum.Always;
            var bg = new StyleBoxFlat();
            bg.BgColor = new Color(0, 0, 0, 0.5);
            bg.SetCornerRadiusAll(6);
            bg.ContentMarginLeft = 6;
            bg.ContentMarginRight = 6;
            bg.ContentMarginTop = 0;
            bg.ContentMarginBottom = 0;
            var box = new PanelContainer();
            box.Name = "Box";
            box.AddThemeStyleboxOverride("panel", bg);
            box.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            box.CustomMinimumSize = new Vector2(50, 0);
            box.SetAnchorsPreset(Control.PRESET_TOP_RIGHT);
            box.GrowHorizontal = Control.GROW_DIRECTION_BEGIN;
            box.OffsetLeft = -108;              // (left of the match's pause button: siege_hud.gd's, at the right edge less 52)
            box.OffsetRight = -58;
            box.OffsetTop = 2;                  // (over the menus' gem count)
            box.OffsetBottom = 2 + SIZE + 4;
            AddChild(box);
            label = new Label();
            label.Name = "Fps";
            label.Text = "-- FPS";
            label.AddThemeFontOverride("font", Ui.HEAVY_FONT);
            label.AddThemeFontSizeOverride("font_size", SIZE);
            label.AddThemeColorOverride("font_color", Color.WHITE);
            label.HorizontalAlignment = HorizontalAlignment.Center;
            label.VerticalAlignment = VerticalAlignment.Center;
            label.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            box.AddChild(label);
        }

        protected override void _Process(double delta)
        {
            var now = Time.GetTicksUsec();
            if (_from == 0)
            {
                _from = now;
                _frames = 0;
                return;
            }
            _frames += 1;
            var dt = (now - _from) / 1000000.0;
            if (dt < EVERY)
                return;
            fps = _frames / dt;
            _frames = 0;
            _from = now;
            var n = (int)Math.Round(fps);
            label.Text = GD.Fmt("%d FPS", n);
            label.AddThemeColorOverride("font_color", n >= 55 ? new Color(0.55, 1.0, 0.55) : n >= 30 ? new Color(1.0, 0.82, 0.35) : new Color(1.0, 0.45, 0.4));
        }
    }
}
