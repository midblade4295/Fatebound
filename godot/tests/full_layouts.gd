extends SceneTree
const Client=preload("res://scripts/full_client.gd")
var app
var failures:Array=[]
var layouts:Array=[]
func _init()->void:call_deferred("_run")
func frame_wait(n:=4)->void:
    for i in n:await process_frame
func check_shell(route:String,resolution:Vector2i)->void:
    var bounds:=Rect2(Vector2.ZERO,Vector2(resolution))
    var minwidth:float=app.body.get_combined_minimum_size().x
    var available:float=app.scroller.size.x
    if minwidth>available+1:failures.append({"route":route,"size":str(resolution),"bodyMinWidth":minwidth,"available":available})
    check_labels(app.body,route,resolution)
    for child in app.page.get_children():
        if child is HBoxContainer:
            for control in child.get_children():
                if control is Button and control.is_visible_in_tree() and not bounds.grow(1).encloses(control.get_global_rect()):failures.append({"route":route,"size":str(resolution),"control":control.text,"rect":str(control.get_global_rect())})
func check_labels(node:Node,route:String,resolution:Vector2i)->void:
    if node is Label and node.is_visible_in_tree() and not node.text.is_empty():
        if node.size.y<node.get_line_height()-1:
            failures.append({"route":route,"size":str(resolution),"collapsedLabel":node.text.left(60),"height":node.size.y})
    for child in node.get_children():check_labels(child,route,resolution)
func screenshot(name:String)->void:
    await RenderingServer.frame_post_draw
    var image:=root.get_texture().get_image()
    assert(image.save_png("res://reports/full-port/screens/"+name+".png")==OK)
func _run()->void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/full-port/screens"))
    app=Client.new();app.autoload_network=false;app._save_path_override="user://layout-full-"+str(Time.get_ticks_usec())+".json"
    app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(app);await process_frame
    app.save_store.memory_only=true;app.d.gold=8325;app.d.tokens=46;app.d.shards={"steel":34,"arcane":18,"fletch":9};app.d.season.pts=275
    app.d.owned=[0,2,5];app.d.tiers={"0":1};app.d.rollTrack.ready=1;app.d.rollTrack.gold=200;app.d.rollTrack.shards.steel=1
    var sizes:=[Vector2i(360,640),Vector2i(390,844),Vector2i(420,936),Vector2i(412,915),Vector2i(600,960),Vector2i(768,1024)]
    for resolution in sizes:
        root.content_scale_size=Vector2i.ZERO;root.size=resolution
        await frame_wait()
        for route in ["home","hero","shop","guild","friends","season","quests","stats","prepare","raid","chests","settings"]:
            app.pages.show(route);await frame_wait()
            check_shell(route,resolution)
            if resolution==Vector2i(420,936) and route in ["home","hero","guild","raid","season"]:await screenshot(route)
        app.start_local("campaign");await frame_wait()
        var board_height:float=app.board.size.y
        for button in [app.roll_button,app.rally_button,app.ult_button,app.tower_title]:
            if not Rect2(Vector2.ZERO,Vector2(resolution)).grow(1).encloses(button.get_global_rect()):failures.append({"route":"battle","size":str(resolution),"control":button.text})
        if board_height<50:failures.append({"route":"battle","size":str(resolution),"boardHeight":board_height})
        layouts.append({"size":str(resolution),"menuPages":12,"battlefieldHeight":board_height})
        if resolution==Vector2i(420,936):await screenshot("solo-battle")
        app.api.local_engine.s.ended=true
        app.api.leave_local();app.poll_timer.stop();app._show_home()
    root.size=Vector2i(420,936);await frame_wait();app.pages.show("home");await frame_wait()
    # Real pointer events on a native navigation button, not just signal invocation.
    var hero:Button=app.ui_root.find_child("nav_hero",true,false)
    var position:=hero.get_global_rect().get_center()
    var motion:=InputEventMouseMotion.new();motion.position=position;Input.parse_input_event(motion)
    var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.position=position;Input.parse_input_event(down)
    await process_frame
    var up:=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.pressed=false;up.position=position;Input.parse_input_event(up)
    await frame_wait()
    if app.screen!="hero":failures.append({"route":"pointer nav","screen":app.screen})
    var result:Dictionary={"layouts":layouts,"failures":failures,"menuLayoutCombinations":sizes.size()*12,"native_mouse_navigation":app.screen=="hero","renderer":RenderingServer.get_video_adapter_name(),"physical_phone":false}
    FileAccess.open("res://reports/full-port/layouts.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  ")+"\n")
    print("FULL_LAYOUTS ",JSON.stringify(result))
    app.queue_free();await frame_wait();quit(0 if failures.is_empty() else 1)
