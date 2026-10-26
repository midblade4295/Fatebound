// Ported from godot/scripts/app/skin.gd (Fatebound 0.31.222).
// (Fatebound.Game.Skin; Godot's 3D skin resource is Fatebound.GUI.Skin.)
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    // 0.31.79: the menu skin (ui_skin.gdshader) drawn behind its parent Control and sized to it. A Node2D, so containers
    // don't lay it out, and show_behind_parent puts it under the parent's own text/stylebox.
    public class Skin : Node2D
    {
        public static readonly Shader SHADER = ResourceLoader.Load<Shader>("res://scripts/app/ui_skin.gdshader");

        public double pad = 16.0;
        public ShaderMaterial mat;
        public Vector2 inset = Vector2.ZERO;          // shrink the drawn rect on each side (e.g. a raised tab drawn bigger than its button)
        public Rect2 offset_rect = new Rect2();       // when size is set, draw this rect instead of the parent's (local coordinates)

        public Skin(GDict @params = null)
        {
            @params ??= new GDict();
            mat = new ShaderMaterial();
            mat.Shader = SHADER;
            Material = mat;
            ShowBehindParent = true;
            foreach (var k in @params)
                mat.SetShaderParameter(k.AsString(), @params[k]);
        }

        public BaseButton _btn = null;
        public bool _was_down = false;
        public bool _was_off = false;

        protected override void _Ready()
        {
            var c = GetParent() as Control;
            if (c != null)
                c.Resized += _Fit;
            _btn = c as BaseButton;
            SetProcess(_btn != null);
            _Fit();
        }

        protected override void _Process(double _d)
        {
            // A button's skin follows it: pushed in while held, greyed while disabled.
            var m = _btn.GetDrawMode();
            var down = m == BaseButton.DrawModeEnum.Pressed || m == BaseButton.DrawModeEnum.HoverPressed;
            if (down != _was_down)
            {
                _was_down = down;
                mat.SetShaderParameter("pressed", down ? 1.0 : 0.0);
            }
            if (_btn.Disabled != _was_off)
            {
                _was_off = _btn.Disabled;
                mat.SetShaderParameter("dim", _was_off ? 0.55 : 0.0);
            }
        }

        public void SetParam(string k, Var v)
        {
            mat.SetShaderParameter(k, v);
        }

        public Rect2 _Rect()
        {
            if (offset_rect.size != Vector2.ZERO)
                return offset_rect;
            var c = GetParent() as Control;
            var s = c != null ? c.Size : new Vector2(10, 10);
            return new Rect2(inset, s - inset * 2.0);
        }

        public void _Fit()
        {
            var r = _Rect();
            Position = r.position;
            mat.SetShaderParameter("rect_size", r.size);
            QueueRedraw();
        }

        protected override void _Draw()
        {
            var r = _Rect();
            DrawRect(new Rect2(new Vector2(-pad, -pad), r.size + new Vector2(pad * 2.0, pad * 2.0)), Color.WHITE);
        }
    }
}
