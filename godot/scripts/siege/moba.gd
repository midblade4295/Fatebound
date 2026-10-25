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
# - Lanes (0.31.165: the Rift, siege_land.gd LANES -- the middle straight down the field, the two side lanes out along
#   its edges; until then the Siege field's west bridge, island and east bridge): each a track of points from one
#   keep's gate to the other's (the dirt paths). Every 30 s each castle sends a group down each lane: 1 Priest, 2
#   Archers, 1 Knight (WAVE). Minions march, fight what's in front of them and push on; a wave that's still alive when
#   the next comes is simply caught up with -- waves stack.
# - Towers (League's rules): three per lane per side (0.31.165; two until then) beside the track, and two King towers
#   in each keep (TOWERS_BLUE). A tower shoots the nearest enemy
#   minion in range; an enemy hero who hurts one of its heroes in range becomes its target at once (call for help);
#   otherwise heroes only when no minion is in range. Shots home in (no dodging); on a hero each shot in a row hits
#   harder (+40 %, up to 3 times), on a minion a share of its health (a Knight 45 %, the others 70 %). A lane's tower
#   can't be damaged while the one before it stands. Without your minions near it a tower takes a third of the damage
#   (backdoor protection). 0.31.217 (Kevin, Honor of Kings: "3 towers a lane, then the king (crystal)"): the keeps' gates
#   stand open and there are no King towers -- a lane's three towers, then the King (until then the third tower opened
#   that lane's gate, the gates the two King towers, and those the King).
#   Only basic attacks (and arrows / fire) hurt towers.
# - The heart is the King (0.31.156, Kevin: "Have the enemy king be the "heart" and players will have to defeat him"):
#   each King sits on his own throne, KING_HP of health, untouchable until the third tower of one of his lanes is down
#   (Honor of Kings' crystal; 0.31.217 -- both his King towers until then); then he can be hit (basic attacks, arrows, fire) and he fights back -- a slam round him every KING_EVERY s. Left
#   alone a while he heals. Defeat theirs and the match is won; at time (15 minutes since 0.31.157), the side that did more to the other's
#   King wins, then more towers down, then hero knockouts. No rescues, no lifting. When an enemy King is open two of
#   each side's bots go for him; bots near their own King under attack defend him.
# - 0.31.157 (Kevin: "Build the other 3 mechanics now" -- the ultimates, the jungle, the gold shop):
#   * ULTIMATES: at level ULT_LEVEL every hero gets his own (ULTS; the ULT button), stronger from ULT_RANK2. Bots use
#     theirs when it's worth it (_bot_ult).
#   * THE JUNGLE: camps of KayKit skeletons between and beside the lanes (CAMPS_BLUE, mirrored for red; the Bone Lord in
#     the river's west pit since 0.31.165, on the island until then). They're team 2 -- everyone's enemy -- but stand still until hit; then the camp fights whoever hit it
#     while he's within its LEASH, and walks home and heals once he's gone. Gold and XP for each; the two buff camps
#     give their killer a buff (ARCANE: abilities and the ultimate recharge faster; EMBER: harder hits); the Bone Lord
#     gives his killers' whole side gold, XP and the LORD buff (harder hits; their minions come out stronger). Towers
#     and minions leave them alone. One bot a side is the jungler; the bots gather for the Lord when they're ahead.
# - 0.31.167 (Kevin: "We need more characters and class roles like League of Legends and heroes of the storm have"):
#   League's six roles and kits of three abilities and the ultimate -- moba_kits.gd (ROLE_OF, KITS: Q the class's
#   ability, W from level 2, E from 3, R the ultimate); each side drafted by role into League's five places (draft).
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
	# 0.31.168 (Kevin picked six new heroes, one a role): each plays on an old class's frame -- its basic attack, its swings,
	# how a bot fights with it -- but has its own body, its own numbers (HERO_BASE), its own shot (HERO_SHOT) and its whole
	# kit, Q included (moba_kits.gd). Bought with gold in the app (economy.gd HERO_PRICES); the bots play them all.
	"golem": {"name":"Golem", "cls":"barbarian", "up":false},
	"dragoon": {"name":"Dragoon", "cls":"knight", "up":false},
	"duelist": {"name":"Duelist", "cls":"rogue", "up":false},
	"stormcaller": {"name":"Stormcaller", "cls":"mage", "up":false},
	"musketeer": {"name":"Musketeer", "cls":"ranger", "up":false},
	"druid": {"name":"Druid", "cls":"mage", "up":false},
}
const HERO_ORDER := ["knight", "barbarian", "rogue", "ranger", "mage", "priest", "crusader", "berserker", "assassin", "sniper",
	"archmage", "necromancer", "golem", "dragoon", "duelist", "stormcaller", "musketeer", "druid"]
# 0.31.168: the new heroes' own numbers over their class's (siege_sim.CLASSES; stat() reads them) and their shots
const HERO_BASE := {
	"golem": {"hp":172.0, "dmg":19.0, "speed":4.5, "range":2.1, "arc":0.35, "windup":0.36, "recover":0.48},
	"dragoon": {"hp":142.0, "dmg":23.0, "speed":4.8, "range":2.7, "arc":0.3, "windup":0.3, "recover":0.45},
	"duelist": {"hp":94.0, "dmg":15.0, "speed":6.3, "range":1.6, "arc":0.5, "windup":0.12, "recover":0.2},
	"stormcaller": {"hp":76.0, "dmg":21.0, "speed":5.0, "range":9.5, "proj_speed":34.0, "aoe":0.0, "windup":0.35, "recover":0.5},
	"musketeer": {"hp":80.0, "dmg":25.0, "speed":5.2, "range":12.5, "proj_speed":46.0, "windup":0.42, "recover":0.85},
	"druid": {"hp":88.0, "dmg":14.0, "speed":5.1, "range":9.0, "proj_speed":26.0, "aoe":0.0, "windup":0.35, "recover":0.45},
}
const HERO_SHOT := {"stormcaller":"bolt", "musketeer":"ball", "druid":"thorn"}
const HERO_SCALE := {"golem":1.12}                             # (the view: the Golem stands a head taller)
const HERO_LINE := {"knight":"Shield up: blocks everything from the front.", "barbarian":"Spins through a crowd.",
	"rogue":"Lunges in, quick and sharp.", "ranger":"Arrows from range, a volley of five.", "mage":"Fireballs, and a nova all round.",
	"priest":"Heals with a beam; Sanctuary heals everyone near.", "crusader":"Throws his hammer through a line, and blocks.",
	"berserker":"A whirlwind that keeps moving.", "assassin":"Vanishes, then strikes twice as hard.",
	"sniper":"A piercing shot through everyone in a line.", "archmage":"Calls down a meteor.",
	"necromancer":"Drains enemies to heal friends; raises the fallen.",
	"golem":"A wall of living stone: boulders, quakes, an avalanche.", "dragoon":"A halberd that sweeps, drags and dives from the sky.",
	"duelist":"Lunges, parries and answers -- a blade for one foe at a time.",
	"stormcaller":"Lightning that leaps from foe to foe, wind and a storm.",
	"musketeer":"Long, heavy shots; buckshot and powder kegs up close.",
	"druid":"Heals that grow over time, roots and bark, a grove of life."}

# the lanes as world points from the blue (team 0) gate to the red (team 1) gate; red walks them backwards. Point
# symmetric: lane 0 backwards and mirrored is lane 2. 0.31.165: the Rift's (siege_land.gd LANES; until then the Siege
# field's three crossings -- the west bridge, the island, the east bridge)
const Land = preload("res://scripts/siege/siege_land.gd")
const Keep = preload("res://scripts/siege/keep.gd")
const LANES := Land.LANES
const LANE_NAMES := ["west", "middle", "east"]
# blue's towers [lane, tier, position] -- beside the track, on its inner side; red's are the mirror. 0.31.165 (Kevin: "3
# towers per lane"): tier 1 outer, 2 inner, 3 the gate's (League's inhibitor turret), and tier 4 the two King towers in the
# keep (lane -1: League's nexus turrets). Each lane's tier n can't be hurt while its tier n - 1 stands; the gate at a
# lane's end while its tier 3 does; the King towers while all three gates stand; the King while a King tower does.
# 0.31.216 (the Honor of Kings square): the side lanes' towers along the square's edges, on the lane's inner side.
const TOWERS_BLUE := [[0, 1, Vector2(-73.04, 16.48)], [0, 2, Vector2(-44.76, 44.76)], [0, 3, Vector2(-17.89, 71.63)],
	[1, 1, Vector2(4.0, 30.0)], [1, 2, Vector2(4.0, 54.0)], [1, 3, Vector2(4.0, 74.5)],
	[2, 1, Vector2(73.04, 16.48)], [2, 2, Vector2(44.76, 44.76)], [2, 3, Vector2(17.89, 71.63)]]
# (0.31.217: no King towers -- Kevin: "3 towers a lane, then the king (crystal)"; tier 4, lane -1, until then)

# 0.31.158 (Kevin: "Balance the minions better, the game ended up have tons of priests. Also minions need to work like
# LoL"): League's waves -- 3 melee (Knights) and 3 casters (Archers); a siege minion (a battle-mage: tanky, ranged fire)
# every 3rd wave, every 2nd from MID_AT, every wave from LATE_AT (melee down to 2 in its waves from MID_AT); a super
# minion (a big Barbarian) instead of the siege one in a lane whose enemy gate is down (2 once both are). No healers.
# League's 30 / 25 / 20 s waves at 14:00 / 30:00 are at half the time here (the match is 15 minutes, not ~30).
const WAVE := ["knight", "ranger", "ranger", "priest"]      # (0.31.155-157: Kevin's 1 healer, 2 ranged, 1 knight; unused now)
const WAVE_FIRST := 15.0
const WAVE_EVERY := 30.0
const WAVE_EVERY_MID := 25.0
const WAVE_EVERY_LATE := 20.0
const MID_AT := 420.0                                       # 7:00 (League's 14:00)
const LATE_AT := 750.0                                      # 12:30 (League's 25:00)
const MINION_CLS := {"melee":"knight", "caster":"ranger", "siege":"mage", "super":"barbarian"}
const MINION_KIND_HP := {"melee":0.5, "caster":0.58, "siege":1.9, "super":2.2}      # League: 477 / 296 / 912 health
const MINION_KIND_DMG := {"melee":0.45, "caster":0.8, "siege":1.0, "super":1.6}
const MINION_KIND_SCALE := {"siege":1.1}      # (the view: x the minion size; 0.31.159: the super minion's own body is
	# fit by its full height, a head taller and twice as broad as the footman's, so no extra scale)
