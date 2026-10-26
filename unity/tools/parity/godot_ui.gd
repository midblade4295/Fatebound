extends SceneTree
# Builds a UI from a JSON spec (tools/parity/ui/*.json) with Godot's own nodes, lets it settle, and prints every
# control's global rect -- tools/guitest builds the same spec with the C# framework and compares (guitest uiparity).
#   godot --headless --path godot -s <abs>/godot_ui.gd -- <spec.json> [shot.png]   (a shot needs a display: Xvfb)
var spec: Dictionary
var frames := 0
var shot := ""
var frame: Control

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	spec = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	if a.size() > 1:
		shot = a[1]
	var w: int = int(spec.get("size", [760, 420])[0])
	var h: int = int(spec.get("size", [760, 420])[1])
	frame = Control.new()
	frame.name = "frame"
	root.add_child(frame)
	frame.size = Vector2(w, h)
	frame.add_child(build(spec.root))

func val(v: Variant) -> Variant:
	if v is String and (v as String).begins_with("#"):
		return Color(v)
	if v is String and (v as String).begins_with("res://"):
		return load(v)
	if v is Array and v.size() == 2 and (v[0] is float or v[0] is int):
		return Vector2(v[0], v[1])
	if v is Array and v.size() == 4 and (v[0] is float or v[0] is int):
		return Color(v[0], v[1], v[2], v[3])
	if v is Dictionary and v.has("type"):
		return build_res(v)
	return v

func build_res(d: Dictionary) -> Variant:
	var r: Variant = ClassDB.instantiate(d.type)
	for k in d:
		if k == "type":
			continue
		if k == "call":
			for c in d.call:
				r.callv(c[0], (c.slice(1) as Array).map(val))
			continue
		r.set(k, val(d[k]))
	return r

func build(d: Dictionary) -> Node:
	var n: Node = ClassDB.instantiate(d.type)
	if d.has("name"):
		n.name = d.name
	for k in d.get("props", {}):
		n.set(k, val(d.props[k]))
	for kind in d.get("theme", {}):
		for item in d.theme[kind]:
			var v: Variant = val(d.theme[kind][item])
			match kind:
				"constant": n.add_theme_constant_override(item, int(v))
				"color": n.add_theme_color_override(item, v)
				"font": n.add_theme_font_override(item, v)
				"font_size": n.add_theme_font_size_override(item, int(v))
				"stylebox": n.add_theme_stylebox_override(item, v)
				"icon": n.add_theme_icon_override(item, v)
	for c in d.get("children", []):
		n.add_child(build(c))
	for c in d.get("call", []):
		n.callv(c[0], (c.slice(1) as Array).map(val))
	return n

func dump(n: Node, path: String) -> void:
	if n is Control:
		var c := n as Control
		var r := c.get_global_rect()
		print("R %s %.2f %.2f %.2f %.2f min=%.2f,%.2f" % [path, r.position.x, r.position.y, r.size.x, r.size.y, c.get_combined_minimum_size().x, c.get_combined_minimum_size().y])
	var i := 0
	for ch in n.get_children():
		dump(ch, path + "/" + (ch.name if not String(ch.name).begins_with("@") else str(i)))
		i += 1

func _process(_d: float) -> bool:
	frames += 1
	if frames == int(spec.get("frames", 4)):
		if shot != "":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(shot)
		for ch in frame.get_children():
			dump(ch, ch.name)
		return true
	return false
