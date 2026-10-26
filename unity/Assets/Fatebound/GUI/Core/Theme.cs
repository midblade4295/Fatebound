// Fatebound GUI (Unity port): theme items -- Godot's default theme (default_theme.cpp) for the control types the game
// uses, and the lookup order a Control follows: its own overrides, the type variation, then its class and base classes.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public enum ThemeDataType { Color = 0, Constant = 1, Font = 2, FontSize = 3, Icon = 4, StyleBox = 5 }

    public sealed class Theme : Resource
    {
        readonly Dictionary<(string, string), object>[] _items = new Dictionary<(string, string), object>[6];
        readonly Dictionary<string, string> _variations = new Dictionary<string, string>();
        public Font DefaultFont;
        public int DefaultFontSize = -1;

        public Theme()
        {
            for (int i = 0; i < 6; i++) _items[i] = new Dictionary<(string, string), object>();
        }

        public void Set(ThemeDataType t, string name, string type, object v) => _items[(int)t][(type, name)] = v;
        public bool TryGet(ThemeDataType t, string name, string type, out object v) => _items[(int)t].TryGetValue((type, name), out v);

        public void SetColor(string name, string type, Col c) => Set(ThemeDataType.Color, name, type, c);
        public void SetConstant(string name, string type, int c) => Set(ThemeDataType.Constant, name, type, c);
        public void SetFont(string name, string type, Font f) => Set(ThemeDataType.Font, name, type, f);
        public void SetFontSize(string name, string type, int s) => Set(ThemeDataType.FontSize, name, type, s);
        public void SetIcon(string name, string type, Texture2D t) => Set(ThemeDataType.Icon, name, type, t);
        public void SetStylebox(string name, string type, StyleBox s) => Set(ThemeDataType.StyleBox, name, type, s);
        public void SetTypeVariation(string variation, string baseType) => _variations[variation] = baseType;
        public string GetTypeVariationBase(string v) => _variations.TryGetValue(v, out var b) ? b : null;

        static Theme _default;
        public static Theme Default
        {
            get
            {
                if (_default == null) _default = BuildDefault();
                return _default;
            }
        }

        // ---------- default_theme.cpp (scale 1) ----------
        static StyleBoxFlat Flat(Col c, float l = 4, float t = 4, float r = 4, float b = 4, int radius = 3, bool drawCenter = true, int border = 0)
        {
            var s = new StyleBoxFlat { BgColor = c };
            s.ContentMarginLeft = Math.Round(l);
            s.ContentMarginTop = Math.Round(t);
            s.ContentMarginRight = Math.Round(r);
            s.ContentMarginBottom = Math.Round(b);
            s.SetCornerRadiusAll(radius);
            s.AntiAliasing = true;
            s.CornerDetail = (int)Math.Min(Math.Ceiling(1.5 * radius), 6);
            s.DrawCenter = drawCenter;
            s.SetBorderWidthAll(border);
            return s;
        }

        static StyleBoxEmpty Empty(float l = -1, float t = -1, float r = -1, float b = -1)
        {
            var s = new StyleBoxEmpty();
            s.ContentMarginLeft = l; s.ContentMarginTop = t; s.ContentMarginRight = r; s.ContentMarginBottom = b;
            return s;
        }

        static Theme BuildDefault()
        {
            var th = new Theme { DefaultFontSize = 16 };
            Col fontColor = new Col(0.875f, 0.875f, 0.875f);
            Col fontHover = new Col(0.95f, 0.95f, 0.95f);
            Col fontPressed = new Col(1f, 1f, 1f);
            Col fontDisabled = fontColor * new Col(1f, 1f, 1f, 0.5f);
            Col fontPlaceholder = new Col(fontColor.r, fontColor.g, fontColor.b, 0.6f);
            Col normal = new Col(0.1f, 0.1f, 0.1f, 0.6f);
            Col hover = new Col(0.225f, 0.225f, 0.225f, 0.6f);
            Col pressed = new Col(0f, 0f, 0f, 0.6f);
            Col disabled = new Col(0.1f, 0.1f, 0.1f, 0.3f);
            Col focusC = new Col(1f, 1f, 1f, 0.75f);
            Col progress = new Col(1f, 1f, 1f, 0.4f);
            Col black = new Col(0f, 0f, 0f);

            th.SetStylebox("panel", "Panel", Flat(normal, 0, 0, 0, 0));
            th.SetStylebox("panel", "PanelContainer", Flat(normal, 0, 0, 0, 0));

            var focus = Flat(focusC, 4, 4, 4, 4, 3, false, 2);
            focus.SetExpandMarginAll(2);
            th.SetStylebox("normal", "Button", Flat(normal));
            th.SetStylebox("hover", "Button", Flat(hover));
            th.SetStylebox("pressed", "Button", Flat(pressed));
            th.SetStylebox("disabled", "Button", Flat(disabled));
            th.SetStylebox("focus", "Button", focus);
            th.SetFontSize("font_size", "Button", -1);
            th.SetConstant("outline_size", "Button", 0);
            th.SetColor("font_color", "Button", fontColor);
            th.SetColor("font_pressed_color", "Button", fontPressed);
            th.SetColor("font_hover_color", "Button", fontHover);
            th.SetColor("font_focus_color", "Button", fontHover);
            th.SetColor("font_hover_pressed_color", "Button", fontPressed);
            th.SetColor("font_disabled_color", "Button", fontDisabled);
            th.SetColor("font_outline_color", "Button", black);
            foreach (var n in new[] { "icon_normal_color", "icon_pressed_color", "icon_hover_color", "icon_hover_pressed_color", "icon_focus_color" })
                th.SetColor(n, "Button", Col.WHITE);
            th.SetColor("icon_disabled_color", "Button", new Col(1f, 1f, 1f, 0.4f));
            th.SetConstant("h_separation", "Button", 4);
            th.SetConstant("icon_max_width", "Button", 0);
            th.SetConstant("align_to_largest_stylebox", "Button", 0);

            th.SetStylebox("normal", "Label", new StyleBoxEmpty());
            th.SetStylebox("focus", "Label", focus);
            th.SetFontSize("font_size", "Label", -1);
            th.SetColor("font_color", "Label", Col.WHITE);
            th.SetColor("font_shadow_color", "Label", new Col(0f, 0f, 0f, 0f));
            th.SetColor("font_outline_color", "Label", black);
            th.SetConstant("shadow_offset_x", "Label", 1);
            th.SetConstant("shadow_offset_y", "Label", 1);
            th.SetConstant("outline_size", "Label", 0);
            th.SetConstant("shadow_outline_size", "Label", 1);
            th.SetConstant("line_spacing", "Label", 3);
            th.SetConstant("paragraph_spacing", "Label", 0);
            th.SetTypeVariation("HeaderSmall", "Label");
            th.SetFontSize("font_size", "HeaderSmall", 20);
            th.SetTypeVariation("HeaderMedium", "Label");
            th.SetFontSize("font_size", "HeaderMedium", 24);
            th.SetTypeVariation("HeaderLarge", "Label");
            th.SetFontSize("font_size", "HeaderLarge", 28);

            var le = Flat(normal);
            le.SetBorderWidth(Side.Bottom, 2);
            le.BorderColor = pressed;
            th.SetStylebox("normal", "LineEdit", le);
            th.SetStylebox("focus", "LineEdit", focus);
            var leRo = Flat(disabled);
            leRo.SetBorderWidth(Side.Bottom, 2);
            leRo.BorderColor = pressed * new Col(1f, 1f, 1f, 0.5f);
            th.SetStylebox("read_only", "LineEdit", leRo);
            th.SetFontSize("font_size", "LineEdit", -1);
            th.SetColor("font_color", "LineEdit", fontColor);
            th.SetColor("font_selected_color", "LineEdit", fontPressed);
            th.SetColor("font_uneditable_color", "LineEdit", fontDisabled);
            th.SetColor("font_placeholder_color", "LineEdit", fontPlaceholder);
            th.SetColor("font_outline_color", "LineEdit", black);
            th.SetColor("caret_color", "LineEdit", fontHover);
            th.SetColor("selection_color", "LineEdit", new Col(0.5f, 0.5f, 0.5f));
            th.SetConstant("minimum_character_width", "LineEdit", 4);
            th.SetConstant("outline_size", "LineEdit", 0);
            th.SetConstant("caret_width", "LineEdit", 1);

            th.SetStylebox("background", "ProgressBar", Flat(disabled, 2, 2, 2, 2, 6));
            th.SetStylebox("fill", "ProgressBar", Flat(progress, 2, 2, 2, 2, 6));
            th.SetFontSize("font_size", "ProgressBar", -1);
            th.SetColor("font_color", "ProgressBar", fontHover);
            th.SetColor("font_outline_color", "ProgressBar", black);
            th.SetConstant("outline_size", "ProgressBar", 0);

            th.SetStylebox("scroll", "HScrollBar", Flat(normal, 0, 4, 0, 4, 10));
            th.SetStylebox("scroll", "VScrollBar", Flat(normal, 4, 0, 4, 0, 10));
            foreach (var t in new[] { "HScrollBar", "VScrollBar" })
            {
                th.SetStylebox("scroll_focus", t, focus);
                th.SetStylebox("grabber", t, Flat(progress, 4, 4, 4, 4, 10));
                th.SetStylebox("grabber_highlight", t, Flat(focusC, 4, 4, 4, 4, 10));
                th.SetStylebox("grabber_pressed", t, Flat(focusC * new Col(0.75f, 0.75f, 0.75f), 4, 4, 4, 4, 10));
            }

            th.SetStylebox("slider", "HSlider", Flat(normal, 4, 4, 4, 4, 4));
            th.SetStylebox("grabber_area", "HSlider", Flat(progress, 4, 4, 4, 4, 4));
            th.SetStylebox("grabber_area_highlight", "HSlider", Flat(focusC, 4, 4, 4, 4, 4));
            th.SetConstant("center_grabber", "HSlider", 0);
            th.SetConstant("grabber_offset", "HSlider", 0);

            th.SetStylebox("panel", "ScrollContainer", new StyleBoxEmpty());
            var sfocus = Flat(focusC);
            sfocus.SetExpandMarginAll(4);
            sfocus.SetBorderWidthAll(2);
            sfocus.DrawCenter = false;
            sfocus.BorderColor = focusC;
            th.SetStylebox("focus", "ScrollContainer", sfocus);
            th.SetConstant("scrollbar_h_separation", "ScrollContainer", 0);
            th.SetConstant("scrollbar_v_separation", "ScrollContainer", 0);

            th.SetStylebox("focus", "RichTextLabel", focus);
            th.SetStylebox("normal", "RichTextLabel", Empty(0, 0, 0, 0));
            foreach (var n in new[] { "normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size" })
                th.SetFontSize(n, "RichTextLabel", -1);
            th.SetColor("default_color", "RichTextLabel", Col.WHITE);
            th.SetColor("font_shadow_color", "RichTextLabel", new Col(0f, 0f, 0f, 0f));
            th.SetColor("font_outline_color", "RichTextLabel", black);
            th.SetConstant("shadow_offset_x", "RichTextLabel", 1);
            th.SetConstant("shadow_offset_y", "RichTextLabel", 1);
            th.SetConstant("shadow_outline_size", "RichTextLabel", 1);
            th.SetConstant("line_separation", "RichTextLabel", 0);
            th.SetConstant("paragraph_separation", "RichTextLabel", 0);
            th.SetConstant("outline_size", "RichTextLabel", 0);

            th.SetConstant("separation", "BoxContainer", 4);
            th.SetConstant("separation", "HBoxContainer", 4);
            th.SetConstant("separation", "VBoxContainer", 4);
            th.SetConstant("margin_left", "MarginContainer", 0);
            th.SetConstant("margin_top", "MarginContainer", 0);
            th.SetConstant("margin_right", "MarginContainer", 0);
            th.SetConstant("margin_bottom", "MarginContainer", 0);
            th.SetConstant("h_separation", "GridContainer", 4);
            th.SetConstant("v_separation", "GridContainer", 4);
            th.SetConstant("h_separation", "FlowContainer", 4);
            th.SetConstant("v_separation", "FlowContainer", 4);
            th.SetConstant("h_separation", "HFlowContainer", 4);
            th.SetConstant("v_separation", "HFlowContainer", 4);
            th.SetConstant("h_separation", "VFlowContainer", 4);
            th.SetConstant("v_separation", "VFlowContainer", 4);
            th.SetConstant("separation", "HSeparator", 4);
            th.SetConstant("separation", "VSeparator", 4);
            var sep = new StyleBoxLine { Color = new Col(0.5f, 0.5f, 0.5f), Thickness = 1 };
            th.SetStylebox("separator", "HSeparator", sep);
            th.SetStylebox("separator", "VSeparator", new StyleBoxLine { Color = new Col(0.5f, 0.5f, 0.5f), Thickness = 1, Vertical = true });

            th.SetStylebox("panel", "TooltipPanel", Flat(new Col(0f, 0f, 0f, 0.5f), 2, 1, 2, 1));
            th.SetColor("font_color", "TooltipLabel", fontHover);
            return th;
        }
    }
}
