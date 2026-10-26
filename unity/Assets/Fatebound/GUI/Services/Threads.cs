// Fatebound engine services (Unity port): Godot's Thread, Mutex (recursive, as Godot's), Semaphore and
// WorkerThreadPool over System.Threading. A GDScript Callable is an Action or a Func<Var> here.
using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public sealed class Thread
    {
        public const int PRIORITY_LOW = 0, PRIORITY_NORMAL = 1, PRIORITY_HIGH = 2;

        System.Threading.Thread _t;
        volatile bool _alive;
        Var _result;

        public int Start(Action callable, int priority = PRIORITY_NORMAL) =>
            callable == null ? Invalid() : Begin(() => { callable(); return Var.Nil; }, priority);

        public int Start(Func<Var> callable, int priority = PRIORITY_NORMAL) =>
            callable == null ? Invalid() : Begin(callable, priority);

        static int Invalid()
        {
            GD.PushError("Condition \"!p_callable.is_valid()\" is true. Returning: ERR_INVALID_PARAMETER");
            return GD.ERR_INVALID_PARAMETER;
        }

        int Begin(Func<Var> f, int priority)
        {
            if (_t != null) { GD.PushError("Thread already started."); return GD.ERR_ALREADY_IN_USE; }
            _alive = true;
            _result = Var.Nil;
            _t = new System.Threading.Thread(() =>
            {
                try { _result = f(); }
                catch (Exception e) { GD.PushError(e.ToString()); }
                finally { _alive = false; }
            })
            { IsBackground = true, Name = "GodotThread" };
            try { _t.Priority = priority == PRIORITY_LOW ? ThreadPriority.BelowNormal : priority == PRIORITY_HIGH ? ThreadPriority.AboveNormal : ThreadPriority.Normal; }
            catch (Exception) { }
            _t.Start();
            return GD.OK;
        }

        /// <summary>wait_to_finish(): joins and returns what the callable returned; the Thread can start again.</summary>
        public Var WaitToFinish()
        {
            if (_t == null) { GD.PushError("Thread must have been started to wait for its completion."); return Var.Nil; }
            _t.Join();
            _t = null;
            var r = _result;
            _result = Var.Nil;
            return r;
        }

        public bool IsStarted() => _t != null;
        public bool IsAlive() => _alive;
        public string GetId() => _t == null ? "" : _t.ManagedThreadId.ToString();
        public static void SetThreadSafetyChecksEnabled(bool enabled) { }
    }

    /// <summary>Godot's Mutex: recursive (the same thread may lock it again).</summary>
    public sealed class Mutex
    {
        readonly object _o = new object();
        public void Lock() => Monitor.Enter(_o);
        public bool TryLock() => Monitor.TryEnter(_o);

        public void Unlock()
        {
            try { Monitor.Exit(_o); }
            catch (SynchronizationLockException) { GD.PushError("Mutex.unlock() from a thread that doesn't hold it."); }
        }
    }

    public sealed class Semaphore
    {
        readonly SemaphoreSlim _s = new SemaphoreSlim(0, int.MaxValue);
        public void Wait() => _s.Wait();
        public bool TryWait() => _s.Wait(0);
        public void Post(int count = 1) { if (count > 0) _s.Release(count); }
    }

    /// <summary>Godot's WorkerThreadPool on the .NET thread pool. Task ids start at 1; a waited task is forgotten
    /// (waiting again is ERR_INVALID_PARAMETER, as Godot).</summary>
    public static class WorkerThreadPool
    {
        static long _next = 1;
        static readonly Dictionary<long, Task> _tasks = new Dictionary<long, Task>();
        static readonly Dictionary<long, Task> _groups = new Dictionary<long, Task>();

        public static long AddTask(Action action, bool highPriority = false, string description = "")
        {
            if (action == null) { GD.PushError("Condition \"!p_action.is_valid()\" is true."); return -1; }
            var t = Task.Factory.StartNew(() =>
            {
                try { action(); }
                catch (Exception e) { GD.PushError(e.ToString()); }
            }, CancellationToken.None, highPriority ? TaskCreationOptions.PreferFairness : TaskCreationOptions.None, TaskScheduler.Default);
            lock (_tasks)
            {
                long id = _next++;
                _tasks[id] = t;
                return id;
            }
        }

        public static bool IsTaskCompleted(long id)
        {
            lock (_tasks)
            {
                if (_tasks.TryGetValue(id, out var t)) return t.IsCompleted;
            }
            GD.PushError("Invalid Task ID");
            return false;
        }

        public static int WaitForTaskCompletion(long id)
        {
            Task t;
            lock (_tasks)
            {
                if (!_tasks.TryGetValue(id, out t)) { GD.PushError("Invalid Task ID"); return GD.ERR_INVALID_PARAMETER; }
                _tasks.Remove(id);
            }
            t.Wait();
            return GD.OK;
        }

        /// <summary>add_group_task(action(index), elements, tasks_needed): action runs once for each index.</summary>
        public static long AddGroupTask(Action<int> action, int elements, int tasksNeeded = -1, bool highPriority = false, string description = "")
        {
            var t = Task.Run(() =>
            {
                try { Parallel.For(0, elements, i => action(i)); }
                catch (Exception e) { GD.PushError(e.ToString()); }
            });
            lock (_tasks)
            {
                long id = _next++;
                _groups[id] = t;
                return id;
            }
        }

        public static bool IsGroupTaskCompleted(long id)
        {
            lock (_tasks)
            {
                if (_groups.TryGetValue(id, out var t)) return t.IsCompleted;
            }
            GD.PushError("Invalid Group Task ID");
            return false;
        }

        public static void WaitForGroupTaskCompletion(long id)
        {
            Task t;
            lock (_tasks)
            {
                if (!_groups.TryGetValue(id, out t)) { GD.PushError("Invalid Group Task ID"); return; }
                _groups.Remove(id);
            }
            t.Wait();
        }
    }
}