const MINION_UP := 0.05                                     # +5 % health and damage every 90 s (League upgrades them too)
const MINION_UP_EVERY := 90.0
const MINION_VS_HERO := 0.6                                 # League: minions deal 60 % to champions
const ACQ_R := 8.0                                          # a minion's acquisition range (League 500)
const HELP_R := 15.0                                        # its call for help reaches allied heroes this far (League 1000)
const MINION_CAP := 48                                      # per side alive (a phone-safety ceiling; waves stack below it)
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
const MINION_XP_BY := {"melee":16.0, "caster":8.0, "siege":25.0, "super":25.0}     # League's ratios (60 / 30 / 93)
const XP_R := 12.0
const HERO_XP := 40.0
const HERO_XP_LVL := 12.0
const TOWER_XP := 50.0
const RESPAWN_BASE := 4.0
const RESPAWN_LVL := 2.6                                    # (1.6 until 0.31.157: a won fight leaves a window to push)
const FOUNTAIN := 0.06                                      # of max health a second, in your own castle
const TOWER_R := 1.5
const TOWER_RANGE := 11.5
const TOWER_HP := [0.0, 900.0, 1150.0, 1300.0, 1200.0]     # by tier (1000 / 1300 until 0.31.157; tiers 3 and 4 since 0.31.165)
# a lane minion's blow on a tower or a gate, by kind (0.31.157: x1.5 for all; 0.31.158 -- six to a wave now, and League's
# towers stand against a wave without heroes: a lone wave takes about a third of an outer tower, siege minions are
# the ones that hurt)
const MINION_TOWER := {"melee":0.4, "caster":0.4, "siege":1.6, "super":1.6}
# 0.31.158 (Kevin: "check tower mechanics to work like league of legends"), from League's wiki: 0.83 shots a second;
# targets by tier (pets, then siege / super minions, then melee, then casters, champions last; nearest within a tier)
# and stays on its target until it dies or leaves; call for help -- an enemy champion who hurts one of ours within
# 1400 (21.5 m here) of the tower, if it isn't already on a champion; "Warming Up": +50 % a shot on a champion, at most
# +150 %, gone 5 s after the last hit on one (a new target doesn't reset it); minions lose 45 / 70 / 14 / 5 % (melee /
# caster / siege / super) a shot; 80 % less damage taken with no enemy minions near; melee champions +20 % on towers;
# outer towers carry 5 plates (gold each) until 7:00 (League's 14:00); local gold for those near, global for all.
const TOWER_EVERY := 1.2                                    # (0.9 until 0.31.158)
const TOWER_FLIGHT := 0.3
const TOWER_HERO_DMG := 50.0                                # (40 at 0.9 s a shot until 0.31.158)
const TOWER_RAMP := 0.5
const TOWER_RAMP_MAX := 3
const TOWER_RAMP_COOL := 5.0
const TOWER_GROW := 0.04                                    # +4 % a minute
const TOWER_PCT := {"melee":0.45, "caster":0.7, "siege":0.14, "super":0.05, "pet":0.45, "lord":0.05}
const TOWER_PCT_ELSE := 0.7
const TOWER_HELP_R := 21.5                                  # League 1400
const BACKDOOR := 0.2                                       # (0.34 until 0.31.158; League's Reinforced Armor: -80 %)
const MELEE_VS_TOWER := 1.2
const PLATES := 5
const PLATES_UNTIL := 420.0                                 # 7:00
const GOLD_PLATE := 60                                      # to each hero of the side near (12 m) when a plate falls
const GOLD_TOWER_LOCAL := 200                               # shared by the side's heroes within 18 m (and the killing blow)
const GOLD_TOWER_GLOBAL := [0, 50, 25, 25, 25]              # every hero of the side, by tier (League's bounties: outer 50, the rest 25)
const GOLD_FIRST_TOWER := 150                               # the match's first tower: on top, for the local share
const TOWER_LOCAL_R := 18.0
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
const MATCH_5V5 := 1200.0                                   # 0.31.165: 20 minutes on the Rift (bot matches seldom took a lane's three
                                                            # towers, its gate and both King towers in 15). 0.31.157: 15 minutes (12 until then -- with the jungle, gold and
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
	# 0.31.168: the six new heroes (moba_kits.gd ult())
	"golem": {"name":"LANDSLIDE", "short":"SLIDE", "cd":75.0,
		"text":"Roll 9 m like an avalanche, flattening everyone in the way; where you stop the ground breaks -- enemies near stunned 1.5 s."},
	"dragoon": {"name":"DRAGON DIVE", "short":"DIVE", "cd":70.0,
		"text":"Leap high onto an enemy hero up to 11 m away and crash down: heavy damage and a 1 s stun round you."},
	"duelist": {"name":"GRAND CHALLENGE", "short":"DUEL", "cd":65.0,
		"text":"Five lightning strikes at the nearest enemy hero up to 8 m, from every side -- harder the more hurt he is."},
	"stormcaller": {"name":"THUNDERSTORM", "short":"STORM", "cd":75.0,
		"text":"A storm up to 13 m away: for 3.5 s bolts strike the enemies under it, each a short stun."},
	"musketeer": {"name":"QUICKDRAW", "short":"DRAW", "cd":70.0,
		"text":"Shoots every enemy hero you can see within 15 m -- up to five -- for double, more the more hurt they are."},
	"druid": {"name":"WILD GROWTH", "short":"GROVE", "cd":80.0,
		"text":"A grove round you for 5 s: allies in it heal 5 % of their health a second; enemies in it slowed and stung."},
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
const GOLD_MINION := {"melee":21, "caster":14, "siege":60, "super":60}     # League's (siege / super +3 every 90 s, at most 90)
const GOLD_HERO := 300
const GOLD_ASSIST := 150                                    # split between the helpers
# 0.31.180 (Kevin, League's rules): the kill goes to the last enemy hero to touch him within KILL_CREDIT s (a tower or
# a minion landing the blow included); an assist to each who hurt him or held him (a slow, a stun) in the last
# ASSIST_WINDOW s, or healed his killer then. Multi-kills: each within MULTI_GAP s of the last; after a QUADRA the
# PENTA may come within PENTA_GAP s, unless one of the enemy comes back first. Bounties: what a hero earns from kills
# and assists counts a quarter, from minions and monsters a twentieth; his killer is paid up to BOUNTY_MAX of it on
# top of GOLD_HERO (the rest carries over to his next life), less when his side is well behind in gold (DEVALUE_*);
# the board shows it from BOUNTY_SHOW, in steps of BOUNTY_STEP.
const KILL_CREDIT := 15.0
const MULTI_GAP := 10.0
const PENTA_GAP := 30.0
const MULTI_NAMES := ["", "", "DOUBLE KILL", "TRIPLE KILL", "QUADRA KILL", "PENTAKILL"]
const BOUNTY_KILL := 0.25
const BOUNTY_CS := 0.05
const BOUNTY_MAX := 700.0
const BOUNTY_SHOW := 150
const BOUNTY_STEP := 50
const DEVALUE_FROM := 0.10                                  # (a side this far behind in gold: its bounties count less --
const DEVALUE_FULL := 0.40                                  #  from 20 % there to 80 % this far behind)
const DEVALUE_MIN := 0.2
const DEVALUE_MAX := 0.8
const ASSIST_WINDOW := 10.0
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
	# 0.31.168: by hero where his class's list doesn't fit him -- the Golem a tank's, the Druid a support's
	"golem": ["boots", "ruby", "cloth", "thorn", "greaves", "sword", "fang", "bloodthirster", "bead", "titan"],
	"druid": ["tome", "boots", "bead", "relic", "greaves", "ruby", "cloth", "thorn"],
}

# ---------- 0.31.157: the jungle ----------
const JUNGLE := -2                                          # a hero's "lane": the jungler
const CAMP_FIRST := 30.0
const LORD_FIRST := 300.0                                   # the Bone Lord rises at 5:00
# blue's camps (red's are the point mirror). 0.31.165, the Rift: in each jungle quadrant of blue's half a Bone Pack near
# the river, a Grave Archers near the keep, and a buff camp in the middle -- the Arcane Wraith on the west, the Ember
# Brute on the east -- each in its pocket of ridges (siege_land.gd RIDGES_BLUE); the Bone Lord in the west pit.
# 0.31.216 (the Honor of Kings square): the same three in each quarter -- the Archers by the keep, the buff in the
# middle of the quarter, the Pack out by the river toward the side lane's corner.
const CAMPS_BLUE := [
	{"kind":"pack", "p":Vector2(-58.69, 16.26)},
	{"kind":"archers", "p":Vector2(-19.8, 48.08)},
	{"kind":"arcane", "p":Vector2(-32.53, 24.04)},
	{"kind":"pack", "p":Vector2(58.69, 16.26)},
	{"kind":"archers", "p":Vector2(19.8, 48.08)},
	{"kind":"ember", "p":Vector2(32.53, 24.04)},
]
const BOSS_P := Vector2(-Land.POOL_X, 0.0)                  # the west pit's island (Land.pit_c(0); the island until 0.31.165)
const CAMP_KINDS := {
	"pack": {"name":"Bone Pack", "mobs":[["warrior", Vector2(0, 0)], ["minion", Vector2(-1.7, 1.2)], ["minion", Vector2(1.7, 1.2)]], "respawn":75.0},
	"archers": {"name":"Grave Archers", "mobs":[["archer", Vector2(-1.3, 0)], ["archer", Vector2(1.3, 0)], ["minion", Vector2(0, 1.5)]], "respawn":75.0},
	"arcane": {"name":"Arcane Wraith", "mobs":[["wraith", Vector2(0, 0)], ["minion", Vector2(-1.8, 1.4)], ["minion", Vector2(1.8, 1.4)]], "respawn":120.0, "buff":"arcane"},
	"ember": {"name":"Ember Brute", "mobs":[["brute", Vector2(0, 0)], ["minion", Vector2(-1.8, 1.4)], ["minion", Vector2(1.8, 1.4)]], "respawn":120.0, "buff":"ember"},
	"lord": {"name":"Bone Lord", "mobs":[["lord", Vector2(0, 0)]], "respawn":180.0},
	"wyrm": {"name":"Grave Wyrm", "mobs":[["wyrm", Vector2(0, 0)]], "respawn":180.0},       # (WYRM_BACK)
}
const MONSTERS := {
	"minion": {"name":"Skeleton", "look":"skel_minion", "cls":"rogue", "hp":2.0, "dmg":0.6, "spd":0.85, "gold":20, "xp":18},
	"warrior": {"name":"Skeleton Warrior", "look":"skel_warrior", "cls":"barbarian", "hp":3.6, "dmg":0.6, "spd":0.8, "gold":45, "xp":40},
	"archer": {"name":"Skeleton Archer", "look":"skel_rogue", "cls":"ranger", "hp":2.4, "dmg":0.7, "spd":0.8, "gold":28, "xp":25},
	"wraith": {"name":"Arcane Wraith", "look":"skel_mage", "cls":"mage", "hp":7.0, "dmg":0.8, "spd":0.8, "gold":90, "xp":70, "scale":1.3},
	"brute": {"name":"Ember Brute", "look":"skel_brute", "cls":"barbarian", "hp":6.5, "dmg":0.85, "spd":0.8, "gold":90, "xp":70, "scale":1.35},
	"lord": {"name":"Bone Lord", "look":"skel_lord", "cls":"barbarian", "hp":26.0, "dmg":1.9, "spd":0.75, "gold":300, "xp":120, "scale":1.9},
	"wyrm": {"name":"Grave Wyrm", "look":"wyrm", "cls":"barbarian", "hp":14.0, "dmg":0.8, "spd":0.7, "gold":150, "xp":80, "scale":1.8},
}
const MON_GROW := 0.05                                      # a monster comes back 5 % stronger for every minute played
const LEASH := 9.0
const LORD_LEASH := 8.0
const RESET_HEAL := 0.3                                     # (0.31.157's heal the moment it was left alone; unused now)
# 0.31.158 (Kevin: "the enemy camps seem to recharge health immediately if you get too far away"), League's leash: a
# camp's patience drains while its target is outside the leash (faster the farther), and it keeps fighting while it
# lasts; at zero, a soft reset -- 6 s walking home healing 6 %/s, ignoring attackers outside the leash (a hit from
# inside ends it and gives some patience back) -- then a hard reset: home, ignoring everyone, healing 15 %/s.
const PATIENCE_DRAIN := 0.3                                 # a second, just outside the leash
const PATIENCE_FAR := 0.08                                  # + this per metre farther out
const PATIENCE_BACK := 0.25                                 # a second, while the target's inside
const SOFT_RESET := 6.0
const SOFT_HEAL := 0.06
const HARD_HEAL := 0.15
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
const SUPER_MINION := 1.5                                   # (0.31.157's super minions; 0.31.158: a super minion of its own)
const LORD_SIEGE := 3.0                                     # 0.31.158: the Bone Lord marching for a side hits towers and gates x3
const LORDLING_HP := 12.0                                   # (x the Barbarian's 130, +5 % a minute played)
const LORDLING_DMG := 1.4
const BUFF_NAMES := {"arcane":"ARCANE", "ember":"EMBER", "lord":"LORD'S BLESSING"}
# ---------- 0.31.166: the Grave Wyrm (step 3 of the new map; Kevin picked concept A) ----------
# A skeletal dragon in the Rift's east pit, the Bone Lord's opposite. Up at 3:00, back WYRM_BACK s after it falls. Each
# kill gives the slaying side a stack of WYRM'S HIDE for the rest of the match: +WYRM_HIDE max health for every one of
# its heroes, at most WYRM_STACKS. Besides its bite, every WYRM_BREATH_EVERY s it breathes soul-fire in a cone at
# whoever it's fighting. Gold and XP to every hero of the side; it counts as an epic monster (the challenges, "epics").
# A side's bots go for it when it's up and they have the edge (_epic_call), gathering WYRM_GATHER at the pit's rim first.
# Tuned on whole bot matches: with health 14 and damage 0.8 (a buff monster's; the Lord's 26 and 1.9), the bots take it
# three or four times a match, the first at about 4:30-7:00 (at 20 and 1.5, one at 14-17 min).
const WYRM_P := Vector2(Land.POOL_X, 0.0)                    # the east pit's island (Land.pit_c(1))
const WYRM_FIRST := 180.0
const WYRM_BACK := 180.0
const WYRM_HIDE := 0.06
const WYRM_STACKS := 4
const WYRM_BREATH_EVERY := 6.0
const WYRM_BREATH_R := 6.5
const WYRM_BREATH_ARC := 0.6                                 # half the cone's angle (radians)
const WYRM_BREATH_DMG := 1.0                                 # x its damage, to everyone in the cone
const WYRM_LEASH := 12.0                                     # (wider than the Lord's 8: a ranged hero shoots it from the pit's rim)
const WYRM_GATHER := 3                                       # bots wait at the rim till this many of theirs are there

