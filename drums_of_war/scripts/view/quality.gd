extends RefCounted
## Keeps the battle smooth on whatever device it is running on.
##
## The battle screen reports the frame rate once a second. If it stays under the target, the
## next level down is applied, each one trading a little finish for speed, until the rate
## holds. The level reached is remembered between launches. It never climbs back by itself
## (that would see-saw); tapping the FPS readout starts again from the top.
##
## The picture is always drawn at the screen's full resolution: no level scales it down.
##
## Level 0  everything on: this is what the game is built to run at
##       1  no bloom, no multisample antialiasing
##       2  hard-edged shadows, coarser distant models
##       3  no live shadows (the woods' baked shade and the blob shadows remain), plainer ground
##       4  no falling leaves or motes, coarser models again
##
## Multisample antialiasing and bloom are only used on screens under 1300 pixels across. On a
## denser screen each is a pass over millions more pixels (measured on a 1440 x 3200 phone:
## about 10 ms and 7 ms of a 16.7 ms frame), antialiasing cannot be seen at that pixel size, and
## what bloom did for the gun flashes is done by the glow painted under them.
##
## It is a safety net for weak devices, so it is slow to act: the rate has to stay well under
## the target for several seconds before anything is given up.

const PATH := "user://quality.cfg"
const MAX_LEVEL := 4
const LOD_PIXELS := [2.5, 2.5, 4.0, 5.0, 8.0]

var level: int = 0
var target: float = 60.0
var enabled: bool = true
var _bad: int = 0
var _settle: int = 3               # readings to ignore after a change (or at the start)


func _init() -> void:
	enabled = DisplayServer.get_name() != "headless" and not OS.has_environment("DRUMS_NO_GOVERNOR")
	var rate := DisplayServer.screen_get_refresh_rate()
	target = clampf(rate, 30.0, 60.0) if rate > 1.0 else 60.0
	if enabled:
		var file := ConfigFile.new()
		if file.load(PATH) == OK:
			level = clampi(int(file.get_value("quality", "level_v5", 0)), 0, MAX_LEVEL)


func _save() -> void:
	if not enabled:
		return
	var file := ConfigFile.new()
	file.set_value("quality", "level_v5", level)
	file.save(PATH)


## Applies the current level. world is the battle world (battle_world.gd).
func apply(world: Node, viewport: Viewport) -> void:
	var size := DisplayServer.window_get_size()
	var dense := mini(size.x, size.y) >= 1300
	if OS.has_environment("DRUMS_DENSE"):
		dense = true                    # for trying the dense-screen settings on a desktop
	viewport.scaling_3d_scale = 1.0
	viewport.msaa_3d = Viewport.MSAA_2X if level < 1 and not dense else Viewport.MSAA_DISABLED
	# On a dense screen a triangle a few pixels across is far too small to see: let models
	# drop to a coarser level sooner there.
	viewport.mesh_lod_threshold = float(LOD_PIXELS[level]) * (1.6 if dense else 1.0)
	RenderingServer.directional_soft_shadow_filter_set_quality(
			RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW if level < 2 else RenderingServer.SHADOW_QUALITY_HARD)
	world.set_quality(level, level < 1 and not dense)


## Call once a second with the measured frame rate while a battle is running.
func report(fps: float, world: Node, viewport: Viewport) -> void:
	if not enabled:
		return
	if _settle > 0:
		_settle -= 1
		return
	if fps >= target * 0.78:
		_bad = 0
		return
	_bad += 1
	if _bad >= 4 and level < MAX_LEVEL:
		level += 1
		_bad = 0
		_settle = 2
		apply(world, viewport)
		_save()


## Back to the top, to be judged afresh.
func restart(world: Node, viewport: Viewport) -> void:
	level = 0
	_bad = 0
	_settle = 3
	apply(world, viewport)
	_save()
