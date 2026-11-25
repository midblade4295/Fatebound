extends SceneTree
## Renders every generated model in a row, fitted the way the game fits them, and prints what
## each one contains. For checking scale, facing and textures after a model is added.
## Needs a display:
##   xvfb-run -a $GODOT --rendering-method mobile --resolution 1280x720 --path drums_of_war -s tools/model_sheet.gd
## Environment: SHEET_OUT (default res://captures/model_sheet.png), SHEET_NAMES (comma list),
## SHEET_CLIP (animation clip to pose rigged characters in), SHEET_TIME (seconds into the clip),
## SHEET_FRONT (set to view the models from the front), SHEET_MUSKET (set to put muskets in hands).

const Models = preload("res://scripts/view/models.gd")

const DEFAULT := ["u_line", "c_line", "u_skirm", "c_skirm", "u_militia", "c_militia", "u_cav", "c_cav", "cannon", "musket", "farmhouse", "battery", "bridge", "tree", "fence"]
const SIZES := {"farmhouse": 4.4, "battery": 3.3, "bridge": 3.0, "tree": 2.6, "fence": 3.4, "cannon": 1.25, "musket": 0.4,
		"u_cav": 2.0, "c_cav": 2.0}

var frame := 0
var out_path := "res://captures/model_sheet.png"


func _initialize() -> void:
	if OS.has_environment("SHEET_OUT"):
		out_path = OS.get_environment("SHEET_OUT")
	var names: Array = DEFAULT
	if OS.has_environment("SHEET_NAMES"):
		names = Array(OS.get_environment("SHEET_NAMES").split(","))
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8ecbff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a9d3ff")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffdca6")
	sun.light_energy = 0.95
	sun.rotation_degrees = Vector3(-42.0, 128.0, 0.0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("74cc4e")
	ground.material_override = gm
	world.add_child(ground)
	var x := 0.0
	var placed := 0
	for name: String in names:
		for team in 2:
			if team == 1 and not ResourceLoader.exists(Models.DIR + name + "/" + name + "_red.png"):
				continue
			var node := Models.make(name, team)
			if node == null:
				continue
			if OS.has_environment("SHEET_MUSKET"):
				Models._attach_musket(node, name)
			if name in ["farmhouse", "battery", "bridge", "fence"]:
				Models.fit_footprint(node, float(SIZES[name]), float(SIZES[name]))
			else:
				Models.fit_height(node, float(SIZES.get(name, 1.4)))
			var box := Models.bounds(node)
			var lib: AnimationLibrary = Models._library(name)
			print("%-10s team %d  size %.2f x %.2f x %.2f  min y %.2f  clips %s" % [name, team, box.size.x, box.size.y, box.size.z,
					box.position.y, (lib.get_animation_list() if lib != null else [])])
			x += box.size.x * 0.5 + 0.5
			node.position = Vector3(x, 0, 0)
			x += box.size.x * 0.5 + 0.5
			world.add_child(node)
			placed += 1
			if lib != null and OS.has_environment("SHEET_CLIP"):
				var inner: Node3D = node.get_node("Model")
				var player := AnimationPlayer.new()
				inner.add_child(player)
				player.add_animation_library("a", lib)
				player.play("a/" + OS.get_environment("SHEET_CLIP"))
				player.seek(float(OS.get_environment("SHEET_TIME")) if OS.has_environment("SHEET_TIME") else 0.3, true)
				player.speed_scale = 0.0
			# A marker on the "forward" side (-Z), so facing can be checked in the picture.
			var arrow := MeshInstance3D.new()
			var am := BoxMesh.new()
			am.size = Vector3(0.12, 0.04, 0.5)
			arrow.mesh = am
			var red := StandardMaterial3D.new()
			red.albedo_color = Color("ff3030")
			arrow.material_override = red
			arrow.position = node.position + Vector3(0, 0.03, -box.size.z * 0.5 - 0.45)
			world.add_child(arrow)
	var cam := Camera3D.new()
	cam.fov = 30.0
	world.add_child(cam)
	var mid := x * 0.5
	var dist := maxf(4.5, x * 1.05)
	# Looking from the front-left: "forward" (-Z) is toward the top of the picture.
	if OS.has_environment("SHEET_FRONT"):
		# From in front of the models (they face -Z), for checking faces and poses.
		cam.look_at_from_position(Vector3(mid + dist * 0.2, dist * 0.3, -dist * 0.75), Vector3(mid, 0.8, 0), Vector3.UP)
	else:
		cam.look_at_from_position(Vector3(mid - dist * 0.25, dist * 0.42, dist * 0.8), Vector3(mid, 0.8, 0), Vector3.UP)
	cam.make_current()
	print("placed ", placed)


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 6:
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
	root.get_texture().get_image().save_png(out_path)
	print("saved ", out_path)
	quit(0)
	return true
