@tool
extends EditorPlugin
# Godot Play Game Services 3.4.0 (Play Games Services v2), MIT licence (LICENSE). Fatebound's copy of its export plugin
# (0.31.102, Kevin: "Google play account linking to the game"):
#  - no autoload: the game talks to the Android singleton through scripts/meta/play_games.gd, never through the
#    plugin's GDScript wrappers (not copied);
#  - Gradle presets only ("Android Play Store", com.fatebound.game): the preview presets export as before;
#  - nothing at all is packed until the Play Games project's numeric Game ID is set -- the export option
#    godot_play_game_services/game_id on the preset, or PLAY_GAMES_APP_ID in the environment -- because the Play Games
#    SDK stops the app at start without its APP_ID. With no ID the feature is simply absent (Settings says so).
#  - the ID goes into res/values/play_games_ids.xml (its own file: Godot's template has no strings.xml to share).

var _export_plugin: AndroidExportPlugin

func _enter_tree() -> void:
	_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null

class AndroidExportPlugin extends EditorExportPlugin:
	var _plugin_name = &"GodotPlayGameServices"

	func _supports_platform(platform):
		return platform is EditorExportPlatformAndroid

	func _game_id() -> String:
		var id := str(get_option("godot_play_game_services/game_id")).strip_edges()
		if id == "" and OS.has_environment("PLAY_GAMES_APP_ID"):
			id = OS.get_environment("PLAY_GAMES_APP_ID").strip_edges()
		return id if id.is_valid_int() else ""

	func _on() -> bool:
		return bool(get_option("gradle_build/use_gradle_build")) and _game_id() != ""

	func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
		if not bool(get_option("gradle_build/use_gradle_build")):
			return
		if _game_id() == "":
			print("[GodotPlayGameServices] no Game ID (godot_play_game_services/game_id or PLAY_GAMES_APP_ID): exported without Google Play Games.")
			return
		DirAccess.make_dir_recursive_absolute("res://android/build/res/values")
		var file := FileAccess.open("res://android/build/res/values/play_games_ids.xml", FileAccess.WRITE)
		if file == null:
			printerr("[GodotPlayGameServices] could not write play_games_ids.xml")
			return
		file.store_string("<?xml version=\"1.0\" encoding=\"utf-8\"?><resources><string translatable=\"false\" name=\"game_services_project_id\">%s</string></resources>" % _game_id())
		file.close()
		print("[GodotPlayGameServices] Game ID %s in res/values/play_games_ids.xml" % _game_id())

	func _get_android_libraries(platform, debug):
		if not _on():
			return PackedStringArray()
		if debug:
			return PackedStringArray([_plugin_name + "/bin/debug/" + _plugin_name + "-debug.aar"])
		return PackedStringArray([_plugin_name + "/bin/release/" + _plugin_name + "-release.aar"])

	func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		if not _supports_platform(platform) or not _on():
			return PackedStringArray()
		return PackedStringArray(["com.google.code.gson:gson:2.11.0", "com.google.android.gms:play-services-games-v2:21.0.0"])

	func _get_android_manifest_application_element_contents(platform: EditorExportPlatform, debug: bool) -> String:
		if not _supports_platform(platform) or not _on():
			return ""
		return "<meta-data android:name=\"com.google.android.gms.games.APP_ID\" android:value=\"@string/game_services_project_id\"/>"

	func _get_name():
		return _plugin_name

	func _get_export_options(platform: EditorExportPlatform) -> Array[Dictionary]:
		if platform.get_os_name() != "Android":
			return []
		return [{"option": {"name": "godot_play_game_services/game_id", "type": TYPE_STRING, "hint": PROPERTY_HINT_NONE,
			"hint_string": "The Play Games Services project's Game ID (digits)"}, "default_value": ""}]
