// Fatebound GUI (Unity port): Godot's Tween -- steps of tweeners run one after another (parallel ones together), the
// left-over delta carried into the next step, property tweeners that read their start value when their step begins
// (after any delay), loops, binding to a node (paused while it is out of the tree, killed when it is freed), and the
// Robert Penner easing equations of easing_equations.h. Properties are addressed as in GDScript ("modulate:a").
using System;
using System.Collections.Generic;
using System.Reflection;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public enum TransitionType { Linear = 0, Sine = 1, Quint = 2, Quart = 3, Quad = 4, Expo = 5, Elastic = 6, Cubic = 7, Circ = 8, Bounce = 9, Back = 10, Spring = 11 }
    public enum EaseType { In = 0, Out = 1, InOut = 2, OutIn = 3 }

    public sealed class Tween
    {
        public const TransitionType TRANS_LINEAR = TransitionType.Linear, TRANS_SINE = TransitionType.Sine, TRANS_QUINT = TransitionType.Quint,
            TRANS_QUART = TransitionType.Quart, TRANS_QUAD = TransitionType.Quad, TRANS_EXPO = TransitionType.Expo, TRANS_ELASTIC = TransitionType.Elastic,
            TRANS_CUBIC = TransitionType.Cubic, TRANS_CIRC = TransitionType.Circ, TRANS_BOUNCE = TransitionType.Bounce, TRANS_BACK = TransitionType.Back,
            TRANS_SPRING = TransitionType.Spring;
        public const EaseType EASE_IN = EaseType.In, EASE_OUT = EaseType.Out, EASE_IN_OUT = EaseType.InOut, EASE_OUT_IN = EaseType.OutIn;
        public enum ProcessModeEnum { Physics = 0, Idle = 1 }
        public enum PauseModeEnum { Bound = 0, Stop = 1, Process = 2 }

        readonly List<List<Tweener>> _steps = new List<List<Tweener>>();
        int _current = -1;
        bool _parallel, _defaultParallel;
        int _loops = 1, _loopsDone;
        bool _running = true, _started, _dead, _valid = true;
        double _speed = 1.0;
        Node _bound;
        bool _isBound;
        internal TransitionType defaultTrans = TransitionType.Linear;
        internal EaseType defaultEase = EaseType.InOut;
        public PauseModeEnum PauseMode = PauseModeEnum.Bound;
        public bool IgnoreTimeScale;
        public event Action Finished;
        public event Action<int> StepFinished, LoopFinished;

        internal Tween(Node bound)
        {
            if (bound != null) { _bound = bound; _isBound = true; }
        }

        // ---------- building ----------
        void Append(Tweener t)
        {
            t.tween = this;
            if (_parallel) _current = Math.Max(_current, 0);
            else _current++;
            _parallel = _defaultParallel;
            while (_steps.Count < _current + 1) _steps.Add(new List<Tweener>());
            _steps[_current].Add(t);
        }

        public PropertyTweener TweenProperty(object target, string property, object finalVal, double duration)
        {
            var t = new PropertyTweener(target, property, finalVal, duration);
            Append(t);
            return t;
        }

        public IntervalTweener TweenInterval(double time)
        {
            var t = new IntervalTweener(time);
            Append(t);
            return t;
        }

        public CallbackTweener TweenCallback(Action callback)
        {
            var t = new CallbackTweener(callback);
            Append(t);
            return t;
        }

        public MethodTweener TweenMethod<T>(Action<T> method, T from, T to, double duration)
        {
            var t = new MethodTweener(v => method((T)Convert(v, typeof(T))), from, to, duration);
            Append(t);
            return t;
        }

        public Tween SetParallel(bool parallel = true) { _defaultParallel = parallel; _parallel = parallel; return this; }
        public Tween Parallel() { _parallel = true; return this; }
        public Tween Chain() { _parallel = false; return this; }
        public Tween SetLoops(int loops = 0) { _loops = loops; return this; }
        public Tween SetTrans(TransitionType t) { defaultTrans = t; return this; }
        public Tween SetEase(EaseType e) { defaultEase = e; return this; }
        public Tween SetSpeedScale(double s) { _speed = s; return this; }
        public Tween SetPauseMode(PauseModeEnum m) { PauseMode = m; return this; }
        public Tween SetProcessMode(ProcessModeEnum m) => this;
        public Tween SetIgnoreTimeScale(bool ignore = true) { IgnoreTimeScale = ignore; return this; }
        public Tween BindNode(Node n) { _bound = n; _isBound = n != null; return this; }

        public int GetLoopsLeft() => _loops <= 0 ? -1 : _loops - _loopsDone;
        public bool IsRunning() => _running;
        public bool IsValid() => _valid;
        public void Kill() { _running = false; _valid = false; _dead = true; }
        public void Stop() { _started = false; _running = false; _dead = false; _totalTime = 0; }
        public void Pause() => _running = false;
        public void Play() => _running = true;
        double _totalTime;
        public double GetTotalElapsedTime() => _totalTime;

        bool CanProcess(bool treePaused)
        {
            if (_isBound && PauseMode == PauseModeEnum.Bound)
            {
                if (Node.IsInstanceValid(_bound)) return _bound.IsInsideTree() && _bound.CanProcess();
            }
            return !treePaused || PauseMode == PauseModeEnum.Process;
        }

        void StartTweeners()
        {
            if (_steps.Count == 0) { _dead = true; _valid = false; return; }
            foreach (var t in _steps[_current]) t.Start();
        }

        /// <summary>The scene tree advances every tween once a frame; false = finished/dead.</summary>
        internal void Step(double scaledDelta, double rawDelta, bool treePaused)
        {
            if (!_valid) return;
            if (!CanProcess(treePaused)) { if (_isBound && !Node.IsInstanceValid(_bound)) Kill(); return; }
            if (!CustomStep(IgnoreTimeScale ? rawDelta : scaledDelta)) _valid = false;
        }

        public bool CustomStep(double delta)
        {
            if (_dead) return false;
            if (_isBound)
            {
                if (!Node.IsInstanceValid(_bound)) return false;
                if (!_bound.IsInsideTree()) return true;
            }
            if (!_running) return true;
            if (!_started)
            {
                if (_steps.Count == 0)
                {
                    GD_Log.Error("Tween started with no Tweeners.");
                    return false;
                }
                _current = 0;
                _loopsDone = 0;
                _totalTime = 0;
                StartTweeners();
                _started = true;
            }
            double rem = delta * _speed;
            _totalTime += rem;
            int guard = 0;
            while (_running && rem > 0)
            {
                double stepDelta = rem;
                bool active = false;
                foreach (var t in _steps[_current])
                {
                    double tmp = rem;
                    active = t.Step(ref tmp) || active;
                    stepDelta = Math.Min(tmp, stepDelta);
                }
                rem = stepDelta;
                if (!active)
                {
                    StepFinished?.Invoke(_current);
                    _current++;
                    if (_current == _steps.Count)
                    {
                        _loopsDone++;
                        if (_loopsDone == _loops)
                        {
                            _running = false;
                            _dead = true;
                            Finished?.Invoke();
                            break;
                        }
                        LoopFinished?.Invoke(_loopsDone);
                        _current = 0;
                        StartTweeners();
                        if (++guard > 1000) break;
                    }
                    else StartTweeners();
                }
                else break;
            }
            return true;
        }

        // ---------- interpolation ----------
        public static double RunEquation(TransitionType trans, EaseType ease, double t, double b, double c, double d)
        {
            if (d <= 0) return b + c;
            switch (trans)
            {
                case TransitionType.Linear: return c * t / d + b;
                case TransitionType.Sine: return Pick(ease, t, b, c, d, SineIn, SineOut, (tt, bb, cc, dd) => -cc / 2 * (Math.Cos(Math.PI * tt / dd) - 1) + bb);
                case TransitionType.Quint: return Pick(ease, t, b, c, d, (tt, bb, cc, dd) => cc * Math.Pow(tt / dd, 5) + bb, (tt, bb, cc, dd) => cc * (Math.Pow(tt / dd - 1, 5) + 1) + bb,
                    (tt, bb, cc, dd) => { tt = tt / dd * 2; return tt < 1 ? cc / 2 * Math.Pow(tt, 5) + bb : cc / 2 * (Math.Pow(tt - 2, 5) + 2) + bb; });
                case TransitionType.Quart: return Pick(ease, t, b, c, d, (tt, bb, cc, dd) => cc * Math.Pow(tt / dd, 4) + bb, (tt, bb, cc, dd) => -cc * (Math.Pow(tt / dd - 1, 4) - 1) + bb,
                    (tt, bb, cc, dd) => { tt = tt / dd * 2; return tt < 1 ? cc / 2 * Math.Pow(tt, 4) + bb : -cc / 2 * (Math.Pow(tt - 2, 4) - 2) + bb; });
                case TransitionType.Quad: return Pick(ease, t, b, c, d, (tt, bb, cc, dd) => cc * Math.Pow(tt / dd, 2) + bb, (tt, bb, cc, dd) => { tt /= dd; return -cc * tt * (tt - 2) + bb; },
                    (tt, bb, cc, dd) => { tt = tt / dd * 2; return tt < 1 ? cc / 2 * Math.Pow(tt, 2) + bb : -cc / 2 * ((tt - 1) * (tt - 3) - 1) + bb; });
                case TransitionType.Expo: return Pick(ease, t, b, c, d, ExpoIn, ExpoOut, (tt, bb, cc, dd) =>
                {
                    if (tt == 0) return bb;
                    if (tt == dd) return bb + cc;
                    tt = tt / dd * 2;
                    if (tt < 1) return cc / 2 * Math.Pow(2, 10 * (tt - 1)) + bb - cc * 0.0005;
                    return cc / 2 * 1.0005 * (-Math.Pow(2, -10 * (tt - 1)) + 2) + bb;
                });
                case TransitionType.Elastic: return Pick(ease, t, b, c, d, ElasticIn, ElasticOut, ElasticInOut);
                case TransitionType.Cubic: return Pick(ease, t, b, c, d, (tt, bb, cc, dd) => { tt /= dd; return cc * tt * tt * tt + bb; }, (tt, bb, cc, dd) => { tt = tt / dd - 1; return cc * (tt * tt * tt + 1) + bb; },
                    (tt, bb, cc, dd) => { tt /= dd / 2; if (tt < 1) return cc / 2 * tt * tt * tt + bb; tt -= 2; return cc / 2 * (tt * tt * tt + 2) + bb; });
                case TransitionType.Circ: return Pick(ease, t, b, c, d, (tt, bb, cc, dd) => { tt /= dd; return -cc * (Math.Sqrt(1 - tt * tt) - 1) + bb; }, (tt, bb, cc, dd) => { tt = tt / dd - 1; return cc * Math.Sqrt(1 - tt * tt) + bb; },
                    (tt, bb, cc, dd) => { tt /= dd / 2; if (tt < 1) return -cc / 2 * (Math.Sqrt(1 - tt * tt) - 1) + bb; tt -= 2; return cc / 2 * (Math.Sqrt(1 - tt * tt) + 1) + bb; });
                case TransitionType.Bounce: return PickInFirst(ease, t, b, c, d, BounceIn, BounceOut);
                case TransitionType.Back: return Pick(ease, t, b, c, d, BackIn, BackOut, (tt, bb, cc, dd) =>
                {
                    double s = 1.70158f * 1.525f;
                    tt /= dd / 2;
                    if (tt < 1) return cc / 2 * (tt * tt * ((s + 1) * tt - s)) + bb;
                    tt -= 2;
                    return cc / 2 * (tt * tt * ((s + 1) * tt + s) + 2) + bb;
                });
                case TransitionType.Spring: return PickInFirst(ease, t, b, c, d, SpringIn, SpringOut);
            }
            return c * t / d + b;
        }

        delegate double Eq(double t, double b, double c, double d);

        static double Pick(EaseType e, double t, double b, double c, double d, Eq inF, Eq outF, Eq inOut)
        {
            switch (e)
            {
                case EaseType.In: return inF(t, b, c, d);
                case EaseType.Out: return outF(t, b, c, d);
                case EaseType.InOut: return inOut(t, b, c, d);
                default:
                    if (t < d / 2) return outF(t * 2, b, c / 2, d);
                    return inF(t * 2 - d, b + c / 2, c / 2, d);
            }
        }

        static double PickInFirst(EaseType e, double t, double b, double c, double d, Eq inF, Eq outF)
        {
            switch (e)
            {
                case EaseType.In: return inF(t, b, c, d);
                case EaseType.Out: return outF(t, b, c, d);
                case EaseType.InOut:
                    if (t < d / 2) return inF(t * 2, b, c / 2, d);
                    return outF(t * 2 - d, b + c / 2, c / 2, d);
                default:
                    if (t < d / 2) return outF(t * 2, b, c / 2, d);
                    return inF(t * 2 - d, b + c / 2, c / 2, d);
            }
        }

        static double SineIn(double t, double b, double c, double d) => -c * Math.Cos(t / d * (Math.PI / 2)) + c + b;
        static double SineOut(double t, double b, double c, double d) => c * Math.Sin(t / d * (Math.PI / 2)) + b;
        static double ExpoIn(double t, double b, double c, double d) => t == 0 ? b : c * Math.Pow(2, 10 * (t / d - 1)) + b - c * 0.001;
        static double ExpoOut(double t, double b, double c, double d) => t == d ? b + c : c * 1.001 * (-Math.Pow(2, -10 * t / d) + 1) + b;

        static double ElasticIn(double t, double b, double c, double d)
        {
            if (t == 0) return b;
            t /= d;
            if (t == 1) return b + c;
            t -= 1;
            float p = (float)(d * 0.3f);
            float a = (float)(c * Math.Pow(2, 10 * t));
            float s = p / 4;
            return -(a * Math.Sin((t * d - s) * (2 * Math.PI) / p)) + b;
        }

        static double ElasticOut(double t, double b, double c, double d)
        {
            if (t == 0) return b;
            t /= d;
            if (t == 1) return b + c;
            float p = (float)(d * 0.3f);
            float s = p / 4;
            return c * Math.Pow(2, -10 * t) * Math.Sin((t * d - s) * (2 * Math.PI) / p) + c + b;
        }

        static double ElasticInOut(double t, double b, double c, double d)
        {
            if (t == 0) return b;
            if ((t /= d / 2) == 2) return b + c;
            float p = (float)(d * (0.3f * 1.5f));
            double a = c;
            float s = p / 4;
            if (t < 1)
            {
                t -= 1;
                a *= Math.Pow(2, 10 * t);
                return -0.5f * (a * Math.Sin((t * d - s) * (2 * Math.PI) / p)) + b;
            }
            t -= 1;
            a *= Math.Pow(2, -10 * t);
            return a * Math.Sin((t * d - s) * (2 * Math.PI) / p) * 0.5f + c + b;
        }

        static double BounceOut(double t, double b, double c, double d)
        {
            t /= d;
            if (t < (1 / 2.75f)) return c * (7.5625f * t * t) + b;
            if (t < (2 / 2.75f)) { t -= 1.5f / 2.75f; return c * (7.5625f * t * t + 0.75f) + b; }
            if (t < (2.5 / 2.75)) { t -= 2.25f / 2.75f; return c * (7.5625f * t * t + 0.9375f) + b; }
            t -= 2.625f / 2.75f;
            return c * (7.5625f * t * t + 0.984375f) + b;
        }

        static double BounceIn(double t, double b, double c, double d) => c - BounceOut(d - t, 0, c, d) + b;

        static double BackIn(double t, double b, double c, double d)
        {
            float s = 1.70158f;
            t /= d;
            return c * t * t * ((s + 1) * t - s) + b;
        }

        static double BackOut(double t, double b, double c, double d)
        {
            float s = 1.70158f;
            t = t / d - 1;
            return c * (t * t * ((s + 1) * t + s) + 1) + b;
        }

        static double SpringOut(double t, double b, double c, double d)
        {
            t /= d;
            double s = 1.0 - t;
            t = (Math.Sin(t * Math.PI * (0.2 + 2.5 * t * t * t)) * Math.Pow(s, 2.2) + t) * (1.0 + (1.2 * s));
            return c * t + b;
        }

        static double SpringIn(double t, double b, double c, double d) => c - SpringOut(d - t, 0, c, d) + b;

        /// <summary>Tween.interpolate_value.</summary>
        public static object InterpolateValue(object initial, object delta, double time, double duration, TransitionType trans, EaseType ease)
        {
            double k = RunEquation(trans, ease, time, 0.0, 1.0, duration);
            return Lerp(initial, Add(initial, delta), k);
        }

        // ---------- values ----------
        internal static object Add(object a, object b)
        {
            switch (a)
            {
                case double d: return d + ToD(b);
                case float f: return (float)(f + ToD(b));
                case int i: return (int)(i + ToD(b));
                case long l: return (long)(l + ToD(b));
                case Vec2 v: return v + (Vec2)b;
                case Vec3 v3: return v3 + (Vec3)b;
                case Col c: return c + (Col)b;
                case Rect2 r: { var o = (Rect2)b; return new Rect2(r.position + o.position, r.size + o.size); }
            }
            return b;
        }

        internal static object Sub(object a, object b)
        {
            switch (a)
            {
                case double d: return d - ToD(b);
                case float f: return (float)(f - ToD(b));
                case int i: return (int)(i - ToD(b));
                case long l: return (long)(l - ToD(b));
                case Vec2 v: return v - (Vec2)b;
                case Vec3 v3: return v3 - (Vec3)b;
                case Col c: return c - (Col)b;
                case Rect2 r: { var o = (Rect2)b; return new Rect2(r.position - o.position, r.size - o.size); }
            }
            return a;
        }

        internal static object Lerp(object a, object b, double t)
        {
            switch (a)
            {
                case double d: return d + (ToD(b) - d) * t;
                case float f: return (float)(f + (ToD(b) - f) * t);
                case int i: return (int)Math.Round(i + (ToD(b) - i) * t);
                case long l: return (long)Math.Round(l + (ToD(b) - l) * t);
                case Vec2 v: return v.Lerp((Vec2)b, t);
                case Vec3 v3: { var o = (Vec3)b; return new Vec3(v3.x + (o.x - v3.x) * t, v3.y + (o.y - v3.y) * t, v3.z + (o.z - v3.z) * t); }
                case Col c: return c.Lerp((Col)b, t);
                case Rect2 r: { var o = (Rect2)b; return new Rect2(r.position.Lerp(o.position, t), r.size.Lerp(o.size, t)); }
                case bool bo: return t >= 0.5 ? b : a;
            }
            return t >= 1 ? b : a;
        }

        static double ToD(object o) => o is double d ? d : o is float f ? f : o is int i ? i : o is long l ? l : System.Convert.ToDouble(o);

        internal static object Convert(object v, Type t)
        {
            if (v == null) return null;
            if (t.IsInstanceOfType(v)) return v;
            if (t.IsEnum) return Enum.ToObject(t, System.Convert.ToInt64(v));
            if (t == typeof(bool)) return System.Convert.ToBoolean(v);
            if (Nullable.GetUnderlyingType(t) is Type nt) return Convert(v, nt);
            if (t == typeof(double)) return ToD(v);
            if (t == typeof(float)) return (float)ToD(v);
            if (t == typeof(int)) return (int)Math.Round(ToD(v));
            if (t == typeof(long)) return (long)Math.Round(ToD(v));
            return v;
        }
    }

    public abstract class Tweener
    {
        internal Tween tween;
        protected double elapsed;
        protected bool finished;
        public event Action Finished;
        internal virtual void Start() { elapsed = 0; finished = false; }
        internal abstract bool Step(ref double delta);
        protected void Finish() { finished = true; Finished?.Invoke(); }
    }

    public sealed class PropertyTweener : Tweener
    {
        readonly object _target;
        readonly string _path;
        object _initial, _final, _delta, _baseFinal;
        readonly double _duration;
        double _delay;
        bool _continue = true, _continueDelayed, _relative;
        TransitionType? _trans;
        EaseType? _ease;
        Func<double, double> _custom;

        internal PropertyTweener(object target, string path, object finalVal, double duration)
        {
            _target = target;
            _path = path;
            _duration = duration;
            _baseFinal = finalVal;
            _final = finalVal;
        }

        public PropertyTweener From(object v)
        {
            _initial = PropertyPath.Coerce(v, PropertyPath.Get(_target, _path));
            _final = PropertyPath.Coerce(_final, _initial);
            _continue = false;
            return this;
        }

        public PropertyTweener FromCurrent() { _continue = false; _initial = PropertyPath.Get(_target, _path); return this; }
        public PropertyTweener AsRelative() { _relative = true; return this; }
        public PropertyTweener SetTrans(TransitionType t) { _trans = t; return this; }
        public PropertyTweener SetEase(EaseType e) { _ease = e; return this; }
        public PropertyTweener SetDelay(double d) { _delay = d; return this; }
        public PropertyTweener SetCustomInterpolator(Func<double, double> f) { _custom = f; return this; }

        bool TargetAlive => !(_target is Node n) || Node.IsInstanceValid(n);

        internal override void Start()
        {
            base.Start();
            if (!TargetAlive) return;
            if (_continue)
            {
                if (Math.Abs(_delay) < 1e-5) _initial = PropertyPath.Get(_target, _path);
                else _continueDelayed = true;
            }
            if (_initial != null) _final = PropertyPath.Coerce(_baseFinal, _initial);
            if (_relative && _initial != null) _final = Tween.Add(_initial, PropertyPath.Coerce(_baseFinal, _initial));
            if (_initial != null) _delta = Tween.Sub(_final, _initial);
        }

        internal override bool Step(ref double delta)
        {
            if (finished) return false;
            if (!TargetAlive) { Finish(); return false; }
            elapsed += delta;
            if (elapsed < _delay) { delta = 0; return true; }
            if (_continueDelayed && Math.Abs(_delay) >= 1e-5)
            {
                _initial = PropertyPath.Get(_target, _path);
                _final = PropertyPath.Coerce(_relative ? Tween.Add(_initial, PropertyPath.Coerce(_baseFinal, _initial)) : _baseFinal, _initial);
                _delta = Tween.Sub(_final, _initial);
                _continueDelayed = false;
            }
            var trans = _trans ?? tween.defaultTrans;
            var ease = _ease ?? tween.defaultEase;
            double time = Math.Min(elapsed - _delay, _duration);
            if (time < _duration)
            {
                if (_custom != null)
                {
                    double t = Tween.RunEquation(trans, ease, time, 0, 1, _duration);
                    PropertyPath.Set(_target, _path, Tween.Lerp(_initial, _final, _custom(t)));
                }
                else PropertyPath.Set(_target, _path, Tween.InterpolateValue(_initial, _delta, time, _duration, trans, ease));
                delta = 0;
                return true;
            }
            PropertyPath.Set(_target, _path, _custom != null ? Tween.Lerp(_initial, _final, _custom(1.0)) : _final);
            delta = elapsed - _delay - _duration;
            Finish();
            return false;
        }
    }

    public sealed class IntervalTweener : Tweener
    {
        readonly double _duration;
        internal IntervalTweener(double d) { _duration = d; }

        internal override bool Step(ref double delta)
        {
            if (finished) return false;
            elapsed += delta;
            if (elapsed < _duration) { delta = 0; return true; }
            delta = elapsed - _duration;
            Finish();
            return false;
        }
    }

    public sealed class CallbackTweener : Tweener
    {
        readonly Action _cb;
        double _delay;
        internal CallbackTweener(Action cb) { _cb = cb; }
        public CallbackTweener SetDelay(double d) { _delay = d; return this; }

        internal override bool Step(ref double delta)
        {
            if (finished) return false;
            if (_cb == null) { Finish(); return false; }
            elapsed += delta;
            if (elapsed >= _delay)
            {
                try { _cb(); }
                catch (Exception ex) { GD_Log.Error("tween callback: " + ex); }
                delta = elapsed - _delay;
                Finish();
                return false;
            }
            delta = 0;
            return true;
        }
    }

    public sealed class MethodTweener : Tweener
    {
        readonly Action<object> _cb;
        readonly object _from, _to;
        readonly object _deltaV;
        readonly double _duration;
        double _delay;
        TransitionType? _trans;
        EaseType? _ease;

        internal MethodTweener(Action<object> cb, object from, object to, double duration)
        {
            _cb = cb;
            _from = from;
            _to = to;
            _duration = duration;
            _deltaV = Tween.Sub(to, from);
        }

        public MethodTweener SetDelay(double d) { _delay = d; return this; }
        public MethodTweener SetTrans(TransitionType t) { _trans = t; return this; }
        public MethodTweener SetEase(EaseType e) { _ease = e; return this; }

        internal override bool Step(ref double delta)
        {
            if (finished) return false;
            elapsed += delta;
            if (elapsed < _delay) { delta = 0; return true; }
            double time = Math.Min(elapsed - _delay, _duration);
            object cur = time < _duration ? Tween.InterpolateValue(_from, _deltaV, time, _duration, _trans ?? tween.defaultTrans, _ease ?? tween.defaultEase) : _to;
            try { _cb(cur); }
            catch (Exception ex) { GD_Log.Error("tween method: " + ex); }
            if (time < _duration) { delta = 0; return true; }
            delta = elapsed - _delay - _duration;
            Finish();
            return false;
        }
    }

    /// <summary>GDScript property paths on C# objects: "self_modulate" -&gt; SelfModulate, "modulate:a" -&gt; Modulate.a.</summary>
    public static class PropertyPath
    {
        static readonly Dictionary<(Type, string), MemberInfo> _members = new Dictionary<(Type, string), MemberInfo>();

        public static string Pascal(string snake)
        {
            var sb = new System.Text.StringBuilder();
            bool up = true;
            foreach (char c in snake)
            {
                if (c == '_') { up = true; continue; }
                sb.Append(up ? char.ToUpperInvariant(c) : c);
                up = false;
            }
            return sb.ToString();
        }

        static MemberInfo Member(Type t, string name)
        {
            lock (_members)
            {
                if (_members.TryGetValue((t, name), out var m)) return m;
                string p = Pascal(name);
                const BindingFlags F = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.FlattenHierarchy;
                m = (MemberInfo)t.GetProperty(p, F) ?? (MemberInfo)t.GetField(p, F) ?? (MemberInfo)t.GetProperty(name, F) ?? t.GetField(name, F);
                _members[(t, name)] = m;
                return m;
            }
        }

        static object GetMember(object o, string name)
        {
            if (o is Node n && n.HasMeta(name) && Member(o.GetType(), name) == null) return n.GetMeta(name);
            var m = Member(o.GetType(), name);
            if (m is PropertyInfo pi) return pi.GetValue(o);
            if (m is FieldInfo fi) return fi.GetValue(o);
            if (o is Node nn && nn.HasMeta(name)) return nn.GetMeta(name);
            throw new MissingMemberException(o.GetType().Name, name);
        }

        static void SetMember(object o, string name, object v)
        {
            var m = Member(o.GetType(), name);
            if (m is PropertyInfo pi) { pi.SetValue(o, Tween.Convert(v, pi.PropertyType)); return; }
            if (m is FieldInfo fi) { fi.SetValue(o, Tween.Convert(v, fi.FieldType)); return; }
            if (o is Node n) { n.SetMeta(name, v); return; }
            throw new MissingMemberException(o.GetType().Name, name);
        }

        static object GetSub(object v, string s)
        {
            switch (v)
            {
                case Vec2 a: return s == "x" ? (double)a.x : (double)a.y;
                case Vec3 a: return s == "x" ? (double)a.x : s == "y" ? (double)a.y : (double)a.z;
                case Col c: return s == "r" ? (double)c.r : s == "g" ? (double)c.g : s == "b" ? (double)c.b : s == "a" ? (double)c.a : s == "h" ? (double)c.H : s == "s" ? (double)c.S : (double)c.V;
                case Rect2 r: return s == "position" ? (object)r.position : r.size;
            }
            return GetMember(v, s);
        }

        static object SetSub(object v, string s, object x)
        {
            double d = x is double dd ? dd : x is float ff ? ff : 0;
            switch (v)
            {
                case Vec2 a: if (s == "x") a.x = (float)d; else a.y = (float)d; return a;
                case Vec3 a: if (s == "x") a.x = (float)d; else if (s == "y") a.y = (float)d; else a.z = (float)d; return a;
                case Col c:
                    if (s == "r") c.r = (float)d; else if (s == "g") c.g = (float)d; else if (s == "b") c.b = (float)d; else if (s == "a") c.a = (float)d;
                    return c;
                case Rect2 r: if (s == "position") r.position = (Vec2)x; else r.size = (Vec2)x; return r;
            }
            SetMember(v, s, x);
            return v;
        }

        /// <summary>get_indexed(path).</summary>
        public static object Get(object target, string path)
        {
            var parts = path.Split(':');
            object v = GetMember(target, parts[0]);
            for (int i = 1; i < parts.Length; i++) v = GetSub(v, parts[i]);
            return v;
        }

        /// <summary>set_indexed(path, value).</summary>
        public static void Set(object target, string path, object value)
        {
            var parts = path.Split(':');
            if (parts.Length == 1) { SetMember(target, parts[0], value); return; }
            var chain = new object[parts.Length];
            chain[0] = GetMember(target, parts[0]);
            for (int i = 1; i < parts.Length - 1; i++) chain[i] = GetSub(chain[i - 1], parts[i]);
            object cur = value;
            for (int i = parts.Length - 1; i >= 1; i--) cur = SetSub(chain[i - 1], parts[i], cur);
            SetMember(target, parts[0], cur);
        }

        /// <summary>A tween's final value in the property's own type (GDScript passes 1 for 1.0 freely).</summary>
        public static object Coerce(object v, object like)
        {
            if (like == null || v == null) return v;
            if (like.GetType() == v.GetType()) return v;
            if (like is double) return System.Convert.ToDouble(v);
            if (like is float) return (float)System.Convert.ToDouble(v);
            if (like is int) return System.Convert.ToInt32(v);
            return v;
        }
    }
}
