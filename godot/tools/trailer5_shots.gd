extends SceneTree
# Fatebound trailer 5 (Kevin: "an all new trailer from scratch ... catch someone's eye ... start off exciting ... show how
# the game works and the objective in a natural way ... no captions, the Herald voicing it, comedic ... new music ...
# cinematic shots, the Necromancer casting in slow motion, a blade striking someone and the blood spraying out in slow
# motion ... the final climax with the title"). Landscape 1920x1080. Built on trailer 2's staged shots (captive, heroes,
# breakin, toofat, carry2, throne, whirl, clash, ...) with new ones: "hook" (an axe strike in slow motion), "necro"
# (the Necromancer's drain and heal beams in slow motion), "hammer" (the Crusader's throw in slow motion).
# One shot per run with Movie Maker (see /tmp/trailer4/render.sh for the override.cfg and exit handling):
#   SHOT=<shot> godot --rendering-method mobile --fixed-fps 30 --write-movie /tmp/trailer5/<shot>.avi -s res://tools/trailer5_shots.gd
# SLOW: time-scale windows per shot (game seconds); LENGTH is game seconds, so slowed parts take more frames.
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Castle = preload("res://scripts/siege/siege_castle.gd")
const SLOW := {"hook": [[0.95, 2.1, 0.18]], "necro": [[0.6, 2.6, 0.25]], "hammer": [[0.55, 1.75, 0.22]], "whirl": [[0.8, 2.4, 0.22]]}
const LENGTH := {"hook": 2.6, "necro": 3.0, "hammer": 2.4, "dawn": 5.0, "clash": 4.5, "captive": 4.0, "heroes": 4.3, "lineup": 4.0, "gather": 4.0, "build": 7.0, "backstab": 4.0, "assault": 5.5,
	"rampart": 4.0, "whirl": 3.2, "feast": 4.0, "carry": 5.0, "throne": 4.0, "reveal": 9.0,
	# Round 28 (Kevin + Derek Lieu's makeover advice: core action first, struggle, comedy, fewer cards)
	"breakin": 10.6, "carry2": 7.9, "toofat": 5.5, "hatsteal": 5.0}
const SUN_DIR := Vector3(0.0, 0.16, -1.0)        # where the reveal's sun sits: low, beyond the enemy castle
var mode
var shot := "dawn"
var frames := 0
var t := 0.0
var cam_a := []
var cam_b := []
var orbit := {}
var follow := ""
var follow_king := -1        # camera tracks this team's King (cam_a/cam_b are offsets from him)
var walkers := {}
var chasers := []
var beats := []
var sun_track := []

func _init() -> void:
	shot = OS.get_environment("SHOT") if OS.has_environment("SHOT") else "dawn"
	mode = Mode.new()
	mode.hq_gfx = true          # High-quality graphics (render with FB_FORCE_HQ=1: the view keeps HQ off on llvmpipe otherwise)
	root.add_child(mode)

func _v(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)

func _revive(u: Dictionary) -> void:
	u.state = "idle"
	u.max_hp = float(mode.sim.stat(u, "hp"))
	u.hp = u.max_hp
	u.respawn_at = 0.0
	u.stun = 0.0

func _sturdy(u: Dictionary) -> void:
	u.max_hp = 5000.0
	u.hp = 5000.0

func _golden_hour() -> void:
	var d := SUN_DIR.normalized()
	for l in mode.view.find_children("*", "DirectionalLight3D", true, false):
		var sun: DirectionalLight3D = l
		sun.global_transform.basis = Basis.looking_at(-d)
		sun.light_color = Color("#ffc98a")
		sun.light_energy = 1.25
		sun.light_angular_distance = 2.5
	for w in mode.view.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (w as WorldEnvironment).environment
		var sm := env.sky.sky_material as ProceduralSkyMaterial
		if sm != null:
			sm.sky_top_color = Color("#4d6fa8")
			sm.sky_horizon_color = Color("#ffb877")
			sm.ground_horizon_color = Color("#f6bf8c")
			sm.ground_bottom_color = Color("#f6bf8c")
			sm.sun_angle_max = 40.0
			sm.sun_curve = 0.08
		env.fog_light_color = Color("#f2c192")

