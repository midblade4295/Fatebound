class_name PlaneAudio
extends Node3D
## Everything one plane sounds like: its engine, its guns, fire, and the
## noises it makes coming apart.
##
## Each PlaneData names its own engine recording and gun samples, so a
## Hurricane, a Spitfire and a Mustang do not sound alike.
##
##  - Engine: one seamless loop. Its note follows the throttle (revs) and,
##    less, the airspeed; its level follows throttle and power. Starting up
##    plays the starter and the engine catching, with the loop fading in under
##    it. A damaged engine misfires (the note stumbles); a dead one coughs,
##    winds down and leaves only the wind.
##  - On the ground: the wheels rumble with speed, the tyres chirp on
##    touchdown, and the undercarriage whines and clunks home.
##  - Guns: one short sample per round actually fired, picked at random from
##    the plane's set with a small pitch change, so bursts never sound like a
##    looped recording and stay in step with the tracers.
##  - Positional for every other plane, with Doppler, so a pass really does
##    drop in pitch as it goes by. For the plane the listener is flying the
##    engine and guns play flat and close instead, as heard from the cockpit.
##
## Cosmetic only: runs on every peer from replicated state and signals.

## Engine note = revs (throttle) x a smaller change with airspeed.
const IDLE_PITCH: float = 0.68
const SLOW_PITCH: float = 0.74
const FAST_PITCH: float = 1.16
## Share of full level an idling engine makes.
const IDLE_LEVEL: float = 0.3
## The loop comes in under the start-up sound between these times (seconds
## after the starter is pressed), which is when the recording's engine catches.
const START_FADE_BEGIN: float = 1.3
const START_FADE_END: float = 2.4
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
const SOUND_ENGINE_START: AudioStream = preload("res://assets/audio/engine_start.wav")
const SOUND_GEAR: AudioStream = preload("res://assets/audio/gear.wav")
const SOUND_GROUND_ROLL: AudioStream = preload("res://assets/audio/ground_roll.wav")
const SOUND_TOUCHDOWN: Array[AudioStream] = [
	preload("res://assets/audio/touchdown_1.wav"), preload("res://assets/audio/touchdown_2.wav"),
]

var plane: PlaneActor
## True for the plane the listener is flying.
var cockpit: bool = false: set = set_cockpit

