extends RefCounted
const C=preload("res://scripts/game/content.gd")
const Raid=preload("res://scripts/game/raid.gd")
const Factory=preload("res://scripts/game/hero_factory.gd")
var app
var result_claimed:=false
var chat_edit:TextEdit
var chat_timer:Timer
var _guild_tab:="overview"
var _cloud_text:=""
var profile_status:Label
var live_guild_box:VBoxContainer
var p:
    get:return app.active_p
var d:Dictionary:
    get:return p.d
func label(parent:Node,text:String,size:=13,color:=Color("#c5d6d4")) -> Label:
    var l:Label=app._label(text,size,color,true);parent.add_child(l);return l
func button(parent:Node,text:String,call:Callable,enabled:=true,key:="")->Button:
    return app.action_button(parent,text,call,enabled,key)
func card(parent:Node,title:String,text:="")->VBoxContainer:return app.card(parent,title,text)
func bar(parent:Node,value:float,total:float)->ProgressBar:
    var b:=ProgressBar.new();b.custom_minimum_size.y=10;b.show_percentage=false;b.max_value=maxf(1,total);b.value=clampf(value,0,total);parent.add_child(b);return b
func show(route:String)->void:
    if route!="guild":chat_edit=null
    match route:
        "home":home()
        "hero":hero()
        "shop":shop()
        "guild":guild()
        "friends":friends()
        "season":season()
        "quests":quests()
        "stats":stats()
        "prepare":prepare()
        "raid":raid()
        "chests":chests()
        "settings":settings()
        "live_guild":live_guild()
        _:home()
func home()->void:
    var body:VBoxContainer=app._shell("FATEBOUND","home")
    if not app.trainer.active and not app.api.is_local():
        var daily_raid=Raid.new();daily_raid.configure(p);daily_raid.ensure_day()
    var banner:=card(body,"Day %d · %s %d"%[int(d.login.streak),p.rank_title(),int(d.rank)],"Brass Company · Your adventure")
    app.portrait(banner,int(d.char),int(d.weapon),225)
    var pow:Dictionary=p.hero_power()
    label(banner,"%s · %s\n%d attack power · %d critical damage · %d health"%[C.character(int(d.char)).n,C.weapon(int(d.weapon)).n,int(pow.power),int(pow.critical),int(pow.maxHp)])
    if not app.save_store.writable:
        label(body,app.save_store.last_error,14,Color("#ffb49d"))
        button(body,"OPEN SAVE RECOVERY",func():app._go("settings"),true,"recover_save")
        return
    if d.get("levelReward") is Dictionary:
        button(body,"LEVEL UP · COLLECT +%d FATE"%int(d.levelReward.get("energy",0)),level_reward,true,"level_reward")
    var battle:=card(body,"READY FOR BATTLE","5-minute matches · free entry · Focus powers your rolls")
    button(battle,"PREPARE & MATCHMAKE",func():app._go("prepare"),not app.trainer.active,"prepare")
    if app.trainer.active:button(battle,"RETURN TO TRAINING BATTLE",func():app.training_show_target("battle"),true,"training_return")
    var links:HBoxContainer=app._row(body)
    button(links,"DAILY RAID",func():app._go("raid"),not app.trainer.active,"raid")
    button(links,"CHESTS %d"%(d.chests.size()+int(d.rollTrack.ready)),func():app._go("chests"),true,"chests")
    var academy:=card(body,"HERO ACADEMY","Learn by playing: Focus, ALL-IN, lanes, crowns, spells, stored attacks and upgrades.")
    button(academy,"REPLAY TRAINING" if d.get("tutorialBattle",{}).get("done",false) else "CONTINUE BATTLE TRAINING",app.begin_training,not app.trainer.active,"training")
    var daily:=card(body,"DAILY QUESTS · %d / 3 COMPLETE"%(d.daily.done as Array).size())
    for id in d.daily.q:
        var q:Dictionary=C.get_table("DAILY_POOL")[int(id)]
        label(daily,"%s  %s"%["✓" if d.daily.done.has(int(id)) else "•",q.d],12)
    button(daily,"QUESTS & REWARDS",func():app._go("quests"),true,"quests")
    var season_box:=card(body,"SEASON %d · %s"%[int(d.season.id)+1,C.get_table("SEASON_NAMES")[int(d.season.id)%6]],"%d season points · Free and premium tracks"%int(d.season.pts))
    button(season_box,"VIEW SEASON PASS",func():app._go("season"),true,"season")
    var mastery:Dictionary=p.mastery()
    var goal:=card(body,"%s %s"%[mastery.title,C.character(int(d.char)).n],"%s mastery · %d points"%[str(mastery.path).capitalize(),int(mastery.value)])
    if d.adventure.get("goal")!=null:
        var wi:=int(d.adventure.goal)
        if wi>=0 and wi<9:
            var cost:Dictionary=p.forge_cost(wi)
            if not cost.is_empty():label(goal,"Upgrade goal: %s · %d/%d %s shards · %d/%d gold"%[C.weapon(wi).n,int(d.shards[cost.kind]),int(cost.shards),cost.kind,int(d.gold),int(cost.gold)])
    button(goal,"HERO & ARMORY",func():app._go("hero"))
    var bottom:HBoxContainer=app._row(body)
    button(bottom,"STATS & RANK",func():app._go("stats"))
    button(bottom,"SETTINGS & SAVES",func():app._go("settings"),true,"settings")
    var due:=0
    for item in d.giftsDue:
        if int(item.get("at",0))<=p.now():due+=1
    if due>0:button(body,"%d RETURN GIFTS READY"%due,func():app._go("friends"))
    if app.api.online_profile.get("pendingRewards",0)>0:button(body,"ONLINE REWARDS WAITING",pending_rewards)
    label(body,"Native conversion 0.3 · Original v114 equipment, rewards and game rules",10,Color("#809e9f"))
