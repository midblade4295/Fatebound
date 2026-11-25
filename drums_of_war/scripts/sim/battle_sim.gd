extends RefCounted
## Drums of War battle rules.
##
## Pure data: no nodes, no engine clock, no engine RNG. Call tick() to advance by DT seconds.
## The same seed and the same deploy commands always give the same battle, which is what the
## headless tests, the bot and (later) replays and online play rely on.
##
## Coordinates are in paces. Side 0's base sits at low y, side 1's at high y. The creek runs
## across the middle and can only be crossed at one bridge and two fords.

const GsRng = preload("res://scripts/sim/sim_rng.gd")

# --- Clock -------------------------------------------------------------------------------
const TICK_RATE := 20
const DT := 1.0 / 20.0

# --- Field -------------------------------------------------------------------------------
const FIELD_W := 18.0
const FIELD_H := 32.0
const CREEK_Y0 := 15.0
const CREEK_Y1 := 17.0
const CROSSINGS := [
	{"x": 3.0, "half": 1.5, "ford": true},
	{"x": 9.0, "half": 1.2, "ford": false},
	{"x": 15.0, "half": 1.5, "ford": true},
]
const DEPLOY_DEPTH := 14.0          # how far from your own baseline you may deploy
const DEPLOY_DEPTH_OPEN := 22.0     # ... on a flank whose enemy redoubt has fallen
const FORD_SPEED_MULT := 0.6

# --- Match -------------------------------------------------------------------------------
const MATCH_TIME := 180.0
const OVERTIME := 60.0
const DOUBLE_POWDER_TIME := 60.0    # the last minute of regular time, and all of overtime
const POWDER_MAX := 10.0
const POWDER_START := 5.0
const POWDER_PERIOD := 2.8          # seconds per point of Powder
const HAND_SIZE := 4

# --- Combat tuning -----------------------------------------------------------------------
const FIRST_VOLLEY_MULT := 1.5
const MORALE_K := 1.3               # morale lost per percent of strength lost
const FLANK_MORALE_MULT := 1.5
const MORALE_REST := 4.0            # seconds without being hit before nerve recovers
const MORALE_REGEN := 3.0           # per second
const ROUT_DAMAGE_MULT := 1.5
const ROUT_SPEED_MULT := 1.3
const RALLY_DIST := 3.0
const RALLY_TIME := 2.0
const RALLY_MORALE := 0.5
const SQUARE_DETECT := 6.5
const SQUARE_FORM_TIME := 1.5
const SQUARE_FORM_TIME_RELOADING := 2.5
const SQUARE_RELEASE_DIST := 8.0
const SQUARE_RELEASE_TIME := 1.0
const SQUARE_FIRE_FRACTION := 0.5
const SQUARE_REPEL_DMG := 60.0
const SQUARE_REPEL_SHOCK := 25.0
const CONTACT := 1.3
const CHARGE_RUNUP := 2.5
const CAV_AGGRO := 7.5
const CAV_RECOIL_TIME := 1.6
const LOOSE_MUSKET_MULT := 0.7
const LOOSE_SHOT_MULT := 0.4
const COLUMN_SHOT_MULT := 1.5
const SQUARE_SHOT_MULT := 2.0
const SHOT_PIERCE_MULT := 0.5
const SHOT_PIERCE_WIDTH := 0.9
const STRUCT_MUSKET_MULT := 0.8
const STRUCT_SHOT_MULT := 0.6
const STRUCT_MELEE_MULT := 0.5
const SEPARATION := 1.4

const REDOUBT_HP := 900.0
const REDOUBT_RANGE := 8.5
const REDOUBT_DMG := 50.0
const REDOUBT_PERIOD := 2.5
const HQ_HP := 2000.0
const HQ_RANGE := 6.5
const HQ_DMG := 50.0
const HQ_PERIOD := 2.0

enum { ST_MARCH, ST_FORMING, ST_SQUARE, ST_ROUT }
enum { PHASE_REGULAR, PHASE_OVERTIME, PHASE_OVER }
const NO_WINNER := -1
const DRAW := 2


