// The audio host (Fatebound.GUI.IAudioHost): every AudioStreamPlayer voice is an AudioSource on one GameObject (2D,
// no spatialisation, like Godot's AudioStreamPlayer), clips from Resources/res (AssetImport: music streams, sounds
// decompressed on load).
using System.Collections.Generic;
using Fatebound.GUI;
using UnityEngine;

namespace Fatebound.Client
{
    public sealed class UnityAudio : IAudioHost
    {
        sealed class Voice
        {
            public AudioSource Source;
            public bool Paused;
            public bool Started;
        }

        readonly GameObject _go;
        readonly Dictionary<string, AudioClip> _clips = new Dictionary<string, AudioClip>();

        public UnityAudio()
        {
            _go = new GameObject("Audio");
            Object.DontDestroyOnLoad(_go);
            if (Object.FindAnyObjectByType<AudioListener>() == null) _go.AddComponent<AudioListener>();
        }

        public object LoadClip(string resPath, out double length)
        {
            if (!_clips.TryGetValue(resPath, out var clip))
            {
                clip = Resources.Load<AudioClip>(UnityGuiHost.ResourcesPath(resPath));
                _clips[resPath] = clip;
            }
            length = clip != null ? clip.length : 0.0;
            return clip;
        }

        public bool ClipExists(string resPath) => LoadClip(resPath, out _) != null;

        public object CreateVoice()
        {
            var s = _go.AddComponent<AudioSource>();
            s.playOnAwake = false;
            s.spatialBlend = 0f;
            s.dopplerLevel = 0f;
            s.bypassReverbZones = true;
            return new Voice { Source = s };
        }

        public void Play(object voice, object clip, double from, float gain, float pitch, bool loop)
        {
            var v = (Voice)voice;
            var s = v.Source;
            s.Stop();
            s.clip = clip as AudioClip;
            if (s.clip == null) return;
            s.loop = loop;
            s.volume = Mathf.Clamp01(gain);
            s.pitch = pitch;
            s.time = Mathf.Clamp((float)from, 0f, Mathf.Max(0f, s.clip.length - 0.001f));
            s.Play();
            v.Paused = false;
            v.Started = true;
        }

        public void Stop(object voice)
        {
            var v = (Voice)voice;
            v.Source.Stop();
            v.Paused = false;
            v.Started = false;
        }

        public void SetPaused(object voice, bool paused)
        {
            var v = (Voice)voice;
            if (!v.Started || v.Paused == paused) return;
            v.Paused = paused;
            if (paused) v.Source.Pause(); else v.Source.UnPause();
        }

        public bool IsActive(object voice)
        {
            var v = (Voice)voice;
            if (!v.Started) return false;
            if (v.Paused) return true;
            // (an AudioSource stops being "playing" while the app is paused: treat focus loss as paused, not ended)
            if (!v.Source.isPlaying && Application.isFocused) v.Started = false;
            return v.Started;
        }

        public double GetPosition(object voice) => ((Voice)voice).Source.time;

        public void Seek(object voice, double position)
        {
            var s = ((Voice)voice).Source;
            if (s.clip != null) s.time = Mathf.Clamp((float)position, 0f, Mathf.Max(0f, s.clip.length - 0.001f));
        }

        public void SetGain(object voice, float gain, float pitch)
        {
            var s = ((Voice)voice).Source;
            s.volume = Mathf.Clamp01(gain);
            s.pitch = pitch;
        }

        public void DestroyVoice(object voice)
        {
            var v = (Voice)voice;
            if (v.Source != null) Object.Destroy(v.Source);
        }
    }
}
