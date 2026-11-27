class_name PlaneAudio
extends Node3D
## Everything one plane sounds like: its engine, its guns, fire, and the
## noises it makes coming apart.
##
## Each PlaneData names its own engine recording and gun samples, so a
## Hurricane, a Spitfire and a Mustang do not sound alike.
##
##  - Engine: one seamless loop whose pitch follows speed and whose level
##    follows power. A damaged engine misfires (the note stumbles); a dead one
##    coughs, winds down and leaves only the wind.
##  - Guns: one short sample per round actually fired, picked at random from
##    the plane's set with a small pitch change, so bursts never sound like a
##    looped recording and stay in step with the tracers.
##  - Positional for every other plane, with Doppler, so a pass really does
##    drop in pitch as it goes by. For the plane the listener is flying the
##    engine and guns play flat and close instead, as heard from the cockpit.
##
## Cosmetic only: runs on every peer from replicated state and signals.

const ENGINE_PITCH_MIN: float = 0.74
const ENGINE_PITCH_MAX: float = 1.2
const NITRO_PITCH_BONUS: float = 0.1
## Other planes: distance (m) at which they are at full level, and beyond
## which they are not heard at all.
const ENGINE_UNIT_SIZE: float = 38.0
const ENGINE_MAX_DISTANCE: float = 1100.0
const GUN_UNIT_SIZE: float = 70.0
const GUN_MAX_DISTANCE: float = 1500.0
const EVENT_UNIT_SIZE: float = 90.0
const EVENT_MAX_DISTANCE: float = 2200.0
## Levels in dB. The cockpit versions are quieter than "full level at the
## source" would be, or the player's own engine would bury everything else.
const COCKPIT_ENGINE_DB: float = -9.0
const COCKPIT_GUN_DB: float = -3.0
const REMOTE_ENGINE_DB: float = 2.0
const REMOTE_GUN_DB: float = 3.0
const GUN_PITCH_SPREAD: float = 0.05
## Rounds that can ring at once per plane before the oldest is cut off.
const GUN_VOICES: int = 6

const SOUND_EXPLOSION: Array[AudioStream] = [
	preload("res://assets/audio/explosion_1.wav"), preload("res://assets/audio/explosion_2.wav"),
]
const SOUND_BREAK: Array[AudioStream] = [
	preload("res://assets/audio/metal_tear_1.wav"), preload("res://assets/audio/metal_tear_2.wav"),
]
const SOUND_WATER_CRASH: AudioStream = preload("res://assets/audio/water_crash_1.wav")
const SOUND_ENGINE_FAIL: AudioStream = preload("res://assets/audio/engine_fail.wav")
const SOUND_FIRE: AudioStream = preload("res://assets/audio/fire.wav")

var plane: PlaneActor
## True for the plane the listener is flying.
var cockpit: bool = false: set = set_cockpit

var _engine_remote: AudioStreamPlayer3D
var _engine_cockpit: AudioStreamPlayer
var _guns_remote: AudioStreamPlayer3D
var _guns_cockpit: AudioStreamPlayer
var _fire: AudioStreamPlayer3D
var _events: AudioStreamPlayer3D
var _engine_level: float = 1.0
var _engine_was_running: bool = true
var _misfire_time: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Call once, after the plane has its PlaneData.
func setup(owner_plane: PlaneActor) -> void:
	plane = owner_plane
	_rng.randomize()
	var data: PlaneData = plane.plane_data
	var engine_stream: AudioStream = SoundTools.looped(data.engine_sound)

	_engine_remote = _make_3d("Engine", ENGINE_UNIT_SIZE, ENGINE_MAX_DISTANCE, REMOTE_ENGINE_DB)
	_engine_remote.stream = engine_stream
	_engine_remote.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	_engine_cockpit = AudioStreamPlayer.new()
	_engine_cockpit.name = "EngineCockpit"
	_engine_cockpit.stream = engine_stream
	_engine_cockpit.volume_db = COCKPIT_ENGINE_DB
	add_child(_engine_cockpit)

	_guns_remote = _make_3d("Guns", GUN_UNIT_SIZE, GUN_MAX_DISTANCE, REMOTE_GUN_DB)
	_guns_remote.max_polyphony = GUN_VOICES
	_guns_cockpit = AudioStreamPlayer.new()
	_guns_cockpit.name = "GunsCockpit"
	_guns_cockpit.volume_db = COCKPIT_GUN_DB
	_guns_cockpit.max_polyphony = GUN_VOICES
	add_child(_guns_cockpit)

	_fire = _make_3d("Fire", 25.0, 500.0, 0.0)
	_fire.stream = SoundTools.looped(SOUND_FIRE)
	_events = _make_3d("Events", EVENT_UNIT_SIZE, EVENT_MAX_DISTANCE, 4.0)
	_events.max_polyphony = 4

	plane.shot_fired.connect(_on_shot_fired)
	plane.part_state_changed.connect(_on_part_state_changed)
	plane.died.connect(_on_died)
	plane.respawned.connect(_on_respawned)
	_start_engine()


func set_cockpit(value: bool) -> void:
	cockpit = value
	if _engine_remote == null:
		return
	# Swap which engine player is sounding without restarting the loop.
	var position_in_loop: float = _active_engine_position()
	_engine_remote.stop()
	_engine_cockpit.stop()
	if plane.alive:
		_start_engine(position_in_loop)