const Vision = preload("res://scripts/siege/moba_vision.gd")
const Kits = preload("res://scripts/siege/moba_kits.gd")      # 0.31.167: roles, W and E
var s                                     # the sim
var kits = null                           # 0.31.167: the heroes' W and E, and what they leave on units
var vision = null                         # 0.31.158: the fog of war (moba_vision.gd)
var rng := RandomNumberGenerator.new()
var towers: Array = []                    # {id, team, lane, tier, p, hp, max_hp, dead, target, ramp, ramp_id, next}
var shots: Array = []                     # {tw, target, t, dmg}
var wave_at := WAVE_FIRST
var waves := 0
var _mid := 0
var heroes: Array = [[], []]              # unit ids
var hero_of := {}                         # unit id -> hero id
var _immune_note := -10.0
var _far_note := -10.0                   # (0.31.179: "out of the tower's range", once in a while)
var kings: Array = [{}, {}]               # per side: {hp, max_hp, dead, next, quiet}
var camps: Array = []                     # 0.31.157: {id, kind, side (0/1, -1 the Lord), p, mobs, alive, next, target, hits}
var rains: Array = []                     # ARROW RAIN in progress: {team, owner, at, r, left, next, dmg}
var boss_go := [false, false]             # a side's bots are going for the Bone Lord
var wyrm_go := [false, false]             # 0.31.166: ...for the Grave Wyrm
var wyrm_stacks := [0, 0]                 # 0.31.166: each side's WYRM'S HIDE
var first_blood := false                 # 0.31.180: the match's first hero kill made
var last_respawn := [-INF, -INF]          # 0.31.180: when a hero of each side last came back (a PENTA's window ends)
var epic_kills := {"lord": [0, 0], "wyrm": [0, 0]}   # 0.31.176: each side's Bone Lords and Grave Wyrms slain (the scoreboard)
# 0.31.177 (Kevin: "Put the player names above the players so people know if it's player or minion easier. If it's a
# bot then give bot name like "bot Alfred""): each seat's bot's name, "Bot Alfred" over its head while a bot plays it
const BOT_NAMES := ["Alfred", "Bertram", "Cedric", "Dorian", "Edmund", "Felix", "Gideon", "Harold", "Ivo", "Jasper",
	"Kendrick", "Leopold", "Magnus", "Nigel", "Osric", "Percival", "Quentin", "Roland", "Sigmund", "Tobias", "Ulric",
	"Victor", "Wendell", "Yorick", "Ada", "Beatrix", "Clara", "Delia", "Edith", "Freya", "Greta", "Hilda", "Isolde",
	"Juno", "Lena", "Mira", "Nora", "Petra", "Rosa", "Sybil", "Tessa", "Vera", "Wren"]

static func bot_label(u: Dictionary) -> String:
	# "Bot Alfred": the seat's own name (an older server's units have none: one from the seat's id, the same on every phone)
	var n := str(u.get("bot_name", ""))
	if n == "":
		n = str(BOT_NAMES[absi(hash(str(u.get("id", "")))) % BOT_NAMES.size()])
	return "Bot " + n
var _boss_check := 0.0
var _jid := 0
var _zid := 0
var _shop_clock := 0.0

# 0.31.160 (Kevin's phone log: the 5v5's sim 20-35 ms a frame): the units by GRID-m cell, for the scans that only want
# what's near a point (a minion's or a tower's or a hero's targets) instead of all 60+ units, each, every time. Rebuilt
# when the tick or the unit count changes; a unit moves well under GRID_PAD within a tick, so a query reaches that much
# further and the caller still checks the real distance.
const GRID := 8.0
const GRID_PAD := 1.0
var _grid := {}
var _grid_time := -1.0
var _grid_n := -1

func units_near(p: Vector2, r: float) -> Array:
	if s.time != _grid_time or s.units.size() != _grid_n:
		_grid_time = s.time
		_grid_n = s.units.size()
		_grid.clear()
		for u in s.units:
			var up: Vector2 = u.pos
			var c := Vector2i(floori(up.x / GRID), floori(up.y / GRID))
			var cell = _grid.get(c)
			if cell == null:
				_grid[c] = [u]
			else:
				(cell as Array).append(u)
	var rr := r + GRID_PAD
	var x0 := floori((p.x - rr) / GRID)
	var x1 := floori((p.x + rr) / GRID)
	var y0 := floori((p.y - rr) / GRID)
	var y1 := floori((p.y + rr) / GRID)
	if x0 == x1 and y0 == y1:
		return _grid.get(Vector2i(x0, y0), [])
	var out := []
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			var cell = _grid.get(Vector2i(cx, cy))
			if cell != null:
				out.append_array(cell)
	return out

# ---------- setup ----------
func begin(sim, my_hero: String, seed_value: int) -> void:
	s = sim
	rng.seed = seed_value
	kits = Kits.new()
	kits.setup(self)
	s.match_time = MATCH_5V5
	for b in TOWERS_BLUE:
		_add_tower(0, int(b[0]), int(b[1]), b[2])
	for b in TOWERS_BLUE:
		_add_tower(1, 2 - int(b[0]) if int(b[0]) >= 0 else -1, int(b[1]), -(b[2] as Vector2))
	for g in s.gates:                     # 0.31.157: the gates (League's inhibitors) a little easier to break
		g.hp = GATE_HP_5V5
		g.max_hp = GATE_HP_5V5
	s.open_gates = true                   # 0.31.217 (Honor of Kings): the gates stand open -- the King is the crystal
	s._update_gate_nav()
	for t in 2:                           # the Kings, home on their thrones: the hearts
		var o: Dictionary = s.oracles[t]
		o.state = "home"
		o.pos = s.throne(t)
		kings[t] = {"hp":KING_HP, "max_hp":KING_HP, "dead":false, "next":0.0, "quiet":0.0}
		s.obstacles.append({"p":o.pos, "r":KING_R, "kind":"moba_king", "kg":t, "team":t})
	s._build_buckets()
	s._build_nav()                        # (the towers block the way and stop arrows)
	# the heroes: yours, then the bots' (no two the same on a side). 0.31.167 (League's roles): each side a team --
	# top (a fighter or a tank), jungle (an assassin or a fighter), mid (a mage or an assassin), bottom (a marksman) and
	# its support (a support or a tank) in the same lane; you take your role's place (your own lane is yours to choose),
	# the bots fill the rest; the top and mid bots are the side's King runners
	# 0.31.170: my_hero "" (the server's match: every seat a bot until a player takes it) -- both sides drafted alike, each
	# bot in its own place's lane (blue's first was a Knight with no lane, as if a player had him)
	for t in 2:
		var mine := ((my_hero if HEROES.has(my_hero) else "knight") if my_hero != "" else "") if t == 0 else ""
		var team := draft(mine)
		var i := 0
		for u in s.units:
			if int(u.team) != t or i >= team.size():
				continue
			var pk: Array = team[i]
			var post := str(pk[1])
			_make_hero(u, str(pk[0]), -1 if (t == 0 and i == 0 and mine != "") else int(POST_LANE[post]), post in ["top", "mid"])
			u["post"] = post
			i += 1
	# 0.31.177: every seat a bot's name, ten different ones a match -- from a generator of their own, so the match's own
	# draws (the drafts, the bots' choices) stay as they were
	var nr := RandomNumberGenerator.new()
	nr.seed = seed_value * 7919 + 13
	var pool: Array = BOT_NAMES.duplicate()
	for hid in heroes[0] + heroes[1]:
		var k := nr.randi_range(0, pool.size() - 1)
		s.by_id[hid]["bot_name"] = str(pool[k])
		pool.remove_at(k)
	vision = Vision.new()                 # 0.31.158: the fog of war
	vision.setup(self)
	# the jungle (0.31.157): each side's four camps (red's the point mirror of blue's), the Bone Lord on the island
	for t in 2:
		for c in CAMPS_BLUE:
			_add_camp(str(c.kind), t, c.p if t == 0 else -(c.p as Vector2))
	_add_camp("lord", -1, BOSS_P)
	_add_camp("wyrm", -1, WYRM_P)                       # 0.31.166: the Grave Wyrm in the east pit

func _add_tower(team: int, lane: int, tier: int, p: Vector2) -> void:
	var id := towers.size()
	towers.append({"id":id, "team":team, "lane":lane, "tier":tier, "p":p, "hp":TOWER_HP[tier], "max_hp":TOWER_HP[tier],
		"dead":false, "target":"", "ramp":0, "ramp_id":"", "next":0.0})
	s.obstacles.append({"p":p, "r":TOWER_R, "kind":"moba_tower", "tw":id, "team":team})

# 0.31.167: a side's five places (League's) -- the lane each plays, the roles that fill it (first choice first), and the
# place a role takes when it's yours
const POSTS := ["top", "jungle", "mid", "bot", "support"]
const POST_LANE := {"top":0, "jungle":JUNGLE, "mid":1, "bot":2, "support":2}
const POST_ROLES := {"top":["fighter", "tank"], "jungle":["assassin", "fighter"], "mid":["mage", "assassin"], "bot":["marksman"],
	"support":["support", "tank"]}
const ROLE_POST := {"tank":"top", "fighter":"top", "assassin":"jungle", "mage":"mid", "marksman":"bot", "support":"support"}

func draft(mine: String) -> Array:
	# a side's five [hero, place]: yours first (if you play on it), then the bots' -- the specialised places filled first
	var out := []
	var taken := []
	var open: Array = POSTS.duplicate()
	if mine != "":
		var mp := str(ROLE_POST.get(Kits.role_of(mine), "top"))
		out.append([mine, mp])
		taken.append(mine)
		open.erase(mp)
	for post in ["bot", "support", "mid", "jungle", "top"]:
		if not open.has(post):
			continue
		var hid := ""
		for role in POST_ROLES[post]:
			var c: Array = HERO_ORDER.filter(func(h): return not taken.has(h) and Kits.role_of(str(h)) == str(role))
			if not c.is_empty():
				hid = str(c[rng.randi_range(0, c.size() - 1)])
				break
		if hid == "":
			var any: Array = HERO_ORDER.filter(func(h): return not taken.has(h))
			hid = str(any[rng.randi_range(0, any.size() - 1)])
		taken.append(hid)
		out.append([hid, post])
	# in the side's own order: top, jungle, mid, bottom, support (yours stays first)
	var head: Array = out.slice(0, 1) if mine != "" else []
	var rest: Array = out.slice(head.size())
	rest.sort_custom(func(a, b): return POSTS.find(str(a[1])) < POSTS.find(str(b[1])))
	return head + rest

func _make_hero(u: Dictionary, hid: String, lane: int, king_runner: bool) -> void:
	var h: Dictionary = HEROES[hid]
	u.cls = str(h.cls)
	u.up = bool(h.up)
	u["hero"] = true
	u["hid"] = hid
	if Kits.kit_q(hid) != "":
		u["kq"] = Kits.kit_q(hid)                  # 0.31.168: his Q is a kit spell (siege_sim.ability_of)
		u["look"] = hid                            # his own body (siege_view.look_key)
	if HERO_SHOT.has(hid):
		u["shot"] = str(HERO_SHOT[hid])            # his basic attack's shot (siege_sim._shoot)
	if HERO_SCALE.has(hid):
		u["mscale"] = float(HERO_SCALE[hid])
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
	heroes[int(u.team)].append(u.id)
	hero_of[u.id] = hid
	_apply(u)
	s._respawn(u, true)

func swap_hero(u: Dictionary, hid: String) -> void:
	# 0.31.170 (online): a player takes this seat as their own hero -- its place, level, gold, items and upgrades stay
	if not HEROES.has(hid) or str(u.get("hid", "")) == hid:
		return
	var ratio: float = float(u.hp) / maxf(1.0, float(u.max_hp))
	var h: Dictionary = HEROES[hid]
	u.cls = str(h.cls)
	u.up = bool(h.up)
	u["hid"] = hid
	for k in ["kq", "look", "shot", "mscale"]:
		u.erase(k)
	if Kits.kit_q(hid) != "":
		u["kq"] = Kits.kit_q(hid)
		u["look"] = hid
	if HERO_SHOT.has(hid):
		u["shot"] = str(HERO_SHOT[hid])
	if HERO_SCALE.has(hid):
		u["mscale"] = float(HERO_SCALE[hid])
	u.cd_ability = 0.0
	u["cd_w"] = 0.0
	u["cd_e"] = 0.0
	hero_of[u.id] = hid
	var offers: Array = u.get("picks", [])
	for i in offers.size():
		offers[i] = _offer(u)                      # (the offers made for the old class: a Priest's leave out damage)
	_apply(u)
	if s.alive(u):
		u.hp = maxf(1.0, float(u.max_hp) * ratio)

