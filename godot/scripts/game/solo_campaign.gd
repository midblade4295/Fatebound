extends "res://scripts/game/arena_local.gd"
# The original 40-fighter, progression-enabled SOLO company battle.
# Distinct from equalized native Arena practice and live matchmaking.
const Factory=preload("res://scripts/game/hero_factory.gd")
var progression
var kind:="campaign"
var tutorial:=false
var pending_choices:Array=[]
var _ult_budget:=0
func configure(p)->void:progression=p
func start(now:int,initial_seed:int,training:=false)->bool:
    seed=initial_seed&0xffffffff
    if seed==0:seed=1
    tutorial=training
    var actors:Array=Factory.company(progression,random)
    s={"version":1,"balanceVersion":110,"ruleSet":"legacy-v114","id":("training-" if training else "solo-")+str(now)+"-"+str(seed),"mode":"training" if training else "campaign","practice":training,"startAt":now,"endAt":now+(86400000 if training else 300000),"regulationEnd":now+300000,"phase":"day","ended":false,"now":now,"revision":0,"events":[],"seq":0,"control":[0,0],"controlDuration":0,"rally":[null,null],"holds":[{},{}],"score":[0,0],"winner":null,"towers":[],"heroes":actors,"tally":[{"damage":0,"shields":0,"rolls":0,"kos":0},{"damage":0,"shields":0,"rolls":0,"kos":0}],"ralliesLeft":[2,2],"rallyCdUntil":[0,0],"enemyRallyMarks":[0.2,0.6],"allyRallyMarks":[0.25,0.65],"extraBotAt":now,"bulwarkUntil":0,"spellSurgeUntil":0,"exposedUntil":{},"holdUntil":{},"captureRewardAt":{},"rallyEnergyClaimed":false,"preview":false,"lastTick":now,"foeFocus":3,"foeAt":now,"objective":{"tower":5+int(floor(random()*3)),"held":[0,0],"at":now,"status":"upcoming"}}
    for i in 10:s.towers.append({"id":i,"name":ROMAN[i],"pts":3 if i>=8 else (2 if i>=5 else 1),"dmg":[0,0],"prev":-1})
    for h in actors:
        h.homeTower=h.tower;h.rallyJoin=0;h.loadout=progression.d.adventure.loadout.duplicate();h.focusAt=now;h.mult=1;h.credit={};h.bounty=false;h.rival=null
        if training:h.hp=100000;h.maxHp=100000
    own().tower=5
    if progression.d.rival!=null:
        for h in actors:
            if int(h.side)==1 and h.name==progression.d.rival:own().rival=h.id
    s.excitement={"momentum":[0,0],"surgeUntil":[0,0],"captureBuffUntil":[0,0],"captureTimes":[[],[]],"nextOrderAt":now+45000,"order":null,"orderCount":0,"lastOrderType":null,"biggestHit":null,"lastCapture":null,"clutchCapture":null,"lastAlert":null,"rivalId":null,"rivalPickAt":0}
    if not training:progression.d.stats.matches=int(progression.d.stats.matches)+1
    event("start","Brass Company · 40-fighter solo battle",now)
    return true
func own()->Dictionary:return s.heroes[0]
func perk(h:Dictionary,key:String)->float:
    var t:=int(progression.d.tiers.get(str(int(h.weapon)),0)) if h.id=="you" else int(h.tier)
    var cfg:Dictionary=C.get_table("PERKS")[C.weapon(int(h.weapon)).cls]
    if cfg.k!=key:return 0
    var value:=float(cfg.v)*int(C.get_table("TIERS")[t].get("perk",0))
    return value if key in ["crit","koEnergy"] else value/100.0
func _crit(h:Dictionary)->float:
    return 2+minf(3,0.1*int(h.level))+float(C.character(int(h.char)).crit)+float(C.weapon(int(h.weapon)).get("crit",0))+perk(h,"crit")+(0.1*int(progression.d.relics.crit)+(1 if int(h.forcedCrits)>0 else 0) if h.id=="you" else 0.0)
func _boost(side:int,now:int)->float:
    var ex:Dictionary=s.excitement
    return power(now)*(1.10 if now<int(ex.surgeUntil[side]) else 1.0)*(1.05 if now<int(ex.captureBuffUntil[side]) else 1.0)
func _team_at(tower:int,side:int,up:=false)->Array:
    var out:Array=[]
    for h in s.heroes:
        if int(h.tower)==tower and int(h.side)==side and (not up or int(h.hp)>0):out.append(h)
    return out
func _ult_add(amount:int)->void:
    var h:=own()
    if int(h.ult)>=100 or int(h.rampage)>0:return
    var n:=C.jsround(amount*(1+perk(h,"ult")))
    if not h.action.is_empty():
        n=mini(n,maxi(0,10-_ult_budget));_ult_budget+=n
    h.ult=mini(100,int(h.ult)+n)
func _momentum(side:int,n:int,now:int)->void:
    var e:Dictionary=s.excitement
    e.momentum[side]=mini(100,int(e.momentum[side])+n)
    if int(e.momentum[side])>=100:
        e.momentum[side]=15;e.surgeUntil[side]=now+12000
        event("surge","MOMENTUM SURGE · +10% damage for 12 seconds",now,{"side":side})
