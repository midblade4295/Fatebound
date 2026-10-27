// Ported from godot/scripts/siege/kill_banner.gd (Fatebound 0.31.222).
using System;
using System.Collections;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    // 0.31.180 (Kevin: "Make banner in middle of screen when a player kills another player. It'll show "name" has slain
    // "name"" -- with League's multi-kills, ACE, First Blood and Shutdown -- "I want the banner art created by eleven so
    // they look more detailed. I also want special effects on the kill streak and first blood ones"): the 5v5's kill
    // banners, one at a time a little above the middle of the screen, from the sim's "kb" and "ace" events.
    //  - every hero kill: the name plaque (assets/ui/banners/plaque_*, ElevenLabs), the killer's portrait and the victim's
    //    (greyed, a skull on it) in its sockets, "<killer>  HAS SLAIN  <victim>" between them -- names in their sides'
    //    colours (yours green since 0.31.195, gold before); blue when your side made the kill, red when the enemy did;
    //  - over it the painted title for FIRST BLOOD, DOUBLE / TRIPLE / QUADRA KILL, PENTAKILL and SHUTDOWN (the gold paid
    //    under the plaque); ACE on its own with the five fallen;
    //  - each slams in (big, then settling), holds, fades. Effects: a light sweeps across the title; FIRST BLOOD bursts
    //    blood from its medallion, drips from its edge and flashes the screen's edges red; DOUBLE silver sparks; TRIPLE
    //    gold sparks and embers; QUADRA light rays turning behind its crest and a burst of gold; PENTAKILL bigger rays,
    //    gold confetti falling, sparks, and the screen's edges glowing gold all the while; SHUTDOWN embers and gold coins
    //    bursting from the broken crown; ACE blue rays and stars.
    //  - a newer banner cuts short the one showing (after a moment), so a QUADRA doesn't wait behind a TRIPLE.
    public class KillBanner : Control
    {
        public const string DIR = "res://assets/ui/banners/";
        public static readonly GArray MULTI_ART = GArray.Of("", "", "double", "triple", "quadra", "penta");
        // the art's width on screen (HUD units, the HUD ~420 wide) and how far its foot sits over the plaque
        public static readonly GDict ART_W = GDict.Of("first_blood", 330.0, "double", 320.0, "triple", 340.0, "shutdown", 330.0, "quadra", 236.0, "penta", 290.0,
            "ace", 220.0);
        public static readonly GDict ART_TUCK = GDict.Of("first_blood", 10.0, "double", 6.0, "triple", 8.0, "shutdown", 10.0, "quadra", 14.0, "penta", 18.0, "ace", 0.0);
        public const double PLAQUE_W = 340.0;
        public static readonly Vector3[] PLAQUE_SOCKETS = { new Vector3(0.1114, 0.5, 0.31), new Vector3(0.8873, 0.5, 0.31) };   // (x, y of the plaque; r of its height)
        public static readonly GDict LIFE = GDict.Of("kill", 2.4, "first_blood", 3.2, "double", 2.8, "triple", 3.0, "quadra", 3.5, "penta", 4.6, "shutdown", 3.2,
            "ace", 3.4);
        public const double OUT = 0.35;                       // the fade at the end
        public const double CUT_AFTER = 0.8;                  // a newer banner may cut the one showing short after this long
        public static readonly Color[] SIDE_COL = { Color.FromCode("#7fe0ff"), Color.FromCode("#ff8f6a") };
        public static readonly Color YOU_COL = Color.FromCode("#8cf0a8");        // your own name (0.31.195: green -- no yellow text)
        public const string SHINE_CODE = @"
shader_type canvas_item;
uniform float sweep = -1.0;
uniform float width = 0.11;
uniform float strength = 0.75;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float d = (UV.x + UV.y * 0.4) / 1.4 - sweep;
	float b = smoothstep(width, 0.0, abs(d)) * strength;
	c.rgb += vec3(1.0, 0.95, 0.82) * b * c.a;
	COLOR = c;
}
";

        public SiegeHud hud;                                  // siege_hud.gd: names, sides, portraits
        public GArray queue = new GArray();
        public GDict cur = new GDict();
        public double age = 0.0;
        public GArray parts = new GArray();
        public GArray shown = new GArray();                   // (tests: every banner started, in order: its "style")
        public GDict _tex = new GDict();
        public TextureRect _art;
        public Control _front;
        public ShaderMaterial _shine;
        public Font _lg;
        public Rng _rng = new Rng();
        public double _drip_t = 0.0;

        protected override void _Ready()
        {
            MouseFilter = Control.MOUSE_FILTER_IGNORE;
            SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            _lg = ResourceLoader.Load<Font>("res://assets/fonts/LilitaOne-Regular.ttf");
            _rng.Seed = (ulong)180;
            _art = new TextureRect();
            _art.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            _art.StretchMode = TextureRect.STRETCH_SCALE;
            _art.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            _art.Visible = false;
            var sh = new Shader();
            sh.Code = SHINE_CODE;
            _shine = new ShaderMaterial();
            _shine.Shader = sh;
            _art.Material = _shine;
            AddChild(_art);
            _front = new Control();
            _front.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            _front.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            _front.Draw += _DrawFront;
            AddChild(_front);
        }

        public Texture2D Tex(string name)
        {
            if (!_tex.Has(name))
            {
                var p = DIR + name + ".png";
                if (name.BeginsWith("res://"))
                    p = name;
                _tex[name] = ResourceLoader.Exists(p) ? Var.Of(ResourceLoader.Load<Texture2D>(p)) : Var.Nil;
            }
            return _tex[name].As<Texture2D>();
        }

        public Texture2D Portrait(Unit u)
        {
            // (u.get("hid", u.get("cls", "knight")): a unit without a hid is no hero; no unit at all ({}) is "knight")
            return Tex(GD.Fmt("res://assets/ui/skins/default_%s.png", GD.Str(u == null ? "knight" : (u.hid != "" ? u.hid : u.cls))));
        }

        public bool Busy()
        {
            return !cur.IsEmpty();
        }

        // ---------- what to show ----------
        public void Push(Ev e)
        {
            var item = new GDict();
            switch (e.S("k", ""))
            {
                case "kb":
                {
                    var kind = e.S("kind", "kill");
                    var style = kind;
                    if (kind == "multi")
                        style = MULTI_ART[GD.Clampi(e.I("n", 2), 2, 5)].AsString();
                    item = GDict.Of("style", style, "by", e.S("by", ""), "id", e.S("id", ""), "bounty", e.I("bounty", 0),
                        "shut", e.B("shut", false) || kind == "shutdown");
                    break;
                }
                case "ace":
                    item = GDict.Of("style", "ace", "by", e.S("by", ""), "ids", e.TryGetValue("ids", out var ids) ? GArray.From(ids as IEnumerable) : new GArray(), "team", e.I("team", -1));
                    break;
                default:
                    return;
            }
            queue.Append(item);
            while (queue.Size() > 4)
            {
                // (a long run of kills: the plain ones go first)
                var drop = -1;
                for (int i = 0; i < queue.Size(); i++)
                {
                    if (GD.Str(queue[i]["style"]) == "kill")
                    {
                        drop = i;
                        break;
                    }
                }
                queue.RemoveAt(drop >= 0 ? drop : 0);
            }
        }

        public void _Start(GDict item)
        {
            cur = item.Duplicate();
            cur["life"] = (double)LIFE.Get(GD.Str(item["style"]), 2.4);
            age = 0.0;
            _drip_t = 0.0;
            shown.Append(GD.Str(item["style"]));
            var st = GD.Str(item["style"]);
            Texture2D t = st != "kill" ? Tex(st) : null;
            _art.Texture = t;
            _art.Visible = t != null;
            _Burst(st);
        }

        // ---------- the frame ----------
        protected override void _Process(double delta)
        {
            if (cur.IsEmpty() && queue.IsEmpty() && parts.IsEmpty())
            {
                if (_art.Visible)
                    _art.Visible = false;
                return;
            }
            age += delta;
            if (!cur.IsEmpty() && !queue.IsEmpty() && age > CUT_AFTER)
                cur["life"] = GD.Minf((double)cur["life"], age + OUT);     // (one waiting: this one goes after its moment)
            if (!cur.IsEmpty() && age >= (double)cur["life"])
            {
                cur = new GDict();
                _art.Visible = false;
            }
            if (cur.IsEmpty() && !queue.IsEmpty())
                _Start(queue.PopFront().D);
            _StepParts(delta);
            _PlaceArt();
            QueueRedraw();
            _front.QueueRedraw();
        }

        public Vector2 Center()
        {
            // the plaque's middle: a little above the middle of the screen, under the top bar and the kill feed
            return new Vector2(Size.x * 0.5, GD.Clampf(Size.y * 0.36, 290.0, 420.0));
        }

        public double ScaleNow()
        {
            if (cur.IsEmpty())
                return 1.0;
            var big = GArray.Of("quadra", "penta", "ace", "first_blood").Has(GD.Str(cur["style"])) ? 1.55 : 1.35;
            if (age < 0.16)
                return GD.Lerpf(big, 0.93, GD.Ease(age / 0.16, 0.5));
            if (age < 0.3)
                return GD.Lerpf(0.93, 1.0, (age - 0.16) / 0.14);
            return 1.0;
        }

        public double AlphaNow()
        {
            if (cur.IsEmpty())
                return 0.0;
            return GD.Clampf(age / 0.08, 0.0, 1.0) * GD.Clampf(((double)cur["life"] - age) / OUT, 0.0, 1.0);
        }

        public Rect2 ArtRect()
        {
            // the title art's rect at rest (before the slam's scale), its foot tucked over the plaque
            var st = GD.Str(cur.Get("style", ""));
            Texture2D t = _art.Texture;
            if (t == null)
                return new Rect2(Center(), Vector2.ZERO);
            double w = (double)ART_W.Get(st, 320.0);
            var h = w * (double)t.GetHeight() / (double)t.GetWidth();
            var c = Center();
            var foot = c.y - PlaqueSize().y * 0.5 + (double)ART_TUCK.Get(st, 8.0);
            if (st == "ace")
                foot = c.y + 30.0;
            return new Rect2(new Vector2(c.x - w * 0.5, foot - h), new Vector2(w, h));
        }

        public Vector2 PlaqueSize()
        {
            var t = Tex("plaque_blue");
            return new Vector2(PLAQUE_W, PLAQUE_W * (t != null ? (double)t.GetHeight() / (double)t.GetWidth() : 0.18));
        }

        public void _PlaceArt()
        {
            if (!_art.Visible)
                return;
            var r = ArtRect();
            var s = ScaleNow();
            var c = Center();
            _art.Size = r.size;
            _art.PivotOffset = c - r.position;          // (scaled round the banner's middle, with the plaque)
            _art.Position = r.position + new Vector2(0, -10.0 * (1.0 - GD.Clampf(((double)cur["life"] - age) / OUT, 0.0, 1.0)));
            _art.Scale = new Vector2(s, s);
            _art.Modulate = new Color(1, 1, 1, AlphaNow());
            // the light across the title: once as it lands; again and again on the big ones
            var period = GArray.Of("triple", "quadra", "penta", "ace", "first_blood").Has(GD.Str(cur["style"])) ? 1.5 : 99.0;
            var tt = GD.Fmod(GD.Maxf(0.0, age - 0.22), period);
            _shine.SetShaderParameter("sweep", tt < 0.7 ? -0.2 + tt / 0.7 * 1.4 : -1.0);
        }

        // ---------- behind the art: rays, the screen's edges ----------
        protected override void _Draw()
        {
            if (cur.IsEmpty())
                return;
            var st = GD.Str(cur["style"]);
            var a = AlphaNow();
            var ar = ArtRect();
            var ac = ar.GetCenter();
            switch (st)
            {
                case "quadra":
                    _Rays(ac, 210.0, 14, new Color(1.0, 0.85, 0.4, 0.33 * a), 0.35);
                    break;
                case "penta":
                    _Rays(ac, 300.0, 18, new Color(1.0, 0.86, 0.42, 0.42 * a), 0.25);
                    _Edges(new Color(1.0, 0.78, 0.25, (0.38 + 0.14 * Math.Sin(age * 6.0)) * a), 90.0);
                    break;
                case "ace":
                    _Rays(ac, 190.0, 12, new Color(0.55, 0.85, 1.0, 0.3 * a), 0.4);
                    break;
                case "first_blood":
                {
                    var k = GD.Clampf(1.0 - age / 0.9, 0.0, 1.0);
                    if (k > 0.0)
                        _Edges(new Color(0.85, 0.04, 0.06, 0.55 * k), 70.0);
                    if (age < 0.5)
                        DrawArc(ac, 40.0 + age * 420.0, 0.0, GD.TAU, 48, new Color(1.0, 0.2, 0.2, 0.6 * (1.0 - age / 0.5)), 5.0, true);
                    break;
                }
                case "shutdown":
                    if (age < 0.45)
                        DrawArc(ac, 30.0 + age * 380.0, 0.0, GD.TAU, 48, new Color(1.0, 0.55, 0.15, 0.55 * (1.0 - age / 0.45)), 5.0, true);
                    break;
            }
            if (GArray.Of("quadra", "penta", "ace").Has(st))
                DrawCircle(ac, ar.size.x * 0.42, st != "ace" ? new Color(1.0, 0.9, 0.5, 0.12 * a) : new Color(0.6, 0.85, 1.0, 0.12 * a));
        }

        public void _Rays(Vector2 c, double r, int n, Color col, double speed)
        {
            var rot = age * speed;
            var clear = new Color(col.r, col.g, col.b, 0.0);
            for (int i = 0; i < n; i++)
            {
                var a0 = rot + GD.TAU * (double)i / (double)n;
                var a1 = a0 + GD.PI / (double)n * 0.75;
                DrawPolygon(new Vector2[] { c, c + Vector2.FromAngle(a0) * r, c + Vector2.FromAngle(a1) * r },
                    new Color[] { col, clear, clear });
            }
        }

        public void _Edges(Color col, double w)
        {
            var clear = new Color(col.r, col.g, col.b, 0.0);
            var W = Size.x;
            var H = Size.y;
            foreach (var q in new Vector2[][] { new[] { new Vector2(0, 0), new Vector2(W, 0), new Vector2(W, w), new Vector2(0, w) }, new[] { new Vector2(0, H), new Vector2(W, H), new Vector2(W, H - w), new Vector2(0, H - w) },
                    new[] { new Vector2(0, 0), new Vector2(0, H), new Vector2(w, H), new Vector2(w, 0) }, new[] { new Vector2(W, 0), new Vector2(W, H), new Vector2(W - w, H), new Vector2(W - w, 0) } })
                DrawPolygon(q, new Color[] { col, col, clear, clear });
        }

        // ---------- in front: the plaque, the names, the gold, the particles ----------
        public void _DrawFront()
        {
            if (!cur.IsEmpty())
            {
                var a = AlphaNow();
                var s = ScaleNow();
                var c = Center();
                var lift = -10.0 * (1.0 - GD.Clampf(((double)cur["life"] - age) / OUT, 0.0, 1.0));
                _front.DrawSetTransform(c + new Vector2(0, lift), 0.0, new Vector2(s, s));
                if (GD.Str(cur["style"]) == "ace")
                    _DrawAce(a);
                else
                    _DrawPlaque(a);
                _front.DrawSetTransform(Vector2.ZERO, 0.0, Vector2.ONE);
            }
            foreach (var p in parts)
                _DrawPart(p.D);
        }

        public Unit _Unit(string id)
        {
            // ({} when there's no such unit: null here)
            return hud != null && hud.sim != null ? (hud.sim.by_id.TryGetValue(id, out var u) ? u : null) : null;
        }

        public Color _NameCol(Unit u)
        {
            if (u == null)
                return Color.WHITE;
            if (GD.Str(u.id) == GD.Str(hud.player_id))
                return YOU_COL;
            return (int)u.team <= 1 ? SIDE_COL[hud.Vt((int)u.team)] : Color.WHITE;
        }

        public void _DrawPlaque(double a)
        {
            var k = _Unit(GD.Str(cur.Get("by", "")));
            var v = _Unit(GD.Str(cur.Get("id", "")));
            bool ours = k != null && hud.Vt((int)k.team) == 0;
            var pt = Tex(ours ? "plaque_blue" : "plaque_red");
            var ps = PlaqueSize();
            var r = new Rect2(-ps * 0.5, ps);
            var w = new Color(1, 1, 1, a);
            if (pt != null)
                _front.DrawTextureRect(pt, r, false, w);
            else
                _front.DrawRect(r, new Color(0.05, 0.1, 0.16, 0.9 * a));
            // the two portraits in their sockets
            for (int i = 0; i < 2; i++)
            {
                Vector3 sk = PLAQUE_SOCKETS[i];
                var pc = r.position + new Vector2(sk.x * ps.x, sk.y * ps.y);
                var pr = sk.z * ps.y * 1.04;
                var who = i == 0 ? k : v;
                _Disc(Portrait(who), pc, pr, i == 0 ? new Color(1, 1, 1, a) : new Color(0.5, 0.5, 0.56, a));
                if (i == 1)
                {
                    var sk_t = Tex("res://assets/ui/v2/icons/skull.png");
                    if (sk_t != null)
                        _front.DrawTextureRect(sk_t, new Rect2(pc + new Vector2(pr * 0.2, pr * 0.05), new Vector2(pr * 1.1, pr * 1.1)), false, w);
                }
            }
            // "<killer>  HAS SLAIN  <victim>", fitted between the sockets
            var room = ps.x * (PLAQUE_SOCKETS[1].x - PLAQUE_SOCKETS[0].x) - ps.y * 0.85;
            var names = LineNames();
            string kn = names[0].AsString();
            string vn = names[1].AsString();
            Font bold = hud._bold;
            Font title = hud._title;
            var fs = 15;
            var verb = "HAS SLAIN";
            var vs = 9;
            var tw = 0.0;
            while (fs > 9)
            {
                tw = bold.GetStringSize(kn, HorizontalAlignment.Left, -1, fs).x + bold.GetStringSize(vn, HorizontalAlignment.Left, -1, fs).x
                    + title.GetStringSize(verb, HorizontalAlignment.Left, -1, vs).x + 14.0;
                if (tw <= room)
                    break;
                fs -= 1;
            }
            var x = -tw * 0.5;
            var @base = (double)fs * 0.36;
            x = _Word(kn, bold, fs, new Vector2(x, @base), _NameCol(k), a) + 7.0;
            x = _Word(verb, title, vs, new Vector2(x, @base - 1.0), Color.FromCode("#f2d18d"), a) + 7.0;
            _Word(vn, bold, fs, new Vector2(x, @base), _NameCol(v), a);
            // a SHUTDOWN's gold: the kill and the bounty
            if ((bool)cur.Get("shut", false) && (int)cur.Get("bounty", 0) > 0)
            {
                var total = 300 + (int)cur["bounty"];
                var txt = GD.Fmt("+%d", total);
                var cw = _lg.GetStringSize(txt, HorizontalAlignment.Left, -1, 24).x + 40.0;
                var cr = new Rect2(new Vector2(-cw * 0.5, ps.y * 0.5 + 6.0), new Vector2(cw, 32.0));
                _front.DrawRect(cr, new Color(0.12, 0.07, 0.01, 0.85 * a));
                _front.DrawRect(cr, new Color(0.88, 0.69, 0.28, a), false, 2.0);
                var coin = Tex("res://assets/ui/currency/coin.png");
                if (coin != null)
                    _front.DrawTextureRect(coin, new Rect2(cr.position + new Vector2(5, 3), new Vector2(26, 26)), false, w);
                _Word(txt, _lg, 24, cr.position + new Vector2(34, 26), Color.WHITE, a);
                var sub = GD.Fmt("%d BOUNTY", (int)cur["bounty"]);
                var sw = bold.GetStringSize(sub, HorizontalAlignment.Left, -1, 10).x;
                _Word(sub, bold, 10, new Vector2(-sw * 0.5, cr.End.y + 13.0), Color.FromCode("#e8dcc0"), a);
            }
        }

        public GArray LineNames()
        {
            // the plaque's two names: [killer, victim] (as the HUD names them: yours, a player's, "Bot <name>")
            var k = _Unit(GD.Str(cur.Get("by", "")));
            var v = _Unit(GD.Str(cur.Get("id", "")));
            return GArray.Of(k != null ? hud.DisplayName(k) : "?", v != null ? hud.DisplayName(v) : "?");
        }

        public void _DrawAce(double a)
        {
            // the five fallen in a row under the crest, and who sealed it
            GArray ids = cur.Get("ids", new GArray()).A;
            var n = ids.Size();
            var d = 46.0;
            var x0 = -((double)n * (d + 6.0) - 6.0) * 0.5 + d * 0.5;
            var y = 58.0;
            var w = new Color(1, 1, 1, a);
            var sk_t = Tex("res://assets/ui/v2/icons/skull.png");
            for (int i = 0; i < n; i++)
            {
                var u = _Unit(GD.Str(ids[i]));
                var pc = new Vector2(x0 + (double)i * (d + 6.0), y);
                _front.DrawCircle(pc, d * 0.5 + 3.0, new Color(0.7, 0.53, 0.2, a));
                _Disc(Portrait(u), pc, d * 0.5, new Color(0.5, 0.5, 0.56, a));
                if (sk_t != null)
                    _front.DrawTextureRect(sk_t, new Rect2(pc + new Vector2(4, 2), new Vector2(22, 22)), false, w);
            }
            var k = _Unit(GD.Str(cur.Get("by", "")));
            bool ours = (int)cur.Get("team", -1) >= 0 && hud.Vt((int)cur["team"]) == 0;
            var line = k != null ? (GD.Fmt("%s SEALED IT", hud.DisplayName(k).ToUpperInvariant())) : "THE WHOLE SIDE IS DOWN";
            if (!ours)
                line = "YOUR WHOLE SIDE IS DOWN";
            double lw = hud._title.GetStringSize(line, HorizontalAlignment.Left, -1, 12).x;
            _Word(line, hud._title, 12, new Vector2(-lw * 0.5, y + d * 0.5 + 22.0), ours ? Color.FromCode("#f2d18d") : Color.FromCode("#ff8f6a"), a);
        }

        public double _Word(string t, Font f, int fs, Vector2 p, Color col, double a)
        {
            col.a = (float)(col.a * a);
            _front.DrawStringOutline(f, p, t, HorizontalAlignment.Left, -1, fs, 5, new Color(0.03, 0.02, 0.05, 0.85 * a));
            _front.DrawString(f, p, t, HorizontalAlignment.Left, -1, fs, col);
            return p.x + f.GetStringSize(t, HorizontalAlignment.Left, -1, fs).x;
        }

        public void _Disc(Texture2D t, Vector2 c, double r, Color mod)
        {
            // a portrait clipped to a circle
            if (t == null)
            {
                _front.DrawCircle(c, r, new Color(0.1, 0.12, 0.16, mod.a));
                return;
            }
            var pts = new List<Vector2>();
            var uvs = new List<Vector2>();
            for (int i = 0; i < 32; i++)
            {
                var v = Vector2.FromAngle(GD.TAU * (double)i / 32.0);
                pts.Add(c + v * r);
                uvs.Add(new Vector2(0.5, 0.46) + v * 0.46);
            }
            _front.DrawPolygon(pts, new Color[] { mod }, uvs, t);
        }

        // ---------- particles ----------
        public void _Burst(string st)
        {
            var ar = ArtRect();
            var ac = ar.GetCenter();
            var top = new Vector2(ac.x, ar.position.y + ar.size.y * 0.22);
            switch (st)
            {
                case "first_blood":
                    for (int i = 0; i < 46; i++)
                    {
                        var dir = Vector2.FromAngle(-GD.PI * 0.5 + _rng.RandfRange(-1.35, 1.35));
                        _Add(GDict.Of("kind", "blood", "p", top, "v", dir * _rng.RandfRange(160.0, 380.0), "life", _rng.RandfRange(0.8, 1.4),
                            "size", _rng.RandfRange(3.5, 7.0), "col", new Color(0.86, 0.05, 0.08), "g", 620.0));
                    }
                    break;
                case "double":
                    _Sparks(ac, 26, new Color(0.92, 0.96, 1.0), 260.0);
                    break;
                case "triple":
                    _Sparks(ac, 34, new Color(1.0, 0.86, 0.38), 300.0);
                    for (int i = 0; i < 14; i++)
                        _Ember(ar, new Color(1.0, 0.7, 0.25));
                    break;
                case "quadra":
                    _Sparks(ac, 44, new Color(1.0, 0.86, 0.38), 340.0);
                    for (int i = 0; i < 10; i++)
                        _Coin(ac, 260.0);
                    break;
                case "penta":
                    _Sparks(ac, 60, new Color(1.0, 0.9, 0.45), 380.0);
                    for (int i = 0; i < 12; i++)
                        _Coin(ac, 300.0);
                    for (int i = 0; i < 40; i++)
                        _Confetti(true);
                    break;
                case "shutdown":
                    for (int i = 0; i < 14; i++)
                        _Coin(top, 280.0);
                    for (int i = 0; i < 20; i++)
                        _Ember(ar, new Color(1.0, 0.45, 0.12));
                    break;
                case "ace":
                    for (int i = 0; i < 26; i++)
                    {
                        var dir2 = Vector2.FromAngle(_rng.Randf() * GD.TAU);
                        _Add(GDict.Of("kind", "star", "p", ac, "v", dir2 * _rng.RandfRange(120.0, 300.0), "life", _rng.RandfRange(0.6, 1.1),
                            "size", _rng.RandfRange(4.0, 8.0), "col", new Color(0.75, 0.92, 1.0), "g", 0.0, "spin", _rng.RandfRange(-6.0, 6.0)));
                    }
                    break;
            }
        }

        public void _Sparks(Vector2 c, int n, Color col, double sp)
        {
            for (int i = 0; i < n; i++)
            {
                var dir = Vector2.FromAngle(_rng.Randf() * GD.TAU);
                _Add(GDict.Of("kind", "spark", "p", c + dir * 20.0, "v", dir * _rng.RandfRange(sp * 0.4, sp), "life", _rng.RandfRange(0.45, 0.9),
                    "size", _rng.RandfRange(2.5, 4.5), "col", col, "g", 180.0));
            }
        }

        public void _Ember(Rect2 ar, Color col)
        {
            var p = new Vector2(_rng.RandfRange(ar.position.x + ar.size.x * 0.1, ar.End.x - ar.size.x * 0.1), _rng.RandfRange(ar.position.y + ar.size.y * 0.4, ar.End.y));
            _Add(GDict.Of("kind", "ember", "p", p, "v", new Vector2(_rng.RandfRange(-20.0, 20.0), _rng.RandfRange(-90.0, -40.0)), "life", _rng.RandfRange(1.0, 1.8),
                "size", _rng.RandfRange(2.5, 4.5), "col", col, "g", -10.0));
        }

        public void _Coin(Vector2 c, double sp)
        {
            var dir = Vector2.FromAngle(-GD.PI * 0.5 + _rng.RandfRange(-1.1, 1.1));
            _Add(GDict.Of("kind", "coin", "p", c, "v", dir * _rng.RandfRange(sp * 0.5, sp), "life", _rng.RandfRange(1.1, 1.6), "size", _rng.RandfRange(16.0, 24.0),
                "col", Color.WHITE, "g", 700.0, "spin", _rng.RandfRange(-8.0, 8.0)));
        }

        public void _Confetti(bool top = false)
        {
            var cols = GArray.Of(Color.FromCode("#ffd65a"), Color.FromCode("#fff3c4"), Color.FromCode("#c77dff"), Color.FromCode("#ff6a5a"));
            var p = new Vector2(_rng.RandfRange(0.0, Size.x), top ? _rng.RandfRange(-40.0, 0.0) : -10.0);
            _Add(GDict.Of("kind", "confetti", "p", p, "v", new Vector2(_rng.RandfRange(-30.0, 30.0), _rng.RandfRange(80.0, 170.0)), "life", _rng.RandfRange(2.4, 3.6),
                "size", _rng.RandfRange(4.0, 7.0), "col", cols[(int)((long)_rng.Randi() % cols.Size())], "g", 30.0, "spin", _rng.RandfRange(-7.0, 7.0)));
        }

        public void _Add(GDict p)
        {
            p["age"] = 0.0;
            p["rot"] = _rng.Randf() * GD.TAU;
            if (parts.Size() < 220)
                parts.Append(p);
        }

        public void _StepParts(double dt)
        {
            // the effects that go on while it shows: FIRST BLOOD's drips, PENTAKILL's confetti, embers
            if (!cur.IsEmpty() && age < (double)cur["life"] - OUT)
            {
                var st = GD.Str(cur["style"]);
                _drip_t -= dt;
                if (_drip_t <= 0.0)
                {
                    var ar = ArtRect();
                    switch (st)
                    {
                        case "first_blood":
                            _drip_t = 0.09;
                            _Add(GDict.Of("kind", "drip", "p", new Vector2(_rng.RandfRange(ar.position.x + ar.size.x * 0.12, ar.End.x - ar.size.x * 0.12), ar.End.y - ar.size.y * 0.16),
                                "v", new Vector2(0.0, _rng.RandfRange(10.0, 40.0)), "life", _rng.RandfRange(0.8, 1.3), "size", _rng.RandfRange(2.0, 3.5),
                                "col", new Color(0.75, 0.03, 0.06), "g", 380.0));
                            break;
                        case "penta":
                            _drip_t = 0.05;
                            _Confetti();
                            break;
                        case "triple":
                        case "shutdown":
                            _drip_t = 0.12;
                            _Ember(ar, st == "triple" ? new Color(1.0, 0.7, 0.25) : new Color(1.0, 0.45, 0.12));
                            break;
                        case "quadra":
                            _drip_t = 0.1;
                            _Sparks(ar.GetCenter() + new Vector2(_rng.RandfRange(-90.0, 90.0), _rng.RandfRange(-60.0, 60.0)), 2, new Color(1.0, 0.88, 0.45), 120.0);
                            break;
                        default:
                            _drip_t = 99.0;
                            break;
                    }
                }
            }
            for (int i = parts.Size() - 1; i > -1; i--)
            {
                GDict p = parts[i].D;
                p["age"] = (double)p["age"] + dt;
                if ((double)p["age"] >= (double)p["life"])
                {
                    parts.RemoveAt(i);
                    continue;
                }
                p["v"] = p["v"].V2 + new Vector2(0.0, (double)p["g"]) * dt;
                if (GArray.Of("confetti", "ember").Has(GD.Str(p["kind"])))
                    p["v"] = p["v"].V2 * (1.0 - 0.6 * dt);
                p["p"] = p["p"].V2 + p["v"].V2 * dt;
                p["rot"] = (double)p["rot"] + (double)p.Get("spin", 0.0) * dt;
            }
        }

        public void _DrawPart(GDict p)
        {
            var k = 1.0 - (double)p["age"] / (double)p["life"];
            Color col = p["col"].As<Color>();
            Vector2 pos = p["p"].V2;
            var sz = (double)p["size"];
            switch (GD.Str(p["kind"]))
            {
                case "blood":
                case "drip":
                {
                    col.a = (float)GD.Clampf(k * 1.6, 0.0, 1.0);
                    Vector2 v = p["v"].V2;
                    _front.DrawLine(pos, pos - v.Normalized() * sz * 1.8, col, sz * 1.4, true);
                    _front.DrawCircle(pos, sz, col);
                    break;
                }
                case "spark":
                    col.a = (float)k;
                    _front.DrawCircle(pos, sz * 2.2, new Color(col.r, col.g, col.b, 0.22 * k));
                    _front.DrawLine(pos, pos - p["v"].V2 * 0.04, col, sz, true);
                    break;
                case "ember":
                    col.a = (float)(k * (0.6 + 0.4 * Math.Sin((double)p["age"] * 20.0 + sz)));
                    _front.DrawCircle(pos, sz * 2.0, new Color(col.r, col.g, col.b, col.a * 0.25));
                    _front.DrawCircle(pos, sz, col);
                    break;
                case "coin":
                {
                    var t = Tex("res://assets/ui/currency/coin.png");
                    var sx = Math.Abs(Math.Cos((double)p["rot"])) * 0.8 + 0.2;
                    if (t != null)
                    {
                        _front.DrawSetTransform(pos, 0.0, new Vector2(sx, 1.0));
                        _front.DrawTextureRect(t, new Rect2(-new Vector2(sz, sz) * 0.5, new Vector2(sz, sz)), false, new Color(1, 1, 1, GD.Clampf(k * 2.0, 0.0, 1.0)));
                        _front.DrawSetTransform(Vector2.ZERO, 0.0, Vector2.ONE);
                    }
                    break;
                }
                case "confetti":
                    col.a = (float)GD.Clampf(k * 2.0, 0.0, 1.0);
                    _front.DrawSetTransform(pos, (double)p["rot"], new Vector2(1.0, Math.Abs(Math.Sin((double)p["rot"] * 1.3)) * 0.8 + 0.2));
                    _front.DrawRect(new Rect2(-new Vector2(sz, sz * 0.6) * 0.5, new Vector2(sz, sz * 0.6)), col);
                    _front.DrawSetTransform(Vector2.ZERO, 0.0, Vector2.ONE);
                    break;
                case "star":
                    col.a = (float)k;
                    _front.DrawSetTransform(pos, (double)p["rot"], Vector2.ONE);
                    _front.DrawRect(new Rect2(new Vector2(-sz, -sz * 0.18), new Vector2(sz * 2.0, sz * 0.36)), col);
                    _front.DrawRect(new Rect2(new Vector2(-sz * 0.18, -sz), new Vector2(sz * 0.36, sz * 2.0)), col);
                    _front.DrawSetTransform(Vector2.ZERO, 0.0, Vector2.ONE);
                    break;
            }
        }
    }
}
