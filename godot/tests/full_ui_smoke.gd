extends SceneTree
const Client=preload("res://scripts/full_client.gd")
var app
var checks:Array[String]=[]
var errors:Array[String]=[]
func _init()->void:call_deferred("_run")
func check(okay:bool,description:String)->void:
    if okay:checks.append(description)
    else:errors.append(description);push_error(description)
func find_button(key:String,node:Node=null)->Button:
    if node==null:node=app.ui_root
    if node is Button and str(node.get_meta("action_key",""))==key:return node
    for child in node.get_children():
        var result:=find_button(key,child)
        if result!=null:return result
    return null
func click(key:String)->bool:
    var b:=find_button(key)
    if b==null or b.disabled:errors.append("missing/disabled control "+key);return false
    b.pressed.emit()
    await process_frame
    return true
func wait_frames(count:=3)->void:
    for i in count:await process_frame
func _run()->void:
    app=Client.new();app.autoload_network=false;app._save_path_override="user://ui-full-"+str(Time.get_ticks_usec())+".json"
    app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_child(app);await process_frame
    app.save_store.memory_only=true
    app.api.base_url="http://127.0.0.1:8851";app.api.online_id="";app.api.player_id="";app.api.token="";app.api.identity_path="user://ui-full-local-identity.json"
    app.progression.d.gold=100000;app.progression.d.tokens=1000;app.progression.d.shards={"steel":500,"arcane":500,"fletch":500};app.progression.d.season.pts=1000
    for route in ["home","hero","shop","season","quests","stats","prepare","raid","chests","guild","friends","settings"]:
        app.pages.show(route);await wait_frames()
        check(app.screen==route,"native "+route+" page mounts")
    app.pages.show("hero");await wait_frames()
    var old_gold:=int(app.d.gold)
    await click("buy_weapon_2")
    check(app.d.owned.has(2) and int(app.d.gold)==old_gold-500,"armory buy button debits source price")
    await click("forge_2")
    check(int(app.d.tiers.get("2",0))==1,"armory forge button upgrades real save")
    app.pages.show("shop");await wait_frames();await click("relic_atk")
    check(int(app.d.relics.atk)==1,"shop relic button changes real modifier")
    app.pages.show("season");await wait_frames();await click("premium");await click("season_free_0")
    check(app.d.season.premium and app.d.season.free.has(0),"pass premium/free actual button paths")
    app.pages.show("guild");await wait_frames();await click("guild_tab_chat")
    var input:TextEdit=app.pages.chat_edit;var identity:=input.get_instance_id()
    input.text="abcd";input.set_caret_column(2);input.insert_text_at_caret("X")
    check(input.text=="abXcd","guild caret inserts forward in the middle")
    var caret:=input.get_caret_column();await create_timer(0.75).timeout
    check(app.pages.chat_edit.get_instance_id()==identity and input.get_caret_column()==caret,"guild refresh/save never replaces composer or caret")
    await click("guild_chat_send")
    check(app.d.native.chat.size()==1 and app.d.native.chat[0].text=="You: abXcd" and input.text=="","guild send appends one message without remount")
    app.pages.show("home");app.pages.show("guild");await wait_frames()
    check(app.d.native.chat.size()==1,"guild message survives navigation")
    app.pages.show("chests");app.d.rollTrack.ready=1;app.d.rollTrack.gold=200;app.d.rollTrack.shards.steel=1;app.pages.show("chests");await wait_frames()
    old_gold=int(app.d.gold);await click("claim_roll_chests")
    check(int(app.d.gold)==old_gold+200 and int(app.d.rollTrack.ready)==0,"native saved-chest claim button exactly once")
    app.pages.show("prepare");await wait_frames();await click("solo_start")
    check(app.screen=="battle" and app.latest.heroes.size()==40,"native solo 40-fighter battle")
    app.api.local_engine.forced_faces=["G","G","G"];app.api.local_engine.own().focus=8
    app._accept(await app.api.state());await wait_frames()
    old_gold=int(app.d.gold);await app._roll()
    check(int(app.d.gold)>=old_gold+200 and app.dice.faces==["G","G","G"],"solo roll UI shows matching faces and real wallet gain")
    app.api.local_engine.own().spell=2
    app._accept(await app.api.state());await app._cast("bulwark")
    check(not app.api.local_engine.own().shieldSlots.is_empty(),"native solo spell creates shields")
    var tower:=int(app._me().tower)
    app._tower_map();await wait_frames();await app._move_to((tower+1)%10)
    check(int(app._me().tower)==(tower+1)%10,"native solo tower selector changes only selected tower")
    app.api.local_engine.own().paidRolls=5
    app.api.local_engine.s.now=int(app.api.local_engine.s.endAt)
    app.api.local_engine.finish(int(app.api.local_engine.s.endAt))
    app._accept(app.api._local_state());await wait_frames()
    check(app.screen=="result","native solo result scene")
    await click("claim_rewards");await wait_frames();await click("result_home")
    check(app.screen=="home" and not app.api.is_local(),"native solo claim returns home without orphaned session")
    app.pages.show("raid");await wait_frames();await click("raid_start")
    check(app.screen=="battle" and app.api.local_kind=="raid" and app.latest.heroes.size()==21,"native daily raid battle scene")
    app.api.local_engine.forced_faces=["H","H","H"]
    await app._roll()
    check(int(app.api.local_engine.boss.armor)<=1,"raid roll strips original armour amount")
    await app._do_action("leave");await wait_frames()
    check(app.screen=="result","raid attempt-end result")
    await click("claim_rewards");await wait_frames();await click("result_home")
    check(app.screen=="home" and not app.api.is_local(),"raid saved end-to-home flow")
    app.pages.show("settings");await wait_frames()
    app.pages._preview_import(app.save_store.export_text());await wait_frames()
    check(find_button("confirm_import")!=null,"save import shows confirmation before replacing data")
    if is_instance_valid(app.modal):app.modal.queue_free();app.modal=null
    var report:Dictionary={"checks":checks,"errors":errors,"count":checks.size(),"status":"PASS" if errors.is_empty() else "FAIL","local_fixture":true,"physical_phone":false}
    FileAccess.open("res://reports/full-port/native-ui-flow.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
    print("FULL_UI ",JSON.stringify(report))
    app.queue_free()
    await wait_frames(5)
    quit(0 if errors.is_empty() else 1)
