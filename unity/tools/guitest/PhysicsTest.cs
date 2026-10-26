// `guitest physics`: the 3D physics facade (Scene3D/Physics3D.cs, PhysicalBone3D.cs) headless, through a fake backend
// that records what the nodes send and moves bodies itself: the siege view's ragdoll (PhysicalBoneSimulator3D on a
// Skeleton3D, cone / hinge / none bones, joint_constraints set after add_child), a loose weapon (RigidBody3D with a box
// shape at a local transform) and a height-field ground patch, through creation, simulation, the bone poses the
// simulator writes, stop, and freeing. Then the same scene with no backend (bodies stay put). Prints FAIL lines and a
// summary; exit code 1 on any failure.
using System;
using System.Collections.Generic;
using Fatebound.GUI;
using Fatebound.Sim;

namespace GuiTest
{
    public static class PhysicsTest
    {
        sealed class FakeBody
        {
            public CollisionObject3D Node;
            public PhysicsBodyMode Mode;
            public Xform3 X = Xform3.IDENTITY;
            public Vec3 Lv, Av;
            public double Mass, Friction, Bounce, LinDamp, AngDamp, GravityScale = 1;
            public uint Layer, Mask;
            public bool Sleeping, Freed, CanSleep = true;
            public PhysicsShapeInstance[] Shapes = Array.Empty<PhysicsShapeInstance>();
            public FakeBody JointParent;
            public PhysicsJointDesc Joint;
            public int TransformSets, JointSets, JointClears;
            public Xform3? Forced;
            public Xform3 PrevX;           // the state before the last step: what the nodes show after a tick
            public Vec3 PrevLv;
        }

        sealed class FakePhysics : IPhysics3D
        {
            public readonly List<FakeBody> Bodies = new List<FakeBody>();
            public int Steps;
            public object BodyCreate(CollisionObject3D node, World3D world) { var b = new FakeBody { Node = node }; Bodies.Add(b); return b; }
            public void BodyFree(object body)
            {
                var b = (FakeBody)body;
                b.Freed = true;
                foreach (var o in Bodies) if (o.JointParent == b) o.JointParent = null;
                Bodies.Remove(b);
            }
            public void BodySetMode(object body, PhysicsBodyMode mode) => ((FakeBody)body).Mode = mode;
            public void BodySetShapes(object body, PhysicsShapeInstance[] shapes) => ((FakeBody)body).Shapes = shapes;
            public void BodySetTransform(object body, in Xform3 t) { var b = (FakeBody)body; b.X = t; b.TransformSets++; }
            public void BodySetCollision(object body, uint layer, uint mask) { var b = (FakeBody)body; b.Layer = layer; b.Mask = mask; }
            public void BodySetMaterial(object body, double f, double bo) { var b = (FakeBody)body; b.Friction = f; b.Bounce = bo; }
            public void BodySetMass(object body, double m) => ((FakeBody)body).Mass = m;
            public void BodySetGravityScale(object body, double s) => ((FakeBody)body).GravityScale = s;
            public void BodySetDamping(object body, double l, double a) { var b = (FakeBody)body; b.LinDamp = l; b.AngDamp = a; }
            public void BodySetLinearVelocity(object body, Vec3 v) => ((FakeBody)body).Lv = v;
            public void BodySetAngularVelocity(object body, Vec3 v) => ((FakeBody)body).Av = v;
            public void BodySetSleeping(object body, bool s) => ((FakeBody)body).Sleeping = s;
            public void BodySetCanSleep(object body, bool c) => ((FakeBody)body).CanSleep = c;
            public void BodySetContinuousCollision(object body, bool on) { }
            public void BodyApplyImpulse(object body, Vec3 i, Vec3 p) { var b = (FakeBody)body; b.Lv += i / (float)b.Mass; }
            public void BodyApplyTorqueImpulse(object body, Vec3 i) { }
            public void BodyApplyForce(object body, Vec3 f, Vec3 p) { }
            public void BodyApplyTorque(object body, Vec3 t) { }
            public bool BodyGetState(object body, out PhysicsBodyState s)
            {
                var b = (FakeBody)body;
                s = new PhysicsBodyState { Transform = b.X, LinearVelocity = b.Lv, AngularVelocity = b.Av, Sleeping = b.Sleeping };
                return true;
            }
            public void BodySetJoint(object body, object parent, in PhysicsJointDesc j) { var b = (FakeBody)body; b.JointParent = (FakeBody)parent; b.Joint = j; b.JointSets++; }
            public void BodyClearJoint(object body) { var b = (FakeBody)body; b.JointParent = null; b.JointClears++; }
            public void Step(double dt)
            {
                Steps++;
                foreach (var b in Bodies)
                {
                    b.PrevX = b.X;
                    b.PrevLv = b.Lv;
                    if (b.Mode != PhysicsBodyMode.Rigid || b.Sleeping) continue;
                    if (b.Forced.HasValue) { b.X = b.Forced.Value; continue; }
                    b.Lv += new Vec3(0f, (float)(-9.8 * b.GravityScale * dt), 0f);
                    b.X.origin += b.Lv * (float)dt;
                }
            }
            public FakeBody Of(CollisionObject3D n) => n.PhysicsBackendData as FakeBody;
        }

