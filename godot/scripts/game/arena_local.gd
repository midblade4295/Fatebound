extends RefCounted
# A direct native port of arena-engine.js for OFFLINE PRACTICE only.
# Online combat always remains on the authoritative server.
const C=preload("res://scripts/game/content.gd")
const CREDIT_KEYS=["damage","absorbed","shieldsBroken","kos","rolls","paidRolls","triples","focusSpent","goldEarned","xpEarned","flips","defenseSeconds","rallyAssists","gifts","giftsSent","spellsCast","ultsUsed"]
const SPELLS=["barrage","bulwark","horn","surge"]
const ROMAN=["I","II","III","IV","V","VI","VII","VIII","IX","X"]
var s:Dictionary={}
var seed:=12345
var forced_faces:Array=[]
var error:=""
func new_credit()->Dictionary:
    var out:Dictionary={}
    for key in CREDIT_KEYS:out[key]=0
    return out
func random()->float:
    var x:int=seed
    x=(x^(x<<13))&0xffffffff
    x=(x^(x>>17))&0xffffffff
    x=(x^(x<<5))&0xffffffff
    seed=x
    return float(seed)/4294967296.0
func faces()->Array:
    if not forced_faces.is_empty():return forced_faces.duplicate()
    var symbols:Array=["S","C","H","G","E","F"]
    var bucket:=random()
    var a:Variant=symbols.pop_at(int(floor(random()*symbols.size())))
    var f:Array=[a,a,a]
    if bucket>=0.15:
        if bucket<0.70:f=[a,a,symbols.pop_at(int(floor(random()*symbols.size())))]
        else:f=[a,symbols.pop_at(int(floor(random()*symbols.size()))),symbols.pop_at(int(floor(random()*symbols.size()))) ]
    for i in [2,1]:
        var j:=int(floor(random()*(i+1)))
        var hold:Variant=f[i];f[i]=f[j];f[j]=hold
    return f
func init_match(id:String,players:Array,now:int,initial_seed:=12345,mode:="standard",duration:=300000,practice:=true,scenario:Dictionary={})->void:
    assert(players.size()==20)
    seed=initial_seed&0xffffffff
    if seed==0:seed=1
    s={"version":1,"balanceVersion":110,"id":id,"mode":mode,"practice":practice,"startAt":now,"endAt":now+duration,"regulationEnd":now+duration,"phase":"day","ended":false,"now":now,"revision":0,"events":[],"seq":0,"control":[0,0],"controlDuration":0,"rally":[null,null],"holds":[{},{}],"score":[0,0],"winner":null,"objective":{"tower":5+int(floor(random()*3)),"warnAt":now+105000,"startAt":now+120000,"endAt":now+150000,"held":[0,0],"status":"upcoming","winner":null},"towers":[],"heroes":[]}
    for i in 10:s.towers.append({"id":i,"name":ROMAN[i],"pts":3 if i>=8 else (2 if i>=5 else 1),"dmg":[0,0],"prev":-1})
    var counts:=[0,0]
    for i in players.size():
        var p:Dictionary=players[i]
        var sd:=i%2;var ci:=clampi(int(p.get("char",0)),0,4);var ch:Dictionary=C.character(ci)
        var hp:=C.jsround(1800*float(ch.hp))
        var loadout:Array=["barrage","bulwark"] if mode=="draft" else p.get("loadout",["barrage","bulwark"]).duplicate()
        var h:Dictionary={"id":p.id,"name":str(p.get("name","Player")).left(24),"bot":bool(p.get("bot",false)),"substitute":false,"connected":not p.get("bot",false),"side":sd,"char":ci,"weapon":clampi(int(p.get("weapon",0)),0,8),"level":10,"atk":C.jsround(30*float(ch.atk)),"maxHp":hp,"hp":hp,"weaponMult":1,"tier":0,"tower":counts[sd],"shieldSlots":[],"downUntil":0,"focus":4,"focusAt":now,"spell":0,"loadout":loadout,"ult":0,"forcedCrits":0,"rampage":0,"surgeUntil":0,"rollAt":now,"nextBot":now+2500+i*173,"lastSeen":now,"moveAt":0,"spellAt":0,"ultAt":0,"rallyAt":0,"ralliesLeft":2,"hot":false,"streak":0,"lastFaces":null,"credit":new_credit(),"captureRewardAt":{},"storedDamage":0,"giftDamage":0}
        for key in CREDIT_KEYS:h[key]=0
        s.heroes.append(h);counts[sd]+=1
    if mode=="ward":
        for h in s.heroes:shields(h,1,60)
    if not scenario.is_empty() and practice:
        var ti:=clampi(int(scenario.get("tower",0)),0,9)
        s.heroes[0].tower=ti;s.heroes[1].tower=ti
        s.towers[ti].dmg=[0,maxi(0,int(scenario.get("deficit",180)))]
    event("start","20 combatants · 5-minute battle",now)
    update_scores()
