extends RefCounted
# 0.31.155 5V5 (the test). Kevin: "What about putting in moba mechanics" -> "5v5" -> "Minions should spawn in a group of
# 1 healer, 2 ranged and 1 knight" -> "Remove the hat system. Minions will stack up if opportunity happens. If minions
# still alive then the new mions that spawn will eventually join them just like in league of legends. Make sure to have
# same tower mechanics as league of legends".
# The rules on top of siege_sim.gd (its hooks call in here; nothing changes unless setup_moba() made one of these):
# - Heroes: five a side (you and four bots; five bots), each keeping its class all match -- no hats, no stands, no
#   villagers. Levels 1-10 from XP (minions dying near you, hero kills, towers); every level a little more health and
#   damage, and a choice of 1 of 3 upgrades. A hero who falls comes back as himself at his castle, later the higher his
#   level; standing in your own castle heals you.
# - Lanes: the three crossings -- the west bridge, the island, the east bridge -- each a track of points from one
#   castle's gate to the other's (the dirt paths). Every 30 s each castle sends a group down each lane: 1 Priest, 2
#   Archers, 1 Knight (WAVE). Minions march, fight what's in front of them and push on; a wave that's still alive when
#   the next comes is simply caught up with -- waves stack.
# - Towers (League's rules): two per lane per side (outer, inner) beside the track. A tower shoots the nearest enemy
#   minion in range; an enemy hero who hurts one of its heroes in range becomes its target at once (call for help);
#   otherwise heroes only when no minion is in range. Shots home in (no dodging); on a hero each shot in a row hits
#   harder (+40 %, up to 3 times), on a minion a share of its health (a Knight 45 %, the others 70 %). A lane's inner
#   tower can't be damaged while its outer one stands; a castle gate can't be damaged while an inner tower of a lane
#   that leads to it stands. Without your minions near it a tower takes a third of the damage (backdoor protection).
#   Only basic attacks (and arrows / fire) hurt towers.
# - The heart is the King (0.31.156, Kevin: "Have the enemy king be the "heart" and players will have to defeat him"):
#   each King sits on his own throne, KING_HP of health, untouchable until one of his castle's front gates is down;
#   then he can be hit (basic attacks, arrows, fire) and he fights back -- a slam round him every KING_EVERY s. Left
#   alone a while he heals. Defeat theirs and the match is won; at time (15 minutes since 0.31.157), the side that did more to the other's
#   King wins, then more towers down, then hero knockouts. No rescues, no lifting. When an enemy gate is down two of
#   each side's bots go for that King; bots near their own King under attack defend him.
# - 0.31.157 (Kevin: "Build the other 3 mechanics now" -- the ultimates, the jungle, the gold shop):
#   * ULTIMATES: at level ULT_LEVEL every hero gets his own (ULTS; the ULT button), stronger from ULT_RANK2. Bots use
#     theirs when it's worth it (_bot_ult).
#   * THE JUNGLE: camps of KayKit skeletons between and beside the lanes (CAMPS_BLUE, mirrored for red; the Bone Lord on
#     the island). They're team 2 -- everyone's enemy -- but stand still until hit; then the camp fights whoever hit it
#     while he's within its LEASH, and walks home and heals once he's gone. Gold and XP for each; the two buff camps
#     give their killer a buff (ARCANE: abilities and the ultimate recharge faster; EMBER: harder hits); the Bone Lord
#     gives his killers' whole side gold, XP and the LORD buff (harder hits; their minions come out stronger). Towers
#     and minions leave them alone. One bot a side is the jungler; the bots gather for the Lord when they're ahead.
#   * GOLD AND THE SHOP: GOLD_START, a trickle every second, last hits on minions, knockouts and assists, towers and
#     camps. Items (ITEMS; ITEM_SLOTS of them) are bought in your own castle or while down -- the big ones are built from
#     the small ones you own (their price is what's left) -- and sold back for SELL_BACK. Bots buy their class's BUILDS.

const HEROES := {
	"knight": {"name":"Knight", "cls":"knight", "up":false}, "barbarian": {"name":"Barbarian", "cls":"barbarian", "up":false},
	"rogue": {"name":"Rogue", "cls":"rogue", "up":false}, "ranger": {"name":"Archer", "cls":"ranger", "up":false},
	"mage": {"name":"Mage", "cls":"mage", "up":false}, "priest": {"name":"Priest", "cls":"priest", "up":false},
	"crusader": {"name":"Crusader", "cls":"knight", "up":true}, "berserker": {"name":"Berserker", "cls":"barbarian", "up":true},
	"assassin": {"name":"Assassin", "cls":"rogue", "up":true}, "sniper": {"name":"Ranger", "cls":"ranger", "up":true},
	"archmage": {"name":"Archmage", "cls":"mage", "up":true}, "necromancer": {"name":"Necromancer", "cls":"priest", "up":true},
}
const HERO_ORDER := ["knight", "barbarian", "rogue", "ranger", "mage", "priest", "crusader", "berserker", "assassin", "sniper",
	"archmage", "necromancer"]
const HERO_LINE := {"knight":"Shield up: blocks everything from the front.", "barbarian":"Spins through a crowd.",
	"rogue":"Lunges in, quick and sharp.", "ranger":"Arrows from range, a volley of five.", "mage":"Fireballs, and a nova all round.",
	"priest":"Heals with a beam; Sanctuary heals everyone near.", "crusader":"Throws his hammer through a line, and blocks.",
	"berserker":"A whirlwind that keeps moving.", "assassin":"Vanishes, then strikes twice as hard.",
	"sniper":"A piercing shot through everyone in a line.", "archmage":"Calls down a meteor.",
	"necromancer":"Drains enemies to heal friends; raises the fallen."}

# the lanes as world points from the blue (team 0) gate to the red (team 1) gate; red walks them backwards. Point
# symmetric: lane 0 backwards and mirrored is lane 2 (the castles are point mirrors).
const LANES := [
	[Vector2(-7, 41), Vector2(-9.5, 39), Vector2(-13.5, 34.5), Vector2(-15.5, 29), Vector2(-15.8, 22), Vector2(-18, 14.5),
		Vector2(-22, 9.5), Vector2(-24, 6.6), Vector2(-24, -4.7), Vector2(-21, -8.5), Vector2(-20, -13.5), Vector2(-19.5, -21),
		Vector2(-19, -28.5), Vector2(-13, -35), Vector2(-5, -38.5), Vector2(-7, -41)],
	[Vector2(7, 41), Vector2(5, 38.5), Vector2(2, 31), Vector2(0.5, 22), Vector2(0, 13.6), Vector2(0, -13.6), Vector2(-0.5, -22),
		Vector2(-2, -31), Vector2(-5, -38.5), Vector2(-7, -41)],
	[Vector2(7, 41), Vector2(5, 38.5), Vector2(13, 35), Vector2(19, 28.5), Vector2(19.5, 21), Vector2(20, 13.5), Vector2(21, 8.5),
		Vector2(24, 4.7), Vector2(24, -6.6), Vector2(22, -9.5), Vector2(18, -14.5), Vector2(15.8, -22), Vector2(15.5, -29),
		Vector2(13.5, -34.5), Vector2(9.5, -39), Vector2(7, -41)],
]
const LANE_NAMES := ["west", "middle", "east"]
# blue's towers [lane, tier (1 outer, 2 inner), position] -- beside the track, on its inner side; red's are the mirror
const TOWERS_BLUE := [[0, 1, Vector2(-15.0, 14.5)], [0, 2, Vector2(-12.5, 28.5)], [1, 1, Vector2(3.3, 19.0)],
	[1, 2, Vector2(5.2, 30.0)], [2, 1, Vector2(17.0, 13.5)], [2, 2, Vector2(16.2, 26.0)]]

const WAVE := ["knight", "ranger", "ranger", "priest"]      # Kevin: 1 healer, 2 ranged, 1 knight (front to back)
const WAVE_FIRST := 15.0
const WAVE_EVERY := 30.0
const MINION_CAP := 40                                      # per side alive (a phone-safety ceiling; waves stack below it)
const MINION_HP := 0.5
const MINION_DMG := 0.45
const MINION_SPD := 0.88
const MINION_GONE := 3.0                                    # a fallen minion's body, then it's gone
const HERO_HP := 1.8                                        # heroes outlast minions
const LEVEL_MAX := 10
const LEVEL_GROW := 0.06                                    # +6 % health and damage a level
const XP_BASE := 60.0
const XP_STEP := 30.0
const MINION_XP := 15.0
const XP_R := 12.0
const HERO_XP := 40.0
const HERO_XP_LVL := 12.0
const TOWER_XP := 50.0
const RESPAWN_BASE := 4.0
const RESPAWN_LVL := 2.6                                    # (1.6 until 0.31.157: a won fight leaves a window to push)
const FOUNTAIN := 0.06                                      # of max health a second, in your own castle
const TOWER_R := 1.5
const TOWER_RANGE := 11.5
const TOWER_HP := [0.0, 900.0, 1150.0]                     # (1000 / 1300 until 0.31.157)
const MINION_SIEGE := 1.5                                   # 0.31.157: minions hit towers and gates this much harder
const TOWER_EVERY := 0.9
const TOWER_FLIGHT := 0.3
const TOWER_HERO_DMG := 40.0
const TOWER_RAMP := 0.4
const TOWER_RAMP_MAX := 3
const TOWER_GROW := 0.04                                    # +4 % a minute
const TOWER_PCT := {"knight":0.45}                          # a share of a minion's health a shot (others 0.7)
const TOWER_PCT_ELSE := 0.7
const BACKDOOR := 0.34
const HELP_FOR := 2.0
const UPGRADES := {
	"dmg":{"name":"+15% DAMAGE"}, "hp":{"name":"+15% HEALTH"}, "spd":{"name":"+8% SPEED"}, "as":{"name":"+12% ATTACK SPEED"},
	"cdr":{"name":"ABILITY +25% FASTER"}, "ls":{"name":"8% LIFESTEAL"}, "regen":{"name":"REGEN 1%/s"},
}
const UP_MAX := 3
const KING_HP := 3000.0                                     # (3500 until 0.31.157)
const KING_R := 1.0
const KING_REACH := 4.5
const KING_SLAM := 50.0
const KING_SLAM_MINION := 0.35                              # 0.31.157: his slam on minions (super minions can chip at him)
const KING_EVERY := 1.6
const KING_REGEN := 0.002                                   # of his health a second, once left alone KING_QUIET s (0.015
const KING_QUIET := 10.0                                    # and 6 s until 0.31.157: a King got back to full between pushes)
const GATE_HP_5V5 := 800.0                                  # 0.31.157: the castle gates in 5v5 (1100 in the siege)
const MATCH_5V5 := 900.0                                    # 0.31.157: 15 minutes (12 until now -- with the jungle, gold and
                                                            # ultimates, bot matches seldom got to a King in 12)
const KING_GUARD := 14.0                                    # enemies this near: he's under attack (bots come to help)

# ---------- 0.31.157: ultimates ----------
const ULT_LEVEL := 6
const ULT_RANK2 := 9                                        # stronger (RANK2_POWER) and quicker back (RANK2_CD)
const RANK2_POWER := 1.35
const RANK2_CD := 0.75
const ULTS := {
	"knight": {"name":"BULWARK", "cd":70.0, "text":"You and every ally near take half damage for 5 s."},
	"barbarian": {"name":"WAR CRY", "short":"WARCRY", "cd":60.0, "text":"6 s of fury: far quicker swings, harder hits, quicker feet."},
	"rogue": {"name":"EXECUTE", "cd":50.0, "text":"Blinks behind the weakest enemy hero near and strikes for triple -- more the more hurt he is."},
	"ranger": {"name":"ARROW RAIN", "short":"RAIN", "cd":60.0, "text":"Arrows pour down on a wide circle for 2.4 s."},
	"mage": {"name":"INFERNO", "cd":60.0, "text":"A huge ring of fire round you: heavy damage, and everyone in it stunned."},
	"priest": {"name":"GRACE", "cd":80.0, "text":"Heals every hero on your side, wherever they are, by a third."},
	"crusader": {"name":"JUDGMENT", "cd":65.0, "text":"Smites the ground: enemies near hurt and stunned, allies near healed."},
	"berserker": {"name":"UNDYING", "cd":75.0, "text":"For 5 s nothing can take you below 1 health, and you hit harder."},
	"assassin": {"name":"FLURRY", "cd":65.0, "text":"Darts from enemy to enemy -- up to four near -- striking each for double."},
	"sniper": {"name":"DEADEYE", "cd":70.0, "text":"A huge arrow across the whole field, through everyone in its way, stunning."},
	"archmage": {"name":"METEORS", "cd":75.0, "text":"Six meteors rain down round your target."},
	"necromancer": {"name":"LEGION", "cd":80.0, "text":"Raises four skeletons who fight for you for 20 s."},
}
const BULWARK_R := 7.0
const BULWARK_DR := 0.5
const BULWARK_TIME := 5.0
const WARCRY_TIME := 6.0
const WARCRY_AS := 0.67                                     # wind-up and recovery x this
const WARCRY_SPD := 1.15
const WARCRY_DMG := 1.25
const EXECUTE_R := 10.0
const EXECUTE_DMG := 3.0
const EXECUTE_MISSING := 0.2                                # + this much of what he's missing
const RAIN_RANGE := 15.0
const RAIN_R := 4.5
const RAIN_TICKS := 8
const RAIN_EVERY := 0.3
const RAIN_DMG := 0.55
const INFERNO_R := 7.0
const INFERNO_DMG := 2.4
const INFERNO_STUN := 1.2
const GRACE_HEAL := 0.35
const JUDGMENT_R := 5.5
const JUDGMENT_DMG := 2.0
const JUDGMENT_STUN := 1.5
const JUDGMENT_HEAL := 0.15
const UNDYING_TIME := 5.0
const UNDYING_DMG := 1.3
const FLURRY_R := 9.0
const FLURRY_N := 4
const FLURRY_DMG := 2.0
const FLURRY_EVERY := 0.22
const DEADEYE_RANGE := 75.0
const DEADEYE_SPEED := 55.0
const DEADEYE_DMG := 3.5
const DEADEYE_STUN := 1.2
const STORM_RANGE := 14.0
const STORM_N := 6
const STORM_SPREAD := 4.0
const STORM_DMG := 1.6
const LEGION_N := 4
const LEGION_TIME := 20.0
const LEGION_HP := 0.9
const LEGION_DMG := 0.6

