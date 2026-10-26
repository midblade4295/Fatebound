// Ported from godot/scripts/app/clan_camp.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector3 = Fatebound.Sim.Vec3;
using Vector4 = Fatebound.Sim.Vec4;
using Color = Fatebound.GUI.Col;
using UI2 = Fatebound.Game.Ui2;
using Eco = Fatebound.Game.Economy;

namespace Fatebound.Game
{
    // 0.31.196 (Kevin: "Do clan chest, clan camp, crest, ..."): the CLAN CAMP at the top of the CLAN window -- the clan's
    // camp painted at its stage (Eco.clan_camp_stage of its level: a tent and a banner; two tents and two banners; a palisade,
    // three banners and a cauldron; a hall, a watchtower and five banners -- tools/build_clan_art.py), alive: the banners in
    // the crest's field colour with the crest on each (the cloth ripples), the campfire's flames, halo and embers with its
    // light flickering over the camp (clan_camp.gdshader), fireflies. Reduce Motion: still.
    // 0.31.197 (Kevin: "make the camp screen fill the entire screen instead of being a small box and incorporate the clan
    // buttons into the screen"): the whole CLAN screen -- the painting is tall now (the stage in its middle, the night sky
    // above it, the ground falling into shadow below: tools/build_clan_art.py), covering this control like Home's camp
    // (cut at the sides on a phone longer than 1:2), with stars twinkling and now and then falling in its sky. The window
    // puts its buttons over it (clan_panel.gd).
    public class ClanCamp : Control
    {
        public static readonly Shader CampShader = ResourceLoader.Load<Shader>("res://scripts/app/clan_camp.gdshader");
        public static readonly Vector2 PAINT = new Vector2(1024.0, 2048.0);
        // tools/build_clan_art.py prints these: per stage, each banner's cloth (above its swallowtails), and the fire's middle
        public static readonly GArray BANNERS = GArray.Of(
            GArray.Of(new Rect2(564, 774, 91, 158)),
            GArray.Of(new Rect2(349, 787, 90, 176), new Rect2(649, 786, 99, 179)),
            GArray.Of(new Rect2(333, 730, 81, 146), new Rect2(473, 697, 87, 154), new Rect2(612, 734, 86, 153)),
            GArray.Of(new Rect2(38, 754, 61, 124), new Rect2(163, 758, 57, 120), new Rect2(289, 768, 61, 120), new Rect2(715, 777, 62, 102), new Rect2(932, 759, 64, 126))
        );
        public static readonly GArray FIRES = GArray.Of(new Vector2(520, 1182), new Vector2(522, 1217), new Vector2(520, 1202), new Vector2(525, 1162));
        public static readonly GArray FIRE_SIZE = GArray.Of(1.05, 0.85, 0.75, 1.3);         // (stage 3's fire is under the cauldron)
        public const double CREST_W = 0.74;                              // a banner's crest, of its width
        public static readonly Rect2 FLIES = new Rect2(80.0, 1000.0, 860.0, 420.0);
        public static readonly Rect2 SKY = new Rect2(0.0, 0.0, 1024.0, 560.0);        // where the stars are (and the falling ones go)
        // 0.31.216 (landscape): the band of the (portrait) painting a wide screen shows -- its banners down to just under the
        // fire, as tall as the screen; either side of it the painting again, wider, dark and soft (back)
        public static readonly Rect2 BAND = new Rect2(0.0, 640.0, 1024.0, 640.0);

        public int stage = 1;
        public string code = "";
        public string frame = "";
        public bool calm = false;
        public Control layer;
        public TextureRect art;
        public TextureRect back;                              // 0.31.216: the painting behind it all, darkened (landscape's sides)
        public GArray crests = new GArray();
        public TextureRect _halo;
        public TextureRect _heart;
        public CPUParticles2D _embers;
        public double _clock = 0.0;
        public GArray _stars = new GArray();                             // [TextureRect, rate, phase]
        public double k = 1.0;                                       // painting px -> this control's px
        public Vector2 origin = Vector2.ZERO;                         // the painting's top left here

        public void Setup(int st, string crest_code, string fr = "", bool reduce_motion = false)
        {
            stage = GD.Clampi(st, 1, 4);
            code = crest_code;
            frame = fr;
            calm = reduce_motion;
        }

