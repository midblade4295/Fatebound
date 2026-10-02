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
		["t_intro_1", "Ah, a new recruit! Welcome to Fatebound. I'm the Royal Herald. I announce things. Loudly. It's a living."],
		["t_intro_2", "Across that field, the enemy is holding our King hostage. We'd like him back. He does the ruling. And the waving."]]},
	{"id": "move", "talk": [
		["t_move_1", "First things first: walking. Drag your thumb on the left side of the screen. Yes, like that. No, the other left."]],
		"task": "Walk around a bit",
		"done": [["t_move_done", "Magnificent. You've mastered the ancient art of 'going places'. The bards will sing of it. Briefly."]]},
	{"id": "hat", "talk": [
		["t_hat_1", "Right now you're a Villager. Villagers are brave, loyal, and hit like a wet sock."],
		["t_hat_2", "See the Barracks? That's the Knight's hat shop. Walk up to its door. In this kingdom the hat makes the hero. Don't ask me why. I just read the scrolls."]],
		"task": "Get a Knight hat at the Barracks door",
		"done": [["t_hat_done", "A Knight! Look at you. Positively shiny. Try not to lose that hat. You'll see why in a moment."]]},
	{"id": "attack", "talk": [
		["t_attack_1", "A training dummy awaits in the courtyard. It volunteered. Well. 'Volunteered'. Walk up to it and tap ATTACK, or hold ATTACK to keep whacking."]],
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
		["t_up_1", "The treasury has kindly 'found' some materials for you. Go back to the Barracks and press UPGRADE."]],
		"task": "Upgrade the Knight hats at the Barracks",
		"done": [["t_up_done", "Crusader hats! Every hat from that shop is fancier now. Upgrades are bought at each hat shop, not the workshop. The workshop is still sulking about it."]]},
	{"id": "rampart", "talk": [
		["t_rampart_1", "One more trick for defending. See the walkway on our front wall? Take its stairs up, and your arrows fly right over the wall. Archers adore it. The enemy does not."]]},
	{"id": "outpost", "talk": [
		["t_out_1", "See that tower up on the ledge? That's an outpost. Stand in its ring to capture it. Capturing is mostly standing around looking important. You're a natural."]],
		"task": "Capture the outpost",
		"done": [["t_out_done", "It's ours! Workers can drop resources off here, and it earns us wood and stone. Passive income. The true magic."]]},
	{"id": "goal", "talk": [
		["t_goal_1", "Now, the actual point of Fatebound. The enemy's dungeon is down a flight of stairs inside their castle, behind their gates. Our King is in there, behind bars. Probably complaining."],
		["t_goal_2", "Break a gate down, and Barbarians are marvellous at that, or have a Worker build a ladder over the wall. Then smash his cell open, grab him and carry him home to his throne."],
		["t_goal_3", "Rescue him three times and we win. They're trying to do the exact same thing to us, so leave a few friends at home. Trust issues are healthy here."]]},
	{"id": "fish", "talk": [
		["t_cake_1", "But first, a dirty trick. See the river? It's full of fish. Stand on the bank and press ACTION to cast your line. Patience. Fish are not known for their punctuality."]],
		"task": "Catch a fish at the river (ACTION on the bank)",
		"done": [["t_cake_took", "A fish! Magnificent. Now, we have a guest in OUR dungeon: the enemy's King. He looks peckish."]]},
	{"id": "feed", "talk": [
		["t_feed_1", "Our dungeon is down the stairs, and the cell door opens for friends. Bring him that fish and press ACTION to feed him. Every bite makes him heavier. Delicious sabotage."]],
		"task": "Feed the fish to their King in our dungeon (ACTION)",
		"done": [["t_feed_done", "He said thank you! Is it tactically brilliant? Yes. Is it ethically questionable? Also yes. Welcome to Fatebound."]]},
	{"id": "shortcut", "talk": [
		["t_rescue_1", "Right. Let's get OUR King back. Normally you'd march over, smash a gate and fight your way in. Today I've arranged a shortcut. Don't ask how. Royal paperwork."]]},
	{"id": "grab", "talk": [
		["t_grab_1", "Here we are. Their gate is, ahem, 'mysteriously broken'. So is his cell door. Go down to their dungeon, find our King and press ACTION to lift him."]],
		"task": "Lift our King in their dungeon (ACTION)",
		"done": [["t_grab_done", "Got him! You're slower while carrying. Heavier Kings need friends to help lift, which is exactly why we feed THEIRS so much fish."]]},
	{"id": "carry", "talk": [
		["t_carry_1", "Now carry him all the way home to his throne. Follow the arrow. And don't drop him. He will never let you forget it."]],
		"task": "Carry our King home to his throne",
		"done": [["t_carry_done", "RESCUED! That's one! Rescue him three times and the match is ours. The crowd goes mild."]]},
	{"id": "end", "talk": [
		["t_end_1", "That's everything! Well. Not everything. But everything I was paid to say."],
		["t_end_2", "Go forth, recruit. Fatebound awaits. Win glory, rescue the King, and please, try to keep your hat on."]]},
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
var _fed0 := 0
var _path := PackedVector2Array()
var _path_clock := 0.0
const DUMMY_AT := Vector2(4.0, 6.6)      # castle-local: open courtyard floor
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
	if str(STEPS[step].id) == "grab":
		_shortcut()
	_show_line()

