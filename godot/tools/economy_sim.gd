extends SceneTree
# The economy, played out (0.31.108, Kevin: "check economy balance for entire game"). Two steps:
#   MODE=samples SEEDS=11,22,33 OUT=/tmp/samples.json godot --headless --path godot -s res://tools/economy_sim.gd
#       full 16v16 bot matches; every unit's end-of-match numbers (kills, rescues, gate damage, gathered, fed, repaired,
#       healed, best burst, won / draw, match length) -> OUT. A bot stands in for a player of average skill.
#   MODE=season SAMPLES=/tmp/samples.json DAYS=84 OUT=/tmp/season.json godot --headless --path godot -s res://tools/economy_sim.gd
#       personas (matches a day, sessions, win rate) play DAYS days from a fresh profile with the REAL Profile / Economy
#       code: each match is a random sample (a win or a loss at the persona's rate), then the challenges, quests and pass
#       tiers are claimed and the chests opened and started the way a player would (shortest while playing, longest
#       before leaving). Income is booked by source per 28-day season; with PREMIUM=1 the premium pass is bought at
#       every season start (its 950 gems booked as spending, not taken from income) and repeats from the pass counted.
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Eco = preload("res://scripts/meta/economy.gd")

const PERSONAS := {
	# sessions: [minute of the UTC day, matches]; days: which days of the week are played (0 = the first day)
	"light":   {"sessions": [[20 * 60, 2]], "days": [0, 1, 2, 4, 5], "win": 0.5},
	"casual":  {"sessions": [[12 * 60, 1], [20 * 60, 2]], "days": [0, 1, 2, 3, 4, 5, 6], "win": 0.5},
	"regular": {"sessions": [[8 * 60, 1], [13 * 60, 2], [21 * 60, 2]], "days": [0, 1, 2, 3, 4, 5, 6], "win": 0.5},
	"grinder": {"sessions": [[9 * 60, 4], [14 * 60, 4], [20 * 60, 4]], "days": [0, 1, 2, 3, 4, 5, 6], "win": 0.5},
}
const ROTATION := ["knight", "barbarian", "rogue", "mage"]      # the class played, by day

var rng := RandomNumberGenerator.new()
var wins: Array = []
var losses: Array = []
var book := {}          # season -> source -> {gold, gems, embers, items}
var counts := {}        # season -> {chests_opened: {kind: n}, chests_full: {kind: n}, matches, ...}

func _init() -> void:
	var mode := OS.get_environment("MODE")
	if mode == "samples":
		_samples()
	elif mode == "season":
		_season()
	else:
		print("MODE=samples | season")
	quit()

# ---------------- step 1: what a match gives ----------------
func _samples() -> void:
	var seeds := (OS.get_environment("SEEDS") if OS.has_environment("SEEDS") else "11,22,33").split(",")
	var out := []
	for sd in seeds:
		var s = Sim.new()
		s.setup(16, int(sd))
		var multi := {}
		while not s.ended:
			s.step()
			for e in s.drain_events():
				if str(e.get("k", "")) == "multikill":
					multi[str(e.id)] = maxi(int(multi.get(str(e.id), 0)), int(e.n))
		for u in s.units:
			out.append({"won": s.winner == int(u.team), "draw": s.winner < 0, "kills": int(u.kills), "rescues": int(u.rescues),
				"gate_dmg": float(u.gate_dmg), "gathered": int(u.gathered), "fed": int(u.fed), "repaired": float(u.repaired),
				"healed": float(u.get("healed", 0.0)), "best_multi": int(multi.get(str(u.id), 0)), "cls": str(u.cls), "time": s.time})
		print("seed %s: %.0f s, score %s, winner %d" % [sd, s.time, str(s.score), s.winner])
	var f := FileAccess.open(OS.get_environment("OUT"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("SAMPLES %d" % out.size())

# ---------------- step 2: a season (or three) ----------------
func _season() -> void:
	var all: Array = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("SAMPLES")))
	for s in all:
		(wins if bool(s.won) else losses).append(s)
	var days := int(OS.get_environment("DAYS")) if OS.has_environment("DAYS") else 84
	var premium := OS.get_environment("PREMIUM") == "1"
	var result := {}
	for name in PERSONAS:
		rng.seed = hash(name)
		book = {}
		counts = {}
		var p = Profile.new("user://econ-sim-%s-%d.json" % [name, int(premium)], "user://econ-sim-none.json")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p.path))
		p.now_override = Eco.SEASON_EPOCH
		p.load_or_create()
		p.d.name = "sim-" + name
		var per: Dictionary = PERSONAS[name]
		var owned_at_start := {}
		var tier_at := {}
		var level_at := {}
		var full_at := {}         # the day of the season the pass was finished
		for day in days:
			var t0 := Eco.SEASON_EPOCH + day * 86400
			var season := 1 + day / Eco.SEASON_DAYS
			if day % Eco.SEASON_DAYS == 0:
				p.now_override = t0
				p.refresh()
				owned_at_start[season] = (p.d.owned as Array).duplicate()
				if premium:
					p.d.gems = int(p.d.gems) + Eco.PREMIUM_COST          # (bought with gems booked as spending)
					p.buy_premium()
					_add(season, "premium_bought", 0, 0, 0)
			if not (per.days as Array).has(day % 7):
				continue
			var cls: String = ROTATION[day % ROTATION.size()]
			for sess in per.sessions:
				_session(p, season, t0 + int(sess[0]) * 60, int(sess[1]), float(per.win), cls)
			tier_at[season] = p.pass_tier()
			level_at[season] = int(p.d.level)
			if p.pass_tier() >= Eco.PASS_TIERS and not full_at.has(season):
				full_at[season] = day % Eco.SEASON_DAYS + 1
		# what the premium track handed over that the player already had at the season's start
		var repeats := {}
		for season in owned_at_start:
			var items: Array = Eco.pass_items(int(season))
			var rep := {"free": [], "prem": []}
			for k in items.size():
				var tier: int = Eco.FREE_ITEM_TIERS[k] if k < Eco.PASS_FREE_ITEMS else Eco.PREMIUM_ITEM_TIERS[k - Eco.PASS_FREE_ITEMS]
				var it: Dictionary = Eco.CATALOG[items[k]]
				if str(it.kind) == "title" or tier > int(tier_at.get(season, 0)):
					continue
				if (owned_at_start[season] as Array).has(items[k]):
					(rep.free if k < Eco.PASS_FREE_ITEMS else rep.prem).append("%s (%s, tier %d)" % [it.name, it.rarity, tier])
			repeats[season] = rep
		result[name] = {"book": book, "counts": counts, "tier": tier_at, "full_on_day": full_at, "level": level_at, "repeats": repeats,
			"end": {"gold": int(p.d.gold), "gems": int(p.d.gems), "embers": int(p.d.embers), "owned": (p.d.owned as Array).size()}}
		print("%s done: level %d, tier %s, gold %d, gems %d, embers %d" % [name, int(p.d.level), str(tier_at), int(p.d.gold), int(p.d.gems), int(p.d.embers)])
	var f := FileAccess.open(OS.get_environment("OUT"), FileAccess.WRITE)
	f.store_string(JSON.stringify(result, " "))
	f.close()
	print("SEASON_DONE")

