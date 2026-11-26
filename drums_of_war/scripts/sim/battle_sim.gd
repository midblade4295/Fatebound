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
const FIELD_H := 36.0
const CREEK_Y0 := 17.0
const CREEK_Y1 := 19.0
const CROSSINGS := [
	{"x": 3.0, "half": 1.5, "ford": true},
	{"x": 9.0, "half": 1.2, "ford": false},
	{"x": 15.0, "half": 1.5, "ford": true},
]
const DEPLOY_DEPTH := 16.0          # how far from your own baseline you may deploy
const DEPLOY_DEPTH_OPEN := 24.0     # ... on a flank whose enemy redoubt has fallen
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
const STRUCT_MUSKET_MULT := 1.0
const STRUCT_SHOT_MULT := 0.6
const STRUCT_MELEE_MULT := 0.8
const STRUCT_GUN_MORALE := 0.5      # how much of the usual nerve a hit from a battery's or the farmhouse's gun costs
const SEPARATION := 1.4

const REDOUBT_HP := 650.0
const REDOUBT_RANGE := 8.5
const REDOUBT_DMG := 50.0
const REDOUBT_PERIOD := 2.5
const HQ_HP := 1800.0
const HQ_RANGE := 6.5
const HQ_DMG := 50.0
const HQ_PERIOD := 2.0

# --- The later cards ----------------------------------------------------------------------
# Leaders (the General, the Marshal, pipers and drummers) carry an "aura": a circle in which
# their regiments lose less nerve, reload, march or recover faster (aura_* in the card data).
const GENERAL_FALL_RADIUS := 9.0    # how far the shock of a fallen commander carries
const GENERAL_FOLLOW := 3.5         # how far behind the leading regiment a leader rides
const SPLASH_SHARE := 0.5           # what grenades do to regiments beside the one they hit
const ABATIS_SLOW := 0.4            # cavalry speed while crossing an abatis
const EARTHWORK_MULT := 0.5         # musket fire on troops behind a fieldwork
const EARTHWORK_DEPTH := 2.0        # how far behind it they are still covered
const BALLOON_RANGE_MULT := 1.25
const LOOSE_SHELL_MULT := 0.6
const GATLING_COOL := 1.5           # heat lost per second while the gun is not firing

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
	var mounted: bool = false    # dragoons: in the saddle (arm is then "cavalry"), or on foot
	var limbered: bool = false   # horse artillery: hooked up and moving
	var idle_time: float = 0.0   # seconds with nothing to shoot at
	var heat: float = 0.0        # Gatling: seconds of fire since it last cooled
	var fired_tick: int = -1000
	var shock_tick: int = -1000
	var haste_until: int = -1    # Forced March and Bugle Call: faster until this tick
	var haste_mult: float = 1.0
	var steady_until: int = -1   # Hold the Line!: cannot be made to run until this tick


## A thing placed on the field that is not a regiment: earthworks, a balloon, a wagon, a mine...
## What it does is its card's "effect".
class Work extends RefCounted:
	var id: int
	var side: int
	var kind: String             # the card id
	var effect: String           # cover, spotter, supply, abatis, hospital, mine, depot
	var def: Dictionary
	var pos: Vector2
	var half_width: float
	var life: float
	var clock: float = 0.0       # supply and depot: seconds to the next delivery
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
var powder_rate: Array = [1.0, 1.0]    # a computer opponent's level may give its side more (see bot.gd LEVELS)
var decks: Array = [[], []]
var regiments: Array = []
var structures: Array = []
var works: Array = []            # earthworks and balloons
var shells: Array = []           # in the air: {due (tick), pos, side, dmg, struct, radius, kind}
var _auras: Array = []           # regiments carrying an aura this tick (leaders)
var _commanders: Array = []      # the General or Marshal of each side, this tick: routed men run to them
var events: Array = []           # things the view may want to show; safe to clear at any time
var command_log: Array = []      # every accepted deploy, for replays and determinism checks
var _next_id: int = 1
var _deferring: bool = false   # while regiments act, hits are queued so that order of acting gives no edge
var _pending: Array = []
var _morale_scale: float = 1.0


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
		_add_structure(side, "hq", -1, Vector2(9.0, 4.5), 1.6, HQ_HP, HQ_RANGE, HQ_DMG, HQ_PERIOD)
		_add_structure(side, "redoubt", 0, Vector2(3.5, 8.5), 1.2, REDOUBT_HP, REDOUBT_RANGE, REDOUBT_DMG, REDOUBT_PERIOD)
		_add_structure(side, "redoubt", 1, Vector2(14.5, 8.5), 1.2, REDOUBT_HP, REDOUBT_RANGE, REDOUBT_DMG, REDOUBT_PERIOD)


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
		return _order_error(side, def, pos)
	if bool(def.get("unique", false)) and general(side) != null:
		return "Your commander is already on the field"
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
	elif def["type"] == "work":
		place_work(side, card_id, pos)
	else:
		spawn(side, card_id, pos)
	return true


