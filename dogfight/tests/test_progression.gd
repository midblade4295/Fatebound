extends Node
## Headless unit test for the items (weapons and components), what fitting
## them does to the plane and to its model, the Commander Level rules and the
## gunnery maths.
##
##   godot --headless --path . res://tests/TestProgression.tscn
##
## Prints PROGRESSION_OK on success.

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)
	_test_mounts_and_prices()
	_test_card_tables()
	_test_stat_building()
	_test_profile_upgrade_flow()
	_test_loadout_rules()
	_test_model_shows_fittings()
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


func _test_mounts_and_prices() -> void:
	# There are no levels: every mount is open, and what you have is what you bought.
	_eq(PlaneMounts.MOUNT_COUNT, 9, "nine mounts: four gun stations and five components")
	_check(PlaneMounts.is_gun_station(0) and PlaneMounts.is_gun_station(3) and not PlaneMounts.is_gun_station(4), "the first four mounts are the gun stations")
	_check(PlaneMounts.mount_accepts(2, GameCatalog.find_card(&"gun_hispano_20mm")), "an outer station takes a gun")
	_check(not PlaneMounts.mount_accepts(4, GameCatalog.find_card(&"gun_hispano_20mm")), "the propeller mount does not")
	var hurricane: PlaneData = GameCatalog.find_plane(&"hurricane")
	var spitfire: PlaneData = GameCatalog.find_plane(&"spitfire")
	var mustang: PlaneData = GameCatalog.find_plane(&"mustang")
	_check(hurricane.is_free(), "the Hurricane is issued free")
	_check(spitfire.price > 0 and mustang.price > spitfire.price, "the Spitfire has a price and the Mustang a higher one (%d, %d)" % [spitfire.price, mustang.price])
	_eq(GameCatalog.plane_rank(hurricane), 0, "the line-up starts with the Hurricane")
	_check(GameCatalog.plane_near(hurricane, -1) == hurricane and GameCatalog.plane_near(hurricane, 1) == spitfire and GameCatalog.plane_near(mustang, 1) == mustang,
			"bots fly the player's plane or the one either side of it")
	_eq(MatchManager5v5.kill_value(1), 100, "a first kill is worth 100 gold")
	_check(MatchManager5v5.kill_value(2) > MatchManager5v5.kill_value(1) and MatchManager5v5.kill_value(5) > MatchManager5v5.kill_value(4) and MatchManager5v5.kill_value(5) == 300,
			"and every kill after it more than the last, up to 300 for the fifth")
	_eq(MatchManager5v5.kill_value(9), MatchManager5v5.kill_value(5), "after which they stay at that")


func _test_card_tables() -> void:
	var browning: ComponentCard = GameCatalog.find_card(&"gun_browning_303")
	var fifty: ComponentCard = GameCatalog.find_card(&"gun_browning_m2")
	var hispano: ComponentCard = GameCatalog.find_card(&"gun_hispano_20mm")
	var four_blade: ComponentCard = GameCatalog.find_card(&"prop_four_blade")
	_eq(browning.max_units(), 4, "up to four of a gun can be fitted")
	_eq(four_blade.max_units(), 1, "one propeller")
	_check(browning.is_optional() and not four_blade.is_optional(), "a plane can fly with no guns but not with no propeller")
	_eq(browning.price(), 150, "a common item costs 150 gold")
	_check(fifty.price() > browning.price() and hispano.price() > fifty.price(), "rarer ones cost more (%d, %d)" % [fifty.price(), hispano.price()])
	_eq(browning.upgrade_cost(1), 60, "Mk I -> II of a common item costs 60")
	_eq(fifty.upgrade_cost(1), 120, "and twice that for a rare one")
	_eq(browning.upgrade_cost(ComponentCard.MAX_MARK), 0, "the top Mark costs nothing more")
	_check(not browning.can_upgrade(ComponentCard.MAX_MARK, 999999), "and cannot be upgraded")
	_check(browning.can_upgrade(1, 60), "an affordable upgrade is allowed")
	_check(not browning.can_upgrade(1, 59), "upgrade blocked without the gold")
	_near(browning.mark_multiplier(1), 1.0, "Mk I multiplier")
	_near(browning.mark_multiplier(ComponentCard.MAX_MARK), 1.16, "Mk V is 16% better: modest, not a different class of weapon")
	_near(browning.damage_at(3), browning.damage * 1.08, "a gun's damage grows with its Mark")
	_check(four_blade.scaled(four_blade.acceleration_bonus, 5) > four_blade.acceleration_bonus, "a Mark improves what an item is good at")
	_near(four_blade.scaled(four_blade.top_speed_bonus, 5), four_blade.top_speed_bonus, "and leaves its drawback as it was")
	_check(four_blade.top_speed_bonus < 0.0, "the four-blade propeller really does cost top speed")
	_check(hispano.weight > fifty.weight and fifty.weight > browning.weight, "heavier guns weigh more")
	_check(hispano.damage > fifty.damage and fifty.damage > browning.damage, "and hit harder")
	_check(browning.fire_rate > fifty.fire_rate and fifty.fire_rate > hispano.fire_rate, "and fire more slowly")
	var ids: Dictionary[StringName, bool] = {}
	var variants: Dictionary[StringName, bool] = {}
	for card: ComponentCard in GameCatalog.CARDS:
		_check(card.id != &"" and not ids.has(card.id), "item id '%s' is unique and set" % card.id)
		ids[card.id] = true
		_check(not card.stat_lines(1).is_empty(), "item '%s' describes what it does" % card.id)
		_check(card.model_variant != &"" and not variants.has(card.model_variant), "item '%s' has its own look on the model" % card.id)
		variants[card.model_variant] = true
		if card.is_gun():
			_check(card.fire_rate > 0.0 and card.damage > 0.0 and card.muzzle_speed > 0.0 and card.gun_range > 0.0, "gun '%s' has its numbers" % card.id)
			_check(card.gun_sounds.size() >= 3, "gun '%s' has its own sounds" % card.id)
	for stock_id: StringName in GameCatalog.STOCK_FITTING_IDS:
		_check(stock_id == &"" or GameCatalog.find_card(stock_id) != null, "stock fitting '%s' exists" % stock_id)


