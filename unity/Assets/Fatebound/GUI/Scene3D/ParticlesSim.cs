#if FB3D
// Godot's GPU particles run on the CPU: one ParticlesSim per GPUParticles3D, ported from
//  * servers/rendering/renderer_rd/storage_rd/particles_storage.cpp: update_particles() (restart requests, inactivity
//    after lifetime * 1.2 without emitting, pre-process, fixed_fps steps with the frame remainder, speed scale) and
//    _particles_process() (phase / cycle, one-shot ending its emission when the cycle wraps, frame parameters);
//  * shaders/particles.glsl main(): the restart phase with randomness and explosiveness, fractional delta, the
//    ACTIVE/STARTED flags and cycle numbers, then the material's start()/process();
//  * the shader ParticleProcessMaterial::_update_shader() writes (scene/resources/particle_process_material.cpp):
//    emission shapes, spread/flatness, velocities (initial, radial, orbit, directional), accelerations, damping,
//    turbulence, velocity limit, angle and angular velocity, scale (+ curves, 3D scale), rotation 3D, hue, animation,
//    colour / colour ramps / alpha and emission curves, disable_z / align_y / rotate_y flags, lifetime randomness and
//    amount ratio, with Godot's rand_from_seed and hash in uint32 arithmetic;
//  * shaders/particles_copy.glsl FILL_INSTANCES: draw order (INDEX, LIFETIME, REVERSE_LIFETIME; VIEW_DEPTH draws in
//    index order), transform align DISABLED / Y_TO_VELOCITY (the view-dependent billboard modes are left to the
//    material), interpolation by the frame remainder, inactive particles collapsed.
// Not simulated (the game uses none): trails, sub-emitters, attractors, collisions, emission point textures.
// Curves and gradients are read the way the shader reads their textures (linear filtering between texels, the
// texel values Godot bakes: CurveTexture floats, GradientTexture1D 8-bit). Shader math runs in float32 like the GPU,
// but sin/cos/pow come from the C library rather than the GPU's approximations, so values differ in the last bits.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public sealed class ParticlesSim
    {
        // ------------------------------------------------------------------ float vector math (GLSL semantics)
        struct V3
        {
            public float x, y, z;
            public V3(float x, float y, float z) { this.x = x; this.y = y; this.z = z; }
            public static V3 operator +(V3 a, V3 b) => new V3(a.x + b.x, a.y + b.y, a.z + b.z);
            public static V3 operator -(V3 a, V3 b) => new V3(a.x - b.x, a.y - b.y, a.z - b.z);
            public static V3 operator -(V3 a) => new V3(-a.x, -a.y, -a.z);
            public static V3 operator *(V3 a, float s) => new V3(a.x * s, a.y * s, a.z * s);
            public static V3 operator *(float s, V3 a) => new V3(a.x * s, a.y * s, a.z * s);
            public static V3 operator *(V3 a, V3 b) => new V3(a.x * b.x, a.y * b.y, a.z * b.z);
            public static V3 operator /(V3 a, float s) => new V3(a.x / s, a.y / s, a.z / s);
            public static bool operator ==(V3 a, V3 b) => a.x == b.x && a.y == b.y && a.z == b.z;
            public static bool operator !=(V3 a, V3 b) => !(a == b);
            public override bool Equals(object o) => o is V3 v && v == this;
            public override int GetHashCode() => x.GetHashCode() ^ y.GetHashCode() ^ z.GetHashCode();
            public static readonly V3 Zero = new V3(0f, 0f, 0f);
        }

        struct V4
        {
            public float x, y, z, w;
            public V4(float x, float y, float z, float w) { this.x = x; this.y = y; this.z = z; this.w = w; }
            public V4(V3 v, float w) { x = v.x; y = v.y; z = v.z; this.w = w; }
            public V3 Xyz { get => new V3(x, y, z); set { x = value.x; y = value.y; z = value.z; } }
            public static V4 operator +(V4 a, V4 b) => new V4(a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w);
            public static V4 operator -(V4 a, V4 b) => new V4(a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w);
            public static V4 operator *(V4 a, float s) => new V4(a.x * s, a.y * s, a.z * s, a.w * s);
            public static V4 operator *(V4 a, V4 b) => new V4(a.x * b.x, a.y * b.y, a.z * b.z, a.w * b.w);
        }

        /// <summary>GLSL mat4: four columns.</summary>
        struct M4
        {
            public V4 c0, c1, c2, c3;
            public static readonly M4 Identity = new M4 { c0 = new V4(1, 0, 0, 0), c1 = new V4(0, 1, 0, 0), c2 = new V4(0, 0, 1, 0), c3 = new V4(0, 0, 0, 1) };
            public V4 Mul(V4 v) => new V4(
                c0.x * v.x + c1.x * v.y + c2.x * v.z + c3.x * v.w,
                c0.y * v.x + c1.y * v.y + c2.y * v.z + c3.y * v.w,
                c0.z * v.x + c1.z * v.y + c2.z * v.z + c3.z * v.w,
                c0.w * v.x + c1.w * v.y + c2.w * v.z + c3.w * v.w);
            public static M4 operator *(M4 a, M4 b) => new M4 { c0 = a.Mul(b.c0), c1 = a.Mul(b.c1), c2 = a.Mul(b.c2), c3 = a.Mul(b.c3) };

            public static M4 From(Xform3 t)
            {
                Vec3 x = t.basis.GetColumn(0), y = t.basis.GetColumn(1), z = t.basis.GetColumn(2);
                return new M4 { c0 = new V4(x.x, x.y, x.z, 0), c1 = new V4(y.x, y.y, y.z, 0), c2 = new V4(z.x, z.y, z.z, 0), c3 = new V4(t.origin.x, t.origin.y, t.origin.z, 1) };
            }

            public Xform3 ToXform()
            {
                var b = Basis.IDENTITY;
                b.SetColumn(0, new Vec3(c0.x, c0.y, c0.z));
                b.SetColumn(1, new Vec3(c1.x, c1.y, c1.z));
                b.SetColumn(2, new Vec3(c2.x, c2.y, c2.z));
                return new Xform3(b, new Vec3(c3.x, c3.y, c3.z));
            }
        }

        static float Dot(V3 a, V3 b) => a.x * b.x + a.y * b.y + a.z * b.z;
        static float Dot(V4 a, V4 b) => a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
        static float Length(V3 a) => MathF.Sqrt(Dot(a, a));
        static float Length(V4 a) => MathF.Sqrt(Dot(a, a));
        static V3 Normalize(V3 a) => a / Length(a);
        static V4 Normalize(V4 a) { float l = Length(a); return new V4(a.x / l, a.y / l, a.z / l, a.w / l); }
        static V3 Cross(V3 a, V3 b) => new V3(a.y * b.z - b.y * a.z, a.z * b.x - b.z * a.x, a.x * b.y - b.x * a.y);
        static float Mix(float a, float b, float t) => a * (1.0f - t) + b * t;
        static V3 Mix(V3 a, V3 b, float t) => new V3(Mix(a.x, b.x, t), Mix(a.y, b.y, t), Mix(a.z, b.z, t));
        static V3 Mix(V3 a, V3 b, V3 t) => new V3(Mix(a.x, b.x, t.x), Mix(a.y, b.y, t.y), Mix(a.z, b.z, t.z));
        static V4 Mix(V4 a, V4 b, float t) => new V4(Mix(a.x, b.x, t), Mix(a.y, b.y, t), Mix(a.z, b.z, t), Mix(a.w, b.w, t));
        static float Clamp(float v, float lo, float hi) => MathF.Min(MathF.Max(v, lo), hi);
        static float Sign(float v) => v > 0 ? 1f : (v < 0 ? -1f : 0f);
        static float Fract(float v) => v - MathF.Floor(v);
        static V4 Fract(V4 v) => new V4(Fract(v.x), Fract(v.y), Fract(v.z), Fract(v.w));
        static V4 Floor(V4 v) => new V4(MathF.Floor(v.x), MathF.Floor(v.y), MathF.Floor(v.z), MathF.Floor(v.w));
        static V3 V(Vec3 v) => new V3(v.x, v.y, v.z);

        static V3 NormalizeOrElse(V3 v, V3 orElse) => v == V3.Zero ? orElse : Normalize(v);

        // ------------------------------------------------------------------ random (the generated shader's)
        static float RandFromSeed(ref uint seed)
        {
            int k;
            int s = unchecked((int)seed);
            if (s == 0) s = 305420679;
            k = s / 127773;
            s = unchecked(16807 * (s - k * 127773) - 2836 * k);
            if (s < 0) s = unchecked(s + 2147483647);
            seed = unchecked((uint)s);
            return (float)(seed % 65536u) / 65535.0f;
        }

        static float RandM1P1(ref uint seed) => RandFromSeed(ref seed) * 2.0f - 1.0f;

        static uint Hash(uint x)
        {
            unchecked
            {
                x = ((x >> 16) ^ x) * 73244475u;
                x = ((x >> 16) ^ x) * 73244475u;
                x = (x >> 16) ^ x;
                return x;
            }
        }

        // ------------------------------------------------------------------ texture reads
        sealed class TexEntry { public int version = int.MinValue; public V4[] texels; }
        static readonly System.Runtime.CompilerServices.ConditionalWeakTable<Texture2D, TexEntry> _texCache = new System.Runtime.CompilerServices.ConditionalWeakTable<Texture2D, TexEntry>();

        static V4[] Texels(Texture2D t)
        {
            switch (t)
            {
                case CurveTexture ct:
                {
                    float[] v = ct.GetValues();
                    var r = new V4[v.Length];
                    bool rgb = ct.TextureMode == CurveTexture.TEXTURE_MODE_RGB;
                    for (int i = 0; i < v.Length; i++) r[i] = rgb ? new V4(v[i], v[i], v[i], 1f) : new V4(v[i], 0f, 0f, 1f);
                    return r;
                }
                case CurveXYZTexture cx:
                {
                    float[] v = cx.GetValues();
                    int w = v.Length / 3;
                    var r = new V4[w];
                    for (int i = 0; i < w; i++) r[i] = new V4(v[i * 3], v[i * 3 + 1], v[i * 3 + 2], 1f);
                    return r;
                }
                case GradientTexture1D gt:
                {
                    int w = gt.Width;
                    var r = new V4[w];
                    for (int i = 0; i < w; i++)
                    {
                        Col c = gt.Gradient == null ? new Col(1f, 1f, 1f, 1f) : gt.Gradient.Sample((float)i / (w - 1));
                        r[i] = gt.UseHdr ? new V4(c.r, c.g, c.b, c.a) : new V4(B8(c.r), B8(c.g), B8(c.b), B8(c.a));
                    }
                    return r;
                }
                default:
                {
                    var img = t.GetImage();
                    if (img == null) return new[] { new V4(1f, 1f, 1f, 1f) };
                    var r = new V4[img.Width];
                    for (int i = 0; i < img.Width; i++) { Col c = img.GetPixel(i, 0); r[i] = new V4(c.r, c.g, c.b, c.a); }
                    return r;
                }
            }
        }

        // (Color::get_r8 / 255)
        static float B8(float c) { float v = MathF.Round(c * 255.0f, MidpointRounding.AwayFromZero); v = v < 0f ? 0f : (v > 255f ? 255f : v); return (int)v / 255.0f; }

        /// <summary>texture(tex, vec2(u)) on a one-row texture: linear filtering, clamped to the edge texels
        /// (repeat_disable) or wrapping (a sampler without hints: the particles shader default is repeat).</summary>
        static V4 Tex(Texture2D t, float u, bool repeat = false)
        {
            if (t == null) return new V4(1f, 1f, 1f, 1f);
            V4[] tx;
            TexEntry e = _texCache.GetOrCreateValue(t);
            lock (e)
            {
                if (e.texels == null || e.version != t.version)
                {
                    e.texels = Texels(t);
                    e.version = t.version;
                }
                tx = e.texels;
            }
            int w = tx.Length;
            float x = u * w - 0.5f;
            float fl = MathF.Floor(x);
            if (float.IsNaN(fl)) fl = 0f;
            int i0 = repeat ? (int)Math.Max(-1e9f, Math.Min(fl, 1e9f)) : (int)Math.Max(-1f, Math.Min(fl, w));
            float f = x - fl;
            int a, b;
            if (repeat)
            {
                a = (int)(((long)i0 % w + w) % w);
                b = (a + 1) % w;
            }
            else
            {
                a = i0 < 0 ? 0 : (i0 >= w ? w - 1 : i0);
                b = i0 + 1 < 0 ? 0 : (i0 + 1 >= w ? w - 1 : i0 + 1);
            }
            return tx[a] + (tx[b] - tx[a]) * f;
        }

        // ------------------------------------------------------------------ the material, read once per process step
        sealed class Mat
        {
            public bool ppm;
            public float[] min = new float[ParticleProcessMaterial.PARAM_MAX], max = new float[ParticleProcessMaterial.PARAM_MAX];
            public Texture2D[] tex = new Texture2D[ParticleProcessMaterial.PARAM_MAX];
            public bool disableZ, alignY, rotateY, dampingAsFriction, inheritEmitterScale;
            public bool useScale3d, useRotation3d, useRotVel3d, turbulence;
            public V3 direction, velocityPivot, boxExtents, ringAxis, shapeOffset, shapeScale, gravity, scale3dMin, scale3dMax,
                rotation3dMin, rotation3dMax, rotVel3dMin, rotVel3dMax, turbSpeed;
            public float spread, flatness, inheritVelocityRatio, sphereRadius, ringHeight, ringRadius, ringInner, ringCone,
                lifetimeRandomness, turbStrength, turbScale, turbSpeedRandom;
            public int shape;
            public V4 color;
            public Texture2D colorRamp, colorInitialRamp, alphaCurve, emissionCurve, velocityLimit, rotVel3dCurve;

            public Texture2D T(int p) => tex[p];
        }

        static float SrgbToLinear(float c) => c < 0.04045f ? c * (1.0f / 12.92f) : MathF.Pow((float)((c + 0.055) * (1.0 / (1.0 + 0.055))), 2.4f);

        static Mat ReadMaterial(GMaterial g)
        {
            var m = new Mat();
            if (!(g is ParticleProcessMaterial p)) return m;
            m.ppm = true;
            for (int i = 0; i < ParticleProcessMaterial.PARAM_MAX; i++) { m.min[i] = p.ParamsMin[i]; m.max[i] = p.ParamsMax[i]; m.tex[i] = p.ParamTextures[i]; }
            m.disableZ = p.ParticleFlagDisableZ;
            m.alignY = p.ParticleFlagAlignY;
            m.rotateY = p.ParticleFlagRotateY;
            m.dampingAsFriction = p.ParticleFlagDampingAsFriction;
            m.inheritEmitterScale = p.ParticleFlagInheritEmitterScale;
            m.useScale3d = p.UseScale3d;
            m.useRotation3d = !m.disableZ && p.UseRotation3d;
            m.useRotVel3d = p.UseRotationVelocity3d;
            m.turbulence = p.TurbulenceEnabled;
            m.direction = V(p.Direction);
            m.spread = (float)p.Spread;
            m.flatness = (float)p.Flatness;
            m.inheritVelocityRatio = (float)p.InheritVelocityRatio;
            m.velocityPivot = V(p.VelocityPivot);
            m.shape = p.EmissionShape;
            m.sphereRadius = (float)p.EmissionSphereRadius;
            m.boxExtents = V(p.EmissionBoxExtents);
            m.ringAxis = V(p.EmissionRingAxis);
            m.ringHeight = (float)p.EmissionRingHeight;
            m.ringRadius = (float)p.EmissionRingRadius;
            m.ringInner = (float)p.EmissionRingInnerRadius;
            m.ringCone = (float)p.EmissionRingConeAngle;
            m.shapeOffset = V(p.EmissionShapeOffset);
            m.shapeScale = V(p.EmissionShapeScale);
            m.gravity = V(p.GravityShaderValue);
            m.scale3dMin = V(p.Scale3dMin);
            m.scale3dMax = V(p.Scale3dMax);
            m.rotation3dMin = V(p.Rotation3dMin);
            m.rotation3dMax = V(p.Rotation3dMax);
            m.rotVel3dMin = V(p.RotationVelocity3dMin);
            m.rotVel3dMax = V(p.RotationVelocity3dMax);
            m.rotVel3dCurve = p.RotationVelocity3dCurve;
            m.lifetimeRandomness = (float)p.LifetimeRandomness;
            Col c = p.Color;
            m.color = new V4(SrgbToLinear(c.r), SrgbToLinear(c.g), SrgbToLinear(c.b), c.a);   // (source_color uniform)
            m.colorRamp = p.ColorRamp;
            m.colorInitialRamp = p.ColorInitialRamp;
            m.alphaCurve = p.AlphaCurve;
            m.emissionCurve = p.EmissionCurve;
            m.velocityLimit = p.VelocityLimitCurve;
            m.turbStrength = (float)p.TurbulenceNoiseStrength;
            m.turbScale = (float)p.TurbulenceNoiseScale;
            m.turbSpeedRandom = (float)p.TurbulenceNoiseSpeedRandom;
            m.turbSpeed = V(p.TurbulenceNoiseSpeed);
            return m;
        }

        // ------------------------------------------------------------------ particle buffer
        const uint FLAG_ACTIVE = 1, FLAG_STARTED = 2;

        struct Particle
        {
            public M4 xform;
            public V3 velocity;
            public uint flags;
            public V4 color, custom, userdata1;
        }

        struct Frame
        {
            public bool emitting;
            public float systemPhase, prevSystemPhase;
            public uint cycle;
            public float explosiveness, randomness, time, delta;
            public float amountRatio;
            public uint randomSeed;
            public M4 emissionTransform;
            public V3 emitterVelocity;
            public float interpToEnd;
        }

        readonly GPUParticles3D _node;
        Particle[] _p = Array.Empty<Particle>();
        int _amount = -1, _fixedFps = int.MinValue;
        bool _emitting, _inactive = true, _clear = true, _restartRequest;
        double _inactiveTime, _phase, _frameRemainder, _time;
        uint _cycle;
        int _seenRestart, _seenEmitRequests;
        Vec3 _prevPos;
        bool _havePrevPos;
        Vec3 _emitterVelocity;
        Mat _m;
        Frame _f;
        float _lifetime;

        /// <summary>Instances (== amount).</summary>
        public int Count;
        /// <summary>Per instance, in draw order: world space, or the node's local space when LocalCoords.</summary>
        public Xform3[] Transforms = Array.Empty<Xform3>();
        /// <summary>COLOR per instance (linear: color_value is a source_color uniform).</summary>
        public Col[] Colors = Array.Empty<Col>();
        /// <summary>INSTANCE_CUSTOM, 4 floats per instance: x angle (radians), y lifetime phase, z animation frame phase, w lifetime fraction.</summary>
        public float[] Custom = Array.Empty<float>();
        /// <summary>true: draw with the node's global transform; false: the transforms are already in world space.</summary>
        public bool LocalCoords;
        /// <summary>false when Godot skips the system (inactive and not emitting).</summary>
        public bool Active;

        Xform3 _emissionXf = Xform3.IDENTITY;
        bool _updated;

        /// <summary>Godot's capture_aabb() (particles_get_current_aabb): the box around every particle whose flags are
        /// non-zero -- live ones, and dead ones from cycle 1 on, which keep their last transform -- in the node's local
        /// space, grown by the longest axis of the draw passes' meshes. Empty before the first process step.</summary>
        public Aabb CaptureAabb()
        {
            if (!_updated) return new Aabb();   // (Godot: no particle buffer yet, an error and AABB())
            Xform3 inv = _emissionXf.AffineInverse();
            var aabb = new Aabb();
            bool first = true;
            for (int i = 0; i < _p.Length; i++)
            {
                if (_p[i].flags == 0) continue;
                var pos = new Vec3(_p[i].xform.c3.x, _p[i].xform.c3.y, _p[i].xform.c3.z);
                if (!_node.LocalCoords) pos = inv.Xform(pos);
                if (first) { aabb.position = pos; first = false; }
                else aabb = aabb.ExpandTo(pos);
            }
            float longest = 0;
            for (int i = 0; i < _node.DrawPasses; i++)
            {
                var mesh = _node.GetDrawPassMesh(i);
                if (mesh != null) longest = Math.Max(ServerMeshAabb(mesh).GetLongestAxisSize(), longest);
            }
            return aabb.Grow(longest);
        }

        /// <summary>mesh_get_aabb as the RenderingServer keeps it: the custom AABB when set, else the surfaces' boxes,
        /// each started at its first vertex with CMP_EPSILON size (RenderingServer::_surface_set_data).</summary>
        static Aabb ServerMeshAabb(Mesh m)
        {
            Aabb custom = m is PrimitiveMesh pm ? pm.CustomAabb : (m is ArrayMesh am ? am.CustomAabb : new Aabb());
            if (custom != new Aabb()) return custom;
            var small = new Vec3((float)GD.CMP_EPSILON, (float)GD.CMP_EPSILON, (float)GD.CMP_EPSILON);
            var aabb = new Aabb();
            var ss = m.GetSurfaces();
            for (int i = 0; i < ss.Count; i++)
            {
                var vs = ss[i].Vertices;
                if (vs == null || vs.Length == 0) continue;
                var sa = new Aabb(vs[0], small);
                for (int k = 1; k < vs.Length; k++) sa = sa.ExpandTo(vs[k]);
                aabb = i == 0 ? sa : aabb.Merge(sa);
            }
            return aabb;
        }

        public ParticlesSim(GPUParticles3D node)
        {
            _node = node;
            _seenRestart = node.RestartCounter;
            _seenEmitRequests = node.EmittingRequestCounter;
            _emitting = node.EmittingRequest;
        }

        void ResetBuffers(int amount)
        {
            _p = new Particle[amount];
            for (int i = 0; i < amount; i++) _p[i].xform = M4.Identity;
            Count = amount;
            Transforms = new Xform3[amount];
            Colors = new Col[amount];
            Custom = new float[amount * 4];
        }

        /// <summary>One rendered frame: Godot's update_particles() for this node, then the copy to instances.</summary>
        public void Update(double frameDelta)
        {
            var n = _node;
            // ---- the RenderingServer calls the node made since last frame
            if (n.Amount != _amount)
            {
                _amount = n.Amount;
                ResetBuffers(_amount);
                _phase = 0;
                _clear = true;
            }
            if (n.FixedFps != _fixedFps)
            {
                if (_fixedFps != int.MinValue) { ResetBuffers(_amount); _phase = 0; _clear = true; }
                _fixedFps = n.FixedFps;
            }
            if (n.RestartCounter != _seenRestart) { _seenRestart = n.RestartCounter; _restartRequest = true; }
            if (n.EmittingRequestCounter != _seenEmitRequests) { _seenEmitRequests = n.EmittingRequestCounter; _emitting = n.EmittingRequest; }
            LocalCoords = n.LocalCoords;

            Xform3 g = n.GlobalTransform;
            if (frameDelta > 0 && _havePrevPos)
            {
                Vec3 v = (g.origin - _prevPos) / frameDelta;
                _emitterVelocity = v;
            }
            _prevPos = g.origin;
            _emissionXf = g;
            _updated = true;
            _havePrevPos = true;
            _time += frameDelta;

            // ---- update_particles()
            if (_restartRequest)
            {
                _phase = 0;
                _clear = true;
                _restartRequest = false;
                _frameRemainder = 0.0;
            }

            if (_inactive && !_emitting) { Active = false; return; }
            if (_emitting)
            {
                if (_inactive)
                {
                    _phase = 0;
                    _clear = true;
                }
                _inactive = false;
                _inactiveTime = 0;
            }
            else
            {
                _inactiveTime += n.SpeedScale * frameDelta;
                if (_inactiveTime > n.Lifetime * 1.2)
                {
                    _inactive = true;
                    Active = false;
                    return;
                }
            }
            Active = true;

            int fixedFps = _fixedFps > 0 ? _fixedFps : 0;
            float todo = _clear ? (float)n.Preprocess : 0f;
            if (todo > 0.0)
            {
                float frameTime = fixedFps > 0 ? 1.0f / fixedFps : 1.0f / 30.0f;
                if (_clear)
                {
                    todo = (float)n.Preprocess;
                    while (todo > 0.0)
                    {
                        Process(frameTime > todo ? todo : frameTime, 1.0);
                        todo -= frameTime;
                    }
                }
            }

            float timeScale = (float)Math.Max(n.SpeedScale, 0.0);
            if (fixedFps > 0)
            {
                float frameTime = 1.0f / fixedFps;
                float delta = (float)frameDelta;
                if (delta > 0.1f) delta = 0.1f;
                else if (delta < 0.0f) delta = 0.0f;
                todo = (float)(_frameRemainder + delta * timeScale);
                while (todo >= frameTime || _clear)
                {
                    Process(frameTime, n.SpeedScale);
                    todo -= frameTime;
                }
                _frameRemainder = todo;
            }
            else Process(frameDelta * timeScale, n.SpeedScale);

            Copy();
        }

        // ------------------------------------------------------------------ _particles_process
        void Process(double delta, double speedScale)
        {
            var n = _node;
            double lifetime = n.Lifetime;
            double newPhase = (_phase + (delta / lifetime)) % 1.0;
            if (_clear) _cycle = 0;
            else if (newPhase < _phase)
            {
                if (n.OneShot) _emitting = false;
                _cycle++;
            }

            _f.emitting = _emitting;
            _f.systemPhase = (float)newPhase;
            _f.prevSystemPhase = (float)_phase;
            _phase = newPhase;
            _f.time = (float)_time;
            _f.delta = (float)delta;
            _f.randomSeed = unchecked((uint)n.Seed);
            _f.explosiveness = (float)n.Explosiveness;
            _f.randomness = (float)n.Randomness;
            _f.emissionTransform = n.LocalCoords ? M4.Identity : M4.From(n.GlobalTransform);
            _f.cycle = _cycle;
            _f.amountRatio = (float)n.AmountRatio;
            _f.emitterVelocity = V(_emitterVelocity);
            _f.interpToEnd = (float)n.InterpToEnd;
            _lifetime = (float)lifetime;
            _m = ReadMaterial(n.ProcessMaterial);

            bool clear = _clear;
            _clear = false;
            int total = _p.Length;
            for (int i = 0; i < total; i++) RunParticle(ref _p[i], (uint)i, (uint)total, clear, n.FractDelta);
        }

        // ------------------------------------------------------------------ particles.glsl main()
        bool restartPosition, restartRotScale, restartVelocity, restartColor, restartCustom;

        void RunParticle(ref Particle P, uint index, uint total, bool clear, bool fractionalDelta)
        {
            float localDelta = _f.delta;
            bool restart = false;
            restartPosition = restartRotScale = restartVelocity = restartColor = restartCustom = false;

            if (clear)
            {
                P.color = new V4(1f, 1f, 1f, 1f);
                P.custom = new V4(0f, 0f, 0f, 0f);
                P.velocity = V3.Zero;
                P.flags = 0;
                P.xform = M4.Identity;
            }
            P.flags &= ~FLAG_STARTED;

            if (!_m.ppm && (P.flags & FLAG_ACTIVE) != 0)
                P.xform.c3.Xyz = P.xform.c3.Xyz + P.velocity * localDelta;   // (no disable_velocity in the default shader)

            if (_f.emitting)
            {
                float restartPhase = (float)index / (float)total;
                if (_f.randomness > 0.0f)
                {
                    uint seed = _f.cycle;
                    if (restartPhase >= _f.systemPhase) seed = unchecked(seed - 1u);
                    seed = unchecked(seed * total);
                    seed = unchecked(seed + index);
                    float random = (float)(HashMain(seed) % 65536u) / 65536.0f;
                    restartPhase += _f.randomness * random * 1.0f / (float)total;
                }
                restartPhase *= (1.0f - _f.explosiveness);

                if (_f.systemPhase > _f.prevSystemPhase)
                {
                    if (restartPhase >= _f.prevSystemPhase && restartPhase < _f.systemPhase)
                    {
                        restart = true;
                        if (fractionalDelta) localDelta = (_f.systemPhase - restartPhase) * _lifetime;
                    }
                }
                else if (_f.delta > 0.0f)
                {
                    if (restartPhase >= _f.prevSystemPhase)
                    {
                        restart = true;
                        if (fractionalDelta) localDelta = (1.0f - restartPhase + _f.systemPhase) * _lifetime;
                    }
                    else if (restartPhase < _f.systemPhase)
                    {
                        restart = true;
                        if (fractionalDelta) localDelta = (_f.systemPhase - restartPhase) * _lifetime;
                    }
                }

                if (restart)
                {
                    P.flags = _f.emitting ? (FLAG_ACTIVE | FLAG_STARTED | unchecked(_f.cycle << 16)) : 0;
                    restartPosition = restartRotScale = restartVelocity = restartColor = restartCustom = true;
                }
            }

            bool active = (P.flags & FLAG_ACTIVE) != 0;
            uint number = unchecked((P.flags >> 16) * total + index);

            if (_m.ppm)
            {
                if (restart && active) Start(ref P, ref active, number, localDelta);
                if (active) ProcessParticle(ref P, ref active, number, localDelta);
            }
            else if (active) P.color = new V4(1f, 1f, 1f, 1f);

            P.flags &= ~FLAG_ACTIVE;
            if (active) P.flags |= FLAG_ACTIVE;
        }

        static uint HashMain(uint x)
        {
            unchecked
            {
                x = ((x >> 16) ^ x) * 0x45d9f3bu;
                x = ((x >> 16) ^ x) * 0x45d9f3bu;
                x = (x >> 16) ^ x;
                return x;
            }
        }

        // ------------------------------------------------------------------ the generated shader's helpers
        struct Display { public V3 scale; public float hueRotation, animationSpeed, animationOffset, lifetime; public V4 color; public float emissionTexturePosition; }
        struct Dynamics { public float angle, angularVelocity, initialVelocityMultiplier, directionalVelocity, radialVelocity, orbitVelocity; public V3 rotation3d; public float turbInfluence; public V3 rotationVelocity3d; }
        struct Physical { public float linearAccel, radialAccel, tangentAccel, damping; }

        const int PI_ = 0;
        const float PI = 3.14159f;

        void InitialPhysical(ref Physical p, ref uint seed)
        {
            var m = _m;
            p.linearAccel = Mix(m.min[ParticleProcessMaterial.PARAM_LINEAR_ACCEL], m.max[ParticleProcessMaterial.PARAM_LINEAR_ACCEL], RandFromSeed(ref seed));
            p.radialAccel = Mix(m.min[ParticleProcessMaterial.PARAM_RADIAL_ACCEL], m.max[ParticleProcessMaterial.PARAM_RADIAL_ACCEL], RandFromSeed(ref seed));
            p.tangentAccel = Mix(m.min[ParticleProcessMaterial.PARAM_TANGENTIAL_ACCEL], m.max[ParticleProcessMaterial.PARAM_TANGENTIAL_ACCEL], RandFromSeed(ref seed));
            p.damping = Mix(m.min[ParticleProcessMaterial.PARAM_DAMPING], m.max[ParticleProcessMaterial.PARAM_DAMPING], RandFromSeed(ref seed));
        }

        void InitialDynamics(ref Dynamics d, ref uint seed)
        {
            var m = _m;
            d.angle = Mix(m.min[ParticleProcessMaterial.PARAM_ANGLE], m.max[ParticleProcessMaterial.PARAM_ANGLE], RandFromSeed(ref seed));
            d.angularVelocity = Mix(m.min[ParticleProcessMaterial.PARAM_ANGULAR_VELOCITY], m.max[ParticleProcessMaterial.PARAM_ANGULAR_VELOCITY], RandFromSeed(ref seed));
            d.initialVelocityMultiplier = Mix(m.min[ParticleProcessMaterial.PARAM_INITIAL_LINEAR_VELOCITY], m.max[ParticleProcessMaterial.PARAM_INITIAL_LINEAR_VELOCITY], RandFromSeed(ref seed));
            d.directionalVelocity = Mix(m.min[ParticleProcessMaterial.PARAM_DIRECTIONAL_VELOCITY], m.max[ParticleProcessMaterial.PARAM_DIRECTIONAL_VELOCITY], RandFromSeed(ref seed));
            d.radialVelocity = Mix(m.min[ParticleProcessMaterial.PARAM_RADIAL_VELOCITY], m.max[ParticleProcessMaterial.PARAM_RADIAL_VELOCITY], RandFromSeed(ref seed));
            d.orbitVelocity = Mix(m.min[ParticleProcessMaterial.PARAM_ORBIT_VELOCITY], m.max[ParticleProcessMaterial.PARAM_ORBIT_VELOCITY], RandFromSeed(ref seed));
            if (m.turbulence)
                d.turbInfluence = Mix(m.min[ParticleProcessMaterial.PARAM_TURB_VEL_INFLUENCE], m.max[ParticleProcessMaterial.PARAM_TURB_VEL_INFLUENCE], RandFromSeed(ref seed));
            if (m.useRotation3d)
            {
                d.rotation3d.x = Mix(m.rotation3dMin.x, m.rotation3dMax.x, RandFromSeed(ref seed));
                d.rotation3d.y = Mix(m.rotation3dMin.y, m.rotation3dMax.y, RandFromSeed(ref seed));
                d.rotation3d.z = Mix(m.rotation3dMin.z, m.rotation3dMax.z, RandFromSeed(ref seed));
                d.rotation3d = d.rotation3d * (3.14159f / 180.0f);
            }
            if (m.useRotVel3d)
            {
                d.rotationVelocity3d.x = Mix(m.rotVel3dMin.x, m.rotVel3dMax.x, RandFromSeed(ref seed));
                d.rotationVelocity3d.y = Mix(m.rotVel3dMin.y, m.rotVel3dMax.y, RandFromSeed(ref seed));
                d.rotationVelocity3d.z = Mix(m.rotVel3dMin.z, m.rotVel3dMax.z, RandFromSeed(ref seed));
                d.rotationVelocity3d = d.rotationVelocity3d * (3.14159f / 180.0f);
            }
        }

        void InitialDisplay(ref Display p, ref uint seed)
        {
            var m = _m;
            float pi = 3.14159f;
            if (m.useScale3d) p.scale = Mix(m.scale3dMin, m.scale3dMax, RandFromSeed(ref seed));
            else { float s = Mix(m.min[ParticleProcessMaterial.PARAM_SCALE], m.max[ParticleProcessMaterial.PARAM_SCALE], RandFromSeed(ref seed)); p.scale = new V3(s, s, s); }
            p.scale = new V3(Sign(p.scale.x) * MathF.Max(MathF.Abs(p.scale.x), 0.001f), Sign(p.scale.y) * MathF.Max(MathF.Abs(p.scale.y), 0.001f), Sign(p.scale.z) * MathF.Max(MathF.Abs(p.scale.z), 0.001f));
            p.hueRotation = pi * 2.0f * Mix(m.min[ParticleProcessMaterial.PARAM_HUE_VARIATION], m.max[ParticleProcessMaterial.PARAM_HUE_VARIATION], RandFromSeed(ref seed));
            p.animationSpeed = Mix(m.min[ParticleProcessMaterial.PARAM_ANIM_SPEED], m.max[ParticleProcessMaterial.PARAM_ANIM_SPEED], RandFromSeed(ref seed));
            p.animationOffset = Mix(m.min[ParticleProcessMaterial.PARAM_ANIM_OFFSET], m.max[ParticleProcessMaterial.PARAM_ANIM_OFFSET], RandFromSeed(ref seed));
            p.lifetime = (1.0f - m.lifetimeRandomness * RandFromSeed(ref seed));
            p.color = m.color;
            if (m.colorInitialRamp != null) p.color = p.color * Tex(m.colorInitialRamp, RandFromSeed(ref seed));
            if (m.shape == ParticleProcessMaterial.EMISSION_SHAPE_POINTS || m.shape == ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS)
                p.emissionTexturePosition = RandFromSeed(ref seed);
        }

        static V4 RotateHue(V4 c, float angle)
        {
            float hc = MathF.Cos(angle), hs = MathF.Sin(angle);
            // columns of 0.299/0.587/0.114 base + cos * B + sin * C (the generated shader's matrices)
            V4 c0 = new V4(0.299f, 0.587f, 0.114f, 0.0f) + new V4(0.701f, -0.587f, -0.114f, 0.0f) * hc + new V4(0.168f, 0.330f, -0.497f, 0.0f) * hs;
            V4 c1 = new V4(0.299f, 0.587f, 0.114f, 0.0f) + new V4(-0.299f, 0.413f, -0.114f, 0.0f) * hc + new V4(-0.328f, 0.035f, 0.292f, 0.0f) * hs;
            V4 c2 = new V4(0.299f, 0.587f, 0.114f, 0.0f) + new V4(-0.300f, -0.588f, 0.886f, 0.0f) * hc + new V4(1.250f, -1.050f, -0.203f, 0.0f) * hs;
            V4 c3 = new V4(0.000f, 0.000f, 0.000f, 1.0f);
            var mtx = new M4 { c0 = c0, c1 = c1, c2 = c2, c3 = c3 };
            return mtx.Mul(c);
        }

        void ProcessDisplay(ref Display p, float lifetime)
        {
            var m = _m;
            if (m.T(ParticleProcessMaterial.PARAM_SCALE) != null) p.scale = p.scale * Tex(m.T(ParticleProcessMaterial.PARAM_SCALE), lifetime).Xyz;
            if (m.T(ParticleProcessMaterial.PARAM_HUE_VARIATION) != null) p.hueRotation *= Tex(m.T(ParticleProcessMaterial.PARAM_HUE_VARIATION), lifetime).x;
            if (m.T(ParticleProcessMaterial.PARAM_ANIM_OFFSET) != null) p.animationOffset += Tex(m.T(ParticleProcessMaterial.PARAM_ANIM_OFFSET), lifetime).x;
            if (m.T(ParticleProcessMaterial.PARAM_ANIM_SPEED) != null) p.animationSpeed *= Tex(m.T(ParticleProcessMaterial.PARAM_ANIM_SPEED), lifetime).x;
            if (m.colorRamp != null) p.color = p.color * Tex(m.colorRamp, lifetime);
            if (m.alphaCurve != null) p.color.w *= Tex(m.alphaCurve, lifetime).x;
            p.color = RotateHue(p.color, p.hueRotation);
            if (m.emissionCurve != null) p.color.Xyz = p.color.Xyz * (1.0f + Tex(m.emissionCurve, lifetime).x);
        }

        V3 InitialPosition(ref Display p, ref uint seed)
        {
            var m = _m;
            float pi = 3.14159f;
            V3 pos = V3.Zero;
            switch (m.shape)
            {
                case ParticleProcessMaterial.EMISSION_SHAPE_SPHERE:
                {
                    float s = RandFromSeed(ref seed) * 2.0f - 1.0f;
                    float t = RandFromSeed(ref seed) * 2.0f * pi;
                    float pr = RandFromSeed(ref seed);
                    float radius = m.sphereRadius * MathF.Sqrt(1.0f - s * s);
                    pos = Mix(V3.Zero, new V3(radius * MathF.Cos(t), radius * MathF.Sin(t), m.sphereRadius * s), pr);
                    break;
                }
                case ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE:
                {
                    float s = RandFromSeed(ref seed) * 2.0f - 1.0f;
                    float t = RandFromSeed(ref seed) * 2.0f * pi;
                    float radius = m.sphereRadius * MathF.Sqrt(1.0f - s * s);
                    pos = new V3(radius * MathF.Cos(t), radius * MathF.Sin(t), m.sphereRadius * s);
                    break;
                }
                case ParticleProcessMaterial.EMISSION_SHAPE_BOX:
                {
                    float a = RandFromSeed(ref seed) * 2.0f - 1.0f;
                    float b = RandFromSeed(ref seed) * 2.0f - 1.0f;
                    float c = RandFromSeed(ref seed) * 2.0f - 1.0f;
                    pos = new V3(a, b, c) * m.boxExtents;
                    break;
                }
                case ParticleProcessMaterial.EMISSION_SHAPE_POINTS:
                case ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS:
                    pos = V3.Zero;   // (emission point textures are not supported)
                    break;
                case ParticleProcessMaterial.EMISSION_SHAPE_RING:
                {
                    float radiusClamped = MathF.Max(0.001f, m.ringRadius);
                    float topRadius = MathF.Max(radiusClamped - MathF.Tan((90.0f - m.ringCone) * (PI_F / 180f)) * m.ringHeight, 0.0f);
                    float yPos = RandFromSeed(ref seed);
                    float skew = MathF.Max(MathF.Min(radiusClamped, topRadius) / MathF.Max(radiusClamped, topRadius), 0.5f);
                    yPos = radiusClamped < topRadius ? MathF.Pow(yPos, skew) : 1.0f - MathF.Pow(yPos, skew);
                    float ringSpawnAngle = RandFromSeed(ref seed) * 2.0f * pi;
                    float ringRandomRadius = MathF.Sqrt(RandFromSeed(ref seed) * (radiusClamped * radiusClamped - m.ringInner * m.ringInner) + m.ringInner * m.ringInner);
                    ringRandomRadius = Mix(ringRandomRadius, ringRandomRadius * (topRadius / radiusClamped), yPos);
                    V3 axis = m.ringAxis == V3.Zero ? new V3(0f, 0f, 1f) : Normalize(m.ringAxis);
                    V3 ortho;
                    if (new V3(MathF.Abs(axis.x), MathF.Abs(axis.y), MathF.Abs(axis.z)) == new V3(1f, 0f, 0f)) ortho = Cross(axis, new V3(0f, 1f, 0f));
                    else ortho = Cross(axis, new V3(1f, 0f, 0f));
                    ortho = Normalize(ortho);
                    float s = MathF.Sin(ringSpawnAngle);
                    float c = MathF.Cos(ringSpawnAngle);
                    float oc = 1.0f - c;
                    // mat3(col0, col1, col2) * ortho
                    V3 col0 = new V3(c + axis.x * axis.x * oc, axis.x * axis.y * oc - axis.z * s, axis.x * axis.z * oc + axis.y * s);
                    V3 col1 = new V3(axis.x * axis.y * oc + s * axis.z, c + axis.y * axis.y * oc, axis.y * axis.z * oc - axis.x * s);
                    V3 col2 = new V3(axis.z * axis.x * oc - axis.y * s, axis.z * axis.y * oc + axis.x * s, c + axis.z * axis.z * oc);
                    ortho = col0 * ortho.x + col1 * ortho.y + col2 * ortho.z;
                    ortho = Normalize(ortho);
                    pos = ortho * ringRandomRadius + axis * (yPos * m.ringHeight - m.ringHeight / 2.0f);
                    break;
                }
            }
            return pos * m.shapeScale + m.shapeOffset;
        }

        const float PI_F = 3.14159265358979f;

        V3 RandomDirectionFromSpread(ref uint seed, float spreadAngle)
        {
            var m = _m;
            float pi = 3.14159f;
            float degreeToRad = pi / 180.0f;
            float spreadRad = spreadAngle * degreeToRad;
            if (m.disableZ)
            {
                float a1 = RandM1P1(ref seed) * spreadRad;
                a1 += m.direction.x != 0.0f ? MathF.Atan2(m.direction.y, m.direction.x) : Sign(m.direction.y) * (pi / 2.0f);
                return new V3(MathF.Cos(a1), MathF.Sin(a1), 0.0f);
            }
            float angle1 = RandM1P1(ref seed) * spreadRad;
            float angle2 = RandM1P1(ref seed) * spreadRad * (1.0f - m.flatness);
            V3 dxz = new V3(MathF.Sin(angle1), 0.0f, MathF.Cos(angle1));
            V3 dyz = new V3(0.0f, MathF.Sin(angle2), MathF.Cos(angle2));
            dyz.z = dyz.z / MathF.Max(0.0001f, MathF.Sqrt(MathF.Abs(dyz.z)));
            V3 spreadDir = new V3(dxz.x * dyz.z, dyz.y, dxz.z * dyz.z);
            V3 dirNrm = Length(m.direction) > 0.0f ? Normalize(m.direction) : new V3(0f, 0f, 1f);
            V3 binormal = Cross(new V3(0f, 1f, 0f), dirNrm);
            if (Length(binormal) < 0.0001f) binormal = new V3(0f, 0f, 1f);
            binormal = Normalize(binormal);
            V3 normal = Cross(binormal, dirNrm);
            spreadDir = binormal * spreadDir.x + normal * spreadDir.y + dirNrm * spreadDir.z;
            return Normalize(spreadDir);
        }

        V3 OrbitDisplacement(ref Dynamics d, float lifetime, M4 transform, M4 emission, float delta)
        {
            var m = _m;
            if (MathF.Abs(d.orbitVelocity) < 0.01f || delta < 0.001f) return V3.Zero;
            V3 displacement = V3.Zero;
            float pi = 3.14159f;
            Texture2D ot = m.T(ParticleProcessMaterial.PARAM_ORBIT_VELOCITY);
            if (m.disableZ)
            {
                float orbitAmount = d.orbitVelocity;
                if (ot != null) orbitAmount *= ot is CurveTexture ? Tex(ot, lifetime).x : Tex(ot, lifetime).z;
                if (orbitAmount != 0.0f)
                {
                    V3 pos = transform.c3.Xyz;
                    V3 org = emission.c3.Xyz;
                    V3 diff = pos - org;
                    float ang = orbitAmount * pi * 2.0f * delta;
                    // mat2(vec2(cos, -sin), vec2(sin, cos)) * diff.xy
                    float rx = MathF.Cos(ang) * diff.x + MathF.Sin(ang) * diff.y;
                    float ry = -MathF.Sin(ang) * diff.x + MathF.Cos(ang) * diff.y;
                    displacement.x -= diff.x;
                    displacement.y -= diff.y;
                    displacement.x += rx;
                    displacement.y += ry;
                }
            }
            else
            {
                V3 ov = new V3(d.orbitVelocity, d.orbitVelocity, d.orbitVelocity);
                ov = ov * Tex(ot, lifetime).Xyz;
                ov = ov * (pi * 2.0f);
                ov = ov * delta;
                M4 inv = M4.From(emission.ToXform().AffineInverse());
                V3 local = inv.Mul(transform.c3).Xyz - m.velocityPivot;
                local.x = 0.0f;
                // mat3 columns (1,0,0), (0,cos,sin), (0,-sin,cos)
                V3 np = new V3(local.x, MathF.Cos(ov.x) * local.y - MathF.Sin(ov.x) * local.z, MathF.Sin(ov.x) * local.y + MathF.Cos(ov.x) * local.z);
                displacement = np - local;

                local = inv.Mul(transform.c3).Xyz - m.velocityPivot;
                local.y = 0.0f;
                // columns (cos,0,-sin), (0,1,0), (sin,0,cos)
                np = new V3(MathF.Cos(ov.y) * local.x + MathF.Sin(ov.y) * local.z, local.y, -MathF.Sin(ov.y) * local.x + MathF.Cos(ov.y) * local.z);
                displacement = displacement + (np - local);

                local = inv.Mul(transform.c3).Xyz - m.velocityPivot;
                local.z = 0.0f;
                // columns (cos,sin,0), (-sin,cos,0), (0,0,1)
                np = new V3(MathF.Cos(ov.z) * local.x - MathF.Sin(ov.z) * local.y, MathF.Sin(ov.z) * local.x + MathF.Cos(ov.z) * local.y, local.z);
                displacement = displacement + (np - local);
            }
            return emission.Mul(new V4(displacement / delta, 0.0f)).Xyz;
        }

        V3 RadialDisplacement(ref Dynamics d, float lifetime, ref uint seed, M4 transform, M4 emission, float delta)
        {
            var m = _m;
            V3 rd = V3.Zero;
            if (delta < 0.001f) return rd;
            float mult = 1.0f;
            if (m.T(ParticleProcessMaterial.PARAM_RADIAL_VELOCITY) != null) mult = Tex(m.T(ParticleProcessMaterial.PARAM_RADIAL_VELOCITY), lifetime).x;
            V3 globalPivot = emission.Mul(new V4(m.velocityPivot, 1.0f)).Xyz;
            if (Length(transform.c3.Xyz - globalPivot) > 0.01f) rd = Normalize(transform.c3.Xyz - globalPivot) * mult * d.radialVelocity;
            else rd = RandomDirectionFromSpread(ref seed, 360.0f) * d.radialVelocity;
            if (mult * d.radialVelocity < 0.0f)
                rd = Normalize(rd) * MathF.Min(MathF.Abs(mult * d.radialVelocity), Length(transform.c3.Xyz - globalPivot) / delta);
            return rd;
        }

        void ProcessPhysical(ref Physical p, float lp)
        {
            var m = _m;
            if (m.T(ParticleProcessMaterial.PARAM_LINEAR_ACCEL) != null) p.linearAccel *= Tex(m.T(ParticleProcessMaterial.PARAM_LINEAR_ACCEL), lp).x;
            if (m.T(ParticleProcessMaterial.PARAM_RADIAL_ACCEL) != null) p.radialAccel *= Tex(m.T(ParticleProcessMaterial.PARAM_RADIAL_ACCEL), lp).x;
            if (m.T(ParticleProcessMaterial.PARAM_TANGENTIAL_ACCEL) != null) p.tangentAccel *= Tex(m.T(ParticleProcessMaterial.PARAM_TANGENTIAL_ACCEL), lp).x;
            if (m.T(ParticleProcessMaterial.PARAM_DAMPING) != null) p.damping *= Tex(m.T(ParticleProcessMaterial.PARAM_DAMPING), lp).x;
        }

        // ---- turbulence (the generated shader's 4D noise and curl)
        static V4 Grad(V4 p)
        {
            p = Fract(new V4(
                Dot(p, new V4(0.143081f, 0.001724f, 0.280166f, 0.262771f)),
                Dot(p, new V4(0.645401f, -0.047791f, -0.146698f, 0.595016f)),
                Dot(p, new V4(-0.499665f, -0.095734f, 0.425674f, -0.207367f)),
                Dot(p, new V4(-0.013596f, -0.848588f, 0.423736f, 0.17044f))));
            V4 q = new V4(p.x * p.y, p.y * p.z, p.z * p.w, p.w * p.x) * 2365.952041f;
            return Fract(q) * 2.0f - new V4(1f, 1f, 1f, 1f);
        }

        static float Noise(V4 coord)
        {
            float d = Dot(coord, new V4(-0.1666667f, -0.1666667f, -0.1666667f, -0.5f));
            coord = new V4(coord.x + d, coord.y + d, coord.z + d, Dot(coord, new V4(0.5f, 0.5f, 0.5f, 0.5f)));
            V4 b = Floor(coord), delta = coord - b;
            float G(float x, float y, float z, float w) { V4 o = new V4(x, y, z, w); return Dot(delta - o, Grad(b + o)); }
            V4 r0123 = new V4(G(0, 0, 0, 0), G(1, 0, 0, 0), G(0, 1, 0, 0), G(1, 1, 0, 0));
            V4 r4567 = new V4(G(0, 0, 1, 0), G(1, 0, 1, 0), G(0, 1, 1, 0), G(1, 1, 1, 0));
            V4 r89AB = new V4(G(0, 0, 0, 1), G(1, 0, 0, 1), G(0, 1, 0, 1), G(1, 1, 0, 1));
            V4 rCDEF = new V4(G(0, 0, 1, 1), G(1, 0, 1, 1), G(0, 1, 1, 1), G(1, 1, 1, 1));
            V4 fade = delta * delta * delta * (new V4(10f, 10f, 10f, 10f) + delta * (new V4(-15f, -15f, -15f, -15f) + delta * 6.0f));
            V4 w0 = Mix(r0123, r89AB, fade.w), w1 = Mix(r4567, rCDEF, fade.w);
            V4 wz = Mix(w0, w1, fade.z);
            float wzyx = Mix(wz.x, wz.z, fade.y), wzyy = Mix(wz.y, wz.w, fade.y);
            return Mix(wzyx, wzyy, fade.x);
        }

        static V3 Noise3x(V4 p)
        {
            float s = Noise(p);
            float o = 1.7320508f * 2048.333333f;
            float s1 = Noise(p + new V4(0f, 0f, 0f, o));
            float s2 = Noise(p - new V4(0f, 0f, 0f, o));
            return new V3(s, s1, s2);
        }

        static V3 Curl3d(V4 p, float c)
        {
            float e = 0.001f + c;
            V4 dx = new V4(e, 0f, 0f, 0f), dy = new V4(0f, e, 0f, 0f), dz = new V4(0f, 0f, e, 0f);
            V3 x0 = Noise3x(p - dx), x1 = Noise3x(p + dx), y0 = Noise3x(p - dy), y1 = Noise3x(p + dy), z0 = Noise3x(p - dz), z1 = Noise3x(p + dz);
            float x = (y1.z - y0.z) - (z1.y - z0.y);
            float y = (z1.x - z0.x) - (x1.z - x0.z);
            float z = (x1.y - x0.y) - (y1.x - y0.x);
            return Normalize(new V3(x, y, z));
        }

        V3 NoiseDirection(V3 pos)
        {
            var m = _m;
            float adjContrast = MathF.Max(m.turbStrength - 1.0f, 0.0f) * 70.0f;
            V4 noiseTime = new V4(m.turbSpeed, m.turbSpeedRandom) * _f.time;
            V4 noisePos = new V4(pos * m.turbScale, 0.0f);
            V3 nd = Curl3d(noisePos + noiseTime, adjContrast);
            nd = Mix(nd * 0.9f, nd, m.turbStrength - 9.0f);
            return nd;
        }

        // ---- start()
        void Start(ref Particle P, ref bool active, uint number, float delta)
        {
            var m = _m;
            uint seed = Hash(unchecked(number + 1u + _f.randomSeed));
            var prm = new Display();
            InitialDisplay(ref prm, ref seed);
            var dyn = new Dynamics();
            InitialDynamics(ref dyn, ref seed);
            var phys = new Physical();
            InitialPhysical(ref phys, ref seed);
            ProcessDisplay(ref prm, 0.0f);
            if (RandFromSeed(ref seed) > _f.amountRatio) active = false;

            if (restartCustom)
            {
                P.custom = new V4(0f, 0f, 0f, 0f);
                P.custom.w = prm.lifetime;
                P.custom.x = dyn.angle;
                P.userdata1.w = 0.0f;
            }
            if (restartColor) P.color = prm.color;
            if (restartRotScale)
            {
                P.xform.c0.Xyz = new V3(1f, 0f, 0f);
                P.xform.c1.Xyz = new V3(0f, 1f, 0f);
                P.xform.c2.Xyz = new V3(0f, 0f, 1f);
            }
            ProcessDisplay(ref prm, 0.0f);

            if (m.useRotation3d && Dot(dyn.rotation3d, dyn.rotation3d) > 0.0f)
            {
                V3 r = dyn.rotation3d;
                var rx = new M4 { c0 = new V4(1f, 0f, 0f, 0f), c1 = new V4(0f, MathF.Cos(r.x), MathF.Sin(r.x), 0f), c2 = new V4(0f, -MathF.Sin(r.x), MathF.Cos(r.x), 0f), c3 = new V4(0f, 0f, 0f, 1f) };
                var ry = new M4 { c0 = new V4(MathF.Cos(r.y), 0f, -MathF.Sin(r.y), 0f), c1 = new V4(0f, 1f, 0f, 0f), c2 = new V4(MathF.Sin(r.y), 0f, MathF.Cos(r.y), 0f), c3 = new V4(0f, 0f, 0f, 1f) };
                var rz = new M4 { c0 = new V4(MathF.Cos(r.z), MathF.Sin(r.z), 0f, 0f), c1 = new V4(-MathF.Sin(r.z), MathF.Cos(r.z), 0f, 0f), c2 = new V4(0f, 0f, 1f, 0f), c3 = new V4(0f, 0f, 0f, 1f) };
                P.xform.c3.Xyz = V3.Zero;
                P.xform = rz * ry * rx * P.xform;
            }

            if (restartPosition)
            {
                P.xform.c3.Xyz = InitialPosition(ref prm, ref seed);
                if (m.turbulence)
                {
                    float initialTurb = Mix(m.min[ParticleProcessMaterial.PARAM_TURB_INIT_DISPLACEMENT], m.max[ParticleProcessMaterial.PARAM_TURB_INIT_DISPLACEMENT], RandFromSeed(ref seed));
                    V3 nd = NoiseDirection(P.xform.c3.Xyz);
                    P.xform.c3.Xyz = P.xform.c3.Xyz + nd * initialTurb;
                }
                P.xform = _f.emissionTransform * P.xform;
            }
            if (restartVelocity)
                P.userdata1.Xyz = RandomDirectionFromSpread(ref seed, m.spread) * dyn.initialVelocityMultiplier;
            else
                P.userdata1.Xyz = P.velocity;

            ProcessDisplay(ref prm, 0.0f);
            P.userdata1.Xyz = _f.emissionTransform.Mul(new V4(P.userdata1.Xyz, 0.0f)).Xyz;
            P.userdata1.Xyz = P.userdata1.Xyz + _f.emitterVelocity * m.inheritVelocityRatio;
            if (m.disableZ)
            {
                P.userdata1.z = 0.0f;
                P.xform.c3.z = 0.0f;
            }
        }

        // ---- process()
        void ProcessParticle(ref Particle P, ref bool active, uint number, float delta)
        {
            var m = _m;
            uint seed = Hash(unchecked(number + 1u + _f.randomSeed));
            var prm = new Display();
            InitialDisplay(ref prm, ref seed);
            var dyn = new Dynamics();
            InitialDynamics(ref dyn, ref seed);
            var phys = new Physical();
            InitialPhysical(ref phys, ref seed);

            float pi = 3.14159f;
            float degreeToRad = pi / 180.0f;

            bool firstFrame = P.custom.y == 0.0f;
            P.custom.y += delta / _lifetime;
            P.custom.y = Mix(P.custom.y, 1.0f, _f.interpToEnd);
            float lifetimePercent = P.custom.y / prm.lifetime;
            if (P.custom.y > P.custom.w) active = false;

            V3 controlled = V3.Zero;
            if (m.T(ParticleProcessMaterial.PARAM_ORBIT_VELOCITY) != null || m.disableZ)
                controlled = controlled + OrbitDisplacement(ref dyn, lifetimePercent, P.xform, _f.emissionTransform, delta);
            controlled = controlled + RadialDisplacement(ref dyn, lifetimePercent, ref seed, P.xform, _f.emissionTransform, delta);
            Texture2D dirTex = m.T(ParticleProcessMaterial.PARAM_DIRECTIONAL_VELOCITY);
            if (dirTex != null) controlled = controlled + Tex(dirTex, lifetimePercent).Xyz * dyn.directionalVelocity;

            ProcessPhysical(ref phys, lifetimePercent);
            V3 force;
            {
                V3 pos = P.xform.c3.Xyz;
                force = m.gravity;
                V3 u1 = P.userdata1.Xyz;
                force = force + (Length(u1) > 0.0f ? Normalize(u1) * phys.linearAccel : V3.Zero);
                V3 org = _f.emissionTransform.c3.Xyz;
                V3 diff = pos - org;
                force = force + (Length(diff) > 0.0f ? Normalize(diff) * phys.radialAccel : V3.Zero);
                float tangentAccel = phys.tangentAccel;
                if (m.disableZ)
                {
                    float lx = diff.y * -1.0f, ly = diff.x;
                    float l = MathF.Sqrt(diff.y * diff.y + diff.x * diff.x);
                    force = force + (l > 0.0f ? new V3(lx / MathF.Sqrt(lx * lx + ly * ly), ly / MathF.Sqrt(lx * lx + ly * ly), 0.0f) * tangentAccel : V3.Zero);
                }
                else
                {
                    V3 crossDiff = Cross(Normalize(diff), Normalize(m.gravity));
                    force = force + (Length(crossDiff) > 0.0f ? Normalize(crossDiff) * tangentAccel : V3.Zero);
                }
                if (m.disableZ) force.z = 0.0f;
                P.userdata1.Xyz = P.userdata1.Xyz + force * delta;
            }
            if (phys.damping > 0.0f)
            {
                float v = Length(P.userdata1.Xyz);
                if (!m.dampingAsFriction) v -= phys.damping * delta;
                else if (v > 0.001f)
                {
                    float damp = v * v * phys.damping * 0.05f * delta;
                    v -= damp;
                }
                if (v < 0.0f) P.userdata1.Xyz = V3.Zero;
                else P.userdata1.Xyz = Normalize(P.userdata1.Xyz) * v;
            }

            if (m.turbulence)
            {
                float turbulenceInfluence = 1.0f;
                Texture2D tl = m.T(ParticleProcessMaterial.PARAM_TURB_INFLUENCE_OVER_LIFE);
                if (tl != null) turbulenceInfluence = Tex(tl, lifetimePercent, true).x;
                V3 nd = NoiseDirection(P.xform.c3.Xyz);
                float velMag = Length(P.userdata1.Xyz);
                float velInfl = Clamp(dyn.turbInfluence * turbulenceInfluence, 0.0f, 1.0f) * (delta <= 0.0f ? 0.0f : 1.0f);
                P.userdata1.Xyz = Mix(P.userdata1.Xyz, Normalize(nd) * velMag * (1.0f + (1.0f - velInfl) * 0.2f), velInfl);
                velMag = Length(controlled);
                controlled = Mix(controlled, Normalize(nd) * velMag * (1.0f + (1.0f - velInfl) * 0.2f), velInfl);
            }
            V3 finalVelocity = controlled + P.userdata1.Xyz;

            if (m.velocityLimit != null && Length(finalVelocity) > 0.001f)
                finalVelocity = Normalize(finalVelocity) * MathF.Min(MathF.Abs(Length(finalVelocity)), MathF.Abs(Tex(m.velocityLimit, lifetimePercent).x));
            if (m.disableZ) finalVelocity.z = 0.0f;

            P.velocity = finalVelocity;
            P.xform.c3.Xyz = P.xform.c3.Xyz + finalVelocity * delta;

            ProcessDisplay(ref prm, lifetimePercent);

            float baseAngle = dyn.angle;
            if (m.T(ParticleProcessMaterial.PARAM_ANGLE) != null) baseAngle *= Tex(m.T(ParticleProcessMaterial.PARAM_ANGLE), lifetimePercent).x;
            if (m.T(ParticleProcessMaterial.PARAM_ANGULAR_VELOCITY) != null)
            {
                P.userdata1.w += Tex(m.T(ParticleProcessMaterial.PARAM_ANGULAR_VELOCITY), lifetimePercent).x * delta * dyn.angularVelocity;
                P.custom.x = baseAngle * degreeToRad + P.userdata1.w;
            }
            else
            {
                baseAngle += P.custom.y * _lifetime * dyn.angularVelocity;
                P.custom.x = baseAngle * degreeToRad;
            }
            P.color = prm.color;

            if (m.disableZ)
            {
                if (m.alignY)
                {
                    if (Length(finalVelocity) > 0.0f) P.xform.c1.Xyz = Normalize(finalVelocity);
                    else P.xform.c1.Xyz = Normalize(P.xform.c1.Xyz);
                    P.xform.c0.Xyz = Normalize(Cross(P.xform.c1.Xyz, P.xform.c2.Xyz));
                    P.xform.c2 = new V4(0f, 0f, 1f, 0f);
                }
                else
                {
                    P.xform.c0 = new V4(MathF.Cos(P.custom.x), -MathF.Sin(P.custom.x), 0f, 0f);
                    P.xform.c1 = new V4(MathF.Sin(P.custom.x), MathF.Cos(P.custom.x), 0f, 0f);
                    P.xform.c2 = new V4(0f, 0f, 1f, 0f);
                }
            }
            else
            {
                if (m.alignY)
                {
                    if (Length(finalVelocity) > 0.0f) P.xform.c1.Xyz = NormalizeOrElse(finalVelocity, new V3(0f, 1f, 0f));
                    else P.xform.c1.Xyz = NormalizeOrElse(P.xform.c1.Xyz, new V3(0f, 1f, 0f));
                    if (P.xform.c1.Xyz == NormalizeOrElse(P.xform.c0.Xyz, new V3(1f, 0f, 0f)))
                    {
                        P.xform.c0.Xyz = NormalizeOrElse(Cross(P.xform.c1.Xyz, P.xform.c2.Xyz), new V3(1f, 0f, 0f));
                        P.xform.c2.Xyz = NormalizeOrElse(Cross(P.xform.c0.Xyz, P.xform.c1.Xyz), new V3(0f, 0f, 1f));
                    }
                    else
                    {
                        P.xform.c2.Xyz = NormalizeOrElse(Cross(P.xform.c0.Xyz, P.xform.c1.Xyz), new V3(0f, 0f, 1f));
                        P.xform.c0.Xyz = NormalizeOrElse(Cross(P.xform.c1.Xyz, P.xform.c2.Xyz), new V3(1f, 0f, 0f));
                    }
                }
                else
                {
                    P.xform.c0.Xyz = NormalizeOrElse(P.xform.c0.Xyz, new V3(1f, 0f, 0f));
                    P.xform.c1.Xyz = NormalizeOrElse(P.xform.c1.Xyz, new V3(0f, 1f, 0f));
                    P.xform.c2.Xyz = NormalizeOrElse(P.xform.c2.Xyz, new V3(0f, 0f, 1f));
                }
                if (m.rotateY)
                {
                    V4 origin = P.xform.c3;
                    P.xform = new M4
                    {
                        c0 = new V4(MathF.Cos(P.custom.x), 0f, -MathF.Sin(P.custom.x), 0f),
                        c1 = new V4(0f, 1f, 0f, 0f),
                        c2 = new V4(MathF.Sin(P.custom.x), 0f, MathF.Cos(P.custom.x), 0f),
                        c3 = new V4(0f, 0f, 0f, 1f),
                    };
                    P.xform.c3 = origin;
                }
            }
            if (m.disableZ) P.xform.c3.z = 0.0f;

            Texture2D sov = m.T(ParticleProcessMaterial.PARAM_SCALE_OVER_VELOCITY);
            if (sov != null)
            {
                float smin = m.min[ParticleProcessMaterial.PARAM_SCALE_OVER_VELOCITY], smax = m.max[ParticleProcessMaterial.PARAM_SCALE_OVER_VELOCITY];
                if (Length(finalVelocity) > 0.001f) prm.scale = prm.scale * Tex(sov, Clamp(Length(finalVelocity) / (smax - smin), 0.0f, 1.0f)).Xyz;
                else prm.scale = prm.scale * Tex(sov, 0.0f).Xyz;
            }
            if (m.inheritEmitterScale)
            {
                var e = _f.emissionTransform;
                prm.scale = prm.scale * new V3(Length(e.c0.Xyz), Length(e.c1.Xyz), Length(e.c2.Xyz));
            }

            if (firstFrame)
            {
                float sx = prm.scale.x < 0.0f ? -1.0f : 1.0f, sy = prm.scale.y < 0.0f ? -1.0f : 1.0f, sz = prm.scale.z < 0.0f ? -1.0f : 1.0f;
                float smin = 0.001f;
                P.xform.c0.Xyz = P.xform.c0.Xyz * (sx * MathF.Max(MathF.Abs(prm.scale.x), smin));
                P.xform.c1.Xyz = P.xform.c1.Xyz * (sy * MathF.Max(MathF.Abs(prm.scale.y), smin));
                P.xform.c2.Xyz = P.xform.c2.Xyz * (sz * MathF.Max(MathF.Abs(prm.scale.z), smin));
            }
            else
            {
                float smin = 0.001f;
                P.xform.c0.Xyz = P.xform.c0.Xyz * MathF.Max(MathF.Abs(prm.scale.x), smin);
                P.xform.c1.Xyz = P.xform.c1.Xyz * MathF.Max(MathF.Abs(prm.scale.y), smin);
                P.xform.c2.Xyz = P.xform.c2.Xyz * MathF.Max(MathF.Abs(prm.scale.z), smin);
            }

            P.custom.z = prm.animationOffset + lifetimePercent * prm.animationSpeed;

            if (m.useRotVel3d && !m.disableZ)
            {
                if (m.rotVel3dCurve != null) dyn.rotationVelocity3d = dyn.rotationVelocity3d * Tex(m.rotVel3dCurve, lifetimePercent).Xyz;
                if (Length(dyn.rotationVelocity3d) > 0.0f)
                {
                    V3 r = dyn.rotationVelocity3d * delta;
                    V4 origin = P.xform.c3;
                    M4 Axis(V4 axis4, float ang)
                    {
                        V4 na = Normalize(axis4);
                        float ux = na.x, uy = na.y, uz = na.z;
                        float s = MathF.Sin(ang), c = MathF.Cos(ang), cm = 1.0f - c;
                        return new M4
                        {
                            c0 = new V4(ux * ux * cm + c, ux * uy * cm - uz * s, ux * uz * cm + uy * s, 0f),
                            c1 = new V4(ux * uy * cm + uz * s, uy * uy * cm + c, uy * uz * cm - ux * s, 0f),
                            c2 = new V4(ux * uz * cm - uy * s, uy * uz * cm + ux * s, uz * uz * cm + c, 0f),
                            c3 = new V4(0f, 0f, 0f, 1f),
                        };
                    }
                    M4 rx = Axis(P.xform.c0, r.x);
                    M4 ry = Axis(P.xform.c1, r.y);
                    M4 rz = Axis(P.xform.c2, r.z);
                    P.xform.c3.Xyz = V3.Zero;
                    P.xform = rz * ry * rx * P.xform;
                    P.xform.c3 = origin;
                }
            }

            if (P.custom.y > P.custom.w) active = false;
        }

        // ------------------------------------------------------------------ particles_copy.glsl FILL_INSTANCES
        void Copy()
        {
            var n = _node;
            int total = _p.Length;
            if (Transforms.Length != total) { Transforms = new Xform3[total]; Colors = new Col[total]; Custom = new float[total * 4]; }
            Count = total;
            if (total == 0) return;
            int order = n.DrawOrder;
            bool byLifetime = order == GPUParticles3D.DRAW_ORDER_LIFETIME || order == GPUParticles3D.DRAW_ORDER_REVERSE_LIFETIME;
            bool reverse = order == GPUParticles3D.DRAW_ORDER_REVERSE_LIFETIME;
            uint split = (uint)((Math.Min((int)(total * _phase), total - 1) + 1) % total);
            float remainder = n.Interpolate ? (float)_frameRemainder : 0.0f;
            int align = n.TransformAlign;
            int axis = n.TransformAlignAxis;

            for (int slot = 0; slot < total; slot++)
            {
                uint particle = (uint)slot;
                if (byLifetime)
                {
                    uint limit = (uint)total - split;
                    if (reverse) particle = (uint)total - particle - 1;
                    if (particle < limit) particle = split + particle;
                    else particle -= limit;
                }
                ref Particle P = ref _p[particle];
                M4 tx;
                if ((P.flags & FLAG_ACTIVE) != 0)
                {
                    tx = P.xform;
                    if (align == GPUParticles3D.TRANSFORM_ALIGN_Y_TO_VELOCITY)
                    {
                        V3 v = Normalize(P.velocity);
                        V3 len = new V3(Length(tx.c0.Xyz), Length(tx.c1.Xyz), Length(tx.c2.Xyz));
                        if (axis == 0)
                        {
                            tx.c0.Xyz = v;
                            tx.c1.Xyz = Normalize(Cross(tx.c2.Xyz / len.z, tx.c0.Xyz));
                            tx.c2.Xyz = Cross(tx.c0.Xyz, tx.c1.Xyz);
                        }
                        else if (axis == 2)
                        {
                            tx.c0.Xyz = Normalize(Cross(tx.c1.Xyz / len.y, v));
                            tx.c2.Xyz = v;
                            tx.c1.Xyz = Normalize(Cross(tx.c2.Xyz, tx.c0.Xyz));
                        }
                        else
                        {
                            tx.c0.Xyz = Normalize(Cross(v, tx.c2.Xyz / len.z));
                            tx.c1.Xyz = v;
                            tx.c2.Xyz = Cross(tx.c0.Xyz, tx.c1.Xyz);
                        }
                        tx.c0.Xyz = tx.c0.Xyz * len.x;
                        tx.c1.Xyz = tx.c1.Xyz * len.y;
                        tx.c2.Xyz = tx.c2.Xyz * len.z;
                    }
                    tx.c3.Xyz = tx.c3.Xyz + P.velocity * remainder;
                    Transforms[slot] = tx.ToXform();
                }
                else
                {
                    // (Godot: a zero basis and an origin at -INF, so nothing draws)
                    Transforms[slot] = new Xform3(new Basis(new Vec3(0f, 0f, 0f), new Vec3(0f, 0f, 0f), new Vec3(0f, 0f, 0f)), new Vec3(0f, 0f, 0f));
                }
                Colors[slot] = new Col(P.color.x, P.color.y, P.color.z, P.color.w);
                Custom[slot * 4] = P.custom.x;
                Custom[slot * 4 + 1] = P.custom.y;
                Custom[slot * 4 + 2] = P.custom.z;
                Custom[slot * 4 + 3] = P.custom.w;
            }
        }
    }
}

#endif