## Puts a work (earthworks, a balloon, a wagon, a mine...) on the field.
func place_work(side: int, card_id: String, pos: Vector2) -> Work:
	var def: Dictionary = cards[card_id]
	var w := Work.new()
	w.id = _next_id
	_next_id += 1
	w.side = side
	w.kind = card_id
	w.def = def
	w.effect = String(def.get("effect", ""))
	w.pos = pos
	w.half_width = float(def.get("radius", 1.0))
	w.life = float(def.get("life", 60.0))
	# A wagon's first load comes after a full interval; a depot sends its first company at once.
	w.clock = float(def.get("every", 0.0)) if w.effect == "supply" else 0.0
	works.append(w)
	events.append({"type": "deploy", "pos": pos, "side": side, "card": card_id})
	return w


## A side's commander (the General or the Marshal), if he is on the field. Only one at a time.
func general(side: int) -> Regiment:
	for r: Regiment in regiments:
		if r.side == side and bool(r.def.get("unique", false)) and not r.dead:
			return r
	return null


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
	r.mounted = def.has("dismount")
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
	for w: Work in works:
		parts.append("%d:%s:%.3f" % [w.id, w.kind, w.life])
	for sh: Dictionary in shells:
		parts.append("%d:%.3f:%.3f" % [int(sh["due"]), Vector2(sh["pos"]).x, Vector2(sh["pos"]).y])
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
		powder[side] = minf(POWDER_MAX, powder[side] + gain * float(powder_rate[side]))
	_auras.clear()
	_commanders.clear()
	for r: Regiment in regiments:
		r.men_tick = r.men
		if r.dead or r.state == ST_ROUT:
			continue
		if r.def.has("aura"):
			_auras.append(r)
		if bool(r.def.get("unique", false)):
			_commanders.append(r)
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
	_update_shells()
	_update_works()
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
	var reach := s.gun_range
	if s.kind == "redoubt" and balloon_over(s.side, s.pos.x):
		reach *= BALLOON_RANGE_MULT
	for r: Regiment in regiments:
		if r.dead or r.side == s.side:
			continue
		var d := s.pos.distance_to(r.pos)
		if d > reach:
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
	# Men attacking a work expect its gun: it hurts as much, but shakes them less than a
	# volley from troops they did not see coming.
	_morale_scale = STRUCT_GUN_MORALE
	_damage(best, dmg, s.pos)
	_morale_scale = 1.0


func _damage_structure(s: Structure, amount: float) -> void:
	if s.dead or phase == PHASE_OVER:
		return
	s.hp -= amount
	if amount >= 8.0:
		events.append({"type": "struct_hit", "pos": s.pos, "amount": amount, "id": s.id, "side": s.side})
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
		r.reload = maxf(0.0, r.reload - DT * _aura(r, "aura_reload"))
		if r.reload < 0.00001:
			r.reload = 0.0             # so that a quarter-second reload is five ticks, not sometimes six
	if r.heat > 0.0 and tick_count - r.fired_tick > 6:
		r.heat = maxf(0.0, r.heat - GATLING_COOL * DT)
	if r.life > 0.0:
		r.life -= DT
		if r.life <= 0.0:
			r.dead = true
			events.append({"type": "spent", "pos": r.pos, "side": r.side})
			return
	if r.state == ST_ROUT:
		_update_rout(r)
		return
	var regen := _aura(r, "aura_regen")
	if r.since_hit > MORALE_REST / regen and r.morale < r.morale_max:
		r.morale = minf(r.morale_max, r.morale + MORALE_REGEN * regen * DT)
	if r.def.has("demolish"):
		_update_pioneers(r)
		return

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
	var was_fighting := r.in_melee
	r.in_melee = foe != null
	if r.in_melee:
		if not was_fighting and r.def.has("bayonet_shock") and tick_count - r.shock_tick > 60:
			# Veterans going in with the bayonet: the sight of it shakes whoever they reach.
			r.shock_tick = tick_count
			events.append({"type": "bayonet", "pos": foe.pos, "side": r.side})
			_morale_hit(foe, float(r.def["bayonet_shock"]))
		_melee(r, foe)
		r.runup = 0.0
		if r.state == ST_MARCH and r.arm != "cavalry":
			r.formation = "line"
		return

	if r.state == ST_FORMING:
		return
	if r.arm == "command":
		_update_general(r)
		return
	if r.def.has("dismount") and _update_dragoons(r):
		return

	var shoot_range := float(r.def.get("range", 0.0))
	if shoot_range > 0.0:
		if r.arm == "artillery" and balloon_over(r.side, r.pos.x):
			shoot_range *= BALLOON_RANGE_MULT
		_update_shooter(r, shoot_range)
	else:
		_update_cavalry(r)


