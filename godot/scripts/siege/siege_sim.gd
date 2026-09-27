extends RefCounted
# Fatebound Siege: real-time capture-the-Oracle. Pure simulation with no scene nodes, stepped at a
# fixed rate, so the same rules can later run on an authoritative server (M3) unchanged.
# Coordinates: Vector2(x, z) on the ground plane. Blue (team 0) holds the south end (+z),
# red (team 1) the north end (-z).

const TICK := 1.0 / 30.0
const HALF_W := 13.0
const HALF_L := 29.0
const UNIT_R := 0.45
const WIN_RESCUES := 2
const MATCH_TIME := 420.0
const RESPAWN_TIME := 5.0
const DROP_RETURN := 12.0
const FORGE_RADIUS := 2.4
const PICKUP_RADIUS := 1.5
const THRONE_RADIUS := 2.2
const ROLL_TIME := 0.7

const FACES := ["knight","barbarian","rogue","ranger","mage","fate"]
const UPGRADE_NAME := {"knight":"Paladin","barbarian":"Berserker","rogue":"Assassin","ranger":"Sniper","mage":"Archmage"}

# range: melee reach or projectile travel. arc: cosine of the half-angle a melee swing covers.
const CLASSES := {
	"villager": {"name":"Villager","hp":60,"speed":5.2,"dmg":8,"range":1.3,"arc":0.5,"windup":0.2,"recover":0.3,
		"ranged":false,"ability":"","ab_cd":0.0,"carry":0.62},
	"knight": {"name":"Knight","hp":150,"speed":4.6,"dmg":18,"range":1.7,"arc":0.4,"windup":0.24,"recover":0.4,
		"ranged":false,"ability":"bash","ab_cd":7.0,"carry":0.6},
	"barbarian": {"name":"Barbarian","hp":130,"speed":4.8,"dmg":26,"range":2.0,"arc":0.25,"windup":0.36,"recover":0.45,
		"ranged":false,"ability":"spin","ab_cd":7.0,"carry":0.6},
	"rogue": {"name":"Rogue","hp":85,"speed":6.2,"dmg":14,"range":1.4,"arc":0.5,"windup":0.13,"recover":0.22,
		"ranged":false,"ability":"lunge","ab_cd":5.0,"carry":0.76},
	"ranger": {"name":"Ranger","hp":80,"speed":5.4,"dmg":15,"range":11.0,"arc":0.0,"windup":0.3,"recover":0.45,
		"ranged":true,"proj_speed":22.0,"aoe":0.0,"ability":"volley","ab_cd":7.0,"carry":0.62},
	"mage": {"name":"Mage","hp":75,"speed":5.0,"dmg":20,"range":9.0,"arc":0.0,"windup":0.4,"recover":0.5,
		"ranged":true,"proj_speed":15.0,"aoe":1.6,"ability":"nova","ab_cd":8.0,"carry":0.62},
}

var time := 0.0
var ended := false
var winner := -1
var end_reason := ""
var units: Array = []
var by_id: Dictionary = {}
var projectiles: Array = []
var oracles: Array = []
var score := [0, 0]
var kills := [0, 0]
var events: Array = []
var obstacles: Array = []
var rng := RandomNumberGenerator.new()
var _ai_clock := 0.0
var _next_proj := 1

# ---------- map ----------
static func throne(team: int) -> Vector2:
	return Vector2(-3.0, 25.0) if team == 0 else Vector2(3.0, -25.0)

static func cell(team: int) -> Vector2:
	# Where a team's own Oracle is held captive: inside the ENEMY keep.
	return Vector2(3.0, -23.0) if team == 0 else Vector2(-3.0, 23.0)

static func forge(team: int) -> Vector2:
	return Vector2(7.5, 18.5) if team == 0 else Vector2(-7.5, -18.5)

static func spawn(team: int) -> Vector2:
	return Vector2(0.0, 21.0) if team == 0 else Vector2(0.0, -21.0)

