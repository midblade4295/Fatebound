extends RefCounted
const C = preload("res://scripts/game/content.gd")
var store
var at_override := -1
var messages: Array[String] = []
var random := RandomNumberGenerator.new()
var d: Dictionary:
    get:return store.data
func _init(save_store) -> void:
    store = save_store
    random.randomize()
func now() -> int:
    return at_override if at_override >= 0 else C.now_ms()
func say(text: String) -> void:
    messages.append(text)
    if messages.size() > 20:messages.pop_front()
func perform(work: Callable) -> bool:
    messages.clear()
    if not store.transaction(work):
        if not store.last_error.is_empty():say(store.last_error)
        return false
    return true
func pool() -> int:
    return clampi(int(d.cap)-int(ceil(maxf(0,float(d.energyAt)-now())/C.REGEN_MS)),0,int(d.cap))
func fate() -> int:
    return pool()+int(d.bonus)
func _add_fate(amount: int) -> void:
    if amount <= 0:return
    var room := maxi(0,int(d.cap)-pool())
    var fill := mini(room,amount)
    if fill > 0:d.energyAt = maxi(now(),int(d.energyAt)-fill*C.REGEN_MS)
    d.bonus = int(d.bonus)+amount-fill
func _xp(amount: int) -> int:
    var before_power:=hero_power()
    var before_level:=int(d.level)
    d.xp = int(d.xp)+maxi(0,amount)
    var ups := 0
    while int(d.xp) >= C.xp_need(int(d.level)):
        d.xp = int(d.xp)-C.xp_need(int(d.level))
        d.level = int(d.level)+1
        ups += 1
    if ups > 0:
        say("Level %d reached"%int(d.level))
        _queue_level(before_level,before_power,ups)
    return ups
func _season_check() -> void:
    var sid := C.season_id(now())
    if int(d.season.id) != sid:d.season = {"id":sid,"pts":0,"free":[],"prem":[],"premium":false}
func _season_add(amount: int) -> void:
    _season_check()
    d.season.pts = int(d.season.pts)+maxi(0,amount)
func _day_check() -> void:
    var today := C.local_day(now())
    if not d.get("economyDay") is Dictionary or str(d.economyDay.get("date","")) != today:
        d.economyDay = {"date":today,"matchEnergy":0,"botEnergy":0,"returnEnergy":0,"freeGift":false}
    if str(d.daily.date) == today and not d.daily.q.is_empty():return
    var h := 0
    for letter in today:h = (h*31+letter.unicode_at(0)) & 0xffffffff
    var ids: Array = []
    var safety := 0
    while ids.size() < 3 and safety < 1000:
        # JavaScript Number multiplication before >>>0 intentionally preserved.
        h = int(float(h)*1103515245.0+12345.0) & 0xffffffff
        var index := h%9
        if not ids.has(index):ids.append(index)
        safety += 1
    assert(ids.size()==3)
    d.daily = {"date":today,"q":ids,"p":{},"done":[]}
func _daily(key: String, amount: float) -> void:
    if amount <= 0:return
    _day_check()
    d.daily.p[key] = float(d.daily.p.get(key,0))+amount
    for index in d.daily.q:
        var q: Dictionary = C.get_table("DAILY_POOL")[int(index)]
        if q.k == key and not d.daily.done.has(index) and float(d.daily.p[key]) >= float(q.need):
            d.daily.done.append(index)
            _grant(q.r)
            _season_add(3)
            say("Daily complete: "+str(q.d))
func _login() -> void:
    var today := C.local_day(now())
    if str(d.login.date) == today:return
    d.login.streak = int(d.login.streak)+1 if str(d.login.date) == C.local_day(now()-86400000) else 1
    d.login.date = today
    var old_pool := pool()
    var cap_next := 50+5*mini(10,maxi(0,int(d.login.streak)-1))+2*int(d.relics.cap)
    d.cap = maxi(int(d.cap),cap_next)
    var bonus := 5+2*mini(10,int(d.login.streak))
    var total := old_pool+bonus
    var filled := mini(int(d.cap),total)
    d.bonus = int(d.bonus)+maxi(0,total-int(d.cap))
    d.energyAt = now()+(int(d.cap)-filled)*C.REGEN_MS
    say("Day %d · +%d Fate · capacity %d"%[int(d.login.streak),bonus,int(d.cap)])
