extends Node
## Headless unit test for the card / Commander Level rules and the gunnery maths.
##
##   godot --headless --path . res://tests/TestProgression.tscn
##
## Prints PROGRESSION_OK on success.

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0
var _level_ups: Array[int] = []


func _ready() -> void:
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)
	_test_commander_levels()
	_test_card_tables()
	_test_stat_building()
	_test_profile_upgrade_flow()
	_test_loadout_rules()
	_test_save_round_trip()
	_test_ballistics()
	if _failures.is_empty():
		print("%d checks passed" % _checks)
		print("PROGRESSION_OK")
	else:
		for failure: String in _failures:
			print("FAIL: " + failure)
		print("PROGRESSION_FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_commander_levels() -> void:
	_eq(CommanderProgression.level_for_total_xp(0), 1, "0 xp is level 1")
	_eq(CommanderProgression.level_for_total_xp(19), 1, "19 xp is still level 1")
	_eq(CommanderProgression.level_for_total_xp(20), 2, "20 xp reaches level 2")
	_eq(CommanderProgression.level_for_total_xp(69), 2, "69 xp is still level 2")
	_eq(CommanderProgression.level_for_total_xp(70), 3, "70 xp reaches level 3")
	_eq(CommanderProgression.level_for_total_xp(999999999), CommanderProgression.MAX_LEVEL, "xp is capped at the max level")
	_eq(CommanderProgression.xp_into_level(75), 5, "xp into level")
	_eq(CommanderProgression.xp_to_next(CommanderProgression.MAX_LEVEL), 0, "no xp needed at max level")
	_eq(CommanderProgression.total_xp_for_level(3), 70, "total xp for level 3")
	_eq(CommanderProgression.card_slot_count(1), 3, "3 slots at level 1")
	_eq(CommanderProgression.card_slot_count(3), 3, "3 slots at level 3")
	_eq(CommanderProgression.card_slot_count(4), 4, "4 slots at level 4")
	_eq(CommanderProgression.card_slot_count(8), 5, "5 slots at level 8")
	_eq(CommanderProgression.card_slot_count(14), 5, "5 slots at level 14")
	_near(CommanderProgression.hp_multiplier(1), 1.0, "no hp bonus at level 1")
	_near(CommanderProgression.hp_multiplier(3), 1.14, "hp bonus at level 3")
	# Planes unlock at 1 / 3 / 6.
	_eq(GameCatalog.best_plane_for_level(1).id, &"hurricane", "level 1 flies the Hurricane")
	_eq(GameCatalog.best_plane_for_level(2).id, &"hurricane", "level 2 still flies the Hurricane")
	_eq(GameCatalog.best_plane_for_level(3).id, &"spitfire", "level 3 unlocks the Spitfire")
	_eq(GameCatalog.best_plane_for_level(6).id, &"mustang", "level 6 unlocks the Mustang")


func _test_card_tables() -> void:
	var common: ComponentCard = GameCatalog.find_card(&"engine_merlin")
	var rare: ComponentCard = GameCatalog.find_card(&"engine_turbo")
	var epic: ComponentCard = GameCatalog.find_card(&"engine_griffon")
	var legendary: ComponentCard = GameCatalog.find_card(&"arm_dragon")
	_eq(common.start_level(), 1, "common starts at 1")
	_eq(rare.start_level(), 3, "rare starts at 3")
	_eq(epic.start_level(), 6, "epic starts at 6")
	_eq(legendary.start_level(), 9, "legendary starts at 9")
	_eq(common.copies_required(1), 2, "common first upgrade needs 2 copies")
	_eq(common.copies_required(2), 4, "common second upgrade needs 4 copies")
	_eq(rare.copies_required(3), 2, "rare first upgrade needs 2 copies")
	_eq(common.coin_cost(1), 5, "level 1 upgrade costs 5")
	_eq(rare.coin_cost(3), 50, "level 3 upgrade costs 50")
	_eq(legendary.coin_cost(9), 8000, "level 9 upgrade costs 8000")
	_eq(common.xp_reward(1), 4, "level 1 upgrade gives 4 xp")
	_eq(common.copies_required(ComponentCard.MAX_LEVEL), 0, "maxed card needs no copies")
	_eq(common.coin_cost(ComponentCard.MAX_LEVEL), 0, "maxed card costs nothing")
	_check(not common.can_upgrade(ComponentCard.MAX_LEVEL, 99999, 999999), "maxed card cannot upgrade")
	_check(common.can_upgrade(1, 2, 5), "affordable upgrade is allowed")
	_check(not common.can_upgrade(1, 1, 5), "upgrade blocked without copies")
	_check(not common.can_upgrade(1, 2, 4), "upgrade blocked without coins")
	_near(common.level_multiplier(1), 1.0, "level 1 multiplier")
	_near(common.level_multiplier(2), 1.1, "level 2 multiplier")
	_near(common.scaled(common.top_speed_bonus, 3), 0.03 * 1.21, "bonus scales 10% per level")
	_check(legendary.total_copies_to_max() < common.total_copies_to_max(), "legendaries need fewer copies to max")
	var ids: Dictionary[StringName, bool] = {}
	for card: ComponentCard in GameCatalog.CARDS:
		_check(card.id != &"" and not ids.has(card.id), "card id '%s' is unique and set" % card.id)
		ids[card.id] = true
		_check(not card.stat_lines(card.start_level()).is_empty(), "card '%s' describes its effect" % card.id)


func _test_stat_building() -> void:
	var plane: PlaneData = GameCatalog.find_plane(&"hurricane")
	var base: PlaneStats = plane.build_base_stats(1)
	_near(base.max_hp, 1000.0, "base hp")
	_near(plane.build_base_stats(3).max_hp, 1140.0, "commander level raises hp")
	var merlin: ComponentCard = GameCatalog.find_card(&"engine_merlin")
	var armor: ComponentCard = GameCatalog.find_card(&"air_armor")
	var nitro: ComponentCard = GameCatalog.find_card(&"gad_nitro")
	var cards: Array[ComponentCard] = [merlin, null, nitro, armor]
	var levels: Array[int] = [1, 0, 1, 3]
	var at_level_1: PlaneStats = plane.build_stats(1, cards, levels)
	_near(at_level_1.top_speed, base.top_speed * 1.03, "engine card raises top speed")
	_near(at_level_1.max_hp, base.max_hp, "card in a locked slot (4th at level 1) is ignored")
	_eq(at_level_1.gadget_type, int(ComponentCard.GadgetType.NITRO_BOOST), "gadget card sets the gadget")
	var at_level_4: PlaneStats = plane.build_stats(4, cards, levels)
	_check(at_level_4.max_hp > plane.build_base_stats(4).max_hp * 1.05, "4th slot counts once level 4 opens it")


func _test_profile_upgrade_flow() -> void:
	Profile.reset_to_new_profile(false)
	Profile.commander_leveled_up.connect(_on_level_up)
	_eq(Profile.coins, Profile.STARTING_COINS, "fresh profile coins")
	_eq(Profile.commander_level(), 1, "fresh profile is level 1")
	_eq(Profile.card_level(&"engine_merlin"), 1, "starter card level")
	_eq(Profile.card_copies(&"engine_merlin"), 2, "starter card copies")
	_check(Profile.try_upgrade_card(&"engine_merlin"), "first upgrade succeeds")
	_eq(Profile.coins, Profile.STARTING_COINS - 5, "upgrade spent 5 coins")
	_eq(Profile.card_copies(&"engine_merlin"), 0, "upgrade spent 2 copies")
	_eq(Profile.card_level(&"engine_merlin"), 2, "card is now level 2")
	_eq(Profile.commander_xp, 4, "upgrade granted 4 hangar xp")
	_check(not Profile.try_upgrade_card(&"engine_merlin"), "second upgrade fails without copies")
	_eq(Profile.coins, Profile.STARTING_COINS - 5, "failed upgrade spends nothing")
	_check(not Profile.try_upgrade_card(&"arm_dragon"), "cannot upgrade a card that is not owned")
	# New cards unlock at their rarity's start level; the first copy is the card itself.
	Profile.add_card_copies(&"engine_turbo", 3)
	_eq(Profile.card_level(&"engine_turbo"), 3, "rare unlocks at level 3")
	_eq(Profile.card_copies(&"engine_turbo"), 2, "first copy unlocks the card, the rest are spare")
	# Grind to Commander Level 3 and check the Spitfire opens up.
	Profile.add_coins(1000000)
	Profile.add_card_copies(&"engine_merlin", 5000)
	Profile.add_card_copies(&"arm_brownings", 5000)
	_check(not Profile.select_plane(&"spitfire"), "Spitfire is locked at level 1")
	var guard: int = 0
	while Profile.commander_level() < 3 and guard < 40:
		guard += 1
		if not Profile.try_upgrade_card(&"engine_merlin"):
			Profile.try_upgrade_card(&"arm_brownings")
	_check(Profile.commander_level() >= 3, "upgrading cards levels the commander up")
	_check(_level_ups.has(2) and _level_ups.has(3), "commander_leveled_up fired for levels 2 and 3")
	_check(Profile.select_plane(&"spitfire"), "Spitfire can be selected at level 3")
	_check(not Profile.select_plane(&"mustang"), "Mustang is still locked")
	var before: float = Profile.build_player_stats().top_speed
	Profile.try_upgrade_card(&"engine_merlin")
	_check(Profile.build_player_stats().top_speed > before, "upgrading the equipped engine makes the plane faster")
	Profile.commander_leveled_up.disconnect(_on_level_up)


func _test_loadout_rules() -> void:
	Profile.reset_to_new_profile(false)
	_eq(Profile.loadout[0], &"engine_merlin", "starter engine equipped in slot 0")
	_eq(Profile.loadout[1], &"arm_brownings", "starter guns equipped in slot 1")
	_eq(Profile.loadout[2], &"gad_nitro", "starter gadget equipped in slot 2")
	Profile.add_card_copies(&"air_armor", 1)
	Profile.add_card_copies(&"gad_smoke", 1)
	_check(not Profile.equip_card(3, &"air_armor"), "airframe slot is locked at level 1")
	_check(not Profile.equip_card(0, &"air_armor"), "airframe card does not fit the engine slot")
	_check(Profile.equip_card(2, &"gad_smoke"), "gadget can be swapped in the gadget slot")
	_check(not Profile.equip_card(1, &"gad_smoke"), "same card cannot be equipped twice")
	_check(not Profile.equip_card(2, &"arm_dragon"), "unowned card cannot be equipped")
	var gadget: ComponentCard = GameCatalog.find_card(&"gad_nitro")
	_check(not CommanderProgression.slot_accepts(4, gadget), "wildcard slot refuses a second gadget")
	_check(CommanderProgression.slot_accepts(4, GameCatalog.find_card(&"air_armor")), "wildcard slot takes passive cards")
	_eq(Profile.build_player_stats().gadget_type, int(ComponentCard.GadgetType.SMOKE_SCREEN), "equipped gadget reaches the plane stats")


func _test_save_round_trip() -> void:
	Profile.reset_to_new_profile(false)
	Profile.save_path = "user://test_profile_round_trip.json"
	Profile.persistence_enabled = true
	Profile.add_coins(123)
	Profile.add_card_copies(&"air_armor", 4)
	Profile.try_upgrade_card(&"engine_merlin")
	var coins: int = Profile.coins
	var xp: int = Profile.commander_xp
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)
	_check(Profile.coins != coins, "reset really reset the profile")
	Profile.persistence_enabled = true
	Profile.load_profile()
	_eq(Profile.coins, coins, "coins survive save/load")
	_eq(Profile.commander_xp, xp, "xp survives save/load")
	_eq(Profile.card_level(&"engine_merlin"), 2, "card level survives save/load")
	_eq(Profile.card_level(&"air_armor"), 3, "unlocked card survives save/load")
	_eq(Profile.card_copies(&"air_armor"), 3, "card copies survive save/load")
	_eq(Profile.loadout[2], &"gad_nitro", "loadout survives save/load")
	Profile.persistence_enabled = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Profile.save_path))
	Profile.save_path = Profile.DEFAULT_SAVE_PATH


