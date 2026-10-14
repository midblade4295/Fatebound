extends Node3D
# 0.31.138: the war map's land as one piece (until now built inside war_table.gd), so that Home's war table
# (war_room.gd) stands the same live map on its table: the land (tools/war_land.py), the sea round it, the forests'
# trees, each place's Meshy miniature (0.31.136) and the crossed swords over a battle. `paint` shows the war on it (who
# holds each place, the battles, the place picked); `step` moves it (the miniature picked lifts, swords bob).
# Map space is this node's own: x right, z toward the viewer, 1 = one map unit (the land is 12 x 18). Moved or scaled
# (Home's table), the shaders follow through `to_map` -- call `placed()` once it is where it stays.
const SocialUI = preload("res://scripts/app/social_ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const Map = preload("res://scripts/meta/war_map.gd")
const Stage = preload("res://scripts/siege/asset_cache.gd")
const LandData = preload("res://scripts/app/war_land_data.gd")   # (tools/war_land.py: the grid, each place's spot)
const LandShader = preload("res://scripts/app/war_land.gdshader")
const SeaShader = preload("res://scripts/app/war_sea.gdshader")
const LAND := "res://assets/war_land/"
const PIECES := "res://assets/meshy/war/"   # each place's Meshy miniature (0.31.136, tools/meshy_war_piece.py)
const TREE_TINT := Color(0.62, 0.8, 0.5)
const RAISE := 0.14                          # the place picked lifts its miniature a little
const SWORDS_UP := 1.35                      # the crossed swords float this high over a battle's place

var land_mat: ShaderMaterial
var sea_mat: ShaderMaterial
var region_img: Image                        # (picking: which place's land a tap is on)
var tiles := {}                              # id -> {"pos": Vector3 (its ground), "node": Node3D or null, "swords": Sprite3D}
var disc := Vector2.ZERO                     # not zero: cut to this oval, its x and z radii (Home's table)
var sea_size := 80.0
var _clock := 0.0

static func tile_pos(id: String) -> Vector3:
	# a place's spot on the land (x right, z toward you; the Lions near, the Stags far, the Ravens east)
	var e: Dictionary = LandData.PLACES.get(id, {})
	return Vector3(float(e.get("x", 0.0)), float(e.get("y", 0.0)), float(e.get("z", 0.0)))

static func noise_tex(freq: float, seed: int, size := 256) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	return t

func build(swords_px := 0.0045, glow := 0.0) -> void:
	var regions: Texture2D = Stage.texture(LAND + "land_regions.png")
	var clouds := noise_tex(0.006, 7)
	# the land
	var land_scene: PackedScene = Stage.scene(LAND + "land.glb")
	if land_scene != null:
		var land := land_scene.instantiate() as Node3D
		add_child(land)
		land_mat = ShaderMaterial.new()
		land_mat.shader = LandShader
		land_mat.set_shader_parameter("color_tex", Stage.texture(LAND + "land_color.jpg"))
		land_mat.set_shader_parameter("region_id", regions)
		land_mat.set_shader_parameter("region_lin", regions)
		land_mat.set_shader_parameter("cloud_tex", clouds)
		land_mat.set_shader_parameter("disc", disc)
		land_mat.set_shader_parameter("glow", glow)
		for mi in land.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = land_mat
	if regions != null:
		region_img = regions.get_image()
		if region_img != null and region_img.is_compressed():
			region_img.decompress()
	# the sea (and the lake, the river, the pools): one sheet at sea level
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(sea_size, sea_size)
	sea.mesh = pm
	sea_mat = ShaderMaterial.new()
	sea_mat.shader = SeaShader
	sea_mat.set_shader_parameter("region_lin", regions)
	sea_mat.set_shader_parameter("wave_tex", noise_tex(0.02, 3))
	sea_mat.set_shader_parameter("cloud_tex", clouds)
	sea_mat.set_shader_parameter("map_rect", Vector4(LandData.X0, LandData.Z0, LandData.X1 - LandData.X0, LandData.Z1 - LandData.Z0))
	sea_mat.set_shader_parameter("h_min", LandData.H_MIN)
	sea_mat.set_shader_parameter("h_max", LandData.H_MAX)
	sea_mat.set_shader_parameter("disc", disc)
	sea_mat.set_shader_parameter("glow", glow)
	sea.material_override = sea_mat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	# the forests' trees (KayKit's, many at once)
	_plant_trees()
	# the places: each miniature standing in its land (sunk so its base hides under the ground), crossed swords
	# over a battle
	var swords_tex: Texture2D = Stage.texture(UI2.icon_path("swords"))
	for id in Map.T:
		var pos := tile_pos(id)
		var e2: Dictionary = LandData.PLACES.get(id, {})
		var node: Node3D = null
		var piece: String = PIECES + str(e2.get("piece", "")) + ".glb"
		if str(e2.get("piece", "")) != "" and ResourceLoader.exists(piece):
			node = Node3D.new()
			node.position = pos
			add_child(node)
			var m := (Stage.scene(piece) as PackedScene).instantiate() as Node3D
			m.scale = Vector3.ONE * float(e2.get("scale", 0.5))
			m.position.y = float(e2.get("sink", 0.0))
			m.rotation.y = deg_to_rad(float(e2.get("yaw", 0.0)))
			node.add_child(m)
		var sw := Sprite3D.new()
		sw.texture = swords_tex
		sw.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sw.pixel_size = swords_px
		sw.no_depth_test = true
		sw.position = pos + Vector3(0.0, SWORDS_UP, 0.0)
		sw.visible = false
		add_child(sw)
		tiles[id] = {"pos":pos, "node":node, "swords":sw}
	placed()

func placed() -> void:
	# the shaders' map space: this node's own, wherever it stands
	var inv := global_transform.affine_inverse() if is_inside_tree() else transform.affine_inverse()
	var m := Projection(inv)
	if land_mat != null:
		land_mat.set_shader_parameter("to_map", m)
	if sea_mat != null:
		sea_mat.set_shader_parameter("to_map", m)

func _plant_trees() -> void:
	var kinds := ["tree_single_A", "tree_single_B"]
	for k in kinds.size():
		var ps: PackedScene = Stage.scene("res://assets/kaykit/hex/%s.gltf" % kinds[k])
		if ps == null:
			continue
		var inst := ps.instantiate()
		var mis := inst.find_children("*", "MeshInstance3D", true, false)
		if mis.is_empty():
			inst.free()
			continue
		var mi := mis[0] as MeshInstance3D
		var mesh: Mesh = mi.mesh
		var base := mi.transform
		inst.free()
		var list := []
		for t in LandData.TREES:
			if int(t[4]) == k:
				list.append(t)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			var t: Array = list[i]
			var sc := float(t[3])
			var b := Basis(Vector3.UP, fmod(float(t[0]) * 12.7 + float(t[2]) * 7.3, TAU)).scaled(Vector3.ONE * sc)
			mm.set_instance_transform(i, Transform3D(b, Vector3(float(t[0]), float(t[1]) - 0.02, float(t[2]))) * base)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var src := mesh.surface_get_material(0) as StandardMaterial3D
		if src != null:
			var tm := src.duplicate() as StandardMaterial3D
			tm.albedo_color = src.albedo_color * TREE_TINT                # (KayKit's teal leaves: a deeper green)
			mmi.material_override = tm
		add_child(mmi)

func region_of(map_pt: Vector3) -> String:
	# which place's land is at a point of map space ("" for the sea)
	if region_img == null:
		return ""
	var u := (map_pt.x - LandData.X0) / (LandData.X1 - LandData.X0)
	var v := (map_pt.z - LandData.Z0) / (LandData.Z1 - LandData.Z0)
	if u < 0.0 or v < 0.0 or u >= 1.0 or v >= 1.0:
		return ""
	var px := region_img.get_pixel(int(u * region_img.get_width()), int(v * region_img.get_height()))
	var idx := int(round(px.r * 255.0))
	return str(LandData.IDS[idx]) if idx < LandData.IDS.size() else ""

func paint(war: Dictionary, sel := "") -> void:
	# the war on the land: each place tinted with its holder's colour, battles pulsing (and their swords), the place picked
	var terr: Dictionary = war.get("terr", {})
	var holders := PackedColorArray()
	var battles := PackedFloat32Array()
	holders.resize(LandData.IDS.size())
	battles.resize(LandData.IDS.size())
	for id in tiles:
		var t: Dictionary = terr.get(id, {})
		var h := str(t.get("h", ""))
		var col: Color = SocialUI.house_color(h) if h != "" else Color(0.85, 0.85, 0.8)
		var k := LandData.IDS.find(id)
		if k >= 0:
			holders[k] = Color(col.r, col.g, col.b, 1.0 if h != "" else 0.0)
			battles[k] = 1.0 if t.has("b") else 0.0
		(tiles[id].swords as Sprite3D).visible = t.has("b")
	if land_mat != null:
		land_mat.set_shader_parameter("holder", holders)
		land_mat.set_shader_parameter("battle", battles)
		land_mat.set_shader_parameter("picked", LandData.IDS.find(sel))

func step(delta: float, sel := "") -> void:
	# the place picked lifts its miniature; crossed swords bob over a battle
	_clock += delta
	for id in tiles:
		var t: Dictionary = tiles[id]
		if t.node != null:
			var n: Node3D = t.node
			var want: float = (t.pos as Vector3).y + (RAISE if id == sel else 0.0)
			n.position.y = lerpf(n.position.y, want, minf(1.0, delta * 10.0))
		var sw: Sprite3D = t.swords
		if sw.visible:
			sw.position.y = (t.pos as Vector3).y + SWORDS_UP + 0.08 * sin(_clock * 3.0)