func _shortcut() -> void:
	# The Herald's "royal paperwork": the recruit appears outside the enemy gate on their dungeon's
	# side, and that gate is broken (walking the whole map would drag in a tutorial).
	var me: Dictionary = sim.by_id[hud.player_id]
	var foe_team := 1 - int(me.team)
	var cell: Vector2 = Sim.cell(me.team)                  # our Oracle is held in THEIR dungeon
	var best: Dictionary = {}
	for g in sim.gates:
		if int(g.team) == foe_team and (best.is_empty() or (g.c as Vector2).distance_to(cell) < (best.c as Vector2).distance_to(cell)):
			best = g
	if best.is_empty():
		return
	best.hp = 0.0
	best.broken = true
	# ...and their jail door down in the dungeon wing (Round 13), or the recruit would face bars.
	for g in sim.gates:
		if int(g.team) == foe_team and str(g.get("kind", "")) == "jail":
			g.hp = 0.0
			g.broken = true
	sim._update_gate_nav()
	me.pos = Sim.gate_front(best)
	me.face = Sim.angle_of((best.c as Vector2) - me.pos)
	if mode.view != null and mode.view.has_method("snap_camera"):
		mode.view.snap_camera()

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
	# The Herald follows the Settings "Master volume" slider and the mute switch, like every other
	# sound (native_audio.gd); he plays above the effects, which run at 0.12 x master x effects.
	var master := 1.0
	var muted := false
	if mode != null and mode.audio != null:
		master = float(mode.audio.levels.get("master", 0.8))
		muted = bool(mode.audio.get("muted"))
	if muted or master <= 0.0:
		return
	voice.volume_db = linear_to_db(master)
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
			# Open courtyard floor between the spawn and the east gate: clear of every building (next
			# to the knight armory it blended in, Kevin 0.19.0). Its own marker says what it is.
			foe.pos = Sim._c(me.team, DUMMY_AT)
			_dummy_hp = foe.hp
			_hits = 0
		"upgrade":
			var cost: Dictionary = sim.upgrade_cost(me.team, "hat_knight")
			sim.stock[me.team].wood = maxi(int(sim.stock[me.team].wood), int(cost.get("wood", 12)))
			sim.stock[me.team].stone = maxi(int(sim.stock[me.team].stone), int(cost.get("stone", 12)))
		"block":
			_block_t = 0.0
		"feed":
			_fed0 = int(me.fed)

func _leave_step() -> void:
	if str(STEPS[step].id) == "attack" and _dummy_id != "":
		# The dummy goes home, healed and slightly humiliated.
		var foe: Dictionary = sim.by_id.get(_dummy_id, {})
		if not foe.is_empty():
			foe.max_hp = float(sim.stat(foe, "hp"))
			foe.hp = foe.max_hp
			foe.pos = Sim.spawn(foe.team)
		_dummy_id = ""