# ---------- stats ----------
func stat(u: Dictionary, key: String, base: Variant) -> Variant:
	var hb: Dictionary = HERO_BASE.get(str(u.get("hid", "")), {})
	if hb.has(key):
		base = hb[key]                             # 0.31.168: the new heroes' own numbers
	match key:
		"hp":
			return float(base) * (1.15 if u.up else 1.0) * float(u.get("m_hp", 1.0))
		"dmg":
			return float(base) * (1.1 if u.up else 1.0) * float(u.get("m_dmg", 1.0))
		"speed":
			return float(base) * float(u.get("m_spd", 1.0)) * (WARCRY_SPD if s.time < float(u.get("bl_until", -1.0)) else 1.0) \
				* (kits.speed_mult(u) if kits != null else 1.0)               # 0.31.167: slows and hastes
		"windup", "recover":
			return float(base) * float(u.get("m_as", 1.0)) * (WARCRY_AS if s.time < float(u.get("bl_until", -1.0)) else 1.0) \
				* (kits.swing_mult(u) if kits != null else 1.0)               # 0.31.167: FRENZY
	return base

func _apply(u: Dictionary) -> void:
	# the multipliers stat() reads, from the level and the upgrades picked
	var ups: Dictionary = u.get("ups", {})
	var lv := float(int(u.get("level", 1)) - 1)
	var before: float = float(u.get("max_hp", 0.0))
	var it := item_stats(u)                   # 0.31.157: what the items add
	u["m_hp"] = HERO_HP * (1.0 + LEVEL_GROW * lv) * (1.0 + 0.15 * float(ups.get("hp", 0))) * (1.0 + float(it.get("hp", 0.0))) \
		* (1.0 + WYRM_HIDE * float(wyrm_stacks[clampi(int(u.team), 0, 1)]))      # 0.31.166: the side's WYRM'S HIDE
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
		wave_at += WAVE_EVERY if s.time < MID_AT else (WAVE_EVERY_MID if s.time < LATE_AT else WAVE_EVERY_LATE)
		waves += 1
		for t in 2:
			for l in 3:
				_spawn_wave(t, l)
	var tv := Time.get_ticks_usec() if s.profile else 0
	_step_towers(dt)
	if s.profile: tv = s._p("m.towers", tv)
	_step_kings(dt)
	if s.profile: tv = s._p("m.kings", tv)
	_step_camps(dt)
	if s.profile: tv = s._p("m.camps", tv)
	_step_rains(dt)
	kits.step(dt)                                      # 0.31.167: zones, traps, poison
	vision.step(dt)
	if s.profile: tv = s._p("vision", tv)
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
			var cdk := dt * float(u.get("m_cdr", 1.0)) * (ARCANE_CDR if arcane else 1.0)     # 0.31.167: W and E
			if float(u.get("cd_w", 0.0)) > 0.0:
				u.cd_w = maxf(0.0, float(u.cd_w) - cdk)
			if float(u.get("cd_e", 0.0)) > 0.0:
				u.cd_e = maxf(0.0, float(u.cd_e) - cdk)
			if gold_on:
				u.gold = float(u.gold) + GOLD_PASSIVE * dt
			if u.has("dance"):
				_step_dance(u)
		elif bool(u.get("summon", false)) and s.time >= float(u.get("expire", INF)):
			s._kill({}, u)                                        # the Necromancer's skeletons crumble
	for u in gone:
		s.units.erase(u)
		s.by_id.erase(u.id)
	if s.profile: tv = s._p("m.units", tv)
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

func wave_kinds(t: int, l: int, n: int) -> Array:
	# League's wave n (1-based) in lane l for side t, front to back: super(s), melee, siege, casters
	var sup := 0
	if _lane_gate_down(t, l):                       # (0.31.217: the lane's third enemy tower down -- its gate until then)
		sup = 2 if _gates_down(1 - t) >= 2 else 1
	var siege := false
	if sup == 0:
		siege = (n % 3 == 0) if s.time < MID_AT else ((n % 2 == 0) if s.time < LATE_AT else true)
	var out := []
	for i in sup:
		out.append("super")
	for i in (2 if siege and s.time >= MID_AT else 3):
		out.append("melee")
	if siege:
		out.append("siege")
	for i in 3:
		out.append("caster")
	return out

func _gates_down(team: int) -> int:
	# 0.31.217: how many of this side's lanes are broken -- their third tower down (the gates stand open now; until then
	# the gates broken)
	var n := 0
	for tw in towers:
		if int(tw.team) == team and int(tw.tier) == 3 and bool(tw.dead):
			n += 1
	return n

func _spawn_wave(t: int, l: int) -> void:
	var alive := 0
	for u in s.units:
		if bool(u.get("minion", false)) and not bool(u.get("summon", false)) and int(u.team) == t and s.alive(u):
			alive += 1
	var lord := lord_buff(t)                   # 0.31.157: the Bone Lord's blessing on this side -- stronger minions
	var up := 1.0 + MINION_UP * floorf(float(s.time) / MINION_UP_EVERY)
	var kinds := wave_kinds(t, l, waves)
	var start := wp(t, l, 0)
	var ahead := (wp(t, l, 1) - start).normalized()
	var side := Vector2(-ahead.y, ahead.x)
	var rows := int(ceil(float(kinds.size()) / 2.0))
	var ids := []
	for k in kinds.size():
		if alive >= MINION_CAP:
			break
		alive += 1
		var u := _new_minion(t, l, str(kinds[k]), up, lord)
		u["wp"] = 1
		# in pairs from the gate out, the front first (behind the gate is the castle wall)
		var row := k / 2
		var col := k % 2
		u.pos = start + ahead * (1.3 * float(rows - 1 - row) + 0.5) + side * (0.8 if col == 0 else -0.8)
		u.face = s.angle_of(ahead)
		u.think_at = s.time + s.TICK * float(k + 1)
		s.units.append(u)
		s.by_id[u.id] = u
		ids.append(u.id)
	if not ids.is_empty():
		s._event("wave", {"team":t, "lane":l, "ids":ids})

func _new_minion(t: int, l: int, mk: String, up: float, lord: bool) -> Dictionary:
	# a lane minion of kind mk (not yet placed nor in the match)
	_mid += 1
	var u: Dictionary = s._new_unit("m%d" % _mid, t, true)
	u.cls = str(MINION_CLS[mk])
	u["minion"] = true
	u["mk"] = mk
	u["lane"] = l
	u["m_hp"] = float(MINION_KIND_HP[mk]) * up * (LORD_MINION if lord else 1.0)
	u["m_dmg"] = float(MINION_KIND_DMG[mk]) * up * (LORD_MINION if lord else 1.0)
	u["m_spd"] = MINION_SPD
	if mk == "super":
		u["super"] = true
	if MINION_KIND_SCALE.has(mk):
		u["mscale"] = float(MINION_KIND_SCALE[mk])     # (siege and super minions stand a little bigger)
	if lord:
		u["lordly"] = true
	u.max_hp = float(s.stat(u, "hp"))
	u.hp = u.max_hp
	return u

func place_minions(t: int, l: int, kinds: Array, at: Vector2) -> Array:
	# 0.31.181 (the tutorial's "delivered" wave): minions of side t put down at `at` on lane l, two abreast, walking on
	# down it from the next of its points ahead of them
	var up := 1.0 + MINION_UP * floorf(float(s.time) / MINION_UP_EVERY)
	var fwd := _forward({"team":t})
	var wi := lane_len(l) - 1
	for i in lane_len(l):
		if (wp(t, l, i) - at).dot(fwd) > 1.0:
			wi = i
			break
	var ahead := (wp(t, l, wi) - at).normalized()
	var side := Vector2(-ahead.y, ahead.x)
	var ids := []
	for k in kinds.size():
		var u := _new_minion(t, l, str(kinds[k]), up, false)
		u["wp"] = wi
		u.pos = at - ahead * (1.3 * float(k / 2)) + side * (0.8 if k % 2 == 0 else -0.8)
		u.face = s.angle_of(ahead)
		u.think_at = s.time + s.TICK * float(k + 1)
		s.units.append(u)
		s.by_id[u.id] = u
		ids.append(u.id)
	if not ids.is_empty():
		s._event("wave", {"team":t, "lane":l, "ids":ids})
	return ids

func _lane_gate_down(t: int, l: int) -> bool:
	# team t's lane l is broken: the enemy's third tower in it down (0.31.217; the enemy gate at its end until then)
	for tw in towers:
		if int(tw.team) == 1 - t and int(tw.lane) == l and int(tw.tier) == 3 and bool(tw.dead):
			return true
	return false

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
	# a keep's gate can be hit once the third tower of the lane that ends at it is down (0.31.165: its tier 3; the inner
	# tower, tier 2, on the Siege field)
	for l in 3:
		var end := wp(1 - int(g.team), l, lane_len(l) - 1)        # where the attackers' track ends: at this castle
		if end.distance_to(g.c) > 6.0:
			continue
		for tw in towers:
			if int(tw.team) == int(g.team) and int(tw.lane) == l and int(tw.tier) == 3 and bool(tw.dead):
				return true
	return false

func _tower_tier(o: Dictionary) -> int:
	# who a tower shoots first (League): pets, siege / super minions, melee, casters, champions
	if bool(o.get("summon", false)):
		return 0
	if bool(o.get("minion", false)):
		match str(o.get("mk", "melee")):
			"siege", "super", "lord": return 1
			"caster": return 3
			_: return 2
	return 4

func _tower_pct(o: Dictionary) -> float:
	if bool(o.get("summon", false)):
		return float(TOWER_PCT.pet)
	return float(TOWER_PCT.get(str(o.get("mk", "melee")), TOWER_PCT_ELSE))

func _step_towers(dt: float) -> void:
	for tw in towers:
		if bool(tw.dead):
			continue
		var cur: Dictionary = s.by_id.get(str(tw.target), {})
		if cur.is_empty() or not s.alive(cur) or (cur.pos as Vector2).distance_to(tw.p) > TOWER_RANGE + s.UNIT_R:
			cur = {}
		# call for help: an enemy champion in range who hurt one of our champions within TOWER_HELP_R just now (unless
		# it's already on a champion)
		if cur.is_empty() or not bool(cur.get("hero", false)):
			for hid in heroes[int(tw.team)]:
				var h: Dictionary = s.by_id.get(hid, {})
				if h.is_empty() or not s.alive(h) or s.time - float(h.get("hh_at", -99.0)) > HELP_FOR or (h.pos as Vector2).distance_to(tw.p) > TOWER_HELP_R:
					continue
				var a: Dictionary = s.by_id.get(str(h.get("hh_by", "")), {})
				if not a.is_empty() and s.alive(a) and (a.pos as Vector2).distance_to(tw.p) <= TOWER_RANGE + s.UNIT_R:
					cur = a
					break
		if cur.is_empty():
			var best := {}
			var bt := 9
			var bd := INF
			for o in units_near(tw.p, TOWER_RANGE + s.UNIT_R):
				if int(o.team) == int(tw.team) or int(o.team) > 1 or not s.alive(o):
					continue
				var d: float = (o.pos as Vector2).distance_to(tw.p)
				if d > TOWER_RANGE + s.UNIT_R:
					continue
				var tier := _tower_tier(o)
				if tier < bt or (tier == bt and d < bd):
					bt = tier
					bd = d
					best = o
			cur = best
		tw.target = str(cur.get("id", ""))
		if s.time - float(tw.get("ramp_at", -99.0)) > TOWER_RAMP_COOL:
			tw.ramp = 0                                # (Warming Up cools off 5 s after the last hit on a champion)
		if cur.is_empty() or s.time < float(tw.next):
			continue
		tw.next = s.time + TOWER_EVERY
		var dmg := 0.0
		var ramp := 0
		if bool(cur.get("hero", false)):
			ramp = int(tw.ramp)
			dmg = TOWER_HERO_DMG * (1.0 + TOWER_RAMP * float(ramp)) * (1.0 + TOWER_GROW * s.time / 60.0)
			tw.ramp = mini(ramp + 1, TOWER_RAMP_MAX)
			tw["ramp_at"] = s.time + TOWER_FLIGHT
		else:
			dmg = float(cur.max_hp) * _tower_pct(cur)
		shots.append({"tw":int(tw.id), "target":str(cur.id), "t":TOWER_FLIGHT, "dmg":dmg})
		s._event("tshot", {"tw":int(tw.id), "id":str(cur.id), "flight":TOWER_FLIGHT, "ramp":ramp})
	for i in range(shots.size() - 1, -1, -1):
		var sh: Dictionary = shots[i]
		sh.t = float(sh.t) - dt
		if float(sh.t) > 0.0:
			continue
		shots.remove_at(i)
		var tw2: Dictionary = towers[int(sh.tw)]
		if bool(tw2.dead):
			continue                                   # (League: a shot is wasted if its tower falls in flight)
		var u: Dictionary = s.by_id.get(str(sh.target), {})
		if not u.is_empty() and s.alive(u):
			s._next_push = Vector3.ZERO
			s._damage({"id":"tower%d" % int(tw2.id), "team":int(tw2.team), "pos":tw2.p, "state":"idle"}, u, float(sh.dmg))

