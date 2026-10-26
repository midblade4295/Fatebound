// Ported from godot/scripts/app/content_loader.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;
using Platform = Fatebound.Game.Platform;

namespace Fatebound.Game
{
    // The content loader (0.31.95, Kevin: "the main game installs a small file from the Play store and itch, then when
    // they launch the game after first install the game will say it's updating"). The first scene the app runs.
    //
    // The installed build holds the engine, the scripts and scenes, the fonts and the launcher art; the game's art and
    // sound are content packs (.pck) on a GitHub release, listed in res://content/manifest.json (tools/content_packs.py).
    // Each start: a pack whose files are already in res:// (running from source, or a full build) needs nothing; one
    // downloaded and checked before (user://packs/<file>, sha256 in verified.json) is mounted; any other is downloaded
    // -- "UPDATING", in 8 MB ranges appended to a .part file (an interrupted download resumes where it stopped, even after
    // the app is closed), hashed as it arrives, checked against the manifest's sha256 -- then mounted. Packs no build of
    // this install lists any more are deleted. Then the game (Main.tscn) starts. A code-only update downloads nothing;
    // new art re-downloads only the packs it is in.
    // Packs never replace the build's own files (load_resource_pack(..., false)) and hold data only (no scripts).
    public class ContentLoader : Control
    {
        public const string MANIFEST = "res://content/manifest.json";
        public const string UIDS = "res://content/uids.json";        // the packs' resources' UIDs (the build's uid cache only has its own)
        public const string DIR = "user://packs";                    // Android and the desktop
        public const string VERIFIED = "user://packs/verified.json";
        public const string MAIN = "res://scenes/Main.tscn";
        public const string TITLE = "res://scripts/app/title_screen.gd";   // 0.31.141: up first, the game loading behind it (not preloaded:
                                                                           // its art is in the ui pack, mounted first)
        public const int CHUNK = 8 * 1024 * 1024;
        public static readonly GArray RETRY = GArray.Of(2.0, 4.0, 8.0, 15.0, 30.0);
        public static readonly Font TITLE_FONT = ResourceLoader.Load<Font>("res://assets/fonts/LilitaOne-Regular.ttf");
        public static readonly Font BODY_FONT = ResourceLoader.Load<Font>("res://assets/fonts/Nunito-ExtraBold.woff2");
        public static readonly Color GOLD = Color.FromCode("#ffc23d");

        public GDict manifest = new GDict();
        public string base_url = "";
        public GArray todo = new GArray();              // packs to download, in order
        public GArray ready_packs = new GArray();       // packs to mount
        public GDict verified = new GDict();
        public long total = 0;                    // bytes to download this start
        public long done_bytes = 0;               // finished packs' bytes
        public int cur = -1;                      // index in todo
        public long offset = 0;                   // bytes of the current pack on disk
        public HashingContext hasher;
        public HTTPRequest http;
        public int fails = 0;
        public int bad_checks = 0;
        public double wait = 0.0;
        public double _speed_t = 0.0;
        public long _speed_b = 0;
        public double speed = 0.0;
        public Node guard = null;
        public bool finished = false;
        public string status_note = "";
        public TitleScreen title_screen = null;      // 0.31.141: the title screen, up while the game loads on a thread
        public bool _loading_main = false;
        public bool _swapped = false;
        public long _title_ms = 0;
        public Thread _game_thread = null;
        public PackedScene _game = null;
        public bool _game_done = false;

        public ProgressBar bar;
        public Label title;
        public Label line;
        public Label note;
        public Button retry_btn;

        // 0.31.132 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §5): where the packs live. On iOS user:// is backed up to iCloud,
        // and Apple's storage rules keep re-downloadable data out of backups: there they live in Library/Caches (never backed
        // up). iOS may empty Caches when the phone is short of space; the packs are then simply downloaded again.
        public string dir = DIR;
        public string verified_path = VERIFIED;

        public static string PacksDir()
        {
            if (Platform.IsIos())
            {
                var c = OS.GetCacheDir();
                if (c != "")
                    return c.PathJoin("fatebound_packs");
            }
            return DIR;
        }

