extends SceneTree
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Old = preload("res://tests/fixtures/siege_net_v30.gd")
const New = preload("res://scripts/siege/siege_net.gd")
const SEEDS := [1337, 424242]
var steps_limit := 240 # Fast by default; SIEGE_BANDWIDTH_STEPS overrides the per-seed tick count.
var benchmark := false
const UNIT_FIELDS := ["hp","max_hp","pos","face","state","cls","up","stun","carrying","lifting","load","offering","task","cd_ability","cd_dodge","kills","deaths","rescues","gathered","gate_dmg","bot","respawn_at","atk","beam","workshop_open","fed","block_until","whirl_until","tower","beam2"]
const SLOW_FIELDS := ["sc","k","o","st","lv","g","n","op","hs","hd","l"]
var sim
var m_old
var m_new
var seed_index := 0
var step_n := 0
var snaps := 0
var old_bytes := 0
var new_bytes := 0
var old_encode_us := 0
var new_encode_us := 0
var old_times: Array = []
var new_times: Array = []
var old_broadcast_us := 0
var new_broadcast_us := 0
var broadcast_n := 0
var errors := 0
var pending: Array = []
var start_us := 0
var packet_min := 1000000000
var packet_max := 0
var raw_old_bytes := 0
var raw_new_bytes := 0
var coverage := {}
var level := 0
var private_count := 0
var corpus: FileAccess

func _init() -> void:
	Engine.max_fps = 20
	benchmark = OS.get_environment("SIEGE_BANDWIDTH_BENCH") == "1"
	if OS.has_environment("SIEGE_BANDWIDTH_STEPS"):
		steps_limit = maxi(2,int(OS.get_environment("SIEGE_BANDWIDTH_STEPS")))
		steps_limit -= steps_limit % 2
	level = int(ProjectSettings.get_setting("compression/formats/zstd/compression_level"))
	start_us = Time.get_ticks_usec()
	_start_seed()
	_edge_cases()
	if benchmark:
		corpus = FileAccess.open("res://snapshot-fixtures.bin", FileAccess.WRITE)
	print("BENCH_START level=%d seeds=%s steps_per_seed=%d" % [level, SEEDS, steps_limit])

func _full_old(s, id: String, e: Array) -> Dictionary:
	# Full legacy reference for a join, without changing the measured broadcast cache.
	var before_n: int = Old._slow_n
	var before_hash: Dictionary = Old._slow_hash.duplicate()
	Old._slow_n = Old.FULL_EVERY - 1
	var msg := Old.snapshot(s,id,e)
	Old._slow_n = before_n
	Old._slow_hash = before_hash
	return msg

func _start_seed() -> void:
	sim = Sim.new()
	sim.setup(16, SEEDS[seed_index], -1)
	sim.units[0].bot = false
	m_old = Sim.new()
	m_old.setup(16, SEEDS[seed_index], -1)
	m_new = Sim.new()
	m_new.setup(16, SEEDS[seed_index], -1)
	Old._slow_hash.clear()
	Old._slow_n = 0
	New._slow_hash.clear()
	New._slow_n = 0
	var id: String = sim.units[0].id
	var a := _full_old(sim, id, [])
	var b := New.snapshot(sim, id, [])
	for key in SLOW_FIELDS:
		_check(b.has(key), "forced join missing " + key)
	_apply_compare(a, b, id, true)
	step_n = 0
	pending.clear()

func _check(ok: bool, label: String) -> void:
	if not ok:
		errors += 1
		if errors < 12:
			print("BENCH_FAIL " + label)

