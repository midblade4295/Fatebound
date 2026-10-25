extends RefCounted
# 0.31.167 KITS AND ROLES (Kevin: "We need more characters and class roles like League of Legends and heroes of the
# storm have" -> League's six roles, three abilities and the ultimate). Every 5v5 hero has a role (ROLE_OF) and a kit:
#   Q  his class's ability (siege_sim.gd: block, spin, lunge, volley, nova, sanctuary; the upgraded classes' hammer,
#      whirlwind, vanish, pierce, meteor, resurrect) -- from level 1
#   W  new, from level 2 (UNLOCK)
#   E  new, from level 3
#   R  the ultimate (moba.gd ULTS) -- from level 6
# This holds W and E (KITS), the effects they're built from, and what they leave on heroes for the rest of the 5v5
# rules to read: shields (moba.mod_damage takes hits off them first), slows and hastes (moba.stat "speed"), quicker
# swings ("windup"/"recover"), damage taken up (marked, cursed), lifesteal, the next basic attacks stronger or
# poisoned, poison ticking, a parry. Zones (holy ground, caltrops, a fire pillar's eruption), traps and dashes step
# here (moba.step -> step). Each cast is a "spell" event {id, team, hid, slot, spell, pos, ...} for the view, the HUD
# and the sound. Bots cast theirs when it's worth it (bot_spells, from moba._think_hero).
# 0.31.168 (Kevin picked six new heroes, one a role -- the Golem, the Dragoon, the Duelist, the Stormcaller, the
# Musketeer, the Druid): their whole kit lives here. Their Q is a kit spell too (an "id" in its "q"; it recharges on
# cd_ability, the old Q's clock, so the HUD's Q button and the bots' "ability" use it as before), and their ultimate
# is "r" (moba.ult hands it to ult(); ULTS keeps its name, recharge and text).

const ROLE_ORDER := ["tank", "fighter", "assassin", "mage", "marksman", "support"]
const ROLE_NAMES := {"tank":"TANK", "fighter":"FIGHTER", "assassin":"ASSASSIN", "mage":"MAGE", "marksman":"MARKSMAN",
	"support":"SUPPORT"}
const ROLE_TEXT := {"tank":"Takes the hits and holds the line.", "fighter":"Fights up close and keeps going.",
	"assassin":"Gets in, takes out a hero, gets out.", "mage":"Spells from range: big damage, control.",
	"marksman":"Steady damage from range; carries late.", "support":"Heals, shields and sets up the team."}
const ROLE_OF := {"knight":"tank", "crusader":"tank", "barbarian":"fighter", "berserker":"fighter", "rogue":"assassin",
	"assassin":"assassin", "ranger":"marksman", "sniper":"marksman", "mage":"mage", "archmage":"mage", "priest":"support",
	"necromancer":"support",
	"golem":"tank", "dragoon":"fighter", "duelist":"assassin", "stormcaller":"mage", "musketeer":"marksman", "druid":"support"}
const UNLOCK := {"q":1, "w":2, "e":3}           # (until 0.31.217: the levels Q, W and E came at; skill points since)
# 0.31.217 (Honor of Kings labels each skill under its button: Damage, Enhance, Crowd Control ...): what a skill is for
const TAG_OF := {
	"block":"DEFENSE", "spin":"DAMAGE", "lunge":"MOBILITY", "volley":"DAMAGE", "nova":"DAMAGE", "sanctuary":"HEAL",
	"hammer":"DAMAGE", "whirlwind":"DAMAGE", "vanish":"STEALTH", "pierce":"DAMAGE", "meteor":"DAMAGE",
	"resurrect":"REVIVE", "barkskin":"DEFENSE", "bash":"CONTROL", "blink":"MOBILITY", "bloodlust":"ENHANCE",
	"boneshield":"DEFENSE", "boulder":"CONTROL", "buckshot":"DAMAGE", "caltrops":"CONTROL", "chain":"CONTROL",
	"challenge":"CONTROL", "charge":"MOBILITY", "consecrate":"DAMAGE", "curse":"DEBUFF", "dazzle":"CONTROL",
	"dragondive":"MOBILITY", "entangle":"CONTROL", "feint":"MOBILITY", "frenzy":"ENHANCE", "gust":"CONTROL",
	"holylight":"HEAL", "impale":"DAMAGE", "keg":"DAMAGE", "knives":"DAMAGE", "landslide":"CONTROL", "leap":"MOBILITY",
	"manashield":"DEFENSE", "mark":"DEBUFF", "missiles":"DAMAGE", "pillar":"CONTROL", "poison":"ENHANCE",
	"quake":"CONTROL", "quickdraw":"ENHANCE", "rally":"DEFENSE", "rejuv":"HEAL", "riposte":"DEFENSE",
	"shadowstep":"MOBILITY", "smokeroll":"MOBILITY", "snare":"CONTROL", "static":"DAMAGE", "stoneskin":"DEFENSE",
	"sweep":"DAMAGE", "thrust":"DAMAGE", "thunderstorm":"DAMAGE", "trap":"CONTROL", "tumble":"MOBILITY",
	"vault":"MOBILITY", "wildgrowth":"HEAL",
}

static func tag(hid: String, slot: String, class_ability := "") -> String:
	# the word under a skill's button
	if slot == "r":
		return "ULTIMATE"
	var k := kit(hid, slot)
	var id := str(k.get("id", class_ability if slot == "q" else ""))
	return str(TAG_OF.get(id, "SKILL"))

