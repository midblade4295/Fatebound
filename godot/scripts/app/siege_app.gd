extends Control
# Fatebound Siege app shell (replaces the dice-era full_client). Owns the profile, the chrome
# (top bar + tab bar), the five screens (scripts/app/screens.gd) and launching matches.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const Roster = preload("res://scripts/app/roster.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const StoreBilling = preload("res://scripts/meta/store_billing.gd")     # 0.31.130: billing.gd (Play) or billing_ios.gd
const GameServices = preload("res://scripts/meta/game_services.gd")     # 0.31.130: play_games.gd or game_center.gd
const EcoSync = preload("res://scripts/meta/eco_sync.gd")
const Screens = preload("res://scripts/app/screens.gd")
const Showcase = preload("res://scripts/app/showcase.gd")
const Siege = preload("res://scripts/siege/siege_mode.gd")
const Audio = preload("res://scripts/native_audio.gd")
const Assets = preload("res://scripts/siege/asset_cache.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const UpdateScreen = preload("res://scripts/app/update_screen.gd")
const VersionCheck = preload("res://scripts/app/version_check.gd")
const OnlineStatus = preload("res://scripts/app/online_status.gd")
const RewardFly = preload("res://scripts/app/reward_fly.gd")
const Social = preload("res://scripts/meta/social.gd")
const ChatPanel = preload("res://scripts/app/chat_panel.gd")
const FriendsPanel = preload("res://scripts/app/friends_panel.gd")
const ChatTicker = preload("res://scripts/app/chat_ticker.gd")
const InviteBanner = preload("res://scripts/app/invite_banner.gd")
const OrdersPanel = preload("res://scripts/app/orders_panel.gd")
const LeaderboardPanel = preload("res://scripts/app/leaderboard_panel.gd")
const DailyReward = preload("res://scripts/app/daily_reward.gd")
const SocialUI = preload("res://scripts/app/social_ui.gd")
const LbFetch = preload("res://scripts/meta/lb_fetch.gd")
const Notify = preload("res://scripts/meta/notify.gd")
const Analytics = preload("res://scripts/meta/analytics.gd")
const Diag = preload("res://scripts/siege/siege_diag.gd")
const TitleLogo = preload("res://scripts/app/title_logo.gd")

# 0.31.112 (Kevin: "move it [Home] to the center button. Move the shop button to far left")
const TABS := [["shop", "SHOP", "stall"], ["pass", "PASS", "banner"], ["home", "HOME", "castle"], ["locker", "LOCKER", "helmet"], ["settings", "SETTINGS", "gear"]]

# Tests may point these elsewhere before the node enters the tree.
var profile_path := "user://siege_profile.json"
var legacy_path := "user://fatebound-save.json"
var now_override := -1

var profile
var audio: Node
var tab := "home"
var home_class := "knight"
var locker_class := "knight"
var forge_cls := "knight"              # 0.31.93: the Forge's class, weapon (Eco.forge_id) and the element picked for star 3
var forge_pick := ""
var quest_cls := ""                   # 0.31.97: the class shown on the Quests screen ("" = the first with a step ready)
var forge_element := ""
var forge_shop := false                # the Embers packs open
var siege = null
var home_fixed := false                # 0.31.112: Home fits the screen and doesn't scroll (Screens.home sets it)

# ---------------- forced update (0.31.73) ----------------
# Kevin: "when server has newer version than players installed game it'll force them to update". The menu asks the
# server its protocol at start-up and on resume (VersionCheck); a refused connect reports it too (siege_mode
# version_mismatch). Server newer -> the blocking Update screen (UpdateScreen) and online play stays locked.
# Server older (a build published before the server deploy) -> "Servers are updating", nothing blocked.
var update_required := false
var server_updating := false
var server_version := -1
var update_screen: Control = null
# Tests may set these before the node enters the tree. Headless (tests, tools) skips the start-up check unless asked.
var version_check := DisplayServer.get_name() != "headless"
var version_check_url := OS.get_environment("SIEGE_URL") if OS.has_environment("SIEGE_URL") else Net.DEFAULT_URL
var open_url: Callable = func(u: String) -> int: return OS.shell_open(u)
var _version_checker: Node = null
var _version_checked_at := -1000.0
const RECHECK_AFTER := 60.0          # s: on resume, ask again if the last check is older than this

var chrome: Control
var content_scroll: ScrollContainer
var content: VBoxContainer
var tab_buttons := {}
var level_label: Label
var name_label: Label
var xp_bar: ProgressBar
var gold_label: Label
var gems_label: Label
var embers_label: Label                # 0.31.105 (Kevin: "Yes put an ember counter at top also")
# 0.31.105: gains fly into the counters (reward_fly.gd). kind (coin / gem / ember) -> {target: the profile's amount,
# shown: what the counter says (it catches up as the pieces land), flying: bursts in the air}
var reward_fly: Node2D
var quiet_top := false                 # (a restored save: the counters just change)
var _cur := {}
var _pill_icon := {}
var _last_press := Vector2(-1, -1)
var _last_press_ms := -100000
var modal: Control = null
var hero_layer: Control
var title_logo: Control                  # Home's title, the King swinging from the knot (title_logo.gd)
var hero_node: Control                 # the Home line-up (roster.gd); null on a safe start
var safe_top := 0.0
var xp_holder: Control
var pass_badge: Control
var _tab_tweens := {}
const TOP_H := 56.0                    # the top bar
const TAB_H := 72.0                    # the tab bar
const BG_ASPECT := 2816.0 / 1024.0     # the painted home backdrop (0.31.117: down the whole screen, the treasure hall
                                       # under the stage; until then 1280 / 720 and it ended under PLAY)
const BG_STAGE := 1280.0 / 720.0       # its top part, the old painting at the same width: where the sun, the clouds and the
                                       # stage are measured (fractions of this height)
const FADE_COLOR := Color("#0d1627")
var _toast: Label
var _toast_box: PanelContainer
var _toast_until := 0.0

# ---------------- start-up diagnostics and safe start (0.31.70; 0.31.72: moved into the BootGuard autoload) ----------------
# BootGuard (scripts/app/boot_guard.gd) runs before this scene loads: the start-up log, the "pending until the menu
# is up" record and SAFE START (no background model loading and no live 3D hero) after a stuck start. This scene
# only reads safe_boot and marks its steps in the log.
var safe_boot := false
var online_status: Node = null         # 0.31.82: the server's player count for Home (the real app only, or FB_STATUS_POLL)
var billing: Node = null               # 0.31.90: Google Play purchases (scripts/meta/billing.gd); inactive off Play
                                       # (0.31.130: the App Store's on iOS, billing_ios.gd -- store_billing.gd picks)
var play_games: Node = null            # 0.31.102: Google Play Games sign-in and the progress kept there (play_games.gd)
                                       # (0.31.130: Game Center on iOS, game_center.gd -- game_services.gd picks)
# 0.31.108: the account on the server (eco_sync.gd) -- the server's copy of the profile is the one that counts.
# Headless (tests, tools) it doesn't reach the real server unless asked (eco_url / FB_ECO=1).
var eco_sync: Node = null
var analytics: Node = null              # 0.31.118: usage statistics to our own server (scripts/meta/analytics.gd)
var notify = Notify.new()                # 0.31.119: "your chest is ready" notifications (the Play build's plugin)
var eco_autostart := DisplayServer.get_name() != "headless" or OS.has_environment("FB_ECO")
var eco_url := OS.get_environment("SIEGE_URL") if OS.has_environment("SIEGE_URL") else Net.DEFAULT_URL
var online_refs := {}                  # Home's "players online" pill: {main, sub}
# 0.31.111 (Kevin: "Build a global chat and players can click a name and have option to add friend to a friends list.
# They can then group up and form a party"): the social side (scripts/meta/social.gd) -- chat, friends, the party.
# Headless (tests, tools) it doesn't reach the real server unless asked (FB_SOCIAL=1).
var social: Node = null
var social_autostart := DisplayServer.get_name() != "headless" or OS.has_environment("FB_SOCIAL")
var chat_ticker: Control = null
var _invite_banner: Control = null
var _social_name := ""
var _social_sig := ""                  # what Home shows of it (requests, invites, the party): redraw when it changes
var _guard: Node = null
# 0.31.84 (Kevin: "put a fps cap of 60 in the menus"): the menus ran uncapped (120 on a 120 Hz phone); a match sets its
# own 30 and puts this back when it ends. The real app only (tests and tools run the menus as fast as they can).
const MENU_FPS := 60

func _boot_mark(phase: String) -> void:
	if _guard != null:
		_guard.mark(phase)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_guard = get_node_or_null("/root/BootGuard")
	get_tree().auto_accept_quit = false
	_menu_fps()
	safe_boot = _guard != null and bool(_guard.safe_boot)
	if not safe_boot:
		_boot_mark("preload models")
		Assets.preload_async()                 # 0.31.8: load the match's models on a thread while the menus are up
	_boot_mark("profile")
	profile = Profile.new(profile_path, legacy_path)
	profile.now_override = now_override
	profile.load_or_create()
	_boot_mark("audio")
	audio = Audio.new()
	add_child(audio)
	_apply_audio()
	_boot_mark("background")
	_build_background()
	_boot_mark("hero")
	_build_hero()
	_boot_mark("menus")
	_build_chrome()
	var fly_layer := CanvasLayer.new()               # 0.31.105: above the menus and their modals
	fly_layer.layer = 60
	add_child(fly_layer)
	reward_fly = RewardFly.new()
	fly_layer.add_child(reward_fly)
	if get_tree().get_script() == null or OS.has_environment("FB_STATUS_POLL"):
		online_status = OnlineStatus.new()
		online_status.changed.connect(paint_online)
		add_child(online_status)
	eco_sync = EcoSync.new()
	eco_sync.url = eco_url
	eco_sync.auto_start = eco_autostart
	eco_sync.setup(profile)
	add_child(eco_sync)
	eco_sync.synced.connect(_on_eco_synced)
	analytics = Analytics.new()
	analytics.url = eco_url
	analytics.auto_start = eco_autostart
	analytics.setup(profile)
	add_child(analytics)
	analytics.watch_errors()
	analytics.begin_session(true, safe_boot)
	analytics.note_level(int(profile.d.level))
	if online_status != null:
		online_status.changed.connect(func():
			if int(online_status.info.get("an", 0)) == 1:
				analytics.server_ok = true)
	eco_sync.rejected.connect(func(op: String, err: String):
		print("ECO rejected %s: %s" % [op, err])
		if op == "match":
			toast("That match couldn't be counted by the server", UI.RED)
		else:
			toast("The server didn't accept that change, so it was undone", UI.RED))
	social = Social.new()
	social.url = eco_url
	social.setup(profile)
	social.show_global = bool(profile.d.settings.get("chat_global", true))
	add_child(social)
	social.note.connect(_on_social_note)
	social.request.connect(_on_friend_request)
	social.invited.connect(_on_party_invite)
	social.go.connect(_on_party_go)
	social.changed.connect(_on_social_changed)
	chat_ticker.setup(self)
	if social_autostart:
		social.set_active(true)
	billing = StoreBilling.make()
	add_child(billing)
	billing.on_server_grant = func(g: Dictionary): eco_sync.adopt(g.get("profile", {}), int(profile.d.account.get("seq", 0)))
	billing.setup(profile)
	billing.note.connect(func(t: String, good: bool): toast(t, UI.GOLD if good else UI.RED))
	billing.granted.connect(_on_iap_granted)
	billing.changed.connect(func():
		if tab == "shop" and not is_instance_valid(modal) and siege == null:
			rebuild())
	play_games = GameServices.make()
	add_child(play_games)
	play_games.note.connect(func(t: String, good: bool): toast(t, UI.GOLD if good else UI.RED))
	play_games.changed.connect(func():
		if tab == "settings" and not is_instance_valid(modal) and siege == null:
			rebuild())
	play_games.ask.connect(func(_here: Dictionary, _cloud: Dictionary):
		if siege == null:
			ask_cloud())                         # (in a match: asked when it ends, _end_match)
	play_games.restored.connect(_on_cloud_restored)
	play_games.setup(profile)
	# Toast: a dark pill just above the tab bar, readable over anything.
	_toast_box = PanelContainer.new()
	var tsb := UI.card_style(Color(0.02, 0.04, 0.08, 0.92), 18, UI.CARD_HI)
	_toast_box.add_theme_stylebox_override("panel", tsb)
	_toast_box.anchor_left = 0.0
	_toast_box.anchor_right = 1.0
	_toast_box.anchor_top = 1.0
	_toast_box.anchor_bottom = 1.0
	_toast_box.offset_left = 18
	_toast_box.offset_right = -18
	_toast_box.offset_top = -150
	_toast_box.offset_bottom = -92
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.visible = false
	add_child(_toast_box)
	_toast = UI.label(_toast_box, "", 14, UI.TEXT, null, true)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if str(profile.d.migration.get("from", "")) == "legacy" and not bool(profile.d.migration.get("shown", false)):
		profile.d.migration["shown"] = true
		profile.save()
		var m: Dictionary = profile.d.migration
		call_deferred("toast", "Welcome to Fatebound! Your progress carried over: +%d gold, +%d gems" % [int(m.gold), int(m.gems)], UI.GOLD)
	content_scroll.get_v_scroll_bar().value_changed.connect(_on_scroll)
	show_tab("home")
	_boot_mark("home shown, waiting for frames")
	if version_check:
		call_deferred("check_server_version")

func _apply_audio() -> void:
	var st: Dictionary = profile.d.settings
	if audio.has_method("set_levels"):
		# 0.31.110 (Kevin: "make it so the audio sliders are max by default"): 100% when unset
		audio.set_levels({"master":float(st.get("master", 1.0)), "combat":float(st.get("sfx", 1.0)), "ui":float(st.get("sfx", 1.0)),
			"music":float(st.get("music", 1.0))})

func sfx(cue: String) -> void:
	if audio != null and audio.has_method("play"):
		audio.play(cue)

# ---------------- chrome ----------------
func _build_background() -> void:
	var grad := Gradient.new()
	# 0.31.83: plain royal blue (the tone the damask used to give it), lighter at the top
	grad.set_color(0, Color("#243d96"))
	grad.set_color(1, Color("#0a1750"))
	grad.add_point(0.45, Color("#152a7c"))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 8
	gt.height = 256
	var bg := TextureRect.new()
	bg.texture = gt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# (0.31.83, Kevin: "I don't like the wallpaper looking pattern on background": the damask that 0.31.79 tiled under
	# every screen is gone.) 0.31.84 (Kevin picked concept C of reports/concepts/bg_concepts.png): royal blue with light
	# rays from the top and drifting gold motes, painted (gpt-image-2, Topaz 2x), covering the screen behind every menu.
	var art := TextureRect.new()
	art.texture = UI2.tex(UI2.V2 + "bg_menu.webp")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	# A soft warm glow behind the top of the screen.
	var glow_g := Gradient.new()
	glow_g.set_color(0, Color(1.0, 0.72, 0.3, 0.18))
	glow_g.set_color(1, Color(1.0, 0.72, 0.3, 0.0))
	var glow := GradientTexture2D.new()
	glow.gradient = glow_g
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	glow.width = 256
	glow.height = 256
	var gl := TextureRect.new()
	gl.texture = glow
	gl.stretch_mode = TextureRect.STRETCH_SCALE
	gl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	gl.offset_top = -180
	gl.offset_bottom = 380
	gl.offset_left = -120
	gl.offset_right = 120
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gl)

