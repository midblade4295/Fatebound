#if FB3D
// Godot's AnimationPlayer (scene/animation/animation_player.cpp, 4.7) on the ported AnimationMixer: play / play_backwards
// / play_section(_with_markers) with custom blend and speed, the cross-fade from the previous animation(s) (each blend's
// weight runs down over its blend time at speed_scale), queue, pause, stop(keep_state), seek(update), speed_scale,
// default and per-pair blend times, animation_set_next, autoplay, loop handling (linear, ping-pong) and the end of a
// non-looping animation (animation_finished, the queue's next, current_animation_changed). Process modes, track
// application and caches: AnimationMixer.cs.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public class AnimationPlayer : AnimationMixer
    {
        struct PlaybackData
        {
            public bool isEnabled;
            public string animationName;
            public double animationLength, pos;
            public float speedScale;
            public double startTime, endTime;

            public double GetStartTime()
            {
                if (isEnabled && (Animation.IsLessApprox(startTime, 0) || Animation.IsGreaterApprox(startTime, animationLength))) return 0;
                return startTime;
            }

            public double GetEndTime()
            {
                if (isEnabled && (Animation.IsLessApprox(endTime, 0) || Animation.IsGreaterApprox(endTime, animationLength))) return animationLength;
                return endTime;
            }
        }

        struct Blend
        {
            public PlaybackData data;
            public double blendTime, blendLeft;
        }

        readonly Dictionary<string, string> _animationNextSet = new Dictionary<string, string>(StringComparer.Ordinal);
        string _finishedAnim = "";
        float _speedScale = 1f;
        double _defaultBlendTime;
        bool _autoCapture = true;
        double _autoCaptureDuration = -1.0;
        public int AutoCaptureTransitionType, AutoCaptureEaseType;

        PlaybackData _current = new PlaybackData { animationName = "", speedScale = 1f };
        string _assigned = "";
        bool _seeked, _internalSeeked, _started;
        Blend[] _blend = new Blend[4];
        int _blendCount;
        readonly List<int> _toErase = new List<int>();

        readonly Dictionary<(string, string), double> _blendTimes = new Dictionary<(string, string), double>();
        readonly List<string> _queue = new List<string>();
        Animation _tmpFrom;
        bool _endReached, _endNotify;
        string _autoplay = "";
        bool _movieQuitOnFinish;
        bool _playing;

        /// <summary>animation_changed(old_name, new_name): the queue moved on to its next animation.</summary>
        public event Action<string, string> AnimationChanged;
        public event Action<string> CurrentAnimationChanged;

        // ------------------------------------------------------------------ playback data
        void ProcessPlaybackData(ref PlaybackData cd, double pDelta, float pBlend, bool pSeeked, bool pInternalSeeked, bool pStarted, bool isCurrent = false)
        {
            double speed = _speedScale * cd.speedScale;
            bool backwards = Animation.IsNegative(speed);
            double delta = pStarted ? 0 : pDelta * speed;
            double nextPos = cd.pos + delta;
            double start = cd.GetStartTime(), end = cd.GetEndTime();
            if (!animationSet.TryGetValue(cd.animationName ?? "", out var from) || from.animation == null) return;
            var looped = Animation.LoopedFlag.None;
            switch (from.animation.LoopMode)
            {
                case Animation.LoopModeEnum.None:
                    if (Animation.IsLessApprox(nextPos, start)) nextPos = start;
                    else if (Animation.IsGreaterApprox(nextPos, end)) nextPos = end;
                    delta = nextPos - cd.pos;
                    break;
                case Animation.LoopModeEnum.Linear:
                    if (Animation.IsLessApprox(nextPos, start) && Animation.IsGreaterOrEqualApprox(cd.pos, start)) looped = Animation.LoopedFlag.Start;
                    if (Animation.IsGreaterApprox(nextPos, end) && Animation.IsLessOrEqualApprox(cd.pos, end)) looped = Animation.LoopedFlag.End;
                    nextPos = GD.Fposmod(nextPos - start, end - start) + start;
                    break;
                case Animation.LoopModeEnum.Pingpong:
                    if (Animation.IsLessApprox(nextPos, start) && Animation.IsGreaterOrEqualApprox(cd.pos, start))
                    {
                        cd.speedScale = (float)(cd.speedScale * -1.0);
                        looped = Animation.LoopedFlag.Start;
                    }
                    if (Animation.IsGreaterApprox(nextPos, end) && Animation.IsLessOrEqualApprox(cd.pos, end))
                    {
                        cd.speedScale = (float)(cd.speedScale * -1.0);
                        looped = Animation.LoopedFlag.End;
                    }
                    nextPos = GD.Pingpong(nextPos - start, end - start) + start;
                    break;
            }
            double prevPos = cd.pos;
            if (isCurrent && from.animation.LoopMode == Animation.LoopModeEnum.None)
            {
                if (!backwards && Animation.IsLessOrEqualApprox(prevPos, end) && GD.IsEqualApprox(nextPos, end))
                {
                    nextPos = end;
                    _endReached = true;
                    _endNotify = Animation.IsLessApprox(prevPos, end);
                    pBlend = 1.0f;
                }
                if (backwards && Animation.IsGreaterOrEqualApprox(prevPos, start) && GD.IsEqualApprox(nextPos, start))
                {
                    nextPos = start;
                    _endReached = true;
                    _endNotify = Animation.IsGreaterApprox(prevPos, start);
                    pBlend = 1.0f;
                }
            }
            cd.pos = nextPos;
            var pi = new PlaybackInfo();
            if (pStarted)
            {
                pi.time = prevPos;
                pi.delta = 0;
                pi.start = start;
                pi.end = end;
                pi.seeked = true;
            }
            else
            {
                pi.time = nextPos;
                pi.delta = delta;
                pi.start = start;
                pi.end = end;
                pi.seeked = pSeeked;
            }
            if (GD.IsZeroApprox(pi.delta) && backwards) pi.delta = -0.0;
            pi.isExternalSeeking = !pInternalSeeked && !pStarted;
            pi.loopedFlag = looped;
            pi.weight = pBlend;
            MakeAnimationInstance(cd.animationName, pi);
        }

        float GetCurrentBlendAmount()
        {
            float blend = 1.0f;
            for (int i = 0; i < _blendCount; i++) blend = (float)(blend - _blend[i].blendLeft);
            return 0 > blend ? 0 : blend;
        }

        void BlendPlaybackData(double pDelta, bool pStarted)
        {
            bool seeked = _seeked, internalSeeked = _internalSeeked;
            if (!GD.IsZeroApprox(pDelta))
            {
                _seeked = false;
                _internalSeeked = false;
            }
            ProcessPlaybackData(ref _current, pDelta, GetCurrentBlendAmount(), seeked, internalSeeked, pStarted, true);
            if (_endReached)
            {
                _blendCount = 0;
                if (_endNotify) _finishedAnim = _assigned;
                return;
            }
            _toErase.Clear();
            for (int i = 0; i < _blendCount; i++)
            {
                ref Blend b = ref _blend[i];
                double left = b.blendLeft - Math.Abs(_speedScale * pDelta) / b.blendTime;
                b.blendLeft = 0 > left ? 0 : left;
                if (Animation.IsLessOrEqualApprox(b.blendLeft, 0))
                {
                    _toErase.Add(i);
                    b.blendLeft = GD.CMP_EPSILON;
                }
                ProcessPlaybackData(ref b.data, pDelta, (float)b.blendLeft, false, false, false);
            }
            for (int i = _toErase.Count - 1; i >= 0; i--) RemoveBlendAt(_toErase[i]);
        }

        void RemoveBlendAt(int i)
        {
            for (int j = i; j < _blendCount - 1; j++) _blend[j] = _blend[j + 1];
            _blendCount--;
            _blend[_blendCount] = default;
        }

        void PushBlend(Blend b)
        {
            if (_blendCount == _blend.Length) Array.Resize(ref _blend, _blend.Length * 2);
            _blend[_blendCount++] = b;
        }

        protected override bool BlendPreProcess(double delta, int trackCount)
        {
            if (!_current.isEnabled)
            {
                SetMixerProcess(false);
                return false;
            }
            if (!animationSet.TryGetValue(_current.animationName ?? "", out var from)) return false;
            _tmpFrom = from.animation;
            _endReached = false;
            _endNotify = false;
            _finishedAnim = "";
            bool started = _started;
            if (_started) _started = false;
            string prev = _current.animationName;
            BlendPlaybackData(delta, started);
            if (prev != _current.animationName) return false;
            return true;
        }

        protected override void BlendPostProcess()
        {
            if (_endReached)
            {
                if (animationSet.TryGetValue(_current.animationName ?? "", out var cur) && _tmpFrom == cur.animation)
                {
                    if (_queue.Count > 0)
                    {
                        if (_finishedAnim.Length > 0)
                        {
                            EmitAnimationFinished(_finishedAnim);
                            if (_queue.Count == 0)
                            {
                                _endReached = false;
                                _endNotify = false;
                                _tmpFrom = null;
                                return;
                            }
                        }
                        string old = _assigned;
                        Play(_queue[0]);
                        string nw = _assigned;
                        if (_queue.Count > 0) _queue.RemoveAt(0);
                        if (_endNotify) AnimationChanged?.Invoke(old, nw);
                    }
                    else
                    {
                        ClearCaches();
                        _playing = false;
                        SetMixerProcess(false);
                        if (_endNotify)
                        {
                            if (_finishedAnim.Length > 0) EmitAnimationFinished(_finishedAnim);
                            CurrentAnimationChanged?.Invoke("");
                        }
                    }
                }
                _endReached = false;
                _endNotify = false;
            }
            _tmpFrom = null;
        }

        // ------------------------------------------------------------------ queue
        public void Queue(string name)
        {
            if (!IsPlaying()) Play(name);
            else _queue.Add(name);
        }

        public string[] GetQueue() => _queue.ToArray();
        public void ClearQueue() => _queue.Clear();

        // ------------------------------------------------------------------ play
        public void PlayBackwards(string name = "", double customBlend = -1) => Play(name, customBlend, -1, true);
        public void PlaySectionWithMarkersBackwards(string name = "", string startMarker = "", string endMarker = "", double customBlend = -1) =>
            PlaySectionWithMarkers(name, startMarker, endMarker, customBlend, -1, true);
        public void PlaySectionBackwards(string name = "", double startTime = -1, double endTime = -1, double customBlend = -1) =>
            PlaySection(name, startTime, endTime, customBlend, -1, true);

        /// <summary>play(name = "", custom_blend = -1, custom_speed = 1.0, from_end = false).</summary>
        public void Play(string name = "", double customBlend = -1, double customSpeed = 1.0, bool fromEnd = false)
        {
            if (_autoCapture) PlayWithCapture(name, _autoCaptureDuration, customBlend, customSpeed, fromEnd);
            else PlayInternal(name, customBlend, customSpeed, fromEnd);
        }

        void PlayInternal(string name, double customBlend, double customSpeed, bool fromEnd) =>
            PlaySectionWithMarkers(name, "", "", customBlend, customSpeed, fromEnd);

        public void PlaySectionWithMarkers(string name = "", string startMarker = "", string endMarker = "", double customBlend = -1, double customSpeed = 1.0, bool fromEnd = false)
        {
            name ??= "";
            startMarker ??= "";
            endMarker ??= "";
            string n = name.Length == 0 ? _assigned : name;
            if (!animationSet.TryGetValue(n, out var ad)) { GD.PushError("Animation not found: " + n + "."); return; }
            var animation = ad.animation;
            if (startMarker == endMarker && startMarker.Length > 0) { GD.PushError("Start marker and end marker cannot be the same marker: " + startMarker + "."); return; }
            if (startMarker.Length > 0 && !animation.HasMarker(startMarker)) { GD.PushError("Marker " + startMarker + " not found in animation: " + n + "."); return; }
            if (endMarker.Length > 0 && !animation.HasMarker(endMarker)) { GD.PushError("Marker " + endMarker + " not found in animation: " + n + "."); return; }
            double startTime = startMarker.Length > 0 ? animation.GetMarkerTime(startMarker) : -1;
            double endTime = endMarker.Length > 0 ? animation.GetMarkerTime(endMarker) : -1;
            if (startMarker.Length > 0 && endMarker.Length > 0 && Animation.IsGreaterApprox(startTime, endTime))
            {
                GD.PushError("End marker " + endMarker + " is placed earlier than start marker " + startMarker + " in animation: " + n + ".");
                return;
            }
            PlaySection(n, startTime, endTime, customBlend, customSpeed, fromEnd);
        }

        public void PlaySection(string name = "", double startTime = -1, double endTime = -1, double customBlend = -1, double customSpeed = 1.0, bool fromEnd = false)
        {
            string pName = name ?? "";
            string n = pName.Length == 0 ? _assigned : pName;
            if (!animationSet.TryGetValue(n, out var ad)) { GD.PushError("Animation not found: " + n + "."); return; }
            if (startTime >= 0 && endTime >= 0 && GD.IsEqualApprox(startTime, endTime)) { GD.PushError("Start time and end time must not equal to each other."); return; }
            if (startTime >= 0 && endTime >= 0 && Animation.IsGreaterApprox(startTime, endTime)) { GD.PushError("Start time " + startTime + " is greater than end time " + endTime + "."); return; }

            if (_current.isEnabled)
            {
                double blendTime = 0.0;
                string fromName = _current.animationName;
                if (Animation.IsGreaterOrEqualApprox(customBlend, 0)) blendTime = customBlend;
                else if (_blendTimes.TryGetValue((fromName, n), out double bt)) blendTime = bt;
                else if (_blendTimes.TryGetValue(("*", n), out bt)) blendTime = bt;
                else if (_blendTimes.TryGetValue((fromName, "*"), out bt)) blendTime = bt;
                if (Animation.IsLessApprox(customBlend, 0) && GD.IsZeroApprox(blendTime) && _defaultBlendTime != 0) blendTime = _defaultBlendTime;
                if (Animation.IsGreaterApprox(blendTime, 0))
                    PushBlend(new Blend { data = _current, blendLeft = GetCurrentBlendAmount(), blendTime = blendTime });
                else _blendCount = 0;
            }

            _current.isEnabled = true;
            _current.animationName = n;
            _current.animationLength = ad.animation.Length;
            _current.speedScale = (float)customSpeed;
            _current.startTime = startTime;
            _current.endTime = endTime;
            double start = _current.GetStartTime(), end = _current.GetEndTime();
            if (!_endReached) _queue.Clear();
            if (_assigned != n)
            {
                _current.pos = fromEnd ? end : start;
                _assigned = n;
                CurrentAnimationChanged?.Invoke(_assigned);
            }
            else
            {
                if (fromEnd && Animation.IsLessOrEqualApprox(_current.pos, start)) SeekInternal(end, true, true, true);
                else if (!fromEnd && Animation.IsGreaterOrEqualApprox(_current.pos, end)) SeekInternal(start, true, true, true);
                else if (_playing) return;
            }
            _seeked = false;
            _started = true;
            SetMixerProcess(true);
            _playing = true;
            EmitAnimationStarted(_assigned);
            string next = AnimationGetNext(pName);
            if (next.Length > 0 && animationSet.ContainsKey(next)) Queue(next);
        }

        /// <summary>play_with_capture: capture isn't ported (an animation with UPDATE_CAPTURE tracks plays without it).</summary>
        public void PlayWithCapture(string name = "", double duration = -1.0, double customBlend = -1, double customSpeed = 1.0, bool fromEnd = false, int transType = 0, int easeType = 0)
        {
            string n = string.IsNullOrEmpty(name) ? _assigned : name;
            var anim = GetAnimationOrNull(n);
            if (anim != null && anim.IsCaptureIncluded()) GD.PushWarning("AnimationPlayer: capture (UPDATE_CAPTURE tracks) is not supported by the port.");
            PlayInternal(name, customBlend, customSpeed, fromEnd);
        }

        public bool IsPlaying() => _playing;
        public bool IsValid() => _current.isEnabled;

        public string CurrentAnimation
        {
            get => _playing ? _assigned : "";
            set
            {
                if (value == "[stop]" || string.IsNullOrEmpty(value))
                {
                    if (IsPlaying()) CallDeferred(() => Stop(false));
                }
                else if (!IsPlaying()) Play(value);
                else if (_assigned != value)
                {
                    float speed = _current.speedScale;
                    Play(value, -1.0, speed, Animation.IsNegative(speed));
                }
            }
        }
        public string GetCurrentAnimation() => CurrentAnimation;
        public void SetCurrentAnimation(string a) => CurrentAnimation = a;

        public string AssignedAnimation
        {
            get => _assigned;
            set
            {
                if (IsPlaying())
                {
                    float speed = _current.speedScale;
                    Play(value, -1.0, speed, Animation.IsNegative(speed));
                }
                else
                {
                    if (!animationSet.TryGetValue(value ?? "", out var ad)) { GD.PushError("Animation not found: " + value + "."); return; }
                    _current.pos = 0;
                    _current.isEnabled = true;
                    _current.animationName = value;
                    _current.animationLength = ad.animation.Length;
                    _current.startTime = -1;
                    _current.endTime = -1;
                    _assigned = value;
                    CurrentAnimationChanged?.Invoke(_assigned);
                }
            }
        }
        public string GetAssignedAnimation() => _assigned;
        public void SetAssignedAnimation(string a) => AssignedAnimation = a;

        public void Pause() => StopInternal(false, false);
        public void Stop(bool keepState = false) => StopInternal(true, keepState);

        public float SpeedScale { get => _speedScale; set => _speedScale = value; }
        public void SetSpeedScale(double s) => _speedScale = (float)s;
        public float GetSpeedScale() => _speedScale;
        public float GetPlayingSpeed() => !_playing ? 0 : _speedScale * _current.speedScale;

        // ------------------------------------------------------------------ seek / advance
        public void SeekInternal(double time, bool update = false, bool updateOnly = false, bool isInternalSeek = false)
        {
            if (!active) return;
            bool isBackward = Animation.IsLessApprox(time, _current.pos);
            CheckImmediatelyAfterStart();
            _current.pos = time;
            if (!_current.isEnabled)
            {
                if (_assigned.Length > 0)
                {
                    if (!animationSet.TryGetValue(_assigned, out var ad)) { GD.PushError("Animation not found: " + _assigned + "."); return; }
                    _current.isEnabled = true;
                    _current.animationName = _assigned;
                    _current.animationLength = ad.animation.Length;
                }
                if (!_current.isEnabled) return;
            }
            _seeked = true;
            _internalSeeked = isInternalSeek;
            if (update)
            {
                ProcessAnimation(isBackward ? -0.0 : 0.0, updateOnly);
                _seeked = false;
            }
        }

        /// <summary>seek(seconds, update = false, update_only = false).</summary>
        public void Seek(double time, bool update = false, bool updateOnly = false) => SeekInternal(time, update, updateOnly);

        public override void Advance(double delta)
        {
            CheckImmediatelyAfterStart();
            base.Advance(delta);
        }

        void CheckImmediatelyAfterStart()
        {
            if (_started) ProcessAnimation(0);
        }

        public double CurrentAnimationPosition => GetCurrentAnimationPosition();
        public double CurrentAnimationLength => GetCurrentAnimationLength();

        public double GetCurrentAnimationPosition()
        {
            if (!_current.isEnabled) { GD.PushError("AnimationPlayer has no current animation."); return 0; }
            return _current.pos;
        }

        public double GetCurrentAnimationLength()
        {
            if (!_current.isEnabled) { GD.PushError("AnimationPlayer has no current animation."); return 0; }
            return _current.animationLength;
        }

        // ------------------------------------------------------------------ sections
        public void SetSectionWithMarkers(string startMarker = "", string endMarker = "")
        {
            if (!_current.isEnabled) { GD.PushError("AnimationPlayer has no current animation."); return; }
            var anim = animationSet.TryGetValue(_current.animationName, out var ad) ? ad.animation : null;
            if (anim == null) return;
            double st = !string.IsNullOrEmpty(startMarker) ? anim.GetMarkerTime(startMarker) : -1;
            double et = !string.IsNullOrEmpty(endMarker) ? anim.GetMarkerTime(endMarker) : -1;
            SetSection(st, et);
        }

        public void SetSection(double startTime = -1, double endTime = -1)
        {
            if (!_current.isEnabled) { GD.PushError("AnimationPlayer has no current animation."); return; }
            if (Animation.IsGreaterOrEqualApprox(startTime, 0) && Animation.IsGreaterOrEqualApprox(endTime, 0) && Animation.IsGreaterOrEqualApprox(startTime, endTime))
            {
                GD.PushError("Start time " + startTime + " is greater than end time " + endTime + ".");
                return;
            }
            _current.startTime = startTime;
            _current.endTime = endTime;
            _current.pos = GD.Clamp(_current.pos, _current.GetStartTime(), _current.GetEndTime());
        }

        public void ResetSection()
        {
            _current.startTime = -1;
            _current.endTime = -1;
        }

        public double GetSectionStartTime() => _current.GetStartTime();
        public double GetSectionEndTime() => _current.GetEndTime();
        public bool HasSection() => Animation.IsGreaterOrEqualApprox(_current.startTime, 0) || Animation.IsGreaterOrEqualApprox(_current.endTime, 0);

        // ------------------------------------------------------------------ settings
        public string Autoplay
        {
            get => _autoplay;
            set
            {
                if (IsInsideTree()) GD.PushWarning("Setting autoplay after the node has been added to the scene has no effect.");
                _autoplay = value ?? "";
            }
        }

        public bool MovieQuitOnFinish { get => _movieQuitOnFinish; set => _movieQuitOnFinish = value; }
        public bool PlaybackAutoCapture { get => _autoCapture; set => _autoCapture = value; }
        public double PlaybackAutoCaptureDuration { get => _autoCaptureDuration; set => _autoCaptureDuration = value; }
        /// <summary>playback_default_blend_time.</summary>
        public double PlaybackDefaultBlendTime { get => _defaultBlendTime; set => _defaultBlendTime = value; }
        public void SetDefaultBlendTime(double t) => _defaultBlendTime = t;
        public double GetDefaultBlendTime() => _defaultBlendTime;

        public void SetBlendTime(string from, string to, double sec)
        {
            if (!animationSet.ContainsKey(from)) { GD.PushError("Animation not found: " + from + "."); return; }
            if (!animationSet.ContainsKey(to)) { GD.PushError("Animation not found: " + to + "."); return; }
            if (sec < 0) { GD.PushError("Blend time cannot be smaller than 0."); return; }
            if (GD.IsZeroApprox(sec)) _blendTimes.Remove((from, to));
            else _blendTimes[(from, to)] = sec;
        }

        public double GetBlendTime(string from, string to) => _blendTimes.TryGetValue((from, to), out double t) ? t : 0;

        public void AnimationSetNext(string animation, string next)
        {
            if (!animationSet.ContainsKey(animation)) { GD.PushError("Animation not found: " + animation + "."); return; }
            _animationNextSet[animation] = next ?? "";
        }

        public string AnimationGetNext(string animation) => animation != null && _animationNextSet.TryGetValue(animation, out var n) ? n : "";

        // ------------------------------------------------------------------ stop
        void StopInternal(bool reset, bool keepState)
        {
            ClearCaches();
            double start = _current.isEnabled ? _current.GetStartTime() : 0;
            if (reset)
            {
                _blendCount = 0;
                if (keepState) _current.pos = start;
                else SeekInternal(start, true, true, true);
                _current.isEnabled = false;
                _current.animationName = "";
                _current.speedScale = 1;
                CurrentAnimationChanged?.Invoke("");
            }
            SetMixerProcess(false);
            _queue.Clear();
            _playing = false;
        }

        // ------------------------------------------------------------------ library notifications
        protected override void OnAnimationChanged(string name)
        {
            base.OnAnimationChanged(name);
            if (_current.isEnabled && _current.animationName == name && animationSet.TryGetValue(name, out var ad))
                _current.animationLength = ad.animation.Length;
        }

        protected override void OnAnimationRemoved(string name, string library)
        {
            base.OnAnimationRemoved(name, library);
            string full = library.Length == 0 ? name : library + "/" + name;
            if (!animationSet.ContainsKey(full)) return;
            var toErase = new List<(string, string)>();
            foreach (var k in _blendTimes.Keys) if (k.Item1 == full || k.Item2 == full) toErase.Add(k);
            foreach (var k in toErase) _blendTimes.Remove(k);
        }

        protected override void OnRenameAnimation(string from, string to)
        {
            base.OnRenameAnimation(from, to);
            var moved = new List<KeyValuePair<(string, string), double>>();
            foreach (var kv in _blendTimes)
                if (kv.Key.Item1 == from || kv.Key.Item2 == from) moved.Add(kv);
            foreach (var kv in moved)
            {
                _blendTimes.Remove(kv.Key);
                _blendTimes[(kv.Key.Item1 == from ? to : kv.Key.Item1, kv.Key.Item2 == from ? to : kv.Key.Item2)] = kv.Value;
            }
            if (_autoplay == from) _autoplay = to;
        }

        public override void _Notification(int what)
        {
            base._Notification(what);
            if (what == NOTIFICATION_READY && animationSet.ContainsKey(_autoplay))
            {
                Active = active;        // (as Godot's set_active(active): no change)
                Play(_autoplay);
                CheckImmediatelyAfterStart();
            }
        }

        public override bool SetStoredProperty(string name, Var value)
        {
            if (name.StartsWith("next/"))
            {
                AnimationSetNext(name.Substring(5), value.AsString());
                return true;
            }
            if (name == "blend_times")
            {
                var arr = value.AsArr();
                if (arr == null || arr.Size() % 3 != 0) return false;
                for (int i = 0; i < arr.Size() / 3; i++) SetBlendTime(arr[i * 3].AsString(), arr[i * 3 + 1].AsString(), (float)arr[i * 3 + 2].AsFloat());
                return true;
            }
            if (name == "current_animation" || name.StartsWith("playback/play")) { CurrentAnimation = value.AsString(); return true; }
            if (name == "autoplay") { _autoplay = value.AsString(); return true; }
            return base.SetStoredProperty(name, value);
        }
    }
}

#endif