func tower_mult(src: Dictionary) -> float:
	# a blow on a tower: melee champions +20 % (League), lane minions MINION_TOWER by kind, the Bone Lord marching for a
	# side LORD_SIEGE
	if bool(src.get("hero", false)) and not bool(s.CLASSES.get(str(src.get("cls", "")), {}).get("ranged", false)):
		return MELEE_VS_TOWER
	if bool(src.get("lordling", false)):
		return LORD_SIEGE
	if lane_minion(str(src.get("id", ""))):
		return float(MINION_TOWER.get(str(src.get("mk", "melee")), 0.4))
	return 1.0

func hit_tower(src: Dictionary, id: int, amount: float, from := Vector2.INF) -> void:
	# a basic attack's hit on a tower (0.31.179: only basic attacks reach this -- siege_sim._melee and a basic shot's
	# impact -- and, given where it was struck from, only from inside the tower's own range)
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
	if from != Vector2.INF and not in_tower_range(tw, from):
		# 0.31.179 (Kevin: "make sure only basic attacks damage towers and that they only damage while inside the towers
		# damage range"): out of its reach (where it would shoot you) a tower isn't hurt -- no sniping it from outside
		if s.time - _far_note > 1.5 and not bool(src.get("bot", true)):
			_far_note = s.time
			s._event("tower_far", {"tw":id, "team":int(tw.team), "by":str(src.get("id", ""))})
		return
	var minions_near := false
	for o in units_near(tw.p, TOWER_RANGE):
		if bool(o.get("minion", false)) and int(o.team) == int(src.team) and s.alive(o) and (o.pos as Vector2).distance_to(tw.p) <= TOWER_RANGE:
			minions_near = true
			break
	if not minions_near:
		amount *= BACKDOOR                      # no minions with you: the tower barely feels it (League: -80 %)
	amount *= tower_mult(src)
	var before := float(tw.hp)
	tw.hp = maxf(0.0, float(tw.hp) - amount)
	if src.has("gate_dmg"):
		src.gate_dmg = float(src.gate_dmg) + minf(amount, before)     # (0.31.164: towers count as gate damage -- "gates")
	s._event("tower_hit", {"tw":id, "dmg":int(round(amount)), "by":str(src.get("id", ""))})     # (0.31.177: who, for the hit's look)
	# outer towers' plates (until 7:00): each fifth of its health that falls pays the side's heroes near
	if int(tw.tier) == 1 and s.time < PLATES_UNTIL and float(tw.hp) > 0.0:
		var step := float(tw.max_hp) / float(PLATES)
		var lost := int(floor((float(tw.max_hp) - float(tw.hp)) / step)) - int(floor((float(tw.max_hp) - before) / step))
		for k in lost:
			tw["plates"] = int(tw.get("plates", 0)) + 1
			var paid := []
			for h in _heroes_near(1 - int(tw.team), tw.p, 12.0, src):
				add_gold(h, GOLD_PLATE, tw.p)
				paid.append(str(h.id))
			s._event("plate", {"tw":id, "team":int(tw.team), "n":int(tw.plates), "ids":paid, "gold":GOLD_PLATE})
	if float(tw.hp) <= 0.0:
		tw.dead = true
		tw.target = ""
		s._event("tower_down", {"tw":id, "team":int(tw.team), "lane":int(tw.lane), "tier":int(tw.tier), "by":str(src.get("id", ""))})
		var et := 1 - int(tw.team)
		var first := towers_down(0) + towers_down(1) == 1
		for hid in heroes[et]:
			add_xp(s.by_id.get(hid, {}), TOWER_XP)
			add_gold(s.by_id.get(hid, {}), float(GOLD_TOWER_GLOBAL[int(tw.tier)]), Vector2.INF)     # global
		var near := _heroes_near(et, tw.p, TOWER_LOCAL_R, src)
		for h in near:
			add_gold(h, float(GOLD_TOWER_LOCAL + (GOLD_FIRST_TOWER if first else 0)) / float(near.size()), tw.p)      # local
			h["towers"] = int(h.get("towers", 0)) + 1     # (0.31.164: a tower destroyed -- by you or near you)
		s._update_gate_nav()

func _heroes_near(team: int, p: Vector2, r: float, src: Dictionary) -> Array:
	# the side's heroes standing within r of p, and whoever's blow it was (wherever he is)
	var out := []
	var by_h := _credit(src)
	if not by_h.is_empty() and int(by_h.team) == team:
		out.append(by_h)
	for hid in heroes[team]:
		var h: Dictionary = s.by_id.get(hid, {})
		if not h.is_empty() and not out.has(h) and s.alive(h) and (h.pos as Vector2).distance_to(p) <= r:
			out.append(h)
	return out

func aim_structure(u: Dictionary, reach: float) -> Dictionary:
	# 0.31.177 (Kevin: "towers aren't targetable"): the enemy tower, King or gate a player's attack can turn to -- one that
	# can be hurt now (a tower once the one before it fell; the King once his towers are down; a gate once its lane's
	# third tower is), within reach of its edge -- scored as siege_sim.nearest_enemy scores a unit (distance, plus up to
	# 2 m for being off to the side or behind): {"p", "d", "score"}, or {} for none
	var best := {}
	var fwd: Vector2 = s.dir_of(u.face)
	var cands := []
	for tw in towers:
		if int(tw.team) != int(u.team) and vulnerable(tw) and in_tower_range(tw, u.pos):     # (0.31.179: one you can hurt from here)
			cands.append([tw.p, TOWER_R])
	var et := 1 - int(u.team)
	if et >= 0 and et <= 1 and not bool(kings[et].dead) and king_open(et):
		cands.append([king_pos(et), KING_R])
	for g in s.gates:
		if int(g.team) != int(u.team) and s.gate_blocks(g) and gate_open(g):
			cands.append([s.seg_closest(u.pos, g.a, g.b), 0.0])
	for c in cands:
		var off: Vector2 = (c[0] as Vector2) - (u.pos as Vector2)
		var d := off.length()
		var edge := d - float(c[1])
		if edge > reach:
			continue
		var sc := maxf(0.0, edge)
		if d > 0.01:
			sc += (1.0 - fwd.dot(off / d)) * 2.0
		if best.is_empty() or sc < float(best.score):
			best = {"p": c[0], "d": d, "score": sc}
	return best

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
		hit_tower(u, int(tw.id), dmg, u.pos)
		hits += 1
	var t2 := 1 - int(u.team)
	var off2: Vector2 = king_pos(t2) - (u.pos as Vector2)
	var d2 := off2.length()
	if not bool(kings[t2].dead) and d2 - KING_R <= reach + 0.3 and (arc <= -1.0 or d2 < 0.3 or fwd.dot(off2 / d2) >= arc - 0.3):
		hit_king(u, t2, dmg)
		hits += 1
	return hits

func in_tower_range(tw: Dictionary, p: Vector2) -> bool:
	# where a tower can shoot you (as _step_towers picks its target: its range, to the edge of you)
	return p.distance_to(tw.p) <= TOWER_RANGE + s.UNIT_R

func tower_in_range(team_of_tower: int, p: Vector2, extra := 0.0) -> Dictionary:
	for tw in towers:
		if int(tw.team) == team_of_tower and not bool(tw.dead) and p.distance_to(tw.p) <= TOWER_RANGE + extra:
			return tw
	return {}

# ---------- the Kings, the hearts (0.31.156) ----------
func king_pos(t: int) -> Vector2:
	return s.oracles[t].pos

func king_open(t: int) -> bool:
	# 0.31.217 (Honor of Kings' crystal): hittable once one of his lanes is broken -- its third tower down (both King
	# towers of his keep until then, 0.31.165; before that once a gate of his castle was)
	if bool(kings[t].dead):
		return false
	return _gates_down(t) > 0


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
	var kp := king_pos(t)
	for o in units_near(kp, KING_GUARD):
		if int(o.team) != t and int(o.team) <= 1 and s.alive(o):
			var d: float = (o.pos as Vector2).distance_to(kp)
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
	if src.has("gate_dmg"):
		src.gate_dmg = float(src.gate_dmg) + minf(amount, float(k.hp))     # (0.31.164: the King too)
	k.hp = maxf(0.0, float(k.hp) - amount)
	k.quiet = 0.0
	s._event("king_hit", {"team":t, "dmg":int(round(amount))})
	if float(k.hp) <= 0.0:
		k.dead = true
		s.score[1 - t] += 1
		s._event("king_down", {"team":t, "by":str(src.get("id", ""))})
		s._finish("king")

# 0.31.179 (Kevin: "Kings should still get damaged by any ability"): an ability's reach taking in the enemy King hurts
# him (towers take basic attacks only). The shapes as the abilities' own: a circle round `at` (r), a cone (d, cos_arc:
# the cosine of its half angle, as siege_sim._melee's), a line from `at` along d (r long, width either side); his body
# KING_R counts.
func king_in_reach(src: Dictionary, at: Vector2, r: float, d := Vector2.ZERO, cos_arc := -2.0, width := -1.0) -> int:
	var st := int(src.get("team", -1))
	if st < 0 or st > 1:
		return -1
	var t := 1 - st
	if bool(kings[t].dead):
		return -1
	var off: Vector2 = king_pos(t) - at
	var dist := off.length()
	if width >= 0.0:
		var along := off.dot(d)
		if along < -KING_R or along > r + KING_R or absf(off.cross(d)) > width + KING_R:
			return -1
		return t
	if dist > r + KING_R:
		return -1
	if cos_arc > -1.0 and dist > KING_R + 0.8 and d != Vector2.ZERO:
		var half := acos(clampf(cos_arc, -1.0, 1.0)) + asin(clampf(KING_R / dist, 0.0, 1.0))
		if absf(d.angle_to(off)) > half:
			return -1
	return t

func ability_king(src: Dictionary, amount: float, at: Vector2, r: float, d := Vector2.ZERO, cos_arc := -2.0, width := -1.0) -> int:
	# hurt the enemy King if he's in this ability's reach: 1 if he was, else 0
	var t := king_in_reach(src, at, r, d, cos_arc, width)
	if t < 0:
		return 0
	hit_king(src, t, amount)
	return 1

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
	if vision != null and s.by_id.has(str(src.get("id", ""))):
		vision.reveal(src)                                   # 0.31.158: attacking shows you for 2 s
	var ls: float = float(src.get("m_ls", 0.0)) + float(kits.lifesteal_add(src))        # (0.31.167: BLOODLUST)
	if ls > 0.0 and amount > 0.0 and src.has("hp") and s.alive(src):
		s._heal(src, src, amount * ls)
	if s._basic_by != "" and s._basic_by == str(src.get("id", "")) and int(src.get("poison_n", 0)) > 0:
		kits.poison_hit(src, dst, amount)                   # 0.31.167: POISON BLADES
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
		var lr := _leash(camp)
		match str(camp.reset):
			"hard":
				pass                                           # (0.31.158: going home, it ignores everyone)
			"soft":
				# a hit from inside the leash ends the soft reset and gives back some patience
				if (src.pos as Vector2).distance_to(camp.p) <= lr and (dst.pos as Vector2).distance_to(camp.p) <= lr:
					camp.reset = ""
					camp.target = str(src.id)
					camp.patience = maxf(float(camp.patience), 0.6)
			_:
				var cur: Dictionary = s.by_id.get(str(camp.target), {})
				if cur.is_empty() or not s.alive(cur):
					camp.target = str(src.id)
				elif (src.pos as Vector2).distance_to(camp.p) <= lr:
					camp.patience = minf(1.0, float(camp.patience) + 0.15)      # (a blow from inside: patience back)

