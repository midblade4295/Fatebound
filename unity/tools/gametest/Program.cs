// `gametest`: the whole game headless, off the device -- the sim, the GUI layer and the translated game scripts as the
// Unity build has them, its files from the test host (Assets/Resources/res), a fresh user://, answering as an Android
// phone does, with no 3D renderer or physics backend and the network cut off (NetworkPolicy: nothing reaches the
// real servers). A script taps through it; the 2D layers are saved as screenshots (SoftRaster: the 3D view is not
// drawn) and every error, warning and exception the game logs is printed with its frame time.
//
//   dotnet run -c Release --project unity/tools/gametest -- <script> <out dir> [window w h]
//
// Script lines ('#' comments):
//   wait <seconds>             run the game that long (60 frames a second)
//   until <seconds> <text>     run until a visible button or label shows <text> (or the time is up: logged)
//   shot <name>                save <out dir>/<name>.png
//   tap <text>                 tap the visible button whose text is <text> (case-insensitive; else a label's)
//   tapall <max> <text>       tap it while it shows (up to max times)
//   tapnode <name>             tap the visible control named <name>
//   tapat <x> <y>              tap at logical (760x420-space) coordinates
//   type <text>                type into the focused (else the first visible) text field; submit: press its Enter
//   tree                       print the visible controls (class, name, text, rect)
// SIEGE_URL=ws://127.0.0.1:<port>/ plays against a local server (godot --headless --path godot -s
// res://server/siege_server.gd with SIEGE_HOST=127.0.0.1 SIEGE_PORT=<port>): only loopback hosts are let through, and
// the game runs in real time (as GT_REALTIME=1 does), the server's clock being the wall's.
// GT_DESKTOP=1: answer as a headless Linux desktop instead of an Android phone.
// Exit code: 1 if the game threw (an exception reached the scene tree) or a tap found nothing, else 0.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using Fatebound.GUI;
using Fatebound.Sim;
using GuiTest;
using GInput = Fatebound.GUI.Input;

namespace GameTest
{
    /// <summary>A headless Linux desktop (GT_DESKTOP=1): the framework's defaults.</summary>
    sealed class DesktopPlatform : DefaultPlatform
    {
        readonly string _user, _cache;
        public DesktopPlatform(string user, string cache) { _user = user; _cache = cache; }
        public override string UserDataDir => _user;
        public override string CacheDir => _cache;
    }

    sealed class TestPlatform : DefaultPlatform
    {
        readonly string _user, _cache;
        public TestPlatform(string user, string cache) { _user = user; _cache = cache; }
        public override string OSName => "Android";
        public override string DisplayName => "Android";
        public override string ModelName => "gametest";
        public override string OSVersion => "34.gametest";
        public override string Locale => "en_US";
        public override string UserDataDir => _user;
        public override string CacheDir => _cache;
        public override string UniqueId => "gametest";
        public override bool HasFeature(string tag)
        {
            switch (tag)
            {
                case "android": case "mobile": case "64": case "arm64": case "template": case "etc2": case "astc": case "single":
                case "debug": case "template_debug":
                    return true;
            }
            return false;
        }
        public override int ShellOpen(string uri) { Program.Log("SHELL_OPEN " + uri); return GD.OK; }
        public override bool HasDisplayFeature(int feature) =>
            feature == DisplayServer.FEATURE_TOUCHSCREEN || feature == DisplayServer.FEATURE_ORIENTATION || feature == DisplayServer.FEATURE_KEEP_SCREEN_ON;
    }

    public static class Program
    {
        public const string Repo = "/home/claude/midblade4295/fatebound";
        static SceneTree _tree;
        static double _t;
        static int _errors, _exceptions, _warnings, _failed, _frames;
        static double _iterMs, _drawMs;
        static bool _realtime;
        static readonly System.Diagnostics.Stopwatch _wall = new System.Diagnostics.Stopwatch();
        static string _out;
        static readonly HashSet<string> _seen = new HashSet<string>();

