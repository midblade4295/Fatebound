// Fatebound GUI (Unity port): Godot's input events and the Input singleton -- touches turned into mouse events the way
// Input::parse_input_event emulates them (index 0 only, the mouse event first, device DEVICE_ID_EMULATION), actions
// for the back button, button state, vibration. The host feeds raw touches/mouse/keys; the root Viewport routes them.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public enum MouseButton { None = 0, Left = 1, Right = 2, Middle = 3, WheelUp = 4, WheelDown = 5, WheelLeft = 6, WheelRight = 7 }

    [Flags]
    public enum MouseButtonMask { None = 0, Left = 1, Right = 2, Middle = 4 }

    public enum Key
    {
        None = 0, Escape = 4194305, Tab = 4194306, Backspace = 4194308, Enter = 4194309, KpEnter = 4194310, Delete = 4194312,
        Home = 4194317, End = 4194318, Left = 4194319, Up = 4194320, Right = 4194321, Down = 4194322, PageUp = 4194323,
        PageDown = 4194324, Shift = 4194325, Ctrl = 4194326, Alt = 4194328, F1 = 4194332, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
        Back = 4194376, Space = 32, A = 65, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
        Key0 = 48, Key1, Key2, Key3, Key4, Key5, Key6, Key7, Key8, Key9,
    }

    public abstract class InputEvent
    {
        public const int DEVICE_ID_EMULATION = -1;
        public int Device;

        public virtual bool IsPressed() => false;
        public bool IsReleased() => IsActionType() && !IsPressed() && !(this is InputEventMouseMotion) && !(this is InputEventScreenDrag);
        public virtual bool IsEcho() => false;
        public virtual bool IsActionType() => false;

        public bool IsAction(string action, bool exactMatch = false) => InputMap.EventIsAction(this, action, exactMatch);

        public bool IsActionPressed(string action, bool allowEcho = false, bool exactMatch = false) =>
            IsPressed() && (allowEcho || !IsEcho()) && InputMap.EventIsAction(this, action, exactMatch);

        public bool IsActionReleased(string action, bool exactMatch = false) =>
            !IsPressed() && InputMap.EventIsAction(this, action, exactMatch);

        public InputEvent Duplicate() => (InputEvent)MemberwiseClone();

        /// <summary>xformed_by: a copy with positions (and vectors) mapped through `xf` (offset applied to positions).</summary>
        public virtual InputEvent XformedBy(Xform2 xf, Vec2 localOfs = default) => Duplicate();

        public override string ToString() => GetType().Name;
    }

    public abstract class InputEventWithModifiers : InputEvent
    {
        public bool ShiftPressed, CtrlPressed, AltPressed, MetaPressed;
        public bool IsShiftPressed() => ShiftPressed;
    }

    public abstract class InputEventMouse : InputEventWithModifiers
    {
        public Vec2 Position, GlobalPosition;
        public MouseButtonMask ButtonMask;
        public MouseButtonMask GetButtonMask() => ButtonMask;
    }

    public sealed class InputEventMouseButton : InputEventMouse
    {
        public MouseButton ButtonIndex;
        public bool Pressed, DoubleClick, Canceled;
        public double Factor = 1.0;
        public override bool IsPressed() => Pressed;
        public override bool IsActionType() => true;

        public override InputEvent XformedBy(Xform2 xf, Vec2 localOfs = default)
        {
            var e = (InputEventMouseButton)Duplicate();
            e.Position = xf.Xform(Position + localOfs);
            return e;
        }
    }

    public sealed class InputEventMouseMotion : InputEventMouse
    {
        public Vec2 Relative, ScreenRelative, Velocity, ScreenVelocity, Tilt;
        public double Pressure;
        public bool PenInverted;

        public override InputEvent XformedBy(Xform2 xf, Vec2 localOfs = default)
        {
            var e = (InputEventMouseMotion)Duplicate();
            e.Position = xf.Xform(Position + localOfs);
            e.Relative = xf.BasisXform(Relative);
            e.Velocity = xf.BasisXform(Velocity);
            return e;
        }
    }

    public sealed class InputEventScreenTouch : InputEvent
    {
        public int Index;
        public Vec2 Position;
        public bool Pressed, Canceled, DoubleTap;
        public override bool IsPressed() => Pressed;
        public override bool IsActionType() => true;

        public override InputEvent XformedBy(Xform2 xf, Vec2 localOfs = default)
        {
            var e = (InputEventScreenTouch)Duplicate();
            e.Position = xf.Xform(Position + localOfs);
            return e;
        }
    }

    public sealed class InputEventScreenDrag : InputEvent
    {
        public int Index;
        public Vec2 Position, Relative, ScreenRelative, Velocity, ScreenVelocity, Tilt;
        public double Pressure;
        public bool PenInverted;

        public override InputEvent XformedBy(Xform2 xf, Vec2 localOfs = default)
        {
            var e = (InputEventScreenDrag)Duplicate();
            e.Position = xf.Xform(Position + localOfs);
            e.Relative = xf.BasisXform(Relative);
            e.Velocity = xf.BasisXform(Velocity);
            return e;
        }
    }

    public sealed class InputEventKey : InputEventWithModifiers
    {
        public Key Keycode, PhysicalKeycode, KeyLabel;
        public int Unicode;
        public bool Pressed, Echo;
        public override bool IsPressed() => Pressed;
        public override bool IsEcho() => Echo;
        public override bool IsActionType() => true;
    }

    public sealed class InputEventAction : InputEvent
    {
        public string Action = "";
        public bool Pressed;
        public double Strength = 1.0;
        public override bool IsPressed() => Pressed;
        public override bool IsActionType() => true;
    }

    public sealed class InputEventMagnifyGesture : InputEventWithModifiers
    {
        public Vec2 Position;
        public double Factor = 1.0;

        public override InputEvent XformedBy(Xform2 xf, Vec2 localOfs = default)
        {
            var e = (InputEventMagnifyGesture)Duplicate();
            e.Position = xf.Xform(Position + localOfs);
            return e;
        }
    }

    public sealed class InputEventPanGesture : InputEventWithModifiers
    {
        public Vec2 Position, Delta;

        public override InputEvent XformedBy(Xform2 xf, Vec2 localOfs = default)
        {
            var e = (InputEventPanGesture)Duplicate();
            e.Position = xf.Xform(Position + localOfs);
            return e;
        }
    }

    /// <summary>The project's input actions (Godot's built-in ui_* plus anything the game adds).</summary>
    public static class InputMap
    {
        static readonly Dictionary<string, List<Func<InputEvent, bool>>> _actions = new Dictionary<string, List<Func<InputEvent, bool>>>
        {
            ["ui_accept"] = new List<Func<InputEvent, bool>> { e => e is InputEventKey k && (k.Keycode == Key.Enter || k.Keycode == Key.KpEnter || k.Keycode == Key.Space) },
            ["ui_cancel"] = new List<Func<InputEvent, bool>> { e => e is InputEventKey k && (k.Keycode == Key.Escape || k.Keycode == Key.Back) },
            ["ui_left"] = new List<Func<InputEvent, bool>> { e => e is InputEventKey k && k.Keycode == Key.Left },
            ["ui_right"] = new List<Func<InputEvent, bool>> { e => e is InputEventKey k && k.Keycode == Key.Right },
            ["ui_up"] = new List<Func<InputEvent, bool>> { e => e is InputEventKey k && k.Keycode == Key.Up },
            ["ui_down"] = new List<Func<InputEvent, bool>> { e => e is InputEventKey k && k.Keycode == Key.Down },
        };

        public static bool EventIsAction(InputEvent e, string action, bool exact)
        {
            if (e is InputEventAction a) return a.Action == action;
            return _actions.TryGetValue(action, out var l) && l.Exists(f => f(e));
        }

        public static void AddAction(string action, Func<InputEvent, bool> match)
        {
            if (!_actions.TryGetValue(action, out var l)) _actions[action] = l = new List<Func<InputEvent, bool>>();
            l.Add(match);
        }

        public static bool HasAction(string action) => _actions.ContainsKey(action);
    }

    /// <summary>Godot's Input singleton.</summary>
    public static class Input
    {
        public static bool EmulateMouseFromTouch = true;
        public static bool EmulateTouchFromMouse = false;
        public static bool TouchscreenAvailable = true;
        static int _mouseFromTouch = -1;
        static MouseButtonMask _mask;
        static Vec2 _mousePos;
        static readonly HashSet<Key> _keys = new HashSet<Key>();
        static readonly Dictionary<string, (bool pressed, ulong frame)> _actionState = new Dictionary<string, (bool, ulong)>();
        static readonly Dictionary<int, Vec2> _touchPos = new Dictionary<int, Vec2>();
        /// <summary>Host hooks: vibration, mouse mode, virtual keyboard.</summary>
        public static Action<int, double> VibrateHook;
        public static Action<string, Rect2, int> ShowKeyboardHook;
        public static Action HideKeyboardHook;
        public static Func<Vec3> AccelerometerHook;
        static readonly List<InputEvent> _queue = new List<InputEvent>();

        public static bool IsTouchscreenAvailable() => TouchscreenAvailable;
        public static MouseButtonMask GetMouseButtonMask() => _mask;
        public static bool IsMouseButtonPressed(MouseButton b) => (_mask & ToMask(b)) != 0;
        public static bool IsKeyPressed(Key k) => _keys.Contains(k);
        public static Vec2 GetLastMousePosition() => _mousePos;

        public static bool IsActionPressed(string a) => _actionState.TryGetValue(a, out var s) && s.pressed;

        public static bool IsActionJustPressed(string a)
        {
            var t = SceneTree.Current;
            return _actionState.TryGetValue(a, out var s) && s.pressed && t != null && s.frame == t.Frame;
        }

        public static bool IsActionJustReleased(string a)
        {
            var t = SceneTree.Current;
            return _actionState.TryGetValue(a, out var s) && !s.pressed && t != null && s.frame == t.Frame;
        }

        public static void VibrateHandheld(int durationMs = 500, double amplitude = -1.0) => VibrateHook?.Invoke(durationMs, amplitude);
        public static Vec3 GetAccelerometer() => AccelerometerHook?.Invoke() ?? Vec3.Zero;

        public static MouseButtonMask ToMask(MouseButton b) =>
            b == MouseButton.Left ? MouseButtonMask.Left : b == MouseButton.Right ? MouseButtonMask.Right : b == MouseButton.Middle ? MouseButtonMask.Middle : MouseButtonMask.None;

        /// <summary>Input.parse_input_event: queues an event (in window pixels) with its emulated mouse twin first.</summary>
        public static void ParseInputEvent(InputEvent e)
        {
            lock (_queue) Parse(e);
        }

        static void Parse(InputEvent e)
        {
            if (e is InputEventMouseButton mb)
            {
                if (mb.Pressed) _mask |= ToMask(mb.ButtonIndex);
                else _mask &= ~ToMask(mb.ButtonIndex);
                mb.ButtonMask = _mask;
                _mousePos = mb.Position;
            }
            else if (e is InputEventMouseMotion mm)
            {
                _mousePos = mm.Position;
                mm.ButtonMask = mm.Device == InputEvent.DEVICE_ID_EMULATION ? _mask : (mm.ButtonMask == 0 ? _mask : mm.ButtonMask);
            }
            else if (e is InputEventKey k)
            {
                if (k.Pressed) _keys.Add(k.Keycode);
                else _keys.Remove(k.Keycode);
            }
            if (e is InputEventScreenTouch st)
            {
                if (st.Pressed) _touchPos[st.Index] = st.Position;
                else _touchPos.Remove(st.Index);
                if (EmulateMouseFromTouch)
                {
                    bool translate = false;
                    if (st.Pressed)
                    {
                        if (_mouseFromTouch == -1) { translate = true; _mouseFromTouch = st.Index; }
                    }
                    else if (st.Index == _mouseFromTouch) { translate = true; _mouseFromTouch = -1; }
                    if (translate)
                    {
                        var be = new InputEventMouseButton
                        {
                            Device = InputEvent.DEVICE_ID_EMULATION,
                            Position = st.Position,
                            GlobalPosition = st.Position,
                            Pressed = st.Pressed,
                            ButtonIndex = MouseButton.Left,
                            DoubleClick = st.DoubleTap,
                            Canceled = st.Canceled,
                        };
                        Parse(be);
                    }
                }
            }
            if (e is InputEventScreenDrag sd)
            {
                _touchPos[sd.Index] = sd.Position;
                if (EmulateMouseFromTouch && sd.Index == _mouseFromTouch)
                {
                    var me = new InputEventMouseMotion
                    {
                        Device = InputEvent.DEVICE_ID_EMULATION,
                        Position = sd.Position,
                        GlobalPosition = sd.Position,
                        Relative = sd.Relative,
                        ScreenRelative = sd.ScreenRelative,
                        Velocity = sd.Velocity,
                        ScreenVelocity = sd.ScreenVelocity,
                        Pressure = sd.Pressure,
                    };
                    Parse(me);
                }
            }
            if (e.IsActionType())
                foreach (var a in new[] { "ui_accept", "ui_cancel", "ui_left", "ui_right", "ui_up", "ui_down" })
                    if (InputMap.EventIsAction(e, a, false) && !e.IsEcho())
                        _actionState[a] = (e.IsPressed(), (SceneTree.Current?.Frame ?? 0) + 1);
            _queue.Add(e);
        }

        /// <summary>The events queued since the last frame (the root viewport takes them at frame start).</summary>
        internal static List<InputEvent> TakeQueued()
        {
            lock (_queue)
            {
                var o = new List<InputEvent>(_queue);
                _queue.Clear();
                return o;
            }
        }

        public static Vec2 TouchPosition(int index) => _touchPos.TryGetValue(index, out var p) ? p : Vec2.Zero;
        public static int TouchCount => _touchPos.Count;
    }

    /// <summary>DisplayServer bits the UI reads (safe area, virtual keyboard, screen size/scale). (More in GUI/Services/Display.cs.)</summary>
    public static partial class DisplayServer
    {
        public static Rect2 SafeArea = new Rect2(0, 0, 0, 0);
        public static Vec2 ScreenSize = new Vec2(1920, 1080);
        public static double ScreenDpi = 420;
        public static int VirtualKeyboardHeight;
        public static Action<bool> KeepScreenOnHook;

        public static Rect2 GetDisplaySafeArea() => SafeArea.size.x > 0 ? SafeArea : new Rect2(Vec2.Zero, ScreenSize);
        public static Vec2 ScreenGetSize() => ScreenSize;
        public static double ScreenGetDpi() => ScreenDpi;
        public static int VirtualKeyboardGetHeight() => VirtualKeyboardHeight;
        public static void VirtualKeyboardShow(string text, Rect2 rect = default, int type = 0) => Input.ShowKeyboardHook?.Invoke(text, rect, type);
        public static void VirtualKeyboardHide() => Input.HideKeyboardHook?.Invoke();
        public static void ScreenSetKeepOn(bool on) => KeepScreenOnHook?.Invoke(on);
        public static bool IsTouchscreenAvailable() => Input.TouchscreenAvailable;
    }
}