func on_kill(src: Dictionary, dst: Dictionary) -> void:
	kits.clear(dst)                              # 0.31.167: shields, slows, poison... gone
	dst["died_at"] = s.time
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
		var mxp := float(MINION_XP_BY.get(str(dst.get("mk", "melee")), MINION_XP))
		for h in near:
			add_xp(h, mxp * (1.0 if near.size() == 1 else 0.65))
		if not by_h.is_empty() and int(by_h.team) != int(dst.team):
			add_gold(by_h, minion_gold(dst), dst.pos, "cs")     # the last hit
			by_h["lh"] = int(by_h.get("lh", 0)) + 1       # (0.31.164: the match's rewards and challenges count it)
	elif bool(dst.get("hero", false)):
		dst.respawn_at = s.time + RESPAWN_BASE + RESPAWN_LVL * float(int(dst.level))
		dst.erase("dance")
		# 0.31.180: whose kill it is -- the hero behind the blow, else the last enemy hero to touch him within KILL_CREDIT
		var killer := kill_credit(dst, by_h)
		var et := 1 - int(dst.team)
		if not killer.is_empty() or (not src.is_empty() and src.has("team") and int(src.team) == et):
			s.kills[et] += 1
		var n := 0
		if not killer.is_empty():
			killer.kills = int(killer.kills) + 1
			n = _multi(killer, dst)
		var reward := HERO_XP + HERO_XP_LVL * float(int(dst.level))
		if not killer.is_empty():
			add_xp(killer, reward)
		for hid in heroes[et]:
			var h2: Dictionary = s.by_id.get(hid, {})
			if not h2.is_empty() and h2 != killer and s.alive(h2) and (h2.pos as Vector2).distance_to(dst.pos) <= XP_R:
				add_xp(h2, reward * 0.5)
		var shown := bounty_shown(dst)
		var paid := _hero_down_gold(dst, killer)
		_pass_buffs(dst, by_h)
		if not killer.is_empty():
			# the banner (siege_hud.gd): FIRST BLOOD, a multi-kill, a SHUTDOWN (a bounty the board showed), else a kill
			var kind := "kill"
			if not first_blood:
				kind = "first_blood"
			elif n >= 2:
				kind = "multi"
			elif shown >= BOUNTY_SHOW:
				kind = "shutdown"
			first_blood = true
			s._event("kb", {"kind":kind, "n":n, "by":str(killer.id), "id":str(dst.id), "team":et, "bounty":int(round(paid)),
				"shut":shown >= BOUNTY_SHOW})
		# ACE: the whole side down at once
		var all_down := true
		for hid3 in heroes[int(dst.team)]:
			var h3: Dictionary = s.by_id.get(hid3, {})
			if not h3.is_empty() and s.alive(h3):
				all_down = false
				break
		if all_down and (not killer.is_empty() or (not src.is_empty() and int(src.get("team", -1)) == et)):
			s._event("ace", {"team":et, "by":str(killer.get("id", "")), "ids":(heroes[int(dst.team)] as Array).duplicate()})
	s._event("death", {"id":dst.id, "by":src.get("id", ""), "push":[snappedf(push.x, 0.01), snappedf(push.y, 0.01), snappedf(push.z, 0.01)],
		"minion":bool(dst.get("minion", false)), "mon":dst.has("mon")})

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
	# 0.31.158: League's minion -- its target by the priority list (_minion_target), kept until a higher one shows up;
	# nothing in reach: the structure in its way (a tower, the gate at the lane's end, the King once open), else on
	# down the lane
	var tg := _minion_target(u)
	if not tg.is_empty():
		if tg.has("tw"):                               # an enemy tower (it's shooting one of ours)
			u["mt"] = ""
			u["mt_tw"] = int(tg.tw)
			_hit_structure(u, towers[int(tg.tw)])
			return
		u["mt"] = str(tg.id)
		u["mt_tw"] = -1
		s._fight(u, tg)
		return
	u["mt"] = ""
	u["mt_pri"] = 9
	var c: Dictionary = s.CLASSES[u.cls]
	var reach := ACQ_R if not bool(c.ranged) else maxf(ACQ_R, float(s.stat(u, "range")) * 0.8)
	var tw := _enemy_tower_near(u, reach + TOWER_R)
	if not tw.is_empty():
		u["mt_tw"] = int(tw.id)
		_hit_structure(u, tw)
		return
	u["mt_tw"] = -1
	var eteam := 1 - int(u.team)
	if king_open(eteam) and (u.pos as Vector2).distance_to(king_pos(eteam)) < reach + KING_R + 2.0:
		_hit_point(u, king_pos(eteam), KING_R)
		return
	_march(u)

func _minion_target(u: Dictionary) -> Dictionary:
	# League's minion targeting, highest first: 1 an enemy champion attacking an allied champion (call for help, the
	# ally within HELP_R -- not while it's hitting a tower), 2 an enemy minion attacking an allied champion, 3 an enemy
	# minion attacking an allied minion, 4 an enemy tower attacking an allied minion, 5 the nearest enemy minion, 6 the
	# nearest enemy champion -- within ACQ_R (ranged: their reach), seen by its side. It keeps its target unless a
	# higher one appears. Returns a unit, {"tw": id} for a tower, or {}.
	var team := int(u.team)
	var c: Dictionary = s.CLASSES[u.cls]
	var acq := ACQ_R if not bool(c.ranged) else maxf(ACQ_R, float(s.stat(u, "range")) * 0.8)
	var cur: Dictionary = s.by_id.get(str(u.get("mt", "")), {})
	var cur_pri := int(u.get("mt_pri", 9))
	if cur.is_empty() or not s.alive(cur) or int(cur.team) == team or int(cur.team) > 1 or (cur.pos as Vector2).distance_to(u.pos) > acq + 3.0 \
			or not can_see(team, cur):
		cur = {}
		cur_pri = 9
	var on_tower := int(u.get("mt_tw", -1)) >= 0
	var best := {}
	var bp := 9
	var bd := INF
	if not on_tower:
		for hid in heroes[team]:
			var h: Dictionary = s.by_id.get(hid, {})
			if h.is_empty() or not s.alive(h) or s.time - float(h.get("hh_at", -99.0)) > HELP_FOR or (h.pos as Vector2).distance_to(u.pos) > HELP_R:
				continue
			var a: Dictionary = s.by_id.get(str(h.get("hh_by", "")), {})
			if a.is_empty() or not s.alive(a) or not can_see(team, a):
				continue
			var da: float = (a.pos as Vector2).distance_to(u.pos)
			if da <= acq + 4.0 and (bp > 1 or da < bd):
				bp = 1
				bd = da
				best = a
	for o in units_near(u.pos, acq):
		if int(o.team) == team or int(o.team) > 1 or not s.alive(o):
			continue
		var d: float = (o.pos as Vector2).distance_to(u.pos)
		if d > acq or not can_see(team, o):
			continue
		var pri := 6
		if bool(o.get("minion", false)):
			pri = 5
			var ot: Dictionary = s.by_id.get(str(o.get("mt", "")), {})
			if not ot.is_empty() and int(ot.team) == team:
				pri = 2 if bool(ot.get("hero", false)) else 3
		elif bool(o.get("hero", false)):
			pri = 6
		else:
			continue
		if pri < bp or (pri == bp and d < bd):
			bp = pri
			bd = d
			best = o
	if bp > 4:
		for tw in towers:                              # 4: an enemy tower shooting one of our minions
			if int(tw.team) == team or bool(tw.dead) or (tw.p as Vector2).distance_to(u.pos) > acq + TOWER_R + 2.0:
				continue
			var tt: Dictionary = s.by_id.get(str(tw.target), {})
			if not tt.is_empty() and int(tt.team) == team and bool(tt.get("minion", false)):
				u["mt_pri"] = 4
				return {"tw":int(tw.id)}
	if not cur.is_empty() and cur_pri <= bp:
		return cur
	u["mt_pri"] = bp
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

func _bot_recall(u: Dictionary) -> bool:
	# 0.31.181: a bot going home recalls when it's safe to stand still (no enemy hero within BOT_RECALL_SAFE m, no
	# enemy tower in reach, not in his own keep already)
	if s.in_castle(u.pos, int(u.team)) or not tower_in_range(1 - int(u.team), u.pos, 1.0).is_empty():
		return false
	for o in units_near(u.pos, BOT_RECALL_SAFE):
		if int(o.team) == 1 - int(u.team) and s.alive(o) and bool(o.get("hero", false)) \
				and (o.pos as Vector2).distance_to(u.pos) < BOT_RECALL_SAFE:
			return false
	u.move = Vector2.ZERO
	return s.act(str(u.id), "recall")

const BOT_RECALL_SAFE := 14.0

func _hit_structure(u: Dictionary, tw: Dictionary) -> void:
	# up to it and swing / shoot (an invulnerable one too: it's in the way -- the hit does nothing). 0.31.179: from
	# inside its range (a hit from outside does nothing), so a long gun walks in too
	_hit_point(u, tw.p, TOWER_R, TOWER_RANGE - 0.6)

func _hit_point(u: Dictionary, p: Vector2, r: float, within := INF) -> void:
	var c: Dictionary = s.CLASSES[u.cls]
	var d: float = (u.pos as Vector2).distance_to(p) - r
	var reach: float = minf(float(s.stat(u, "range")) * (0.85 if bool(c.ranged) else 1.0), within - r)
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
		if int(g.team) == team and (g.c as Vector2).distance_to(p) < 6.0:
			return g
	return {}

func _hit_gate(u: Dictionary, g: Dictionary) -> void:
	var c: Dictionary = s.CLASSES[u.cls]
	var cp: Vector2 = s.seg_closest(u.pos, g.a, g.b)
	var d: float = (u.pos as Vector2).distance_to(cp)
	var reach: float = float(s.stat(u, "range")) * (0.8 if bool(c.ranged) else 1.0)
	if d > reach + s.WALL_R:
		s._nav_to(u, cp + (g["in"] as Vector2) * -1.2, 0.6)
		return
	u.move = Vector2.ZERO
	u.face = s.angle_of(cp - (u.pos as Vector2))
	s._start_attack(u, "attack", false)

func _think_hero(u: Dictionary) -> void:
	var c: Dictionary = s.CLASSES[u.cls]
	var reach := float(s.stat(u, "range"))
	# our King under attack: those near come back and fight whoever's at him
	var th := king_threat(int(u.team))
	if not th.is_empty() and (u.pos as Vector2).distance_to(king_pos(int(u.team))) < 45.0 and u.hp > u.max_hp * 0.35:
		_fight_h(u, th)
		return
	# their King open (a lane of theirs broken, 0.31.217): the King runners go for him -- their heroes in the way first
	# (until then the King towers first, once a gate was down)
	var eteam := 1 - int(u.team)
	if king_open(eteam) and ((bool(u.get("kr", false)) and u.hp > u.max_hp * 0.45) \
			or (_end_push(int(u.team)) and u.hp > u.max_hp * 0.35)):
		for o in units_near(u.pos, reach + 3.0):
			if int(o.team) == eteam and s.alive(o) and bool(o.get("hero", false)) and (o.pos as Vector2).distance_to(u.pos) < reach + 3.0 \
					and can_see(int(u.team), o):
				_fight_h(u, o)
				return
		_hit_point(u, king_pos(eteam), KING_R)
		return
	# 0.31.157: the ultimate when it's worth it (before running home: GRACE, BULWARK, UNDYING are for hard moments)
	if _bot_ult(u) or kits.bot_spells(u):              # (0.31.167: W and E too)
		return
	# hurt: home to heal -- 0.31.181: by RECALL when no enemy hero is near and no tower is on him, else on foot
	if s.recalling(u):
		u.move = Vector2.ZERO
		return
	if bool(u.get("back", false)):
		if u.hp >= u.max_hp * 0.92:
			u.back = false
		else:
			if not _bot_recall(u):
				s._nav_to(u, s.spawn(int(u.team)), 1.5)
			return
	if u.hp < u.max_hp * 0.3 and not s.in_castle(u.pos, int(u.team)):
		u["back"] = true
		if not _bot_recall(u):
			s._nav_to(u, s.spawn(int(u.team)), 1.5)
		return
	# 0.31.157: the Bone Lord when the side goes for him
	if boss_go[int(u.team)] and u.hp > u.max_hp * 0.45 and _go_lord(u):
		return
	if wyrm_go[int(u.team)] and u.hp > u.max_hp * 0.4 and _go_epic(u, _wyrm_unit(), WYRM_GATHER):     # 0.31.166
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
	for o in units_near(u.pos, fd):
		if int(o.team) == int(u.team) or not s.alive(o) or not bool(o.get("hero", false)) or not can_see(int(u.team), o):
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
	for o in units_near(u.pos, md):
		if int(o.team) == int(u.team) or not s.alive(o) or not bool(o.get("minion", false)) or not can_see(int(u.team), o):
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
		if int(g.team) == int(u.team) or not s.gate_blocks(g) or not gate_open(g):
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
	for o in units_near(p, TOWER_RANGE):
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
		if int(g.team) != team and not s.gate_blocks(g):
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
			ev["c"] = at                                  # 0.31.160: not "at" (the sim's _event stamps "at" with the time)
			ev["r"] = RAIN_R
			ev["dur"] = 0.25 + RAIN_EVERY * float(RAIN_TICKS)
		"mage":
			for o in _enemies_in(u, u.pos, INFERNO_R):
				s._next_push = s._push_from(u.pos, o.pos, 6.0, 3.0)
				s._damage(u, o, dmg * INFERNO_DMG * k, INFERNO_STUN)
			ability_king(u, dmg * INFERNO_DMG * k, u.pos, INFERNO_R)
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
			ability_king(u, dmg * JUDGMENT_DMG * k, u.pos, JUDGMENT_R)
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
			ev["c"] = c
		"necromancer":
			var ids3 := []
			var n2 := LEGION_N + (2 if k > 1.0 else 0)
			for i in n2:
				var z := _raise_skeleton(u, (u.pos as Vector2) + Vector2.from_angle(TAU * float(i) / float(n2) + 0.4) * 1.8)
				ids3.append(z.id)
			ev["ids"] = ids3
		_:
			if not kits.ult(u, k, dmg, ev):            # 0.31.168: the six new heroes' (moba_kits.gd)
				return false
	u.ult_cd = ult_max_cd(u)
	if hid not in ["rogue", "assassin"] and u.state != "dash" and not u.has("dance"):
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
		if int(o.team) != int(u.team) and s.alive(o) and (o.pos as Vector2).distance_to(at) <= r:
			out.append(o)
	return out