        protected override void _Ready()
        {
            MouseFilter = Control.MOUSE_FILTER_IGNORE;
            ClipContents = true;
            back = new TextureRect();
            back.Texture = UI2.Tex(GD.Fmt("res://assets/ui/clans/camp_%d.webp", stage));
            back.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            back.StretchMode = TextureRect.STRETCH_SCALE;
            back.Modulate = new Color(0.32, 0.3, 0.38);
            back.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(back);
            layer = new Control();
            layer.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            layer.Size = PAINT;
            AddChild(layer);
            art = new TextureRect();
            art.Texture = UI2.Tex(GD.Fmt("res://assets/ui/clans/camp_%d.webp", stage));
            art.SetAnchorsPreset(Control.PRESET_TOP_LEFT);
            art.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            art.StretchMode = TextureRect.STRETCH_SCALE;
            art.Size = PAINT;
            art.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            art.SetMeta("clan_camp", stage);
            var m = new ShaderMaterial();
            m.Shader = CampShader;
            m.SetShaderParameter("paint_size", PAINT);
            m.SetShaderParameter("motion", calm ? 0.0 : 1.0);
            Vector2 fire = FIRES[stage - 1].V2;
            m.SetShaderParameter("fire", new Vector3(fire.x, fire.y, 300.0));
            var cloth = new GArray();
            foreach (var b in BANNERS[stage - 1])
            {
                Rect2 r = (Rect2)b;
                cloth.Append(new Vector4(r.position.x, r.position.y, r.End.x, r.End.y));
            }
            m.SetShaderParameter("cloth", cloth);
            m.SetShaderParameter("cloth_n", cloth.Size());
            var k = Crest.Colors(code);
            m.SetShaderParameter("recolor", k.IsEmpty() ? 0.0 : 1.0);
            if (!k.IsEmpty())
            {
                Color fc = (Color)k["field"];
                m.SetShaderParameter("field_col", new Vector3(fc.r, fc.g, fc.b));
            }
            art.Material = m;
            layer.AddChild(art);
            // the crest on each banner
            foreach (var b in BANNERS[stage - 1])
            {
                Rect2 r = (Rect2)b;
                var c = new Crest();
                c.SetCrest(code, frame);
                var w = r.size.x * CREST_W;
                c.Size = new Vector2(w, w * Crest.ASPECT);
                c.Position = new Vector2(r.position.x + (r.size.x - w) * 0.5, r.position.y + r.size.y * 0.47 - c.Size.y * 0.5);
                c.SetMeta("banner_crest", true);
                layer.AddChild(c);
                crests.Append(c);
            }
            // the fire
            double s = (double)FIRE_SIZE[stage - 1];
            _halo = _Glow(fire + new Vector2(0, -10) * s, new Vector2(380, 300) * s, new Color(1.0, 0.5, 0.18, 0.3));
            _heart = _Glow(fire + new Vector2(0, -12) * s, new Vector2(70, 60) * s, new Color(1.0, 0.9, 0.6, 0.55));
            if (!calm)
            {
                _embers = new CPUParticles2D();
                _embers.Position = fire + new Vector2(0, -24) * s;
                _embers.Amount = 18;
                _embers.Lifetime = 2.2;
                _embers.Preprocess = 2.2;
                _embers.Texture = CampScene._DotTex();
                _embers.LocalCoords = false;
                var g = new Gradient();
                g.SetColor(0, new Color(1.0, 0.95, 0.7, 1.0));
                g.AddPoint(0.4, new Color(1.0, 0.6, 0.2, 0.9));
                g.SetColor(g.GetPointCount() - 1, new Color(0.9, 0.2, 0.05, 0.0));
                _embers.ColorRamp = g;
                var add = new CanvasItemMaterial();
                add.BlendMode = CanvasBlendMode.Add;
                _embers.Material = add;
                _embers.EmissionShape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE;
                _embers.EmissionRectExtents = new Vector2(26, 10) * s;
                _embers.Direction = new Vector2(0, -1);
                _embers.Spread = 22.0;
                _embers.Gravity = new Vector2(0, -25);
                _embers.InitialVelocityMin = 40.0;
                _embers.InitialVelocityMax = 95.0;
                _embers.TangentialAccelMin = -25.0;
                _embers.TangentialAccelMax = 25.0;
                _embers.ScaleAmountMin = 0.16;
                _embers.ScaleAmountMax = 0.36;
                layer.AddChild(_embers);
                var flies = new CampScene.Fireflies();
                flies.tex = CampScene.GlowTexture();
                flies.area = FLIES;
                flies.Setup(10);
                layer.AddChild(flies);
            }
            // the night sky: stars that twinkle, and now and then one that falls
            var rng = new Rng();
            rng.Seed = 197;
            for (int i = 0; i < 26; i++)
            {
                var at = new Vector2(rng.RandfRange(20.0, 980.0), rng.RandfRange(16.0, SKY.End.y - 40.0));
                var st = _Glow(at, Vector2.ONE * rng.RandfRange(10.0, 18.0), new Color(0.95, 0.93, 1.0, calm ? 0.35 : 0.0));
                _stars.Append(GArray.Of(st, rng.RandfRange(0.4, 1.2), rng.Randf() * GD.TAU));
            }
            if (!calm)
            {
                var fall = new CampScene.FallingStar();
                fall.tex = CampScene.GlowTexture();
                fall.area = SKY;
                fall.wait = 5.0;
                layer.AddChild(fall);
            }
            _Fit();
        }