class Regiment extends RefCounted:
	var id: int
	var side: int
	var card_id: String
	var def: Dictionary
	var arm: String
	var lane: int
	var pos: Vector2
	var facing: Vector2
	var hp: float
	var max_hp: float
	var men: int
	var men_max: int
	var men_tick: int            # strength at the start of this tick; volleys use it so both sides fire fairly
	var morale: float
	var morale_max: float
	var state: int = 0
	var formation: String = "column"
	var reload: float = 0.0
	var fired_first: bool = false
	var form_timer: float = 0.0
	var release_timer: float = 0.0
	var runup: float = 0.0
	var recoil: float = 0.0
	var since_hit: float = 99.0
	var life: float = -1.0       # guns only: seconds of ammunition left
	var rally_timer: float = 0.0
	var in_melee: bool = false
	var dead: bool = false


class Structure extends RefCounted:
	var id: int
	var side: int
	var kind: String             # "hq" or "redoubt"
	var flank: int               # 0 = low-x flank, 1 = high-x flank, -1 for the headquarters
	var pos: Vector2
	var radius: float
	var hp: float
	var max_hp: float
	var gun_range: float
	var gun_dmg: float
	var gun_period: float
	var reload: float = 0.0
	var dead: bool = false


var rng: GsRng
var cards: Dictionary
var tick_count: int = 0
var time: float = 0.0
var phase: int = PHASE_REGULAR
var winner: int = NO_WINNER
var powder: Array = [POWDER_START, POWDER_START]
var decks: Array = [[], []]
var regiments: Array = []
var structures: Array = []
var events: Array = []           # things the view may want to show; safe to clear at any time
var command_log: Array = []      # every accepted deploy, for replays and determinism checks
var _next_id: int = 1
var _deferring: bool = false   # while regiments act, hits are queued so that order of acting gives no edge
var _pending: Array = []


static func load_cards(path: String = "res://data/cards.json") -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open card data: " + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Card data is not a JSON object: " + path)
		return {}
	return parsed


func _init(seed_value: int, card_defs: Dictionary, deck0: Array, deck1: Array) -> void:
	rng = GsRng.new(seed_value)
	cards = card_defs
	decks = [deck0.duplicate(), deck1.duplicate()]
	rng.shuffle(decks[0])
	rng.shuffle(decks[1])
	for side in 2:
		_add_structure(side, "hq", -1, Vector2(9.0, 2.5), 1.6, HQ_HP, HQ_RANGE, HQ_DMG, HQ_PERIOD)
		_add_structure(side, "redoubt", 0, Vector2(3.5, 6.5), 1.2, REDOUBT_HP, REDOUBT_RANGE, REDOUBT_DMG, REDOUBT_PERIOD)
		_add_structure(side, "redoubt", 1, Vector2(14.5, 6.5), 1.2, REDOUBT_HP, REDOUBT_RANGE, REDOUBT_DMG, REDOUBT_PERIOD)


func _add_structure(side: int, kind: String, flank: int, local_pos: Vector2, radius: float,
		hp: float, gun_range: float, gun_dmg: float, gun_period: float) -> void:
	var s := Structure.new()
	s.id = _next_id
	_next_id += 1
	s.side = side
	s.kind = kind
	s.flank = flank
	s.pos = local_pos if side == 0 else Vector2(local_pos.x, FIELD_H - local_pos.y)
	s.radius = radius
	s.hp = hp
	s.max_hp = hp
	s.gun_range = gun_range
	s.gun_dmg = gun_dmg
	s.gun_period = gun_period
	structures.append(s)


# ==========================================================================================
# Queries
# ==========================================================================================

static func fwd(side: int) -> float:
	return 1.0 if side == 0 else -1.0


## Distance from a side's own baseline.
static func local_y(side: int, y: float) -> float:
	return y if side == 0 else FIELD_H - y


static func from_local(side: int, p: Vector2) -> Vector2:
	return p if side == 0 else Vector2(p.x, FIELD_H - p.y)


func hand(side: int) -> Array:
	return decks[side].slice(0, HAND_SIZE)


func next_card(side: int) -> String:
	return decks[side][HAND_SIZE] if decks[side].size() > HAND_SIZE else ""


func card_cost(card_id: String) -> int:
	return int(cards[card_id]["cost"])


func double_powder() -> bool:
	return time >= MATCH_TIME - DOUBLE_POWDER_TIME


func time_left() -> float:
	if phase == PHASE_REGULAR:
		return maxf(0.0, MATCH_TIME - time)
	return maxf(0.0, MATCH_TIME + OVERTIME - time)


func hq(side: int) -> Structure:
	for s: Structure in structures:
		if s.side == side and s.kind == "hq":
			return s
	return null