## Pioneers make for the nearest enemy work on their lane, paying no attention to anything
## else, and when they reach it they blow it up, and themselves with it.
func _update_pioneers(r: Regiment) -> void:
	var st := _lane_structure(r)
	r.in_melee = false
	if r.pos.distance_to(st.pos) <= st.radius + 0.8:
		events.append({"type": "demolish", "pos": st.pos, "side": r.side})
		_damage_structure(st, float(r.def["demolish"]))
		r.dead = true
		r.hp = 0.0
		r.men = 0
		return
	r.formation = "column"
	_move(r, st.pos, float(r.def["speed"]))


## The General keeps just behind whichever of his regiments is furthest forward near him.
## He does not seek a fight; if nobody is left to lead he stays where he is.
func _update_general(r: Regiment) -> void:
	var lead: Regiment = null
	var lead_score := -INF
	for o: Regiment in regiments:
		if o.dead or o.side != r.side or o == r or o.state == ST_ROUT or o.arm == "command":
			continue
		if float(o.def.get("speed", 0.0)) <= 0.0:
			continue
		var score := local_y(r.side, o.pos.y) - absf(o.pos.x - r.pos.x) * 0.5
		if score > lead_score:
			lead_score = score
			lead = o
	if lead == null:
		return
	var goal := _fix_pos(lead.pos - Vector2(0.0, fwd(r.side) * GENERAL_FOLLOW))
	if in_creek(goal.y):
		goal = lead.pos
	if r.pos.distance_to(goal) > 0.7:
		_move(r, goal, float(r.def["speed"]))
	else:
		r.facing = Vector2(0.0, fwd(r.side))


