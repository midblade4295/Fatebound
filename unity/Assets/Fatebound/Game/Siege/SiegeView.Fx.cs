// Ported from godot/scripts/siege/siege_view.gd (Fatebound 0.31.222): projectiles, effects (rings, sparks, numbers),
// the camera, health bars, cloth capes, blasts and loose weapons, the EffectBlocks explosions, physical smoke, the
// shockwave, ragdolls and dropped weapons, Vanish, meteors.
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector2i = Fatebound.Sim.Vec2i;
using Vector3 = Fatebound.Sim.Vec3;
using Vector4 = Fatebound.Sim.Vec4;
using Color = Fatebound.GUI.Col;
using Transform3D = Fatebound.Sim.Xform3;
using Quaternion = Fatebound.Sim.Quat;
using AABB = Fatebound.Sim.Aabb;
using Material = Fatebound.GUI.GMaterial;
using Environment = Fatebound.GUI.Environment;

namespace Fatebound.Game
{
    using Stage = Fatebound.Game.AssetCache;
    using Sim = Fatebound.Sim.SiegeSim;

    public partial class SiegeView
    {
        // ---------- projectiles ----------
        public void _SyncProjectiles()
        {
            var live = new GDict();
            foreach (var p in sim.projectiles)
            {
                live[p.id] = true;
                Node3D node = proj_nodes.Get(p.id).As<Node3D>();
                if (node == null)
                {
                    node = _MakeProjectile(GD.Str(p.kind));
                    if (p.big)
                        node.Scale = Vector3.ONE * 2.2;             // 0.31.157: the Ranger's DEADEYE
                    proj_nodes[p.id] = node;
                    fxs.ProjTrail(node, p);                        // 0.31.201: what it leaves behind it
                }
                // Offline the sim ticks at 30 Hz while frames run at 60: draw it where it is *now*.
                Vector2 at = p.pos + p.vel * proj_lead;
                var y = 1.2 + Sim.HeightAt(at);
                node.Position = new Vector3(at.x, y, at.y);
                node.Rotation = new Vector3(0.0, Sim.AngleOf(p.vel), 0.0);
                if (GD.Str(p.kind) == "hammer" || GD.Str(p.kind) == "boulder")
                {
                    var sp = node.GetNodeOrNull("spin") as Node3D;
                    if (sp != null)
                    {
                        var r = sp.Rotation;
                        r.x = (float)(Time.GetTicksMsec() * (GD.Str(p.kind) == "hammer" ? 0.018 : 0.012));   // end over end; the boulder rolls
                        sp.Rotation = r;
                    }
                }
            }
            foreach (var id in proj_nodes.Keys())
            {
                if (!live.Has(id))
                {
                    proj_nodes[id].As<Node>().QueueFree();
                    proj_nodes.Erase(id);
                }
            }
        }

        public Node3D _MakeProjectile(string kind)
        {
            var root = new Node3D();
            AddChild(root);
            if (kind == "hammer")
            {
                // The Crusader's hammer (0.30.5): a glowing gold head on a wooden handle, spinning end over end.
                var spin = new Node3D();
                spin.Name = "spin";
                root.AddChild(spin);
                var handle = new MeshInstance3D();
                var hm = new CylinderMesh();
                hm.TopRadius = 0.05;
                hm.BottomRadius = 0.06;
                hm.Height = 0.8;
                handle.Mesh = hm;
                var wood = new StandardMaterial3D();
                wood.AlbedoColor = new Color("#7a4e2a");
                handle.MaterialOverride = wood;
                spin.AddChild(handle);
                var head = new MeshInstance3D();
                var bm = new BoxMesh();
                bm.Size = new Vector3(0.46, 0.26, 0.26);
                head.Mesh = bm;
                head.Position = new Vector3(0.0, 0.4, 0.0);
                var gold = new StandardMaterial3D();
                gold.AlbedoColor = new Color("#f2c94c");
                gold.EmissionEnabled = true;
                gold.Emission = new Color("#ffd766");
                gold.EmissionEnergyMultiplier = 1.3;
                gold.Metallic = 0.6;
                gold.Roughness = 0.35;
                head.MaterialOverride = gold;
                spin.AddChild(head);
                root.Scale = Vector3.ONE * 1.25;
                return root;
            }
            if (kind == "pierce")
            {
                // the Sniper's shot (0.31.32): a long arrow with a pale glowing streak behind it
                var pr = new Node3D();
                var pk = Stage.Scene("res://assets/kaykit/weapons/arrow_bow.gltf");
                if (pk != null)
                {
                    Node3D ar = pk.Instantiate() as Node3D;
                    ar.Scale = new Vector3(1.6, 1.6, 2.0);
                    pr.AddChild(ar);
                }
                var streak = new MeshInstance3D();
                var cm = new CylinderMesh();
                cm.TopRadius = 0.06;
                cm.BottomRadius = 0.0;
                cm.Height = 3.2;
                streak.Mesh = cm;
                streak.MaterialOverride = _FxMat(new Color(0.85, 0.95, 1.0));
                var srot = streak.Rotation;
                srot.x = (float)(GD.PI * 0.5);
                streak.Rotation = srot;
                var spos = streak.Position;
                spos.z = -1.7f;
                streak.Position = spos;
                pr.AddChild(streak);
                AddChild(pr);
                return pr;
            }
            if (Array.IndexOf(new[] { "bolt", "ball", "thorn", "boulder" }, kind) >= 0)
            {
                _MakeShotFx(root, kind);                    // 0.31.168: the new heroes' shots
                return root;
            }
            if (kind == "arrow")
            {
                var packed = Stage.Scene("res://assets/kaykit/weapons/arrow_bow.gltf");
                if (packed != null)
                {
                    Node3D arrow = packed.Instantiate() as Node3D;
                    // The model already lies along +Z, arrowhead forward (measured: z -0.64..0.62, the narrow end at
                    // +Z), and the root turns +Z onto the flight path. The old 90 deg turn about X stood every arrow
                    // on its tip (Kevin: "arrows flying sideways instead of straight").
                    arrow.Scale = Vector3.ONE * 1.3;
                    root.AddChild(arrow);
                    return root;
                }
            }
            var ball = new MeshInstance3D();
            var sm = new SphereMesh();
            sm.Radius = kind == "fire" ? 0.28 : 0.12;
            sm.Height = sm.Radius * 2.0;
            ball.Mesh = sm;
            ball.MaterialOverride = _Unshaded(_Bright(kind == "fire" ? new Color(1.0, 0.55, 0.15, 0.95) : new Color(1, 1, 0.8, 0.9)));
            root.AddChild(ball);
            return root;
        }

        public static GDict _shot_mats = new GDict();

        public StandardMaterial3D _ShotMat(string key, Color col, double glow, double rough = 0.6)
        {
            if (!_shot_mats.Has(key))
            {
                var m = new StandardMaterial3D();
                m.AlbedoColor = col;
                m.Roughness = rough;
                if (glow > 0.0)
                {
                    m.EmissionEnabled = true;
                    m.Emission = col;
                    m.EmissionEnergyMultiplier = glow;
                }
                _shot_mats[key] = Var.Of(m);
            }
            return _shot_mats[key].As<StandardMaterial3D>();
        }

        public void _MakeShotFx(Node3D root, string kind)
        {
            // 0.31.168: the Stormcaller's bolt (a crackling blue streak), the Musketeer's ball (a lead shot and its white trail),
            // the Druid's thorn (a glowing green seed), the Golem's boulder (a carved stone with a cyan rune, rolling)
            switch (kind)
            {
                case "bolt":
                {
                    var core = new MeshInstance3D();
                    var cm = new CapsuleMesh();
                    cm.Radius = 0.07;
                    cm.Height = 1.1;
                    core.Mesh = cm;
                    var cr = core.Rotation;
                    cr.x = (float)(GD.PI * 0.5);
                    core.Rotation = cr;
                    core.MaterialOverride = _FxMat(new Color(0.85, 0.95, 1.0));
                    root.AddChild(core);
                    var glow = new MeshInstance3D();
                    var gm = new CapsuleMesh();
                    gm.Radius = 0.16;
                    gm.Height = 1.4;
                    glow.Mesh = gm;
                    var gr = glow.Rotation;
                    gr.x = (float)(GD.PI * 0.5);
                    glow.Rotation = gr;
                    glow.MaterialOverride = _Unshaded(new Color(0.35, 0.6, 1.0, 0.45));
                    root.AddChild(glow);
                    break;
                }
                case "ball":
                {
                    var ball = new MeshInstance3D();
                    var sm = new SphereMesh();
                    sm.Radius = 0.09;
                    sm.Height = 0.18;
                    ball.Mesh = sm;
                    ball.MaterialOverride = _ShotMat("ball", new Color(0.35, 0.36, 0.4), 0.0, 0.3);
                    root.AddChild(ball);
                    var trail = new MeshInstance3D();
                    var tm = new CylinderMesh();
                    tm.TopRadius = 0.07;
                    tm.BottomRadius = 0.0;
                    tm.Height = 1.6;
                    trail.Mesh = tm;
                    var tr = trail.Rotation;
                    tr.x = (float)(GD.PI * 0.5);
                    trail.Rotation = tr;
                    var tp = trail.Position;
                    tp.z = -0.85f;
                    trail.Position = tp;
                    trail.MaterialOverride = _Unshaded(new Color(1.0, 0.97, 0.9, 0.55));
                    root.AddChild(trail);
                    break;
                }
                case "thorn":
                {
                    var seed = new MeshInstance3D();
                    var pm = new PrismMesh();
                    pm.Size = new Vector3(0.16, 0.5, 0.16);
                    seed.Mesh = pm;
                    var sr = seed.Rotation;
                    sr.x = (float)(GD.PI * 0.5);
                    seed.Rotation = sr;
                    seed.MaterialOverride = _FxMat(new Color(0.55, 1.0, 0.35));
                    root.AddChild(seed);
                    var halo = new MeshInstance3D();
                    var hm = new SphereMesh();
                    hm.Radius = 0.2;
                    hm.Height = 0.4;
                    halo.Mesh = hm;
                    halo.MaterialOverride = _Unshaded(new Color(0.4, 1.0, 0.3, 0.35));
                    root.AddChild(halo);
                    break;
                }
                case "boulder":
                {
                    var spin = new Node3D();
                    spin.Name = "spin";
                    root.AddChild(spin);
                    var rock = new MeshInstance3D();
                    var rm = new SphereMesh();
                    rm.Radius = 0.48;
                    rm.Height = 0.9;
                    rm.RadialSegments = 9;
                    rm.Rings = 5;
                    rock.Mesh = rm;
                    rock.MaterialOverride = _ShotMat("boulder", new Color("#8d8a82"), 0.0, 0.95);
                    spin.AddChild(rock);
                    var rune = new MeshInstance3D();
                    rune.Mesh = _RingMesh(0.3, 0.06);
                    var rr = rune.Rotation;
                    rr.z = (float)(GD.PI * 0.5);
                    rune.Rotation = rr;
                    var rp = rune.Position;
                    rp.x = 0.44f;
                    rune.Position = rp;
                    rune.MaterialOverride = _FxMat(new Color("#5fe8ff"));
                    spin.AddChild(rune);
                    var sp = spin.Position;
                    sp.y = -0.6f;
                    spin.Position = sp;
                    break;
                }
            }
        }

