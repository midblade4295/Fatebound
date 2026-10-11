extends Node
# 0.31.102: Google Play Games sign-in and the progress kept in the player's Google account (Kevin: "Google play account
# linking to the game"). Only the Play app has the plugin (addons/GodotPlayGameServices, packed by the Gradle preset
# once the Play Games project's Game ID is set); everywhere else `active()` is false and Settings says so.
#
# Signing in: Play Games v2 signs the player in by itself at start when they have Play Games (isAuthenticated); SIGN
# IN in Settings asks Google to (signIn). There is no sign-out in Play Games v2 (the Play Games app owns that).
#
# The copy (one Saved Game, SLOT): the profile as JSON, gzipped and base64'd (ASCII, so the plugin's JSON hands the
# bytes back intact), with a stamp, the time, the phone and a summary. The profile remembers the stamp of the copy it
# is in step with and whether it changed since (Profile.save marks it). Signed in, the game reads the copy first and
# never writes before it has:
#   - no copy yet                          -> this phone's progress goes up (the first link)
#   - the copy is the one we're in step with -> ours goes up when it has changed
#   - another phone wrote since, and this one hasn't changed (or is a new install, never linked) -> Google Play's
#     replaces ours
#   - both changed (or a second phone with its own progress links the account) -> the player chooses (ask):
#     USE GOOGLE PLAY'S or KEEP THIS PHONE'S (which then goes up). Nothing is ever replaced without that choice.
# Then ours goes up at most every UPLOAD_EVERY s while it changes, when the app goes to the background, and on BACK UP
# NOW. A copy written by a newer version of the game (v > CLOUD_VERSION) is never overwritten or read.
const Profile = preload("res://scripts/meta/profile.gd")
const PLUGIN := "GodotPlayGameServices"
const SLOT := "fatebound-profile"
const MAGIC := "FB1:"
const WAIT := 30.0                    # s for Google to answer before we call it unreachable
const UPLOAD_EVERY := 120.0           # s between uploads while the progress keeps changing

signal changed                        # state / name / last backup changed: Settings redraws
signal note(text: String, good: bool)
signal ask(here: Dictionary, cloud: Dictionary)    # both sides have progress: the app asks which to keep
signal restored                       # Google Play's copy replaced this phone's: the app rebuilds its screens

var profile                           # Profile
var plugin = null                     # the Android singleton, or a test double with the same calls and signals
var device := ""                      # this phone's model, written into the copy
var state := "off"                    # off | out | signing | checking | synced | ask | error
var player := ""                      # the Play Games name
var why := ""                         # the last error, for Settings
var _cloud := {}                      # Google Play's copy while the player chooses
var _wait := ""                       # what Google owes us: "sign" | "load" | "save"
var _wait_t := 0.0
var _since := 0.0                     # s since the last upload started
var _up_stamp := ""                   # the stamp of the upload in flight
var _up_saves := 0                    # profile.saves when it started
var _manual := false                  # the player pressed SIGN IN / BACK UP NOW (say how it went)

static func supported() -> bool:
	return Engine.has_singleton(PLUGIN)

func setup(p, plug = null) -> void:
	profile = p
	plugin = plug
	if plugin == null and supported():
		plugin = Engine.get_singleton(PLUGIN)
		plugin.initialize()
	if plugin == null:
		return
	device = OS.get_model_name()
	plugin.userAuthenticated.connect(_on_auth)
	plugin.currentPlayerLoaded.connect(_on_player)
	plugin.gameLoaded.connect(_on_loaded)
	plugin.gameSaved.connect(_on_saved)
	plugin.conflictEmitted.connect(_on_conflict)
	_state("signing")
	_ask_google("sign")
	plugin.isAuthenticated()

func active() -> bool:
	return plugin != null

func last_backup() -> int:
	return int(profile.d.cloud.get("at", 0)) if profile != null else 0

# ---------------- the player's buttons ----------------
func sign_in() -> void:
	if plugin == null or state in ["signing", "checking"]:
		return
	_manual = true
	_state("signing")
	_ask_google("sign")
	plugin.signIn()

func back_up_now() -> void:
	if plugin == null or _wait != "":
		return
	_manual = true
	if state == "synced":
		_upload()
	elif state == "error":
		_check()                           # read the copy again first: never write blind
	elif state == "out":
		sign_in()

func choose(keep_cloud: bool) -> void:
	# the answer to `ask`
	if state != "ask" or _cloud.is_empty():
		return
	var c := _cloud
	_cloud = {}
	if keep_cloud:
		_restore(c)
	else:
		_state("checking")
		_upload()

func pending_choice() -> Dictionary:
	# Settings' CHOOSE re-opens the question
	return {"here":profile.summary(), "cloud":_cloud_side(_cloud)} if state == "ask" else {}

func on_pause() -> void:
	if state == "synced" and bool(profile.d.cloud.dirty) and _wait == "":
		_upload()

func on_resume() -> void:
	if state == "error" and _wait == "":
		_check()

