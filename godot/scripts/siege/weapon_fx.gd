extends RefCounted
# Weapon effects (0.31.100). Kevin: "I want the effects to look better for the forge weapons. I also want to add effects
# for all the legendary weapons."
#  - a glow pass over the weapon's own materials (forge_glow.gdshader): a fresnel rim, a glint running up the piece,
#    glowing veins (Forge stars 2-3) and, on a legendary, its gems / lava / eye lit from its own texture (a colour key);
#  - painted sprites (assets/vfx/weapon, cut from an ElevenLabs gpt-image-2 sheet by tools/cut_vfx_sheet.py) as
#    particles, or pinned to the piece (rays behind a staff's head, a halo, a turning sigil, sparks circling it);
#  - a ribbon behind the blade in a swing (a body's melee weapon only).
# The Forge's stars: 1 Polished, glints. 2 Runed, + glowing veins and runes drifting along it, a faint ribbon.
# 3 Ascended, all in the element's colour, + fire's flames and embers, frost's snow and mist, storm's lightning and
# sparks, holy rays and motes, nature's leaves, void's wisps and a vortex, and a bright ribbon.
# Every legendary has its own signature (LEGENDARY), whether or not it has stars; with stars the two add up.
# Cosmetic only. Since 0.31.101 a match shows every live player's (with fewer effects on, theirs glow without particles).
# Particle sizes in Godot ignore the emitter's scale, so the particles are built by weapon_fx_root.gd on its first frame
# in the tree, in world units measured from the piece (everything below is in units of the piece's length).
const Eco = preload("res://scripts/meta/economy.gd")
const GLOW = preload("res://scripts/siege/forge_glow.gdshader")
const Root = preload("res://scripts/siege/weapon_fx_root.gd")
const TINT := {"common":"#ffd9a0", "rare":"#6cc4ff", "epic":"#d6a2ff", "legendary":"#ffc23d"}