        public static void Log(string s) => Console.WriteLine($"[{_t,7:F2}] {s}");

        public static int Main(string[] args)
        {
            CultureInfo.DefaultThreadCurrentCulture = CultureInfo.InvariantCulture;
            CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
            if (args.Length < 2) { Console.WriteLine("gametest <script> <out dir> [w h]"); return 2; }
            _out = args[1];
            Directory.CreateDirectory(_out);
            int ww = args.Length > 3 ? int.Parse(args[2]) : 1600, wh = args.Length > 3 ? int.Parse(args[3]) : 720;
            string user = "/tmp/fb-gametest/user", cache = "/tmp/fb-gametest/cache-dir";
            if (Directory.Exists(user) && System.Environment.GetEnvironmentVariable("KEEP_USER") == null) Directory.Delete(user, true);
            Directory.CreateDirectory(user);
            Directory.CreateDirectory(cache);

            GD.PrintSink = s => Log("print " + s);
            GD.ErrorSink = s =>
            {
                _errors++;
                bool ex = s.Contains("Exception") && s.Contains("   at ");
                if (ex) _exceptions++;
                // (a repeated error once, with its count at the end)
                string key = s.Length > 300 ? s.Substring(0, 300) : s;
                if (_seen.Add(key)) Log((ex ? "EXCEPTION " : "ERROR ") + Trim(s, ex ? 14 : 4));
            };
            GD.WarningSink = s =>
            {
                _warnings++;
                if (_seen.Add("W" + s)) Log("WARNING " + Trim(s, 3));
            };
            NetworkPolicy.Allow = uri =>
            {
                // a local test server (SIEGE_URL=ws://127.0.0.1:<port>/..., godot/server/siege_server.gd run on loopback)
                if (uri.IsLoopback) return true;
                if (_seen.Add("NET " + uri.Host)) Log("NET blocked " + uri.Scheme + "://" + uri.Host + uri.AbsolutePath);
                return false;
            };
            bool desktop = System.Environment.GetEnvironmentVariable("GT_DESKTOP") == "1";
            _realtime = System.Environment.GetEnvironmentVariable("SIEGE_URL") != null || System.Environment.GetEnvironmentVariable("GT_REALTIME") == "1";
            _wall.Start();
            PlatformHost.Init(desktop ? new DesktopPlatform(user, cache) : (IPlatform)new TestPlatform(user, cache));
            ResourceLoader.Host = new TestHost(Repo);
            DisplayServer.ScreenSize = new Vec2(ww, wh);
            DisplayServer.SafeArea = new Rect2(0, 0, ww, wh);
            DisplayServer.ScreenDpi = 420;
            GInput.TouchscreenAvailable = true;

            _tree = new SceneTree(new Vec2(760, 420));
            _tree.Root.BaseSize = new Vec2(760, 420);
            _tree.Root.SetWindowSize(new Vec2(ww, wh));
            var sw = System.Diagnostics.Stopwatch.StartNew();
            try { Fatebound.Game.GameMain.Start(_tree); }
            catch (Exception e) { _exceptions++; Log("EXCEPTION at start: " + e); }

            foreach (var raw in File.ReadAllLines(args[0]))
            {
                string line = raw.Trim();
                int hash = line.IndexOf('#');
                if (hash >= 0) line = line.Substring(0, hash).Trim();
                if (line == "") continue;
                var parts = line.Split(' ', 2);
                string cmd = parts[0], arg = parts.Length > 1 ? parts[1].Trim() : "";
                Log("> " + line);
                switch (cmd)
                {
                    case "wait":
                        _frames = 0; _iterMs = _drawMs = 0;
                        Run(double.Parse(arg));
                        Log($"frame cost over the wait: process {_iterMs / Math.Max(1, _frames):F2} ms, 2D draw lists {_drawMs / Math.Max(1, _frames):F2} ms ({_frames} frames)");
                        break;
                    case "until":
                    {
                        var p = arg.Split(' ', 2);
                        double limit = double.Parse(p[0]), end = _t + limit;
                        while (_t < end && Find(p[1], false) == null) Run(1.0 / 60.0);
                        if (Find(p[1], false) == null) { Log("UNTIL timed out: no \"" + p[1] + "\""); _failed++; }
                        break;
                    }
                    case "tapall":
                    {
                        // tapall <max> <text>: tap it while it shows (up to max times, a second apart)
                        var p = arg.Split(' ', 2);
                        int max = int.Parse(p[0]), n = 0;
                        Control c;
                        while (n < max && (c = Find(p[1], true)) != null)
                        {
                            Tap(OnScreen(c));
                            Run(0.8);
                            n++;
                        }
                        Log("tapped " + n + "x");
                        break;
                    }
                    case "shot": Shot(arg); break;
                    case "tap":
                    {
                        var c = Find(arg, true);
                        if (c == null) { Log("TAP: no visible \"" + arg + "\""); _failed++; break; }
                        Tap(OnScreen(c));
                        break;
                    }
                    case "tapnode":
                    {
                        var c = All().FirstOrDefault(n => n.Name == arg);
                        if (c == null) { Log("TAPNODE: no visible " + arg); _failed++; break; }
                        Tap(c.GetGlobalRect().GetCenter());
                        break;
                    }
                    case "tapat":
                    {
                        var p = arg.Split(' ');
                        Tap(new Vec2(float.Parse(p[0]), float.Parse(p[1])));
                        break;
                    }
                    case "type":
                    case "submit":
                    {
                        var le = (_tree.Root.GuiFocus as LineEdit) ?? All().OfType<LineEdit>().FirstOrDefault(l => l.Editable);
                        if (le == null) { Log(cmd.ToUpperInvariant() + ": no visible text field"); _failed++; break; }
                        if (cmd == "type") le.SetTextFromKeyboard(arg);
                        else le.Submit();
                        Run(0.1);
                        break;
                    }
                    case "tree":
                        foreach (var c in All())
                        {
                            string text = Text(c);
                            var r = c.GetGlobalRect();
                            if (text != "" || c is BaseButton)
                                Console.WriteLine($"    {Cls(c)} {NodeName(c)} \"{text.Replace("\n", "\\n")}\" ({r.position.x:F1},{r.position.y:F1} {r.size.x:F1}x{r.size.y:F1})");
                        }
                        break;
                    default: Log("unknown command " + cmd); _failed++; break;
                }
            }
            Log($"done: {_t:F1} s of game in {sw.Elapsed.TotalSeconds:F1} s; {_exceptions} exceptions, {_errors} errors, {_warnings} warnings, {_failed} failed steps");
            return _exceptions > 0 || _failed > 0 ? 1 : 0;
        }

