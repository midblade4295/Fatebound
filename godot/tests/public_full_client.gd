extends SceneTree
const Client=preload("res://scripts/full_client.gd")
var a
var b
var started:=Time.get_ticks_msec()
var battle_at:=0
var room:=""
var rolls:=[0,0]
var spells:=[0,0]
var ultimates:=[0,0]
var moves:=[0,0]
var knockouts:=[0,0]
var respawns:=[0,0]
var down:=[false,false]
var final_states:Array=[{},{}]
var errors:Array=[]
func _init()->void:call_deferred("_run")
func find_button(client,key:String,node:Node=null)->Button:
    if node==null:node=client.ui_root
    if node is Button and str(node.get_meta("action_key",""))==key:return node
    for child in node.get_children():
        var found:=find_button(client,key,child)
        if found!=null:return found
    return null
func make_client(suffix:String):
    var client=Client.new();client.autoload_network=false
    client._save_path_override="user://public-full-"+suffix+"-"+str(Time.get_ticks_usec())+".json"
    root.add_child(client);client.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    client.api.player_id="";client.api.token="";client.api.online_id=""
    client.api.identity_path="user://public-full-identity-"+suffix+"-"+str(Time.get_ticks_usec())+".json"
    client.progression.d.native.name="Native 0.3 QA "+suffix
    client.progression.d.adventure.loadout=["barrage","bulwark"]
    client.progression.store.commit()
    return client
func maybe_act(client,index:int)->void:
    if client.screen!="battle" or client.busy:return
    var h:Dictionary=client._me()
    if h.is_empty():return
    if int(h.hp)<=0:
        if not down[index]:knockouts[index]+=1
        down[index]=true
        if not client.roll_button.disabled:errors.append("KO ROLL incorrectly enabled")
        return
    if down[index]:respawns[index]+=1;down[index]=false
    var now:float=client._server_now()
    if moves[index]==0 and now>=int(h.get("moveAt",0)):
        await client._move_to((int(h.tower)+1)%10)
        if client.api.last_action_answer.get("ok",false):moves[index]+=1
        return
    if int(h.ult)>=100 and ultimates[index]==0:
        await client._do_action("ultimate")
        if client.api.last_action_answer.get("ok",false):ultimates[index]+=1
        return
    if int(h.spell)>0 and now>=int(h.spellAt) and spells[index]<3:
        await client._cast("barrage" if spells[index]%2==0 else "bulwark")
        if client.api.last_action_answer.get("ok",false):spells[index]+=1
        return
    if not client.roll_button.disabled:
        await client._roll()
        if client.api.last_action_answer.get("ok",false):rolls[index]+=1
func _run()->void:
    a=make_client("A");b=make_client("B")
    await process_frame
    var queue_at:=Time.get_ticks_msec()
    await a.start_online();await b.start_online()
    if a.screen!="queue" or b.screen!="queue":push_error("PUBLIC_NATIVE_QUEUE_FAILED");quit(2);return
    print("PUBLIC_NATIVE queue started")
    while Time.get_ticks_msec()-started<420000:
        if a.screen=="battle" and b.screen=="battle" and room.is_empty():
            room=str(a.current_match_id);battle_at=Time.get_ticks_msec()
            if b.current_match_id!=room:errors.append("Clients entered different rooms")
            if battle_at-queue_at<19900:errors.append("Queue ended too early")
            print("PUBLIC_NATIVE shared room after ",(battle_at-queue_at)/1000.0,"s")
        if a.screen=="result":final_states[0]=a.latest_state.duplicate(true)
        else:await maybe_act(a,0)
        if b.screen=="result":final_states[1]=b.latest_state.duplicate(true)
        else:await maybe_act(b,1)
        if not final_states[0].is_empty() and not final_states[1].is_empty():break
        await create_timer(0.18).timeout
    if final_states[0].is_empty() or final_states[1].is_empty():errors.append("Native full match timed out")
    else:
        var sa:Array=final_states[0].result.get("score",[]);var sb:Array=final_states[1].result.get("score",[])
        if sa!=sb:errors.append("Final crowns disagree")
        print("PUBLIC_NATIVE match complete score=",sa," rolls=",rolls)
    var persisted:Array=[]
    for client in [a,b]:
        var claim:=find_button(client,"claim_rewards")
        if claim==null:errors.append("Missing native reward button");continue
        claim.pressed.emit()
        for _i in 200:
            await create_timer(0.05).timeout
            if client.pages.result_claimed:break
        if not client.pages.result_claimed:errors.append("Native claim did not finish");continue
        var before:Dictionary=client.progression.d.duplicate(true)
        var history:Dictionary=await client.api.sync_receipts()
        if not history.get("ok",false):errors.append("Receipt history recovery unavailable")
        if int(client.progression.d.gold)!=int(before.gold) or int(client.progression.d.xp)!=int(before.xp):errors.append("Reward history duplicated progression")
        var replay:Dictionary=await client.api.claim(room,"fletch")
        if not replay.get("ok",false) or int(client.progression.d.gold)!=int(before.gold):errors.append("Duplicate claim was not idempotent")
        var on_disk=JSON.parse_string(FileAccess.get_file_as_string(client.save_store.path))
        if not on_disk is Dictionary or not on_disk.adventure.receipts.has(room):errors.append("Receipt missing after saved-file readback")
        persisted.append({"gold":client.progression.d.gold,"xp":client.progression.d.xp,"receipt_count":client.progression.d.adventure.receipts.size()})
        var home:=find_button(client,"result_home")
        if home==null:errors.append("Missing Home result button")
        else:home.pressed.emit()
    if a.screen=="home" and b.screen=="home":
        await a.start_online();await b.start_online()
        if a.screen!="queue" or b.screen!="queue":errors.append("Second native queue failed")
        await a._cancel_queue();await b._cancel_queue()
        if a.screen!="home" or b.screen!="home":errors.append("Second queue did not cancel cleanly")
    var report:Dictionary={"status":"PASS" if errors.is_empty() else "FAIL","errors":errors,"room":room,"elapsed_s":(Time.get_ticks_msec()-started)/1000.0,"rolls":rolls,"moves":moves,"spells":spells,"ultimates":ultimates,"knockouts_seen":knockouts,"respawns_seen":respawns,"score":final_states[0].get("result",{}).get("score",[]),"a_wire":a.api.wire.stats,"b_wire":b.api.wire.stats,"decoded_json_bytes":a.api.bytes_received+b.api.bytes_received,"saved_wallets":persisted,"physical_phone":false,"real_clock":true,"test_control_endpoints_used":false}
    FileAccess.open("res://reports/full-port/public-native-match.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
    print("PUBLIC_NATIVE_FINAL ",JSON.stringify(report))
    a.queue_free();b.queue_free();await process_frame;await process_frame
    quit(0 if errors.is_empty() else 1)
