extends RefCounted
# Fatebound Siege online protocol, shared by the headless server (server/siege_server.gd) and the
# phone client (siege_net_client.gd). The server runs the real SiegeSim; clients keep a mirror
# SiegeSim (same map from setup()) whose dynamic state is overwritten from snapshots, so the
# existing view and HUD render online matches unchanged.
#
# Transport: WebSocket binary frames, each one var_to_bytes(Dictionary). Never bytes_to_var with
# objects: decode() uses the default allow_objects=false.
const Sim = preload("res://scripts/siege/siege_sim.gd")

const VERSION := 14              # 14 = ladder climbing speeds (by depth); 13 = hat shops are buildings; 12 = fishing
const DEFAULT_URL := "wss://136-113-125-3.sslip.io/fatebound/siege/ws"
const DEFAULT_PORT := 8082
const SNAP_HZ := 15.0            # 10 -> 15 (0.18.4): ~1.3 KB each, ~19 KB/s per player; remote
                                 # units' interpolation delay 100 -> 67 ms
const PREDICT_SNAP := 2.5        # m: a predicting phone snaps to the server beyond this
const MAX_PACKET := 64 * 1024            # client -> server; anything larger is dropped
const TEAM_SIZE := 16

const STATES := ["idle", "move", "wind", "recover", "dodge", "dead", "lift", "gather", "repair", "build_ladder", "fish"]
const CLASSES := ["villager", "worker", "knight", "barbarian", "rogue", "ranger", "mage", "priest"]
const LOADS := ["", "wood", "stone"]
const TASKS := ["", "gather", "repair", "build_ladder"]
const ATKS := ["", "attack", "ability"]
# Actions a client may ask for (anything else is ignored by the server).
const ACTIONS := ["attack", "ability", "dodge", "interact", "hat_swap",
	"take_tools", "buy", "workshop_leave"]
const HAT_CLS := ["knight", "barbarian", "rogue", "ranger", "mage", "worker", "priest"]

# Per-unit values in the snapshot, in this order, each packed as a signed 16-bit integer of
# value * SCALE[i] (positions to 1 cm, angles to 0.001 rad, timers to 0.01 s).
const F := 31
const SCALE := [1.0, 1.0, 100.0, 100.0, 1000.0, 1.0, 1.0, 1.0, 100.0, 1.0,
	1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 100.0, 100.0, 1.0, 1.0,
	1.0, 1.0, 0.1, 1.0, 10.0, 1.0, 1.0, 1.0, 1.0, 1.0, 100.0]

# Wire format: 1 byte tag + payload. "R" = var_to_bytes, "Z" = zstd(var_to_bytes) with the raw
# size in 4 bytes. Snapshots are compressed; small client messages go raw.
static func encode(msg: Dictionary, compress := false) -> PackedByteArray:
	var raw := var_to_bytes(msg)
	var out := PackedByteArray()
	if compress:
		var z := raw.compress(FileAccess.COMPRESSION_ZSTD)
		out.resize(5)
		out[0] = 0x5A
		out.encode_u32(1, raw.size())
		out.append_array(z)
		return out
	out.append(0x52)
	out.append_array(raw)
	return out

static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 2 or bytes.size() > MAX_PACKET * 16:
		return {}
	var raw := PackedByteArray()
	if bytes[0] == 0x5A and bytes.size() > 5:
		var n := bytes.decode_u32(1)
		if n <= 0 or n > MAX_PACKET * 64:
			return {}
		raw = bytes.slice(5).decompress(n, FileAccess.COMPRESSION_ZSTD)
	elif bytes[0] == 0x52:
		raw = bytes.slice(1)
	else:
		return {}
	var v: Variant = bytes_to_var(raw)
	return v if v is Dictionary else {}

static func _pack(arr: PackedByteArray, i: int, v: float) -> void:
	arr.encode_s16(i * 2, clampi(int(round(v * SCALE[i % F])), -32768, 32767))

static func _unpack(arr: PackedByteArray, i: int) -> float:
	return float(arr.decode_s16(i * 2)) / SCALE[i % F]

static func _code(list: Array, value: Variant) -> int:
	var i := list.find(value)
	return maxi(0, i)