func _build_obstacles() -> void:
	obstacles.clear()
	# Keeps sit behind each throne; rocks and trees break up the midfield into lanes.
	for t in 2:
		var s := 1.0 if t == 0 else -1.0
		obstacles.append({"p":Vector2(0*s, 28.2*s),"r":4.2,"kind":"keep"})
		obstacles.append({"p":Vector2(-8.5*s, 24.0*s),"r":1.6,"kind":"tower"})
		obstacles.append({"p":Vector2(8.5*s, 24.0*s),"r":1.6,"kind":"tower"})
		obstacles.append({"p":Vector2(-5.5*s, 9.0*s),"r":1.1,"kind":"rock"})
		obstacles.append({"p":Vector2(6.0*s, 11.5*s),"r":1.2,"kind":"tree"})
		obstacles.append({"p":Vector2(-10.0*s, 14.0*s),"r":1.2,"kind":"tree"})
		obstacles.append({"p":Vector2(2.2*s, 5.0*s),"r":0.9,"kind":"rock"})
	obstacles.append({"p":Vector2(0, 0),"r":1.8,"kind":"ruin"})
	obstacles.append({"p":Vector2(-9.0, 0.5),"r":1.3,"kind":"tree"})
	obstacles.append({"p":Vector2(9.0, -0.5),"r":1.3,"kind":"tree"})

# ---------- setup ----------
func setup(team_size: int, seed_value: int, player_team := 0) -> void:
	rng.seed = seed_value
	_build_obstacles()
	oracles = [_new_oracle(0), _new_oracle(1)]
	var roles := ["raid","defend","raid","escort","raid","defend","escort","raid","defend","raid"]
	for t in 2:
		for i in team_size:
			var human := t == player_team and i == 0
			var id := "you" if human else "%s%d" % ["b" if t == 0 else "r", i]
			var u := _new_unit(id, t, not human, roles[i % roles.size()])
			units.append(u)
			by_id[id] = u
			_respawn(u, true)

func _new_oracle(team: int) -> Dictionary:
	return {"team":team,"state":"cell","pos":cell(team),"carrier":"","dropped_at":0.0}

func _new_unit(id: String, team: int, bot: bool, role: String) -> Dictionary:
	return {"id":id,"team":team,"bot":bot,"role":role,"cls":"villager","up":false,"hp":60.0,"max_hp":60.0,
		"pos":Vector2.ZERO,"face":0.0,"move":Vector2.ZERO,"state":"idle","t":0.0,"atk":"","cd_dodge":0.0,
		"cd_ability":0.0,"stun":0.0,"carrying":false,"respawn_at":0.0,"kills":0,"deaths":0,"rescues":0,
		"dodge_dir":Vector2.ZERO,"target":"","forge":{"open":false,"faces":["fate","fate","fate"],"held":[false,false,false],
		"rolling":0.0,"rolled":false},"ai_goal":Vector2.ZERO,"lunge_hit":false,
		"unstick":0.0,"unstick_dir":Vector2.ZERO,"stuck_t":0.0,"last_pos":Vector2.ZERO}

func stat(u: Dictionary, key: String) -> Variant:
	var base: Variant = CLASSES[u.cls][key]
	if u.up and key in ["hp","dmg"]:
		return float(base) * 1.25
	return base

func class_label(u: Dictionary) -> String:
	return UPGRADE_NAME.get(u.cls,"") if u.up else str(CLASSES[u.cls].name)

func _respawn(u: Dictionary, first := false) -> void:
	var sp := spawn(u.team)
	u.pos = sp + Vector2(rng.randf_range(-3.5,3.5), rng.randf_range(-1.2,1.2))
	u.face = PI if u.team == 0 else 0.0
	u.max_hp = float(stat(u,"hp"))
	u.hp = u.max_hp
	u.state = "idle"
	u.t = 0.0
	u.stun = 0.0
	u.carrying = false
	u.forge.open = false
	if not first:
		_event("spawn", {"id":u.id})

