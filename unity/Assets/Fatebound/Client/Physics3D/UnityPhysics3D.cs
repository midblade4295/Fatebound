// Fatebound (Unity port): simulates the engine-free 3D physics nodes (GUI/Scene3D/Physics3D.cs, PhysicalBone3D.cs)
// with PhysX through Unity -- the facade's PhysicsServer3D backend (Godot's project uses Jolt; these effects -- ragdolls,
// loose weapons, their ground patches -- were never deterministic, so the aim is Godot's semantics, not Jolt's numbers).
//  * Worlds: every World3D gets its own Unity scene with a local 3D physics scene (LocalPhysicsMode.Physics3D), stepped
//    by PhysicsScene.Simulate from the facade's step (Physics.simulationMode = Script: nothing else steps). Bodies of
//    different worlds can't touch, without depending on the renderer's per-world layers (which run out into a shared
//    layer 31) or the global layer collision matrix.
//  * One GameObject per body, flat under its world's root (as Godot's server bodies), no renderers: a Rigidbody always
//    (kinematic for STATIC and KINEMATIC bodies), each enabled shape a child GameObject at its shape transform with its
//    collider: BoxCollider, SphereCollider, CapsuleCollider (Y, height including the caps in both engines), a convex
//    MeshCollider for a cylinder, a MeshCollider for a HeightMapShape3D laid out as Godot/Jolt do (centred, one unit
//    per sample, map_data row-major by depth, the (x+1,z)-(x,z+1) diagonal). Colliders and joints are (re)built
//    lazily, right before the next step.
//  * Coordinates as Conv (mirror X): points/linear velocities (x,y,z) -> (-x,y,z); rotations (x,y,z,w) -> (x,-y,-z,w);
//    angular velocities (pseudo-vectors) (x,y,z) -> (x,-y,-z); joint frames convert like rotations.
//  * Godot/Jolt values: gravity 9.8 down; damping = the facade's totals (COMBINE adds the world's 0.1); friction
//    combines by min (Jolt: |min(f1, f2)|) = PhysicsMaterialCombine.Minimum; bounce combines by sum clamped to 1 in Jolt
//    -- Unity has no sum, Maximum is exact whenever one side is 0 (anything on the ground patches) and close otherwise;
//    max speeds, sleep threshold, contact distance, bounce threshold and solver iterations from Jolt's settings (below).
//  * Joints (PhysicalBone3D): a ConfigurableJoint on the bone's body to its parent bone's, linear motion locked. Its
//    rest pose is the bodies' relative rotation when Unity configures it, so the child is turned for that moment to
//    where the two joint frames coincide (Godot's rest pose by definition) and put back. Cone: twist about frame X
//    (angular X limit +-twist_span), swing cone about Y/Z (+-swing_span). Hinge: about frame Z, made the angular X axis;
//    Jolt's reference shift turns lower/upper into a symmetric +-limit (sign conventions can't flip an elbow). Pin:
//    position only. Slider / 6DOF: not built (warned once). A ragdoll's bones don't collide with each other (Jolt's
//    do; PhysX makes the overlapping capsules jitter -- IgnoreWithinRagdolls).
using System;
using System.Collections.Generic;
using Fatebound.GUI;
using Fatebound.Sim;
using UnityEngine;
using UnityEngine.SceneManagement;
using Object = UnityEngine.Object;
using Quaternion = UnityEngine.Quaternion;
using Vector3 = UnityEngine.Vector3;
using UMesh = UnityEngine.Mesh;
using UPhysicsMaterial = UnityEngine.PhysicsMaterial;

namespace Fatebound.Client
{
    public sealed class UnityPhysics3D : IPhysics3D
    {
        public static UnityPhysics3D Instance { get; private set; }

