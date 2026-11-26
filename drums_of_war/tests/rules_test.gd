extends SceneTree
## Headless checks of the battle rules. Prints DRUMS_RULES_PASS when every check holds.

const Sim = preload("res://scripts/sim/battle_sim.gd")
const Bot = preload("res://scripts/sim/bot.gd")
const Profile = preload("res://scripts/app/profile.gd")

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
	check(cards.size() == 48, "forty-eight cards load from data/cards.json")
	var tiers := {}
	for id: String in cards:
		tiers[cards[id].get("rarity", "")] = int(tiers.get(cards[id].get("rarity", ""), 0)) + 1
	check(tiers.keys().all(func(t): return t in ["common", "rare", "epic", "legendary"]), "every card has a rarity")
	check(int(tiers.get("common", 0)) == 18 and int(tiers.get("rare", 0)) == 15 and int(tiers.get("epic", 0)) == 10 and int(tiers.get("legendary", 0)) == 5,
			"eighteen common, fifteen rare, ten epic and five legendary")
	for id: String in cards:
		var d: Dictionary = cards[id]
		if d["type"] != "unit" and String(d.get("effect", "")) == "":
			check(false, "%s says what it does (an effect)" % id)
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
	test_levels()
	test_later_infantry()
	test_later_cavalry()
	test_later_guns()
	test_later_orders()
	test_later_works()
	test_leaders()
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
	# Roundshot x1.5 against a column; half of that again for the regiment behind.
	var shot := float(cards["field_gun"]["shot_dmg"])
	check(near(front.hp, 360.0 - shot * 1.5), "roundshot hits a column half again as hard (%.1f left)" % front.hp)
	check(near(behind.hp, 360.0 - shot * 0.75), "and ploughs on into the regiment behind (%.1f left)" % behind.hp)
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
	check(near(loose.hp, 160.0 - shot * Sim.LOOSE_SHOT_MULT), "roundshot does little to loose order (%.1f left)" % loose.hp)
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
	check(near(sim.powder[0], 9.0), "and costs 1 Powder")
	r.fired_first = true
	sim.decks[0][sim.decks[0].find("fire")] = "militia"
	sim.decks[0][0] = "fire"
	sim.deploy(0, 0, Vector2(9, 6.5))
	check(not r.fired_first, "a regiment given Fire! shoots as hard as with its first volley")
	sim._start_rout(r)
	var rally_idx: int = sim.hand(0).find("rally")
	check(sim.deploy(0, rally_idx, r.pos), "Rally is accepted on a routing regiment")
	check(r.state == Sim.ST_MARCH and near(r.morale, 70.0), "Rally stops the rout and restores nerve")


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
	var gun := sim.spawn(1, "field_gun", Vector2(9, 13.5))
	line.reload = 99.0
	gun.reload = 99.0
	sim.tick()
	# 2 men x 45, half again for the first volley.
	check(near(gun.hp, 150.0 - 135.0), "sharpshooters pick the gun crew over the nearer line (gun %.1f)" % gun.hp)
	check(near(line.hp, 360.0), "and leave the line alone")
	var sim2 := quiet(new_sim())
	sim2.spawn(0, "sharpshooters", Vector2(9, 4))
	var far := sim2.spawn(1, "line_infantry", Vector2(9, 13.5))
	far.reload = 99.0
	sim2.tick()
	check(far.hp < 360.0, "they reach 9.5 paces, far beyond a musket")
	var sim3 := quiet(new_sim())
	sim3.spawn(0, "sharpshooters", Vector2(3.5, 20.0))
	var work := sim3.redoubt(1, 0)
	sim3.tick()
	# 135 for the volley, and only three tenths of that on earth and timber.
	check(near(Sim.REDOUBT_HP - work.hp, 135.0 * Sim.STRUCT_MUSKET_MULT * 0.3), "but their rifles do little to a battery (%.1f)" % (Sim.REDOUBT_HP - work.hp))


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
	run(sim, 6.2)
	check(has_event(sim, "jam") and gun.reload > 2.0, "after seven seconds of fire it jams")
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
	check(near(a.hp, 210.0) and near(b.hp, 210.0), "then bursts on everyone within reach (%.0f, %.0f)" % [a.hp, b.hp])
	check(near(how.reload, 6.0 - 1.45, 0.06), "and the howitzer is slow to reload")
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
	check(sq.dead or near(sq.hp, 0.0), "then a square under it is destroyed (180 x2)")
	var sim2 := quiet(new_sim())
	sim2.decks[0] = ["grand_battery", "rally", "militia", "scouts", "field_gun"]
	sim2.powder[0] = 10.0
	var redoubt := sim2.redoubt(1, 0)
	sim2.deploy(0, 0, redoubt.pos)
	run(sim2, 2.1)
	check(near(redoubt.hp, Sim.REDOUBT_HP - 170.0), "it does 170 to a structure")


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
	check(near(360.0 - shelled.hp, float(cards["field_gun"]["shot_dmg"]) * 1.5), "they do nothing against cannon (%.1f, a full shot on a column)" % (360.0 - shelled.hp))
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
	check(near(led.morale_max - led.morale, plain_loss * float(cards["general"]["aura_nerve"]), 0.2), "troops near the General lose less nerve (%.1f against %.1f)" % [led.morale_max - led.morale, plain_loss])
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
	check(sim5.general(0).pos.distance_to(lead.pos) < 5.0, "he rides to keep behind his leading regiment")


