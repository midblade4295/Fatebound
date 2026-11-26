extends Node3D
## Development tool: loads a model, prints its node tree / surfaces / bounds,
## checks it faces Godot's forward (-Z) and saves beauty shots from a few angles.
##
##   godot --path . res://tools/ModelPreview.tscn -- model=res://assets/models/spitfire_stylized.glb out=/tmp/model
##
## Rendering needs a real display driver (see tools/shot_capture.gd); with
## --headless it still prints the report and then quits without images.

const VIEWS: Array[Vector3] = [Vector3(7.5, 3.6, -9.0), Vector3(-9.5, 2.2, 6.5), Vector3(0.01, 15.0, 0.5), Vector3(11.0, 0.6, 0.0)]

var _model: Node3D
var _propeller: Node3D
var _out: String = ""
var _frame: int = 0
var _view: int = 0

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	var model_path: String = "res://assets/models/spitfire_stylized.glb"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("model="):
			model_path = argument.trim_prefix("model=")
		elif argument.begins_with("out="):
			_out = argument.trim_prefix("out=")
	_model = (load(model_path) as PackedScene).instantiate() as Node3D
	add_child(_model)
	_propeller = _model.find_child("PropellerMesh", true, false) as Node3D
	_report(_model, 0)
	if _propeller != null:
		var nose: Vector3 = _propeller.global_position
		print("PropellerMesh pivot at ", nose, "  -> faces -Z: ", nose.z < -0.5 and absf(nose.x) < 0.01)
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		get_tree().quit()
		return
	_aim(VIEWS[0])


func _process(delta: float) -> void:
	if _propeller != null:
		_propeller.rotate_z(delta * 3.0)
	_frame += 1
	if _frame % 12 != 0:
		return
	await RenderingServer.frame_post_draw
	var path: String = "%s_%d.png" % [_out, _view]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	_view += 1
	if _view >= VIEWS.size():
		get_tree().quit()
		return
	_aim(VIEWS[_view])


func _aim(eye: Vector3) -> void:
	_camera.look_at_from_position(eye, Vector3(0.0, 0.3, 0.2), Vector3.UP)


func _report(node: Node, depth: int) -> void:
	var line: String = "%s%s (%s)" % ["  ".repeat(depth), node.name, node.get_class()]
	var mesh_instance: MeshInstance3D = node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		var bounds: AABB = mesh_instance.mesh.get_aabb()
		var surfaces: PackedStringArray = PackedStringArray()
		for surface: int in range(mesh_instance.mesh.get_surface_count()):
			var material: Material = mesh_instance.mesh.surface_get_material(surface)
			var standard: BaseMaterial3D = material as BaseMaterial3D
			if standard != null:
				surfaces.append("%s #%s metal %.2f rough %.2f" % [standard.resource_name, standard.albedo_color.to_html(), standard.metallic, standard.roughness])
			else:
				surfaces.append(material.resource_name if material != null else "<none>")
		line += "  pos %s  aabb %s .. %s  surfaces [%s]" % [mesh_instance.position, bounds.position, bounds.end, ", ".join(surfaces)]
	print(line)
	for child: Node in node.get_children():
		_report(child, depth + 1)