        // Jolt's simulation settings in Godot 4.7 (physics/jolt_physics_3d/*), as far as PhysX has them
        public static float MaxLinearVelocity = 500f;                         // limits/max_linear_velocity
        public static float MaxAngularVelocity = 2700f * Mathf.Deg2Rad;       // limits/max_angular_velocity (Unity's default is 7 rad/s)
        public static float SleepVelocity = 0.03f;                            // simulation/sleep_velocity_threshold (PhysX: energy/mass 0.5 v^2)
        public static float ContactOffset = 0.02f;                            // simulation/speculative_contact_distance
        public static float BounceThreshold = 1f;                             // simulation/bounce_velocity_threshold
        public static int SolverIterations = 10, SolverVelocityIterations = 2; // velocity_steps 10, position_steps 2
        /// <summary>PhysX pushes overlapping shapes apart at up to 10 m/s by default (ragdoll capsules overlap at the
        /// joints and keep colliding, as in Jolt, whose position correction is gentler); Jolt-like speeds.</summary>
        public static float MaxDepenetrationVelocity = 3f;
        /// <summary>Jolt keeps the bodies of a PhysicalBone3D joint colliding (joint_disable_collisions_between_bodies
        /// is never called); here they don't, nor any two bones of one ragdoll (IgnoreWithinRagdolls).</summary>
        public static bool JointBodiesCollide = false;

        sealed class World
        {
            public World3D Source;
            public Scene Scene;
            public PhysicsScene Physics;
            public GameObject Root;
            public readonly List<Body> Bodies = new List<Body>();
        }

        sealed class Body
        {
            public CollisionObject3D Node;
            public World World;
            public GameObject Go;
            public Transform T;
            public Rigidbody Rb;
            public PhysicsBodyMode Mode = PhysicsBodyMode.Static;
            public PhysicsShapeInstance[] Shapes = Array.Empty<PhysicsShapeInstance>();
            public bool ShapesDirty;
            public readonly List<GameObject> ShapeGos = new List<GameObject>();
            public readonly List<UMesh> OwnedMeshes = new List<UMesh>();
            public UPhysicsMaterial Material;
            public float GravityScale = 1f;
            public bool CanSleep = true, Ccd, WasSleeping, Placed;
            public Vector3 Scale = Vector3.one;
            // a kinematic body's move for the next step (Jolt: kinematic_transform, MoveKinematic in pre_step)
            public bool HasTarget;
            public Vector3 TargetPos;
            public Quaternion TargetRot = Quaternion.identity;
            // joint
            public Body JointParent;
            public PhysicsJointDesc Joint;
            public bool JointDirty;
            public ConfigurableJoint Cj;

            public bool Dynamic => Mode == PhysicsBodyMode.Rigid || Mode == PhysicsBodyMode.RigidLinear;
        }

        readonly Dictionary<World3D, World> _worlds = new Dictionary<World3D, World>();
        readonly List<World> _worldList = new List<World>();
        static readonly Dictionary<(float, float), UMesh> _cylinders = new Dictionary<(float, float), UMesh>();
        static readonly HashSet<string> _warned = new HashSet<string>();
        int _sceneSerial;

        public UnityPhysics3D()
        {
            Instance = this;
            Physics.simulationMode = SimulationMode.Script;     // (transforms set here sync at each Simulate: autoSyncTransforms stays off)
            Vec3 g = PhysicsServer3D.DefaultGravityVector;
            float gs = (float)PhysicsServer3D.DefaultGravity;
            Physics.gravity = Conv.Dir(new Vec3(g.x * gs, g.y * gs, g.z * gs));
            Physics.bounceThreshold = BounceThreshold;
            Physics.defaultContactOffset = ContactOffset;
            Physics.defaultMaxAngularSpeed = MaxAngularVelocity;
            Physics.defaultMaxDepenetrationVelocity = MaxDepenetrationVelocity;
            Physics.defaultSolverIterations = SolverIterations;
            Physics.defaultSolverVelocityIterations = SolverVelocityIterations;
            PhysicsServer3D.Backend = this;
        }

        static void Warn(string what)
        {
            if (_warned.Add(what)) Debug.LogWarning("Fatebound physics: " + what);
        }

        static Vector3 AngularToUnity(Vec3 w) => new Vector3(w.x, -w.y, -w.z);
        static Vec3 AngularToGodot(Vector3 w) => new Vec3(w.x, -w.y, -w.z);
        static Vec3 PosToGodot(Vector3 p) => new Vec3(-p.x, p.y, p.z);
        static Quat RotToGodot(Quaternion q) => new Quat(q.x, -q.y, -q.z, q.w);

