extends RefCounted
## Supplies the 3D figures and props. A generated model in assets/models/<name>/<name>.glb is
## used when it exists; otherwise a chunky stand-in is built from primitive shapes, so the game
## always runs and any card can be played before its model is made.
##
## team 0 is the local player's army (Union blue); team 1 is the enemy (Confederate crimson).

const MusketDrill = preload("res://scripts/view/musket_drill.gd")

const DIR := "res://assets/models/"

# card id -> [team 0 model, team 1 model]
const SOLDIER_MODELS := {
	"line_infantry": ["u_line", "c_line"],
	"skirmishers": ["u_skirm", "c_skirm"],
	"militia": ["u_militia", "c_militia"],
	"scouts": ["u_cav", "c_cav"],
	"heavy_cavalry": ["u_cav", "c_cav"],
	"field_gun": ["u_line", "c_line"],
	# The ten later cards have no models of their own yet: they borrow the nearest existing
	# figure, tinted (CARD_TINT) so they can be told apart on the field.
	"sharpshooters": ["u_skirm", "c_skirm"],
	"zouaves": ["u_line", "c_line"],
	"dragoons": ["u_cav", "c_cav"],
	"general": ["u_cav", "c_cav"],
	"horse_artillery": ["u_line", "c_line"],
	"gatling_gun": ["u_line", "c_line"],
	"howitzer": ["u_line", "c_line"],
	# The second set: borrowed figures too, until they have models of their own.
	"conscripts": ["u_militia", "c_militia"],
	"voltigeurs": ["u_skirm", "c_skirm"],
	"riflemen": ["u_skirm", "c_skirm"],
	"pioneers": ["u_militia", "c_militia"],
	"grenadiers": ["u_line", "c_line"],
	"old_guard": ["u_line", "c_line"],
	"cossacks": ["u_cav", "c_cav"],
	"hussars": ["u_cav", "c_cav"],
	"lancers": ["u_cav", "c_cav"],
	"cuirassiers": ["u_cav", "c_cav"],
	"drummer_boy": ["u_militia", "c_militia"],
	"highland_piper": ["u_line", "c_line"],
	"marshal": ["u_cav", "c_cav"],
	"coehorn_mortar": ["u_line", "c_line"],
	"mountain_howitzer": ["u_line", "c_line"],
	"rifled_gun": ["u_line", "c_line"],
	"rocket_troop": ["u_skirm", "c_skirm"],
	"siege_gun": ["u_line", "c_line"],
	"great_mortar": ["u_line", "c_line"],
}
# Leaders who go on foot; every other leader is mounted.
const FOOT_LEADERS := ["drummer_boy", "highland_piper"]
const ON_FOOT_MODELS := {"dragoons": ["u_skirm", "c_skirm"]}      # what a mounted card looks like dismounted
const HEIGHTS := {"infantry": 2.1, "artillery": 2.1, "skirmishers": 2.2, "militia": 2.0, "scouts": 2.8, "heavy_cavalry": 3.2,
		"sharpshooters": 2.3, "zouaves": 2.25, "dragoons": 2.9, "general": 3.5,
		"conscripts": 1.9, "voltigeurs": 2.0, "riflemen": 2.2, "pioneers": 2.1, "grenadiers": 2.45, "old_guard": 2.5,
		"cossacks": 2.6, "hussars": 2.85, "lancers": 2.95, "cuirassiers": 3.35, "drummer_boy": 1.7, "highland_piper": 2.2, "marshal": 3.7}
const CARD_TINT := {"sharpshooters": Color(0.78, 0.95, 0.78), "zouaves": Color(1.32, 0.7, 0.64), "dragoons": Color(1.18, 1.06, 0.55),
		"general": Color(1.3, 1.14, 0.58), "gatling_gun": Color(0.5, 0.52, 0.58), "howitzer": Color(0.78, 0.7, 0.58),
		"conscripts": Color(0.88, 0.86, 0.8), "voltigeurs": Color(0.85, 1.05, 1.2), "riflemen": Color(0.6, 0.85, 0.6),
		"pioneers": Color(0.9, 0.78, 0.62), "grenadiers": Color(0.72, 0.72, 0.95), "old_guard": Color(0.55, 0.58, 0.9),
		"cossacks": Color(1.1, 0.85, 0.7), "hussars": Color(1.25, 0.8, 1.05), "lancers": Color(0.85, 1.2, 1.05),
		"cuirassiers": Color(1.18, 1.2, 1.3), "drummer_boy": Color(1.1, 1.0, 0.9), "highland_piper": Color(0.8, 1.15, 0.85),
		"marshal": Color(1.35, 1.2, 1.25), "coehorn_mortar": Color(0.8, 0.72, 0.6), "mountain_howitzer": Color(0.9, 0.8, 0.65),
		"rifled_gun": Color(0.55, 0.57, 0.62), "rocket_troop": Color(1.2, 0.8, 0.7), "siege_gun": Color(0.6, 0.62, 0.66),
		"great_mortar": Color(0.55, 0.55, 0.6)}