        // ---------- effects ----------
        // No material or text writes per frame here. In Godot's GLES3 renderer every material parameter
        // change re-uploads that material's buffer (glBufferData), and changing a Label3D's modulate
        // rebuilds its mesh and materials. Field logs showed the Adreno driver hanging after ~5-6k frames
        // of that churn, so effects share cached materials and fade by scale only, and damage numbers
        // are drawn by the 2D HUD instead of Label3D.
        public static GDict _fx_mats = new GDict();
        public GArray numbers = new GArray();   // [{pos: Vector3, text, mine, at}] read by the HUD

        public StandardMaterial3D _FxMat(Color color)
        {
            var key = color.ToHtmlExact();
            if (!_fx_mats.Has(key))
                _fx_mats[key] = Var.Of(_Unshaded(_Bright(color)));
            return _fx_mats[key].As<StandardMaterial3D>();
        }

        public double _shake = 0.0;

        public void Shake(double amount)
        {
            _shake = GD.Maxf(_shake, amount);
        }

        // 0.31.181: a hero recalling -- a violet ring rising round his feet and motes going up, faster as he's nearly gone;
        // where he left and where he arrives a flash (on_event "recall_done")
        public double _recall_t = 0.0;
        public static readonly Color RECALL_COL = new Color("#b9a8ff");

        public void _SyncRecallFx(double dt)
        {
            if (sim == null || sim.moba == null)
                return;
            _recall_t -= dt;
            if (_recall_t > 0.0)
                return;
            _recall_t = 0.22;
            foreach (var u in sim.units)
            {
                if (!u.hero || !sim.Recalling(u))
                    continue;
                GDict a = actors.Get(u.id, new GDict()).D;
                if (a.IsEmpty() || !a["root"].As<Node3D>().Visible)
                    continue;
                Vector3 p = a["root"].As<Node3D>().Position;
                var k = 1.0 - GD.Clampf((u.recall_until - sim.time) / Sim.RECALL_TIME, 0.0, 1.0);
                RingAt(p + new Vector3(0, 0.08, 0), RECALL_COL, 0.6 + 0.8 * k, 0.55);
                for (int i = 0; i < 1 + (int)(k * 3.0); i++)
                    Spark(p + new Vector3(GD.RandfRange(-0.5, 0.5), 0.2 + GD.Randf() * 1.6, GD.RandfRange(-0.5, 0.5)), RECALL_COL);
            }
        }

        public void RingAt(Vector3 at, Color color, double grow = 2.2, double life = 0.6)
        {
            if (low_fx && life < 0.5)
                return;
            var mi = new MeshInstance3D();
            mi.Mesh = _RingMesh(0.5, 0.12);
            var c = color;
            c.a = 0.85f;
            mi.MaterialOverride = _FxMat(c);
            mi.Position = at + new Vector3(0, 0.08, 0);
            mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            AddChild(mi);
            _fx.Append(GDict.Of("node", mi, "at", _time, "life", life, "kind", "ring", "grow", grow));
        }

        public void Spark(Vector3 at, Color color)
        {
            if (low_fx)
                return;
            var mi = new MeshInstance3D();
            if (_spark_mesh == null)
            {
                _spark_mesh = new SphereMesh();
                _spark_mesh.Radius = 0.12;
                _spark_mesh.Height = 0.24;
                _spark_mesh.RadialSegments = 6;
                _spark_mesh.Rings = 3;
            }
            mi.Mesh = _spark_mesh;
            mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            mi.MaterialOverride = _FxMat(color);
            mi.Position = at;
            AddChild(mi);
            var dir = new Vector3(GD.RandfRange(-1, 1), GD.RandfRange(0.6, 1.6), GD.RandfRange(-1, 1));
            _fx.Append(GDict.Of("node", mi, "at", _time, "life", 0.45, "kind", "spark", "p0", at, "dir", dir));
        }

        public void Number(Vector3 at, string text, bool mine, bool gold = false)
        {
            numbers.Append(GDict.Of("pos", at, "text", text, "mine", mine, "at", _time, "gold", gold));
            if (numbers.Size() > 40)
                numbers.PopFront();
        }

        public void _StepFx()
        {
            for (int i = _fx.Size() - 1; i > -1; i--)
            {
                GDict fx = _fx[i].D;
                var age = _time - (double)fx["at"];
                Node3D node = fx["node"].As<Node3D>();
                if (age > (double)fx["life"] || !GD.IsInstanceValid(node))
                {
                    if (GD.IsInstanceValid(node))
                        node.QueueFree();
                    _fx.RemoveAt(i);
                    continue;
                }
                var u = age / (double)fx["life"];
                switch (GD.Str(fx["kind"]))
                {
                    case "ring":
                    {
                        // Grow outward and disappear at the end of its life (no alpha fade).
                        var s = 0.4 + u * (double)fx["grow"];
                        node.Scale = new Vector3(s, 0.3, s);
                        break;
                    }
                    case "shell":
                    {
                        Vector3 p0 = fx["p0"].AsVec3();
                        Vector3 p1 = fx["p1"].AsVec3();
                        node.Position = p0.Lerp(p1, u) + new Vector3(0, 7.0 * u * (1.0 - u), 0);
                        var r = node.Rotation;
                        r.x += 0.25f;
                        node.Rotation = r;
                        break;
                    }
                    case "spark":
                        node.Position = fx["p0"].AsVec3() + fx["dir"].AsVec3() * u * 1.2;
                        node.Scale = Vector3.ONE * GD.Maxf(0.05, 1.0 - u);
                        break;
                    case "fall":                                     // 0.31.157: an ARROW RAIN arrow
                        node.Position = fx["p0"].AsVec3().Lerp(fx["p1"].AsVec3(), u);
                        break;
                    case "bolt":                                     // 0.31.168: a lightning segment -- thins out and goes
                    {
                        var w = GD.Maxf(0.05, 1.0 - u * u);
                        node.Scale = new Vector3(w, w, 1.0);
                        break;
                    }
                }
            }
            for (int i = numbers.Size() - 1; i > -1; i--)
            {
                if (_time - (double)numbers[i]["at"] > 0.8)
                    numbers.RemoveAt(i);
            }
        }

        // ---------- camera ----------
        public GArray cam_override = new GArray();   // [eye: Vector3, target: Vector3] for tests/screenshots only

        public void SnapCamera()
        {
            // Jump straight to the player next frame (after a teleport) instead of gliding across the map.
            _cam_target = Vector3.ZERO;
        }

        // 0.31.216: the landscape camera (Honor of Kings'): its turn round the map, its tilt, how far it stands from the point it
        // looks at, how far ahead of you (up the screen) that point is, its field of view (vertical, 16:9 .. 21:9 phones
        // showing more or less across). (Until 0.31.216: portrait, looking straight up the field, 38 m up and 30 m back, fov 50.)
        public const double CAM_YAW = GD.PI / 4.0;           // the screen's up, for blue: the world's -y (up the field) turned this far toward -x
        public const double CAM_PITCH = 0.9076;         // 52 degrees
        public const double CAM_DIST = 22.0;
        public const double CAM_AHEAD = 2.0;
        public const double CAM_FOV = 34.0;

        public static Vector2 ScreenUp(int team)
        {
            // the world direction (x, z) the top of the screen looks along: blue's keep bottom-left, red's top-right
            var u = new Vector2(0.0, -1.0).Rotated(-CAM_YAW);
            return team == 0 ? u : -u;
        }

