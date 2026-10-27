// Ported from godot/scripts/app/siege_app.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;
using UI = Fatebound.Game.Ui;
using UI2 = Fatebound.Game.Ui2;
using Eco = Fatebound.Game.Economy;
using Audio = Fatebound.Game.NativeAudio;
using Assets = Fatebound.Game.AssetCache;
using Net = Fatebound.Game.SiegeNet;
using SocialUI = Fatebound.Game.SocialUi;
using Diag = Fatebound.Game.SiegeDiag;
using Moba = Fatebound.Sim.Moba;

namespace Fatebound.Game
{
    // Fatebound Siege app shell (replaces the dice-era full_client). Owns the profile, the chrome
    // (top bar + tab bar), the five screens (scripts/app/screens.gd) and launching matches.
    public class SiegeApp : Control
    {
        // 0.31.141 (Kevin: "...also load faster"): the match (siege_mode.gd and what only it needs) is no longer compiled with
        // the app at start-up (~0.4 s): it loads first in the background queue once Home is up (Assets.preload_async), or
        // right there when a match starts before that (a safe start)
        public const string SIEGE_MODE = "res://scripts/siege/siege_mode.gd";
        // ...and so are the windows opened later (~0.3 s more), loaded in the background right after it (_later: there and then
        // if opened first)
        public const string CHAT_PANEL = "res://scripts/app/chat_panel.gd";
        public const string FRIENDS_PANEL = "res://scripts/app/friends_panel.gd";
        public const string CLAN_PANEL = "res://scripts/app/clan_panel.gd";                // 0.31.134: clans
        public const string ORDERS_PANEL = "res://scripts/app/orders_panel.gd";
        public const string LEADERBOARD_PANEL = "res://scripts/app/leaderboard_panel.gd";
        public const string DAILY_REWARD = "res://scripts/app/daily_reward.gd";
        public const string STARTER_OFFER = "res://scripts/app/starter_offer.gd";         // 0.31.214: Home's Starter Pack window
        public const string UPDATE_SCREEN = "res://scripts/app/update_screen.gd";
        public const string MOBA_PANEL = "res://scripts/app/moba_panel.gd";              // 0.31.155: 5V5 (the test)
        public const string TRAINING_PICK = "res://scripts/app/training_pick.gd";        // 0.31.217: TRAINING (which, and a hero of three)
        public const string CHAMPION_WINDOW = "res://scripts/app/champion_window.gd";    // 0.31.187: a champion's own window (the Locker)
        public const string HERALD_INTRO = "res://scripts/app/herald_intro.gd";          // 0.31.198: the Royal Herald's welcome
        public static readonly GArray LATER = GArray.Of(SIEGE_MODE, CLAN_PANEL, CHAT_PANEL, FRIENDS_PANEL, ORDERS_PANEL, DAILY_REWARD, LEADERBOARD_PANEL, UPDATE_SCREEN,
            MOBA_PANEL, CHAMPION_WINDOW, HERALD_INTRO, STARTER_OFFER, TRAINING_PICK);

        // 0.31.112 (Kevin: "move it [Home] to the center button. Move the shop button to far left")
        // 0.31.139 (Kevin: "Move the settings cog into a menu that players can press on their level icon on top left. then move
        // the social to where the settings was and rename that Alliance"): ALLIANCE (friends and clan) in SETTINGS' place;
        // Settings is under the level shield (open_player_menu). The settings screen is still the tab "settings".
        public static readonly GArray TABS = GArray.Of(GArray.Of("shop", "SHOP", "stall"), GArray.Of("pass", "PASS", "banner"), GArray.Of("home", "HOME", "castle"), GArray.Of("locker", "ARMORY", "swords"), GArray.Of("alliance", "ALLIANCE", "friends"));

        // Tests may point these elsewhere before the node enters the tree.
        public string profile_path = "user://siege_profile.json";
        public string legacy_path = "user://fatebound-save.json";
        public int now_override = -1;

        public Profile profile;
        public Audio audio;
        public string tab = "home";
        public string home_class = "knight";
        // 0.31.187: the Locker's tabs -- CHAMPIONS (first) and TITLES (0.31.187's ARMORY, a class's weapons, went with them).
        // 0.31.204 (Kevin: "redo the locker menu. Change the name to armory and only put in there what the player owns"): the
        // ARMORY (the tab keeps its id "locker") -- HEROES, OUTFITS, TITLES, each only what you own
        public string locker_tab = "heroes";
        // 0.31.204 (Kevin: "put a hero tab in the market that shows heroes that player doesn't own and that's where they will
        // purchase them"): the Market's tabs -- OUTFITS (the weekly sale and every outfit), HEROES (the ones you don't own, to
        // unlock), GEMS
        public string shop_tab = "outfits";
        public string quest_cls = "";                   // 0.31.97: the class shown on the Quests screen ("" = the first with a step ready)
        public SiegeMode siege = null;
        public bool home_fixed = false;                // 0.31.112: Home fits the screen and doesn't scroll (Screens.home sets it)

        // ---------------- forced update (0.31.73) ----------------
        // Kevin: "when server has newer version than players installed game it'll force them to update". The menu asks the
        // server its protocol at start-up and on resume (VersionCheck); a refused connect reports it too (siege_mode
        // version_mismatch). Server newer -> the blocking Update screen (UpdateScreen) and online play stays locked.
        // Server older (a build published before the server deploy) -> "Servers are updating", nothing blocked.
        // 0.31.209 (Kevin: "if there's an update, the message will post right when player launches game instead of having to
        // enter a match"): the start-up check also compares this build with the server's minimum app build (the "ver" answer's
        // "min_build", the server's min-build file) -- older: the Update screen at once (behind the title, so it's there as the
        // title lifts), not only when PLAY's hello is turned away.
        public bool update_required = false;
        public bool server_updating = false;
        public int server_version = -1;
        public int server_five = -1;                      // 0.31.170: the server's online 5v5 -- -1 not known yet, 1 there, 0 not (an older
                                                          // server: PLAY is a match against bots, as in 0.31.164-0.31.169)
        public string server_min_build = "";                 // 0.31.209: the oldest app build the server lets in ("ver" says; "" none)
        public UpdateScreen update_screen = null;
        // Tests may set these before the node enters the tree. Headless (tests, tools) skips the start-up check unless asked.
        public bool version_check = DisplayServer.GetName() != "headless";
        public string version_check_url = OS.HasEnvironment("SIEGE_URL") ? OS.GetEnvironment("SIEGE_URL") : Net.DEFAULT_URL;
        public Func<string, int> open_url = (string u) => OS.ShellOpen(u);
        public VersionCheck _version_checker = null;
        public double _version_checked_at = -1000.0;
        public const double RECHECK_AFTER = 60.0;          // s: on resume, ask again if the last check is older than this

        public Control chrome;
        public ScrollContainer content_scroll;
        public VBoxContainer content;
        public GDict tab_buttons = new GDict();
        public Label level_label;
        public Label name_label;
        public ProgressBar xp_bar;
        public Label gold_label;
        public Label gems_label;
        // 0.31.105: gains fly into the counters (reward_fly.gd). kind (coin / gem) -> {target: the profile's amount,
        // shown: what the counter says (it catches up as the pieces land), flying: bursts in the air}
        public RewardFly reward_fly;
        public bool quiet_top = false;                 // (a restored save: the counters just change)
        public GDict _cur = new GDict();
        public GDict _pill_icon = new GDict();
        public Vector2 _last_press = new Vector2(-1, -1);
        public long _last_press_ms = -100000;
        public Control modal = null;
        public Control hero_layer;
        public TitleScreen title_screen = null;        // 0.31.139: the title screen the app opens on (title_screen.gd); null once gone
        public Control player_menu = null;         // 0.31.139: the menu under the level shield (SETTINGS, DISCORD)
        public Control home_menu = null;           // 0.31.194: the menu under the top bar's menu button (ORDERS, QUESTS, RANKS, TUTORIAL)
        public Control menu_button;                // 0.31.194: that button, in the top bar
        public Control menu_badge;                 // ... and its count of what's waiting in the menu
        public CampScene home_scene;                // Home's camp (camp_scene.gd; 0.31.138-0.31.193 the war room)
        public double safe_top = 0.0;
        public double safe_left = 0.0;                   // 0.31.216: landscape -- the notch is on a side
        public double safe_right = 0.0;
        public Control xp_holder;
        public Control pass_badge;
        public Control alliance_badge;
        public GDict _tab_tweens = new GDict();
        public const double TOP_H = 52.0;                    // the top bar (56 in portrait)
        public const double TAB_H = 72.0;                    // a tab's tile (the tab bar's height in portrait)
        // 0.31.216 (Kevin: "The game needs to change from vertical to horizontal", Honor of Kings): the app is landscape -- the
        // top bar across the top, the tabs down a wooden rail on the left (RAIL_W), the screens beside it; the notch's side
        // inset (safe_left / safe_right) kept clear.
        public const double RAIL_W = 84.0;
        public static readonly Color FADE_COLOR = Color.FromCode("#0d1627");
        public Label _toast;
        public PanelContainer _toast_box;
        public double _toast_until = 0.0;

        // ---------------- start-up diagnostics and safe start (0.31.70; 0.31.72: moved into the BootGuard autoload) ----------------
        // BootGuard (scripts/app/boot_guard.gd) runs before this scene loads: the start-up log, the "pending until the menu
        // is up" record and SAFE START (no background model loading and no live 3D hero) after a stuck start. This scene
        // only reads safe_boot and marks its steps in the log.
        public bool safe_boot = false;
        public OnlineStatus online_status = null;         // 0.31.82: the server's player count for Home (the real app only, or FB_STATUS_POLL)
        public Node billing = null;               // 0.31.90: Google Play purchases (scripts/meta/billing.gd); inactive off Play
                                                  // (0.31.130: the App Store's on iOS, billing_ios.gd -- store_billing.gd picks)
        public Node play_games = null;            // 0.31.102: Google Play Games sign-in and the progress kept there (play_games.gd)
                                                  // (0.31.130: Game Center on iOS, game_center.gd -- game_services.gd picks)
        // 0.31.108: the account on the server (eco_sync.gd) -- the server's copy of the profile is the one that counts.
        // Headless (tests, tools) it doesn't reach the real server unless asked (eco_url / FB_ECO=1).
        public EcoSync eco_sync = null;
        public AccountLink account_link = null;          // 0.31.132: transfer code, Game Center link, account deletion (account_link.gd)
        public int _gc_tries = 0;
        public Analytics analytics = null;              // 0.31.118: usage statistics to our own server (scripts/meta/analytics.gd)
        public HeyCatch heycatch = null;               // 0.31.212: and to HeyCatch (scripts/meta/heycatch.gd: phones only, the same toggle)
        public Notify notify = new Notify();                // 0.31.119: "your chest is ready" notifications (the Play build's plugin)
        public bool eco_autostart = DisplayServer.GetName() != "headless" || OS.HasEnvironment("FB_ECO");
        public string eco_url = OS.HasEnvironment("SIEGE_URL") ? OS.GetEnvironment("SIEGE_URL") : Net.DEFAULT_URL;
        public GDict online_refs = new GDict();                  // Home's "players online" pill: {main, sub}
        // 0.31.111 (Kevin: "Build a global chat and players can click a name and have option to add friend to a friends list.
        // They can then group up and form a party"): the social side (scripts/meta/social.gd) -- chat, friends, the party.
        // Headless (tests, tools) it doesn't reach the real server unless asked (FB_SOCIAL=1).
        public Social social = null;
        public bool social_autostart = DisplayServer.GetName() != "headless" || OS.HasEnvironment("FB_SOCIAL");
        public ChatTicker chat_ticker = null;
        public HBoxContainer body = null;         // 0.31.216: the tab rail and the screen area beside it
        public InviteBanner _invite_banner = null;
        public string social_tab = "friends";            // 0.31.134: FRIENDS or CLAN, the one the social window opened on last
        public string _social_name = "";
        public string _social_sig = "";                  // what Home shows of it (requests, invites, the party): redraw when it changes
        public BootGuard _guard = null;
        // 0.31.84 (Kevin: "put a fps cap of 60 in the menus"): the menus ran uncapped (120 on a 120 Hz phone); a match sets its
        // own 30 and puts this back when it ends. The real app only (tests and tools run the menus as fast as they can).
        public const int MENU_FPS = 60;

        public bool _background = false;
        public bool _building = false;                 // 0.31.142: Home being built a piece a frame behind the boot title (_stage)

        public async Task _Stage(Control boot_title, double done)
        {
            // a piece of Home built: the boot title's LOADING bar moves on, and it gets a frame before the next piece
            if (!GD.IsInstanceValid(boot_title))
                return;
            if (boot_title is TitleScreen)                // (has_method("set_progress"))
                ((TitleScreen)boot_title).SetProgress(done);
            if (_building)
                await Await.ProcessFrame();
        }

        public void _StartBackground()
        {
            if (_background || safe_boot)
                return;
            _background = true;
            _BootMark("preload models");
            Assets.PreloadAsync(LATER);
        }

        public static Resource _Later(string path)
        {
            // 0.31.141: a script not compiled at start-up (LATER): from the background queue, or loaded there and then
            // (the port: the .gd's script resource; its callers below make the C# class itself -- `_later(X).new()` is `new X()`)
            return Assets.Res(path) as Resource;
        }

        public void _BootMark(string phase)
        {
            if (_guard != null)
                _guard.Mark(phase);
        }

