extends "res://tools/trailer6_shots.gd"
# Play Store cinematic stills (0.31.116, Kevin: "new playstore screenshots ... a mix of cinematic action screenshots along
# with gameplay screenshots"): trailer 6's staged runs, played up to one moment and that frame saved, at any size (the
# window's: --resolution 1080x1920 for a portrait shot). Nothing is drawn until just before the moment (the match, its
# animations and the cameras run as in the trailer), so a still costs a few seconds rather than a whole recording.
#   RUN=<court|run|fall|charge> AT=<game seconds> OUT=<png> [PRESET=<name>] [CAM="ex,ey,ez,lx,ly,lz,fov"] [WIDE=1]
#   FB_FORCE_HQ=1 DISPLAY=:98 godot --rendering-method mobile --fixed-fps 30 --resolution 1080x1920 --path . \
#       -s res://tools/store3_shots.gd
# PRESET is one of the portrait framings below (from the run's own staging); CAM replaces the trailer's camera outright;
# WIDE=1 keeps the trailer camera's width instead of its height (a tall frame shows more above and below). Tuning: PAN
# (metres sideways), FOV, EYE_Y (meteor), BACK (gate_blast), WARM (seconds drawn before the moment), NOHATS=1 (no dropped
# hats), ROCK=1 (the game's own falling meteor rock).
var at := 0.0
var out := "/tmp/store3/still.png"
var cam_spec: Array = []
var saving := false

func _init() -> void:
	super._init()
	at = float(OS.get_environment("AT")) if OS.has_environment("AT") else 1.0
	if OS.has_environment("OUT"):
		out = OS.get_environment("OUT")
	if OS.has_environment("CAM"):
		cam_spec = Array(OS.get_environment("CAM").split(",")).map(func(x): return float(x))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	seed(int(OS.get_environment("SEED")) if OS.has_environment("SEED") else 7)    # (the blasts throw people at random)
	RenderingServer.render_loop_enabled = false

func _process(delta: float) -> bool:
	if saving:
		return false
	var r := super._process(delta)
	if frames >= 2 and mode.view != null and mode.view.camera != null:
		if OS.has_environment("WIDE"):
			mode.view.camera.keep_aspect = Camera3D.KEEP_WIDTH
		var pc := _preset(OS.get_environment("PRESET")) if OS.has_environment("PRESET") else []
		if not pc.is_empty():
			var e: Vector3 = pc[0]
			var l: Vector3 = pc[1]
			if OS.has_environment("PAN"):                       # slide the camera sideways (the subject moves the other way)
				var rt := (l - e).cross(Vector3.UP).normalized() * float(OS.get_environment("PAN"))
				e += rt
				l += rt
			mode.view.cam_override = [e, l]
			mode.view.camera.fov = float(pc[2]) if not OS.has_environment("FOV") else float(OS.get_environment("FOV"))
		if cam_spec.size() >= 6:
			mode.view.cam_override = [Vector3(cam_spec[0], cam_spec[1], cam_spec[2]), Vector3(cam_spec[3], cam_spec[4], cam_spec[5])]
			if cam_spec.size() >= 7:
				mode.view.camera.fov = cam_spec[6]
	if OS.has_environment("NOHATS") and s != null:
		s.hats.clear()                                         # (no dropped hats lying in the foreground)
	if OS.has_environment("ROCK") and mode.view != null:
		for w in mode.view._meteors_fx:                        # the game's own falling meteor, not the trailer's fireball
			if w.has("rock") and is_instance_valid(w.rock):
				(w.rock as Node3D).visible = true
	var warm := float(OS.get_environment("WARM")) if OS.has_environment("WARM") else 0.6
	if t >= at - warm and not RenderingServer.render_loop_enabled:
		RenderingServer.render_loop_enabled = true            # (effects and particles warm up for the shot)
	if t >= at and frames > 4:
		saving = true
		RenderingServer.frame_post_draw.connect(func():
			root.get_texture().get_image().save_png(out)
			printerr("STILL_DONE %s t=%.3f" % [out, t])
			OS.kill(OS.get_process_id()), CONNECT_ONE_SHOT)       # (Godot can hang on exit after a run like this)
	return r

func _fireball_launch(to: Vector3) -> void:
	# (the trailer's fireball rides the staff mesh the Archmage no longer has as a separate piece: without it, the sim's
	# meteor is still set off on time -- the game's own falling rock shows with ROCK=1)
	if fb == null or not is_instance_valid(fb):
		set_meta("fb_t0", float(s.time) + float(mode._accum) + frame_dt)
		return
	super._fireball_launch(to)

