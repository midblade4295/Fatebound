extends SceneTree
const Client=preload("res://scripts/full_client.gd")
func _init()->void:call_deferred("_run")
func count(n:Node)->int:
    var c:=1 if (n is GPUParticles2D or n is GPUParticles3D) else 0
    for ch in n.get_children():c+=count(ch)
    return c
func _run()->void:
    var app=Client.new();app.autoload_network=false;app._save_path_override="user://fx-"+str(Time.get_ticks_usec())+".json"
    app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(app);await process_frame
    app.save_store.memory_only=true;root.size=Vector2i(420,936)
    app.pages.show("home");for i in 20:await process_frame
    var on:=count(app)
    app.d.native.settings.lowFx=true;app.apply_settings();app.pages.show("home");for i in 20:await process_frame
    var off:=count(app)
    print("FX_CHECK particles_normal=",on," particles_low_quality=",off)
    quit(0 if on>0 and off==0 else 1)
