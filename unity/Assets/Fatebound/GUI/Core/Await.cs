// GDScript's `await`: `await get_tree().process_frame`, `await get_tree().create_timer(t).timeout`, `await some_signal`.
// The continuation runs right where Godot resumes the function -- inside the signal's emission on the main thread
// (custom awaiters, no SynchronizationContext involved, so Unity and the headless runner behave the same).
using System;
using System.Runtime.CompilerServices;

namespace Fatebound.GUI
{
    public static class Await
    {
        /// <summary>await get_tree().process_frame</summary>
        public static SignalAwaitable ProcessFrame() =>
            new SignalAwaitable(h => SceneTree.Current.ProcessFrame += h, h => SceneTree.Current.ProcessFrame -= h);

        /// <summary>await get_tree().physics_frame</summary>
        public static SignalAwaitable PhysicsFrame() =>
            new SignalAwaitable(h => SceneTree.Current.PhysicsFrame += h, h => SceneTree.Current.PhysicsFrame -= h);

        /// <summary>await get_tree().create_timer(seconds).timeout</summary>
        public static SignalAwaitable Timer(double seconds, bool processAlways = true, bool ignoreTimeScale = false)
        {
            var t = SceneTree.Current.CreateTimer(seconds, processAlways, false, ignoreTimeScale);
            return new SignalAwaitable(h => t.Timeout += h, h => t.Timeout -= h);
        }

        /// <summary>await some_signal (an Action event): Signal(h => x.Done += h, h => x.Done -= h)</summary>
        public static SignalAwaitable Signal(Action<Action> add, Action<Action> remove) => new SignalAwaitable(add, remove);

        /// <summary>await some_signal carrying a value: var v = await Signal&lt;int&gt;(h => x.Picked += h, h => x.Picked -= h)</summary>
        public static SignalAwaitable<T> Signal<T>(Action<Action<T>> add, Action<Action<T>> remove) => new SignalAwaitable<T>(add, remove);
    }

    public readonly struct SignalAwaitable
    {
        readonly Action<Action> _add, _remove;
        public SignalAwaitable(Action<Action> add, Action<Action> remove) { _add = add; _remove = remove; }
        public Awaiter GetAwaiter() => new Awaiter(_add, _remove);

        public sealed class Awaiter : INotifyCompletion
        {
            readonly Action<Action> _add, _remove;
            bool _done;
            public Awaiter(Action<Action> add, Action<Action> remove) { _add = add; _remove = remove; }
            public bool IsCompleted => _done;
            public void GetResult() { }

            public void OnCompleted(Action continuation)
            {
                Action h = null;
                h = () =>
                {
                    _remove(h);
                    _done = true;
                    continuation();
                };
                _add(h);
            }
        }
    }

    public readonly struct SignalAwaitable<T>
    {
        readonly Action<Action<T>> _add, _remove;
        public SignalAwaitable(Action<Action<T>> add, Action<Action<T>> remove) { _add = add; _remove = remove; }
        public Awaiter GetAwaiter() => new Awaiter(_add, _remove);

        public sealed class Awaiter : INotifyCompletion
        {
            readonly Action<Action<T>> _add, _remove;
            bool _done;
            T _value;
            public Awaiter(Action<Action<T>> add, Action<Action<T>> remove) { _add = add; _remove = remove; }
            public bool IsCompleted => _done;
            public T GetResult() => _value;

            public void OnCompleted(Action continuation)
            {
                Action<T> h = null;
                h = v =>
                {
                    _remove(h);
                    _value = v;
                    _done = true;
                    continuation();
                };
                _add(h);
            }
        }
    }
}