# hid -> {"q": what the class's ability is, "w": {...}, "e": {...}}. A W/E: id (the effect), name, short (the button),
# cd (s), text, and its numbers.
const KITS := {
	"knight": {
		"q": {"name":"SHIELD", "text":"Hold: your shield blocks everything from the front."},
		"w": {"id":"bash", "name":"SHIELD BASH", "short":"BASH", "cd":10.0, "dist":5.0, "dmg":1.0, "stun":1.0,
			"text":"Charge 5 m behind your shield; the first enemy you hit is stunned for 1 s."},
		"e": {"id":"rally", "name":"RALLY", "cd":16.0, "r":7.0, "shield":0.15, "dur":4.0,
			"text":"You and every ally hero near: a shield worth 15 % of your health for 4 s."}},
	"crusader": {
		"q": {"name":"HAMMER", "text":"Throws his hammer through a line; it comes back."},
		"w": {"id":"block", "name":"SHIELD", "short":"BLOCK", "cd":0.0, "hold":true,
			"text":"Hold: your shield blocks everything from the front."},
		"e": {"id":"consecrate", "name":"CONSECRATE", "short":"HOLY", "cd":14.0, "r":4.0, "dur":4.0, "dmg":0.25, "slow":0.3,
			"heal":0.015, "text":"Holy ground round you for 4 s: enemies on it slowed and burnt, allies healed."}},
	"barbarian": {
		"q": {"name":"SPIN", "text":"A spinning swing that hits everyone round you."},
		"w": {"id":"leap", "name":"LEAP", "cd":11.0, "range":8.0, "r":2.5, "dmg":1.2, "slow":0.3, "dur":1.5,
			"text":"Leap onto an enemy hero up to 8 m away (or ahead) and slam: damage and a slow round you."},
		"e": {"id":"bloodlust", "name":"BLOODLUST", "short":"RAGE", "cd":15.0, "ls":0.3, "haste":0.15, "dur":5.0,
			"text":"5 s: your hits heal you for 30 % of their damage, and you're 15 % quicker."}},
	"berserker": {
		"q": {"name":"WHIRLWIND", "text":"A whirlwind that keeps moving."},
		"w": {"id":"charge", "name":"RECKLESS CHARGE", "short":"CHARGE", "cd":10.0, "dist":7.0, "dmg":0.8,
			"text":"Charge 7 m through them, hitting everyone you pass."},
		"e": {"id":"frenzy", "name":"FRENZY", "cd":16.0, "heal":0.12, "as":0.35, "dur":4.0,
			"text":"Heal 12 % of your health and swing 35 % quicker for 4 s."}},
	"rogue": {
		"q": {"name":"LUNGE", "text":"Lunges in, quick and sharp."},
		"w": {"id":"caltrops", "name":"CALTROPS", "cd":12.0, "range":8.0, "r":3.0, "dur":4.0, "dmg":0.2, "slow":0.4,
			"text":"Scatter caltrops round an enemy hero up to 8 m away: slowed and cut while on them, 4 s."},
		"e": {"id":"poison", "name":"POISON BLADES", "short":"POISON", "cd":10.0, "n":3, "dps":0.25, "dur":4.0,
			"text":"Your next 3 hits poison: a quarter of your damage a second for 4 s."}},
	"assassin": {
		"q": {"name":"VANISH", "text":"Vanishes, then strikes twice as hard."},
		"w": {"id":"shadowstep", "name":"SHADOW STEP", "short":"STEP", "cd":10.0, "range":8.0, "dmg":1.5,
			"text":"Step out of the shadows behind an enemy hero up to 8 m away and strike."},
		"e": {"id":"knives", "name":"FAN OF KNIVES", "short":"KNIVES", "cd":8.0, "r":5.5, "arc":0.7, "dmg":1.0, "slow":0.25,
			"dur":2.0, "text":"Knives in a fan ahead of you: damage, and a slow for 2 s."}},
	"ranger": {
		"q": {"name":"VOLLEY", "text":"Five arrows in a fan."},
		"w": {"id":"tumble", "name":"TUMBLE", "cd":8.0, "dist":4.5, "emp":0.6, "dur":3.0,
			"text":"Roll 4.5 m; your next shot within 3 s hits 60 % harder."},
		"e": {"id":"snare", "name":"SNARE ARROW", "short":"SNARE", "cd":12.0, "range":12.0, "dmg":0.8, "stun":1.2,
			"text":"An arrow that roots the first enemy it hits for 1.2 s."}},
	"sniper": {
		"q": {"name":"PIERCE", "text":"A piercing shot through everyone in a line."},
		"w": {"id":"trap", "name":"BEAR TRAP", "short":"TRAP", "cd":14.0, "n":2, "life":40.0, "arm":0.8, "r":1.0, "dmg":0.8,
			"stun":1.5, "text":"Set a trap at your feet (two at most): the first enemy on it is caught for 1.5 s and seen."},
		"e": {"id":"mark", "name":"HUNTER'S MARK", "short":"MARK", "cd":14.0, "range":13.0, "amp":0.2, "dur":5.0,
			"text":"Mark an enemy hero up to 13 m away: seen, and takes 20 % more damage for 5 s."}},
	"mage": {
		"q": {"name":"NOVA", "text":"A blast of fire all round her."},
		"w": {"id":"pillar", "name":"FIRE PILLAR", "short":"PILLAR", "cd":10.0, "range":10.0, "r":2.5, "delay":0.7, "dmg":1.6,
			"stun":1.0, "text":"Fire erupts under an enemy up to 10 m away after a moment: heavy damage and a 1 s stun."},
		"e": {"id":"blink", "name":"BLINK", "cd":14.0, "dist":6.0,
			"text":"Vanish and appear 6 m away, the way you're going."}},
	"archmage": {
		"q": {"name":"METEOR", "text":"Calls down a meteor."},
		"w": {"id":"missiles", "name":"ARCANE MISSILES", "short":"MISSILE", "cd":8.0, "range":10.0, "n":3, "dmg":0.9,
			"text":"Three bolts at up to three enemies near (heroes first)."},
		"e": {"id":"manashield", "name":"MANA SHIELD", "short":"SHIELD", "cd":16.0, "shield":0.25, "dur":4.0,
			"text":"A shield worth 25 % of your health for 4 s."}},
	"priest": {
		"q": {"name":"SANCTUARY", "text":"Heals every ally near."},
		"w": {"id":"holylight", "name":"HOLY LIGHT", "short":"LIGHT", "cd":10.0, "range":10.0, "heal":0.22,
			"text":"Heal the most hurt ally hero near you (or you) by 22 % of their health, and free them of slows."},
		"e": {"id":"dazzle", "name":"DAZZLE", "cd":14.0, "r":4.5, "stun":0.9,
			"text":"A flash of light: every enemy round you stunned for 0.9 s."}},
	"necromancer": {
		"q": {"name":"RESURRECT", "text":"Brings a fallen ally back where he fell."},
		"w": {"id":"boneshield", "name":"BONE SHIELD", "short":"BONES", "cd":12.0, "range":10.0, "shield":0.2, "dur":4.0,
			"text":"Bones wrap the most hurt ally hero near you (or you): a shield of 20 % of their health, 4 s."},
		"e": {"id":"curse", "name":"CURSE", "cd":13.0, "range":10.0, "slow":0.35, "amp":0.15, "dur":4.0,
			"text":"Curse an enemy hero up to 10 m away: slowed 35 % and takes 15 % more damage for 4 s."}},
	# ---- 0.31.168: the six new heroes (Q is theirs too, and R) ----
	"golem": {
		"q": {"id":"boulder", "name":"BOULDER", "cd":9.0, "range":11.0, "dmg":1.2, "stun":1.0,
			"text":"Hurl a boulder: the first enemy it hits takes heavy damage and is stunned for 1 s."},
		"w": {"id":"stoneskin", "name":"STONESKIN", "short":"STONE", "cd":15.0, "dr":0.4, "dur":4.0,
			"text":"Your skin turns to stone for 4 s: you take 40 % less damage, and slows fall off you."},
		"e": {"id":"quake", "name":"QUAKE", "cd":11.0, "r":4.0, "dmg":0.9, "slow":0.4, "dur":2.0,
			"text":"Stamp the ground: everyone round you hurt and slowed 40 % for 2 s."},
		"r": {"id":"landslide", "dist":9.0, "dmg":1.2, "r":4.0, "land":1.6, "stun":1.5}},
	"dragoon": {
		"q": {"id":"sweep", "name":"SWEEP", "cd":7.0, "r":3.8, "arc":1.05, "dmg":1.3, "heal":0.05,
			"text":"A wide sweep of the halberd ahead: damage, and you heal 5 % of your health for each hero hit."},
		"w": {"id":"impale", "name":"IMPALE", "cd":11.0, "len":6.0, "w":1.0, "dmg":1.0, "pull":3.0, "slow":0.3, "dur":1.5,
			"text":"Thrust 6 m ahead: everyone in the line hurt, dragged 3 m toward you and slowed."},
		"e": {"id":"vault", "name":"VAULT", "cd":12.0, "dist":6.0, "emp":0.6, "dur":3.0,
			"text":"Pole-vault 6 m; your next strike within 3 s hits 60 % harder."},
		"r": {"id":"dragondive", "range":11.0, "r":3.5, "dmg":2.2, "stun":1.0}},
	"duelist": {
		"q": {"id":"thrust", "name":"LUNGE", "cd":5.0, "dist":5.0, "dmg":1.4, "refund":0.5,
			"text":"Lunge 5 m: the first enemy you meet takes a hard thrust -- a hero, and it's back twice as soon."},
		"w": {"id":"riposte", "name":"RIPOSTE", "cd":12.0, "dur":1.0, "r":3.5, "dmg":1.8, "stun":0.8,
			"text":"Parry for 1 s: nothing hurts you. If anything struck, you answer the nearest enemy: a heavy thrust and a 0.8 s stun."},
		"e": {"id":"feint", "name":"FEINT", "cd":11.0, "dist":3.5, "hide":1.5,
			"text":"Spring back 3.5 m and vanish for 1.5 s: your first strike out of it hits twice as hard."},
		"r": {"id":"challenge", "range":8.0, "n":5, "dmg":0.8, "missing":0.06}},
	"stormcaller": {
		"q": {"id":"chain", "name":"CHAIN LIGHTNING", "short":"CHAIN", "cd":7.0, "range":10.0, "jump":4.5, "n":4, "dmg":1.3,
			"fall":0.75, "text":"Lightning strikes the nearest enemy and leaps to three more near him, each a little weaker."},
		"w": {"id":"static", "name":"STATIC FIELD", "short":"STATIC", "cd":12.0, "range":9.0, "r":3.0, "dur":3.0, "dmg":0.35,
			"slow":0.3, "text":"A crackling field up to 9 m away for 3 s: enemies in it shocked and slowed 30 %."},
		"e": {"id":"gust", "name":"GUST", "cd":12.0, "r":5.0, "arc":0.8, "push":4.0, "dmg":0.5, "slow":0.3, "dur":1.5,
			"text":"A blast of wind ahead: enemies blown back 4 m and slowed."},
		"r": {"id":"thunderstorm", "range":13.0, "r":5.0, "n":8, "every":0.45, "dmg":1.1, "stun":0.35}},
	"musketeer": {
		"q": {"id":"buckshot", "name":"BUCKSHOT", "short":"BUCK", "cd":7.0, "r":7.0, "arc":0.45, "dmg":1.3, "close":1.6,
			"push":1.5, "text":"A spread of shot ahead: damage and a shove -- close up it hits much harder."},
		"w": {"id":"keg", "name":"POWDER KEG", "short":"KEG", "cd":11.0, "range":9.0, "r":3.0, "delay":0.8, "dmg":1.5, "push":2.5,
			"text":"Lob a lit keg up to 9 m: a moment later it bursts, hurting and throwing back everyone round it."},
		"e": {"id":"smokeroll", "name":"SMOKE ROLL", "short":"ROLL", "cd":10.0, "dist":4.5, "r":3.0, "zdur":3.0, "slow":0.3,
			"emp":0.6, "dur":3.0, "text":"Roll 4.5 m out of a cloud of smoke that slows enemies in it; your next shot within 3 s hits 60 % harder."},
		"r": {"id":"quickdraw", "range":15.0, "n":5, "dmg":2.0, "missing":0.12}},
	"druid": {
		"q": {"id":"rejuv", "name":"REJUVENATE", "short":"REJUV", "cd":8.0, "range":10.0, "hps":0.06, "dur":5.0,
			"text":"The most hurt ally hero near you (or you) heals 6 % of their health a second for 5 s."},
		"w": {"id":"entangle", "name":"ENTANGLE", "short":"ROOTS", "cd":12.0, "range":10.0, "r":1.8, "delay":0.5, "dmg":0.8,
			"stun":1.5, "text":"Roots burst up under an enemy up to 10 m away: hurt and held fast for 1.5 s."},
		"e": {"id":"barkskin", "name":"BARKSKIN", "short":"BARK", "cd":14.0, "range":10.0, "dr":0.3, "dur":4.0,
			"text":"Bark covers the most hurt ally hero near you (or you): 30 % less damage for 4 s."},
		"r": {"id":"wildgrowth", "r":7.0, "dur":5.0, "heal":0.025, "slow":0.3, "dmg":0.15}},
}