func _stage() -> void:
	var s = mode.sim
	var me: Dictionary = s.by_id[mode.hud.player_id]
	mode.hud.visible = false
	mode.hud.diag = null
	for u in s.units:
		_revive(u)
		u.bot = true
	match shot:
		"hook":
			# The opening: their Barbarian's axe comes down on our Knight -- slow motion as it lands, blood in the air.
			var spot := Vector2(-10.0, 30.0)
			var kn: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != me.id)[0]
			var bb: Dictionary = s.units.filter(func(x): return x.team == 1)[0]
			s._set_class(kn, "knight", false)
			s._set_class(bb, "barbarian", true)
			for u in [kn, bb]:
				u.bot = false
				_revive(u)
			kn.pos = spot
			bb.pos = spot + Vector2(1.5, -0.4)
			kn.face = Sim.angle_of((bb.pos as Vector2) - (kn.pos as Vector2))
			bb.face = Sim.angle_of((kn.pos as Vector2) - (bb.pos as Vector2))
			_sturdy(kn)                      # he takes the blow (no dying into a villager mid-shot)
			set_meta("bleed", kn.id)
			for u in s.units:
				if u.id != kn.id and u.id != bb.id:
					u.bot = false
					u.move = Vector2.ZERO
					u.pos = Sim.spawn(u.team)
			beats = [[0.35, kn.id, "attack"], [0.75, bb.id, "smash"]]
			cam_a = [_v(spot + Vector2(-1.4, 2.9), 1.15), _v(spot + Vector2(0.9, -0.3), 1.0)]
			cam_b = [_v(spot + Vector2(1.6, 4.4), 1.9), _v(spot + Vector2(-0.4, 0.2), 0.6)]   # eases round to see him land
		"necro":
			# The Necromancer in slow motion: green life-drain on their Knight, the white heal on our wounded Rogue.
			var c := Vector2(-6.0, 30.0)
			var nc: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != me.id)[0]
			var foe: Dictionary = s.units.filter(func(x): return x.team == 1)[0]
			var ally: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != me.id)[1]
			s._set_class(nc, "priest", true)
			s._set_class(foe, "knight", false)
			s._set_class(ally, "rogue", false)
			for u in [nc, foe, ally]:
				u.bot = false
				_revive(u)
				u.move = Vector2.ZERO
			nc.pos = c
			foe.pos = c + Vector2(-2.6, 3.4)       # front-left (towards the camera): the green drain -- he faces it
			ally.pos = c + Vector2(3.0, 2.2)       # front-right: the white heal
			_sturdy(foe)
			ally.max_hp = 400.0
			ally.hp = 60.0
			foe.face = Sim.angle_of((nc.pos as Vector2) - (foe.pos as Vector2))
			for u in s.units:
				if u.id != nc.id and u.id != foe.id and u.id != ally.id:
					u.bot = false
					u.move = Vector2.ZERO
					u.pos = Sim.spawn(u.team)
			set_meta("necro", nc.id)
			# (trailer 5, Kevin) from the front, pulled back so the Knight he drains and the Rogue he heals are both in frame
			cam_a = [_v(c + Vector2(-0.6, 8.6), 2.7), _v(c + Vector2(0.0, -1.6), 1.0)]
			cam_b = [_v(c + Vector2(0.7, 7.6), 2.4), _v(c + Vector2(0.0, -1.6), 1.05)]
		"hammer":
			# The Crusader's hammer in slow motion, spinning through a line of three.
			var hc := Vector2(-14.0, 32.0)
			var cr: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != me.id)[0]
			s._set_class(cr, "knight", true)
			cr.bot = false
			_revive(cr)
			cr.pos = hc
			cr.face = Sim.angle_of(Vector2(1, 0))
			var foes: Array = s.units.filter(func(x): return x.team == 1).slice(0, 3)
			for k in foes.size():
				var fo: Dictionary = foes[k]
				s._set_class(fo, ["barbarian", "rogue", "mage"][k], false)
				fo.bot = false
				_revive(fo)
				fo.pos = hc + Vector2(5.0 + k * 1.9, (k - 1) * 0.45)
				fo.face = Sim.angle_of((cr.pos as Vector2) - (fo.pos as Vector2))
				_sturdy(fo)
				walkers[fo.id] = ((cr.pos as Vector2) - (fo.pos as Vector2)).normalized()   # (Kevin) charging, not standing
			set_meta("rush", foes.map(func(x): return x.id))
			set_meta("striker", cr.id)
			for u in s.units:
				if u.id != cr.id and not foes.has(u):
					u.bot = false
					u.move = Vector2.ZERO
					u.pos = Sim.spawn(u.team)
			beats = [[0.45, cr.id, "hammer"]]
			cam_a = [_v(hc + Vector2(3.4, 5.4), 1.8), _v(hc + Vector2(4.4, 0.0), 1.0)]
			cam_b = [_v(hc + Vector2(5.2, 4.8), 1.6), _v(hc + Vector2(5.0, 0.0), 1.0)]
		"dawn":
			for i in int(60.0 / Sim.TICK):
				s.step(Sim.TICK)
				s.drain_events()
			cam_a = [Vector3(-34, 30, 96), Vector3(0, 4, 5)]
			cam_b = [Vector3(-14, 19, 64), Vector3(0, 2, 18)]
		"captive":
			# Our King behind bars in THEIR dungeon, their guards at the bars.
			var cell: Vector2 = Sim.cell(0)
			var jail: Dictionary = s.gates.filter(func(g): return g.team == 1 and str(g.get("kind", "")) == "jail")[0]
			var out: Vector2 = ((jail.c as Vector2) - cell).normalized()
			var side := Vector2(out.y, -out.x)
			var k := 0
			for u in s.units:
				if u.team == 1 and k < 3:
					u.bot = false
					u.move = Vector2.ZERO
					u.pos = (jail.c as Vector2) + out * 1.6 + side * (-1.6 + k * 1.6)
					u.face = Sim.angle_of(cell - (u.pos as Vector2))
					k += 1
			var cy := Sim.height_at(cell)
			cam_a = [_v(cell + out * 7.0 + side * 2.5, cy + 6.5), _v(cell, cy + 1.0)]
			cam_b = [_v(cell + out * 3.6 + side * 1.2, cy + 2.8), _v(cell, cy + 1.2)]
		"heroes":
			# One villager walks up to the Barracks door and comes out a Knight -- close, so it reads.
			var st: Dictionary = s.stands.filter(func(x): return x.team == 0 and x.cls == "knight")[0]
			var door: Vector2 = st.p
			# (Not the player's unit: the match loop overwrites its move with the idle joystick.)
			var hero: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != me.id)[0]
			s._set_class(hero, "villager", false)
			hero.bot = false
			hero.pos = door + Vector2(4.5, 0.8)
			walkers[hero.id] = (door - (hero.pos as Vector2)).normalized() * 0.7
			me.pos = Sim._c(0, Vector2(6.0, 12.0))
			for u in s.units:
				if u.id != hero.id and u.id != me.id:
					u.pos = Sim.spawn(u.team) if u.team == 1 else Sim._c(0, Vector2(6.0, 12.0))
					u.bot = false
					u.move = Vector2.ZERO
			set_meta("hero", hero.id)
			cam_a = [_v(door + Vector2(4.6, 3.4), 2.8), _v(door + Vector2(1.6, 0.4), 1.1)]
			cam_b = [_v(door + Vector2(3.4, 2.4), 2.2), _v(door + Vector2(1.0, 0.2), 1.2)]
		"lineup":
			# Every hat is a hero: the seven classes in a row, the camera sliding along them.
			var classes := ["knight", "barbarian", "rogue", "ranger", "mage", "priest", "worker"]
			var j2 := 0
			for u in s.units:
				u.bot = false
				u.move = Vector2.ZERO
				if u.team == 0 and j2 < classes.size():
					s._set_class(u, classes[j2], j2 % 2 == 0)
					u.pos = Sim._c(0, Vector2(-7.2 + j2 * 2.4, 12.2))
					u.face = Sim.angle_of(Vector2(0.0, -1.0))
					j2 += 1
				else:
					u.pos = Sim.spawn(1) if u.team == 1 else Sim._c(0, Vector2(0.0, 24.0))
			cam_a = [_v(Sim._c(0, Vector2(-8.5, 7.6)), 2.6), _v(Sim._c(0, Vector2(-3.5, 12.2)), 1.3)]
			cam_b = [_v(Sim._c(0, Vector2(8.5, 7.6)), 2.6), _v(Sim._c(0, Vector2(3.5, 12.2)), 1.3)]
		"breakin":
			# Cold open (Lieu: get straight into the core action): smash their cell door, grab our King, run.
			var cell0: Vector2 = Sim.cell(0)
			var jail1: Dictionary = s.gates.filter(func(g): return g.team == 1 and str(g.get("kind", "")) == "jail")[0]
			var outj: Vector2 = ((jail1.c as Vector2) - cell0).normalized()
			var sidej := Vector2(outj.y, -outj.x)
			jail1.hp = 45.0
			for g in s.gates:
				if g.team == 1 and str(g.get("kind", "")) != "jail":
					g.broken = true                      # a way back out of their castle
					g.hp = 0.0
					break
			s._update_gate_nav()
			var crew2: Array = s.units.filter(func(x): return x.team == 0 and x.id != me.id)
			var smasher: Dictionary = crew2[0]
			var grabber: Dictionary = crew2[1]
			var escort2: Dictionary = crew2[2]
			s._set_class(smasher, "barbarian", true)
			s._set_class(grabber, "knight", true)
			s._set_class(escort2, "ranger", false)
			smasher.pos = (jail1.c as Vector2) + outj * 1.35
			smasher.face = Sim.angle_of(-outj)
			grabber.pos = (jail1.c as Vector2) + outj * 2.5 + sidej * 1.2
			escort2.pos = (jail1.c as Vector2) + outj * 2.7 - sidej * 1.3
			for u in s.units:
				u.bot = false
				u.move = Vector2.ZERO
				if not [smasher.id, grabber.id, escort2.id].has(u.id):
					u.pos = Sim.spawn(u.team)
			for u in [smasher, grabber, escort2]:
				_sturdy(u)
			beats = [[0.25, smasher.id, "smash"], [0.85, smasher.id, "smash"], [1.45, smasher.id, "smash"], [2.05, smasher.id, "smash"],
				[2.0, grabber.id, "to_king"], [3.3, grabber.id, "grab_go"]]
			follow_king = 0
			var ca: Vector2 = outj * 5.2 + sidej * 2.2
			var cb: Vector2 = outj * 4.0 + sidej * 3.6
			cam_a = [Vector3(ca.x, 4.6, ca.y), Vector3(outj.x * 1.2, 0.6, outj.y * 1.2)]
			cam_b = [Vector3(cb.x, 5.6, cb.y), Vector3(0.0, 0.8, 0.0)]
		"carry2":
			# The carry home with a struggle (Lieu: don't make it look easy): a rogue ambushes the carrier, our
			# King drops, and a teammate scoops him up.
			var start3 := Vector2(0.0, -9.0)
			var home3 := Vector2(0.0, 1.0)
			var al: Array = s.units.filter(func(x): return x.team == 0 and x.id != me.id)
			var carrier3: Dictionary = al[0]
			var scooper: Dictionary = al[1]
			s._set_class(carrier3, "knight", false)
			s._set_class(scooper, "barbarian", true)
			var o3: Dictionary = s.oracles[0]
			carrier3.bot = false
			carrier3.pos = o3.pos + Vector2(0.5, 0)
			s.act(carrier3.id, "interact")
			carrier3.pos = start3
			o3.pos = start3
			carrier3.hp = 6.0
			walkers[carrier3.id] = home3
			scooper.bot = false
			scooper.pos = start3 + Vector2(-1.2, -1.6)
			_sturdy(scooper)
			walkers[scooper.id] = home3 * 0.8                 # a step behind the carrier
			var amb: Dictionary = s.units.filter(func(x): return x.team == 1)[0]
			s._set_class(amb, "rogue", false)
			amb.bot = false
			amb.pos = start3 + Vector2(1.0, 3.3)
			amb.face = Sim.angle_of(-home3)
			_sturdy(amb)
			for u in s.units:
				if not [carrier3.id, scooper.id, amb.id].has(u.id):
					u.bot = false
					u.move = Vector2.ZERO
					u.pos = Sim.spawn(u.team)
			amb.pos = start3 + Vector2(-0.7, 2.9)              # the far side of the path: not between camera and King
			# The stab is a scripted beat (a swing at a moving target can miss): it lands as the swing does. Then
			# the barbarian makes for the King and scoops him the moment he's within reach.
			# After the stab the rogue backs off out of the path; the barbarian stops, and only goes for the King after
			# a beat, so the drop reads (he'd scooped him within 0.2 s).
			beats = [[0.85, amb.id, "attack"], [1.1, carrier3.id, "die"], [1.15, scooper.id, "stop"], [1.4, amb.id, "retreat"], [2.5, amb.id, "stop"]]
			set_meta("scoop", scooper.id)
			set_meta("scoop_after", 2.0)
			follow_king = 0
			cam_a = [Vector3(6.0, 4.6, -1.0), Vector3(0.0, 1.0, 1.2)]
			cam_b = [Vector3(5.0, 5.4, -3.5), Vector3(0.0, 1.0, 2.5)]
		"toofat":
			# Comedy and the heavy-King rule, shown not told: their lone raider lifts their fattened King in our
			# dungeon and can't budge; our barbarian sends him home without him.
			var capf: Dictionary = s.oracles[1]
			capf.cakes = 12
			capf.weight = 4
			var jail0: Dictionary = s.gates.filter(func(g): return g.team == 0 and str(g.get("kind", "")) == "jail")[0]
			jail0.broken = true
			jail0.hp = 0.0
			s._update_gate_nav()
			var outf: Vector2 = ((jail0.c as Vector2) - (capf.pos as Vector2)).normalized()
			var sidef := Vector2(outf.y, -outf.x)
			var raider: Dictionary = s.units.filter(func(x): return x.team == 1)[0]
			s._set_class(raider, "knight", false)
			raider.bot = false
			raider.pos = (capf.pos as Vector2) + outf * 1.0
			raider.hp = 40.0
			var guard2: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != me.id)[0]
			s._set_class(guard2, "barbarian", true)
			guard2.bot = false
			guard2.pos = (jail0.c as Vector2) + outf * 2.2 + sidef * 1.8       # comes in from the far side
			_sturdy(guard2)
			for u in s.units:
				if u.id != raider.id and u.id != guard2.id:
					u.bot = false
					u.move = Vector2.ZERO
					u.pos = Sim.spawn(u.team)
			beats = [[0.5, raider.id, "grab_stuck"], [2.2, guard2.id, "to_raider"], [3.25, guard2.id, "attack"], [3.5, raider.id, "die"]]
			set_meta("raider", raider.id)
			var cyf := Sim.height_at(capf.pos)
			# Above the dungeon wall, looking down into the cell (lower, it put the wall across the frame).
			cam_a = [_v((capf.pos as Vector2) + outf * 5.0 - sidef * 1.4, cyf + 5.6), _v((capf.pos as Vector2) + outf * 0.6, cyf + 1.2)]
			cam_b = [_v((capf.pos as Vector2) + outf * 4.2 - sidef * 1.0, cyf + 5.0), _v((capf.pos as Vector2) + outf * 0.8, cyf + 1.3)]
		"hatsteal":
			# Hats are power -- and they drop: their barbarian downs our knight, and their villager walks over his
			# hat and becomes a knight.
			var spot4 := Vector2(-6.0, 18.0)
			var victim4: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != me.id)[0]
			var killer: Dictionary = s.units.filter(func(x): return x.team == 1)[0]
			var thief: Dictionary = s.units.filter(func(x): return x.team == 1)[1]
			s._set_class(victim4, "knight", false)
			victim4.bot = false
			victim4.pos = spot4
			victim4.hp = 8.0
			victim4.face = Sim.angle_of(Vector2(1.0, 0.0))
			s._set_class(killer, "barbarian", false)
			killer.bot = false
			killer.pos = spot4 + Vector2(1.5, 0.0)
			killer.face = Sim.angle_of(Vector2(-1.0, 0.0))
			_sturdy(killer)
			s._set_class(thief, "villager", false)
			thief.bot = false
			thief.pos = spot4 + Vector2(-3.8, 2.2)
			for u in s.units:
				if not [victim4.id, killer.id, thief.id].has(u.id):
					u.bot = false
					u.move = Vector2.ZERO
					u.pos = Sim.spawn(u.team)
			beats = [[0.35, killer.id, "attack"], [1.05, thief.id, "to_hat"]]
			set_meta("hero", thief.id)
			cam_a = [_v(spot4 + Vector2(1.5, 5.6), 2.6), _v(spot4 + Vector2(-1.0, 0.6), 1.0)]
			cam_b = [_v(spot4 + Vector2(0.4, 4.8), 2.3), _v(spot4 + Vector2(-1.2, 0.8), 1.1)]
		"gather":
			# The economy (Kevin: "the trailer should include gathering resources"): workers chop a tree and
			# mine a rock with their tools; one hauls lumber home.
			var best_w := {}
			var best_s := {}
			var bd := INF
			for nw in s.nodes:
				if nw.kind != "wood" or (nw.p as Vector2).y < 6.0 or (nw.p as Vector2).y > 30.0:
					continue
				for ns in s.nodes:
					if ns.kind == "stone" and (ns.p as Vector2).distance_to(nw.p) < bd:
						bd = (ns.p as Vector2).distance_to(nw.p)
						best_w = nw
						best_s = ns
			var crew: Array = s.units.filter(func(x): return x.team == 0 and x.id != me.id).slice(0, 4)
			var spots := [[best_w, Vector2(1.0, 0.3)], [best_w, Vector2(-0.9, 0.6)], [best_s, Vector2(1.0, -0.2)]]
			for k4 in 3:
				var wk: Dictionary = crew[k4]
				var node: Dictionary = spots[k4][0]
				s._set_class(wk, "worker", false)
				wk.bot = false
				wk.pos = (node.p as Vector2) + (spots[k4][1] as Vector2).normalized() * (float(node.r) + 0.75)
				wk.face = Sim.angle_of((node.p as Vector2) - (wk.pos as Vector2))
				wk.task = {"kind": "gather", "t": 99.0, "node": node.id}
			var hauler: Dictionary = crew[3]
			s._set_class(hauler, "worker", false)
			hauler.bot = false
			hauler.load = {"kind": "wood", "n": 3}
			hauler.pos = (best_w.p as Vector2) + Vector2(-3.5, -1.5)
			walkers[hauler.id] = Vector2(0.15, 1.0).normalized() * 0.55
			for u in s.units:
				if not crew.has(u):
					u.bot = false
					u.move = Vector2.ZERO
					u.pos = Sim.spawn(u.team)
			var mid2: Vector2 = ((best_w.p as Vector2) + (best_s.p as Vector2)) * 0.5
			orbit = {"c": _v(mid2, 0.9), "r": 7.5, "h": 3.6, "a0": 2.6, "a1": 3.5}
		"build":
			# Ladders get you INTO their castle (Kevin): the ladder goes up half a second in (most of the 3 s build
			# happens before recording), the builder steps aside, and three heroes climb over and drop inside
			# while the camera cranes up over the wall after them.
			s.stock[0].wood = 60
			# (trailer 5) the enemy castle's front wall on today's map: the old fixed spot no longer touched it, so no ladder
			# was ever raised. Take their front-most plain wall segment, a point on it clear of the gate, just outside it.
			var fw: Dictionary = {}
			for w in s.walls:
				if str(w.kind) != "wall" or int(w.team) != 1:
					continue
				var mid: Vector2 = ((w.a as Vector2) + (w.b as Vector2)) * 0.5
				if absf(mid.x) < 6.0 or absf(mid.x) > 22.0 or ((w.a as Vector2) - (w.b as Vector2)).length() < 5.0:
					continue
				if fw.is_empty() or mid.y > (((fw.a as Vector2) + (fw.b as Vector2)) * 0.5).y:
					fw = w
			var cp2: Vector2 = Sim.seg_closest(((fw.a as Vector2) + (fw.b as Vector2)) * 0.5, fw.a, fw.b)
			var spot2 := cp2 + Vector2(0.0, float(fw.r) + Sim.UNIT_R + 0.35)
			var team0: Array = s.units.filter(func(x): return x.team == 0 and x.id != me.id)
			var builder: Dictionary = team0[0]
			s._set_class(builder, "worker", false)
			builder.bot = false
			builder.pos = spot2
			builder.face = Sim.angle_of(Vector2(0.0, -1.0))
			var climbers := []
			for k5 in 3:
				var c5: Dictionary = team0[k5 + 1]
				s._set_class(c5, ["knight", "barbarian", "ranger"][k5], k5 == 0)
				c5.bot = false
				c5.pos = spot2 + Vector2(1.8 + k5 * 1.1, 2.0 + k5 * 1.3)
				climbers.append(c5)
			for u in s.units:
				if u.id != builder.id and not climbers.has(u):
					u.bot = false
					u.move = Vector2.ZERO
					u.pos = Sim.spawn(u.team)
			s.act(builder.id, "interact")
			for i in int(0.7 / Sim.TICK):
				s.step(Sim.TICK)
			# (trailer 5, Kevin: show the ladder actually going up and being climbed) the worker is still hammering when
			# recording starts; the ladder swings up at ~2.3 s; the heroes climb it after.
			beats = [[2.9, builder.id, "aside"]]
			for k6 in 3:
				beats.append([3.2 + k6 * 0.5, climbers[k6].id, "climb"])
			cam_a = [_v(spot2 + Vector2(5.0, 5.4), 3.0), _v(cp2 + Vector2(0.0, 0.6), 1.8)]
			cam_b = [_v(spot2 + Vector2(3.4, 3.4), 6.2), _v(cp2 + Vector2(-0.2, -2.2), 1.6)]
		"backstab":
			# Fight dirty (Kevin: "a rogue sneaking up and stabbing someone in the back"): their archer is busy
			# shooting the other way; our rogue creeps up behind her and stabs.
			var spot3 := Vector2(8.0, 14.0)
			var victim: Dictionary = s.units.filter(func(x): return x.team == 1)[0]
			var rogue2: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != me.id)[0]
			s._set_class(victim, "ranger", false)
			victim.bot = false
			victim.move = Vector2.ZERO
			victim.pos = spot3
			victim.face = Sim.angle_of(Vector2(0.25, -1.0))          # looking (and shooting) away
			victim.hp = 12.0                                         # the first stab in the back finishes her
			s._set_class(rogue2, "rogue", false)
			rogue2.bot = false
			rogue2.pos = spot3 + Vector2(-0.6, 4.4)
			var creep2: Vector2 = (spot3 + Vector2(-0.1, 0.95) - (rogue2.pos as Vector2)).normalized() * 0.3
			walkers[rogue2.id] = creep2
			rogue2.face = Sim.angle_of(creep2)
			for u in s.units:
				if u.id != victim.id and u.id != rogue2.id:
					u.bot = false
					u.move = Vector2.ZERO
					u.pos = Sim.spawn(u.team)
			# Her shots don't auto-aim (aiming turned her round to face the nearest enemy -- the rogue -- so he
			# stabbed her from the front; Kevin), and her facing stays locked away from him.
			set_meta("away", [victim.id, victim.face])
			beats = [[0.3, victim.id, "shoot"], [1.05, victim.id, "shoot"], [1.8, victim.id, "shoot"],
				[1.9, rogue2.id, "stop"], [1.95, rogue2.id, "attack"], [2.55, rogue2.id, "attack"]]
			cam_a = [_v(spot3 + Vector2(4.2, -2.6), 2.2), _v(spot3 + Vector2(-0.3, 1.6), 1.0)]
			cam_b = [_v(spot3 + Vector2(3.0, -1.6), 1.9), _v(spot3 + Vector2(-0.2, 0.9), 1.1)]
		"clash":
			# Sixteen against sixteen: both armies charge into each other on our side of the river.
			var mix2 := ["knight", "barbarian", "ranger", "rogue", "mage", "priest", "knight", "barbarian"]
			var bi := 0
			var ri := 0
			for u in s.units:
				u.bot = false
				if u.team == 0:
					s._set_class(u, mix2[bi % mix2.size()], bi % 3 == 0)
					u.pos = Vector2(-13.0 + (bi % 8) * 3.6, 23.0 + (bi / 8) * 2.2)
					walkers[u.id] = Vector2(0.0, -1.0)
					bi += 1
				else:
					s._set_class(u, mix2[(ri + 3) % mix2.size()], ri % 3 == 1)
					u.pos = Vector2(-12.0 + (ri % 8) * 3.6, 9.5 - (ri / 8) * 2.2)
					walkers[u.id] = Vector2(0.0, 1.0)
					ri += 1
				_revive(u)
			beats = [[1.2, "", "melee"]]
			cam_a = [Vector3(-19.0, 3.2, 15.5), Vector3(-2.0, 1.2, 16.0)]
			cam_b = [Vector3(-12.0, 4.6, 12.0), Vector3(4.0, 1.2, 16.5)]
		"throne":
			# The last steps: a knight carries our King into the throne room and sets him down -- a rescue.
			var o2: Dictionary = s.oracles[0]
			var bearer: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != me.id)[0]
			s._set_class(bearer, "knight", true)
			bearer.bot = false
			bearer.pos = (o2.pos as Vector2) + Vector2(0.5, 0.0)
			s.act(bearer.id, "interact")
			var th: Vector2 = Sim.throne(0)
			var start2: Vector2 = Sim._c(0, Vector2(0.0, 24.2))
			bearer.pos = start2
			o2.pos = start2
			walkers[bearer.id] = (th - start2).normalized()
			# Four allies flank the throne (none between the camera and it); the rest far away.
			var flank := [Vector2(-3.2, 26.2), Vector2(-2.2, 27.4), Vector2(2.4, 27.2), Vector2(3.4, 26.0)]
			var fi := 0
			for u in s.units:
				if u.id != bearer.id:
					u.bot = false
					u.move = Vector2.ZERO
					if u.team == 0 and u.id != me.id and fi < flank.size():
						u.pos = Sim._c(0, flank[fi])
						fi += 1
					else:
						u.pos = Sim.spawn(u.team)
					u.face = Sim.angle_of(th - (u.pos as Vector2))
			var thy := Sim.height_at(th)
			cam_a = [_v(Sim._c(0, Vector2(5.5, 21.0)), thy + 4.2), _v(th + (start2 - th) * 0.5, thy + 1.0)]
			cam_b = [_v(Sim._c(0, Vector2(3.5, 22.6)), thy + 3.2), _v(th, thy + 1.2)]
		"assault":
			var eg: Dictionary = s.gates.filter(func(g): return g.team == 1 and str(g.get("kind", "")) != "jail")[0]
			var front: Vector2 = Sim.gate_front(eg)
			var out2: Vector2 = (front - (eg.c as Vector2)).normalized()
			var side2 := Vector2(out2.y, -out2.x)
			var mix := ["knight", "barbarian", "ranger", "mage", "priest", "knight"]
			var b := 0
			var r := 0
			for u in s.units:
				if u.team == 0 and b < 12:
					s._set_class(u, mix[b % mix.size()], b % 3 == 0)
					u.pos = front + out2 * (3.0 + (b % 3) * 2.2) + side2 * ((b / 3) * 2.4 - 3.6)
					b += 1
				elif u.team == 1 and r < 10:
					s._set_class(u, ["ranger", "rogue", "ranger", "barbarian"][r % 4], r % 4 == 0)
					u.pos = front + out2 * (0.6 + (r % 2) * 1.2) + side2 * ((r / 2) * 2.0 - 4.0)
					r += 1
				_revive(u)
			eg.hp = 160.0                                # it gives way during the shot (Round 28)
			orbit = {"c": _v(front + out2 * 2.0, 0.8), "r": 13.0, "h": 8.5, "a0": Sim.angle_of(out2) - 0.9, "a1": Sim.angle_of(out2) + 0.5}
		"rampart":
			# Rangers on our rampart loose volleys over the wall at the attackers below.
			var posts: Array = Castle.RAMPART_POSTS
			var a := 0
			var e := 0
			for u in s.units:
				if u.team == 0 and a < posts.size():
					s._set_class(u, "ranger", a % 2 == 0)
					u.role = "defend"
					u.pos = Sim._c(0, posts[a])
					u["post"] = a
					_sturdy(u)
					a += 1
				elif u.team == 0:
					u.pos = Sim._c(0, Vector2(0.0, 24.0))
					u.bot = false
				elif u.team == 1 and e < 9:
					s._set_class(u, ["knight", "barbarian", "rogue"][e % 3], false)
					u.pos = Sim._c(0, Vector2(-6.0 + (e % 5) * 3.0, -5.0 - (e / 5) * 3.0))
					_sturdy(u)
					e += 1
			for i in int(1.0 / Sim.TICK):
				s.step(Sim.TICK)
			var eye0: Vector2 = Sim._c(0, Vector2(7.5, 8.5))
			var eye1: Vector2 = Sim._c(0, Vector2(5.0, 7.0))
			cam_a = [_v(eye0, 6.5), _v(Sim._c(0, Vector2(0.0, -6.0)), 0.8)]
			cam_b = [_v(eye1, 5.2), _v(Sim._c(0, Vector2(-1.0, -7.0)), 0.8)]
		"whirl":
			# (trailer 5, Kevin) three of theirs charge our Berserker; he goes into a spin and cuts them all down -- in slow
			# motion from the moment he spins; each is thrown back dead (state only, so nobody turns into a villager).
			var field := Vector2(-6.0, 22.0)
			s._set_class(me, "barbarian", true)
			me.bot = false
			_revive(me)
			me.pos = field
			me.cd_ability = 0.0
			me.face = Sim.angle_of(Vector2(0, -1))
			var rush := []
			for u in s.units:
				if u.team == 1 and rush.size() < 3:
					var k9 := rush.size()
					u.bot = false
					_revive(u)
					s._set_class(u, ["knight", "rogue", "mage"][k9], false)     # no second barbarian to confuse with ours
					var ang := -PI * 0.5 + (k9 - 1) * 0.95
					u.pos = field + Vector2(cos(ang), sin(ang)) * 5.6
					u.face = Sim.angle_of(field - (u.pos as Vector2))
					_sturdy(u)
					rush.append(u.id)
					walkers[u.id] = (field - (u.pos as Vector2)).normalized()
				elif u.team == 0 and u.id != me.id:
					u.pos = Sim.spawn(0)
			set_meta("rush", rush)
			beats = [[0.78, me.id, "spin"]]
			orbit = {"c": _v(field + Vector2(0.0, -1.2), 1.0), "r": 6.2, "h": 2.4, "a0": 1.15, "a1": 2.1}
		"feast":
			# A rogue walks a fish into our dungeon (the cell door lifts for friends) and feeds THEIR King:
			# he goes from fatter to fattest, with a puff.
			var cap: Dictionary = s.oracles[1]
			cap.cakes = 11
			cap.weight = 3
			var jail2: Dictionary = s.gates.filter(func(g): return g.team == 0 and str(g.get("kind", "")) == "jail")[0]
			var out3: Vector2 = ((jail2.c as Vector2) - (cap.pos as Vector2)).normalized()
			var feeder: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != me.id)[0]
			s._set_class(feeder, "rogue", false)
			feeder.bot = false
			feeder.offering = true
			feeder.pos = (jail2.c as Vector2) + out3 * 2.2
			walkers[feeder.id] = -out3 * 0.6
			beats = [[1.9, feeder.id, "feed"]]
			for u in s.units:
				if u.id != feeder.id:
					u.pos = Sim.spawn(u.team)
					u.bot = false
					u.move = Vector2.ZERO
			var cy2 := Sim.height_at(cap.pos)
			var side3 := Vector2(out3.y, -out3.x)
			cam_a = [_v((cap.pos as Vector2) + out3 * 6.0 + side3 * 3.0, cy2 + 4.6), _v(cap.pos, cy2 + 1.2)]
			cam_b = [_v((cap.pos as Vector2) + out3 * 3.8 + side3 * 1.8, cy2 + 3.0), _v(cap.pos, cy2 + 1.4)]
		"carry":
			var start := Vector2(0.0, -9.0)
			var home_dir := Vector2(0.0, 1.0)
			var allies: Array = s.units.filter(func(x): return x.team == 0 and x.id != me.id)
			var foes2: Array = s.units.filter(func(x): return x.team == 1)
			var carrier: Dictionary = allies[0]
			s._set_class(carrier, "knight", true)
			var o: Dictionary = s.oracles[0]
			carrier.bot = false
			carrier.pos = o.pos + Vector2(0.5, 0)
			s.act(carrier.id, "interact")
			carrier.pos = start
			o.pos = start
			walkers[carrier.id] = home_dir
			for k2 in 3:
				var es: Dictionary = allies[k2 + 1]
				s._set_class(es, ["barbarian", "priest", "ranger"][k2], k2 == 0)
				es.bot = false
				es.pos = start + Vector2([-1.6, 1.6, 0.0][k2], [-0.6, -0.6, -2.0][k2])
				walkers[es.id] = home_dir
			for k3 in 4:
				var fo: Dictionary = foes2[k3]
				s._set_class(fo, ["rogue", "knight", "barbarian", "rogue"][k3], false)
				fo.bot = false
				fo.pos = start + Vector2(-2.0 + k3 * 1.4, -7.5 - (k3 % 2) * 1.2)
				chasers.append(fo.id)
			me.pos = Sim.spawn(0)
			follow = carrier.id
			cam_a = [Vector3(6.5, 6.0, -6.0), Vector3(0, 1.0, 2.0)]
			cam_b = [Vector3(3.5, 7.5, -9.0), Vector3(0, 1.0, 3.5)]
		"reveal":
			# The whole kingdom at golden hour, the sun low beyond the enemy castle; the title and its god
			# rays are composited over this in post.
			for i in int(40.0 / Sim.TICK):
				s.step(Sim.TICK)
				s.drain_events()
			_golden_hour()
			cam_a = [Vector3(0.0, 24.0, 90.0), Vector3(0.0, 9.0, -40.0)]
			cam_b = [Vector3(0.0, 33.0, 104.0), Vector3(0.0, 12.0, -40.0)]
	mode.view.snap_camera()