func _gold(h:Dictionary,amount:int)->void:
    h.gold=int(h.gold)+amount
    if h.id=="you":progression.d.gold=h.gold
    elif int(h.side)==0:progression.d.allyProgress[h.name]={"level":h.level,"gold":h.gold,"xp":h.xp}
func _refresh_hero()->void:
    var h:=own();var ratio:=float(h.hp)/maxf(1,float(h.maxHp));var p:Dictionary=progression.hero_power()
    h.level=progression.d.level;h.xp=progression.d.xp;h.gold=progression.d.gold;h.atk=p.atk;h.maxHp=p.maxHp
    if int(h.hp)>0:h.hp=C.jsround(float(h.maxHp)*ratio)
func _absorb(h:Dictionary,damage:int,attacker:Dictionary)->Dictionary:
    h.shieldSlots.sort();var left:=damage;var broken:=0
    while left>0 and not h.shieldSlots.is_empty():
        var take:=mini(left,int(h.shieldSlots[0]));h.shieldSlots[0]=int(h.shieldSlots[0])-take;left-=take
        if int(h.shieldSlots[0])<=0:h.shieldSlots.pop_front();broken+=1
    h.absorbed=float(h.get("absorbed",0))+damage-left
    if broken>0 and not attacker.is_empty():
        attacker.shieldsBroken=int(attacker.shieldsBroken)+broken;s.tally[int(attacker.side)].shields=int(s.tally[int(attacker.side)].shields)+broken
        if attacker.id=="you":progression._daily("shieldsBroken",broken);_ult_add(5*broken)
    return {"left":left,"absorbed":damage-left,"broken":broken}
func _record_damage(h:Dictionary,amount:int,ti:int)->void:
    h.damage=float(h.damage)+amount;s.tally[int(h.side)].damage=float(s.tally[int(h.side)].damage)+amount
    s.towers[ti].dmg[int(h.side)]=float(s.towers[ti].dmg[int(h.side)])+amount
func _ko(who:Dictionary,target:Dictionary,now:int)->void:
    target.hp=0;target.shieldSlots=[];target.downUntil=now+45000;who.kos=int(who.kos)+1;s.tally[int(who.side)].kos=int(s.tally[int(who.side)].kos)+1
    var ti:=int(target.tower)
    event("ko",str(who.name)+" knocked out "+str(target.name),now,{"actor":who.id,"target":target.id,"tower":ti})
    if _team_at(ti,int(target.side),true).is_empty():
        var pool:=0
        for h in _team_at(ti,int(target.side)):pool+=int(h.maxHp)
        _record_damage(who,C.jsround(pool*0.15),ti)
    if int(who.side)==1 and int(who.kos)>=2:who.bounty=true
    if target.id=="you" and int(who.side)==1:
        own().rival=who.id;progression.d.rival=who.name
    if who.id=="you":
        progression._daily("kos",1);progression.d.stats.kos=int(progression.d.stats.kos)+1;_ult_add(10)
        var g:=C.jsround((20+5*int(target.level))*float(who.action.get("mult",1)))
        if target.bounty:g*=3;target.bounty=false;who.bounties=int(who.bounties)+1;progression._daily("bounties",1)
        if who.rival==target.id:g=C.jsround(g*1.5);who.rival=null;progression.d.rival=null;_momentum(0,10,now)
        _gold(who,g)
        if random()<minf(0.95,0.15+0.05*int(progression.d.relics.lucky)):
            progression.d.chests.append(progression.make_chest(int(who.action.get("mult",1))))
            progression.say("KO chest saved · open now or hold for ×3 at match end")
    if target.bounty and who.id!="you":target.bounty=false
    _momentum(int(who.side),12,now)
func garrison_hit(who:Dictionary,ti:int,damage:int,now:int,ignore_shields:=false)->Dictionary:
    var targets:=_team_at(ti,1-int(who.side),true)
    # The web client used a random-sort comparator. A seeded Fisher-Yates order
    # chooses the same kind of randomized garrison allocation without a JS sort dependency.
    for i in range(targets.size()-1,0,-1):
        var j:=int(floor(random()*(i+1)));var item:Dictionary=targets[i];targets[i]=targets[j];targets[j]=item
    if int(who.side)==1 and ti==int(own().tower) and now<int(s.bulwarkUntil):damage=C.jsround(damage*0.5)
    var remaining:=damage;var absorbed:=0;var kos:=0
    if not ignore_shields:
        for h in targets:
            if remaining<=0:break
            var a:=_absorb(h,remaining,who);remaining=int(a.left);absorbed+=int(a.absorbed)
    var left:=remaining
    for h in targets:
        if left<=0:break
        var amount:=mini(left,int(h.hp));h.hp=int(h.hp)-amount;left-=amount
        _record_damage(who,amount,ti)
        if int(h.hp)<=0:_ko(who,h,now);kos+=1
    return {"dealt":remaining-left,"absorbed":absorbed,"kos":kos}