## Dragoons ride up their lane until something is in carbine range, get down and fight on
## foot, and mount again once it has been quiet for a moment. Returns true while there is
## nothing for the ordinary shooting rules to do.
func _update_dragoons(r: Regiment) -> bool:
	var reach := float(r.def["range"])
	var has_target := _shoot_target_regiment(r, reach) != null or _shoot_target_structure(r, reach) != null
	if r.mounted:
		if has_target and not in_ford_water(r.pos):
			r.mounted = false
			r.arm = "infantry"
			r.formation = "line"
			r.idle_time = 0.0
			r.reload = maxf(r.reload, float(r.def["dismount"]))
			events.append({"type": "dismount", "pos": r.pos, "side": r.side})
			return true
		r.formation = "column"
		_move(r, _lane_structure(r).pos, float(r.def["speed"]))
		return true
	if has_target:
		r.idle_time = 0.0
		return false
	r.idle_time += DT
	if r.idle_time >= float(r.def.get("remount", 2.0)):
		r.mounted = true
		r.arm = "cavalry"
		events.append({"type": "mount", "pos": r.pos, "side": r.side})
	return true


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
	if not wet and r.def.has("closes") and r.state == ST_MARCH and r.reload > 0.0:
		# The volley is away: close with the bayonet instead of standing to reload.
		var prey := _nearest_enemy(r, float(r.def["closes"]), true)
		if prey != null and prey.arm != "cavalry" and _bank(prey.pos.y) == _bank(r.pos.y):
			r.formation = "line"
			_move(r, prey.pos, float(r.def["speed"]) * 1.25)
			return
	if not wet and bool(r.def.get("siege", false)):
		# A siege gun was brought for the works: it shoots at them before anything else.
		var work := _shoot_target_structure(r, shoot_range)
		if work != null:
			r.facing = (work.pos - r.pos).normalized()
			if r.reload <= 0.0:
				_fire_at_structure(r, work)
			return
	if not wet:
		var target_reg := _shoot_target_regiment(r, shoot_range)
		if target_reg != null:
			_unlimber(r)
			r.facing = (target_reg.pos - r.pos).normalized()
			if r.state != ST_SQUARE:
				r.formation = "line"
			r.runup = 0.0
			if r.reload <= 0.0:
				_fire_at_regiment(r, target_reg)
			return
		var target_st := _shoot_target_structure(r, shoot_range)
		if target_st != null:
			_unlimber(r)
			r.facing = (target_st.pos - r.pos).normalized()
			if r.state != ST_SQUARE:
				r.formation = "line"
			if r.reload <= 0.0:
				_fire_at_structure(r, target_st)
			return
	if r.state == ST_SQUARE or (r.arm == "artillery" and not r.def.has("limber")):
		return
	if r.arm == "artillery" and not r.limbered:
		# Horse artillery: nothing in reach, so after a moment the team is hooked up again.
		r.idle_time += DT
		if r.idle_time < float(r.def["limber"]):
			return
		r.limbered = true
	# Nothing to shoot: advance on a nearby enemy, or up the lane.
	var goal: Vector2
	var near := _nearest_enemy(r, shoot_range + 3.0, true)
	if near != null:
		goal = near.pos
	else:
		goal = _lane_structure(r).pos
	r.formation = "column"
	_move(r, goal, float(r.def["speed"]))


## A gun that was on the move has to be unhooked before it can fire.
func _unlimber(r: Regiment) -> void:
	r.idle_time = 0.0
	if r.limbered:
		r.limbered = false
		r.reload = maxf(r.reload, float(r.def.get("unlimber", 1.0)))


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
	# Run for the headquarters, or for the General if he is nearer.
	var refuge := Vector2.INF
	if home != null and not home.dead:
		refuge = home.pos
	for g: Regiment in _commanders:
		if g.side == r.side and not g.dead and g != r and r.pos.distance_to(g.pos) < r.pos.distance_to(refuge):
			refuge = g.pos
	if refuge == Vector2.INF:
		var edge := Vector2(r.pos.x, 0.6 if r.side == 0 else FIELD_H - 0.6)
		_move(r, edge, speed)
		if r.pos.distance_to(edge) < 0.3:
			r.dead = true
		return
	if r.pos.distance_to(refuge) <= RALLY_DIST:
		r.rally_timer += DT
		if r.rally_timer >= RALLY_TIME:
			_rally(r, RALLY_MORALE * r.morale_max)
	else:
		_move(r, refuge, speed)


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
	r.fired_tick = tick_count
	if r.def.has("burst_dmg"):
		_fire_burst(r, t, null)
		return
	if r.def.has("shell_dmg"):
		r.fired_first = true
		_fire_shell(r, t.pos)
		return
	if r.arm == "artillery":
		_fire_gun(r, t)
		return
	var dmg := _volley_damage(r)
	events.append({"type": "volley", "pos": r.pos, "to": t.pos, "side": r.side, "men": r.men_tick})
	_damage(t, dmg * _musket_mult(t, r.pos), r.pos)
	if r.def.has("splash"):
		# Grenades: those standing beside the regiment hit get a share.
		var reach := float(r.def["splash"])
		for o: Regiment in regiments:
			if o != t and not o.dead and o.side != r.side and o.pos.distance_to(t.pos) <= reach:
				_damage(o, dmg * SPLASH_SHARE * _musket_mult(o, r.pos), t.pos)


## How much of a musket ball's harm reaches a regiment: less in loose order, behind its own
## earthworks, or through a cuirass.
func _musket_mult(t: Regiment, from: Vector2) -> float:
	var m := cover_mult(t, from) * float(t.def.get("armour", 1.0))
	if bool(t.def.get("loose", false)):
		m *= LOOSE_MUSKET_MULT
	return m


