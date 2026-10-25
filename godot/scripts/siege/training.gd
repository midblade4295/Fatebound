extends Control
# 0.31.217 THE TRAINING (Kevin, with a recording of Honor of Kings' two training matches: "Here is how I want the
# training to go in fatebound. The helper will be another character and voiced by the herald." The helper: the
# Dragoon). Kael Wyrmlance, the Dragoon ("Last Rider of Skyreach"), fights at your side and talks you through it in the
# Herald's voice (assets/vo/training/<id>.ogg; art_sources/training/script.json -- LINES here, word for word).
# As Honor of Kings' own: his line in a bar at the top (his portrait, the key words lit) while the match runs on; the
# task in a box at the top right (TUTORIAL 1/5 ...); his quips in a bubble over his head ("Well done!"); a hand on what
# to tap; a dotted path to where to go.
#  TRAINING 1, THE BASICS -- a quiet Rift (every other hero at his fountain, no waves or camps of their own; KAEL'S
#   BLESSING: you take half damage and can't fall): follow him down the middle lane; a wave of their minions; a skill
#   learnt with the +; an enemy hero; level 2 and the second skill; two heroes at once; level 3 and a skill made
#   stronger; level 4, the ultimate, and three heroes to use it on; the quick-buy; then the challenges -- their outer
#   tower (our minions first: its ring yellow, red when it's on you), the high ground (our army takes the inner one on
#   the way), the King. VICTORY.
#  TRAINING 2, 5V5 BATTLE -- a real match against bots with Kael beside you (you take a quarter less damage; their
#   heroes hit softer): the map first, the match waiting (the lanes, the minions, the towers, how it's won, which heroes
#   go where); he takes you to your hero's lane; then missions 1/4 to 4/4 (an outer, an inner and a high ground tower,
#   the King), the towers' lesson the first time you're by one (the match waits), HOME when you're hurt, the quick-buy
#   when you can afford it, the King when he's open.
# Either one done: the training's gold, once (siege_mode.finish_tutorial -> Profile.finish_tutorial); no match rewards.
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Minimap = preload("res://scripts/siege/minimap.gd")
const VisualTheme = preload("res://scripts/ui/visual_theme.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const VO_DIR := "res://assets/vo/training/"
const PORTRAIT := "res://assets/ui/skins/default_dragoon.png"
const KAEL_HID := "dragoon"
const KAEL_NAME := "Kael"
const VOICE_GAIN := 0.55          # x master (as the tutorial's Herald)
const TYPE_CPS := 40.0
const HP_FLOOR := 0.3             # training 1: you (and Kael) can't fall
const TAKE := 0.5                 # ...and take half damage
const TAKE2 := 0.25               # training 2: a quarter less
const SOFT := 0.5                 # training 1: Kael's and the enemy heroes' hits (m_out)
const SOFT2 := 0.8                # training 2: the enemy heroes'
const FOE_HP := 0.5               # training 1: an enemy hero put in front of you comes at half health
const TOWER_LEFT := 0.55          # training 1: their towers at this much health when you get there
const KING_LEFT := 0.25           # ...and their King
const P_START := Vector2(2.0, 40.0)        # (blue's; red's the point mirror) you and Kael, behind our outer tower
const P_MOVE := Vector2(0.0, 14.0)         # the first walk's end: out of our tower's reach (it's at (4, 30), 11.5 m)
const P_WAVE := Vector2(0.0, -4.0)         # their wave put down here, walking at you
const WAVE := ["melee", "melee", "melee", "caster", "caster", "caster"]
const ARMY := ["melee", "melee", "melee", "melee", "caster", "caster"]
const GOLD := Color("#ffd257")
const INK := Color(0.08, 0.05, 0.02, 0.9)
const KEY_INK := "#ffd65a"
# the words lit in his lines (longest first)
const KEYS := ["skill point", "high ground", "ATTACK", "HOME", "plus", "skills", "skill", "ultimate", "minions", "minion",
	"gold", "towers", "tower", "King", "level", "ring", "yellow", "red", "green", "lanes", "lane", "jungle", "item", "Victory!"]

const LINES := {
	"k1_hello": "Kael Wyrmlance, at your service. Stay close, and I'll show you how we fight.",
	"k1_trouble": "There's trouble at the front. Come on!",
	"k1_controls": "Your left thumb moves you. Your right thumb fights.",
	"k1_follow": "Follow me!",
	"k1_minions": "Enemy minions! Tap ATTACK to strike. Keep moving while you fight.",
	"k1_gold": "Finish a minion, and its gold is yours.",
	"k1_learn": "Every level gives you a skill point. Tap the plus to learn your first skill.",
	"k1_enemy": "An enemy hero! Red health bars are enemies. Hit him with your skill!",
	"k1_level": "You've levelled up. Time to learn your second skill.",
	"k1_combo": "Two of them! Use one skill, then the other. Quick as you can!",
	"k1_upgrade": "Another level. Put the point on a skill you know, to make it stronger.",
	"k1_ult": "Level four. Your ultimate is ready to learn. It's your strongest move.",
	"k1_ult_use": "Here they come. Hit them with your ultimate!",
	"k1_ult_done": "Not bad! I'll have to watch out for you.",
	"k1_shop": "You've earned some gold. Tap the item on the left to buy it, right here.",
	"k1_shop_done": "Better gear, harder hits.",
	"k1_towers": "Now we break their towers. Three in a lane, then their King. Defeat him, and we win!",
	"k1_tower": "Let our minions walk in first. A tower shoots the first one in its range.",
	"k1_tower_red": "Its ring is red. It's aiming at you. Step back!",
	"k1_tower_down": "Tower down! Our army's taken their inner tower too. On to the high ground!",
	"k1_king_open": "The lane is broken. Their King is open. Charge!",
	"k1_king_slam": "He hits hard. Stay with the minions!",
	"k1_victory": "Victory! You're a natural.",
	"b_well_done": "Well done!",
	"b_on_fire": "Wow, you're on fire!",
	"b_watch_out": "Watch out!",
	"b_nice": "Nice!",
	"b_natural": "You're a natural!",
	"b_brb": "Be right back!",
	"b_over_here": "Over here!",
	"k2_welcome": "Welcome to the Rift. This time it's a real battle. Five against five.",
	"k2_lanes": "The Rift has three lanes.",
	"k2_minions": "Minions march down every lane.",
	"k2_towers": "Each side has three towers in every lane.",
	"k2_win1": "Break all three towers in one lane,",
	"k2_win2": "and their King is open. Defeat him to win!",
	"k2_roles": "Each lane suits different heroes.",
	"k2_top": "The top lane suits fighters and tanks.",
	"k2_mid": "The middle lane suits mages.",
	"k2_bot": "The bottom lane suits marksmen and supports.",
	"k2_jungle": "Assassins hunt in the jungle, between the lanes.",
	"k2_ready": "Get ready. We're heading into battle!",
	"k2_go_top": "To the top lane. Follow me!",
	"k2_go_mid": "To the middle lane. Follow me!",
	"k2_go_bot": "To the bottom lane. Follow me!",
	"k2_go_jungle": "To the jungle. Follow me!",
	"k2_tw1": "Towers hit hard. Here's how they work.",
	"k2_tw2": "Near an enemy tower, its ring turns yellow.",
	"k2_tw3": "When it aims at you, the ring turns red.",
	"k2_tw4": "A tower shoots the first one to walk into its range.",
	"k2_tw5": "So let a minion walk in first.",
	"k2_tw6": "When the ring turns green, it's safe to attack.",
	"k2_tw7": "Hit an enemy hero under his tower, and the tower turns on you.",
	"k2_recall": "You're hurt. Tap HOME to go back and heal.",
	"k2_shop": "You've got the gold for that item. Tap it on the left.",
	"k2_king": "Their King hits incredibly hard. Don't stand in his slam!",
	"k2_victory": "Victory! You're ready for the real thing.",
	"k2_defeat": "We'll get them next time.",
}

# Each step: its id, the box's heading and task, the lines that start it ("say") and end it ("after", before the next's),
# Kael's quip in his bubble when it's done ("bubble")
const K1 := [
	{"id":"move", "head":"TUTORIAL 1/5", "task":"Follow Kael down the lane", "say":["k1_hello", "k1_trouble", "k1_controls", "k1_follow"]},
	{"id":"minions", "head":"TUTORIAL 2/5", "task":"Defeat the enemy minions", "say":["k1_minions"], "bubble":"b_well_done"},
	{"id":"learn", "head":"TUTORIAL 3/5", "task":"Tap the + to learn a skill", "say":["k1_learn"]},
	{"id":"hero", "head":"TUTORIAL 3/5", "task":"Defeat the enemy hero with your skill", "say":["k1_enemy"], "bubble":"b_on_fire"},
	{"id":"learn2", "head":"TUTORIAL 4/5", "task":"Learn your second skill", "say":["k1_level"]},
	{"id":"combo", "head":"TUTORIAL 4/5", "task":"Defeat both enemy heroes", "say":["k1_combo"], "bubble":"b_natural"},
	{"id":"upgrade", "head":"TUTORIAL 4/5", "task":"Make a skill stronger with the +", "say":["k1_upgrade"]},
	{"id":"ult", "head":"TUTORIAL 5/5", "task":"Learn your ultimate", "say":["k1_ult"]},
	{"id":"ult_use", "head":"TUTORIAL 5/5", "task":"Hit the enemy heroes with your ultimate", "say":["k1_ult_use"], "after":["k1_ult_done"]},
	{"id":"shop", "head":"QUICK-BUY", "task":"Tap the item on the left to buy it", "say":["k1_shop"], "after":["k1_shop_done"]},
	{"id":"tower1", "head":"CHALLENGE 1/3", "task":"Destroy the enemy outer tower", "say":["k1_towers"], "after":["k1_tower_down"]},
	{"id":"tower3", "head":"CHALLENGE 2/3", "task":"Destroy the high ground tower", "say":[]},
	{"id":"king", "head":"CHALLENGE 3/3", "task":"Defeat the enemy King", "say":["k1_king_open"]},
]
const K2 := [
	{"id":"tour", "head":"THE RIFT", "task":"", "say":[]},
	{"id":"go", "head":"YOUR LANE", "task":"Follow Kael to your lane", "say":[]},
	{"id":"m1", "head":"MISSION 1/4", "task":"Destroy an enemy outer tower", "say":[]},
	{"id":"m2", "head":"MISSION 2/4", "task":"Destroy an enemy inner tower", "say":[]},
	{"id":"m3", "head":"MISSION 3/4", "task":"Destroy an enemy high ground tower", "say":[]},
	{"id":"m4", "head":"MISSION 4/4", "task":"Defeat the enemy King", "say":[]},
]
const TOUR := ["k2_welcome", "k2_lanes", "k2_minions", "k2_towers", "k2_win1", "k2_win2", "k2_roles", "k2_top", "k2_mid",
	"k2_bot", "k2_jungle", "k2_ready"]
const TOWER_TALK := ["k2_tw1", "k2_tw2", "k2_tw3", "k2_tw4", "k2_tw5", "k2_tw6", "k2_tw7"]
const POST_GO := {"top":"k2_go_top", "mid":"k2_go_mid", "bot":"k2_go_bot", "support":"k2_go_bot", "jungle":"k2_go_jungle"}
const POST_NAME := {"top":"the top lane", "mid":"the middle lane", "bot":"the bottom lane", "support":"the bottom lane", "jungle":"the jungle"}

var which := 1                # 1: the basics, 2: the 5v5 battle (siege_mode.training)
var mode                      # siege_mode.gd
var sim
var hud
var steps: Array = []
var step := -1
var phase := "wait"           # wait (the match warming up) -> play -> over
var hold_kind := ""           # the match waits while he says these: "tour" (the map), "towers" (the towers' lesson)
var lines_said: Array = []    # (tests) every line begun in the bar, in order
var bubbles_said: Array = []  # ...and every bubble
var kael: Dictionary = {}
var foes: Array = []          # training 1: the enemy heroes put in front of you
var won := false
var _queue: Array = []
var _cur := ""                # the line in the bar
var _last := ""
var _shown := 0.0
var _line_t := 0.0
var _idle := 99.0
var _time := 0.0
var _ai := 0.0
var _wave: Array = []
var _ours: Array = []
var _ours_at := -99.0
var _goal := Vector2.INF       # where Kael's leading you
var _tw: Dictionary = {}
var _bubble := ""
var _bubble_until := 0.0
var _once := {}
var _cool := {}
var _ult_used := false
var _bought := false
var _lh0 := 0
var _guide_until := {}        # a short-lived pointer (training 2: HOME, the quick-buy) -> until
var _note := ""
var _note_until := 0.0
var _path := PackedVector2Array()
var _path_clock := 0.0
var _end_at := -1.0
var voice: AudioStreamPlayer
var voice2: AudioStreamPlayer  # (the bubbles)
# the bar, the box, the tap catcher, the map, the end
var bar: PanelContainer
var bar_text: RichTextLabel
var portrait: Panel
var box: PanelContainer
var box_head: Label
var box_task: Label
var box_prog: Label
var tapper: Control
var map: Control
var skip_btn: Button
var end_layer: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	voice = AudioStreamPlayer.new()
	voice.bus = "Master"
	add_child(voice)
	voice2 = AudioStreamPlayer.new()
	voice2.bus = "Master"
	add_child(voice2)
	tapper = Tapper.new()
	tapper.trainer = self
	tapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tapper.visible = false
	add_child(tapper)
	# the bar: Kael's portrait in a gold ring, his name, his line
	bar = PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _box(Color(0.03, 0.05, 0.13, 0.9), Color(VisualTheme.GOLD_DARK, 0.95), 14, 6))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.visible = false
	add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(h)
	portrait = Panel.new()
	portrait.custom_minimum_size = Vector2(50, 50)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.85, 0.72, 0.42)
	ps.set_corner_radius_all(25)
	ps.border_color = GOLD
	ps.set_border_width_all(2)
	ps.anti_aliasing = true
	portrait.add_theme_stylebox_override("panel", ps)
	portrait.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(portrait)
	var face := TextureRect.new()
	face.texture = load(PORTRAIT) if ResourceLoader.exists(PORTRAIT) else null
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.position = Vector2(-6, -2)
	face.size = Vector2(62, 62)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.add_child(face)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var nm := _label(v, "KAEL  ·  THE DRAGOON", 10, GOLD)
	nm.add_theme_constant_override("outline_size", 3)
	bar_text = RichTextLabel.new()
	bar_text.bbcode_enabled = true
	bar_text.fit_content = true
	bar_text.scroll_active = false
	bar_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar_text.add_theme_font_override("normal_font", VisualTheme.BOLD_FONT)
	bar_text.add_theme_font_size_override("normal_font_size", 14)
	bar_text.add_theme_color_override("default_color", Color("#fff6e0"))
	bar_text.add_theme_constant_override("outline_size", 3)
	bar_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	bar_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(bar_text)
	# the box: the task
	box = PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(Color(0.03, 0.05, 0.13, 0.86), Color(VisualTheme.GOLD_DARK, 0.9), 10, 7))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.visible = false
	add_child(box)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 1)
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bv)
	box_head = _label(bv, "", 11, GOLD)
	box_task = _label(bv, "", 13, Color("#fff4d6"))
	box_task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box_prog = _label(bv, "", 12, Color("#9ff6ef"))
	_layout()