func hero()->void:
    var body:VBoxContainer=app._shell("HERO & ARMORY","hero")
    var current:Dictionary=C.character(int(d.char));var pow:Dictionary=p.hero_power()
    var box:=card(body,str(current.n),str(current.d))
    if d.get("levelReward") is Dictionary:button(box,"COLLECT LEVEL REWARD",level_reward,true,"level_reward")
    app.portrait(box,int(d.char),int(d.weapon),195)
    label(box,"POWER %d · CRITICAL %d · HEALTH %d"%[int(pow.power),int(pow.critical),int(pow.maxHp)],14,Color("#f1dda3"))
    if d.get("boss") is Dictionary and d.boss.get("killed",false) and d.boss.get("killer","")=="You" and str(d.boss.date)==C.local_day(p.now()):label(box,"SLAYER OF "+str(d.boss.name).to_upper()+" · TODAY",13,Color("#ffc780"))
    label(box,"Level %d · XP %d / %d"%[int(d.level),int(d.xp),C.xp_need(int(d.level))])
    bar(box,float(d.xp),C.xp_need(int(d.level)))
    var pick:=OptionButton.new();pick.fit_to_longest_item=false;pick.clip_text=true;pick.custom_minimum_size.y=46
    for i in 5:pick.add_item(str(C.character(i).n))
    pick.selected=int(d.char);pick.item_selected.connect(func(i):app.mutate(func():return p.set_character(i),"Hero changed",true));box.add_child(pick)
    var ultimate:Dictionary=C.get_table("ULTS")[current.id]
    label(box,str(ultimate.n)+"\n"+str(ultimate.d),13,Color("#b7d9eb"))
    label(body,"Equip any owned weapon on any hero. Forged gear and relics affect solo battles and raids. Online matches remain equalized at level 10.",12)
    for i in 9:
        var item:Dictionary=C.weapon(i);var owned:bool=d.owned.has(i);var tier:=int(d.tiers.get(str(i),0));var t:Dictionary=C.get_table("TIERS")[tier]
        var cell:=card(body,str(item.n)+" · "+str(t.n),"Attack ×%.2f%s"%[float(item.m)*float(t.m)," · +%.1f critical multiplier"%float(item.crit) if item.has("crit") else ""])
        if owned:
            var row:HBoxContainer=app._row(cell)
            button(row,"EQUIPPED" if int(d.weapon)==i else "EQUIP",_equip.bind(i),int(d.weapon)!=i,"equip_"+str(i))
            var cost:Dictionary=p.forge_cost(i)
            if cost.is_empty():label(cell,"LEGENDARY · maximum quality",13,Color("#f7cf80"))
            else:
                label(cell,"Next: %s · %d %s shards + %d gold"%[C.get_table("TIERS")[int(cost.tier)].n,int(cost.shards),cost.kind,int(cost.gold)])
                var can:bool=int(d.gold)>=int(cost.gold) and int(d.shards[cost.kind])>=int(cost.shards)
                button(row,"FORGE",_forge.bind(i),can,"forge_"+str(i))
                button(cell,"PIN UPGRADE GOAL",_pin.bind(i))
            if int(t.get("perk",0))>0:
                var perk:Dictionary=C.get_table("PERKS")[item.cls]
                var val:float=float(perk.v)*int(t.perk)*(5 if perk.k=="koEnergy" else 1)
                label(cell,str(perk.d).replace("{v}",str(val)),12,Color("#bcb1eb"))
        elif item.has("quest"):
            var q:Dictionary=item.quest;var best:=float(d.native.get("weaponQuestBest",{}).get(q.k,0))
            label(cell,"QUEST · "+str(q.d),13,Color("#e2c88f"));bar(cell,best,float(q.need))
            label(cell,"Best qualifying solo match: %d / %d"%[int(best),int(q.need)],11)
        else:button(cell,"BUY & EQUIP · %d GOLD"%int(item.get("cost",0)),_buy_weapon.bind(i),int(d.gold)>=int(item.get("cost",0)),"buy_weapon_"+str(i))
    var mastery:Dictionary=p.mastery();var masterybox:=card(body,"MASTERY · "+str(mastery.title),"Cosmetic ranks from qualifying online matches. No hidden power advantage.")
    var paths:HBoxContainer=app._row(masterybox)
    for key in ["assault","guardian","commander"]:button(paths,str(key).capitalize(),_mastery_path.bind(key))
    for key in ["assault","guardian","commander"]:label(masterybox,"%s: %d"%[str(key).capitalize(),int(mastery.scores.get(key,0))])
    if int(mastery.next)>0:bar(masterybox,int(mastery.value),int(mastery.next));label(masterybox,"Next rank at %d"%int(mastery.next))
    if not d.titles.is_empty():label(masterybox,"Titles: "+", ".join(d.titles))
    var actions:HBoxContainer=app._row(body)
    button(actions,"DAILY QUESTS",func():app._go("quests"))
    button(actions,"STATS",func():app._go("stats"))
func _equip(i:int)->void:app.mutate(func():return p.equip(i),"Equipped "+str(C.weapon(i).n))
func _forge(i:int)->void:app.mutate(func():return p.forge(i),"Forging complete" )
func _pin(i:int)->void:app.mutate(func():return p.pin_goal(i),"Upgrade goal pinned")
func _buy_weapon(i:int)->void:app.mutate(func():return p.buy_weapon(i),"Bought and equipped "+str(C.weapon(i).n))
func _mastery_path(key:String)->void:app.mutate(func():return p.perform(func():d.adventure.path=key),"Mastery path selected")
func shop()->void:
    var body:VBoxContainer=app._shell("SHOP","shop")
    if app.trainer.active:
        var demo:=card(body,"PRACTICE PURCHASE ONLY","This demonstration uses the temporary training save. Your real balances will not change.")
        button(demo,"+10 FATE · 300 PRACTICE GOLD",func():
            if int(d.gold)<300:return
            if app.mutate(func():return p.perform(func():d.gold=int(d.gold)-300;p._add_fate(10)),"Practice Fate +10"):
                app.trainer.notify("practice_purchase")
        ,int(d.gold)>=300,"training_flask")
    else:
        card(body,"FATE & TEMPORARY BOOST SALES PAUSED","The original v114 build has no active Fate-spending feature. Existing Fate and cap bonuses are preserved. Home combat consumables were not carried into a new match, so those purchases remain disabled.")
    var box:=card(body,"RELICS · %d RAID TOKENS"%int(d.tokens),"Permanent solo/raid upgrades. Online fair-play battles do not use these bonuses.")
    for r in C.get_table("RELICS"):
        if r.id=="cap":continue
        var have:=int(d.relics[r.id]);var cost:=int(r.cost)*(1+have)
        var relic:=card(box,str(r.n)+" · %d/%d"%[have,int(r.max)],str(r.d))
        button(relic,"MAXIMUM" if have>=int(r.max) else "BUY · %d TOKENS"%cost,_relic.bind(str(r.id)),have<int(r.max) and int(d.tokens)>=cost,"relic_"+str(r.id))
    var weapons:=card(body,"WEAPONS & FORGING","Weapons, shard requirements, quest unlocks and quality tiers are in your armory.")
    button(weapons,"OPEN ARMORY",func():app._go("hero"))
    var premium:=card(body,"SEASON PREMIUM · 180 RAID TOKENS","An in-game token purchase, not a real-money payment. Unlocks the premium reward track for the current season.")
    button(premium,"OPEN SEASON PASS",func():app._go("season"))
func _relic(key:String)->void:app.mutate(func():return p.buy_relic(key),"Relic upgraded")
func season()->void:
    p.perform(func():p._season_check())
    var body:VBoxContainer=app._shell("SEASON PASS","season")
    var sid:=int(d.season.id);var title:=str(C.get_table("SEASON_NAMES")[sid%6])
    var hours:=maxi(0,int(ceil(float(ContentTimeEnd(sid)-p.now())/3600000)))
    var head:=card(body,"SEASON %d · %s"%[sid+1,title],"%d season points · ends in %d hours"%[int(d.season.pts),hours])
    label(head,"Earn points from qualifying battles, daily quests and raid milestones. Fate rewards are your stored balance, not match Focus. Claims are saved immediately.")
    button(head,"PREMIUM ACTIVE" if d.season.premium else "UNLOCK PREMIUM · 180 TOKENS",func():app.mutate(func():return p.activate_premium(),"Premium unlocked for this season"),not d.season.premium and int(d.tokens)>=180,"premium")
    for i in 10:
        var tier:Array=C.get_table("SEASON_TIERS")[i]
        var unlocked:bool=int(d.season.pts)>=int(tier[0])
        var cell:=card(body,"TIER %d · %d POINTS"%[i+1,int(tier[0])])
        bar(cell,int(d.season.pts),int(tier[0]))
        label(cell,"FREE · "+p.reward_text(tier[1]),13)
        button(cell,"CLAIMED" if d.season.free.has(i) else "CLAIM FREE",_claim_season.bind(i,false),unlocked and not d.season.free.has(i),"season_free_"+str(i))
        label(cell,"PREMIUM · "+p.reward_text(tier[2]),13,Color("#ccb6ec"))
        button(cell,"CLAIMED" if d.season.prem.has(i) else "CLAIM PREMIUM",_claim_season.bind(i,true),unlocked and d.season.premium and not d.season.prem.has(i),"season_prem_"+str(i))
