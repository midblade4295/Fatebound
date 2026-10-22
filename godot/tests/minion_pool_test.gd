extends SceneTree
# 0.31.207 (Kevin: "The match keeps getting stutters"): the lane minions' bodies come from a pool (siege_view.gd
# prefill_minions / _pool_take / _pool_put) and any other body waits its turn, BUILD_PER_FRAME a frame. A 5v5 of bots,
# the loading card's prefill run by hand (the warm-up is skipped under a scripted main loop), then the sim stepped with
# the view synced each step through the first three waves:
#   - the prefill fills the pool with two waves' bodies (and no more);
#   - no frame builds more than BUILD_PER_FRAME bodies other than heroes;
#   - the first two waves come out of the pool without building a minion's body;
#   - the loading card shows the first of each kind and side (drawn once), and its fall; warm_end puts it all away;
#   - a fallen minion's body goes back to the pool (hidden, its animation off) and comes out again at its next one,
#     alive -- its ring up, its weapons back in its hands;
#   - every minion alive has its body (none left waiting).
const Mode = preload("res://scripts/siege/siege_mode.gd")
const View = preload("res://scripts/siege/siege_view.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")

var mode
var frames := 0
var phase := "boot"
var fails := []
var built_max := 0
var waves_seen := 0
var built_wave2 := 0

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	mode = Mode.new()
	mode.moba_hero = "knight"
	mode.match_seed = 4402
	root.add_child(mode)

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("FAIL ", what)

func _minions_alive(s) -> Array:
	var out := []
	for u in s.units:
		if bool(u.get("minion", false)) and not u.has("look") and s.alive(u):
			out.append(u)
	return out

func _process(_d: float) -> bool:
	frames += 1
	if phase == "boot":
		if mode.sim == null or not mode._build_queue.is_empty() or frames < 20:
			return false
		var view = mode.view
		var s = mode.sim
		s.by_id["you"].bot = true
		var jobs: Array = view.prefill_minions({"melee":6, "caster":6, "siege":1})
		_check(jobs.size() == 2 * 13 * 3, "prefill jobs %d (want 78)" % jobs.size())
		for j in jobs:
			(j as Callable).call()
		_check(view.pool_size() == 78, "pool after the prefill %d (want 78)" % view.pool_size())
		for j in view.prefill_minions({"melee":6, "caster":6, "siege":1}):
			(j as Callable).call()
		_check(view.pool_size() == 78, "a second prefill adds nothing (%d)" % view.pool_size())
		# the loading card shows the first of each kind and side beside you (drawn once); warm_end hides them
		var shown := 0
		for k in view._minion_pool:
			for a in view._minion_pool[k]:
				shown += 1 if (a.root as Node3D).visible else 0
		_check(shown == 6, "the first of each kind and side shown on the card: %d (want 6)" % shown)
		var fight: Array = view.warm_fight()
		for j in fight:
			(j as Callable).call()
		view.warm_end()
		for k in view._minion_pool:
			for a in view._minion_pool[k]:
				_check(not (a.root as Node3D).visible, "a pooled body hidden after the card (%s)" % k)
				_check(a.get("rag") == null, "no ragdoll left on a pooled body (%s)" % k)
		_check(view._debris.is_empty(), "no loose weapons left from the card")
		phase = "run"
		mode.process_mode = Node.PROCESS_MODE_DISABLED     # (the test steps the sim and syncs the view itself)
		print("POOL prefilled ", view.pool_size())
		return false
	if phase != "run":
		return false
	var s = mode.sim
	var view = mode.view
	# a frame: the sim's ticks for 1/30 s, then the view (as siege_mode does), the bodies built this frame counted
	var b0: int = view.pool_built
	var r0: int = view.pool_reused
	for i in 2:
		s.step(Sim.TICK)
	for e in s.drain_events():
		if str(e.k) == "wave":
			waves_seen += 1
		view.on_event(e)
	view.sync(1.0 / 30.0)
	var built: int = view.pool_built - b0
	built_max = maxi(built_max, built)
	_check(built <= View.BUILD_PER_FRAME, "t=%.1f: %d bodies built in a frame" % [s.time, built])
	if view.pool_reused > r0 or built > 0:
		print("  t=%.1f  from the pool %d, built %d, pooled %d, minions %d" % [s.time, view.pool_reused - r0, built, view.pool_size(), _minions_alive(s).size()])
	if s.time > 44.9 and s.time < 46.5:
		built_wave2 += built
	if s.time > 47.0 and phase == "run":
		phase = "done"
		var alive := _minions_alive(s)
		var missing := 0
		for u in alive:
			var a: Dictionary = view.actors.get(str(u.id), {})
			if a.is_empty() or not is_instance_valid(a.root):
				missing += 1
		print("POOL t=%.0f waves %d, minions alive %d (bodies missing %d), reused %d, built %d (most a frame %d), pooled now %d" % [s.time,
			waves_seen, alive.size(), missing, view.pool_reused, view.pool_built, built_max, view.pool_size()])
		_check(missing == 0, "%d minions with no body" % missing)
		_check(waves_seen >= 12, "waves seen %d (two a side a lane... want 12)" % waves_seen)
		_check(view.pool_reused >= 72, "bodies from the pool %d (want the first two waves', 72)" % view.pool_reused)
		_check(built_wave2 == 0, "the second wave built %d bodies (want none: the pool's)" % built_wave2)
		# a body out of the pool: alive again -- its ring up, its weapons in its hands, not lying as it fell
		var checked := 0
		for u in alive:
			var a: Dictionary = view.actors.get(str(u.id), {})
			if a.is_empty() or str(a.get("pool_key", "")) == "":
				continue
			checked += 1
			_check(not bool(a.dead) and a.get("rag") == null, "%s: not still dead" % str(u.id))
			_check((a.ring as Node3D).visible, "%s: its ring up" % str(u.id))
			_check(str(a.clip) != "g/Death_A", "%s: not playing its fall" % str(u.id))
			var held := 0
			for slot in (a.body as Node3D).find_children("*", "BoneAttachment3D", true, false):
				if str((slot as BoneAttachment3D).bone_name).begins_with("handslot"):
					for w in (slot as Node).get_children():
						if w is Node3D and not (w as Node3D).visible:
							fails.append("%s: a weapon still hidden" % str(u.id))
						held += 1
			_check(held > 0, "%s: weapons in its hands" % str(u.id))
		_check(checked >= 30, "pooled minions checked %d" % checked)
		# and those waiting in the pool: hidden, their animation off
		for k in view._minion_pool:
			for a in view._minion_pool[k]:
				_check(not (a.root as Node3D).visible, "a pooled body hidden (%s)" % k)
				_check(not is_instance_valid(a.player) or not (a.player as AnimationPlayer).active, "a pooled body's animation off (%s)" % k)
		if fails.is_empty():
			print("MINION_POOL_PASS")
			quit(0)
		else:
			print("MINION_POOL_FAIL ", fails)
			quit(1)
	if frames > 4000:
		print("MINION_POOL_FAIL timeout t=%.1f" % s.time)
		quit(1)
	return false