        protected override async void _Ready()
        {
            try
            {
                SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
                _guard = GetNodeOrNull("/root/BootGuard") as BootGuard;
                GetTree().AutoAcceptQuit = false;
                _MenuFps();
                safe_boot = _guard != null && (bool)_guard.safe_boot;
                // 0.31.142 (Kevin: "It freezes while loading for a few seconds"): with the boot screen's title up in front, Home is
                // built a piece a frame (_stage), the title's LOADING bar moving on between the pieces, instead of in one go that
                // stopped the screen for 2.4 s on his S21. (Tests and tools, with no title in front, build it in one go as before.)
                var up0 = GetTree().GetNodesInGroup(TitleScreen.GROUP);
                Control boot_title = up0.Count != 0 ? up0[0] as Control : null;
                _building = boot_title != null;
                _BootMark("profile");
                profile = new Profile(profile_path, legacy_path);
                profile.now_override = now_override;
                profile.LoadOrCreate();
                _BootMark("audio");
                audio = new Audio();
                AddChild(audio);
                _ApplyAudio();
                _BootMark("background");
                _BuildBackground();
                await _Stage(boot_title, 0.66);
                _BootMark("hero");
                _BuildHero();
                await _Stage(boot_title, 0.76);
                // (0.31.142-0.31.193: "hero 3D" -- the war room's table and heroes, a frame after its painting. The camp is painted.)
                _BootMark("menus");
                _BuildChrome();
                await _Stage(boot_title, 0.86);
                var fly_layer = new CanvasLayer();               // 0.31.105: above the menus and their modals
                fly_layer.Layer = 60;
                AddChild(fly_layer);
                reward_fly = new RewardFly();
                fly_layer.AddChild(reward_fly);
                if (GetTree().GetScript() == null || OS.HasEnvironment("FB_STATUS_POLL"))
                {
                    online_status = new OnlineStatus();
                    online_status.Changed += PaintOnline;
                    AddChild(online_status);
                }
                eco_sync = new EcoSync();
                eco_sync.url = eco_url;
                eco_sync.auto_start = eco_autostart;
                eco_sync.Setup(profile);
                AddChild(eco_sync);
                eco_sync.Synced += _OnEcoSynced;
                analytics = new Analytics();
                analytics.url = eco_url;
                analytics.auto_start = eco_autostart;
                analytics.Setup(profile);
                AddChild(analytics);
                heycatch = new HeyCatch();
                heycatch.Setup(profile);
                AddChild(heycatch);
                analytics.hc = heycatch;
                analytics.WatchErrors();
                analytics.BeginSession(true, safe_boot);
                analytics.NoteLevel((int)profile.d["level"]);
                if (online_status != null)
                {
                    online_status.Changed += () =>
                    {
                        if ((int)online_status.info.Get("an", 0) == 1)
                            analytics.server_ok = true;
                    };
                }
                eco_sync.Rejected += (string op, string err) =>
                {
                    GD.Print(GD.Fmt("ECO rejected %s: %s", op, err));
                    if (op == "match")
                        Toast("That match couldn't be counted by the server", UI.RED);
                    else
                        Toast("The server didn't accept that change, so it was undone", UI.RED);
                };
                social = new Social();
                social.url = eco_url;
                social.Setup(profile);
                social.show_global = (bool)profile.d["settings"].Get("chat_global", true);
                AddChild(social);
                social.Note += _OnSocialNote;
                social.Request += _OnFriendRequest;
                social.Invited += _OnPartyInvite;
                social.Go += _OnPartyGo;
                social.Changed += _OnSocialChanged;
                social.ClanInvited += _OnClanInvited;
                social.Pull += () =>                  // 0.31.196: a Clan Chest, a shard given or received -- fetch the account
                {
                    if (eco_sync != null)
                        eco_sync.Pull();
                };
                chat_ticker.Setup(this);
                if (social_autostart)
                    social.SetActive(true);
                billing = StoreBilling.Make();
                AddChild(billing);
                var bl = billing as IStoreBilling;          // (billing.gd or billing_ios.gd: one face, duck-typed in the .gd)
                bl.on_server_grant = (GDict g) => eco_sync.Adopt(g.Get("profile", new GDict()), (int)profile.d["account"].Get("seq", 0));
                bl.Setup(profile);
                bl.Note += (string t, bool good) => Toast(t, good ? UI.GOLD : UI.RED);
                bl.Granted += _OnIapGranted;
                bl.Changed += () =>
                {
                    if (tab == "shop" && !GD.IsInstanceValid(modal) && siege == null)
                        Rebuild();
                };
                play_games = GameServices.Make();
                AddChild(play_games);
                var pg = play_games as IGameServices;       // (play_games.gd or game_center.gd: one face, duck-typed in the .gd)
                pg.Note += (string t, bool good) => Toast(t, good ? UI.GOLD : UI.RED);
                pg.Changed += () =>
                {
                    if (tab == "settings" && !GD.IsInstanceValid(modal) && siege == null)
                        Rebuild();
                };
                pg.Ask += (GDict _here, GDict _cloud) =>
                {
                    if (siege == null)
                        AskCloud();                         // (in a match: asked when it ends, _end_match)
                };
                pg.Restored += _OnCloudRestored;
                pg.Setup(profile);
                // 0.31.132 (the iOS port): the account between phones -- the same on Android and iPhone
                account_link = new AccountLink();
                account_link.url = eco_url;
                AddChild(account_link);
                account_link.Setup(profile);
                account_link.Switched += _OnAccountSwitched;
                account_link.Note += (string t, bool good) => Toast(t, good ? UI.GOLD : UI.RED);
                account_link.AskGc += (GDict _other) =>
                {
                    if (siege == null)
                        AskGc();                              // (in a match: asked when it ends)
                };
                if (play_games is GameCenter)             // (has_signal("signed"): Game Center's)
                    ((GameCenter)play_games).Signed += (string _team) => _GcLink();
                eco_sync.StateChanged += _GcLink;
                // Toast: a dark pill just above the tab bar, readable over anything.
                _toast_box = new PanelContainer();
                var tsb = UI.CardStyle(new Color(0.02, 0.04, 0.08, 0.92), 18, UI.CARD_HI);
                _toast_box.AddThemeStyleboxOverride("panel", tsb);
                _toast_box.AnchorLeft = 0.0;
                _toast_box.AnchorRight = 1.0;
                _toast_box.AnchorTop = 1.0;
                _toast_box.AnchorBottom = 1.0;
                _toast_box.OffsetLeft = 18;
                _toast_box.OffsetRight = -18;
                _toast_box.OffsetTop = -150;
                _toast_box.OffsetBottom = -92;
                _toast_box.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                _toast_box.Visible = false;
                AddChild(_toast_box);
                _toast = UI.Label(_toast_box, "", 14, UI.TEXT, null, true);
                _toast.HorizontalAlignment = HorizontalAlignment.Center;
                _toast.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                if (GD.Str(profile.d["migration"].Get("from", "")) == "legacy" && !(bool)profile.d["migration"].Get("shown", false))
                {
                    profile.d["migration"].D["shown"] = true;
                    profile.Save();
                    GDict m = profile.d["migration"].D;
                    var welcome = GD.Fmt("Welcome to Fatebound! Your progress carried over: +%d gold, +%d gems", (int)m["gold"], (int)m["gems"]);
                    CallDeferred(() => Toast(welcome, UI.GOLD));
                }
                content_scroll.GetVScrollBar().ValueChanged += _OnScroll;
                await _Stage(boot_title, 0.9);
                ShowTab("home");
                _building = false;
                _ = _Stage(boot_title, 0.95);
                _BootMark("home shown, waiting for frames");
                var up = GetTree().GetNodesInGroup(TitleScreen.GROUP);
                if (up.Count != 0)
                    AdoptTitle(up[0] as TitleScreen);                     // 0.31.141: the boot screen put it up first, the game loading behind it
                else if (GetTree().GetScript() == null || OS.HasEnvironment("FB_TITLE"))
                    ShowTitle();                           // 0.31.139: the title screen over Home (not under tests and tools)
                // 0.31.8: the match's models (0.31.141: and its script, and the windows opened later) load on a thread while the
                // menus are up. 0.31.142: with the title up, once its show is over (TAP TO START), so they don't jolt it.
                if (GD.IsInstanceValid(title_screen))            // (and title_screen.has_signal("shown"))
                {
                    var ts = title_screen;
                    Action on_shown = null, on_done = null;     // (CONNECT_ONE_SHOT)
                    on_shown = () => { ts.Shown -= on_shown; _StartBackground(); };
                    on_done = () => { ts.Done -= on_done; _StartBackground(); };
                    ts.Shown += on_shown;
                    ts.Done += on_done;
                }
                else
                    _StartBackground();
                if (version_check)
                    CallDeferred(CheckServerVersion);
            }
            catch (Exception e) { GD.PushError(e.ToString()); }
        }

        public void _ApplyAudio()
        {
            GDict st = profile.d["settings"].D;
            // (audio.has_method("set_levels"): NativeAudio's)
            // 0.31.110 (Kevin: "make it so the audio sliders are max by default"): 100% when unset
            audio.SetLevels(new GDict { { "master", (double)st.Get("master", 1.0) }, { "combat", (double)st.Get("sfx", 1.0) }, { "ui", (double)st.Get("sfx", 1.0) },
                { "music", (double)st.Get("music", 1.0) } });
        }

        public void Sfx(string cue)
        {
            if (audio != null)                 // (and audio.has_method("play"): NativeAudio's)
                audio.Play(cue);
        }

        // ---------------- chrome ----------------
        public void _BuildBackground()
        {
            var grad = new Gradient();
            // 0.31.83: plain royal blue (the tone the damask used to give it), lighter at the top
            grad.SetColor(0, Color.FromCode("#243d96"));
            grad.SetColor(1, Color.FromCode("#0a1750"));
            grad.AddPoint(0.45, Color.FromCode("#152a7c"));
            var gt = new GradientTexture2D();
            gt.Gradient = grad;
            gt.FillFrom = new Vector2(0.5, 0.0);
            gt.FillTo = new Vector2(0.5, 1.0);
            gt.Width = 8;
            gt.Height = 256;
            var bg = new TextureRect();
            bg.Texture = gt;
            bg.StretchMode = TextureRect.STRETCH_SCALE;
            bg.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            bg.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            bg.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(bg);
            // (0.31.83, Kevin: "I don't like the wallpaper looking pattern on background": the damask that 0.31.79 tiled under
            // every screen is gone.) 0.31.84 (Kevin picked concept C of reports/concepts/bg_concepts.png): royal blue with light
            // rays from the top and drifting gold motes, painted (gpt-image-2, Topaz 2x), covering the screen behind every menu.
            var art = new TextureRect();
            art.Texture = UI2.Tex(UI2.V2 + "bg_menu.webp");
            art.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            art.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
            art.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            art.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(art);
            // A soft warm glow behind the top of the screen.
            var glow_g = new Gradient();
            glow_g.SetColor(0, new Color(1.0, 0.72, 0.3, 0.18));
            glow_g.SetColor(1, new Color(1.0, 0.72, 0.3, 0.0));
            var glow = new GradientTexture2D();
            glow.Gradient = glow_g;
            glow.Fill = GradientTexture2D.FillEnum.Radial;
            glow.FillFrom = new Vector2(0.5, 0.5);
            glow.FillTo = new Vector2(1.0, 0.5);
            glow.Width = 256;
            glow.Height = 256;
            var gl = new TextureRect();
            gl.Texture = glow;
            gl.StretchMode = TextureRect.STRETCH_SCALE;
            gl.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            gl.SetAnchorsAndOffsetsPreset(Control.PRESET_TOP_WIDE);
            gl.OffsetTop = -180;
            gl.OffsetBottom = 380;
            gl.OffsetLeft = -120;
            gl.OffsetRight = 120;
            gl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(gl);
        }

        public GradientTexture2D _Grad(Color c0, Color c1, int w = 8, int h = 64)
        {
            var g = new Gradient();
            g.SetColor(0, c0);
            g.SetColor(1, c1);
            var t = new GradientTexture2D();
            t.Gradient = g;
            t.FillFrom = new Vector2(0.5, 0.0);
            t.FillTo = new Vector2(0.5, 1.0);
            t.Width = w;
            t.Height = h;
            return t;
        }

        public void _Band(Control parent, Color c0, Color c1, bool top, double px)
        {
            var r = new TextureRect();
            r.Texture = _Grad(c0, c1);
            r.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            r.StretchMode = TextureRect.STRETCH_SCALE;
            r.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            r.AnchorRight = 1.0;
            if (top)
                r.OffsetBottom = px;
            else
            {
                r.AnchorTop = 1.0;
                r.AnchorBottom = 1.0;
                r.OffsetTop = -px;
            }
            parent.AddChild(r);
        }

        public void _BuildHero()
        {
            // 0.31.79: Home's painted backdrop. 0.31.194 (Kevin picked B2, the champions' camp): the six champions round their
            // campfire in the castle's courtyard at dusk (camp_scene.gd), the fire, the lanterns, the magic and the sky alive, laid
            // out so the champions' feet are just over PLAY. (0.31.138-0.31.193: the war room, its table and heroes in 3D.)
            // Scrolls away with a parallax as the menu is scrolled.
            safe_top = _SafeTop();
            var sides = _SafeSides();
            safe_left = sides.x;
            safe_right = sides.y;
            hero_layer = new Control();
            hero_layer.AnchorRight = 1.0;
            hero_layer.AnchorBottom = 1.0;             // 0.31.117: the whole screen (was 650 + safe_top: the painting stopped under
                                                       // PLAY and the rest of Home was plain navy -- Kevin: "very empty")
            hero_layer.ClipContents = true;
            hero_layer.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(hero_layer);
            var calm = (bool)profile.d["settings"].Get("reduce_motion", false);
            var under = new ColorRect();                 // (under the painting's foot on a phone taller than 9:20)
            under.Color = Color.FromCode("#120d14");
            under.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            under.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            hero_layer.AddChild(under);
            home_scene = new CampScene(calm, safe_boot);
            home_scene.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            hero_layer.AddChild(home_scene);
            Action lay = () =>
            {
                home_scene.inset_left = RAIL_W + safe_left;
                home_scene.Place(HomePlayTop());
            };
            hero_layer.Resized += lay;
            lay();
            _Band(hero_layer, new Color(0.02, 0.03, 0.09, 0.72), new Color(0.02, 0.03, 0.09, 0.0), true, 110.0 + safe_top);
            _Band(hero_layer, new Color(FADE_COLOR, 0.0), new Color(FADE_COLOR, 1.0), false, 150.0);
            // (0.31.113-0.31.138: the "All Tied Up" title stood here. 0.31.139, Kevin: "Seems very busy now. Maybe remove the
            // fatebound title and instead put that in a startup screen and any loading screens": the title screen
            // (title_screen.gd), the first-start download screen and the match's warm-up cover have it now.)
        }

        public static readonly Font LOGO_FONT = ResourceLoader.Load<Font>("res://assets/fonts/LilitaOne-Regular.ttf");

        public void HeroShow(string _cls = "", GDict _look = null)
        {
            // (Home builds call this:) the camp laid out again, now that the chat line and the tab bar are there to measure
            // from. (0.31.79-0.31.193 Home's heroes in 3D, in what's equipped: the camp's champions are painted.)
            if (home_scene != null)
            {
                home_scene.inset_left = RAIL_W + safe_left;
                home_scene.Place(HomePlayTop());
            }
        }

        public void _OnScroll(double v)
        {
            { var p = hero_layer.Position; p.y = (float)(-v * 0.55); hero_layer.Position = p; }
            { var mc = hero_layer.Modulate; mc.a = (float)GD.Clampf(1.0 - v / 360.0, 0.0, 1.0); hero_layer.Modulate = mc; }
        }

        public double _SafeTop()
        {
            // Status bar / notch inset in logical pixels.
            var safe = DisplayServer.GetDisplaySafeArea();
            var window = (Vector2)DisplayServer.WindowGetSize();
            var logical = GetViewport().GetVisibleRect().size;
            if (window.y <= 0 || safe.size.y <= 0)
                return 0.0;
            return GD.Clampf((double)safe.position.y * logical.y / window.y, 0.0, 60.0);
        }

        public Vector2 _SafeSides()
        {
            // 0.31.216: the notch's inset on the left and the right, in logical pixels (landscape)
            var safe = DisplayServer.GetDisplaySafeArea();
            var window = (Vector2)DisplayServer.WindowGetSize();
            var logical = GetViewport().GetVisibleRect().size;
            if (window.x <= 0 || safe.size.x <= 0)
                return Vector2.ZERO;
            var k = (double)logical.x / window.x;
            return new Vector2(GD.Clampf((double)safe.position.x * k, 0.0, 60.0), GD.Clampf((window.x - (double)safe.End.x) * k, 0.0, 60.0));
        }

        public double ContentW()
        {
            // 0.31.216: the screens' width -- the screen less the tab rail, the notch and the list's margins
            return Size.x - RAIL_W - safe_left - safe_right - 24.0;
        }