# Each gun card's piece: height, and how much of the barrel's length it keeps.
const GUNS := {"field_gun": [1.8, 1.0], "horse_artillery": [1.45, 1.0], "gatling_gun": [1.5, 0.85], "howitzer": [1.75, 0.62],
		"coehorn_mortar": [1.05, 0.5], "mountain_howitzer": [1.3, 0.62], "rifled_gun": [1.75, 1.3], "rocket_troop": [1.2, 1.4],
		"siege_gun": [2.4, 1.25], "great_mortar": [2.7, 0.55]}
const SHARED_CLIPS := "u_line"     # rigged characters without clips of their own borrow this one's
# Degrees to turn each generated model about the vertical so that it faces "forward" (-Z):
# characters and riders come facing +Z, gun muzzles along -X, bridge and fence run along X.
const YAW := {"u_line": 180.0, "c_line": 180.0, "u_skirm": 180.0, "c_skirm": 180.0, "u_militia": 180.0,
		"c_militia": 180.0, "u_cav": 180.0, "c_cav": 180.0, "cannon": -90.0, "battery": -90.0,
		"bridge": 90.0, "fence": 90.0}
const CLIPS := ["idle", "walk", "run", "fire", "death", "idle_calm", "march", "panic", "death_forward", "hit", "cheer", "stab", "kneel", "knockback"]
const LOOPING := ["idle", "walk", "run", "idle_calm", "march", "panic", "cheer"]
# The part of a library clip that is actually wanted, in seconds [from, to], and how it repeats.
# The thrust has a long wind-up, the kneel a still second before it starts, the flinch a slow
# recovery; the game plays only the useful stretch.
const TRIM := {"stab": [1.5, 2.25], "kneel": [0.9, 2.57], "hit": [0.0, 1.0]}
const PINGPONG := ["stab"]             # played forward then back, so the thrust repeats smoothly
const SPEED := {"hit": 1.7, "stab": 1.25, "kneel": 1.6, "knockback": 1.15, "panic": 1.15}
# What to play when a character has no clip of that name.
const FALLBACK := {"idle_calm": "idle", "march": "walk", "panic": "run", "death_forward": "death",
		"hit": "idle", "cheer": "idle", "stab": "idle", "kneel": "idle"}

const SKIN := Color("f2c49b")
const BLACK := Color("1c1c22")
const WOOD := Color("8a5a2e")
const STEEL := Color("c8ccd4")
const BRASS := Color("f2b632")
const WHITE := Color("f4f1e8")
const CRIMSON := Color("c81e3a")
const BLUE := Color("2456c9")

static var _scenes: Dictionary = {}       # name -> PackedScene or null
# Stonework and timber that came out of the generator darker than the painted look wants:
# their texture is multiplied by this (values above 1 brighten).
const LIFT := {"bridge": Color(1.22, 1.2, 1.16), "fence": Color(1.1, 1.07, 1.02)}

# The most triangles each model is drawn with. The generated models carry thousands of
# triangles, but on the battlefield a soldier is about a hundred pixels tall and a tree two
# hundred across: drawn in full, most triangles would be smaller than a few pixels, which is
# the costliest thing a graphics chip can be asked to draw and shows nothing. Each model is
# cut down once, when first made, to the coarsest of its own detail levels that fits (the
# importer builds those levels; see trimmed()). The engine's own distance-based choice is not
# used: on a dense phone screen it kept far too much.
const BUDGET := {
	"u_line": 800, "c_line": 800, "u_skirm": 800, "c_skirm": 800, "u_militia": 800, "c_militia": 800,
	"u_cav": 1200, "c_cav": 1200, "cannon": 1050, "musket": 100,
	"farmhouse": 14000, "battery": 3100, "bridge": 2100,
	"tree": 1350, "tree_oak": 1900, "tree_pine": 1350, "tree_birch": 1350,
	"bush": 320, "fence": 400, "rocks": 320, "log": 270,
}
static var _cut_meshes: Dictionary = {}   # "mesh id|budget" -> ArrayMesh

static var _libraries: Dictionary = {}    # name -> AnimationLibrary or null
static var _red_tex: Dictionary = {}      # name -> Texture2D or null
static var _meshes: Dictionary = {}       # stand-in key -> ArrayMesh
static var _mats: Dictionary = {}


# ==========================================================================================
# Generated models
# ==========================================================================================

static func has_model(name: String) -> bool:
	return _scene(name) != null


static func _scene(name: String) -> PackedScene:
	if not _scenes.has(name):
		var path := DIR + name + "/" + name + ".glb"
		_scenes[name] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[name]


