// Fatebound GUI (Unity port): Godot's threaded resource loading (ResourceLoader.load_threaded_request /
// load_threaded_get_status / load_threaded_get, THREAD_LOAD_*), and the main-thread hop the loaders use.
//
// What runs where: formats a loader can decode off the main thread (CanLoadOnThread: the baked scenes and resources,
// GUI/Scene3D/BakedLoader.cs) load on a .NET worker; everything else the host provides (textures, fonts, audio) loads on
// the main thread when the request is polled or fetched (the Unity host's Resources.Load works on the main thread only).
// A worker that needs the host (a file's bytes) posts the call to the main thread (MainThread.Post) and waits: the main
// thread runs it in its next MainThread.Flush (each frame's render), or at once when it polls/fetches/load()s that path.
// A finished load enters the resource cache (a later load() of the path returns it, as in Godot); load() of a path
// being loaded on a thread waits for that load. A request of a cached path completes at once.
using System;
using System.Collections.Generic;
using System.Threading;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public static partial class ResourceLoader
    {
        public const int THREAD_LOAD_INVALID_RESOURCE = 0, THREAD_LOAD_IN_PROGRESS = 1, THREAD_LOAD_FAILED = 2, THREAD_LOAD_LOADED = 3;
        public const int CACHE_MODE_IGNORE = 0, CACHE_MODE_REUSE = 1, CACHE_MODE_REPLACE = 2, CACHE_MODE_IGNORE_DEEP = 3, CACHE_MODE_REPLACE_DEEP = 4;

        /// <summary>More formats a worker may load (the baked ones always do).</summary>
        public static Func<string, bool> CanLoadOnThread;

        sealed class ThreadLoad
        {
            public string path;
            public volatile int status = THREAD_LOAD_IN_PROGRESS;
            public Resource result;
            public bool onMain;            // loaded on the main thread when polled / fetched
            public int requests;           // load_threaded_request calls not yet matched by a load_threaded_get
            public readonly ManualResetEventSlim done = new ManualResetEventSlim(false);
        }

        static readonly Dictionary<string, ThreadLoad> _threadLoads = new Dictionary<string, ThreadLoad>();

        static Resource Cached(string path)
        {
            lock (_cache)
            {
                if (_pinned.TryGetValue(path, out var p)) return p;
                if (_cache.TryGetValue(path, out var w) && w.TryGetTarget(out var r)) return r;
            }
            return null;
        }

        static void AddToCache(string path, Resource res)
        {
            res.ResourcePath = path;
            lock (_cache)
            {
                _cache[path] = new WeakReference<Resource>(res);
                if (res is Font) _pinned[path] = res;
            }
        }

        /// <summary>load_threaded_request(path, type_hint, use_sub_threads, cache_mode): OK (the outcome shows in the
        /// status: FAILED for a missing or broken file, as Godot).</summary>
        public static int LoadThreadedRequest(string path, string typeHint = "", bool useSubThreads = false, int cacheMode = CACHE_MODE_REUSE)
        {
            path = Normalize(path);
            bool main = PlatformHost.IsMainThread;      // (also pins PlatformHost's main thread before any worker runs)
            ThreadLoad tl;
            lock (_threadLoads)
            {
                if (_threadLoads.TryGetValue(path, out tl)) { tl.requests++; return GD.OK; }
                tl = new ThreadLoad { path = path, requests = 1 };
                _threadLoads[path] = tl;
            }
            var cached = cacheMode == CACHE_MODE_REUSE ? Cached(path) : null;
            if (cached != null) Finish(tl, cached);
            else if (LoadsOnThread(path))
                System.Threading.Tasks.Task.Run(() =>
                {
                    Resource r = null;
                    try { r = LoadUncached(path); }
                    catch (Exception e) { GD.PushError("load_threaded_request(" + path + "): " + e); }
                    if (r != null) AddToCache(path, r);
                    Finish(tl, r);
                });
            else tl.onMain = true;
            return GD.OK;
        }

        static bool LoadsOnThread(string path)
        {
#if FB3D
            if (BakedLoader.Handles(path)) return true;
#endif
            return CanLoadOnThread != null && CanLoadOnThread(path);
        }

        static void Finish(ThreadLoad tl, Resource r)
        {
            tl.result = r;
            tl.status = r != null ? THREAD_LOAD_LOADED : THREAD_LOAD_FAILED;
            tl.done.Set();
        }

        static ThreadLoad GetThreadLoad(string path)
        {
            lock (_threadLoads) return _threadLoads.TryGetValue(path, out var tl) ? tl : null;
        }

        /// <summary>Runs a main-thread load now (the request was for a host format).</summary>
        static void RunOnMainIfPending(ThreadLoad tl)
        {
            if (!tl.onMain || tl.done.IsSet) return;
            lock (tl)
            {
                if (tl.done.IsSet) return;
                Resource r = null;
                try { r = Cached(tl.path) ?? LoadUncached(tl.path); }
                catch (Exception e) { GD.PushError("load_threaded_request(" + tl.path + "): " + e); }
                if (r != null) AddToCache(tl.path, r);
                Finish(tl, r);
            }
        }

        /// <summary>load_threaded_get_status(path, progress): THREAD_LOAD_*; progress[0] gets 0..1 when an Array is passed.</summary>
        public static int LoadThreadedGetStatus(string path, GArray progress = null)
        {
            path = Normalize(path);
            MainThread.Flush();             // (serves workers waiting for the host)
            var tl = GetThreadLoad(path);
            int st = THREAD_LOAD_INVALID_RESOURCE;
            if (tl != null)
            {
                if (PlatformHost.IsMainThread) RunOnMainIfPending(tl);
                st = tl.status;
            }
            if (progress != null)
            {
                if (progress.Size() < 1) progress.Resize(1);
                progress[0] = st == THREAD_LOAD_LOADED ? 1.0 : 0.0;
            }
            return st;
        }

        /// <summary>load_threaded_get(path): waits for the load and returns the resource (null if it failed or was never
        /// requested); the request is released, as Godot.</summary>
        public static Resource LoadThreadedGet(string path)
        {
            path = Normalize(path);
            var tl = GetThreadLoad(path);
            if (tl == null)
            {
                GD.PushError("Attempted to load a resource already loaded or not requested (load_threaded_get): " + path);
                return null;
            }
            if (PlatformHost.IsMainThread) RunOnMainIfPending(tl);
            WaitPumping(tl.done);
            lock (_threadLoads)
            {
                if (--tl.requests <= 0 && _threadLoads.TryGetValue(path, out var cur) && cur == tl) _threadLoads.Remove(path);
            }
            return tl.result;
        }

        public static T LoadThreadedGet<T>(string path) where T : Resource => LoadThreadedGet(path) as T;

        /// <summary>load(path) while that path loads on a thread: the thread's result (waited for), or false.</summary>
        static bool JoinThreadLoad(string path, out Resource r)
        {
            r = null;
            var tl = GetThreadLoad(path);
            if (tl == null) return false;
            if (PlatformHost.IsMainThread) RunOnMainIfPending(tl);
            else if (tl.onMain && !tl.done.IsSet) return false;
            WaitPumping(tl.done);
            r = tl.result;
            return true;
        }

        /// <summary>Waits for an event; on the main thread, runs the work workers post meanwhile (no deadlock when a
        /// worker waits for the host).</summary>
        static void WaitPumping(ManualResetEventSlim ev)
        {
            if (!PlatformHost.IsMainThread) { ev.Wait(); return; }
            while (!ev.Wait(1)) MainThread.Flush();
        }

        /// <summary>Runs f on the main thread: directly when already there, otherwise posted (MainThread) and waited for.</summary>
        public static T OnMainThread<T>(Func<T> f)
        {
            if (PlatformHost.IsMainThread) return f();
            T result = default;
            Exception err = null;
            using (var ev = new ManualResetEventSlim(false))
            {
                MainThread.Post(_ =>
                {
                    try { result = f(); }
                    catch (Exception e) { err = e; }
                    finally { ev.Set(); }
                }, null);
                ev.Wait();
            }
            if (err != null) throw new Exception("main-thread call failed", err);
            return result;
        }

        /// <summary>A res:// file's bytes from the host, from any thread.</summary>
        public static byte[] ReadHostFile(string path) => Host == null ? null : OnMainThread(() => Host.ReadFile(path));
    }
}