# ---------- 0.31.157: gold and the shop ----------
const GOLD_START := 500
const GOLD_PASSIVE := 2.0                                   # a second, from the first wave
const GOLD_MINION := {"knight":22, "ranger":15, "priest":15}
const GOLD_HERO := 300
const GOLD_ASSIST := 150                                    # split between the helpers
const ASSIST_WINDOW := 10.0
const GOLD_TOWER := 150
const GOLD_TOWER_TEAM := 75
const SELL_BACK := 0.7
const ITEM_SLOTS := 6
const ARMOR_MAX := 0.5
# stats are fractions: dmg/hp/as/spd/cdr/heal add to the multipliers, ls is lifesteal, regen of health a second,
# armor less damage taken. "from": the smaller items it's built from (owned ones come off the price).
const ITEMS := {
	"sword": {"name":"Long Sword", "cost":350, "dmg":0.12, "icon":"sword"},
	"ruby": {"name":"Ruby Crystal", "cost":400, "hp":0.15, "icon":"ruby"},
	"dagger": {"name":"Dagger", "cost":300, "as":0.12, "icon":"dagger"},
	"boots": {"name":"Boots", "cost":300, "spd":0.10, "boots":true, "icon":"boots"},
	"tome": {"name":"Spell Tome", "cost":400, "cdr":0.20, "icon":"tome"},
	"fang": {"name":"Vampire Fang", "cost":400, "ls":0.07, "icon":"fang"},
	"bead": {"name":"Healing Bead", "cost":250, "regen":0.006, "icon":"bead"},
	"cloth": {"name":"Cloth Armor", "cost":300, "armor":0.10, "icon":"shield"},
	"greaves": {"name":"Swift Greaves", "cost":900, "from":["boots"], "spd":0.20, "boots":true, "icon":"boots"},
	"bloodthirster": {"name":"Bloodthirster", "cost":1900, "from":["sword", "fang"], "dmg":0.35, "ls":0.12, "icon":"sword"},
	"titan": {"name":"Titan's Belt", "cost":1700, "from":["ruby", "bead"], "hp":0.40, "regen":0.012, "icon":"ruby"},
	"phantom": {"name":"Phantom Blade", "cost":1700, "from":["dagger", "dagger"], "as":0.35, "spd":0.06, "icon":"dagger"},
	"archon": {"name":"Archon Staff", "cost":1800, "from":["tome", "sword"], "dmg":0.30, "cdr":0.30, "icon":"tome"},
	"thorn": {"name":"Thornplate", "cost":1600, "from":["cloth", "ruby"], "armor":0.25, "hp":0.15, "icon":"shield"},
	"relic": {"name":"Holy Relic", "cost":1500, "from":["tome", "bead"], "heal":0.40, "hp":0.15, "cdr":0.15, "icon":"bead"},
}
const ITEM_ORDER := ["sword", "ruby", "dagger", "boots", "tome", "fang", "bead", "cloth",
	"bloodthirster", "titan", "phantom", "archon", "thorn", "greaves", "relic"]
const BUILDS := {
	"knight": ["boots", "ruby", "cloth", "thorn", "greaves", "sword", "fang", "bloodthirster", "bead", "titan"],
	"barbarian": ["sword", "boots", "fang", "bloodthirster", "greaves", "ruby", "cloth", "thorn", "bead", "titan"],
	"rogue": ["sword", "boots", "fang", "bloodthirster", "dagger", "dagger", "phantom", "greaves", "ruby", "cloth", "thorn"],
	"ranger": ["dagger", "boots", "dagger", "phantom", "sword", "fang", "bloodthirster", "greaves", "ruby", "bead", "titan"],
	"mage": ["tome", "boots", "sword", "archon", "greaves", "ruby", "bead", "titan", "cloth"],
	"priest": ["tome", "boots", "bead", "relic", "greaves", "ruby", "cloth", "thorn"],
}

# ---------- 0.31.157: the jungle ----------
const JUNGLE := -2                                          # a hero's "lane": the jungler
const CAMP_FIRST := 30.0
const LORD_FIRST := 300.0                                   # the Bone Lord rises at 5:00
# blue's camps (red's are the point mirror): the Bone Pack between the west lane and the middle, the Grave Archers
# between the middle and the east lane; the two buff camps out in the open fields beyond the side lanes, on blue's
# half (each spot the most open one round there -- tools: rocks and trees in the way stopped bots' arrows)
const CAMPS_BLUE := [
	{"kind":"pack", "p":Vector2(-8.5, 16.0)},
	{"kind":"archers", "p":Vector2(8.5, 24.0)},
	{"kind":"arcane", "p":Vector2(-28.0, 35.0)},
	{"kind":"ember", "p":Vector2(28.5, 29.0)},
]
const BOSS_P := Vector2(-7.5, -0.5)                         # the island's west end, beside the old tower
const CAMP_KINDS := {
	"pack": {"name":"Bone Pack", "mobs":[["warrior", Vector2(0, 0)], ["minion", Vector2(-1.7, 1.2)], ["minion", Vector2(1.7, 1.2)]], "respawn":75.0},
	"archers": {"name":"Grave Archers", "mobs":[["archer", Vector2(-1.3, 0)], ["archer", Vector2(1.3, 0)], ["minion", Vector2(0, 1.5)]], "respawn":75.0},
	"arcane": {"name":"Arcane Wraith", "mobs":[["wraith", Vector2(0, 0)], ["minion", Vector2(-1.8, 1.4)], ["minion", Vector2(1.8, 1.4)]], "respawn":120.0, "buff":"arcane"},
	"ember": {"name":"Ember Brute", "mobs":[["brute", Vector2(0, 0)], ["minion", Vector2(-1.8, 1.4)], ["minion", Vector2(1.8, 1.4)]], "respawn":120.0, "buff":"ember"},
	"lord": {"name":"Bone Lord", "mobs":[["lord", Vector2(0, 0)]], "respawn":180.0},
}
const MONSTERS := {
	"minion": {"name":"Skeleton", "look":"skel_minion", "cls":"rogue", "hp":2.0, "dmg":0.6, "spd":0.85, "gold":20, "xp":18},
	"warrior": {"name":"Skeleton Warrior", "look":"skel_warrior", "cls":"barbarian", "hp":3.6, "dmg":0.6, "spd":0.8, "gold":45, "xp":40},
	"archer": {"name":"Skeleton Archer", "look":"skel_rogue", "cls":"ranger", "hp":2.4, "dmg":0.7, "spd":0.8, "gold":28, "xp":25},
	"wraith": {"name":"Arcane Wraith", "look":"skel_mage", "cls":"mage", "hp":7.0, "dmg":0.8, "spd":0.8, "gold":90, "xp":70, "scale":1.3},
	"brute": {"name":"Ember Brute", "look":"skel_brute", "cls":"barbarian", "hp":6.5, "dmg":0.85, "spd":0.8, "gold":90, "xp":70, "scale":1.35},
	"lord": {"name":"Bone Lord", "look":"skel_lord", "cls":"barbarian", "hp":26.0, "dmg":1.9, "spd":0.75, "gold":300, "xp":120, "scale":1.9},
}
const MON_GROW := 0.05                                      # a monster comes back 5 % stronger for every minute played
const LEASH := 9.0
const LORD_LEASH := 8.0
const RESET_HEAL := 0.3                                     # of its health a second, once left alone
const LORD_SLAM_EVERY := 5.0
const LORD_SLAM_R := 4.5
const LORD_SLAM_DMG := 1.4
const BUFF_TIME := 90.0
const BUFF_PASS_MIN := 30.0                                 # a buff taken off a fallen hero: at least this long
const ARCANE_CDR := 1.3
const EMBER_DMG := 1.2
const LORD_TIME := 120.0
const LORD_DMG := 1.15
const LORD_MINION := 1.4
const SUPER_MINION := 1.5                                   # a lane whose enemy gate is down: its minions x this
const BUFF_NAMES := {"arcane":"ARCANE", "ember":"EMBER", "lord":"LORD'S BLESSING"}

var s                                     # the sim
var rng := RandomNumberGenerator.new()
var towers: Array = []                    # {id, team, lane, tier, p, hp, max_hp, dead, target, ramp, ramp_id, next}
var shots: Array = []                     # {tw, target, t, dmg}
var wave_at := WAVE_FIRST
var waves := 0
var _mid := 0
var heroes: Array = [[], []]              # unit ids
var hero_of := {}                         # unit id -> hero id
var _immune_note := -10.0
var kings: Array = [{}, {}]               # per side: {hp, max_hp, dead, next, quiet}
var camps: Array = []                     # 0.31.157: {id, kind, side (0/1, -1 the Lord), p, mobs, alive, next, target, hits}
var rains: Array = []                     # ARROW RAIN in progress: {team, owner, at, r, left, next, dmg}
var boss_go := [false, false]             # a side's bots are going for the Bone Lord
var _boss_check := 0.0
var _jid := 0
var _zid := 0
var _shop_clock := 0.0

# ---------- setup ----------
func begin(sim, my_hero: String, seed_value: int) -> void:
	s = sim
	rng.seed = seed_value
	s.match_time = MATCH_5V5
	for st in s.stands:
		st.stock = 0                      # (the shops stay as buildings; nothing to take)
	s.hats = []
	s.bomb_next = [INF, INF]
	for b in TOWERS_BLUE:
		_add_tower(0, int(b[0]), int(b[1]), b[2])
	for b in TOWERS_BLUE:
		_add_tower(1, 2 - int(b[0]), int(b[1]), -(b[2] as Vector2))
	for g in s.gates:                     # 0.31.157: the gates (League's inhibitors) a little easier to break
		if str(g.get("kind", "")) != "jail":
			g.hp = GATE_HP_5V5
			g.max_hp = GATE_HP_5V5
	for t in 2:                           # the Kings, home on their thrones: the hearts
		var o: Dictionary = s.oracles[t]
		o.state = "home"
		o.pos = s.throne(t)
		o.lifters = []
		o.carrier = ""
		kings[t] = {"hp":KING_HP, "max_hp":KING_HP, "dead":false, "next":0.0, "quiet":0.0}
		s.obstacles.append({"p":o.pos, "r":KING_R, "kind":"moba_king", "kg":t, "team":t})
	s._build_buckets()
	s._build_nav()                        # (the towers block the way and stop arrows)
	for t in 2:                           # the island lane at its plain cost: minions walk mid
		var grid: AStarGrid2D = s.nav[t]
		for ix in range(grid.region.position.x, grid.region.end.x):
			for iz in range(grid.region.position.y, grid.region.end.y):
				var cc := Vector2i(ix, iz)
				if s._lane_cell(s.nav_point(cc)) and s.water_depth(s.nav_point(cc)) <= 0.15:
					grid.set_point_weight_scale(cc, 1.0)
	# the heroes: yours, then the bots' (no two the same on a side)
	var pool: Array = HERO_ORDER.duplicate()
	var lanes := [[-1, 0, 1, 2, JUNGLE], [0, 1, 2, JUNGLE, 1]]       # 0.31.157: one jungler a side
	for t in 2:
		var taken := []
		if t == 0:
			taken.append(my_hero if HEROES.has(my_hero) else "knight")
		var i := 0
		for u in s.units:
			if int(u.team) != t:
				continue
			var hid := ""
			if t == 0 and i == 0:
				hid = str(taken[0])
			else:
				var left := pool.filter(func(h): return not taken.has(h))
				hid = str(left[rng.randi_range(0, left.size() - 1)])
				taken.append(hid)
			_make_hero(u, hid, int(lanes[t][mini(i, 4)]), (i in [1, 2]) if t == 0 else (i in [0, 1]))
			i += 1
	# the jungle (0.31.157): each side's four camps (red's the point mirror of blue's), the Bone Lord on the island
	for t in 2:
		for c in CAMPS_BLUE:
			_add_camp(str(c.kind), t, c.p if t == 0 else -(c.p as Vector2))
	_add_camp("lord", -1, BOSS_P)