# kind "p" (default): particles. tex: the sprite; n, life (s); size (x the piece's length); at: the stretch along the
# piece they come from (0 = the grip end, 1 = the business end), w: how far out to the sides (x the piece's girth);
# world: left behind in the world (rising flames, falling leaves) rather than riding the piece; vel (lengths/s), along
# the piece unless spread; grav (lengths/s^2, world up for world ones); spin (deg/s), angle (deg, random start);
# look over its life: pop (grow then shrink), shrink, grow; fade: slow, hot (white-hot first), flicker; turb: wander.
# kind "bill"/"flat": one sprite pinned at "at", facing the camera / laid across the piece; spin (rad/s), pulse.
# kind "orbit": n sprites circling the piece's axis at r (x length), speed rad/s.
const PRESETS := {
	"glints":    {"tex":"sparkle", "n":3, "life":1.0, "size":0.16, "at":[0.3, 1.0], "w":0.5, "pop":true, "angle":12.0, "core":0.9},
	"sparkle":   {"tex":"sparkle", "n":6, "life":0.9, "size":0.2, "at":[0.25, 1.0], "w":0.6, "pop":true, "angle":12.0, "core":0.9},
	"twinkle":   {"tex":"stars", "n":3, "life":1.5, "size":0.26, "at":[0.55, 1.0], "w":1.3, "pop":true, "angle":30.0, "core":0.9},
	"runes":     {"tex":"runes", "grid":2, "n":4, "life":2.6, "size":0.12, "at":[0.15, 0.85], "w":1.8, "vel":[0.03, 0.06], "spread":10.0, "fade":"slow", "core":0.7, "alpha":0.9},
	"motes":     {"tex":"dot", "n":14, "life":1.8, "size":0.045, "at":[0.3, 1.0], "w":0.9, "world":true, "vel":[0.02, 0.06], "spread":180.0, "grav":Vector3(0, 0.1, 0), "fade":"slow", "core":0.6},
	"embers":    {"tex":"dot", "n":18, "life":1.2, "size":0.03, "at":[0.5, 1.0], "w":0.8, "world":true, "vel":[0.05, 0.2], "spread":180.0, "grav":Vector3(0, 0.35, 0), "turb":1.0, "fade":"hot", "core":1.0},
	"flames":    {"tex":"flame", "n":12, "life":0.6, "size":0.2, "at":[0.65, 1.0], "w":0.5, "world":true, "vel":[0.0, 0.1], "spread":180.0, "grav":Vector3(0, 0.6, 0), "shrink":true, "fade":"hot", "core":0.8},
	"smoke":     {"tex":"smoke", "n":6, "life":1.8, "size":0.28, "at":[0.55, 1.0], "w":0.6, "world":true, "vel":[0.0, 0.05], "spread":180.0, "grav":Vector3(0, 0.08, 0), "grow":true, "spin":40.0, "angle":180.0, "fade":"slow", "core":0.0, "alpha":0.3},
	"lightning": {"tex":"lightning", "n":4, "life":0.16, "size":0.3, "at":[0.5, 1.0], "w":0.7, "angle":180.0, "fade":"flicker", "core":1.0},
	"sparks":    {"tex":"dot", "n":12, "life":0.45, "size":0.022, "at":[0.6, 1.0], "w":0.6, "world":true, "vel":[0.4, 0.9], "spread":180.0, "grav":Vector3(0, -1.5, 0), "fade":"hot", "core":1.0},
	"snow":      {"tex":"snowflake", "n":8, "life":2.4, "size":0.09, "at":[0.25, 1.0], "w":1.3, "world":true, "vel":[0.0, 0.03], "spread":180.0, "grav":Vector3(0, -0.06, 0), "spin":90.0, "angle":180.0, "turb":0.5, "fade":"slow", "core":0.6},
	"mist":      {"tex":"smoke", "n":5, "life":2.2, "size":0.32, "at":[0.3, 1.0], "w":0.8, "vel":[0.0, 0.02], "spread":180.0, "grow":true, "spin":20.0, "angle":180.0, "fade":"slow", "core":0.0, "alpha":0.2},
	"leaves":    {"tex":"leaf", "n":7, "life":2.6, "size":0.1, "at":[0.1, 1.0], "w":1.3, "world":true, "vel":[0.0, 0.04], "spread":180.0, "grav":Vector3(0, -0.06, 0), "spin":120.0, "angle":180.0, "turb":0.6, "fade":"slow", "core":0.3},
	"feathers":  {"tex":"feather", "n":5, "life":2.8, "size":0.14, "at":[0.5, 1.0], "w":1.1, "world":true, "vel":[0.0, 0.04], "spread":180.0, "grav":Vector3(0, -0.07, 0), "spin":50.0, "angle":180.0, "turb":0.5, "fade":"slow", "core":0.4},
	"wisps":     {"tex":"wisp", "n":8, "life":1.3, "size":0.18, "at":[0.5, 1.0], "w":0.6, "world":true, "vel":[0.0, 0.08], "spread":180.0, "grav":Vector3(0, 0.25, 0), "shrink":true, "core":0.6, "alpha":0.85},
	"crescents": {"tex":"crescent", "n":4, "life":2.4, "size":0.11, "at":[0.3, 1.0], "w":1.4, "vel":[0.02, 0.05], "spread":10.0, "spin":25.0, "angle":180.0, "fade":"slow", "core":0.7},
	"rays":      {"kind":"bill", "tex":"rays", "at":0.9, "size":0.75, "spin":0.25, "pulse":0.35, "alpha":0.7, "core":0.5},
	"halo":      {"kind":"flat", "tex":"ring", "at":1.08, "size":0.42, "spin":0.0, "pulse":0.25, "alpha":0.9, "core":0.6},
	"sigil":     {"kind":"bill", "tex":"sigil", "at":0.9, "size":0.5, "spin":0.35, "pulse":0.3, "alpha":0.45, "core":0.3},
	"vortex":    {"kind":"bill", "tex":"vortex", "at":0.9, "size":0.45, "spin":-1.2, "pulse":0.25, "alpha":0.5, "core":0.3},
	"orbit":     {"kind":"orbit", "tex":"sparkle", "n":3, "at":0.88, "r":0.17, "size":0.11, "speed":1.8, "pulse":0.4, "alpha":1.0, "core":0.9},
}
const STAR_FX := {1: ["glints"], 2: ["glints", "runes"], 3: ["glints"]}
const ELEMENT_FX := {
	"fire":   [{"p":"flames", "n":18, "size":0.14, "life":0.4, "at":[0.35, 1.0], "w":0.4}, {"p":"embers"}],
	"frost":  [{"p":"snow"}, {"p":"mist"}],
	"storm":  [{"p":"lightning"}, {"p":"sparks"}],
	"holy":   [{"p":"rays", "size":0.45, "alpha":0.5}, {"p":"motes"}],
	"nature": [{"p":"leaves"}, {"p":"motes", "n":8}],
	"void":   [{"p":"wisps"}, {"p":"vortex", "alpha":0.4}],
}
# the glow by stars: rim, glint, veins, brightness
const STAR_GLOW := [[0.0, 0.0, 0.0, 1.0], [0.35, 0.9, 0.0, 1.0], [0.45, 1.0, 0.4, 1.0], [0.7, 1.2, 1.0, 1.15]]