const DASH_SPEED := 17.0
const SHIELD_CAP := 0.6                  # (of max health: shields from several casts stack up to this)
const ZONE_EVERY := 0.5

var m                                    # moba.gd
var s                                    # siege_sim.gd
var zones: Array = []                    # {zid, spell, team, owner, at, r, until, next, dmg, slow, heal, delay_at, stun}
var traps: Array = []                    # {id, team, owner, at, armed_at, until, r, dmg, stun}
var _trap_id := 0
var _zone_id := 0
var _afflicted := {}                     # unit id -> true: someone with poison ticking (or REJUVENATE healing)
var _riposting := {}                     # unit id -> true: a Duelist parrying (RIPOSTE)

func setup(moba) -> void:
	m = moba
	s = moba.s

# ---------- what the rest reads ----------
static func role_of(hid: String) -> String:
	return str(ROLE_OF.get(hid, ""))

static func kit(hid: String, slot: String) -> Dictionary:
	return (KITS.get(hid, {}) as Dictionary).get(slot, {})

static func kit_q(hid: String) -> String:
	# 0.31.168: the hero's Q when it's a kit spell (the six new heroes), else ""
	return str(kit(hid, "q").get("id", ""))

static func cd_key(slot: String) -> String:
	return "cd_ability" if slot == "q" else "cd_" + slot

func cd(u: Dictionary, slot: String) -> float:
	return float(u.get(cd_key(slot), 0.0))

func unlocked(u: Dictionary, slot: String) -> bool:
	# 0.31.217: learnt -- a skill point spent on it (moba.learn); by level (UNLOCK) until then
	return m.rank(u, slot) > 0 if m != null else int(u.get("level", 1)) >= int(UNLOCK.get(slot, 1))

func can_cast(u: Dictionary, slot: String) -> bool:
	var k := kit(str(u.get("hid", "")), slot)
	return not k.is_empty() and bool(u.get("hero", false)) and s.alive(u) and unlocked(u, slot) and cd(u, slot) <= 0.0

func speed_mult(u: Dictionary) -> float:
	var t: float = s.time
	var k := 1.0
	if t < float(u.get("slow_until", -1.0)):
		k *= 1.0 - float(u.get("slow_k", 0.0))
	if t < float(u.get("haste_until", -1.0)):
		k *= 1.0 + float(u.get("haste_k", 0.0))
	return k

func swing_mult(u: Dictionary) -> float:
	return 1.0 / (1.0 + float(u.get("as_k", 0.0))) if s.time < float(u.get("as_until", -1.0)) else 1.0

func lifesteal_add(u: Dictionary) -> float:
	return float(u.get("ls_k", 0.0)) if s.time < float(u.get("ls_until", -1.0)) else 0.0

func taken(src: Dictionary, dst: Dictionary, a: float) -> float:
	# (moba.mod_damage, after its own multipliers) a parry, marks and curses, then shields
	var t: float = s.time
	if t < float(dst.get("parry_until", -1.0)):
		if dst.has("riposte") and a > 0.0 and int(src.get("team", -1)) != int(dst.team):
			dst.riposte["hit"] = true                 # (RIPOSTE: something struck -- he answers when the parry ends)
		return 0.0
	if t < float(dst.get("amp_until", -1.0)):
		a *= 1.0 + float(dst.get("amp_k", 0.0))
	if a > 0.0 and float(dst.get("shield", 0.0)) > 0.0:
		if t >= float(dst.get("shield_until", -1.0)):
			dst.shield = 0.0
		else:
			var took := minf(float(dst.shield), a)
			dst.shield = float(dst.shield) - took
			a -= took
	return a

func clear(u: Dictionary) -> void:
	# fallen (or back): nothing carries over
	for k in ["shield", "shield_until", "slow_until", "haste_until", "amp_until", "as_until", "ls_until", "emp_n", "poison_n",
			"parry_until", "dots", "dash", "riposte", "unstop_until"]:
		u.erase(k)
	_afflicted.erase(str(u.get("id", "")))
	_riposting.erase(str(u.get("id", "")))

# ---------- casting ----------
func spell(u: Dictionary, slot: String) -> bool:
	var k := kit(str(u.get("hid", "")), slot)
	if k.is_empty() or not k.has("id") or bool(k.get("hold", false)) or slot == "r":
		return false
	if not can_cast(u, slot) or not s.can_act(u) or u.has("dance") or int(u.get("tower", -1)) >= 0:
		return false
	var ev := {"id":u.id, "team":int(u.team), "hid":str(u.hid), "slot":slot, "spell":str(k.id), "pos":u.pos}
	u[cd_key(slot)] = float(k.cd) * m.rank_cd(u, slot)        # (before the cast: LUNGE's dash may hand half of it back)
	_pk = m.rank_power(u, slot)                   # 0.31.217: its rank's strength
	if not _cast(u, k, ev):
		u[cd_key(slot)] = 0.0
		return false
	s._event("spell", ev)
	return true

var _pk := 1.0                                    # 0.31.217: the casting skill's rank strength (spell sets it)