        public static Vector2 ScreenToWorld(Vector2 v, int team)
        {
            // a direction on the screen (x right, y down) as a world direction (x, z)
            var up = ScreenUp(team);
            var right = new Vector2(-up.y, up.x);
            return right * v.x - up * v.y;
        }

        public void _UpdateCamera(double dt)
        {
            if (cam_override.Size() == 2)
            {
                camera.Position = cam_override[0].AsVec3();
                camera.LookAt(cam_override[1].AsVec3(), Vector3.UP);
                return;
            }
            Unit me = sim.by_id.TryGetValue(player_id, out var me0) ? me0 : null;
            var focus = Vector3.ZERO;
            GDict a = actors.Get(player_id, new GDict()).D;
            if (!a.IsEmpty())
                focus = a["root"].As<Node3D>().Position;
            if (me != null && me.state == "dead" && !a.IsEmpty())
            {
                // 0.31.22 (Kevin): the camera stays with your body through the countdown (it cut to your spawn) -- with the
                // ragdoll's hips if it has one, so it follows where you were thrown
                var rg = a.Get("rag");
                focus = a["root"].As<Node3D>().Position;
                if (!rg.IsNull && GD.IsInstanceValid(rg["sim"]))
                {
                    foreach (var pb in rg["sim"].As<Node>().GetChildren())
                    {
                        if (pb is PhysicalBone3D && GD.Str((pb as PhysicalBone3D).BoneName) == "hips")
                        {
                            focus = (pb as Node3D).GlobalPosition;
                            focus.y = 0.0f;
                            break;
                        }
                    }
                }
            }
            // 0.31.216 (Kevin: "The game needs to change from vertical to horizontal", Honor of Kings' camera): landscape, turned
            // CAM_YAW so the square map sits square on the screen -- your keep bottom-left, theirs top-right (red's view turned
            // half way round, as before) -- looking down at CAM_PITCH, a little ahead of you (up the screen).
            var up = ScreenUp(me != null ? me.team : 0);
            var target = focus + new Vector3(up.x, 0.0, up.y) * CAM_AHEAD;
            _cam_target = _cam_target == Vector3.ZERO ? target : _cam_target.Lerp(target, 1.0 - Math.Exp(-dt * 6.0));
            camera.Position = _cam_target + new Vector3(-up.x, 0.0, -up.y) * CAM_DIST * Math.Cos(CAM_PITCH) + new Vector3(0.0, CAM_DIST * Math.Sin(CAM_PITCH), 0.0);
            camera.LookAt(_cam_target, Vector3.UP);
            if (_shake > 0.01)
            {
                // Short camera shake for the tantrum shockwave.
                camera.Position += new Vector3(GD.RandfRange(-1, 1), GD.RandfRange(-0.5, 0.5), GD.RandfRange(-1, 1)) * _shake * 0.5;
                _shake = GD.Maxf(0.0, _shake - dt * 1.6);
            }
        }

        public GDict _bar_y = new GDict();                                  // 0.31.160: a tower's / King's bar height (they don't move; was height_at a frame)
        public static readonly Color MY_BAR = new Color("#7dff8a");

        public GArray Bars()
        {
            // [{pos, fill, color}] for the HUD to draw 2D health bars over living units.
            var output = new GArray();
            if (sim.moba != null)
            {
                foreach (var tw in sim.moba.towers)                 // 0.31.155 5V5: the towers' health (wide)
                {
                    if (!tw.dead)
                    {
                        if (!_bar_y.Has(tw.id))
                            _bar_y[tw.id] = Sim.HeightAt(tw.p) + Towers.Height(tw.tier) + 0.5;     // (0.31.172: over the new towers)
                        output.Append(GDict.Of("pos", new Vector3(tw.p.x, (double)_bar_y[tw.id], tw.p.y), "fill", GD.Clampf(tw.hp / tw.max_hp, 0.0, 1.0),
                            "color", TEAM_COLORS[Vt(tw.team)], "wide", true));
                    }
                }
                for (int kt = 0; kt < 2; kt++)                               // 0.31.156: the Kings (the hearts)
                {
                    if (!sim.moba.kings[kt].dead)
                    {
                        Vector2 kp = sim.moba.KingPos(kt);
                        if (!_bar_y.Has(GD.Fmt("k%d", kt)))
                            _bar_y[GD.Fmt("k%d", kt)] = Sim.HeightAt(kp) + 3.4;
                        output.Append(GDict.Of("pos", new Vector3(kp.x, (double)_bar_y[GD.Fmt("k%d", kt)], kp.y), "fill", sim.moba.KingFrac(kt), "color", new Color("#ffd65a"), "wide", true));
                    }
                }
            }
            foreach (var u in sim.units)
            {
                if (u.state == "dead")
                    continue;
                GDict a = actors.Get(u.id, new GDict()).D;
                if (a.IsEmpty() || !GD.IsInstanceValid(a["root"]) || !a["root"].As<Node3D>().Visible)
                    continue;                                    // (0.31.158: in the fog -- no bar either)
                if (!(bool)a.Get("onscr", true))
                    continue;                                    // 0.31.219: off the screen (sync's frustum test: its bar with it)
                Color c = u.id == player_id ? MY_BAR : TEAM_COLORS[Vt(u.team)];
                var bar = GDict.Of("pos", a["root"].As<Node3D>().Position + new Vector3(0, 2.7 * u.mscale, 0), "fill", GD.Clampf(u.hp / GD.Maxf(1.0, u.max_hp), 0.0, 1.0), "color", c);
                if (u.HasMon && u.mscale > 1.0)
                {
                    bar["name"] = GD.Str(Moba.MONSTERS[GD.Str(u.mkind)].name);        // 0.31.157: the buff monsters and the Bone Lord
                    bar["name_color"] = new Color("#ffe9a6");
                    if (Array.IndexOf(new[] { "lord", "wyrm" }, GD.Str(u.mkind)) >= 0)
                        bar["wide"] = true;
                }
                else if (u.lordling)
                {
                    bar["name"] = "Bone Lord";                                       // 0.31.158: marching for a side
                    bar["name_color"] = TEAM_COLORS[Vt(u.team)].Lightened(0.3);
                    bar["wide"] = true;
                }
                if (u.id == player_id && my_name != "")
                {
                    // 0.31.88 (Kevin: "Show the nameplate for the players own name also"): yours from your profile, so it's there
                    // against bots too and doesn't wait on the server
                    bar["name"] = my_tag != "" ? GD.Fmt("[%s] %s", my_tag, my_name) : my_name;
                    bar["crest"] = my_crest;
                    bar["title"] = my_title;
                    bar["name_color"] = new Color("#8cf0a8");       // (0.31.195: yours green -- no yellow text; gold until then)
                }
                else if (player_names.Has(u.id))
                {
                    // 0.31.86 (Kevin: "shows the player names on the battlefield above their heads. Only live players will show
                    // names."): over the bar -- yours gold (green since 0.31.195), your side's light blue, theirs light red (0.31.177: bots by their names)
                    bar["name"] = GD.Str(player_names[u.id]);
                    if (GD.Str(player_tags.Get(u.id, "")) != "")
                    {
                        bar["name"] = GD.Fmt("[%s] %s", GD.Str(player_tags[u.id]), GD.Str(player_names[u.id]));   // 0.31.134: their clan's tag
                        bar["crest"] = GD.Str(player_crests.Get(u.id, ""));                                // 0.31.196: and crest
                    }
                    bar["title"] = GD.Str(player_titles.Get(u.id, ""));
                    bar["name_color"] = u.id == player_id ? new Color("#8cf0a8") : (Vt(u.team) == 0 ? new Color("#bfeeff") : new Color("#ffc4b4"));
                }
                else if (u.hero && u.bot && sim.moba != null)
                {
                    // 0.31.177 (Kevin: "Put the player names above the players so people know if it's player or minion easier. If
                    // it's a bot then give bot name like "bot Alfred""): a bot's hero too, by its seat's name, a shade softer
                    bar["name"] = Moba.BotLabel(u);
                    bar["name_color"] = Vt(u.team) == 0 ? new Color("#a8dcef") : new Color("#f0b4a6");
                }
                output.Append(bar);
            }
            return output;
        }

        public GArray GateBars()
        {
            // Damaged gates (either team) get a health bar over the arch.
            var output = new GArray();
            foreach (var g in sim.gates)
            {
                if (!sim.GateBlocks(g) || g.hp >= g.max_hp)
                    continue;
                output.Append(GDict.Of("pos", new Vector3(g.c.x, 4.2, g.c.y), "fill", g.hp / g.max_hp, "color", TEAM_COLORS[Vt(g.team)]));
            }
            return output;
        }

        public Vector3 UnitWorld(string id)
        {
            // 0.31.111: where a unit is drawn (the HUD pins quick chat bubbles over it); INF when there's no such unit
            GDict a = actors.Get(id, new GDict()).D;
            if (a.IsEmpty() || !GD.IsInstanceValid(a["root"]))
                return Vector3.INF;
            return a["root"].As<Node3D>().Position;
        }

        public Vector2 ScreenPoint(Vector3 world)
        {
            return camera.UnprojectPosition(world);
        }

        public bool IsOnScreen(Vector3 world)
        {
            return !camera.IsPositionBehind(world) && new Rect2(Vector2.ZERO, GetViewport().GetVisibleRect().size).HasPoint(camera.UnprojectPosition(world));
        }


