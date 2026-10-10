extends Control
# The content loader (0.31.95, Kevin: "the main game installs a small file from the Play store and itch, then when
# they launch the game after first install the game will say it's updating"). The first scene the app runs.
#
# The installed build holds the engine, the scripts and scenes, the fonts and the launcher art; the game's art and
# sound are content packs (.pck) on a GitHub release, listed in res://content/manifest.json (tools/content_packs.py).
# Each start: a pack whose files are already in res:// (running from source, or a full build) needs nothing; one
# downloaded and checked before (user://packs/<file>, sha256 in verified.json) is mounted; any other is downloaded
# -- "UPDATING", in 8 MB ranges appended to a .part file (an interrupted download resumes where it stopped, even after
# the app is closed), hashed as it arrives, checked against the manifest's sha256 -- then mounted. Packs no build of
# this install lists any more are deleted. Then the game (Main.tscn) starts. A code-only update downloads nothing;
# new art re-downloads only the packs it is in.
# Packs never replace the build's own files (load_resource_pack(..., false)) and hold data only (no scripts).
const MANIFEST := "res://content/manifest.json"
const UIDS := "res://content/uids.json"        # the packs' resources' UIDs (the build's uid cache only has its own)
const DIR := "user://packs"
const VERIFIED := "user://packs/verified.json"
const MAIN := "res://scenes/Main.tscn"
const CHUNK := 8 * 1024 * 1024
const RETRY := [2.0, 4.0, 8.0, 15.0, 30.0]
const TITLE_FONT = preload("res://assets/fonts/LuckiestGuy-Regular.ttf")
const BODY_FONT = preload("res://assets/fonts/Nunito-ExtraBold.woff2")
const GOLD := Color("#ffc23d")

var manifest: Dictionary = {}
var base_url := ""
var todo: Array = []              # packs to download, in order
var ready_packs: Array = []       # packs to mount
var verified: Dictionary = {}
var total := 0                    # bytes to download this start
var done_bytes := 0               # finished packs' bytes
var cur := -1                     # index in todo
var offset := 0                   # bytes of the current pack on disk
var hasher: HashingContext
var http: HTTPRequest
var fails := 0
var bad_checks := 0
var wait := 0.0
var _speed_t := 0.0
var _speed_b := 0
var speed := 0.0
var guard: Node = null
var finished := false
var status_note := ""

var bar: ProgressBar
var title: Label
var line: Label
var note: Label
var retry_btn: Button

# ---------- pure parts (tests/content_test.gd) ----------
static func plan(m: Dictionary, have: Dictionary, present: Callable) -> Dictionary:
	# have: file -> sha256 of the packs on the phone, checked; present(probe) -> that pack's files are in res:// already
	var mount := []
	var fetch := []
	var keep := []
	for p in m.get("packs", []):
		if present.call(str(p.probe)):
			continue
		keep.append(str(p.file))
		if str(have.get(str(p.file), "")) == str(p.sha256):
			mount.append(p)
		else:
			fetch.append(p)
	return {"mount": mount, "fetch": fetch, "keep": keep}

static func range_header(at: int, size: int) -> String:
	return "Range: bytes=%d-%d" % [at, mini(at + CHUNK, size) - 1]

static func mb(b: int) -> String:
	return "%.1f MB" % (b / 1048576.0)

# ---------- start ----------
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_meta("content_loader", true)
	guard = get_node_or_null("/root/BootGuard")
	_build_ui()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) if FileAccess.file_exists(MANIFEST) else null
	if not (parsed is Dictionary):
		_log("CONTENT no manifest: starting the game as it is")
		_start_game.call_deferred()
		return
	manifest = parsed
	base_url = OS.get_environment("FB_CONTENT_URL") if OS.has_environment("FB_CONTENT_URL") else str(manifest.get("url", ""))
	DirAccess.make_dir_recursive_absolute(DIR)
	verified = _read_verified()
	var have := {}
	for f in verified:
		if FileAccess.file_exists(DIR.path_join(f)):
			have[f] = verified[f]
	var pl := plan(manifest, have, func(probe: String) -> bool: return ResourceLoader.exists(probe))
	ready_packs = pl.mount
	todo = pl.fetch
	_cleanup(pl.keep)
	_log("CONTENT %d packs: %d in the build, %d on the phone, %d to download" % [(manifest.get("packs", []) as Array).size(),
		(manifest.get("packs", []) as Array).size() - (pl.keep as Array).size(), ready_packs.size(), todo.size()])
	if todo.is_empty():
		_mount_and_start.call_deferred()
		return
	for p in todo:
		total += int(p.size)
	if guard != null and guard.has_method("hold"):
		guard.hold(true)                     # a download is not a frozen start
	visible = true
	http = HTTPRequest.new()
	http.accept_gzip = false                 # byte ranges of the file as it is
	http.use_threads = true
	http.timeout = 30.0
	_net_options(http)
	add_child(http)
	http.request_completed.connect(_on_chunk)
	_next_pack()

