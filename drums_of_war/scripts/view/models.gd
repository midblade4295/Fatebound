extends RefCounted
## Supplies the 3D figures and props. A generated model in assets/models/<name>/<name>.glb is
## used when it exists; otherwise a chunky stand-in is built from primitive shapes, so the game
## always runs and any card can be played before its model is made.
##
## team 0 is the local player's army (Union blue); team 1 is the enemy (Confederate crimson).

const DIR := "res://assets/models/"

# card id -> [team 0 model, team 1 model]
const SOLDIER_MODELS := {
	"line_infantry": ["u_line", "c_line"],
	"skirmishers": ["u_skirm", "c_skirm"],
	"militia": ["u_militia", "c_militia"],
	"scouts": ["u_cav", "c_cav"],
	"heavy_cavalry": ["u_cav", "c_cav"],
	"field_gun": ["u_line", "c_line"],
}
const HEIGHTS := {"infantry": 2.1, "artillery": 2.1, "scouts": 2.8, "heavy_cavalry": 3.2}
const SHARED_CLIPS := "u_line"     # rigged characters without clips of their own borrow this one's
# Degrees to turn each generated model about the vertical so that it faces "forward" (-Z):
# characters and riders come facing +Z, gun muzzles along -X, bridge and fence run along X.
const YAW := {"u_line": 180.0, "c_line": 180.0, "u_skirm": 180.0, "c_skirm": 180.0, "u_militia": 180.0,
		"c_militia": 180.0, "u_cav": 180.0, "c_cav": 180.0, "cannon": -90.0, "battery": -90.0,
		"bridge": 90.0, "fence": 90.0}
const CLIPS := ["idle", "walk", "run", "fire", "death"]
const LOOPING := ["idle", "walk", "run"]

const SKIN := Color("f2c49b")
const BLACK := Color("1c1c22")
const WOOD := Color("8a5a2e")
const STEEL := Color("c8ccd4")
const BRASS := Color("f2b632")
const WHITE := Color("f4f1e8")
const CRIMSON := Color("c81e3a")
const BLUE := Color("2456c9")

static var _scenes: Dictionary = {}       # name -> PackedScene or null
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
static func make(name: String, team: int) -> Node3D:
	var scene := _scene(name)
	if scene == null:
		return null
	var holder := Node3D.new()
	var inner: Node3D = scene.instantiate()
	inner.name = "Model"
	inner.rotation.y = deg_to_rad(float(YAW.get(name, 0.0)))
	holder.add_child(inner)
	if team == 1:
		var red := _red_texture(name)
		if red != null:
			for mi: MeshInstance3D in inner.find_children("*", "MeshInstance3D", true, false):
				for surface in mi.mesh.get_surface_count():
					var base := mi.mesh.surface_get_material(surface)
					if base is BaseMaterial3D:
						var copy: BaseMaterial3D = base.duplicate()
						copy.albedo_texture = red
						mi.set_surface_override_material(surface, copy)
	return holder


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
				copy.loop_mode = Animation.LOOP_LINEAR if clip in LOOPING else Animation.LOOP_NONE
				_keep_in_place(copy)
				lib.add_animation(clip, copy)
				found += 1
		temp.free()
	if found == 0 and name != SHARED_CLIPS:
		# Every generated rig has the same bones, so one character's clips drive them all.
		_libraries[name] = _library(SHARED_CLIPS)
	else:
		_libraries[name] = lib if found > 0 else null
	return _libraries[name]


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


static func play(soldier: Node3D, clip: String, restart: bool) -> void:
	if not soldier.has_meta("player"):
		return
	var player: AnimationPlayer = soldier.get_meta("player")
	var full := "a/" + clip
	if not player.has_animation(full):
		full = "a/idle"
		if not player.has_animation(full):
			return
	if restart:
		player.stop()
	player.play(full, 0.12)
	if clip == "fire" and player.has_animation("a/idle"):
		player.queue("a/idle")


