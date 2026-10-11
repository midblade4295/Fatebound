extends SceneTree
# Google Play Games sign-in and the progress kept in the Google account (0.31.102, Kevin: "Google play account linking
# to the game"), against a fake of the plugin's singleton (same calls and signals; it answers at once, or not at all):
# the first link uploads, changes go up later, a new install takes Google Play's copy, a phone in step takes a newer
# copy, two different progresses make the player choose (both answers), nothing is overwritten that couldn't be read
# or that a newer version wrote, a silent Google gives an error and TRY AGAIN, and Settings shows each state.
#   godot --headless --path godot -s res://tests/play_games_test.gd
const Profile = preload("res://scripts/meta/profile.gd")
const PlayGames = preload("res://scripts/meta/play_games.gd")
const App = preload("res://scripts/app/siege_app.gd")
var fails: Array = []
var app
var frames := 0
var step := 0
var fake_app

class FakePlay extends Node:
	signal userAuthenticated(ok: bool)
	signal currentPlayerLoaded(json: String)
	signal gameLoaded(json: String)
	signal gameSaved(ok: bool, name: String, desc: String)
	signal conflictEmitted(json: String)
	var signed := false                 # the phone's Play Games account is signed in
	var cloud = null                    # the saved game's bytes (shared between "phones" through `store`)
	var store: Dictionary = {}          # {"bytes": PackedByteArray} -- one Google account
	var silent := false                 # Google never answers
	var saves := 0
	func initialize() -> void:
		pass
	func isAuthenticated() -> void:
		if not silent:
			userAuthenticated.emit(signed)
	func signIn() -> void:
		signed = true
		userAuthenticated.emit(true)
	func loadCurrentPlayer(_force: bool) -> void:
		currentPlayerLoaded.emit(JSON.stringify({"displayName":"Midblade", "playerId":"g123"}))
	func loadGame(_name: String, _create: bool) -> void:
		if silent:
			return
		if not store.has("bytes"):
			gameLoaded.emit("null")
		else:
			gameLoaded.emit(JSON.stringify({"content":Array(store.bytes as PackedByteArray), "metadata":{"uniqueName":_name}}))
	func saveGame(name: String, desc: String, bytes: PackedByteArray, _t: int, _p: int) -> void:
		if silent:
			return
		saves += 1
		store["bytes"] = bytes
		gameSaved.emit(true, name, desc)

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func phone(tag: String) -> Profile:
	var p := Profile.new("user://pg_%s_%d.json" % [tag, Time.get_ticks_usec()], "user://none_%d.json" % Time.get_ticks_usec())
	p.load_or_create()
	return p

func linked(p: Profile, store: Dictionary, signed := true) -> Array:
	var f := FakePlay.new()
	f.store = store
	f.signed = signed
	var pg = PlayGames.new()
	root.add_child(f)
	root.add_child(pg)
	var log := {"ask":0, "restored":0, "notes":[]}
	pg.ask.connect(func(_h, _c): log.ask += 1)
	pg.restored.connect(func(): log.restored += 1)
	pg.note.connect(func(t, good): log.notes.append([t, good]))
	pg.setup(p, f)
	return [pg, f, log]

func cloud_of(store: Dictionary) -> Dictionary:
	return PlayGames.decode(store.get("bytes", PackedByteArray()))