func _net_options(h: HTTPRequest) -> void:
	# (desktop testing behind a proxy: FB_CONTENT_PROXY host:port, FB_CONTENT_CA a PEM bundle)
	if OS.has_environment("FB_CONTENT_PROXY"):
		var hp := OS.get_environment("FB_CONTENT_PROXY").split(":")
		h.set_https_proxy(hp[0], int(hp[1]))
		h.set_http_proxy(hp[0], int(hp[1]))
	if OS.has_environment("FB_CONTENT_CA"):
		var cert := X509Certificate.new()
		if cert.load(OS.get_environment("FB_CONTENT_CA")) == OK:
			h.set_tls_options(TLSOptions.client(cert))

# ---------- downloading ----------
func _next_pack() -> void:
	cur += 1
	if cur >= todo.size():
		_mount_and_start()
		return
	var p: Dictionary = todo[cur]
	var part := _part(p)
	hasher = HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	offset = 0
	if FileAccess.file_exists(part):
		# resume: hash what is there (in steps, so the screen keeps drawing), then fetch the rest
		var f := FileAccess.open(part, FileAccess.READ)
		if f != null:
			var n := f.get_length()
			if n > int(p.size):
				f.close()
				DirAccess.remove_absolute(part)
			else:
				while f.get_position() < n:
					hasher.update(f.get_buffer(mini(4 << 20, n - f.get_position())))
					await get_tree().process_frame
				offset = n
				f.close()
	_log("CONTENT %s: %s of %s already here" % [p.name, mb(offset), mb(int(p.size))])
	_request()

func _part(p: Dictionary) -> String:
	return DIR.path_join(str(p.file) + ".part")

func _request() -> void:
	var p: Dictionary = todo[cur]
	if offset >= int(p.size):
		_finish_pack()
		return
	var err := http.request(base_url + str(p.file), [range_header(offset, int(p.size))])
	if err != OK:
		_trouble("Couldn't start the download (%d)" % err)

func _on_chunk(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var p: Dictionary = todo[cur]
	if result != HTTPRequest.RESULT_SUCCESS or not (code == 206 or code == 200) or body.is_empty():
		_trouble("No connection" if result != HTTPRequest.RESULT_SUCCESS else "Download problem (HTTP %d)" % code)
		return
	var part := _part(p)
	if code == 200:
		# the server sent the whole file instead of the range: start this pack over with it
		if body.size() != int(p.size):
			_trouble("Download problem (whole file, wrong size)")
			return
		DirAccess.remove_absolute(part)
		hasher = HashingContext.new()
		hasher.start(HashingContext.HASH_SHA256)
		offset = 0
	var f := FileAccess.open(part, FileAccess.READ_WRITE) if FileAccess.file_exists(part) else FileAccess.open(part, FileAccess.WRITE)
	if f == null:
		_trouble("Couldn't save the download — is the phone full? (%s needed)" % mb(total - done_bytes - offset))
		return
	f.seek_end()
	f.store_buffer(body)
	var err := f.get_error()
	f.close()
	if err != OK:
		_trouble("Couldn't save the download — is the phone full? (%s needed)" % mb(total - done_bytes - offset))
		return
	hasher.update(body)
	offset += body.size()
	fails = 0
	status_note = ""
	if offset >= int(p.size):
		_finish_pack()
	else:
		_request()

func _finish_pack() -> void:
	var p: Dictionary = todo[cur]
	var sha := hasher.finish().hex_encode()
	var part := _part(p)
	if sha != str(p.sha256):
		_log("CONTENT %s: check failed (%s), downloading it again" % [p.name, sha.substr(0, 12)])
		DirAccess.remove_absolute(part)
		offset = 0
		hasher = HashingContext.new()
		hasher.start(HashingContext.HASH_SHA256)
		bad_checks += 1
		if bad_checks > 2:
			_trouble("The download was damaged — trying again")
			return
		_request()
		return
	var final := DIR.path_join(str(p.file))
	if FileAccess.file_exists(final):
		DirAccess.remove_absolute(final)
	DirAccess.rename_absolute(part, final)
	verified[str(p.file)] = sha
	_write_verified()
	done_bytes += int(p.size)
	ready_packs.append(p)
	_log("CONTENT %s downloaded and checked" % p.name)
	_next_pack()

func _trouble(why: String) -> void:
	fails += 1
	wait = RETRY[mini(fails - 1, RETRY.size() - 1)]
	status_note = why
	_log("CONTENT trouble: %s (retry in %ds)" % [why, int(wait)])
	retry_btn.visible = true

func _retry_now() -> void:
	if wait > 0.0:
		wait = 0.0
		retry_btn.visible = false
		status_note = ""
		_request()

func _process(delta: float) -> void:
	if finished or http == null:
		return
	if wait > 0.0:
		wait -= delta
		if wait <= 0.0:
			wait = 0.0
			retry_btn.visible = false
			_request()
	var now := done_bytes + offset + (http.get_downloaded_bytes() if http.get_http_client_status() == HTTPClient.STATUS_BODY else 0)
	_speed_t += delta
	if _speed_t >= 1.0:
		speed = lerpf(speed, (now - _speed_b) / _speed_t, 0.5 if speed > 0.0 else 1.0)
		_speed_b = now
		_speed_t = 0.0
	bar.value = 100.0 * now / maxf(total, 1)
	if status_note != "":
		line.text = "%s — retrying in %d s" % [status_note, ceili(wait)] if wait > 0.0 else status_note
	else:
		line.text = "%s / %s%s" % [mb(now), mb(total), ("   ·   %.1f MB/s" % (speed / 1048576.0)) if speed > 0.0 else ""]

# ---------- mount and go ----------
func _mount_and_start() -> void:
	finished = true
	for p in ready_packs:
		var path := DIR.path_join(str(p.file))
		if not ProjectSettings.load_resource_pack(path, false):
			_log("CONTENT %s would not mount: downloading it again" % p.name)
			verified.erase(str(p.file))
			_write_verified()
			DirAccess.remove_absolute(path)
			get_tree().reload_current_scene.call_deferred()
			return
	if total > 0:
		line.text = "Ready!"
		bar.value = 100.0
	_log("CONTENT mounted %d packs, %d UIDs" % [ready_packs.size(), _register_uids()])
	if guard != null and guard.has_method("hold"):
		guard.hold(false)
	_start_game.call_deferred()

func _register_uids() -> int:
	if ready_packs.is_empty() or not FileAccess.file_exists(UIDS):
		return 0
	var map: Variant = JSON.parse_string(FileAccess.get_file_as_string(UIDS))
	if not (map is Dictionary):
		return 0
	var n := 0
	for u in map:
		var id := ResourceUID.text_to_id(str(u))
		if id != ResourceUID.INVALID_ID and not ResourceUID.has_id(id):
			ResourceUID.add_id(id, str(map[u]))
			n += 1
	return n

func _start_game() -> void:
	get_tree().change_scene_to_file(MAIN)

func _cleanup(keep: Array) -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	var gone := false
	for f in d.get_files():
		if f == "verified.json":
			continue
		var base := f.trim_suffix(".part")
		if not keep.has(base):
			d.remove(f)
			verified.erase(base)
			gone = true
			_log("CONTENT removed old pack %s" % f)
	if gone:
		_write_verified()

func _read_verified() -> Dictionary:
	if FileAccess.file_exists(VERIFIED):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(VERIFIED))
		if v is Dictionary:
			return v
	return {}

