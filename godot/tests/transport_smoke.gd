extends SceneTree
const ApiScript = preload("res://scripts/arena_api.gd")
var api

func _init():
    call_deferred("_run")

func _control(path: String) -> Dictionary:
    var h := HTTPRequest.new()
    get_root().add_child(h)
    var err := h.request("http://127.0.0.1:8852" + path)
    if err != OK:
        return {"error":err}
    var response: Array = await h.request_completed
    h.queue_free()
    return JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())

func _run():
    api = ApiScript.new()
    api.base_url = "http://127.0.0.1:8851"
    api.identity_path = "user://godot_m1_wire_local.json"
    get_root().add_child(api)
    await process_frame
    var session: Dictionary = await api.ensure_session("Godot Wire Smoke")
    assert(session.get("ok",false))
    var queued: Dictionary = await api.queue(0,0,["barrage","bulwark"])
    assert(queued.get("ok",false))
    await _control("/advance?ms=20500")
    var first: Dictionary = await api.state()
    assert(first.get("status","") == "battle")
    var after_first: Dictionary = api.wire.stats.duplicate(true)
    var url_after_first: String = api._make_url("/state",true,false)
    await _control("/advance?ms=500")
    var second: Dictionary = await api.state()
    assert(second.get("status","") == "battle")
    var after_second: Dictionary = api.wire.stats.duplicate(true)
    print("TRANSPORT first=%s second=%s cursor_url=%s" % [after_first,after_second,url_after_first])
    assert(int(after_first.full) >= 1)
    assert(int(after_second.delta) >= 1)
    await _control("/finish")
    await api.state()
    await api.claim(str(second.get("match",{}).get("id","")),"steel")
    print("TRANSPORT_SMOKE_PASS")
    quit(0)
