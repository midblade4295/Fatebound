extends Node
## Headless test of the game's sound wiring. It cannot judge how anything
## sounds; it checks that the right sound is asked to play at the right time.
##
##   godot --headless --fixed-fps 60 --path . res://tests/TestAudio.tscn
##
## Prints AUDIO_OK on success.

var _manager: MatchManager5v5
var _battle_audio: BattleAudio
var _player: PlaneActor
var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0
var _clock: float = -1.0
var _stage: int = 0
## How far from the player each near miss was reported, at the moment it happened.
var _whizzes: Array[float] = []


func _ready() -> void:
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)
	GameSession.local_player_enabled = true
	GameSession.match_seed = 11
	GameSession.bot_skill = 0.0
	GameSession.ground_start = false  # This test is about flying: start in the air.
	_test_catalogue()
	var arena: Node = (load(GameSession.SCENE_ARENA) as PackedScene).instantiate()
	add_child(arena)
	_manager = arena.get_node("MatchManager") as MatchManager5v5
	_battle_audio = arena.get_node("BattleAudio") as BattleAudio
	_player = _manager.local_slot().plane
	for slot: PilotSlot in _manager.get_roster():
		if not slot.is_local:
			slot.controller.set_physics_process(false)  # Quiet skies: bots fly straight and hold fire.
	_manager.bullet_system.bullet_whizzed.connect(func(at: Vector3) -> void: _whizzes.append(at.distance_to(_player.global_position)))


