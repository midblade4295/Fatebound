// Fatebound GUI (Unity port): the root Viewport -- the canvas_items stretch (760x420 base, aspect expand), input
// routing as viewport.cpp does it (_input in reverse tree order, then the GUI: mouse focus on press, motion to the
// focused control, touch focus by index, bubbling to parents until a STOP filter, hover enter/exit; then
// _unhandled_input), keyboard focus, and the canvas walk that turns every visible item's draw list into vertex batches
// for the host (canvas layers, z index buckets, show-behind-parent, clip_contents rectangles, modulate).
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public partial struct RVert
    {
        public float x, y, u, v;
        public Col c;
        /// <summary>Clip rectangle in device pixels (x0, y0, x1, y1).</summary>
        public float cx0, cy0, cx1, cy1;
    }

    public sealed partial class RenderBatch
    {
        public Texture2D texture;
        public GMaterial material;
        public CanvasItem materialOwner;
        public DrawMode mode;
        public float aux;
        public CanvasBlendMode blend;
        public bool repeat;
        public readonly List<RVert> verts = new List<RVert>();
        public readonly List<int> indices = new List<int>();
    }

    public partial class Viewport : Node
    {
        public Vec2 BaseSize = new Vec2(760, 420);
        Vec2 _windowSize = new Vec2(760, 420);
        Vec2 _visible = new Vec2(760, 420);
        float _scale = 1f;
        /// <summary>The window stretch: viewport units to device pixels (applied when rendering and to incoming events).</summary>
        public Xform2 StretchTransform = Xform2.IDENTITY;
        public event Action SizeChanged;
        public event Action<Control> GuiFocusChanged;

        readonly List<Control> _roots = new List<Control>();
        bool _canvasDirty = true;
        bool _handled;
        Vec2 _mousePos;
        Control _mouseFocus;
        MouseButtonMask _mouseFocusMask;
        readonly Dictionary<int, Control> _touchFocus = new Dictionary<int, Control>();
        readonly List<Control> _overHierarchy = new List<Control>();
        Control _mouseOver;
        public Control GuiFocus { get; private set; }
        public bool HideFocus { get; private set; }
        public bool GuiDisableInput;
        readonly List<InputEvent> _pushed = new List<InputEvent>();

        public override Viewport GetViewport() => this;

#if FB3D
        // ---------- 3D: the world this viewport shows and its camera ----------
        World3D _ownWorld, _world3d;
        bool _ownWorld3D, _transparentBg;
        int _msaa3d, _screenAa;
        double _scaling3dScale = 1.0;
        readonly List<Camera3D> _cameras = new List<Camera3D>();
        Camera3D _camera;
        /// <summary>The renderer's data for this viewport (its render texture, camera...).</summary>
        public object BackendData;
        public enum Msaa { Disabled = 0, X2 = 1, X4 = 2, X8 = 3 }
        public const int MSAA_DISABLED = 0, MSAA_2X = 1, MSAA_4X = 2, MSAA_8X = 3;
        public const int SCREEN_SPACE_AA_DISABLED = 0, SCREEN_SPACE_AA_FXAA = 1;
        public const int SCALING_3D_MODE_BILINEAR = 0, SCALING_3D_MODE_FSR = 1;
        public bool HandleInputLocally = true;
        public bool Disable3D;
        public int Scaling3DMode;
        public double MeshLodThreshold = 1.0;
        public bool UseDebanding, UseOcclusionCulling;
        public int PositionalShadowAtlasSize = 2048;

        public bool OwnWorld3D
        {
            get => _ownWorld3D;
            set
            {
                if (_ownWorld3D == value) return;
                _ownWorld3D = value;
                _ownWorld = value ? new World3D() : null;
                RenderSync.MarkViewport(this);
            }
        }

        /// <summary>world_3d: set one to share it between viewports.</summary>
        public World3D World3D
        {
            get => _world3d;
            set { _world3d = value; RenderSync.MarkViewport(this); }
        }

        public bool TransparentBg { get => _transparentBg; set { _transparentBg = value; RenderSync.MarkViewport(this); } }
        public int Msaa3D { get => _msaa3d; set { _msaa3d = value; RenderSync.MarkViewport(this); } }
        public int ScreenSpaceAa { get => _screenAa; set { _screenAa = value; RenderSync.MarkViewport(this); } }
        public double Scaling3DScale { get => _scaling3dScale; set { _scaling3dScale = value; RenderSync.MarkViewport(this); } }

        static World3D _defaultWorld;

        /// <summary>find_world_3d(): its own world, the one set, else its parent viewport's (the root has the default).</summary>
        public World3D FindWorld3D()
        {
            if (_ownWorld != null) return _ownWorld;
            if (_world3d != null) return _world3d;
            var pv = Parent?.GetViewport();
            if (pv != null && pv != this) return pv.FindWorld3D();
            return _world3d = _defaultWorld ?? (_defaultWorld = new World3D());
        }

        public World3D GetWorld3D() => _world3d;

        /// <summary>The size the 3D view renders at (the window's pixels for the root, the size for a SubViewport).</summary>
        public virtual Vec2 Get3DSize() => _windowSize;
        /// <summary>Viewport coordinates to the camera's (the root's stretch).</summary>
        public Vec2 GetCameraCoords(Vec2 p) => StretchTransform.Xform(p);
        public Vec2 GetCameraRectSize() => Get3DSize();

        public Camera3D GetCamera3D() => _camera;

        internal bool Camera3DAdd(Camera3D c)
        {
            if (_cameras.Contains(c)) return false;
            _cameras.Add(c);
            return _cameras.Count == 1;
        }

        internal void Camera3DRemove(Camera3D c) => _cameras.Remove(c);

        internal void Camera3DSet(Camera3D c)
        {
            if (_camera == c) return;
            var old = _camera;
            _camera = c;
            old?.BecameCurrent(false);
            c?.BecameCurrent(true);
            RenderSync.MarkViewport(this);
        }

        internal void Camera3DMakeNextCurrent(Camera3D exclude)
        {
            foreach (var c in _cameras)
            {
                if (c == exclude || !c.IsInsideTree()) continue;
                if (_camera != null) return;
                c.MakeCurrent();
                return;
            }
        }

        protected override void OnEnterTree()
        {
            base.OnEnterTree();
            RenderSync.MarkViewport(this);
        }

        protected override void OnExitTree()
        {
            RenderSync.RemovedViewport(this);
            base.OnExitTree();
        }

        /// <summary>The ViewportTexture showing this viewport (get_texture()).</summary>
        public ViewportTexture GetTexture()
        {
            if (_tex == null) _tex = new ViewportTexture { viewport = this };
            var sz = Get3DSize();
            _tex.width = (int)sz.x;
            _tex.height = (int)sz.y;
            return _tex;
        }

#endif
        ViewportTexture _tex;

        // ---------- size / stretch ----------
        /// <summary>Sets the window size in device pixels; canvas_items stretch with aspect expand.</summary>
        public void SetWindowSize(Vec2 px)
        {
            _windowSize = px;
            _scale = Math.Min(px.x / BaseSize.x, px.y / BaseSize.y);
            if (_scale <= 0) _scale = 1;
            _visible = new Vec2(px.x / _scale, px.y / _scale);
            StretchTransform = new Xform2(0.0, new Vec2(_scale, _scale), 0.0, Vec2.Zero);
            MarkCanvasDirty();
            foreach (var r in _roots.ToArray()) r.SizeChanged();
            SizeChanged?.Invoke();
        }

        /// <summary>For tests: a viewport exactly `size` virtual units at scale 1.</summary>
        public void SetVisibleSize(Vec2 size)
        {
            BaseSize = size;
            SetWindowSize(size);
        }

        public Rect2 GetVisibleRect() => new Rect2(Vec2.Zero, _visible);
        public Vec2 GetWindowSize() => _windowSize;
        public float CanvasScale => _scale;
        public Vec2 Size => _visible;
        public Vec2 GetMousePosition() => _mousePos;
        public Xform2 GetFinalTransform() => StretchTransform;
        public Xform2 GetScreenTransform() => StretchTransform;

        // ---------- bookkeeping ----------
        internal void MarkCanvasDirty() => _canvasDirty = true;
        public bool CanvasDirty => _canvasDirty;

        internal void AddRootControl(Control c) { if (!_roots.Contains(c)) _roots.Add(c); }
        internal void RemoveRootControl(Control c) => _roots.Remove(c);

        internal void RemoveControl(Control c)
        {
            if (_mouseFocus == c) { _mouseFocus = null; _mouseFocusMask = 0; }
            if (GuiFocus == c) GuiFocus = null;
            if (_mouseOver == c || _overHierarchy.Contains(c)) DropMouseOver(c.GetParentControl());
            foreach (var k in new List<int>(_touchFocus.Keys)) if (_touchFocus[k] == c) _touchFocus.Remove(k);
        }

        internal void HideControl(Control c)
        {
            if (_mouseFocus == c) { _mouseFocus = null; _mouseFocusMask = 0; }
            if (GuiFocus == c) SetFocus(null, false);
            if (_mouseOver == c || _overHierarchy.Contains(c)) DropMouseOver(c.GetParentControl());
        }

        internal void SetFocus(Control c, bool hide)
        {
            if (GuiFocus == c) { HideFocus = hide; return; }
            var old = GuiFocus;
            GuiFocus = c;
            HideFocus = hide;
            old?.NotifyFocus(false);
            c?.NotifyFocus(true);
            GuiFocusChanged?.Invoke(c);
        }

        public void GuiReleaseFocus() => SetFocus(null, false);
        public Control GuiGetFocusOwner() => GuiFocus;
        public Control GuiGetHoveredControl() => _mouseOver;
        public bool GuiIsDragging() => false;

        // ---------- input ----------
        public void SetInputAsHandled() => _handled = true;
        public bool IsInputHandled() => _handled;

        /// <summary>Frame start: everything Input queued, in window pixels.</summary>
        internal void FlushInput()
        {
            foreach (var e in Input.TakeQueued()) PushInput(e, false);
        }

        /// <summary>push_input: local_coords = already in viewport units.</summary>
        public void PushInput(InputEvent ev, bool localCoords = false)
        {
            if (GuiDisableInput) return;
            if (!localCoords) ev = ev.XformedBy(StretchTransform.AffineInverse());
            bool prevHandled = _handled;
            _handled = false;
            if (ev is InputEventMouse me)
            {
                me.GlobalPosition = me.Position;
                _mousePos = me.Position;
                UpdateMouseOver(me.Position);
            }
            var tree = GetTree();
            if (tree != null)
            {
                tree.DispatchInput(ev, this, false);
                if (!_handled) GuiInputEvent(ev);
                else GuiCleanup(ev);
                if (!_handled) tree.DispatchInput(ev, this, true);
            }
            _ = prevHandled;
        }

        void GuiCleanup(InputEvent ev)
        {
            if (ev is InputEventMouseButton mb && !mb.Pressed)
            {
                _mouseFocusMask &= ~Input.ToMask(mb.ButtonIndex);
                if (_mouseFocusMask == 0) _mouseFocus = null;
            }
            if (ev is InputEventScreenTouch st && !st.Pressed) _touchFocus.Remove(st.Index);
        }

        List<Control> SortedRoots()
        {
            var o = new List<Control>(_roots);
            GetTree()?.TreeOrder();                       // (fresh tree indices)
            int Layer(Control c) => c.GetCanvasLayerNode()?.Layer ?? 0;
            o.Sort((a, b) =>
            {
                int la = Layer(a), lb = Layer(b);
                if (la != lb) return la.CompareTo(lb);
                return a.treeIndex.CompareTo(b.treeIndex);
            });
            return o;
        }

        public Control GuiFindControl(Vec2 global)
        {
            var roots = SortedRoots();
            for (int i = roots.Count - 1; i >= 0; i--)
            {
                var sw = roots[i];
                if (!sw.IsVisibleInTree()) continue;
                var pci = sw.GetParentItem();
                Xform2 xf = pci != null ? pci.GetGlobalTransformWithCanvas() : LayerTransform(sw);
                var ret = FindAt(sw, global, xf);
                if (ret != null) return ret;
            }
            return null;
        }

        /// <summary>The canvas transform in viewport units (CanvasLayer offset/scale; the stretch is not part of it).</summary>
        static Xform2 LayerTransform(CanvasItem ci)
        {
            var cl = ci.GetCanvasLayerNode();
            return cl != null ? cl.Transform : Xform2.IDENTITY;
        }

        Control FindAt(CanvasItem node, Vec2 global, Xform2 xf)
        {
            if (!node.Visible) return null;
            Xform2 m = xf * node.GetTransform();
            if (m.BasisDeterminant() == 0f) return null;
            var c = node as Control;
            if (c == null || !c.ClipContents || c.HasPoint(m.AffineInverse().Xform(global)))
            {
                var ch = node.AllChildren;
                for (int i = ch.Count - 1; i >= 0; i--)
                {
                    if (!(ch[i] is CanvasItem ci) || ci.TopLevel) continue;
                    var r = FindAt(ci, global, m);
                    if (r != null) return r;
                }
            }
            if (c == null || c.MouseFilter == MouseFilterEnum.Ignore) return null;
            if (!c.HasPoint(m.AffineInverse().Xform(global))) return null;
            return c;
        }

        /// <summary>The canvas-and-global transform of a control in viewport units (no stretch).</summary>
        static Xform2 LocalizerOf(Control c) => (LayerTransform(c) * c.GetGlobalTransform()).AffineInverse();

        void UpdateMouseOver(Vec2 pos)
        {
            var over = GuiFindControl(pos);
            if (over == _mouseOver && !(over == null && _overHierarchy.Count > 0)) return;
            Control common = null;
            var ancestors = new List<Control>();
            if (over != null)
            {
                for (CanvasItem a = over; a != null; a = a.GetParentItem())
                {
                    if (a is Control ac)
                    {
                        if (ac.MouseFilter != MouseFilterEnum.Ignore)
                        {
                            int found = _overHierarchy.IndexOf(ac);
                            if (found >= 0) { common = _overHierarchy[found]; break; }
                            ancestors.Add(ac);
                        }
                        if (ac.MouseFilter == MouseFilterEnum.Stop) break;
                    }
                    if (a.TopLevel) break;
                }
            }
            if (_mouseOver != null || _overHierarchy.Count > 0) DropMouseOver(common);
            if (over != null)
            {
                _mouseOver = over;
                for (int i = ancestors.Count - 1; i >= 0; i--)
                {
                    _overHierarchy.Add(ancestors[i]);
                    ancestors[i].NotifyMouse(true);
                }
            }
        }

        void DropMouseOver(Control until)
        {
            _mouseOver = null;
            int keep = until != null ? _overHierarchy.IndexOf(until) + 1 : 0;
            for (int i = _overHierarchy.Count - 1; i >= keep; i--)
            {
                var c = _overHierarchy[i];
                if (c.IsInsideTree()) c.NotifyMouse(false);
            }
            if (keep < _overHierarchy.Count) _overHierarchy.RemoveRange(keep, _overHierarchy.Count - keep);
        }

        void GuiCallInput(Control control, InputEvent ev)
        {
            bool pointer = ev is InputEventMouse || ev is InputEventScreenDrag || ev is InputEventScreenTouch;
            bool scroll = ev is InputEventMouseButton mb && (mb.ButtonIndex == MouseButton.WheelUp || mb.ButtonIndex == MouseButton.WheelDown || mb.ButtonIndex == MouseButton.WheelLeft || mb.ButtonIndex == MouseButton.WheelRight);
            CanvasItem ci = control;
            while (ci != null)
            {
                if (ci is Control c)
                {
                    if (c.MouseFilter != MouseFilterEnum.Ignore) SceneTree.Safe(() => c.CallGuiInput(ev));
                    if (!c.IsInsideTree() || c.TopLevel) break;
                    if (c.MouseFilter == MouseFilterEnum.Stop && pointer && !scroll)
                    {
                        SetInputAsHandled();
                        break;
                    }
                }
                if (_handled) break;
                if (ci.TopLevel) break;
                ev = ev.XformedBy(ci.GetTransform());
                ci = ci.GetParentItem();
            }
        }

        void GuiInputEvent(InputEvent e)
        {
            if (e is InputEventMouseButton mb)
            {
                Vec2 mpos = mb.Position;
                if (mb.Pressed)
                {
                    var bm = Input.ToMask(mb.ButtonIndex);
                    if (_mouseFocusMask != 0 && (_mouseFocusMask & bm) == 0)
                    {
                        if (_mouseFocus == null) return;
                        _mouseFocusMask |= bm;
                    }
                    else
                    {
                        _mouseFocus = GuiFindControl(mpos);
                        if (_mouseFocus == null)
                        {
                            if (GuiFocus != null && mb.ButtonIndex == MouseButton.Left) { HideFocus = true; GuiFocus.QueueRedraw(); }
                            return;
                        }
                        _mouseFocusMask |= bm;
                    }
                    var ev = (InputEventMouseButton)mb.Duplicate();
                    ev.Position = LocalizerOf(_mouseFocus).Xform(mpos);
                    if (mb.ButtonIndex == MouseButton.Left)
                    {
                        for (CanvasItem ci = _mouseFocus; ci != null; ci = ci.GetParentItem())
                        {
                            if (ci is Control c)
                            {
                                if (c.FocusMode != FocusModeEnum.None && c.IsVisibleInTree())
                                {
                                    if (_overHierarchy.Contains(c)) c.GrabFocus(true);
                                    break;
                                }
                                if (c.MouseFilter == MouseFilterEnum.Stop) break;
                            }
                            if (ci.TopLevel) break;
                        }
                    }
                    if (_mouseFocus != null && _mouseFocus.CanProcess()) GuiCallInput(_mouseFocus, ev);
                }
                else
                {
                    _mouseFocusMask &= ~Input.ToMask(mb.ButtonIndex);
                    if (_mouseFocus == null) return;
                    var ev = (InputEventMouseButton)mb.Duplicate();
                    ev.Position = LocalizerOf(_mouseFocus).Xform(mpos);
                    var mf = _mouseFocus;
                    if (_mouseFocusMask == 0) _mouseFocus = null;
                    if (mf.CanProcess()) GuiCallInput(mf, ev);
                }
                return;
            }
            if (e is InputEventMouseMotion mm)
            {
                Control over = _mouseFocus ?? GuiFindControl(mm.Position);
                if (over != null)
                {
                    var loc = LocalizerOf(over);
                    var ev = (InputEventMouseMotion)mm.Duplicate();
                    ev.GlobalPosition = mm.Position;
                    ev.Velocity = loc.BasisXform(mm.Velocity);
                    ev.Relative = loc.BasisXform(mm.Relative);
                    ev.Position = loc.Xform(mm.Position);
                    if (over.CanProcess()) GuiCallInput(over, ev);
                }
                return;
            }
            if (e is InputEventScreenTouch st)
            {
                if (st.Pressed)
                {
                    var over = GuiFindControl(st.Position);
                    if (over != null)
                    {
                        _touchFocus[st.Index] = over;
                        if (over.CanProcess())
                        {
                            var ev = (InputEventScreenTouch)st.Duplicate();
                            ev.Position = LocalizerOf(over).Xform(st.Position);
                            GuiCallInput(over, ev);
                        }
                    }
                }
                else
                {
                    _touchFocus.TryGetValue(st.Index, out var over);
                    if (over != null && over.IsInsideTree() && over.CanProcess())
                    {
                        var ev = (InputEventScreenTouch)st.Duplicate();
                        ev.Position = LocalizerOf(over).Xform(st.Position);
                        GuiCallInput(over, ev);
                    }
                    _touchFocus.Remove(st.Index);
                }
                return;
            }
            if (e is InputEventScreenDrag sd)
            {
                _touchFocus.TryGetValue(sd.Index, out var over);
                if (over == null || !over.IsInsideTree()) over = GuiFindControl(sd.Position);
                if (over != null && over.CanProcess())
                {
                    var loc = LocalizerOf(over);
                    var ev = (InputEventScreenDrag)sd.Duplicate();
                    ev.Velocity = loc.BasisXform(sd.Velocity);
                    ev.Relative = loc.BasisXform(sd.Relative);
                    ev.Position = loc.Xform(sd.Position);
                    GuiCallInput(over, ev);
                }
                return;
            }
            if (e is InputEventMagnifyGesture || e is InputEventPanGesture)
            {
                Vec2 p = e is InputEventMagnifyGesture mg ? mg.Position : ((InputEventPanGesture)e).Position;
                var over = GuiFindControl(p);
                if (over != null && over.CanProcess()) GuiCallInput(over, e.XformedBy(LocalizerOf(over)));
                return;
            }
            if (e is InputEventKey && GuiFocus != null && GuiFocus.IsVisibleInTree())
                GuiCallInput(GuiFocus, e);
        }

        // ---------- rendering ----------
        struct Item
        {
            public CanvasItem ci;
            public Xform2 xf;
            public Col mod;
            public bool hasClip;
            public Rect2 clip;
            public GMaterial mat;
            public CanvasItem matOwner;
        }

        /// <summary>Redraws dirty items, then flattens every canvas into batches in draw order (device pixels).</summary>
        public List<RenderBatch> Render()
        {
            MainThread.Flush();
            StyleBox.CurrentOversampling = _scale;
            var tree = GetTree();
            tree?.ProcessRedraws();
            _canvasDirty = false;
            // Canvases: the main one (layer 0) and each CanvasLayer, by layer then tree order.
            var canvases = new List<(int layer, int order, Node owner, List<CanvasItem> roots)>();
            var mainRoots = new List<CanvasItem>();
            var layers = new Dictionary<CanvasLayer, List<CanvasItem>>();
            int ord = 0;
            if (tree != null)
            {
                foreach (var n in tree.TreeOrder())
                {
                    if (n.GetViewport() != this) continue;                // (a SubViewport's canvas is drawn into its texture)
                    if (n is CanvasLayer cl && !layers.ContainsKey(cl)) layers[cl] = new List<CanvasItem>();
                    if (!(n is CanvasItem ci) || ci.GetParentItem() != null) continue;
                    var layer = ci.GetCanvasLayerNode();
                    if (layer == null) mainRoots.Add(ci);
                    else
                    {
                        if (!layers.TryGetValue(layer, out var l)) layers[layer] = l = new List<CanvasItem>();
                        l.Add(ci);
                    }
                }
            }
            canvases.Add((0, -1, this, mainRoots));
            foreach (var kv in layers)
            {
                if (!kv.Key.Visible || !kv.Key.IsInsideTree()) continue;
                canvases.Add((kv.Key.Layer, ord++, kv.Key, kv.Value));
            }
            canvases.Sort((a, b) => a.layer != b.layer ? a.layer.CompareTo(b.layer) : a.order.CompareTo(b.order));
            var batches = new List<RenderBatch>();
            foreach (var cv in canvases)
            {
                Xform2 baseXf = cv.owner is CanvasLayer cl ? StretchTransform * cl.Transform : StretchTransform;
                var zBuckets = new SortedDictionary<int, List<Item>>();
                foreach (var root in cv.roots) Cull(root, baseXf, Col.WHITE, false, default, 0, null, null, zBuckets);
                foreach (var b in zBuckets.Values)
                    foreach (var it in b) Emit(it, batches);
            }
            return batches;
        }

        void Cull(CanvasItem ci, Xform2 parentXf, Col parentMod, bool parentHasClip, Rect2 parentClip, int parentZ, GMaterial parentMat, CanvasItem parentMatOwner, SortedDictionary<int, List<Item>> z)
        {
            if (!ci.Visible) return;
            Xform2 xf = parentXf * ci.GetTransform();
            Col mod = parentMod * ci.Modulate;
            if (mod.a <= 0.001f && !(ci.Material is ShaderMaterial)) return;
            int zi = ci.ZAsRelative ? parentZ + ci.ZIndex : ci.ZIndex;
            zi = Math.Max(-4096, Math.Min(4096, zi));
            bool hasClip = parentHasClip;
            Rect2 clip = parentClip;
            if (ci.ClipsChildren)
            {
                Rect2 own = xf.XformRect(ci.GetItemRect());
                clip = hasClip ? clip.Intersection(own) : own;
                hasClip = true;
            }
            GMaterial mat = ci.UseParentMaterial ? parentMat : ci.Material;
            CanvasItem matOwner = ci.UseParentMaterial ? parentMatOwner : (ci.Material != null ? ci : null);
            var ch = ci.AllChildren;
            for (int i = 0; i < ch.Count; i++)
                if (ch[i] is CanvasItem c && !c.TopLevel && c.ShowBehindParent) Cull(c, xf, mod, hasClip, clip, zi, mat, matOwner, z);
            if (!ci.drawList.IsEmpty)
            {
                if (!z.TryGetValue(zi, out var l)) z[zi] = l = new List<Item>();
                l.Add(new Item { ci = ci, xf = xf, mod = mod * ci.SelfModulate, hasClip = hasClip, clip = clip, mat = mat, matOwner = matOwner });
            }
            for (int i = 0; i < ch.Count; i++)
                if (ch[i] is CanvasItem c && !c.TopLevel && !c.ShowBehindParent) Cull(c, xf, mod, hasClip, clip, zi, mat, matOwner, z);
        }

        void Emit(Item it, List<RenderBatch> batches)
        {
            var dl = it.ci.drawList;
            float cx0 = -1e9f, cy0 = -1e9f, cx1 = 1e9f, cy1 = 1e9f;
            if (it.hasClip)
            {
                cx0 = it.clip.position.x; cy0 = it.clip.position.y;
                cx1 = it.clip.position.x + it.clip.size.x; cy1 = it.clip.position.y + it.clip.size.y;
                if (cx1 <= cx0 || cy1 <= cy0) return;
            }
            var blend = it.mat is CanvasItemMaterial cim ? cim.BlendMode : CanvasBlendMode.Mix;
            foreach (var s in dl.segments)
            {
                if (s.vCount == 0) continue;
                bool repeat = s.mode == DrawMode.Normal && s.aux > 0.5f;
                DrawMode mode = s.mode == DrawMode.Hairline ? DrawMode.Normal : s.mode;
                float aux = s.mode == DrawMode.SdfText ? s.aux : 0f;
                RenderBatch b = batches.Count > 0 ? batches[batches.Count - 1] : null;
                if (b == null || b.texture != s.tex || b.mode != mode || b.aux != aux || b.material != it.mat || b.blend != blend || b.repeat != repeat || b.verts.Count > 60000)
                {
                    b = new RenderBatch { texture = s.tex, mode = mode, aux = aux, material = it.mat, materialOwner = it.matOwner, blend = blend, repeat = repeat };
                    batches.Add(b);
                }
                int vb = b.verts.Count;
                if (s.mode == DrawMode.Hairline)
                {
                    for (int i = 0; i + 1 < s.vCount; i += 2)
                    {
                        var a = dl.verts[s.vStart + i];
                        var c = dl.verts[s.vStart + i + 1];
                        Vec2 pa = it.xf.Xform(new Vec2(a.x, a.y)), pc = it.xf.Xform(new Vec2(c.x, c.y));
                        Vec2 d = (pc - pa).Normalized();
                        Vec2 n = new Vec2(-d.y, d.x) * 0.5f;
                        int k = b.verts.Count;
                        b.verts.Add(RV(pa + n, a, it, cx0, cy0, cx1, cy1));
                        b.verts.Add(RV(pa - n, a, it, cx0, cy0, cx1, cy1));
                        b.verts.Add(RV(pc - n, c, it, cx0, cy0, cx1, cy1));
                        b.verts.Add(RV(pc + n, c, it, cx0, cy0, cx1, cy1));
                        b.indices.Add(k); b.indices.Add(k + 1); b.indices.Add(k + 2);
                        b.indices.Add(k); b.indices.Add(k + 2); b.indices.Add(k + 3);
                    }
                    continue;
                }
                for (int i = 0; i < s.vCount; i++)
                {
                    var v = dl.verts[s.vStart + i];
                    Vec2 p = it.xf.Xform(new Vec2(v.x, v.y));
                    b.verts.Add(RV(p, v, it, cx0, cy0, cx1, cy1));
                }
                for (int i = 0; i < s.iCount; i++) b.indices.Add(vb + dl.idx[s.iStart + i] - s.vStart);
            }
        }

        static RVert RV(Vec2 p, GVertex v, Item it, float cx0, float cy0, float cx1, float cy1) =>
            new RVert { x = p.x, y = p.y, u = v.u, v = v.v, c = v.c * it.mod, cx0 = cx0, cy0 = cy0, cx1 = cx1, cy1 = cy1 };

        /// <summary>End of frame: deferred calls (minimum-size updates, container sorts) and redraws of dirty items, until
        /// nothing changes (Godot runs queue_redraw's _redraw_callback through the same deferred queue).</summary>
        internal void UpdateLayout()
        {
            var tree = GetTree();
            if (tree == null) return;
            StyleBox.CurrentOversampling = _scale;
            for (int pass = 0; pass < 8; pass++)
            {
                tree.FlushDeferred();
                bool any = tree.ProcessRedraws();
                if (!any && !tree.HasDeferred) break;
            }
        }
    }

