// Fatebound engine services (Unity port): Godot's OS, Engine, ClassDB, Performance and Logger singletons. What the
// device decides comes from PlatformHost.Host (IPlatform); the rest is plain .NET:
//  - OS: names, locale, environment variables (the game's test hooks), user/cache dirs, threads, loggers.
//  - Engine: the frame counters and time scale of the running SceneTree, max_fps through the host, a singleton
//    registry the host fills (Android plugins re-implemented in C#: "GodotGooglePlayBilling"...; empty by default).
//  - ClassDB: a registry of classes the host can instantiate / call statics on by name (empty: class_exists is false).
//  - Logger / OS.add_logger: a Logger receives print() lines and push_error / push_warning / exceptions, as Godot's
//    script loggers do (an exception from game code counts as ERROR_TYPE_SCRIPT, the port's script error).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    /// <summary>Godot's Logger: override _LogError / _LogMessage and register with OS.AddLogger.</summary>
    public partial class Logger
    {
        public const int ERROR_TYPE_ERROR = 0, ERROR_TYPE_WARNING = 1, ERROR_TYPE_SCRIPT = 2, ERROR_TYPE_SHADER = 3;

        public virtual void _LogError(string function, string file, int line, string code, string rationale, bool editorNotify, int errorType, GArray scriptBacktraces) { }
        /// <summary>A printed line (with its "\n"); error: it went to stderr (printerr).</summary>
        public virtual void _LogMessage(string message, bool error) { }
    }

    public static partial class OS
    {
        // ------------------------------------------------------------------ the device
        public static string GetName() => PlatformHost.Host.OSName;
        public static string GetModelName() => PlatformHost.Host.ModelName;
        public static string GetVersion() => PlatformHost.Host.OSVersion;
        public static string GetDistributionName() => PlatformHost.Host.OSName == "Linux" ? "Linux" : PlatformHost.Host.OSName;
        public static string GetLocale() => PlatformHost.Host.Locale;

        /// <summary>get_locale_language(): the language part of the locale ("en_US" -> "en").</summary>
        public static string GetLocaleLanguage()
        {
            string l = GetLocale();
            int i = l.IndexOf('_');
            return i >= 0 ? l.Substring(0, i) : l;
        }

        public static bool HasFeature(string tag) => PlatformHost.Host.HasFeature(tag);
        public static string GetUniqueId() => PlatformHost.Host.UniqueId;
        public static int GetProcessorCount() => PlatformHost.Host.ProcessorCount;
        public static string GetProcessorName() => "";
        public static bool IsDebugBuild() => PlatformHost.Host.IsDebugBuild;
        public static string[] GetCmdlineArgs() => PlatformHost.Host.CmdlineArgs;

        /// <summary>get_cmdline_user_args(): the arguments after "--" or "++".</summary>
        public static string[] GetCmdlineUserArgs()
        {
            var a = GetCmdlineArgs();
            int i = Array.FindIndex(a, x => x == "--" || x == "++");
            if (i < 0) return Array.Empty<string>();
            var r = new string[a.Length - i - 1];
            Array.Copy(a, i + 1, r, 0, r.Length);
            return r;
        }

        public static string GetUserDataDir() => PlatformHost.Host.UserDataDir;
        public static string GetDataDir() => PlatformHost.Host.UserDataDir;
        public static string GetCacheDir() => PlatformHost.Host.CacheDir;
        public static string GetConfigDir() => PlatformHost.Host.UserDataDir;
        public static bool IsUserfsPersistent() => true;
        public static int ShellOpen(string uri) => PlatformHost.Host.ShellOpen(uri);
        public static int ShellShowInFileManager(string path, bool openFolder = true) => PlatformHost.Host.ShellOpen(ProjectSettings.GlobalizePath(path));
        public static bool RequestPermission(string name) => PlatformHost.Host.RequestPermission(name);
        public static bool RequestPermissions() => PlatformHost.Host.RequestPermissions();
        public static string[] GetGrantedPermissions() => PlatformHost.Host.GrantedPermissions();
        public static void RevokeGrantedPermissions() { }
        public static long GetStaticMemoryUsage() => PlatformHost.Host.StaticMemoryUsage;
        public static long GetStaticMemoryPeakUsage() => PlatformHost.Host.StaticMemoryUsage;
        public static GDict GetMemoryInfo() => new GDict { { "physical", -1 }, { "free", -1 }, { "available", -1 }, { "stack", -1 } };
        public static string GetExecutablePath()
        {
            try { return Process.GetCurrentProcess().MainModule?.FileName ?? ""; }
            catch (Exception) { return ""; }
        }

        public static int GetProcessId() => Process.GetCurrentProcess().Id;
        public static bool IsStdoutVerbose() => false;

        /// <summary>Running programs is not available in the port: -1, as a failed execute().</summary>
        public static int Execute(string path, string[] arguments, GArray output = null, bool readStderr = false, bool openConsole = false) => -1;
        public static int CreateProcess(string path, string[] arguments, bool openConsole = false) => -1;
        public static int Kill(int pid) => GD.FAILED;

        // ------------------------------------------------------------------ environment
        public static bool HasEnvironment(string name) => !string.IsNullOrEmpty(name) && PlatformHost.Host.GetEnv(name) != null;

        /// <summary>get_environment(name): "" when it isn't set.</summary>
        public static string GetEnvironment(string name) => (string.IsNullOrEmpty(name) ? null : PlatformHost.Host.GetEnv(name)) ?? "";

        public static void SetEnvironment(string name, string value)
        {
            if (string.IsNullOrEmpty(name)) { GD.PushError("Can't set environment variable: Variable name is empty."); return; }
            if (name.Contains("=")) { GD.PushError("Can't set environment variable: Variable name \"" + name + "\" contains \"=\"."); return; }
            PlatformHost.Host.SetEnv(name, value ?? "");
        }

        public static void UnsetEnvironment(string name)
        {
            if (string.IsNullOrEmpty(name)) { GD.PushError("Can't unset environment variable: Variable name is empty."); return; }
            PlatformHost.Host.UnsetEnv(name);
        }

        // ------------------------------------------------------------------ threads and time
        public static void DelayMsec(long msec) { if (msec > 0) System.Threading.Thread.Sleep((int)Math.Min(msec, int.MaxValue)); }
        public static void DelayUsec(long usec) { if (usec > 0) System.Threading.Thread.Sleep((int)Math.Min(usec / 1000, int.MaxValue)); }

        static long _nextThreadId = 1;
        [ThreadStatic] static long _threadId;

        /// <summary>get_thread_caller_id(): 1 on the main thread (the one that called PlatformHost.Init), then 2, 3... for
        /// other threads in the order they first ask.</summary>
        public static long GetThreadCallerId()
        {
            if (PlatformHost.IsMainThread) return 1;
            if (_threadId == 0) _threadId = Interlocked.Increment(ref _nextThreadId);
            return _threadId;
        }

        public static long GetMainThreadId() => 1;

        // ------------------------------------------------------------------ loggers
        static readonly List<Logger> _loggers = new List<Logger>();
        static Action<string> _prevPrint, _prevError, _prevWarning;
        static bool _hooked;
        [ThreadStatic] static bool _inLogger;

        /// <summary>add_logger(logger): it receives every print line and error from now on.</summary>
        public static void AddLogger(Logger logger)
        {
            if (logger == null) return;
            lock (_loggers)
            {
                if (!_loggers.Contains(logger)) _loggers.Add(logger);
                if (_hooked) return;
                _hooked = true;
                _prevPrint = GD.PrintSink;
                _prevError = GD.ErrorSink;
                _prevWarning = GD.WarningSink;
                GD.PrintSink = s => { _prevPrint?.Invoke(s); Dispatch(s, 0); };
                GD.ErrorSink = s => { _prevError?.Invoke(s); Dispatch(s, 1); };
                GD.WarningSink = s => { _prevWarning?.Invoke(s); Dispatch(s, 2); };
            }
        }

        /// <summary>An error or warning from the host engine itself (not from the game's print / push_error): handed to
        /// the loggers as Godot hands them its own engine errors.</summary>
        public static void LogHostMessage(string message, bool warning) => Dispatch(message, warning ? 2 : 1);

        public static void RemoveLogger(Logger logger)
        {
            lock (_loggers) _loggers.Remove(logger);
        }

        static void Dispatch(string s, int kind)
        {
            if (_inLogger) return;          // a logger printing doesn't log itself again
            Logger[] ls;
            lock (_loggers)
            {
                if (_loggers.Count == 0) return;
                ls = _loggers.ToArray();
            }
            _inLogger = true;
            try
            {
                foreach (var l in ls)
                {
                    try
                    {
                        if (kind == 0) l._LogMessage(s + "\n", false);
                        else if (kind == 2) l._LogError("push_warning", "core/variant/variant_utility.cpp", 1033, s, "", false, Logger.ERROR_TYPE_WARNING, new GArray());
                        else if (IsException(s)) l._LogError(ExceptionSite(s), "", 0, FirstLine(s), "", false, Logger.ERROR_TYPE_SCRIPT, new GArray());
                        else l._LogError("push_error", "core/variant/variant_utility.cpp", 1023, s, "", false, Logger.ERROR_TYPE_ERROR, new GArray());
                    }
                    catch (Exception) { }
                }
            }
            finally { _inLogger = false; }
        }

        static string FirstLine(string s)
        {
            int i = s.IndexOf('\n');
            return (i < 0 ? s : s.Substring(0, i)).TrimEnd('\r');
        }

        static bool IsException(string s)
        {
            string f = FirstLine(s);
            int colon = f.IndexOf(':');
            string head = colon > 0 ? f.Substring(0, colon) : f;
            return head.EndsWith("Exception", StringComparison.Ordinal) && head.IndexOf(' ') < 0;
        }

        static string ExceptionSite(string s)
        {
            int at = s.IndexOf("\n   at ", StringComparison.Ordinal);
            if (at < 0) return "";
            int end = s.IndexOf('(', at);
            return end > at ? s.Substring(at + 7, end - at - 7) : "";
        }
    }

    public static partial class Engine
    {
        // ------------------------------------------------------------------ frames
        public static long GetProcessFrames() => SceneTree.Current != null ? (long)SceneTree.Current.Frame : 0;
        public static long GetFramesDrawn() => GetProcessFrames();

        public static long GetPhysicsFrames()
        {
            Track();
            return _physicsFrames;
        }

        public static double GetFramesPerSecond() => PlatformHost.Host.FramesPerSecond;

        public static int MaxFps
        {
            get => PlatformHost.Host.MaxFps;
            set => PlatformHost.Host.MaxFps = value;
        }

        static int _physicsTps = 60;

        public static int PhysicsTicksPerSecond
        {
            get => SceneTree.Current != null ? (int)Math.Round(SceneTree.Current.PhysicsTicksPerSecond) : _physicsTps;
            set
            {
                _physicsTps = Math.Max(1, value);
                if (SceneTree.Current != null) SceneTree.Current.PhysicsTicksPerSecond = _physicsTps;
            }
        }

        public static int MaxPhysicsStepsPerFrame = 8;
        public static double PhysicsJitterFix = 0.5;

        public static double TimeScale
        {
            get => SceneTree.Current != null ? SceneTree.Current.TimeScale : 1.0;
            set { if (SceneTree.Current != null) SceneTree.Current.TimeScale = value; }
        }

        public static bool IsEditorHint() => false;
        public static bool IsEmbeddedInEditor() => false;
        public static SceneTree GetMainLoop() => SceneTree.Current;

        // frame-rate meter: frames counted over the last second of real time
        static SceneTree _tracked;
        static long _physicsFrames, _fpsFrames, _fpsWindowStart;
        static double _fps = 1.0;

        /// <summary>The frames per second the default platform reports (measured on the current SceneTree).</summary>
        public static double MeasuredFps
        {
            get
            {
                Track();
                return _fps;
            }
        }

        static void Track()
        {
            var t = SceneTree.Current;
            if (t == null || t == _tracked) return;
            if (_tracked != null)
            {
                _tracked.ProcessFrame -= OnFrame;
                _tracked.PhysicsFrame -= OnPhysics;
            }
            _tracked = t;
            t.ProcessFrame += OnFrame;
            t.PhysicsFrame += OnPhysics;
            _fpsWindowStart = Time.GetTicksUsec();
            _fpsFrames = 0;
        }

        static void OnPhysics() => _physicsFrames++;

        static void OnFrame()
        {
            _fpsFrames++;
            long now = Time.GetTicksUsec();
            long dt = now - _fpsWindowStart;
            if (dt >= 1000000)
            {
                _fps = _fpsFrames * 1e6 / dt;
                _fpsFrames = 0;
                _fpsWindowStart = now;
            }
        }

        // ------------------------------------------------------------------ singletons (Android / iOS plugins)
        static readonly Dictionary<string, object> _singletons = new Dictionary<string, object>();

        /// <summary>The host's stand-ins for engine plugins ("GodotGooglePlayBilling"...).</summary>
        public static void RegisterSingleton(string name, object instance) { lock (_singletons) _singletons[name] = instance; }
        public static void UnregisterSingleton(string name) { lock (_singletons) _singletons.Remove(name); }
        public static bool HasSingleton(string name) { lock (_singletons) return _singletons.ContainsKey(name); }

        public static object GetSingleton(string name)
        {
            lock (_singletons)
            {
                if (_singletons.TryGetValue(name, out var o)) return o;
            }
            GD.PushError("Failed to retrieve non-existent singleton '" + name + "'.");
            return null;
        }

        public static string[] GetSingletonList() { lock (_singletons) return new List<string>(_singletons.Keys).ToArray(); }

        // ------------------------------------------------------------------ version
        /// <summary>The engine version the port reproduces (Godot 4.7.2-stable).</summary>
        public static GDict GetVersionInfo() => new GDict {
            { "major", 4 }, { "minor", 7 }, { "patch", 2 }, { "hex", 0x040702 }, { "status", "stable" }, { "build", "official" },
            { "hash", "ed1daf0bf001b61586d9930840f2f1394092c079" }, { "timestamp", 0 }, { "string", "4.7.2-stable (official)" } };

        public static GDict GetAuthorInfo() => new GDict();
        public static GDict GetLicenseInfo() => new GDict();
        public static string GetLicenseText() => "";
        public static string GetArchitectureName() => System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture == System.Runtime.InteropServices.Architecture.Arm64 ? "arm64" : "x86_64";

        // (Performance monitors the default platform reports for TIME_PROCESS / TIME_PHYSICS_PROCESS; a host that
        // measures its frame can set these)
        public static double LastProcessTime, LastPhysicsTime;
    }

    /// <summary>Godot's ClassDB as a registry: the host registers the classes (iOS StoreKit / Game Center stand-ins...)
    /// game code looks up by name. Nothing is registered by default.</summary>
    public static partial class ClassDB
    {
        sealed class Entry
        {
            public Func<object> Factory;
            public Func<string, Var[], Var> Statics;
        }

        static readonly Dictionary<string, Entry> _classes = new Dictionary<string, Entry>();

        /// <param name="factory">instantiate(name) (null: can't be instantiated)</param>
        /// <param name="statics">class_call_static(name, method, args...)</param>
        public static void Register(string name, Func<object> factory = null, Func<string, Var[], Var> statics = null)
        {
            lock (_classes) _classes[name] = new Entry { Factory = factory, Statics = statics };
        }

        public static void Unregister(string name) { lock (_classes) _classes.Remove(name); }

        static Entry Get(string name)
        {
            lock (_classes) return name != null && _classes.TryGetValue(name, out var e) ? e : null;
        }

        public static bool ClassExists(string name) => Get(name) != null;
        public static bool CanInstantiate(string name) => Get(name)?.Factory != null;

        public static object Instantiate(string name)
        {
            var e = Get(name);
            if (e?.Factory == null) { GD.PushError("Cannot instantiate class '" + name + "'."); return null; }
            return e.Factory();
        }

        public static Var ClassCallStatic(string name, string method, params Var[] args)
        {
            var e = Get(name);
            if (e?.Statics == null) { GD.PushError("Class '" + name + "' has no static method '" + method + "'."); return Var.Nil; }
            return e.Statics(method, args);
        }

        public static string[] GetClassList() { lock (_classes) return new List<string>(_classes.Keys).ToArray(); }
    }

    /// <summary>Godot's Performance monitors: the numbers come from the host (PlatformHost.Host.GetMonitor).</summary>
    public static partial class Performance
    {
        public const int TIME_FPS = 0, TIME_PROCESS = 1, TIME_PHYSICS_PROCESS = 2, TIME_NAVIGATION_PROCESS = 3, MEMORY_STATIC = 4,
            MEMORY_STATIC_MAX = 5, MEMORY_MESSAGE_BUFFER_MAX = 6, OBJECT_COUNT = 7, OBJECT_RESOURCE_COUNT = 8, OBJECT_NODE_COUNT = 9,
            OBJECT_ORPHAN_NODE_COUNT = 10, RENDER_TOTAL_OBJECTS_IN_FRAME = 11, RENDER_TOTAL_PRIMITIVES_IN_FRAME = 12,
            RENDER_TOTAL_DRAW_CALLS_IN_FRAME = 13, RENDER_VIDEO_MEM_USED = 14, RENDER_TEXTURE_MEM_USED = 15, RENDER_BUFFER_MEM_USED = 16,
            PHYSICS_2D_ACTIVE_OBJECTS = 17, PHYSICS_2D_COLLISION_PAIRS = 18, PHYSICS_2D_ISLAND_COUNT = 19, PHYSICS_3D_ACTIVE_OBJECTS = 20,
            PHYSICS_3D_COLLISION_PAIRS = 21, PHYSICS_3D_ISLAND_COUNT = 22, AUDIO_OUTPUT_LATENCY = 23;

        public static double GetMonitor(int monitor) => PlatformHost.Host.GetMonitor(monitor);

        static readonly Dictionary<string, Func<Var>> _custom = new Dictionary<string, Func<Var>>();
        public static void AddCustomMonitor(string id, Func<Var> callable) { lock (_custom) _custom[id] = callable; }
        public static void RemoveCustomMonitor(string id) { lock (_custom) _custom.Remove(id); }
        public static bool HasCustomMonitor(string id) { lock (_custom) return _custom.ContainsKey(id); }

        public static Var GetCustomMonitor(string id)
        {
            Func<Var> f;
            lock (_custom) _custom.TryGetValue(id, out f);
            return f != null ? f() : Var.Nil;
        }
    }
}
