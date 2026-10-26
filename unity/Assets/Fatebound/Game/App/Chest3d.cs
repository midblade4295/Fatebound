// Ported from godot/scripts/app/chest3d.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;
using Environment = Fatebound.GUI.Environment;

namespace Fatebound.Game
{
    // 0.31.79: the Meshy chests in the menus (baked by tools/chest_bake.gd: 1.6 m wide, base at y 0, front +Z, the lid hung
    // from a "Lid" pivot at its back edge). make() adds the treasure's light; pose() animates idle / tease / open.
    public class Chest3d
    {
        public const string DIR = "res://assets/ui/v2/chests/";
        public static readonly GDict KIND = new GDict { { "wooden", "wood" }, { "wood", "wood" }, { "silver", "silver" }, { "gold", "gold" }, { "royal", "royal" } };
        public static readonly GDict GLOW = new GDict { { "wood", Color.FromCode("#ffcf6a") }, { "silver", Color.FromCode("#bfe2ff") }, { "gold", Color.FromCode("#ffd76a") }, { "royal", Color.FromCode("#e2a8ff") } };

        public static Node3D Make(string kind)
        {
            string k = KIND.Get(kind, "wood").AsString();
            PackedScene ps = ResourceLoader.Load<PackedScene>(DIR + GD.Fmt("%s.scn", k));
            var root = new Node3D();
            Node3D body = ps.Instantiate() as Node3D;
            body.Name = "Body";
            root.AddChild(body);
            var seam = GD.Float(Var.Of(body.GetMeta("seam", 0.6)));
            var depth = GD.Float(Var.Of(body.GetMeta("depth", 1.0)));
            var light = new OmniLight3D();
            light.Name = "Glow";
            light.LightColor = (Color)GLOW[k];
            light.OmniRange = 2.2;
            light.LightEnergy = 0.0;
            light.Position = new Vector3(0.0, seam + 0.15, 0.0);
            body.AddChild(light);
            var card = new MeshInstance3D();
            card.Name = "Card";
            var pm = new PlaneMesh();
            pm.Size = new Vector2(1.45, depth * 0.9);
            card.Mesh = pm;
            var gm = new StandardMaterial3D();
            gm.ShadingMode = BaseMaterial3D.SHADING_MODE_UNSHADED;
            Color gc = (Color)GLOW[k];
            gm.AlbedoColor = new Color(gc.r * 1.9, gc.g * 1.6, gc.b * 1.1);
            card.MaterialOverride = gm;
            card.Position = new Vector3(0.0, seam - 0.06, 0.0);
            card.Visible = false;
            body.AddChild(card);
            root.SetMeta("seam", seam);
            return root;
        }

        public static double _EaseOutBack(double x)
        {
            var c1 = 1.9;
            var c3 = c1 + 1.0;
            return 1.0 + c3 * GD.Pow(x - 1.0, 3.0) + c1 * GD.Pow(x - 1.0, 2.0);
        }

