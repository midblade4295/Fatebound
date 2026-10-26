// Fatebound GUI (Unity port): Godot's Node / SceneTree semantics for the ported UI code -- the child list, entering and
// leaving the tree, _ready/_process/_input order, deferred calls, queue_free, timers, meta. Pure C# (no UnityEngine):
// the Unity host (Client/GUIHost) and the test host drive SceneTree.Iterate() once a frame.
using System;
using System.Collections.Generic;
using System.Reflection;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public enum ProcessModeEnum { Inherit, Pausable, WhenPaused, Always, Disabled }

    public class Node : IGodotObject
    {
        public const int NOTIFICATION_ENTER_TREE = 10, NOTIFICATION_EXIT_TREE = 11, NOTIFICATION_READY = 13,
            NOTIFICATION_PAUSED = 14, NOTIFICATION_UNPAUSED = 15, NOTIFICATION_PROCESS = 17, NOTIFICATION_PARENTED = 18,
            NOTIFICATION_UNPARENTED = 19, NOTIFICATION_PREDELETE = 1, NOTIFICATION_POST_ENTER_TREE = 27,
            NOTIFICATION_RESIZED = 40, NOTIFICATION_DRAW = 30, NOTIFICATION_VISIBILITY_CHANGED = 31,
            NOTIFICATION_THEME_CHANGED = 45, NOTIFICATION_SORT_CHILDREN = 50, NOTIFICATION_WM_GO_BACK_REQUEST = 1007,
            NOTIFICATION_APPLICATION_PAUSED = 2015, NOTIFICATION_APPLICATION_RESUMED = 2014,
            NOTIFICATION_APPLICATION_FOCUS_IN = 2016, NOTIFICATION_APPLICATION_FOCUS_OUT = 2017;

        string _name;
        public string Name
        {
            get => _name ?? GetType().Name;
            set => _name = value;
        }

        public Node Parent { get; private set; }
        internal readonly List<Node> children = new List<Node>();
        SceneTree _tree;
        bool _ready;
        bool _queued;
        bool _freed;
        public ProcessModeEnum ProcessMode = ProcessModeEnum.Inherit;
        public int ProcessPriority;
        bool? _processOn, _physicsOn, _inputOn, _unhandledOn;
        Dictionary<string, object> _meta;
        HashSet<string> _groups;
        public Node Owner;
        static ulong _nextId = 1;
        readonly ulong _instanceId = _nextId++;
        internal Viewport vpCache;
        internal bool internalProcessOn;
        /// <summary>Position in SceneTree.TreeOrder() (valid after it was last rebuilt).</summary>
        internal int treeIndex;
        int _ovr = -1;

        /// <summary>get_instance_id().</summary>
        public ulong GetInstanceId() => _instanceId;
        /// <summary>get_class(): the engine class this node is (a game class reports the framework class it extends).</summary>
        public string GetClass()
        {
            for (var t = GetType(); t != null; t = t.BaseType)
                if (t.Namespace == typeof(Node).Namespace) return t.Name;
            return "Node";
        }
        public static implicit operator Var(Node n) => n == null ? Var.Nil : Var.Of(n);

        public event Action TreeEntered, TreeExiting, TreeExited, Ready, Renamed;
        public event Action<Node> ChildEnteredTree, ChildExitingTree;
        public event Action ChildOrderChanged;

        // ---------- tree ----------
        public bool IsInsideTree() => _tree != null;
        public SceneTree GetTree() => _tree ?? SceneTree.Current;
        public bool IsQueuedForDeletion() => _queued;
        public bool IsFreed => _freed;
        public bool IsNodeReady() => _ready;

        public Node GetParent() => Parent;
        public T GetParentOrNull<T>() where T : class => Parent as T;
        /// <summary>Internal children (a ScrollContainer's scroll bars): drawn and hit-tested, but not in get_child().</summary>
        public enum InternalMode { Disabled = 0, Front = 1, Back = 2 }
        internal InternalMode internalMode;
        int _front, _back;

        public int GetChildCount(bool includeInternal = false) => includeInternal ? children.Count : children.Count - _front - _back;

        public Node GetChild(int i, bool includeInternal = false)
        {
            int n = GetChildCount(includeInternal);
            if (i < 0) i += n;
            if (i < 0 || i >= n) return null;
            return children[includeInternal ? i : i + _front];
        }

        public T GetChild<T>(int i, bool includeInternal = false) where T : Node => GetChild(i, includeInternal) as T;

        public List<Node> GetChildren(bool includeInternal = false) =>
            includeInternal ? new List<Node>(children) : children.GetRange(_front, children.Count - _front - _back);

        public int GetIndex(bool includeInternal = false)
        {
            if (Parent == null) return -1;
            int i = Parent.children.IndexOf(this);
            return includeInternal || internalMode != InternalMode.Disabled ? i : i - Parent._front;
        }

        /// <summary>All children including internal ones, in draw order (for the viewport's walks).</summary>
        internal List<Node> AllChildren => children;

        /// <summary>The nearest Viewport above (cached while in the tree, as Godot's data.viewport).</summary>
        public virtual Viewport GetViewport() => vpCache ?? GetTree()?.Root;

        public void AddChild(Node child, bool forceReadableName = false, InternalMode internalMode = InternalMode.Disabled)
        {
            if (child == null || child == this) return;
            if (child.Parent != null) child.Parent.RemoveChild(child);
            child.Parent = this;
            child.internalMode = internalMode;
            if (internalMode == InternalMode.Front) children.Insert(_front++, child);
            else if (internalMode == InternalMode.Back) { children.Add(child); _back++; }
            else children.Insert(children.Count - _back, child);
            child._Notification(NOTIFICATION_PARENTED);
            child.OnParented();
            if (_tree != null)
            {
                child.PropagateEnterTree(_tree);
                if (_readyNotified) child.PropagateReady();
            }
            AddChildNotify(child);
            ChildOrderChanged?.Invoke();
        }

        public void AddSibling(Node sibling)
        {
            if (Parent == null) return;
            Parent.AddChild(sibling);
            Parent.MoveChild(sibling, GetIndex() + 1);
        }

        public void RemoveChild(Node child)
        {
            if (child == null || child.Parent != this) return;
            bool inTree = _tree != null;
            if (inTree) child.PropagateExitTree();
            RemoveChildNotify(child);
            child._Notification(NOTIFICATION_UNPARENTED);
            child.OnUnparented();
            children.Remove(child);
            if (child.internalMode == InternalMode.Front) _front--;
            else if (child.internalMode == InternalMode.Back) _back--;
            child.internalMode = InternalMode.Disabled;
            child.Parent = null;
            ChildOrderChanged?.Invoke();
            if (inTree) child.PropagateAfterExitTree();
        }

        public void MoveChild(Node child, int to)
        {
            int from = children.IndexOf(child);
            if (from < 0) return;
            int lo = 0, hi = children.Count - 1;
            if (child.internalMode == InternalMode.Front) hi = _front - 1;
            else if (child.internalMode == InternalMode.Back) lo = children.Count - _back;
            else { lo = _front; hi = children.Count - _back - 1; }
            int n = hi - lo + 1;
            if (to < 0) to += n;
            to = lo + Math.Max(0, Math.Min(n - 1, to));
            if (from == to) return;
            children.RemoveAt(from);
            children.Insert(to, child);
            _tree?.MarkOrderDirty();
            MoveChildNotify(child);
            ChildOrderChanged?.Invoke();
        }

        public virtual void Reparent(Node newParent, bool keepGlobalTransform = true)
        {
            Parent?.RemoveChild(this);
            newParent.AddChild(this);
        }

        protected virtual void AddChildNotify(Node child) { }
        protected virtual void RemoveChildNotify(Node child) { }
        protected virtual void MoveChildNotify(Node child) { }
        protected virtual void OnParented() { }
        protected virtual void OnUnparented() { }

        bool _readyNotified;

        /// <summary>Entering the tree: this node, then its children (pre-order); ready comes after, children first.</summary>
        internal void PropagateEnterTree(SceneTree tree)
        {
            _tree = tree;
            vpCache = this as Viewport ?? Parent?.vpCache ?? (Parent is Viewport pv ? pv : null);
            tree.Register(this);
            _Notification(NOTIFICATION_ENTER_TREE);
            OnEnterTree();
            _EnterTree();
            TreeEntered?.Invoke();
            Parent?.ChildEnteredTree?.Invoke(this);
            for (int i = 0; i < children.Count; i++) children[i].PropagateEnterTree(tree);
        }

        internal void PropagateReady()
        {
            _readyNotified = true;
            for (int i = 0; i < children.Count; i++) children[i].PropagateReady();
            _Notification(NOTIFICATION_POST_ENTER_TREE);
            OnPostEnterTree();
            if (!_ready)
            {
                _ready = true;
                _Notification(NOTIFICATION_READY);
                _Ready();
                Ready?.Invoke();
            }
        }

        internal void PropagateExitTree()
        {
            for (int i = children.Count - 1; i >= 0; i--) children[i].PropagateExitTree();
            _ExitTree();
            TreeExiting?.Invoke();
            _Notification(NOTIFICATION_EXIT_TREE);
            OnExitTree();
            _tree?.Unregister(this);
            Parent?.ChildExitingTree?.Invoke(this);
            _readyNotified = false;
            _tree = null;
            vpCache = null;
        }

        internal void PropagateAfterExitTree()
        {
            for (int i = children.Count - 1; i >= 0; i--) children[i].PropagateAfterExitTree();
            TreeExited?.Invoke();
        }

        protected virtual void OnEnterTree() { }
        protected virtual void OnPostEnterTree() { }
        protected virtual void OnExitTree() { }

        /// <summary>queue_free(): out of the tree at the end of this frame, then freed.</summary>
        public void QueueFree()
        {
            if (_queued || _freed) return;
            _queued = true;
            var t = GetTree();
            if (t != null) t.QueueDelete(this);
            else Free();
        }

        public void Free()
        {
            if (_freed) return;
            Parent?.RemoveChild(this);
            FreeRecursive();
        }

        void FreeRecursive()
        {
            for (int i = children.Count - 1; i >= 0; i--) children[i].FreeRecursive();
            _Notification(NOTIFICATION_PREDELETE);
            OnFreed();
            children.Clear();
            _freed = true;
        }

        protected virtual void OnFreed() { }

        /// <summary>is_instance_valid(node).</summary>
        public static bool IsInstanceValid(Node n) => n != null && !n._freed;

        // ---------- lookup ----------
        public Node GetNodeOrNull(string path)
        {
            if (string.IsNullOrEmpty(path)) return null;
            Node n = this;
            if (path.StartsWith("/"))
            {
                n = GetTree()?.Root;
                path = path.TrimStart('/');
                if (path.StartsWith("root/")) path = path.Substring(5);
                else if (path == "root") return n;
            }
            foreach (var part in path.Split('/'))
            {
                if (n == null) return null;
                if (part == "" || part == ".") continue;
                if (part == "..") { n = n.Parent; continue; }
                Node found = null;
                foreach (var c in n.children)
                    if (c.Name == part) { found = c; break; }
                n = found;
            }
            return n;
        }

        public T GetNodeOrNull<T>(string path) where T : Node => GetNodeOrNull(path) as T;
        public Node GetNode(string path) => GetNodeOrNull(path);
        public T GetNode<T>(string path) where T : Node => GetNodeOrNull(path) as T;
        public bool HasNode(string path) => GetNodeOrNull(path) != null;

        public Node FindChild(string pattern, bool recursive = true, bool owned = true)
        {
            foreach (var c in children)
            {
                if (Match(c.Name, pattern)) return c;
                if (recursive)
                {
                    var r = c.FindChild(pattern, true, owned);
                    if (r != null) return r;
                }
            }
            return null;
        }

        public List<Node> FindChildren(string pattern, string type = "", bool recursive = true, bool owned = true)
        {
            var o = new List<Node>();
            foreach (var c in children)
            {
                if (Match(c.Name, pattern) && (type == "" || c.IsClass(type))) o.Add(c);
                if (recursive) o.AddRange(c.FindChildren(pattern, type, true, owned));
            }
            return o;
        }

        public virtual bool IsClass(string type)
        {
            for (var t = GetType(); t != null && t != typeof(object); t = t.BaseType)
                if (t.Name == type) return true;
            return false;
        }

        static bool Match(string name, string pattern)
        {
            if (pattern == "*") return true;
            if (!pattern.Contains("*") && !pattern.Contains("?")) return name == pattern;
            var rx = "^" + System.Text.RegularExpressions.Regex.Escape(pattern).Replace("\\*", ".*").Replace("\\?", ".") + "$";
            return System.Text.RegularExpressions.Regex.IsMatch(name, rx);
        }

        public bool IsAncestorOf(Node n)
        {
            for (var p = n?.Parent; p != null; p = p.Parent)
                if (p == this) return true;
            return false;
        }

        // ---------- processing ----------
        protected virtual void _Ready() { }
        protected virtual void _EnterTree() { }
        protected virtual void _ExitTree() { }
        protected virtual void _Process(double delta) { }
        protected virtual void _PhysicsProcess(double delta) { }
        protected virtual void _Input(InputEvent e) { }
        protected virtual void _UnhandledInput(InputEvent e) { }
        public virtual void _Notification(int what) { }

        public void Notification(int what) => _Notification(what);

        /// <summary>Godot's _set for stored properties with dynamic names ("bones/3/rest", "surface_material_override/0"):
        /// the baked-scene loader calls it first; true = handled (see Resource.SetStoredProperty).</summary>
        public virtual bool SetStoredProperty(string name, Var value) => false;

        internal void CallProcess(double delta) => _Process(delta);
        internal void CallPhysicsProcess(double delta) => _PhysicsProcess(delta);
        internal void CallInput(InputEvent e) => _Input(e);
        internal void CallUnhandledInput(InputEvent e) => _UnhandledInput(e);

        static readonly Dictionary<Type, int> _overrides = new Dictionary<Type, int>();
        int Overrides()
        {
            if (_ovr >= 0) return _ovr;
            _ovr = TypeOverrides(GetType());
            return _ovr;
        }

        static int TypeOverrides(Type t)
        {
            lock (_overrides)
            {
                if (_overrides.TryGetValue(t, out var f)) return f;
                int flags = 0;
                if (Declares(t, "_Process")) flags |= 1;
                if (Declares(t, "_PhysicsProcess")) flags |= 2;
                if (Declares(t, "_Input")) flags |= 4;
                if (Declares(t, "_UnhandledInput")) flags |= 8;
                _overrides[t] = flags;
                return flags;
            }
        }

        static bool Declares(Type t, string method)
        {
            for (var x = t; x != null && x != typeof(Node); x = x.BaseType)
            {
                var m = x.GetMethod(method, BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public | BindingFlags.DeclaredOnly);
                if (m != null && x.Namespace != typeof(Node).Namespace) return true;
            }
            return false;
        }

        /// <summary>As Godot: a script defining _process processes unless set_process(false).</summary>
        public bool IsProcessing() => _processOn ?? (Overrides() & 1) != 0;
        public bool IsPhysicsProcessing() => _physicsOn ?? (Overrides() & 2) != 0;
        public bool IsProcessingInput() => _inputOn ?? (Overrides() & 4) != 0;
        public bool IsProcessingUnhandledInput() => _unhandledOn ?? (Overrides() & 8) != 0;
        public void SetProcess(bool on) { if (_processOn != on) { _processOn = on; _tree?.MarkProcessDirty(); } }
        public void SetPhysicsProcess(bool on) { if (_physicsOn != on) { _physicsOn = on; _tree?.MarkProcessDirty(); } }
        public void SetProcessInput(bool on) { if (_inputOn != on) { _inputOn = on; _tree?.MarkProcessDirty(); } }
        public void SetProcessUnhandledInput(bool on) { if (_unhandledOn != on) { _unhandledOn = on; _tree?.MarkProcessDirty(); } }
        /// <summary>Internal processing (the engine's own per-frame work: particles' timing, animation players...),
        /// separate from the script's _process.</summary>
        public void SetProcessInternal(bool on) { if (internalProcessOn != on) { internalProcessOn = on; _tree?.MarkProcessDirty(); } }
        public bool IsProcessingInternal() => internalProcessOn;
        protected virtual void InternalProcess(double delta) { }
        internal void CallInternalProcess(double delta) => InternalProcess(delta);

        /// <summary>can_process(): not paused out (process_mode against SceneTree.paused).</summary>
        public bool CanProcess()
        {
            var t = GetTree();
            if (t == null) return false;
            ProcessModeEnum m = ProcessMode;
            for (var n = this; m == ProcessModeEnum.Inherit && n != null; n = n.Parent) m = n.ProcessMode;
            if (m == ProcessModeEnum.Inherit) m = ProcessModeEnum.Pausable;
            switch (m)
            {
                case ProcessModeEnum.Disabled: return false;
                case ProcessModeEnum.Always: return true;
                case ProcessModeEnum.WhenPaused: return t.Paused;
                default: return !t.Paused;
            }
        }

        // ---------- deferred, tweens, timers ----------
        public void CallDeferred(Action a) => (GetTree() ?? SceneTree.Current)?.Defer(a);

        public Tween CreateTween()
        {
            var t = new Tween(this);
            (GetTree() ?? SceneTree.Current)?.AddTween(t);
            return t;
        }

        // ---------- meta / groups ----------
        public void SetMeta(string key, object value)
        {
            if (_meta == null) _meta = new Dictionary<string, object>();
            _meta[key] = value;
        }

        public object GetMeta(string key, object dflt = null) => _meta != null && _meta.TryGetValue(key, out var v) ? v : dflt;
        public T GetMeta<T>(string key, T dflt = default) => _meta != null && _meta.TryGetValue(key, out var v) && v is T t ? t : dflt;
        public bool HasMeta(string key) => _meta != null && _meta.ContainsKey(key);
        public void RemoveMeta(string key) => _meta?.Remove(key);

        public void AddToGroup(string g)
        {
            if (_groups == null) _groups = new HashSet<string>();
            _groups.Add(g);
        }

        public void RemoveFromGroup(string g) => _groups?.Remove(g);
        public bool IsInGroup(string g) => _groups != null && _groups.Contains(g);

        public override string ToString() => Name + ":<" + GetType().Name + ">";
    }

    public sealed class SceneTreeTimer
    {
        public double TimeLeft;
        public bool ProcessAlways, IgnoreTimeScale;
        public event Action Timeout;
        internal bool done;
        internal void Fire() { done = true; Timeout?.Invoke(); }
        public void Cancel() => done = true;
    }

    /// <summary>The Timer node (one-shot or repeating).</summary>
    public class Timer : Node
    {
        public double WaitTime = 1.0;
        public bool OneShot;
        public bool Autostart;
        public bool Paused;
        public double TimeLeft { get; private set; }
        bool _running;
        public event Action Timeout;

        protected override void _Ready()
        {
            if (Autostart) Start();
        }

        public void Start(double time = -1)
        {
            if (time > 0) WaitTime = time;
            TimeLeft = WaitTime;
            _running = true;
            SetProcess(true);
        }

        public void Stop() { _running = false; TimeLeft = 0; }
        public bool IsStopped() => !_running;

        protected override void _Process(double delta)
        {
            if (!_running || Paused) return;
            TimeLeft -= delta;
            if (TimeLeft <= 0)
            {
                if (OneShot) _running = false;
                else TimeLeft += WaitTime;
                Timeout?.Invoke();
            }
        }
    }

    /// <summary>The scene tree: owns the root viewport, runs a frame (input, process, timers, tweens, deferred calls,
    /// deletions, layout), as Godot's main loop iteration does.</summary>
    public class SceneTree
    {
        public static SceneTree Current;
        public Viewport Root { get; private set; }
        public bool Paused;
        public double TimeScale = 1.0;
        public ulong Frame { get; private set; }
        /// <summary>Seconds since start (Time.get_ticks_msec()/1000).</summary>
        public double Now { get; private set; }
        public event Action ProcessFrame, PhysicsFrame;

        bool _nodesDirty = true, _procDirty = true;
        int _nodeCount;
        readonly List<Node> _ordered = new List<Node>();
        readonly List<Node> _proc = new List<Node>(), _phys = new List<Node>(), _input = new List<Node>(), _unhandled = new List<Node>();
        readonly List<CanvasItem> _redraw = new List<CanvasItem>();
        CanvasItem[] _redrawScratch = new CanvasItem[64];
        Node[] _scratch = new Node[256];
#if FB3D
        internal readonly List<Node3D> xformChangeList = new List<Node3D>();
#endif
        readonly List<Action> _deferred = new List<Action>();
        readonly List<Node> _deleteQueue = new List<Node>();
        readonly List<SceneTreeTimer> _timers = new List<SceneTreeTimer>();
        readonly List<Tween> _tweens = new List<Tween>();
        double _physicsAcc;
        public double PhysicsTicksPerSecond = 60.0;
        public bool QuitRequested { get; private set; }
        public int QuitCode;

        public SceneTree(Vec2 size)
        {
            Current = this;
            Root = new Viewport { Name = "root" };
            Root.SetVisibleSize(size);
            Root.PropagateEnterTree(this);
            Root.PropagateReady();
        }

        internal void Register(Node n) { _nodeCount++; _nodesDirty = true; _procDirty = true; }
        internal void Unregister(Node n) { _nodeCount--; _nodesDirty = true; _procDirty = true; }
        internal void MarkOrderDirty() { _nodesDirty = true; _procDirty = true; }
        internal void MarkProcessDirty() => _procDirty = true;
        public int GetNodeCount() => _nodeCount;

        /// <summary>Every node in tree order (parents before children, siblings in order). Rebuilt only after the
        /// tree changed; don't change the tree while walking it (copy it first).</summary>
        public List<Node> TreeOrder()
        {
            if (_nodesDirty)
            {
                _ordered.Clear();
                Walk(Root);
                _nodesDirty = false;
            }
            return _ordered;
        }

        void Walk(Node n)
        {
            n.treeIndex = _ordered.Count;
            _ordered.Add(n);
            var c = n.children;
            for (int i = 0; i < c.Count; i++) Walk(c[i]);
        }

        void RebuildProcessLists()
        {
            if (!_procDirty) return;
            var order = TreeOrder();
            _proc.Clear(); _phys.Clear(); _input.Clear(); _unhandled.Clear();
            bool prio = false;
            for (int i = 0; i < order.Count; i++)
            {
                var n = order[i];
                if (n.IsProcessing() || n.internalProcessOn) { _proc.Add(n); if (n.ProcessPriority != 0) prio = true; }
                if (n.IsPhysicsProcessing()) _phys.Add(n);
                if (n.IsProcessingInput()) _input.Add(n);
                if (n.IsProcessingUnhandledInput()) _unhandled.Add(n);
            }
            if (prio) StableByPriority(_proc);
            _procDirty = false;
        }

        static void StableByPriority(List<Node> l)
        {
            var idx = new Dictionary<Node, int>(l.Count);
            for (int i = 0; i < l.Count; i++) idx[l[i]] = i;
            l.Sort((a, b) => a.ProcessPriority != b.ProcessPriority ? a.ProcessPriority.CompareTo(b.ProcessPriority) : idx[a].CompareTo(idx[b]));
        }

        /// <summary>A copy of a list in a reused buffer (what Godot's process groups iterate: nodes added meanwhile wait
        /// for the next frame, removed ones are skipped by their checks).</summary>
        int Snapshot(List<Node> l)
        {
            if (_scratch.Length < l.Count) _scratch = new Node[Math.Max(l.Count, _scratch.Length * 2)];
            l.CopyTo(_scratch);
            return l.Count;
        }

        /// <summary>_input then (if not handled) the GUI, then _unhandled_input: in reverse tree order, as Godot.</summary>
        internal void DispatchInput(InputEvent ev, Viewport vp, bool unhandled)
        {
            RebuildProcessLists();
            var l = unhandled ? _unhandled : _input;
            var arr = l.ToArray();
            for (int i = arr.Length - 1; i >= 0 && !vp.IsInputHandled(); i--)
            {
                var n = arr[i];
                if (!n.IsInsideTree() || n.IsFreed || !n.CanProcess()) continue;
                if (unhandled) { if (n.IsProcessingUnhandledInput()) Safe(() => n.CallUnhandledInput(ev)); }
                else if (n.IsProcessingInput()) Safe(() => n.CallInput(ev));
            }
        }

        /// <summary>queue_redraw(): the item's _draw runs before the frame is drawn.</summary>
        internal void QueueRedrawItem(CanvasItem ci)
        {
            if (ci.inRedrawQueue) return;
            ci.inRedrawQueue = true;
            _redraw.Add(ci);
        }

        /// <summary>Runs the queued redraws (hidden items wait until they're shown). True if any drew.</summary>
        internal bool ProcessRedraws()
        {
            bool any = false;
            for (int pass = 0; pass < 4 && _redraw.Count > 0; pass++)
            {
                int n = _redraw.Count;
                if (_redrawScratch.Length < n) _redrawScratch = new CanvasItem[Math.Max(n, _redrawScratch.Length * 2)];
                _redraw.CopyTo(_redrawScratch);
                _redraw.Clear();
                for (int i = 0; i < n; i++)
                {
                    var ci = _redrawScratch[i];
                    _redrawScratch[i] = null;
                    ci.inRedrawQueue = false;
                    if (ci.drawDirty && ci.IsInsideTree() && !ci.IsFreed && ci.IsVisibleInTree()) { ci.Redraw(); any = true; }
                }
            }
            return any;
        }

#if FB3D
        /// <summary>NOTIFICATION_TRANSFORM_CHANGED to every Node3D whose global transform changed (and asked to hear
        /// it), as SceneTree::flush_transform_notifications.</summary>
        public void FlushTransformNotifications()
        {
            for (int i = 0; i < xformChangeList.Count; i++)
            {
                var n = xformChangeList[i];
                if (!n.inXformChangeList) continue;
                Safe(n.DeliverTransformChanged);
            }
            xformChangeList.Clear();
        }
#else
        public void FlushTransformNotifications() { }
#endif

        public void Defer(Action a) { lock (_deferred) _deferred.Add(a); }
        public bool HasDeferred { get { lock (_deferred) return _deferred.Count > 0; } }

        public void FlushDeferred()
        {
            for (int pass = 0; pass < 64; pass++)
            {
                Action[] batch;
                lock (_deferred)
                {
                    if (_deferred.Count == 0) return;
                    batch = _deferred.ToArray();
                    _deferred.Clear();
                }
                foreach (var a in batch)
                {
                    try { a(); }
                    catch (Exception ex) { GD_Log.Error("deferred call: " + ex); }
                }
            }
        }

        internal void QueueDelete(Node n) => _deleteQueue.Add(n);
        internal void AddTween(Tween t) => _tweens.Add(t);

        public SceneTreeTimer CreateTimer(double seconds, bool processAlways = true, bool processInPhysics = false, bool ignoreTimeScale = false)
        {
            var t = new SceneTreeTimer { TimeLeft = seconds, ProcessAlways = processAlways, IgnoreTimeScale = ignoreTimeScale };
            _timers.Add(t);
            return t;
        }

        public Tween CreateTween()
        {
            var t = new Tween(null);
            _tweens.Add(t);
            return t;
        }

        public void Quit(int code = 0) { QuitRequested = true; QuitCode = code; }

        /// <summary>Godot quits on Android's back button unless this is off; the game handles back itself (siege_app's
        /// NOTIFICATION_WM_GO_BACK_REQUEST closes windows, then quits from Home), so the port leaves it off.</summary>
        public bool QuitOnGoBack = false;

        /// <summary>propagate_notification from the root (window events: go-back, focus, pause/resume).</summary>
        public void PropagateNotification(int what)
        {
            foreach (var n in TreeOrder().ToArray())
                if (n.IsInsideTree()) Safe(() => n._Notification(what));
        }

        /// <summary>Android's back button.</summary>
        public void GoBackRequest()
        {
            PropagateNotification(Node.NOTIFICATION_WM_GO_BACK_REQUEST);
            if (QuitOnGoBack) Quit();
        }

        public Node CurrentScene;

        /// <summary>change_scene_to_node: the old scene is freed at the end of the frame.</summary>
        public void ChangeSceneToNode(Node scene)
        {
            var old = CurrentScene;
            CurrentScene = scene;
            if (old != null) old.QueueFree();
            Defer(() => Root.AddChild(scene));
        }

        /// <summary>One frame: input events first (the host queues them), physics ticks, process, timers, tweens,
        /// deferred calls, deletions, then the layout settles and dirty canvas items redraw.</summary>
        public void Iterate(double delta)
        {
            Frame++;
            Now += delta;
            double scaled = delta * TimeScale;
            Root.FlushInput();
            FlushDeferred();
            _physicsAcc += delta;
            double step = 1.0 / PhysicsTicksPerSecond;
            int ticks = 0;
            while (_physicsAcc >= step && ticks < 8)
            {
                _physicsAcc -= step;
                ticks++;
                FlushTransformNotifications();
                PhysicsFrame?.Invoke();
                RebuildProcessLists();
                int n = Snapshot(_phys);
                double pd = step * TimeScale;
                for (int i = 0; i < n; i++)
                {
                    var nd = _scratch[i];
                    _scratch[i] = null;
                    if (nd.IsInsideTree() && !nd.IsFreed && nd.IsPhysicsProcessing() && nd.CanProcess()) Safe(nd, pd, _physCall);
                }
                FlushDeferred();
                FlushTransformNotifications();
            }
            if (ticks == 8) _physicsAcc = 0;
            ProcessFrame?.Invoke();
            FlushDeferred();
            FlushTransformNotifications();
            RebuildProcessLists();
            {
                // tree order (process_priority first): each node's internal processing, then its _process
                int n = Snapshot(_proc);
                for (int i = 0; i < n; i++)
                {
                    var nd = _scratch[i];
                    _scratch[i] = null;
                    if (!nd.IsInsideTree() || nd.IsFreed || !nd.CanProcess()) continue;
                    if (nd.internalProcessOn) Safe(nd, scaled, _internalCall);
                    if (nd.IsProcessing() && nd.IsInsideTree()) Safe(nd, scaled, _procCall);
                }
            }
            FlushDeferred();
            FlushTransformNotifications();
            for (int i = 0; i < _timers.Count; i++)
            {
                var t = _timers[i];
                if (t.done) continue;
                if (Paused && !t.ProcessAlways) continue;
                t.TimeLeft -= t.IgnoreTimeScale ? delta : scaled;
                if (t.TimeLeft <= 0) Safe(t.Fire);
            }
            _timers.RemoveAll(t => t.done);
            for (int i = 0; i < _tweens.Count; i++)
            {
                var tw = _tweens[i];
                if (!tw.IsValid()) continue;
                Safe(() => tw.Step(scaled, delta, Paused));
            }
            _tweens.RemoveAll(t => !t.IsValid());
            FlushDeferred();
            FlushTransformNotifications();
            if (_deleteQueue.Count > 0)
            {
                var del = _deleteQueue.ToArray();
                _deleteQueue.Clear();
                foreach (var n in del) n.Free();
            }
            Root.UpdateLayout();
        }


        internal static void Safe(Action a)
        {
            try { a(); }
            catch (Exception ex) { GD_Log.Error(ex.ToString()); }
        }

        // (no closure per node per frame)
        static readonly Action<Node, double> _procCall = (n, d) => n.CallProcess(d);
        static readonly Action<Node, double> _physCall = (n, d) => n.CallPhysicsProcess(d);
        static readonly Action<Node, double> _internalCall = (n, d) => n.CallInternalProcess(d);

        static void Safe(Node n, double d, Action<Node, double> a)
        {
            try { a(n, d); }
            catch (Exception ex) { GD_Log.Error(n.Name + ": " + ex); }
        }
    }

    /// <summary>print / push_error / push_warning from the framework: through Fatebound.Sim.GD's sinks (the host points
    /// those at its log).</summary>
    public static class GD_Log
    {
        public static void Print(params object[] parts) => Fatebound.Sim.GD.PrintSink?.Invoke(string.Concat(Array.ConvertAll(parts, p => Fatebound.Sim.GFormat.Str(Fatebound.Sim.Var.Of(p)))));
        public static void Error(string s) => Fatebound.Sim.GD.ErrorSink?.Invoke(s);
        public static void Warning(string s) => Fatebound.Sim.GD.WarningSink?.Invoke(s);
    }
}
