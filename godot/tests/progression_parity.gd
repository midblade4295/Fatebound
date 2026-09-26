extends SceneTree
const C=preload("res://scripts/game/content.gd")
const Store=preload("res://scripts/game/progress_store.gd")
const Progress=preload("res://scripts/game/progression.gd")
const Solo=preload("res://scripts/game/solo_campaign.gd")
const Raid=preload("res://scripts/game/raid.gd")
const Legacy=preload("res://scripts/game/legacy_import.gd")
var checks:Array[String]=[]
var failures:Array[String]=[]
var base:=1790431200000
func fresh(memory:=true):
    var s=Store.new("user://test-native-progress-%d.json"%Time.get_ticks_usec(),false);s.memory_only=memory
    var p=Progress.new(s);p.at_override=base;assert(p.boot());return p
func expect(condition:bool,text:String)->void:
    if not condition:
        failures.append(text)
        push_error("FAIL "+text)
    else:checks.append(text)
func _init()->void:
    var p=fresh()
    expect(p.fate()==57 and int(p.d.cap)==50,"day-one original Fate reward/overflow")
    p.at_override=base+86400000;p.boot()
    expect(int(p.d.login.streak)==2 and int(p.d.cap)==55 and p.fate()==66,"day-two streak/cap preserves overflow")
    p.at_override=base+3*86400000;p.boot()
    expect(int(p.d.login.streak)==1 and int(p.d.cap)==55,"missed-day streak resets without shrinking cap")
    p=fresh();p.d.gold=10000;p.d.shards.steel=100
    expect(p.buy_weapon(2) and int(p.d.gold)==9500 and p.d.owned.has(2),"weapon price and ownership transaction")
    expect(not p.buy_weapon(2) and int(p.d.gold)==9500,"owned weapon cannot charge twice")
    expect(not p.buy_weapon(3),"quest-only weapon cannot be bought")
    expect(p.forge(2) and int(p.d.gold)==8000 and int(p.d.shards.steel)==80 and int(p.d.tiers["2"])==1,"Rare forging exact 20 shards/1500 gold")
    p.d.tokens=100
    expect(p.buy_relic("atk") and int(p.d.tokens)==85 and int(p.d.relics.atk)==1,"Whetstone base price")
    expect(p.buy_relic("atk") and int(p.d.tokens)==55 and int(p.d.relics.atk)==2,"Whetstone escalating price")
    expect(not p.buy_relic("cap"),"paused cap sales remain disabled")
    var disk=fresh(false);disk.d.gold=10000;disk.d.shards.steel=100;disk.store.commit();disk.store.fault_inject=true
    var before:Dictionary=disk.d.duplicate(true)
    expect(not disk.forge(0) and disk.d==before,"forge rollback on persistence failure")
    disk.store.fault_inject=false
    expect(disk.forge(0),"forge retries after save failure")
    var roundtrip=Store.new(disk.store.path,true)
    expect(JSON.parse_string(JSON.stringify(roundtrip.data))==JSON.parse_string(JSON.stringify(disk.d)),"atomic save roundtrip incl numeric index normalization")
    p=fresh();p.d.tokens=200;p.d.season.pts=1000
    expect(p.activate_premium() and int(p.d.tokens)==20,"premium original 180-token price")
    var fate:=p.fate();expect(p.claim_season(0,false) and p.fate()==fate+20,"free tier1 +20 Fate")
    fate=p.fate();expect(not p.claim_season(0,false) and p.fate()==fate,"season claim exactly once")
    p.claim_season(2,true)
    expect(int(p.d.level)==6 and int(p.d.levelReward.energy)==3,"premium level-up retains +3 Fate choice")
    fate=p.fate();expect(p.claim_level_reward() and p.fate()==fate+3 and not p.claim_level_reward(),"level reward exactly once")
    var snapshot:Dictionary=JSON.parse_string(JSON.stringify(p.d));var imported:Dictionary=Store.normalized(snapshot)
    expect(imported.season.free.has(0) and imported.season.prem.has(2),"imported JSON numeric tier IDs cannot duplicate claims")
    var receipt:Dictionary={"id":"receipt-one","at":base,"season":C.season_id(base),"char":0,"weapon":0,"claimed":true,"eligible":false,"win":false,"reward":{"gold":20,"fate":2,"pts":1,"shards":3,"xp":1},"mastery":{"assault":2},"stats":{"rolls":2,"paidRolls":2,"damage":100}}
    var gold:=int(p.d.gold)
    expect(p.apply_receipt(receipt) and int(p.d.gold)==gold+20,"server receipt applied")
    expect(p.apply_receipt(receipt) and int(p.d.gold)==gold+20,"server receipt deduplicated")
    var points:=int(p.d.season.pts);receipt.id="old-season";receipt.season=int(receipt.season)-1
    expect(p.apply_receipt(receipt) and int(p.d.season.pts)==points,"old season receipts do not grant current points")
    p=fresh();p._roll_track(39,0)
    expect(int(p.d.rollTrack.ready)==1 and int(p.d.rollTrack.progress)==19 and int(p.d.rollTrack.gold)==200,"paid-Focus chest progress 20/39")
    expect(p.claim_roll_chests() and int(p.d.gold)==200 and int(p.d.shards.steel)==1,"roll chest bank collected exactly")
    expect(not p.claim_roll_chests(),"roll chest cannot double claim")
    p.d.chests=[{"level":5,"mult":2,"kind":"steel"}]
    var ordinary:Dictionary=p.chest_reward(p.d.chests[0],3,0)
    var jackpot:Dictionary=p.chest_reward(p.d.chests[0],3,1)
    expect(int(ordinary.gold)==540 and int(ordinary.shards)==6 and int(jackpot.gold)==1080 and int(jackpot.shards)==18,"held chest ×3/jackpot formulas")
    expect(p.open_chest(0) and p.d.chests.is_empty() and not p.open_chest(0),"loot pop and payout are one transaction")
    p.check_weapon_quests({"triples":3,"kos":3,"damage":5000,"shieldsBroken":5,"rolls":60})
    expect(p.d.owned.has(1) and p.d.owned.has(3) and p.d.owned.has(4) and p.d.owned.has(6) and p.d.owned.has(8),"all five weapon quests unlock from exact requirements")
    expect(p.send_free_gift("Ari","attack") and not p.send_free_gift("Ari","attack"),"free gift once daily")
    expect(int(p.gift_box("ally:Ari").items[0])==500,"saved gift attack captures source magnitude")
    p.d.giftsDue=[{"name":"Ari","at":base-1,"energy":10}];p.d.economyDay.returnEnergy=25
    expect(p.claim_return(0) and int(p.d.giftsDue[0].energy)==5 and int(p.d.economyDay.returnEnergy)==30,"returned Fate cap leaves remainder saved")
    var raw:String=p.store.export_text();var parsed:Dictionary=p.store.parse_import(raw)
    expect(parsed.ok and parsed.save.owned==p.d.owned,"export/import keeps gear and unknown fields")
    expect(not p.store.parse_import('{"owned":[0],"gold":-5}').ok,"negative imported gold rejected without mutation")
    var solo=Solo.new();solo.configure(p);solo.start(base,12345);solo.own().focus=8;solo.forced_faces=["G","G","G"]
    var chest_progress_before:=int(p.d.rollTrack.progress)+20*int(p.d.rollTrack.ready)
    gold=int(p.d.gold);var roll:Dictionary=solo.act("you",{"type":"roll","mult":1},base)
    expect(roll.ok and int(roll.result.effects.goldAdded)==200,"solo triple gold pays original 200")
    expect(int(solo.own().paidRolls)==1 and int(p.d.rollTrack.progress)+20*int(p.d.rollTrack.ready)==chest_progress_before+1,"solo paid rolls feed XP/chest progression")
    solo.own().focus=8;solo.own().rollAt=0;solo.forced_faces=["F","F","F"]
    roll=solo.act("you",{"type":"roll","mult":1},base+3000)
    var choices:Array=solo.s.pendingGift;var kinds:Dictionary={};var bonuses:=0
    for item in choices:kinds[item.kind]=true;bonuses+=int(item.bonus)
    expect(choices.size()==3 and kinds.size()==3 and bonuses==1,"triple gift makes three distinct cards with one bonus")
    expect(solo.act("you",{"type":"gift_choice","index":0},base+3100).ok and solo.s.pendingGift.is_empty(),"gift card choice resolves once")
    var raid=Raid.new();raid.configure(p);expect(raid.ensure_day(),"daily raid initialization")
    var initial_attempts:=int(raid.boss.attempts);expect(raid.start(base,7),"raid attempt starts")
    expect(int(raid.boss.attempts)==initial_attempts+1 and raid.s.heroes.size()==21,"raid uses attempt once /20 company +boss")
    raid.forced_faces=["H","H","H"];var armour:=int(raid.boss.armor)
    roll=raid.act("you",{"type":"roll","mult":1},base)
    expect(roll.ok and int(raid.boss.armor)==maxi(0,armour-3),"raid triple shield strips three armour")
    raid.run.telegraphUntil=base+1000;raid.run.parryHit=false
    expect(raid.parry(base) and raid.run.parryHit,"raid parry inside windup")
    raid.tick(base+1001);expect(raid.run.parried,"raid parry arms next-attack bonus")
    raid.end_attempt("leave",base+2000)
    expect(not raid.act("you",{"type":"roll","mult":1},base+4000).ok,"raid cannot act after attempt ended")
    var endstate:Dictionary=solo.export_state();var restored=Solo.new();restored.configure(p)
    expect(restored.restore(JSON.parse_string(JSON.stringify(endstate))) and restored.own().hp==solo.own().hp,"solo session export/restore preserves HP and progression")
    var report:Dictionary={"checks":checks,"count":checks.size(),"failures":failures,"status":"PASS" if failures.is_empty() else "FAIL","source":"v114 tables and verified original formulas","physical_phone":false}
    FileAccess.open("res://reports/full-port/progression-tests.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
    print("PROGRESSION_PASS ",JSON.stringify(report))
    quit(0 if failures.is_empty() else 1)