# ---------------- server side ----------------
static func snapshot(sim, for_unit: String, events: Array) -> Dictionary:
	# for_unit "" = the shared part only (see for_player).
	var vals := PackedFloat32Array()
	vals.resize(sim.units.size() * F)
	var u_arr := vals
	var i := 0
	for u in sim.units:
		var task: Dictionary = u.task
		var b := i * F
		u_arr[b + 0] = u.hp
		u_arr[b + 1] = u.max_hp
		u_arr[b + 2] = u.pos.x
		u_arr[b + 3] = u.pos.y
		u_arr[b + 4] = u.face
		u_arr[b + 5] = _code(STATES, u.state)
		u_arr[b + 6] = _code(CLASSES, u.cls)
		u_arr[b + 7] = 1.0 if u.up else 0.0
		u_arr[b + 8] = u.stun
		u_arr[b + 9] = 1.0 if u.carrying else 0.0
		u_arr[b + 10] = float(u.get("lifting", -1))
		u_arr[b + 11] = _code(LOADS, u.load.kind)
		u_arr[b + 12] = u.load.n
		u_arr[b + 13] = 1.0 if u.get("offering", false) else 0.0
		u_arr[b + 14] = _code(TASKS, task.get("kind", ""))
		u_arr[b + 15] = float(task.get("node", task.get("gate", -1)))
		u_arr[b + 16] = u.cd_ability
		u_arr[b + 17] = u.cd_dodge
		u_arr[b + 18] = u.kills
		u_arr[b + 19] = u.deaths
		u_arr[b + 20] = u.rescues
		u_arr[b + 21] = u.gathered
		u_arr[b + 22] = u.gate_dmg
		u_arr[b + 23] = 1.0 if u.bot else 0.0
		u_arr[b + 24] = u.respawn_at
		u_arr[b + 25] = _code(ATKS, u.get("atk", ""))
		# Priest beam target: its unit index + 1 (0 = none).
		u_arr[b + 26] = float(sim.units.find(sim.by_id.get(str(u.beam), {})) + 1) if str(u.get("beam", "")) != "" else 0.0
		u_arr[b + 27] = 1.0 if u.workshop_open else 0.0
		u_arr[b + 28] = float(u.get("fed", 0))
		u_arr[b + 29] = 1.0 if sim.blocking(u) else 0.0
		u_arr[b + 30] = maxf(0.0, float(u.get("whirl_until", 0.0)) - sim.time)
		i += 1
	var packed := PackedByteArray()
	packed.resize(vals.size() * 2)
	for k in vals.size():
		_pack(packed, k, vals[k])
	var proj := []
	for p in sim.projectiles:
		proj.append([p.id, p.pos, p.vel, p.kind])
	var gates := PackedFloat32Array()
	for g in sim.gates:
		gates.append_array([g.hp, g.max_hp, 1.0 if g.broken else 0.0, 1.0 if g.open else 0.0])
	var nodes := PackedInt32Array()
	for n in sim.nodes:
		nodes.append(n.amount)
	var outposts := PackedFloat32Array()
	for op in sim.outposts:
		outposts.append_array([float(op.owner), float(op.prog), float(op.get("stock", 0))])
	# Hats: stock per stand, and every dropped hat as [id, class, upgraded, x, z].
	var stocks := PackedByteArray()
	for st in sim.stands:
		stocks.append(int(st.stock))
	var hats := PackedFloat32Array()
	for h in sim.hats:
		hats.append_array([float(h.id), float(HAT_CLS.find(h.cls)), 1.0 if h.up else 0.0, h.pos.x, h.pos.y])
	var oracles := []
	for o in sim.oracles:
		oracles.append({"state":o.state, "pos":o.pos, "carrier":o.carrier, "lifters":o.lifters.duplicate(),
			"carry_team":o.carry_team, "dropped_at":o.dropped_at, "cakes":o.cakes, "weight":o.weight})
	var msg := {"t":"s", "tm":sim.time, "sc":sim.score.duplicate(), "k":sim.kills.duplicate(),
		"st":sim.stock.duplicate(true), "lv":sim.levels.duplicate(true), "end":[sim.ended, sim.winner, sim.end_reason],
		"u":packed, "p":proj, "g":gates, "n":nodes, "o":oracles, "l":sim.ladders.duplicate(true), "op":outposts, "hs":stocks, "hd":hats, "e":events}
	if for_unit != "":
		return for_player(msg, sim, for_unit)
	return msg

static func for_player(base: Dictionary, sim, unit_id: String) -> Dictionary:
	# The shared snapshot plus this player's private bits (task). Shallow copy: the
	# big arrays are shared, only "me" differs, so the server builds the snapshot once per tick.
	var msg := base.duplicate(false)
	if sim.by_id.has(unit_id):
		var me: Dictionary = sim.by_id[unit_id]
		msg["me"] = {"task":me.task.duplicate(true)}
	return msg

