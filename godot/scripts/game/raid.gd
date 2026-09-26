extends "res://scripts/game/arena_local.gd"
const Factory=preload("res://scripts/game/hero_factory.gd")
var progression
var run:Dictionary={}
var kind:="raid"
var boss:Dictionary:
    get:return progression.d.boss
func configure(p)->void:
    progression=p
func ensure_day()->bool:
    var today:=C.local_day(progression.now())
    if progression.d.get("boss") is Dictionary and str(progression.d.boss.get("date",""))==today:return true
    return progression.perform(func():
        var old:Variant=progression.d.get("boss")
        if old is Dictionary and old.get("clan") is Dictionary:
            var better:=0
            for score in old.clan.values():
                if float(score)>float(old.get("dmg",0)):better+=1
            var place:=better+1
            var tokens:=0 if float(old.get("dmg",0))<=0 else (5 if place==1 else (3 if place<=3 else (2 if place<=10 else 1)))
            if tokens>0:progression.d.bossPending={"name":old.name,"place":place,"tk":tokens,"killed":old.killed}
        var h:=7
        for letter in today:h=(h*33+letter.unicode_at(0))&0xffffffff
        var chosen:Array=C.get_table("BOSS_NAMES")[h%5]
        var ci:=0
        for i in 5:
            if C.character(i).id==chosen[1]:ci=i
        var maximum:=32000+2500*maxi(5,int(progression.d.level))
        var clan:Dictionary={};var already:=0
        for name in C.get_table("NAMES").slice(1,20):
            var value:=C.jsround(maximum*(0.05+((h*31+str(name).unicode_at(0)*7)%100)/100.0*0.10)/19*4)
            clan[name]=value;already+=value
        progression.d.boss={"date":today,"name":chosen[0],"char":ci,"weapon":int(chosen[2]),"weak":"C" if ((h>>3)&1) else "S","max":maximum,"hp":maximum-already,"armor":4,"dmg":0,"attempts":0,"tiers":[],"killed":false,"killer":null,"clan":clan,"stagger":0,"milestones":[]}
        if progression.d.get("bossPending") is Dictionary:
            var pending:Dictionary=progression.d.bossPending;progression.d.tokens=int(progression.d.tokens)+int(pending.tk)
            progression.say("Previous daily raid · company #%d · +%d tokens"%[int(pending.place),int(pending.tk)])
            progression.d.bossPending=null
    )
func start(now:int,initial_seed:int)->bool:
    if not ensure_day() or boss.killed or int(boss.attempts)>=3:return false
    seed=initial_seed&0xffffffff
    if seed==0:seed=1
    var team:Array=Factory.company(progression,random)
    var participants:Array=[]
    for h in team:
        if int(h.side)==0:h.tower=0;participants.append(h)
    var b:Dictionary={"id":"boss","name":boss.name,"side":1,"char":boss.char,"weapon":boss.weapon,"level":30,"atk":0,"hp":boss.hp,"maxHp":boss.max,"shieldSlots":[],"downUntil":0,"tower":0,"bot":true,"substitute":false,"connected":true}
    participants.append(b)
    s={"version":1,"balanceVersion":110,"id":"raid-"+str(now),"mode":"raid","practice":false,"heroes":participants,"towers":[],"now":now,"startAt":now,"endAt":now+90000,"phase":"raid","ended":false,"revision":0,"seq":0,"events":[],"score":[0,0],"control":[0,0],"controlDuration":0,"rally":[null,null],"holds":[{},{}]}
    for i in 10:s.towers.append({"id":i,"name":ROMAN[i],"pts":0,"prev":-1,"dmg":[0,0]})
    run={"until":now+90000,"staggerMeter":0,"staggerUntil":0,"parryUntil":0,"parried":false,"parryHit":false,"nextStrike":now+5000,"telegraphUntil":0,"botAt":now,"ended":false,"dmg":0,"date":boss.date,"reason":""}
    boss.attempts=int(boss.attempts)+1
    event("start","Raid attempt %d / 3 · 90 seconds"%int(boss.attempts),now)
    sync_boss()
    return true
func sync_boss()->void:
    if s.is_empty():return
    var b:=hero("boss");b.hp=maxi(0,int(boss.hp));b.maxHp=boss.max;b.downUntil=int(s.endAt)+999999 if boss.killed else 0
    s.boss= boss.duplicate(true)
    s.raid=run.duplicate(true)
func phase()->int:
    return 3 if float(boss.hp)<=float(boss.max)/3 else (2 if float(boss.hp)<=float(boss.max)*2/3 else 1)