func _cast(u: Dictionary, k: Dictionary, ev: Dictionary) -> bool:
	var dmg := float(s.stat(u, "dmg")) * _pk
	var mhp := float(u.max_hp) * _pk
	match str(k.id):
		"bash":
			_dash(u, _move_dir(u), float(k.dist), {"dmg":dmg * float(k.dmg), "stun":float(k.stun), "first":true})
		"rally":
			var ids := []
			for o in _allies_near(u, float(k.r), true):
				_shield(o, mhp * float(k.shield), float(k.dur))
				ids.append(o.id)
			ev["ids"] = ids
			ev["r"] = float(k.r)
		"consecrate":
			_zone(u, str(k.id), u.pos, float(k.r), float(k.dur), {"dmg":dmg * float(k.dmg), "slow":float(k.slow),
				"heal":float(k.heal)})
			ev["r"] = float(k.r)
		"leap":
			var to := _aim(u, float(k.range), 6.0)
			ev["to"] = to
			_dash(u, (to - (u.pos as Vector2)).normalized() if to.distance_to(u.pos) > 0.3 else s.dir_of(u.face),
				minf(float(k.range), to.distance_to(u.pos)), {"land":{"r":float(k.r), "dmg":dmg * float(k.dmg),
				"slow":float(k.slow), "dur":float(k.dur)}, "leap":true}, 15.0)
		"bloodlust":
			u["ls_k"] = float(k.ls)
			u["ls_until"] = s.time + float(k.dur)
			_haste(u, float(k.haste), float(k.dur))
		"charge":
			_dash(u, _move_dir(u), float(k.dist), {"dmg":dmg * float(k.dmg), "through":true}, 19.0)
		"frenzy":
			s._heal(u, u, mhp * float(k.heal))
			u["as_k"] = float(k.as)
			u["as_until"] = s.time + float(k.dur)
		"caltrops":
			var at := _aim(u, float(k.range), 4.0)
			_zone(u, str(k.id), at, float(k.r), float(k.dur), {"dmg":dmg * float(k.dmg), "slow":float(k.slow)})
			ev["c"] = at
			ev["r"] = float(k.r)
		"poison":
			u["poison_n"] = int(k.n)
			u["poison_k"] = float(k.dps)
			u["poison_dur"] = float(k.dur)
		"shadowstep":
			var tgt := _hero_near(u, float(k.range))
			if tgt.is_empty():
				return false
			var behind: Vector2 = (tgt.pos as Vector2) - s.dir_of(float(tgt.face)) * 1.1
			ev["from"] = u.pos
			u.pos = s._clamp_to_field(s._push_out(behind, s.UNIT_R, int(u.team)))
			u.face = s.angle_of((tgt.pos as Vector2) - (u.pos as Vector2))
			s._next_push = s._push_from(u.pos, tgt.pos, 4.0, 1.6)
			s._damage(u, tgt, dmg * float(k.dmg))
			ev["to"] = u.pos
			ev["target"] = str(tgt.id)
		"knives":
			var d := _face_foe(u, float(k.r))
			var n := 0
			for o in _enemies_near(u, u.pos, float(k.r)):
				var off: Vector2 = (o.pos as Vector2) - (u.pos as Vector2)
				if off.length() < 0.8 or absf(d.angle_to(off)) <= float(k.arc):
					s._damage(u, o, dmg * float(k.dmg))
					_slow(o, float(k.slow), float(k.dur), u)
					n += 1
			n += m.ability_king(u, dmg * float(k.dmg), u.pos, float(k.r), d, cos(float(k.arc)))
			ev["dir"] = d
			ev["r"] = float(k.r)
			ev["n"] = n
		"tumble":
			_dash(u, _move_dir(u), float(k.dist), {}, 18.0)
			u["emp_n"] = 1
			u["emp_k"] = float(k.emp)
			u["emp_until"] = s.time + float(k.dur) + 0.4
		"snare":
			var aim := _aim(u, float(k.range), float(k.range))
			u.face = s.angle_of(aim - (u.pos as Vector2))
			_shot(u, "arrow", s.dir_of(u.face), 26.0, float(k.range), dmg * float(k.dmg), {"stun":float(k.stun), "spell":"snare"})
		"trap":
			var mine := traps.filter(func(tr): return str(tr.owner) == str(u.id))
			if mine.size() >= int(k.n):
				traps.erase(mine[0])
				s._event("trap_gone", {"trap":int(mine[0].id)})
			_trap_id += 1
			traps.append({"id":_trap_id, "team":int(u.team), "owner":str(u.id), "at":u.pos, "armed_at":s.time + float(k.arm),
				"until":s.time + float(k.life), "r":float(k.r), "dmg":dmg * float(k.dmg), "stun":float(k.stun)})
			ev["trap"] = _trap_id
		"mark":
			var tgt2 := _hero_near(u, float(k.range))
			if tgt2.is_empty():
				return false
			_amp(tgt2, float(k.amp), float(k.dur))
			for i in 3:
				m.vision.reveal(tgt2)
			tgt2["rev_until"] = maxf(float(tgt2.get("rev_until", -1.0)), s.time + float(k.dur))
			ev["target"] = str(tgt2.id)
		"pillar":
			var at2 := _aim(u, float(k.range), 7.0)
			_zone(u, str(k.id), at2, float(k.r), 0.0, {"dmg":dmg * float(k.dmg), "stun":float(k.stun),
				"delay_at":s.time + float(k.delay)})
			u.face = s.angle_of(at2 - (u.pos as Vector2))
			ev["c"] = at2
			ev["r"] = float(k.r)
			ev["delay"] = float(k.delay)
		"blink":
			var to2: Vector2 = (u.pos as Vector2) + _move_dir(u) * float(k.dist)
			ev["from"] = u.pos
			u.pos = s._clamp_to_field(s._push_out(to2, s.UNIT_R, int(u.team)))
			ev["to"] = u.pos
		"missiles":
			var pool := _enemies_near(u, u.pos, float(k.range))
			var me_p: Vector2 = u.pos
			pool.sort_custom(func(a, b): return _foe_key(a, me_p) < _foe_key(b, me_p))
			var n2 := 0
			for o in pool:
				if n2 >= int(k.n):
					break
				var dd: Vector2 = ((o.pos as Vector2) - me_p).normalized()
				_shot(u, "fire", dd, 22.0, float(k.range) + 2.0, dmg * float(k.dmg), {"spell":"missiles"})
				n2 += 1
			if n2 == 0:
				return false
		"manashield":
			_shield(u, mhp * float(k.shield), float(k.dur))
		"holylight":
			var who := _most_hurt(u, float(k.range))
			s._heal(u, who, float(who.max_hp) * float(k.heal))
			who.erase("slow_until")
			ev["target"] = str(who.id)
		"dazzle":
			var n3 := 0
			for o in _enemies_near(u, u.pos, float(k.r)):
				o.stun = maxf(float(o.stun), float(k.stun))
				m.note_cc(u, o)
				n3 += 1
			ev["r"] = float(k.r)
			ev["n"] = n3
		"boneshield":
			var who2 := _most_hurt(u, float(k.range))
			_shield(who2, float(who2.max_hp) * float(k.shield), float(k.dur))
			ev["target"] = str(who2.id)
		"curse":
			var tgt3 := _hero_near(u, float(k.range))
			if tgt3.is_empty():
				return false
			_slow(tgt3, float(k.slow), float(k.dur), u)
			_amp(tgt3, float(k.amp), float(k.dur))
			ev["target"] = str(tgt3.id)
		# ---- 0.31.168: the six new heroes ----
		"boulder":
			var aim3 := _aim(u, float(k.range), float(k.range))
			u.face = s.angle_of(aim3 - (u.pos as Vector2))
			_shot(u, "boulder", s.dir_of(u.face), 20.0, float(k.range), dmg * float(k.dmg), {"stun":float(k.stun), "spell":"boulder"})
		"stoneskin":
			_dr(u, float(k.dr), float(k.dur))
			u["unstop_until"] = s.time + float(k.dur)
			u.erase("slow_until")
		"quake":
			var n4 := 0
			for o in _enemies_near(u, u.pos, float(k.r)):
				s._next_push = s._push_from(u.pos, o.pos, 3.0, 2.0)
				s._damage(u, o, dmg * float(k.dmg))
				_slow(o, float(k.slow), float(k.dur), u)
				n4 += 1
			n4 += m.ability_king(u, dmg * float(k.dmg), u.pos, float(k.r))
			ev["r"] = float(k.r)
			ev["n"] = n4
		"sweep":
			var d3 := _face_foe(u, float(k.r) + 1.0)
			var heroes_hit := 0
			for o in _enemies_near(u, u.pos, float(k.r)):
				var off3: Vector2 = (o.pos as Vector2) - (u.pos as Vector2)
				if off3.length() < 0.8 or absf(d3.angle_to(off3)) <= float(k.arc):
					s._damage(u, o, dmg * float(k.dmg))
					if bool(o.get("hero", false)):
						heroes_hit += 1
			if heroes_hit > 0:
				s._heal(u, u, mhp * float(k.heal) * float(heroes_hit))
			m.ability_king(u, dmg * float(k.dmg), u.pos, float(k.r), d3, cos(float(k.arc)))
			ev["dir"] = d3
			ev["r"] = float(k.r)
		"impale":
			var d4 := _face_foe(u, float(k.len))
			var hit_n := 0
			for o in _enemies_near(u, u.pos, float(k.len) + 0.5):
				var off4: Vector2 = (o.pos as Vector2) - (u.pos as Vector2)
				var along := off4.dot(d4)
				if along < -0.3 or along > float(k.len) or absf(off4.cross(d4)) > float(k.w) + s.UNIT_R:
					continue
				s._damage(u, o, dmg * float(k.dmg))
				if s.alive(o) and not o.has("mon"):
					s._knockback(o, -d4 * minf(float(k.pull), maxf(0.0, along - 1.3)))
				_slow(o, float(k.slow), float(k.dur), u)
				hit_n += 1
			hit_n += m.ability_king(u, dmg * float(k.dmg), u.pos, float(k.len), d4, -2.0, float(k.w))
			ev["dir"] = d4
			ev["len"] = float(k.len)
			ev["n"] = hit_n
		"vault":
			_dash(u, _move_dir(u), float(k.dist), {"leap":true}, 15.0)
			u["emp_n"] = 1
			u["emp_k"] = float(k.emp)
			u["emp_until"] = s.time + float(k.dur) + 0.4
		"thrust":
			var d5 := _face_foe(u, float(k.dist) + 1.0)
			_dash(u, d5, float(k.dist), {"dmg":dmg * float(k.dmg), "first":true, "refund":float(k.refund)}, 20.0)
		"riposte":
			u["parry_until"] = s.time + float(k.dur)
			u["riposte"] = {"until":s.time + float(k.dur), "hit":false, "r":float(k.r), "dmg":dmg * float(k.dmg),
				"stun":float(k.stun)}
			_riposting[str(u.id)] = true
		"feint":
			var back: Vector2 = -s.dir_of(float(u.face))
			if (u.move as Vector2).length() > 0.2:
				back = (u.move as Vector2).normalized()
			_dash(u, back, float(k.dist), {}, 18.0)
			u.face = s.angle_of(-back)
			u["vanish_until"] = s.time + float(k.hide)
			s._event("vanish", {"id":u.id, "team":u.team, "until":s.time + float(k.hide)})
		"chain":
			var first := _hero_near(u, float(k.range))
			if first.is_empty():
				first = s.nearest_enemy(u, float(k.range))
			if first.is_empty():
				return false
			u.face = s.angle_of((first.pos as Vector2) - (u.pos as Vector2))
			var pts := [u.pos]
			var hit := [str(first.id)]
			var cur: Dictionary = first
			var amt := dmg * float(k.dmg)
			for i in int(k.n):
				pts.append(cur.pos)
				s._damage(u, cur, amt)
				amt *= float(k.fall)
				var nxt := {}
				var nd := float(k.jump)
				for o in _enemies_near(u, cur.pos, float(k.jump)):
					if hit.has(str(o.id)):
						continue
					var dd2: float = (o.pos as Vector2).distance_to(cur.pos) - (2.0 if bool(o.get("hero", false)) else 0.0)
					if dd2 < nd:
						nd = dd2
						nxt = o
				if nxt.is_empty():
					break
				hit.append(str(nxt.id))
				cur = nxt
			ev["pts"] = pts
		"static":
			var at3 := _aim(u, float(k.range), 6.0)
			_zone(u, str(k.id), at3, float(k.r), float(k.dur), {"dmg":dmg * float(k.dmg), "slow":float(k.slow)})
			u.face = s.angle_of(at3 - (u.pos as Vector2))
			ev["c"] = at3
			ev["r"] = float(k.r)
		"gust":
			var d6 := _face_foe(u, float(k.r))
			for o in _enemies_near(u, u.pos, float(k.r)):
				var off6: Vector2 = (o.pos as Vector2) - (u.pos as Vector2)
				if off6.length() < 0.8 or absf(d6.angle_to(off6)) <= float(k.arc):
					s._damage(u, o, dmg * float(k.dmg))
					if s.alive(o) and not o.has("mon"):
						s._knockback(o, (off6.normalized() if off6.length() > 0.1 else d6) * float(k.push))
					_slow(o, float(k.slow), float(k.dur), u)
			m.ability_king(u, dmg * float(k.dmg), u.pos, float(k.r), d6, cos(float(k.arc)))
			ev["dir"] = d6
			ev["r"] = float(k.r)
		"buckshot":
			var d7 := _face_foe(u, float(k.r))
			for o in _enemies_near(u, u.pos, float(k.r)):
				var off7: Vector2 = (o.pos as Vector2) - (u.pos as Vector2)
				if off7.length() < 0.8 or absf(d7.angle_to(off7)) <= float(k.arc):
					var close := clampf(1.0 - (off7.length() - 1.5) / (float(k.r) - 1.5), 0.0, 1.0)
					s._damage(u, o, dmg * float(k.dmg) * lerpf(1.0, float(k.close), close))
					if s.alive(o) and not o.has("mon"):
						s._knockback(o, (off7.normalized() if off7.length() > 0.1 else d7) * float(k.push))
			m.ability_king(u, dmg * float(k.dmg), u.pos, float(k.r), d7, cos(float(k.arc)))
			ev["dir"] = d7
			ev["r"] = float(k.r)
		"keg":
			var at4 := _aim(u, float(k.range), 6.0)
			_zone(u, str(k.id), at4, float(k.r), 0.0, {"dmg":dmg * float(k.dmg), "push":float(k.push),
				"delay_at":s.time + float(k.delay)})
			u.face = s.angle_of(at4 - (u.pos as Vector2))
			ev["c"] = at4
			ev["r"] = float(k.r)
			ev["delay"] = float(k.delay)
		"smokeroll":
			_zone(u, "smoke", u.pos, float(k.r), float(k.zdur), {"slow":float(k.slow)})
			_dash(u, _away_dir(u), float(k.dist), {}, 18.0)
			u["emp_n"] = 1
			u["emp_k"] = float(k.emp)
			u["emp_until"] = s.time + float(k.dur) + 0.4
			ev["r"] = float(k.r)
		"rejuv":
			var who3 := _most_hurt(u, float(k.range))
			_dot(who3, u, float(who3.max_hp) * float(k.hps), float(k.dur), true)
			ev["target"] = str(who3.id)
		"entangle":
			var tgt4 := _hero_near(u, float(k.range))
			if tgt4.is_empty():
				tgt4 = s.nearest_enemy(u, float(k.range))
			if tgt4.is_empty():
				return false
			_zone(u, str(k.id), tgt4.pos, float(k.r), 0.0, {"dmg":dmg * float(k.dmg), "stun":float(k.stun),
				"delay_at":s.time + float(k.delay), "push":0.0})
			u.face = s.angle_of((tgt4.pos as Vector2) - (u.pos as Vector2))
			ev["c"] = tgt4.pos
			ev["r"] = float(k.r)
			ev["delay"] = float(k.delay)
		"barkskin":
			var who4 := _most_hurt(u, float(k.range))
			_dr(who4, float(k.dr), float(k.dur))
			ev["target"] = str(who4.id)
		_:
			return false
	return true

