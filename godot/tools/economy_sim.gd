extends SceneTree
# The economy, played out (0.31.189, Kevin: "Now check the gold and gem economy and make sure it's balanced"; the 5v5's
# heir of 0.31.108's model, which played Siege). Two steps:
#   MODE=samples SEEDS=2001,2002 OUT=/tmp/samples.json godot --headless --path godot -s res://tools/economy_sim.gd
#       whole 5v5 bot matches; every hero's end-of-match numbers (knockouts, towers, camps, last hits, epic monsters,
#       tower / gate damage, best burst, won / draw, match length) -> OUT. A bot stands in for a player of average skill.
#   MODE=season SAMPLES=/tmp/samples.json DAYS=112 OUT=/tmp/season.json godot --headless --path godot -s res://tools/economy_sim.gd
#       personas (matches a day, sessions, win rate) play DAYS days from a new account with the REAL Profile / Economy
#       code: each match a random sample (a win or a loss at the persona's rate); the login reward, challenges, quests and
#       pass tiers claimed and the chests opened and started the way a player would (shortest while playing, longest
#       before leaving). The free player spends the way the game invites him to: gold on the heroes he lacks (a shard of
#       one first, at its discount; a Hero Token on the dearest), shards of heroes he owns melted, then the Frostbound
#       outfits for gold (0.31.189) once the heroes are his; gems kept (booked, not
#       spent -- what they could buy is worked out from the totals). Income is booked by source per 28 days, and the day
#       each hero was unlocked, so the gold left with nothing to buy shows. START (unix) sets the first day (default
#       2026-11-02, after the six's launch price). ONLINE=1: the matches are online (+20 %).
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Eco = preload("res://scripts/meta/economy.gd")

const PERSONAS := {
	# sessions: [minute of the UTC day, matches]; days: which days of the week are played (0 = the first day)
	"light":   {"sessions": [[20 * 60, 2]], "days": [0, 1, 2, 4, 5], "win": 0.5},
	"casual":  {"sessions": [[12 * 60, 1], [20 * 60, 2]], "days": [0, 1, 2, 3, 4, 5, 6], "win": 0.5},
	"regular": {"sessions": [[8 * 60, 1], [13 * 60, 2], [21 * 60, 2]], "days": [0, 1, 2, 3, 4, 5, 6], "win": 0.5},
	"grinder": {"sessions": [[9 * 60, 3], [14 * 60, 3], [20 * 60, 4]], "days": [0, 1, 2, 3, 4, 5, 6], "win": 0.5},
}
# the heroes played, by day (everyone's twelve; a sold one once it's his)
const ROTATION := ["knight", "mage", "ranger", "barbarian", "priest", "rogue", "crusader", "archmage", "sniper",
	"berserker", "assassin", "necromancer"]

var rng := RandomNumberGenerator.new()
var wins: Array = []
var losses: Array = []
var book := {}          # period -> source -> {gold, gems}
var counts := {}        # period -> what -> n
var spent := {}         # period -> {gold, gems}

func _init() -> void:
	var mode := OS.get_environment("MODE")
	if mode == "samples":
		_samples()
	elif mode == "season":
		_season()
	else:
		print("MODE=samples | season")
	quit()