func redoubt(side: int, flank: int) -> Structure:
	for s: Structure in structures:
		if s.side == side and s.kind == "redoubt" and s.flank == flank:
			return s
	return null


func redoubts_lost(side: int) -> int:
	var n := 0
	for s: Structure in structures:
		if s.side == side and s.kind == "redoubt" and s.dead:
			n += 1
	return n


func deploy_depth(side: int, x: float) -> float:
	var flank := 0 if x < FIELD_W * 0.5 else 1
	var enemy_redoubt := redoubt(1 - side, flank)
	return DEPLOY_DEPTH_OPEN if enemy_redoubt != null and enemy_redoubt.dead else DEPLOY_DEPTH


static func in_creek(y: float) -> bool:
	return y > CREEK_Y0 and y < CREEK_Y1


static func crossing_at(x: float) -> Dictionary:
	for c: Dictionary in CROSSINGS:
		if absf(x - float(c["x"])) <= float(c["half"]):
			return c
	return {}


static func in_ford_water(p: Vector2) -> bool:
	if not in_creek(p.y):
		return false
	var c := crossing_at(p.x)
	return not c.is_empty() and bool(c["ford"])


## Why a card cannot be played there, or "" if it can.
func deploy_error(side: int, hand_index: int, pos: Vector2) -> String:
	if phase == PHASE_OVER:
		return "The battle is over"
	if hand_index < 0 or hand_index >= HAND_SIZE or hand_index >= decks[side].size():
		return "No such card"
	var card_id: String = decks[side][hand_index]
	var def: Dictionary = cards[card_id]
	if powder[side] + 0.0001 < float(def["cost"]):
		return "Not enough Powder"
	if pos.x < 0.5 or pos.x > FIELD_W - 0.5 or pos.y < 0.5 or pos.y > FIELD_H - 0.5:
		return "Off the field"
	if def["type"] == "order":
		if card_id == "fire" and _order_fire_target(side, pos, float(def["radius"])) == null:
			return "No regiment there to give the order to"
		if card_id == "rally" and _order_rally_targets(side, pos, float(def["radius"])).is_empty():
			return "No regiment there to rally"
		return ""
	if in_creek(pos.y):
		return "Cannot deploy in the creek"
	if local_y(side, pos.y) > deploy_depth(side, pos.x):
		return "Too far forward"
	return ""


func deploy(side: int, hand_index: int, pos: Vector2) -> bool:
	if deploy_error(side, hand_index, pos) != "":
		return false
	var deck: Array = decks[side]
	var card_id: String = deck[hand_index]
	var def: Dictionary = cards[card_id]
	powder[side] -= float(def["cost"])
	# The next card slides into the slot just played; the played card goes to the back.
	if deck.size() > HAND_SIZE:
		deck[hand_index] = deck[HAND_SIZE]
		deck.remove_at(HAND_SIZE)
		deck.append(card_id)
	command_log.append({"tick": tick_count, "side": side, "card": card_id, "x": pos.x, "y": pos.y})
	if def["type"] == "order":
		_play_order(side, card_id, def, pos)
	else:
		spawn(side, card_id, pos)
	return true


## Puts a regiment straight onto the field. deploy() uses it; tests use it to set up scenes.
func spawn(side: int, card_id: String, pos: Vector2) -> Regiment:
	var def: Dictionary = cards[card_id]
	var r := Regiment.new()
	r.id = _next_id
	_next_id += 1
	r.side = side
	r.card_id = card_id
	r.def = def
	r.arm = def["arm"]
	r.pos = pos
	r.facing = Vector2(0.0, fwd(side))
	r.lane = 0 if pos.x < 6.0 else (2 if pos.x > 12.0 else 1)
	r.men_max = int(def["men"])
	r.men = r.men_max
	r.men_tick = r.men
	r.max_hp = float(def["hp_per_man"]) * r.men_max
	r.hp = r.max_hp
	r.morale_max = float(def["morale"])
	r.morale = r.morale_max
	r.life = float(def.get("life", -1.0))
	if r.arm == "artillery":
		r.formation = "line"
	regiments.append(r)
	events.append({"type": "deploy", "pos": pos, "side": side, "card": card_id})
	return r


