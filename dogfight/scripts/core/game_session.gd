extends Node
## Autoload "GameSession": carries the match setup from the lobby into the arena
## and owns scene flow (Hangar -> Lobby -> Arena -> Hangar). It also registers
## the keyboard actions used for desktop testing, so no InputMap entries need to
## be maintained by hand in project.godot.

const SCENE_HANGAR: String = "res://scenes/menu/MainMenu.tscn"
const SCENE_LOBBY: String = "res://scenes/lobby/MatchLobby.tscn"
const SCENE_ARENA: String = "res://scenes/arena/DogfightArena5v5.tscn"

# Action names shared by the touch HUD (which presses them through Input) and
# by PlayerController (which only ever reads actions, never widgets).
const ACTION_STEER_LEFT: StringName = &"steer_left"
const ACTION_STEER_RIGHT: StringName = &"steer_right"
const ACTION_PITCH_UP: StringName = &"pitch_up"
const ACTION_PITCH_DOWN: StringName = &"pitch_down"
const ACTION_FIRE: StringName = &"fire"
const ACTION_RUDDER_LEFT: StringName = &"rudder_left"
const ACTION_RUDDER_RIGHT: StringName = &"rudder_right"
const ACTION_THROTTLE_UP: StringName = &"throttle_up"
const ACTION_THROTTLE_DOWN: StringName = &"throttle_down"
const ACTION_ENGINE: StringName = &"toggle_engine"
const ACTION_GEAR: StringName = &"toggle_gear"

## Planes per team. 5v5 by default.
var team_size: int = 5
## The longest a battle with no human in it runs, seconds. A player's
## sortie has no clock: it lasts until they cash out or are killed, and what
## limits it is fuel.
var match_duration: float = 600.0
var local_team: Teams.Id = Teams.Id.TEAM_BLUE
## False runs ten bots with no human (attract mode and headless tests).
var local_player_enabled: bool = true
## 0.0-1.0 average bot skill. Individual bots vary around it.
var bot_skill: float = 0.55
## True: everyone starts parked on their airfield and has to take off.
## False: everyone starts already flying (the old air start).
var ground_start: bool = true
## Seed for bot names/skills. 0 picks a random one per match.
var match_seed: int = 0


func _ready() -> void:
	_register_default_actions()
	_protect_master_bus()


func goto_hangar() -> void:
	get_tree().change_scene_to_file(SCENE_HANGAR)


func goto_lobby() -> void:
	get_tree().change_scene_to_file(SCENE_LOBBY)


func goto_arena() -> void:
	get_tree().change_scene_to_file(SCENE_ARENA)


## Ten engines, forty guns and an explosion can add up to far more than full
## scale. A limiter on the master bus turns that into "loud" instead of
## crackling distortion.
func _protect_master_bus() -> void:
	var master: int = AudioServer.get_bus_index(&"Master")
	if master < 0 or AudioServer.get_bus_effect_count(master) > 0:
		return
	if ClassDB.class_exists(&"AudioEffectHardLimiter"):
		var limiter: AudioEffect = ClassDB.instantiate(&"AudioEffectHardLimiter") as AudioEffect
		limiter.set(&"ceiling_db", -1.0)
		limiter.set(&"pre_gain_db", -3.0)
		AudioServer.add_bus_effect(master, limiter)


func _register_default_actions() -> void:
	_add_key_action(ACTION_STEER_LEFT, [KEY_A, KEY_LEFT])
	_add_key_action(ACTION_STEER_RIGHT, [KEY_D, KEY_RIGHT])
	_add_key_action(ACTION_PITCH_UP, [KEY_W, KEY_UP])
	_add_key_action(ACTION_PITCH_DOWN, [KEY_S, KEY_DOWN])
	_add_key_action(ACTION_FIRE, [KEY_SPACE])
	_add_key_action(ACTION_RUDDER_LEFT, [KEY_Q, KEY_Z])
	_add_key_action(ACTION_RUDDER_RIGHT, [KEY_E, KEY_C])
	_add_key_action(ACTION_THROTTLE_UP, [KEY_R, KEY_PAGEUP])
	_add_key_action(ACTION_THROTTLE_DOWN, [KEY_F, KEY_PAGEDOWN])
	_add_key_action(ACTION_ENGINE, [KEY_I])
	_add_key_action(ACTION_GEAR, [KEY_G])


func _add_key_action(action: StringName, keys: Array[Key]) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for key: Key in keys:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
