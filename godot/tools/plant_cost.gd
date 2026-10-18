extends SceneTree
# Dev tool (0.31.173): what the Rift's trees and bushes cost to draw -- triangles in the 3D view and in the shadow pass,
# and draw calls -- with the match's own camera following you at nine spots, the 3D view at the phone's real size
# (siege_mode.RENDER_SCALE 0.5 of the S21 Ultra's 1440x3200: 720x1600; VW/VH to change it). The sim is held still and
# the camera given 60 frames to settle, so every run and every group sees the same frame.
#   FB_FORCE_HQ=1 DISPLAY=:98 godot --rendering-method mobile --resolution 450x1000 --fixed-fps 30 --path godot \
#     -s res://tools/plant_cost.gd
# PLANT_GROUPS (comma list; default all,none): "all" as the game draws it; "none" without any plant; or one group hidden --
# brush, ridges, edge_trees, outer_trees, shadows (the trees' shadow copies). SPOTS: "x_y" places to stand.
# Prints COST lines per spot and group, then the totals. Runs on 0.31.172 too (its KayKit plants are found by name).
const Mode = preload("res://scripts/siege/siege_mode.gd")
var mode
var frames := 0
var spots := ["-24_46", "-46_20", "0_60", "24_46", "46_20", "0_88", "0_10", "-50_70", "50_-20"]
var groups := ["all", "none"]
var si := -1
var gi := 0
var hold := 0
var tot := {}

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	if OS.has_environment("SPOTS"):
		spots = Array(OS.get_environment("SPOTS").split(","))
	if OS.has_environment("PLANT_GROUPS"):
		groups = Array(OS.get_environment("PLANT_GROUPS").split(","))
	mode = Mode.new()
	mode.moba_hero = "knight"
	mode.match_seed = 4401
	root.add_child(mode)

static func _is_plant(c: Node) -> bool:
	var n := str(c.name)
	if n.begins_with("Brush_") or n.begins_with("Plants_") or n.begins_with("Shadows_"):
		return true
	if not (c is MultiMeshInstance3D) and n.begins_with("Tree_"):
		return true                                    # (0.31.172's edge trees: a KayKit scene each)
	var p := str(c.get_meta("perf", ""))
	if p in ["outer_trees", "edge_trees", "brush"]:
		return true
	var k := str(c.get_meta("perf_kind", ""))
	return p == "ridges" and (k.begins_with("Tree") or k.begins_with("Bush"))

static func _group(c: Node) -> String:
	var n := str(c.name)
	if n.begins_with("Brush_"):
		return "brush"
	if n.begins_with("Shadows_"):
		return "shadows"
	if not (c is MultiMeshInstance3D) and n.begins_with("Tree_"):
		return "edge_trees"
	return str(c.get_meta("perf", ""))

func _show(g: String) -> void:
	for c in mode.view.get_children():
		if c is Node3D and _is_plant(c):
			(c as Node3D).visible = not (g == "none" or _group(c) == g)

func _process(_d: float) -> bool:
	frames += 1
	if frames > 40:
		mode._accum = -1.0e9                       # (the sim held still: the same units in every measure)
	if mode.sim == null or not mode._build_queue.is_empty() or frames < 40:
		return false
	if frames == 40:
		mode.hud.visible = false
		mode.view.fog_on = false
		mode.viewport.size = Vector2i(int(OS.get_environment("VW")) if OS.has_environment("VW") else 720,
			int(OS.get_environment("VH")) if OS.has_environment("VH") else 1600)
	if hold > 0:
		hold -= 1
		if hold == 0:
			var vp: RID = mode.viewport.get_viewport_rid()
			var a := [RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
				RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
				RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)]
			var g := str(groups[gi])
			print("COST %-8s %-12s view %7d  shadow %7d  draws %4d" % [spots[si], g, a[0], a[1], a[2]])
			if not tot.has(g):
				tot[g] = [0, 0, 0]
			for i in 3:
				tot[g][i] += int(a[i])
			gi += 1
			if gi < groups.size():
				_show(str(groups[gi]))
				hold = 4
		return false
	si += 1
	if si >= spots.size():
		for g in groups:
			print("COST total    %-12s view %7d  shadow %7d  draws %4d  (a spot: %d / %d)" % [g, tot[g][0], tot[g][1], tot[g][2],
				tot[g][0] / spots.size(), tot[g][1] / spots.size()])
		quit(0)
		return false
	var xy := str(spots[si]).split("_")
	mode.view.cam_override = []
	(mode.sim.by_id["you"] as Dictionary).pos = Vector2(float(xy[0]), float(xy[1]))
	gi = 0
	_show("all")
	hold = 60
	return false
