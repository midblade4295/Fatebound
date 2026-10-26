// Ported from godot/scripts/siege/asset_cache.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;

namespace Fatebound.Game
{
    // Shared resource cache for Siege: models (PackedScene), textures and baked animation libraries, loaded once per
    // session (was the dice-era kaykit_stage.gd's scene cache; 0.31.78: any resource, so the background preload covers the
    // textures and the Meshy bodies' animations too, which used to load synchronously -- and the first Crusader or Berserker
    // of a match froze the phone for a moment).
    public static class AssetCache
    {
        public static GDict _cache = new GDict();       // path -> Resource (null when the file is missing)

        public static Resource Res(string path)
        {
            if (!_cache.Has(path))
            {
                Resource got = Finish(path);
                _cache[path] = Var.Of(got != null ? got : (ResourceLoader.Exists(path) ? ResourceLoader.Load(path) : null));
            }
            return _cache[path].As<Resource>();
        }

        public static PackedScene Scene(string path)
        {
            return Res(path) as PackedScene;
        }

        public static Texture2D Texture(string path)
        {
            return Res(path) as Texture2D;
        }

        public static bool Has(string path)
        {
            return _cache.Has(path);
        }

        // ---- background preload (0.31.8: "the game takes long to start after pressing Play") ----
        // At app start the menus are idle, so everything a match needs is loaded on a thread then (the list is written by
        // tools/preload_list.gd: whatever a match build asked the cache for, every class body with its animations, and the
        // start-up cache). Pressing Play then finds it all here; a path still loading is waited for (finish).
        //
        // 0.31.91: ONE load at a time, no sub-threads. Kevin's S21 froze on the Godot splash on the first start of a fresh
        // install (Vulkan; the testers' "frozen splash" phones were fresh installs too). Reproduced on desktop Vulkan with an
        // empty shader cache: the start hangs forever, every thread asleep. Godot 4.7.2, scene_shader_forward_mobile.cpp
        // ShaderData::is_valid() holds SceneShaderForwardMobile::singleton_mutex while ShaderRD::version_is_valid() waits for
        // the shader's compile tasks (a WorkerThreadPool group, shader_rd.cpp _compile_version_end). Those tasks need a free
        // pool thread, but the ~200 parallel loads (each waiting load lets another start) filled every pool thread with loads
        // blocked on that same mutex. With a warm shader cache nothing compiles, so it only hit first starts (and would hit
        // after a shader change). With one load in flight the pool always has a free thread for the compile.
        public const string PRELOAD_LIST = "res://content/preload.json";   // (.txt files are not exported; JSON is. 0.31.95: in the base build, not a pack)
        public static GArray _queue = new GArray();            // paths not requested yet, in list order
        public static string _loading = "";                    // the one path loading on a pool thread, or ""

        public static void PreloadAsync(GArray first = null)
        {
            first ??= new GArray();
            // first: paths loaded before the list (0.31.141: the match's own script, no longer compiled at start-up)
            if (!_queue.IsEmpty() || _loading != "" || !FileAccess.FileExists(PRELOAD_LIST))
                return;
            Var parsed = JSON.ParseString(FileAccess.GetFileAsString(PRELOAD_LIST));
            if (!parsed.IsArr)
                return;
            var all = first.Duplicate();
            all.AppendArray(parsed.A);
            foreach (var line in all)
            {
                var path = GD.Str(line).StripEdges();
                if (path == "" || _cache.Has(path) || _queue.Has(path) || !ResourceLoader.Exists(path))
                    continue;
                _queue.Append(path);
            }
            _Next();
        }

        public static void _Next()
        {
            // Request the next queued path (one in flight at a time).
            while (_loading == "" && !_queue.IsEmpty())
            {
                string path = _queue.PopFront().AsString();
                if (_cache.Has(path))
                    continue;
                if (ResourceLoader.LoadThreadedRequest(path, "", false) == GD.OK)
                    _loading = path;
            }
        }

        public static void Poll()
        {
            // Move a finished load into the cache and start the next (call every frame while in the menus).
            if (_loading != "")
            {
                var st = ResourceLoader.LoadThreadedGetStatus(_loading);
                if (st == ResourceLoader.THREAD_LOAD_LOADED)
                {
                    _cache[_loading] = Var.Of(ResourceLoader.LoadThreadedGet(_loading));
                    _loading = "";
                }
                else if (st == ResourceLoader.THREAD_LOAD_FAILED || st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE)
                    _loading = "";
            }
            _Next();
        }

        public static void Drain()
        {
            // 0.31.141: the app is closing: finish the one load in flight and drop the rest (the queue now holds scripts too, and
            // a script half-compiled on a thread while the engine shuts down can't resolve what it uses)
            _queue.Clear();
            if (_loading != "")
            {
                var p = _loading;
                _loading = "";
                _cache[p] = Var.Of(ResourceLoader.LoadThreadedGet(p));
            }
        }

        public static int Pending()
        {
            return _queue.Size() + (_loading != "" ? 1 : 0);
        }

        public static Resource Finish(string path)
        {
            // Needed right now: wait for it if it is the one loading; if it is only queued, the caller loads it directly.
            if (path == _loading)
            {
                _loading = "";
                return ResourceLoader.LoadThreadedGet(path);
            }
            _queue.Erase(path);
            return null;
        }
    }
}
