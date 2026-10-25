extends SceneTree
# 0.31.172 (Kevin: "new tower models" -- the Royal A lane and King towers -- "I want them to visually break as their
# health gets lower"): towers.gd and the view's towers.
#  - the stages by health: whole above 75 %, then 1 / 2 / 3 at 75 / 50 / 25 %, 4 once fallen;
#  - both models load with their cells: every triangle in a cell, every cell breaking at a stage (1-4) or never (the
#    foot), each of the four stages taking some of the tower, and the foot left standing;
#  - in a match: every tower drawn from its model (tier 4 the King tower), its front towards the other side, its shots
#    starting at its brazier; hurt one past 75 %, 50 %, 25 % and down -- the right stage each time, its mesh told to
#    hide that stage's cells, the broken-off pieces falling, landing and gone a few seconds later, smoke from 50 %, its
#    brazier out at 25 %; a match joined with a tower already half down shows it so at once (nothing falls).
#   godot --headless --path godot -s res://tests/tower_look_test.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Towers = preload("res://scripts/siege/towers.gd")
var mode
var frames := 0
var fails := []
var phase := 0
var t_mark := 0
var tw_id := 3

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	check(Towers.stage_of(900, 900, false) == 0 and Towers.stage_of(676, 900, false) == 0 and Towers.stage_of(675, 900, false) == 1
		and Towers.stage_of(450, 900, false) == 2 and Towers.stage_of(225, 900, false) == 3 and Towers.stage_of(1, 900, false) == 3
		and Towers.stage_of(0, 900, true) == 4, "stages by health: 75 / 50 / 25 %, then fallen")
	check(Towers.kind_of(1) == "lane" and Towers.kind_of(3) == "lane" and Towers.kind_of(4) == "king"
		and Towers.height(2) > Towers.height(1) and Towers.height(3) > Towers.height(2), "the lane tower a little bigger each tier; the King's own")
	for tier in [1, 4]:
		var node := Towers.instance(tier, 0)
		var mi: MeshInstance3D = node.get_meta("mesh", null)
		check(mi != null and mi.material_override is ShaderMaterial, "%s: the model, drawn with tower.gdshader" % Towers.kind_of(tier))
		if mi == null:
			continue
		var a: Array = mi.mesh.surface_get_arrays(0)
		var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var tris := idx.size() / 3
		var pieces := Towers.chunks(Towers.kind_of(tier), mi.mesh)
		var by_stage := {}
		var in_cells := 0
		var bad := 0
		for c in pieces:
			by_stage[int(c.stage)] = int(by_stage.get(int(c.stage), 0)) + int(c.tris)
			in_cells += int(c.tris)
			if not int(c.stage) in [1, 2, 3, 4, 9]:
				bad += 1
		check(uv2.size() > 0 and in_cells == tris and bad == 0, "%s: %d triangles, all in %d cells, each with its stage" % [Towers.kind_of(tier), tris, pieces.size()])
		var share := []
		for s in [1, 2, 3, 4, 9]:
			share.append(float(by_stage.get(s, 0)) / float(tris))
		check(share.slice(0, 4).all(func(x): return x >= 0.05) and float(share[4]) >= 0.15,
			"%s: each stage takes some of it, the foot stays (%s)" % [Towers.kind_of(tier), str(share.map(func(x): return snappedf(x, 0.01)))])
		node.free()
	mode = Mode.new()
	mode.moba_hero = "knight"
	mode.match_seed = 4402
	root.add_child(mode)

