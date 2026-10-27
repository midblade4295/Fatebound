// Ported from godot/scripts/siege/tutorial.gd (Fatebound 0.31.222).
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
    using UI2 = Fatebound.Game.Ui2;
    using Poses = Fatebound.Game.TutorialPoses;

    // 0.31.181 THE 5V5 TUTORIAL (Kevin: "Now create a tutorial walking player through the basics of a match. Things like how
    // buying works, economy in game, trying not to die because feeds enemy team economy. Benefits of building up team
    // economy with minions and jungling ect ect. Make it voiced and make it humorous and sarcastic").
    //
    // A 5v5 against bots, made quiet (siege_mode.gd tutorial = true; begin() below): every hero but you stays at his
    // fountain ("a tea break"), no waves and no camps of their own, and you can't fall (half damage, and a floor under
    // your health). Over it, under the HUD's pause button and panels, this overlay: the Royal Herald talks -- the match
    // waits (siege_mode doesn't step it while holds()), the line typed out on his proclamation scroll as he says it, a tap
    // for the next -- then sets a task to DO in the live match, checked every frame, with guidance drawn over the world
    // (a marching dotted route, a ring and an arrow on the target, an edge arrow when it's off screen) or a TAP / HOLD ring
    // on the HUD's button. What a task needs is put there by the tutorial ("royal paperwork"): a wave each side to
    // last-hit, our Grave Archers camp, our minions walking under their tower, a hop to where it all is.
    //
    // 0.31.182 (Kevin, of the dialog: "make it so he blends into text box seamlessly" -> concept D, the scroll, "but also
    // have him doing some funny stuff with the scroll like sometimes he's laying on top of it and sometimes leaning on it"):
    // each line is written on the scroll, the Herald with it in one of eight poses (scroll_<pose>.png, ElevenLabs; their
    // parchment and its clear part in tutorial_poses.gd): holding it open, lying on it, leaning on it, sitting on it with
    // his tea, peeking over it, asleep on it, standing on it with a pointer, hanging off it. The scroll as wide as it can be
    // with all of him on the screen; the line in the clear part of its parchment, the biggest type that fits.
    // VOICE: assets/vo/tutorial/<id>.ogg, the Herald's voice (ElevenLabs; art_sources/tutorial: script.json, the prompts;
    // tools/build_tutorial_assets.py). The captions here are script.json's lines (tests/tutorial_test.gd checks).
    // 0.31.199 (Kevin: "change the voice lines in the battle training now so the trainer doesn't introduce himself twice
    // since players met him in the UI training. Also in training talk about how to teleport back to base and it heals
    // you"): he opens knowing you (scripts/app/herald_intro.gd introduced him), the Rift's line calls back to the King's
    // chair, and the recall's lines say HOME teleports you back to the castle and the castle heals you.
    // 0.31.206 (Kevin: "Also teach players about how wards work in the training"): after the jungle, WARD -- the fog of war
    // (you see only what your side's heroes, minions, towers and wards see), the brush (whoever's in it is hidden from
    // outside unless a ward of yours is in it too), then walk into the brush nearest you and tap WARD; done: a ward watches
    // 90 s unseen by the enemy, you carry two and they come back (moba_vision.gd). Voiced like the rest.
    public class Tutorial : Control
    {
        public const string VO_DIR = "res://assets/vo/tutorial/";
        public const string POSE_PATH = "res://assets/ui/tutorial/scroll_%s.png";
        public static readonly Color INK_TEXT = Color.FromCode("#3e2610");             // (the scroll's writing)
        public static readonly Color INK_HINT = Color.FromCode("#8c241e");
        public const double SCROLL_SIDE = 18.0;                      // the parchment at most the screen less this each side
        public const double SCROLL_FIT = 4.0;                        // ...and all of the Herald on the screen, this from its edges
        public const double SCROLL_BOTTOM = 32.0;                    // the parchment's foot this above the screen's (TAP TO CONTINUE under it)
        public const double SCROLL_TALL = 0.72;                      // 0.31.216: the Herald and his parchment no taller than this of the screen
        public const int LINE_GAP = -3;                              // the writing's lines a little closer than the font's own
        public static readonly int[] TEXT_PX = { 17, 16, 15, 14, 13, 12 };
        public const double TYPE_CPS = 42.0;
        public const double VOICE_GAIN = 0.55;          // x master (the Herald's match calls: 0.5)
        public const int LH_GOAL = 2;
        public const int TOWER_HITS = 3;
        public const double SHIELD_FOR = 0.6;
        public const double HP_FLOOR = 0.3;             // (you can't fall in the tutorial)
        public const double TAKE = 0.5;                 // ...and take half damage
        public static readonly Vector2 LANE_AT = new Vector2(3.0, 24.0);          // (blue's; red's the point mirror) behind our minions, out of our tower's reach
        public static readonly Vector2 LANE_OURS = new Vector2(0.0, 19.0);        // where our wave is put down, walking north
        public static readonly Vector2 LANE_THEIRS = new Vector2(0.0, -3.0);      // ...theirs, walking south: they meet near the middle
        public static readonly List<string> LANE_KINDS = new List<string> { "melee", "melee", "melee", "caster", "caster", "caster" };
        public static readonly List<string> TOWER_KINDS = new List<string> { "melee", "melee", "melee", "melee", "caster", "caster" };
        public const double CAMP_WEAK = 0.6;            // the tutorial's Grave Archers: "a bit under the weather"
        public const double WARD_NEAR = 14.0;           // 0.31.206: the ward step's brush farther than this -> a hop to WARD_HOP m short of it
        public const double WARD_HOP = 7.0;

        // Each step: talk (lines before the task), task (shown as the objective), done (lines once it's done). A line is
        // [voice id, caption, the Herald's pose]. "@pay": the last line, by whether the tutorial's gold is still to be paid.
        public static readonly GArray STEPS = GArray.Of(
            GDict.Of("id", "intro", "talk", GArray.Of(
                GArray.Of("t5_intro_1", "Oh, it's you again. I'd introduce myself, but we've done that, and once was plenty. Welcome to your first battle. It's only practice. The enemy promised to go easy on you. They laughed, but they promised.", "hold"),
                GArray.Of("t5_intro_2", "This is the Rift. Remember the King and his very comfortable chair? Ours is behind us. Theirs is at the far end, looking smug. Knock him off it and we win. Simple. You'd be amazed.", "lying"))),
            GDict.Of("id", "move", "talk", GArray.Of(
                GArray.Of("t5_move_1", "Let's begin with walking. Drag your thumb on the left side of the screen. You can do it. I believe in you. Mildly.", "leaning")),
                "task", "Drag on the left side of the screen to walk",
                "done", GArray.Of(GArray.Of("t5_move_done", "Legs! Working legs. The bards are already writing a song about it. A short one.", "sitting"))),
            GDict.Of("id", "lane", "talk", GArray.Of(
                GArray.Of("t5_lane_1", "Both castles send waves of minions down every lane. They march, they fight, they die. Nobody writes them songs either.", "napping"),
                GArray.Of("t5_lane_2", "Here's the secret: a minion pays its gold only to whoever lands the killing blow. That's a last hit. Softening it up earns you nothing but sore arms.", "peeking"),
                GArray.Of("t5_lane_3", "I've had a wave delivered. Wait until an enemy minion is nearly dead, then finish it off. Two last hits, please. I'll be counting.", "pointing")),
                "task", "Land the killing blow on 2 enemy minions",
                "done", GArray.Of(GArray.Of("t5_lh_done", "Gold! Funny how it turns up when you actually finish things. There's a life lesson in there. I shan't spell it out.", "hanging"))),
            GDict.Of("id", "eco", "talk", GArray.Of(
                GArray.Of("t5_eco_1", "Gold is everything here. Minions, monsters, towers and enemy heroes all pay. Even standing about pays a trickle, which explains a great many recruits.", "napping"),
                GArray.Of("t5_eco_2", "And it's not just your gold. The whole team's gold decides who wins the big fights. Tap the score bar at the top to see everyone's.", "pointing")),
                "task", "Tap the score bar at the top",
                "done", GArray.Of(GArray.Of("t5_eco_done", "Our gold, their gold, and who's slacking. Close it when you've finished judging people. I never have.", "sitting"))),
            GDict.Of("id", "recall", "talk", GArray.Of(
                GArray.Of("t5_recall_1", "Pockets full, or health running low? Same answer: go home. Tap HOME and you teleport straight back to our castle. Stand still for six seconds, though. Anything that hits you cancels it. So perhaps not next to the enemy.", "peeking")),
                "task", "Tap HOME, then stand still for 6 seconds",
                "done", GArray.Of(GArray.Of("t5_recall_done", "Home sweet castle. Stand here and you heal. Quickly, and for free. It's the only free thing in the kingdom. The shop serves you here too. Or while you're dead. Retail is grim.", "leaning"))),
            GDict.Of("id", "shop", "talk", GArray.Of(
                GArray.Of("t5_shop_1", "Tap SHOP and buy an item. Items make you hit harder, live longer, and look slightly less doomed. Can't decide? The shop suggests things. Like me, but less charming.", "lying")),
                "task", "Open the SHOP and buy an item",
                "done", GArray.Of(GArray.Of("t5_shop_done", "A purchase! Remember: gold in your pocket does nothing. Gold turned into swords does a great deal.", "hold"))),
            GDict.Of("id", "abilities", "talk", GArray.Of(
                GArray.Of("t5_ab_1", "Now, your tricks. Q, W and E are your abilities, and R, your ultimate, arrives at level six. I've had you promoted to level three. Paperwork. Don't ask.", "peeking"),
                GArray.Of("t5_ab_2", "Hold Q to raise your shield. Tap W to bash, and E to rally. Each level also brings an upgrade card, so pick one. Try everything, so I know it all works.", "lying")),
                "task", "Hold Q, tap W, tap E, and pick your upgrades",
                "done", GArray.Of(GArray.Of("t5_ab_done", "A shield, a shove and a pep talk. Very knightly. Very you.", "leaning"))),
            GDict.Of("id", "jungle", "talk", GArray.Of(
                GArray.Of("t5_jg_1", "Between the lanes lies the jungle, full of monsters. Rude ones. Clear a camp and it pays gold and experience. Some even leave a buff that makes you stronger.", "napping"),
                GArray.Of("t5_jg_2", "Our Grave Archers are just over there. Go and clear the camp. They do hit back, so keep that shield handy.", "hanging")),
                "task", "Clear the Grave Archers camp",
                "done", GArray.Of(GArray.Of("t5_jg_done", "Cleared! That's the jungle: a team that takes its camps out-earns one that doesn't. Free gold. Well. Paid for in bruises.", "hold"))),
            GDict.Of("id", "ward", "talk", GArray.Of(
                GArray.Of("t5_ward_1", "See that grey murk out there? That's the fog of war. We only see what our heroes, minions, towers and wards can see. Anything else could be an enemy. Or a very large bush.", "peeking"),
                GArray.Of("t5_ward_2", "Speaking of bushes: that tall grass is brush. Anyone in it is invisible from outside, unless there's a ward in there with them. Walk into the brush, then tap WARD.", "pointing")),
                "task", "Walk into the brush and tap WARD",
                "done", GArray.Of(GArray.Of("t5_ward_done", "A ward! It watches for ninety seconds, and the enemy can't see it. You carry two, and they grow back. Put them where trouble comes from. Which, around here, is everywhere.", "leaning"))),
            GDict.Of("id", "tower", "talk", GArray.Of(
                GArray.Of("t5_tw_1", "Now, towers. They guard each lane and shoot whatever wanders in. Only basic attacks hurt them, and only from inside their range. No sniping. I checked.", "peeking"),
                GArray.Of("t5_tw_2", "Golden rule: minions first. A tower shoots minions before heroes, unless you hit one of their heroes right under it. More paperwork, and here we are. Hit it three times.", "lying")),
                "task", "Hit the enemy tower 3 times with ATTACK",
                "done", GArray.Of(GArray.Of("t5_tw_done", "Lovely. Keep that up and it falls. Every tower pays the whole team, and brings us one step closer to their King.", "leaning"))),
            GDict.Of("id", "die", "talk", GArray.Of(
                GArray.Of("t5_die_1", "Now, the important bit. Dying. Every time you die, the enemy gets three hundred gold. Plus your bounty, if you've been showing off.", "pointing"),
                GArray.Of("t5_die_2", "That gold buys them swords. Swords they then use on you. You see the problem. Dying isn't just embarrassing. It's a donation.", "hanging"),
                GArray.Of("t5_die_3", "So when your health runs low, back off and recall. A living coward earns more than a dead hero. I should know. I'm still here.", "peeking"),
                GArray.Of("t5_die_4", "And if you take down someone with a big bounty, that's a shutdown, and all that gold is yours. Revenge is so much nicer when it pays.", "lying"))),
            GDict.Of("id", "win", "talk", GArray.Of(
                GArray.Of("t5_win_1", "To win, push down a lane: outer tower, inner tower, gate tower, then the gate. Then the two towers by their King, then the King himself. He's large, grumpy, and hits back.", "peeking"),
                GArray.Of("t5_win_2", "And do it together. Five heroes with full pockets beat one brave idiot every time. I've watched it happen. Repeatedly.", "napping"))),
            GDict.Of("id", "end", "talk", GArray.Of(
                GArray.Of("t5_end_1", "That's the lot. You're ready. Well. Readier.", "sitting"),
                GArray.Of("@pay", "", "")))
        );
        public static readonly GArray END_GOLD = GArray.Of("t5_end_gold", "Here's two hundred and fifty gold for sitting through all that. Go on. Win something. Make me look good.", "hold");
        public static readonly GArray END_NOGOLD = GArray.Of("t5_end_nogold", "No pay this time, I'm afraid. You've had your gold already, and the treasury has a long memory. Go on. Win something.", "hanging");

        public SiegeMode mode;                      // siege_mode.gd
        public SiegeSim sim;
        public SiegeHud hud;
        public int step = 0;
        public string phase = "wait";               // wait (the match warming up) -> talk -> task -> done -> next step ... -> finished
        public int line = 0;
        public double shown = 0.0;                  // characters typed out
        public bool finished = false;
        public AudioStreamPlayer voice;
        public GArray lines_said = new GArray();    // (tests) every line id shown, in order
        public double _time = 0.0;
        public Vector2 _start = Vector2.ZERO;
        public int _lh0 = 0;
        public List<string> _red = new List<string>();          // the lane step's enemy minions
        public List<string> _ours = new List<string>();         // the tower step's minions of ours
        public Camp _camp = null;
        public Tower _tw = null;
        public int _tw_hits = 0;
        public Brush _brush = null;   // 0.31.206: the ward step's brush patch (moba_vision.gd brushes: {id, p, r})
        public double _shield_t = 0.0;
        public bool _w_done = false;
        public bool _e_done = false;
        public string _note = "";                   // a line under the objective for a moment ("Interrupted!")
        public double _note_until = 0.0;
        public List<Vector2> _path = new List<Vector2>();
        public double _path_clock = 0.0;
        public GDict _pose_tex = new GDict();
        public string pose = "";                    // the Herald's pose showing
        // the talk: a dimmer that takes the tap, the Herald with his scroll, the writing on it
        public Control dim;
        public TextureRect scroll;
        public Label text_label;
        public Label hint_label;
        public Label count_label;
        // the task: the objective card
        public PanelContainer card;
        public Label task_label;
        public Label note_label;

        protected override void _Ready()
        {
            MouseFilter = Control.MOUSE_FILTER_IGNORE;
            SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            voice = new AudioStreamPlayer();
            voice.Bus = "Master";
            AddChild(voice);
            var d = new Dimmer();
            d.tut = this;
            dim = d;
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            AddChild(dim);
            scroll = new TextureRect();
            scroll.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            scroll.StretchMode = TextureRect.STRETCH_SCALE;
            scroll.TextureFilter = TextureFilterMode.LinearWithMipmaps;
            scroll.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(scroll);
            text_label = new Label();
            text_label.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            text_label.AddThemeFontOverride("font", VisualTheme.BOLD_FONT);
            text_label.AddThemeFontSizeOverride("font_size", 16);
            text_label.AddThemeColorOverride("font_color", INK_TEXT);
            text_label.AddThemeConstantOverride("line_spacing", LINE_GAP);
            text_label.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(text_label);
            hint_label = _InkLabel("TAP TO CONTINUE  >", 12, VisualTheme.GOLD);
            hint_label.HorizontalAlignment = HorizontalAlignment.Right;
            count_label = _InkLabel("", 11, new Color(1, 1, 1, 0.55));
            card = new PanelContainer();
            card.AddThemeStyleboxOverride("panel", _Box(new Color(0.04, 0.06, 0.15, 0.9), VisualTheme.GOLD_DARK, 12, 8));
            card.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            card.AnchorLeft = 0.0;
            card.AnchorRight = 1.0;
            card.OffsetLeft = 10;
            card.OffsetRight = -10;
            AddChild(card);
            var cv = new VBoxContainer();
            cv.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            cv.AddThemeConstantOverride("separation", 1);
            card.AddChild(cv);
            var head = new Label();
            head.Text = "THE HERALD WANTS YOU TO";
            head.AddThemeFontOverride("font", VisualTheme.BOLD_FONT);
            head.AddThemeFontSizeOverride("font_size", 10);
            head.AddThemeColorOverride("font_color", VisualTheme.GOLD);
            head.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            cv.AddChild(head);
            task_label = new Label();
            task_label.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            task_label.AddThemeFontOverride("font", VisualTheme.BOLD_FONT);
            task_label.AddThemeFontSizeOverride("font_size", 15);
            task_label.AddThemeColorOverride("font_color", Color.FromCode("#fff4d6"));
            task_label.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            cv.AddChild(task_label);
            note_label = new Label();
            note_label.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            note_label.AddThemeFontOverride("font", VisualTheme.BOLD_FONT);
            note_label.AddThemeFontSizeOverride("font_size", 12);
            note_label.AddThemeColorOverride("font_color", Color.FromCode("#9ff6ef"));
            note_label.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            cv.AddChild(note_label);
            _Layout();
        }

        public static StyleBoxFlat _Box(Color bg, Color rim, int radius, int pad)
        {
            var sb = new StyleBoxFlat();
            sb.BgColor = bg;
            sb.BorderColor = rim;
            sb.SetBorderWidthAll(2);
            sb.SetCornerRadiusAll(radius);
            sb.ContentMarginLeft = pad + 2;
            sb.ContentMarginRight = pad + 2;
            sb.ContentMarginTop = pad;
            sb.ContentMarginBottom = pad;
            sb.ShadowColor = new Color(0, 0, 0, 0.45);
            sb.ShadowSize = 6;
            return sb;
        }

        public Label _InkLabel(string text, int px, Color col)
        {
            var l = new Label();
            l.Text = text;
            l.AddThemeFontOverride("font", VisualTheme.BOLD_FONT);
            l.AddThemeFontSizeOverride("font_size", px);
            l.AddThemeColorOverride("font_color", col);
            l.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(l);
            return l;
        }

        // ---------------- the scroll ----------------
        public Texture2D PoseTex(string p)
        {
            if (!_pose_tex.Has(p))
            {
                var path = GD.Fmt(POSE_PATH, p);
                _pose_tex[p] = ResourceLoader.Exists(path) ? Var.Of(ResourceLoader.Load<Texture2D>(path)) : Var.Nil;
            }
            return _pose_tex[p].As<Texture2D>();
        }

        public static GDict ScrollRects(string p, Vector2 view)
        {
            // where pose p's art goes on a screen of size view: "art" (the whole of it), "parch", "text" (the clear part, the
            // writing's), "k" (its scale). The parchment as wide as the screen less SCROLL_SIDE each side, unless that would put
            // some of the Herald off the screen; centred on it, then nudged in; its foot SCROLL_BOTTOM above the screen's.
            GDict g = Poses.POSES.Get(p, Poses.POSES["hold"]).D;
            Vector2 sz = g["size"].V2;
            Rect2 pr = g["parch"].As<Rect2>();
            Rect2 tr = g["text"].As<Rect2>();
            var k = GD.Minf((view.x - 2.0 * SCROLL_SIDE) / pr.size.x, (view.x - 2.0 * SCROLL_FIT) / sz.x);
            k = GD.Minf(k, view.y * SCROLL_TALL / sz.y);         // (0.31.216: landscape -- no taller than this of the screen, him and all)
            var x = view.x * 0.5 - (pr.position.x + pr.size.x * 0.5) * k;
            x = sz.x * k <= view.x - 2.0 * SCROLL_FIT ? GD.Clampf(x, SCROLL_FIT - 0.0, view.x - SCROLL_FIT - sz.x * k) : x;
            var y = GD.Minf(view.y - SCROLL_BOTTOM - pr.End.y * k, view.y - 2.0 - sz.y * k);     // (his feet on the screen too)
            var o = new Vector2(x, y);
            return GDict.Of("art", new Rect2(o, sz * k), "parch", new Rect2(o + pr.position * k, pr.size * k), "text", new Rect2(o + tr.position * k, tr.size * k), "k", k);
        }

        public static double TextHeight(string text, double width, int px)
        {
            // the writing's height at px in that width, its lines LINE_GAP closer than the font's own
            Font font = VisualTheme.BOLD_FONT;
            var lh = font.GetHeight(px);
            var n = GD.Roundi(font.GetMultilineStringSize(text, HorizontalAlignment.Left, width, px).y / lh);
            return (double)n * lh + (double)(GD.Maxi(0, n - 1) * LINE_GAP);
        }

        public static int FitPx(string text, Vector2 box)
        {
            // the biggest of TEXT_PX that fits the line in the box
            foreach (var px in TEXT_PX)
            {
                if (TextHeight(text, box.x, px) <= box.y)
                    return px;
            }
            return (int)TEXT_PX[TEXT_PX.Length - 1];
        }

        // A full-screen shade that takes the tap moving the Herald on -- not over the HUD's pause button
        public class Dimmer : ColorRect
        {
            public Tutorial tut;
            protected override void _Ready()
            {
                MouseFilter = Control.MOUSE_FILTER_STOP;
                Color = new Color(0.0, 0.01, 0.04, 0.42);
            }
            // (_has_point: the facade's Control.has_point virtual)
            public override bool HasPoint(Vector2 p)
            {
                if (tut == null || tut.hud == null || !GD.IsInstanceValid(tut.hud.pause_btn))
                    return true;
                return !tut.hud.pause_btn.GetGlobalRect().Grow(4.0).HasPoint(GetGlobalTransform() * p);
            }
            protected override void _GuiInput(InputEvent e)
            {
                if ((e is InputEventScreenTouch && (e as InputEventScreenTouch).Pressed) || (e is InputEventMouseButton && (e as InputEventMouseButton).Pressed && (e as InputEventMouseButton).ButtonIndex == MouseButton.Left))
                {
                    AcceptEvent();
                    tut.Next();
                }
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

        // ---------------- the match, made quiet ----------------
        public void Begin(SiegeMode m)
        {
            mode = m;
            sim = m.sim;
            hud = m.hud;
            var me = _Me();
            for (int t = 0; t < 2; t++)
            {
                foreach (var hid in sim.moba.heroes[t])
                {
                    Unit h = sim.by_id.TryGetValue(hid, out var hu) ? hu : null;
                    if (h != null && GD.Str(hid) != GD.Str(me != null ? me.id : ""))
                    {
                        h.bot = false;                     // (a tea break: they stand at their fountains)
                        h.move = Vector2.ZERO;
                    }
                }
            }
            sim.moba.wave_at = GD.INF;                        // no waves but the ones put down here
            foreach (var c in sim.moba.camps)
                c.next = GD.INF;                              // no camps either (the Bone Lord and the Wyrm included)
            _start = me != null ? me.pos : Vector2.ZERO;
            _Refresh();
        }

        public Unit _Me()
        {
            // ({} when there's no such unit: null here)
            return sim != null ? (sim.by_id.TryGetValue(hud.player_id, out var u) ? u : null) : null;
        }

        public void _KeepQuiet()
        {
            var me = _Me();
            if (me == null)
                return;
            if (sim.Alive(me))
            {
                me.dr = GD.Maxf((double)me.dr, TAKE);
                me.dr_until = (double)sim.time + 1.0;
                if ((double)me.hp < (double)me.max_hp * HP_FLOOR)
                    me.hp = (double)me.max_hp * HP_FLOOR;
            }
            foreach (var c in sim.moba.camps)
            {
                if (!(bool)c.alive)
                    c.next = GD.INF;
            }
            if ((double)sim.match_time - (double)sim.time < 120.0)
                sim.match_time = (double)sim.match_time + 600.0;      // (the clock never runs out on a lesson)
        }

        public bool Holds()
        {
            // siege_mode: while true the match doesn't step (the Herald is talking, or about to)
            return GArray.Of("wait", "talk", "done").Has(phase) || finished;
        }

        // ---------------- flow ----------------
        public GArray _Lines()
        {
            GDict st = STEPS[step].D;
            return phase == "talk" ? st.Get("talk", new GArray()).A : (phase == "done" ? st.Get("done", new GArray()).A : new GArray());
        }

        public GArray CurrentLine()
        {
            var ls = _Lines();
            if (line >= ls.Size())
                return GArray.Of("", "", "hold");
            GArray l = ls[line].A;
            if (GD.Str(l[0]) == "@pay")
                return mode != null && mode.TutorialPays() ? END_GOLD : END_NOGOLD;
            return l;
        }

        public void Next()
        {
            // a tap: the line typed out first, then the next one
            if (phase == "wait")
                return;
            if (finished)
            {
                _Finish();
                return;
            }
            if (!GArray.Of("talk", "done").Has(phase))
                return;
            if (shown < (double)GD.Str(CurrentLine()[1]).Length)
            {
                shown = 9999.0;
                return;
            }
            line += 1;
            if (line < _Lines().Size())
            {
                _ShowLine();
                return;
            }
            if (phase == "talk" && STEPS[step].D.Has("task"))
            {
                phase = "task";
                _EnterTask();
                voice.Stop();
                _Refresh();
                return;
            }
            _NextStep();
        }

        public void _NextStep()
        {
            step += 1;
            line = 0;
            phase = "talk";
            if (step >= STEPS.Size())
            {
                step = STEPS.Size() - 1;
                finished = true;
                _Finish();
                return;
            }
            _EnterStep();
            if (mode != null && mode.analytics != null)
                mode.analytics.LogEv("tutorial_step", GDict.Of("step", step, "id", GD.Str(STEPS[step]["id"])));
            _ShowLine();
        }

        public void _Finish()
        {
            voice.Stop();
            if (mode != null)
                mode.FinishTutorial();
        }

        public void _CompleteTask()
        {
            phase = "done";
            line = 0;
            if (mode != null && mode.audio != null)
                mode.audio.Play("claim");
            if (STEPS[step].D.Get("done", new GArray()).A.IsEmpty())
                _NextStep();
            else
                _ShowLine();
        }

        public void _ShowLine()
        {
            shown = 0.0;
            var l = CurrentLine();
            var id = GD.Str(l[0]);
            lines_said.Append(id);
            _SetPose(l.Size() > 2 && GD.Str(l[2]) != "" ? GD.Str(l[2]) : "hold");
            voice.Stop();
            var master = 1.0;
            var muted = false;
            if (mode != null && mode.audio != null)
            {
                master = (double)mode.audio.levels.Get("master", 1.0);
                muted = (bool)mode.audio.muted;
            }
            var p = VO_DIR + id + ".ogg";
            if (id != "" && !muted && master > 0.0 && ResourceLoader.Exists(p))
            {
                voice.Stream = ResourceLoader.Load<AudioStream>(p);
                voice.VolumeDb = GD.LinearToDb(master * VOICE_GAIN);
                voice.Play();
            }
            _Refresh();
        }

        public void _SetPose(string p)
        {
            if (p == pose)
                return;
            pose = p;
            scroll.Texture = PoseTex(p);
            // he changes how he's holding it: the scroll pops a little
            GDict r = ScrollRects(p, Size);
            scroll.PivotOffset = new Vector2(r["art"].As<Rect2>().size.x * 0.5, r["art"].As<Rect2>().size.y);
            scroll.Scale = new Vector2(0.94, 0.94);
            var sm = scroll.Modulate;
            sm.a = 0.35f;
            scroll.Modulate = sm;
            var tw = CreateTween().SetParallel(true);
            tw.TweenProperty(scroll, "scale", Vector2.ONE, 0.22).SetTrans(Tween.TRANS_BACK).SetEase(Tween.EASE_OUT);
            tw.TweenProperty(scroll, "modulate:a", 1.0, 0.12);
        }

        public void _Refresh()
        {
            var talking = GArray.Of("talk", "done").Has(phase) || finished;
            if (hud != null)
                hud.tut_modal = talking || phase == "wait";
            dim.Visible = talking;
            scroll.Visible = talking && scroll.Texture != null;
            text_label.Visible = talking;
            hint_label.Visible = talking;
            count_label.Visible = talking;
            card.Visible = phase == "task" && !(hud != null && (hud.ShopOpen() || hud.BoardOpen()));
            count_label.Text = GD.Fmt("LESSON %d OF %d", step + 1, STEPS.Size());
            if (phase == "task")
                task_label.Text = GD.Str(STEPS[step]["task"]);
            text_label.Text = talking ? GD.Str(CurrentLine()[1]) : "";
            text_label.VisibleCharacters = shown < 9000.0 ? (int)shown : -1;
            _Layout();
            if (talking)
            {
                GDict r = ScrollRects(pose, Size);
                text_label.AddThemeFontSizeOverride("font_size", FitPx(text_label.Text, r["text"].As<Rect2>().size));
            }
        }

        public void _Layout()
        {
            if (scroll == null)
                return;
            GDict r = ScrollRects(pose != "" ? pose : "hold", Size);
            Rect2 art = r["art"].As<Rect2>();
            Rect2 tr = r["text"].As<Rect2>();
            scroll.Position = art.position;
            scroll.Size = art.size;
            text_label.Position = tr.position;
            text_label.Size = tr.size;
            // under the scroll, on the shade: the lesson on the left, TAP TO CONTINUE on the right
            var foot = Size.y - SCROLL_BOTTOM + 13.0;                  // (clear of the rods' caps)
            hint_label.Position = new Vector2(Size.x * 0.5, foot);
            hint_label.Size = new Vector2(Size.x * 0.5 - SCROLL_SIDE, 18);
            count_label.Position = new Vector2(SCROLL_SIDE, foot);
            count_label.Size = new Vector2(Size.x * 0.5, 18);
            // the objective card under the HUD's top (gold, items); hidden while the shop or the board is open (they say it)
            card.Visible = phase == "task" && !(hud != null && (hud.ShopOpen() || hud.BoardOpen()));
            card.OffsetTop = 182.0;
            card.OffsetBottom = card.OffsetTop + 10.0;
        }

        // ---------------- steps and tasks ----------------
        public void _EnterStep()
        {
            // what a step needs, put there as its talk begins (the match waits meanwhile)
            var me = _Me();
            if (me == null)
                return;
            var t = (int)me.team;
            switch (GD.Str(STEPS[step]["id"]))
            {
                case "lane":
                    _Hop(_Side(t, LANE_AT));
                    _DeliverLane();
                    break;
                case "recall":
                    if (Sim.InCastle(me.pos, t) || !sim.Alive(me))
                    {
                        if (!sim.Alive(me))
                            sim.Respawn(me);
                        _Hop(_Side(t, LANE_AT));
                    }
                    break;
                case "shop":
                    if (!sim.moba.CanShop(me))
                        _Hop(Sim.Spawn(t));
                    break;
                case "abilities":
                    while ((int)me.level < 3)
                        sim.moba.AddXp(me, sim.moba.Need((int)me.level) - (double)me.xp + 0.1);
                    break;
                case "jungle":
                    _camp = null;
                    foreach (var c in sim.moba.camps)
                    {
                        if (GD.Str(c.kind) == "archers" && (int)c.side == t && (_camp == null || Math.Abs(c.p.y) > Math.Abs(_camp.p.y)))
                            _camp = c;                             // (ours nearest the keep)
                    }
                    if (_camp != null && sim.moba.CampLive(_camp).Count == 0)
                    {
                        sim.moba._SpawnCamp(_camp);
                        foreach (var mid in _camp.mobs)
                        {
                            Unit mob = sim.by_id.TryGetValue(GD.Str(mid), out var mu) ? mu : null;
                            if (mob != null)
                            {
                                mob.max_hp = (double)mob.max_hp * CAMP_WEAK;
                                mob.hp = (double)mob.max_hp;
                            }
                        }
                    }
                    break;
                case "ward":
                {
                    // the brush patch of ours nearest you (you're by our Grave Archers: one at the jungle's way in)
                    _brush = null;
                    var best = GD.INF;
                    foreach (var b in sim.moba.vision.brushes)
                    {
                        bool ours = (b.p.y > 0.0) == (t == 0);
                        double dd = me.pos.DistanceTo(b.p);
                        if (ours && dd < best)
                        {
                            best = dd;
                            _brush = b;
                        }
                    }
                    if (_brush != null && best > WARD_NEAR)
                    {
                        // far off (home, or wandering): paperwork again -- you, along the way to it, with it in sight
                        var pts = new List<Vector2> { me.pos };
                        pts.AddRange(sim.FindPath(t, me.pos, _brush.p));
                        pts.Add(_brush.p);
                        var left = WARD_HOP;
                        Vector2 at = _brush.p;
                        for (int i = pts.Count - 1; i > 0; i--)
                        {
                            double seg = pts[i].DistanceTo(pts[i - 1]);
                            if (seg >= left)
                            {
                                at = pts[i].Lerp(pts[i - 1], left / seg);
                                break;
                            }
                            left -= seg;
                            at = pts[i - 1];
                        }
                        _Hop(at);
                    }
                    break;
                }
                case "tower":
                    _tw = null;
                    foreach (var tw in sim.moba.towers)
                    {
                        if ((int)tw.team != t && (int)tw.lane == 1 && (int)tw.tier == 1)
                            _tw = tw;
                    }
                    if (_tw != null)
                    {
                        var toward = t == 0 ? new Vector2(0.0, 1.0) : new Vector2(0.0, -1.0);     // (our side of it)
                        var at = new Vector2(0.0, _tw.p.y) + toward * 17.0;
                        _Hop(at + new Vector2(2.5, 0.0));
                        _ours = sim.moba.PlaceMinions(t, 1, TOWER_KINDS, at - toward * 1.5);
                    }
                    _tw_hits = 0;
                    break;
            }
        }

        public void _EnterTask()
        {
            var me = _Me();
            _note = "";
            switch (GD.Str(STEPS[step]["id"]))
            {
                case "move":
                    _start = me.pos;
                    break;
                case "lane":
                    _lh0 = (int)me.lh;
                    break;
                case "ward":
                    me.ward_ch = GD.Maxf((double)me.ward_ch, 1.0);     // (a charge to put down, whatever was used)
                    break;
                case "abilities":
                    _shield_t = 0.0;
                    _w_done = false;
                    _e_done = false;
                    foreach (var k in new[] { "cd_ability", "cd_w", "cd_e" })
                        me.Set(k, 0.0);                          // (all three ready, whatever was used in the lane)
                    break;
            }
        }

        public static Vector2 _Side(int team, Vector2 p)
        {
            return team == 0 ? p : -p;
        }

        public void _DeliverLane()
        {
            var t = (int)_Me().team;
            sim.moba.PlaceMinions(t, 1, LANE_KINDS, _Side(t, LANE_OURS));
            _red = sim.moba.PlaceMinions(1 - t, 1, LANE_KINDS, _Side(t, LANE_THEIRS));
        }

        public void _Hop(Vector2 p)
        {
            // "royal paperwork": you, there -- with the recall's flash at both ends
            var me = _Me();
            if (me == null)
                return;
            Vector2 from = me.pos;
            if (sim.Recalling(me))
                sim.RecallCancel(me);
            me.pos = p;
            me.move = Vector2.ZERO;
            var e = new Ev { { "k", "recall_done" }, { "id", GD.Str(me.id) }, { "from", from }, { "to", p }, { "tut", true } };
            if (mode != null && mode.view != null)
                mode.view.OnEvent(e);
            if (mode != null)
                mode._EventSound(e);
        }

        public List<string> _AliveIds(List<string> ids)
        {
            return ids.FindAll(id => sim.by_id.ContainsKey(GD.Str(id)) && sim.Alive(sim.by_id[GD.Str(id)]));
        }

        public void OnEvent(Ev e)
        {
            // (siege_mode passes on the match's events)
            var me = _Me();
            if (me == null || phase != "task")
                return;
            bool mine = e.S("id", "") == GD.Str(me.id);
            switch (e.S("k", ""))
            {
                case "recall_done":
                    if (mine && !e.B("tut", false) && GD.Str(STEPS[step]["id"]) == "recall")
                        _CompleteTask();
                    break;
                case "recall_cancel":
                    if (mine)
                        _SayNote("Interrupted! Step away from the fight, then try again.");
                    break;
                case "buy":
                    if (mine && GD.Str(STEPS[step]["id"]) == "shop")
                    {
                        if (hud.ShopOpen())
                            hud.CloseShop();
                        _CompleteTask();
                    }
                    break;
                case "spell":
                    if (mine && GD.Str(STEPS[step]["id"]) == "abilities")
                    {
                        if (e.S("slot", "") == "w")
                            _w_done = true;
                        else if (e.S("slot", "") == "e")
                            _e_done = true;
                    }
                    break;
                case "tower_hit":
                    if (e.S("by", "") == GD.Str(me.id) && _tw != null && e.I("tw", -1) == (int)_tw.id)
                        _tw_hits += 1;
                    break;
                case "ward":
                    if (mine && GD.Str(STEPS[step]["id"]) == "ward")
                    {
                        if (sim.moba.vision.BrushAt(e.Has("pos") ? e.P("pos") : me.pos) >= 0)
                            _CompleteTask();
                        else
                        {
                            me.ward_ch = (double)me.ward_ch + 1.0;     // (that one's on the house)
                            _SayNote("That's open ground. Into the brush first, then WARD.");
                        }
                    }
                    break;
            }
        }

        public void _SayNote(string t)
        {
            _note = t;
            _note_until = _time + 3.5;
        }

        public string Progress()
        {
            // the task's count so far ("1/2"), if it has one
            var me = _Me();
            switch (GD.Str(STEPS[step]["id"]))
            {
                case "lane":
                    return GD.Fmt("%d/%d", GD.Mini((int)me.lh - _lh0, LH_GOAL), LH_GOAL);
                case "tower":
                    return GD.Fmt("%d/%d", GD.Mini(_tw_hits, TOWER_HITS), TOWER_HITS);
                case "abilities":
                {
                    var n = GD.Int(_shield_t >= SHIELD_FOR) + GD.Int(_w_done) + GD.Int(_e_done) + GD.Int(me.picks == null || me.picks.Count == 0);
                    return GD.Fmt("%d/4", n);
                }
                case "jungle":
                    if (_camp != null)
                        return GD.Fmt("%d left", sim.moba.CampLive(_camp).Count);
                    break;
            }
            return "";
        }

        public bool TaskDone()
        {
            var me = _Me();
            switch (GD.Str(STEPS[step]["id"]))
            {
                case "move":
                    return me.pos.DistanceTo(_start) >= 6.0;
                case "lane":
                    return (int)me.lh - _lh0 >= LH_GOAL;
                case "eco":
                    return hud.BoardOpen();
                case "recall":
                    return false;                               // (its "recall_done")
                case "shop":
                    return false;                               // (a "buy")
                case "ward":
                    return false;                               // (a "ward" in a brush)
                case "abilities":
                    return _shield_t >= SHIELD_FOR && _w_done && _e_done && (me.picks == null || me.picks.Count == 0);
                case "jungle":
                    return _camp != null && sim.moba.CampLive(_camp).Count == 0;
                case "tower":
                    return _tw_hits >= TOWER_HITS || (_tw != null && (bool)_tw.dead);     // (the minions beat you to it)
            }
            return true;
        }

        public void _TaskTick(double delta)
        {
            var me = _Me();
            switch (GD.Str(STEPS[step]["id"]))
            {
                case "lane":
                    if (_AliveIds(_red).Count == 0 && (int)me.lh - _lh0 < LH_GOAL)
                    {
                        _DeliverLane();                        // (another delivery: they were all finished off by others)
                        _SayNote("Another delivery. Try to land the last blow this time.");
                    }
                    break;
                case "abilities":
                    if (sim.Blocking(me))
                        _shield_t += delta;
                    break;
                case "tower":
                    if (_tw != null && !(bool)_tw.dead)
                    {
                        var near = false;
                        foreach (var id in _AliveIds(_ours))
                        {
                            if (sim.by_id[GD.Str(id)].pos.DistanceTo(_tw.p) < 22.0)
                                near = true;
                        }
                        if (!near)
                        {
                            var t = (int)me.team;
                            var toward = t == 0 ? new Vector2(0.0, 1.0) : new Vector2(0.0, -1.0);
                            _ours = sim.moba.PlaceMinions(t, 1, TOWER_KINDS, new Vector2(0.0, _tw.p.y) + toward * 15.5);
                            _SayNote("More minions. Do let them go first.");
                        }
                    }
                    break;
            }
        }

        protected override void _Process(double delta)
        {
            if (sim == null)
                return;
            _time += delta;
            _KeepQuiet();
            voice.StreamPaused = hud.Paused();
            if (phase == "wait")
            {
                if (mode == null || mode.Warmed())
                {
                    phase = "talk";
                    _EnterStep();
                    _ShowLine();
                }
                return;
            }
            if (phase == "task")
            {
                _TaskTick(delta);
                _UpdatePath(delta);
                var pg = Progress();
                task_label.Text = GD.Str(STEPS[step]["task"]) + (pg != "" ? ("   " + pg) : "");
                var me = _Me();
                var n = _time < _note_until ? _note : "";
                if (n == "" && me != null && !sim.Alive(me))
                    n = "Back on your feet in a moment...";
                if (n == "" && GD.Str(STEPS[step]["id"]) == "recall" && sim.Recalling(me))
                    n = GD.Fmt("Stand still... %.1f", GD.Maxf(0.0, (double)me.recall_until - (double)sim.time));
                note_label.Text = n;
                note_label.Visible = n != "";
                if (TaskDone())
                    _CompleteTask();
            }
            else if (GArray.Of("talk", "done").Has(phase))
            {
                var full = GD.Str(CurrentLine()[1]);
                if (shown < 9000.0)
                    shown = GD.Minf(shown + delta * TYPE_CPS, (double)full.Length);
                text_label.VisibleCharacters = shown >= (double)full.Length ? -1 : (int)shown;
                bool said = shown >= (double)full.Length && !voice.Playing;
                var hm = hint_label.Modulate;
                hm.a = (float)(said ? (0.55 + 0.45 * Math.Sin(_time * 5.0)) : 0.35);
                hint_label.Modulate = hm;
            }
            _Layout();
            QueueRedraw();
        }

        // ---------------- guidance ----------------
        public static readonly Color GOLD = Color.FromCode("#ffd257");
        public static readonly Color INK = new Color(0.08, 0.05, 0.02, 0.9);

        public GDict TaskInfo()
        {
            // what to point at: "pos" (a world point) + "label" for the route, ring and arrow; "button" (a HUD button) with
            // "hold"; "rect" (a HUD rect) for the score bar, the shop, the upgrade cards
            var me = _Me();
            if (me == null || phase != "task")
                return new GDict();
            switch (GD.Str(STEPS[step]["id"]))
            {
                case "move":
                    return GDict.Of("stick", true);
                case "lane":
                {
                    Unit best = null;
                    foreach (var id in _AliveIds(_red))
                    {
                        Unit m = sim.by_id[GD.Str(id)];
                        if (best == null || (double)m.hp < (double)best.hp)
                            best = m;
                    }
                    if (best == null)
                        return new GDict();
                    bool low = (double)best.hp <= (double)sim.Stat(me, SK.dmg) * 1.1;
                    var info = GDict.Of("pos", best.pos, "label", low ? "LAST HIT NOW" : "ENEMY MINIONS", "small", true);
                    if (low)
                        info["button"] = "attack";
                    return info;
                }
                case "eco":
                {
                    Rect2 sb = hud.ScoreBarRect();
                    return !hud.BoardOpen() ? GDict.Of("rect", sb, "rect_label", "TAP", "label_at", new Vector2(sb.GetCenter().x + sb.size.x * 0.3, sb.End.y + 20.0)) : new GDict();
                }
                case "recall":
                    if (sim.Recalling(me))
                        return new GDict();
                    return GDict.Of("button", "recall");
                case "shop":
                {
                    Rect2 sr = hud.ShopRect();
                    return !hud.ShopOpen() ? GDict.Of("rect", sr, "rect_label", "TAP", "label_at", new Vector2(sr.End.x + 38.0, sr.GetCenter().y)) : new GDict();
                }
                case "abilities":
                    if (_shield_t < SHIELD_FOR)
                        return GDict.Of("button", "ability", "hold", true);
                    if (!_w_done)
                        return GDict.Of("button", "w");
                    if (!_e_done)
                        return GDict.Of("button", "e");
                    if (!(me.picks == null || me.picks.Count == 0))
                        return GDict.Of("rect", hud.PickRect(0).Merge(hud.PickRect(2)), "rect_label", "CHOOSE ONE");
                    break;
                case "jungle":
                {
                    if (_camp == null)
                        return new GDict();
                    var info2 = GDict.Of("pos", _camp.p, "label", "GRAVE ARCHERS");
                    if (me.pos.DistanceTo(_camp.p) < 7.0)
                        info2["button"] = "attack";
                    return info2;
                }
                case "ward":
                {
                    if (_brush == null)
                        return new GDict();
                    var info4 = GDict.Of("pos", _brush.p, "label", "BRUSH", "ring", (double)_brush.r);
                    if (sim.moba.vision.BrushAt(me.pos) >= 0)
                        info4["button"] = "ward";
                    return info4;
                }
                case "tower":
                {
                    if (_tw == null)
                        return new GDict();
                    var info3 = GDict.Of("pos", _tw.p, "label", "ENEMY TOWER", "ring", 2.6, "lift", 7.0);
                    if (sim.moba.InTowerRange(_tw, me.pos))
                        info3["button"] = "attack";
                    return info3;
                }
            }
            return new GDict();
        }

        public void _UpdatePath(double delta)
        {
            _path_clock -= delta;
            if (_path_clock > 0.0)
                return;
            _path_clock = 0.4;
            var info = TaskInfo();
            var me = _Me();
            _path = info.Has("pos") && !(bool)info.Get("small", false) ? sim.FindPath((int)me.team, me.pos, info["pos"].V2) : new List<Vector2>();
        }

        public Vector3 _W(Vector2 p, double lift = 0.15)
        {
            return new Vector3(p.x, Sim.HeightAt(p) + lift, p.y);
        }

        public void _Plate(Vector2 center, string text)
        {
            Font font = VisualTheme.BOLD_FONT;
            var fs = 14;
            var w = font.GetStringSize(text, HorizontalAlignment.Left, -1, fs).x + 20.0;
            var r = new Rect2(center.x - w * 0.5, center.y - 13, w, 26);
            DrawRect(r.Grow(2), INK);
            DrawRect(r, new Color(0.12, 0.09, 0.03, 0.95));
            DrawRect(new Rect2(r.position, new Vector2(r.size.x, 3)), GOLD);
            DrawString(font, new Vector2(r.position.x + 10, r.position.y + 19), text, HorizontalAlignment.Left, -1, fs, Color.WHITE);
        }

        public void _Arrow(Vector2 tip, double s, bool up = false)
        {
            // a fat outlined arrow pointing down at tip (or up)
            var k = up ? -1.0 : 1.0;
            var pts = new List<Vector2> { tip, tip + new Vector2(-22, -26 * k) * s, tip + new Vector2(-9, -26 * k) * s, tip + new Vector2(-9, -52 * k) * s,
                tip + new Vector2(9, -52 * k) * s, tip + new Vector2(9, -26 * k) * s, tip + new Vector2(22, -26 * k) * s };
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

        protected override void _Draw()
        {
            if (sim == null)
                return;
            if (phase != "task")
                return;
            var info = TaskInfo();
            var pulse = 0.5 + 0.5 * Math.Sin(_time * 5.0);
            var me = _Me();
            if (me == null)
                return;
            if (info.Has("stick"))
            {
                // a ghost thumb on the left, circling
                var @base = new Vector2(Size.x * 0.27, Size.y - 190.0);
                DrawCircle(@base, 46.0, new Color(1, 1, 1, 0.08));
                DrawArc(@base, 46.0, 0.0, GD.TAU, 48, new Color(GOLD, 0.7), 3.0, true);
                var thumb = @base + Vector2.FromAngle(_time * 2.2) * 26.0;
                DrawCircle(thumb, 17.0, INK);
                DrawCircle(thumb, 14.0, GOLD);
                _Plate(@base + new Vector2(0, 72), "DRAG HERE");
            }
            if (info.Has("button"))
            {
                foreach (var b in hud._Buttons())
                {
                    if (GD.Str(b["id"]) == GD.Str(info["button"]))
                    {
                        double rr = (double)b["r"] + 10.0 + 7.0 * pulse;
                        DrawArc(b["c"].V2, rr + 3.0, 0.0, GD.TAU, 48, INK, 9.0, true);
                        DrawArc(b["c"].V2, rr, 0.0, GD.TAU, 48, GOLD, 6.0, true);
                        _Plate(b["c"].V2 + new Vector2(0, -(double)b["r"] - 32.0), (bool)info.Get("hold", false) ? "HOLD" : "TAP");
                    }
                }
            }
            if (info.Has("rect"))
            {
                Rect2 r = info["rect"].As<Rect2>().Grow(5.0 + 4.0 * pulse);
                DrawRect(r.Grow(3.0), INK, false, 5.0);
                DrawRect(r, GOLD, false, 4.0);
                _Plate(info.Get("label_at", new Vector2(r.GetCenter().x, r.End.y + 20.0)).V2, GD.Str(info.Get("rect_label", "TAP")));
            }
            if (!info.Has("pos"))
                return;
            Vector2 tgt = info["pos"].V2;
            var pts = new List<Vector2> { me.pos };
            pts.AddRange(_path);
            pts.Add(tgt);
            if (!(bool)info.Get("small", false))
            {
                // the route: dots every 1.1 m along the way, marching toward the target
                var step_len = 1.1;
                var along = GD.Fmod(_time * 2.2, step_len);
                var walked = 0.0;
                for (int i = 0; i < pts.Count - 1; i++)
                {
                    Vector2 a = pts[i];
                    Vector2 b2 = pts[i + 1];
                    double seg = a.DistanceTo(b2);
                    while (along < seg && walked + along < 40.0)
                    {
                        var wq = _W(a.Lerp(b2, along / GD.Maxf(seg, 0.001)));
                        if (hud.on_screen(wq))
                        {
                            Vector2 sq = hud.project(wq);
                            DrawCircle(sq, 7.0, INK);
                            DrawCircle(sq, 5.0, GOLD);
                        }
                        along += step_len;
                    }
                    along -= seg;
                    walked += seg;
                }
            }
            var route = 0.0;
            Vector2 guide = tgt;
            var got = false;
            for (int i = 0; i < pts.Count - 1; i++)
            {
                double seg2 = pts[i].DistanceTo(pts[i + 1]);
                if (!got && route + seg2 >= 8.0)
                {
                    guide = pts[i].Lerp(pts[i + 1], (8.0 - route) / GD.Maxf(seg2, 0.001));
                    got = true;
                }
                route += seg2;
            }
            var label = GD.Str(info.Get("label", "HERE")) + ((bool)info.Get("small", false) || route < 4.0 ? "" : GD.Fmt(" · %d m", (int)GD.Round(route)));
            if (hud.on_screen(_W(tgt, 0.0)))
            {
                var ring = new List<Vector2>();
                var inner = new List<Vector2>();
                double rad = (double)info.Get("ring", (bool)info.Get("small", false) ? 0.9 : 1.4);
                for (int k = 0; k < 33; k++)
                {
                    var off = Vector2.FromAngle(GD.TAU * k / 32.0);
                    ring.Add(hud.project(_W(tgt + off * rad, 0.08)));
                    inner.Add(hud.project(_W(tgt + off * rad * (0.35 + 0.55 * pulse), 0.08)));
                }
                DrawPolyline(ring, INK, 9.0, true);
                DrawPolyline(ring, GOLD, 5.0, true);
                DrawPolyline(inner, new Color(GOLD, 0.8 - 0.6 * pulse), 3.0, true);
                Vector2 tip = hud.project(_W(tgt, (double)info.Get("lift", 2.4))) + new Vector2(0, -10.0 * pulse);
                double top_free = card.GetRect().End.y + 12.0;
                if (tip.y - 100.0 > top_free)
                {
                    _Arrow(tip, 1.1);
                    _Plate(tip + new Vector2(0, -78), label);
                }
                else
                {
                    Vector2 tip2 = hud.project(_W(tgt, 0.0)) + new Vector2(0, 24.0 + 10.0 * pulse);
                    _Arrow(tip2, 1.1, true);
                    _Plate(tip2 + new Vector2(0, 78), label);
                }
            }
            else
            {
                // off screen: a big edge arrow the way to go
                var center = Size * 0.5;
                Vector2 from_s = hud.project(_W(me.pos, 1.0));
                Vector2 to_s = hud.project(_W(guide, 1.0));
                var dir = (to_s - from_s).Normalized();
                if (dir == Vector2.ZERO)
                    dir = new Vector2(0, -1);
                var edge = center + dir * GD.Minf(Size.x * 0.40, Size.y * 0.30);
                edge.y = (float)GD.Maxf(edge.y, card.GetRect().End.y + 60.0);
                var side = new Vector2(-dir.y, dir.x);
                DrawColoredPolygon(new[] { edge + dir * 40, edge - dir * 18 + side * 30, edge - dir * 18 - side * 30 }, INK);
                DrawColoredPolygon(new[] { edge + dir * 34, edge - dir * 14 + side * 24, edge - dir * 14 - side * 24 }, GOLD);
                _Plate(edge - dir * 50, label);
            }
        }
    }
}
