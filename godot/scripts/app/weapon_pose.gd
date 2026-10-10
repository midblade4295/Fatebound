extends RefCounted
# A weapon set posed like the Armory Reforged concept sheets (0.31.93): the off-hand shield upright behind, the main
# weapon diagonal in front (tip to the upper right); a non-shield off-hand piece (a second dagger, a tome) mirrored.
# Used by the Forge's preview (forge_stage.gd) and the Locker/shop icons (tools/render_weapon_icons.gd). Fits a
# 2.35-unit orthographic frame centred on the origin, looking down -Z.
# 0.31.94 (every class): a piece is first stood up -- its longest side up, its broadest face to the camera -- since a bow
# or crossbow lies along Z or X in its hand space and a claw is wider than it is tall; a staff shows its face (the side
# the ornament looks out of, View.STAFF_FACE); a closed tome shows its cover (fitted to face out of the hand, -Z).
const View = preload("res://scripts/siege/siege_view.gd")
const COVER_BACK := ["mw/spellwright_tome", "mw/hex_tome", "mw/gravecaller_tome", "mw/prism_tome", "mw/rootwise_tome"]

static func _piece(file: String) -> Node3D:
	if file == "":
		return null
	var ps: PackedScene = load(View.weapon_path(file))
	return ps.instantiate() if ps != null else null

static func _bounds(n: Node3D) -> AABB:
	return View._model_box(n)

static func _upright(file: String, b: AABB) -> Basis:
	# the turn that shows the piece best: a staff's face to the camera; anything else longest side up, broadest face out
	var t := View.weapon_template(file)
	if COVER_BACK.has(file):
		return Basis(Vector3.UP, PI)
	if View.STAFF_FACE.has(t):
		var f: Vector3 = View.STAFF_FACE[t]
		return Basis(Vector3.UP, -atan2(f.x, f.z))
	var s := b.size
	var order := [0, 1, 2]
	order.sort_custom(func(a, c): return s[a] > s[c])
	var cols := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	cols[order[0]] = Vector3.UP
	cols[order[1]] = Vector3.RIGHT
	cols[order[2]] = Vector3.BACK
	var bs := Basis(cols[0], cols[1], cols[2])
	if bs.determinant() < 0.0:
		cols[order[1]] = Vector3.LEFT
		bs = Basis(cols[0], cols[1], cols[2])
	return bs

static func _stand(holder: Node3D, piece: Node3D, file: String, height: float) -> Node3D:
	# holder <- (scale, tilt) <- (stand up) <- the piece, centred
	var tilt := Node3D.new()
	holder.add_child(tilt)
	var up := Node3D.new()
	tilt.add_child(up)
	up.add_child(piece)
	var b := _bounds(piece)
	piece.position = -b.get_center()
	up.basis = _upright(file, b)
	var stood: AABB = Transform3D(up.basis, Vector3.ZERO) * AABB(-b.size * 0.5, b.size)
	tilt.scale = Vector3.ONE * (height / maxf(stood.size.y, 0.01))
	return tilt

static func compose(holder: Node3D, r_file: String, l_file: String, fx := {}) -> void:
	var main := _piece(r_file)
	var off := _piece(l_file)
	var main_file := r_file
	var off_shield: bool = l_file != "" and View.weapon_template(l_file).contains("shield")
	var off_book: bool = l_file != "" and View.weapon_template(l_file).contains("spellbook")
	if off != null and not off_shield and (main == null or r_file.contains("quiver")):
		# a bow held in the left hand is the weapon (a quiver in the right only carries its arrows)
		var swap := main
		main = off
		off = swap
		main_file = l_file
		l_file = r_file
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
		var mb := _stand(holder, main, main_file, 2.1)
		mb.rotation_degrees = Vector3(0, -12, -38)
		mb.position = Vector3(-0.12 if off != null else 0.0, 0.0, 0.3)
		if int(fx.get("stars", 0)) > 0:
			View.apply_forge(main, fx, true)
	if off != null and not off_shield:
		var ob := _stand(holder, off, l_file, 1.25 if off_book else 1.6)
		ob.rotation_degrees = Vector3(0, 12, 38) if not off_book else Vector3(0, -10, 12)
		ob.position = Vector3(0.25, 0.0, 0.1) if not off_book else Vector3(0.4, -0.15, -0.3)
		if int(fx.get("stars", 0)) > 0:
			View.apply_forge(off, fx, false)
