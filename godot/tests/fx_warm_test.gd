extends SceneTree
# 0.31.207 (Kevin: "The match keeps getting stutters"): the match's loading card shows every look once before the match
# is seen -- each of this match's heroes' casts, Q and ultimate, the one-off events, the lasting states, the zones, a
# trap, each projectile's trail (spell_fx.gd warm_jobs), the jungle's monsters (siege_view.gd warm_bodies), a wave's
# minions into the pool with the first of each drawn (prefill_minions) and a fight's looks (warm_fight) -- then clears
# it all (clear_all, warm_end). A 5v5 with the warm-up forced on (FB_FORCE_WARMUP):
#   - the card waits for every job, then lifts (not cut short by its limit);
#   - at the lift nothing it showed is left: no effect live or held, the pooled bodies hidden, no loose weapons, no
#     blood, what the view made for the looks hidden;
#   - the match clock waited behind the card;
#   - then every one of the 18 heroes' looks played on your hero (not only this match's ten), and cleared: no errors.
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const Kits = preload("res://scripts/siege/moba_kits.gd")

var mode
var frames := 0
var phase := "warm"
var fails := []
var t_lift := -1.0
var saw_card := false

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	OS.set_environment("FB_FORCE_WARMUP", "1")
	mode = Mode.new()
	mode.moba_hero = "mage"
	mode.match_seed = 4402
	root.add_child(mode)

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("FAIL ", what)

func _finish() -> void:
	if fails.is_empty():
		print("FX_WARM_PASS")
		quit(0)
	else:
		print("FX_WARM_FAIL ", fails)
		quit(1)

func _process(_d: float) -> bool:
	frames += 1
	if frames > 3000:
		print("FX_WARM_FAIL timeout in ", phase)
		quit(1)
		return false
	if mode.sim == null or not mode._build_queue.is_empty():
		return false
	var view = mode.view
	var fxs = view.fxs
	match phase:
		"warm":
			var w: Dictionary = mode._warm
			if not w.is_empty():
				saw_card = true
				if float(w.fade) >= 0.0 and t_lift < 0.0:
					# the frame it lifts (its clear ran in this frame's _warm_step; the view's sync after it)
					t_lift = float(w.t)
					_check(float(w.t) < mode.warm_max, "the card lifted at its limit (%.1f s): jobs cut short" % float(w.t))
					_check((w.fx as Array).is_empty() and (w.pool as Array).is_empty() and (w.fight as Array).is_empty(), "every job ran")
					_check(fxs._live.is_empty(), "no effect left live (%d)" % fxs._live.size())
					_check(fxs._holds.is_empty(), "no effect left held (%s)" % str(fxs._holds.keys()))
					_check(view._pool_shown.is_empty(), "the shown bodies put away")
					_check(view._debris.is_empty(), "no loose weapons")
					for list in [view._splats, view._pools]:
						for m in list:
							_check(not (m.mi as Node3D).visible, "no blood left")
					for n in w.shown:
						if is_instance_valid(n) and n is Node3D:
							_check(not (n as Node3D).visible, "what the view made for a look hidden (%s)" % str(n))
					_check(view.pool_size() == 78, "the pool filled: %d (want 78)" % view.pool_size())
					_check(int(fxs.warm_shown) >= 40, "looks shown %d" % int(fxs.warm_shown))
					_check(mode.sim.time < 0.5, "the match clock waited (t=%.2f)" % mode.sim.time)
					print("WARM lifted at %.2f s: %d looks shown, %d bodies pooled, %d view nodes noted" % [t_lift, int(fxs.warm_shown), view.pool_size(), (w.shown as Array).size()])
			elif saw_card:
				_check(t_lift >= 0.0, "the card lifted")
				phase = "all"
				frames = 0
			return false
		"all":
			# every hero's looks, on your own hero
			var me_id: String = mode.hud.player_id
			var n0: int = int(fxs.warm_shown)
			for hid in Moba.HERO_ORDER:
				var h: Dictionary = (Moba.HEROES[hid] as Dictionary).duplicate()
				h["hid"] = hid
				h["hero"] = true
				var kq: String = Kits.kit_q(hid)
				if kq != "":
					h["kq"] = kq
				fxs._warm_hero(me_id, h)
			fxs._warm_events(me_id, Moba.HERO_ORDER)
			fxs._warm_states(me_id)
			fxs._warm_zones(me_id)
			fxs._warm_trails(me_id)
			_check(int(fxs.warm_shown) - n0 >= 18 * 3, "every hero's looks shown (%d)" % (int(fxs.warm_shown) - n0))
			_check(not fxs._live.is_empty(), "the looks are live")
			phase = "settle"
			frames = 0
			return false
		"settle":
			if frames < 20:
				return false
			fxs.clear_all()
			_check(fxs._live.is_empty() and fxs._holds.is_empty(), "all of them cleared")
			_finish()
	return false