func event(kind:String,text:String,now:int,extra:Dictionary={})->void:
    s.seq=int(s.seq)+1
    var e:Dictionary={"seq":s.seq,"type":kind,"text":text,"at":now}
    e.merge(extra,true);s.events.append(e)
    if s.events.size()>80:s.events.pop_front()
func hero(id:String)->Dictionary:
    for h in s.heroes:
        if h.id==id:return h
    return {}
func leader(t:Dictionary)->int:
    return 0 if float(t.dmg[0])>float(t.dmg[1]) else (1 if float(t.dmg[1])>float(t.dmg[0]) else -1)
func points(side:int)->int:
    var total:=0
    for t in s.towers:
        if leader(t)==side:total+=int(t.pts)
    return total
func update_scores()->void:
    s.score=[0,0]
    for side in 2:s.score[side]=C.jsround((float(s.control[side])/float(s.controlDuration) if s.controlDuration else 0.0)+points(side)*2)
func bump(h:Dictionary,key:String,amount:float)->void:
    h[key]=float(h.get(key,0))+amount
    if not h.bot and not h.substitute:
        h.credit[key]=float(h.credit.get(key,0))+amount
func shields(h:Dictionary,count:int,strength:int)->int:
    var gained:=0
    for i in count:
        if h.shieldSlots.size()<3:h.shieldSlots.append(strength);gained+=strength
        else:
            var weak:Variant=h.shieldSlots.min();var index:int=h.shieldSlots.find(weak)
            if strength>weak:h.shieldSlots[index]=strength;gained+=strength-int(weak)
    return gained
func shield_total(side:int)->int:
    var value:=0
    for h in s.heroes:
        if int(h.side)==side:
            for v in h.shieldSlots:value+=int(v)
    return value
func hit(who:Dictionary,amount:float,now:int,ignore_shield:=false,reward_capture:=false)->Dictionary:
    var ti:=int(who.tower);var side:=int(who.side);var t:Dictionary=s.towers[ti];var before:=leader(t)
    var foes:Array=[]
    for h in s.heroes:
        if int(h.side)!=side and int(h.tower)==ti and float(h.hp)>0:foes.append(h)
    var damage:=C.jsround(amount);var absorbed:=0;var dealt:=0
    if float(s.holds[1-side].get(str(ti),s.holds[1-side].get(ti,0)))>now:damage=C.jsround(damage*0.5)
    if foes.is_empty():
        dealt=C.jsround(damage*1.2);t.dmg[side]=float(t.dmg[side])+dealt;bump(who,"damage",dealt)
    else:
        for h in foes:
            if damage<=0:break
            h.shieldSlots.sort()
            while not ignore_shield and damage>0 and not h.shieldSlots.is_empty():
                var v:=mini(damage,int(h.shieldSlots[0]));h.shieldSlots[0]=int(h.shieldSlots[0])-v;damage-=v;absorbed+=v;bump(h,"absorbed",v)
                if int(h.shieldSlots[0])<=0:h.shieldSlots.pop_front();bump(who,"shieldsBroken",1)
            if damage<=0:break
            var take:=mini(damage,int(h.hp));h.hp=int(h.hp)-take;damage-=take;dealt+=take;bump(who,"damage",take);t.dmg[side]=float(t.dmg[side])+take
            if int(h.hp)<=0:
                h.downUntil=now+45000;h.shieldSlots=[];bump(who,"kos",1)
                event("ko",str(who.name)+" defeated "+str(h.name),now,{"actor":who.id,"target":h.id,"tower":ti})
        var wiped:=true;var pool:=0
        for h in foes:
            if float(h.hp)>0:wiped=false
            pool+=int(h.maxHp)
        if wiped:
            var breach:=C.jsround(pool*0.15);t.dmg[side]=float(t.dmg[side])+breach;bump(who,"damage",breach);dealt+=breach
    var after:=leader(t)
    if after!=before and after==side:
        if before!=-1:bump(who,"flips",1)
        t.prev=after
        var eligible:=reward_capture and before!=-1 and now>=int(who.captureRewardAt.get(str(ti),-999999999999))+30000
        if eligible:
            who.focus=mini(8,int(who.focus)+1);who.spell=mini(2,int(who.spell)+1);who.captureRewardAt[str(ti)]=now
        event("capture","Tower "+str(t.name)+" captured"+(" · +1 Focus and spell charge" if eligible else ""),now,{"actor":who.id,"side":side,"tower":ti,"rewarded":eligible})
    return {"dealt":dealt,"absorbed":absorbed}