#if FB3D
    /// <summary>Godot's SubViewport: its own canvas and 3D view (its world, or its parent's), rendered by the host into
    /// a texture (get_texture()) that a TextureRect shows.</summary>
    public partial class SubViewport : Viewport
    {
        public enum UpdateMode { Disabled = 0, Once = 1, WhenVisible = 2, WhenParentVisible = 3, Always = 4 }
        public enum ClearModeEnum { Always = 0, Never = 1, Once = 2 }
        public const UpdateMode UPDATE_DISABLED = UpdateMode.Disabled, UPDATE_ONCE = UpdateMode.Once, UPDATE_WHEN_VISIBLE = UpdateMode.WhenVisible,
            UPDATE_WHEN_PARENT_VISIBLE = UpdateMode.WhenParentVisible, UPDATE_ALWAYS = UpdateMode.Always;
        public const ClearModeEnum CLEAR_MODE_ALWAYS = ClearModeEnum.Always, CLEAR_MODE_NEVER = ClearModeEnum.Never, CLEAR_MODE_ONCE = ClearModeEnum.Once;

        Vec2i _size = new Vec2i(512, 512);
        UpdateMode _update = UpdateMode.WhenVisible;
        ClearModeEnum _clear = ClearModeEnum.Always;
        public Vec2i Size2DOverride;
        public bool Size2DOverrideStretch;
        /// <summary>Bumped by UPDATE_ONCE requests: the renderer draws one frame when it sees a new value.</summary>
        public int UpdateOnceCounter { get; private set; }

        public SubViewport()
        {
            SetVisibleSize(new Vec2(_size.x, _size.y));
        }

        public new Vec2i Size
        {
            get => _size;
            set
            {
                _size = new Vec2i(Math.Max(1, value.x), Math.Max(1, value.y));
                SetVisibleSize(new Vec2(_size.x, _size.y));
                RenderSync.MarkViewport(this);
            }
        }

        public UpdateMode RenderTargetUpdateMode
        {
            get => _update;
            set
            {
                _update = value;
                if (value == UpdateMode.Once) UpdateOnceCounter++;
                RenderSync.MarkViewport(this);
            }
        }

        public ClearModeEnum RenderTargetClearMode { get => _clear; set { _clear = value; RenderSync.MarkViewport(this); } }

        public override Vec2 Get3DSize() => new Vec2(_size.x, _size.y);

        /// <summary>Whether the host should draw it this frame (UPDATE_WHEN_VISIBLE: when the controls showing it are).</summary>
        public bool ShouldRender()
        {
            switch (_update)
            {
                case UpdateMode.Disabled: return false;
                case UpdateMode.Always: return true;
                case UpdateMode.Once: return true;
                default: return IsVisibleForUpdate();
            }
        }

        bool IsVisibleForUpdate()
        {
            // a SubViewport shown by a texture: visible when its parent control (a SubViewportContainer, or the
            // control it lives under) is visible
            for (var p = Parent; p != null; p = p.Parent)
            {
                if (p is CanvasItem ci) return ci.IsVisibleInTree();
                if (p is Node3D n3) return n3.IsVisibleInTree();
                if (p is Viewport) return true;
            }
            return true;
        }
    }
#endif
}