        // ---------- cloth capes (0.31.17, Kevin: "realistic cloth physics for the capes"; 0.31.18: "floating capes ... very
        // jittery") ----------
        // The Knight, Mage, Ranger and both Rogues wear a cape (a skinned 56-vertex mesh in the KayKit models, rigid on the
        // torso). Near the camera it hangs from a small spring grid -- CAPE_COLS x CAPE_ROWS points, the top row pinned across
        // the shoulders to the chest bone, the rest falling under gravity with a little wind, held by stretch and bend links,
        // kept behind the back, outside the torso and above the ground -- stepped at a fixed 30 Hz and eased onto the screen.
        // The cape mesh itself is bent by the grid in its vertex shader, so there is no separate cloth object to be left
        // behind (0.31.17's floating capes) and no mesh rebuilt each frame (its cost on phones).
        public const int CAPE_COLS = 3;
        public const int CAPE_ROWS = 4;
        public const double CAPE_NEAR = 32.0;          // ground distance from the camera
        public const double CAPE_GRAVITY = 7.5;
        public const double CAPE_DAMP = 0.9;
        public const int CAPE_ITERS = 2;
        public const double CAPE_STEP = 1.0 / 30.0;
        public const string CAPE_SHADER = "\n" +
            "shader_type spatial;\n" +
            "render_mode cull_disabled;\n" +
            "uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;\n" +
            "uniform vec4 albedo : source_color = vec4(1.0);\n" +
            "uniform float roughness = 0.5;\n" +
            "uniform vec3 offs[12];\n" +
            "void vertex() {\n" +
            "\t// model-space position -> place on the 3 x 4 grid (shoulders at y 1.2, hem at 0.12, 0.94 m across)\n" +
            "\tfloat u = clamp((VERTEX.x + 0.47) / 0.94, 0.0, 1.0) * 2.0;\n" +
            "\tfloat v = clamp((1.2 - VERTEX.y) / 1.08, 0.0, 1.0) * 3.0;\n" +
            "\tint c0 = int(min(floor(u), 1.0));\n" +
            "\tint r0 = int(min(floor(v), 2.0));\n" +
            "\tfloat fu = u - float(c0);\n" +
            "\tfloat fv = v - float(r0);\n" +
            "\tvec3 a = mix(offs[r0 * 3 + c0], offs[r0 * 3 + c0 + 1], fu);\n" +
            "\tvec3 b = mix(offs[(r0 + 1) * 3 + c0], offs[(r0 + 1) * 3 + c0 + 1], fu);\n" +
            "\tVERTEX += mix(a, b, fv);\n" +
            "}\n" +
            "void fragment() {\n" +
            "\tvec4 t = texture(albedo_tex, UV) * albedo;\n" +
            "\tALBEDO = t.rgb;\n" +
            "\tROUGHNESS = roughness;\n" +
            "}\n";
        public static Shader _cape_shader = null;
        public static long cape_usec = 0;           // time spent in cloth this session (diag/tests)
        public static int cape_active = 0;

        public void _CapeSetup(GDict a)
        {
            a["cape"] = Var.Nil;
            Node3D body = a["body"].As<Node3D>();
            MeshInstance3D orig = null;
            foreach (var c in body.FindChildren("*_Cape", "MeshInstance3D", true, false))
            {
                orig = c as MeshInstance3D;
                break;
            }
            Skeleton3D skel = body.FindChild("Skeleton3D", true, false) as Skeleton3D;
            if (orig == null || skel == null || skel.FindBone("chest") < 0)
                return;
            if (_cape_shader == null)
            {
                _cape_shader = new Shader();
                _cape_shader.Code = CAPE_SHADER;
            }
            var sm = new ShaderMaterial();
            sm.Shader = _cape_shader;
            var src = orig.GetActiveMaterial(0);
            if (src is BaseMaterial3D)
            {
                sm.SetShaderParameter("albedo_tex", (src as BaseMaterial3D).AlbedoTexture);
                sm.SetShaderParameter("albedo", (src as BaseMaterial3D).AlbedoColor);
                sm.SetShaderParameter("roughness", (src as BaseMaterial3D).Roughness);
            }
            var zero = new Vector3[CAPE_COLS * CAPE_ROWS];
            sm.SetShaderParameter("offs", zero);
            orig.MaterialOverride = sm;
            var rest = new List<Vector3>();
            for (int r = 0; r < CAPE_ROWS; r++)
            {
                var fv = (double)r / (double)(CAPE_ROWS - 1);
                for (int c2 = 0; c2 < CAPE_COLS; c2++)
                {
                    var fu = (double)c2 / (double)(CAPE_COLS - 1);
                    var half = GD.Lerpf(0.40, 0.47, fv);
                    rest.Add(new Vector3(GD.Lerpf(-half, half, fu), GD.Lerpf(1.2, 0.12, fv), GD.Lerpf(-0.08, -0.36, fv)));
                }
            }
            var chest = skel.FindBone("chest");
            a["cape"] = GDict.Of("skel", skel, "chest", chest, "b0i", skel.GetBoneGlobalRest(chest).AffineInverse(), "rest", Var.Of(rest.ToArray()),
                "pos", Var.Of(new Vector3[0]), "prev", Var.Of(new Vector3[0]), "shown", Var.Of((Vector3[])zero.Clone()), "mat", Var.Of(sm), "on", false, "acc", 0.0);
        }

        public void _CapeStep(GDict a, double dt)
        {
            var t0 = Time.GetTicksUsec();
            _CapeStepInner(a, dt);
            cape_usec += Time.GetTicksUsec() - t0;
        }

        public void _CapeStepInner(GDict a, double dt)
        {
            GDict cp = a["cape"].D;
            Skeleton3D skel = cp["skel"].As<Skeleton3D>();
            if (!GD.IsInstanceValid(skel))
            {
                a["cape"] = Var.Nil;
                return;
            }
            Vector3 ap = a["root"].As<Node3D>().GlobalPosition;
            Vector3 cpos = GD.IsInstanceValid(camera) ? camera.GlobalPosition : ap;
            var near = new Vector2(ap.x - cpos.x, ap.z - cpos.z).Length() < CAPE_NEAR && skel.IsVisibleInTree();
            var n = CAPE_COLS * CAPE_ROWS;
            if (!near)
            {
                if ((bool)cp["on"])                                  // back to the plain cape
                {
                    cp["on"] = false;
                    var z = new Vector3[n];
                    cp["shown"] = Var.Of(z);
                    cp["mat"].As<ShaderMaterial>().SetShaderParameter("offs", z);
                }
                return;
            }
            Transform3D model = skel.GlobalTransform;
            Transform3D rig_m = skel.GetBoneGlobalPose((int)cp["chest"]) * (Transform3D)cp["b0i"];   // model space, rigid on the chest
            Transform3D rig = model * rig_m;
            Vector3[] rest = cp["rest"].As<Vector3[]>();
            Vector3[] pos = cp["pos"].As<Vector3[]>();
            Vector3[] prev = cp["prev"].As<Vector3[]>();
            if (!(bool)cp["on"] || pos.Length != n)
            {
                Array.Resize(ref pos, n);
                Array.Resize(ref prev, n);
                for (int i = 0; i < n; i++)
                {
                    pos[i] = rig * rest[i];
                    prev[i] = pos[i];
                }
                cp["on"] = true;
                cp["acc"] = 0.0;
            }
            // fixed 30 Hz steps (frame times vary on phones; a variable step made it shiver)
            cp["acc"] = GD.Minf((double)cp["acc"] + dt, CAPE_STEP * 3.0);
            var h2 = CAPE_STEP * CAPE_STEP;
            var inv = rig.AffineInverse();
            var ground = ap.y + 0.03;
            var wind = new Vector3(Math.Sin(_time * 1.3 + (double)((int)cp["chest"] + rest.Length)) * 0.8, 0.0, Math.Cos(_time * 0.9) * 0.5);
            while ((double)cp["acc"] >= CAPE_STEP)
            {
                cp["acc"] = (double)cp["acc"] - CAPE_STEP;
                for (int i = 0; i < n; i++)
                {
                    if (i < CAPE_COLS)
                    {
                        prev[i] = pos[i];
                        pos[i] = rig * rest[i];                         // pinned across the shoulders
                        continue;
                    }
                    Vector3 p = pos[i];
                    Vector3 v = (p - prev[i]) * CAPE_DAMP;
                    prev[i] = p;
                    pos[i] = p + v + (new Vector3(0.0, -CAPE_GRAVITY, 0.0) + wind) * h2;
                }
                for (int it = 0; it < CAPE_ITERS; it++)
                {
                    for (int r = 0; r < CAPE_ROWS; r++)
                    {
                        for (int c = 0; c < CAPE_COLS; c++)
                        {
                            var i = r * CAPE_COLS + c;
                            if (c + 1 < CAPE_COLS)
                                _CapeLink(pos, rest, i, i + 1, r == 0);
                            if (r + 1 < CAPE_ROWS)
                                _CapeLink(pos, rest, i, i + CAPE_COLS, r == 0);
                            if (r + 2 < CAPE_ROWS)
                                _CapeLink(pos, rest, i, i + 2 * CAPE_COLS, r == 0);
                        }
                    }
                    for (int i = CAPE_COLS; i < n; i++)
                    {
                        Vector3 m = inv * pos[i];
                        var moved = false;
                        if (m.z > -0.07)
                        {
                            m.z = -0.07f;
                            moved = true;
                        }
                        var rxz = new Vector2(m.x, m.z);
                        if (m.y > 0.05 && m.y < 1.3 && rxz.Length() < 0.3)
                        {
                            rxz = rxz.Length() > 0.001 ? rxz.Normalized() * 0.3 : new Vector2(0.0, -0.3);
                            m.x = rxz.x;
                            m.z = rxz.y;
                            moved = true;
                        }
                        if (moved)
                            pos[i] = rig * m;
                        if (pos[i].y < ground)
                            pos[i].y = (float)ground;
                    }
                }
            }
            cp["pos"] = Var.Of(pos);
            cp["prev"] = Var.Of(prev);
            // the bend each point makes, in the cape's model space, eased onto the screen
            var inv_model = model.AffineInverse();
            Vector3[] shown = cp["shown"].As<Vector3[]>();
            var k = 1.0 - Math.Exp(-dt * 30.0);
            for (int i = 0; i < n; i++)
            {
                Vector3 off = inv_model * pos[i] - rig_m * rest[i];
                shown[i] = shown[i].Lerp(off, k);
            }
            cp["shown"] = Var.Of(shown);
            cp["mat"].As<ShaderMaterial>().SetShaderParameter("offs", shown);
            cape_active += 1;
        }