## Every card can be dealt, deployed by the bot and fought with, in decks drawn at random.
func test_levels() -> void:
	check(near(float(Bot.LEVELS[1]["powder"]), 1.0) and near(float(Bot.LEVELS[0]["powder"]), 1.0), "Recruit and Regular get Powder at the player's rate")
	var sim := new_sim()
	sim.powder_rate[1] = float(Bot.LEVELS[2]["powder"])
	sim.powder = [0.0, 0.0]
	run(sim, 14.0)
	check(near(sim.powder[1] / sim.powder[0], float(Bot.LEVELS[2]["powder"]), 0.01) and float(Bot.LEVELS[2]["powder"]) > 1.0,
			"the Veteran's Powder comes faster by the stated share (%.2f)" % (sim.powder[1] / sim.powder[0]))


func test_any_deck_plays() -> void:
	var ids: Array = cards.keys()
	var seen := {}
	for trial in 16:
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
	check(seen.size() >= 40, "nearly every card gets played across the trials (%d of 48)" % seen.size())
	var never: Array = cards.keys().filter(func(id): return not seen.has(id))
	if not never.is_empty():
		print("    never played: ", never)


# --- The thirty cards of the second set ---------------------------------------------------------

## A regiment that stands still and does not shoot back, for being shot at in tests.
func target(sim: Sim, side: int, id: String, at: Vector2) -> Sim.Regiment:
	var r := sim.spawn(side, id, at)
	r.reload = 9999.0
	r.def = r.def.duplicate()
	r.def["speed"] = 0.0
	return r


func test_later_infantry() -> void:
	var sim := quiet(new_sim())
	var a := target(sim, 1, "line_infantry", Vector2(13, 14))
	var b := target(sim, 1, "line_infantry", Vector2(14.4, 14.2))
	var far := target(sim, 1, "line_infantry", Vector2(17, 14))
	var g := sim.spawn(0, "grenadiers", Vector2(13, 9.5))
	sim.tick()
	# 5 men, half again for the first volley; the regiment beside it takes half.
	var volley := 5.0 * float(cards["grenadiers"]["volley_dmg"]) * 1.5
	check(near(360.0 - a.hp, volley) and near(360.0 - b.hp, volley * 0.5), "grenadiers' grenades burst among the regiment beside their mark (%.1f, %.1f)" % [360.0 - a.hp, 360.0 - b.hp])
	check(near(far.hp, 360.0), "but not on one further off")
	var guard_sim := quiet(new_sim())
	var guard := guard_sim.spawn(0, "old_guard", Vector2(13, 10))
	guard.reload = 9999.0
	guard_sim._morale_hit(guard, 500.0)
	check(guard.state != Sim.ST_ROUT and near(guard.morale, 1.0), "the Old Guard never runs")
	var p_sim := quiet(new_sim())
	var work := p_sim.redoubt(1, 1)
	var pio := p_sim.spawn(0, "pioneers", Vector2(14.5, 20.5))
	var blocker := target(p_sim, 1, "militia", Vector2(14.5, 22.5))
	run(p_sim, 8.0)
	check(has_event(p_sim, "demolish") or near(work.hp, Sim.REDOUBT_HP - 160.0), "pioneers walk past the enemy to a battery and blow it up")
	check(near(work.hp, Sim.REDOUBT_HP - 160.0) and pio.dead, "for 160, and are gone (%.0f)" % (Sim.REDOUBT_HP - work.hp))
	check(blocker.hp > 0.0, "having ignored the regiment in their way")
	check(cards["conscripts"]["cost"] == 1 and cards["riflemen"]["range"] > cards["line_infantry"]["range"], "conscripts cost 1; riflemen outrange muskets")