        // ------------------------------------------------------------------ worlds
        World GetWorld(World3D w)
        {
            if (_worlds.TryGetValue(w, out var d)) return d;
            var scene = SceneManager.CreateScene("Fatebound physics " + w.Id + "." + (++_sceneSerial), new CreateSceneParameters(LocalPhysicsMode.Physics3D));
            var root = new GameObject("World#" + w.Id + " physics");
            SceneManager.MoveGameObjectToScene(root, scene);
            d = new World { Source = w, Scene = scene, Physics = scene.GetPhysicsScene(), Root = root };
            _worlds[w] = d;
            _worldList.Add(d);
            return d;
        }

        // ------------------------------------------------------------------ bodies
        public object BodyCreate(CollisionObject3D node, World3D world)
        {
            var w = GetWorld(world);
            var go = new GameObject(node.Name);
            go.transform.SetParent(w.Root.transform, false);
            var rb = go.AddComponent<Rigidbody>();
            rb.isKinematic = true;
            rb.useGravity = true;
            rb.interpolation = RigidbodyInterpolation.None;
            rb.collisionDetectionMode = CollisionDetectionMode.Discrete;
            rb.mass = 1f;
            rb.linearDamping = 0f;
            rb.angularDamping = 0f;
            rb.maxLinearVelocity = MaxLinearVelocity;
            rb.maxAngularVelocity = MaxAngularVelocity;
            rb.maxDepenetrationVelocity = MaxDepenetrationVelocity;
            rb.solverIterations = SolverIterations;
            rb.solverVelocityIterations = SolverVelocityIterations;
            rb.sleepThreshold = SleepThreshold(true);
            var mat = new UPhysicsMaterial("body")
            {
                dynamicFriction = 1f, staticFriction = 1f, bounciness = 0f,
                frictionCombine = PhysicsMaterialCombine.Minimum, bounceCombine = PhysicsMaterialCombine.Maximum,
            };
            var b = new Body { Node = node, World = w, Go = go, T = go.transform, Rb = rb, Material = mat };
            w.Bodies.Add(b);
            return b;
        }

        static float SleepThreshold(bool canSleep) => canSleep ? 0.5f * SleepVelocity * SleepVelocity : 0f;

        public void BodyFree(object body)
        {
            var b = (Body)body;
            var w = b.World;
            if (w != null)
            {
                for (int i = 0; i < w.Bodies.Count; i++)
                {
                    var o = w.Bodies[i];
                    if (o.JointParent != b) continue;
                    DestroyJoint(o);
                    o.JointParent = null;
                    o.JointDirty = false;
                }
                w.Bodies.Remove(b);
            }
            DestroyJoint(b);
            b.JointParent = null;
            ClearShapes(b);
            if (b.Go != null)
            {
                b.Go.SetActive(false);              // (out of the simulation now; Destroy waits for the frame's end)
                Object.Destroy(b.Go);
            }
            if (b.Material != null) Object.Destroy(b.Material);
            b.Go = null;
            b.Rb = null;
            b.Material = null;
            b.World = null;
        }

        public void BodySetMode(object body, PhysicsBodyMode mode)
        {
            var b = (Body)body;
            if (b.Mode == mode || b.Rb == null) return;
            b.Mode = mode;
            b.HasTarget = false;
            var rb = b.Rb;
            if (!b.Dynamic)
            {
                rb.collisionDetectionMode = CollisionDetectionMode.Discrete;
                rb.isKinematic = true;
            }
            else
            {
                foreach (var g in b.ShapeGos)                // (a non-convex MeshCollider can't be on a dynamic body)
                    if (g != null && g.TryGetComponent<MeshCollider>(out var mc) && !mc.convex) mc.convex = true;
                rb.isKinematic = false;
                rb.collisionDetectionMode = b.Ccd ? CollisionDetectionMode.ContinuousDynamic : CollisionDetectionMode.Discrete;
                rb.WakeUp();
            }
            rb.constraints = mode == PhysicsBodyMode.RigidLinear ? RigidbodyConstraints.FreezeRotation : RigidbodyConstraints.None;
            b.WasSleeping = false;
        }

