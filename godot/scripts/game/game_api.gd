extends "res://scripts/arena_api.gd"
const Content=preload("res://scripts/game/content.gd")
const NativeArena=preload("res://scripts/game/arena_local.gd")
const Solo=preload("res://scripts/game/solo_campaign.gd")
const Raid=preload("res://scripts/game/raid.gd")
var progression
var active_progression
var local_engine=null
var local_kind:=""
var online_id:=""
var previous_saved_at:=0
var online_profile:Dictionary={}
var receipt_sync_busy:=false
var sync_error:=""
var local_error:=""
var pause_local:=false
var paused_wall_at:=0
var last_action_answer:Dictionary={}
func _ready()->void:
    super._ready()
    online_id=player_id
func configure(p)->void:
    progression=p;active_progression=p
func is_local()->bool:return local_engine!=null
func current_progress():return active_progression if active_progression!=null else progression
func _capture()->void:
    if local_engine==null:return
    active_progression.d.native.session={"kind":local_kind,"snapshot":local_engine.export_state(),"savedAt":Content.now_ms(),"pausedAt":paused_wall_at}
func checkpoint()->bool:
    if local_engine==null:return progression.store.commit() if progression!=null else true
    _capture()
    var okay:bool=active_progression.store.commit()
    if not okay:local_error=active_progression.store.last_error
    previous_saved_at=Content.now_ms()
    return okay
func start_local(kind:String,options:Dictionary={},temporary_progress=null)->Dictionary:
    if local_engine!=null and not local_engine.s.get("ended",false):return {"ok":false,"error":"Finish the current session first"}
    active_progression=temporary_progress if temporary_progress!=null else progression
    local_kind=kind;local_error="";pause_local=false;paused_wall_at=0
    var now:int=active_progression.now()
    var seed_value:int=int(options.get("seed",int(Time.get_ticks_usec())&0xffffffff))
    if kind in ["campaign","training"]:
        local_engine=Solo.new();local_engine.configure(active_progression)
    elif kind=="raid":
        local_engine=Raid.new();local_engine.configure(active_progression)
        if not local_engine.ensure_day():local_engine=null;return {"ok":false,"error":active_progression.store.last_error}
    else:local_engine=NativeArena.new()
    var okay:bool=active_progression.perform(func():
        if kind in ["campaign","training"]:local_engine.start(now,seed_value,kind=="training")
        elif kind=="raid":
            if not local_engine.start(now,seed_value):return false
        else:
            var p:Dictionary=active_progression.d
            var players:Array=[]
            for i in 20:players.append({"id":"you" if i==0 else "local-bot-"+str(i),"name":"You" if i==0 else "Practice Bot "+str(i),"bot":i>0,"char":int(p.char) if i==0 else i%5,"weapon":int(p.weapon) if i==0 else int([0,1,4,5,7][i%5]),"loadout":p.adventure.loadout.duplicate()})
            local_engine.init_match("practice-"+str(now),players,now,seed_value,str(options.get("mode","standard")),int(options.get("duration",300000)),true,options.get("scenario",{}))
        _capture()
        return true
    )
    if not okay:
        local_engine=null;active_progression=progression;local_kind=""
        return {"ok":false,"error":active_progression.store.last_error if not active_progression.store.last_error.is_empty() else "This session is unavailable."}
    player_id="you"
    wire.clear()
    previous_saved_at=now
    return _local_state()
func restore_local()->Dictionary:
    var session:Variant=progression.d.native.get("session")
    if not session is Dictionary or not session.get("snapshot") is Dictionary:return {"ok":false,"error":"No native session to resume"}
    local_kind=str(session.get("kind",""));active_progression=progression
    if local_kind=="campaign":local_engine=Solo.new();local_engine.configure(progression)
    elif local_kind=="raid":local_engine=Raid.new();local_engine.configure(progression)
    elif local_kind=="practice":local_engine=NativeArena.new()
    else:return {"ok":false,"error":"Unsupported saved session; export your save before replacing it."}
    if not local_engine.restore(session.snapshot):local_engine=null;return {"ok":false,"error":"Saved session could not be read. Your save is preserved."}
    player_id="you";wire.clear()
    pause_local=local_kind=="raid" and progression.d.get("levelReward") is Dictionary
    paused_wall_at=int(session.get("pausedAt",session.get("savedAt",progression.now()))) if pause_local else 0
    _advance_local()
    return _local_state()
func leave_local()->bool:
    if local_engine==null:return true
    if local_kind in ["campaign","practice"] and not local_engine.s.ended:return false
    if local_kind=="raid" and not local_engine.s.ended:local_engine.end_attempt("leave",Content.now_ms())
    if local_kind!="training":
        if not active_progression.perform(func():active_progression.d.native.erase("session")):return false
    local_engine=null;local_kind="";active_progression=progression;player_id=online_id;pause_local=false;paused_wall_at=0
    wire.clear()
    return true
