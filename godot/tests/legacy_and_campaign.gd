extends SceneTree
const Store=preload("res://scripts/game/progress_store.gd")
const Progress=preload("res://scripts/game/progression.gd")
const Solo=preload("res://scripts/game/solo_campaign.gd")
const Raid=preload("res://scripts/game/raid.gd")
const Legacy=preload("res://scripts/game/legacy_import.gd")
var errors:Array=[]
var checks:Array=[]
const NOW:=1790431200000
func check(okay:bool,name:String)->void:
    if okay:checks.append(name)
    else:errors.append(name);push_error(name)
func fresh():
    var store=Store.new("user://legacy-test-not-written.json",false);store.memory_only=true
    var p=Progress.new(store);p.at_override=NOW;p.boot();return p
func finite_state(value:Variant)->bool:
    if value is float:return is_finite(value)
    if value is Array:
        for item in value:
            if not finite_state(item):return false
    elif value is Dictionary:
        for item in value.values():
            if not finite_state(item):return false
    return true
func _init()->void:
    var p=fresh();var e=Solo.new();e.configure(p);e.start(NOW,111)
    var snapshot:Dictionary=e.s.duplicate(true);snapshot.sessionBuild=106;snapshot.focus=3;snapshot.focusAt=NOW-9000;snapshot.ended=false;snapshot.lobby=false;snapshot.lastTick=NOW
    snapshot.heroes[0].id="00";snapshot.heroes[0].hp=407;snapshot.heroes[0].tower=8;snapshot.heroes[0].shieldSlots=[11,60];snapshot.heroes[0].paidRolls=7;snapshot.heroes[0].spentEnergy=12
    p.d.war={"model":2,"matchVersion":3,"sessionBuild":106,"id":"legacy-approved","phase":"day","startAt":NOW-40000,"endAt":NOW+260000,"control":[14000,31000],"controlDuration":17000,"playerId":"00","snapshot":snapshot,"rallyClaimed":true,"preview":false}
    var old:Dictionary=p.d.duplicate(true)
    var converted:Dictionary=Legacy.convert(p)
    check(converted.get("converted",false),"compatible session106 converts to native")
    if converted.get("converted",false):
        var resumed=Solo.new();resumed.configure(p);check(resumed.restore(p.d.native.session.snapshot),"converted native snapshot is loadable")
        check(int(resumed.own().hp)==407 and int(resumed.own().tower)==8 and resumed.own().shieldSlots==[11,60],"import preserves player HP/tower/shields")
        check(int(resumed.own().focus)==3 and int(resumed.own().paidRolls)==7 and int(resumed.own().focusSpent)==12,"import preserves Focus and participation")
        check(int(resumed.s.endAt)==NOW+260000 and resumed.s.control==[14000,31000],"import preserves deadline and banked control")
        check(p.d.native.importedLegacyWar==old.war and p.d.war==null,"original web battle preserved separately")
        check(int(p.d.gold)==int(old.gold) and int(p.d.stats.matches)==int(old.stats.matches),"battle conversion does not charge or count a new match")
    var expired=fresh();expired.d.war=old.war.duplicate(true);expired.d.war.endAt=NOW-61000
    var skipped:Dictionary=Legacy.convert(expired)
    check(not skipped.converted and expired.d.war!=null and not expired.d.native.has("session"),"expired web session preserved without invented rewards")
    var reports:Array=[]
    for ci in 5:
        var prog=fresh();prog.d.char=ci;prog.d.weapon=[0,1,4,5,7][ci];prog.d.owned=[0,1,2,3,4,5,6,7,8];prog.d.level=15
        prog.d.tiers[str(prog.d.weapon)]=2;prog.d.relics.atk=3;prog.d.relics.crit=1;prog.d.relics.lucky=1
        var game=Solo.new();game.configure(prog);game.start(NOW,1109+ci*91)
        var actions:=0;var cast:=0;var ability:=0;var rolled:=0
        for tick in range(1,1442):
            var time:=NOW+tick*250;prog.at_override=time;game.tick(time)
            if game.s.ended:break
            var h:Dictionary=game.own()
            if prog.d.get("levelReward") is Dictionary:prog.claim_level_reward()
            if int(h.hp)<=0:continue
            if not game.s.get("pendingGift",[]).is_empty():game.act("you",{"type":"gift_choice","index":0},time)
            if int(h.ult)>=100:
                if game.act("you",{"type":"ultimate"},time).ok:ability+=1
            if int(h.spell)>0 and time>=int(h.spellAt) and tick%20==0:
                var command:Dictionary=game.act("you",{"type":"spell","spell":["barrage","bulwark","surge"][cast%3]},time)
                if command.ok:cast+=1
            if int(h.focus)>0 and time>=int(h.rollAt):
                var reply:Dictionary=game.act("you",{"type":"roll","mult":1,"qte":1.35},time)
                if reply.ok:rolled+=1
                actions+=1
            if tick%160==0:game.act("you",{"type":"move","tower":(int(h.tower)+1)%10},time)
            if tick==600:
                var saved:Dictionary=JSON.parse_string(JSON.stringify(game.export_state()))
                var restored=Solo.new();restored.configure(prog);check(restored.restore(saved),"mid-match JSON restore hero "+str(ci));game=restored
        check(game.s.ended,"solo full timed match completes hero "+str(ci))
        check(finite_state(game.s) and finite_state(prog.d),"finite state/rewards hero "+str(ci))
        check(game.s.heroes.size()==40 and prog.d.native.journal.is_empty(),"40-fighter loop stays local hero "+str(ci))
        reports.append({"hero":ci,"rolls":rolled,"spells":cast,"ults":ability,"score":game.s.score,"result":game.result("you").reward})
    var raid_p=fresh();raid_p.d.level=8
    var raid=Raid.new();raid.configure(raid_p);raid.ensure_day();raid.start(NOW,93)
    var maximum:=int(raid.boss.max);raid_p.gift_box().items.append(maximum)
    var won:Dictionary=raid.act("you",{"type":"stored","index":0},NOW)
    check(won.ok and raid.boss.killed and raid.run.ended,"stored attack can finish raid and closes attempt")
    check(raid.boss.killer=="You" and int(raid.boss.dmg)>0,"personal raid damage and Slayer credited")
    var paid:Dictionary=raid_p.d.duplicate(true)
    check(not raid.act("you",{"type":"stored","index":0},NOW+1000).ok and raid_p.d==paid,"ended raid cannot award again")
    var file:Dictionary={"status":"PASS" if errors.is_empty() else "FAIL","checks":checks,"errors":errors,"campaign_runs":reports,"physical_phone":false}
    FileAccess.open("res://reports/full-port/legacy-campaign-tests.json",FileAccess.WRITE).store_string(JSON.stringify(file,"  ")+"\n")
    print("LEGACY_CAMPAIGN ",JSON.stringify(file))
    quit(0 if errors.is_empty() else 1)