# Each legendary piece (by its mw/ model): col, its glow (rim, sweep), key [hue deg, +- deg, min saturation, min
# brightness] and key_amt for the parts of its texture that light up, trail (a swing's ribbon), solo (a pair of the
# same piece: the particles on the main hand only), fx (presets, with overrides; col defaults to the piece's).
const LEGENDARY := {
	"kingsoath_sword":        {"col":"#ffd36b", "rim":0.35, "sweep":1.0, "trail":"#ffe08a",
		"fx":[{"p":"sparkle", "col":"#fff2c4"}, {"p":"motes"}, {"p":"twinkle", "col":"#ffe7a3"}]},
	"kingsoath_shield":       {"col":"#ffd36b", "rim":0.3, "sweep":0.8},
	"worldsplitter_axe":      {"col":"#ff6a1a", "rim":0.25, "sweep":0.35, "key":[22, 16, 0.55, 0.55], "key_amt":2.4, "trail":"#ff6a1a",
		"fx":[{"p":"embers", "at":[0.6, 1.0], "col":"#ff7a2a"}, {"p":"flames", "n":6, "size":0.14, "at":[0.7, 1.0], "col":"#ff5a10"},
			{"p":"smoke", "n":4, "col":"#b0400f", "alpha":0.2}]},
	"grimgrin_scythe":        {"col":"#b36bff", "rim":0.35, "sweep":0.4, "key":[268, 22, 0.25, 0.35], "key_amt":2.0, "trail":"#a070ff",
		"fx":[{"p":"wisps", "col":"#b07aff"}, {"p":"smoke", "n":4, "col":"#6a3cc0", "alpha":0.25}]},
	"archon_staff":           {"col":"#4fc3ff", "rim":0.35, "sweep":0.5, "key":[205, 18, 0.45, 0.45], "key_amt":2.2,
		"fx":[{"p":"orbit", "col":"#8fdcff"}, {"p":"sigil", "col":"#3aa0ff", "at":0.88}, {"p":"sparkle", "n":3, "at":[0.75, 1.0], "col":"#bfeaff"}]},
	"solaris_staff":          {"col":"#ffb02e", "rim":0.3, "sweep":0.6, "key":[22, 12, 0.6, 0.6], "key_amt":1.8,
		"fx":[{"p":"rays", "col":"#ffc04a", "size":0.8}, {"p":"motes", "col":"#ffd27a", "at":[0.6, 1.0]}, {"p":"sparkle", "n":3, "at":[0.75, 1.0]}]},
	"verdict_maul":           {"col":"#ffe6a0", "rim":0.35, "sweep":1.0, "trail":"#fff0c0",
		"fx":[{"p":"runes", "n":5, "col":"#ffd56a"}, {"p":"sparkle", "n":5, "col":"#fff6d8"}]},
	"verdict_shield":         {"col":"#ffe6a0", "rim":0.3, "sweep":0.8},
	"kingsguard_sword":       {"col":"#5a8cff", "rim":0.4, "sweep":0.9, "key":[220, 15, 0.6, 0.5], "key_amt":1.6, "trail":"#7fa6ff",
		"fx":[{"p":"sparkle", "col":"#cfe0ff"}, {"p":"twinkle", "col":"#ffd770"}, {"p":"motes", "col":"#6f9bff"}]},
	"kingsguard_shield":      {"col":"#5a8cff", "rim":0.3, "sweep":0.7},
	"skyrender_axe":          {"col":"#6fd2ff", "rim":0.4, "sweep":0.5, "key":[210, 20, 0.45, 0.45], "key_amt":2.0, "trail":"#9fe4ff",
		"fx":[{"p":"lightning", "n":5, "col":"#9fe6ff"}, {"p":"sparks", "col":"#c8f2ff"}]},
	"moonfang_dagger":        {"col":"#b98aff", "rim":0.4, "sweep":0.7, "key":[268, 22, 0.3, 0.5], "key_amt":2.0, "trail":"#c09aff", "solo":true,
		"fx":[{"p":"crescents", "col":"#d4b8ff"}, {"p":"sparkle", "n":3, "col":"#e6d6ff"}]},
	"dawnpiercer_bow":        {"col":"#ffe08a", "rim":0.35, "sweep":0.6, "key":[85, 28, 0.35, 0.3], "key_amt":1.2,
		"fx":[{"p":"leaves", "col":"#a6e05a"}, {"p":"motes", "col":"#ffe39a", "at":[0.0, 1.0], "w":1.2}]},
	"emberheart_staff":       {"col":"#ff8a2a", "rim":0.3, "sweep":0.5,
		"fx":[{"p":"flames", "col":"#ff7a1a", "at":[0.82, 1.0], "size":0.16}, {"p":"embers", "col":"#ffb04a", "at":[0.75, 1.0]},
			{"p":"feathers", "n":3, "col":"#ff9a3a", "at":[0.8, 1.0]}]},
	"seraph_staff":           {"col":"#fff1c8", "rim":0.35, "sweep":0.6,
		"fx":[{"p":"halo", "col":"#ffe6a0"}, {"p":"feathers", "col":"#fff4d6", "size":0.1, "alpha":0.75}, {"p":"motes", "col":"#fff3c8", "at":[0.6, 1.0]}]},
	"goldensledge_hammer":    {"col":"#ffcf3a", "rim":0.35, "sweep":1.0, "trail":"#ffd76a",
		"fx":[{"p":"sparks", "n":14, "col":"#ffc84a", "at":[0.75, 1.0]}, {"p":"sparkle", "n":4, "col":"#fff0b0", "at":[0.7, 1.0]}]},
	"oathbound_hammer":       {"col":"#ffd88a", "rim":0.35, "sweep":0.8, "trail":"#ffe3a0",
		"fx":[{"p":"rays", "col":"#ffdc8a", "at":0.88, "size":0.6, "alpha":0.55}, {"p":"motes", "col":"#ffe3a0"}]},
	"oathbound_shield":       {"col":"#ffd88a", "rim":0.3, "sweep":0.7},
	"bloodroar_demon":        {"col":"#ff3a2a", "rim":0.35, "sweep":0.4, "key":[12, 18, 0.5, 0.3], "key_amt":2.4, "trail":"#ff3020",
		"fx":[{"p":"embers", "col":"#ff4020"}, {"p":"smoke", "n":4, "col":"#a01810", "alpha":0.25}]},
	"lichcrown_staff":        {"col":"#5cff8a", "rim":0.35, "sweep":0.4,
		"fx":[{"p":"flames", "n":10, "col":"#4dff7a", "at":[0.84, 1.0], "size":0.15}, {"p":"wisps", "n":5, "col":"#7dffa0", "at":[0.7, 1.0]}]},
	"lastbreath_dagger":      {"col":"#a070ff", "rim":0.4, "sweep":0.6, "key":[272, 22, 0.25, 0.35], "key_amt":2.0, "trail":"#9a60ff", "solo":true,
		"fx":[{"p":"smoke", "n":5, "col":"#7a44d8", "alpha":0.3, "at":[0.4, 1.0]}, {"p":"wisps", "n":4, "size":0.14, "col":"#c09cff"}]},
	"hawksjudgment_crossbow": {"col":"#ffd36b", "rim":0.35, "sweep":0.9,
		"fx":[{"p":"feathers", "n":4, "col":"#ffd77a", "size":0.1, "alpha":0.8, "at":[0.0, 1.0], "w":1.0}, {"p":"sparkle", "n":5, "col":"#fff2c4", "at":[0.0, 1.0], "w":0.9}]},
	"astral_staff":           {"col":"#b06bff", "rim":0.35, "sweep":0.5, "key":[268, 22, 0.4, 0.45], "key_amt":2.0,
		"fx":[{"p":"orbit", "n":4, "col":"#e6d0ff"}, {"p":"twinkle", "col":"#c9a6ff"}, {"p":"vortex", "col":"#7a4cff", "alpha":0.35}]},
	"astral_book":            {"col":"#6f7bff", "rim":0.35, "sweep":0.5,
		"fx":[{"p":"sigil", "col":"#8a7dff", "at":0.5, "size":1.0, "alpha":0.35}, {"p":"motes", "n":10, "col":"#a99cff", "at":[0.0, 1.0], "w":1.0}]},
}
const NO_SWING := ["bow", "staff", "wand", "spellbook", "book", "tome", "shield", "quiver", "orb", "lantern"]