func _advance_local()->void:
    if local_engine==null or local_engine.s.ended or not local_error.is_empty() or pause_local:return
    var now:int=active_progression.now();var from:=int(local_engine.s.now)
    if now<from:return
    var before:Dictionary=local_engine.export_state()
    var oldsave:Dictionary=active_progression.d.duplicate(true)
    # Bounded catch-up to the recorded end: never spend a human roll or gift while away.
    var limit:int=mini(now,int(local_engine.s.endAt)+60000)
    var steps:=0
    while from<limit and not local_engine.s.ended and steps<1800:
        from=mini(limit,from+250);local_engine.tick(from);steps+=1
    _capture()
    if local_engine.s.ended or now-previous_saved_at>=3000:
        if not active_progression.store.commit():
            active_progression.store.data=oldsave;local_engine.restore(before);local_error=active_progression.store.last_error
        previous_saved_at=now
func _local_state()->Dictionary:
    if local_engine==null:return {"ok":true,"status":"idle"}
    var s:Dictionary=local_engine.snapshot();var complete:bool=s.ended
    var result:Dictionary={}
    if complete:
        if local_kind=="raid":result={"id":s.id,"win":local_engine.boss.killed,"draw":false,"score":[int(local_engine.run.dmg),int(local_engine.boss.hp)],"reward":{},"stats":{"damage":local_engine.run.dmg},"raid":true,"reason":local_engine.run.reason,"eligible":true}
        else:result=local_engine.result("you")
    return {"ok":true,"status":"complete" if complete else "battle","serverNow":s.now,"match":s,"result":result,"earnings":{"gold":0,"xp":0,"paidRolls":0},"local":true,"kind":local_kind,"saveError":local_error}
func state(full:=false)->Dictionary:
    if local_engine!=null:_advance_local();return _local_state()
    return await super.state(full)
func queue(char_index:=0,weapon_index:=0,loadout:=["barrage","bulwark"])->Dictionary:
    if local_engine!=null:return {"ok":false,"error":"Finish the offline session before matchmaking"}
    player_id=online_id
    var response:Dictionary=await super.queue(int(char_index),int(weapon_index),loadout)
    return response
func ensure_session(display_name:="Godot Player")->Dictionary:
    if local_engine!=null:return {"ok":true,"playerId":"you","local":true}
    player_id=online_id
    var answer:Dictionary=await super.ensure_session(display_name)
    if answer.get("ok",false):online_id=player_id
    return answer
func action(kind:String,match_id:String,payload:={}) -> Dictionary:
    var response:Dictionary=await _perform_action(kind,match_id,payload)
    last_action_answer=response.duplicate(true)
    return response
func _perform_action(kind:String,match_id:String,payload:={}) -> Dictionary:
    if local_engine==null:return await super.action(kind,match_id,payload)
    if not local_error.is_empty():return {"ok":false,"error":local_error}
    if str(local_engine.s.id)!=match_id:return {"ok":false,"error":"Stale offline action"}
    _advance_local()
    if not local_error.is_empty():return {"ok":false,"error":local_error,"state":_local_state()}
    if pause_local:return {"ok":false,"error":"Collect the level-up reward to continue this raid."}
    var before:Dictionary=local_engine.export_state()
    var result:Dictionary={}
    var params:Dictionary=payload.duplicate(true);params.type=kind
    var okay:bool=active_progression.perform(func():
        result.merge(local_engine.act("you",params,active_progression.now()),true)
        if not result.get("ok",false):return false
        _capture()
        return true
    )
    if not okay:
        local_engine.restore(before)
        return {"ok":false,"error":str(result.get("error",active_progression.store.last_error)),"state":_local_state()}
    result.state=_local_state()
    return result