func boot() -> bool:
    return perform(func():
        _season_check()
        _day_check()
        _login()
        if d.get("pendingMatch") is Dictionary:
            var reward: Dictionary = d.pendingMatch
            d.pendingMatch = null
            d.gold = int(d.gold)+int(reward.get("gold",0))
            _add_fate(int(reward.get("energy",0)))
            if int(reward.get("season",-1)) == C.season_id(now()):_season_add(int(reward.get("pts",0)))
            var kind := str(reward.get("kind",C.shard_kind(int(d.weapon))))
            if d.shards.has(kind):d.shards[kind] = int(d.shards[kind])+int(reward.get("shards",0))
        if d.get("pendingRoll") is Dictionary:
            var pending: Dictionary = d.pendingRoll
            if d.get("war") is Dictionary and d.war.get("snapshot") is Dictionary:
                var old: Dictionary = d.war.snapshot
                if not old.get("ended",true) and (not pending.has("warId") or pending.warId == d.war.get("id")):
                    old.focus = mini(int(old.get("focusMax",8)),int(old.get("focus",0))+int(pending.get("paid",0)))
            d.pendingRoll = null
        var box := gift_box()
        if int(box.get("armed",0)) > 0:
            box.items.push_front(int(box.armed));box.armed = 0
    )
func hero_power(ci := -1, wi := -1) -> Dictionary:
    ci = int(d.char) if ci < 0 else ci
    wi = int(d.weapon) if wi < 0 else wi
    var character: Dictionary = C.character(ci)
    var weapon: Dictionary = C.weapon(wi)
    var tier: Dictionary = C.get_table("TIERS")[int(d.tiers.get(str(wi),0))]
    var attack := C.jsround((10+2*int(d.level))*float(character.atk)*(1+0.02*int(d.relics.atk)))
    var wm := float(weapon.m)*float(tier.m)
    var crit := 2+minf(3,0.1*int(d.level))+float(character.crit)+float(weapon.get("crit",0))+0.1*int(d.relics.crit)
    var perk := C.get_table("PERKS")[weapon.cls] as Dictionary
    if perk.k == "crit":crit += float(perk.v)*int(tier.get("perk",0))
    return {"atk":attack,"maxHp":C.jsround(60*(10+2*int(d.level))*float(character.hp)),"weaponMult":wm,"crit":crit,"power":C.jsround(attack*wm),"critical":C.jsround(attack*wm*crit)}
func _grant(reward: Dictionary) -> void:
    d.gold = int(d.gold)+int(reward.get("gold",0))
    d.tokens = int(d.tokens)+int(reward.get("tokens",0))
    _add_fate(int(reward.get("energy",reward.get("fate",0))))
    if int(reward.get("xp",0)) > 0:_xp(int(reward.xp))
    if int(reward.get("level",0)) > 0:
        var before_level:=int(d.level);var before_power:=hero_power()
        d.level = int(d.level)+int(reward.level)
        _queue_level(before_level,before_power,int(reward.level))
    if int(reward.get("pts",0)) > 0:_season_add(int(reward.pts))
    var kind := str(reward.get("kind",C.shard_kind(int(d.weapon))))
    if d.shards.has(kind):d.shards[kind] = int(d.shards[kind])+int(reward.get("shards",0))
    for i in int(reward.get("chest",0)):d.chests.append(make_chest())
    if reward.has("weapon") and not d.owned.has(int(reward.weapon)):d.owned.append(int(reward.weapon))
    if reward.has("title") and not d.titles.has(reward.title):d.titles.append(reward.title)
func grant(reward: Dictionary) -> bool:
    return perform(func():_grant(reward))