# ---------- 0.31.168: the six new heroes' ultimates (moba.ult -> here; k: its rank's power) ----------
func ult(u: Dictionary, pk: float, dmg: float, ev: Dictionary) -> bool:
	var k := kit(str(u.get("hid", "")), "r")
	if k.is_empty():
		return false
	ev["spell"] = str(k.id)
	match str(k.id):
		"landslide":
			var to := _aim(u, float(k.dist), float(k.dist))
			var dir: Vector2 = (to - (u.pos as Vector2)).normalized() if to.distance_to(u.pos) > 0.5 else _move_dir(u)
			_dash(u, dir, float(k.dist), {"dmg":dmg * float(k.dmg) * pk, "through":true, "land":{"r":float(k.r),
				"dmg":dmg * float(k.land) * pk, "stun":float(k.stun)}}, 16.0)
			ev["dir"] = dir
		"dragondive":
			var tgt := _hero_near(u, float(k.range))
			var to2: Vector2 = tgt.pos if not tgt.is_empty() else _aim(u, float(k.range), 8.0)
			var off: Vector2 = to2 - (u.pos as Vector2)
			_dash(u, off.normalized() if off.length() > 0.3 else s.dir_of(u.face), minf(float(k.range), off.length()),
				{"leap":true, "land":{"r":float(k.r), "dmg":dmg * float(k.dmg) * pk, "stun":float(k.stun)}}, 14.0)
			ev["to"] = to2
		"challenge":
			var tgt2 := _hero_near(u, float(k.range))
			if tgt2.is_empty():
				return false
			var ids := []
			for i in int(k.n) + (1 if pk > 1.0 else 0):
				ids.append(str(tgt2.id))
			u["dance"] = {"ids":ids, "i":0, "next":s.time, "dmg":dmg * float(k.dmg) * pk, "missing":float(k.missing)}
			ev["target"] = str(tgt2.id)
		"thunderstorm":
			var c := _aim(u, float(k.range), 8.0)
			var n := int(k.n) + (2 if pk > 1.0 else 0)
			_zone(u, str(k.id), c, float(k.r), float(k.every) * float(n) + 0.3, {"strike":{"dmg":dmg * float(k.dmg),
				"stun":float(k.stun)}, "every":float(k.every), "next_at":s.time + 0.3})
			u.face = s.angle_of(c - (u.pos as Vector2))
			ev["c"] = c
			ev["r"] = float(k.r)
		"quickdraw":
			var pool := []
			for o in m.units_near(u.pos, float(k.range)):
				if int(o.team) != int(u.team) and int(o.team) <= 1 and s.alive(o) and bool(o.get("hero", false)) \
						and m.can_see(int(u.team), o) and (o.pos as Vector2).distance_to(u.pos) <= float(k.range):
					pool.append(o)
			if pool.is_empty():
				return false
			var me_p: Vector2 = u.pos
			pool.sort_custom(func(a, b): return (a.pos as Vector2).distance_to(me_p) < (b.pos as Vector2).distance_to(me_p))
			var ids2 := []
			var pts := []
			for o in pool.slice(0, int(k.n)):
				s._next_push = s._push_from(u.pos, o.pos, 4.0, 1.6)
				s._damage(u, o, dmg * float(k.dmg) * pk + float(k.missing) * maxf(0.0, float(o.max_hp) - float(o.hp)))
				ids2.append(str(o.id))
				pts.append(o.pos)
			u.face = s.angle_of((pts[0] as Vector2) - (u.pos as Vector2))
			ev["ids"] = ids2
			ev["pts"] = pts
		"wildgrowth":
			_zone(u, str(k.id), u.pos, float(k.r), float(k.dur), {"heal":float(k.heal) * pk, "slow":float(k.slow),
				"dmg":dmg * float(k.dmg)})
			ev["c"] = u.pos
			ev["r"] = float(k.r)
		_:
			return false
	return true