func _blast(who:Dictionary,ti:int,damage:int,now:int)->Dictionary:
    var foes:=_team_at(ti,1-int(who.side),true);var before:=float(who.damage)
    if foes.is_empty():_record_damage(who,damage,ti)
    else:
        var total:=0
        for h in foes:total+=maxi(1,int(h.hp))
        for h in foes:
            var take:=mini(int(h.hp),C.jsround(damage*maxi(1,int(h.hp))/float(total)));h.hp=int(h.hp)-take
            _record_damage(who,take,ti)
            if int(h.hp)<=0:_ko(who,h,now)
    return {"dealt":int(float(who.damage)-before),"absorbed":0}
func _consume_gift(h:Dictionary)->int:
    if h.id=="you":return 0 # v114 returns player armed amounts to inventory; use explicit stored action
    var box:Dictionary=progression.gift_box("ally:"+str(h.name));var n:=int(box.get("armed",0));box.armed=0;return n
func _gift_choices(mult:float,triple:bool)->void:
    var allies:=_team_at(int(own().tower),0,true)
    allies=[]
    for h in s.heroes:
        if h.id!="you" and int(h.side)==0 and int(h.hp)>0:allies.append(h)
    for i in range(allies.size()-1,0,-1):
        var j:=int(floor(random()*(i+1)));var hold:Dictionary=allies[i];allies[i]=allies[j];allies[j]=hold
    var count:=mini(3,allies.size());var kinds:Array=["gold","energy","attack"]
    for i in [2,1]:
        var j:=int(floor(random()*(i+1)));var hold:Variant=kinds[i];kinds[i]=kinds[j];kinds[j]=hold
    var bonus:=int(floor(random()*count)) if triple and count>0 else -1
    pending_choices=[]
    for i in count:pending_choices.append({"id":allies[i].id,"name":allies[i].name,"char":allies[i].char,"weapon":allies[i].weapon,"kind":kinds[i],"mult":mult*(3 if i==bonus else 1),"bonus":i==bonus})
    s.pendingGift=pending_choices.duplicate(true)
