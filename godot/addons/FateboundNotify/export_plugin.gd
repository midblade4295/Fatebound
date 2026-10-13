@tool
extends EditorPlugin
# 0.31.119: hands the FateboundNotify AAR (godot/android_plugins/fatebound_notify) to Gradle exports only -- the Play
# Store preset. The preview presets export without Gradle and stay as they were (no notifications there).

var export_plugin: NotifyExportPlugin

func _enter_tree():
	export_plugin = NotifyExportPlugin.new()
	add_export_plugin(export_plugin)

func _exit_tree():
	remove_export_plugin(export_plugin)
	export_plugin = null

class NotifyExportPlugin extends EditorExportPlugin:
	var _plugin_name = "FateboundNotify"

	func _supports_platform(platform):
		return platform is EditorExportPlatformAndroid

	func _uses_gradle() -> bool:
		return bool(get_option("gradle_build/use_gradle_build"))

	func _get_android_libraries(platform, debug):
		if not _uses_gradle():
			return PackedStringArray()
		if debug:
			return PackedStringArray([_plugin_name + "/bin/debug/" + _plugin_name + "-debug.aar"])
		return PackedStringArray([_plugin_name + "/bin/release/" + _plugin_name + "-release.aar"])

	func _get_name():
		return _plugin_name