func _event(kind: String, data: Dictionary) -> void:
	data["k"] = kind
	data["at"] = time
	events.append(data)

func drain_events() -> Array:
	var out := events
	events = []
	return out

# ---------- helpers ----------
static func dir_of(angle: float) -> Vector2:
	# Facing angle uses the same convention as a Node3D's rotation.y looking down +z.
	return Vector2(sin(angle), cos(angle))

static func angle_of(v: Vector2) -> float:
	return atan2(v.x, v.y)

func alive(u: Dictionary) -> bool:
	return u.state != "dead"

func enemies_of(u: Dictionary) -> Array:
	return units.filter(func(o): return o.team != u.team and alive(o))

func nearest_enemy(u: Dictionary, max_d: float, prefer_front := false) -> Dictionary:
	var best := {}
	var best_score := INF
	var fwd := dir_of(u.face)
	for o in units:
		if o.team == u.team or not alive(o):
			continue
		var off: Vector2 = o.pos - u.pos
		var d := off.length()
		if d > max_d:
			continue
		var s := d
		if prefer_front and d > 0.01:
			s += (1.0 - fwd.dot(off / d)) * 2.0
		if s < best_score:
			best_score = s
			best = o
	return best

func oracle_carrier(team: int) -> Dictionary:
	var o: Dictionary = oracles[team]
	return by_id.get(o.carrier, {}) if o.state == "carried" else {}

# ---------- input (from HUD or bot brain) ----------
func act(id: String, action: String, arg: Variant = null) -> bool:
	var u: Dictionary = by_id.get(id, {})
	if u.is_empty() or ended or not alive(u):
		return false
	match action:
		"attack": return _start_attack(u, "attack")
		"ability": return _start_attack(u, "ability")
		"dodge": return _dodge(u)
		"interact": return _interact(u)
		"forge_roll": return _forge_roll(u, arg)
		"forge_take": return _forge_take(u)
		"forge_leave":
			u.forge.open = false
			return true
	return false

func set_move(id: String, v: Vector2) -> void:
	var u: Dictionary = by_id.get(id, {})
	if not u.is_empty():
		u.move = v.limit_length(1.0)

func can_act(u: Dictionary) -> bool:
	return alive(u) and u.stun <= 0.0 and u.state in ["idle","move"] and not u.forge.open

func _aim(u: Dictionary, reach: float) -> void:
	var target := nearest_enemy(u, reach, true)
	if not target.is_empty():
		u.face = angle_of(target.pos - u.pos)

func _start_attack(u: Dictionary, kind: String) -> bool:
	if not can_act(u) or u.carrying:
		return false
	if kind == "ability":
		if CLASSES[u.cls].ability == "" or u.cd_ability > 0.0:
			return false
		u.cd_ability = float(CLASSES[u.cls].ab_cd)
	var reach := float(stat(u,"range")) * (1.0 if CLASSES[u.cls].ranged else 1.9)
	if kind == "ability" and CLASSES[u.cls].ability == "lunge":
		reach = 6.0
	_aim(u, reach)
	u.state = "wind"
	u.atk = kind
	u.t = float(stat(u,"windup")) * (1.3 if kind == "ability" else 1.0)
	u.lunge_hit = false
	_event("attack", {"id":u.id,"kind":kind,"ability":CLASSES[u.cls].ability if kind == "ability" else ""})
	return true

func _dodge(u: Dictionary) -> bool:
	if not alive(u) or u.stun > 0.0 or u.carrying or u.cd_dodge > 0.0 or u.state in ["wind","dodge"] or u.forge.open:
		return false
	var d: Vector2 = u.move if u.move.length() > 0.2 else dir_of(u.face)
	u.dodge_dir = d.normalized()
	u.face = angle_of(u.dodge_dir)
	u.state = "dodge"
	u.t = 0.3
	u.cd_dodge = 2.2
	_event("dodge", {"id":u.id})
	return true

