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
## Level 0  everything on
##       1  no bloom, no multisample antialiasing
##       2  hard-edged shadows, no rim light, coarser distant models
##       3  trees no longer cast real shadows (their soft pools on the ground remain)
##       4  no real shadows at all (blob shadows remain), plainer ground
##       5  no falling leaves or motes, no fill light, coarser models again

const PATH := "user://quality.cfg"
const MAX_LEVEL := 5
const LOD_PIXELS := [2.5, 2.5, 4.0, 4.0, 5.0, 8.0]

var level: int = 0
var target: float = 60.0
var enabled: bool = true
var _bad: int = 0
var _settle: int = 3               # readings to ignore after a change (or at the start)


func _init() -> void:
	enabled = DisplayServer.get_name() != "headless"
	var rate := DisplayServer.screen_get_refresh_rate()
	target = clampf(rate, 30.0, 60.0) if rate > 1.0 else 60.0
	if enabled:
		var file := ConfigFile.new()
		if file.load(PATH) == OK:
			level = clampi(int(file.get_value("quality", "level", 0)), 0, MAX_LEVEL)


func _save() -> void:
	if not enabled:
		return
	var file := ConfigFile.new()
	file.set_value("quality", "level", level)
	file.save(PATH)


## Applies the current level. world is the battle world (battle_world.gd).
func apply(world: Node, viewport: Viewport) -> void:
	viewport.msaa_3d = Viewport.MSAA_2X if level < 1 else Viewport.MSAA_DISABLED
	viewport.scaling_3d_scale = 1.0
	viewport.mesh_lod_threshold = float(LOD_PIXELS[level])
	RenderingServer.directional_soft_shadow_filter_set_quality(
			RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW if level < 2 else RenderingServer.SHADOW_QUALITY_HARD)
	world.set_quality(level)


## Call once a second with the measured frame rate while a battle is running.
func report(fps: float, world: Node, viewport: Viewport) -> void:
	if not enabled:
		return
	if _settle > 0:
		_settle -= 1
		return
	if fps >= target * 0.86:
		_bad = 0
		return
	_bad += 1
	if _bad >= 2 and level < MAX_LEVEL:
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
