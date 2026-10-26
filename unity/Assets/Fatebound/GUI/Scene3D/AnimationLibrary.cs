#if FB3D
// Godot's AnimationLibrary (scene/resources/animation_library.cpp): named animations (kept sorted by name, as Godot's
// RBMap with StringName::AlphCompare), the animation_added/removed/renamed/changed signals the mixers follow, and the
// stored property "_data" (Dictionary name -> Animation) the baked-asset loader sets.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public sealed class AnimationLibrary : Resource
    {
        readonly SortedDictionary<string, Animation> _animations = new SortedDictionary<string, Animation>(StringComparer.Ordinal);
        readonly Dictionary<Animation, Action> _changedHandlers = new Dictionary<Animation, Action>();
        /// <summary>Bumped when animations are added, removed or renamed.</summary>
        internal int listVersion;

        public event Action<string> AnimationAdded, AnimationRemoved, AnimationChanged;
        public event Action<string, string> AnimationRenamed;

        public static bool IsValidAnimationName(string name) =>
            !(string.IsNullOrEmpty(name) || name.IndexOf('/') >= 0 || name.IndexOf(':') >= 0 || name.IndexOf(',') >= 0 || name.IndexOf('[') >= 0);

        public static bool IsValidLibraryName(string name) =>
            !(name.IndexOf('/') >= 0 || name.IndexOf(':') >= 0 || name.IndexOf(',') >= 0 || name.IndexOf('[') >= 0);

        public static string ValidateLibraryName(string name) =>
            name.Replace('/', '_').Replace(':', '_').Replace(',', '_').Replace('[', '_');

        internal SortedDictionary<string, Animation> Animations => _animations;

        void Connect(string name, Animation anim)
        {
            Action h = () => AnimationChanged?.Invoke(name);
            _changedHandlers[anim] = h;
            anim.Changed += h;
        }

        void Disconnect(Animation anim)
        {
            if (anim != null && _changedHandlers.TryGetValue(anim, out var h))
            {
                anim.Changed -= h;
                _changedHandlers.Remove(anim);
            }
        }

        public int AddAnimation(string name, Animation animation)
        {
            if (!IsValidAnimationName(name)) { GD.PushError("Invalid animation name: '" + name + "'."); return GD.ERR_INVALID_PARAMETER; }
            if (animation == null) { GD.PushError("Condition \"p_animation.is_null()\" is true. Returning: ERR_INVALID_PARAMETER"); return GD.ERR_INVALID_PARAMETER; }
            if (_animations.TryGetValue(name, out var old))
            {
                Disconnect(old);
                _animations.Remove(name);
                listVersion++;
                AnimationRemoved?.Invoke(name);
            }
            _animations[name] = animation;
            // (one animation in a library under two names: Godot connects it twice; the last name wins here)
            Disconnect(animation);
            Connect(name, animation);
            listVersion++;
            AnimationAdded?.Invoke(name);
            return GD.OK;
        }

        public void RemoveAnimation(string name)
        {
            if (name == null || !_animations.TryGetValue(name, out var a)) { GD.PushError("Animation not found: " + name + "."); return; }
            Disconnect(a);
            _animations.Remove(name);
            listVersion++;
            AnimationRemoved?.Invoke(name);
        }

        public void RenameAnimation(string name, string newName)
        {
            if (name == null || !_animations.TryGetValue(name, out var a)) { GD.PushError("Animation not found: " + name + "."); return; }
            if (!IsValidAnimationName(newName)) { GD.PushError("Invalid animation name: '" + newName + "'."); return; }
            if (_animations.ContainsKey(newName)) { GD.PushError("Animation name \"" + newName + "\" already exists in library."); return; }
            Disconnect(a);
            Connect(newName, a);
            _animations[newName] = a;
            _animations.Remove(name);
            listVersion++;
            AnimationRenamed?.Invoke(name, newName);
        }

        public bool HasAnimation(string name) => name != null && _animations.ContainsKey(name);

        public Animation GetAnimation(string name)
        {
            if (name != null && _animations.TryGetValue(name, out var a)) return a;
            GD.PushError("Animation not found: \"" + name + "\".");
            return null;
        }

        /// <summary>get_animation_list(): the names, sorted.</summary>
        public string[] GetAnimationList()
        {
            var r = new string[_animations.Count];
            _animations.Keys.CopyTo(r, 0);
            return r;
        }

        public int GetAnimationListSize() => _animations.Count;

        public override bool SetStoredProperty(string name, Var value)
        {
            if (name != "_data") return false;
            foreach (var a in _animations.Values) Disconnect(a);
            _animations.Clear();
            listVersion++;
            var d = value.AsDict();
            if (d == null) return true;
            foreach (var k in d.Keys())
            {
                var anim = d[k].Obj as Animation;
                AddAnimation(k.AsString(), anim);
            }
            return true;
        }

        /// <summary>_get_data(): name -> Animation.</summary>
        public GDict GetData()
        {
            var d = new GDict();
            foreach (var kv in _animations) d[kv.Key] = Var.Of(kv.Value);
            return d;
        }

        public override Resource Duplicate(bool deep = false)
        {
            var l = new AnimationLibrary { ResourceName = ResourceName };
            foreach (var kv in _animations) l.AddAnimation(kv.Key, deep ? (Animation)kv.Value.Duplicate(true) : kv.Value);
            return l;
        }
    }
}

#endif
