extends SceneTree
# 0.31.197: the clan camp (scripts/app/clan_camp.gd) at its four stages, full screen, with a crest -- for a look at the
# paintings, their banners in the crest's colours and the crests on them.
#   SHOT_DIR=/tmp/x CREST=3.5.1 godot --path godot --resolution 1080x2340 -s res://tools/clan_camp_shot.gd
const ClanCamp = preload("res://scripts/app/clan_camp.gd")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var dir := OS.get_environment("SHOT_DIR") if OS.has_environment("SHOT_DIR") else "/tmp"
	var code := OS.get_environment("CREST") if OS.has_environment("CREST") else "3.5.1"
	for st in range(1, 5):
		var c = ClanCamp.new()
		c.setup(st, code)
		c.size = root.get_visible_rect().size
		root.add_child(c)
		for i in 40:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(dir.path_join("clan_camp_stage%d.png" % st))
		c.queue_free()
		await process_frame
	print("CLAN_CAMP_SHOTS done")
	quit(0)
