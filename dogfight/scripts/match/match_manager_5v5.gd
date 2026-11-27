class_name MatchManager5v5
extends Node
## Runs one 5v5 Air Supremacy match: roster, spawning, score, timer, respawns.
##
## Rules (all read from GameSession so the lobby can change them):
##  - Two teams of five. Every seat is always filled; seats without a human
##    get a SquadAIController, so 1 player + 9 bots works out of the box.
##  - Ticket drain: every plane lost gives the *other* team one point. Planes
##    have no health: one is lost when it hits the sea, the ground, a ship, or
##    another aircraft too hard to survive. Whoever crippled it gets the credit.
##  - First team to the score limit wins, otherwise the higher score when the
##    clock runs out. Equal scores are a draw.
##  - Everyone starts parked on their own airfield with the engine off, and
##    has to start up and take off. A downed pilot gets a new plane on the
##    same airfield after a delay, protected until it leaves the ground.
##  - A damaged plane that lands at its own airfield and stops is repaired.
##
## Networking: this node only does work on the server (or offline, where the
## local instance is the server). Planes are added under `planes_root`, which
## the scene's MultiplayerSpawner watches, so clients receive them
## automatically. assign_human()/release_to_ai() hand a seat between a peer
## and a bot without touching the plane itself.

signal phase_changed(new_phase: Phase)
signal score_changed(blue_score: int, red_score: int)
## [param killer] is null when the victim crashed on their own.
signal takedown(victim: PilotSlot, killer: PilotSlot)
signal match_ended(winning_team: int)

enum Phase { COUNTDOWN, ACTIVE, FINISHED }

## `winning_team` value for a tied match.
const DRAW: int = -1
const COUNTDOWN_TIME: float = 3.0
## A parking spot is busy if another plane is on the ground this close to it (m).
const PARKING_CLEARANCE: float = 24.0
const PARKING_RETRY_TIME: float = 0.5
const BOT_NAMES: Array[String] = [
	"Biggles", "Maverick", "Dusty", "Skipper", "Red Baroness", "Lucky", "Ginger",
	"Hawk", "Whiskey", "Bandit", "Rocket", "Duchess", "Tailspin", "Flak", "Ace of Clubs",
	"Sparks", "Vulture", "Blitz", "Comet", "Mustard",
]

@export var plane_scene: PackedScene
## Parent for every PlaneActor. Must be the MultiplayerSpawner's spawn path.
@export var planes_root: Node3D
@export var controllers_root: Node
@export var bullet_system: BulletSystem
@export var midair_collisions: MidairCollisions
## The arena, for its airfields. Without one (or with GameSession.ground_start
## off) planes start in the air at the spawn markers instead.
@export var arena: ArenaBuilder
@export var blue_spawns: Node3D
@export var red_spawns: Node3D
@export var arena_center: Vector3 = Vector3.ZERO
@export var arena_radius: float = 3200.0
@export var arena_ceiling: float = 4500.0

var phase: Phase = Phase.COUNTDOWN
var time_left: float = 300.0
var countdown_left: float = COUNTDOWN_TIME
var winning_team: int = DRAW
## Payout for the local player, filled in when the match ends (null for bots-only).
var last_rewards: MatchRewards

var _scores: Array[int] = [0, 0]
var _roster: Array[PilotSlot] = []
var _planes: Array[PlaneActor] = []
var _blackboard: SquadBlackboard = SquadBlackboard.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	if not multiplayer.is_server():
		set_physics_process(false)
		return
	var roster_seed: int = GameSession.match_seed
	if roster_seed == 0:
		roster_seed = int(randi())
	_rng.seed = roster_seed + 1
	time_left = GameSession.match_duration
	_roster = build_roster(roster_seed)
	for slot: PilotSlot in _roster:
		if slot.is_local:
			slot.peer_id = multiplayer.get_unique_id()
	for slot: PilotSlot in _roster:
		_spawn_plane(slot)
	_set_weapons_locked(true)
	phase_changed.emit(phase)
	score_changed.emit(_scores[0], _scores[1])


func _physics_process(delta: float) -> void:
	match phase:
		Phase.COUNTDOWN:
			countdown_left -= delta
			if countdown_left <= 0.0:
				countdown_left = 0.0
				_set_phase(Phase.ACTIVE)
				_set_weapons_locked(false)
		Phase.ACTIVE:
			time_left = maxf(time_left - delta, 0.0)
			_tick_respawns(delta)
			if time_left <= 0.0:
				_finish_match()
		Phase.FINISHED:
			pass