func set_character(index: int) -> bool:
    if index < 0 or index > 4:return false
    return perform(func():d.char = index)
func equip(index: int) -> bool:
    if not d.owned.has(index):return false
    return perform(func():d.weapon = index)
func buy_weapon(index: int) -> bool:
    if index < 0 or index > 8 or d.owned.has(index):return false
    var item: Dictionary = C.weapon(index)
    if item.has("quest") or not item.has("cost") or int(d.gold)<int(item.cost):return false
    return perform(func():
        d.gold = int(d.gold)-int(item.cost)
        d.owned.append(index)
        d.weapon = index
    )
func forge_cost(index: int) -> Dictionary:
    if not d.owned.has(index):return {}
    var tier := int(d.tiers.get(str(index),0))
    if tier>=3:return {}
    var next: Dictionary = C.get_table("TIERS")[tier+1]
    return {"tier":tier+1,"gold":int(next.gold),"shards":int(next.shards),"kind":C.shard_kind(index)}
func forge(index: int) -> bool:
    var cost := forge_cost(index)
    if cost.is_empty() or int(d.gold)<cost.gold or int(d.shards[cost.kind])<cost.shards:return false
    return perform(func():
        d.gold = int(d.gold)-int(cost.gold)
        d.shards[cost.kind] = int(d.shards[cost.kind])-int(cost.shards)
        d.tiers[str(index)] = cost.tier
    )
func buy_relic(key: String) -> bool:
    if key == "cap":return false # paused in actual v114 live shop
    var item: Dictionary = {}
    for r in C.get_table("RELICS"):
        if r.id==key:item=r
    if item.is_empty():return false
    var have := int(d.relics.get(key,0))
    var cost := int(item.cost)*(1+have)
    if have>=int(item.max) or int(d.tokens)<cost:return false
    return perform(func():
        d.tokens=int(d.tokens)-cost
        d.relics[key]=have+1
    )
func activate_premium() -> bool:
    if int(d.season.id)!=C.season_id(now()) or d.season.premium or int(d.tokens)<180:return false
    return perform(func():d.tokens=int(d.tokens)-180;d.season.premium=true)
func claim_season(index: int, premium := false) -> bool:
    if index<0 or index>=10 or int(d.season.id)!=C.season_id(now()):return false
    var tier: Array = C.get_table("SEASON_TIERS")[index]
    var track := "prem" if premium else "free"
    if int(d.season.pts)<int(tier[0]) or (premium and not d.season.premium) or d.season[track].has(index):return false
    return perform(func():
        d.season[track].append(index)
        _grant(tier[2] if premium else tier[1])
    )
func make_chest(mult := 1) -> Dictionary:
    return {"level":int(d.level),"mult":mult,"kind":C.shard_kind(int(d.weapon))}
func chest_reward(chest: Variant, bonus := 1, forced_jackpot := -1) -> Dictionary:
    var box: Dictionary = chest if chest is Dictionary else {"level":int(chest),"mult":1,"kind":C.shard_kind(int(d.weapon))}
    var jackpot := random.randi_range(0,11) in [6,7] if forced_jackpot < 0 else forced_jackpot==1
    var scale := bonus*int(box.get("mult",1))
    return {"gold":(40+10*int(box.get("level",d.level)))*(2 if jackpot else 1)*scale,"shards":(3 if jackpot else 1)*scale,"kind":str(box.get("kind",C.shard_kind(int(d.weapon)))),"jackpot":jackpot}
func open_chest(index: int, bonus := 1) -> bool:
    if index < 0 or index >= d.chests.size() or not [1,3].has(bonus):return false
    return perform(func():
        var chest: Variant = d.chests.pop_at(index)
        var reward := chest_reward(chest,bonus)
        _grant(reward)
        say("Chest opened · +%d gold · +%d %s shards"%[int(reward.gold),int(reward.shards),reward.kind])
    )