func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)

func _clear_sightline() -> void:
	# Hide props (boulders, rocks, trees, barrels) standing between the camera and what it's looking at (Kevin: a boulder
	# blocked the opening). Actors, terrain and water are left alone.
	if cam_a.is_empty():
		return
	var keep := {}
	for a in mode.view.actors.values():
		keep[a.root] = true
	var segs := [[cam_a[0], cam_a[1]], [cam_b[0], cam_b[1]]]
	var hidden := 0
	for c in mode.view.get_children():
		if not (c is Node3D) or keep.has(c) or not (c as Node3D).visible:
			continue
		var p: Vector3 = (c as Node3D).global_position
		if p.length() < 0.5:
			continue                                   # terrain, water and other meshes built at the origin
		for sg in segs:
			var e: Vector3 = sg[0]
			var t2: Vector3 = sg[1]
			var ab := Vector2(t2.x - e.x, t2.z - e.z)
			var ap := Vector2(p.x - e.x, p.z - e.z)
			var k := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.15)
			if ap.distance_to(ab * k) < 2.4:
				(c as Node3D).visible = false
				hidden += 1
				break
	printerr("cleared %d props from the sightline" % hidden)

func _slow_scale(tt: float) -> float:
	for w in SLOW.get(shot, []):
		if tt >= float(w[0]) and tt < float(w[1]):
			return float(w[2])
	return 1.0