# ---------------------------------------------------------------------------
# Queries (used by the HUD, the camera and the controllers)
# ---------------------------------------------------------------------------

## Every plane in the match, alive or not. Do not modify the returned array.
func get_planes() -> Array[PlaneActor]:
	return _planes


func get_roster() -> Array[PilotSlot]:
	return _roster


func team_score(team: Teams.Id) -> int:
	return _scores[team]


func score_limit() -> int:
	return GameSession.score_limit


func team_size() -> int:
	return GameSession.team_size


## The seat flown by the player on this device, or null in a bots-only match.
func local_slot() -> PilotSlot:
	for slot: PilotSlot in _roster:
		if slot.is_local:
			return slot
	return null


func slot_for_plane(plane: PlaneActor) -> PilotSlot:
	for slot: PilotSlot in _roster:
		if slot.plane == plane:
			return slot
	return null


## First seat on [param team] that a bot is flying, or null if the team is full of humans.
func find_bot_slot(team: Teams.Id) -> PilotSlot:
	for slot: PilotSlot in _roster:
		if slot.team == team and not slot.is_human:
			return slot
	return null


# ---------------------------------------------------------------------------
# Seat hand-over (humans joining/leaving mid-match)
# ---------------------------------------------------------------------------

## Gives a bot's seat to a human. The plane keeps flying; only the pilot changes.
func assign_human(slot: PilotSlot, peer_id: int, display_name: String) -> void:
	if slot == null or not multiplayer.is_server():
		return
	slot.is_human = true
	slot.peer_id = peer_id
	slot.is_local = peer_id == multiplayer.get_unique_id()
	slot.display_name = display_name
	slot.plane.pilot_name = display_name
	slot.plane.is_human = true
	slot.plane.owner_peer_id = peer_id
	slot.plane.input.set_multiplayer_authority(peer_id)
	_attach_controller(slot)


## A human left: a bot takes the stick on the spot, score and plane untouched.
func release_to_ai(slot: PilotSlot) -> void:
	if slot == null or not multiplayer.is_server():
		return
	slot.is_human = false
	slot.is_local = false
	slot.peer_id = 1
	slot.plane.is_human = false
	slot.plane.owner_peer_id = 1
	slot.plane.input.set_multiplayer_authority(1)
	_attach_controller(slot)


# ---------------------------------------------------------------------------
# Roster and spawning
# ---------------------------------------------------------------------------

## Builds the ten seats for a match. Static and driven only by [param roster_seed]
## so the lobby can show exactly the line-up the arena will then spawn.
static func build_roster(roster_seed: int) -> Array[PilotSlot]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = roster_seed
	var names: Array[String] = BOT_NAMES.duplicate()
	for index: int in range(names.size() - 1, 0, -1):
		var swap: int = rng.randi_range(0, index)
		var held: String = names[index]
		names[index] = names[swap]
		names[swap] = held
	var roster: Array[PilotSlot] = []
	var player_level: int = Profile.commander_level()
	for team_index: int in range(Teams.COUNT):
		for seat: int in range(GameSession.team_size):
			var slot: PilotSlot = PilotSlot.new()
			slot.index = roster.size()
			slot.team = team_index as Teams.Id
			slot.seat = seat
			if GameSession.local_player_enabled and slot.team == GameSession.local_team and seat == 0:
				slot.is_human = true
				slot.is_local = true
				slot.display_name = Profile.pilot_name
				slot.commander_level = player_level
			else:
				slot.display_name = names[slot.index % names.size()]
				# Bots sit within a level of the player so matches stay fair.
				slot.commander_level = clampi(player_level + rng.randi_range(-1, 1), 1, CommanderProgression.MAX_LEVEL)
				slot.bot_skill = clampf(GameSession.bot_skill + rng.randf_range(-0.2, 0.2), 0.05, 1.0)
			roster.append(slot)
	return roster


