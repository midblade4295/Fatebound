class_name PilotSlot
extends RefCounted
## One of the ten seats in a 5v5 match. A seat always exists and always has a
## plane; what changes is who flies it (a local player, a remote peer or a bot).

## 0-9 across both teams.
var index: int = 0
var team: Teams.Id = Teams.Id.TEAM_BLUE
## 0-4 within the team; also picks the spawn point.
var seat: int = 0
var display_name: String = ""
## What they fly, and how well it is fitted out: 0 (stock) upward. The
## local player's own plane and fittings come from Profile instead.
var plane_data: PlaneData
var grade: int = 0
var is_human: bool = false
## True for the player on this device.
var is_local: bool = false
## Network peer flying this seat. 1 = server / offline / bot.
var peer_id: int = 1
var bot_skill: float = 0.5
var plane: PlaneActor
## PlayerController or SquadAIController. Null for a remote human (their
## input arrives through the plane's InputSync instead).
var controller: Node
var kills: int = 0
## True once this pilot's plane has been lost: there is no second one.
var out: bool = false