var _engine_remote: AudioStreamPlayer3D
var _engine_cockpit: AudioStreamPlayer
var _guns_remote: AudioStreamPlayer3D
var _guns_cockpit: AudioStreamPlayer
var _fire: AudioStreamPlayer3D
var _events: AudioStreamPlayer3D
var _starter: AudioStreamPlayer3D
var _gear: AudioStreamPlayer3D
var _roll: AudioStreamPlayer3D
var _engine_level: float = 1.0
var _engine_was_running: bool = true
var _stopped_by_pilot: bool = false
## Seconds since the starter was pressed; INF once the engine is simply running.
var _start_age: float = INF
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
	_starter = _make_3d("Starter", ENGINE_UNIT_SIZE, ENGINE_MAX_DISTANCE, 3.0)
	_starter.stream = SOUND_ENGINE_START
	_gear = _make_3d("Gear", 18.0, 250.0, 0.0)
	_gear.stream = SOUND_GEAR
	_roll = _make_3d("GroundRoll", 20.0, 350.0, -30.0)
	_roll.stream = SoundTools.looped(SOUND_GROUND_ROLL)

	plane.shot_fired.connect(_on_shot_fired)
	plane.part_state_changed.connect(_on_part_state_changed)
	plane.died.connect(_on_died)
	plane.respawned.connect(_on_respawned)
	plane.engine_started.connect(_on_engine_started)
	plane.engine_stopped.connect(_on_engine_stopped)
	plane.gear_moved.connect(_on_gear_moved)
	plane.touched_down.connect(_on_touched_down)
	_engine_was_running = plane.is_engine_running()
	_engine_level = 1.0 if _engine_was_running else 0.0
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
	var running: bool = plane.is_engine_running()
	if _engine_was_running and not running:
		# Shot dead or out of fuel: a cough and a wind-down over the top. A
		# pilot switching off gets the same wind-down, only quieter.
		_play_event(SOUND_ENGINE_FAIL, 1.12 if _stopped_by_pilot else 1.0, -9.0 if _stopped_by_pilot else -2.0)
	_engine_was_running = running
	_stopped_by_pilot = false
	# Level follows throttle and power, easing so changes swell and fade.
	var target_level: float = 0.0
	if running:
		target_level = lerpf(IDLE_LEVEL, 1.0, plane.throttle) * lerpf(0.55, 1.0, power)
		if _start_age < START_FADE_END:
			_start_age += delta
			target_level *= smoothstep(START_FADE_BEGIN, START_FADE_END, _start_age)
	_engine_level = lerpf(_engine_level, target_level, 1.0 - exp(-2.2 * delta))
	var speed_ratio: float = clampf(plane.speed / maxf(plane.stats.top_speed, 1.0), 0.0, 1.5)
	var pitch: float = lerpf(IDLE_PITCH, 1.0, plane.throttle) * lerpf(SLOW_PITCH, FAST_PITCH, clampf((speed_ratio - 0.3) / 0.9, 0.0, 1.0))
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

	# Wheels on the ground: a rumble that grows with speed.
	var rolling: bool = plane.is_on_ground() and plane.speed > 1.5
	if rolling != _roll.playing:
		if rolling:
			_roll.play(_rng.randf_range(0.0, 2.0))
		else:
			_roll.stop()
	if rolling:
		var roll_ratio: float = clampf(plane.speed / maxf(plane.takeoff_speed(), 1.0), 0.0, 1.2)
		_roll.volume_db = lerpf(-28.0, -3.0, clampf(roll_ratio, 0.0, 1.0))
		_roll.pitch_scale = lerpf(0.7, 1.2, clampf(roll_ratio, 0.0, 1.0))
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
	_roll.stop()
	_starter.stop()
	# Into the sea, or into something harder.
	if plane.global_position.y < 25.0 and plane.airfield_at(plane.global_position) == null:
		_play_event(SOUND_WATER_CRASH, _rng.randf_range(0.92, 1.05), 2.0)
	_play_event(SOUND_EXPLOSION[_rng.randi_range(0, SOUND_EXPLOSION.size() - 1)], _rng.randf_range(0.9, 1.08), 3.0)


func _on_respawned(_plane: PlaneActor) -> void:
	# A new plane is either already flying or parked with a cold engine.
	_engine_was_running = plane.is_engine_running()
	_engine_level = 1.0 if _engine_was_running else 0.0
	_start_age = INF
	_start_engine()


func _on_engine_started(_plane: PlaneActor) -> void:
	_start_age = 0.0
	_engine_level = 0.0
	_starter.pitch_scale = _rng.randf_range(0.96, 1.04)
	_starter.play()


func _on_engine_stopped(_plane: PlaneActor) -> void:
	_stopped_by_pilot = true
	_starter.stop()
	_start_age = INF


func _on_gear_moved(_plane: PlaneActor, going_down: bool) -> void:
	# Coming down is a touch slower and lower than going up.
	_gear.pitch_scale = 0.94 if going_down else 1.04
	_gear.volume_db = 0.0 if cockpit else -5.0
	_gear.play()


func _on_touched_down(_plane: PlaneActor, sink_speed: float, on_wheels: bool) -> void:
	var firmness: float = clampf(sink_speed / PlaneActor.HARD_LANDING_SINK, 0.1, 1.0)
	if on_wheels:
		_play_event(SOUND_TOUCHDOWN[_rng.randi_range(0, SOUND_TOUCHDOWN.size() - 1)], lerpf(1.1, 0.9, firmness), lerpf(-6.0, 4.0, firmness))
	else:
		# No wheels: metal on tarmac.
		_play_event(SOUND_BREAK[_rng.randi_range(0, SOUND_BREAK.size() - 1)], 0.8, 4.0)


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