## A shell from a howitzer or mortar, or a rocket, which lands somewhere near its mark.
func _fire_shell(r: Regiment, at: Vector2) -> void:
	var kind := "shell"
	var extra := {}
	if bool(r.def.get("rocket", false)):
		kind = "rocket"
		var scatter := float(r.def.get("scatter", 0.0))
		at = _fix_pos(at + Vector2(rng.range_f(-scatter, scatter), rng.range_f(-scatter, scatter)))
		extra = {"shock": float(r.def.get("shock", 0.0)), "cav_mult": float(r.def.get("cav_mult", 1.0))}
	var dmg := float(r.def["shell_dmg"])
	_launch_shell(r.side, r.pos, at, dmg, dmg * STRUCT_SHOT_MULT * float(r.def.get("struct_mult", 1.0)),
			float(r.def["shell_radius"]), float(r.def["shell_time"]), kind, extra)


## The Gatling: a short burst every quarter second with no reload to wait out, until the
## barrels have been turning too long and it jams.
func _fire_burst(r: Regiment, t: Regiment, s: Structure) -> void:
	r.fired_first = true
	var dmg := float(r.def["burst_dmg"])
	if t != null:
		events.append({"type": "burst", "pos": r.pos, "to": t.pos, "side": r.side})
		_damage(t, dmg * _musket_mult(t, r.pos), r.pos)
	else:
		events.append({"type": "burst", "pos": r.pos, "to": s.pos, "side": r.side})
		_damage_structure(s, dmg * STRUCT_MUSKET_MULT)
	r.heat += float(r.def["reload"])
	if r.heat >= float(r.def["jam_after"]):
		r.heat = 0.0
		r.reload = float(r.def["jam_time"])
		events.append({"type": "jam", "pos": r.pos, "side": r.side})


## A shell (or a whole bombardment) on its way: it lands where it was aimed, after "delay"
## seconds, on whoever is there by then.
func _launch_shell(side: int, from: Vector2, to: Vector2, dmg: float, struct_dmg: float, radius: float, delay: float, kind: String,
		extra: Dictionary = {}) -> void:
	var shell := {"due": tick_count + int(round(delay / DT)), "pos": to, "side": side, "dmg": dmg, "struct": struct_dmg,
			"radius": radius, "kind": kind}
	shell.merge(extra)
	shells.append(shell)
	events.append({"type": "shell", "pos": from, "to": to, "side": side, "time": delay, "radius": radius, "kind": kind})


func _update_shells() -> void:
	if shells.is_empty():
		return
	var flying: Array = []
	for sh: Dictionary in shells:
		if int(sh["due"]) > tick_count:
			flying.append(sh)
			continue
		var at: Vector2 = sh["pos"]
		var radius := float(sh["radius"])
		events.append({"type": "shell_burst", "pos": at, "side": sh["side"], "radius": radius, "kind": sh["kind"]})
		for o: Regiment in regiments:
			if o.dead or o.side == int(sh["side"]) or o.pos.distance_to(at) > radius:
				continue
			var dmg := float(sh["dmg"])
			if sh["kind"] == "barrage":
				dmg *= _shot_mult(o)          # round shot and shell together: worst for squares and columns
			elif bool(o.def.get("loose", false)):
				dmg *= LOOSE_SHELL_MULT
			if o.arm == "cavalry":
				dmg *= float(sh.get("cav_mult", 1.0))          # rockets terrify horses
			_damage(o, dmg, at)
			if float(sh.get("shock", 0.0)) > 0.0:
				_morale_hit(o, float(sh["shock"]))
		for st: Structure in structures:
			if not st.dead and st.side != int(sh["side"]) and st.pos.distance_to(at) <= radius + st.radius:
				_damage_structure(st, float(sh["struct"]))
	shells = flying


