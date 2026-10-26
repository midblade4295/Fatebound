#if FB3D
// Godot's 3D physics nodes (scene/3d/physics: collision_object_3d.cpp, physics_body_3d.cpp, static_body_3d.cpp,
// rigid_body_3d.cpp, collision_shape_3d.cpp, 4.7) for the ported code, and the seam to whatever simulates them.
//
// The seam mirrors Godot's PhysicsServer3D: a body node talks to the backend the host registered
// (PhysicsServer3D.Backend, the Unity client's PhysX one) at the same moments Godot calls the server -- the body is
// made when the node enters a world (one space per World3D) and freed when it leaves, every setter pushes at once,
// shapes go over as the flattened list of the body's shape owners (CollisionShape3D children). Headless (tests, the
// .NET server) there is no backend: bodies keep their properties and simply never move.
//
// The step, where main.cpp does it in a physics tick: SceneTree.Iterate calls PhysicsServer3D.FlushQueries at the
// tick's start, before _physics_process (flush_queries: every body that was awake in the last step takes its state
// -- RigidBody3D / a simulating PhysicalBone3D set their global transform without echoing it back, their velocities,
// sleeping), and PhysicsServer3D.Step after _physics_process (end_sync + step). So, as in Godot, what a frame draws is
// the state of the step before the frame's last one. Nothing steps while the tree is paused (set_pause turns the
// physics server off).
//
// Not here (unused by the game): Area3D, CharacterBody3D, AnimatableBody3D, ray/shape casts and space queries, contact
// monitoring and its signals, collision exceptions, axis locks, _integrate_forces, disable_mode (stored only).
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    /// <summary>PhysicsServer3D::BodyMode.</summary>
    public enum PhysicsBodyMode { Static = 0, Kinematic = 1, Rigid = 2, RigidLinear = 3 }

    /// <summary>One enabled shape of a body: the resource and its transform in the body's space (the shape owner's,
    /// i.e. the CollisionShape3D's local transform). Disabled shape owners are left out.</summary>
    public struct PhysicsShapeInstance
    {
        public Shape3D Shape;
        public Xform3 Transform;
    }

    /// <summary>What a body reports after a step (PhysicsDirectBodyState3D's part the nodes read). Godot space.</summary>
    public struct PhysicsBodyState
    {
        public Xform3 Transform;
        public Vec3 LinearVelocity, AngularVelocity;
        public bool Sleeping;
    }

    /// <summary>A PhysicalBone3D's joint to its parent bone's body, as PhysicsServer3D::joint_make_* gets it: FrameA in
    /// the parent body's space, FrameB (joint_offset) in this body's; at creation both frames coincide in the world,
    /// that pose is the joint's rest. Angles in radians. Pin uses the frames' origins only; cone twists about the
    /// frames' X axis within a circular swing cone; a hinge turns about their Z axis.</summary>
    public struct PhysicsJointDesc
    {
        public PhysicalBone3D.JointTypeEnum Type;
        public Xform3 FrameA, FrameB;
        public float SwingSpan, TwistSpan;
        public bool AngularLimitEnabled;
        public float AngularLimitUpper, AngularLimitLower;

        /// <summary>The hinge as Jolt builds it (JoltHingeJoint3D::rebuild): with limits on (and lower &lt;= upper) frame A
        /// is turned about Z by -(lower + upper) / 2 so the limit becomes symmetric, +-halfSpan -- Godot's angle being
        /// -(B's rotation relative to A), the allowed range for B is [-upper, -lower] about Z. fixedJoint: lower ==
        /// upper. Without limits: halfSpan = PI (free).</summary>
        public Xform3 HingeFrameA(out float halfSpan, out bool fixedJoint)
        {
            fixedJoint = false;
            halfSpan = (float)Math.PI;
            Xform3 a = FrameA;
            if (AngularLimitEnabled && AngularLimitLower <= AngularLimitUpper)
            {
                double mid = (AngularLimitLower + AngularLimitUpper) / 2.0;
                halfSpan = (float)(AngularLimitUpper - mid);
                fixedJoint = AngularLimitLower == AngularLimitUpper;
                a.basis = a.basis * Basis.FromEuler(new Vec3(0f, 0f, (float)-mid), EulerOrder.ZYX);
            }
            return a;
        }

        /// <summary>The cone as Jolt builds it (JoltConeTwistJoint3D::_build_swing_twist): spans outside [0, PI] mean
        /// free (an invalid swing frees the twist too). PI = free.</summary>
        public void ConeLimits(out float swing, out float twist)
        {
            const float PI = (float)Math.PI;
            bool twistValid = TwistSpan >= 0 && TwistSpan <= PI, swingValid = SwingSpan >= 0 && SwingSpan <= PI;
            twist = twistValid ? TwistSpan : PI;
            swing = swingValid ? SwingSpan : PI;
            if (!swingValid) twist = PI;
        }
    }

    /// <summary>The physics backend the host plugs in (the Unity client's PhysX one). Godot space throughout (the
    /// backend converts); body handles are the backend's own objects. Called on the main thread.</summary>
    public interface IPhysics3D
    {
        /// <summary>A body for a node entering `world` (its space). The facade then sets its mode, collision, shapes,
        /// transform and parameters.</summary>
        object BodyCreate(CollisionObject3D node, World3D world);
        /// <summary>The node left its world (or was freed): drop the body, its joint, and joints made to it.</summary>
        void BodyFree(object body);
        void BodySetMode(object body, PhysicsBodyMode mode);
        void BodySetShapes(object body, PhysicsShapeInstance[] shapes);
        /// <summary>Static / rigid bodies are placed there; a kinematic one moves there over the next step.</summary>
        void BodySetTransform(object body, in Xform3 transform);
        void BodySetCollision(object body, uint layer, uint mask);
        /// <summary>Godot's computed values: a negative friction is "rough", a negative bounce "absorbent".</summary>
        void BodySetMaterial(object body, double friction, double bounce);
        void BodySetMass(object body, double mass);
        void BodySetGravityScale(object body, double scale);
        /// <summary>The total damping (the body's, plus the world's default in DAMP_MODE_COMBINE).</summary>
        void BodySetDamping(object body, double linear, double angular);
        void BodySetLinearVelocity(object body, Vec3 velocity);
        void BodySetAngularVelocity(object body, Vec3 velocity);
        void BodySetSleeping(object body, bool sleeping);
        void BodySetCanSleep(object body, bool canSleep);
        void BodySetContinuousCollision(object body, bool on);
        /// <summary>position: offset from the body's origin, in world orientation (as Godot's apply_impulse).</summary>
        void BodyApplyImpulse(object body, Vec3 impulse, Vec3 position);
        void BodyApplyTorqueImpulse(object body, Vec3 impulse);
        /// <summary>A force for the next step.</summary>
        void BodyApplyForce(object body, Vec3 force, Vec3 position);
        void BodyApplyTorque(object body, Vec3 torque);
        /// <summary>The body's state after the last step; false when there's nothing to take (it slept through it).</summary>
        bool BodyGetState(object body, out PhysicsBodyState state);
        /// <summary>Makes (or remakes) `body`'s joint to `parent` (a PhysicalBone3D's joint).</summary>
        void BodySetJoint(object body, object parent, in PhysicsJointDesc joint);
        void BodyClearJoint(object body);
        /// <summary>Advances every space by delta seconds.</summary>
        void Step(double delta);
    }

    /// <summary>The facade's side of Godot's PhysicsServer3D: the backend, the project's default space settings, the
    /// bodies whose state is read back after a step, and the two SceneTree hooks.</summary>
    public static class PhysicsServer3D
    {
        public const PhysicsBodyMode BODY_MODE_STATIC = PhysicsBodyMode.Static, BODY_MODE_KINEMATIC = PhysicsBodyMode.Kinematic,
            BODY_MODE_RIGID = PhysicsBodyMode.Rigid, BODY_MODE_RIGID_LINEAR = PhysicsBodyMode.RigidLinear;

        /// <summary>Null when nothing simulates (headless).</summary>
        public static IPhysics3D Backend;

        // project settings physics/3d/* (Godot's defaults; Fatebound's project.godot keeps them)
        public static double DefaultGravity = 9.8;
        public static Vec3 DefaultGravityVector = new Vec3(0f, -1f, 0f);
        public static double DefaultLinearDamp = 0.1, DefaultAngularDamp = 0.1;

        static readonly List<CollisionObject3D> _sync = new List<CollisionObject3D>();
        static CollisionObject3D[] _scratch = new CollisionObject3D[64];
        internal static int bodyCount;

        /// <summary>Steps taken (the bodies that joined the sync list since the last one aren't read yet).</summary>
        public static long StepCount { get; private set; }
        public static int BodyCount => bodyCount;

        internal static double TotalDamp(int mode, double damp, double dflt) => mode == 1 ? damp : dflt + damp;

        internal static void AddSync(CollisionObject3D o)
        {
            if (o.syncIndex >= 0) return;
            o.syncIndex = _sync.Count;
            o.syncSince = StepCount;
            _sync.Add(o);
        }

        internal static void RemoveSync(CollisionObject3D o)
        {
            int i = o.syncIndex;
            if (i < 0) return;
            int last = _sync.Count - 1;
            if (i != last) { _sync[i] = _sync[last]; _sync[i].syncIndex = i; }
            _sync.RemoveAt(last);
            o.syncIndex = -1;
        }

        /// <summary>flush_queries (a physics tick's start): the bodies that took part in the last step take its state.</summary>
        public static void FlushQueries(SceneTree tree)
        {
            var be = Backend;
            if (be == null || tree == null || tree.Paused || _sync.Count == 0) return;
            int n = _sync.Count;
            if (_scratch.Length < n) _scratch = new CollisionObject3D[Math.Max(n, _scratch.Length * 2)];
            _sync.CopyTo(_scratch);
            for (int i = 0; i < n; i++)
            {
                var o = _scratch[i];
                _scratch[i] = null;
                if (o.syncIndex < 0 || o.syncSince >= StepCount || o.PhysicsBackendData == null || o.IsFreed) continue;
                if (!be.BodyGetState(o.PhysicsBackendData, out var st)) continue;
                try { o.SyncFromPhysics(st); }
                catch (Exception ex) { GD_Log.Error(o.Name + ": " + ex); }
            }
        }

        /// <summary>end_sync + step (after the tick's _physics_process).</summary>
        public static void Step(SceneTree tree, double delta)
        {
            var be = Backend;
            if (be == null || tree == null || tree.Paused || bodyCount == 0) return;
            be.Step(delta);
            StepCount++;
        }
    }

    // ================================================================== CollisionObject3D
    public abstract partial class CollisionObject3D : Node3D
    {
        public enum DisableModeEnum { Remove = 0, MakeStatic = 1, KeepActive = 2 }
        public const DisableModeEnum DISABLE_MODE_REMOVE = DisableModeEnum.Remove, DISABLE_MODE_MAKE_STATIC = DisableModeEnum.MakeStatic,
            DISABLE_MODE_KEEP_ACTIVE = DisableModeEnum.KeepActive;

        uint _layer = 1, _mask = 1, _srvLayer = 1, _srvMask = 1;
        double _priority = 1.0;
        internal PhysicsBodyMode bodyMode;
        object _body;
        bool _stateSync;
        internal int syncIndex = -1;
        internal long syncSince;
        /// <summary>Stored only (the facade doesn't model process_mode DISABLED).</summary>
        public DisableModeEnum DisableMode = DisableModeEnum.Remove;
        public bool InputRayPickable = true, InputCaptureOnDrag;

        sealed class ShapeOwner
        {
            public object Owner;
            public Xform3 Xform = Xform3.IDENTITY;
            public bool Disabled;
            public readonly List<Shape3D> Shapes = new List<Shape3D>();
        }

        readonly SortedDictionary<uint, ShapeOwner> _owners = new SortedDictionary<uint, ShapeOwner>();
        readonly List<Shape3D> _watched = new List<Shape3D>();
        readonly Action _shapeChanged;

        protected CollisionObject3D(PhysicsBodyMode mode)
        {
            bodyMode = mode;
            _shapeChanged = PushShapes;
            SetNotifyTransform(true);
        }

        /// <summary>The backend's body (null while out of a world, or headless).</summary>
        public object PhysicsBackendData => _body;
        protected static IPhysics3D Be => PhysicsServer3D.Backend;

        // ------------------------------------------------------------------ collision layers
        public uint CollisionLayer { get => _layer; set { _layer = value; ServerSetCollision(value, _srvMask); } }
        public uint CollisionMask { get => _mask; set { _mask = value; ServerSetCollision(_srvLayer, value); } }
        /// <summary>Stored (Jolt doesn't use it).</summary>
        public double CollisionPriority { get => _priority; set => _priority = value; }

        public void SetCollisionLayerValue(int layer, bool on)
        {
            if (layer < 1 || layer > 32) { GD.PushError("Collision layer number must be between 1 and 32 inclusive."); return; }
            CollisionLayer = on ? _layer | (1u << (layer - 1)) : _layer & ~(1u << (layer - 1));
        }
        public bool GetCollisionLayerValue(int layer) => layer >= 1 && layer <= 32 && (_layer & (1u << (layer - 1))) != 0;
        public void SetCollisionMaskValue(int layer, bool on)
        {
            if (layer < 1 || layer > 32) { GD.PushError("Collision layer number must be between 1 and 32 inclusive."); return; }
            CollisionMask = on ? _mask | (1u << (layer - 1)) : _mask & ~(1u << (layer - 1));
        }
        public bool GetCollisionMaskValue(int layer) => layer >= 1 && layer <= 32 && (_mask & (1u << (layer - 1))) != 0;

        /// <summary>body_set_collision_layer / _mask on the server (PhysicalBone3D sets 0/0 there while its simulator is off).</summary>
        internal void ServerSetCollision(uint layer, uint mask)
        {
            _srvLayer = layer;
            _srvMask = mask;
            if (_body != null) Be?.BodySetCollision(_body, layer, mask);
        }

        internal void SetBodyMode(PhysicsBodyMode mode)
        {
            if (bodyMode == mode) return;
            bodyMode = mode;
            if (_body != null) Be?.BodySetMode(_body, mode);
        }

        /// <summary>The body has a state sync callback (RigidBody3D always, PhysicalBone3D while it simulates): its state
        /// is read back after each step it was awake for.</summary>
        internal void SetStateSync(bool on)
        {
            _stateSync = on;
            if (!on) PhysicsServer3D.RemoveSync(this);
            else if (_body != null) PhysicsServer3D.AddSync(this);
        }

        internal virtual void SyncFromPhysics(in PhysicsBodyState state) { }

        /// <summary>set_global_transform with set_ignore_transform_notification: the children follow, the body's own
        /// TRANSFORM_CHANGED (which would push the transform back to the server) isn't queued.</summary>
        internal void SetGlobalTransformFromPhysics(in Xform3 t)
        {
            bool was = inXformChangeList;
            GlobalTransform = t;
            if (!was && inXformChangeList)
            {
                var l = GetTree()?.xformChangeList;
                int n = l?.Count ?? 0;
                if (n > 0 && l[n - 1] == this)
                {
                    l.RemoveAt(n - 1);
                    inXformChangeList = false;
                }
            }
        }

        // ------------------------------------------------------------------ world
        protected override void OnEnterWorld()
        {
            base.OnEnterWorld();
            var be = Be;
            var world = GetWorld3D();
            if (be == null || world == null) return;
            _body = be.BodyCreate(this, world);
            if (_body == null) return;
            PhysicsServer3D.bodyCount++;
            be.BodySetMode(_body, bodyMode);
            be.BodySetCollision(_body, _srvLayer, _srvMask);
            PushShapes();
            be.BodySetTransform(_body, GlobalTransform);
            PushBodyParams(be);
            if (_stateSync) PhysicsServer3D.AddSync(this);
        }

        protected override void OnExitWorld()
        {
            if (_body != null)
            {
                PhysicsServer3D.RemoveSync(this);
                Unwatch();
                var b = _body;
                _body = null;
                PhysicsServer3D.bodyCount--;
                Be?.BodyFree(b);
            }
            base.OnExitWorld();
        }

        /// <summary>The subclass's server state, sent when the body is made (mass, material, damping, velocities...).</summary>
        protected virtual void PushBodyParams(IPhysics3D be) { }

        protected override void OnTransformChanged()
        {
            base.OnTransformChanged();
            if (_body != null) Be?.BodySetTransform(_body, GlobalTransform);
        }

        // ------------------------------------------------------------------ shape owners
        public uint CreateShapeOwner(object owner)
        {
            uint id = 0;
            foreach (var k in _owners.Keys) id = k + 1;        // (shapes.back()->key() + 1)
            _owners[id] = new ShapeOwner { Owner = owner };
            return id;
        }

        public void RemoveShapeOwner(uint owner)
        {
            if (!_owners.ContainsKey(owner)) return;
            ShapeOwnerClearShapes(owner);
            _owners.Remove(owner);
        }

        public uint[] GetShapeOwners() => new List<uint>(_owners.Keys).ToArray();

        ShapeOwner OwnerData(uint id)
        {
            if (_owners.TryGetValue(id, out var o)) return o;
            GD.PushError("Condition \"!shapes.has(p_owner)\" is true.");
            return null;
        }

        public void ShapeOwnerSetTransform(uint owner, Xform3 xform)
        {
            var o = OwnerData(owner);
            if (o == null) return;
            o.Xform = xform;
            ShapesChanged();
        }

        public Xform3 ShapeOwnerGetTransform(uint owner) => OwnerData(owner)?.Xform ?? Xform3.IDENTITY;
        public object ShapeOwnerGetOwner(uint owner) => OwnerData(owner)?.Owner;

        public void ShapeOwnerSetDisabled(uint owner, bool disabled)
        {
            var o = OwnerData(owner);
            if (o == null || o.Disabled == disabled) return;
            o.Disabled = disabled;
            ShapesChanged();
        }

        public bool IsShapeOwnerDisabled(uint owner) => OwnerData(owner)?.Disabled ?? false;

        public void ShapeOwnerAddShape(uint owner, Shape3D shape)
        {
            if (shape == null) { GD.PushError("Parameter \"p_shape\" is null."); return; }
            var o = OwnerData(owner);
            if (o == null) return;
            o.Shapes.Add(shape);
            ShapesChanged();
        }

        public int ShapeOwnerGetShapeCount(uint owner) => OwnerData(owner)?.Shapes.Count ?? 0;

        public Shape3D ShapeOwnerGetShape(uint owner, int shape)
        {
            var o = OwnerData(owner);
            return o != null && shape >= 0 && shape < o.Shapes.Count ? o.Shapes[shape] : null;
        }

        /// <summary>The shape's index in the body (owners in order, each owner's shapes in order).</summary>
        public int ShapeOwnerGetShapeIndex(uint owner, int shape)
        {
            int idx = 0;
            foreach (var kv in _owners)
            {
                if (kv.Key == owner) return shape >= 0 && shape < kv.Value.Shapes.Count ? idx + shape : -1;
                idx += kv.Value.Shapes.Count;
            }
            return -1;
        }

        public void ShapeOwnerRemoveShape(uint owner, int shape)
        {
            var o = OwnerData(owner);
            if (o == null || shape < 0 || shape >= o.Shapes.Count) return;
            o.Shapes.RemoveAt(shape);
            ShapesChanged();
        }

        public void ShapeOwnerClearShapes(uint owner)
        {
            var o = OwnerData(owner);
            if (o == null || o.Shapes.Count == 0) return;
            o.Shapes.Clear();
            ShapesChanged();
        }

        public uint ShapeFindOwner(int shapeIndex)
        {
            int idx = 0;
            foreach (var kv in _owners)
            {
                if (shapeIndex < idx + kv.Value.Shapes.Count) return kv.Key;
                idx += kv.Value.Shapes.Count;
            }
            return uint.MaxValue;
        }

        void ShapesChanged() { if (_body != null) PushShapes(); }

        void PushShapes()
        {
            var be = Be;
            if (_body == null || be == null) return;
            var list = new List<PhysicsShapeInstance>();
            Unwatch();
            foreach (var kv in _owners)
            {
                var o = kv.Value;
                for (int i = 0; i < o.Shapes.Count; i++)
                {
                    var s = o.Shapes[i];
                    if (!_watched.Contains(s)) { _watched.Add(s); s.Changed += _shapeChanged; }
                    if (!o.Disabled) list.Add(new PhysicsShapeInstance { Shape = s, Transform = o.Xform });
                }
            }
            be.BodySetShapes(_body, list.ToArray());
        }

        void Unwatch()
        {
            for (int i = 0; i < _watched.Count; i++) _watched[i].Changed -= _shapeChanged;
            _watched.Clear();
        }
    }

    // ================================================================== PhysicsBody3D
    public abstract partial class PhysicsBody3D : CollisionObject3D
    {
        protected PhysicsBody3D(PhysicsBodyMode mode) : base(mode) { }
        public virtual Vec3 GetLinearVelocity() => Vec3.Zero;
        public virtual Vec3 GetAngularVelocity() => Vec3.Zero;
    }

    // ================================================================== StaticBody3D
    public partial class StaticBody3D : PhysicsBody3D
    {
        PhysicsMaterial _material;
        Vec3 _constantLinear, _constantAngular;
        readonly Action _reload;

        public StaticBody3D() : this(PhysicsBodyMode.Static) { }

        protected StaticBody3D(PhysicsBodyMode mode) : base(mode)
        {
            _reload = ReloadPhysicsCharacteristics;
        }

        public PhysicsMaterial PhysicsMaterialOverride
        {
            get => _material;
            set
            {
                if (_material != null) _material.Changed -= _reload;
                _material = value;
                if (_material != null) _material.Changed += _reload;
                ReloadPhysicsCharacteristics();
            }
        }

        /// <summary>Stored (conveyor-style contact velocities aren't simulated by the backend).</summary>
        public Vec3 ConstantLinearVelocity { get => _constantLinear; set => _constantLinear = value; }
        public Vec3 ConstantAngularVelocity { get => _constantAngular; set => _constantAngular = value; }

        void ReloadPhysicsCharacteristics()
        {
            if (PhysicsBackendData == null) return;
            if (_material == null) Be?.BodySetMaterial(PhysicsBackendData, 1.0, 0.0);
            else Be?.BodySetMaterial(PhysicsBackendData, _material.ComputedFriction, _material.ComputedBounce);
        }

        protected override void PushBodyParams(IPhysics3D be) => ReloadPhysicsCharacteristics();
    }

    // ================================================================== RigidBody3D
    public partial class RigidBody3D : PhysicsBody3D
    {
        public enum FreezeModeEnum { Static = 0, Kinematic = 1 }
        public const FreezeModeEnum FREEZE_MODE_STATIC = FreezeModeEnum.Static, FREEZE_MODE_KINEMATIC = FreezeModeEnum.Kinematic;
        public enum CenterOfMassModeEnum { Auto = 0, Custom = 1 }
        public const CenterOfMassModeEnum CENTER_OF_MASS_MODE_AUTO = CenterOfMassModeEnum.Auto, CENTER_OF_MASS_MODE_CUSTOM = CenterOfMassModeEnum.Custom;
        public enum DampModeEnum { Combine = 0, Replace = 1 }
        public const DampModeEnum DAMP_MODE_COMBINE = DampModeEnum.Combine, DAMP_MODE_REPLACE = DampModeEnum.Replace;

        float _mass = 1f, _gravityScale = 1f, _linearDamp, _angularDamp;
        Vec3 _inertia, _centerOfMass, _linearVelocity, _angularVelocity;
        bool _canSleep = true, _lockRotation, _freeze, _sleeping, _ccd, _customIntegrator, _contactMonitor;
        int _maxContacts, _contactCount;
        FreezeModeEnum _freezeMode = FreezeModeEnum.Static;
        CenterOfMassModeEnum _comMode = CenterOfMassModeEnum.Auto;
        DampModeEnum _linearDampMode = DampModeEnum.Combine, _angularDampMode = DampModeEnum.Combine;
        PhysicsMaterial _material;
        readonly Action _reload;

        public event Action SleepingStateChanged;

        public RigidBody3D() : base(PhysicsBodyMode.Rigid)
        {
            _reload = ReloadPhysicsCharacteristics;
            SetStateSync(true);
        }

        object B => PhysicsBackendData;

        void ApplyBodyMode()
        {
            if (_freeze) SetBodyMode(_freezeMode == FreezeModeEnum.Static ? PhysicsBodyMode.Static : PhysicsBodyMode.Kinematic);
            else if (_lockRotation) SetBodyMode(PhysicsBodyMode.RigidLinear);
            else SetBodyMode(PhysicsBodyMode.Rigid);
        }

        public bool LockRotation { get => _lockRotation; set { if (value == _lockRotation) return; _lockRotation = value; ApplyBodyMode(); } }
        public bool Freeze { get => _freeze; set { if (value == _freeze) return; _freeze = value; ApplyBodyMode(); } }
        public FreezeModeEnum FreezeMode { get => _freezeMode; set { if (value == _freezeMode) return; _freezeMode = value; ApplyBodyMode(); } }

        public double Mass
        {
            get => _mass;
            set
            {
                if (value <= 0) { GD.PushError("Condition \"p_mass <= 0\" is true."); return; }
                _mass = (float)value;
                if (B != null) Be?.BodySetMass(B, _mass);
            }
        }

        /// <summary>Stored (the backend derives the inertia from the shapes, as Godot does while this is zero).</summary>
        public Vec3 Inertia
        {
            get => _inertia;
            set
            {
                if (value.x < 0 || value.y < 0 || value.z < 0) { GD.PushError("Condition \"p_inertia.x < 0\" is true."); return; }
                _inertia = value;
            }
        }

        /// <summary>Stored (the backend uses the shapes' centre of mass).</summary>
        public CenterOfMassModeEnum CenterOfMassMode
        {
            get => _comMode;
            set { if (_comMode == value) return; _comMode = value; if (value == CenterOfMassModeEnum.Auto) _centerOfMass = Vec3.Zero; }
        }

        public Vec3 CenterOfMass
        {
            get => _centerOfMass;
            set
            {
                if (_centerOfMass == value) return;
                if (_comMode != CenterOfMassModeEnum.Custom) { GD.PushError("Condition \"center_of_mass_mode != CENTER_OF_MASS_MODE_CUSTOM\" is true."); return; }
                _centerOfMass = value;
            }
        }

        public PhysicsMaterial PhysicsMaterialOverride
        {
            get => _material;
            set
            {
                if (_material != null) _material.Changed -= _reload;
                _material = value;
                if (_material != null) _material.Changed += _reload;
                ReloadPhysicsCharacteristics();
            }
        }

        void ReloadPhysicsCharacteristics()
        {
            if (B == null) return;
            if (_material == null) Be?.BodySetMaterial(B, 1.0, 0.0);
            else Be?.BodySetMaterial(B, _material.ComputedFriction, _material.ComputedBounce);
        }

        public double GravityScale { get => _gravityScale; set { _gravityScale = (float)value; if (B != null) Be?.BodySetGravityScale(B, _gravityScale); } }

        public DampModeEnum LinearDampMode { get => _linearDampMode; set { _linearDampMode = value; PushDamping(); } }
        public DampModeEnum AngularDampMode { get => _angularDampMode; set { _angularDampMode = value; PushDamping(); } }

        public double LinearDamp
        {
            get => _linearDamp;
            set
            {
                if (value < 0) { GD.PushError("Condition \"p_linear_damp < 0.0\" is true."); return; }
                _linearDamp = (float)value;
                PushDamping();
            }
        }

        public double AngularDamp
        {
            get => _angularDamp;
            set
            {
                if (value < 0) { GD.PushError("Condition \"p_angular_damp < 0.0\" is true."); return; }
                _angularDamp = (float)value;
                PushDamping();
            }
        }

        /// <summary>What the body is damped with: its own damping plus the world's default (0.1) in COMBINE mode.</summary>
        public double TotalLinearDamp => PhysicsServer3D.TotalDamp((int)_linearDampMode, _linearDamp, PhysicsServer3D.DefaultLinearDamp);
        public double TotalAngularDamp => PhysicsServer3D.TotalDamp((int)_angularDampMode, _angularDamp, PhysicsServer3D.DefaultAngularDamp);

        void PushDamping() { if (B != null) Be?.BodySetDamping(B, TotalLinearDamp, TotalAngularDamp); }

        public Vec3 LinearVelocity
        {
            get => _linearVelocity;
            set { _linearVelocity = value; if (B != null) Be?.BodySetLinearVelocity(B, value); }
        }

        public Vec3 AngularVelocity
        {
            get => _angularVelocity;
            set { _angularVelocity = value; if (B != null) Be?.BodySetAngularVelocity(B, value); }
        }

        public override Vec3 GetLinearVelocity() => _linearVelocity;
        public override Vec3 GetAngularVelocity() => _angularVelocity;

        public void SetAxisVelocity(Vec3 axis)
        {
            Vec3 a = axis.Normalized();
            _linearVelocity -= a * a.Dot(_linearVelocity);
            _linearVelocity += axis;
            if (B != null) Be?.BodySetLinearVelocity(B, _linearVelocity);
        }

        public bool Sleeping { get => _sleeping; set { _sleeping = value; if (B != null) Be?.BodySetSleeping(B, value); } }
        public bool IsSleeping() => _sleeping;
        public bool CanSleep { get => _canSleep; set { _canSleep = value; if (B != null) Be?.BodySetCanSleep(B, value); } }
        public bool IsAbleToSleep() => _canSleep;
        public bool ContinuousCd { get => _ccd; set { _ccd = value; if (B != null) Be?.BodySetContinuousCollision(B, value); } }
        /// <summary>Stored (_integrate_forces isn't called by the port).</summary>
        public bool CustomIntegrator { get => _customIntegrator; set => _customIntegrator = value; }
        /// <summary>Stored: contacts aren't reported by the backend (no body_entered/exited).</summary>
        public bool ContactMonitor { get => _contactMonitor; set => _contactMonitor = value; }
        public int MaxContactsReported { get => _maxContacts; set => _maxContacts = value; }
        public int GetContactCount() => _contactCount;
        public List<Node3D> GetCollidingBodies() => new List<Node3D>();

        public void ApplyCentralImpulse(Vec3 impulse) { if (B != null) Be?.BodyApplyImpulse(B, impulse, Vec3.Zero); }
        public void ApplyImpulse(Vec3 impulse, Vec3 position = default) { if (B != null) Be?.BodyApplyImpulse(B, impulse, position); }
        public void ApplyTorqueImpulse(Vec3 impulse) { if (B != null) Be?.BodyApplyTorqueImpulse(B, impulse); }
        public void ApplyCentralForce(Vec3 force) { if (B != null) Be?.BodyApplyForce(B, force, Vec3.Zero); }
        public void ApplyForce(Vec3 force, Vec3 position = default) { if (B != null) Be?.BodyApplyForce(B, force, position); }
        public void ApplyTorque(Vec3 torque) { if (B != null) Be?.BodyApplyTorque(B, torque); }

        protected override void PushBodyParams(IPhysics3D be)
        {
            var b = B;
            be.BodySetMass(b, _mass);
            ReloadPhysicsCharacteristics();
            be.BodySetGravityScale(b, _gravityScale);
            be.BodySetDamping(b, TotalLinearDamp, TotalAngularDamp);
            be.BodySetCanSleep(b, _canSleep);
            be.BodySetContinuousCollision(b, _ccd);
            be.BodySetLinearVelocity(b, _linearVelocity);
            be.BodySetAngularVelocity(b, _angularVelocity);
            if (_sleeping) be.BodySetSleeping(b, true);
        }

        /// <summary>RigidBody3D::_sync_body_state.</summary>
        internal override void SyncFromPhysics(in PhysicsBodyState s)
        {
            if (s.Transform != GlobalTransform) SetGlobalTransformFromPhysics(s.Transform);
            _linearVelocity = s.LinearVelocity;
            _angularVelocity = s.AngularVelocity;
            if (_sleeping != s.Sleeping)
            {
                _sleeping = s.Sleeping;
                SleepingStateChanged?.Invoke();
            }
        }
    }

    // ================================================================== CollisionShape3D
    /// <summary>Gives its parent CollisionObject3D a shape (a shape owner made when it's parented; its local transform is
    /// the shape's transform in the body).</summary>
    public partial class CollisionShape3D : Node3D
    {
        Shape3D _shape;
        bool _disabled;
        CollisionObject3D _co;
        uint _ownerId;
        public Col DebugColor = new Col(0f, 0f, 0f, 0f);
        public bool DebugFill = true;

        public CollisionShape3D() { SetNotifyLocalTransform(true); }

        public Shape3D Shape
        {
            get => _shape;
            set
            {
                if (value == _shape) return;
                _shape = value;
                if (_co != null)
                {
                    _co.ShapeOwnerClearShapes(_ownerId);
                    if (_shape != null) _co.ShapeOwnerAddShape(_ownerId, _shape);
                }
            }
        }

        public bool Disabled
        {
            get => _disabled;
            set
            {
                _disabled = value;
                if (_co != null) _co.ShapeOwnerSetDisabled(_ownerId, value);
            }
        }

        void UpdateInShapeOwner(bool xformOnly = false)
        {
            _co.ShapeOwnerSetTransform(_ownerId, Transform);
            if (xformOnly) return;
            _co.ShapeOwnerSetDisabled(_ownerId, _disabled);
        }

        protected override void OnParented()
        {
            base.OnParented();
            _co = Parent as CollisionObject3D;
            if (_co == null) return;
            _ownerId = _co.CreateShapeOwner(this);
            if (_shape != null) _co.ShapeOwnerAddShape(_ownerId, _shape);
            UpdateInShapeOwner();
        }

        protected override void OnEnterTree()
        {
            base.OnEnterTree();
            if (_co != null) UpdateInShapeOwner();
        }

        public override void _Notification(int what)
        {
            base._Notification(what);
            if (what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED && _co != null) UpdateInShapeOwner(true);
        }

        protected override void OnUnparented()
        {
            if (_co != null) _co.RemoveShapeOwner(_ownerId);
            _ownerId = 0;
            _co = null;
            base.OnUnparented();
        }
    }
}

#endif
