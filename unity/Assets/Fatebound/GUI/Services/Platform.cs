// Fatebound engine services (Unity port): the one door to the device. Everything OS / Engine / Performance / the
// DisplayServer additions / FileAccess's user:// need from the platform goes through IPlatform. PlatformHost.Host is a
// DefaultPlatform (plain .NET, what the headless tests run on, answering as Godot's headless Linux build does) until
// the Unity client installs its own -- a DefaultPlatform subclass overriding what Unity knows -- with PlatformHost.Init(host)
// at startup, before any game code runs.
//
// PlatformHost.Init (or the first touch of Platform) also registers the GUI's value types with the Variant marshaller
// (Col -> Color, Rect2 -> Rect2, Xform2 -> Transform2D), so var_to_bytes / var_to_str / bytes_to_var know them.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    /// <summary>What the services need from the device. DefaultPlatform implements all of it in .NET; a host overrides
    /// what it knows better.</summary>
    public interface IPlatform
    {
        /// <summary>OS.get_name(): "Android", "Linux", "Windows", "macOS", "iOS".</summary>
        string OSName { get; }
        /// <summary>DisplayServer.get_name(): "headless" for tests, "Android" on the phone.</summary>
        string DisplayName { get; }
        string ModelName { get; }
        string OSVersion { get; }
        /// <summary>OS.get_locale(): "en_US" style.</summary>
        string Locale { get; }
        /// <summary>Where user:// lives. On Android this must be the app's internal files dir (Context.getFilesDir(),
        /// what Godot used), so players' existing saves are found.</summary>
        string UserDataDir { get; }
        string CacheDir { get; }
        string UniqueId { get; }
        int ProcessorCount { get; }
        bool IsDebugBuild { get; }
        string[] CmdlineArgs { get; }
        /// <summary>OS.has_feature(tag): "android", "mobile", "pc", "linux", "debug" / "release", "64", "arm64"...</summary>
        bool HasFeature(string tag);
        /// <summary>An environment variable, or null when it isn't set (the game uses them as test hooks).</summary>
        string GetEnv(string name);
        void SetEnv(string name, string value);
        void UnsetEnv(string name);
        /// <summary>OS.shell_open: an Error code.</summary>
        int ShellOpen(string uri);
        bool RequestPermission(string name);
        bool RequestPermissions();
        string[] GrantedPermissions();
        long StaticMemoryUsage { get; }
        /// <summary>Performance.get_monitor(monitor): the engine's numbers (0 when unknown).</summary>
        double GetMonitor(int monitor);
        /// <summary>Engine.get_frames_per_second().</summary>
        double FramesPerSecond { get; }
        /// <summary>Engine.max_fps (0 = uncapped): the host applies it (Application.targetFrameRate).</summary>
        int MaxFps { get; set; }
        Vec2i WindowSize { get; }
        double RefreshRate { get; }
        string ClipboardGet();
        void ClipboardSet(string text);
        /// <summary>DisplayServer.has_feature(DisplayServer.FEATURE_*).</summary>
        bool HasDisplayFeature(int feature);
    }

    /// <summary>IPlatform in plain .NET, answering as Godot's headless desktop build does (display "headless", window
    /// 0x0, refresh rate -1). Subclass and override for a real device.</summary>
    public partial class DefaultPlatform : IPlatform
    {
        readonly string _userDir;
        string _clipboard = "";
        int _maxFps;

        /// <param name="userDataDir">user:// (default: Godot's desktop location for the project name).</param>
        public DefaultPlatform(string userDataDir = null) { _userDir = userDataDir; }

        public virtual string OSName
        {
            get
            {
                if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) return "Windows";
                if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX)) return "macOS";
                return "Linux";
            }
        }

        public virtual string DisplayName => "headless";
        public virtual string ModelName => "GenericDevice";

        public virtual string OSVersion
        {
            get
            {
                try
                {
                    if (File.Exists("/etc/os-release"))
                        foreach (var l in File.ReadAllLines("/etc/os-release"))
                            if (l.StartsWith("VERSION_ID=", StringComparison.Ordinal)) return l.Substring(11).Trim('"');
                }
                catch (Exception) { }
                return System.Environment.OSVersion.Version.ToString();
            }
        }

        /// <summary>As OS_Unix: LANG without its encoding ("en_US.UTF-8" -> "en_US"), "en" when unset.</summary>
        public virtual string Locale
        {
            get
            {
                string l = System.Environment.GetEnvironmentVariable("LANG");
                if (string.IsNullOrEmpty(l)) return "en";
                int dot = l.IndexOf('.');
                if (dot >= 0) l = l.Substring(0, dot);
                if (l == "C" || l == "POSIX" || l.Length == 0) return "en";
                return l;
            }
        }

        public virtual string UserDataDir
        {
            get
            {
                if (_userDir != null) return _userDir;
                string name = ProjectSettings.GetSetting("application/config/name", "").AsString();
                name = name.Length == 0 ? "[unnamed project]" : name.ValidateFilename();
                if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                    return Path.Combine(System.Environment.GetFolderPath(System.Environment.SpecialFolder.ApplicationData), "Godot", "app_userdata", name).Replace('\\', '/');
                if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                    return Path.Combine(Home, "Library/Application Support/Godot/app_userdata", name);
                string data = System.Environment.GetEnvironmentVariable("XDG_DATA_HOME");
                if (string.IsNullOrEmpty(data)) data = Path.Combine(Home, ".local/share");
                return Path.Combine(data, "godot/app_userdata", name);
            }
        }

        static string Home => System.Environment.GetEnvironmentVariable("HOME") ?? System.Environment.GetFolderPath(System.Environment.SpecialFolder.UserProfile);

        public virtual string CacheDir
        {
            get
            {
                string c = System.Environment.GetEnvironmentVariable("XDG_CACHE_HOME");
                if (!string.IsNullOrEmpty(c)) return c;
                if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) return Path.GetTempPath().TrimEnd('\\', '/').Replace('\\', '/');
                return Path.Combine(Home, ".cache");
            }
        }

        public virtual string UniqueId
        {
            get
            {
                foreach (var p in new[] { "/etc/machine-id", "/var/lib/dbus/machine-id" })
                {
                    try { if (File.Exists(p)) return File.ReadAllText(p).Trim(); }
                    catch (Exception) { }
                }
                return "";
            }
        }

        public virtual int ProcessorCount => System.Environment.ProcessorCount;
        public virtual bool IsDebugBuild => true;
        public virtual string[] CmdlineArgs => Array.Empty<string>();

        public virtual bool HasFeature(string tag)
        {
            switch (tag)
            {
                case "pc": return true;
                case "linux": return OSName == "Linux";
                case "windows": return OSName == "Windows";
                case "macos": return OSName == "macOS";
                case "debug": return IsDebugBuild;
                case "release": return !IsDebugBuild;
                case "64": return System.Environment.Is64BitProcess;
                case "32": return !System.Environment.Is64BitProcess;
                case "x86_64": return RuntimeInformation.ProcessArchitecture == Architecture.X64;
                case "arm64": return RuntimeInformation.ProcessArchitecture == Architecture.Arm64;
                case "single": return true;
            }
            return false;
        }

        public virtual string GetEnv(string name) => System.Environment.GetEnvironmentVariable(name);
        public virtual void SetEnv(string name, string value) => System.Environment.SetEnvironmentVariable(name, value);
        public virtual void UnsetEnv(string name) => System.Environment.SetEnvironmentVariable(name, null);

        public virtual int ShellOpen(string uri)
        {
            try
            {
                ProcessStartInfo psi;
                if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) psi = new ProcessStartInfo(uri) { UseShellExecute = true };
                else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX)) psi = new ProcessStartInfo("open", uri) { UseShellExecute = false };
                else psi = new ProcessStartInfo("xdg-open", uri) { UseShellExecute = false };
                Process.Start(psi);
                return GD.OK;
            }
            catch (Exception) { return GD.ERR_CANT_OPEN; }
        }

        public virtual bool RequestPermission(string name) => true;
        public virtual bool RequestPermissions() => true;
        public virtual string[] GrantedPermissions() => Array.Empty<string>();
        public virtual long StaticMemoryUsage => GC.GetTotalMemory(false);

        public virtual double GetMonitor(int monitor)
        {
            switch (monitor)
            {
                case Performance.TIME_FPS: return FramesPerSecond;
                case Performance.TIME_PROCESS: return Engine.LastProcessTime;
                case Performance.TIME_PHYSICS_PROCESS: return Engine.LastPhysicsTime;
                case Performance.MEMORY_STATIC: return StaticMemoryUsage;
                case Performance.OBJECT_NODE_COUNT: return SceneTree.Current != null ? SceneTree.Current.TreeOrder().Count : 0;
            }
            return 0;
        }

        public virtual double FramesPerSecond => Engine.MeasuredFps;

        public virtual int MaxFps
        {
            get => _maxFps;
            set => _maxFps = Math.Max(0, value);
        }

        public virtual Vec2i WindowSize => new Vec2i(0, 0);
        public virtual double RefreshRate => -1.0;
        public virtual string ClipboardGet() => _clipboard;
        public virtual void ClipboardSet(string text) => _clipboard = text ?? "";
        public virtual bool HasDisplayFeature(int feature) => false;
    }

    /// <summary>The current IPlatform (a DefaultPlatform until the host sets its own).</summary>
    public static partial class PlatformHost
    {
        static IPlatform _host;
        static int _mainThread;

        static PlatformHost()
        {
            _mainThread = System.Threading.Thread.CurrentThread.ManagedThreadId;
            RegisterValueTypes();
        }

        public static IPlatform Host
        {
            get => _host ?? (_host = new DefaultPlatform());
            set => _host = value;
        }

        /// <summary>Startup: installs the host (null: DefaultPlatform), marks the calling thread as the main thread
        /// (OS.get_thread_caller_id() == 1 there) and registers the GUI value types with the marshaller.</summary>
        public static void Init(IPlatform host = null)
        {
            _host = host ?? new DefaultPlatform();
            _mainThread = System.Threading.Thread.CurrentThread.ManagedThreadId;
        }

        public static bool IsMainThread => System.Threading.Thread.CurrentThread.ManagedThreadId == _mainThread;
        internal static int MainThreadManagedId => _mainThread;

        static bool _registered;

        /// <summary>Col, Rect2 and Xform2 as Godot's Color, Rect2 and Transform2D in var_to_bytes / var_to_str.</summary>
        public static void RegisterValueTypes()
        {
            if (_registered) return;
            _registered = true;
            GMarshal.Register<Col>(GD.TYPE_COLOR, c => new double[] { c.r, c.g, c.b, c.a },
                d => new Col((float)d[0], (float)d[1], (float)d[2], (float)d[3]));
            GMarshal.Register<Rect2>(GD.TYPE_RECT2, r => new double[] { r.position.x, r.position.y, r.size.x, r.size.y },
                d => new Rect2(new Vec2((float)d[0], (float)d[1]), new Vec2((float)d[2], (float)d[3])));
            GMarshal.Register<Xform2>(GD.TYPE_TRANSFORM2D, t => new double[] { t.x.x, t.x.y, t.y.x, t.y.y, t.origin.x, t.origin.y },
                d => new Xform2(new Vec2((float)d[0], (float)d[1]), new Vec2((float)d[2], (float)d[3]), new Vec2((float)d[4], (float)d[5])));
        }
    }
}