func _update_works() -> void:
	if works.is_empty():
		return
	var count := works.size()
	for i in count:
		var w: Work = works[i]
		match w.effect:
			"supply":
				w.clock -= DT
				if w.clock <= 0.0:
					w.clock += float(w.def["every"])
					powder[w.side] = minf(POWDER_MAX, powder[w.side] + float(w.def["amount"]))
					events.append({"type": "supply", "pos": w.pos, "side": w.side})
			"depot":
				w.clock -= DT
				if w.clock <= 0.0:
					w.clock += float(w.def["every"])
					spawn(w.side, String(w.def["spawn"]), _fix_pos(w.pos + Vector2(0.0, fwd(w.side) * 1.2)))
			"hospital":
				var heal := float(w.def["heal"]) * DT
				for r: Regiment in regiments:
					if r.dead or r.side != w.side or r.hp >= r.max_hp or r.pos.distance_to(w.pos) > w.half_width:
						continue
					r.hp = minf(r.max_hp, r.hp + heal)
					r.men = int(ceilf(r.hp / float(r.def["hp_per_man"])))
			"abatis":
				for r: Regiment in regiments:
					if not r.dead and r.side != w.side and r.arm == "cavalry" and _in_abatis(r.pos, w):
						r.runup = 0.0             # no charge goes through felled trees
						_damage(r, float(w.def["dps"]) * DT, w.pos)
			"mine":
				var tripped := false
				for r: Regiment in regiments:
					if not r.dead and r.side != w.side and r.pos.distance_to(w.pos) <= float(w.def["trigger"]):
						tripped = true
						break
				if tripped:
					events.append({"type": "mine", "pos": w.pos, "side": w.side, "radius": w.half_width})
					for r: Regiment in regiments:
						if not r.dead and r.side != w.side and r.pos.distance_to(w.pos) <= w.half_width:
							_damage(r, float(w.def["dmg"]), w.pos)
					w.dead = true
					continue
		w.life -= DT
		if w.life <= 0.0:
			w.dead = true
			events.append({"type": "work_gone", "pos": w.pos, "side": w.side, "kind": w.kind})
	works = works.filter(func(w: Work) -> bool: return not w.dead)


func _in_abatis(p: Vector2, w: Work) -> bool:
	return absf(p.x - w.pos.x) <= w.half_width and absf(p.y - w.pos.y) <= 1.0


## True if that side has a balloon up over the flank that x lies on.
func balloon_over(side: int, x: float) -> bool:
	for w: Work in works:
		if w.effect == "spotter" and w.side == side and (w.pos.x < FIELD_W * 0.5) == (x < FIELD_W * 0.5):
			return true
	return false


## How much of a musket volley reaches a regiment: half if it stands behind one of its own
## fieldworks and the fire comes from in front of the work.
func cover_mult(t: Regiment, from: Vector2) -> float:
	for w: Work in works:
		if w.effect != "cover" or w.side != t.side or absf(t.pos.x - w.pos.x) > w.half_width:
			continue
		var behind := (w.pos.y - t.pos.y) * fwd(t.side)       # how far behind the work the regiment stands
		if behind >= -0.6 and behind <= EARTHWORK_DEPTH and (from.y - w.pos.y) * fwd(t.side) > 0.0:
			return EARTHWORK_MULT
	return 1.0


