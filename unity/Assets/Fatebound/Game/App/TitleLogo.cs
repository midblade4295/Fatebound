// Ported from godot/scripts/app/title_logo.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;
using Material = Fatebound.GUI.GMaterial;
using UI = Fatebound.Game.Ui;
using UI2 = Fatebound.Game.Ui2;
using RiftFx = Fatebound.Game.TitleRiftFx;

namespace Fatebound.Game
{
    // The title (0.31.193, Kevin: "Let's make a brand new title graphic that fits new game style" -> C4: "make the flags on
    // side blow around and the lighting effect in middle show effects"): FATEBOUND split by a white-hot rift, FATE in ice
    // blue, BOUND in fire, a crown over the split, a team flag at each end. Layers cut from one painting
    // (tools/build_title_logo.py): the word with the crown and the rift; the two flags behind it, each waving from its pole
    // (title_flag.gdshader); the rift crackling with lightning, its glow flickering, sparks spitting off it
    // (title_rift_fx.gd). Still with Reduce Motion (and as the title screen's afterimages). Width sets the size (height
    // follows); without the ui pack's art it falls back to text.
    // (0.31.113-0.31.192: "All Tied Up" -- the rope-bound title with the captured King swinging from the knot.)
    public class TitleLogo : Control
    {
        public static readonly Shader FLAG_SHADER = ResourceLoader.Load<Shader>("res://scripts/app/title_flag.gdshader");

        public static readonly Vector2 BASE = new Vector2(1400, 632);                                       // title_rift_base.webp
        public static readonly GArray FLAG_L = GArray.Of(new Vector2(0.0, 153.1), new Vector2(161, 369));               // title_flag_l.webp: its corner on the base, its size
        public static readonly GArray FLAG_R = GArray.Of(new Vector2(1233.2, 153.1), new Vector2(167, 354));            // title_flag_r.webp
        // each pole's line in its flag's own px, (y, x) by y (the cloth waves with its distance from it)
        public static readonly GArray POLE_L = GArray.Of(new Vector2(0.7, 102.5), new Vector2(48.5, 114.8), new Vector2(110.1, 133.3), new Vector2(144.2, 140.1),
            new Vector2(260.4, 140.1), new Vector2(383.5, 126.5), new Vector2(522.9, 119.6));
        public static readonly GArray POLE_R = GArray.Of(new Vector2(0.7, 63.6), new Vector2(48.5, 55.4), new Vector2(82.7, 45.1), new Vector2(130.6, 31.4), new Vector2(157.9, 39.6),
            new Vector2(228.3, 54.0), new Vector2(269.3, 60.8), new Vector2(301.5, 69.0), new Vector2(522.9, 69.0));
        public static readonly GArray GLOW = GArray.Of(new Vector2(605.0, 168.8), new Vector2(120, 438));               // title_rift_glow.webp
        // the rift's middle, top to bottom (base px)
        public static readonly GArray RIFT = GArray.Of(new Vector2(634.9, 204.4), new Vector2(639.8, 212.6), new Vector2(646.3, 220.8), new Vector2(653.7, 229.0), new Vector2(667.0, 237.2),
            new Vector2(667.1, 245.4), new Vector2(664.9, 253.6), new Vector2(662.2, 261.8), new Vector2(659.7, 270.0), new Vector2(656.9, 278.2),
            new Vector2(654.5, 286.4), new Vector2(651.9, 294.6), new Vector2(649.4, 302.8), new Vector2(650.4, 311.0), new Vector2(658.5, 319.2),
            new Vector2(665.3, 327.4), new Vector2(672.7, 335.6), new Vector2(680.1, 343.8), new Vector2(678.5, 352.1), new Vector2(673.8, 360.3),
            new Vector2(668.7, 368.5), new Vector2(664.8, 376.7), new Vector2(660.7, 384.9), new Vector2(657.7, 393.1), new Vector2(664.3, 401.3),
            new Vector2(672.0, 409.5), new Vector2(679.2, 417.7), new Vector2(676.5, 425.9), new Vector2(671.1, 434.1), new Vector2(665.8, 442.3),
            new Vector2(660.4, 450.5), new Vector2(656.2, 458.7), new Vector2(662.6, 466.9), new Vector2(669.1, 475.1), new Vector2(672.1, 483.3),
            new Vector2(666.0, 491.5), new Vector2(660.7, 499.7), new Vector2(656.4, 507.9), new Vector2(661.4, 516.1), new Vector2(666.3, 524.3),
            new Vector2(669.0, 532.5));
        public const double FLAG_AMP = 6.0;                   // the flags' swing (flag px) in a steady breeze
        public const double KICK_BOOST = 2.6;                 // ...times this much more, dying away, after the title's slam

        public bool calm = false;
        public double t = 0.0;
        public double boost = 0.0;                        // the flags' extra swing (the slam), dying away
        public TextureRect flag_l;
        public TextureRect flag_r;
        public RiftFx rift;                               // title_rift_fx.gd
        public TextureRect _base;

