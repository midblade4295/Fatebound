extends SceneTree
const C=preload("res://scripts/game/content.gd")
const Store=preload("res://scripts/game/progress_store.gd")
const Progression=preload("res://scripts/game/progression.gd")
const Arena=preload("res://scripts/game/arena_local.gd")
func _init()->void:
    var store=Store.new("user://test-full-core.json",false)
    var p=Progression.new(store)
    p.at_override=1790424000000
    assert(p.boot())
    assert(int(store.data.level)==5)
    var engine=Arena.new()
    var players:Array=[]
    for i in 20:players.append({"id":"test%d"%i,"name":"Test %d"%i,"bot":i>0,"char":i%5,"weapon":0})
    engine.init_match("test",players,100000,12345)
    engine.forced_faces=["C","C","S"]
    var rolled:Dictionary=engine.act("test0",{"type":"roll","mult":1},100000)
    assert(rolled.ok)
    assert(rolled.result.symbol=="C")
    engine.tick(100500)
    print("FULL_CORE_SMOKE_PASS ",JSON.stringify(rolled.result))
    quit(0)