func _roll_track(amount: int, wi: int) -> void:
    if amount<=0:return
    var r: Dictionary = d.rollTrack
    r.progress = int(r.progress)+amount
    var count := int(int(r.progress)/20)
    r.progress = int(r.progress)%20
    if count>0:
        r.ready=int(r.ready)+count;r.gold=int(r.gold)+200*count
        var kind:=C.shard_kind(wi);r.shards[kind]=int(r.shards.get(kind,0))+count
        say("Roll chest saved · open Chests to collect")
func claim_roll_chests() -> bool:
    if int(d.rollTrack.ready)<=0:return false
    return perform(func():
        var r: Dictionary=d.rollTrack
        d.gold=int(d.gold)+int(r.gold)
        for key in r.shards:d.shards[key]=int(d.shards[key])+int(r.shards[key])
        r.ready=0;r.gold=0;r.shards={"steel":0,"arcane":0,"fletch":0}
    )
func check_weapon_quests(stats: Dictionary) -> void:
    # Original quest requirements are per-match bests, not lifetime summed totals.
    if not d.native.has("weaponQuestBest"):d.native.weaponQuestBest={}
    for i in 9:
        var w: Dictionary=C.weapon(i)
        if not w.has("quest"):continue
        var q: Dictionary=w.quest
        d.native.weaponQuestBest[q.k]=maxf(float(d.native.weaponQuestBest.get(q.k,0)),float(stats.get(q.k,0)))
        if float(stats.get(q.k,0))>=float(q.need) and not d.owned.has(i):
            d.owned.append(i);say(w.n+" unlocked")
func apply_receipt(receipt: Dictionary) -> bool:
    if not receipt.get("id") is String or not receipt.get("reward") is Dictionary:return false
    if d.adventure.receipts.has(receipt.id):return true
    return perform(func():
        var p: Dictionary=d.adventure
        p.receipts.append(receipt.id)
        var reward: Dictionary=receipt.reward.duplicate(true)
        var sid:=int(receipt.get("season",C.season_id(int(receipt.get("at",0)))))
        if sid!=C.season_id(now()):reward.pts=0
        reward.kind=str(receipt.get("shardKind",C.shard_kind(int(d.weapon) if str(receipt.id).begins_with("guild:") else int(receipt.get("weapon",d.weapon)))))
        _grant(reward)
        var key:=str(int(receipt.get("char",d.char)))
        if not p.mastery.has(key):p.mastery[key]={"assault":0,"guardian":0,"commander":0}
        for track in ["assault","guardian","commander"]:p.mastery[key][track]=int(p.mastery[key][track])+int(receipt.get("mastery",{}).get(track,0))
        if not str(receipt.id).begins_with("guild:") and receipt.get("stats") is Dictionary:
            var stats: Dictionary=receipt.stats
            d.stats.matches=int(d.stats.matches)+1
            if receipt.get("win",false):d.stats.wins=int(d.stats.wins)+1
            for stat in ["damage","kos","triples","rolls","flips"]:d.stats[stat]=float(d.stats.get(stat,0))+float(stats.get(stat,0))
            for pair in [["bestDmg","damage"],["bestKos","kos"],["bestTriples","triples"]]:d.stats[pair[0]]=maxf(float(d.stats.get(pair[0],0)),float(stats.get(pair[1],0)))
            if receipt.get("eligible",false) and C.local_day(int(receipt.get("at",0)))==C.local_day(now()):
                for stat in ["rolls","triples","kos","shieldsBroken","damage","gifts","flips"]:_daily(stat,float(stats.get(stat,0)))
                if receipt.get("win",false):_daily("wins",1)
    )
func mastery() -> Dictionary:
    var key:=str(int(d.char));var path_key:=str(d.adventure.path)
    var score:Dictionary=d.adventure.mastery.get(key,{"assault":0,"guardian":0,"commander":0})
    var value:=int(score.get(path_key,0));var rank:=0
    for threshold in [50,150,350,700]:
        if value>=threshold:rank+=1
    return {"scores":score,"path":path_key,"value":value,"rank":rank,"title":["Recruit","Adept","Veteran","Champion","Master"][rank],"next":[50,150,350,700,0][rank]}