func _add_tower(team: int, lane: int, tier: int, p: Vector2) -> void:
	var id := towers.size()
	towers.append({"id":id, "team":team, "lane":lane, "tier":tier, "p":p, "hp":TOWER_HP[tier], "max_hp":TOWER_HP[tier],
		"dead":false, "target":"", "ramp":0, "ramp_id":"", "next":0.0})
	s.obstacles.append({"p":p, "r":TOWER_R, "kind":"moba_tower", "tw":id, "team":team})

func _make_hero(u: Dictionary, hid: String, lane: int, king_runner: bool) -> void:
	var h: Dictionary = HEROES[hid]
	u.cls = str(h.cls)
	u.up = bool(h.up)
	u["hero"] = true
	u["hid"] = hid
	u["lane"] = lane
	u["kr"] = king_runner and u.bot
	u["level"] = 1
	u["xp"] = 0.0
	u["picks"] = []
	u["ups"] = {}
	u["ult_cd"] = 0.0
	u["gold"] = float(GOLD_START)
	u["gold_total"] = 0.0
	u["items"] = []
	u["bought"] = []
	u["buffs"] = {}
	u.role = "escort"
	heroes[int(u.team)].append(u.id)
	hero_of[u.id] = hid
	_apply(u)
	s._respawn(u, true)

# ---------- stats ----------
func stat(u: Dictionary, key: String, base: Variant) -> Variant:
	match key:
		"hp":
			return float(base) * (1.15 if u.up else 1.0) * float(u.get("m_hp", 1.0))
		"dmg":
			return float(base) * (1.1 if u.up else 1.0) * float(u.get("m_dmg", 1.0))
		"speed":
			return float(base) * float(u.get("m_spd", 1.0)) * (WARCRY_SPD if s.time < float(u.get("bl_until", -1.0)) else 1.0)
		"windup", "recover":
			return float(base) * float(u.get("m_as", 1.0)) * (WARCRY_AS if s.time < float(u.get("bl_until", -1.0)) else 1.0)
	return base

func _apply(u: Dictionary) -> void:
	# the multipliers stat() reads, from the level and the upgrades picked
	var ups: Dictionary = u.get("ups", {})
	var lv := float(int(u.get("level", 1)) - 1)
	var before: float = float(u.get("max_hp", 0.0))
	var it := item_stats(u)                   # 0.31.157: what the items add
	u["m_hp"] = HERO_HP * (1.0 + LEVEL_GROW * lv) * (1.0 + 0.15 * float(ups.get("hp", 0))) * (1.0 + float(it.get("hp", 0.0)))
	u["m_dmg"] = (1.0 + LEVEL_GROW * lv) * (1.0 + 0.15 * float(ups.get("dmg", 0))) * (1.0 + float(it.get("dmg", 0.0)))
	u["m_spd"] = 1.0 + 0.08 * float(ups.get("spd", 0)) + float(it.get("spd", 0.0))
	u["m_as"] = pow(0.88, float(ups.get("as", 0))) / (1.0 + float(it.get("as", 0.0)))
	u["m_cdr"] = 1.0 + 0.25 * float(ups.get("cdr", 0)) + float(it.get("cdr", 0.0))
	u["m_ls"] = 0.08 * float(ups.get("ls", 0)) + float(it.get("ls", 0.0))
	u["m_regen"] = 0.01 * float(ups.get("regen", 0)) + float(it.get("regen", 0.0))
	u["m_armor"] = minf(ARMOR_MAX, float(it.get("armor", 0.0)))
	u["m_heal"] = 1.0 + float(it.get("heal", 0.0))
	var after := float(s.stat(u, "hp"))
	u.max_hp = after
	if before > 0.0 and s.alive(u):
		u.hp = minf(after, float(u.hp) + maxf(0.0, after - before))      # the health a level brings comes with it
	elif float(u.get("hp", 0.0)) > after:
		u.hp = after                                                      # (an item sold while down)

func need(level: int) -> float:
	return XP_BASE + XP_STEP * float(level - 1)

func add_xp(u: Dictionary, x: float) -> void:
	if not bool(u.get("hero", false)) or int(u.level) >= LEVEL_MAX:
		return
	u.xp = float(u.xp) + x
	while int(u.level) < LEVEL_MAX and float(u.xp) >= need(int(u.level)):
		u.xp = float(u.xp) - need(int(u.level))
		u.level = int(u.level) + 1
		(u.picks as Array).append(_offer(u))
		_apply(u)
		s._event("level", {"id":u.id, "team":u.team, "level":int(u.level)})
		if int(u.level) == ULT_LEVEL or int(u.level) == ULT_RANK2:
			s._event("ult_ready", {"id":u.id, "team":u.team, "rank":ult_rank(u)})     # 0.31.157: unlocked / stronger
		if u.bot:
			pick(u, rng.randi_range(0, 2))
	if int(u.level) >= LEVEL_MAX:
		u.xp = 0.0

func _offer(u: Dictionary) -> Array:
	var pool := []
	for k in UPGRADES:
		if int((u.ups as Dictionary).get(k, 0)) >= UP_MAX:
			continue
		if u.cls == "priest" and k in ["dmg", "ls"]:
			continue                                  # (a healer's beam does no damage)
		pool.append(k)
	var out := []
	while out.size() < 3 and not pool.is_empty():
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out

func pick(u: Dictionary, i: int) -> bool:
	var picks: Array = u.get("picks", [])
	if picks.is_empty():
		return false
	var offer: Array = picks[0]
	if i < 0 or i >= offer.size():
		return false
	var k := str(offer[i])
	u.ups[k] = int((u.ups as Dictionary).get(k, 0)) + 1
	picks.pop_front()
	_apply(u)
	s._event("pick", {"id":u.id, "up":k})
	return true

# ---------- the match ----------
func step(dt: float) -> void:
	if s.time >= wave_at:
		wave_at += WAVE_EVERY
		waves += 1
		for t in 2:
			for l in 3:
				_spawn_wave(t, l)
	_step_towers(dt)
	_step_kings(dt)
	_step_camps(dt)
	_step_rains(dt)
	var gold_on: bool = s.time >= WAVE_FIRST
	var gone := []
	for u in s.units:
		if not s.alive(u):
			if (bool(u.get("minion", false)) or u.has("mon")) and s.time >= float(u.get("gone_at", INF)):
				gone.append(u)
			if bool(u.get("hero", false)) and gold_on:
				u.gold = float(u.gold) + GOLD_PASSIVE * dt
			continue
		if bool(u.get("hero", false)):
			var heal := float(u.get("m_regen", 0.0))
			if s.in_castle(u.pos, int(u.team)):
				heal += FOUNTAIN
			if heal > 0.0 and u.hp < u.max_hp:
				u.hp = minf(u.max_hp, u.hp + u.max_hp * heal * dt)
			# 0.31.157: the ultimate's recharge (abilities' speed counts; ARCANE adds to both), gold trickling in
			var arcane: bool = s.time < float((u.buffs as Dictionary).get("arcane", -1.0))
			u.ult_cd = maxf(0.0, float(u.ult_cd) - dt * float(u.get("m_cdr", 1.0)) * (ARCANE_CDR if arcane else 1.0))
			if arcane and float(u.cd_ability) > 0.0:
				u.cd_ability = maxf(0.0, float(u.cd_ability) - dt * float(u.get("m_cdr", 1.0)) * (ARCANE_CDR - 1.0))
			if gold_on:
				u.gold = float(u.gold) + GOLD_PASSIVE * dt
			if u.has("dance"):
				_step_dance(u)
		elif bool(u.get("summon", false)) and s.time >= float(u.get("expire", INF)):
			s._kill({}, u)                                        # the Necromancer's skeletons crumble
	for u in gone:
		s.units.erase(u)
		s.by_id.erase(u.id)
	# the bots shop when they're home or down; the Lord: a side's bots go when they're ahead
	_shop_clock += dt
	if _shop_clock >= 1.0:
		_shop_clock = 0.0
		for t in 2:
			for hid in heroes[t]:
				var h: Dictionary = s.by_id.get(hid, {})
				if not h.is_empty() and bool(h.bot) and can_shop(h):
					_bot_shop(h)
	_boss_check += dt
	if _boss_check >= 2.0:
		_boss_check = 0.0
		_boss_call()

func _spawn_wave(t: int, l: int) -> void:
	var alive := 0
	for u in s.units:
		if bool(u.get("minion", false)) and not bool(u.get("summon", false)) and int(u.team) == t and s.alive(u):
			alive += 1
	var lord := lord_buff(t)                   # 0.31.157: the Bone Lord's blessing on this side -- stronger minions
	var sup := _lane_gate_down(t, l)           # 0.31.157: League's inhibitor -- their gate at this lane's end down: super minions
	var start := wp(t, l, 0)
	var ahead := (wp(t, l, 1) - start).normalized()
	var side := Vector2(-ahead.y, ahead.x)
	var ids := []
	for k in WAVE.size():
		if alive >= MINION_CAP:
			break
		alive += 1
		_mid += 1
		var id := "m%d" % _mid
		var u: Dictionary = s._new_unit(id, t, true, "raid")
		u.cls = str(WAVE[k])
		u["minion"] = true
		u["lane"] = l
		u["wp"] = 1
		u["m_hp"] = MINION_HP * (LORD_MINION if lord else 1.0) * (SUPER_MINION if sup else 1.0)
		u["m_dmg"] = MINION_DMG * (LORD_MINION if lord else 1.0) * (SUPER_MINION if sup else 1.0)
		if sup:
			u["super"] = true
		u["m_spd"] = MINION_SPD
		if lord:
			u["lordly"] = true
		u.max_hp = float(s.stat(u, "hp"))
		u.hp = u.max_hp
		# (front to back from the gate out: the Knight ahead, the Priest at the gate -- behind it is the castle wall)
		u.pos = start + ahead * (1.4 * float(WAVE.size() - 1 - k)) + side * (0.9 if k == 1 else (-0.9 if k == 2 else 0.0))
		u.face = s.angle_of(ahead)
		u.think_at = s.time + s.TICK * float(k + 1)
		s.units.append(u)
		s.by_id[id] = u
		ids.append(id)
	if not ids.is_empty():
		s._event("wave", {"team":t, "lane":l, "ids":ids})

func _lane_gate_down(t: int, l: int) -> bool:
	# the enemy castle's gate at the end of team t's lane l is down
	var g := _gate_at(1 - t, wp(t, l, lane_len(l) - 1))
	return not g.is_empty() and not s.gate_blocks(g)

func wp(t: int, l: int, i: int) -> Vector2:
	# point i of lane l walked by team t (red walks it backwards)
	var pts: Array = LANES[l]
	i = clampi(i, 0, pts.size() - 1)
	return pts[i] if t == 0 else pts[pts.size() - 1 - i]

func lane_len(l: int) -> int:
	return (LANES[l] as Array).size()

# ---------- towers ----------
func vulnerable(tw: Dictionary) -> bool:
	if bool(tw.dead):
		return false
	if int(tw.tier) == 1:
		return true
	for o in towers:
		if int(o.team) == int(tw.team) and int(o.lane) == int(tw.lane) and int(o.tier) == int(tw.tier) - 1 and not bool(o.dead):
			return false
	return true

func towers_down(team: int) -> int:
	var n := 0
	for tw in towers:
		if int(tw.team) == team and bool(tw.dead):
			n += 1
	return n

func gate_open(g: Dictionary) -> bool:
	# a castle gate can be hit once an inner tower of a lane that ends at it is down (the jail: once a front gate is)
	if str(g.get("kind", "")) == "jail":
		for o in s.gates:
			if int(o.team) == int(g.team) and str(o.get("kind", "")) != "jail" and not s.gate_blocks(o):
				return true
		return false
	for l in 3:
		var end := wp(1 - int(g.team), l, lane_len(l) - 1)        # where the attackers' track ends: at this castle
		if end.distance_to(g.c) > 6.0:
			continue
		for tw in towers:
			if int(tw.team) == int(g.team) and int(tw.lane) == l and int(tw.tier) == 2 and bool(tw.dead):
				return true
	return false