func _apply_roll(h:Dictionary,f:Array,mult:float,now:int,qte:=1.0)->Dictionary:
    var result:=C.resolve(f);var action:Variant=result.action;var triple:bool=result.tier=="triple";var me:bool=h.id=="you"
    var ti:=int(h.tower);var t:Dictionary=s.towers[ti];var sd:=int(h.side);var old_leader:=leader(t)
    var original_mult:=mult
    if me and now<int(s.spellSurgeUntil):mult*=1.25
    if sd==1 and action in ["S","C"] and now<int(s.holdUntil.get(str(ti),0)):mult*=0.5
    if sd==1 and now<int(s.exposedUntil.get(str(ti),0)):mult*=1.5
    if sd==1:s.foeFocus=maxi(0,int(s.foeFocus)-1)
    var before:Dictionary={"gold":progression.d.gold,"xp":progression.d.xp,"damage":h.damage,"focus":h.focus,"shield":shield_total(sd),"gift":h.giftDamage,"spell":h.spell,"ult":h.ult}
    h.rolls=int(h.rolls)+1;s.tally[sd].rolls=int(s.tally[sd].rolls)+1
    if triple:h.triples=int(h.triples)+1;_momentum(sd,7,now)
    if me:
        progression._daily("rolls",1);progression.d.stats.rolls=int(progression.d.stats.rolls)+1
        if triple:progression._daily("triples",1);progression.d.stats.triples=int(progression.d.stats.triples)+1
    var strike:Dictionary={"dealt":0,"absorbed":0,"kos":0}
    if action in ["S","C"]:
        var foes:=_team_at(ti,1-sd,true)
        var rally:Variant=s.rally[sd];var rmult:=1.0
        if rally is Dictionary and int(rally.tower)==ti and int(rally.until)>now:
            if not foes.is_empty() and not rally.rollers.has(h.id):rally.rollers.append(h.id)
            rmult=minf(2,1+0.1*rally.rollers.size())
        var buff:=1.25 if int(h.buffUntil)>now else 1.0
        var heat:=1.1 if me and int(h.streak)>=5 else 1.0
        var core:=int(result.units)*float(h.atk)*_boost(sd,now)*float(h.weaponMult)*buff*(qte if me and action=="C" else 1.0)*rmult*mult*heat*(_crit(h) if action=="C" else 1.0)
        if not foes.is_empty():
            core*=(1.25 if action=="C" and triple else 1.0)*(1+perk(h,"triple") if triple else 1.0)*(2 if me and int(h.rampage)>0 else 1)
            var damage:=C.jsround(core);var shield_pool:=0
            for foe in foes:
                for v in foe.shieldSlots:shield_pool+=int(v)
            if damage>shield_pool:damage+=_consume_gift(h)
            strike=garrison_hit(h,ti,damage,now)
            if me and int(strike.kos)>0 and perk(h,"koEnergy")>0:
                var raw:=minf(float(h.action.get("paid",0))*0.25,perk(h,"koEnergy")*0.05*mult*int(strike.kos))
                progression.d.energyFraction=float(progression.d.get("energyFraction",0))+raw
                var amount:=int(floor(float(progression.d.energyFraction)));progression.d.energyFraction=float(progression.d.energyFraction)-amount
                if amount>0:progression._add_fate(amount)
        else:
            var damage:=C.jsround(core*1.2*(1+perk(h,"siege")))+_consume_gift(h)
            _record_damage(h,damage,ti);strike.dealt=damage
    elif action=="H":
        var targets:=_team_at(ti,sd,true)
        if not triple:
            targets.sort_custom(func(a,b):
                var aa:=0.0;var bb:=0.0
                for v in a.shieldSlots:aa+=float(v)
                for v in b.shieldSlots:bb+=float(v)
                return aa+float(a.hp)/float(a.maxHp)<bb+float(b.hp)/float(b.maxHp)
            )
            targets=targets.slice(0,1)
        var strength:=maxi(1,C.jsround(2*float(h.atk)*float(h.weaponMult)*mult))
        for target in targets:shields(target,1,strength)
    elif action=="G":_gold(h,C.jsround(int(result.gold)*mult*float(C.character(int(h.char)).get("gold",1))))
    if me and result.tier!="none" and action!="E":h.focus=mini(8,int(h.focus)+1)
    if action=="E" and me:h.focus=mini(8,int(h.focus)+C.jsround((int(result.energy)+int(C.character(int(h.char)).get("energy",0)))*mult))
    if action=="F":
        if me:_gift_choices(mult,triple)
        elif sd==0 and random()<0.05 and progression.fate()<int(progression.d.cap) and int(progression.d.economyDay.botEnergy)<10:
            var amount:=mini(3 if triple else 1,10-int(progression.d.economyDay.botEnergy));progression.d.economyDay.botEnergy=int(progression.d.economyDay.botEnergy)+amount;progression._add_fate(amount)
    var damage_delta:=float(h.damage)-float(before.damage)
    if me and damage_delta>0:
        t.playerRewardMult=mult;progression._daily("damage",damage_delta);progression.d.stats.damage=float(progression.d.stats.damage)+damage_delta
        var biggest:Variant=s.excitement.biggestHit
        if not biggest is Dictionary or damage_delta>float(biggest.get("damage",0)):s.excitement.biggestHit={"damage":damage_delta,"at":now,"tower":ti,"critical":action=="C"}
    if me:
        if old_leader==1 and leader(t)==0 and int(h.action.get("paid",0))>0 and now>=int(s.captureRewardAt.get(str(ti),-999999999999))+30000:
            s.captureRewardAt[str(ti)]=now;h.spell=mini(2,int(h.spell)+1);h.focus=mini(8,int(h.focus)+1)
        if triple:h.spell=mini(2,int(h.spell)+(2 if int(s.endAt)-now<=30000 else 1))
        if float(h.action.get("mult",0))>=8 and result.tier=="none":s.exposedUntil[str(ti)]=now+8000
    var out:Dictionary={"type":"roll","faces":f,"tier":result.tier,"symbol":action,"mult":original_mult,"cost":h.action.get("paid",0) if me else 0,"dealt":strike.dealt,"absorbed":strike.absorbed,"effects":{"goldAdded":int(progression.d.gold)-int(before.gold),"xpAdded":0,"focusGained":maxi(0,int(h.focus)-int(before.focus)),"shieldAdded":maxi(0,shield_total(sd)-int(before.shield)),"spellAdded":maxi(0,int(h.spell)-int(before.spell)),"giftChoice":s.get("pendingGift",[]) if me else []}}
    var ev:=out.duplicate(true);ev.actor=h.id;ev.tower=ti;event("roll",str(h.name)+": "+str(result.tier)+" "+(str(action) if action!=null else "mixed"),now,ev)
    return out
func _call_rally(side:int,ti:int,now:int)->void:
    s.rally[side]={"leader":"you" if side==0 else "Crimson","tower":ti,"until":now+60000,"rollers":[]}
    s.ralliesLeft[side]=int(s.ralliesLeft[side])-1;s.rallyCdUntil[side]=now+240000
    for h in s.heroes:
        if int(h.side)!=side:continue
        h.rallyJoin=now+int(random()*15000) if random()<0.75 else now+999999999
    own().ralliesLeft=s.ralliesLeft[0];own().rallyAt=s.rallyCdUntil[0]
    event("rally",("Brass Company" if side==0 else "Crimson Vow")+" rallied Tower "+ROMAN[ti],now,{"actor":"you" if side==0 else "enemy","side":side,"tower":ti})
