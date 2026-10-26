// Godot's audio as the game uses it: AudioStream resources (.wav / .ogg / .mp3 loaded with load()) and
// AudioStreamPlayer (non-positional, the Master bus). Behaviour from scene/audio/audio_stream_player_internal.cpp:
// max_polyphony 1 (play() while playing restarts), playback paused while the node is outside the tree or can't
// process (pause mode), "finished" emitted from internal process once a playback has ended (not when stopped),
// volume_db -> linear gain, pitch_scale. The host (IAudioHost, the Unity client's AudioSources) does the mixing.
// Import defaults are Godot's: loop off for every stream the game ships (their .import files all say so); the game
// turns looping on in code (stream.loop = true).
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    /// <summary>What the engine side provides for audio.</summary>
    public interface IAudioHost
    {
        /// <summary>The engine clip of a res:// audio file (main thread), and its length in seconds; null if missing.</summary>
        object LoadClip(string resPath, out double length);
        bool ClipExists(string resPath);
        object CreateVoice();
        void Play(object voice, object clip, double from, float gain, float pitch, bool loop);
        void Stop(object voice);
        void SetPaused(object voice, bool paused);
        /// <summary>True while the voice's playback is running or paused (Godot's playback still registered).</summary>
        bool IsActive(object voice);
        double GetPosition(object voice);
        void Seek(object voice, double position);
        void SetGain(object voice, float gain, float pitch);
        void DestroyVoice(object voice);
    }

    public abstract partial class AudioStream : Resource
    {
        object _clip;
        double _length = -1;
        bool _loaded;

        /// <summary>The engine clip (loaded on first use, on the main thread).</summary>
        public object Clip
        {
            get
            {
                if (!_loaded && AudioServer.Host != null && !string.IsNullOrEmpty(ResourcePath))
                {
                    _loaded = true;
                    _clip = AudioServer.Host.LoadClip(ResourcePath, out _length);
                }
                return _clip;
            }
        }

        public virtual double GetLength()
        {
            var _ = Clip;
            return _length < 0 ? 0.0 : _length;
        }

        internal abstract bool Looping { get; }
        public virtual bool IsMonophonic() => false;
    }

    public sealed partial class AudioStreamOggVorbis : AudioStream
    {
        public bool Loop;
        public double LoopOffset;
        public double Bpm;
        public int BeatCount, BarBeats = 4;
        internal override bool Looping => Loop;
    }

    public sealed partial class AudioStreamMP3 : AudioStream
    {
        public bool Loop;
        public double LoopOffset;
        public double Bpm;
        public int BeatCount, BarBeats = 4;
        internal override bool Looping => Loop;
    }

    public sealed partial class AudioStreamWAV : AudioStream
    {
        public const int LOOP_DISABLED = 0, LOOP_FORWARD = 1, LOOP_PINGPONG = 2, LOOP_BACKWARD = 3;
        public const int FORMAT_8_BITS = 0, FORMAT_16_BITS = 1, FORMAT_IMA_ADPCM = 2, FORMAT_QOA = 3;
        public int LoopMode = LOOP_DISABLED;
        public int LoopBegin, LoopEnd;
        public int MixRate = 44100;
        public bool Stereo;
        public int Format = FORMAT_16_BITS;
        internal override bool Looping => LoopMode != LOOP_DISABLED;
    }

    /// <summary>Godot's AudioServer, as far as the game reaches it: the Master bus.</summary>
    public static partial class AudioServer
    {
        public static IAudioHost Host;
        static readonly List<string> _buses = new List<string> { "Master" };
        static readonly List<double> _busDb = new List<double> { 0.0 };
        static readonly List<bool> _busMute = new List<bool> { false };
        internal static readonly List<AudioStreamPlayer> Players = new List<AudioStreamPlayer>();

        public static int GetBusCount() => _buses.Count;
        public static int GetBusIndex(string name) => _buses.IndexOf(name);
        public static string GetBusName(int i) => i >= 0 && i < _buses.Count ? _buses[i] : "";
        public static double GetBusVolumeDb(int i) => i >= 0 && i < _busDb.Count ? _busDb[i] : 0.0;
        public static void SetBusVolumeDb(int i, double db) { if (i >= 0 && i < _busDb.Count) { _busDb[i] = db; Refresh(); } }
        public static double GetBusVolumeLinear(int i) => GD.DbToLinear(GetBusVolumeDb(i));
        public static void SetBusVolumeLinear(int i, double v) => SetBusVolumeDb(i, GD.LinearToDb(v));
        public static bool IsBusMute(int i) => i >= 0 && i < _busMute.Count && _busMute[i];
        public static void SetBusMute(int i, bool mute) { if (i >= 0 && i < _busMute.Count) { _busMute[i] = mute; Refresh(); } }

        /// <summary>A player's gain on its bus (unknown buses fall back to Master, as Godot does).</summary>
        internal static float BusGain(string bus)
        {
            int i = _buses.IndexOf(bus);
            if (i < 0) i = 0;
            float g = (float)GD.DbToLinear(_busDb[i]);
            if (_busMute[i]) g = 0f;
            if (i != 0) g *= _busMute[0] ? 0f : (float)GD.DbToLinear(_busDb[0]);
            return g;
        }

        static void Refresh()
        {
            foreach (var p in Players) p.RefreshGain();
        }
    }

    public partial class AudioStreamPlayer : Node
    {
        public const int MIX_TARGET_STEREO = 0, MIX_TARGET_SURROUND = 1, MIX_TARGET_CENTER = 2;
        public const int PLAYBACK_TYPE_DEFAULT = 0, PLAYBACK_TYPE_STREAM = 1, PLAYBACK_TYPE_SAMPLE = 2;

        AudioStream _stream;
        double _volumeDb;
        double _pitch = 1.0;
        string _bus = "Master";
        object _voice;
        bool _active;          // a playback is registered (playing or paused)
        bool _paused;

        public bool Autoplay;
        public int MaxPolyphony = 1;
        public int MixTarget = MIX_TARGET_STEREO;
        public int PlaybackType = PLAYBACK_TYPE_DEFAULT;

        public event Action Finished;

        public AudioStream Stream
        {
            get => _stream;
            set
            {
                if (_stream == value) return;
                // Godot: setting a stream stops the current playbacks
                if (_active) Stop();
                _stream = value;
            }
        }

        public double VolumeDb
        {
            get => _volumeDb;
            set
            {
                if (double.IsNaN(value)) { GD.PushError("Volume can't be set to NaN."); return; }
                _volumeDb = value;
                RefreshGain();
            }
        }

        public double VolumeLinear
        {
            get => GD.DbToLinear(_volumeDb);
            set => VolumeDb = GD.LinearToDb(value);
        }

        public double PitchScale
        {
            get => _pitch;
            set
            {
                if (!(value > 0.0)) { GD.PushError("Pitch scale must be positive."); return; }
                _pitch = value;
                RefreshGain();
            }
        }

        public string Bus
        {
            get => _bus;
            set { _bus = value ?? "Master"; RefreshGain(); }
        }

        public bool Playing
        {
            get => IsPlaying();
            set { if (value) Play(); else Stop(); }
        }

        public bool StreamPaused
        {
            get => _active && _paused;
            set => SetPausedInternal(value);
        }

        float Gain => (float)GD.DbToLinear(_volumeDb) * AudioServer.BusGain(_bus);

        internal void RefreshGain()
        {
            if (_voice != null && AudioServer.Host != null) AudioServer.Host.SetGain(_voice, Gain, (float)_pitch);
        }

        public void Play(double fromPosition = 0.0)
        {
            if (_stream == null) return;
            if (!IsInsideTree()) { GD.PushError("Playback can only happen when a node is inside the scene tree"); return; }
            var host = AudioServer.Host;
            if (host == null) return;
            var clip = _stream.Clip;
            if (clip == null) return;
            if (_voice == null) _voice = host.CreateVoice();
            // max_polyphony 1: the new playback replaces the old one
            host.Play(_voice, clip, Math.Max(0.0, fromPosition), Gain, (float)_pitch, _stream.Looping);
            _active = true;
            _paused = false;
            SetProcessInternal(true);
            if (!CanProcess()) SetPausedInternal(true);
        }

        public void Stop()
        {
            if (_voice != null && AudioServer.Host != null) AudioServer.Host.Stop(_voice);
            _active = false;
            _paused = false;
            SetProcessInternal(false);
        }

        public void Seek(double toPosition)
        {
            if (_voice != null && _active && AudioServer.Host != null) AudioServer.Host.Seek(_voice, Math.Max(0.0, toPosition));
        }

        public bool IsPlaying() => _active && !_paused && _voice != null && AudioServer.Host != null && AudioServer.Host.IsActive(_voice);

        public double GetPlaybackPosition() => _voice != null && _active && AudioServer.Host != null ? AudioServer.Host.GetPosition(_voice) : 0.0;

        public bool HasStreamPlayback() => _active;

        void SetPausedInternal(bool paused)
        {
            if (!_active) return;
            _paused = paused;
            if (_voice != null && AudioServer.Host != null) AudioServer.Host.SetPaused(_voice, paused);
        }

        protected override void InternalProcess(double delta)
        {
            // a playback that ended on its own: Godot removes it and emits "finished"
            if (_active && !_paused && (_voice == null || AudioServer.Host == null || !AudioServer.Host.IsActive(_voice)))
            {
                _active = false;
                SetProcessInternal(false);
                Finished?.Invoke();
            }
        }

        public override void _Notification(int what)
        {
            base._Notification(what);
            switch (what)
            {
                case NOTIFICATION_ENTER_TREE:
                    if (!AudioServer.Players.Contains(this)) AudioServer.Players.Add(this);
                    if (Autoplay) Play(0.0);
                    SetPausedInternal(!CanProcess());
                    break;
                case NOTIFICATION_EXIT_TREE:
                    SetPausedInternal(true);
                    break;
                case NOTIFICATION_PREDELETE:
                    AudioServer.Players.Remove(this);
                    if (_voice != null && AudioServer.Host != null) AudioServer.Host.DestroyVoice(_voice);
                    _voice = null;
                    _active = false;
                    break;
                case NOTIFICATION_PAUSED:
                    if (!(IsInsideTree() && CanProcess())) SetPausedInternal(true);
                    break;
                case NOTIFICATION_UNPAUSED:
                    SetPausedInternal(false);
                    break;
            }
        }
    }
}
