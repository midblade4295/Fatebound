extends RefCounted
# 0.31.120 (Kevin: referral codes): a new player enters a friend's code (the friend code from Friends, social.gd's pid)
# within REF_DAYS of making their account and before level REF_LEVEL; when they reach level REF_LEVEL the server gives
# them and the friend a Gold chest each (Profile.grant_referral -- never a phone op). A friend is rewarded for at most
# REF_MAX new players. Kept in referrals.json in the state directory:
#   {"by": {new acct: friend acct}, "paid": {new acct: true}, "count": {friend acct: n rewarded}}
# A phone asks on its own socket: {"t":"ref", "acct", "key", "code"} -> {"t":"ref", "ok", "why", "name"} (why:
# "code" (no such player), "self", "late" (too old an account / level), "done" (already entered one), "loop" (that
# friend entered yours)).
const Eco = preload("res://scripts/meta/economy.gd")
const REF_DAYS := Eco.REF_DAYS
const REF_LEVEL := Eco.REF_LEVEL
const REF_MAX := Eco.REF_MAX

var path := ""
var by := {}
var paid := {}
var count := {}
var log_fn: Callable = func(_s): pass

func _init(state_dir := "") -> void:
	var state := state_dir
	if state == "":
		state = OS.get_environment("STATE_DIRECTORY") if OS.has_environment("STATE_DIRECTORY") else "user://"
	path = state.path_join("referrals.json")
	if FileAccess.file_exists(path):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if v is Dictionary:
			by = v.get("by", {}) if v.get("by", {}) is Dictionary else {}
			paid = v.get("paid", {}) if v.get("paid", {}) is Dictionary else {}
			count = v.get("count", {}) if v.get("count", {}) is Dictionary else {}

func _save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"by":by, "paid":paid, "count":count}))
		f.close()

func claim(acct: String, key: String, code: String, eco, social) -> Dictionary:
	var e: Dictionary = eco.open(acct, key) if eco != null else {}
	if e.is_empty():
		return {"t":"ref", "ok":false, "why":"auth"}
	code = code.strip_edges().replace("#", "").replace(" ", "").to_lower()
	if social == null or not social.users.has(code):
		return {"t":"ref", "ok":false, "why":"code"}
	var friend := str(social.users[code].acct)
	if friend == acct:
		return {"t":"ref", "ok":false, "why":"self"}
	if by.has(acct):
		return {"t":"ref", "ok":false, "why":"done"}
	if str(by.get(friend, "")) == acct:
		return {"t":"ref", "ok":false, "why":"loop"}
	var created := int(e.meta.get("created", 0))
	if eco.now() - created > REF_DAYS * 86400 or int(e.p.d.get("level", 1)) >= REF_LEVEL:
		return {"t":"ref", "ok":false, "why":"late"}
	by[acct] = friend
	_save()
	var name := str(social.users[code].get("name", "a friend"))
	e.p.replaying = true
	e.p.d.referral["by"] = name
	e.p.save()
	e.p.replaying = false
	e.meta.rev = int(e.meta.get("rev", 0)) + 1
	eco._save_meta(e)
	log_fn.call("referral: %s entered %s's code" % [acct, friend])
	return {"t":"ref", "ok":true, "name":name}

func check(acct: String, eco) -> int:
	# after the account changed (a match, ops): the rewards once it's reached REF_LEVEL -> chests given
	if not by.has(acct) or paid.has(acct) or eco == null:
		return 0
	var e: Dictionary = eco._load(acct)
	if e.is_empty() or int(e.p.d.get("level", 1)) < REF_LEVEL:
		return 0
	paid[acct] = true
	var friend := str(by[acct])
	var n := 0
	var fe: Dictionary = eco._load(friend)
	var new_name := str(e.p.d.get("name", "Player"))
	var friend_name := str(fe.p.d.get("name", "your friend")) if not fe.is_empty() else "your friend"
	if eco.grant_referral(acct, "joined", friend_name):
		n += 1
	if int(count.get(friend, 0)) < REF_MAX and eco.grant_referral(friend, "friend", new_name):
		count[friend] = int(count.get(friend, 0)) + 1
		n += 1
	_save()
	log_fn.call("referral: %s reached level %d -- %d gold chest(s)" % [acct, REF_LEVEL, n])
	return n