func gift_box(who := "player") -> Dictionary:
    if not d.damageGifts.get(who) is Dictionary:d.damageGifts[who]={"items":[],"armed":0}
    if not d.damageGifts[who].get("items") is Array:d.damageGifts[who].items=[]
    return d.damageGifts[who]
func send_free_gift(name: String, kind: String) -> bool:
    _day_check()
    if d.economyDay.freeGift or not ["gold","energy","attack"].has(kind):return false
    return perform(func():d.economyDay.freeGift=true;_send_gift(name,kind,1))
func _send_gift(name: String, kind: String, mult: int) -> void:
    if not d.allyProgress.has(name):d.allyProgress[name]={"level":maxi(3,int(d.level)),"gold":0,"xp":0}
    if kind=="gold":d.allyProgress[name].gold=int(d.allyProgress[name].get("gold",0))+30*mult
    elif kind=="energy":d.allyRolls[name]=int(d.allyRolls.get(name,0))+3*mult
    else:gift_box("ally:"+name).items.append(500*mult)
    var due:Dictionary={"id":str(now())+"-"+str(random.randi()),"at":now()+120000+int(random.randf()*480000),"name":name}
    if random.randf()<0.25:due.damage=100*mult
    else:due.energy=mult
    d.giftsDue.append(due)
    _daily("gifts",1)
func claim_return(index: int) -> bool:
    if index<0 or index>=d.giftsDue.size():return false
    var item:Dictionary=d.giftsDue[index]
    if int(item.get("at",0))>now():return false
    _day_check()
    if int(item.get("energy",0))>0 and int(d.economyDay.returnEnergy)>=30:return false
    return perform(func():
        var g:Dictionary=d.giftsDue[index]
        if int(g.get("damage",0))>0:
            gift_box().items.append(int(g.damage));d.giftsDue.remove_at(index)
        else:
            var take:=mini(int(g.get("energy",0)),maxi(0,30-int(d.economyDay.returnEnergy)))
            _add_fate(take);d.economyDay.returnEnergy=int(d.economyDay.returnEnergy)+take
            g.energy=int(g.get("energy",0))-take
            if int(g.energy)<=0:d.giftsDue.remove_at(index)
    )
func pin_goal(index: int) -> bool:
    if index>=0 and not d.owned.has(index):return false
    return perform(func():d.adventure.goal=index if index>=0 else null)
func rank_title() -> String:
    var title:="Bronze"
    for item in C.get_table("RANKS"):
        if int(d.rank)>=int(item[1]):title=str(item[0])
    return title
func reward_text(reward: Dictionary) -> String:
    var text:Array[String]=[]
    for pair in [["gold","gold"],["energy","Fate"],["fate","Fate"],["tokens","raid tokens"],["xp","XP"],["shards","weapon shards"],["chest","stored chests"],["level","hero levels"]]:
        if int(reward.get(pair[0],0))>0:text.append("+%d %s"%[int(reward[pair[0]]),pair[1]])
    if reward.has("weapon"):text.append(str(C.weapon(int(reward.weapon)).n))
    if reward.has("title"):text.append("Title: "+str(reward.title))
    return " · ".join(text)
func _queue_level(before_level:int,before_power:Dictionary,ups:int)->void:
    var old:Variant=d.get("levelReward")
    var after:=hero_power()
    d.levelReward={"before":old.before if old is Dictionary else {"level":before_level,"attack":before_power.power,"critical":before_power.critical},"after":{"level":d.level,"attack":after.power,"critical":after.critical},"energy":int(old.get("energy",0) if old is Dictionary else 0)+3*ups,"char":d.char,"weapon":d.weapon}
func claim_level_reward()->bool:
    if not d.get("levelReward") is Dictionary:return false
    return perform(func():
        var reward:Dictionary=d.levelReward
        d.levelReward=null
        _add_fate(int(reward.get("energy",0)))
    )