func _process(delta: float) -> bool:
	frames += 1
	if OS.has_environment("FRAMELOG"):
		printerr("F %d %.2f" % [frames, Time.get_ticks_msec() / 1000.0])
	mode._guard_clock = -1.0e9
	if frames == 2:
		_stage()
		if shot in ["hook", "necro", "hammer"]:
			_clear_sightline()
	if frames < 2:
		return false
	t += delta
	if OS.has_environment("STILL_AT") and frames == 3:
		t = float(OS.get_environment("STILL_AT"))
	Engine.time_scale = _slow_scale(t)
	if OS.has_environment("STILL_AT") and frames == 7:
		root.get_texture().get_image().save_png("/tmp/trailer5/still_%s.png" % shot)
		printerr("SHOT_DONE %s still" % shot)
		quit(0)
		return false
	var e := _ease(clampf(t / float(LENGTH[shot]), 0.0, 1.0))
	var s = mode.sim
	if not orbit.is_empty():
		var ang: float = lerpf(orbit.a0, orbit.a1, e)
		var c: Vector3 = orbit.c
		mode.view.cam_override = [c + Vector3(sin(ang) * orbit.r, orbit.h, cos(ang) * orbit.r), c]
	elif follow_king >= 0:
		var ok2: Dictionary = s.oracles[follow_king]
		var kp := Vector3(ok2.pos.x, Sim.height_at(ok2.pos), ok2.pos.y)
		mode.view.cam_override = [kp + (cam_a[0] as Vector3).lerp(cam_b[0], e), kp + (cam_a[1] as Vector3).lerp(cam_b[1], e)]
	elif follow != "":
		var fu: Dictionary = s.by_id[follow]
		var fp := Vector3(fu.pos.x, Sim.height_at(fu.pos), fu.pos.y)
		mode.view.cam_override = [fp + (cam_a[0] as Vector3).lerp(cam_b[0], e), fp + (cam_a[1] as Vector3).lerp(cam_b[1], e)]
	elif not cam_a.is_empty():
		mode.view.cam_override = [(cam_a[0] as Vector3).lerp(cam_b[0], e), (cam_a[1] as Vector3).lerp(cam_b[1], e)]
	for id in walkers:
		s.by_id[id].move = walkers[id]
	if follow != "":
		for id in chasers:
			var ch: Dictionary = s.by_id[id]
			ch.move = ((s.by_id[follow].pos as Vector2) - (ch.pos as Vector2)).normalized()
	for b in beats.duplicate():
		if t >= float(b[0]) and str(b[2]) == "melee":
			beats.erase(b)
			walkers.clear()
			for u in s.units:
				u.bot = true
			continue
		if t >= float(b[0]):
			beats.erase(b)
			var bu: Dictionary = s.by_id[b[1]]
			walkers.erase(b[1])
			bu.move = Vector2.ZERO
			if str(b[2]) == "feed":
				s.act(bu.id, "interact")
			elif str(b[2]) == "stop":
				walkers.erase(bu.id)
				bu.move = Vector2.ZERO
			elif str(b[2]) == "retreat":
				walkers[bu.id] = Vector2(-1.0, -0.4).normalized() * 0.6
			elif str(b[2]) == "die":
				s._damage({"team": 1 - int(bu.team), "id": "trailer", "pos": bu.pos}, bu, 9999.0)
			elif str(b[2]) == "smash":
				bu.cd_attack = 0.0
				s._start_attack(bu, "attack", false)
			elif str(b[2]) == "to_king":
				var tk: Dictionary = s.oracles[bu.team]
				walkers[bu.id] = ((tk.pos as Vector2) - (bu.pos as Vector2)).normalized() * 0.8
			elif str(b[2]) == "grab_go":
				walkers.erase(bu.id)
				bu.move = Vector2.ZERO
				s.act(bu.id, "interact")
				for u in s.units:
					if u.team == 0 and u.id != s.by_id[mode.hud.player_id].id:
						u.bot = true
						u.role = "escort"
			elif str(b[2]) == "grab_home":
				walkers.erase(bu.id)
				bu.move = Vector2.ZERO
				s.act(bu.id, "interact")
				walkers[bu.id] = Vector2(0.0, 1.0)
			elif str(b[2]) == "grab_stuck":
				s.act(bu.id, "interact")
				walkers[bu.id] = ((bu.pos as Vector2) - Sim.cell(1)).normalized()     # tries to walk out -- can't
			elif str(b[2]) == "to_raider":
				var rd: Dictionary = s.by_id[str(get_meta("raider"))]
				walkers[bu.id] = ((rd.pos as Vector2) - (bu.pos as Vector2)).normalized() * 0.85
			elif str(b[2]) == "to_hat":
				var hp4 := Vector2.INF
				for h in s.hats:
					hp4 = h.pos
				if hp4 != Vector2.INF:
					walkers[bu.id] = (hp4 - (bu.pos as Vector2)).normalized() * 0.75
			elif str(b[2]) == "shoot":
				bu.cd_attack = 0.0
				s._start_attack(bu, "attack", false)
			elif str(b[2]) == "spin":
				s.act(bu.id, "ability")          # they keep charging into it; each stops when it cuts him down
			elif str(b[2]) == "hammer":
				s._throw_hammer(bu)
			elif str(b[2]) == "attack":
				bu.cd_attack = 0.0
				s._start_attack(bu, "attack")
			elif str(b[2]) == "aside":
				walkers[bu.id] = Vector2(-1.0, 0.35).normalized() * 0.6
			elif str(b[2]) == "climb":
				# (trailer 5) to the foot of the ladder actually raised, then up and over it (was a fixed point on the old map)
				var cl: Array = get_meta("climbers", [])
				cl.append(bu.id)
				set_meta("climbers", cl)
	if (shot == "whirl" or shot == "hammer") and has_meta("rush"):
		var me3: Dictionary = s.by_id[str(get_meta("striker", mode.hud.player_id))]
		for rid in get_meta("rush"):
			var ru: Dictionary = s.by_id[str(rid)]
			var hk := "rhp_" + str(rid)
			var fk3 := "rfly_" + str(rid)
			var was3 := float(get_meta(hk, ru.hp))
			set_meta(hk, ru.hp)
			if ru.hp < was3 - 1.0 and not has_meta(fk3):
				set_meta(fk3, [t, ru.pos, ((ru.pos as Vector2) - (me3.pos as Vector2)).normalized()])
				ru.state = "dead"
				ru.respawn_at = INF
				ru.move = Vector2.ZERO
				walkers.erase(rid)
				var bp := Vector3(ru.pos.x, Sim.height_at(ru.pos) + 1.1, ru.pos.y)
				for k10 in 30:
					mode.view.spark(bp + Vector3(randf_range(-0.15, 0.15), randf_range(-0.2, 0.3), randf_range(-0.15, 0.15)),
						Color(0.62 + randf() * 0.2, 0.02, 0.03))
			if has_meta(fk3):
				var fl: Array = get_meta(fk3)
				var kk := clampf((t - float(fl[0])) / 0.5, 0.0, 1.0)
				ru.pos = (fl[1] as Vector2) + (fl[2] as Vector2) * 1.6 * (1.0 - pow(1.0 - kk, 2.0))
				var ra: Dictionary = mode.view.actors.get(ru.id, {})
				if not ra.is_empty() and ra.get("body") != null:
					(ra.body as Node3D).position.y = 0.8 * 4.0 * kk * (1.0 - kk)
	if shot == "build" and has_meta("climbers"):
		var lads: Array = s.ladders.filter(func(l): return int(l.team) == 0)
		if not lads.is_empty():
			var foot: Vector2 = (lads[0].p as Vector2) + Vector2(0.0, 1.15)
			for cid in get_meta("climbers"):
				var cu: Dictionary = s.by_id[str(cid)]
				var up_k := "up_" + str(cid)
				if not has_meta(up_k) and (cu.pos as Vector2).distance_to(foot) < 0.45:
					set_meta(up_k, true)
				walkers[cid] = Vector2(0.0, -1.0) if has_meta(up_k) else (foot - (cu.pos as Vector2)).normalized()
	if shot == "hook" and has_meta("bleed"):
		var bu2: Dictionary = s.by_id[str(get_meta("bleed"))]
		var was := float(get_meta("bleed_hp", bu2.hp))
		set_meta("bleed_hp", bu2.hp)
		if bu2.hp < was - 1.0 and not has_meta("fly_t0"):   # he was just hit: thrown back, dead before he lands
			var bb2: Dictionary = s.units.filter(func(x): return x.team == 1)[0]
			set_meta("fly_t0", t)
			set_meta("fly_p0", bu2.pos)
			set_meta("fly_dir", ((bu2.pos as Vector2) - (bb2.pos as Vector2)).normalized())
			bu2.state = "dead"
			bu2.respawn_at = INF
			bu2.move = Vector2.ZERO
			var hp5 := Vector3(bu2.pos.x, Sim.height_at(bu2.pos) + 1.15, bu2.pos.y)
			for k8 in 46:
				mode.view.spark(hp5 + Vector3(randf_range(-0.15, 0.15), randf_range(-0.2, 0.3), randf_range(-0.15, 0.15)),
					Color(0.62 + randf() * 0.2, 0.02, 0.03))
	if shot == "hook" and has_meta("fly_t0"):
		var fu: Dictionary = s.by_id[str(get_meta("bleed"))]
		var fk := clampf((t - float(get_meta("fly_t0"))) / 0.55, 0.0, 1.0)
		fu.pos = (get_meta("fly_p0") as Vector2) + (get_meta("fly_dir") as Vector2) * 1.7 * (1.0 - pow(1.0 - fk, 2.0))
		var fa: Dictionary = mode.view.actors.get(fu.id, {})
		if not fa.is_empty() and fa.get("body") != null:
			(fa.body as Node3D).position.y = 0.95 * 4.0 * fk * (1.0 - fk)
	if shot == "necro" and has_meta("necro"):
		s.act(str(get_meta("necro")), "attack")
	if shot == "backstab" and has_meta("away"):
		var aw: Array = get_meta("away")
		var vu: Dictionary = s.by_id[str(aw[0])]
		if vu.state != "dead":
			vu.face = float(aw[1])
	if (shot == "heroes" or shot == "hatsteal") and has_meta("hero") and not has_meta("transformed"):
		# The hat goes on: stop at the door, turn to the camera in a burst of gold, then a swing.
		var hu: Dictionary = s.by_id[str(get_meta("hero"))]
		if hu.cls != "villager" and hu.state != "dead":
			set_meta("transformed", true)
			walkers.erase(hu.id)
			hu.move = Vector2.ZERO
			var eye: Vector3 = mode.view.cam_override[0] if not mode.view.cam_override.is_empty() else Vector3.ZERO
			hu.face = Sim.angle_of(Vector2(eye.x, eye.z) - (hu.pos as Vector2))
			var hp3 := Vector3(hu.pos.x, Sim.height_at(hu.pos), hu.pos.y)
			mode.view.ring_at(hp3 + Vector3(0, 0.08, 0), Color("#ffd257"), 2.2, 0.7)
			for k7 in 14:
				mode.view.spark(hp3 + Vector3(randf_range(-0.7, 0.7), 0.4 + randf() * 1.8, randf_range(-0.7, 0.7)), Color("#ffe08a"))
			beats.append([t + 0.55, hu.id, "smash"])
	if shot == "carry2" and has_meta("scoop") and not has_meta("scooped"):
		var sc: Dictionary = s.by_id[str(get_meta("scoop"))]
		var kg: Dictionary = s.oracles[0]
		if str(kg.state) == "dropped" and t >= float(get_meta("scoop_after", 0.0)):
			walkers[sc.id] = ((kg.pos as Vector2) - (sc.pos as Vector2)).normalized() * 0.85
			if (sc.pos as Vector2).distance_to(kg.pos) < 1.1:
				set_meta("scooped", true)
				sc.move = Vector2.ZERO
				s.act(sc.id, "interact")
				walkers[sc.id] = Vector2(0.0, 1.0)
	if shot == "throne" and int(s.score[0]) > 0 and not has_meta("seated"):
		set_meta("seated", true)
		var ok: Dictionary = s.oracles[0]
		ok.state = "dropped"
		ok.pos = Sim.throne(0) + (Sim._c(0, Vector2(0.0, 0.0)) - Sim.throne(0)).normalized() * 0.9
		ok.carrier = ""
		ok.lifters = []
		ok.dropped_at = s.time
		walkers.clear()
		for u in s.units:
			u.move = Vector2.ZERO
	if shot == "reveal":
		var cam: Camera3D = mode.view.camera
		var sp := cam.unproject_position(cam.global_position + SUN_DIR.normalized() * 3000.0)
		var vs := root.get_visible_rect().size
		sun_track.append([sp.x / vs.x, sp.y / vs.y, not cam.is_position_behind(cam.global_position + SUN_DIR.normalized() * 3000.0)])
	if t >= float(LENGTH[shot]):
		if shot == "reveal":
			var f := FileAccess.open("/tmp/trailer5/reveal_sun.json", FileAccess.WRITE)
			f.store_string(JSON.stringify(sun_track))
			f.close()
		printerr("SHOT_DONE %s %d frames" % [shot, frames])
		quit(0)
	return false
