extends Node
# 0.31.130 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §4): Game Center sign-in and achievements, with the same face as
# play_games.gd (Google Play Games) so the app and Settings talk to either (scripts/meta/game_services.gd picks one).
# The native side is GodotApplePlugins' GameCenterManager (addons/GodotApplePluginsGameCenter, a GDExtension in the iOS
# build only), wrapped by Native below; tests hand setup() a double with Native's calls and signals.
#
# Signing in: Apple signs the player in by itself at start (its own banner, or its sheet the first time). There is no
# in-app sign-in once a player has declined -- Apple's rule -- so Settings says where: iOS Settings > Game Center.
# Achievements: the 18 of achievements.gd with Apple's ids (gc_achievement_ids.gd), as percentages (Apple has no
# incremental kind), checked every ACH_EVERY s while signed in; only what changed is reported (GameKit itself keeps a
# report made offline and sends it later).
# The progress: iOS v1 keeps no cloud copy (no GameKit saved games): the server account holds it, moved with a transfer
# code, and Game Center's teamPlayerID links the account so a reinstall gets it back (signed -> the app). So `ask` and
# `restored` exist only for the same face and are never emitted.
const Achievements = preload("res://scripts/meta/achievements.gd")
const GcIds = preload("res://scripts/meta/gc_achievement_ids.gd")
const Platform = preload("res://scripts/meta/platform.gd")
const ACH_EVERY := 5.0                 # s between looks at the achievements (only what changed is sent)

signal changed                        # state / name changed: Settings redraws
signal note(text: String, good: bool)
signal ask(here: Dictionary, cloud: Dictionary)    # (never: no cloud copy on iOS v1)
signal restored                       # (never)
signal signed(team_player_id: String)  # signed in to Game Center: the app links the server account to this player

var profile                           # Profile
var plugin = null                     # Native, or a test double with the same calls and signals
var state := "off"                    # off | out | signing | synced  (play_games.gd's names; "synced" = signed in)
var player := ""                      # the Game Center alias
var team_id := ""                     # teamPlayerID (stays on the phone; the server keeps only a hash of it)
var why := ""                         # the last error (diagnostics; Settings shows where to sign in instead)
var achievements = Achievements.new()
var reported := 0                     # achievements reported this run (diagnostics, tests)
var _ach_clock := 0.0
var _manual := false

# GodotApplePlugins' Game Center classes, reached through ClassDB (the names don't exist outside the iOS build)
class Native extends RefCounted:
	signal authenticated(ok: bool)
	signal failed(msg: String)
	var gc: Object = null

	func _init() -> void:
		gc = ClassDB.instantiate("GameCenterManager")
		gc.authentication_result.connect(func(ok): authenticated.emit(bool(ok)))
		gc.authentication_error.connect(func(m): failed.emit(str(m)))

	func authenticate() -> void:
		gc.authenticate()

	func _local() -> Object:
		return gc.get("local_player") if gc != null else null

	func player_alias() -> String:
		var lp := _local()
		return str(lp.get("alias")) if lp != null else ""

	func team_player_id() -> String:
		var lp := _local()
		return str(lp.get("team_player_id")) if lp != null else ""

	func report(list: Array, cb: Callable) -> void:
		# list: [[id, percent], ...] -> one GKAchievement.report_achievement; cb(error or null)
		var arr := []
		for it in list:
			var a: Object = ClassDB.class_call_static(&"GKAchievement", &"make", str(it[0]))
			if a == null:
				continue
			a.set("percent_complete", float(it[1]))
			a.set("shows_completion_banner", true)
			arr.append(a)
		if not arr.is_empty():
			ClassDB.class_call_static(&"GKAchievement", &"report_achievement", arr, cb)

	func show_achievements() -> void:
		ClassDB.class_call_static(&"GKGameCenterViewController", &"show_type", 2)   # State.ACHIEVEMENTS

	func identity(cb: Callable) -> void:
		# Apple's identity signature (cb(data: Dictionary {url, data, salt, timestamp}, error)): the server checks it
		var lp := _local()
		if lp != null:
			# (GameKit may answer off the main thread: the game hears it on the main one)
			lp.call("fetch_items_for_identity_verification_signature", func(d, e): cb.call_deferred(d, e))

static func supported() -> bool:
	return Platform.has_class(Platform.GAMECENTER_CLASS)

func setup(p, plug = null) -> void:
	profile = p
	plugin = plug
	if plugin == null and supported():
		plugin = Native.new()
	if plugin == null:
		return
	achievements.ids = GcIds.IDS
	plugin.authenticated.connect(_on_auth)
	plugin.failed.connect(func(m: String): why = m)
	_state("signing")
	plugin.authenticate()

func active() -> bool:
	return plugin != null

func last_backup() -> int:
	return 0                                          # (no cloud copy on iOS v1)

# ---------------- the player's buttons (play_games.gd's face) ----------------
func sign_in() -> void:
	# Apple shows its sheet again only while it still allows it; otherwise iOS Settings > Game Center
	if plugin == null or state == "signing":
		return
	_manual = true
	_state("signing")
	plugin.authenticate()

func back_up_now() -> void:
	if state == "out":
		sign_in()

func choose(_keep_cloud: bool) -> void:
	pass

func pending_choice() -> Dictionary:
	return {}

func on_pause() -> void:
	pass

func on_resume() -> void:
	# back from iOS Settings: signed in there? (GameKit tells the handler too; asking again is harmless)
	if plugin != null and state == "out":
		plugin.authenticate()

func signed_in() -> bool:
	return plugin != null and state == "synced"

func show_achievements() -> void:
	# Apple's own achievements screen
	if signed_in():
		plugin.show_achievements()

func identity(cb: Callable) -> void:
	if signed_in():
		plugin.identity(cb)

func _process(delta: float) -> void:
	if plugin == null:
		return
	_ach_clock += delta
	if _ach_clock >= ACH_EVERY:
		_ach_clock = 0.0
		if signed_in():
			sync_achievements()

func sync_achievements() -> int:
	var list := []
	achievements.sync_percent(profile, func(id: String, pct: float): list.append([id, pct]))
	if not list.is_empty():
		reported += list.size()
		plugin.report(list, func(err) -> void:
			if err != null:
				print("game_center: report: %s" % str(err)))
	return list.size()

# ---------------- Apple's answers ----------------
func _on_auth(ok: bool) -> void:
	if not ok:
		state = "out"
		player = ""
		if _manual:
			note.emit("Sign in from iOS Settings > Game Center", false)
		_manual = false
		changed.emit()
		return
	player = str(plugin.player_alias())
	team_id = str(plugin.team_player_id())
	why = ""
	var was := state
	_state("synced")
	if _manual:
		note.emit("Signed in to Game Center", true)
	_manual = false
	if was != "synced" and team_id != "":
		signed.emit(team_id)

func _state(s: String) -> void:
	state = s
	changed.emit()