func _grad(c0: Color, c1: Color, w := 8, h := 64) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0.5, 0.0)
	t.fill_to = Vector2(0.5, 1.0)
	t.width = w
	t.height = h
	return t

func _band(parent: Control, c0: Color, c1: Color, top: bool, px: float) -> void:
	var r := TextureRect.new()
	r.texture = _grad(c0, c1)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_right = 1.0
	if top:
		r.offset_bottom = px
	else:
		r.anchor_top = 1.0
		r.anchor_bottom = 1.0
		r.offset_top = -px
	parent.add_child(r)

func _build_hero() -> void:
	# 0.31.79: Home's painted backdrop (castle battlements at golden hour, the rival castle beyond, a gold-rimmed dais),
	# drifting cloud wisps, slow sun rays, the seven heroes in 3D on the dais (roster.gd), gold motes and the logo.
	# Scrolls away with a parallax as the menu is scrolled.
	safe_top = _safe_top()
	hero_layer = Control.new()
	hero_layer.anchor_right = 1.0
	hero_layer.anchor_bottom = 1.0             # 0.31.117: the whole screen (was 650 + safe_top: the painting stopped under
	                                           # PLAY and the rest of Home was plain navy -- Kevin: "very empty")
	hero_layer.clip_contents = true
	hero_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hero_layer)
	var bgt := TextureRect.new()
	bgt.texture = UI2.tex(UI2.V2 + "bg_home.webp")
	bgt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bgt.stretch_mode = TextureRect.STRETCH_SCALE
	bgt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_layer.add_child(bgt)
	var calm := bool(profile.d.settings.get("reduce_motion", false))
	var clouds: Array = []
	for cd in [[0.36, 260.0, 46.0, 0.42, 75.0], [0.47, 200.0, 34.0, 0.36, 60.0], [0.27, 170.0, 30.0, 0.3, 95.0]]:
		var c := TextureRect.new()
		c.texture = UI2.glow_tex()
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.stretch_mode = TextureRect.STRETCH_SCALE
		c.size = Vector2(cd[1], cd[2])
		c.modulate = Color(1, 0.97, 0.92, cd[3])
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hero_layer.add_child(c)
		clouds.append([c, cd])
	var sun := UI2.rays(hero_layer, 620.0, Color(1.0, 0.9, 0.62), 90.0, 0.32)
	var sun_glow := UI2.glow(hero_layer, Rect2(0, 0, 170, 170), Color(1.0, 0.93, 0.7, 0.7))
	if safe_boot:
		hero_node = null                      # safe start: the painted backdrop only, no live 3D heroes
	else:
		hero_node = Roster.new()
		hero_layer.add_child(hero_node)
	var lay := func():
		var w := hero_layer.size.x
		var h := w * BG_ASPECT
		var hs := w * BG_STAGE                             # (the stage part's height: the measurements below)
		var top := -0.405 * w + safe_top
		bgt.position = Vector2(0, top)
		bgt.size = Vector2(w, h)
		var sp := Vector2(0.615 * w, top + 0.574 * hs)
		sun.position = sp - sun.size * 0.5
		sun_glow.position = sp - sun_glow.size * 0.5
		for cl in clouds:
			(cl[0] as Control).position.y = top + float(cl[1][0]) * hs
		if hero_node != null:
			var dais := top + 0.858 * hs                    # the painted dais' centre
			hero_node.position = Vector2(0, dais - Roster.FEET_Y)
			hero_node.size = Vector2(w, 340.0)
	hero_layer.resized.connect(lay)
	lay.call()
	if not calm:
		for cl in clouds:
			var c: Control = cl[0]
			var secs: float = cl[1][4]
			c.position.x = randf_range(-80.0, 300.0)
			UI2.when_ready(c, func(): _drift(c, secs, true))
	_band(hero_layer, Color(0.02, 0.03, 0.09, 0.72), Color(0.02, 0.03, 0.09, 0.0), true, 110.0 + safe_top)
	_band(hero_layer, Color(FADE_COLOR, 0.0), Color(FADE_COLOR, 1.0), false, 150.0)
	if not calm:
		var glow := Gradient.new()
		glow.set_color(0, Color(1, 0.85, 0.5, 1.0))
		glow.set_color(1, Color(1, 0.85, 0.5, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = glow
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 24
		gt.height = 24
		var motes := CPUParticles2D.new()
		motes.texture = gt
		motes.amount = 22
		motes.lifetime = 7.0
		motes.preprocess = 7.0
		motes.position = Vector2(210, 470 + safe_top)
		motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		motes.emission_rect_extents = Vector2(200, 30)
		motes.direction = Vector2(0.2, -1.0)
		motes.spread = 18.0
		motes.gravity = Vector2.ZERO
		motes.initial_velocity_min = 14.0
		motes.initial_velocity_max = 34.0
		motes.scale_amount_min = 0.25
		motes.scale_amount_max = 0.6
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 0.0))
		ramp.set_color(1, Color(1, 1, 1, 0.0))
		ramp.add_point(0.25, Color(1, 1, 1, 0.9))
		ramp.add_point(0.75, Color(1, 1, 1, 0.6))
		motes.color_ramp = ramp
		hero_layer.add_child(motes)
	# The game is just "Fatebound" (Kevin). 0.31.113: the "All Tied Up" title (Kevin: "I like the all tied up one. Can you
	# also make it so the king swings back and forth from the rope"), between the side medallions under the top bar.
	title_logo = TitleLogo.new(calm)
	hero_layer.add_child(title_logo)
	var place := func():
		var w := hero_layer.size.x
		var lw := minf(w - 150.0, 300.0)
		title_logo.size = Vector2(lw, lw * TitleLogo.aspect())
		title_logo.position = Vector2((w - lw) * 0.5, 60.0 + safe_top)
	hero_layer.resized.connect(place)
	place.call()