        public void _BuildChrome()
        {
            chrome = new VBoxContainer();
            chrome.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            chrome.OffsetLeft = safe_left;
            chrome.OffsetRight = -safe_right;
            chrome.AddThemeConstantOverride("separation", 0);
            AddChild(chrome);
            UI.Spacer(chrome, 4.0 + safe_top);
            // --- top bar: level shield, name + XP, gold and gems (0.31.79 look)
            var top = new Control();
            top.CustomMinimumSize = new Vector2(0, TOP_H);
            chrome.AddChild(top);
            var bar = new HBoxContainer();
            bar.AddThemeConstantOverride("separation", 8);
            bar.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            bar.OffsetLeft = 10;
            bar.OffsetRight = -10;
            bar.OffsetBottom = -6;
            top.AddChild(bar);
            var sh = new Control();
            sh.CustomMinimumSize = new Vector2(44, 50);
            sh.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            bar.AddChild(sh);
            var st = new TextureRect();
            st.Texture = UI2.Tex(UI2.V2 + "shield.svg");
            st.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            st.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            st.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            st.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            sh.AddChild(st);
            level_label = UI2.Text(sh, "1", 20, Color.WHITE, Color.FromCode("#0e1433"), 5);
            level_label.HorizontalAlignment = HorizontalAlignment.Center;
            level_label.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            level_label.OffsetBottom = -6;
            // 0.31.139: the shield opens the player's menu (SETTINGS lives there now) -- a little cog on its corner says so
            var cog = new TextureRect();
            cog.Texture = UI2.Tex(UI2.IconPath("gear"));
            cog.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            cog.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            cog.Size = new Vector2(22, 22);
            cog.Position = new Vector2(28, 30);
            cog.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            sh.AddChild(cog);
            var shb = new Button();
            shb.Flat = true;
            shb.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus", "hover_pressed" })
                shb.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            shb.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            shb.OffsetRight = 6;
            shb.OffsetBottom = 4;
            shb.SetMeta("action_key", "top_level");
            shb.Pressed += () =>
            {
                Sfx("menuOpen");
                OpenPlayerMenu();
            };
            sh.AddChild(shb);
            var who = new VBoxContainer();
            who.AddThemeConstantOverride("separation", 4);
            who.Alignment = BoxContainer.ALIGNMENT_CENTER;
            UI.Grow(who);
            bar.AddChild(who);
            name_label = UI2.Body(who, "", 14, Color.WHITE, false);
            name_label.ClipText = true;
            name_label.TextOverrunBehavior = TextServer.OVERRUN_TRIM_ELLIPSIS;      // (0.31.87: a long title ends in "...")
            name_label.AddThemeColorOverride("font_outline_color", new Color(0, 0, 0, 0.7));
            name_label.AddThemeConstantOverride("outline_size", 4);
            xp_holder = new VBoxContainer();
            xp_holder.CustomMinimumSize = new Vector2(0, 10);
            who.AddChild(xp_holder);
            menu_button = _MenuButton(bar);
            gold_label = _Pill(bar, "coin");
            gems_label = _Pill(bar, "gem");
            // (0.31.105-0.31.183 an Embers counter too: 0.31.184, Kevin: "Maybe let's have the two currency so it's more simple")
            // --- the rail on the left, the screen area beside it (0.31.216: the tab bar was across the bottom)
            body = new HBoxContainer();
            body.AddThemeConstantOverride("separation", 0);
            body.SizeFlagsVertical = Control.SIZE_EXPAND_FILL;
            chrome.AddChild(body);
            var rail = new Control();
            rail.Name = "TabRail";
            rail.CustomMinimumSize = new Vector2(RAIL_W, 0);
            body.AddChild(rail);
            var screen_col = new VBoxContainer();
            screen_col.AddThemeConstantOverride("separation", 0);
            screen_col.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            body.AddChild(screen_col);
            // --- screen area ---
            content_scroll = new ScrollContainer();
            content_scroll.SizeFlagsVertical = Control.SIZE_EXPAND_FILL;
            content_scroll.HorizontalScrollMode = ScrollContainer.SCROLL_MODE_DISABLED;
            // Drag-scrolling is done by _input below; the built-in one never saw drags that started on a
            // card or button (they stop the event) and would fight ours where it did.
            content_scroll.ScrollDeadzone = 1000000;
            screen_col.AddChild(content_scroll);
            var margin = new MarginContainer();
            margin.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            foreach (var side in new[] { "left", "right" })
                margin.AddThemeConstantOverride("margin_" + side, 12);
            margin.AddThemeConstantOverride("margin_top", 4);
            margin.AddThemeConstantOverride("margin_bottom", 16);
            content_scroll.AddChild(margin);
            content = new VBoxContainer();
            content.AddThemeConstantOverride("separation", 14);
            content.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            margin.AddChild(content);
            // --- the chat line over the tab bar, Home only (0.31.111; set up once the social side exists)
            chat_ticker = new ChatTicker();
            screen_col.AddChild(chat_ticker);
            // --- the tab rail: dark wood with a gold edge on its right; the open tab is a raised gold-framed tile (0.31.79; a
            // bar across the bottom until 0.31.216)
            var tb = rail;
            var wood = new TextureRect();
            wood.Texture = UI2.Tex(UI2.V2 + "tex_wood.webp");
            wood.StretchMode = TextureRect.STRETCH_TILE;
            wood.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            wood.TextureRepeat = TextureRepeatMode.Enabled;
            wood.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            wood.Modulate = new Color(0.62, 0.5, 0.42);
            wood.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            tb.AddChild(wood);
            var shade = new TextureRect();                  // (darker toward the screen side)
            shade.Texture = _Grad(new Color(0.05, 0.02, 0.0, 0.1), new Color(0.05, 0.02, 0.0, 0.6), 8, 64);
            shade.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            shade.StretchMode = TextureRect.STRETCH_SCALE;
            shade.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            shade.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            tb.AddChild(shade);
            var edge = new ColorRect();
            edge.Color = Color.FromCode("#2a1604");
            edge.AnchorLeft = 1.0;
            edge.AnchorRight = 1.0;
            edge.AnchorBottom = 1.0;
            edge.OffsetLeft = -3;
            edge.OffsetRight = 3;
            edge.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            tb.AddChild(edge);
            var gold_edge = new TextureRect();
            gold_edge.Texture = _Grad(Color.FromCode("#fff0b0"), Color.FromCode("#b9761b"), 4, 16);
            gold_edge.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            gold_edge.StretchMode = TextureRect.STRETCH_SCALE;
            gold_edge.AnchorLeft = 1.0;
            gold_edge.AnchorRight = 1.0;
            gold_edge.AnchorBottom = 1.0;
            gold_edge.OffsetLeft = -2;
            gold_edge.OffsetRight = 1;
            gold_edge.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            tb.AddChild(gold_edge);
            var trow = new VBoxContainer();
            trow.AddThemeConstantOverride("separation", 0);
            trow.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            trow.OffsetTop = 4;
            trow.OffsetBottom = -6;
            trow.OffsetLeft = 2;
            trow.OffsetRight = -5;
            tb.AddChild(trow);
            foreach (var t in TABS)
                tab_buttons[t[0]] = _TabButton(trow, GD.Str(t[0]), GD.Str(t[1]), GD.Str(t[2]));
            pass_badge = UI2.Badge(tab_buttons["pass"]["button"].As<Control>(), "0", new Vector2(-10, 4));
            tab_buttons["pass"].D["badge"] = pass_badge;
            alliance_badge = UI2.Badge(tab_buttons["alliance"]["button"].As<Control>(), "0", new Vector2(-10, 4));   // (friend requests, invites)
            alliance_badge.Visible = false;
        }

        public Label _Pill(Node parent, string kind)
        {
            // A dark pill with the currency coming out of its left end and a green "+". Tapping it opens the shop.
            var p = new PanelContainer();
            var sb = new StyleBoxEmpty();
            sb.ContentMarginLeft = 15;
            sb.ContentMarginRight = 3;
            sb.ContentMarginTop = 3;
            sb.ContentMarginBottom = 3;
            p.AddThemeStyleboxOverride("panel", sb);
            p.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            parent.AddChild(p);
            var edge = new GDict { { "coin", Color.FromCode("#e9b648") }, { "gem", Color.FromCode("#5fd2f0") } };
            UI2.Skin(p, new GDict { { "radius", 15.0 }, { "outline", 2.0 }, { "outline_color", edge.Get(kind, Color.FromCode("#5fd2f0")) },
                { "rim", 0.0 }, { "fill_top", new Color(0.06, 0.09, 0.24, 0.94) }, { "fill_bottom", new Color(0.01, 0.02, 0.08, 0.94) }, { "shadow_y", 3.0 }, { "shadow_alpha", 0.5 }, { "bevel", 0.1 } });
            var r = new HBoxContainer();
            r.AddThemeConstantOverride("separation", 3);
            p.AddChild(r);
            var l = UI2.Body(r, "0", 14, Color.WHITE, false);
            l.CustomMinimumSize = new Vector2(33, 0);
            l.HorizontalAlignment = HorizontalAlignment.Right;
            var plus = new Panel();
            plus.CustomMinimumSize = new Vector2(19, 19);
            plus.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            r.AddChild(plus);
            UI2.Skin(plus, UI2.ButtonParams("green", 7.0, 3.0));
            var pl = UI.Label(plus, "+", 14, Color.WHITE, UI.HEAVY_FONT);
            pl.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            pl.OffsetTop = -3;
            pl.HorizontalAlignment = HorizontalAlignment.Center;
            pl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            var coin = new TextureRect();
            coin.Texture = UI2.Tex(GD.Fmt("res://assets/ui/currency/%s.png", kind));
            _pill_icon[kind] = coin;
            coin.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            coin.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            coin.Size = new Vector2(32, 32);
            coin.Position = new Vector2(-14, -4);
            coin.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            p.AddChild(coin);                      // (a non-container child, so it's placed by hand)
            coin.TopLevel = false;
            p.SortChildren += () =>
            {
                coin.Size = new Vector2(32, 32);
                coin.Position = new Vector2(-16, ((double)p.Size.y - 32.0) * 0.5);
            };
            foreach (var c in r.GetChildren())
                (c as Control).MouseFilter = Control.MOUSE_FILTER_IGNORE;
            var hit = new Button();
            hit.Flat = true;
            hit.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus" })
                hit.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            hit.SetMeta("action_key", "pill_" + kind);
            hit.Pressed += () =>
            {
                Sfx("tab");
                if (kind == "gem")
                    shop_tab = "gems";                  // (0.31.204: the gem pill opens the Market's GEMS)
                ShowTab("shop");
            };
            p.AddChild(hit);
            return l;
        }

        public GDict _TabButton(Node parent, string id, string text, string icon_name)
        {
            var b = new Button();
            b.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus" })
                b.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            b.CustomMinimumSize = new Vector2(0, 52);
            b.SetMeta("action_key", "tab_" + id);
            b.SizeFlagsVertical = Control.SIZE_EXPAND_FILL;            // (0.31.216: a tile of the rail)
            b.Pressed += () =>
            {
                if (id == "alliance")
                {
                    Sfx("menuOpen");                    // (0.31.139: the friends and clan window, over the screen you're on)
                    OpenSocial();
                    return;
                }
                Sfx("tab");                             // 0.31.110: its own sound, a soft rustle into a click
                ShowTab(id);
            };
            parent.AddChild(b);
            var plate = new Control();                    // the raised tile of the open tab
            plate.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            plate.OffsetTop = 2;
            plate.OffsetLeft = 2;
            plate.OffsetRight = 10;                       // (0.31.216: it stands out over the rail's edge toward the screen)
            plate.OffsetBottom = -2;
            plate.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            plate.Visible = false;
            b.AddChild(plate);
            UI2.Plate(plate, "royal", 16.0, "gold");
            var halo = UI2.Glow(plate, new Rect2(0, 0, 10, 10), new Color(1.0, 0.86, 0.45, 0.55));
            plate.Resized += () =>
            {
                halo.Size = new Vector2(plate.Size.x * 1.1, plate.Size.y * 0.8);
                halo.Position = new Vector2(plate.Size.x * -0.05, 2);
            };
            var ic = new TextureRect();
            ic.Texture = UI2.Tex(UI2.IconPath(icon_name));
            ic.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            ic.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            ic.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.AddChild(ic);
            var l = UI2.Text(b, text, 11, Color.FromCode("#f1dfba"), new Color(0.1, 0.04, 0.0, 0.9), 3, false);
            l.HorizontalAlignment = HorizontalAlignment.Center;
            l.SetAnchorsAndOffsetsPreset(Control.PRESET_BOTTOM_WIDE);
            l.OffsetTop = -19;
            l.OffsetBottom = -4;
            return new GDict { { "button", b }, { "icon", ic }, { "label", l }, { "plate", plate } };
        }

        public void _StyleTab(GDict tb, bool on)
        {
            Button b = tb["button"].As<Button>();
            TextureRect ic = tb["icon"].As<TextureRect>();
            Label l = tb["label"].As<Label>();
            tb["plate"].As<Control>().Visible = on;
            var px = on ? 40.0 : 32.0;
            Action place = () =>
            {
                ic.Size = new Vector2(px, px);
                ic.Position = new Vector2(((double)b.Size.x - px) * 0.5 + (on ? 4.0 : 0.0), GD.Maxf(2.0, ((double)b.Size.y - 18.0 - px) * 0.5));
            };
            // (b.resized.is_connected(tb.get("place", func(): pass)): the last place this tab connected)
            if (tb.Has("place") && tb["place"].Obj is Action old_place)
                b.Resized -= old_place;
            tb["place"] = place;
            b.Resized += place;
            place();
            ic.Modulate = on ? Color.WHITE : new Color(0.92, 0.88, 0.84);
            l.AddThemeColorOverride("font_color", on ? Color.WHITE : Color.FromCode("#d8c7a8"));     // (0.31.195: white, not gold)
            l.AddThemeFontSizeOverride("font_size", on ? 12 : 10);
            l.AddThemeConstantOverride("outline_size", on ? 4 : 3);
            var key = GD.Str(Var.Of(b.GetMeta("action_key")));
            if (_tab_tweens.Has(key) && GD.IsInstanceValid(_tab_tweens[key]))
                _tab_tweens[key].As<Tween>().Kill();
            _tab_tweens.Erase(key);
            if (on && IsInsideTree())
            {
                double y0 = ic.Position.y;
                var tw = ic.CreateTween().SetLoops();
                tw.TweenProperty(ic, "position:y", y0 - 3.0, 1.1).SetTrans(Tween.TRANS_SINE).SetEase(Tween.EASE_IN_OUT);
                tw.TweenProperty(ic, "position:y", y0, 1.1).SetTrans(Tween.TRANS_SINE).SetEase(Tween.EASE_IN_OUT);
                _tab_tweens[key] = Var.Of(tw);
            }
        }

        public void RefreshTop()
        {
            GDict d = profile.d;
            level_label.Text = GD.Str((int)d["level"]);
            name_label.Text = Net.TitleText(GD.Str(d["name"]), GD.Str(d["title"]));      // (0.31.87: the title as it joins the name)
            foreach (var c in xp_holder.GetChildren())
                c.QueueFree();
            UI2.Bar(xp_holder, (int)d["xp"], Eco.LevelXp((int)d["level"]), Color.FromCode("#b6f3ff"), Color.FromCode("#36b9ea"), 10.0);
            _Counter("coin", gold_label, (int)d["gold"]);
            _Counter("gem", gems_label, (int)d["gems"]);
            // Badge on the PASS tab when rewards are waiting.
            var claimable = 0;
            for (int tier = 1; tier < profile.PassTier() + 1; tier++)
            {
                foreach (var prem in new[] { false, true })
                {
                    if (profile.CanClaim(tier, prem))
                        claimable += 1;
                }
            }
            pass_badge.Visible = claimable > 0;
            (pass_badge.GetChild(0) as Label).Text = GD.Str(claimable);
            PaintMenu();                                  // 0.31.194
        }

        // ---------------- the currency counters (0.31.105) ----------------
        public void _Counter(string kind, Label lbl, int value)
        {
            // A rise flies in from where the reward came from (reward_fly.gd) and the counter counts up as the pieces land; a
            // fall (spending) shows at once. While a match runs the counters wait: the menus catch up (and fly) on the way back.
            GDict c = _cur.Get(kind, new GDict()).D;
            if (c.IsEmpty() || quiet_top || reward_fly == null)
            {
                _cur[kind] = new GDict { { "target", value }, { "shown", value }, { "flying", 0 } };
                lbl.Text = UI.Compact(value);
                return;
            }
            if (siege != null || !chrome.IsVisibleInTree())
                return;
            var delta = value - (int)c["target"];
            c["target"] = value;
            if (delta < 0)
            {
                c["shown"] = GD.Maxi((int)c["shown"] + delta, 0);
                lbl.Text = UI.Compact((int)c["shown"]);
            }
            else if (delta > 0)
            {
                c["flying"] = (int)c["flying"] + 1;
                reward_fly.Burst(kind, delta, FlyOrigin(), _pill_icon.Get(kind).As<Control>(), (int share) =>
                {
                    c["shown"] = GD.Mini((int)c["shown"] + share, (int)c["target"]);
                    lbl.Text = UI.Compact((int)c["shown"]);
                    _Punch(kind);
                }, () =>
                {
                    c["flying"] = (int)c["flying"] - 1;
                    if ((int)c["flying"] <= 0)
                    {
                        c["shown"] = c["target"];
                        lbl.Text = UI.Compact((int)c["target"]);
                    }
                });
            }
        }

        public Vector2 FlyOrigin()
        {
            // where a reward came from: the tap that claimed it (CLAIM, COLLECT, BUY ...), else the middle of the screen
            if (_last_press.x >= 0.0 && Time.GetTicksMsec() - _last_press_ms < 2500)
                return _last_press;
            return GetViewportRect().size * new Vector2(0.5, 0.45);
        }

        public GDict _punch_ms = new GDict();

        public void _Punch(string kind)
        {
            Control ic = _pill_icon.Get(kind).As<Control>();
            if (!GD.IsInstanceValid(ic))
                return;
            ic.PivotOffset = ic.Size * 0.5;
            ic.Scale = Vector2.ONE * 1.32;
            var tw = ic.CreateTween();
            tw.TweenProperty(ic, "scale", Vector2.ONE, 0.18).SetTrans(Tween.TRANS_BACK).SetEase(Tween.EASE_OUT);
            var now = Time.GetTicksMsec();
            if (now - (long)_punch_ms.Get(kind, 0) > 70)            // a quick run of clinks, not a roar
            {
                _punch_ms[kind] = now;
                Sfx(kind);                                           // 0.31.109: coin / gem / ember, each its own
            }
        }

        public void ShowTitle()
        {
            // 0.31.139: the title screen (title_screen.gd) on its own layer over everything; a tap lifts it off Home
            var layer = new CanvasLayer();
            layer.Layer = 90;
            AddChild(layer);
            title_screen = new TitleScreen(this, (bool)profile.d["settings"].Get("reduce_motion", false));
            layer.AddChild(title_screen);
            title_screen.Done += () =>
            {
                title_screen = null;
                layer.QueueFree();
            };
            _TitleWhenDrawn();
        }

