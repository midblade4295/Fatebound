extends SceneTree
# Feeds the logcat filter lines shaped like the S21 Ultra report: window/touch noise, a crash
# header, abort message and backtrace, plus driver errors. The whole fatal block must survive.
const Diag = preload("res://scripts/siege/siege_diag.gd")
func _init() -> void:
	var raw := PackedStringArray()
	for i in 3000:
		raw.append("09-27 16:12:%02d.100 I/VRI[GodotAppLauncher]@20b2311(22545): mWNT: t=0xb4 fn= %d" % [i % 60, i])
		if i % 7 == 0:
			raw.append("09-27 16:12:00.000 W/InsetsController(22545): noise %d" % i)
	raw.append("09-27 16:12:40.001 E/Adreno-GSL(22545): <gsl_ldd_control:553>: ioctl fd 38 code 0xc0400913 (IOCTL_KGSL_GPU_COMMAND) failed: errno 35 Resource deadlock would occur")
	raw.append("09-27 16:12:40.002 W/Adreno-GSL(22545): <log_gpu_snapshot:465>: panel.gpuSnapshotPath is not set.not generating user snapshot")
	raw.append("09-27 16:12:41.500 F/libc    (22545): Fatal signal 6 (SIGABRT), code -1 (SI_QUEUE) in tid 22601 (GLThread 1234), pid 22545 (d.kaykitrebuild)")
	raw.append("09-27 16:12:41.700 F/DEBUG   (25169): Abort message: 'example abort'")
	for f in 30:
		raw.append("09-27 16:12:41.761 F/DEBUG   (25169):       #%02d pc 0000000000%06x  /vendor/lib64/egl/libGLESv2_adreno.so" % [f, f * 16])
	raw.append("--------- beginning of crash")
	var out: String = Diag.filter_logcat("\n".join(raw), 120)
	assert(out.contains("Fatal signal 6"))
	assert(out.contains("Abort message"))
	assert(out.contains("#00 pc") and out.contains("#29 pc"))
	assert(out.contains("IOCTL_KGSL_GPU_COMMAND"))
	assert(not out.contains("VRI[") and not out.contains("InsetsController"))
	print(out.substr(0, 600))
	print("SIEGE_LOGCAT_FILTER_PASS lines=", out.split("\n").size())
	quit(0)
