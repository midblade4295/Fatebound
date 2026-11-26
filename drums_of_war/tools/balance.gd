extends SceneTree
## Plays many computer-versus-computer matches and writes one line of JSON per match, for
## tools/balance_report.py to add up: how each match ended, how long it took, what fell, and
## which cards each side held and played.
##
##   godot --headless --path drums_of_war -s tools/balance.gd
## Environment: MATCHES (default 100), SEED0 (first seed, default 1), DECKS ("random" for a
## fresh random deck per side per match, or "starter" for the first eight cards on both sides),
## LEVELS (the two sides' bot levels, default "1,1"), OUT (file to append to; default prints).

const Sim = preload("res://scripts/sim/battle_sim.gd")
const Bot = preload("res://scripts/sim/bot.gd")

const STARTER := ["line_infantry", "skirmishers", "militia", "scouts", "heavy_cavalry", "field_gun", "fire", "rally"]


func _env(name: String, fallback: String) -> String:
	return OS.get_environment(name) if OS.has_environment(name) else fallback


func _init() -> void:
	var cards := Sim.load_cards()
	var matches := int(_env("MATCHES", "100"))
	var seed0 := int(_env("SEED0", "1"))
	var random_decks := _env("DECKS", "random") == "random"
	var levels := _env("LEVELS", "1,1").split(",")
	var out: FileAccess = null
	if OS.has_environment("OUT"):
		var path := OS.get_environment("OUT")
		out = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
		out.seek_end()
	for s in range(seed0, seed0 + matches):
		var deck0: Array = Bot.pick_deck(cards, s * 2) if random_decks else STARTER
		var deck1: Array = Bot.pick_deck(cards, s * 2 + 1) if random_decks else STARTER
		var sim := Sim.new(s, cards, deck0, deck1)
		var b0 := Bot.new(0, s, int(levels[0]))
		var b1 := Bot.new(1, s, int(levels[1]))
		sim.powder_rate = [float(b0.cfg["powder"]), float(b1.cfg["powder"])]
		var first_fall := -1.0
		var routs := 0
		var guard := 0
		while sim.phase != Sim.PHASE_OVER and guard < 6000:
			b0.tick(sim)
			b1.tick(sim)
			sim.tick()
			for e: Dictionary in sim.events:
				if e["type"] == "destroyed" and first_fall < 0.0:
					first_fall = sim.time
				elif e["type"] == "rout":
					routs += 1
			sim.events.clear()
			guard += 1
		var how := "unfinished"
		if sim.phase == Sim.PHASE_OVER:
			if sim.hq(0).dead or sim.hq(1).dead:
				how = "colours"
			elif sim.time < Sim.MATCH_TIME + 0.2:
				how = "regular"            # on batteries taken, when the clock ran out
			elif sim.time < Sim.MATCH_TIME + Sim.OVERTIME - 0.2:
				how = "sudden"             # a structure fell in overtime
			else:
				how = "points" if sim.winner != Sim.DRAW else "draw"
		var plays := [{}, {}]
		for c: Dictionary in sim.command_log:
			var side := int(c["side"])
			plays[side][c["card"]] = int(plays[side].get(c["card"], 0)) + 1
		var damage := [0.0, 0.0]       # damage taken by each side's structures
		for st: Sim.Structure in sim.structures:
			damage[st.side] += st.max_hp - st.hp
		var line := JSON.stringify({"seed": s, "winner": sim.winner, "how": how, "time": snappedf(sim.time, 0.1),
				"lost": [sim.redoubts_lost(0), sim.redoubts_lost(1)], "first_fall": snappedf(first_fall, 0.1), "routs": routs,
				"damage": [snappedf(damage[0], 1.0), snappedf(damage[1], 1.0)], "decks": [deck0, deck1], "plays": plays})
		if out != null:
			out.store_line(line)
		else:
			print(line)
	if out != null:
		out.close()
	quit()
