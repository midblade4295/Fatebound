class_name BattleAudio
extends Node
## The sounds that belong to the listener rather than to any one plane:
##  - wind over the cockpit, rising with speed (it is all that is left when
##    the engine stops),
##  - bullets that pass close by, each a short crack-and-zip placed where it
##    went past so it pans and fades correctly,
##  - rounds striking the listener's own plane, and a quieter tick when the
##    listener's rounds strike someone else,
##  - aircraft colliding.
## Lives in the arena scene and is wired up by dogfight_arena.gd.

const SOUND_WIND: AudioStream = preload("res://assets/audio/wind.wav")
const SOUND_WHIZ: Array[AudioStream] = [
	preload("res://assets/audio/bullet_whiz_1.wav"), preload("res://assets/audio/bullet_whiz_2.wav"),
	preload("res://assets/audio/bullet_whiz_3.wav"), preload("res://assets/audio/bullet_whiz_4.wav"),
]
const SOUND_HIT: Array[AudioStream] = [
	preload("res://assets/audio/bullet_hit_1.wav"), preload("res://assets/audio/bullet_hit_2.wav"),
	preload("res://assets/audio/bullet_hit_3.wav"), preload("res://assets/audio/bullet_hit_4.wav"),
]
const SOUND_COLLISION: Array[AudioStream] = [
	preload("res://assets/audio/collision_1.wav"), preload("res://assets/audio/collision_2.wav"),
]

const WIND_MIN_DB: float = -30.0
const WIND_MAX_DB: float = -11.0
## Whiz sounds are spaced at least this far apart, or a long burst passing
## by turns into a wall of noise.
const WHIZ_MIN_INTERVAL: float = 0.045
const WHIZ_VOICES: int = 5

var listener: PlaneActor

var _wind: AudioStreamPlayer
var _whiz_players: Array[AudioStreamPlayer3D] = []
var _next_whiz: int = 0
var _whiz_cooldown: float = 0.0
var _hits_taken: AudioStreamPlayer
var _hits_scored: AudioStreamPlayer
var _collisions: AudioStreamPlayer3D
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_wind = AudioStreamPlayer.new()
	_wind.name = "Wind"
	_wind.stream = SoundTools.looped(SOUND_WIND)
	_wind.volume_db = WIND_MIN_DB
	add_child(_wind)
	for index: int in range(WHIZ_VOICES):
		var whiz: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		whiz.name = "Whiz%d" % index
		whiz.unit_size = 14.0
		whiz.max_distance = 120.0
		whiz.volume_db = 5.0
		add_child(whiz)
		_whiz_players.append(whiz)
	_hits_taken = AudioStreamPlayer.new()
	_hits_taken.name = "HitsTaken"
	_hits_taken.volume_db = -1.0
	_hits_taken.max_polyphony = 4
	add_child(_hits_taken)
	_hits_scored = AudioStreamPlayer.new()
	_hits_scored.name = "HitsScored"
	_hits_scored.volume_db = -13.0
	_hits_scored.max_polyphony = 3
	add_child(_hits_scored)
	_collisions = AudioStreamPlayer3D.new()
	_collisions.name = "Collisions"
	_collisions.unit_size = 80.0
	_collisions.max_distance = 1800.0
	_collisions.volume_db = 5.0
	_collisions.max_polyphony = 3
	add_child(_collisions)


## Connects to a running match. [param local_plane] is the plane the listener
## flies, or null when spectating (then only world sounds play).
func bind(manager: MatchManager5v5, local_plane: PlaneActor) -> void:
	listener = local_plane
	manager.bullet_system.listener = local_plane
	manager.bullet_system.bullet_whizzed.connect(_on_bullet_whizzed)
	manager.bullet_system.bullet_hit.connect(_on_bullet_hit)
	if manager.midair_collisions != null:
		manager.midair_collisions.planes_collided.connect(_on_planes_collided)
	if local_plane != null:
		_wind.play()


## Follows a new plane (spectator camera changes, hand-over of a seat).
func set_listener(manager: MatchManager5v5, local_plane: PlaneActor) -> void:
	listener = local_plane
	manager.bullet_system.listener = local_plane


func _process(delta: float) -> void:
	_whiz_cooldown = maxf(_whiz_cooldown - delta, 0.0)
	if listener == null or not is_instance_valid(listener) or not _wind.playing:
		return
	# Wind: louder and a little higher the faster you go. Silent when dead.
	var speed_ratio: float = clampf(listener.speed / maxf(listener.stats.top_speed, 1.0), 0.0, 1.5) if listener.alive else 0.0
	var target_db: float = lerpf(WIND_MIN_DB, WIND_MAX_DB, clampf(speed_ratio / 1.3, 0.0, 1.0)) if listener.alive else -60.0
	_wind.volume_db = lerpf(_wind.volume_db, target_db, 1.0 - exp(-3.0 * delta))
	_wind.pitch_scale = lerpf(0.85, 1.25, clampf(speed_ratio / 1.3, 0.0, 1.0))


func _on_bullet_whizzed(world_position: Vector3) -> void:
	if _whiz_cooldown > 0.0:
		return
	_whiz_cooldown = WHIZ_MIN_INTERVAL
	var player: AudioStreamPlayer3D = _whiz_players[_next_whiz]
	_next_whiz = (_next_whiz + 1) % _whiz_players.size()
	player.global_position = world_position
	player.stream = SOUND_WHIZ[_rng.randi_range(0, SOUND_WHIZ.size() - 1)]
	player.pitch_scale = _rng.randf_range(0.9, 1.15)
	player.play()


func _on_bullet_hit(victim: PlaneActor, shooter: PlaneActor, _world_position: Vector3) -> void:
	if listener == null:
		return
	if victim == listener:
		# Rounds going through your own aeroplane: loud and close.
		_hits_taken.stream = SOUND_HIT[_rng.randi_range(0, SOUND_HIT.size() - 1)]
		_hits_taken.pitch_scale = _rng.randf_range(0.9, 1.1)
		_hits_taken.play()
	elif shooter == listener:
		_hits_scored.stream = SOUND_HIT[_rng.randi_range(0, SOUND_HIT.size() - 1)]
		_hits_scored.pitch_scale = _rng.randf_range(1.15, 1.35)
		_hits_scored.play()


func _on_planes_collided(first: PlaneActor, second: PlaneActor, _first_part: int, _second_part: int, closing_speed: float) -> void:
	_collisions.global_position = (first.global_position + second.global_position) * 0.5
	_collisions.stream = SOUND_COLLISION[_rng.randi_range(0, SOUND_COLLISION.size() - 1)]
	# A scrape is quieter and higher than a full-blooded smash.
	var violence: float = clampf(closing_speed / 80.0, 0.15, 1.0)
	_collisions.volume_db = lerpf(-8.0, 6.0, violence)
	_collisions.pitch_scale = lerpf(1.2, 0.9, violence) * _rng.randf_range(0.95, 1.05)
	_collisions.play()
