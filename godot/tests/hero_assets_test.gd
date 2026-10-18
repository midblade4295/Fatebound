extends SceneTree
# 0.31.171 (step 3 of the plan: hero polish -- Kevin picked "Both, 2 takes"): every hero's four abilities have their
# painted icon (assets/ui/abilities/<hero>_<q|w|e|r>.png: the HUD's buttons, the hero window's kit) and their own sound
# (assets/sounds, tools/build_hero_sfx.py). A match's sound picker (siege_mode._event_sound) is fed each hero's
# events -- every Q, W and E spell, every ultimate, the new heroes' shots and hits, the shield raised, the whirlwind, a
# vanish, a leap's landing, the pillar's eruption, a trap snapping, the roots, a storm's bolt, a riposte, a flurry --
# and must play that ability's own cue, a file that exists.
#   godot --headless --path godot -s res://tests/hero_assets_test.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Hud = preload("res://scripts/siege/siege_hud.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const Kits = preload("res://scripts/siege/moba_kits.gd")
var mode
var rec: Node
var frames := 0
var fails := []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	# ---- the icons
	var bad := []
	for hid in Moba.HERO_ORDER:
		for slot in ["q", "w", "e", "r"]:
			var t: Texture2D = Hud.ability_icon(str(hid), slot)
			if t == null or t.get_width() != 192 or t.get_height() != 192:
				bad.append("%s_%s" % [hid, slot])
	check(Moba.HERO_ORDER.size() == 18 and bad.is_empty(), "every hero's Q, W, E and R has its icon (%d heroes) %s" % [Moba.HERO_ORDER.size(), str(bad)])
	check(Hud.ability_icon("", "q") == null and Hud.ability_icon("nobody", "q") == null, "no hero, no icon (the button's name instead)")
	# ---- every spell has its own sound
	var spells := []
	for hid in Moba.HERO_ORDER:
		for slot in ["q", "w", "e"]:
			var k: Dictionary = Kits.kit(str(hid), slot)
			if k.has("id") and str(k.id) != "block":         # (the Crusader's W is his shield, held: "block_up" below)
				spells.append(str(k.id))
	var no_cue := []
	var borrowed := []
	for sp in spells:
		if not Mode.SPELL_CUE.has(sp):
			no_cue.append(sp)
			continue
		var cue := str(Mode.SPELL_CUE[sp][0])
		# (FIRE PILLAR, ENTANGLE and RIPOSTE keep a light cast: their own sound is where they land)
		if not cue.begins_with("ab_") and sp not in ["pillar", "entangle", "riposte"]:
			borrowed.append(sp)
		var n := int(Mode.SPELL_CUE[sp][1])
		for i in n:
			var f := cue if n <= 1 else "%s%d" % [cue, i + 1]
			if not ResourceLoader.exists("res://assets/sounds/%s.wav" % f):
				no_cue.append(f)
	check(spells.size() >= 40 and no_cue.is_empty(), "every Q/W/E spell has a sound (%d spells) %s" % [spells.size(), str(no_cue)])
	check(borrowed.is_empty(), "each its own %s" % str(borrowed))
	var sc := GDScript.new()
	sc.source_code = "extends Node\nvar played := []\nvar muted := false\nvar levels := {\"master\":1.0, \"combat\":1.0, \"ui\":1.0}\nfunc play(cue: String, quiet := false, vol := 1.0) -> void:\n\tplayed.append(cue)\n"
	sc.reload()
	rec = Node.new()
	rec.set_script(sc)
	root.add_child(rec)
	mode = Mode.new()
	mode.audio = rec
	mode.moba_hero = "knight"
	root.add_child(mode)

func _heard(e: Dictionary) -> Array:
	rec.played.clear()
	mode._event_sound(e)
	return rec.played.duplicate()

func _as(me: Dictionary, hid: String) -> void:
	me.hid = hid
	if Moba.HERO_SHOT.has(hid):
		me["shot"] = str(Moba.HERO_SHOT[hid])
	else:
		me.erase("shot")

