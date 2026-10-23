extends SceneTree
# 0.31.208 (Kevin: "Make a all new loading screen graphic and as players join it'll show their character along with
# cosmetics they are wearing in the loading screen"): scripts/siege/loading_screen.gd.
#   1. Connecting: the new painting behind, the title, your hero alone on the plaza in your outfit, ringed in gold,
#      your name plate (YOU), LEAVE.
#   2. The lobby: each name's hero in the outfit sent beside it ("hr"/"sk"), built in that outfit; you in the middle;
#      the others in the order they came; each drops in and lands (a flip for a new one, none for those already there);
#      the plates say the outfit's name or the hero's.
#   3. One leaves: his hero goes. Seven: two rows, the second behind and a step up. An outfit not made for that hero (or
#      an unknown hero) isn't worn.
#   4. An older server (names only): the others as shadows ("joining..."), you as yourself.
#   5. loading(): PREPARING THE BATTLEFIELD, no LEAVE, the heroes stay; later lobby messages change nothing.
#   6. The match: offline its loading card is this screen (your hero on it); online the lobby itself becomes the card
#      at the welcome (siege_mode.gd).
const Loading = preload("res://scripts/siege/loading_screen.gd")
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const View = preload("res://scripts/siege/siege_view.gd")

class FakeAudio extends Node:
	var played: Array = []
	func play(cue: String, _quiet := false) -> void:
		played.append(cue)

var fails := []
var ls
var audio: FakeAudio
var phase := "connect"
var t := 0.0
var frames := 0
var mode

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	audio = FakeAudio.new()
	root.add_child(audio)
	ls = Loading.new()
	ls.audio = audio
	ls.my_hero = "knight"
	ls.my_skin = "knight_lion"
	ls.my_name = "Kevin"
	root.add_child(ls)

func _msg(names: Array, hr, sk, me := 0, left := 15.0) -> Dictionary:
	var m := {"t":"lobby", "left":left, "wait":20.0, "names":names, "tt":names.map(func(_n): return ""), "ct":names.map(func(_n): return ""),
		"me":me, "online":names.size(), "slots":10, "running":false}
	if hr != null:
		m["hr"] = hr
		m["sk"] = sk
	return m

func _fig_of(name_start: String) -> Dictionary:
	for f in ls.figs.values():
		if str(f.name).begins_with(name_start) and not bool(f.gone):
			return f
	return {}

func _live() -> Array:
	return ls.figs.values().filter(func(f): return not bool(f.gone))

func _skin_tex_on(body: Node3D, skin: String) -> bool:
	# the outfit's texture on one of the body's meshes (View.make_body dresses a body in an outfit's texture)
	var want := Eco.skin_texture(skin)
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var mats := [m.material_override]
		if m.mesh != null:
			for i in m.mesh.get_surface_count():
				mats.append(m.get_surface_override_material(i))
				mats.append(m.mesh.surface_get_material(i))
		for mat in mats:
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null and (mat as StandardMaterial3D).albedo_texture.resource_path == want:
				return true
			if mat is ShaderMaterial:
				for p in ["albedo", "tex", "texture_albedo", "albedo_texture"]:
					var v = (mat as ShaderMaterial).get_shader_parameter(p)
					if v is Texture2D and (v as Texture2D).resource_path == want:
						return true
	return false