func _test_stat_building() -> void:
	var plane: PlaneData = GameCatalog.find_plane(&"hurricane")
	var browning: ComponentCard = GameCatalog.find_card(&"gun_browning_303")
	var hispano: ComponentCard = GameCatalog.find_card(&"gun_hispano_20mm")
	var base: PlaneStats = plane.build_base_stats()
	_near(base.max_hp, 1000.0, "base toughness")
	_eq(base.gun_count(), 0, "the bare aeroplane has no guns")
	_near(base.fire_rate, 0.0, "so it cannot fire")
	# As it leaves the factory: two .303s.
	var stock: PlaneStats = plane.build_stock_stats()
	_eq(stock.gun_count(), 2, "a stock plane has two guns")
	_near(stock.fire_rate, browning.fire_rate * 2.0, "firing at twice one gun's rate")
	_near(stock.bullet_damage, browning.damage, "each round a .303 round")
	_near(stock.weight, 1.0 + browning.weight * 2.0, "and carries their weight")
	_near(stock.stall_speed, base.stall_speed * sqrt(stock.weight), "which raises the stalling speed a little")
	_check(stock.mass > base.mass and stock.climb_rate < base.climb_rate, "and takes a little off the climb (%.2f against %.2f m/s)" % [stock.climb_rate, base.climb_rate])
	_check(stock.wing_loading() > base.wing_loading(), "and loads the wing more, which is what turning is paid for with")
	# The figures are the real aeroplane's, and what it can do comes from flying it.
	_near(base.mass, plane.base_mass, "the bare aeroplane weighs what the real one did")
	_check(base.top_speed * PlaneActor.MPH > 273.0 and base.top_speed * PlaneActor.MPH < 295.0, "a Hurricane's top speed at sea level is a real one (%.0f mph)" % (base.top_speed * PlaneActor.MPH))
	_check(base.top_speed_high * PlaneActor.MPH > 332.0 and base.top_speed_high * PlaneActor.MPH < 350.0, "and at 21,000 ft, where it is fastest, it does the real 340 mph (%.0f)" % (base.top_speed_high * PlaneActor.MPH))
	var mustang_stats: PlaneStats = GameCatalog.find_plane(&"mustang").build_base_stats()
	_check(mustang_stats.top_speed * PlaneActor.MPH > 365.0 and mustang_stats.top_speed * PlaneActor.MPH < 390.0 and mustang_stats.top_speed_high * PlaneActor.MPH > 428.0 and mustang_stats.top_speed_high * PlaneActor.MPH < 447.0,
			"a Mustang does the real 375 mph at sea level and 437 mph at 25,000 ft (%.0f and %.0f)" % [mustang_stats.top_speed * PlaneActor.MPH, mustang_stats.top_speed_high * PlaneActor.MPH])
	_check(base.stall_speed * 3.6 > 115.0 and base.stall_speed * 3.6 < 160.0, "and so is its stalling speed (%.0f km/h)" % (base.stall_speed * 3.6))
	var spitfire: PlaneStats = GameCatalog.find_plane(&"spitfire").build_base_stats()
	var mustang: PlaneStats = GameCatalog.find_plane(&"mustang").build_base_stats()
	_check(mustang.top_speed > spitfire.top_speed and spitfire.top_speed > base.top_speed, "Mustang, Spitfire, Hurricane: fastest to slowest (%.0f, %.0f, %.0f m/s)" % [mustang.top_speed, spitfire.top_speed, base.top_speed])
	_check(spitfire.climb_rate > mustang.climb_rate and spitfire.climb_rate > base.climb_rate, "the Spitfire climbs best (%.1f against %.1f and %.1f m/s)" % [spitfire.climb_rate, mustang.climb_rate, base.climb_rate])
	_check(mustang.wing_loading() > spitfire.wing_loading() * 1.2 and mustang.stall_speed > spitfire.stall_speed * 1.1, "the heavy Mustang lands fastest and turns widest")
	# One gun fitted is one gun.
	var one_gun: Array[ComponentCard] = GameCatalog.stock_fittings()
	one_gun[1] = null
	var single: PlaneStats = plane.build_stats(one_gun, GameCatalog.stock_marks())
	_eq(single.gun_count(), 1, "one gun fitted is one gun")
	_check(single.gun_at(0) == browning and single.gun_at(1) == null, "in the station it was fitted to")
	_near(single.fire_rate, browning.fire_rate, "firing at one gun's rate")
	# Four cannon: only once the outer stations are open, and they are heavy.
	var cannon: Array[ComponentCard] = GameCatalog.stock_fittings()
	for station: int in range(PlaneMounts.GUN_STATION_COUNT):
		cannon[station] = hispano
	var four_cannon: PlaneStats = plane.build_stats(cannon, GameCatalog.stock_marks())
	var stock_at_3: PlaneStats = plane.build_stock_stats()
	_eq(four_cannon.gun_count(), 4, "four cannon fitted is four cannon")
	_near(four_cannon.weight, 1.0 + hispano.weight * 4.0, "weigh four cannon")
	_check(four_cannon.fire_rate * four_cannon.bullet_damage > stock_at_3.fire_rate * stock_at_3.bullet_damage * 2.5, "and hit far harder than two .303s")
	_check(four_cannon.stall_speed > stock_at_3.stall_speed * 1.04, "but need more speed to take off (%.1f vs %.1f m/s)" % [four_cannon.stall_speed, stock_at_3.stall_speed])
	_check(four_cannon.power_loading() < stock_at_3.power_loading() * 0.92 and four_cannon.climb_rate < stock_at_3.climb_rate * 0.93, "and climb worse (%.1f against %.1f m/s)" % [four_cannon.climb_rate, stock_at_3.climb_rate])
	# Marks.
	var marks: Array[int] = GameCatalog.stock_marks()
	marks[0] = 5
	marks[1] = 5
	_near(plane.build_stats(GameCatalog.stock_fittings(), marks).bullet_damage, browning.damage * 1.16, "Mk V guns do 16% more damage")
	# Components.
	var fitted: Array[ComponentCard] = GameCatalog.stock_fittings()
	fitted[PlaneMounts.mount_for_slot(ComponentCard.Slot.ENGINE)] = GameCatalog.find_card(&"engine_merlin_61")
	var faster: PlaneStats = plane.build_stats(fitted, GameCatalog.stock_marks())
	_check(faster.top_speed > stock.top_speed * 1.04, "a better engine raises top speed")
	_check(absf(faster.stall_speed - stock.stall_speed * sqrt(faster.weight / stock.weight)) < 0.1, "without raising the stalling speed by more than its weight does (%.2f against %.2f m/s)" % [faster.stall_speed, stock.stall_speed])
	fitted = GameCatalog.stock_fittings()
	fitted[PlaneMounts.mount_for_slot(ComponentCard.Slot.WINGTIPS)] = GameCatalog.find_card(&"tips_clipped")
	var clipped: PlaneStats = plane.build_stats(fitted, GameCatalog.stock_marks())
	_check(clipped.roll_power > stock.roll_power * 1.1 and clipped.stall_speed > stock.stall_speed * 1.02, "clipped wings roll faster and stall sooner")
	_check(clipped.wing_span < stock.wing_span and clipped.top_speed > stock.top_speed, "being shorter in the span, and a little faster for it")
	fitted[PlaneMounts.mount_for_slot(ComponentCard.Slot.WINGTIPS)] = GameCatalog.find_card(&"tips_extended")
	_check(plane.build_stats(fitted, GameCatalog.stock_marks()).stall_speed < stock.stall_speed * 0.98, "extended wings stall later")
	fitted = GameCatalog.stock_fittings()
	fitted[PlaneMounts.mount_for_slot(ComponentCard.Slot.ARMOUR)] = GameCatalog.find_card(&"armour_full")
	var armoured: PlaneStats = plane.build_stats(fitted, GameCatalog.stock_marks())
	_check(armoured.max_hp > base.max_hp * 1.2 and armoured.fuel_leak < 0.6, "armour toughens the plane and slows fuel leaks")
	fitted = GameCatalog.stock_fittings()
	fitted[PlaneMounts.mount_for_slot(ComponentCard.Slot.UNDERCARRIAGE)] = GameCatalog.find_card(&"gear_reinforced")
	_near(plane.build_stats(fitted, GameCatalog.stock_marks()).gear_strength, 1.35, "reinforced undercarriage is 35% stronger")
	# An item in the wrong kind of mount is left off.
	fitted = GameCatalog.stock_fittings()
	fitted[PlaneMounts.mount_for_slot(ComponentCard.Slot.PROPELLER)] = browning
	_check(plane.build_stats(fitted, GameCatalog.stock_marks()).fitting_in(ComponentCard.Slot.PROPELLER) == null, "a gun in the propeller mount is not fitted")
	_eq(stock.fitting_ids().size(), PlaneMounts.MOUNT_COUNT, "the fittings can be listed by id for other peers")
	_eq(stock.fitting_ids()[0], "gun_browning_303", "in mount order")