func ContentTimeEnd(sid:int)->int:return C.SEASON_EPOCH+(sid+1)*C.SEASON_MS
func _claim_season(i:int,premium:bool)->void:app.mutate(func():return p.claim_season(i,premium),"Season reward saved")
func quests()->void:
    p.perform(func():p._day_check())
    var body:VBoxContainer=app._shell("QUESTS","quests")
    card(body,"DAY %d · %d/3 DAILY QUESTS"%[int(d.login.streak),d.daily.done.size()],"Daily rewards are paid automatically when complete, plus 3 season points per quest. They reset at local midnight.")
    for id in d.daily.q:
        var q:Dictionary=C.get_table("DAILY_POOL")[int(id)];var value:=float(d.daily.p.get(q.k,0));var done:bool=d.daily.done.has(int(id))
        var cell:=card(body,("✓ " if done else "")+str(q.d),p.reward_text(q.r)+" · +3 season points")
        bar(cell,value,float(q.need));label(cell,"COMPLETE" if done else "%d / %d"%[int(value),int(q.need)])
    card(body,"EQUIPMENT QUESTS","These use your best qualifying solo match, not lifetime totals. Online alpha does not directly unlock permanent weapons.")
    for i in 9:
        var w:Dictionary=C.weapon(i)
        if not w.has("quest"):continue
        var q:Dictionary=w.quest;var best:=float(d.native.get("weaponQuestBest",{}).get(q.k,0))
        var cell:=card(body,str(q.d),"Unlock: "+str(w.n));bar(cell,best,float(q.need));label(cell,"UNLOCKED" if d.owned.has(i) else "%d / %d"%[int(best),int(q.need)])
    button(body,"PLAY A SOLO COMPANY BATTLE",func():app.start_local("campaign"),not app.trainer.active)
func stats()->void:
    var body:VBoxContainer=app._shell("RECORD & RANK","stats")
    var st:Dictionary=d.stats
    var box:=card(body,p.rank_title()+" · %d rank points"%int(d.rank),"Local solo league. Online equalized matches contribute to your record/mastery but do not change this local ladder.")
    for row in [["Battles",st.matches],["Wins",st.wins],["Best damage",st.bestDmg],["Best knockouts",st.bestKos],["Best triples",st.bestTriples],["Lifetime damage",st.damage],["Lifetime knockouts",st.kos],["Lifetime triples",st.triples],["Lifetime rolls",st.rolls],["Tower flips",st.flips]]:label(box,"%s · %d"%[row[0],int(row[1])],14)
    var ladder:Array=d.ladder.duplicate(true) if d.ladder is Array else []
    ladder.append({"n":"You","p":int(d.rank)});ladder.sort_custom(func(a,b):return float(a.p)>float(b.p))
    var list:=card(body,"SOLO LEAGUE LADDER","Other entries are simulated company rivals.")
    for i in ladder.size():label(list,"#%d · %s · %d"%[i+1,ladder[i].n,int(ladder[i].p)])
    if not d.titles.is_empty():card(body,"EARNED TITLES",", ".join(d.titles))
func prepare()->void:
    var body:VBoxContainer=app._shell("PREPARE FOR BATTLE","prepare")
    var box:=card(body,"CHOOSE YOUR TWO SPELLS","Barrage attacks; Bulwark shields; War Horn rallies; Arcane Surge returns Focus and boosts results. Both share the two-charge bank.")
    var row:HBoxContainer=app._row(box)
    var picks:Array[OptionButton]=[]
    for slot in 2:
        var choice:=OptionButton.new();choice.fit_to_longest_item=false;choice.clip_text=true;choice.custom_minimum_size.y=46;choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
        for key in app.SPELLS:choice.add_item(app.SPELL_NAMES[key])
        choice.selected=maxi(0,app.SPELLS.find(str(d.adventure.loadout[slot])));picks.append(choice);row.add_child(choice)
    button(box,"SAVE LOADOUT",func():
        var loadout:Array=[app.SPELLS[picks[0].selected],app.SPELLS[picks[1].selected]]
        if loadout[0]==loadout[1]:app.flash_message("Choose two different spells.");return
        app.mutate(func():return p.perform(func():d.adventure.loadout=loadout),"Spell loadout saved",false)
    )
    var online:=card(body,"ONLINE · FAIR-PLAY SKIRMISH","Search for 20 seconds, then fill empty slots with labelled bots. 20 fighters, 10 per team. The server owns HP, rolls, respawns, rewards and scores. No leaving for Home during the match.")
    button(online,"FIND ONLINE BATTLE",app.start_online,not app.trainer.active,"online_queue")
    var solo:=card(body,"SOLO COMPANY BATTLE","The original progression-enabled game: 40 simulated fighters, your hero level, all weapon qualities/relics, timed critical strikes, orders, momentum, stored gifts, loot chests and local rank.")
    button(solo,"START 5-MINUTE SOLO BATTLE",func():app.start_local("campaign"),not app.trainer.active,"solo_start")
    var practice:=card(body,"PRACTICE · NO REWARDS","Equalized native version of the online rules. Useful for experimenting without changing resources, rank or mastery.")
    button(practice,"STANDARD PRACTICE",func():app.start_local("practice"),not app.trainer.active,"practice_start")
    var daily:String=["focus","draft","ward"][int(floor(float(p.now())/86400000))%3]
    label(practice,"Today's trial: "+{"focus":"Focus Rush · Focus regenerates twice as fast","draft":"Fixed Loadout · Barrage + Bulwark","ward":"Guardian Trial · start with a shield"}[str(daily)],13)
    button(practice,"PLAY DAILY TRIAL",func():app.start_local("practice",{"mode":daily}),not app.trainer.active,"daily_trial")
    var moment:Variant=d.adventure.get("lastMoment")
    if moment is Dictionary:
        button(practice,"RETRY LAST TOWER · 60s PRACTICE",func():app.start_local("practice",{"duration":60000,"scenario":moment}),not app.trainer.active,"last_moment")
    button(body,"LIVE GUILD EXPEDITION",func():app._go("live_guild"),not app.trainer.active)
    button(body,"UNCLAIMED ONLINE REWARDS",pending_rewards,not app.trainer.active)
    var name:=LineEdit.new();name.text=str(d.native.name);name.max_length=24;name.placeholder_text="Local hero / new account name";name.custom_minimum_size.y=44;body.add_child(name)
    button(body,"SAVE LOCAL NAME",func():app.mutate(func():return p.perform(func():d.native.name=name.text.strip_edges().left(24)),"Local name saved; existing online guest names are unchanged",false))