# ---------- the effects ----------
func _shield(u: Dictionary, amount: float, dur: float) -> void:
	var have := float(u.get("shield", 0.0)) if s.time < float(u.get("shield_until", -1.0)) else 0.0
	u["shield"] = minf(have + amount, float(u.max_hp) * SHIELD_CAP)
	u["shield_until"] = maxf(float(u.get("shield_until", -1.0)), s.time + dur)

func _slow(u: Dictionary, k: float, dur: float, by := {}) -> void:
	if k <= 0.0 or s.time < float(u.get("unstop_until", -1.0)):
		return                                   # (STONESKIN: slows fall off him)
	if not by.is_empty():
		m.note_cc(by, u)                         # (0.31.180: an assist if he falls soon)
	if s.time < float(u.get("slow_until", -1.0)):
		u["slow_k"] = maxf(float(u.get("slow_k", 0.0)), k)
		u["slow_until"] = maxf(float(u.slow_until), s.time + dur)
	else:
		u["slow_k"] = k
		u["slow_until"] = s.time + dur

func _haste(u: Dictionary, k: float, dur: float) -> void:
	u["haste_k"] = k
	u["haste_until"] = s.time + dur

func _amp(u: Dictionary, k: float, dur: float) -> void:
	u["amp_k"] = maxf(k, float(u.get("amp_k", 0.0)) if s.time < float(u.get("amp_until", -1.0)) else 0.0)
	u["amp_until"] = maxf(float(u.get("amp_until", -1.0)), s.time + dur)

func _dot(u: Dictionary, by: Dictionary, dps: float, dur: float, heal := false) -> void:
	# poison ticking once a second -- or (heal: 0.31.168, REJUVENATE) healing
	var dots: Array = u.get("dots", [])
	for d in dots:
		if str(d.by) == str(by.get("id", "")) and bool(d.get("heal", false)) == heal:
			d.dps = maxf(float(d.dps), dps)
			d.until = s.time + dur
			return
	dots.append({"by":str(by.get("id", "")), "team":int(by.get("team", -1)), "dps":dps, "until":s.time + dur, "next":s.time + 1.0,
		"heal":heal})
	u["dots"] = dots
	_afflicted[str(u.id)] = true

func _dr(u: Dictionary, k: float, dur: float) -> void:
	# damage taken down (moba.mod_damage reads dr / dr_until -- BULWARK's): STONESKIN, BARKSKIN
	if s.time < float(u.get("dr_until", -1.0)):
		u["dr"] = maxf(float(u.get("dr", 0.0)), k)
	else:
		u["dr"] = k
	u["dr_until"] = maxf(float(u.get("dr_until", -1.0)), s.time + dur)
	u["skin_until"] = s.time + dur                # (the view: bark or stone over him)

func _zone(u: Dictionary, kind: String, at: Vector2, r: float, dur: float, fx: Dictionary) -> void:
	_zone_id += 1
	var z := {"zid":_zone_id, "spell":kind, "team":int(u.team), "owner":str(u.id), "at":at, "r":r, "until":s.time + dur, "next":s.time}
	z.merge(fx)
	zones.append(z)

func _dash(u: Dictionary, dir: Vector2, dist: float, fx: Dictionary, speed := DASH_SPEED) -> void:
	u.state = "dash"
	u.t = dist / speed + 0.05
	u.face = s.angle_of(dir)
	u.move = Vector2.ZERO
	var dd := {"dir":dir, "left":dist, "total":dist, "speed":speed, "hits":[]}
	dd.merge(fx)
	u["dash"] = dd

func _shot(u: Dictionary, kind: String, dir: Vector2, speed: float, reach: float, dmg: float, fx: Dictionary) -> void:
	var p := {"id":s._next_proj, "team":int(u.team), "owner":u.id, "pos":(u.pos as Vector2) + dir * 0.6, "from":u.pos,
		"vel":dir * speed, "dmg":dmg, "aoe":0.0, "life":reach / speed, "kind":kind, "gate_mult":0.0, "high":false}
	p.merge(fx)
	s.projectiles.append(p)
	s._event("proj", {"pid":s._next_proj, "kind":kind})
	s._next_proj += 1

func proj_hit(p: Dictionary, hit: Dictionary) -> void:
	# (siege_sim._step_projectiles) a spell's shot struck: what it does besides the damage
	if float(p.get("slow", 0.0)) > 0.0:
		_slow(hit, float(p.slow), float(p.get("slow_dur", 1.5)), s.by_id.get(str(p.get("owner", "")), {}))

func on_basic(u: Dictionary) -> float:
	# (siege_sim._resolve_attack) a basic attack is about to land: the damage it gets (TUMBLE's empowered shot);
	# POISON BLADES' charges are spent where the hit lands (poison_hit)
	var k := 1.0
	if int(u.get("emp_n", 0)) > 0:
		if s.time < float(u.get("emp_until", -1.0)):
			k += float(u.get("emp_k", 0.0))
		u.emp_n = int(u.emp_n) - 1
	return k

func poison_hit(src: Dictionary, dst: Dictionary, amount: float) -> void:
	# (moba.on_damage: a basic hit by someone with POISON BLADES' charges)
	if int(src.get("poison_n", 0)) <= 0 or int(dst.get("team", -1)) == int(src.team) or amount <= 0.0:
		return
	src.poison_n = int(src.poison_n) - 1
	_dot(dst, src, float(s.stat(src, "dmg")) * float(src.get("poison_k", 0.25)), float(src.get("poison_dur", 4.0)))