        public TextureRect _Glow(Vector2 centre, Vector2 sz, Color col)
        {
            var t = new TextureRect();
            t.Texture = CampScene.GlowTexture();
            t.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            t.StretchMode = TextureRect.STRETCH_SCALE;
            t.Size = sz;
            t.PivotOffset = sz * 0.5;
            t.Position = centre - sz * 0.5;
            t.Modulate = col;
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            var mat = new CanvasItemMaterial();
            mat.BlendMode = CanvasBlendMode.Add;
            t.Material = mat;
            layer.AddChild(t);
            return t;
        }

        public override void _Notification(int what)
        {
            if (what == NOTIFICATION_RESIZED)
                _Fit();
        }

        public void _Fit()
        {
            // the painting covers this control (centred: a phone longer than 1:2 loses a little of its sides)
            if (layer == null || Size.x <= 0.0 || Size.y <= 0.0)
                return;
            k = GD.Maxf((double)Size.x / PAINT.x, (double)Size.y / PAINT.y);
            origin = ((Size - PAINT * k) * 0.5).Round();
            if (Size.x > Size.y)
            {
                // 0.31.216 (landscape): the band from the banners to the fire, as tall as the screen; the darkened painting on
                // the sides (cover-scaled about the same band)
                var kb = GD.Maxf((double)Size.x / PAINT.x, (double)Size.y / BAND.size.y);
                back.Size = PAINT * kb;
                back.Position = new Vector2((Size.x - PAINT.x * kb) * 0.5, GD.Clampf(Size.y * 0.5 - BAND.GetCenter().y * kb, Size.y - PAINT.y * kb, 0.0));
                k = GD.Minf(k, (double)Size.y / BAND.size.y);
                origin = new Vector2((Size.x - PAINT.x * k) * 0.5, -BAND.position.y * k).Round();
            }
            back.Visible = Size.x > Size.y && PAINT.x * k < Size.x - 0.5;
            layer.Position = origin;
            layer.Scale = new Vector2(k, k);
        }

        public Vector2 ToScreen(Vector2 p)
        {
            // a point of the painting -> this control's px
            return origin + p * k;
        }

        protected override void _Process(double delta)
        {
            if (calm || !IsVisibleInTree() || art == null)
                return;
            _clock += delta;
            var t = _clock;
            var flick = 0.55 * GD.Sin(t * 7.3) + 0.3 * GD.Sin(t * 13.1 + 1.3) + 0.15 * GD.Sin(t * 2.1 + 0.4);
            { var mc = _heart.Modulate; mc.a = (float)(0.5 + 0.16 * flick); _heart.Modulate = mc; }
            _heart.Scale = Vector2.ONE * (0.95 + 0.08 * flick);
            { var mc = _halo.Modulate; mc.a = (float)(0.28 + 0.07 * flick); _halo.Modulate = mc; }
            _halo.Scale = Vector2.ONE * (0.97 + 0.05 * flick);
            var m = art.Material as ShaderMaterial;
            m.SetShaderParameter("clock", t);
            m.SetShaderParameter("fire_flick", flick);
            foreach (var st in _stars)
            {
                var tr = st[0].As<TextureRect>();
                { var mc = tr.Modulate; mc.a = (float)(0.8 * GD.Pow(GD.Maxf(0.0, GD.Sin(t * (double)st[1] + (double)st[2])), 3.0)); tr.Modulate = mc; }
            }
        }
    }
}
