extends RefCounted
# 0.31.118 (Kevin's spec, ANALYTICS_SPEC_FOR_CLAUDE.md: "self-hosted analytics on the Siege server ... no SDK and no third
# party"): the events and, for each, the only props it may carry. Shared by the phone (scripts/meta/analytics.gd: what
# it logs) and the server (server/analytics.gd: what it keeps -- anything else is dropped). Props are numbers, true/false
# or short words made by the game's own code: never a name, a chat line, a token or an order id.

const MAX_PROPS := 32                # (0.31.212: 12 -> 32 for the server's match_quit -- still only the listed keys)
const MAX_STR := 40

# sent by the phone ({"t":"an"} batches)
const CLIENT := {
	"session_start": ["cold", "safe_boot", "net", "plat"],     # 0.31.132: plat "android" | "ios" (| "desktop")
	"session_end": ["dur_s", "lost"],              # lost: the session never said it ended (sent at the next start)
	"clean_session": ["prev_sid"],                  # the last session ended without a crash or a stuck start
	"tutorial_start": [],
	"tutorial_step": ["step", "id"],
	"tutorial_complete": ["dur_s"],
	"tutorial_skip": ["dur_s", "step", "id"],
	"match_join": ["mode", "party_n"],
	"match_start": ["match", "mode", "class"],      # (the phone's only for "bots": online matches are the server's)
	"match_finish": ["match", "mode", "dur_s", "result", "team_n", "class", "class0"],
	"match_quit": ["match", "mode", "quit_at_s", "class", "class0"],
	"level_up": ["lvl"],
	"forge": ["item", "stars"],
	"chest_open": ["rarity", "src"],
	"shop_view": ["tab"],
	"daily_reward": ["day"],                         # 0.31.119: the daily login reward claimed (day 1-7)
	"update_screen": ["from_build", "need"],
	"error": ["kind", "n"],
	"opt_out": [],
	"q_dropped": ["n"],
}

# written by the server itself (it knows these first-hand; the phone never sends them)
const SERVER := {
	"session_online": [],
	"match_start": ["match", "mode", "class"],
	# 0.31.212 (NEW_PLAYER_RETENTION_HANDOFF.md): the player's upgrades from the match's shop -- items bought, the gold
	# they cost, the gold left unspent
	"match_finish": ["match", "mode", "dur_s", "result", "team_n", "class", "class0", "items", "gold_spent", "gold_left"],
	# 0.31.212 (the same): the match as the player left it. why: the drop's reason ("left" = quit on purpose, "closed" /
	# "silent" = the connection went, "idle", ...); held: their seat waited for them and they never came back (let go
	# when the wait ran out or the match ended); rejoins: times they came back to this seat; match_s: the match's clock
	# at the leave; team 0 blue / 1 red, the rest from their side: score (Kings toppled), kills (the team's), k/d/a
	# (theirs), each King's HP in percent, and their shop totals
	"match_quit": ["match", "mode", "quit_at_s", "class", "class0", "why", "held", "rejoins", "match_s", "hero", "team", "lvl",
		"score_us", "score_them", "kills_us", "kills_them", "k", "d", "a", "king_us_pct", "king_them_pct",
		"items", "gold_spent", "gold_left"],
	# 0.31.212 (the same): an upgrade a player bought with the match's gold (a bot's buys are not counted)
	"match_shop_buy": ["match", "mode", "item", "cost", "match_s", "hero", "gold_left"],
	"purchase_verified": ["product", "test", "store"],     # 0.31.131: store "google" | "apple"
	"chat_send": ["kind"],
	"friend_add": [],
	"friend_accept": [],
	"party_create": [],
	"party_join": ["n"],
	"party_invite": [],
	"quick_chat": ["i"],
	"update_screen": ["from_build", "need"],
	"clan_create": ["house", "join"],               # 0.31.134: clans (server/clans.gd)
	"clan_join": ["n"],
	"clan_request": [],
	"clan_invite": [],
	"clan_leave": [],
	# 0.31.208, server (Kevin: "Gold and gem spending ... tracking system for server"): gold or gems an account spent, as the
	# server replayed it (server/eco_accounts.gd spend_props): what on, what it cost, what was left
	"spend": ["cat", "item", "op", "gold", "gems", "gold_left", "gems_left", "lvl", "hero", "off", "n", "season"],
}

static func clean_props(allowed: Array, p: Variant) -> Dictionary:
	# only the allowed keys; numbers and true/false as they are, anything else as a short string
	var out := {}
	if not (p is Dictionary):
		return out
	for k in allowed:
		if out.size() >= MAX_PROPS:
			break
		if not (p as Dictionary).has(k):
			continue
		var v: Variant = p[k]
		match typeof(v):
			TYPE_BOOL, TYPE_INT:
				out[k] = v
			TYPE_FLOAT:
				out[k] = int(v) if is_finite(v) and float(int(v)) == v else (snappedf(v, 0.01) if is_finite(v) else 0)
			_:
				out[k] = str(v).left(MAX_STR)
	return out
