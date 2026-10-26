// Fatebound GUI (Unity port): Godot's StyleBoxes -- content margins, minimum size, and the drawing: StyleBoxFlat is
// style_box_flat.cpp's draw ported line for line (adapted borders/corners, ring and fill triangulation, shadow, AA
// feathers of aa_size device pixels), StyleBoxTexture a nine-patch, StyleBoxLine a line. Script styles (tactile_style,
// brass_style) subclass StyleBox and override Draw.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public abstract class StyleBox : Resource
    {
        /// <summary>The canvas oversampling while items redraw (TextServer::get_current_drawn_item_oversampling).</summary>
        public static float CurrentOversampling = 1f;

        protected readonly float[] contentMargin = { -1f, -1f, -1f, -1f };

        public double ContentMarginLeft { get => contentMargin[0]; set { contentMargin[0] = (float)value; EmitChanged(); } }
        public double ContentMarginTop { get => contentMargin[1]; set { contentMargin[1] = (float)value; EmitChanged(); } }
        public double ContentMarginRight { get => contentMargin[2]; set { contentMargin[2] = (float)value; EmitChanged(); } }
        public double ContentMarginBottom { get => contentMargin[3]; set { contentMargin[3] = (float)value; EmitChanged(); } }

        public void SetContentMargin(Side s, double v) { contentMargin[(int)s] = (float)v; EmitChanged(); }
        public void SetContentMarginAll(double v) { for (int i = 0; i < 4; i++) contentMargin[i] = (float)v; EmitChanged(); }
        public double GetContentMargin(Side s) => contentMargin[(int)s];

        /// <summary>get_margin: the content margin when set (&gt;= 0), else the style's own (border widths ...).</summary>
        public float GetMargin(Side s)
        {
            float m = contentMargin[(int)s];
            return m < 0f ? GetStyleMargin(s) : m;
        }

        protected virtual float GetStyleMargin(Side s) => 0f;

        public virtual Vec2 GetMinimumSize() =>
            new Vec2(GetMargin(Side.Left) + GetMargin(Side.Right), GetMargin(Side.Top) + GetMargin(Side.Bottom));

        public Vec2 GetOffset() => new Vec2(GetMargin(Side.Left), GetMargin(Side.Top));

        public abstract void Draw(DrawList ci, Rect2 rect);

        public virtual Rect2 GetDrawRect(Rect2 rect) => rect;

        public virtual bool TestMask(Vec2 point, Rect2 rect) => true;

        public override Resource Duplicate(bool deep = false)
        {
            var o = (StyleBox)MemberwiseClone();
            Array.Copy(contentMargin, o.contentMargin, 4);
            return o;
        }
    }

    public sealed class StyleBoxEmpty : StyleBox
    {
        public override void Draw(DrawList ci, Rect2 rect) { }
    }

    public sealed class StyleBoxFlat : StyleBox
    {
        Col _bg = new Col(0.6f, 0.6f, 0.6f, 1f);
        Col _border = new Col(0.8f, 0.8f, 0.8f, 1f);
        Col _shadow = new Col(0f, 0f, 0f, 0.6f);
        readonly float[] _bw = new float[4];
        readonly float[] _cr = new float[4];
        readonly float[] _em = new float[4];
        public bool DrawCenter = true;
        public bool BorderBlend;
        public Vec2 Skew;
        public int ShadowSize;
        public Vec2 ShadowOffset;
        public bool AntiAliasing = true;
        public double AntiAliasingSize = 1.0;
        int _detail = 8;

        public Col BgColor { get => _bg; set { _bg = value; EmitChanged(); } }
        public Col BorderColor { get => _border; set { _border = value; EmitChanged(); } }
        public Col ShadowColor { get => _shadow; set { _shadow = value; EmitChanged(); } }
        public int CornerDetail { get => _detail; set => _detail = Math.Max(1, Math.Min(20, value)); }

        public int BorderWidthLeft { get => (int)_bw[0]; set => _bw[0] = value; }
        public int BorderWidthTop { get => (int)_bw[1]; set => _bw[1] = value; }
        public int BorderWidthRight { get => (int)_bw[2]; set => _bw[2] = value; }
        public int BorderWidthBottom { get => (int)_bw[3]; set => _bw[3] = value; }
        public void SetBorderWidthAll(int w) { for (int i = 0; i < 4; i++) _bw[i] = w; EmitChanged(); }
        public void SetBorderWidth(Side s, int w) { _bw[(int)s] = w; EmitChanged(); }
        public int GetBorderWidth(Side s) => (int)_bw[(int)s];
        public int GetBorderWidthMin() => (int)Math.Min(Math.Min(_bw[0], _bw[1]), Math.Min(_bw[2], _bw[3]));

        public int CornerRadiusTopLeft { get => (int)_cr[0]; set => _cr[0] = value; }
        public int CornerRadiusTopRight { get => (int)_cr[1]; set => _cr[1] = value; }
        public int CornerRadiusBottomRight { get => (int)_cr[2]; set => _cr[2] = value; }
        public int CornerRadiusBottomLeft { get => (int)_cr[3]; set => _cr[3] = value; }
        public void SetCornerRadiusAll(int r) { for (int i = 0; i < 4; i++) _cr[i] = r; EmitChanged(); }
        public void SetCornerRadius(Corner c, int r) { _cr[(int)c] = r; EmitChanged(); }
        public int GetCornerRadius(Corner c) => (int)_cr[(int)c];

        public double ExpandMarginLeft { get => _em[0]; set => _em[0] = (float)value; }
        public double ExpandMarginTop { get => _em[1]; set => _em[1] = (float)value; }
        public double ExpandMarginRight { get => _em[2]; set => _em[2] = (float)value; }
        public double ExpandMarginBottom { get => _em[3]; set => _em[3] = (float)value; }
        public void SetExpandMarginAll(double m) { for (int i = 0; i < 4; i++) _em[i] = (float)m; EmitChanged(); }
        public void SetExpandMargin(Side s, double m) { _em[(int)s] = (float)m; EmitChanged(); }

        protected override float GetStyleMargin(Side s) => _bw[(int)s];

        public override Resource Duplicate(bool deep = false)
        {
            var o = (StyleBoxFlat)base.Duplicate(deep);
            var f = typeof(StyleBoxFlat);
            // arrays are readonly fields: copy element-wise into fresh ones via reflection-free clone
            var c = new StyleBoxFlat();
            Array.Copy(contentMargin, c.contentMargin, 4);
            Array.Copy(_bw, c._bw, 4);
            Array.Copy(_cr, c._cr, 4);
            Array.Copy(_em, c._em, 4);
            c._bg = _bg; c._border = _border; c._shadow = _shadow; c.DrawCenter = DrawCenter; c.BorderBlend = BorderBlend;
            c.Skew = Skew; c.ShadowSize = ShadowSize; c.ShadowOffset = ShadowOffset; c.AntiAliasing = AntiAliasing;
            c.AntiAliasingSize = AntiAliasingSize; c._detail = _detail;
            _ = o; _ = f;
            return c;
        }

        public override Rect2 GetDrawRect(Rect2 r)
        {
            Rect2 dr = r.GrowIndividual(_em[0], _em[1], _em[2], _em[3]);
            if (ShadowSize > 0)
            {
                Rect2 sr = dr.Grow(ShadowSize);
                sr.position = sr.position + ShadowOffset;
                dr = dr.Merge(sr);
            }
            return dr;
        }

        // ---------- style_box_flat.cpp ----------
        static void SetInnerCornerRadius(Rect2 style, Rect2 inner, float[] cr, float[] icr)
        {
            float bl = inner.position.x - style.position.x;
            float bt = inner.position.y - style.position.y;
            float br = style.size.x - inner.size.x - bl;
            float bb = style.size.y - inner.size.y - bt;
            icr[0] = Math.Max(cr[0] - Math.Min(bt, bl), 0f);
            icr[1] = Math.Max(cr[1] - Math.Min(bt, br), 0f);
            icr[2] = Math.Max(cr[2] - Math.Min(bb, br), 0f);
            icr[3] = Math.Max(cr[3] - Math.Min(bb, bl), 0f);
        }

        static Vec2 MinF(Vec2 v, float m) => new Vec2(Math.Min(v.x, m), Math.Min(v.y, m));
        static Vec2 MaxF(Vec2 v, float m) => new Vec2(Math.Max(v.x, m), Math.Max(v.y, m));

        static void SetCornerScale(Rect2 style, Rect2 inner, float[] cr, Vec2[] scale)
        {
            float bl = inner.position.x - style.position.x;
            float bt = inner.position.y - style.position.y;
            float br = style.size.x - inner.size.x - bl;
            float bb = style.size.y - inner.size.y - bt;
            float[] overflow =
            {
                -Math.Min(0f, inner.size.y - cr[0] - cr[3]),
                -Math.Min(0f, inner.size.x - cr[0] - cr[1]),
                -Math.Min(0f, inner.size.y - cr[1] - cr[2]),
                -Math.Min(0f, inner.size.x - cr[3] - cr[2]),
            };
            float hb = bl + br, vb = bt + bb;
            float[] ratios = { hb > 0 ? bl / hb : 0, vb > 0 ? bt / vb : 0, hb > 0 ? br / hb : 0, vb > 0 ? bb / vb : 0 };
            Vec2[] red =
            {
                new Vec2(overflow[1] * ratios[0], overflow[0] * ratios[1]),
                new Vec2(overflow[1] * ratios[2], overflow[2] * ratios[1]),
                new Vec2(overflow[3] * ratios[2], overflow[2] * ratios[3]),
                new Vec2(overflow[3] * ratios[0], overflow[0] * ratios[3]),
            };
            var pcr = new Vec2[4];
            for (int i = 0; i < 4; i++) pcr[i] = new Vec2(cr[i], cr[i]);
            var left = new Vec2[4];
            for (int i = 0; i < 4; i++) left[i] = -MinF(pcr[i] - red[i], 0f);
            Vec2[] dist =
            {
                MaxF(pcr[0] - red[0] - left[3] - left[1], 0f),
                MaxF(pcr[1] - red[1] - left[0] - left[2], 0f),
                MaxF(pcr[2] - red[2] - left[1] - left[3], 0f),
                MaxF(pcr[3] - red[3] - left[2] - left[0], 0f),
            };
            for (int i = 0; i < 4; i++)
            {
                Vec2 un = MaxF(left[(i + 1) % 4] + left[(i + 3) % 4] - dist[i], 0f);
                Vec2 den = MaxF(pcr[i] - un, 1.1920929e-07f);
                scale[i] = new Vec2(dist[i].x / den.x, dist[i].y / den.y);
            }
        }

        static void RoundedRect(List<Vec2> verts, List<int> indices, List<Col> colors, Rect2 style, float[] cr, Rect2 ring, Rect2 inner,
            Col innerColor, Col outerColor, int detail, Vec2 skew, bool filled = false)
        {
            int vOff = verts.Count;
            int ad = (cr[0] > 0 || cr[1] > 0 || cr[2] > 0 || cr[3] > 0) ? detail : 1;
            bool border = !filled;
            var rcr = new float[4];
            SetInnerCornerRadius(style, ring, cr, rcr);
            var rs = new Vec2[4];
            SetCornerScale(style, ring, rcr, rs);
            Vec2[] outer =
            {
                ring.position + new Vec2(rcr[0], rcr[0]) * rs[0],
                new Vec2(ring.position.x + ring.size.x - rcr[1] * rs[1].x, ring.position.y + rcr[1] * rs[1].y),
                ring.position + ring.size - new Vec2(rcr[2], rcr[2]) * rs[2],
                new Vec2(ring.position.x + rcr[3] * rs[3].x, ring.position.y + ring.size.y - rcr[3] * rs[3].y),
            };
            var icr = new float[4];
            SetInnerCornerRadius(style, inner, cr, icr);
            var isc = new Vec2[4];
            SetCornerScale(style, inner, icr, isc);
            Vec2[] innerP =
            {
                inner.position + new Vec2(icr[0], icr[0]) * isc[0],
                new Vec2(inner.position.x + inner.size.x - icr[1] * isc[1].x, inner.position.y + icr[1] * isc[1].y),
                inner.position + inner.size - new Vec2(icr[2], icr[2]) * isc[2],
                new Vec2(inner.position.x + icr[3] * isc[3].x, inner.position.y + inner.size.y - icr[3] * isc[3].y),
            };
            float quarter = (float)(Math.PI / 2.0);
            Vec2 center = style.GetCenter();
            int newCount = (ad + 1) * (border ? 8 : 4);
            int baseV = verts.Count;
            for (int k = 0; k < newCount; k++) { verts.Add(Vec2.Zero); colors.Add(Col.WHITE); }
            for (int c = 0; c < 4; c++)
                for (int dd = 0; dd <= ad; dd++)
                {
                    int io = (ad + 1) * c + dd;
                    if (border) io *= 2;
                    float ang = (float)((c + dd / (double)ad) * quarter + Math.PI);
                    float co = MathF.Cos(ang), si = MathF.Sin(ang);
                    {
                        float x = icr[c] * co * isc[c].x + innerP[c].x;
                        float y = icr[c] * si * isc[c].y + innerP[c].y;
                        float xs = -skew.x * (y - center.y), ys = -skew.y * (x - center.x);
                        verts[baseV + io] = new Vec2(x + xs, y + ys);
                        colors[baseV + io] = innerColor;
                    }
                    if (border)
                    {
                        float x = rcr[c] * co * rs[c].x + outer[c].x;
                        float y = rcr[c] * si * rs[c].y + outer[c].y;
                        float xs = -skew.x * (y - center.y), ys = -skew.y * (x - center.x);
                        verts[baseV + io + 1] = new Vec2(x + xs, y + ys);
                        colors[baseV + io + 1] = outerColor;
                    }
                }
            int ringCount = verts.Count - vOff;
            if (border)
                for (int i = 0; i < ringCount; i++)
                {
                    indices.Add(vOff + i % ringCount);
                    indices.Add(vOff + (i + 2) % ringCount);
                    indices.Add(vOff + (i + 1) % ringCount);
                }
            if (filled)
            {
                int stripes = ringCount / 2 - 1;
                int last = ringCount - 1;
                for (int i = 0; i < stripes; i++)
                {
                    indices.Add(vOff + i); indices.Add(vOff + last - i - 1); indices.Add(vOff + i + 1);
                    indices.Add(vOff + i); indices.Add(vOff + last - i); indices.Add(vOff + last - i - 1);
                }
            }
        }

        static void Adapt(int a, int b, float[] adapted, float[] values, float width, float maxA, float maxB)
        {
            float va = values[a], vb = values[b];
            float factor = Math.Min(1f, width / (va + vb));
            adapted[a] = Math.Min(Math.Min(va * factor, maxA), adapted[a]);
            adapted[b] = Math.Min(Math.Min(vb * factor, maxB), adapted[b]);
        }

        public override void Draw(DrawList ci, Rect2 rect)
        {
            bool drawBorder = _bw[0] > 0 || _bw[1] > 0 || _bw[2] > 0 || _bw[3] > 0;
            bool drawShadow = ShadowSize > 0;
            if (!drawBorder && !DrawCenter && !drawShadow) return;
            Rect2 style = rect.GrowIndividual(_em[0], _em[1], _em[2], _em[3]);
            if (Math.Abs(style.size.x) < 1e-5f || Math.Abs(style.size.y) < 1e-5f) return;
            bool rounded = _cr[0] > 0 || _cr[1] > 0 || _cr[2] > 0 || _cr[3] > 0;
            bool aaOn = (rounded || !(Math.Abs(Skew.x) < 1e-5f && Math.Abs(Skew.y) < 1e-5f)) && AntiAliasing;
            bool blendOn = BorderBlend && drawBorder;
            Col borderAlpha = new Col(_border.r, _border.g, _border.b, 0f);
            Col borderBlend = DrawCenter ? _bg : borderAlpha;
            Col borderInner = blendOn ? borderBlend : _border;
            float width = Math.Max(style.size.x, 0f), height = Math.Max(style.size.y, 0f);
            var ab = new float[] { 1000000f, 1000000f, 1000000f, 1000000f };
            Adapt(1, 3, ab, _bw, height, height, height);
            Adapt(0, 2, ab, _bw, width, width, width);
            var ac = new float[] { 1000000f, 1000000f, 1000000f, 1000000f };
            Adapt(1, 2, ac, _cr, height, height - ab[3], height - ab[1]);
            Adapt(0, 3, ac, _cr, height, height - ab[3], height - ab[1]);
            Adapt(0, 1, ac, _cr, width, width - ab[2], width - ab[0]);
            Adapt(3, 2, ac, _cr, width, width - ab[2], width - ab[0]);
            Rect2 infill = style.GrowIndividual(-ab[0], -ab[1], -ab[2], -ab[3]);
            Rect2 bsr = style;
            float aa = 1f;
            if (aaOn)
            {
                float sf = CurrentOversampling == 0f ? 1f : CurrentOversampling;
                aa = (float)AntiAliasingSize / sf;
                for (int i = 0; i < 4; i++)
                    if (_bw[i] > 0) bsr = bsr.GrowSide(i, -aa);
            }
            var verts = new List<Vec2>();
            var indices = new List<int>();
            var colors = new List<Col>();
            if (drawShadow)
            {
                Rect2 sin = style;
                sin.position = sin.position + ShadowOffset;
                Rect2 sr = style.Grow(ShadowSize);
                sr.position = sr.position + ShadowOffset;
                Col st = new Col(_shadow.r, _shadow.g, _shadow.b, 0f);
                RoundedRect(verts, indices, colors, sin, ac, sr, sin, _shadow, st, _detail, Skew);
                if (DrawCenter) RoundedRect(verts, indices, colors, sin, ac, sin, sin, _shadow, _shadow, _detail, Skew, true);
            }
            if (drawBorder && !aaOn) RoundedRect(verts, indices, colors, bsr, ac, bsr, infill, borderInner, _border, _detail, Skew);
            if (DrawCenter && (!aaOn || blendOn)) RoundedRect(verts, indices, colors, bsr, ac, infill, infill, _bg, _bg, _detail, Skew, true);
            if (aaOn)
            {
                var abw = new float[4];
                var abwh = new float[4];
                var afw = new float[4];
                var afwh = new float[4];
                for (int i = 0; i < 4; i++)
                {
                    if (drawBorder && _bw[i] > 0) { abw[i] = aa; abwh[i] = aa * 0.5f; }
                    else { afw[i] = aa; afwh[i] = aa * 0.5f; }
                }
                if (DrawCenter)
                {
                    Rect2 tr = infill.GrowIndividual(afwh[0], afwh[1], afwh[2], afwh[3]);
                    Rect2 co = tr.GrowIndividual(-afw[0], -afw[1], -afw[2], -afw[3]);
                    if (!blendOn) RoundedRect(verts, indices, colors, bsr, ac, co, co, _bg, _bg, _detail, Skew, true);
                    if (!blendOn || !drawBorder)
                        RoundedRect(verts, indices, colors, bsr, ac, tr, co, _bg, new Col(_bg.r, _bg.g, _bg.b, 0f), _detail, Skew);
                }
                if (drawBorder)
                {
                    Rect2 innerCo = infill.GrowIndividual(abwh[0], abwh[1], abwh[2], abwh[3]);
                    Rect2 innerTr = innerCo.GrowIndividual(-abw[0], -abw[1], -abw[2], -abw[3]);
                    Rect2 outerTr = style.GrowIndividual(abwh[0], abwh[1], abwh[2], abwh[3]);
                    Rect2 outerCo = bsr.GrowIndividual(abwh[0], abwh[1], abwh[2], abwh[3]);
                    RoundedRect(verts, indices, colors, bsr, ac, outerCo, blendOn ? infill : innerCo, borderInner, _border, _detail, Skew);
                    if (!blendOn) RoundedRect(verts, indices, colors, bsr, ac, innerCo, innerTr, borderBlend, _border, _detail, Skew);
                    RoundedRect(verts, indices, colors, bsr, ac, outerTr, outerCo, _border, borderAlpha, _detail, Skew);
                }
            }
            ci.AddTriangles(indices, verts, colors);
        }
    }

    public sealed class StyleBoxTexture : StyleBox
    {
        public enum AxisStretchMode { Stretch = 0, Tile = 1, TileFit = 2 }
        public Texture2D Texture;
        readonly float[] _tm = new float[4];
        readonly float[] _em = new float[4];
        public Rect2 RegionRect;
        public Col ModulateColor = Col.WHITE;
        public bool DrawCenter = true;
        public AxisStretchMode AxisStretchHorizontal, AxisStretchVertical;

        public double TextureMarginLeft { get => _tm[0]; set => _tm[0] = (float)value; }
        public double TextureMarginTop { get => _tm[1]; set => _tm[1] = (float)value; }
        public double TextureMarginRight { get => _tm[2]; set => _tm[2] = (float)value; }
        public double TextureMarginBottom { get => _tm[3]; set => _tm[3] = (float)value; }
        public void SetTextureMarginAll(double m) { for (int i = 0; i < 4; i++) _tm[i] = (float)m; EmitChanged(); }
        public void SetTextureMargin(Side s, double m) { _tm[(int)s] = (float)m; EmitChanged(); }
        public double ExpandMarginLeft { get => _em[0]; set => _em[0] = (float)value; }
        public double ExpandMarginTop { get => _em[1]; set => _em[1] = (float)value; }
        public double ExpandMarginRight { get => _em[2]; set => _em[2] = (float)value; }
        public double ExpandMarginBottom { get => _em[3]; set => _em[3] = (float)value; }
        public void SetExpandMarginAll(double m) { for (int i = 0; i < 4; i++) _em[i] = (float)m; EmitChanged(); }

        protected override float GetStyleMargin(Side s) => _tm[(int)s];

        public override Rect2 GetDrawRect(Rect2 r) => r.GrowIndividual(_em[0], _em[1], _em[2], _em[3]);

        public override void Draw(DrawList ci, Rect2 rect)
        {
            if (Texture == null) return;
            Rect2 r = GetDrawRect(rect);
            Rect2 src = RegionRect.size.x == 0 && RegionRect.size.y == 0 ? new Rect2(Vec2.Zero, Texture.GetSize()) : RegionRect;
            ci.AddNinePatch(r, src, Texture, new Vec2(_tm[0], _tm[1]), new Vec2(_tm[2], _tm[3]),
                (DrawList.NinePatchAxis)AxisStretchHorizontal, (DrawList.NinePatchAxis)AxisStretchVertical, DrawCenter, ModulateColor);
        }
    }

    public sealed class StyleBoxLine : StyleBox
    {
        public Col Color = new Col(0f, 0f, 0f, 1f);
        public float GrowBegin = 1f, GrowEnd = 1f;
        public int Thickness = 1;
        public bool Vertical;

        public override void Draw(DrawList ci, Rect2 rect)
        {
            Rect2 r = rect;
            if (Vertical)
            {
                r.position = new Vec2(r.position.x + (r.size.x - Thickness) / 2f, r.position.y - GrowBegin);
                r.size = new Vec2(Thickness, r.size.y + GrowBegin + GrowEnd);
            }
            else
            {
                r.position = new Vec2(r.position.x - GrowBegin, r.position.y + (r.size.y - Thickness) / 2f);
                r.size = new Vec2(r.size.x + GrowBegin + GrowEnd, Thickness);
            }
            ci.AddRect(r, Color, false);
        }
    }
}
