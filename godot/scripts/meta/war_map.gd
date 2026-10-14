extends RefCounted
# 0.31.135 (Kevin, Crown War step 2 -- the "Crown War" design doc): the war map both sides share. Three houses, each
# with a home that can never be taken (King's Day, a later step, attacks homes), and fifteen territories between them,
# joined by links: a house attacks only along a link from land it holds (its home counts). The server (server/world.gd)
# keeps who holds what; the phone (scripts/app/war_table.gd) draws it as a 3D war table from these positions.
# Positions are map units (x right, y down); the table lays a hex tile at each, 2.4 units apart.
const HOUSES := ["lions", "stags", "ravens"]
const HOMES := {"lions": "home_lions", "stags": "home_stags", "ravens": "home_ravens"}
const HOUSE_NAMES := {"lions": "Lions", "stags": "Stags", "ravens": "Ravens"}

# id -> {"name", "p": map position, "home": house ("" for a territory), "look": what stands on its tile}
const T := {
	"home_lions":  {"name": "Lions' Keep",  "p": Vector2(0.9, 1.1), "home": "lions",  "look": "castle"},
	"home_stags":  {"name": "Stags' Keep",  "p": Vector2(6.7, 1.1), "home": "stags",  "look": "castle"},
	"home_ravens": {"name": "Ravens' Keep", "p": Vector2(3.8, 4.2), "home": "ravens", "look": "castle"},
	"mill":   {"name": "The Mill",     "p": Vector2(2.1, 1.1),  "home": "", "look": "mill"},
	"tower":  {"name": "Old Tower",    "p": Vector2(3.3, 1.1),  "home": "", "look": "tower"},
	"abbey":  {"name": "The Abbey",    "p": Vector2(4.5, 1.1),  "home": "", "look": "abbey"},
	"pass":   {"name": "High Pass",    "p": Vector2(5.7, 1.1),  "home": "", "look": "pass"},
	"quarry": {"name": "The Quarry",   "p": Vector2(1.5, 2.15), "home": "", "look": "quarry"},
	"ford":   {"name": "The Ford",     "p": Vector2(2.7, 2.15), "home": "", "look": "ford"},
	"lake":   {"name": "Silver Lake",  "p": Vector2(3.85, 2.15), "home": "", "look": "lake"},
	"bridge": {"name": "King's Bridge", "p": Vector2(4.95, 2.15), "home": "", "look": "bridge"},
	"mine":   {"name": "Deep Mine",    "p": Vector2(6.1, 2.15), "home": "", "look": "mine"},
	"marsh":  {"name": "The Marsh",    "p": Vector2(2.0, 3.2),  "home": "", "look": "marsh"},
	"woods":  {"name": "Kingswood",    "p": Vector2(3.2, 3.2),  "home": "", "look": "woods"},
	"forge":  {"name": "The Forge",    "p": Vector2(4.4, 3.2),  "home": "", "look": "forge"},
	"cliffs": {"name": "Grey Cliffs",  "p": Vector2(5.6, 3.2),  "home": "", "look": "cliffs"},
	"fen":    {"name": "Raven Fen",    "p": Vector2(2.6, 4.2),  "home": "", "look": "fen"},
	"port":   {"name": "Saltport",     "p": Vector2(5.0, 4.2),  "home": "", "look": "port"},
}
const LINKS := [
	["home_lions", "mill"], ["home_lions", "quarry"], ["mill", "tower"], ["mill", "ford"], ["quarry", "ford"],
	["quarry", "marsh"], ["tower", "abbey"], ["tower", "lake"], ["ford", "lake"], ["ford", "woods"], ["abbey", "pass"],
	["abbey", "bridge"], ["pass", "home_stags"], ["pass", "mine"], ["home_stags", "mine"], ["lake", "bridge"],
	["lake", "woods"], ["lake", "forge"], ["bridge", "mine"], ["bridge", "forge"], ["mine", "cliffs"], ["marsh", "woods"],
	["woods", "forge"], ["forge", "cliffs"], ["marsh", "fen"], ["woods", "fen"], ["fen", "home_ravens"],
	["home_ravens", "port"], ["forge", "port"], ["cliffs", "port"],
]

# ---- the numbers (the design doc's "Starting numbers"; Kevin approved them)
const ATTEMPTS := 5                 # battles a clan member scores in a day (UTC)
const PTS_CROWN := 50               # each crown a battle earns: a gate broken, the King rescued, the match won
const PTS_LOSS := 100               # a lost battle takes this off
const NEED_OWNED := 1000            # points to take a territory another house holds
const NEED_NEUTRAL := 500           # ... one nobody holds (every Monday's land rush)

static func territories() -> Array:
	# the fifteen that can be taken (not the homes), in a fixed order
	var out := []
	for id in T:
		if str(T[id].home) == "":
			out.append(id)
	return out

static func is_home(id: String) -> bool:
	return T.has(id) and str(T[id].home) != ""

static func neighbours(id: String) -> Array:
	var out := []
	for l in LINKS:
		if l[0] == id:
			out.append(l[1])
		elif l[1] == id:
			out.append(l[0])
	return out

static func linked(a: String, b: String) -> bool:
	for l in LINKS:
		if (l[0] == a and l[1] == b) or (l[0] == b and l[1] == a):
			return true
	return false

static func name_of(id: String) -> String:
	return str(T.get(id, {}).get("name", id))

static func points(crowns: int, won: bool) -> int:
	# what one clan member's battle adds to their clan's bar (a win is always worth something, a loss never helps)
	return crowns * PTS_CROWN - (0 if won else PTS_LOSS)