## An instance of a generated model inside a holder node, or null if there is no such model.
## Scale and place it with fit_height() or fit_footprint().
static func make(name: String, team: int, budget: int = -1) -> Node3D:
	var scene := _scene(name)
	if scene == null:
		return null
	var holder := Node3D.new()
	var inner: Node3D = scene.instantiate()
	inner.name = "Model"
	inner.rotation.y = deg_to_rad(float(YAW.get(name, 0.0)))
	holder.add_child(inner)
	if budget > 0 or BUDGET.has(name):
		trim(inner, budget if budget > 0 else int(BUDGET[name]))
	var red: Texture2D = _red_texture(name) if team == 1 else null
	if red != null or LIFT.has(name):
		for mi: MeshInstance3D in inner.find_children("*", "MeshInstance3D", true, false):
			for surface in mi.mesh.get_surface_count():
				var base := mi.mesh.surface_get_material(surface)
				if base is BaseMaterial3D:
					var copy: BaseMaterial3D = base.duplicate()
					if red != null:
						copy.albedo_texture = red
					if LIFT.has(name):
						copy.albedo_color = LIFT[name]
					mi.set_surface_override_material(surface, copy)
	return holder


## Swaps every mesh under a node for a version of itself with at most "budget" triangles.
static func trim(node: Node, budget: int) -> void:
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null:
			mi.mesh = trimmed(mi.mesh, budget)


## A mesh with the same vertices as "mesh" but only the triangles of its coarsest detail level
## that still has no more than "budget" of them (or its coarsest level, if none is that small).
## Made once per mesh and budget, then shared. The result has a single, fixed level of detail.
static func trimmed(mesh: Mesh, budget: int) -> Mesh:
	var key := "%d|%d" % [mesh.get_rid().get_id(), budget]
	if _cut_meshes.has(key):
		return _cut_meshes[key]
	var out := ArrayMesh.new()
	var changed := false
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var data: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), s)
		var wide: bool = int(data.get("vertex_count", 0)) > 65535
		var full: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if full.size() / 3 > budget:
			# Levels run from fine to coarse: take the first that fits, else the coarsest.
			var pick: PackedByteArray = PackedByteArray()
			for level: Dictionary in data.get("lods", []):
				pick = level["index_data"]
				if pick.size() / (4 if wide else 2) / 3 <= budget:
					break
			if not pick.is_empty():
				var indices := PackedInt32Array()
				if wide:
					indices = pick.to_int32_array()
				else:
					indices.resize(pick.size() / 2)
					for i in indices.size():
						indices[i] = pick.decode_u16(i * 2)
				arrays[Mesh.ARRAY_INDEX] = indices
				changed = true
		var flags := 0
		if mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS:
			flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		out.surface_set_material(s, mesh.surface_get_material(s))
	_cut_meshes[key] = out if changed else mesh
	return _cut_meshes[key]


static func _red_texture(name: String) -> Texture2D:
	if not _red_tex.has(name):
		var path := DIR + name + "/" + name + "_red.png"
		_red_tex[name] = load(path) if ResourceLoader.exists(path) else null
	return _red_tex[name]