        public void BodySetTransform(object body, in Xform3 x)
        {
            var b = (Body)body;
            if (b.Rb == null) return;
            Vec3 s = x.basis.GetScale();
            var scale = new Vector3(s.x, s.y, s.z);
            if (scale != b.Scale && s.x != 0f && s.y != 0f && s.z != 0f)
            {
                b.Scale = scale;
                b.T.localScale = scale;                       // (Jolt scales the shapes by the body's scale)
            }
            var pos = Conv.Pos(x.origin);
            var rot = Conv.Rot(x.basis.GetRotationQuaternion());
            if (b.Mode == PhysicsBodyMode.Kinematic && b.Placed)
            {
                b.HasTarget = true;
                b.TargetPos = pos;
                b.TargetRot = rot;
                return;
            }
            b.T.SetPositionAndRotation(pos, rot);
            b.Rb.position = pos;
            b.Rb.rotation = rot;
            b.Placed = true;
            b.HasTarget = false;
        }

        public void BodySetShapes(object body, PhysicsShapeInstance[] shapes)
        {
            var b = (Body)body;
            b.Shapes = shapes ?? Array.Empty<PhysicsShapeInstance>();
            b.ShapesDirty = true;
        }

        public void BodySetCollision(object body, uint layer, uint mask)
        {
            // Godot: two bodies meet when (a.layer & b.mask) | (b.layer & a.mask). Exact for the game's bodies (1/1, or
            // 0/0 for a physical bone whose simulator is off); other combinations collide with everything.
            var b = (Body)body;
            if (b.Rb != null) b.Rb.detectCollisions = layer != 0 || mask != 0;
        }

        public void BodySetMaterial(object body, double friction, double bounce)
        {
            var m = ((Body)body).Material;
            if (m == null) return;
            float f = Mathf.Abs((float)friction);
            m.dynamicFriction = f;
            m.staticFriction = f;
            m.frictionCombine = friction < 0 ? PhysicsMaterialCombine.Maximum : PhysicsMaterialCombine.Minimum;   // (rough: its own friction wins, roughly)
            m.bounciness = bounce < 0 ? 0f : Mathf.Clamp01((float)bounce);                                     // (absorbent: no bounce)
            m.bounceCombine = bounce < 0 ? PhysicsMaterialCombine.Minimum : PhysicsMaterialCombine.Maximum;
        }

        public void BodySetMass(object body, double mass)
        {
            var b = (Body)body;
            if (b.Rb != null && mass > 0) b.Rb.mass = (float)mass;
        }

        public void BodySetGravityScale(object body, double scale)
        {
            var b = (Body)body;
            b.GravityScale = (float)scale;
            if (b.Rb != null) b.Rb.useGravity = b.GravityScale == 1f;      // (other scales: an acceleration before each step)
        }

        public void BodySetDamping(object body, double linear, double angular)
        {
            var b = (Body)body;
            if (b.Rb == null) return;
            // (PhysX damps after adding gravity, Jolt-in-Godot before: a difference of g*dt*damp*dt a step)
            b.Rb.linearDamping = Mathf.Max(0f, (float)linear);
            b.Rb.angularDamping = Mathf.Max(0f, (float)angular);
        }

        public void BodySetLinearVelocity(object body, Vec3 v)
        {
            var b = (Body)body;
            if (b.Rb != null && b.Dynamic) b.Rb.linearVelocity = Conv.Dir(v);     // (Jolt: on a kinematic body it's a surface velocity)
        }

        public void BodySetAngularVelocity(object body, Vec3 v)
        {
            var b = (Body)body;
            if (b.Rb != null && b.Dynamic) b.Rb.angularVelocity = AngularToUnity(v);
        }

        public void BodySetSleeping(object body, bool sleeping)
        {
            var b = (Body)body;
            if (b.Rb == null || !b.Dynamic) return;
            if (sleeping) b.Rb.Sleep();
            else b.Rb.WakeUp();
        }

        public void BodySetCanSleep(object body, bool canSleep)
        {
            var b = (Body)body;
            b.CanSleep = canSleep;
            if (b.Rb == null) return;
            b.Rb.sleepThreshold = SleepThreshold(canSleep);
            if (!canSleep && b.Dynamic) b.Rb.WakeUp();
        }

        public void BodySetContinuousCollision(object body, bool on)
        {
            var b = (Body)body;
            b.Ccd = on;
            if (b.Rb != null && b.Dynamic) b.Rb.collisionDetectionMode = on ? CollisionDetectionMode.ContinuousDynamic : CollisionDetectionMode.Discrete;
        }