        // ---------- pure parts (tests/content_test.gd) ----------
        public static GDict Plan(GDict m, GDict have, Func<string, bool> present)
        {
            // have: file -> sha256 of the packs on the phone, checked; present(probe) -> that pack's files are in res:// already
            var mount = new GArray();
            var fetch = new GArray();
            var keep = new GArray();
            foreach (var p in m.Get("packs", new GArray()))
            {
                if (present(GD.Str(p["probe"])))
                    continue;
                keep.Append(GD.Str(p["file"]));
                if (GD.Str(have.Get(GD.Str(p["file"]), "")) == GD.Str(p["sha256"]))
                    mount.Append(p);
                else
                    fetch.Append(p);
            }
            return new GDict { { "mount", mount }, { "fetch", fetch }, { "keep", keep } };
        }

        public static string RangeHeader(long at, long size)
        {
            return GD.Fmt("Range: bytes=%d-%d", at, Math.Min(at + CHUNK, size) - 1);
        }

        public static string Mb(long b)
        {
            return GD.Fmt("%.1f MB", b / 1048576.0);
        }

        // ---------- start ----------
        protected override void _Ready()
        {
            SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            SetMeta("content_loader", true);
            guard = GetNodeOrNull("/root/BootGuard");
            _BuildUi();
            Var parsed = FileAccess.FileExists(MANIFEST) ? JSON.ParseString(FileAccess.GetFileAsString(MANIFEST)) : Var.Nil;
            if (!parsed.IsDict)
            {
                _Log("CONTENT no manifest: starting the game as it is");
                CallDeferred(_StartGame);
                return;
            }
            manifest = parsed.D;
            base_url = OS.HasEnvironment("FB_CONTENT_URL") ? OS.GetEnvironment("FB_CONTENT_URL") : GD.Str(manifest.Get("url", ""));
            dir = PacksDir();
            verified_path = dir.PathJoin("verified.json");
            DirAccess.MakeDirRecursiveAbsolute(dir);
            verified = _ReadVerified();
            var have = new GDict();
            foreach (var f in verified)
            {
                if (FileAccess.FileExists(dir.PathJoin(f.AsString())))
                    have[f] = verified[f];
            }
            var pl = Plan(manifest, have, (string probe) => ResourceLoader.Exists(probe));
            ready_packs = pl["mount"].A;
            todo = pl["fetch"].A;
            _Cleanup(pl["keep"].A);
            _Log(GD.Fmt("CONTENT %d packs: %d in the build, %d on the phone, %d to download", manifest.Get("packs", new GArray()).Size(),
                manifest.Get("packs", new GArray()).Size() - pl["keep"].Size(), ready_packs.Size(), todo.Size()));
            if (todo.IsEmpty())
            {
                CallDeferred(_MountAndStart);
                return;
            }
            foreach (var p in todo)
                total += (long)p["size"];
            if (guard != null && guard is BootGuard)
                ((BootGuard)guard).Hold(true);                     // a download is not a frozen start
            Visible = true;
            http = new HTTPRequest();
            http.AcceptGzip = false;                 // byte ranges of the file as it is
            http.UseThreads = true;
            http.Timeout = 30.0;
            _NetOptions(http);
            AddChild(http);
            http.RequestCompleted += _OnChunk;
            _NextPack();
        }

        public void _NetOptions(HTTPRequest h)
        {
            // (desktop testing behind a proxy: FB_CONTENT_PROXY host:port, FB_CONTENT_CA a PEM bundle)
            if (OS.HasEnvironment("FB_CONTENT_PROXY"))
            {
                var hp = OS.GetEnvironment("FB_CONTENT_PROXY").Split(":");
                h.SetHttpsProxy(hp[0], GD.Int(hp[1]));
                h.SetHttpProxy(hp[0], GD.Int(hp[1]));
            }
            if (OS.HasEnvironment("FB_CONTENT_CA"))
            {
                var cert = new X509Certificate();
                if (cert.Load(OS.GetEnvironment("FB_CONTENT_CA")) == GD.OK)
                    h.SetTlsOptions(TLSOptions.Client(cert));
            }
        }