func state_hash() -> int:
	var parts := PackedStringArray()
	parts.append("%d|%d|%d|%.4f|%.4f" % [tick_count, phase, winner, powder[0], powder[1]])
	for r: Regiment in regiments:
		parts.append("%d:%d:%s:%.4f:%.4f:%.3f:%.3f:%d" % [r.id, r.side, r.card_id, r.pos.x, r.pos.y, r.hp, r.morale, r.state])
	for s: Structure in structures:
		parts.append("%d:%.3f" % [s.id, s.hp])
	return "|".join(parts).hash()


# ==========================================================================================
# Tick
# ==========================================================================================

func tick() -> void:
	if phase == PHASE_OVER:
		return
	tick_count += 1
	time = tick_count * DT
	var gain := DT / POWDER_PERIOD * (2.0 if double_powder() else 1.0)
	for side in 2:
		powder[side] = minf(POWDER_MAX, powder[side] + gain)
	for r: Regiment in regiments:
		r.men_tick = r.men
	for s: Structure in structures:
		if not s.dead:
			_update_structure(s)
	_deferring = true
	for r: Regiment in regiments:
		if not r.dead:
			_update_regiment(r)
	_deferring = false
	for hit: Array in _pending:
		if hit[0] == 0:
			_damage(hit[1], hit[2], hit[3])
		else:
			_morale_hit(hit[1], hit[2])
	_pending.clear()
	_separate()
	regiments = regiments.filter(func(r: Regiment) -> bool: return not r.dead)
	_check_clock()


func _check_clock() -> void:
	if phase == PHASE_REGULAR and time >= MATCH_TIME:
		var lost0 := redoubts_lost(0)
		var lost1 := redoubts_lost(1)
		if lost0 != lost1:
			_finish(0 if lost1 > lost0 else 1)
		else:
			phase = PHASE_OVERTIME
			events.append({"type": "overtime"})
	elif phase == PHASE_OVERTIME and time >= MATCH_TIME + OVERTIME:
		var f0 := _structure_fraction(0)
		var f1 := _structure_fraction(1)
		if absf(f0 - f1) < 0.0005:
			_finish(DRAW)
		else:
			_finish(0 if f0 > f1 else 1)


func _structure_fraction(side: int) -> float:
	var hp := 0.0
	var max_hp := 0.0
	for s: Structure in structures:
		if s.side == side:
			hp += maxf(0.0, s.hp)
			max_hp += s.max_hp
	return hp / max_hp


func _finish(who: int) -> void:
	if phase == PHASE_OVER:
		return
	winner = who
	phase = PHASE_OVER
	events.append({"type": "over", "winner": who})


# ==========================================================================================
# Structures
# ==========================================================================================

func _update_structure(s: Structure) -> void:
	if s.reload > 0.0:
		s.reload = maxf(0.0, s.reload - DT)
		return
	var best: Regiment = null
	var best_d := INF
	for r: Regiment in regiments:
		if r.dead or r.side == s.side:
			continue
		var d := s.pos.distance_to(r.pos)
		if d > s.gun_range:
			continue
		if r.state == ST_ROUT:
			d += 4.0
		if d < best_d:
			best_d = d
			best = r
	if best == null:
		return
	s.reload = s.gun_period
	var dmg := s.gun_dmg * (LOOSE_MUSKET_MULT if bool(best.def.get("loose", false)) else 1.0)
	events.append({"type": "cannon", "pos": s.pos, "to": best.pos, "side": s.side})
	_damage(best, dmg, s.pos)


func _damage_structure(s: Structure, amount: float) -> void:
	if s.dead or phase == PHASE_OVER:
		return
	s.hp -= amount
	if s.hp > 0.0:
		return
	s.hp = 0.0
	s.dead = true
	events.append({"type": "destroyed", "pos": s.pos, "side": s.side, "kind": s.kind})
	if s.kind == "hq" or phase == PHASE_OVERTIME:
		_finish(1 - s.side)


# ==========================================================================================
# Regiments
# ==========================================================================================