        public void BodyApplyImpulse(object body, Vec3 impulse, Vec3 position)
        {
            var b = (Body)body;
            if (b.Rb == null || !b.Dynamic) return;
            if (position == Vec3.Zero) b.Rb.AddForce(Conv.Dir(impulse), ForceMode.Impulse);
            else b.Rb.AddForceAtPosition(Conv.Dir(impulse), b.Rb.position + Conv.Dir(position), ForceMode.Impulse);
        }

        public void BodyApplyTorqueImpulse(object body, Vec3 impulse)
        {
            var b = (Body)body;
            if (b.Rb != null && b.Dynamic) b.Rb.AddTorque(AngularToUnity(impulse), ForceMode.Impulse);
        }

        public void BodyApplyForce(object body, Vec3 force, Vec3 position)
        {
            var b = (Body)body;
            if (b.Rb == null || !b.Dynamic) return;
            if (position == Vec3.Zero) b.Rb.AddForce(Conv.Dir(force), ForceMode.Force);
            else b.Rb.AddForceAtPosition(Conv.Dir(force), b.Rb.position + Conv.Dir(position), ForceMode.Force);
        }

        public void BodyApplyTorque(object body, Vec3 torque)
        {
            var b = (Body)body;
            if (b.Rb != null && b.Dynamic) b.Rb.AddTorque(AngularToUnity(torque), ForceMode.Force);
        }

        public bool BodyGetState(object body, out PhysicsBodyState state)
        {
            state = default;
            var b = (Body)body;
            var rb = b.Rb;
            if (rb == null) return false;
            bool sleeping = b.Dynamic && rb.IsSleeping();
            if (sleeping && b.WasSleeping) return false;        // (Jolt syncs the bodies that were active in the step)
            b.WasSleeping = sleeping;
            state.Transform = new Xform3(new Basis(RotToGodot(rb.rotation), new Vec3(b.Scale.x, b.Scale.y, b.Scale.z)), PosToGodot(rb.position));
            if (b.Dynamic)
            {
                state.LinearVelocity = PosToGodot(rb.linearVelocity);
                state.AngularVelocity = AngularToGodot(rb.angularVelocity);
            }
            state.Sleeping = sleeping;
            return true;
        }

        // ------------------------------------------------------------------ joints
        public void BodySetJoint(object body, object parent, in PhysicsJointDesc joint)
        {
            var b = (Body)body;
            var p = parent as Body;
            if (joint.Type == PhysicalBone3D.JointTypeEnum.None || p == null || p == b) { BodyClearJoint(body); return; }
            b.Joint = joint;
            b.JointParent = p;
            b.JointDirty = true;
        }

        public void BodyClearJoint(object body)
        {
            var b = (Body)body;
            b.JointParent = null;
            b.JointDirty = false;
            DestroyJoint(b);
        }

        static void DestroyJoint(Body b)
        {
            if (b.Cj == null) return;
            Object.DestroyImmediate(b.Cj);      // (Destroy would leave it acting in this frame's steps)
            b.Cj = null;
        }

        static SoftJointLimit Limit(float deg) => new SoftJointLimit { limit = deg };
        const float MAX_LIMIT = 177f;           // PhysX's largest angular limit

