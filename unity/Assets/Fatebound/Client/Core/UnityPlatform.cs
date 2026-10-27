// The device as the game's services see it (Fatebound.GUI.IPlatform), answering as Godot 4.7's Android build does:
// user:// is the app's internal files dir (Context.getFilesDir(), Godot's GodotIO.getDataDir) so existing saves are
// found, the model is Build.MODEL, the locale java.util.Locale.getDefault().toString(), the unique id ANDROID_ID,
// the version "<sdk>.<incremental>" (stock Android). Elsewhere (editor, desktop) Unity's equivalents.
using System;
using Fatebound.GUI;
using Fatebound.Sim;
using UnityEngine;
using Time = UnityEngine.Time;

namespace Fatebound.Client
{
    public sealed class UnityPlatform : DefaultPlatform
    {
        readonly bool _android = Application.platform == RuntimePlatform.Android;
        string _userDir, _cacheDir, _model, _version, _locale, _uniqueId;
        int _maxFps;
        double _fps;
        int _frames;
        double _fpsTime;

        public UnityPlatform()
        {
            // read once on the main thread (the JNI calls must not run on a worker)
            if (_android)
            {
                try
                {
                    using (var player = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
                    using (var activity = player.GetStatic<AndroidJavaObject>("currentActivity"))
                    {
                        using (var files = activity.Call<AndroidJavaObject>("getFilesDir")) _userDir = files.Call<string>("getAbsolutePath");
                        using (var cache = activity.Call<AndroidJavaObject>("getCacheDir")) _cacheDir = cache.Call<string>("getAbsolutePath");
                        using (var resolver = activity.Call<AndroidJavaObject>("getContentResolver"))
                        using (var secure = new AndroidJavaClass("android.provider.Settings$Secure"))
                            _uniqueId = secure.CallStatic<string>("getString", resolver, "android_id");
                    }
                    using (var build = new AndroidJavaClass("android.os.Build")) _model = build.GetStatic<string>("MODEL");
                    using (var ver = new AndroidJavaClass("android.os.Build$VERSION"))
                    {
                        int sdk = ver.GetStatic<int>("SDK_INT");
                        string inc = ver.GetStatic<string>("INCREMENTAL");
                        _version = string.IsNullOrEmpty(inc) ? sdk.ToString() : sdk + "." + inc;
                    }
                    using (var loc = new AndroidJavaClass("java.util.Locale"))
                    using (var def = loc.CallStatic<AndroidJavaObject>("getDefault"))
                        _locale = def.Call<string>("toString");
                }
                catch (Exception e)
                {
                    Debug.LogError("UnityPlatform: " + e);
                }
            }
            if (string.IsNullOrEmpty(_userDir)) _userDir = Application.persistentDataPath;
            if (string.IsNullOrEmpty(_cacheDir)) _cacheDir = Application.temporaryCachePath;
            if (string.IsNullOrEmpty(_model)) _model = SystemInfo.deviceModel;
            if (string.IsNullOrEmpty(_version)) _version = SystemInfo.operatingSystem;
            if (string.IsNullOrEmpty(_locale)) _locale = "en";
            if (_uniqueId == null) _uniqueId = _android ? "" : SystemInfo.deviceUniqueIdentifier;
            MaxFps = 0;
        }

        public override string OSName
        {
            get
            {
                switch (Application.platform)
                {
                    case RuntimePlatform.Android: return "Android";
                    case RuntimePlatform.IPhonePlayer: return "iOS";
                    case RuntimePlatform.WindowsPlayer:
                    case RuntimePlatform.WindowsEditor: return "Windows";
                    case RuntimePlatform.OSXPlayer:
                    case RuntimePlatform.OSXEditor: return "macOS";
                    default: return "Linux";
                }
            }
        }

        public override string DisplayName
        {
            get
            {
                switch (Application.platform)
                {
                    case RuntimePlatform.Android: return "Android";
                    case RuntimePlatform.IPhonePlayer: return "iOS";
                    case RuntimePlatform.WindowsPlayer:
                    case RuntimePlatform.WindowsEditor: return "Windows";
                    case RuntimePlatform.OSXPlayer:
                    case RuntimePlatform.OSXEditor: return "macOS";
                    default: return "X11";
                }
            }
        }

        public override string ModelName => _model;
        public override string OSVersion => _version;
        public override string Locale => _locale;
        public override string UserDataDir => _userDir;
        public override string CacheDir => _cacheDir;
        public override string UniqueId => _uniqueId;
        public override int ProcessorCount => SystemInfo.processorCount;
        public override bool IsDebugBuild => Debug.isDebugBuild;

        public override bool HasFeature(string tag)
        {
            if (!_android) return base.HasFeature(tag);
            switch (tag)
            {
                case "android":
                case "mobile":
                case "64":
                case "arm64":
                case "template":
                case "etc2":
                case "astc":
                case "single":
                    return true;
                case "debug": return Debug.isDebugBuild;
                case "release": return !Debug.isDebugBuild;
                case "template_debug": return Debug.isDebugBuild;
                case "template_release": return !Debug.isDebugBuild;
            }
            return false;
        }

        public override int ShellOpen(string uri)
        {
            Application.OpenURL(uri);
            return GD.OK;
        }

        public override bool RequestPermission(string name)
        {
#if UNITY_ANDROID
            if (!_android) return true;
            if (UnityEngine.Android.Permission.HasUserAuthorizedPermission(name)) return true;
            UnityEngine.Android.Permission.RequestUserPermission(name);
            return false;
#else
            return true;
#endif
        }

        public override long StaticMemoryUsage => GC.GetTotalMemory(false);

        /// <summary>Godot's Engine.get_frames_per_second(): frames counted over each second.</summary>
        public override double FramesPerSecond => _fps;

        /// <summary>Godot's max_fps (0 = no cap: Vulkan's FIFO vsync caps at the display rate) as Unity's frame rate.
        /// The cap itself, not clamped to the refresh rate Unity reports: Kevin's first match log (the 60 fps cap) never
        /// went over 30 fps -- the build's Optimized Frame Pacing on, under which Unity can report a 30 Hz display (and
        /// so a target of 30) and holds a frame that misses 60's 16.7 ms to 30 (a whole second refresh). Android shows
        /// a frame at the display's next refresh anyway, so a target over its rate costs nothing. No cap: the display's
        /// fastest mode (Android's default target, -1, is 30). Kept: Tick sets it again if anything resets it.</summary>
        public override int MaxFps
        {
            get => _maxFps;
            set
            {
                _maxFps = Math.Max(0, value);
                QualitySettings.vSyncCount = 0;
                _target = _maxFps > 0 ? _maxFps : Math.Max(60, FastestRefresh());
                Application.targetFrameRate = _target;
            }
        }

        int _target;

        /// <summary>The display's fastest refresh rate (its modes', Hz).</summary>
        public static int FastestRefresh()
        {
            double best = Screen.currentResolution.refreshRateRatio.value;
            foreach (var r in Screen.resolutions) best = Math.Max(best, r.refreshRateRatio.value);
            return Mathf.RoundToInt((float)best);
        }

        /// <summary>For the match log: the refresh rate now, the display's modes' rates, Unity's frame-rate target.</summary>
        public static string DisplayText()
        {
            var rates = new System.Collections.Generic.SortedSet<int>();
            foreach (var r in Screen.resolutions) rates.Add(Mathf.RoundToInt((float)r.refreshRateRatio.value));
            return "hz=" + Mathf.RoundToInt((float)Screen.currentResolution.refreshRateRatio.value) + " modes=" + string.Join("/", rates)
                + " target=" + Application.targetFrameRate;
        }

        public override Vec2i WindowSize => new Vec2i(Screen.width, Screen.height);

        public override double RefreshRate
        {
            get
            {
                var r = Screen.currentResolution.refreshRateRatio.value;
                return r > 0 ? r : 60.0;
            }
        }

        public override string ClipboardGet() => GUIUtility.systemCopyBuffer ?? "";
        public override void ClipboardSet(string text) => GUIUtility.systemCopyBuffer = text ?? "";

        public override bool HasDisplayFeature(int feature)
        {
            switch (feature)
            {
                case DisplayServer.FEATURE_TOUCHSCREEN: return UnityEngine.Input.touchSupported;
                case DisplayServer.FEATURE_MOUSE: return !_android;
                case DisplayServer.FEATURE_CLIPBOARD: return true;
                case DisplayServer.FEATURE_VIRTUAL_KEYBOARD: return TouchScreenKeyboard.isSupported;
                case DisplayServer.FEATURE_ORIENTATION: return _android;
                case DisplayServer.FEATURE_KEEP_SCREEN_ON: return _android;
                case DisplayServer.FEATURE_HIDPI: return true;
            }
            return false;
        }

        /// <summary>Once a frame (GuiCanvas): counts frames for FramesPerSecond.</summary>
        public void Tick()
        {
            if (_target > 0 && Application.targetFrameRate != _target) Application.targetFrameRate = _target;
            _frames++;
            double now = Time.realtimeSinceStartupAsDouble;
            if (_fpsTime == 0) _fpsTime = now;
            if (now - _fpsTime >= 1.0)
            {
                _fps = _frames / (now - _fpsTime);
                _frames = 0;
                _fpsTime = now;
            }
        }
    }
}