static var _glow := {}               # glow settings -> ShaderMaterial
static var _base := {}               # base material id|glow key -> the base material with that glow as next_pass

static func legendary(file: String) -> Dictionary:
	return LEGENDARY.get(file.substr(3), {}) if file.begins_with("mw/") else {}

static func wants(file: String, fx: Dictionary) -> bool:
	return int(fx.get("stars", 0)) > 0 or not legendary(file).is_empty()

static func color(fx: Dictionary) -> Color:
	# the stars' colour: the element's at 3 stars, else the rarity's
	if int(fx.get("stars", 0)) >= Eco.FORGE_STARS.size() and Eco.ELEMENT_COLOR.has(str(fx.get("element", ""))):
		return Color(str(Eco.ELEMENT_COLOR[str(fx.element)]))
	return Color(str(TINT.get(str(fx.get("rarity", "common")), "#ffd9a0")))

static func box_of(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != null and n != model:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b: AABB = xf * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

static func swings(template: String) -> bool:
	if template == "":
		return false
	var t := template.to_lower()
	for w in NO_SWING:
		if t.contains(w):
			return false
	return true

static func spec(entry, col: Color, mul := 1.0) -> Dictionary:
	# a preset with its overrides and colour
	var e: Dictionary = {"p": entry} if entry is String else entry
	var out: Dictionary = PRESETS.get(str(e.p), {}).duplicate()
	for k in e:
		if k != "p":
			out[k] = e[k]
	out["col"] = Color(str(e.col)) if e.has("col") else col
	if out.has("n") and str(out.get("kind", "p")) == "p":
		out["n"] = maxi(1, int(round(float(out.n) * mul)))
	return out

static func apply(model: Node3D, file: String, fx: Dictionary, main := true, template := "", lite := false) -> void:
	# the glow on this piece, and its particles / ribbon (built on its first frame in the tree, weapon_fx_root.gd).
	# template: the KayKit file the piece is held like (a body's weapon); "" for a piece on show (no ribbon).
	# lite: the glow only (another player's weapon with fewer effects on, 0.31.101)
	var stars := clampi(int(fx.get("stars", 0)), 0, Eco.FORGE_STARS.size())
	var leg := legendary(file)
	if stars <= 0 and leg.is_empty():
		return
	var box := box_of(model)
	var star_col := color(fx)
	var leg_col := Color(str(leg.get("col", "#ffffff")))
	# ---- the glow
	var g: Array = STAR_GLOW[stars] if stars > 0 else [float(leg.get("rim", 0.3)), float(leg.get("sweep", 0.6)), 0.0, 1.0]
	var gcol := star_col if stars > 0 else leg_col
	var key: Array = leg.get("key", [])
	var key_amt := float(leg.get("key_amt", 1.6)) if not key.is_empty() else 0.0
	var span := snappedf(maxf(box.size.y, 0.2), 0.05)
	var gk := "%s|%.2f|%.2f|%.2f|%.2f|%.2f|%s|%.2f" % [gcol.to_html(), g[0], g[1], g[2], g[3], span, str(key), key_amt]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for surf in m.mesh.get_surface_count():
			var base := m.get_active_material(surf)
			if base == null:
				continue
			var tex: Texture2D = (base as BaseMaterial3D).albedo_texture if base is BaseMaterial3D else null
			var mk := gk + ("|%d" % tex.get_instance_id() if key_amt > 0.0 and tex != null else "")
			if not _glow.has(mk):
				var gm := ShaderMaterial.new()
				gm.shader = GLOW
				gm.set_shader_parameter("tint", gcol)
				gm.set_shader_parameter("rim", g[0])
				gm.set_shader_parameter("sweep", g[1])
				gm.set_shader_parameter("veins", g[2])
				gm.set_shader_parameter("boost", g[3])
				gm.set_shader_parameter("span", span)
				if key_amt > 0.0 and tex != null:
					gm.set_shader_parameter("albedo_tex", tex)
					gm.set_shader_parameter("key", Vector4(float(key[0]) / 360.0, float(key[1]) / 360.0, float(key[2]), float(key[3])))
					gm.set_shader_parameter("key_amt", key_amt)
				_glow[mk] = gm
			var bk := "%d|%s" % [base.get_instance_id(), mk]
			if not _base.has(bk):
				var dup: Material = base.duplicate()
				dup.next_pass = _glow[mk]
				_base[bk] = dup
			m.set_surface_override_material(surf, _base[bk])
	# ---- particles, pinned sprites, the ribbon
	if lite:
		return
	var specs: Array = []
	if main and stars > 0:
		for e in STAR_FX[stars]:
			if str(e) == "glints" and not leg.is_empty():
				continue                                  # (a legendary sparkles its own way)
			specs.append(spec(e, star_col))
		if stars >= Eco.FORGE_STARS.size():
			for e in ELEMENT_FX.get(str(fx.get("element", "")), []):
				specs.append(spec(e, star_col, 0.6 if not leg.is_empty() else 1.0))
	if not leg.is_empty() and (main or not bool(leg.get("solo", false))):
		for e in leg.get("fx", []):
			specs.append(spec(e, leg_col))
	var trail := Color(0, 0, 0, 0)
	if swings(template):
		if leg.has("trail"):
			trail = Color(str(leg.trail))
		elif stars >= 2:
			trail = Color(star_col, 0.45 if stars == 2 else 1.0)
	if specs.is_empty() and trail.a <= 0.0:
		return
	var root := Root.new()
	root.name = "WeaponFx"
	root.box = box
	root.specs = specs
	root.trail = trail
	model.add_child(root)