        void BuildJoint(Body b)
        {
            b.JointDirty = false;
            DestroyJoint(b);
            var p = b.JointParent;
            if (p == null || p.Go == null || b.Go == null || p.World != b.World) return;
            var d = b.Joint;
            if (d.Type == PhysicalBone3D.JointTypeEnum.Slider || d.Type == PhysicalBone3D.JointTypeEnum.SixDOF)
            {
                Warn("PhysicalBone3D " + d.Type + " joints aren't simulated");
                return;
            }
            Xform3 fa = d.FrameA, fb = d.FrameB;
            float hingeHalf = 0f;
            bool hingeFixed = false;
            if (d.Type == PhysicalBone3D.JointTypeEnum.Hinge) fa = d.HingeFrameA(out hingeHalf, out hingeFixed);
            Quaternion qa = Conv.Rot(fa.basis.GetRotationQuaternion()), qb = Conv.Rot(fb.basis.GetRotationQuaternion());

            // Unity takes the joint's rest pose from the bodies' rotations as it configures it: turn the child to where
            // both frames coincide (Godot's rest), configure, put it back
            Transform tb = b.T;
            Vector3 savedPos = tb.position, rbPos = b.Rb.position;
            Quaternion savedRot = tb.rotation, rbRot = b.Rb.rotation;
            Quaternion aligned = p.T.rotation * qa * Quaternion.Inverse(qb);
            tb.rotation = aligned;
            b.Rb.rotation = aligned;

            var cj = b.Go.AddComponent<ConfigurableJoint>();
            cj.autoConfigureConnectedAnchor = false;
            cj.anchor = Conv.Pos(fb.origin);
            cj.connectedAnchor = Conv.Pos(fa.origin);
            bool hinge = d.Type == PhysicalBone3D.JointTypeEnum.Hinge;
            // the frame's axes in the body (Conv.Rot(q) * e_i: X = -mirror(X_godot), Y, Z = mirror(Y_godot), mirror(Z_godot))
            cj.axis = hinge ? qb * Vector3.forward : qb * Vector3.right;
            cj.secondaryAxis = hinge ? qb * Vector3.right : qb * Vector3.up;
            cj.xMotion = ConfigurableJointMotion.Locked;
            cj.yMotion = ConfigurableJointMotion.Locked;
            cj.zMotion = ConfigurableJointMotion.Locked;
            switch (d.Type)
            {
                case PhysicalBone3D.JointTypeEnum.Pin:
                    cj.angularXMotion = ConfigurableJointMotion.Free;
                    cj.angularYMotion = ConfigurableJointMotion.Free;
                    cj.angularZMotion = ConfigurableJointMotion.Free;
                    break;
                case PhysicalBone3D.JointTypeEnum.Cone:
                {
                    d.ConeLimits(out float swing, out float twist);
                    float tw = twist * Mathf.Rad2Deg, sw = swing * Mathf.Rad2Deg;
                    if (tw >= MAX_LIMIT) cj.angularXMotion = ConfigurableJointMotion.Free;
                    else if (tw <= 0f) cj.angularXMotion = ConfigurableJointMotion.Locked;
                    else
                    {
                        cj.angularXMotion = ConfigurableJointMotion.Limited;
                        cj.lowAngularXLimit = Limit(-tw);
                        cj.highAngularXLimit = Limit(tw);
                    }
                    var m = sw >= MAX_LIMIT ? ConfigurableJointMotion.Free : sw <= 0f ? ConfigurableJointMotion.Locked : ConfigurableJointMotion.Limited;
                    cj.angularYMotion = m;
                    cj.angularZMotion = m;
                    if (m == ConfigurableJointMotion.Limited)
                    {
                        cj.angularYLimit = Limit(sw);
                        cj.angularZLimit = Limit(sw);
                    }
                    break;
                }
                case PhysicalBone3D.JointTypeEnum.Hinge:
                {
                    cj.angularYMotion = ConfigurableJointMotion.Locked;
                    cj.angularZMotion = ConfigurableJointMotion.Locked;
                    float half = hingeHalf * Mathf.Rad2Deg;
                    if (hingeFixed) cj.angularXMotion = ConfigurableJointMotion.Locked;
                    else if (half >= MAX_LIMIT) cj.angularXMotion = ConfigurableJointMotion.Free;
                    else
                    {
                        cj.angularXMotion = ConfigurableJointMotion.Limited;
                        cj.lowAngularXLimit = Limit(-half);
                        cj.highAngularXLimit = Limit(half);
                    }
                    break;
                }
            }
            cj.enableCollision = JointBodiesCollide;
            cj.connectedBody = p.Rb;

            tb.SetPositionAndRotation(savedPos, savedRot);
            b.Rb.position = rbPos;
            b.Rb.rotation = rbRot;
            b.Cj = cj;
        }

        // ------------------------------------------------------------------ shapes
        static void ClearShapes(Body b)
        {
            foreach (var g in b.ShapeGos)
                if (g != null)
                {
                    g.SetActive(false);
                    Object.Destroy(g);
                }
            b.ShapeGos.Clear();
            foreach (var m in b.OwnedMeshes) if (m != null) Object.Destroy(m);
            b.OwnedMeshes.Clear();
        }

