// Ported from godot/scripts/app/showcase.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector2i = Fatebound.Sim.Vec2i;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;
using Transform3D = Fatebound.Sim.Xform3;
using Environment = Fatebound.GUI.Environment;
using Eco = Fatebound.Game.Economy;
using View = Fatebound.Game.SiegeView;

namespace Fatebound.Game
{
    // 3D hero: the player's equipped look for a class idling on a small stone dais. Transparent
    // background so it sits on the pre-rendered Blender backdrop (assets/ui/hero_backdrop.jpg).
    // Rendered in its own SubViewport at physical-pixel resolution; only transforms change per frame.
    public class Showcase : Control
    {
        public const string BACKDROP = "res://assets/ui/hero_backdrop.jpg";

        public SubViewport viewport;
        public Node3D world;
        public Node3D holder;
        public Node3D body;
        public AnimationPlayer player;
        public string cls = "knight";
        public GDict cosmetic = new GDict();
        public string _key = "";
        // Camera framing (set before the node enters the tree): distance, height, look-at height.
        public double cam_z = 7.4;
        public double cam_y = 1.45;
        public double look_y = 0.88;
        // 0.31.175: without its own stone plinth (a contact shadow only) -- the 5v5 hero window stands the hero on the painted
        // hall's dais instead
        public bool plinth = true;
        // 0.31.42: turn it with a finger (the Siege Pass detail view). A drag spins the figure; let go and it coasts to a stop,
        // then turns slowly on its own.
        public bool interactive = false;
        public double _yaw = -0.12;
        public double _spin = 0.0;
        public bool _dragging = false;
        public double _last_drag = -10.0;
        // 0.31.48 (Kevin: zoom in and out in the detail window): two-finger pinch, the mouse wheel, or zoom_by() from buttons.
        public const double ZOOM_MIN = 0.75;
        public const double ZOOM_MAX = 2.6;
        public Camera3D _cam;
        public double _zoom = 1.0;
        public double _zoom_to = 1.0;
        public GDict _touches = new GDict();
        public double _pinch_d = 0.0;

        public static TextureRect Backdrop(Control parent)
        {
            var t = new TextureRect();
            t.Texture = ResourceLoader.Load<Texture2D>(BACKDROP);
            t.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            t.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
            t.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(t);
            return t;
        }

        protected override void _Ready()
        {
            MouseFilter = interactive ? Control.MOUSE_FILTER_STOP : Control.MOUSE_FILTER_IGNORE;
            viewport = new SubViewport();
            viewport.OwnWorld3D = true;
            viewport.TransparentBg = true;
            viewport.Msaa3D = Viewport.MSAA_DISABLED;       // 0.31.144: drawn at the screen's own pixel density; MSAA's pipelines weren't pre-compiled (a hitch the first time it opened)
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
            _BuildScene();
            Resized += _Resize;
            _Resize();
            _Rebuild();
        }

        public void _Resize()
        {
            // Physical pixels: the canvas is stretched, so scale by window size over logical size.
            var logical = GetViewport().GetVisibleRect().size;
            var window = (Vector2)DisplayServer.WindowGetSize();
            var ratio = 1.0;
            if (logical.x > 0 && window.x > 0)
                ratio = GD.Clampf((double)window.x / logical.x, 1.0, 4.0);
            viewport.Size = new Vector2i(GD.Maxi(64, GD.Int(Size.x * ratio)), GD.Maxi(64, GD.Int(Size.y * ratio)));
        }

        public StandardMaterial3D _Mat(Color c, double metal = 0.0, double rough = 0.75)
        {
            var m = new StandardMaterial3D();
            m.AlbedoColor = c;
            m.Roughness = rough;
            m.Metallic = metal;
            return m;
        }