        public void _CapeLink(Vector3[] pos, Vector3[] rest, int i, int j, bool pin_i)
        {
            Vector3 d = pos[j] - pos[i];
            var l = d.Length();
            if (l < 0.0001)
                return;
            double want = rest[i].DistanceTo(rest[j]);
            var corr = d * ((l - want) / l);
            if (pin_i)
                pos[j] -= corr;                                     // the shoulder end doesn't move
            else
            {
                pos[i] += corr * 0.5;
                pos[j] -= corr * 0.5;
            }
        }


        public void _BlastBodies(Vector2 at2, double radius, double speed)
        {
            // 0.31.21: the dead and the loose weapons lying round a blast are thrown by it
            var at = new Vector3(at2.x, Sim.HeightAt(at2), at2.y);
            foreach (var a in _ragdolls)
            {
                var rg = a.D.Get("rag");
                if (rg.IsNull || !GD.IsInstanceValid(rg["sim"]))
                    continue;
                foreach (var pb in rg["sim"].As<Node>().GetChildren())
                {
                    if (!(pb is PhysicalBone3D))
                        continue;
                    Vector3 d = (pb as Node3D).GlobalPosition - at;
                    var dist = new Vector2(d.x, d.z).Length();
                    if (dist > radius)
                        continue;
                    var dir = dist > 0.05 ? new Vector3(d.x, 0.0, d.z).NormalizedChecked() : new Vector3(GD.RandfRange(-1, 1), 0.0, GD.RandfRange(-1, 1)).NormalizedChecked();
                    var f = speed * (1.0 - 0.6 * dist / radius);
                    (pb as PhysicalBone3D).LinearVelocity += dir * f + new Vector3(0.0, f * 0.7, 0.0);
                    (pb as PhysicalBone3D).AngularVelocity += new Vector3(GD.RandfRange(-1, 1), GD.RandfRange(-1, 1), GD.RandfRange(-1, 1)) * f;
                }
            }
            foreach (var db in _debris)
            {
                var rb = db["node"];
                if (!GD.IsInstanceValid(rb))
                    continue;
                Vector3 d2 = rb.As<Node3D>().GlobalPosition - at;
                var dist2 = new Vector2(d2.x, d2.z).Length();
                if (dist2 > radius)
                    continue;
                var dir2 = dist2 > 0.05 ? new Vector3(d2.x, 0.0, d2.z).NormalizedChecked() : new Vector3(GD.RandfRange(-1, 1), 0.0, GD.RandfRange(-1, 1)).NormalizedChecked();
                var f2 = speed * 1.2 * (1.0 - 0.6 * dist2 / radius);
                rb.As<RigidBody3D>().Sleeping = false;
                rb.As<RigidBody3D>().LinearVelocity += dir2 * f2 + new Vector3(0.0, f2 * 0.8, 0.0);
                rb.As<RigidBody3D>().AngularVelocity += new Vector3(GD.RandfRange(-8, 8), GD.RandfRange(-8, 8), GD.RandfRange(-8, 8));
            }
        }

        public bool _kick_skip = false;

        public void _KickDebris()
        {
            // loose weapons are kicked along by whoever walks into them
            if (_debris.IsEmpty())
                return;
            _kick_skip = !_kick_skip;
            if (_kick_skip && Engine.GetFramesPerSecond() > 40)
                return;                                     // (0.31.219: every other frame at 60 fps -- each walker against each weapon)
            // (0.31.160: each actor's place once a frame -- it was looked up for every weapon on the ground, for every actor)
            // (0.31.220: the walkers in 2 m cells -- each weapon looks only at those in the cells round it, not at all ~70)
            var cells = new GDict();
            foreach (var a in actors.Values())
            {
                if (!((bool)a.D.Get("dead", false) || !a.D.Get("rag").IsNull) && a["root"].As<Node3D>().Visible)
                {
                    Vector3 ap0 = a["root"].As<Node3D>().Position;
                    var ck = new Vector2i(GD.Floori(ap0.x / 2.0), GD.Floori(ap0.z / 2.0));
                    if (!cells.Has(ck))
                        cells[ck] = new GArray();
                    cells[ck].A.Append(a);
                }
            }
            foreach (var db in _debris)
            {
                var rb = db["node"];
                if (!GD.IsInstanceValid(rb))
                    continue;
                Vector3 wp = rb.As<Node3D>().Position;         // (both the view's children: its own space)
                var walkers = new GArray();
                var wc = new Vector2i(GD.Floori(wp.x / 2.0), GD.Floori(wp.z / 2.0));
                for (int dx = 0; dx < 3; dx++)
                {
                    for (int dz = 0; dz < 3; dz++)
                    {
                        var lst = cells.Get(new Vector2i(wc.x + dx - 1, wc.y + dz - 1));
                        if (!lst.IsNull)
                            walkers.AppendArray(lst.A);
                    }
                }
                foreach (var a in walkers)
                {
                    Vector3 ap = a["root"].As<Node3D>().Position;
                    var d = new Vector2(wp.x - ap.x, wp.z - ap.z);
                    if (d.Length() > 0.62 || Math.Abs(wp.y - ap.y) > 1.2)
                        continue;
                    Vector3 lp = a.D.Get("kick_last", ap).AsVec3();
                    var mv = new Vector2(ap.x - lp.x, ap.z - lp.z);
                    if (mv.Length() < 0.004)
                        continue;
                    var dir = (d.Normalized() * 0.5 + mv.Normalized() * 0.5).Normalized();
                    rb.As<RigidBody3D>().Sleeping = false;
                    rb.As<RigidBody3D>().LinearVelocity = new Vector3(dir.x * 3.2, 1.0, dir.y * 3.2);
                    rb.As<RigidBody3D>().AngularVelocity += new Vector3(GD.RandfRange(-4, 4), GD.RandfRange(-4, 4), GD.RandfRange(-4, 4));
                }
            }
            foreach (var a in actors.Values())
                a.D["kick_last"] = a["root"].As<Node3D>().Position;
        }

        // ---------- the EffectBlocks explosions (0.31.57, Kevin) ----------
        // The pack's heavy explosion (fireball, sparks, rolling smoke, burning debris with smoke trails) on the bomb and the
        // meteor, its light one (a small pop, sparks, puffs) on catapult stones. Copies in assets/vfx/effectblocks without the
        // pack's demo script and sound. Every emitter is switched to local coordinates so the node's scale sizes the whole
        // effect; half the particles on low effects; freed when the longest emitter is done.
        public static ParticleProcessMaterial _fire_cool = null;
        public static readonly GDict PACK_EXPLOSIONS = GDict.Of("heavy", Var.Of(ResourceLoader.Load<PackedScene>("res://assets/vfx/effectblocks/explosion_heavy.tscn")),
            "light", Var.Of(ResourceLoader.Load<PackedScene>("res://assets/vfx/effectblocks/explosion_light.tscn")));

        public void _PackExplosion(string kind, Vector3 at, double size, bool own_smoke = false)
        {
            Node3D n = PACK_EXPLOSIONS[kind].As<PackedScene>().Instantiate() as Node3D;
            if (own_smoke && n.HasNode("Smoke"))
                n.GetNode("Smoke").Free();                    // 0.31.59: our physical smoke replaces the pack's smoke
            if (own_smoke && n.HasNode("Fire"))
            {
                // the pack's fireball cools to an opaque near-black ball; ours cools to a thin grey and fades, handing over to
                // the smoke cloud
                var fire = n.GetNode("Fire") as GPUParticles3D;
                if (_fire_cool == null)
                {
                    _fire_cool = (fire.ProcessMaterial as ParticleProcessMaterial).Duplicate() as ParticleProcessMaterial;
                    var g = new Gradient();
                    g.SetOffsets(new double[] { 0.0, 0.16, 0.3, 0.55 });                    // (g.offsets = ...: the property's setter)
                    g.SetColors(new[] { new Color(0.95, 0.5, 0.0, 1.0), new Color(0.85, 0.27, 0.04, 1.0), new Color(0.3, 0.26, 0.23, 0.5), new Color(0.34, 0.33, 0.32, 0.0) });
                    var gt = new GradientTexture1D();
                    gt.Gradient = g;
                    _fire_cool.ColorRamp = gt;
                }
                fire.ProcessMaterial = _fire_cool;
            }
            n.Position = at;
            n.Scale = Vector3.ONE * size;
            AddChild(n);
            var life = 0.5;
            foreach (var gp in n.FindChildren("*", "GPUParticles3D", true, false))
            {
                var p3 = gp as GPUParticles3D;
                p3.LocalCoords = true;
                if (low_fx)
                    p3.AmountRatio = 0.5;
                life = GD.Maxf(life, p3.Lifetime * 1.6);
                p3.Restart();
            }
            GetTree().CreateTimer(life + 0.5).Timeout += n.QueueFree;
        }

