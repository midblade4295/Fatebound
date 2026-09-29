extends Control
# Fatebound Siege tutorial (0.19.0, Kevin: "a tutorial walkthrough that shows the player how to
# play; a narrator talking to the player, with humor; I'll add the voiceover later").
#
# A small offline match (siege_mode.gd, tutorial = true) with everyone frozen, and this overlay on
# top of the HUD: the Herald's lines (typewriter, NEXT), then an objective the player has to DO
# (walk, grab a hat, hit the dummy...), checked from the sim every frame, with an arrow pointing at
# where to go or a ring around the button to press.
#
# VOICEOVER: every line has an id. Drop res://assets/vo/tutorial/<id>.ogg (or .wav / .mp3) in and it
# plays with the text; missing files are simply skipped. assets/vo/tutorial/SCRIPT.md lists them.
const Sim = preload("res://scripts/siege/siege_sim.gd")
const VO_DIR := "res://assets/vo/tutorial/"
const TYPE_CPS := 48.0

# Each step: talk (lines before the task), task (what to do, shown as the objective), done (lines
# once it's done). Lines are [voice id, text].
const STEPS := [
	{"id": "intro", "talk": [
		["t_intro_1", "Ah, a new recruit! Welcome to the siege. I'm the Royal Herald. I announce things. Loudly. It's a living."],
		["t_intro_2", "Across that field, the enemy is holding our Oracle hostage. We'd like her back. She does the prophecies. And the baking."]]},
	{"id": "move", "talk": [
		["t_move_1", "First things first: walking. Drag your thumb on the left side of the screen. Yes, like that. No, the other left."]],
		"task": "Walk around a bit",
		"done": [["t_move_done", "Magnificent. You've mastered the ancient art of 'going places'. The bards will sing of it. Briefly."]]},
	{"id": "hat", "talk": [
		["t_hat_1", "Right now you're a Villager. Villagers are brave, loyal, and hit like a wet sock."],
		["t_hat_2", "Walk into the Knight's hat shop. In this kingdom the hat makes the hero. Don't ask me why. I just read the scrolls."]],
		"task": "Get a Knight hat at the Knight hat shop",
		"done": [["t_hat_done", "A Knight! Look at you. Positively shiny. Try not to lose that hat. You'll see why in a moment."]]},
	{"id": "attack", "talk": [
		["t_attack_1", "Here's a training dummy. It volunteered. Well. 'Volunteered'. Tap ATTACK to whack it, or hold ATTACK to keep whacking."]],
		"task": "Hit the dummy 3 times",
		"done": [["t_attack_done", "Excellent violence. The dummy has filed a complaint. It will be ignored."]]},
	{"id": "dodge", "talk": [
		["t_dodge_1", "Now the most important skill in any war: not being where the sword is. Tap DODGE."]],
		"task": "Dodge",
		"done": [["t_dodge_done", "Nimble! Cowardly, some might say. I prefer 'tactically absent'."]]},
	{"id": "block", "talk": [
		["t_block_1", "Every class has an ability. Knights have a very large shield. Hold ABILITY to raise it: it stops everything from the front, even for friends hiding behind you."]],
		"task": "Hold ABILITY to block for a second",
		"done": [["t_block_done", "A wall with legs! Your allies will adore you. Mostly they'll adore standing behind you."]]},
	{"id": "hats", "talk": [
		["t_hats_1", "A word of warning. When you fall in battle, your hat falls too, and anyone can pick it up. Friend or foe. Yes, even the enemy. Fashion is cruel."],
		["t_hats_2", "You'll come back as a Villager. Grab a hat off the ground or run home to a hat shop. Sneak into the enemy castle and you can even use theirs. Rude, but legal."]]},
	{"id": "workshop", "talk": [
		["t_ws_1", "Next: the workshop. Follow the arrow, and mind the barrels."]],
		"task": "Go to the workshop",
		"done": [
			["t_ws_done", "Workers bring wood and stone here. Spend it on stronger gates, better armor and catapults. Walls don't build themselves. Believe me, I asked."],
			["t_ws_worker", "Want to be a Worker? Take tools here. Workers chop trees, mine rocks, repair gates and build ladders. Glamorous? No. Essential? Also no. Just kidding. Very essential."]]},
	{"id": "upgrade", "talk": [
		["t_up_1", "The treasury has kindly 'found' some materials for you. Go back to the Knight hat shop and press UPGRADE."]],
		"task": "Upgrade the Knight hats at the Knight hat shop",
		"done": [["t_up_done", "Paladin hats! Every hat from that shop is fancier now. Upgrades are bought at each hat shop, not the workshop. The workshop is still sulking about it."]]},
	{"id": "outpost", "talk": [
		["t_out_1", "See that tower up on the ledge? That's an outpost. Stand in its ring to capture it. Capturing is mostly standing around looking important. You're a natural."]],
		"task": "Capture the outpost",
		"done": [["t_out_done", "It's ours! We can respawn here, workers can drop resources off here, and it earns us wood and stone. Passive income. The true magic."]]},
	{"id": "goal", "talk": [
		["t_goal_1", "Now, the actual point of all this. The enemy's dungeon is inside their castle, behind their gates. Our Oracle is in there. Probably bored."],
		["t_goal_2", "Break a gate down, and Barbarians are marvellous at that, or have a Worker build a ladder over the wall. Then grab her and carry her home to our throne."],
		["t_goal_3", "Rescue her three times and we win. They're trying to do the exact same thing to us, so leave a few friends at home. Trust issues are healthy here."]],
		"task": "Head out toward the river",
		"done": [["t_goal_done", "Behold, the battlefield. Lovely, isn't it? Mind the enemy. And the river. And the catapults. Mostly the enemy."]]},
	{"id": "cake", "talk": [
		["t_cake_1", "One more thing. There are cake trees out there. Feed cake to the enemy's captive and she gets heavier, so they need more people to carry her home."],
		["t_cake_2", "Is it tactically brilliant? Yes. Is it ethically questionable? Also yes. Welcome to siege warfare."]]},
	{"id": "end", "talk": [
		["t_end_1", "That's everything! Well. Not everything. But everything I was paid to say."],
		["t_end_2", "Go forth, recruit. Win glory. Rescue the Oracle. And please, try to keep your hat on."]]},
]