func _step_towers(dt: float) -> void:
	for tw in towers:
		if bool(tw.dead):
			continue
		var cur: Dictionary = s.by_id.get(str(tw.target), {})
		if cur.is_empty() or not s.alive(cur) or (cur.pos as Vector2).distance_to(tw.p) > TOWER_RANGE + s.UNIT_R:
			cur = {}
		# call for help: an enemy hero in range who hurt one of our heroes in range just now
		var help := {}
		for h in s.units:
			if not bool(h.get("hero", false)) or int(h.team) != int(tw.team) or not s.alive(h):
				continue
			if s.time - float(h.get("hh_at", -99.0)) > HELP_FOR or (h.pos as Vector2).distance_to(tw.p) > TOWER_RANGE:
				continue
			var a: Dictionary = s.by_id.get(str(h.get("hh_by", "")), {})
			if not a.is_empty() and s.alive(a) and (a.pos as Vector2).distance_to(tw.p) <= TOWER_RANGE + s.UNIT_R:
				help = a
				break
		if not help.is_empty() and (cur.is_empty() or not bool(cur.get("hero", false))):
			cur = help
		if cur.is_empty():
			var best := {}
			var bd := INF
			for heroes_pass in [false, true]:                    # minions first; heroes only when there are none
				for o in s.units:
					if int(o.team) == int(tw.team) or int(o.team) > 1 or not s.alive(o) or bool(o.get("hero", false)) != heroes_pass:
						continue
					var d: float = (o.pos as Vector2).distance_to(tw.p)
					if d <= TOWER_RANGE + s.UNIT_R and d < bd:
						bd = d
						best = o
				if not best.is_empty():
					break
			cur = best
		tw.target = str(cur.get("id", ""))
		if cur.is_empty() or s.time < float(tw.next):
			continue
		tw.next = s.time + TOWER_EVERY
		var dmg := 0.0
		if bool(cur.get("hero", false)):
			if str(tw.ramp_id) == str(cur.id):
				tw.ramp = mini(int(tw.ramp) + 1, TOWER_RAMP_MAX)
			else:
				tw.ramp_id = str(cur.id)
				tw.ramp = 0
			dmg = TOWER_HERO_DMG * (1.0 + TOWER_RAMP * float(tw.ramp)) * (1.0 + TOWER_GROW * s.time / 60.0)
		else:
			tw.ramp_id = ""
			tw.ramp = 0
			dmg = float(cur.max_hp) * float(TOWER_PCT.get(str(cur.cls), TOWER_PCT_ELSE))
		shots.append({"tw":int(tw.id), "target":str(cur.id), "t":TOWER_FLIGHT, "dmg":dmg})
		s._event("tshot", {"tw":int(tw.id), "id":str(cur.id), "flight":TOWER_FLIGHT, "ramp":int(tw.ramp)})
	for i in range(shots.size() - 1, -1, -1):
		var sh: Dictionary = shots[i]
		sh.t = float(sh.t) - dt
		if float(sh.t) > 0.0:
			continue
		shots.remove_at(i)
		var tw2: Dictionary = towers[int(sh.tw)]
		var u: Dictionary = s.by_id.get(str(sh.target), {})
		if not u.is_empty() and s.alive(u):
			s._next_push = Vector3.ZERO
			s._damage({"id":"tower%d" % int(tw2.id), "team":int(tw2.team), "pos":tw2.p, "state":"idle"}, u, float(sh.dmg))

func hit_tower(src: Dictionary, id: int, amount: float) -> void:
	if id < 0 or id >= towers.size():
		return
	var tw: Dictionary = towers[id]
	if bool(tw.dead) or int(src.get("team", -1)) == int(tw.team) or int(src.get("team", -1)) < 0 or int(src.get("team", -1)) > 1:
		return
	if not vulnerable(tw):
		if s.time - _immune_note > 1.5 and not bool(src.get("bot", true)):
			_immune_note = s.time
			s._event("tower_immune", {"tw":id, "team":int(tw.team)})
		return
	var minions_near := false
	for o in s.units:
		if bool(o.get("minion", false)) and int(o.team) == int(src.team) and s.alive(o) and (o.pos as Vector2).distance_to(tw.p) <= TOWER_RANGE:
			minions_near = true
			break
	if not minions_near:
		amount *= BACKDOOR                      # no minions with you: the tower barely feels it
	if lane_minion(str(src.get("id", ""))):
		amount *= MINION_SIEGE
	tw.hp = maxf(0.0, float(tw.hp) - amount)
	s._event("tower_hit", {"tw":id, "dmg":int(round(amount))})
	if float(tw.hp) <= 0.0:
		tw.dead = true
		tw.target = ""
		s._event("tower_down", {"tw":id, "team":int(tw.team), "lane":int(tw.lane), "tier":int(tw.tier), "by":str(src.get("id", ""))})
		for hid in heroes[1 - int(tw.team)]:
			add_xp(s.by_id.get(hid, {}), TOWER_XP)
			add_gold(s.by_id.get(hid, {}), GOLD_TOWER_TEAM, Vector2.INF)        # 0.31.157: everyone on the side
		var by_h := _credit(src)
		if not by_h.is_empty():
			add_gold(by_h, GOLD_TOWER, tw.p)                                     # and the one who brought it down
		s._update_gate_nav()

func melee_towers(u: Dictionary, reach: float, arc: float, dmg: float) -> int:
	if int(u.team) > 1:
		return 0                                 # (0.31.157: the jungle's monsters leave towers and Kings alone)
	var fwd: Vector2 = s.dir_of(u.face)
	var hits := 0
	for tw in towers:
		if bool(tw.dead) or int(tw.team) == int(u.team):
			continue
		var off: Vector2 = (tw.p as Vector2) - (u.pos as Vector2)
		var d := off.length()
		if d - TOWER_R > reach + 0.3:
			continue
		if arc > -1.0 and d > 0.3 and fwd.dot(off / d) < arc - 0.3:
			continue
		hit_tower(u, int(tw.id), dmg)
		hits += 1
	var t2 := 1 - int(u.team)
	var off2: Vector2 = king_pos(t2) - (u.pos as Vector2)
	var d2 := off2.length()
	if not bool(kings[t2].dead) and d2 - KING_R <= reach + 0.3 and (arc <= -1.0 or d2 < 0.3 or fwd.dot(off2 / d2) >= arc - 0.3):
		hit_king(u, t2, dmg)
		hits += 1
	return hits

func tower_in_range(team_of_tower: int, p: Vector2, extra := 0.0) -> Dictionary:
	for tw in towers:
		if int(tw.team) == team_of_tower and not bool(tw.dead) and p.distance_to(tw.p) <= TOWER_RANGE + extra:
			return tw
	return {}

# ---------- the Kings, the hearts (0.31.156) ----------
func king_pos(t: int) -> Vector2:
	return s.oracles[t].pos

func king_open(t: int) -> bool:
	# hittable once a front gate of his castle is down
	if bool(kings[t].dead):
		return false
	for g in s.gates:
		if int(g.team) == t and str(g.get("kind", "")) != "jail" and not s.gate_blocks(g):
			return true
	return false

func king_frac(t: int) -> float:
	return float(kings[t].hp) / float(kings[t].max_hp)

func tiebreak() -> int:
	# at time: who did more to the other's King, then towers, then hero knockouts (-1: level)
	if absf(king_frac(0) - king_frac(1)) > 0.001:
		return 0 if king_frac(1) < king_frac(0) else 1
	if towers_down(0) != towers_down(1):
		return 0 if towers_down(1) > towers_down(0) else 1
	if s.kills[0] != s.kills[1]:
		return 0 if s.kills[0] > s.kills[1] else 1
	return -1

func king_threat(t: int) -> Dictionary:
	# the nearest enemy within KING_GUARD of King t ({} when none)
	var best := {}
	var bd := KING_GUARD
	for o in s.units:
		if int(o.team) != t and int(o.team) <= 1 and s.alive(o):
			var d: float = (o.pos as Vector2).distance_to(king_pos(t))
			if d < bd:
				bd = d
				best = o
	return best

func hit_king(src: Dictionary, t: int, amount: float) -> void:
	var k: Dictionary = kings[t]
	if bool(k.dead) or int(src.get("team", -1)) == t or int(src.get("team", -1)) < 0 or int(src.get("team", -1)) > 1 or s.ended:
		return
	if not king_open(t):
		if s.time - _immune_note > 1.5 and not bool(src.get("bot", true)):
			_immune_note = s.time
			s._event("king_immune", {"team":t})
		return
	k.hp = maxf(0.0, float(k.hp) - amount)
	k.quiet = 0.0
	s._event("king_hit", {"team":t, "dmg":int(round(amount))})
	if float(k.hp) <= 0.0:
		k.dead = true
		s.score[1 - t] += 1
		s._event("king_down", {"team":t, "by":str(src.get("id", ""))})
		s._finish("king")

func _step_kings(dt: float) -> void:
	for t in 2:
		var k: Dictionary = kings[t]
		if bool(k.dead):
			continue
		var kp := king_pos(t)
		var near := []
		var any := false
		for o in s.units:
			if int(o.team) == t or int(o.team) > 1 or not s.alive(o):
				continue
			var d: float = (o.pos as Vector2).distance_to(kp)
			if d <= KING_GUARD:
				any = true
			if d <= KING_REACH + s.UNIT_R:
				near.append(o)
		if not near.is_empty() and s.time >= float(k.next):
			k.next = s.time + KING_EVERY
			var dmg: float = KING_SLAM * (1.0 + TOWER_GROW * float(s.time) / 60.0)
			s._event("king_slam", {"team":t})
			for o in near:
				s._next_push = s._push_from(kp, o.pos, 5.0, 2.6)
				s._damage({"id":"king%d" % t, "team":t, "pos":kp, "state":"idle"}, o, dmg * (KING_SLAM_MINION if bool(o.get("minion", false)) else 1.0))
		if any:
			k.quiet = 0.0
		else:
			k.quiet = float(k.quiet) + dt
			if float(k.quiet) >= KING_QUIET and float(k.hp) < float(k.max_hp):
				k.hp = minf(float(k.max_hp), float(k.hp) + float(k.max_hp) * KING_REGEN * dt)

# ---------- hits and knockouts ----------
func on_damage(src: Dictionary, dst: Dictionary, amount: float) -> void:
	if src.is_empty() or int(src.get("team", -1)) == int(dst.team):
		return
	var ls := float(src.get("m_ls", 0.0))
	if ls > 0.0 and amount > 0.0 and src.has("hp") and s.alive(src):
		s._heal(src, src, amount * ls)
	if bool(dst.get("hero", false)) and bool(src.get("hero", false)):
		dst["hh_by"] = str(src.id)
		dst["hh_at"] = s.time
	if bool(dst.get("hero", false)):
		var hb := _credit(src)
		if not hb.is_empty():
			if not dst.has("hit_log"):
				dst["hit_log"] = {}
			(dst.hit_log as Dictionary)[str(hb.id)] = s.time    # (0.31.157: who helped -- assists)
	if dst.has("mon") and int(src.get("team", -1)) in [0, 1] and s.by_id.has(str(src.get("id", ""))):
		var camp: Dictionary = camps[int(dst.mon)]            # 0.31.157: a camp hit -- it fights back
		(camp.hits as Dictionary)[str(src.id)] = s.time
		var cur: Dictionary = s.by_id.get(str(camp.target), {})
		if cur.is_empty() or not s.alive(cur) or (cur.pos as Vector2).distance_to(camp.p) > _leash(camp):
			camp.target = str(src.id)

func on_kill(src: Dictionary, dst: Dictionary) -> void:
	dst["died_at"] = s.time
	dst["died_hat"] = -1
	dst.task = {}
	dst.load = {"kind":"", "n":0}
	dst.offering = false
	dst.deaths = int(dst.deaths) + 1
	var push: Vector3 = dst.get("death_push", Vector3.ZERO)
	var by_h := _credit(src)                     # 0.31.157: the hero behind the blow (a Necromancer's skeleton's: him)
	if dst.has("mon"):
		dst.respawn_at = INF
		dst["gone_at"] = s.time + MINION_GONE
		_monster_down(dst, by_h)
	elif bool(dst.get("summon", false)):
		dst.respawn_at = INF
		dst["gone_at"] = s.time + MINION_GONE      # (no reward for the Necromancer's skeletons)
	elif bool(dst.get("minion", false)):
		dst.respawn_at = INF
		dst["gone_at"] = s.time + MINION_GONE
		var near := []
		for hid in heroes[1 - int(dst.team)]:
			var h: Dictionary = s.by_id.get(hid, {})
			if not h.is_empty() and s.alive(h) and (h.pos as Vector2).distance_to(dst.pos) <= XP_R:
				near.append(h)
		for h in near:
			add_xp(h, MINION_XP * (1.0 if near.size() == 1 else 0.65))
		if not by_h.is_empty() and int(by_h.team) != int(dst.team):
			add_gold(by_h, float(GOLD_MINION.get(str(dst.cls), 15)), dst.pos)     # the last hit
	elif bool(dst.get("hero", false)):
		dst.respawn_at = s.time + RESPAWN_BASE + RESPAWN_LVL * float(int(dst.level))
		dst.erase("dance")
		if not src.is_empty() and src.has("team") and int(src.team) != int(dst.team) and int(src.team) <= 1:
			s.kills[int(src.team)] += 1
			if bool(src.get("hero", false)):
				src.kills = int(src.kills) + 1
				s._multi_kill(src, dst)
				s._stat_add(src, "kills", 1.0)
		var reward := HERO_XP + HERO_XP_LVL * float(int(dst.level))
		if bool(src.get("hero", false)):
			add_xp(src, reward)
		for hid in heroes[1 - int(dst.team)]:
			var h2: Dictionary = s.by_id.get(hid, {})
			if not h2.is_empty() and h2 != src and s.alive(h2) and (h2.pos as Vector2).distance_to(dst.pos) <= XP_R:
				add_xp(h2, reward * 0.5)
		_hero_down_gold(dst, by_h)
		_pass_buffs(dst, by_h)
	s._event("death", {"id":dst.id, "by":src.get("id", ""), "push":[snappedf(push.x, 0.01), snappedf(push.y, 0.01), snappedf(push.z, 0.01)],
		"minion":bool(dst.get("minion", false)), "mon":dst.has("mon")})