func _interact(u: Dictionary) -> bool:
	if u.stun > 0.0 or not u.state in ["idle","move"]:
		return false
	if u.carrying:
		_release_oracle(u, true)
		return true
	var mine: Dictionary = oracles[u.team]
	if mine.state in ["cell","dropped"] and u.pos.distance_to(mine.pos) <= PICKUP_RADIUS:
		mine.state = "carried"
		mine.carrier = u.id
		u.carrying = true
		u.forge.open = false
		_event("pickup", {"id":u.id,"team":u.team})
		return true
	if u.pos.distance_to(forge(u.team)) <= FORGE_RADIUS:
		u.forge.open = true
		u.forge.rolled = false
		u.forge.held = [false,false,false]
		return true
	return false

func context_action(u: Dictionary) -> String:
	# What the ACTION button does right now, for the HUD label.
	if not alive(u):
		return ""
	if u.carrying:
		return "throw"
	var mine: Dictionary = oracles[u.team]
	if mine.state in ["cell","dropped"] and u.pos.distance_to(mine.pos) <= PICKUP_RADIUS:
		return "grab"
	if u.pos.distance_to(forge(u.team)) <= FORGE_RADIUS:
		return "forge"
	return ""

# ---------- forge dice ----------
func _forge_roll(u: Dictionary, held: Variant) -> bool:
	var f: Dictionary = u.forge
	if not f.open or f.rolling > 0.0 or u.pos.distance_to(forge(u.team)) > FORGE_RADIUS + 0.6:
		return false
	if held is Array and f.rolled:
		for i in 3:
			f.held[i] = bool(held[i])
	else:
		f.held = [false,false,false]
	for i in 3:
		if not f.held[i]:
			f.faces[i] = FACES[rng.randi() % FACES.size()]
	f.rolling = ROLL_TIME
	f.rolled = true
	u.state = "idle"
	_event("forge_roll", {"id":u.id,"faces":f.faces.duplicate()})
	return true

static func forge_result(faces: Array) -> Dictionary:
	# Pair of a class (fate faces are wild) grants it; three of a kind grants the upgraded form.
	var wild := faces.count("fate")
	var best := ""
	var best_n := 0
	for c in ["knight","barbarian","rogue","ranger","mage"]:
		var n: int = faces.count(c)
		if n > best_n:
			best_n = n
			best = c
	if best == "":
		return {"cls":"", "up":false, "n":wild}
	var total := best_n + wild
	return {"cls":best if total >= 2 else "", "up":total >= 3, "n":total}

func _forge_take(u: Dictionary) -> bool:
	var f: Dictionary = u.forge
	if not f.open or f.rolling > 0.0 or not f.rolled:
		return false
	var r := forge_result(f.faces)
	if r.cls == "" and f.faces.count("fate") == 3:
		r = {"cls":FACES[rng.randi() % 5], "up":true}
	if r.cls == "":
		return false
	var ratio: float = u.hp / maxf(1.0, u.max_hp)
	u.cls = r.cls
	u.up = r.up
	u.max_hp = float(stat(u,"hp"))
	u.hp = maxf(1.0, u.max_hp * maxf(ratio, 0.75))
	u.cd_ability = 0.0
	f.open = false
	_event("class", {"id":u.id,"cls":u.cls,"up":u.up})
	return true

# ---------- damage ----------
func _damage(src: Dictionary, dst: Dictionary, amount: float, stun := 0.0) -> void:
	if not alive(dst) or dst.state == "dodge":
		return
	dst.hp -= amount
	if stun > 0.0:
		dst.stun = maxf(dst.stun, stun)
	_event("hit", {"id":dst.id,"by":src.get("id",""),"dmg":int(round(amount))})
	if dst.hp <= 0.0:
		_kill(src, dst)