func act(id:String,input:Dictionary,now:int)->Dictionary:
    if s.is_empty() or s.ended:return {"ok":false,"error":"No active solo match"}
    var h:=hero(id)
    if h.is_empty():return {"ok":false,"error":"Unknown participant"}
    var me:bool=id=="you";var kind:=str(input.get("type",""))
    if kind=="gift_choice":
        var index:=int(input.get("index",-1));var choices:Array=s.get("pendingGift",[])
        if index<0 or index>=choices.size():return {"ok":false,"error":"Choose an available gift card"}
        var choice:Dictionary=choices[index];progression._send_gift(choice.name,choice.kind,int(choice.mult));own().giftsSent=int(own().giftsSent)+1;s.pendingGift=[];pending_choices=[]
        return {"ok":true,"result":{"type":kind}}
    if int(h.hp)<=0:return {"ok":false,"error":"Wait to respawn"}
    var out:Dictionary={"type":kind,"dealt":0,"absorbed":0}
    if kind=="move":
        var ti:=int(input.get("tower",-1))
        if ti<0 or ti>9:return {"ok":false,"error":"Invalid tower"}
        h.tower=ti;h.moveAt=now+300
        event("move","You moved to Tower "+ROMAN[ti],now,{"actor":id,"tower":ti})
    elif kind=="roll":
        if now<int(h.rollAt):return {"ok":false,"error":"Dice are still settling"}
        if not s.get("pendingGift",[]).is_empty():return {"ok":false,"error":"Choose a recipient for your last gift first"}
        var free:=int(h.rampage)>0;var allin:=bool(input.get("allIn",false))
        var mult:=1 if free else (maxi(4,int(h.focus)*2) if allin else int(input.get("mult",1)))
        var paid:=0 if free else (int(h.focus) if allin else mult)
        if not free and (paid<1 or int(h.focus)<paid):return {"ok":false,"error":"Not enough Focus"}
        if not free and not allin and not mult in [1,2,3,4]:return {"ok":false,"error":"Invalid multiplier"}
        h.focus=int(h.focus)-paid;h.action={"mult":mult,"paid":paid,"free":free};_ult_budget=0
        h.paidRolls=int(h.paidRolls)+(1 if paid>0 else 0);h.focusSpent=int(h.focusSpent)+paid;h.rollAt=now+1700;h.mult=mult
        var f:Array=faces()
        if h.hot:f[2]=f[0];h.hot=false;h.streak=0
        if int(h.forcedCrits)>0:
            f[2]="C"
            if f[0]!="C" and f[1]!="C":f[1]="C"
        var r:=C.resolve(f)
        if r.tier!="none" and paid>0:h.streak=int(h.streak)+1;h.hot=int(h.streak)>=10
        h.lastFaces=f
        out=_apply_roll(h,f,mult,now,clampf(float(input.get("qte",1)),1,2.05))
        _ult_add((8 if r.tier=="triple" else (3 if r.tier=="pair" else 1))*mult)
        if int(h.rampage)>0:h.rampage=int(h.rampage)-1
        if int(h.forcedCrits)>0:h.forcedCrits=int(h.forcedCrits)-1
        if paid>0:progression._xp(paid)
        progression._roll_track(paid,int(h.weapon));progression.check_weapon_quests(h)
        out.effects.xpAdded=paid
        _refresh_hero()
    elif kind=="rally":
        if int(s.ralliesLeft[0])<=0 or now<int(s.rallyCdUntil[0]):return {"ok":false,"error":"Rally is unavailable"}
        if int(h.focus)<2:return {"ok":false,"error":"Rally needs 2 Focus"}
        h.focus=int(h.focus)-2
        _call_rally(0,int(h.tower),now)
    elif kind=="spell":
        var spell:=str(input.get("spell",""))
        if not spell in SPELLS or int(h.spell)<=0 or now<int(h.spellAt):return {"ok":false,"error":"Spell needs a charge or is cooling down"}
        if spell=="horn" and (int(s.ralliesLeft[0])<=0 or now<int(s.rallyCdUntil[0])):return {"ok":false,"error":"Rally unavailable"}
        h.spell=int(h.spell)-1;h.spellAt=now+650
        if spell=="barrage":
            var before:=float(h.damage);var damage:=C.jsround(5*float(h.atk)*float(h.weaponMult)*_boost(0,now)*1.5)
            var old:Dictionary=h.action;h.action={"mult":1,"paid":0};_ult_budget=0
            if not _team_at(int(h.tower),1,true).is_empty():out.merge(garrison_hit(h,int(h.tower),damage,now),true)
            else:out.dealt=C.jsround(damage*1.2);_record_damage(h,int(out.dealt),int(h.tower))
            h.action=old;progression._daily("damage",maxf(0,float(h.damage)-before))
        elif spell=="bulwark":
            s.holdUntil[str(int(h.tower))]=now+8000
            for ally in _team_at(int(h.tower),0,true):shields(ally,1,C.jsround(4*float(h.atk)*float(h.weaponMult)))
        elif spell=="horn":_call_rally(0,int(h.tower),now)
        elif spell=="surge":h.focus=mini(8,int(h.focus)+4);s.spellSurgeUntil=now+10000
        event("spell",spell.to_upper(),now,{"actor":id,"tower":h.tower,"spell":spell})
    elif kind=="stored":
        var box:Dictionary=progression.gift_box();var index:=int(input.get("index",-1))
        if index<0 or index>=box.items.size():return {"ok":false,"error":"Choose a stored attack"}
        var damage:=int(box.items.pop_at(index));var before:=float(h.damage)
        h.action={"mult":1,"paid":0};_ult_budget=0
        if not _team_at(int(h.tower),1,true).is_empty():out.merge(garrison_hit(h,int(h.tower),damage,now),true)
        else:_record_damage(h,C.jsround(damage*1.2),int(h.tower));out.dealt=C.jsround(damage*1.2)
        var delta:=float(h.damage)-before
        if delta>0:progression._daily("damage",delta);progression.d.stats.damage=float(progression.d.stats.damage)+delta
        event("roll","STORED ATTACK",now,{"actor":id,"tower":h.tower,"symbol":"S","dealt":out.dealt,"tier":"pair"})
    elif kind=="ultimate":
        if int(h.ult)<100:return {"ok":false,"error":"Ultimate is not ready"}
        h.ult=0;h.ultsUsed=int(h.ultsUsed)+1
        var ti:=int(h.tower)
        match int(h.char):
            0:
                for ally in _team_at(ti,0):shields(ally,3 if ally.id==id else 2,C.jsround(2*float(h.atk)*float(h.weaponMult)*int(h.get("mult",1))))
                s.bulwarkUntil=now+10000
            1:h.forcedCrits=3
            2:h.rampage=5
            3:
                var pool:=0
                for foe in _team_at(ti,1):pool+=int(foe.maxHp)
                out.merge(_blast(h,ti,C.jsround(pool*0.25*_boost(0,now)),now),true)
            4:
                for i in 6:
                    var damage:=C.jsround(2*float(h.atk)*float(h.weaponMult)*_boost(0,now))
                    var hit:=garrison_hit(h,ti,damage,now)
                    if int(hit.kos)>0:progression._add_fate(3*int(hit.kos))
                    out.dealt=int(out.dealt)+int(hit.dealt);out.absorbed=int(out.absorbed)+int(hit.absorbed)
                    if hit.dealt==0 and _team_at(ti,1,true).is_empty():_record_damage(h,C.jsround(damage*1.2),ti)
        event("ultimate","ULTIMATE",now,{"actor":id,"tower":ti})
    elif kind=="rally_energy":
        if s.phase not in ["finale","overtime"] or s.rallyEnergyClaimed or progression.d.economyDay.get("rallyEnergy",false):return {"ok":false,"error":"Final-push Fate already collected today"}
        s.rallyEnergyClaimed=true;progression.d.economyDay.rallyEnergy=true;progression._add_fate(3)
    else:return {"ok":false,"error":"Unknown solo action"}
    _captures(now);update_scores();s.revision=int(s.revision)+1
    return {"ok":true,"result":out}
