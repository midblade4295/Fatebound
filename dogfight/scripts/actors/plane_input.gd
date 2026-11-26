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
## through RPCs so a dropped packet can never swallow an evade or a gadget.

## x: -1 turn left .. +1 turn right.  y: -1 nose down .. +1 nose up.
@export var steer: Vector2 = Vector2.ZERO
@export var firing: bool = false

## World-space point the pilot's aim assist wants bullets nudged toward.
## Only honoured by PlaneActor inside a small cone around the nose.
var assist_point: Vector3 = Vector3.ZERO
var assist_active: bool = false

var _evade_pending: bool = false
var _gadget_pending: bool = false


## Request an evade roll. Safe to call every frame the button is held.
func press_evade() -> void:
	if multiplayer.is_server():
		_evade_pending = true
	else:
		_rpc_press_evade.rpc_id(1)


## Request the tactical gadget.
func press_gadget() -> void:
	if multiplayer.is_server():
		_gadget_pending = true
	else:
		_rpc_press_gadget.rpc_id(1)


## Returns true once per request. Called by PlaneActor on the server.
func consume_evade() -> bool:
	var pending: bool = _evade_pending
	_evade_pending = false
	return pending


func consume_gadget() -> bool:
	var pending: bool = _gadget_pending
	_gadget_pending = false
	return pending


## Neutral stick, trigger released, nothing queued.
func clear() -> void:
	steer = Vector2.ZERO
	firing = false
	assist_active = false
	_evade_pending = false
	_gadget_pending = false


@rpc("authority", "call_remote", "reliable")
func _rpc_press_evade() -> void:
	_evade_pending = true


@rpc("authority", "call_remote", "reliable")
func _rpc_press_gadget() -> void:
	_gadget_pending = true