        // ---------- physical smoke (0.31.59, Kevin: realistic, physics-based smoke that lingers after explosions) ----------
        // A one-shot GPU particle cloud per blast: puffs (a generated, lumpy smoke texture) are thrown out of a sphere at the
        // blast, slowed hard by air drag (damping), lifted by buoyancy and pushed by a steady breeze (both as gravity), and
        // stirred by a turbulence noise field so the cloud boils and curls instead of moving in straight lines. Each puff swells
        // as it rises, turns slowly, starts dark and fire-warm, then thins to a pale grey and fades -- the cloud lingers for
        // 8-10 s. Depth-sorted, soft where it meets the ground (proximity fade), no shadows; 40 % of the puffs on low effects.
        public static readonly Texture2D SMOKE_TEX = ResourceLoader.Load<Texture2D>("res://assets/vfx/smoke/smoke_puff.png");
        public static readonly Vector3 SMOKE_WIND = new Vector3(0.45, 0.0, 0.18);
        public static StandardMaterial3D _smoke_draw = null;

        public static StandardMaterial3D _SmokeDrawMat()
        {
            if (_smoke_draw == null)
            {
                var m = new StandardMaterial3D();
                m.BillboardMode = BaseMaterial3D.BILLBOARD_PARTICLES;
                m.BillboardKeepScale = true;
                m.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
                m.ShadingMode = BaseMaterial3D.SHADING_MODE_UNSHADED;
                m.VertexColorUseAsAlbedo = true;
                m.AlbedoTexture = SMOKE_TEX;
                m.ProximityFadeEnabled = true;
                m.ProximityFadeDistance = 1.4;
                m.CullMode = BaseMaterial3D.CULL_DISABLED;
                _smoke_draw = m;
            }
            return _smoke_draw;
        }

        public void SmokeCloud(Vector3 at, double size, int amount, double life)
        {
            var pm = new ParticleProcessMaterial();
            pm.EmissionShape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE;
            pm.EmissionSphereRadius = 1.1 * size;
            pm.Direction = new Vector3(0, 1, 0);
            pm.Spread = 80.0;
            pm.InitialVelocityMin = 2.6 * size;
            pm.InitialVelocityMax = 6.5 * size;
            pm.DampingMin = 2.4 * size;                       // air drag: the blast's push dies within a second or so
            pm.DampingMax = 3.6 * size;
            pm.Gravity = new Vector3(0.0, 0.55, 0.0) + SMOKE_WIND;  // buoyancy up, the breeze sideways
            pm.TurbulenceEnabled = true;
            pm.TurbulenceNoiseStrength = 1.8;
            pm.TurbulenceNoiseScale = 3.2 * size;
            pm.TurbulenceNoiseSpeed = new Vector3(0.15, 0.3, 0.1);
            pm.TurbulenceNoiseSpeedRandom = 0.3;
            pm.TurbulenceInfluenceMin = 0.05;
            pm.TurbulenceInfluenceMax = 0.16;
            pm.LifetimeRandomness = 0.35;
            pm.AngleMin = -180.0;
            pm.AngleMax = 180.0;
            pm.AngularVelocityMin = -14.0;
            pm.AngularVelocityMax = 14.0;
            pm.ScaleMin = 2.0 * size;
            pm.ScaleMax = 3.4 * size;
            var sc = new Curve();
            sc.AddPoint(new Vector2(0.0, 0.35));
            sc.AddPoint(new Vector2(0.2, 0.85));
            sc.AddPoint(new Vector2(1.0, 1.45));
            var sct = new CurveTexture();
            sct.Curve = sc;
            pm.ScaleCurve = sct;
            var g = new Gradient();
            g.SetOffsets(new double[] { 0.0, 0.04, 0.12, 0.45, 1.0 });                    // (g.offsets = ...: the property's setter)
            g.SetColors(new[] { new Color(0.55, 0.32, 0.16, 0.0), new Color(0.42, 0.28, 0.2, 0.92), new Color(0.24, 0.23, 0.22, 0.9),
                new Color(0.42, 0.41, 0.4, 0.62), new Color(0.62, 0.62, 0.62, 0.0) });
            var gt = new GradientTexture1D();
            gt.Gradient = g;
            pm.ColorRamp = gt;
            var gi = new Gradient();                          // each puff a little lighter or darker than the next
            gi.SetColors(new[] { new Color(0.82, 0.82, 0.82), new Color(1.12, 1.1, 1.08) });
            var git = new GradientTexture1D();
            git.Gradient = gi;
            pm.ColorInitialRamp = git;
            var p = new GPUParticles3D();
            p.ProcessMaterial = pm;
            var q = new QuadMesh();
            q.Size = Vector2.ONE;
            q.Material = _SmokeDrawMat();
            p.DrawPass1 = q;
            p.Amount = amount;
            p.Lifetime = life;
            p.OneShot = true;
            p.Explosiveness = 0.85;
            p.Randomness = 0.4;
            p.FixedFps = 30;
            p.Interpolate = true;
            p.DrawOrder = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH;
            p.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            p.VisibilityAabb = new AABB(new Vector3(-22, -4, -22) * size, new Vector3(44, 34, 44) * size);
            if (low_fx)
                p.AmountRatio = 0.4;
            p.Position = at;
            AddChild(p);
            p.Restart();
            GetTree().CreateTimer(life * 1.4 + 1.0).Timeout += p.QueueFree;
        }

        // ---------- shockwave (0.31.56, Kevin: the EffectBlocks pack's shockwave on the bomb and meteor blasts) ----------
        // The pack's effect (assets/other/shockwave.tscn): one torus, inner 0.8 / outer 1.0, triangular section, growing from
        // nothing to its full size over 0.74 s on an ease-in curve, drawn with its screen-distortion shader (in
        // assets/vfx/effectblocks/shockwave.gdshader, adapted to bend round the ring's own centre; distortion 0.1, noise 0.273
        // as in its material). Here it's a plain
        // MeshInstance3D animated in _sync_shocks (one particle never needed a particle system), sized to each blast, and
        // skipped on low effects (the screen copy it reads costs a little on phones).
        public static readonly Shader SHOCK_SHADER = ResourceLoader.Load<Shader>("res://assets/vfx/effectblocks/shockwave.gdshader");
        public const double SHOCK_LIFE = 0.74;
        public static ShaderMaterial _shock_mat = null;
        public static TorusMesh _shock_mesh = null;
        public GArray _shocks = new GArray();

        public void Shockwave(Vector3 at, double radius, double delay = 0.0)
        {
            if (low_fx)
                return;
            if (_shock_mat == null)
            {
                _shock_mat = new ShaderMaterial();
                _shock_mat.Shader = SHOCK_SHADER;
                _shock_mat.SetShaderParameter("distortion_intensity", 0.1);
                _shock_mat.SetShaderParameter("noise_influence", 0.273);
                _shock_mesh = new TorusMesh();
                _shock_mesh.InnerRadius = 0.8;
                _shock_mesh.OuterRadius = 1.0;
                _shock_mesh.Rings = 40;
                _shock_mesh.RingSegments = 3;
            }
            var mi = new MeshInstance3D();
            mi.Mesh = _shock_mesh;
            mi.MaterialOverride = _shock_mat;
            mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            mi.Position = at;
            mi.Scale = Vector3.ONE * 0.001;
            mi.Visible = false;
            AddChild(mi);
            _shocks.Append(GDict.Of("node", mi, "t0", _time + delay, "r", radius));
        }

        public void _SyncShocks()
        {
            for (int i = _shocks.Size() - 1; i > -1; i--)
            {
                GDict sh = _shocks[i].D;
                MeshInstance3D mi = sh["node"].As<MeshInstance3D>();
                double t = (_time - (double)sh["t0"]) / SHOCK_LIFE;
                if (t >= 1.0 || !GD.IsInstanceValid(mi))
                {
                    if (GD.IsInstanceValid(mi))
                        mi.QueueFree();
                    _shocks.RemoveAt(i);
                    continue;
                }
                if (t < 0.0)
                    continue;
                mi.Visible = true;
                // the pack's scale curve: (0,0) leaving at slope 0.227, (1,1) arriving at 1.392 -- a cubic Hermite
                var c = (2.0 * t * t * t - 3.0 * t * t + 1.0) * 0.0 + (t * t * t - 2.0 * t * t + t) * 0.227 + (-2.0 * t * t * t + 3.0 * t * t) * 1.0 + (t * t * t - t * t) * 1.392;
                mi.Scale = Vector3.ONE * GD.Maxf(0.001, (double)sh["r"] * c);
                mi.SetInstanceShaderParameter("fade", 1.0 - t * t);
            }
        }

