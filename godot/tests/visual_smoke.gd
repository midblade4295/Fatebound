extends SceneTree

func hero(i: int) -> Dictionary:
    return {
        "id":"p%d"%i,"name":"P%d"%i,"bot":i>1,"substitute":false,"connected":true,
        "side":0 if i<10 else 1,"char":0,"weapon":0,"level":10,"atk":30,
        "maxHp":1800,"hp":1800,"tower":0 if i in [0,10] else i%10,
        "shieldSlots":[],"downUntil":0,"focus":8,"focusAt":0,"spell":2,
        "loadout":["barrage","bulwark"],"ult":100,"forcedCrits":0,"rampage":0,
        "surgeUntil":0,"rollAt":0,"moveAt":0,"spellAt":0,"rallyAt":0,
        "ralliesLeft":1,"damage":0,"shieldsBroken":0,"kos":0,"rolls":1,
        "paidRolls":1,"triples":0,"focusSpent":1,"spellsCast":0,"ultsUsed":0,
        "streak":0,"hot":false,"lastFaces":["C","C","S"],"giftDamage":0,"storedDamage":0
    }

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var scene: PackedScene = load("res://scenes/Main.tscn")
    var main = scene.instantiate()
    get_root().add_child(main)
    await process_frame
    main.api.player_id = "p0"
    var heroes: Array = []
    for i in 20:
        heroes.append(hero(i))
    var towers: Array = []
    for i in 10:
        towers.append({"id":i,"name":"Tower %d"%(i+1),"pts":i,"dmg":[0,0],"prev":-1})
    var snapshot := {
        "id":"visual-room","now":1000,"startAt":0,"endAt":301000,"phase":"regulation",
        "ended":false,"score":[5,3],"heroes":heroes,"towers":towers,"events":[]
    }
    main.latest = snapshot
    main.current_match_id = "visual-room"
    main.active = true
    main._show_battle()
    main._update_battle(snapshot,{"gold":25})
    assert(main.dice_labels.size() == 3)
    await main._animate_confirmed_roll(["C","C","S"],{
        "faces":["C","C","S"],"symbol":"C","tier":"pair","dealt":420,"absorbed":60,
        "effects":{"focusGained":1,"shieldAdded":0,"goldAdded":0,"xpAdded":1,"giftAdded":0}
    })
    assert(main.dice_labels[0].text == "CRIT")
    assert(main.dice_labels[1].text == "CRIT")
    assert(main.dice_labels[2].text == "SWORD")
    main._confirmed_feedback({"symbol":"H","dealt":0,"absorbed":0,"effects":{"shieldAdded":120,"goldAdded":0,"focusGained":0,"giftAdded":0}})
    await create_timer(0.8).timeout
    print("VISUAL_SMOKE_PASS dice=%s/%s/%s" % [main.dice_labels[0].text,main.dice_labels[1].text,main.dice_labels[2].text])
    quit(0)