func power(now:int)->float:
    var elapsed:=now-int(s.startAt)
    return 1.5 if elapsed>=240000 else (1.15 if elapsed>=120000 else 1.0)
func _rally(h:Dictionary,now:int,free:=false)->void:
    if not free:h.focus=int(h.focus)-2
    h.ralliesLeft=int(h.ralliesLeft)-1;h.rallyAt=now+60000
    s.rally[int(h.side)]={"leader":h.id,"tower":h.tower,"until":now+60000,"rollers":[]}
    for b in s.heroes:
        if int(b.side)==int(h.side) and b.bot and random()<0.45:b.tower=h.tower
    event("rally",str(h.name)+" rallied Tower "+ROMAN[int(h.tower)],now,{"actor":h.id,"side":h.side,"tower":h.tower})
func _validate(h:Dictionary,input:Dictionary,now:int)->String:
    if h.is_empty():return "Not in this match"
    if s.ended:return "Match has ended"
    if int(h.hp)<=0:return "Wait to respawn"
    var kind:=str(input.get("type",""))
    if kind=="move":
        if not input.get("tower") in range(10):return "Invalid tower"
        if now<int(h.moveAt):return "Moving too fast"
    elif kind=="roll":
        if now<int(h.rollAt):return "Dice are still settling"
        if input.has("allIn") and not input.allIn is bool:return "Invalid ALL-IN flag"
        if not input.get("mult",1) in [1,2,3,4]:return "Multiplier must be an integer from 1 to 4"
        var free:=int(h.rampage)>0
        if not free:
            if input.get("allIn",false):
                if int(h.focus)<3:return "Multiplier unavailable"
            elif int(h.focus)<int({1:0,2:2,3:4,4:6}[int(input.get("mult",1))]):return "Multiplier unavailable"
            if int(h.focus)<(int(h.focus) if input.get("allIn",false) else int(input.get("mult",1))):return "Not enough Focus"
    elif kind=="spell":
        if not h.loadout.has(input.get("spell")):return "Spell is not equipped"
        if int(h.spell)<=0:return "No spell charges"
        if now<int(h.spellAt):return "Spell is cooling down"
        if input.spell=="horn" and (now<int(h.rallyAt) or int(h.ralliesLeft)<=0):return "Rally unavailable"
    elif kind=="rally":
        if now<int(h.rallyAt):return "Rally is cooling down"
        if int(h.ralliesLeft)<=0:return "No rallies remaining"
        if int(h.focus)<2:return "Rally needs 2 Focus"
    elif kind=="gift":
        if int(h.giftDamage)<=0:return "No stored attack to send"
        var target:=hero(str(input.get("target","")))
        if target.is_empty() or target.id==h.id or target.side!=h.side:return "Choose a teammate"
        if int(target.storedDamage)>=int(target.maxHp)*2:return "That teammate already has a full stored-attack bank"
    elif kind=="stored":
        if int(h.storedDamage)<=0:return "No stored attack"
    elif kind=="ultimate":
        if int(h.ult)<100:return "Ultimate is not ready"
    else:return "Unknown action"
    return ""
