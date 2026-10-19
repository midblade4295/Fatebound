extends Control
# 0.31.181 THE 5V5 TUTORIAL (Kevin: "Now create a tutorial walking player through the basics of a match. Things like how
# buying works, economy in game, trying not to die because feeds enemy team economy. Benefits of building up team
# economy with minions and jungling ect ect. Make it voiced and make it humorous and sarcastic").
#
# A 5v5 against bots, made quiet (siege_mode.gd tutorial = true; begin() below): every hero but you stays at his
# fountain ("a tea break"), no waves and no camps of their own, and you can't fall (half damage, and a floor under
# your health). Over it, under the HUD's pause button and panels, this overlay: the Royal Herald talks -- the match
# waits (siege_mode doesn't step it while holds()), the line typed out on his proclamation scroll as he says it, a tap
# for the next -- then sets a task to DO in the live match, checked every frame, with guidance drawn over the world
# (a marching dotted route, a ring and an arrow on the target, an edge arrow when it's off screen) or a TAP / HOLD ring
# on the HUD's button. What a task needs is put there by the tutorial ("royal paperwork"): a wave each side to
# last-hit, our Grave Archers camp, our minions walking under their tower, a hop to where it all is.
#
# 0.31.182 (Kevin, of the dialog: "make it so he blends into text box seamlessly" -> concept D, the scroll, "but also
# have him doing some funny stuff with the scroll like sometimes he's laying on top of it and sometimes leaning on it"):
# each line is written on the scroll, the Herald with it in one of eight poses (scroll_<pose>.png, ElevenLabs; their
# parchment and its clear part in tutorial_poses.gd): holding it open, lying on it, leaning on it, sitting on it with
# his tea, peeking over it, asleep on it, standing on it with a pointer, hanging off it. The scroll as wide as it can be
# with all of him on the screen; the line in the clear part of its parchment, the biggest type that fits.
# VOICE: assets/vo/tutorial/<id>.ogg, the Herald's voice (ElevenLabs; art_sources/tutorial: script.json, the prompts;
# tools/build_tutorial_assets.py). The captions here are script.json's lines (tests/tutorial_test.gd checks).
const Sim = preload("res://scripts/siege/siege_sim.gd")
const VisualTheme = preload("res://scripts/ui/visual_theme.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const VO_DIR := "res://assets/vo/tutorial/"
const Poses = preload("res://scripts/siege/tutorial_poses.gd")
const POSE_PATH := "res://assets/ui/tutorial/scroll_%s.png"
const INK_TEXT := Color("#3e2610")             # (the scroll's writing)
const INK_HINT := Color("#8c241e")
const SCROLL_SIDE := 18.0                      # the parchment at most the screen less this each side
const SCROLL_FIT := 4.0                        # ...and all of the Herald on the screen, this from its edges
const SCROLL_BOTTOM := 32.0                    # the parchment's foot this above the screen's (TAP TO CONTINUE under it)
const LINE_GAP := -3                           # the writing's lines a little closer than the font's own
const TEXT_PX := [17, 16, 15, 14, 13, 12]
const TYPE_CPS := 42.0
const VOICE_GAIN := 0.55          # x master (the Herald's match calls: 0.5)
const LH_GOAL := 2
const TOWER_HITS := 3
const SHIELD_FOR := 0.6
const HP_FLOOR := 0.3             # (you can't fall in the tutorial)
const TAKE := 0.5                 # ...and take half damage
const LANE_AT := Vector2(3.0, 24.0)          # (blue's; red's the point mirror) behind our minions, out of our tower's reach
const LANE_OURS := Vector2(0.0, 19.0)        # where our wave is put down, walking north
const LANE_THEIRS := Vector2(0.0, -3.0)      # ...theirs, walking south: they meet near the middle
const LANE_KINDS := ["melee", "melee", "melee", "caster", "caster", "caster"]
const TOWER_KINDS := ["melee", "melee", "melee", "melee", "caster", "caster"]
const CAMP_WEAK := 0.6            # the tutorial's Grave Archers: "a bit under the weather"

# Each step: talk (lines before the task), task (shown as the objective), done (lines once it's done). A line is
# [voice id, caption, the Herald's pose]. "@pay": the last line, by whether the tutorial's gold is still to be paid.
const STEPS := [
	{"id":"intro", "talk":[
		["t5_intro_1", "Ah. A new recruit. How thrilling. I'm the Royal Herald. I announce things. Today I announce you. And, I suspect, your mistakes.", "hold"],
		["t5_intro_2", "This is the Rift. Five of us, five of them, three lanes, and a King on each side. Knock theirs off his throne and we win. Simple. You'd be amazed.", "lying"]]},
	{"id":"move", "talk":[
		["t5_move_1", "Let's begin with walking. Drag your thumb on the left side of the screen. You can do it. I believe in you. Mildly.", "leaning"]],
		"task":"Drag on the left side of the screen to walk",
		"done":[["t5_move_done", "Legs! Working legs. The bards are already writing a song about it. A short one.", "sitting"]]},
	{"id":"lane", "talk":[
		["t5_lane_1", "Both castles send waves of minions down every lane. They march, they fight, they die. Nobody writes them songs either.", "napping"],
		["t5_lane_2", "Here's the secret: a minion pays its gold only to whoever lands the killing blow. That's a last hit. Softening it up earns you nothing but sore arms.", "peeking"],
		["t5_lane_3", "I've had a wave delivered. Wait until an enemy minion is nearly dead, then finish it off. Two last hits, please. I'll be counting.", "pointing"]],
		"task":"Land the killing blow on 2 enemy minions",
		"done":[["t5_lh_done", "Gold! Funny how it turns up when you actually finish things. There's a life lesson in there. I shan't spell it out.", "hanging"]]},
	{"id":"eco", "talk":[
		["t5_eco_1", "Gold is everything here. Minions, monsters, towers and enemy heroes all pay. Even standing about pays a trickle, which explains a great many recruits.", "napping"],
		["t5_eco_2", "And it's not just your gold. The whole team's gold decides who wins the big fights. Tap the score bar at the top to see everyone's.", "pointing"]],
		"task":"Tap the score bar at the top",
		"done":[["t5_eco_done", "Our gold, their gold, and who's slacking. Close it when you've finished judging people. I never have.", "sitting"]]},
	{"id":"recall", "talk":[
		["t5_recall_1", "Pockets full? Then go home and spend it. Tap HOME to recall. It takes six seconds, and anything that hits you cancels it. So perhaps not next to the enemy. Just a thought.", "peeking"]],
		"task":"Tap HOME, then stand still for 6 seconds",
		"done":[["t5_recall_done", "Home sweet castle. The fountain heals you, and the shop serves you here. Or while you're dead. Retail is grim.", "leaning"]]},
	{"id":"shop", "talk":[
		["t5_shop_1", "Tap SHOP and buy an item. Items make you hit harder, live longer, and look slightly less doomed. Can't decide? The shop suggests things. Like me, but less charming.", "lying"]],
		"task":"Open the SHOP and buy an item",
		"done":[["t5_shop_done", "A purchase! Remember: gold in your pocket does nothing. Gold turned into swords does a great deal.", "hold"]]},
	{"id":"abilities", "talk":[
		["t5_ab_1", "Now, your tricks. Q, W and E are your abilities, and R, your ultimate, arrives at level six. I've had you promoted to level three. Paperwork. Don't ask.", "peeking"],
		["t5_ab_2", "Hold Q to raise your shield. Tap W to bash, and E to rally. Each level also brings an upgrade card, so pick one. Try everything, so I know it all works.", "lying"]],
		"task":"Hold Q, tap W, tap E, and pick your upgrades",
		"done":[["t5_ab_done", "A shield, a shove and a pep talk. Very knightly. Very you.", "leaning"]]},
	{"id":"jungle", "talk":[
		["t5_jg_1", "Between the lanes lies the jungle, full of monsters. Rude ones. Clear a camp and it pays gold and experience. Some even leave a buff that makes you stronger.", "napping"],
		["t5_jg_2", "Our Grave Archers are just over there. Go and clear the camp. They do hit back, so keep that shield handy.", "hanging"]],
		"task":"Clear the Grave Archers camp",
		"done":[["t5_jg_done", "Cleared! That's the jungle: a team that takes its camps out-earns one that doesn't. Free gold. Well. Paid for in bruises.", "hold"]]},
	{"id":"tower", "talk":[
		["t5_tw_1", "Now, towers. They guard each lane and shoot whatever wanders in. Only basic attacks hurt them, and only from inside their range. No sniping. I checked.", "peeking"],
		["t5_tw_2", "Golden rule: minions first. A tower shoots minions before heroes, unless you hit one of their heroes right under it. More paperwork, and here we are. Hit it three times.", "lying"]],
		"task":"Hit the enemy tower 3 times with ATTACK",
		"done":[["t5_tw_done", "Lovely. Keep that up and it falls. Every tower pays the whole team, and brings us one step closer to their King.", "leaning"]]},
	{"id":"die", "talk":[
		["t5_die_1", "Now, the important bit. Dying. Every time you die, the enemy gets three hundred gold. Plus your bounty, if you've been showing off.", "pointing"],
		["t5_die_2", "That gold buys them swords. Swords they then use on you. You see the problem. Dying isn't just embarrassing. It's a donation.", "hanging"],
		["t5_die_3", "So when your health runs low, back off and recall. A living coward earns more than a dead hero. I should know. I'm still here.", "peeking"],
		["t5_die_4", "And if you take down someone with a big bounty, that's a shutdown, and all that gold is yours. Revenge is so much nicer when it pays.", "lying"]]},
	{"id":"win", "talk":[
		["t5_win_1", "To win, push down a lane: outer tower, inner tower, gate tower, then the gate. Then the two towers by their King, then the King himself. He's large, grumpy, and hits back.", "peeking"],
		["t5_win_2", "And do it together. Five heroes with full pockets beat one brave idiot every time. I've watched it happen. Repeatedly.", "napping"]]},
	{"id":"end", "talk":[
		["t5_end_1", "That's the lot. You're ready. Well. Readier.", "sitting"],
		["@pay", "", ""]]},
]
const END_GOLD := ["t5_end_gold", "Here's two hundred and fifty gold for sitting through all that. Go on. Win something. Make me look good.", "hold"]
const END_NOGOLD := ["t5_end_nogold", "No pay this time, I'm afraid. You've had your gold already, and the treasury has a long memory. Go on. Win something.", "hanging"]

var mode                      # siege_mode.gd
var sim
var hud
var step := 0
var phase := "wait"           # wait (the match warming up) -> talk -> task -> done -> next step ... -> finished
var line := 0
var shown := 0.0              # characters typed out
var finished := false
var voice: AudioStreamPlayer
var lines_said: Array = []    # (tests) every line id shown, in order
var _time := 0.0
var _start := Vector2.ZERO
var _lh0 := 0
var _red: Array = []          # the lane step's enemy minions
var _ours: Array = []         # the tower step's minions of ours
var _camp: Dictionary = {}
var _tw: Dictionary = {}
var _tw_hits := 0
var _shield_t := 0.0
var _w_done := false
var _e_done := false
var _note := ""               # a line under the objective for a moment ("Interrupted!")
var _note_until := 0.0
var _path := PackedVector2Array()
var _path_clock := 0.0
var _pose_tex := {}
var pose := ""                # the Herald's pose showing
# the talk: a dimmer that takes the tap, the Herald with his scroll, the writing on it
var dim: Control
var scroll: TextureRect
var text_label: Label
var hint_label: Label
var count_label: Label
# the task: the objective card
var card: PanelContainer
var task_label: Label
var note_label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	voice = AudioStreamPlayer.new()
	voice.bus = "Master"
	add_child(voice)
	dim = Dimmer.new()
	dim.tut = self
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	scroll = TextureRect.new()
	scroll.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scroll.stretch_mode = TextureRect.STRETCH_SCALE
	scroll.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scroll)
	text_label = Label.new()
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_override("font", VisualTheme.BOLD_FONT)
	text_label.add_theme_font_size_override("font_size", 16)
	text_label.add_theme_color_override("font_color", INK_TEXT)
	text_label.add_theme_constant_override("line_spacing", LINE_GAP)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(text_label)
	hint_label = _ink_label("TAP TO CONTINUE  >", 12, VisualTheme.GOLD)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label = _ink_label("", 11, Color(1, 1, 1, 0.55))
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(Color(0.04, 0.06, 0.15, 0.9), VisualTheme.GOLD_DARK, 12, 8))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.anchor_left = 0.0
	card.anchor_right = 1.0
	card.offset_left = 10
	card.offset_right = -10
	add_child(card)
	var cv := VBoxContainer.new()
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_theme_constant_override("separation", 1)
	card.add_child(cv)
	var head := Label.new()
	head.text = "THE HERALD WANTS YOU TO"
	head.add_theme_font_override("font", VisualTheme.BOLD_FONT)
	head.add_theme_font_size_override("font_size", 10)
	head.add_theme_color_override("font_color", VisualTheme.GOLD)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(head)
	task_label = Label.new()
	task_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task_label.add_theme_font_override("font", VisualTheme.BOLD_FONT)
	task_label.add_theme_font_size_override("font_size", 15)
	task_label.add_theme_color_override("font_color", Color("#fff4d6"))
	task_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(task_label)
	note_label = Label.new()
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.add_theme_font_override("font", VisualTheme.BOLD_FONT)
	note_label.add_theme_font_size_override("font_size", 12)
	note_label.add_theme_color_override("font_color", Color("#9ff6ef"))
	note_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(note_label)
	_layout()

