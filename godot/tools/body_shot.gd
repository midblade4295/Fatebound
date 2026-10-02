extends SceneTree
# A class model with its weapons, posed in its idle: BODY env picks the look (default necromancer).
const View = preload("res://scripts/siege/siege_view.gd")
var frames := 0
func _init() -> void:
	var v = View.new()
	root.add_child(v)
	v._build_lighting()
	var look := OS.get_environment("BODY") if OS.has_environment("BODY") else "necromancer"
	var made: Dictionary = View.make_body(look)
	var body: Node3D = made.body
	v.add_child(body)
	body.rotation.y = PI * 0.85
	var pl: AnimationPlayer = made.player
	if pl != null:
		pl.play(str(View.LOOKS[look].idle))
	var cam := Camera3D.new()
	cam.fov = 35.0
	v.add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(0.0, 1.4, 4.2), Vector3(0.0, 0.95, 0.0), Vector3.UP)
	RenderingServer.frame_post_draw.connect(func():
		if frames == 8:
			root.get_texture().get_image().save_png("/tmp/body_%s.png" % look)
			print("SHOT ", look))
func _process(_d: float) -> bool:
	frames += 1
	return frames > 10