func _process(_d: float) -> bool:
	frames += 1
	if mode.sim == null or frames < 6:
		return false
	var me: Dictionary = mode.sim.by_id.get(str(mode.hud.player_id), {})
	if me.is_empty():
		check(false, "the player's hero")
		quit(1)
		return true
	var id := str(me.id)
	var at: Vector2 = me.pos
	var all_played := []
	# every ultimate
	var wrong := []
	for hid in Moba.HERO_ORDER:
		var h := _heard({"k":"ult", "ult":str(hid), "id":id, "pos":at})
		all_played.append_array(h)
		if h != ["ult_" + str(hid)]:
			wrong.append("%s: %s" % [hid, str(h)])
	check(wrong.is_empty(), "every ultimate plays its own sound %s" % str(wrong))
	# every spell
	wrong = []
	for sp in Mode.SPELL_CUE:
		var h := _heard({"k":"spell", "spell":str(sp), "id":id, "pos":at})
		all_played.append_array(h)
		if h.size() != 1 or not str(h[0]).begins_with(str(Mode.SPELL_CUE[sp][0])):
			wrong.append("%s: %s" % [sp, str(h)])
	check(wrong.is_empty(), "every spell plays its cue %s" % str(wrong))
	# the new heroes' shots and hits, the Golem's swing
	var want := {"musketeer":["atk_musket", "hit_musket"], "stormcaller":["atk_bolt", "hit_bolt"], "druid":["atk_thorn", "hit_thorn"],
		"golem":["atk_golem", "hit_golem"]}
	var keep_hid := str(me.hid)
	var keep_shot = me.get("shot", null)
	wrong = []
	for hid in want:
		_as(me, hid)
		var a := _heard({"k":"attack", "id":id, "kind":"attack", "ability":"", "combo":0})
		var foe := ""
		for u in mode.sim.units:
			if int(u.team) != int(me.team):
				foe = str(u.id)
				break
		var hh := _heard({"k":"hit", "id":foe, "by":id, "dmg":10})
		all_played.append_array(a + hh)
		if a != [want[hid][0]] or hh != [want[hid][1]]:
			wrong.append("%s: %s %s" % [hid, str(a), str(hh)])
	check(wrong.is_empty(), "the Musketeer's, Stormcaller's, Druid's and Golem's attacks and hits %s" % str(wrong))
	# the Sniper's PIERCE (an "ability" attack), the old heroes' swings unchanged
	_as(me, "sniper")
	var was_up = me.get("up", false)
	var was_cls := str(me.cls)
	me.cls = "ranger"
	me.up = true
	var p := _heard({"k":"attack", "id":id, "kind":"ability", "ability":"volley", "combo":0})
	_as(me, "ranger")
	me.up = false
	var v := _heard({"k":"attack", "id":id, "kind":"attack", "ability":"", "combo":0})
	check(p == ["ab_pierce"] and v.size() == 1 and str(v[0]).begins_with("tm_bow_shot"), "PIERCE %s; a Ranger's arrow %s" % [str(p), str(v)])
	all_played.append_array(p)
	me.cls = was_cls
	me.up = was_up
	# the rest of the kit's moments
	_as(me, "assassin")
	var fl := _heard({"k":"flurry_hit", "id":id, "target":id, "from":at, "pos":at})
	var va := _heard({"k":"vanish", "id":id, "team":me.team, "until":1.0})
	_as(me, "duelist")
	var ch := _heard({"k":"flurry_hit", "id":id, "target":id, "from":at, "pos":at})
	var fe := _heard({"k":"vanish", "id":id, "team":me.team, "until":1.0})
	check(fl.size() == 1 and str(fl[0]).begins_with("flurry") and va == ["ab_vanish"], "FLURRY's slashes %s, VANISH %s" % [str(fl), str(va)])
	check(ch == ["ab_thrust"] and fe.is_empty(), "GRAND CHALLENGE's thrusts %s; FEINT's vanish has its spell's sound %s" % [str(ch), str(fe)])
	_as(me, "barbarian")
	var l1 := _heard({"k":"slam", "id":id, "pos":at, "r":2.0})
	_as(me, "dragoon")
	var l2 := _heard({"k":"slam", "id":id, "pos":at, "r":2.0})
	check(l1 == ["ab_leap_land"] and l2 == ["ult_dragoon_land"], "LEAP and DRAGON DIVE land with their own %s %s" % [str(l1), str(l2)])
	var more := {
		"block_up": [{"k":"block_up", "id":id}, "ab_shield"],
		"whirl": [{"k":"whirl", "id":id}, "ab_whirl"],
		"pillar": [{"k":"pillar", "c":at, "r":2.5, "team":0}, "ab_pillar"],
		"trap_snap": [{"k":"trap_snap", "trap":1, "id":id, "pos":at}, "ab_trap_snap"],
		"roots": [{"k":"burst", "spell":"entangle", "c":at, "r":1.8, "team":0}, "ab_entangle"],
		"zap": [{"k":"zap", "c":at, "team":0, "id":id}, "hit_bolt"],
		"riposte": [{"k":"riposte", "id":id, "target":id, "pos":at}, "ab_riposte"],
	}
	wrong = []
	for what in more:
		var h := _heard(more[what][0])
		all_played.append_array(h)
		if h != [more[what][1]]:
			wrong.append("%s: %s" % [what, str(h)])
	check(wrong.is_empty(), "the shield raised, the whirlwind, the eruption, the trap, the roots, the storm's bolt, the riposte %s" % str(wrong))
	all_played.append_array(fl + va + ch + l1 + l2)
	me.hid = keep_hid
	if keep_shot != null:
		me["shot"] = keep_shot
	# every cue played: a file, short, mono
	var missing := []
	var odd := []
	for cue in all_played:
		var path := "res://assets/sounds/%s.wav" % cue
		if not ResourceLoader.exists(path):
			missing.append(cue)
			continue
		var st: AudioStreamWAV = load(path)
		if st.get_length() > 2.3 or st.stereo:
			odd.append("%s %.2f s%s" % [cue, st.get_length(), " stereo" if st.stereo else ""])
	check(all_played.size() > 70 and missing.is_empty(), "every cue played exists (%d plays) %s" % [all_played.size(), str(missing)])
	check(odd.is_empty(), "each a short mono sound %s" % str(odd))
	print("HERO_ASSETS_%s" % ("PASS" if fails.is_empty() else "FAIL %s" % str(fails)))
	quit(0 if fails.is_empty() else 1)
	return true
