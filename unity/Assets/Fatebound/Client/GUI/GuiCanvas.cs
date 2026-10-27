// Fatebound (Unity port): runs the GUI framework inside Unity. Owns the SceneTree, feeds it touches/mouse/keys the way
// Godot's Android/desktop input arrives, iterates it once a frame and draws its render batches.
// Drawing: Godot's 2D renderer works in sRGB values (colours, textures and blending, no linear conversion), so the
// batches are drawn into a raw RGBA8 texture the size of the screen (one mesh per batch, vertices in screen pixels, the
// Fatebound/GUI shader or a ported canvas shader), from a command buffer run when the screen camera starts -- after
// the 3D viewports' cameras have rendered this frame's images the GUI shows. One CanvasRenderer on an overlay canvas
// then puts that texture on the screen (Fatebound/GUIComposite).
using System.Collections.Generic;
using Fatebound.GUI;
using Fatebound.Sim;
using UnityEngine;
using GInput = Fatebound.GUI.Input;
using GKey = Fatebound.GUI.Key;
using UInput = UnityEngine.Input;
using Shader = UnityEngine.Shader;
using Texture = UnityEngine.Texture;
using Material = UnityEngine.Material;
using Time = UnityEngine.Time;
using Mesh = UnityEngine.Mesh;
using UnityEngine.Rendering;

namespace Fatebound.Client
{
    [DefaultExecutionOrder(-100)]
    public sealed class GuiCanvas : MonoBehaviour
    {
        public static GuiCanvas Instance { get; private set; }
        public SceneTree Tree { get; private set; }
        Canvas _canvas;
        CanvasRenderer _composite;
        Mesh _compositeQuad;
        Material _compositeMat;
        Camera _screenCam;
        RenderTexture _gui;
        CommandBuffer _cmd;
        bool _cmdReady;

        /// <summary>Godot's rendering/environment/defaults/default_clear_color: the window's clear colour (sRGB).</summary>
        public static Col ClearColor = new Col(0.3f, 0.3f, 0.3f, 1f);
        readonly Dictionary<(CanvasBlendMode, int), Material> _materials = new Dictionary<(CanvasBlendMode, int), Material>();
        Shader _shader;
        UnityEngine.Texture2D _white;
        Vector2Int _screen;
        readonly Dictionary<int, Vector2> _lastTouch = new Dictionary<int, Vector2>();
        Vector2 _lastMouse;
        bool _mouseDown;
        TouchScreenKeyboard _keyboard;
        LineEdit _editing;

        /// <summary>Hooks a ported ShaderMaterial (a .gdshader path) to its Unity shader; set by the shader registry.</summary>
        public static System.Func<ShaderMaterial, Material> CanvasShaderMaterial;

        public static GuiCanvas Create()
        {
            var go = new GameObject("GUI");
            DontDestroyOnLoad(go);
            return go.AddComponent<GuiCanvas>();
        }