func _test_profile_upgrade_flow() -> void:
	Profile.reset_to_new_profile(false)
	_eq(Profile.gold, Profile.STARTING_GOLD, "a new pilot's gold")
	_eq(Profile.card_units(&"gun_browning_303"), 2, "a new pilot has two .303s")
	_eq(Profile.card_mark(&"gun_browning_303"), 1, "at Mk I")
	_check(Profile.owns_card(&"prop_three_blade") and Profile.owns_card(&"gear_standard"), "and the standard parts")
	_check(not Profile.owns_card(&"gun_hispano_20mm") and Profile.card_mark(&"gun_hispano_20mm") == 0, "but no cannon")
	_check(Profile.owns_plane(&"hurricane") and not Profile.owns_plane(&"spitfire"), "and a Hurricane, but no Spitfire")

	# Components are bought, one at a time.
	var browning: ComponentCard = GameCatalog.find_card(&"gun_browning_303")
	_check(Profile.try_buy_card(&"gun_browning_303"), "a third .303 can be bought")
	_eq(Profile.gold, Profile.STARTING_GOLD - browning.price(), "for its price")
	_eq(Profile.card_units(&"gun_browning_303"), 3, "and is one more gun to fit")
	_check(Profile.try_buy_card(&"gun_browning_303"), "and a fourth")
	_check(not Profile.try_buy_card(&"gun_browning_303") and Profile.card_units(&"gun_browning_303") == 4, "but not a fifth: there are only four stations")
	var gold: int = Profile.gold
	_check(not Profile.try_buy_card(&"gun_hispano_20mm") and Profile.gold == gold, "a cannon that cannot be afforded is not bought, and nothing is spent")
	Profile.add_gold(100000)
	gold = Profile.gold
	_check(Profile.try_buy_card(&"gun_hispano_20mm") and Profile.card_units(&"gun_hispano_20mm") == 1, "with the gold, one cannon bought is one cannon")
	_eq(Profile.gold, gold - GameCatalog.find_card(&"gun_hispano_20mm").price(), "paid for")
	_check(Profile.try_buy_card(&"prop_four_blade") and not Profile.try_buy_card(&"prop_four_blade"), "only one propeller can be owned: only one can be fitted")

	# Upgrades cost gold and nothing else.
	gold = Profile.gold
	_check(Profile.try_upgrade_card(&"gun_browning_303"), "an upgrade succeeds")
	_eq(Profile.gold, gold - 60, "for 60 gold")
	_eq(Profile.card_units(&"gun_browning_303"), 4, "and none of the guns themselves")
	_eq(Profile.card_mark(&"gun_browning_303"), 2, "the .303 is now Mk II")
	_check(not Profile.try_upgrade_card(&"engine_griffon_65"), "an item that is not owned cannot be upgraded")
	var before: float = Profile.build_player_stats().bullet_damage
	_check(Profile.try_upgrade_card(&"gun_browning_303"), "another Mark for the fitted guns")
	_check(Profile.build_player_stats().bullet_damage > before, "upgrading the fitted guns makes them hit harder")
	Profile.gold = 10
	_check(not Profile.try_upgrade_card(&"gun_browning_303") and Profile.gold == 10, "an upgrade that cannot be afforded spends nothing")

	# Planes are bought too.
	var spitfire: PlaneData = GameCatalog.find_plane(&"spitfire")
	_check(not Profile.select_plane(&"spitfire"), "a plane that is not owned cannot be selected")
	_check(not Profile.try_buy_plane(&"spitfire"), "or bought without the gold")
	Profile.gold = spitfire.price + 400
	_check(Profile.try_buy_plane(&"spitfire"), "with the gold it can")
	_eq(Profile.gold, 400, "for its price")
	_check(Profile.owns_plane(&"spitfire") and Profile.selected_plane() == spitfire, "and it is the pilot's plane now")
	_check(not Profile.try_buy_plane(&"spitfire"), "it cannot be bought twice")
	_check(Profile.select_plane(&"hurricane") and Profile.select_plane(&"spitfire"), "and the pilot can go between the two")

	# Insurance: a share of the plane's price, paid at the start of a sortie.
	_eq(Profile.insurance_cost(GameCatalog.find_plane(&"hurricane")), 0, "a free plane needs no insurance")
	_eq(Profile.insurance_cost(spitfire), ceili(float(spitfire.price) * Profile.INSURANCE_RATE), "a Spitfire's is 15% of its price")
	_check(not Profile.pay_insurance() and Profile.gold == 400, "nothing is charged unless the pilot has asked for it")
	Profile.set_insure_sorties(true)
	_check(Profile.pay_insurance(), "asked for, the premium is paid")
	_eq(Profile.gold, 400 - Profile.insurance_cost(spitfire), "out of the pilot's gold")
	Profile.gold = 5
	_check(not Profile.pay_insurance() and Profile.gold == 5, "a pilot who cannot pay it flies uninsured")

	# Losing a plane: it has to be bought again; what was fitted is kept.
	var fitted_before: Array[StringName] = Profile.loadout.duplicate()
	var cannon_before: int = Profile.card_units(&"gun_hispano_20mm")
	_check(Profile.lose_plane(&"spitfire"), "a Spitfire that does not come back is lost")
	_check(not Profile.owns_plane(&"spitfire") and Profile.selected_plane().id == &"hurricane", "and the pilot is back in a Hurricane")
	_check(Profile.loadout == fitted_before and Profile.card_units(&"gun_hispano_20mm") == cannon_before, "with everything that was fitted, and everything owned")
	_check(not Profile.lose_plane(&"hurricane") and Profile.owns_plane(&"hurricane"), "a Hurricane is never lost for good: another is issued")
	Profile.gold = spitfire.price
	_check(Profile.try_buy_plane(&"spitfire") and Profile.gold == 0, "the Spitfire can be bought again, at full price")
	Profile.bank_bounty(370)
	_eq(Profile.gold, 370, "a bounty banked is gold in hand")


