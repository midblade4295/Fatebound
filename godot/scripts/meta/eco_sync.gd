extends Node
# 0.31.108 (Kevin: "make sure everything is verified by server so players can't edit gems ect"): the phone's side of
# the accounts the Siege server keeps (server/eco_accounts.gd).
#
# The first time it reaches a server that keeps accounts, the phone asks for one ("new"), handing over its progress so
# far once (the server takes it in held to what that many matches could earn, purchases counted only if Google
# confirmed them). From then on the phone's profile is a prediction:
#   - every change made in the app is an op (Profile._rec -> _on_op) that goes into the outbox (kept on disk) and up
#     to the server in batches; the server replays it with the same Profile code and its own clock;
#   - each answer carries the account as the server has it: it replaces the phone's copy, the ops not answered yet are
#     applied again on top (Profile.apply_op), and the screens redraw if anything differs;
#   - a VS BOTS match needs a ticket from the server (request_ticket) before it starts -- Kevin: "Always online" -- and
#     its result goes up as an op carrying that ticket; an online match is paid by the server from its own match;
#   - a purchase is granted by the server to the account (billing.gd sends the account with the purchase).
# Ops are numbered; the server skips any number it has done, so sending a batch again after a lost answer is safe.
# Nothing here can add gems or gold the server doesn't agree with: an edited save is replaced by the next answer.
const Net = preload("res://scripts/siege/siege_net.gd")
const Diag = preload("res://scripts/siege/siege_diag.gd")

signal synced(differs: bool)           # the profile is the server's again (differs: what it shows changed)
signal rejected(op: String, error: String)
signal state_changed

const DEBOUNCE := 0.35                 # s after an op before the batch goes up
const TIMEOUT := 15.0
const MAX_BATCH := 64
const RETRY := [3.0, 6.0, 15.0, 30.0, 60.0]

var profile
var url := OS.get_environment("SIEGE_URL") if OS.has_environment("SIEGE_URL") else Net.DEFAULT_URL
var auto_start := true                 # tests turn this off and call start() / pull() themselves
var outbox_path := ""
var outbox: Array = []                 # [{"s", "op", "a", "tk"?}]
var next_seq := 1
var enabled := false                   # this phone has an account on the server
var online := false                    # the last exchange worked
var started := false
var ticket := ""                       # the VS BOTS ticket of the match being played
var _req: Dictionary = {}              # the exchange in flight: {ws, sent, msg, t0, ops}
var _want := false                     # an exchange is wanted even with nothing to send (a pull, a ticket)
var _want_ticket := false
var _ticket_cbs: Array = []
var _send_at := 0.0
var _fails := 0
var _clock := 0.0

func setup(p) -> void:
	profile = p
	outbox_path = str(p.path).get_basename() + ".outbox.json"
	_load_outbox()
	profile.on_op = _on_op
	_account_changed()

func _account_changed() -> void:
	enabled = str(profile.d.account.get("id", "")) != "" and str(profile.d.account.get("key", "")) != ""
	profile.server_mode = enabled
	next_seq = maxi(next_seq, int(profile.d.account.get("seq", 0)) + 1)
	state_changed.emit()

func _ready() -> void:
	if auto_start:
		start()

func start() -> void:
	# reach the server: an account if there is none yet, else the account as it stands (and whatever is waiting)
	started = true
	pull()

func pull() -> void:
	_want = true
	_send_at = minf(_send_at, _clock)

func account_switched() -> void:
	# Google Play's saved progress replaced this phone's, and with it the account: what was waiting belonged to the
	# other one
	outbox.clear()
	next_seq = 1
	_save_outbox()
	_account_changed()
	pull()

func request_ticket(cb: Callable) -> void:
	# a VS BOTS match may start: cb(ticket) -- "" when the server can't be reached (no match without it); "local"
	# with no account (an older server: the phone's own economy)
	if not enabled:
		cb.call("local")
		return
	_ticket_cbs.append(cb)
	_want_ticket = true
	pull()

func pending() -> int:
	return outbox.size()

# ---------------- the outbox ----------------
func _on_op(op: String, args: Array) -> void:
	if not enabled:
		return
	var o := {"s":next_seq, "op":op, "a":args}
	if op == "match":
		o["tk"] = ticket
		ticket = ""
	next_seq += 1
	outbox.append(o)
	_save_outbox()
	if _send_at <= _clock:
		_send_at = _clock + DEBOUNCE               # (a retry already waiting keeps its time)
	state_changed.emit()

func _load_outbox() -> void:
	outbox = []
	if outbox_path == "" or not FileAccess.file_exists(outbox_path):
		return
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(outbox_path))
	if v is Dictionary and v.get("ops", null) is Array:
		outbox = v.ops
		next_seq = maxi(next_seq, int(v.get("next", 1)))

func _save_outbox() -> void:
	if outbox_path == "":
		return
	var f := FileAccess.open(outbox_path + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"next":next_seq, "ops":outbox}))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(outbox_path + ".tmp"), ProjectSettings.globalize_path(outbox_path))

# ---------------- talking to the server ----------------
func _process(delta: float) -> void:
	_clock += delta
	if not _req.is_empty():
		_poll()
		return
	if not started or _clock < _send_at:
		return
	if _want or (enabled and not outbox.is_empty()):
		_send()

