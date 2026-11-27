class_name Debris
extends Node3D
## A piece that has been shot off a plane: a wing panel, a rudder, a whole
## tail. It carries on at the plane's speed, slows in the air, tumbles and
## falls, and is removed when it reaches the sea or its time runs out.
## Purely cosmetic: debris does not collide with anything.

const GRAVITY: float = 26.0
const AIR_DRAG: float = 0.7
const LIFETIME: float = 7.0
## Debris below this height has hit the water.
const SEA_LEVEL: float = 0.0

var _velocity: Vector3 = Vector3.ZERO
var _spin_axis: Vector3 = Vector3.RIGHT
var _spin_rate: float = 0.0
var _age: float = 0.0

## Height of the ground under the piece. At sea level it sinks and is gone; on
## anything higher (an airfield) it comes to rest instead.
var floor_height: float = SEA_LEVEL


func _ready() -> void:
	# Moved every rendered frame, so the engine must not interpolate it as well.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Takes over [param piece] (and its children), keeping it exactly where it
## is in the world, and sends it off at [param start_velocity].
func launch(piece: Node3D, start_velocity: Vector3) -> void:
	var where: Transform3D = piece.global_transform
	global_transform = Transform3D(Basis.IDENTITY, where.origin)
	piece.get_parent().remove_child(piece)
	add_child(piece)
	piece.global_transform = where
	_velocity = start_velocity
	_spin_axis = Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 0.4), randf_range(-1.0, 1.0)).normalized()
	_spin_rate = randf_range(2.5, 6.0)


func _process(delta: float) -> void:
	_age += delta
	_velocity += Vector3.DOWN * GRAVITY * delta
	_velocity -= _velocity * AIR_DRAG * delta
	global_position += _velocity * delta
	rotate(_spin_axis, _spin_rate * delta)
	if global_position.y < floor_height and floor_height > SEA_LEVEL:
		# On the airfield: stop falling, skid to a halt and lie there.
		global_position.y = floor_height
		_velocity.y = 0.0
		_velocity -= _velocity * minf(4.0 * delta, 1.0)
		_spin_rate = maxf(_spin_rate - 12.0 * delta, 0.0)
	if _age >= LIFETIME or global_position.y < SEA_LEVEL:
		queue_free()
