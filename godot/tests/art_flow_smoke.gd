extends SceneTree
var main
var checks: Array[String] = []

func _init() -> void:
    call_deferred("_run")

func _control(path: String) -> void:
    var request := HTTPRequest.new()
    root.add_child(request)
    assert(request.request("http://127.0.0.1:8852"+path) == OK)
    var response: Array = await request.request_completed
    assert(int(response[1]) == 200)
    request.queue_free()

func _run() -> void:
    main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    main.api.base_url = "http://127.0.0.1:8851"
    main.api.identity_path = "user://art_flow_local.json"
    main.api.player_id = ""
    main.api.token = ""
    await main._start_queue("Art UI Test")
    assert(main.screen == "queue")
    await main._cancel_queue()
    assert(main.screen == "home")
    checks.append("native queue / confirmed cancellation")
    await main._start_queue("Art UI Test")
    await _control("/advance?ms=20500")
    var state: Dictionary = await main.api.state()
    main._accept(state)
    assert(main.screen == "battle")
    await _control("/boost")
    state = await main.api.state()
    main._accept(state)
    await process_frame
    assert(main.board != null and not main.roll_button.disabled)
    checks.append("native battle scene and authoritative controls")
    await _control("/force-faces?faces=C,C,S")
    await main._roll()
    assert(main.dice.faces == ["C","C","S"])
    assert(not main.dice.pending and not main.busy)
    assert(not "{\"" in main.bank.text)
    checks.append("native roll / all faces / human-readable bank")
    await _control("/boost")
    main._accept(await main.api.state())
    await main._cast("bulwark")
    assert(main.board._effects.size() > 0)
    checks.append("confirmed native spell VFX")
    main._tower_map()
    assert(is_instance_valid(main.modal))
    await main._move_to(4)
    assert(int(main._me().tower) == 4 and main.modal == null)
    assert(main.board.pan == 0 and main.board._effects.is_empty())
    checks.append("tower selector / confirmed move / cleared VFX")
    await _control("/knockout?player="+main.api.player_id+"&ms=1500")
    main._accept(await main.api.state())
    assert(main.roll_button.disabled)
    await _control("/advance?ms=2000")
    main._accept(await main.api.state())
    assert(int(main._me().hp) > 0)
    checks.append("authoritative KO and confirmed respawn")
    await _control("/finish")
    state = await main.api.state()
    main._accept(state)
    assert(main.screen == "result")
    # Exercise the actual result-screen signal, not only the API method.
    for child in main.page.get_children():
        if child is Button and child.text == "CLAIM REWARD":
            child.pressed.emit()
    for _i in 80:
        await create_timer(0.05).timeout
        if main.status.text.begins_with("Rewards claimed"):
            break
    assert(main.status.text.begins_with("Rewards claimed"))
    for child in main.page.get_children():
        if child is Button and child.text == "PLAY AGAIN":
            assert(not child.disabled)
            child.pressed.emit()
            break
    assert(main.screen == "home")
    checks.append("native results / reward button / next-game button")
    await main._start_queue("Art UI Test")
    assert(main.screen == "queue")
    await main._cancel_queue()
    assert(main.screen == "home")
    checks.append("second native queue / cancellation")
    var report := {"checks":checks,"status":"PASS","local_harness_only":true,"no_physical_phone":true}
    FileAccess.open("res://reports/ART_FLOW_TEST.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
    print("ART_FLOW_PASS "+JSON.stringify(report))
    quit(0)