        static string Trim(string s, int lines)
        {
            var l = s.Replace("\r", "").Split('\n');
            return l.Length <= lines ? s : string.Join("\n", l.Take(lines)) + "\n      ...";
        }

        static void Run(double seconds)
        {
            const double DT = 1.0 / 60.0;
            int n = Math.Max(1, (int)Math.Round(seconds / DT));
            for (int i = 0; i < n; i++)
            {
                if (_realtime)
                {
                    // (against a server: the game's clock kept with the wall's)
                    double ahead = _t - _wall.Elapsed.TotalSeconds;
                    if (ahead > 0.002) System.Threading.Thread.Sleep((int)(ahead * 1000));
                }
                _t += DT;
                try
                {
                    long t0 = System.Diagnostics.Stopwatch.GetTimestamp();
                    _tree.Iterate(DT);
                    long t1 = System.Diagnostics.Stopwatch.GetTimestamp();
                    RenderingServer.RaiseFramePreDraw();
                    _tree.Root.Render();
                    RenderingServer.RaiseFramePostDraw();
                    long t2 = System.Diagnostics.Stopwatch.GetTimestamp();
                    _iterMs += (t1 - t0) * 1000.0 / System.Diagnostics.Stopwatch.Frequency;
                    _drawMs += (t2 - t1) * 1000.0 / System.Diagnostics.Stopwatch.Frequency;
                    _frames++;
                }
                catch (Exception e)
                {
                    _exceptions++;
                    if (_seen.Add("X" + e.Message)) Log("EXCEPTION in the frame: " + Trim(e.ToString(), 14));
                }
            }
        }