func _kill(src: Dictionary, dst: Dictionary) -> void:
	if dst.carrying:
		_release_oracle(dst, false)
	dst.hp = 0.0
	dst.state = "dead"
	dst.forge.open = false
	dst.respawn_at = time + RESPAWN_TIME
	dst.deaths += 1
	if not src.is_empty() and src.has("team"):
		kills[src.team] += 1
		if src.has("kills"):
			src.kills += 1
	_event("death", {"id":dst.id,"by":src.get("id","")})

func _release_oracle(u: Dictionary, thrown: bool) -> void:
	var o: Dictionary = oracles[u.team]
	u.carrying = false
	o.state = "dropped"
	o.carrier = ""
	o.dropped_at = time
	var p: Vector2 = u.pos
	if thrown:
		p += dir_of(u.face) * 4.5
	o.pos = _clamp_to_field(_push_out(p, 0.6))
	_event("drop", {"team":u.team,"thrown":thrown,"id":u.id})

func _melee(u: Dictionary, reach: float, arc: float, dmg: float, stun := 0.0) -> int:
	var fwd := dir_of(u.face)
	var hits := 0
	for o in units:
		if o.team == u.team or not alive(o):
			continue
		var off: Vector2 = o.pos - u.pos
		var d := off.length()
		if d > reach + UNIT_R:
			continue
		if arc > -1.0 and d > 0.3 and fwd.dot(off / d) < arc:
			continue
		_damage(u, o, dmg, stun)
		hits += 1
	return hits

func _shoot(u: Dictionary, angle: float, dmg: float, aoe: float, speed: float, reach: float) -> void:
	var d := dir_of(angle)
	projectiles.append({"id":_next_proj,"team":u.team,"owner":u.id,"pos":u.pos + d*0.6,"vel":d*speed,
		"dmg":dmg,"aoe":aoe,"life":reach/speed,"kind":"fire" if aoe > 0.0 else "arrow"})
	_event("proj", {"pid":_next_proj,"kind":"fire" if aoe > 0.0 else "arrow"})
	_next_proj += 1

func _resolve_attack(u: Dictionary) -> void:
	var c: Dictionary = CLASSES[u.cls]
	var dmg := float(stat(u,"dmg"))
	if u.atk == "attack":
		if c.ranged:
			_shoot(u, u.face, dmg, float(c.aoe), float(c.proj_speed), float(c.range))
		else:
			_melee(u, float(c.range), float(c.arc), dmg)
		return
	match str(c.ability):
		"bash":
			_melee(u, 2.3, 0.3, dmg*0.7, 1.3)
		"spin":
			_melee(u, 2.8, -2.0, dmg*1.15)
		"volley":
			for i in 5:
				_shoot(u, u.face + (i-2)*0.13, dmg*0.8, 0.0, float(c.proj_speed), float(c.range))
		"nova":
			_melee(u, 3.3, -2.0, dmg*1.4)
			_event("nova", {"id":u.id})

# ---------- stepping ----------
func step(dt: float = TICK) -> void:
	if ended:
		return
	time += dt
	_ai_clock += dt
	if _ai_clock >= 0.15:
		_ai_clock = 0.0
		for u in units:
			if u.bot:
				_think(u)
	for u in units:
		_step_unit(u, dt)
	_separate()
	_step_projectiles(dt)
	_step_oracles(dt)
	if time >= MATCH_TIME:
		_finish("time")