func test_later_cavalry() -> void:
	var sim := quiet(new_sim())
	var runner := sim.spawn(1, "line_infantry", Vector2(13, 14))
	sim._start_rout(runner)
	var hp := runner.hp
	var h := sim.spawn(0, "hussars", Vector2(13, 13.0))
	h.runup = 0.0
	sim.tick()
	var plain := quiet(new_sim())
	var runner2 := plain.spawn(1, "line_infantry", Vector2(13, 14))
	plain._start_rout(runner2)
	var h2 := plain.spawn(0, "lancers", Vector2(13, 13.0))
	h2.runup = 0.0
	plain.tick()
	# Both sword 3 men; hussars 32 x 2.5 for the chase, lancers 28 without, and both x1.5 on the running.
	check(near(hp - runner.hp, 3 * 32 * 2.5 * 1.5 * Sim.DT, 0.05), "hussars cut down a running regiment at 2.5 times the rate (%.2f)" % (hp - runner.hp))
	var sq_sim := quiet(new_sim())
	var square := sq_sim.spawn(1, "line_infantry", Vector2(13, 14))
	square.state = Sim.ST_SQUARE
	square.formation = "square"
	square.release_timer = 999.0
	square.reload = 999.0
	var lance := sq_sim.spawn(0, "lancers", Vector2(13, 12.9))
	lance.runup = 9.0
	sq_sim.tick()
	check(has_event(sq_sim, "repelled") and near(360.0 - square.hp, 3 * float(cards["lancers"]["charge_dmg"]) * 0.5), "lancers still put half a charge into a square (%.1f)" % (360.0 - square.hp))
	check(300.0 - lance.hp < Sim.SQUARE_REPEL_DMG * 0.5 + 6.0, "and take half the usual hurt from it (%.1f)" % (300.0 - lance.hp))
	var cav_sim := quiet(new_sim())
	var cuir := target(cav_sim, 1, "cuirassiers", Vector2(13, 15))
	var hus := target(cav_sim, 1, "hussars", Vector2(5, 15))
	cav_sim.spawn(0, "riflemen", Vector2(13, 8.0))
	cav_sim.spawn(0, "riflemen", Vector2(5, 8.0))
	cav_sim.tick()
	var cut := hus.max_hp - hus.hp
	check(cut > 0.0 and near(cuir.max_hp - cuir.hp, cut * 0.5), "a cuirass turns half of every musket ball (%.1f against %.1f)" % [cuir.max_hp - cuir.hp, cut])


func test_later_guns() -> void:
	var sim := quiet(new_sim())
	var rk := sim.spawn(0, "rocket_troop", Vector2(9, 4))
	var mark := target(sim, 1, "scouts", Vector2(9, 13))
	sim.tick()
	var flight: Dictionary = sim.shells[0] if not sim.shells.is_empty() else {}
	check(not flight.is_empty() and flight["kind"] == "rocket", "rocket troops fire rockets")
	check(not flight.is_empty() and Vector2(flight["pos"]).distance_to(mark.pos) <= 2.2 * 1.42, "which land somewhere near the mark")
	var sim2 := quiet(new_sim())
	sim2.spawn(0, "siege_gun", Vector2(3.5, 12.0))
	var nearer := target(sim2, 1, "line_infantry", Vector2(3.5, 16.0))
	var work := sim2.redoubt(1, 0)
	sim2.tick()
	var siege: Dictionary = cards["siege_gun"]
	check(near(nearer.hp, 360.0) and near(Sim.REDOUBT_HP - work.hp, float(siege["shot_dmg"]) * Sim.STRUCT_SHOT_MULT * float(siege["struct_mult"])),
			"a siege gun shoots at the battery before the regiment in front of it, and hits it hard (%.0f)" % (Sim.REDOUBT_HP - work.hp))
	var sim3 := quiet(new_sim())
	sim3.spawn(0, "rifled_gun", Vector2(9, 4))
	var far := target(sim3, 1, "line_infantry", Vector2(9, 17.5))
	sim3.tick()
	check(far.hp < 360.0, "a rifled gun reaches 13.5 paces")
	var sim4 := quiet(new_sim())
	var mh := sim4.spawn(0, "mountain_howitzer", Vector2(13, 4))
	run(sim4, 3.0)
	check(mh.limbered and mh.pos.y > 4.5, "a mountain howitzer limbers up and follows the advance")
	var sim5 := quiet(new_sim())
	sim5.spawn(0, "great_mortar", Vector2(3.5, 9.0))
	var far_work := sim5.redoubt(1, 0)
	run(sim5, 2.4)
	check(near(Sim.REDOUBT_HP - far_work.hp, 300.0 * Sim.STRUCT_SHOT_MULT), "the Great Mortar reaches a battery 18.5 paces off, from behind your own (%.0f)" % (Sim.REDOUBT_HP - far_work.hp))