func _process(delta: float) -> void:
	if plane == null or not plane.alive:
		return
	var power: float = plane.engine_power()
	var running: bool = power > 0.0
	if _engine_was_running and not running:
		# The engine has just died: a cough and a wind-down over the top.
		_play_event(SOUND_ENGINE_FAIL, 1.0, -2.0)
	_engine_was_running = running

	# Level follows power, easing so a dying engine fades rather than cuts.
	var target_level: float = 0.0 if not running else lerpf(0.55, 1.0, power)
	_engine_level = lerpf(_engine_level, target_level, 1.0 - exp(-1.6 * delta))
	var speed_ratio: float = clampf(plane.speed / maxf(plane.stats.top_speed, 1.0), 0.3, 1.5)
	var pitch: float = lerpf(ENGINE_PITCH_MIN, ENGINE_PITCH_MAX, clampf((speed_ratio - 0.4) / 0.9, 0.0, 1.0))
	if plane.is_boosting():
		pitch += NITRO_PITCH_BONUS
	# A hurt engine misfires: every so often the note sags for a moment.
	var engine_damage: float = plane.part_damage_of(PlaneActor.Part.ENGINE)
	if running and engine_damage >= PlaneActor.PART_DAMAGED_AT:
		_misfire_time -= delta
		if _misfire_time <= 0.0:
			_misfire_time = _rng.randf_range(0.12, lerpf(0.9, 0.3, engine_damage))
		if _misfire_time < 0.07:
			pitch *= 0.86
	var level_db: float = linear_to_db(maxf(_engine_level, 0.0001))
	if cockpit:
		_engine_cockpit.pitch_scale = pitch
		_engine_cockpit.volume_db = COCKPIT_ENGINE_DB + level_db
	else:
		_engine_remote.pitch_scale = pitch
		_engine_remote.volume_db = REMOTE_ENGINE_DB + level_db

	var burning: bool = plane.has_flag(PlaneActor.FLAG_BURNING)
	if burning != _fire.playing:
		if burning:
			_fire.play(_rng.randf_range(0.0, 2.0))
		else:
			_fire.stop()


func _start_engine(from_position: float = -1.0) -> void:
	var stream: AudioStream = _engine_remote.stream
	if stream == null:
		return
	# Start each plane somewhere different in the loop, or ten identical
	# engines would beat against each other in step.
	var start: float = from_position if from_position >= 0.0 else _rng.randf_range(0.0, maxf(stream.get_length() - 0.1, 0.0))
	if cockpit:
		_engine_cockpit.play(start)
	else:
		_engine_remote.play(start)


func _active_engine_position() -> float:
	if _engine_cockpit.playing:
		return _engine_cockpit.get_playback_position()
	if _engine_remote.playing:
		return _engine_remote.get_playback_position()
	return -1.0


func _on_shot_fired(_plane: PlaneActor) -> void:
	var samples: Array[AudioStream] = plane.plane_data.gun_sounds
	if samples.is_empty():
		return
	var sample: AudioStream = samples[_rng.randi_range(0, samples.size() - 1)]
	var pitch: float = plane.plane_data.gun_pitch * _rng.randf_range(1.0 - GUN_PITCH_SPREAD, 1.0 + GUN_PITCH_SPREAD)
	if cockpit:
		_guns_cockpit.stream = sample
		_guns_cockpit.pitch_scale = pitch
		_guns_cockpit.play()
	else:
		_guns_remote.stream = sample
		_guns_remote.pitch_scale = pitch
		_guns_remote.play()


func _on_part_state_changed(_plane: PlaneActor, part: PlaneActor.Part, state: PlaneActor.PartState) -> void:
	# Something has been torn off.
	if state == PlaneActor.PartState.DESTROYED and PlaneActor.PART_DETACHES[part]:
		_play_event(SOUND_BREAK[_rng.randi_range(0, SOUND_BREAK.size() - 1)], _rng.randf_range(0.9, 1.1), 2.0 if cockpit else 0.0)


func _on_died(_victim: PlaneActor, _killer: PlaneActor) -> void:
	_engine_remote.stop()
	_engine_cockpit.stop()
	_fire.stop()
	# Into the sea, or into something harder.
	if plane.global_position.y < 25.0:
		_play_event(SOUND_WATER_CRASH, _rng.randf_range(0.92, 1.05), 2.0)
	_play_event(SOUND_EXPLOSION[_rng.randi_range(0, SOUND_EXPLOSION.size() - 1)], _rng.randf_range(0.9, 1.08), 3.0)


func _on_respawned(_plane: PlaneActor) -> void:
	_engine_level = 1.0
	_engine_was_running = true
	_start_engine()


func _play_event(stream: AudioStream, pitch: float, volume_db: float) -> void:
	_events.stream = stream
	_events.pitch_scale = pitch
	_events.volume_db = volume_db
	_events.play()


func _make_3d(player_name: String, unit_size: float, max_distance: float, volume_db: float) -> AudioStreamPlayer3D:
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.name = player_name
	player.unit_size = unit_size
	player.max_distance = max_distance
	player.volume_db = volume_db
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	# High frequencies die away with distance, so far-off planes rumble.
	player.attenuation_filter_cutoff_hz = 6000.0
	player.attenuation_filter_db = -18.0
	add_child(player)
	return player