## Bounds of everything drawn under the holder, in the holder's own space.
static func bounds(holder: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in holder.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		if mi.skin != null:
			# A skinned mesh is drawn at its bind size whatever its rig's node scales are
			# (the generated rigs use centimetre bones under a 0.01 armature), so only the
			# model root's own transform applies.
			n = holder.get_node("Model")
			xf = (n as Node3D).transform
			n = null
		while n != null and n != holder:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func _apply_fit(holder: Node3D, scale_by: float, box: AABB) -> void:
	var inner: Node3D = holder.get_node("Model")
	inner.scale *= scale_by
	var centre := box.get_center() * scale_by
	inner.position -= Vector3(centre.x, box.position.y * scale_by, centre.z)


static func fit_height(holder: Node3D, height: float) -> void:
	var box := bounds(holder)
	if box.size.y > 0.0001:
		_apply_fit(holder, height / box.size.y, box)


static func fit_footprint(holder: Node3D, width: float, depth: float) -> void:
	var box := bounds(holder)
	if box.size.x > 0.0001 and box.size.z > 0.0001:
		_apply_fit(holder, minf(width / box.size.x, depth / box.size.z), box)


## The five animation clips of a rigged character, gathered from its anim_<clip>.glb files.
static func _library(name: String) -> AnimationLibrary:
	if _libraries.has(name):
		return _libraries[name]
	var lib := AnimationLibrary.new()
	var found := 0
	for clip: String in CLIPS:
		var path := DIR + name + "/anim_" + clip + ".glb"
		if not ResourceLoader.exists(path):
			continue
		var temp: Node = (load(path) as PackedScene).instantiate()
		var player: AnimationPlayer = temp.find_child("AnimationPlayer", true, false)
		if player != null:
			var best: Animation = null
			for anim_name: StringName in player.get_animation_list():
				var a := player.get_animation(anim_name)
				if best == null or a.length > best.length:
					best = a
			if best != null:
				var copy: Animation = best.duplicate()
				if TRIM.has(clip):
					copy = _trimmed(copy, float(TRIM[clip][0]), float(TRIM[clip][1]))
				if clip in PINGPONG:
					copy.loop_mode = Animation.LOOP_PINGPONG
				else:
					copy.loop_mode = Animation.LOOP_LINEAR if clip in LOOPING else Animation.LOOP_NONE
				_keep_in_place(copy)
				lib.add_animation(clip, copy)
				found += 1
		temp.free()
	if found == 0 and name != SHARED_CLIPS:
		# Every generated rig has the same bones, so one character's clips drive them all.
		_libraries[name] = _borrowed_library()
	else:
		_libraries[name] = lib if found > 0 else null
	return _libraries[name]


## A new clip holding only the stretch of a clip between two times, resampled 30 times a second.
static func _trimmed(src: Animation, from: float, to: float) -> Animation:
	var out := Animation.new()
	to = minf(to, src.length)
	out.length = maxf(0.05, to - from)
	for track in src.get_track_count():
		var kind := src.track_get_type(track)
		if kind != Animation.TYPE_POSITION_3D and kind != Animation.TYPE_ROTATION_3D and kind != Animation.TYPE_SCALE_3D:
			continue
		var t := out.add_track(kind)
		out.track_set_path(t, src.track_get_path(track))
		var steps := int(ceil(out.length * 30.0))
		for i in steps + 1:
			var at := minf(from + i / 30.0, to)
			if kind == Animation.TYPE_POSITION_3D:
				out.position_track_insert_key(t, at - from, src.position_track_interpolate(track, at))
			elif kind == Animation.TYPE_ROTATION_3D:
				out.rotation_track_insert_key(t, at - from, src.rotation_track_interpolate(track, at))
			else:
				out.scale_track_insert_key(t, at - from, src.scale_track_interpolate(track, at))
	return out


## The shared clips with only what transfers between characters: bone rotations, and the hips'
## movement. The clips' other position and scale tracks hold the first character's own bone
## lengths, which would pull every borrower toward his proportions.
static func _borrowed_library() -> AnimationLibrary:
	if _libraries.has("_borrowed"):
		return _libraries["_borrowed"]
	var source := _library(SHARED_CLIPS)
	var out: AnimationLibrary = null
	if source != null:
		out = AnimationLibrary.new()
		for clip: StringName in source.get_animation_list():
			var anim: Animation = source.get_animation(clip).duplicate()
			for track in range(anim.get_track_count() - 1, -1, -1):
				var kind := anim.track_get_type(track)
				var is_hips := String(anim.track_get_path(track)).to_lower().ends_with(":hips")
				if kind == Animation.TYPE_SCALE_3D or (kind == Animation.TYPE_POSITION_3D and not is_hips):
					anim.remove_track(track)
			out.add_animation(clip, anim)
	_libraries["_borrowed"] = out
	return out


## The rules move regiments; a clip that also walks the hips forward would double the motion.
static func _keep_in_place(anim: Animation) -> void:
	for track in anim.get_track_count():
		if anim.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var path := String(anim.track_get_path(track))
		if not path.to_lower().contains("hips"):
			continue
		var first: Vector3 = anim.track_get_key_value(track, 0) if anim.track_get_key_count(track) > 0 else Vector3.ZERO
		for key in anim.track_get_key_count(track):
			var v: Vector3 = anim.track_get_key_value(track, key)
			anim.track_set_key_value(track, key, Vector3(first.x, v.y, first.z))


## Moves a figure's clip, and the hands that hold its musket, on by dt seconds.
static func step(soldier: Node3D, dt: float) -> void:
	if not soldier.has_meta("player"):
		return
	(soldier.get_meta("player") as AnimationPlayer).advance(dt)
	if soldier.has_meta("skeleton"):
		(soldier.get_meta("skeleton") as Skeleton3D).advance(dt)


## Hands a figure's animation back to the engine to run every frame (a man who has fallen out
## of his regiment has nobody stepping him).
static func free_run(soldier: Node3D) -> void:
	if not soldier.has_meta("player"):
		return
	(soldier.get_meta("player") as AnimationPlayer).callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	if soldier.has_meta("skeleton"):
		(soldier.get_meta("skeleton") as Skeleton3D).modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE


## Whether this figure has a clip of exactly that name (not a fallback).
static func has_clip(soldier: Node3D, clip: String) -> bool:
	if soldier == null or not soldier.has_meta("player"):
		return false
	return (soldier.get_meta("player") as AnimationPlayer).has_animation("a/" + clip)


static func play(soldier: Node3D, clip: String, restart: bool) -> void:
	if not soldier.has_meta("player"):
		return
	var player: AnimationPlayer = soldier.get_meta("player")
	var full := "a/" + clip
	if not player.has_animation(full):
		full = "a/" + String(FALLBACK.get(clip, "idle"))
		if not player.has_animation(full):
			return
	if restart:
		player.stop()
	var pace: float = float(SPEED.get(clip, 1.0)) * float(soldier.get_meta("pace", 1.0))
	player.play(full, 0.16, pace)


static var _pool: Dictionary = {}         # "card|team" -> Array of figures built ahead of time


## Loads a model and everything its figures need (mesh, textures, clips, the musket) now, so
## that nothing is read from storage in the middle of a battle.
static func preload_card(card_id: String, arm: String) -> void:
	for model_name: String in SOLDIER_MODELS.get(card_id, []):
		if _scene(model_name) != null:
			_library(model_name)
	if arm == "infantry":
		_scene("musket")
	if arm == "artillery":
		_scene("cannon")


## Builds one figure ahead of time and keeps it, outside the scene, until make_soldier() asks
## for it. Returns false once "want" are already waiting.
static func stock_soldier(card_id: String, arm: String, team: int, world: Node3D, want: int) -> bool:
	var key := "%s|%s|%d" % [card_id, arm, team]
	if not _pool.has(key):
		_pool[key] = []
	var waiting: Array = _pool[key]
	if waiting.size() >= want:
		return false
	waiting.append(_build_soldier(card_id, arm, team, world))
	return true


## Frees every figure built ahead of time (they are not in the scene, so nothing else will).
static func clear_stock() -> void:
	for key: String in _pool:
		for figure: Node3D in _pool[key]:
			if is_instance_valid(figure):
				figure.free()
	_pool.clear()


## One man (or one mounted man) for a card: one built ahead of time if there is one waiting,
## otherwise made on the spot.
static func make_soldier(card_id: String, arm: String, team: int, world: Node3D) -> Node3D:
	var waiting: Array = _pool.get("%s|%s|%d" % [card_id, arm, team], [])
	while not waiting.is_empty():
		var figure: Node3D = waiting.pop_back()
		if is_instance_valid(figure):
			return figure
	return _build_soldier(card_id, arm, team, world)


## The generated model if there is one, else a stand-in.
static func _build_soldier(card_id: String, arm: String, team: int, world: Node3D) -> Node3D:
	var names: Array = SOLDIER_MODELS.get(card_id, [])
	var height: float = HEIGHTS.get(card_id, HEIGHTS.get(arm, 0.98))
	var mounted := arm == "cavalry" or (arm == "command" and not card_id in FOOT_LEADERS)
	if not mounted and ON_FOOT_MODELS.has(card_id):
		names = ON_FOOT_MODELS[card_id]
		height = float(HEIGHTS["skirmishers"])
	if names.size() == 2:
		var model_name: String = names[team]
		var made := make(model_name, team)
		if made != null:
			fit_height(made, height)
			var rigged: bool = made.find_child("Skeleton3D", true, false) != null
			var lib := _library(model_name) if rigged else null
			if rigged and arm == "infantry":
				_attach_musket(made)
			if lib != null:
				var inner: Node3D = made.get_node("Model")
				var player: AnimationPlayer = inner.find_child("AnimationPlayer", true, false)
				if player == null:
					player = AnimationPlayer.new()
					inner.add_child(player)
				for existing: StringName in player.get_animation_library_list():
					if existing == &"a":
						player.remove_animation_library(existing)
				player.add_animation_library("a", lib)
				made.set_meta("player", player)
				# The regiment view steps the clip and the skeleton itself (see step()), so that in
				# a crowded battle each man can be animated every second or third frame.
				player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				var skeleton: Skeleton3D = made.find_child("Skeleton3D", true, false)
				if skeleton != null:
					skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
					made.set_meta("skeleton", skeleton)
				play(made, "idle_calm", false)
				player.seek(randf() * 1.5, true)
				made.set_meta("pace", randf_range(0.93, 1.07))    # so a rank is not a row of clones
				play(made, "idle_calm", false)
			elif mounted:
				_apply_gallop(made)
			if CARD_TINT.has(card_id):
				_tint(made, card_id)
			return made
	return _stand_in_soldier(card_id, arm, team, height)


static var _tinted: Dictionary = {}       # "card|material id" -> the tinted copy


## Washes a figure in its card's colour. Riders use the gallop shader's own tint; everything
## else gets tinted copies of its materials, shared between all figures of that card.
static func _tint(made: Node3D, card_id: String) -> void:
	var colour: Color = CARD_TINT[card_id]
	for mi: MeshInstance3D in made.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		if mi.material_override is ShaderMaterial:
			mi.set_instance_shader_parameter("tint", Vector3(colour.r, colour.g, colour.b))
			continue
		for surface in mi.mesh.get_surface_count():
			var base: Material = mi.get_surface_override_material(surface)
			if base == null:
				base = mi.mesh.surface_get_material(surface)
			if not (base is BaseMaterial3D):
				continue
			var key := "%s|%d" % [card_id, base.get_instance_id()]
			if not _tinted.has(key):
				var copy: BaseMaterial3D = base.duplicate()
				copy.albedo_color = Color(copy.albedo_color.r * colour.r, copy.albedo_color.g * colour.g, copy.albedo_color.b * colour.b)
				_tinted[key] = copy
			mi.set_surface_override_material(surface, _tinted[key])


## The gun a card's crew serves: the cannon model at that card's size and colour, or the
## primitive stand-in if there is no model.
static func make_gun(card_id: String, team: int, world: Node3D) -> Node3D:
	var spec: Array = GUNS.get(card_id, GUNS["field_gun"])
	var gun := make("cannon", team)
	if gun == null:
		return stand_in_cannon(world)
	fit_height(gun, float(spec[0]))
	gun.scale.z = float(spec[1])
	if CARD_TINT.has(card_id):
		_tint(gun, card_id)
	return gun


## Mounted figures are single unrigged models, so their legs are worked by a vertex shader:
## everything below the belly swings fore and aft, front and hind pairs out of step, while the
## body bobs and rocks. The regiment view sets "gallop" (0 standing, 1 at full stretch).
const GALLOP_SHADER := """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float y_min;
uniform float y_size;
uniform float z_mid;
uniform float x_half;
instance uniform vec3 tint = vec3(1.0);
instance uniform float gallop = 0.0;
instance uniform float phase = 0.0;
void vertex() {
	float h = (VERTEX.y - y_min) / y_size;
	float leg = (1.0 - smoothstep(0.1, 0.34, h)) * (1.0 - smoothstep(0.45, 0.8, abs(VERTEX.x) / x_half));
	float front = step(z_mid, VERTEX.z);
	float t = TIME * 13.0 + phase;
	float stride = t + front * 1.9 + sign(VERTEX.x) * 0.5;
	VERTEX.z += sin(stride) * leg * 0.15 * y_size * gallop;
	VERTEX.y += max(0.0, cos(stride)) * leg * 0.06 * y_size * gallop;
	float body = 1.0 - leg;
	VERTEX.y += (sin(t) * 0.5 + 0.5) * 0.04 * y_size * gallop * body;
	VERTEX.y += (VERTEX.z - z_mid) * sin(t + 0.9) * 0.07 * gallop * body;
}
void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint;
	ROUGHNESS = 0.85;
}
"""

static var _gallop_shader: Shader = null


static func _apply_gallop(made: Node3D) -> void:
	if _gallop_shader == null:
		_gallop_shader = Shader.new()
		_gallop_shader.code = GALLOP_SHADER
	var meshes: Array = []
	for mi: MeshInstance3D in made.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var base := mi.mesh.surface_get_material(0)
		if not (base is BaseMaterial3D) or (base as BaseMaterial3D).albedo_texture == null:
			continue
		var box := mi.mesh.get_aabb()
		var mat := ShaderMaterial.new()
		mat.shader = _gallop_shader
		mat.set_shader_parameter("albedo_tex", (base as BaseMaterial3D).albedo_texture)
		mat.set_shader_parameter("y_min", box.position.y)
		mat.set_shader_parameter("y_size", box.size.y)
		mat.set_shader_parameter("z_mid", box.get_center().z)
		mat.set_shader_parameter("x_half", box.size.x * 0.5)
		mi.material_override = mat
		mi.set_instance_shader_parameter("phase", randf() * TAU)
		mi.set_instance_shader_parameter("gallop", 0.0)
		meshes.append(mi)
	if not meshes.is_empty():
		made.set_meta("gallop", meshes)


## Gives a rigged character a musket and the modifier that makes him hold it (musket_drill.gd).
static func _attach_musket(made: Node3D) -> void:
	var skeleton: Skeleton3D = made.find_child("Skeleton3D", true, false)
	var musket := make("musket", 0)
	if skeleton == null or musket == null:
		return
	# Skeleton space to the model's own space (Y up, facing +Z); the rigs use centimetre bones
	# under a 0.01 armature.
	var to_model := Transform3D.IDENTITY
	var n: Node = skeleton
	var model_root: Node = made.get_node("Model")
	while n != null and n != model_root:
		if n is Node3D:
			to_model = (n as Node3D).transform * to_model
		n = n.get_parent()
	fit_footprint(musket, MusketDrill.LENGTH, 100000.0)     # the model lies along X, bayonet tip at -X
	var thickness := bounds(musket).size.y
	skeleton.add_child(musket)
	var drill := MusketDrill.new()
	skeleton.add_child(drill)
	if drill.setup(skeleton, to_model, musket, thickness):
		made.set_meta("drill", drill)
	else:
		drill.queue_free()
		musket.queue_free()


# ==========================================================================================
# Stand-in figures built from primitives
# ==========================================================================================

static func _mat(colour: Color, roughness: float = 0.7) -> StandardMaterial3D:
	var key := colour.to_html() + str(roughness)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		m.roughness = roughness
		_mats[key] = m
	return _mats[key]


static func _box(size: Vector3) -> Mesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _ball(radius: float) -> Mesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 12
	m.rings = 6
	return m


static func _tube(radius: float, height: float, top: float = -1.0) -> Mesh:
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = radius if top < 0.0 else top
	m.height = height
	m.radial_segments = 12
	m.rings = 1
	return m


static func _pill(radius: float, height: float) -> Mesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 12
	m.rings = 4
	return m


static func _at(pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot), pos)


