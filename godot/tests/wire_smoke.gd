extends SceneTree

const WireScript = preload("res://scripts/arena_wire.gd")

func _init() -> void:
    var wire := WireScript.new()
    assert(WireScript.winning_dice(["C","C","S"]).indices == [0,1])
    assert(WireScript.winning_dice(["H","G","H"]).indices == [0,2])
    assert(WireScript.winning_dice(["F","F","F"]).tier == "triple")
    var heroes: Array = []
    for i in 20:
        heroes.append({"id":"p%d"%i,"name":"P%d"%i,"bot":i>1,"substitute":false,"connected":true,"side":0 if i<10 else 1,"char":0,"weapon":0,"level":10,"atk":30,"maxHp":1800,"hp":1800,"tower":i%10,"shieldSlots":[],"downUntil":0,"focus":8,"focusAt":0,"spell":1,"loadout":["barrage","bulwark"],"ult":0,"forcedCrits":0,"rampage":0,"surgeUntil":0,"rollAt":0,"moveAt":0,"spellAt":0,"rallyAt":0,"ralliesLeft":1,"damage":0,"shieldsBroken":0,"kos":0,"rolls":0,"paidRolls":0,"triples":0,"focusSpent":0,"spellsCast":0,"ultsUsed":0,"streak":0,"hot":false,"lastFaces":["S","H","G"],"giftDamage":0,"storedDamage":0})
    var towers: Array = []
    for i in 10:
        towers.append({"id":i,"name":"Tower %d"%(i+1),"pts":i,"dmg":[0,0],"prev":-1})
    var full := {"version":1,"balanceVersion":110,"id":"room","mode":"standard","practice":false,"startAt":1,"endAt":300001,"regulationEnd":300001,"phase":"regulation","ended":false,"now":1000,"revision":1,"seq":2,"control":[0,0],"controlDuration":[0,0],"rally":[null,null],"holds":[[],[]],"score":[0,0],"winner":null,"objective":{},"completedAt":0,"heroes":heroes,"towers":towers}
    var first: Dictionary = wire.decode({"wire":2,"id":"room","revision":1,"seq":2,"full":full,"events":[]})
    assert(first.get("heroes",[]).size() == 20)
    var delta := {"wire":2,"id":"room","base":1,"revision":2,"seq":3,"set":{"now":1750,"revision":2,"seq":3},"heroes":[[0,{"hp":0,"downUntil":11750}]],"towers":[[3,{"prev":0}]],"events":[{"seq":3,"type":"roll","at":1700}]}
    var second: Dictionary = wire.decode(delta)
    assert(second["heroes"][0]["hp"] == 0)
    assert(second["heroes"][0]["downUntil"] == 11750)
    assert(second["towers"][3]["prev"] == 0)
    assert(wire.cursor()["revision"] == 2)
    print("WIRE_SMOKE_PASS full=%d delta=%d" % [wire.stats.full,wire.stats.delta])
    quit(0)
