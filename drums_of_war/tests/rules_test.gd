extends SceneTree
## Headless checks of the battle rules. Prints DRUMS_RULES_PASS when every check holds.

const Sim = preload("res://scripts/sim/battle_sim.gd")
const Bot = preload("res://scripts/sim/bot.gd")

const DECK := ["line_infantry", "skirmishers", "militia", "scouts", "heavy_cavalry", "field_gun", "fire", "rally"]

var cards: Dictionary
var failures: int = 0
var checks: int = 0


func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("  FAIL: ", what)


func near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps


func new_sim(seed_value: int = 1) -> Sim:
	return Sim.new(seed_value, cards, DECK, DECK)


## Silences every structure's gun, for scenes that are about regiments only.
func quiet(sim: Sim) -> Sim:
	for s: Sim.Structure in sim.structures:
		s.reload = 99999.0
	return sim


func run(sim: Sim, seconds: float) -> void:
	for i in int(round(seconds * Sim.TICK_RATE)):
		sim.tick()


func has_event(sim: Sim, type: String) -> bool:
	for e: Dictionary in sim.events:
		if e["type"] == type:
			return true
	return false


func _init() -> void:
	cards = Sim.load_cards()
	check(cards.size() == 18, "eighteen cards load from data/cards.json")
	test_powder()
	test_deploy_and_hand()
	test_first_volley_and_reload()
	test_ford()
	test_square_repels_cavalry()
	test_cavalry_catches_reloading_line()
	test_militia_cannot_square()
	test_rout_and_rally()
	test_field_gun()
	test_redoubt_and_deploy_zone()
	test_orders()
	test_win_conditions()
	test_sharpshooters()
	test_zouaves()
	test_dragoons()
	test_horse_artillery()
	test_gatling()
	test_howitzer()
	test_grand_battery()
	test_earthworks()
	test_balloon()
	test_general()
	test_any_deck_plays()
	test_determinism()
	print("%d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("DRUMS_RULES_PASS")
	quit(0 if failures == 0 else 1)


func test_powder() -> void:
	var sim := new_sim()
	check(near(sim.powder[0], 5.0), "Powder starts at 5")
	run(sim, 2.8)
	check(near(sim.powder[0], 6.0), "one Powder every 2.8 s (got %.3f)" % sim.powder[0])
	run(sim, 60.0)
	check(near(sim.powder[0], 10.0), "Powder caps at 10")
	sim.powder[0] = 0.0
	run(sim, 120.0 - sim.time)
	sim.powder[0] = 0.0
	run(sim, 2.8)
	check(near(sim.powder[0], 2.0), "Powder doubles in the final minute (got %.3f)" % sim.powder[0])


func test_deploy_and_hand() -> void:
	var sim := new_sim(3)
	var hand: Array = sim.hand(0)
	var next: String = sim.next_card(0)
	check(hand.size() == 4 and next != "", "four cards in hand and one shown next")
	check(sim.deploy_error(0, 0, Vector2(9, 20)) != "" or cards[hand[0]]["type"] == "order", "cannot deploy troops past your own half")
	check(sim.deploy_error(1, 0, Vector2(9, 10)) != "" or cards[sim.hand(1)[0]]["type"] == "order", "the other side's half is mirrored")
	# Find a unit card in hand and play it.
	var idx := -1
	for i in 4:
		if cards[hand[i]]["type"] == "unit":
			idx = i
			break
	check(idx >= 0, "hand holds at least one unit card")
	var card_id: String = hand[idx]
	var cost := float(cards[card_id]["cost"])
	sim.powder[0] = cost - 0.5
	check(not sim.deploy(0, idx, Vector2(9, 10)), "cannot play a card you cannot afford")
	sim.powder[0] = 10.0
	check(sim.deploy_error(0, idx, Vector2(9, 18)) != "", "cannot deploy in the creek")
	check(sim.deploy(0, idx, Vector2(9, 10)), "a legal deploy is accepted")
	check(near(sim.powder[0], 10.0 - cost), "the card's cost is spent")
	check(sim.regiments.size() == 1 and sim.regiments[0].card_id == card_id, "the regiment is on the field")
	check(sim.hand(0)[idx] == next, "the next card takes the played slot")
	check(sim.decks[0][-1] == card_id, "the played card goes to the back of the deck")
	check(sim.command_log.size() == 1, "the deploy is logged")


func test_first_volley_and_reload() -> void:
	var sim := quiet(new_sim())
	var a := sim.spawn(0, "line_infantry", Vector2(9, 6))
	var b := sim.spawn(1, "line_infantry", Vector2(9, 11))
	sim.tick()
	# 6 men x 22 x 1.5 first-volley bonus = 198, and both fire in the same instant.
	check(near(b.hp, 360.0 - 198.0), "first volley does 198 (target has %.1f left)" % b.hp)
	check(near(a.hp, 360.0 - 198.0), "the return volley is simultaneous and equal (%.1f left)" % a.hp)
	check(near(a.reload, 3.2), "the shooter starts a 3.2 s reload")
	check(b.men == 3, "strength falls with losses (3 men left, got %d)" % b.men)
	run(sim, 3.25)
	# Second volley: 3 men x 22, no bonus = 66.
	check(near(b.hp, 162.0 - 66.0), "the second volley has no bonus and fewer muskets (%.1f left)" % b.hp)
	check(a.formation == "line", "a firing regiment stands in line")


func test_ford() -> void:
	var sim := quiet(new_sim())
	var dry := sim.spawn(0, "line_infantry", Vector2(12, 5))
	var wet := sim.spawn(0, "line_infantry", Vector2(3, Sim.CREEK_Y0 + 0.2))
	wet.lane = 0
	var y_dry := dry.pos.y
	var y_wet := wet.pos.y
	run(sim, 1.0)
	var moved_dry := dry.pos.distance_to(Vector2(12, y_dry))
	check(near(moved_dry, 1.4, 0.05), "infantry marches 1.4 paces a second (%.2f)" % moved_dry)
	check(near(wet.pos.y - y_wet, 1.4 * 0.6, 0.05), "wading a ford is 40%% slower (%.2f)" % (wet.pos.y - y_wet))
	# A regiment standing in the ford cannot fire.
	var sim2 := quiet(new_sim())
	var wader := sim2.spawn(0, "line_infantry", Vector2(3, Sim.CREEK_Y0 + 1.0))
	var target := sim2.spawn(1, "militia", Vector2(3, Sim.CREEK_Y1 + 2.0))
	target.reload = 99.0
	sim2.tick()
	check(not wader.fired_first, "no firing from the water")
	check(near(target.hp, target.max_hp), "the enemy on the bank is unharmed")


func test_square_repels_cavalry() -> void:
	var sim := quiet(new_sim())
	# Out in the open field, clear of the Headquarters, so the cavalry has nothing else to go for.
	var line := sim.spawn(0, "line_infantry", Vector2(13, 10))
	var cav := sim.spawn(1, "scouts", Vector2(13, 16.5))
	run(sim, 4.0)
	check(has_event(sim, "square"), "infantry forms square when cavalry closes")
	check(has_event(sim, "repelled"), "the charge is repelled by the square")
	check(not has_event(sim, "charge"), "no successful charge")
	check(line.state != Sim.ST_ROUT and not line.dead, "the square holds")
	check(cav.dead or cav.hp < cav.max_hp, "the cavalry is hurt")


func test_cavalry_catches_reloading_line() -> void:
	var sim := quiet(new_sim())
	var line := sim.spawn(0, "line_infantry", Vector2(9, 5))
	line.reload = 3.2
	line.fired_first = true
	sim.spawn(1, "heavy_cavalry", Vector2(9, 10.4))
	run(sim, 3.0)
	check(has_event(sim, "charge"), "cavalry reaches a reloading line before the square closes")
	check(not has_event(sim, "repelled"), "the square never formed")
	check(line.dead or line.state == Sim.ST_ROUT, "the line is broken")


func test_militia_cannot_square() -> void:
	var sim := quiet(new_sim())
	var mob := sim.spawn(0, "militia", Vector2(9, 5))
	mob.reload = 99.0
	sim.spawn(1, "scouts", Vector2(9, 11.5))
	run(sim, 3.0)
	check(not has_event(sim, "square"), "militia never forms square")
	check(has_event(sim, "charge"), "cavalry charges home on militia")
	check(mob.dead or mob.state == Sim.ST_ROUT, "the militia breaks")


func test_rout_and_rally() -> void:
	var sim := new_sim()
	var r := sim.spawn(0, "line_infantry", Vector2(9, 12))
	r.morale = 5.0
	sim._damage(r, 60.0, Vector2(9, 20))
	check(r.state == Sim.ST_ROUT, "a regiment breaks when its nerve reaches zero")
	check(has_event(sim, "rout"), "a rout is announced")
	run(sim, 1.0)
	check(r.pos.y < 12.0, "a routed regiment runs for home")
	var before := r.hp
	sim._damage(r, 10.0, Vector2(9, 20))
	check(near(before - r.hp, 15.0), "routed troops take half again as much damage")
	run(sim, 12.0)
	check(r.state == Sim.ST_MARCH, "it rallies at Headquarters")
	check(has_event(sim, "rally"), "a rally is announced")
	check(r.morale >= 50.0 and r.morale < 100.0, "it comes back with about half its nerve (%.1f)" % r.morale)
	# With no Headquarters to run to, a routed regiment leaves the field.
	var sim2 := new_sim()
	var lost := sim2.spawn(0, "line_infantry", Vector2(9, 6))
	sim2.hq(0).dead = true
	sim2._start_rout(lost)
	run(sim2, 8.0)
	check(sim2.regiments.is_empty(), "with no Headquarters, a routed regiment is gone")


func test_field_gun() -> void:
	var sim := quiet(new_sim())
	var gun := sim.spawn(0, "field_gun", Vector2(9, 4))
	var front := sim.spawn(1, "line_infantry", Vector2(9, 12))
	var behind := sim.spawn(1, "line_infantry", Vector2(9, 14.5))
	front.reload = 99.0
	behind.reload = 99.0
	sim.tick()
	# 150 roundshot, x1.5 against a column; half of that again for the regiment behind.
	check(near(front.hp, 360.0 - 225.0), "roundshot hits a column for 225 (%.1f left)" % front.hp)
	check(near(behind.hp, 360.0 - 112.5), "and ploughs on into the regiment behind (%.1f left)" % behind.hp)
	check(near(gun.reload, 4.0), "the gun reloads for 4 s")
	var sim2 := quiet(new_sim())
	sim2.spawn(0, "field_gun", Vector2(9, 4))
	var close := sim2.spawn(1, "line_infantry", Vector2(9, 7.5))
	close.reload = 99.0
	sim2.tick()
	check(has_event(sim2, "canister") and near(close.hp, 360.0 - 220.0), "grapeshot at close range does 220")
	var sim3 := quiet(new_sim())
	sim3.spawn(0, "field_gun", Vector2(9, 4))
	var loose := sim3.spawn(1, "skirmishers", Vector2(9, 12))
	loose.reload = 99.0
	sim3.tick()
	check(near(loose.hp, 180.0 - 60.0), "roundshot does little to loose order (%.1f left)" % loose.hp)
	var sim4 := quiet(new_sim())
	sim4.spawn(0, "field_gun", Vector2(4, 4))
	run(sim4, 35.1)
	check(sim4.regiments.is_empty(), "a gun leaves the field when its ammunition is spent")
	var sim5 := quiet(new_sim())
	var prey := sim5.spawn(0, "field_gun", Vector2(9, 5))
	prey.reload = 99.0
	sim5.spawn(1, "scouts", Vector2(9, 9))
	run(sim5, 2.5)
	check(prey.dead or sim5.regiments.all(func(x): return x.arm != "artillery" or x.state == Sim.ST_ROUT), "cavalry overruns an unguarded gun")


func test_redoubt_and_deploy_zone() -> void:
	var sim := new_sim()
	var intruder := sim.spawn(1, "line_infantry", Vector2(3.5, 13))
	intruder.reload = 99.0
	sim.tick()
	check(near(intruder.hp, 360.0 - Sim.REDOUBT_DMG), "a redoubt fires on troops in range")
	var sim2 := new_sim()
	sim2.powder[0] = 10.0
	var hand: Array = sim2.hand(0)
	var idx := -1
	for i in 4:
		if cards[hand[i]]["type"] == "unit":
			idx = i
	check(sim2.deploy_error(0, idx, Vector2(3, 20)) != "", "cannot deploy across the creek while the redoubt stands")
	sim2._damage_structure(sim2.redoubt(1, 0), 99999.0)
	check(sim2.redoubt(1, 0).dead and sim2.phase != Sim.PHASE_OVER, "a fallen redoubt does not end regular time")
	check(sim2.deploy_error(0, idx, Vector2(3, 20)) == "", "a fallen redoubt opens that flank to deployment")
	check(sim2.deploy_error(0, idx, Vector2(15, 20)) != "", "the other flank stays closed")
	var marcher := sim2.spawn(0, "line_infantry", Vector2(3, 20))
	check(sim2._lane_structure(marcher).kind == "hq", "with the redoubt gone, that lane marches on Headquarters")


func test_orders() -> void:
	var sim := new_sim()
	var r := sim.spawn(0, "line_infantry", Vector2(9, 6))
	r.reload = 3.0
	sim.decks[0] = ["fire", "rally", "militia", "scouts", "line_infantry", "skirmishers", "heavy_cavalry", "field_gun"]
	sim.powder[0] = 10.0
	check(sim.deploy_error(0, 0, Vector2(2, 2)) != "", "Fire! needs a regiment under it")
	check(sim.deploy(0, 0, Vector2(9, 6.5)), "Fire! is accepted on a regiment")
	check(near(r.reload, 0.0), "Fire! clears the reload")
	sim._start_rout(r)
	var rally_idx: int = sim.hand(0).find("rally")
	check(sim.deploy(0, rally_idx, r.pos), "Rally is accepted on a routing regiment")
	check(r.state == Sim.ST_MARCH and near(r.morale, 50.0), "Rally stops the rout and restores nerve")


func test_win_conditions() -> void:
	var sim := new_sim()
	sim._damage_structure(sim.hq(1), 99999.0)
	check(sim.phase == Sim.PHASE_OVER and sim.winner == 0, "capturing the Colours wins at once")
	var sim2 := new_sim()
	sim2._damage_structure(sim2.redoubt(0, 1), 99999.0)
	run(sim2, 180.0)
	check(sim2.phase == Sim.PHASE_OVER and sim2.winner == 1, "more redoubts destroyed wins on time")
	var sim3 := new_sim()
	run(sim3, 180.0)
	check(sim3.phase == Sim.PHASE_OVERTIME, "a level match goes to overtime")
	sim3._damage_structure(sim3.redoubt(1, 0), 99999.0)
	check(sim3.phase == Sim.PHASE_OVER and sim3.winner == 0, "in overtime the first structure to fall decides it")
	var sim4 := new_sim()
	sim4._damage_structure(sim4.redoubt(0, 0), 100.0)
	run(sim4, 240.0)
	check(sim4.phase == Sim.PHASE_OVER and sim4.winner == 1, "after overtime the side with healthier structures wins")
	var sim5 := new_sim()
	run(sim5, 240.0)
	check(sim5.winner == Sim.DRAW, "a dead-level match is a draw")


func play_bots(seed_value: int, seconds: float) -> Sim:
	var sim := new_sim(seed_value)
	var b0 := Bot.new(0, seed_value)
	var b1 := Bot.new(1, seed_value)
	for i in int(seconds * Sim.TICK_RATE):
		b0.tick(sim)
		b1.tick(sim)
		sim.tick()
		sim.events.clear()
	return sim


func test_determinism() -> void:
	var a := play_bots(42, 90.0)
	var b := play_bots(42, 90.0)
	var c := play_bots(43, 90.0)
	check(a.command_log.size() > 6, "the bots actually play cards (%d deploys)" % a.command_log.size())
	check(a.state_hash() == b.state_hash(), "the same seed gives the same battle")
	if a.state_hash() != b.state_hash():
		for i in mini(a.command_log.size(), b.command_log.size()):
			if str(a.command_log[i]) != str(b.command_log[i]):
				print("    first difference at deploy %d: %s vs %s" % [i, a.command_log[i], b.command_log[i]])
				break
	check(a.state_hash() != c.state_hash(), "a different seed gives a different battle")


# --- The ten later cards ---------------------------------------------------------------------

func test_sharpshooters() -> void:
	var sim := quiet(new_sim())
	sim.spawn(0, "sharpshooters", Vector2(9, 4))
	var line := sim.spawn(1, "line_infantry", Vector2(9, 10))
	var gun := sim.spawn(1, "field_gun", Vector2(9, 14.5))
	line.reload = 99.0
	gun.reload = 99.0
	sim.tick()
	# 2 men x 55, half again for the first volley.
	check(near(gun.hp, 150.0 - 165.0) or gun.dead, "sharpshooters pick the gun crew over the nearer line (gun %.1f)" % gun.hp)
	check(near(line.hp, 360.0), "and leave the line alone")
	var sim2 := quiet(new_sim())
	sim2.spawn(0, "sharpshooters", Vector2(9, 4))
	var far := sim2.spawn(1, "line_infantry", Vector2(9, 14.5))
	far.reload = 99.0
	sim2.tick()
	check(far.hp < 360.0, "they reach 10.5 paces, far beyond a musket")


func test_zouaves() -> void:
	var sim := quiet(new_sim())
	var z := sim.spawn(0, "zouaves", Vector2(13, 10))
	var foe := sim.spawn(1, "line_infantry", Vector2(13, 15))
	foe.reload = 99.0
	check(near(z.morale_max, 160.0), "zouaves have the steadiest nerve on the field")
	sim.tick()
	check(z.reload > 0.0, "they open with a volley")
	run(sim, 3.0)
	check(has_event(sim, "bayonet"), "and then go in with the bayonet instead of reloading")
	check(z.in_melee or foe.state == Sim.ST_ROUT or foe.dead, "they are in among the enemy within three seconds, or it has already run")
	var cav_sim := quiet(new_sim())
	var z2 := cav_sim.spawn(0, "zouaves", Vector2(13, 10))
	cav_sim.spawn(1, "scouts", Vector2(13, 16))
	run(cav_sim, 0.2)
	check(z2.state == Sim.ST_FORMING, "they still form square when horse bears down")


func test_dragoons() -> void:
	var sim := quiet(new_sim())
	var d := sim.spawn(0, "dragoons", Vector2(13, 4))
	check(d.mounted and d.arm == "cavalry", "dragoons arrive mounted")
	var start := d.pos.y
	run(sim, 1.0)
	check(d.pos.y - start > 2.5, "and ride fast (%.2f paces in a second)" % (d.pos.y - start))
	var foe := sim.spawn(1, "militia", Vector2(13, d.pos.y + 5.5))
	foe.reload = 99.0
	var hp := foe.hp
	run(sim, 0.2)
	check(not d.mounted and d.arm == "infantry" and has_event(sim, "dismount"), "they get down when an enemy comes into carbine range")
	var held := d.pos
	run(sim, 1.5)
	check(foe.hp < hp, "and open fire on foot")
	check(d.pos.distance_to(held) < 0.3, "holding the spot")
	foe.dead = true
	run(sim, 2.5)
	check(d.mounted and has_event(sim, "mount"), "they mount again once it is quiet")
	var sq := quiet(new_sim())
	var line := sq.spawn(1, "line_infantry", Vector2(13, 20))
	line.reload = 99.0
	sq.spawn(0, "dragoons", Vector2(13, 14.5))
	run(sq, 0.2)
	check(line.state == Sim.ST_FORMING, "mounted dragoons make infantry form square")


func test_horse_artillery() -> void:
	var sim := quiet(new_sim())
	var gun := sim.spawn(0, "horse_artillery", Vector2(13, 4))
	var start := gun.pos.y
	run(sim, 1.4)
	check(near(gun.pos.y, start), "horse artillery waits a moment before limbering up")
	run(sim, 3.0)
	check(gun.limbered and gun.pos.y > start + 2.0, "then follows the advance (%.2f paces)" % (gun.pos.y - start))
	var foe := sim.spawn(1, "line_infantry", Vector2(13, gun.pos.y + 9.0))
	foe.reload = 99.0
	run(sim, 0.1)
	check(not gun.limbered and gun.reload > 1.0, "an enemy in range makes it unlimber, which takes time")
	var stopped := gun.pos.y
	run(sim, 1.4)
	check(foe.hp < 360.0 and near(gun.pos.y, stopped, 0.05), "and then it fires from where it stopped")


func test_gatling() -> void:
	var sim := quiet(new_sim())
	var gun := sim.spawn(0, "gatling_gun", Vector2(9, 4))
	var foe := sim.spawn(1, "heavy_cavalry", Vector2(9, 10))
	foe.hp = 100000.0
	foe.max_hp = 100000.0
	foe.recoil = 99.0
	foe.def = foe.def.duplicate()
	foe.def["speed"] = 0.0
	run(sim, 1.0)
	var bursts := 0
	for e: Dictionary in sim.events:
		if e["type"] == "burst":
			bursts += 1
	check(bursts == 4, "a Gatling fires four bursts a second (%d)" % bursts)
	check(near(100000.0 - foe.hp, 64.0), "for 16 each (%.1f)" % (100000.0 - foe.hp))
	run(sim, 5.2)
	check(has_event(sim, "jam") and gun.reload > 3.0, "after six seconds of fire it jams")
	var jammed_hp := foe.hp
	run(sim, 1.0)
	check(near(foe.hp, jammed_hp), "and is silent while jammed")
	sim.powder[0] = 10.0
	sim.decks[0] = ["fire", "rally", "militia", "scouts", "field_gun"]
	check(sim.deploy(0, 0, gun.pos), "Fire! can be given to a jammed Gatling")
	run(sim, 0.3)
	check(foe.hp < jammed_hp, "which clears the jam")


func test_howitzer() -> void:
	var sim := quiet(new_sim())
	var how := sim.spawn(0, "howitzer", Vector2(9, 4))
	var a := sim.spawn(1, "line_infantry", Vector2(9, 14))
	var b := sim.spawn(1, "line_infantry", Vector2(10.6, 14.4))
	for r: Sim.Regiment in [a, b]:
		r.reload = 99.0
		r.def = r.def.duplicate()
		r.def["speed"] = 0.0
	sim.tick()
	check(has_event(sim, "shell") and near(a.hp, 360.0), "a howitzer shell takes time to arrive")
	run(sim, 1.4)
	check(near(a.hp, 230.0) and near(b.hp, 230.0), "then bursts on everyone within reach (%.0f, %.0f)" % [a.hp, b.hp])
	check(near(how.reload, 6.5 - 1.45, 0.06), "and the howitzer is slow to reload")
	var sim2 := quiet(new_sim())
	sim2.spawn(0, "howitzer", Vector2(9, 4))
	var close := sim2.spawn(1, "line_infantry", Vector2(9, 7))
	close.reload = 99.0
	close.def = close.def.duplicate()
	close.def["speed"] = 0.0
	run(sim2, 3.0)
	check(near(close.hp, 360.0), "it cannot drop a shell on something right in front of it")
	var sim3 := quiet(new_sim())
	sim3.spawn(0, "howitzer", Vector2(9, 4))
	var mover := sim3.spawn(1, "scouts", Vector2(3, 15))
	sim3.tick()
	run(sim3, 1.4)
	check(near(mover.hp, mover.max_hp), "a shell can be outrun")


func test_grand_battery() -> void:
	var sim := quiet(new_sim())
	sim.decks[0] = ["grand_battery", "rally", "militia", "scouts", "field_gun"]
	sim.powder[0] = 10.0
	var sq := sim.spawn(1, "line_infantry", Vector2(13, 24))
	sq.state = Sim.ST_SQUARE
	sq.formation = "square"
	sq.release_timer = 99.0
	sq.reload = 99.0
	check(sim.deploy_error(0, 0, sq.pos) == "", "the Grand Battery can be called down anywhere, even deep in enemy ground")
	sim.deploy(0, 0, sq.pos)
	check(near(sim.powder[0], 6.0), "it costs 4 Powder")
	run(sim, 1.9)
	check(near(sq.hp, 360.0), "nothing lands for two seconds")
	run(sim, 0.2)
	check(sq.dead or near(sq.hp, 0.0), "then a square under it is destroyed (200 x2)")
	var sim2 := quiet(new_sim())
	sim2.decks[0] = ["grand_battery", "rally", "militia", "scouts", "field_gun"]
	sim2.powder[0] = 10.0
	var redoubt := sim2.redoubt(1, 0)
	sim2.deploy(0, 0, redoubt.pos)
	run(sim2, 2.1)
	check(near(redoubt.hp, Sim.REDOUBT_HP - 260.0), "it does 260 to a structure")


func test_earthworks() -> void:
	var open_sim := quiet(new_sim())
	var target := open_sim.spawn(0, "line_infantry", Vector2(13, 10))
	target.reload = 99.0
	open_sim.spawn(1, "line_infantry", Vector2(13, 15.5))
	open_sim.tick()
	var open_loss := 360.0 - target.hp
	var sim := quiet(new_sim())
	sim.decks[0] = ["earthworks", "rally", "militia", "scouts", "field_gun"]
	sim.powder[0] = 10.0
	check(sim.deploy(0, 0, Vector2(13, 10.6)), "earthworks are placed like a unit")
	check(sim.works.size() == 1 and sim.regiments.is_empty(), "they are a work, not a regiment")
	var covered := sim.spawn(0, "line_infantry", Vector2(13, 10))
	covered.reload = 99.0
	sim.spawn(1, "line_infantry", Vector2(13, 15.5))
	sim.tick()
	check(near(360.0 - covered.hp, open_loss * 0.5), "a volley does half to troops behind them (%.1f against %.1f)" % [360.0 - covered.hp, open_loss])
	var sim2 := quiet(new_sim())
	sim2.place_work(0, "earthworks", Vector2(13, 10.6))
	var shelled := sim2.spawn(0, "line_infantry", Vector2(13, 10))
	shelled.reload = 99.0
	sim2.spawn(1, "field_gun", Vector2(13, 20))
	sim2.tick()
	check(near(360.0 - shelled.hp, 225.0), "they do nothing against cannon (%.1f, the full 150 x1.5 on a column)" % (360.0 - shelled.hp))
	run(sim2, 60.0)
	check(sim2.works.is_empty(), "and they crumble after a minute")


func test_balloon() -> void:
	var sim := quiet(new_sim())
	sim.spawn(0, "field_gun", Vector2(13, 4))
	var far := sim.spawn(1, "line_infantry", Vector2(13, 18))
	far.reload = 99.0
	far.def = far.def.duplicate()
	far.def["speed"] = 0.0
	run(sim, 0.5)
	check(near(far.hp, 360.0), "14 paces is beyond a field gun")
	sim.place_work(0, "balloon", Vector2(15, 3))
	sim.tick()
	check(far.hp < 360.0, "until a balloon goes up on that flank")
	var sim2 := quiet(new_sim())
	sim2.spawn(0, "field_gun", Vector2(13, 4))
	var other := sim2.spawn(1, "line_infantry", Vector2(13, 18))
	other.reload = 99.0
	other.def = other.def.duplicate()
	other.def["speed"] = 0.0
	sim2.place_work(0, "balloon", Vector2(3, 3))
	run(sim2, 0.5)
	check(near(other.hp, 360.0), "a balloon on the other flank is no help")


func test_general() -> void:
	var plain := quiet(new_sim())
	var alone := plain.spawn(0, "line_infantry", Vector2(13, 10))
	alone.reload = 99.0
	plain.spawn(1, "line_infantry", Vector2(13, 15.5))
	plain.tick()
	var plain_loss := alone.morale_max - alone.morale
	var sim := quiet(new_sim())
	var led := sim.spawn(0, "line_infantry", Vector2(13, 10))
	led.reload = 99.0
	var g := sim.spawn(0, "general", Vector2(13, 7.6))
	sim.spawn(1, "line_infantry", Vector2(13, 15.5))
	sim.tick()
	sim.tick()
	check(near(led.morale_max - led.morale, plain_loss * 0.6, 0.2), "troops near the General lose less nerve (%.1f against %.1f)" % [led.morale_max - led.morale, plain_loss])
	var sim2 := quiet(new_sim())
	var loader := sim2.spawn(0, "line_infantry", Vector2(13, 10))
	sim2.spawn(0, "general", Vector2(13, 7.6))
	loader.reload = 3.0
	loader.state = Sim.ST_SQUARE
	loader.release_timer = 99.0
	run(sim2, 1.0)
	check(near(loader.reload, 3.0 - 1.25, 0.07), "and reload a quarter faster (%.2f left of 3)" % loader.reload)
	var sim3 := quiet(new_sim())
	var runner := sim3.spawn(0, "line_infantry", Vector2(13, 14))
	runner.state = Sim.ST_ROUT
	runner.morale = 0.0
	sim3.spawn(0, "general", Vector2(13, 12))
	run(sim3, 2.6)
	check(runner.state != Sim.ST_ROUT, "a routed regiment rallies on the General")
	var sim4 := quiet(new_sim())
	var shaken := sim4.spawn(0, "line_infantry", Vector2(13, 10))
	shaken.reload = 99.0
	var doomed := sim4.spawn(0, "general", Vector2(13, 7.6))
	sim4.tick()
	sim4._damage(doomed, 9999.0, Vector2(13, 20))
	check(has_event(sim4, "general_down") and near(shaken.morale, 100.0 - 35.0), "when he falls, those around him take a shock (%.1f)" % shaken.morale)
	var sim5 := quiet(new_sim())
	sim5.decks[0] = ["general", "general", "militia", "scouts", "field_gun"]
	sim5.powder[0] = 10.0
	check(sim5.deploy(0, 0, Vector2(9, 6)), "a General can be deployed")
	check(sim5.deploy_error(0, 0, Vector2(9, 6)) != "" or sim5.hand(0)[0] != "general", "but only one at a time")
	var lead := sim5.spawn(0, "line_infantry", Vector2(4, 12))
	lead.reload = 99.0
	run(sim5, 6.0)
	check(sim5.general(0).pos.distance_to(lead.pos) < 4.0, "he rides to keep behind his leading regiment")


## Every card can be dealt, deployed by the bot and fought with, in decks drawn at random.
func test_any_deck_plays() -> void:
	var ids: Array = cards.keys()
	var seen := {}
	for trial in 6:
		var rng := Sim.GsRng.new(100 + trial)
		var deck0: Array = ids.duplicate()
		var deck1: Array = ids.duplicate()
		rng.shuffle(deck0)
		rng.shuffle(deck1)
		var sim := Sim.new(200 + trial, cards, deck0.slice(0, 8), deck1.slice(0, 8))
		var b0 := Bot.new(0, 200 + trial)
		var b1 := Bot.new(1, 200 + trial)
		var guard := 0
		while sim.phase != Sim.PHASE_OVER and guard < 6000:
			b0.tick(sim)
			b1.tick(sim)
			sim.tick()
			sim.events.clear()
			guard += 1
		for c: Dictionary in sim.command_log:
			seen[c["card"]] = true
		check(sim.phase == Sim.PHASE_OVER, "a match with random decks finishes (trial %d)" % trial)
		check(sim.command_log.size() >= 12, "and the bots find things to play from them (%d deploys)" % sim.command_log.size())
	check(seen.size() >= 16, "nearly every card gets played across the trials (%d of 18)" % seen.size())
