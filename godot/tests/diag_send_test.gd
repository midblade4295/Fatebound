extends SceneTree
# 0.31.120 (Kevin: "SEND TO DEVELOPER"): the player sends the game's log from Settings, asked every time.
#  1. server/diag_reports.gd: nothing to send -> "empty"; a report is kept as diag/<time>-<ID>.txt (a JSON header, then
#     the log, control characters out, the note at most 500); the account only when its key opens it; 4 an hour from
#     one account or one address, then "busy"; the oldest go past the limits
#  2. App.diag_message: a huge log is fitted under one packet once compressed (its first lines and its end kept)
#  3. the REAL server (port 8109) and the real app: Settings > SEND TO DEVELOPER > a note > SEND: "Sent -- report #ID";
#     the server has it with the note, the build and the account; tools/diag_reports.py lists it and shows it
#   godot --headless --path godot -s res://tests/diag_send_test.gd
const DiagReports = preload("res://server/diag_reports.gd")
const Accounts = preload("res://server/eco_accounts.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const Diag = preload("res://scripts/siege/siege_diag.gd")
const App = preload("res://scripts/app/siege_app.gd")

var fails: Array = []
var port := 8109
var url := ""
var pid := -1
var sd := ""
var phase := "boot"
var t_phase := 0.0
var acct := {}
var notes := {}
var app

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _files(dir: String) -> Array:
	var out := []
	var da := DirAccess.open(dir)
	if da != null:
		for f in da.get_files():
			if f.ends_with(".txt"):
				out.append(f)
	out.sort()
	return out

func _init() -> void:
	# --- 1. the server's side
	var tmp := OS.get_user_data_dir().path_join("diag-unit-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var acc = Accounts.new(tmp)
	var a: Dictionary = acc.handle({"t":"eco", "new":true})
	var dr = DiagReports.new(tmp)
	check(str(dr.handle({"t":"diag", "log":"  ", "note":""}, acc, "1.2.3.4").why) == "empty", "nothing to send: refused")
	var r: Dictionary = dr.handle({"t":"diag", "acct":str(a.acct), "key":str(a.key), "name":"Kev", "build":"0.31.120-fatebound",
		"dev":{"model":"SM-G998U", "os":"Android 14", "gpu":"Mali-G78"}, "note":"x".repeat(900),
		"log":"==== siege_diag.log ====\nline one" + String.chr(7) + String.chr(27) + "\nERROR: boom\n"}, acc, "1.2.3.4")
	var files := _files(tmp.path_join("diag"))
	check(bool(r.ok) and str(r.id).length() == 6 and files.size() == 1 and str(files[0]).ends_with("-%s.txt" % r.id), "a report: kept as diag/<time>-%s.txt" % str(r.get("id", "")))
	var lines := FileAccess.get_file_as_string(tmp.path_join("diag").path_join(files[0])).split("\n")
	var head: Variant = JSON.parse_string(lines[0])
	check(head is Dictionary and str(head.acct) == str(a.acct) and str(head.model) == "SM-G998U" and str(head.build) == "0.31.120-fatebound"
		and str(head.note).length() == 500 and str(head.name) == "Kev", "its header: the account, phone, build, name, the note cut to 500")
	check(lines[2] == "line one" and lines[3] == "ERROR: boom", "the log after it, control characters out")
	var r2: Dictionary = dr.handle({"t":"diag", "acct":str(a.acct), "key":"0".repeat(64), "log":"x"}, acc, "5.6.7.8")
	var anon := false
	for f in _files(tmp.path_join("diag")):
		if str(f).contains(str(r2.get("id", "?"))):
			anon = str((JSON.parse_string(FileAccess.get_file_as_string(tmp.path_join("diag").path_join(f)).split("\n")[0]) as Dictionary).acct) == ""
	check(bool(r2.ok) and anon, "a wrong key: still taken, as anonymous")
	for i in 3:
		dr.handle({"t":"diag", "acct":str(a.acct), "key":str(a.key), "log":"again"}, acc, "9.9.9.9")
	check(str(dr.handle({"t":"diag", "acct":str(a.acct), "key":str(a.key), "log":"again"}, acc, "9.9.9.9").get("why", "")) == "busy",
		"a 5th from one account within the hour: busy")
	for i in 3:
		dr.handle({"t":"diag", "log":"anon"}, acc, "5.6.7.8")
	check(str(dr.handle({"t":"diag", "log":"anon"}, acc, "5.6.7.8").get("why", "")) == "busy" and bool(dr.handle({"t":"diag", "log":"anon"}, acc, "5.6.7.9").ok),
		"...and from one address: busy (another address: fine)")
	dr.now_override = int(Time.get_unix_time_from_system()) + 3700
	check(bool(dr.handle({"t":"diag", "acct":str(a.acct), "key":str(a.key), "log":"later"}, acc, "9.9.9.9").ok), "an hour later: fine again")
	dr.now_override = -1
	dr.keep_files = 3
	dr._prune()
	check(_files(tmp.path_join("diag")).size() == 3, "past the limits the oldest go")
	# --- 2. fitting a huge log
	var big := ""
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var parts := PackedStringArray()
	parts.append("SESSION START build 0.31.120 head line")
	for i in 30000:
		parts.append("%d frame %x %x" % [i, rng.randi(), rng.randi()])
	parts.append("THE VERY END")
	big = "\n".join(parts)
	var p = Profile.new("user://diag-p-%d.json" % Time.get_ticks_usec(), "user://none.json")
	p.load_or_create()
	var m: Dictionary = App.diag_message("it froze", big, p)
	var enc := Net.encode(m, true)
	check(enc.size() <= Net.MAX_PACKET - 2048 and str(m.log).begins_with("SESSION START") and str(m.log).ends_with("THE VERY END")
		and str(m.log).contains("characters left out") and not m.has("acct"),
		"a %d KB log fitted into one packet (%d bytes compressed), its start and end kept" % [big.length() / 1024, enc.size()])
	var small: Dictionary = App.diag_message("", "short log", p)
	check(str(small.log) == "short log" and str(small.dev.os) != "", "a short one goes whole, with the phone's details")
	# --- 3. the real thing
	url = "ws://127.0.0.1:%d" % port
	sd = OS.get_user_data_dir().path_join("diag-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(sd)
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("STATE_DIRECTORY", sd)
	OS.set_environment("SIEGE_MIN_BUILD", "off")
	OS.set_environment("SIEGE_URL", url)
	var sacc = Accounts.new(sd)
	var sa: Dictionary = sacc.handle({"t":"eco", "new":true})
	acct = {"acct":str(sa.acct), "key":str(sa.key)}
	var f := FileAccess.open(Diag.PATH, FileAccess.WRITE)
	f.store_string("SESSION 0.31.120 test\nERROR: a test error for the report\nlast line\n")
	f.close()
	pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(pid > 0, "server process started")

func _find(node: Node, pred: Callable) -> Array:
	var out := []
	if pred.call(node):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find(c, pred))
	return out

func _btn(key: String) -> Button:
	var b := _find(app, func(n): return n is Button and str(n.get_meta("action_key", "")) == key and (n as Button).is_visible_in_tree())
	return b[0] if not b.is_empty() else null

func _go(p: String) -> void:
	phase = p
	t_phase = 0.0

func _process(delta: float) -> bool:
	t_phase += delta
	match phase:
		"boot":
			if t_phase > 2.0:
				var base := "user://diagtest-%d" % Time.get_ticks_usec()
				var p = Profile.new(base + "-profile.json", base + "-none.json")
				p.load_or_create()
				p.d.name = "Kevin"
				p.d.account = {"id":acct.acct, "key":acct.key, "seq":0}
				p.d.tutorial_done = true
				p.save()
				app = App.new()
				app.profile_path = base + "-profile.json"
				app.legacy_path = base + "-none.json"
				root.add_child(app)
				_go("settings")
		"settings":
			if t_phase > 0.5:
				app.show_tab("settings")
				var b := _btn("send_diag")
				check(b != null, "Settings: SEND TO DEVELOPER")
				if b == null:
					_finish()
					return false
				b.pressed.emit()
				var note := _find(app.modal, func(n): return n is LineEdit and n.name == "DiagNote")
				check(app.modal != null and not note.is_empty() and _btn("diag_send") != null and _btn("diag_cancel") != null,
					"it asks first: what's sent, a note, SEND / CANCEL")
				if note.is_empty():
					_finish()
					return false
				(note[0] as LineEdit).text = "Froze on the loading screen"
				_btn("diag_send").pressed.emit()
				check(_btn("diag_send") != null and _btn("diag_send").text == "SENDING...", "SEND: SENDING...")
				_go("sent")
		"sent":
			if str(app._toast.text).begins_with("Sent -- report #"):
				var id := str(app._toast.text).trim_prefix("Sent -- report #").get_slice(".", 0)
				check(id.length() == 6 and not is_instance_valid(app.modal), "Sent -- report #%s; the card closes" % id)
				var files := _files(sd.path_join("diag"))
				var ok := false
				if files.size() == 1:
					var txt := FileAccess.get_file_as_string(sd.path_join("diag").path_join(files[0]))
					var head: Dictionary = JSON.parse_string(txt.split("\n")[0])
					ok = str(head.id) == id and str(head.note) == "Froze on the loading screen" and str(head.acct) == str(acct.acct) \
						and str(head.build) == Diag.BUILD and str(head.name) == "Kevin" and txt.contains("ERROR: a test error for the report")
				check(ok, "the server has it: the note, the account, the build, the log")
				var out := []
				OS.execute("python3", [ProjectSettings.globalize_path("res://tools/diag_reports.py"), "--dir", sd], out, true)
				check(str(out[0]).contains("1 report(s)") and str(out[0]).contains("#" + id) and str(out[0]).contains("Froze on the loading"),
					"tools/diag_reports.py lists it")
				out = []
				OS.execute("python3", [ProjectSettings.globalize_path("res://tools/diag_reports.py"), "--dir", sd, "show", id, "--errors"], out, true)
				check(str(out[0]).contains("Report #" + id) and str(out[0]).contains("ERROR: a test error") and not str(out[0]).contains("last line"),
					"...and shows it (--errors: the error lines)")
				_finish()
			elif t_phase > 10.0:
				check(false, "sent within 10 s (toast: %s)" % str(app._toast.text))
				_finish()
	return false

func _finish() -> void:
	if pid > 0:
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])
		pid = -1
	print("DIAG_SEND_PASS" if fails.is_empty() else "DIAG_SEND_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
