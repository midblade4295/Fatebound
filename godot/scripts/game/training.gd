extends RefCounted
const C=preload("res://scripts/game/content.gd")
const Store=preload("res://scripts/game/progress_store.gd")
const Progress=preload("res://scripts/game/progression.gd")
var app
var real_progress
var temp_store
var temp_progress
var index:=0
var active:=false
var changing:=false
func begin(client,progress)->bool:
    app=client;real_progress=progress
    var saved:Dictionary=progress.d
    index=0 if saved.get("tutorialBattle",{}).get("done",false) else clampi(int(saved.get("tutorialBattle",{}).get("step",0)),0,32)
    temp_store=Store.new("user://unused-training-memory.json",false);temp_store.memory_only=true
    temp_store.data=Store.normalized(saved.duplicate(true))
    temp_store.data.native.erase("session");temp_store.data.pendingRoll=null;temp_store.data.pendingMatch=null;temp_store.data.levelReward=null
    temp_store.data.gold=0;temp_store.data.bonus=120;temp_store.data.xp=0;temp_store.data.level=30
    temp_store.data.rollTrack={"progress":0,"ready":0,"gold":0,"shards":{"steel":0,"arcane":0,"fletch":0}}
    temp_progress=Progress.new(temp_store)
    var started:Dictionary=app.api.start_local("training",{},temp_progress)
    if not started.get("ok",false):return false
    active=true
    app._accept(started);app.poll_timer.start()
    prepare()
    return true
func lesson()->Dictionary:return C.get_table("BATTLE_LESSONS")[index]
func persist()->void:
    real_progress.perform(func():real_progress.d.tutorialBattle={"step":index,"done":false,"paused":false})
func prepare()->void:
    if not active:return
    var l:=lesson();var e=app.api.local_engine;var h:Dictionary=e.own()
    h.rampage=0;h.forcedCrits=0;h.hot=false;h.streak=0;h.focus=8;h.rollAt=0
    if l.has("faces"):e.forced_faces=l.faces.duplicate()
    else:e.forced_faces=[]
    if l.get("action","")=="mult":h.mult=1
    if l.get("action","")=="ult":h.ult=100
    if index in [14,15] and temp_progress.gift_box().items.is_empty():temp_progress.gift_box().items.append(500)
    if index==13 and e.s.get("pendingGift",[]).is_empty():e._gift_choices(1,true)
    if index==19:e.s.ralliesLeft[0]=3;e.s.rallyCdUntil[0]=0;h.ralliesLeft=3;h.rallyAt=0
    if index==28:temp_store.data.gold=500;h.gold=500
    var target:="battle"
    if index==18:target="map"
    elif index in [22]:target="home"
    elif index in [23,24]:target="hero"
    elif index in [25,26]:target="guild"
    elif index in [27,28]:target="friends"
    elif index in [29,30]:target="shop"
    elif index==31:target="battle"
    elif index==32:target="home"
    app.training_show_target(target)
    if index==13:app.show_gift_choices()
    if index==15:app.show_stored_attacks()
    app.rebuild_coach()
    persist()
func next()->void:
    if not active or changing:return
    changing=true
    if index>=32:
        finish(true);changing=false;return
    index+=1
    prepare()
    changing=false
func notify(action:String)->void:
    if not active or changing:return
    var expected:=str(lesson().get("action",""))
    var mapping:Dictionary={"giftRoll":"roll","gift":"gift_choice","giftOpen":"stored_menu","giftUse":"stored","ult":"ultimate","tower":"move","visitGuild":"guild","visitFriends":"friends","visitShop":"shop","buyEnergy":"practice_purchase"}
    if expected.is_empty():return
    if action==str(mapping.get(expected,expected)):next()
func finish(done:=false)->void:
    if not active:return
    active=false
    real_progress.perform(func():
        real_progress.d.tutorialBattle={"step":0 if done else index,"done":done,"paused":not done}
        real_progress.d.tutorial={"step":0,"done":done,"paused":not done}
    )
    app.api.local_engine=null;app.api.local_kind="";app.api.active_progression=real_progress;app.api.player_id=app.api.online_id
    app.poll_timer.stop();app.busy=false;app.current_match_id="";app.latest={};app.latest_state={}
    if is_instance_valid(app.coach):app.coach.queue_free()
    app.coach=null
    app._show_home()