func raid()->void:
    var manager=Raid.new();manager.configure(p)
    if not app.trainer.active:manager.ensure_day()
    var body:VBoxContainer=app._shell("DAILY RAID","raid")
    var b:Variant=d.boss
    if not b is Dictionary:
        label(body,"Daily raid is not available in the training sandbox.");return
    var head:=card(body,str(b.name),"Daily solo raid · simulated company support · resets at local midnight. The live guild expedition is a separate online system.")
    app.portrait(head,int(b.char),int(b.weapon),175)
    label(head,"%d / %d health · phase %d"%[maxi(0,int(b.hp)),int(b.max),manager.phase()],16,Color("#edcd9b"));bar(head,float(b.hp),float(b.max))
    label(head,"WEAK FACE: %s · ARMOUR %d/4\nWeak-face pairs/triples hit ×2. Shield results strip armour. Damage equal to 3%% max HP staggers for 8 seconds of ×3 attacks. Parry during the wind-up or take the boss's hit."%["CRITICAL" if b.weak=="C" else "SWORD",int(b.armor)])
    button(head,"SLAIN TODAY" if b.killed else "FIGHT · %d ATTEMPTS LEFT"%maxi(0,3-int(b.attempts)),func():app.start_local("raid"),not b.killed and int(b.attempts)<3 and not app.trainer.active,"raid_start")
    var tiers:=card(body,"PERSONAL DAMAGE · %d"%int(b.dmg))
    for i in 4:
        var t:Array=C.get_table("BOSS_TIERS")[i];var need:=maxi(1000,C.jsround(float(b.max)*float(t[0])))
        label(tiers,"%s %d damage · %d gold · %d tokens · %d XP"%["✓" if b.tiers.has(i) else "•",need,int(t[1]),int(t[2]),int(t[3])]);bar(tiers,float(b.dmg),need)
    label(tiers,"Kill qualification: contribute at least 2% max HP for 5 tokens, a chest and 90 XP. The last hit awards today's Slayer title.")
    var milestones:=card(body,"COMPANY RAID MILESTONES","Contribute damage to qualify. Rewards are collected automatically once per milestone.")
    for i in 4:
        var t:Array=C.get_table("BOSS_MILESTONES")[i]
        label(milestones,"%s %d%% · %d gold · %d tokens · %d shards · %d season pts"%["✓" if b.get("milestones",[]).has(i) else "•",int(float(t[0])*100),int(t[1]),int(t[2]),int(t[3]),int(t[4])])
    var ranks:Array=[]
    for name in b.clan:ranks.append({"name":name,"damage":b.clan[name]})
    ranks.append({"name":"You","damage":b.dmg});ranks.sort_custom(func(a,c):return float(a.damage)>float(c.damage))
    var rankbox:=card(body,"SIMULATED COMPANY CONTRIBUTIONS","Next-day placing pays 5 / 3 / 2 / 1 tokens by rank if you contributed damage.")
    for i in ranks.size():label(rankbox,"#%d · %s · %d"%[i+1,ranks[i].name,int(ranks[i].damage)],12)
func chests()->void:
    var body:VBoxContainer=app._shell("SAVED CHESTS","chests")
    chests_content(body,false)
func chests_content(parent:Node,battle:bool)->void:
    var box:=card(parent,"ROLL CHESTS · %d READY"%int(d.rollTrack.ready),"Each 20 paid Focus in solo battles banks 200 gold and one matching weapon shard. Chests stay saved until collected.")
    bar(box,int(d.rollTrack.progress),20);label(box,"%d / 20 · %d gold stored"%[int(d.rollTrack.progress),int(d.rollTrack.gold)])
    button(box,"COLLECT ROLL CHESTS",func():
        if app.mutate(func():return p.claim_roll_chests(),"Roll chests collected",not battle) and battle:app._battle_inventory()
    ,int(d.rollTrack.ready)>0 and not app.busy,"claim_roll_chests")
    var held:=card(parent,"LOOT CHESTS · %d SAVED"%d.chests.size(),"Open now for ×1, or keep them for automatic ×3 gold and shards at the end of a normal solo company match. Waiting or changing menus never destroys a chest.")
    for i in d.chests.size():
        var c:Variant=d.chests[i];var lv:=int(c.get("level",d.level)) if c is Dictionary else int(c)
        var mult:=int(c.get("mult",1)) if c is Dictionary else 1
        button(held,"OPEN CHEST %d · LEVEL %d · ×%d"%[i+1,lv,mult],_open_chest.bind(i,battle),not app.busy,"loot_chest_"+str(i))
    if d.chests.is_empty():label(held,"No loot chests waiting.")
    var attacks:=card(parent,"STORED ATTACKS · %d"%p.gift_box().items.size(),"Saved personal attacks are available in solo battles and raids. Live online attack gifts remain match-scoped and server-controlled.")
    for amount in p.gift_box().items:label(attacks,"%d saved damage"%int(amount))
func _open_chest(index:int,battle:bool)->void:
    if app.mutate(func():return p.open_chest(index),"Loot collected",not battle):
        var message:=" · ".join(p.messages)
        if battle:app._battle_inventory()
        app.flash_message(message if not message.is_empty() else "Chest reward saved")
func company_roster()->Array:
    if app.api.is_local() and app.api.local_kind in ["campaign","training"]:
        var out:Array=[]
        for member in app.api.local_engine.s.heroes:
            if int(member.side)==0:out.append(member)
        return out
    if not d.native.get("company") is Array or d.native.company.size()!=20:
        var rng:=RandomNumberGenerator.new();rng.seed=7103+int(d.level)*97
        var roster:Array=Factory.company(p,rng.randf)
        var ours:Array=[]
        for member in roster:
            if int(member.side)==0:ours.append(member)
        p.perform(func():d.native.company=ours)
    var saved:Array=d.native.company.duplicate(true)
    if not saved.is_empty():
        var power:Dictionary=p.hero_power()
        saved[0].char=int(d.char);saved[0].weapon=int(d.weapon);saved[0].level=int(d.level)
        saved[0].atk=power.atk;saved[0].maxHp=power.maxHp;saved[0].hp=power.maxHp
    for member in saved:
        if member.id=="you":continue
        var extra:Variant=d.allyProgress.get(member.name)
        if extra is Dictionary:
            member.level=maxi(int(member.level),int(extra.get("level",member.level)))
            member.gold=int(extra.get("gold",member.get("gold",0)))
    return saved