        // ---------- downloading ----------
        public async void _NextPack()
        {
            try
            {
                cur += 1;
                if (cur >= todo.Size())
                {
                    _MountAndStart();
                    return;
                }
                GDict p = todo[cur].D;
                var part = _Part(p);
                hasher = new HashingContext();
                hasher.Start(HashingContext.HASH_SHA256);
                offset = 0;
                if (FileAccess.FileExists(part))
                {
                    // resume: hash what is there (in steps, so the screen keeps drawing), then fetch the rest
                    var f = FileAccess.Open(part, FileAccess.READ);
                    if (f != null)
                    {
                        var n = f.GetLength();
                        if (n > (long)p["size"])
                        {
                            f.Close();
                            DirAccess.RemoveAbsolute(part);
                        }
                        else
                        {
                            while (f.GetPosition() < n)
                            {
                                hasher.Update(f.GetBuffer(Math.Min(4 << 20, n - f.GetPosition())));
                                await Await.ProcessFrame();
                            }
                            offset = n;
                            f.Close();
                        }
                    }
                }
                _Log(GD.Fmt("CONTENT %s: %s of %s already here", p["name"], Mb(offset), Mb((long)p["size"])));
                _Request();
            }
            catch (Exception e) { GD.PushError(e.ToString()); }
        }

        public string _Part(GDict p)
        {
            return dir.PathJoin(GD.Str(p["file"]) + ".part");
        }

        public void _Request()
        {
            GDict p = todo[cur].D;
            if (offset >= (long)p["size"])
            {
                _FinishPack();
                return;
            }
            var err = http.Request(base_url + GD.Str(p["file"]), new[] { RangeHeader(offset, (long)p["size"]) });
            if (err != GD.OK)
                _Trouble(GD.Fmt("Couldn't start the download (%d)", err));
        }

        public void _OnChunk(int result, int code, string[] _headers, byte[] body)
        {
            GDict p = todo[cur].D;
            if (result != HTTPRequest.RESULT_SUCCESS || !(code == 206 || code == 200) || body.Length == 0)
            {
                _Trouble(result != HTTPRequest.RESULT_SUCCESS ? "No connection" : GD.Fmt("Download problem (HTTP %d)", code));
                return;
            }
            var part = _Part(p);
            if (code == 200)
            {
                // the server sent the whole file instead of the range: start this pack over with it
                if (body.Length != (long)p["size"])
                {
                    _Trouble("Download problem (whole file, wrong size)");
                    return;
                }
                DirAccess.RemoveAbsolute(part);
                hasher = new HashingContext();
                hasher.Start(HashingContext.HASH_SHA256);
                offset = 0;
            }
            var f = FileAccess.FileExists(part) ? FileAccess.Open(part, FileAccess.READ_WRITE) : FileAccess.Open(part, FileAccess.WRITE);
            if (f == null)
            {
                _Trouble(GD.Fmt("Couldn't save the download — is the phone full? (%s needed)", Mb(total - done_bytes - offset)));
                return;
            }
            f.SeekEnd();
            f.StoreBuffer(body);
            var err = f.GetError();
            f.Close();
            if (err != GD.OK)
            {
                _Trouble(GD.Fmt("Couldn't save the download — is the phone full? (%s needed)", Mb(total - done_bytes - offset)));
                return;
            }
            hasher.Update(body);
            offset += body.Length;
            fails = 0;
            status_note = "";
            if (offset >= (long)p["size"])
                _FinishPack();
            else
                _Request();
        }

        public void _FinishPack()
        {
            GDict p = todo[cur].D;
            var sha = hasher.Finish().HexEncode();
            var part = _Part(p);
            if (sha != GD.Str(p["sha256"]))
            {
                _Log(GD.Fmt("CONTENT %s: check failed (%s), downloading it again", p["name"], sha.Substr(0, 12)));
                DirAccess.RemoveAbsolute(part);
                offset = 0;
                hasher = new HashingContext();
                hasher.Start(HashingContext.HASH_SHA256);
                bad_checks += 1;
                if (bad_checks > 2)
                {
                    _Trouble("The download was damaged — trying again");
                    return;
                }
                _Request();
                return;
            }
            var final = dir.PathJoin(GD.Str(p["file"]));
            if (FileAccess.FileExists(final))
                DirAccess.RemoveAbsolute(final);
            DirAccess.RenameAbsolute(part, final);
            verified[GD.Str(p["file"])] = sha;
            _WriteVerified();
            done_bytes += (long)p["size"];
            ready_packs.Append(p);
            _Log(GD.Fmt("CONTENT %s downloaded and checked", p["name"]));
            _NextPack();
        }

