extends Control
# 0.31.111 (Kevin: "players can ... add friend to a friends list. They can then group up and form a party"): the
# Friends window. Your friend code (and adding someone by theirs), your party (leader's crown, KICK, LEAVE, PLAY
# TOGETHER), party invites and friend requests waiting, your friends -- online first, each with INVITE -- the requests
# you've sent and the players you've blocked. Redrawn whenever scripts/meta/social.gd changes.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const SocialUI = preload("res://scripts/app/social_ui.gd")
const Eco = preload("res://scripts/meta/economy.gd")

var app
var social
var _list: VBoxContainer
var _scroll: ScrollContainer
var _code: LineEdit
var _ref: LineEdit                 # 0.31.120: the code of the friend who invited you
var _ref_busy := false
var _dirty := false

func open(a) -> void:
	app = a
	social = a.social
	var w := SocialUI.window(self, "FRIENDS", "friends", func():
		app.sfx("menuClose")
		app.close_modal(), 56.0 + float(app.safe_top), 24.0)
	var body: VBoxContainer = w.body
	SocialUI.social_tabs(body, app, "friends")              # 0.31.134: FRIENDS | CLAN
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 1000000
	body.add_child(_scroll)
	set_meta("drag_scroll", _scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	social.changed.connect(_on_changed)
	_render()

func ref_changed() -> void:
	# (siege_app.redeem_code: the server answered)
	_ref_busy = false
	_dirty = true

func _on_changed(what: String) -> void:
	if what in ["friends", "party", "state", "me", "clan"]:
		_dirty = true

func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		var keep := _scroll.scroll_vertical
		var typed := _code.text if is_instance_valid(_code) else ""
		var typed_ref := _ref.text if is_instance_valid(_ref) else ""
		_render()
		if is_instance_valid(_code):
			_code.text = typed
		if is_instance_valid(_ref):
			_ref.text = typed_ref
		_scroll.set_deferred("scroll_vertical", keep)

func _section(title: String, sub := "") -> VBoxContainer:
	var f := UI2.frame(_list, "glass", 10, 16.0)
	f.add_theme_constant_override("separation", 6)
	var h := UI.row(f, 8)
	UI.grow(UI2.text(h, title, 17, UI2.GOLD))
	if sub != "":
		var s := UI.label(h, sub, 12, UI2.MUTED, UI.HEAVY_FONT)
		s.autowrap_mode = TextServer.AUTOWRAP_OFF
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return f

func _person(parent: Node, c: Dictionary, crown := false) -> HBoxContainer:
	# a row: status dot, the name (tap: its card), title, status line; buttons go on the end
	var r := UI.row(parent, 8)
	SocialUI.dot(r, str(c.get("st", "offline")))
	var nb := Button.new()
	nb.flat = true
	nb.focus_mode = Control.FOCUS_NONE
	nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	nb.clip_text = true
	nb.custom_minimum_size = Vector2(0, 44)
	for st_name in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		nb.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	nb.set_meta("action_key", "friend_" + str(c.get("pid", "")))
	var card := c.duplicate()
	nb.pressed.connect(func(): SocialUI.name_card(app, self, card))
	r.add_child(nb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nb.add_child(v)
	var top := UI.row(v, 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if crown:
		UI2.icon(top, "crown", 18.0).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI2.text(top, str(c.get("n", "Player")), 15, Color.WHITE)
	if str(c.get("ct", "")) != "":
		UI.label(top, "[%s]" % str(c.ct), 12, UI2.GOLD, UI.HEAVY_FONT).size_flags_vertical = Control.SIZE_SHRINK_CENTER   # 0.31.134
	SocialUI.title_label(top, str(c.get("tt", "")), 11)
	var sl := UI.label(v, SocialUI.status_text(c), 11, SocialUI.ST_COL.get(str(c.get("st", "offline")), UI2.MUTED).lightened(0.25), UI.HEAVY_FONT)
	sl.autowrap_mode = TextServer.AUTOWRAP_OFF
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _small(parent: Node, text: String, color: String, key: String, cb: Callable, w := 78.0) -> Button:
	var b := UI2.button(parent, text, color, cb, key, 13, 36.0, 11.0)
	b.custom_minimum_size.x = w
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b

func _tag(parent: Node, text: String, col: Color) -> Label:
	var l := UI.label(parent, text, 12, col, UI.HEAVY_FONT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

func _fail() -> void:
	app.sfx("error")
	app.toast("Not connected to the server right now", UI.RED)

func _render() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	# ---- not connected
	if not social.online():
		var f := _section("NOT CONNECTED")
		var why := "Friends and parties need the game's server. Trying again shortly..."
		if not social.has_account():
			why = "Friends and parties start once you've been online with the game's server."
		elif str(social.state) == "old":
			why = "Friends and parties arrive with the next server update."
		elif str(social.state) == "connecting":
			why = "Connecting..."
		UI2.body(f, why, 13, UI2.SOFT)
		return
	# ---- your code / add by code
	var cf := _section("YOUR FRIEND CODE")
	var cr := UI.row(cf, 8)
	var code := UI2.text(cr, social.code_of(str(social.me.get("pid", ""))), 22, Color.WHITE)
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_small(cr, "COPY", "blue", "friend_code_copy", func():
		DisplayServer.clipboard_set(social.code_of(str(social.me.pid)))
		app.sfx("confirm")
		app.toast("Friend code copied -- send it to a friend", UI.CYAN))
	var ar := UI.row(cf, 8)
	_code = SocialUI.field(ar, "A friend's code", 12)
	_code.text_submitted.connect(func(_t): _add_code())
	_small(ar, "ADD", "green", "friend_code_add", func(): _add_code())
	_invite_section()
	# ---- the party
	if social.in_party():
		var p: Dictionary = social.party
		var pf := _section("YOUR PARTY", "%d / %d" % [social.party_size(), int(p.get("max", 4))])
		for m in p.get("members", []):
			var me: bool = str(m.pid) == str(social.me.pid)
			var r := _person(pf, m, str(m.pid) == str(p.leader))
			if me:
				_tag(r, "YOU", UI2.GOLD)
			elif social.is_leader():
				var mp := str(m.pid)
				_small(r, "KICK", "red", "party_kick_" + mp, func():
					app.sfx("menuClose")
					if not social.kick(mp):
						_fail(), 66.0)
		for m in p.get("pending", []):
			var r2 := _person(pf, m)
			_tag(r2, "INVITED", UI2.MUTED)
		var br := UI.row(pf, 8)
		if social.is_leader():
			UI.grow(UI2.button(br, "PLAY TOGETHER", "orange", func():
				app.close_modal()
				app.start_match(true), "party_play", 17, 46.0))
		else:
			var wait := UI2.button(br, "LEADER STARTS", "grey", func(): pass, "party_wait", 15, 46.0)
			UI.grow(wait)
			UI2.dim_button(wait, true)
		var lb := UI2.button(br, "LEAVE", "red", func():
			app.sfx("menuClose")
			if not social.leave():
				_fail(), "party_leave", 15, 46.0)
		lb.custom_minimum_size.x = 96
	# ---- invites and requests waiting
	if not social.invites.is_empty():
		var inf := _section("PARTY INVITES")
		for pa in social.invites:
			var from: Dictionary = social.invites[pa].from
			var r := _person(inf, from)
			var pid_pa: String = pa
			_small(r, "JOIN", "green", "invite_join", func():
				app.sfx("confirm")
				if not social.join(pid_pa):
					_fail(), 70.0)
			_small(r, "✕", "ghost", "invite_no", func():
				app.sfx("tap")
				social.no_join(pid_pa), 44.0)
	if not social.rin.is_empty():
		var rf := _section("FRIEND REQUESTS", str(social.rin.size()))
		for c in social.rin:
			var r := _person(rf, c)
			var cp := str(c.pid)
			_small(r, "ACCEPT", "green", "req_accept_" + cp, func():
				app.sfx("confirm")
				if not social.add(cp):
					_fail(), 84.0)
			_small(r, "✕", "ghost", "req_decline_" + cp, func():
				app.sfx("tap")
				social.decline(cp), 44.0)
	# ---- friends, online first
	var ff := _section("FRIENDS", "%d" % social.friends.size())
	if social.friends.is_empty():
		UI2.body(ff, "No friends yet. Tap a name in the chat to add them, or trade friend codes.", 13, UI2.SOFT)
	var order := {"online": 0, "match": 1, "offline": 2}
	var fl: Array = social.friends.duplicate()
	fl.sort_custom(func(a, b):
		var oa := int(order.get(str(a.st), 3))
		var ob := int(order.get(str(b.st), 3))
		return oa < ob if oa != ob else str(a.n).nocasecmp_to(str(b.n)) < 0)
	var full: bool = social.in_party() and social.party_size() + (social.party.get("pending", []) as Array).size() >= int(social.party.get("max", 4))
	for c in fl:
		var r := _person(ff, c)
		var cp := str(c.pid)
		if social.in_my_party(cp):
			_tag(r, "IN PARTY", UI2.GOLD)
		elif str(c.st) == "online" and not full:
			_small(r, "INVITE", "orange", "friend_invite_" + cp, func():
				app.sfx("confirm")
				if not social.invite(cp):
					_fail(), 80.0)
		elif str(c.st) == "match":
			_small(r, "JOIN", "green", "friend_join_" + cp, func():      # 0.31.120: into their match
				app.sfx("confirm")
				app.join_friend(cp), 80.0)
	# ---- sent, blocked
	if not social.rout.is_empty():
		var sf := _section("REQUESTS SENT", str(social.rout.size()))
		for c in social.rout:
			var r := _person(sf, c)
			var cp := str(c.pid)
			_small(r, "CANCEL", "ghost", "req_cancel_" + cp, func():
				app.sfx("tap")
				social.unfriend(cp), 80.0)
	if not social.blocked.is_empty():
		var bf := _section("BLOCKED", str(social.blocked.size()))
		for c in social.blocked:
			var r := UI.row(bf, 8)
			var n := UI2.text(r, str(c.n), 14, UI2.SOFT)
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var cp := str(c.pid)
			_small(r, "UNBLOCK", "blue", "unblock_" + cp, func():
				app.sfx("tap")
				social.unblock(cp), 90.0)

func _add_code() -> void:
	var t := _code.text.strip_edges().replace("#", "").replace(" ", "").to_lower()
	if t.length() != 10 or not t.is_valid_hex_number():
		app.sfx("error")
		app.toast("A friend code is 10 letters and numbers (like 3FA21C9B0D)", UI.RED)
		return
	if t == str(social.me.get("pid", "")):
		app.sfx("error")
		app.toast("That's your own code", UI.MUTED)
		return
	if social.add(t):
		app.sfx("confirm")
		_code.text = ""
	else:
		_fail()

# ---------------- invite friends (0.31.120, Kevin: referral codes) ----------------
func _invite_section() -> void:
	var p: Dictionary = app.profile.d
	var ref: Dictionary = p.get("referral", {})
	var f := _section("INVITE FRIENDS")
	UI2.body(f, "A new player who enters your friend code gets a Gold Chest at level %d -- and so do you." % Eco.REF_LEVEL, 13, UI2.SOFT)
	var mine := (ref.get("notes", []) as Array).filter(func(n): return str(n.get("kind", "")) == "friend").size()
	if mine > 0:
		var l := UI.label(f, "Friends who reached level %d with your code: %d" % [Eco.REF_LEVEL, mine], 12, UI2.GOLD, UI.HEAVY_FONT)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
	var by := str(ref.get("by", ""))
	if by != "":
		var got := (ref.get("notes", []) as Array).any(func(n): return str(n.get("kind", "")) == "joined")
		UI2.body(f, ("You joined with %s's code." % by) + ("" if got else " Reach level %d for your Gold Chest!" % Eco.REF_LEVEL), 13, UI2.GOLD)
	elif int(p.get("level", 1)) < Eco.REF_LEVEL and not bool(p.get("settings", {}).get("ref_late", false)):
		var rr := UI.row(f, 8)
		_ref = SocialUI.field(rr, "Invited? Their code", 12)
		_ref.text_submitted.connect(func(_t): _redeem())
		var b := _small(rr, "REDEEM", "orange", "ref_redeem", func(): _redeem(), 96.0)
		if _ref_busy:
			UI2.dim_button(b, true)

func _redeem() -> void:
	if _ref_busy or not is_instance_valid(_ref):
		return
	var t := _ref.text.strip_edges().replace("#", "").replace(" ", "").to_lower()
	if t.length() != 10 or not t.is_valid_hex_number():
		app.sfx("error")
		app.toast("A friend code is 10 letters and numbers (like 3FA21C9B0D)", UI.RED)
		return
	if t == str(social.me.get("pid", "")):
		app.sfx("error")
		app.toast("That's your own code", UI.MUTED)
		return
	_ref_busy = true
	app.sfx("tap")
	app.redeem_code(t)
	_dirty = true