# ---------- ACTION: only the King ----------
func context(u: Dictionary) -> String:
	if true:
		return ""                                # (0.31.156: the Kings are the hearts -- nothing to lift)
	if u.carrying:
		var ho: Dictionary = s.lifting_oracle(u)
		return "throw" if (not ho.is_empty() and ho.lifters.size() == 1 and s.lifters_needed(ho) == 1) else "letgo"
	var lo: Dictionary = s._liftable(u)
	if not lo.is_empty():
		return "join" if lo.state == "carried" else "grab"
	return ""

func interact(u: Dictionary) -> bool:
	if true:
		return false
	if u.carrying:
		var ho: Dictionary = s.lifting_oracle(u)
		s._leave_lift(u, not ho.is_empty() and ho.lifters.size() == 1 and s.lifters_needed(ho) == 1)
		return true
	var lo: Dictionary = s._liftable(u)
	if not lo.is_empty():
		s._join_lift(u, lo)
		return true
	return false

# ---------- the bots ----------
func think(u: Dictionary) -> void:
	if not s.alive(u) or u.stun > 0.0 or u.state in ["wind", "recover", "dodge"]:
		return
	s._unstick_check(u)
	if u.has("mon"):
		_think_monster(u)                     # 0.31.157: the jungle
	elif bool(u.get("summon", false)):
		_think_summon(u)                      # 0.31.157: the Necromancer's LEGION
	elif bool(u.get("minion", false)):
		_think_minion(u)
	else:
		_think_hero(u)

func _forward(u: Dictionary) -> Vector2:
	return Vector2(0, -1) if int(u.team) == 0 else Vector2(0, 1)

func _think_minion(u: Dictionary) -> void:
	var c: Dictionary = s.CLASSES[u.cls]
	var aggro := 9.0 if bool(c.ranged) else 5.5
	if u.cls == "priest":
		if s._think_priest(u):
			return
		# follow the wave: a step behind the nearest friend of the lane who isn't a priest
		var lead := {}
		var ld := 14.0
		for o in s.units:
			if o != u and int(o.team) == int(u.team) and s.alive(o) and bool(o.get("minion", false)) and int(o.lane) == int(u.lane) \
					and o.cls != "priest" and (o.pos as Vector2).distance_to(u.pos) < ld:
				ld = (o.pos as Vector2).distance_to(u.pos)
				lead = o
		if not lead.is_empty():
			s._nav_to(u, (lead.pos as Vector2) - _forward(u) * 2.0, 1.2)
			return
		_march(u)
		return
	var foe := _minion_unit_target(u, aggro, false)
	if not foe.is_empty():
		u["mt"] = str(foe.id)
		s._fight(u, foe)
		return
	var tw := _enemy_tower_near(u, aggro + TOWER_R)
	if not tw.is_empty():
		_hit_structure(u, tw)
		return
	var eteam := 1 - int(u.team)
	if king_open(eteam) and (u.pos as Vector2).distance_to(king_pos(eteam)) < aggro + KING_R + 2.0:
		_hit_point(u, king_pos(eteam), KING_R)
		return
	foe = _minion_unit_target(u, aggro, true)
	if not foe.is_empty():
		u["mt"] = str(foe.id)
		s._fight(u, foe)
		return
	_march(u)

func _minion_unit_target(u: Dictionary, aggro: float, heroes_too: bool) -> Dictionary:
	# a minion's target: an enemy hero who just hurt one of our heroes near me (call for help), the one I'm on, the
	# nearest enemy minion -- heroes only on the second pass (after towers)
	for h in s.units:
		if int(h.team) != int(u.team) or not bool(h.get("hero", false)) or not s.alive(h):
			continue
		if s.time - float(h.get("hh_at", -99.0)) <= HELP_FOR and (h.pos as Vector2).distance_to(u.pos) < 9.0:
			var a: Dictionary = s.by_id.get(str(h.get("hh_by", "")), {})
			if not a.is_empty() and s.alive(a) and (a.pos as Vector2).distance_to(u.pos) < aggro + 3.0:
				return a
	var cur: Dictionary = s.by_id.get(str(u.get("mt", "")), {})
	if not cur.is_empty() and s.alive(cur) and int(cur.team) <= 1 and (cur.pos as Vector2).distance_to(u.pos) < aggro + 2.5 \
			and (heroes_too or not bool(cur.get("hero", false))):
		return cur
	var best := {}
	var bd := aggro
	for o in s.units:
		if int(o.team) == int(u.team) or int(o.team) > 1 or not s.alive(o) or o.state == "fly":
			continue                                  # (0.31.157: minions leave the jungle's monsters alone)
		if bool(o.get("hero", false)) and not heroes_too:
			continue
		var d: float = (o.pos as Vector2).distance_to(u.pos)
		if d < bd:
			bd = d
			best = o
	return best

func _enemy_tower_near(u: Dictionary, r: float) -> Dictionary:
	var best := {}
	var bd := r
	for tw in towers:
		if int(tw.team) == int(u.team) or bool(tw.dead):
			continue
		var d: float = (u.pos as Vector2).distance_to(tw.p)
		if d < bd:
			bd = d
			best = tw
	return best

func _hit_structure(u: Dictionary, tw: Dictionary) -> void:
	# up to it and swing / shoot (an invulnerable one too: it's in the way -- the hit does nothing)
	_hit_point(u, tw.p, TOWER_R)

func _hit_point(u: Dictionary, p: Vector2, r: float) -> void:
	var c: Dictionary = s.CLASSES[u.cls]
	var d: float = (u.pos as Vector2).distance_to(p) - r
	var reach: float = float(c.range) * (0.85 if bool(c.ranged) else 1.0)
	if d > reach:
		s._nav_to(u, p, r + reach * 0.8)
		return
	u.move = Vector2.ZERO
	u.face = s.angle_of(p - (u.pos as Vector2))
	s._start_attack(u, "attack", false)

func _march(u: Dictionary) -> void:
	var l := int(u.lane)
	var i := int(u.get("wp", 1))
	var goal := wp(int(u.team), l, i)
	if (u.pos as Vector2).distance_to(goal) < 2.5 and i < lane_len(l) - 1:
		u.wp = i + 1
		goal = wp(int(u.team), l, i + 1)
	if i >= lane_len(l) - 1:
		# the lane's end: the enemy gate -- in through it once it's down (to whatever's inside)
		var g := _gate_at(1 - int(u.team), goal)
		if not g.is_empty() and s.gate_blocks(g):
			_hit_gate(u, g)
			return
		goal = s.throne(1 - int(u.team))
	s._nav_to(u, goal, 0.8)

func _gate_at(team: int, p: Vector2) -> Dictionary:
	for g in s.gates:
		if int(g.team) == team and str(g.get("kind", "")) != "jail" and (g.c as Vector2).distance_to(p) < 6.0:
			return g
	return {}

func _hit_gate(u: Dictionary, g: Dictionary) -> void:
	var c: Dictionary = s.CLASSES[u.cls]
	var cp: Vector2 = s.seg_closest(u.pos, g.a, g.b)
	var d: float = (u.pos as Vector2).distance_to(cp)
	var reach: float = float(c.range) * (0.8 if bool(c.ranged) else 1.0)
	if d > reach + s.WALL_R:
		s._nav_to(u, cp + (g["in"] as Vector2) * -1.2, 0.6)
		return
	u.move = Vector2.ZERO
	u.face = s.angle_of(cp - (u.pos as Vector2))
	s._start_attack(u, "attack", false)

func _think_hero(u: Dictionary) -> void:
	var c: Dictionary = s.CLASSES[u.cls]
	var reach := float(c.range)
	# our King under attack: those near come back and fight whoever's at him
	var th := king_threat(int(u.team))
	if not th.is_empty() and (u.pos as Vector2).distance_to(king_pos(int(u.team))) < 45.0 and u.hp > u.max_hp * 0.35:
		_fight_h(u, th)
		return
	# their King open (a gate of his down): the King runners go for him -- their heroes in the way first
	var eteam := 1 - int(u.team)
	if king_open(eteam) and ((bool(u.get("kr", false)) and u.hp > u.max_hp * 0.45) or (_end_push(int(u.team)) and u.hp > u.max_hp * 0.35)):
		for o in s.units:
			if int(o.team) == eteam and s.alive(o) and bool(o.get("hero", false)) and (o.pos as Vector2).distance_to(u.pos) < reach + 3.0:
				_fight_h(u, o)
				return
		_hit_point(u, king_pos(eteam), KING_R)
		return
	# 0.31.157: the ultimate when it's worth it (before running home: GRACE, BULWARK, UNDYING are for hard moments)
	if _bot_ult(u):
		return
	# hurt: home to heal
	if bool(u.get("back", false)):
		if u.hp >= u.max_hp * 0.92:
			u.back = false
		else:
			s._nav_to(u, s.spawn(int(u.team)), 1.5)
			return
	if u.hp < u.max_hp * 0.3 and not s.in_castle(u.pos, int(u.team)):
		u["back"] = true
		s._nav_to(u, s.spawn(int(u.team)), 1.5)
		return
	# 0.31.157: the Bone Lord when the side goes for him
	if boss_go[int(u.team)] and u.hp > u.max_hp * 0.45 and _go_lord(u):
		return
	if u.cls == "priest" and s._think_priest(u):
		return
	# under an enemy tower that would shoot me (no minion of ours for it to shoot first, or it's on me): step out
	var tw := tower_in_range(1 - int(u.team), u.pos, 0.6)
	if not tw.is_empty() and (str(tw.target) == str(u.id) or not _our_minions_near(int(u.team), tw.p)):
		var away: Vector2 = ((u.pos as Vector2) - (tw.p as Vector2)).normalized()
		u.move = (away - _forward(u) * 0.6).normalized()
		return
	# an enemy hero in reach and not under his tower
	var foe := {}
	var fd := reach + 4.0
	for o in s.units:
		if int(o.team) == int(u.team) or not s.alive(o) or not bool(o.get("hero", false)):
			continue
		var d: float = (o.pos as Vector2).distance_to(u.pos)
		if d < fd and (tower_in_range(1 - int(u.team), o.pos).is_empty() or _our_minions_near(int(u.team), o.pos)):
			fd = d
			foe = o
	if not foe.is_empty():
		_fight_h(u, foe)
		return
	# 0.31.157: a camp that's fighting me (anyone), the jungler's rounds
	var jm := _monster_on(u)
	if not jm.is_empty():
		_fight_h(u, jm)
		return
	if int(u.get("lane", 1)) == JUNGLE and _think_jungle(u):
		return
	# minions near
	var m := {}
	var md := maxf(reach + 2.0, 7.0)
	for o in s.units:
		if int(o.team) == int(u.team) or not s.alive(o) or not bool(o.get("minion", false)):
			continue
		var d2: float = (o.pos as Vector2).distance_to(u.pos)
		if d2 < md and tower_in_range(1 - int(u.team), o.pos).is_empty():
			md = d2
			m = o
	if not m.is_empty():
		_fight_h(u, m)
		return
	# their tower, while our minions take its shots
	var et := _enemy_tower_near(u, reach + 8.0)
	if not et.is_empty() and vulnerable(et) and _our_minions_near(int(u.team), et.p) and str(et.target) != str(u.id):
		_hit_structure(u, et)
		return
	# 0.31.157: their gate, once it can be hurt, while our minions are at it (League's heroes hit the inhibitor too)
	for g in s.gates:
		if int(g.team) == int(u.team) or str(g.get("kind", "")) == "jail" or not s.gate_blocks(g) or not gate_open(g):
			continue
		if (g.c as Vector2).distance_to(u.pos) < reach + 10.0 and _our_minions_near(int(u.team), g.c):
			_hit_gate(u, g)
			return
	# follow our wave in my lane (a few steps behind its front); none out: wait by my lane's front tower
	var l := int(u.get("lane", 1))
	if l == JUNGLE:
		l = int(u.get("gank", 1))
	if l < 0:
		l = 1
	var front := {}
	var fi := -1
	for o in s.units:
		if int(o.team) != int(u.team) or not s.alive(o) or not bool(o.get("minion", false)) or int(o.lane) != l:
			continue
		if int(o.wp) > fi or (int(o.wp) == fi and (o.pos as Vector2).dot(_forward(u)) > (front.pos as Vector2).dot(_forward(u))):
			fi = int(o.wp)
			front = o
	var goal: Vector2
	if not front.is_empty():
		goal = (front.pos as Vector2) - _forward(u) * 3.0
	else:
		goal = _home_tower_spot(int(u.team), l)
	s._nav_to(u, goal, 1.2)

