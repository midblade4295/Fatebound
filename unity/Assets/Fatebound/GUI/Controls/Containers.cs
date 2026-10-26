// Fatebound GUI (Unity port): Godot's containers -- the deferred queue_sort, fit_child_in_rect, and the layouts of
// BoxContainer (stretch ratios with the accumulated-error pixel), GridContainer, CenterContainer, MarginContainer,
// PanelContainer, Panel, and ScrollContainer (scroll bars, touch drag with dead zone and fling), ported from scene/gui.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public partial class Container : Control
    {
        bool _pendingSort;
        public event Action SortChildren, PreSortChildren;

        public Container() { MouseFilter = MouseFilterEnum.Pass; }

        void ChildMinsizeChanged()
        {
            UpdateMinimumSize();
            QueueSort();
        }

        protected override void AddChildNotify(Node child)
        {
            base.AddChildNotify(child);
            if (!(child is Control c)) return;
            c.SizeFlagsChanged += QueueSort;
            c.MinimumSizeChanged += ChildMinsizeChanged;
            c.VisibilityChanged += ChildMinsizeChanged;
            UpdateMinimumSize();
            QueueSort();
        }

        protected override void MoveChildNotify(Node child)
        {
            base.MoveChildNotify(child);
            if (!(child is Control)) return;
            UpdateMinimumSize();
            QueueSort();
        }

        protected override void RemoveChildNotify(Node child)
        {
            base.RemoveChildNotify(child);
            if (!(child is Control c)) return;
            c.SizeFlagsChanged -= QueueSort;
            c.MinimumSizeChanged -= ChildMinsizeChanged;
            c.VisibilityChanged -= ChildMinsizeChanged;
            UpdateMinimumSize();
            QueueSort();
        }

        public void QueueSort()
        {
            if (!IsInsideTree() || _pendingSort) return;
            CallDeferred(DoSort);
            _pendingSort = true;
        }

        void DoSort()
        {
            if (!IsInsideTree()) { _pendingSort = false; return; }
            _Notification(NOTIFICATION_PRE_SORT_CHILDREN);
            PreSortChildren?.Invoke();
            _Notification(NOTIFICATION_SORT_CHILDREN);
            OnSortChildren();
            SortChildren?.Invoke();
            _pendingSort = false;
        }

        /// <summary>NOTIFICATION_SORT_CHILDREN: lay the children out.</summary>
        protected virtual void OnSortChildren() { }

        protected override void OnResized() => QueueSort();

        protected override void OnThemeChanged() => QueueSort();

        protected override void OnVisibilityChanged()
        {
            base.OnVisibilityChanged();
            if (IsVisibleInTree()) QueueSort();
        }

        public void FitChildInRect(Control child, Rect2 rect)
        {
            if (child == null || child.Parent != this) return;
            Vec2 min = child.GetCombinedMinimumSize();
            Vec2 max = child.GetCombinedMaximumSize();
            Rect2 r = rect;
            var hf = child.SizeFlagsHorizontal;
            var vf = child.SizeFlagsVertical;
            if ((hf & SizeFlags.Fill) == 0)
            {
                float w = min.x;
                if (max.x >= 0) w = Math.Min(w, max.x);
                r.size = new Vec2(w, r.size.y);
                if ((hf & SizeFlags.ShrinkEnd) != 0) r.position = new Vec2(r.position.x + rect.size.x - w, r.position.y);
                else if ((hf & SizeFlags.ShrinkCenter) != 0) r.position = new Vec2(r.position.x + MathF.Floor((rect.size.x - w) / 2), r.position.y);
            }
            if ((vf & SizeFlags.Fill) == 0)
            {
                float h = min.y;
                if (max.y >= 0) h = Math.Min(h, max.y);
                r.size = new Vec2(r.size.x, h);
                if ((vf & SizeFlags.ShrinkEnd) != 0) r.position = new Vec2(r.position.x, r.position.y + rect.size.y - h);
                else if ((vf & SizeFlags.ShrinkCenter) != 0) r.position = new Vec2(r.position.x, r.position.y + MathF.Floor((rect.size.y - h) / 2));
            }
            child.SetRect(r);
            child.Rotation = 0;
            child.Scale = Vec2.One;
        }

        protected enum Sortable { VisibleInTree, Visible, Ignore }

        protected Control AsSortable(Node n, Sortable mode = Sortable.VisibleInTree)
        {
            var c = n as Control;
            if (c == null || c.TopLevel) return null;
            if (mode == Sortable.Visible && !c.Visible) return null;
            if (mode == Sortable.VisibleInTree && !c.IsVisibleInTree()) return null;
            return c;
        }

        static float CeilF(float v) => MathF.Ceiling(v);
        protected static Vec2 CeilV(Vec2 v) => new Vec2(CeilF(v.x), CeilF(v.y));
    }

    public partial class BoxContainer : Container
    {
        public enum AlignmentMode { Begin = 0, Center = 1, End = 2 }
        public const AlignmentMode ALIGNMENT_BEGIN = AlignmentMode.Begin, ALIGNMENT_CENTER = AlignmentMode.Center, ALIGNMENT_END = AlignmentMode.End;
        protected bool vertical;
        AlignmentMode _alignment = AlignmentMode.Begin;

        public bool Vertical { get => vertical; set { vertical = value; QueueSort(); UpdateMinimumSize(); } }
        public AlignmentMode Alignment { get => _alignment; set { if (_alignment == value) return; _alignment = value; Resort(); } }

        int Separation => GetThemeConstant("separation");

        struct Msc { public int min, max, final; public bool stretch; }

        void Resort()
        {
            Vec2 ns = Size;
            int nsx = (int)ns.x, nsy = (int)ns.y;
            int count = 0, stretchMin = 0, stretchAvail = 0;
            float ratioTotal = 0f;
            var cache = new Dictionary<Control, Msc>();
            int sep = Separation;
            int nChildren = GetChildCount();
            for (int i = 0; i < nChildren; i++)
            {
                var c = AsSortable(GetChild(i));
                if (c == null) continue;
                Vec2 mn = CeilV(c.GetBoundMinimumSize());
                Vec2 mx = c.GetCombinedMaximumSize();
                var m = new Msc();
                if (vertical)
                {
                    stretchMin += (int)mn.y;
                    m.min = (int)mn.y;
                    m.max = (int)mx.y;
                    m.stretch = (c.SizeFlagsVertical & SizeFlags.Expand) != 0;
                }
                else
                {
                    stretchMin += (int)mn.x;
                    m.min = (int)mn.x;
                    m.max = (int)mx.x;
                    m.stretch = (c.SizeFlagsHorizontal & SizeFlags.Expand) != 0;
                }
                if (m.max >= 0 && m.max < m.min) m.max = m.min;
                if (m.stretch)
                {
                    stretchAvail += m.min;
                    ratioTotal += (float)c.SizeFlagsStretchRatio;
                }
                m.final = m.min;
                cache[c] = m;
                count++;
            }
            if (count == 0) return;
            int stretchMax = (vertical ? nsy : nsx) - (count - 1) * sep;
            int stretchDiff = stretchMax - stretchMin;
            if (stretchDiff < 0) stretchDiff = 0;
            stretchAvail += stretchDiff;
            while (ratioTotal > 0)
            {
                bool ok = true;
                float error = 0f;
                for (int i = 0; i < nChildren; i++)
                {
                    var c = AsSortable(GetChild(i));
                    if (c == null) continue;
                    var m = cache[c];
                    if (m.stretch)
                    {
                        float ratio = (float)c.SizeFlagsStretchRatio;
                        float px = stretchAvail * ratio / ratioTotal;
                        error += px - (int)px;
                        if (px < m.min)
                        {
                            m.stretch = false;
                            ratioTotal -= ratio;
                            ok = false;
                            stretchAvail -= m.min;
                            m.final = m.min;
                            cache[c] = m;
                            break;
                        }
                        else if (m.max >= 0 && px > m.max)
                        {
                            m.stretch = false;
                            ratioTotal -= ratio;
                            ok = false;
                            stretchAvail -= m.max;
                            m.final = m.max;
                            cache[c] = m;
                            break;
                        }
                        else
                        {
                            m.final = (int)px;
                            if (error >= 1 && (m.max < 0 || m.final < m.max))
                            {
                                m.final += 1;
                                error -= 1;
                            }
                            cache[c] = m;
                        }
                    }
                }
                if (ok) break;
            }
            int ofs = 0;
            int finalDiff = stretchMax - stretchMin;
            for (int i = 0; i < nChildren; i++)
            {
                var c = AsSortable(GetChild(i));
                if (c == null) continue;
                var m = cache[c];
                finalDiff -= m.final - m.min;
            }
            if (finalDiff < 0) finalDiff = 0;
            if (_alignment == AlignmentMode.Center) ofs = finalDiff / 2;
            else if (_alignment == AlignmentMode.End) ofs = finalDiff;
            bool first = true;
            int idx = 0;
            for (int i = 0; i < nChildren; i++)
            {
                var c = AsSortable(GetChild(i));
                if (c == null) continue;
                var m = cache[c];
                if (first) first = false;
                else ofs += sep;
                int from = ofs, to = ofs + m.final;
                if (m.stretch && idx == count - 1) to = vertical ? nsy : nsx;
                int size = to - from;
                Rect2 rect = vertical ? new Rect2(0, from, ns.x, size) : new Rect2(from, 0, size, ns.y);
                FitChildInRect(c, rect);
                ofs = to;
                idx++;
            }
        }

        public override Vec2 GetMinimumSize()
        {
            int w = 0, h = 0;
            bool first = true;
            int sep = Separation;
            int n = GetChildCount();
            for (int i = 0; i < n; i++)
            {
                var c = AsSortable(GetChild(i), Sortable.Visible);
                if (c == null) continue;
                Vec2 s = CeilV(c.GetBoundMinimumSize());
                int sw = (int)s.x, sh = (int)s.y;
                if (vertical)
                {
                    if (sw > w) w = sw;
                    h += sh + (first ? 0 : sep);
                }
                else
                {
                    if (sh > h) h = sh;
                    w += sw + (first ? 0 : sep);
                }
                first = false;
            }
            return new Vec2(w, h);
        }

        protected override void OnSortChildren() => Resort();

        protected override void OnThemeChanged()
        {
            base.OnThemeChanged();
            UpdateMinimumSize();
        }

        /// <summary>add_spacer: an expanding Control.</summary>
        public Control AddSpacer(bool begin)
        {
            var c = new Control { MouseFilter = MouseFilterEnum.Pass };
            if (vertical) c.SizeFlagsVertical = SizeFlags.ExpandFill;
            else c.SizeFlagsHorizontal = SizeFlags.ExpandFill;
            AddChild(c);
            if (begin) MoveChild(c, 0);
            return c;
        }
    }

    public partial class HBoxContainer : BoxContainer { public HBoxContainer() { vertical = false; } }
    public partial class VBoxContainer : BoxContainer { public VBoxContainer() { vertical = true; } }

    public partial class GridContainer : Container
    {
        int _columns = 1;
        public int Columns { get => _columns; set { _columns = Math.Max(1, value); QueueSort(); UpdateMinimumSize(); } }

        protected override void OnSortChildren()
        {
            Resort();
            UpdateMinimumSize();
        }

        protected override void OnThemeChanged()
        {
            base.OnThemeChanged();
            UpdateMinimumSize();
        }

        void Resort()
        {
            var colMinw = new SortedDictionary<int, int>();
            var rowMinh = new SortedDictionary<int, int>();
            var colMaxw = new SortedDictionary<int, int>();
            var rowMaxh = new SortedDictionary<int, int>();
            var colFixed = new Dictionary<int, int>();
            var rowFixed = new Dictionary<int, int>();
            var colExp = new SortedSet<int>();
            var rowExp = new SortedSet<int>();
            int hsep = GetThemeConstant("h_separation"), vsep = GetThemeConstant("v_separation");
            int valid = 0;
            Vec2 sz = Size;
            int sw = (int)sz.x, sh = (int)sz.y;
            Vec2 cmax = GetCombinedMaximumSize();
            int cmw = (int)cmax.x, cmh = (int)cmax.y;
            int n = GetChildCount();
            for (int i = 0; i < n; i++)
            {
                var c = AsSortable(GetChild(i));
                if (c == null) continue;
                int row = valid / _columns, col = valid % _columns;
                valid++;
                Vec2 msf = c.GetBoundMinimumSize();
                int msw = (int)msf.x, msh = (int)msf.y;
                Vec2 mx = c.GetCombinedMaximumSize();
                colMinw[col] = colMinw.TryGetValue(col, out var cw) ? Math.Max(cw, msw) : msw;
                rowMinh[row] = rowMinh.TryGetValue(row, out var rh) ? Math.Max(rh, msh) : msh;
                int maxW = (int)mx.x >= 0 ? (int)mx.x : (cmw >= 0 ? cmw : sw);
                colMaxw[col] = colMaxw.TryGetValue(col, out var cmx) ? Math.Max(cmx, maxW) : maxW;
                int maxH = (int)mx.y >= 0 ? (int)mx.y : (cmh >= 0 ? cmh : sh);
                rowMaxh[row] = rowMaxh.TryGetValue(row, out var rmx) ? Math.Max(rmx, maxH) : maxH;
                if ((c.SizeFlagsHorizontal & SizeFlags.Expand) != 0) colExp.Add(col);
                if ((c.SizeFlagsVertical & SizeFlags.Expand) != 0) rowExp.Add(row);
            }
            foreach (var k in new List<int>(colMaxw.Keys)) if (colMaxw[k] < colMinw[k]) colMaxw[k] = colMinw[k];
            foreach (var k in new List<int>(rowMaxh.Keys)) if (rowMaxh[k] < rowMinh[k]) rowMaxh[k] = rowMinh[k];
            int maxCol = Math.Min(valid, _columns);
            int maxRow = (int)Math.Ceiling(valid / (float)_columns);
            for (int i = valid; i < _columns; i++) colExp.Add(i);
            float remW = sz.x, remH = sz.y;
            foreach (var kv in colMinw) if (!colExp.Contains(kv.Key)) remW -= kv.Value;
            foreach (var kv in rowMinh) if (!rowExp.Contains(kv.Key)) remH -= kv.Value;
            remH -= vsep * Math.Max(maxRow - 1, 0);
            remW -= hsep * Math.Max(maxCol - 1, 0);
            int CMin(int k) => colMinw.TryGetValue(k, out var v) ? v : 0;
            int RMin(int k) => rowMinh.TryGetValue(k, out var v) ? v : 0;
            bool canFit = false;
            while (!canFit && colExp.Count > 0)
            {
                canFit = true;
                int maxIndex = colExp.Min;
                foreach (int e in colExp)
                {
                    if (CMin(e) > CMin(maxIndex)) maxIndex = e;
                    if (canFit && (remW / colExp.Count) < CMin(e)) canFit = false;
                }
                if (!canFit)
                {
                    colExp.Remove(maxIndex);
                    remW -= CMin(maxIndex);
                    colFixed[maxIndex] = CMin(maxIndex);
                }
            }
            canFit = false;
            while (!canFit && rowExp.Count > 0)
            {
                canFit = true;
                int maxIndex = rowExp.Min;
                foreach (int e in rowExp)
                {
                    if (RMin(e) > RMin(maxIndex)) maxIndex = e;
                    if (canFit && (remH / rowExp.Count) < RMin(e)) canFit = false;
                }
                if (!canFit)
                {
                    rowExp.Remove(maxIndex);
                    remH -= RMin(maxIndex);
                    rowFixed[maxIndex] = RMin(maxIndex);
                }
            }
            bool maxFit = false;
            while (!maxFit && colExp.Count > 0)
            {
                maxFit = true;
                int capped = -1;
                foreach (int e in colExp)
                    if (colMaxw.ContainsKey(e) && (remW / colExp.Count) > colMaxw[e]) { capped = e; maxFit = false; break; }
                if (capped >= 0)
                {
                    colExp.Remove(capped);
                    remW -= colMaxw[capped];
                    colFixed[capped] = colMaxw[capped];
                }
            }
            maxFit = false;
            while (!maxFit && rowExp.Count > 0)
            {
                maxFit = true;
                int capped = -1;
                foreach (int e in rowExp)
                    if (rowMaxh.ContainsKey(e) && (remH / rowExp.Count) > rowMaxh[e]) { capped = e; maxFit = false; break; }
                if (capped >= 0)
                {
                    rowExp.Remove(capped);
                    remH -= rowMaxh[capped];
                    rowFixed[capped] = rowMaxh[capped];
                }
            }
            int colRemPx = 0, colExpand = 0;
            if (colExp.Count > 0)
            {
                colExpand = (int)(remW / colExp.Count);
                colRemPx = (int)(remW - colExp.Count * colExpand);
            }
            int rowRemPx = 0, rowExpand = 0;
            if (rowExp.Count > 0)
            {
                rowExpand = (int)(remH / rowExp.Count);
                rowRemPx = (int)(remH - rowExp.Count * rowExpand);
            }
            int colOfs = 0, rowOfs = 0;
            int colRemIdx = 0;
            for (int i = 0; i < maxCol; i++)
            {
                if (colRemPx == 0) break;
                if (colExp.Contains(i)) { colRemIdx = i + 1; colRemPx--; }
            }
            int rowRemIdx = 0;
            for (int i = 0; i < maxRow; i++)
            {
                if (rowRemPx == 0) break;
                if (rowExp.Contains(i)) { rowRemIdx = i + 1; rowRemPx--; }
            }
            valid = 0;
            for (int i = 0; i < n; i++)
            {
                var c = AsSortable(GetChild(i));
                if (c == null) continue;
                int row = valid / _columns, col = valid % _columns;
                valid++;
                if (col == 0)
                {
                    colOfs = 0;
                    if (row > 0)
                    {
                        rowOfs += (rowExp.Contains(row - 1) ? rowExpand : RMin(row - 1)) + vsep;
                        if (rowExp.Contains(row - 1) && row - 1 < rowRemIdx) rowOfs++;
                    }
                }
                float w = colExp.Contains(col) ? colExpand : (colFixed.TryGetValue(col, out var fw) ? fw : CMin(col));
                float h = rowExp.Contains(row) ? rowExpand : (rowFixed.TryGetValue(row, out var fh) ? fh : RMin(row));
                if (colExp.Contains(col) && col < colRemIdx) w++;
                if (rowExp.Contains(row) && row < rowRemIdx) h++;
                FitChildInRect(c, new Rect2(colOfs, rowOfs, w, h));
                colOfs += (int)w + hsep;
            }
        }

        public override Vec2 GetMinimumSize()
        {
            var colMinw = new Dictionary<int, int>();
            var rowMinh = new Dictionary<int, int>();
            int maxRow = 0, maxCol = 0, valid = 0;
            int n = GetChildCount();
            for (int i = 0; i < n; i++)
            {
                var c = AsSortable(GetChild(i), Sortable.Visible);
                if (c == null) continue;
                int row = valid / _columns, col = valid % _columns;
                valid++;
                Vec2 ms = c.GetBoundMinimumSize();
                int w = (int)ms.x, h = (int)ms.y;
                colMinw[col] = colMinw.TryGetValue(col, out var cw) ? Math.Max(cw, w) : w;
                rowMinh[row] = rowMinh.TryGetValue(row, out var rh) ? Math.Max(rh, h) : h;
                maxCol = Math.Max(col, maxCol);
                maxRow = Math.Max(row, maxRow);
            }
            float W = 0, H = 0;
            foreach (var v in colMinw.Values) W += v;
            foreach (var v in rowMinh.Values) H += v;
            H += GetThemeConstant("v_separation") * maxRow;
            W += GetThemeConstant("h_separation") * maxCol;
            return new Vec2(W, H);
        }
    }

    public partial class CenterContainer : Container
    {
        bool _topLeft;
        public bool UseTopLeft { get => _topLeft; set { if (_topLeft == value) return; _topLeft = value; UpdateMinimumSize(); QueueSort(); } }

        public override Vec2 GetMinimumSize()
        {
            if (_topLeft) return Vec2.Zero;
            Vec2 ms = Vec2.Zero;
            int n = GetChildCount();
            for (int i = 0; i < n; i++)
            {
                var c = AsSortable(GetChild(i), Sortable.Visible);
                if (c == null) continue;
                Vec2 m = c.GetBoundMinimumSize();
                ms = new Vec2(Math.Max(ms.x, m.x), Math.Max(ms.y, m.y));
            }
            return ms;
        }

        protected override void OnSortChildren()
        {
            Vec2 size = Size;
            int n = GetChildCount();
            for (int i = 0; i < n; i++)
            {
                var c = AsSortable(GetChild(i));
                if (c == null) continue;
                Vec2 m = c.GetBoundMinimumSize();
                Vec2 ofs = _topLeft ? (-m * 0.5).Floor() : ((size - m) / 2.0).Floor();
                FitChildInRect(c, new Rect2(ofs, m));
            }
        }
    }

    public partial class MarginContainer : Container
    {
        int ML => GetThemeConstant("margin_left");
        int MT => GetThemeConstant("margin_top");
        int MR => GetThemeConstant("margin_right");
        int MB => GetThemeConstant("margin_bottom");

        public override Vec2 GetMinimumSize()
        {
            Vec2 max = Vec2.Zero;
            int n = GetChildCount();
            for (int i = 0; i < n; i++)
            {
                var c = AsSortable(GetChild(i), Sortable.Visible);
                if (c == null) continue;
                Vec2 s = c.GetBoundMinimumSize();
                max = new Vec2(Math.Max(max.x, s.x), Math.Max(max.y, s.y));
            }
            return new Vec2(max.x + ML + MR, max.y + MT + MB);
        }

        public int GetMarginSize(Side s) => s == Side.Left ? ML : s == Side.Right ? MR : s == Side.Top ? MT : MB;

        protected override void OnSortChildren()
        {
            Vec2 s = Size;
            int n = GetChildCount();
            for (int i = 0; i < n; i++)
            {
                var c = AsSortable(GetChild(i));
                if (c == null) continue;
                int w = (int)(s.x - ML - MR);
                int h = (int)(s.y - MT - MB);
                FitChildInRect(c, new Rect2(ML, MT, w, h));
            }
        }

        protected override void OnThemeChanged()
        {
            base.OnThemeChanged();
            UpdateMinimumSize();
        }
    }

    public partial class PanelContainer : Container
    {
        public PanelContainer() { MouseFilter = MouseFilterEnum.Stop; }

        StyleBox Panel => GetThemeStylebox("panel");

        public override Vec2 GetMinimumSize()
        {
            Vec2 ms = Vec2.Zero;
            int n = GetChildCount();
            for (int i = 0; i < n; i++)
            {
                var c = AsSortable(GetChild(i), Sortable.Visible);
                if (c == null) continue;
                Vec2 m = c.GetBoundMinimumSize();
                ms = new Vec2(Math.Max(ms.x, m.x), Math.Max(ms.y, m.y));
            }
            var p = Panel;
            if (p != null) ms = ms + p.GetMinimumSize();
            return ms;
        }

        protected override void OnDraw() => Panel?.Draw(drawList, new Rect2(Vec2.Zero, Size));

        protected override void OnSortChildren()
        {
            Vec2 size = Size;
            Vec2 ofs = Vec2.Zero;
            var p = Panel;
            if (p != null)
            {
                size = size - p.GetMinimumSize();
                ofs = ofs + p.GetOffset();
            }
            int n = GetChildCount();
            for (int i = 0; i < n; i++)
            {
                var c = AsSortable(GetChild(i));
                if (c == null) continue;
                FitChildInRect(c, new Rect2(ofs, size));
            }
        }
    }

    /// <summary>Panel: a Control that draws its "panel" stylebox.</summary>
    public partial class Panel : Control
    {
        public Panel() { MouseFilter = MouseFilterEnum.Stop; }
        protected override void OnDraw() => GetThemeStylebox("panel")?.Draw(drawList, new Rect2(Vec2.Zero, Size));
    }

    /// <summary>Range: value, min, max, step, page (Godot's Range; named so it does not clash with System.Range).</summary>
    public partial class RangeControl : Control
    {
        double _min, _max = 100, _step = 1, _page, _value;
        public bool Rounded, AllowGreater, AllowLesser, ExpEdit;
        public event Action<double> ValueChanged;
        public event Action Changed;

        public double MinValue { get => _min; set { _min = value; ClampValue(); OnRangeChanged(); } }
        public double MaxValue { get => _max; set { _max = value; ClampValue(); OnRangeChanged(); } }
        public double Step { get => _step; set { _step = value; OnRangeChanged(); } }
        public double Page { get => _page; set { _page = value; ClampValue(); OnRangeChanged(); } }

        public double Value
        {
            get => _value;
            set => SetValue(value);
        }

        public void SetValueNoSignal(double v) => SetValue(v, false);

        void SetValue(double v, bool signal = true)
        {
            if (_step > 0) v = Math.Round((v - _min) / _step) * _step + _min;
            if (Rounded) v = Math.Round(v);
            if (!AllowGreater && v > _max - _page) v = _max - _page;
            if (!AllowLesser && v < _min) v = _min;
            if (_value == v) return;
            _value = v;
            QueueRedraw();
            OnValueChanged();
            if (signal) ValueChanged?.Invoke(_value);
        }

        void ClampValue()
        {
            double v = _value;
            if (!AllowGreater && v > _max - _page) v = _max - _page;
            if (!AllowLesser && v < _min) v = _min;
            if (v != _value) { _value = v; OnValueChanged(); ValueChanged?.Invoke(_value); }
        }

        void OnRangeChanged() { QueueRedraw(); Changed?.Invoke(); }

        protected virtual void OnValueChanged() { }

        public double Ratio
        {
            get
            {
                if (_max == _min) return 1;
                return Math.Max(0, Math.Min(1, (_value - _min) / (_max - _min)));
            }
            set => Value = _min + (_max - _min) * value;
        }
    }

    public partial class ScrollBar : RangeControl
    {
        protected bool vertical;
        public const double PAGE_DIVISOR = 8.0;
        bool _dragging;
        double _dragOfs;
        public event Action Scrolling;

        public ScrollBar() { Step = 0; MouseFilter = MouseFilterEnum.Stop; }

        public override Vec2 GetMinimumSize()
        {
            var bg = GetThemeStylebox("scroll");
            var gr = GetThemeStylebox("grabber");
            Vec2 b = bg.GetMinimumSize(), g = gr.GetMinimumSize();
            return vertical ? new Vec2(Math.Max(b.x, g.x), b.y + g.y) : new Vec2(b.x + g.x, Math.Max(b.y, g.y));
        }

        public void Scroll(double amount) => Value = Value + amount;
        public void ScrollTo(double v) => Value = v;
        protected override void OnValueChanged() => Scrolling?.Invoke();

        float GrabberSize()
        {
            float area = vertical ? Size.y : Size.x;
            double range = MaxValue - MinValue;
            if (range <= 0) return area;
            float min = vertical ? GetThemeStylebox("grabber").GetMinimumSize().y : GetThemeStylebox("grabber").GetMinimumSize().x;
            return (float)Math.Max(min, area * Page / range);
        }

        float GrabberOfs()
        {
            float area = vertical ? Size.y : Size.x;
            double range = MaxValue - MinValue - Page;
            if (range <= 0) return 0;
            return (float)((Value - MinValue) / range * (area - GrabberSize()));
        }

        protected override void OnDraw()
        {
            GetThemeStylebox("scroll").Draw(drawList, new Rect2(Vec2.Zero, Size));
            float gs = GrabberSize(), go = GrabberOfs();
            var r = vertical ? new Rect2(0, go, Size.x, gs) : new Rect2(go, 0, gs, Size.y);
            GetThemeStylebox(_dragging ? "grabber_pressed" : "grabber").Draw(drawList, r);
        }

        protected override void OnGuiInput(InputEvent e)
        {
            if (e is InputEventMouseButton mb && mb.ButtonIndex == MouseButton.Left)
            {
                if (mb.Pressed)
                {
                    float p = vertical ? mb.Position.y : mb.Position.x;
                    float go = GrabberOfs(), gs = GrabberSize();
                    if (p < go) Scroll(-Page);
                    else if (p > go + gs) Scroll(Page);
                    else { _dragging = true; _dragOfs = p - go; }
                }
                else _dragging = false;
                AcceptEvent();
                QueueRedraw();
            }
            else if (e is InputEventMouseMotion mm && _dragging)
            {
                float p = (vertical ? mm.Position.y : mm.Position.x) - (float)_dragOfs;
                float area = (vertical ? Size.y : Size.x) - GrabberSize();
                if (area > 0) Value = MinValue + p / area * (MaxValue - MinValue - Page);
                AcceptEvent();
            }
        }
    }

    public partial class VScrollBar : ScrollBar { public VScrollBar() { vertical = true; } }
    public partial class HScrollBar : ScrollBar { public HScrollBar() { vertical = false; } }

    public partial class ScrollContainer : Container
    {
        public enum ScrollMode { Disabled = 0, Auto = 1, ShowAlways = 2, ShowNever = 3, Reserve = 4, MaximizeFirst = 5 }
        public const ScrollMode SCROLL_MODE_DISABLED = ScrollMode.Disabled, SCROLL_MODE_AUTO = ScrollMode.Auto, SCROLL_MODE_SHOW_ALWAYS = ScrollMode.ShowAlways,
            SCROLL_MODE_SHOW_NEVER = ScrollMode.ShowNever, SCROLL_MODE_RESERVE = ScrollMode.Reserve;
        readonly HScrollBar _h = new HScrollBar { Name = "_h_scroll" };
        readonly VScrollBar _v = new VScrollBar { Name = "_v_scroll" };
        ScrollMode _hMode = ScrollMode.Auto, _vMode = ScrollMode.Auto;
        Vec2 _largest;
        public int ScrollDeadzone;
        public bool FollowFocus;
        public bool DrawFocusBorder;
        bool _dragTouching, _dragDeaccel, _beyondDeadzone;
        Vec2 _dragSpeed, _dragAccum, _lastDragAccum, _dragFrom;
        double _timeSinceMotion;
        public event Action ScrollStarted, ScrollEnded;

        public ScrollContainer()
        {
            ClipContents = true;
            _h.FocusMode = FocusModeEnum.None;
            _v.FocusMode = FocusModeEnum.None;
            AddChild(_h, false, InternalMode.Front);
            AddChild(_v, false, InternalMode.Front);
            _h.Scrolling += QueueSortScroll;
            _v.Scrolling += QueueSortScroll;
            SetProcess(false);
        }

        void QueueSortScroll() => QueueSort();

        public HScrollBar GetHScrollBar() => _h;
        public VScrollBar GetVScrollBar() => _v;

        public ScrollMode HorizontalScrollMode { get => _hMode; set { _hMode = value; UpdateMinimumSize(); QueueSort(); } }
        public ScrollMode VerticalScrollMode { get => _vMode; set { _vMode = value; UpdateMinimumSize(); QueueSort(); } }

        public int ScrollHorizontal { get => (int)_h.Value; set { _h.Value = value; QueueSort(); } }
        public int ScrollVertical { get => (int)_v.Value; set { _v.Value = value; QueueSort(); } }

        Rect2 Margins()
        {
            var p = GetThemeStylebox("panel");
            return new Rect2(p.GetMargin(Side.Left), p.GetMargin(Side.Top), p.GetMargin(Side.Right), p.GetMargin(Side.Bottom));
        }

        bool HVisible => _h.Visible;
        bool VVisible => _v.Visible;
        int HSep => GetThemeConstant("scrollbar_h_separation");
        int VSep => GetThemeConstant("scrollbar_v_separation");

        public override Vec2 GetMinimumSize()
        {
            _largest = Vec2.Zero;
            int n = GetChildCount();
            for (int i = 0; i < n; i++)
            {
                var c = AsSortable(GetChild(i), Sortable.Visible);
                if (c == null) continue;
                Vec2 m = c.GetBoundMinimumSize();
                _largest = new Vec2(Math.Max(_largest.x, m.x), Math.Max(_largest.y, m.y));
            }
            Vec2 min = Vec2.Zero;
            Vec2 size = Size;
            bool vShow = _vMode == ScrollMode.ShowAlways || _vMode == ScrollMode.Reserve || ((_vMode == ScrollMode.Auto || _vMode == ScrollMode.MaximizeFirst) && _largest.y > size.y);
            bool hShow = _hMode == ScrollMode.ShowAlways || _hMode == ScrollMode.Reserve || ((_hMode == ScrollMode.Auto || _hMode == ScrollMode.MaximizeFirst) && _largest.x > size.x);
            if (_hMode == ScrollMode.Disabled || _hMode == ScrollMode.MaximizeFirst)
            {
                min.x = _largest.x;
                if (vShow) min.x += _v.GetMinimumSize().x + HSep;
            }
            if (_vMode == ScrollMode.Disabled || _vMode == ScrollMode.MaximizeFirst)
            {
                min.y = _largest.y;
                if (hShow) min.y += _h.GetMinimumSize().y + VSep;
            }
            Rect2 m2 = Margins();
            return min + m2.position + m2.size;
        }

        void UpdateScrollbars()
        {
            Rect2 m = Margins();
            Vec2 size = Size - (m.position + m.size);
            Vec2 hmin = _h.GetBoundMinimumSize(), vmin = _v.GetBoundMinimumSize();
            _h.Visible = _hMode == ScrollMode.ShowAlways || ((_hMode == ScrollMode.Auto || _hMode == ScrollMode.Reserve || _hMode == ScrollMode.MaximizeFirst) && _largest.x > size.x);
            _v.Visible = _vMode == ScrollMode.ShowAlways || ((_vMode == ScrollMode.Auto || _vMode == ScrollMode.Reserve || _vMode == ScrollMode.MaximizeFirst) && _largest.y > size.y);
            _h.MaxValue = _largest.x;
            _h.Page = VVisible ? size.x - vmin.x : size.x;
            _v.MaxValue = _largest.y;
            _v.Page = HVisible ? size.y - hmin.y : size.y;
            // scroll bar placement (_update_scrollbar_position)
            float hh = hmin.y, vw = vmin.x;
            _h.SetAnchorsAndOffsetsPreset(LayoutPreset.TopLeft);
            _v.SetAnchorsAndOffsetsPreset(LayoutPreset.TopLeft);
            _h.SetRect(new Rect2(m.position.x, Size.y - m.size.y - hh, Size.x - m.position.x - m.size.x - (VVisible ? vw : 0), hh));
            _v.SetRect(new Rect2(Size.x - m.size.x - vw, m.position.y, vw, Size.y - m.position.y - m.size.y - (HVisible ? hh : 0)));
        }

        void Reposition()
        {
            GetMinimumSize();
            UpdateScrollbars();
            Rect2 m = Margins();
            Vec2 size = Size - (m.position + m.size);
            Vec2 ofs = m.position;
            if (HVisible || _hMode == ScrollMode.Reserve) size.y -= _h.GetMinimumSize().y + VSep;
            if (VVisible || _vMode == ScrollMode.Reserve) size.x -= _v.GetMinimumSize().x + HSep;
            int n = GetChildCount();
            for (int i = 0; i < n; i++)
            {
                var c = AsSortable(GetChild(i));
                if (c == null) continue;
                Vec2 mn = c.GetCombinedMinimumSize(), mx = c.GetCombinedMaximumSize();
                Rect2 r = new Rect2(new Vec2(-ScrollHorizontal, -ScrollVertical), mn);
                if ((c.SizeFlagsHorizontal & SizeFlags.Expand) != 0)
                {
                    float w = Math.Max(size.x, mn.x);
                    if (mx.x >= 0) w = Math.Min(w, mx.x);
                    r.size = new Vec2(w, r.size.y);
                }
                if ((c.SizeFlagsVertical & SizeFlags.Expand) != 0)
                {
                    float h = Math.Max(size.y, mn.y);
                    if (mx.y >= 0) h = Math.Min(h, mx.y);
                    r.size = new Vec2(r.size.x, h);
                }
                r.position = (r.position + ofs).Floor();
                FitChildInRect(c, r);
            }
            QueueRedraw();
        }

        protected override void OnSortChildren() => Reposition();

        protected override void _Ready() { }

        protected override void OnPostEnterTree()
        {
            base.OnPostEnterTree();
            CallDeferred(Reposition);
        }

        protected override void OnDraw() => GetThemeStylebox("panel").Draw(drawList, new Rect2(Vec2.Zero, Size));

        void CancelDrag()
        {
            SetProcess(false);
            _dragDeaccel = false;
            _dragTouching = false;
            _dragSpeed = Vec2.Zero;
            _dragAccum = Vec2.Zero;
            _lastDragAccum = Vec2.Zero;
            _dragFrom = Vec2.Zero;
            if (_beyondDeadzone)
            {
                ScrollEnded?.Invoke();
                _beyondDeadzone = false;
            }
        }

        protected override void OnGuiInput(InputEvent e)
        {
            double prevV = _v.Value, prevH = _h.Value;
            bool hOn = _hMode != ScrollMode.Disabled, vOn = _vMode != ScrollMode.Disabled;
            if (e is InputEventMouseButton mb)
            {
                if (mb.Pressed)
                {
                    bool mod = false;
                    if (mb.ButtonIndex == MouseButton.WheelUp && vOn) { _v.Scroll(-_v.Page / ScrollBar.PAGE_DIVISOR * mb.Factor); mod = true; }
                    if (mb.ButtonIndex == MouseButton.WheelDown && vOn) { _v.Scroll(_v.Page / ScrollBar.PAGE_DIVISOR * mb.Factor); mod = true; }
                    if (mod && (_v.Value != prevV || _h.Value != prevH)) { AcceptEvent(); return; }
                }
                if (!Input.IsTouchscreenAvailable() || mb.ButtonIndex != MouseButton.Left) return;
                if (mb.Pressed)
                {
                    if (_dragTouching) CancelDrag();
                    _dragSpeed = Vec2.Zero;
                    _dragAccum = Vec2.Zero;
                    _lastDragAccum = Vec2.Zero;
                    _dragFrom = new Vec2((float)prevH, (float)prevV);
                    _dragTouching = true;
                    _dragDeaccel = false;
                    _beyondDeadzone = false;
                    _timeSinceMotion = 0;
                    SetProcess(true);
                }
                else if (_dragTouching)
                {
                    if (_dragSpeed == Vec2.Zero) CancelDrag();
                    else _dragDeaccel = true;
                }
                return;
            }
            if (e is InputEventMouseMotion mm)
            {
                if (_dragTouching && !_dragDeaccel)
                {
                    Vec2 motion = mm.Relative;
                    _dragAccum = _dragAccum - motion;
                    if (_beyondDeadzone || (hOn && Math.Abs(_dragAccum.x) > ScrollDeadzone) || (vOn && Math.Abs(_dragAccum.y) > ScrollDeadzone))
                    {
                        if (!_beyondDeadzone)
                        {
                            ScrollStarted?.Invoke();
                            _beyondDeadzone = true;
                            _dragAccum = -motion;
                        }
                        Vec2 diff = _dragFrom + _dragAccum;
                        if (hOn) _h.ScrollTo(diff.x); else _dragAccum.x = 0;
                        if (vOn) _v.ScrollTo(diff.y); else _dragAccum.y = 0;
                        _timeSinceMotion = 0;
                    }
                }
                if (_v.Value != prevV || _h.Value != prevH) AcceptEvent();
            }
        }

        protected override void _Process(double delta)
        {
            if (!_dragTouching) return;
            if (_dragDeaccel)
            {
                Vec2 pos = new Vec2((float)_h.Value, (float)_v.Value) + _dragSpeed * delta;
                bool offH = false, offV = false;
                if (pos.x < 0) { pos.x = 0; offH = true; }
                if (pos.x > _h.MaxValue - _h.Page) { pos.x = (float)(_h.MaxValue - _h.Page); offH = true; }
                if (pos.y < 0) { pos.y = 0; offV = true; }
                if (pos.y > _v.MaxValue - _v.Page) { pos.y = (float)(_v.MaxValue - _v.Page); offV = true; }
                if (_hMode != ScrollMode.Disabled) _h.ScrollTo(pos.x);
                if (_vMode != ScrollMode.Disabled) _v.ScrollTo(pos.y);
                float sx = _dragSpeed.x < 0 ? -1 : 1, vx = Math.Abs(_dragSpeed.x) - 1000f * (float)delta;
                if (vx < 0) offH = true;
                float sy = _dragSpeed.y < 0 ? -1 : 1, vy = Math.Abs(_dragSpeed.y) - 1000f * (float)delta;
                if (vy < 0) offV = true;
                _dragSpeed = new Vec2(sx * vx, sy * vy);
                if (offH && offV) CancelDrag();
            }
            else
            {
                if (_timeSinceMotion == 0 || _timeSinceMotion > 0.1)
                {
                    Vec2 diff = _dragAccum - _lastDragAccum;
                    _lastDragAccum = _dragAccum;
                    _dragSpeed = diff / delta;
                }
                _timeSinceMotion += delta;
            }
        }

        public void EnsureControlVisible(Control c)
        {
            if (!IsAncestorOf(c)) return;
            Rect2 gr = c.GetGlobalRect();
            Rect2 own = GetGlobalRect();
            float dy = 0;
            if (gr.position.y < own.position.y) dy = gr.position.y - own.position.y;
            else if (gr.End.y > own.End.y) dy = gr.End.y - own.End.y;
            ScrollVertical = (int)(ScrollVertical + dy);
        }
    }

    /// <summary>A separator line.</summary>
    public partial class HSeparator : Control
    {
        public HSeparator() { MouseFilter = MouseFilterEnum.Ignore; }
        public override Vec2 GetMinimumSize() => new Vec2(0, GetThemeConstant("separation"));
        protected override void OnDraw()
        {
            var s = GetThemeStylebox("separator");
            var r = new Rect2(0, MathF.Floor((Size.y - s.GetMinimumSize().y) / 2), Size.x, s.GetMinimumSize().y);
            s.Draw(drawList, r);
        }
    }
}