func _update_regiment(r: Regiment) -> void:
	r.since_hit += DT
	if r.reload > 0.0:
		r.reload = maxf(0.0, r.reload - DT)
	if r.life > 0.0:
		r.life -= DT
		if r.life <= 0.0:
			r.dead = true
			events.append({"type": "spent", "pos": r.pos, "side": r.side})
			return
	if r.state == ST_ROUT:
		_update_rout(r)
		return
	if r.since_hit > MORALE_REST and r.morale < r.morale_max:
		r.morale = minf(r.morale_max, r.morale + MORALE_REGEN * DT)

	if bool(r.def.get("can_square", false)):
		_update_square(r)

	if r.recoil > 0.0:
		# Cavalry thrown back by a square: fall back before choosing a new target.
		r.recoil -= DT
		r.in_melee = false
		_move(r, Vector2(r.pos.x, r.pos.y - fwd(r.side) * 6.0), float(r.def["speed"]))
		r.runup = 0.0
		return

	var foe := _nearest_enemy(r, CONTACT)
	r.in_melee = foe != null
	if r.in_melee:
		_melee(r, foe)
		r.runup = 0.0
		if r.state == ST_MARCH and r.arm != "cavalry":
			r.formation = "line"
		return

	if r.state == ST_FORMING:
		return

	var shoot_range := float(r.def.get("range", 0.0))
	if shoot_range > 0.0:
		_update_shooter(r, shoot_range)
	else:
		_update_cavalry(r)


func _update_square(r: Regiment) -> void:
	match r.state:
		ST_MARCH:
			if _enemy_cavalry_within(r, SQUARE_DETECT):
				r.state = ST_FORMING
				r.form_timer = SQUARE_FORM_TIME_RELOADING if r.reload > 0.0 else SQUARE_FORM_TIME
				events.append({"type": "forming", "pos": r.pos, "side": r.side})
		ST_FORMING:
			r.form_timer -= DT
			if r.form_timer <= 0.0:
				r.state = ST_SQUARE
				r.formation = "square"
				r.release_timer = SQUARE_RELEASE_TIME
				events.append({"type": "square", "pos": r.pos, "side": r.side})
		ST_SQUARE:
			if _enemy_cavalry_within(r, SQUARE_RELEASE_DIST):
				r.release_timer = SQUARE_RELEASE_TIME
			else:
				r.release_timer -= DT
				if r.release_timer <= 0.0:
					r.state = ST_MARCH
					r.formation = "line"


func _update_shooter(r: Regiment, shoot_range: float) -> void:
	var wet := in_ford_water(r.pos)
	if not wet:
		var target_reg := _shoot_target_regiment(r, shoot_range)
		if target_reg != null:
			r.facing = (target_reg.pos - r.pos).normalized()
			if r.state != ST_SQUARE:
				r.formation = "line"
			r.runup = 0.0
			if r.reload <= 0.0:
				_fire_at_regiment(r, target_reg)
			return
		var target_st := _shoot_target_structure(r, shoot_range)
		if target_st != null:
			r.facing = (target_st.pos - r.pos).normalized()
			if r.state != ST_SQUARE:
				r.formation = "line"
			if r.reload <= 0.0:
				_fire_at_structure(r, target_st)
			return
	if r.state == ST_SQUARE or r.arm == "artillery":
		return
	# Nothing to shoot: advance on a nearby enemy, or up the lane.
	var goal: Vector2
	var near := _nearest_enemy(r, shoot_range + 3.0, true)
	if near != null:
		goal = near.pos
	else:
		goal = _lane_structure(r).pos
	r.formation = "column"
	_move(r, goal, float(r.def["speed"]))


func _update_cavalry(r: Regiment) -> void:
	var speed := float(r.def["speed"])
	var prey := _charge_target(r)
	if prey != null:
		_move(r, prey.pos, speed)
		return
	var st := _lane_structure(r)
	if r.pos.distance_to(st.pos) <= st.radius + 0.9:
		r.in_melee = true
		r.runup = 0.0
		_damage_structure(st, r.men_tick * float(r.def["melee_dps"]) * STRUCT_MELEE_MULT * DT)
	else:
		_move(r, st.pos, speed)


func _update_rout(r: Regiment) -> void:
	r.in_melee = false
	r.formation = "rout"
	var home := hq(r.side)
	var speed := maxf(1.4, float(r.def["speed"])) * ROUT_SPEED_MULT
	if home == null or home.dead:
		var edge := Vector2(r.pos.x, 0.6 if r.side == 0 else FIELD_H - 0.6)
		_move(r, edge, speed)
		if r.pos.distance_to(edge) < 0.3:
			r.dead = true
		return
	if r.pos.distance_to(home.pos) <= RALLY_DIST:
		r.rally_timer += DT
		if r.rally_timer >= RALLY_TIME:
			_rally(r, RALLY_MORALE * r.morale_max)
	else:
		_move(r, home.pos, speed)


