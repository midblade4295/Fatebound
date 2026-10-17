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

const ROLE_ORDER := ["tank", "fighter", "assassin", "mage", "marksman", "support"]
const ROLE_NAMES := {"tank":"TANK", "fighter":"FIGHTER", "assassin":"ASSASSIN", "mage":"MAGE", "marksman":"MARKSMAN",
	"support":"SUPPORT"}
const ROLE_TEXT := {"tank":"Takes the hits and holds the line.", "fighter":"Fights up close and keeps going.",
	"assassin":"Gets in, takes out a hero, gets out.", "mage":"Spells from range: big damage, control.",
	"marksman":"Steady damage from range; carries late.", "support":"Heals, shields and sets up the team."}
const ROLE_OF := {"knight":"tank", "crusader":"tank", "barbarian":"fighter", "berserker":"fighter", "rogue":"assassin",
	"assassin":"assassin", "ranger":"marksman", "sniper":"marksman", "mage":"mage", "archmage":"mage", "priest":"support",
	"necromancer":"support"}
const UNLOCK := {"q":1, "w":2, "e":3}

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
var _afflicted := {}                     # unit id -> true: someone with poison ticking

func setup(moba) -> void:
	m = moba
	s = moba.s

# ---------- what the rest reads ----------
static func role_of(hid: String) -> String:
	return str(ROLE_OF.get(hid, ""))

static func kit(hid: String, slot: String) -> Dictionary:
	return (KITS.get(hid, {}) as Dictionary).get(slot, {})

func cd(u: Dictionary, slot: String) -> float:
	return float(u.get("cd_" + slot, 0.0))

func unlocked(u: Dictionary, slot: String) -> bool:
	return int(u.get("level", 1)) >= int(UNLOCK.get(slot, 1))

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
			"parry_until", "dots", "dash"]:
		u.erase(k)
	_afflicted.erase(str(u.get("id", "")))

# ---------- casting ----------
func spell(u: Dictionary, slot: String) -> bool:
	var k := kit(str(u.get("hid", "")), slot)
	if k.is_empty() or bool(k.get("hold", false)):
		return false
	if not can_cast(u, slot) or not s.can_act(u) or u.has("dance") or int(u.get("tower", -1)) >= 0:
		return false
	var ev := {"id":u.id, "team":int(u.team), "hid":str(u.hid), "slot":slot, "spell":str(k.id), "pos":u.pos}
	if not _cast(u, k, ev):
		return false
	u["cd_" + slot] = float(k.cd)
	s._event("spell", ev)
	return true

func _cast(u: Dictionary, k: Dictionary, ev: Dictionary) -> bool:
	var dmg := float(s.stat(u, "dmg"))
	var mhp := float(u.max_hp)
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
					_slow(o, float(k.slow), float(k.dur))
					n += 1
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
			_slow(tgt3, float(k.slow), float(k.dur))
			_amp(tgt3, float(k.amp), float(k.dur))
			ev["target"] = str(tgt3.id)
		_:
			return false
	return true

# ---------- the effects ----------
func _shield(u: Dictionary, amount: float, dur: float) -> void:
	var have := float(u.get("shield", 0.0)) if s.time < float(u.get("shield_until", -1.0)) else 0.0
	u["shield"] = minf(have + amount, float(u.max_hp) * SHIELD_CAP)
	u["shield_until"] = maxf(float(u.get("shield_until", -1.0)), s.time + dur)

func _slow(u: Dictionary, k: float, dur: float) -> void:
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

