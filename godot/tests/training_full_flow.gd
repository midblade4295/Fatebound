extends SceneTree
const Client=preload("res://scripts/full_client.gd")
var app
var errors:Array=[]
var visited:Array=[]
func _init()->void:call_deferred("_run")
func find_action(key:String,node:Node=null)->Button:
    if node==null:node=app.ui_root
    if node is Button and str(node.get_meta("action_key",""))==key:return node
    for child in node.get_children():
        var found:=find_action(key,child)
        if found!=null:return found
    return null
func _run()->void:
    app=Client.new();app.autoload_network=false;app._save_path_override="user://training-full-"+str(Time.get_ticks_usec())+".json"
    app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(app);await process_frame
    app.save_store.memory_only=true
    var before:Dictionary=app.progression.d.duplicate(true)
    app.begin_training();await process_frame
    var loops:=0
    while app.trainer.active and loops<60:
        loops+=1
        var step:=int(app.trainer.index)
        if not visited.has(step):visited.append(step)
        var lesson:Dictionary=app.trainer.lesson()
        var action:=str(lesson.get("action",""))
        print("TRAINING_STEP ",step," ",action," screen=",app.screen)
        if action.is_empty():
            var next:=find_action("coach_next")
            if next==null:errors.append("missing next on step"+str(step));break
            next.pressed.emit()
        elif action in ["roll","giftRoll"]:
            if app.screen!="battle":errors.append("roll outside battle"+str(step));break
            # Exercise the complete UI method, including the real timed critical minigame.
            await app._roll()
        elif action=="mult":
            app.mult_select.select(1);app.mult_select.item_selected.emit(1)
        elif action=="gift":
            var choices:Array=app.api.local_engine.s.get("pendingGift",[])
            var selected:=-1
            for i in choices.size():
                if choices[i].get("bonus",false):selected=i
            if selected<0:errors.append("no bonus gift in lesson13");break
            await app._choose_gift(selected)
        elif action=="giftOpen":app.show_stored_attacks()
        elif action=="giftUse":await app._use_stored(0)
        elif action=="ult":await app._do_action("ultimate")
        elif action=="map":app._tower_map()
        elif action=="tower":await app._move_to(7)
        elif action=="rally":await app._do_action("rally")
        elif action=="home":app._go("home")
        elif action in ["hero","visitGuild","visitFriends","visitShop"]:
            app._go({"hero":"hero","visitGuild":"guild","visitFriends":"friends","visitShop":"shop"}[action])
        elif action=="buyEnergy":
            var button:=find_action("training_flask")
            if button==null or button.disabled:errors.append("training purchase not usable");break
            button.pressed.emit()
        else:errors.append("unsupported lesson action "+action);break
        for _i in 4:await process_frame
        if app.trainer.active and int(app.trainer.index)==step:
            errors.append("lesson did not advance "+str(step));break
    var after:Dictionary=app.progression.d.duplicate(true)
    for key in ["tutorial","tutorialBattle"]:before.erase(key);after.erase(key)
    if before!=after:errors.append("training changed real progression outside tutorial flags")
    if app.trainer.active or visited.size()!=33:errors.append("not all33 lessons completed")
    if not app.progression.d.tutorialBattle.done:errors.append("completion not persisted")
    var result:Dictionary={"status":"PASS" if errors.is_empty() else "FAIL","visited":visited,"errors":errors,"real_resources_unchanged":before==after,"native_ui":true}
    FileAccess.open("res://reports/full-port/training-flow.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  ")+"\n")
    print("TRAINING_FLOW ",JSON.stringify(result))
    app.queue_free();await process_frame;await process_frame
    quit(0 if errors.is_empty() else 1)
