extends SceneTree
const Store=preload("res://scripts/game/progress_store.gd")
const Progress=preload("res://scripts/game/progression.gd")
const Solo=preload("res://scripts/game/solo_campaign.gd")
const Raid=preload("res://scripts/game/raid.gd")
const API=preload("res://scripts/game/game_api.gd")
func _init():
    var store=Store.new("user://parse-only.json",false);store.memory_only=true
    var p=Progress.new(store);p.at_override=1790431200000
    assert(p.boot())
    var solo=Solo.new();solo.configure(p);assert(solo.start(p.now(),12345))
    var player:Dictionary=solo.own();player.focus=8
    var response:Dictionary=solo.act("you",{"type":"roll","mult":1},p.now())
    assert(response.ok)
    var raid=Raid.new();raid.configure(p);assert(raid.ensure_day());assert(raid.start(p.now(),2345))
    var output:Dictionary=raid.act("you",{"type":"roll","mult":1},p.now());assert(output.ok)
    print("ALL_MODULES_PASS SOLO=",response.result," RAID=",output.result)
    quit(0)