func _test_ballistics() -> void:
	# Bullets drop and slow down.
	_check(Ballistics.drop_after(1.0) > 4.0 and Ballistics.drop_after(1.0) < 4.9, "a bullet falls 4-4.9 m in its first second (%.2f m)" % Ballistics.drop_after(1.0))
	var level_shot: Vector3 = Vector3(0.0, 0.0, -420.0)
	for _tick: int in range(60):
		level_shot = Ballistics.step(level_shot, 1.0 / 60.0)
	_check(level_shot.length() < 350.0 and level_shot.length() > 320.0, "drag takes about a fifth of a bullet's speed in a second (%.0f m/s)" % level_shot.length())
	_check(level_shot.y < -8.0, "and gravity has it falling by then (%.1f m/s)" % level_shot.y)

	# The lead solution must agree with how BulletSystem really flies a bullet.
	var shooter: Vector3 = Vector3(0.0, 200.0, 0.0)
	var shooter_velocity: Vector3 = Vector3(0.0, 0.0, -80.0)
	var target: Vector3 = Vector3(120.0, 230.0, -300.0)
	var target_velocity: Vector3 = Vector3(-60.0, 5.0, -40.0)
	var bullet_speed: float = 420.0
	var time: float = Ballistics.intercept_time(shooter, shooter_velocity, target, target_velocity, bullet_speed)
	_check(time > 0.0, "an intercept exists for a crossing target")
	var lead: Vector3 = Ballistics.lead_point(shooter, shooter_velocity, target, target_velocity, bullet_speed)
	_check(lead.y > (target + target_velocity * time).y, "the aim point is above the meeting point, to allow for drop")
	# Fire the way PlaneActor does and step the way BulletSystem does.
	var bullet_position: Vector3 = shooter
	var bullet_velocity: Vector3 = (lead - shooter).normalized() * bullet_speed + shooter_velocity
	var tick: float = 1.0 / 240.0
	var flown: float = 0.0
	while flown < time:
		var slice: float = minf(tick, time - flown)
		bullet_velocity = Ballistics.step(bullet_velocity, slice)
		bullet_position += bullet_velocity * slice
		flown += slice
	var miss: float = bullet_position.distance_to(target + target_velocity * time)
	_check(miss < 0.3, "a bullet aimed at the lead point hits (miss %.3f m)" % miss)
	_check(Ballistics.intercept_time(Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, -100.0), Vector3(0.0, 0.0, -500.0), 420.0) < 0.0,
			"no intercept on a target that outruns the bullet")
	_check(Ballistics.intercept_time(Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, -5000.0), Vector3.ZERO, 420.0) < 0.0,
			"no intercept on a target beyond the bullet's reach")
	_near(Ballistics.angle_off_nose(Vector3.ZERO, Vector3.FORWARD, Vector3(0.0, 0.0, -50.0)), 0.0, "dead ahead is 0 angle off")


func _on_level_up(new_level: int) -> void:
	_level_ups.append(new_level)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _eq(actual: Variant, expected: Variant, message: String) -> void:
	var same: bool = actual == expected
	_check(same, "%s (expected %s, got %s)" % [message, expected, actual])


func _near(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) < 0.0001, "%s (expected %f, got %f)" % [message, expected, actual])
