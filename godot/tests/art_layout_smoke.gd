extends SceneTree
var main
var report: Array = []
var failures: Array = []

func _init() -> void:
    call_deferred("_run")

func _check_controls(node: Node, bounds: Rect2, note: String) -> void:
    if node is BaseButton and (node as Control).is_visible_in_tree():
        var rect: Rect2 = node.get_global_rect()
        if not bounds.grow(1.5).encloses(rect):
            failures.append({"where":note,"button":node.text,"rect":str(rect),"bounds":str(bounds)})
    for child in node.get_children():
        _check_controls(child,bounds,note)

func _run() -> void:
    var scene: PackedScene = load("res://scenes/Main.tscn")
    main = scene.instantiate()
    root.add_child(main)
    await process_frame
    main.api.player_id = "art-fixture-0"
    var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/art-fixture.json"))
    var resolutions := [Vector2i(360,640),Vector2i(390,844),Vector2i(420,936),Vector2i(412,915),Vector2i(600,960),Vector2i(768,1024)]
    for resolution in resolutions:
        root.content_scale_size = Vector2i.ZERO
        root.size = resolution
        await process_frame
        main._show_home()
        await create_timer(0.08).timeout
        _check_controls(main.ui_root,Rect2(Vector2.ZERO,Vector2(resolution)),"home "+str(resolution))
        main._accept(fixture.duplicate(true))
        await create_timer(0.16).timeout
        var bounds := Rect2(Vector2.ZERO,Vector2(resolution))
        _check_controls(main.ui_root,bounds,"battle "+str(resolution))
        assert(main.board.size.y > 140, "Battlefield collapsed")
        assert(main.roll_button.get_global_rect().end.x <= resolution.x, "ROLL clipped")
        assert(main.rally_button.get_global_rect().end.x <= resolution.x,"Rally clipped")
        assert(main.ult_button.get_global_rect().end.y <= resolution.y,"Ultimate clipped")
        assert(main.dice.faces == ["H","C","C"])
        report.append({"resolution":str(resolution),"battlefield":str(main.board.size),"roll":str(main.roll_button.get_global_rect()),"rally":str(main.rally_button.get_global_rect())})
    root.size = Vector2i(420,936)
    await process_frame
    await create_timer(0.3).timeout
    if DisplayServer.get_name() != "headless":
        await RenderingServer.frame_post_draw
        assert(root.get_texture().get_image().save_png("res://reports/native-art-battle.png") == OK)
    var ko := fixture.duplicate(true)
    ko.match.revision = 20
    ko.match.heroes[0].hp = 0
    ko.match.heroes[0].downUntil = ko.serverNow-1000
    main._accept(ko)
    await process_frame
    assert(main.roll_button.disabled and main.roll_button.text == "RESPAWNING…")
    var stale := fixture.duplicate(true)
    stale.match.revision = 19
    main._accept(stale)
    assert(main._me().hp == 0, "Stale response resurrected hero")
    main._more()
    await create_timer(0.15).timeout
    assert(is_instance_valid(main.modal))
    main.modal.queue_free()
    main.modal = null
    var crowd := fixture.duplicate(true)
    crowd.match.revision = 21
    for h in crowd.match.heroes:
        h.tower = 8
    main._accept(crowd)
    await create_timer(0.15).timeout
    assert(main.board._pan_limit() > 0)
    main.board.pan = main.board._pan_limit()
    await create_timer(0.15).timeout
    assert(main.board.clip_contents)
    main.board.confirm_event({"type":"spell","actor":"art-fixture-0","tower":8,"spell":"barrage"})
    await create_timer(0.15).timeout
    assert(main.board._effects.size() == 1)
    crowd.match.revision = 22
    crowd.match.heroes[0].tower = 7
    main._accept(crowd)
    assert(main.board.pan == 0 and main.board._effects.is_empty())
    var out := {"layouts":report,"failures":failures,"zero_hp_waits_for_server":true,"stale_state_ignored":true,"crowd_panning":true,"spell_clipped_and_cleared_on_move":true,"physical_android_tested":false,"renderer":DisplayServer.get_name()}
    FileAccess.open("res://reports/ART_LAYOUT_TEST.json",FileAccess.WRITE).store_string(JSON.stringify(out,"  ")+"\n")
    if failures.size() > 0:
        push_error("LAYOUT_FAILURES "+JSON.stringify(failures))
        quit(1)
    else:
        print("ART_LAYOUT_PASS "+JSON.stringify(out))
        quit(0)
