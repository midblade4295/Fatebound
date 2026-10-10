extends RefCounted
# A weapon set posed like the Armory Reforged concept sheets (0.31.93): the off-hand shield upright behind, the main
# weapon diagonal in front (tip to the upper right); a non-shield off-hand piece (a second dagger, a tome) mirrored.
# Used by the Forge's preview (forge_stage.gd) and the Locker/shop icons (tools/render_weapon_icons.gd). Fits a
# 2.35-unit orthographic frame centred on the origin, looking down -Z.
const View = preload("res://scripts/siege/siege_view.gd")

static func _piece(file: String) -> Node3D:
	if file == "":
		return null
	var ps: PackedScene = load(View.weapon_path(file))
	return ps.instantiate() if ps != null else null

static func _bounds(n: Node3D) -> AABB:
	return View._model_box(n)

static func compose(holder: Node3D, r_file: String, l_file: String, fx := {}) -> void:
	var main := _piece(r_file)
	var off := _piece(l_file)
	var off_shield: bool = l_file != "" and View.weapon_template(l_file).contains("shield")
	if main == null and off != null and not off_shield:
		main = off                      # (a bow held in the left hand: it is the weapon)
		off = null
	if off != null and off_shield:
		var sb := Node3D.new()
		holder.add_child(sb)
		sb.add_child(off)
		var b := _bounds(off)
		off.position = -b.get_center()
		sb.scale = Vector3.ONE * (1.55 / maxf(b.size.y, b.size.x))
		sb.rotation_degrees = Vector3(0, 14, 0)
		sb.position = Vector3(0.28, -0.05, -0.4)
		if int(fx.get("stars", 0)) > 0:
			View.apply_forge(off, fx, false)
	if main != null:
		var mb := Node3D.new()
		holder.add_child(mb)
		mb.add_child(main)
		var b2 := _bounds(main)
		main.position = -b2.get_center()
		mb.scale = Vector3.ONE * (2.1 / maxf(b2.size.y, 0.01))
		mb.rotation_degrees = Vector3(0, -12, -38)
		mb.position = Vector3(-0.12 if off != null else 0.0, 0.0, 0.3)
		if int(fx.get("stars", 0)) > 0:
			View.apply_forge(main, fx, true)
	if off != null and not off_shield:
		var ob := Node3D.new()
		holder.add_child(ob)
		ob.add_child(off)
		var b3 := _bounds(off)
		off.position = -b3.get_center()
		ob.scale = Vector3.ONE * (1.6 / maxf(b3.size.y, 0.01))
		ob.rotation_degrees = Vector3(0, 12, 38)
		ob.position = Vector3(0.25, 0.0, 0.1)
		if int(fx.get("stars", 0)) > 0:
			View.apply_forge(off, fx, false)
