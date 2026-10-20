extends RefCounted
# Weapon effects (0.31.100). Kevin: "I want the effects to look better for the forge weapons. I also want to add effects
# for all the legendary weapons." 0.31.188 (Kevin: "Remove the forge and the individual weapon skins. I only want the
# cosmetics to be an entire outfit. Each outfit has its own specific looking weapon"): the Forge's stars and elements are
# gone with the weapons; what's left is a signature weapon's own look (SIGNATURE) -- an outfit's weapon:
#  - a glow pass over the weapon's own materials (forge_glow.gdshader): a fresnel rim, a glint running up the piece and
#    its gems / lava / eye lit from its own texture (a colour key);
#  - painted sprites (assets/vfx/weapon, cut from an ElevenLabs gpt-image-2 sheet by tools/cut_vfx_sheet.py) as
#    particles, or pinned to the piece (rays behind a staff's head, a halo, a turning sigil, sparks circling it);
#  - a ribbon behind the blade in a swing (a body's melee weapon only).
# Cosmetic only. A match shows every live player's (with fewer effects on, theirs glow without particles).
# Particle sizes in Godot ignore the emitter's scale, so the particles are built by weapon_fx_root.gd on its first frame
# in the tree, in world units measured from the piece (everything below is in units of the piece's length).
const GLOW = preload("res://scripts/siege/forge_glow.gdshader")
const Root = preload("res://scripts/siege/weapon_fx_root.gd")

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
# Each signature piece (by its mw/ model): col, its glow (rim, sweep), key [hue deg, +- deg, min saturation, min
# brightness] and key_amt for the parts of its texture that light up, trail (a swing's ribbon), solo (a pair of the
# same piece: the particles on the main hand only), fx (presets, with overrides; col defaults to the piece's), spin
# (0.31.103: parts of the model cut into their own nodes by tools/weapon_spin_parts.py, turned about their own +Y at
# speed rad/s and rocked +-wobble degrees about their X at wobble_speed).
# (0.31.100-0.31.187: the legendary weapons' -- Kingsoath, the Eye of the Archon, the Astral Codex ...)
const SIGNATURE := {
	"lion_sword":           {"col":"#ffd36b", "rim":0.3, "sweep":0.9, "trail":"#ffe08a", "fx":[{"p":"sparkle", "n":4, "col":"#fff2c4"}]},
	"lion_shield":          {"col":"#ffd36b", "rim":0.25, "sweep":0.7},
	"mammoth_axe":          {"col":"#fff1d6", "rim":0.2, "sweep":0.4, "trail":"#e8dcc0", "fx":[{"p":"snow", "n":5}]},
	"coin_dagger":          {"col":"#ffcf3a", "rim":0.3, "sweep":0.8, "trail":"#c47bff", "solo":true, "fx":[{"p":"sparkle", "n":3, "col":"#ffe08a"}]},
	"orchard_bow":          {"col":"#ff8fb0", "rim":0.25, "sweep":0.5, "fx":[{"p":"leaves", "n":5, "col":"#ffb0c8"}]},
	"phoenix_staff":        {"col":"#ff7a1a", "rim":0.3, "sweep":0.5, "fx":[{"p":"flames", "col":"#ff7a1a", "at":[0.8, 1.0], "size":0.16},
		{"p":"embers", "col":"#ffb04a", "at":[0.75, 1.0]}, {"p":"feathers", "n":3, "col":"#ff9a3a", "at":[0.8, 1.0]}]},
	"bell_scepter":         {"col":"#ffd27a", "rim":0.3, "sweep":0.6, "fx":[{"p":"motes", "n":8, "col":"#fff3c8", "at":[0.6, 1.0]},
		{"p":"rays", "col":"#ffe0a0", "size":0.45, "alpha":0.4}]},
	"ember_hammer":         {"col":"#ff6a1a", "rim":0.25, "sweep":0.35, "key":[20, 16, 0.55, 0.5], "key_amt":2.4, "trail":"#ff6a1a",
		"fx":[{"p":"embers", "col":"#ff7a2a", "at":[0.6, 1.0]}, {"p":"smoke", "n":3, "col":"#5a3020", "alpha":0.2}]},
	"ashen_shield":         {"col":"#ff6a1a", "rim":0.2, "sweep":0.3, "key":[20, 16, 0.55, 0.5], "key_amt":2.2},
	"bloodmoon_greatsword": {"col":"#ff3a2a", "rim":0.35, "sweep":0.4, "key":[5, 14, 0.5, 0.35], "key_amt":2.0, "trail":"#ff3020",
		"fx":[{"p":"embers", "n":10, "col":"#ff4020"}, {"p":"smoke", "n":3, "col":"#a01810", "alpha":0.2}]},
	"ribbon_dagger":        {"col":"#e0486a", "rim":0.35, "sweep":0.6, "trail":"#e0486a", "solo":true,
		"fx":[{"p":"smoke", "n":3, "col":"#7a2040", "alpha":0.25}]},
	"wolf_crossbow":        {"col":"#cfd6e0", "rim":0.25, "sweep":0.5, "fx":[{"p":"mist", "col":"#cfd6e0", "alpha":0.15}]},
	"orrery_staff":         {"col":"#7fb8ff", "rim":0.35, "sweep":0.5, "key":[210, 20, 0.45, 0.45], "key_amt":2.0,
		"fx":[{"p":"orbit", "n":3, "col":"#ffe08a"}, {"p":"twinkle", "col":"#c9d8ff"}]},
	"starchart_tome":       {"col":"#ffd36b", "rim":0.3, "sweep":0.5, "fx":[{"p":"twinkle", "col":"#ffe7a3", "at":[0.0, 1.0], "w":1.0}]},
	"lantern_shovel":       {"col":"#7dff9a", "rim":0.3, "sweep":0.3, "key":[120, 30, 0.4, 0.4], "key_amt":2.2,
		"fx":[{"p":"wisps", "n":5, "col":"#8dffa8", "at":[0.75, 0.95]}]},
	"geode_hammer":         {"col":"#b06bff", "rim":0.3, "sweep":0.4, "key":[275, 25, 0.35, 0.35], "key_amt":2.2, "trail":"#b06bff",
		"fx":[{"p":"sparkle", "col":"#d9b8ff", "at":[0.7, 1.0]}]},
	"geode_shield":         {"col":"#b06bff", "rim":0.25, "sweep":0.3, "key":[275, 25, 0.35, 0.35], "key_amt":2.0},
	"dragon_halberd":       {"col":"#ff6a3a", "rim":0.3, "sweep":0.5, "trail":"#ff6a3a", "fx":[{"p":"embers", "n":10, "col":"#ff8a3a", "at":[0.75, 1.0]}]},
	"rose_rapier":          {"col":"#ffd36b", "rim":0.3, "sweep":0.9, "trail":"#ff5a7a", "fx":[{"p":"leaves", "n":4, "col":"#d0304a", "at":[0.0, 0.4]}]},
	"thorn_stiletto":       {"col":"#8fd16f", "rim":0.25, "sweep":0.5},
	"lightning_rod_staff":  {"col":"#6fb6ff", "rim":0.35, "sweep":0.5, "key":[205, 18, 0.45, 0.45], "key_amt":2.2,
		"fx":[{"p":"lightning", "n":4, "col":"#9fe6ff", "at":[0.8, 1.0]}, {"p":"sparks", "col":"#c8f2ff", "at":[0.8, 1.0]}]},
	"brass_blunderbuss":    {"col":"#ffcf6a", "rim":0.25, "sweep":0.7, "fx":[{"p":"smoke", "n":3, "col":"#e8e2d6", "alpha":0.2, "at":[0.85, 1.0]}]},
	"blossom_staff":        {"col":"#ffb0d0", "rim":0.3, "sweep":0.4, "fx":[{"p":"leaves", "n":7, "col":"#ffb0c8", "at":[0.7, 1.0]},
		{"p":"motes", "n":6, "col":"#fff0f6", "at":[0.7, 1.0]}]},
}
const NO_SWING := ["bow", "staff", "wand", "spellbook", "book", "tome", "shield", "quiver", "orb", "lantern"]

