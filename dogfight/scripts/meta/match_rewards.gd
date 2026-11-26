class_name MatchRewards
extends RefCounted
## What one finished match paid out. Returned by Profile.grant_match_rewards().

var coins: int = 0
## Parallel arrays: card id and how many copies of it dropped.
var card_ids: Array[StringName] = []
var card_counts: Array[int] = []