# ---------- stepping ----------
func step(dt: float) -> void:
	for i in range(zones.size() - 1, -1, -1):
		var z: Dictionary = zones[i]
		var owner: Dictionary = s.by_id.get(str(z.owner), {"team":int(z.team), "id":""})
		if z.has("delay_at"):
			if s.time < float(z.delay_at):
				continue
			for o in _enemies_near(owner, z.at, float(z.r) + s.UNIT_R):
				if float(z.get("push", -1.0)) != 0.0:
					s._next_push = s._push_from(z.at, o.pos, 5.0, 3.0)
				s._damage(owner, o, float(z.dmg), float(z.get("stun", 0.0)))
				if float(z.get("push", 0.0)) > 0.0 and s.alive(o) and not o.has("mon"):
					var away: Vector2 = (o.pos as Vector2) - (z.at as Vector2)
					s._knockback(o, (away.normalized() if away.length() > 0.1 else Vector2.from_angle(s.rng.randf() * TAU)) \
						* float(z.push) * (1.0 - 0.5 * clampf(away.length() / float(z.r), 0.0, 1.0)))
			if float(z.get("dmg", 0.0)) > 0.0:
				m.ability_king(owner, float(z.dmg), z.at, float(z.r))       # (0.31.179: abilities hurt the King)
			# (the fire pillar's own event; 0.31.168: the Musketeer's keg and the Druid's roots a "burst")
			if str(z.spell) == "pillar":
				s._event("pillar", {"c":z.at, "r":float(z.r), "team":int(z.team)})
			else:
				s._event("burst", {"spell":str(z.spell), "c":z.at, "r":float(z.r), "team":int(z.team)})
			zones.remove_at(i)
			continue
		if s.time >= float(z.until):
			zones.remove_at(i)
			continue
		if z.has("strike"):
			# 0.31.168: THUNDERSTORM -- a bolt every `every` s onto an enemy under it (heroes first), else the ground
			if s.time >= float(z.next_at):
				z.next_at = float(z.next_at) + float(z.every)
				var pool := _enemies_near(owner, z.at, float(z.r))
				var pick := {}
				for o in pool:
					if pick.is_empty() or (bool(o.get("hero", false)) and not bool(pick.get("hero", false))) \
							or (bool(o.get("hero", false)) == bool(pick.get("hero", false)) and s.rng.randf() < 0.5):
						pick = o
				# (0.31.179: the enemy King under it counts as a hero)
				var kt: int = m.king_in_reach(owner, z.at, float(z.r)) if (pick.is_empty() or not bool(pick.get("hero", false))) else -1
				if kt >= 0:
					pick = {}
				var spot: Vector2 = m.king_pos(kt) if kt >= 0 else (pick.pos if not pick.is_empty() else (z.at as Vector2) + Vector2.from_angle(s.rng.randf() * TAU) \
					* sqrt(s.rng.randf()) * float(z.r))
				if kt >= 0:
					m.hit_king(owner, kt, float(z.strike.dmg))
				elif not pick.is_empty():
					s._damage(owner, pick, float(z.strike.dmg), float(z.strike.stun))
				s._event("zap", {"c":spot, "team":int(z.team), "id":str(pick.get("id", ""))})
			continue
		if s.time < float(z.next):
			continue
		z.next = float(z.next) + ZONE_EVERY
		for o in m.units_near(z.at, float(z.r) + 1.0):
			if not s.alive(o) or (o.pos as Vector2).distance_to(z.at) > float(z.r):
				continue
			if int(o.team) != int(z.team):
				if float(z.get("dmg", 0.0)) > 0.0:
					s._damage(owner, o, float(z.dmg))
				if float(z.get("slow", 0.0)) > 0.0:
					_slow(o, float(z.slow), ZONE_EVERY + 0.15, owner)
			elif float(z.get("heal", 0.0)) > 0.0 and (bool(o.get("hero", false)) or bool(o.get("minion", false))):
				s._heal(owner, o, float(o.max_hp) * float(z.heal))
		if float(z.get("dmg", 0.0)) > 0.0:
			m.ability_king(owner, float(z.dmg), z.at, float(z.r))          # (0.31.179: the King in it)
	for i in range(traps.size() - 1, -1, -1):
		var tr: Dictionary = traps[i]
		if s.time >= float(tr.until):
			traps.remove_at(i)
			s._event("trap_gone", {"trap":int(tr.id)})
			continue
		if s.time < float(tr.armed_at):
			continue
		for o in m.units_near(tr.at, float(tr.r) + 1.0):
			if int(o.team) == int(tr.team) or int(o.team) > 1 or not s.alive(o) \
					or (o.pos as Vector2).distance_to(tr.at) > float(tr.r):
				continue
			var owner2: Dictionary = s.by_id.get(str(tr.owner), {"team":int(tr.team), "id":""})
			s._damage(owner2, o, float(tr.dmg), float(tr.stun))
			m.vision.reveal(o)
			s._event("trap_snap", {"trap":int(tr.id), "id":o.id, "pos":tr.at})
			traps.remove_at(i)
			break
	if not _afflicted.is_empty():
		for id in _afflicted.keys():
			var u: Dictionary = s.by_id.get(str(id), {})
			if u.is_empty() or not s.alive(u) or not u.has("dots"):
				_afflicted.erase(id)
				continue
			var dots: Array = u.dots
			for j in range(dots.size() - 1, -1, -1):
				var d: Dictionary = dots[j]
				if s.time >= float(d.next):
					d.next = float(d.next) + 1.0
					var by: Dictionary = s.by_id.get(str(d.by), {"team":int(d.team), "id":""})
					if bool(d.get("heal", false)):
						s._heal(by, u, float(d.dps))
					else:
						s._damage(by, u, float(d.dps))
					if not s.alive(u):
						break
				if s.time >= float(d.until):
					dots.remove_at(j)
			if dots.is_empty():
				u.erase("dots")
				_afflicted.erase(id)
	if not _riposting.is_empty():
		# 0.31.168 RIPOSTE: when the parry ends -- if anything struck him, he answers the nearest enemy
		for id2 in _riposting.keys():
			var du: Dictionary = s.by_id.get(str(id2), {})
			if du.is_empty() or not s.alive(du) or not du.has("riposte"):
				_riposting.erase(id2)
				continue
			var rp: Dictionary = du.riposte
			if s.time < float(rp.until):
				continue
			_riposting.erase(id2)
			du.erase("riposte")
			if not bool(rp.hit):
				continue
			var foe := {}
			var fd := float(rp.r)
			for o in _enemies_near(du, du.pos, float(rp.r)):
				var dd: float = (o.pos as Vector2).distance_to(du.pos) - (1.5 if bool(o.get("hero", false)) else 0.0)
				if dd < fd:
					fd = dd
					foe = o
			if foe.is_empty():
				continue
			du.face = s.angle_of((foe.pos as Vector2) - (du.pos as Vector2))
			s._next_push = s._push_from(du.pos, foe.pos, 4.0, 1.8)
			s._damage(du, foe, float(rp.dmg), float(rp.stun))
			s._event("riposte", {"id":du.id, "target":str(foe.id), "pos":foe.pos})
			s._event("attack", {"id":du.id, "kind":"attack", "ability":"", "combo":2})

func step_dash(u: Dictionary, dt: float) -> void:
	# (siege_sim._step_unit, state "dash") along the line; who it hits on the way; what it does when it lands
	var dd: Dictionary = u.get("dash", {})
	u.t -= dt
	if dd.is_empty():
		u.state = "idle"
		return
	var step_len := minf(float(dd.left), float(dd.speed) * dt)
	u.pos += (dd.dir as Vector2) * step_len
	dd.left = float(dd.left) - step_len
	if float(dd.get("dmg", 0.0)) > 0.0 and not (bool(dd.get("first", false)) and not (dd.hits as Array).is_empty()):
		for o in m.units_near(u.pos, 2.0):
			if int(o.team) == int(u.team) or not s.alive(o) or (dd.hits as Array).has(o.id):
				continue
			if (o.pos as Vector2).distance_to(u.pos) > s.UNIT_R * 2.0 + 0.35:
				continue
			(dd.hits as Array).append(o.id)
			s._next_push = s._push_from(u.pos, o.pos, 4.0, 1.8)
			s._damage(u, o, float(dd.dmg), float(dd.get("stun", 0.0)))
			if float(dd.get("refund", 0.0)) > 0.0 and bool(o.get("hero", false)):
				u.cd_ability = float(u.cd_ability) * float(dd.refund)       # (LUNGE: a hero -- back twice as soon)
			if bool(dd.get("through", false)) and s.alive(o):
				var side := Vector2(-(dd.dir as Vector2).y, (dd.dir as Vector2).x)
				if side.dot((o.pos as Vector2) - (u.pos as Vector2)) < 0.0:
					side = -side
				o.pos = s._clamp_to_field(s._push_out((o.pos as Vector2) + side * 1.2, s.UNIT_R, int(o.team)))
			if bool(dd.get("first", false)):
				dd.left = 0.0                      # (SHIELD BASH stops on the first)
				break
		if not (dd.hits as Array).has("king") and float(dd.left) > 0.0 \
				and m.king_in_reach(u, u.pos, s.UNIT_R + 0.35) >= 0:
			(dd.hits as Array).append("king")       # (0.31.179: the King on the way, once)
			m.ability_king(u, float(dd.dmg), u.pos, s.UNIT_R + 0.35)
			if bool(dd.get("first", false)):
				dd.left = 0.0
	if float(dd.left) <= 0.001 or u.t <= 0.0:
		var land: Dictionary = dd.get("land", {})
		if not land.is_empty():
			for o in _enemies_near(u, u.pos, float(land.r)):
				s._next_push = s._push_from(u.pos, o.pos, 5.0, 2.6)
				s._damage(u, o, float(land.dmg), float(land.get("stun", 0.0)))
				_slow(o, float(land.get("slow", 0.0)), float(land.get("dur", 1.0)), u)
			m.ability_king(u, float(land.dmg), u.pos, float(land.r))
			s._event("slam", {"id":u.id, "pos":u.pos, "r":float(land.r)})
		u.erase("dash")
		u.state = "recover"
		u.t = 0.12

# ---------- aiming ----------
func _move_dir(u: Dictionary) -> Vector2:
	var mv: Vector2 = u.move
	return mv.normalized() if mv.length() > 0.2 else s.dir_of(float(u.face))

