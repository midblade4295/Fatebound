// Fatebound GUI (Unity port): the widgets -- Label (label.cpp's shaping, wrapping, line metrics, layout data and the
// shadow/outline/fill draw order), BaseButton (press/hover/touch state machine and draw modes) and Button
// (stylebox per state, icon and text placement), TextureButton, TextureRect (stretch and expand modes), ColorRect,
// NinePatchRect, ProgressBar, HSlider, LineEdit, a RichTextLabel for [color] BBCode, ReferenceRect.
using System;
using System.Collections.Generic;
using System.Text;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    // ======================================================================================== Label
    public partial class Label : Control
    {
        string _text = "";
        AutowrapMode _autowrap = AutowrapMode.Off;
        HorizontalAlignment _hAlign = HorizontalAlignment.Left;
        VerticalAlignment _vAlign = VerticalAlignment.Top;
        bool _clip;
        OverrunBehavior _overrun = OverrunBehavior.NoTrimming;
        bool _uppercase;
        int _visibleChars = -1;
        float _visibleRatio = 1f;
        int _linesSkipped;
        int _maxLinesVisible = -1;
        public string EllipsisChar = "…";
        public LabelSettings LabelSettings;
        LineBreakFlags _trimFlags = LineBreakFlags.TrimStartEdgeSpaces | LineBreakFlags.TrimEndEdgeSpaces;

        sealed class Paragraph
        {
            public ShapedText shaped;
            public List<ShapedText> lines = new List<ShapedText>();
            public int start;
        }

        readonly List<Paragraph> _paras = new List<Paragraph>();
        bool _textDirty = true, _linesDirty = true;
        int _totalLines;
        Vec2 _minsize;

        public Label() { MouseFilter = MouseFilterEnum.Ignore; SizeFlagsVertical = SizeFlags.ShrinkCenter; }
        public Label(string text) : this() { Text = text; }

        public string Text
        {
            get => _text;
            set
            {
                value ??= "";
                if (_text == value) return;
                _text = value;
                _textDirty = true;
                if (_visibleRatio < 1) _visibleChars = (int)(GetTotalCharacterCount() * _visibleRatio);
                QueueRedraw();
                UpdateMinimumSize();
            }
        }

        public AutowrapMode AutowrapMode { get => _autowrap; set { if (_autowrap == value) return; _autowrap = value; _linesDirty = true; QueueRedraw(); UpdateMinimumSize(); } }
        public HorizontalAlignment HorizontalAlignment { get => _hAlign; set { if (_hAlign == value) return; _hAlign = value; _linesDirty = true; QueueRedraw(); } }
        public VerticalAlignment VerticalAlignment { get => _vAlign; set { _vAlign = value; QueueRedraw(); } }
        public bool ClipText { get => _clip; set { if (_clip == value) return; _clip = value; QueueRedraw(); UpdateMinimumSize(); } }
        public OverrunBehavior TextOverrunBehavior { get => _overrun; set { if (_overrun == value) return; _overrun = value; _linesDirty = true; QueueRedraw(); UpdateMinimumSize(); } }
        public bool Uppercase { get => _uppercase; set { if (_uppercase == value) return; _uppercase = value; _textDirty = true; QueueRedraw(); UpdateMinimumSize(); } }
        public int LinesSkipped { get => _linesSkipped; set { _linesSkipped = value; _linesDirty = true; QueueRedraw(); UpdateMinimumSize(); } }
        public int MaxLinesVisible { get => _maxLinesVisible; set { _maxLinesVisible = value; _linesDirty = true; QueueRedraw(); UpdateMinimumSize(); } }
        public LineBreakFlags AutowrapTrimFlags { get => _trimFlags; set { _trimFlags = value; _linesDirty = true; QueueRedraw(); UpdateMinimumSize(); } }

        public int VisibleCharacters
        {
            get => _visibleChars;
            set
            {
                if (_visibleChars == value) return;
                _visibleChars = value;
                int total = GetTotalCharacterCount();
                _visibleRatio = value < 0 || total == 0 ? 1f : Math.Min(1f, value / (float)total);
                QueueRedraw();
            }
        }

        public double VisibleRatio
        {
            get => _visibleRatio;
            set
            {
                _visibleRatio = (float)value;
                _visibleChars = value >= 1 ? -1 : (int)(GetTotalCharacterCount() * value);
                QueueRedraw();
            }
        }

        public int GetTotalCharacterCount() => _text.Length;

        Font CurFont => LabelSettings?.Font ?? GetThemeFont("font");
        int CurFontSize => LabelSettings != null ? LabelSettings.FontSize : GetThemeFontSize("font_size");
        int LineSpacing => LabelSettings != null ? (int)LabelSettings.LineSpacing : GetThemeConstant("line_spacing");
        int ParagraphSpacing => LabelSettings != null ? (int)LabelSettings.ParagraphSpacing : GetThemeConstant("paragraph_spacing");
        StyleBox Style => GetThemeStylebox("normal");

        protected override void OnThemeChanged()
        {
            _textDirty = true;
            QueueRedraw();
        }

        protected override void OnResized()
        {
            _linesDirty = true;
        }

        void Shape()
        {
            var style = Style;
            int width = (int)(Size.x - style.GetMinimumSize().x);
            var font = CurFont;
            int fs = CurFontSize;
            if (_textDirty)
            {
                _paras.Clear();
                string txt = _uppercase ? _text.ToUpperInvariant() : _text;
                int start = 0;
                foreach (var str in txt.Split('\n'))
                {
                    var p = new Paragraph { start = start };
                    p.shaped = ShapedText.Shape(str + "​", font, fs);
                    start += str.Length + 1;
                    _paras.Add(p);
                }
                _textDirty = false;
                _linesDirty = true;
            }
            if (_linesDirty)
            {
                _totalLines = 0;
                LineBreakFlags flags = LineBreakFlags.Mandatory;
                switch (_autowrap)
                {
                    case AutowrapMode.WordSmart: flags = LineBreakFlags.WordBound | LineBreakFlags.Adaptive | LineBreakFlags.Mandatory; break;
                    case AutowrapMode.Word: flags = LineBreakFlags.WordBound | LineBreakFlags.Mandatory; break;
                    case AutowrapMode.Arbitrary: flags = LineBreakFlags.GraphemeBound | LineBreakFlags.Mandatory; break;
                }
                flags |= _trimFlags;
                foreach (var p in _paras)
                {
                    p.lines.Clear();
                    var br = p.shaped.GetLineBreaks(width, 0, flags);
                    for (int i = 0; i + 1 < br.Count; i += 2) p.lines.Add(p.shaped.Substr(br[i], br[i + 1] - br[i]));
                    _totalLines += p.lines.Count;
                }
                if (_text.Length == 0)
                {
                    _minsize = new Vec2(1, GetLineHeight());
                    _linesDirty = false;
                    return;
                }
                int visibleLines = GetVisibleLineCount();
                bool linesHidden = visibleLines > 0 && visibleLines < _totalLines;
                if (_autowrap == AutowrapMode.Off) _minsize.x = 0;
                int lineIndex = 0;
                var ofl = TextServer.FlagsFromBehavior(_overrun);
                int elc = string.IsNullOrEmpty(EllipsisChar) ? 0x2026 : char.ConvertToUtf32(EllipsisChar, 0);
                foreach (var p in _paras)
                {
                    if (_autowrap == AutowrapMode.Off)
                        foreach (var l in p.lines) if (_minsize.x < l.Size.x) _minsize.x = l.Size.x;
                    if (_autowrap != AutowrapMode.Off)
                    {
                        var of = ofl;
                        if (linesHidden) of |= OverrunFlags.EnforceEllipsis;
                        int li = visibleLines - lineIndex - 1;
                        if (linesHidden && li >= 0 && li < p.lines.Count) p.lines[li].OverrunTrim(width, of, elc);
                    }
                    else
                        foreach (var l in p.lines) l.OverrunTrim(width, ofl, elc);
                    lineIndex += p.lines.Count;
                }
                _linesDirty = false;
                UpdateVisible();
                if (_autowrap == AutowrapMode.Off || !_clip || _overrun == OverrunBehavior.NoTrimming) UpdateMinimumSize();
            }
        }

        void UpdateVisible()
        {
            int ls = LineSpacing, ps = ParagraphSpacing;
            int fontH = (int)CurFont.GetHeight(CurFontSize);
            int linesVisible = _totalLines;
            if (_maxLinesVisible >= 0 && linesVisible > _maxLinesVisible) linesVisible = _maxLinesVisible;
            _minsize.y = 0;
            int last = Math.Min(_totalLines, linesVisible + _linesSkipped);
            int lineIndex = 0;
            foreach (var p in _paras)
            {
                if (lineIndex + p.lines.Count <= _linesSkipped) { lineIndex += p.lines.Count; continue; }
                int start = lineIndex < _linesSkipped ? _linesSkipped - lineIndex : 0;
                int end = lineIndex + p.lines.Count < last ? p.lines.Count : last - lineIndex;
                if (end <= 0) break;
                for (int i = start; i < end; i++)
                {
                    LineAscDesc(p.lines[i], fontH, out double asc, out double dsc);
                    _minsize.y += (float)(asc + dsc + ls);
                }
                _minsize.y += ps;
                lineIndex += p.lines.Count;
            }
            if (_minsize.y > 0) _minsize.y -= ls + ps;
        }

        static void LineAscDesc(ShapedText l, int fontH, out double asc, out double dsc)
        {
            asc = l.ascent;
            dsc = l.descent;
            if (asc + dsc < fontH)
            {
                double diff = fontH - (asc + dsc);
                asc += diff / 2;
                dsc += diff - diff / 2;
            }
        }

        void EnsureShaped()
        {
            if (_textDirty || _linesDirty) Shape();
        }

        public int GetLineHeight(int line = -1)
        {
            int fontH = (int)CurFont.GetHeight(CurFontSize);
            if (line >= 0 && line < _totalLines)
            {
                var l = LineAt(line);
                LineAscDesc(l, fontH, out double a, out double d);
                return (int)(a + d);
            }
            if (_totalLines > 0)
            {
                int h = fontH;
                foreach (var p in _paras) foreach (var l in p.lines) h = Math.Max(h, (int)(l.ascent + l.descent));
                return h;
            }
            return fontH;
        }

        ShapedText LineAt(int line)
        {
            int idx = 0;
            foreach (var p in _paras)
            {
                if (idx + p.lines.Count <= line) { idx += p.lines.Count; continue; }
                return p.lines[line - idx];
            }
            return null;
        }

        public int GetLineCount() { EnsureShaped(); return _totalLines; }

        public int GetVisibleLineCount()
        {
            var style = Style;
            int ls = LineSpacing, ps = ParagraphSpacing;
            int fontH = (int)CurFont.GetHeight(CurFontSize);
            int linesVisible = 0;
            float total = 0;
            int lineIndex = 0;
            foreach (var p in _paras)
            {
                if (lineIndex + p.lines.Count <= _linesSkipped) { lineIndex += p.lines.Count; continue; }
                int start = lineIndex < _linesSkipped ? _linesSkipped - lineIndex : 0;
                bool stop = false;
                for (int i = start; i < p.lines.Count; i++)
                {
                    LineAscDesc(p.lines[i], fontH, out double a, out double d);
                    total += (float)(a + d + ls);
                    if (total > Math.Ceiling(Size.y - style.GetMinimumSize().y + ls)) { stop = true; break; }
                    linesVisible++;
                }
                if (stop) break;
                total += ps;
                lineIndex += p.lines.Count;
            }
            if (_maxLinesVisible >= 0 && linesVisible > _maxLinesVisible) linesVisible = _maxLinesVisible;
            return linesVisible;
        }

        public override Vec2 GetMinimumSize()
        {
            EnsureShaped();
            Vec2 ms = _minsize;
            int fs = CurFontSize;
            ms.y = (float)Math.Max(ms.y, CurFont.GetHeight(fs));
            Vec2 st = Style.GetMinimumSize();
            if (_autowrap != AutowrapMode.Off)
            {
                if (!_clip && _overrun != OverrunBehavior.NoTrimming && _maxLinesVisible > 0)
                    ms.y = (float)Math.Min(ms.y, (CurFont.GetHeight(fs) + LineSpacing) * _maxLinesVisible);
                else if (_clip || _overrun != OverrunBehavior.NoTrimming) ms.y = 1;
                return new Vec2(1 + st.x, ms.y + st.y);
            }
            if (_clip || _overrun != OverrunBehavior.NoTrimming) ms.x = 1;
            return ms + st;
        }

        Vec2 LineOffset(ShapedText l)
        {
            var style = Style;
            Vec2 size = Size;
            float lw = l.Size.x;
            float x = 0;
            switch (_hAlign)
            {
                case HorizontalAlignment.Fill:
                case HorizontalAlignment.Left: x = style.GetOffset().x; break;
                case HorizontalAlignment.Center: x = (int)(size.x - lw) / 2; break;
                case HorizontalAlignment.Right: x = (int)(size.x - style.GetMargin(Side.Right) - lw); break;
            }
            return new Vec2(x, 0);
        }

        protected override void OnDraw()
        {
            EnsureShaped();
            var style = Style;
            var ci = drawList;
            var font = CurFont;
            int fs = CurFontSize;
            int fontH = (int)font.GetHeight(fs);
            bool hs = LabelSettings != null;
            Col fontColor = hs ? LabelSettings.FontColor : GetThemeColor("font_color");
            Col shadowColor = hs ? LabelSettings.ShadowColor : GetThemeColor("font_shadow_color");
            Vec2 shadowOfs = hs ? LabelSettings.ShadowOffset : new Vec2(GetThemeConstant("shadow_offset_x"), GetThemeConstant("shadow_offset_y"));
            int ps = ParagraphSpacing;
            Col outlineColor = hs ? LabelSettings.OutlineColor : GetThemeColor("font_outline_color");
            int outlineSize = hs ? LabelSettings.OutlineSize : GetThemeConstant("outline_size");
            int shadowOutline = hs ? LabelSettings.ShadowSize : GetThemeConstant("shadow_outline_size");
            style.Draw(ci, new Rect2(Vec2.Zero, Size));
            if (_clip) { }
            // get_layout_data
            int ls = LineSpacing;
            int linesVisible = 0;
            float totalH = 0;
            int lineIndex = 0;
            foreach (var p in _paras)
            {
                if (lineIndex + p.lines.Count <= _linesSkipped) { lineIndex += p.lines.Count; continue; }
                int start = lineIndex < _linesSkipped ? _linesSkipped - lineIndex : 0;
                for (int i = start; i < p.lines.Count; i++)
                {
                    LineAscDesc(p.lines[i], fontH, out double a, out double d);
                    totalH += (float)(a + d + ls);
                    if (totalH > Math.Ceiling(Size.y - style.GetMinimumSize().y + ls)) break;
                    linesVisible++;
                }
                totalH += ps;
                lineIndex += p.lines.Count;
            }
            if (_maxLinesVisible >= 0 && linesVisible > _maxLinesVisible) linesVisible = _maxLinesVisible;
            int lastLine = Math.Min(_totalLines, linesVisible + _linesSkipped);
            int totalGlyphs = 0;
            totalH = 0;
            lineIndex = 0;
            foreach (var p in _paras)
            {
                if (lineIndex + p.lines.Count <= _linesSkipped) { lineIndex += p.lines.Count; continue; }
                int start = lineIndex < _linesSkipped ? _linesSkipped - lineIndex : 0;
                int end = lineIndex + p.lines.Count < lastLine ? p.lines.Count : lastLine - lineIndex;
                if (end <= 0) break;
                for (int i = start; i < end; i++)
                {
                    LineAscDesc(p.lines[i], fontH, out double a, out double d);
                    totalH += (float)(a + d + ls);
                    totalGlyphs += p.lines[i].GlyphCount + p.lines[i].ellipsis.Count;
                }
                totalH += ps;
                lineIndex += p.lines.Count;
            }
            totalH += style.GetMargin(Side.Top) + style.GetMargin(Side.Bottom);
            int vbegin = 0, vsep = 0;
            if (linesVisible > 0)
            {
                switch (_vAlign)
                {
                    case VerticalAlignment.Center: vbegin = (int)((Size.y - (totalH - ls - ps)) / 2); break;
                    case VerticalAlignment.Bottom: vbegin = (int)(Size.y - (totalH - ls - ps)); break;
                    case VerticalAlignment.Fill: vsep = linesVisible > 1 ? (int)((Size.y - (totalH - ls - ps)) / (linesVisible - 1)) : 0; break;
                }
            }
            Vec2 ofs = new Vec2(0, style.GetOffset().y + vbegin);
            int lineSp = ls + vsep;
            int visibleGlyphs = _visibleChars < 0 ? int.MaxValue : (int)(totalGlyphs * _visibleRatio);
            if (_visibleChars >= 0) visibleGlyphs = _visibleChars;
            int processed = 0;
            lineIndex = 0;
            foreach (var p in _paras)
            {
                if (lineIndex + p.lines.Count <= _linesSkipped) { lineIndex += p.lines.Count; continue; }
                int start = lineIndex < _linesSkipped ? _linesSkipped - lineIndex : 0;
                int end = lineIndex + p.lines.Count < lastLine ? p.lines.Count : lastLine - lineIndex;
                if (end <= 0) break;
                for (int i = start; i < end; i++)
                {
                    var l = p.lines[i];
                    ofs.x = LineOffset(l).x;
                    LineAscDesc(l, fontH, out double asc, out double dsc);
                    ofs.y += (float)asc;
                    var drawLine = l;
                    if (visibleGlyphs != int.MaxValue)
                    {
                        int allowed = visibleGlyphs - processed;
                        if (allowed < l.GlyphCount)
                        {
                            drawLine = l.Clone();
                            drawLine.trimPos = Math.Max(0, allowed);
                            drawLine.ellipsis.Clear();
                            drawLine.ellipsisWidth = 0;
                        }
                    }
                    if (shadowColor.a != 0 && shadowOutline > 0) drawLine.Draw(ci, ofs + shadowOfs, shadowColor, shadowOutline);
                    if (shadowColor.a > 0) drawLine.Draw(ci, ofs + shadowOfs, shadowColor, 0);
                    if (outlineSize > 0 && outlineColor.a != 0) drawLine.Draw(ci, ofs, outlineColor, outlineSize);
                    drawLine.Draw(ci, ofs, fontColor, 0);
                    processed += l.GlyphCount;
                    ofs.y += (float)(dsc + lineSp);
                }
                ofs.y += ps;
                lineIndex += p.lines.Count;
            }
        }

        public override bool ClipsChildren => _clip || base.ClipsChildren;
    }

    /// <summary>LabelSettings resource.</summary>
    public sealed partial class LabelSettings : Resource
    {
        public Font Font;
        public int FontSize = 16;
        public Col FontColor = Col.WHITE;
        public double LineSpacing = 3, ParagraphSpacing;
        public int OutlineSize;
        public Col OutlineColor = Col.WHITE;
        public int ShadowSize = 1;
        public Col ShadowColor = new Col(0f, 0f, 0f, 0f);
        public Vec2 ShadowOffset = new Vec2(1, 1);
    }

    // ======================================================================================== Buttons
    public sealed partial class ButtonGroup : Resource
    {
        internal readonly List<BaseButton> buttons = new List<BaseButton>();
        public bool AllowUnpress;
        public event Action<BaseButton> Pressed;
        internal void EmitPressed(BaseButton b) => Pressed?.Invoke(b);
        public BaseButton GetPressedButton() => buttons.Find(b => b.ButtonPressed);
        public List<BaseButton> GetButtons() => new List<BaseButton>(buttons);
    }

    public partial class BaseButton : Control
    {
        public enum DrawModeEnum { Normal = 0, Pressed = 1, Hover = 2, Disabled = 3, HoverPressed = 4 }
        public enum ActionModeEnum { ButtonPress = 0, ButtonRelease = 1 }
        public const ActionModeEnum ACTION_MODE_BUTTON_PRESS = ActionModeEnum.ButtonPress, ACTION_MODE_BUTTON_RELEASE = ActionModeEnum.ButtonRelease;
        bool _pressed, _hovering, _pressAttempt, _pressingInside, _disabled, _pressedDownWithFocus;
        int _touchIndex = -1;
        public bool ToggleMode;
        public bool KeepPressedOutside;
        public ActionModeEnum ActionMode = ActionModeEnum.ButtonRelease;
        public MouseButtonMask ButtonMask = MouseButtonMask.Left;
        ButtonGroup _group;
        public event Action Pressed, ButtonDown, ButtonUp;
        public event Action<bool> Toggled;

        public BaseButton() { FocusMode = FocusModeEnum.All; }

        public bool Disabled
        {
            get => _disabled;
            set
            {
                if (_disabled == value) return;
                _disabled = value;
                if (value)
                {
                    if (!ToggleMode) _pressed = false;
                    _pressAttempt = false;
                    _pressingInside = false;
                }
                QueueRedraw();
            }
        }

        public bool ButtonPressed
        {
            get => _pressed;
            set => SetPressed(value, true);
        }

        public void SetPressedNoSignal(bool p) => SetPressed(p, false);

        void SetPressed(bool p, bool signal)
        {
            if (!ToggleMode || _pressed == p) return;
            _pressed = p;
            if (p) UnpressGroup();
            if (signal) { OnToggled(p); Toggled?.Invoke(p); }
            QueueRedraw();
        }

        public bool IsHovered() => _hovering;

        public ButtonGroup ButtonGroup
        {
            get => _group;
            set
            {
                _group?.buttons.Remove(this);
                _group = value;
                _group?.buttons.Add(this);
                QueueRedraw();
            }
        }

        void UnpressGroup()
        {
            if (_group == null) return;
            if (ToggleMode && !_group.AllowUnpress) _pressed = true;
            foreach (var b in _group.buttons) if (b != this) b.SetPressed(false, true);
        }

        public DrawModeEnum GetDrawMode()
        {
            if (_disabled) return DrawModeEnum.Disabled;
            if (!_pressAttempt && _hovering) return _pressed ? DrawModeEnum.HoverPressed : DrawModeEnum.Hover;
            bool pressing;
            if (_pressAttempt)
            {
                pressing = _pressingInside || KeepPressedOutside;
                if (_pressed) pressing = !pressing;
            }
            else pressing = _pressed;
            return pressing ? DrawModeEnum.Pressed : DrawModeEnum.Normal;
        }

        public bool IsPressedOrHeld => _pressAttempt && _pressingInside;

        protected virtual void OnPressed() { }
        protected virtual void OnToggled(bool on) { }

        void DoPressed()
        {
            OnPressed();
            Pressed?.Invoke();
        }

        void OnActionEvent(InputEvent e)
        {
            bool isTouchPressInside = e is InputEventScreenTouch st && st.Pressed && _pressingInside;
            if (e.IsPressed() && (_hovering || isTouchPressInside))
            {
                _pressAttempt = true;
                _pressingInside = true;
                if (!_pressedDownWithFocus) { _pressedDownWithFocus = true; ButtonDown?.Invoke(); }
            }
            if (_pressAttempt && _pressingInside)
            {
                bool fire = (e.IsPressed() && ActionMode == ActionModeEnum.ButtonPress) || (!e.IsPressed() && ActionMode == ActionModeEnum.ButtonRelease);
                if (fire)
                {
                    if (ToggleMode)
                    {
                        if (ActionMode == ActionModeEnum.ButtonPress) { _pressAttempt = false; _pressingInside = false; _touchIndex = -1; }
                        _pressed = !_pressed;
                        UnpressGroup();
                        _group?.EmitPressed(this);
                        OnToggled(_pressed);
                        Toggled?.Invoke(_pressed);
                        DoPressed();
                    }
                    else DoPressed();
                }
            }
            if (!e.IsPressed())
            {
                _pressAttempt = false;
                _pressingInside = false;
                if (_pressedDownWithFocus) { _pressedDownWithFocus = false; ButtonUp?.Invoke(); }
            }
            QueueRedraw();
        }

        protected override void OnGuiInput(InputEvent e)
        {
            if (_disabled) return;
            if (e.Device != InputEvent.DEVICE_ID_EMULATION)
            {
                if (e is InputEventScreenTouch t)
                {
                    if (_touchIndex == -1)
                    {
                        if (t.Pressed)
                        {
                            _touchIndex = t.Index;
                            _pressAttempt = true;
                            _pressingInside = HasPoint(t.Position);
                            OnActionEvent(e);
                        }
                    }
                    else if (t.Index == _touchIndex && !t.Pressed)
                    {
                        _touchIndex = -1;
                        OnActionEvent(e);
                    }
                }
                if (e is InputEventScreenDrag d && d.Index == _touchIndex && _pressAttempt)
                {
                    bool last = _pressingInside;
                    _pressingInside = HasPoint(d.Position);
                    if (last != _pressingInside) QueueRedraw();
                }
            }
            bool masked = e is InputEventMouseButton mb && (ButtonMask & Input.ToMask(mb.ButtonIndex)) != 0;
            bool accept = e.IsActionPressed("ui_accept") || (e.IsAction("ui_accept") && !e.IsPressed());
            if (masked || (accept && e is InputEventKey))
                OnActionEvent(e);
            else if (e is InputEventMouseMotion mm && _pressAttempt)
            {
                bool last = _pressingInside;
                _pressingInside = HasPoint(mm.Position);
                if (last != _pressingInside) QueueRedraw();
            }
        }

        protected override void OnMouseNotify(bool enter)
        {
            _hovering = enter;
            QueueRedraw();
        }

        public override void _Notification(int what)
        {
            base._Notification(what);
            if (what == NOTIFICATION_SCROLL_BEGIN && _pressAttempt)
            {
                _pressAttempt = false;
                _touchIndex = -1;
                QueueRedraw();
            }
            if (what == NOTIFICATION_FOCUS_EXIT)
            {
                if (_pressAttempt) { _pressAttempt = false; _touchIndex = -1; QueueRedraw(); }
                if (_pressedDownWithFocus) { _pressedDownWithFocus = false; ButtonUp?.Invoke(); }
            }
            if (what == NOTIFICATION_EXIT_TREE || (what == NOTIFICATION_VISIBILITY_CHANGED && !IsVisibleInTree()))
            {
                if (!ToggleMode) _pressed = false;
                _hovering = false;
                _pressAttempt = false;
                _pressingInside = false;
                _touchIndex = -1;
            }
        }
    }

    public partial class Button : BaseButton
    {
        string _text = "";
        Texture2D _icon;
        bool _flat, _clip, _expandIcon;
        HorizontalAlignment _align = HorizontalAlignment.Center;
        HorizontalAlignment _iconAlign = HorizontalAlignment.Left;
        VerticalAlignment _vIconAlign = VerticalAlignment.Center;
        OverrunBehavior _overrun = OverrunBehavior.NoTrimming;
        AutowrapMode _autowrap = AutowrapMode.Off;
        List<ShapedText> _lines = new List<ShapedText>();
        float _bufWidth = -1;
        bool _dirty = true;

        public Button() { MouseFilter = MouseFilterEnum.Stop; }
        public Button(string text) : this() { Text = text; }

        public string Text { get => _text; set { value ??= ""; if (_text == value) return; _text = value; _dirty = true; UpdateMinimumSize(); QueueRedraw(); } }
        public Texture2D Icon { get => _icon; set { if (_icon == value) return; _icon = value; UpdateMinimumSize(); QueueRedraw(); } }
        public bool Flat { get => _flat; set { _flat = value; QueueRedraw(); } }
        public bool ClipText { get => _clip; set { _clip = value; UpdateMinimumSize(); QueueRedraw(); } }
        public bool ExpandIcon { get => _expandIcon; set { _expandIcon = value; UpdateMinimumSize(); QueueRedraw(); } }
        public HorizontalAlignment Alignment { get => _align; set { _align = value; QueueRedraw(); } }
        public HorizontalAlignment IconAlignment { get => _iconAlign; set { _iconAlign = value; UpdateMinimumSize(); QueueRedraw(); } }
        public VerticalAlignment VerticalIconAlignment { get => _vIconAlign; set { _vIconAlign = value; UpdateMinimumSize(); QueueRedraw(); } }
        public OverrunBehavior TextOverrunBehavior { get => _overrun; set { _overrun = value; _dirty = true; UpdateMinimumSize(); QueueRedraw(); } }
        public AutowrapMode AutowrapMode { get => _autowrap; set { _autowrap = value; _dirty = true; UpdateMinimumSize(); QueueRedraw(); } }

        protected override void OnThemeChanged() { _dirty = true; QueueRedraw(); }
        protected override void OnResized() { if (_autowrap != AutowrapMode.Off) { _dirty = true; UpdateMinimumSize(); QueueRedraw(); } }

        Font CurFont => GetThemeFont("font");
        int CurFontSize => GetThemeFontSize("font_size");

        StyleBox CurrentStyle()
        {
            switch (GetDrawMode())
            {
                case DrawModeEnum.HoverPressed:
                    if (HasThemeStylebox("hover_pressed")) return GetThemeStylebox("hover_pressed");
                    return GetThemeStylebox("pressed");
                case DrawModeEnum.Pressed: return GetThemeStylebox("pressed");
                case DrawModeEnum.Hover: return GetThemeStylebox("hover");
                case DrawModeEnum.Disabled: return GetThemeStylebox("disabled");
                default: return GetThemeStylebox("normal");
            }
        }

        /// <summary>TextParagraph: the text broken into lines at `width` (-1: no wrapping).</summary>
        void ShapeLines(float width)
        {
            if (!_dirty && width == _bufWidth) return;
            _lines.Clear();
            _bufWidth = width;
            _dirty = false;
            var font = CurFont;
            int fs = CurFontSize;
            if (font == null || fs == 0) return;
            LineBreakFlags flags = LineBreakFlags.Mandatory;
            switch (_autowrap)
            {
                case AutowrapMode.WordSmart: flags = LineBreakFlags.WordBound | LineBreakFlags.Adaptive | LineBreakFlags.Mandatory; break;
                case AutowrapMode.Word: flags = LineBreakFlags.WordBound | LineBreakFlags.Mandatory; break;
                case AutowrapMode.Arbitrary: flags = LineBreakFlags.GraphemeBound | LineBreakFlags.Mandatory; break;
            }
            flags |= LineBreakFlags.TrimStartEdgeSpaces | LineBreakFlags.TrimEndEdgeSpaces;
            var st = ShapedText.Shape(_text, font, fs);
            var br = st.GetLineBreaks(_autowrap != AutowrapMode.Off ? width : 0, 0, flags);
            for (int i = 0; i + 1 < br.Count; i += 2) _lines.Add(st.Substr(br[i], br[i + 1] - br[i]));
            if (_lines.Count == 0) _lines.Add(st);
            if (width > 0 && _overrun != OverrunBehavior.NoTrimming)
                foreach (var l in _lines) l.OverrunTrim(width, TextServer.FlagsFromBehavior(_overrun));
            else if (width > 0 && _clip)
                foreach (var l in _lines) l.OverrunTrim(width, OverrunFlags.Trim);
        }

        Vec2 TextSize()
        {
            float w = 0, h = 0;
            foreach (var l in _lines) { var ls = l.Size; w = Math.Max(w, ls.x); h += ls.y; }
            if (_lines.Count > 1) h += (_lines.Count - 1) * GetThemeConstant("line_spacing");
            return new Vec2(w, h);
        }

        Vec2 FitIcon(Vec2 s)
        {
            int max = GetThemeConstant("icon_max_width");
            if (max > 0 && s.x > max) { s.y = s.y * max / s.x; s.x = max; }
            return s;
        }

        Texture2D CurIcon => _icon ?? GetThemeIcon("icon");

        public override Vec2 GetMinimumSize()
        {
            ShapeLines(_bufWidth < 0 ? -1 : _bufWidth);
            Vec2 min = string.IsNullOrEmpty(_text) ? Vec2.Zero : TextSize();
            if (_clip || _overrun != OverrunBehavior.NoTrimming || _autowrap != AutowrapMode.Off) min.x = 0;
            var icon = CurIcon;
            int hsep = Math.Max(0, GetThemeConstant("h_separation"));
            if (!_expandIcon && icon != null)
            {
                Vec2 isz = FitIcon(icon.GetSize());
                if (_vIconAlign == VerticalAlignment.Center) min.y = Math.Max(min.y, isz.y);
                else min.y += isz.y;
                if (_iconAlign != HorizontalAlignment.Center)
                {
                    min.x += isz.x;
                    if (!string.IsNullOrEmpty(_text)) min.x += hsep;
                }
                else min.x = Math.Max(min.x, isz.x);
            }
            if (!string.IsNullOrEmpty(_text))
            {
                float fh = (float)CurFont.GetHeight(CurFontSize);
                if (_vIconAlign == VerticalAlignment.Center) min.y = Math.Max(fh, min.y);
                else min.y += fh;
            }
            return CurrentStyle().GetMinimumSize() + min;
        }

        protected override void OnDraw()
        {
            var ci = drawList;
            Vec2 size = Size;
            var style = CurrentStyle();
            if (!_flat) style.Draw(ci, new Rect2(Vec2.Zero, size));
            var icon = CurIcon;
            if (string.IsNullOrEmpty(_text) && icon == null) return;
            float ml = style.GetMargin(Side.Left), mr = style.GetMargin(Side.Right), mt = style.GetMargin(Side.Top), mb = style.GetMargin(Side.Bottom);
            Vec2 remain = new Vec2(size.x - ml - mr, size.y - mt - mb);
            int hsep = Math.Max(0, GetThemeConstant("h_separation"));
            Col fontColor;
            Col iconMod = Col.WHITE;
            switch (GetDrawMode())
            {
                case DrawModeEnum.HoverPressed:
                    fontColor = GetThemeColor("font_hover_pressed_color");
                    if (HasThemeColor("icon_hover_pressed_color")) iconMod = GetThemeColor("icon_hover_pressed_color");
                    break;
                case DrawModeEnum.Pressed:
                    fontColor = HasThemeColor("font_pressed_color") ? GetThemeColor("font_pressed_color") : GetThemeColor("font_color");
                    if (HasThemeColor("icon_pressed_color")) iconMod = GetThemeColor("icon_pressed_color");
                    break;
                case DrawModeEnum.Hover:
                    fontColor = GetThemeColor("font_hover_color");
                    if (HasThemeColor("icon_hover_color")) iconMod = GetThemeColor("icon_hover_color");
                    break;
                case DrawModeEnum.Disabled:
                    fontColor = GetThemeColor("font_disabled_color");
                    if (HasThemeColor("icon_disabled_color")) iconMod = GetThemeColor("icon_disabled_color");
                    else iconMod.a = 0.4f;
                    break;
                default:
                    fontColor = GetThemeColor("font_color");
                    if (HasThemeColor("icon_normal_color")) iconMod = GetThemeColor("icon_normal_color");
                    break;
            }
            bool clipped = _clip || _overrun != OverrunBehavior.NoTrimming || _autowrap != AutowrapMode.Off;
            Vec2 custom = remain;
            if (icon != null)
            {
                Vec2 isz = icon.GetSize();
                if (_expandIcon)
                {
                    ShapeLines(_bufWidth);
                    Vec2 tb = TextSize();
                    Vec2 s = custom;
                    if (!clipped && _iconAlign != HorizontalAlignment.Center && tb.x > 0) s.x -= tb.x + hsep;
                    if (_vIconAlign != VerticalAlignment.Center) s.y -= tb.y;
                    float iw = isz.x * s.y / isz.y, ih = s.y;
                    if (iw > s.x) { iw = s.x; ih = isz.y * iw / isz.x; }
                    isz = new Vec2(iw, ih);
                }
                isz = FitIcon(isz).Round();
                if (isz.x > 0)
                {
                    Vec2 io = Vec2.Zero;
                    switch (_iconAlign)
                    {
                        case HorizontalAlignment.Center: io.x = (custom.x - isz.x) / 2f + ml; break;
                        case HorizontalAlignment.Right: io.x = size.x - mr - isz.x; break;
                        default: io.x = ml; break;
                    }
                    switch (_vIconAlign)
                    {
                        case VerticalAlignment.Center: io.y = (custom.y - isz.y) / 2f + mt; break;
                        case VerticalAlignment.Bottom: io.y = size.y - mb - isz.y; break;
                        default: io.y = mt; break;
                    }
                    io = io.Floor();
                    ci.AddTextureRect(new Rect2(io, isz), icon, false, iconMod);
                }
                if (!string.IsNullOrEmpty(_text))
                {
                    if (_iconAlign != HorizontalAlignment.Center) remain.x -= isz.x + hsep;
                    if (_vIconAlign != VerticalAlignment.Center) remain.y -= isz.y;
                }
            }
            if (!string.IsNullOrEmpty(_text))
            {
                float bufW = MathF.Ceiling(Math.Max(1f, remain.x));
                if (_autowrap != AutowrapMode.Off && Math.Abs(bufW - _bufWidth) > 0.001f) UpdateMinimumSize();
                ShapeLines(bufW);
                Vec2 ts = TextSize();
                Vec2 to = Vec2.Zero;
                if (_align == HorizontalAlignment.Center) to.x = (remain.x - bufW) / 2f;
                to.x += ml;
                if (_iconAlign == HorizontalAlignment.Left && icon != null) to.x += custom.x - remain.x;
                to.y = (remain.y - ts.y) / 2f + mt;
                if (_vIconAlign == VerticalAlignment.Top && icon != null) to.y += custom.y - remain.y;
                Col oc = GetThemeColor("font_outline_color");
                int os = GetThemeConstant("outline_size");
                int lsp = GetThemeConstant("line_spacing");
                Vec2 o = to;
                foreach (var l in _lines)
                {
                    float lx = o.x;
                    float lw = l.Size.x;
                    if (_align == HorizontalAlignment.Center) lx += MathF.Floor((bufW - lw) / 2f);
                    else if (_align == HorizontalAlignment.Right) lx += bufW - lw;
                    Vec2 bl = new Vec2(lx, o.y + l.ascent);
                    if (os > 0 && oc.a > 0) l.Draw(ci, bl, oc, os);
                    l.Draw(ci, bl, fontColor, 0);
                    o.y += l.ascent + l.descent + lsp;
                }
            }
        }
    }

    public partial class TextureButton : BaseButton
    {
        public Texture2D TextureNormal, TexturePressed, TextureHover, TextureDisabled, TextureFocused;
        public bool IgnoreTextureSize;
        public TextureRect.StretchModeEnum StretchMode = TextureRect.StretchModeEnum.Scale;
        public bool FlipH, FlipV;

        public override Vec2 GetMinimumSize()
        {
            if (IgnoreTextureSize) return Vec2.Zero;
            var t = TextureNormal ?? TexturePressed ?? TextureHover;
            return t?.GetSize() ?? Vec2.Zero;
        }

        protected override void OnDraw()
        {
            Texture2D t = TextureNormal;
            switch (GetDrawMode())
            {
                case DrawModeEnum.Pressed: case DrawModeEnum.HoverPressed: t = TexturePressed ?? (GetDrawMode() == DrawModeEnum.HoverPressed ? TextureHover : null) ?? TextureNormal; break;
                case DrawModeEnum.Hover: t = TextureHover ?? TextureNormal; break;
                case DrawModeEnum.Disabled: t = TextureDisabled ?? TextureNormal; break;
            }
            if (t == null) return;
            Vec2 sz = Size;
            if (FlipH) sz.x = -sz.x;
            if (FlipV) sz.y = -sz.y;
            drawList.AddTextureRect(new Rect2(Vec2.Zero, sz), t, false, Col.WHITE);
        }
    }

    // ======================================================================================== Textures, rects
    public partial class TextureRect : Control
    {
        public enum ExpandModeEnum { KeepSize = 0, IgnoreSize = 1, FitWidth = 2, FitWidthProportional = 3, FitHeight = 4, FitHeightProportional = 5 }
        public enum StretchModeEnum { Scale = 0, Tile = 1, Keep = 2, KeepCentered = 3, KeepAspect = 4, KeepAspectCentered = 5, KeepAspectCovered = 6 }
        public const ExpandModeEnum EXPAND_KEEP_SIZE = ExpandModeEnum.KeepSize, EXPAND_IGNORE_SIZE = ExpandModeEnum.IgnoreSize, EXPAND_FIT_WIDTH = ExpandModeEnum.FitWidth,
            EXPAND_FIT_WIDTH_PROPORTIONAL = ExpandModeEnum.FitWidthProportional, EXPAND_FIT_HEIGHT = ExpandModeEnum.FitHeight, EXPAND_FIT_HEIGHT_PROPORTIONAL = ExpandModeEnum.FitHeightProportional;
        public const StretchModeEnum STRETCH_SCALE = StretchModeEnum.Scale, STRETCH_TILE = StretchModeEnum.Tile, STRETCH_KEEP = StretchModeEnum.Keep,
            STRETCH_KEEP_CENTERED = StretchModeEnum.KeepCentered, STRETCH_KEEP_ASPECT = StretchModeEnum.KeepAspect,
            STRETCH_KEEP_ASPECT_CENTERED = StretchModeEnum.KeepAspectCentered, STRETCH_KEEP_ASPECT_COVERED = StretchModeEnum.KeepAspectCovered;
        Texture2D _tex;
        ExpandModeEnum _expand = ExpandModeEnum.KeepSize;
        StretchModeEnum _stretch = StretchModeEnum.Scale;
        bool _flipH, _flipV;

        public TextureRect() { MouseFilter = MouseFilterEnum.Pass; }

        public Texture2D Texture
        {
            get => _tex;
            set
            {
                if (_tex == value) return;
                if (_tex != null) _tex.Changed -= TexChanged;
                _tex = value;
                if (_tex != null) _tex.Changed += TexChanged;
                QueueRedraw();
                UpdateMinimumSize();
            }
        }

        void TexChanged() { QueueRedraw(); UpdateMinimumSize(); }

        public ExpandModeEnum ExpandMode { get => _expand; set { if (_expand == value) return; _expand = value; QueueRedraw(); UpdateMinimumSize(); } }
        public StretchModeEnum StretchMode { get => _stretch; set { if (_stretch == value) return; _stretch = value; QueueRedraw(); } }
        public bool FlipH { get => _flipH; set { _flipH = value; QueueRedraw(); } }
        public bool FlipV { get => _flipV; set { _flipV = value; QueueRedraw(); } }

        protected override void OnResized() => UpdateMinimumSize();

        public override Vec2 GetMinimumSize()
        {
            if (_tex == null) return Vec2.Zero;
            switch (_expand)
            {
                case ExpandModeEnum.KeepSize: return _tex.GetSize();
                case ExpandModeEnum.IgnoreSize: return Vec2.Zero;
                case ExpandModeEnum.FitWidth: return new Vec2(Size.y, 0);
                case ExpandModeEnum.FitWidthProportional: return new Vec2(Size.y * (_tex.GetWidth() / (float)_tex.GetHeight()), 0);
                case ExpandModeEnum.FitHeight: return new Vec2(0, Size.x);
                case ExpandModeEnum.FitHeightProportional: return new Vec2(0, Size.x * (_tex.GetHeight() / (float)_tex.GetWidth()));
            }
            return Vec2.Zero;
        }

        protected override void OnDraw()
        {
            if (_tex == null) return;
            Vec2 size = Vec2.Zero, offset = Vec2.Zero;
            Rect2 region = new Rect2(0, 0, 0, 0);
            bool tile = false;
            switch (_stretch)
            {
                case StretchModeEnum.Scale: size = Size; break;
                case StretchModeEnum.Tile: size = Size; tile = true; break;
                case StretchModeEnum.Keep: size = _tex.GetSize(); break;
                case StretchModeEnum.KeepCentered: offset = (Size - _tex.GetSize()) / 2; size = _tex.GetSize(); break;
                case StretchModeEnum.KeepAspectCentered:
                case StretchModeEnum.KeepAspect:
                {
                    size = Size;
                    int tw = (int)(_tex.GetWidth() * size.y / _tex.GetHeight());
                    int th = (int)size.y;
                    if (tw > size.x)
                    {
                        tw = (int)size.x;
                        th = (int)(_tex.GetHeight() * tw / (float)_tex.GetWidth());
                    }
                    if (_stretch == StretchModeEnum.KeepAspectCentered)
                    {
                        offset.x += (size.x - tw) / 2;
                        offset.y += (size.y - th) / 2;
                    }
                    size = new Vec2(tw, th);
                    break;
                }
                case StretchModeEnum.KeepAspectCovered:
                {
                    size = Size;
                    Vec2 ts = _tex.GetSize();
                    float sx = size.x / ts.x, sy = size.y / ts.y;
                    float sc = sx > sy ? sx : sy;
                    Vec2 scaled = ts * sc;
                    region.position = ((scaled - size) / sc).Abs() / 2f;
                    region.size = size / sc;
                    break;
                }
            }
            size.x *= _flipH ? -1f : 1f;
            size.y *= _flipV ? -1f : 1f;
            if (region.size.x > 0 && region.size.y > 0) drawList.AddTextureRectRegion(new Rect2(offset, size), _tex, region, Col.WHITE);
            else drawList.AddTextureRect(new Rect2(offset, size), _tex, tile, Col.WHITE);
        }
    }

    public partial class ColorRect : Control
    {
        Col _color = Col.WHITE;
        public Col Color { get => _color; set { if (_color == value) return; _color = value; QueueRedraw(); } }
        public ColorRect() { }
        public ColorRect(Col c) { _color = c; }
        protected override void OnDraw() => drawList.AddRect(new Rect2(Vec2.Zero, Size), _color, false);
    }

    public partial class NinePatchRect : Control
    {
        public Texture2D Texture;
        public bool DrawCenter = true;
        public Rect2 RegionRect;
        public int PatchMarginLeft, PatchMarginTop, PatchMarginRight, PatchMarginBottom;
        public DrawList.NinePatchAxis AxisStretchHorizontal, AxisStretchVertical;
        public NinePatchRect() { MouseFilter = MouseFilterEnum.Ignore; }
        public override Vec2 GetMinimumSize() => new Vec2(PatchMarginLeft + PatchMarginRight, PatchMarginTop + PatchMarginBottom);

        protected override void OnDraw()
        {
            if (Texture == null) return;
            drawList.AddNinePatch(new Rect2(Vec2.Zero, Size), RegionRect, Texture, new Vec2(PatchMarginLeft, PatchMarginTop),
                new Vec2(PatchMarginRight, PatchMarginBottom), AxisStretchHorizontal, AxisStretchVertical, DrawCenter, Col.WHITE);
        }
    }

    public partial class ReferenceRect : Control
    {
        public Col BorderColor = new Col(1f, 0f, 0f, 1f);
        public double BorderWidth = 1;
        public bool EditorOnly = true;
        protected override void OnDraw()
        {
            if (EditorOnly) return;
            drawList.AddPolyline(new[] { Vec2.Zero, new Vec2(Size.x, 0), Size, new Vec2(0, Size.y), Vec2.Zero }, new[] { BorderColor }, (float)BorderWidth, false);
        }
    }

    // ======================================================================================== Ranges
    public partial class ProgressBar : RangeControl
    {
        public enum FillModeEnum { BeginToEnd = 0, EndToBegin = 1, TopToBottom = 2, BottomToTop = 3 }
        public FillModeEnum FillMode = FillModeEnum.BeginToEnd;
        bool _showPct = true;
        public bool ShowPercentage { get => _showPct; set { _showPct = value; UpdateMinimumSize(); QueueRedraw(); } }

        public ProgressBar() { SizeFlagsVertical = 0; Step = 0.01; }

        public override Vec2 GetMinimumSize()
        {
            var bg = GetThemeStylebox("background");
            var fg = GetThemeStylebox("fill");
            Vec2 m = bg.GetMinimumSize();
            Vec2 f = fg.GetMinimumSize();
            m = new Vec2(Math.Max(m.x, f.x), Math.Max(m.y, f.y));
            if (_showPct)
            {
                var font = GetThemeFont("font");
                var tl = font.GetStringSize("100%", HorizontalAlignment.Left, -1, GetThemeFontSize("font_size"));
                m.y = Math.Max(m.y, bg.GetMinimumSize().y + tl.y);
            }
            else m = new Vec2(Math.Max(m.x, 1), Math.Max(m.y, 1));
            return m;
        }

        protected override void OnDraw()
        {
            var bg = GetThemeStylebox("background");
            var fg = GetThemeStylebox("fill");
            bg.Draw(drawList, new Rect2(Vec2.Zero, Size));
            float r = (float)Ratio;
            if (FillMode == FillModeEnum.BeginToEnd || FillMode == FillModeEnum.EndToBegin)
            {
                int mp = (int)fg.GetMinimumSize().x;
                int p = (int)Math.Round(r * (Size.x - mp));
                if (p > 0)
                {
                    if (FillMode == FillModeEnum.EndToBegin)
                    {
                        int rem = (int)Math.Round((1.0 - r) * (Size.x - mp));
                        fg.Draw(drawList, new Rect2(rem, 0, p + mp, Size.y));
                    }
                    else fg.Draw(drawList, new Rect2(0, 0, p + mp, Size.y));
                }
            }
            else
            {
                int mp = (int)fg.GetMinimumSize().y;
                int p = (int)Math.Round(r * (Size.y - mp));
                if (p > 0)
                {
                    if (FillMode == FillModeEnum.TopToBottom) fg.Draw(drawList, new Rect2(0, 0, Size.x, p + mp));
                    else
                    {
                        int rem = (int)Math.Round((1.0 - r) * (Size.y - mp));
                        fg.Draw(drawList, new Rect2(0, rem, Size.x, p + mp));
                    }
                }
            }
            if (_showPct)
            {
                double ratio = MaxValue == MinValue ? 1 : Math.Max(0, Math.Min(1, (Value - MinValue) / (MaxValue - MinValue)));
                string txt = ((int)Math.Round(ratio * 100)) + "%";
                var font = GetThemeFont("font");
                int fs = GetThemeFontSize("font_size");
                var st = font.ShapeCached(txt, fs);
                Vec2 pos = new Vec2((Size.x - st.width) / 2, (Size.y - (st.ascent + st.descent)) / 2).Round();
                int os = GetThemeConstant("outline_size");
                Col oc = GetThemeColor("font_outline_color");
                if (os > 0 && oc.a > 0) st.Draw(drawList, pos + new Vec2(0, st.ascent), oc, os);
                st.Draw(drawList, pos + new Vec2(0, st.ascent), GetThemeColor("font_color"), 0);
            }
        }
    }

    public partial class Slider : RangeControl
    {
        protected bool vertical;
        public bool Editable = true;
        public bool Scrollable = true;
        bool _grabbing;
        double _grabPos, _ratioBefore;
        public event Action DragStarted;
        public event Action<bool> DragEnded;

        public Slider() { FocusMode = FocusModeEnum.All; }

        Texture2D Grabber => (MouseInsideOrFocus ? GetThemeIcon("grabber_highlight") : GetThemeIcon("grabber")) ?? GetThemeIcon("grabber");
        bool MouseInsideOrFocus => mouseInside || HasFocus(true);

        public override Vec2 GetMinimumSize()
        {
            Vec2 ss = GetThemeStylebox("slider").GetMinimumSize();
            Vec2 rs = GetThemeIcon("grabber")?.GetSize() ?? Vec2.Zero;
            return vertical ? new Vec2(Math.Max(ss.x, rs.x), ss.y) : new Vec2(ss.x, Math.Max(ss.y, rs.y));
        }

        protected override void OnGuiInput(InputEvent e)
        {
            if (!Editable) return;
            var g = Grabber;
            double gw = GetThemeConstant("center_grabber") != 0 || g == null ? 0 : g.GetWidth();
            double gh = GetThemeConstant("center_grabber") != 0 || g == null ? 0 : g.GetHeight();
            if (e is InputEventMouseButton mb && mb.ButtonIndex == MouseButton.Left)
            {
                if (mb.Pressed)
                {
                    _grabPos = vertical ? mb.Position.y : mb.Position.x;
                    _ratioBefore = Ratio;
                    DragStarted?.Invoke();
                    double max = vertical ? Size.y - gh : Size.x - gw;
                    if (vertical) Ratio = 1 - ((_grabPos - gh / 2.0) / max);
                    else Ratio = (_grabPos - gw / 2.0) / max;
                    _grabbing = true;
                    _ratioBefore = Ratio;
                }
                else if (_grabbing)
                {
                    _grabbing = false;
                    DragEnded?.Invoke(Ratio != _ratioBefore);
                }
                AcceptEvent();
            }
            else if (e is InputEventMouseMotion mm && _grabbing)
            {
                double areasize = vertical ? Size.y - gh : Size.x - gw;
                if (areasize <= 0) return;
                double motion = (vertical ? mm.Position.y : mm.Position.x) - _grabPos;
                if (vertical) motion = -motion;
                Ratio = _ratioBefore + motion / areasize;
                AcceptEvent();
            }
        }

        protected override void OnMouseNotify(bool enter) => QueueRedraw();

        protected override void OnDraw()
        {
            Vec2 size = Size;
            int sw = (int)size.x, sh = (int)size.y;
            double ratio = double.IsNaN(Ratio) ? 0 : Ratio;
            var style = GetThemeStylebox("slider");
            bool hl = Editable && MouseInsideOrFocus;
            var grabber = Editable ? Grabber : (GetThemeIcon("grabber_disabled") ?? Grabber);
            var area = hl ? GetThemeStylebox("grabber_area_highlight") : GetThemeStylebox("grabber_area");
            int gwI = grabber?.GetWidth() ?? 0, ghI = grabber?.GetHeight() ?? 0;
            bool center = GetThemeConstant("center_grabber") != 0;
            int gofs = GetThemeConstant("grabber_offset");
            if (!vertical)
            {
                int wh = (int)style.GetMinimumSize().y;
                double areasize = sw - (center ? 0 : gwI);
                int shift = center ? -gwI / 2 : 0;
                style.Draw(drawList, new Rect2(0, sh / 2 - wh / 2, sw, wh));
                area.Draw(drawList, new Rect2(0, (sh - wh) / 2, (float)Math.Round(areasize * ratio + gwI / 2 + shift), wh));
                if (grabber != null) drawList.AddTextureRect(new Rect2((float)Math.Round(ratio * areasize + shift), sh / 2 - ghI / 2 + gofs, gwI, ghI), grabber, false, Col.WHITE);
            }
            else
            {
                int ww = (int)style.GetMinimumSize().x;
                double areasize = sh - (center ? 0 : ghI);
                int shift = center ? ghI / 2 : 0;
                style.Draw(drawList, new Rect2(sw / 2 - ww / 2, 0, ww, sh));
                area.Draw(drawList, new Rect2((sw - ww) / 2, (float)Math.Round(sh - areasize * ratio - ghI / 2 + shift), ww, (float)Math.Round(areasize * ratio + ghI / 2 - shift)));
                if (grabber != null) drawList.AddTextureRect(new Rect2(sw / 2 - gwI / 2 + gofs, (float)(sh - ratio * areasize - ghI + shift), gwI, ghI), grabber, false, Col.WHITE);
            }
        }
    }

    public partial class HSlider : Slider { public HSlider() { vertical = false; SizeFlagsVertical = SizeFlags.ShrinkBegin; } }
    public partial class VSlider : Slider { public VSlider() { vertical = true; SizeFlagsHorizontal = SizeFlags.ShrinkBegin; } }

    // ======================================================================================== LineEdit
    public partial class LineEdit : Control
    {
        string _text = "";
        public string PlaceholderText = "";
        public int MaxLength;
        public bool Editable = true;
        public bool Secret;
        public bool SelectAllOnFocus;
        public bool ContextMenuEnabled = true;
        public bool VirtualKeyboardEnabled = true;
        public HorizontalAlignment Alignment = HorizontalAlignment.Left;
        int _caret;
        double _blink;
        bool _caretOn = true;
        public event Action<string> TextChanged, TextSubmitted;

        public LineEdit() { FocusMode = FocusModeEnum.All; MouseFilter = MouseFilterEnum.Stop; MouseDefaultCursorShape = CursorShape.Ibeam; }

        public string Text
        {
            get => _text;
            set
            {
                value ??= "";
                if (MaxLength > 0 && value.Length > MaxLength) value = value.Substring(0, MaxLength);
                _text = value;
                _caret = Math.Min(_caret, _text.Length);
                QueueRedraw();
            }
        }

        public int CaretColumn { get => _caret; set { _caret = Math.Max(0, Math.Min(_text.Length, value)); QueueRedraw(); } }

        StyleBox CurStyle => !Editable ? GetThemeStylebox("read_only") : GetThemeStylebox("normal");

        public override Vec2 GetMinimumSize()
        {
            var font = GetThemeFont("font");
            int fs = GetThemeFontSize("font_size");
            float em = font.GetCharSize('W', fs).x;
            Vec2 m = new Vec2(GetThemeConstant("minimum_character_width") * em, (float)font.GetHeight(fs));
            return m + CurStyle.GetMinimumSize();
        }

        /// <summary>Text typed by the host's on-screen keyboard (the whole new string).</summary>
        public void SetTextFromKeyboard(string s)
        {
            if (!Editable) return;
            string old = _text;
            Text = s;
            _caret = _text.Length;
            if (old != _text) TextChanged?.Invoke(_text);
        }

        public void InsertTextAtCaret(string s)
        {
            if (!Editable) return;
            string t = _text.Insert(_caret, s);
            if (MaxLength > 0 && t.Length > MaxLength) return;
            _text = t;
            _caret += s.Length;
            QueueRedraw();
            TextChanged?.Invoke(_text);
        }

        public void Submit() => TextSubmitted?.Invoke(_text);
        public void Clear() { Text = ""; TextChanged?.Invoke(_text); }
        public void SelectAll() { }
        public void Deselect() { }
        public void Edit() => GrabFocus();
        public void Unedit() => ReleaseFocus();

        public override void _Notification(int what)
        {
            base._Notification(what);
            if (what == NOTIFICATION_FOCUS_ENTER && Editable && VirtualKeyboardEnabled)
            {
                DisplayServer.VirtualKeyboardShow(_text, GetGlobalRect(), 0);
                SetProcess(true);
            }
            if (what == NOTIFICATION_FOCUS_EXIT)
            {
                DisplayServer.VirtualKeyboardHide();
                SetProcess(false);
            }
        }

        protected override void _Process(double delta)
        {
            _blink += delta;
            if (_blink >= 0.65) { _blink = 0; _caretOn = !_caretOn; QueueRedraw(); }
        }

        protected override void OnGuiInput(InputEvent e)
        {
            if (e is InputEventMouseButton mb && mb.Pressed && mb.ButtonIndex == MouseButton.Left)
            {
                GrabFocus();
                _caret = _text.Length;
                AcceptEvent();
                return;
            }
            if (e is InputEventKey k && k.Pressed && Editable)
            {
                if (k.Keycode == Key.Backspace && _caret > 0)
                {
                    _text = _text.Remove(_caret - 1, 1);
                    _caret--;
                    TextChanged?.Invoke(_text);
                }
                else if (k.Keycode == Key.Enter || k.Keycode == Key.KpEnter) TextSubmitted?.Invoke(_text);
                else if (k.Keycode == Key.Left) _caret = Math.Max(0, _caret - 1);
                else if (k.Keycode == Key.Right) _caret = Math.Min(_text.Length, _caret + 1);
                else if (k.Unicode >= 32) InsertTextAtCaret(char.ConvertFromUtf32(k.Unicode));
                QueueRedraw();
                AcceptEvent();
            }
        }

        protected override void OnDraw()
        {
            var style = HasFocus() && Editable ? GetThemeStylebox("focus") : null;
            var normal = CurStyle;
            normal.Draw(drawList, new Rect2(Vec2.Zero, Size));
            var font = GetThemeFont("font");
            int fs = GetThemeFontSize("font_size");
            bool ph = _text.Length == 0;
            string shown = ph ? PlaceholderText : (Secret ? new string('•', _text.Length) : _text);
            Col c = ph ? GetThemeColor("font_placeholder_color") : (Editable ? GetThemeColor("font_color") : GetThemeColor("font_uneditable_color"));
            var st = font.ShapeCached(shown, fs);
            float h = st.ascent + st.descent;
            Vec2 ofs = normal.GetOffset();
            float avail = Size.x - normal.GetMinimumSize().x;
            float x = ofs.x;
            if (Alignment == HorizontalAlignment.Center) x += MathF.Floor((avail - st.width) / 2);
            else if (Alignment == HorizontalAlignment.Right) x += avail - st.width;
            float y = MathF.Round((Size.y - h) / 2) + st.ascent;
            st.Draw(drawList, new Vec2(x, y), c, 0, -1, avail);
            if (HasFocus() && Editable && _caretOn)
            {
                float cx = x;
                if (!ph)
                {
                    var pre = font.ShapeCached(Secret ? new string('•', _caret) : _text.Substring(0, _caret), fs);
                    cx += pre.width;
                }
                drawList.AddRect(new Rect2(cx, y - st.ascent, GetThemeConstant("caret_width"), h), GetThemeColor("caret_color"), false);
            }
            _ = style;
        }
    }

    // ======================================================================================== RichTextLabel
    /// <summary>The RichTextLabel the game uses: [color=..], [b], [i] BBCode, word-wrapped, fit_content.</summary>
    public partial class RichTextLabel : Control
    {
        string _text = "";
        public bool BbcodeEnabled;
        public bool FitContent;
        public bool ScrollActive = true;
        AutowrapMode _autowrap = AutowrapMode.WordSmart;
        public HorizontalAlignment HorizontalAlignment = HorizontalAlignment.Left;
        float _contentH;
        struct Span { public string text; public Col? color; }
        readonly List<Span> _spans = new List<Span>();

        public RichTextLabel() { MouseFilter = MouseFilterEnum.Stop; ClipContents = true; }

        public string Text { get => _text; set { _text = value ?? ""; Parse(); QueueRedraw(); UpdateMinimumSize(); } }
        public AutowrapMode AutowrapMode { get => _autowrap; set { _autowrap = value; QueueRedraw(); UpdateMinimumSize(); } }

        public void AppendText(string bbcode) => Text = _text + bbcode;
        public void Clear() => Text = "";

        // visible_characters / visible_ratio, as Godot's default VC_CHARS_BEFORE_SHAPING: the text is cut to its first
        // N characters before it's laid out (it looks like the text being typed)
        int _visibleChars = -1;
        public int VisibleCharacters
        {
            get => _visibleChars;
            set { if (_visibleChars == value) return; _visibleChars = value; QueueRedraw(); if (FitContent) UpdateMinimumSize(); }
        }

        public double VisibleRatio
        {
            get { int total = GetTotalCharacterCount(); return _visibleChars < 0 || total == 0 ? 1.0 : Math.Min(1.0, _visibleChars / (double)total); }
            set => VisibleCharacters = value >= 1 ? -1 : (int)(GetTotalCharacterCount() * value);
        }

        public int GetTotalCharacterCount()
        {
            int n = 0;
            foreach (var sp in _spans) n += sp.text.Length;
            return n;
        }

        public string GetParsedText()
        {
            var sb = new StringBuilder();
            foreach (var s in _spans) sb.Append(s.text);
            return sb.ToString();
        }

        void Parse()
        {
            _spans.Clear();
            if (!BbcodeEnabled) { _spans.Add(new Span { text = _text }); return; }
            var colors = new Stack<Col>();
            var sb = new StringBuilder();
            int i = 0;
            void Flush()
            {
                if (sb.Length == 0) return;
                _spans.Add(new Span { text = sb.ToString(), color = colors.Count > 0 ? colors.Peek() : (Col?)null });
                sb.Clear();
            }
            while (i < _text.Length)
            {
                if (_text[i] == '[')
                {
                    int close = _text.IndexOf(']', i);
                    if (close > i)
                    {
                        string tag = _text.Substring(i + 1, close - i - 1);
                        if (tag.StartsWith("color="))
                        {
                            Flush();
                            string cs = tag.Substring(6).Trim('"');
                            colors.Push(Col.HtmlIsValid(cs) ? Col.Html(cs) : Col.Named(cs));
                            i = close + 1;
                            continue;
                        }
                        if (tag == "/color") { Flush(); if (colors.Count > 0) colors.Pop(); i = close + 1; continue; }
                        if (tag == "b" || tag == "/b" || tag == "i" || tag == "/i" || tag == "center" || tag == "/center") { i = close + 1; continue; }
                    }
                }
                sb.Append(_text[i]);
                i++;
            }
            Flush();
        }

        sealed class Run { public ShapedText st; public Col color; public float x; public int line; }

        List<Run> Layout(float width, out float height, out List<(float asc, float desc, float w)> lineInfo)
        {
            var font = GetThemeFont("normal_font");
            int fs = GetThemeFontSize("normal_font_size");
            var runs = new List<Run>();
            lineInfo = new List<(float, float, float)>();
            float x = 0;
            int line = 0;
            float asc = (float)font.GetAscent(fs), desc = (float)font.GetDescent(fs);
            Col def = GetThemeColor("default_color");
            int left = _visibleChars;
            foreach (var sp in _spans)
            {
                if (left == 0) break;
                string text = sp.text;
                if (left > 0)
                {
                    if (text.Length > left) text = text.Substring(0, left);
                    left -= text.Length;
                }
                // split on spaces keeping them, wrap by words
                var parts = new List<string>();
                var cur = new StringBuilder();
                foreach (char ch in text)
                {
                    if (ch == '\n') { if (cur.Length > 0) parts.Add(cur.ToString()); cur.Clear(); parts.Add("\n"); continue; }
                    cur.Append(ch);
                    if (ch == ' ') { parts.Add(cur.ToString()); cur.Clear(); }
                }
                if (cur.Length > 0) parts.Add(cur.ToString());
                foreach (var w in parts)
                {
                    if (w == "\n") { lineInfo.Add((asc, desc, x)); line++; x = 0; continue; }
                    var st = font.ShapeCached(w, fs);
                    float ww = st.width;
                    float trimmed = w.EndsWith(" ") ? font.ShapeCached(w.TrimEnd(' '), fs).width : ww;
                    if (_autowrap != AutowrapMode.Off && width > 0 && x > 0 && x + trimmed > width)
                    {
                        lineInfo.Add((asc, desc, x));
                        line++;
                        x = 0;
                    }
                    runs.Add(new Run { st = st, color = sp.color ?? def, x = x, line = line });
                    x += ww;
                }
            }
            lineInfo.Add((asc, desc, x));
            int sep = GetThemeConstant("line_separation");
            height = 0;
            for (int i = 0; i < lineInfo.Count; i++) height += lineInfo[i].Item1 + lineInfo[i].Item2 + (i > 0 ? sep : 0);
            return runs;
        }

        public override Vec2 GetMinimumSize()
        {
            var sb = GetThemeStylebox("normal");
            if (!FitContent) return sb.GetMinimumSize();
            Layout(Size.x - sb.GetMinimumSize().x, out float h, out _);
            _contentH = h;
            return new Vec2(sb.GetMinimumSize().x, h + sb.GetMinimumSize().y);
        }

        protected override void OnResized() { if (FitContent) UpdateMinimumSize(); }

        public int GetContentHeight() => (int)_contentH;

        protected override void OnDraw()
        {
            var sb = GetThemeStylebox("normal");
            sb.Draw(drawList, new Rect2(Vec2.Zero, Size));
            float width = Size.x - sb.GetMinimumSize().x;
            var runs = Layout(width, out float h, out var lines);
            _contentH = h;
            int os = GetThemeConstant("outline_size");
            Col oc = GetThemeColor("font_outline_color");
            int sep = GetThemeConstant("line_separation");
            var lineY = new float[lines.Count];
            float y = sb.GetOffset().y;
            for (int i = 0; i < lines.Count; i++)
            {
                lineY[i] = y + lines[i].asc;
                y += lines[i].asc + lines[i].desc + sep;
            }
            for (int pass = 0; pass < 2; pass++)
                foreach (var r in runs)
                {
                    float lx = sb.GetOffset().x;
                    if (HorizontalAlignment == HorizontalAlignment.Center) lx += MathF.Floor((width - lines[r.line].w) / 2);
                    else if (HorizontalAlignment == HorizontalAlignment.Right) lx += width - lines[r.line].w;
                    var p = new Vec2(lx + r.x, lineY[r.line]);
                    if (pass == 0) { if (os > 0 && oc.a > 0) r.st.Draw(drawList, p, oc, os); }
                    else r.st.Draw(drawList, p, r.color, 0);
                }
        }
    }
}