# ---------------- client side ----------------
static func apply(sim, msg: Dictionary, me_id: String, predict := false) -> void:
	# Overwrites the mirror sim's dynamic state. Unit positions go to "net_to" so the client can
	# interpolate between snapshots; everything else is set directly.
	# The phone predicts its own unit: keep its position/facing (and a dodge it started) unless the
	# server disagrees by > PREDICT_SNAP or the unit is in a server-driven state (0.18.4).
	var mine_prev := {}
	if predict and sim.by_id.has(me_id):
		var mp: Dictionary = sim.by_id[me_id]
		mine_prev = {"pos": mp.pos, "face": mp.face, "state": mp.state, "t": float(mp.get("t", 0.0))}
	sim.time = float(msg.get("tm", sim.time))
	sim.score = msg.get("sc", sim.score)
	sim.kills = msg.get("k", sim.kills)
	sim.stock = msg.get("st", sim.stock)
	sim.levels = msg.get("lv", sim.levels)
	var end: Array = msg.get("end", [false, -1, ""])
	sim.ended = bool(end[0])
	sim.winner = int(end[1])
	sim.end_reason = str(end[2])
	var packed: PackedByteArray = msg.get("u", PackedByteArray())
	var u_arr := PackedFloat32Array()
	u_arr.resize(packed.size() / 2)
	for k in u_arr.size():
		u_arr[k] = _unpack(packed, k)
	var n_units: int = mini(sim.units.size(), u_arr.size() / F)
	for i in n_units:
		var u: Dictionary = sim.units[i]
		var b := i * F
		var was_dead: bool = u.state == "dead"
		u.hp = u_arr[b + 0]
		u.max_hp = u_arr[b + 1]
		var to := Vector2(u_arr[b + 2], u_arr[b + 3])
		u["net_from"] = u.pos
		u["net_to"] = to
		var state: String = STATES[clampi(int(u_arr[b + 5]), 0, STATES.size() - 1)]
		if was_dead != (state == "dead") or u.pos.distance_to(to) > 6.0:
			u.pos = to                       # respawn / teleport: no sliding across the map
			u["net_from"] = to
		u.face = u_arr[b + 4]
		u.state = state
		u.cls = CLASSES[clampi(int(u_arr[b + 6]), 0, CLASSES.size() - 1)]
		u.up = u_arr[b + 7] > 0.5
		u.stun = u_arr[b + 8]
		u.carrying = u_arr[b + 9] > 0.5
		u.lifting = int(u_arr[b + 10])
		u.load = {"kind":LOADS[clampi(int(u_arr[b + 11]), 0, LOADS.size() - 1)], "n":int(u_arr[b + 12])}
		u.offering = u_arr[b + 13] > 0.5
		var tk: String = TASKS[clampi(int(u_arr[b + 14]), 0, TASKS.size() - 1)]
		u.task = {} if tk == "" else {"kind":tk, "node":int(u_arr[b + 15]), "gate":int(u_arr[b + 15]), "t":0.0}
		u.cd_ability = u_arr[b + 16]
		u.cd_dodge = u_arr[b + 17]
		u.kills = int(u_arr[b + 18])
		u.deaths = int(u_arr[b + 19])
		u.rescues = int(u_arr[b + 20])
		u.gathered = int(u_arr[b + 21])
		u.gate_dmg = u_arr[b + 22]
		u.bot = u_arr[b + 23] > 0.5
		u.respawn_at = u_arr[b + 24]
		u.atk = ATKS[clampi(int(u_arr[b + 25]), 0, ATKS.size() - 1)]
		var bi := int(round(u_arr[b + 26])) - 1
		u.beam = str(sim.units[bi].id) if bi >= 0 and bi < sim.units.size() else ""
		u.workshop_open = u_arr[b + 27] > 0.5
		# The mirror doesn't step: flag the states open-ended; the next snapshot clears them.
		u.block_until = 1.0e9 if u_arr[b + 29] > 0.5 else 0.0
		u.whirl_until = 1.0e9 if u_arr[b + 30] > 0.005 else 0.0
		u.fed = int(u_arr[b + 28])
	# Projectiles slide between snapshots like units (0.18.5, Kevin: "projectiles skip across the
	# screen online"): they used to be redrawn only at each snapshot's position, so an arrow at
	# 22 m/s sat still for 66 ms and then jumped 1.5 m. Now each keeps from/to: a new one starts at
	# its spawn point (on the same one-interval-behind timeline as the units it flies between), and
	# one that ended this snapshot gets one last slide to its impact point before it disappears.
	var old := {}
	for p in sim.projectiles:
		old[p.id] = p
	sim.projectiles.clear()
	var seen := {}
	for p in msg.get("p", []):
		var prev: Dictionary = old.get(p[0], {})
		var from: Vector2 = prev.get("net_to", p[1])
		sim.projectiles.append({"id":p[0], "pos":from, "net_from":from, "net_to":p[1], "vel":p[2], "kind":p[3], "team":-1})
		seen[p[0]] = true
	var ends := {}
	for e in msg.get("e", []):
		if e is Dictionary and str(e.get("k", "")) == "proj_end" and e.has("pos"):
			ends[e.get("pid")] = e.pos
	for id in old:
		var gone: Dictionary = old[id]
		if not seen.has(id) and ends.has(id) and not bool(gone.get("ghost", false)):
			var last: Vector2 = gone.get("net_to", gone.pos)
			sim.projectiles.append({"id":id, "pos":last, "net_from":last, "net_to":ends[id], "vel":gone.vel,
				"kind":gone.kind, "team":-1, "ghost":true})
	var gates: PackedFloat32Array = msg.get("g", PackedFloat32Array())
	for gi in mini(sim.gates.size(), gates.size() / 4):
		var g: Dictionary = sim.gates[gi]
		g.hp = gates[gi * 4]
		g.max_hp = gates[gi * 4 + 1]
		g.broken = gates[gi * 4 + 2] > 0.5
		g.open = gates[gi * 4 + 3] > 0.5
	var nodes: PackedInt32Array = msg.get("n", PackedInt32Array())
	for ni in mini(sim.nodes.size(), nodes.size()):
		sim.nodes[ni].amount = nodes[ni]
	var oracles: Array = msg.get("o", [])
	for t in mini(2, oracles.size()):
		var src: Dictionary = oracles[t]
		var o: Dictionary = sim.oracles[t]
		for k in src:
			o[k] = src[k]
	sim.ladders = msg.get("l", sim.ladders)
	var ops: PackedFloat32Array = msg.get("op", PackedFloat32Array())
	for oi in mini(sim.outposts.size(), ops.size() / 3):
		sim.outposts[oi].owner = int(ops[oi * 3])
		sim.outposts[oi].prog = ops[oi * 3 + 1]
		sim.outposts[oi].stock = int(ops[oi * 3 + 2])
	var stocks: PackedByteArray = msg.get("hs", PackedByteArray())
	for si in mini(sim.stands.size(), stocks.size()):
		sim.stands[si].stock = stocks[si]
	var hd: PackedFloat32Array = msg.get("hd", PackedFloat32Array())
	sim.hats = []
	for hi in hd.size() / 5:
		var k := hi * 5
		sim.hats.append({"id":int(hd[k]), "cls":HAT_CLS[clampi(int(hd[k + 1]), 0, HAT_CLS.size() - 1)], "up":hd[k + 2] > 0.5,
			"pos":Vector2(hd[k + 3], hd[k + 4]), "t":0.0})
	if not mine_prev.is_empty():
		var me2: Dictionary = sim.by_id[me_id]
		var server_pos: Vector2 = me2.get("net_to", me2.pos)
		me2.erase("net_to")
		me2.erase("net_from")
		me2["srv_pos"] = server_pos
		if sim.client_drivable(me2) and (mine_prev.pos as Vector2).distance_to(server_pos) <= PREDICT_SNAP:
			me2.pos = mine_prev.pos
			me2.face = mine_prev.face
			# A dodge or swing we started locally keeps playing until its timer runs out (the server's
			# confirmation arrives a round trip later).
			if str(mine_prev.state) in ["dodge", "wind", "recover"] and float(mine_prev.t) > 0.0:
				me2.state = mine_prev.state
				me2.t = mine_prev.t
		else:
			me2.pos = server_pos
	if msg.has("me") and sim.by_id.has(me_id):
		var me: Dictionary = sim.by_id[me_id]
		me.task = msg.me.task

static func interpolate(sim, alpha: float) -> void:
	# Called every frame between snapshots: slide unit positions from the previous snapshot to
	# the latest (alpha 0..1 across one snapshot interval).
	var a := clampf(alpha, 0.0, 1.0)
	for u in sim.units:
		if u.has("net_to"):
			u.pos = (u.net_from as Vector2).lerp(u.net_to, a)
	for p in sim.projectiles:
		if p.has("net_to"):
			p.pos = (p.net_from as Vector2).lerp(p.net_to, a)