func _rally(r: Regiment, morale_value: float) -> void:
	r.state = ST_MARCH
	r.formation = "column"
	r.morale = clampf(morale_value, 1.0, r.morale_max)
	r.rally_timer = 0.0
	r.since_hit = 0.0
	r.facing = Vector2(0.0, fwd(r.side))
	events.append({"type": "rally", "pos": r.pos, "side": r.side})


func _start_rout(r: Regiment) -> void:
	if r.state == ST_ROUT or r.dead:
		return
	r.state = ST_ROUT
	r.formation = "rout"
	r.morale = 0.0
	r.rally_timer = 0.0
	r.recoil = 0.0
	events.append({"type": "rout", "pos": r.pos, "side": r.side})


# --- Fire ----------------------------------------------------------------------------------

func _fire_at_regiment(r: Regiment, t: Regiment) -> void:
	r.reload = float(r.def["reload"])
	if r.arm == "artillery":
		_fire_gun(r, t)
		return
	var dmg := _volley_damage(r)
	if bool(t.def.get("loose", false)):
		dmg *= LOOSE_MUSKET_MULT
	events.append({"type": "volley", "pos": r.pos, "to": t.pos, "side": r.side, "men": r.men_tick})
	_damage(t, dmg, r.pos)


func _fire_at_structure(r: Regiment, s: Structure) -> void:
	r.reload = float(r.def["reload"])
	if r.arm == "artillery":
		r.fired_first = true
		events.append({"type": "cannon", "pos": r.pos, "to": s.pos, "side": r.side})
		_damage_structure(s, float(r.def["shot_dmg"]) * STRUCT_SHOT_MULT)
		return
	var dmg := _volley_damage(r) * STRUCT_MUSKET_MULT
	events.append({"type": "volley", "pos": r.pos, "to": s.pos, "side": r.side, "men": r.men_tick})
	_damage_structure(s, dmg)


func _volley_damage(r: Regiment) -> float:
	var firing := float(r.men_tick)
	if r.state == ST_SQUARE:
		firing = ceilf(firing * SQUARE_FIRE_FRACTION)
	var dmg := firing * float(r.def["volley_dmg"])
	if not r.fired_first:
		dmg *= FIRST_VOLLEY_MULT
		r.fired_first = true
	return dmg


func _fire_gun(r: Regiment, t: Regiment) -> void:
	r.fired_first = true
	var to_target := t.pos - r.pos
	var dist := to_target.length()
	if dist <= float(r.def["canister_range"]):
		var dmg := float(r.def["canister_dmg"])
		if bool(t.def.get("loose", false)):
			dmg *= LOOSE_MUSKET_MULT
		events.append({"type": "canister", "pos": r.pos, "to": t.pos, "side": r.side})
		_damage(t, dmg, r.pos)
		return
	var dir := to_target / dist
	var shot := float(r.def["shot_dmg"])
	var reach := float(r.def["range"])
	events.append({"type": "cannon", "pos": r.pos, "to": r.pos + dir * reach, "side": r.side})
	# Roundshot keeps going: everything else along its path takes a share.
	var others: Array = []
	for o: Regiment in regiments:
		if o.dead or o.side == r.side or o == t:
			continue
		var rel := o.pos - r.pos
		var along := rel.dot(dir)
		if along <= dist or along > reach:
			continue
		if absf(rel.cross(dir)) <= SHOT_PIERCE_WIDTH:
			others.append(o)
	_damage(t, shot * _shot_mult(t), r.pos)
	for o: Regiment in others:
		_damage(o, shot * SHOT_PIERCE_MULT * _shot_mult(o), r.pos)


func _shot_mult(t: Regiment) -> float:
	if bool(t.def.get("loose", false)):
		return LOOSE_SHOT_MULT
	if t.formation == "square":
		return SQUARE_SHOT_MULT
	if t.formation == "column":
		return COLUMN_SHOT_MULT
	return 1.0


# --- Melee ---------------------------------------------------------------------------------

func _melee(r: Regiment, foe: Regiment) -> void:
	var dps := r.men_tick * float(r.def["melee_dps"])
	if r.arm == "cavalry":
		if r.runup >= CHARGE_RUNUP:
			if foe.state == ST_SQUARE:
				events.append({"type": "repelled", "pos": foe.pos, "side": r.side})
				_damage(r, SQUARE_REPEL_DMG, foe.pos)
				_morale_hit(r, SQUARE_REPEL_SHOCK)
				r.recoil = CAV_RECOIL_TIME
				return
			events.append({"type": "charge", "pos": foe.pos, "side": r.side})
			_damage(foe, r.men_tick * float(r.def["charge_dmg"]), r.pos)
			_morale_hit(foe, float(r.def["charge_shock"]))
		if foe.state == ST_SQUARE:
			dps *= 0.3
		elif foe.arm == "artillery":
			dps *= 2.0
	elif r.state == ST_SQUARE and foe.arm == "cavalry":
		dps *= 1.5
	_damage(foe, dps * DT, r.pos)