func _fight_h(u: Dictionary, foe: Dictionary) -> void:
	# a hero bot's fight: the sim's, but a Priest has no shot -- the Necromancer drains (his beam) from close enough,
	# the Priest keeps a few steps off and leaves the healing to his own thinking (0.31.157)
	if u.cls != "priest":
		s._fight(u, foe)
		return
	var d: float = (u.pos as Vector2).distance_to(foe.pos)
	if bool(u.up) and d <= float(s.CLASSES.priest.range) - 1.5:
		u.move = Vector2.ZERO
		u.face = s.angle_of((foe.pos as Vector2) - (u.pos as Vector2))
		s._beam(u)
		return
	s._nav_to(u, foe.pos, float(s.CLASSES.priest.range) - 2.5 if bool(u.up) else 6.0)

func _end_push(team: int) -> bool:
	# (0.31.157) their King open and we're clearly ahead right now -- two more of us standing: everyone goes for him
	var up := [0, 0]
	for t in 2:
		for hid in heroes[t]:
			var h: Dictionary = s.by_id.get(hid, {})
			if not h.is_empty() and s.alive(h):
				up[t] += 1
	return up[team] >= 3 and up[team] >= up[1 - team] + 2

func _our_minions_near(team: int, p: Vector2) -> bool:
	for o in s.units:
		if bool(o.get("minion", false)) and int(o.team) == team and s.alive(o) and (o.pos as Vector2).distance_to(p) <= TOWER_RANGE:
			return true
	return false

func _home_tower_spot(team: int, l: int) -> Vector2:
	# behind our frontmost standing tower of the lane (or at the gate)
	var best := {}
	for tw in towers:
		if int(tw.team) == team and int(tw.lane) == l and not bool(tw.dead) and (best.is_empty() or int(tw.tier) < int(best.tier)):
			best = tw
	if best.is_empty():
		return wp(team, l, 1)
	var fwd := Vector2(0, -1) if team == 0 else Vector2(0, 1)
	return (best.p as Vector2) - fwd * 3.0

func _enemy_gate_down(team: int) -> bool:
	for g in s.gates:
		if int(g.team) != team and str(g.get("kind", "")) != "jail" and not s.gate_blocks(g):
			return true
	return false

# ======================================================================================================================
# 0.31.157 ULTIMATES (Kevin: "Build the other 3 mechanics now")
# ======================================================================================================================
func ult_rank(u: Dictionary) -> int:
	var lv := int(u.get("level", 1))
	return 0 if lv < ULT_LEVEL else (1 if lv < ULT_RANK2 else 2)

func ult_info(u: Dictionary) -> Dictionary:
	return ULTS.get(str(u.get("hid", "")), {})

func ult_max_cd(u: Dictionary) -> float:
	return float(ult_info(u).get("cd", 60.0)) * (RANK2_CD if ult_rank(u) >= 2 else 1.0)

func ult_ready(u: Dictionary) -> bool:
	return bool(u.get("hero", false)) and ult_rank(u) > 0 and float(u.get("ult_cd", 0.0)) <= 0.0 and s.alive(u)

func ult(u: Dictionary) -> bool:
	if not ult_ready(u) or not s.can_act(u) or u.has("dance"):
		return false
	var k := RANK2_POWER if ult_rank(u) >= 2 else 1.0
	var dmg := float(s.stat(u, "dmg"))
	var hid := str(u.hid)
	var ev := {"id":u.id, "team":int(u.team), "ult":hid, "pos":u.pos}
	match hid:
		"knight":
			var ids := []
			for o in s.units:
				if int(o.team) == int(u.team) and s.alive(o) and (o.pos as Vector2).distance_to(u.pos) <= BULWARK_R \
						and (bool(o.get("hero", false)) or bool(o.get("minion", false))):
					o["dr_until"] = s.time + BULWARK_TIME * k
					o["dr"] = minf(0.7, BULWARK_DR * (1.0 + (k - 1.0) * 0.5))
					ids.append(o.id)
			ev["ids"] = ids
		"barbarian":
			u["bl_until"] = s.time + WARCRY_TIME * k
		"rogue":
			var tgt := _weakest_hero(u, EXECUTE_R)
			if tgt.is_empty():
				tgt = s.nearest_enemy(u, EXECUTE_R)
			if tgt.is_empty():
				return false
			var behind: Vector2 = (tgt.pos as Vector2) - s.dir_of(float(tgt.face)) * 1.1
			ev["from"] = u.pos
			u.pos = s._clamp_to_field(s._push_out(behind, s.UNIT_R, int(u.team)))
			u.face = s.angle_of((tgt.pos as Vector2) - (u.pos as Vector2))
			s._next_push = s._push_from(u.pos, tgt.pos, 5.0, 2.0)
			s._damage(u, tgt, dmg * EXECUTE_DMG * k + EXECUTE_MISSING * maxf(0.0, float(tgt.max_hp) - float(tgt.hp)))
			ev["to"] = u.pos
			ev["target"] = str(tgt.id)
		"ranger":
			var at := _ult_aim(u, RAIN_RANGE, u.pos + s.dir_of(u.face) * 9.0)
			rains.append({"team":int(u.team), "owner":str(u.id), "at":at, "r":RAIN_R, "left":RAIN_TICKS, "next":s.time + 0.25,
				"dmg":dmg * RAIN_DMG * k})
			u.face = s.angle_of(at - (u.pos as Vector2))
			ev["at"] = at
			ev["r"] = RAIN_R
			ev["dur"] = 0.25 + RAIN_EVERY * float(RAIN_TICKS)
		"mage":
			for o in _enemies_in(u, u.pos, INFERNO_R):
				s._next_push = s._push_from(u.pos, o.pos, 6.0, 3.0)
				s._damage(u, o, dmg * INFERNO_DMG * k, INFERNO_STUN)
			ev["r"] = INFERNO_R
		"priest":
			var ids2 := []
			for hid2 in heroes[int(u.team)]:
				var h: Dictionary = s.by_id.get(hid2, {})
				if not h.is_empty() and s.alive(h):
					s._heal(u, h, float(h.max_hp) * GRACE_HEAL * k)
					ids2.append(h.id)
			ev["ids"] = ids2
		"crusader":
			for o in _enemies_in(u, u.pos, JUDGMENT_R):
				s._next_push = s._push_from(u.pos, o.pos, 4.0, 2.4)
				s._damage(u, o, dmg * JUDGMENT_DMG * k, JUDGMENT_STUN)
			for o2 in s.units:
				if int(o2.team) == int(u.team) and s.alive(o2) and (o2.pos as Vector2).distance_to(u.pos) <= JUDGMENT_R:
					s._heal(u, o2, float(o2.max_hp) * JUDGMENT_HEAL * k)
			ev["r"] = JUDGMENT_R
		"berserker":
			u["ud_until"] = s.time + UNDYING_TIME * (1.0 + (k - 1.0) * 0.6)
		"assassin":
			var tg := []
			var pool := _enemies_in(u, u.pos, FLURRY_R)
			var me_p: Vector2 = u.pos
			pool.sort_custom(func(a, b): return _flurry_key(a, me_p) < _flurry_key(b, me_p))       # heroes first, nearest first
			for o in pool:
				if tg.size() >= FLURRY_N + (1 if k > 1.0 else 0):
					break
				tg.append(str(o.id))
			if tg.is_empty():
				return false
			u["dance"] = {"ids":tg, "i":0, "next":s.time, "dmg":dmg * FLURRY_DMG * k}
			ev["ids"] = tg
		"sniper":
			var aim := _ult_aim_hero(u, DEADEYE_RANGE * 0.8)
			if aim != Vector2.INF:
				u.face = s.angle_of(aim - (u.pos as Vector2))
			var d: Vector2 = s.dir_of(u.face)
			s.projectiles.append({"id":s._next_proj, "team":int(u.team), "owner":u.id, "pos":(u.pos as Vector2) + d * 0.6, "from":u.pos,
				"vel":d * DEADEYE_SPEED, "dmg":dmg * DEADEYE_DMG * k, "aoe":0.0, "life":DEADEYE_RANGE / DEADEYE_SPEED, "kind":"pierce",
				"gate_mult":0.0, "hit":[], "high":true, "stun":DEADEYE_STUN, "big":true})
			s._event("proj", {"pid":s._next_proj, "kind":"pierce"})
			s._next_proj += 1
		"archmage":
			var c := _ult_aim(u, STORM_RANGE, u.pos + s.dir_of(u.face) * 9.0)
			u.face = s.angle_of(c - (u.pos as Vector2))
			var n := STORM_N + (2 if k > 1.0 else 0)
			for i in n:
				var off := Vector2.ZERO if i == 0 else Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.0, STORM_SPREAD)
				var at2: Vector2 = s._push_out(c + off, 0.2)
				var delay := 0.6 + 0.3 * float(i)
				s.meteors.append({"team":int(u.team), "owner":u.id, "at":at2, "t_hit":s.time + delay, "dmg":dmg * STORM_DMG, "burn_until":-1.0})
				s._event("meteor_warn", {"id":u.id, "team":int(u.team), "pos":at2, "delay":delay})
			ev["at"] = c
		"necromancer":
			var ids3 := []
			var n2 := LEGION_N + (2 if k > 1.0 else 0)
			for i in n2:
				var z := _raise_skeleton(u, (u.pos as Vector2) + Vector2.from_angle(TAU * float(i) / float(n2) + 0.4) * 1.8)
				ids3.append(z.id)
			ev["ids"] = ids3
		_:
			return false
	u.ult_cd = ult_max_cd(u)
	if hid not in ["rogue", "assassin"]:
		u.state = "recover"                        # (a beat to cast it; the view plays the cast)
		u.t = 0.35
		u.move = Vector2.ZERO
	s._event("ult", ev)
	return true

func _flurry_key(o: Dictionary, p: Vector2) -> float:
	return (0.0 if bool(o.get("hero", false)) else 100.0) + (o.pos as Vector2).distance_to(p)

func _enemies_in(u: Dictionary, at: Vector2, r: float) -> Array:
	var out := []
	for o in s.units:
		if int(o.team) != int(u.team) and s.alive(o) and o.state != "fly" and (o.pos as Vector2).distance_to(at) <= r:
			out.append(o)
	return out

func _weakest_hero(u: Dictionary, r: float) -> Dictionary:
	var best := {}
	var bf := INF
	for o in s.units:
		if int(o.team) == int(u.team) or int(o.team) > 1 or not s.alive(o) or not bool(o.get("hero", false)):
			continue
		if (o.pos as Vector2).distance_to(u.pos) > r:
			continue
		var f := float(o.hp) / maxf(1.0, float(o.max_hp))
		if f < bf:
			bf = f
			best = o
	return best

func _ult_aim(u: Dictionary, r: float, fallback: Vector2) -> Vector2:
	# an area ult's centre: the nearest enemy hero in reach, else the nearest enemy, else ahead
	var h := {}
	var hd := r
	for o in s.units:
		if int(o.team) != int(u.team) and int(o.team) <= 1 and s.alive(o) and bool(o.get("hero", false)):
			var d: float = (o.pos as Vector2).distance_to(u.pos)
			if d < hd:
				hd = d
				h = o
	if h.is_empty():
		h = s.nearest_enemy(u, r)
	return h.pos if not h.is_empty() else s._clamp_to_field(fallback)

func _ult_aim_hero(u: Dictionary, r: float) -> Vector2:
	# the nearest enemy hero in reach (the Ranger's DEADEYE turns to him); INF: none -- shoot where you face
	var best := Vector2.INF
	var bd := r
	for o in s.units:
		if int(o.team) != int(u.team) and int(o.team) <= 1 and s.alive(o) and bool(o.get("hero", false)):
			var d: float = (o.pos as Vector2).distance_to(u.pos)
			if d < bd:
				bd = d
				best = o.pos
	return best

func _step_rains(_dt: float) -> void:
	for i in range(rains.size() - 1, -1, -1):
		var r: Dictionary = rains[i]
		if s.time < float(r.next):
			continue
		r.next = float(r.next) + RAIN_EVERY
		r.left = int(r.left) - 1
		var owner: Dictionary = s.by_id.get(str(r.owner), {"team":int(r.team), "id":""})
		for o in s.units:
			if int(o.team) != int(r.team) and s.alive(o) and o.state != "fly" and (o.pos as Vector2).distance_to(r.at) <= float(r.r):
				s._damage(owner, o, float(r.dmg))
		if int(r.left) <= 0:
			rains.remove_at(i)