        void BuildShapes(Body b)
        {
            b.ShapesDirty = false;
            if (b.Go == null) return;
            ClearShapes(b);
            foreach (var inst in b.Shapes)
            {
                if (inst.Shape == null) continue;
                var sgo = new GameObject(inst.Shape.GetType().Name);
                sgo.layer = b.Go.layer;
                sgo.transform.SetParent(b.T, false);
                Conv.Apply(sgo.transform, inst.Transform);
                Collider c = null;
                switch (inst.Shape)
                {
                    case BoxShape3D box:
                    {
                        var bc = sgo.AddComponent<BoxCollider>();
                        bc.size = new Vector3(box.Size.x, box.Size.y, box.Size.z);
                        c = bc;
                        break;
                    }
                    case SphereShape3D sph:
                    {
                        var sc = sgo.AddComponent<SphereCollider>();
                        sc.radius = (float)sph.Radius;
                        c = sc;
                        break;
                    }
                    case CapsuleShape3D cap:
                    {
                        var cc = sgo.AddComponent<CapsuleCollider>();
                        cc.direction = 1;
                        cc.radius = (float)cap.Radius;
                        cc.height = (float)cap.Height;
                        c = cc;
                        break;
                    }
                    case CylinderShape3D cyl:
                    {
                        var mc = sgo.AddComponent<MeshCollider>();
                        mc.sharedMesh = Cylinder((float)cyl.Radius, (float)cyl.Height);
                        mc.convex = true;
                        c = mc;
                        break;
                    }
                    case HeightMapShape3D hm:
                    {
                        var mesh = HeightMap(hm);
                        if (mesh == null) break;
                        b.OwnedMeshes.Add(mesh);
                        var mc = sgo.AddComponent<MeshCollider>();
                        mc.convex = b.Dynamic;                // (Jolt doesn't support height maps on dynamic bodies either)
                        mc.sharedMesh = mesh;
                        c = mc;
                        break;
                    }
                    default:
                        Warn(inst.Shape.GetType().Name + " isn't simulated");
                        break;
                }
                if (c != null)
                {
                    c.sharedMaterial = b.Material;
                    c.contactOffset = ContactOffset;
                }
                b.ShapeGos.Add(sgo);
            }
            if (b.Rb != null)
            {
                b.Rb.ResetCenterOfMass();
                b.Rb.ResetInertiaTensor();
                if (b.Dynamic) b.Rb.WakeUp();
            }
        }

        /// <summary>HeightMapShape3D as Jolt lays it out (centred, one unit per sample, row-major by depth, quads split
        /// along the (x+1,z)-(x,z+1) diagonal, NaN = hole), X mirrored, faces up.</summary>
        static UMesh HeightMap(HeightMapShape3D hm)
        {
            int w = hm.MapWidth, dpt = hm.MapDepth;
            var data = hm.MapDataRaw;
            if (w < 2 || dpt < 2 || data.Length != w * dpt) { Warn("a HeightMapShape3D smaller than 2x2 isn't simulated"); return null; }
            float ox = -(w - 1) / 2f, oz = -(dpt - 1) / 2f;
            var verts = new Vector3[w * dpt];
            for (int z = 0; z < dpt; z++)
                for (int x = 0; x < w; x++)
                {
                    float h = data[z * w + x];
                    verts[z * w + x] = new Vector3(-(ox + x), float.IsNaN(h) ? 0f : h, oz + z);
                }
            var tris = new List<int>((w - 1) * (dpt - 1) * 6);
            for (int z = 0; z < dpt - 1; z++)
                for (int x = 0; x < w - 1; x++)
                {
                    int lr = z * w + x, ll = z * w + x + 1, ur = (z + 1) * w + x, ul = (z + 1) * w + x + 1;
                    // Godot's (lr, ur, ll) and (ll, ur, ul), wound the other way for the mirror
                    if (!Hole(data, lr, ur, ll)) { tris.Add(lr); tris.Add(ll); tris.Add(ur); }
                    if (!Hole(data, ll, ur, ul)) { tris.Add(ll); tris.Add(ul); tris.Add(ur); }
                }
            var mesh = new UMesh { name = "heightmap" };
            if (verts.Length > 65535) mesh.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
            mesh.vertices = verts;
            mesh.SetTriangles(tris, 0);
            mesh.RecalculateBounds();
            return mesh;
        }

