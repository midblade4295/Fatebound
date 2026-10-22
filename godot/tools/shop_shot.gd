extends SceneTree
# 0.31.202: review shots of the 5v5's item shop -- you in your castle with gold and a few items, the shop open, one item
# picked (and a second shot with one of yours picked).
#   DISPLAY=:97 godot --rendering-method mobile --fixed-fps 30 --resolution 900x1600 --path godot -s res://tools/shop_shot.gd
# OUT (prefix, default /tmp/shop_), GOLD (default 2400), PICK (an item id to pick; default the first big item).
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Moba = preload("res://scripts/siege/moba.gd")
var mode
var frames := 0
var prefix := "/tmp/shop_"
var shots := {}

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	if OS.has_environment("OUT"):
		prefix = OS.get_environment("OUT")
	mode = Mode.new()
	mode.moba_hero = "knight"
	mode.match_seed = 4402
	root.add_child(mode)
	RenderingServer.frame_post_draw.connect(func():
		if shots.has(frames):
			root.get_texture().get_image().save_png(str(shots[frames]))
			print("SHOT ", shots[frames])
			shots.erase(frames))

func _process(_delta: float) -> bool:
	frames += 1
	if mode.sim == null or not mode._build_queue.is_empty() or frames < 40:
		return false
	var s = mode.sim
	if frames == 40:
		s.moba.wave_at = INF
		var me: Dictionary = s.by_id["you"]
		me.gold = float(int(OS.get_environment("GOLD")) if OS.has_environment("GOLD") else 2400)
		var basics: Array = Moba.ITEM_ORDER.filter(func(x): return not Moba.ITEMS[x].has("from"))
		me["items"] = [str(basics[0]), str(basics[2])]
		mode.hud.open_shop()
		var bigs: Array = Moba.ITEM_ORDER.filter(func(x): return Moba.ITEMS[x].has("from"))
		var pick := OS.get_environment("PICK") if OS.has_environment("PICK") else str(bigs[0])
		mode.hud._shop_sel = {"item": pick}
		mode.hud._shop_key = ""
		shots[frames + 12] = prefix + "item.png"
	if frames == 70:
		mode.hud._shop_sel = {"slot": 0}
		mode.hud._shop_key = ""
		shots[frames + 8] = prefix + "slot.png"
	if frames == 75:
		mode.hud._shop_sel = {}
		mode.hud._shop_key = ""
		shots[frames + 8] = prefix + "none.png"
	if frames > 95 and shots.is_empty():
		quit(0)
	return false