func _canon(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			if k not in ["net_from","net_to"]:
				out[k] = _canon(v[k])
		return out
	if v is Array:
		var out := []
		for x in v:
			out.append(_canon(x))
		return out
	return v

func _apply_compare(a: Dictionary, b: Dictionary, id: String, exhaustive := false) -> void:
	# Both snapshots are decoded and applied using the ORIGINAL installed protocol30 client code.
	var da := Old.decode(Old.encode(a, true))
	var db := Old.decode(New.encode(b, true))
	Old.apply(m_old, da, id, false)
	Old.apply(m_new, db, id, false)
	Old.interpolate(m_old, 1.0)
	Old.interpolate(m_new, 1.0)
	for i in m_old.units.size():
		for k in UNIT_FIELDS:
			_check(m_old.units[i].get(k) == m_new.units[i].get(k), "unit %d field %s step %d" % [i,k,step_n])
	for k in ["time","score","kills","ended","winner","end_reason","stock","levels","projectiles","items","oracles","ladders","hats"]:
		_check(_canon(m_old.get(k)) == _canon(m_new.get(k)), "sim field %s step %d" % [k,step_n])
	for i in m_old.gates.size():
		for k in ["hp","max_hp","broken","open"]:
			_check(m_old.gates[i][k] == m_new.gates[i][k], "gate " + k)
	for i in m_old.outposts.size():
		for k in ["owner","prog","stock","occ"]:
			_check(m_old.outposts[i].get(k) == m_new.outposts[i].get(k), "outpost " + k)
	for i in m_old.nodes.size():
		_check(m_old.nodes[i].amount == m_new.nodes[i].amount, "node amount")
	for i in m_old.stands.size():
		_check(m_old.stands[i].stock == m_new.stands[i].stock, "stand stock")
	_check(da.get("e", []) == db.get("e", []), "events mismatch")
	if exhaustive:
		for key in SLOW_FIELDS:
			_check(b.has(key), "full snapshot missing " + key)

func _edge_cases() -> void:
	var id: String = sim.units[0].id
	# Force unusual state into snapshots without modifying the gameplay used for measured runs.
	var task0: Dictionary = sim.units[0].task.duplicate(true)
	for task in [{}, {"kind":"gather","node":0,"t":0.375}, {"kind":"repair","gate":0,"t":0.8}]:
		sim.units[0].task = task
		var a := _full_old(sim, id, [])
		var b := New.snapshot(sim, id, [])
		_check(b.has("me") == not task.is_empty(), "private task omission")
		_apply_compare(a, b, id, true)
	sim.units[0].task = task0
	# Whirlwind boundary must preserve the ORIGINAL float32/int16 rounded decoder predicate.
	for left in [0.0,0.0049999999,0.005,0.0050000001,0.01,0.5,2.999]:
		sim.units[0].whirl_until = sim.time + left
		_apply_compare(_full_old(sim,id,[]),New.snapshot(sim,id,[]),id,true)
	sim.units[0].whirl_until = 0.0
	# Existing entities followed by empty arrays must clear, rather than persist.
	sim.projectiles = [{"id":1,"pos":Vector2(1,2),"vel":Vector2(3,4),"kind":"arrow"}]
	sim.items = [{"id":1,"kind":"log","pos":Vector2(2,3),"ang":0.1,"roll":0.2,"rax":0.3}]
	_apply_compare(_full_old(sim,id,[]),New.snapshot(sim,id,[]),id,true)
	sim.projectiles.clear()
	sim.items.clear()
	var e := [{"k":"proj_end","pid":1,"pos":Vector2(2,3)}]
	_apply_compare(_full_old(sim,id,e),New.snapshot(sim,id,e),id,true)
	_apply_compare(_full_old(sim,id,[]),New.snapshot(sim,id,[]),id,true)
	_check(m_new.items.is_empty() and m_new.projectiles.is_empty(), "entity clears")
	sim.ended = true
	sim.winner = 1
	sim.end_reason = "test"
	_apply_compare(_full_old(sim,id,[]),New.snapshot(sim,id,[]),id,true)
	_check(m_new.ended and m_new.winner == 1 and m_new.end_reason == "test", "match ending")
	sim.ended = false
	sim.winner = -1
	sim.end_reason = ""
	_apply_compare(_full_old(sim,id,[]),New.snapshot(sim,id,[]),id,true)
	_check(not m_new.ended and m_new.winner == -1 and m_new.end_reason == "", "normal end fallback")
	# A full late-join unicast must not swallow updates owed to existing connections.
	New.snapshot(sim,"",[])
	var before_n: int = New._slow_n
	var before_hash: Dictionary = New._slow_hash.duplicate()
	sim.stock[0].wood += 7
	sim.score[0] += 1
	sim.kills[0] += 1
	sim.oracles[0].weight += 1
	var joining := New.snapshot(sim,id,[])
	_check(New._slow_n==before_n and New._slow_hash==before_hash,"join consumed shared cache")
	for key in SLOW_FIELDS:
		_check(joining.has(key),"joining missing "+key)
	var dirty := New.snapshot(sim,"",[])
	for key in ["st","sc","k","o"]:
		_check(dirty.has(key),"join swallowed dirty "+key)
	_apply_compare(_full_old(sim,id,[]),New.for_player(dirty,sim,id),id)
	# Reset all test-induced snapshot state before measured deterministic gameplay.
	_start_seed()

func _measure(a: Dictionary, b: Dictionary, id: String) -> void:
	var tasks := []
	for u in sim.units:
		tasks.append(u.task.duplicate(true))
	if corpus != null:
		var fixture := var_to_bytes({"old":a,"new":b,"tasks":tasks})
		corpus.store_32(fixture.size())
		corpus.store_buffer(fixture)
	var t := Time.get_ticks_usec()
	var ba := Old.encode(Old.for_player(a,sim,id),true)
	var dt := Time.get_ticks_usec()-t
	old_encode_us += dt
	old_times.append(dt)
	t = Time.get_ticks_usec()
	var bb := New.encode(New.for_player(b,sim,id),true)
	dt = Time.get_ticks_usec()-t
	new_encode_us += dt
	new_times.append(dt)
	old_bytes += ba.size()
	new_bytes += bb.size()
	raw_old_bytes += var_to_bytes(Old.for_player(a,sim,id)).size()
	raw_new_bytes += var_to_bytes(New.for_player(b,sim,id)).size()
	packet_min = mini(packet_min, bb.size())
	packet_max = maxi(packet_max, bb.size())
	for e in a.get("e", []):
		coverage[e.get("k","")] = int(coverage.get(e.get("k",""),0)) + 1
	# Compare actually encoded packets; do not re-encode for the common path.
	var da := Old.decode(ba)
	var db := Old.decode(bb)
	Old.apply(m_old,da,id,false)
	Old.apply(m_new,db,id,false)
	Old.interpolate(m_old,1.0)
	Old.interpolate(m_new,1.0)
	for i in m_old.units.size():
		for k in UNIT_FIELDS:
			_check(m_old.units[i].get(k)==m_new.units[i].get(k),"unit %d field %s step %d" % [i,k,step_n])
	for k in ["time","score","kills","ended","winner","end_reason","stock","levels","projectiles","items","oracles","ladders","hats"]:
		_check(_canon(m_old.get(k))==_canon(m_new.get(k)),"sim "+k+" step "+str(step_n))
	for i in m_old.gates.size():
		for k in ["hp","max_hp","broken","open"]:
			_check(m_old.gates[i][k]==m_new.gates[i][k],"gate "+k)
	for i in m_old.outposts.size():
		for k in ["owner","prog","stock","occ"]:
			_check(m_old.outposts[i].get(k)==m_new.outposts[i].get(k),"outpost "+k)
	for i in m_old.nodes.size():
		_check(m_old.nodes[i].amount==m_new.nodes[i].amount,"node")
	for i in m_old.stands.size():
		_check(m_old.stands[i].stock==m_new.stands[i].stock,"stock")
	_check(da.get("e",[])==db.get("e",[]),"event")
	if snaps % 15 == 0:
		t = Time.get_ticks_usec()
		for u in sim.units:
			Old.encode(Old.for_player(a,sim,u.id),true)
		old_broadcast_us += Time.get_ticks_usec()-t
		t = Time.get_ticks_usec()
		var shared := New.encode(b,true)
		for u in sim.units:
			var personalized := New.for_player(b,sim,u.id)
			if personalized.has("me"):
				New.encode(personalized,true)
				private_count += 1
		new_broadcast_us += Time.get_ticks_usec()-t
		broadcast_n += 1
	snaps += 1

func _process(_delta: float) -> bool:
	# Four fixed simulation ticks per rendered process frame, capped at 20 process frames/s.
	for unused in 4:
		sim.step(Sim.TICK)
		pending.append_array(sim.drain_events())
		step_n += 1
		if step_n % 600 == 0:
			print("BENCH_PROGRESS level=%d seed=%d step=%d errors=%d" % [level,SEEDS[seed_index],step_n,errors])
		if step_n % 2 == 0:
			var a := Old.snapshot(sim,"",pending)
			var b := New.snapshot(sim,"",pending)
			_measure(a,b,sim.units[0].id)
			pending=[]
			# Late joins should immediately see every slow field even between periodic refreshes.
			if step_n % 600 == 100:
				_apply_compare(_full_old(sim,sim.units[0].id,[]),New.snapshot(sim,sim.units[0].id,[]),sim.units[0].id,true)
		if step_n >= steps_limit:
			print("BENCH_SEED_DONE level=%d seed=%d errors=%d simtime=%.3f ended=%s" % [level,SEEDS[seed_index],errors,sim.time,sim.ended])
			seed_index += 1
			if seed_index >= SEEDS.size():
				_finish()
				return false
			_start_seed()
	return false

func _finish() -> void:
	old_times.sort()
	new_times.sort()
	var results := {"level":level,"seeds":SEEDS,"sim_seconds":float(steps_limit*SEEDS.size())/30.0,"snapshots":snaps,"errors":errors,
		"baseline_bytes":old_bytes,"candidate_bytes":new_bytes,"baseline_MB_hour":float(old_bytes)/snaps*15.0*3600.0/1000000.0,
		"candidate_MB_hour":float(new_bytes)/snaps*15.0*3600.0/1000000.0,"saving_pct_same_level":100.0*(1.0-float(new_bytes)/old_bytes),
		"baseline_encode_us_avg":float(old_encode_us)/snaps,"candidate_encode_us_avg":float(new_encode_us)/snaps,
		"baseline_encode_us_p99":old_times[int(old_times.size()*0.99)],"candidate_encode_us_p99":new_times[int(new_times.size()*0.99)],
		"baseline_broadcast_us_avg":float(old_broadcast_us)/broadcast_n,"candidate_broadcast_us_avg":float(new_broadcast_us)/broadcast_n,
		"broadcast_samples":broadcast_n,"private_tasks_per_broadcast_avg":float(private_count)/broadcast_n,
		"candidate_packet_min":packet_min,"candidate_packet_max":packet_max,"raw_baseline_bytes":raw_old_bytes,"raw_candidate_bytes":raw_new_bytes,
		"wall_seconds":float(Time.get_ticks_usec()-start_us)/1000000.0,"events":coverage}
	if corpus != null:
		corpus.close()
	var result_json := JSON.stringify(results)
	print("BENCH_RESULT " + result_json)
	if benchmark:
		var f := FileAccess.open("res://bench-level-%d.json" % level,FileAccess.WRITE)
		f.store_string(result_json+"\n")
	print("SIEGE_BANDWIDTH_%s seeds=%d ticks_per_seed=%d snapshots=%d errors=%d" % ["PASS" if errors==0 else "FAIL",SEEDS.size(),steps_limit,snaps,errors])
	quit(0 if errors==0 else 1)