        public void _BuildScene()
        {
            var env = new Environment();
            env.BackgroundMode = Environment.BG_CLEAR_COLOR;
            env.AmbientLightSource = Environment.AMBIENT_SOURCE_COLOR;
            env.AmbientLightColor = Color.FromCode("#d8cfe6");
            // Same measured Vulkan compensation as the battle view.
            env.AmbientLightEnergy = 0.55 * View.VULKAN_AMBIENT;
            env.TonemapMode = Environment.TONE_MAPPER_FILMIC;
            env.TonemapExposure = 0.85 * View.VULKAN_EXPOSURE;
            env.TonemapWhite = 3.0;
            var we = new WorldEnvironment();
            we.Environment = env;
            world.AddChild(we);
            // Matches the backdrop: low warm sun behind-left (rim), soft key from the front-right.
            var key = new DirectionalLight3D();
            key.LightColor = Color.FromCode("#ffe2bd");
            key.LightEnergy = 1.25;
            key.RotationDegrees = new Vector3(-28, 28, 0);
            world.AddChild(key);
            var sun = new OmniLight3D();
            sun.LightColor = Color.FromCode("#ff9a4a");
            sun.LightEnergy = 3.2;
            sun.OmniRange = 9.0;
            sun.Position = new Vector3(-2.6, 2.4, -2.2);
            world.AddChild(sun);
            var cool = new OmniLight3D();
            cool.LightColor = Color.FromCode("#7f92ff");
            cool.LightEnergy = 0.9;
            cool.OmniRange = 8.0;
            cool.Position = new Vector3(2.8, 1.2, 2.4);
            world.AddChild(cool);
            var cam = new Camera3D();
            cam.Fov = 30.0;
            // Vertical FOV 30 at 7.4 m sees ~4 m of height: the 2.2 m character fills about half the
            // frame, feet at ~78% down (below them the menu's class name and picker sit on the fade).
            cam.Position = new Vector3(0, cam_y, cam_z);
            world.AddChild(cam);
            cam.LookAt(new Vector3(0, look_y, 0), Vector3.UP);
            _cam = cam;
            // Dais: dark disc shadow, gold-rimmed hex plinth.
            var shadow = new MeshInstance3D();
            var sm = new CylinderMesh();
            sm.TopRadius = 1.9;
            sm.BottomRadius = 1.9;
            sm.Height = 0.02;
            sm.RadialSegments = 40;
            shadow.Mesh = sm;
            var shm = new StandardMaterial3D();
            shm.AlbedoColor = new Color(0, 0, 0, 0.32);
            shm.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
            shm.ShadingMode = BaseMaterial3D.SHADING_MODE_UNSHADED;
            shadow.MaterialOverride = shm;
            shadow.Position = new Vector3(0, -0.6, 0);
            world.AddChild(shadow);
            holder = new Node3D();
            holder.Position = new Vector3(0, -0.24, 0);
            if (!plinth)
            {
                sm.TopRadius = 0.75;
                sm.BottomRadius = 0.75;
                shm.AlbedoColor = new Color(0, 0, 0, 0.42);
                shadow.Position = new Vector3(0, -0.235, 0);
                world.AddChild(holder);
                return;
            }
            var edge = new MeshInstance3D();
            var rm = new CylinderMesh();
            rm.TopRadius = 1.42;
            rm.BottomRadius = 1.5;
            rm.Height = 0.18;
            rm.RadialSegments = 6;
            edge.Mesh = rm;
            edge.MaterialOverride = _Mat(Color.FromCode("#d9a441"), 0.5, 0.35);
            edge.Position = new Vector3(0, -0.5, 0);
            world.AddChild(edge);
            var dais = new MeshInstance3D();
            var dm = new CylinderMesh();
            dm.TopRadius = 1.3;
            dm.BottomRadius = 1.36;
            dm.Height = 0.28;
            dm.RadialSegments = 6;
            dais.Mesh = dm;
            dais.MaterialOverride = _Mat(Color.FromCode("#77839e"));
            dais.Position = new Vector3(0, -0.38, 0);
            world.AddChild(dais);
            world.AddChild(holder);
        }

        public void ShowLook(string new_cls, GDict new_cosmetic)
        {
            cls = new_cls;
            cosmetic = new_cosmetic;
            if (IsInsideTree())
                _Rebuild();
        }

        public void _Rebuild()
        {
            var key = GD.Fmt("%s|%s", cls, GD.Str(cosmetic));
            if (key == _key || holder == null)
                return;
            _key = key;
            if (body != null)
                body.QueueFree();
            var body_key = GD.Str(Eco.UP_LOOK.Get(cls, cls));          // 0.31.38: a Crusader is built as a Knight, etc.
            GDict made = View.MakeBody(body_key, cosmetic);
            if (made.IsEmpty())
                return;
            body = made["body"].As<Node3D>();
            player = made["player"].As<AnimationPlayer>();
            holder.AddChild(body);
            body.Scale = Vector3.ONE * 1.12;
            string idle = GD.Str(View.LOOKS.Get(body_key, View.LOOKS["knight"])["idle"]);
            if (player.HasAnimation(idle))
                player.Play(idle);
        }