        void Awake()
        {
            Instance = this;
            _platform = new UnityPlatform();
            PlatformHost.Init(_platform);
            ResourceLoader.Host = new UnityGuiHost();
            AudioServer.Host = new UnityAudio();
            Fatebound.Sim.GD.PrintSink = s => Debug.Log(s);
            Fatebound.Sim.GD.ErrorSink = s => Debug.LogError(s);
            Fatebound.Sim.GD.WarningSink = s => Debug.LogWarning(s);
            _canvas = gameObject.AddComponent<Canvas>();
            _canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            _canvas.sortingOrder = 100;
            _canvas.pixelPerfect = false;
            var cgo = new GameObject("gui", typeof(RectTransform));
            cgo.transform.SetParent(transform, false);
            var rt = (RectTransform)cgo.transform;
            rt.anchorMin = rt.anchorMax = Vector2.zero;
            rt.pivot = Vector2.zero;
            rt.anchoredPosition = Vector2.zero;
            rt.sizeDelta = Vector2.zero;
            _composite = cgo.AddComponent<CanvasRenderer>();
            _compositeQuad = new Mesh { hideFlags = HideFlags.DontSave };
            _compositeMat = new Material(Shader.Find("Hidden/Fatebound/GUIComposite") ?? Resources.Load<Shader>("Shaders/FateboundGUIComposite")) { hideFlags = HideFlags.DontSave };
            _shader = Shader.Find("Fatebound/GUI") ?? Resources.Load<Shader>("Shaders/FateboundGUI");
            // the screen: a camera that draws nothing (its clear is covered by the GUI's image) and hosts the overlay
            var sc = new GameObject("screen");
            sc.transform.SetParent(transform, false);
            _screenCam = sc.AddComponent<Camera>();
            _screenCam.cullingMask = 0;
            _screenCam.clearFlags = CameraClearFlags.SolidColor;
            _screenCam.backgroundColor = Color.black;
            _screenCam.depth = 0;
            _screenCam.allowHDR = false;
            _screenCam.allowMSAA = false;
            _screenCam.useOcclusionCulling = false;
            _cmd = new CommandBuffer { name = "Fatebound GUI" };
            RenderPipelineManager.beginCameraRendering += OnBeginCamera;
            _white = UnityEngine.Texture2D.whiteTexture;
            _screen = new Vector2Int(Screen.width, Screen.height);
            Tree = new SceneTree(new Vec2(760, 420));
            Tree.Root.BaseSize = new Vec2(760, 420);
            Tree.Root.SetWindowSize(new Vec2(Screen.width, Screen.height));
            UpdateSafeArea();
            UnityRenderStats.Install(Tree);
            UInput.multiTouchEnabled = true;
            GInput.TouchscreenAvailable = UInput.touchSupported;
            GInput.VibrateHook = (ms, amp) => { if (Application.isMobilePlatform) Handheld.Vibrate(); };
            GInput.ShowKeyboardHook = (text, rect, type) =>
            {
                _editing = Tree.Root.GuiFocus as LineEdit;
                _keyboard = TouchScreenKeyboard.Open(text ?? "", TouchScreenKeyboardType.Default, false, false, false, false, "", _editing?.MaxLength ?? 0);
            };
            GInput.HideKeyboardHook = () => { if (_keyboard != null) _keyboard.active = false; _keyboard = null; _editing = null; };
            DisplayServer.KeepScreenOnHook = on => Screen.sleepTimeout = on ? SleepTimeout.NeverSleep : SleepTimeout.SystemSetting;
            _renderer3D = new UnityRenderer3D();
            new UnityPhysics3D();           // the 3D physics backend: registers itself as PhysicsServer3D.Backend
            CanvasShaderMaterial = sm => _renderer3D.Materials.GetCanvas(sm);
            InlineShaders.Register();
        }

        UnityRenderer3D _renderer3D;
        UnityPlatform _platform;

        void UpdateSafeArea()
        {
            var sa = Screen.safeArea;
            DisplayServer.ScreenSize = new Vec2(Screen.width, Screen.height);
            DisplayServer.SafeArea = new Rect2(sa.x, Screen.height - sa.yMax, sa.width, sa.height);
            DisplayServer.ScreenDpi = Screen.dpi > 0 ? Screen.dpi : 420;
        }

        static Vec2 Px(Vector2 p) => new Vec2(p.x, Screen.height - p.y);