static func _box(bg: Color, rim: Color, radius: int, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = rim
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad + 2
	sb.content_margin_right = pad + 2
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 6
	return sb

func _ink_label(text: String, px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", VisualTheme.BOLD_FONT)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

# ---------------- the scroll ----------------
func pose_tex(p: String) -> Texture2D:
	if not _pose_tex.has(p):
		var path := POSE_PATH % p
		_pose_tex[p] = load(path) if ResourceLoader.exists(path) else null
	return _pose_tex[p]

static func scroll_rects(p: String, view: Vector2) -> Dictionary:
	# where pose p's art goes on a screen of size view: "art" (the whole of it), "parch", "text" (the clear part, the
	# writing's), "k" (its scale). The parchment as wide as the screen less SCROLL_SIDE each side, unless that would put
	# some of the Herald off the screen; centred on it, then nudged in; its foot SCROLL_BOTTOM above the screen's.
	var g: Dictionary = Poses.POSES.get(p, Poses.POSES["hold"])
	var sz: Vector2 = g.size
	var pr: Rect2 = g.parch
	var tr: Rect2 = g.text
	var k := minf((view.x - 2.0 * SCROLL_SIDE) / pr.size.x, (view.x - 2.0 * SCROLL_FIT) / sz.x)
	var x := view.x * 0.5 - (pr.position.x + pr.size.x * 0.5) * k
	x = clampf(x, SCROLL_FIT - 0.0, view.x - SCROLL_FIT - sz.x * k) if sz.x * k <= view.x - 2.0 * SCROLL_FIT else x
	var y := minf(view.y - SCROLL_BOTTOM - pr.end.y * k, view.y - 2.0 - sz.y * k)     # (his feet on the screen too)
	var o := Vector2(x, y)
	return {"art": Rect2(o, sz * k), "parch": Rect2(o + pr.position * k, pr.size * k), "text": Rect2(o + tr.position * k, tr.size * k), "k": k}

static func text_height(text: String, width: float, px: int) -> float:
	# the writing's height at px in that width, its lines LINE_GAP closer than the font's own
	var font: Font = VisualTheme.BOLD_FONT
	var lh := font.get_height(px)
	var n := roundi(font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, px).y / lh)
	return float(n) * lh + float(maxi(0, n - 1) * LINE_GAP)

static func fit_px(text: String, box: Vector2) -> int:
	# the biggest of TEXT_PX that fits the line in the box
	for px in TEXT_PX:
		if text_height(text, box.x, px) <= box.y:
			return px
	return int(TEXT_PX[-1])

# A full-screen shade that takes the tap moving the Herald on -- not over the HUD's pause button
class Dimmer extends ColorRect:
	var tut
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		color = Color(0.0, 0.01, 0.04, 0.42)
	func _has_point(p: Vector2) -> bool:
		if tut == null or tut.hud == null or not is_instance_valid(tut.hud.pause_btn):
			return true
		return not tut.hud.pause_btn.get_global_rect().grow(4.0).has_point(get_global_transform() * p)
	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
			accept_event()
			tut.next()

func _unhandled_input(e: InputEvent) -> void:
	if holds() and phase != "wait" and e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		next()

# ---------------- the match, made quiet ----------------
func begin(m) -> void:
	mode = m
	sim = m.sim
	hud = m.hud
	var me := _me()
	for t in 2:
		for hid in sim.moba.heroes[t]:
			var h: Dictionary = sim.by_id.get(hid, {})
			if not h.is_empty() and str(hid) != str(me.get("id", "")):
				h.bot = false                     # (a tea break: they stand at their fountains)
				h.move = Vector2.ZERO
	sim.moba.wave_at = INF                        # no waves but the ones put down here
	for c in sim.moba.camps:
		c.next = INF                              # no camps either (the Bone Lord and the Wyrm included)
	_start = me.get("pos", Vector2.ZERO)
	_refresh()

func _me() -> Dictionary:
	return sim.by_id.get(hud.player_id, {}) if sim != null else {}

func _keep_quiet() -> void:
	var me := _me()
	if me.is_empty():
		return
	if sim.alive(me):
		me["dr"] = maxf(float(me.get("dr", 0.0)), TAKE)
		me["dr_until"] = float(sim.time) + 1.0
		if float(me.hp) < float(me.max_hp) * HP_FLOOR:
			me.hp = float(me.max_hp) * HP_FLOOR
	for c in sim.moba.camps:
		if not bool(c.alive):
			c.next = INF
	if float(sim.match_time) - float(sim.time) < 120.0:
		sim.match_time = float(sim.match_time) + 600.0      # (the clock never runs out on a lesson)

func holds() -> bool:
	# siege_mode: while true the match doesn't step (the Herald is talking, or about to)
	return phase in ["wait", "talk", "done"] or finished

# ---------------- flow ----------------
func _lines() -> Array:
	var st: Dictionary = STEPS[step]
	return st.get("talk", []) if phase == "talk" else (st.get("done", []) if phase == "done" else [])

func current_line() -> Array:
	var ls := _lines()
	if line >= ls.size():
		return ["", "", "hold"]
	var l: Array = ls[line]
	if str(l[0]) == "@pay":
		return END_GOLD if mode != null and mode.tutorial_pays() else END_NOGOLD
	return l

func next() -> void:
	# a tap: the line typed out first, then the next one
	if phase == "wait":
		return
	if finished:
		_finish()
		return
	if phase not in ["talk", "done"]:
		return
	if shown < float(str(current_line()[1]).length()):
		shown = 9999.0
		return
	line += 1
	if line < _lines().size():
		_show_line()
		return
	if phase == "talk" and STEPS[step].has("task"):
		phase = "task"
		_enter_task()
		voice.stop()
		_refresh()
		return
	_next_step()

func _next_step() -> void:
	step += 1
	line = 0
	phase = "talk"
	if step >= STEPS.size():
		step = STEPS.size() - 1
		finished = true
		_finish()
		return
	_enter_step()
	if mode != null and mode.get("analytics") != null:
		mode.analytics.log_ev("tutorial_step", {"step":step, "id":str(STEPS[step].id)})
	_show_line()

func _finish() -> void:
	voice.stop()
	if mode != null:
		mode.finish_tutorial()

func _complete_task() -> void:
	phase = "done"
	line = 0
	if mode != null and mode.audio != null and mode.audio.has_method("play"):
		mode.audio.play("claim")
	if (STEPS[step].get("done", []) as Array).is_empty():
		_next_step()
	else:
		_show_line()

func _show_line() -> void:
	shown = 0.0
	var l := current_line()
	var id := str(l[0])
	lines_said.append(id)
	_set_pose(str(l[2]) if l.size() > 2 and str(l[2]) != "" else "hold")
	voice.stop()
	var master := 1.0
	var muted := false
	if mode != null and mode.audio != null:
		master = float(mode.audio.levels.get("master", 1.0))
		muted = bool(mode.audio.get("muted"))
	var p := VO_DIR + id + ".ogg"
	if id != "" and not muted and master > 0.0 and ResourceLoader.exists(p):
		voice.stream = load(p)
		voice.volume_db = linear_to_db(master * VOICE_GAIN)
		voice.play()
	_refresh()

func _set_pose(p: String) -> void:
	if p == pose:
		return
	pose = p
	scroll.texture = pose_tex(p)
	# he changes how he's holding it: the scroll pops a little
	var r: Dictionary = scroll_rects(p, size)
	scroll.pivot_offset = Vector2((r.art as Rect2).size.x * 0.5, (r.art as Rect2).size.y)
	scroll.scale = Vector2(0.94, 0.94)
	scroll.modulate.a = 0.35
	var tw := create_tween().set_parallel(true)
	tw.tween_property(scroll, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(scroll, "modulate:a", 1.0, 0.12)

func _refresh() -> void:
	var talking := phase in ["talk", "done"] or finished
	if hud != null:
		hud.tut_modal = talking or phase == "wait"
	dim.visible = talking
	scroll.visible = talking and scroll.texture != null
	text_label.visible = talking
	hint_label.visible = talking
	count_label.visible = talking
	card.visible = phase == "task" and not (hud != null and (hud.shop_open() or hud.board_open()))
	count_label.text = "LESSON %d OF %d" % [step + 1, STEPS.size()]
	if phase == "task":
		task_label.text = str(STEPS[step].task)
	text_label.text = str(current_line()[1]) if talking else ""
	text_label.visible_characters = int(shown) if shown < 9000.0 else -1
	_layout()
	if talking:
		var r: Dictionary = scroll_rects(pose, size)
		text_label.add_theme_font_size_override("font_size", fit_px(text_label.text, (r.text as Rect2).size))

func _layout() -> void:
	if scroll == null:
		return
	var r: Dictionary = scroll_rects(pose if pose != "" else "hold", size)
	var art: Rect2 = r.art
	var tr: Rect2 = r.text
	scroll.position = art.position
	scroll.size = art.size
	text_label.position = tr.position
	text_label.size = tr.size
	# under the scroll, on the shade: the lesson on the left, TAP TO CONTINUE on the right
	var foot := size.y - SCROLL_BOTTOM + 13.0                  # (clear of the rods' caps)
	hint_label.position = Vector2(size.x * 0.5, foot)
	hint_label.size = Vector2(size.x * 0.5 - SCROLL_SIDE, 18)
	count_label.position = Vector2(SCROLL_SIDE, foot)
	count_label.size = Vector2(size.x * 0.5, 18)
	# the objective card under the HUD's top (gold, items); hidden while the shop or the board is open (they say it)
	card.visible = phase == "task" and not (hud != null and (hud.shop_open() or hud.board_open()))
	card.offset_top = 182.0
	card.offset_bottom = card.offset_top + 10.0

# ---------------- steps and tasks ----------------
func _enter_step() -> void:
	# what a step needs, put there as its talk begins (the match waits meanwhile)
	var me := _me()
	if me.is_empty():
		return
	var t := int(me.team)
	match str(STEPS[step].id):
		"lane":
			_hop(_side(t, LANE_AT))
			_deliver_lane()
		"recall":
			if sim.in_castle(me.pos, t) or not sim.alive(me):
				if not sim.alive(me):
					sim._respawn(me)
				_hop(_side(t, LANE_AT))
		"shop":
			if not sim.moba.can_shop(me):
				_hop(sim.spawn(t))
		"abilities":
			while int(me.level) < 3:
				sim.moba.add_xp(me, sim.moba.need(int(me.level)) - float(me.xp) + 0.1)
		"jungle":
			_camp = {}
			for c in sim.moba.camps:
				if str(c.kind) == "archers" and int(c.side) == t and (_camp.is_empty() or absf((c.p as Vector2).y) > absf((_camp.p as Vector2).y)):
					_camp = c                             # (ours nearest the keep)
			if not _camp.is_empty() and sim.moba.camp_live(_camp).is_empty():
				sim.moba._spawn_camp(_camp)
				for mid in _camp.mobs:
					var mob: Dictionary = sim.by_id.get(str(mid), {})
					if not mob.is_empty():
						mob.max_hp = float(mob.max_hp) * CAMP_WEAK
						mob.hp = float(mob.max_hp)
		"tower":
			_tw = {}
			for tw in sim.moba.towers:
				if int(tw.team) != t and int(tw.lane) == 1 and int(tw.tier) == 1:
					_tw = tw
			if not _tw.is_empty():
				var toward := Vector2(0.0, 1.0) if t == 0 else Vector2(0.0, -1.0)     # (our side of it)
				var at := Vector2(0.0, (_tw.p as Vector2).y) + toward * 17.0
				_hop(at + Vector2(2.5, 0.0))
				_ours = sim.moba.place_minions(t, 1, TOWER_KINDS, at - toward * 1.5)
			_tw_hits = 0

func _enter_task() -> void:
	var me := _me()
	_note = ""
	match str(STEPS[step].id):
		"move":
			_start = me.pos
		"lane":
			_lh0 = int(me.get("lh", 0))
		"abilities":
			_shield_t = 0.0
			_w_done = false
			_e_done = false
			for k in ["cd_ability", "cd_w", "cd_e"]:
				me[k] = 0.0                          # (all three ready, whatever was used in the lane)

static func _side(team: int, p: Vector2) -> Vector2:
	return p if team == 0 else -p

func _deliver_lane() -> void:
	var t := int(_me().team)
	sim.moba.place_minions(t, 1, LANE_KINDS, _side(t, LANE_OURS))
	_red = sim.moba.place_minions(1 - t, 1, LANE_KINDS, _side(t, LANE_THEIRS))

func _hop(p: Vector2) -> void:
	# "royal paperwork": you, there -- with the recall's flash at both ends
	var me := _me()
	if me.is_empty():
		return
	var from: Vector2 = me.pos
	if sim.recalling(me):
		sim.recall_cancel(me)
	me.pos = p
	me.move = Vector2.ZERO
	var e := {"k":"recall_done", "id":str(me.id), "from":from, "to":p, "tut":true}
	if mode != null and mode.view != null:
		mode.view.on_event(e)
	if mode != null and mode.has_method("_event_sound"):
		mode._event_sound(e)

func _alive_ids(ids: Array) -> Array:
	return ids.filter(func(id): return not sim.by_id.get(str(id), {}).is_empty() and sim.alive(sim.by_id[str(id)]))

func on_event(e: Dictionary) -> void:
	# (siege_mode passes on the match's events)
	var me := _me()
	if me.is_empty() or phase != "task":
		return
	var mine: bool = str(e.get("id", "")) == str(me.id)
	match str(e.get("k", "")):
		"recall_done":
			if mine and not bool(e.get("tut", false)) and str(STEPS[step].id) == "recall":
				_complete_task()
		"recall_cancel":
			if mine:
				_say_note("Interrupted! Step away from the fight, then try again.")
		"buy":
			if mine and str(STEPS[step].id) == "shop":
				if hud.shop_open():
					hud.close_shop()
				_complete_task()
		"spell":
			if mine and str(STEPS[step].id) == "abilities":
				if str(e.get("slot", "")) == "w":
					_w_done = true
				elif str(e.get("slot", "")) == "e":
					_e_done = true
		"tower_hit":
			if str(e.get("by", "")) == str(me.id) and not _tw.is_empty() and int(e.get("tw", -1)) == int(_tw.id):
				_tw_hits += 1

func _say_note(t: String) -> void:
	_note = t
	_note_until = _time + 3.5

func progress() -> String:
	# the task's count so far ("1/2"), if it has one
	var me := _me()
	match str(STEPS[step].id):
		"lane":
			return "%d/%d" % [mini(int(me.get("lh", 0)) - _lh0, LH_GOAL), LH_GOAL]
		"tower":
			return "%d/%d" % [mini(_tw_hits, TOWER_HITS), TOWER_HITS]
		"abilities":
			var n := int(_shield_t >= SHIELD_FOR) + int(_w_done) + int(_e_done) + int((me.get("picks", []) as Array).is_empty())
			return "%d/4" % n
		"jungle":
			if not _camp.is_empty():
				return "%d left" % sim.moba.camp_live(_camp).size()
	return ""

func task_done() -> bool:
	var me := _me()
	match str(STEPS[step].id):
		"move":
			return (me.pos as Vector2).distance_to(_start) >= 6.0
		"lane":
			return int(me.get("lh", 0)) - _lh0 >= LH_GOAL
		"eco":
			return hud.board_open()
		"recall":
			return false                               # (its "recall_done")
		"shop":
			return false                               # (a "buy")
		"abilities":
			return _shield_t >= SHIELD_FOR and _w_done and _e_done and (me.get("picks", []) as Array).is_empty()
		"jungle":
			return not _camp.is_empty() and sim.moba.camp_live(_camp).is_empty()
		"tower":
			return _tw_hits >= TOWER_HITS or (not _tw.is_empty() and bool(_tw.dead))     # (the minions beat you to it)
	return true

func _task_tick(delta: float) -> void:
	var me := _me()
	match str(STEPS[step].id):
		"lane":
			if _alive_ids(_red).is_empty() and int(me.get("lh", 0)) - _lh0 < LH_GOAL:
				_deliver_lane()                        # (another delivery: they were all finished off by others)
				_say_note("Another delivery. Try to land the last blow this time.")
		"abilities":
			if sim.blocking(me):
				_shield_t += delta
		"tower":
			if not _tw.is_empty() and not bool(_tw.dead):
				var near := false
				for id in _alive_ids(_ours):
					if (sim.by_id[str(id)].pos as Vector2).distance_to(_tw.p) < 22.0:
						near = true
				if not near:
					var t := int(me.team)
					var toward := Vector2(0.0, 1.0) if t == 0 else Vector2(0.0, -1.0)
					_ours = sim.moba.place_minions(t, 1, TOWER_KINDS, Vector2(0.0, (_tw.p as Vector2).y) + toward * 15.5)
					_say_note("More minions. Do let them go first.")

func _process(delta: float) -> void:
	if sim == null:
		return
	_time += delta
	_keep_quiet()
	voice.stream_paused = hud.paused()
	if phase == "wait":
		if mode == null or mode.warmed():
			phase = "talk"
			_enter_step()
			_show_line()
		return
	if phase == "task":
		_task_tick(delta)
		_update_path(delta)
		var pg := progress()
		task_label.text = str(STEPS[step].task) + (("   " + pg) if pg != "" else "")
		var me := _me()
		var n := _note if _time < _note_until else ""
		if n == "" and not me.is_empty() and not sim.alive(me):
			n = "Back on your feet in a moment..."
		if n == "" and str(STEPS[step].id) == "recall" and sim.recalling(me):
			n = "Stand still... %.1f" % maxf(0.0, float(me.recall_until) - float(sim.time))
		note_label.text = n
		note_label.visible = n != ""
		if task_done():
			_complete_task()
	elif phase in ["talk", "done"]:
		var full := str(current_line()[1])
		if shown < 9000.0:
			shown = minf(shown + delta * TYPE_CPS, float(full.length()))
		text_label.visible_characters = -1 if shown >= float(full.length()) else int(shown)
		var said: bool = shown >= float(full.length()) and not voice.playing
		hint_label.modulate.a = (0.55 + 0.45 * sin(_time * 5.0)) if said else 0.35
	_layout()
	queue_redraw()

# ---------------- guidance ----------------
const GOLD := Color("#ffd257")
const INK := Color(0.08, 0.05, 0.02, 0.9)

func task_info() -> Dictionary:
	# what to point at: "pos" (a world point) + "label" for the route, ring and arrow; "button" (a HUD button) with
	# "hold"; "rect" (a HUD rect) for the score bar, the shop, the upgrade cards
	var me := _me()
	if me.is_empty() or phase != "task":
		return {}
	match str(STEPS[step].id):
		"move":
			return {"stick": true}
		"lane":
			var best: Dictionary = {}
			for id in _alive_ids(_red):
				var m: Dictionary = sim.by_id[str(id)]
				if best.is_empty() or float(m.hp) < float(best.hp):
					best = m
			if best.is_empty():
				return {}
			var low: bool = float(best.hp) <= float(sim.stat(me, "dmg")) * 1.1
			var info := {"pos": best.pos, "label": "LAST HIT NOW" if low else "ENEMY MINIONS", "small": true}
			if low:
				info["button"] = "attack"
			return info
		"eco":
			var sb: Rect2 = hud.score_bar_rect()
			return {"rect": sb, "rect_label": "TAP", "label_at": Vector2(sb.get_center().x + sb.size.x * 0.3, sb.end.y + 20.0)} if not hud.board_open() else {}
		"recall":
			if sim.recalling(me):
				return {}
			return {"button": "recall"}
		"shop":
			var sr: Rect2 = hud.shop_rect()
			return {"rect": sr, "rect_label": "TAP", "label_at": Vector2(sr.end.x + 38.0, sr.get_center().y)} if not hud.shop_open() else {}
		"abilities":
			if _shield_t < SHIELD_FOR:
				return {"button": "ability", "hold": true}
			if not _w_done:
				return {"button": "w"}
			if not _e_done:
				return {"button": "e"}
			if not (me.get("picks", []) as Array).is_empty():
				return {"rect": hud.pick_rect(0).merge(hud.pick_rect(2)), "rect_label": "CHOOSE ONE"}
		"jungle":
			if _camp.is_empty():
				return {}
			var info2 := {"pos": _camp.p, "label": "GRAVE ARCHERS"}
			if (me.pos as Vector2).distance_to(_camp.p) < 7.0:
				info2["button"] = "attack"
			return info2
		"tower":
			if _tw.is_empty():
				return {}
			var info3 := {"pos": _tw.p, "label": "ENEMY TOWER", "ring": 2.6, "lift": 7.0}
			if sim.moba.in_tower_range(_tw, me.pos):
				info3["button"] = "attack"
			return info3
	return {}

func _update_path(delta: float) -> void:
	_path_clock -= delta
	if _path_clock > 0.0:
		return
	_path_clock = 0.4
	var info := task_info()
	var me := _me()
	_path = sim.find_path(int(me.team), me.pos, info.pos) if info.has("pos") and not info.get("small", false) else PackedVector2Array()

func _w(p: Vector2, lift := 0.15) -> Vector3:
	return Vector3(p.x, Sim.height_at(p) + lift, p.y)

func _plate(center: Vector2, text: String) -> void:
	var font: Font = VisualTheme.BOLD_FONT
	var fs := 14
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 20.0
	var r := Rect2(center.x - w * 0.5, center.y - 13, w, 26)
	draw_rect(r.grow(2), INK)
	draw_rect(r, Color(0.12, 0.09, 0.03, 0.95))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), GOLD)
	draw_string(font, Vector2(r.position.x + 10, r.position.y + 19), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

func _arrow(tip: Vector2, s: float, up := false) -> void:
	# a fat outlined arrow pointing down at tip (or up)
	var k := -1.0 if up else 1.0
	var pts := PackedVector2Array([tip, tip + Vector2(-22, -26 * k) * s, tip + Vector2(-9, -26 * k) * s, tip + Vector2(-9, -52 * k) * s,
		tip + Vector2(9, -52 * k) * s, tip + Vector2(9, -26 * k) * s, tip + Vector2(22, -26 * k) * s])
	var c := Vector2.ZERO
	for q in pts:
		c += q
	c /= pts.size()
	var out := PackedVector2Array()
	for q in pts:
		out.append(c + (q - c) * 1.18)
	draw_colored_polygon(out, INK)
	draw_colored_polygon(pts, GOLD)

func _draw() -> void:
	if sim == null:
		return
	if phase != "task":
		return
	var info := task_info()
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	var me := _me()
	if me.is_empty():
		return
	if info.has("stick"):
		# a ghost thumb on the left, circling
		var base := Vector2(size.x * 0.27, size.y - 190.0)
		draw_circle(base, 46.0, Color(1, 1, 1, 0.08))
		draw_arc(base, 46.0, 0.0, TAU, 48, Color(GOLD, 0.7), 3.0, true)
		var thumb := base + Vector2.from_angle(_time * 2.2) * 26.0
		draw_circle(thumb, 17.0, INK)
		draw_circle(thumb, 14.0, GOLD)
		_plate(base + Vector2(0, 72), "DRAG HERE")
	if info.has("button") and hud.has_method("_buttons"):
		for b in hud._buttons():
			if str(b.id) == str(info.button):
				var rr: float = float(b.r) + 10.0 + 7.0 * pulse
				draw_arc(b.c, rr + 3.0, 0.0, TAU, 48, INK, 9.0, true)
				draw_arc(b.c, rr, 0.0, TAU, 48, GOLD, 6.0, true)
				_plate(b.c + Vector2(0, -float(b.r) - 32.0), "HOLD" if info.get("hold", false) else "TAP")
	if info.has("rect"):
		var r: Rect2 = (info.rect as Rect2).grow(5.0 + 4.0 * pulse)
		draw_rect(r.grow(3.0), INK, false, 5.0)
		draw_rect(r, GOLD, false, 4.0)
		_plate(info.get("label_at", Vector2(r.get_center().x, r.end.y + 20.0)), str(info.get("rect_label", "TAP")))
	if not info.has("pos"):
		return
	var tgt: Vector2 = info.pos
	var pts := PackedVector2Array([me.pos])
	pts.append_array(_path)
	pts.append(tgt)
	if not info.get("small", false):
		# the route: dots every 1.1 m along the way, marching toward the target
		var step_len := 1.1
		var along := fmod(_time * 2.2, step_len)
		var walked := 0.0
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b2: Vector2 = pts[i + 1]
			var seg := a.distance_to(b2)
			while along < seg and walked + along < 40.0:
				var wq := _w(a.lerp(b2, along / maxf(seg, 0.001)))
				if hud.on_screen.call(wq):
					var sq: Vector2 = hud.project.call(wq)
					draw_circle(sq, 7.0, INK)
					draw_circle(sq, 5.0, GOLD)
				along += step_len
			along -= seg
			walked += seg
	var route := 0.0
	var guide: Vector2 = tgt
	var got := false
	for i in range(pts.size() - 1):
		var seg2: float = (pts[i] as Vector2).distance_to(pts[i + 1])
		if not got and route + seg2 >= 8.0:
			guide = (pts[i] as Vector2).lerp(pts[i + 1], (8.0 - route) / maxf(seg2, 0.001))
			got = true
		route += seg2
	var label := str(info.get("label", "HERE")) + ("" if info.get("small", false) or route < 4.0 else " · %d m" % int(round(route)))
	if hud.on_screen.call(_w(tgt, 0.0)):
		var ring := PackedVector2Array()
		var inner := PackedVector2Array()
		var rad: float = info.get("ring", 0.9 if info.get("small", false) else 1.4)
		for k in 33:
			var off := Vector2.from_angle(TAU * k / 32.0)
			ring.append(hud.project.call(_w(tgt + off * rad, 0.08)))
			inner.append(hud.project.call(_w(tgt + off * rad * (0.35 + 0.55 * pulse), 0.08)))
		draw_polyline(ring, INK, 9.0, true)
		draw_polyline(ring, GOLD, 5.0, true)
		draw_polyline(inner, Color(GOLD, 0.8 - 0.6 * pulse), 3.0, true)
		var tip: Vector2 = hud.project.call(_w(tgt, float(info.get("lift", 2.4)))) + Vector2(0, -10.0 * pulse)
		var top_free: float = card.get_rect().end.y + 12.0
		if tip.y - 100.0 > top_free:
			_arrow(tip, 1.1)
			_plate(tip + Vector2(0, -78), label)
		else:
			var tip2: Vector2 = hud.project.call(_w(tgt, 0.0)) + Vector2(0, 24.0 + 10.0 * pulse)
			_arrow(tip2, 1.1, true)
			_plate(tip2 + Vector2(0, 78), label)
	else:
		# off screen: a big edge arrow the way to go
		var center := size * 0.5
		var from_s: Vector2 = hud.project.call(_w(me.pos, 1.0))
		var to_s: Vector2 = hud.project.call(_w(guide, 1.0))
		var dir := (to_s - from_s).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2(0, -1)
		var edge := center + dir * minf(size.x * 0.40, size.y * 0.30)
		edge.y = maxf(edge.y, card.get_rect().end.y + 60.0)
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([edge + dir * 40, edge - dir * 18 + side * 30, edge - dir * 18 - side * 30]), INK)
		draw_colored_polygon(PackedVector2Array([edge + dir * 34, edge - dir * 14 + side * 24, edge - dir * 14 - side * 24]), GOLD)
		_plate(edge - dir * 50, label)