func _process(delta: float) -> void:
	if plugin == null:
		return
	_since += delta
	if _wait != "":
		_wait_t += delta
		if _wait_t > WAIT:
			var what := _wait
			_wait = ""
			if what == "sign":
				_fail("out", "Google Play didn't answer")
			else:
				_fail("error", "Google Play saves didn't answer")
		return
	if state == "synced" and bool(profile.d.cloud.dirty) and _since > UPLOAD_EVERY:
		_upload()

# ---------------- Google's answers ----------------
func _on_auth(ok: bool) -> void:
	if _wait == "sign":
		_wait = ""
	if not ok:
		_fail("out", "Not signed in to Google Play" if _manual else "")
		return
	plugin.loadCurrentPlayer(false)
	_check()

func _on_player(json: String) -> void:
	var v: Variant = JSON.parse_string(json)
	if v is Dictionary:
		player = str((v as Dictionary).get("displayName", ""))
		changed.emit()

func _check() -> void:
	_state("checking")
	_ask_google("load")
	plugin.loadGame(SLOT, false)

func _on_loaded(json: String) -> void:
	if _wait != "load":
		return
	_wait = ""
	var v: Variant = JSON.parse_string(json)
	if v == null:
		_upload()                         # no copy yet: the first link
		return
	var c := decode(v.get("content", []) if v is Dictionary else [])
	if c.is_empty():
		_fail("error", "The Google Play save couldn't be read")
		return
	if int(c.get("v", 0)) > Profile.CLOUD_VERSION:
		_fail("error", "Your Google Play save is from a newer version: update the game")
		return
	_decide(c)

func _decide(c: Dictionary) -> void:
	var here: Dictionary = profile.d.cloud
	if str(c.get("stamp", "")) == str(here.stamp):
		_state("synced")
		if bool(here.dirty):
			_upload()
		else:
			_done_manual("Your progress is backed up to Google Play")
		return
	if (str(here.stamp) != "" and not bool(here.dirty)) or (str(here.stamp) == "" and profile.is_fresh()):
		_restore(c)
		return
	_cloud = c
	_state("ask")
	ask.emit(profile.summary(), _cloud_side(c))

func _restore(c: Dictionary) -> void:
	if profile.restore_cloud(c.get("profile"), str(c.get("stamp", ""))):
		_state("synced")
		note.emit("Progress restored from Google Play", true)
		restored.emit()
	else:
		_fail("error", "The Google Play save couldn't be read")

func _upload() -> void:
	_up_stamp = "%d-%06d" % [profile.now(), randi() % 1000000]
	_up_saves = int(profile.saves)
	_since = 0.0
	var s: Dictionary = profile.summary()
	var desc := "Level %d · %d wins" % [int(s.level), int(s.wins)]
	_ask_google("save")
	plugin.saveGame(SLOT, desc, encode(profile.cloud_payload(_up_stamp, device)), 0, profile.now())

func _on_saved(ok: bool, _name: String, _desc: String) -> void:
	if _wait != "save":
		return
	_wait = ""
	if not ok:
		_fail("error", "Google Play couldn't save")
		return
	profile.d.cloud = {"stamp":_up_stamp, "dirty":int(profile.saves) != _up_saves, "at":profile.now()}
	profile.save(false)
	_state("synced")
	_done_manual("Backed up to Google Play")

func _on_conflict(_json: String) -> void:
	# two phones wrote at once: Google keeps the newest (the policy); read it again before writing anything
	if _wait in ["load", "save"]:
		_wait = ""
		_check()

# ---------------- helpers ----------------
func _ask_google(what: String) -> void:
	_wait = what
	_wait_t = 0.0

func _state(s: String) -> void:
	state = s
	if s != "error" and s != "out":
		why = ""
	changed.emit()

func _fail(s: String, text: String) -> void:
	state = s
	why = text
	if text != "" and _manual:              # (on its own -- at start, offline -- it only shows in Settings)
		note.emit(text, false)
	_manual = false
	changed.emit()

func _done_manual(text: String) -> void:
	if _manual:
		note.emit(text, true)
	_manual = false

static func _cloud_side(c: Dictionary) -> Dictionary:
	var out: Dictionary = (c.get("sum", {}) as Dictionary).duplicate() if c.get("sum", {}) is Dictionary else {}
	out["device"] = str(c.get("device", ""))
	out["at"] = int(c.get("at", 0))
	return out

static func encode(payload: Dictionary) -> PackedByteArray:
	var raw := JSON.stringify(payload).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	return (MAGIC + Marshalls.raw_to_base64(raw)).to_ascii_buffer()

static func decode(content: Variant) -> Dictionary:
	# the bytes as the plugin's JSON gives them (an array of numbers), or a PackedByteArray
	var bytes := PackedByteArray()
	if content is PackedByteArray:
		bytes = content
	elif content is Array:
		for x in content:
			bytes.append(int(x) & 0xff)
	var txt := bytes.get_string_from_ascii()
	if not txt.begins_with(MAGIC):
		return {}
	var raw := Marshalls.base64_to_raw(txt.substr(MAGIC.length()))
	if raw.is_empty():
		return {}
	var json := raw.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()
	var v: Variant = JSON.parse_string(json)
	return v if v is Dictionary and (v as Dictionary).has("profile") else {}