        void FeedInput()
        {
            if (UInput.touchSupported && UInput.touchCount > 0 || _lastTouch.Count > 0)
            {
                var seen = new HashSet<int>();
                for (int i = 0; i < UInput.touchCount; i++)
                {
                    var t = UInput.GetTouch(i);
                    seen.Add(t.fingerId);
                    var pos = Px(t.position);
                    switch (t.phase)
                    {
                        case TouchPhase.Began:
                            _lastTouch[t.fingerId] = t.position;
                            GInput.ParseInputEvent(new InputEventScreenTouch { Index = t.fingerId, Position = pos, Pressed = true, DoubleTap = t.tapCount > 1 });
                            break;
                        case TouchPhase.Moved:
                        {
                            var rel = t.deltaPosition;
                            _lastTouch[t.fingerId] = t.position;
                            var relG = new Vec2(rel.x, -rel.y);
                            float dt = Mathf.Max(t.deltaTime, 1e-4f);
                            GInput.ParseInputEvent(new InputEventScreenDrag { Index = t.fingerId, Position = pos, Relative = relG, ScreenRelative = relG, Velocity = relG / dt, ScreenVelocity = relG / dt, Pressure = t.pressure });
                            break;
                        }
                        case TouchPhase.Ended:
                        case TouchPhase.Canceled:
                            _lastTouch.Remove(t.fingerId);
                            GInput.ParseInputEvent(new InputEventScreenTouch { Index = t.fingerId, Position = pos, Pressed = false, Canceled = t.phase == TouchPhase.Canceled });
                            break;
                    }
                }
                foreach (var id in new List<int>(_lastTouch.Keys))
                    if (!seen.Contains(id))
                    {
                        GInput.ParseInputEvent(new InputEventScreenTouch { Index = id, Position = Px(_lastTouch[id]), Pressed = false, Canceled = true });
                        _lastTouch.Remove(id);
                    }
            }
            else if (UInput.mousePresent)
            {
                // Desktop / editor: a real mouse (Godot does not emulate touch from the mouse in this project).
                Vector2 mp = UInput.mousePosition;
                if (mp != _lastMouse)
                {
                    var rel = mp - _lastMouse;
                    var relG = new Vec2(rel.x, -rel.y);
                    float dt = Mathf.Max(Time.unscaledDeltaTime, 1e-4f);
                    GInput.ParseInputEvent(new InputEventMouseMotion { Position = Px(mp), Relative = relG, ScreenRelative = relG, Velocity = relG / dt, ButtonMask = GInput.GetMouseButtonMask() });
                    _lastMouse = mp;
                }
                for (int b = 0; b < 3; b++)
                {
                    var mb = b == 0 ? MouseButton.Left : b == 1 ? MouseButton.Right : MouseButton.Middle;
                    if (UInput.GetMouseButtonDown(b)) GInput.ParseInputEvent(new InputEventMouseButton { ButtonIndex = mb, Pressed = true, Position = Px(mp) });
                    if (UInput.GetMouseButtonUp(b)) GInput.ParseInputEvent(new InputEventMouseButton { ButtonIndex = mb, Pressed = false, Position = Px(mp) });
                }
                float wheel = UInput.mouseScrollDelta.y;
                if (wheel != 0)
                {
                    var wb = wheel > 0 ? MouseButton.WheelUp : MouseButton.WheelDown;
                    GInput.ParseInputEvent(new InputEventMouseButton { ButtonIndex = wb, Pressed = true, Position = Px(mp), Factor = Mathf.Abs(wheel) });
                    GInput.ParseInputEvent(new InputEventMouseButton { ButtonIndex = wb, Pressed = false, Position = Px(mp), Factor = Mathf.Abs(wheel) });
                }
            }
            if (UInput.GetKeyDown(KeyCode.Escape)) Tree.GoBackRequest();
            if (!Application.isMobilePlatform)
            {
                foreach (char ch in UInput.inputString)
                {
                    if (ch == '\b') Key(GKey.Backspace);
                    else if (ch == '\n' || ch == '\r') Key(GKey.Enter);
                    else Key(GKey.None, ch);
                }
            }
            if (_keyboard != null && _editing != null && Node.IsInstanceValid(_editing))
            {
                if (_keyboard.text != _editing.Text) _editing.SetTextFromKeyboard(_keyboard.text);
                if (_keyboard.status == TouchScreenKeyboard.Status.Done) { _editing.Submit(); _editing.ReleaseFocus(); }
                else if (_keyboard.status != TouchScreenKeyboard.Status.Visible) _editing.ReleaseFocus();
            }
        }

        static void Key(GKey k, char ch = '\0')
        {
            GInput.ParseInputEvent(new InputEventKey { Keycode = k, Unicode = ch, Pressed = true });
            GInput.ParseInputEvent(new InputEventKey { Keycode = k, Unicode = ch, Pressed = false });
        }

        void OnApplicationPause(bool paused)
        {
            Tree?.PropagateNotification(paused ? Node.NOTIFICATION_APPLICATION_PAUSED : Node.NOTIFICATION_APPLICATION_RESUMED);
        }

        void OnApplicationFocus(bool focus)
        {
            Tree?.Root.SendWindowFocus(focus);
            Tree?.PropagateNotification(focus ? Node.NOTIFICATION_APPLICATION_FOCUS_IN : Node.NOTIFICATION_APPLICATION_FOCUS_OUT);
        }

        void Update()
        {
            if (Screen.width != _screen.x || Screen.height != _screen.y)
            {
                _screen = new Vector2Int(Screen.width, Screen.height);
                Tree.Root.SetWindowSize(new Vec2(Screen.width, Screen.height));
                UpdateSafeArea();
            }
            _platform.Tick();
            UnityRenderStats.Frame();
            FeedInput();
            Tree.Iterate(Time.unscaledDeltaTime);
            if (Tree.QuitRequested) Application.Quit(Tree.QuitCode);
        }

        void OnDestroy()
        {
            RenderPipelineManager.beginCameraRendering -= OnBeginCamera;
            if (_gui != null) { _gui.Release(); Destroy(_gui); }
        }

        void OnBeginCamera(ScriptableRenderContext ctx, Camera cam)
        {
            if (cam != _screenCam || !_cmdReady) return;
            ctx.ExecuteCommandBuffer(_cmd);
            ctx.Submit();
            _cmdReady = false;
        }

        void LateUpdate()
        {
            Shader.SetGlobalFloat("_FB_Time", (float)(Time.realtimeSinceStartupAsDouble % 3600.0));
            RenderingServer.RaiseFramePreDraw();
            // the 3D worlds' changes to their Unity objects, the viewports' cameras (they render into their textures
            // before the screen camera, whose overlay canvas then draws the GUI with them)
            _renderer3D.Frame(Time.unscaledDeltaTime);
            Draw(Tree.Root.Render());
        }

