extends RefCounted
# 0.31.119: the Google Play Games achievement ids, from Play Console > Play Games Services > Achievements (each one's
# "ID", like "CgkI...EAIQAQ"), for the achievements listed in godot/PLAY_ACHIEVEMENTS_HANDOFF.md; an empty id is skipped
# (nothing is sent for it). A script, not a JSON file, so every export carries it.
# 0.31.121: all 18 filled in (Kevin, 2026-10-13; Play Games Game ID 1022979193240).
const IDS := {
	"welcome": "CgkImPO-8uIdEAIQAg",
	"first_blood": "CgkImPO-8uIdEAIQAw",
	"first_victory": "CgkImPO-8uIdEAIQBA",
	"kings_rescue": "CgkImPO-8uIdEAIQBQ",
	"many_hats": "CgkImPO-8uIdEAIQBg",
	"fattening": "CgkImPO-8uIdEAIQBw",
	"lumberjack": "CgkImPO-8uIdEAIQCA",
	"gatecrasher": "CgkImPO-8uIdEAIQCQ",
	"heavy_lifting": "CgkImPO-8uIdEAIQCg",
	"centurion": "CgkImPO-8uIdEAIQCw",
	"relentless": "CgkImPO-8uIdEAIQDA",
	"unstoppable": "CgkImPO-8uIdEAIQDQ",
	"bodyguard": "CgkImPO-8uIdEAIQDg",
	"master_smith": "CgkImPO-8uIdEAIQDw",
	"seasoned": "CgkImPO-8uIdEAIQEA",
	"siege_lord": "CgkImPO-8uIdEAIQEQ",
	"slayer": "CgkImPO-8uIdEAIQEg",
	"legend": "CgkImPO-8uIdEAIQEw",
}