func test_later_orders() -> void:
	var sim := quiet(new_sim())
	var a := sim.spawn(0, "line_infantry", Vector2(12, 10))
	var b := sim.spawn(0, "line_infantry", Vector2(14, 10))
	a.reload = 3.0
	b.reload = 3.0
	a.fired_first = true
	b.fired_first = true
	sim.decks[0] = ["volley_fire", "forced_march", "hold_the_line", "cut_supply", "militia"]
	sim.powder = [10.0, 10.0]
	check(sim.deploy_error(0, 0, Vector2(2, 30)) != "", "Volley Fire! needs regiments under it")
	check(sim.deploy(0, 0, Vector2(13, 10)), "Volley Fire! is accepted on two regiments")
	check(near(a.reload, 0.0) and near(b.reload, 0.0) and not a.fired_first and not b.fired_first, "both fire at once, as hard as a first volley")
	var idx: int = sim.hand(0).find("forced_march")
	check(sim.deploy(0, idx, Vector2(13, 10)), "Forced March is accepted")
	var start := a.pos
	sim.tick()
	check(near(a.pos.distance_to(start), 1.4 * 1.5 * Sim.DT, 0.002), "and they march half again as fast (%.3f)" % a.pos.distance_to(start))
	idx = sim.hand(0).find("hold_the_line")
	sim.deploy(0, idx, Vector2(13, 10))
	sim._morale_hit(a, 500.0)
	check(a.state != Sim.ST_ROUT, "under Hold the Line! nothing makes them run")
	run(sim, float(cards["hold_the_line"]["duration"]) + 0.1)
	sim._morale_hit(a, 500.0)
	check(a.state == Sim.ST_ROUT, "until it wears off")
	sim.powder = [10.0, 8.0]
	idx = sim.hand(0).find("cut_supply")
	check(sim.deploy(0, idx, Vector2(9, 3)), "Cut the Supply Line can be played anywhere")
	check(near(sim.powder[1], 5.0), "and the enemy loses 3 Powder")
	var bsim := quiet(new_sim())
	var cav := bsim.spawn(0, "scouts", Vector2(9, 8))
	bsim.decks[0] = ["bugle_call", "fire", "militia", "rally", "scouts"]
	bsim.powder[0] = 10.0
	check(bsim.deploy(0, 0, cav.pos) and cav.runup >= Sim.CHARGE_RUNUP, "Bugle Call makes cavalry ready to charge at once")
	var asim := quiet(new_sim())
	asim.decks[0] = ["ambush", "fire", "militia", "rally", "scouts"]
	asim.powder[0] = 10.0
	check(asim.deploy_error(0, 0, asim.redoubt(1, 0).pos + Vector2(0, -2.0)) != "", "an ambush cannot be laid right beside an enemy work")
	check(asim.deploy(0, 0, Vector2(9, 22)), "but can be laid deep in enemy ground")
	check(asim.regiments.size() == 1 and asim.regiments[0].card_id == "riflemen", "where riflemen appear")