func _init() -> void:
	# ---- the copy's format
	var p0 := phone("fmt")
	p0.d.name = "Mïdblade ⚔"
	var enc := PlayGames.encode(p0.cloud_payload("s1", "Pixel"))
	var dec := PlayGames.decode(Array(enc))
	check(str(dec.get("stamp", "")) == "s1" and str(dec.profile.name) == "Mïdblade ⚔" and not dec.profile.has("cloud") and str(dec.device) == "Pixel",
		"the copy round-trips through the plugin's JSON bytes (stamp, name, no cloud block)")
	var ascii := true
	for b in enc:
		ascii = ascii and b < 128
	check(ascii and PlayGames.decode([1, 2, 3]).is_empty() and PlayGames.decode("x").is_empty(), "ASCII on the wire; junk decodes to nothing")
	# ---- phone A: not signed in, then SIGN IN -> the first link uploads
	var account := {}
	var a := phone("a")
	a.d.gold = 1234
	a.d.stats.matches = 9
	a.save()
	var la := linked(a, account, false)
	var pga = la[0]
	check(pga.state == "out", "not signed in at start: out (%s)" % pga.state)
	pga.sign_in()
	var c1 := cloud_of(account)
	check(pga.state == "synced" and str(pga.player) == "Midblade" and int(c1.profile.gold) == 1234, "SIGN IN: named, and the first link uploads this phone's progress")
	check(str(a.d.cloud.stamp) == str(c1.stamp) and not bool(a.d.cloud.dirty) and int(a.d.cloud.at) > 0, "the profile is in step with the copy")
	# ---- a change goes up later, not at once
	var saves0: int = la[1].saves
	a.d.gold = 1500
	a.save()
	check(bool(a.d.cloud.dirty) and la[1].saves == saves0, "a change marks it, nothing uploaded yet")
	pga._process(PlayGames.UPLOAD_EVERY + 1.0)
	check(la[1].saves == saves0 + 1 and int(cloud_of(account).profile.gold) == 1500 and not bool(a.d.cloud.dirty), "after a while it goes up")
	# ---- a change during an upload stays marked
	pga._up_saves = a.saves - 1
	pga._ask_google("save")
	pga._on_saved(true, "", "")
	check(bool(a.d.cloud.dirty), "a save during the upload: still marked")
	# ---- phone B, a new install: takes Google Play's copy silently, keeps its own settings
	var b := phone("b")
	b.d.settings.music = 0.1
	var lb := linked(b, account)
	check(lb[0].state == "synced" and int(b.d.gold) == 1500 and lb[2].restored == 1 and lb[2].ask == 0, "a new install takes Google Play's progress without asking")
	check(is_equal_approx(float(b.d.settings.music), 0.1) and str(b.d.cloud.stamp) == str(cloud_of(account).stamp), "... keeping its own sound settings")
	# ---- B plays and uploads; A (in step, unchanged since) takes it on its next check
	b.d.gems = 77
	b.save()
	lb[0].back_up_now()
	a.d.cloud.dirty = false
	pga._check()
	check(int(a.d.gems) == 77 and pga.state == "synced" and la[2].ask == 0, "a phone in step takes a newer copy from another phone")
	# ---- both changed: the player chooses
	b.d.gems = 200
	b.save()
	lb[0].back_up_now()
	a.d.gold = 9999
	a.save()
	pga._check()
	check(pga.state == "ask" and la[2].ask == 1 and int(a.d.gold) == 9999, "both changed: asked, nothing replaced yet")
	var q: Dictionary = pga.pending_choice()
	check(int(q.here.gold) == 9999 and int(q.cloud.gems) == 200, "the question shows both sides")
	pga.choose(false)
	check(pga.state == "synced" and int(cloud_of(account).profile.gold) == 9999, "KEEP THIS PHONE'S: this phone's goes up")
	lb[0]._check()                       # B was in step and unchanged: it now takes A's
	check(int(b.d.gold) == 9999, "and the other phone follows")
	# ... and USE GOOGLE PLAY'S
	var c := phone("c")
	c.d.stats.matches = 3
	c.d.gold = 5
	c.save()
	var lc := linked(c, account)
	check(lc[0].state == "ask", "a second phone with its own progress is asked")
	lc[0].choose(true)
	check(int(c.d.gold) == 9999 and lc[2].restored == 1 and lc[0].state == "synced", "USE GOOGLE PLAY'S replaces this phone's")
	# ---- never overwrite what can't be read, or what a newer version wrote
	var junk := {"bytes":"garbage".to_ascii_buffer()}
	var d := phone("d")
	d.d.stats.matches = 2
	d.save()
	var ld := linked(d, junk)
	check(ld[0].state == "error" and ld[1].saves == 0 and str(junk.bytes.get_string_from_ascii()) == "garbage", "an unreadable copy: error, never overwritten")
	var newer_payload := d.cloud_payload("future", "")
	newer_payload["v"] = 99
	var newer := {"bytes":PlayGames.encode(newer_payload)}
	var e := phone("e")
	var le := linked(e, newer)
	check(le[0].state == "error" and le[1].saves == 0 and str(le[0].why).contains("newer"), "a copy from a newer version: left alone, 'update the game'")
	# ---- Google silent: an error after the wait, TRY AGAIN reads again
	var f_acc := {}
	var g := phone("g")
	var lg := linked(g, f_acc)
	lg[1].silent = true
	lg[0]._check()
	lg[0]._process(PlayGames.WAIT + 1.0)
	check(lg[0].state == "error" and (lg[2].notes as Array).is_empty() and str(lg[0].why) != "", "no answer: an error for Settings, no toast on its own")
	lg[0].back_up_now()
	lg[0]._process(PlayGames.WAIT + 1.0)
	check(not (lg[2].notes as Array).is_empty(), "... and a toast when the player pressed TRY AGAIN")
	lg[1].silent = false
	lg[0].back_up_now()
	check(lg[0].state == "synced" and f_acc.has("bytes"), "TRY AGAIN reads first, then links")
	# ---- off Play: nothing
	var off = PlayGames.new()
	root.add_child(off)
	off.setup(phone("off"))
	check(not off.active() and off.state == "off", "without the plugin: off")
	# ---- the screens
	var base := "user://pg_ui-%d" % Time.get_ticks_usec()
	app = App.new()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	app.now_override = 1791000000
	root.add_child(app)