func _session(p, season: int, t: int, n: int, win: float, cls: String) -> void:
	p.now_override = t
	_chests(p, season, false)
	for i in n:
		var won := rng.randf() < win
		var pool: Array = wins if won else losses
		var s: Dictionary = pool[rng.randi() % pool.size()]
		t += int(s.time) + 120                                   # the match and the menus around it
		p.now_override = t
		var q := {cls: {"t": 600.0, "kills": s.kills, "rescues": s.rescues, "gates": int(float(s.gate_dmg) / 100.0),
			"gathered": s.gathered, "fed": s.fed, "healed": int(s.healed), "repaired": int(s.repaired), "lifts": 0, "best_multi": s.best_multi}}
		var me := {"kills": s.kills, "rescues": s.rescues, "gate_dmg": s.gate_dmg, "gathered": s.gathered, "fed": s.fed, "lifts": 0,
			"best_multi": s.best_multi, "cls": cls, "cls_main": cls, "repaired": s.repaired, "healed": s.healed,
			"kills_cls": {cls: s.kills}, "q": q}
		var snap := _snap(p)
		var out: Dictionary = p.apply_match(me, won, bool(s.draw) and not won, false)
		_book(p, season, "matches", snap)
		_count(season, "matches", 1)
		for c in out.get("chests", []):
			_count(season, ("full_" if bool(c.full) else "got_") + str(c.kind), 1)
		for span in ["daily", "weekly"]:
			var list: Array = p.d.challenges[span]
			for k in list.size():
				snap = _snap(p)
				var r: Dictionary = p.claim_challenge(span, k)
				if bool(r.ok):
					for c in r.get("chests", []):
						_count(season, ("full_" if bool(c.full) else "got_") + str(c.kind), 1)
				_book(p, season, "challenges_" + span, snap)
		for qc in Eco.QUESTS:
			while p.quest_ready(qc):
				snap = _snap(p)
				var r: Dictionary = p.claim_quest(qc)
				for c in r.get("chests", []):
					_count(season, ("full_" if bool(c.full) else "got_") + str(c.kind), 1)
				_book(p, season, "quests", snap)
		snap = _snap(p)
		p.claim_all()
		_book(p, season, "pass", snap)
		_chests(p, season, false)
	_chests(p, season, true)

func _chests(p, season: int, leaving: bool) -> void:
	var i := 0
	while i < p.chests().size():
		var c: Dictionary = p.chests()[i]
		if p.chest_ready(c):
			var snap := _snap(p)
			var r: Dictionary = p.open_chest(i)
			_book(p, season, "chest_" + str(c.kind), snap)
			_count(season, "opened_" + str(c.kind), 1)
			if str(r.get("item", "")) != "":
				_count(season, "item_" + str(Eco.CATALOG[r.item].rarity), 1)
			if int(r.get("dupe_embers", 0)) > 0:
				_count(season, "dupe", 1)
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
	return {"gold": int(p.d.gold), "gems": int(p.d.gems), "embers": int(p.d.embers), "items": (p.d.owned as Array).size()}

func _book(p, season: int, src: String, snap: Dictionary) -> void:
	var now := _snap(p)
	_add(season, src, now.gold - snap.gold, now.gems - snap.gems, now.embers - snap.embers, now.items - snap.items)

func _add(season: int, src: String, gold: int, gems: int, embers: int, items := 0) -> void:
	var key := str(season)
	if not book.has(key):
		book[key] = {}
	if not book[key].has(src):
		book[key][src] = {"gold": 0, "gems": 0, "embers": 0, "items": 0}
	var b: Dictionary = book[key][src]
	b.gold += gold
	b.gems += gems
	b.embers += embers
	b.items += items

func _count(season: int, what: String, n: int) -> void:
	var key := str(season)
	if not counts.has(key):
		counts[key] = {}
	counts[key][what] = int(counts[key].get(what, 0)) + n
