extends SceneTree
# 0.31.155 5V5 (the test) in the app:
#  1. Home: (0.31.164, Kevin: "5v5 only") PLAY opens the hero window -- no 5V5 (TEST) medallion, for a new player too:
#     12 heroes, the last pick kept; (0.31.181) TUTORIAL, the 5v5's: a new player's starts it without a ticket;
#  2. a hero picked, BATTLE: an offline 5v5 as that hero;
#  3. the HUD: level and XP, the towers standing; a level-up's three upgrades tapped on the screen apply one;
#  4. (0.31.157) the gold and SHOP under the towers line: tapped, the shop; an item picked and bought in your castle;
#     the ULT button: LV 6 until level 6, then the Archmage's METEORS, tapped: cast; the jungle's skeletons and the
#     Bone Lord on the field (pictures);
#  5. (0.31.158) the fog of war: the shroud over what your side can't see (clear round you), an enemy out of your sight
#     not drawn, one in it drawn; the brush's bushes; WARD tapped: a ward at your feet, shown; (0.31.159) the lane
#     minions in their own Meshy bodies, the red side's repainted red;
#  6. the end: the results, paid like a match (0.31.164).
#   godot --headless --path godot -s res://tests/moba_ui_test.gd   (SHOT_DIR=... under Xvfb for pictures)
const App = preload("res://scripts/app/siege_app.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const HeroPanel = preload("res://scripts/app/moba_panel.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const ItemIcon = preload("res://scripts/siege/item_icon.gd")
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
				check(btn("side_moba") == null and btn("side_commander") == null and btn("play") != null and btn("home_menu") != null,
					"a new player's Home: PLAY and the menu, no 5V5 medallion")
				press("home_menu")                       # 0.31.194: the TUTORIAL is in the top bar's menu
				check(btn("tutorial_start") != null, "the menu has the TUTORIAL")
				press("tutorial_start")
				_go("fresh_pick")
		"fresh_pick":
			# 0.31.217: the TRAINING window -- which (THE BASICS first for a new player) and a hero of three, then BATTLE
			if t_phase > 0.4:
				check(btn("training_1") != null and btn("training_2") != null and btn("training_hero_knight") != null
					and btn("training_hero_mage") != null and btn("training_hero_ranger") != null and app.modal != null and int(app.modal.which) == 1,
					"TRAINING: the two trainings (THE BASICS picked) and three heroes")
				press("training_hero_mage")
				press("training_go")
				_go("fresh_tutorial")
		"fresh_tutorial":
			if t_phase > 0.5:
				check(app.siege != null and bool(app.siege.tutorial) and not bool(app.siege.online) and str(app.siege.moba_hero) == "mage"
					and int(app.siege.training) == 1,
					"BATTLE: training 1's match, offline, as the Mage (no ticket asked)")
				app.queue_free()
				app = null
				_go("boot")
		"boot":
			if t_phase > 0.3:
				_app(true)
				_go("home")
		"home":
			if t_phase > 1.0:
				check(btn("side_moba") == null and btn("side_commander") == null and btn("play") != null and btn("home_menu") != null,
					"Home: PLAY (the 5v5), the menu (the TUTORIAL in it)")
				_shot("moba_home")
				press("play")
				_go("heroes")
		"heroes":
			if t_phase > 0.4:
				check(app.modal is HeroPanel, "it opens the hero window")
				var n := 0
				for hid in Moba.HERO_ORDER:
					if btn("moba_hero_" + str(hid)) != null:
						n += 1
				var m = app.modal
				check(n == 18 and m.hero == "knight" and m._stage_name.text == "KNIGHT" and m._stage_role.text == "TANK" and has_text(m, "W SHIELD BASH"),
					"18 heroes; the Knight to start, described: his role and kit (0.31.167)")
				# 0.31.175: the stage -- the Knight in 3D on the hall's dais, his role's badge; the role badges over the columns
				check(m._show != null and m._show.cls == "knight" and m._stage_badge.texture != null and not m._stage_lock.visible
					and HeroPanel.role_badge("marksman") != null and m.find_children("*", "TextureRect", true, false).any(func(t): return t.texture != null and str(t.texture.resource_path).ends_with("hero_hall.webp")),
					"the stage: the Knight in 3D in the champions' hall, the TANK badge; a badge for each role")
				# 0.31.168: the new six are bought with gold -- a locked one shows its price; BATTLE becomes UNLOCK
				# (0.31.185: the clock on a week the Golem isn't in the free rotation)
				# (0.31.187: and after the six's launch price -- the launch price has its own test, league_iap_test)
				var wk := maxi(int(Time.get_unix_time_from_system()), Eco.SIX_LAUNCH + Eco.LAUNCH_DAYS * 86400)
				while Eco.free_heroes(wk).has("golem"):
					wk += 7 * 86400
				app.profile.now_override = wk
				app.profile.d.gold = 10000
				press("moba_hero_golem")
				var go: Button = app.modal._go
				check(app.modal.hero == "golem" and not app.profile.owns_hero("golem") and go.text == "GET IN MARKET" and not go.disabled
					and app.modal._stage_name.text == "GOLEM" and app.modal._stage_lock.visible and app.modal._stage_price.text == "25,000"
					and has_text(app.modal, "Q BOULDER"), "the Golem: locked, 25,000 gold -- GET IN MARKET (0.31.204; 0.31.189-0.31.203 UNLOCK)")
				_shot("moba_heroes_locked")
				app.profile.d.gold = 25600
				press("moba_battle")
				# 0.31.204 (Kevin: heroes are bought in the Market; asked: "Send to Market"): the Market's HEROES, his card lit
				var ring: Array = app.content.find_children("*", "Panel", true, false).filter(func(n): return n.has_meta("hero_focus_ring"))
				check(not is_instance_valid(app.modal) and app.tab == "shop" and str(app.shop_tab) == "heroes" and btn("hero_unlock_golem") != null
					and ring.size() == 1 and ring[0].get_parent() == btn("hero_look_golem").get_parent(),
					"GET IN MARKET: the window shuts, the Market's HEROES with the Golem's card lit")
				press("hero_unlock_golem")
				check(app.modal != null and btn("hero_buy_gold") != null and btn("hero_buy_gems") != null and btn("hero_buy_shard") == null
					and btn("hero_buy_token") == null and has_text(app.modal, "UNLOCK GORRAK"), "UNLOCK there: the choice -- 25,000 gold or 450 gems")
				_shot("moba_unlock_chooser")
				press("hero_buy_gold")
				check(app.profile.owns_hero("golem") and int(app.profile.d.gold) == 600 and btn("hero_look_golem") == null,
					"25,000 gold: the Golem is yours (gone from the Market's HEROES)")
				_go("reopen")                         # (a frame for the 5v5 window GET IN MARKET shut to go)
		"reopen":
			if t_phase > 0.1:
				app.open_moba()
				press("moba_hero_golem")
				check(app.modal.hero == "golem" and app.modal._go.text == "BATTLE" and not app.modal._stage_lock.visible, "back in the 5v5 window: the Golem plays")
				app.profile.now_override = -1
				press("moba_hero_archmage")
				check(app.modal.hero == "archmage" and app.modal._stage_name.text == "ARCHMAGE" and app.modal._stage_role.text == "MAGE"
					and app.modal._show.cls == "archmage" and has_text(app.modal, "E MANA SHIELD"), "the Archmage picked")
				_shot("moba_heroes")
				gold0 = int(app.profile.d.gold)
				# (0.31.170: a server without the online 5v5 -- BATTLE is the match against bots, as here since 0.31.155;
				# online_five_test plays the server's)
				app.server_five = 0
				press("moba_battle")
				_go("match")
		"match":
			if app.siege != null and app.siege.sim != null and app.siege.hud != null and t_phase > 1.0:
				var s = app.siege
				var me: Dictionary = s.sim.by_id["you"]
				check(str(app.profile.d.settings.get("moba_hero", "")) == "archmage", "the pick kept on the phone")
				check(s.moba_hero == "archmage" and not s.online and s.sim.moba != null and me.cls == "mage" and me.up
					and s.sim.units.size() == 10, "BATTLE: an offline 5v5, you the Archmage")
				# 0.31.217 (Honor of Kings): a level up -- a skill point; a + over each skill it can go on; tap W's
				s.sim.moba.add_xp(me, Moba.XP_BASE + 1.0)
				var spots: Array = s.hud.learn_spots(me)
				var wsp: Array = spots.filter(func(x): return str(x.slot) == "w")
				check(int(me.level) == 2 and int(me.sp) == 2 and spots.size() == 3 and wsp.size() == 1 and (me.picks as Array).is_empty(),
					"level 2: two skill points, a + over Q, W and E (%d)" % spots.size())
				if wsp.size() == 1:
					s.hud._touch(0, wsp[0].c, true)
					s.hud._touch(0, wsp[0].c, false)
				check(s.sim.moba.rank(me, "w") == 1 and int(me.sp) == 1, "W's + tapped: W learnt, a point left")
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
				check(s.hud.shop_open() and btn("shop_item_sword") != null and btn("shop_item_archon") != null and btn("shop_slot_0") != null
					and btn("shop_tab_0") != null and btn("shop_tab_4") != null and btn("shop_item_bloodthirster") == null,
					"tapped: the shop -- your slots, RECOMMENDED (the Archmage's list: no Bloodthirster) and the other tabs")
				press("shop_tab_1")                      # 0.31.217: Honor of Kings' tabs
				check(btn("shop_item_bloodthirster") != null and btn("shop_item_tome") == null, "ATTACK: the attack items, the Bloodthirster among them")
				press("shop_tab_0")
				var g0 := int(me.gold)
				press("shop_item_sword")
				s.hud._refresh_shop(me)
				check(has_text(s.hud.shop_panel, "LONG SWORD") and has_text(s.hud.shop_panel, "BUY · 350"), "a Long Sword picked: what it gives, BUY · 350")
				# 0.31.175: every item its painted icon and its name on its cell; the armory painted over the shop
				var painted := Moba.ITEM_ORDER.all(func(x): return ItemIcon.texture(str(x)) != null)
				check(painted and has_text(s.hud.shop_panel, "Archon Staff") and s.hud._shop_pick_icon.item == "sword"
					and s.hud.shop_panel.find_children("*", "TextureRect", true, false).any(func(t): return t.texture != null and str(t.texture.resource_path).ends_with("shop_banner.webp")),
					"the shop in paint: each item's icon and name, the armory across the top, the picked item's icon")
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
				s.sim.moba._bot_learn(me)                 # (0.31.217: every point spent)
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
				check(not lord.is_empty() and s.view.actors.has(lord.id), "the Bone Lord in his pit")
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
				r1.pos = Vector2(14.0, -20.0)
				r2.pos = me.pos + Vector2(4.0, -3.0)
				s.sim.moba.wave_at = s.sim.time                  # (0.31.159: a wave, for the minions' bodies)
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
				check(s.view.get_node_or_null("FogOfWar") is Decal and s.view.fog_alpha_at(me.pos) == 0 and s.view.fog_alpha_at(Vector2(14.0, -20.0)) == s.view.FOG_ALPHA,
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
				# 0.31.159: the minions' bodies -- each kind its own Meshy body, the red side's in red
				var kinds := {}
				var red_ok := false
				for u in s.sim.units:
					if not bool(u.get("minion", false)) or not s.view.actors.has(u.id):
						continue
					var ma: Dictionary = s.view.actors[u.id]
					if ma.body == null:
						continue
					kinds[str(ma.get("mlook", ""))] = true
					if int(u.team) == 1 and not red_ok:
						for mi in (ma.body as Node).find_children("*", "MeshInstance3D", true, false):
							for si in (mi as MeshInstance3D).mesh.get_surface_count():
								var om := (mi as MeshInstance3D).get_surface_override_material(si) as StandardMaterial3D
								red_ok = red_ok or (om != null and om.albedo_texture != null and om.albedo_texture.resource_path.ends_with("_red.jpg"))
				check(kinds.has("minion_melee") and kinds.has("minion_caster") and not kinds.has(""), "the minions in their own bodies (%s)" % str(kinds.keys()))
				check(red_ok, "...the red side's repainted red")
				_shot("moba_fog")
				me.pos = Sim.spawn(0)
				_go("play")
		"play":
			if t_phase > 0.5 and t_phase < 0.6:
				var s0 = app.siege
				var y0: Dictionary = s0.sim.by_id["you"]
				y0["sp"] = int(y0.get("sp", 0)) + 1                   # (0.31.217: a point waiting, for the picture)
			if t_phase > 3.0:
				_shot("moba_match")
				var s = app.siege
				check(not s.hud.learn_spots(s.sim.by_id["you"]).is_empty() and has_moba_status(s), "a skill point waiting: a + on the screen; LEVEL and TOWERS under your health")
				s.sim._finish("time")
				_go("end")
		"end":
			if t_phase > 1.5:
				var s = app.siege
				check(s.hud.result_panel != null and int(app.profile.d.gold) > gold0 and int(app.profile.d.stats.get("matches", 0)) == 1,
					"the results, paid like a match (+%d gold)" % (int(app.profile.d.gold) - gold0))
				_shot("moba_result")
				return _finish()
	return false

func has_moba_status(s) -> bool:
	# (drawn, not nodes: the HUD's status draws from these)
	var me: Dictionary = s.sim.by_id["you"]
	return int(me.level) >= 2 and s.sim.moba.towers.size() == 18        # (0.31.217: nine a side -- three a lane, no King towers)

func _finish() -> bool:
	print("MOBA_UI_PASS" if fails.is_empty() else "MOBA_UI_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true