func _step_dance(u: Dictionary) -> void:
	# the Assassin's FLURRY: one strike every FLURRY_EVERY, beside each target in turn
	var dn: Dictionary = u.dance
	if s.time < float(dn.next):
		return
	var ids: Array = dn.ids
	while int(dn.i) < ids.size():
		var t: Dictionary = s.by_id.get(str(ids[int(dn.i)]), {})
		dn.i = int(dn.i) + 1
		if t.is_empty() or not s.alive(t):
			continue
		var side := Vector2.from_angle(rng.randf() * TAU) * 1.0
		var from: Vector2 = u.pos
		u.pos = s._clamp_to_field(s._push_out((t.pos as Vector2) + side, s.UNIT_R, int(u.team)))
		u.face = s.angle_of((t.pos as Vector2) - (u.pos as Vector2))
		u.state = "recover"
		u.t = FLURRY_EVERY + 0.05
		u.move = Vector2.ZERO
		s._next_push = s._push_from(u.pos, t.pos, 4.0, 1.6)
		s._damage(u, t, float(dn.dmg))
		s._event("flurry_hit", {"id":u.id, "target":t.id, "from":from, "pos":u.pos})
		s._event("attack", {"id":u.id, "kind":"attack", "ability":"", "combo":int(dn.i) % 3})
		dn.next = s.time + FLURRY_EVERY
		return
	u.erase("dance")

func mod_damage(src: Dictionary, dst: Dictionary, amount: float) -> float:
	# (sim._damage, before the hit lands) what the ultimates, the buffs and the items do to a hit
	var a := amount
	var t: float = s.time
	if not src.is_empty():
		if t < float(src.get("bl_until", -1.0)):
			a *= WARCRY_DMG
		if t < float(src.get("ud_until", -1.0)):
			a *= UNDYING_DMG
		var b: Dictionary = src.get("buffs", {})
		if not b.is_empty():
			if t < float(b.get("ember", -1.0)):
				a *= EMBER_DMG
			if t < float(b.get("lord", -1.0)):
				a *= LORD_DMG
	if t < float(dst.get("dr_until", -1.0)):
		a *= 1.0 - float(dst.get("dr", 0.0))
	a *= 1.0 - float(dst.get("m_armor", 0.0))
	if t < float(dst.get("ud_until", -1.0)):
		a = minf(a, maxf(0.0, float(dst.hp) - 1.0))         # UNDYING: never below 1
	return a

func _raise_skeleton(owner: Dictionary, at: Vector2) -> Dictionary:
	_zid += 1
	var id := "z%d" % _zid
	var z: Dictionary = s._new_unit(id, int(owner.team), true, "raid")
	z.cls = "rogue"
	z["summon"] = true
	z["minion"] = true
	z["lane"] = -1
	z["owner"] = str(owner.id)
	z["expire"] = s.time + LEGION_TIME
	z["look"] = "skel_minion"
	var lv := float(int(owner.get("level", 1)) - 1)
	z["m_hp"] = LEGION_HP * (1.0 + LEVEL_GROW * lv)
	z["m_dmg"] = LEGION_DMG * (1.0 + LEVEL_GROW * lv)
	z["m_spd"] = 1.0
	z.max_hp = float(s.stat(z, "hp"))
	z.hp = z.max_hp
	z.pos = s._clamp_to_field(s._push_out(at, s.UNIT_R, int(owner.team)))
	z.face = owner.face
	z.think_at = s.time + s.TICK
	s.units.append(z)
	s.by_id[id] = z
	return z

func _think_summon(u: Dictionary) -> void:
	# a LEGION skeleton: the nearest enemy near its Necromancer, else at his side
	var owner: Dictionary = s.by_id.get(str(u.get("owner", "")), {})
	var base: Vector2 = owner.pos if not owner.is_empty() and s.alive(owner) else u.pos
	var best := {}
	var bd := 12.0
	for o in s.units:
		if int(o.team) == int(u.team) or not s.alive(o) or o.state == "fly":
			continue
		if o.has("mon") and str(camps[int(o.mon)].target) == "":
			continue                                   # (sleeping monsters are left alone)
		var d: float = (o.pos as Vector2).distance_to(base)
		if d < bd:
			bd = d
			best = o
	if not best.is_empty():
		s._fight(u, best)
		return
	s._nav_to(u, base, 2.5)

func _bot_ult(u: Dictionary) -> bool:
	# when a bot's ultimate is worth it
	if not ult_ready(u) or not s.can_act(u):
		return false
	var hid := str(u.hid)
	var et := 1 - int(u.team)
	var near_h := 0
	var near_any := 0
	var closest := {}
	var cd := INF
	for o in s.units:
		if int(o.team) == int(u.team) or not s.alive(o):
			continue
		var d: float = (o.pos as Vector2).distance_to(u.pos)
		if int(o.team) == et and bool(o.get("hero", false)):
			if d < cd:
				cd = d
				closest = o
			if d <= 7.0:
				near_h += 1
		if d <= 7.0 and (int(o.team) == et or (o.has("mon") and str(camps[int(o.mon)].target) != "")):
			near_any += 1
	var lord_fight := false
	var lord: Dictionary = _lord_unit()
	if not lord.is_empty() and str(camps[int(lord.mon)].target) != "" and (lord.pos as Vector2).distance_to(u.pos) < 8.0:
		lord_fight = true
	match hid:
		"knight":
			return (near_h >= 1 and (u.hp < u.max_hp * 0.6 or _allies_near(u, BULWARK_R) >= 2)) and ult(u)
		"barbarian":
			return ((cd < 4.0) or lord_fight) and ult(u)
		"rogue":
			var w := _weakest_hero(u, EXECUTE_R)
			return not w.is_empty() and float(w.hp) < float(w.max_hp) * 0.45 and ult(u)
		"ranger", "archmage":
			if closest.is_empty() or cd > (RAIN_RANGE if hid == "ranger" else STORM_RANGE):
				return lord_fight and ult(u)
			var crowd := 0
			for o in s.units:
				if int(o.team) == et and s.alive(o) and (o.pos as Vector2).distance_to(closest.pos) <= 4.5:
					crowd += 1
			return (crowd >= 3 or float(closest.hp) < float(closest.max_hp) * 0.4) and ult(u)
		"mage":
			return ((near_h >= 2) or (near_h >= 1 and near_any >= 4) or lord_fight) and ult(u)
		"priest":
			var low := 0
			for hid2 in heroes[int(u.team)]:
				var h: Dictionary = s.by_id.get(hid2, {})
				if not h.is_empty() and s.alive(h):
					if float(h.hp) < float(h.max_hp) * 0.3:
						return ult(u)
					if float(h.hp) < float(h.max_hp) * 0.6:
						low += 1
			return low >= 2 and ult(u)
		"crusader":
			return ((near_h >= 1 and near_any >= 2) or lord_fight) and ult(u)
		"berserker":
			return u.hp < u.max_hp * 0.3 and (near_h >= 1 or lord_fight) and ult(u)
		"assassin":
			return ((near_h >= 1 and (near_any >= 2 or (not closest.is_empty() and float(closest.hp) < float(closest.max_hp) * 0.5))) or lord_fight) and ult(u)
		"sniper":
			var aim := _ult_aim_hero(u, DEADEYE_RANGE * 0.8)
			if aim == Vector2.INF:
				return false
			for o in s.units:
				if int(o.team) == et and s.alive(o) and bool(o.get("hero", false)) and (o.pos as Vector2) == aim:
					return float(o.hp) < float(o.max_hp) * 0.4 and ult(u)
			return false
		"necromancer":
			return (near_h >= 1 or near_any >= 3 or lord_fight) and ult(u)
	return false

func _allies_near(u: Dictionary, r: float) -> int:
	var n := 0
	for o in s.units:
		if o != u and int(o.team) == int(u.team) and s.alive(o) and bool(o.get("hero", false)) and (o.pos as Vector2).distance_to(u.pos) <= r:
			n += 1
	return n

# ======================================================================================================================
# 0.31.157 GOLD AND THE SHOP
# ======================================================================================================================
func gate_mult(src: Dictionary) -> float:
	# (sim._damage_gate) a lane minion's blow on a gate counts MINION_SIEGE
	return MINION_SIEGE if lane_minion(str(src.get("id", ""))) else 1.0

func lane_minion(id: String) -> bool:
	var u: Dictionary = s.by_id.get(id, {})
	return bool(u.get("minion", false)) and not bool(u.get("summon", false))

func _credit(src: Dictionary) -> Dictionary:
	# the hero a blow counts for: himself, or the Necromancer whose skeleton it was ({} for towers, minions, monsters)
	if src.is_empty():
		return {}
	if bool(src.get("hero", false)):
		return src
	if bool(src.get("summon", false)):
		var o: Dictionary = s.by_id.get(str(src.get("owner", "")), {})
		if bool(o.get("hero", false)):
			return o
	return {}

func add_gold(u: Dictionary, n: float, at: Vector2) -> void:
	if u.is_empty() or not bool(u.get("hero", false)) or n <= 0.0:
		return
	u.gold = float(u.gold) + n
	u.gold_total = float(u.get("gold_total", 0.0)) + n
	s._event("gold", {"id":u.id, "n":int(round(n)), "pos":at if at != Vector2.INF else u.pos})

func _hero_down_gold(dst: Dictionary, by_h: Dictionary) -> void:
	# a hero knocked out: GOLD_HERO to whoever did it, GOLD_ASSIST between those who helped (hit him lately or stood by)
	var et := 1 - int(dst.team)
	if not by_h.is_empty() and int(by_h.team) == et:
		add_gold(by_h, GOLD_HERO, dst.pos)
	var hlog: Dictionary = dst.get("hit_log", {})
	var helpers := []
	for hid in heroes[et]:
		var h: Dictionary = s.by_id.get(hid, {})
		if h.is_empty() or h == by_h:
			continue
		var hit_lately: bool = s.time - float(hlog.get(str(hid), -99.0)) <= ASSIST_WINDOW
		if hit_lately or (s.alive(h) and (h.pos as Vector2).distance_to(dst.pos) <= XP_R):
			helpers.append(h)
	for h in helpers:
		add_gold(h, float(GOLD_ASSIST) / float(helpers.size()), dst.pos)
	dst["hit_log"] = {}

func item_stats(u: Dictionary) -> Dictionary:
	var out := {}
	for id in u.get("items", []):
		var it: Dictionary = ITEMS.get(str(id), {})
		for k in ["dmg", "hp", "as", "spd", "cdr", "ls", "regen", "armor", "heal"]:
			if it.has(k):
				out[k] = float(out.get(k, 0.0)) + float(it[k])
	return out

func can_shop(u: Dictionary) -> bool:
	# in your own castle, or while down
	return bool(u.get("hero", false)) and (not s.alive(u) or s.in_castle(u.pos, int(u.team)))

func _comps_owned(u: Dictionary, id: String) -> Array:
	# the inventory slots this item would be built from (each component once)
	var out := []
	var inv: Array = u.get("items", [])
	for c in ITEMS[id].get("from", []):
		for i in inv.size():
			if str(inv[i]) == str(c) and not out.has(i):
				out.append(i)
				break
	return out

func price(u: Dictionary, id: String) -> int:
	if not ITEMS.has(id):
		return 0
	var p := int(ITEMS[id].cost)
	var inv: Array = u.get("items", [])
	for i in _comps_owned(u, id):
		p -= int(ITEMS[str(inv[i])].cost)
	return maxi(0, p)

func buy_why(u: Dictionary, id: String) -> String:
	# "" when it can be bought now; else why not: "where", "gold", "full", "boots"
	if not ITEMS.has(id) or not bool(u.get("hero", false)):
		return "item"
	if not can_shop(u):
		return "where"
	var used := _comps_owned(u, id)
	var inv: Array = u.get("items", [])
	if inv.size() - used.size() >= ITEM_SLOTS:
		return "full"
	if bool(ITEMS[id].get("boots", false)):
		for i in inv.size():
			if bool(ITEMS[str(inv[i])].get("boots", false)) and not used.has(i):
				return "boots"
	if float(u.get("gold", 0.0)) < float(price(u, id)):
		return "gold"
	return ""

func buy(u: Dictionary, id: String) -> bool:
	if buy_why(u, id) != "":
		return false
	var cost := price(u, id)
	var used := _comps_owned(u, id)
	used.sort()
	used.reverse()
	for i in used:
		(u.items as Array).remove_at(i)
	(u.items as Array).append(id)
	(u.bought as Array).append(id)
	u.gold = float(u.gold) - float(cost)
	_apply(u)
	s._event("buy", {"id":u.id, "item":id, "cost":cost})
	return true

func sell(u: Dictionary, slot: int) -> bool:
	var inv: Array = u.get("items", [])
	if not can_shop(u) or slot < 0 or slot >= inv.size():
		return false
	var id := str(inv[slot])
	inv.remove_at(slot)
	var back := int(float(ITEMS[id].cost) * SELL_BACK)
	u.gold = float(u.gold) + float(back)
	_apply(u)
	s._event("sell", {"id":u.id, "item":id, "gold":back})
	return true