        public static double Aspect()
        {
            return (double)BASE.y / BASE.x;
        }

        public TitleLogo(bool still = false)
        {
            calm = still;
            MouseFilter = Control.MOUSE_FILTER_IGNORE;
            var bt = UI2.Tex(UI2.V2 + "title_rift_base.webp");
            var lt = UI2.Tex(UI2.V2 + "title_flag_l.webp");
            var rt = UI2.Tex(UI2.V2 + "title_flag_r.webp");
            var gt = UI2.Tex(UI2.V2 + "title_rift_glow.webp");
            if (bt == null || lt == null || rt == null || gt == null)
            {
                _Fallback();
                return;
            }
            flag_l = _Layer(lt);                 // (behind the word: the poles go behind its outline)
            flag_r = _Layer(rt);
            flag_l.Material = _FlagMat(lt, POLE_L, 1.0, 0.0);
            flag_r.Material = _FlagMat(rt, POLE_R, -1.0, 0.37);
            _base = _Layer(bt);
            rift = new RiftFx(gt, still);
            var pts = new List<Vector2>();
            foreach (var q in RIFT)
                pts.Add(q.V2);
            rift.line = pts;
            AddChild(rift);
            Resized += _Lay;
        }

        public TextureRect _Layer(Texture2D tx)
        {
            var r = new TextureRect();
            r.Texture = tx;
            r.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            r.StretchMode = TextureRect.STRETCH_SCALE;
            r.TextureFilter = TextureFilterMode.LinearWithMipmaps;
            r.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(r);
            return r;
        }

        public ShaderMaterial _FlagMat(Texture2D tx, GArray pole, double side, double phase)
        {
            var m = new ShaderMaterial();
            m.Shader = FLAG_SHADER;
            m.SetShaderParameter("tex_px", tx.GetSize());
            var pts = new List<Vector2>();
            foreach (var q in pole)
                pts.Add(q.V2);
            while (pts.Count < 10)
                pts.Add(pts[pts.Count - 1]);
            m.SetShaderParameter("pole", pts.ToArray());
            m.SetShaderParameter("pole_n", pole.Size());
            m.SetShaderParameter("side", side);
            m.SetShaderParameter("amp", calm ? 0.0 : FLAG_AMP);
            m.SetShaderParameter("reach", 130.0);
            m.SetShaderParameter("t", phase);
            m.SetMeta("phase", phase);          // (the two flags out of step)
            return m;
        }

        protected override void _Ready()
        {
            if (_base != null)
                _Lay();                              // (sized before it went in)
        }

        public void _Lay()
        {
            double s = (double)Size.x / BASE.x;
            _base.Position = Vector2.ZERO;
            _base.Size = BASE * s;
            flag_l.Position = FLAG_L[0].V2 * s;
            flag_l.Size = FLAG_L[1].V2 * s;
            flag_r.Position = FLAG_R[0].V2 * s;
            flag_r.Size = FLAG_R[1].V2 * s;
            rift.Position = Vector2.ZERO;
            rift.Size = BASE * s;
            rift.Lay(s, new Rect2(GLOW[0].V2, GLOW[1].V2));
        }

        public void Kick(double deg)
        {
            // the title slamming onto the wall: the flags whip about, the rift flares (deg: the slam's strength, title_screen.gd
            // KICK_DEG)
            if (_base == null || calm)
                return;
            boost = KICK_BOOST * GD.Clampf(deg / 32.0, 0.0, 1.5);
            rift.Burst(1.0);
        }

        public void SetShine(Material mat)
        {
            // 0.31.141: a material on the lettering (the title screen's gold glint)
            if (_base != null)
                _base.Material = mat;
        }

        public double FlagAmp()
        {
            return flag_l != null ? GD.Float(Var.Of((flag_l.Material as ShaderMaterial).GetShaderParameter("amp"))) : 0.0;
        }

        protected override void _Process(double delta)
        {
            if (_base == null || calm)
                return;
            t += delta;
            boost *= Math.Exp(-delta / 0.9);
            foreach (var f in new[] { flag_l, flag_r })
            {
                var m = (f as TextureRect).Material as ShaderMaterial;
                m.SetShaderParameter("t", t + GD.Float(Var.Of(m.GetMeta("phase"))));
                m.SetShaderParameter("amp", FLAG_AMP * (1.0 + boost));
            }
        }

        public void _Fallback()
        {
            // the text title, if the ui pack's art isn't there
            var v = new VBoxContainer();
            v.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            v.Alignment = BoxContainer.ALIGNMENT_CENTER;
            v.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(v);
            var logo = UI2.Text(v, "FATEBOUND", 50, UI2.GOLD, UI2.INK, 13);
            logo.AddThemeColorOverride("font_shadow_color", new Color(0.1, 0.05, 0.0, 0.85));
            logo.AddThemeConstantOverride("shadow_offset_y", 6);
            logo.HorizontalAlignment = HorizontalAlignment.Center;
        }
    }
}
