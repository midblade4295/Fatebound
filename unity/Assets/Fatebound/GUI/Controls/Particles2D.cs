// Fatebound GUI (Unity port): CPUParticles2D for the menus' sparkles and embers, following cpu_particles_2d.cpp
// (restart phases with explosiveness/randomness, per-particle seeds, emission shapes, gravity, damping, tangential and
// radial acceleration, angular velocity, scale curves, colour ramps, hue variation, pre-process, one-shot).
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public class CPUParticles2D : Node2D
    {
        public enum EmissionShapeEnum { Point = 0, Sphere = 1, SphereSurface = 2, Rectangle = 3, Points = 4, DirectedPoints = 5, Ring = 6 }
        public const EmissionShapeEnum EMISSION_SHAPE_POINT = EmissionShapeEnum.Point, EMISSION_SHAPE_SPHERE = EmissionShapeEnum.Sphere,
            EMISSION_SHAPE_SPHERE_SURFACE = EmissionShapeEnum.SphereSurface, EMISSION_SHAPE_RECTANGLE = EmissionShapeEnum.Rectangle,
            EMISSION_SHAPE_POINTS = EmissionShapeEnum.Points, EMISSION_SHAPE_RING = EmissionShapeEnum.Ring;

        struct Particle
        {
            public Xform2 xform;
            public Col color;
            public Vec2 velocity;
            public bool active;
            public double rotation, time, lifetime;
            public float angleRand, scaleRand, hueRotRand, animOffsetRand;
            public Col startColorRand, baseColor;
            public float custom1, custom3;
            public uint seed;
        }

        Particle[] _particles = new Particle[8];
        bool _emitting = true, _active;
        double _time;
        uint _cycle;
        public double Lifetime = 1.0;
        public bool OneShot;
        public double Preprocess;
        public double SpeedScale = 1.0;
        public double Explosiveness;
        public double Randomness;
        public double LifetimeRandomness;
        public int FixedFps;
        public bool FractDelta = true;
        public bool LocalCoords;
        public Texture2D Texture;
        public Vec2 Direction = new Vec2(1, 0);
        public double Spread = 45;
        public Vec2 Gravity = new Vec2(0, 980);
        public double InitialVelocityMin, InitialVelocityMax;
        public double AngularVelocityMin, AngularVelocityMax;
        public double OrbitVelocityMin, OrbitVelocityMax;
        public double LinearAccelMin, LinearAccelMax;
        public double RadialAccelMin, RadialAccelMax;
        public double TangentialAccelMin, TangentialAccelMax;
        public double DampingMin, DampingMax;
        public double AngleMin, AngleMax;
        public double ScaleAmountMin = 1, ScaleAmountMax = 1;
        public double HueVariationMin, HueVariationMax;
        public Curve ScaleAmountCurve;
        public Curve AngularVelocityCurve, DampingCurve, HueVariationCurve, AngleCurve, OrbitVelocityCurve;
        public Col Color = Col.WHITE;
        public Gradient ColorRamp, ColorInitialRamp;
        public EmissionShapeEnum EmissionShape = EmissionShapeEnum.Point;
        public double EmissionSphereRadius = 1;
        public Vec2 EmissionRectExtents = new Vec2(1, 1);
        public double EmissionRingRadius = 1, EmissionRingInnerRadius;
        public Vec2[] EmissionPoints = new Vec2[0];
        public bool ParticleFlagAlignY;
        uint _seed;
        public bool UseFixedSeed;
        readonly Rng _rng = new Rng();
        public event Action Finished;

        public CPUParticles2D()
        {
            _seed = (uint)System.Environment.TickCount;
        }

        public int Amount
        {
            get => _particles.Length;
            set
            {
                if (value < 1) return;
                _particles = new Particle[value];
            }
        }

        public uint Seed { get => _seed; set { _seed = value; UseFixedSeed = true; } }

        public bool Emitting
        {
            get => _emitting;
            set
            {
                if (_emitting == value) return;
                if (value && !UseFixedSeed && OneShot) _seed = (uint)new Random().Next();
                _emitting = value;
                if (_emitting)
                {
                    _active = true;
                    if (_time == 0) UpdateInternal(0);
                }
            }
        }

        public void Restart(bool keepSeed = false)
        {
            _time = 0;
            _cycle = 0;
            for (int i = 0; i < _particles.Length; i++) _particles[i].active = false;
            if (!keepSeed && !UseFixedSeed) _seed = (uint)new Random().Next();
            _emitting = false;
            Emitting = true;
        }

        protected override void _Ready() => SetProcess(true);

        protected override void _Process(double delta) => UpdateInternal(delta);

        static uint IdHash(uint x)
        {
            x = ((x >> 16) ^ x) * 0x45d9f3b;
            x = ((x >> 16) ^ x) * 0x45d9f3b;
            x = (x >> 16) ^ x;
            return x;
        }

        static float RandFromSeed(ref uint seed)
        {
            int s = (int)seed;
            if (s == 0) s = 305420679;
            int k = s / 127773;
            s = 16807 * (s - k * 127773) - 2836 * k;
            if (s < 0) s += 2147483647;
            seed = (uint)s;
            return (seed % 65536u) / 65535.0f;
        }

        static double Lerp(double a, double b, double t) => a + (b - a) * t;

        void UpdateInternal(double delta)
        {
            if (!IsVisibleInTree()) return;
            if (!_active && !_emitting) { _time = 0; _cycle = 0; return; }
            if (_time == 0 && Preprocess > 0)
            {
                double frameTime = FixedFps > 0 ? 1.0 / FixedFps : 1.0 / 30.0;
                double todo = Preprocess;
                double ss = SpeedScale;
                SpeedScale = 1.0;
                while (todo > 0) { Process(Math.Min(frameTime, todo)); todo -= frameTime; }
                SpeedScale = ss;
            }
            if (delta > 0) Process(delta);
            QueueRedraw();
        }

        void Process(double delta)
        {
            delta *= SpeedScale;
            int pcount = _particles.Length;
            double prevTime = _time;
            _time += delta;
            if (_time > Lifetime)
            {
                _time %= Lifetime;
                _cycle++;
                if (OneShot && _cycle > 0)
                {
                    _emitting = false;
                    Finished?.Invoke();
                }
            }
            Xform2 emissionXf = Xform2.IDENTITY, velXf = Xform2.IDENTITY;
            if (!LocalCoords)
            {
                emissionXf = GetGlobalTransform();
                velXf = emissionXf;
                velXf.origin = Vec2.Zero;
            }
            double systemPhase = _time / Lifetime;
            bool any = false;
            for (int i = 0; i < pcount; i++)
            {
                ref Particle p = ref _particles[i];
                if (!_emitting && !p.active) continue;
                double localDelta = delta;
                double restartPhase = i / (double)pcount;
                if (Randomness > 0)
                {
                    uint s = _cycle;
                    if (restartPhase >= systemPhase) s -= 1;
                    s *= (uint)pcount;
                    s += (uint)i;
                    double r = (IdHash(s) % 65536u) / 65536.0;
                    restartPhase += Randomness * r * 1.0 / pcount;
                }
                restartPhase *= 1.0 - Explosiveness;
                double restartTime = restartPhase * Lifetime;
                bool restart = false;
                if (_time > prevTime)
                {
                    if (restartTime >= prevTime && restartTime < _time)
                    {
                        restart = true;
                        if (FractDelta) localDelta = _time - restartTime;
                    }
                }
                else if (localDelta > 0)
                {
                    if (restartTime >= prevTime)
                    {
                        restart = true;
                        if (FractDelta) localDelta = Lifetime - restartTime + _time;
                    }
                    else if (restartTime < _time)
                    {
                        restart = true;
                        if (FractDelta) localDelta = _time - restartTime;
                    }
                }
                if (p.time * (1.0 - Explosiveness) > p.lifetime) restart = true;
                float tv = 0f;
                if (restart)
                {
                    if (!_emitting) { p.active = false; continue; }
                    p.active = true;
                    p.seed = _seed + (uint)i + (uint)i + _cycle;
                    _rng.Seed = p.seed;
                    p.angleRand = (float)_rng.Randf();
                    p.scaleRand = (float)_rng.Randf();
                    p.hueRotRand = (float)_rng.Randf();
                    p.animOffsetRand = (float)_rng.Randf();
                    p.startColorRand = ColorInitialRamp != null ? ColorInitialRamp.Sample(_rng.Randf()) : Col.WHITE;
                    double a1 = Direction.Angle() + (_rng.Randf() * 2.0 - 1.0) * Spread * Math.PI / 180.0;
                    Vec2 rot = new Vec2(Math.Cos(a1), Math.Sin(a1));
                    p.velocity = rot * Lerp(InitialVelocityMin, InitialVelocityMax, _rng.Randf());
                    double baseAngle = Lerp(AngleMin, AngleMax, p.angleRand);
                    p.rotation = baseAngle * Math.PI / 180.0;
                    p.custom1 = 0;
                    p.custom3 = (float)(1.0 - _rng.Randf() * LifetimeRandomness);
                    p.xform = Xform2.IDENTITY;
                    p.time = 0;
                    p.lifetime = Lifetime * p.custom3;
                    p.baseColor = Col.WHITE;
                    switch (EmissionShape)
                    {
                        case EmissionShapeEnum.Sphere:
                        {
                            double t = Math.PI * 2 * _rng.Randf();
                            double rad = EmissionSphereRadius * _rng.Randf();
                            p.xform.origin = new Vec2(Math.Cos(t), Math.Sin(t)) * rad;
                            break;
                        }
                        case EmissionShapeEnum.SphereSurface:
                        {
                            double s = _rng.Randf(), t = Math.PI * 2 * _rng.Randf();
                            double rad = EmissionSphereRadius * Math.Sqrt(1.0 - s * s);
                            p.xform.origin = new Vec2(Math.Cos(t), Math.Sin(t)) * rad;
                            break;
                        }
                        case EmissionShapeEnum.Rectangle:
                            p.xform.origin = new Vec2(_rng.Randf() * 2.0 - 1.0, _rng.Randf() * 2.0 - 1.0) * EmissionRectExtents;
                            break;
                        case EmissionShapeEnum.Points:
                        case EmissionShapeEnum.DirectedPoints:
                            if (EmissionPoints.Length > 0) p.xform.origin = EmissionPoints[new Random().Next(EmissionPoints.Length)];
                            break;
                        case EmissionShapeEnum.Ring:
                        {
                            double t = Math.PI * 2 * _rng.Randf();
                            double o2 = EmissionRingRadius * EmissionRingRadius, i2 = EmissionRingInnerRadius * EmissionRingInnerRadius;
                            double rad = Math.Sqrt(_rng.Randf() * (o2 - i2) + i2);
                            p.xform.origin = new Vec2(Math.Cos(t), Math.Sin(t)) * rad;
                            break;
                        }
                    }
                    if (!LocalCoords)
                    {
                        p.velocity = velXf.Xform(p.velocity);
                        p.xform = emissionXf * p.xform;
                    }
                }
                else if (!p.active) continue;
                else if (p.time >= p.lifetime)
                {
                    p.active = false;
                    tv = 1f;
                }
                else
                {
                    uint s = p.seed;
                    p.time += localDelta;
                    p.custom1 = (float)(p.time / Lifetime);
                    tv = (float)(p.time / p.lifetime);
                    Vec2 force = Gravity;
                    Vec2 pos = p.xform.origin;
                    if (p.velocity.Length() > 0) force = force + p.velocity.Normalized() * Lerp(LinearAccelMin, LinearAccelMax, RandFromSeed(ref s));
                    Vec2 org = emissionXf.origin;
                    Vec2 diff = pos - org;
                    if (diff.Length() > 0) force = force + diff.Normalized() * Lerp(RadialAccelMin, RadialAccelMax, RandFromSeed(ref s));
                    Vec2 yx = new Vec2(diff.y, diff.x);
                    if (yx.Length() > 0) force = force + (yx * new Vec2(-1, 1)).Normalized() * Lerp(TangentialAccelMin, TangentialAccelMax, RandFromSeed(ref s));
                    p.velocity = p.velocity + force * localDelta;
                    double orbit = (OrbitVelocityCurve?.Sample(tv) ?? 1.0) * Lerp(OrbitVelocityMin, OrbitVelocityMax, RandFromSeed(ref s));
                    if (orbit != 0)
                    {
                        double ang = orbit * localDelta * Math.PI * 2;
                        var rx = new Xform2(-ang, Vec2.Zero);
                        p.xform.origin = p.xform.origin - diff + rx.BasisXform(diff);
                    }
                    double tdamp = DampingCurve?.Sample(tv) ?? 1.0;
                    if (DampingMax + tdamp > 0)
                    {
                        double v = p.velocity.Length();
                        double damp = tdamp * Lerp(DampingMin, DampingMax, RandFromSeed(ref s));
                        v -= damp * localDelta;
                        p.velocity = v < 0 ? Vec2.Zero : p.velocity.Normalized() * v;
                    }
                    double baseAngle = (AngleCurve?.Sample(tv) ?? 1.0) * Lerp(AngleMin, AngleMax, p.angleRand);
                    baseAngle += p.custom1 * Lifetime * (AngularVelocityCurve?.Sample(tv) ?? 1.0) * Lerp(AngularVelocityMin, AngularVelocityMax, RandFromSeed(ref s));
                    p.rotation = baseAngle * Math.PI / 180.0;
                }
                double texScale = ScaleAmountCurve != null ? ScaleAmountCurve.Sample(tv) : 1.0;
                double hueVar = HueVariationCurve?.Sample(tv) ?? 0.0;
                double hueAng = hueVar * Math.PI * 2 * Lerp(HueVariationMin, HueVariationMax, p.hueRotRand);
                Col c = ColorRamp != null ? ColorRamp.Sample(tv) * Color : Color;
                if (hueAng != 0)
                {
                    double hc = Math.Cos(hueAng), hs = Math.Sin(hueAng);
                    double[,] m = new double[3, 3];
                    double[] m1 = { 0.299, 0.587, 0.114, 0.299, 0.587, 0.114, 0.299, 0.587, 0.114 };
                    double[] m2 = { 0.701, -0.587, -0.114, -0.299, 0.413, -0.114, -0.300, -0.588, 0.886 };
                    double[] m3 = { 0.168, 0.330, -0.497, -0.328, 0.035, 0.292, 1.250, -1.050, -0.203 };
                    for (int r = 0; r < 3; r++) for (int k = 0; k < 3; k++) m[r, k] = m1[r * 3 + k] + m2[r * 3 + k] * hc + m3[r * 3 + k] * hs;
                    // xform_inv = transpose multiply
                    double nr = m[0, 0] * c.r + m[1, 0] * c.g + m[2, 0] * c.b;
                    double ng = m[0, 1] * c.r + m[1, 1] * c.g + m[2, 1] * c.b;
                    double nb = m[0, 2] * c.r + m[1, 2] * c.g + m[2, 2] * c.b;
                    c = new Col(nr, ng, nb, c.a);
                }
                p.color = c * p.baseColor * p.startColorRand;
                if (ParticleFlagAlignY)
                {
                    Vec2 y = p.velocity.Length() > 0 ? p.velocity.Normalized() : p.xform.y.Normalized();
                    p.xform.y = y;
                    p.xform.x = y.Orthogonal();
                }
                else
                {
                    p.xform.x = new Vec2(Math.Cos(p.rotation), -Math.Sin(p.rotation));
                    p.xform.y = new Vec2(Math.Sin(p.rotation), Math.Cos(p.rotation));
                }
                double bs = texScale * Lerp(ScaleAmountMin, ScaleAmountMax, p.scaleRand);
                if (bs < 0.00001) bs = 0.00001;
                p.xform.x = p.xform.x * bs;
                p.xform.y = p.xform.y * bs;
                p.xform.origin = p.xform.origin + p.velocity * localDelta;
                any = true;
            }
            if (!_emitting && !any) _active = false;
        }

        protected override void OnDraw()
        {
            Xform2 inv = LocalCoords ? Xform2.IDENTITY : GetGlobalTransform().AffineInverse();
            Vec2 ts = Texture?.GetSize() ?? new Vec2(1, 1);
            for (int i = 0; i < _particles.Length; i++)
            {
                var p = _particles[i];
                if (!p.active) continue;
                Xform2 xf = inv * p.xform;
                Vec2 h = ts * 0.5;
                var pts = new[] { xf.Xform(new Vec2(-h.x, -h.y)), xf.Xform(new Vec2(h.x, -h.y)), xf.Xform(new Vec2(h.x, h.y)), xf.Xform(new Vec2(-h.x, h.y)) };
                var cols = new[] { p.color, p.color, p.color, p.color };
                if (Texture != null)
                {
                    var t = Texture;
                    var uvs = new[] { t.MapUV(new Vec2(0, 0)), t.MapUV(new Vec2(1, 0)), t.MapUV(new Vec2(1, 1)), t.MapUV(new Vec2(0, 1)) };
                    drawList.AddPrimitive(pts, cols, uvs, t.BoundTexture());
                }
                else drawList.AddPrimitive(pts, cols);
            }
        }
    }
}
