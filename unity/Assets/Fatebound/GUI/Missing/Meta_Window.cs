// Facade addition (the meta/ porter, Fatebound Unity port): the bits of Godot's Window the game asks of its root --
// get_window().has_focus() and the root window's focus_entered / focus_exited signals (scripts/native_audio.gd: stop
// every sound when the app loses focus, play none without it). The port's root is a Viewport (there is no Window class),
// so these are on Viewport and Node.GetWindow() is the tree's root.
//  - has_focus(): Window::has_focus asks DisplayServer::window_is_focused, which Godot's Android (and headless) display
//    server answers `true` always -- DisplayServer.WindowIsFocused does the same.
//  - focus_entered / focus_exited: Window::_event_callback(WINDOW_EVENT_FOCUS_IN / _OUT) -- on Android sent by
//    OS_Android::main_loop_focusin / focusout (the app coming to the front / going away). The Unity client calls
//    SendWindowFocus(bool) from OnApplicationFocus. (Godot also propagates NOTIFICATION_WM_WINDOW_FOCUS_IN / _OUT to
//    the window's nodes; nothing in the game listens for those, and this doesn't send them.)
using System;

namespace Fatebound.GUI
{
    public static partial class DisplayServer
    {
        /// <summary>window_is_focused(): true, as Godot's Android and headless display servers answer.</summary>
        public static bool WindowIsFocused(int windowId = 0) => true;
    }

    public partial class Node
    {
        /// <summary>get_window(): the window this node is in -- the tree's root (the port's only window).</summary>
        public Viewport GetWindow() => GetTree()?.Root;
    }

    public partial class Viewport
    {
        bool _windowFocused;

        /// <summary>The root window's focus_entered / focus_exited signals (the app came to the front / went away).</summary>
        public event Action FocusEntered, FocusExited;

        /// <summary>Window.has_focus().</summary>
        public bool HasFocus() => DisplayServer.WindowIsFocused();

        /// <summary>The host: the window got (true) or lost (false) the focus -- WINDOW_EVENT_FOCUS_IN / _OUT.</summary>
        public void SendWindowFocus(bool focusIn)
        {
            _windowFocused = focusIn;
            if (focusIn) FocusEntered?.Invoke();
            else FocusExited?.Invoke();
        }
    }
}
