// Ported from godot/scripts/siege/training.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    using Sim = Fatebound.Sim.SiegeSim;
    using Eco = Fatebound.Game.Economy;

    // 0.31.217 THE TRAINING (Kevin, with a recording of Honor of Kings' two training matches: "Here is how I want the
    // training to go in fatebound. The helper will be another character and voiced by the herald." The helper: the
    // Dragoon). Kael Wyrmlance, the Dragoon ("Last Rider of Skyreach"), fights at your side and talks you through it in the
    // Herald's voice (assets/vo/training/<id>.ogg; art_sources/training/script.json -- LINES here, word for word).
    // As Honor of Kings' own: his line in a bar at the top (his portrait, the key words lit) while the match runs on; the
    // task in a box at the top right (TUTORIAL 1/5 ...); his quips in a bubble over his head ("Well done!"); a hand on what
    // to tap; a dotted path to where to go.
    //  TRAINING 1, THE BASICS -- a quiet Rift (every other hero at his fountain, no waves or camps of their own; KAEL'S
    //   BLESSING: you take half damage and can't fall): follow him down the middle lane; a wave of their minions; a skill
    //   learnt with the +; an enemy hero; level 2 and the second skill; two heroes at once; level 3 and a skill made
    //   stronger; level 4, the ultimate, and three heroes to use it on; the quick-buy; then the challenges -- their outer
    //   tower (our minions first: its ring yellow, red when it's on you), the high ground (our army takes the inner one on
    //   the way), the King. VICTORY.
    //  TRAINING 2, 5V5 BATTLE -- a real match against bots with Kael beside you (you take a quarter less damage; their
    //   heroes hit softer): the map first, the match waiting (the lanes, the minions, the towers, how it's won, which heroes
    //   go where); he takes you to your hero's lane; then missions 1/4 to 4/4 (an outer, an inner and a high ground tower,
    //   the King), the towers' lesson the first time you're by one (the match waits), HOME when you're hurt, the quick-buy
    //   when you can afford it, the King when he's open.
    // Either one done: the training's gold, once (siege_mode.finish_tutorial -> Profile.finish_tutorial); no match rewards.
    public class Training : Control
    {
        public const string VO_DIR = "res://assets/vo/training/";
        public const string PORTRAIT = "res://assets/ui/skins/default_dragoon.png";
        public const string KAEL_HID = "dragoon";
        public const string KAEL_NAME = "Kael";
        public const double VOICE_GAIN = 0.55;          // x master (as the tutorial's Herald)
        public const double TYPE_CPS = 40.0;
        public const double HP_FLOOR = 0.3;             // training 1: you (and Kael) can't fall
        public const double TAKE = 0.5;                 // ...and take half damage
        public const double TAKE2 = 0.25;               // training 2: a quarter less
        public const double SOFT = 0.5;                 // training 1: Kael's and the enemy heroes' hits (m_out)
        public const double SOFT2 = 0.8;                // training 2: the enemy heroes'
        public const double FOE_HP = 0.5;               // training 1: an enemy hero put in front of you comes at half health
        public const double TOWER_LEFT = 0.55;          // training 1: their towers at this much health when you get there
        public const double KING_LEFT = 0.25;           // ...and their King
        public static readonly Vector2 P_START = new Vector2(2.0, 40.0);        // (blue's; red's the point mirror) you and Kael, behind our outer tower
        public static readonly Vector2 P_MOVE = new Vector2(0.0, 14.0);         // the first walk's end: out of our tower's reach (it's at (4, 30), 11.5 m)
        public static readonly Vector2 P_WAVE = new Vector2(0.0, -4.0);         // their wave put down here, walking at you
        public static readonly List<string> WAVE = new List<string> { "melee", "melee", "melee", "caster", "caster", "caster" };
        public static readonly List<string> ARMY = new List<string> { "melee", "melee", "melee", "melee", "caster", "caster" };
        public static readonly Color GOLD = Color.FromCode("#ffd257");
        public static readonly Color INK = new Color(0.08, 0.05, 0.02, 0.9);
        public const string KEY_INK = "#ffd65a";
        // the words lit in his lines (longest first)
        public static readonly GArray KEYS = GArray.Of("skill point", "high ground", "ATTACK", "HOME", "plus", "skills", "skill", "ultimate", "minions", "minion",
            "gold", "towers", "tower", "King", "level", "ring", "yellow", "red", "green", "lanes", "lane", "jungle", "item", "Victory!");

        public static readonly GDict LINES = new GDict
        {
            { "k1_hello", "Kael Wyrmlance, at your service. Stay close, and I'll show you how we fight." },
            { "k1_trouble", "There's trouble at the front. Come on!" },
            { "k1_controls", "Your left thumb moves you. Your right thumb fights." },
            { "k1_follow", "Follow me!" },
            { "k1_minions", "Enemy minions! Tap ATTACK to strike. Keep moving while you fight." },
            { "k1_gold", "Finish a minion, and its gold is yours." },
            { "k1_learn", "Every level gives you a skill point. Tap the plus to learn your first skill." },
            { "k1_enemy", "An enemy hero! Red health bars are enemies. Hit him with your skill!" },
            { "k1_level", "You've levelled up. Time to learn your second skill." },
            { "k1_combo", "Two of them! Use one skill, then the other. Quick as you can!" },
            { "k1_upgrade", "Another level. Put the point on a skill you know, to make it stronger." },
            { "k1_ult", "Level four. Your ultimate is ready to learn. It's your strongest move." },
            { "k1_ult_use", "Here they come. Hit them with your ultimate!" },
            { "k1_ult_done", "Not bad! I'll have to watch out for you." },
            { "k1_shop", "You've earned some gold. Tap the item on the left to buy it, right here." },
            { "k1_shop_done", "Better gear, harder hits." },
            { "k1_towers", "Now we break their towers. Three in a lane, then their King. Defeat him, and we win!" },
            { "k1_tower", "Let our minions walk in first. A tower shoots the first one in its range." },
            { "k1_tower_red", "Its ring is red. It's aiming at you. Step back!" },
            { "k1_tower_down", "Tower down! Our army's taken their inner tower too. On to the high ground!" },
            { "k1_king_open", "The lane is broken. Their King is open. Charge!" },
            { "k1_king_slam", "He hits hard. Stay with the minions!" },
            { "k1_victory", "Victory! You're a natural." },
            { "b_well_done", "Well done!" },
            { "b_on_fire", "Wow, you're on fire!" },
            { "b_watch_out", "Watch out!" },
            { "b_nice", "Nice!" },
            { "b_natural", "You're a natural!" },
            { "b_brb", "Be right back!" },
            { "b_over_here", "Over here!" },
            { "k2_welcome", "Welcome to the Rift. This time it's a real battle. Five against five." },
            { "k2_lanes", "The Rift has three lanes." },
            { "k2_minions", "Minions march down every lane." },
            { "k2_towers", "Each side has three towers in every lane." },
            { "k2_win1", "Break all three towers in one lane," },
            { "k2_win2", "and their King is open. Defeat him to win!" },
            { "k2_roles", "Each lane suits different heroes." },
            { "k2_top", "The top lane suits fighters and tanks." },
            { "k2_mid", "The middle lane suits mages." },
            { "k2_bot", "The bottom lane suits marksmen and supports." },
            { "k2_jungle", "Assassins hunt in the jungle, between the lanes." },
            { "k2_ready", "Get ready. We're heading into battle!" },
            { "k2_go_top", "To the top lane. Follow me!" },
            { "k2_go_mid", "To the middle lane. Follow me!" },
            { "k2_go_bot", "To the bottom lane. Follow me!" },
            { "k2_go_jungle", "To the jungle. Follow me!" },
            { "k2_tw1", "Towers hit hard. Here's how they work." },
            { "k2_tw2", "Near an enemy tower, its ring turns yellow." },
            { "k2_tw3", "When it aims at you, the ring turns red." },
            { "k2_tw4", "A tower shoots the first one to walk into its range." },
            { "k2_tw5", "So let a minion walk in first." },
            { "k2_tw6", "When the ring turns green, it's safe to attack." },
            { "k2_tw7", "Hit an enemy hero under his tower, and the tower turns on you." },
            { "k2_recall", "You're hurt. Tap HOME to go back and heal." },
            { "k2_shop", "You've got the gold for that item. Tap it on the left." },
            { "k2_king", "Their King hits incredibly hard. Don't stand in his slam!" },
            { "k2_victory", "Victory! You're ready for the real thing." },
            { "k2_defeat", "We'll get them next time." },
        };

        // Each step: its id, the box's heading and task, the lines that start it ("say") and end it ("after", before the next's),
        // Kael's quip in his bubble when it's done ("bubble")
        public static readonly GArray K1 = GArray.Of(
            GDict.Of("id", "move", "head", "TUTORIAL 1/5", "task", "Follow Kael down the lane", "say", GArray.Of("k1_hello", "k1_trouble", "k1_controls", "k1_follow")),
            GDict.Of("id", "minions", "head", "TUTORIAL 2/5", "task", "Defeat the enemy minions", "say", GArray.Of("k1_minions"), "bubble", "b_well_done"),
            GDict.Of("id", "learn", "head", "TUTORIAL 3/5", "task", "Tap the + to learn a skill", "say", GArray.Of("k1_learn")),
            GDict.Of("id", "hero", "head", "TUTORIAL 3/5", "task", "Defeat the enemy hero with your skill", "say", GArray.Of("k1_enemy"), "bubble", "b_on_fire"),
            GDict.Of("id", "learn2", "head", "TUTORIAL 4/5", "task", "Learn your second skill", "say", GArray.Of("k1_level")),
            GDict.Of("id", "combo", "head", "TUTORIAL 4/5", "task", "Defeat both enemy heroes", "say", GArray.Of("k1_combo"), "bubble", "b_natural"),
            GDict.Of("id", "upgrade", "head", "TUTORIAL 4/5", "task", "Make a skill stronger with the +", "say", GArray.Of("k1_upgrade")),
            GDict.Of("id", "ult", "head", "TUTORIAL 5/5", "task", "Learn your ultimate", "say", GArray.Of("k1_ult")),
            GDict.Of("id", "ult_use", "head", "TUTORIAL 5/5", "task", "Hit the enemy heroes with your ultimate", "say", GArray.Of("k1_ult_use"), "after", GArray.Of("k1_ult_done")),
            GDict.Of("id", "shop", "head", "QUICK-BUY", "task", "Tap the item on the left to buy it", "say", GArray.Of("k1_shop"), "after", GArray.Of("k1_shop_done")),
            GDict.Of("id", "tower1", "head", "CHALLENGE 1/3", "task", "Destroy the enemy outer tower", "say", GArray.Of("k1_towers"), "after", GArray.Of("k1_tower_down")),
            GDict.Of("id", "tower3", "head", "CHALLENGE 2/3", "task", "Destroy the high ground tower", "say", new GArray()),
            GDict.Of("id", "king", "head", "CHALLENGE 3/3", "task", "Defeat the enemy King", "say", GArray.Of("k1_king_open"))
        );
        public static readonly GArray K2 = GArray.Of(
            GDict.Of("id", "tour", "head", "THE RIFT", "task", "", "say", new GArray()),
            GDict.Of("id", "go", "head", "YOUR LANE", "task", "Follow Kael to your lane", "say", new GArray()),
            GDict.Of("id", "m1", "head", "MISSION 1/4", "task", "Destroy an enemy outer tower", "say", new GArray()),
            GDict.Of("id", "m2", "head", "MISSION 2/4", "task", "Destroy an enemy inner tower", "say", new GArray()),
            GDict.Of("id", "m3", "head", "MISSION 3/4", "task", "Destroy an enemy high ground tower", "say", new GArray()),
            GDict.Of("id", "m4", "head", "MISSION 4/4", "task", "Defeat the enemy King", "say", new GArray())
        );
        public static readonly GArray TOUR = GArray.Of("k2_welcome", "k2_lanes", "k2_minions", "k2_towers", "k2_win1", "k2_win2", "k2_roles", "k2_top", "k2_mid",
            "k2_bot", "k2_jungle", "k2_ready");
        public static readonly GArray TOWER_TALK = GArray.Of("k2_tw1", "k2_tw2", "k2_tw3", "k2_tw4", "k2_tw5", "k2_tw6", "k2_tw7");
        public static readonly GDict POST_GO = GDict.Of("top", "k2_go_top", "mid", "k2_go_mid", "bot", "k2_go_bot", "support", "k2_go_bot", "jungle", "k2_go_jungle");
        public static readonly GDict POST_NAME = GDict.Of("top", "the top lane", "mid", "the middle lane", "bot", "the bottom lane", "support", "the bottom lane", "jungle", "the jungle");

        public int which = 1;                       // 1: the basics, 2: the 5v5 battle (siege_mode.training)
        public SiegeMode mode;                      // siege_mode.gd
        public SiegeSim sim;
        public SiegeHud hud;
        public GArray steps = new GArray();
        public int step = -1;
        public string phase = "wait";               // wait (the match warming up) -> play -> over
        public string hold_kind = "";               // the match waits while he says these: "tour" (the map), "towers" (the towers' lesson)
        public GArray lines_said = new GArray();    // (tests) every line begun in the bar, in order
        public GArray bubbles_said = new GArray();  // ...and every bubble
        public Unit kael = null;
        public List<string> foes = new List<string>();          // training 1: the enemy heroes put in front of you
        public bool won = false;
        public GArray _queue = new GArray();
        public string _cur = "";                    // the line in the bar
        public string _last = "";
        public double _shown = 0.0;
        public double _line_t = 0.0;
        public double _idle = 99.0;
        public double _time = 0.0;
        public double _ai = 0.0;
        public List<string> _wave = new List<string>();
        public List<string> _ours = new List<string>();
        public double _ours_at = -99.0;
        public Vector2 _goal = Vector2.INF;         // where Kael's leading you
        public Tower _tw = null;
        public string _bubble = "";
        public double _bubble_until = 0.0;
        public GDict _once = new GDict();
        public GDict _cool = new GDict();
        public bool _ult_used = false;
        public bool _bought = false;
        public int _lh0 = 0;
        public GDict _guide_until = new GDict();    // a short-lived pointer (training 2: HOME, the quick-buy) -> until
        public string _note = "";
        public double _note_until = 0.0;
        public List<Vector2> _path = new List<Vector2>();
        public double _path_clock = 0.0;
        public double _end_at = -1.0;
        public AudioStreamPlayer voice;
        public AudioStreamPlayer voice2;            // (the bubbles)
        // the bar, the box, the tap catcher, the map, the end
        public PanelContainer bar;
        public RichTextLabel bar_text;
        public Panel portrait;
        public PanelContainer box;
        public Label box_head;
        public Label box_task;
        public Label box_prog;
        public Tapper tapper;
        public Minimap map;
        public Button skip_btn;
        public Control end_layer;

        protected override void _Ready()
        {
            MouseFilter = Control.MOUSE_FILTER_IGNORE;
            SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            voice = new AudioStreamPlayer();
            voice.Bus = "Master";
            AddChild(voice);
            voice2 = new AudioStreamPlayer();
            voice2.Bus = "Master";
            AddChild(voice2);
            tapper = new Tapper();
            tapper.trainer = this;
            tapper.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            tapper.Visible = false;
            AddChild(tapper);
            // the bar: Kael's portrait in a gold ring, his name, his line
            bar = new PanelContainer();
            bar.AddThemeStyleboxOverride("panel", _Box(new Color(0.03, 0.05, 0.13, 0.9), new Color(VisualTheme.GOLD_DARK, 0.95), 14, 6));
            bar.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            bar.Visible = false;
            AddChild(bar);
            var h = new HBoxContainer();
            h.AddThemeConstantOverride("separation", 8);
            h.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            bar.AddChild(h);
            portrait = new Panel();
            portrait.CustomMinimumSize = new Vector2(50, 50);
            var ps = new StyleBoxFlat();
            ps.BgColor = new Color(0.85, 0.72, 0.42);
            ps.SetCornerRadiusAll(25);
            ps.BorderColor = GOLD;
            ps.SetBorderWidthAll(2);
            ps.AntiAliasing = true;
            portrait.AddThemeStyleboxOverride("panel", ps);
            portrait.ClipChildren = CanvasItem.CLIP_CHILDREN_AND_DRAW;
            portrait.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            h.AddChild(portrait);
            var face = new TextureRect();
            face.Texture = ResourceLoader.Exists(PORTRAIT) ? ResourceLoader.Load<Texture2D>(PORTRAIT) : null;
            face.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            face.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
            face.Position = new Vector2(-6, -2);
            face.Size = new Vector2(62, 62);
            face.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            portrait.AddChild(face);
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 0);
            v.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            v.Alignment = BoxContainer.ALIGNMENT_CENTER;
            v.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            h.AddChild(v);
            var nm = _Label(v, "KAEL  ·  THE DRAGOON", 10, GOLD);
            nm.AddThemeConstantOverride("outline_size", 3);
            bar_text = new RichTextLabel();
            bar_text.BbcodeEnabled = true;
            bar_text.FitContent = true;
            bar_text.ScrollActive = false;
            bar_text.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            bar_text.AddThemeFontOverride("normal_font", VisualTheme.BOLD_FONT);
            bar_text.AddThemeFontSizeOverride("normal_font_size", 14);
            bar_text.AddThemeColorOverride("default_color", Color.FromCode("#fff6e0"));
            bar_text.AddThemeConstantOverride("outline_size", 3);
            bar_text.AddThemeColorOverride("font_outline_color", new Color(0, 0, 0, 0.6));
            bar_text.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            bar_text.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            v.AddChild(bar_text);
            // the box: the task
            box = new PanelContainer();
            box.AddThemeStyleboxOverride("panel", _Box(new Color(0.03, 0.05, 0.13, 0.86), new Color(VisualTheme.GOLD_DARK, 0.9), 10, 7));
            box.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            box.Visible = false;
            AddChild(box);
            var bv = new VBoxContainer();
            bv.AddThemeConstantOverride("separation", 1);
            bv.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            box.AddChild(bv);
            box_head = _Label(bv, "", 11, GOLD);
            box_task = _Label(bv, "", 13, Color.FromCode("#fff4d6"));
            box_task.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            box_prog = _Label(bv, "", 12, Color.FromCode("#9ff6ef"));
            _Layout();
        }

        public static StyleBoxFlat _Box(Color bg, Color rim, int radius, int pad)
        {
            var sb = new StyleBoxFlat();
            sb.BgColor = bg;
            sb.BorderColor = rim;
            sb.SetBorderWidthAll(2);
            sb.SetCornerRadiusAll(radius);
            sb.ContentMarginLeft = pad + 4;
            sb.ContentMarginRight = pad + 4;
            sb.ContentMarginTop = pad;
            sb.ContentMarginBottom = pad;
            sb.ShadowColor = new Color(0, 0, 0, 0.4);
            sb.ShadowSize = 5;
            sb.AntiAliasing = true;
            return sb;
        }

        public Label _Label(Node parent, string text, int px, Color col)
        {
            var l = new Label();
            l.Text = text;
            l.AddThemeFontOverride("font", VisualTheme.BOLD_FONT);
            l.AddThemeFontSizeOverride("font_size", px);
            l.AddThemeColorOverride("font_color", col);
            l.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(l);
            return l;
        }

        // A full-screen catch for the taps while the match waits (the map, the towers' lesson, the end): a tap moves him on.
        // Not over the HUD's pause button.
        public class Tapper : ColorRect
        {
            public Training trainer;
            protected override void _Ready()
            {
                MouseFilter = Control.MOUSE_FILTER_STOP;
                Color = new Color(0.0, 0.01, 0.04, 0.5);
            }
            // (_has_point: the facade's Control.has_point virtual)
            public override bool HasPoint(Vector2 p)
            {
                if (trainer == null || trainer.hud == null || !GD.IsInstanceValid(trainer.hud.pause_btn))
                    return true;
                return !trainer.hud.pause_btn.GetGlobalRect().Grow(4.0).HasPoint(GetGlobalTransform() * p);
            }
            protected override void _GuiInput(InputEvent e)
            {
                if ((e is InputEventScreenTouch && (e as InputEventScreenTouch).Pressed) || (e is InputEventMouseButton && (e as InputEventMouseButton).Pressed && (e as InputEventMouseButton).ButtonIndex == MouseButton.Left))
                {
                    AcceptEvent();
                    trainer.Next();
                }
            }
        }

        // The big map of the tour (minimap.gd, large) with what he's talking about lit over it
        public class MapFx : Control
        {
            public Training trainer;
            protected override void _Ready()
            {
                MouseFilter = Control.MOUSE_FILTER_IGNORE;
                SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            }
            protected override void _Process(double _dt)
            {
                QueueRedraw();
            }
            protected override void _Draw()
            {
                trainer._DrawMapFx(this);
            }
        }

        protected override void _UnhandledInput(InputEvent e)
        {
            if (Holds() && phase != "wait" && e is InputEventKey && (e as InputEventKey).Pressed && !(e as InputEventKey).Echo
                && Array.IndexOf(new[] { Key.Space, Key.Enter, Key.KpEnter }, (e as InputEventKey).PhysicalKeycode) >= 0)
            {
                GetViewport().SetInputAsHandled();
                Next();
            }
        }

        // ---------------- the match ----------------
        public void Begin(SiegeMode m)
        {
            mode = m;
            sim = m.sim;
            hud = m.hud;
            steps = which == 1 ? K1 : K2;
            hud.kill_feed_on = false;                   // (his words instead)
            var me = _Me();
            var t = me != null ? (int)me.team : 0;
            kael = _PickKael(t);
            if (which == 1)
            {
                for (int tt = 0; tt < 2; tt++)
                {
                    foreach (var hid in sim.moba.heroes[tt])
                    {
                        Unit hh = sim.by_id.TryGetValue(hid, out var hu) ? hu : null;
                        if (hh != null && GD.Str(hid) != GD.Str(me != null ? me.id : ""))
                        {
                            hh.bot = false;                  // (every other hero at his fountain; Kael's driven from here)
                            hh.move = Vector2.ZERO;
                        }
                    }
                }
                sim.moba.wave_at = GD.INF;                      // no waves but the ones put down here
                foreach (var c in sim.moba.camps)
                    c.next = GD.INF;                            // no camps either
                me.pos = _Side(t, P_START);
                me.face = Sim.AngleOf(_Side(t, new Vector2(0, -1)));
                if (kael != null)
                {
                    kael.pos = _Side(t, P_START + new Vector2(-2.0, -1.5));
                    kael.face = me.face;
                    kael.m_out = SOFT;
                }
            }
            else
            {
                if (kael != null)
                    kael.bot = false;                        // (he goes where you go)
                foreach (var hid in sim.moba.heroes[1 - t])
                {
                    Unit foe = sim.by_id.TryGetValue(hid, out var fu) ? fu : null;
                    if (foe != null)
                        foe.m_out = SOFT2;
                }
            }
            _RefreshBox();
        }

        public Unit _PickKael(int t)
        {
            // one of our bots becomes Kael: a Dragoon of ours if there is one, else the support (the jungler if you're it)
            var me = _Me();
            Unit pick = null;
            foreach (var hid in sim.moba.heroes[t])
            {
                Unit u = sim.by_id.TryGetValue(hid, out var uu) ? uu : null;
                if (u == null || GD.Str(hid) == GD.Str(me != null ? me.id : ""))
                    continue;
                if (GD.Str(u.hid) == KAEL_HID)
                {
                    pick = u;
                    break;
                }
                if (pick == null || GD.Str(u.post) == (GD.Str(me != null ? me.post : "") != "support" ? "support" : "jungle"))
                    pick = u;
            }
            if (pick == null)
                return null;
            sim.moba.SwapHero(pick, KAEL_HID);
            pick.bot_name = KAEL_NAME;
            pick.bot = false;
            pick.move = Vector2.ZERO;
            return pick;
        }

        public Unit _Me()
        {
            // ({} when there's no such unit: null here)
            return sim != null && hud != null ? (sim.by_id.TryGetValue(hud.player_id, out var u) ? u : null) : null;
        }

        public static Vector2 _Side(int team, Vector2 p)
        {
            return team == 0 ? p : -p;
        }

        public bool Holds()
        {
            // siege_mode: while true the match doesn't step (warming up, the map, the towers' lesson)
            return phase == "wait" || hold_kind != "";
        }

        public string StepId()
        {
            return step >= 0 && step < steps.Size() ? GD.Str(steps[step]["id"]) : "";
        }

        public void _Keep(Unit me)
        {
            // the blessing, and the clock never runs out on a lesson (training 1)
            if (me == null || !sim.Alive(me))
                return;
            me.dr = GD.Maxf((double)me.dr, which == 1 ? TAKE : TAKE2);
            me.dr_until = (double)sim.time + 1.0;
            if (which == 1)
            {
                if ((double)me.hp < (double)me.max_hp * HP_FLOOR)
                    me.hp = (double)me.max_hp * HP_FLOOR;
                if (kael != null && sim.Alive(kael) && (double)kael.hp < (double)kael.max_hp * HP_FLOOR)
                    kael.hp = (double)kael.max_hp * HP_FLOOR;
                foreach (var c in sim.moba.camps)
                {
                    if (!(bool)c.alive)
                        c.next = GD.INF;
                }
                if ((double)sim.match_time - (double)sim.time < 120.0)
                    sim.match_time = (double)sim.match_time + 600.0;
            }
        }

        // ---------------- the bar ----------------
        public void Say(string id)
        {
            _queue.Append(id);
        }

        public static string Lit(string text)
        {
            // the line in bbcode, its key words gold
            var rx = new RegEx();
            var alts = new GArray();
            foreach (var k in KEYS)
                alts.Append(GD.Str(k).Replace("!", "\\!"));
            rx.Compile("(?<![\\w])(" + GStr.Join("|", alts) + ")(?![\\w])");
            return rx.Sub(text.Replace("[", "(").Replace("]", ")"), "[color=" + KEY_INK + "]$1[/color]", true);
        }

        public void _StartLine(string id)
        {
            _cur = id;
            _last = id;
            _shown = 0.0;
            _line_t = 0.0;
            lines_said.Append(id);
            bar_text.Text = Lit(GD.Str(LINES.Get(id, "")));
            bar_text.VisibleCharacters = 0;
            _Play(voice, id);
        }

        public bool _Play(AudioStreamPlayer p, string id)
        {
            p.Stop();
            p.Stream = null;
            var master = 1.0;
            var muted = false;
            if (mode != null && mode.audio != null)
            {
                master = (double)mode.audio.levels.Get("master", 1.0);
                muted = (bool)mode.audio.muted;
            }
            var path = VO_DIR + id + ".ogg";
            if (muted || master <= 0.0 || !ResourceLoader.Exists(path))
                return false;
            p.Stream = ResourceLoader.Load<AudioStream>(path);
            p.VolumeDb = GD.LinearToDb(master * VOICE_GAIN);
            p.Play();
            return true;
        }

        public void _TickBar(double dt)
        {
            if (_cur == "")
            {
                if (!_queue.IsEmpty())
                    _StartLine(GD.Str(_queue.PopFront()));
                else
                    _idle += dt;
            }
            if (_cur != "")
            {
                _line_t += dt;
                var full = GD.Str(LINES.Get(_cur, "")).Length;
                _shown = GD.Minf(_shown + dt * TYPE_CPS, (double)full);
                bar_text.VisibleCharacters = _shown >= (double)full ? -1 : (int)_shown;
                // on when it's said and typed out (unvoiced -- muted -- when there's been time to read it)
                var least = (double)full / TYPE_CPS + 0.45;
                if (voice.Stream == null)
                    least = GD.Maxf(least, (double)full / 15.0 + 0.8);
                if (!voice.Playing && _line_t >= least)
                {
                    _cur = "";
                    _idle = 0.0;
                    voice.Stream = null;
                }
            }
            bar.Visible = _cur != "" || (_idle < 2.2 && _last != "") || hold_kind != "";
        }

        public void Next()
        {
            // a tap while the match waits: the line typed out, then on to the next
            if (phase == "over")
                return;
            if (_cur == "")
                return;
            var full = GD.Str(LINES.Get(_cur, "")).Length;
            if (_shown < (double)full)
            {
                _shown = (double)full;
                return;
            }
            voice.Stop();
            voice.Stream = null;
            _cur = "";
            _idle = 0.0;
        }

        public void _Cut()
        {
            // the line in the bar stops (the match is about to wait for a lesson of its own)
            voice.Stop();
            voice.Stream = null;
            if (_cur != "")
            {
                _cur = "";
                _idle = 0.0;
            }
        }

        public void Bubble(string id)
        {
            if (kael == null || !sim.Alive(kael))
                return;
            _bubble = id;
            _bubble_until = _time + 2.4;
            bubbles_said.Append(id);
            if (!voice.Playing)
                _Play(voice2, id);
        }

        // ---------------- steps ----------------
        public void _SetStep(int i, GArray pre = null)
        {
            pre ??= new GArray();
            step = i;
            _queue = pre.Duplicate();
            if (i >= steps.Size())
                return;
            foreach (var id in steps[i].Get("say", new GArray()))
                _queue.Append(GD.Str(id));
            _Enter(StepId());
            _RefreshBox();
            if (mode != null && mode.analytics != null)
                mode.analytics.LogEv("tutorial_step", GDict.Of("step", i, "id", StepId()));
        }

        public void _Complete()
        {
            GArray after = steps[step].Get("after", new GArray()).A;
            if (GD.Str(steps[step].Get("bubble", "")) != "")
                Bubble(GD.Str(steps[step]["bubble"]));
            if (mode != null && mode.audio != null)
                mode.audio.Play("claim");
            _note = "";
            _SetStep(step + 1, after);
        }

        public void _Enter(string id)
        {
            var me = _Me();
            var t = me != null ? (int)me.team : 0;
            var et = 1 - t;
            _goal = Vector2.INF;
            switch (id)
            {
                case "move":
                    _goal = _Side(t, P_MOVE);
                    break;
                case "minions":
                    _lh0 = me != null ? (int)me.lh : 0;
                    _wave = sim.moba.PlaceMinions(et, 1, WAVE, _Side(t, P_WAVE));
                    break;
                case "hero":
                    foes = new List<string> { _PutFoe(2, me.pos + _Side(t, new Vector2(1.0, -11.0))) };
                    break;
                case "learn2":
                    _LevelTo(2);
                    break;
                case "combo":
                    foes = new List<string> { _PutFoe(0, me.pos + _Side(t, new Vector2(-3.0, -11.0))), _PutFoe(3, me.pos + _Side(t, new Vector2(3.0, -12.0))) };
                    break;
                case "upgrade":
                    _LevelTo(3);
                    break;
                case "ult":
                    _LevelTo(4);
                    break;
                case "ult_use":
                {
                    _ult_used = false;
                    me.ult_cd = 0.0;
                    Vector2 c = me.pos + _Side(t, new Vector2(0.0, -10.0));
                    foes = new List<string> { _PutFoe(1, c + new Vector2(-1.6, 0.0)), _PutFoe(2, c + new Vector2(1.6, 0.0)), _PutFoe(4, c + _Side(t, new Vector2(0.0, -1.6))) };
                    break;
                }
                case "shop":
                {
                    _bought = false;
                    List<string> nb = sim.moba.NextBuys(me, 1);
                    if (nb.Count != 0)
                        me.gold = GD.Maxf((double)me.gold, (double)sim.moba.Price(me, GD.Str(nb[0])) + 60.0);
                    break;
                }
                case "tower1":
                    _tw = _Tower(et, 1, 1);
                    _Weaken(_tw);
                    break;
                case "tower3":
                    _tw = _Tower(et, 1, 3);
                    _Weaken(_tw);
                    break;
                case "king":
                {
                    _tw = null;
                    KingSt k = sim.moba.kings[et];
                    k.hp = GD.Minf((double)k.hp, (double)k.max_hp * KING_LEFT);
                    break;
                }
                case "tour":
                    hold_kind = "tour";
                    _Cut();
                    _queue = TOUR.Duplicate();
                    _ShowMap(true);
                    break;
                case "go":
                {
                    var post = GD.Str(me != null && me.post != "" ? me.post : "top");     // (me.get("post", "top"): a unit without a post has none)
                    _queue.Append(GD.Str(POST_GO.Get(post, "k2_go_top")));
                    _goal = _LaneGoal(t, post);
                    break;
                }
                case "m1":
                case "m2":
                case "m3":
                case "m4":
                    break;
            }
        }

        public Tower _Tower(int team, int lane, int tier)
        {
            foreach (var tw in sim.moba.towers)
            {
                if ((int)tw.team == team && (int)tw.lane == lane && (int)tw.tier == tier)
                    return tw;
            }
            return null;
        }

        public void _Weaken(Tower tw)
        {
            if (tw != null && !(bool)tw.dead)
                tw.hp = GD.Minf((double)tw.hp, (double)tw.max_hp * TOWER_LEFT);
        }

        public Vector2 _LaneGoal(int t, string post)
        {
            if (post == "jungle")
            {
                foreach (var c in sim.moba.camps)
                {
                    if ((int)c.side == t && GArray.Of("arcane", "ember").Has(GD.Str(c.kind)))
                        return c.p;
                }
            }
            var lane = Moba.POST_LANE.TryGetValue(post, out var pl) ? pl : 1;
            var tw = _Tower(t, lane, 1);
            return tw != null ? tw.p : Sim.Spawn(t);
        }

        public void _LevelTo(int n)
        {
            var me = _Me();
            while ((me != null ? (int)me.level : 1) < n)
                sim.moba.AddXp(me, sim.moba.Need((int)me.level) - (double)me.xp + 0.1);
        }

        public string _PutFoe(int i, Vector2 at)
        {
            // training 1: an enemy hero, there, at half health, hitting softer
            var t = (int)_Me().team;
            List<string> ids = sim.moba.heroes[1 - t];
            Unit foe = sim.by_id.TryGetValue(ids[GD.Clampi(i, 0, ids.Count - 1)], out var fu) ? fu : null;
            if (foe == null)
                return "";
            if (!sim.Alive(foe))
                sim.Respawn(foe);
            foe.pos = at;
            foe.move = Vector2.ZERO;
            foe.state = "idle";
            foe.hp = (double)foe.max_hp * FOE_HP;
            foe.m_out = SOFT;
            foe.face = Sim.AngleOf(_Me().pos - at);
            sim.Emit("recall_done", new Ev { { "id", GD.Str(foe.id) }, { "from", at }, { "to", at }, { "tut", true } });     // (he arrives in a flash)
            return GD.Str(foe.id);
        }

        public List<string> _Alive(List<string> ids)
        {
            return ids.FindAll(id => sim.by_id.ContainsKey(GD.Str(id)) && sim.Alive(sim.by_id[GD.Str(id)]));
        }

        public bool _Done()
        {
            var me = _Me();
            var t = me != null ? (int)me.team : 0;
            switch (StepId())
            {
                case "move":
                    return me.pos.DistanceTo(_goal) <= 4.0;
                case "minions":
                    return _Alive(_wave).Count == 0;
                case "learn":
                    return _Learnt(me) >= 1;
                case "hero":
                case "combo":
                    return _Alive(foes).Count == 0;
                case "learn2":
                    return _Learnt(me) >= 2;
                case "upgrade":
                    foreach (var sl in new[] { "q", "w", "e" })
                    {
                        if (sim.moba.Rank(me, sl) >= 2)
                            return true;
                    }
                    return false;
                case "ult":
                    return sim.moba.Rank(me, "r") >= 1;
                case "ult_use":
                    return _Alive(foes).Count == 0;
                case "shop":
                    return _bought;
                case "tower1":
                case "tower3":
                    return _tw == null || (bool)_tw.dead;
                case "king":
                    return false;                              // (the match ends: match_over)
                case "tour":
                    return hold_kind == "";
                case "go":
                    return me.pos.DistanceTo(_goal) <= 9.0;
                case "m1":
                case "m2":
                case "m3":
                {
                    var tier = GD.Int(StepId().Substr(1));
                    foreach (var tw in sim.moba.towers)
                    {
                        if ((int)tw.team != t && (int)tw.tier == tier && (bool)tw.dead)
                            return true;
                    }
                    return false;
                }
            }
            return false;
        }

        public int _Learnt(Unit me)
        {
            var n = 0;
            foreach (var sl in new[] { "q", "w", "e" })
            {
                if (sim.moba.Rank(me, sl) >= 1)
                    n += 1;
            }
            return n;
        }

        public string Progress()
        {
            var me = _Me();
            switch (StepId())
            {
                case "minions":
                    return GD.Fmt("%d/%d", _wave.Count - _Alive(_wave).Count, _wave.Count);
                case "combo":
                    return GD.Fmt("%d/2", foes.Count - _Alive(foes).Count);
                case "ult_use":
                    return GD.Fmt("%d/3", foes.Count - _Alive(foes).Count);
                case "tower1":
                case "tower3":
                    if (_tw != null)
                        return GD.Fmt("Tower health %d%%", (int)Math.Ceiling(100.0 * (double)_tw.hp / GD.Maxf(1.0, (double)_tw.max_hp)));
                    break;
                case "king":
                {
                    var et = 1 - (me != null ? (int)me.team : 0);
                    return GD.Fmt("King health %d%%", (int)Math.Ceiling(100.0 * sim.moba.KingFrac(et)));
                }
            }
            return "";
        }

        public void _RefreshBox()
        {
            if (step < 0 || step >= steps.Size())
            {
                box.Visible = false;
                return;
            }
            GDict st = steps[step].D;
            box_head.Text = GD.Str(st["head"]);
            var task = GD.Str(st["task"]);
            if (StepId() == "go")
            {
                var me = _Me();
                task = "Follow Kael to " + GD.Str(POST_NAME.Get(GD.Str(me != null && me.post != "" ? me.post : "top"), "your lane"));
            }
            box_task.Text = task;
            box.Visible = task != "" && phase == "play" && hold_kind == "";
        }

        // ---------------- every frame ----------------
        protected override void _Process(double delta)
        {
            if (sim == null)
                return;
            _time += delta;
            var me = _Me();
            if (phase != "over")
                _Keep(me);
            voice.StreamPaused = hud.Paused();
            voice2.StreamPaused = hud.Paused();
            if (hud.Paused())
                return;
            if (phase == "wait")
            {
                if (mode == null || mode.Warmed())
                {
                    phase = "play";
                    _SetStep(0);
                    // (Honor of Kings' "Arcana Trial Privileges in effect!")
                    hud.Toast(which == 1 ? "KAEL'S BLESSING: you take half damage and can't fall" : "KAEL'S BLESSING: you take a quarter less damage", GOLD);
                }
                _Layout();
                return;
            }
            _TickBar(delta);
            if (hold_kind != "" && _cur == "" && _queue.IsEmpty())
                _EndHold();
            if (phase == "play" && hold_kind == "" && !sim.ended)
            {
                _ai -= delta;
                if (_ai <= 0.0)
                {
                    _ai = 0.1;
                    _DriveKael();
                    if (which == 1)
                        _DriveFoes();
                }
                _TickStep(delta);
                if (step < steps.Size() && _Done())
                    _Complete();
                _UpdatePath(delta);
            }
            if (phase == "over" && _end_at >= 0.0 && _time >= _end_at && end_layer != null)
            {
                _end_at = -1.0;
                _ShowCard();
            }
            box_prog.Text = Progress();
            box_prog.Visible = box_prog.Text != "" || (_note != "" && _time < _note_until);
            if (_note != "" && _time < _note_until)
                box_prog.Text = _note;
            _RefreshBox();
            if (hud != null)
                hud.tut_modal = Holds() || phase == "over";
            tapper.Visible = hold_kind != "";
            tapper.Color = new Color(0.0, 0.01, 0.04, hold_kind == "tour" ? 0.55 : 0.22);     // (the towers' lesson: the ring in sight)
            _Layout();
            QueueRedraw();
        }

        public void _TickStep(double _dt)
        {
            var me = _Me();
            if (me == null)
                return;
            var t = (int)me.team;
            var et = 1 - t;
            switch (StepId())
            {
                case "move":
                    if (kael != null && me.pos.DistanceTo(kael.pos) > 12.0 && _ReadyFor("over_here", 9.0))
                        Bubble("b_over_here");
                    break;
                case "minions":
                    if ((int)me.lh > _lh0 && _First("gold"))
                        Say("k1_gold");
                    break;
                case "ult_use":
                    break;
                case "tower1":
                case "tower3":
                case "king":
                {
                    Vector2 at = _tw != null ? _tw.p : sim.moba.KingPos(et);
                    _DeliverArmy(at);
                    if (_tw != null && !(bool)_tw.dead)
                    {
                        if (sim.moba.InTowerRange(_tw, me.pos) && _First("tower"))
                            Say("k1_tower");
                        if (GD.Str(_tw.target) == GD.Str(me.id) && _First("tower_red"))
                        {
                            Say("k1_tower_red");
                            Bubble("b_watch_out");
                        }
                    }
                    break;
                }
                case "m1":
                case "m2":
                case "m3":
                case "m4":
                    _TickBattle(me, t, et);
                    break;
            }
            if (which == 2 && StepId() == "go")
                _TickBattle(me, t, et);
        }

        public void _DeliverArmy(Vector2 at)
        {
            // training 1's towers and King: our minions walking in ahead of you, more when they're gone
            var me = _Me();
            var t = (int)me.team;
            if (_Alive(_ours).FindAll(id => sim.by_id[GD.Str(id)].pos.DistanceTo(at) < 26.0).Count != 0)
                return;
            if ((double)sim.time - _ours_at < 6.0)
                return;
            _ours_at = (double)sim.time;
            var toward = _Side(t, new Vector2(0.0, 1.0));                   // (our side of it)
            var from = new Vector2(0.0, at.y) + toward * 17.0;
            _ours = sim.moba.PlaceMinions(t, 1, ARMY, from);
            if (StepId() != "tower1" || _once.Has("army"))
            {
                _note = "More of our minions -- let them go first";
                _note_until = _time + 3.0;
            }
            _once["army"] = true;
        }

        public void _TickBattle(Unit me, int t, int et)
        {
            // training 2's moments, each when it comes
            if (!sim.Alive(me))
                return;
            // the towers' lesson: the first time you're by one of theirs (the match waits)
            if (!_once.Has("towers"))
            {
                foreach (var tw in sim.moba.towers)
                {
                    if ((int)tw.team == et && !(bool)tw.dead && me.pos.DistanceTo(tw.p) <= (double)Moba.TOWER_RANGE + 3.0)
                    {
                        _once["towers"] = true;
                        _tw = tw;
                        hold_kind = "towers";
                        _Cut();
                        _queue = TOWER_TALK.Duplicate();
                        return;
                    }
                }
            }
            if ((double)me.hp < (double)me.max_hp * 0.35 && !Sim.InCastle(me.pos, t) && !sim.Recalling(me) && _ReadyFor("recall", 90.0, 2))
            {
                Say("k2_recall");
                _guide_until["recall"] = _time + 8.0;
            }
            List<string> nb = sim.moba.NextBuys(me, 1);
            if (nb.Count != 0 && sim.moba.BuyWhy(me, GD.Str(nb[0])) == "" && !hud.ShopOpen() && _ReadyFor("shop", 150.0, 2))
            {
                Say("k2_shop");
                _guide_until["shop"] = _time + 8.0;
            }
            if (sim.moba.KingOpen(et) && _First("king"))
                Say("k2_king");
            foreach (var o in sim.moba.UnitsNear(me.pos, 9.0))
            {
                if ((int)o.team == et && (bool)o.hero && sim.Alive(o) && sim.moba.CanSee(t, o) && _ReadyFor("watch", 60.0))
                {
                    Bubble("b_watch_out");
                    break;
                }
            }
        }

        public bool _First(string key)
        {
            if (_once.Has(key))
                return false;
            _once[key] = true;
            return true;
        }

        public bool _ReadyFor(string key, double every, int most = 999)
        {
            GArray c = _cool.Get(key, GArray.Of(-GD.INF, 0)).A;
            if (_time < (double)c[0] || (int)c[1] >= most)
                return false;
            _cool[key] = GArray.Of(_time + every, (int)c[1] + 1);
            return true;
        }

        public void _EndHold()
        {
            var was = hold_kind;
            hold_kind = "";
            if (was == "tour")
            {
                _ShowMap(false);
                _Complete();
            }
        }

        public void OnEvent(Ev e)
        {
            // (siege_mode passes on the match's events)
            var me = _Me();
            if (me == null || phase != "play")
                return;
            bool mine = e.S("id", "") == GD.Str(me.id);
            switch (e.S("k", ""))
            {
                case "buy":
                    if (mine)
                    {
                        _bought = true;
                        if (hud.ShopOpen() && which == 1)
                            hud.CloseShop();
                    }
                    break;
                case "ult":
                    if (mine)
                        _ult_used = true;
                    break;
                case "death":
                {
                    Unit dead = sim.by_id.TryGetValue(e.S("id", ""), out var du) ? du : null;
                    if (e.S("by", "") == GD.Str(me.id) && (dead != null && (bool)dead.hero) && which == 2 && _ReadyFor("nice", 30.0))
                        Bubble("b_nice");
                    break;
                }
                case "tower_down":
                    if (which == 2 && e.I("team", -1) != (int)me.team && _ReadyFor("tower_down", 20.0))
                        Bubble("b_well_done");
                    break;
                case "king_slam":
                    if (which == 1 && e.I("team", -1) != (int)me.team && me.pos.DistanceTo(sim.moba.KingPos(e.I("team"))) < 8.0 && _First("slam"))
                        Say("k1_king_slam");
                    break;
                case "recall":
                    if (kael != null && e.S("id", "") == GD.Str(kael.id))
                        Bubble("b_brb");
                    break;
            }
            _AfterEvent(e);
        }

        public void _AfterEvent(Ev e)
        {
            // training 1: the bubbles at a lesson's end; the high ground once the outer tower falls
            if (which != 1)
                return;
            if (e.S("k", "") == "tower_down" && GArray.Of("tower1", "tower3").Has(StepId()))
            {
                var me = _Me();
                if (e.I("tier", 0) == 1)
                {
                    var inner = _Tower(1 - (int)me.team, e.I("lane", 1), 2);       // our army takes their inner tower too
                    if (inner != null && !(bool)inner.dead)
                        sim.moba.HitTower(kael != null ? kael : me, (int)inner.id, 1.0e9, Vector2.INF);
                }
            }
        }

        public void _ShowMap(bool on)
        {
            if (on)
            {
                if (map == null)
                {
                    map = new Minimap();
                    map.hud = hud;
                    map.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                    AddChild(map);
                    var fx = new MapFx();
                    fx.trainer = this;
                    map.AddChild(fx);
                    skip_btn = new Button();
                    skip_btn.Text = "SKIP  ›";
                    skip_btn.FocusMode = Control.FOCUS_NONE;
                    skip_btn.AddThemeFontOverride("font", VisualTheme.BOLD_FONT);
                    skip_btn.AddThemeFontSizeOverride("font_size", 12);
                    skip_btn.SetMeta("action_key", "training_skip");
                    var ks = _Box(new Color(0.04, 0.06, 0.15, 0.92), new Color(VisualTheme.GOLD_DARK, 0.95), 10, 4);
                    foreach (var st in new[] { "normal", "hover", "pressed", "focus" })
                        skip_btn.AddThemeStyleboxOverride(st, ks);
                    skip_btn.AddThemeColorOverride("font_color", GOLD);
                    skip_btn.Pressed += () =>
                    {
                        _queue.Clear();
                        voice.Stop();
                        voice.Stream = null;
                        _cur = "";
                    };
                    AddChild(skip_btn);
                }
                map.Visible = true;
                skip_btn.Visible = true;
            }
            else if (map != null)
            {
                map.Visible = false;
                skip_btn.Visible = false;
            }
        }

        // ---------------- Kael and the foes ----------------
        public void _DriveKael()
        {
            if (kael == null || !sim.Alive(kael) || (double)kael.stun > 0.0 || GArray.Of("wind", "recover", "dodge").Has(GD.Str(kael.state)))
                return;
            var me = _Me();
            if (me == null)
                return;
            var t = (int)me.team;
            var et = 1 - t;
            if ((int)kael.sp > 0)
                sim.moba._BotLearn(kael);
            if (sim.Recalling(kael))
            {
                kael.move = Vector2.ZERO;
                return;
            }
            if (which == 2)
            {
                if (GD.Fmod(_time, 3.0) < 0.1)
                    sim.moba._BotShop(kael);
                if ((double)kael.hp < (double)kael.max_hp * 0.25 && _HeroNear(kael, 8.0) == null && !Sim.InCastle(kael.pos, t))
                {
                    sim.Act(GD.Str(kael.id), "recall");
                    return;
                }
            }
            Vector2 mid = me.pos;
            // leading the way: on to the goal, waiting for you when you fall behind
            if (_goal != Vector2.INF && GArray.Of("move", "go").Has(StepId()))
            {
                var foe0 = _HeroNear(kael, 7.0);
                if (foe0 != null)
                {
                    sim.moba._FightH(kael, foe0);
                    return;
                }
                double lag = me.pos.DistanceTo(kael.pos);
                bool ahead = (double)kael.pos.DistanceTo(_goal) + 1.0 < me.pos.DistanceTo(_goal);
                if (lag > 10.0 && ahead)
                {
                    kael.move = Vector2.ZERO;
                    kael.face = Sim.AngleOf(me.pos - kael.pos);
                    return;
                }
                sim.NavTo(kael, _goal + _Side(t, new Vector2(-2.0, 1.0)), 1.0);
                return;
            }
            if (!sim.Alive(me))
                mid = Sim.Spawn(t);
            // a fight near you: their heroes first, then minions (in training 1 only the healthy ones: the last hits are yours)
            Unit foe = kael.pos.DistanceTo(mid) < 14.0 ? _HeroNear(kael, 9.0) : null;
            if (foe == null)
            {
                foreach (var o in sim.moba.UnitsNear(mid, 8.0))
                {
                    if ((int)o.team == et && sim.Alive(o) && (bool)o.minion && (which == 2 || (double)o.hp > (double)o.max_hp * 0.5))
                    {
                        foe = o;
                        break;
                    }
                }
            }
            if (foe != null)
            {
                if (!sim.moba._BotUlt(kael) && !sim.moba.kits.BotSpells(kael))
                    sim.moba._FightH(kael, foe);
                return;
            }
            // a structure you're at, with our minions under it
            Tower tw = sim.moba._EnemyTowerNear(kael, 6.0);
            if (tw != null && sim.moba.InTowerRange(tw, me.pos) && GD.Str(tw.target) != GD.Str(kael.id) && sim.moba.Vulnerable(tw))
            {
                sim.moba._HitStructure(kael, tw);
                return;
            }
            if (sim.moba.KingOpen(et) && me.pos.DistanceTo(sim.moba.KingPos(et)) < 14.0)
            {
                sim.moba._HitPoint(kael, sim.moba.KingPos(et), Moba.KING_R);
                return;
            }
            // else at your side
            Vector2 spot = mid + _Side(t, new Vector2(-2.2, 2.4));
            if (kael.pos.DistanceTo(spot) > 3.0)
                sim.NavTo(kael, spot, 1.5);
            else
                kael.move = Vector2.ZERO;
        }

        public Unit _HeroNear(Unit u, double r)
        {
            Unit best = null;
            var bd = GD.INF;
            foreach (var o in sim.moba.UnitsNear(u.pos, r))
            {
                if ((int)o.team == (int)u.team || (int)o.team > 1 || !sim.Alive(o) || !(bool)o.hero)
                    continue;
                if (which == 2 && !sim.moba.CanSee((int)u.team, o))
                    continue;
                double d = o.pos.DistanceTo(u.pos);
                if (d < bd)
                {
                    bd = d;
                    best = o;
                }
            }
            return best;
        }

        public void _DriveFoes()
        {
            // training 1's enemy heroes come at you (or at Kael)
            var me = _Me();
            foreach (var id in _Alive(foes))
            {
                Unit f = sim.by_id[GD.Str(id)];
                if ((double)f.stun > 0.0 || GArray.Of("wind", "recover", "dodge").Has(GD.Str(f.state)))
                    continue;
                Unit tgt = sim.Alive(me) && me.pos.DistanceTo(f.pos) < 18.0 ? me : null;
                if (tgt == null && kael != null && sim.Alive(kael) && kael.pos.DistanceTo(f.pos) < 18.0)
                    tgt = kael;
                if (tgt == null)
                {
                    f.move = Vector2.ZERO;
                    continue;
                }
                sim.moba._FightH(f, tgt);
            }
        }

        // ---------------- the end ----------------
        public void MatchOver(bool we_won)
        {
            // (siege_mode, the match over: their King down -- or ours, or the clock): VICTORY or DEFEAT, his line, the card
            if (phase == "over")
                return;
            phase = "over";
            won = we_won;
            hold_kind = "";
            _ShowMap(false);
            _queue.Clear();
            _cur = "";
            voice.Stop();
            Say(which == 1 ? "k1_victory" : (won ? "k2_victory" : "k2_defeat"));
            end_layer = new Control();
            end_layer.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            end_layer.MouseFilter = Control.MOUSE_FILTER_STOP;
            AddChild(end_layer);
            MoveChild(end_layer, 0);                         // (under the bar)
            var dim = new ColorRect();
            dim.Color = new Color(0.0, 0.01, 0.04, 0.55);
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            dim.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            end_layer.AddChild(dim);
            var big = new Label();
            big.Text = won ? "VICTORY" : "DEFEAT";
            big.AddThemeFontOverride("font", VisualTheme.BOLD_FONT);
            big.AddThemeFontSizeOverride("font_size", 64);
            big.AddThemeColorOverride("font_color", won ? GOLD : Color.FromCode("#c9d2e8"));
            big.AddThemeConstantOverride("outline_size", 10);
            big.AddThemeColorOverride("font_outline_color", won ? new Color(0.25, 0.12, 0.02) : new Color(0.05, 0.07, 0.15));
            big.HorizontalAlignment = HorizontalAlignment.Center;
            big.Size = new Vector2(600, 80);
            big.Position = new Vector2(Size.x * 0.5 - 300.0, Size.y * 0.36 - 40.0);
            big.PivotOffset = new Vector2(300, 40);
            big.Scale = new Vector2(1.6, 1.6);
            var bm = big.Modulate;
            bm.a = 0.0f;
            big.Modulate = bm;
            big.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            big.Name = "Big";
            end_layer.AddChild(big);
            var tw = CreateTween().SetParallel(true);
            tw.TweenProperty(big, "scale", Vector2.ONE, 0.45).SetTrans(Tween.TRANS_BACK).SetEase(Tween.EASE_OUT);
            tw.TweenProperty(big, "modulate:a", 1.0, 0.25);
            box.Visible = false;
            _end_at = _time + 1.4;
        }

        public void _ShowCard()
        {
            // TRAINING COMPLETE, the gold (once), CONTINUE
            bool pays = mode != null && mode.TutorialPays();
            var card = new PanelContainer();
            card.AddThemeStyleboxOverride("panel", _Box(new Color(0.04, 0.06, 0.15, 0.96), GOLD, 14, 12));
            card.Name = "Card";
            end_layer.AddChild(card);
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 6);
            v.Alignment = BoxContainer.ALIGNMENT_CENTER;
            card.AddChild(v);
            var hd = _Label(v, GD.Fmt("TRAINING %d COMPLETE", which), 18, GOLD);
            hd.HorizontalAlignment = HorizontalAlignment.Center;
            var sub = _Label(v, (which == 1 ? "You've learnt the basics -- the 5v5 battle training is next." : "You're ready for a real match."), 12, Color.FromCode("#d8d0c0"));
            sub.HorizontalAlignment = HorizontalAlignment.Center;
            if (pays)
            {
                var g = _Label(v, GD.Fmt("+%d GOLD", Eco.TUTORIAL_GOLD), 20, Color.FromCode("#ffd65a"));
                g.HorizontalAlignment = HorizontalAlignment.Center;
            }
            var b = new Button();
            b.Text = "CONTINUE";
            b.FocusMode = Control.FOCUS_NONE;
            b.CustomMinimumSize = new Vector2(200, 40);
            b.AddThemeFontOverride("font", VisualTheme.BOLD_FONT);
            b.AddThemeFontSizeOverride("font_size", 16);
            var bs = new StyleBoxFlat();
            bs.BgColor = Color.FromCode("#e8a530");
            bs.BorderColor = Color.FromCode("#ffe9a6");
            bs.SetBorderWidthAll(2);
            bs.SetCornerRadiusAll(10);
            foreach (var st in new[] { "normal", "hover", "pressed", "focus" })
                b.AddThemeStyleboxOverride(st, bs);
            b.AddThemeColorOverride("font_color", Color.FromCode("#3a1c00"));
            b.SetMeta("action_key", "training_continue");
            b.Pressed += () =>
            {
                voice.Stop();
                if (mode != null)
                    mode.FinishTutorial();
            };
            var cc = new CenterContainer();
            cc.AddChild(b);
            v.AddChild(cc);
            card.ResetSize();
            card.Position = new Vector2(Size.x * 0.5 - card.Size.x * 0.5, Size.y * 0.36 + 52.0);
        }

        // ---------------- layout ----------------
        public void _Layout()
        {
            if (bar == null)
                return;
            if (hold_kind == "tour" || phase == "over")
            {
                var w = GD.Minf(560.0, Size.x - 40.0);
                bar.CustomMinimumSize = new Vector2(w, 0);
                bar.ResetSize();
                bar.Position = new Vector2(Size.x * 0.5 - w * 0.5, Size.y - bar.Size.y - 12.0);
            }
            else
            {
                // the top middle: between the map's column and the box
                var left = 156.0;
                var right = Size.x - 222.0;
                var w2 = GD.Clampf(right - left, 280.0, 470.0);
                bar.CustomMinimumSize = new Vector2(w2, 0);
                bar.ResetSize();
                bar.Position = new Vector2(left + GD.Maxf(0.0, (right - left - w2) * 0.5), 58.0);
            }
            var bw = 204.0;
            box.CustomMinimumSize = new Vector2(bw, 0);
            box.ResetSize();
            box.Position = new Vector2(Size.x - bw - 8.0, 54.0);
            if (map != null && map.Visible)
            {
                var ms = GD.Minf(Size.y - bar.Size.y - 40.0, 300.0);
                map.Size = new Vector2(ms, ms);
                map.Position = new Vector2(Size.x * 0.5 - ms * 0.5, GD.Maxf(8.0, (Size.y - bar.Size.y - 20.0 - ms) * 0.5));
                skip_btn.Position = new Vector2(map.Position.x + ms + 12.0, map.Position.y);
            }
        }

        // ---------------- guidance ----------------
        public GDict Guide()
        {
            // what to point at now: "pos" (a world point, its "label"), "button" (a HUD button), "learn" (a + to tap), "rect"
            // (a HUD rect: the quick-buy), "stick"
            var me = _Me();
            if (me == null || phase != "play" || hold_kind != "")
                return new GDict();
            var t = (int)me.team;
            var et = 1 - t;
            switch (StepId())
            {
                case "move":
                {
                    var g = GDict.Of("pos", _goal, "label", "FOLLOW KAEL", "route", true);
                    if (me.pos.DistanceTo(_Side(t, P_START)) < 2.0)
                        g["stick"] = true;
                    return g;
                }
                case "minions":
                {
                    Unit best = null;
                    foreach (var id in _Alive(_wave))
                    {
                        Unit m = sim.by_id[GD.Str(id)];
                        if (best == null || m.pos.DistanceTo(me.pos) < best.pos.DistanceTo(me.pos))
                            best = m;
                    }
                    if (best == null)
                        return new GDict();
                    return GDict.Of("pos", best.pos, "label", "ENEMY MINIONS", "small", true, "button", "attack");
                }
                case "learn":
                case "learn2":
                case "upgrade":
                case "ult":
                {
                    var want = "";
                    foreach (var sp in hud.LearnSpots(me))
                    {
                        var sl = GD.Str(sp["slot"]);
                        if (StepId() == "ult" && sl != "r")
                            continue;
                        if (StepId() == "upgrade" && sim.moba.Rank(me, sl) < 1)
                            continue;
                        if (StepId() == "learn2" && sim.moba.Rank(me, sl) >= 1)
                            continue;
                        want = sl;
                        break;
                    }
                    return want != "" ? GDict.Of("learn", want) : new GDict();
                }
                case "hero":
                case "combo":
                case "ult_use":
                {
                    Unit near = null;
                    foreach (var id in _Alive(foes))
                    {
                        Unit f = sim.by_id[GD.Str(id)];
                        if (near == null || f.pos.DistanceTo(me.pos) < near.pos.DistanceTo(me.pos))
                            near = f;
                    }
                    if (near == null)
                        return new GDict();
                    var gi = GDict.Of("pos", near.pos, "label", "ENEMY HERO", "small", true);
                    if (StepId() == "ult_use" && !_ult_used && sim.moba.UltReady(me))
                        gi["button"] = "ult";
                    else if (StepId() == "hero")
                        gi["button"] = _SkillButton(me);
                    return gi;
                }
                case "shop":
                {
                    GArray qr = hud.QuickRects(me);
                    return !qr.IsEmpty() && !_bought ? GDict.Of("rect", qr[0]["r"].As<Rect2>()) : new GDict();
                }
                case "tower1":
                case "tower3":
                {
                    if (_tw == null || (bool)_tw.dead)
                        return new GDict();
                    var gt = GDict.Of("pos", _tw.p, "label", "ENEMY TOWER", "ring", 2.6, "lift", 7.0, "route", me.pos.DistanceTo(_tw.p) > 16.0);
                    if (sim.moba.InTowerRange(_tw, me.pos) && GD.Str(_tw.target) != GD.Str(me.id))
                        gt["button"] = "attack";
                    return gt;
                }
                case "king":
                {
                    Vector2 kp = sim.moba.KingPos(et);
                    return GDict.Of("pos", kp, "label", "ENEMY KING", "ring", 2.2, "lift", 5.0, "route", me.pos.DistanceTo(kp) > 14.0);
                }
                case "go":
                    return GDict.Of("pos", _goal, "label", "FOLLOW KAEL", "route", true);
                case "m1":
                case "m2":
                case "m3":
                case "m4":
                {
                    var gb = new GDict();
                    if (_time < (double)_guide_until.Get("recall", -1.0) && !sim.Recalling(me))
                        gb["button"] = "recall";
                    else if (_time < (double)_guide_until.Get("shop", -1.0))
                    {
                        GArray qr2 = hud.QuickRects(me);
                        if (!qr2.IsEmpty())
                            gb["rect"] = qr2[0]["r"];
                    }
                    var target = _MissionTarget(me, t, et);
                    if (target != Vector2.INF && me.pos.DistanceTo(target) > 18.0)
                    {
                        gb["pos"] = target;
                        gb["label"] = StepId() == "m4" ? "ENEMY KING" : "ENEMY TOWER";
                        gb["lift"] = 7.0;
                        gb["ring"] = 2.6;
                        gb["faint"] = true;
                    }
                    return gb;
                }
            }
            return new GDict();
        }

        public string _SkillButton(Unit me)
        {
            foreach (var b in hud._Buttons())
            {
                var sl = GD.Str(SiegeHud.SLOT_OF.Get(GD.Str(b["id"]), ""));
                if (GArray.Of("q", "w", "e").Has(sl) && sim.moba.Rank(me, sl) >= 1)
                    return GD.Str(b["id"]);
            }
            return "attack";
        }

        public Vector2 _MissionTarget(Unit me, int t, int et)
        {
            if (StepId() == "m4")
                return sim.moba.KingOpen(et) ? sim.moba.KingPos(et) : Vector2.INF;
            var tier = GD.Int(StepId().Substr(1));
            var lane = Moba.POST_LANE.TryGetValue(GD.Str(me.post != "" ? me.post : "mid"), out var pl) ? pl : 1;
            var best = Vector2.INF;
            var bd = GD.INF;
            foreach (var tw in sim.moba.towers)
            {
                if ((int)tw.team != et || (bool)tw.dead || (int)tw.tier != tier || !sim.moba.Vulnerable(tw))
                    continue;
                double d = me.pos.DistanceTo(tw.p) - ((int)tw.lane == lane ? 40.0 : 0.0);
                if (d < bd)
                {
                    bd = d;
                    best = tw.p;
                }
            }
            return best;
        }

        public void _UpdatePath(double delta)
        {
            _path_clock -= delta;
            if (_path_clock > 0.0)
                return;
            _path_clock = 0.4;
            var g = Guide();
            var me = _Me();
            _path = g.Has("pos") && ((bool)g.Get("route", false) || (bool)g.Get("faint", false)) && me != null ? sim.FindPath((int)me.team, me.pos, g["pos"].V2) : new List<Vector2>();
        }

        public Vector3 _W(Vector2 p, double lift = 0.15)
        {
            return new Vector3(p.x, Sim.HeightAt(p) + lift, p.y);
        }

        public void _Plate(Vector2 center, string text, int fs = 13)
        {
            Font font = VisualTheme.BOLD_FONT;
            var w = font.GetStringSize(text, HorizontalAlignment.Left, -1, fs).x + 18.0;
            var r = new Rect2(center.x - w * 0.5, center.y - 12, w, 24);
            DrawRect(r.Grow(2), INK);
            DrawRect(r, new Color(0.12, 0.09, 0.03, 0.95));
            DrawRect(new Rect2(r.position, new Vector2(r.size.x, 3)), GOLD);
            DrawString(font, new Vector2(r.position.x + 9, r.position.y + 17), text, HorizontalAlignment.Left, -1, fs, Color.WHITE);
        }

        public void _Arrow(Vector2 tip, double s, bool up = false)
        {
            var k = up ? -1.0 : 1.0;
            var pts = new List<Vector2> { tip, tip + new Vector2(-20, -24 * k) * s, tip + new Vector2(-8, -24 * k) * s, tip + new Vector2(-8, -46 * k) * s,
                tip + new Vector2(8, -46 * k) * s, tip + new Vector2(8, -24 * k) * s, tip + new Vector2(20, -24 * k) * s };
            var c = Vector2.ZERO;
            foreach (var q in pts)
                c += q;
            c /= pts.Count;
            var @out = new List<Vector2>();
            foreach (var q in pts)
                @out.Add(c + (q - c) * 1.18);
            DrawColoredPolygon(@out, INK);
            DrawColoredPolygon(pts, GOLD);
        }

        public void _Hand(Vector2 tip)
        {
            // Honor of Kings' hand: a white glove, its finger pressing on the spot
            var press = 0.5 + 0.5 * Math.Sin(_time * 6.0);
            var o = tip + new Vector2(4.0, 6.0) + new Vector2(5.0, 7.0) * press;
            var f1 = o + new Vector2(10.0, 24.0);
            var palm = o + new Vector2(19.0, 40.0);
            for (int pass_ = 0; pass_ < 2; pass_++)
            {
                var col = pass_ == 0 ? INK : new Color(1, 1, 1, 0.97);
                var g = pass_ == 0 ? 3.0 : 0.0;
                DrawLine(o, f1, col, 12.0 + g * 2.0, true);
                DrawCircle(o, 6.0 + g, col);
                DrawCircle(palm, 15.0 + g, col);
                DrawCircle(palm + new Vector2(9.0, -10.0), 7.0 + g, col);
                DrawCircle(palm + new Vector2(15.0, -3.0), 6.5 + g, col);
                DrawLine(palm + new Vector2(-10.0, -2.0), palm + new Vector2(-17.0, -12.0), col, 9.0 + g * 2.0, true);
                DrawCircle(palm + new Vector2(-17.0, -12.0), 4.5 + g, col);
            }
            DrawArc(tip, 10.0 + 10.0 * (1.0 - press), 0.0, GD.TAU, 32, new Color(1, 1, 1, 0.55 * press), 3.0, true);
        }

        protected override void _Draw()
        {
            if (sim == null || phase == "wait")
                return;
            var me = _Me();
            if (me == null)
                return;
            _DrawBubble();
            if (hold_kind == "towers")
                _DrawTowerCard();
            if (phase != "play" || hold_kind != "")
                return;
            var g = Guide();
            var pulse = 0.5 + 0.5 * Math.Sin(_time * 5.0);
            if (g.Has("stick"))
            {
                var @base = new Vector2(GD.Maxf(215.0, Size.x * 0.27), Size.y - 112.0);     // (right of the quick-buy)
                DrawCircle(@base, 44.0, new Color(1, 1, 1, 0.08));
                DrawArc(@base, 44.0, 0.0, GD.TAU, 48, new Color(GOLD, 0.7), 3.0, true);
                var thumb = @base + Vector2.FromAngle(_time * 2.2) * 24.0;
                DrawCircle(thumb, 16.0, INK);
                DrawCircle(thumb, 13.0, GOLD);
                _Hand(thumb);
                _Plate(@base + new Vector2(0, -62), "DRAG TO MOVE");
            }
            if (g.Has("button") && GD.Str(g["button"]) != "")
            {
                foreach (var b in hud._Buttons())
                {
                    if (GD.Str(b["id"]) == GD.Str(g["button"]))
                    {
                        double rr = (double)b["r"] + 8.0 + 6.0 * pulse;
                        DrawArc(b["c"].V2, rr + 3.0, 0.0, GD.TAU, 48, INK, 8.0, true);
                        DrawArc(b["c"].V2, rr, 0.0, GD.TAU, 48, GOLD, 5.0, true);
                        _Hand(b["c"].V2);
                    }
                }
            }
            if (g.Has("learn") && GD.Str(g["learn"]) != "")
            {
                foreach (var sp in hud.LearnSpots(me))
                {
                    if (GD.Str(sp["slot"]) == GD.Str(g["learn"]))
                    {
                        DrawArc(sp["c"].V2, 20.0 + 6.0 * pulse, 0.0, GD.TAU, 40, GOLD, 4.0, true);
                        _Hand(sp["c"].V2);
                        _Plate(sp["c"].V2 + new Vector2(-70.0, -34.0), "TAP +");
                    }
                }
            }
            if (g.Has("rect"))
            {
                Rect2 r = g["rect"].As<Rect2>().Grow(4.0 + 3.0 * pulse);
                DrawRect(r.Grow(2.0), INK, false, 5.0);
                DrawRect(r, GOLD, false, 3.5);
                _Hand(new Vector2(r.End.x - 10.0, r.GetCenter().y));
            }
            if (!g.Has("pos"))
                return;
            Vector2 tgt = g["pos"].V2;
            bool faint = (bool)g.Get("faint", false);
            var pts = new List<Vector2> { me.pos };
            pts.AddRange(_path);
            pts.Add(tgt);
            if ((bool)g.Get("route", false) || faint)
            {
                // the dotted path, marching toward the target (Honor of Kings' "Follow me!")
                var step_len = 1.2;
                var along = GD.Fmod(_time * 2.4, step_len);
                var walked = 0.0;
                for (int i = 0; i < pts.Count - 1; i++)
                {
                    Vector2 a = pts[i];
                    Vector2 b2 = pts[i + 1];
                    double seg = a.DistanceTo(b2);
                    while (along < seg && walked + along < 36.0)
                    {
                        var wq = _W(a.Lerp(b2, along / GD.Maxf(seg, 0.001)));
                        if (hud.on_screen(wq))
                        {
                            Vector2 sq = hud.project(wq);
                            DrawCircle(sq, 6.0, new Color(INK, faint ? 0.5 : 0.9));
                            DrawCircle(sq, 4.2, new Color(GOLD, faint ? 0.55 : 1.0));
                        }
                        along += step_len;
                    }
                    along -= seg;
                    walked += seg;
                }
            }
            var route = 0.0;
            Vector2 guide_p = tgt;
            var got = false;
            for (int i = 0; i < pts.Count - 1; i++)
            {
                double seg2 = pts[i].DistanceTo(pts[i + 1]);
                if (!got && route + seg2 >= 8.0)
                {
                    guide_p = pts[i].Lerp(pts[i + 1], (8.0 - route) / GD.Maxf(seg2, 0.001));
                    got = true;
                }
                route += seg2;
            }
            var label = GD.Str(g.Get("label", "HERE")) + ((bool)g.Get("small", false) || route < 5.0 ? "" : GD.Fmt("  %d m", (int)GD.Round(route)));
            if (hud.on_screen(_W(tgt, 0.0)))
            {
                var ring = new List<Vector2>();
                double rad = (double)g.Get("ring", (bool)g.Get("small", false) ? 0.9 : 1.4);
                for (int k = 0; k < 33; k++)
                    ring.Add(hud.project(_W(tgt + Vector2.FromAngle(GD.TAU * k / 32.0) * rad, 0.08)));
                DrawPolyline(ring, INK, 7.0, true);
                DrawPolyline(ring, GOLD, 4.0, true);
                if (!faint)
                {
                    Vector2 tip = hud.project(_W(tgt, (double)g.Get("lift", 2.4))) + new Vector2(0, -8.0 * pulse);
                    var above = new Rect2(tip.x - 90.0, tip.y - 80.0, 180.0, 80.0);        // (the arrow and its plate, over the target)
                    bool clear = tip.y - 90.0 > (bar.Visible ? bar.GetRect().End.y + 6.0 : 60.0)
                        && !(box.Visible && box.GetRect().Grow(6.0).Intersects(above));
                    if (clear)
                    {
                        _Arrow(tip, 0.9);
                        _Plate(tip + new Vector2(0, -66), label);
                    }
                    else
                    {
                        Vector2 tip2 = hud.project(_W(tgt, 0.0)) + new Vector2(0, 22.0 + 8.0 * pulse);
                        _Arrow(tip2, 0.9, true);
                        _Plate(tip2 + new Vector2(0, 66), label);
                    }
                }
            }
            else
            {
                var center = Size * 0.5;
                Vector2 from_s = hud.project(_W(me.pos, 1.0));
                Vector2 to_s = hud.project(_W(guide_p, 1.0));
                var dir = (to_s - from_s).Normalized();
                if (dir == Vector2.ZERO)
                    dir = new Vector2(0, -1);
                var edge = center + dir * GD.Minf(Size.x * 0.36, Size.y * 0.28);
                var side = new Vector2(-dir.y, dir.x);
                var a2 = faint ? 0.55 : 1.0;
                DrawColoredPolygon(new[] { edge + dir * 34, edge - dir * 16 + side * 26, edge - dir * 16 - side * 26 }, new Color(INK, 0.9 * a2));
                DrawColoredPolygon(new[] { edge + dir * 28, edge - dir * 12 + side * 20, edge - dir * 12 - side * 20 }, new Color(GOLD, a2));
                if (!faint)
                    _Plate(edge - dir * 44, label);
            }
        }

        public void _DrawBubble()
        {
            // his quip over his head, a white bubble with its tail down to him
            if (_bubble == "" || _time >= _bubble_until || kael == null || !sim.Alive(kael))
                return;
            var head = _W(kael.pos, 3.4);
            if (!hud.on_screen(head))
                return;
            Vector2 p = hud.project(head);
            var text = GD.Str(LINES.Get(_bubble, ""));
            Font font = VisualTheme.BOLD_FONT;
            var fs = 13;
            var w = font.GetStringSize(text, HorizontalAlignment.Left, -1, fs).x + 22.0;
            var age = _time - (_bubble_until - 2.4);
            var k = GD.Clampf(age / 0.15, 0.0, 1.0) * GD.Clampf((_bubble_until - _time) / 0.3, 0.0, 1.0);
            var r = new Rect2(p.x - w * 0.5, p.y - 40.0, w, 28.0);
            var sb = new StyleBoxFlat();
            sb.BgColor = new Color(1, 1, 1, 0.96 * k);
            sb.BorderColor = new Color(0.1, 0.12, 0.2, 0.9 * k);
            sb.SetBorderWidthAll(2);
            sb.SetCornerRadiusAll(12);
            sb.AntiAliasing = true;
            DrawColoredPolygon(new[] { new Vector2(p.x - 8, r.End.y - 2), new Vector2(p.x + 8, r.End.y - 2), new Vector2(p.x, r.End.y + 10) }, new Color(0.1, 0.12, 0.2, 0.9 * k));
            DrawStyleBox(sb, r);
            DrawColoredPolygon(new[] { new Vector2(p.x - 6, r.End.y - 3), new Vector2(p.x + 6, r.End.y - 3), new Vector2(p.x, r.End.y + 6) }, new Color(1, 1, 1, 0.96 * k));
            DrawString(font, new Vector2(r.position.x + 11, r.position.y + 19), text, HorizontalAlignment.Left, -1, fs, new Color(0.1, 0.12, 0.22, k));
        }

        public void _DrawTowerCard()
        {
            // the towers' lesson: what each colour of its ring means, the one he's on lit
            var cur = _cur != "" ? _cur : _last;
            var rows = GArray.Of(GArray.Of("yellow", "NEAR IT", "k2_tw2"), GArray.Of("red", "SHOOTING YOU", "k2_tw3"), GArray.Of("green", "SHOOTING A MINION: ATTACK", "k2_tw6"));
            var lit_rows = GDict.Of("k2_tw2", 0, "k2_tw3", 1, "k2_tw4", 2, "k2_tw5", 2, "k2_tw6", 2, "k2_tw7", 1);
            Font font = VisualTheme.BOLD_FONT;
            var w = 300.0;
            var r = new Rect2(Size.x * 0.5 - w * 0.5, Size.y - 124.0, w, 112.0);        // (low, the tower and its ring in sight)
            DrawRect(r.Grow(2.0), INK);
            DrawRect(r, new Color(0.04, 0.06, 0.15, 0.94));
            DrawRect(new Rect2(r.position, new Vector2(r.size.x, 3)), GOLD);
            DrawString(font, r.position + new Vector2(12, 20), "A TOWER'S RING", HorizontalAlignment.Left, -1, 12, GOLD);
            for (int i = 0; i < rows.Size(); i++)
            {
                var y = r.position.y + 40.0 + 26.0 * (double)i;
                Color col = View_RING[GD.Str(rows[i][0])].As<Color>();
                bool on = (int)lit_rows.Get(cur, -1) == i;
                var c = new Vector2(r.position.x + 30.0, y);
                DrawArc(c, 10.0, 0.0, GD.TAU, 28, new Color(col, 1.0), on ? 4.0 : 2.5, true);
                DrawCircle(c, 3.5, new Color(0.8, 0.8, 0.85));
                DrawString(font, c + new Vector2(22, 5), GD.Str(rows[i][1]), HorizontalAlignment.Left, -1, on ? 13 : 12, on ? Color.WHITE : new Color(1, 1, 1, 0.6));
            }
            if (_tw != null && hud.on_screen(_W(_tw.p, 0.0)))
            {
                Vector2 tip = hud.project(_W(_tw.p, 7.0)) + new Vector2(0, -6.0 * (0.5 + 0.5 * Math.Sin(_time * 5.0)));
                if (tip.y > 60.0)
                    _Arrow(tip, 0.8);
            }
        }

        public static readonly GDict View_RING = GDict.Of("yellow", new Color(1.0, 0.85, 0.35), "red", new Color(1.0, 0.25, 0.2), "green", new Color(0.35, 1.0, 0.45));

        public void _DrawMapFx(Control c)
        {
            // the tour: on the big map, what his line is about
            if (map == null)
                return;
            var cur = _cur != "" ? _cur : _last;
            var me = _Me();
            var t = me != null ? (int)me.team : 0;
            var et = 1 - t;
            var pulse = 0.5 + 0.5 * Math.Sin(_time * 4.0);
            var lanes = new GArray();
            switch (cur)
            {
                case "k2_lanes":
                case "k2_roles":
                    lanes = GArray.Of(0, 1, 2);
                    break;
                case "k2_top":
                    lanes = GArray.Of(0);
                    break;
                case "k2_mid":
                case "k2_win1":
                    lanes = GArray.Of(1);
                    break;
                case "k2_bot":
                    lanes = GArray.Of(2);
                    break;
                case "k2_ready":
                {
                    var post = me != null ? GD.Str(me.post != "" ? me.post : "mid") : "mid";
                    if (post != "jungle")
                        lanes = GArray.Of(Moba.POST_LANE.TryGetValue(post, out var pl) ? pl : 1);
                    break;
                }
            }
            foreach (var l in lanes)
            {
                var pl = new List<Vector2>();
                foreach (var p in Moba.LANES[(int)l])
                    pl.Add(map.ToMap(p));
                c.DrawPolyline(pl, new Color(GOLD, 0.35 + 0.3 * pulse), 12.0, true);
                c.DrawPolyline(pl, new Color(1.0, 0.95, 0.7, 0.9), 3.0, true);
            }
            Font font = VisualTheme.BOLD_FONT;
            if (GArray.Of("k2_roles", "k2_top", "k2_mid", "k2_bot", "k2_jungle", "k2_ready").Has(cur))
            {
                var names = GDict.Of(0, "TOP", 1, "MID", 2, "BOTTOM");
                foreach (var l in new[] { 0, 1, 2 })
                {
                    Vector2[] pts = Moba.LANES[l];
                    Vector2 at = map.ToMap(pts[l == 1 ? (pts.Length >> 1) : (pts.Length >> 1) - 3]);
                    if (GArray.Of("k2_roles").Has(cur) || lanes.Has(l))
                        _MapTag(c, font, at, GD.Str(names[l]));
                }
            }
            if (GArray.Of("k2_jungle", "k2_roles").Has(cur))
            {
                foreach (var camp in sim.moba.camps)
                {
                    if (GArray.Of(0, 1).Has((int)camp.side))
                        c.DrawArc(map.ToMap(camp.p), 5.0 + 3.0 * pulse, 0.0, GD.TAU, 20, Color.FromCode("#c58bff"), 2.0, true);
                }
                _MapTag(c, font, map.ToMap(_Side(t, new Vector2(-34.0, 30.0))), "JUNGLE");
            }
            if (cur == "k2_minions")
            {
                foreach (var l in new[] { 0, 1, 2 })
                {
                    Vector2[] pts2 = Moba.LANES[l];
                    for (int side = 0; side < 2; side++)
                    {
                        for (int k = 0; k < 4; k++)
                        {
                            var f = GD.Fmod(_time * 0.12 + (double)k * 0.07, 0.5);
                            double u = side == 0 ? f : 1.0 - f;
                            c.DrawCircle(map.ToMap(_Along(pts2, u)), 2.6, side == t ? Color.FromCode("#4fc3ff") : Color.FromCode("#ff5a4a"));
                        }
                    }
                }
            }
            if (GArray.Of("k2_towers", "k2_win1").Has(cur))
            {
                foreach (var tw in sim.moba.towers)
                {
                    if (cur == "k2_win1" && ((int)tw.team != et || (int)tw.lane != 1))
                        continue;
                    Vector2 tp = map.ToMap(tw.p);
                    var on = true;
                    if (cur == "k2_win1")
                        on = GD.Fmod(_time * 1.5, 3.0) >= (double)((int)tw.tier - 1);
                    if (on)
                        c.DrawArc(tp, 7.0 + 3.0 * pulse, 0.0, GD.TAU, 20, GOLD, 2.5, true);
                }
            }
            if (cur == "k2_win2")
            {
                Vector2 kp = map.ToMap(sim.moba.KingPos(et));
                c.DrawArc(kp, 10.0 + 5.0 * pulse, 0.0, GD.TAU, 28, GOLD, 3.0, true);
                _MapTag(c, font, kp + (kp.x > c.Size.x * 0.5 ? new Vector2(-38, 26) : new Vector2(38, -26)), "THEIR KING");
            }
            if (cur == "k2_welcome")
            {
                _MapTag(c, font, map.ToMap(sim.moba.KingPos(t)) + new Vector2(0, -20), "US");
                _MapTag(c, font, map.ToMap(sim.moba.KingPos(et)) + new Vector2(0, 20), "THEM");
            }
        }

        public Vector2 _Along(IList<Vector2> pts, double u)
        {
            var total = 0.0;
            for (int i = 0; i < pts.Count - 1; i++)
                total += pts[i].DistanceTo(pts[i + 1]);
            var want = total * GD.Clampf(u, 0.0, 1.0);
            for (int i = 0; i < pts.Count - 1; i++)
            {
                double seg = pts[i].DistanceTo(pts[i + 1]);
                if (want <= seg)
                    return pts[i].Lerp(pts[i + 1], want / GD.Maxf(seg, 0.001));
                want -= seg;
            }
            return pts[pts.Count - 1];
        }

        public void _MapTag(Control c, Font font, Vector2 at, string text)
        {
            var w = font.GetStringSize(text, HorizontalAlignment.Left, -1, 11).x + 12.0;
            var r = new Rect2(at.x - w * 0.5, at.y - 9.0, w, 18.0);
            c.DrawRect(r, new Color(0.04, 0.05, 0.1, 0.88));
            c.DrawRect(r, new Color(GOLD, 0.9), false, 1.5);
            c.DrawString(font, new Vector2(r.position.x + 6, r.position.y + 13), text, HorizontalAlignment.Left, -1, 11, Color.WHITE);
        }
    }
}
