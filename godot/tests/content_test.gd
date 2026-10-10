extends SceneTree
# 0.31.95 content packs: the app starts in the loader, the manifest is sound, the loader's plan (what to mount, what to
# download, what to keep), its byte ranges, and nothing that runs before the packs are mounted needs their files.
#   godot --headless --path godot -s res://tests/content_test.gd
const Loader = preload("res://scripts/app/content_loader.gd")
var fails: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("FAIL ", what)
	else:
		print("ok   ", what)

func _init() -> void:
	check(str(ProjectSettings.get_setting("application/run/main_scene")) == "res://scenes/Boot.tscn", "the app starts in the content loader")
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(Loader.MANIFEST))
	check(m is Dictionary and int(m.get("format", 0)) == 1 and str(m.get("url", "")).begins_with("https://"), "the manifest reads")
	var packs: Array = m.get("packs", []) if m is Dictionary else []
	var names := []
	var sound := true
	for p in packs:
		names.append(str(p.name))
		var f := str(p.file)
		if not (f.begins_with(str(p.name) + "-") and f.ends_with(".pck") and int(p.size) > 1000000 and str(p.sha256).length() == 64):
			sound = false
			print("   bad entry ", p)
		if not ResourceLoader.exists(str(p.probe)):
			sound = false
			print("   probe missing ", p.probe)
	check(names == ["ui", "world", "heroes", "weapons", "audio"] and sound, "5 packs, each named by its hash, sized, with a sha256 and a probe in the project (%s)" % str(names))
	# the plan
	var all := Loader.plan(m, {}, func(_p): return true)
	check((all.mount as Array).is_empty() and (all.fetch as Array).is_empty() and (all.keep as Array).is_empty(), "running from source (every probe there): nothing to do")
	var fresh := Loader.plan(m, {}, func(_p): return false)
	check((fresh.fetch as Array).size() == 5 and (fresh.keep as Array).size() == 5, "a fresh install downloads all 5")
	var have := {str(packs[0].file): str(packs[0].sha256), str(packs[2].file): str(packs[2].sha256), str(packs[3].file): "0bad"}
	var some := Loader.plan(m, have, func(_p): return false)
	check((some.mount as Array).size() == 2 and (some.fetch as Array).size() == 3 and str(some.fetch[1].name) == "weapons",
		"two checked packs mount, a pack whose check doesn't match downloads again")
	check(Loader.range_header(0, 20000000) == "Range: bytes=0-%d" % (Loader.CHUNK - 1) and
		Loader.range_header(2 * Loader.CHUNK, 20000000) == "Range: bytes=%d-19999999" % (2 * Loader.CHUNK), "byte ranges of 8 MB, the last one short")
	# what runs before the packs are mounted (the autoload, its log, the loader) touches only the build's own assets
	var early_ok := true
	var rx := RegEx.new()
	rx.compile("res://assets/[^\"]+")
	for path in ["res://scripts/app/boot_guard.gd", "res://scripts/siege/siege_diag.gd", "res://scripts/app/content_loader.gd", "res://scenes/Boot.tscn"]:
		for hit in rx.search_all(FileAccess.get_file_as_string(path)):
			var a := hit.get_string()
			if not (a.begins_with("res://assets/branding/") or a.begins_with("res://assets/fonts/") or a.begins_with("res://assets/vfx/")):
				early_ok = false
				print("   %s uses %s before the packs are mounted" % [path, a])
	check(early_ok, "the autoload, its log and the loader use only the build's own assets")
	# the base presets leave the packs' files out, and keep the loader's
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	var presets_ok := true
	for block in cfg.split("[preset."):
		if block.contains('name="Android Play Store"') or block.contains('name="Android KayKit Rebuild"'):
			var ex := block.substr(block.find("exclude_filter=")).get_slice("\n", 0)
			for pat in ["assets/ui/*", "assets/meshy/weapons/*", "assets/meshy/knight/*", "assets/kaykit/*", "assets/music/*"]:
				if not ex.contains(pat):
					presets_ok = false
					print("   a base preset ships ", pat)
			if ex.contains("assets/branding") or ex.contains("assets/fonts"):
				presets_ok = false
	check(presets_ok, "both base presets (Play, itch) leave the packs' files out and keep the loader's")
	var out := []
	var code := OS.execute("python3", [ProjectSettings.globalize_path("res://tools/content_packs.py"), "coverage"], out, true)
	check(code == 0, "every asset is in exactly one pack or the base (%s)" % str(out).left(200))
	print("CONTENT_PASS" if fails.is_empty() else "CONTENT_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
