// Ported from godot/scripts/siege/minimap.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    using Land = Fatebound.Sim.Land;
    using Keep = Fatebound.Sim.Keep;
    using View = Fatebound.Game.SiegeView;

    // The match's minimap (0.31.216, Kevin: "make fatebound more like [Honor of Kings]" -- the landscape HUD's map in the
    // top-left corner). The field as the camera sees it: the square, your keep bottom-left (siege_view.gd screen_up) --
    // the painted plan tools/bake_land.gd bakes (assets/terrain/minimap.png), turned to the view. Over it: the towers
    // (your side blue, theirs red, a fallen one a grey cross), the Kings, the jungle's camps that are up, the epic
    // monsters, the minions and the heroes -- yours always, theirs only where your side sees them (moba_vision.gd: the fog
    // of war) -- you ringed in white, your wards. Redrawn REDRAW times a second; the plan is one texture.
    public class Minimap : Control
    {
        public const string PLAN = "res://assets/terrain/minimap.png";
        public const double SPAN = 168.0;                       // metres across the minimap (the 156 m square and a little of its edge)
        public const double REDRAW = 0.2;
        public static readonly Color BLUE = new Color("#4fc3ff");
        public static readonly Color RED = new Color("#ff5a4a");
        public static readonly Color MONSTER = new Color("#c58bff");

        public SiegeHud hud;                                    // siege_hud.gd (its sim, player_id)
        public Texture2D _plan = null;
        public double _clock = 0.0;
        public StyleBoxFlat _frame = null;

        protected override void _Ready()
        {
            MouseFilter = Control.MOUSE_FILTER_IGNORE;
            ClipContents = true;
            if (ResourceLoader.Exists(PLAN))
                _plan = ResourceLoader.Load<Texture2D>(PLAN);
        }

        protected override void _Process(double dt)
        {
            _clock -= dt;
            if (_clock <= 0.0)
            {
                _clock = REDRAW;
                QueueRedraw();
            }
        }

        public int Team()
        {
            if (hud == null || hud.sim == null)
                return 0;
            return hud.sim.by_id.TryGetValue(hud.player_id, out var u) ? u.team : 0;
        }

        public Vector2 ToMap(Vector2 p)
        {
            // a world point on the minimap: along the screen's right and up, as the camera sees it
            var up = View.ScreenUp(Team());
            var right = new Vector2(-up.y, up.x);
            var k = Size.x / SPAN;
            return Size * 0.5 + new Vector2(p.Dot(right), -p.Dot(up)) * k;
        }

        protected override void _Draw()
        {
            if (_frame == null)
            {
                _frame = new StyleBoxFlat();
                _frame.BgColor = new Color(0.02, 0.04, 0.06, 0.82);
                _frame.BorderColor = new Color(VisualTheme.GOLD_DARK, 0.9);
                _frame.SetBorderWidthAll(2);
                _frame.SetCornerRadiusAll(6);
                _frame.AntiAliasing = true;
            }
            DrawStyleBox(_frame, new Rect2(Vector2.ZERO, Size));
            if (hud == null || hud.sim == null)
                return;
            var sim = hud.sim;
            var me_team = Team();
            var k = Size.x / SPAN;
            if (_plan != null)
            {
                // the plan covers Land.bake_rect in world orientation: turned and scaled to the view
                var br = Land.BakeRect();
                var r = new Rect2(br.x, br.y, br.w, br.h);
                var up = View.ScreenUp(me_team);
                var ang = Math.Atan2(up.x, -up.y);                 // the world's -y is the screen's up when this is 0
                DrawSetTransform(Size * 0.5, -ang, new Vector2(k, k));
                DrawTextureRect(_plan, new Rect2(r.position, r.size), false, new Color(1, 1, 1, 0.92));
                DrawSetTransform(Vector2.ZERO, 0.0, Vector2.ONE);
            }
            var m = sim.moba;
            if (m == null)
                return;
            var vis = m.vision;
            // the camps that are up and the epic monsters
            foreach (var camp in m.camps)
            {
                // (camp.has("alive"): a camp always has it)
                var up_now = camp.alive;
                if (!up_now)
                    continue;
                var cp = ToMap(camp.p);
                var epic = camp.kind == "lord" || camp.kind == "wyrm";
                DrawCircle(cp, epic ? 4.2 : 2.6, new Color(0.05, 0.03, 0.08, 0.9));
                DrawCircle(cp, epic ? 3.2 : 1.8, epic ? MONSTER : new Color("#e8d7a0"));
            }
            // the towers and the Kings
            foreach (var tw in m.towers)
            {
                var tp = ToMap(tw.p);
                var col = tw.team == me_team ? BLUE : RED;
                if (tw.dead)
                {
                    DrawLine(tp - new Vector2(3, 3), tp + new Vector2(3, 3), new Color(0.6, 0.6, 0.6, 0.8), 1.5);
                    DrawLine(tp - new Vector2(3, -3), tp + new Vector2(3, -3), new Color(0.6, 0.6, 0.6, 0.8), 1.5);
                    continue;
                }
                DrawRect(new Rect2(tp - new Vector2(4, 4), new Vector2(8, 8)), new Color(0.02, 0.03, 0.05, 0.95));
                DrawRect(new Rect2(tp - new Vector2(3, 3), new Vector2(6, 6)), col);
            }
            for (int t = 0; t < 2; t++)
            {
                var kp = ToMap(SiegeSim.M(t, Keep.KING));
                DrawCircle(kp, 5.5, new Color(0.02, 0.03, 0.05, 0.95));
                DrawCircle(kp, 4.5, new Color("#ffd65a"));
                DrawCircle(kp, 2.5, t == me_team ? BLUE : RED);
            }
            // your wards
            foreach (var w in vis != null ? vis.wards : new List<Ward>())
            {
                if (w.team == me_team)
                    DrawCircle(ToMap(w.p), 2.2, new Color("#9cff8a"));
            }
            // the minions, then the heroes (yours always; theirs where your side sees them)
            var mine_id = GD.Str(hud.player_id);
            var heroes = new List<Unit>();
            foreach (var u in sim.units)
            {
                if (u.state == "dead" || u.team > 1)
                    continue;
                var ally = u.team == me_team;
                if (!ally && vis != null && !vis.CanSee(me_team, u))
                    continue;
                if (u.hero)
                {
                    heroes.Add(u);
                    continue;
                }
                DrawCircle(ToMap(u.pos), 1.4, new Color(ally ? BLUE : RED, 0.9));
            }
            foreach (var u in heroes)
            {
                var hp = ToMap(u.pos);
                var ally = u.team == me_team;
                var col = ally ? BLUE : RED;
                DrawCircle(hp, 5.0, new Color(0.02, 0.03, 0.05, 0.95));
                DrawCircle(hp, 4.0, col);
                if (u.id == mine_id)
                    DrawArc(hp, 6.0, 0.0, GD.TAU, 20, Color.WHITE, 1.6, true);
            }
            // where the camera looks: a thin frame round your view
            Unit me = sim.by_id.TryGetValue(mine_id, out var mu) ? mu : null;
            if (me != null)
            {
                var c = ToMap(me.pos);
                Vector2 half = new Vector2(15.0, 8.0) * k * ((double)hud.Size.x / GD.Maxf(hud.Size.y, 1.0)) / 1.8;
                DrawRect(new Rect2(c - half, half * 2.0), new Color(1, 1, 1, 0.35), false, 1.0);
            }
        }
    }
}