## Every plane type has its own engine recording, and every kind of gun its
## own samples.
func _test_catalogue() -> void:
	var engines: Array[AudioStream] = []
	for data: PlaneData in GameCatalog.PLANES:
		_check(data.engine_sound != null, "%s has an engine sound" % data.display_name)
		if data.engine_sound == null:
			continue
		_check(not engines.has(data.engine_sound), "%s's engine is not another plane's engine" % data.display_name)
		engines.append(data.engine_sound)
		var loop: AudioStreamWAV = SoundTools.looped(data.engine_sound) as AudioStreamWAV
		_check(loop != null and loop.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s's engine plays as a loop" % data.display_name)
		if loop != null:
			_check(loop.get_length() > 4.0 and loop.loop_end == roundi(loop.get_length() * float(loop.mix_rate)),
					"the loop runs the whole %.1f s of the file" % loop.get_length())
	var first_samples: Array[AudioStream] = []
	for gun: ComponentCard in GameCatalog.cards_in_slot(ComponentCard.Slot.GUN):
		_check(gun.gun_sounds.size() >= 3, "%s has several samples to vary between (%d)" % [gun.display_name, gun.gun_sounds.size()])
		if gun.gun_sounds.is_empty():
			continue
		_check(not first_samples.has(gun.gun_sounds[0]), "the %s does not sound like another gun" % gun.display_name)
		first_samples.append(gun.gun_sounds[0])
		for sample: AudioStream in gun.gun_sounds:
			_check(sample.get_length() > 0.15 and sample.get_length() < 0.7, "%s sample is one short shot (%.2f s)" % [gun.display_name, sample.get_length()])


func _physics_process(delta: float) -> void:
	if _stage < 0 or _manager.phase != MatchManager5v5.Phase.ACTIVE:
		return
	if _clock < 0.0:
		_clock = 0.0
	_clock += delta
	var engine_here: AudioStreamPlayer = _player.audio.get_node("EngineCockpit") as AudioStreamPlayer
	var guns_here: AudioStreamPlayer = _player.audio.get_node("GunsCockpit") as AudioStreamPlayer
	match _stage:
		0:
			# Engines: the player's from the cockpit, everyone else's in the world.
			_check(_player.audio.cockpit and engine_here.playing, "the player's engine plays from the cockpit")
			_check(not (_player.audio.get_node("Engine") as AudioStreamPlayer3D).playing, "and not a second time in the world")
			var running: int = 0
			for plane: PlaneActor in _manager.get_planes():
				if plane != _player and (plane.audio.get_node("Engine") as AudioStreamPlayer3D).playing and not plane.audio.cockpit:
					running += 1
			_check(running == 9, "the other nine engines play in 3D (%d)" % running)
			_check((_battle_audio.get_node("Wind") as AudioStreamPlayer).playing, "wind is playing")
			_check(not (_player.audio.get_node("Fire") as AudioStreamPlayer3D).playing, "nothing is on fire yet")
			set_meta(&"cruise_pitch", engine_here.pitch_scale)
			Input.action_press(GameSession.ACTION_FIRE)
			_stage = 1
		1:
			if _clock >= 0.4:
				_check(guns_here.playing, "firing plays the gun sample")
				_check(_player.stats.gun_at(0).gun_sounds.has(guns_here.stream), "and it is one of the fitted gun's own samples")
				Input.action_release(GameSession.ACTION_FIRE)
				_check(_whizzes.is_empty(), "the player's own bullets do not whiz past them")
				_fire_past_player(6.0)
				_fire_past_player(60.0)
				_stage = 2
		2:
			if _clock >= 1.2:
				_check(_whizzes.size() == 1, "a bullet passing 6 m away is heard once, one passing 60 m away is not (%d)" % _whizzes.size())
				if not _whizzes.is_empty():
					_check(_whizzes[0] > 3.0 and _whizzes[0] < 10.0, "and is placed where it went by (%.1f m from the player)" % _whizzes[0])
				var whiz_playing: bool = false
				for child: Node in _battle_audio.get_children():
					var whiz: AudioStreamPlayer3D = child as AudioStreamPlayer3D
					if whiz != null and child.name.begins_with("Whiz") and whiz.stream != null:
						whiz_playing = true
				_check(whiz_playing, "a whiz sample was started")
				# Dive: the engine note should rise with speed.
				Input.action_press(GameSession.ACTION_PITCH_DOWN)
				_stage = 3
		3:
			if _clock >= 3.0:
				Input.action_release(GameSession.ACTION_PITCH_DOWN)
				var cruise_pitch: float = get_meta(&"cruise_pitch")
				_check(engine_here.pitch_scale > cruise_pitch + 0.02, "the engine note rises in a dive (%.2f -> %.2f)" % [cruise_pitch, engine_here.pitch_scale])
				# Kill the engine and set the plane alight.
				_player.apply_damage(1000000.0, null, PlaneActor.Part.ENGINE)
				Input.action_press(GameSession.ACTION_PITCH_UP)
				_stage = 4
		4:
			if _clock >= 5.5:
				Input.action_release(GameSession.ACTION_PITCH_UP)
				_check(engine_here.volume_db < PlaneAudio.COCKPIT_ENGINE_DB - 20.0, "a dead engine falls silent (%.0f dB)" % engine_here.volume_db)
				_check((_player.audio.get_node("Fire") as AudioStreamPlayer3D).playing, "and the fire can be heard")
				var events: AudioStreamPlayer3D = _player.audio.get_node("Events") as AudioStreamPlayer3D
				_check(events.stream == PlaneAudio.SOUND_ENGINE_FAIL, "the engine was heard failing")
				_check((_battle_audio.get_node("Wind") as AudioStreamPlayer).playing, "the wind carries on")
				_finish()


## Fires one enemy bullet from ahead of the player back past them,
## [param miss] metres above.
func _fire_past_player(miss: float) -> void:
	var enemy: PlaneActor = null
	for plane: PlaneActor in _manager.get_planes():
		if plane.team != _player.team:
			enemy = plane
			break
	var ahead: Vector3 = _player.forward()
	var gun: Vector3 = _player.global_position + ahead * 250.0 + Vector3.UP * miss
	# Aim at where the player will be, so the pass really is `miss` metres off.
	var target: Vector3 = Ballistics.lead_point(gun, Vector3.ZERO, _player.global_position + Vector3.UP * miss, _player.velocity, 420.0)
	_manager.bullet_system.spawn(gun, (target - gun).normalized() * 420.0, enemy, 2.0, 1.0, 420.0)


func _finish() -> void:
	_stage = -1
	for action: StringName in [GameSession.ACTION_FIRE, GameSession.ACTION_PITCH_DOWN, GameSession.ACTION_PITCH_UP]:
		Input.action_release(action)
	if _failures.is_empty():
		print("%d checks passed" % _checks)
		print("AUDIO_OK")
	else:
		for failure: String in _failures:
			print("FAIL: " + failure)
		print("AUDIO_FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