func act(id:String,input:Dictionary,now:int)->Dictionary:
    var h:=hero(id);error=_validate(h,input,now)
    if not error.is_empty():return {"ok":false,"error":error}
    var kind:=str(input.type);var result:Dictionary={"type":kind}
    var before:Dictionary={"focus":h.focus,"spell":h.spell,"ult":h.ult,"gift":h.giftDamage,"gold":h.credit.goldEarned,"xp":h.credit.xpEarned,"shield":shield_total(int(h.side))}
    if kind=="move":h.tower=int(input.tower);h.moveAt=now+700;result.tower=h.tower
    elif kind=="roll":
        var free:=int(h.rampage)>0;var allin:=bool(input.get("allIn",false))
        var mult:=1 if free else (maxi(4,int(h.focus)*2) if allin else int(input.get("mult",1)))
        var cost:=0 if free else (int(h.focus) if allin else mult)
        h.focus=int(h.focus)-cost;bump(h,"focusSpent",cost);h.rollAt=now+2200;bump(h,"rolls",1)
        if cost>0 and not h.bot and not h.substitute:bump(h,"paidRolls",1);bump(h,"xpEarned",cost)
        var enchanted:=int(h.forcedCrits)>0;var f:=faces()
        if h.hot:f[2]=f[0];h.hot=false;h.streak=0
        if int(h.forcedCrits)>0:
            f[2]="C"
            if f[0]!="C" and f[1]!="C":f[1]="C"
            h.forcedCrits=int(h.forcedCrits)-1
        var r:=C.resolve(f);h.lastFaces=f;var triple:bool=r.tier=="triple"
        if triple:bump(h,"triples",1);h.spell=mini(2,int(h.spell)+(2 if int(s.endAt)-now<=30000 else 1))
        if r.tier!="none" and cost>0:
            h.streak=int(h.streak)+1
            if int(h.streak)>=10:h.hot=true
        var surge:=1.25 if now<int(h.surgeUntil) else 1.0
        var rally:Variant=s.rally[int(h.side)]
        var rally_here:bool=rally is Dictionary and rally.tower==h.tower and float(rally.until)>now
        var rm:=minf(2,1+0.1*rally.rollers.size()) if rally_here else 1.0
        if rally_here and h.id!=rally.leader and not rally.rollers.has(h.id):rally.rollers.append(h.id);bump(hero(rally.leader),"rallyAssists",1)
        var strike:Dictionary={"dealt":0,"absorbed":0};var action:Variant=r.action;var ch:Dictionary=C.character(int(h.char))
        if action in ["S","C"]:
            var amount:=int(r.units)*float(h.atk)*mult*surge*rm*power(now)*(1.1 if int(h.streak)>=5 else 1.0)*(2 if int(h.rampage)>0 else 1)*(3+float(ch.crit)+(1 if enchanted else 0) if action=="C" else 1.0)*(1.25 if action=="C" and triple else 1.0)
            strike=hit(h,amount,now,false,cost>0)
        elif action=="H":
            if triple:
                for a in s.heroes:
                    if a.side==h.side and a.tower==h.tower and float(a.hp)>0:shields(a,1,C.jsround(2*float(h.atk)*mult*surge))
            else:shields(h,1,C.jsround(2*float(h.atk)*mult*surge))
        elif action=="E":h.focus=mini(8,int(h.focus)+C.jsround(((5 if triple else 1)+int(ch.get("energy",0)))*mult*surge))
        elif action=="F":h.giftDamage=mini(int(h.maxHp)*2,int(h.giftDamage)+C.jsround(int(r.units)*float(h.atk)*mult*surge*power(now)*1.25));bump(h,"gifts",1)
        elif action=="G":bump(h,"goldEarned",C.jsround(int(r.gold)*mult*surge*float(ch.get("gold",1))))
        if r.tier!="none" and action!="E":h.focus=mini(8,int(h.focus)+1)
        if int(h.rampage)>0:h.rampage=int(h.rampage)-1
        else:h.ult=mini(100,int(h.ult)+mini(10,(8 if triple else (3 if r.tier=="pair" else 1))*mult))
        result.merge({"faces":f,"tier":r.tier,"symbol":action,"mult":mult,"cost":cost},true);result.merge(strike,true)
        var extra:=result.duplicate(true);extra.actor=id;extra.tower=h.tower
        event("roll",str(h.name)+": "+str(r.tier)+" "+(str(action) if action!=null else "mixed"),now,extra)
    elif kind=="spell":
        var spell:=str(input.spell);h.spell=int(h.spell)-1;bump(h,"spellsCast",1);h.spellAt=now+650
        if spell=="barrage":result.merge(hit(h,5*float(h.atk)*1.5*power(now),now),true)
        if spell=="bulwark":
            s.holds[int(h.side)][str(int(h.tower))]=now+8000
            for a in s.heroes:
                if a.side==h.side and a.tower==h.tower and float(a.hp)>0:shields(a,1,int(h.atk)*4)
        if spell=="horn":_rally(h,now,true)
        if spell=="surge":h.focus=mini(8,int(h.focus)+4);h.surgeUntil=now+10000
        event("spell",str(h.name)+": "+{"barrage":"Barrage","bulwark":"Bulwark","horn":"War Horn","surge":"Arcane Surge"}[spell],now,{"actor":id,"tower":h.tower,"spell":spell})
    elif kind=="rally":_rally(h,now)
    elif kind=="gift":
        var target:=hero(str(input.target));var sent:=mini(maxi(0,int(target.maxHp)*2-int(target.storedDamage)),int(h.giftDamage))
        target.storedDamage=int(target.storedDamage)+sent;h.giftDamage=int(h.giftDamage)-sent;bump(h,"giftsSent",1);result.sent=sent
        event("gift",str(h.name)+" sent an attack to "+str(target.name),now,{"actor":id,"target":target.id})
    elif kind=="stored":result.merge(hit(h,float(h.storedDamage),now),true);h.storedDamage=0
    elif kind=="ultimate":
        h.ult=0;bump(h,"ultsUsed",1)
        match int(h.char):
            0:
                s.holds[int(h.side)][str(int(h.tower))]=now+10000
                for a in s.heroes:
                    if a.side==h.side and a.tower==h.tower:shields(a,3 if a.id==id else 2,int(h.atk)*2)
            1:h.forcedCrits=3
            2:h.rampage=5
            3:
                var pool:=0
                for a in s.heroes:
                    if a.side!=h.side and a.tower==h.tower:pool+=int(a.maxHp)
                result.merge(hit(h,pool*0.25*power(now),now,true),true)
            4:
                var old_kos:=int(h.kos)
                for i in 6:hit(h,float(h.atk)*2*power(now),now)
                h.focus=mini(8,int(h.focus)+3*(int(h.kos)-old_kos))
        event("ultimate",str(h.name)+" used an ultimate",now,{"actor":id,"tower":h.tower})
    if kind in ["roll","spell","ultimate"]:
        result.effects={"focusBefore":before.focus,"focusAfter":h.focus,"focusGained":maxi(0,int(h.focus)-int(before.focus)+int(result.get("cost",0))),"shieldAdded":maxi(0,shield_total(int(h.side))-int(before.shield)),"giftAdded":maxi(0,int(h.giftDamage)-int(before.gift)),"goldAdded":maxi(0,mini(1500,int(h.credit.goldEarned))-mini(1500,int(before.gold))),"xpAdded":maxi(0,mini(150,int(h.credit.xpEarned))-mini(150,int(before.xp))),"spellAdded":maxi(0,int(h.spell)-int(before.spell)),"ultAdded":maxi(0,int(h.ult)-int(before.ult)),"tower":h.tower,"paidRolls":h.credit.paidRolls}
    s.revision=int(s.revision)+1;update_scores();return {"ok":true,"result":result}