func _step_unit(u: Dictionary, dt: float) -> void:
	if u.state == "dead":
		if time >= u.respawn_at:
			_respawn(u)
		return
	u.cd_dodge = maxf(0.0, u.cd_dodge - dt)
	u.cd_ability = maxf(0.0, u.cd_ability - dt)
	var f: Dictionary = u.forge
	if f.rolling > 0.0:
		f.rolling = maxf(0.0, f.rolling - dt)
	if f.open and u.pos.distance_to(forge(u.team)) > FORGE_RADIUS + 0.8:
		f.open = false
	if u.stun > 0.0:
		u.stun -= dt
		return
	var speed := float(stat(u,"speed"))
	match u.state:
		"wind":
			u.t -= dt
			if CLASSES[u.cls].ability == "lunge" and u.atk == "ability":
				u.pos += dir_of(u.face) * 15.0 * dt
				if not u.lunge_hit:
					var hit := _melee(u, 1.1, 0.2, float(stat(u,"dmg"))*2.0)
					u.lunge_hit = hit > 0
			if u.t <= 0.0:
				if not (CLASSES[u.cls].ability == "lunge" and u.atk == "ability"):
					_resolve_attack(u)
				u.state = "recover"
				u.t = float(stat(u,"recover"))
			return
		"recover":
			u.t -= dt
			u.pos += u.move * speed * 0.25 * dt
			if u.t <= 0.0:
				u.state = "idle"
			return
		"dodge":
			u.t -= dt
			u.pos += u.dodge_dir * 13.0 * dt
			if u.t <= 0.0:
				u.state = "idle"
			return
	if f.open:
		u.state = "idle"
		return
	var mult := float(CLASSES[u.cls].carry) if u.carrying else 1.0
	if u.move.length() > 0.08:
		u.pos += u.move * speed * mult * dt
		u.face = lerp_angle(u.face, angle_of(u.move), minf(1.0, dt*14.0))
		u.state = "move"
	else:
		u.state = "idle"

func _push_out(p: Vector2, r: float) -> Vector2:
	for ob in obstacles:
		var off: Vector2 = p - ob.p
		var min_d: float = ob.r + r
		var d := off.length()
		if d < min_d:
			p = ob.p + (off / d if d > 0.001 else Vector2(1,0)) * min_d
	return p

func _clamp_to_field(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, -HALF_W, HALF_W), clampf(p.y, -HALF_L, HALF_L))

func _separate() -> void:
	for i in units.size():
		var a: Dictionary = units[i]
		if not alive(a):
			continue
		for j in range(i+1, units.size()):
			var b: Dictionary = units[j]
			if not alive(b):
				continue
			var off: Vector2 = b.pos - a.pos
			var d := off.length()
			if d < UNIT_R*2.0 and d > 0.0001:
				var push := off / d * (UNIT_R*2.0 - d) * 0.5
				a.pos -= push
				b.pos += push
	for u in units:
		if alive(u):
			u.pos = _clamp_to_field(_push_out(u.pos, UNIT_R))

func _step_projectiles(dt: float) -> void:
	for i in range(projectiles.size()-1, -1, -1):
		var p: Dictionary = projectiles[i]
		p.pos += p.vel * dt
		p.life -= dt
		var hit := {}
		for o in units:
			if o.team != p.team and alive(o) and o.pos.distance_to(p.pos) < UNIT_R + 0.25:
				hit = o
				break
		var blocked := false
		for ob in obstacles:
			if p.pos.distance_to(ob.p) < ob.r:
				blocked = true
				break
		if hit.is_empty() and not blocked and p.life > 0.0 and absf(p.pos.x) < HALF_W + 2 and absf(p.pos.y) < HALF_L + 2:
			continue
		var owner: Dictionary = by_id.get(p.owner, {"team":p.team})
		if p.aoe > 0.0:
			for o in units:
				if o.team != p.team and alive(o) and o.pos.distance_to(p.pos) <= p.aoe:
					_damage(owner, o, p.dmg * (1.0 if o == hit else 0.6))
			_event("boom", {"pos":p.pos})
		elif not hit.is_empty():
			_damage(owner, hit, p.dmg)
		_event("proj_end", {"pid":p.id})
		projectiles.remove_at(i)

