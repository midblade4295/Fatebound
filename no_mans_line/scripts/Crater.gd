class_name Crater
extends StaticBody2D
## Crater.gd -- shell hole left by a mortar. Soldiers standing in its CoverZone
## take reduced bullet damage (Unit.CRATER_COVER_MULTIPLIER) and Trench Raiders
## lose their open-ground penalty while inside.
##
## Collision setup: StaticBody2D on layer 3 (cover), mask 0.
##                  CoverZone Area2D on layer 0, mask 1 + 2 (unit layers).

var _inside: Array[Unit] = []
var _removing := false


func _ready() -> void:
	# Pop in.
	scale = Vector2(0.4, 0.4)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.15)


func _on_cover_zone_body_entered(body: Node2D) -> void:
	var unit := body as Unit
	if unit != null and not _inside.has(unit):
		_inside.append(unit)
		unit.crater_count += 1


func _on_cover_zone_body_exited(body: Node2D) -> void:
	var unit := body as Unit
	if unit != null and _inside.has(unit):
		_inside.erase(unit)
		unit.crater_count -= 1


## Fades the crater out (called when the crater cap is reached).
func remove() -> void:
	if _removing:
		return
	_removing = true
	# body_exited does not fire for a freed Area2D, so undo the cover by hand.
	for unit in _inside:
		if is_instance_valid(unit):
			unit.crater_count -= 1
	_inside.clear()
	$CoverZone.set_deferred("monitoring", false)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.6)
	tween.tween_callback(queue_free)