var mode                      # siege_mode.gd
var sim
var hud
var step := 0
var phase := "talk"           # talk (lines before the task) -> task -> done (lines after) -> next
var line := 0
var shown := 0.0              # characters revealed (typewriter)
var finished := false
var _start := Vector2.ZERO
var _dummy_id := ""
var _dummy_hp := 0.0
var _hits := 0
var _block_t := 0.0
var _time := 0.0
var voice: AudioStreamPlayer
var panel: PanelContainer
var name_label: Label
var text_label: Label
var task_label: Label
var next_btn: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	voice = AudioStreamPlayer.new()
	voice.bus = "Master"
	add_child(voice)
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.12, 0.9)
	sb.border_color = Color("#f2c76b")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 64
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.offset_left = 8
	panel.offset_right = -8
	panel.offset_top = 172
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	name_label = Label.new()
	name_label.text = "THE ROYAL HERALD"
	name_label.add_theme_color_override("font_color", Color("#f2c76b"))
	name_label.add_theme_font_size_override("font_size", 12)
	v.add_child(name_label)
	text_label = Label.new()
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override("font_size", 15)
	text_label.custom_minimum_size = Vector2(0, 40)
	v.add_child(text_label)
	var row := HBoxContainer.new()
	v.add_child(row)
	task_label = Label.new()
	task_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	task_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task_label.add_theme_color_override("font_color", Color("#9ff6ef"))
	task_label.add_theme_font_size_override("font_size", 13)
	row.add_child(task_label)
	# NEXT on the right: the HUD's joystick takes touches on the left side of the screen.
	next_btn = Button.new()
	next_btn.text = "NEXT ▶"
	next_btn.custom_minimum_size = Vector2(96, 38)
	next_btn.pressed.connect(next)
	row.add_child(next_btn)
	# The Herald's badge in the panel's left margin (drawn after the panel, so on top of it).
	var badge: Control = preload("res://scripts/app/ui.gd").icon(self, "crown", 40, Color("#f2c76b"))
	badge.position = Vector2(20, 184)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE

func begin(m) -> void:
	mode = m
	sim = m.sim
	hud = m.hud
	# A quiet castle: everyone else stands still (no ambush during the lesson).
	for u in sim.units:
		if u.id != hud.player_id:
			u.bot = false
			u.move = Vector2.ZERO
	var me: Dictionary = sim.by_id[hud.player_id]
	_start = me.pos
	_show_line()

# ---------------- flow ----------------
func _lines() -> Array:
	var st: Dictionary = STEPS[step]
	return st.get("talk", []) if phase == "talk" else st.get("done", []) if phase == "done" else []

func current_line() -> Array:
	var ls := _lines()
	return ls[line] if line < ls.size() else ["", ""]

func next() -> void:
	# NEXT: finish the typewriter first, then advance.
	if finished:
		mode.finish_tutorial()
		return
	var ls := _lines()
	if phase in ["talk", "done"] and line < ls.size() and shown < float(str(current_line()[1]).length()):
		shown = 9999.0
		return
	if phase in ["talk", "done"]:
		line += 1
		if line < ls.size():
			_show_line()
			return
		if phase == "talk" and STEPS[step].has("task"):
			phase = "task"
			_enter_task()
			_refresh()
			return
		_next_step()

func _next_step() -> void:
	_leave_step()
	step += 1
	line = 0
	phase = "talk"
	if step >= STEPS.size():
		step = STEPS.size() - 1
		finished = true
		_refresh()
		return
	_show_line()

func _complete_task() -> void:
	phase = "done"
	line = 0
	if STEPS[step].get("done", []).is_empty():
		_next_step()
	else:
		_show_line()
	if mode.audio != null and mode.audio.has_method("play"):
		mode.audio.play("claim")

func _show_line() -> void:
	shown = 0.0
	var id := str(current_line()[0])
	voice.stop()
	for ext in [".ogg", ".wav", ".mp3"]:
		var p: String = VO_DIR + id + ext
		if id != "" and ResourceLoader.exists(p):
			voice.stream = load(p)
			voice.play()
			break
	_refresh()

func _refresh() -> void:
	var st: Dictionary = STEPS[step]
	task_label.text = ("▶ " + str(st.task)) if phase == "task" else ""
	if finished:
		next_btn.text = "FINISH ✔"
	elif phase == "task":
		next_btn.visible = false
	else:
		next_btn.visible = true
		next_btn.text = "NEXT ▶"
	if phase == "task":
		text_label.text = str(st.get("talk", [["", ""]])[-1][1]) if not st.get("talk", []).is_empty() else ""
		shown = 9999.0

# ---------------- tasks ----------------
func _enter_task() -> void:
	var me: Dictionary = sim.by_id[hud.player_id]
	match str(STEPS[step].id):
		"move":
			_start = me.pos
		"attack":
			# An enemy stands in as a very durable dummy, just in front of the player.
			var foe: Dictionary = sim.units.filter(func(x): return x.team != me.team)[0]
			_dummy_id = foe.id
			foe.bot = false
			foe.move = Vector2.ZERO
			foe.max_hp = 9999.0
			foe.hp = 9999.0
			foe.pos = me.pos + Vector2(sin(me.face), cos(me.face)) * 1.6
			_dummy_hp = foe.hp
			_hits = 0
		"upgrade":
			var cost: Dictionary = sim.upgrade_cost(me.team, "hat_knight")
			sim.stock[me.team].wood = maxi(int(sim.stock[me.team].wood), int(cost.get("wood", 12)))
			sim.stock[me.team].stone = maxi(int(sim.stock[me.team].stone), int(cost.get("stone", 12)))
		"block":
			_block_t = 0.0

func _leave_step() -> void:
	if str(STEPS[step].id) == "attack" and _dummy_id != "":
		# The dummy goes home, healed and slightly humiliated.
		var foe: Dictionary = sim.by_id.get(_dummy_id, {})
		if not foe.is_empty():
			foe.max_hp = float(sim.stat(foe, "hp"))
			foe.hp = foe.max_hp
			foe.pos = Sim.spawn(foe.team)
		_dummy_id = ""