func _weakest_hero(u: Dictionary, r: float) -> Dictionary:
	var best := {}
	var bf := INF
	for o in s.units:
		if int(o.team) == int(u.team) or int(o.team) > 1 or not s.alive(o) or not bool(o.get("hero", false)) or not can_see(int(u.team), o):
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
		if int(o.team) != int(u.team) and int(o.team) <= 1 and s.alive(o) and bool(o.get("hero", false)) and can_see(int(u.team), o):
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
		if int(o.team) != int(u.team) and int(o.team) <= 1 and s.alive(o) and bool(o.get("hero", false)) and can_see(int(u.team), o):
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
			if int(o.team) != int(r.team) and s.alive(o) and (o.pos as Vector2).distance_to(r.at) <= float(r.r):
				s._damage(owner, o, float(r.dmg))
		ability_king(owner, float(r.dmg), r.at, float(r.r))             # (0.31.179: the King under it too)
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
		s._damage(u, t, float(dn.dmg) + float(dn.get("missing", 0.0)) * maxf(0.0, float(t.max_hp) - float(t.hp)))   # (0.31.168: GRAND CHALLENGE)
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
	if bool(dst.get("hero", false)) and lane_minion(str(src.get("id", ""))):
		a *= MINION_VS_HERO                             # 0.31.158: League's minions deal 60 % to champions
	if t < float(dst.get("dr_until", -1.0)):
		a *= 1.0 - float(dst.get("dr", 0.0))
	a *= 1.0 - float(dst.get("m_armor", 0.0))
	if kits != null:
		a = kits.taken(src, dst, a)                         # 0.31.167: marks and curses, then shields
	if t < float(dst.get("ud_until", -1.0)):
		a = minf(a, maxf(0.0, float(dst.hp) - 1.0))         # UNDYING: never below 1
	if dst.has("mon") and str(camps[int(dst.mon)].reset) == "hard":
		a = 0.0                                             # (a camp hard-resetting can't be hurt till it's home)
	return a

func _raise_skeleton(owner: Dictionary, at: Vector2) -> Dictionary:
	_zid += 1
	var id := "z%d" % _zid
	var z: Dictionary = s._new_unit(id, int(owner.team), true)
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
	for o in units_near(base, bd):
		if int(o.team) == int(u.team) or not s.alive(o):
			continue
		if o.has("mon") and str(camps[int(o.mon)].target) == "":
			continue                                   # (sleeping monsters are left alone)
		if not can_see(int(u.team), o):
			continue
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
		if int(o.team) == int(u.team) or not s.alive(o) or not can_see(int(u.team), o):
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
		_:
			return kits.bot_ult(u, near_h, near_any, closest, cd, lord_fight) and ult(u)      # 0.31.168: the six new heroes
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
	# (sim._damage_gate) a lane minion's blow on a gate counts as on a tower (MINION_TOWER), the Bone Lord's LORD_SIEGE
	if bool(src.get("lordling", false)):
		return LORD_SIEGE
	return float(MINION_TOWER.get(str(src.get("mk", "melee")), 0.4)) if lane_minion(str(src.get("id", ""))) else 1.0

func minion_gold(u: Dictionary) -> float:
	# League's last-hit gold: melee 21, caster 14; siege and super 60, +3 every 90 s, at most 90; the Bone Lord 150
	var mk := str(u.get("mk", "melee"))
	if bool(u.get("lordling", false)):
		return 150.0
	var g := float(GOLD_MINION.get(mk, 14))
	if mk in ["siege", "super"]:
		g = minf(90.0, g + 3.0 * floorf(float(s.time) / MINION_UP_EVERY))
	return g

func can_see(team: int, u: Dictionary) -> bool:
	# 0.31.158: side `team` sees u (its own, or in its sight and not hidden in brush) -- the fog of war
	return vision == null or vision.can_see(team, u)

func ward(u: Dictionary) -> bool:
	return vision != null and vision.place_ward(u)

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

func add_gold(u: Dictionary, n: float, at: Vector2, kind := "") -> void:
	# (0.31.180: kind "kill" -- a kill's or an assist's gold -- or "cs" -- a minion's or a monster's: the bounty grows)
	if u.is_empty() or not bool(u.get("hero", false)) or n <= 0.0:
		return
	if kind == "kill" or kind == "cs":
		u["bounty"] = float(u.get("bounty", 0.0)) + n * (BOUNTY_KILL if kind == "kill" else BOUNTY_CS)
	u.gold = float(u.gold) + n
	u.gold_total = float(u.get("gold_total", 0.0)) + n
	s._event("gold", {"id":u.id, "n":int(round(n)), "pos":at if at != Vector2.INF else u.pos})

func _hero_down_gold(dst: Dictionary, killer: Dictionary) -> float:
	# a hero knocked out: GOLD_HERO and his bounty to his killer, GOLD_ASSIST between those who helped (0.31.180:
	# hurt or held him, or healed the killer, within ASSIST_WINDOW s -- League's). The bounty paid back.
	var et := 1 - int(dst.team)
	var paid := 0.0
	if not killer.is_empty() and int(killer.team) == et:
		var raw := minf(float(dst.get("bounty", 0.0)), BOUNTY_MAX)
		paid = raw * (1.0 - devalue(int(dst.team)))
		dst["bounty"] = float(dst.get("bounty", 0.0)) - raw            # (above BOUNTY_MAX: the rest is his next life's)
		add_gold(killer, GOLD_HERO + paid, dst.pos, "kill")
	var hlog: Dictionary = dst.get("hit_log", {})
	var clog: Dictionary = dst.get("cc_log", {})
	var heals: Dictionary = killer.get("heal_log", {}) if not killer.is_empty() else {}
	var helpers := []
	for hid in heroes[et]:
		var h: Dictionary = s.by_id.get(hid, {})
		if h.is_empty() or h == killer:
			continue
		var t_last := maxf(float(hlog.get(str(hid), -99.0)), maxf(float(clog.get(str(hid), -99.0)), float(heals.get(str(hid), -99.0))))
		if s.time - t_last <= ASSIST_WINDOW:
			helpers.append(h)
	for h in helpers:
		add_gold(h, float(GOLD_ASSIST) / float(helpers.size()), dst.pos, "kill")
		h["assists"] = int(h.get("assists", 0)) + 1        # 0.31.176: the scoreboard's K/D/A (League's: helped, not the blow)
	dst["hit_log"] = {}
	dst["cc_log"] = {}
	return paid

func kill_credit(dst: Dictionary, by_h: Dictionary) -> Dictionary:
	# 0.31.180: the enemy hero whose kill it is -- the one behind the blow, else the last enemy hero to touch him within
	# KILL_CREDIT s (League's: a tower or a minion finishing what he started); {} for none
	var et := 1 - int(dst.team)
	if not by_h.is_empty() and int(by_h.get("team", -1)) == et:
		return by_h
	var best := {}
	var bt: float = s.time - KILL_CREDIT
	for hid in dst.get("hit_log", {}):
		var h: Dictionary = s.by_id.get(str(hid), {})
		var at := float(dst.hit_log[hid])
		if not h.is_empty() and int(h.team) == et and bool(h.get("hero", false)) and at >= bt:
			best = h
			bt = at
	return best

func _multi(k: Dictionary, dst: Dictionary) -> int:
	# 0.31.180: League's multi-kill windows (MULTI_GAP between kills; a QUADRA's PENTA within PENTA_GAP unless one of
	# the enemy came back first); a PENTA ends the chain. The step is a "multikill" event (the Herald calls it).
	var n := 1
	var last := float(k.get("mk_t", -INF))
	var had := int(k.get("mk_n", 0))
	if had == 4:
		if s.time - last <= PENTA_GAP and float(last_respawn[int(dst.team)]) <= last:
			n = 5
	elif had >= 1 and had < 4 and s.time - last <= MULTI_GAP:
		n = had + 1
	k["mk_n"] = n if n < 5 else 0
	k["mk_t"] = s.time
	if n >= 2:
		k["best_multi"] = maxi(int(k.get("best_multi", 0)), n)
		s._event("multikill", {"id":k.id, "team":int(k.team), "n":n, "name":MULTI_NAMES[n]})
	return n

func worth(u: Dictionary) -> float:
	# what a hero carries and his items' cost (the board's gold)
	var n := float(u.get("gold", 0.0))
	for id in u.get("items", []):
		n += float(ITEMS.get(str(id), {}).get("cost", 0))
	return n

func side_worth(t: int) -> float:
	var n := 0.0
	for hid in heroes[t]:
		n += worth(s.by_id.get(hid, {}))
	return n

func devalue(t: int) -> float:
	# how much less side t's bounties count: nothing until it's DEVALUE_FROM behind in gold, DEVALUE_MIN there, up to
	# DEVALUE_MAX at DEVALUE_FULL behind
	var ours := side_worth(t)
	var theirs := side_worth(1 - t)
	if theirs <= 0.0 or ours >= theirs:
		return 0.0
	var d := (theirs - ours) / theirs
	if d < DEVALUE_FROM:
		return 0.0
	return lerpf(DEVALUE_MIN, DEVALUE_MAX, clampf((d - DEVALUE_FROM) / (DEVALUE_FULL - DEVALUE_FROM), 0.0, 1.0))

func bounty_value(u: Dictionary) -> float:
	# what his killer would be paid on top of the kill now
	if not bool(u.get("hero", false)) or int(u.get("team", -1)) < 0 or int(u.get("team", -1)) > 1:
		return 0.0
	return minf(float(u.get("bounty", 0.0)), BOUNTY_MAX) * (1.0 - devalue(int(u.team)))

func bounty_shown(u: Dictionary) -> int:
	# the board's figure: from BOUNTY_SHOW, in steps of BOUNTY_STEP (0: none shown)
	var v := bounty_value(u)
	return 0 if v < float(BOUNTY_SHOW) else int(floor(v / float(BOUNTY_STEP))) * BOUNTY_STEP

func note_cc(by: Dictionary, dst: Dictionary) -> void:
	# 0.31.180: a hero slowed / stunned / held dst (an assist if dst falls within ASSIST_WINDOW)
	var hb := _credit(by)
	if hb.is_empty() or not bool(dst.get("hero", false)) or int(hb.team) == int(dst.get("team", -1)):
		return
	if not dst.has("cc_log"):
		dst["cc_log"] = {}
	(dst.cc_log as Dictionary)[str(hb.id)] = s.time