const LOGO_FONT = preload("res://assets/fonts/LuckiestGuy-Regular.ttf")

func _drift(c: Control, secs: float, first: bool) -> void:
	# a cloud wisp crosses the sky left to right, then starts again off the left edge
	var w := hero_layer.size.x
	if not first:
		c.position.x = -c.size.x - 20.0
	var dist := w + 40.0 - c.position.x
	var tw := c.create_tween()
	tw.tween_property(c, "position:x", w + 40.0, secs * dist / (w + c.size.x + 60.0))
	tw.tween_callback(func(): _drift(c, secs, false))

func hero_show(_cls := "", _look := {}) -> void:
	# Home's line-up wears what's equipped (rebuilt only for a class whose look changed).
	if hero_node != null:
		var looks := {}
		for c in Eco.CLASSES:
			looks[c] = profile.look_for(c)
		hero_node.set_looks(looks)

func _on_scroll(v: float) -> void:
	hero_layer.position.y = -v * 0.55
	hero_layer.modulate.a = clampf(1.0 - v / 360.0, 0.0, 1.0)

func _safe_top() -> float:
	# Status bar / notch inset in logical pixels.
	var safe := DisplayServer.get_display_safe_area()
	var window := Vector2(DisplayServer.window_get_size())
	var logical := get_viewport().get_visible_rect().size
	if window.y <= 0 or safe.size.y <= 0:
		return 0.0
	return clampf(float(safe.position.y) * logical.y / window.y, 0.0, 60.0)

func _build_chrome() -> void:
	chrome = VBoxContainer.new()
	chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chrome.add_theme_constant_override("separation", 0)
	add_child(chrome)
	UI.spacer(chrome, 6.0 + safe_top)
	# --- top bar: level shield, name + XP, gold and gems (0.31.79 look)
	var top := Control.new()
	top.custom_minimum_size = Vector2(0, TOP_H)
	chrome.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.offset_left = 10
	bar.offset_right = -10
	bar.offset_bottom = -6
	top.add_child(bar)
	var sh := Control.new()
	sh.custom_minimum_size = Vector2(44, 50)
	sh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(sh)
	var st := TextureRect.new()
	st.texture = UI2.tex(UI2.V2 + "shield.svg")
	st.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	st.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	st.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.add_child(st)
	level_label = UI2.text(sh, "1", 20, Color.WHITE, Color("#0e1433"), 5)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	level_label.offset_bottom = -6
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 4)
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.grow(who)
	bar.add_child(who)
	name_label = UI2.body(who, "", 14, Color.WHITE, false)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS      # (0.31.87: a long title ends in "...")
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	name_label.add_theme_constant_override("outline_size", 4)
	xp_holder = VBoxContainer.new()
	xp_holder.custom_minimum_size = Vector2(0, 10)
	who.add_child(xp_holder)
	gold_label = _pill(bar, "coin")
	gems_label = _pill(bar, "gem")
	embers_label = _pill(bar, "ember")
	# --- screen area ---
	content_scroll = ScrollContainer.new()
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Drag-scrolling is done by _input below; the built-in one never saw drags that started on a
	# card or button (they stop the event) and would fight ours where it did.
	content_scroll.scroll_deadzone = 1000000
	chrome.add_child(content_scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 26)
	content_scroll.add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(content)
	# --- the chat line over the tab bar, Home only (0.31.111; set up once the social side exists)
	chat_ticker = ChatTicker.new()
	chrome.add_child(chat_ticker)
	# --- tab bar: dark wood with a gold edge; the open tab is a raised gold-framed tile (0.31.79)
	var tb := Control.new()
	tb.custom_minimum_size = Vector2(0, TAB_H)
	chrome.add_child(tb)
	var wood := TextureRect.new()
	wood.texture = UI2.tex(UI2.V2 + "tex_wood.webp")
	wood.stretch_mode = TextureRect.STRETCH_TILE
	wood.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wood.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	wood.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wood.modulate = Color(0.62, 0.5, 0.42)
	wood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.add_child(wood)
	_band(tb, Color(0.08, 0.03, 0.0, 0.1), Color(0.05, 0.02, 0.0, 0.7), true, TAB_H)
	var edge := ColorRect.new()
	edge.color = Color("#2a1604")
	edge.anchor_right = 1.0
	edge.offset_top = -3
	edge.offset_bottom = 3
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.add_child(edge)
	var gold_edge := TextureRect.new()
	gold_edge.texture = _grad(Color("#fff0b0"), Color("#b9761b"), 4, 16)
	gold_edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gold_edge.stretch_mode = TextureRect.STRETCH_SCALE
	gold_edge.anchor_right = 1.0
	gold_edge.offset_top = -2
	gold_edge.offset_bottom = 2
	gold_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.add_child(gold_edge)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 0)
	trow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	trow.offset_left = 4
	trow.offset_right = -4
	tb.add_child(trow)
	for t in TABS:
		tab_buttons[t[0]] = _tab_button(trow, t[0], t[1], t[2])
	pass_badge = UI2.badge(tab_buttons["pass"].button, "0", Vector2(-10, 4))
	tab_buttons["pass"]["badge"] = pass_badge

