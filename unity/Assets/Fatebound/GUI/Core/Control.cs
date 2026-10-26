// Fatebound GUI (Unity port): Godot's Control, as control.cpp does it -- anchors and offsets, the position/size
// caches recomputed in _size_changed (grow directions, minimum and maximum size), presets, the deferred minimum-size
// update that containers listen to, rotation/scale about the pivot, mouse filter, focus, theme overrides and lookups.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public enum LayoutPreset
    {
        TopLeft = 0, TopRight = 1, BottomLeft = 2, BottomRight = 3, CenterLeft = 4, CenterTop = 5, CenterRight = 6,
        CenterBottom = 7, Center = 8, LeftWide = 9, TopWide = 10, RightWide = 11, BottomWide = 12, VcenterWide = 13,
        HcenterWide = 14, FullRect = 15,
    }

    public enum LayoutPresetMode { Minsize = 0, KeepWidth = 1, KeepHeight = 2, KeepSize = 3 }

    [Flags]
    public enum SizeFlags { ShrinkBegin = 0, Fill = 1, Expand = 2, ExpandFill = 3, ShrinkCenter = 4, ShrinkEnd = 8 }

    public enum MouseFilterEnum { Stop = 0, Pass = 1, Ignore = 2 }
    public enum GrowDirection { Begin = 0, End = 1, Both = 2 }
    public enum FocusModeEnum { None = 0, Click = 1, All = 2 }
    public enum CursorShape { Arrow = 0, Ibeam = 1, PointingHand = 2, Cross = 3, Wait = 4, Busy = 5, Drag = 6, CanDrop = 7, Forbidden = 8, Move = 13 }
    public enum LayoutDirectionEnum { Inherited = 0, ApplicationLocale = 1, Ltr = 2, Rtl = 3 }

    public class Control : CanvasItem
    {
        // ---------- GDScript constant names (Control.SIZE_EXPAND_FILL ...) ----------
        public const SizeFlags SIZE_SHRINK_BEGIN = SizeFlags.ShrinkBegin, SIZE_FILL = SizeFlags.Fill, SIZE_EXPAND = SizeFlags.Expand,
            SIZE_EXPAND_FILL = SizeFlags.ExpandFill, SIZE_SHRINK_CENTER = SizeFlags.ShrinkCenter, SIZE_SHRINK_END = SizeFlags.ShrinkEnd;
        public const MouseFilterEnum MOUSE_FILTER_STOP = MouseFilterEnum.Stop, MOUSE_FILTER_PASS = MouseFilterEnum.Pass, MOUSE_FILTER_IGNORE = MouseFilterEnum.Ignore;
        public const LayoutPreset PRESET_TOP_LEFT = LayoutPreset.TopLeft, PRESET_TOP_RIGHT = LayoutPreset.TopRight, PRESET_BOTTOM_LEFT = LayoutPreset.BottomLeft,
            PRESET_BOTTOM_RIGHT = LayoutPreset.BottomRight, PRESET_CENTER_LEFT = LayoutPreset.CenterLeft, PRESET_CENTER_TOP = LayoutPreset.CenterTop,
            PRESET_CENTER_RIGHT = LayoutPreset.CenterRight, PRESET_CENTER_BOTTOM = LayoutPreset.CenterBottom, PRESET_CENTER = LayoutPreset.Center,
            PRESET_LEFT_WIDE = LayoutPreset.LeftWide, PRESET_TOP_WIDE = LayoutPreset.TopWide, PRESET_RIGHT_WIDE = LayoutPreset.RightWide,
            PRESET_BOTTOM_WIDE = LayoutPreset.BottomWide, PRESET_VCENTER_WIDE = LayoutPreset.VcenterWide, PRESET_HCENTER_WIDE = LayoutPreset.HcenterWide,
            PRESET_FULL_RECT = LayoutPreset.FullRect;
        public const LayoutPresetMode PRESET_MODE_MINSIZE = LayoutPresetMode.Minsize, PRESET_MODE_KEEP_WIDTH = LayoutPresetMode.KeepWidth,
            PRESET_MODE_KEEP_HEIGHT = LayoutPresetMode.KeepHeight, PRESET_MODE_KEEP_SIZE = LayoutPresetMode.KeepSize;
        public const GrowDirection GROW_DIRECTION_BEGIN = GrowDirection.Begin, GROW_DIRECTION_END = GrowDirection.End, GROW_DIRECTION_BOTH = GrowDirection.Both;
        public const FocusModeEnum FOCUS_NONE = FocusModeEnum.None, FOCUS_CLICK = FocusModeEnum.Click, FOCUS_ALL = FocusModeEnum.All;
        public const float ANCHOR_BEGIN = 0f, ANCHOR_END = 1f;
        public const int NOTIFICATION_MOUSE_ENTER = 41, NOTIFICATION_MOUSE_EXIT = 42, NOTIFICATION_FOCUS_ENTER = 43, NOTIFICATION_FOCUS_EXIT = 44,
            NOTIFICATION_PRE_SORT_CHILDREN = 51, NOTIFICATION_SCROLL_BEGIN = 47, NOTIFICATION_SCROLL_END = 48;

        // ---------- data ----------
        readonly float[] _anchor = new float[4];
        readonly float[] _offset = new float[4];
        Vec2 _posCache, _sizeCache;
        Vec2 _minCache;
        bool _minValid;
        Vec2 _lastMin = Vec2.Zero;
        bool _updatingLastMin;
        Vec2 _customMin;
        Vec2 _customMax = new Vec2(-1f, -1f);
        GrowDirection _hGrow = GrowDirection.End, _vGrow = GrowDirection.End;
        SizeFlags _hFlags = SizeFlags.Fill, _vFlags = SizeFlags.Fill;
        float _stretchRatio = 1f;
        MouseFilterEnum _mouseFilter = MouseFilterEnum.Stop;
        bool _clip;
        float _rotation;
        Vec2 _scale = Vec2.One;
        Vec2 _pivot;
        Vec2 _pivotRatio;
        public FocusModeEnum FocusMode = FocusModeEnum.None;
        public string TooltipText = "";
        public CursorShape MouseDefaultCursorShape = CursorShape.Arrow;
        public LayoutDirectionEnum LayoutDirection = LayoutDirectionEnum.Inherited;
        public bool AutoTranslate = true;
        public Theme Theme;
        string _typeVariation = "";
        internal bool mouseInside;

        Dictionary<string, Col> _ovColor;
        Dictionary<string, int> _ovConst;
        Dictionary<string, Font> _ovFont;
        Dictionary<string, int> _ovFontSize;
        Dictionary<string, StyleBox> _ovStyle;
        Dictionary<string, Texture2D> _ovIcon;

        public event Action Resized, MinimumSizeChanged, SizeFlagsChanged, MouseEntered, MouseExited, FocusEntered, FocusExited, ThemeChanged;
        public event Action<InputEvent> GuiInput;

        public Control()
        {
            FocusMode = DefaultFocusMode;
        }

        protected virtual FocusModeEnum DefaultFocusMode => FocusModeEnum.None;

        public Control GetParentControl() => Parent as Control;

        // ---------- tree ----------
        protected override void OnEnterTree()
        {
            base.OnEnterTree();
            if (GetParentItem() == null) GetViewport()?.AddRootControl(this);
            else GetParentItem().ItemRectChanged += SizeChanged;
            NotifyThemeChanged();
        }

        protected override void OnPostEnterTree()
        {
            SizeChanged();
        }

        protected override void OnExitTree()
        {
            ReleaseFocus();
            var vp = GetViewport();
            vp?.RemoveControl(this);
            vp?.RemoveRootControl(this);
            var p = Parent as CanvasItem;
            if (p != null) p.ItemRectChanged -= SizeChanged;
            base.OnExitTree();
        }

        protected override void OnTopLevelChanged()
        {
            if (!IsInsideTree()) return;
            var p = Parent as CanvasItem;
            var vp = GetViewport();
            if (TopLevel)
            {
                if (p != null) p.ItemRectChanged -= SizeChanged;
                vp?.AddRootControl(this);
            }
            else
            {
                vp?.RemoveRootControl(this);
                if (p != null) p.ItemRectChanged += SizeChanged;
                else vp?.AddRootControl(this);
            }
            SizeChanged();
        }

        internal void NotifyThemeChanged()
        {
            _themeCache.Clear();
            _Notification(NOTIFICATION_THEME_CHANGED);
            OnThemeChanged();
            ThemeChanged?.Invoke();
            QueueRedraw();
            UpdateMinimumSize();
            SizeChanged();
        }

        /// <summary>NOTIFICATION_THEME_CHANGED for the node type (containers re-sort, labels reshape ...).</summary>
        protected virtual void OnThemeChanged() { }

        protected override void OnVisibilityChanged()
        {
            if (!IsInsideTree()) return;
            if (!IsVisibleInTree()) GetViewport()?.HideControl(this);
            else SizeChanged();
        }

        // ---------- layout ----------
        public Rect2 GetParentAnchorableRect()
        {
            if (!IsInsideTree()) return new Rect2(0, 0, 0, 0);
            var p = GetParentItem();
            if (p != null) return p is Control pc ? new Rect2(Vec2.Zero, pc.Size) : p.GetItemRect();
            return GetViewport()?.GetVisibleRect() ?? new Rect2(0, 0, 0, 0);
        }

        static bool ApproxEq(Vec2 a, Vec2 b)
        {
            bool E(float x, float y)
            {
                if (x == y) return true;
                float tol = 0.00001f * Math.Abs(x);
                if (tol < 0.00001f) tol = 0.00001f;
                return Math.Abs(x - y) < tol;
            }
            return E(a.x, b.x) && E(a.y, b.y);
        }

        internal void SizeChanged()
        {
            Rect2 pr = GetParentAnchorableRect();
            var edge = new float[4];
            for (int i = 0; i < 4; i++)
            {
                float area = (i & 1) == 0 ? pr.size.x : pr.size.y;
                edge[i] = _offset[i] + _anchor[i] * area;
            }
            Vec2 np = new Vec2(edge[0], edge[1]);
            Vec2 ns = new Vec2(edge[2], edge[3]) - np;
            Vec2 max = GetCombinedMaximumSize();
            Vec2 min = GetCombinedMinimumSize();
            if (min.x > ns.x)
            {
                if (_hGrow == GrowDirection.Begin) np.x += ns.x - min.x;
                else if (_hGrow == GrowDirection.Both) np.x += 0.5f * (ns.x - min.x);
                ns.x = min.x;
            }
            if (max.x >= 0 && max.x < ns.x)
            {
                if (_hGrow == GrowDirection.Begin) np.x += ns.x - max.x;
                else if (_hGrow == GrowDirection.Both) np.x += 0.5f * (ns.x - max.x);
                ns.x = max.x;
            }
            if (min.y > ns.y)
            {
                if (_vGrow == GrowDirection.Begin) np.y += ns.y - min.y;
                else if (_vGrow == GrowDirection.Both) np.y += 0.5f * (ns.y - min.y);
                ns.y = min.y;
            }
            if (max.y >= 0 && max.y < ns.y)
            {
                if (_vGrow == GrowDirection.Begin) np.y += ns.y - max.y;
                else if (_vGrow == GrowDirection.Both) np.y += 0.5f * (ns.y - max.y);
                ns.y = max.y;
            }
            bool posChanged = np != _posCache;
            bool sizeChanged = ns != _sizeCache;
            bool apos = !ApproxEq(np, _posCache);
            bool asize = !ApproxEq(ns, _sizeCache);
            if (posChanged) _posCache = np;
            if (sizeChanged) _sizeCache = ns;
            if (IsInsideTree())
            {
                if (apos || asize)
                {
                    if (asize) QueueRedraw();
                    else QueueRepaint();
                    EmitItemRectChanged();
                    if (asize)
                    {
                        _Notification(NOTIFICATION_RESIZED);
                        OnResized();
                        Resized?.Invoke();
                    }
                }
                else if (posChanged) QueueRepaint();
            }
        }

        /// <summary>NOTIFICATION_RESIZED for the node type.</summary>
        protected virtual void OnResized() { }

        void ComputeOffsets(Rect2 r)
        {
            Vec2 ps = GetParentAnchorableRect().size;
            float x = r.position.x;
            _offset[0] = x - _anchor[0] * ps.x;
            _offset[1] = r.position.y - _anchor[1] * ps.y;
            _offset[2] = x + r.size.x - _anchor[2] * ps.x;
            _offset[3] = r.position.y + r.size.y - _anchor[3] * ps.y;
        }

        void ComputeAnchors(Rect2 r)
        {
            Vec2 ps = GetParentAnchorableRect().size;
            if (ps.x == 0 || ps.y == 0) return;
            float x = r.position.x;
            _anchor[0] = (x - _offset[0]) / ps.x;
            _anchor[1] = (r.position.y - _offset[1]) / ps.y;
            _anchor[2] = (x + r.size.x - _offset[2]) / ps.x;
            _anchor[3] = (r.position.y + r.size.y - _offset[3]) / ps.y;
        }

        public void SetAnchor(Side side, double anchor, bool keepOffset = false, bool pushOppositeAnchor = true)
        {
            int s = (int)side;
            Rect2 pr = GetParentAnchorableRect();
            float range = side == Side.Left || side == Side.Right ? pr.size.x : pr.size.y;
            float prev = _offset[s] + _anchor[s] * range;
            float prevOpp = _offset[(s + 2) % 4] + _anchor[(s + 2) % 4] * range;
            _anchor[s] = (float)anchor;
            if (((side == Side.Left || side == Side.Top) && _anchor[s] > _anchor[(s + 2) % 4]) ||
                ((side == Side.Right || side == Side.Bottom) && _anchor[s] < _anchor[(s + 2) % 4]))
            {
                if (pushOppositeAnchor) _anchor[(s + 2) % 4] = _anchor[s];
                else _anchor[s] = _anchor[(s + 2) % 4];
            }
            if (!keepOffset)
            {
                _offset[s] = prev - _anchor[s] * range;
                if (pushOppositeAnchor) _offset[(s + 2) % 4] = prevOpp - _anchor[(s + 2) % 4] * range;
            }
            if (IsInsideTree()) SizeChanged();
            QueueRedraw();
        }

        public void SetAnchorAndOffset(Side side, double anchor, double offset, bool pushOppositeAnchor = false)
        {
            SetAnchor(side, anchor, false, pushOppositeAnchor);
            SetOffset(side, offset);
        }

        public double GetAnchor(Side s) => _anchor[(int)s];
        public double GetOffset(Side s) => _offset[(int)s];

        public void SetOffset(Side side, double v)
        {
            int s = (int)side;
            if (_offset[s] == (float)v) return;
            _offset[s] = (float)v;
            SizeChanged();
        }

        public double AnchorLeft { get => _anchor[0]; set => SetAnchor(Side.Left, value, true, true); }
        public double AnchorTop { get => _anchor[1]; set => SetAnchor(Side.Top, value, true, true); }
        public double AnchorRight { get => _anchor[2]; set => SetAnchor(Side.Right, value, true, true); }
        public double AnchorBottom { get => _anchor[3]; set => SetAnchor(Side.Bottom, value, true, true); }
        public double OffsetLeft { get => _offset[0]; set => SetOffset(Side.Left, value); }
        public double OffsetTop { get => _offset[1]; set => SetOffset(Side.Top, value); }
        public double OffsetRight { get => _offset[2]; set => SetOffset(Side.Right, value); }
        public double OffsetBottom { get => _offset[3]; set => SetOffset(Side.Bottom, value); }

        public void SetBegin(Vec2 p)
        {
            if (_offset[0] == p.x && _offset[1] == p.y) return;
            _offset[0] = p.x; _offset[1] = p.y;
            SizeChanged();
        }

        public void SetEnd(Vec2 p)
        {
            if (_offset[2] == p.x && _offset[3] == p.y) return;
            _offset[2] = p.x; _offset[3] = p.y;
            SizeChanged();
        }

        public Vec2 GetBegin() => new Vec2(_offset[0], _offset[1]);
        public Vec2 GetEnd() => new Vec2(_offset[2], _offset[3]);

        public GrowDirection GrowHorizontal { get => _hGrow; set { _hGrow = value; SizeChanged(); } }
        public GrowDirection GrowVertical { get => _vGrow; set { _vGrow = value; SizeChanged(); } }

        public void SetAnchorsPreset(LayoutPreset p, bool keepOffsets = false)
        {
            switch (p)
            {
                case LayoutPreset.TopLeft: case LayoutPreset.BottomLeft: case LayoutPreset.CenterLeft: case LayoutPreset.TopWide:
                case LayoutPreset.BottomWide: case LayoutPreset.LeftWide: case LayoutPreset.HcenterWide: case LayoutPreset.FullRect:
                    SetAnchor(Side.Left, ANCHOR_BEGIN, keepOffsets); break;
                case LayoutPreset.CenterTop: case LayoutPreset.CenterBottom: case LayoutPreset.Center: case LayoutPreset.VcenterWide:
                    SetAnchor(Side.Left, 0.5, keepOffsets); break;
                default:
                    SetAnchor(Side.Left, ANCHOR_END, keepOffsets); break;
            }
            switch (p)
            {
                case LayoutPreset.TopLeft: case LayoutPreset.TopRight: case LayoutPreset.CenterTop: case LayoutPreset.LeftWide:
                case LayoutPreset.RightWide: case LayoutPreset.TopWide: case LayoutPreset.VcenterWide: case LayoutPreset.FullRect:
                    SetAnchor(Side.Top, ANCHOR_BEGIN, keepOffsets); break;
                case LayoutPreset.CenterLeft: case LayoutPreset.CenterRight: case LayoutPreset.Center: case LayoutPreset.HcenterWide:
                    SetAnchor(Side.Top, 0.5, keepOffsets); break;
                default:
                    SetAnchor(Side.Top, ANCHOR_END, keepOffsets); break;
            }
            switch (p)
            {
                case LayoutPreset.TopLeft: case LayoutPreset.BottomLeft: case LayoutPreset.CenterLeft: case LayoutPreset.LeftWide:
                    SetAnchor(Side.Right, ANCHOR_BEGIN, keepOffsets); break;
                case LayoutPreset.CenterTop: case LayoutPreset.CenterBottom: case LayoutPreset.Center: case LayoutPreset.VcenterWide:
                    SetAnchor(Side.Right, 0.5, keepOffsets); break;
                default:
                    SetAnchor(Side.Right, ANCHOR_END, keepOffsets); break;
            }
            switch (p)
            {
                case LayoutPreset.TopLeft: case LayoutPreset.TopRight: case LayoutPreset.CenterTop: case LayoutPreset.TopWide:
                    SetAnchor(Side.Bottom, ANCHOR_BEGIN, keepOffsets); break;
                case LayoutPreset.CenterLeft: case LayoutPreset.CenterRight: case LayoutPreset.Center: case LayoutPreset.HcenterWide:
                    SetAnchor(Side.Bottom, 0.5, keepOffsets); break;
                default:
                    SetAnchor(Side.Bottom, ANCHOR_END, keepOffsets); break;
            }
        }

        public void SetOffsetsPreset(LayoutPreset p, LayoutPresetMode mode = LayoutPresetMode.Minsize, int margin = 0)
        {
            Vec2 min = GetMinimumSize();
            Vec2 ns = Size;
            if (mode == LayoutPresetMode.Minsize || mode == LayoutPresetMode.KeepHeight) ns.x = min.x;
            if (mode == LayoutPresetMode.Minsize || mode == LayoutPresetMode.KeepWidth) ns.y = min.y;
            Rect2 pr = GetParentAnchorableRect();
            float x = pr.size.x;
            switch (p)
            {
                case LayoutPreset.TopLeft: case LayoutPreset.BottomLeft: case LayoutPreset.CenterLeft: case LayoutPreset.TopWide:
                case LayoutPreset.BottomWide: case LayoutPreset.LeftWide: case LayoutPreset.HcenterWide: case LayoutPreset.FullRect:
                    _offset[0] = x * (0f - _anchor[0]) + margin + pr.position.x; break;
                case LayoutPreset.CenterTop: case LayoutPreset.CenterBottom: case LayoutPreset.Center: case LayoutPreset.VcenterWide:
                    _offset[0] = x * (0.5f - _anchor[0]) - ns.x / 2 + pr.position.x; break;
                default:
                    _offset[0] = x * (1f - _anchor[0]) - ns.x - margin + pr.position.x; break;
            }
            switch (p)
            {
                case LayoutPreset.TopLeft: case LayoutPreset.TopRight: case LayoutPreset.CenterTop: case LayoutPreset.LeftWide:
                case LayoutPreset.RightWide: case LayoutPreset.TopWide: case LayoutPreset.VcenterWide: case LayoutPreset.FullRect:
                    _offset[1] = pr.size.y * (0f - _anchor[1]) + margin + pr.position.y; break;
                case LayoutPreset.CenterLeft: case LayoutPreset.CenterRight: case LayoutPreset.Center: case LayoutPreset.HcenterWide:
                    _offset[1] = pr.size.y * (0.5f - _anchor[1]) - ns.y / 2 + pr.position.y; break;
                default:
                    _offset[1] = pr.size.y * (1f - _anchor[1]) - ns.y - margin + pr.position.y; break;
            }
            switch (p)
            {
                case LayoutPreset.TopLeft: case LayoutPreset.BottomLeft: case LayoutPreset.CenterLeft: case LayoutPreset.LeftWide:
                    _offset[2] = x * (0f - _anchor[2]) + ns.x + margin + pr.position.x; break;
                case LayoutPreset.CenterTop: case LayoutPreset.CenterBottom: case LayoutPreset.Center: case LayoutPreset.VcenterWide:
                    _offset[2] = x * (0.5f - _anchor[2]) + ns.x / 2 + pr.position.x; break;
                default:
                    _offset[2] = x * (1f - _anchor[2]) - margin + pr.position.x; break;
            }
            switch (p)
            {
                case LayoutPreset.TopLeft: case LayoutPreset.TopRight: case LayoutPreset.CenterTop: case LayoutPreset.TopWide:
                    _offset[3] = pr.size.y * (0f - _anchor[3]) + ns.y + margin + pr.position.y; break;
                case LayoutPreset.CenterLeft: case LayoutPreset.CenterRight: case LayoutPreset.Center: case LayoutPreset.HcenterWide:
                    _offset[3] = pr.size.y * (0.5f - _anchor[3]) + ns.y / 2 + pr.position.y; break;
                default:
                    _offset[3] = pr.size.y * (1f - _anchor[3]) - margin + pr.position.y; break;
            }
            SizeChanged();
        }

        public void SetAnchorsAndOffsetsPreset(LayoutPreset p, LayoutPresetMode mode = LayoutPresetMode.Minsize, int margin = 0)
        {
            SetAnchorsPreset(p);
            SetOffsetsPreset(p, mode, margin);
        }

        public void SetGrowDirectionPreset(LayoutPreset p)
        {
            switch (p)
            {
                case LayoutPreset.TopLeft: case LayoutPreset.BottomLeft: case LayoutPreset.CenterLeft: case LayoutPreset.LeftWide:
                    _hGrow = GrowDirection.End; break;
                case LayoutPreset.TopRight: case LayoutPreset.BottomRight: case LayoutPreset.CenterRight: case LayoutPreset.RightWide:
                    _hGrow = GrowDirection.Begin; break;
                default: _hGrow = GrowDirection.Both; break;
            }
            switch (p)
            {
                case LayoutPreset.TopLeft: case LayoutPreset.TopRight: case LayoutPreset.CenterTop: case LayoutPreset.TopWide:
                    _vGrow = GrowDirection.End; break;
                case LayoutPreset.BottomLeft: case LayoutPreset.BottomRight: case LayoutPreset.CenterBottom: case LayoutPreset.BottomWide:
                    _vGrow = GrowDirection.Begin; break;
                default: _vGrow = GrowDirection.Both; break;
            }
            SizeChanged();
        }

        /// <summary>The `anchors_preset` property: sets the anchors only (offsets kept).</summary>
        public LayoutPreset AnchorsPreset { set => SetAnchorsPreset(value, true); }

        public Vec2 Position
        {
            get => _posCache;
            set => SetPosition(value);
        }

        public void SetPosition(Vec2 p, bool keepOffsets = false)
        {
            if (keepOffsets) ComputeAnchors(new Rect2(p, _sizeCache));
            else ComputeOffsets(new Rect2(p, _sizeCache));
            SizeChanged();
        }

        public Vec2 Size
        {
            get => _sizeCache;
            set => SetSize(value);
        }

        public void SetSize(Vec2 s, bool keepOffsets = false)
        {
            if (!float.IsFinite(s.x) || !float.IsFinite(s.y)) return;
            Vec2 ns = s;
            Vec2 min = GetCombinedMinimumSize();
            if (ns.x < min.x) ns.x = min.x;
            if (ns.y < min.y) ns.y = min.y;
            Vec2 max = GetCombinedMaximumSize();
            if (max.x >= 0 && ns.x > max.x) ns.x = max.x;
            if (max.y >= 0 && ns.y > max.y) ns.y = max.y;
            if (keepOffsets) ComputeAnchors(new Rect2(_posCache, ns));
            else ComputeOffsets(new Rect2(_posCache, ns));
            SizeChanged();
        }

        public void SetRect(Rect2 r)
        {
            for (int i = 0; i < 4; i++) _anchor[i] = ANCHOR_BEGIN;
            ComputeOffsets(r);
            if (IsInsideTree()) SizeChanged();
        }

        public Vec2 GlobalPosition
        {
            get => GetGlobalTransform().origin;
            set => SetGlobalPosition(value);
        }

        public void SetGlobalPosition(Vec2 p, bool keepOffsets = false)
        {
            var pi = GetParentItem();
            Vec2 inParent = pi != null ? pi.GetGlobalTransform().AffineInverse().Xform(p) : p;
            SetPosition(inParent - InternalTransform().origin, keepOffsets);
        }

        public Rect2 GetRect() => new Rect2(Position, Scale * Size);

        public Rect2 GetGlobalRect()
        {
            var xf = GetGlobalTransform();
            return new Rect2(xf.origin, xf.GetScale() * Size);
        }

        public Vec2 GetScreenPosition() => GetGlobalTransformWithCanvas().origin;
        public Rect2 GetScreenRect() { var xf = GetGlobalTransformWithCanvas(); return new Rect2(xf.origin, xf.GetScale() * Size); }

        public override Rect2 GetItemRect() => new Rect2(Vec2.Zero, Size);
        public Rect2 GetAnchorableRect() => new Rect2(Vec2.Zero, Size);

        public double Rotation { get => _rotation; set { _rotation = (float)value; QueueRepaint(); EmitItemRectChangedPos(); } }
        public double RotationDegrees { get => _rotation * 180.0 / Math.PI; set => Rotation = value * Math.PI / 180.0; }
        public Vec2 Scale { get => _scale; set { _scale = value; QueueRepaint(); EmitItemRectChangedPos(); } }
        public Vec2 PivotOffset { get => _pivot; set { _pivot = value; QueueRepaint(); } }
        public Vec2 PivotOffsetRatio { get => _pivotRatio; set { _pivotRatio = value; QueueRepaint(); } }

        void EmitItemRectChangedPos() { }

        Vec2 CombinedPivot() => _pivot + new Vec2(_pivotRatio.x * _sizeCache.x, _pivotRatio.y * _sizeCache.y);

        Xform2 InternalTransform()
        {
            var xf = new Xform2(_rotation, _scale, 0.0, Vec2.Zero);
            Vec2 pv = CombinedPivot();
            xf = xf.TranslatedLocal(-pv);
            xf.origin = xf.origin + pv;
            return xf;
        }

        public override Xform2 GetTransform()
        {
            var xf = InternalTransform();
            xf.origin = xf.origin + _posCache;
            return xf;
        }

        // ---------- minimum / maximum size ----------
        /// <summary>get_minimum_size / _get_minimum_size: the node type's own minimum.</summary>
        public virtual Vec2 GetMinimumSize() => Vec2.Zero;
        public virtual Vec2 GetMaximumSize() => new Vec2(-1f, -1f);

        public Vec2 CustomMinimumSize
        {
            get => _customMin;
            set
            {
                if (value == _customMin || !value.IsFinite()) return;
                _customMin = value;
                UpdateMinimumSize();
            }
        }

        public Vec2 CustomMaximumSize
        {
            get => _customMax;
            set
            {
                var n = value;
                if (n.x < 0) n.x = -1;
                if (n.y < 0) n.y = -1;
                _customMax = n;
                UpdateMinimumSize();
                SizeChanged();
            }
        }

        public Vec2 GetCombinedMinimumSize()
        {
            if (!_minValid)
            {
                Vec2 m = GetMinimumSize();
                _minCache = new Vec2(Math.Max(m.x, _customMin.x), Math.Max(m.y, _customMin.y));
                _minValid = true;
            }
            return _minCache;
        }

        public Vec2 GetCombinedMaximumSize()
        {
            Vec2 m = GetMaximumSize();
            if (_customMax.x >= 0) m.x = m.x >= 0 ? Math.Min(m.x, _customMax.x) : _customMax.x;
            if (_customMax.y >= 0) m.y = m.y >= 0 ? Math.Min(m.y, _customMax.y) : _customMax.y;
            return m;
        }

        public Vec2 GetBoundMinimumSize()
        {
            Vec2 mn = GetCombinedMinimumSize(), mx = GetCombinedMaximumSize();
            if (mx.x >= 0 && mn.x > mx.x) mn.x = mx.x;
            if (mx.y >= 0 && mn.y > mx.y) mn.y = mx.y;
            return mn;
        }

        /// <summary>update_minimum_size(): invalidates the caches up the tree and, deferred, re-lays this out.</summary>
        public void UpdateMinimumSize()
        {
            if (!IsInsideTree()) return;
            Control inv = this;
            while (inv != null && inv._minValid)
            {
                inv._minValid = false;
                if (inv.TopLevel) break;
                inv = inv.GetParentControl();
            }
            if (!IsVisibleInTree())
            {
                _lastMin = new Vec2(-1, -1);
                return;
            }
            if (_updatingLastMin) return;
            _updatingLastMin = true;
            CallDeferred(UpdateMinimumSizeDeferred);
        }

        void UpdateMinimumSizeDeferred()
        {
            if (!IsInsideTree()) { _updatingLastMin = false; return; }
            Vec2 m = GetCombinedMinimumSize();
            _updatingLastMin = false;
            if (m != _lastMin)
            {
                _lastMin = m;
                SizeChanged();
                MinimumSizeChanged?.Invoke();
            }
        }

        // ---------- size flags ----------
        public SizeFlags SizeFlagsHorizontal
        {
            get => _hFlags;
            set { if (_hFlags == value) return; _hFlags = value; SizeFlagsChanged?.Invoke(); }
        }

        public SizeFlags SizeFlagsVertical
        {
            get => _vFlags;
            set { if (_vFlags == value) return; _vFlags = value; SizeFlagsChanged?.Invoke(); }
        }

        public double SizeFlagsStretchRatio
        {
            get => _stretchRatio;
            set { if (_stretchRatio == (float)value) return; _stretchRatio = (float)value; SizeFlagsChanged?.Invoke(); }
        }

        // ---------- clipping, mouse ----------
        public bool ClipContents { get => _clip; set { _clip = value; QueueRepaint(); } }
        public override bool ClipsChildren => _clip;

        public MouseFilterEnum MouseFilter { get => _mouseFilter; set => _mouseFilter = value; }

        public virtual bool HasPoint(Vec2 p) => new Rect2(Vec2.Zero, Size).HasPoint(p);

        public void AcceptEvent() => GetViewport()?.SetInputAsHandled();

        protected virtual void _GuiInput(InputEvent e) { }

        internal void CallGuiInput(InputEvent e)
        {
            GuiInput?.Invoke(e);
            if (GetViewport()?.IsInputHandled() == true) return;
            OnGuiInput(e);
            if (GetViewport()?.IsInputHandled() == true) return;
            _GuiInput(e);
        }

        /// <summary>The node type's own gui_input (buttons, sliders, scroll containers).</summary>
        protected virtual void OnGuiInput(InputEvent e) { }

        internal void NotifyMouse(bool enter)
        {
            mouseInside = enter;
            _Notification(enter ? NOTIFICATION_MOUSE_ENTER : NOTIFICATION_MOUSE_EXIT);
            OnMouseNotify(enter);
            if (enter) MouseEntered?.Invoke();
            else MouseExited?.Invoke();
        }

        protected virtual void OnMouseNotify(bool enter) { }

        // ---------- focus ----------
        public bool HasFocus(bool ignoreHiddenFocus = false) => GetViewport()?.GuiFocus == this && !(ignoreHiddenFocus && GetViewport().HideFocus);

        public void GrabFocus(bool hideFocus = false)
        {
            if (!IsInsideTree() || FocusMode == FocusModeEnum.None) return;
            GetViewport()?.SetFocus(this, hideFocus);
        }

        public void ReleaseFocus()
        {
            var vp = GetViewport();
            if (vp != null && vp.GuiFocus == this) vp.SetFocus(null, false);
        }

        internal void NotifyFocus(bool enter)
        {
            _Notification(enter ? NOTIFICATION_FOCUS_ENTER : NOTIFICATION_FOCUS_EXIT);
            if (enter) FocusEntered?.Invoke();
            else FocusExited?.Invoke();
            QueueRedraw();
        }

        public bool IsLayoutRtl() => false;

        // ---------- theme ----------
        public string ThemeTypeVariation
        {
            get => _typeVariation;
            set { _typeVariation = value ?? ""; if (IsInsideTree()) NotifyThemeChanged(); }
        }

        void OverrideChanged()
        {
            _themeCache.Clear();
            if (IsInsideTree())
            {
                _Notification(NOTIFICATION_THEME_CHANGED);
                OnThemeChanged();
                ThemeChanged?.Invoke();
                QueueRedraw();
                UpdateMinimumSize();
                SizeChanged();
            }
        }

        public void AddThemeColorOverride(string name, Col c) { (_ovColor ??= new Dictionary<string, Col>())[name] = c; OverrideChanged(); }
        public void AddThemeConstantOverride(string name, int v) { (_ovConst ??= new Dictionary<string, int>())[name] = v; OverrideChanged(); }
        public void AddThemeFontOverride(string name, Font f) { if (f == null) { RemoveThemeFontOverride(name); return; } (_ovFont ??= new Dictionary<string, Font>())[name] = f; OverrideChanged(); }
        public void AddThemeFontSizeOverride(string name, int s) { (_ovFontSize ??= new Dictionary<string, int>())[name] = s; OverrideChanged(); }
        public void AddThemeStyleboxOverride(string name, StyleBox s) { if (s == null) { RemoveThemeStyleboxOverride(name); return; } (_ovStyle ??= new Dictionary<string, StyleBox>())[name] = s; OverrideChanged(); }
        public void AddThemeIconOverride(string name, Texture2D t) { if (t == null) { RemoveThemeIconOverride(name); return; } (_ovIcon ??= new Dictionary<string, Texture2D>())[name] = t; OverrideChanged(); }
        public void RemoveThemeColorOverride(string name) { if (_ovColor?.Remove(name) == true) OverrideChanged(); }
        public void RemoveThemeConstantOverride(string name) { if (_ovConst?.Remove(name) == true) OverrideChanged(); }
        public void RemoveThemeFontOverride(string name) { if (_ovFont?.Remove(name) == true) OverrideChanged(); }
        public void RemoveThemeFontSizeOverride(string name) { if (_ovFontSize?.Remove(name) == true) OverrideChanged(); }
        public void RemoveThemeStyleboxOverride(string name) { if (_ovStyle?.Remove(name) == true) OverrideChanged(); }
        public void RemoveThemeIconOverride(string name) { if (_ovIcon?.Remove(name) == true) OverrideChanged(); }
        public bool HasThemeColorOverride(string name) => _ovColor?.ContainsKey(name) == true;
        public bool HasThemeConstantOverride(string name) => _ovConst?.ContainsKey(name) == true;
        public bool HasThemeFontOverride(string name) => _ovFont?.ContainsKey(name) == true;
        public bool HasThemeFontSizeOverride(string name) => _ovFontSize?.ContainsKey(name) == true;
        public bool HasThemeStyleboxOverride(string name) => _ovStyle?.ContainsKey(name) == true;
        public bool HasThemeIconOverride(string name) => _ovIcon?.ContainsKey(name) == true;

        readonly Dictionary<(int, string, string), object> _themeCache = new Dictionary<(int, string, string), object>();

        /// <summary>Type names to look up, as Godot's get_theme_type_dependencies: the variation chain, then the class chain.</summary>
        List<string> TypeChain(string type)
        {
            var o = new List<string>();
            if (!string.IsNullOrEmpty(type) && type != GetType().Name)
            {
                for (string t = type; t != null && !o.Contains(t); t = Theme.Default.GetTypeVariationBase(t)) o.Add(t);
                return o;
            }
            for (string t = _typeVariation; !string.IsNullOrEmpty(t) && !o.Contains(t); t = Theme.Default.GetTypeVariationBase(t)) o.Add(t);
            for (var t = GetType(); t != null && t != typeof(CanvasItem); t = t.BaseType) o.Add(t.Name);
            return o;
        }

        object Lookup(ThemeDataType dt, string name, string type)
        {
            var key = ((int)dt, name, type ?? "");
            if (_themeCache.TryGetValue(key, out var v)) return v;
            v = null;
            var chain = TypeChain(type);
            // Ancestor `theme` resources first (the theme owner chain), then the default theme.
            for (Node n = this; n != null && v == null; n = n.Parent)
            {
                if (n is Control c && c.Theme != null)
                    foreach (var t in chain)
                        if (c.Theme.TryGet(dt, name, t, out var tv)) { v = tv; break; }
            }
            if (v == null)
                foreach (var t in chain)
                    if (Theme.Default.TryGet(dt, name, t, out var tv)) { v = tv; break; }
            _themeCache[key] = v;
            return v;
        }

        public Col GetThemeColor(string name, string type = null)
        {
            if (string.IsNullOrEmpty(type) && _ovColor != null && _ovColor.TryGetValue(name, out var c)) return c;
            return Lookup(ThemeDataType.Color, name, type) is Col cc ? cc : new Col(0f, 0f, 0f, 1f);
        }

        public int GetThemeConstant(string name, string type = null)
        {
            if (string.IsNullOrEmpty(type) && _ovConst != null && _ovConst.TryGetValue(name, out var c)) return c;
            return Lookup(ThemeDataType.Constant, name, type) is int i ? i : 0;
        }

        public Font GetThemeFont(string name, string type = null)
        {
            if (string.IsNullOrEmpty(type) && _ovFont != null && _ovFont.TryGetValue(name, out var f)) return f;
            if (Lookup(ThemeDataType.Font, name, type) is Font ff) return ff;
            for (Node n = this; n != null; n = n.Parent)
                if (n is Control c && c.Theme?.DefaultFont != null) return c.Theme.DefaultFont;
            return Theme.Default.DefaultFont ?? ThemeDB.FallbackFont;
        }

        public int GetThemeFontSize(string name, string type = null)
        {
            if (string.IsNullOrEmpty(type) && _ovFontSize != null && _ovFontSize.TryGetValue(name, out var s) && s > 0) return s;
            if (Lookup(ThemeDataType.FontSize, name, type) is int i && i > 0) return i;
            for (Node n = this; n != null; n = n.Parent)
                if (n is Control c && c.Theme != null && c.Theme.DefaultFontSize > 0) return c.Theme.DefaultFontSize;
            return Theme.Default.DefaultFontSize > 0 ? Theme.Default.DefaultFontSize : ThemeDB.FallbackFontSize;
        }

        static readonly StyleBox _emptyStyle = new StyleBoxEmpty();

        public StyleBox GetThemeStylebox(string name, string type = null)
        {
            if (string.IsNullOrEmpty(type) && _ovStyle != null && _ovStyle.TryGetValue(name, out var s)) return s;
            return Lookup(ThemeDataType.StyleBox, name, type) as StyleBox ?? _emptyStyle;
        }

        public Texture2D GetThemeIcon(string name, string type = null)
        {
            if (string.IsNullOrEmpty(type) && _ovIcon != null && _ovIcon.TryGetValue(name, out var t)) return t;
            return Lookup(ThemeDataType.Icon, name, type) as Texture2D;
        }

        public bool HasThemeColor(string name, string type = null) => (string.IsNullOrEmpty(type) && HasThemeColorOverride(name)) || Lookup(ThemeDataType.Color, name, type) != null;
        public bool HasThemeConstant(string name, string type = null) => (string.IsNullOrEmpty(type) && HasThemeConstantOverride(name)) || Lookup(ThemeDataType.Constant, name, type) != null;
        public bool HasThemeStylebox(string name, string type = null) => (string.IsNullOrEmpty(type) && HasThemeStyleboxOverride(name)) || Lookup(ThemeDataType.StyleBox, name, type) != null;
        public bool HasThemeFont(string name, string type = null) => (string.IsNullOrEmpty(type) && HasThemeFontOverride(name)) || Lookup(ThemeDataType.Font, name, type) != null;

        /// <summary>begin_bulk_theme_override / end: overrides apply at the end.</summary>
        public void BeginBulkThemeOverride() { }
        public void EndBulkThemeOverride() { }

        // ---------- misc ----------
        public void ResetSize() => SetSize(Vec2.Zero);
        public void SetDragForwarding(object a, object b, object c) { }
        public Vec2 GetLocalMousePos() => GetLocalMousePosition();

        /// <summary>The Control's notification hook for child order (Godot queues a redraw).</summary>
        protected override void MoveChildNotify(Node child)
        {
            base.MoveChildNotify(child);
            QueueRedraw();
        }
    }
}
