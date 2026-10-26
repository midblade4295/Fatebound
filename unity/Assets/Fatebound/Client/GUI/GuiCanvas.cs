// Fatebound (Unity port): runs the GUI framework inside Unity. Owns the SceneTree, feeds it touches/mouse/keys the way
// Godot's Android/desktop input arrives, iterates it once a frame and draws its render batches through a Screen Space
// Overlay canvas (one CanvasRenderer per batch, mesh vertices in screen pixels, the Fatebound/GUI shader).
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

namespace Fatebound.Client
{
    [DefaultExecutionOrder(-100)]
    public sealed class GuiCanvas : MonoBehaviour
    {
        public static GuiCanvas Instance { get; private set; }
        public SceneTree Tree { get; private set; }
        Canvas _canvas;
        readonly List<CanvasRenderer> _renderers = new List<CanvasRenderer>();
        readonly List<Mesh> _meshes = new List<Mesh>();
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
            ResourceLoader.Host = new UnityGuiHost();
            Fatebound.Sim.GD.PrintSink = s => Debug.Log(s);
            Fatebound.Sim.GD.ErrorSink = s => Debug.LogError(s);
            Fatebound.Sim.GD.WarningSink = s => Debug.LogWarning(s);
            _canvas = gameObject.AddComponent<Canvas>();
            _canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            _canvas.sortingOrder = 100;
            _canvas.pixelPerfect = false;
            _canvas.additionalShaderChannels = AdditionalCanvasShaderChannels.TexCoord1 | AdditionalCanvasShaderChannels.TexCoord2 | AdditionalCanvasShaderChannels.TexCoord3;
            _shader = Shader.Find("Fatebound/GUI") ?? Resources.Load<Shader>("Shaders/FateboundGUI");
            _white = UnityEngine.Texture2D.whiteTexture;
            _screen = new Vector2Int(Screen.width, Screen.height);
            Tree = new SceneTree(new Vec2(760, 420));
            Tree.Root.BaseSize = new Vec2(760, 420);
            Tree.Root.SetWindowSize(new Vec2(Screen.width, Screen.height));
            UpdateSafeArea();
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
        }

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
            FeedInput();
            Tree.Iterate(Time.unscaledDeltaTime);
            if (Tree.QuitRequested) Application.Quit(Tree.QuitCode);
        }

        void LateUpdate()
        {
            RenderingServer.RaiseFramePreDraw();
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
                    case CanvasBlendMode.Mul: mat.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.DstColor); mat.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.Zero); break;
                    case CanvasBlendMode.PremultAlpha: mat.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.One); mat.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha); break;
                    default: mat.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.SrcAlpha); mat.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha); break;
                }
                _materials[key] = mat;
            }
            return mat;
        }

        readonly List<Vector3> _pos = new List<Vector3>();
        readonly List<Color32> _col = new List<Color32>();
        readonly List<Vector4> _uv0 = new List<Vector4>();
        readonly List<Vector4> _uv1 = new List<Vector4>();
        readonly List<int> _idx = new List<int>();

        void Draw(List<RenderBatch> batches)
        {
            float h = Screen.height;
            while (_renderers.Count < batches.Count)
            {
                var go = new GameObject("batch" + _renderers.Count, typeof(RectTransform));
                go.transform.SetParent(transform, false);
                var rt = (RectTransform)go.transform;
                rt.anchorMin = rt.anchorMax = Vector2.zero;
                rt.pivot = Vector2.zero;
                rt.anchoredPosition = Vector2.zero;
                rt.sizeDelta = Vector2.zero;
                var cr = go.AddComponent<CanvasRenderer>();
                _renderers.Add(cr);
                _meshes.Add(new Mesh { hideFlags = HideFlags.DontSave });
                _meshes[_meshes.Count - 1].MarkDynamic();
            }
            for (int i = 0; i < _renderers.Count; i++)
            {
                var cr = _renderers[i];
                if (i >= batches.Count)
                {
                    if (cr.gameObject.activeSelf) cr.gameObject.SetActive(false);
                    continue;
                }
                if (!cr.gameObject.activeSelf) cr.gameObject.SetActive(true);
                var b = batches[i];
                _pos.Clear(); _col.Clear(); _uv0.Clear(); _uv1.Clear(); _idx.Clear();
                float mode = b.mode == DrawMode.SdfText ? 1f : 0f;
                foreach (var v in b.verts)
                {
                    _pos.Add(new Vector3(v.x, h - v.y, 0));
                    var c = v.c;
                    _col.Add(new Color32((byte)(Mathf.Clamp01(c.r) * 255f + 0.5f), (byte)(Mathf.Clamp01(c.g) * 255f + 0.5f), (byte)(Mathf.Clamp01(c.b) * 255f + 0.5f), (byte)(Mathf.Clamp01(c.a) * 255f + 0.5f)));
                    _uv0.Add(new Vector4(v.u, 1f - v.v, mode, b.aux));
                    _uv1.Add(new Vector4(v.cx0, h - v.cy1, v.cx1, h - v.cy0));
                }
                _idx.AddRange(b.indices);
                var mesh = _meshes[i];
                mesh.Clear();
                mesh.indexFormat = _pos.Count > 65000 ? UnityEngine.Rendering.IndexFormat.UInt32 : UnityEngine.Rendering.IndexFormat.UInt16;
                mesh.SetVertices(_pos);
                mesh.SetColors(_col);
                mesh.SetUVs(0, _uv0);
                mesh.SetUVs(1, _uv1);
                mesh.SetTriangles(_idx, 0, false);
                cr.SetMesh(mesh);
                Texture tex = b.texture?.GetHandle() as Texture ?? _white;
                if (b.repeat && tex.wrapMode != TextureWrapMode.Repeat) tex.wrapMode = TextureWrapMode.Repeat;
                cr.materialCount = 1;
                cr.SetMaterial(MaterialFor(b), 0);
                cr.SetTexture(tex);
            }
            RenderingServer.RaiseFramePostDraw();
        }
    }
}