## One man (or one mounted man) for a card: the generated model if there is one, else a stand-in.
static func make_soldier(card_id: String, arm: String, team: int, world: Node3D) -> Node3D:
	var names: Array = SOLDIER_MODELS.get(card_id, [])
	var height: float = HEIGHTS.get(card_id, HEIGHTS.get(arm, 0.98))
	if names.size() == 2:
		var model_name: String = names[team]
		var made := make(model_name, team)
		if made != null:
			fit_height(made, height)
			var rigged: bool = made.find_child("Skeleton3D", true, false) != null
			var lib := _library(model_name) if rigged else null
			if rigged and arm == "infantry":
				_attach_musket(made, model_name)
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
				play(made, "idle", false)
				player.seek(randf() * 1.5, true)
			return made
	return _stand_in_soldier(card_id, arm, team, height)


## Where a bone sits in skeleton space at a moment of a clip, worked out from the clip's tracks
## (bones the clip does not move keep their rest pose).
static func _clip_pose(skeleton: Skeleton3D, anim: Animation, bone: int, time: float) -> Transform3D:
	var chain: Array = []
	var b := bone
	while b >= 0:
		chain.push_front(b)
		b = skeleton.get_bone_parent(b)
	var out := Transform3D.IDENTITY
	for index: int in chain:
		var rest := skeleton.get_bone_rest(index)
		var pos := rest.origin
		var rot := rest.basis.get_rotation_quaternion()
		var bone_name := skeleton.get_bone_name(index)
		for track in anim.get_track_count():
			var path := anim.track_get_path(track)
			if path.get_subname_count() == 0 or String(path.get_subname(0)) != bone_name:
				continue
			if anim.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				rot = anim.rotation_track_interpolate(track, time)
			elif anim.track_get_type(track) == Animation.TYPE_POSITION_3D:
				pos = anim.position_track_interpolate(track, time)
		out = out * Transform3D(Basis(rot), pos)
	return out


## Puts the musket in a rigged character's hands. It is fixed to the rear hand so that, at the
## start of the firing clip, it lies level through both hands and points the way he faces.
static func _attach_musket(made: Node3D, model_name: String = SHARED_CLIPS) -> void:
	var skeleton: Skeleton3D = made.find_child("Skeleton3D", true, false)
	var lib := _library(model_name)
	var musket := make("musket", 0)
	if skeleton == null or musket == null or lib == null or not lib.has_animation("fire"):
		return
	var left := skeleton.find_bone("LeftHand")
	var right := skeleton.find_bone("RightHand")
	var fore := skeleton.find_bone("RightForeArm")
	if left < 0 or right < 0 or fore < 0:
		return
	# Work in the model's own space (Y up, facing +Z), not the skeleton's, whose axes and
	# units depend on how the rig was exported.
	var to_model := Transform3D.IDENTITY
	var n: Node = skeleton
	var model_root: Node = made.get_node("Model")
	while n != null and n != model_root:
		if n is Node3D:
			to_model = (n as Node3D).transform * to_model
		n = n.get_parent()
	var fire := lib.get_animation("fire")
	var rear_bone := left
	var g_rear := to_model * _clip_pose(skeleton, fire, left, 0.15)
	var g_front := to_model * _clip_pose(skeleton, fire, right, 0.15)
	if g_front.origin.z < g_rear.origin.z:
		var swap := g_rear
		g_rear = g_front
		g_front = swap
		rear_bone = right
	var forearm := (to_model * skeleton.get_bone_global_rest(right).origin).distance_to(to_model * skeleton.get_bone_global_rest(fore).origin)
	if forearm < 0.0001:
		return
	var length := forearm * 5.2
	fit_footprint(musket, length, 100000.0)          # the model lies along X, bayonet tip at -X
	var through := g_front.origin - g_rear.origin
	var dir := Vector3(through.x * 0.15, through.y * 0.3, maxf(through.z, forearm)).normalized()
	var x_axis := -dir
	var up := (Vector3.UP - dir * dir.y).normalized()
	var basis := Basis(x_axis, up, x_axis.cross(up))
	var thickness := bounds(musket).size.y
	# The rear hand holds the musket about a quarter of the way along from the butt.
	var wanted := Transform3D(basis, g_rear.origin + dir * (length * 0.25) - up * (thickness * 0.5))
	var attach := BoneAttachment3D.new()
	attach.bone_name = skeleton.get_bone_name(rear_bone)
	skeleton.add_child(attach)
	attach.add_child(musket)
	musket.transform = g_rear.affine_inverse() * wanted

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
	var mounted := arm == "cavalry"
	var key := "%s|%d" % [card_id, team]
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