func task_target() -> Variant:
	# Where the arrow points (world Vector2), or a HUD button id (String), or null.
	var me: Dictionary = sim.by_id[hud.player_id]
	match str(STEPS[step].id):
		"hat", "upgrade":
			return _stand(me.team, "knight").p
		"attack":
			return "attack"
		"dodge":
			return "dodge"
		"block":
			return "ability"
		"workshop":
			return Sim.workshop(me.team)
		"outpost":
			return _outpost(me.team).p
		"goal":
			return Vector2(0.0, 4.0) if me.team == 0 else Vector2(0.0, -4.0)
	return null

func _stand(team: int, cls: String) -> Dictionary:
	for st in sim.stands:
		if int(st.team) == team and str(st.cls) == cls:
			return st
	return {}

func _outpost(team: int) -> Dictionary:
	# The outpost on our half nearest to our castle.
	var best: Dictionary = {}
	for op in sim.outposts:
		var on_ours: bool = (op.p.y > 0.0) == (team == 0)
		if on_ours and (best.is_empty() or absf(op.p.y) > absf(best.p.y)):
			best = op
	return best

func task_done() -> bool:
	var me: Dictionary = sim.by_id[hud.player_id]
	match str(STEPS[step].id):
		"move":
			return me.pos.distance_to(_start) >= 6.0
		"hat":
			return me.cls == "knight"
		"attack":
			var foe: Dictionary = sim.by_id.get(_dummy_id, {})
			if not foe.is_empty():
				foe.move = Vector2.ZERO
				if foe.hp < _dummy_hp - 0.5:
					_hits += 1
					_dummy_hp = foe.hp
			return _hits >= 3
		"dodge":
			return me.state == "dodge"
		"block":
			return _block_t >= 1.0
		"workshop":
			return me.pos.distance_to(Sim.workshop(me.team)) <= Sim.WORKSHOP_RADIUS
		"upgrade":
			return int(sim.levels[me.team].get("hat_knight", 0)) >= 1
		"outpost":
			return int(_outpost(me.team).owner) == me.team
		"goal":
			return (me.pos.y < 8.0) if me.team == 0 else (me.pos.y > -8.0)
	return true

func _process(delta: float) -> void:
	if sim == null:
		return
	_time += delta
	# Keep the castle quiet (the sim's own respawn/brains won't wake them: bot = false).
	var me: Dictionary = sim.by_id.get(hud.player_id, {})
	if me.is_empty():
		return
	if phase == "task":
		if str(STEPS[step].id) == "block" and sim.blocking(me):
			_block_t += delta
		if str(STEPS[step].id) == "hat" and me.cls not in ["villager", "knight"]:
			task_label.text = "▶ Fine hat, wrong hat. At the Knight hat shop press ACTION (NEW HAT) to swap."
		if task_done():
			_complete_task()
	elif phase in ["talk", "done"]:
		var full := str(current_line()[1])
		shown = minf(shown + delta * TYPE_CPS, float(full.length()) + 1.0)
		text_label.text = full.substr(0, int(shown))
	queue_redraw()

# ---------------- drawing: arrows and button rings ----------------
func _draw() -> void:
	if sim == null or phase != "task":
		return
	var tgt: Variant = task_target()
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	var gold := Color("#f2c76b")
	if tgt is String:
		for b in hud._buttons():
			if str(b.id) == str(tgt):
				draw_arc(b.c, float(b.r) + 10.0 + 6.0 * pulse, 0.0, TAU, 40, gold, 4.0, true)
		return
	if not (tgt is Vector2):
		return
	var world := Vector3(tgt.x, Sim.height_at(tgt) + 2.2, tgt.y)
	var sp: Vector2 = hud.project.call(world)
	if hud.on_screen.call(world):
		# A bouncing arrow over the spot.
		var tip := sp + Vector2(0, -8.0 * pulse)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-16, -26), tip + Vector2(16, -26)]), gold)
		draw_rect(Rect2(tip + Vector2(-6, -52), Vector2(12, 28)), gold)
	else:
		# Off-screen: an arrow at the screen edge pointing the way.
		var center := size * 0.5
		var dir := (sp - center).normalized()
		var edge := center + dir * minf(size.x * 0.42, size.y * 0.36)
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([edge + dir * 22, edge - dir * 10 + side * 14, edge - dir * 10 - side * 14]), gold)