func _captures(now:int)->void:
    var e:Dictionary=s.excitement
    for t in s.towers:
        var lead:=leader(t);var was:=int(t.prev)
        if lead==was:continue
        t.prev=lead
        if lead<0 or was<0:continue
        var ti:=int(t.id)
        if lead==0 and int(own().tower)==ti and not t.get("playerFlipPaid",false) and float(t.get("playerRewardMult",0))>0:
            var g:=C.jsround(60*int(t.pts)*float(t.playerRewardMult));t.playerFlipPaid=true;_gold(own(),g)
            own().flips=int(own().flips)+1;progression.d.stats.flips=int(progression.d.stats.flips)+1;progression._daily("flips",1)
        _momentum(lead,18,now)
        var times:Array=[]
        for time in e.captureTimes[lead]:
            if now-int(time)<30000:times.append(time)
        times.append(now);e.captureTimes[lead]=times
        if times.size()>=2:e.captureBuffUntil[lead]=now+8000;_momentum(lead,15 if times.size()>=3 else 10,now)
        e.lastCapture={"side":lead,"tower":ti,"at":now}
        if int(s.endAt)-now<=30000:e.clutchCapture=e.lastCapture.duplicate()
        event("capture",("Brass Company" if lead==0 else "Crimson Vow")+" takes Tower "+ROMAN[ti],now,{"side":lead,"actor":"you" if lead==0 else "enemy","tower":ti})
func _orders(now:int,dt:int)->void:
    var e:Dictionary=s.excitement
    if int(s.endAt)-now<=30000:e.order=null;return
    if not e.order is Dictionary and now>=int(e.nextOrderAt):
        var types:=["capture","kos","shields","triples","hold"];var typ:String=types[int(e.orderCount)%5];e.orderCount=int(e.orderCount)+1
        var target:=5
        if typ=="capture":
            var candidates:Array=[]
            for t in s.towers:
                if leader(t)!=0:candidates.append(t)
            candidates.sort_custom(func(a,b):return int(a.pts)>int(b.pts) or (a.pts==b.pts and absf(float(a.dmg[0])-float(a.dmg[1]))<absf(float(b.dmg[0])-float(b.dmg[1]))))
            if candidates.is_empty():typ="kos"
            else:target=int(candidates[0].id)
        var base:=int(s.tally[0].kos) if typ=="kos" else (int(s.tally[0].shields) if typ=="shields" else 0)
        if typ=="triples":
            for h in s.heroes:
                if int(h.side)==0:base+=int(h.triples)
        e.order={"type":typ,"tower":target,"base":base,"need":{"capture":1,"kos":2,"shields":4,"triples":3,"hold":15000}[typ],"held":0,"progress":0,"until":now+35000,"done":false}
        e.nextOrderAt=now+45000
    if not e.order is Dictionary:return
    var order:Dictionary=e.order
    if now>=int(order.until):e.order=null;e.nextOrderAt=maxi(int(e.nextOrderAt),now+10000);return
    if order.done:return
    var val:=0
    match str(order.type):
        "capture":val=1 if leader(s.towers[int(order.tower)])==0 else 0
        "kos":val=int(s.tally[0].kos)-int(order.base)
        "shields":val=int(s.tally[0].shields)-int(order.base)
        "triples":
            for h in s.heroes:
                if int(h.side)==0:val+=int(h.triples)
            val-=int(order.base)
        "hold":
            var n:=0
            for t in s.towers:
                if int(t.pts)>=2 and leader(t)==0:n+=1
            if n>=2:order.held=int(order.held)+mini(500,dt)
            val=int(order.held)
    order.progress=maxi(0,val)
    if val>=int(order.need):order.done=true;_gold(own(),30);_momentum(0,18,now);event("order","COMPANY ORDER COMPLETE · +30 gold",now)
