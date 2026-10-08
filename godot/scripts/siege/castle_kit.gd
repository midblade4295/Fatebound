extends RefCounted
# Meshy castle kits (0.31.74). Kevin picked the concepts "A2" (Royal) and "B1" (War fortress) -- "B1 for one team and
# A2 for the other" -- with "insides done also so the castles don't look cookie cutter" and "make sure players can climb
# up on the front wall to shoot outside" (the rampart walkway behind the front wall, Castle.WALK_*, unchanged).
#
# Only what is DRAWN changes: the castle's layout (walls, gates, terraces, stairs, rooms) is the sim's, exactly as
# before. Each piece is a Meshy model (assets/meshy/castle/, prepared by tools/meshy_building_tex.py: 1K texture, 512
# for small props, fire glow masks), drawn with team_swap.gdshader so a kit's blue cloth turns red on the red castle.
# The view (siege_view.gd, _build_castle*) lays the pieces along the sim's walls and terrace edges and puts the rest at
# the spots below.
const Stage = preload("res://scripts/siege/asset_cache.gd")
const DIR := "res://assets/meshy/castle/"
const SWAP_SHADER := preload("res://scripts/siege/team_swap.gdshader")
# 0.31.75, Kevin: "make both castles the same royal style" -- both teams build the Royal kit; on the red castle
# team_swap turns its blue roofs, banners and canopy red. The War kit stays described (and its files in the repo) but
# is left out of the APK (export_presets.cfg, exclude_filter "assets/meshy/castle/war_*" and ".../floors/war_*"):
# to bring it back, name it here AND drop those two patterns from the presets.
const STYLE_OF_TEAM := ["royal", "royal"]          # blue, red
const FIRE_GLOW := Color(1.0, 0.55, 0.18)