func _fire_at_structure(r: Regiment, s: Structure) -> void:
	r.reload = float(r.def["reload"])
	r.fired_tick = tick_count
	if r.def.has("burst_dmg"):
		_fire_burst(r, null, s)
		return
	if r.def.has("shell_dmg"):
		r.fired_first = true
		_fire_shell(r, s.pos)
		return
	if r.arm == "artillery":
		r.fired_first = true
		events.append({"type": "cannon", "pos": r.pos, "to": s.pos, "side": r.side})
		_damage_structure(s, float(r.def["shot_dmg"]) * STRUCT_SHOT_MULT * float(r.def.get("struct_mult", 1.0)))
		return
	# A card may be better or worse than a musket against earth and timber ("struct_mult").
	var dmg := _volley_damage(r) * STRUCT_MUSKET_MULT * float(r.def.get("struct_mult", 1.0))
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
		var hunting := float(r.def.get("pursuit", 1.0)) if foe.state == ST_ROUT else 1.0
		if r.runup >= CHARGE_RUNUP and r.def.has("charge_dmg"):
			if foe.state == ST_SQUARE:
				events.append({"type": "repelled", "pos": foe.pos, "side": r.side})
				if r.def.has("lance"):
					# A lance reaches over the bayonets: part of the charge still lands.
					var share := float(r.def["lance"])
					_damage(foe, r.men_tick * float(r.def["charge_dmg"]) * share, r.pos)
					_morale_hit(foe, float(r.def["charge_shock"]) * share)
					_damage(r, SQUARE_REPEL_DMG * 0.5, foe.pos)
				else:
					_damage(r, SQUARE_REPEL_DMG, foe.pos)
					_morale_hit(r, SQUARE_REPEL_SHOCK)
				r.recoil = CAV_RECOIL_TIME
				return
			events.append({"type": "charge", "pos": foe.pos, "side": r.side})
			_damage(foe, r.men_tick * float(r.def["charge_dmg"]) * hunting, r.pos)
			_morale_hit(foe, float(r.def["charge_shock"]))
		dps *= hunting
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
	if amount >= 8.0:
		# For the view only: where a blow landed, how hard, and where it came from.
		events.append({"type": "hit", "pos": t.pos, "from": from, "amount": amount, "id": t.id, "side": t.side, "of": t.max_hp})
	if t.hp <= 0.0:
		t.hp = 0.0
		t.men = 0
		t.dead = true
		events.append({"type": "destroyed_regiment", "pos": t.pos, "side": t.side})
		if t.def.has("fall_shock"):
			# The commander is down: everyone who could see him fall is shaken.
			events.append({"type": "general_down", "pos": t.pos, "side": t.side})
			for o: Regiment in regiments:
				if not o.dead and o.side == t.side and o != t and o.pos.distance_to(t.pos) <= GENERAL_FALL_RADIUS:
					_morale_hit(o, float(t.def["fall_shock"]))
		return
	t.men = int(ceilf(t.hp / float(t.def["hp_per_man"])))
	var loss := amount / t.max_hp * 100.0 * MORALE_K * _morale_scale
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
	amount *= _aura(t, "aura_nerve")
	t.morale -= amount
	if t.morale <= 0.0:
		if bool(t.def.get("steady", false)) or tick_count < t.steady_until:
			t.morale = 1.0                 # they will not run
			return
		_start_rout(t)


# --- Orders --------------------------------------------------------------------------------

func _order_fire_target(side: int, pos: Vector2, radius: float) -> Regiment:
	var best: Regiment = null
	var best_d := radius
	for r: Regiment in regiments:
		if r.dead or r.side != side or r.state == ST_ROUT or r.state == ST_FORMING:
			continue
		if float(r.def.get("range", 0.0)) <= 0.0 or r.mounted or r.limbered:
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


## Your shooters within the circle that can be told to fire now.
func _order_shooters(side: int, pos: Vector2, radius: float) -> Array:
	var out: Array = []
	for r: Regiment in regiments:
		if r.dead or r.side != side or r.state == ST_ROUT or r.state == ST_FORMING:
			continue
		if float(r.def.get("range", 0.0)) <= 0.0 or r.mounted or r.limbered:
			continue
		if r.pos.distance_to(pos) <= radius:
			out.append(r)
	return out


## Your regiments within the circle that are still standing (not running), optionally only cavalry.
func _order_standing(side: int, pos: Vector2, radius: float, cavalry_only: bool = false) -> Array:
	var out: Array = []
	for r: Regiment in regiments:
		if r.dead or r.side != side or r.state == ST_ROUT or r.pos.distance_to(pos) > radius:
			continue
		if cavalry_only and r.arm != "cavalry":
			continue
		out.append(r)
	return out


## Why an order cannot be given there, or "".
func _order_error(side: int, def: Dictionary, pos: Vector2) -> String:
	var radius := float(def.get("radius", 1.0))
	match String(def.get("effect", "")):
		"fire":
			if _order_fire_target(side, pos, radius) == null:
				return "No regiment there to give the order to"
		"volley":
			if _order_shooters(side, pos, radius).is_empty():
				return "No regiment there to give the order to"
		"rally":
			if _order_rally_targets(side, pos, radius).is_empty():
				return "No regiment there to rally"
		"haste", "steady":
			if _order_standing(side, pos, radius).is_empty():
				return "No regiment there to give the order to"
		"bugle":
			if _order_standing(side, pos, radius, true).is_empty():
				return "No cavalry there to sound the charge for"
		"ambush":
			if in_creek(pos.y):
				return "Cannot deploy in the creek"
			for st: Structure in structures:
				if not st.dead and st.side != side and st.pos.distance_to(pos) < float(def.get("clear", 4.5)):
					return "Too close to the enemy's works"
	return ""


