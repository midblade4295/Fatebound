#if FB3D
// Godot's ragdoll pair (scene/3d/physics/physical_bone_3d.cpp and physical_bone_simulator_3d.cpp, 4.7), ported line by
// line onto the facade's physics seam (Physics3D.cs) and SkeletonModifier3D (Skeleton3D.cs):
//  * PhysicalBone3D: a body for one bone, a child of a PhysicalBoneSimulator3D. Entering the tree it binds to its bone,
//    puts itself at skeleton * bone global pose * body_offset (orthonormalized) and becomes KINEMATIC (STATIC with no
//    collision while its simulator is inactive), then (re)makes its joint to the nearest ancestor bone that has a
//    physical bone: frames joint_offset (in this body, its origin forced to body_offset's inverse origin) and the same
//    world frame in the parent body, taken from the bodies' transforms at that moment (the joint's rest pose).
//  * Simulating, it is RIGID and top level; after each step it takes the body's transform and tells the simulator the
//    bone's pose: skeleton_global^-1 * (body_global * body_offset^-1).
//  * PhysicalBoneSimulator3D: a SkeletonModifier3D; in the skeleton's modification pass it writes each simulated bone
//    with Skeleton3D.SetBoneGlobalPose (the skins and attachments show it; the animation's own poses come back after),
//    and while a bone isn't simulated it puts the body back at the animated pose.
// joint_constraints/* are stored properties (pb.Set("joint_constraints/swing_span", 50.0), degrees in, radians kept),
// all joint types' data as Godot; the backend makes pin, cone and hinge joints (Jolt-style frames, see PhysicsJointDesc).
// Differences: no editor gizmo / update_offset; set_joint_type(NONE) on a made joint leaves it as Godot does.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public partial class PhysicalBone3D : PhysicsBody3D
    {
        public enum DampModeEnum { Combine = 0, Replace = 1 }
        public const DampModeEnum DAMP_MODE_COMBINE = DampModeEnum.Combine, DAMP_MODE_REPLACE = DampModeEnum.Replace;
        public enum JointTypeEnum { None = 0, Pin = 1, Cone = 2, Hinge = 3, Slider = 4, SixDOF = 5 }
        public const JointTypeEnum JOINT_TYPE_NONE = JointTypeEnum.None, JOINT_TYPE_PIN = JointTypeEnum.Pin,
            JOINT_TYPE_CONE = JointTypeEnum.Cone, JOINT_TYPE_HINGE = JointTypeEnum.Hinge, JOINT_TYPE_SLIDER = JointTypeEnum.Slider,
            JOINT_TYPE_6DOF = JointTypeEnum.SixDOF;

        const string JC = "joint_constraints/";
        static float Deg2Rad(Var v) => GD.DegToRadF((float)v.AsFloat());
        static Var Rad2Deg(float r) => (double)GD.RadToDegF(r);

        // ------------------------------------------------------------------ joint data (Godot's JointData structs)
        public abstract class JointData
        {
            public abstract JointTypeEnum GetJointType();
            internal abstract bool Set(string name, Var v);
            internal abstract bool Get(string name, out Var v);
        }

        public sealed class PinJointData : JointData
        {
            public float bias = 0.3f, damping = 1.0f, impulse_clamp = 0.0f;
            public override JointTypeEnum GetJointType() => JointTypeEnum.Pin;
            internal override bool Set(string n, Var v)
            {
                switch (n)
                {
                    case JC + "bias": bias = (float)v.AsFloat(); return true;
                    case JC + "damping": damping = (float)v.AsFloat(); return true;
                    case JC + "impulse_clamp": impulse_clamp = (float)v.AsFloat(); return true;
                }
                return false;
            }
            internal override bool Get(string n, out Var v)
            {
                switch (n)
                {
                    case JC + "bias": v = (double)bias; return true;
                    case JC + "damping": v = (double)damping; return true;
                    case JC + "impulse_clamp": v = (double)impulse_clamp; return true;
                }
                v = Var.Nil;
                return false;
            }
        }

        public sealed class ConeJointData : JointData
        {
            public float swing_span = (float)(Math.PI * 0.25), twist_span = (float)Math.PI, bias = 0.3f, softness = 0.8f, relaxation = 1.0f;
            public override JointTypeEnum GetJointType() => JointTypeEnum.Cone;
            internal override bool Set(string n, Var v)
            {
                switch (n)
                {
                    case JC + "swing_span": swing_span = Deg2Rad(v); return true;
                    case JC + "twist_span": twist_span = Deg2Rad(v); return true;
                    case JC + "bias": bias = (float)v.AsFloat(); return true;
                    case JC + "softness": softness = (float)v.AsFloat(); return true;
                    case JC + "relaxation": relaxation = (float)v.AsFloat(); return true;
                }
                return false;
            }
            internal override bool Get(string n, out Var v)
            {
                switch (n)
                {
                    case JC + "swing_span": v = Rad2Deg(swing_span); return true;
                    case JC + "twist_span": v = Rad2Deg(twist_span); return true;
                    case JC + "bias": v = (double)bias; return true;
                    case JC + "softness": v = (double)softness; return true;
                    case JC + "relaxation": v = (double)relaxation; return true;
                }
                v = Var.Nil;
                return false;
            }
        }

        public sealed class HingeJointData : JointData
        {
            public bool angular_limit_enabled;
            public float angular_limit_upper = (float)(Math.PI * 0.5), angular_limit_lower = (float)(-Math.PI * 0.5),
                angular_limit_bias = 0.3f, angular_limit_softness = 0.9f, angular_limit_relaxation = 1.0f;
            public override JointTypeEnum GetJointType() => JointTypeEnum.Hinge;
            internal override bool Set(string n, Var v)
            {
                switch (n)
                {
                    case JC + "angular_limit_enabled": angular_limit_enabled = v.Truthy; return true;
                    case JC + "angular_limit_upper": angular_limit_upper = Deg2Rad(v); return true;
                    case JC + "angular_limit_lower": angular_limit_lower = Deg2Rad(v); return true;
                    case JC + "angular_limit_bias": angular_limit_bias = (float)v.AsFloat(); return true;
                    case JC + "angular_limit_softness": angular_limit_softness = (float)v.AsFloat(); return true;
                    case JC + "angular_limit_relaxation": angular_limit_relaxation = (float)v.AsFloat(); return true;
                }
                return false;
            }
            internal override bool Get(string n, out Var v)
            {
                switch (n)
                {
                    case JC + "angular_limit_enabled": v = angular_limit_enabled; return true;
                    case JC + "angular_limit_upper": v = Rad2Deg(angular_limit_upper); return true;
                    case JC + "angular_limit_lower": v = Rad2Deg(angular_limit_lower); return true;
                    case JC + "angular_limit_bias": v = (double)angular_limit_bias; return true;
                    case JC + "angular_limit_softness": v = (double)angular_limit_softness; return true;
                    case JC + "angular_limit_relaxation": v = (double)angular_limit_relaxation; return true;
                }
                v = Var.Nil;
                return false;
            }
        }

        public sealed class SliderJointData : JointData
        {
            public float linear_limit_upper = 1.0f, linear_limit_lower = -1.0f, linear_limit_softness = 1.0f, linear_limit_restitution = 0.7f,
                linear_limit_damping = 1.0f, angular_limit_upper, angular_limit_lower, angular_limit_softness = 1.0f,
                angular_limit_restitution = 0.7f, angular_limit_damping = 1.0f;
            public override JointTypeEnum GetJointType() => JointTypeEnum.Slider;
            internal override bool Set(string n, Var v)
            {
                switch (n)
                {
                    case JC + "linear_limit_upper": linear_limit_upper = (float)v.AsFloat(); return true;
                    case JC + "linear_limit_lower": linear_limit_lower = (float)v.AsFloat(); return true;
                    case JC + "linear_limit_softness": linear_limit_softness = (float)v.AsFloat(); return true;
                    case JC + "linear_limit_restitution": linear_limit_restitution = (float)v.AsFloat(); return true;
                    case JC + "linear_limit_damping": linear_limit_damping = (float)v.AsFloat(); return true;
                    case JC + "angular_limit_upper": angular_limit_upper = Deg2Rad(v); return true;
                    case JC + "angular_limit_lower": angular_limit_lower = Deg2Rad(v); return true;
                    case JC + "angular_limit_softness": angular_limit_softness = (float)v.AsFloat(); return true;
                    case JC + "angular_limit_restitution": angular_limit_restitution = (float)v.AsFloat(); return true;
                    case JC + "angular_limit_damping": angular_limit_damping = (float)v.AsFloat(); return true;
                }
                return false;
            }
            internal override bool Get(string n, out Var v)
            {
                switch (n)
                {
                    case JC + "linear_limit_upper": v = (double)linear_limit_upper; return true;
                    case JC + "linear_limit_lower": v = (double)linear_limit_lower; return true;
                    case JC + "linear_limit_softness": v = (double)linear_limit_softness; return true;
                    case JC + "linear_limit_restitution": v = (double)linear_limit_restitution; return true;
                    case JC + "linear_limit_damping": v = (double)linear_limit_damping; return true;
                    case JC + "angular_limit_upper": v = Rad2Deg(angular_limit_upper); return true;
                    case JC + "angular_limit_lower": v = Rad2Deg(angular_limit_lower); return true;
                    case JC + "angular_limit_softness": v = (double)angular_limit_softness; return true;
                    case JC + "angular_limit_restitution": v = (double)angular_limit_restitution; return true;
                    case JC + "angular_limit_damping": v = (double)angular_limit_damping; return true;
                }
                v = Var.Nil;
                return false;
            }
        }

        public sealed class SixDOFJointData : JointData
        {
            public sealed class AxisData
            {
                public bool linear_limit_enabled = true;
                public float linear_limit_upper, linear_limit_lower, linear_limit_softness = 0.7f, linear_restitution = 0.5f, linear_damping = 1.0f;
                public bool linear_spring_enabled;
                public float linear_spring_stiffness, linear_spring_damping, linear_equilibrium_point;
                public bool angular_limit_enabled = true;
                public float angular_limit_upper, angular_limit_lower, angular_limit_softness = 0.5f, angular_restitution, angular_damping = 1.0f, erp = 0.5f;
                public bool angular_spring_enabled;
                public float angular_spring_stiffness, angular_spring_damping, angular_equilibrium_point;
            }

            public readonly AxisData[] axis_data = { new AxisData(), new AxisData(), new AxisData() };
            public override JointTypeEnum GetJointType() => JointTypeEnum.SixDOF;

            static AxisData Axis(SixDOFJointData d, string n, out string var)
            {
                var = null;
                if (!n.StartsWith(JC)) return null;
                var parts = n.Split('/');
                if (parts.Length < 3) return null;
                int a = parts[1] == "x" ? 0 : parts[1] == "y" ? 1 : parts[1] == "z" ? 2 : -1;
                if (a < 0) return null;
                var = parts[2];
                return d.axis_data[a];
            }

            internal override bool Set(string n, Var v)
            {
                var ax = Axis(this, n, out string k);
                if (ax == null) return false;
                float f = (float)v.AsFloat();
                switch (k)
                {
                    case "linear_limit_enabled": ax.linear_limit_enabled = v.Truthy; break;
                    case "linear_limit_upper": ax.linear_limit_upper = f; break;
                    case "linear_limit_lower": ax.linear_limit_lower = f; break;
                    case "linear_limit_softness": ax.linear_limit_softness = f; break;
                    case "linear_spring_enabled": ax.linear_spring_enabled = v.Truthy; break;
                    case "linear_spring_stiffness": ax.linear_spring_stiffness = f; break;
                    case "linear_spring_damping": ax.linear_spring_damping = f; break;
                    case "linear_equilibrium_point": ax.linear_equilibrium_point = f; break;
                    case "linear_restitution": ax.linear_restitution = f; break;
                    case "linear_damping": ax.linear_damping = f; break;
                    case "angular_limit_enabled": ax.angular_limit_enabled = v.Truthy; break;
                    case "angular_limit_upper": ax.angular_limit_upper = Deg2Rad(v); break;
                    case "angular_limit_lower": ax.angular_limit_lower = Deg2Rad(v); break;
                    case "angular_limit_softness": ax.angular_limit_softness = f; break;
                    case "angular_restitution": ax.angular_restitution = f; break;
                    case "angular_damping": ax.angular_damping = f; break;
                    case "erp": ax.erp = f; break;
                    case "angular_spring_enabled": ax.angular_spring_enabled = v.Truthy; break;
                    case "angular_spring_stiffness": ax.angular_spring_stiffness = f; break;
                    case "angular_spring_damping": ax.angular_spring_damping = f; break;
                    case "angular_equilibrium_point": ax.angular_equilibrium_point = f; break;
                    default: return false;
                }
                return true;
            }

            internal override bool Get(string n, out Var v)
            {
                v = Var.Nil;
                var ax = Axis(this, n, out string k);
                if (ax == null) return false;
                switch (k)
                {
                    case "linear_limit_enabled": v = ax.linear_limit_enabled; break;
                    case "linear_limit_upper": v = (double)ax.linear_limit_upper; break;
                    case "linear_limit_lower": v = (double)ax.linear_limit_lower; break;
                    case "linear_limit_softness": v = (double)ax.linear_limit_softness; break;
                    case "linear_spring_enabled": v = ax.linear_spring_enabled; break;
                    case "linear_spring_stiffness": v = (double)ax.linear_spring_stiffness; break;
                    case "linear_spring_damping": v = (double)ax.linear_spring_damping; break;
                    case "linear_equilibrium_point": v = (double)ax.linear_equilibrium_point; break;
                    case "linear_restitution": v = (double)ax.linear_restitution; break;
                    case "linear_damping": v = (double)ax.linear_damping; break;
                    case "angular_limit_enabled": v = ax.angular_limit_enabled; break;
                    case "angular_limit_upper": v = Rad2Deg(ax.angular_limit_upper); break;
                    case "angular_limit_lower": v = Rad2Deg(ax.angular_limit_lower); break;
                    case "angular_limit_softness": v = (double)ax.angular_limit_softness; break;
                    case "angular_restitution": v = (double)ax.angular_restitution; break;
                    case "angular_damping": v = (double)ax.angular_damping; break;
                    case "erp": v = (double)ax.erp; break;
                    case "angular_spring_enabled": v = ax.angular_spring_enabled; break;
                    case "angular_spring_stiffness": v = (double)ax.angular_spring_stiffness; break;
                    case "angular_spring_damping": v = (double)ax.angular_spring_damping; break;
                    case "angular_equilibrium_point": v = (double)ax.angular_equilibrium_point; break;
                    default: return false;
                }
                return true;
            }
        }

        // ------------------------------------------------------------------ state
        JointData _jointData;
        Xform3 _jointOffset = Xform3.IDENTITY, _bodyOffset = Xform3.IDENTITY, _bodyOffsetInverse = Xform3.IDENTITY;
        PhysicalBoneSimulator3D _simulator;
        bool _simulatePhysics, _internalSimulatePhysics;
        int _boneId = -1;
        string _boneName = "";
        float _bounce, _mass = 1.0f, _friction = 1.0f, _gravityScale = 1.0f, _linearDamp, _angularDamp;
        Vec3 _linearVelocity, _angularVelocity;
        bool _canSleep = true, _customIntegrator;
        DampModeEnum _linearDampMode = DampModeEnum.Combine, _angularDampMode = DampModeEnum.Combine;
        // the joint as last made on the server (Godot's `joint` RID): parent body and frame A
        PhysicalBone3D _jointParent;
        Xform3 _jointLocalA = Xform3.IDENTITY;
        bool _jointMade;

        public PhysicalBone3D() : base(PhysicsBodyMode.Static)
        {
            ResetPhysicsSimulationState();
        }

        object B => PhysicsBackendData;

        // ------------------------------------------------------------------ stored properties
        /// <summary>_set: "bone_name" and the joint's "joint_constraints/*" (angles in degrees).</summary>
        public override bool SetStoredProperty(string name, Var value)
        {
            if (name == "bone_name") { BoneName = value.AsString(); return true; }
            if (_jointData != null && _jointData.Set(name, value))
            {
                if (_jointMade && _jointData.GetJointType() == JointType) PushJoint();       // (the server's joint_set_param)
                return true;
            }
            return base.SetStoredProperty(name, value);
        }

        public bool GetStoredProperty(string name, out Var value)
        {
            if (name == "bone_name") { value = _boneName; return true; }
            if (_jointData != null) return _jointData.Get(name, out value);
            value = Var.Nil;
            return false;
        }

        /// <summary>Object.set(property, value): the stored properties above, else the C# property of that name.</summary>
        public void Set(string property, Var value)
        {
            if (SetStoredProperty(property, value)) return;
            try { PropertyPath.Set(this, property, value.Obj); }
            catch (Exception) { /* Godot ignores an unknown property */ }
        }

        /// <summary>Object.get(property).</summary>
        public Var Get(string property)
        {
            if (GetStoredProperty(property, out var v)) return v;
            try { return Var.Of(PropertyPath.Get(this, property)); }
            catch (Exception) { return Var.Nil; }
        }

        public JointData GetJointData() => _jointData;

        // ------------------------------------------------------------------ tree
        protected override void OnPostEnterTree()
        {
            base.OnPostEnterTree();
            UpdateSimulatorPath();
            UpdateBoneId();
            ResetToRestPosition();
            ResetPhysicsSimulationState();
            if (_jointData != null) ReloadJoint();
        }

        void Detach()
        {
            var sim = GetSimulator();
            if (sim != null && _boneId != -1)
            {
                sim.UnbindPhysicalBoneFromBone(_boneId);
                _boneId = -1;
            }
            JointClear();
        }

        protected override void OnExitTree()
        {
            Detach();                         // (NOTIFICATION_EXIT_TREE, before the body leaves its space)
            base.OnExitTree();
        }

        protected override void OnUnparented()
        {
            Detach();
            base.OnUnparented();
        }

        // ------------------------------------------------------------------ simulator / skeleton
        void UpdateSimulatorPath() => _simulator = Parent as PhysicalBoneSimulator3D;
        public PhysicalBoneSimulator3D GetSimulator() => _simulator != null && !_simulator.IsFreed ? _simulator : null;
        public Skeleton3D GetSkeleton() => GetSimulator()?.GetSkeleton();
        public int GetBoneId() => _boneId;

        void UpdateBoneId()
        {
            var sim = GetSimulator();
            if (sim == null) return;
            int nb = sim.FindBone(_boneName);
            if (nb != _boneId)
            {
                if (_boneId != -1) sim.UnbindPhysicalBoneFromBone(_boneId);
                _boneId = nb;
                sim.BindPhysicalBoneToBone(_boneId, this);
                FixJointOffset();
                ResetPhysicsSimulationState();
            }
        }

        public void ResetToRestPosition()
        {
            var sim = GetSimulator();
            var sk = GetSkeleton();
            if (sim == null || sk == null) return;
            if (_boneId == -1) GlobalTransform = (sk.GlobalTransform * _bodyOffset).Orthonormalized();
            else GlobalTransform = (sk.GlobalTransform * sim.GetBoneGlobalPose(_boneId) * _bodyOffset).Orthonormalized();
        }

        public void ResetPhysicsSimulationState()
        {
            if (_simulatePhysics) StartPhysicsSimulation();
            else StopPhysicsSimulation();
        }

        void StartPhysicsSimulation()
        {
            if (_internalSimulatePhysics || _simulator == null || _boneId == -1) return;
            ResetToRestPosition();
            SetBodyMode(PhysicsBodyMode.Rigid);
            ServerSetCollision(CollisionLayer, CollisionMask);
            SetStateSync(true);
            TopLevel = true;
            _internalSimulatePhysics = true;
        }

        void StopPhysicsSimulation()
        {
            var sim = GetSimulator();
            if (sim != null)
            {
                if (sim.IsActive() && _boneId != -1)
                {
                    SetBodyMode(PhysicsBodyMode.Kinematic);
                    ServerSetCollision(CollisionLayer, CollisionMask);
                }
                else
                {
                    SetBodyMode(PhysicsBodyMode.Static);
                    ServerSetCollision(0, 0);
                }
            }
            if (_internalSimulatePhysics)
            {
                SetStateSync(false);
                TopLevel = false;
                _internalSimulatePhysics = false;
            }
        }

        internal void SetSimulatePhysics(bool simulate)
        {
            if (_simulatePhysics == simulate) return;
            _simulatePhysics = simulate;
            ResetPhysicsSimulationState();
        }

        public bool GetSimulatePhysics() => _simulatePhysics;
        public bool IsSimulatingPhysics() => _internalSimulatePhysics;

        /// <summary>_body_state_changed: the body's state, and the bone's pose for the simulator.</summary>
        internal override void SyncFromPhysics(in PhysicsBodyState s)
        {
            if (!_simulatePhysics || !_internalSimulatePhysics) return;
            if (s.Transform != GlobalTransform) SetGlobalTransformFromPhysics(s.Transform);
            _linearVelocity = s.LinearVelocity;
            _angularVelocity = s.AngularVelocity;
            var sim = GetSimulator();
            var sk = GetSkeleton();
            if (sim != null && sk != null && _boneId != -1)
                sim.SetBoneGlobalPose(_boneId, sk.GlobalTransform.AffineInverse() * (s.Transform * _bodyOffsetInverse));
        }

        // ------------------------------------------------------------------ joint
        internal void OnBoneParentChanged() => ReloadJoint();

        void FixJointOffset()
        {
            if (GetSimulator() != null) _jointOffset.origin = _bodyOffset.AffineInverse().origin;
        }

        void UpdateJointOffset()
        {
            FixJointOffset();
            ResetToRestPosition();
        }

        void ReloadJoint()
        {
            var sim = GetSimulator();
            if (sim == null || sim.GetSkeleton() == null) { JointClear(); return; }
            var a = sim.GetPhysicalBoneParent(_boneId);
            if (a == null) { JointClear(); return; }
            if (JointType == JointTypeEnum.None) return;          // (Godot: nothing; a joint made before stays)
            Xform3 jointXf = GlobalTransform * _jointOffset;
            Xform3 localA = a.GlobalTransform.AffineInverse() * jointXf;
            _jointLocalA = localA.Orthonormalized();
            _jointParent = a;
            _jointMade = true;
            PushJoint();
        }

        void PushJoint()
        {
            var be = Be;
            if (be == null || B == null || _jointParent == null || _jointParent.PhysicsBackendData == null) return;
            var d = new PhysicsJointDesc { Type = JointType, FrameA = _jointLocalA, FrameB = _jointOffset };
            switch (_jointData)
            {
                case ConeJointData c: d.SwingSpan = c.swing_span; d.TwistSpan = c.twist_span; break;
                case HingeJointData h:
                    d.AngularLimitEnabled = h.angular_limit_enabled;
                    d.AngularLimitUpper = h.angular_limit_upper;
                    d.AngularLimitLower = h.angular_limit_lower;
                    break;
            }
            be.BodySetJoint(B, _jointParent.PhysicsBackendData, d);
        }

        void JointClear()
        {
            bool had = _jointMade;
            _jointMade = false;
            _jointParent = null;
            if (had && B != null) Be?.BodyClearJoint(B);
        }

        public JointTypeEnum JointType
        {
            get => _jointData?.GetJointType() ?? JointTypeEnum.None;
            set
            {
                if (value == JointType) return;
                switch (value)
                {
                    case JointTypeEnum.Pin: _jointData = new PinJointData(); break;
                    case JointTypeEnum.Cone: _jointData = new ConeJointData(); break;
                    case JointTypeEnum.Hinge: _jointData = new HingeJointData(); break;
                    case JointTypeEnum.Slider: _jointData = new SliderJointData(); break;
                    case JointTypeEnum.SixDOF: _jointData = new SixDOFJointData(); break;
                    default: _jointData = null; break;
                }
                ReloadJoint();
            }
        }

        public Xform3 JointOffset { get => _jointOffset; set { _jointOffset = value; UpdateJointOffset(); } }

        public Vec3 JointRotation
        {
            get => _jointOffset.basis.GetEulerNormalized();
            set
            {
                _jointOffset.basis = Basis.FromEuler(value) * Basis.FromScale(_jointOffset.basis.GetScale());   // (set_euler_scale)
                UpdateJointOffset();
            }
        }

        public Xform3 BodyOffset
        {
            get => _bodyOffset;
            set
            {
                _bodyOffset = value;
                _bodyOffsetInverse = value.AffineInverse();
                UpdateJointOffset();
            }
        }

        public string BoneName
        {
            get => _boneName;
            set
            {
                _boneName = value ?? "";
                _boneId = -1;
                UpdateBoneId();
                ResetToRestPosition();
            }
        }

        // ------------------------------------------------------------------ body parameters
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

        public double Friction
        {
            get => _friction;
            set
            {
                if (value < 0 || value > 1) { GD.PushError("Condition \"p_friction < 0 || p_friction > 1\" is true."); return; }
                _friction = (float)value;
                if (B != null) Be?.BodySetMaterial(B, _friction, _bounce);
            }
        }

        public double Bounce
        {
            get => _bounce;
            set
            {
                if (value < 0 || value > 1) { GD.PushError("Condition \"p_bounce < 0 || p_bounce > 1\" is true."); return; }
                _bounce = (float)value;
                if (B != null) Be?.BodySetMaterial(B, _friction, _bounce);
            }
        }

        public double GravityScale { get => _gravityScale; set { _gravityScale = (float)value; if (B != null) Be?.BodySetGravityScale(B, _gravityScale); } }
        public DampModeEnum LinearDampMode { get => _linearDampMode; set { _linearDampMode = value; PushDamping(); } }
        public DampModeEnum AngularDampMode { get => _angularDampMode; set { _angularDampMode = value; PushDamping(); } }

        public double LinearDamp
        {
            get => _linearDamp;
            set
            {
                if (value < 0) { GD.PushError("Condition \"p_linear_damp < 0\" is true."); return; }
                _linearDamp = (float)value;
                PushDamping();
            }
        }

        public double AngularDamp
        {
            get => _angularDamp;
            set
            {
                if (value < 0) { GD.PushError("Condition \"p_angular_damp < 0\" is true."); return; }
                _angularDamp = (float)value;
                PushDamping();
            }
        }

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
        public bool CanSleep { get => _canSleep; set { _canSleep = value; if (B != null) Be?.BodySetCanSleep(B, value); } }
        public bool IsAbleToSleep() => _canSleep;
        /// <summary>Stored (_integrate_forces isn't called by the port).</summary>
        public bool CustomIntegrator { get => _customIntegrator; set => _customIntegrator = value; }

        public void ApplyCentralImpulse(Vec3 impulse) { if (B != null) Be?.BodyApplyImpulse(B, impulse, Vec3.Zero); }
        public void ApplyImpulse(Vec3 impulse, Vec3 position = default) { if (B != null) Be?.BodyApplyImpulse(B, impulse, position); }

        protected override void PushBodyParams(IPhysics3D be)
        {
            var b = B;
            be.BodySetMass(b, _mass);
            be.BodySetMaterial(b, _friction, _bounce);
            be.BodySetGravityScale(b, _gravityScale);
            be.BodySetDamping(b, TotalLinearDamp, TotalAngularDamp);
            be.BodySetCanSleep(b, _canSleep);
            be.BodySetLinearVelocity(b, _linearVelocity);
            be.BodySetAngularVelocity(b, _angularVelocity);
            if (_jointMade) PushJoint();
        }
    }

    // ================================================================== PhysicalBoneSimulator3D
    public partial class PhysicalBoneSimulator3D : SkeletonModifier3D
    {
        sealed class SimulatedBone
        {
            public int parent = -1;
            public int[] childBones = Array.Empty<int>();
            public Xform3 globalPose = Xform3.IDENTITY;
            public PhysicalBone3D physicalBone, cacheParentPhysicalBone;
        }

        bool _simulating;
        readonly List<SimulatedBone> _bones = new List<SimulatedBone>();
        Skeleton3D _connected;
        readonly Action _onBoneListChanged, _onPoseUpdated;

        public PhysicalBoneSimulator3D()
        {
            _onBoneListChanged = BoneListChangedHandler;
            _onPoseUpdated = PoseUpdatedHandler;
        }

        void Connect(Skeleton3D sk)
        {
            if (_connected == sk) return;
            if (_connected != null)
            {
                _connected.BoneListChanged -= _onBoneListChanged;
                _connected.PoseUpdated -= _onPoseUpdated;
            }
            _connected = sk;
            if (sk != null)
            {
                sk.BoneListChanged += _onBoneListChanged;
                sk.PoseUpdated += _onPoseUpdated;
            }
        }

        protected override void _SkeletonChanged(Skeleton3D oldSkeleton, Skeleton3D newSkeleton)
        {
            Connect(newSkeleton);
            BoneListChangedHandler();
        }

        // (Godot's connections die with the object; the skeleton's events would keep a freed simulator)
        protected override void OnFreed()
        {
            Connect(null);
            base.OnFreed();
        }

        void BoneListChangedHandler()
        {
            if (IsFreed) return;
            _bones.Clear();
            var sk = GetSkeleton();
            if (sk == null) return;
            for (int i = 0; i < sk.GetBoneCount(); i++)
                _bones.Add(new SimulatedBone { parent = sk.GetBoneParent(i), childBones = sk.GetBoneChildren(i) });
            RebuildPhysicalBonesCache();
            PoseUpdatedHandler();
        }

        void PoseUpdatedHandler()
        {
            if (IsFreed) return;
            var sk = GetSkeleton();
            if (sk == null || _simulating) return;
            if (sk.GetBoneCount() != _bones.Count) BoneListChangedHandler();
            else for (int i = 0; i < sk.GetBoneCount(); i++) BonePoseUpdated(sk, i);
        }

        void BonePoseUpdated(Skeleton3D sk, int bone)
        {
            if ((uint)bone >= (uint)_bones.Count) { GD.PushError("Index p_bone_id = " + bone + " is out of bounds."); return; }
            _bones[bone].globalPose = sk.GetBoneGlobalPose(bone);
        }

        protected override void _SetActive(bool active) => ResetPhysicalBonesState();

        void ResetPhysicalBonesState()
        {
            for (int i = 0; i < _bones.Count; i++) _bones[i].physicalBone?.ResetPhysicsSimulationState();
        }

        public bool IsSimulatingPhysics() => _simulating;
        public int FindBone(string name) => GetSkeleton()?.FindBone(name) ?? -1;
        public string GetBoneName(int bone) => GetSkeleton()?.GetBoneName(bone) ?? "";
        public int GetBoneCount() => _bones.Count;
        public bool IsBoneParentOf(int bone, int parentBone) => GetSkeleton()?.IsBoneParentOf(bone, parentBone) ?? false;

        bool BoneOk(int bone)
        {
            if ((uint)bone < (uint)_bones.Count) return true;
            GD.PushError("Index p_bone = " + bone + " is out of bounds (bone_size = " + _bones.Count + ").");
            return false;
        }

        public void BindPhysicalBoneToBone(int bone, PhysicalBone3D pb)
        {
            if (!BoneOk(bone)) return;
            if (_bones[bone].physicalBone != null) { GD.PushError("Condition \"bones[p_bone].physical_bone\" is true."); return; }
            if (pb == null) { GD.PushError("Parameter \"p_physical_bone\" is null."); return; }
            _bones[bone].physicalBone = pb;
            RebuildPhysicalBonesCache();
        }

        public void UnbindPhysicalBoneFromBone(int bone)
        {
            if (!BoneOk(bone)) return;
            _bones[bone].physicalBone = null;
            RebuildPhysicalBonesCache();
        }

        public PhysicalBone3D GetPhysicalBone(int bone) => BoneOk(bone) ? _bones[bone].physicalBone : null;

        public PhysicalBone3D GetPhysicalBoneParent(int bone)
        {
            if (!BoneOk(bone)) return null;
            return _bones[bone].cacheParentPhysicalBone ?? GetPhysicalBoneParentUncached(bone);
        }

        PhysicalBone3D GetPhysicalBoneParentUncached(int bone)
        {
            if (!BoneOk(bone)) return null;
            int parent = _bones[bone].parent;
            if (parent < 0) return null;
            return _bones[parent].physicalBone ?? GetPhysicalBoneParent(parent);
        }

        void RebuildPhysicalBonesCache()
        {
            for (int i = 0; i < _bones.Count; i++)
            {
                var parentPb = GetPhysicalBoneParentUncached(i);
                if (parentPb != _bones[i].cacheParentPhysicalBone)
                {
                    _bones[i].cacheParentPhysicalBone = parentPb;
                    _bones[i].physicalBone?.OnBoneParentChanged();
                }
            }
        }

        public void PhysicalBonesStopSimulation()
        {
            _simulating = false;
            ResetPhysicalBonesState();
            StopSimulation(this);
        }

        static void StopSimulation(Node n)
        {
            for (int i = n.GetChildCount() - 1; i >= 0; --i)
                if (n.GetChild(i) is PhysicalBone3D pb) StopSimulation(pb);
            if (n is PhysicalBone3D self) self.SetSimulatePhysics(false);
        }

        /// <summary>physical_bones_start_simulation(bones = []): those bones and their descendants (all when empty).</summary>
        public void PhysicalBonesStartSimulation(IReadOnlyList<string> bones = null)
        {
            PoseUpdatedHandler();
            _simulating = true;
            ResetPhysicalBonesState();
            var sim = new List<int>();
            if (bones != null)
                for (int i = bones.Count - 1; i >= 0; --i)
                {
                    int id = FindBone(bones[i]);
                    if (id != -1) sim.Add(id);
                }
            StartSimulation(this, this, sim);
        }

        public void PhysicalBonesStartSimulation(GArray bones)
        {
            var l = new List<string>();
            if (bones != null) foreach (var b in bones) l.Add(b.AsString());
            PhysicalBonesStartSimulation(l);
        }

        static void StartSimulation(PhysicalBoneSimulator3D s, Node n, List<int> simBones)
        {
            for (int i = n.GetChildCount() - 1; i >= 0; --i)
                if (n.GetChild(i) is PhysicalBone3D pb) StartSimulation(s, pb, simBones);
            if (!(n is PhysicalBone3D self)) return;
            if (simBones.Count == 0) { self.SetSimulatePhysics(true); return; }
            for (int i = simBones.Count - 1; i >= 0; --i)
                if (simBones[i] == self.GetBoneId() || s.IsBoneParentOf(self.GetBoneId(), simBones[i]))
                {
                    self.SetSimulatePhysics(true);
                    break;
                }
        }

        public Xform3 GetBoneGlobalPose(int bone) => BoneOk(bone) ? _bones[bone].globalPose : Xform3.IDENTITY;

        public void SetBoneGlobalPose(int bone, Xform3 pose)
        {
            if (BoneOk(bone)) _bones[bone].globalPose = pose;
        }

        protected override void _ProcessModificationWithDelta(double delta)
        {
            var sk = GetSkeleton();
            if (sk == null) return;
            if (sk.GetBoneCount() != _bones.Count) { GD.PushError("Condition \"skeleton->get_bone_count() != (int)bones.size()\" is true."); return; }
            for (int i = 0; i < sk.GetBoneCount(); i++)
            {
                var pb = _bones[i].physicalBone;
                if (pb == null) continue;
                if (!pb.IsSimulatingPhysics())
                {
                    BonePoseUpdated(sk, i);
                    pb.ResetToRestPosition();
                }
                else if (_simulating) sk.SetBoneGlobalPose(i, _bones[i].globalPose);
            }
        }
    }
}

#endif