# Per kit (sizes in metres; "model units" = the Meshy model's own, centred on its bounds):
#   wall      curtain walls (the sim's "wall"/"backwall" lines): model, h (merlon tops), depth, len (piece length aimed for)
#   terrace   terrace faces, stair sides and the rampart's edges: model, body (the part of its height below its balustrade
#             or railing -- that part spans the climb), depth, len
#   gatehouse round each gate: model, s (scale; its arch ~3 m wide), out (pushed out from the wall line, so the
#             wall-walk behind stays clear), door (scale of the KayKit gate whose door leaves swing in the arch)
#   tower     the four corner towers: model, s
#   dungeon   archway over the doorway down to the dungeon: model, s, depth
#   throne    behind / under the throne: model, s, ys (extra height factor), back (its middle, metres in front of the
#             back wall's face), lift (metres the throne is raised: it stands on the war dais), sink (metres into the floor)
#   floors    per area (court, walk, l1, l2, dungeon): [texture, metres per tile, tint]
#   steps     the stairs' stone colour; treads (the striped tops) tinted by tread
#   props     [model, castle-local spot (blue castle space: front wall z 3, back 29), level y, turn (deg; 0 = its front
#             faces the castle's front), height] -- along walls and terrace edges, clear of the hat shops, stairs and
#             the way to the dungeon (visual only, like the KayKit props before)
#   fires     model -> flame points in model units (burning braziers, the forge, the dungeon gate's torches)
const KITS := {
	"royal": {
		"wall": {"m": "royal_wall", "h": 2.9, "depth": 1.8, "len": 8.0},
		"terrace": {"m": "royal_terrace_wall", "body": 0.70, "depth": 1.1, "len": 6.0},
		"gatehouse": {"m": "royal_gatehouse", "s": 5.15, "out": 0.5, "door": 3.3},
		"tower": {"m": "royal_tower", "s": 4.3},
		"dungeon": {"m": "royal_dungeon_arch", "s": 4.3, "depth": 2.0},
		"throne": {"m": "royal_throne_canopy", "s": 1.75, "ys": 1.0, "back": 0.35, "lift": 0.0},
		"floors": {"court": ["royal_court", 4.0, Color(0.86, 0.84, 0.8)], "walk": ["royal_court", 4.0, Color(0.8, 0.78, 0.74)],
			"l1": ["royal_garden", 3.5, Color(0.86, 0.86, 0.82)], "l2": ["royal_marble", 4.0, Color(0.9, 0.89, 0.87)],
			"dungeon": ["royal_court", 4.0, Color(0.5, 0.5, 0.55)]},
		"steps": Color("#cbb994"), "tread": Color(1.0, 0.97, 0.9),
		"props": [
			["royal_fountain", Vector2(-6.0, 12.75), 0.0, 0.0, 2.0],
			["royal_stall", Vector2(6.0, 12.55), 0.0, 0.0, 2.4],
			["royal_topiary", Vector2(-10.6, 4.9), 0.0, 0.0, 2.3],
			["royal_topiary", Vector2(10.6, 4.9), 0.0, 0.0, 2.3],
			["royal_topiary", Vector2(-5.9, 15.2), 1.8, 0.0, 2.1],
			["royal_topiary", Vector2(5.9, 15.2), 1.8, 0.0, 2.1],
			["royal_hedge_box", Vector2(-8.6, 20.9), 1.8, 0.0, 0.9],
			["royal_hedge_box", Vector2(-13.6, 20.9), 1.8, 0.0, 0.9],
			["royal_hedge_box", Vector2(8.6, 20.9), 1.8, 0.0, 0.9],
			["royal_hedge_box", Vector2(12.4, 20.9), 1.8, 0.0, 0.9],
			["royal_topiary", Vector2(-4.4, 23.2), 3.6, 0.0, 2.0],
			["royal_topiary", Vector2(4.4, 23.2), 3.6, 0.0, 2.0],
			["royal_banner", Vector2(-3.7, 25.8), 3.6, 0.0, 3.4],
			["royal_banner", Vector2(3.7, 25.8), 3.6, 0.0, 3.4],
			["royal_statue", Vector2(-6.0, 28.2), 3.6, 0.0, 2.6],
			["royal_statue", Vector2(6.0, 28.2), 3.6, 0.0, 2.6],
		],
		"fires": {},
	},
	"war": {
		"wall": {"m": "war_wall", "h": 2.9, "depth": 1.8, "len": 8.0},
		"terrace": {"m": "war_terrace_wall", "body": 0.76, "depth": 1.1, "len": 6.0},
		"gatehouse": {"m": "war_gatehouse", "s": 4.4, "out": 0.8, "door": 3.0},
		"tower": {"m": "war_tower", "s": 2.9},
		"dungeon": {"m": "war_dungeon_gate", "s": 4.3, "depth": 2.0},
		"throne": {"m": "war_throne_dais", "s": 1.9, "ys": 1.0, "back": 1.3, "lift": 0.16, "sink": 0.11},
		"floors": {"court": ["war_earth", 5.0, Color(1, 1, 1)], "walk": ["war_planks", 3.0, Color(1, 1, 1)],
			"l1": ["war_planks", 3.0, Color(1, 1, 1)], "l2": ["war_slate", 4.0, Color(1.1, 1.1, 1.1)],
			"dungeon": ["war_slate", 4.0, Color(0.7, 0.7, 0.72)]},
		"steps": Color("#4a4e57"), "tread": Color(0.55, 0.55, 0.6),
		"props": [
			["war_forge", Vector2(-6.0, 12.4), 0.0, 0.0, 2.6],
			["war_weapon_rack", Vector2(6.0, 12.9), 0.0, 0.0, 1.6],
			["war_brazier", Vector2(-10.1, 4.6), 0.0, 0.0, 1.4],
			["war_brazier", Vector2(10.1, 4.6), 0.0, 0.0, 1.4],
			["war_dummy", Vector2(-12.0, 5.0), 0.0, 20.0, 2.0],
			["war_dummy", Vector2(-12.3, 7.3), 0.0, -15.0, 2.0],
			["war_dummy", Vector2(12.0, 5.0), 0.0, -20.0, 2.0],
			["war_brazier", Vector2(-5.9, 15.2), 1.8, 0.0, 1.3],
			["war_brazier", Vector2(5.9, 15.2), 1.8, 0.0, 1.3],
			["war_tent", Vector2(-5.8, 20.4), 1.8, 0.0, 1.9],
			["war_tent", Vector2(9.4, 20.4), 1.8, 0.0, 1.9],
			["war_tent", Vector2(12.4, 20.4), 1.8, 0.0, 1.9],
			["war_supplies", Vector2(-18.6, 28.1), 3.6, 90.0, 1.2],
			["war_supplies", Vector2(11.0, 28.1), 3.6, -90.0, 1.2],
			["war_weapon_rack", Vector2(5.8, 28.4), 3.6, 0.0, 1.6],
			["war_weapon_rack", Vector2(-5.8, 28.4), 3.6, 0.0, 1.6],
		],
		"fires": {
			"war_brazier": [Vector3(0.0, 0.36, 0.01)],
			"war_throne_dais": [Vector3(0.766, -0.18, 0.617), Vector3(-0.765, -0.18, 0.613)],
			"war_forge": [Vector3(-0.396, -0.37, -0.28)],
			"war_dungeon_gate": [Vector3(-0.739, 0.05, 0.14), Vector3(0.748, 0.05, 0.13)],
		},
	},
}

