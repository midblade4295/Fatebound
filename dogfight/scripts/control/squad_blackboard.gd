class_name SquadBlackboard
extends RefCounted
## Shared notes for every bot in a match: who is attacking whom.
## Bots consult it when scoring targets so a team spreads its fire instead of
## five planes chasing the same victim. One instance is owned by the match
## manager and handed to every SquadAIController.

## victim instance id -> number of bots currently attacking it.
var _claims: Dictionary[int, int] = {}


func claim(victim: PlaneActor) -> void:
	if victim == null:
		return
	var key: int = victim.get_instance_id()
	_claims[key] = _claims.get(key, 0) + 1


func release(victim: PlaneActor) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	var key: int = victim.get_instance_id()
	var count: int = _claims.get(key, 0) - 1
	if count <= 0:
		_claims.erase(key)
	else:
		_claims[key] = count


func claim_count(victim: PlaneActor) -> int:
	if victim == null:
		return 0
	return _claims.get(victim.get_instance_id(), 0)


func clear() -> void:
	_claims.clear()
