class_name PlaneInput
extends Node
## The only thing a pilot (human or AI) is allowed to touch on a plane.
##
## PlaneActor reads this node every physics tick and never asks who is driving.
## That is what makes slots interchangeable: PlayerController and
## SquadAIController both just write here.
##
## Networking: in an online match this node's multiplayer authority is the
## owning peer and the InputSync child replicates `steer`/`firing` to the
## server, which stays authoritative over the plane itself. One-shot buttons go
## through RPCs so a dropped packet can never swallow an engine start or a gear selection.

## The stick. x: -1 hard left .. +1 hard right. In the air that is the
## ailerons (it rolls the plane); on the ground it steers. y: -1 forward (nose
## down) .. +1 right back (nose up): the elevators.
@export var steer: Vector2 = Vector2.ZERO
## The rudder pedals: -1 nose left .. +1 nose right. Left at 0, the plane's
## pilot keeps the turns tidy with his feet by himself; any pedal takes over.
@export_range(-1.0, 1.0) var rudder: float = 0.0
@export var firing: bool = false
## Where the throttle lever is: 0 = closed (and wheel brakes on, when on the
## ground) .. 1 = fully open.
@export_range(0.0, 1.0) var throttle: float = 1.0

## World-space point the pilot's aim assist wants bullets nudged toward.
## Only honoured by PlaneActor inside a small cone around the nose.
var assist_point: Vector3 = Vector3.ZERO
var assist_active: bool = false

var _engine_pending: bool = false
var _gear_pending: bool = false


## Press the engine starter (or the cut-off, if it is running).
func press_engine() -> void:
	if multiplayer.is_server():
		_engine_pending = true
	else:
		_rpc_press_engine.rpc_id(1)


## Move the undercarriage lever: up if it is down, down if it is up.
func press_gear() -> void:
	if multiplayer.is_server():
		_gear_pending = true
	else:
		_rpc_press_gear.rpc_id(1)


## Returns true once per request. Called by PlaneActor on the server.
func consume_engine() -> bool:
	var pending: bool = _engine_pending
	_engine_pending = false
	return pending


func consume_gear() -> bool:
	var pending: bool = _gear_pending
	_gear_pending = false
	return pending


## Neutral stick, trigger released, nothing queued. The throttle lever stays
## where it is: it is a lever, not a spring.
func clear() -> void:
	steer = Vector2.ZERO
	rudder = 0.0
	firing = false
	assist_active = false
	_engine_pending = false
	_gear_pending = false


@rpc("authority", "call_remote", "reliable")
func _rpc_press_engine() -> void:
	_engine_pending = true


@rpc("authority", "call_remote", "reliable")
func _rpc_press_gear() -> void:
	_gear_pending = true
