extends SceneTree
# 0.31.212: HeyCatch's install guide, "Build and run it yourself if you can": the real app (scripts/app/siege_app.gd,
# a fresh profile, our own server out of reach) with HEYCATCH=1 so a desktop run sends -- to HeyCatch's REAL ingest
# (in.heycatch.ai). It opens on Home, goes through a few tabs, goes to the background (the flush), and prints what
# the ingest answered. On a phone none of the proxy part applies; it's for a machine whose HTTPS goes through a proxy
# (HTTPS_PROXY, with its CA bundle in HEYCATCH_CA).
#   HEYCATCH=1 HEYCATCH_CA=/root/.ccr/ca-bundle.crt godot --headless --path godot -s res://tools/heycatch_verify.gd
# Prints HEYCATCH_VERIFY_OK <batches> (each answered 2xx) or HEYCATCH_VERIFY_FAIL <why>.
const App = preload("res://scripts/app/siege_app.gd")

var app
var t := 0.0
var step := 0
var codes: Array = []

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1/fatebound/siege/ws")   # (never our live server)
	if OS.get_environment("HEYCATCH") != "1":
		print("HEYCATCH_VERIFY_FAIL set HEYCATCH=1")
		quit(1)
		return
	var base := "user://hcverify-%d" % Time.get_ticks_usec()
	app = App.new()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	root.add_child(app)

func _process(d: float) -> bool:
	t += d
	var hc = app.heycatch if app != null else null
	if hc == null:
		if t > 10.0:
			print("HEYCATCH_VERIFY_FAIL the app made no HeyCatch node")
			quit(1)
		return false
	match step:
		0:
			var px := OS.get_environment("HTTPS_PROXY")
			if px != "" and hc._req != null:
				var hp := px.trim_prefix("http://").trim_prefix("https://").split("@")[-1].trim_suffix("/")
				hc._req.set_https_proxy(hp.get_slice(":", 0), int(hp.get_slice(":", 1)))
				var ca_path := OS.get_environment("HEYCATCH_CA")
				if ca_path != "":
					var ca := X509Certificate.new()
					if ca.load(ca_path) == OK:
						hc._req.set_tls_options(TLSOptions.client(ca))
			hc._req.request_completed.connect(func(_r, code, _h, _b): codes.append(code))
			print("HeyCatch active=%s url=%s project=%s id=%s" % [hc.active(), hc.url, hc.PROJECT_KEY, hc.distinct_id()])
			step = 1
		1:
			if t > 3.0:
				for tab in ["shop", "locker", "pass", "alliance", "home"]:
					app.show_tab(tab)
				step = 2
		2:
			if t > 14.0:                                # (session_start waits up to 10 s to learn the server's out of reach)
				app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
				step = 3
		3:
			if t > 30.0 or (not codes.is_empty() and hc.queue.is_empty() and hc._busy.is_empty()):
				var ok: bool = not codes.is_empty() and codes.all(func(c): return int(c) >= 200 and int(c) < 300) and hc.queue.is_empty()
				print("ingest answers: %s, left waiting %d" % [str(codes), hc.queue.size()])
				print(("HEYCATCH_VERIFY_OK %d" % codes.size()) if ok else ("HEYCATCH_VERIFY_FAIL answers %s" % str(codes)))
				quit(0 if ok else 1)
	return false
