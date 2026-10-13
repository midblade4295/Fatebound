extends RefCounted
# 0.31.119: the Google Play Games achievement ids, from Play Console > Play Games Services > Achievements (each one's
# "ID", like "CgkI...EAIQAQ"). Grokbot/Kevin fill these in after creating the achievements listed in
# godot/PLAY_ACHIEVEMENTS_HANDOFF.md; an empty id is skipped (nothing is sent for it). A script, not a JSON file, so
# every export carries it.
const IDS := {
	"welcome": "",
	"first_blood": "",
	"first_victory": "",
	"kings_rescue": "",
	"many_hats": "",
	"fattening": "",
	"lumberjack": "",
	"gatecrasher": "",
	"heavy_lifting": "",
	"centurion": "",
	"relentless": "",
	"unstoppable": "",
	"bodyguard": "",
	"master_smith": "",
	"seasoned": "",
	"siege_lord": "",
	"slayer": "",
	"legend": "",
}
