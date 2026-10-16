extends SceneTree
# 0.31.155 5V5 (the test) in the app:
#  1. Home: 5V5 (TEST) on the right -- under TUTORIAL until the tutorial's done, in its place after; it opens the hero
#     window: 12 heroes, the last pick kept;
#  2. a hero picked, BATTLE: an offline 5v5 as that hero (no server, no ticket);
#  3. the HUD: level and XP, the towers standing; a level-up's three upgrades tapped on the screen apply one;
#  4. (0.31.157) the gold and SHOP under the towers line: tapped, the shop; an item picked and bought in your castle;
#     the ULT button: LV 6 until level 6, then the Archmage's METEORS, tapped: cast; the jungle's skeletons and the
#     Bone Lord on the field (pictures);
#  5. (0.31.158) the fog of war: the shroud over what your side can't see (clear round you), an enemy out of your sight
#     not drawn, one in it drawn; the brush's bushes; WARD tapped: a ward at your feet, shown;
#  6. the end: the results without rewards (the gold as it was).
#   godot --headless --path godot -s res://tests/moba_ui_test.gd   (SHOT_DIR=... under Xvfb for pictures)
const App = preload("res://scripts/app/siege_app.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const HeroPanel = preload("res://scripts/app/moba_panel.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")

var fails: Array = []
var phase := "fresh"
var t := 0.0
var t_phase := 0.0
var app
var shots := ""
var gold0 := 0
var ult_seen := false

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func btn(key: String, node: Node = null) -> Button:
	if node == null:
		node = app
	if node is Button and str(node.get_meta("action_key", "")) == key and node.is_visible_in_tree():
		return node
	for c in node.get_children():
		var r := btn(key, c)
		if r != null:
			return r
	return null

func press(key: String) -> bool:
	var b := btn(key)
	if b == null or b.disabled:
		check(false, "button %s present and enabled" % key)
		return false
	b.pressed.emit()
	return true

func has_text(node: Node, s: String) -> bool:
	if (node is Label and (node as Label).text.contains(s)) or (node is Button and (node as Button).text.contains(s)):
		return node.is_visible_in_tree()
	for c in node.get_children():
		if has_text(c, s):
			return true
	return false

func _init() -> void:
	shots = OS.get_environment("SHOT_DIR") if DisplayServer.get_name() != "headless" else ""
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")

func _shot(name: String) -> void:
	if shots != "":
		root.get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))

func _go(next: String) -> void:
	phase = next
	t_phase = 0.0

func _app(done: bool) -> void:
	var base := "user://mobaui-%d" % Time.get_ticks_usec()
	var p = Profile.new(base + "-profile.json", base + "-none.json")
	p.load_or_create()
	p.d.name = "Alice"
	p.d.tutorial_done = done
	p.save()
	app = App.new()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	root.add_child(app)