func tick(now:int)->void:
    if s.is_empty() or s.ended:return
    var prev:=int(s.now);var dt:=clampi(now-prev,0,5000);s.now=now
    if not tutorial:
        var bankdt:=maxi(0,mini(now,int(s.startAt)+240000)-mini(prev,int(s.startAt)+240000))
        s.controlDuration=int(s.controlDuration)+bankdt
        for sd in 2:s.control[sd]=float(s.control[sd])+points(sd)*bankdt
    var player:=own()
    var n:=int(floor(float(now-int(player.focusAt))/14000))
    if n>0:player.focus=mini(8,int(player.focus)+n);player.focusAt=int(player.focusAt)+n*14000
    for h in s.heroes:
        if int(h.hp)<=0 and now>=int(h.downUntil):h.hp=h.maxHp;h.shieldSlots=[];h.downUntil=0;event("respawn",str(h.name)+" returned",now,{"actor":h.id})
        if h.bot:
            var rally:Variant=s.rally[int(h.side)]
            h.tower=int(rally.tower) if rally is Dictionary and now<int(rally.until) and now>=int(h.rallyJoin) else int(h.homeTower)
    if tutorial:s.revision=int(s.revision)+1;return
    var before_phase:=str(s.phase)
    if s.phase!="overtime":s.phase="finale" if now>=int(s.startAt)+240000 else ("pressure" if now>=int(s.startAt)+120000 else "day")
    if before_phase!=s.phase:event("phase",str(s.phase).to_upper(),now)
    var rate:=1.2 if s.phase=="overtime" else (1.0 if s.phase=="finale" else (0.85 if s.phase=="pressure" else 0.65))
    for side in 2:
        var bots:Array=[]
        for h in s.heroes:
            if int(h.side)==side and h.id!="you" and int(h.hp)>0:bots.append(h)
        var rally:Variant=s.rally[side]
        var live:bool=rally is Dictionary and now<int(rally.until)
        var count:=rate*dt/1000.0*(2 if live else 1)
        while count>0 and not bots.is_empty():
            if random()>count:break
            count-=1
            var h:Dictionary=bots[int(floor(random()*bots.size()))]
            var box:Dictionary=progression.gift_box("ally:"+str(h.name))
            if not box.items.is_empty() and int(box.get("armed",0))==0:box.armed=int(box.items.pop_front())
            _apply_roll(h,faces(),1,now)
    if now-int(s.extraBotAt)>=1000:
        s.extraBotAt=now
        for h in s.heroes:
            if h.id!="you" and int(h.side)==0 and int(h.hp)>0 and int(progression.d.allyRolls.get(h.name,0))>0:
                progression.d.allyRolls[h.name]=int(progression.d.allyRolls[h.name])-1;_apply_roll(h,faces(),1,now);break
    var elapsed:float=float(now-int(s.startAt))/maxf(1,float(int(s.endAt)-int(s.startAt)))
    for sd in [1,0]:
        var marks:Array=s.enemyRallyMarks if sd==1 else s.allyRallyMarks
        var rally:Variant=s.rally[sd]
        if not marks.is_empty() and elapsed>=float(marks[0]) and int(s.ralliesLeft[sd])>0 and (not rally is Dictionary or now>=int(rally.until)) and now>=int(s.rallyCdUntil[sd]):
            marks.pop_front();var candidate:=0;var low:=INF
            for ti in 10:
                var hp:=0
                for h in _team_at(ti,1-sd):
                    if h.id!="you":hp+=maxi(0,int(h.hp))
                if hp<low:candidate=ti;low=hp
            _call_rally(sd,candidate,now)
    _captures(now);_orders(now,dt)
    _supply(now,dt)
    update_scores()
    if s.phase=="overtime" and (s.score[0]!=s.score[1] or now>=int(s.endAt)):finish(now)
    elif now>=int(s.endAt):
        if not s.preview and s.score[0]==s.score[1]:s.phase="overtime";s.endAt=now+60000;event("phase","SUDDEN DEATH",now)
        else:finish(now)
    s.revision=int(s.revision)+1