static var _glow := {}               # glow settings -> ShaderMaterial
static var _base := {}               # base material id|glow key -> the base material with that glow as next_pass

static func signature(file: String) -> Dictionary:
	return SIGNATURE.get(file.substr(3), {}) if file.begins_with("mw/") else {}

static func wants(file: String) -> bool:
	return not signature(file).is_empty()

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

static func apply(model: Node3D, file: String, main := true, template := "", lite := false) -> void:
	# the glow on this piece, and its particles / ribbon (built on its first frame in the tree, weapon_fx_root.gd).
	# template: the KayKit file the piece is held like (a body's weapon); "" for a piece on show (no ribbon).
	# lite: the glow only (another player's weapon with fewer effects on, 0.31.101)
	var leg := signature(file)
	if leg.is_empty():
		return
	var box := box_of(model)
	var leg_col := Color(str(leg.get("col", "#ffffff")))
	# ---- the glow
	var g: Array = [float(leg.get("rim", 0.3)), float(leg.get("sweep", 0.6)), 0.0, 1.0]
	var gcol := leg_col
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
	if main or not bool(leg.get("solo", false)):
		for e in leg.get("fx", []):
			specs.append(spec(e, leg_col))
	var trail := Color(0, 0, 0, 0)
	if swings(template) and leg.has("trail"):
		trail = Color(str(leg.trail))
	var spins: Array = leg.get("spin", [])
	if specs.is_empty() and trail.a <= 0.0 and spins.is_empty():
		return
	var root := Root.new()
	root.name = "WeaponFx"
	root.box = box
	root.specs = specs
	root.trail = trail
	root.spins = spins
	model.add_child(root)