func _preset(name: String) -> Array:
	# [eye, look, vertical fov] for a portrait frame
	var gate: Dictionary = s.gates.filter(func(g): return g.team == 1 and str(g.get("kind", "")) != "jail" and (g.c as Vector2).x > 0.0)[0]
	var gf: Vector2 = Sim.gate_front(gate)
	match name:
		"gate_blast":
			# (charge) low behind the hero and his friends, their gate going up in front of them
			var ta: Vector2 = get_meta("throw_at")
			var tg: Vector2 = (gf - ta).normalized()
			var pr := Vector2(-tg.y, tg.x)
			var back := float(OS.get_environment("BACK")) if OS.has_environment("BACK") else 7.5
			var b := _bomb()
			var aim: Vector2 = gf.lerp(b.p, 0.75) if not b.is_empty() and str(b.state) != "carried" else gf
			if has_meta("aim"):
				aim = get_meta("aim")
			elif t >= 7.2:
				set_meta("aim", aim)                              # (held once it goes off)
			var ly2 := float(OS.get_environment("LOOK_Y")) if OS.has_environment("LOOK_Y") else 3.0
			var ey2 := float(OS.get_environment("EYE_Y")) if OS.has_environment("EYE_Y") else 2.6
			return [_g(ta - tg * back + pr * 0.4, ey2), _g(aim, ly2), 60.0]
		"breach":
			# (charge) everyone in through the broken gate, from behind them
			var ta2: Vector2 = get_meta("throw_at")
			var tg2: Vector2 = (gf - ta2).normalized()
			var pr2 := Vector2(-tg2.y, tg2.x)
			return [_g(ta2 - tg2 * 4.0 + pr2 * 1.6, 3.6), _g(gf + tg2 * 1.5, 1.6), 60.0]
		"rally":
			# (charge) the Villager running the bomb at the viewer, his friends falling in round him
			var d3: Vector2 = get_meta("dir")
			var sd3 := Vector2(-d3.y, d3.x)
			var a3 := _actor(hero.id)
			var hb3: Vector3 = (a3.root as Node3D).position if not a3.is_empty() else _g(hero.pos)
			var dist := float(OS.get_environment("DIST")) if OS.has_environment("DIST") else 6.0
			return [hb3 + _v(d3 * dist + sd3 * 0.8, 1.5), hb3 + _v(d3 * 0.5 - sd3 * 0.2, 1.5), 56.0]
		"charge_in":
			# (charge) inside their gate, the army pouring in through the breach at the viewer
			var ta4: Vector2 = get_meta("throw_at")
			var tg4: Vector2 = (gf - ta4).normalized()
			return [_g(gf + tg4 * 3.0, 1.5), _g(ta4 - tg4 * 1.0, 1.4), 60.0]
		"whirl":
			# (charge) the Berserker's spin through the three who rush him, from in front
			var d: Vector2 = get_meta("dir")
			var sd := Vector2(-d.y, d.x)
			var bz_id: String = str(get_meta("allies")[4])
			var a := _actor(bz_id)
			var hb: Vector3 = (a.root as Node3D).position if not a.is_empty() else _g(s.by_id[bz_id].pos)
			return [hb + _v(d * 5.5 - sd * 3.0, 1.8), hb + _v(d * 1.0 + sd * 0.8, 1.0), 60.0]
		"meteor":
			# (fall) the blast from the side and further back, the bodies thrown up into the frame
			var c: Vector2 = get_meta("meteor_c")
			var dd: Vector2 = get_meta("pace_dir")
			var sdd := Vector2(dd.y, -dd.x)
			var hh: Vector2 = c - dd * 3.4 - sdd * 1.8
			var be: Vector2 = hh - sdd * 8.5 - dd * 2.5
			var ey := float(OS.get_environment("EYE_Y")) if OS.has_environment("EYE_Y") else 1.7
			var ly := float(OS.get_environment("LOOK_Y")) if OS.has_environment("LOOK_Y") else 2.6
			return [_g(be, ey), _g(c - dd * 0.5, ly), 60.0]
		"cast":
			# (fall) the red Archmage, the fire gathering on his raised staff, his target far behind him
			var c2: Vector2 = get_meta("meteor_c")
			var dd2: Vector2 = get_meta("pace_dir")
			var sdd2 := Vector2(dd2.y, -dd2.x)
			var mp: Vector2 = c2 + dd2 * 6.5 - sdd2 * 9.0
			var to_c: Vector2 = (c2 - mp).normalized()
			var mr := Vector2(-to_c.y, to_c.x)
			return [_g(mp + to_c * 3.6 + mr * 1.2, 1.0), _g(mp - to_c * 0.2, 2.4), 60.0]
	return []