func claim(match_id:String,shard_kind:="steel")->Dictionary:
    if local_engine!=null:
        if not local_engine.s.ended or str(local_engine.s.id)!=match_id:return {"ok":false,"error":"No completed session"}
        var result:Dictionary=_local_state().result
        var okay:bool=active_progression.perform(func():
            if local_kind=="campaign" and active_progression.d.get("pendingMatch") is Dictionary:
                var reward:Dictionary=active_progression.d.pendingMatch.duplicate(true);active_progression.d.pendingMatch=null
                if int(reward.get("season",-1))!=Content.season_id(active_progression.now()):reward.pts=0
                active_progression._grant(reward)
            if result.get("scenario") is Dictionary:active_progression.d.adventure.lastMoment=result.scenario.duplicate(true)
            active_progression.d.native.erase("session")
        )
        if not okay:return {"ok":false,"error":active_progression.store.last_error}
        return {"ok":true,"receipt":{"id":match_id,"reward":result.get("reward",{})},"local":true}
    # Persist intent before network claim. A successful server response can safely
    # be retried even if the phone dies before its local reward write.
    var journal_key:="claim:"+match_id
    if not progression.perform(func():progression.d.native.journal[journal_key]={"id":match_id,"kind":shard_kind}):return {"ok":false,"error":progression.store.last_error}
    var answer:Dictionary=await super.claim(match_id,shard_kind)
    if answer.get("ok",false):
        if not progression.apply_receipt(answer.get("receipt",{})):return {"ok":false,"error":"Server receipt is safe, but local saving failed. Retry after freeing storage."}
        progression.perform(func():progression.d.native.journal.erase(journal_key))
        online_profile=answer.get("profile",{})
    return answer
func profile()->Dictionary:
    var answer:Dictionary=await super.profile()
    if answer.get("ok",false):online_profile=answer
    return answer
func pending_rewards()->Dictionary:
    return await _request("/pending-rewards")
func guild_call(command:Dictionary)->Dictionary:
    var response:Dictionary=await _request("/guild",command)
    if response.get("ok",false) and response.get("receipt") is Dictionary:
        var claimed:Dictionary=await claim(str(response.receipt.id),Content.shard_kind(int(progression.d.weapon)))
        if not claimed.get("ok",false):return claimed
        response.receipt=claimed.receipt
    return response
func sync_receipts()->Dictionary:
    if local_engine!=null or receipt_sync_busy:return {"ok":false,"error":"Busy"}
    receipt_sync_busy=true;sync_error=""
    # Retry durable interrupted claims before reading already-claimed history.
    for entry in progression.d.native.journal.values().duplicate(true):
        if not entry is Dictionary or not entry.has("id"):continue
        var answer:Dictionary=await claim(str(entry.id),str(entry.get("kind","steel")))
        if not answer.get("ok",false):sync_error=str(answer.get("error","Claim recovery failed"));receipt_sync_busy=false;return answer
    var cursor:="";var count:=0
    for _i in 100:
        var response:Dictionary=await _request("/receipts?limit=100"+("&after="+cursor.uri_encode() if not cursor.is_empty() else ""))
        if not response.get("ok",false):
            sync_error="Receipt history requires the native-compatible server update." if int(response.get("status",0))==404 else str(response.get("error","Reward history unavailable"))
            receipt_sync_busy=false;return {"ok":false,"error":sync_error}
        for receipt in response.get("receipts",[]):
            if receipt.get("claimed",false):
                if not progression.apply_receipt(receipt):receipt_sync_busy=false;return {"ok":false,"error":progression.store.last_error}
                count+=1
        var next:Variant=response.get("next")
        if next==null or str(next).is_empty():break
        cursor=str(next)
    receipt_sync_busy=false
    return {"ok":true,"count":count}
func cloud_request(code:String,upload:=false)->Dictionary:
    var regex:=RegEx.new();regex.compile("^FB-[23456789ABCDEFGHJKMNPQRSTVWXYZ]{4}-[23456789ABCDEFGHJKMNPQRSTVWXYZ]{4}$")
    if regex.search(code)==null:return {"ok":false,"error":"Enter your own FB-XXXX-XXXX save code."}
    var host:=base_url.trim_suffix("/arena")
    var request:=HTTPRequest.new();request.timeout=15;request.accept_gzip=true;request.body_size_limit=5*1024*1024;add_child(request)
    var url:=host+"/api/save"+("?playerId="+code.uri_encode() if not upload else "")
    var body:="" if not upload else JSON.stringify({"playerId":code,"save":JSON.stringify(progression.d)})
    var started:=request.request(url,PackedStringArray(["Content-Type: application/json","Cache-Control: no-store"]),HTTPClient.METHOD_POST if upload else HTTPClient.METHOD_GET,body)
    if started!=OK:request.queue_free();return {"ok":false,"error":"Cloud request could not start"}
    var raw:Array=await request.request_completed;request.queue_free()
    if int(raw[0])!=HTTPRequest.RESULT_SUCCESS:return {"ok":false,"error":"Cloud connection failed; local data is unchanged."}
    var answer=JSON.parse_string((raw[3] as PackedByteArray).get_string_from_utf8())
    if not answer is Dictionary:return {"ok":false,"error":"Cloud returned an invalid response"}
    if int(raw[1])<200 or int(raw[1])>=300:return {"ok":false,"error":"Save code not found" if int(raw[1])==404 else str(answer.get("error","Cloud request failed"))}
    answer.ok=true;return answer