func _pill(parent: Node, kind: String) -> Label:
	# A dark pill with the currency coming out of its left end and a green "+". Tapping it opens the shop.
	var p := PanelContainer.new()
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = 15
	sb.content_margin_right = 3
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(p)
	var edge := {"coin": Color("#e9b648"), "gem": Color("#5fd2f0"), "ember": Color("#ff8a3d")}
	UI2.skin(p, {"radius": 15.0, "outline": 2.0, "outline_color": edge.get(kind, Color("#5fd2f0")),
		"rim": 0.0, "fill_top": Color(0.06, 0.09, 0.24, 0.94), "fill_bottom": Color(0.01, 0.02, 0.08, 0.94), "shadow_y": 3.0, "shadow_alpha": 0.5, "bevel": 0.1})
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 3)
	p.add_child(r)
	var l := UI2.body(r, "0", 14, Color.WHITE, false)
	l.custom_minimum_size = Vector2(33, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var plus := Panel.new()
	plus.custom_minimum_size = Vector2(19, 19)
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(plus)
	UI2.skin(plus, UI2.button_params("green", 7.0, 3.0))
	var pl := UI.label(plus, "+", 14, Color.WHITE, UI.HEAVY_FONT)
	pl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pl.offset_top = -3
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin := TextureRect.new()
	coin.texture = UI2.tex("res://assets/ui/currency/%s.png" % kind)
	_pill_icon[kind] = coin
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.size = Vector2(32, 32)
	coin.position = Vector2(-14, -4)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(coin)                      # (a non-container child, so it's placed by hand)
	coin.top_level = false
	p.sort_children.connect(func():
		coin.size = Vector2(32, 32)
		coin.position = Vector2(-16, (p.size.y - 32.0) * 0.5))
	for c in r.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "focus"]:
		hit.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	hit.set_meta("action_key", "pill_" + kind)
	hit.pressed.connect(func():
		sfx("tab")
		show_tab("forge" if kind == "ember" else "shop"))      # (Embers are bought in the Forge)
	p.add_child(hit)
	return l

func _tab_button(parent: Node, id: String, text: String, icon_name: String) -> Dictionary:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(0, TAB_H)
	b.set_meta("action_key", "tab_" + id)
	UI.grow(b)
	b.pressed.connect(func():
		sfx("tab")                             # 0.31.110: its own sound, a soft rustle into a click
		show_tab(id))
	parent.add_child(b)
	var plate := Control.new()                    # the raised tile of the open tab
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.offset_top = -18
	plate.offset_left = 1
	plate.offset_right = -1
	plate.offset_bottom = -3
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.visible = false
	b.add_child(plate)
	UI2.plate(plate, "royal", 16.0, "gold")
	var halo := UI2.glow(plate, Rect2(0, 0, 10, 10), Color(1.0, 0.86, 0.45, 0.55))
	plate.resized.connect(func():
		halo.size = Vector2(plate.size.x * 1.1, 56)
		halo.position = Vector2(plate.size.x * -0.05, 2))
	var ic := TextureRect.new()
	ic.texture = UI2.tex(UI2.icon_path(icon_name))
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	var l := UI2.text(b, text, 11, Color("#f1dfba"), Color(0.1, 0.04, 0.0, 0.9), 3, false)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	l.offset_top = -22
	l.offset_bottom = -6
	return {"button":b, "icon":ic, "label":l, "plate":plate}