        public void _Trouble(string why)
        {
            fails += 1;
            wait = (double)RETRY[GD.Mini(fails - 1, RETRY.Size() - 1)];
            status_note = why;
            _Log(GD.Fmt("CONTENT trouble: %s (retry in %ds)", why, GD.Int(wait)));
            retry_btn.Visible = true;
        }

        public void _RetryNow()
        {
            if (wait > 0.0)
            {
                wait = 0.0;
                retry_btn.Visible = false;
                status_note = "";
                _Request();
            }
        }

        protected override void _Process(double delta)
        {
            if (_loading_main && !_swapped)
                _PollGame();
            if (finished || http == null)
                return;
            if (wait > 0.0)
            {
                wait -= delta;
                if (wait <= 0.0)
                {
                    wait = 0.0;
                    retry_btn.Visible = false;
                    _Request();
                }
            }
            var now = done_bytes + offset + (http.GetHttpClientStatus() == HTTPClient.STATUS_BODY ? http.GetDownloadedBytes() : 0);
            _speed_t += delta;
            if (_speed_t >= 1.0)
            {
                speed = GD.Lerpf(speed, (now - _speed_b) / _speed_t, speed > 0.0 ? 0.5 : 1.0);
                _speed_b = now;
                _speed_t = 0.0;
            }
            bar.Value = 100.0 * now / GD.Maxf(total, 1);
            if (status_note != "")
                line.Text = wait > 0.0 ? GD.Fmt("%s — retrying in %d s", status_note, GD.Ceili(wait)) : status_note;
            else
                line.Text = GD.Fmt("%s / %s%s", Mb(now), Mb(total), speed > 0.0 ? (GD.Fmt("   ·   %.1f MB/s", speed / 1048576.0)) : "");
        }

        // ---------- mount and go ----------
        public void _MountAndStart()
        {
            finished = true;
            foreach (var p in ready_packs)
            {
                var path = dir.PathJoin(GD.Str(p["file"]));
                if (!ProjectSettings.LoadResourcePack(path, false))
                {
                    _Log(GD.Fmt("CONTENT %s would not mount: downloading it again", p["name"]));
                    verified.Erase(GD.Str(p["file"]));
                    _WriteVerified();
                    DirAccess.RemoveAbsolute(path);
                    CallDeferred(() => GetTree().ReloadCurrentScene());
                    return;
                }
            }
            if (total > 0)
            {
                line.Text = "Ready!";
                bar.Value = 100.0;
            }
            _Log(GD.Fmt("CONTENT mounted %d packs, %d UIDs", ready_packs.Size(), _RegisterUids()));
            if (guard != null && guard is BootGuard)
                ((BootGuard)guard).Hold(false);
            CallDeferred(_StartGame);
        }

        public int _RegisterUids()
        {
            if (ready_packs.IsEmpty() || !FileAccess.FileExists(UIDS))
                return 0;
            Var map = JSON.ParseString(FileAccess.GetFileAsString(UIDS));
            if (!map.IsDict)
                return 0;
            var n = 0;
            foreach (var u in map)
            {
                var id = ResourceUID.TextToId(GD.Str(u));
                if (id != ResourceUID.INVALID_ID && !ResourceUID.HasId(id))
                {
                    ResourceUID.AddId(id, GD.Str(map[u]));
                    n += 1;
                }
            }
            return n;
        }