func _spawn_plane(slot: PilotSlot) -> void:
	var plane: PlaneActor = plane_scene.instantiate() as PlaneActor
	plane.name = "Plane%d_%s" % [slot.index, Teams.name_of(slot.team)]
	if slot.is_local:
		plane.setup(Profile.selected_plane(), Profile.build_player_stats(), slot.team, slot.display_name, slot.peer_id)
	else:
		var data: PlaneData = GameCatalog.best_plane_for_level(slot.commander_level)
		plane.setup(data, _build_bot_stats(data, slot.commander_level), slot.team, slot.display_name, 1)
	plane.is_human = slot.is_human
	plane.seed_random(int(_rng.randi()))
	plane.arena_center = arena_center
	plane.arena_radius = arena_radius
	plane.arena_ceiling = arena_ceiling
	plane.bullet_system = bullet_system
	if arena != null:
		plane.airfields = arena.airfields
	planes_root.add_child(plane, true)
	for field: Airfield in plane.airfields:
		# Planes stand on the airfield by arithmetic, not by bumping into it.
		plane.add_collision_exception_with(field.ground_body)
	slot.plane = plane
	_planes.append(plane)
	bullet_system.register_plane(plane)
	if midair_collisions != null:
		midair_collisions.register_plane(plane)
	plane.died.connect(_on_plane_died)
	_place_plane(slot, true)
	_attach_controller(slot)


## Creates the right pilot for a seat, replacing whatever was there before.
func _attach_controller(slot: PilotSlot) -> void:
	if slot.controller != null and is_instance_valid(slot.controller):
		slot.controller.queue_free()
		slot.controller = null
	if slot.is_human:
		if slot.is_local:
			var player: PlayerController = PlayerController.new()
			player.name = "Player_%d" % slot.index
			player.plane = slot.plane
			player.match_manager = self
			controllers_root.add_child(player)
			slot.controller = player
		# A remote human needs no controller here: their PlaneInput is
		# replicated to the server by the plane's InputSync.
		return
	var bot: SquadAIController = SquadAIController.new()
	bot.name = "Bot_%d" % slot.index
	bot.skill = slot.bot_skill
	bot.setup(slot.plane, self, _blackboard, int(_rng.randi()))
	controllers_root.add_child(bot)
	slot.controller = bot


## Bots fly a believable loadout for their level: two to four guns of one
## kind, and for each other mount either the standard item or something
## better, more often as the level rises. Nothing Legendary.
func _build_bot_stats(data: PlaneData, commander_level: int) -> PlaneStats:
	var fittings: Array[ComponentCard] = GameCatalog.stock_fittings()
	var marks: Array[int] = GameCatalog.stock_marks()
	var mark: int = clampi(1 + floori(float(commander_level) / 3.0), 1, ComponentCard.MAX_MARK)
	var upgrade_chance: float = clampf(0.15 + 0.06 * float(commander_level), 0.0, 0.8)
	var guns: Array[ComponentCard] = GameCatalog.cards_in_slot(ComponentCard.Slot.GUN)
	var gun: ComponentCard = guns[0]
	if _rng.randf() < upgrade_chance:
		gun = guns[_rng.randi_range(0, guns.size() - 1)]
	var gun_count: int = 2 + (_rng.randi_range(0, 2) if _rng.randf() < upgrade_chance else 0)
	for mount: int in range(CommanderProgression.MOUNT_COUNT):
		if CommanderProgression.is_gun_station(mount):
			fittings[mount] = gun if mount < gun_count else null
			marks[mount] = mark
			continue
		if _rng.randf() >= upgrade_chance:
			continue
		var options: Array[ComponentCard] = []
		for option: ComponentCard in GameCatalog.cards_in_slot(CommanderProgression.MOUNT_SLOTS[mount]):
			if option.rarity != ComponentCard.Rarity.LEGENDARY:
				options.append(option)
		if not options.is_empty():
			fittings[mount] = options[_rng.randi_range(0, options.size() - 1)]
			marks[mount] = mark
	return data.build_stats(commander_level, fittings, marks)


## Puts a seat's plane into the match, factory fresh: parked on its own
## airfield, or in the air if there is no airfield to park on. Returns false
## (and does nothing) if every parking spot is busy and [param force] is off.
func _place_plane(slot: PilotSlot, force: bool) -> bool:
	var field: Airfield = _home_airfield(slot.team)
	if field == null:
		slot.plane.respawn(_air_spawn_transform(slot))
		return true
	var spot: int = _free_parking_spot(field, slot)
	if spot < 0:
		if not force:
			return false
		spot = slot.seat
	slot.plane.respawn(field.parking_transform(spot), true)
	return true