func _test_loadout_rules() -> void:
	Profile.reset_to_new_profile(false)
	var propeller_mount: int = PlaneMounts.mount_for_slot(ComponentCard.Slot.PROPELLER)
	var armour_mount: int = PlaneMounts.mount_for_slot(ComponentCard.Slot.ARMOUR)
	_eq(Profile.loadout[0], &"gun_browning_303", "a .303 in the left inner station")
	_eq(Profile.loadout[1], &"gun_browning_303", "and one in the right inner station")
	_eq(Profile.loadout[2], &"", "the outer stations are empty")
	_eq(Profile.loadout[propeller_mount], &"prop_three_blade", "the standard propeller is fitted")
	_eq(Profile.loadout[armour_mount], &"", "no armour")
	_eq(Profile.fitted_count(&"gun_browning_303"), 2, "two .303s fitted")
	Profile.add_card_units(&"armour_seat", 1)
	Profile.add_card_units(&"gun_browning_303", 1)
	# Taking a gun off: one gun fitted is one gun.
	_check(Profile.unequip_mount(1), "a gun can be taken off")
	_eq(Profile.build_player_stats().gun_count(), 1, "with one gun fitted the plane has one gun")
	_check(not Profile.unequip_mount(1), "an empty station has nothing to take off")
	_check(not Profile.unequip_mount(propeller_mount), "the propeller cannot be taken off, only swapped")
	_check(Profile.equip_card(1, &"gun_browning_303"), "and the gun can go back on")
	_check(Profile.equip_card(2, &"gun_browning_303"), "a third .303 goes in an outer station")
	_check(not Profile.equip_card(3, &"gun_browning_303"), "there is no fourth to fit: every unit is on the plane")
	_eq(Profile.find_mount_for(GameCatalog.find_card(&"gun_browning_303")), -1, "so there is nowhere to fit another")
	_check(not Profile.equip_card(propeller_mount, &"gun_browning_303"), "a gun does not go in the propeller mount")
	_check(not Profile.equip_card(3, &"gun_hispano_20mm"), "an item that is not owned cannot be fitted")
	Profile.add_card_units(&"gun_hispano_20mm", 1)
	_eq(Profile.find_mount_for(GameCatalog.find_card(&"gun_hispano_20mm")), 3, "a new gun goes to the empty station")
	_check(Profile.equip_card(3, &"gun_hispano_20mm"), "one cannon alongside three machine guns")
	var mixed: PlaneStats = Profile.build_player_stats()
	_eq(mixed.gun_count(), 4, "four guns fitted")
	_check(mixed.gun_at(3) == GameCatalog.find_card(&"gun_hispano_20mm") and mixed.gun_at(0) == GameCatalog.find_card(&"gun_browning_303"), "each station fires what is in it")
	Profile.add_card_units(&"prop_four_blade", 1)
	_eq(Profile.find_mount_for(GameCatalog.find_card(&"prop_four_blade")), propeller_mount, "a new propeller replaces the old one")
	var before: PlaneStats = Profile.build_player_stats()
	_check(Profile.equip_card(propeller_mount, &"prop_four_blade"), "the four-blade propeller is fitted")
	var after: PlaneStats = Profile.build_player_stats()
	_check(after.static_thrust > before.static_thrust and after.top_speed < before.top_speed, "it trades top speed for pull at low speed")
	_check(Profile.equip_card(armour_mount, &"armour_seat"), "armour can be fitted")
	_check(Profile.build_player_stats().max_hp > after.max_hp, "and toughens the plane")
	_check(Profile.unequip_mount(armour_mount), "and taken off again")