func _play_order(side: int, card_id: String, def: Dictionary, pos: Vector2) -> void:
	var radius := float(def.get("radius", 1.0))
	events.append({"type": "order", "pos": pos, "side": side, "card": card_id, "radius": radius})
	match String(def.get("effect", "")):
		"fire":
			var r := _order_fire_target(side, pos, radius)
			if r != null:
				r.reload = 0.0
				r.heat = 0.0
				r.fired_first = false      # on the word of command: as steady as the first volley
		"volley":
			for r: Regiment in _order_shooters(side, pos, radius):
				r.reload = 0.0
				r.heat = 0.0
				r.fired_first = false
		"rally":
			for r: Regiment in _order_rally_targets(side, pos, radius):
				if r.state == ST_ROUT:
					_rally(r, float(def["morale_restore"]))
				else:
					r.morale = minf(r.morale_max, r.morale + float(def["morale_restore"]))
		"barrage":
			var off_map := Vector2(pos.x, -2.0 if side == 0 else FIELD_H + 2.0)
			_launch_shell(side, off_map, pos, float(def["dmg"]), float(def["struct_dmg"]), radius, float(def["delay"]), "barrage")
		"haste":
			for r: Regiment in _order_standing(side, pos, radius):
				r.haste_until = tick_count + int(round(float(def["duration"]) / DT))
				r.haste_mult = float(def["mult"])
		"steady":
			for r: Regiment in _order_standing(side, pos, radius):
				r.steady_until = tick_count + int(round(float(def["duration"]) / DT))
				r.morale = minf(r.morale_max, r.morale + float(def.get("morale_restore", 0.0)))
		"bugle":
			for r: Regiment in _order_standing(side, pos, radius, true):
				r.runup = CHARGE_RUNUP
				r.recoil = 0.0
				r.haste_until = tick_count + int(round(float(def["duration"]) / DT))
				r.haste_mult = float(def["mult"])
		"raid":
			powder[1 - side] = maxf(0.0, powder[1 - side] - float(def["drain"]))
			events.append({"type": "raid", "pos": pos, "side": side})
		"ambush":
			spawn(side, String(def["spawn"]), pos)


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


## What the leaders within reach do for a regiment, as a factor: "aura_nerve" (the share of
## nerve it loses; the smallest wins), or "aura_reload", "aura_speed", "aura_regen" (how much
## faster; the largest wins). 1.0 where no leader is near. A leader does nothing for himself.
func _aura(r: Regiment, key: String) -> float:
	var best := 1.0
	for g: Regiment in _auras:
		if g == r or g.side != r.side or g.dead or not g.def.has(key):
			continue
		if r.pos.distance_to(g.pos) > float(g.def["aura"]):
			continue
		var v := float(g.def[key])
		best = minf(best, v) if key == "aura_nerve" else maxf(best, v)
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
	var too_close := float(r.def.get("min_range", 0.0))
	var snipes := bool(r.def.get("snipe", false))
	for o: Regiment in regiments:
		if o.dead or o.side == r.side:
			continue
		var d := r.pos.distance_to(o.pos)
		if d > shoot_range or d < too_close:
			continue
		var score := d + (3.0 if o.state == ST_ROUT else 0.0)
		if snipes and (o.arm == "artillery" or o.arm == "command"):
			score -= 100.0             # gunners and officers first
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
		if d <= shoot_range and d < best_d and d >= float(r.def.get("min_range", 0.0)) - s.radius:
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
		var soft := o.arm == "artillery" or o.arm == "command" or bool(o.def.get("loose", false)) or o.state == ST_ROUT
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
	if tick_count < r.haste_until:
		speed *= r.haste_mult
	if not _auras.is_empty():
		speed *= _aura(r, "aura_speed")
	if r.arm == "cavalry":
		for w: Work in works:
			if w.effect == "abatis" and w.side != r.side and _in_abatis(r.pos, w):
				speed *= ABATIS_SLOW
				break
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
			var a_fixed := a.state == ST_SQUARE or a.state == ST_FORMING or (a.arm == "artillery" and not a.limbered)
			var b_fixed := b.state == ST_SQUARE or b.state == ST_FORMING or (b.arm == "artillery" and not b.limbered)
			if not a_fixed:
				a.pos = _fix_pos(a.pos - push * amount)
			if not b_fixed:
				b.pos = _fix_pos(b.pos + push * amount)
