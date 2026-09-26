extends SceneTree

const ApiScript = preload("res://scripts/arena_api.gd")

var a
var b
var started_ms := Time.get_ticks_msec()
var rolls := [0,0]
var moves := [0,0]
var spells := [0,0]
var rallies := [0,0]
var ultimates := [0,0]
var kos_seen := [0,0]
var respawns_seen := [0,0]
var was_down := [false,false]

func _init() -> void:
    call_deferred("_run")

func _hero(api: Node, state: Dictionary) -> Dictionary:
    var snapshot: Dictionary = state.get("match",{})
    for h in snapshot.get("heroes",[]):
        if str(h.get("id","")) == api.player_id:
            return h
    return {}

func _safe_state(api: Node) -> Dictionary:
    var state := await api.state()
    if not state.get("ok",false):
        push_warning("state failed: " + str(state))
        await create_timer(0.75).timeout
    return state

func _maybe_act(api: Node, state: Dictionary, idx: int) -> Dictionary:
    if state.get("status","") != "battle":
        return state
    var snapshot: Dictionary = state.get("match",{})
    var hero := _hero(api,state)
    if hero.is_empty():
        return state
    var now := int(snapshot.get("now",0))
    var hp := int(hero.get("hp",0))
    if hp <= 0:
        if not was_down[idx]:
            kos_seen[idx] += 1
        was_down[idx] = true
        return state
    if was_down[idx]:
        respawns_seen[idx] += 1
        was_down[idx] = false
    if moves[idx] == 0 and now >= int(hero.get("moveAt",0)):
        var target := (int(hero.get("tower",0)) + 1) % 10
        var moved: Dictionary = await api.action("move",str(snapshot.get("id","")),{"tower":target})
        if moved.get("ok",false):
            moves[idx] += 1
            state = moved.get("state",state)
            hero = _hero(api,state)
            snapshot = state.get("match",snapshot)
            now = int(snapshot.get("now",now))
    if spells[idx] == 0 and int(hero.get("spell",0)) > 0 and now >= int(hero.get("spellAt",0)):
        var cast: Dictionary = await api.action("spell",str(snapshot.get("id","")),{"spell":"barrage"})
        if cast.get("ok",false):
            spells[idx] += 1
            state = cast.get("state",state)
            hero = _hero(api,state)
            snapshot = state.get("match",snapshot)
            now = int(snapshot.get("now",now))
    if rallies[idx] == 0 and int(hero.get("ralliesLeft",0)) > 0 and int(hero.get("focus",0)) >= 2 and now >= int(hero.get("rallyAt",0)):
        var rally: Dictionary = await api.action("rally",str(snapshot.get("id","")))
        if rally.get("ok",false):
            rallies[idx] += 1
            state = rally.get("state",state)
            hero = _hero(api,state)
            snapshot = state.get("match",snapshot)
            now = int(snapshot.get("now",now))
    if ultimates[idx] == 0 and int(hero.get("ult",0)) >= 100:
        var ultimate: Dictionary = await api.action("ultimate",str(snapshot.get("id","")))
        if ultimate.get("ok",false):
            ultimates[idx] += 1
            state = ultimate.get("state",state)
            hero = _hero(api,state)
            snapshot = state.get("match",snapshot)
            now = int(snapshot.get("now",now))
    if int(hero.get("focus",0)) >= 1 and now >= int(hero.get("rollAt",0)):
        var rolled: Dictionary = await api.action("roll",str(snapshot.get("id","")),{"mult":1,"allIn":false})
        if rolled.get("ok",false):
            rolls[idx] += 1
            state = rolled.get("state",state)
    return state

func _run() -> void:
    a = ApiScript.new()
    a.identity_path = "user://godot_m1_live_a.json"
    get_root().add_child(a)
    b = ApiScript.new()
    b.identity_path = "user://godot_m1_live_b.json"
    get_root().add_child(b)
    await process_frame
    var sa: Dictionary = await a.ensure_session("Godot M1 Live A")
    var sb: Dictionary = await b.ensure_session("Godot M1 Live B")
    if not sa.get("ok",false) or not sb.get("ok",false):
        push_error("SESSION_FAIL")
        quit(1)
        return
    var qa: Dictionary = await a.queue(0,0,["barrage","bulwark"])
    var qb: Dictionary = await b.queue(1,1,["barrage","surge"])
    if not qa.get("ok",false) or not qb.get("ok",false):
        push_error("QUEUE_FAIL " + str([qa,qb]))
        quit(2)
        return
    print("GODOT_LIVE queue_started A=%s B=%s" % [a.player_id,b.player_id])
    var state_a: Dictionary = qa
    var state_b: Dictionary = qb
    var room := ""
    var complete_a: Dictionary = {}
    var complete_b: Dictionary = {}
    while Time.get_ticks_msec() - started_ms < 345000:
        state_a = await _safe_state(a)
        state_b = await _safe_state(b)
        if state_a.get("status","") in ["battle","complete"] and state_b.get("status","") in ["battle","complete"]:
            var ra := str(state_a.get("match",{}).get("id",""))
            var rb := str(state_b.get("match",{}).get("id",""))
            if room == "":
                room = ra
                print("GODOT_LIVE room=%s search_seconds=%.2f" % [room,float(Time.get_ticks_msec()-started_ms)/1000.0])
            if ra != room or rb != room:
                push_error("ROOM_MISMATCH %s %s %s" % [room,ra,rb])
                quit(3)
                return
        if state_a.get("status","") == "complete":
            complete_a = state_a
        else:
            state_a = await _maybe_act(a,state_a,0)
        if state_b.get("status","") == "complete":
            complete_b = state_b
        else:
            state_b = await _maybe_act(b,state_b,1)
        if not complete_a.is_empty() and not complete_b.is_empty():
            break
        await create_timer(0.55).timeout
    if complete_a.is_empty() or complete_b.is_empty():
        push_error("MATCH_TIMEOUT")
        quit(4)
        return
    var room_a := str(complete_a.get("match",{}).get("id",""))
    var room_b := str(complete_b.get("match",{}).get("id",""))
    if room_a != room_b or room_a != room:
        push_error("COMPLETE_ROOM_MISMATCH")
        quit(5)
        return
    var ca: Dictionary = await a.claim(room,"steel")
    var cb: Dictionary = await b.claim(room,"arcane")
    if not ca.get("ok",false) or not cb.get("ok",false):
        push_error("CLAIM_FAIL " + str([ca,cb]))
        quit(6)
        return
    var q2a: Dictionary = await a.queue(0,0,["barrage","bulwark"])
    var q2b: Dictionary = await b.queue(1,1,["barrage","surge"])
    if not q2a.get("ok",false) or not q2b.get("ok",false):
        push_error("REQUEUE_FAIL")
        quit(7)
        return
    await a.cancel()
    await b.cancel()
    var report := {
        "status":"PASS",
        "room":room,
        "elapsed_s":float(Time.get_ticks_msec()-started_ms)/1000.0,
        "rolls":rolls,
        "moves":moves,
        "spells":spells,
        "rallies":rallies,
        "ultimates":ultimates,
        "kos_seen":kos_seen,
        "respawns_seen":respawns_seen,
        "a_transport":a.wire.stats,
        "b_transport":b.wire.stats,
        "response_bytes_total":a.bytes_received+b.bytes_received,
        "requests_total":a.request_count+b.request_count,
        "score_a":complete_a.get("result",{}).get("score",[]),
        "score_b":complete_b.get("result",{}).get("score",[])
    }
    print("GODOT_LIVE_PASS " + JSON.stringify(report))
    quit(0)