func _process(delta: float) -> bool:
	t += delta
	t_phase += delta
	if t > 200.0:
		check(false, "timed out in phase %s" % phase)
		return _finish()
	match phase:
		"fresh":
			_app(false)
			_go("fresh_home")
		"fresh_home":
			if t_phase > 1.0:
				var tb := btn("tutorial_start")
				var mb := btn("side_moba")
				var pb := btn("play")
				check(tb != null and mb != null and has_text(mb, "5V5") and mb.global_position.y >= tb.global_position.y + tb.size.y - 8.0
					and absf(mb.global_position.x - tb.global_position.x) < 1.0 and pb != null and not mb.get_global_rect().intersects(pb.get_global_rect()),
					"no tutorial yet: 5V5 under TUTORIAL, clear of PLAY")
				app.queue_free()
				app = null
				_go("boot")
		"boot":
			if t_phase > 0.3:
				_app(true)
				_go("home")
		"home":
			if t_phase > 1.0:
				check(btn("side_moba") != null and btn("tutorial_start") == null and btn("side_commander") == null, "Home: 5V5 where the tutorial was")
				_shot("moba_home")
				press("side_moba")
				_go("heroes")
		"heroes":
			if t_phase > 0.4:
				check(app.modal is HeroPanel, "it opens the hero window")
				var n := 0
				for hid in Moba.HERO_ORDER:
					if btn("moba_hero_" + str(hid)) != null:
						n += 1
				check(n == 12 and app.modal.hero == "knight" and has_text(app.modal, "Knight: Shield up"), "12 heroes; the Knight to start, described")
				press("moba_hero_archmage")
				check(app.modal.hero == "archmage" and has_text(app.modal, "Archmage: Calls down a meteor"), "the Archmage picked")
				_shot("moba_heroes")
				gold0 = int(app.profile.d.gold)
				press("moba_battle")
				_go("match")
		"match":
			if app.siege != null and app.siege.sim != null and app.siege.hud != null and t_phase > 1.0:
				var s = app.siege
				var me: Dictionary = s.sim.by_id["you"]
				check(str(app.profile.d.settings.get("moba_hero", "")) == "archmage", "the pick kept on the phone")
				check(s.moba_hero == "archmage" and not s.online and not s.tutorial and s.sim.moba != null and me.cls == "mage" and me.up
					and s.sim.units.size() == 10, "BATTLE: an offline 5v5, you the Archmage")
				# a level up: three upgrades on the screen; tap the second
				s.sim.moba.add_xp(me, Moba.XP_BASE + 1.0)
				var offer: Array = (me.picks as Array)[0]
				var r: Rect2 = s.hud.pick_rect(1)
				s.hud._touch(0, r.get_center(), true)
				s.hud._touch(0, r.get_center(), false)
				check(int(me.level) == 2 and (me.picks as Array).is_empty() and int((me.ups as Dictionary).get(str(offer[1]), 0)) == 1,
					"level 2: three upgrades on the screen; the second tapped (%s) applies" % str(offer[1]))
				# the shop: the gold pill tapped
				var ub: Array = s.hud._buttons().filter(func(b): return str(b.id) == "ult")
				check(ub.size() == 1 and s.sim.moba.ult_rank(me) == 0, "the ULT button, locked (LV %d)" % Moba.ULT_LEVEL)
				var sr: Rect2 = s.hud.shop_rect()
				s.hud._touch(0, sr.get_center(), true)
				s.hud._touch(0, sr.get_center(), false)
				_go("shop")
		"shop":
			if t_phase > 0.6:
				var s = app.siege
				var me: Dictionary = s.sim.by_id["you"]
				check(s.hud.shop_open() and btn("shop_item_sword") != null and btn("shop_item_bloodthirster") != null and btn("shop_slot_0") != null,
					"tapped: the shop -- your slots, the small items and the big ones")
				var g0 := int(me.gold)
				press("shop_item_sword")
				s.hud._refresh_shop(me)
				check(has_text(s.hud.shop_panel, "LONG SWORD") and has_text(s.hud.shop_panel, "BUY · 350"), "a Long Sword picked: what it gives, BUY · 350")
				press("shop_act")
				check((me.items as Array) == ["sword"] and int(me.gold) == g0 - 350, "bought, in your castle (%d gold left)" % int(me.gold))
				_go("shop2")
		"shop2":
			if t_phase > 0.5:
				_shot("moba_shop")
				press("shop_close")
				var s = app.siege
				var me: Dictionary = s.sim.by_id["you"]
				s.sim.moba.add_xp(me, 99999.0)
				while not (me.picks as Array).is_empty():
					s.sim.moba.pick(me, 0)
				me.pos = Vector2(-20.0, 38.0)
				me.face = s.sim.angle_of(Vector2(0, -1))
				me.state = "idle"
				_go("ult")
		"ult":
			if t_phase > 0.5:
				var s = app.siege
				var me: Dictionary = s.sim.by_id["you"]
				var b: Dictionary = s.hud._buttons().filter(func(x): return str(x.id) == "ult")[0]
				check(not s.hud.shop_open() and s.sim.moba.ult_rank(me) >= 1, "closed; level %d: the ultimate is yours" % int(me.level))
				s.hud._touch(1, b.c, true)
				s.hud._touch(1, b.c, false)
				_go("ult2")
		"ult2":
			if t_phase > 0.1 and not ult_seen:
				ult_seen = true
				var s = app.siege
				var me: Dictionary = s.sim.by_id["you"]
				check(float(me.ult_cd) > 0.0 and s.sim.meteors.size() >= Moba.STORM_N, "ULT tapped: METEORS (%d)" % s.sim.meteors.size())
			if t_phase > 1.1:
				_shot("moba_ult")
				var s = app.siege
				var camp: Dictionary = s.sim.moba.camps.filter(func(c): return str(c.kind) == "pack" and int(c.side) == 0)[0]
				s.sim.moba._spawn_camp(camp)
				var me: Dictionary = s.sim.by_id["you"]
				me.pos = (camp.p as Vector2) + Vector2(1.0, 5.0)
				me.face = s.sim.angle_of(Vector2(0, -1))
				s.view.snap_camera()
				_go("camp")
		"camp":
			if t_phase > 1.2:
				var s = app.siege
				var mons: Array = s.sim.units.filter(func(u): return u.has("mon") and s.sim.alive(u))
				check(mons.size() == 3 and mons.all(func(u): return s.view.actors.has(u.id) and s.view.actors[u.id].body != null),
					"the Bone Pack on the field: three skeletons")
				_shot("moba_camp")
				var lc: Dictionary = s.sim.moba.camps.filter(func(c): return str(c.kind) == "lord")[0]
				s.sim.moba._spawn_camp(lc)
				var me: Dictionary = s.sim.by_id["you"]
				me.pos = Moba.BOSS_P + Vector2(0.5, 6.0)
				me.face = s.sim.angle_of(Vector2(0, -1))
				s.view.snap_camera()
				_go("lord")
		"lord":
			if t_phase > 1.2:
				var s = app.siege
				var lord: Dictionary = s.sim.moba._lord_unit()
				check(not lord.is_empty() and s.view.actors.has(lord.id), "the Bone Lord on the island")
				_shot("moba_lord")
				# 0.31.158: the fog -- you in the jungle, one red hero far off in red's, one a few steps from you
				var me: Dictionary = s.sim.by_id["you"]
				me.pos = Vector2(-27.0, 26.0)
				me.face = s.sim.angle_of(Vector2(0, -1))
				var r1: Dictionary = s.sim.by_id["r1"]
				var r2: Dictionary = s.sim.by_id["r2"]
				for r in [r1, r2]:
					r.bot = false
					r.move = Vector2.ZERO
					if not s.sim.alive(r):
						s.sim._respawn(r)
				r1.pos = Vector2(28.0, -35.0)
				r2.pos = me.pos + Vector2(4.0, -3.0)
				s.view.snap_camera()
				var wb: Array = s.hud._buttons().filter(func(x): return str(x.id) == "ward")
				check(wb.size() == 1, "the WARD button")
				if wb.size() == 1:
					s.hud._touch(1, wb[0].c, true)
					s.hud._touch(1, wb[0].c, false)
				_go("fog")
		"fog":
			if t_phase > 0.8:
				var s = app.siege
				var me: Dictionary = s.sim.by_id["you"]
				var v = s.sim.moba.vision
				check(v.wards.any(func(w): return str(w.owner) == "you") and s.view._ward_nodes.size() >= 1, "WARD tapped: a ward at your feet, shown")
				check(s.view.get_node_or_null("FogOfWar") is Decal and s.view.fog_alpha_at(me.pos) == 0 and s.view.fog_alpha_at(Vector2(28.0, -35.0)) == s.view.FOG_ALPHA,
					"the fog: clear round you, dark over red's jungle")
				var a1: Dictionary = s.view.actors.get("r1", {})
				var a2: Dictionary = s.view.actors.get("r2", {})
				check(not a1.is_empty() and not (a1.root as Node3D).visible and not a2.is_empty() and (a2.root as Node3D).visible,
					"a red hero out of your side's sight isn't drawn; one in it is")
				var bushes := 0
				for c in s.view.get_children():
					if c is MultiMeshInstance3D and str(c.name).begins_with("Brush_"):
						bushes += (c as MultiMeshInstance3D).multimesh.instance_count
				check(bushes >= 40, "the brush patches' bushes (%d)" % bushes)
				_shot("moba_fog")
				me.pos = Sim.spawn(0)
				_go("play")
		"play":
			if t_phase > 0.5 and t_phase < 0.6:
				var s0 = app.siege
				var y0: Dictionary = s0.sim.by_id["you"]
				for k in 2:
					(y0.picks as Array).append(s0.sim.moba._offer(y0))     # (picks waiting, for the picture)
			if t_phase > 3.0:
				_shot("moba_match")
				var s = app.siege
				check(s.hud._picks_open() and has_moba_status(s), "picks waiting on the screen; LEVEL and TOWERS under your health")
				s.sim._finish("time")
				_go("end")
		"end":
			if t_phase > 1.5:
				var s = app.siege
				check(s.hud.result_panel != null and int(app.profile.d.gold) == gold0, "the results; no rewards (the gold as it was)")
				_shot("moba_result")
				return _finish()
	return false

func has_moba_status(s) -> bool:
	# (drawn, not nodes: the HUD's status draws from these)
	var me: Dictionary = s.sim.by_id["you"]
	return int(me.level) >= 2 and s.sim.moba.towers.size() == 12

func _finish() -> bool:
	print("MOBA_UI_PASS" if fails.is_empty() else "MOBA_UI_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true