        // ---------- ragdolls and dropped weapons (0.31.20, Kevin: "ragdoll physics so when they die they fall to the ground
        // in a way that they were killed"; "when a player dies their weapons fall on the ground too") ----------
        // A death near the camera turns the body into a ragdoll: 11 physics bodies on the KayKit skeleton (hips, chest, head,
        // upper and lower arms and legs) joined by cones (hips, shoulders, neck) and hinges (elbows, knees), thrown with the
        // killing blow's push from the sim (a sword: back from the killer; an arrow or hammer: the way it flew; a bomb or a
        // catapult stone: up and away from the blast) and tumbling. The ground under it is a small height-field patch sampled
        // from the land (castle floors included). The weapons in his hands come loose as rigid bodies thrown the same way.
        // All of it is freed when he respawns; at most RAG_MAX at once (the oldest is let go).
        public const int RAG_MAX = 8;
        public const double RAG_NEAR = 40.0;
        public static readonly (string, string, double, int, double)[] RAG_SPEC =
        {
            // bone, child bone (for its length), radius, joint (0 none, 1 cone, 2 hinge), mass
            ("hips", "spine", 0.24, 0, 3.0), ("chest", "head", 0.27, 1, 3.0), ("head", "", 0.4, 1, 2.0),
            ("upperarm.l", "lowerarm.l", 0.08, 1, 0.6), ("lowerarm.l", "wrist.l", 0.07, 2, 0.5),
            ("upperarm.r", "lowerarm.r", 0.08, 1, 0.6), ("lowerarm.r", "wrist.r", 0.07, 2, 0.5),
            ("upperleg.l", "lowerleg.l", 0.1, 1, 0.9), ("lowerleg.l", "foot.l", 0.09, 2, 0.7),
            ("upperleg.r", "lowerleg.r", 0.1, 1, 0.9), ("lowerleg.r", "foot.r", 0.09, 2, 0.7),
        };
        public GArray _ragdolls = new GArray();
        public GArray _debris = new GArray();

        public GDict _patch_h = new GDict();                       // 0.31.160: the land's height at whole metres, for the ragdolls' ground patches

        public StaticBody3D _GroundPatch(Vector3 c, int half = 7)
        {
            // 0.31.160: sampled at the whole metres the patch sits on (it was offset by the death spot's fractions: up to half a
            // metre off) and remembered -- a patch is 169 or 441 Sim.height_at, ~6 us each here and several times that on the
            // phone, for every death in view; a wave's deaths keep landing on the same few metres of lane
            var hm = new HeightMapShape3D();
            var w = half * 2 + 1;
            hm.MapWidth = w;
            hm.MapDepth = w;
            var data = new float[w * w];
            var cx = (int)Math.Round(c.x, MidpointRounding.AwayFromZero);
            var cz = (int)Math.Round(c.z, MidpointRounding.AwayFromZero);
            if (_patch_h.Size() > 40000)
                _patch_h.Clear();
            for (int zi = 0; zi < w; zi++)
            {
                for (int xi = 0; xi < w; xi++)
                {
                    var k = new Vector2i(cx + xi - half, cz + zi - half);
                    var h = _patch_h.Get(k);
                    if (h.IsNull)
                    {
                        h = Sim.HeightAt(new Vector2(k.x, k.y));
                        _patch_h[k] = h;
                    }
                    data[zi * w + xi] = (float)(double)h;
                }
            }
            hm.MapData = data;
            var sb = new StaticBody3D();
            var cs = new CollisionShape3D();
            cs.Shape = hm;
            sb.AddChild(cs);
            sb.Position = new Vector3((double)cx, 0.0, (double)cz);
            sb.PhysicsMaterialOverride = new PhysicsMaterial();
            sb.PhysicsMaterialOverride.Friction = 0.9;
            AddChild(sb);
            return sb;
        }

        public void _Ragdoll(GDict a, Vector3 push)
        {
            if (!a.Get("rag").IsNull || a.Get("body").IsNull)
                return;
            Node3D root = a["root"].As<Node3D>();
            if (GD.IsInstanceValid(camera) && new Vector2(root.GlobalPosition.x - camera.GlobalPosition.x, root.GlobalPosition.z - camera.GlobalPosition.z).Length() > RAG_NEAR)
                return;
            Skeleton3D skel = a["body"].As<Node3D>().FindChild("Skeleton3D", true, false) as Skeleton3D;
            if (skel == null)
                return;
            while (_ragdolls.Size() >= RAG_MAX)
                _RagdollEnd(_ragdolls[0].D);
            var sim3 = new PhysicalBoneSimulator3D();
            skel.AddChild(sim3);
            var bones = new List<PhysicalBone3D>();
            foreach (var sp in RAG_SPEC)
            {
                var bi = skel.FindBone(GD.Str(sp.Item1));
                if (bi < 0)
                    continue;
                var length = 0.6;
                var dir = Vector3.UP;
                if (GD.Str(sp.Item2) != "")
                {
                    var ci = skel.FindBone(GD.Str(sp.Item2));
                    if (ci >= 0)
                    {
                        Vector3 co = skel.GetBoneRest(ci).origin;
                        length = GD.Maxf(co.Length(), 0.05);
                        dir = co / length;
                    }
                }
                var pb = new PhysicalBone3D();
                pb.BoneName = GD.Str(sp.Item1);
                double r = sp.Item3;
                var basis = dir.DistanceTo(Vector3.UP) > 0.001 ? new Basis(new Quaternion(Vector3.UP, dir)) : Basis.IDENTITY;
                var reach = GD.Str(sp.Item1) != "head" ? length * 0.5 : 0.42;
                pb.BodyOffset = new Transform3D(basis, dir * reach);
                pb.JointOffset = new Transform3D(Basis.IDENTITY, new Vector3(0.0, -reach, 0.0));
                var cs = new CollisionShape3D();
                if (GD.Str(sp.Item1) == "head")
                {
                    var sph = new SphereShape3D();
                    sph.Radius = r;
                    cs.Shape = sph;
                }
                else
                {
                    var cap = new CapsuleShape3D();
                    cap.Radius = r;
                    cap.Height = GD.Maxf(length, r * 2.0 + 0.02);
                    cs.Shape = cap;
                }
                pb.AddChild(cs);
                pb.Mass = sp.Item5;
                pb.Friction = 0.85;
                pb.Bounce = 0.05;
                pb.LinearDamp = 0.6;
                pb.AngularDamp = 1.6;
                switch (sp.Item4)
                {
                    case 1:
                        pb.JointType = PhysicalBone3D.JOINT_TYPE_CONE;
                        break;
                    case 2:
                        pb.JointType = PhysicalBone3D.JOINT_TYPE_HINGE;
                        break;
                    default:
                        pb.JointType = PhysicalBone3D.JOINT_TYPE_NONE;
                        break;
                }
                sim3.AddChild(pb);
                if (sp.Item4 == 1)
                {
                    pb.Set("joint_constraints/swing_span", 50.0);
                    pb.Set("joint_constraints/twist_span", 25.0);
                }
                else if (sp.Item4 == 2)
                {
                    pb.Set("joint_constraints/angular_limit_enabled", true);
                    pb.Set("joint_constraints/angular_limit_upper", 0.0);
                    pb.Set("joint_constraints/angular_limit_lower", -110.0);
                }
                bones.Add(pb);
            }
            if (bones.Count == 0)
            {
                sim3.QueueFree();
                return;
            }
            var ground = _GroundPatch(root.GlobalPosition, 10);       // room for the throw (a bomb carries them ~4 m)
            if (!a.Get("player").IsNull)
                a["player"].As<AnimationPlayer>().Pause();
            sim3.PhysicalBonesStartSimulation();
            var spin = push.Length() * 0.9;
            foreach (var pb in bones)
            {
                pb.LinearVelocity = push + new Vector3(GD.RandfRange(-0.4, 0.4), GD.RandfRange(0.0, 0.3), GD.RandfRange(-0.4, 0.4));
                pb.AngularVelocity = new Vector3(GD.RandfRange(-1, 1), GD.RandfRange(-1, 1), GD.RandfRange(-1, 1)) * spin;
            }
            a["ring"].As<MeshInstance3D>().Visible = false;
            a["rag"] = GDict.Of("sim", sim3, "ground", ground, "t0", _time);
            _ragdolls.Append(a);
        }

        public void _RagdollEnd(GDict a)
        {
            var rg = a.Get("rag");
            if (rg.IsNull)
                return;
            if (GD.IsInstanceValid(rg["sim"]))
            {
                rg["sim"].As<PhysicalBoneSimulator3D>().PhysicalBonesStopSimulation();
                rg["sim"].As<Node>().QueueFree();
            }
            if (GD.IsInstanceValid(rg["ground"]))
                rg["ground"].As<Node>().QueueFree();
            a["rag"] = Var.Nil;
            if (!a.Get("player").IsNull && GD.IsInstanceValid(a["player"]))
                a["player"].As<AnimationPlayer>().Play();
            _ragdolls.Erase(a);
        }

