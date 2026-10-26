#if FB3D
// Godot's Animation resource (scene/resources/animation.cpp, 4.7): every track type as data (value, position/rotation/
// scale 3D, blend shape, method, bezier, audio, animation), Godot's key insertion (_insert), key search (_find, with the
// is_equal_approx match), interpolation (nearest, linear, cubic, linear/cubic angle; key transitions as ease curves) and
// loop wrap (none, linear, ping-pong) exactly as _interpolate does it, in real_t (float) where Godot uses real_t.
// position/rotation/scale/blend_shape/value_track_interpolate, bezier_track_interpolate, track_get_key_indices_in_range
// (method and discrete tracks), markers. The baked-asset loader feeds Godot's stored properties through SetStoredProperty
// ("length", "loop_mode", "step", "markers", "tracks/N/type|imported|enabled|path|interp|loop_wrap|keys|use_blend") in
// Godot's stored formats (transform keys: a PackedFloat32Array of [time, transition, x, y, z(, w)] per key; value keys: a
// Dictionary {times, transitions, values, update}). Compressed animations ("_compression", Animation.compress()) are not
// supported: the game's .res libraries and imported glTF scenes store their tracks uncompressed (checked in Godot).
//
// NodePath (Godot's core/string/node_path.cpp parse): the track paths ("Armature/Skeleton3D:hips" -> names
// [Armature, Skeleton3D], subnames [hips]) with get_name/get_subname(_count); converts from and to string.
//
// The game's AnimationMixer reads the keys through internal entry points that take a per-track key hint (the previous
// key index), checked so the result is exactly what the binary search gives.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    /// <summary>Godot's NodePath: "a/b:c:d" (names a, b; subnames c, d), "/root/x" (absolute), "." , "..".</summary>
    public readonly struct NodePath : IEquatable<NodePath>
    {
        readonly string[] _names, _subnames;
        readonly bool _absolute;
        readonly string _str;

        public NodePath(string path)
        {
            _names = Array.Empty<string>();
            _subnames = Array.Empty<string>();
            _absolute = false;
            _str = "";
            if (string.IsNullOrEmpty(path)) return;
            string p = path;
            var sub = new List<string>();
            bool absolute = p[0] == '/';
            int subpos = p.IndexOf(':');
            if (subpos != -1)
            {
                int from = subpos + 1;
                for (int i = from; i <= p.Length; i++)
                {
                    if (i == p.Length || p[i] == ':')
                    {
                        string s = p.Substring(from, i - from);
                        if (s.Length == 0)
                        {
                            if (i == p.Length) continue;
                            GD.PushError("Invalid NodePath '" + path + "'.");
                            return;
                        }
                        sub.Add(s);
                        from = i + 1;
                    }
                }
                p = p.Substring(0, subpos);
            }
            var names = new List<string>();
            bool lastIsSlash = true;
            int start = absolute ? 1 : 0, f = start;
            for (int i = start; i <= p.Length; i++)
            {
                if (i == p.Length || p[i] == '/')
                {
                    if (!lastIsSlash) names.Add(p.Substring(f, i - f));
                    f = i + 1;
                    lastIsSlash = true;
                }
                else lastIsSlash = false;
            }
            if (names.Count == 0 && !absolute && sub.Count == 0) return;
            _names = names.ToArray();
            _subnames = sub.ToArray();
            _absolute = absolute;
            _str = Build(_names, _subnames, absolute);
        }

        static string Build(string[] names, string[] sub, bool absolute)
        {
            var sb = new System.Text.StringBuilder();
            if (absolute) sb.Append('/');
            for (int i = 0; i < names.Length; i++) { if (i > 0) sb.Append('/'); sb.Append(names[i]); }
            for (int i = 0; i < sub.Length; i++) { sb.Append(':'); sb.Append(sub[i]); }
            return sb.ToString();
        }

        public static implicit operator NodePath(string s) => new NodePath(s);
        public static explicit operator string(NodePath p) => p.ToString();

        public bool IsAbsolute() => _absolute;
        public bool IsEmpty() => (_names?.Length ?? 0) == 0 && (_subnames?.Length ?? 0) == 0 && !_absolute;
        public int GetNameCount() => _names?.Length ?? 0;
        public string GetName(int i) => _names != null && (uint)i < (uint)_names.Length ? _names[i] : "";
        public int GetSubnameCount() => _subnames?.Length ?? 0;
        public string GetSubname(int i) => _subnames != null && (uint)i < (uint)_subnames.Length ? _subnames[i] : "";
        public string GetConcatenatedNames() => Build(_names ?? Array.Empty<string>(), Array.Empty<string>(), _absolute);
        public string GetConcatenatedSubnames() => string.Join(":", _subnames ?? Array.Empty<string>());
        /// <summary>The node part ("a/b"), for get_node.</summary>
        public string NodePart => GetConcatenatedNames();
        public string[] Subnames => _subnames ?? Array.Empty<string>();

        public override string ToString() => _str ?? "";
        public bool Equals(NodePath o) => string.Equals(_str ?? "", o._str ?? "", StringComparison.Ordinal);
        public override bool Equals(object o) => o is NodePath p && Equals(p);
        public override int GetHashCode() => (_str ?? "").GetHashCode();
        public static bool operator ==(NodePath a, NodePath b) => a.Equals(b);
        public static bool operator !=(NodePath a, NodePath b) => !a.Equals(b);
    }

    public class Animation : Resource
    {
        public enum TrackType : byte { Value = 0, Position3D = 1, Rotation3D = 2, Scale3D = 3, BlendShape = 4, Method = 5, Bezier = 6, Audio = 7, Animation = 8 }
        public enum InterpolationType : byte { Nearest = 0, Linear = 1, Cubic = 2, LinearAngle = 3, CubicAngle = 4 }
        public enum UpdateMode : byte { Continuous = 0, Discrete = 1, Capture = 2 }
        public enum LoopModeEnum : byte { None = 0, Linear = 1, Pingpong = 2 }
        public enum LoopedFlag : byte { None = 0, End = 1, Start = 2 }
        public enum FindMode : byte { Nearest = 0, Approx = 1, Exact = 2 }

        public const TrackType TYPE_VALUE = TrackType.Value, TYPE_POSITION_3D = TrackType.Position3D, TYPE_ROTATION_3D = TrackType.Rotation3D,
            TYPE_SCALE_3D = TrackType.Scale3D, TYPE_BLEND_SHAPE = TrackType.BlendShape, TYPE_METHOD = TrackType.Method,
            TYPE_BEZIER = TrackType.Bezier, TYPE_AUDIO = TrackType.Audio, TYPE_ANIMATION = TrackType.Animation;
        public const InterpolationType INTERPOLATION_NEAREST = InterpolationType.Nearest, INTERPOLATION_LINEAR = InterpolationType.Linear,
            INTERPOLATION_CUBIC = InterpolationType.Cubic, INTERPOLATION_LINEAR_ANGLE = InterpolationType.LinearAngle,
            INTERPOLATION_CUBIC_ANGLE = InterpolationType.CubicAngle;
        public const UpdateMode UPDATE_CONTINUOUS = UpdateMode.Continuous, UPDATE_DISCRETE = UpdateMode.Discrete, UPDATE_CAPTURE = UpdateMode.Capture;
        public const LoopModeEnum LOOP_NONE = LoopModeEnum.None, LOOP_LINEAR = LoopModeEnum.Linear, LOOP_PINGPONG = LoopModeEnum.Pingpong;
        public const LoopedFlag LOOPED_FLAG_NONE = LoopedFlag.None, LOOPED_FLAG_END = LoopedFlag.End, LOOPED_FLAG_START = LoopedFlag.Start;
        public const FindMode FIND_MODE_NEAREST = FindMode.Nearest, FIND_MODE_APPROX = FindMode.Approx, FIND_MODE_EXACT = FindMode.Exact;
        public const double ANIM_MIN_LENGTH = 0.001;
        public const float DEFAULT_STEP = 1.0f / 30;

        // ------------------------------------------------------------------ tracks
        internal abstract class Track
        {
            public TrackType type;
            public InterpolationType interpolation = InterpolationType.Linear;
            public bool loopWrap = true, imported, enabled = true;
            public NodePath path;
            public string concatenatedPath = "";
            public double[] times = Array.Empty<double>();
            public float[] transitions = Array.Empty<float>();
            public int count;
            public int keyVersion;
            // _find(keys, length) + 1, cached per (keys, length)
            internal int lenVer = -1;
            internal double lenLength;
            internal int lenValue;
            internal abstract void Grow(int cap);
            internal abstract void RemoveValueAt(int i);
            internal abstract void InsertValueAt(int i);
        }

        internal class Track<T> : Track
        {
            public T[] values = Array.Empty<T>();

            internal override void Grow(int cap)
            {
                if (times.Length >= cap) return;
                int n = Math.Max(cap, Math.Max(4, times.Length * 2));
                Array.Resize(ref times, n);
                Array.Resize(ref transitions, n);
                Array.Resize(ref values, n);
            }

            internal override void RemoveValueAt(int i)
            {
                Array.Copy(times, i + 1, times, i, count - i - 1);
                Array.Copy(transitions, i + 1, transitions, i, count - i - 1);
                Array.Copy(values, i + 1, values, i, count - i - 1);
                count--;
                values[count] = default;
                keyVersion++;
            }

            internal override void InsertValueAt(int i)
            {
                Grow(count + 1);
                Array.Copy(times, i, times, i + 1, count - i);
                Array.Copy(transitions, i, transitions, i + 1, count - i);
                Array.Copy(values, i, values, i + 1, count - i);
                count++;
                keyVersion++;
            }

            /// <summary>Godot's _insert: a key at (about) the same time is replaced, keeping its transition.</summary>
            public int Insert(double time, T value, float transition)
            {
                int idx = count;
                while (true)
                {
                    if (idx > 0 && GD.IsEqualApprox(times[idx - 1], time))
                    {
                        times[idx - 1] = time;
                        values[idx - 1] = value;
                        keyVersion++;
                        return idx - 1;
                    }
                    if (idx == 0 || times[idx - 1] < time)
                    {
                        InsertValueAt(idx);
                        times[idx] = time;
                        transitions[idx] = transition;
                        values[idx] = value;
                        return idx;
                    }
                    idx--;
                }
            }

            public void SetCount(int n)
            {
                times = new double[n];
                transitions = new float[n];
                values = new T[n];
                count = n;
                keyVersion++;
            }
        }

        internal sealed class ValueTrack : Track<Var> { public UpdateMode updateMode = UpdateMode.Continuous; }
        internal struct MethodKey { public string method; public Var[] args; }
        internal struct BezierKey { public Vec2 inHandle, outHandle; public float value; public int handleMode; }
        internal struct AudioKey { public Resource stream; public float startOffset, endOffset; }
        internal sealed class AudioTrack : Track<AudioKey> { public bool useBlend = true; }

        readonly List<Track> _tracks = new List<Track>();
        double _length = 1.0;
        float _step = DEFAULT_STEP;
        LoopModeEnum _loopMode = LoopModeEnum.None;
        bool _captureIncluded;
        struct MarkerKey { public double time; public string name; }
        readonly List<MarkerKey> _markerNames = new List<MarkerKey>();
        readonly Dictionary<string, double> _markerTimes = new Dictionary<string, double>();
        readonly Dictionary<string, Col> _markerColors = new Dictionary<string, Col>();
        /// <summary>Bumped when tracks are added, removed, moved or re-pathed (the mixers' track bindings).</summary>
        internal int structureVersion;

        internal List<Track> Tracks => _tracks;

        // ------------------------------------------------------------------ properties
        public double Length
        {
            get => _length;
            set { _length = value < ANIM_MIN_LENGTH ? ANIM_MIN_LENGTH : value; EmitChanged(); }
        }
        public void SetLength(double l) => Length = l;
        public double GetLength() => _length;

        public LoopModeEnum LoopMode
        {
            get => _loopMode;
            set { _loopMode = value; EmitChanged(); }
        }
        public void SetLoopMode(LoopModeEnum m) => LoopMode = m;
        public LoopModeEnum GetLoopMode() => _loopMode;

        public double Step
        {
            get => _step;
            set { _step = (float)value; EmitChanged(); }
        }
        public void SetStep(double s) => Step = s;
        public double GetStep() => _step;

        public bool IsCaptureIncluded() => _captureIncluded;

        void CheckCaptureIncluded()
        {
            _captureIncluded = false;
            foreach (var t in _tracks)
                if (t is ValueTrack vt && vt.updateMode == UpdateMode.Capture) { _captureIncluded = true; break; }
        }

        bool TrackOk(int track)
        {
            if ((uint)track < (uint)_tracks.Count) return true;
            GD.PushError("Index p_track = " + track + " is out of bounds (tracks.size() = " + _tracks.Count + ").");
            return false;
        }

        // ------------------------------------------------------------------ stored properties
        public override bool SetStoredProperty(string name, Var value)
        {
            switch (name)
            {
                case "length": Length = value.AsFloat(); return true;
                case "loop_mode": LoopMode = (LoopModeEnum)value.AsInt(); return true;
                case "step": Step = value.AsFloat(); return true;
                case "capture_included": return true;           // (read-only: recomputed from the tracks)
                case "loop": if (value.Truthy) _loopMode = LoopModeEnum.Linear; return true;    // (Godot 3.x)
                case "_compression":
                    GD.PushError("Animation: compressed animations are not supported by the port (re-import without compression).");
                    return true;
                case "markers":
                {
                    var arr = value.AsArr();
                    if (arr == null) return false;
                    foreach (var m in arr)
                    {
                        var d = m.AsDict();
                        if (d == null || !d.Has("name") || !d.Has("time")) return false;
                        string mn = d["name"].AsString();
                        double mt = d["time"].AsFloat();
                        MarkerInsert(mt, mn);
                        _markerTimes[mn] = mt;
                        _markerColors[mn] = d.Has("color") && d["color"].Obj is Col c ? c : new Col(1f, 1f, 1f, 1f);
                    }
                    return true;
                }
            }
            if (!name.StartsWith("tracks/")) return false;
            int s1 = name.IndexOf('/', 7);
            if (s1 < 0) return false;
            int track = (int)GStr.ToInt(name.Substring(7, s1 - 7));
            string what = name.Substring(s1 + 1);
            if (_tracks.Count == track && what == "type")
            {
                switch (value.AsString())
                {
                    case "position_3d": AddTrack(TrackType.Position3D); break;
                    case "rotation_3d": AddTrack(TrackType.Rotation3D); break;
                    case "scale_3d": AddTrack(TrackType.Scale3D); break;
                    case "blend_shape": AddTrack(TrackType.BlendShape); break;
                    case "value": AddTrack(TrackType.Value); break;
                    case "method": AddTrack(TrackType.Method); break;
                    case "bezier": AddTrack(TrackType.Bezier); break;
                    case "audio": AddTrack(TrackType.Audio); break;
                    case "animation": AddTrack(TrackType.Animation); break;
                    default: return false;
                }
                return true;
            }
            if ((uint)track >= (uint)_tracks.Count) { TrackOk(track); return false; }
            var t = _tracks[track];
            switch (what)
            {
                case "path": TrackSetPath(track, new NodePath(value.AsString())); return true;
                case "compressed_track": GD.PushError("Animation: compressed tracks are not supported by the port."); return false;
                case "use_blend": if (t.type == TrackType.Audio) AudioTrackSetUseBlend(track, value.Truthy); return true;
                case "interp": TrackSetInterpolationType(track, (InterpolationType)value.AsInt()); return true;
                case "loop_wrap": TrackSetInterpolationLoopWrap(track, value.Truthy); return true;
                case "imported": TrackSetImported(track, value.Truthy); return true;
                case "enabled": TrackSetEnabled(track, value.Truthy); return true;
                case "keys":
                case "key_values":
                    return SetStoredKeys(t, value);
            }
            return false;
        }

        bool SetStoredKeys(Track t, Var value)
        {
            switch (t.type)
            {
                case TrackType.Position3D:
                case TrackType.Scale3D:
                case TrackType.Rotation3D:
                case TrackType.BlendShape:
                {
                    var r = AnimVar.ToReals(value);
                    int size = t.type == TrackType.Rotation3D ? 6 : t.type == TrackType.BlendShape ? 3 : 5;
                    if (r == null || r.Length % size != 0) { GD.PushError("Condition \"vcount % " + size + "\" is true."); return false; }
                    int count = r.Length / size;
                    if (t is Track<Vec3> v3)
                    {
                        v3.SetCount(count);
                        for (int i = 0; i < count; i++)
                        {
                            int o = i * size;
                            v3.times[i] = r[o];
                            v3.transitions[i] = r[o + 1];
                            v3.values[i] = new Vec3(r[o + 2], r[o + 3], r[o + 4]);
                        }
                    }
                    else if (t is Track<Quat> q)
                    {
                        q.SetCount(count);
                        for (int i = 0; i < count; i++)
                        {
                            int o = i * size;
                            q.times[i] = r[o];
                            q.transitions[i] = r[o + 1];
                            q.values[i] = new Quat(r[o + 2], r[o + 3], r[o + 4], r[o + 5]);
                        }
                    }
                    else if (t is Track<float> bs)
                    {
                        bs.SetCount(count);
                        for (int i = 0; i < count; i++)
                        {
                            int o = i * size;
                            bs.times[i] = r[o];
                            bs.transitions[i] = r[o + 1];
                            bs.values[i] = r[o + 2];
                        }
                    }
                    return true;
                }
                case TrackType.Value:
                {
                    var vt = (ValueTrack)t;
                    var d = value.AsDict();
                    if (d == null || !d.Has("times") || !d.Has("values")) return false;
                    if (d.Has("cont")) vt.updateMode = d["cont"].Truthy ? UpdateMode.Continuous : UpdateMode.Discrete;
                    if (d.Has("update"))
                    {
                        int um = d["update"].AsInt();
                        if (um < 0) um = 0;
                        else if (um > 3) um = 3;
                        vt.updateMode = (UpdateMode)um;
                    }
                    _captureIncluded = _captureIncluded || vt.updateMode == UpdateMode.Capture;
                    var times = AnimVar.ToReals(d["times"]);
                    var values = d["values"].AsArr();
                    if (times == null || values == null || times.Length != values.Size()) return false;
                    if (times.Length > 0)
                    {
                        int n = times.Length;
                        vt.SetCount(n);
                        for (int i = 0; i < n; i++)
                        {
                            vt.times[i] = times[i];
                            vt.transitions[i] = 1f;
                            vt.values[i] = AnimVar.Normalize(values[i]);
                        }
                        if (d.Has("transitions"))
                        {
                            var tr = AnimVar.ToReals(d["transitions"]);
                            if (tr == null || tr.Length != n) return false;
                            for (int i = 0; i < n; i++) vt.transitions[i] = tr[i];
                        }
                    }
                    return true;
                }
                case TrackType.Method:
                {
                    int ti = _tracks.IndexOf(t);
                    while (TrackGetKeyCount(ti) > 0) TrackRemoveKey(ti, 0);
                    var d = value.AsDict();
                    if (d == null || !d.Has("times") || !d.Has("values")) return false;
                    var times = AnimVar.ToReals(d["times"]);
                    var values = d["values"].AsArr();
                    if (times == null || values == null || times.Length != values.Size()) return false;
                    for (int i = 0; i < times.Length; i++) TrackInsertKey(ti, times[i], values[i]);
                    if (d.Has("transitions"))
                    {
                        var tr = AnimVar.ToReals(d["transitions"]);
                        if (tr == null || tr.Length != times.Length) return false;
                        for (int i = 0; i < tr.Length; i++) TrackSetKeyTransition(ti, i, tr[i]);
                    }
                    return true;
                }
                case TrackType.Bezier:
                {
                    var bt = (Track<BezierKey>)t;
                    var d = value.AsDict();
                    if (d == null || !d.Has("times") || !d.Has("points")) return false;
                    var times = AnimVar.ToReals(d["times"]);
                    var pts = AnimVar.ToReals(d["points"]);
                    if (times == null || pts == null || times.Length * 5 != pts.Length) return false;
                    var hm = d.Has("handle_modes") ? d["handle_modes"].Obj as int[] : null;
                    bt.SetCount(times.Length);
                    for (int i = 0; i < times.Length; i++)
                    {
                        bt.times[i] = times[i];
                        bt.transitions[i] = 0;
                        bt.values[i] = new BezierKey
                        {
                            value = pts[i * 5],
                            inHandle = new Vec2(pts[i * 5 + 1], pts[i * 5 + 2]),
                            outHandle = new Vec2(pts[i * 5 + 3], pts[i * 5 + 4]),
                            handleMode = hm != null && i < hm.Length ? hm[i] : 0,
                        };
                    }
                    return true;
                }
                case TrackType.Audio:
                {
                    var at = (AudioTrack)t;
                    var d = value.AsDict();
                    if (d == null || !d.Has("times") || !d.Has("clips")) return false;
                    var times = AnimVar.ToReals(d["times"]);
                    var clips = d["clips"].AsArr();
                    if (times == null || clips == null || times.Length != clips.Size()) return false;
                    at.SetCount(0);
                    for (int i = 0; i < times.Length; i++)
                    {
                        var c = clips[i].AsDict();
                        if (c == null || !c.Has("start_offset") || !c.Has("end_offset") || !c.Has("stream")) continue;
                        at.Grow(at.count + 1);
                        at.times[at.count] = times[i];
                        at.transitions[at.count] = 1f;
                        at.values[at.count] = new AudioKey { startOffset = (float)c["start_offset"].AsFloat(), endOffset = (float)c["end_offset"].AsFloat(), stream = c["stream"].Obj as Resource };
                        at.count++;
                    }
                    at.keyVersion++;
                    return true;
                }
                case TrackType.Animation:
                {
                    var an = (Track<string>)t;
                    var d = value.AsDict();
                    if (d == null || !d.Has("times") || !d.Has("clips")) return false;
                    var times = AnimVar.ToReals(d["times"]);
                    var clips = d["clips"];
                    var names = clips.Obj as string[];
                    var arr = clips.AsArr();
                    int n = names?.Length ?? arr?.Size() ?? -1;
                    if (times == null || times.Length != n) return false;
                    an.SetCount(n);
                    for (int i = 0; i < n; i++)
                    {
                        an.times[i] = times[i];
                        an.transitions[i] = 1f;
                        an.values[i] = names != null ? names[i] : arr[i].AsString();
                    }
                    return true;
                }
            }
            return false;
        }

        // ------------------------------------------------------------------ track management
        public int AddTrack(TrackType type, int atPos = -1)
        {
            if ((uint)atPos >= (uint)_tracks.Count) atPos = _tracks.Count;
            Track t;
            switch (type)
            {
                case TrackType.Position3D: case TrackType.Scale3D: t = new Track<Vec3>(); break;
                case TrackType.Rotation3D: t = new Track<Quat>(); break;
                case TrackType.BlendShape: t = new Track<float>(); break;
                case TrackType.Value: t = new ValueTrack(); break;
                case TrackType.Method: t = new Track<MethodKey>(); break;
                case TrackType.Bezier: t = new Track<BezierKey>(); break;
                case TrackType.Audio: t = new AudioTrack(); break;
                case TrackType.Animation: t = new Track<string>(); break;
                default: GD.PushError("Unknown track type"); return atPos;
            }
            t.type = type;
            _tracks.Insert(atPos, t);
            structureVersion++;
            EmitChanged();
            return atPos;
        }

        public void RemoveTrack(int track)
        {
            if (!TrackOk(track)) return;
            _tracks.RemoveAt(track);
            structureVersion++;
            EmitChanged();
            CheckCaptureIncluded();
        }

        public int GetTrackCount() => _tracks.Count;
        public TrackType TrackGetType(int track) => TrackOk(track) ? _tracks[track].type : TrackType.Value;

        public void TrackSetPath(int track, NodePath path)
        {
            if (!TrackOk(track)) return;
            _tracks[track].path = path;
            _tracks[track].concatenatedPath = path.ToString();
            structureVersion++;
            EmitChanged();
        }

        public NodePath TrackGetPath(int track) => TrackOk(track) ? _tracks[track].path : default;

        public int FindTrack(NodePath path, TrackType type)
        {
            for (int i = 0; i < _tracks.Count; i++)
                if (_tracks[i].path == path && _tracks[i].type == type) return i;
            return -1;
        }

        /// <summary>get_cache_type: bezier tracks blend as value tracks; rotation and scale share the position cache.</summary>
        public static TrackType GetCacheType(TrackType t)
        {
            if (t == TrackType.Bezier) return TrackType.Value;
            if (t == TrackType.Rotation3D || t == TrackType.Scale3D) return TrackType.Position3D;
            return t;
        }

        public void TrackMoveUp(int track)
        {
            if (track < _tracks.Count - 1) { var x = _tracks[track]; _tracks[track] = _tracks[track + 1]; _tracks[track + 1] = x; }
            structureVersion++;
            EmitChanged();
        }

        public void TrackMoveDown(int track)
        {
            if ((uint)track < (uint)_tracks.Count && track > 0) { var x = _tracks[track]; _tracks[track] = _tracks[track - 1]; _tracks[track - 1] = x; }
            structureVersion++;
            EmitChanged();
        }

        public void TrackMoveTo(int track, int toIndex)
        {
            if (!TrackOk(track)) return;
            if ((uint)toIndex > (uint)_tracks.Count) { GD.PushError("Index p_to_index out of bounds."); return; }
            if (track == toIndex || track == toIndex - 1) return;
            var t = _tracks[track];
            _tracks.RemoveAt(track);
            _tracks.Insert(toIndex > track ? toIndex - 1 : toIndex, t);
            structureVersion++;
            EmitChanged();
        }

        public void TrackSwap(int track, int withTrack)
        {
            if (!TrackOk(track) || !TrackOk(withTrack)) return;
            if (track == withTrack) return;
            var x = _tracks[track];
            _tracks[track] = _tracks[withTrack];
            _tracks[withTrack] = x;
            structureVersion++;
            EmitChanged();
        }

        public void TrackSetImported(int track, bool imported) { if (TrackOk(track)) _tracks[track].imported = imported; }
        public bool TrackIsImported(int track) => TrackOk(track) && _tracks[track].imported;
        public void TrackSetEnabled(int track, bool enabled) { if (!TrackOk(track)) return; _tracks[track].enabled = enabled; EmitChanged(); }
        public bool TrackIsEnabled(int track) => TrackOk(track) && _tracks[track].enabled;
        public void TrackSetInterpolationType(int track, InterpolationType interp) { if (!TrackOk(track)) return; _tracks[track].interpolation = interp; EmitChanged(); }
        public InterpolationType TrackGetInterpolationType(int track) => TrackOk(track) ? _tracks[track].interpolation : InterpolationType.Nearest;
        public void TrackSetInterpolationLoopWrap(int track, bool enable) { if (!TrackOk(track)) return; _tracks[track].loopWrap = enable; EmitChanged(); }
        public bool TrackGetInterpolationLoopWrap(int track) => TrackOk(track) && _tracks[track].loopWrap;
        public bool TrackIsCompressed(int track) => false;

        public void Clear()
        {
            _tracks.Clear();
            _loopMode = LoopModeEnum.None;
            _length = 1;
            structureVersion++;
            EmitChanged();
        }

        /// <summary>duplicate(): a new Animation with copies of the tracks and keys (key values are shared, as Godot's
        /// Variants are).</summary>
        public override Resource Duplicate(bool deep = false)
        {
            var a = new Animation { ResourceName = ResourceName, ResourcePath = "" };
            a._length = _length;
            a._step = _step;
            a._loopMode = _loopMode;
            a._captureIncluded = _captureIncluded;
            foreach (var t in _tracks) a._tracks.Add(CloneTrack(t));
            a._markerNames.AddRange(_markerNames);
            foreach (var kv in _markerTimes) a._markerTimes[kv.Key] = kv.Value;
            foreach (var kv in _markerColors) a._markerColors[kv.Key] = kv.Value;
            return a;
        }

        static Track CloneTrack(Track t)
        {
            Track c;
            switch (t)
            {
                case ValueTrack v: { var n = new ValueTrack { updateMode = v.updateMode }; CopyKeys(v, n); c = n; break; }
                case AudioTrack au: { var n = new AudioTrack { useBlend = au.useBlend }; CopyKeys(au, n); c = n; break; }
                case Track<Vec3> v3: { var n = new Track<Vec3>(); CopyKeys(v3, n); c = n; break; }
                case Track<Quat> q: { var n = new Track<Quat>(); CopyKeys(q, n); c = n; break; }
                case Track<float> f: { var n = new Track<float>(); CopyKeys(f, n); c = n; break; }
                case Track<MethodKey> m: { var n = new Track<MethodKey>(); CopyKeys(m, n); c = n; break; }
                case Track<BezierKey> b: { var n = new Track<BezierKey>(); CopyKeys(b, n); c = n; break; }
                case Track<string> s: { var n = new Track<string>(); CopyKeys(s, n); c = n; break; }
                default: throw new InvalidOperationException();
            }
            c.type = t.type;
            c.interpolation = t.interpolation;
            c.loopWrap = t.loopWrap;
            c.imported = t.imported;
            c.enabled = t.enabled;
            c.path = t.path;
            c.concatenatedPath = t.concatenatedPath;
            return c;
        }

        static void CopyKeys<T>(Track<T> src, Track<T> dst)
        {
            dst.SetCount(src.count);
            Array.Copy(src.times, dst.times, src.count);
            Array.Copy(src.transitions, dst.transitions, src.count);
            Array.Copy(src.values, dst.values, src.count);
        }

        public void CopyTrack(int track, Animation to)
        {
            if (to == null || !TrackOk(track)) return;
            int dst = to.GetTrackCount();
            to.AddTrack(TrackGetType(track));
            to.TrackSetPath(dst, TrackGetPath(track));
            to.TrackSetImported(dst, TrackIsImported(track));
            to.TrackSetEnabled(dst, TrackIsEnabled(track));
            to.TrackSetInterpolationType(dst, TrackGetInterpolationType(track));
            to.TrackSetInterpolationLoopWrap(dst, TrackGetInterpolationLoopWrap(track));
            if (TrackGetType(track) == TrackType.Value) to.ValueTrackSetUpdateMode(dst, ValueTrackGetUpdateMode(track));
            for (int i = 0; i < TrackGetKeyCount(track); i++)
                to.TrackInsertKey(dst, TrackGetKeyTime(track, i), TrackGetKeyValue(track, i), TrackGetKeyTransition(track, i));
        }

        // ------------------------------------------------------------------ keys
        public int PositionTrackInsertKey(int track, double time, Vec3 position)
        {
            if (!TrackOk(track)) return -1;
            if (_tracks[track].type != TrackType.Position3D) { GD.PushError("Condition \"t->type != TYPE_POSITION_3D\" is true. Returning: -1"); return -1; }
            int r = ((Track<Vec3>)_tracks[track]).Insert(time, position, 1f);
            EmitChanged();
            return r;
        }

        public int RotationTrackInsertKey(int track, double time, Quat rotation)
        {
            if (!TrackOk(track)) return -1;
            if (_tracks[track].type != TrackType.Rotation3D) { GD.PushError("Condition \"t->type != TYPE_ROTATION_3D\" is true. Returning: -1"); return -1; }
            int r = ((Track<Quat>)_tracks[track]).Insert(time, rotation, 1f);
            EmitChanged();
            return r;
        }

        public int ScaleTrackInsertKey(int track, double time, Vec3 scale)
        {
            if (!TrackOk(track)) return -1;
            if (_tracks[track].type != TrackType.Scale3D) { GD.PushError("Condition \"t->type != TYPE_SCALE_3D\" is true. Returning: -1"); return -1; }
            int r = ((Track<Vec3>)_tracks[track]).Insert(time, scale, 1f);
            EmitChanged();
            return r;
        }

        public int BlendShapeTrackInsertKey(int track, double time, double blend)
        {
            if (!TrackOk(track)) return -1;
            if (_tracks[track].type != TrackType.BlendShape) { GD.PushError("Condition \"t->type != TYPE_BLEND_SHAPE\" is true. Returning: -1"); return -1; }
            int r = ((Track<float>)_tracks[track]).Insert(time, (float)blend, 1f);
            EmitChanged();
            return r;
        }

        public int TrackInsertKey(int track, double time, Var key, double transition = 1)
        {
            if (!TrackOk(track)) return -1;
            var t = _tracks[track];
            int ret = -1;
            float tr = (float)transition;
            switch (t.type)
            {
                case TrackType.Position3D:
                case TrackType.Scale3D:
                    if (!key.IsVec3 && !(key.Obj is Vec3i)) { GD.PushError("Condition \"(p_key.get_type() != Variant::VECTOR3) && (p_key.get_type() != Variant::VECTOR3I)\" is true. Returning: -1"); return -1; }
                    ret = t.type == TrackType.Position3D ? PositionTrackInsertKey(track, time, AnimVar.ToVec3(key)) : ScaleTrackInsertKey(track, time, AnimVar.ToVec3(key));
                    TrackSetKeyTransition(track, ret, tr);
                    break;
                case TrackType.Rotation3D:
                    if (!AnimVar.IsQuatOrBasis(key)) { GD.PushError("Condition \"(p_key.get_type() != Variant::QUATERNION) && (p_key.get_type() != Variant::BASIS)\" is true. Returning: -1"); return -1; }
                    ret = RotationTrackInsertKey(track, time, AnimVar.ToQuat(key));
                    TrackSetKeyTransition(track, ret, tr);
                    break;
                case TrackType.BlendShape:
                    if (!key.IsNum) { GD.PushError("Condition \"(p_key.get_type() != Variant::FLOAT) && (p_key.get_type() != Variant::INT)\" is true. Returning: -1"); return -1; }
                    ret = BlendShapeTrackInsertKey(track, time, key.AsFloat());
                    TrackSetKeyTransition(track, ret, tr);
                    break;
                case TrackType.Value:
                    ret = ((ValueTrack)t).Insert(time, AnimVar.Normalize(key), tr);
                    break;
                case TrackType.Method:
                {
                    var d = key.AsDict();
                    if (d == null) { GD.PushError("Condition \"p_key.get_type() != Variant::DICTIONARY\" is true. Returning: -1"); return -1; }
                    if (!d.Has("method") || !d["method"].IsString) { GD.PushError("Condition \"!d.has(\"method\") || !d[\"method\"].is_string()\" is true. Returning: -1"); return -1; }
                    if (!d.Has("args") || !d["args"].IsArr) { GD.PushError("Condition \"!d.has(\"args\") || !d[\"args\"].is_array()\" is true. Returning: -1"); return -1; }
                    var args = d["args"].AsArr();
                    var a = new Var[args.Size()];
                    for (int i = 0; i < a.Length; i++) a[i] = args[i];
                    ret = ((Track<MethodKey>)t).Insert(time, new MethodKey { method = d["method"].AsString(), args = a }, tr);
                    break;
                }
                case TrackType.Bezier:
                {
                    var arr = key.AsArr();
                    if (arr == null || arr.Size() != 5) { GD.PushError("Condition \"arr.size() != 5\" is true. Returning: -1"); return -1; }
                    var k = new BezierKey { value = (float)arr[0].AsFloat(), inHandle = new Vec2((float)arr[1].AsFloat(), (float)arr[2].AsFloat()), outHandle = new Vec2((float)arr[3].AsFloat(), (float)arr[4].AsFloat()) };
                    ret = ((Track<BezierKey>)t).Insert(time, k, 1f);
                    break;
                }
                case TrackType.Audio:
                {
                    var d = key.AsDict();
                    if (d == null || !d.Has("start_offset") || !d.Has("end_offset") || !d.Has("stream")) { GD.PushError("Invalid audio key."); return -1; }
                    ret = ((AudioTrack)t).Insert(time, new AudioKey { startOffset = (float)d["start_offset"].AsFloat(), endOffset = (float)d["end_offset"].AsFloat(), stream = d["stream"].Obj as Resource }, 1f);
                    break;
                }
                case TrackType.Animation:
                    ret = ((Track<string>)t).Insert(time, key.AsString(), 1f);
                    break;
            }
            EmitChanged();
            return ret;
        }

        public void TrackRemoveKey(int track, int idx)
        {
            if (!TrackOk(track)) return;
            var t = _tracks[track];
            if ((uint)idx >= (uint)t.count) { GD.PushError("Index p_idx = " + idx + " is out of bounds."); return; }
            t.RemoveValueAt(idx);
            EmitChanged();
        }

        public void TrackRemoveKeyAtTime(int track, double time)
        {
            int idx = TrackFindKey(track, time, FindMode.Approx);
            if (idx < 0) { GD.PushError("Condition \"idx < 0\" is true."); return; }
            TrackRemoveKey(track, idx);
        }

        public int TrackGetKeyCount(int track) => TrackOk(track) ? _tracks[track].count : -1;

        public double TrackGetKeyTime(int track, int key)
        {
            if (!TrackOk(track)) return -1;
            var t = _tracks[track];
            if ((uint)key >= (uint)t.count) { GD.PushError("Index p_key_idx = " + key + " is out of bounds."); return -1; }
            return t.times[key];
        }

        public double TrackGetKeyTransition(int track, int key)
        {
            if (!TrackOk(track)) return -1;
            var t = _tracks[track];
            if ((uint)key >= (uint)t.count) { GD.PushError("Index p_key_idx = " + key + " is out of bounds."); return -1; }
            if (t.type == TrackType.Bezier || t.type == TrackType.Audio || t.type == TrackType.Animation) return 1;
            return t.transitions[key];
        }

        public Var TrackGetKeyValue(int track, int key)
        {
            if (!TrackOk(track)) return Var.Nil;
            var t = _tracks[track];
            if ((uint)key >= (uint)t.count) { GD.PushError("Index p_key_idx = " + key + " is out of bounds."); return Var.Nil; }
            switch (t)
            {
                case Track<Vec3> v: return v.values[key];
                case Track<Quat> q: return Var.Of(q.values[key]);
                case Track<float> f: return (double)f.values[key];
                case ValueTrack vt: return vt.values[key];
                case Track<MethodKey> m:
                {
                    var d = new GDict();
                    d["method"] = m.values[key].method;
                    var args = new GArray();
                    foreach (var a in m.values[key].args) args.Append(a);
                    d["args"] = args;
                    return d;
                }
                case Track<BezierKey> b:
                {
                    var arr = new GArray();
                    var k = b.values[key];
                    arr.Append((double)k.value); arr.Append((double)k.inHandle.x); arr.Append((double)k.inHandle.y);
                    arr.Append((double)k.outHandle.x); arr.Append((double)k.outHandle.y);
                    return arr;
                }
                case AudioTrack at:
                {
                    var d = new GDict();
                    d["start_offset"] = (double)at.values[key].startOffset;
                    d["end_offset"] = (double)at.values[key].endOffset;
                    d["stream"] = Var.Of(at.values[key].stream);
                    return d;
                }
                case Track<string> s: return s.values[key];
            }
            return Var.Nil;
        }

        public void TrackSetKeyValue(int track, int key, Var value)
        {
            if (!TrackOk(track)) return;
            var t = _tracks[track];
            if ((uint)key >= (uint)t.count) { GD.PushError("Index p_key_idx = " + key + " is out of bounds."); return; }
            switch (t)
            {
                case Track<Vec3> v:
                    if (!value.IsVec3 && !(value.Obj is Vec3i)) { GD.PushError("Condition \"(p_value.get_type() != Variant::VECTOR3) && (p_value.get_type() != Variant::VECTOR3I)\" is true."); return; }
                    v.values[key] = AnimVar.ToVec3(value);
                    break;
                case Track<Quat> q:
                    if (!AnimVar.IsQuatOrBasis(value)) { GD.PushError("Condition \"(p_value.get_type() != Variant::QUATERNION) && (p_value.get_type() != Variant::BASIS)\" is true."); return; }
                    q.values[key] = AnimVar.ToQuat(value);
                    break;
                case Track<float> f:
                    if (!value.IsNum) { GD.PushError("Condition \"(p_value.get_type() != Variant::FLOAT) && (p_value.get_type() != Variant::INT)\" is true."); return; }
                    f.values[key] = (float)value.AsFloat();
                    break;
                case ValueTrack vt: vt.values[key] = AnimVar.Normalize(value); break;
                case Track<MethodKey> m:
                {
                    var d = value.AsDict();
                    if (d == null) return;
                    var k = m.values[key];
                    if (d.Has("method")) k.method = d["method"].AsString();
                    if (d.Has("args")) { var a = d["args"].AsArr(); k.args = new Var[a.Size()]; for (int i = 0; i < a.Size(); i++) k.args[i] = a[i]; }
                    m.values[key] = k;
                    break;
                }
                case Track<BezierKey> b:
                {
                    var arr = value.AsArr();
                    if (arr == null || arr.Size() != 5) { GD.PushError("Condition \"arr.size() != 5\" is true."); return; }
                    var k = b.values[key];
                    k.value = (float)arr[0].AsFloat();
                    k.inHandle = new Vec2((float)arr[1].AsFloat(), (float)arr[2].AsFloat());
                    k.outHandle = new Vec2((float)arr[3].AsFloat(), (float)arr[4].AsFloat());
                    b.values[key] = k;
                    break;
                }
                case AudioTrack at:
                {
                    var d = value.AsDict();
                    if (d == null || !d.Has("start_offset") || !d.Has("end_offset") || !d.Has("stream")) return;
                    at.values[key] = new AudioKey { startOffset = (float)d["start_offset"].AsFloat(), endOffset = (float)d["end_offset"].AsFloat(), stream = d["stream"].Obj as Resource };
                    break;
                }
                case Track<string> s: s.values[key] = value.AsString(); break;
            }
            t.keyVersion++;
            EmitChanged();
        }

        public void TrackSetKeyTime(int track, int key, double time)
        {
            if (!TrackOk(track)) return;
            var t = _tracks[track];
            if ((uint)key >= (uint)t.count) { GD.PushError("Index p_key_idx = " + key + " is out of bounds."); return; }
            switch (t)
            {
                case Track<Vec3> v: Move(v, key, time); return;
                case Track<Quat> q: Move(q, key, time); return;
                case Track<float> f: Move(f, key, time); return;
                case ValueTrack vt: Move(vt, key, time); return;
                case Track<MethodKey> m: Move(m, key, time); return;
                case Track<BezierKey> b: Move(b, key, time); return;
                case AudioTrack at: Move(at, key, time); return;
                case Track<string> s: Move(s, key, time); return;
            }
        }

        static void Move<T>(Track<T> t, int key, double time)
        {
            T v = t.values[key];
            float tr = t.transitions[key];
            t.RemoveValueAt(key);
            t.Insert(time, v, tr);
        }

        public void TrackSetKeyTransition(int track, int key, double transition)
        {
            if (!TrackOk(track)) return;
            var t = _tracks[track];
            if ((uint)key >= (uint)t.count) { GD.PushError("Index p_key_idx = " + key + " is out of bounds."); return; }
            if (t.type == TrackType.Bezier || t.type == TrackType.Audio || t.type == TrackType.Animation) { EmitChanged(); return; }
            t.transitions[key] = (float)transition;
            EmitChanged();
        }

        public int TrackFindKey(int track, double time, FindMode mode = FindMode.Nearest, bool limit = false, bool backward = false)
        {
            if (!TrackOk(track)) return -1;
            var t = _tracks[track];
            int k = Find(t, time, backward, limit);
            if ((uint)k >= (uint)t.count) return -1;
            if ((mode == FindMode.Approx && !GD.IsEqualApprox(t.times[k], time)) || (mode == FindMode.Exact && t.times[k] != time)) return -1;
            return k;
        }

        public Error PositionTrackGetKey(int track, int key, out Vec3 position)
        {
            position = Vec3.Zero;
            if (!TrackOk(track) || _tracks[track].type != TrackType.Position3D) return Error.InvalidParameter;
            var t = (Track<Vec3>)_tracks[track];
            if ((uint)key >= (uint)t.count) return Error.InvalidParameter;
            position = t.values[key];
            return Error.Ok;
        }

        public Error RotationTrackGetKey(int track, int key, out Quat rotation)
        {
            rotation = Quat.IDENTITY;
            if (!TrackOk(track) || _tracks[track].type != TrackType.Rotation3D) return Error.InvalidParameter;
            var t = (Track<Quat>)_tracks[track];
            if ((uint)key >= (uint)t.count) return Error.InvalidParameter;
            rotation = t.values[key];
            return Error.Ok;
        }

        public Error ScaleTrackGetKey(int track, int key, out Vec3 scale)
        {
            scale = Vec3.Zero;
            if (!TrackOk(track) || _tracks[track].type != TrackType.Scale3D) return Error.InvalidParameter;
            var t = (Track<Vec3>)_tracks[track];
            if ((uint)key >= (uint)t.count) return Error.InvalidParameter;
            scale = t.values[key];
            return Error.Ok;
        }

        public Error BlendShapeTrackGetKey(int track, int key, out float blend)
        {
            blend = 0;
            if (!TrackOk(track) || _tracks[track].type != TrackType.BlendShape) return Error.InvalidParameter;
            var t = (Track<float>)_tracks[track];
            if ((uint)key >= (uint)t.count) return Error.InvalidParameter;
            blend = t.values[key];
            return Error.Ok;
        }

        public enum Error { Ok = 0, Unavailable = 2, InvalidParameter = 31 }

        // ------------------------------------------------------------------ key search (_find)
        internal int Find(Track t, double time, bool backward = false, bool limit = false)
        {
            int len = t.count;
            if (len == 0) return -2;
            int low = 0, high = len - 1, middle = 0;
            var keys = t.times;
            while (low <= high)
            {
                middle = (low + high) / 2;
                if (GD.IsEqualApprox(time, keys[middle])) return middle;
                if (time < keys[middle]) high = middle - 1;
                else low = middle + 1;
            }
            if (!backward) { if (keys[middle] > time) middle--; }
            else { if (keys[middle] < time) middle++; }
            if (limit && middle > -1 && middle < len)
            {
                double diff = _length - keys[middle];
                if ((IsNegative(keys[middle]) && !GD.IsZeroApprox(keys[middle])) || (IsNegative(diff) && !GD.IsZeroApprox(diff)))
                {
                    GD.PushError("Found the key outside the animation range. Consider using the clean-up option in AnimationTrackEditor to fix it.");
                    return -1;
                }
            }
            return middle;
        }

        /// <summary>_find(keys, time) forward without limit, starting from a hint (the last result): the same answer as
        /// the binary search (the hint is only taken when no key is within is_equal_approx of the time).</summary>
        internal int FindHinted(Track t, double time, ref int hint)
        {
            int len = t.count;
            if (len == 0) return -2;
            int h = hint;
            if (h >= -1 && h < len)
            {
                if (Brackets(t, h, time)) return h;
                if (h + 1 < len && Brackets(t, h + 1, time)) { hint = h + 1; return h + 1; }
            }
            int r = Find(t, time);
            hint = r;
            return r;
        }

        static bool Brackets(Track t, int h, double time)
        {
            var k = t.times;
            if (h >= 0)
            {
                double kt = k[h];
                if (!(kt < time) || GD.IsEqualApprox(time, kt)) return false;
            }
            if (h + 1 < t.count)
            {
                double kt = k[h + 1];
                if (!(kt > time) || GD.IsEqualApprox(time, kt)) return false;
            }
            return true;
        }

        internal static bool IsNegative(double d) => BitConverter.DoubleToInt64Bits(d) < 0;

        int LenUpToLength(Track t)
        {
            if (t.lenVer != t.keyVersion || t.lenLength != _length)
            {
                t.lenValue = Find(t, _length) + 1;
                t.lenVer = t.keyVersion;
                t.lenLength = _length;
            }
            return t.lenValue;
        }

        // ------------------------------------------------------------------ interpolation (_interpolate)
        internal struct Plan
        {
            public int idx, next, pre, post;
            public float c, preT, toT, postT;
        }

        const int PLAN_FAIL = -1, PLAN_KEY = 0, PLAN_INTERP = 1;

        static float PingpongF(float v, float length)
        {
            if (length == 0.0f) return 0.0f;
            float x = (v - length) / (length * 2.0f);
            float fr = x - MathF.Floor(x);
            return MathF.Abs(fr * length * 2.0f - length);
        }

        static int RoundI(float v) => (int)MathF.Round(v, MidpointRounding.AwayFromZero);

        /// <summary>The key indices and weight _interpolate works with: PLAN_FAIL (no key), PLAN_KEY (return the key
        /// p.idx as is) or PLAN_INTERP (interpolate as `interp` says, p.c the weight).</summary>
        int MakePlan(Track t, double time, InterpolationType interp, bool loopWrap, bool backward, ref int hint, out Plan p)
        {
            p = default;
            int len = LenUpToLength(t);
            if (len <= 0) return PLAN_FAIL;
            if (len == 1) { p.idx = 0; return PLAN_KEY; }
            int idx = backward || hint < -1 ? Find(t, time, backward) : FindHinted(t, time, ref hint);
            if (idx == -2) return PLAN_FAIL;
            var k = t.times;
            double length = _length;
            int maxi = len - 1;
            bool isStartEdge = backward ? idx >= len : idx == -1;
            bool isEndEdge = backward ? idx == 0 : idx >= maxi;
            float c, delta = 0f, from = 0f;
            int pre = -1, next, post = -1;
            float preT = 0f, toT = 0f, postT = 0f;
            bool useCubic = interp == InterpolationType.Cubic || interp == InterpolationType.CubicAngle;

            if (!loopWrap || _loopMode == LoopModeEnum.None)
            {
                if (isStartEdge) idx = backward ? maxi : 0;
                next = GD.ClampInt(idx + (backward ? -1 : 1), 0, maxi);
                if (useCubic)
                {
                    pre = GD.ClampInt(idx + (backward ? 1 : -1), 0, maxi);
                    post = GD.ClampInt(idx + (backward ? -2 : 2), 0, maxi);
                }
            }
            else if (_loopMode == LoopModeEnum.Linear)
            {
                if (isStartEdge) idx = backward ? 0 : maxi;
                next = (int)GD.Posmod(idx + (backward ? -1 : 1), len);
                if (useCubic)
                {
                    pre = (int)GD.Posmod(idx + (backward ? 1 : -1), len);
                    post = (int)GD.Posmod(idx + (backward ? -2 : 2), len);
                }
                if (isStartEdge)
                {
                    if (!backward)
                    {
                        float endtime = (float)(length - k[idx]);
                        if (endtime < 0) endtime = 0;
                        delta = (float)(endtime + k[next]);
                        from = (float)(endtime + time);
                    }
                    else
                    {
                        float endtime = (float)k[idx];
                        if (endtime > length) endtime = (float)length;
                        delta = (float)(endtime + length - k[next]);
                        from = (float)(endtime + length - time);
                    }
                }
                else if (isEndEdge)
                {
                    if (!backward)
                    {
                        delta = (float)((length - k[idx]) + k[next]);
                        from = (float)(time - k[idx]);
                    }
                    else
                    {
                        delta = (float)(k[idx] + (length - k[next]));
                        from = (float)((length - time) - (length - k[idx]));
                    }
                }
            }
            else
            {
                if (isStartEdge) idx = backward ? len : -1;
                next = RoundI(PingpongF((float)(idx + (backward ? -1 : 1)) + 0.5f, (float)len) - 0.5f);
                if (useCubic)
                {
                    pre = RoundI(PingpongF((float)(idx + (backward ? 1 : -1)) + 0.5f, (float)len) - 0.5f);
                    post = RoundI(PingpongF((float)(idx + (backward ? -2 : 2)) + 0.5f, (float)len) - 0.5f);
                }
                idx = RoundI(PingpongF((float)idx + 0.5f, (float)len) - 0.5f);
                if (isStartEdge)
                {
                    if (!backward)
                    {
                        float endtime = (float)k[idx];
                        if (endtime < 0) endtime = 0;
                        delta = (float)(endtime + k[next]);
                        from = (float)(endtime + time);
                    }
                    else
                    {
                        float endtime = (float)(length - k[idx]);
                        if (endtime > length) endtime = (float)length;
                        delta = (float)(endtime + length - k[next]);
                        from = (float)(endtime + length - time);
                    }
                }
                else if (isEndEdge)
                {
                    if (!backward)
                    {
                        delta = (float)(length * 2.0 - k[idx] - k[next]);
                        from = (float)(time - k[idx]);
                    }
                    else
                    {
                        delta = (float)(k[idx] + k[next]);
                        from = (float)((length - time) - (length - k[idx]));
                    }
                }
            }

            if (!isStartEdge && !isEndEdge)
            {
                if (!backward)
                {
                    delta = (float)(k[next] - k[idx]);
                    from = (float)(time - k[idx]);
                }
                else
                {
                    delta = (float)((length - k[next]) - (length - k[idx]));
                    from = (float)((length - time) - (length - k[idx]));
                }
            }

            c = GD.IsZeroApproxF(delta) ? 0f : from / delta;
            p.idx = idx;
            float tr = t.transitions[idx];
            if (tr == 0) return PLAN_KEY;
            if (tr != 1.0f) c = (float)GD.Ease(c, tr);
            p.c = c;
            p.next = next;
            if (useCubic)
            {
                if (!loopWrap || _loopMode == LoopModeEnum.None)
                {
                    preT = (float)(k[pre] - k[idx]);
                    toT = (float)(k[next] - k[idx]);
                    postT = (float)(k[post] - k[idx]);
                }
                else if (_loopMode == LoopModeEnum.Linear)
                {
                    preT = (float)(pre > idx ? -length + k[pre] - k[idx] : k[pre] - k[idx]);
                    toT = (float)(next < idx ? length + k[next] - k[idx] : k[next] - k[idx]);
                    postT = (float)(next < idx || post <= idx ? length + k[post] - k[idx] : k[post] - k[idx]);
                }
                else
                {
                    preT = (float)(k[pre] - k[idx]);
                    toT = (float)(k[next] - k[idx]);
                    postT = (float)(k[post] - k[idx]);
                    if ((pre > idx && idx == next && post < next) || (pre < idx && idx == next && post > next))
                        preT = (float)(k[idx] - k[pre]);
                    else if (pre == idx)
                        preT = (float)(idx < next ? -k[idx] * 2.0 : (length - k[idx]) * 2.0);
                    if (idx == next)
                    {
                        toT = (float)(pre < idx ? (length - k[idx]) * 2.0 : -k[idx] * 2.0);
                        postT = (float)(k[next] - k[post] + toT);
                    }
                    else if (next == post)
                        postT = (float)(idx < next ? (length - k[next]) * 2.0 + toT : -k[next] * 2.0 + toT);
                }
                p.pre = pre;
                p.post = post;
                p.preT = preT;
                p.toT = toT;
                p.postT = postT;
            }
            return PLAN_INTERP;
        }

        internal bool InterpolateVec3(Track<Vec3> t, double time, bool backward, ref int hint, out Vec3 r)
        {
            int k = MakePlan(t, time, t.interpolation, t.loopWrap, backward, ref hint, out var p);
            var v = t.values;
            if (k == PLAN_FAIL) { r = Vec3.Zero; return false; }
            if (k == PLAN_KEY) { r = v[p.idx]; return true; }
            switch (t.interpolation)
            {
                case InterpolationType.Linear:
                case InterpolationType.LinearAngle:
                    r = v[p.idx].Lerp(v[p.next], p.c);
                    return true;
                case InterpolationType.Cubic:
                case InterpolationType.CubicAngle:
                    r = v[p.idx].CubicInterpolateInTime(v[p.next], v[p.pre], v[p.post], p.c, p.toT, p.preT, p.postT);
                    return true;
                default:
                    r = v[p.idx];
                    return true;
            }
        }

        internal bool InterpolateQuat(Track<Quat> t, double time, bool backward, ref int hint, out Quat r)
        {
            int k = MakePlan(t, time, t.interpolation, t.loopWrap, backward, ref hint, out var p);
            var v = t.values;
            if (k == PLAN_FAIL) { r = Quat.IDENTITY; return false; }
            if (k == PLAN_KEY) { r = v[p.idx]; return true; }
            switch (t.interpolation)
            {
                case InterpolationType.Linear:
                case InterpolationType.LinearAngle:
                    r = v[p.idx].Slerp(v[p.next], p.c);
                    return true;
                case InterpolationType.Cubic:
                case InterpolationType.CubicAngle:
                    r = v[p.idx].SphericalCubicInterpolateInTime(v[p.next], v[p.pre], v[p.post], p.c, p.toT, p.preT, p.postT);
                    return true;
                default:
                    r = v[p.idx];
                    return true;
            }
        }

        internal bool InterpolateFloat(Track<float> t, double time, bool backward, ref int hint, out float r)
        {
            int k = MakePlan(t, time, t.interpolation, t.loopWrap, backward, ref hint, out var p);
            var v = t.values;
            if (k == PLAN_FAIL) { r = 0; return false; }
            if (k == PLAN_KEY) { r = v[p.idx]; return true; }
            switch (t.interpolation)
            {
                case InterpolationType.Linear:
                    r = GD.LerpF(v[p.idx], v[p.next], p.c);
                    return true;
                case InterpolationType.LinearAngle:       // (through Variant: a float gets the angle lerp)
                    r = (float)AnimVar.InterpolateAngle((double)v[p.idx], (double)v[p.next], p.c).AsFloat();
                    return true;
                case InterpolationType.Cubic:
                    r = GD.CubicInterpolateInTimeF(v[p.idx], v[p.next], v[p.pre], v[p.post], p.c, p.toT, p.preT, p.postT);
                    return true;
                case InterpolationType.CubicAngle:
                    r = (float)AnimVar.CubicInterpolateAngleInTime((double)v[p.pre], (double)v[p.idx], (double)v[p.next], (double)v[p.post], p.c, p.preT, p.toT, p.postT).AsFloat();
                    return true;
                default:
                    r = v[p.idx];
                    return true;
            }
        }

        internal bool InterpolateValue(ValueTrack t, double time, InterpolationType interp, bool backward, ref int hint, out Var r)
        {
            int k = MakePlan(t, time, interp, t.loopWrap, backward, ref hint, out var p);
            var v = t.values;
            if (k == PLAN_FAIL) { r = Var.Nil; return false; }
            if (k == PLAN_KEY) { r = v[p.idx]; return true; }
            switch (interp)
            {
                case InterpolationType.Linear:
                    r = AnimVar.Interpolate(v[p.idx], v[p.next], p.c);
                    return true;
                case InterpolationType.LinearAngle:
                    r = AnimVar.InterpolateAngle(v[p.idx], v[p.next], p.c);
                    return true;
                case InterpolationType.Cubic:
                    r = AnimVar.CubicInterpolateInTime(v[p.pre], v[p.idx], v[p.next], v[p.post], p.c, p.preT, p.toT, p.postT);
                    return true;
                case InterpolationType.CubicAngle:
                    r = AnimVar.CubicInterpolateAngleInTime(v[p.pre], v[p.idx], v[p.next], v[p.post], p.c, p.preT, p.toT, p.postT);
                    return true;
                default:
                    r = v[p.idx];
                    return true;
            }
        }

        // ------------------------------------------------------------------ public interpolation API
        public Error TryPositionTrackInterpolate(int track, double time, out Vec3 r, bool backward = false)
        {
            r = Vec3.Zero;
            if (!TrackOk(track)) return Error.InvalidParameter;
            if (_tracks[track].type != TrackType.Position3D) return Error.InvalidParameter;
            int hint = -3;
            return InterpolateVec3((Track<Vec3>)_tracks[track], time, backward, ref hint, out r) ? Error.Ok : Error.Unavailable;
        }

        public Vec3 PositionTrackInterpolate(int track, double time, bool backward = false)
        {
            if (!TrackOk(track)) return Vec3.Zero;
            var e = TryPositionTrackInterpolate(track, time, out var r, backward);
            if (e != Error.Ok) { GD.PushError("3D Position Track: '" + _tracks[track].path + "' is unavailable."); return Vec3.Zero; }
            return r;
        }

        public Error TryRotationTrackInterpolate(int track, double time, out Quat r, bool backward = false)
        {
            r = Quat.IDENTITY;
            if (!TrackOk(track)) return Error.InvalidParameter;
            if (_tracks[track].type != TrackType.Rotation3D) return Error.InvalidParameter;
            int hint = -3;
            return InterpolateQuat((Track<Quat>)_tracks[track], time, backward, ref hint, out r) ? Error.Ok : Error.Unavailable;
        }

        public Quat RotationTrackInterpolate(int track, double time, bool backward = false)
        {
            if (!TrackOk(track)) return Quat.IDENTITY;
            var e = TryRotationTrackInterpolate(track, time, out var r, backward);
            if (e != Error.Ok) { GD.PushError("3D Rotation Track: '" + _tracks[track].path + "' is unavailable."); return Quat.IDENTITY; }
            return r;
        }

        public Error TryScaleTrackInterpolate(int track, double time, out Vec3 r, bool backward = false)
        {
            r = new Vec3(1f, 1f, 1f);
            if (!TrackOk(track)) return Error.InvalidParameter;
            if (_tracks[track].type != TrackType.Scale3D) return Error.InvalidParameter;
            int hint = -3;
            if (InterpolateVec3((Track<Vec3>)_tracks[track], time, backward, ref hint, out var v)) { r = v; return Error.Ok; }
            return Error.Unavailable;
        }

        public Vec3 ScaleTrackInterpolate(int track, double time, bool backward = false)
        {
            if (!TrackOk(track)) return new Vec3(1f, 1f, 1f);
            var e = TryScaleTrackInterpolate(track, time, out var r, backward);
            if (e != Error.Ok) { GD.PushError("3D Scale Track: '" + _tracks[track].path + "' is unavailable."); return new Vec3(1f, 1f, 1f); }
            return r;
        }

        public Error TryBlendShapeTrackInterpolate(int track, double time, out float r, bool backward = false)
        {
            r = 0;
            if (!TrackOk(track)) return Error.InvalidParameter;
            if (_tracks[track].type != TrackType.BlendShape) return Error.InvalidParameter;
            int hint = -3;
            return InterpolateFloat((Track<float>)_tracks[track], time, backward, ref hint, out r) ? Error.Ok : Error.Unavailable;
        }

        public double BlendShapeTrackInterpolate(int track, double time, bool backward = false)
        {
            if (!TrackOk(track)) return 0;
            var e = TryBlendShapeTrackInterpolate(track, time, out var r, backward);
            if (e != Error.Ok) { GD.PushError("Blend Shape Track: '" + _tracks[track].path + "' is unavailable."); return 0; }
            return r;
        }

        public Var ValueTrackInterpolate(int track, double time, bool backward = false)
        {
            if (!TrackOk(track)) return 0;
            if (!(_tracks[track] is ValueTrack vt)) { GD.PushError("Condition \"t->type != TYPE_VALUE\" is true."); return Var.Nil; }
            int hint = -3;
            return InterpolateValue(vt, time, vt.updateMode == UpdateMode.Discrete ? InterpolationType.Nearest : vt.interpolation, backward, ref hint, out var r) ? r : Var.Nil;
        }

        public void ValueTrackSetUpdateMode(int track, UpdateMode mode)
        {
            if (!TrackOk(track)) return;
            if (!(_tracks[track] is ValueTrack vt)) { GD.PushError("Condition \"t->type != TYPE_VALUE\" is true."); return; }
            vt.updateMode = mode;
            CheckCaptureIncluded();
            EmitChanged();
        }

        public UpdateMode ValueTrackGetUpdateMode(int track) => TrackOk(track) && _tracks[track] is ValueTrack vt ? vt.updateMode : UpdateMode.Continuous;

        public string MethodTrackGetName(int track, int key) =>
            TrackOk(track) && _tracks[track] is Track<MethodKey> m && (uint)key < (uint)m.count ? m.values[key].method : "";

        public Var[] MethodTrackGetParams(int track, int key) =>
            TrackOk(track) && _tracks[track] is Track<MethodKey> m && (uint)key < (uint)m.count ? m.values[key].args : Array.Empty<Var>();

        // bezier
        public int BezierTrackInsertKey(int track, double time, double value, Vec2 inHandle, Vec2 outHandle)
        {
            if (!TrackOk(track) || !(_tracks[track] is Track<BezierKey> bt)) return -1;
            var k = new BezierKey { value = (float)value, inHandle = inHandle, outHandle = outHandle };
            if (k.inHandle.x > 0) k.inHandle.x = 0;
            if (k.outHandle.x < 0) k.outHandle.x = 0;
            int r = bt.Insert(time, k, 1f);
            EmitChanged();
            return r;
        }

        public double BezierTrackGetKeyValue(int track, int key) => TrackOk(track) && _tracks[track] is Track<BezierKey> b && (uint)key < (uint)b.count ? b.values[key].value : 0;
        public Vec2 BezierTrackGetKeyInHandle(int track, int key) => TrackOk(track) && _tracks[track] is Track<BezierKey> b && (uint)key < (uint)b.count ? b.values[key].inHandle : Vec2.Zero;
        public Vec2 BezierTrackGetKeyOutHandle(int track, int key) => TrackOk(track) && _tracks[track] is Track<BezierKey> b && (uint)key < (uint)b.count ? b.values[key].outHandle : Vec2.Zero;

        public double BezierTrackInterpolate(int track, double time)
        {
            if (!TrackOk(track) || !(_tracks[track] is Track<BezierKey> bt)) return 0;
            int len = LenUpToLength(bt);
            if (len <= 0) return 0;
            if (len == 1) return bt.values[0].value;
            int idx = Find(bt, time);
            if (idx == -2) return 0;
            if (idx < 0) return bt.values[0].value;
            if (idx >= bt.count - 1) return bt.values[bt.count - 1].value;
            double tt = time - bt.times[idx];
            float duration = (float)(bt.times[idx + 1] - bt.times[idx]);
            float low = 0f, high = 1f;
            var start = new Vec2(0f, bt.values[idx].value);
            var startOut = start + bt.values[idx].outHandle;
            var end = new Vec2(duration, bt.values[idx + 1].value);
            var endIn = end + bt.values[idx + 1].inHandle;
            for (int i = 0; i < 10; i++)
            {
                float middle = (low + high) / 2;
                var ip = start.BezierInterpolate(startOut, endIn, end, middle);
                if (ip.x < tt) low = middle;
                else high = middle;
            }
            var lowPos = start.BezierInterpolate(startOut, endIn, end, low);
            var highPos = start.BezierInterpolate(startOut, endIn, end, high);
            float c = (float)((tt - lowPos.x) / (highPos.x - lowPos.x));
            return lowPos.Lerp(highPos, c).y;
        }

        // audio / animation tracks (data only: the port's mixer doesn't play them)
        public int AudioTrackInsertKey(int track, double time, Resource stream, double startOffset = 0, double endOffset = 0)
        {
            if (!TrackOk(track) || !(_tracks[track] is AudioTrack at)) return -1;
            int r = at.Insert(time, new AudioKey { stream = stream, startOffset = (float)Math.Max(0, startOffset), endOffset = (float)Math.Max(0, endOffset) }, 1f);
            EmitChanged();
            return r;
        }

        public Resource AudioTrackGetKeyStream(int track, int key) => TrackOk(track) && _tracks[track] is AudioTrack at && (uint)key < (uint)at.count ? at.values[key].stream : null;
        public double AudioTrackGetKeyStartOffset(int track, int key) => TrackOk(track) && _tracks[track] is AudioTrack at && (uint)key < (uint)at.count ? at.values[key].startOffset : 0;
        public double AudioTrackGetKeyEndOffset(int track, int key) => TrackOk(track) && _tracks[track] is AudioTrack at && (uint)key < (uint)at.count ? at.values[key].endOffset : 0;
        public void AudioTrackSetUseBlend(int track, bool on) { if (TrackOk(track) && _tracks[track] is AudioTrack at) { at.useBlend = on; EmitChanged(); } }
        public bool AudioTrackIsUseBlend(int track) => TrackOk(track) && _tracks[track] is AudioTrack at && at.useBlend;

        public int AnimationTrackInsertKey(int track, double time, string animation)
        {
            if (!TrackOk(track) || !(_tracks[track] is Track<string> an)) return -1;
            int r = an.Insert(time, animation ?? "", 1f);
            EmitChanged();
            return r;
        }

        public void AnimationTrackSetKeyAnimation(int track, int key, string animation)
        {
            if (TrackOk(track) && _tracks[track] is Track<string> an && (uint)key < (uint)an.count) { an.values[key] = animation ?? ""; EmitChanged(); }
        }

        public string AnimationTrackGetKeyAnimation(int track, int key) => TrackOk(track) && _tracks[track] is Track<string> an && (uint)key < (uint)an.count ? an.values[key] : "";

        // ------------------------------------------------------------------ keys in a time range (method / discrete tracks)
        static void KeyIndicesInRange(Track t, double fromTime, double toTime, List<int> r, bool backward)
        {
            int len = t.count;
            if (len == 0) return;
            var k = t.times;
            int from = 0, to = len - 1;
            if (!backward)
            {
                while (k[from] < fromTime || GD.IsEqualApprox(k[from], fromTime)) { from++; if (to < from) return; }
                while (k[to] > toTime && !GD.IsEqualApprox(k[to], toTime)) { to--; if (to < from) return; }
            }
            else
            {
                while (k[from] < fromTime && !GD.IsEqualApprox(k[from], fromTime)) { from++; if (to < from) return; }
                while (k[to] > toTime || GD.IsEqualApprox(k[to], toTime)) { to--; if (to < from) return; }
            }
            if (from == to) { r.Add(from); return; }
            if (!backward) for (int i = from; i <= to; i++) r.Add(i);
            else for (int i = to; i >= from; i--) r.Add(i);
        }

        public void TrackGetKeyIndicesInRange(int track, double time, double delta, double start, double end, List<int> indices, LoopedFlag loopedFlag = LoopedFlag.None)
        {
            if (!TrackOk(track)) return;
            if (delta == 0) return;
            var t = _tracks[track];
            double fromTime = time - delta, toTime = time;
            if (start < 0) start = 0;
            if (end > _length) end = _length;
            bool isBackward = false;
            if (fromTime > toTime) { isBackward = true; double x = fromTime; fromTime = toTime; toTime = x; }
            switch (_loopMode)
            {
                case LoopModeEnum.None:
                    if (fromTime < 0) fromTime = 0;
                    if (fromTime > end) fromTime = end;
                    if (toTime < 0) toTime = 0;
                    if (toTime > end) toTime = end;
                    break;
                case LoopModeEnum.Linear:
                    if (fromTime > end || fromTime < start) fromTime = GD.Fposmod(fromTime, end);
                    if (toTime > end || toTime < start) toTime = GD.Fposmod(toTime, end);
                    if (fromTime > toTime)
                    {
                        double animEnd = end + GD.CMP_EPSILON, animStart = start - GD.CMP_EPSILON;
                        if (!isBackward)
                        {
                            KeyIndicesInRange(t, fromTime, animEnd, indices, isBackward);
                            KeyIndicesInRange(t, animStart, toTime, indices, isBackward);
                        }
                        else
                        {
                            KeyIndicesInRange(t, animStart, toTime, indices, isBackward);
                            KeyIndicesInRange(t, fromTime, animEnd, indices, isBackward);
                        }
                        return;
                    }
                    if (loopedFlag != LoopedFlag.None)
                    {
                        if (!isBackward && GD.IsEqualApprox(fromTime, start))
                        {
                            int edge = TrackFindKey(track, start, FindMode.Exact);
                            if (edge >= 0) indices.Add(edge);
                        }
                        else if (isBackward && GD.IsEqualApprox(toTime, end))
                        {
                            int edge = TrackFindKey(track, end, FindMode.Exact);
                            if (edge >= 0) indices.Add(edge);
                        }
                    }
                    break;
                case LoopModeEnum.Pingpong:
                    if (fromTime > end || fromTime < start) fromTime = GD.Pingpong(fromTime, _length);
                    if (toTime > end || toTime < start) toTime = GD.Pingpong(toTime, _length);
                    if (loopedFlag == LoopedFlag.Start)
                    {
                        KeyIndicesInRange(t, start, fromTime, indices, true);
                        KeyIndicesInRange(t, start, toTime, indices, false);
                        return;
                    }
                    if (loopedFlag == LoopedFlag.End)
                    {
                        KeyIndicesInRange(t, fromTime, end, indices, false);
                        KeyIndicesInRange(t, toTime, end, indices, true);
                        return;
                    }
                    if (!isBackward && GD.IsEqualApprox(toTime, end)) toTime -= GD.CMP_EPSILON;
                    else if (isBackward && GD.IsEqualApprox(fromTime, start)) fromTime += GD.CMP_EPSILON;
                    break;
            }
            KeyIndicesInRange(t, fromTime, toTime, indices, isBackward);
        }

        // ------------------------------------------------------------------ markers
        int MarkerFind(double time)
        {
            int len = _markerNames.Count;
            if (len == 0) return -2;
            int low = 0, high = len - 1, middle = 0;
            while (low <= high)
            {
                middle = (low + high) / 2;
                if (GD.IsEqualApprox(time, _markerNames[middle].time)) return middle;
                if (time < _markerNames[middle].time) high = middle - 1;
                else low = middle + 1;
            }
            if (_markerNames[middle].time > time) middle--;
            return middle;
        }

        void MarkerInsert(double time, string name)
        {
            int idx = _markerNames.Count;
            while (true)
            {
                if (idx > 0 && GD.IsEqualApprox(_markerNames[idx - 1].time, time)) { _markerNames[idx - 1] = new MarkerKey { time = time, name = name }; return; }
                if (idx == 0 || _markerNames[idx - 1].time < time) { _markerNames.Insert(idx, new MarkerKey { time = time, name = name }); return; }
                idx--;
            }
        }

        public void AddMarker(string name, double time)
        {
            int idx = MarkerFind(time);
            if ((uint)idx < (uint)_markerNames.Count && GD.IsEqualApprox(time, _markerNames[idx].time))
            {
                _markerTimes.Remove(_markerNames[idx].name);
                _markerColors.Remove(_markerNames[idx].name);
                _markerNames[idx] = new MarkerKey { time = _markerNames[idx].time, name = name };
            }
            else MarkerInsert(time, name);
            _markerTimes[name] = time;
            _markerColors[name] = new Col(1f, 1f, 1f, 1f);
        }

        public void RemoveMarker(string name)
        {
            if (!_markerTimes.TryGetValue(name, out double t)) { GD.PushError("Condition \"!E\" is true."); return; }
            int idx = MarkerFind(t);
            if (!((uint)idx < (uint)_markerNames.Count && GD.IsEqualApprox(_markerNames[idx].time, t))) { GD.PushError("Condition \"!success\" is true."); return; }
            _markerNames.RemoveAt(idx);
            _markerTimes.Remove(name);
            _markerColors.Remove(name);
        }

        public bool HasMarker(string name) => name != null && _markerTimes.ContainsKey(name);
        public double GetMarkerTime(string name) => name != null && _markerTimes.TryGetValue(name, out double t) ? t : -1;

        public string GetMarkerAtTime(double time)
        {
            int idx = MarkerFind(time);
            return (uint)idx < (uint)_markerNames.Count && GD.IsEqualApprox(_markerNames[idx].time, time) ? _markerNames[idx].name : "";
        }

        public string GetNextMarker(double time)
        {
            int idx = MarkerFind(time);
            return idx >= -1 && idx < _markerNames.Count - 1 ? _markerNames[idx + 1].name : "";
        }

        public string GetPrevMarker(double time)
        {
            int idx = MarkerFind(time);
            return (uint)idx < (uint)_markerNames.Count ? _markerNames[idx].name : "";
        }

        public string[] GetMarkerNames()
        {
            var r = new string[_markerNames.Count];
            for (int i = 0; i < r.Length; i++) r[i] = _markerNames[i].name;
            return r;
        }

        public Col GetMarkerColor(string name) => name != null && _markerColors.TryGetValue(name, out var c) ? c : new Col(0f, 0f, 0f, 1f);
        public void SetMarkerColor(string name, Col c) => _markerColors[name] = c;

        // ------------------------------------------------------------------ helpers (static, as Godot's)
        public static bool IsLessOrEqualApprox(double a, double b) => a < b || GD.IsEqualApprox(a, b);
        public static bool IsLessApprox(double a, double b) => a < b && !GD.IsEqualApprox(a, b);
        public static bool IsGreaterOrEqualApprox(double a, double b) => a > b || GD.IsEqualApprox(a, b);
        public static bool IsGreaterApprox(double a, double b) => a > b && !GD.IsEqualApprox(a, b);

        /// <summary>interpolate_via_rest (angles): blends from p_from toward p_to by weight without crossing the rest's
        /// opposite angle.</summary>
        public static double InterpolateViaRest(double from, double to, double weight, double rest = 0.0)
        {
            double rotA = GD.Fposmod(from, GD.TAU), rotB = GD.Fposmod(to, GD.TAU), rotRest = GD.Fposmod(rest, GD.TAU);
            if (rotRest < GD.PI)
            {
                rotA = rotA > rotRest + GD.PI ? rotA - GD.TAU : rotA;
                rotB = rotB > rotRest + GD.PI ? rotB - GD.TAU : rotB;
            }
            else
            {
                rotA = rotA < rotRest - GD.PI ? rotA + GD.TAU : rotA;
                rotB = rotB < rotRest - GD.PI ? rotB + GD.TAU : rotB;
            }
            return GD.Fposmod(rotA + (rotB - rotRest) * weight, GD.TAU);
        }

        /// <summary>interpolate_via_rest (quaternions): from * IDENTITY.slerp(rest^-1 * to, weight), normalized.</summary>
        public static Quat InterpolateViaRest(Quat from, Quat to, float weight, Quat rest)
        {
            if (GD.MathChecks)
            {
                if (!from.IsNormalized()) { GD.PushError("The start quaternion must be normalized."); return Quat.IDENTITY; }
                if (!to.IsNormalized()) { GD.PushError("The end quaternion must be normalized."); return Quat.IDENTITY; }
                if (!rest.IsNormalized()) { GD.PushError("The rest quaternion must be normalized."); return Quat.IDENTITY; }
            }
            return (from * Quat.IDENTITY.Slerp(rest.Inverse() * to, weight)).Normalized();
        }
    }

    /// <summary>Godot's Variant helpers the animation code uses (Animation::interpolate_variant, blend_variant,
    /// add/subtract_variant, cast_to/from_blendwise, cubic_interpolate_in_time_variant, Variant::zero) for the value types
    /// value tracks carry here (bool, int, float, Vector2/3/4, Quaternion, Color, Basis, Transform3D, arrays of those);
    /// others fall back to Godot's "nearest" (c &lt; 0.5 ? a : b). Plus conversions from the stored formats.</summary>
    public static class AnimVar
    {
        // ---- conversions
        public static float[] ToReals(Var v)
        {
            switch (v.Obj)
            {
                case float[] f: return f;
                case double[] d: { var r = new float[d.Length]; for (int i = 0; i < d.Length; i++) r[i] = (float)d[i]; return r; }
                case int[] ia: { var r = new float[ia.Length]; for (int i = 0; i < ia.Length; i++) r[i] = ia[i]; return r; }
                case long[] la: { var r = new float[la.Length]; for (int i = 0; i < la.Length; i++) r[i] = la[i]; return r; }
                case List<float> lf: return lf.ToArray();
                case GArray a: { var r = new float[a.Size()]; for (int i = 0; i < a.Size(); i++) r[i] = (float)a[i].AsFloat(); return r; }
            }
            return null;
        }

        /// <summary>A key value as the port's own types (a decoded Quaternion/Basis/Transform3D/Color that arrived as a
        /// GValue becomes the C# struct).</summary>
        public static Var Normalize(Var v)
        {
            if (v.Obj is GValue g)
            {
                var c = g.C;
                switch (g.Type)
                {
                    case GD.TYPE_QUATERNION: return Var.Of(new Quat(c[0], c[1], c[2], c[3]));
                    case GD.TYPE_BASIS: return Var.Of(Basis.FromRows((float)c[0], (float)c[1], (float)c[2], (float)c[3], (float)c[4], (float)c[5], (float)c[6], (float)c[7], (float)c[8]));
                    case GD.TYPE_TRANSFORM3D: return Var.Of(ToXform3(v));
                    case GD.TYPE_COLOR: return Var.Of(new Col(c[0], c[1], c[2], c[3]));
                    case GD.TYPE_VECTOR4: return Var.Of(new Vec4((float)c[0], (float)c[1], (float)c[2], (float)c[3]));
                }
            }
            return v;
        }

        public static Vec3 ToVec3(Var v) => v.IsVec3 ? v.AsVec3() : v.Obj is Vec3i i ? new Vec3((float)i.x, (float)i.y, (float)i.z) : Vec3.Zero;

        public static bool IsQuatOrBasis(Var v)
        {
            var o = v.Obj;
            return o is Quat || o is Basis || (o is GValue g && (g.Type == GD.TYPE_QUATERNION || g.Type == GD.TYPE_BASIS));
        }

        public static Quat ToQuat(Var v)
        {
            switch (v.Obj)
            {
                case Quat q: return q;
                case Basis b: return b.GetQuaternion();
                case GValue g when g.Type == GD.TYPE_QUATERNION: return new Quat(g.C[0], g.C[1], g.C[2], g.C[3]);
                case GValue g when g.Type == GD.TYPE_BASIS: return ((Basis)Normalize(v).Obj).GetQuaternion();
            }
            return Quat.IDENTITY;
        }

        /// <summary>A Transform3D from a Var (Xform3, or a decoded GValue: basis by rows then origin).</summary>
        public static Xform3 ToXform3(Var v)
        {
            switch (v.Obj)
            {
                case Xform3 x: return x;
                case GValue g when g.Type == GD.TYPE_TRANSFORM3D:
                {
                    var c = g.C;
                    return new Xform3(Basis.FromRows((float)c[0], (float)c[1], (float)c[2], (float)c[3], (float)c[4], (float)c[5], (float)c[6], (float)c[7], (float)c[8]),
                        new Vec3((float)c[9], (float)c[10], (float)c[11]));
                }
            }
            return Xform3.IDENTITY;
        }

        static int T(Var v) => v.GodotType;

        public static bool IsVariantInterpolatable(Var v)
        {
            int t = T(v);
            return (t >= GD.TYPE_BOOL && t <= GD.TYPE_STRING_NAME) || t == GD.TYPE_ARRAY || t >= GD.TYPE_PACKED_INT32_ARRAY;
        }

        /// <summary>Variant::zero(): the type's zero (Quaternion(), Color() = black, identity Basis/Transform3D...).</summary>
        public static Var Zero(Var v)
        {
            switch (v.Type)
            {
                case VT.Nil: return v;
                case VT.Bool: return false;
                case VT.Int: return 0L;
                case VT.Float: return 0.0;
                case VT.Vec2: return Vec2.Zero;
                case VT.Vec2i: return new Vec2i(0, 0);
                case VT.Vec3: return Vec3.Zero;
                case VT.String: return "";
                case VT.Arr: return new GArray();
                case VT.Dict: return new GDict();
            }
            switch (v.Obj)
            {
                case Quat _: return Var.Of(Quat.IDENTITY);
                case Col _: return Var.Of(new Col(0f, 0f, 0f, 1f));
                case Vec4 _: return Var.Of(new Vec4(0f, 0f, 0f, 0f));
                case Vec3i _: return Var.Of(new Vec3i(0, 0, 0));
                case Basis _: return Var.Of(Basis.IDENTITY);
                case Xform3 _: return Var.Of(Xform3.IDENTITY);
            }
            return Var.Nil;
        }

        static bool IsArray(Var v) => v.Type == VT.Arr;

        public static Var CastToBlendwise(Var v)
        {
            switch (v.Type)
            {
                case VT.Bool: return v.Truthy ? 1.0 : 0.0;
                case VT.Int: return (double)v.AsLong();
                case VT.Vec2i: { var i = v.AsVec2i(); return new Vec2((float)i.x, (float)i.y); }
                case VT.String:
                {
                    var s = v.AsString();
                    var arr = new GArray();
                    foreach (var c in s) arr.Append((double)(float)c);
                    return arr;
                }
            }
            if (v.Obj is Vec3i i3) return new Vec3((float)i3.x, (float)i3.y, (float)i3.z);
            return v;
        }

        public static Var CastFromBlendwise(Var v, int type)
        {
            switch (type)
            {
                case GD.TYPE_BOOL: return (float)v.AsFloat() >= 0.5f;
                case GD.TYPE_INT: return (long)Math.Round(v.AsFloat(), MidpointRounding.AwayFromZero);
                case GD.TYPE_VECTOR2I: { var x = v.AsVec2(); return new Vec2i((int)MathF.Round(x.x, MidpointRounding.AwayFromZero), (int)MathF.Round(x.y, MidpointRounding.AwayFromZero)); }
                case GD.TYPE_VECTOR3I: { var x = v.AsVec3(); return Var.Of(new Vec3i((int)MathF.Round(x.x, MidpointRounding.AwayFromZero), (int)MathF.Round(x.y, MidpointRounding.AwayFromZero), (int)MathF.Round(x.z, MidpointRounding.AwayFromZero))); }
                case GD.TYPE_STRING:
                {
                    var a = v.AsArr();
                    if (a == null) return v;
                    var sb = new System.Text.StringBuilder();
                    foreach (var e in a)
                    {
                        int c = (int)MathF.Round((float)e.AsFloat(), MidpointRounding.AwayFromZero);
                        if (c == 0 || (c & 0xfffff800) == 0xd800 || c > 0x10ffff) c = ' ';
                        sb.Append(char.ConvertFromUtf32(c));
                    }
                    return sb.ToString();
                }
            }
            return v;
        }

        static bool Same(Var a, Var b) => T(a) == T(b);

        public static Var Add(Var a, Var b)
        {
            if (!Same(a, b))
            {
                if (a.IsNum && b.IsNum) return Add(CastToBlendwise(a), CastToBlendwise(b));
                if (!IsArray(a)) return a;
            }
            switch (a.Type)
            {
                case VT.Nil: return Var.Nil;
                case VT.Float: return a.AsFloat() + b.AsFloat();
                case VT.Vec2: return a.AsVec2() + b.AsVec2();
                case VT.Vec3: return a.AsVec3() + b.AsVec3();
                case VT.Int: case VT.Vec2i: return CastFromBlendwise(Add(CastToBlendwise(a), CastToBlendwise(b)), T(a));
                case VT.Bool: case VT.String: return b;
                case VT.Arr:
                    return ArrayOp(a.AsArr(), b.AsArr(), (x, y) => Add(x, y), 0f, false, true);
            }
            switch (a.Obj)
            {
                case Quat qa: return Var.Of(qa * (Quat)b.Obj);
                case Basis ba: return Var.Of(ba * (Basis)b.Obj);
                case Xform3 ta: return Var.Of(ta * (Xform3)b.Obj);
                case Col ca: return Var.Of(ca + (Col)b.Obj);
                case Vec4 va: return Var.Of(va + (Vec4)b.Obj);
                case Vec3i _: return CastFromBlendwise(Add(CastToBlendwise(a), CastToBlendwise(b)), T(a));
            }
            return a + b;
        }

        public static Var Subtract(Var a, Var b)
        {
            if (!Same(a, b))
            {
                if (a.IsNum && b.IsNum) return Subtract(CastToBlendwise(a), CastToBlendwise(b));
                if (!IsArray(a)) return a;
            }
            switch (a.Type)
            {
                case VT.Nil: return Var.Nil;
                case VT.Float: return a.AsFloat() - b.AsFloat();
                case VT.Vec2: return a.AsVec2() - b.AsVec2();
                case VT.Vec3: return a.AsVec3() - b.AsVec3();
                case VT.Int: case VT.Vec2i: return CastFromBlendwise(Subtract(CastToBlendwise(a), CastToBlendwise(b)), T(a));
                case VT.Bool: case VT.String: return a;
                case VT.Arr:
                    return ArrayOp(a.AsArr(), b.AsArr(), (x, y) => Subtract(x, y), 0f, false, true);
            }
            switch (a.Obj)
            {
                case Quat qa: return Var.Of(((Quat)b.Obj).Inverse() * qa);
                case Basis ba: return Var.Of(((Basis)b.Obj).Inverse() * ba);
                case Xform3 ta: return Var.Of(((Xform3)b.Obj).AffineInverse() * ta);
                case Col ca: return Var.Of(ca - (Col)b.Obj);
                case Vec4 va: return Var.Of(va - (Vec4)b.Obj);
                case Vec3i _: return CastFromBlendwise(Subtract(CastToBlendwise(a), CastToBlendwise(b)), T(a));
            }
            return a - b;
        }

        public static Var Blend(Var a, Var b, float c)
        {
            if (!Same(a, b))
            {
                if (a.IsNum && b.IsNum) return Blend(CastToBlendwise(a), CastToBlendwise(b), c);
                if (!IsArray(a)) return a;
            }
            switch (a.Type)
            {
                case VT.Nil: return Var.Nil;
                case VT.Float: return a.AsFloat() + b.AsFloat() * c;
                case VT.Vec2: return a.AsVec2() + b.AsVec2() * c;
                case VT.Vec3: return a.AsVec3() + b.AsVec3() * c;
                case VT.Bool: case VT.Int: case VT.Vec2i: return CastFromBlendwise(Blend(CastToBlendwise(a), CastToBlendwise(b), c), T(a));
                case VT.Arr:
                    return ArrayOp(a.AsArr(), b.AsArr(), (x, y) => Blend(x, y, c), c, false, false);
            }
            switch (a.Obj)
            {
                case Quat qa: return Var.Of(qa * Quat.IDENTITY.Slerp((Quat)b.Obj, c));
                case Basis ba: return Var.Of(ba + ((Basis)b.Obj) * c);
                case Xform3 ta: return Var.Of(ta * Xform3.IDENTITY.InterpolateWith((Xform3)b.Obj, c));
                case Col ca: return Var.Of(ca + ((Col)b.Obj) * c);
                case Vec4 va: return Var.Of(va + ((Vec4)b.Obj) * c);
                case Vec3i _: return CastFromBlendwise(Blend(CastToBlendwise(a), CastToBlendwise(b), c), T(a));
            }
            return c < 0.5 ? a : b;
        }

        public static Var Interpolate(Var a, Var b, float c)
        {
            if (!Same(a, b))
            {
                if (a.IsNum && b.IsNum) return Interpolate(CastToBlendwise(a), CastToBlendwise(b), c);
                if (!IsArray(a)) return a;
            }
            switch (a.Type)
            {
                case VT.Nil: return Var.Nil;
                case VT.Float: { double x = a.AsFloat(); return x + (b.AsFloat() - x) * (double)c; }
                case VT.Vec2: return a.AsVec2().Lerp(b.AsVec2(), c);
                case VT.Vec3: return a.AsVec3().Lerp(b.AsVec3(), c);
                case VT.Bool: case VT.Int: case VT.Vec2i: return CastFromBlendwise(Interpolate(CastToBlendwise(a), CastToBlendwise(b), c), T(a));
                case VT.Arr:
                    return ArrayOp(a.AsArr(), b.AsArr(), (x, y) => Interpolate(x, y, c), c, false, false);
            }
            switch (a.Obj)
            {
                case Quat qa: return Var.Of(qa.Slerp((Quat)b.Obj, c));
                case Basis ba: return Var.Of(ba.Lerp((Basis)b.Obj, c));
                case Xform3 ta: return Var.Of(ta.InterpolateWith((Xform3)b.Obj, c));
                case Col ca: return Var.Of(ca.Lerp((Col)b.Obj, c));
                case Vec4 va: return Var.Of(va.Lerp((Vec4)b.Obj, c));
                case Vec3i _: return CastFromBlendwise(Interpolate(CastToBlendwise(a), CastToBlendwise(b), c), T(a));
            }
            return c < 0.5 ? a : b;
        }

        // (the array cases: element by element, the shorter array's last element standing in past its end)
        static Var ArrayOp(GArray a, GArray b, Func<Var, Var, Var> op, float c, bool unused, bool always)
        {
            int min = a.Size(), max = b.Size();
            bool aLarger = false;
            if (min > max) { int x = min; min = max; max = x; aLarger = true; }
            var r = new GArray();
            int i = 0;
            for (; i < min; i++) r.Append(op(a[i], b[i]));
            if (min != max && (always || (aLarger ? !GD.IsEqualApproxF(c, 1.0f) : !GD.IsZeroApproxF(c))))
            {
                if (aLarger)
                {
                    Var last = i > 0 ? b[i - 1] : Zero(a[i]);
                    for (; i < max; i++) r.Append(op(a[i], last));
                }
                else
                {
                    Var last = i > 0 ? a[i - 1] : Zero(b[i]);
                    for (; i < max; i++) r.Append(op(last, b[i]));
                }
            }
            return r;
        }

        public static Var InterpolateAngle(Var a, Var b, float c)
        {
            int ta = T(a), tb = T(b);
            uint f = (1u << ta) | (1u << tb);
            if (f == ((1u << GD.TYPE_INT) | (1u << GD.TYPE_FLOAT)) || f == (1u << GD.TYPE_FLOAT))
            {
                float x = (float)a.AsFloat(), y = (float)b.AsFloat();
                return (double)GD.FposmodF(GD.LerpAngleF(x, y, c), (float)GD.TAU);
            }
            return Interpolate(a, b, c);
        }

        static double CubicInTime(double from, double to, double pre, double post, double w, double toT, double preT, double postT)
        {
            double t = GD.Lerp(0.0, toT, w);
            double a1 = GD.Lerp(pre, from, preT == 0 ? 0.0 : (t - preT) / -preT);
            double a2 = GD.Lerp(from, to, toT == 0 ? 0.5 : t / toT);
            double a3 = GD.Lerp(to, post, postT - toT == 0 ? 1.0 : (t - toT) / (postT - toT));
            double b1 = GD.Lerp(a1, a2, toT - preT == 0 ? 0.0 : (t - preT) / (toT - preT));
            double b2 = GD.Lerp(a2, a3, postT == 0 ? 1.0 : t / postT);
            return GD.Lerp(b1, b2, toT == 0 ? 0.5 : t / toT);
        }

        /// <summary>cubic_interpolate_in_time_variant(pre_a, a, b, post_b, c, pre_a_t, b_t, post_b_t).</summary>
        public static Var CubicInterpolateInTime(Var preA, Var a, Var b, Var postB, float c, float preAT, float bT, float postBT)
        {
            if (T(preA) != T(a) || T(preA) != T(b) || T(preA) != T(postB))
            {
                if (preA.IsNum && a.IsNum && b.IsNum && postB.IsNum)
                    return CubicInterpolateInTime(CastToBlendwise(preA), CastToBlendwise(a), CastToBlendwise(b), CastToBlendwise(postB), c, preAT, bT, postBT);
                if (!IsArray(a)) return a;
            }
            switch (a.Type)
            {
                case VT.Nil: return Var.Nil;
                case VT.Float: return CubicInTime(a.AsFloat(), b.AsFloat(), preA.AsFloat(), postB.AsFloat(), c, bT, preAT, postBT);
                case VT.Vec2: return a.AsVec2().CubicInterpolateInTime(b.AsVec2(), preA.AsVec2(), postB.AsVec2(), c, bT, preAT, postBT);
                case VT.Vec3: return a.AsVec3().CubicInterpolateInTime(b.AsVec3(), preA.AsVec3(), postB.AsVec3(), c, bT, preAT, postBT);
                case VT.Bool: case VT.Int: case VT.Vec2i:
                    return CastFromBlendwise(CubicInterpolateInTime(CastToBlendwise(preA), CastToBlendwise(a), CastToBlendwise(b), CastToBlendwise(postB), c, preAT, bT, postBT), T(a));
                case VT.String: return Interpolate(a, b, c);
            }
            switch (a.Obj)
            {
                case Quat qa: return Var.Of(qa.SphericalCubicInterpolateInTime((Quat)b.Obj, (Quat)preA.Obj, (Quat)postB.Obj, c, bT, preAT, postBT));
                case Vec4 va: return Var.Of(va.CubicInterpolateInTime((Vec4)b.Obj, (Vec4)preA.Obj, (Vec4)postB.Obj, c, bT, preAT, postBT));
                case Col ca:
                {
                    Col cb = (Col)b.Obj, cpa = (Col)preA.Obj, cpb = (Col)postB.Obj;
                    return Var.Of(new Col(CubicInTime(ca.r, cb.r, cpa.r, cpb.r, c, bT, preAT, postBT), CubicInTime(ca.g, cb.g, cpa.g, cpb.g, c, bT, preAT, postBT),
                        CubicInTime(ca.b, cb.b, cpa.b, cpb.b, c, bT, preAT, postBT), CubicInTime(ca.a, cb.a, cpa.a, cpb.a, c, bT, preAT, postBT)));
                }
                case Basis ba:
                {
                    Basis bb = (Basis)b.Obj, bpa = (Basis)preA.Obj, bpb = (Basis)postB.Obj;
                    Basis r;
                    r.row0 = ba.row0.CubicInterpolateInTime(bb.row0, bpa.row0, bpb.row0, c, bT, preAT, postBT);
                    r.row1 = ba.row1.CubicInterpolateInTime(bb.row1, bpa.row1, bpb.row1, c, bT, preAT, postBT);
                    r.row2 = ba.row2.CubicInterpolateInTime(bb.row2, bpa.row2, bpb.row2, c, bT, preAT, postBT);
                    return Var.Of(r);
                }
                case Xform3 ta:
                {
                    Xform3 tb = (Xform3)b.Obj, tpa = (Xform3)preA.Obj, tpb = (Xform3)postB.Obj;
                    Basis r;
                    r.row0 = ta.basis.row0.CubicInterpolateInTime(tb.basis.row0, tpa.basis.row0, tpb.basis.row0, c, bT, preAT, postBT);
                    r.row1 = ta.basis.row1.CubicInterpolateInTime(tb.basis.row1, tpa.basis.row1, tpb.basis.row1, c, bT, preAT, postBT);
                    r.row2 = ta.basis.row2.CubicInterpolateInTime(tb.basis.row2, tpa.basis.row2, tpb.basis.row2, c, bT, preAT, postBT);
                    return Var.Of(new Xform3(r, ta.origin.CubicInterpolateInTime(tb.origin, tpa.origin, tpb.origin, c, bT, preAT, postBT)));
                }
            }
            if (IsArray(a))
            {
                var pa = preA.AsArr() ?? new GArray();
                var aa = a.AsArr();
                var ab = b.AsArr() ?? new GArray();
                var pb = postB.AsArr() ?? new GArray();
                int min = aa.Size(), max = ab.Size();
                bool aLarger = false;
                if (min > max) { int x = min; min = max; max = x; aLarger = true; }
                var res = new GArray();
                if (min == 0 && max == 0) return res;
                Var vz = Zero(aLarger ? aa[0] : ab[0]);
                Var preLast = pa.Size() > 0 ? pa[pa.Size() - 1] : vz;
                Var postLast = pb.Size() > 0 ? pb[pb.Size() - 1] : vz;
                int i = 0;
                for (; i < min; i++) res.Append(CubicInterpolateInTime(i >= pa.Size() ? preLast : pa[i], aa[i], ab[i], i >= pb.Size() ? postLast : pb[i], c, preAT, bT, postBT));
                if (min != max)
                {
                    Var lesserLast = vz;
                    if (aLarger && !GD.IsEqualApproxF(c, 1.0f))
                    {
                        if (i > 0) lesserLast = ab[i - 1];
                        for (; i < max; i++) res.Append(CubicInterpolateInTime(i >= pa.Size() ? preLast : pa[i], aa[i], lesserLast, i >= pb.Size() ? postLast : pb[i], c, preAT, bT, postBT));
                    }
                    else if (!aLarger && !GD.IsZeroApproxF(c))
                    {
                        if (i > 0) lesserLast = aa[i - 1];
                        for (; i < max; i++) res.Append(CubicInterpolateInTime(i >= pa.Size() ? preLast : pa[i], lesserLast, ab[i], i >= pb.Size() ? postLast : pb[i], c, preAT, bT, postBT));
                    }
                }
                return res;
            }
            return c < 0.5 ? a : b;
        }

        public static Var CubicInterpolateAngleInTime(Var preA, Var a, Var b, Var postB, float c, float preAT, float bT, float postBT)
        {
            uint f = (1u << T(a)) | (1u << T(b)) | (1u << T(preA)) | (1u << T(postB));
            if (f == ((1u << GD.TYPE_INT) | (1u << GD.TYPE_FLOAT)) || f == (1u << GD.TYPE_FLOAT))
            {
                float fa = (float)a.AsFloat(), fb = (float)b.AsFloat(), pa = (float)preA.AsFloat(), pb = (float)postB.AsFloat();
                float tau = (float)GD.TAU;
                float fromRot = fa % tau;
                float preDiff = (pa - fromRot) % tau;
                float preRot = fromRot + (2.0f * preDiff) % tau - preDiff;
                float toDiff = (fb - fromRot) % tau;
                float toRot = fromRot + (2.0f * toDiff) % tau - toDiff;
                float postDiff = (pb - toRot) % tau;
                float postRot = toRot + (2.0f * postDiff) % tau - postDiff;
                float r = GD.CubicInterpolateInTimeF(fromRot, toRot, preRot, postRot, c, bT, preAT, postBT);
                return (double)GD.FposmodF(r, tau);
            }
            return CubicInterpolateInTime(preA, a, b, postB, c, preAT, bT, postBT);
        }
    }
}

#endif