func _process(_d: float) -> bool:
	frames += 1
	if mode.sim == null or not mode._build_queue.is_empty() or frames < 30:
		return false
	var s = mode.sim
	var v = mode.view
	if phase == 0:
		phase = 1
		s.moba.wave_at = INF
		for c in s.moba.camps:
			c.next = INF
		for u in s.units:
			if bool(u.get("hero", false)):
				u.bot = false
				u.pos = s.spawn(int(u.team))
				u.move = Vector2.ZERO
				u.task = {}
		var drawn := 0
		var faced := 0
		for tw in s.moba.towers:
			var mt: Dictionary = v.moba_towers.get(int(tw.id), {})
			if mt.is_empty() or not is_instance_valid(mt.node):
				continue
			if str((mt.node as Node3D).get_meta("kind", "")) == Towers.kind_of(int(tw.tier)) and mt.mesh != null:
				drawn += 1
			var front: Vector3 = (mt.node as Node3D).global_basis.z
			var to: Vector2 = s.throne(1 - int(tw.team)) - (tw.p as Vector2)
			if Vector2(front.x, front.z).normalized().dot(to.normalized()) > 0.99:
				faced += 1
		check(drawn == s.moba.towers.size() and drawn == 18, "every tower drawn from its model (%d of %d)" % [drawn, s.moba.towers.size()])
		check(faced == drawn, "each facing the other side's keep (%d)" % faced)
		var mt3: Dictionary = v.moba_towers[tw_id]
		var tw3: Dictionary = s.moba.towers[tw_id]
		var top: Vector3 = mt3.top
		var gy: float = s.height_at(tw3.p)
		check(absf(top.y - gy - Towers.brazier(int(tw3.tier)).y) < 0.01 and top.y - gy > 3.0, "its shots start at its brazier (%.1f m up)" % (top.y - gy))
		check(int(mt3.stage) == 0 and is_instance_valid(mt3.fire) and mt3.smoke == null, "whole: its brazier burning, no smoke")
		t_mark = frames
		return false
	var tw: Dictionary = s.moba.towers[tw_id]
	var mt: Dictionary = v.moba_towers[tw_id]
	var mi: MeshInstance3D = mt.mesh
	var dt := frames - t_mark
	if phase == 1 and dt == 2:
		tw.hp = float(tw.max_hp) * 0.7
	elif phase == 1 and dt == 4:
		check(int(mt.stage) == 1 and is_equal_approx(float(mi.get_instance_shader_parameter("broken")), 1.0) and v._falling.size() > 0,
			"at 70 %%: stage 1, its first cells hidden, %d pieces falling" % v._falling.size())
		check(float(mi.get_instance_shader_parameter("dmg")) > 0.25, "cracks spreading (dmg %.2f)" % float(mi.get_instance_shader_parameter("dmg")))
		tw.hp = float(tw.max_hp) * 0.45
	elif phase == 1 and dt == 6:
		check(int(mt.stage) == 2 and mt.smoke != null and is_instance_valid(mt.fire), "at 45 %: stage 2, smoke rising, the brazier still lit")
		tw.hp = float(tw.max_hp) * 0.2
	elif phase == 1 and dt == 8:
		check(int(mt.stage) == 3 and mt.fire == null and is_equal_approx(float(mi.get_instance_shader_parameter("lit")), 0.0) and mt.flames != null,
			"at 20 %: stage 3, the brazier out, flames from the broken top")
		var f0: Dictionary = v._falling[0]
		check(float(f0.rest) < 0.0, "the pieces still in the air")
		tw.hp = 0.0
		tw.dead = true
		s._event("tower_down", {"tw":tw_id, "team":int(tw.team), "lane":int(tw.lane), "tier":int(tw.tier), "by":"you"})
	elif phase == 1 and dt == 10:
		check(int(mt.stage) == 4 and is_equal_approx(float(mi.get_instance_shader_parameter("broken")), 4.0) and mt.flames == null,
			"fallen: stage 4, all but its foot down (%d pieces)" % v._falling.size())
		check(is_instance_valid(mt.node) and (mt.node as Node3D).visible, "its foot still stands")
	elif phase == 1 and dt == 90:
		var landed: int = v._falling.filter(func(f): return float(f.rest) >= 0.0).size()
		check(landed > 0, "the pieces landed (%d of %d)" % [landed, v._falling.size()])
	elif phase == 1 and dt == 420:
		check(v._falling.is_empty(), "and gone a few seconds later (%d left)" % v._falling.size())
		# a match joined late: a tower already half down is drawn so at once, nothing falls
		var tw2: Dictionary = s.moba.towers[tw_id + 1]
		var mt2: Dictionary = v.moba_towers[tw_id + 1]
		tw2.hp = float(tw2.max_hp) * 0.4
		mt2.stage = -1
		phase = 2
		t_mark = frames
	elif phase == 2 and frames - t_mark == 3:
		var mt2: Dictionary = v.moba_towers[tw_id + 1]
		check(int(mt2.stage) == 2 and v._falling.is_empty(), "a first look at a half-down tower: stage 2 at once, nothing falling")
		print("TOWER_LOOK_%s" % ("PASS" if fails.is_empty() else "FAIL %s" % str(fails)))
		quit(0 if fails.is_empty() else 1)
		return true
	return false