func task_info() -> Dictionary:
	# Guidance for the current task: "pos" (world Vector2) + "label" for the marker and path line,
	# and/or "button" (a HUD button id) to ring.
	var me: Dictionary = sim.by_id[hud.player_id]
	match str(STEPS[step].id):
		"hat", "upgrade":
			return {"pos": _stand(me.team, "knight").p, "label": "KNIGHT HAT SHOP"}
		"attack":
			var foe: Dictionary = sim.by_id.get(_dummy_id, {})
			return {"pos": foe.pos, "label": "TRAINING DUMMY", "button": "attack"} if not foe.is_empty() else {"button": "attack"}
		"dodge":
			return {"button": "dodge"}
		"block":
			return {"button": "ability", "hold": true}
		"workshop":
			return {"pos": Sim.workshop(me.team), "label": "WORKSHOP"}
		"outpost":
			return {"pos": _outpost(me.team).p, "label": "OUTPOST"}
		"fish":
			var spot: Vector2 = sim._fish_spot(me)
			return {"pos": spot, "label": "RIVER"} if spot != Vector2.INF else {}
		"feed":
			return {"pos": sim.oracles[1 - int(me.team)].pos, "label": "THEIR KING"}
		"grab":
			return {"pos": sim.oracles[int(me.team)].pos, "label": "OUR KING"}
		"carry":
			return {"pos": Sim.throne(me.team), "label": "OUR THRONE"}
	return {}

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
		"fish":
			return bool(me.offering)
		"feed":
			return int(me.fed) > _fed0
		"grab":
			return bool(me.carrying)
		"carry":
			return int(sim.score[int(me.team)]) >= 1
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
		_update_path(delta)
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

# ---------------- drawing: guidance (0.19.1, Kevin: "make the arrows more obvious and clear") ----------------
# A marching dotted line along the actual walking route (nav path: through gates and up stairs),
# a pulsing ring on the ground at the target, a big outlined arrow over it with a name + distance
# plate, a big labelled edge arrow when the target is off-screen, and TAP / HOLD rings on buttons.
const GOLD := Color("#ffd257")
const INK := Color(0.08, 0.05, 0.02, 0.9)

func _update_path(delta: float) -> void:
	_path_clock -= delta
	if _path_clock > 0.0:
		return
	_path_clock = 0.4
	var info := task_info()
	var me: Dictionary = sim.by_id[hud.player_id]
	_path = sim.find_path(me.team, me.pos, info.pos) if info.has("pos") else PackedVector2Array()

func _w(p: Vector2, lift := 0.15) -> Vector3:
	return Vector3(p.x, Sim.height_at(p) + lift, p.y)

