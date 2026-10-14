extends RefCounted
# 0.31.130 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §4): the Game Center achievement ids, App Store Connect >
# Fatebound > Game Center > Achievements ("Achievement ID"). Apple's ids are our own strings, so they are simply
# "fatebound.<key>" for the 18 of scripts/meta/achievements.gd (the twin of play_achievement_ids.gd). Each must be made
# in App Store Connect with exactly this id (an id can never be reused or deleted once live -- Kevin approves first);
# one that isn't there yet is reported and Apple answers with an error, which only means nothing shows for it.
const PREFIX := "fatebound."
const IDS := {
	"welcome": "fatebound.welcome",
	"first_blood": "fatebound.first_blood",
	"first_victory": "fatebound.first_victory",
	"kings_rescue": "fatebound.kings_rescue",
	"many_hats": "fatebound.many_hats",
	"fattening": "fatebound.fattening",
	"lumberjack": "fatebound.lumberjack",
	"gatecrasher": "fatebound.gatecrasher",
	"heavy_lifting": "fatebound.heavy_lifting",
	"centurion": "fatebound.centurion",
	"relentless": "fatebound.relentless",
	"unstoppable": "fatebound.unstoppable",
	"bodyguard": "fatebound.bodyguard",
	"master_smith": "fatebound.master_smith",
	"seasoned": "fatebound.seasoned",
	"siege_lord": "fatebound.siege_lord",
	"slayer": "fatebound.slayer",
	"legend": "fatebound.legend",
}
