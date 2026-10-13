extends SceneTree
# 0.31.124 (Kevin: "Add the discord link to the game" + "Also give a reward for joining the discord").
#  1. Profile.claim_discord: Eco.DISCORD_GEMS once; a second time refused; an op the server replays
#  2. the server's copy (eco_accounts): the op pays once per account, however often a phone sends it
#  3. the app: Settings > COMMUNITY -- JOIN OUR DISCORD (+100 GEMS) opens the invite and pays once; after that the
#     button just opens the invite
#   godot --headless --path godot -s res://tests/discord_test.gd
const Profile = preload("res://scripts/meta/profile.gd")
const Accounts = preload("res://server/eco_accounts.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const App = preload("res://scripts/app/siege_app.gd")

var fails: Array = []
var app
var frames := 0
var opened: Array = []
var g0 := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	check(Eco.DISCORD_URL == "https://discord.gg/H8eKXH8TmM", "the invite link")
	var p = Profile.new("user://discord-p-%d.json" % Time.get_ticks_usec(), "user://none.json")
	p.load_or_create()
	var g := int(p.d.gems)
	var r: Dictionary = p.claim_discord()
	check(bool(r.ok) and int(p.d.gems) == g + Eco.DISCORD_GEMS and bool(p.d.discord), "claimed: +%d gems" % Eco.DISCORD_GEMS)
	check(not bool(p.claim_discord().ok) and int(p.d.gems) == g + Eco.DISCORD_GEMS, "a second time: refused")
	check(Profile.OPS.has("claim_discord"), "an op the server replays")
	# the server's copy
	var tmp := OS.get_user_data_dir().path_join("discord-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var acc = Accounts.new(tmp)
	var a: Dictionary = acc.handle({"t":"eco", "new":true})
	var gs := int(acc._load(str(a.acct)).p.d.gems)
	var back: Dictionary = acc.handle({"t":"eco", "acct":str(a.acct), "key":str(a.key),
		"ops":[{"s":1, "op":"claim_discord", "a":[]}, {"s":2, "op":"claim_discord", "a":[]}]})
	check(bool(back.results[0].ok) and not bool(back.results[1].ok) and int(back.profile.gems) == gs + Eco.DISCORD_GEMS and bool(back.profile.discord),
		"the server pays it once per account (%d -> %d)" % [gs, int(back.profile.gems)])
	var again: Dictionary = acc.handle({"t":"eco", "acct":str(a.acct), "key":str(a.key), "ops":[{"s":3, "op":"claim_discord", "a":[]}]})
	check(not bool(again.results[0].ok) and int(again.profile.gems) == gs + Eco.DISCORD_GEMS, "...also when a phone sends it again later")
	# the app
	var base := "user://discord-app-%d" % Time.get_ticks_usec()
	var ap = Profile.new(base + "-profile.json", base + "-none.json")
	ap.load_or_create()
	ap.d.tutorial_done = true
	ap.save()
	app = App.new()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	root.add_child(app)
	app.open_url = func(u: String) -> int:
		opened.append(u)
		return OK

func _btn(key: String) -> Button:
	var b: Array = app.find_children("*", "Button", true, false).filter(func(x): return str(x.get_meta("action_key", "")) == key)
	return b[0] if not b.is_empty() else null

func _process(_d: float) -> bool:
	frames += 1
	if frames == 4:
		app.show_tab("settings")
	elif frames == 6:
		var b := _btn("discord")
		var card: Node = app.content.find_child("CommunityCard", true, false)
		var txt: Array = card.find_children("*", "Label", true, false).map(func(l): return str(l.text)) if card != null else []
		check(b != null and b.text == "JOIN OUR DISCORD  ·  +%d GEMS" % Eco.DISCORD_GEMS and txt.has("COMMUNITY")
			and txt.any(func(t): return t.contains("%d gems, once" % Eco.DISCORD_GEMS)), "Settings > COMMUNITY: JOIN OUR DISCORD, +%d GEMS" % Eco.DISCORD_GEMS)
		g0 = int(app.profile.d.gems)
		if b != null:
			b.pressed.emit()
	elif frames == 8:
		check(opened == [Eco.DISCORD_URL], "it opens the invite (%s)" % str(opened))
		check(int(app.profile.d.gems) == g0 + Eco.DISCORD_GEMS and bool(app.profile.d.discord), "...and pays %d gems" % Eco.DISCORD_GEMS)
		var b := _btn("discord")
		check(b != null and b.text == "JOIN OUR DISCORD", "after that: just JOIN OUR DISCORD")
		if b != null:
			b.pressed.emit()
	elif frames == 10:
		check(opened.size() == 2 and int(app.profile.d.gems) == g0 + Eco.DISCORD_GEMS, "pressed again: opens the invite, nothing more paid")
		print("DISCORD_PASS" if fails.is_empty() else "DISCORD_FAIL %s" % str(fails))
		quit(0 if fails.is_empty() else 1)
	return false