# --- Damage and morale ---------------------------------------------------------------------

func _damage(t: Regiment, amount: float, from: Vector2) -> void:
	if _deferring:
		_pending.append([0, t, amount, from])
		return
	if t.dead or amount <= 0.0:
		return
	if t.state == ST_ROUT:
		amount *= ROUT_DAMAGE_MULT
	t.hp -= amount
	t.since_hit = 0.0
	if t.hp <= 0.0:
		t.hp = 0.0
		t.men = 0
		t.dead = true
		events.append({"type": "destroyed_regiment", "pos": t.pos, "side": t.side})
		return
	t.men = int(ceilf(t.hp / float(t.def["hp_per_man"])))
	var loss := amount / t.max_hp * 100.0 * MORALE_K
	if t.state != ST_SQUARE and t.state != ST_ROUT:
		var away := from - t.pos
		if away.length() > 0.01 and t.facing.dot(away.normalized()) < -0.2:
			loss *= FLANK_MORALE_MULT
	_morale_hit(t, loss)


func _morale_hit(t: Regiment, amount: float) -> void:
	if _deferring:
		_pending.append([1, t, amount])
		return
	if t.dead or t.state == ST_ROUT:
		return
	t.morale -= amount
	if t.morale <= 0.0:
		_start_rout(t)


# --- Orders --------------------------------------------------------------------------------

func _order_fire_target(side: int, pos: Vector2, radius: float) -> Regiment:
	var best: Regiment = null
	var best_d := radius
	for r: Regiment in regiments:
		if r.dead or r.side != side or r.state == ST_ROUT or r.state == ST_FORMING:
			continue
		if float(r.def.get("range", 0.0)) <= 0.0:
			continue
		var d := r.pos.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = r
	return best


func _order_rally_targets(side: int, pos: Vector2, radius: float) -> Array:
	var out: Array = []
	for r: Regiment in regiments:
		if not r.dead and r.side == side and r.pos.distance_to(pos) <= radius:
			out.append(r)
	return out


func _play_order(side: int, card_id: String, def: Dictionary, pos: Vector2) -> void:
	events.append({"type": "order", "pos": pos, "side": side, "card": card_id, "radius": float(def["radius"])})
	if card_id == "fire":
		var r := _order_fire_target(side, pos, float(def["radius"]))
		if r != null:
			r.reload = 0.0
	elif card_id == "rally":
		for r: Regiment in _order_rally_targets(side, pos, float(def["radius"])):
			if r.state == ST_ROUT:
				_rally(r, float(def["morale_restore"]))
			else:
				r.morale = minf(r.morale_max, r.morale + float(def["morale_restore"]))


# --- Targeting -----------------------------------------------------------------------------

func _nearest_enemy(r: Regiment, max_dist: float, skip_routing: bool = false) -> Regiment:
	var best: Regiment = null
	var best_d := max_dist
	for o: Regiment in regiments:
		if o.dead or o.side == r.side:
			continue
		if skip_routing and o.state == ST_ROUT:
			continue
		var d := r.pos.distance_to(o.pos)
		if d <= best_d:
			best_d = d
			best = o
	return best


func _enemy_cavalry_within(r: Regiment, dist: float) -> bool:
	for o: Regiment in regiments:
		if o.dead or o.side == r.side or o.arm != "cavalry" or o.state == ST_ROUT:
			continue
		if r.pos.distance_to(o.pos) <= dist:
			return true
	return false


func _shoot_target_regiment(r: Regiment, shoot_range: float) -> Regiment:
	var best: Regiment = null
	var best_score := INF
	for o: Regiment in regiments:
		if o.dead or o.side == r.side:
			continue
		var d := r.pos.distance_to(o.pos)
		if d > shoot_range:
			continue
		var score := d + (3.0 if o.state == ST_ROUT else 0.0)
		if score < best_score:
			best_score = score
			best = o
	return best