        static int _fails, _checks;

        static void Check(string what, bool ok)
        {
            _checks++;
            if (ok) return;
            _fails++;
            Console.WriteLine("FAIL " + what);
        }

        static bool Near(float a, float b, float eps = 1e-4f) => Math.Abs(a - b) <= eps;
        static bool Near(Vec3 a, Vec3 b, float eps = 1e-4f) => Near(a.x, b.x, eps) && Near(a.y, b.y, eps) && Near(a.z, b.z, eps);
        static bool Near(Xform3 a, Xform3 b, float eps = 1e-4f) =>
            Near(a.origin, b.origin, eps) && Near(a.basis.GetColumn(0), b.basis.GetColumn(0), eps) && Near(a.basis.GetColumn(1), b.basis.GetColumn(1), eps) && Near(a.basis.GetColumn(2), b.basis.GetColumn(2), eps);
        static bool Near(Basis a, Basis b, float eps = 1e-4f) => Near(a.GetColumn(0), b.GetColumn(0), eps) && Near(a.GetColumn(1), b.GetColumn(1), eps) && Near(a.GetColumn(2), b.GetColumn(2), eps);
        static Vec3 V(double x, double y, double z) => new Vec3((float)x, (float)y, (float)z);
        static float Rad(double deg) => GD.DegToRadF((float)deg);

        // the siege view's RAG_SPEC, trimmed: bone, child (for the length), radius, joint (0 none, 1 cone, 2 hinge), mass
        static readonly object[][] SPEC =
        {
            new object[] { "hips", "spine", 0.24, 0, 3.0 }, new object[] { "chest", "head", 0.27, 1, 3.0 }, new object[] { "head", "", 0.4, 1, 2.0 },
            new object[] { "upperarm.l", "lowerarm.l", 0.08, 1, 0.6 }, new object[] { "lowerarm.l", "wrist.l", 0.07, 2, 0.5 },
        };

        sealed class Scene
        {
            public Node3D View;
            public Node3D Body;
            public Skeleton3D Skel;
            public PhysicalBoneSimulator3D Sim;
            public readonly List<PhysicalBone3D> Bones = new List<PhysicalBone3D>();
            public StaticBody3D Ground;
            public RigidBody3D Weapon;
            public Node3D WeaponMesh;
        }

        static Skeleton3D MakeSkeleton()
        {
            var sk = new Skeleton3D { Name = "Skeleton3D" };
            void Bone(string n, string parent, Vec3 o)
            {
                int i = sk.AddBone(n);
                if (parent != null) sk.SetBoneParent(i, sk.FindBone(parent));
                sk.SetBoneRest(i, new Xform3(Basis.IDENTITY, o));
            }
            Bone("hips", null, V(0, 0.9, 0));
            Bone("spine", "hips", V(0, 0.2, 0));
            Bone("chest", "spine", V(0, 0.25, 0));
            Bone("head", "chest", V(0, 0.35, 0));
            Bone("upperarm.l", "chest", V(0.15, 0.2, 0));
            Bone("lowerarm.l", "upperarm.l", V(0.28, 0, 0));
            Bone("wrist.l", "lowerarm.l", V(0.25, 0, 0));
            sk.ResetBonePoses();
            // a pose that isn't the rest (the animation's): the arm raised, the chest turned
            sk.SetBonePoseRotation(sk.FindBone("upperarm.l"), new Quat(V(0, 0, 1), 0.6));
            sk.SetBonePoseRotation(sk.FindBone("chest"), new Quat(V(0, 1, 0), 0.3));
            return sk;
        }