func _step_oracles(dt: float) -> void:
	for t in 2:
		var o: Dictionary = oracles[t]
		match o.state:
			"carried":
				var c: Dictionary = by_id.get(o.carrier, {})
				if c.is_empty() or not alive(c):
					o.state = "dropped"
					o.dropped_at = time
					continue
				o.pos = c.pos
				if c.pos.distance_to(throne(t)) <= THRONE_RADIUS:
					score[t] += 1
					c.rescues += 1
					c.carrying = false
					oracles[t] = _new_oracle(t)
					_event("rescue", {"team":t,"id":c.id})
					if score[t] >= WIN_RESCUES:
						_finish("rescue")
			"dropped":
				# Captors touching a loose Oracle drag her straight back to the cell.
				for u in units:
					if u.team != t and alive(u) and u.pos.distance_to(o.pos) <= PICKUP_RADIUS:
						oracles[t] = _new_oracle(t)
						_event("recaptured", {"team":t,"id":u.id})
						break
				if oracles[t].state == "dropped" and time - float(o.dropped_at) >= DROP_RETURN:
					oracles[t] = _new_oracle(t)
					_event("recaptured", {"team":t,"id":""})

func _finish(reason: String) -> void:
	ended = true
	end_reason = reason
	if score[0] != score[1]:
		winner = 0 if score[0] > score[1] else 1
	elif kills[0] != kills[1]:
		winner = 0 if kills[0] > kills[1] else 1
	else:
		winner = -1
	_event("end", {"winner":winner,"reason":reason})

# ---------- bots ----------
func _move_toward(u: Dictionary, goal: Vector2, stop := 0.4) -> void:
	var off: Vector2 = goal - u.pos
	if off.length() <= stop:
		u.move = Vector2.ZERO
		return
	if u.unstick > 0.0:
		u.move = u.unstick_dir
		return
	var d := off.normalized()
	# Slide around obstacles: steer along the tangent on the side closer to the goal.
	var steer := Vector2.ZERO
	for ob in obstacles:
		var to: Vector2 = ob.p - u.pos
		var dist := to.length()
		var clear: float = dist - ob.r - UNIT_R
		if clear < 2.2 and dist > 0.01 and to.dot(d) > 0.0 and dist < off.length() + ob.r:
			var tangent := Vector2(-to.y, to.x) / dist
			if tangent.dot(d) < 0.0:
				tangent = -tangent
			var w := clampf(1.0 - clear / 2.2, 0.0, 1.0)
			steer += tangent * w * 1.6 - to / dist * w * 0.4
	u.move = (d + steer).normalized()

func _bot_forge(u: Dictionary) -> void:
	var f: Dictionary = u.forge
	u.move = Vector2.ZERO
	if not f.open:
		_interact(u)
		return
	if f.rolling > 0.0:
		return
	if f.rolled:
		var r := forge_result(f.faces)
		if r.cls != "" or f.faces.count("fate") == 3:
			_forge_take(u)
			return
		var held := [false,false,false]
		for i in 3:
			if f.faces[i] == "fate":
				held[i] = true
		_forge_roll(u, held)
	else:
		_forge_roll(u, null)