func _test_model_shows_fittings() -> void:
	var plane: PlaneData = GameCatalog.find_plane(&"hurricane")
	var visual: PlaneVisual = PlaneVisual.new()
	add_child(visual)
	# Stock: two guns, three-blade propeller, nothing extra.
	visual.build(plane, Teams.Id.TEAM_BLUE, GameCatalog.stock_fittings())
	_check(visual.has_gun_at(0) and visual.has_gun_at(1), "the stock model shows its two inner guns")
	_check(not visual.has_gun_at(2) and not visual.has_gun_at(3), "and no outer guns")
	_eq(_gun_pieces(visual), 2, "exactly two gun pieces are on the model")
	_eq(visual.propeller_piece_name(), &"PropellerMesh", "three-blade propeller")
	for piece: StringName in [&"PropellerMesh4", &"EngineIntake", &"EngineBulges", &"ArmourSeat", &"ArmourScreen", &"WingTipExtL", &"GunL1_20", &"GearL_heavy", &"WingTipL_clipped"]:
		_check(not visual.has_model_piece(piece), "stock model has no %s" % piece)
	var stock_wheel: float = visual.undercarriage_contacts()[0].y
	var stock_span: float = _wing_half_span(visual)
	var stock_muzzle: Vector3 = visual.gun_muzzles()[0]
	# One gun fitted: one gun shown.
	var one_gun: Array[ComponentCard] = GameCatalog.stock_fittings()
	one_gun[1] = null
	visual.build(plane, Teams.Id.TEAM_BLUE, one_gun)
	_check(visual.has_gun_at(0) and not visual.has_gun_at(1), "fit one gun and the model shows one gun")
	_eq(_gun_pieces(visual), 1, "one gun piece on the model")
	_near(visual.gun_muzzles()[1].length(), 0.0, "an empty station has no muzzle")
	# No guns at all.
	var unarmed: Array[ComponentCard] = GameCatalog.stock_fittings()
	unarmed[0] = null
	unarmed[1] = null
	visual.build(plane, Teams.Id.TEAM_BLUE, unarmed)
	_eq(_gun_pieces(visual), 0, "fit no guns and the model shows none")
	# Everything different.
	var full: Array[ComponentCard] = [
		GameCatalog.find_card(&"gun_hispano_20mm"), GameCatalog.find_card(&"gun_browning_m2"),
		GameCatalog.find_card(&"gun_browning_303"), GameCatalog.find_card(&"gun_hispano_20mm"),
		GameCatalog.find_card(&"prop_four_blade"), GameCatalog.find_card(&"engine_griffon_65"),
		GameCatalog.find_card(&"tips_extended"), GameCatalog.find_card(&"armour_full"), GameCatalog.find_card(&"gear_reinforced"),
	]
	visual.build(plane, Teams.Id.TEAM_BLUE, full)
	_eq(_gun_pieces(visual), 4, "four guns fitted, four shown")
	for piece: StringName in [&"GunL1_20", &"GunR1_50", &"GunL2_303", &"GunR2_20"]:
		_check(visual.has_model_piece(piece), "each station shows the kind of gun fitted there (%s)" % piece)
	_check(not visual.has_model_piece(&"GunL1_303") and not visual.has_model_piece(&"GunR1_20"), "and not the kinds that are not")
	_eq(visual.propeller_piece_name(), &"PropellerMesh4", "four-blade propeller")
	for piece: StringName in [&"EngineIntake", &"EngineBulges", &"ArmourSeat", &"ArmourScreen", &"WingTipExtL", &"WingTipExtR"]:
		_check(visual.has_model_piece(piece), "the fitted %s is on the model" % piece)
	var muzzles: Array[Vector3] = visual.gun_muzzles()
	_check(muzzles[0].x < 0.0 and muzzles[2].x < muzzles[0].x and muzzles[1].x > 0.0 and muzzles[3].x > muzzles[1].x, "muzzles are where the guns are: left and right, inner and outer")
	_check(muzzles[0].z < stock_muzzle.z - 0.3, "a cannon's barrel reaches further forward than a .303's (%.2f vs %.2f)" % [muzzles[0].z, stock_muzzle.z])
	_check(visual.undercarriage_contacts()[0].y < stock_wheel - 0.05, "the reinforced undercarriage has bigger wheels")
	_check(_wing_half_span(visual) > stock_span + 0.3, "extended tips make the wing longer to hit (%.2f vs %.2f)" % [_wing_half_span(visual), stock_span])
	# Clipped wings.
	var clipped: Array[ComponentCard] = GameCatalog.stock_fittings()
	clipped[PlaneMounts.mount_for_slot(ComponentCard.Slot.WINGTIPS)] = GameCatalog.find_card(&"tips_clipped")
	visual.build(plane, Teams.Id.TEAM_BLUE, clipped)
	_check(_wing_half_span(visual) < stock_span - 0.3, "clipped tips make it shorter (%.2f vs %.2f)" % [_wing_half_span(visual), stock_span])
	_check(not visual.has_model_piece(&"WingTipL_clipped"), "the spare tip shape is not left on the model")
	visual.queue_free()