        static IEnumerable<Control> All()
        {
            var stack = new Stack<Node>();
            stack.Push(_tree.Root);
            var list = new List<Control>();
            while (stack.Count > 0)
            {
                var n = stack.Pop();
                if (n is Control c && c.IsVisibleInTree()) list.Add(c);
                if (n is CanvasItem ci && !ci.Visible) continue;
                var kids = n.GetChildren(true);
                for (int i = kids.Count - 1; i >= 0; i--) stack.Push(kids[i]);
            }
            return list;
        }

        /// <summary>The node's class as Godot's get_class() names it: the framework class a game class extends.</summary>
        static string Cls(Node n)
        {
            var t = n.GetType();
            while (t != null && t.Assembly != typeof(Node).Assembly) t = t.BaseType;
            return t?.Name ?? "Node";
        }

        static string NodeName(Node n) => string.IsNullOrEmpty(n.Name) || n.Name.StartsWith("@") ? Cls(n) : n.Name;

        static string Text(Control c)
        {
            switch (c)
            {
                case Button b: return b.Text ?? "";
                case Label l: return l.Text ?? "";
                case RichTextLabel r: return r.GetParsedText() ?? "";
            }
            return "";
        }

        static Control Find(string text, bool forTap)
        {
            Control label = null;
            foreach (var c in All())
            {
                string t = Text(c).Trim();
                if (!t.Equals(text, StringComparison.OrdinalIgnoreCase)) continue;
                if (c is BaseButton b && !b.Disabled) return c;
                if (label == null) label = c;
            }
            return label;
        }

        /// <summary>The middle of the part of the control that's on the screen (where a finger would go).</summary>
        static Vec2 OnScreen(Control c)
        {
            var r = c.GetGlobalRect();
            var vis = _tree.Root.GetVisibleRect();
            float x0 = Math.Max(r.position.x, vis.position.x), y0 = Math.Max(r.position.y, vis.position.y);
            float x1 = Math.Min(r.position.x + r.size.x, vis.position.x + vis.size.x), y1 = Math.Min(r.position.y + r.size.y, vis.position.y + vis.size.y);
            if (x1 <= x0 || y1 <= y0) { Log("TAP: \"" + Text(c) + "\" is off the screen"); return r.GetCenter(); }
            if (x0 != r.position.x || y0 != r.position.y || x1 != r.position.x + r.size.x || y1 != r.position.y + r.size.y)
                Log("NOTE: \"" + Text(c) + "\" is partly off the screen " + r);
            return new Vec2((x0 + x1) * 0.5f, (y0 + y1) * 0.5f);
        }

        static void Tap(Vec2 logical)
        {
            var p = _tree.Root.StretchTransform.Xform(logical);
            Log($"tap ({logical.x:F0},{logical.y:F0})");
            GInput.ParseInputEvent(new InputEventScreenTouch { Index = 0, Position = p, Pressed = true });
            Run(0.1);
            GInput.ParseInputEvent(new InputEventScreenTouch { Index = 0, Position = p, Pressed = false });
            Run(0.1);
        }

        static void Shot(string name)
        {
            var size = _tree.Root.GetWindowSize();
            var r = new SoftRaster((int)size.x, (int)size.y, new Col(0.3f, 0.3f, 0.3f, 1f));
            r.Draw(_tree.Root.Render());
            string path = Path.Combine(_out, name + ".png");
            Png.Save(path, r.ToImage());
            Log("shot " + path);
        }
    }
}
