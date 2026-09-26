extends SceneTree

const ApiScript = preload("res://scripts/arena_api.gd")

var api

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    api = ApiScript.new()
    get_root().add_child(api)
    await process_frame
    var session: Dictionary = await api.ensure_session("Godot M1 Smoke")
    if not session.get("ok",false):
        push_error("SESSION_FAIL " + str(session))
        quit(1)
        return
    var queued: Dictionary = await api.queue(0,0,["barrage","bulwark"])
    if not queued.get("ok",false) or queued.get("status","") != "searching":
        push_error("QUEUE_FAIL " + str(queued))
        quit(2)
        return
    if int(queued.get("capacity",20)) != 20 or int(queued.get("waitMs",20000)) != 20000:
        push_error("QUEUE_RULE_MISMATCH " + str(queued))
        quit(3)
        return
    var cancelled: Dictionary = await api.cancel()
    if not cancelled.get("ok",false) or cancelled.get("status","") != "idle":
        push_error("CANCEL_FAIL " + str(cancelled))
        quit(4)
        return
    print("API_SMOKE_PASS player=%s requests=%d bytes=%d" % [api.player_id,api.request_count,api.bytes_received])
    quit(0)