## Merges parts ([mesh, transform, colour]) into one mesh with a surface per colour.
static func _merge(parts: Array) -> ArrayMesh:
	var by_colour := {}
	for part: Array in parts:
		var key: String = (part[2] as Color).to_html()
		if not by_colour.has(key):
			by_colour[key] = []
		by_colour[key].append(part)
	var out := ArrayMesh.new()
	for key: String in by_colour:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part: Array in by_colour[key]:
			st.append_from(part[0], 0, part[1])
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, _mat(Color(key)))
	return out


static func _man_parts(card_id: String, team: int, lift: float, mounted: bool) -> Array:
	var coat := BLUE if team == 0 else Color("b9b4a8")
	var trousers := Color("8fb4e8") if team == 0 else Color("8f95a0")
	var hat := Color("1b2f6b") if team == 0 else Color("a39680")
	if card_id == "skirmishers":
		coat = Color("1e3f8f") if team == 0 else Color("8c877a")
	elif card_id == "militia":
		coat = Color("6f9be0") if team == 0 else Color("d6cdb8")
	var parts: Array = []
	var y := lift
	if not mounted:
		parts.append([_box(Vector3(0.13, 0.24, 0.15)), _at(Vector3(-0.085, y + 0.12, 0)), trousers])
		parts.append([_box(Vector3(0.13, 0.24, 0.15)), _at(Vector3(0.085, y + 0.12, 0)), trousers])
		parts.append([_box(Vector3(0.15, 0.08, 0.2)), _at(Vector3(-0.085, y + 0.04, -0.02)), BLACK])
		parts.append([_box(Vector3(0.15, 0.08, 0.2)), _at(Vector3(0.085, y + 0.04, -0.02)), BLACK])
		y += 0.2
	parts.append([_pill(0.19, 0.46), _at(Vector3(0, y + 0.24, 0)), coat])
	if card_id != "militia":
		parts.append([_box(Vector3(0.07, 0.42, 0.34)), _at(Vector3(0, y + 0.25, 0), Vector3(0, 0, 0.7)), WHITE if team == 0 else CRIMSON])
	else:
		parts.append([_box(Vector3(0.4, 0.06, 0.36)), _at(Vector3(0, y + 0.2, 0)), WOOD if team == 0 else CRIMSON])
	if team == 1:
		parts.append([_tube(0.2, 0.07), _at(Vector3(0, y + 0.13, 0)), CRIMSON])          # sash
	parts.append([_ball(0.11), _at(Vector3(-0.25, y + 0.2, -0.06)), SKIN])               # big hands
	parts.append([_ball(0.11), _at(Vector3(0.25, y + 0.2, -0.06)), SKIN])
	parts.append([_ball(0.18), _at(Vector3(0, y + 0.58, 0)), SKIN])
	parts.append([_ball(0.055), _at(Vector3(0, y + 0.56, -0.17)), SKIN.darkened(0.08)])  # nose
	parts.append([_box(Vector3(0.2, 0.05, 0.05)), _at(Vector3(0, y + 0.5, -0.16)), Color("5a3a1e")])   # moustache
	if card_id == "militia":
		parts.append([_tube(0.3, 0.03), _at(Vector3(0, y + 0.72, 0)), Color("e3c66a")])
		parts.append([_tube(0.15, 0.12, 0.13), _at(Vector3(0, y + 0.78, 0)), Color("e3c66a")])
	elif team == 0:
		parts.append([_tube(0.17, 0.13, 0.15), _at(Vector3(0, y + 0.76, 0.01)), hat])     # kepi
		parts.append([_box(Vector3(0.24, 0.025, 0.14)), _at(Vector3(0, y + 0.71, -0.17)), BLACK])
	else:
		parts.append([_tube(0.31, 0.03), _at(Vector3(0, y + 0.72, 0)), hat])              # slouch hat
		parts.append([_tube(0.16, 0.13, 0.14), _at(Vector3(0, y + 0.79, 0)), hat])
		parts.append([_tube(0.165, 0.04), _at(Vector3(0, y + 0.75, 0)), CRIMSON])
	if mounted:
		parts.append([_box(Vector3(0.05, 0.6, 0.07)), _at(Vector3(0.27, y + 0.55, -0.12), Vector3(-0.5, 0, 0)), STEEL])   # sabre
	else:
		parts.append([_box(Vector3(0.06, 0.07, 0.8)), _at(Vector3(0.25, y + 0.28, -0.3)), WOOD])                        # musket
		parts.append([_box(Vector3(0.03, 0.03, 0.26)), _at(Vector3(0.25, y + 0.3, -0.8)), STEEL])
	return parts


