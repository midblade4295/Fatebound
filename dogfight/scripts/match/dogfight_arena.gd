extends Node3D
## Root of scenes/arena/DogfightArena5v5.tscn. Its only job is wiring: once
## every child is ready it points the chase camera and the HUD at the local
## player's plane. With no local player (bots-only attract mode) it becomes a
## simple spectator that hops between planes.

const SPECTATE_SWITCH_TIME: float = 12.0

var _spectating: bool = false
var _spectate_timer: float = SPECTATE_SWITCH_TIME
var _spectate_index: int = 0

@onready var match_manager: MatchManager5v5 = $MatchManager
@onready var chase_camera: ChaseCamera = $ChaseCamera
@onready var hud: Hud = $HUD
@onready var battle_audio: BattleAudio = $BattleAudio


func _ready() -> void:
	var slot: PilotSlot = match_manager.local_slot()
	var local_plane: PlaneActor = slot.plane if slot != null else null
	_spectating = local_plane == null
	var planes: Array[PlaneActor] = match_manager.get_planes()
	var follow: PlaneActor = local_plane
	if follow == null and not planes.is_empty():
		follow = planes[0]
	chase_camera.set_target(follow)
	hud.bind(match_manager, chase_camera, local_plane)
	battle_audio.bind(match_manager, local_plane)
	if local_plane != null:
		# The player's own engine and guns are heard from the cockpit.
		local_plane.audio.cockpit = true


func _process(delta: float) -> void:
	if not _spectating:
		return
	_spectate_timer -= delta
	var current: PlaneActor = chase_camera.target
	var needs_switch: bool = _spectate_timer <= 0.0 or current == null or not current.alive
	if not needs_switch:
		return
	var planes: Array[PlaneActor] = match_manager.get_planes()
	for _attempt: int in range(planes.size()):
		_spectate_index = (_spectate_index + 1) % planes.size()
		if planes[_spectate_index].alive:
			chase_camera.set_target(planes[_spectate_index])
			_spectate_timer = SPECTATE_SWITCH_TIME
			return