func tick(now:int)->void:
    if s.is_empty() or s.ended:return
    var prev:=int(s.now);var dt:=clampi(now-prev,0,5000);s.now=now
    var bank_to:=mini(now,int(s.startAt)+240000);var bank_from:=mini(prev,int(s.startAt)+240000);var bank_dt:=maxi(0,bank_to-bank_from)
    s.controlDuration=int(s.controlDuration)+bank_dt
    for side in 2:s.control[side]=float(s.control[side])+points(side)*bank_dt
    var regen:=7000 if s.mode=="focus" else 14000
    for h in s.heroes:
        if int(h.hp)<=0 and now>=int(h.downUntil):
            h.hp=h.maxHp;h.downUntil=0;event("respawn",str(h.name)+" returned",now,{"actor":h.id})
        var n:=int(floor(float(now-int(h.focusAt))/regen))
        if n>0:h.focus=mini(8,int(h.focus)+n);h.focusAt=int(h.focusAt)+n*regen
        var contested:=false
        for a in s.heroes:
            if a.side!=h.side and a.tower==h.tower and int(a.hp)>0:contested=true;break
        if int(h.hp)>0 and leader(s.towers[int(h.tower)])==int(h.side) and contested:bump(h,"defenseSeconds",float(dt)/1000)
    var o:Dictionary=s.objective
    if o.status=="upcoming" and now>=int(o.warnAt):o.status="warning";event("objective","Supply objective at Tower "+ROMAN[int(o.tower)]+" in 15 seconds",now,{"tower":o.tower})
    if o.status=="warning" and now>=int(o.startAt):o.status="active";event("objective","Hold Tower "+ROMAN[int(o.tower)]+" for the supply bonus",now,{"tower":o.tower})
    if o.status=="active":
        var side:=leader(s.towers[int(o.tower)])
        if side>=0:o.held[side]=int(o.held[side])+maxi(0,mini(now,int(o.endAt))-maxi(prev,int(o.startAt)))
        if now>=int(o.endAt):
            o.status="complete";o.winner=0 if float(o.held[0])>float(o.held[1]) else (1 if float(o.held[1])>float(o.held[0]) else null)
            if o.winner!=null:
                for h in s.heroes:
                    if h.side==o.winner:h.focus=mini(8,int(h.focus)+1);h.spell=mini(2,int(h.spell)+1)
            event("objective","Supply objective tied — no bonus" if o.winner==null else "Supply objective secured · +1 Focus and spell charge",now,{"side":o.winner,"tower":o.tower})
    var old_phase:=str(s.phase)
    if s.phase!="overtime":s.phase="finale" if now>=int(s.startAt)+240000 else ("pressure" if now>=int(s.startAt)+120000 else "day")
    if old_phase!=s.phase:event("phase","FINAL MINUTE · attack ×1.5" if s.phase=="finale" else "PRESSURE RISING · attack ×1.15",now)
    for h in s.heroes:
        if not(h.bot or h.substitute) or int(h.hp)<=0 or now<int(h.nextBot):continue
        h.nextBot=now+2600+int(floor(random()*2700))
        if h.bot:
            if o.status=="active" and random()<0.4:h.tower=o.tower
            elif random()<0.12:h.tower=int(floor(random()*10))
        var action_result:Dictionary={"ok":true}
        if int(h.ult)>=100:action_result=act(h.id,{"type":"ultimate"},now)
        elif int(h.spell)>0 and random()<0.4:action_result=act(h.id,{"type":"spell","spell":h.loadout[int(floor(random()*2))]},now)
        elif int(h.focus)>=1 or int(h.rampage)>0:action_result=act(h.id,{"type":"roll","mult":2 if int(h.focus)>=4 and random()<0.4 else 1},now)
        if not action_result.get("ok",false):continue # mirrors the JS try/catch around the entire bot turn
        if int(h.giftDamage)>0:
            var eligible:Array=[]
            for a in s.heroes:
                if a.id!=h.id and a.side==h.side and int(a.hp)>0 and int(a.storedDamage)<int(a.maxHp)*2:eligible.append(a)
            var idx:=int(floor(random()*eligible.size()))
            if not eligible.is_empty():
                action_result=act(h.id,{"type":"gift","target":eligible[idx].id},now)
                if not action_result.get("ok",false):continue
        if int(h.storedDamage)>0:act(h.id,{"type":"stored"},now)
    update_scores()
    if s.phase=="overtime" and (s.score[0]!=s.score[1] or now>=int(s.endAt)):finish(now)
    elif now>=int(s.endAt):
        if s.score[0]==s.score[1]:s.phase="overtime";s.endAt=now+60000;event("phase","SUDDEN DEATH · next crown lead wins",now)
        else:finish(now)
    s.revision=int(s.revision)+1
