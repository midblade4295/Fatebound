// Fatebound GUI (Unity port): Godot's CanvasItem (visibility, modulate, z index, top level, the _draw callback and the
// whole draw_* API), Node2D, Sprite2D, Polygon2D, CanvasLayer, the canvas materials, and the RenderingServer calls the
// UI code uses on a canvas item (custom StyleBoxes draw through those).
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public enum TextureFilterMode { ParentNode = 0, Nearest = 1, Linear = 2, NearestWithMipmaps = 3, LinearWithMipmaps = 4 }
    public enum TextureRepeatMode { ParentNode = 0, Disabled = 1, Enabled = 2, Mirror = 3 }

    public abstract class CanvasItem : Node
    {
        bool _visible = true;
        Col _modulate = Col.WHITE, _selfModulate = Col.WHITE;
        int _z;
        bool _zRelative = true;
        bool _topLevel;
        bool _showBehindParent;
        internal readonly DrawList drawList = new DrawList();
        internal bool drawDirty = true;
        bool _drawing;
        public GMaterial Material;
        public bool UseParentMaterial;
        public TextureFilterMode TextureFilter = TextureFilterMode.ParentNode;
        public TextureRepeatMode TextureRepeat = TextureRepeatMode.ParentNode;
        public int LightMask = 1;
        public uint VisibilityLayer = 1;

        /// <summary>The "draw" signal: fires inside the redraw, after _draw().</summary>
        public event Action Draw;
        public event Action VisibilityChanged, Hidden, ItemRectChanged;

        protected CanvasItem() { drawList.owner = this; }

        // ---------- properties ----------
        public bool Visible
        {
            get => _visible;
            set
            {
                if (_visible == value) return;
                _visible = value;
                QueueRedraw();
                PropagateVisibilityChanged(value);
                OnVisibilityChanged();
            }
        }

        public void Show() => Visible = true;
        public void Hide() => Visible = false;

        void PropagateVisibilityChanged(bool v)
        {
            if (!IsInsideTree()) return;
            _Notification(NOTIFICATION_VISIBILITY_CHANGED);
            VisibilityChanged?.Invoke();
            if (!v) Hidden?.Invoke();
            foreach (var c in children)
                if (c is CanvasItem ci && ci._visible && !ci.TopLevel) ci.PropagateVisibilityChanged(v);
        }

        protected virtual void OnVisibilityChanged() { }

        public bool IsVisibleInTree()
        {
            if (!IsInsideTree()) return false;
            for (Node n = this; n != null; n = n.Parent)
            {
                if (n is CanvasItem ci)
                {
                    if (!ci._visible) return false;
                    if (ci._topLevel && n != this) { }
                }
                else if (n is CanvasLayer cl) return cl.Visible;
                else if (n is Viewport) return true;
            }
            return true;
        }

        public Col Modulate
        {
            get => _modulate;
            set { if (_modulate != value) { _modulate = value; QueueRepaint(); } }
        }

        public Col SelfModulate
        {
            get => _selfModulate;
            set { if (_selfModulate != value) { _selfModulate = value; QueueRepaint(); } }
        }

        public int ZIndex { get => _z; set { _z = Math.Max(-4096, Math.Min(4096, value)); QueueRepaint(); } }
        public bool ZAsRelative { get => _zRelative; set { _zRelative = value; QueueRepaint(); } }
        public bool ShowBehindParent { get => _showBehindParent; set { _showBehindParent = value; QueueRepaint(); } }

        public bool TopLevel
        {
            get => _topLevel;
            set
            {
                if (_topLevel == value) return;
                _topLevel = value;
                OnTopLevelChanged();
                QueueRepaint();
            }
        }

        protected virtual void OnTopLevelChanged() { }

        /// <summary>Parent canvas item (null at a canvas root, under a CanvasLayer/Viewport/plain Node, or when top level).</summary>
        public CanvasItem GetParentItem() => _topLevel ? null : Parent as CanvasItem;

        // ---------- transforms ----------
        public abstract Xform2 GetTransform();

        public virtual Xform2 GetGlobalTransform()
        {
            var p = GetParentItem();
            return p != null ? p.GetGlobalTransform() * GetTransform() : GetTransform();
        }

        /// <summary>The canvas (CanvasLayer) transform this item is drawn under.</summary>
        public Xform2 GetCanvasTransform()
        {
            for (Node n = Parent; n != null; n = n.Parent)
            {
                if (n is CanvasLayer cl) return cl.Transform;
                if (n is Viewport) return Xform2.IDENTITY;
            }
            return Xform2.IDENTITY;
        }

        public Xform2 GetViewportTransform() => GetCanvasTransform();
        public Xform2 GetGlobalTransformWithCanvas() => GetCanvasTransform() * GetGlobalTransform();

        public CanvasLayer GetCanvasLayerNode()
        {
            for (Node n = Parent; n != null; n = n.Parent)
            {
                if (n is CanvasLayer cl) return cl;
                if (n is Viewport) return null;
            }
            return null;
        }

        public Vec2 GetGlobalMousePosition()
        {
            var vp = GetViewport();
            return vp == null ? Vec2.Zero : GetCanvasTransform().AffineInverse().Xform(vp.GetMousePosition());
        }

        public Vec2 GetLocalMousePosition() => GetGlobalTransform().AffineInverse().Xform(GetGlobalMousePosition());
        public Rect2 GetViewportRect() => GetViewport()?.GetVisibleRect() ?? new Rect2(0, 0, 760, 420);

        public InputEvent MakeInputLocal(InputEvent e) => e.XformedBy(GetGlobalTransformWithCanvas().AffineInverse());

        /// <summary>Local rect used for clipping children (Control: its rect).</summary>
        public virtual Rect2 GetItemRect() => new Rect2(0, 0, 0, 0);
        public virtual bool ClipsChildren => false;

        protected void EmitItemRectChanged() => ItemRectChanged?.Invoke();

        // ---------- redraw ----------
        /// <summary>queue_redraw(): _draw() runs again before the next frame is shown.</summary>
        public void QueueRedraw()
        {
            if (_drawing) return;
            drawDirty = true;
            GetViewport()?.MarkCanvasDirty();
        }

        /// <summary>Something that only changes how the recorded commands show (modulate, z): no _draw() needed.</summary>
        protected void QueueRepaint() => GetViewport()?.MarkCanvasDirty();

        protected virtual void _Draw() { }

        internal void Redraw()
        {
            drawList.Clear();
            drawDirty = false;
            if (!IsVisibleInTree()) { drawDirty = true; return; }
            _drawing = true;
            try
            {
                _Notification(NOTIFICATION_DRAW);
                OnDraw();
                _Draw();
                Draw?.Invoke();
            }
            catch (Exception ex) { GD_Log.Error("_draw " + Name + ": " + ex); }
            finally
            {
                drawList.SetTransform(Xform2.IDENTITY);
                _drawing = false;
            }
        }

        /// <summary>Built-in drawing of the node type itself (Label's text, Panel's stylebox ...), before the user _draw.</summary>
        protected virtual void OnDraw() { }

        public DrawList GetCanvasItem() => drawList;

        protected override void OnEnterTree()
        {
            drawDirty = true;
            GetViewport()?.MarkCanvasDirty();
        }

        protected override void OnExitTree()
        {
            GetViewport()?.MarkCanvasDirty();
        }

        protected override void MoveChildNotify(Node child) => QueueRepaint();

        // ---------- draw API ----------
        public void DrawSetTransform(Vec2 pos, double rot = 0.0, Vec2? scale = null) =>
            drawList.SetTransform(new Xform2(rot, scale ?? Vec2.One, 0.0, pos));

        public void DrawSetTransformMatrix(Xform2 xf) => drawList.SetTransform(xf);

        public void DrawLine(Vec2 from, Vec2 to, Col color, double width = -1.0, bool antialiased = false) =>
            drawList.AddLine(from, to, color, (float)width, antialiased);

        public void DrawDashedLine(Vec2 from, Vec2 to, Col color, double width = -1.0, double dash = 2.0, bool aligned = true, bool antialiased = false)
        {
            float length = (to - from).Length();
            Vec2 step = (to - from).Normalized() * (float)dash;
            if (length < dash || step == Vec2.Zero)
            {
                DrawLine(from, to, color, width, antialiased);
                return;
            }
            var pts = new List<Vec2>();
            int steps = aligned ? (int)Math.Ceiling(length / dash) : (int)Math.Floor(length / dash);
            if (steps % 2 == 0) steps--;
            Vec2 off = aligned ? Vec2.Zero : (to - from).Normalized() * (float)(length - steps * dash) / 2f;
            Vec2 p = from + off;
            for (int i = 0; i < steps; i += 2)
            {
                pts.Add(p);
                p = p + step;
                pts.Add(i + 1 >= steps ? to - off : p);
                p = p + step;
            }
            DrawMultiline(pts, color, width, antialiased);
        }

        public void DrawPolyline(IList<Vec2> points, Col color, double width = -1.0, bool antialiased = false) =>
            drawList.AddPolyline(points, new[] { color }, (float)width, antialiased);

        public void DrawPolylineColors(IList<Vec2> points, IList<Col> colors, double width = -1.0, bool antialiased = false) =>
            drawList.AddPolyline(points, colors, (float)width, antialiased);

        public void DrawArc(Vec2 center, double radius, double startAngle, double endAngle, int pointCount, Col color, double width = -1.0, bool antialiased = false) =>
            DrawEllipseArc(center, radius, radius, startAngle, endAngle, pointCount, color, width, antialiased);

        public void DrawEllipseArc(Vec2 center, double major, double minor, double startAngle, double endAngle, int pointCount, Col color, double width = -1.0, bool antialiased = false)
        {
            if (pointCount < 2) return;
            var pts = new Vec2[pointCount];
            float delta = (float)Math.Max(-Math.PI * 2, Math.Min(Math.PI * 2, endAngle - startAngle));
            float mj = (float)major, mn = (float)minor, sa = (float)startAngle;
            for (int i = 0; i < pointCount; i++)
            {
                float theta = (i / (pointCount - 1.0f)) * delta + sa;
                pts[i] = center + new Vec2(mj * MathF.Cos(theta), mn * MathF.Sin(theta));
            }
            DrawPolyline(pts, color, width, antialiased);
        }

        public void DrawMultiline(IList<Vec2> points, Col color, double width = -1.0, bool antialiased = false) =>
            drawList.AddMultiline(points, new[] { color }, (float)width, antialiased);

        public void DrawMultilineColors(IList<Vec2> points, IList<Col> colors, double width = -1.0, bool antialiased = false) =>
            drawList.AddMultiline(points, colors, (float)width, antialiased);

        public void DrawRect(Rect2 rect, Col color, bool filled = true, double width = -1.0, bool antialiased = false)
        {
            Rect2 r = rect.Abs();
            float w = (float)width;
            if (filled) drawList.AddRect(r, color, antialiased);
            else if (w >= r.size.x || w >= r.size.y) drawList.AddRect(r.Grow(0.5f * w), color, antialiased);
            else
            {
                var pts = new[]
                {
                    r.position, r.position + new Vec2(r.size.x, 0f), r.position + r.size, r.position + new Vec2(0f, r.size.y), r.position,
                };
                drawList.AddPolyline(pts, new[] { color }, w, antialiased);
            }
        }

        public void DrawCircle(Vec2 pos, double radius, Col color, bool filled = true, double width = -1.0, bool antialiased = false) =>
            DrawEllipse(pos, radius, radius, color, filled, width, antialiased);

        public void DrawEllipse(Vec2 pos, double major, double minor, Col color, bool filled = true, double width = -1.0, bool antialiased = false)
        {
            float mj = (float)major, mn = (float)minor, w = (float)width;
            if (filled) drawList.AddEllipse(pos, mj, mn, color, antialiased);
            else if (w >= 2f * Math.Max(mj, mn)) drawList.AddEllipse(pos, mj + 0.5f * w, mn + 0.5f * w, color, antialiased);
            else
            {
                const int SEG = 64;
                var pts = new Vec2[SEG + 1];
                float step = (float)(Math.PI * 2) / SEG;
                for (int i = 0; i < SEG; i++)
                {
                    float a = i * step;
                    pts[i] = new Vec2(MathF.Cos(a) * mj + pos.x, MathF.Sin(a) * mn + pos.y);
                }
                pts[SEG] = pts[0];
                drawList.AddPolyline(pts, new[] { color }, w, antialiased);
            }
        }

        public void DrawColoredPolygon(IList<Vec2> points, Col color, IList<Vec2> uvs = null, Texture2D texture = null) =>
            drawList.AddPolygon(points, new[] { color }, uvs, texture);

        public void DrawPolygon(IList<Vec2> points, IList<Col> colors, IList<Vec2> uvs = null, Texture2D texture = null) =>
            drawList.AddPolygon(points, colors, uvs, texture);

        public void DrawPrimitive(IList<Vec2> points, IList<Col> colors, IList<Vec2> uvs, Texture2D texture = null)
        {
            var p = new Vec2[points.Count];
            points.CopyTo(p, 0);
            var c = new Col[colors.Count];
            colors.CopyTo(c, 0);
            Vec2[] u = null;
            if (uvs != null && uvs.Count > 0) { u = new Vec2[uvs.Count]; uvs.CopyTo(u, 0); }
            drawList.AddPrimitive(p, c, u, texture);
        }

        public void DrawTexture(Texture2D texture, Vec2 pos, Col? modulate = null)
        {
            if (texture == null) return;
            drawList.AddTextureRect(new Rect2(pos, texture.GetSize()), texture, false, modulate ?? Col.WHITE);
        }

        public void DrawTextureRect(Texture2D texture, Rect2 rect, bool tile, Col? modulate = null, bool transpose = false) =>
            drawList.AddTextureRect(rect, texture, tile, modulate ?? Col.WHITE, transpose);

        public void DrawTextureRectRegion(Texture2D texture, Rect2 rect, Rect2 srcRect, Col? modulate = null, bool transpose = false, bool clipUV = true) =>
            drawList.AddTextureRectRegion(rect, texture, srcRect, modulate ?? Col.WHITE, transpose, clipUV);

        public void DrawStyleBox(StyleBox sb, Rect2 rect) => sb?.Draw(drawList, rect);

        public void DrawString(Font font, Vec2 pos, string text, HorizontalAlignment alignment = HorizontalAlignment.Left, double width = -1, int fontSize = 16, Col? modulate = null) =>
            (font ?? ThemeDB.FallbackFont).DrawString(drawList, pos, text, alignment, (float)width, fontSize, modulate ?? Col.WHITE);

        public void DrawStringOutline(Font font, Vec2 pos, string text, HorizontalAlignment alignment = HorizontalAlignment.Left, double width = -1, int fontSize = 16, int size = 1, Col? modulate = null) =>
            (font ?? ThemeDB.FallbackFont).DrawStringOutline(drawList, pos, text, alignment, (float)width, fontSize, size, modulate ?? Col.WHITE);

        public void DrawMultilineString(Font font, Vec2 pos, string text, HorizontalAlignment alignment = HorizontalAlignment.Left, double width = -1, int fontSize = 16, int maxLines = -1, Col? modulate = null) =>
            (font ?? ThemeDB.FallbackFont).DrawMultilineString(drawList, pos, text, alignment, (float)width, fontSize, maxLines, modulate ?? Col.WHITE);

        public double DrawChar(Font font, Vec2 pos, string ch, int fontSize = 16, Col? modulate = null) =>
            (font ?? ThemeDB.FallbackFont).DrawChar(drawList, pos, ch, fontSize, modulate ?? Col.WHITE);

        public double DrawCharOutline(Font font, Vec2 pos, string ch, int fontSize = 16, int size = -1, Col? modulate = null) =>
            (font ?? ThemeDB.FallbackFont).DrawCharOutline(drawList, pos, ch, fontSize, size, modulate ?? Col.WHITE);

        // ---------- render-time state ----------
        internal Xform2 renderXform;
        internal Col renderModulate;
        internal Rect2 renderClip;
        internal bool renderHasClip;
        internal int renderZ;
    }

    /// <summary>Godot's Node2D: position, rotation, scale, skew.</summary>
    public class Node2D : CanvasItem
    {
        Vec2 _pos, _scale = Vec2.One;
        double _rot, _skew;

        public Vec2 Position { get => _pos; set { _pos = value; QueueRepaint(); } }
        public double Rotation { get => _rot; set { _rot = value; QueueRepaint(); } }
        public double RotationDegrees { get => _rot * 180.0 / Math.PI; set => Rotation = value * Math.PI / 180.0; }
        public Vec2 Scale { get => _scale; set { _scale = value; QueueRepaint(); } }
        public double Skew { get => _skew; set { _skew = value; QueueRepaint(); } }

        public override Xform2 GetTransform() => new Xform2(_rot, _scale, _skew, _pos);

        public Vec2 GlobalPosition
        {
            get => GetGlobalTransform().origin;
            set
            {
                var p = GetParentItem();
                Position = p != null ? p.GetGlobalTransform().AffineInverse().Xform(value) : value;
            }
        }

        public double GlobalRotation
        {
            get => GetGlobalTransform().GetRotation();
            set
            {
                var p = GetParentItem();
                Rotation = p != null ? value - p.GetGlobalTransform().GetRotation() : value;
            }
        }

        public Vec2 GlobalScale => GetGlobalTransform().GetScale();

        public Xform2 Transform
        {
            get => GetTransform();
            set
            {
                _pos = value.origin;
                _rot = value.GetRotation();
                _scale = value.GetScale();
                QueueRepaint();
            }
        }

        public void Translate(Vec2 by) => Position = _pos + by;
        public void Rotate(double by) => Rotation = _rot + by;
        public void LookAt(Vec2 point) => Rotation = _rot + (point - GlobalPosition).Angle() - GlobalRotation;
        public Vec2 ToLocal(Vec2 global) => GetGlobalTransform().AffineInverse().Xform(global);
        public Vec2 ToGlobal(Vec2 local) => GetGlobalTransform().Xform(local);
    }

    public class Sprite2D : Node2D
    {
        Texture2D _tex;
        public Texture2D Texture { get => _tex; set { _tex = value; QueueRedraw(); } }
        bool _centered = true;
        public bool Centered { get => _centered; set { _centered = value; QueueRedraw(); } }
        Vec2 _offset;
        public Vec2 Offset { get => _offset; set { _offset = value; QueueRedraw(); } }
        bool _flipH, _flipV;
        public bool FlipH { get => _flipH; set { _flipH = value; QueueRedraw(); } }
        public bool FlipV { get => _flipV; set { _flipV = value; QueueRedraw(); } }
        int _hframes = 1, _vframes = 1, _frame;
        public int Hframes { get => _hframes; set { _hframes = Math.Max(1, value); QueueRedraw(); } }
        public int Vframes { get => _vframes; set { _vframes = Math.Max(1, value); QueueRedraw(); } }
        public int Frame { get => _frame; set { _frame = value; QueueRedraw(); } }
        bool _regionEnabled;
        Rect2 _region;
        public bool RegionEnabled { get => _regionEnabled; set { _regionEnabled = value; QueueRedraw(); } }
        public Rect2 RegionRect { get => _region; set { _region = value; QueueRedraw(); } }

        public Rect2 GetRect()
        {
            if (_tex == null) return new Rect2(0, 0, 0, 0);
            Vec2 s = _regionEnabled ? _region.size : _tex.GetSize();
            s = new Vec2(s.x / _hframes, s.y / _vframes);
            Vec2 ofs = _offset;
            if (_centered) ofs = ofs - s / 2;
            return new Rect2(ofs, s);
        }

        protected override void OnDraw()
        {
            if (_tex == null) return;
            Rect2 dst = GetRect();
            Rect2 base0 = _regionEnabled ? _region : new Rect2(Vec2.Zero, _tex.GetSize());
            Vec2 fs = new Vec2(base0.size.x / _hframes, base0.size.y / _vframes);
            Rect2 src = new Rect2(base0.position + new Vec2(fs.x * (_frame % _hframes), fs.y * (_frame / _hframes)), fs);
            if (_flipH) { src.position = new Vec2(src.position.x + src.size.x, src.position.y); src.size = new Vec2(-src.size.x, src.size.y); }
            if (_flipV) { src.position = new Vec2(src.position.x, src.position.y + src.size.y); src.size = new Vec2(src.size.x, -src.size.y); }
            DrawTextureRectRegion(_tex, dst, src);
        }
    }

    public class Polygon2D : Node2D
    {
        public Vec2[] Polygon = new Vec2[0];
        public Col Color = Col.WHITE;
        public Col[] VertexColors;
        public Vec2[] UV;
        public Texture2D Texture;
        public Vec2 Offset;
        public bool Antialiased;

        public void Changed() => QueueRedraw();

        protected override void OnDraw()
        {
            if (Polygon == null || Polygon.Length < 3) return;
            var pts = new Vec2[Polygon.Length];
            for (int i = 0; i < pts.Length; i++) pts[i] = Polygon[i] + Offset;
            IList<Col> cols = VertexColors != null && VertexColors.Length == pts.Length ? VertexColors : new[] { Color };
            if (VertexColors != null && VertexColors.Length == pts.Length && Color != Col.WHITE)
            {
                var c2 = new Col[pts.Length];
                for (int i = 0; i < c2.Length; i++) c2[i] = VertexColors[i] * Color;
                cols = c2;
            }
            Vec2[] uvs = null;
            if (Texture != null && UV != null && UV.Length == pts.Length)
            {
                Vec2 ts = Texture.GetSize();
                uvs = new Vec2[UV.Length];
                for (int i = 0; i < uvs.Length; i++) uvs[i] = new Vec2(UV[i].x / ts.x, UV[i].y / ts.y);
            }
            DrawPolygon(pts, cols, uvs, Texture);
        }
    }

    /// <summary>A separate canvas drawn above (layer &gt; 0) or below the main one, with its own transform.</summary>
    public class CanvasLayer : Node
    {
        int _layer = 1;
        bool _visible = true;
        public Vec2 Offset;
        public double Rotation;
        public Vec2 Scale = Vec2.One;
        public bool FollowViewportEnabled;
        public event Action VisibilityChanged;

        public int Layer { get => _layer; set { _layer = value; GetViewport()?.MarkCanvasDirty(); } }

        public bool Visible
        {
            get => _visible;
            set
            {
                if (_visible == value) return;
                _visible = value;
                GetViewport()?.MarkCanvasDirty();
                VisibilityChanged?.Invoke();
                foreach (var c in children)
                    if (c is CanvasItem ci && ci.Visible) ci._Notification(NOTIFICATION_VISIBILITY_CHANGED);
            }
        }

        public void Show() => Visible = true;
        public void Hide() => Visible = false;
        public Xform2 Transform => new Xform2(Rotation, Scale, 0.0, Offset);

        public Xform2 GetFinalTransform() => Transform;
    }

    // ---------- materials ----------
    public abstract class GMaterial
    {
        public int version;
        public void EmitChanged() => version++;
    }

    public enum CanvasBlendMode { Mix = 0, Add = 1, Sub = 2, Mul = 3, PremultAlpha = 4 }

    public sealed class CanvasItemMaterial : GMaterial
    {
        public CanvasBlendMode BlendMode = CanvasBlendMode.Mix;
        public bool ParticlesAnimation;
        public int ParticlesAnimHFrames = 1, ParticlesAnimVFrames = 1;
        public bool ParticlesAnimLoop;
    }

    /// <summary>A Godot shader by path ("res://scripts/app/ui_skin.gdshader"); the host maps it to its own port.</summary>
    public sealed class Shader
    {
        public readonly string ResourcePath;
        public string Code;
        public Shader(string path) { ResourcePath = path; }
        static readonly Dictionary<string, Shader> _cache = new Dictionary<string, Shader>();

        public static Shader Get(string path)
        {
            lock (_cache)
            {
                if (!_cache.TryGetValue(path, out var s)) _cache[path] = s = new Shader(path);
                return s;
            }
        }
    }

    public sealed class ShaderMaterial : GMaterial
    {
        public Shader Shader;
        readonly Dictionary<string, object> _params = new Dictionary<string, object>();
        public IReadOnlyDictionary<string, object> Params => _params;

        public void SetShaderParameter(string name, object value)
        {
            _params[name] = value;
            version++;
        }

        public object GetShaderParameter(string name) => _params.TryGetValue(name, out var v) ? v : null;
    }

    /// <summary>The RenderingServer calls the UI code makes on a canvas item.</summary>
    public static class RenderingServer
    {
        public static void CanvasItemAddPolygon(DrawList ci, IList<Vec2> points, IList<Col> colors, IList<Vec2> uvs = null, Texture2D texture = null) =>
            ci.AddPolygon(points, colors, uvs, texture);

        public static void CanvasItemAddPolyline(DrawList ci, IList<Vec2> points, IList<Col> colors, double width = -1.0, bool antialiased = false) =>
            ci.AddPolyline(points, colors, (float)width, antialiased);

        public static void CanvasItemAddRect(DrawList ci, Rect2 rect, Col color, bool antialiased = false) => ci.AddRect(rect, color, antialiased);

        public static void CanvasItemAddCircle(DrawList ci, Vec2 pos, double radius, Col color, bool antialiased = false) =>
            ci.AddEllipse(pos, (float)radius, (float)radius, color, antialiased);

        public static void CanvasItemAddLine(DrawList ci, Vec2 from, Vec2 to, Col color, double width = -1.0, bool antialiased = false) =>
            ci.AddLine(from, to, color, (float)width, antialiased);

        public static void CanvasItemAddTextureRect(DrawList ci, Rect2 rect, Texture2D tex, bool tile = false, Col? modulate = null, bool transpose = false) =>
            ci.AddTextureRect(rect, tex, tile, modulate ?? Col.WHITE, transpose);

        public static void CanvasItemAddTextureRectRegion(DrawList ci, Rect2 rect, Texture2D tex, Rect2 src, Col? modulate = null, bool transpose = false) =>
            ci.AddTextureRectRegion(rect, tex, src, modulate ?? Col.WHITE, transpose);

        /// <summary>Frame hooks for the perf overlay (siege_diag): the host raises these around its render.</summary>
        public static event Action FramePreDraw, FramePostDraw;
        public static void RaiseFramePreDraw() => FramePreDraw?.Invoke();
        public static void RaiseFramePostDraw() => FramePostDraw?.Invoke();
    }
}