static func _stand_in_soldier(card_id: String, arm: String, team: int, height: float) -> Node3D:
	var mounted := arm == "cavalry" or (arm == "command" and not card_id in FOOT_LEADERS)
	var key := "%s|%s|%d" % [card_id, "m" if mounted else "f", team]
	if not _meshes.has(key):
		var parts: Array = []
		if mounted:
			var hide := (Color("7a4a26") if team == 0 else Color("2a2622"))
			if card_id == "heavy_cavalry":
				hide = Color("e8e2d6") if team == 0 else Color("6a6a70")
			parts.append([_pill(0.23, 0.95), _at(Vector3(0, 0.62, 0), Vector3(PI * 0.5, 0, 0)), hide])
			for leg: Array in [[-0.14, -0.3], [0.14, -0.3], [-0.14, 0.3], [0.14, 0.3]]:
				parts.append([_box(Vector3(0.1, 0.44, 0.1)), _at(Vector3(leg[0], 0.22, leg[1])), hide.darkened(0.15)])
			parts.append([_box(Vector3(0.17, 0.36, 0.2)), _at(Vector3(0, 0.93, -0.45), Vector3(0.5, 0, 0)), hide])
			parts.append([_box(Vector3(0.19, 0.2, 0.34)), _at(Vector3(0, 1.1, -0.62), Vector3(0.25, 0, 0)), hide])
			parts.append([_ball(0.045), _at(Vector3(-0.1, 1.15, -0.62)), WHITE])        # big goofy eyes
			parts.append([_ball(0.045), _at(Vector3(0.1, 1.15, -0.62)), WHITE])
			parts.append([_ball(0.02), _at(Vector3(-0.12, 1.15, -0.65)), BLACK])
			parts.append([_ball(0.02), _at(Vector3(0.12, 1.15, -0.65)), BLACK])
			parts.append([_box(Vector3(0.06, 0.3, 0.06)), _at(Vector3(0, 0.6, 0.52), Vector3(-0.6, 0, 0)), BLACK])
			parts.append([_box(Vector3(0.5, 0.05, 0.4)), _at(Vector3(0, 0.86, 0.02)), BLUE if team == 0 else CRIMSON])
			parts.append_array(_man_parts(card_id, team, 0.86, true))
		else:
			parts.append_array(_man_parts(card_id, team, 0.0, false))
		_meshes[key] = _merge(parts)
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	var natural := 1.72 if mounted else 0.98     # the stand-in's own height before scaling
	mi.scale = Vector3.ONE * (height / natural)
	holder.add_child(mi)
	return holder


static func stand_in_cannon(_world: Node3D) -> Node3D:
	if not _meshes.has("cannon"):
		var parts: Array = []
		parts.append([_tube(0.15, 1.05, 0.11), _at(Vector3(0, 0.5, -0.25), Vector3(-PI * 0.5 + 0.08, 0, 0)), BRASS])
		parts.append([_tube(0.17, 0.12), _at(Vector3(0, 0.46, 0.26), Vector3(-PI * 0.5, 0, 0)), BRASS])
		for sx: float in [-1.0, 1.0]:
			parts.append([_tube(0.38, 0.09), _at(Vector3(sx * 0.33, 0.38, 0.05), Vector3(0, 0, PI * 0.5)), WOOD.darkened(0.25)])
			parts.append([_tube(0.09, 0.11), _at(Vector3(sx * 0.33, 0.38, 0.05), Vector3(0, 0, PI * 0.5)), BRASS])
		parts.append([_box(Vector3(0.22, 0.12, 0.95)), _at(Vector3(0, 0.26, 0.4), Vector3(-0.28, 0, 0)), WOOD])
		_meshes["cannon"] = _merge(parts)
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes["cannon"]
	mi.scale = Vector3.ONE * 1.4
	holder.add_child(mi)
	return holder