        public void AdoptTitle(TitleScreen ts)
        {
            // 0.31.141 (Kevin: "Make the intro splash screen more exciting and also load faster"): the boot screen
            // (content_loader.gd) puts the title up as soon as it can and loads the game behind it; the game takes it over here
            title_screen = ts;
            ts.app = this;
            var layer = ts.GetParent();
            ts.Done += () =>
            {
                title_screen = null;
                if (GD.IsInstanceValid(layer) && layer is CanvasLayer)
                    layer.QueueFree();
            };
            _TitleWhenDrawn();
        }

        public async void _TitleWhenDrawn()
        {
            try
            {
                // Home is built: once it has been drawn behind the title (its 3D compiled), the title says TAP TO START
                for (int i = 0; i < 3; i++)
                    await Await.ProcessFrame();
                if (GD.IsInstanceValid(title_screen))           // (and title_screen.has_method("home_ready"))
                {
                    title_screen.HomeReady();
                    // 0.31.142: Home has been drawn (its 3D compiled); while the title covers it, don't draw it at all, so the title's
                    // show has the phone to itself -- back as the title starts to lift off it
                    if (!title_screen.leaving)                  // (title_screen.has_signal("lifting"))
                    {
                        Visible = false;
                        var ts = title_screen;
                        Action on_lift = null, on_exit = null;   // (CONNECT_ONE_SHOT)
                        on_lift = () => { ts.Lifting -= on_lift; Visible = true; };
                        on_exit = () => { ts.TreeExiting -= on_exit; Visible = true; };
                        ts.Lifting += on_lift;
                        ts.TreeExiting += on_exit;
                    }
                }
                // (0.31.142: how many pipelines the start compiled, and how many of those stopped a frame to do it ("draw"))
                _BootMark(GD.Fmt("title: home ready behind it (pipelines: draw %d, canvas %d, mesh %d, surface %d, specialization %d)",
                    RenderingServer.GetRenderingInfo(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
                    RenderingServer.GetRenderingInfo(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS),
                    RenderingServer.GetRenderingInfo(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
                    RenderingServer.GetRenderingInfo(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
                    RenderingServer.GetRenderingInfo(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION)));
            }
            catch (Exception e) { GD.PushError(e.ToString()); }
        }

        public void OpenPlayerMenu()
        {
            // 0.31.139 (Kevin: "Move the settings cog into a menu that players can press on their level icon on top left"): a
            // small panel under the shield -- who you are (level, XP), SETTINGS and DISCORD. A tap outside closes it.
            CloseModal();
            var m = new Control();
            m.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            m.SetMeta("player_menu", true);
            AddChild(m);
            modal = m;
            player_menu = m;
            var catcher = new Button();
            catcher.Flat = true;
            catcher.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus", "hover_pressed" })
                catcher.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            catcher.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            catcher.SetMeta("action_key", "player_menu_close");
            catcher.Pressed += () =>
            {
                Sfx("menuClose");
                CloseModal();
            };
            m.AddChild(catcher);
            var dim = new ColorRect();
            dim.Color = new Color(0.0, 0.01, 0.04, 0.35);
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            dim.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            m.AddChild(dim);
            var holder = new Control();
            holder.Position = new Vector2(8, 4.0 + safe_top + TOP_H - 2.0);
            holder.Size = new Vector2(GD.Minf(250.0, Size.x - 16.0), 10);
            m.AddChild(holder);
            var v = UI2.Frame(holder, "night", 10, 16.0, "gold");
            (v.GetParent() as Control).CustomMinimumSize = new Vector2(holder.Size.x, 0);
            v.AddThemeConstantOverride("separation", 8);
            GDict d = profile.d;
            var who = UI.Row(v, 8);
            var nm = UI2.Text(who, GD.Str(d["name"]), 18, Color.WHITE, UI2.INK, 5);
            nm.ClipText = true;
            nm.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            var lv = UI2.Text(who, GD.Fmt("LV %d", (int)d["level"]), 18, UI2.GOLD, UI2.INK, 5);
            lv.SizeFlagsHorizontal = Control.SIZE_SHRINK_END;
            var sb = UI2.Button(v, "SETTINGS", "blue", () =>
            {
                Sfx("tab");
                CloseModal();
                ShowTab("settings");
            }, "menu_settings", 18, 46.0, 14.0, UI2.IconPath("gear"));
            sb.Alignment = HorizontalAlignment.Left;
            var claimed = (bool)d.Get("discord", false);
            var db = UI2.Button(v, claimed ? "DISCORD" : GD.Fmt("JOIN OUR DISCORD  +%d", Eco.DISCORD_GEMS), "discord", () =>
            {
                CloseModal();
                Screens.DiscordPress(this);
            }, "menu_discord", 15, 42.0, 14.0);
            db.Alignment = HorizontalAlignment.Left;
            (v.GetParent() as Control).ResetSize();
            var panel = v.GetParent() as Control;
            panel.Scale = new Vector2(0.92, 0.92);
            { var mc = panel.Modulate; mc.a = 0.0f; panel.Modulate = mc; }
            var tw = panel.CreateTween().SetParallel();
            tw.TweenProperty(panel, "scale", Vector2.ONE, 0.14).SetTrans(Tween.TRANS_BACK).SetEase(Tween.EASE_OUT);
            tw.TweenProperty(panel, "modulate:a", 1.0, 0.1);
        }

        public Control _MenuButton(Node bar)
        {
            // 0.31.194 (Kevin picked the camp for Home, without its side buttons -- where they went: "Menu button"): a round
            // button in the top bar; ORDERS, QUESTS, RANKS and the TUTORIAL in a panel under it (open_home_menu). Its badge counts
            // what's ready in them (paint_menu); until the tutorial's been played it glows, with a "!".
            var holder = new Control();
            holder.Name = "MenuButton";
            holder.CustomMinimumSize = new Vector2(44, 44);
            holder.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            bar.AddChild(holder);
            var glow = UI2.Glow(holder, new Rect2(-14, -14, 72, 72), new Color(1.0, 0.85, 0.4, 0.55));
            glow.Name = "MenuGlow";
            glow.Visible = false;
            var disc = new Control();
            disc.Name = "Disc";
            disc.Position = new Vector2(1, 1);
            disc.Size = new Vector2(42, 42);
            disc.PivotOffset = new Vector2(21, 21);
            disc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            holder.AddChild(disc);
            UI2.Plate(disc, "royal", 21.0, "gold", new GDict { { "rim", 3.0 }, { "shadow_y", 3.0 } });
            for (int i = 0; i < 3; i++)                                  // (three bars: the menu)
            {
                var line = new Panel();
                var sb = new StyleBoxFlat();
                sb.BgColor = UI2.CREAM;
                sb.BorderColor = UI2.INK;
                sb.SetBorderWidthAll(1);
                sb.SetCornerRadiusAll(3);
                line.AddThemeStyleboxOverride("panel", sb);
                line.Position = new Vector2(10, 12.0 + i * 7.0);
                line.Size = new Vector2(22, 5);
                line.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                disc.AddChild(line);
            }
            var b = new Button();
            b.Flat = true;
            b.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus", "hover_pressed" })
                b.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            b.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            b.OffsetLeft = -4;
            b.OffsetRight = 4;
            b.OffsetTop = -4;
            b.OffsetBottom = 4;
            b.SetMeta("action_key", "home_menu");
            b.Pressed += () =>
            {
                if (GD.IsInstanceValid(home_menu) && modal == home_menu)
                {
                    Sfx("menuClose");
                    CloseModal();
                    return;
                }
                Sfx("menuOpen");
                OpenHomeMenu();
            };
            holder.AddChild(b);
            menu_badge = UI2.Badge(disc, "0", new Vector2(8, -8));
            menu_badge.Visible = false;
            return holder;
        }

        public void PaintMenu()
        {
            // 0.31.194: the menu button's badge -- the orders and quest steps ready to claim (with the daily reward), and a "!"
            // (and a glow) until the tutorial's been played
            if (menu_badge == null)
                return;
            GDict c = Screens.MenuCounts(this);
            var n = (int)c["orders"] + (int)c["quests"];
            var fresh = !(bool)c["tutorial_done"];
            menu_badge.Visible = n > 0 || fresh;
            var bl = menu_badge.FindChildren("*", "Label", true, false);
            if (bl.Count != 0)
                (bl[0] as Label).Text = n > 0 ? GD.Str(n) : "!";
            var g = menu_button.GetNodeOrNull("MenuGlow");
            if (g != null)
                (g as CanvasItem).Visible = fresh;
            var disc = menu_button.GetNodeOrNull("Disc") as Control;
            if (disc == null || !disc.IsInsideTree())
                return;
            var want = n > 0 || fresh;                    // (it wiggles now and then while something's waiting)
            Tween tw = disc.HasMeta("wiggle") ? disc.GetMeta("wiggle") as Tween : null;
            if (want && (tw == null || !tw.IsValid()))
            {
                tw = disc.CreateTween().SetLoops();
                tw.TweenInterval(3.0);
                foreach (var a in new[] { -12.0, 10.0, -7.0, 4.0, 0.0 })
                    tw.TweenProperty(disc, "rotation", GD.DegToRad(a), 0.08);
                disc.SetMeta("wiggle", tw);
            }
            else if (!want && tw != null)
            {
                tw.Kill();
                disc.RemoveMeta("wiggle");
                disc.Rotation = 0.0;
            }
        }

        public void OpenHomeMenu()
        {
            // 0.31.194: what Home's side buttons were, in a panel under the menu button -- ORDERS (the daily reward, the daily
            // and weekly orders), QUESTS (each champion's quest line), RANKS (the week's leaderboard) and the TUTORIAL (with its
            // gold until that's been paid). PASS has its own tab. A tap outside closes it.
            CloseModal();
            GDict c = Screens.MenuCounts(this);
            var m = new Control();
            m.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            m.SetMeta("home_menu", true);
            AddChild(m);
            modal = m;
            home_menu = m;
            var catcher = new Button();
            catcher.Flat = true;
            catcher.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus", "hover_pressed" })
                catcher.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            catcher.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            catcher.SetMeta("action_key", "home_menu_close");
            catcher.Pressed += () =>
            {
                Sfx("menuClose");
                CloseModal();
            };
            m.AddChild(catcher);
            var dim = new ColorRect();
            dim.Color = new Color(0.0, 0.01, 0.04, 0.35);
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            dim.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            m.AddChild(dim);
            var pw = GD.Minf(290.0, Size.x - 16.0);
            var holder = new Control();
            var bx = menu_button != null ? menu_button.GlobalPosition.x + menu_button.Size.x * 0.5 : Size.x - 120.0;
            holder.Position = new Vector2(GD.Clampf(bx - pw * 0.62, 8.0, Size.x - 8.0 - pw), 4.0 + safe_top + TOP_H - 2.0);
            holder.Size = new Vector2(pw, 10);
            m.AddChild(holder);
            var v = UI2.Frame(holder, "night", 10, 16.0, "gold");
            var panel = v.GetParent() as Control;
            panel.CustomMinimumSize = new Vector2(pw, 0);
            v.AddThemeConstantOverride("separation", 6);
            var tdone = (bool)c["tutorial_done"];
            _MenuRow(v, "scroll", "ORDERS", "The daily reward and your orders", (int)c["orders"], "side_orders", () =>
            {
                Sfx("menuOpen");
                OpenOrders();
            });
            _MenuRow(v, Screens.QuestIconName(), "QUESTS", "Every champion's quest line", (int)c["quests"], "side_quests", () =>
            {
                Sfx("tab");
                CloseModal();
                quest_cls = Screens.QuestFirst(profile);
                ShowTab("quests");
            });
            _MenuRow(v, "trophy", "RANKS", "This week's leaderboard", 0, "side_ranks", () =>
            {
                Sfx("menuOpen");
                OpenLeaderboard();
            });
            var tr = _MenuRow(v, "horn", "TRAINING", !tdone ? (GD.Fmt("Learn with Kael  ·  +%d gold", TUTORIAL_GOLD)) : "The basics, or a 5v5 with Kael", 0,
                "tutorial_start", () =>
                {
                    CloseModal();
                    Sfx("confirm");
                    StartTutorial();
                }, !tdone ? "gold" : "silver");
            if (!tdone)
            {
                UI2.Glow(tr.GetMeta("disc") as Control, new Rect2(-12, -12, 70, 70), new Color(1.0, 0.85, 0.4, 0.5));
                UI2.Wiggle(tr.GetMeta("icon") as Control, 1.6);
            }
            panel.ResetSize();
            panel.PivotOffset = new Vector2(pw * 0.62, 0.0);
            panel.Scale = new Vector2(0.92, 0.92);
            { var mc = panel.Modulate; mc.a = 0.0f; panel.Modulate = mc; }
            var tw = panel.CreateTween().SetParallel();
            tw.TweenProperty(panel, "scale", Vector2.ONE, 0.14).SetTrans(Tween.TRANS_BACK).SetEase(Tween.EASE_OUT);
            tw.TweenProperty(panel, "modulate:a", 1.0, 0.1);
        }

        public Button _MenuRow(Node parent, string icon, string title, string sub, int badge, string key, Action on_press, string rim = "gold")
        {
            // one of the menu's rows: a medallion with its icon (and a badge), the name and a line under it
            var b = new Button();
            b.Flat = true;
            b.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "focus", "hover_pressed" })
                b.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            var pressed = new StyleBoxFlat();
            pressed.BgColor = new Color(1, 1, 1, 0.08);
            pressed.SetCornerRadiusAll(12);
            b.AddThemeStyleboxOverride("pressed", pressed);
            b.CustomMinimumSize = new Vector2(0, 60);
            b.SetMeta("action_key", key);
            b.Pressed += on_press;
            parent.AddChild(b);
            var r = new HBoxContainer();
            r.AddThemeConstantOverride("separation", 10);
            r.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            r.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.AddChild(r);
            var disc = new Control();
            disc.CustomMinimumSize = new Vector2(52, 52);
            disc.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            disc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            r.AddChild(disc);
            UI2.Plate(disc, "royal", 26.0, rim, new GDict { { "rim", 3.0 }, { "shadow_y", 4.0 } });
            var ic = UI2.Icon(disc, icon, 44.0);
            ic.Position = new Vector2(4, 3);
            ic.PivotOffset = new Vector2(22, 22);
            if (badge > 0)
                UI2.Badge(disc, GD.Str(badge), new Vector2(6, -6));
            var col = new VBoxContainer();
            col.AddThemeConstantOverride("separation", 0);
            col.Alignment = BoxContainer.ALIGNMENT_CENTER;
            col.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            col.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            r.AddChild(col);
            var t = UI2.Text(col, title, 19, Color.WHITE, UI2.INK, 5);
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            var s = UI2.Body(col, sub, 12, UI2.SOFT);
            s.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.SetMeta("disc", disc);
            b.SetMeta("icon", ic);
            return b;
        }

        public void PaintAlliance()
        {
            // 0.31.139: the ALLIANCE tab's badge: friend requests, party and clan invites, clan join requests (as SOCIAL had)
            if (alliance_badge == null)
                return;
            int n = social != null && social.Online() ? social.Attention() : 0;
            alliance_badge.Visible = n > 0;
            var bl = alliance_badge.FindChildren("*", "Label", true, false);
            if (bl.Count != 0)
                (bl[0] as Label).Text = GD.Str(n);
        }

        public double HomePlayTop()
        {
            // where PLAY's top is on the screen (the camp stands the champions' feet just over it)
            // (0.31.216: the chests' top -- the heroes stand over the chests in landscape; PLAY's top in portrait)
            return 4.0 + safe_top + TOP_H + 4.0 + (double)Screens.HomeLayout(HomeHeight())["chests"];
        }

        public double HomeHeight()
        {
            // the height Home has to fill: the screen less the top bar, the chat line, the tab bar and the list's margins
            double vh = GetViewportRect().size.y;
            var ticker = chat_ticker != null ? (double)ChatTicker.H : 0.0;
            return vh - (4.0 + safe_top + TOP_H) - ticker - 20.0;       // (0.31.216: no tab bar under it -- the rail is beside it)
        }

        public void ShowTab(string id)
        {
            if (GD.IsInstanceValid(modal))
                CloseModal();                          // (a window's button that goes to another tab, e.g. the pass summary)
            if (analytics != null && (id == "shop" || id == "pass") && (tab != id || siege != null))
                analytics.LogEv("shop_view", new GDict { { "tab", id } });
            if (heycatch != null)
                heycatch.Screen(id);                          // 0.31.212: a screen view (the tab; not the same one twice in a row)
            tab = id;
            profile.Refresh();
            foreach (var t in tab_buttons)
                _StyleTab(tab_buttons[t].D, GD.Str(t) == id);
            hero_layer.Visible = id == "home";
            if (chat_ticker != null)
                chat_ticker.Visible = id == "home";
            if (online_status != null)
                online_status.SetActive(id == "home" && siege == null);
            hero_layer.Position = Vector2.ZERO;
            hero_layer.Scale = Vector2.ONE;
            { var mc = hero_layer.Modulate; mc.a = 1.0f; hero_layer.Modulate = mc; }
            content_scroll.ScrollVertical = 0;
            Rebuild();
            content_scroll.VerticalScrollMode = (id == "home" && home_fixed) ? ScrollContainer.SCROLL_MODE_SHOW_NEVER
                : ScrollContainer.SCROLL_MODE_AUTO;
            { var mc = content.Modulate; mc.a = 0.0f; content.Modulate = mc; }
            CreateTween().TweenProperty(content, "modulate:a", 1.0, 0.18);
            if (id == "home")
                CallDeferred(OfferDaily);
        }

        public void Rebuild()
        {
            // Screens are rebuilt from the profile after every change; they're small and static.
            foreach (var c in content.GetChildren())
            {
                content.RemoveChild(c);
                c.QueueFree();
            }
            if (tab == "home" && social != null)
                _social_sig = SocialSig();             // (what Home is about to show of the social side)
            if (GD.IsInstanceValid(modal) && GObject.HasMethod(modal, "refresh"))
                GObject.Call(modal, "refresh");        // 0.31.112: a window showing the profile (ORDERS) follows it
            switch (tab)
            {
                case "home": Screens.Home(this, content); break;
                case "pass": Screens.PassScreen(this, content); break;
                case "shop": Screens.Shop(this, content); break;
                case "locker": Screens.Locker(this, content); break;
                case "settings": Screens.Settings(this, content); break;
                case "quests": Screens.Quests(this, content); break;
            }
            RefreshTop();
        }

        // ---------------- players online (0.31.82) ----------------
        public void PaintOnline()
        {
            // Home's pill from the last status answer: "12 PLAYERS ONLINE" (or the plain server line while unknown)
            Label main = online_refs.Get("main").As<Label>();
            Label sub = online_refs.Get("sub").As<Label>();
            if (!GD.IsInstanceValid(main) || !GD.IsInstanceValid(sub))
                return;
            GDict info = online_status != null ? online_status.info : new GDict();
            // (0.31.139: a short line -- the pill sits between the medallion columns at the top now)
            if (info.IsEmpty())
            {
                main.Text = "FATEBOUND";                    // (0.31.164: was LIVE SIEGE SERVER / 16 vs 16)
                sub.Text = "5 vs 5";
                return;
            }
            // 0.31.140 (Kevin: "make sure it shows players currently online"): everyone with the game open -- the server's
            // "chatting" (its social connections: Home, the menus and matches alike; you're one of them), not "online" (only the
            // players in a match room, which said 0 with Kevin on Home in 0.31.117). An older server without it: "online".
            var n = GD.Maxi((int)info.Get("chatting", 0), (int)info.Get("online", 0));
            if (n < 1 && social != null && social.Online())
                n = 1;                                       // (you are)
            main.Text = n >= 1 ? (GD.Fmt("%d PLAYER%s ONLINE", n, n == 1 ? "" : "S")) : "FATEBOUND";
            if (!ONLINE_MATCHES)
            {
                sub.Text = "5 vs 5";                        // (0.31.164: no lobby or battles on the server to count)
                return;
            }
            var fighting = (int)info.Get("in_match", 0);
            var waiting = (int)info.Get("waiting", 0);
            if (waiting > 0 && (double)info.Get("lobby", -1.0) >= 0.0)
                sub.Text = GD.Fmt("%d in the lobby", waiting);
            else if (fighting > 0)
                sub.Text = GD.Fmt("%d in battle", fighting);
            else
                sub.Text = "5 vs 5";
        }

        // ---------------- feedback ----------------
        public void Toast(string text, Color? color = null)
        {
            var col = color ?? UI.TEXT;
            _toast.Text = text;
            _toast.AddThemeColorOverride("font_color", UI.Ink(col));     // (0.31.195: the good news white, not gold)
            _toast_box.Visible = true;
            { var mc = _toast_box.Modulate; mc.a = 1.0f; _toast_box.Modulate = mc; }
            _toast_until = Time.GetTicksMsec() / 1000.0 + 2.8;
            MoveChild(_toast_box, GetChildCount() - 1);
        }

        public void Confirm(string title_text, string body, string yes_text, string style, Action on_yes, Action on_no = null)
        {
            Sfx("menuOpen");
            CloseModal();
            modal = new Control();
            modal.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            AddChild(modal);
            var dim = new ColorRect();
            dim.Color = new Color(0, 0, 0, 0.6);
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            modal.AddChild(dim);
            var center = new CenterContainer();
            center.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            modal.AddChild(center);
            var v = UI.Card(center);
            (v.GetParent() as Control).CustomMinimumSize = new Vector2(GD.Minf(360, Size.x - 32), 0);
            UI.Title(v, title_text, 20);
            var b = UI.Label(v, body, 14, UI.MUTED);
            b.HorizontalAlignment = HorizontalAlignment.Center;
            var r = UI.Row(v, 10);
            UI.Grow(UI.Button(r, "CANCEL", "secondary", () =>
            {
                Sfx("menuClose");
                CloseModal();
                if (on_no != null)
                    on_no();
            }, "modal_no"));
            UI.Grow(UI.Button(r, yes_text, style, () =>
            {
                CloseModal();
                on_yes();
            }, "modal_yes"));
        }

        public void Choose(string title_text, string body, GArray options)
        {
            // 0.31.189: a question with a button for each way (an outfit for gems or for gold): options [{text, style, key,
            // enabled, call}], then CANCEL; the dialog closes before the chosen call runs
            Sfx("menuOpen");
            CloseModal();
            modal = new Control();
            modal.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            AddChild(modal);
            var dim = new ColorRect();
            dim.Color = new Color(0, 0, 0, 0.6);
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            modal.AddChild(dim);
            var center = new CenterContainer();
            center.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            modal.AddChild(center);
            var v = UI.Card(center);
            (v.GetParent() as Control).CustomMinimumSize = new Vector2(GD.Minf(360, Size.x - 32), 0);
            UI.Title(v, title_text, 20);
            var b = UI.Label(v, body, 14, UI.MUTED);
            b.HorizontalAlignment = HorizontalAlignment.Center;
            b.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            foreach (var o in options)
            {
                Delegate call = o["call"].Obj as Delegate;      // (a Callable: called with no arguments, as call.call())
                var ob = UI.Button(v, GD.Str(o["text"]), GD.Str(o["style"]), () =>
                {
                    CloseModal();
                    GObject.Invoke(call);
                }, GD.Str(o["key"]));
                ob.Disabled = !(bool)o.Get("enabled", true);
            }
            UI.Button(v, "CANCEL", "secondary", () =>
            {
                Sfx("menuClose");
                CloseModal();
            }, "modal_no");
        }

        public void Notice(string title_text, string body)
        {
            // 0.31.119: a message with one OK (why a match ended, ...)
            Sfx("menuOpen");
            CloseModal();
            modal = new Control();
            modal.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            AddChild(modal);
            var dim = new ColorRect();
            dim.Color = new Color(0, 0, 0, 0.6);
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            modal.AddChild(dim);
            var center = new CenterContainer();
            center.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            modal.AddChild(center);
            var v = UI.Card(center);
            (v.GetParent() as Control).CustomMinimumSize = new Vector2(GD.Minf(360, Size.x - 32), 0);
            UI.Title(v, title_text, 20);
            var b = UI.Label(v, body, 14, UI.MUTED);
            b.HorizontalAlignment = HorizontalAlignment.Center;
            b.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            UI.Grow(UI.Button(UI.Row(v, 10), "OK", "primary", () =>
            {
                Sfx("menuClose");
                CloseModal();
            }, "modal_ok"));
        }

        public void CloseModal()
        {
            if (GD.IsInstanceValid(modal))
                modal.QueueFree();
            modal = null;
            if (social != null)
                CallDeferred(_SocialHome);
        }

        // ---------------- menu drag-scroll (0.18.3, Kevin: "the main menu can't scroll up and down") ----------------
        // Every screen is cards and buttons, and those stop input, so the ScrollContainer's own touch drag
        // never started. Here the app sees events before the controls: a press inside the menu that moves
        // more than DRAG_START px vertically becomes a scroll; the control under the finger gets a
        // cancelled press (released off-screen) so it doesn't fire; short taps pass through untouched.
        public const double DRAG_START = 14.0;
        public bool _drag_down = false;
        public bool _dragging = false;
        public Vector2 _drag_from = Vector2.ZERO;
        public double _drag_scroll0 = 0.0;
        public double _fling = 0.0;
        public bool _cancelling = false;
        public bool _swallow_up = false;
        public ScrollContainer _drag_sc = null;

        public bool _MenuScrollLive()
        {
            return _ScrollTarget() != null;
        }

        public ScrollContainer _ScrollTarget()
        {
            // the menu's own list -- or, with a window open that has one (0.31.111: the chat, Friends), that window's list
            if (siege != null)
                return null;
            if (GD.IsInstanceValid(modal))
            {
                object ms = modal.HasMeta("drag_scroll") ? modal.GetMeta("drag_scroll") : null;   // (a null default still errors)
                if (ms is ScrollContainer && GD.IsInstanceValid(ms) && (ms as ScrollContainer).IsVisibleInTree())
                    return ms as ScrollContainer;
                return null;
            }
            if (tab == "home" && home_fixed)
                return null;                            // 0.31.112: Home doesn't scroll
            if (GD.IsInstanceValid(content_scroll) && content_scroll.IsVisibleInTree())
                return content_scroll;
            return null;
        }

        protected override void _Input(InputEvent @event)
        {
            if (_building)
                return;
            // (event.position / event.pressed: the touch's or the mouse's -- each of these events has them)
            Vector2 ev_position = @event is InputEventScreenTouch st0 ? st0.Position : @event is InputEventScreenDrag sd0 ? sd0.Position
                : @event is InputEventMouse ms0 ? ms0.Position : Vector2.ZERO;
            if ((@event is InputEventScreenTouch || (@event is InputEventMouseButton mb0 && mb0.ButtonIndex == MouseButton.Left)) && @event.IsPressed())
            {
                _last_press = ev_position;             // (0.31.105: where a claimed reward flies from)
                _last_press_ms = Time.GetTicksMsec();
            }
            if (_cancelling || !_MenuScrollLive())
                return;
            // Touch (the phone) or a real mouse (desktop). Mouse events emulated from touch are ignored
            // here (the touch events drive it) and swallowed while a scroll is in progress.
            bool is_touch = @event is InputEventScreenTouch || @event is InputEventScreenDrag;
            bool emulated = (@event is InputEventMouse) && @event.Device == InputEvent.DEVICE_ID_EMULATION;
            if (is_touch && (@event is InputEventScreenTouch st1 ? st1.Index : ((InputEventScreenDrag)@event).Index) != 0)
                return;
            if (emulated)
            {
                // Swallow the pointer while scrolling, and the finger-lift release that follows a scroll
                // (whichever order the platform delivers the touch and its emulated mouse event in).
                if (_dragging || (_swallow_up && @event is InputEventMouseButton && !@event.IsPressed()))
                {
                    if (@event is InputEventMouseButton && !@event.IsPressed())
                        _swallow_up = false;
                    GetViewport().SetInputAsHandled();
                }
                return;
            }
            bool press = (@event is InputEventScreenTouch) || (@event is InputEventMouseButton mb1 && mb1.ButtonIndex == MouseButton.Left);
            bool motion = (@event is InputEventScreenDrag) || (@event is InputEventMouseMotion mm0 && (mm0.ButtonMask & MouseButtonMask.Left) != 0);
            if (press)
            {
                if (@event.IsPressed())
                {
                    _swallow_up = false;
                    var sc = _ScrollTarget();
                    if (sc.GetGlobalRect().HasPoint(ev_position))
                    {
                        _drag_sc = sc;
                        _drag_down = true;
                        _dragging = false;
                        _drag_from = ev_position;
                        _drag_scroll0 = sc.ScrollVertical;
                        _fling = 0.0;
                    }
                }
                else
                {
                    if (_dragging)
                    {
                        GetViewport().SetInputAsHandled();
                        _swallow_up = true;
                    }
                    _drag_down = false;
                    _dragging = false;
                }
            }
            else if (motion && _drag_down)
            {
                double dy = (double)ev_position.y - _drag_from.y;
                if (!_dragging && GD.Absf(dy) > DRAG_START)
                {
                    _dragging = true;
                    _CancelPress();
                }
                if (_dragging && GD.IsInstanceValid(_drag_sc))
                {
                    _drag_sc.ScrollVertical = (int)(_drag_scroll0 - dy);
                    // ("velocity" in event: both a drag and a mouse motion have it)
                    double vy = @event is InputEventScreenDrag sd1 ? sd1.Velocity.y : ((InputEventMouseMotion)@event).Velocity.y;
                    _fling = GD.Clampf(-vy, -4000.0, 4000.0);
                    GetViewport().SetInputAsHandled();
                }
            }
        }

        public void _CancelPress()
        {
            // Cancel the pressed control: move the pointer off-screen first (buttons update "pressing
            // inside" only from motion, and the drag's motion is swallowed -- without this PLAY still fired
            // after a scroll), then release there. Godot buttons only fire when released over them.
            _cancelling = true;
            var away = new InputEventMouseMotion();
            away.Position = new Vector2(-10000, -10000);
            away.GlobalPosition = away.Position;
            away.ButtonMask = MouseButtonMask.Left;
            GetViewport().PushInput(away, true);
            var up = new InputEventMouseButton();
            up.ButtonIndex = MouseButton.Left;
            up.Pressed = false;
            up.Position = new Vector2(-10000, -10000);
            up.GlobalPosition = up.Position;
            GetViewport().PushInput(up, true);
            _cancelling = false;
        }

        protected override void _Process(double _delta)
        {
            if (_building)
                return;                                 // (0.31.142: Home still being built behind the boot title)
            Assets.Poll();
            // Keep gliding after a flick, easing out.
            if (!_drag_down && GD.Absf(_fling) > 30.0 && _MenuScrollLive() && _ScrollTarget() == _drag_sc)
            {
                _drag_sc.ScrollVertical = (int)(_drag_sc.ScrollVertical + _fling * _delta);
                _fling *= GD.Pow(0.04, _delta);
            }
            else if (!_drag_down)
                _fling = 0.0;
            if (_toast_box.Visible)
            {
                var left = _toast_until - Time.GetTicksMsec() / 1000.0;
                { var mc = _toast_box.Modulate; mc.a = (float)GD.Clampf(left / 0.5, 0.0, 1.0); _toast_box.Modulate = mc; }
                if (left <= 0.0)
                    _toast_box.Visible = false;
            }
            _FitModal();
        }

        public void _FitModal()
        {
            // 0.31.216: landscape -- a window card (a CenterContainer's) taller or wider than the screen is drawn smaller to fit
            // it whole, about its middle; nothing changes for one that fits
            if (!GD.IsInstanceValid(modal))
                return;
            foreach (var c in modal.GetChildren())
            {
                if (c is CenterContainer && c.GetChildCount() > 0)
                {
                    var card = c.GetChild(0) as Control;
                    if (card == null)
                        continue;
                    var need = card.GetCombinedMinimumSize();
                    var avail = Size - new Vector2(16.0 + safe_left + safe_right, 12.0);
                    var k = GD.Clampf(GD.Minf((double)avail.y / GD.Maxf(need.y, 1.0), (double)avail.x / GD.Maxf(need.x, 1.0)), 0.5, 1.0);
                    if (GD.Absf(card.Scale.x - k) > 0.005 || card.PivotOffset != need * 0.5)
                    {
                        card.PivotOffset = need * 0.5;
                        card.Scale = new Vector2(k, k);
                    }
                }
            }
        }

        // ---------------- matches ----------------
        public const int TUTORIAL_GOLD = Eco.TUTORIAL_GOLD;
        public bool _ticket_wait = false;              // 0.31.108: asking the server for a VS BOTS ticket
        public bool _ticket_ok = false;

        public void _OnEcoSynced(bool differs)
        {
            // 0.31.108: the profile is the server's again; redraw only if something shown changed (and not mid-match)
            if (social != null && social.Online() && GD.Str(profile.d["name"]) != _social_name)
            {
                _social_name = GD.Str(profile.d["name"]);
                social.Refresh();                          // 0.31.111: a new name -- the chat and friends lists show it
            }
            if (analytics != null)
                analytics.NoteLevel((int)profile.d["level"]);
            if (siege == null && tab == "home")
            {
                CallDeferred(() => OfferIntro());               // 0.31.198: no name yet (a new account -- after the wipe, everyone's)
                CallDeferred(() => OfferReferral());            // 0.31.120: a referral chest that came with this answer (it checks)
            }
            if (!differs || siege != null)
                return;
            RefreshTop();
            if (!GD.IsInstanceValid(modal))
                Rebuild();
        }

        // (`_later(X).new()` below: the port makes the window's C# class itself -- a script isn't a resource there, and
        // nothing is compiled at run time, so there is nothing to load first)
        public void OpenMoba()
        {
            // 0.31.155 5V5 (the test): the hero window (moba_panel.gd), then BATTLE -> start_moba
            CloseModal();
            var m = new MobaPanel();
            AddChild(m);
            modal = m;
            m.Open(this);
        }

        public void OpenChampion(string hid, string skin = "__worn", bool owned_only = false)
        {
            // 0.31.187: a champion's window (champion_window.gd) -- his place, his effects, him in 3D, his skins, story and kit.
            // 0.31.204: from the Armory (owned_only), only the outfits of his you own
            CloseModal();
            var m = new ChampionWindow();
            AddChild(m);
            modal = m;
            m.Open(this, hid, skin, owned_only);
        }

        public void OpenMarket(string tab_id, string hero_focus = "")
        {
            // 0.31.204: the Market on one of its tabs (OUTFITS, HEROES, GEMS) -- from the 5v5 picker's GET IN MARKET, the Armory's
            // MORE IN THE MARKET, a hero window's; hero_focus: the hero whose card the HEROES tab glides to and lights up
            shop_tab = tab_id;
            if (hero_focus != "")
                SetMeta("shop_hero_focus", hero_focus);
            ShowTab("shop");
        }

        public void StartMoba(string hero)
        {
            // 0.31.155: an offline 5v5 against bots as this hero (siege_mode.gd moba_hero; scripts/siege/moba.gd). 0.31.164: the
            // game's match -- a VS BOTS ticket from the server first, paid like one (start_match). 0.31.170: online -- the
            // server's 5v5, with whoever else is playing and bots in the seats nobody has taken (against bots only when the
            // server is from before it)
            if (siege != null)
                return;
            if (ONLINE_MATCHES && server_five != 0)
            {
                StartOnlineMoba(hero);
                return;
            }
            pending_moba = hero;
            StartMatch(false);
            if (siege == null && !_ticket_wait)
                pending_moba = "";                          // (no ticket: nothing started)
        }

        public string pending_moba = "";                    // 0.31.155: the hero the next match is a 5v5 with
        public bool pending_tutorial = false;             // 0.31.181: the next match is the tutorial
        public int pending_training = 1;                 // 0.31.217: ...which training

        public void StartTutorial()
        {
            // 0.31.181 (Kevin: "create a tutorial walking player through the basics of a match"): the tutorial. 0.31.217 (Kevin,
            // with Honor of Kings' training: "Here is how I want the training to go in fatebound"): the TRAINING window first --
            // which of the two and a hero of three (training_pick.gd) -- then start_training
            if (siege != null)
                return;
            CloseModal();
            var m = new TrainingPick();
            AddChild(m);
            modal = m;
            m.Open(this);
        }

        public void StartTraining(int which, string hid)
        {
            // a match against bots on this phone with Kael the Dragoon (scripts/siege/training.gd): 1 the basics on a quiet
            // Rift, 2 a real 5v5. No ticket (nothing in it is paid like a match); its own gold, once, when one's finished
            // (Profile.finish_tutorial)
            if (siege != null)
                return;
            pending_tutorial = true;
            pending_training = GD.Clampi(which, 1, 2);
            pending_moba = (hid == "knight" || hid == "mage" || hid == "ranger") ? hid : "knight";       // (training_pick.gd HEROES)
            StartMatch(false, true);
            pending_tutorial = false;
        }
        public bool _flush_wait = false;

        public void StartOnlineMoba(string hero, bool follow = false)
        {
            // 0.31.170: into the server's 5v5 as this hero. Changes still on their way to the server go first -- a hero bought a
            // moment ago must be the account's there, or the match seats you as another
            if (siege != null)
                return;
            if (eco_sync != null && eco_sync.enabled && eco_sync.Pending() > 0 && !follow)
            {
                if (_flush_wait)
                    return;
                _flush_wait = true;
                Toast("Connecting to the server...", UI.GOLD);
                eco_sync.Flush(() =>
                {
                    _flush_wait = false;
                    StartOnlineMoba(hero, true);
                });
                return;
            }
            pending_moba = hero;
            StartMatch(true, follow);
            if (siege == null)
                pending_moba = "";
        }

        public string SavedHero()
        {
            // the hero window's last pick (settings.moba_hero), if it's still yours (0.31.185: or still free this week)
            var h = GD.Str(profile.d["settings"].Get("moba_hero", ""));
            var heroes = Moba.HEROES;      // (loaded when needed: not at boot)
            return heroes.ContainsKey(h) && profile.CanPlayHero(h) ? h : "knight";
        }

        public string pending_join = "";                   // 0.31.120: a friend's public id whose match the next PLAY joins

        public void JoinFriend(string pid)
        {
            // 0.31.120 (Kevin: "make so it's a join match option"): Friends > JOIN on a friend who's in a match
            if (!ONLINE_MATCHES)
            {
                Toast("Matches with friends are coming to 5v5 soon", UI.MUTED);     // 0.31.164 (5v5 only: offline for now)
                return;
            }
            if (social != null && social.InParty() && social.PartySize() > 1)
            {
                Sfx("error");
                Toast("Leave your party to join a friend's match", UI.MUTED);
                return;
            }
            CloseModal();
            pending_join = pid;
            pending_moba = SavedHero();                      // 0.31.170: as your last pick
            StartMatch(true);
            if (siege == null)
            {
                pending_join = "";
                pending_moba = "";
            }
        }

        // 0.31.164 (Kevin, on the new 5v5 map: "Remove them now: 5v5 only"): Siege, Commander, the tutorial and the war map's
        // battles are gone from the app -- PLAY is the 5v5 (the hero window, then a match against bots, paid like any match).
        // Online matches come back with an online 5v5; until then JOIN and a party's PLAY don't start one. (0.31.169: their
        // code went too -- Crown War with it.) 0.31.170: the online 5v5 -- PLAY, a party's PLAY and JOIN go to the server's
        // match (Kevin: "Only have the regular play button so player is always playing on server plus they play with bots
        // anyway when there aren't enough players")
        public const bool ONLINE_MATCHES = true;

        public void Play()
        {
            // Home's PLAY: the 5v5's hero window (0.31.164)
            if (update_required)
            {
                ShowUpdateScreen();
                return;
            }
            Sfx("menuOpen");
            OpenMoba();
        }

        public void StartMatch(bool online, bool follow = false)
        {
            if (siege != null)
                return;
            if (online && update_required)
            {
                ShowUpdateScreen();               // online stays locked until the update is installed
                return;
            }
            if (online && social != null && social.Online() && social.InParty())
            {
                // 0.31.111: a party plays together -- the leader's PLAY takes everyone in the menu along (social "play" ->
                // "go"); a member waits for the leader (follow: the leader's "go" arrived)
                if (social.IsLeader())
                    social.Play();
                else if (!follow)
                {
                    Sfx("error");
                    var lead = GD.Str(social.CardOf(GD.Str(social.party.Get("leader", ""))).Get("n", "your leader"));
                    Toast(GD.Fmt("%s starts your party's match -- or leave the party to play alone", lead), UI.MUTED);
                    return;
                }
            }
            if (!online && eco_sync != null && eco_sync.enabled && !_ticket_ok && !pending_tutorial)
            {
                // 0.31.108 (Kevin: "Always online"): a VS BOTS match pays only against a ticket the server gives now
                if (_ticket_wait)
                    return;
                _ticket_wait = true;
                Toast("Connecting to the server...", UI.GOLD);
                eco_sync.RequestTicket((string tk) =>
                {
                    _ticket_wait = false;
                    if (tk == "")
                    {
                        Sfx("error");
                        Toast("A match needs a connection to the server", UI.RED);
                        pending_moba = "";
                        return;
                    }
                    _ticket_ok = true;
                    StartMatch(false);
                    _ticket_ok = false;
                });
                return;
            }
            Sfx("matchStart");
            if (analytics != null && !pending_tutorial)
                analytics.LogEv("match_join", new GDict { { "mode", online ? "online" : "bots" },
                    { "party_n", social != null && social.Online() && social.InParty() ? social.PartySize() : 1 } });
            if (heycatch != null)
                heycatch.Screen(pending_tutorial && !online ? "tutorial" : (online ? "match_online" : "match_bots"));
            siege = new SiegeMode();
            siege.online = online;
            siege.tutorial = pending_tutorial && !online;
            siege.training = pending_training;             // 0.31.217
            if (pending_moba != "")
            {
                siege.moba_hero = pending_moba;              // 0.31.155 (start_moba: through the tutorial's door, a full 5v5)
                pending_moba = "";
            }
            siege.profile = profile;
            siege.audio = audio;
            siege.low_fx = (bool)profile.d["settings"].Get("reduce_motion", false);
            siege.hq_gfx = true;                         // 0.31.163: always (no toggle in Settings; an old saved "off" is ignored)
            siege.vibrate = (bool)profile.d["settings"].Get("vibrate", true);          // 0.31.120
            siege.player_name = GD.Str(profile.d["name"]);
            siege.clan_tag = social != null ? social.MyTag() : "";        // 0.31.134: on your own plate
            siege.clan_crest = social != null ? social.MyCrest() : "";    // 0.31.196
            siege.analytics = analytics;
            siege.party_join = pending_join;                 // 0.31.120: Friends > JOIN (their match)
            pending_join = "";
            siege.Exited += _EndMatch;
            siege.VersionMismatch += _OnVersionMismatch;
            if (online_status != null)
                online_status.SetActive(false);
            _SetMenuActive(false);
            AddChild(siege);
        }

        public void _SetMenuActive(bool on)
        {
            // While a match runs nothing of the menu may render or animate: the home hero owns a
            // physical-resolution 4x-MSAA 3D viewport plus particles, and the PLAY button loops tweens.
            // A hidden layer alone is not enough for the tweens/particles, so processing is disabled too.
            chrome.Visible = on;
            chrome.ProcessMode = on ? ProcessModeEnum.Inherit : ProcessModeEnum.Disabled;
            hero_layer.ProcessMode = on ? ProcessModeEnum.Inherit : ProcessModeEnum.Disabled;
            if (!on)
                hero_layer.Visible = false;          // coming back, show_tab decides (home only)
        }

        public void _MenuFps()
        {
            if (GetTree().GetScript() == null || OS.HasEnvironment("FB_MENU_FPS"))
                Engine.MaxFps = MENU_FPS;
        }

        public void _EndMatch()
        {
            var replay = "";
            var note = "";
            if (GD.IsInstanceValid(siege))
            {
                note = GD.Str(siege.exit_note);
                replay = GD.Str(siege.replay_hero);          // 0.31.164: PLAY AGAIN after a 5v5 -- a new match, with its own ticket
                siege.NoteLeaving();                     // 0.31.118: a VS BOTS match left before its end
                siege.QueueFree();
            }
            siege = null;
            if (eco_sync != null && eco_sync.enabled)
                eco_sync.Pull();                          // 0.31.108: the server's count of the match (online), or ours sent up
            if (analytics != null)
                analytics.NoteLevel((int)profile.d["level"]);
            CallDeferred(_MenuFps);                 // (after the match's _exit_tree puts back what it found)
            _SetMenuActive(true);
            ShowTab("home");
            if (play_games != null && (play_games as IGameServices).state == "ask")
                AskCloud();                              // 0.31.102: Google Play's question waited for the match to end
            else if (account_link != null && !account_link.PendingGc().IsEmpty())
                AskGc();                                 // 0.31.132: Game Center's question too
            if (update_required)
                ShowUpdateScreen();
            else if (server_updating)
                Toast(SERVER_UPDATING, UI.GOLD);
            else if (note == "tutorial_paid")
            {
                Toast(GD.Fmt("Training complete! +%d gold", TUTORIAL_GOLD), UI.GOLD);        // 0.31.181 (0.31.217: the training)
                Sfx("claim");
            }
            else if (note == "tutorial")
                Toast("Training complete!", UI.GOLD);
            else if (note == "idle")
                Notice("REMOVED FOR BEING IDLE", "You didn't move or attack for 3 minutes, so a bot took your place. Nothing was paid for that match.");
            else if (note == "no_five" && replay != "")
            {
                // 0.31.170: the server isn't on the online 5v5 yet -- the match against bots, as before
                server_five = 0;
                Toast("Online 5v5 isn't on the server yet -- a match against bots", UI.GOLD);
                StartMoba(replay);
            }
            else if (replay != "")
                StartMoba(replay);
        }

        // ---------------- Google Play's copy of the progress (0.31.102) ----------------
        public void AskCloud()
        {
            // Both this phone and Google Play have progress: the player picks. Nothing is replaced without this choice.
            GDict q = play_games != null ? (play_games as IGameServices).PendingChoice() : new GDict();
            if (q.IsEmpty())
                return;
            GDict here = q["here"].D;
            GDict cloud = q["cloud"].D;
            var when = "";
            if ((int)cloud.Get("at", 0) > 0)
            {
                var dt = Time.GetDatetimeDictFromUnixTime((int)cloud["at"]);
                when = GD.Fmt(" (%s %d)", GArray.Of("", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")[(int)dt["month"]], (int)dt["day"]);
            }
            var from = GD.Str(cloud.Get("device", ""));
            var body = GD.Fmt("Google Play has saved progress%s%s:\n%s\n\nThis phone:\n%s\n\nThe one you don't keep is replaced.",
                from != "" ? (" from " + from) : "", when, _CloudLine(cloud), _CloudLine(here));
            CloseModal();
            modal = new Control();
            modal.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            AddChild(modal);
            var dim = new ColorRect();
            dim.Color = new Color(0, 0, 0, 0.6);
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            modal.AddChild(dim);
            var center = new CenterContainer();
            center.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            modal.AddChild(center);
            var v = UI.Card(center);
            (v.GetParent() as Control).CustomMinimumSize = new Vector2(GD.Minf(360, Size.x - 32), 0);
            UI.Title(v, "WHICH PROGRESS?", 20);
            var b = UI.Label(v, body, 14, UI.MUTED);
            b.HorizontalAlignment = HorizontalAlignment.Center;
            UI.Button(v, "USE GOOGLE PLAY'S", "primary", () =>
            {
                CloseModal();
                (play_games as IGameServices).Choose(true);
            }, "cloud_use");
            UI.Button(v, "KEEP THIS PHONE'S", "secondary", () =>
            {
                CloseModal();
                (play_games as IGameServices).Choose(false);
            }, "cloud_keep");
        }

        public static string _CloudLine(GDict s)
        {
            var n = (int)s.Get("items", 0);
            return GD.Fmt("Level %d · %d wins · %d gold · %d gems · %d item%s", (int)s.Get("level", 1), (int)s.Get("wins", 0),
                (int)s.Get("gold", 0), (int)s.Get("gems", 0), n, n == 1 ? "" : "s");
        }

        // ---------------- the account between phones (0.31.132, the iOS port) ----------------
        public void _OnAccountSwitched()
        {
            // a transfer code, Game Center or a deletion changed the account: chat reconnects, the server's copy comes in
            if (social != null && GObject.HasMethod(social, "account_switched"))
                social.AccountSwitched();
            _OnCloudRestored();
        }

        public void _GcLink()
        {
            // iOS: the Game Center player linked to the account, so a reinstall gets it back (a few tries a run)
            if (account_link == null || play_games == null || !GObject.HasMethod(play_games, "identity") || !(play_games as IGameServices).SignedIn())
                return;
            if (!account_link.HasAccount() || account_link.busy != "" || _gc_tries >= 3 || siege != null)
                return;
            var team = GD.Str(GObject.Get(play_games, "team_id"));
            if (team == "" || account_link.gc_done == team || !account_link.PendingGc().IsEmpty())
                return;
            _gc_tries += 1;
            (play_games as GameCenter).Identity((Var d, Var e) =>
            {
                if (e.IsNull && d.D != null)                    // (e == null and d is Dictionary)
                    account_link.GameCenter(team, d.D);
            });
        }

        public VBoxContainer _ModalCard(string title_text)
        {
            CloseModal();
            modal = new Control();
            modal.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            AddChild(modal);
            var dim = new ColorRect();
            dim.Color = new Color(0, 0, 0, 0.6);
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            modal.AddChild(dim);
            var center = new CenterContainer();
            center.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            modal.AddChild(center);
            var v = UI.Card(center);
            (v.GetParent() as Control).CustomMinimumSize = new Vector2(GD.Minf(360, Size.x - 32), 0);
            UI.Title(v, title_text, 20);
            return v;
        }

        public Label _ModalText(Node v, string text)
        {
            var b = UI.Label(v, text, 14, UI.MUTED);
            b.HorizontalAlignment = HorizontalAlignment.Center;
            b.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            return b;
        }

        public void AskGc()
        {
            // Game Center's player has another account and this phone has progress of its own: the player picks
            GDict o = account_link != null ? account_link.PendingGc() : new GDict();
            if (o.IsEmpty())
                return;
            Sfx("menuOpen");
            var v = _ModalCard("WHICH PROGRESS?");
            _ModalText(v, GD.Fmt("Your Game Center player already has a Fatebound account:\n%s\n\nThis phone:\n%s\n\nUse that account here, or keep this phone's (Game Center then goes with it).",
                _CloudLine(o.Get("sum", new GDict()).D), _CloudLine(profile.Summary())));
            UI.Button(v, "USE THAT ACCOUNT", "primary", () =>
            {
                CloseModal();
                account_link.ChooseGc(true);
            }, "gc_use");
            UI.Button(v, "KEEP THIS PHONE'S", "secondary", () =>
            {
                CloseModal();
                var team = play_games != null ? GD.Str(GObject.Get(play_games, "team_id")) : "";
                account_link.ChooseGc(false);
                if (play_games != null && GObject.HasMethod(play_games, "identity"))
                {
                    (play_games as GameCenter).Identity((Var d, Var e) =>
                    {
                        if (e.IsNull && d.D != null)
                            account_link.GameCenterRelink(team, d.D);
                    });
                }
            }, "gc_keep");
        }

        public static string _LinkWhy(GDict a)
        {
            switch (GD.Str(a.Get("why", "")))
            {
                case "code":
                    return "That code isn't right, or it has run out. Make a new one on the other phone";
                case "busy":
                    return "Too many tries. Wait a few minutes and try again";
                case "old":
                    return "The server needs an update for this. Try again later";
                case "auth":
                    return "Your account isn't ready yet. Try again in a moment";
            }
            return "Couldn't reach the server. Check your connection";
        }

        public void ShowMoveCode()
        {
            // Settings > MOVE TO ANOTHER PHONE: a one-time code for the other phone (Android or iPhone)
            if (account_link == null || account_link.busy != "")
                return;
            account_link.NewCode((GDict a) =>
            {
                if (!(bool)a.Get("ok", false))
                {
                    Toast(_LinkWhy(a), UI.RED);
                    return;
                }
                var code = GD.Str(a["code"]);
                Sfx("menuOpen");
                var v = _ModalCard("MOVE TO ANOTHER PHONE");
                var cl = UI.Label(v, code.Left(4) + " " + code.Substr(4), 34, UI2.GOLD, UI.TITLE_FONT);
                cl.HorizontalAlignment = HorizontalAlignment.Center;
                cl.SetMeta("action_key", "move_code_text");
                _ModalText(v, GD.Fmt("On your other phone (Android or iPhone), open Settings > ACCOUNT > ENTER A CODE and type this within %d minutes. That phone then plays as this account, with all your progress and gems. The code works once.", (int)a.Get("ttl", 600) / 60));
                var r = UI.Row(v, 10);
                UI.Grow(UI.Button(r, "COPY", "secondary", () =>
                {
                    DisplayServer.ClipboardSet(code);
                    Toast("Code copied", UI.GOLD);
                }, "move_copy"));
                UI.Grow(UI.Button(r, "OK", "primary", () =>
                {
                    Sfx("menuClose");
                    CloseModal();
                }, "modal_ok"));
            });
        }

        public void EnterMoveCode()
        {
            // Settings > ENTER A CODE: this phone takes the account another phone made a code for
            Sfx("menuOpen");
            var v = _ModalCard("ENTER A CODE");
            _ModalText(v, "Type the code from your other phone (Settings > ACCOUNT > MOVE TO ANOTHER PHONE). This phone's progress is replaced by that account's.");
            var f = SocialUI.Field(v, "8-character code", 9);
            f.SetMeta("action_key", "move_code_field");
            var r = UI.Row(v, 10);
            UI.Grow(UI.Button(r, "CANCEL", "secondary", () =>
            {
                Sfx("menuClose");
                CloseModal();
            }, "modal_no"));
            Action go = () =>
            {
                var typed = f.Text;
                CloseModal();
                account_link.UseCode(typed, (GDict a) =>
                {
                    if ((bool)a.Get("ok", false))
                        Toast("This phone now plays as your account", UI.GOLD);
                    else
                        Toast(_LinkWhy(a), UI.RED);
                });
            };
            f.TextSubmitted += (string _t) => go();
            UI.Grow(UI.Button(r, "USE CODE", "primary", go, "move_use"));
        }

        public void AskDeleteAccount()
        {
            // Settings > DELETE ACCOUNT (App Store 5.1.1(v); Google Play's data deletion): twice asked, then gone for good
            Confirm("DELETE ACCOUNT?", "Your Fatebound account is deleted from our server for good: level, gold, gems, items, purchases, friends and leaderboard place. This phone starts again from the beginning.",
                "DELETE", "danger", () =>
                {
                    Confirm("ARE YOU SURE?", "This can't be undone. Gems and purchases on this account can't be brought back.", "DELETE FOREVER", "danger", () =>
                    {
                        account_link.DeleteAccount((GDict a) =>
                        {
                            if ((bool)a.Get("ok", false))
                                Notice("ACCOUNT DELETED", "Your account was deleted from our server. The game starts fresh on this phone.");
                            else
                                Toast(_LinkWhy(a), UI.RED);
                        });
                    });
                });
        }

        public void _OnCloudRestored()
        {
            // the profile was replaced: everything shown from it is redrawn (the counters just change: nothing was earned)
            if (eco_sync != null)
                eco_sync.AccountSwitched();              // 0.31.108: (and with it, maybe, the account on the server)
            _ApplyAudio();
            HeroShow();
            if (siege == null)
            {
                quiet_top = true;
                Rebuild();
                quiet_top = false;
            }
        }

        // ---------------- forced update ----------------
        public const string SERVER_UPDATING = "Servers are updating, try again in a few minutes";

        public void CheckServerVersion()
        {
            // Ask the server which protocol it speaks (no match is joined). One at a time.
            if (GD.IsInstanceValid(_version_checker))
                return;
            _version_checked_at = Time.GetTicksMsec() / 1000.0;
            _version_checker = new VersionCheck();
            _version_checker.url = version_check_url;
            _version_checker.Done += _OnServerVersion;
            _version_checker.Answered += (GDict m) =>
            {
                server_five = (int)m.Get("five", 0) >= Net.FIVE ? 1 : 0;
                server_min_build = GD.Str(m.Get("min_build", ""));
                if (analytics != null)
                    analytics.server_ok = (int)m.Get("an", 0) == 1;
            };
            AddChild(_version_checker);
        }

        public void _OnServerVersion(int server_v)
        {
            _version_checker = null;
            if (analytics != null)
                analytics.SetNet(server_v >= 0);
            if (server_v == Net.VERSION && Net.BuildTooOld(Diag.BUILD, server_min_build))
            {
                // 0.31.209 (Kevin: "if there's an update, the message will post right when player launches game instead of having
                // to enter a match"): the same protocol, but this build is older than the server's minimum ("ver" says it). The
                // server turns such an app away only at its hello, as if it were one protocol ahead -- the same verdict, now.
                GD.Print(GD.Fmt("VERSION_CHECK build %s older than the server's minimum %s", Diag.BUILD, server_min_build));
                server_v = Net.VERSION + 1;
            }
            ApplyServerVersion(server_v);
        }

        public void ApplyServerVersion(int server_v)
        {
            string verdict = Net.VersionVerdict(server_v);
            GD.Print(GD.Fmt("VERSION_CHECK server=%d client=%d -> %s", server_v, Net.VERSION, verdict));
            switch (verdict)
            {
                case "update":
                    server_version = server_v;
                    update_required = true;
                    server_updating = false;
                    if (siege == null)              // an offline match in progress gets it when it ends (_end_match)
                        ShowUpdateScreen();
                    break;
                case "server_old":
                    server_version = server_v;
                    server_updating = true;
                    break;
                case "ok":
                    // Same protocol (e.g. the server was rolled back): unlock.
                    server_version = server_v;
                    server_updating = false;
                    if (update_required)
                    {
                        update_required = false;
                        HideUpdateScreen();
                        if (siege == null)
                            Rebuild();
                    }
                    break;
                default:
                    break;                           // unknown: offline or an older server; the connect path still checks
            }
        }

        public void _OnVersionMismatch(int server_v, string verdict)
        {
            // A refused connect (siege_mode). "update": straight to the Update screen. "server_old": siege_mode shows the
            // message and comes home by itself; Home repeats it (_end_match).
            server_version = server_v;
            if (verdict == "update")
            {
                update_required = true;
                server_updating = false;
                CallDeferred(_EndMatch);
            }
            else
                server_updating = true;
        }

        public void ShowUpdateScreen()
        {
            if (GD.IsInstanceValid(update_screen))
            {
                MoveChild(update_screen, GetChildCount() - 1);
                update_screen.Visible = true;
                return;
            }
            update_screen = new UpdateScreen();
            update_screen.server_version = server_version;
            if (analytics != null)
                analytics.LogEv("update_screen", new GDict { { "from_build", Diag.BUILD }, { "need", server_version } });
            update_screen.open_url = open_url;
            update_screen.OfflineRequested += () =>
            {
                // 0.31.84 merge: Home has no VS BOTS mode any more (one PLAY, always online), so this starts the offline
                // match itself; the Update screen comes back when it ends (_end_match).
                HideUpdateScreen();
                StartMatch(false);
                Toast("Offline vs bots. Update the game to play online.", UI.GOLD);
            };
            AddChild(update_screen);              // last child: over the menus, the toast and any match
        }

        public void HideUpdateScreen()
        {
            if (GD.IsInstanceValid(update_screen))
                update_screen.QueueFree();
            update_screen = null;
        }

        public void _OnIapGranted(string product, GDict g)
        {
            // 0.31.90: a confirmed purchase landed in the profile
            if ((bool)g.Get("again", false))
                return;
            if (heycatch != null)
                heycatch.Capture("purchase_completed", new GDict { { "product", product } });      // 0.31.212: a business outcome (HeyCatch only)
            Sfx((int)g.Get("gems", 0) > 0 ? "gemPack" : "purchase");       // 0.31.110: gems pouring out
            var bits = new List<string> { GD.Fmt("+%s gems", UI.Compact((int)g.Get("gems", 0))) };
            if ((int)g.Get("gold", 0) > 0)
                bits.Add(GD.Fmt("+%s gold", UI.Grouped((int)g["gold"])));
            if ((int)g.Get("token", 0) > 0)
                bits.Add("a Hero Token");                  // 0.31.188: the starter pack's (it held a weapon)
            Toast(string.Join("  ·  ", bits), UI.GOLD);
            Rebuild();
        }

        protected override void _ExitTree()
        {
            Assets.Drain();                             // 0.31.141: no script left compiling on a thread as the app closes
        }

        public override void _Notification(int what)
        {
            if (what == NOTIFICATION_WM_GO_BACK_REQUEST)
            {
                if (GD.IsInstanceValid(update_screen))
                    GetTree().Quit();              // the Update screen can't be backed out of into the game
                else if (GD.IsInstanceValid(modal))
                    CloseModal();
                else if (GD.IsInstanceValid(siege))
                    siege.RequestLeave();
                else if (tab != "home")
                    ShowTab("home");
                else
                {
                    if (analytics != null)
                        analytics.EndSession();
                    GetTree().Quit();
                }
            }
            else if (what == NOTIFICATION_WM_CLOSE_REQUEST)
            {
                if (analytics != null)
                    analytics.EndSession();                // (desktop: the window closed)
                GetTree().Quit();
            }
            else if (what == NOTIFICATION_APPLICATION_PAUSED)
            {
                if (analytics != null)
                    analytics.EndSession();                // 0.31.118: a session is a time in the foreground
                if (heycatch != null)
                    heycatch.Flush();                       // 0.31.212: (session_end with it)
                if (notify != null && profile != null)
                    notify.OnBackground(profile);          // 0.31.119: a chest that finishes while we're away says so
                if (audio != null)                         // (and audio.has_method("stop"): NativeAudio's)
                    audio.Stop();
                if (social != null)
                    social.SetActive(false);               // 0.31.111: back when the app is
                if (play_games != null)
                    (play_games as IGameServices).OnPause();                  // 0.31.102: the latest progress up to Google Play
                if (online_status != null)
                    online_status.SetActive(false);
            }
            else if (what == NOTIFICATION_APPLICATION_RESUMED)
            {
                if (notify != null)
                    notify.OnForeground();                 // 0.31.119: back in the game -- the chests show themselves
                if (analytics != null)
                    analytics.BeginSession(false, false, GD.Str(analytics.meta.Get("net", "")));
                if (eco_sync != null && eco_sync.auto_start)
                    eco_sync.Start();                   // 0.31.108: the account as the server has it
                if (social != null && social_autostart)
                    social.SetActive(true);
                if (billing != null)
                    (billing as IStoreBilling).Resume();                   // a purchase finished while we were away (or a pending one cleared)
                if (play_games != null)
                    (play_games as IGameServices).OnResume();
                if (online_status != null)
                    online_status.SetActive(tab == "home" && siege == null);
                if (version_check && siege == null && Time.GetTicksMsec() / 1000.0 - _version_checked_at > RECHECK_AFTER)
                {
                    // 0.31.91: deferred -- this notification is propagated through the tree, and add_child during it fails
                    // ("Parent node is busy setting up children" in Kevin's log), leaving a checker that blocked every later check.
                    CallDeferred(CheckServerVersion);   // back from the Play Store (or a long pause): ask again
                }
            }
        }

        // ---------------- chat, friends, the party (0.31.111) ----------------
        public void OpenChat(string ch = "global", string back = "")
        {
            // back "clan" (0.31.197: the clan camp's CHAT): closing the chat goes back to the camp
            if (social == null)
                return;
            CloseModal();
            var m = new ChatPanel();
            m.back = back;
            AddChild(m);
            modal = m;
            m.Open(this, ch);
        }

        public void OpenOrders()
        {
            CloseModal();
            var m = new OrdersPanel();
            AddChild(m);
            modal = m;
            m.Open(this);
        }

        public void ChestStarted()
        {
            // 0.31.119: a chest started unlocking -- the first time, ask whether they'd like a notification when it's ready
            // (our question first; Android's own dialog only on YES, so a NO here doesn't use up Android's two asks)
            if (notify == null || !notify.ShouldAsk(profile))
                return;
            profile.d["settings"].D["notify_asked"] = true;
            profile.Save();
            Confirm("CHEST NOTIFICATIONS", "Want a notification when your chest is ready to open? You can change this in Settings.",
                "YES", "primary", () =>
                {
                    notify.RequestPermission();
                },
                () =>
                {
                    profile.d["settings"].D["notify"] = false;
                    profile.Save();
                });
        }

        public void OpenStarter()
        {
            // 0.31.214: the Starter Pack's window (Home's offer card)
            CloseModal();
            var m = new StarterOffer();
            AddChild(m);
            modal = m;
            m.Open(this);
            if (heycatch != null)
                heycatch.Screen("starter_offer");
        }

        public void OpenDaily()
        {
            // 0.31.119: the DAILY REWARD card
            CloseModal();
            var m = new DailyReward();
            AddChild(m);
            modal = m;
            m.Open(this);
        }

        // 0.31.119: the daily reward opens by itself on Home the first time each day a claim waits (not in tests or screenshot
        // tools, which set daily_auto when they want it)
        public bool daily_auto = DisplayServer.GetName() != "headless" && !OS.HasEnvironment("SHOT_DIR");
        public string _daily_offered = "";

        public bool OfferPrize()
        {
            // 0.31.120: a weekly leaderboard prize the server paid since we last said so -- once
            if (!daily_auto || siege != null || update_required || tab != "home" || GD.IsInstanceValid(modal))
                return false;
            GArray pz = profile.d.Get("prizes", new GArray()).A;
            if (pz.IsEmpty() || GD.Str(pz[0].Get("week", "")) == GD.Str(profile.d["settings"].Get("prize_seen", "")))
                return false;
            GDict x = pz[0].D;
            profile.d["settings"].D["prize_seen"] = GD.Str(x["week"]);
            profile.Save();
            var bits = new List<string> { GD.Fmt("%d gems", (int)x.Get("gems", 0)) };
            if (GD.Str(x.Get("chest", "")) != "")
                bits.Add(GD.Fmt("a %s", GD.Str(Eco.CHESTS[GD.Str(x["chest"])]["name"])));
            var t = GD.Str(x.Get("title", ""));
            if (t != "" && Net.TITLES.Has(t))
                bits.Add(GD.Fmt("the title \"%s\" (wear it from the Armory)", GD.Str(Net.TITLES[t][0])));
            Sfx("confirm");
            Notice("LEADERBOARD PRIZE", GD.Fmt("You finished #%d on last week's leaderboard! You got %s.", (int)x.Get("rank", 0), string.Join(", ", bits)));
            return true;
        }

        public bool OfferClanReward()
        {
            // 0.31.196: a week's Clan Chest and League gems the server paid since we last said so -- once
            if (!daily_auto || siege != null || update_required || tab != "home" || GD.IsInstanceValid(modal))
                return false;
            GArray cr = profile.d.Get("clan_rewards", new GArray()).A;
            if (cr.IsEmpty() || GD.Str(cr[0].Get("week", "")) == GD.Str(profile.d["settings"].Get("clan_reward_seen", "")))
                return false;
            GDict x = cr[0].D;
            profile.d["settings"].D["clan_reward_seen"] = GD.Str(x["week"]);
            profile.Save();
            Sfx("confirm");
            Notice("CLAN REWARDS", ClanRewardText(x));
            return true;
        }

        public static string ClanRewardText(GDict x)
        {
            var bits = new List<string>();
            if (GD.Str(x.Get("chest", "")) != "")
                bits.Add(GD.Fmt("the %s", GD.Str(Eco.CHESTS.Get(GD.Str(x["chest"]), new GDict()).Get("name", "Chest"))));
            if ((int)x.Get("gems", 0) > 0)
                bits.Add(GD.Fmt("%d gems", (int)x["gems"]));
            var place = (int)x.Get("rank", 0) > 0 ? GD.Fmt(" and finished #%d in the Clan League", (int)x["rank"]) : "";
            return GD.Fmt("[%s] %s scored %d points last week%s! You got %s.%s", GD.Str(x.Get("tag", "")), GD.Str(x.Get("clan", "Your clan")),
                (int)x.Get("pts", 0), place, bits.Count != 0 ? string.Join(" and ", bits) : "nothing this time",
                GD.Str(x.Get("chest", "")) != "" ? "\nOpen the chest from your chest slots." : "");
        }

        public bool OfferReferral()
        {
            // 0.31.120: Gold chests from a referral (server/referrals.gd) since we last said so
            if (!daily_auto || siege != null || update_required || tab != "home" || GD.IsInstanceValid(modal))
                return false;
            var seen = (int)profile.d["settings"].Get("ref_seen", 0);
            GArray fresh = profile.d.Get("referral", new GDict()).Get("notes", new GArray()).A.Filter((Var n) => (int)n.Get("at", 0) > seen);
            if (fresh.IsEmpty())
                return false;
            profile.d["settings"].D["ref_seen"] = (int)fresh[0].Get("at", 0);
            profile.Save();
            Sfx("confirm");
            Notice("FRIEND REWARD", ReferralText(fresh));
            return true;
        }

        public static string ReferralText(GArray fresh)
        {
            var lines = new List<string>();
            foreach (var n in fresh)
            {
                if (GD.Str(n.Get("kind", "")) == "joined")
                    lines.Add(GD.Fmt("You reached level %d with %s's code: a Gold Chest for you!", Eco.REF_LEVEL, GD.Str(n.Get("name", "a friend"))));
                else
                    lines.Add(GD.Fmt("%s reached level %d with your code: a Gold Chest for you!", GD.Str(n.Get("name", "A friend")), Eco.REF_LEVEL));
            }
            if (lines.Count > 3)
                return GD.Fmt("%d friend rewards: %d Gold Chests! Open them from your chest slots.", lines.Count, lines.Count);
            return string.Join("\n", lines) + "\nOpen it from your chest slots.";
        }

        public void RedeemCode(string code, Action<GDict> cb = null)
        {
            // 0.31.120 (Kevin: referral codes): a new player enters the code of the friend who invited them -- the server checks
            // it (server/referrals.gd) and answers {"t":"ref", "ok", "why", "name"}
            var acct = GD.Str(profile.d["account"].Get("id", ""));
            var key = GD.Str(profile.d["account"].Get("key", ""));
            if (acct == "" || key == "")
            {
                Sfx("error");
                Toast("Play one online match first, then enter the code", UI.MUTED);
                return;
            }
            LbFetch.Ask(this, GD.Str(eco_url), new GDict { { "t", "ref" }, { "acct", acct }, { "key", key }, { "code", code } }, (GDict r) =>
            {
                if (r.IsEmpty())
                {
                    Sfx("error");
                    Toast("Not connected to the server right now", UI.RED);
                }
                else if ((bool)r.Get("ok", false))
                {
                    Sfx("confirm");
                    profile.d["referral"].D["by"] = GD.Str(r.Get("name", "a friend"));
                    profile.Save();
                    if (eco_sync != null)
                        eco_sync.Pull();
                    Toast(GD.Fmt("Code accepted! Reach level %d and you both get a Gold Chest", Eco.REF_LEVEL), UI.CYAN);
                }
                else
                {
                    Sfx("error");
                    var why = GD.Str(r.Get("why", ""));
                    if (why == "late")
                    {
                        profile.d["settings"].D["ref_late"] = true;
                        profile.Save();
                    }
                    Toast(GD.Str(new GDict { { "code", "No player has that code" }, { "self", "That's your own code" }, { "done", "You've already entered a friend's code" },
                        { "loop", "That friend joined with your code" }, { "late", GD.Fmt("Codes are for new players (first %d days, under level %d)", Eco.REF_DAYS, Eco.REF_LEVEL) },
                        { "auth", "Play one online match first, then enter the code" } }.Get(why, "The server didn't take that code")), UI.RED);
                }
                if (GD.IsInstanceValid(modal) && GObject.HasMethod(modal, "ref_changed"))
                    GObject.Call(modal, "ref_changed");
                if (cb != null)
                    cb(r);
            });
        }

        // ---------------- SEND TO DEVELOPER (0.31.120) ----------------
        public static GDict DiagMessage(string note, string log_text, Profile p)
        {
            // the report (server/diag_reports.gd), fitted under one packet once compressed: the log's first lines (the session
            // header) and as much of its end as fits
            var msg = new GDict { { "t", "diag" }, { "name", GD.Str(p.d.Get("name", "")) }, { "build", Diag.BUILD }, { "note", note.StripEdges().Left(500) },
                { "dev", new GDict { { "model", OS.GetModelName() }, { "os", GD.Fmt("%s %s", OS.GetName(), OS.GetVersion()) }, { "gpu", RenderingServer.GetVideoAdapterName() } } },
                { "log", log_text } };
            var acct = GD.Str(p.d["account"].Get("id", ""));
            if (acct != "")
            {
                msg["acct"] = acct;
                msg["key"] = GD.Str(p.d["account"].Get("key", ""));
            }
            var keep = GD.Mini(GStr.Length(log_text), 390000);
            if (keep < GStr.Length(log_text))
                msg["log"] = log_text.Left(3000) + GD.Fmt("\n[... %d characters left out ...]\n", GStr.Length(log_text) - keep) + log_text.Right(keep - 3000);
            while (Net.Encode(msg, true).Length > Net.MAX_PACKET - 2048 && keep > 4000)
            {
                keep = (int)(keep * 0.7);
                msg["log"] = log_text.Left(3000) + GD.Fmt("\n[... %d characters left out ...]\n", GStr.Length(log_text) - keep) + log_text.Right(keep - 3000);
            }
            return msg;
        }

        public void SendDiagnostics(string note, Action<GDict> cb)
        {
            // cb({"ok", "id"} / {"ok": false, "why"} / {} with no answer)
            LbFetch.Ask(this, GD.Str(eco_url), DiagMessage(note, Diag.ReadLogs(200), profile), cb, true);
        }

        public void OpenSendDiag()
        {
            // Settings > SEND TO DEVELOPER: what's sent, a line about the problem, SEND -- asked every time
            Sfx("menuOpen");
            CloseModal();
            modal = new Control();
            modal.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            AddChild(modal);
            var dim = new ColorRect();
            dim.Color = new Color(0, 0, 0, 0.6);
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            modal.AddChild(dim);
            var center = new CenterContainer();
            center.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            modal.AddChild(center);
            var v = UI2.Frame(center, "royal", 14, 20.0, "gold");
            (v.GetParent() as Control).CustomMinimumSize = new Vector2(GD.Minf(360, Size.x - 32), 0);
            v.AddThemeConstantOverride("separation", 10);
            UI2.Center(UI2.Text(v, "SEND TO DEVELOPER", 22, UI2.GOLD));
            UI2.Body(v, "Sends this phone's game log to the developer to fix a problem: what the game was doing, its errors, your " +
                "phone model and the game's version, with your player name. No chats, purchases or other apps.", 13, UI2.SOFT);
            var note = SocialUI.Field(v, "What went wrong? (optional)", 300);
            note.Name = "DiagNote";
            var r = UI.Row(v, 10);
            UI.Grow(UI2.Button(r, "CANCEL", "ghost", () =>
            {
                Sfx("menuClose");
                CloseModal();
            }, "diag_cancel", 15, 44.0));
            var send = UI2.Button(r, "SEND", "orange", () => { }, "diag_send", 17, 44.0);
            UI.Grow(send);
            var m = modal;
            send.Pressed += () =>
            {
                if (send.HasMeta("busy"))
                    return;
                send.SetMeta("busy", true);
                send.Text = "SENDING...";
                UI2.DimButton(send, true);
                Sfx("tap");
                SendDiagnostics(note.Text, (GDict res) =>
                {
                    if ((bool)res.Get("ok", false))
                    {
                        Sfx("confirm");
                        if (modal == m)
                            CloseModal();
                        Toast(GD.Fmt("Sent -- report #%s. Thank you!", GD.Str(res.Get("id", ""))), UI.CYAN);
                        return;
                    }
                    Sfx("error");
                    if (GD.Str(res.Get("why", "")) == "busy")
                        Toast("You've sent a few already -- try again in an hour", UI.MUTED);
                    else
                        Toast("Couldn't reach the server -- try again, or use COPY DIAGNOSTICS", UI.RED);
                    if (GD.IsInstanceValid(send))
                    {
                        send.RemoveMeta("busy");
                        send.Text = "SEND";
                        UI2.DimButton(send, false);
                    }
                });
            };
        }

        // 0.31.198 (Kevin, with the server wiped so everyone starts fresh: "Have the game ask their name and after they do that
        // it'll briefly say what game is and then ask if they would like to play tutorial. Make the tutorial guy pop up while
        // doing this and voice it ..."; "Also have him briefly take player through menus"): the Royal Herald's welcome
        // (herald_intro.gd) on Home, before anything else, for a player with no name yet -- Profile's "Player": a new install,
        // or anyone once the wiped server has made them a new account. Not in tests or screenshot tools, which call
        // open_intro or set intro_auto.
        public bool intro_auto = DisplayServer.GetName() != "headless" && !OS.HasEnvironment("SHOT_DIR");

        public bool NeedsIntro()
        {
            return profile != null && GD.Str(profile.d.Get("name", "")) == "Player";
        }

        public bool OfferIntro()
        {
            if (!intro_auto || siege != null || update_required || tab != "home" || GD.IsInstanceValid(modal))
                return false;
            if (!NeedsIntro())
                return false;
            OpenIntro();
            return true;
        }

        public void OpenIntro()
        {
            CloseModal();
            var m = new HeraldIntro();
            AddChild(m);
            modal = m;
            m.Open(this);
        }

        public void OfferDaily()
        {
            if (OfferIntro() || OfferPrize() || OfferClanReward() || OfferReferral())
                return;
            if (!daily_auto || siege != null || update_required || tab != "home" || GD.IsInstanceValid(modal))
                return;
            if (!profile.LoginReady())                  // (0.31.164: no tutorial to finish first any more)
                return;
            var today = Eco.DayKey(profile.Now());
            if (_daily_offered == today)
                return;
            _daily_offered = today;
            OpenDaily();
        }

        public void OpenLeaderboard()
        {
            // 0.31.119: the week's leaderboard (RANKS on Home)
            CloseModal();
            var m = new LeaderboardPanel();
            AddChild(m);
            modal = m;
            m.Open(this);
        }

        public void OpenFriends()
        {
            if (social == null)
                return;
            CloseModal();
            social_tab = "friends";
            var m = new FriendsPanel();
            AddChild(m);
            modal = m;
            m.Open(this);
        }

        public void OpenClan(string focus = "")
        {
            // 0.31.134: the CLAN window, beside FRIENDS. Focus "join": not in a clan, it opens on joining -- the clans to join,
            // START MY OWN CLAN
            if (social == null)
                return;
            CloseModal();
            social_tab = "clan";
            var m = new ClanPanel();
            AddChild(m);
            modal = m;
            m.Open(this, focus);
        }

        public void OpenSocial(string which = "")
        {
            // the ALLIANCE tab (0.31.134-0.31.138: Home's SOCIAL medallion): FRIENDS or CLAN (the last one open, unless something
            // waits in the other)
            if (which == "" && social != null && social.Online())
            {
                int fr = social.rin.Size() + social.invites.Size();
                int cl = social.clan_inv.Size() + (social.IsClanOfficer() ? social.ClanRequests() : 0);
                which = fr > 0 && cl == 0 ? "friends" : (cl > 0 && fr == 0 ? "clan" : social_tab);
            }
            if (which == "clan")
                OpenClan();
            else
                OpenFriends();
        }

        public void ClanFounded()
        {
            // the server took the clan's gold: fetch the account as it stands now
            if (eco_sync != null)
                eco_sync.Pull();
            Toast("Your clan is founded!", UI.GOLD);
        }

        public void _OnClanInvited(GDict c, GDict by)
        {
            if (siege != null)
                return;                               // (it waits in CLAN)
            Sfx("chatPop");
            Toast(GD.Fmt("%s invited you to [%s] %s -- see ALLIANCE", GD.Str(by.Get("n", "Someone")), GD.Str(c.Get("tag", "")), GD.Str(c.Get("name", ""))), UI.CYAN);
        }

        public void _OnSocialNote(string t, bool bad, bool pop)
        {
            if (siege != null)
                return;
            if (pop)
                Sfx("chatPop");
            Toast(t, bad ? UI.RED : UI.GOLD);
        }

        public void _OnFriendRequest(GDict card)
        {
            if (siege != null)
                return;
            Sfx("chatPop");
            Toast(GD.Fmt("%s wants to be friends -- see Friends", GD.Str(card.Get("n", "Someone"))), UI.CYAN);
        }

        public void _OnPartyInvite(string pa, GDict card)
        {
            if (siege != null)
                return;                               // (it waits in Friends)
            Sfx("chatPop");
            if (GD.IsInstanceValid(_invite_banner))
                _invite_banner.QueueFree();
            _invite_banner = new InviteBanner();
            AddChild(_invite_banner);
            _invite_banner.ShowInvite(this, pa, card, safe_top + TOP_H + 14.0);
        }

        public void _OnPartyGo(string _pa, string by)
        {
            // the party leader pressed PLAY: everyone in the menu follows
            if (siege != null || update_required || GD.IsInstanceValid(update_screen) || !ONLINE_MATCHES)
                return;
            CloseModal();
            Toast(GD.Fmt("%s is heading into battle -- your party follows!", by), UI.GOLD);
            StartOnlineMoba(SavedHero(), true);            // 0.31.170: as your last pick
        }

        public string SocialSig()
        {
            if (social == null || !social.Online())
                return "off";
            var names = new List<string>();
            foreach (var m in social.party.Get("members", new GArray()).A)
                names.Add(GD.Str(m["pid"]) + GD.Str(m["n"]));
            return GD.Fmt("%d|%s|%s|%s", social.Attention(), GD.Str(social.party.Get("leader", "")), string.Join(",", names), social.MyTag());
        }

        public void _OnSocialChanged(string what)
        {
            if (what == "me")
                _social_name = GD.Str(profile.d["name"]);
            PaintAlliance();
            if (siege != null || !(what == "friends" || what == "party" || what == "state" || what == "clan"))
                return;
            _SocialHome();
        }

        public void _SocialHome()
        {
            // Home shows the Friends badge and the party: redraw it when they change (not under a window: when it closes)
            var sig = SocialSig();
            if (sig != _social_sig && tab == "home" && !GD.IsInstanceValid(modal) && siege == null)
            {
                _social_sig = sig;
                Rebuild();
            }
        }
    }
}