func _shoot_target_structure(r: Regiment, shoot_range: float) -> Structure:
	var best: Structure = null
	var best_d := INF
	for s: Structure in structures:
		if s.dead or s.side == r.side:
			continue
		var d := r.pos.distance_to(s.pos) - s.radius
		if d <= shoot_range and d < best_d:
			best_d = d
			best = s
	return best


func _charge_target(r: Regiment) -> Regiment:
	var best: Regiment = null
	var best_score := INF
	for o: Regiment in regiments:
		if o.dead or o.side == r.side or o.state == ST_SQUARE:
			continue
		var d := r.pos.distance_to(o.pos)
		if d > CAV_AGGRO:
			continue
		var soft := o.arm == "artillery" or bool(o.def.get("loose", false)) or o.state == ST_ROUT
		var score := d * (0.6 if soft else 1.0)
		if score < best_score:
			best_score = score
			best = o
	return best


func _lane_structure(r: Regiment) -> Structure:
	var enemy := 1 - r.side
	if r.lane != 1:
		var rd := redoubt(enemy, 0 if r.lane == 0 else 1)
		if rd != null and not rd.dead:
			return rd
	return hq(enemy)


# --- Movement ------------------------------------------------------------------------------

func _move(r: Regiment, dest: Vector2, speed: float) -> void:
	if speed <= 0.0:
		return
	if in_ford_water(r.pos):
		speed *= FORD_SPEED_MULT
	var wp := _waypoint(r.pos, dest)
	var d := wp - r.pos
	var dist := d.length()
	if dist < 0.001:
		return
	var step := minf(dist, speed * DT)
	r.pos += d / dist * step
	r.facing = d / dist
	r.runup += step
	r.pos = _fix_pos(r.pos)


static func _bank(y: float) -> int:
	if y <= CREEK_Y0:
		return -1
	if y >= CREEK_Y1:
		return 1
	return 0


## The creek is only passable at the crossings, so a move to the far bank goes by way of one.
static func _waypoint(from: Vector2, dest: Vector2) -> Vector2:
	var fb := _bank(from.y)
	var db := _bank(dest.y)
	if fb == 0:
		if db == 0:
			return dest
		return Vector2(from.x, CREEK_Y1 + 0.3 if db > 0 else CREEK_Y0 - 0.3)
	if db == fb:
		return dest
	var best: Dictionary = CROSSINGS[0]
	var best_cost := INF
	for c: Dictionary in CROSSINGS:
		var cost := absf(from.x - float(c["x"])) + absf(dest.x - float(c["x"]))
		if cost < best_cost:
			best_cost = cost
			best = c
	var inset := float(best["half"]) - 0.35
	var entry := Vector2(clampf(from.x, float(best["x"]) - inset, float(best["x"]) + inset),
			CREEK_Y0 if fb < 0 else CREEK_Y1)
	if from.distance_to(entry) < 0.05:
		return Vector2(entry.x, CREEK_Y1 + 0.3 if fb < 0 else CREEK_Y0 - 0.3)
	return entry


static func _fix_pos(p: Vector2) -> Vector2:
	p.x = clampf(p.x, 0.4, FIELD_W - 0.4)
	p.y = clampf(p.y, 0.4, FIELD_H - 0.4)
	if in_creek(p.y) and crossing_at(p.x).is_empty():
		# Pushed into deep water: put it back on the nearer bank.
		p.y = CREEK_Y0 if p.y - CREEK_Y0 < CREEK_Y1 - p.y else CREEK_Y1
	return p


func _separate() -> void:
	var n := regiments.size()
	for i in n:
		var a: Regiment = regiments[i]
		if a.dead or a.state == ST_ROUT:
			continue
		for j in range(i + 1, n):
			var b: Regiment = regiments[j]
			if b.dead or b.side != a.side or b.state == ST_ROUT:
				continue
			var d := b.pos - a.pos
			var dist := d.length()
			if dist >= SEPARATION:
				continue
			var push := Vector2(1.0, 0.0) if dist < 0.001 else d / dist
			var amount := (SEPARATION - dist) * 0.25
			var a_fixed := a.state == ST_SQUARE or a.state == ST_FORMING or a.arm == "artillery"
			var b_fixed := b.state == ST_SQUARE or b.state == ST_FORMING or b.arm == "artillery"
			if not a_fixed:
				a.pos = _fix_pos(a.pos - push * amount)
			if not b_fixed:
				b.pos = _fix_pos(b.pos + push * amount)