func own()->Dictionary:
    return s.heroes[0]
func _refresh_power()->void:
    var h:=own();var ratio:=float(h.hp)/maxf(1,float(h.maxHp));var power_data:Dictionary=progression.hero_power()
    h.atk=power_data.atk;h.maxHp=power_data.maxHp;h.hp=C.jsround(h.maxHp*ratio);h.level=progression.d.level
func _ult_add(amount:int)->void:
    var h:=own()
    if int(h.rampage)>0:return
    var tier:=int(progression.d.tiers.get(str(int(h.weapon)),0));var perk:Dictionary=C.get_table("PERKS")[C.weapon(int(h.weapon)).cls]
    var boost:=0.25*int(C.get_table("TIERS")[tier].get("perk",0)) if perk.k=="ult" else 0.0
    var n:=C.jsround(amount*(1+boost))
    if h.action is Dictionary:
        n=mini(n,maxi(0,10-int(h.action.get("ultEarned",0))))
        h.action.ultEarned=int(h.action.get("ultEarned",0))+n
    h.ult=mini(100,int(h.ult)+n)
func _boss_hit(who:Dictionary,amount:int,now:int)->int:
    if run.ended or int(boss.hp)<=0:return 0
    var take:=mini(amount,int(boss.hp));boss.hp=int(boss.hp)-take
    if who.id=="you":
        boss.dmg=int(boss.dmg)+take;run.dmg=int(run.dmg)+take
        for i in 4:
            var t:Array=C.get_table("BOSS_TIERS")[i]
            if not boss.tiers.has(i) and int(boss.dmg)>=maxi(1000,C.jsround(float(boss.max)*float(t[0]))):
                boss.tiers.append(i);progression._grant({"gold":int(t[1]),"tokens":int(t[2]),"xp":int(t[3])});_refresh_power()
                progression.say("Raid tier %d · +%d gold · +%d tokens · +%d XP"%[i+1,int(t[1]),int(t[2]),int(t[3])])
    else:boss.clan[who.name]=int(boss.clan.get(who.name,0))+take
    var total:=int(boss.max)-maxi(0,int(boss.hp))
    if not boss.get("milestones") is Array:boss.milestones=[]
    for i in 4:
        var t:Array=C.get_table("BOSS_MILESTONES")[i]
        if int(boss.dmg)>0 and not boss.milestones.has(i) and total>=float(boss.max)*float(t[0]):
            boss.milestones.append(i);progression._grant({"gold":int(t[1]),"tokens":int(t[2]),"shards":int(t[3]),"pts":int(t[4])})
            progression.say("Raid company milestone %d / 4"%(i+1))
    if int(boss.hp)<=0 and not boss.killed:
        boss.killed=true;boss.killer="You" if who.id=="you" else who.name
        if int(boss.dmg)>=float(boss.max)*0.02:
            progression._grant({"tokens":5,"chest":1,"xp":90});_refresh_power()
        end_attempt("slain",now)
    sync_boss()
    return take
func end_attempt(reason:String,now:int)->void:
    if run.ended:return
    run.ended=true;run.reason=reason;s.ended=true;s.phase="complete";s.completedAt=now
    event("end","BOSS SLAIN" if reason=="slain" else ("KNOCKED OUT" if reason=="KO" else ("ATTEMPT ENDED" if reason=="leave" else "TIME'S UP")),now)
func parry(now:int)->bool:
    if run.ended or int(run.telegraphUntil)<=now or int(run.telegraphUntil)==0:return false
    run.parryHit=true
    sync_boss()
    return true
func _crit(h:Dictionary)->float:
    if h.id=="you":return float(progression.hero_power().crit)+(1 if int(h.forcedCrits)>0 else 0)
    var ch:Dictionary=C.character(int(h.char));var w:Dictionary=C.weapon(int(h.weapon));var perk:Dictionary=C.get_table("PERKS")[w.cls];var tier:Dictionary=C.get_table("TIERS")[int(h.get("tier",0))]
    return 2+minf(3,0.1*int(h.level))+float(ch.crit)+float(w.get("crit",0))+(float(perk.v)*int(tier.get("perk",0)) if perk.k=="crit" else 0.0)