        Material MaterialFor(RenderBatch b)
        {
            if (b.material is ShaderMaterial sm && CanvasShaderMaterial != null)
            {
                var m = CanvasShaderMaterial(sm);
                if (m != null) return m;
            }
            var key = (b.blend, 0);
            if (!_materials.TryGetValue(key, out var mat))
            {
                mat = new Material(_shader) { hideFlags = HideFlags.DontSave };
                switch (b.blend)
                {
                    case CanvasBlendMode.Add: mat.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.SrcAlpha); mat.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.One); break;
                    case CanvasBlendMode.Sub:
                        mat.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.SrcAlpha);
                        mat.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.One);
                        mat.SetFloat("_BlendOp", (float)UnityEngine.Rendering.BlendOp.ReverseSubtract);
                        break;
                    case CanvasBlendMode.Mul: mat.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.DstColor); mat.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.Zero); break;
                    case CanvasBlendMode.PremultAlpha: mat.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.One); mat.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha); break;
                    default: mat.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.SrcAlpha); mat.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha); break;
                }
                _materials[key] = mat;
            }
            return mat;
        }


        readonly CanvasDrawer _rootDrawer = new CanvasDrawer();
        readonly Dictionary<Viewport, CanvasDrawer> _vpDrawers = new Dictionary<Viewport, CanvasDrawer>();
        readonly List<Viewport> _vpGone = new List<Viewport>();

        void Draw(List<RenderBatch> batches)
        {
            int w = Mathf.Max(1, Screen.width), h = Mathf.Max(1, Screen.height);
            if (_gui == null || _gui.width != w || _gui.height != h)
            {
                if (_gui != null) { _gui.Release(); Destroy(_gui); }
                _gui = new RenderTexture(w, h, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Linear) { name = "gui", filterMode = FilterMode.Point };
                _gui.Create();
                _compositeQuad.Clear();
                _compositeQuad.SetVertices(new List<Vector3> { new Vector3(0, 0), new Vector3(0, h), new Vector3(w, h), new Vector3(w, 0) });
                _compositeQuad.SetUVs(0, new List<Vector2> { new Vector2(0, 0), new Vector2(0, 1), new Vector2(1, 1), new Vector2(1, 0) });
                _compositeQuad.SetColors(new List<Color32> { Color.white, Color.white, Color.white, Color.white });
                _compositeQuad.SetTriangles(new[] { 0, 1, 2, 0, 2, 3 }, 0);
                _composite.SetMesh(_compositeQuad);
                _composite.materialCount = 1;
                _composite.SetMaterial(_compositeMat, 0);
            }
            _composite.SetTexture(_gui);
            _cmd.Clear();
            var clear = new Color(ClearColor.r, ClearColor.g, ClearColor.b, ClearColor.a);

            // SubViewports first: their 2D canvas goes into their texture, over the 3D picture their camera rendered
            // this frame (Godot draws a viewport's canvas after its 3D), before the root canvas samples them
            foreach (var d in _renderer3D.Viewports)
            {
                if (!d.Draw2D || d.Ldr == null) continue;
                var vp = d.Vp;
                var vb = vp.Render();
                if (!_vpDrawers.TryGetValue(vp, out var drawer)) _vpDrawers[vp] = drawer = new CanvasDrawer();
                Color? vclear = null;
                if (!d.Rendered3D) vclear = vp.TransparentBg ? new Color(0, 0, 0, 0) : clear;
                if (vb.Count == 0 && vclear == null) continue;
                drawer.Record(_cmd, d.Ldr, d.Ldr.width, d.Ldr.height, vb, vclear, MaterialFor, _white);
            }
            _vpGone.Clear();
            foreach (var kv in _vpDrawers) if (!kv.Key.IsInsideTree()) _vpGone.Add(kv.Key);
            foreach (var vp in _vpGone) { _vpDrawers[vp].Release(); _vpDrawers.Remove(vp); }

            // the root: its own 3D (if a camera renders in the root viewport) under the GUI, else the clear colour
            var root = _renderer3D.RootData(Tree.Root);
            if (root != null && root.Rendered3D && root.Ldr != null && root.Ldr.width == w && root.Ldr.height == h)
            {
                _cmd.CopyTexture(root.Ldr, _gui);
                _rootDrawer.Record(_cmd, _gui, w, h, batches, null, MaterialFor, _white);
            }
            else _rootDrawer.Record(_cmd, _gui, w, h, batches, clear, MaterialFor, _white);
            _cmdReady = true;
            RenderingServer.RaiseFramePostDraw();
        }
    }
}