static var _mats: Dictionary = {}     # "model|team" -> ShaderMaterial

static func kit(team: int) -> Dictionary:
	return KITS[STYLE_OF_TEAM[team]]

static func piece(model: String, team: int) -> Node3D:
	# The model under a root whose origin is the middle of its foot (bottom of its bounds). Metas: "size" (its bounds,
	# model units), "lift" (model units -> root space offset, for points given in model units), "mat".
	var root := Node3D.new()
	root.name = model
	var packed: PackedScene = Stage.scene(DIR + model + ".glb")
	if packed == null:
		root.set_meta("size", Vector3.ONE)
		root.set_meta("lift", Vector3.ZERO)
		return root
	var m: Node3D = packed.instantiate()
	var meshes := m.find_children("*", "MeshInstance3D", true, false)
	var box := AABB()
	var first := true
	for mi in meshes:
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != m:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b: AABB = xf * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	var c := box.get_center()
	m.position = Vector3(-c.x, -box.position.y, -c.z)
	root.add_child(m)
	var mat := material(model, team, meshes)
	for mi in meshes:
		(mi as MeshInstance3D).material_override = mat
	root.set_meta("size", box.size)
	root.set_meta("lift", m.position)
	root.set_meta("mat", mat)
	return root

static func material(model: String, team: int, meshes: Array) -> ShaderMaterial:
	var key := "%s|%d" % [model, team]
	if _mats.has(key):
		return _mats[key]
	var mat := ShaderMaterial.new()
	mat.shader = SWAP_SHADER
	mat.set_shader_parameter("team", team)
	if not meshes.is_empty():
		var src := (meshes[0] as MeshInstance3D).get_active_material(0) as BaseMaterial3D
		if src != null:
			mat.set_shader_parameter("albedo_tex", src.albedo_texture)
	var glow_path := DIR + model + "_glow.png"
	var fiery := false
	for k in KITS:
		fiery = fiery or (KITS[k].fires as Dictionary).has(model)
	if fiery and Stage.texture(glow_path) != null:
		mat.set_shader_parameter("glow_tex", Stage.texture(glow_path))
		mat.set_shader_parameter("glow_color", FIRE_GLOW)
		mat.set_shader_parameter("glow_energy", 1.0)
	_mats[key] = mat
	return mat

static func lower_side_flip(a: Vector2, b: Vector2, height_at: Callable) -> bool:
	# Terrace pieces show their decorated face (model +Z) to the LOWER side of the edge they line. With the run's
	# rotation (-atan2 of its direction) +Z points along (-d.y, d.x); true = turn it round.
	var d := (b - a).normalized()
	var nrm := Vector2(-d.y, d.x)
	var mid := (a + b) * 0.5
	return float(height_at.call(mid + nrm * 1.0)) > float(height_at.call(mid - nrm * 1.0)) + 0.05