func act(id:String,input:Dictionary,now:int)->Dictionary:
    if s.is_empty() or run.ended or id!="you":return {"ok":false,"error":"No active raid attempt"}
    if str(boss.date)!=C.local_day(now):end_attempt("day_changed",now);return {"ok":false,"error":"The daily raid reset at midnight."}
    var h:=own();var kind:=str(input.get("type",""))
    if int(h.hp)<=0:return {"ok":false,"error":"This attempt has ended."}
    if kind=="parry":return {"ok":parry(now),"result":{"type":"parry"}}
    if kind=="leave":end_attempt("leave",now);return {"ok":true,"result":{"type":"leave"}}
    var before:Dictionary={"gold":progression.d.gold,"xp":progression.d.xp,"dmg":boss.dmg,"hp":h.hp,"armor":boss.armor}
    var out:Dictionary={"type":kind,"dealt":0,"absorbed":0}
    if kind=="roll":
        if now<int(h.rollAt):return {"ok":false,"error":"Dice are still settling"}
        h.rollAt=now+1700;h.action={"mult":1,"paid":0,"free":true,"boss":true,"ultEarned":0}
        var f:Array=faces()
        if h.hot:f[2]=f[0];h.hot=false;h.streak=0
        if int(h.forcedCrits)>0:
            f[2]="C"
            if f[0]!="C" and f[1]!="C":f[1]="C"
        var r:=C.resolve(f);h.lastFaces=f
        out.merge({"faces":f,"tier":r.tier,"symbol":r.action,"mult":1,"cost":0})
        progression._daily("rolls",1);progression.d.stats.rolls=int(progression.d.stats.rolls)+1
        if r.tier=="triple":progression._daily("triples",1);progression.d.stats.triples=int(progression.d.stats.triples)+1
        if r.action in ["S","C"]:
            var weak:=2.0 if r.tier!="none" and r.action==boss.weak else 1.0
            var stagger:=3.0 if now<int(run.staggerUntil) else 1.0
            var armour:=0.5 if int(boss.armor)>0 else 1.0
            var pp:=1.25 if phase()==3 else 1.0
            var parry_bonus:=1.5 if run.parried else 1.0;run.parried=false
            var qte:=clampf(float(input.get("qte",1)),1,2.05) if r.action=="C" else 1.0
            var damage:=C.jsround(int(r.units)*float(h.atk)*float(h.weaponMult)*(1.25 if int(h.buffUntil)>now else 1.0)*qte*(1.1 if int(h.streak)>=5 else 1.0)*weak*stagger*armour*pp*parry_bonus*(2 if int(h.rampage)>0 else 1)*(_crit(h) if r.action=="C" else 1.0)*(1.25 if r.action=="C" and r.tier=="triple" else 1.0))
            out.dealt=_boss_hit(h,damage,now);run.staggerMeter=int(run.staggerMeter)+damage
        elif r.action=="H":
            var broke:=mini(int(boss.armor),3 if r.tier=="triple" else 1);boss.armor=int(boss.armor)-broke
            if broke>0:_ult_add(5*broke)
        elif r.action=="G":run.staggerMeter=int(run.staggerMeter)+C.jsround(float(boss.max)*(0.015 if r.tier=="triple" else 0.005)*float(C.character(int(h.char)).get("gold",1)))
        elif r.action=="E":
            var pct:float=(0.15 if r.tier=="triple" else 0.05)+int(C.character(int(h.char)).get("energy",0))*0.03
            h.hp=mini(int(h.maxHp),int(h.hp)+C.jsround(float(h.maxHp)*pct))
        elif r.action=="F":
            var index:=1+int(floor(random()*19));var ally:Dictionary=s.heroes[index]
            _boss_hit(ally,C.jsround((5 if r.tier=="triple" else 2)*float(ally.atk)*float(ally.weaponMult)*(0.5 if int(boss.armor)>0 else 1.0)),now)
        if now>=int(run.staggerUntil) and float(run.staggerMeter)>=float(boss.max)*0.03:
            run.staggerMeter=0;run.staggerUntil=now+8000
            event("stagger","STAGGERED · triple damage for 8 seconds",now)
        _ult_add(8 if r.tier=="triple" else (3 if r.tier=="pair" else 1))
        if int(h.rampage)>0:h.rampage=int(h.rampage)-1
        if int(h.forcedCrits)>0:h.forcedCrits=int(h.forcedCrits)-1
        var delt:=int(boss.dmg)-int(before.dmg)
        if delt>0:progression._daily("damage",delt);progression.d.stats.damage=float(progression.d.stats.damage)+delt
        var ev:=out.duplicate(true);ev.actor=id;ev.tower=0;event("roll","Raid roll",now,ev)
    elif kind=="stored":
        var box:Dictionary=progression.gift_box();var index:=int(input.get("index",-1))
        if index<0 or index>=box.items.size():return {"ok":false,"error":"Choose a saved attack"}
        var power_amount:=int(box.items.pop_at(index));var damage:=_boss_hit(h,power_amount,now);out.dealt=damage
        if damage>0:progression._daily("damage",damage);progression.d.stats.damage=float(progression.d.stats.damage)+damage
    elif kind=="ultimate":
        if int(h.ult)<100:return {"ok":false,"error":"Ultimate is not ready"}
        h.ult=0;h.ultsUsed=int(h.ultsUsed)+1
        match int(h.char):
            0:
                run.nextStrike=now+12000;run.telegraphUntil=0
                shields(h,3,C.jsround(2*float(h.atk)*float(h.weaponMult)))
            1:h.forcedCrits=3
            2:h.rampage=5
            3:out.dealt=_boss_hit(h,C.jsround(float(boss.max)*0.04),now)
            4:
                for i in 6:out.dealt=int(out.dealt)+_boss_hit(h,C.jsround(2*float(h.atk)*float(h.weaponMult)*(0.5 if int(boss.armor)>0 else 1.0)),now)
        event("ultimate","Raid ultimate",now,{"actor":id,"tower":0})
    else:return {"ok":false,"error":"This action is not available in raids"}
    out.effects={"goldAdded":maxi(0,int(progression.d.gold)-int(before.gold)),"xpAdded":maxi(0,int(progression.d.xp)-int(before.xp)),"armorBroken":int(before.armor)-int(boss.armor),"hpGained":maxi(0,int(h.hp)-int(before.hp)),"stagger":run.staggerMeter}
    sync_boss();s.revision=int(s.revision)+1
    return {"ok":true,"result":out}