func finish(now:int)->void:
    if s.ended:return
    update_scores()
    var damage:=[0.0,0.0]
    for h in s.heroes:damage[int(h.side)]+=float(h.damage)
    s.winner=0 if s.score[0]>s.score[1] else (1 if s.score[1]>s.score[0] else (0 if damage[0]>damage[1] else (1 if damage[1]>damage[0] else null)))
    s.ended=true;s.phase="complete";s.completedAt=now
    event("end","DRAW" if s.winner==null else "MATCH COMPLETE",now,{"winner":s.winner})
func result(id:String)->Dictionary:
    var actor:=hero(id)
    if not s.ended or actor.is_empty():return {}
    var h:=actor.duplicate(true);h.merge(actor.credit,true)
    var eligible:=not bool(s.practice) and int(h.paidRolls)>=5;var win:bool=s.winner==h.side
    var champ:=float(h.damage)>0;var breaker:=float(h.shieldsBroken)>0
    for a in s.heroes:
        if a.side!=h.side:continue
        var compare:Dictionary=a.duplicate(true)
        if not a.bot:compare.merge(a.credit,true)
        if float(compare.damage)>float(h.damage):champ=false
        if float(compare.shieldsBroken)>float(h.shieldsBroken):breaker=false
    var mastery:Dictionary={"assault":mini(60,int(floor(float(h.damage)/150))),"guardian":mini(60,int(floor(float(h.absorbed)/100))+int(floor(float(h.defenseSeconds)/15))),"commander":mini(60,int(h.rallyAssists)*3+int(h.flips)*2)}
    var stats:Dictionary={}
    for key in ["damage","absorbed","rallyAssists","flips","rolls","paidRolls","triples","kos","shieldsBroken"]:stats[key]=h[key]
    stats.defenseSeconds=int(floor(float(h.defenseSeconds)));stats.gifts=h.giftsSent;stats.spells=h.spellsCast
    var tip:="You finished with %d unused spell charge%s."%[int(h.spell),"" if int(h.spell)==1 else "s"] if int(h.spell)>0 else ("Try rotating to a contested objective before the final minute." if int(h.flips)==0 else "Review your final tower choice and try a different spell pairing.")
    return {"id":s.id,"char":h.char,"weapon":h.weapon,"balanceVersion":110,"completedAt":s.completedAt,"eligible":eligible,"practice":s.practice,"win":win,"draw":s.winner==null,"score":s.score.duplicate(),"side":h.side,"mastery":mastery,"stats":stats,"tip":tip,"scenario":{"tower":h.tower,"deficit":maxf(0,float(s.towers[int(h.tower)].dmg[1-int(h.side)])-float(s.towers[int(h.tower)].dmg[int(h.side)]))},"reward":{"gold":(180 if win else 80)+mini(1500,int(h.goldEarned)) if eligible else 0,"fate":(5 if win else 2) if eligible else 0,"pts":(10 if win else 5)+(5 if champ else 0)+(3 if breaker else 0) if eligible else 0,"shards":(4 if win else 2) if eligible else 0,"xp":mini(150,int(h.xpEarned)) if eligible else 0}}
func snapshot()->Dictionary:
    return s.duplicate(true)
func export_state()->Dictionary:
    return {"seed":seed,"state":snapshot()}
func restore(value:Dictionary)->bool:
    if not value.get("state") is Dictionary or int(value.state.get("version",0))!=1 or (value.state.get("heroes",[]) as Array).size()!=20:return false
    s=value.state.duplicate(true);seed=int(value.get("seed",12345));return true