        public void _StartGame()
        {
            // 0.31.141 (Kevin: "Make the intro splash screen more exciting and also load faster"): the title screen goes up
            // now, and the game (Main.tscn: the scripts, ~1.5 s to compile) loads behind it on a thread of its OWN -- not on
            // Godot's worker pool: with the shader cache empty (a fresh install or update) a load on a pool thread waits for
            // the shader compiles that need those same pool threads, while the title's own drawing waits on the load's lock
            // (tools/cold_start_check.sh froze that way on a 2-core box; the 0.31.91 lesson, asset_cache.gd). Once loaded, and
            // the title's slam has settled (title_screen.can_swap), the game goes in behind the title, which stays up on its
            // own layer until Home is built and the player taps.
            // 0.31.142: the game goes in as soon as it has loaded, behind a still LOADING... (title_screen.hold_for_game), and the
            // title's show plays once Home is ready -- so building and first drawing Home no longer stop the show halfway.
            if (OS.HasEnvironment("FB_NO_TITLE"))
            {
                GetTree().ChangeSceneToFile(MAIN);
                return;
            }
            _game_thread = new Thread();
            if (_game_thread.Start(_LoadGame) != GD.OK)
            {
                _game_thread = null;
                GetTree().ChangeSceneToFile(MAIN);
                return;
            }
            _loading_main = true;
            _title_ms = Time.GetTicksMsec();
            _ShowTitle();
        }

        public void _LoadGame()
        {
            // (the game's own thread)
            var p = ResourceLoader.Load(MAIN) as PackedScene;
            CallDeferred(() => _Loaded(p));
        }

        public void _Loaded(PackedScene p)
        {
            _game = p;
            _game_done = true;
        }

        public void _ShowTitle()
        {
            // (load(TITLE) / script.saved_settings() / script.new(...): the title screen's script, loaded only now -- in C#
            // the TitleScreen class, always there)
            GDict settings = TitleScreen.SavedSettings();
            var layer = new CanvasLayer();
            layer.Name = "TitleLayer";
            layer.Layer = 90;                                   // (as siege_app.show_title: over everything the game builds)
            GetTree().Root.AddChild(layer);
            title_screen = new TitleScreen(null, (bool)settings.Get("reduce_motion", false));
            layer.AddChild(title_screen);
            Visible = false;                                    // (the download screen, if it was up)
            if (guard != null && guard is BootGuard)
                ((BootGuard)guard).WaitForGame(true);
        }

        public void _PollGame()
        {
            if (!_game_done)
                return;
            if (_game == null)
            {
                _swapped = true;
                _FinishThread();
                _Log("CONTENT the game didn't load on its thread: loading it directly");
                GetTree().ChangeSceneToFile(MAIN);
                return;
            }
            if (GD.IsInstanceValid(title_screen))
            {
                title_screen.HoldForGame();                   // 0.31.142: a still LOADING... before the game goes in behind it
                if (!title_screen.CanSwap())
                    return;
            }
            _swapped = true;
            _FinishThread();
            _Log(GD.Fmt("CONTENT the game loaded behind the title (%d ms after it went up)", Time.GetTicksMsec() - _title_ms));
            if (guard != null && guard is BootGuard)
                ((BootGuard)guard).WaitForGame(false);
            GetTree().ChangeSceneToPacked(_game);
        }

        public void _FinishThread()
        {
            if (_game_thread != null && _game_thread.IsStarted())
                _game_thread.WaitToFinish();
            _game_thread = null;
        }

        protected override void _ExitTree()
        {
            _FinishThread();                                   // (the app closed while the game was still loading)
        }

        public void _Cleanup(GArray keep)
        {
            var d = DirAccess.Open(dir);
            if (d == null)
                return;
            var gone = false;
            foreach (var f in d.GetFiles())
            {
                if (f == "verified.json")
                    continue;
                var @base = f.TrimSuffix(".part");
                if (!keep.Has(@base))
                {
                    d.Remove(f);
                    verified.Erase(@base);
                    gone = true;
                    _Log(GD.Fmt("CONTENT removed old pack %s", f));
                }
            }
            if (gone)
                _WriteVerified();
        }

        public GDict _ReadVerified()
        {
            if (FileAccess.FileExists(verified_path))
            {
                Var v = JSON.ParseString(FileAccess.GetFileAsString(verified_path));
                if (v.IsDict)
                    return v.D;
            }
            return new GDict();
        }

        public void _WriteVerified()
        {
            var f = FileAccess.Open(verified_path, FileAccess.WRITE);
            if (f != null)
            {
                f.StoreString(JSON.Stringify(verified));
                f.Close();
            }
        }

        public void _Log(string s)
        {
            GD.Print(s);
            if (guard != null && guard is BootGuard)
                ((BootGuard)guard).Mark(s);
        }