func _home_airfield(team: Teams.Id) -> Airfield:
	if arena == null or not GameSession.ground_start:
		return null
	return arena.airfield_for(team)


## The seat's own parking spot if nothing is standing on it or about to roll
## through it, otherwise the first spare one that is clear. -1 if none is.
func _free_parking_spot(field: Airfield, slot: PilotSlot) -> int:
	var candidates: Array[int] = [slot.seat % field.parking_spot_count()]
	for spot: int in range(field.parking_spot_count() - 1, -1, -1):
		if not candidates.has(spot):
			candidates.append(spot)
	for spot: int in candidates:
		if _is_parking_spot_clear(field, spot, slot.plane):
			return spot
	return -1


func _is_parking_spot_clear(field: Airfield, spot: int, for_plane: PlaneActor) -> bool:
	var place: Vector2 = field.runway_coordinates(field.parking_transform(spot).origin)
	for other: PlaneActor in _planes:
		if other == for_plane or not other.alive or not other.is_on_ground():
			continue
		var where: Vector2 = field.runway_coordinates(other.global_position)
		if where.distance_to(place) < PARKING_CLEARANCE:
			return false
		# Something further back in the same lane is already rolling this way.
		var same_lane: bool = absf(where.x - place.x) < PARKING_CLEARANCE * 0.5
		if same_lane and where.y < place.y and other.speed > 1.0:
			return false
	return true


## Airborne spawn above the team's base, nose pointed at the middle of the arena.
func _air_spawn_transform(slot: PilotSlot) -> Transform3D:
	var group: Node3D = blue_spawns if slot.team == Teams.Id.TEAM_BLUE else red_spawns
	var marker: Node3D = group.get_child(slot.seat % group.get_child_count()) as Node3D
	var origin: Vector3 = marker.global_position
	var to_center: Vector3 = arena_center - origin
	to_center.y = 0.0
	if to_center.length_squared() < 1.0:
		to_center = Vector3.FORWARD
	return Transform3D(Basis.looking_at(to_center.normalized(), Vector3.UP), origin)


# ---------------------------------------------------------------------------
# Scoring, respawns, end of match
# ---------------------------------------------------------------------------

func _on_plane_died(victim: PlaneActor, killer: PlaneActor) -> void:
	var victim_slot: PilotSlot = slot_for_plane(victim)
	if victim_slot == null:
		return
	victim_slot.respawn_timer = GameSession.respawn_delay
	if phase != Phase.ACTIVE:
		return
	victim_slot.deaths += 1
	var killer_slot: PilotSlot = null
	if killer != null and is_instance_valid(killer) and killer.is_hostile_to(victim):
		killer_slot = slot_for_plane(killer)
		if killer_slot != null:
			killer_slot.kills += 1
	# Ticket drain: the loss counts for the other team no matter how it happened.
	var scoring_team: Teams.Id = Teams.opponent_of(victim.team)
	_scores[scoring_team] += 1
	takedown.emit(victim_slot, killer_slot)
	score_changed.emit(_scores[0], _scores[1])
	if _scores[scoring_team] >= GameSession.score_limit:
		_finish_match()


func _tick_respawns(delta: float) -> void:
	for slot: PilotSlot in _roster:
		if slot.respawn_timer <= 0.0:
			continue
		slot.respawn_timer -= delta
		if slot.respawn_timer <= 0.0:
			# If the airfield is crowded the new plane waits a moment longer.
			slot.respawn_timer = 0.0 if _place_plane(slot, false) else PARKING_RETRY_TIME


func _finish_match() -> void:
	if phase == Phase.FINISHED:
		return
	var blue: int = _scores[Teams.Id.TEAM_BLUE]
	var red: int = _scores[Teams.Id.TEAM_RED]
	if blue > red:
		winning_team = Teams.Id.TEAM_BLUE
	elif red > blue:
		winning_team = Teams.Id.TEAM_RED
	else:
		winning_team = DRAW
	_set_weapons_locked(true)
	var player: PilotSlot = local_slot()
	if player != null:
		last_rewards = Profile.grant_match_rewards(winning_team == int(player.team), player.kills)
	_set_phase(Phase.FINISHED)
	match_ended.emit(winning_team)


func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	phase_changed.emit(phase)


func _set_weapons_locked(locked: bool) -> void:
	for plane: PlaneActor in _planes:
		plane.weapons_locked = locked