func test_later_works() -> void:
	var sim := quiet(new_sim())
	sim.powder = [2.0, 2.0]
	sim.place_work(0, "supply_wagon", Vector2(5, 3))
	var every := float(cards["supply_wagon"]["every"])
	run(sim, every - 0.1)
	var before: float = sim.powder[0]
	run(sim, 0.2)
	check(near(sim.powder[0] - before, 1.0 + 4.0 * Sim.DT / Sim.POWDER_PERIOD, 0.01), "a supply wagon brings a point of Powder at a time")
	run(sim, float(cards["supply_wagon"]["life"]) - every + 0.2)
	check(sim.works.is_empty(), "four times, and then it is gone")
	var hsim := quiet(new_sim())
	var hurt := target(hsim, 0, "line_infantry", Vector2(9, 6))
	hsim._damage(hurt, 150.0, Vector2(9, 20))
	var men_before := hurt.men
	hsim.place_work(0, "field_hospital", Vector2(9, 5))
	run(hsim, 10.0)
	check(near(hurt.hp, minf(360.0, 210.0 + 10.0 * float(cards["field_hospital"]["heal"])), 1.0) and hurt.men > men_before,
			"a field hospital gives men back (%.0f hp, %d men)" % [hurt.hp, hurt.men])
	var msim := quiet(new_sim())
	msim.place_work(0, "torpedo", Vector2(13, 14.6))
	var walker := msim.spawn(1, "line_infantry", Vector2(13, 16.2))
	var beside := target(msim, 1, "militia", Vector2(14.6, 15.6))
	run(msim, 1.5)
	check(has_event(msim, "mine") or walker.hp < 360.0, "a torpedo goes off under the first regiment to walk over it")
	check(walker.hp <= 360.0 - float(cards["torpedo"]["dmg"]) + 0.1 and beside.hp < 320.0 and msim.works.is_empty(), "hurting everyone near it, once")
	var asim := quiet(new_sim())
	asim.place_work(0, "abatis", Vector2(9, 10))
	var horse := asim.spawn(1, "heavy_cavalry", Vector2(9, 10.5))
	horse.runup = 9.0
	asim.tick()
	check(near(horse.runup, 0.0) and horse.hp < 525.0, "an abatis stops a charge and cuts up the horses")
	var dsim := quiet(new_sim())
	dsim.place_work(0, "recruiting_depot", Vector2(9, 5))
	run(dsim, 0.1)
	check(dsim.regiments.size() == 1 and dsim.regiments[0].card_id == "conscripts", "a recruiting depot sends out conscripts at once")
	var raised := 1
	dsim.events.clear()
	for i in 40 * Sim.TICK_RATE:
		dsim.tick()
		for e: Dictionary in dsim.events:
			if e["type"] == "deploy" and e["card"] == "conscripts":
				raised += 1
		dsim.events.clear()
	check(raised == 4 and dsim.works.is_empty(), "four companies in all, and then it is gone (%d)" % raised)


func test_leaders() -> void:
	var plain := quiet(new_sim())
	var slow := plain.spawn(0, "line_infantry", Vector2(13, 5))
	slow.def = slow.def.duplicate()
	var s0 := slow.pos.y
	plain.tick()
	var sim := quiet(new_sim())
	var quick := sim.spawn(0, "line_infantry", Vector2(13, 5))
	sim.spawn(0, "drummer_boy", Vector2(13, 3))
	var q0 := quick.pos.y
	sim.tick()
	sim.tick()
	check(near((quick.pos.y - q0) / 2.0, (slow.pos.y - s0) * 1.25, 0.003), "regiments near a drummer march a quarter faster")
	var psim := quiet(new_sim())
	var piped := psim.spawn(0, "line_infantry", Vector2(13, 10))
	piped.reload = 9999.0
	psim.spawn(0, "highland_piper", Vector2(13, 8))
	psim.tick()
	piped.morale = 50.0
	piped.since_hit = 99.0
	psim.tick()
	check(near(piped.morale, 50.0 + Sim.MORALE_REGEN * 3.0 * Sim.DT), "a piper brings nerve back three times as fast")
	var msim := quiet(new_sim())
	msim.decks[0] = ["marshal", "general", "militia", "scouts", "fire"]
	msim.powder[0] = 10.0
	check(msim.deploy(0, 0, Vector2(9, 6)), "a Marshal can be deployed")
	check(msim.deploy_error(0, msim.hand(0).find("general"), Vector2(9, 6)) != "", "but not a General beside him: one commander at a time")
	check(not Profile.is_valid_deck(["general", "marshal", "militia", "scouts", "fire", "rally", "line_infantry", "zouaves"], cards),
			"and a deck may hold only one of them")