        static Scene Build(SceneTree tree)
        {
            var s = new Scene();
            s.View = new Node3D { Name = "View" };
            tree.Root.AddChild(s.View);
            s.Body = new Node3D { Name = "Body", Position = V(3, 0, -2) };
            s.Body.RotateY(0.7);
            s.View.AddChild(s.Body);
            s.Skel = MakeSkeleton();
            s.Body.AddChild(s.Skel);
            tree.Iterate(1.0 / 60.0);

            // _ground_patch
            var hm = new HeightMapShape3D { MapWidth = 5, MapDepth = 5 };
            var data = new float[25];
            for (int i = 0; i < 25; i++) data[i] = 0.01f * i;
            hm.MapData = data;
            s.Ground = new StaticBody3D { Name = "Ground" };
            var gcs = new CollisionShape3D { Shape = hm };
            s.Ground.AddChild(gcs);
            s.Ground.Position = V(3, 0, -2);
            s.Ground.PhysicsMaterialOverride = new Fatebound.GUI.PhysicsMaterial();
            s.Ground.PhysicsMaterialOverride.Friction = 0.9;
            s.View.AddChild(s.Ground);

            // _ragdoll
            s.Sim = new PhysicalBoneSimulator3D();
            s.Skel.AddChild(s.Sim);
            foreach (var sp in SPEC)
            {
                string bn = (string)sp[0], cn = (string)sp[1];
                int bi = s.Skel.FindBone(bn);
                double length = 0.6;
                Vec3 dir = Vec3.UP;
                if (cn != "")
                {
                    int ci = s.Skel.FindBone(cn);
                    Vec3 co = s.Skel.GetBoneRest(ci).origin;
                    length = Math.Max(co.Length(), 0.05);
                    dir = co / (float)length;
                }
                var pb = new PhysicalBone3D { BoneName = bn };
                var basis = dir.DistanceTo(Vec3.UP) > 0.001f ? new Basis(new Quat(Vec3.UP, dir)) : Basis.IDENTITY;
                double reach = bn != "head" ? length * 0.5 : 0.42;
                pb.BodyOffset = new Xform3(basis, dir * (float)reach);
                pb.JointOffset = new Xform3(Basis.IDENTITY, V(0, -reach, 0));
                var cs = new CollisionShape3D();
                double r = (double)sp[2];
                if (bn == "head") cs.Shape = new SphereShape3D { Radius = r };
                else cs.Shape = new CapsuleShape3D { Radius = r, Height = Math.Max(length, r * 2.0 + 0.02) };
                pb.AddChild(cs);
                pb.Mass = (double)sp[4];
                pb.Friction = 0.85;
                pb.Bounce = 0.05;
                pb.LinearDamp = 0.6;
                pb.AngularDamp = 1.6;
                int jt = (int)sp[3];
                pb.JointType = jt == 1 ? PhysicalBone3D.JOINT_TYPE_CONE : jt == 2 ? PhysicalBone3D.JOINT_TYPE_HINGE : PhysicalBone3D.JOINT_TYPE_NONE;
                s.Sim.AddChild(pb);
                if (jt == 1)
                {
                    pb.Set("joint_constraints/swing_span", 50.0);
                    pb.Set("joint_constraints/twist_span", 25.0);
                }
                else if (jt == 2)
                {
                    pb.Set("joint_constraints/angular_limit_enabled", true);
                    pb.Set("joint_constraints/angular_limit_upper", 0.0);
                    pb.Set("joint_constraints/angular_limit_lower", -110.0);
                }
                s.Bones.Add(pb);
            }

            // _drop_weapons
            s.Weapon = new RigidBody3D { Name = "Weapon" };
            s.WeaponMesh = new Node3D { Name = "Mesh" };
            s.Weapon.AddChild(s.WeaponMesh);
            var wcs = new CollisionShape3D { Shape = new BoxShape3D { Size = V(0.1, 0.8, 0.1) }, Transform = new Xform3(new Basis(V(1, 0, 0), 0.4), V(0, 0.3, 0)) };
            s.Weapon.AddChild(wcs);
            s.Weapon.Mass = 0.8;
            s.Weapon.PhysicsMaterialOverride = new Fatebound.GUI.PhysicsMaterial();
            s.Weapon.PhysicsMaterialOverride.Bounce = 0.2;
            s.Weapon.PhysicsMaterialOverride.Friction = 0.7;
            s.View.AddChild(s.Weapon);
            s.Weapon.GlobalPosition = V(3.2, 1.4, -2.1);
            s.Weapon.LinearVelocity = V(0.5, 1.5, 0);
            s.Weapon.AngularVelocity = V(1, 2, 3);
            return s;
        }

