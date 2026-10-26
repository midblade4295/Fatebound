// Fatebound engine services (Unity port): the rest of Godot's DisplayServer the game calls (the UI's part -- safe
// area, virtual keyboard, screen size -- is in GUI/Core/Input.cs). Answers come from PlatformHost.Host: the default is
// Godot's headless display server (name "headless", window 0x0, refresh rate -1, no features).
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public static partial class DisplayServer
    {
        public const int FEATURE_GLOBAL_MENU = 0, FEATURE_SUBWINDOWS = 1, FEATURE_TOUCHSCREEN = 2, FEATURE_MOUSE = 3,
            FEATURE_MOUSE_WARP = 4, FEATURE_CLIPBOARD = 5, FEATURE_VIRTUAL_KEYBOARD = 6, FEATURE_CURSOR_SHAPE = 7,
            FEATURE_CUSTOM_CURSOR_SHAPE = 8, FEATURE_NATIVE_DIALOG = 9, FEATURE_IME = 10, FEATURE_WINDOW_TRANSPARENCY = 11,
            FEATURE_HIDPI = 12, FEATURE_ICON = 13, FEATURE_NATIVE_ICON = 14, FEATURE_ORIENTATION = 15, FEATURE_SWAP_BUFFERS = 16,
            FEATURE_KEEP_SCREEN_ON = 17, FEATURE_CLIPBOARD_PRIMARY = 18, FEATURE_TEXT_TO_SPEECH = 19;

        /// <summary>get_name(): "headless" in tests, "Android" on the phone.</summary>
        public static string GetName() => PlatformHost.Host.DisplayName;
        public static bool HasFeature(int feature) => PlatformHost.Host.HasDisplayFeature(feature);
        /// <summary>window_get_size(): the window in pixels.</summary>
        public static Vec2i WindowGetSize(int windowId = 0) => PlatformHost.Host.WindowSize;
        public static double ScreenGetRefreshRate(int screen = -1) => PlatformHost.Host.RefreshRate;
        public static void ClipboardSet(string text) => PlatformHost.Host.ClipboardSet(text);
        public static string ClipboardGet() => PlatformHost.Host.ClipboardGet();
        public static bool ClipboardHas() => PlatformHost.Host.ClipboardGet().Length > 0;
    }
}