func _think(u: Dictionary) -> void:
	if not alive(u) or u.stun > 0.0 or u.state in ["wind","recover","dodge"]:
		return
	# Unstick: if a bot wanted to move but barely did, sidestep for a moment.
	u.unstick = maxf(0.0, u.unstick - 0.15)
	if u.move.length() > 0.1 and not u.forge.open and u.pos.distance_to(u.last_pos) < 0.12:
		u.stuck_t += 0.15
		if u.stuck_t >= 0.6:
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			u.unstick_dir = (Vector2(-u.move.y, u.move.x) * side - u.move * 0.3).normalized()
			u.unstick = 0.7
			u.stuck_t = 0.0
	else:
		u.stuck_t = 0.0
	u.last_pos = u.pos
	if u.cls == "villager" and not u.carrying:
		var fg := forge(u.team)
		if u.pos.distance_to(fg) <= FORGE_RADIUS - 0.4:
			_bot_forge(u)
		else:
			u.forge.open = false
			_move_toward(u, fg, 0.6)
		return
	var c: Dictionary = CLASSES[u.cls]
	var mine: Dictionary = oracles[u.team]
	var theirs: Dictionary = oracles[1 - u.team]
	if u.carrying:
		# Run home; pass to a faster teammate isn't worth the risk for a bot.
		_move_toward(u, throne(u.team), 0.2)
		return
	var goal: Vector2 = u.pos
	var enemy_carrier := oracle_carrier(1 - u.team)
	var ally_carrier := oracle_carrier(u.team)
	if not enemy_carrier.is_empty() and (u.role == "defend" or u.pos.distance_to(enemy_carrier.pos) < 14.0):
		goal = enemy_carrier.pos
	elif mine.state in ["cell","dropped"] and u.role in ["raid","escort"]:
		goal = mine.pos
	elif not ally_carrier.is_empty():
		goal = ally_carrier.pos + dir_of(u.face) * 1.5
	elif u.role == "defend":
		goal = theirs.pos + Vector2(0, -3.0 if u.team == 1 else 3.0)
	else:
		goal = mine.pos
	# Raiders only fight what blocks them; defenders and escorts hunt more widely.
	var aggro := {"raid":3.5,"escort":6.5,"defend":8.0}.get(u.role, 6.0) as float
	if c.ranged:
		aggro = maxf(aggro, float(c.range) * (0.6 if u.role == "raid" else 0.95))
	var foe := nearest_enemy(u, aggro)
	if not enemy_carrier.is_empty() and u.pos.distance_to(enemy_carrier.pos) < aggro + 3.0:
		foe = enemy_carrier
	if u.hp < u.max_hp * 0.3 and not foe.is_empty() and u.cd_dodge <= 0.0 and rng.randf() < 0.25:
		u.move = (u.pos - foe.pos).normalized()
		_dodge(u)
		return
	if not foe.is_empty():
		var d: float = u.pos.distance_to(foe.pos)
		var reach := float(c.range)
		if c.ranged:
			if d < reach * 0.45:
				u.move = (u.pos - foe.pos).normalized()
			elif d > reach * 0.85:
				_move_toward(u, foe.pos, 0.5)
			else:
				u.move = Vector2.ZERO
			if d <= reach * 0.9:
				u.face = angle_of(foe.pos - u.pos)
				if u.cd_ability <= 0.0 and rng.randf() < 0.35:
					_start_attack(u, "ability")
				else:
					_start_attack(u, "attack")
			return
		if d <= reach + UNIT_R + 0.1:
			u.move = Vector2.ZERO
			u.face = angle_of(foe.pos - u.pos)
			var ab := str(c.ability)
			var crowd := _melee_count(u, 2.8)
			if u.cd_ability <= 0.0 and ((ab == "spin" and crowd >= 2) or ab == "bash" or rng.randf() < 0.3):
				_start_attack(u, "ability")
			else:
				_start_attack(u, "attack")
			return
		if str(c.ability) == "lunge" and d < 5.5 and u.cd_ability <= 0.0:
			u.face = angle_of(foe.pos - u.pos)
			_start_attack(u, "ability")
			return
		_move_toward(u, foe.pos, reach * 0.8)
		return
	# Pick up the Oracle when standing on her.
	if mine.state in ["cell","dropped"] and u.pos.distance_to(mine.pos) <= PICKUP_RADIUS:
		_interact(u)
		return
	_move_toward(u, goal, 0.8)

func _melee_count(u: Dictionary, r: float) -> int:
	var n := 0
	for o in units:
		if o.team != u.team and alive(o) and o.pos.distance_to(u.pos) <= r:
			n += 1
	return n