func guild()->void:
    var root:VBoxContainer=app._shell("GUILD HALL","guild")
    var guild_data:Variant=app.api.online_profile.get("guild")
    card(root,str(guild_data.get("name","Brass Company")) if guild_data is Dictionary else "Brass Company","Your company, shared goals and next battle.")
    button(root,"LIVE GUILD · WEEKLY EXPEDITION",func():app._go("live_guild"),not app.trainer.active,"live_guild")
    var tabs:HBoxContainer=app._row(root)
    var panes:Dictionary={}
    for key in ["overview","roster","chat"]:
        var pane:=VBoxContainer.new();pane.add_theme_constant_override("separation",8);pane.visible=_guild_tab==key;panes[key]=pane
    for spec in [["overview","OVERVIEW"],["roster","COMPANY"],["chat","WAR ROOM"]]:
        var b:=button(tabs,spec[1],func():
            _guild_tab=spec[0]
            for key in panes:panes[key].visible=key==_guild_tab
            app.scroller.set_deferred("scroll_vertical",0)
        ,true,"guild_tab_"+spec[0]);b.add_theme_font_size_override("font_size",11)
    for key in panes:root.add_child(panes[key])
    var overview:VBoxContainer=panes.overview
    var live:=card(overview,"REAL GUILD · WEEKLY EXPEDITION","Only real online guild members contribute to Supply camp, Fort assault and Citadel. Solo company bots are not members of your live guild.")
    if guild_data is Dictionary:
        label(live,"%s · %d real members\n%s route · week %s UTC"%[guild_data.name,guild_data.members.size(),str(guild_data.route).capitalize(),guild_data.week])
        bar(live,float(guild_data.progress),120);label(live,"%d / 120 shared contribution"%int(guild_data.progress))
    else:label(live,"Create a guild or join using a friend's guild code.")
    var roster:Array=company_roster();var standing:=0;var damage:=0;var kos:=0
    for member in roster:
        if int(member.hp)>0:standing+=1
        damage+=int(member.damage);kos+=int(member.kos)
    card(overview,"SOLO COMPANY SNAPSHOT","%d fighters · %d standing\n%d damage · %d knockouts\nHold contested towers through the final push."%[roster.size(),standing,damage,kos])
    var hero_info:=card(overview,"YOUR HERO · "+str(C.character(int(d.char)).n),str(C.character(int(d.char)).d))
    label(hero_info,str(C.get_table("ULTS")[C.character(int(d.char)).id].d))
    label(hero_info,"Online battles use equalized level-10 equipment. Gold and XP from rolls are banked until match-end rewards.",11)
    var members:VBoxContainer=panes.roster
    card(members,"BRASS COMPANY · 20 SOLO FIGHTERS","The roster below is simulated. Real guild members appear under Live guild.")
    for member in roster:
        var row:=card(members,("YOU" if member.id=="you" else str(member.name))+" · "+str(C.character(int(member.char)).n),"Level %d · Tower %s · %d damage%s"%[int(member.level),app.ROMAN[int(member.tower)],int(member.damage)," · Recovering" if int(member.hp)<=0 else ""])
        bar(row,float(member.hp),float(member.maxHp))
    var chat:VBoxContainer=panes.chat
    card(chat,"COMPANY WAR ROOM","Local solo messages and battle updates. Messages here are saved on this device, not broadcast to other players.")
    var log:=VBoxContainer.new();log.add_theme_constant_override("separation",5);log.name="guild_chat_log";chat.add_child(log)
    for message in d.native.chat:
        if message is Dictionary:label(log,str(message.get("text","")),13)
    if d.native.chat.is_empty():label(log,"No messages yet. Plan your next tower push here.")
    chat_edit=TextEdit.new();chat_edit.name="guild_chat_input";chat_edit.custom_minimum_size.y=108
    chat_edit.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;chat_edit.text_direction=Control.TEXT_DIRECTION_LTR
    chat_edit.virtual_keyboard_enabled=true;chat_edit.text=str(d.native.chatDraft)
    chat.add_child(chat_edit)
    var draft_status:Label=label(chat,"%d/120 · device-local draft"%chat_edit.text.length(),11)
    var draft_timer:=Timer.new();draft_timer.wait_time=0.55;draft_timer.one_shot=true;chat.add_child(draft_timer)
    chat_edit.text_changed.connect(func():
        if not is_instance_valid(chat_edit):return
        # Never assign input.text from a render callback: this preserves IME/caret state.
        d.native.chatDraft=chat_edit.text
        draft_status.text="%d/120 · device-local draft"%chat_edit.text.length()
        draft_timer.start()
    )
    draft_timer.timeout.connect(func():
        if not p.store.commit():draft_status.text=p.store.last_error
    )
    button(chat,"SEND MESSAGE",func():
        if not is_instance_valid(chat_edit):return
        var text:=chat_edit.text.strip_edges()
        if text.is_empty():return
        if text.length()>120:draft_status.text="Messages are limited to 120 characters.";return
        if p.perform(func():
            d.native.chat.append({"text":"You: "+text,"at":p.now()})
            if d.native.chat.size()>30:d.native.chat.pop_front()
            d.native.chatDraft=""
        ):
            # Replace only the log; the composer itself stays mounted and focused.
            for child in log.get_children():log.remove_child(child);child.queue_free()
            for entry in d.native.chat:label(log,str(entry.text),13)
            chat_edit.text="";draft_status.text="Message added to your local war room."
            chat_edit.grab_focus();app.audio.play("confirm")
        else:draft_status.text=p.store.last_error
    ,true,"guild_chat_send")
func friends()->void:
    p.perform(func():p._day_check())
    var body:VBoxContainer=app._shell("FRIENDS & GIFTS","friends")
    var giftbox:=card(body,"YOUR STORED ATTACKS","%d attacks saved. Choose an attack from the battlefield inventory to use its captured damage immediately. Shields can absorb it."%p.gift_box().items.size())
    for amount in p.gift_box().items:label(giftbox,"%d damage"%int(amount))
    var returns:=card(body,"RETURN GIFTS","Up to 30 returned Fate can be collected per local day. Any remainder stays saved; stored attacks do not consume the Fate limit.")
    var waiting:=false
    for i in d.giftsDue.size():
        var item:Dictionary=d.giftsDue[i];var ready:bool=int(item.get("at",0))<=p.now();waiting=true
        var description:="%d stored damage"%int(item.damage) if int(item.get("damage",0))>0 else "%d Fate"%int(item.get("energy",0))
        var seconds:=maxi(0,int(ceil(float(int(item.get("at",0))-p.now())/1000)))
        var message:="%s · %s"%[str(item.get("name","Guildmate")),description]
        if not ready:message+=" · %dm %02ds"%[int(seconds/60),seconds%60]
        button(returns,"CLAIM "+message if ready else message,_return_gift.bind(i),ready and (int(item.get("damage",0))>0 or int(d.economyDay.returnEnergy)<30),"return_gift_"+str(i))
    if not waiting:label(returns,"No returned gifts waiting.")
    var free:=card(body,"ONE FREE GIFT PER DAY","Extra help for a simulated company member, in addition to gifts from dice. Gold goes to that member; extra rolls and attacks stay in their inventory.")
    label(free,"Used today." if d.economyDay.freeGift else "Your free gift is ready.")
    var roster:Array=company_roster()
    for member in roster:
        if member.id=="you":continue
        var box:=card(body,str(member.name),"Level %d · Tower %s · %d stored rolls"%[int(member.level),app.ROMAN[int(member.tower)],int(d.allyRolls.get(member.name,0))])
        button(box,"CHOOSE FREE GIFT",_free_gift_offer.bind(str(member.name)),not d.economyDay.freeGift,"free_gift_"+str(member.name))
func _return_gift(index:int)->void:app.mutate(func():return p.claim_return(index),"Returned gift collected")
func _free_gift_offer(name:String)->void:
    var box:VBoxContainer=app._popup("HELP "+name.to_upper())
    label(box,"Choose one gift. It is sent to this simulated company member, not added to your own wallet.")
    for spec in [["gold","30 GOLD"],["energy","3 STORED ROLLS"],["attack","500 STORED DAMAGE"]]:
        button(box,"SEND "+spec[1],_send_free.bind(name,spec[0]),not d.economyDay.freeGift,"send_free_"+spec[0])
func _send_free(name:String,kind:String)->void:
    if app.mutate(func():return p.send_free_gift(name,kind),"Gift sent. A return will arrive in 2–10 minutes."):
        if is_instance_valid(app.modal):app.modal.queue_free();app.modal=null
func live_guild()->void:
    var body:VBoxContainer=app._shell("LIVE GUILD EXPEDITION","live_guild")
    card(body,"REAL ONLINE GUILD","Create or join using a guild code. Qualifying online battles contribute to a shared weekly expedition. This page is separate from your solo company and local chat.")
    profile_status=label(body,"Connect to load your guild and reward history.",13)
    live_guild_box=VBoxContainer.new();live_guild_box.add_theme_constant_override("separation",9);body.add_child(live_guild_box)
    button(body,"CONNECT / REFRESH",_load_live_guild,not app.trainer.active,"guild_refresh")
    if not app.api.online_profile.is_empty():_render_live_guild(app.api.online_profile)
    elif not app.trainer.active:_load_live_guild.call_deferred()
func _load_live_guild()->void:
    if app.profile_in_flight or app.screen!="live_guild":return
    app.profile_in_flight=true
    var generation:int=app.epoch
    var session:Dictionary=await app.api.ensure_session(str(d.native.name))
    if not session.get("ok",false):
        app.profile_in_flight=false
        if generation==app.epoch and is_instance_valid(profile_status):profile_status.text=str(session.get("error","Could not connect"))
        return
    var profile:Dictionary=await app.api.profile()
    app.profile_in_flight=false
    if generation!=app.epoch or app.screen!="live_guild":return
    if profile.get("ok",false):_render_live_guild(profile)
    else:profile_status.text=str(profile.get("error","Guild request failed"))