# ---------------- step 1: what a 5v5 match gives ----------------
func _samples() -> void:
	var seeds := (OS.get_environment("SEEDS") if OS.has_environment("SEEDS") else "2001,2002").split(",")
	var heroes := ["knight", "mage", "ranger", "golem", "rogue", "priest", "musketeer", "druid"]
	var out := []
	for i in seeds.size():
		var sd := int(seeds[i])
		var s = Sim.new()
		s.setup(5, sd)
		s.setup_moba(str(heroes[i % heroes.size()]), sd)
		s.by_id["you"].bot = true
		var multi := {}
		while not s.ended:
			s.step()
			for e in s.drain_events():
				if str(e.get("k", "")) == "multikill":
					multi[str(e.get("id", ""))] = maxi(int(multi.get(str(e.get("id", "")), 0)), int(e.get("n", 0)))
		for u in s.units:
			if not bool(u.get("hero", false)):
				continue
			out.append({"won": s.winner == int(u.team), "draw": s.winner < 0, "kills": int(u.kills), "gate_dmg": float(u.get("gate_dmg", 0.0)),
				"towers": int(u.get("towers", 0)), "camps": int(u.get("camps", 0)), "lh": int(u.get("lh", 0)), "epics": int(u.get("epics", 0)),
				"healed": float(u.get("healed", 0.0)), "best_multi": int(multi.get(str(u.id), 0)), "cls": str(u.cls), "time": s.time})
		print("seed %d: %.0f s, winner %d" % [sd, s.time, s.winner])
	var f := FileAccess.open(OS.get_environment("OUT"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("SAMPLES %d" % out.size())

# ---------------- step 2: months of play ----------------
func _season() -> void:
	var all: Array = []
	for path in OS.get_environment("SAMPLES").split(","):
		all.append_array(JSON.parse_string(FileAccess.get_file_as_string(path)))
	for s in all:
		(wins if bool(s.won) else losses).append(s)
	var days := int(OS.get_environment("DAYS")) if OS.has_environment("DAYS") else 112
	var start := int(OS.get_environment("START")) if OS.has_environment("START") else 1793577600     # 2026-11-02 00:00 UTC
	var online := OS.get_environment("ONLINE") == "1"
	var only := OS.get_environment("PERSONAS").split(",") if OS.has_environment("PERSONAS") else PackedStringArray()
	var result := {"samples": {"wins": wins.size(), "losses": losses.size()}}
	for name in PERSONAS:
		if not only.is_empty() and not only.has(name):
			continue
		rng.seed = hash(name)
		book = {}
		counts = {}
		spent = {}
		var p = Profile.new("user://econ-sim-%s.json" % name, "user://econ-sim-none.json")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p.path))
		p.now_override = start
		p.load_or_create()
		p.d.name = "sim-" + name
		p.d.tutorial_done = false
		var snap := _snap(p)
		p.finish_tutorial()
		_book(p, 1, "tutorial", snap)
		var per: Dictionary = PERSONAS[name]
		var unlocked := {}        # hero -> day
		var gold_at := {}         # period -> gold held at its end
		var gems_at := {}
		var level_at := {}
		var tier_at := {}
		for day in days:
			var t0 := start + day * 86400
			var period := 1 + day / 28
			if not (per.days as Array).has(day % 7):
				continue
			p.now_override = t0 + int(per.sessions[0][0]) * 60 - 60
			p.refresh()
			if p.login_ready():
				snap = _snap(p)
				p.claim_login()
				_book(p, period, "login", snap)
			var played: Array = ROTATION.duplicate()
			for h in Eco.HERO_PRICES:
				if p.owns_hero(str(h)):
					played.append(str(h))
			var hero: String = played[day % played.size()]
			for sess in per.sessions:
				_session(p, period, t0 + int(sess[0]) * 60, int(sess[1]), float(per.win), hero, online)
				_spend(p, period, day, unlocked)
			gold_at[period] = int(p.d.gold)
			gems_at[period] = int(p.d.gems)
			level_at[period] = int(p.d.level)
			tier_at[period] = p.pass_tier()
		result[name] = {"book": book, "counts": counts, "spent": spent, "unlocked": unlocked, "gold_at": gold_at,
			"gems_at": gems_at, "level": level_at, "tier": tier_at,
			"end": {"gold": int(p.d.gold), "gems": int(p.d.gems), "level": int(p.d.level), "shards": (p.d.shards as Array).size(),
				"tokens": int(p.d.get("tokens", 0)), "heroes": (p.d.heroes as Array).size()}}
		print("%s: level %d, gold %d, gems %d, heroes %s" % [name, int(p.d.level), int(p.d.gold), int(p.d.gems), str(unlocked)])
	var f := FileAccess.open(OS.get_environment("OUT"), FileAccess.WRITE)
	f.store_string(JSON.stringify(result, " "))
	f.close()
	print("SEASON_DONE")

func _spend(p, period: int, day: int, unlocked: Dictionary) -> void:
	# the free player: a Hero Token on the dearest hero he lacks; a shard of one he lacks at its discount; shards of
	# heroes he has melted; then gold on the cheapest hero he lacks
	var want: Array = Eco.HERO_PRICES.keys().filter(func(h): return not p.owns_hero(str(h)))
	want.sort_custom(func(a, b): return int(p.hero_price(a).get("gold", 0)) > int(p.hero_price(b).get("gold", 0)))
	if int(p.d.get("tokens", 0)) > 0 and not want.is_empty():
		if bool(p.use_token(str(want[0])).ok):
			unlocked[str(want[0])] = "day %d (token)" % day
			_count(period, "token_used", 1)
	for h in Eco.HERO_PRICES:
		while p.shards_of(str(h)) > 0:
			var snap := _snap(p)
			if not p.owns_hero(str(h)):
				if not bool(p.use_shard(str(h)).ok):
					break
				unlocked[str(h)] = "day %d (shard)" % day
				_spent(period, snap, p)
				_count(period, "shard_used", 1)
			else:
				p.melt_shard(str(h))
				_book(p, period, "shards_melted", snap)
				_count(period, "shard_melted", 1)
	want = Eco.HERO_PRICES.keys().filter(func(h): return not p.owns_hero(str(h)))
	want.sort_custom(func(a, b): return int(p.hero_price(a).get("gold", 0)) < int(p.hero_price(b).get("gold", 0)))
	for h in want:
		var snap := _snap(p)
		if bool(p.buy_hero(str(h)).ok):
			unlocked[str(h)] = "day %d (gold)" % day
			_spent(period, snap, p)
	# 0.31.189: the heroes all his -- gold on the Frostbound outfits (Eco.SKINS "gold")
	if Eco.HERO_PRICES.keys().all(func(h): return p.owns_hero(str(h))):
		for id in Eco.SKINS:
			if int(Eco.SKINS[id].get("gold", 0)) > 0 and not p.owns_skin(str(id)) and int(p.d.gold) >= int(Eco.SKINS[id].gold):
				var snap := _snap(p)
				if bool(p.buy_skin_gold(str(id)).ok):
					_spent(period, snap, p)
					_count(period, "outfit_for_gold", 1)
					unlocked["outfits"] = int(unlocked.get("outfits", 0)) + 1

