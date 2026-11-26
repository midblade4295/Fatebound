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
var commander_level: int = 1
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
var deaths: int = 0
## Seconds until respawn; 0 while alive.
var respawn_timer: float = 0.0