func _bot_shop(u: Dictionary) -> void:
	# the next thing on its class's list it hasn't bought (counting what went into bigger items); saves up for it
	var build: Array = BUILDS.get(str(u.cls), BUILDS.knight)
	var seen := {}
	for id in build:
		seen[id] = int(seen.get(id, 0)) + 1
		if (u.bought as Array).count(id) >= int(seen[id]):
			continue
		buy(u, str(id))
		return

# ======================================================================================================================
# 0.31.157 THE JUNGLE
# ======================================================================================================================
func _add_camp(kind: String, side: int, p: Vector2) -> void:
	camps.append({"id":camps.size(), "kind":kind, "side":side, "p":p, "mobs":[], "alive":false,
		"next":LORD_FIRST if kind == "lord" else CAMP_FIRST, "target":"", "hits":{}, "slam":0.0})

func _leash(camp: Dictionary) -> float:
	return LORD_LEASH if str(camp.kind) == "lord" else LEASH

func _spawn_camp(camp: Dictionary) -> void:
	var kd: Dictionary = CAMP_KINDS[camp.kind]
	var grow := 1.0 + MON_GROW * float(s.time) / 60.0
	var ids := []
	for m in kd.mobs:
		var mk := str(m[0])
		var md: Dictionary = MONSTERS[mk]
		var off: Vector2 = m[1]
		if int(camp.side) == 1:
			off = -off                                  # (red's camps face the other way)
		_jid += 1
		var id := "j%d" % _jid
		var u: Dictionary = s._new_unit(id, 2, true, "raid")
		u.cls = str(md.cls)
		u["mon"] = int(camp.id)
		u["mkind"] = mk
		u["look"] = str(md.look)
		u["mscale"] = float(md.get("scale", 1.0))
		u["m_hp"] = float(md.hp) * grow
		u["m_dmg"] = float(md.dmg) * grow
		u["m_spd"] = float(md.spd)
		u.max_hp = float(s.stat(u, "hp"))
		u.hp = u.max_hp
		u["home"] = (camp.p as Vector2) + off
		u.pos = u.home
		u.face = s.angle_of(Vector2(0, 1) if int(camp.side) == 0 else Vector2(0, -1)) if int(camp.side) >= 0 else s.angle_of(Vector2(1, 0))
		u["home_face"] = u.face
		u.think_at = s.time + s.TICK * float(ids.size() + 1)
		s.units.append(u)
		s.by_id[id] = u
		ids.append(id)
	camp.mobs = ids
	camp.alive = true
	camp.target = ""
	camp.hits = {}
	camp.slam = s.time + LORD_SLAM_EVERY
	s._event("camp_up", {"camp":int(camp.id), "kind":str(camp.kind), "ids":ids})

func camp_live(camp: Dictionary) -> Array:
	var out := []
	for id in camp.mobs:
		var m: Dictionary = s.by_id.get(str(id), {})
		if not m.is_empty() and s.alive(m):
			out.append(m)
	return out

func _step_camps(dt: float) -> void:
	for camp in camps:
		if not bool(camp.alive):
			if s.time >= float(camp.next):
				_spawn_camp(camp)
			continue
		var live := camp_live(camp)
		# the fight: a target who left the leash or fell -> the latest of the others who hit it, still inside
		var tgt: Dictionary = s.by_id.get(str(camp.target), {})
		var lr := _leash(camp)
		if not tgt.is_empty() and (not s.alive(tgt) or (tgt.pos as Vector2).distance_to(camp.p) > lr):
			tgt = {}
		if tgt.is_empty() and str(camp.target) != "":
			var best := ""
			var bt := -INF
			for hid in camp.hits:
				var h: Dictionary = s.by_id.get(str(hid), {})
				if h.is_empty() or not s.alive(h) or (h.pos as Vector2).distance_to(camp.p) > lr or s.time - float(camp.hits[hid]) > 6.0:
					continue
				if float(camp.hits[hid]) > bt:
					bt = float(camp.hits[hid])
					best = str(hid)
			camp.target = best
			if best == "":
				camp.hits = {}
		# left alone: they heal
		if str(camp.target) == "":
			for m in live:
				if float(m.hp) < float(m.max_hp):
					m.hp = minf(float(m.max_hp), float(m.hp) + float(m.max_hp) * RESET_HEAL * dt)
		elif str(camp.kind) == "lord" and not live.is_empty() and s.time >= float(camp.slam):
			# the Bone Lord's slam round him
			camp.slam = s.time + LORD_SLAM_EVERY
			var lord: Dictionary = live[0]
			var hit := 0
			for o in s.units:
				if int(o.team) <= 1 and s.alive(o) and (o.pos as Vector2).distance_to(lord.pos) <= LORD_SLAM_R:
					s._next_push = s._push_from(lord.pos, o.pos, 6.0, 3.0)
					s._damage(lord, o, float(s.stat(lord, "dmg")) * LORD_SLAM_DMG)
					hit += 1
			s._event("lord_slam", {"id":lord.id, "pos":lord.pos, "n":hit})

func _think_monster(u: Dictionary) -> void:
	var camp: Dictionary = camps[int(u.mon)]
	var home: Vector2 = u.home
	var tgt: Dictionary = s.by_id.get(str(camp.target), {})
	var lr := _leash(camp)
	if not tgt.is_empty() and s.alive(tgt) and (tgt.pos as Vector2).distance_to(camp.p) <= lr \
			and (u.pos as Vector2).distance_to(camp.p) <= lr + 4.0:
		u["resetting"] = false
		s._fight(u, tgt)
		return
	# nobody to fight: home, and stand
	if (u.pos as Vector2).distance_to(home) > 0.7:
		u["resetting"] = true
		s._nav_to(u, home, 0.4)
		return
	u["resetting"] = false
	u.move = Vector2.ZERO
	u.face = lerp_angle(float(u.face), float(u.get("home_face", u.face)), 0.3)

func _monster_down(dst: Dictionary, by_h: Dictionary) -> void:
	var camp: Dictionary = camps[int(dst.mon)]
	var md: Dictionary = MONSTERS[str(dst.mkind)]
	if str(dst.mkind) == "lord":
		# the Bone Lord: every hero of the side that brought him down
		var side := int(by_h.team) if not by_h.is_empty() else _side_near(dst.pos)
		if side >= 0:
			for hid in heroes[side]:
				var h: Dictionary = s.by_id.get(hid, {})
				if h.is_empty():
					continue
				add_gold(h, float(md.gold), dst.pos)
				add_xp(h, float(md.xp))
				if s.alive(h):
					(h.buffs as Dictionary)["lord"] = s.time + LORD_TIME
			boss_go[side] = false
		s._event("lord_down", {"team":side, "by":str(by_h.get("id", ""))})
	else:
		if not by_h.is_empty():
			add_gold(by_h, float(md.gold), dst.pos)
			var near := []
			for hid in heroes[int(by_h.team)]:
				var h2: Dictionary = s.by_id.get(hid, {})
				if not h2.is_empty() and s.alive(h2) and (h2.pos as Vector2).distance_to(dst.pos) <= XP_R:
					near.append(h2)
			for h2 in near:
				add_xp(h2, float(md.xp) * (1.0 if near.size() == 1 else 0.7))
			var buff := str(CAMP_KINDS[camp.kind].get("buff", ""))
			if buff != "" and str(camp.mobs[0]) == str(dst.id):
				(by_h.buffs as Dictionary)[buff] = s.time + BUFF_TIME       # the big one's buff: to whoever finished him
				s._event("buff", {"id":by_h.id, "team":int(by_h.team), "buff":buff})
	if camp_live(camp).is_empty():
		camp.alive = false
		camp.next = s.time + float(CAMP_KINDS[camp.kind].respawn)
		camp.target = ""
		s._event("camp_clear", {"camp":int(camp.id), "kind":str(camp.kind), "by":str(by_h.get("id", "")),
			"team":int(by_h.get("team", -1))})

func _side_near(p: Vector2) -> int:
	# (the Lord fell to no hero -- a stray meteor's owner gone): the side with more heroes near
	var n := [0, 0]
	for t in 2:
		for hid in heroes[t]:
			var h: Dictionary = s.by_id.get(hid, {})
			if not h.is_empty() and s.alive(h) and (h.pos as Vector2).distance_to(p) <= XP_R:
				n[t] += 1
	return -1 if n[0] == n[1] else (0 if n[0] > n[1] else 1)

func _pass_buffs(dst: Dictionary, by_h: Dictionary) -> void:
	# a fallen hero's ARCANE / EMBER go to whoever knocked him out (the LORD's blessing is just lost)
	var b: Dictionary = dst.get("buffs", {})
	for k in ["arcane", "ember"]:
		if s.time < float(b.get(k, -1.0)):
			if not by_h.is_empty() and int(by_h.team) != int(dst.team):
				(by_h.buffs as Dictionary)[k] = s.time + maxf(BUFF_PASS_MIN, float(b[k]) - s.time)
				s._event("buff", {"id":by_h.id, "team":int(by_h.team), "buff":k, "from":dst.id})
			b.erase(k)
	b.erase("lord")

func has_buff(u: Dictionary, k: String) -> bool:
	return s.time < float((u.get("buffs", {}) as Dictionary).get(k, -1.0))

func lord_buff(t: int) -> bool:
	for hid in heroes[t]:
		var h: Dictionary = s.by_id.get(hid, {})
		if not h.is_empty() and s.alive(h) and has_buff(h, "lord"):
			return true
	return false

func _lord_unit() -> Dictionary:
	for camp in camps:
		if str(camp.kind) == "lord" and bool(camp.alive):
			var live := camp_live(camp)
			return live[0] if not live.is_empty() else {}
	return {}

func _monster_on(u: Dictionary) -> Dictionary:
	# a monster of a camp that's fighting me or a friend right by me (the weakest of it in reach)
	var best := {}
	var bh := INF
	for camp in camps:
		if not bool(camp.alive) or str(camp.target) == "":
			continue
		var tg: Dictionary = s.by_id.get(str(camp.target), {})
		if tg.is_empty() or int(tg.team) != int(u.team) or (tg != u and (tg.pos as Vector2).distance_to(u.pos) > 7.0):
			continue
		for m in camp_live(camp):
			if (m.pos as Vector2).distance_to(u.pos) < 12.0 and float(m.hp) < bh:
				bh = float(m.hp)
				best = m
	return best

func _think_jungle(u: Dictionary) -> bool:
	# the jungler: our side's camps, nearest first (the buff camps count); none up: theirs once he's level 4; else
	# he walks a lane for a while (follows the wave: _think_hero's lane logic with "gank")
	var best := {}
	var bd := INF
	for pass_i in 2:
		for camp in camps:
			if not bool(camp.alive) or str(camp.kind) == "lord":
				continue
			if pass_i == 0 and int(camp.side) != int(u.team):
				continue
			if pass_i == 1 and (int(camp.side) == int(u.team) or int(u.level) < 4):
				continue
			var d: float = (camp.p as Vector2).distance_to(u.pos)
			if d < bd:
				bd = d
				best = camp
		if not best.is_empty():
			break
	if best.is_empty():
		if s.time >= float(u.get("gank_until", -1.0)):
			u["gank"] = rng.randi_range(0, 2)
			u["gank_until"] = s.time + 25.0
		return false
	var live := camp_live(best)
	if live.is_empty():
		return false
	var target: Dictionary = live[0]
	for m in live:
		if (m.pos as Vector2).distance_to(u.pos) < (target.pos as Vector2).distance_to(u.pos) - 1.5:
			target = m
	if bool(s.CLASSES[u.cls].ranged) and (u.pos as Vector2).distance_to(target.pos) > 6.0 and str(best.target) == "":
		s._nav_to(u, target.pos, 4.5)            # (close in first: from far off a rock or a tree can be in the way)
		return true
	_fight_h(u, target)
	return true

func _boss_call() -> void:
	# a side's bots go for the Bone Lord when he's up and they're clearly ahead right now (two of theirs down, or
	# well ahead in levels with four of ours up); they give it up when that's no longer so
	var lord := _lord_unit()
	for t in 2:
		if lord.is_empty():
			boss_go[t] = false
			continue
		var up := [0, 0]
		var lv := [0, 0]
		for tt in 2:
			for hid in heroes[tt]:
				var h: Dictionary = s.by_id.get(hid, {})
				if h.is_empty():
					continue
				lv[tt] += int(h.level)
				if s.alive(h):
					up[tt] += 1
		boss_go[t] = up[t] >= 3 and (up[1 - t] <= up[t] - 2 or (lv[t] >= lv[1 - t] + 5 and up[t] >= 4))

func _go_lord(u: Dictionary) -> bool:
	if not bool(u.bot):
		return false
	var lord := _lord_unit()
	if lord.is_empty() or (lord.pos as Vector2).distance_to(u.pos) > 60.0:
		return false
	# their heroes at the pit first
	for o in s.units:
		if int(o.team) == 1 - int(u.team) and s.alive(o) and bool(o.get("hero", false)) and (o.pos as Vector2).distance_to(lord.pos) < 10.0 \
				and (o.pos as Vector2).distance_to(u.pos) < 9.0:
			_fight_h(u, o)
			return true
	_fight_h(u, lord)
	return true
