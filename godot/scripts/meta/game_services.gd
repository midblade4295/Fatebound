extends RefCounted
# 0.31.130 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §1): which store's game services the app uses. Both have one face
# (signals changed / note / ask / restored; state, player, why, achievements; setup, active, sign_in, back_up_now,
# choose, pending_choice, on_pause, on_resume, signed_in, show_achievements, last_backup), so the app and Settings only
# ever talk to what this hands back:
#   Android (and the desktop, where nothing is active)  scripts/meta/play_games.gd    Google Play Games, unchanged
#   iOS                                                 scripts/meta/game_center.gd   Game Center
# Achievements are counted the same for both (achievements.gd, by key); each service maps a key to its own id.
const Platform = preload("res://scripts/meta/platform.gd")
const PlayGames = preload("res://scripts/meta/play_games.gd")
const GameCenter = preload("res://scripts/meta/game_center.gd")

static func script_for(store: String = "") -> Script:
	return GameCenter if (store if store != "" else Platform.store()) == "appstore" else PlayGames

static func make(store: String = "") -> Node:
	return script_for(store).new()

static func is_game_center(s) -> bool:
	return s != null and s.get_script() == GameCenter
