#if FB3D
// Godot's ParticleProcessMaterial (scene/resources/particle_process_material.cpp): every property with Godot's default
// (the constructor's set_* calls), the PARAM_* min/max/curve triples behind set_param_min/max/texture (a min above
// the max drags the other along, as Godot does), particle flags, emission shapes, turbulence, collision, sub-emitter.
// Curves assigned as param textures get Godot's default curve range when they have none (ensure_default_setup).
// Every change calls EmitChanged(). ParticlesSim (ParticlesSim.cs) runs the shader this material generates.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public class ParticleProcessMaterial : GMaterial
    {
        public const int PARAM_INITIAL_LINEAR_VELOCITY = 0, PARAM_ANGULAR_VELOCITY = 1, PARAM_ORBIT_VELOCITY = 2, PARAM_LINEAR_ACCEL = 3,
            PARAM_RADIAL_ACCEL = 4, PARAM_TANGENTIAL_ACCEL = 5, PARAM_DAMPING = 6, PARAM_ANGLE = 7, PARAM_SCALE = 8, PARAM_HUE_VARIATION = 9,
            PARAM_ANIM_SPEED = 10, PARAM_ANIM_OFFSET = 11, PARAM_TURB_INFLUENCE_OVER_LIFE = 12, PARAM_TURB_VEL_INFLUENCE = 13,
            PARAM_TURB_INIT_DISPLACEMENT = 14, PARAM_RADIAL_VELOCITY = 15, PARAM_DIRECTIONAL_VELOCITY = 16, PARAM_SCALE_OVER_VELOCITY = 17,
            PARAM_MAX = 18;
        public const int PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY = 0, PARTICLE_FLAG_ROTATE_Y = 1, PARTICLE_FLAG_DISABLE_Z = 2,
            PARTICLE_FLAG_DAMPING_AS_FRICTION = 3, PARTICLE_FLAG_INHERIT_EMITTER_SCALE = 4, PARTICLE_FLAG_MAX = 5;
        public const int EMISSION_SHAPE_POINT = 0, EMISSION_SHAPE_SPHERE = 1, EMISSION_SHAPE_SPHERE_SURFACE = 2, EMISSION_SHAPE_BOX = 3,
            EMISSION_SHAPE_POINTS = 4, EMISSION_SHAPE_DIRECTED_POINTS = 5, EMISSION_SHAPE_RING = 6, EMISSION_SHAPE_MAX = 7;
        public const int SUB_EMITTER_DISABLED = 0, SUB_EMITTER_CONSTANT = 1, SUB_EMITTER_AT_END = 2, SUB_EMITTER_AT_COLLISION = 3,
            SUB_EMITTER_AT_START = 4, SUB_EMITTER_MAX = 5;
        public const int COLLISION_DISABLED = 0, COLLISION_RIGID = 1, COLLISION_HIDE_ON_CONTACT = 2, COLLISION_MAX = 3;

        readonly float[] _min = new float[PARAM_MAX], _max = new float[PARAM_MAX];
        Texture2D[] _tex = new Texture2D[PARAM_MAX];
        bool[] _flags = new bool[PARTICLE_FLAG_MAX];

        Vec3 _direction, _velocityPivot, _boxExtents, _ringAxis, _shapeOffset, _shapeScale, _turbSpeed, _gravity,
            _scale3dMin, _scale3dMax, _rot3dMin, _rot3dMax, _rotVel3dMin, _rotVel3dMax;
        float _spread, _flatness, _sphereRadius, _ringHeight, _ringRadius, _ringInnerRadius, _ringConeAngle,
            _turbStrength, _turbScale, _turbSpeedRandom, _collisionFriction, _collisionBounce;
        double _lifetimeRandomness, _inheritVelocityRatio, _subFrequency;
        int _emissionShape, _pointCount = 1, _subMode, _subAtEnd, _subAtCollision, _subAtStart, _collisionMode;
        bool _turbulence, _useScale3d, _useRotation3d, _useRotVel3d, _subKeepVelocity, _attractors, _collisionScale;
        Col _color;
        Texture2D _colorRamp, _colorInitialRamp, _alphaCurve, _emissionCurve, _velocityLimitCurve, _rotVel3dCurve,
            _pointTexture, _normalTexture, _colorTexture;

        void C() => EmitChanged();
        static void Err(string m) => GD.PushError(m);

        public ParticleProcessMaterial()
        {
            _direction = new Vec3(1f, 0f, 0f);
            _spread = 45f;
            _flatness = 0f;
            _min[PARAM_SCALE] = 1f; _max[PARAM_SCALE] = 1f;
            _min[PARAM_DIRECTIONAL_VELOCITY] = 1f; _max[PARAM_DIRECTIONAL_VELOCITY] = 1f;
            _scale3dMin = new Vec3(1f, 1f, 1f); _scale3dMax = new Vec3(1f, 1f, 1f);
            _emissionShape = EMISSION_SHAPE_POINT;
            _sphereRadius = 1f;
            _boxExtents = new Vec3(1f, 1f, 1f);
            _ringAxis = new Vec3(0f, 0f, 1f);
            _ringHeight = 1f;
            _ringRadius = 1f;
            _ringInnerRadius = 0f;
            _ringConeAngle = 90f;
            _shapeOffset = new Vec3(0f, 0f, 0f);
            _shapeScale = new Vec3(1f, 1f, 1f);
            _turbulence = false;
            _turbSpeed = new Vec3(0f, 0f, 0f);
            _turbStrength = 1f;
            _turbScale = 9f;
            _turbSpeedRandom = 0.2f;
            _min[PARAM_TURB_VEL_INFLUENCE] = 0.1f; _max[PARAM_TURB_VEL_INFLUENCE] = 0.1f;
            _gravity = new Vec3(0f, -9.8f, 0f);
            _lifetimeRandomness = 0;
            _subMode = SUB_EMITTER_DISABLED;
            _subFrequency = 4;
            _subAtEnd = 1;
            _subAtCollision = 1;
            _subAtStart = 1;
            _attractors = true;
            _collisionMode = COLLISION_DISABLED;
            _color = new Col(1f, 1f, 1f, 1f);
        }

        // ---------------------------------------------------------------- params
        public void SetParamMin(int param, double value)
        {
            if (param < 0 || param >= PARAM_MAX) { Err("Index p_param = " + param + " is out of bounds (PARAM_MAX = " + PARAM_MAX + ")."); return; }
            _min[param] = (float)value;
            if (_min[param] > _max[param]) SetParamMax(param, value);
            C();
        }

        public void SetParamMax(int param, double value)
        {
            if (param < 0 || param >= PARAM_MAX) { Err("Index p_param = " + param + " is out of bounds (PARAM_MAX = " + PARAM_MAX + ")."); return; }
            _max[param] = (float)value;
            if (_min[param] > _max[param]) SetParamMin(param, value);
            C();
        }

        public double GetParamMin(int param) => param >= 0 && param < PARAM_MAX ? _min[param] : 0;
        public double GetParamMax(int param) => param >= 0 && param < PARAM_MAX ? _max[param] : 0;
        public void SetParam(int param, Vec2 v) { SetParamMin(param, v.x); SetParamMax(param, v.y); }
        public Vec2 GetParam(int param) => new Vec2((float)GetParamMin(param), (float)GetParamMax(param));

        public void SetParamTexture(int param, Texture2D texture)
        {
            if (param < 0 || param >= PARAM_MAX) { Err("Index p_param = " + param + " is out of bounds (PARAM_MAX = " + PARAM_MAX + ")."); return; }
            _tex[param] = texture;
            switch (param)
            {
                case PARAM_ANGULAR_VELOCITY: AdjustCurveRange(texture, -360, 360); break;
                case PARAM_ORBIT_VELOCITY: AdjustCurveRange(texture, -2, 2); break;
                case PARAM_LINEAR_ACCEL: case PARAM_RADIAL_ACCEL: case PARAM_TANGENTIAL_ACCEL: AdjustCurveRange(texture, -200, 200); break;
                case PARAM_DAMPING: AdjustCurveRange(texture, 0, 100); break;
                case PARAM_ANGLE: AdjustCurveRange(texture, -360, 360); break;
                case PARAM_SCALE: AdjustCurveRange(texture, 0, 1); break;
                case PARAM_HUE_VARIATION: AdjustCurveRange(texture, -1, 1); break;
                case PARAM_ANIM_SPEED: AdjustCurveRange(texture, 0, 200); break;
                case PARAM_TURB_INFLUENCE_OVER_LIFE: AdjustCurveRange(texture, 0, 1); break;
                case PARAM_SCALE_OVER_VELOCITY: AdjustCurveRange(texture, 0, 3); break;
            }
            C();
        }

        public Texture2D GetParamTexture(int param) => param >= 0 && param < PARAM_MAX ? _tex[param] : null;

        static void AdjustCurveRange(Texture2D t, float min, float max)
        {
            if (t is CurveTexture ct) ct.EnsureDefaultSetup(min, max);
            else if (t is CurveXYZTexture cx) cx.EnsureDefaultSetup(min, max);
        }

        /// <summary>The raw arrays (renderer / ParticlesSim access).</summary>
        public IReadOnlyList<float> ParamsMin => _min;
        public IReadOnlyList<float> ParamsMax => _max;
        public IReadOnlyList<Texture2D> ParamTextures => _tex;

        public void SetParticleFlag(int flag, bool enable)
        {
            if (flag < 0 || flag >= PARTICLE_FLAG_MAX) { Err("Index p_particle_flag out of bounds."); return; }
            _flags[flag] = enable;
            C();
        }

        public bool GetParticleFlag(int flag) => flag >= 0 && flag < PARTICLE_FLAG_MAX && _flags[flag];

        // ---------------------------------------------------------------- the min/max/curve properties
        public Vec2 Angle { get => GetParam(PARAM_ANGLE); set => SetParam(PARAM_ANGLE, value); }
        public double AngleMin { get => GetParamMin(PARAM_ANGLE); set => SetParamMin(PARAM_ANGLE, value); }
        public double AngleMax { get => GetParamMax(PARAM_ANGLE); set => SetParamMax(PARAM_ANGLE, value); }
        public Texture2D AngleCurve { get => GetParamTexture(PARAM_ANGLE); set => SetParamTexture(PARAM_ANGLE, value); }
        public Vec2 InitialVelocity { get => GetParam(PARAM_INITIAL_LINEAR_VELOCITY); set => SetParam(PARAM_INITIAL_LINEAR_VELOCITY, value); }
        public double InitialVelocityMin { get => GetParamMin(PARAM_INITIAL_LINEAR_VELOCITY); set => SetParamMin(PARAM_INITIAL_LINEAR_VELOCITY, value); }
        public double InitialVelocityMax { get => GetParamMax(PARAM_INITIAL_LINEAR_VELOCITY); set => SetParamMax(PARAM_INITIAL_LINEAR_VELOCITY, value); }
        public Vec2 AngularVelocity { get => GetParam(PARAM_ANGULAR_VELOCITY); set => SetParam(PARAM_ANGULAR_VELOCITY, value); }
        public double AngularVelocityMin { get => GetParamMin(PARAM_ANGULAR_VELOCITY); set => SetParamMin(PARAM_ANGULAR_VELOCITY, value); }
        public double AngularVelocityMax { get => GetParamMax(PARAM_ANGULAR_VELOCITY); set => SetParamMax(PARAM_ANGULAR_VELOCITY, value); }
        public Texture2D AngularVelocityCurve { get => GetParamTexture(PARAM_ANGULAR_VELOCITY); set => SetParamTexture(PARAM_ANGULAR_VELOCITY, value); }
        public Vec2 DirectionalVelocity { get => GetParam(PARAM_DIRECTIONAL_VELOCITY); set => SetParam(PARAM_DIRECTIONAL_VELOCITY, value); }
        public double DirectionalVelocityMin { get => GetParamMin(PARAM_DIRECTIONAL_VELOCITY); set => SetParamMin(PARAM_DIRECTIONAL_VELOCITY, value); }
        public double DirectionalVelocityMax { get => GetParamMax(PARAM_DIRECTIONAL_VELOCITY); set => SetParamMax(PARAM_DIRECTIONAL_VELOCITY, value); }
        public Texture2D DirectionalVelocityCurve { get => GetParamTexture(PARAM_DIRECTIONAL_VELOCITY); set => SetParamTexture(PARAM_DIRECTIONAL_VELOCITY, value); }
        public Vec2 OrbitVelocity { get => GetParam(PARAM_ORBIT_VELOCITY); set => SetParam(PARAM_ORBIT_VELOCITY, value); }
        public double OrbitVelocityMin { get => GetParamMin(PARAM_ORBIT_VELOCITY); set => SetParamMin(PARAM_ORBIT_VELOCITY, value); }
        public double OrbitVelocityMax { get => GetParamMax(PARAM_ORBIT_VELOCITY); set => SetParamMax(PARAM_ORBIT_VELOCITY, value); }
        public Texture2D OrbitVelocityCurve { get => GetParamTexture(PARAM_ORBIT_VELOCITY); set => SetParamTexture(PARAM_ORBIT_VELOCITY, value); }
        public Vec2 RadialVelocity { get => GetParam(PARAM_RADIAL_VELOCITY); set => SetParam(PARAM_RADIAL_VELOCITY, value); }
        public double RadialVelocityMin { get => GetParamMin(PARAM_RADIAL_VELOCITY); set => SetParamMin(PARAM_RADIAL_VELOCITY, value); }
        public double RadialVelocityMax { get => GetParamMax(PARAM_RADIAL_VELOCITY); set => SetParamMax(PARAM_RADIAL_VELOCITY, value); }
        public Texture2D RadialVelocityCurve { get => GetParamTexture(PARAM_RADIAL_VELOCITY); set => SetParamTexture(PARAM_RADIAL_VELOCITY, value); }
        public Vec2 LinearAccel { get => GetParam(PARAM_LINEAR_ACCEL); set => SetParam(PARAM_LINEAR_ACCEL, value); }
        public double LinearAccelMin { get => GetParamMin(PARAM_LINEAR_ACCEL); set => SetParamMin(PARAM_LINEAR_ACCEL, value); }
        public double LinearAccelMax { get => GetParamMax(PARAM_LINEAR_ACCEL); set => SetParamMax(PARAM_LINEAR_ACCEL, value); }
        public Texture2D LinearAccelCurve { get => GetParamTexture(PARAM_LINEAR_ACCEL); set => SetParamTexture(PARAM_LINEAR_ACCEL, value); }
        public Vec2 RadialAccel { get => GetParam(PARAM_RADIAL_ACCEL); set => SetParam(PARAM_RADIAL_ACCEL, value); }
        public double RadialAccelMin { get => GetParamMin(PARAM_RADIAL_ACCEL); set => SetParamMin(PARAM_RADIAL_ACCEL, value); }
        public double RadialAccelMax { get => GetParamMax(PARAM_RADIAL_ACCEL); set => SetParamMax(PARAM_RADIAL_ACCEL, value); }
        public Texture2D RadialAccelCurve { get => GetParamTexture(PARAM_RADIAL_ACCEL); set => SetParamTexture(PARAM_RADIAL_ACCEL, value); }
        public Vec2 TangentialAccel { get => GetParam(PARAM_TANGENTIAL_ACCEL); set => SetParam(PARAM_TANGENTIAL_ACCEL, value); }
        public double TangentialAccelMin { get => GetParamMin(PARAM_TANGENTIAL_ACCEL); set => SetParamMin(PARAM_TANGENTIAL_ACCEL, value); }
        public double TangentialAccelMax { get => GetParamMax(PARAM_TANGENTIAL_ACCEL); set => SetParamMax(PARAM_TANGENTIAL_ACCEL, value); }
        public Texture2D TangentialAccelCurve { get => GetParamTexture(PARAM_TANGENTIAL_ACCEL); set => SetParamTexture(PARAM_TANGENTIAL_ACCEL, value); }
        public Vec2 Damping { get => GetParam(PARAM_DAMPING); set => SetParam(PARAM_DAMPING, value); }
        public double DampingMin { get => GetParamMin(PARAM_DAMPING); set => SetParamMin(PARAM_DAMPING, value); }
        public double DampingMax { get => GetParamMax(PARAM_DAMPING); set => SetParamMax(PARAM_DAMPING, value); }
        public Texture2D DampingCurve { get => GetParamTexture(PARAM_DAMPING); set => SetParamTexture(PARAM_DAMPING, value); }
        public Vec2 Scale { get => GetParam(PARAM_SCALE); set => SetParam(PARAM_SCALE, value); }
        public double ScaleMin { get => GetParamMin(PARAM_SCALE); set => SetParamMin(PARAM_SCALE, value); }
        public double ScaleMax { get => GetParamMax(PARAM_SCALE); set => SetParamMax(PARAM_SCALE, value); }
        public Texture2D ScaleCurve { get => GetParamTexture(PARAM_SCALE); set => SetParamTexture(PARAM_SCALE, value); }
        public Vec2 ScaleOverVelocity { get => GetParam(PARAM_SCALE_OVER_VELOCITY); set => SetParam(PARAM_SCALE_OVER_VELOCITY, value); }
        public double ScaleOverVelocityMin { get => GetParamMin(PARAM_SCALE_OVER_VELOCITY); set => SetParamMin(PARAM_SCALE_OVER_VELOCITY, value); }
        public double ScaleOverVelocityMax { get => GetParamMax(PARAM_SCALE_OVER_VELOCITY); set => SetParamMax(PARAM_SCALE_OVER_VELOCITY, value); }
        public Texture2D ScaleOverVelocityCurve { get => GetParamTexture(PARAM_SCALE_OVER_VELOCITY); set => SetParamTexture(PARAM_SCALE_OVER_VELOCITY, value); }
        public Vec2 HueVariation { get => GetParam(PARAM_HUE_VARIATION); set => SetParam(PARAM_HUE_VARIATION, value); }
        public double HueVariationMin { get => GetParamMin(PARAM_HUE_VARIATION); set => SetParamMin(PARAM_HUE_VARIATION, value); }
        public double HueVariationMax { get => GetParamMax(PARAM_HUE_VARIATION); set => SetParamMax(PARAM_HUE_VARIATION, value); }
        public Texture2D HueVariationCurve { get => GetParamTexture(PARAM_HUE_VARIATION); set => SetParamTexture(PARAM_HUE_VARIATION, value); }
        public Vec2 AnimSpeed { get => GetParam(PARAM_ANIM_SPEED); set => SetParam(PARAM_ANIM_SPEED, value); }
        public double AnimSpeedMin { get => GetParamMin(PARAM_ANIM_SPEED); set => SetParamMin(PARAM_ANIM_SPEED, value); }
        public double AnimSpeedMax { get => GetParamMax(PARAM_ANIM_SPEED); set => SetParamMax(PARAM_ANIM_SPEED, value); }
        public Texture2D AnimSpeedCurve { get => GetParamTexture(PARAM_ANIM_SPEED); set => SetParamTexture(PARAM_ANIM_SPEED, value); }
        public Vec2 AnimOffset { get => GetParam(PARAM_ANIM_OFFSET); set => SetParam(PARAM_ANIM_OFFSET, value); }
        public double AnimOffsetMin { get => GetParamMin(PARAM_ANIM_OFFSET); set => SetParamMin(PARAM_ANIM_OFFSET, value); }
        public double AnimOffsetMax { get => GetParamMax(PARAM_ANIM_OFFSET); set => SetParamMax(PARAM_ANIM_OFFSET, value); }
        public Texture2D AnimOffsetCurve { get => GetParamTexture(PARAM_ANIM_OFFSET); set => SetParamTexture(PARAM_ANIM_OFFSET, value); }
        public Vec2 TurbulenceInfluence { get => GetParam(PARAM_TURB_VEL_INFLUENCE); set => SetParam(PARAM_TURB_VEL_INFLUENCE, value); }
        public double TurbulenceInfluenceMin { get => GetParamMin(PARAM_TURB_VEL_INFLUENCE); set => SetParamMin(PARAM_TURB_VEL_INFLUENCE, value); }
        public double TurbulenceInfluenceMax { get => GetParamMax(PARAM_TURB_VEL_INFLUENCE); set => SetParamMax(PARAM_TURB_VEL_INFLUENCE, value); }
        public Vec2 TurbulenceInitialDisplacement { get => GetParam(PARAM_TURB_INIT_DISPLACEMENT); set => SetParam(PARAM_TURB_INIT_DISPLACEMENT, value); }
        public double TurbulenceInitialDisplacementMin { get => GetParamMin(PARAM_TURB_INIT_DISPLACEMENT); set => SetParamMin(PARAM_TURB_INIT_DISPLACEMENT, value); }
        public double TurbulenceInitialDisplacementMax { get => GetParamMax(PARAM_TURB_INIT_DISPLACEMENT); set => SetParamMax(PARAM_TURB_INIT_DISPLACEMENT, value); }
        public Texture2D TurbulenceInfluenceOverLife { get => GetParamTexture(PARAM_TURB_INFLUENCE_OVER_LIFE); set => SetParamTexture(PARAM_TURB_INFLUENCE_OVER_LIFE, value); }

        // ---------------------------------------------------------------- flags
        public bool ParticleFlagAlignY { get => GetParticleFlag(PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY); set => SetParticleFlag(PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY, value); }
        public bool ParticleFlagRotateY { get => GetParticleFlag(PARTICLE_FLAG_ROTATE_Y); set => SetParticleFlag(PARTICLE_FLAG_ROTATE_Y, value); }
        public bool ParticleFlagDisableZ { get => GetParticleFlag(PARTICLE_FLAG_DISABLE_Z); set => SetParticleFlag(PARTICLE_FLAG_DISABLE_Z, value); }
        public bool ParticleFlagDampingAsFriction { get => GetParticleFlag(PARTICLE_FLAG_DAMPING_AS_FRICTION); set => SetParticleFlag(PARTICLE_FLAG_DAMPING_AS_FRICTION, value); }
        public bool ParticleFlagInheritEmitterScale { get => GetParticleFlag(PARTICLE_FLAG_INHERIT_EMITTER_SCALE); set => SetParticleFlag(PARTICLE_FLAG_INHERIT_EMITTER_SCALE, value); }

        // ---------------------------------------------------------------- spawn
        public double LifetimeRandomness { get => _lifetimeRandomness; set { _lifetimeRandomness = value; C(); } }
        public Vec3 EmissionShapeOffset { get => _shapeOffset; set { _shapeOffset = value; C(); } }
        public Vec3 EmissionShapeScale { get => _shapeScale; set { _shapeScale = value; C(); } }
        public int EmissionShape
        {
            get => _emissionShape;
            set { if (value < 0 || value >= EMISSION_SHAPE_MAX) { Err("Index p_shape out of bounds."); return; } _emissionShape = value; C(); }
        }
        public double EmissionSphereRadius { get => _sphereRadius; set { _sphereRadius = (float)value; C(); } }
        public Vec3 EmissionBoxExtents { get => _boxExtents; set { _boxExtents = value; C(); } }
        public Texture2D EmissionPointTexture { get => _pointTexture; set { _pointTexture = value; C(); } }
        public Texture2D EmissionNormalTexture { get => _normalTexture; set { _normalTexture = value; C(); } }
        public Texture2D EmissionColorTexture { get => _colorTexture; set { _colorTexture = value; C(); } }
        public int EmissionPointCount { get => _pointCount; set { _pointCount = value; C(); } }
        public Vec3 EmissionRingAxis { get => _ringAxis; set { _ringAxis = value; C(); } }
        public double EmissionRingHeight { get => _ringHeight; set { _ringHeight = (float)value; C(); } }
        public double EmissionRingRadius { get => _ringRadius; set { _ringRadius = (float)value; C(); } }
        public double EmissionRingInnerRadius { get => _ringInnerRadius; set { _ringInnerRadius = (float)value; C(); } }
        public double EmissionRingConeAngle { get => _ringConeAngle; set { _ringConeAngle = (float)value; C(); } }

        static bool Gt(Vec3 a, Vec3 b) => a.x == b.x ? (a.y == b.y ? a.z > b.z : a.y > b.y) : a.x > b.x;
        static bool Lt(Vec3 a, Vec3 b) => a.x == b.x ? (a.y == b.y ? a.z < b.z : a.y < b.y) : a.x < b.x;

        public bool UseRotation3d { get => _useRotation3d; set { _useRotation3d = value; C(); } }
        public Vec3 Rotation3dMin { get => _rot3dMin; set { _rot3dMin = value; if (Gt(_rot3dMin, _rot3dMax)) Rotation3dMax = _rot3dMin; C(); } }
        public Vec3 Rotation3dMax { get => _rot3dMax; set { _rot3dMax = value; if (Lt(_rot3dMax, _rot3dMin)) Rotation3dMin = _rot3dMax; C(); } }
        public double InheritVelocityRatio { get => _inheritVelocityRatio; set { _inheritVelocityRatio = value; C(); } }
        public Vec3 VelocityPivot { get => _velocityPivot; set { _velocityPivot = value; C(); } }
        public Vec3 Direction { get => _direction; set { _direction = value; C(); } }
        public double Spread { get => _spread; set { _spread = (float)value; C(); } }
        public double Flatness { get => _flatness; set { _flatness = (float)value; C(); } }
        public Texture2D VelocityLimitCurve { get => _velocityLimitCurve; set { _velocityLimitCurve = value; C(); } }
        public bool UseRotationVelocity3d { get => _useRotVel3d; set { _useRotVel3d = value; C(); } }
        public Vec3 RotationVelocity3dMin { get => _rotVel3dMin; set { _rotVel3dMin = value; C(); } }
        public Vec3 RotationVelocity3dMax { get => _rotVel3dMax; set { _rotVel3dMax = value; C(); } }
        public Texture2D RotationVelocity3dCurve { get => _rotVel3dCurve; set { _rotVel3dCurve = value; C(); } }

        // ---------------------------------------------------------------- accelerations / display
        public Vec3 Gravity { get => _gravity; set { _gravity = value; C(); } }
        /// <summary>The gravity the shader gets (a zero gravity becomes (0, -0.000001, 0): it doubles as the up vector).</summary>
        public Vec3 GravityShaderValue => _gravity == new Vec3(0f, 0f, 0f) ? new Vec3(0.0, -0.000001, 0.0) : _gravity;
        public bool AttractorInteractionEnabled { get => _attractors; set { _attractors = value; C(); } }
        public bool UseScale3d { get => _useScale3d; set { _useScale3d = value; C(); } }
        public Vec3 Scale3dMin { get => _scale3dMin; set { _scale3dMin = value; if (Gt(_scale3dMin, _scale3dMax)) Scale3dMax = _scale3dMin; C(); } }
        public Vec3 Scale3dMax { get => _scale3dMax; set { _scale3dMax = value; if (Lt(_scale3dMax, _scale3dMin)) Scale3dMin = _scale3dMax; C(); } }
        public Col Color { get => _color; set { _color = value; C(); } }
        public Texture2D ColorRamp { get => _colorRamp; set { _colorRamp = value; C(); } }
        public Texture2D ColorInitialRamp { get => _colorInitialRamp; set { _colorInitialRamp = value; C(); } }
        public Texture2D AlphaCurve { get => _alphaCurve; set { _alphaCurve = value; C(); } }
        public Texture2D EmissionCurve { get => _emissionCurve; set { _emissionCurve = value; C(); } }

        // ---------------------------------------------------------------- turbulence / collision / sub emitter
        public bool TurbulenceEnabled { get => _turbulence; set { _turbulence = value; C(); } }
        public double TurbulenceNoiseStrength { get => _turbStrength; set { _turbStrength = (float)value; C(); } }
        public double TurbulenceNoiseScale { get => _turbScale; set { _turbScale = (float)value; C(); } }
        public Vec3 TurbulenceNoiseSpeed { get => _turbSpeed; set { _turbSpeed = value; C(); } }
        public double TurbulenceNoiseSpeedRandom { get => _turbSpeedRandom; set { _turbSpeedRandom = (float)value; C(); } }
        public int CollisionMode { get => _collisionMode; set { _collisionMode = value; C(); } }
        public double CollisionFriction { get => _collisionFriction; set { _collisionFriction = (float)value; C(); } }
        public double CollisionBounce { get => _collisionBounce; set { _collisionBounce = (float)value; C(); } }
        public bool CollisionUseScale { get => _collisionScale; set { _collisionScale = value; C(); } }
        public int SubEmitterMode { get => _subMode; set { _subMode = value; C(); } }
        public double SubEmitterFrequency { get => _subFrequency; set { _subFrequency = value; C(); } }
        public int SubEmitterAmountAtEnd { get => _subAtEnd; set { _subAtEnd = value; C(); } }
        public int SubEmitterAmountAtCollision { get => _subAtCollision; set { _subAtCollision = value; C(); } }
        public int SubEmitterAmountAtStart { get => _subAtStart; set { _subAtStart = value; C(); } }
        public bool SubEmitterKeepVelocity { get => _subKeepVelocity; set { _subKeepVelocity = value; C(); } }

        public override Resource Duplicate(bool deep = false)
        {
            var m = (ParticleProcessMaterial)MemberwiseCloneFresh();
            return m;
        }

        // (a copy with fresh "changed" listeners: built field by field through a new instance)
        ParticleProcessMaterial MemberwiseCloneFresh()
        {
            var m = new ParticleProcessMaterial();
            Array.Copy(_min, m._min, PARAM_MAX);
            Array.Copy(_max, m._max, PARAM_MAX);
            m._tex = (Texture2D[])_tex.Clone();
            m._flags = (bool[])_flags.Clone();
            m._direction = _direction; m._velocityPivot = _velocityPivot; m._boxExtents = _boxExtents; m._ringAxis = _ringAxis;
            m._shapeOffset = _shapeOffset; m._shapeScale = _shapeScale; m._turbSpeed = _turbSpeed; m._gravity = _gravity;
            m._scale3dMin = _scale3dMin; m._scale3dMax = _scale3dMax; m._rot3dMin = _rot3dMin; m._rot3dMax = _rot3dMax;
            m._rotVel3dMin = _rotVel3dMin; m._rotVel3dMax = _rotVel3dMax;
            m._spread = _spread; m._flatness = _flatness; m._sphereRadius = _sphereRadius; m._ringHeight = _ringHeight;
            m._ringRadius = _ringRadius; m._ringInnerRadius = _ringInnerRadius; m._ringConeAngle = _ringConeAngle;
            m._turbStrength = _turbStrength; m._turbScale = _turbScale; m._turbSpeedRandom = _turbSpeedRandom;
            m._collisionFriction = _collisionFriction; m._collisionBounce = _collisionBounce;
            m._lifetimeRandomness = _lifetimeRandomness; m._inheritVelocityRatio = _inheritVelocityRatio; m._subFrequency = _subFrequency;
            m._emissionShape = _emissionShape; m._pointCount = _pointCount; m._subMode = _subMode; m._subAtEnd = _subAtEnd;
            m._subAtCollision = _subAtCollision; m._subAtStart = _subAtStart; m._collisionMode = _collisionMode;
            m._turbulence = _turbulence; m._useScale3d = _useScale3d; m._useRotation3d = _useRotation3d; m._useRotVel3d = _useRotVel3d;
            m._subKeepVelocity = _subKeepVelocity; m._attractors = _attractors; m._collisionScale = _collisionScale;
            m._color = _color;
            m._colorRamp = _colorRamp; m._colorInitialRamp = _colorInitialRamp; m._alphaCurve = _alphaCurve; m._emissionCurve = _emissionCurve;
            m._velocityLimitCurve = _velocityLimitCurve; m._rotVel3dCurve = _rotVel3dCurve;
            m._pointTexture = _pointTexture; m._normalTexture = _normalTexture; m._colorTexture = _colorTexture;
            m.RenderPriority = RenderPriority;
            m.NextPass = NextPass;
            m.ResourceName = ResourceName;
            return m;
        }
    }
}

#endif