func _write_verified() -> void:
	var f := FileAccess.open(VERIFIED, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(verified))
		f.close()

func _log(s: String) -> void:
	print(s)
	if guard != null and guard.has_method("mark"):
		guard.mark(s)

# ---------- the screen ----------
func _build_ui() -> void:
	visible = false                          # shown only when something has to be downloaded
	var bg := TextureRect.new()
	bg.texture = load("res://assets/branding/background.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.05, 0.12, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 28
	col.offset_right = -28
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	add_child(col)
	var hero := TextureRect.new()
	hero.texture = load("res://assets/branding/foreground.png")
	hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero.custom_minimum_size = Vector2(0, 300)
	col.add_child(hero)
	title = _label("FATEBOUND", TITLE_FONT, 54, Color.WHITE, 12)
	col.add_child(title)
	col.add_child(_label("UPDATING", TITLE_FONT, 30, GOLD, 8))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	col.add_child(gap)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 30)
	bar.show_percentage = false
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.03, 0.06, 0.14, 0.85)
	back.set_corner_radius_all(15)
	back.border_color = Color(1, 1, 1, 0.35)
	back.set_border_width_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(15)
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	col.add_child(bar)
	line = _label("", BODY_FONT, 20, Color.WHITE, 6)
	col.add_child(line)
	note = _label("Downloading the game's art and sound. This happens once — later updates only download what changed. Wi-Fi recommended.",
		BODY_FONT, 16, Color(1, 1, 1, 0.85), 5)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)
	retry_btn = Button.new()
	retry_btn.text = "RETRY NOW"
	retry_btn.visible = false
	retry_btn.add_theme_font_override("font", TITLE_FONT)
	retry_btn.add_theme_font_size_override("font_size", 24)
	retry_btn.custom_minimum_size = Vector2(220, 56)
	retry_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color("#e8892a")
	bs.set_corner_radius_all(14)
	bs.border_color = Color("#7a3a0c")
	bs.set_border_width_all(3)
	retry_btn.add_theme_stylebox_override("normal", bs)
	retry_btn.add_theme_stylebox_override("hover", bs)
	retry_btn.add_theme_stylebox_override("pressed", bs)
	retry_btn.pressed.connect(_retry_now)
	col.add_child(retry_btn)

func _label(t: String, font: Font, size: int, c: Color, outline: int) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
	l.add_theme_constant_override("outline_size", outline)
	return l