func _process(delta: float) -> bool:
	t += delta
	frames += 1
	if frames > 4000:
		check(false, "timed out in " + phase)
		_finish()
		return false
	match phase:
		"connect":
			if t < 1.2:
				return false
			var bgs: Array = ls.find_children("*", "TextureRect", false, false).filter(func(n): return (n as TextureRect).texture != null and (n as TextureRect).texture.resource_path == Loading.BG)
			check(bgs.size() == 1, "1. the new painting behind (%s)" % Loading.BG)
			check(ls.find_children("*", "", true, false).any(func(n): return n.get_script() == Loading.TitleLogo), "1. the title over its sky")
			var live := _live()
			check(live.size() == 1 and bool(live[0].me) and str(live[0].hero) == "knight" and str(live[0].skin) == "knight_lion",
				"1. connecting: you alone on the plaza, your Knight in his Lionguard outfit")
			check(live.size() == 1 and live[0].body != null and bool(live[0].landed), "1. ...dropped in and landed")
			check(live.size() == 1 and _skin_tex_on(live[0].body, "knight_lion"), "1. ...the body wears the outfit")
			check(live.size() == 1 and str((live[0].plate_sub as Label).text) == str(Eco.SKINS.knight_lion.name), "1. the plate says the outfit (%s)" % str(Eco.SKINS.knight_lion.name))
			check(ls.leave_btn.visible and ls.state == "connecting", "1. LEAVE, connecting")
			# 2. the lobby: Mara (Stormcaller, Stormforged) and Ozzy (Golem, none) with me (second in the server's list)
			audio.played.clear()
			ls.update(_msg(["Mara", "Kevin", "Ozzy"], ["stormcaller", "knight", "golem"], ["stormcaller_stormforged", "knight_lion", ""], 1))
			phase = "lobby"
			t = 0.0
		"lobby":
			if t < 1.5:
				return false
			var live := _live()
			check(live.size() == 3, "2. three heroes on the plaza (%d)" % live.size())
			var mara := _fig_of("Mara")
			var ozzy := _fig_of("Ozzy")
			var me: Dictionary = ls.figs.get("me", {})
			check(not mara.is_empty() and str(mara.hero) == "stormcaller" and str(mara.skin) == "stormcaller_stormforged" and _skin_tex_on(mara.body, "stormcaller_stormforged"),
				"2. Mara's Stormcaller in the Stormforged outfit she wears")
			check(not ozzy.is_empty() and str(ozzy.hero) == "golem" and str(ozzy.skin) == "" and str((ozzy.plate_sub as Label).text) == "Golem", "2. Ozzy's Golem, his own look (the plate: Golem)")
			check(not me.is_empty() and absf(float((me.at as Vector3).x)) < 0.01, "2. you in the middle (x %.2f)" % (float((me.at as Vector3).x) if not me.is_empty() else -99.0))
			check(live.all(func(f): return bool(f.landed)), "2. each landed")
			check(int(ls.joined_n) == 3, "2. three landings (%d)" % int(ls.joined_n))
			check(audio.played.has("flip") == false, "2. no flip for those already there when the lobby first shows")
			check(ls.title.text == "BATTLE STARTS IN" and ls.count_lbl.text == "3 / 10 PLAYERS", "2. the countdown and the count (%s, %s)" % [ls.title.text, ls.count_lbl.text])
			# 3. Bea joins (flip), Ozzy leaves
			audio.played.clear()
			ls.update(_msg(["Mara", "Kevin", "Bea"], ["stormcaller", "knight", "duelist"], ["stormcaller_stormforged", "knight_lion", "golem_frost"], 1))
			phase = "change"
			t = 0.0
		"change":
			if t < 1.2:
				return false
			check(audio.played.has("flip"), "3. a flip for Bea joining")
			check(_fig_of("Ozzy").is_empty() and not ls.figs.values().any(func(f): return str(f.name) == "Ozzy"), "3. Ozzy left: his Golem gone")
			var bea := _fig_of("Bea")
			check(not bea.is_empty() and str(bea.hero) == "duelist" and str(bea.skin) == "", "3. Bea's Duelist -- the Golem's outfit sent with her isn't worn")
			# seven: two rows
			var names := ["Mara", "Kevin", "Bea", "Thorn", "Lux", "Grim", "Wynn"]
			ls.update(_msg(names, ["stormcaller", "knight", "duelist", "berserker", "druid", "necromancer", "nosuchhero"],
				["stormcaller_stormforged", "knight_lion", "", "", "druid_blossom", "", ""], 1))
			phase = "seven"
			t = 0.0
		"seven":
			if t < 1.8:
				return false
			var live := _live()
			check(live.size() == 7, "3. seven on the plaza (%d)" % live.size())
			var back := live.filter(func(f): return float((f.at as Vector3).z) < Loading.BACK_Z * 0.5)
			check(back.size() == 2 and back.all(func(f): return float((f.at as Vector3).y) > 0.5), "3. two in a second row behind, a step up (%d)" % back.size())
			check(str(_fig_of("Wynn").get("hero", "?")) == "" and bool(_fig_of("Wynn").get("unknown", false)), "3. a hero this app doesn't know: a shadow")
			check(not _fig_of("Lux").is_empty() and str(_fig_of("Lux").skin) == "druid_blossom", "3. Lux's Druid in Cherry Blossom")
			# 4. an older server: names only
			ls.free()
			ls = Loading.new()
			ls.audio = audio
			ls.my_hero = "mage"
			ls.my_name = "Kevin"
			root.add_child(ls)
			ls.update(_msg(["Kevin", "Mara", "Ozzy"], null, null, 0))
			phase = "old"
			t = 0.0
		"old":
			if t < 1.5:
				return false
			var live := _live()
			var me: Dictionary = ls.figs.get("me", {})
			check(live.size() == 3 and not me.is_empty() and str(me.hero) == "mage" and not bool(me.unknown), "4. an older server: you as your Mage")
			var others := live.filter(func(f): return not bool(f.me))
			check(others.size() == 2 and others.all(func(f): return bool(f.unknown) and str((f.plate_sub as Label).text) == "joining..."), "4. ...the others as shadows, joining...")
			# 5. loading
			ls.loading()
			check(ls.state == "loading" and not ls.leave_btn.visible and ls.leave_btn.disabled and ls.title.text == "PREPARING THE BATTLEFIELD" and ls.z_index == 100,
				"5. loading: PREPARING THE BATTLEFIELD, no LEAVE, over everything")
			ls.update(_msg(["Kevin"], ["mage"], [""], 0))
			check(_live().size() == 3 and ls.title.text == "PREPARING THE BATTLEFIELD", "5. a late lobby message changes nothing")
			ls.free()
			ls = null
			# 6. the match's loading card (offline, staged)
			OS.set_environment("FB_STAGED_START", "1")
			OS.set_environment("FB_FORCE_WARMUP", "1")
			mode = Mode.new()
			mode.moba_hero = "golem"
			mode.match_seed = 4402
			root.add_child(mode)
			phase = "match"
			t = 0.0
		"match":
			if t < 0.3:
				return false
			var cover = mode._cover
			check(cover != null and cover.get_script() == Loading and cover.state == "loading", "6. offline: the match's loading card is the loading screen")
			if cover != null and cover.get_script() == Loading:
				var mine: Array = (cover.figs as Dictionary).values().filter(func(f): return bool(f.me))
				check(mine.size() == 1 and str(mine[0].hero) == "golem", "6. ...your Golem on it")
			phase = "lift"
			t = 0.0
		"lift":
			if mode._cover != null and t < 30.0:
				return false
			check(mode._cover == null and mode.warmed(), "6. it lifts when the match is built and warmed (%.1f s)" % t)
			# online: at the welcome the lobby itself becomes the card (its heroes stay)
			var m2 = Mode.new()
			var lob = Loading.new()
			lob.my_hero = "druid"
			m2.lobby = lob
			m2.add_child(lob)
			m2._lobby_to_card()
			check(m2._cover == lob and m2.lobby == null and lob.state == "loading" and lob.z_index == 100,
				"6. online: at the welcome the lobby becomes the loading card")
			m2.free()
			_finish()
	return false

func _finish() -> void:
	if fails.is_empty():
		print("LOADING_SCREEN_PASS")
		quit(0)
	else:
		print("LOADING_SCREEN_FAIL ", fails)
		quit(1)