func _render_live_guild(profile:Dictionary)->void:
    if app.screen!="live_guild" or not is_instance_valid(live_guild_box):return
    for child in live_guild_box.get_children():live_guild_box.remove_child(child);child.queue_free()
    var guild:Variant=profile.get("guild")
    profile_status.text="Connected as "+str(profile.get("name","Player"))
    if profile.get("active") is Dictionary:
        label(live_guild_box,"An online match or search is still active. Resume it before changing guild membership.")
        button(live_guild_box,"RESUME MATCH",func():
            var state:Dictionary=await app.api.state(true)
            if state.get("ok",false):app._accept(state);app.poll_timer.start()
        ,true,"guild_resume_match")
        return
    if not guild is Dictionary:
        var create:=card(live_guild_box,"CREATE A GUILD")
        var name:=LineEdit.new();name.placeholder_text="Guild name";name.max_length=32;name.custom_minimum_size.y=44;create.add_child(name)
        button(create,"CREATE",func():_guild_command({"type":"create","name":name.text.strip_edges()}),true,"guild_create")
        var join:=card(live_guild_box,"JOIN A GUILD")
        var code:=LineEdit.new();code.placeholder_text="Friend's guild code";code.max_length=16;code.custom_minimum_size.y=44;join.add_child(code)
        button(join,"JOIN",func():_guild_command({"type":"join","code":code.text.strip_edges().to_upper()}),true,"guild_join")
        return
    var head:=card(live_guild_box,str(guild.name),"Invite code: %s\n%d members · week %s UTC"%[guild.code,guild.members.size(),guild.week])
    button(head,"COPY INVITE CODE",func():DisplayServer.clipboard_set(str(guild.code));profile_status.text="Guild code copied.")
    label(head,"ROUTE: "+str(guild.route).to_upper()+" · %d progress"%int(guild.progress),15)
    bar(head,float(guild.progress),120)
    if str(guild.leader)==str(app.api.online_id):
        var routes:HBoxContainer=app._row(head)
        for route in ["assault","defense","command"]:button(routes,str(route).capitalize(),_guild_command.bind({"type":"route","route":route}),int(guild.progress)==0,"guild_route_"+route)
        label(head,"The leader can choose a route before the first contribution of the week.",11)
    var contribution:=0
    for member in guild.members:
        if str(member.id)==str(app.api.online_id):contribution=int(member.contribution)
    for i in 3:
        var checkpoint:=card(live_guild_box,["SUPPLY CAMP","FORT ASSAULT","CITADEL"][i],"%d contribution · %d gold · %d weapon shards · %d raid tokens"%[[20,60,120][i],[150,300,600][i],[2,4,8][i],[1,2,4][i]])
        var claimed:=false
        for value in guild.get("claimed",[]):
            if int(value)==i:claimed=true
        var key:="guild:"+str(guild.week)+":"+str(i)
        var local_claimed:bool=d.adventure.receipts.has(key)
        button(checkpoint,"CLAIMED" if local_claimed else ("RECOVER CLAIM" if claimed else "CLAIM REWARD"),_guild_command.bind({"type":"claim","milestone":i}),not local_claimed and contribution>0 and int(guild.progress)>=[20,60,120][i],"guild_claim_"+str(i))
    if contribution<=0:label(live_guild_box,"Contribute through a qualifying online battle before claiming expedition rewards.")
    var members:=card(live_guild_box,"REAL MEMBERS")
    for member in guild.members:label(members,str(member.name)+" · %d contribution"%int(member.contribution)+( " · Leader" if str(member.id)==str(guild.leader) else ""),12)
    button(live_guild_box,"LEAVE GUILD",func():
        var confirm:VBoxContainer=app._popup("LEAVE THIS GUILD?")
        label(confirm,"You will need an invite code to rejoin. Existing earned rewards remain yours.")
        button(confirm,"CONFIRM LEAVE",_guild_command.bind({"type":"leave"}),true,"guild_confirm_leave")
    )
var _guild_busy:=false
func _guild_command(command:Dictionary)->void:
    if _guild_busy or app.screen!="live_guild":return
    _guild_busy=true
    var modal_ref:Control=app.modal
    var generation:int=app.epoch
    if is_instance_valid(profile_status):profile_status.text="Waiting for server confirmation…"
    var response:Dictionary=await app.api.guild_call(command)
    _guild_busy=false
    if generation!=app.epoch or app.screen!="live_guild":return
    if not response.get("ok",false):profile_status.text=str(response.get("error","Guild action was not confirmed"));return
    if is_instance_valid(modal_ref) and app.modal==modal_ref:modal_ref.queue_free();app.modal=null
    app._wallet_refresh()
    var profile:Dictionary=await app.api.profile()
    if generation!=app.epoch or app.screen!="live_guild":return
    if profile.get("ok",false):_render_live_guild(profile)
    app.audio.play("confirm")
func pending_rewards()->void:
    if app.trainer.active or app.api.is_local():return
    var box:VBoxContainer=app._popup("ONLINE REWARDS")
    var message:=label(box,"Connecting to your server account…")
    var generation:int=app.epoch
    var modal_ref:Control=app.modal
    var session:Dictionary=await app.api.ensure_session(str(d.native.name))
    if generation!=app.epoch or not is_instance_valid(modal_ref) or modal_ref!=app.modal:return
    if not session.get("ok",false):message.text=str(session.get("error","Connection failed"));return
    var response:Dictionary=await app.api.pending_rewards()
    if generation!=app.epoch or not is_instance_valid(modal_ref) or modal_ref!=app.modal:return
    if not response.get("ok",false):message.text=str(response.get("error","Could not load rewards"));return
    var items:Array=response.get("receipts",response.get("rewards",[]))
    message.text="Claiming is safe to retry. Rewards are recorded in your native save only once."
    if items.is_empty():label(box,"No unclaimed server rewards.")
    for receipt in items:
        var reward:Dictionary=receipt.get("reward",{})
        var cell:=card(box,"BATTLE REWARD",p.reward_text(reward))
        button(cell,"CLAIM",_pending_claim.bind(str(receipt.id)),true,"pending_claim_"+str(receipt.id))
    button(box,"RECOVER PREVIOUSLY CLAIMED REWARDS",func():
        message.text="Reading your authenticated receipt history…"
        var reply:Dictionary=await app.api.sync_receipts()
        app._wallet_refresh()
        if is_instance_valid(message):message.text="Reward history synchronized safely." if reply.get("ok",false) else str(reply.get("error","Sync failed"))
    ,true,"receipt_recovery")
var _claim_busy:=false
func _pending_claim(id:String)->void:
    if _claim_busy:return
    _claim_busy=true
    var generation:int=app.epoch
    var modal_ref:Control=app.modal
    var response:Dictionary=await app.api.claim(id,C.shard_kind(int(d.weapon)))
    _claim_busy=false
    app._wallet_refresh()
    if generation!=app.epoch or not is_instance_valid(modal_ref) or app.modal!=modal_ref:return
    if response.get("ok",false):app.audio.play("coin");pending_rewards()
    else:app.flash_message(str(response.get("error","Reward was not saved; retry safely.")))