func _style_tab(tb: Dictionary, on: bool) -> void:
	var b: Button = tb.button
	var ic: TextureRect = tb.icon
	var l: Label = tb.label
	(tb.plate as Control).visible = on
	var px := 52.0 if on else 38.0
	var place := func():
		ic.size = Vector2(px, px)
		ic.position = Vector2((b.size.x - px) * 0.5, -8.0 if on else 6.0)
	if b.resized.is_connected(tb.get("place", func(): pass)):
		b.resized.disconnect(tb.place)
	tb["place"] = place
	b.resized.connect(place)
	place.call()
	ic.modulate = Color.WHITE if on else Color(0.92, 0.88, 0.84)
	l.add_theme_color_override("font_color", UI2.GOLD if on else Color("#f1dfba"))
	l.add_theme_font_size_override("font_size", 13 if on else 10)
	l.add_theme_constant_override("outline_size", 4 if on else 3)
	var key := str(b.get_meta("action_key"))
	if _tab_tweens.has(key) and is_instance_valid(_tab_tweens[key]):
		(_tab_tweens[key] as Tween).kill()
	_tab_tweens.erase(key)
	if on and is_inside_tree():
		var tw := ic.create_tween().set_loops()
		tw.tween_property(ic, "position:y", -12.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(ic, "position:y", -8.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tab_tweens[key] = tw

func refresh_top() -> void:
	var d: Dictionary = profile.d
	level_label.text = str(int(d.level))
	name_label.text = Net.title_text(str(d.name), str(d.title))      # (0.31.87: the title as it joins the name)
	for c in xp_holder.get_children():
		c.queue_free()
	UI2.bar(xp_holder, int(d.xp), Eco.level_xp(int(d.level)), Color("#b6f3ff"), Color("#36b9ea"), 10.0)
	_counter("coin", gold_label, int(d.gold))
	_counter("gem", gems_label, int(d.gems))
	_counter("ember", embers_label, int(d.get("embers", 0)))
	# Badge on the PASS tab when rewards are waiting.
	var claimable := 0
	for tier in range(1, profile.pass_tier() + 1):
		for prem in [false, true]:
			if profile.can_claim(tier, prem):
				claimable += 1
	pass_badge.visible = claimable > 0
	(pass_badge.get_child(0) as Label).text = str(claimable)

# ---------------- the currency counters (0.31.105) ----------------
func _counter(kind: String, lbl: Label, value: int) -> void:
	# A rise flies in from where the reward came from (reward_fly.gd) and the counter counts up as the pieces land; a
	# fall (spending) shows at once. While a match runs the counters wait: the menus catch up (and fly) on the way back.
	var c: Dictionary = _cur.get(kind, {})
	if c.is_empty() or quiet_top or reward_fly == null:
		_cur[kind] = {"target": value, "shown": value, "flying": 0}
		lbl.text = UI.compact(value)
		return
	if siege != null or not chrome.is_visible_in_tree():
		return
	var delta := value - int(c.target)
	c.target = value
	if delta < 0:
		c.shown = maxi(int(c.shown) + delta, 0)
		lbl.text = UI.compact(int(c.shown))
	elif delta > 0:
		c.flying = int(c.flying) + 1
		reward_fly.burst(kind, delta, fly_origin(), _pill_icon.get(kind), func(share: int):
			c.shown = mini(int(c.shown) + share, int(c.target))
			lbl.text = UI.compact(int(c.shown))
			_punch(kind), func():
			c.flying = int(c.flying) - 1
			if int(c.flying) <= 0:
				c.shown = c.target
				lbl.text = UI.compact(int(c.target)))

func fly_origin() -> Vector2:
	# where a reward came from: the tap that claimed it (CLAIM, COLLECT, BUY ...), else the middle of the screen
	if _last_press.x >= 0.0 and Time.get_ticks_msec() - _last_press_ms < 2500:
		return _last_press
	return get_viewport_rect().size * Vector2(0.5, 0.45)

var _punch_ms := {}
func _punch(kind: String) -> void:
	var ic: Control = _pill_icon.get(kind)
	if not is_instance_valid(ic):
		return
	ic.pivot_offset = ic.size * 0.5
	ic.scale = Vector2.ONE * 1.32
	var tw := ic.create_tween()
	tw.tween_property(ic, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var now := Time.get_ticks_msec()
	if now - int(_punch_ms.get(kind, 0)) > 70:            # a quick run of clinks, not a roar
		_punch_ms[kind] = now
		sfx(kind)                                           # 0.31.109: coin / gem / ember, each its own

func home_height() -> float:
	# the height Home has to fill: the screen less the top bar, the chat line, the tab bar and the list's margins
	var vh := get_viewport_rect().size.y
	var ticker := float(ChatTicker.H) if chat_ticker != null else 0.0
	return vh - (6.0 + safe_top + TOP_H) - ticker - TAB_H - 30.0

func show_tab(id: String) -> void:
	if is_instance_valid(modal):
		close_modal()                          # (a window's button that goes to another tab, e.g. the pass summary)
	if analytics != null and id in ["shop", "pass"] and (tab != id or siege != null):
		analytics.log_ev("shop_view", {"tab":id})
	tab = id
	profile.refresh()
	for t in tab_buttons:
		_style_tab(tab_buttons[t], t == id)
	hero_layer.visible = id == "home"
	if chat_ticker != null:
		chat_ticker.visible = id == "home"
	if online_status != null:
		online_status.set_active(id == "home" and siege == null)
	hero_layer.position.y = 0.0
	hero_layer.modulate.a = 1.0
	content_scroll.scroll_vertical = 0
	rebuild()
	content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if (id == "home" and home_fixed) \
		else ScrollContainer.SCROLL_MODE_AUTO
	content.modulate.a = 0.0
	create_tween().tween_property(content, "modulate:a", 1.0, 0.18)
	if id == "home":
		offer_daily.call_deferred()

func rebuild() -> void:
	# Screens are rebuilt from the profile after every change; they're small and static.
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	if tab == "home" and social != null:
		_social_sig = social_sig()             # (what Home is about to show of the social side)
	if is_instance_valid(modal) and modal.has_method("refresh"):
		modal.refresh()                        # 0.31.112: a window showing the profile (ORDERS) follows it
	match tab:
		"home": Screens.home(self, content)
		"pass": Screens.pass_screen(self, content)
		"shop": Screens.shop(self, content)
		"locker": Screens.locker(self, content)
		"settings": Screens.settings(self, content)
		"forge": Screens.forge(self, content)
		"quests": Screens.quests(self, content)
	refresh_top()

# ---------------- players online (0.31.82) ----------------
func paint_online() -> void:
	# Home's pill from the last status answer: "12 PLAYERS ONLINE" (or the plain server line while unknown)
	var main: Label = online_refs.get("main")
	var sub: Label = online_refs.get("sub")
	if not is_instance_valid(main) or not is_instance_valid(sub):
		return
	var info: Dictionary = online_status.info if online_status != null else {}
	if info.is_empty():
		main.text = "LIVE SIEGE SERVER"
		sub.text = "16 vs 16  ·  bots fill any empty slots"
		return
	var n := int(info.get("online", 0))
	# 0.31.117 (Kevin's Home said "0 PLAYERS ONLINE" with him on it): a count only once someone else is on
	main.text = "%d PLAYERS ONLINE" % n if n >= 2 else "LIVE SIEGE SERVER"
	var fighting := int(info.get("in_match", 0))
	var waiting := int(info.get("waiting", 0))
	if waiting > 0 and float(info.get("lobby", -1.0)) >= 0.0:
		sub.text = "%d in the lobby  ·  join them!" % waiting
	elif fighting > 0:
		sub.text = "%d in battle  ·  bots fill the rest" % fighting
	else:
		sub.text = "bots fill the empty slots"

# ---------------- feedback ----------------
func toast(text: String, color := UI.TEXT) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast_box.visible = true
	_toast_box.modulate.a = 1.0
	_toast_until = Time.get_ticks_msec() / 1000.0 + 2.8
	move_child(_toast_box, get_child_count() - 1)

func confirm(title_text: String, body: String, yes_text: String, style: String, on_yes: Callable, on_no := Callable()) -> void:
	sfx("menuOpen")
	close_modal()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var v := UI.card(center)
	(v.get_parent() as Control).custom_minimum_size = Vector2(minf(360, size.x - 32), 0)
	UI.title(v, title_text, 20)
	var b := UI.label(v, body, 14, UI.MUTED)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var r := UI.row(v, 10)
	UI.grow(UI.button(r, "CANCEL", "secondary", func():
		sfx("menuClose")
		close_modal()
		if on_no.is_valid():
			on_no.call(), "modal_no"))
	UI.grow(UI.button(r, yes_text, style, func():
		close_modal()
		on_yes.call(), "modal_yes"))

func notice(title_text: String, body: String) -> void:
	# 0.31.119: a message with one OK (why a match ended, ...)
	sfx("menuOpen")
	close_modal()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var v := UI.card(center)
	(v.get_parent() as Control).custom_minimum_size = Vector2(minf(360, size.x - 32), 0)
	UI.title(v, title_text, 20)
	var b := UI.label(v, body, 14, UI.MUTED)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.grow(UI.button(UI.row(v, 10), "OK", "primary", func():
		sfx("menuClose")
		close_modal(), "modal_ok"))

func close_modal() -> void:
	if is_instance_valid(modal):
		modal.queue_free()
	modal = null
	if social != null:
		_social_home.call_deferred()

# ---------------- menu drag-scroll (0.18.3, Kevin: "the main menu can't scroll up and down") ----------------
# Every screen is cards and buttons, and those stop input, so the ScrollContainer's own touch drag
# never started. Here the app sees events before the controls: a press inside the menu that moves
# more than DRAG_START px vertically becomes a scroll; the control under the finger gets a
# cancelled press (released off-screen) so it doesn't fire; short taps pass through untouched.
const DRAG_START := 14.0
var _drag_down := false
var _dragging := false
var _drag_from := Vector2.ZERO
var _drag_scroll0 := 0.0
var _fling := 0.0
var _cancelling := false
var _swallow_up := false
var _drag_sc: ScrollContainer = null

func _menu_scroll_live() -> bool:
	return _scroll_target() != null

func _scroll_target() -> ScrollContainer:
	# the menu's own list -- or, with a window open that has one (0.31.111: the chat, Friends), that window's list
	if siege != null:
		return null
	if is_instance_valid(modal):
		var ms: Variant = modal.get_meta("drag_scroll", null)
		if ms is ScrollContainer and is_instance_valid(ms) and (ms as ScrollContainer).is_visible_in_tree():
			return ms
		return null
	if tab == "home" and home_fixed:
		return null                            # 0.31.112: Home doesn't scroll
	if is_instance_valid(content_scroll) and content_scroll.is_visible_in_tree():
		return content_scroll
	return null

func _input(event: InputEvent) -> void:
	if (event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)) and event.pressed:
		_last_press = event.position             # (0.31.105: where a claimed reward flies from)
		_last_press_ms = Time.get_ticks_msec()
	if _cancelling or not _menu_scroll_live():
		return
	# Touch (the phone) or a real mouse (desktop). Mouse events emulated from touch are ignored
	# here (the touch events drive it) and swallowed while a scroll is in progress.
	var is_touch: bool = event is InputEventScreenTouch or event is InputEventScreenDrag
	var emulated: bool = (event is InputEventMouse) and event.device == InputEvent.DEVICE_ID_EMULATION
	if is_touch and int(event.get("index")) != 0:
		return
	if emulated:
		# Swallow the pointer while scrolling, and the finger-lift release that follows a scroll
		# (whichever order the platform delivers the touch and its emulated mouse event in).
		if _dragging or (_swallow_up and event is InputEventMouseButton and not event.pressed):
			if event is InputEventMouseButton and not event.pressed:
				_swallow_up = false
			get_viewport().set_input_as_handled()
		return
	var press: bool = (event is InputEventScreenTouch) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)
	var motion: bool = (event is InputEventScreenDrag) or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0)
	if press:
		if event.pressed:
			_swallow_up = false
			var sc := _scroll_target()
			if sc.get_global_rect().has_point(event.position):
				_drag_sc = sc
				_drag_down = true
				_dragging = false
				_drag_from = event.position
				_drag_scroll0 = sc.scroll_vertical
				_fling = 0.0
		else:
			if _dragging:
				get_viewport().set_input_as_handled()
				_swallow_up = true
			_drag_down = false
			_dragging = false
	elif motion and _drag_down:
		var dy: float = event.position.y - _drag_from.y
		if not _dragging and absf(dy) > DRAG_START:
			_dragging = true
			_cancel_press()
		if _dragging and is_instance_valid(_drag_sc):
			_drag_sc.scroll_vertical = int(_drag_scroll0 - dy)
			var vy: float = event.velocity.y if "velocity" in event else event.relative.y * 60.0
			_fling = clampf(-vy, -4000.0, 4000.0)
			get_viewport().set_input_as_handled()