func _dot(u: Dictionary, by: Dictionary, dps: float, dur: float) -> void:
	var dots: Array = u.get("dots", [])
	for d in dots:
		if str(d.by) == str(by.get("id", "")):
			d.dps = maxf(float(d.dps), dps)
			d.until = s.time + dur
			return
	dots.append({"by":str(by.get("id", "")), "team":int(by.get("team", -1)), "dps":dps, "until":s.time + dur, "next":s.time + 1.0})
	u["dots"] = dots
	_afflicted[str(u.id)] = true

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
	u.task = {}
	var dd := {"dir":dir, "left":dist, "speed":speed, "hits":[]}
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
		_slow(hit, float(p.slow), float(p.get("slow_dur", 1.5)))

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
				s._next_push = s._push_from(z.at, o.pos, 5.0, 3.0)
				s._damage(owner, o, float(z.dmg), float(z.get("stun", 0.0)))
			s._event("pillar", {"c":z.at, "r":float(z.r), "team":int(z.team)})
			zones.remove_at(i)
			continue
		if s.time >= float(z.until):
			zones.remove_at(i)
			continue
		if s.time < float(z.next):
			continue
		z.next = float(z.next) + ZONE_EVERY
		for o in m.units_near(z.at, float(z.r) + 1.0):
			if not s.alive(o) or o.state == "fly" or (o.pos as Vector2).distance_to(z.at) > float(z.r):
				continue
			if int(o.team) != int(z.team):
				if float(z.get("dmg", 0.0)) > 0.0:
					s._damage(owner, o, float(z.dmg))
				if float(z.get("slow", 0.0)) > 0.0:
					_slow(o, float(z.slow), ZONE_EVERY + 0.15)
			elif float(z.get("heal", 0.0)) > 0.0 and (bool(o.get("hero", false)) or bool(o.get("minion", false))):
				s._heal(owner, o, float(o.max_hp) * float(z.heal))
	for i in range(traps.size() - 1, -1, -1):
		var tr: Dictionary = traps[i]
		if s.time >= float(tr.until):
			traps.remove_at(i)
			s._event("trap_gone", {"trap":int(tr.id)})
			continue
		if s.time < float(tr.armed_at):
			continue
		for o in m.units_near(tr.at, float(tr.r) + 1.0):
			if int(o.team) == int(tr.team) or int(o.team) > 1 or not s.alive(o) or o.state == "fly" \
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
					s._damage(by, u, float(d.dps))
					if not s.alive(u):
						break
				if s.time >= float(d.until):
					dots.remove_at(j)
			if dots.is_empty():
				u.erase("dots")
				_afflicted.erase(id)

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
			if int(o.team) == int(u.team) or not s.alive(o) or o.state == "fly" or (dd.hits as Array).has(o.id):
				continue
			if (o.pos as Vector2).distance_to(u.pos) > s.UNIT_R * 2.0 + 0.35:
				continue
			(dd.hits as Array).append(o.id)
			s._next_push = s._push_from(u.pos, o.pos, 4.0, 1.8)
			s._damage(u, o, float(dd.dmg), float(dd.get("stun", 0.0)))
			if bool(dd.get("through", false)) and s.alive(o):
				var side := Vector2(-(dd.dir as Vector2).y, (dd.dir as Vector2).x)
				if side.dot((o.pos as Vector2) - (u.pos as Vector2)) < 0.0:
					side = -side
				o.pos = s._clamp_to_field(s._push_out((o.pos as Vector2) + side * 1.2, s.UNIT_R, int(o.team)))
			if bool(dd.get("first", false)):
				dd.left = 0.0                      # (SHIELD BASH stops on the first)
				break
	if float(dd.left) <= 0.001 or u.t <= 0.0:
		var land: Dictionary = dd.get("land", {})
		if not land.is_empty():
			for o in _enemies_near(u, u.pos, float(land.r)):
				s._next_push = s._push_from(u.pos, o.pos, 5.0, 2.6)
				s._damage(u, o, float(land.dmg))
				_slow(o, float(land.get("slow", 0.0)), float(land.get("dur", 1.0)))
			s._event("slam", {"id":u.id, "pos":u.pos, "r":float(land.r)})
		u.erase("dash")
		u.state = "recover"
		u.t = 0.12

# ---------- aiming ----------
func _move_dir(u: Dictionary) -> Vector2:
	var mv: Vector2 = u.move
	return mv.normalized() if mv.length() > 0.2 else s.dir_of(float(u.face))

func _hero_near(u: Dictionary, r: float) -> Dictionary:
	var best := {}
	var bd := r
	for o in m.units_near(u.pos, r):
		if int(o.team) == int(u.team) or int(o.team) > 1 or not s.alive(o) or not bool(o.get("hero", false)) \
				or o.state == "fly" or not m.can_see(int(u.team), o):
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
		if int(o.team) != int(u.get("team", -1)) and s.alive(o) and o.state != "fly" and (o.pos as Vector2).distance_to(at) <= r:
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
	for slot in ["w", "e"]:
		var k := kit(hid, slot)
		if k.is_empty() or bool(k.get("hold", false)) or not can_cast(u, slot):
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
	return false