func settings()->void:
    var body:VBoxContainer=app._shell("SETTINGS & SAVES","settings")
    var sound:=card(body,"SOUND & EFFECTS")
    sound_panel(sound)
    var storage:=card(body,"SAVE BACKUP & IMPORT","The native preview is a separate Android app. Android cannot automatically read the old game's private save folder. Import your own Fatebound export or load your own cloud-save code. Preview progress is backed up before an import.")
    button(storage,"EXPORT SAVE FILE",_export_file,true,"export_file")
    button(storage,"COPY SAVE TO CLIPBOARD",func():DisplayServer.clipboard_set(p.store.export_text());app.flash_message("Save copied. Keep it private; it contains your game progress."),true,"export_clipboard")
    button(storage,"IMPORT SAVE FILE",_import_file,not app.trainer.active,"import_file")
    button(storage,"IMPORT FROM CLIPBOARD",func():_preview_import(DisplayServer.clipboard_get()),not app.trainer.active,"import_clipboard")
    var cloud:=card(body,"CLOUD SAVE · LEGACY CODE","Use a save code that belongs to you. Loading shows a preview before replacing local progress. Upload is manual and asks for confirmation. Do not keep two clients writing the same code.")
    var code:=LineEdit.new();code.placeholder_text="FB-XXXX-XXXX";code.text=str(d.native.cloud.get("code",""));code.max_length=12;code.custom_minimum_size.y=44;cloud.add_child(code)
    button(cloud,"LOAD CLOUD SAVE PREVIEW",func():_load_cloud(code.text.strip_edges().to_upper()),not app.trainer.active,"cloud_load")
    button(cloud,"UPLOAD NATIVE SAVE",func():_confirm_cloud_upload(code.text.strip_edges().to_upper()),not app.trainer.active,"cloud_upload")
    button(cloud,"CREATE A NEW BACKUP CODE",func():
        var alphabet:="23456789ABCDEFGHJKMNPQRSTVWXYZ";var crypto:=Crypto.new();var bytes:=crypto.generate_random_bytes(8);var chars:=""
        for byte in bytes:chars+=alphabet[int(byte)%alphabet.length()]
        code.text="FB-"+chars.substr(0,4)+"-"+chars.substr(4,4)
        app.flash_message("New backup code prepared. Tap Upload to create it on the server.")
    )
    var profile:=card(body,"ONLINE ACCOUNT & RECOVERY","Your existing Godot guest identity stays on this device. Importing the browser progression save transfers its wallet, gear and quests, not a separate browser account's bearer token or guild membership.")
    button(profile,"RECOVER MY ONLINE REWARDS",pending_rewards,not app.trainer.active,"online_recovery")
    label(profile,"No account tokens or signing keys are placed in save exports.",11)
    var about:=card(body,"FATEBOUND NATIVE 0.3","Native Godot client using the approved v114 rules and original baked artwork. Server-authoritative online battles remain protocol 1, transport 2 and balance 110. The online server was not rewritten in GDScript.")
    label(about,"Art: KayKit Adventurers 2.0, Character Animations 1.1 and Medieval Hexagon Pack, Kay Lousberg · CC0. Sound design: original Fatebound PCM effects.",11)
    label(about,"Temporary practice/training resources are isolated from permanent progress. Personal-device backup codes are not a substitute for a production account recovery system.",11)
func sound_panel(parent:Node)->void:
    var mute:=button(parent,"UNMUTE" if app.audio.muted else "MUTE ALL",func():
        app.audio.toggle()
        sound_refresh_text(parent)
    ,true,"sound_mute")
    mute.set_meta("mute_button",true)
    for spec in [["master","Master"],["combat","Combat & spells"],["ui","Menus & rewards"]]:
        var row:=VBoxContainer.new();parent.add_child(row)
        var value:=float(d.native.settings.get(spec[0],0.75))
        var name:Label=label(row,"%s · %d%%"%[spec[1],int(value*100)])
        var slider:=HSlider.new();slider.min_value=0;slider.max_value=100;slider.step=1;slider.value=value*100;slider.custom_minimum_size.y=38;slider.name="audio_"+spec[0];row.add_child(slider)
        slider.value_changed.connect(func(v):
            d.native.settings[spec[0]]=v/100.0
            name.text="%s · %d%%"%[spec[1],int(v)]
            app.audio.set_levels(d.native.settings)
        )
        slider.drag_ended.connect(func(_changed):
            if not p.store.commit():app.flash_message(p.store.last_error)
        )
    var sample:HBoxContainer=app._row(parent)
    for spec in [["sword","SWORD"],["crit","CRIT"],["barrage","SPELL"]]:button(sample,spec[1],func():app.audio.play(spec[0]),true,"preview_"+spec[0])
    var motion:=CheckButton.new();motion.text="Reduce motion and flashes";motion.button_pressed=bool(d.native.settings.reduceMotion);motion.custom_minimum_size.y=44;parent.add_child(motion)
    motion.toggled.connect(func(enabled):
        p.perform(func():d.native.settings.reduceMotion=enabled)
        app.apply_settings()
    )
func sound_refresh_text(root:Node)->void:
    for child in root.get_children():
        if child is Button and child.get_meta("mute_button",false):child.text="UNMUTE" if app.audio.muted else "MUTE ALL"
func _export_file()->void:
    var dialog:=FileDialog.new();dialog.use_native_dialog=true;dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE
    dialog.title="Export Fatebound save";dialog.current_file="Fatebound-save-"+str(C.now_ms())+".json";dialog.add_filter("*.json","Fatebound save")
    app.add_child(dialog)
    dialog.file_selected.connect(func(path):
        var f:=FileAccess.open(path,FileAccess.WRITE)
        if f==null:app.flash_message("Could not write there. Use clipboard or cloud backup instead.")
        else:f.store_string(p.store.export_text());f.flush();f.close();app.flash_message("Save exported successfully.")
        dialog.queue_free()
    )
    dialog.canceled.connect(dialog.queue_free);dialog.popup_centered_ratio(0.85)
func _import_file()->void:
    var dialog:=FileDialog.new();dialog.use_native_dialog=true;dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE
    dialog.title="Import your Fatebound save";dialog.add_filter("*.json","Fatebound save")
    app.add_child(dialog)
    dialog.file_selected.connect(func(path):
        var file:=FileAccess.open(path,FileAccess.READ)
        if file==null:app.flash_message("Could not read that file. Try clipboard or your cloud code.")
        elif file.get_length()>4*1024*1024:app.flash_message("Save exceeds the supported 4 MB limit.")
        else:_preview_import(file.get_as_text())
        dialog.queue_free()
    )
    dialog.canceled.connect(dialog.queue_free);dialog.popup_centered_ratio(0.85)
func _preview_import(text:String)->void:
    if app.trainer.active:return
    var parsed:Dictionary=p.store.parse_import(text)
    if not parsed.get("ok",false):app.flash_message(str(parsed.get("error","Invalid save")));return
    var box:VBoxContainer=app._popup("CONFIRM SAVE IMPORT")
    label(box,str(parsed.summary),18,Color("#eddea9"))
    label(box,"This replaces this preview's progression after a timestamped backup. It does not change the normal Fatebound app or import its online guest identity.")
    if parsed.save.get("war") is Dictionary and str(parsed.save.war.get("phase",""))!="complete":label(box,"An old web battle snapshot is present. Its data will be preserved and the native compatibility converter will attempt to resume it.",12,Color("#ffd09d"))
    button(box,"BACK UP & IMPORT",func():
        if not p.store.install_import(parsed.save):app.flash_message(p.store.last_error);return
        app.progression.boot();app.apply_settings()
        if is_instance_valid(app.modal):app.modal.queue_free();app.modal=null
        app._show_home();app.flash_message("Progress imported. The previous native save has been backed up.")
        app.resume_imported_war()
    ,true,"confirm_import")
