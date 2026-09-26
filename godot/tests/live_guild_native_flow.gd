extends SceneTree
const Client=preload("res://scripts/full_client.gd")
var app
var checks:Array[String]=[]
var failures:Array[String]=[]
func _init()->void:call_deferred("_run")
func check(okay:bool,text:String)->void:
    if okay:checks.append(text)
    else:failures.append(text);push_error(text)
func find_action(key:String,node:Node=null)->Button:
    if node==null:node=app.ui_root
    if node is Button and str(node.get_meta("action_key",""))==key:return node
    for child in node.get_children():
        var found:=find_action(key,child)
        if found!=null:return found
    return null
func control(path:String)->void:
    var http:=HTTPRequest.new();root.add_child(http);assert(http.request("http://127.0.0.1:8852"+path)==OK)
    var response:Array=await http.request_completed;http.queue_free();assert(int(response[1])==200)
func wait_ready()->void:
    for i in 120:
        await create_timer(0.04).timeout
        if not app.profile_in_flight and not app.pages._guild_busy:return
func _run()->void:
    app=Client.new();app.autoload_network=false;app._save_path_override="user://guild-ui-"+str(Time.get_ticks_usec())+".json"
    app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(app);await process_frame
    app.save_store.memory_only=true;app.api.base_url="http://127.0.0.1:8851";app.api.identity_path="user://guild-ui-local.json";app.api.token="";app.api.online_id="";app.api.player_id=""
    app.pages.show("live_guild");await wait_ready();await create_timer(0.15).timeout
    var create:=find_action("guild_create")
    check(create!=null,"live guild connection renders create form")
    if create!=null:
        for field in create.get_parent().get_children():
            if field is LineEdit:field.text="Native Full Port Test"
        create.pressed.emit();await wait_ready();await create_timer(0.15).timeout
    var guild:Variant=app.api.online_profile.get("guild")
    check(guild is Dictionary and guild.name=="Native Full Port Test","native guild create roundtrip")
    await app.pages._guild_command({"type":"route","route":"defense"})
    check(app.api.online_profile.guild.route=="defense","native leader route changes server route")
    await control("/guild-progress")
    await app.pages._load_live_guild();await create_timer(0.15).timeout
    var claim:=find_action("guild_claim_0");check(claim!=null and not claim.disabled,"qualified live milestone enables claim")
    var gold:=int(app.d.gold);var tokens:=int(app.d.tokens);var shards:=int(app.d.shards.steel)
    if claim!=null:claim.pressed.emit();await wait_ready();await create_timer(0.20).timeout
    check(int(app.d.gold)==gold+150 and int(app.d.tokens)==tokens+1 and int(app.d.shards.steel)==shards+2,"guild receipt pays exact original milestone once")
    var before:Dictionary=app.d.duplicate(true)
    var recovered:Dictionary=await app.api.sync_receipts()
    check(recovered.ok and int(app.d.gold)==int(before.gold) and int(app.d.tokens)==int(before.tokens),"claimed receipt history deduplicates native award")
    await app.pages._guild_command({"type":"leave"})
    check(app.api.online_profile.get("guild")==null,"native leave-guild roundtrip")
    # Manual cloud calls only use this isolated local web-host fixture and a test code.
    app.pages.show("settings");app.api.base_url="http://127.0.0.1:8853/arena"
    var code:="FB-2345-6789"
    var uploaded:Dictionary=await app.api.cloud_request(code,true)
    var fetched:Dictionary=await app.api.cloud_request(code,false)
    var parsed:Dictionary=app.save_store.parse_import(str(fetched.get("save","")))
    check(uploaded.get("ok",false) and fetched.get("ok",false) and parsed.get("ok",false),"native cloud upload/read/import parser roundtrip")
    check(int(parsed.get("save",{}).get("gold",-1))==int(app.d.gold),"cloud roundtrip preserves native progression")
    var invalid:Dictionary=await app.api.cloud_request("not-a-code",false)
    check(not invalid.ok,"native cloud input rejects invalid save code")
    var report:Dictionary={"status":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures,"local_only":true,"physical_phone":false}
    FileAccess.open("res://reports/full-port/guild-cloud-flow.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
    print("GUILD_CLOUD_FLOW ",JSON.stringify(report))
    app.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