func _supply(now:int,dt:int)->void:
    var o:Dictionary=s.objective;var since:=now-int(s.startAt)
    if since>=105000 and o.status=="upcoming":o.status="warning";event("objective","Supply cache soon at Tower "+ROMAN[int(o.tower)],now,{"tower":o.tower})
    if since>=120000 and o.status=="warning":o.status="active"
    if o.status=="active":
        var lead:=leader(s.towers[int(o.tower)])
        if lead>=0:o.held[lead]=float(o.held[lead])+mini(1000,dt)
        if since>=150000:
            o.status="complete";var winner:=0 if o.held[0]>o.held[1] else (1 if o.held[1]>o.held[0] else -1)
            if winner==0:own().focus=mini(8,int(own().focus)+1);own().spell=mini(2,int(own().spell)+1)
            o.winner=winner
            event("objective","Supply cache secured" if winner==0 else "Supply objective ended",now,{"tower":o.tower,"side":winner})
func finish(now:int)->void:
    if s.ended:return
    update_scores();s.ended=true;s.phase="complete";s.completedAt=now
    var h:=own();var allies:Array=[]
    for a in s.heroes:
        if int(a.side)==0:allies.append(a)
    var win:bool=s.score[0]>s.score[1] or (s.score[0]==s.score[1] and float(s.tally[0].damage)>float(s.tally[1].damage))
    s.winner=0 if win else 1
    var ranked:=allies.duplicate();ranked.sort_custom(func(a,b):return float(a.damage)>float(b.damage))
    var broken:=allies.duplicate();broken.sort_custom(func(a,b):return int(a.shieldsBroken)>int(b.shieldsBroken))
    var eligible:bool=not tutorial and not s.preview and int(h.paidRolls)>=5 and now>=int(s.endAt)
    var champ:bool=eligible and float(h.damage)>0 and ranked[0].id==h.id
    var breaker:bool=eligible and int(h.shieldsBroken)>0 and broken[0].id==h.id
    var top3:=false
    for a in ranked.slice(0,3):
        if a.id==h.id and float(h.damage)>0 and eligible:top3=true
    progression._day_check()
    var fate_reward:=mini(5 if win else 2,maxi(0,20-int(progression.d.economyDay.matchEnergy))) if eligible else 0
    progression.d.economyDay.matchEnergy=int(progression.d.economyDay.matchEnergy)+fate_reward
    var reward:Dictionary={"gold":(180 if win else 80) if eligible else 0,"energy":fate_reward,"pts":((10 if win else 5)+(5 if champ else 0)+(3 if breaker else 0)) if eligible else 0,"shards":((4 if win else 2)+(4 if top3 else 0)+(4 if champ else 0)) if eligible else 0,"kind":C.shard_kind(int(h.weapon)),"season":C.season_id(now)}
    progression.d.pendingMatch=reward.duplicate(true)
    if win and eligible:progression.d.stats.wins=int(progression.d.stats.wins)+1;progression._daily("wins",1)
    for pair in [["bestDmg","damage"],["bestKos","kos"],["bestTriples","triples"]]:progression.d.stats[pair[0]]=maxf(float(progression.d.stats[pair[0]]),float(h[pair[1]]))
    var delta:=((25 if win else -10)+(10 if champ else 0)+(5 if int(h.kos)>=3 else 0)) if eligible else 0
    progression.d.rank=maxi(0,int(progression.d.rank)+delta)
    if not progression.d.ladder is Array:
        progression.d.ladder=[]
        for i in 9:progression.d.ladder.append({"n":C.get_table("NAMES")[i],"p":C.jsround(20+i*38+random()*30)})
    for entry in progression.d.ladder:entry.p=maxi(0,int(entry.p)+C.jsround((random()-0.35)*20))
    var held_rewards:Array=[]
    if not s.preview:
        var held:Array=progression.d.chests.duplicate(true);progression.d.chests=[]
        for chest in held:
            var r:Dictionary=progression.chest_reward(chest,3);progression._grant(r);held_rewards.append(r)
    var stats:=h.duplicate(true)
    stats.gifts=h.giftsSent
    s.completedResult={"id":s.id,"win":win,"draw":false,"score":s.score.duplicate(),"side":0,"eligible":eligible,"char":h.char,"weapon":h.weapon,"practice":tutorial,"reward":reward,"stats":stats,"champion":ranked[0].name,"breaker":broken[0].name,"rankDelta":delta,"heldChests":held_rewards,"highlights":s.excitement.duplicate(true),"tip":"Opening control + final tower points ×2","scenario":{"tower":h.tower,"deficit":maxf(0,float(s.towers[int(h.tower)].dmg[1])-float(s.towers[int(h.tower)].dmg[0]))}}
    event("end","VICTORY" if win else "DEFEAT",now)
func result(_id:String)->Dictionary:return s.get("completedResult",{}).duplicate(true)
func restore(value:Dictionary)->bool:
    if not value.get("state") is Dictionary or value.state.get("ruleSet","")!="legacy-v114":return false
    s=value.state.duplicate(true);seed=int(value.get("seed",12345));tutorial=s.get("mode","")=="training";return true