        // ---------- the screen ----------
        public void _BuildUi()
        {
            Visible = false;                          // shown only when something has to be downloaded
            // 0.31.139 (Kevin: put the title "in a startup screen and any loading screens"): the title screen's castle wall and
            // the title itself (both in the base build: no pack is here yet -- tools/build_title_art.py)
            var bg = new TextureRect();
            bg.Texture = ResourceLoader.Load<Texture2D>("res://assets/branding/splash_land.png");       // (0.31.216: the landscape band of the wall)
            bg.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            bg.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
            bg.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            AddChild(bg);
            var shade = new ColorRect();
            shade.Color = new Color(0.03, 0.02, 0.05, 0.35);
            shade.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            AddChild(shade);
            var col = new VBoxContainer();
            col.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            col.OffsetLeft = 28;
            col.OffsetRight = -28;
            col.Alignment = BoxContainer.ALIGNMENT_CENTER;
            col.AddThemeConstantOverride("separation", 14);
            AddChild(col);
            var hero = new TextureRect();
            hero.Texture = ResourceLoader.Load<Texture2D>("res://assets/branding/title_logo.webp");
            hero.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            hero.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            hero.TextureFilter = TextureFilterMode.LinearWithMipmaps;
            hero.CustomMinimumSize = new Vector2(0, 190);
            col.AddChild(hero);
            title = _Label("", TITLE_FONT, 10, Color.WHITE, 2);      // (the title is the picture above now)
            title.Visible = false;
            col.AddChild(title);
            col.AddChild(_Label("UPDATING", TITLE_FONT, 30, Color.WHITE, 8));   // (0.31.195: white, not gold)
            var gap = new Control();
            gap.CustomMinimumSize = new Vector2(0, 6);
            col.AddChild(gap);
            bar = new ProgressBar();
            bar.CustomMinimumSize = new Vector2(0, 30);
            bar.ShowPercentage = false;
            var back = new StyleBoxFlat();
            back.BgColor = new Color(0.03, 0.06, 0.14, 0.85);
            back.SetCornerRadiusAll(15);
            back.BorderColor = new Color(1, 1, 1, 0.35);
            back.SetBorderWidthAll(2);
            var fill = new StyleBoxFlat();
            fill.BgColor = GOLD;
            fill.SetCornerRadiusAll(15);
            bar.AddThemeStyleboxOverride("background", back);
            bar.AddThemeStyleboxOverride("fill", fill);
            col.AddChild(bar);
            line = _Label("", BODY_FONT, 20, Color.WHITE, 6);
            col.AddChild(line);
            note = _Label("Downloading the game's art and sound. This happens once — later updates only download what changed. Wi-Fi recommended.",
                BODY_FONT, 16, new Color(1, 1, 1, 0.85), 5);
            note.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            col.AddChild(note);
            retry_btn = new Button();
            retry_btn.Text = "RETRY NOW";
            retry_btn.Visible = false;
            retry_btn.AddThemeFontOverride("font", TITLE_FONT);
            retry_btn.AddThemeFontSizeOverride("font_size", 24);
            retry_btn.CustomMinimumSize = new Vector2(220, 56);
            retry_btn.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
            var bs = new StyleBoxFlat();
            bs.BgColor = Color.FromCode("#e8892a");
            bs.SetCornerRadiusAll(14);
            bs.BorderColor = Color.FromCode("#7a3a0c");
            bs.SetBorderWidthAll(3);
            retry_btn.AddThemeStyleboxOverride("normal", bs);
            retry_btn.AddThemeStyleboxOverride("hover", bs);
            retry_btn.AddThemeStyleboxOverride("pressed", bs);
            retry_btn.Pressed += _RetryNow;
            col.AddChild(retry_btn);
        }

        public Label _Label(string t, Font font, int size, Color c, int outline)
        {
            var l = new Label();
            l.Text = t;
            l.HorizontalAlignment = HorizontalAlignment.Center;
            l.AddThemeFontOverride("font", font);
            l.AddThemeFontSizeOverride("font_size", size);
            l.AddThemeColorOverride("font_color", c);
            l.AddThemeColorOverride("font_outline_color", new Color(0.05, 0.03, 0.02));
            l.AddThemeConstantOverride("outline_size", outline);
            return l;
        }
    }
}