static func _box(bg: Color, rim: Color, radius: int, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = rim
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad + 4
	sb.content_margin_right = pad + 4
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 5
	sb.anti_aliasing = true
	return sb

func _label(parent: Node, text: String, px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", VisualTheme.BOLD_FONT)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

# A full-screen catch for the taps while the match waits (the map, the towers' lesson, the end): a tap moves him on.
# Not over the HUD's pause button.
class Tapper extends ColorRect:
	var trainer
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		color = Color(0.0, 0.01, 0.04, 0.5)
	func _has_point(p: Vector2) -> bool:
		if trainer == null or trainer.hud == null or not is_instance_valid(trainer.hud.pause_btn):
			return true
		return not trainer.hud.pause_btn.get_global_rect().grow(4.0).has_point(get_global_transform() * p)
	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
			accept_event()
			trainer.next()

# The big map of the tour (minimap.gd, large) with what he's talking about lit over it
class MapFx extends Control:
	var trainer
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	func _process(_dt: float) -> void:
		queue_redraw()
	func _draw() -> void:
		trainer._draw_map_fx(self)

func _unhandled_input(e: InputEvent) -> void:
	if holds() and phase != "wait" and e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		next()

# ---------------- the match ----------------
func begin(m) -> void:
	mode = m
	sim = m.sim
	hud = m.hud
	steps = K1 if which == 1 else K2
	hud.kill_feed_on = false                   # (his words instead)
	var me := _me()
	var t := int(me.get("team", 0))
	kael = _pick_kael(t)
	if which == 1:
		for tt in 2:
			for hid in sim.moba.heroes[tt]:
				var hh: Dictionary = sim.by_id.get(hid, {})
				if not hh.is_empty() and str(hid) != str(me.get("id", "")):
					hh.bot = false                  # (every other hero at his fountain; Kael's driven from here)
					hh.move = Vector2.ZERO
		sim.moba.wave_at = INF                      # no waves but the ones put down here
		for c in sim.moba.camps:
			c.next = INF                            # no camps either
		me.pos = _side(t, P_START)
		me.face = sim.angle_of(_side(t, Vector2(0, -1)))
		if not kael.is_empty():
			kael.pos = _side(t, P_START + Vector2(-2.0, -1.5))
			kael.face = me.face
			kael["m_out"] = SOFT
	else:
		if not kael.is_empty():
			kael.bot = false                        # (he goes where you go)
		for hid in sim.moba.heroes[1 - t]:
			var foe: Dictionary = sim.by_id.get(hid, {})
			if not foe.is_empty():
				foe["m_out"] = SOFT2
	_refresh_box()

func _pick_kael(t: int) -> Dictionary:
	# one of our bots becomes Kael: a Dragoon of ours if there is one, else the support (the jungler if you're it)
	var me := _me()
	var pick: Dictionary = {}
	for hid in sim.moba.heroes[t]:
		var u: Dictionary = sim.by_id.get(hid, {})
		if u.is_empty() or str(hid) == str(me.get("id", "")):
			continue
		if str(u.get("hid", "")) == KAEL_HID:
			pick = u
			break
		if pick.is_empty() or str(u.get("post", "")) == ("support" if str(me.get("post", "")) != "support" else "jungle"):
			pick = u
	if pick.is_empty():
		return {}
	sim.moba.swap_hero(pick, KAEL_HID)
	pick["bot_name"] = KAEL_NAME
	pick.bot = false
	pick.move = Vector2.ZERO
	return pick

func _me() -> Dictionary:
	return sim.by_id.get(hud.player_id, {}) if sim != null and hud != null else {}

static func _side(team: int, p: Vector2) -> Vector2:
	return p if team == 0 else -p

func holds() -> bool:
	# siege_mode: while true the match doesn't step (warming up, the map, the towers' lesson)
	return phase == "wait" or hold_kind != ""

func step_id() -> String:
	return str(steps[step].id) if step >= 0 and step < steps.size() else ""

func _keep(me: Dictionary) -> void:
	# the blessing, and the clock never runs out on a lesson (training 1)
	if me.is_empty() or not sim.alive(me):
		return
	me["dr"] = maxf(float(me.get("dr", 0.0)), TAKE if which == 1 else TAKE2)
	me["dr_until"] = float(sim.time) + 1.0
	if which == 1:
		if float(me.hp) < float(me.max_hp) * HP_FLOOR:
			me.hp = float(me.max_hp) * HP_FLOOR
		if not kael.is_empty() and sim.alive(kael) and float(kael.hp) < float(kael.max_hp) * HP_FLOOR:
			kael.hp = float(kael.max_hp) * HP_FLOOR
		for c in sim.moba.camps:
			if not bool(c.alive):
				c.next = INF
		if float(sim.match_time) - float(sim.time) < 120.0:
			sim.match_time = float(sim.match_time) + 600.0

# ---------------- the bar ----------------
func say(id: String) -> void:
	_queue.append(id)

static func lit(text: String) -> String:
	# the line in bbcode, its key words gold
	var rx := RegEx.new()
	var alts := []
	for k in KEYS:
		alts.append(str(k).replace("!", "\\!"))
	rx.compile("(?<![\\w])(" + "|".join(alts) + ")(?![\\w])")
	return rx.sub(text.replace("[", "(").replace("]", ")"), "[color=" + KEY_INK + "]$1[/color]", true)

func _start_line(id: String) -> void:
	_cur = id
	_last = id
	_shown = 0.0
	_line_t = 0.0
	lines_said.append(id)
	bar_text.text = lit(str(LINES.get(id, "")))
	bar_text.visible_characters = 0
	_play(voice, id)

func _play(p: AudioStreamPlayer, id: String) -> bool:
	p.stop()
	p.stream = null
	var master := 1.0
	var muted := false
	if mode != null and mode.audio != null:
		master = float(mode.audio.levels.get("master", 1.0))
		muted = bool(mode.audio.get("muted"))
	var path := VO_DIR + id + ".ogg"
	if muted or master <= 0.0 or not ResourceLoader.exists(path):
		return false
	p.stream = load(path)
	p.volume_db = linear_to_db(master * VOICE_GAIN)
	p.play()
	return true

func _tick_bar(dt: float) -> void:
	if _cur == "":
		if not _queue.is_empty():
			_start_line(str(_queue.pop_front()))
		else:
			_idle += dt
	if _cur != "":
		_line_t += dt
		var full := str(LINES.get(_cur, "")).length()
		_shown = minf(_shown + dt * TYPE_CPS, float(full))
		bar_text.visible_characters = -1 if _shown >= float(full) else int(_shown)
		# on when it's said and typed out (unvoiced -- muted -- when there's been time to read it)
		var least := float(full) / TYPE_CPS + 0.45
		if voice.stream == null:
			least = maxf(least, float(full) / 15.0 + 0.8)
		if not voice.playing and _line_t >= least:
			_cur = ""
			_idle = 0.0
			voice.stream = null
	bar.visible = _cur != "" or (_idle < 2.2 and _last != "") or hold_kind != ""

func next() -> void:
	# a tap while the match waits: the line typed out, then on to the next
	if phase == "over":
		return
	if _cur == "":
		return
	var full := str(LINES.get(_cur, "")).length()
	if _shown < float(full):
		_shown = float(full)
		return
	voice.stop()
	voice.stream = null
	_cur = ""
	_idle = 0.0

func _cut() -> void:
	# the line in the bar stops (the match is about to wait for a lesson of its own)
	voice.stop()
	voice.stream = null
	if _cur != "":
		_cur = ""
		_idle = 0.0

func bubble(id: String) -> void:
	if kael.is_empty() or not sim.alive(kael):
		return
	_bubble = id
	_bubble_until = _time + 2.4
	bubbles_said.append(id)
	if not voice.playing:
		_play(voice2, id)

# ---------------- steps ----------------
func _set_step(i: int, pre: Array = []) -> void:
	step = i
	_queue = pre.duplicate()
	if i >= steps.size():
		return
	for id in steps[i].get("say", []):
		_queue.append(str(id))
	_enter(step_id())
	_refresh_box()
	if mode != null and mode.get("analytics") != null:
		mode.analytics.log_ev("tutorial_step", {"step":i, "id":step_id()})

func _complete() -> void:
	var after: Array = steps[step].get("after", [])
	if str(steps[step].get("bubble", "")) != "":
		bubble(str(steps[step].bubble))
	if mode != null and mode.audio != null and mode.audio.has_method("play"):
		mode.audio.play("claim")
	_note = ""
	_set_step(step + 1, after)

func _enter(id: String) -> void:
	var me := _me()
	var t := int(me.get("team", 0))
	var et := 1 - t
	_goal = Vector2.INF
	match id:
		"move":
			_goal = _side(t, P_MOVE)
		"minions":
			_lh0 = int(me.get("lh", 0))
			_wave = sim.moba.place_minions(et, 1, WAVE, _side(t, P_WAVE))
		"hero":
			foes = [_put_foe(2, (me.pos as Vector2) + _side(t, Vector2(1.0, -11.0)))]
		"learn2":
			_level_to(2)
		"combo":
			foes = [_put_foe(0, (me.pos as Vector2) + _side(t, Vector2(-3.0, -11.0))), _put_foe(3, (me.pos as Vector2) + _side(t, Vector2(3.0, -12.0)))]
		"upgrade":
			_level_to(3)
		"ult":
			_level_to(4)
		"ult_use":
			_ult_used = false
			me["ult_cd"] = 0.0
			var c: Vector2 = (me.pos as Vector2) + _side(t, Vector2(0.0, -10.0))
			foes = [_put_foe(1, c + Vector2(-1.6, 0.0)), _put_foe(2, c + Vector2(1.6, 0.0)), _put_foe(4, c + _side(t, Vector2(0.0, -1.6)))]
		"shop":
			_bought = false
			var nb: Array = sim.moba.next_buys(me, 1)
			if not nb.is_empty():
				me.gold = maxf(float(me.gold), float(sim.moba.price(me, str(nb[0]))) + 60.0)
		"tower1":
			_tw = _tower(et, 1, 1)
			_weaken(_tw)
		"tower3":
			_tw = _tower(et, 1, 3)
			_weaken(_tw)
		"king":
			_tw = {}
			var k: Dictionary = sim.moba.kings[et]
			k.hp = minf(float(k.hp), float(k.max_hp) * KING_LEFT)
		"tour":
			hold_kind = "tour"
			_cut()
			_queue = TOUR.duplicate()
			_show_map(true)
		"go":
			var post := str(me.get("post", "top"))
			_queue.append(str(POST_GO.get(post, "k2_go_top")))
			_goal = _lane_goal(t, post)
		"m1", "m2", "m3", "m4":
			pass

func _tower(team: int, lane: int, tier: int) -> Dictionary:
	for tw in sim.moba.towers:
		if int(tw.team) == team and int(tw.lane) == lane and int(tw.tier) == tier:
			return tw
	return {}

func _weaken(tw: Dictionary) -> void:
	if not tw.is_empty() and not bool(tw.dead):
		tw.hp = minf(float(tw.hp), float(tw.max_hp) * TOWER_LEFT)

func _lane_goal(t: int, post: String) -> Vector2:
	if post == "jungle":
		for c in sim.moba.camps:
			if int(c.side) == t and str(c.kind) in ["arcane", "ember"]:
				return c.p
	var lane := int(sim.moba.POST_LANE.get(post, 1))
	var tw := _tower(t, lane, 1)
	return tw.p if not tw.is_empty() else sim.spawn(t)

func _level_to(n: int) -> void:
	var me := _me()
	while int(me.get("level", 1)) < n:
		sim.moba.add_xp(me, sim.moba.need(int(me.level)) - float(me.xp) + 0.1)

func _put_foe(i: int, at: Vector2) -> String:
	# training 1: an enemy hero, there, at half health, hitting softer
	var t := int(_me().team)
	var ids: Array = sim.moba.heroes[1 - t]
	var foe: Dictionary = sim.by_id.get(ids[clampi(i, 0, ids.size() - 1)], {})
	if foe.is_empty():
		return ""
	if not sim.alive(foe):
		sim._respawn(foe)
	foe.pos = at
	foe.move = Vector2.ZERO
	foe.state = "idle"
	foe.hp = float(foe.max_hp) * FOE_HP
	foe["m_out"] = SOFT
	foe.face = sim.angle_of((_me().pos as Vector2) - at)
	sim._event("recall_done", {"id":str(foe.id), "from":at, "to":at, "tut":true})     # (he arrives in a flash)
	return str(foe.id)

func _alive(ids: Array) -> Array:
	return ids.filter(func(id): return not sim.by_id.get(str(id), {}).is_empty() and sim.alive(sim.by_id[str(id)]))

func _done() -> bool:
	var me := _me()
	var t := int(me.get("team", 0))
	match step_id():
		"move":
			return (me.pos as Vector2).distance_to(_goal) <= 4.0
		"minions":
			return _alive(_wave).is_empty()
		"learn":
			return _learnt(me) >= 1
		"hero", "combo":
			return _alive(foes).is_empty()
		"learn2":
			return _learnt(me) >= 2
		"upgrade":
			for sl in ["q", "w", "e"]:
				if sim.moba.rank(me, sl) >= 2:
					return true
			return false
		"ult":
			return sim.moba.rank(me, "r") >= 1
		"ult_use":
			return _alive(foes).is_empty()
		"shop":
			return _bought
		"tower1", "tower3":
			return _tw.is_empty() or bool(_tw.dead)
		"king":
			return false                              # (the match ends: match_over)
		"tour":
			return hold_kind == ""
		"go":
			return (me.pos as Vector2).distance_to(_goal) <= 9.0
		"m1", "m2", "m3":
			var tier := int(step_id().substr(1))
			for tw in sim.moba.towers:
				if int(tw.team) != t and int(tw.tier) == tier and bool(tw.dead):
					return true
			return false
	return false

func _learnt(me: Dictionary) -> int:
	var n := 0
	for sl in ["q", "w", "e"]:
		if sim.moba.rank(me, sl) >= 1:
			n += 1
	return n

func progress() -> String:
	var me := _me()
	match step_id():
		"minions":
			return "%d/%d" % [_wave.size() - _alive(_wave).size(), _wave.size()]
		"combo":
			return "%d/2" % (foes.size() - _alive(foes).size())
		"ult_use":
			return "%d/3" % (foes.size() - _alive(foes).size())
		"tower1", "tower3":
			if not _tw.is_empty():
				return "Tower health %d%%" % int(ceil(100.0 * float(_tw.hp) / maxf(1.0, float(_tw.max_hp))))
		"king":
			var et := 1 - int(me.get("team", 0))
			return "King health %d%%" % int(ceil(100.0 * sim.moba.king_frac(et)))
	return ""

func _refresh_box() -> void:
	if step < 0 or step >= steps.size():
		box.visible = false
		return
	var st: Dictionary = steps[step]
	box_head.text = str(st.head)
	var task := str(st.task)
	if step_id() == "go":
		task = "Follow Kael to " + str(POST_NAME.get(str(_me().get("post", "top")), "your lane"))
	box_task.text = task
	box.visible = task != "" and phase == "play" and hold_kind == ""

# ---------------- every frame ----------------
func _process(delta: float) -> void:
	if sim == null:
		return
	_time += delta
	var me := _me()
	if phase != "over":
		_keep(me)
	voice.stream_paused = hud.paused()
	voice2.stream_paused = hud.paused()
	if hud.paused():
		return
	if phase == "wait":
		if mode == null or mode.warmed():
			phase = "play"
			_set_step(0)
			# (Honor of Kings' "Arcana Trial Privileges in effect!")
			hud.toast("KAEL'S BLESSING: you take half damage and can't fall" if which == 1 else "KAEL'S BLESSING: you take a quarter less damage", GOLD)
		_layout()
		return
	_tick_bar(delta)
	if hold_kind != "" and _cur == "" and _queue.is_empty():
		_end_hold()
	if phase == "play" and hold_kind == "" and not sim.ended:
		_ai -= delta
		if _ai <= 0.0:
			_ai = 0.1
			_drive_kael()
			if which == 1:
				_drive_foes()
		_tick_step(delta)
		if step < steps.size() and _done():
			_complete()
		_update_path(delta)
	if phase == "over" and _end_at >= 0.0 and _time >= _end_at and end_layer != null:
		_end_at = -1.0
		_show_card()
	box_prog.text = progress()
	box_prog.visible = box_prog.text != "" or (_note != "" and _time < _note_until)
	if _note != "" and _time < _note_until:
		box_prog.text = _note
	_refresh_box()
	if hud != null:
		hud.tut_modal = holds() or phase == "over"
	tapper.visible = hold_kind != ""
	tapper.color = Color(0.0, 0.01, 0.04, 0.55 if hold_kind == "tour" else 0.22)     # (the towers' lesson: the ring in sight)
	_layout()
	queue_redraw()

func _tick_step(_dt: float) -> void:
	var me := _me()
	if me.is_empty():
		return
	var t := int(me.team)
	var et := 1 - t
	match step_id():
		"move":
			if not kael.is_empty() and (me.pos as Vector2).distance_to(kael.pos) > 12.0 and _ready_for("over_here", 9.0):
				bubble("b_over_here")
		"minions":
			if int(me.get("lh", 0)) > _lh0 and _first("gold"):
				say("k1_gold")
		"ult_use":
			pass
		"tower1", "tower3", "king":
			var at: Vector2 = _tw.p if not _tw.is_empty() else sim.moba.king_pos(et)
			_deliver_army(at)
			if not _tw.is_empty() and not bool(_tw.dead):
				if sim.moba.in_tower_range(_tw, me.pos) and _first("tower"):
					say("k1_tower")
				if str(_tw.get("target", "")) == str(me.id) and _first("tower_red"):
					say("k1_tower_red")
					bubble("b_watch_out")
		"m1", "m2", "m3", "m4":
			_tick_battle(me, t, et)
	if which == 2 and step_id() == "go":
		_tick_battle(me, t, et)

func _deliver_army(at: Vector2) -> void:
	# training 1's towers and King: our minions walking in ahead of you, more when they're gone
	var me := _me()
	var t := int(me.team)
	if not _alive(_ours).filter(func(id): return (sim.by_id[str(id)].pos as Vector2).distance_to(at) < 26.0).is_empty():
		return
	if float(sim.time) - _ours_at < 6.0:
		return
	_ours_at = float(sim.time)
	var toward := _side(t, Vector2(0.0, 1.0))                   # (our side of it)
	var from := Vector2(0.0, at.y) + toward * 17.0
	_ours = sim.moba.place_minions(t, 1, ARMY, from)
	if step_id() != "tower1" or _once.has("army"):
		_note = "More of our minions -- let them go first"
		_note_until = _time + 3.0
	_once["army"] = true

func _tick_battle(me: Dictionary, t: int, et: int) -> void:
	# training 2's moments, each when it comes
	if not sim.alive(me):
		return
	# the towers' lesson: the first time you're by one of theirs (the match waits)
	if not _once.has("towers"):
		for tw in sim.moba.towers:
			if int(tw.team) == et and not bool(tw.dead) and (me.pos as Vector2).distance_to(tw.p) <= float(sim.moba.TOWER_RANGE) + 3.0:
				_once["towers"] = true
				_tw = tw
				hold_kind = "towers"
				_cut()
				_queue = TOWER_TALK.duplicate()
				return
	if float(me.hp) < float(me.max_hp) * 0.35 and not sim.in_castle(me.pos, t) and not sim.recalling(me) and _ready_for("recall", 90.0, 2):
		say("k2_recall")
		_guide_until["recall"] = _time + 8.0
	var nb: Array = sim.moba.next_buys(me, 1)
	if not nb.is_empty() and sim.moba.buy_why(me, str(nb[0])) == "" and not hud.shop_open() and _ready_for("shop", 150.0, 2):
		say("k2_shop")
		_guide_until["shop"] = _time + 8.0
	if sim.moba.king_open(et) and _first("king"):
		say("k2_king")
	for o in sim.moba.units_near(me.pos, 9.0):
		if int(o.team) == et and bool(o.get("hero", false)) and sim.alive(o) and sim.moba.can_see(t, o) and _ready_for("watch", 60.0):
			bubble("b_watch_out")
			break

func _first(key: String) -> bool:
	if _once.has(key):
		return false
	_once[key] = true
	return true

func _ready_for(key: String, every: float, most := 999) -> bool:
	var c: Array = _cool.get(key, [-INF, 0])
	if _time < float(c[0]) or int(c[1]) >= most:
		return false
	_cool[key] = [_time + every, int(c[1]) + 1]
	return true

func _end_hold() -> void:
	var was := hold_kind
	hold_kind = ""
	if was == "tour":
		_show_map(false)
		_complete()

func on_event(e: Dictionary) -> void:
	# (siege_mode passes on the match's events)
	var me := _me()
	if me.is_empty() or phase != "play":
		return
	var mine: bool = str(e.get("id", "")) == str(me.id)
	match str(e.get("k", "")):
		"buy":
			if mine:
				_bought = true
				if hud.shop_open() and which == 1:
					hud.close_shop()
		"ult":
			if mine:
				_ult_used = true
		"death":
			var dead: Dictionary = sim.by_id.get(str(e.get("id", "")), {})
			if str(e.get("by", "")) == str(me.id) and bool(dead.get("hero", false)) and which == 2 and _ready_for("nice", 30.0):
				bubble("b_nice")
		"tower_down":
			if which == 2 and int(e.get("team", -1)) != int(me.team) and _ready_for("tower_down", 20.0):
				bubble("b_well_done")
		"king_slam":
			if which == 1 and int(e.get("team", -1)) != int(me.team) and (me.pos as Vector2).distance_to(sim.moba.king_pos(int(e.team))) < 8.0 and _first("slam"):
				say("k1_king_slam")
		"recall":
			if not kael.is_empty() and str(e.get("id", "")) == str(kael.id):
				bubble("b_brb")
	_after_event(e)

func _after_event(e: Dictionary) -> void:
	# training 1: the bubbles at a lesson's end; the high ground once the outer tower falls
	if which != 1:
		return
	if str(e.get("k", "")) == "tower_down" and step_id() in ["tower1", "tower3"]:
		var me := _me()
		if int(e.get("tier", 0)) == 1:
			var inner := _tower(1 - int(me.team), int(e.get("lane", 1)), 2)       # our army takes their inner tower too
			if not inner.is_empty() and not bool(inner.dead):
				sim.moba.hit_tower(kael if not kael.is_empty() else me, int(inner.id), 1.0e9)

func _show_map(on: bool) -> void:
	if on:
		if map == null:
			map = Minimap.new()
			map.hud = hud
			map.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(map)
			var fx := MapFx.new()
			fx.trainer = self
			map.add_child(fx)
			skip_btn = Button.new()
			skip_btn.text = "SKIP  ›"
			skip_btn.focus_mode = Control.FOCUS_NONE
			skip_btn.add_theme_font_override("font", VisualTheme.BOLD_FONT)
			skip_btn.add_theme_font_size_override("font_size", 12)
			skip_btn.set_meta("action_key", "training_skip")
			var ks := _box(Color(0.04, 0.06, 0.15, 0.92), Color(VisualTheme.GOLD_DARK, 0.95), 10, 4)
			for st in ["normal", "hover", "pressed", "focus"]:
				skip_btn.add_theme_stylebox_override(st, ks)
			skip_btn.add_theme_color_override("font_color", GOLD)
			skip_btn.pressed.connect(func():
				_queue.clear()
				voice.stop()
				voice.stream = null
				_cur = "")
			add_child(skip_btn)
		map.visible = true
		skip_btn.visible = true
	elif map != null:
		map.visible = false
		skip_btn.visible = false

# ---------------- Kael and the foes ----------------
func _drive_kael() -> void:
	if kael.is_empty() or not sim.alive(kael) or kael.stun > 0.0 or str(kael.state) in ["wind", "recover", "dodge"]:
		return
	var me := _me()
	if me.is_empty():
		return
	var t := int(me.team)
	var et := 1 - t
	if int(kael.get("sp", 0)) > 0:
		sim.moba._bot_learn(kael)
	if sim.recalling(kael):
		kael.move = Vector2.ZERO
		return
	if which == 2:
		if fmod(_time, 3.0) < 0.1:
			sim.moba._bot_shop(kael)
		if float(kael.hp) < float(kael.max_hp) * 0.25 and _hero_near(kael, 8.0).is_empty() and not sim.in_castle(kael.pos, t):
			sim.act(str(kael.id), "recall")
			return
	var mid: Vector2 = me.pos
	# leading the way: on to the goal, waiting for you when you fall behind
	if _goal != Vector2.INF and step_id() in ["move", "go"]:
		var foe0 := _hero_near(kael, 7.0)
		if not foe0.is_empty():
			sim.moba._fight_h(kael, foe0)
			return
		var lag: float = (me.pos as Vector2).distance_to(kael.pos)
		var ahead: bool = (kael.pos as Vector2).distance_to(_goal) + 1.0 < (me.pos as Vector2).distance_to(_goal)
		if lag > 10.0 and ahead:
			kael.move = Vector2.ZERO
			kael.face = sim.angle_of((me.pos as Vector2) - (kael.pos as Vector2))
			return
		sim._nav_to(kael, _goal + _side(t, Vector2(-2.0, 1.0)), 1.0)
		return
	if not sim.alive(me):
		mid = sim.spawn(t)
	# a fight near you: their heroes first, then minions (in training 1 only the healthy ones: the last hits are yours)
	var foe: Dictionary = _hero_near(kael, 9.0) if (kael.pos as Vector2).distance_to(mid) < 14.0 else {}
	if foe.is_empty():
		for o in sim.moba.units_near(mid, 8.0):
			if int(o.team) == et and sim.alive(o) and bool(o.get("minion", false)) and (which == 2 or float(o.hp) > float(o.max_hp) * 0.5):
				foe = o
				break
	if not foe.is_empty():
		if not sim.moba._bot_ult(kael) and not sim.moba.kits.bot_spells(kael):
			sim.moba._fight_h(kael, foe)
		return
	# a structure you're at, with our minions under it
	var tw: Dictionary = sim.moba._enemy_tower_near(kael, 6.0)
	if not tw.is_empty() and sim.moba.in_tower_range(tw, me.pos) and str(tw.get("target", "")) != str(kael.id) and sim.moba.vulnerable(tw):
		sim.moba._hit_structure(kael, tw)
		return
	if sim.moba.king_open(et) and (me.pos as Vector2).distance_to(sim.moba.king_pos(et)) < 14.0:
		sim.moba._hit_point(kael, sim.moba.king_pos(et), sim.moba.KING_R)
		return
	# else at your side
	var spot: Vector2 = mid + _side(t, Vector2(-2.2, 2.4))
	if (kael.pos as Vector2).distance_to(spot) > 3.0:
		sim._nav_to(kael, spot, 1.5)
	else:
		kael.move = Vector2.ZERO

func _hero_near(u: Dictionary, r: float) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for o in sim.moba.units_near(u.pos, r):
		if int(o.team) == int(u.team) or int(o.team) > 1 or not sim.alive(o) or not bool(o.get("hero", false)):
			continue
		if which == 2 and not sim.moba.can_see(int(u.team), o):
			continue
		var d: float = (o.pos as Vector2).distance_to(u.pos)
		if d < bd:
			bd = d
			best = o
	return best

func _drive_foes() -> void:
	# training 1's enemy heroes come at you (or at Kael)
	var me := _me()
	for id in _alive(foes):
		var f: Dictionary = sim.by_id[str(id)]
		if f.stun > 0.0 or str(f.state) in ["wind", "recover", "dodge"]:
			continue
		var tgt: Dictionary = me if sim.alive(me) and (me.pos as Vector2).distance_to(f.pos) < 18.0 else {}
		if tgt.is_empty() and not kael.is_empty() and sim.alive(kael) and (kael.pos as Vector2).distance_to(f.pos) < 18.0:
			tgt = kael
		if tgt.is_empty():
			f.move = Vector2.ZERO
			continue
		sim.moba._fight_h(f, tgt)

# ---------------- the end ----------------
func match_over(we_won: bool) -> void:
	# (siege_mode, the match over: their King down -- or ours, or the clock): VICTORY or DEFEAT, his line, the card
	if phase == "over":
		return
	phase = "over"
	won = we_won
	hold_kind = ""
	_show_map(false)
	_queue.clear()
	_cur = ""
	voice.stop()
	say("k1_victory" if which == 1 else ("k2_victory" if won else "k2_defeat"))
	end_layer = Control.new()
	end_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(end_layer)
	move_child(end_layer, 0)                         # (under the bar)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.04, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_layer.add_child(dim)
	var big := Label.new()
	big.text = "VICTORY" if won else "DEFEAT"
	big.add_theme_font_override("font", VisualTheme.BOLD_FONT)
	big.add_theme_font_size_override("font_size", 64)
	big.add_theme_color_override("font_color", GOLD if won else Color("#c9d2e8"))
	big.add_theme_constant_override("outline_size", 10)
	big.add_theme_color_override("font_outline_color", Color(0.25, 0.12, 0.02) if won else Color(0.05, 0.07, 0.15))
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.size = Vector2(600, 80)
	big.position = Vector2(size.x * 0.5 - 300.0, size.y * 0.36 - 40.0)
	big.pivot_offset = Vector2(300, 40)
	big.scale = Vector2(1.6, 1.6)
	big.modulate.a = 0.0
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big.name = "Big"
	end_layer.add_child(big)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(big, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(big, "modulate:a", 1.0, 0.25)
	box.visible = false
	_end_at = _time + 1.4

func _show_card() -> void:
	# TRAINING COMPLETE, the gold (once), CONTINUE
	var pays: bool = mode != null and mode.has_method("tutorial_pays") and mode.tutorial_pays()
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(Color(0.04, 0.06, 0.15, 0.96), GOLD, 14, 12))
	card.name = "Card"
	end_layer.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(v)
	var hd := _label(v, "TRAINING %d COMPLETE" % which, 18, GOLD)
	hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _label(v, ("You've learnt the basics -- the 5v5 battle training is next." if which == 1 else "You're ready for a real match."), 12, Color("#d8d0c0"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if pays:
		var g := _label(v, "+%d GOLD" % Eco.TUTORIAL_GOLD, 20, Color("#ffd65a"))
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var b := Button.new()
	b.text = "CONTINUE"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(200, 40)
	b.add_theme_font_override("font", VisualTheme.BOLD_FONT)
	b.add_theme_font_size_override("font_size", 16)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color("#e8a530")
	bs.border_color = Color("#ffe9a6")
	bs.set_border_width_all(2)
	bs.set_corner_radius_all(10)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, bs)
	b.add_theme_color_override("font_color", Color("#3a1c00"))
	b.set_meta("action_key", "training_continue")
	b.pressed.connect(func():
		voice.stop()
		if mode != null:
			mode.finish_tutorial())
	var cc := CenterContainer.new()
	cc.add_child(b)
	v.add_child(cc)
	card.reset_size()
	card.position = Vector2(size.x * 0.5 - card.size.x * 0.5, size.y * 0.36 + 52.0)

# ---------------- layout ----------------
func _layout() -> void:
	if bar == null:
		return
	if hold_kind == "tour" or phase == "over":
		var w := minf(560.0, size.x - 40.0)
		bar.custom_minimum_size = Vector2(w, 0)
		bar.reset_size()
		bar.position = Vector2(size.x * 0.5 - w * 0.5, size.y - bar.size.y - 12.0)
	else:
		# the top middle: between the map's column and the box
		var left := 156.0
		var right := size.x - 222.0
		var w2 := clampf(right - left, 280.0, 470.0)
		bar.custom_minimum_size = Vector2(w2, 0)
		bar.reset_size()
		bar.position = Vector2(left + maxf(0.0, (right - left - w2) * 0.5), 58.0)
	var bw := 204.0
	box.custom_minimum_size = Vector2(bw, 0)
	box.reset_size()
	box.position = Vector2(size.x - bw - 8.0, 54.0)
	if map != null and map.visible:
		var ms := minf(size.y - bar.size.y - 40.0, 300.0)
		map.size = Vector2(ms, ms)
		map.position = Vector2(size.x * 0.5 - ms * 0.5, maxf(8.0, (size.y - bar.size.y - 20.0 - ms) * 0.5))
		skip_btn.position = Vector2(map.position.x + ms + 12.0, map.position.y)

# ---------------- guidance ----------------
func guide() -> Dictionary:
	# what to point at now: "pos" (a world point, its "label"), "button" (a HUD button), "learn" (a + to tap), "rect"
	# (a HUD rect: the quick-buy), "stick"
	var me := _me()
	if me.is_empty() or phase != "play" or hold_kind != "":
		return {}
	var t := int(me.team)
	var et := 1 - t
	match step_id():
		"move":
			var g := {"pos": _goal, "label": "FOLLOW KAEL", "route": true}
			if (me.pos as Vector2).distance_to(_side(t, P_START)) < 2.0:
				g["stick"] = true
			return g
		"minions":
			var best: Dictionary = {}
			for id in _alive(_wave):
				var m: Dictionary = sim.by_id[str(id)]
				if best.is_empty() or (m.pos as Vector2).distance_to(me.pos) < (best.pos as Vector2).distance_to(me.pos):
					best = m
			if best.is_empty():
				return {}
			return {"pos": best.pos, "label": "ENEMY MINIONS", "small": true, "button": "attack"}
		"learn", "learn2", "upgrade", "ult":
			var want := ""
			for sp in hud.learn_spots(me):
				var sl := str(sp.slot)
				if step_id() == "ult" and sl != "r":
					continue
				if step_id() == "upgrade" and sim.moba.rank(me, sl) < 1:
					continue
				if step_id() == "learn2" and sim.moba.rank(me, sl) >= 1:
					continue
				want = sl
				break
			return {"learn": want} if want != "" else {}
		"hero", "combo", "ult_use":
			var near: Dictionary = {}
			for id in _alive(foes):
				var f: Dictionary = sim.by_id[str(id)]
				if near.is_empty() or (f.pos as Vector2).distance_to(me.pos) < (near.pos as Vector2).distance_to(me.pos):
					near = f
			if near.is_empty():
				return {}
			var gi := {"pos": near.pos, "label": "ENEMY HERO", "small": true}
			if step_id() == "ult_use" and not _ult_used and sim.moba.ult_ready(me):
				gi["button"] = "ult"
			elif step_id() == "hero":
				gi["button"] = _skill_button(me)
			return gi
		"shop":
			var qr: Array = hud.quick_rects(me)
			return {"rect": (qr[0].r as Rect2)} if not qr.is_empty() and not _bought else {}
		"tower1", "tower3":
			if _tw.is_empty() or bool(_tw.dead):
				return {}
			var gt := {"pos": _tw.p, "label": "ENEMY TOWER", "ring": 2.6, "lift": 7.0, "route": (me.pos as Vector2).distance_to(_tw.p) > 16.0}
			if sim.moba.in_tower_range(_tw, me.pos) and str(_tw.get("target", "")) != str(me.id):
				gt["button"] = "attack"
			return gt
		"king":
			var kp: Vector2 = sim.moba.king_pos(et)
			return {"pos": kp, "label": "ENEMY KING", "ring": 2.2, "lift": 5.0, "route": (me.pos as Vector2).distance_to(kp) > 14.0}
		"go":
			return {"pos": _goal, "label": "FOLLOW KAEL", "route": true}
		"m1", "m2", "m3", "m4":
			var gb := {}
			if _time < float(_guide_until.get("recall", -1.0)) and not sim.recalling(me):
				gb["button"] = "recall"
			elif _time < float(_guide_until.get("shop", -1.0)):
				var qr2: Array = hud.quick_rects(me)
				if not qr2.is_empty():
					gb["rect"] = qr2[0].r
			var target := _mission_target(me, t, et)
			if target != Vector2.INF and (me.pos as Vector2).distance_to(target) > 18.0:
				gb["pos"] = target
				gb["label"] = "ENEMY KING" if step_id() == "m4" else "ENEMY TOWER"
				gb["lift"] = 7.0
				gb["ring"] = 2.6
				gb["faint"] = true
			return gb
	return {}

func _skill_button(me: Dictionary) -> String:
	for b in hud._buttons():
		var sl := str(hud.SLOT_OF.get(str(b.id), ""))
		if sl in ["q", "w", "e"] and sim.moba.rank(me, sl) >= 1:
			return str(b.id)
	return "attack"

func _mission_target(me: Dictionary, t: int, et: int) -> Vector2:
	if step_id() == "m4":
		return sim.moba.king_pos(et) if sim.moba.king_open(et) else Vector2.INF
	var tier := int(step_id().substr(1))
	var lane := int(sim.moba.POST_LANE.get(str(me.get("post", "mid")), 1))
	var best := Vector2.INF
	var bd := INF
	for tw in sim.moba.towers:
		if int(tw.team) != et or bool(tw.dead) or int(tw.tier) != tier or not sim.moba.vulnerable(tw):
			continue
		var d: float = (me.pos as Vector2).distance_to(tw.p) - (40.0 if int(tw.lane) == lane else 0.0)
		if d < bd:
			bd = d
			best = tw.p
	return best

func _update_path(delta: float) -> void:
	_path_clock -= delta
	if _path_clock > 0.0:
		return
	_path_clock = 0.4
	var g := guide()
	var me := _me()
	_path = sim.find_path(int(me.team), me.pos, g.pos) if g.has("pos") and bool(g.get("route", false) or g.get("faint", false)) and not me.is_empty() else PackedVector2Array()

func _w(p: Vector2, lift := 0.15) -> Vector3:
	return Vector3(p.x, Sim.height_at(p) + lift, p.y)

func _plate(center: Vector2, text: String, fs := 13) -> void:
	var font: Font = VisualTheme.BOLD_FONT
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 18.0
	var r := Rect2(center.x - w * 0.5, center.y - 12, w, 24)
	draw_rect(r.grow(2), INK)
	draw_rect(r, Color(0.12, 0.09, 0.03, 0.95))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), GOLD)
	draw_string(font, Vector2(r.position.x + 9, r.position.y + 17), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

func _arrow(tip: Vector2, s: float, up := false) -> void:
	var k := -1.0 if up else 1.0
	var pts := PackedVector2Array([tip, tip + Vector2(-20, -24 * k) * s, tip + Vector2(-8, -24 * k) * s, tip + Vector2(-8, -46 * k) * s,
		tip + Vector2(8, -46 * k) * s, tip + Vector2(8, -24 * k) * s, tip + Vector2(20, -24 * k) * s])
	var c := Vector2.ZERO
	for q in pts:
		c += q
	c /= pts.size()
	var out := PackedVector2Array()
	for q in pts:
		out.append(c + (q - c) * 1.18)
	draw_colored_polygon(out, INK)
	draw_colored_polygon(pts, GOLD)

func _hand(tip: Vector2) -> void:
	# Honor of Kings' hand: a white glove, its finger pressing on the spot
	var press := 0.5 + 0.5 * sin(_time * 6.0)
	var o := tip + Vector2(4.0, 6.0) + Vector2(5.0, 7.0) * press
	var f1 := o + Vector2(10.0, 24.0)
	var palm := o + Vector2(19.0, 40.0)
	for pass_ in 2:
		var col := INK if pass_ == 0 else Color(1, 1, 1, 0.97)
		var g := 3.0 if pass_ == 0 else 0.0
		draw_line(o, f1, col, 12.0 + g * 2.0, true)
		draw_circle(o, 6.0 + g, col)
		draw_circle(palm, 15.0 + g, col)
		draw_circle(palm + Vector2(9.0, -10.0), 7.0 + g, col)
		draw_circle(palm + Vector2(15.0, -3.0), 6.5 + g, col)
		draw_line(palm + Vector2(-10.0, -2.0), palm + Vector2(-17.0, -12.0), col, 9.0 + g * 2.0, true)
		draw_circle(palm + Vector2(-17.0, -12.0), 4.5 + g, col)
	draw_arc(tip, 10.0 + 10.0 * (1.0 - press), 0.0, TAU, 32, Color(1, 1, 1, 0.55 * press), 3.0, true)

func _draw() -> void:
	if sim == null or phase == "wait":
		return
	var me := _me()
	if me.is_empty():
		return
	_draw_bubble()
	if hold_kind == "towers":
		_draw_tower_card()
	if phase != "play" or hold_kind != "":
		return
	var g := guide()
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	if g.has("stick"):
		var base := Vector2(maxf(215.0, size.x * 0.27), size.y - 112.0)     # (right of the quick-buy)
		draw_circle(base, 44.0, Color(1, 1, 1, 0.08))
		draw_arc(base, 44.0, 0.0, TAU, 48, Color(GOLD, 0.7), 3.0, true)
		var thumb := base + Vector2.from_angle(_time * 2.2) * 24.0
		draw_circle(thumb, 16.0, INK)
		draw_circle(thumb, 13.0, GOLD)
		_hand(thumb)
		_plate(base + Vector2(0, -62), "DRAG TO MOVE")
	if g.has("button") and str(g.button) != "":
		for b in hud._buttons():
			if str(b.id) == str(g.button):
				var rr: float = float(b.r) + 8.0 + 6.0 * pulse
				draw_arc(b.c, rr + 3.0, 0.0, TAU, 48, INK, 8.0, true)
				draw_arc(b.c, rr, 0.0, TAU, 48, GOLD, 5.0, true)
				_hand(b.c)
	if g.has("learn") and str(g.learn) != "":
		for sp in hud.learn_spots(me):
			if str(sp.slot) == str(g.learn):
				draw_arc(sp.c, 20.0 + 6.0 * pulse, 0.0, TAU, 40, GOLD, 4.0, true)
				_hand(sp.c)
				_plate((sp.c as Vector2) + Vector2(-70.0, -34.0), "TAP +")
	if g.has("rect"):
		var r: Rect2 = (g.rect as Rect2).grow(4.0 + 3.0 * pulse)
		draw_rect(r.grow(2.0), INK, false, 5.0)
		draw_rect(r, GOLD, false, 3.5)
		_hand(Vector2(r.end.x - 10.0, r.get_center().y))
	if not g.has("pos"):
		return
	var tgt: Vector2 = g.pos
	var faint: bool = g.get("faint", false)
	var pts := PackedVector2Array([me.pos])
	pts.append_array(_path)
	pts.append(tgt)
	if g.get("route", false) or faint:
		# the dotted path, marching toward the target (Honor of Kings' "Follow me!")
		var step_len := 1.2
		var along := fmod(_time * 2.4, step_len)
		var walked := 0.0
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b2: Vector2 = pts[i + 1]
			var seg := a.distance_to(b2)
			while along < seg and walked + along < 36.0:
				var wq := _w(a.lerp(b2, along / maxf(seg, 0.001)))
				if hud.on_screen.call(wq):
					var sq: Vector2 = hud.project.call(wq)
					draw_circle(sq, 6.0, Color(INK, 0.5 if faint else 0.9))
					draw_circle(sq, 4.2, Color(GOLD, 0.55 if faint else 1.0))
				along += step_len
			along -= seg
			walked += seg
	var route := 0.0
	var guide_p: Vector2 = tgt
	var got := false
	for i in range(pts.size() - 1):
		var seg2: float = (pts[i] as Vector2).distance_to(pts[i + 1])
		if not got and route + seg2 >= 8.0:
			guide_p = (pts[i] as Vector2).lerp(pts[i + 1], (8.0 - route) / maxf(seg2, 0.001))
			got = true
		route += seg2
	var label := str(g.get("label", "HERE")) + ("" if g.get("small", false) or route < 5.0 else "  %d m" % int(round(route)))
	if hud.on_screen.call(_w(tgt, 0.0)):
		var ring := PackedVector2Array()
		var rad: float = g.get("ring", 0.9 if g.get("small", false) else 1.4)
		for k in 33:
			ring.append(hud.project.call(_w(tgt + Vector2.from_angle(TAU * k / 32.0) * rad, 0.08)))
		draw_polyline(ring, INK, 7.0, true)
		draw_polyline(ring, GOLD, 4.0, true)
		if not faint:
			var tip: Vector2 = hud.project.call(_w(tgt, float(g.get("lift", 2.4)))) + Vector2(0, -8.0 * pulse)
			var above := Rect2(tip.x - 90.0, tip.y - 80.0, 180.0, 80.0)        # (the arrow and its plate, over the target)
			var clear: bool = tip.y - 90.0 > (bar.get_rect().end.y + 6.0 if bar.visible else 60.0) \
				and not (box.visible and box.get_rect().grow(6.0).intersects(above))
			if clear:
				_arrow(tip, 0.9)
				_plate(tip + Vector2(0, -66), label)
			else:
				var tip2: Vector2 = hud.project.call(_w(tgt, 0.0)) + Vector2(0, 22.0 + 8.0 * pulse)
				_arrow(tip2, 0.9, true)
				_plate(tip2 + Vector2(0, 66), label)
	else:
		var center := size * 0.5
		var from_s: Vector2 = hud.project.call(_w(me.pos, 1.0))
		var to_s: Vector2 = hud.project.call(_w(guide_p, 1.0))
		var dir := (to_s - from_s).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2(0, -1)
		var edge := center + dir * minf(size.x * 0.36, size.y * 0.28)
		var side := Vector2(-dir.y, dir.x)
		var a2 := 0.55 if faint else 1.0
		draw_colored_polygon(PackedVector2Array([edge + dir * 34, edge - dir * 16 + side * 26, edge - dir * 16 - side * 26]), Color(INK, 0.9 * a2))
		draw_colored_polygon(PackedVector2Array([edge + dir * 28, edge - dir * 12 + side * 20, edge - dir * 12 - side * 20]), Color(GOLD, a2))
		if not faint:
			_plate(edge - dir * 44, label)

func _draw_bubble() -> void:
	# his quip over his head, a white bubble with its tail down to him
	if _bubble == "" or _time >= _bubble_until or kael.is_empty() or not sim.alive(kael):
		return
	var head := _w(kael.pos, 3.4)
	if not hud.on_screen.call(head):
		return
	var p: Vector2 = hud.project.call(head)
	var text := str(LINES.get(_bubble, ""))
	var font: Font = VisualTheme.BOLD_FONT
	var fs := 13
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 22.0
	var age := _time - (_bubble_until - 2.4)
	var k := clampf(age / 0.15, 0.0, 1.0) * clampf((_bubble_until - _time) / 0.3, 0.0, 1.0)
	var r := Rect2(p.x - w * 0.5, p.y - 40.0, w, 28.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.96 * k)
	sb.border_color = Color(0.1, 0.12, 0.2, 0.9 * k)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.anti_aliasing = true
	draw_colored_polygon(PackedVector2Array([Vector2(p.x - 8, r.end.y - 2), Vector2(p.x + 8, r.end.y - 2), Vector2(p.x, r.end.y + 10)]), Color(0.1, 0.12, 0.2, 0.9 * k))
	draw_style_box(sb, r)
	draw_colored_polygon(PackedVector2Array([Vector2(p.x - 6, r.end.y - 3), Vector2(p.x + 6, r.end.y - 3), Vector2(p.x, r.end.y + 6)]), Color(1, 1, 1, 0.96 * k))
	draw_string(font, Vector2(r.position.x + 11, r.position.y + 19), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.12, 0.22, k))

func _draw_tower_card() -> void:
	# the towers' lesson: what each colour of its ring means, the one he's on lit
	var cur := _cur if _cur != "" else _last
	var rows := [["yellow", "NEAR IT", "k2_tw2"], ["red", "SHOOTING YOU", "k2_tw3"], ["green", "SHOOTING A MINION: ATTACK", "k2_tw6"]]
	var lit_rows := {"k2_tw2": 0, "k2_tw3": 1, "k2_tw4": 2, "k2_tw5": 2, "k2_tw6": 2, "k2_tw7": 1}
	var font: Font = VisualTheme.BOLD_FONT
	var w := 300.0
	var r := Rect2(size.x * 0.5 - w * 0.5, size.y - 124.0, w, 112.0)        # (low, the tower and its ring in sight)
	draw_rect(r.grow(2.0), INK)
	draw_rect(r, Color(0.04, 0.06, 0.15, 0.94))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), GOLD)
	draw_string(font, r.position + Vector2(12, 20), "A TOWER'S RING", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GOLD)
	for i in rows.size():
		var y := r.position.y + 40.0 + 26.0 * float(i)
		var col: Color = View_RING[str(rows[i][0])]
		var on: bool = int(lit_rows.get(cur, -1)) == i
		var c := Vector2(r.position.x + 30.0, y)
		draw_arc(c, 10.0, 0.0, TAU, 28, Color(col, 1.0), 4.0 if on else 2.5, true)
		draw_circle(c, 3.5, Color(0.8, 0.8, 0.85))
		draw_string(font, c + Vector2(22, 5), str(rows[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13 if on else 12, Color.WHITE if on else Color(1, 1, 1, 0.6))
	if not _tw.is_empty() and hud.on_screen.call(_w(_tw.p, 0.0)):
		var tip: Vector2 = hud.project.call(_w(_tw.p, 7.0)) + Vector2(0, -6.0 * (0.5 + 0.5 * sin(_time * 5.0)))
		if tip.y > 60.0:
			_arrow(tip, 0.8)

const View_RING := {"yellow": Color(1.0, 0.85, 0.35), "red": Color(1.0, 0.25, 0.2), "green": Color(0.35, 1.0, 0.45)}

func _draw_map_fx(c: Control) -> void:
	# the tour: on the big map, what his line is about
	if map == null:
		return
	var cur := _cur if _cur != "" else _last
	var me := _me()
	var t := int(me.get("team", 0))
	var et := 1 - t
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	var lanes := []
	match cur:
		"k2_lanes", "k2_roles":
			lanes = [0, 1, 2]
		"k2_top":
			lanes = [0]
		"k2_mid", "k2_win1":
			lanes = [1]
		"k2_bot":
			lanes = [2]
		"k2_ready":
			var post := str(me.get("post", "mid"))
			if post != "jungle":
				lanes = [int(sim.moba.POST_LANE.get(post, 1))]
	for l in lanes:
		var pl := PackedVector2Array()
		for p in sim.moba.LANES[l]:
			pl.append(map.to_map(p))
		c.draw_polyline(pl, Color(GOLD, 0.35 + 0.3 * pulse), 12.0, true)
		c.draw_polyline(pl, Color(1.0, 0.95, 0.7, 0.9), 3.0, true)
	var font: Font = VisualTheme.BOLD_FONT
	if cur in ["k2_roles", "k2_top", "k2_mid", "k2_bot", "k2_jungle", "k2_ready"]:
		var names := {0: "TOP", 1: "MID", 2: "BOTTOM"}
		for l in [0, 1, 2]:
			var pts: Array = sim.moba.LANES[l]
			var at: Vector2 = map.to_map(pts[(pts.size() >> 1) if l == 1 else (pts.size() >> 1) - 3])
			if cur in ["k2_roles"] or lanes.has(l):
				_map_tag(c, font, at, str(names[l]))
	if cur in ["k2_jungle", "k2_roles"]:
		for camp in sim.moba.camps:
			if int(camp.side) in [0, 1]:
				c.draw_arc(map.to_map(camp.p), 5.0 + 3.0 * pulse, 0.0, TAU, 20, Color("#c58bff"), 2.0, true)
		_map_tag(c, font, map.to_map(_side(t, Vector2(-34.0, 30.0))), "JUNGLE")
	if cur == "k2_minions":
		for l in [0, 1, 2]:
			var pts2: Array = sim.moba.LANES[l]
			for side in 2:
				for k in 4:
					var f := fmod(_time * 0.12 + float(k) * 0.07, 0.5)
					var u: float = f if side == 0 else 1.0 - f
					c.draw_circle(map.to_map(_along(pts2, u)), 2.6, Color("#4fc3ff") if side == t else Color("#ff5a4a"))
	if cur in ["k2_towers", "k2_win1"]:
		for tw in sim.moba.towers:
			if cur == "k2_win1" and (int(tw.team) != et or int(tw.lane) != 1):
				continue
			var tp: Vector2 = map.to_map(tw.p)
			var on := true
			if cur == "k2_win1":
				on = fmod(_time * 1.5, 3.0) >= float(int(tw.tier) - 1)
			if on:
				c.draw_arc(tp, 7.0 + 3.0 * pulse, 0.0, TAU, 20, GOLD, 2.5, true)
	if cur == "k2_win2":
		var kp: Vector2 = map.to_map(sim.moba.king_pos(et))
		c.draw_arc(kp, 10.0 + 5.0 * pulse, 0.0, TAU, 28, GOLD, 3.0, true)
		_map_tag(c, font, kp + (Vector2(-38, 26) if kp.x > c.size.x * 0.5 else Vector2(38, -26)), "THEIR KING")
	if cur == "k2_welcome":
		_map_tag(c, font, map.to_map(sim.moba.king_pos(t)) + Vector2(0, -20), "US")
		_map_tag(c, font, map.to_map(sim.moba.king_pos(et)) + Vector2(0, 20), "THEM")

func _along(pts: Array, u: float) -> Vector2:
	var total := 0.0
	for i in range(pts.size() - 1):
		total += (pts[i] as Vector2).distance_to(pts[i + 1])
	var want := total * clampf(u, 0.0, 1.0)
	for i in range(pts.size() - 1):
		var seg: float = (pts[i] as Vector2).distance_to(pts[i + 1])
		if want <= seg:
			return (pts[i] as Vector2).lerp(pts[i + 1], want / maxf(seg, 0.001))
		want -= seg
	return pts[pts.size() - 1]

func _map_tag(c: Control, font: Font, at: Vector2, text: String) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0
	var r := Rect2(at.x - w * 0.5, at.y - 9.0, w, 18.0)
	c.draw_rect(r, Color(0.04, 0.05, 0.1, 0.88))
	c.draw_rect(r, Color(GOLD, 0.9), false, 1.5)
	c.draw_string(font, Vector2(r.position.x + 6, r.position.y + 13), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