## Number of gun pieces left on a built model.
func _gun_pieces(visual: PlaneVisual) -> int:
	var count: int = 0
	for tag: String in PlaneVisual.GUN_STATION_TAGS:
		for kind: String in PlaneVisual.GUN_KINDS:
			if visual.has_model_piece(StringName("Gun%s_%s" % [tag, kind])):
				count += 1
	return count


## How far out the hit boxes of the right wing reach.
func _wing_half_span(visual: PlaneVisual) -> float:
	var parts: PackedInt32Array = PackedInt32Array()
	var boxes: Array[AABB] = []
	visual.collect_hit_boxes(parts, boxes)
	var reach: float = 0.0
	for box: AABB in boxes:
		reach = maxf(reach, box.end.x)
	return reach


func _test_save_round_trip() -> void:
	Profile.reset_to_new_profile(false)
	Profile.save_path = "user://test_profile_round_trip.json"
	Profile.persistence_enabled = true
	Profile.add_gold(5000)
	Profile.add_card_units(&"gun_hispano_20mm", 2)
	Profile.add_card_units(&"gun_browning_303", 2)
	Profile.try_upgrade_card(&"gun_browning_303")
	Profile.unequip_mount(1)
	Profile.try_buy_plane(&"spitfire")
	Profile.set_insure_sorties(true)
	var gold: int = Profile.gold
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)
	_check(Profile.gold != gold and not Profile.owns_plane(&"spitfire"), "reset really reset the profile")
	Profile.persistence_enabled = true
	Profile.load_profile()
	_eq(Profile.gold, gold, "gold survives save/load")
	_check(Profile.owns_plane(&"spitfire") and Profile.selected_plane().id == &"spitfire", "and the plane that was bought, still selected")
	_check(not Profile.owns_plane(&"mustang"), "but not one that was not")
	_check(Profile.insure_sorties, "and the choice to insure")
	_eq(Profile.card_mark(&"gun_browning_303"), 2, "an item's Mark survives save/load")
	_eq(Profile.card_units(&"gun_browning_303"), 4, "and how many there are")
	_eq(Profile.card_units(&"gun_hispano_20mm"), 2, "a bought item survives save/load")
	_eq(Profile.loadout[0], &"gun_browning_303", "the fitted gun is still fitted")
	_eq(Profile.loadout[1], &"", "the station that was emptied is still empty")
	_eq(Profile.loadout[PlaneMounts.mount_for_slot(ComponentCard.Slot.PROPELLER)], &"prop_three_blade", "the propeller is still on")
	# A save from before any of this (levelled cards, coins, Hangar XP): the
	# coins are gold, a plane the XP had unlocked is kept, and the fittings
	# start from stock rather than failing to load.
	var old_save: Dictionary = {
		"version": 1, "pilot_name": "Old Hand", "coins": 777, "commander_xp": 70,
		"selected_plane_id": "spitfire", "loadout": ["engine_merlin", "arm_brownings", "gad_nitro", "", ""],
		"cards": {"engine_merlin": {"level": 5, "copies": 3}},
	}
	var file: FileAccess = FileAccess.open(Profile.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(old_save))
	file.close()
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)
	Profile.persistence_enabled = true
	Profile.load_profile()
	_eq(Profile.gold, 777, "an old save's coins are gold")
	_check(Profile.owns_plane(&"spitfire") and not Profile.owns_plane(&"mustang"), "the Spitfire its experience had earned is kept, and no more")
	_eq(Profile.selected_plane().id, &"spitfire", "still selected")
	_eq(Profile.card_units(&"gun_browning_303"), 2, "and it starts with the stock guns")
	_eq(Profile.loadout[0], &"gun_browning_303", "fitted")
	_eq(Profile.build_player_stats().gun_count(), 2, "ready to fly")
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

	# Drag is the air's doing: high up, in thinner air, there is less of it.
	var thin: float = Ballistics.air_at(4000.0)
	_check(thin > 0.6 and thin < 0.72, "at 4000 m the air is about two thirds as dense (%.2f)" % thin)
	var high_shot: Vector3 = Vector3(0.0, 0.0, -420.0)
	for _tick: int in range(60):
		high_shot = Ballistics.step(high_shot, 1.0 / 60.0, thin)
	_check(high_shot.length() > level_shot.length() + 15.0, "so a bullet keeps more of its speed up there (%.0f against %.0f m/s after a second)" % [high_shot.length(), level_shot.length()])
	_check(Ballistics.time_to_travel(400.0, 420.0, thin) < Ballistics.time_to_travel(400.0, 420.0) - 0.02, "and gets to 400 m sooner (%.2f against %.2f s)" % [Ballistics.time_to_travel(400.0, 420.0, thin), Ballistics.time_to_travel(400.0, 420.0)])
	var high_time: float = Ballistics.intercept_time(shooter, shooter_velocity, target, target_velocity, bullet_speed, thin)
	var high_lead: Vector3 = Ballistics.lead_point(shooter, shooter_velocity, target, target_velocity, bullet_speed, thin)
	bullet_position = shooter
	bullet_velocity = (high_lead - shooter).normalized() * bullet_speed + shooter_velocity
	flown = 0.0
	while flown < high_time:
		var slice: float = minf(tick, high_time - flown)
		bullet_velocity = Ballistics.step(bullet_velocity, slice, thin)
		bullet_position += bullet_velocity * slice
		flown += slice
	miss = bullet_position.distance_to(target + target_velocity * high_time)
	_check(miss < 0.3, "the lead worked out for thin air hits in thin air (miss %.3f m)" % miss)
	_check(Ballistics.intercept_time(Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, -5000.0), Vector3.ZERO, 420.0) < 0.0,
			"no intercept on a target beyond the bullet's reach")
	_near(Ballistics.angle_off_nose(Vector3.ZERO, Vector3.FORWARD, Vector3(0.0, 0.0, -50.0)), 0.0, "dead ahead is 0 angle off")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _eq(actual: Variant, expected: Variant, message: String) -> void:
	var same: bool = actual == expected
	_check(same, "%s (expected %s, got %s)" % [message, expected, actual])


func _near(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) < 0.0001, "%s (expected %f, got %f)" % [message, expected, actual])