func _plate(center: Vector2, text: String) -> void:
	var font: Font = ThemeDB.fallback_font
	var fs := 15
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 20.0
	var r := Rect2(center.x - w * 0.5, center.y - 14, w, 26)
	draw_rect(r.grow(2), INK)
	draw_rect(r, Color(0.12, 0.09, 0.03, 0.95))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), GOLD)
	draw_string(font, Vector2(r.position.x + 10, r.position.y + 19), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

func _arrow_down(tip: Vector2, s: float) -> void:
	# A fat downward arrow with a dark outline.
	var pts := PackedVector2Array([tip, tip + Vector2(-22, -26) * s, tip + Vector2(-9, -26) * s, tip + Vector2(-9, -52) * s,
		tip + Vector2(9, -52) * s, tip + Vector2(9, -26) * s, tip + Vector2(22, -26) * s])
	var out := PackedVector2Array()
	var c := Vector2.ZERO
	for q in pts: c += q
	c /= pts.size()
	for q in pts: out.append(c + (q - c) * 1.18)
	draw_colored_polygon(out, INK)
	draw_colored_polygon(pts, GOLD)

func _arrow_up(tip: Vector2, s: float) -> void:
	var pts := PackedVector2Array([tip, tip + Vector2(22, 26) * s, tip + Vector2(9, 26) * s, tip + Vector2(9, 52) * s,
		tip + Vector2(-9, 52) * s, tip + Vector2(-9, 26) * s, tip + Vector2(-22, 26) * s])
	var out := PackedVector2Array()
	var c := Vector2.ZERO
	for q in pts: c += q
	c /= pts.size()
	for q in pts: out.append(c + (q - c) * 1.18)
	draw_colored_polygon(out, INK)
	draw_colored_polygon(pts, GOLD)

func _draw() -> void:
	if sim == null or phase != "task":
		return
	var info := task_info()
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	var me: Dictionary = sim.by_id[hud.player_id]
	if info.has("button"):
		for b in hud._buttons():
			if str(b.id) == str(info.button):
				var rr: float = float(b.r) + 12.0 + 8.0 * pulse
				draw_arc(b.c, rr + 3.0, 0.0, TAU, 48, INK, 9.0, true)
				draw_arc(b.c, rr, 0.0, TAU, 48, GOLD, 6.0, true)
				_plate(b.c + Vector2(0, -float(b.r) - 34.0), "HOLD" if info.get("hold", false) else "TAP")
	if not info.has("pos"):
		return
	var tgt: Vector2 = info.pos
	# The route: dots every 1.1 m along the nav path, marching toward the target.
	var pts := PackedVector2Array([me.pos])
	pts.append_array(_path)
	pts.append(tgt)
	var step_len := 1.1
	var along := fmod(_time * 2.2, step_len)
	var walked := 0.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b2: Vector2 = pts[i + 1]
		var seg := a.distance_to(b2)
		while along < seg and walked + along < 40.0:
			var q := a.lerp(b2, along / seg)
			var wq := _w(q)
			if hud.on_screen.call(wq):
				var sq: Vector2 = hud.project.call(wq)
				draw_circle(sq, 7.0, INK)
				draw_circle(sq, 5.0, GOLD)
			along += step_len
		along -= seg
		walked += seg
	# Walking distance along the route (not straight through walls), and a guide point ~8 m ahead
	# on it: the edge arrow points there, so it always agrees with the dots. (Projecting the far
	# target itself flipped the arrow when it was behind the camera.)
	var route := 0.0
	var guide: Vector2 = tgt
	var got_guide := false
	for i in range(pts.size() - 1):
		var seg2: float = (pts[i] as Vector2).distance_to(pts[i + 1])
		if not got_guide and route + seg2 >= 8.0:
			guide = (pts[i] as Vector2).lerp(pts[i + 1], (8.0 - route) / maxf(seg2, 0.001))
			got_guide = true
		route += seg2
	var label := "%s · %d m" % [str(info.get("label", "HERE")), int(round(route))]
	var top := _w(tgt, 2.6)
	if hud.on_screen.call(_w(tgt, 0.0)):
		# A pulsing ring on the ground at the target.
		var ring := PackedVector2Array()
		var inner := PackedVector2Array()
		for k in 33:
			var ang := TAU * k / 32.0
			var off := Vector2(cos(ang), sin(ang))
			ring.append(hud.project.call(_w(tgt + off * 1.4, 0.08)))
			inner.append(hud.project.call(_w(tgt + off * (0.5 + 0.8 * pulse), 0.08)))
		draw_polyline(ring, INK, 9.0, true)
		draw_polyline(ring, GOLD, 5.0, true)
		draw_polyline(inner, Color(GOLD, 0.8 - 0.6 * pulse), 3.0, true)
		var tip: Vector2 = hud.project.call(top) + Vector2(0, -10.0 * pulse)
		var panel_bottom: float = panel.get_rect().end.y + 12.0
		if tip.y - 104.0 > panel_bottom:
			_arrow_down(tip, 1.25)
			_plate(tip + Vector2(0, -84), label)
		else:
			# Too close to the Herald's panel: point up at the target from below it instead.
			var base: Vector2 = hud.project.call(_w(tgt, 0.0))
			var tip2 := base + Vector2(0, 26.0 + 10.0 * pulse)
			_arrow_up(tip2, 1.25)
			_plate(tip2 + Vector2(0, 84), label)
	else:
		# Off-screen: a big edge arrow pointing the way, with the name and distance.
		var center := size * 0.5
		var from_s: Vector2 = hud.project.call(_w(me.pos, 1.0))
		var to_s: Vector2 = hud.project.call(_w(guide, 1.0))
		var dir := (to_s - from_s).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2(0, -1)
		var edge := center + dir * minf(size.x * 0.40, size.y * 0.34)
		edge.y = maxf(edge.y, panel.get_rect().end.y + 60.0)     # never under the Herald's panel
		var side := Vector2(-dir.y, dir.x)
		var tri := PackedVector2Array([edge + dir * 34, edge - dir * 14 + side * 24, edge - dir * 14 - side * 24])
		var tri_o := PackedVector2Array([edge + dir * 40, edge - dir * 18 + side * 30, edge - dir * 18 - side * 30])
		draw_colored_polygon(tri_o, INK)
		draw_colored_polygon(tri, GOLD)
		_plate(edge - dir * 46, label)