        static PhysicalBone3D Pb(Scene s, string bone) => s.Bones.Find(b => b.BoneName == bone);

        static Xform3 RestPose(Scene s, PhysicalBone3D pb) =>
            (s.Skel.GlobalTransform * s.Skel.GetBoneGlobalPose(pb.GetBoneId()) * pb.BodyOffset).Orthonormalized();

        public static int Run()
        {
            _fails = _checks = 0;
            var fake = new FakePhysics();
            PhysicsServer3D.Backend = fake;
            try { RunWithBackend(fake); }
            finally { PhysicsServer3D.Backend = null; }
            RunHeadless();
            Console.WriteLine(_fails == 0 ? "physics: all " + _checks + " checks pass" : "physics: " + _fails + " of " + _checks + " checks FAIL");
            return _fails == 0 ? 0 : 1;
        }

        static void RunWithBackend(FakePhysics fake)
        {
            var tree = new SceneTree(new Vec2(100, 100));
            var s = Build(tree);
            tree.Iterate(1.0 / 120.0);           // (no physics tick yet: the transforms flush at the frame's end)

            // ---- bodies as made
            Check("bodies made (ground + 5 bones + weapon)", fake.Bodies.Count == 7 && PhysicsServer3D.BodyCount == 7);
            var g = fake.Of(s.Ground);
            Check("ground static", g != null && g.Mode == PhysicsBodyMode.Static);
            Check("ground material friction 0.9 bounce 0", g != null && Near((float)g.Friction, 0.9f) && g.Bounce == 0);
            Check("ground shape is the height map", g != null && g.Shapes.Length == 1 && g.Shapes[0].Shape is HeightMapShape3D);
            Check("ground transform", g != null && Near(g.X.origin, V(3, 0, -2)));
            var hmShape = (HeightMapShape3D)s.Ground.ShapeOwnerGetShape(0, 0);
            Check("height map data, min/max", hmShape.MapDataRaw.Length == 25 && Near((float)hmShape.GetMaxHeight(), 0.24f) && hmShape.GetMinHeight() == 0);

            var w = fake.Of(s.Weapon);
            Check("weapon rigid", w != null && w.Mode == PhysicsBodyMode.Rigid);
            Check("weapon mass / material", w != null && Near((float)w.Mass, 0.8f) && Near((float)w.Friction, 0.7f) && Near((float)w.Bounce, 0.2f));
            Check("weapon damping = the world's default 0.1 (COMBINE)", w != null && Near((float)w.LinDamp, 0.1f) && Near((float)w.AngDamp, 0.1f));
            Check("weapon velocities sent", w != null && Near(w.Lv, V(0.5, 1.5, 0)) && Near(w.Av, V(1, 2, 3)));
            Check("weapon transform (global_position after add_child)", w != null && Near(w.X.origin, V(3.2, 1.4, -2.1)));
            Check("weapon box shape at its local transform", w != null && w.Shapes.Length == 1 && w.Shapes[0].Shape is BoxShape3D && Near(w.Shapes[0].Transform.origin, V(0, 0.3, 0)));

            foreach (var pb in s.Bones)
            {
                var fb = fake.Of(pb);
                Check(pb.BoneName + ": kinematic, layer 1/1", fb != null && fb.Mode == PhysicsBodyMode.Kinematic && fb.Layer == 1 && fb.Mask == 1);
                Check(pb.BoneName + ": bound", pb.GetBoneId() == s.Skel.FindBone(pb.BoneName) && s.Sim.GetPhysicalBone(pb.GetBoneId()) == pb);
                Check(pb.BoneName + ": at its bone (rest position)", Near(pb.GlobalTransform, RestPose(s, pb)));
                Check(pb.BoneName + ": body at the node", fb != null && Near(fb.X, pb.GlobalTransform));
                Check(pb.BoneName + ": joint_offset origin = body_offset^-1", Near(pb.JointOffset.origin, pb.BodyOffset.AffineInverse().origin));
                Check(pb.BoneName + ": damping 0.7 / 1.7", fb != null && Near((float)fb.LinDamp, 0.7f) && Near((float)fb.AngDamp, 1.7f));
                Check(pb.BoneName + ": friction / bounce / mass", fb != null && Near((float)fb.Friction, 0.85f) && Near((float)fb.Bounce, 0.05f) && fb.Mass > 0);
            }

            var hips = Pb(s, "hips");
            var chest = Pb(s, "chest");
            var head = Pb(s, "head");
            var upper = Pb(s, "upperarm.l");
            var lower = Pb(s, "lowerarm.l");
            Check("hips: no joint", fake.Of(hips).JointParent == null && fake.Of(hips).JointSets == 0);
            Check("chest: cone to hips (spine has no body)", fake.Of(chest).JointParent == fake.Of(hips) && fake.Of(chest).Joint.Type == PhysicalBone3D.JOINT_TYPE_CONE);
            Check("chest: swing 50, twist 25 (radians)", Near(fake.Of(chest).Joint.SwingSpan, Rad(50)) && Near(fake.Of(chest).Joint.TwistSpan, Rad(25)));
            Check("head: cone to chest", fake.Of(head).JointParent == fake.Of(chest));
            Check("upperarm: cone to chest", fake.Of(upper).JointParent == fake.Of(chest));
            Check("lowerarm: hinge to upperarm", fake.Of(lower).JointParent == fake.Of(upper) && fake.Of(lower).Joint.Type == PhysicalBone3D.JOINT_TYPE_HINGE);
            var hj = fake.Of(lower).Joint;
            Check("lowerarm: limits on, upper 0, lower -110", hj.AngularLimitEnabled && Near(hj.AngularLimitUpper, 0) && Near(hj.AngularLimitLower, Rad(-110)));
            foreach (var pb in new[] { chest, head, upper, lower })
            {
                var j = fake.Of(pb).Joint;
                var parent = (PhysicalBone3D)fake.Of(pb).JointParent.Node;
                Check(pb.BoneName + ": joint frames coincide (rest pose)", Near(parent.GlobalTransform * j.FrameA, pb.GlobalTransform * j.FrameB, 2e-4f));
            }
            var shifted = hj.HingeFrameA(out float half, out bool fixd);
            Check("hinge: Jolt's shift, +-55 about Z", Near(half, Rad(55)) && !fixd && Near(shifted.basis, hj.FrameA.basis * new Basis(V(0, 0, 1), Rad(55))));
            hj.ConeLimits(out float sw0, out float tw0);
            var cone = fake.Of(chest).Joint;
            cone.ConeLimits(out float sw, out float tw);
            Check("cone limits pass through", Near(sw, Rad(50)) && Near(tw, Rad(25)));
            Check("stored properties read back in degrees", Near((float)chest.Get("joint_constraints/swing_span").AsFloat(), 50f, 1e-3f) &&
                  Near((float)lower.Get("joint_constraints/angular_limit_lower").AsFloat(), -110f, 1e-3f) && lower.Get("joint_constraints/angular_limit_enabled").Truthy);
            Check("defaults (hinge softness 0.9, cone bias 0.3)", Near((float)lower.Get("joint_constraints/angular_limit_softness").AsFloat(), 0.9f) && Near((float)chest.Get("joint_constraints/bias").AsFloat(), 0.3f));
            Check("Get of a plain property", Near((float)chest.Get("mass").AsFloat(), 3f));
            int chestJointSets = fake.Of(chest).JointSets;
            chest.Set("joint_constraints/swing_span", 40.0);
            Check("a joint param after the joint is made re-sends it", fake.Of(chest).JointSets == chestJointSets + 1 && Near(fake.Of(chest).Joint.SwingSpan, Rad(40)));
            chest.Set("joint_constraints/swing_span", 50.0);

            // ---- the bones follow the animation while not simulated
            s.Skel.SetBonePoseRotation(s.Skel.FindBone("upperarm.l"), new Quat(V(0, 0, 1), 0.9));
            tree.Iterate(1.0 / 120.0);
            Check("kinematic bone follows the animated pose", Near(upper.GlobalTransform, RestPose(s, upper)));
            Check("... and its body is moved there", Near(fake.Of(upper).X, upper.GlobalTransform));

            // ---- simulate
            var animatedChest = RestPose(s, chest);
            s.Sim.PhysicalBonesStartSimulation();
            Check("simulator simulating", s.Sim.IsSimulatingPhysics());
            foreach (var pb in s.Bones)
            {
                Check(pb.BoneName + ": rigid, top level, simulating", fake.Of(pb).Mode == PhysicsBodyMode.Rigid && pb.TopLevel && pb.IsSimulatingPhysics());
                pb.LinearVelocity = V(0, 0.5, 0);
            }
            Check("velocity after start reaches the body", Near(fake.Of(hips).Lv, V(0, 0.5, 0)));
            Check("start keeps the bone where the animation had it", Near(chest.GlobalTransform, animatedChest));
            var forced = new Xform3(new Basis(V(1, 0, 0), 0.5) * animatedChest.basis, animatedChest.origin + V(0.1, 0.4, 0));
            fake.Of(chest).Forced = forced;
            Xform3? shown = null;
            int chestBone = s.Skel.FindBone("chest"), spineBone = s.Skel.FindBone("spine");
            Xform3 shownSpine = Xform3.IDENTITY, shownHips = Xform3.IDENTITY;
            s.Skel.SkeletonUpdated += () =>
            {
                shown = s.Skel.GetBoneGlobalPose(chestBone);
                shownSpine = s.Skel.GetBoneGlobalPose(spineBone);
                shownHips = s.Skel.GetBoneGlobalPose(s.Skel.FindBone("hips"));
            };
            long steps0 = PhysicsServer3D.StepCount;
            tree.Iterate(1.0 / 60.0);        // tick 1: nothing to read yet, step
            Check("first tick: no state read before a step", Near(chest.GlobalTransform, animatedChest));
            int chestSets = fake.Of(chest).TransformSets;   // (the top-level switch's own TRANSFORM_CHANGED went out in tick 1)
            tree.Iterate(1.0 / 60.0);        // tick 2: read the step, step again; the skeleton's modification shows it
            Check("stepped twice", PhysicsServer3D.StepCount == steps0 + 2 && fake.Steps >= 2);
            Check("bone body took the backend's transform", Near(chest.GlobalTransform, forced));
            Check("... without sending it back", fake.Of(chest).TransformSets == chestSets);
            Check("simulator holds the bone pose", Near(s.Sim.GetBoneGlobalPose(chestBone), s.Skel.GlobalTransform.AffineInverse() * (forced * chest.BodyOffset.AffineInverse()), 2e-4f));
            Check("skeleton shows the simulated chest", shown.HasValue && Near(shown.Value, s.Skel.GlobalTransform.AffineInverse() * (forced * chest.BodyOffset.AffineInverse()), 2e-4f));
            Check("a bone without a body keeps its pose relative to its (simulated) parent",
                  Near(shownSpine, shownHips * s.Skel.GetBonePose(spineBone), 2e-4f));
            Check("falling hips: velocity read back (the step before the last, as Godot)", hips.LinearVelocity.y < 0.5f && Near(hips.LinearVelocity, fake.Of(hips).PrevLv));
            Check("skeleton's own poses restored after the frame (animation unchanged)", Near(s.Skel.GetBonePose(chestBone).basis, new Basis(new Quat(V(0, 1, 0), 0.3))));

            // ---- the loose weapon
            Check("weapon follows its body", Near(s.Weapon.GlobalTransform, fake.Of(s.Weapon).PrevX) && s.Weapon.GlobalPosition.x > 3.2f);
            Check("its mesh child follows", Near(s.WeaponMesh.GlobalPosition, s.Weapon.GlobalPosition));
            int slept = 0;
            s.Weapon.SleepingStateChanged += () => slept++;
            fake.Of(s.Weapon).Sleeping = true;
            tree.Iterate(1.0 / 60.0);
            Check("sleeping_state_changed", slept == 1 && s.Weapon.Sleeping);
            s.Weapon.Sleeping = false;
            Check("waking reaches the body", !fake.Of(s.Weapon).Sleeping);
            s.Weapon.LinearVelocity += V(0, 3, 0);
            Check("linear_velocity += reads the synced value", Near(fake.Of(s.Weapon).Lv, s.Weapon.LinearVelocity));

            // ---- paused: nothing steps
            long st = PhysicsServer3D.StepCount;
            tree.Paused = true;
            tree.Iterate(1.0 / 60.0);
            Check("paused tree doesn't step", PhysicsServer3D.StepCount == st);
            tree.Paused = false;

            // ---- stop
            fake.Of(chest).Forced = null;
            s.Sim.PhysicalBonesStopSimulation();
            foreach (var pb in s.Bones)
                Check(pb.BoneName + ": kinematic again, not top level", fake.Of(pb).Mode == PhysicsBodyMode.Kinematic && !pb.TopLevel && !pb.IsSimulatingPhysics());
            tree.Iterate(1.0 / 60.0);
            Check("stopped bones go back to the animated pose", Near(chest.GlobalTransform, RestPose(s, chest)) && Near(upper.GlobalTransform, RestPose(s, upper)));

            // ---- simulator inactive: bones static without collision
            s.Sim.Active = false;
            Check("inactive simulator: bones static, layer 0/0", fake.Of(chest).Mode == PhysicsBodyMode.Static && fake.Of(chest).Layer == 0 && fake.Of(chest).Mask == 0);
            Check("... node's collision layer unchanged", chest.CollisionLayer == 1);
            s.Sim.Active = true;

            // ---- free (_ragdoll_end and the debris timeout)
            var lowerBody = fake.Of(lower);
            s.Sim.QueueFree();
            s.Ground.QueueFree();
            s.Weapon.QueueFree();
            tree.Iterate(1.0 / 60.0);
            Check("all bodies freed", fake.Bodies.Count == 0 && PhysicsServer3D.BodyCount == 0);
            Check("joints cleared as the bones left", lowerBody.Freed && lowerBody.JointClears >= 1);
            Check("freed simulator no longer follows the skeleton", s.Sim.IsFreed && s.Sim.GetBoneCount() >= 0);
            s.Skel.SetBonePoseRotation(chestBone, new Quat(V(0, 1, 0), 0.1));
            tree.Iterate(1.0 / 60.0);          // (a freed simulator's handlers must not run)
            s.View.QueueFree();
            tree.Iterate(1.0 / 60.0);
        }

        static void RunHeadless()
        {
            var tree = new SceneTree(new Vec2(100, 100));
            var s = Build(tree);
            tree.Iterate(1.0 / 60.0);
            var chest = Pb(s, "chest");
            Check("headless: no backend bodies", chest.PhysicsBackendData == null && PhysicsServer3D.BodyCount == 0);
            Check("headless: bone at its rest position", Near(chest.GlobalTransform, RestPose(s, chest)));
            s.Sim.PhysicalBonesStartSimulation();
            var at = chest.GlobalTransform;
            var wAt = s.Weapon.GlobalTransform;
            for (int i = 0; i < 10; i++) tree.Iterate(1.0 / 60.0);
            Check("headless: simulated bones stay put", chest.IsSimulatingPhysics() && Near(chest.GlobalTransform, at));
            Check("headless: weapon stays put", Near(s.Weapon.GlobalTransform, wAt));
            Check("headless: stored property", Near((float)chest.Get("joint_constraints/twist_span").AsFloat(), 25f, 1e-3f));
            s.Sim.PhysicalBonesStopSimulation();
            s.View.QueueFree();
            tree.Iterate(1.0 / 60.0);
        }
    }
}