var _cloud_busy:=false
func _load_cloud(code:String)->void:
    if _cloud_busy:return
    _cloud_busy=true;app.flash_message("Loading cloud save without changing local progress…")
    var generation:int=app.epoch
    var answer:Dictionary=await app.api.cloud_request(code,false)
    _cloud_busy=false
    if generation!=app.epoch:return
    if not answer.get("ok",false):app.flash_message(str(answer.get("error","Cloud load failed")));return
    var raw:Variant=answer.get("save")
    if raw==null:app.flash_message("No save exists for that code.");return
    var text:=str(raw) if raw is String else JSON.stringify(raw)
    _preview_import(text)
func _confirm_cloud_upload(code:String)->void:
    var box:VBoxContainer=app._popup("CONFIRM CLOUD UPLOAD")
    label(box,"Upload this native progression save to "+code+"?",16)
    label(box,"This can replace an existing save under that code. Use your own new backup code to avoid overwriting the older browser client. The native session and browser session formats are not interchangeable.")
    button(box,"UPLOAD THIS SAVE",func():_upload_cloud(code),true,"confirm_cloud_upload")
func _upload_cloud(code:String)->void:
    if _cloud_busy:return
    _cloud_busy=true
    var owner=p
    var generation:int=app.epoch
    var modal_ref:Control=app.modal
    var response:Dictionary=await app.api.cloud_request(code,true)
    _cloud_busy=false
    if response.get("ok",false):owner.perform(func():owner.d.native.cloud.code=code)
    if generation!=app.epoch or not is_instance_valid(modal_ref) or app.modal!=modal_ref:return
    if response.get("ok",false):
        modal_ref.queue_free();app.modal=null
        app.flash_message("Cloud backup uploaded. Keep the code private.")
    else:app.flash_message(str(response.get("error","Cloud upload failed")))
func show_result(state:Dictionary)->void:
    result_claimed=false
    var result:Dictionary=state.get("result",{})
    var raid_result:bool=state.get("kind","")=="raid"
    var practice:bool=result.get("practice",false)
    var headline:="RAID COMPLETE" if raid_result else ("DRAW" if result.get("draw",false) else ("VICTORY" if result.get("win",false) else "DEFEAT"))
    var body:VBoxContainer=app._shell(headline,"result",false)
    var head:=card(body,headline)
    if raid_result:
        label(head,"%d damage this attempt · %s"%[int(result.get("stats",{}).get("damage",0)),str(result.get("reason","")).replace("KO","knocked out").capitalize()],17)
        label(head,"Personal tiers, company milestones and qualifying kill rewards were already saved as you earned them. Claim below completes this attempt without paying them twice.")
    else:
        var score:Array=result.get("score",[0,0]);label(head,"%d — %d CROWNS"%[int(score[0]),int(score[1])],27,Color("#efd18c"))
        label(head,"Practice completed. No rank, mastery or permanent rewards are granted." if practice else str(result.get("tip","Hold contested towers through the final push.")))
        if not practice and not result.get("eligible",false):label(head,"At least 5 paid rolls are required for match-end rewards.",12,Color("#edbc9d"))
        var reward:Dictionary=result.get("reward",{})
        label(head,p.reward_text(reward) if not reward.is_empty() else "No additional match rewards",16,Color("#a6e5cd"))
    var stats_box:=card(body,"YOUR BATTLE")
    var stats:Dictionary=result.get("stats",{})
    for pair in [["damage","Damage"],["kos","Knockouts"],["shieldsBroken","Shields broken"],["rolls","Rolls"],["paidRolls","Paid rolls"],["triples","Triples"],["flips","Flips"],["spells","Spells"],["bounties","Bounties"]]:
        if stats.has(pair[0]):label(stats_box,"%s · %d"%[pair[1],int(stats[pair[0]])],13)
    if result.has("champion"):label(stats_box,"Champion · "+str(result.champion)+"\nShield destroyer · "+str(result.breaker))
    if result.has("rankDelta"):label(stats_box,"Rank %+d · %s %d"%[int(result.rankDelta),p.rank_title(),int(d.rank)])
    if result.has("heldChests") and not result.heldChests.is_empty():
        var held:=card(body,"HELD CHESTS OPENED AT ×3")
        for reward in result.heldChests:label(held,p.reward_text(reward))
    if result.get("highlights") is Dictionary:
        var highlights:Dictionary=result.highlights
        if highlights.get("biggestHit") is Dictionary:label(stats_box,"Biggest strike · %d damage"%int(highlights.biggestHit.damage))
        if highlights.get("clutchCapture") is Dictionary:label(stats_box,"Final-push capture · Tower "+app.ROMAN[int(highlights.clutchCapture.tower)])
    var shard:=OptionButton.new();shard.fit_to_longest_item=false;shard.custom_minimum_size.y=44
    for name in ["Steel shards","Arcane shards","Fletch shards"]:shard.add_item(name)
    shard.selected=["steel","arcane","fletch"].find(C.shard_kind(int(d.weapon)))
    if not state.get("local",false):body.add_child(shard)
    else:body.add_child(shard);shard.visible=false
    var claim_status:=label(body,"Rewards are safe to retry; duplicate claims do not pay twice.",12)
    var claim:=button(body,"FINISH ATTEMPT" if raid_result else ("FINISH PRACTICE" if practice else "CLAIM REWARDS"),func():pass,true,"claim_rewards")
    var again:=button(body,"BACK TO HOME",func():
        if not result_claimed:return
        if app.api.is_local():app.api.leave_local()
        app.latest={};app.latest_state={};app.current_match_id=""
        app._show_home()
    ,false,"result_home")
    claim.pressed.connect(func():
        if claim.disabled:return
        claim.disabled=true;claim_status.text="Saving reward claim…"
        var kind:String=C.shard_kind(int(d.weapon)) if state.get("local",false) else ["steel","arcane","fletch"][shard.selected]
        var reply:Dictionary=await app.api.claim(str(result.get("id",app.current_match_id)),kind)
        if not is_instance_valid(claim):return
        if reply.get("ok",false):
            result_claimed=true;again.disabled=false;claim.text="SAVED";claim_status.text="Rewards saved. Your next battle is ready."
            app.audio.play("coin");app._wallet_refresh()
        else:claim.disabled=false;claim_status.text=str(reply.get("error","Claim was not saved. Retry safely."))
    )
    if not raid_result and result.get("scenario") is Dictionary:
        p.perform(func():d.adventure.lastMoment=result.scenario.duplicate(true))
    app.audio.play("victory" if result.get("win",false) else "defeat")
func level_reward()->void:
    if not d.get("levelReward") is Dictionary:return
    var reward:Dictionary=d.levelReward
    var box:VBoxContainer=app._popup("LEVEL UP · %d"%int(reward.get("after",{}).get("level",d.level)))
    label(box,"Your permanent hero has grown stronger.",17,Color("#f5dd9d"))
    var before:Dictionary=reward.get("before",{});var after:Dictionary=reward.get("after",{})
    label(box,"Attack %d → %d\nCritical %d → %d\n+%d stored Fate"%[int(before.get("attack",0)),int(after.get("attack",0)),int(before.get("critical",0)),int(after.get("critical",0)),int(reward.get("energy",0))],20)
    button(box,"COLLECT LEVEL REWARD",func():
        if p.claim_level_reward():
            app.resume_level_pause()
            if is_instance_valid(app.modal):app.modal.queue_free();app.modal=null
            app._wallet_refresh();app.audio.play("level")
        else:app.flash_message(p.store.last_error)
    ,true,"claim_level_reward")