func _live(n: Node) -> bool:
	while n != null:
		if n.is_queued_for_deletion():
			return false
		n = n.get_parent()
	return true

func btn(key: String) -> Button:
	for c in root.find_children("*", "Button", true, false):
		if str(c.get_meta("action_key", "")) == key and (c as Control).is_visible_in_tree() and _live(c):
			return c
	return null

func texts() -> String:
	var out := ""
	for l in app.content.find_children("*", "Label", true, false):
		if _live(l):
			out += (l as Label).text + "\n"
	return out

func _process(_d: float) -> bool:
	frames += 1
	if frames < 8:
		return false
	match step:
		0:
			app.show_tab("settings")
		1:
			check(texts().contains("Available in the Google Play version") and btn("play_sign_in") == null, "Settings off Play: says where it works, no button")
			fake_app = FakePlay.new()
			fake_app.signed = false
			root.add_child(fake_app)
			app.play_games.setup(app.profile, fake_app)
		2:
			check(btn("play_sign_in") != null and texts().contains("Not signed in"), "Settings: SIGN IN WITH GOOGLE PLAY")
			btn("play_sign_in").pressed.emit()
		3:
			check(app.play_games.state == "synced" and btn("play_backup") != null and texts().contains("as Midblade"), "signed in: named, BACK UP NOW")
			# another phone wrote different progress; this one changed too -> the question
			var other := Profile.new("user://pg_other_%d.json" % Time.get_ticks_usec(), "user://none.json")
			other.load_or_create()
			other.d.gold = 4321
			other.d.stats.matches = 50
			fake_app.store["bytes"] = PlayGames.encode(other.cloud_payload("other-1", "Galaxy S21 Ultra"))
			app.profile.d.gold = 7
			app.profile.save()
			app.play_games._check()
		4:
			check(app.play_games.state == "ask" and btn("cloud_use") != null and btn("cloud_keep") != null, "the question: USE GOOGLE PLAY'S / KEEP THIS PHONE'S")
			btn("cloud_use").pressed.emit()
		5:
			check(int(app.profile.d.gold) == 4321 and app.play_games.state == "synced", "USE GOOGLE PLAY'S from the screen: restored")
			print("PLAY_GAMES_PASS" if fails.is_empty() else "PLAY_GAMES_FAIL %s" % str(fails))
			quit(0 if fails.is_empty() else 1)
	step += 1
	return false