        public void _DropWeapons(GDict a, Vector3 push)
        {
            // whatever he held comes loose: each weapon or shield becomes a tumbling rigid body thrown with him
            if (a.Get("body").IsNull)
                return;
            Node3D root = a["root"].As<Node3D>();
            if (GD.IsInstanceValid(camera) && new Vector2(root.GlobalPosition.x - camera.GlobalPosition.x, root.GlobalPosition.z - camera.GlobalPosition.z).Length() > RAG_NEAR)
                return;
            StaticBody3D ground = null;
            foreach (var slot in a["body"].As<Node3D>().FindChildren("*", "BoneAttachment3D", true, false))
            {
                if (!GD.Str((slot as BoneAttachment3D).BoneName).BeginsWith("handslot"))
                    continue;
                foreach (var w in (slot as Node3D).GetChildren())
                {
                    if (!(w is Node3D) || !(w as Node3D).Visible)
                        continue;
                    var aabb = _NodeAabb(w as Node3D);
                    if (aabb.size.Length() < 0.05)
                        continue;
                    if (ground == null)
                        ground = _GroundPatch(root.GlobalPosition, 6);
                    var rb = new RigidBody3D();
                    Transform3D gt = (w as Node3D).GlobalTransform;
                    var copy = (w as Node3D).Duplicate() as Node3D;
                    rb.AddChild(copy);
                    copy.Transform = new Transform3D(gt.basis, Vector3.ZERO);
                    var cs = new CollisionShape3D();
                    var bx = new BoxShape3D();
                    bx.Size = new Vector3(GD.Maxf(aabb.size.x, 0.08), GD.Maxf(aabb.size.y, 0.08), GD.Maxf(aabb.size.z, 0.08)) * gt.basis.GetScale();
                    cs.Shape = bx;
                    cs.Transform = new Transform3D(gt.basis.Orthonormalized(), gt.basis * aabb.GetCenter());
                    rb.AddChild(cs);
                    rb.Mass = 0.8;
                    rb.PhysicsMaterialOverride = new PhysicsMaterial();
                    rb.PhysicsMaterialOverride.Bounce = 0.2;
                    rb.PhysicsMaterialOverride.Friction = 0.7;
                    AddChild(rb);
                    rb.GlobalPosition = gt.origin;
                    rb.LinearVelocity = push * 1.1 + new Vector3(GD.RandfRange(-0.8, 0.8), 1.2 + GD.Randf(), GD.RandfRange(-0.8, 0.8));
                    rb.AngularVelocity = new Vector3(GD.RandfRange(-6, 6), GD.RandfRange(-6, 6), GD.RandfRange(-6, 6));
                    (w as Node3D).Visible = false;
                    _debris.Append(GDict.Of("node", rb, "ground", ground, "t0", _time, "id", GD.Str(a.Get("id", ""))));
                }
            }
            // loose weapons lie a while, then go (with their bit of ground)
            for (int i = _debris.Size() - 1; i > -1; i--)
            {
                if (_time - (double)_debris[i]["t0"] > 30.0 || _debris.Size() > 24)
                {
                    GDict d = _debris[i].D;
                    if (GD.IsInstanceValid(d["node"]))
                        d["node"].As<Node>().QueueFree();
                    if (GD.IsInstanceValid(d["ground"]) && _debris.Filter(x => x["ground"] == d["ground"]).Size() <= 1)
                        d["ground"].As<Node>().QueueFree();
                    _debris.RemoveAt(i);
                }
            }
        }

        public AABB _NodeAabb(Node3D n)
        {
            var box = new AABB();
            var first = true;
            var list = n.FindChildren("*", "MeshInstance3D", true, false);
            if (n is MeshInstance3D)
                list.Add(n);
            foreach (var m in list)
            {
                var mi = m as MeshInstance3D;
                if (mi.Mesh == null)
                    continue;
                var b = n.GlobalTransform.AffineInverse() * mi.GlobalTransform * mi.Mesh.GetAabb();
                box = first ? b : box.Merge(b);
                first = false;
            }
            return box;
        }


        // ---------- the upgrades' new abilities in the view (0.31.32) ----------
        public void _SyncVanish(GDict a, Unit u)
        {
            // an Assassin in Vanish: almost nothing for the enemy (8 % opaque), a ghost for his own side (45 %); ring hidden from
            // the enemy. Each mesh gets a see-through copy of its material while it lasts (GeometryInstance3D.transparency
            // didn't show on the phone renderer in the check render).
            bool v = sim.Vanished(u);
            double want = 0.0;
            if (v)
                want = u.team == (sim.by_id.TryGetValue(player_id, out var me0) ? me0.team : 0) ? 0.55 : 0.92;
            bool on = (bool)a.Get("vanish_on", false);
            if (v && !on)
            {
                a["vanish_on"] = true;
                foreach (var mi in a["body"].As<Node3D>().FindChildren("*", "MeshInstance3D", true, false))
                {
                    var m3 = mi as MeshInstance3D;
                    if (m3.Mesh == null)
                        continue;
                    for (int si = 0; si < m3.Mesh.GetSurfaceCount(); si++)
                    {
                        Material @base = m3.GetActiveMaterial(si);
                        if (@base is BaseMaterial3D)
                        {
                            var ghost = (@base as BaseMaterial3D).Duplicate() as BaseMaterial3D;
                            ghost.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
                            var gc = ghost.AlbedoColor;
                            gc.a = (float)(1.0 - want);
                            ghost.AlbedoColor = gc;
                            m3.SetMeta(GD.Fmt("vanish_prev_%d", si), m3.GetSurfaceOverrideMaterial(si));
                            m3.SetSurfaceOverrideMaterial(si, ghost);
                        }
                    }
                }
                if (want > 0.9)
                    a["ring"].As<MeshInstance3D>().Visible = false;
            }
            else if (!v && on)
            {
                a["vanish_on"] = false;
                foreach (var mi in a["body"].As<Node3D>().FindChildren("*", "MeshInstance3D", true, false))
                {
                    var m3 = mi as MeshInstance3D;
                    if (m3.Mesh == null)
                        continue;
                    for (int si = 0; si < m3.Mesh.GetSurfaceCount(); si++)
                    {
                        if (m3.HasMeta(GD.Fmt("vanish_prev_%d", si)))
                        {
                            m3.SetSurfaceOverrideMaterial(si, m3.GetMeta(GD.Fmt("vanish_prev_%d", si)) as Material);
                            m3.RemoveMeta(GD.Fmt("vanish_prev_%d", si));
                        }
                    }
                }
            }
            else if (v && want > 0.9)
                a["ring"].As<MeshInstance3D>().Visible = false;
        }

        public GArray _meteors_fx = new GArray();

        public void _MeteorWarn(Vector2 p2, double delay, int team)
        {
            var at = new Vector3(p2.x, Sim.HeightAt(p2), p2.y);
            var ring = _Decal(at + new Vector3(0.0, 0.05, 0.0), Sim.METEOR_R, new Color(1.0, 0.35, 0.15), 0.6);
            ring.Visible = false;                                        // (0.31.201: spell_fx.gd draws the warning, runes turning)
            var rock = new MeshInstance3D();
            var sm = new SphereMesh();
            sm.Radius = 0.9;
            sm.Height = 1.8;
            sm.RadialSegments = 10;
            sm.Rings = 6;
            rock.Mesh = sm;
            var mm = new StandardMaterial3D();
            mm.AlbedoColor = new Color(0.35, 0.18, 0.1);
            mm.EmissionEnabled = true;
            mm.Emission = new Color(1.0, 0.45, 0.12);
            mm.EmissionEnergyMultiplier = 2.5;
            rock.MaterialOverride = mm;
            var from = at + new Vector3(7.0, 28.0, 5.0);
            rock.Position = from;
            AddChild(rock);
            fxs.MeteorTrail(rock);                                      // 0.31.201: fire and smoke streaming off it
            _meteors_fx.Append(GDict.Of("ring", ring, "rock", rock, "from", from, "to", at, "t0", _time, "dur", delay));
        }

        public void _MeteorHit(Vector2 p2, double burn)
        {
            var at = new Vector3(p2.x, Sim.HeightAt(p2) + 0.4, p2.y);
            Shockwave(at, Sim.METEOR_R + 1.2);                                          // 0.31.56
            _PackExplosion("heavy", new Vector3(at.x, at.y - 0.2, at.z), 3.4, true);      // 0.31.57 (0.31.58: a bit larger)
            SmokeCloud(at, 1.05, 34, 7.5);                                         // 0.31.59
            RingAt(at, new Color(1.0, 0.5, 0.15), Sim.METEOR_R * 1.3, 0.6);
            Shake(0.5);
            _BlastBodies(p2, Sim.METEOR_R + 1.5, 5.0);
            WaterBlast(p2, 0.7);
            _meteors_fx.Append(GDict.Of("burn_at", at, "until", _time + burn));
        }

        public void _SyncMeteorFx(double dt)
        {
            for (int i = _meteors_fx.Size() - 1; i > -1; i--)
            {
                GDict m = _meteors_fx[i].D;
                if (m.Has("rock"))
                {
                    var k = GD.Clampf((_time - (double)m["t0"]) / GD.Maxf((double)m["dur"], 0.01), 0.0, 1.0);
                    if (GD.IsInstanceValid(m["rock"]))
                        m["rock"].As<Node3D>().Position = m["from"].AsVec3().Lerp(m["to"].AsVec3(), k * k);
                    if (GD.IsInstanceValid(m["ring"]))
                        m["ring"].As<Node3D>().Scale = new Vector3(1.0, 0.15, 1.0) * (0.8 + 0.2 * Math.Sin(_time * 18.0));
                    if (k >= 1.0)
                    {
                        if (GD.IsInstanceValid(m["rock"]))
                            m["rock"].As<Node>().QueueFree();
                        if (GD.IsInstanceValid(m["ring"]))
                            m["ring"].As<Node>().QueueFree();
                        _meteors_fx.RemoveAt(i);
                    }
                }
                else
                {
                    if (_time >= (double)m["until"])
                    {
                        _meteors_fx.RemoveAt(i);
                        continue;
                    }
                    // (0.31.201: the burning ground is spell_fx.gd's fire disc)
                }
            }
        }


        public GArray _recent_blasts = new GArray();        // [pos, time]: items appearing next to one pop higher
    }
}