        public void ZoomBy(double f)
        {
            _zoom_to = GD.Clampf(_zoom_to * f, ZOOM_MIN, ZOOM_MAX);
        }

        protected override void _GuiInput(InputEvent @event)
        {
            if (!interactive)
                return;
            var now = Time.GetTicksMsec() / 1000.0;
            // zoom: wheel, trackpad/OS pinch, and our own two-finger pinch on touch screens
            if (@event is InputEventMouseButton wb && wb.Pressed && (wb.ButtonIndex == MouseButton.WheelUp || wb.ButtonIndex == MouseButton.WheelDown))
            {
                ZoomBy(wb.ButtonIndex == MouseButton.WheelUp ? 1.12 : 1.0 / 1.12);
                AcceptEvent();
                return;
            }
            if (@event is InputEventMagnifyGesture mg)
            {
                ZoomBy(mg.Factor);
                AcceptEvent();
                return;
            }
            if (@event is InputEventScreenTouch)
            {
                var st = @event as InputEventScreenTouch;
                if (st.Pressed)
                    _touches[st.Index] = st.Position;
                else
                    _touches.Erase(st.Index);
                _pinch_d = 0.0;
                if (_touches.Size() >= 2)
                {
                    _dragging = false;
                    AcceptEvent();
                    return;
                }
            }
            if (@event is InputEventScreenDrag && _touches.Size() >= 2)
            {
                var sd = @event as InputEventScreenDrag;
                _touches[sd.Index] = sd.Position;
                GArray keys = _touches.Keys();
                double d = _touches[keys[0]].V2.DistanceTo(_touches[keys[1]].V2);
                if (_pinch_d > 0.0 && d > 0.0)
                    ZoomBy(d / _pinch_d);
                _pinch_d = d;
                AcceptEvent();
                return;
            }
            if (@event is InputEventScreenTouch || (@event is InputEventMouseButton mb && mb.ButtonIndex == MouseButton.Left))
            {
                _dragging = @event.IsPressed();
                if (_dragging)
                    _spin = 0.0;
                AcceptEvent();
            }
            else if (@event is InputEventScreenDrag || (@event is InputEventMouseMotion mm && (mm.ButtonMask & MouseButtonMask.Left) != 0))
            {
                double dx = @event is InputEventScreenDrag sdr ? sdr.Relative.x : ((InputEventMouseMotion)@event).Relative.x;
                _yaw += dx * 0.012;
                _spin = GD.Lerpf(_spin, dx * 0.012 * 60.0, 0.5);            // rad/s at about 60 events a second
                _last_drag = now;
                AcceptEvent();
            }
        }

        protected override void _Process(double delta)
        {
            if (holder == null || !IsVisibleInTree())
                return;
            if (!interactive)
            {
                var hr = holder.Rotation;
                hr.y = (float)(GD.Sin(Time.GetTicksMsec() / 1000.0 * 0.4) * 0.32 - 0.12);
                holder.Rotation = hr;
                return;
            }
            if (!_dragging)
            {
                _yaw += _spin * delta;
                _spin *= GD.Exp(-delta * 2.5);
                if (Time.GetTicksMsec() / 1000.0 - _last_drag > 2.5)
                    _yaw += 0.45 * delta;                                // left alone: a slow turn
            }
            {
                var hr = holder.Rotation;
                hr.y = (float)_yaw;
                holder.Rotation = hr;
            }
            if (_cam != null && GD.Absf(_zoom - _zoom_to) > 0.0005)
            {
                _zoom = GD.Lerpf(_zoom, _zoom_to, 1.0 - GD.Exp(-delta * 12.0));
                // closer, and the eye drops toward the look point so a close-up looks at the gear, not down on the head
                var eye = new Vector3(0.0, look_y + (cam_y - look_y) / _zoom, cam_z / _zoom);
                _cam.Transform = new Transform3D(Basis.LookingAt(new Vector3(0, look_y, 0) - eye, Vector3.UP), eye);
            }
        }
    }
}
