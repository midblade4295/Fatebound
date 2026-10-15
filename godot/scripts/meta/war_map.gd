extends RefCounted
# 0.31.135 (Kevin, Crown War step 2 -- the "Crown War" design doc): the war map both sides share. Three houses, each
# with a home (0.31.151: stormed only on King's Day, every Sunday -- below), and fifteen territories between them,
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
const ATTEMPTS := 5                 # (0.31.135-0.31.149: battles a clan member scored in a day. 0.31.150, Kevin: "Remove the
                                    # 5 battle daily" -- no limit; the server still sends it as "att"/"max" for older phones)
const PTS_CROWN := 50               # each crown a battle earns: a gate broken, the King rescued, the match won
const PTS_LOSS := 100               # a lost battle takes this off
const NEED_OWNED := 1000            # points to take a territory another house holds
const NEED_NEUTRAL := 500           # ... one nobody holds (every Monday's land rush)
# 0.31.151 -- King's Day (Kevin: "Do them all"; the design doc's later step): every Sunday (UTC, the week's last day)
# the keeps can be stormed -- by a house holding land linked to one, or by its own house taking it back. A keep takes
# NEED_HOME points; a fallen keep counts HOME_WORTH lands for its captor in the week's count (and no longer counts as
# its own house's land to attack from) until Monday gives every keep back.
const KINGS_DAY := 0                # Time's weekday (0 = Sunday, UTC)
const NEED_HOME := 2000
const HOME_WORTH := 3

static func is_kings_day(t: int) -> bool:
	return int(Time.get_datetime_dict_from_unix_time(t).weekday) == KINGS_DAY

static func kings_day_next(t: int) -> int:
	# when the next King's Day starts (today's start when it's King's Day now)
	var day0 := t - posmod(t, 86400)
	var wd := int(Time.get_datetime_dict_from_unix_time(t).weekday)
	return day0 + posmod(KINGS_DAY - wd, 7) * 86400

static func worth(id: String) -> int:
	# what holding it counts for in the week's count (a fallen keep: HOME_WORTH)
	return HOME_WORTH if is_home(id) else 1

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
