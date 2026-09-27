extends SceneTree
const Client=preload("res://scripts/full_client.gd")
var app
func _init()->void:call_deferred("_run")
func fw(n:=4)->void:
    for i in n:await process_frame
func _run()->void:
    var out:String=OS.get_environment("SHOT") if OS.get_environment("SHOT")!="" else "user://battle-shot.png"
    app=Client.new();app.autoload_network=false;app._save_path_override="user://dev-shot-"+str(Time.get_ticks_usec())+".json"
    app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(app);await process_frame
    app.save_store.memory_only=true;app.d.gold=8325;app.d.owned=[0,2,5]
    if OS.get_environment("SCALE")=="2":
        root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS;root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND;root.content_scale_size=Vector2i(420,936);root.size=Vector2i(840,1872)
    else:
        root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(420,936)
    await fw()
    app.start_local("raid" if OS.get_environment("KIND")=="raid" else "campaign");await fw(40)
    var mode:=OS.get_environment("MODE")
    if mode=="roll":
        app.api.local_engine.s.get("pendingGift",[]).clear()
        app._roll();await fw(50)
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(out)
    print("VP ",app.dice._viewport.size," board ",app.board.size, " cam ",app.dice._camera.position)
    app.api.local_engine.s.ended=true;app.api.leave_local();app.poll_timer.stop()
    quit()
