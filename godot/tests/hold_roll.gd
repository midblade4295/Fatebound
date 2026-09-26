extends SceneTree
const Client=preload("res://scripts/full_client.gd")
func _init()->void:call_deferred("_run")
func _run()->void:
    var app=Client.new();app.autoload_network=false;app._save_path_override="user://hold-"+str(Time.get_ticks_usec())+".json"
    root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);await process_frame
    app.save_store.memory_only=true;app.start_local("campaign")
    app.api.local_engine.forced_faces=["G","G","G"]
    for i in 6:await process_frame
    var button:Button=app.roll_button
    var pos:=button.get_global_rect().get_center()
    var move:=InputEventMouseMotion.new();move.position=pos;Input.parse_input_event(move)
    var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.position=pos;Input.parse_input_event(down)
    await create_timer(2.7).timeout
    var up:=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.pressed=false;up.position=pos;Input.parse_input_event(up)
    await create_timer(0.2).timeout
    var at_release:int=app._me().get("rolls",0)
    await create_timer(2.5).timeout
    var after:int=app._me().get("rolls",0)
    var report:Dictionary={"status":"PASS" if at_release>0 and after==at_release and not app.auto_running else "FAIL","at_release":at_release,"after_wait":after,"auto_running":app.auto_running,"native_input_events":true}
    print("HOLD_ROLL ",JSON.stringify(report))
    FileAccess.open("res://reports/full-port/hold-roll.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
    app.queue_free();await process_frame;await process_frame
    quit(0 if report.status=="PASS" else 1)
