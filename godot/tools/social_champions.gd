extends SceneTree
# The social kit's champion pictures (Kevin: "Just give me a zip file with everything like graphic art, what the game is
# about ect that I can give to it so it posts on socials"): each champion's own window (champion_window.gd: his painted
# place, his effects, him in 3D) with its buttons, panel and name hidden, the stage made taller so he stands bigger,
# turned three-quarters to the lens. tools/build_muse_kit.py sets his name, title, role and line under him.
#   DISPLAY=:97 FB_FORCE_HQ=1 godot --rendering-method mobile --fixed-fps 30 --resolution 1080x1350 --path . \
#     -s res://tools/social_champions.gd
#   OUTDIR=<dir>  HEROES=knight,mage (default: all 18)  SKINS=own|outfit|both (default both)  YAW=-0.45  ZOOM=1.0
#   DUMP=<json>: no pictures -- the champions' facts for the kit's text instead (name, title, role, story, line, kit,
#   epic outfit, whether he's yours from the start), and the roles' lines; headless is enough (--headless)
# Writes <OUTDIR>/<hero>.png (his own look) and <OUTDIR>/<outfit id>.png (his epic set: "golem_geode"). Never the
# live server.
const App = preload("res://scripts/app/siege_app.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Champions = preload("res://scripts/meta/champions.gd")
const Kits = preload("res://scripts/siege/moba_kits.gd")

const NOW := 1795000000
const SETTLE := 110                      # frames after opening a window before its picture (the model loads, fx spread)
var app
var frames := 0
var outdir := "/tmp/social_champions"
var queue: Array = []                    # [[hero, skin id or ""], ...]
var cur := -1
var opened_at := 0
var pending := false
var yaw := -0.45
var zoom := 1.0
var dumping := false

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	if OS.has_environment("DUMP"):
		dumping = true
		_dump(OS.get_environment("DUMP"))
		quit()
		return
	outdir = OS.get_environment("OUTDIR") if OS.has_environment("OUTDIR") else outdir
	DirAccess.make_dir_recursive_absolute(outdir)
	yaw = float(OS.get_environment("YAW")) if OS.has_environment("YAW") else yaw
	zoom = float(OS.get_environment("ZOOM")) if OS.has_environment("ZOOM") else zoom
	var heroes: Array = Moba.HERO_ORDER.duplicate()
	if OS.has_environment("HEROES"):
		heroes = Array(OS.get_environment("HEROES").split(","))
	var skins := OS.get_environment("SKINS") if OS.has_environment("SKINS") else "both"
	for h in heroes:
		if skins != "outfit":
			queue.append([h, ""])
		if skins != "own":
			for id in Eco.OUTFITS:
				if str(id).begins_with(str(h) + "_"):
					queue.append([h, str(id)])
	var base := "user://socialchamp-%d" % Time.get_ticks_usec()
	app = App.new()
	app.eco_autostart = false
	app.social_autostart = false
	app.version_check = false
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	app.now_override = NOW
	app.intro_auto = false
	app.daily_auto = false
	root.add_child(app)
	RenderingServer.frame_post_draw.connect(func():
		if pending:
			pending = false
			var q: Array = queue[cur]
			var name := str(q[0]) if str(q[1]) == "" else str(q[1])
			var path := outdir.path_join(name + ".png")
			root.get_texture().get_image().save_png(path)
			print("SOCIAL_CHAMP ", path))

func _dump(path: String) -> void:
	var out := []
	for hid in Moba.HERO_ORDER:
		var c: Dictionary = Champions.of(hid)
		var kit := {}
		for sl in ["q", "w", "e"]:
			var a: Dictionary = Kits.kit(hid, sl)
			kit[sl] = {"name": str(a.get("name", "")), "text": str(a.get("text", ""))}
		var u: Dictionary = Moba.ULTS.get(hid, {})
		kit["r"] = {"name": str(u.get("name", "")), "text": str(u.get("text", ""))}
		var outfit := ""
		var outfit_id := ""
		for id in Eco.OUTFITS:
			if str(id).begins_with(str(hid) + "_"):
				outfit_id = str(id)
				outfit = str(Eco.OUTFITS[id].set)
		out.append({"id": hid, "class": str(Moba.HEROES[hid].name), "name": str(c.name), "short": str(c.get("short", "")),
			"title": str(c.title), "role": Kits.role_of(hid), "lore": str(c.lore), "quote": str(c.quote),
			"starter": not Eco.HERO_PRICES.has(hid), "outfit": outfit, "outfit_id": outfit_id, "abilities": kit})
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"roles": Kits.ROLE_TEXT, "free_each_week": Eco.FREE_HEROES, "champions": out}, "  "))
	f.close()
	print("SOCIAL_CHAMP_DUMP ", path)

func _seed() -> void:
	var p = app.profile
	p.d.name = "Midblade"
	p.d.tutorial_done = true
	for h in Moba.HERO_ORDER:
		if not (p.d.get("heroes", []) as Array).has(h):
			(p.d.heroes as Array).append(h)
	p.save()

func _bare(m) -> void:
	# his window without its controls: the panel, the zoom buttons, hint and chips, the close button; the stage taller
	m._scroll.get_parent().visible = false
	m._status.get_parent().visible = false
	for c in m.get_children():
		if c is BaseButton or c is VBoxContainer:     # (the close button; the name, title and role: the kit sets its own)
			c.visible = false
	var stage: Control = m._show.get_parent()
	stage.anchor_top = 0.12
	stage.anchor_bottom = 0.80
	if zoom != 1.0:
		m._show.zoom_by(zoom)

func _process(_d: float) -> bool:
	if dumping:
		return true
	frames += 1
	if frames == 3:
		_seed()
		app.rebuild()
	if frames >= 12 and (cur < 0 or frames == opened_at + SETTLE + 4):
		cur += 1
		if cur >= queue.size():
			OS.kill(OS.get_process_id())                   # (Godot can hang on exit here)
			return false
		var q: Array = queue[cur]
		app.open_champion(str(q[0]), str(q[1]))
		opened_at = frames
	if cur >= 0 and cur < queue.size() and app.modal != null:
		if frames == opened_at + 2:
			_bare(app.modal)
		var sh = app.modal._show
		if sh != null:
			sh._dragging = true                              # (held: no slow turn of his own)
			sh._yaw = yaw
		if frames == opened_at + SETTLE:
			pending = true
	return false