func tick(now:int)->void:
    if s.is_empty() or run.ended:return
    s.now=now
    if str(boss.date)!=C.local_day(now):end_attempt("day_changed",now);return
    if now>=int(run.until):end_attempt("time",now);sync_boss();return
    var h:=own()
    if now-int(run.botAt)>900:
        run.botAt=now
        var ally:Dictionary=s.heroes[1+int(floor(random()*19))]
        var r:=C.resolve(faces())
        if r.action in ["S","C"] and int(boss.hp)>0:
            _boss_hit(ally,C.jsround(int(r.units)*float(ally.atk)*float(ally.weaponMult)*(0.5 if int(boss.armor)>0 else 1.0)*(_crit(ally) if r.action=="C" else 1.0)),now)
            event("roll",str(ally.name)+" strikes",now,{"actor":ally.id,"tower":0,"symbol":r.action,"dealt":1,"tier":r.tier})
        elif r.action=="H" and int(boss.armor)>0 and random()<0.5:boss.armor=int(boss.armor)-1
    if run.ended:sync_boss();return
    if int(boss.hp)>0 and int(h.hp)>0:
        if int(run.telegraphUntil)==0 and now>=int(run.nextStrike):
            run.telegraphUntil=now+1300;run.parryHit=false
            event("warning","PARRY NOW",now,{"actor":"boss","tower":0})
        if int(run.telegraphUntil)>0 and now>=int(run.telegraphUntil):
            run.telegraphUntil=0;run.nextStrike=now+(3200 if phase()==3 else (4500 if phase()==2 else 6000))
            if run.parryHit:run.parried=true;event("parry","PARRY · next attack ×1.5",now,{"actor":"you","tower":0})
            else:
                var damage:=C.jsround(float(h.maxHp)*(0.35 if phase()==3 else 0.22));h.shieldSlots.sort()
                while damage>0 and not h.shieldSlots.is_empty():
                    var amount:=mini(damage,int(h.shieldSlots[0]));damage-=amount;h.shieldSlots[0]=int(h.shieldSlots[0])-amount
                    if int(h.shieldSlots[0])<=0:h.shieldSlots.pop_front()
                h.hp=maxi(0,int(h.hp)-damage)
                event("roll","Boss strikes",now,{"actor":"boss","tower":0,"symbol":"S","dealt":damage,"tier":"pair"})
                if int(h.hp)<=0:h.downUntil=now+999999;end_attempt("KO",now)
    sync_boss();s.revision=int(s.revision)+1
func export_state()->Dictionary:
    return {"seed":seed,"state":snapshot(),"run":run.duplicate(true)}
func restore(value:Dictionary)->bool:
    if not value.get("run") is Dictionary or not value.get("state") is Dictionary:return false
    run=value.run.duplicate(true);s=value.state.duplicate(true);seed=int(value.get("seed",1));sync_boss();return true