func _away_dir(u: Dictionary) -> Vector2:
	# (0.31.168, SMOKE ROLL) the way you're going -- standing still, away from the nearest enemy (else back)
	var mv: Vector2 = u.move
	if mv.length() > 0.2:
		return mv.normalized()
	var foe: Dictionary = s.nearest_enemy(u, 10.0)
	if not foe.is_empty() and (foe.pos as Vector2).distance_to(u.pos) > 0.1:
		return ((u.pos as Vector2) - (foe.pos as Vector2)).normalized()
	return -s.dir_of(float(u.face))

func _hero_near(u: Dictionary, r: float) -> Dictionary:
	var best := {}
	var bd := r
	for o in m.units_near(u.pos, r):
		if int(o.team) == int(u.team) or int(o.team) > 1 or not s.alive(o) or not bool(o.get("hero", false)) \
				or not m.can_see(int(u.team), o):
			continue
		var d: float = (o.pos as Vector2).distance_to(u.pos)
		if d <= bd:
			bd = d
			best = o
	return best

func _aim(u: Dictionary, r: float, ahead: float) -> Vector2:
	# the nearest enemy hero in reach, else the nearest enemy, else ahead
	var h := _hero_near(u, r)
	if h.is_empty():
		h = s.nearest_enemy(u, r)
	if not h.is_empty():
		return h.pos
	return s._clamp_to_field((u.pos as Vector2) + _move_dir(u) * ahead)

func _face_foe(u: Dictionary, r: float) -> Vector2:
	var h := _hero_near(u, r)
	if h.is_empty():
		h = s.nearest_enemy(u, r)
	if not h.is_empty() and (h.pos as Vector2).distance_to(u.pos) > 0.2:
		u.face = s.angle_of((h.pos as Vector2) - (u.pos as Vector2))
	return s.dir_of(float(u.face))

func _enemies_near(u: Dictionary, at: Vector2, r: float) -> Array:
	var out := []
	for o in m.units_near(at, r):
		if int(o.team) != int(u.get("team", -1)) and s.alive(o) and (o.pos as Vector2).distance_to(at) <= r:
			if o.has("mon") and str(m.camps[int(o.mon)].target) == "" and int(u.get("team", -1)) <= 1:
				continue                           # (sleeping monsters are left out of area spells)
			out.append(o)
	return out

func _allies_near(u: Dictionary, r: float, heroes_only: bool) -> Array:
	var out := []
	for o in m.units_near(u.pos, r):
		if int(o.team) == int(u.team) and s.alive(o) and (o.pos as Vector2).distance_to(u.pos) <= r \
				and (not heroes_only or bool(o.get("hero", false))):
			out.append(o)
	return out

func _most_hurt(u: Dictionary, r: float) -> Dictionary:
	var best := u
	var bf := float(u.hp) / maxf(1.0, float(u.max_hp))
	for o in _allies_near(u, r, true):
		var f := float(o.hp) / maxf(1.0, float(o.max_hp))
		if f < bf:
			bf = f
			best = o
	return best

func _foe_key(o: Dictionary, p: Vector2) -> float:
	return (0.0 if bool(o.get("hero", false)) else 100.0) + (o.pos as Vector2).distance_to(p)

# ---------- bots ----------
func bot_spells(u: Dictionary) -> bool:
	# a bot's W or E when it's worth it (moba._think_hero, after the ultimate)
	if not s.can_act(u):
		return false
	var hid := str(u.hid)
	for slot in ["q", "w", "e"]:                  # (0.31.168: Q too, for the heroes whose Q is a kit spell)
		var k := kit(hid, slot)
		if k.is_empty() or not k.has("id") or bool(k.get("hold", false)) or not can_cast(u, slot):
			continue
		if _worth(u, k) and spell(u, slot):
			return true
	return false

func _worth(u: Dictionary, k: Dictionary) -> bool:
	var hp := float(u.hp) / maxf(1.0, float(u.max_hp))
	var foe := _hero_near(u, float(k.get("range", 7.0)))
	var near_foes := _enemies_near(u, u.pos, 5.0).size()
	match str(k.id):
		"bash", "leap", "shadowstep", "curse", "mark", "pillar", "snare", "missiles":
			return not foe.is_empty() or (str(k.id) in ["missiles", "pillar"] and near_foes >= 3)
		"charge", "knives", "dazzle":
			return not _hero_near(u, 5.0).is_empty() or near_foes >= 3
		"caltrops":
			return not foe.is_empty()
		"rally", "manashield":
			return hp < 0.6 and (near_foes > 0 or not _hero_near(u, 10.0).is_empty())
		"consecrate", "bloodlust", "frenzy", "poison":
			return near_foes > 0 and (not _hero_near(u, 6.0).is_empty() or near_foes >= 2 or hp < 0.5)
		"holylight", "boneshield":
			var who := _most_hurt(u, float(k.range))
			return float(who.hp) / maxf(1.0, float(who.max_hp)) < 0.55
		"tumble", "blink":
			return (hp < 0.35 and near_foes > 0) or (not _hero_near(u, 3.0).is_empty() and hp < 0.6)
		"trap":
			return near_foes == 0 and not s.in_castle(u.pos, int(u.team)) \
				and traps.filter(func(tr): return str(tr.owner) == str(u.id)).size() < int(k.n)
		# ---- 0.31.168 ----
		"boulder", "entangle", "static", "keg":
			return not foe.is_empty() or (str(k.id) in ["static", "keg"] and near_foes >= 3)
		"chain":
			return not foe.is_empty() or _enemies_near(u, u.pos, float(k.range)).size() >= 3
		"thrust", "impale":
			var r2 := float(k.get("dist", k.get("len", 5.0)))
			return not _hero_near(u, r2).is_empty() and (hp > 0.35 or str(k.id) == "impale")
		"sweep", "quake", "buckshot", "gust":
			var reach := float(k.r) * (0.6 if str(k.id) in ["buckshot", "gust"] else 0.9)
			return not _hero_near(u, reach).is_empty() or _enemies_near(u, u.pos, reach).size() >= 3 \
				or (str(k.id) == "gust" and hp < 0.5 and near_foes > 0)
		"stoneskin":
			return near_foes > 0 and (hp < 0.6 or not _hero_near(u, 4.0).is_empty())
		"riposte":
			return not _hero_near(u, 2.6).is_empty() and hp < 0.85
		"vault", "smokeroll", "feint":
			return (hp < 0.35 and near_foes > 0) or (str(k.id) == "vault" and hp > 0.6 and not _hero_near(u, 7.0).is_empty()
				and _hero_near(u, 3.0).is_empty())
		"rejuv":
			var who3 := _most_hurt(u, float(k.range))
			return float(who3.hp) / maxf(1.0, float(who3.max_hp)) < 0.7 and not who3.has("dots")
		"barkskin":
			var who4 := _most_hurt(u, float(k.range))
			return float(who4.hp) / maxf(1.0, float(who4.max_hp)) < 0.5 and not _enemies_near(u, who4.pos, 6.0).is_empty()
	return false

func bot_ult(u: Dictionary, near_h: int, near_any: int, closest: Dictionary, cd_h: float, lord_fight: bool) -> bool:
	# (moba._bot_ult) when the six new heroes' ultimates are worth it; near_h / near_any within 7 m
	var k := kit(str(u.get("hid", "")), "r")
	var hp := float(u.hp) / maxf(1.0, float(u.max_hp))
	match str(k.get("id", "")):
		"landslide":
			return (near_h >= 1 and (near_any >= 2 or hp < 0.5)) or lord_fight
		"dragondive":
			return (not closest.is_empty() and cd_h <= float(k.range) and (float(closest.hp) < float(closest.max_hp) * 0.6
				or near_any >= 2)) or lord_fight
		"challenge":
			return not closest.is_empty() and cd_h <= float(k.range) and float(closest.hp) < float(closest.max_hp) * 0.65
		"thunderstorm":
			if closest.is_empty() or cd_h > float(k.range):
				return lord_fight
			return _enemies_near(u, closest.pos, float(k.r)).size() >= 3 or float(closest.hp) < float(closest.max_hp) * 0.4
		"quickdraw":
			var seen := 0
			var low := false
			for o in m.units_near(u.pos, float(k.range)):
				if int(o.team) != int(u.team) and int(o.team) <= 1 and s.alive(o) and bool(o.get("hero", false)) \
						and m.can_see(int(u.team), o):
					seen += 1
					low = low or float(o.hp) < float(o.max_hp) * 0.35
			return seen >= 2 or low
		"wildgrowth":
			var hurt := 0
			for o in _allies_near(u, float(k.r), true):
				if float(o.hp) < float(o.max_hp) * 0.6:
					hurt += 1
			return (hurt >= 2 and near_any > 0) or (hp < 0.3 and near_h > 0) or lord_fight
	return false
