// Ported from godot/scripts/app/chest_row.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector2i = Fatebound.Sim.Vec2i;
using Vector3 = Fatebound.Sim.Vec3;
using Transform3D = Fatebound.Sim.Xform3;
using Chest3D = Fatebound.Game.Chest3d;

namespace Fatebound.Game
{
    // 0.31.79: Home's chest slots in 3D -- one transparent SubViewport across the row, an orthographic camera, each chest
    // standing over its slot (x = the slot's centre in this control). A ready chest teases (hops and rattles, light leaking
    // from the lid); the others breathe.
    public class ChestRow : Control
    {
        public GArray slots = new GArray();                  // [{kind, mode: "tease"|"idle", x}]
        public double chest_px = 84.0;                   // how wide a chest looks on screen
        public double base_y = 0.82;                     // where the chests' feet sit, as a fraction of the height
        public SubViewport viewport;
        public Node3D world;
        public Camera3D cam;
        public GArray _chests = new GArray();
        public double _t = 0.0;
        public const double YAW = 28.0;
        public const double PITCH = 22.0;

        protected override void _Ready()
        {
            MouseFilter = Control.MOUSE_FILTER_IGNORE;
            viewport = new SubViewport();
            viewport.OwnWorld3D = true;
            viewport.TransparentBg = true;
            viewport.Msaa3D = Viewport.MSAA_DISABLED;       // 0.31.142: as war_room.gd (MSAA meant pipelines compiled on Home's first frame)
            viewport.RenderTargetUpdateMode = SubViewport.UPDATE_WHEN_VISIBLE;
            AddChild(viewport);
            var tex = new TextureRect();
            tex.Texture = viewport.GetTexture();
            tex.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            tex.StretchMode = TextureRect.STRETCH_SCALE;
            tex.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            tex.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(tex);
            world = new Node3D();
            viewport.AddChild(world);
            Chest3D.Stage(world);
            cam = new Camera3D();
            cam.Projection = Camera3D.PROJECTION_ORTHOGONAL;
            world.AddChild(cam);
            foreach (var s in slots)
            {
                var c = Chest3D.Make(GD.Str(s["kind"]));
                world.AddChild(c);
                _chests.Append(c);
            }
            Resized += _Layout;
            _Layout();
        }

        public void _Layout()
        {
            if (Size.x <= 0.0 || Size.y <= 0.0)
                return;
            var r = Chest3D.ViewportRatio(this);
            viewport.Size = new Vector2i(GD.Maxi(64, (int)(Size.x * r)), GD.Maxi(32, (int)(Size.y * r)));
            var upp = 1.95 / chest_px;                         // metres per pixel (a chest seen at this angle is ~1.95 m across)
            cam.Size = Size.y * upp;
            var yaw = GD.DegToRad(YAW);
            var pitch = GD.DegToRad(PITCH);
            var fwd = new Vector3(-Math.Sin(yaw) * Math.Cos(pitch), -Math.Sin(pitch), -Math.Cos(yaw) * Math.Cos(pitch));
            var right = new Vector3(Math.Cos(yaw), 0.0, -Math.Sin(yaw));
            var up = right.Cross(fwd).NormalizedChecked();
            // the point at the viewport's centre: chests stand on y = 0, their feet base_y down the frame
            var centre = up * ((base_y - 0.5) * Size.y * upp);
            cam.Transform = new Transform3D(Basis.LookingAt(fwd, Vector3.UP), centre - fwd * 20.0);
            for (int i = 0; i < _chests.Size(); i++)
            {
                double x = (double)slots[i]["x"];
                (_chests[i].As<Node3D>()).Position = right * ((x - Size.x * 0.5) * upp);
            }
        }

        protected override void _Process(double delta)
        {
            if (!IsVisibleInTree())
                return;
            _t += delta;
            for (int i = 0; i < _chests.Size(); i++)
                Chest3D.Pose(_chests[i].As<Node3D>(), GD.Str(slots[i]["mode"]), _t, i * 0.7);
        }
    }
}