func note_heal(by: Dictionary, dst: Dictionary) -> void:
	# 0.31.180: a hero healed an ally (an assist if that ally kills within ASSIST_WINDOW)
	if by == dst or not bool(by.get("hero", false)) or not bool(dst.get("hero", false)) or int(by.team) != int(dst.team):
		return
	if not dst.has("heal_log"):
		dst["heal_log"] = {}
	(dst.heal_log as Dictionary)[str(by.id)] = s.time

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
	var build: Array = BUILDS.get(str(u.get("hid", "")), BUILDS.get(str(u.cls), BUILDS.knight))
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
		"next":LORD_FIRST if kind == "lord" else (WYRM_FIRST if kind == "wyrm" else CAMP_FIRST), "target":"", "hits":{}, "slam":0.0,
		"patience":1.0, "reset":"", "reset_at":0.0})

func _leash(camp: Dictionary) -> float:
	match str(camp.kind):
		"lord": return LORD_LEASH
		"wyrm": return WYRM_LEASH
	return LEASH

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
		var u: Dictionary = s._new_unit(id, 2, true)
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
	camp.patience = 1.0
	camp.reset = ""
	camp.slam = s.time + (WYRM_BREATH_EVERY if str(camp.kind) == "wyrm" else LORD_SLAM_EVERY)
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
		var lr := _leash(camp)
		match str(camp.reset):
			"soft", "hard":
				var rate := SOFT_HEAL if str(camp.reset) == "soft" else HARD_HEAL
				var settled := true
				for m in live:
					if float(m.hp) < float(m.max_hp):
						m.hp = minf(float(m.max_hp), float(m.hp) + float(m.max_hp) * rate * dt)
						settled = false
					if (m.pos as Vector2).distance_to(m.home) > 0.9:
						settled = false
				if str(camp.reset) == "soft" and s.time >= float(camp.reset_at):
					camp.reset = "hard"
					s._event("camp_reset", {"camp":int(camp.id), "hard":true})
				if settled:
					camp.reset = ""
					camp.patience = 1.0
					camp.hits = {}
				continue
		var tgt: Dictionary = s.by_id.get(str(camp.target), {})
		if str(camp.target) != "" and (tgt.is_empty() or not s.alive(tgt)):
			# its target fell: the latest other who hit it, still inside the leash; nobody -- reset
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
			tgt = s.by_id.get(best, {})
			if best == "":
				_soft_reset(camp)
				continue
		if str(camp.target) == "":
			for m in live:
				if float(m.hp) < float(m.max_hp) - 0.5:
					_soft_reset(camp)                # hurt with no one to fight (a stray blow): back and heal
					break
			continue
		var d: float = (tgt.pos as Vector2).distance_to(camp.p)
		if d > lr:
			# 0.31.166, League's: its target gone out of the leash -- it turns on the latest other who hit it still inside
			# (the Wyrm healed whenever its tank walked off, three more of them at it)
			var other := ""
			var ot := -INF
			for hid in camp.hits:
				var h: Dictionary = s.by_id.get(str(hid), {})
				if str(hid) == str(camp.target) or h.is_empty() or not s.alive(h) or (h.pos as Vector2).distance_to(camp.p) > lr \
						or s.time - float(camp.hits[hid]) > 6.0:
					continue
				if float(camp.hits[hid]) > ot:
					ot = float(camp.hits[hid])
					other = str(hid)
			if other != "":
				camp.target = other
				tgt = s.by_id[other]
			else:
				camp.patience = float(camp.patience) - dt * (PATIENCE_DRAIN + PATIENCE_FAR * (d - lr))
				if float(camp.patience) <= 0.0:
					_soft_reset(camp)
					continue
		else:
			camp.patience = minf(1.0, float(camp.patience) + dt * PATIENCE_BACK)
		if str(camp.kind) == "lord" and not live.is_empty() and s.time >= float(camp.slam):
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
		if str(camp.kind) == "wyrm" and not live.is_empty() and not tgt.is_empty() and s.time >= float(camp.slam) \
				and (tgt.pos as Vector2).distance_to((live[0] as Dictionary).pos) <= WYRM_BREATH_R:
			# 0.31.166: the Grave Wyrm's soul-fire, a cone at whoever it's fighting
			camp.slam = s.time + WYRM_BREATH_EVERY
			var wy: Dictionary = live[0]
			var dir: Vector2 = ((tgt.pos as Vector2) - (wy.pos as Vector2)).normalized()
			wy.face = s.angle_of(dir)
			var burnt := 0
			for o in units_near(wy.pos, WYRM_BREATH_R + 1.0):
				if int(o.team) > 1 or not s.alive(o):
					continue
				var off: Vector2 = (o.pos as Vector2) - (wy.pos as Vector2)
				if off.length() <= WYRM_BREATH_R and (off.length() < 1.0 or absf(dir.angle_to(off)) <= WYRM_BREATH_ARC):
					s._damage(wy, o, float(s.stat(wy, "dmg")) * WYRM_BREATH_DMG)
					burnt += 1
			s._event("wyrm_breath", {"id":wy.id, "pos":wy.pos, "dir":dir, "n":burnt})

func _summon_lord(team: int) -> Dictionary:
	# 0.31.158 (Kevin: "when a team kills the giant in middle, he will spawn on your side like a minion"): the Bone Lord
	# comes out of the slayers' castle and marches down the middle lane with their minions, fighting like one (League's
	# targeting), towers shooting him first but only 5 % a shot, and hitting towers and gates x LORD_SIEGE -- until he falls
	_mid += 1
	var id := "L%d" % _mid
	var u: Dictionary = s._new_unit(id, team, true)
	u.cls = "barbarian"
	u["minion"] = true
	u["mk"] = "lord"
	u["lordling"] = true
	u["look"] = "skel_lord"
	u["mscale"] = 2.2
	u["lane"] = 1
	u["wp"] = 1
	var grow := 1.0 + MON_GROW * float(s.time) / 60.0
	u["m_hp"] = LORDLING_HP * grow
	u["m_dmg"] = LORDLING_DMG * grow
	u["m_spd"] = 0.8
	u.max_hp = float(s.stat(u, "hp"))
	u.hp = u.max_hp
	var start := wp(team, 1, 0)
	var ahead := (wp(team, 1, 1) - start).normalized()
	u.pos = start + ahead * 2.5
	u.face = s.angle_of(ahead)
	u.think_at = s.time + s.TICK
	s.units.append(u)
	s.by_id[id] = u
	s._event("lord_march", {"team":team, "id":id})
	return u

func _soft_reset(camp: Dictionary) -> void:
	camp.reset = "soft"
	camp.reset_at = s.time + SOFT_RESET
	camp.target = ""
	s._event("camp_reset", {"camp":int(camp.id), "hard":false})

func _think_monster(u: Dictionary) -> void:
	var camp: Dictionary = camps[int(u.mon)]
	var home: Vector2 = u.home
	var lr := _leash(camp)
	var tgt: Dictionary = s.by_id.get(str(camp.target), {})
	if str(camp.reset) == "" and not tgt.is_empty() and s.alive(tgt):
		u["resetting"] = false
		if (tgt.pos as Vector2).distance_to(camp.p) <= lr:
			s._fight(u, tgt)
			return
		# its target is outside the leash: to the leash's edge toward him (patience draining), shooting if he's in reach
		var c: Dictionary = s.CLASSES[u.cls]
		var d: float = (u.pos as Vector2).distance_to(tgt.pos)
		if bool(c.ranged) and d <= float(s.stat(u, "range")) * 0.9:
			u.move = Vector2.ZERO
			u.face = s.angle_of((tgt.pos as Vector2) - (u.pos as Vector2))
			s._start_attack(u, "attack", false)
			return
		var edge: Vector2 = (camp.p as Vector2) + ((tgt.pos as Vector2) - (camp.p as Vector2)).normalized() * (lr - 0.5)
		if (u.pos as Vector2).distance_to(edge) > 0.8:
			s._nav_to(u, edge, 0.5)
		else:
			u.move = Vector2.ZERO
			u.face = s.angle_of((tgt.pos as Vector2) - (u.pos as Vector2))
			if d <= float(s.stat(u, "range")) + s.UNIT_R + 0.2:
				s._start_attack(u, "attack", false)
		return
	# resetting, or nobody to fight: home, and stand
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
				add_gold(h, float(md.gold), dst.pos, "cs")
				add_xp(h, float(md.xp))
				h["epics"] = int(h.get("epics", 0)) + 1      # (0.31.164)
				if s.alive(h):
					(h.buffs as Dictionary)["lord"] = s.time + LORD_TIME
			boss_go[side] = false
			epic_kills.lord[side] = int(epic_kills.lord[side]) + 1
		s._event("lord_down", {"team":side, "by":str(by_h.get("id", ""))})
		if side >= 0:
			_summon_lord(side)                         # 0.31.158 (Kevin): he rises again on their side, like a minion
	elif str(dst.mkind) == "wyrm":
		# 0.31.166: the Grave Wyrm -- every hero of the slaying side: gold, XP, and a stack of WYRM'S HIDE for good
		var wside := int(by_h.team) if not by_h.is_empty() else _side_near(dst.pos)
		if wside >= 0:
			wyrm_stacks[wside] = mini(WYRM_STACKS, int(wyrm_stacks[wside]) + 1)
			for hid in heroes[wside]:
				var wh: Dictionary = s.by_id.get(hid, {})
				if wh.is_empty():
					continue
				add_gold(wh, float(md.gold), dst.pos, "cs")
				add_xp(wh, float(md.xp))
				wh["epics"] = int(wh.get("epics", 0)) + 1
				_apply(wh)                                 # (the health it brings comes with it)
			wyrm_go[wside] = false
			epic_kills.wyrm[wside] = int(epic_kills.wyrm[wside]) + 1
		s._event("wyrm_down", {"team":wside, "by":str(by_h.get("id", "")), "stacks":int(wyrm_stacks[wside]) if wside >= 0 else 0})
	else:
		if not by_h.is_empty():
			add_gold(by_h, float(md.gold), dst.pos, "cs")
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
		if not by_h.is_empty() and not str(dst.mkind) in ["lord", "wyrm"]:
			by_h["camps"] = int(by_h.get("camps", 0)) + 1    # (0.31.164: a camp cleared -- whoever finished it)
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
			if not bool(camp.alive) or str(camp.kind) in ["lord", "wyrm"]:
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
	_epic_call()

func _epic_call() -> void:
	# 0.31.166: a side's bots go for the Grave Wyrm when it's up, they have at least three up and aren't outnumbered (as
	# many up: not behind in levels either -- the side with the edge takes it, rather than both meeting at the pit), and
	# its Hide can still grow for them; they give it up when that's no longer so (the Lord comes first)
	var wy := _wyrm_unit()
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
	for t in 2:
		wyrm_go[t] = not wy.is_empty() and not boss_go[t] and int(wyrm_stacks[t]) < WYRM_STACKS and up[t] >= 3 \
			and (up[t] > up[1 - t] or (up[t] == up[1 - t] and lv[t] >= lv[1 - t]))

func _go_lord(u: Dictionary) -> bool:
	return _go_epic(u, _lord_unit())

func _go_epic(u: Dictionary, boss: Dictionary, gather := 0) -> bool:
	if not bool(u.bot):
		return false
	if boss.is_empty() or (boss.pos as Vector2).distance_to(u.pos) > 60.0:
		return false
	# their heroes at the pit first
	for o in units_near(u.pos, 9.0):
		if int(o.team) == 1 - int(u.team) and s.alive(o) and bool(o.get("hero", false)) and (o.pos as Vector2).distance_to(boss.pos) < 10.0 \
				and (o.pos as Vector2).distance_to(u.pos) < 9.0 and can_see(int(u.team), o):
			_fight_h(u, o)
			return true
	if gather > 0:
		# 0.31.166: the Grave Wyrm is a fight for several -- one at a time it burns them down and heals in between: wait at the
		# rim till `gather` of ours are there, unless it's already fighting one of us
		var fighting: Dictionary = s.by_id.get(str(camps[int(boss.mon)].target), {})
		if fighting.is_empty() or int(fighting.team) != int(u.team):
			var near := 0
			for o in units_near(boss.pos, 14.0):
				if int(o.team) == int(u.team) and bool(o.get("hero", false)) and s.alive(o):
					near += 1
			if near < gather:
				var stage: Vector2 = (boss.pos as Vector2) + ((u.pos as Vector2) - (boss.pos as Vector2)).normalized() * 9.5
				if (u.pos as Vector2).distance_to(stage) > 1.2:
					s._nav_to(u, stage, 1.0)
				else:
					u.move = Vector2.ZERO
				return true
	_fight_h(u, boss)
	return true

func _wyrm_unit() -> Dictionary:
	for camp in camps:
		if str(camp.kind) == "wyrm" and bool(camp.alive):
			var live := camp_live(camp)
			return live[0] if not live.is_empty() else {}
	return {}
