extends SceneTree
## Plays full bot-versus-bot matches across many seeds. The two sides use identical decks and
## rules, so over enough seeds neither should win every time. Prints DRUMS_BOTS_PASS.

const Sim = preload("res://scripts/sim/battle_sim.gd")
const Bot = preload("res://scripts/sim/bot.gd")

const DECK := ["line_infantry", "skirmishers", "militia", "scouts", "heavy_cavalry", "field_gun", "fire", "rally"]


func _init() -> void:
	var cards := Sim.load_cards()
	var seeds := 24
	if OS.has_environment("SEEDS"):
		seeds = int(OS.get_environment("SEEDS"))
	var wins := [0, 0, 0]
	var by_colours := 0
	var total_time := 0.0
	var total_deploys := 0
	var events := {}
	var ok := true
	var redoubt_dmg := 0.0
	var hq_dmg := 0.0
	var redoubts_fallen := 0
	var regular_time_wins := 0
	for s in range(1, seeds + 1):
		var sim := Sim.new(s, cards, DECK, DECK)
		var b0 := Bot.new(0, s)
		var b1 := Bot.new(1, s)
		var guard := 0
		while sim.phase != Sim.PHASE_OVER and guard < 6000:
			b0.tick(sim)
			b1.tick(sim)
			sim.tick()
			for e: Dictionary in sim.events:
				events[e["type"]] = int(events.get(e["type"], 0)) + 1
			sim.events.clear()
			guard += 1
		if sim.phase != Sim.PHASE_OVER:
			print("  seed %d never finished" % s)
			ok = false
			continue
		wins[sim.winner] += 1
		if sim.hq(0).dead or sim.hq(1).dead:
			by_colours += 1
		total_time += sim.time
		if sim.time < Sim.MATCH_TIME + 0.5:
			regular_time_wins += 1
		for st: Sim.Structure in sim.structures:
			if st.kind == "hq":
				hq_dmg += st.max_hp - st.hp
			else:
				redoubt_dmg += st.max_hp - st.hp
				if st.dead:
					redoubts_fallen += 1
		total_deploys += sim.command_log.size()
	print("matches: %d   side0 %d / side1 %d / draws %d   Colours captured in %d" % [seeds, wins[0], wins[1], wins[2], by_colours])
	print("average length %.0f s, average deploys per match %.1f" % [total_time / seeds, float(total_deploys) / seeds])
	print("per match: redoubts fallen %.2f, redoubt damage %.0f, HQ damage %.0f, decided in regular time %d of %d" % [
			float(redoubts_fallen) / seeds, redoubt_dmg / seeds, hq_dmg / seeds, regular_time_wins, seeds])
	var keys := events.keys()
	keys.sort()
	var line := ""
	for k: String in keys:
		line += "%s %.1f  " % [k, float(events[k]) / seeds]
	print("events per match: ", line)
	for needed: String in ["volley", "cannon", "rout", "square", "charge"]:
		if not events.has(needed):
			print("  no '%s' ever happened" % needed)
			ok = false
	if seeds >= 12 and (wins[0] == 0 or wins[1] == 0):
		print("  one side never won")
		ok = false
	if ok:
		print("DRUMS_BOTS_PASS")
	quit(0 if ok else 1)
