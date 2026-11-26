class_name Teams
extends RefCounted
## Team identifiers and the palette every system (paint, HUD, radar, tracers) reads from.

enum Id { TEAM_BLUE, TEAM_RED }

const COUNT: int = 2

const COLOR_BLUE: Color = Color("2f8cff")
const COLOR_RED: Color = Color("f0433a")
const COLOR_BLUE_DARK: Color = Color("17489c")
const COLOR_RED_DARK: Color = Color("96211c")


static func opponent_of(team: Id) -> Id:
	return Id.TEAM_RED if team == Id.TEAM_BLUE else Id.TEAM_BLUE


static func color_of(team: Id) -> Color:
	return COLOR_BLUE if team == Id.TEAM_BLUE else COLOR_RED


static func dark_color_of(team: Id) -> Color:
	return COLOR_BLUE_DARK if team == Id.TEAM_BLUE else COLOR_RED_DARK


static func name_of(team: Id) -> String:
	return "BLUE" if team == Id.TEAM_BLUE else "RED"


static func are_hostile(a: Id, b: Id) -> bool:
	return a != b
