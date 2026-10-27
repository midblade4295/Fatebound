// Ported from godot/scripts/siege/siege_view.gd (Fatebound 0.31.222): the 5v5 -- towers (breaking in stages), the fog of
// war, brush, ground marks, wards, ultimates / the jungle / gold, W and E, the Grave Wyrm's soul-fire, tower shots,
// _animate, on_event, the Kings.
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
    using Land = Fatebound.Sim.Land;
    using Keep = Fatebound.Sim.Keep;
    using Sim = Fatebound.Sim.SiegeSim;

    public partial class SiegeView
    {
        // ---------- 5V5 (0.31.155, scripts/siege/moba.gd) ----------
        // The lane towers, their range on the ground when you're near an enemy one (red when it's aiming at you), their shots
        // (a fireball from the brazier that homes in on its target). 0.31.172 (Kevin: "new tower models ... I want them to
        // visually break as their health gets lower"): the Meshy towers of towers.gd -- the lane tower (a little bigger each
        // tier) and the King tower -- breaking in stages as they're hurt: cracks spreading, pieces breaking off and tumbling
        // down (_tower_stage, _sync_falling), the brazier going out, smoke and then fire from the broken top; when one falls,
        // all but its foot comes down in a burst of rubble. (Was KayKit hex towers in the side's colour; a stump once fallen.)
        public const double MINION_SCALE = 0.78;
        public static readonly double[] TOWER_SMOKE_H = { 0.0, 0.0, 0.74, 0.52, 0.2 };       // by stage: where the smoke rises from (of the tower's height)
        public GDict moba_towers = new GDict();           // tower id -> {node, mesh, ring, stage, tier, h, top, fire, smoke, flames, dmg}
        public GArray _tshots = new GArray();                    // {node, from, id, t0, flight, to}
        public GArray _falling = new GArray();                   // broken-off pieces: {node, vel, spin, ground, t, rest}

        public void _BuildMoba()
        {
            if (sim.moba == null)
                return;
            _BuildBrush();
            _BuildFog();
            foreach (var tw in sim.moba.towers)
            {
                var gy = Sim.HeightAt(tw.p);
                var tier = tw.tier;
                // its front (the brazier's gem; the King tower's stairs) towards the other side's keep
                Vector2 d = Sim.Throne(1 - tw.team) - tw.p;
                var node = Towers.Instance(tier, Vt(tw.team));
                node.Position = new Vector3(tw.p.x, gy, tw.p.y);
                var nr = node.Rotation;
                nr.y = (float)Math.Atan2(d.x, d.y);
                node.Rotation = nr;
                AddChild(node);
                Vector3 top = node.Position + new Basis(Vector3.UP, node.Rotation.y) * Towers.Brazier(tier);
                // its range on the ground near it (0.31.217: Honor of Kings' -- a decal laid on the ground, a strong rim and a faint
                // fill, its colour by what it's doing: tower_ring; a thin torus floating at its foot until then)
                var ring = new Decal();
                double rr = Moba.TOWER_RANGE;
                ring.Size = new Vector3(rr * 2.0 + 0.4, 4.0, rr * 2.0 + 0.4);
                ring.Position = new Vector3(tw.p.x, gy + 0.5, tw.p.y);
                ring.TextureAlbedo = _RangeTex();
                ring.AlbedoMix = 1.0;
                ring.UpperFade = 0.3;
                ring.LowerFade = 0.3;
                ring.Modulate = RING_COLORS["yellow"].As<Color>();
                ring.Visible = false;
                AddChild(ring);
                var fire = _BeaconFire(top - new Vector3(0, 0.25, 0));
                fire.Scale = Vector3.ONE * (tier < 4 ? 0.2 : 0.26);          // (a small flame in the bowl, under the gem)
                fire.Amount = 8;
                ((fire.DrawPass1 as QuadMesh).Material as StandardMaterial3D).AlbedoColor = new Color(1.5, 0.62, 0.18, 0.8);
                moba_towers[tw.id] = GDict.Of("node", node, "mesh", Var.Of(node.GetMeta("mesh", null)), "ring", ring, "stage", -1, "tier", tier,
                    "h", Towers.Height(tier), "top", top, "fire", fire, "smoke", Var.Nil, "flames", Var.Nil, "dmg", -1.0);
                MeshInstance3D tmi = Var.Of(node.GetMeta("mesh", null)).As<MeshInstance3D>();
                if (tmi != null)
                    Towers.Chunks(Towers.KindOf(tier), tmi.Mesh);      // (the pieces made now, not in the middle of a fight)
            }
        }

        // 0.31.217 (Honor of Kings' tower ring, Kevin's recording): near an enemy tower its range shows -- yellow; red when it's
        // shooting you; green when it's shooting one of yours (a minion walked in first: safe to hit it)
        public static readonly GDict RING_COLORS = GDict.Of("yellow", new Color(1.0, 0.86, 0.3, 0.9), "red", new Color(1.0, 0.18, 0.12, 1.0), "green", new Color(0.3, 1.0, 0.42, 0.9));
        public static ImageTexture _range_img = null;

        public static ImageTexture _RangeTex()
        {
            // a white ring with soft edges round a faint disc (the decal tints it)
            if (_range_img != null)
                return _range_img;
            var n = 128;                                   // (one small texture for all of them, made once: ~16k pixels)
            var data = new byte[n * n * 4];
            var c = (double)(n - 1) * 0.5;
            var i = 0;
            for (int y = 0; y < n; y++)
            {
                for (int x = 0; x < n; x++)
                {
                    var d = new Vector2((double)x - c, (double)y - c).Length() / c;
                    var a = 0.0;
                    if (d <= 1.0)
                        a = 0.07 + 0.88 * GD.Clampf((d - 0.93) / 0.03, 0.0, 1.0) * GD.Clampf((1.0 - d) / 0.025, 0.0, 1.0);
                    data[i] = 255;
                    data[i + 1] = 255;
                    data[i + 2] = 255;
                    data[i + 3] = unchecked((byte)(int)(a * 255.0));
                    i += 4;
                }
            }
            _range_img = ImageTexture.CreateFromImage(Image.CreateFromData(n, n, false, ImageFormat.RGBA8, data));
            return _range_img;
        }

        public string TowerRing(Tower tw, Unit me)
        {
            // (me: null for the .gd's {})
            if (tw.dead || me == null || tw.team == me.team || !sim.Alive(me)
                    || me.pos.DistanceTo(tw.p) > Moba.TOWER_RANGE + 5.0)
                return "";
            var tg = tw.target ?? "";
            if (tg == me.id)
                return "red";
            Unit tu = tg != "" && sim.by_id.TryGetValue(tg, out var tgu) ? tgu : null;
            if (tu != null && tu.team == me.team && sim.Alive(tu))
                return "green";
            return "yellow";
        }

        public void _TowerStage(Tower tw, GDict mt, int stage, bool animate)
        {
            // A tower's look at a stage (towers.gd): that stage's cells hidden in its mesh and, when it happens before your
            // eyes, dropped as pieces; the brazier out from stage 3; smoke from 2, flames from the broken top at 3; at 4 (it
            // fell) the foot smoulders.
            var old = (int)mt["stage"];
            mt["stage"] = stage;
            MeshInstance3D mi = mt["mesh"].As<MeshInstance3D>();
            if (mi != null)
            {
                mi.SetInstanceShaderParameter("broken", (double)stage);
                mi.SetInstanceShaderParameter("lit", stage < 3 ? 1.0 : 0.0);
            }
            Node3D node = mt["node"].As<Node3D>();
            Vector3 @base = node.Position;
            if (animate && old >= 0 && stage > old && mi != null)
            {
                var pieces = Towers.Chunks(Towers.KindOf((int)mt["tier"]), mi.Mesh);
                var mid = Vector3.ZERO;
                var n = 0;
                foreach (var cv in pieces)
                {
                    GDict c = cv.D;
                    if ((int)c["stage"] > old && (int)c["stage"] <= stage)
                    {
                        Vector3 at = node.ToGlobal(c["center"].AsVec3() * (double)mt["h"]);
                        _DropPiece(c, mt, at, @base);
                        mid += at;
                        n += 1;
                    }
                }
                if (n > 0)
                {
                    mid /= (double)n;
                    SmokeCloud(mid, stage < 4 ? 0.28 : 0.7, stage < 4 ? 5 : 14, 3.0);
                    TowerBroke?.Invoke(mid, stage);
                }
            }
            if (stage >= 3 && GD.IsInstanceValid(mt["fire"]))
            {
                mt["fire"].As<Node>().QueueFree();
                mt["fire"] = Var.Nil;
            }
            if (stage >= 2)
            {
                Vector3 sh = @base + new Vector3(0, (double)mt["h"] * TOWER_SMOKE_H[GD.Mini(stage, 4)], 0);
                if (mt["smoke"].IsNull || !GD.IsInstanceValid(mt["smoke"]))
                    mt["smoke"] = _TowerSmoke(sh);
                mt["smoke"].As<Node3D>().Position = sh;
                mt["smoke"].As<GPUParticles3D>().AmountRatio = stage < 4 ? 1.0 : 0.5;
            }
            if (stage == 3 && (mt["flames"].IsNull || !GD.IsInstanceValid(mt["flames"])))
            {
                mt["flames"] = _BeaconFire(@base + new Vector3(0, (double)mt["h"] * 0.5, 0));
                mt["flames"].As<Node3D>().Scale = Vector3.ONE * 0.3;
                ((mt["flames"].As<GPUParticles3D>().DrawPass1 as QuadMesh).Material as StandardMaterial3D).AlbedoColor = new Color(1.5, 0.62, 0.18, 0.8);
            }
            else if (stage >= 4 && !mt["flames"].IsNull && GD.IsInstanceValid(mt["flames"]))
            {
                mt["flames"].As<Node>().QueueFree();
                mt["flames"] = Var.Nil;
            }
        }

        public void _DropPiece(GDict c, GDict mt, Vector3 at, Vector3 @base)
        {
            // a broken-off piece: thrown out from the tower's middle, tumbling, it bounces once and settles, then sinks away
            if (_falling.Size() >= 90)
                return;
            var p = new MeshInstance3D();
            p.Mesh = c["mesh"].As<Mesh>();
            p.MaterialOverride = mt["mesh"].As<MeshInstance3D>().MaterialOverride;
            p.SetInstanceShaderParameter("dmg", (double)mt["dmg"]);
            p.CastShadow = low_fx ? GeometryInstance3D.SHADOW_CASTING_SETTING_OFF : GeometryInstance3D.SHADOW_CASTING_SETTING_ON;
            p.Position = at;
            p.Basis = mt["node"].As<Node3D>().Basis.Scaled(Vector3.ONE * (double)mt["h"]);
            AddChild(p);
            var @out = new Vector2(at.x - @base.x, at.z - @base.z);
            @out = @out.Length() > 0.05 ? @out.Normalized() : Vector2.FromAngle(GD.Randf() * GD.TAU);
            var spd = GD.RandfRange(1.2, 3.4);
            _falling.Append(GDict.Of("node", p, "vel", new Vector3(@out.x * spd, GD.RandfRange(0.5, 2.6), @out.y * spd),
                "spin", new Vector3(GD.RandfRange(-1, 1), GD.RandfRange(-1, 1), GD.RandfRange(-1, 1)).NormalizedChecked() * GD.RandfRange(2.0, 6.0),
                "ground", Sim.HeightAt(new Vector2(at.x, at.z)), "bounced", false, "rest", -1.0, "t", 0.0));
        }

        public void _SyncFalling(double dt)
        {
            for (int i = _falling.Size() - 1; i > -1; i--)
            {
                GDict f = _falling[i].D;
                MeshInstance3D p = f["node"].As<MeshInstance3D>();
                if (!GD.IsInstanceValid(p))
                {
                    _falling.RemoveAt(i);
                    continue;
                }
                f["t"] = (double)f["t"] + dt;
                if ((double)f["rest"] < 0.0)
                {
                    Vector3 v = f["vel"].AsVec3();
                    v.y -= (float)(22.0 * dt);
                    p.Position += v * dt;
                    Vector3 sp = f["spin"].AsVec3();
                    if (sp.Length() > 0.01)
                        p.Basis = new Basis(sp.NormalizedChecked(), sp.Length() * dt) * p.Basis;
                    var gy = (double)f["ground"] + 0.15;
                    if (p.Position.y <= gy)
                    {
                        var pp = p.Position;
                        pp.y = (float)gy;
                        p.Position = pp;
                        if (!(bool)f["bounced"])
                        {
                            f["bounced"] = true;
                            v = new Vector3(v.x * 0.45, -v.y * 0.28, v.z * 0.45);
                            f["spin"] = sp * 0.4;
                            if (GD.Randf() < 0.5)
                                Spark(p.Position + new Vector3(0, 0.1, 0), new Color("#d9cdb4"));
                        }
                        else
                            f["rest"] = (double)f["t"];
                    }
                    f["vel"] = v;
                }
                else if ((double)f["t"] - (double)f["rest"] > 2.6)
                {
                    var pp = p.Position;
                    pp.y -= (float)(dt * 0.5);                     // (sinks into the ground, then goes)
                    p.Position = pp;
                    if ((double)f["t"] - (double)f["rest"] > 4.2)
                    {
                        p.QueueFree();
                        _falling.RemoveAt(i);
                    }
                }
            }
        }

        public GPUParticles3D _TowerSmoke(Vector3 at)
        {
            // a broken tower's smoke: a thin grey column drifting with the breeze, as long as it stands (and from its foot after)
            var pm = new ParticleProcessMaterial();
            pm.EmissionShape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE;
            pm.EmissionSphereRadius = 0.5;
            pm.Direction = new Vector3(0, 1, 0);
            pm.Spread = 10.0;
            pm.InitialVelocityMin = 0.8;
            pm.InitialVelocityMax = 1.5;
            pm.Gravity = new Vector3(0.0, 0.5, 0.0) + SMOKE_WIND * 1.4;
            pm.DampingMin = 0.2;
            pm.DampingMax = 0.4;
            pm.ScaleMin = 0.9;
            pm.ScaleMax = 1.5;
            var sc = new Curve();
            sc.AddPoint(new Vector2(0.0, 0.5));
            sc.AddPoint(new Vector2(1.0, 2.2));
            var sct = new CurveTexture();
            sct.Curve = sc;
            pm.ScaleCurve = sct;
            pm.AngleMin = -180.0;
            pm.AngleMax = 180.0;
            var g = new Gradient();
            g.SetOffsets(new double[] { 0.0, 0.15, 0.6, 1.0 });                    // (g.offsets = ...: the property's setter)
            g.SetColors(new[] { new Color(0.22, 0.2, 0.19, 0.0), new Color(0.25, 0.23, 0.22, 0.55), new Color(0.42, 0.41, 0.4, 0.3),
                new Color(0.55, 0.55, 0.55, 0.0) });
            var gt = new GradientTexture1D();
            gt.Gradient = g;
            pm.ColorRamp = gt;
            var q = new QuadMesh();
            q.Size = new Vector2(1.3, 1.3);
            q.Material = _SmokeDrawMat();
            var ps = new GPUParticles3D();
            ps.ProcessMaterial = pm;
            ps.DrawPass1 = q;
            ps.Amount = low_fx ? 5 : 9;
            ps.Lifetime = 5.0;
            ps.Preprocess = 3.0;
            ps.LocalCoords = false;
            ps.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            ps.VisibilityAabb = new AABB(new Vector3(-6, -1, -6), new Vector3(12, 12, 12));
            ps.Position = at;
            AddChild(ps);
            return ps;
        }

        public Plane[] _planes = new Plane[0];                    // (this frame's camera frustum, from sync)
        public double _fire_clock = 0.0;

        public void _SyncMoba()
        {
            // 0.31.220: a tower's flame (and a burning tower's smoke and fire) simulated only near the screen -- each is a GPU
            // particle system the graphics chip steps every frame, seen or not (18 towers' flames always on); 5 times a second
            _fire_clock -= GetProcessDeltaTime();
            var fire_tick = _fire_clock <= 0.0;
            if (fire_tick)
                _fire_clock = 0.2;
            _SyncRains();
            _SyncAuras();
            _SyncBreaths();
            _SyncKits();                               // 0.31.167: W and E
            _SyncFog();
            _SyncWards();
            Unit me = sim.by_id.TryGetValue(player_id, out var me0) ? me0 : null;
            foreach (var tw in sim.moba.towers)
            {
                GDict mt = moba_towers.Get(tw.id, new GDict()).D;
                if (mt.IsEmpty())
                    continue;
                // 0.31.172: breaking with its health (a first look -- a match joined late -- shows it as it is, nothing falls)
                var stg = Towers.StageOf(tw.hp, tw.max_hp, tw.dead);
                if (stg != (int)mt["stage"] && stg > (int)mt["stage"])
                    _TowerStage(tw, mt, stg, (int)mt["stage"] >= 0);
                var dm = tw.dead ? 1.0 : GD.Clampf(1.0 - tw.hp / GD.Maxf(tw.max_hp, 1.0), 0.0, 1.0);
                if (Math.Abs(dm - (double)mt["dmg"]) > 0.01 && !mt["mesh"].IsNull)
                {
                    mt["dmg"] = dm;
                    mt["mesh"].As<MeshInstance3D>().SetInstanceShaderParameter("dmg", dm);
                }
                if (fire_tick)
                {
                    var near = _planes.Length == 0 || _OnScreen(mt["top"].AsVec3(), _planes, 7.0);
                    foreach (var fk in new[] { "fire", "smoke", "flames" })
                    {
                        var f = mt.Get(fk);
                        if (!f.IsNull && GD.IsInstanceValid(f) && f.As<GPUParticles3D>().Emitting != near)
                            f.As<GPUParticles3D>().Emitting = near;
                    }
                }
                Decal ring = mt["ring"].As<Decal>();
                var rs = TowerRing(tw, me);
                ring.Visible = rs != "";
                if (rs != "")
                    ring.Modulate = RING_COLORS[rs].As<Color>();
            }
            for (int i = _tshots.Size() - 1; i > -1; i--)
            {
                GDict sh = _tshots[i].D;
                var k = GD.Clampf((_time - (double)sh["t0"]) / (double)sh["flight"], 0.0, 1.0);
                GDict a = actors.Get(GD.Str(sh["id"]), new GDict()).D;
                if (!a.IsEmpty() && GD.IsInstanceValid(a["root"]))
                    sh["to"] = a["root"].As<Node3D>().Position + new Vector3(0, 1.1, 0);
                Vector3 at = sh["from"].AsVec3().Lerp(sh["to"].AsVec3(), k);
                at.y += (float)(Math.Sin(k * GD.PI) * 0.8);
                if (GD.IsInstanceValid(sh["node"]))
                    sh["node"].As<Node3D>().Position = at;
                if (k >= 1.0)
                {
                    if (GD.IsInstanceValid(sh["node"]))
                        sh["node"].As<Node3D>().QueueFree();
                    for (int j = 0; j < 4; j++)
                        Spark(sh["to"].AsVec3() + new Vector3(GD.RandfRange(-0.3, 0.3), GD.RandfRange(-0.2, 0.4), GD.RandfRange(-0.3, 0.3)), new Color("#ffb04a"));
                    _tshots.RemoveAt(i);
                }
            }
        }

        // ---------- 0.31.158: the fog of war (moba_vision.gd) ----------
        // A dark veil over what your side can't see -- ground, trees and castles alike: one Decal over the whole field, its
        // texture a coarse mask (FOG_CELL m a texel, filtered smooth) redrawn FOG_EVERY s from your side's sight
        // (moba_vision.sources) -- each source a clear disc, brush patches dark again unless one of yours stands (or a ward of
        // yours stands) in them. (The texture is replaced, not updated: a decal keeps its own copy until its texture is
        // replaced. A screen-space veil from the depth buffer was tried: the depth buffer isn't there with the battle's MSAA on
        // the Mobile renderer.) Brush patches are KayKit bushes. Your side's wards show as little glowing posts; the enemy's
        // don't.
        public const double FOG_CELL = 2.0;
        public const int FOG_ALPHA = 200;
        public static readonly Color FOG_TINT = Color.FromRgba8(16, 22, 36);               // (a cool, dim veil: the decal mixes it in at FOG_ALPHA)
        public const double FOG_EVERY = 0.15;
        public GDict _fog = new GDict();
        public GDict _ward_nodes = new GDict();
        public bool fog_on = true;                         // (tests and render tools can turn the veil off)

        public bool _Fogged(Unit u)
        {
            // (0.31.158) the unit's body is hidden in the fog of war -- its effects go too
            GDict a = actors.Get(u.id ?? "", new GDict()).D;
            return !a.IsEmpty() && GD.IsInstanceValid(a["root"]) && !a["root"].As<Node3D>().Visible;
        }

        public int _MyTeam()
        {
            Unit me = sim.by_id.TryGetValue(player_id, out var me0) ? me0 : null;               // (0.31.160: no throwaway {} per call -- it's asked per unit, per frame)
            return me != null ? me.team : my_side;
        }

        public void _BuildFog()
        {
            var br = Land.BakeRect();                          // (the C# sim's bake_rect(): (x, y, w, h))
            var r = new Rect2(br.x, br.y, br.w, br.h);
            var w = (int)Math.Ceiling(r.size.x / FOG_CELL);
            var h = (int)Math.Ceiling(r.size.y / FOG_CELL);
            var img = Image.Create(w, h, false, ImageFormat.RGBA8);
            img.Fill(new Color(0, 0, 0, 0));
            var tex = ImageTexture.CreateFromImage(img);
            var d = new Decal();
            d.Size = new Vector3((double)w * FOG_CELL, 40.0, (double)h * FOG_CELL);
            d.Position = new Vector3(r.position.x + (double)w * FOG_CELL * 0.5, 8.0, r.position.y + (double)h * FOG_CELL * 0.5);
            d.TextureAlbedo = tex;
            d.AlbedoMix = 1.0;
            d.UpperFade = 0.0;
            d.LowerFade = 0.0;
            d.NormalFade = 0.0;
            d.Name = "FogOfWar";
            AddChild(d);
            _fog = GDict.Of("decal", d, "img", Var.Of(img), "tex", Var.Of(tex), "w", w, "h", h, "rect", r, "at", -10.0);
        }

        public int FogAlphaAt(Vector2 p)
        {
            // (tests) the veil over p: 0 clear .. FOG_ALPHA
            if (_fog.IsEmpty())
                return 0;
            Rect2 r = _fog["rect"].As<Rect2>();
            var cx = (int)((p.x - r.position.x) / FOG_CELL);
            var cz = (int)((p.y - r.position.y) / FOG_CELL);
            if (cx < 0 || cz < 0 || cx >= (int)_fog["w"] || cz >= (int)_fog["h"])
                return 0;
            return _fog["img"].As<Image>().GetPixel(cx, cz).A8;
        }

        public void _Stamp(Image img, int w, int h, Rect2 r, Vector2 c, double rad, Color col)
        {
            // a disc of texels, a row at a time
            var cx = (c.x - r.position.x) / FOG_CELL - 0.5;
            var cz = (c.y - r.position.y) / FOG_CELL - 0.5;
            var rr = rad / FOG_CELL;
            var z0 = GD.Maxi(0, (int)Math.Floor(cz - rr));
            var z1 = GD.Mini(h - 1, (int)Math.Ceiling(cz + rr));
            for (int z = z0; z < z1 + 1; z++)
            {
                var dz = (double)z - cz;
                var span = rr * rr - dz * dz;
                if (span < 0.0)
                    continue;
                var half = Math.Sqrt(span);
                var x0 = GD.Maxi(0, (int)Math.Ceiling(cx - half));
                var x1 = GD.Mini(w - 1, (int)Math.Floor(cx + half));
                if (x1 >= x0)
                    img.FillRect(new Rect2(x0, z, x1 - x0 + 1, 1), col);         // (Rect2i(x0, z, w, 1): the facade's FillRect takes a Rect2)
            }
        }

        public void _SyncFog()
        {
            if (_fog.IsEmpty() || sim.moba == null || sim.moba.vision == null)
                return;
            _fog["decal"].As<Decal>().Visible = fog_on;
            if (_time - (double)_fog["at"] < FOG_EVERY || !fog_on)
                return;
            // 0.31.220: and only when the sim's sight has changed (moba_vision.gd's epoch: every 0.2 s) -- it was drawn again
            // every 0.15 s from the same sight
            int ep = sim.moba.vision.epoch;            // (vision.get("epoch"): the C# sim's MobaVision always has it)
            if (ep >= 0 && ep == (int)_fog.Get("ep", -2))
                return;
            _fog["ep"] = ep;
            _fog["at"] = _time;
            Image img = _fog["img"].As<Image>();
            int w = (int)_fog["w"];
            int h = (int)_fog["h"];
            Rect2 r = _fog["rect"].As<Rect2>();
            var dark = new Color(FOG_TINT, (double)FOG_ALPHA / 255.0);
            var clear = new Color(FOG_TINT, 0.0);
            img.Fill(dark);
            var vis = sim.moba.vision;
            var src = vis.SourcesFor(_MyTeam());              // (vision.sources(team): [position, radius, brush] each)
            var done = new List<(Vector2 p, double r, int brush)>();
            var in_brush = new GDict();
            foreach (var sr in src)
            {
                if (sr.brush >= 0)
                    in_brush[sr.brush] = true;
                var skip = false;
                foreach (var d in done)
                {
                    if (sr.p.DistanceTo(d.p) < 3.0 && d.r >= sr.r - 0.1)
                    {
                        skip = true;                              // (a pack of minions: one disc)
                        break;
                    }
                }
                if (skip)
                    continue;
                done.Add(sr);
                _Stamp(img, w, h, r, sr.p, sr.r, clear);
            }
            foreach (var b in vis.brushes)
            {
                if (!in_brush.Has(b.id))
                    _Stamp(img, w, h, r, b.p, b.r, dark);        // (looking in from outside: nothing)
            }
            _fog["tex"].As<ImageTexture>().SetImage(img);
        }

        public void _BuildBrush()
        {
            // The brush you hide in (moba_vision.gd's patches). 0.31.216 (Kevin: "need new models for grass"): Honor of Kings' tall
            // lavender-tipped grass painted by ElevenLabs (ground_cards.gd BRUSH), thick enough to fill its circle -- a ring of
            // tall clumps round its edge, more through the middle -- with the field's grass clumps at its foot. (0.31.173: the
            // Meshy bushes and grasses of foliage.gd's BRUSH_SETS; KayKit's before.)
            if (sim.moba == null || sim.moba.vision == null)
                return;
            var rng = new Rng();
            rng.Seed = 158;
            var n = 0;
            foreach (var b in sim.moba.vision.brushes)
            {
                Vector2 c = b.p;
                double rad = b.r;
                var tall = new GArray();
                var tall_c = new GArray();
                var low = new GArray();
                var low_c = new GArray();
                var ring = (int)Math.Ceiling(GD.TAU * (rad - 0.4) / 0.95);
                for (int k = 0; k < ring; k++)
                {
                    var a = GD.TAU * ((double)k + rng.RandfRange(-0.3, 0.3)) / ring;
                    tall.Append(_BrushXf(c + Vector2.FromAngle(a) * (rad - 0.45) * rng.RandfRange(0.9, 1.05), rng, 2.0, 2.5));
                    tall_c.Append(GroundCards.Custom((int)(rng.Randi() % 2), rng));
                }
                var inner = (int)(rad * rad * 1.1);
                for (int k = 0; k < inner; k++)
                {
                    var q = c + Vector2.FromAngle(rng.Randf() * GD.TAU) * Math.Sqrt(rng.Randf()) * (rad - 0.9);
                    tall.Append(_BrushXf(q, rng, 2.1, 2.6));
                    tall_c.Append(GroundCards.Custom((int)(rng.Randi() % 2), rng));
                }
                for (int k = 0; k < (int)(ring * 0.8); k++)
                {
                    var q = c + Vector2.FromAngle(rng.Randf() * GD.TAU) * (rad + rng.RandfRange(-0.1, 0.35));
                    low.Append(_BrushXf(q, rng, 0.6, 0.9));
                    low_c.Append(GroundCards.Custom((int)(rng.Randi() % 8), rng));
                }
                // one MultiMesh a patch and kind (Brush_*: tests/moba_ui_test.gd, foliage_test.gd count them)
                foreach (var pair in new[] { ("brush", tall, tall_c), ("blades", low, low_c) })
                {
                    var mm = new MultiMesh();
                    mm.TransformFormat = MultiMesh.TRANSFORM_3D;
                    mm.UseCustomData = true;
                    mm.Mesh = GroundCards.Mesh(GD.Str(pair.Item1));
                    mm.InstanceCount = pair.Item2.Size();
                    for (int i = 0; i < mm.InstanceCount; i++)
                    {
                        mm.SetInstanceTransform(i, (Transform3D)pair.Item2[i]);
                        mm.SetInstanceCustomData(i, pair.Item3[i].As<Color>());
                    }
                    var mmi = new MultiMeshInstance3D();
                    mmi.Name = GD.Fmt("Brush_%s_%d", GD.Str(pair.Item1), n);
                    mmi.Multimesh = mm;
                    mmi.MaterialOverride = GroundCards.Material(GD.Str(pair.Item1), PAINT_TINT * CARD_LIGHT);
                    mmi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                    mmi.SetMeta("perf", "brush");
                    mmi.SetMeta("perf_kind", GD.Str(pair.Item1));
                    mmi.SetMeta("places", pair.Item2);
                    AddChild(mmi);
                }
                n += 1;
            }
        }

        public static Transform3D _BrushXf(Vector2 q, Rng rng, double s0, double s1)
        {
            var sc = rng.RandfRange(s0, s1);
            var b = new Basis(Vector3.UP, rng.Randf() * GD.TAU).Scaled(new Vector3(sc * rng.RandfRange(0.9, 1.2), sc, sc * rng.RandfRange(0.9, 1.2)));
            return new Transform3D(b, new Vector3(q.x, Sim.HeightAt(q) - 0.06, q.y));
        }

        // 0.31.216 (Kevin: "use eleven to draw detailed paint on ground"): carved stone circles where Honor of Kings has them --
        // the river's crossing in the middle, the pits' floors, the lanes outside each keep's gates and halfway down the
        // middle lane and the side lanes -- and a ring of carved stone round every tower's foot (ground_cards.gd decals).
        public static readonly (Vector2, double)[] MARK_CIRCLES = { (new Vector2(0.0, 0.0), 8.5), (new Vector2(0.0, 41.0), 6.0), (new Vector2(-60.0, 33.0), 6.0),
            (new Vector2(60.0, 33.0), 6.0) };
        public const double MARK_RING = 6.4;                 // a tower's ring, across (its hole ~2.4 m: the tower's foot stands in it)

        public void _BuildGroundMarks()
        {
            // (the ground's own height: the ridges' rock, where a mark runs under it, hides it -- and the build step is a quarter
            // of the time terrain_height's took)
            Func<Vector2, double> h = (p) => Land.GroundHeight(p);             // (ground_height(p, false))
            var spots = new List<(string, Vector2, double)>();
            foreach (var c in MARK_CIRCLES)
            {
                spots.Add(("circle.png", c.Item1, c.Item2));
                if (c.Item1.Length() > 0.1)
                    spots.Add(("circle.png", -c.Item1, c.Item2));
            }
            for (int i = 0; i < 2; i++)
                spots.Add(("circle.png", Land.PitC(i), Land.PIT_R * 1.9));
            for (int t = 0; t < 2; t++)
            {
                for (int g = 0; g < Keep.GATE_ANG.Length; g++)
                {
                    Vector2 gc = Keep.GateC(g);
                    var @out = (gc - Keep.C).Normalized();
                    spots.Add(("circle.png", Sim.M(t, gc + @out * 6.2), 5.2));
                }
            }
            if (sim.moba != null)
            {
                foreach (var tw in sim.moba.towers)
                    spots.Add(("ring.png", tw.p, MARK_RING));
            }
            var rng = new Rng();
            rng.Seed = 216;
            foreach (var sp in spots)
            {
                var mi = new MeshInstance3D();
                mi.Mesh = GroundCards.DecalMesh(sp.Item2, sp.Item3, h);
                ShaderMaterial m = GroundCards.DecalMaterial(GD.Str(sp.Item1), PAINT_TINT * 1.05).Duplicate() as ShaderMaterial;
                m.SetShaderParameter("spin", rng.Randf() * GD.TAU);
                mi.MaterialOverride = m;
                mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                mi.SetMeta("perf", "marks");
                AddChild(mi);
            }
        }

        public void _SyncWards()
        {
            if (sim.moba == null || sim.moba.vision == null)
                return;
            var team = _MyTeam();
            var live = new GDict();
            foreach (var w in sim.moba.vision.wards)
            {
                if (w.team != team)
                    continue;                                    // (the enemy's wards are hidden)
                live[w.id] = true;
                if (!_ward_nodes.Has(w.id))
                    _ward_nodes[w.id] = _MakeWard(w.p);
            }
            foreach (var id in _ward_nodes.Keys())
            {
                if (!live.Has(id))
                {
                    if (GD.IsInstanceValid(_ward_nodes[id]))
                        _ward_nodes[id].As<Node3D>().QueueFree();
                    _ward_nodes.Erase(id);
                }
            }
        }

        public Node3D _MakeWard(Vector2 p)
        {
            var root = new Node3D();
            root.Position = new Vector3(p.x, Sim.HeightAt(p), p.y);
            var post = new MeshInstance3D();
            var cm = new CylinderMesh();
            cm.TopRadius = 0.05;
            cm.BottomRadius = 0.09;
            cm.Height = 1.0;
            post.Mesh = cm;
            var wood = new StandardMaterial3D();
            wood.AlbedoColor = new Color("#5a3d22");
            post.MaterialOverride = wood;
            var pp = post.Position;
            pp.y = 0.5f;
            post.Position = pp;
            root.AddChild(post);
            var orb = new MeshInstance3D();
            var sm = new SphereMesh();
            sm.Radius = 0.16;
            sm.Height = 0.32;
            orb.Mesh = sm;
            orb.MaterialOverride = _FxMat(new Color("#7fd8ff"));
            var op = orb.Position;
            op.y = 1.1f;
            orb.Position = op;
            root.AddChild(orb);
            var ring = new MeshInstance3D();
            ring.Mesh = _RingMesh(0.45, 0.06);
            ring.Scale = new Vector3(1, 0.2, 1);
            ring.MaterialOverride = _Unshaded(new Color(0.5, 0.85, 1.0, 0.7));
            var rp = ring.Position;
            rp.y = 0.06f;
            ring.Position = rp;
            root.AddChild(ring);
            AddChild(root);
            return root;
        }

        // ---------- 0.31.157: ultimates, the jungle, gold ----------
        public static readonly GDict ULT_COL = new GDict
        {
            { "knight", "#ffd65a" }, { "barbarian", "#ff5a3a" }, { "rogue", "#7a5ab8" }, { "ranger", "#cfe8b8" }, { "mage", "#ff8a3a" },
            { "priest", "#fff1a8" }, { "crusader", "#ffd65a" }, { "berserker", "#ff2a2a" }, { "assassin", "#9a6bff" }, { "sniper", "#dff4ff" },
            { "archmage", "#c070ff" }, { "necromancer", "#7dff8a" },
        };
        public static readonly GDict AURA_COL = GDict.Of("dr", "#ffd65a", "bl", "#ff5a3a", "ud", "#ff2a2a", "arcane", "#7fb8ff", "ember", "#ff8a3a", "lord", "#c9a6ff");
        public GArray _rain_fx = new GArray();                   // {at, r, until, next}
        public double _aura_at = 0.0;

        public Vector3 _Ground(Vector2 p, double up = 0.1)
        {
            return new Vector3(p.x, Sim.HeightAt(p) + up, p.y);
        }

        public void _MobaFx(GDict e)
        {
            GDict a = actors.Get(GD.Str(e.Get("id", "")), new GDict()).D;
            switch (GD.Str(e["k"]))
            {
                case "ult":
                {
                    // 0.31.201: each ultimate its own look (spell_fx.gd ult); the Ranger's arrows still fall here (_sync_rains)
                    Vector3 at = !a.IsEmpty() && GD.IsInstanceValid(a["root"]) ? a["root"].As<Node3D>().Position : _Ground(e["pos"].AsVec2());
                    var sp = GD.Str(e.Get("spell", ""));
                    if (sp != "" && !a.IsEmpty() && NEW_ULT_CLIP.Has(sp))
                        _Play(a, GD.Str(NEW_ULT_CLIP[sp]), 1.2, 0.45);
                    if (GD.Str(e["ult"]) == "ranger")
                    {
                        Vector2 c2 = e.Get("c", e["pos"]).AsVec2();
                        _rain_fx.Append(GDict.Of("at", c2, "r", (double)e.Get("r", 4.5), "until", _time + (double)e.Get("dur", 2.0), "next", _time));
                    }
                    fxs.Ult(GD.Str(e["ult"]), e, a, at);
                    break;
                }
                case "flurry_hit":
                    fxs.Event(e);
                    break;
                case "lord_slam":
                {
                    var lp = _Ground(e["pos"].AsVec2(), 0.2);
                    RingAt(lp, new Color("#c9a6ff"), 2.0 * Moba.LORD_SLAM_R - 0.4, 0.5);
                    Shockwave(lp, Moba.LORD_SLAM_R);
                    for (int i = 0; i < 8; i++)
                        Spark(lp + new Vector3(GD.RandfRange(-2.0, 2.0), 0.3 + GD.Randf() * 0.8, GD.RandfRange(-2.0, 2.0)), new Color("#d8c2ff"));
                    Unit me = sim.by_id.TryGetValue(player_id, out var me0) ? me0 : null;
                    if (me != null && me.pos.DistanceTo(e["pos"].AsVec2()) < 14.0)
                        Shake(0.35);
                    break;
                }
                case "camp_up":
                {
                    foreach (var id in e.Get("ids", new GArray()))
                    {
                        GDict ca = actors.Get(GD.Str(id), new GDict()).D;
                        Unit cu = sim.by_id.TryGetValue(GD.Str(id), out var cu0) ? cu0 : null;
                        if (cu == null)
                            continue;
                        var cp = _Ground(cu.pos);
                        RingAt(cp, TEAM_COLORS[2], 1.8, 0.6);
                        for (int i = 0; i < 6; i++)
                            Spark(cp + new Vector3(GD.RandfRange(-0.5, 0.5), GD.Randf() * 0.8, GD.RandfRange(-0.5, 0.5)), new Color("#e8dcc0"));
                        if (!ca.IsEmpty() && GD.IsInstanceValid(ca["root"]))
                            ca["root"].As<Node3D>().Position = cp - new Vector3(0, 0.1, 0);
                    }
                    break;
                }
                case "buff":
                {
                    if (!a.IsEmpty() && GD.IsInstanceValid(a["root"]))
                    {
                        var bc = new Color(GD.Str(AURA_COL.Get(GD.Str(e["buff"]), "#ffffff")));
                        for (int i = 0; i < 2; i++)
                            RingAt(a["root"].As<Node3D>().Position, bc, 2.4 + i * 1.6, 0.7 + 0.2 * i);
                        for (int i = 0; i < 10; i++)
                            Spark(a["root"].As<Node3D>().Position + new Vector3(GD.RandfRange(-0.5, 0.5), 0.3 + GD.Randf() * 2.0, GD.RandfRange(-0.5, 0.5)), bc);
                    }
                    break;
                }
                case "lord_down":
                {
                    var ld = _Ground(Moba.BOSS_P, 0.2);
                    _PackExplosion("heavy", ld + new Vector3(0, 1.4, 0), 1.6);
                    for (int i = 0; i < 3; i++)
                        RingAt(ld, new Color("#c9a6ff"), 3.0 + i * 2.0, 0.8 + i * 0.2);
                    Shake(0.6);
                    break;
                }
                case "gold":
                    if (GD.Str(e["id"]) == player_id)
                        Number(_Ground(e["pos"].AsVec2(), 2.4), GD.Fmt("+%d", (int)e["n"]), true, true);
                    break;
                case "lord_march":                                       // 0.31.158: the Bone Lord out of the slayers' castle
                {
                    Unit lu = sim.by_id.TryGetValue(GD.Str(e.Get("id", "")), out var lu0) ? lu0 : null;
                    if (lu != null && ((int)e["team"] == _MyTeam() || sim.moba.CanSee(_MyTeam(), lu)))
                    {
                        var lm = _Ground(lu.pos, 0.2);
                        for (int i = 0; i < 3; i++)
                            RingAt(lm, TEAM_COLORS[Vt((int)e["team"])].Lightened(0.2), 2.0 + i * 1.6, 0.7 + i * 0.2);
                        for (int i = 0; i < 12; i++)
                            Spark(lm + new Vector3(GD.RandfRange(-1.2, 1.2), 0.3 + GD.Randf() * 2.4, GD.RandfRange(-1.2, 1.2)), new Color("#d8c2ff"));
                    }
                    break;
                }
                case "wyrm_breath":                                      // 0.31.166: the Grave Wyrm's soul-fire
                {
                    if (a.IsEmpty() || !GD.IsInstanceValid(a["root"]) || !a["root"].As<Node3D>().Visible)
                        return;
                    _Play(a, "w/Breath", 1.0, 1.4);
                    Vector2 bd = e.Get("dir", new Vector2(0, 1)).AsVec2().Normalized();
                    Node3D root3 = a["root"].As<Node3D>();
                    Vector3 mouth = root3.Position + new Basis(Vector3.UP, Sim.AngleOf(bd)) * (WyrmBody.MouthLocal() * a["body"].As<Node3D>().Scale.x);
                    _breaths.Append(GDict.Of("at", _time + WyrmBody.BREATH_AT, "from", mouth, "dir", bd));
                    break;
                }
                case "wyrm_down":                                        // 0.31.166: its soul-fire bursts out of it
                {
                    var wd = _Ground(Moba.WYRM_P, 0.2);
                    foreach (var id in actors)
                    {
                        if ((double)actors[id].D.Get("big", 0.0) > 0.0 && GD.IsInstanceValid(actors[id]["root"]))
                            wd = actors[id]["root"].As<Node3D>().Position + new Vector3(0, 0.2, 0);
                    }
                    for (int i = 0; i < 3; i++)
                        RingAt(wd, WYRM_FIRE, 3.0 + i * 2.2, 0.8 + i * 0.25);
                    _SoulFire(wd + new Vector3(0, 1.6, 0), Vector3.UP, 1.4, 0.9);
                    Shockwave(wd + new Vector3(0, 0.3, 0), 7.0);
                    for (int i = 0; i < 16; i++)
                        Spark(wd + new Vector3(GD.RandfRange(-2.5, 2.5), 0.4 + GD.Randf() * 3.0, GD.RandfRange(-2.5, 2.5)), WYRM_FIRE);
                    Shake(0.6);
                    break;
                }
                case "ward":
                {
                    if ((int)e.Get("team", -1) == _MyTeam())
                    {
                        var wp3 = _Ground(e["pos"].AsVec2(), 0.15);
                        RingAt(wp3, new Color("#8fe3ff"), 3.0, 0.5);
                        for (int i = 0; i < 5; i++)
                            Spark(wp3 + new Vector3(GD.RandfRange(-0.3, 0.3), 0.4 + GD.Randf() * 1.0, GD.RandfRange(-0.3, 0.3)), new Color("#bdf0ff"));
                    }
                    break;
                }
            }
        }

        // ---------- 0.31.167: W and E (moba_kits.gd) ----------
        // Each cast: its caster's clip (SPELL_CLIP) and a burst in its colour (SPELL_COL) shaped by what it is -- rings for the
        // area ones, a trail for the dashes, sparks at both ends of a blink or a shadow step, a fan for the knives, a pillar of
        // light for HOLY LIGHT, fire for the pillar's eruption. What lasts is drawn while it lasts (_sync_kits): a shield is a
        // glowing bubble round its hero, a slow a pale ring at his feet, a mark or a curse a red one, poison green sparks rising;
        // holy ground and caltrops a ring on the ground for their time, a fire pillar's warning circle until it erupts; your
        // side's bear traps (theirs are hidden).
        public static readonly GDict SPELL_CLIP = new GDict
        {
            { "bash", "m/Melee_Block_Attack" }, { "rally", "r/Ranged_Magic_Raise" }, { "consecrate", "r/Ranged_Magic_Raise" },
            { "leap", "m/Melee_1H_Attack_Jump_Chop" }, { "bloodlust", "r/Ranged_Magic_Raise" }, { "charge", "mb/Running_B" }, { "frenzy", "r/Ranged_Magic_Raise" },
            { "caltrops", "g/Throw" }, { "poison", "g/Use_Item" }, { "shadowstep", "m/Melee_Dualwield_Attack_Stab" }, { "knives", "g/Throw" },
            { "tumble", "ma/Dodge_Forward" }, { "snare", "r/Ranged_Bow_Release" }, { "trap", "g/Interact" }, { "mark", "g/Interact" },
            { "pillar", "r/Ranged_Magic_Spellcasting" }, { "missiles", "r/Ranged_Magic_Shoot" }, { "manashield", "r/Ranged_Magic_Raise" },
            { "holylight", "r/Ranged_Magic_Spellcasting" }, { "dazzle", "r/Ranged_Magic_Raise" }, { "boneshield", "r/Ranged_Magic_Spellcasting" },
            { "curse", "r/Ranged_Magic_Shoot" },
            // 0.31.168: the six new heroes
            { "boulder", "g/Throw" }, { "stoneskin", "r/Ranged_Magic_Raise" }, { "quake", "m/Melee_1H_Attack_Jump_Chop" }, { "sweep", "m/Melee_2H_Attack_Slice" },
            { "impale", "m/Melee_2H_Attack_Stab" }, { "vault", "mb/Jump_Full_Long" }, { "thrust", "m/Melee_1H_Attack_Stab" }, { "riposte", "m/Melee_Blocking" },
            { "feint", "ma/Dodge_Backward" }, { "chain", "r/Ranged_Magic_Shoot" }, { "static", "r/Ranged_Magic_Spellcasting" }, { "gust", "r/Ranged_Magic_Shoot" },
            { "buckshot", "r/Ranged_Bow_Release" }, { "keg", "g/Throw" }, { "smokeroll", "ma/Dodge_Forward" }, { "rejuv", "r/Ranged_Magic_Spellcasting" },
            { "entangle", "r/Ranged_Magic_Summon" }, { "barkskin", "r/Ranged_Magic_Raise" },
        };
        public static readonly GDict SPELL_COL = new GDict
        {
            { "bash", "#bcd8ff" }, { "rally", "#ffd65a" }, { "consecrate", "#ffe9a6" }, { "leap", "#e0c9a0" }, { "bloodlust", "#ff3a2a" },
            { "charge", "#ff6a3a" }, { "frenzy", "#ff5a3a" }, { "caltrops", "#b8b8b8" }, { "poison", "#7dff6a" }, { "shadowstep", "#9a6bff" }, { "knives", "#d8d0ff" },
            { "tumble", "#e0d0b0" }, { "snare", "#cfe8b8" }, { "trap", "#a08060" }, { "mark", "#ff4a4a" }, { "pillar", "#ff8a3a" }, { "blink", "#8fc8ff" },
            { "missiles", "#c070ff" }, { "manashield", "#7fb8ff" }, { "holylight", "#fff1a8" }, { "dazzle", "#ffffff" }, { "boneshield", "#e8e0c8" },
            { "curse", "#b04aff" },
            // 0.31.168
            { "boulder", "#9a978e" }, { "stoneskin", "#b8b2a4" }, { "quake", "#c8b48a" }, { "sweep", "#e8e4dc" }, { "impale", "#f0d0a0" }, { "vault", "#ffcf8a" },
            { "thrust", "#f4f0ff" }, { "riposte", "#ffe27a" }, { "feint", "#c9b8ff" }, { "chain", "#9fd4ff" }, { "static", "#6fb4ff" }, { "gust", "#d8f4ff" },
            { "buckshot", "#ffe0a0" }, { "keg", "#ff9a3a" }, { "smokeroll", "#c8c8c8" }, { "smoke", "#b8b8b8" }, { "rejuv", "#8dff6a" }, { "entangle", "#6fbf3a" },
            { "barkskin", "#a07a4a" }, { "landslide", "#b0a48a" }, { "dragondive", "#ff7a3a" }, { "challenge", "#ffe27a" }, { "thunderstorm", "#7fb8ff" },
            { "quickdraw", "#ffd890" }, { "wildgrowth", "#6aff7a" },
        };
        public GDict _zone_nodes = new GDict();                      // zone id -> its ring
        public GDict _trap_nodes = new GDict();                      // trap id -> its mesh
        public GDict _kit_marks = new GDict();                       // unit id -> {"shield": node, "slow": node, "amp": node}
        public double _kit_next = 0.0;

        public void _KitFx(GDict e)
        {
            GDict a = actors.Get(GD.Str(e.Get("id", "")), new GDict()).D;
            bool shown = !a.IsEmpty() && GD.IsInstanceValid(a["root"]) && a["root"].As<Node3D>().Visible;
            switch (GD.Str(e["k"]))
            {
                case "spell":
                {
                    var sp = GD.Str(e["spell"]);
                    var col = new Color(GD.Str(SPELL_COL.Get(sp, "#ffffff")));
                    if (!shown && (int)e.Get("team", -1) != _MyTeam())
                        return;
                    if (!a.IsEmpty() && SPELL_CLIP.Has(sp))
                        _Play(a, GD.Str(SPELL_CLIP[sp]), sp != "charge" ? 1.4 : 1.8, 0.45);
                    Vector3 at = shown ? a["root"].As<Node3D>().Position : _Ground(e["pos"].AsVec2());
                    fxs.Cast(sp, e, a, at, GD.Str(e.Get("hid", "")));     // 0.31.201: each its own look (spell_fx.gd)
                    break;
                }
                case "slam":
                case "pillar":
                case "burst":
                case "zap":
                case "riposte":
                    fxs.Event(e);                               // 0.31.201 (spell_fx.gd event)
                    break;
                case "trap_snap":
                    fxs.Event(e);
                    if (_trap_nodes.Has((int)e["trap"]))
                    {
                        _trap_nodes[(int)e["trap"]].As<Node3D>().QueueFree();
                        _trap_nodes.Erase((int)e["trap"]);
                    }
                    break;
                case "trap_gone":
                    if (_trap_nodes.Has((int)e["trap"]))
                    {
                        _trap_nodes[(int)e["trap"]].As<Node3D>().QueueFree();
                        _trap_nodes.Erase((int)e["trap"]);
                    }
                    break;
            }
        }

        public void _ShakeNear(Vector2 p, double r, double k)
        {
            Unit me = sim.by_id.TryGetValue(player_id, out var me0) ? me0 : null;
            if (me != null && me.pos.DistanceTo(p) < r)
                Shake(k);
        }

        public static readonly GDict NEW_ULT_CLIP = GDict.Of("landslide", "mb/Running_B", "dragondive", "mb/Jump_Full_Long", "thunderstorm", "r/Ranged_Magic_Summon",
            "quickdraw", "r/Ranged_Bow_Release", "wildgrowth", "r/Ranged_Magic_Raise");
        public static BoxMesh _bolt_mesh;

        public void _BoltLine(Vector3 from, Vector3 to, Color col, double life, double jag)
        {
            // a jagged streak of light (chain lightning, the storm's bolts, a musket's tracer): a few thin boxes, each from one
            // kink to the next, thinning out over its life (_step_fx "bolt")
            if (low_fx && life < 0.2)
                return;
            if (_bolt_mesh == null)
            {
                _bolt_mesh = new BoxMesh();
                _bolt_mesh.Size = new Vector3(0.16, 0.16, 1.0);
            }
            var n = GD.Maxi(1, (int)(from.DistanceTo(to) / 1.2));
            var prev = from;
            for (int i = 0; i < n; i++)
            {
                var t = (double)(i + 1) / (double)n;
                var nxt = from.Lerp(to, t);
                if (i < n - 1)
                    nxt += new Vector3(GD.RandfRange(-jag, jag), GD.RandfRange(-jag, jag) * 0.6, GD.RandfRange(-jag, jag)) * 0.5;
                var seg = new MeshInstance3D();
                seg.Mesh = _bolt_mesh;
                seg.MaterialOverride = _FxMat(col);
                seg.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                AddChild(seg);
                var mid = (prev + nxt) * 0.5;
                var len = GD.Maxf(0.05, prev.DistanceTo(nxt));
                seg.Position = mid;
                if (len > 0.06)
                    seg.LookAtFromPosition(mid, nxt, Math.Abs((nxt - prev).NormalizedChecked().y) < 0.95 ? Vector3.UP : Vector3.RIGHT);
                seg.Scale = new Vector3(1.0, 1.0, len);
                _fx.Append(GDict.Of("node", seg, "at", _time, "life", life, "kind", "bolt"));
                prev = nxt;
            }
        }

        public void _Lob(Vector3 from, Vector3 to, double dur, Color col)
        {
            // a thrown thing's arc (the powder keg): _step_fx's "shell"
            var mi = new MeshInstance3D();
            var cm = new CylinderMesh();
            cm.TopRadius = 0.22;
            cm.BottomRadius = 0.22;
            cm.Height = 0.42;
            mi.Mesh = cm;
            mi.MaterialOverride = _ShotMat("keg", col, 0.0, 0.8);
            mi.Position = from;
            AddChild(mi);
            _fx.Append(GDict.Of("node", mi, "at", _time, "life", dur, "kind", "shell", "p0", from, "p1", to));
        }

        public void _Vines(Vector3 at, double r)
        {
            // roots bursting up (ENTANGLE, WILD GROWTH): a ring of green spikes that sink back (_step_fx "spark" moves them)
            for (int i = 0; i < 8; i++)
            {
                var ang = GD.TAU * (double)i / 8.0 + GD.Randf() * 0.3;
                var mi = new MeshInstance3D();
                var pm = new PrismMesh();
                pm.Size = new Vector3(0.18, 0.9, 0.18);
                mi.Mesh = pm;
                mi.MaterialOverride = _ShotMat("vine", new Color("#4f8f2a"), 0.4, 0.8);
                mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                var p = at + new Vector3(Math.Cos(ang) * r * 0.5, 0.3, Math.Sin(ang) * r * 0.5);
                mi.Position = p;
                mi.Rotation = new Vector3(GD.RandfRange(-0.4, 0.4), 0.0, GD.RandfRange(-0.4, 0.4));
                AddChild(mi);
                _fx.Append(GDict.Of("node", mi, "at", _time, "life", 0.9, "kind", "spark", "p0", p, "dir", new Vector3(0, -0.3, 0)));
            }
        }

        public void _SyncKits()
        {
            var kits = sim.moba.kits;
            double t = sim.time;
            var my = _MyTeam();
            // zones (0.31.201: each its own ground, spell_fx.gd zone -- holy rays, lightning, smoke, the grove)
            var live = new GDict();
            foreach (var z in kits.zones)
            {
                var zid = z.zid;
                live[zid] = true;
                if (!_zone_nodes.Has(zid))
                    _zone_nodes[zid] = Var.Of(fxs.Zone(z));
            }
            foreach (var z in _zone_nodes.Keys())
            {
                if (!live.Has(z))
                {
                    fxs.Release(GD.Fmt("zone:%d", (int)z));
                    _zone_nodes.Erase(z);
                }
            }
            // your side's traps
            foreach (var tr in kits.traps)
            {
                if (tr.team != my || _trap_nodes.Has(tr.id))
                    continue;
                _trap_nodes[tr.id] = Var.Of(fxs.TrapNode(_Ground(tr.at, 0.05), TEAM_COLORS[Vt(my)]));
            }
            // what lasts on heroes: shields, slows, marks, skins, parries, poison, dashes, the ultimates' auras (spell_fx.gd)
            foreach (var id in actors)
            {
                Unit u = sim.by_id.TryGetValue(GD.Str(id), out var u0) ? u0 : null;
                if (u == null || !u.hero)
                    continue;
                GDict a = actors[id].D;
                if (!GD.IsInstanceValid(a["root"]))
                    continue;
                bool vis = a["root"].As<Node3D>().Visible && sim.Alive(u);
                fxs.SyncUnit(GD.Str(id), u, a, vis);
            }
        }

        // ---------- the Grave Wyrm's soul-fire (0.31.166) ----------
        // A pale cyan-green flame poured from its jaws along the breath's line: a GPU particle stream (the smoke puff sprite, added
        // on, white-hot to green to nothing, swelling as it goes) spread to the sim's cone (moba.gd WYRM_BREATH_ARC, out to
        // WYRM_BREATH_R), cinders, and the ground it reaches scorched with a ring.
        public static readonly Color WYRM_FIRE = new Color("#7dffd0");
        public GArray _breaths = new GArray();                   // {at, from, dir}: soul-fire to pour (once the clip has lunged)
        public static ParticleProcessMaterial _soul_pm = null;
        public static StandardMaterial3D _soul_draw = null;

        public void _SyncBreaths()
        {
            for (int i = _breaths.Size() - 1; i > -1; i--)
            {
                GDict b = _breaths[i].D;
                if (_time < (double)b["at"])
                    continue;
                _breaths.RemoveAt(i);
                Vector2 d2 = b["dir"].AsVec2();
                Vector3 from = b["from"].AsVec3();
                var from2 = new Vector2(from.x, from.z);
                double reach = Moba.WYRM_BREATH_R;
                _SoulFire(from, (new Vector3(d2.x, 0.0, d2.y) + new Vector3(0, -0.28, 0)).NormalizedChecked(), 1.0, 0.85);
                RingAt(_Ground(from2 + d2 * reach * 0.8), WYRM_FIRE, reach * 0.9, 0.7);
                for (int k = 0; k < 10; k++)
                {
                    var off = d2.Rotated(GD.RandfRange(-1.0, 1.0) * Moba.WYRM_BREATH_ARC) * GD.RandfRange(0.3, 1.0) * reach;
                    Spark(_Ground(from2 + off, 0.3 + GD.Randf() * 0.8), WYRM_FIRE);
                }
                Unit me = sim.by_id.TryGetValue(player_id, out var me0) ? me0 : null;
                if (me != null && me.pos.DistanceTo(from2) < 12.0)
                    Shake(0.3);
            }
        }

        public void _SoulFire(Vector3 at, Vector3 dir, double size, double pour)
        {
            // the flame stream, poured for `pour` seconds along dir from at; straight up (Vector3.UP), one burst
            if (_soul_pm == null)
            {
                var pm = new ParticleProcessMaterial();
                pm.EmissionShape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE;
                pm.EmissionSphereRadius = 0.25;
                pm.Direction = new Vector3(0, 0, -1);
                pm.Spread = 30.0;                                  // about WYRM_BREATH_ARC (0.6 rad) either side
                pm.InitialVelocityMin = 10.0;
                pm.InitialVelocityMax = 14.0;
                pm.DampingMin = 9.0;
                pm.DampingMax = 13.0;
                pm.Gravity = new Vector3(0, 2.2, 0);                   // flames rise
                pm.AngleMin = -180.0;
                pm.AngleMax = 180.0;
                pm.AngularVelocityMin = -90.0;
                pm.AngularVelocityMax = 90.0;
                pm.ScaleMin = 0.7;
                pm.ScaleMax = 1.1;
                var sc = new Curve();
                sc.AddPoint(new Vector2(0.0, 0.3));
                sc.AddPoint(new Vector2(0.35, 1.0));
                sc.AddPoint(new Vector2(1.0, 1.7));
                var sct = new CurveTexture();
                sct.Curve = sc;
                pm.ScaleCurve = sct;
                var g = new Gradient();
                g.SetOffsets(new double[] { 0.0, 0.12, 0.45, 1.0 });                    // (g.offsets = ...: the property's setter)
                g.SetColors(new[] { new Color(0.75, 1.0, 0.95, 0.0), new Color(0.45, 1.0, 0.8, 0.5), new Color(0.12, 0.7, 0.5, 0.32), new Color(0.0, 0.2, 0.15, 0.0) });
                var gt = new GradientTexture1D();
                gt.Gradient = g;
                pm.ColorRamp = gt;
                pm.LifetimeRandomness = 0.3;
                _soul_pm = pm;
                var m = new StandardMaterial3D();
                m.BillboardMode = BaseMaterial3D.BILLBOARD_PARTICLES;
                m.BillboardKeepScale = true;
                m.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
                m.BlendMode = BaseMaterial3D.BLEND_MODE_ADD;
                m.ShadingMode = BaseMaterial3D.SHADING_MODE_UNSHADED;
                m.VertexColorUseAsAlbedo = true;
                m.AlbedoTexture = SMOKE_TEX;
                m.CullMode = BaseMaterial3D.CULL_DISABLED;
                _soul_draw = m;
            }
            var p = new GPUParticles3D();
            p.ProcessMaterial = _soul_pm;
            var q = new QuadMesh();
            q.Size = Vector2.ONE;
            q.Material = _soul_draw;
            p.DrawPass1 = q;
            p.Amount = 90;
            p.Lifetime = 0.9;
            p.FixedFps = 30;
            p.Interpolate = true;
            p.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            p.VisibilityAabb = new AABB(new Vector3(-10, -4, -10), new Vector3(20, 14, 20));
            if (low_fx)
                p.AmountRatio = 0.5;
            p.Position = at;
            var burst = Math.Abs(dir.NormalizedChecked().Dot(Vector3.UP)) > 0.99;
            if (burst)
            {
                p.Basis = new Basis(Vector3.RIGHT, GD.PI * 0.5).Scaled(Vector3.ONE * size);          // its -Z up
                p.Explosiveness = 0.8;
                p.OneShot = true;
            }
            else
                p.Basis = Basis.LookingAt(dir, Vector3.UP).Scaled(Vector3.ONE * size);
            AddChild(p);
            p.Restart();
            if (!burst)
            {
                GetTree().CreateTimer(pour).Timeout += () =>
                {
                    if (GD.IsInstanceValid(p))
                        p.Emitting = false;
                };
            }
            GetTree().CreateTimer(pour + p.Lifetime + 0.5).Timeout += p.QueueFree;
        }

        public void _SyncRains()
        {
            for (int i = _rain_fx.Size() - 1; i > -1; i--)
            {
                GDict rf = _rain_fx[i].D;
                if (_time >= (double)rf["until"])
                {
                    _rain_fx.RemoveAt(i);
                    continue;
                }
                if (_time < (double)rf["next"])
                    continue;
                rf["next"] = _time + (low_fx ? 0.12 : 0.05);
                var packed = Stage.Scene("res://assets/kaykit/weapons/arrow_bow.gltf");
                if (packed == null)
                    continue;
                var ang = GD.Randf() * GD.TAU;
                Vector2 to2 = rf["at"].AsVec2() + new Vector2(Math.Cos(ang), Math.Sin(ang)) * Math.Sqrt(GD.Randf()) * (double)rf["r"];
                var to = _Ground(to2, 0.2);
                Node3D arrow = packed.Instantiate() as Node3D;
                arrow.Scale = Vector3.ONE * 1.3;
                var ar = arrow.Rotation;
                ar.x = (float)(GD.PI * 0.5);                   // nose down
                arrow.Rotation = ar;
                AddChild(arrow);
                _fx.Append(GDict.Of("node", arrow, "at", _time, "life", 0.32, "kind", "fall", "p0", to + new Vector3(GD.RandfRange(-1.0, 1.0), 9.0, GD.RandfRange(-1.0, 1.0)), "p1", to));
            }
        }

        public void _SyncAuras()
        {
            // (0.31.201: spell_fx.gd sync_unit, from _sync_kits)
        }

        public void _TowerShot(GDict e)
        {
            Tower tw = sim.moba.towers[(int)e["tw"]];
            GDict mt0 = moba_towers.Get((int)e["tw"], new GDict()).D;
            Vector3 from = !mt0.IsEmpty() ? mt0["top"].AsVec3() : new Vector3(tw.p.x, Sim.HeightAt(tw.p) + 4.4, tw.p.y);   // (its brazier)
            var node = _MakeProjectile("fire");
            node.Position = from;
            if ((int)e.Get("ramp", 0) >= 2)
                node.Scale = Vector3.ONE * (1.0 + 0.2 * (double)(int)e["ramp"]);      // (a tower warmed up on a hero: bigger shots)
            GDict a = actors.Get(GD.Str(e["id"]), new GDict()).D;
            Vector3 to = !a.IsEmpty() && GD.IsInstanceValid(a["root"]) ? a["root"].As<Node3D>().Position + new Vector3(0, 1.1, 0) : from;
            _tshots.Append(GDict.Of("node", node, "from", from, "id", GD.Str(e["id"]), "t0", _time, "flight", (double)e.Get("flight", 0.3), "to", to));
        }

        public void _TowerDown(GDict e)
        {
            // it falls: all but its foot comes down (_tower_stage 4), a blast of rubble and dust
            Tower tw = sim.moba.towers[(int)e["tw"]];
            GDict mt = moba_towers.Get((int)e["tw"], new GDict()).D;
            var gy = Sim.HeightAt(tw.p);
            var at = new Vector3(tw.p.x, gy, tw.p.y);
            if (!mt.IsEmpty())
            {
                mt["ring"].As<Node3D>().Visible = false;
                if ((int)mt["stage"] < 4)
                    _TowerStage(tw, mt, 4, (int)mt["stage"] >= 0);
            }
            _PackExplosion("heavy", at + new Vector3(0, 2.0, 0), 1.6);
            for (int i = 0; i < 3; i++)
                RingAt(at + new Vector3(0, 0.2, 0), new Color("#e0c9a0"), 3.0 + i, 0.7 + i * 0.2);
            _shake = GD.Maxf(_shake, 0.5);
        }

        public void _Animate(GDict a, Unit u, double vel)
        {
            GDict look = LOOKS.Get(GD.Str(a.Get("mlook", "")) != "" ? GD.Str(a.Get("mlook", "")) : u.cls, LOOKS["knight"]).D;
            if (u.state == "dead")
            {
                if (!(bool)a["dead"])
                {
                    a["dead"] = true;
                    if (a.Get("rag").IsNull)
                        _Play(a, "g/Death_A", 1.0, 99.0);       // far off (no ragdoll): the old fall
                }
                return;
            }
            if ((bool)a["dead"])
            {
                a["dead"] = false;
                _RagdollEnd(a);
                a["busy_until"] = 0.0;
            }
            if (_time < (double)a["busy_until"])
                return;
            if (u.stun > 0.0)
                _Play(a, "g/Hit_B", 0.6);
            else if (u.state == "dodge")
                _Play(a, "ma/Dodge_Forward", 1.6, 0.3);
            else if (sim.Whirling(u))
                _Play(a, "m/Melee_2H_Attack_Spinning", 1.8);
            else if (sim.Blocking(u))
                _Play(a, "m/Melee_Blocking");
            else if (u.beam != "")
                _Play(a, "r/Ranged_Magic_Spellcasting_Long");
            else if (vel > 0.6)
                _Play(a, "mb/Running_A", GD.Clampf(vel / 5.2, 0.7, 1.4));
            else
                _Play(a, GD.Str(look["idle"]));
        }

        public GArray ev_log = null;                          // (tools/hitch_bench.gd: what happened, frame by frame)

        public void OnEvent(GDict e)
        {
            if (ev_log != null)
                ev_log.Append(GD.Str(e["k"]) + (e.Has("spell") ? "/" + GD.Str(e["spell"]) : "") + (e.Has("ult") ? "/" + GD.Str(e["ult"]) : ""));
            GDict a = actors.Get(GD.Str(e.Get("id", "")), new GDict()).D;
            switch (GD.Str(e["k"]))
            {
                case "attack":
                {
                    if (a.IsEmpty())
                        return;
                    GDict look = LOOKS.Get(GD.Str(a.Get("mlook", "")) != "" ? GD.Str(a.Get("mlook", "")) : a["cls"], LOOKS["knight"]).D;
                    var clip = GD.Str(e["kind"] == "ability" ? look["ability"] : look["attack"]);
                    if (e["kind"] == "attack" && look.Has("combo"))                  // 0.31.62: the combo's swing
                    {
                        GArray cb = look["combo"].A;
                        clip = GD.Str(cb[(int)e.Get("combo", 0) % cb.Size()]);
                    }
                    _Play(a, clip, 1.7, 0.55);
                    if (e["kind"] == "ability")
                    {
                        Unit qu = sim.by_id.TryGetValue(GD.Str(e["id"]), out var qu0) ? qu0 : null;
                        if (qu != null && a["root"].As<Node3D>().Visible)
                            fxs.Q(sim.AbilityOf(qu), a, qu);        // 0.31.201: the old classes' Q, each its own look
                    }
                    break;
                }
                case "blocked":                                                        // 0.31.62: the shield takes it
                    if (!a.IsEmpty())
                        _Play(a, "m/Melee_Block_Hit", 1.6, 0.3);
                    break;
                case "hit":
                {
                    if (a.IsEmpty() || !a["root"].As<Node3D>().Visible)
                        return;                                    // (0.31.158: nothing shown for a hit in the fog)
                    Spark(a["root"].As<Node3D>().Position + new Vector3(0, 1.3, 0), new Color("#ffd27a"));
                    Unit hu = sim.by_id.TryGetValue(GD.Str(e["id"]), out var hu0) ? hu0 : null;
                    if (hu != null)
                    {
                        Unit src = sim.by_id.TryGetValue(GD.Str(e.Get("by", "")), out var src0) ? src0 : null;
                        BloodHit(hu.pos, src != null ? src.pos : hu.pos - Vector2.FromAngle(hu.face), (double)e.Get("dmg", 20));
                    }
                    Number(a["root"].As<Node3D>().Position + new Vector3(0, 2.2, 0), GD.Str(e["dmg"]), e["id"] == player_id);
                    if (_time >= (double)a["busy_until"])
                    {
                        a["hit_flip"] = !(bool)a.Get("hit_flip", false);      // 0.31.62: the two flinches take turns
                        _Play(a, (bool)a["hit_flip"] ? "g/Hit_B" : "g/Hit_A", 1.4, 0.3);
                    }
                    break;
                }
                case "death":
                {
                    Unit du = sim.by_id.TryGetValue(GD.Str(e.Get("id", "")), out var du0) ? du0 : null;
                    if (du != null)
                        BloodPool(du.pos);
                    if (!a.IsEmpty() && a["root"].As<Node3D>().Visible)
                    {
                        // (0.31.161: everyone's weapons fly out again -- Kevin: "I want the minions weapons to fly out of hands";
                        // not for a body hidden in the 5v5's fog: nothing to see, and it isn't moved while hidden)
                        Var pa = e.Get("push", GArray.Of(0.0, 1.6, 0.0));
                        var push = pa.Size() >= 3 ? new Vector3((double)pa[0], (double)pa[1], (double)pa[2]) : new Vector3(0.0, 1.6, 0.0);
                        _DropWeapons(a, push);
                        _Ragdoll(a, push);
                    }
                    break;
                }
                case "spawn":
                    if (!a.IsEmpty())
                    {
                        a["root"].As<Node3D>().Position = new Vector3(sim.by_id[GD.Str(e["id"])].pos.x, 0, sim.by_id[GD.Str(e["id"])].pos.y);
                        RingAt(a["root"].As<Node3D>().Position, TEAM_COLORS[Vt(sim.by_id[GD.Str(e["id"])].team)], 1.6, 0.6);
                    }
                    break;
                case "vanish":
                    if (sim.by_id.ContainsKey(GD.Str(e["id"])))
                        sim.by_id[GD.Str(e["id"])].vanish_until = (double)e["until"];
                    if (!a.IsEmpty() && a["root"].As<Node3D>().Visible)
                        fxs.Q("vanish", a, sim.by_id[GD.Str(e["id"])]);
                    break;
                case "unvanish":
                    if (sim.by_id.ContainsKey(GD.Str(e["id"])))
                        sim.by_id[GD.Str(e["id"])].vanish_until = sim.time;
                    break;
                case "meteor_warn":
                    _MeteorWarn(e["pos"].AsVec2(), (double)e["delay"], (int)e["team"]);
                    fxs.Event(e);
                    break;
                case "meteor_hit":
                    _recent_blasts.Append(GArray.Of(e["pos"], _time));
                    _MeteorHit(e["pos"].AsVec2(), (double)e["burn"]);
                    fxs.Event(e);
                    break;
                case "pierce_hit":
                case "nova":
                case "resurrect":
                case "sanctuary":
                case "boom":
                case "block_up":
                case "dodge":
                case "proj":
                    fxs.Event(e);                                          // 0.31.201: spell_fx.gd event
                    break;
                case "gate_hit":
                {
                    Gate g = sim.gates[(int)e["gate"]];
                    Vector2 gp = g.c + new Vector2(GD.RandfRange(-1.0, 1.0), 0.0);
                    var gy = Sim.HeightAt(g.c);
                    Spark(new Vector3(gp.x, gy + 1.4 + GD.Randf() * 1.2, gp.y), new Color("#e8d6b0"));
                    if (GD.Randf() < 0.35)
                        Number(new Vector3(g.c.x, gy + 3.2, g.c.y), GD.Str(e["dmg"]), false);
                    break;
                }
                case "gate_broken":
                {
                    Gate g2 = sim.gates[(int)e["gate"]];
                    var gy2 = Sim.HeightAt(g2.c);
                    for (int i = 0; i < 3; i++)
                        RingAt(new Vector3(g2.c.x, gy2 + 0.2, g2.c.y), new Color("#e0c9a0"), 2.5 + i, 0.7 + i * 0.2);
                    for (int i = 0; i < 12; i++)
                        Spark(new Vector3(g2.c.x + GD.RandfRange(-2, 2), gy2 + 0.5 + GD.Randf() * 2.5, g2.c.y + GD.RandfRange(-1, 1)), new Color("#c8b89a"));
                    break;
                }
                case "tower_hit":
                {
                    // 0.31.177 (Kevin: "towers aren't targetable"): a hit on a tower shows -- chips of stone off the side it came
                    // from, and the damage over it when it's yours
                    GDict mt = moba_towers.Get((int)e["tw"], new GDict()).D;
                    if (mt.IsEmpty() || sim.moba == null)
                        return;
                    Vector2 twp = sim.moba.towers[(int)e["tw"]].p;
                    Unit by_u = sim.by_id.TryGetValue(GD.Str(e.Get("by", "")), out var by0) ? by0 : null;
                    var side = by_u != null ? (by_u.pos - twp).Normalized() : Vector2.ZERO;
                    var ty = Sim.HeightAt(twp);
                    var chip = new Vector3(twp.x + side.x * Moba.TOWER_R, ty + 1.0 + GD.Randf() * 1.6, twp.y + side.y * Moba.TOWER_R);
                    Spark(chip, new Color("#e8d6b0"));
                    if (GD.Str(e.Get("by", "")) == player_id)
                    {
                        Spark(chip, new Color("#ffd27a"));
                        Number(mt["top"].AsVec3() + new Vector3(0, 1.1, 0), GD.Str(e["dmg"]), false);
                    }
                    break;
                }
                case "recall_done":                            // 0.31.181: gone from there, here now
                {
                    Unit ru = sim.by_id.TryGetValue(GD.Str(e.Get("id", "")), out var ru0) ? ru0 : null;
                    if (!a.IsEmpty() && ru != null)
                    {
                        a["root"].As<Node3D>().Position = new Vector3(ru.pos.x, Sim.HeightAt(ru.pos), ru.pos.y);     // (no gliding across the map)
                        if (GD.Str(e["id"]) == player_id)
                            SnapCamera();                       // (has_method("snap_camera"): it's this class's own)
                    }
                    foreach (var key in new[] { "from", "to" })
                    {
                        Vector2 rp = e.Get(key, Vector2.ZERO).AsVec2();
                        var ry = Sim.HeightAt(rp);
                        RingAt(new Vector3(rp.x, ry + 0.1, rp.y), RECALL_COL, 2.6, 0.7);
                        for (int i = 0; i < 10; i++)
                            Spark(new Vector3(rp.x + GD.RandfRange(-0.6, 0.6), ry + 0.3 + GD.Randf() * 2.2, rp.y + GD.RandfRange(-0.6, 0.6)), RECALL_COL);
                    }
                    break;
                }
                case "tshot":
                    _TowerShot(e);                        // 0.31.155 5V5
                    break;
                case "tower_down":
                    _TowerDown(e);
                    break;
                case "king_slam":
                {
                    Vector2 kp = sim.moba.KingPos((int)e["team"]);              // 0.31.156 5V5: the King hits back
                    var ky = Sim.HeightAt(kp);
                    RingAt(new Vector3(kp.x, ky + 0.2, kp.y), new Color("#ffd65a"), Moba.KING_REACH, 0.5);
                    for (int i = 0; i < 6; i++)
                        Spark(new Vector3(kp.x + GD.RandfRange(-1.5, 1.5), ky + 0.4 + GD.Randf() * 1.0, kp.y + GD.RandfRange(-1.5, 1.5)), new Color("#ffd65a"));
                    break;
                }
                case "spell":
                case "slam":
                case "pillar":
                case "trap_snap":
                case "trap_gone":
                case "burst":
                case "zap":
                case "riposte":
                    _KitFx(e);                            // 0.31.167 5V5: W and E (0.31.168: the new heroes' bursts, bolts, ripostes)
                    break;
                case "ult":
                case "flurry_hit":
                case "lord_slam":
                case "camp_up":
                case "buff":
                case "lord_down":
                case "gold":
                case "lord_march":
                case "ward":
                case "wyrm_breath":
                case "wyrm_down":
                    _MobaFx(e);                           // 0.31.157 5V5: ultimates, the jungle, gold (0.31.166: the Wyrm; and the
                                                          // Lord's march and a placed ward, whose effects were never reached)
                    break;
                case "king_down":
                {
                    Vector2 kd = sim.moba.KingPos((int)e["team"]);
                    var kdy = Sim.HeightAt(kd);
                    _PackExplosion("heavy", new Vector3(kd.x, kdy + 1.6, kd.y), 1.8);
                    for (int i = 0; i < 3; i++)
                        RingAt(new Vector3(kd.x, kdy + 0.2, kd.y), new Color("#ffd65a"), 3.0 + i * 1.5, 0.8 + i * 0.2);
                    _shake = GD.Maxf(_shake, 0.8);
                    break;
                }
            }
        }
        // ---------- the Kings ----------
        // Each side's KING on his throne, the heart of its base (models 0.20.2, Kevin). The model isn't rigged, so he's
        // animated by hand: breathing and a sway. Kevin named them kingT1 / kingT2; matched by robe colour: T2 (purple) leads
        // blue, T1 (red) leads red. (Internal names -- sim.oracles, oracle_nodes -- stay: players never see them.)
        public const double KING_HEIGHT = 2.6;              // the Knight hero is 2.54; the king a touch taller (and much wider)

        public GDict _MakeOracle(int team)
        {
            var root = new Node3D();
            AddChild(root);
            var body = new Node3D();                     // the part that breathes and sways
            root.AddChild(body);
            var packed = Stage.Scene(GD.Fmt("res://assets/kings/king_%s_fat.glb", Vt(team) == 0 ? "blue" : "red"));
            Node3D m = packed != null ? packed.Instantiate() as Node3D : new Node3D();
            m.Scale = Vector3.ONE * (KING_HEIGHT / 1.9);          // the models are 1.9 tall, feet at 0
            foreach (var mi in m.FindChildren("*", "MeshInstance3D", true, false))
                (mi as MeshInstance3D).CastShadow = _Hq() ? GeometryInstance3D.SHADOW_CASTING_SETTING_ON : GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            body.AddChild(m);
            var ground_ring = _Decal(Vector3.ZERO, 1.0, TEAM_COLORS[Vt(team)], 0.8);
            ground_ring.Reparent(root, false);
            return GDict.Of("root", root, "body", body, "ground", ground_ring);
        }

        public void _SyncOracles(double dt)
        {
            for (int t = 0; t < 2; t++)
            {
                GDict n = oracle_nodes[t].D;
                Oracle o = sim.oracles[t];
                Node3D root = n["root"].As<Node3D>();
                var target = new Vector3(o.pos.x, Sim.HeightAt(o.pos), o.pos.y);
                // Facing (Kevin: "the king is facing the wall"): on his throne he looks out over his base.
                if (o.pos.DistanceTo(Sim.Throne(t)) < 1.5)
                {
                    var rr = root.Rotation;
                    rr.y = (float)GD.LerpAngle(root.Rotation.y, Sim.AngleOf(Sim.M(t, Keep.GateC(1)) - Sim.Throne(t)), 1.0 - Math.Exp(-dt * 6.0));
                    root.Rotation = rr;
                }
                var pulse = 0.8 + Math.Sin(_time * 4.0) * 0.2;
                n["ground"].As<Node3D>().Scale = new Vector3(pulse, 0.15, pulse);
                root.Position = root.Position.DistanceTo(target) > 5.0 ? target : root.Position.Lerp(target, 1.0 - Math.Exp(-dt * 20.0));
            }
        }
    }
}
