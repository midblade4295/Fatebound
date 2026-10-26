// Ported from godot/scripts/native_audio.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;

namespace Fatebound.Game
{
    // Exact existing Fatebound PCM effects exported to local WAV assets, never fetched during combat.
    public class NativeAudio : Node
    {
        public List<AudioStreamPlayer> voices = new List<AudioStreamPlayer>();
        public GDict cache = new GDict();
        public bool muted = false;
        public GDict last = new GDict();

        protected override void _Ready()
        {
            var cfg = new ConfigFile();
            if (cfg.Load("user://native_audio.cfg") == GD.OK)
                muted = (bool)cfg.GetValue("audio", "muted", false);
            for (int i = 0; i < 16; i++)      // 8 until 0.30.8: matches now play combat, gathering, gate and footstep sounds
            {
                var player = new AudioStreamPlayer();
                player.VolumeDb = -15.0;
                AddChild(player);
                voices.Add(player);
            }
            GetTree().Root.FocusExited += Stop;
        }

        public void Stop()
        {
            foreach (var player in voices)
                player.Stop();
        }

        public void Toggle()
        {
            muted = !muted;
            if (muted)
                Stop();
            var cfg = new ConfigFile();
            cfg.SetValue("audio", "muted", muted);
            cfg.Save("user://native_audio.cfg");
        }

        public void Play(string cue, bool quiet = false, double vol = 1.0)
        {
            if (muted || !GetWindow().HasFocus())
                return;
            var now = Time.GetTicksMsec();
            if (now - GD.Long(last.Get(cue, -9999)) < 90)
                return;
            var path = "res://assets/sounds/" + cue + ".wav";
            if (!cache.Has(cue))
            {
                if (!ResourceLoader.Exists(path))
                    return;
                cache[cue] = Var.Of(ResourceLoader.Load(path));
            }
            last[cue] = now;
            foreach (var player in voices)
            {
                if (!player.Playing)
                {
                    player.Stream = cache[cue].As<AudioStream>();
                    bool ui_cue = GArray.Of("tap", "menuOpen", "menuClose", "equip", "purchase", "coin", "confirm", "error", "chest", "level", "energy",
                        "gem", "ember", "claim", "chestOpen", "forge", "flip", "countdown", "matchStart",   // (0.31.109: the new menu sounds)
                        "tab", "toggle", "slider", "unlock", "premium", "tierUp", "revealRare", "revealEpic", "revealLegendary", "gemPack",
                        "levelUp", "resultWin", "resultLose",   // (0.31.110)
                        "ping", "chatPop",   // (0.31.111)
                        "titleSlam").Has(cue);   // (0.31.139: the title screen)
                    // 0.31.58 (Kevin: game audio louder): base 0.12 -> 0.2, and a cue may ask for up to 3x (the bomb) -- vol was
                    // clamped to 1, so every "louder" gain above 1 did nothing
                    double gain = GD.Minf(1.0, 0.2 * (double)levels["master"] * (double)(ui_cue ? levels["ui"] : levels["combat"]) * (quiet ? 0.40 : 1.0) * GD.Clampf(vol, 0.0, 3.0));
                    if (gain <= 0)
                        return;
                    player.VolumeDb = GD.LinearToDb(gain);
                    player.Play();
                    return;
                }
            }
        }

        public GDict levels = new GDict { { "master", 1.0 }, { "combat", 1.0 }, { "ui", 1.0 }, { "music", 1.0 } };   // 0.31.110: every slider at 100% by default

        public void SetLevels(GDict value)
        {
            foreach (var key in levels)
            {
                if (value.Get(key).IsFloat || value.Get(key).IsInt)
                    levels[key] = GD.Clampf((double)value[key], 0, 1);
            }
            if ((double)levels["master"] <= 0)
                Stop();
        }
    }
}