        public static void Pose(Node3D root, string mode, double t, double phase = 0.0)
        {
            // mode: "idle" (a slow breath), "tease" (ready to open: a hop and a rattle every couple of seconds with light
            // leaking out of the lid), "open" (t seconds into the 1.6 s opening: shake, pop, the lid flies open, light spills out),
            // "opened" (held open).
            Node3D body = root.GetNode("Body") as Node3D;
            Node3D lid = body.GetNode("Lid") as Node3D;
            OmniLight3D light = body.GetNode("Glow") as OmniLight3D;
            MeshInstance3D card = body.GetNode("Card") as MeshInstance3D;
            var lid_deg = 0.0;
            var y = 0.0;
            var sx = 1.0;
            var sy = 1.0;
            var rz = 0.0;
            var glow = 0.0;
            switch (mode)
            {
                case "idle":
                    {
                        var p = (t + phase) / 2.4 * GD.TAU;
                        y = 0.03 * (0.5 - 0.5 * GD.Cos(p));
                        sy = 1.0 + 0.02 * GD.Sin(p);
                        sx = 1.0 - 0.012 * GD.Sin(p);
                        break;
                    }
                case "tease":
                    {
                        var cyc = GD.Fmod(t + phase, 2.2);
                        var p = (t + phase) / 2.2 * GD.TAU;
                        y = 0.03 * (0.5 - 0.5 * GD.Cos(p));
                        if (cyc > 1.55)
                        {
                            var a = (cyc - 1.55) / 0.65;
                            rz = GD.Sin(a * GD.PI * 6.0) * 5.0 * GD.Sin(a * GD.PI);
                            y += 0.14 * GD.Sin(a * GD.PI);
                            lid_deg = -14.0 * GD.Sin(a * GD.PI);
                            glow = GD.Sin(a * GD.PI);
                        }
                        break;
                    }
                case "open":
                    if (t < 0.45)
                    {
                        var a = t / 0.45;
                        rz = GD.Sin(t * 48.0) * 5.0 * a;
                        sy = 1.0 - 0.1 * a;
                        sx = 1.0 + 0.06 * a;
                    }
                    else if (t < 0.62)
                    {
                        var b = (t - 0.45) / 0.17;
                        sy = GD.Lerpf(0.9, 1.14, b);
                        sx = GD.Lerpf(1.06, 0.94, b);
                        y = 0.3 * GD.Sin(b * GD.PI * 0.5);
                        lid_deg = -112.0 * _EaseOutBack(GD.Clampf(b, 0.0, 1.0)) * 0.55;
                        glow = b;
                    }
                    else
                    {
                        var c = GD.Clampf((t - 0.62) / 0.4, 0.0, 1.0);
                        lid_deg = GD.Lerpf(-61.6, -108.0, _EaseOutBack(c));
                        y = 0.3 * (1.0 - c) * (1.0 - c);
                        var land = GD.Clampf((t - 0.85) / 0.25, 0.0, 1.0);
                        sy = 1.0 + 0.08 * GD.Sin(land * GD.PI) * (1.0 - land) - 0.02 * GD.Sin(land * GD.PI);
                        sx = 1.0 - 0.04 * GD.Sin(land * GD.PI) * (1.0 - land);
                        glow = 1.0;
                    }
                    break;
                case "opened":
                    lid_deg = -108.0;
                    glow = 0.85 + 0.15 * GD.Sin(t * 3.0);
                    break;
            }
            body.Position = new Vector3(0.0, y, 0.0);
            body.Scale = new Vector3(sx, sy, sx);
            body.Rotation = new Vector3(0.0, 0.0, GD.DegToRad(rz));
            lid.Rotation = new Vector3(GD.DegToRad(lid_deg), 0.0, 0.0);
            light.LightEnergy = 1.6 * glow;
            card.Visible = glow > 0.05;
        }

        public static void Stage(Node3D world)
        {
            // The lights and environment the chests are lit with (a warm key, a cool rim).
            var env = new Environment();
            env.BackgroundMode = Environment.BG_CLEAR_COLOR;
            env.AmbientLightSource = Environment.AMBIENT_SOURCE_COLOR;
            env.AmbientLightColor = new Color(0.8, 0.82, 0.95);
            env.AmbientLightEnergy = 0.75;
            env.TonemapMode = Environment.TONE_MAPPER_FILMIC;
            var we = new WorldEnvironment();
            we.Environment = env;
            world.AddChild(we);
            var sun = new DirectionalLight3D();
            sun.LightColor = Color.FromCode("#ffe6c0");
            sun.LightEnergy = 1.35;
            world.AddChild(sun);
            sun.LookAtFromPosition(new Vector3(2.0, 4.0, 3.5), Vector3.ZERO, Vector3.UP);
            var rim = new DirectionalLight3D();
            rim.LightColor = Color.FromCode("#9cc0ff");
            rim.LightEnergy = 1.2;
            world.AddChild(rim);
            rim.LookAtFromPosition(new Vector3(-3.0, 2.5, -3.0), Vector3.ZERO, Vector3.UP);
        }

        public static double ViewportRatio(Control c)
        {
            var logical = c.GetViewport().GetVisibleRect().size;
            var window = (Vector2)DisplayServer.WindowGetSize();
            if (logical.x > 0 && window.x > 0)
                return GD.Clampf((double)window.x / logical.x, 1.0, 4.0);
            return 1.0;
        }
    }
}