func _cancel_press() -> void:
	# Cancel the pressed control: move the pointer off-screen first (buttons update "pressing
	# inside" only from motion, and the drag's motion is swallowed -- without this PLAY still fired
	# after a scroll), then release there. Godot buttons only fire when released over them.
	_cancelling = true
	var away := InputEventMouseMotion.new()
	away.position = Vector2(-10000, -10000)
	away.global_position = away.position
	away.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(away, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = Vector2(-10000, -10000)
	up.global_position = up.position
	get_viewport().push_input(up, true)
	_cancelling = false

func _process(_delta: float) -> void:
	Assets.poll()
	# Keep gliding after a flick, easing out.
	if not _drag_down and absf(_fling) > 30.0 and _menu_scroll_live() and _scroll_target() == _drag_sc:
		_drag_sc.scroll_vertical = int(_drag_sc.scroll_vertical + _fling * _delta)
		_fling *= pow(0.04, _delta)
	elif not _drag_down:
		_fling = 0.0
	if _toast_box.visible:
		var left := _toast_until - Time.get_ticks_msec() / 1000.0
		_toast_box.modulate.a = clampf(left / 0.5, 0.0, 1.0)
		if left <= 0.0:
			_toast_box.visible = false

# ---------------- matches ----------------
const TUTORIAL_GOLD := Eco.TUTORIAL_GOLD
var _ticket_wait := false              # 0.31.108: asking the server for a VS BOTS ticket
var _ticket_ok := false

func _on_eco_synced(differs: bool) -> void:
	# 0.31.108: the profile is the server's again; redraw only if something shown changed (and not mid-match)
	if social != null and social.online() and str(profile.d.name) != _social_name:
		_social_name = str(profile.d.name)
		social.refresh()                          # 0.31.111: a new name -- the chat and friends lists show it
	if analytics != null:
		analytics.note_level(int(profile.d.level))
	if siege == null and tab == "home":
		offer_referral.call_deferred()            # 0.31.120: a referral chest that came with this answer (it checks)
	if not differs or siege != null:
		return
	refresh_top()
	if not is_instance_valid(modal):
		rebuild()

func start_tutorial() -> void:
	# The Herald's walkthrough: a small offline match (siege_mode.gd tutorial = true).
	start_match(false, true)

var pending_join := ""                   # 0.31.120: a friend's public id whose match the next PLAY joins

func join_friend(pid: String) -> void:
	# 0.31.120 (Kevin: "make so it's a join match option"): Friends > JOIN on a friend who's in a match
	if social != null and social.in_party() and social.party_size() > 1:
		sfx("error")
		toast("Leave your party to join a friend's match", UI.MUTED)
		return
	close_modal()
	pending_join = pid
	start_match(true)
	if siege == null:
		pending_join = ""

func start_match(online: bool, tutorial := false, follow := false) -> void:
	if siege != null:
		return
	if online and update_required:
		show_update_screen()               # online stays locked until the update is installed
		return
	if online and not tutorial and social != null and social.online() and social.in_party():
		# 0.31.111: a party plays together -- the leader's PLAY takes everyone in the menu along (social "play" ->
		# "go"); a member waits for the leader (follow: the leader's "go" arrived)
		if social.is_leader():
			social.play()
		elif not follow:
			sfx("error")
			var lead := str(social.card_of(str(social.party.get("leader", ""))).get("n", "your leader"))
			toast("%s starts your party's match -- or leave the party to play alone" % lead, UI.MUTED)
			return
	if not online and not tutorial and eco_sync != null and eco_sync.enabled and not _ticket_ok:
		# 0.31.108 (Kevin: "Always online"): a VS BOTS match pays only against a ticket the server gives now
		if _ticket_wait:
			return
		_ticket_wait = true
		toast("Connecting to the server...", UI.GOLD)
		eco_sync.request_ticket(func(tk: String):
			_ticket_wait = false
			if tk == "":
				sfx("error")
				toast("VS BOTS needs a connection to the server", UI.RED)
				return
			_ticket_ok = true
			start_match(false, false)
			_ticket_ok = false)
		return
	sfx("matchStart")
	if analytics != null and not tutorial:
		analytics.log_ev("match_join", {"mode":"online" if online else "bots",
			"party_n":social.party_size() if social != null and social.online() and social.in_party() else 1})
	siege = Siege.new()
	siege.online = online
	siege.tutorial = tutorial
	siege.profile = profile
	siege.audio = audio
	siege.low_fx = bool(profile.d.settings.get("reduce_motion", false))
	siege.hq_gfx = bool(profile.d.settings.get("hq_graphics", true))
	siege.vibrate = bool(profile.d.settings.get("vibrate", true))          # 0.31.120
	siege.player_name = str(profile.d.name)
	siege.analytics = analytics
	siege.party_join = pending_join                 # 0.31.120: Friends > JOIN (their match)
	pending_join = ""
	siege.exited.connect(_end_match)
	siege.version_mismatch.connect(_on_version_mismatch)
	if online_status != null:
		online_status.set_active(false)
	_set_menu_active(false)
	add_child(siege)

func _set_menu_active(on: bool) -> void:
	# While a match runs nothing of the menu may render or animate: the home hero owns a
	# physical-resolution 4x-MSAA 3D viewport plus particles, and the PLAY button loops tweens.
	# A hidden layer alone is not enough for the tweens/particles, so processing is disabled too.
	chrome.visible = on
	chrome.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	hero_layer.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if not on:
		hero_layer.visible = false          # coming back, show_tab decides (home only)

func _menu_fps() -> void:
	if get_tree().get_script() == null or OS.has_environment("FB_MENU_FPS"):
		Engine.max_fps = MENU_FPS

func _end_match() -> void:
	var note := ""
	if is_instance_valid(siege):
		note = str(siege.exit_note)
		siege.note_leaving()                     # 0.31.118: a VS BOTS match or the tutorial left before its end
		siege.queue_free()
	siege = null
	if eco_sync != null and eco_sync.enabled:
		eco_sync.pull()                          # 0.31.108: the server's count of the match (online), or ours sent up
	if analytics != null:
		analytics.note_level(int(profile.d.level))
	_menu_fps.call_deferred()                 # (after the match's _exit_tree puts back what it found)
	_set_menu_active(true)
	show_tab("home")
	if play_games != null and play_games.state == "ask":
		ask_cloud()                              # 0.31.102: Google Play's question waited for the match to end
	if update_required:
		show_update_screen()
	elif server_updating:
		toast(SERVER_UPDATING, UI.GOLD)
	elif note == "idle":
		notice("REMOVED FOR BEING IDLE", "You didn't move or attack for 3 minutes, so a bot took your place. Nothing was paid for that match.")

# ---------------- Google Play's copy of the progress (0.31.102) ----------------
func ask_cloud() -> void:
	# Both this phone and Google Play have progress: the player picks. Nothing is replaced without this choice.
	var q: Dictionary = play_games.pending_choice() if play_games != null else {}
	if q.is_empty():
		return
	var here: Dictionary = q.here
	var cloud: Dictionary = q.cloud
	var when := ""
	if int(cloud.get("at", 0)) > 0:
		var dt := Time.get_datetime_dict_from_unix_time(int(cloud.at))
		when = " (%s %d)" % [["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][int(dt.month)], int(dt.day)]
	var from := str(cloud.get("device", ""))
	var body := "Google Play has saved progress%s%s:\n%s\n\nThis phone:\n%s\n\nThe one you don't keep is replaced." % [
		(" from " + from) if from != "" else "", when, _cloud_line(cloud), _cloud_line(here)]
	close_modal()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var v := UI.card(center)
	(v.get_parent() as Control).custom_minimum_size = Vector2(minf(360, size.x - 32), 0)
	UI.title(v, "WHICH PROGRESS?", 20)
	var b := UI.label(v, body, 14, UI.MUTED)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.button(v, "USE GOOGLE PLAY'S", "primary", func():
		close_modal()
		play_games.choose(true), "cloud_use")
	UI.button(v, "KEEP THIS PHONE'S", "secondary", func():
		close_modal()
		play_games.choose(false), "cloud_keep")

static func _cloud_line(s: Dictionary) -> String:
	var n := int(s.get("items", 0))
	return "Level %d · %d wins · %d gold · %d gems · %d item%s" % [int(s.get("level", 1)), int(s.get("wins", 0)),
		int(s.get("gold", 0)), int(s.get("gems", 0)), n, "" if n == 1 else "s"]

func _on_cloud_restored() -> void:
	# the profile was replaced: everything shown from it is redrawn (the counters just change: nothing was earned)
	if eco_sync != null:
		eco_sync.account_switched()              # 0.31.108: (and with it, maybe, the account on the server)
	_apply_audio()
	hero_show()
	if siege == null:
		quiet_top = true
		rebuild()
		quiet_top = false

# ---------------- forced update ----------------
const SERVER_UPDATING := "Servers are updating, try again in a few minutes"

func check_server_version() -> void:
	# Ask the server which protocol it speaks (no match is joined). One at a time.
	if is_instance_valid(_version_checker):
		return
	_version_checked_at = Time.get_ticks_msec() / 1000.0
	_version_checker = VersionCheck.new()
	_version_checker.url = version_check_url
	_version_checker.done.connect(_on_server_version)
	_version_checker.answered.connect(func(m: Dictionary):
		if analytics != null:
			analytics.server_ok = int(m.get("an", 0)) == 1)
	add_child(_version_checker)

func _on_server_version(server_v: int) -> void:
	_version_checker = null
	if analytics != null:
		analytics.set_net(server_v >= 0)
	apply_server_version(server_v)

func apply_server_version(server_v: int) -> void:
	var verdict: String = Net.version_verdict(server_v)
	print("VERSION_CHECK server=%d client=%d -> %s" % [server_v, Net.VERSION, verdict])
	match verdict:
		"update":
			server_version = server_v
			update_required = true
			server_updating = false
			if siege == null:              # an offline match in progress gets it when it ends (_end_match)
				show_update_screen()
		"server_old":
			server_version = server_v
			server_updating = true
		"ok":
			# Same protocol (e.g. the server was rolled back): unlock.
			server_version = server_v
			server_updating = false
			if update_required:
				update_required = false
				hide_update_screen()
				if siege == null:
					rebuild()
		_:
			pass                           # unknown: offline or an older server; the connect path still checks

func _on_version_mismatch(server_v: int, verdict: String) -> void:
	# A refused connect (siege_mode). "update": straight to the Update screen. "server_old": siege_mode shows the
	# message and comes home by itself; Home repeats it (_end_match).
	server_version = server_v
	if verdict == "update":
		update_required = true
		server_updating = false
		call_deferred("_end_match")
	else:
		server_updating = true

func show_update_screen() -> void:
	if is_instance_valid(update_screen):
		move_child(update_screen, get_child_count() - 1)
		update_screen.visible = true
		return
	update_screen = UpdateScreen.new()
	update_screen.server_version = server_version
	if analytics != null:
		analytics.log_ev("update_screen", {"from_build":Diag.BUILD, "need":server_version})
	update_screen.open_url = open_url
	update_screen.offline_requested.connect(func():
		# 0.31.84 merge: Home has no VS BOTS mode any more (one PLAY, always online), so this starts the offline
		# match itself; the Update screen comes back when it ends (_end_match).
		hide_update_screen()
		start_match(false)
		toast("Offline vs bots. Update the game to play online.", UI.GOLD))
	add_child(update_screen)              # last child: over the menus, the toast and any match

func hide_update_screen() -> void:
	if is_instance_valid(update_screen):
		update_screen.queue_free()
	update_screen = null

func _on_iap_granted(product: String, g: Dictionary) -> void:
	# 0.31.90: a confirmed purchase landed in the profile
	if bool(g.get("again", false)):
		return
	sfx("gemPack" if int(g.get("gems", 0)) > 0 else "purchase")       # 0.31.110: gems pouring out
	var bits := ["+%s gems" % UI.compact(int(g.get("gems", 0)))]
	if int(g.get("embers", 0)) > 0:
		bits.append("+%d Embers" % int(g.embers))
	if str(g.get("item", "")) != "":
		bits.append(str(Eco.item(str(g.item)).get("name", "")))
	toast("  ·  ".join(bits), UI.GOLD)
	rebuild()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(update_screen):
			get_tree().quit()              # the Update screen can't be backed out of into the game
		elif is_instance_valid(modal):
			close_modal()
		elif is_instance_valid(siege):
			siege.request_leave()
		elif tab != "home":
			show_tab("home")
		else:
			if analytics != null:
				analytics.end_session()
			get_tree().quit()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		if analytics != null:
			analytics.end_session()                # (desktop: the window closed)
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		if analytics != null:
			analytics.end_session()                # 0.31.118: a session is a time in the foreground
		if notify != null and profile != null:
			notify.on_background(profile)          # 0.31.119: a chest that finishes while we're away says so
		if audio != null and audio.has_method("stop"):
			audio.stop()
		if social != null:
			social.set_active(false)               # 0.31.111: back when the app is
		if play_games != null:
			play_games.on_pause()                  # 0.31.102: the latest progress up to Google Play
		if online_status != null:
			online_status.set_active(false)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if notify != null:
			notify.on_foreground()                 # 0.31.119: back in the game -- the chests show themselves
		if analytics != null:
			analytics.begin_session(false, false, str(analytics.meta.get("net", "")))
		if eco_sync != null and eco_sync.auto_start:
			eco_sync.start()                   # 0.31.108: the account as the server has it
		if social != null and social_autostart:
			social.set_active(true)
		if billing != null:
			billing.resume()                   # a purchase finished while we were away (or a pending one cleared)
		if play_games != null:
			play_games.on_resume()
		if online_status != null:
			online_status.set_active(tab == "home" and siege == null)
		if version_check and siege == null and Time.get_ticks_msec() / 1000.0 - _version_checked_at > RECHECK_AFTER:
			# 0.31.91: deferred -- this notification is propagated through the tree, and add_child during it fails
			# ("Parent node is busy setting up children" in Kevin's log), leaving a checker that blocked every later check.
			check_server_version.call_deferred()   # back from the Play Store (or a long pause): ask again

# ---------------- chat, friends, the party (0.31.111) ----------------
func open_chat(ch := "global") -> void:
	if social == null:
		return
	close_modal()
	var m := ChatPanel.new()
	add_child(m)
	modal = m
	m.open(self, ch)

func open_orders() -> void:
	close_modal()
	var m := OrdersPanel.new()
	add_child(m)
	modal = m
	m.open(self)

func chest_started() -> void:
	# 0.31.119: a chest started unlocking -- the first time, ask whether they'd like a notification when it's ready
	# (our question first; Android's own dialog only on YES, so a NO here doesn't use up Android's two asks)
	if notify == null or not notify.should_ask(profile):
		return
	profile.d.settings["notify_asked"] = true
	profile.save()
	confirm("CHEST NOTIFICATIONS", "Want a notification when your chest is ready to open? You can change this in Settings.",
		"YES", "primary", func():
			notify.request_permission(),
		func():
			profile.d.settings["notify"] = false
			profile.save())

func open_daily() -> void:
	# 0.31.119: the DAILY REWARD card
	close_modal()
	var m := DailyReward.new()
	add_child(m)
	modal = m
	m.open(self)

# 0.31.119: the daily reward opens by itself on Home the first time each day a claim waits (not in tests or screenshot
# tools, which set daily_auto when they want it)
var daily_auto := DisplayServer.get_name() != "headless" and not OS.has_environment("SHOT_DIR")
var _daily_offered := ""

func offer_prize() -> bool:
	# 0.31.120: a weekly leaderboard prize the server paid since we last said so -- once
	if not daily_auto or siege != null or update_required or tab != "home" or is_instance_valid(modal):
		return false
	var pz: Array = profile.d.get("prizes", [])
	if pz.is_empty() or str(pz[0].get("week", "")) == str(profile.d.settings.get("prize_seen", "")):
		return false
	var x: Dictionary = pz[0]
	profile.d.settings["prize_seen"] = str(x.week)
	profile.save()
	var bits := ["%d gems" % int(x.get("gems", 0))]
	if str(x.get("chest", "")) != "":
		bits.append("a %s" % str(Eco.CHESTS[str(x.chest)].name))
	var t := str(x.get("title", ""))
	if t != "" and Net.TITLES.has(t):
		bits.append("the title \"%s\" (wear it from the Locker)" % str(Net.TITLES[t][0]))
	sfx("confirm")
	notice("LEADERBOARD PRIZE", "You finished #%d on last week's leaderboard! You got %s." % [int(x.get("rank", 0)), ", ".join(bits)])
	return true

func offer_referral() -> bool:
	# 0.31.120: Gold chests from a referral (server/referrals.gd) since we last said so
	if not daily_auto or siege != null or update_required or tab != "home" or is_instance_valid(modal):
		return false
	var seen := int(profile.d.settings.get("ref_seen", 0))
	var fresh: Array = (profile.d.get("referral", {}).get("notes", []) as Array).filter(func(n): return int(n.get("at", 0)) > seen)
	if fresh.is_empty():
		return false
	profile.d.settings["ref_seen"] = int(fresh[0].get("at", 0))
	profile.save()
	sfx("confirm")
	notice("FRIEND REWARD", referral_text(fresh))
	return true

static func referral_text(fresh: Array) -> String:
	var lines := []
	for n in fresh:
		if str(n.get("kind", "")) == "joined":
			lines.append("You reached level %d with %s's code: a Gold Chest for you!" % [Eco.REF_LEVEL, str(n.get("name", "a friend"))])
		else:
			lines.append("%s reached level %d with your code: a Gold Chest for you!" % [str(n.get("name", "A friend")), Eco.REF_LEVEL])
	if lines.size() > 3:
		return "%d friend rewards: %d Gold Chests! Open them from your chest slots." % [lines.size(), lines.size()]
	return "\n".join(lines) + "\nOpen it from your chest slots."

func redeem_code(code: String, cb := Callable()) -> void:
	# 0.31.120 (Kevin: referral codes): a new player enters the code of the friend who invited them -- the server checks
	# it (server/referrals.gd) and answers {"t":"ref", "ok", "why", "name"}
	var acct := str(profile.d.account.get("id", ""))
	var key := str(profile.d.account.get("key", ""))
	if acct == "" or key == "":
		sfx("error")
		toast("Play one online match first, then enter the code", UI.MUTED)
		return
	LbFetch.ask(self, str(eco_url), {"t":"ref", "acct":acct, "key":key, "code":code}, func(r: Dictionary):
		if r.is_empty():
			sfx("error")
			toast("Not connected to the server right now", UI.RED)
		elif bool(r.get("ok", false)):
			sfx("confirm")
			profile.d.referral["by"] = str(r.get("name", "a friend"))
			profile.save()
			if eco_sync != null:
				eco_sync.pull()
			toast("Code accepted! Reach level %d and you both get a Gold Chest" % Eco.REF_LEVEL, UI.CYAN)
		else:
			sfx("error")
			var why := str(r.get("why", ""))
			if why == "late":
				profile.d.settings["ref_late"] = true
				profile.save()
			toast({"code":"No player has that code", "self":"That's your own code", "done":"You've already entered a friend's code",
				"loop":"That friend joined with your code", "late":"Codes are for new players (first %d days, under level %d)" % [Eco.REF_DAYS, Eco.REF_LEVEL],
				"auth":"Play one online match first, then enter the code"}.get(why, "The server didn't take that code"), UI.RED)
		if is_instance_valid(modal) and modal.has_method("ref_changed"):
			modal.ref_changed()
		if cb.is_valid():
			cb.call(r))

# ---------------- SEND TO DEVELOPER (0.31.120) ----------------
static func diag_message(note: String, log_text: String, p) -> Dictionary:
	# the report (server/diag_reports.gd), fitted under one packet once compressed: the log's first lines (the session
	# header) and as much of its end as fits
	var msg := {"t":"diag", "name":str(p.d.get("name", "")), "build":Diag.BUILD, "note":note.strip_edges().left(500),
		"dev":{"model":OS.get_model_name(), "os":"%s %s" % [OS.get_name(), OS.get_version()], "gpu":RenderingServer.get_video_adapter_name()},
		"log":log_text}
	var acct := str(p.d.account.get("id", ""))
	if acct != "":
		msg["acct"] = acct
		msg["key"] = str(p.d.account.get("key", ""))
	var keep := mini(log_text.length(), 390000)
	if keep < log_text.length():
		msg.log = log_text.left(3000) + "\n[... %d characters left out ...]\n" % (log_text.length() - keep) + log_text.right(keep - 3000)
	while Net.encode(msg, true).size() > Net.MAX_PACKET - 2048 and keep > 4000:
		keep = int(keep * 0.7)
		msg.log = log_text.left(3000) + "\n[... %d characters left out ...]\n" % (log_text.length() - keep) + log_text.right(keep - 3000)
	return msg

func send_diagnostics(note: String, cb: Callable) -> void:
	# cb({"ok", "id"} / {"ok": false, "why"} / {} with no answer)
	LbFetch.ask(self, str(eco_url), diag_message(note, Diag.read_logs(200), profile), cb, true)

func open_send_diag() -> void:
	# Settings > SEND TO DEVELOPER: what's sent, a line about the problem, SEND -- asked every time
	sfx("menuOpen")
	close_modal()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var v := UI2.frame(center, "royal", 14, 20.0, "gold")
	(v.get_parent() as Control).custom_minimum_size = Vector2(minf(360, size.x - 32), 0)
	v.add_theme_constant_override("separation", 10)
	UI2.center(UI2.text(v, "SEND TO DEVELOPER", 22, UI2.GOLD))
	UI2.body(v, "Sends this phone's game log to the developer to fix a problem: what the game was doing, its errors, your " +
		"phone model and the game's version, with your player name. No chats, purchases or other apps.", 13, UI2.SOFT)
	var note := SocialUI.field(v, "What went wrong? (optional)", 300)
	note.name = "DiagNote"
	var r := UI.row(v, 10)
	UI.grow(UI2.button(r, "CANCEL", "ghost", func():
		sfx("menuClose")
		close_modal(), "diag_cancel", 15, 44.0))
	var send := UI2.button(r, "SEND", "orange", func(): pass, "diag_send", 17, 44.0)
	UI.grow(send)
	var m := modal
	send.pressed.connect(func():
		if send.has_meta("busy"):
			return
		send.set_meta("busy", true)
		send.text = "SENDING..."
		UI2.dim_button(send, true)
		sfx("tap")
		send_diagnostics(note.text, func(res: Dictionary):
			if bool(res.get("ok", false)):
				sfx("confirm")
				if modal == m:
					close_modal()
				toast("Sent -- report #%s. Thank you!" % str(res.get("id", "")), UI.CYAN)
				return
			sfx("error")
			if str(res.get("why", "")) == "busy":
				toast("You've sent a few already -- try again in an hour", UI.MUTED)
			else:
				toast("Couldn't reach the server -- try again, or use COPY DIAGNOSTICS", UI.RED)
			if is_instance_valid(send):
				send.remove_meta("busy")
				send.text = "SEND"
				UI2.dim_button(send, false)))

func offer_daily() -> void:
	if offer_prize() or offer_referral():
		return
	if not daily_auto or siege != null or update_required or tab != "home" or is_instance_valid(modal):
		return
	if not bool(profile.d.get("tutorial_done", false)) or not profile.login_ready():
		return
	var today := Eco.day_key(profile.now())
	if _daily_offered == today:
		return
	_daily_offered = today
	open_daily()

func open_leaderboard() -> void:
	# 0.31.119: the week's leaderboard (RANKS on Home)
	close_modal()
	var m := LeaderboardPanel.new()
	add_child(m)
	modal = m
	m.open(self)

func open_friends() -> void:
	if social == null:
		return
	close_modal()
	var m := FriendsPanel.new()
	add_child(m)
	modal = m
	m.open(self)

func _on_social_note(t: String, bad: bool, pop: bool) -> void:
	if siege != null:
		return
	if pop:
		sfx("chatPop")
	toast(t, UI.RED if bad else UI.GOLD)

func _on_friend_request(card: Dictionary) -> void:
	if siege != null:
		return
	sfx("chatPop")
	toast("%s wants to be friends -- see Friends" % str(card.get("n", "Someone")), UI.CYAN)

func _on_party_invite(pa: String, card: Dictionary) -> void:
	if siege != null:
		return                               # (it waits in Friends)
	sfx("chatPop")
	if is_instance_valid(_invite_banner):
		_invite_banner.queue_free()
	_invite_banner = InviteBanner.new()
	add_child(_invite_banner)
	_invite_banner.show_invite(self, pa, card, safe_top + TOP_H + 14.0)

func _on_party_go(_pa: String, by: String) -> void:
	# the party leader pressed PLAY: everyone in the menu follows
	if siege != null or update_required or is_instance_valid(update_screen):
		return
	close_modal()
	toast("%s is heading into battle -- your party follows!" % by, UI.GOLD)
	start_match(true, false, true)

func social_sig() -> String:
	if social == null or not social.online():
		return "off"
	var names := []
	for m in social.party.get("members", []):
		names.append(str(m.pid) + str(m.n))
	return "%d|%s|%s" % [social.attention(), str(social.party.get("leader", "")), ",".join(names)]

func _on_social_changed(what: String) -> void:
	if what == "me":
		_social_name = str(profile.d.name)
	if siege != null or not what in ["friends", "party", "state"]:
		return
	_social_home()

func _social_home() -> void:
	# Home shows the Friends badge and the party: redraw it when they change (not under a window: when it closes)
	var sig := social_sig()
	if sig != _social_sig and tab == "home" and not is_instance_valid(modal) and siege == null:
		_social_sig = sig
		rebuild()