func _session(p, period: int, t: int, n: int, win: float, hero: String, online: bool) -> void:
	p.now_override = t
	_chests(p, period, false)
	for i in n:
		var won := rng.randf() < win
		var pool: Array = wins if won else losses
		var s: Dictionary = pool[rng.randi() % pool.size()]
		t += int(s.time) + 120                                   # the match and the menus around it
		p.now_override = t
		var q := {hero: {"t": float(s.time), "kills": s.kills, "gates": int(float(s.gate_dmg) / 100.0), "healed": int(s.healed),
			"best_multi": s.best_multi, "towers": s.towers, "camps": s.camps, "lh": s.lh, "epics": s.epics}}
		var me := {"kills": s.kills, "rescues": 0, "gate_dmg": s.gate_dmg, "gathered": 0, "fed": 0, "lifts": 0,
			"best_multi": s.best_multi, "cls": hero, "cls_main": hero, "healed": s.healed, "towers": s.towers, "camps": s.camps,
			"lh": s.lh, "epics": s.epics, "kills_cls": {hero: s.kills}, "q": q}
		var snap := _snap(p)
		var out: Dictionary = p.apply_match(me, won, bool(s.draw) and not won, online)
		_book(p, period, "matches", snap)
		_count(period, "matches", 1)
		for c in out.get("chests", []):
			_count(period, ("full_" if bool(c.full) else "got_") + str(c.kind), 1)
		for span in ["daily", "weekly"]:
			var list: Array = p.d.challenges[span]
			for k in list.size():
				snap = _snap(p)
				var r: Dictionary = p.claim_challenge(span, k)
				if bool(r.ok):
					for c in r.get("chests", []):
						_count(period, ("full_" if bool(c.full) else "got_") + str(c.kind), 1)
				_book(p, period, "challenges_" + span, snap)
		for qc in Eco.QUESTS:
			while p.quest_ready(qc):
				snap = _snap(p)
				var r: Dictionary = p.claim_quest(qc)
				for c in r.get("chests", []):
					_count(period, ("full_" if bool(c.full) else "got_") + str(c.kind), 1)
				_book(p, period, "quests", snap)
		snap = _snap(p)
		p.claim_all()
		_book(p, period, "pass", snap)
		_chests(p, period, false)
	_chests(p, period, true)

func _chests(p, period: int, leaving: bool) -> void:
	var i := 0
	while i < p.chests().size():
		var c: Dictionary = p.chests()[i]
		if p.chest_ready(c):
			var snap := _snap(p)
			var r: Dictionary = p.open_chest(i)
			_book(p, period, "chest_" + str(c.kind), snap)
			_count(period, "opened_" + str(c.kind), 1)
			if str(r.get("shard", "")) != "":
				_count(period, "shard_from_chest", 1)
		else:
			i += 1
	if p.unlocking().is_empty() and not p.chests().is_empty():
		var best := 0
		for k in p.chests().size():
			var a: int = int(Eco.CHESTS[p.chests()[k].kind].unlock)
			var b: int = int(Eco.CHESTS[p.chests()[best].kind].unlock)
			if (a > b) if leaving else (a < b):
				best = k
		p.start_unlock(best)

func _snap(p) -> Dictionary:
	return {"gold": int(p.d.gold), "gems": int(p.d.gems)}

func _book(p, period: int, src: String, snap: Dictionary) -> void:
	var now := _snap(p)
	var key := str(period)
	if not book.has(key):
		book[key] = {}
	if not book[key].has(src):
		book[key][src] = {"gold": 0, "gems": 0}
	book[key][src].gold += now.gold - snap.gold
	book[key][src].gems += now.gems - snap.gems

func _spent(period: int, snap: Dictionary, p) -> void:
	var key := str(period)
	if not spent.has(key):
		spent[key] = {"gold": 0, "gems": 0}
	spent[key].gold += snap.gold - int(p.d.gold)
	spent[key].gems += snap.gems - int(p.d.gems)

func _count(period: int, what: String, n: int) -> void:
	var key := str(period)
	if not counts.has(key):
		counts[key] = {}
	counts[key][what] = int(counts[key].get(what, 0)) + n