        static bool Hole(float[] d, int a, int b, int c) => float.IsNaN(d[a]) || float.IsNaN(d[b]) || float.IsNaN(d[c]);

        static UMesh Cylinder(float r, float h)
        {
            if (_cylinders.TryGetValue((r, h), out var m) && m != null) return m;
            const int N = 16;
            var v = new Vector3[N * 2];
            for (int i = 0; i < N; i++)
            {
                float a = i * Mathf.PI * 2f / N;
                v[i] = new Vector3(Mathf.Cos(a) * r, -h / 2f, Mathf.Sin(a) * r);
                v[N + i] = new Vector3(Mathf.Cos(a) * r, h / 2f, Mathf.Sin(a) * r);
            }
            var t = new List<int>();
            for (int i = 0; i < N; i++)
            {
                int j = (i + 1) % N;
                t.Add(i); t.Add(N + i); t.Add(j);
                t.Add(j); t.Add(N + i); t.Add(N + j);
                if (i > 0 && i < N - 1)
                {
                    t.Add(0); t.Add(j); t.Add(i);                  // bottom
                    t.Add(N); t.Add(N + i); t.Add(N + j);          // top
                }
            }
            m = new UMesh { name = "cylinder" };
            m.vertices = v;
            m.SetTriangles(t, 0);
            m.RecalculateBounds();
            _cylinders[(r, h)] = m;
            return m;
        }

        /// <summary>The bones of one ragdoll (one PhysicalBoneSimulator3D) don't collide with each other. Jolt lets them
        /// (Godot never disables a PhysicalBone3D joint's collisions) and resolves the overlap of neighbouring capsules
        /// at a joint gently; PhysX fights it against the joint every step and the ragdoll jitters and flies about
        /// (Kevin, the first Unity builds: "ragdolls are acting sporadic").</summary>
        static void IgnoreWithinRagdolls(World w)
        {
            var groups = new Dictionary<Node, List<Collider>>();
            foreach (var b in w.Bodies)
            {
                if (!(b.Node is PhysicalBone3D pb) || b.Go == null) continue;
                var owner = pb.GetParent();
                if (owner == null) continue;
                if (!groups.TryGetValue(owner, out var list)) groups[owner] = list = new List<Collider>();
                foreach (var g in b.ShapeGos)
                    if (g != null && g.TryGetComponent<Collider>(out var c)) list.Add(c);
            }
            foreach (var list in groups.Values)
                for (int i = 0; i < list.Count; i++)
                    for (int j = i + 1; j < list.Count; j++)
                        if (list[i].attachedRigidbody != list[j].attachedRigidbody) Physics.IgnoreCollision(list[i], list[j], true);
        }

        // ------------------------------------------------------------------ step
        public void Step(double delta)
        {
            float dt = (float)delta;
            if (dt <= 0f) return;
            Vector3 g = Physics.gravity;
            for (int wi = 0; wi < _worldList.Count; wi++)
            {
                var w = _worldList[wi];
                if (w.Bodies.Count == 0 || !w.Physics.IsValid()) continue;
                var bodies = w.Bodies;
                bool boneShapes = false;
                for (int i = 0; i < bodies.Count; i++)
                {
                    var b = bodies[i];
                    if (!b.ShapesDirty) continue;
                    BuildShapes(b);
                    if (b.Node is PhysicalBone3D) boneShapes = true;
                }
                if (boneShapes) IgnoreWithinRagdolls(w);
                for (int i = 0; i < bodies.Count; i++)
                {
                    var b = bodies[i];
                    if (b.JointDirty) BuildJoint(b);
                    var rb = b.Rb;
                    if (rb == null) continue;
                    if (b.HasTarget)
                    {
                        b.HasTarget = false;
                        if (b.Mode == PhysicsBodyMode.Kinematic)
                        {
                            rb.MovePosition(b.TargetPos);
                            rb.MoveRotation(b.TargetRot);
                        }
                    }
                    if (b.GravityScale != 1f && b.Dynamic && !rb.IsSleeping() && b.GravityScale != 0f)
                        rb.AddForce(g * b.GravityScale, ForceMode.Acceleration);
                }
                w.Physics.Simulate(dt);
            }
        }
    }
}
