extends RefCounted
const C=preload("res://scripts/game/content.gd")
static func make(progress,side:int,index:int,level:int,is_you:bool,random:Callable)->Dictionary:
    var ci:=int(progress.d.char) if is_you else int(floor(float(random.call())*5))
    var wi:=int(progress.d.weapon) if is_you else mini(8,int(floor(float(random.call())*9*level/8.0)))
    var character:Dictionary=C.character(ci)
    var tier:=int(progress.d.tiers.get(str(wi),0)) if is_you else 0
    if not is_you and level>=5:
        var r:=float(random.call());tier=3 if r<0.04 else (2 if r<0.16 else (1 if r<0.4 else 0))
    var attack:=C.jsround((10+2*level)*float(character.atk))
    var hp:=C.jsround(60*(10+2*level)*float(character.hp))
    if is_you:attack=C.jsround(attack*(1+0.02*int(progress.d.relics.atk)))
    return {"id":"you" if is_you else str(side)+str(index),"name":"You" if is_you else str(C.get_table("NAMES")[(side*20+index)%40]),"side":side,"level":level,"char":ci,"weapon":wi,"atk":attack,"maxHp":hp,"hp":hp,"tier":tier,"weaponMult":float(C.weapon(wi).m)*float(C.get_table("TIERS")[tier].m),"bot":not is_you,"substitute":false,"connected":is_you,"shieldSlots":[],"downUntil":0,"damage":0,"absorbed":0,"shieldsBroken":0,"kos":0,"triples":0,"rolls":0,"paidRolls":0,"focusSpent":0,"gold":int(progress.d.gold) if is_you else 0,"xp":int(progress.d.xp) if is_you else 0,"tower":0,"rallyJoin":0,"focus":4,"focusAt":progress.now(),"spell":0,"spellAt":0,"ralliesLeft":2,"rallyAt":0,"rollAt":0,"moveAt":0,"ult":0,"ultsUsed":0,"streak":0,"hot":false,"lastFaces":null,"giftDamage":0,"storedDamage":0,"forcedCrits":0,"rampage":0,"buffUntil":0,"surgeUntil":0,"flips":0,"bounties":0,"giftsSent":0,"qteMult":1.0,"action":{}}
static func company(progress,random:Callable)->Array:
    var heroes:Array=[]
    heroes.append(make(progress,0,0,int(progress.d.level),true,random))
    for i in range(1,20):heroes.append(make(progress,0,i,maxi(3,int(progress.d.level)-2+int(floor(float(random.call())*5))),false,random))
    for i in 20:heroes.append(make(progress,1,i,maxi(3,int(progress.d.level)-2+int(floor(float(random.call())*5))),false,random))
    for h in heroes:
        if h.bot and int(h.side)==0 and progress.d.allyProgress.get(h.name) is Dictionary:
            var saved:Dictionary=progress.d.allyProgress[h.name]
            h.level=maxi(int(h.level),int(saved.get("level",h.level)));h.gold=int(saved.get("gold",0));h.xp=int(saved.get("xp",0))
            var character:Dictionary=C.character(int(h.char))
            h.atk=C.jsround((10+2*int(h.level))*float(character.atk));h.maxHp=C.jsround(60*(10+2*int(h.level))*float(character.hp));h.hp=h.maxHp
    for sd in 2:
        var list:Array=[]
        for h in heroes:
            if h.bot and int(h.side)==sd:list.append(h)
        list.sort_custom(func(a,b):return int(a.level)>int(b.level))
        for k in list.size():list[k].tower=9-int(k/2)
    return heroes