func _message() -> Dictionary:
	if not enabled:
		# a new account, with this phone's progress so far (taken in once, within limits)
		var imp: Dictionary = profile.d.duplicate(true)
		for k in ["settings", "cloud", "account", "history"]:
			imp.erase(k)
		return {"t":"eco", "v":Net.VERSION, "build":Diag.BUILD, "new":true, "import":imp}
	return {"t":"eco", "v":Net.VERSION, "build":Diag.BUILD, "acct":str(profile.d.account.id), "key":str(profile.d.account.key),
		"ops":outbox.slice(0, MAX_BATCH), "ticket":_want_ticket}

func _send() -> void:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 21
	ws.outbound_buffer_size = 1 << 17
	var msg := _message()
	_want = false
	if ws.connect_to_url(url) != OK:
		_failed()
		return
	_req = {"ws":ws, "sent":false, "msg":msg, "t0":_clock, "ticket":bool(msg.get("ticket", false))}

func _poll() -> void:
	var ws: WebSocketPeer = _req.ws
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not bool(_req.sent):
		ws.put_packet(Net.encode(_req.msg, true))
		_req.sent = true
	var answer := {}
	while ws.get_available_packet_count() > 0:
		var m := Net.decode(ws.get_packet())
		if str(m.get("t", "")) == "eco":
			answer = m
	if not answer.is_empty():
		var sent: Dictionary = _req.msg
		var had_ticket := bool(_req.ticket)
		_req = {}
		if st == WebSocketPeer.STATE_OPEN:
			ws.close()
		apply_answer(answer, sent, had_ticket)
		return
	if st == WebSocketPeer.STATE_CLOSED or _clock - float(_req.t0) > TIMEOUT:
		_req = {}
		if st != WebSocketPeer.STATE_CLOSED:
			ws.close()
		_failed()

func _failed() -> void:
	online = false
	_fails += 1
	_send_at = _clock + float(RETRY[mini(_fails - 1, RETRY.size() - 1)])
	if not enabled:
		# no account yet: an older server that keeps none, or no connection -- a few tries, then the next start
		_want = _fails < 3
	_ticket_done("")
	state_changed.emit()

func _ticket_done(tk: String) -> void:
	_want_ticket = false
	var cbs := _ticket_cbs.duplicate()
	_ticket_cbs.clear()
	for cb in cbs:
		(cb as Callable).call(tk)

func apply_answer(a: Dictionary, sent: Dictionary = {}, had_ticket := false) -> void:
	online = true
	_fails = 0
	if not bool(a.get("ok", false)):
		if str(a.get("why", "")) == "auth":
			# the server doesn't know this key (its accounts were reset): a new account from this phone's copy
			profile.d.account = {"id":"", "key":"", "seq":0}
			outbox.clear()
			next_seq = 1
			_save_outbox()
			profile.save(false)
			_account_changed()
			_want = true
		_ticket_done("")
		state_changed.emit()
		return
	if a.has("key"):
		profile.d.account = {"id":str(a.acct), "key":str(a.key), "seq":0}
		_account_changed()
	var seq := int(a.get("seq", 0))
	var ops_by_s := {}
	for o in sent.get("ops", []):
		ops_by_s[int(o.s)] = str(o.op)
	for r in a.get("results", []):
		if not bool(r.get("ok", false)) and not bool(r.get("dup", false)):
			rejected.emit(str(ops_by_s.get(int(r.get("s", 0)), "?")), str(r.get("error", "")))
	var left := []
	for o in outbox:
		if int(o.s) > seq:
			left.append(o)
	outbox = left
	next_seq = maxi(next_seq, seq + 1)
	_save_outbox()
	if a.has("now"):
		profile.clock_offset = int(a.now) - int(Time.get_unix_time_from_system())
	adopt(a.get("profile", {}), seq)
	if had_ticket:
		ticket = str(a.get("ticket", ""))
		_ticket_done(ticket)
	if not outbox.is_empty():
		_send_at = _clock                           # more waiting: straight on
	state_changed.emit()

func adopt(sp: Variant, seq: int) -> void:
	# the server's copy replaces this phone's; what is the phone's alone stays; the unanswered ops again on top
	if not (sp is Dictionary) or not (sp as Dictionary).has("stats"):
		return
	var d: Dictionary = profile.d
	var before := _view(d)
	var nd: Dictionary = (sp as Dictionary).duplicate(true)
	nd["settings"] = d.settings
	nd["cloud"] = d.cloud
	nd["account"] = {"id":str(d.account.id), "key":str(d.account.key), "seq":seq}
	nd["iap"] = {"done":d.iap.get("done", []), "starter":bool((sp as Dictionary).get("iap", {}).get("starter", false))}
	for k in ["migration", "refund_note", "title_note"]:
		if d.has(k):
			nd[k] = d[k]
	profile.d = profile._normalized(nd)
	var was: bool = profile.replaying
	profile.replaying = true
	for o in outbox:
		if str(o.op) == "match":
			var ar: Array = o.a
			if ar.size() == 3 and ar[0] is Dictionary:
				profile.apply_match(ar[0], bool(ar[1]), bool(ar[2]), false)
		else:
			profile.apply_op(str(o.op), o.a)
	profile.replaying = was
	profile.save()
	synced.emit(_view(profile.d) != before)

static func _view(d: Dictionary) -> String:
	# what the screens show, to tell whether a redraw is needed
	var v := d.duplicate(true)
	for k in ["settings", "cloud", "account", "history", "iap"]:
		v.erase(k)
	return JSON.stringify(v, "", true)
