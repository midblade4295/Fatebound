extends Node
## The one-life sortie, played three times over by a scripted player:
##   1. A Hurricane. Five kills build a bounty, each worth more than the last;
##      the plane comes home damaged and low on fuel, and the pilot pays for
##      repairs, then fuel, out of the bounty, and finally cashes out.
##   2. A Spitfire, not insured. One kill, then the pilot is killed: the
##      bounty is lost and so is the Spitfire.
##   3. A Spitfire bought again, insured this time, and lost again: the
##      premium was paid, and the plane is still theirs.
## The bots are sent home: this is about the rules, not the fighting. Kills
## are handed to the player rather than shot for.
## Prints SORTIE_OK on success.

enum Step { SET_UP, KILLS, COME_HOME, STOPPING, REPAIRING, REFUELLING, BROKE, CASHED, LOSE_UNINSURED, LOSE_INSURED, DONE }

const GOLD_AT_START: int = 1000

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0
var _arena: Node
var _manager: MatchManager5v5
var _hud: Hud
var _player: PlaneActor
var _step: Step = Step.SET_UP
var _step_time: float = 0.0
var _sortie: int = 0
var _gold_before: int = 0
var _bounty_before: int = 0
var _sky_cleared: bool = false
var _serviced: int = 0


func _ready() -> void:
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)
	Profile.gold = GOLD_AT_START
	GameSession.local_player_enabled = true
	GameSession.ground_start = true
	GameSession.bot_skill = 0.0
	_start_sortie()


## A fresh arena, with every bot stood down so that nothing happens to the
## player that the test did not do.
func _start_sortie() -> void:
	if _arena != null:
		remove_child(_arena)
		_arena.queue_free()
	_sortie += 1
	GameSession.match_seed = 20 + _sortie
	_arena = (load(GameSession.SCENE_ARENA) as PackedScene).instantiate()
	add_child(_arena)
	_manager = _arena.get_node("MatchManager") as MatchManager5v5
	_hud = _arena.get_node("HUD") as Hud
	_player = _manager.local_slot().plane
	for slot: PilotSlot in _manager.get_roster():
		if slot.controller is SquadAIController:
			slot.controller.queue_free()
			slot.controller = null
	_sky_cleared = false
	_serviced = 0
	_manager.sky_cleared.connect(func(_team: int) -> void: _sky_cleared = true)
	_player.serviced.connect(func(_plane: PlaneActor) -> void: _serviced += 1)


func _physics_process(delta: float) -> void:
	if _step == Step.DONE or _manager == null:
		return
	_step_time += delta
	if _manager.phase == MatchManager5v5.Phase.COUNTDOWN:
		return
	match _step:
		Step.SET_UP:
			_check(_player.burns_fuel and _player.service_on_order, "the player's engine burns fuel and their ground crew wait to be told")
			_check(_manager.bounty == 0 and _manager.next_kill_value() == 100, "a sortie starts with no bounty; the first kill is worth 100")
			_check(not _manager.can_service(), "parked before take-off there is nothing to repair, refuel or cash out")
			_check(not _manager.insured and Profile.gold == GOLD_AT_START, "a Hurricane needs no insurance and none is charged")
			_gold_before = Profile.gold
			_next(Step.KILLS)
		Step.KILLS:
			_run_kills()
		Step.COME_HOME:
			_come_home()
		Step.STOPPING:
			_player.input.throttle = 0.0
			if _manager.can_service():
				_check_the_menu()
			elif _step_time > 60.0:
				_check(false, "the plane never came to rest at home (speed %.1f, on ground %s)" % [_player.speed, _player.is_on_ground()])
				_finish()
		Step.REPAIRING:
			if _serviced >= 1:
				_check(not _player.needs_repair() and _player.visual.has_piece(PlaneActor.Part.RIGHT_WINGTIP), "the ground crew have mended it, new wingtip and all")
				_check(_player.fuel < 0.5, "but nobody has touched the fuel: that was not ordered (%.0f%%)" % (_player.fuel * 100.0))
				_check(_manager.can_service(), "the menu is still there")
				_check(not _manager.buy_service(true, false), "there is nothing more to repair, so nothing more to pay for")
				_bounty_before = _manager.bounty
				var fuel_cost: int = _manager.service_cost(false, true)
				_check(fuel_cost == _player.refuel_cost() and fuel_cost > 30 and fuel_cost <= PlaneActor.REFUEL_PRICE, "filling a tank that is 40%% full costs %d gold" % fuel_cost)
				_check(_manager.buy_service(false, true), "fuel can be bought on its own")
				_check(_manager.bounty == _bounty_before - fuel_cost, "for its price")
				_next(Step.REFUELLING)
			elif _step_time > 60.0:
				_check(false, "the repairs never finished")
				_finish()
		Step.REFUELLING:
			if _serviced >= 2:
				_check(is_equal_approx(_player.fuel, 1.0), "the tank is full")
				_check(_player.service_orders == 0, "and the ground crew have nothing left to do")
				_next(Step.BROKE)
			elif _step_time > 30.0:
				_check(false, "the refuelling never finished")
				_finish()
		Step.BROKE:
			_run_broke()
		Step.CASHED:
			_run_cashed()
		Step.LOSE_UNINSURED:
			_run_lost(false)
		Step.LOSE_INSURED:
			_run_lost(true)


# ---------------------------------------------------------------------------
# Sortie 1: kills, the bounty, the landing menu, cashing out
# ---------------------------------------------------------------------------

func _run_kills() -> void:
	var expected: int = 0
	var number: int = 0
	for slot: PilotSlot in _manager.get_roster():
		if slot.team == _player.team:
			continue
		number += 1
		var worth: int = MatchManager5v5.kill_value(number)
		_check(_manager.next_kill_value() == worth, "kill %d is worth %d" % [number, worth])
		slot.plane._die(_player)
		expected += worth
		_check(_manager.bounty == expected, "and the bounty is now %d (got %d)" % [expected, _manager.bounty])
		_check(slot.out and not slot.plane.alive, "the pilot it was taken from is out of the battle")
	_check(expected == 870, "five kills come to 870 gold")
	_check(_manager.local_slot().kills == 5 and _manager.pilots_left(Teams.opponent_of(_player.team)) == 0, "all five of the enemy are down")
	_check(_sky_cleared, "the sky is announced clear")
	_check(_manager.phase == MatchManager5v5.Phase.ACTIVE and _manager.outcome == MatchManager5v5.Outcome.FLYING, "but the sortie is not over: the bounty still has to be got home")
	_check(Profile.gold == _gold_before, "and none of it is the pilot's yet (gold %d)" % Profile.gold)
	# A friend lost on the way is no kill of anyone's.
	var friend: PlaneActor = null
	for slot: PilotSlot in _manager.get_roster():
		if slot.team == _player.team and not slot.is_local and friend == null:
			friend = slot.plane
	friend._die(null)
	_check(_manager.bounty == expected and _manager.pilots_left(_player.team) == 4, "a team-mate who crashes changes nobody's bounty")
	_next(Step.COME_HOME)


## Shot up and short of fuel, the plane is put on a short approach to its
## own runway, wheels down.
func _come_home() -> void:
	var field: Airfield = _player.home_airfield()
	var direction: Vector3 = field.takeoff_direction()
	# (A plane that has not yet left the ground cannot be hurt; this one has.)
	_player._spawn_shield = 0.0
	_player.apply_damage(100000.0, null, PlaneActor.Part.RIGHT_WINGTIP)
	_player.apply_damage(_player.stats.max_hp * PlaneActor.PART_STRENGTH[PlaneActor.Part.FUSELAGE] * 0.3, null, PlaneActor.Part.FUSELAGE)
	_player.set_engine_running(true)
	_player.set_gear_down(true)
	_player.input.throttle = 0.0
	_player.throttle = 0.0
	_player.speed = _player.stats.landing_stall_speed * 1.15
	_player.teleport(Transform3D(Basis.looking_at(direction, Vector3.UP) * Basis.from_euler(Vector3(deg_to_rad(8.0), 0.0, 0.0)), field.runway_start() + direction * 250.0 + Vector3.UP * 12.0))
	_player.global_position.y -= _player.height_above_ground() - 0.6
	_player.throw(direction * _player.speed + Vector3.DOWN * 1.5)
	_player.fuel = 0.4
	_check(not _manager.can_service(), "in the air there is no menu")
	_next(Step.STOPPING)


func _check_the_menu() -> void:
	_check(_player.alive and _player.is_parked_at_home(), "stopped on its own airfield")
	var panel: Control = _hud.get_node("Root/ServicePanel") as Control
	_hud._process(0.0)
	_check(panel.visible, "the landing menu comes up")
	var repair: int = _manager.service_cost(true, false)
	var refuel: int = _manager.service_cost(false, true)
	_check(repair > PlaneActor.REPAIR_PRICE_PER_JOB and refuel > 0, "there is a price for repairs (%d) and one for fuel (%d)" % [repair, refuel])
	_check(_manager.service_cost(true, true) == repair + refuel, "and both together cost both")
	var repair_button: Button = panel.find_child("RepairButton", true, false) as Button
	var both_button: Button = panel.find_child("BothButton", true, false) as Button
	var cash_button: Button = panel.find_child("CashOutButton", true, false) as Button
	_check(repair_button.text.contains(str(repair)) and both_button.text.contains(str(repair + refuel)), "the buttons say what each costs")
	_check(cash_button.text.contains(str(_manager.bounty)), "and what cashing out would bank (%d)" % _manager.bounty)
	# Repairs first, on their own: paid for out of the bounty.
	_bounty_before = _manager.bounty
	_gold_before = Profile.gold
	repair_button.pressed.emit()
	_check(_manager.bounty == _bounty_before - repair and Profile.gold == _gold_before, "REPAIR takes its price out of the bounty and leaves the pilot's own gold alone")
	_check(_player.service_orders == PlaneActor.SERVICE_REPAIR, "and the ground crew have their orders: repairs, not fuel")
	_check(not _manager.buy_service(true, false) and _manager.bounty == _bounty_before - repair, "it cannot be paid for twice")
	_check(_manager.service_spent == repair, "the bill is kept (%d)" % _manager.service_spent)
	_next(Step.REPAIRING)


## A bill that cannot be met is not run up.
func _run_broke() -> void:
	_player.apply_damage(_player.stats.max_hp * PlaneActor.PART_STRENGTH[PlaneActor.Part.TAIL] * 0.5, null, PlaneActor.Part.TAIL)
	var kept_bounty: int = _manager.bounty
	var kept_gold: int = Profile.gold
	_manager.bounty = 3
	Profile.gold = 1
	_check(_manager.funds() == 4 and _manager.service_cost(true, false) > 4, "with 4 gold in all, a repair costing %d is out of reach" % _manager.service_cost(true, false))
	_check(not _manager.buy_service(true, false) and _manager.bounty == 3 and Profile.gold == 1 and _player.service_orders == 0, "so it is not done and nothing is charged")
	# With no bounty left to pay from, the pilot's own gold pays.
	Profile.gold = 500
	_manager.bounty = 10
	var cost: int = _manager.service_cost(true, false)
	_check(_manager.buy_service(true, false) and _manager.bounty == 0 and Profile.gold == 500 - (cost - 10), "when the bounty runs out the rest comes from the pilot's own gold")
	_manager.bounty = kept_bounty
	Profile.gold = kept_gold
	_gold_before = Profile.gold
	_bounty_before = _manager.bounty
	_check((_hud.get_node("Root/ServicePanel") as Control).find_child("CashOutButton", true, false) != null, "CASH OUT is on the menu")
	((_hud.get_node("Root/ServicePanel") as Control).find_child("CashOutButton", true, false) as Button).pressed.emit()
	_next(Step.CASHED)


func _run_cashed() -> void:
	_check(_manager.outcome == MatchManager5v5.Outcome.HOME and _manager.phase == MatchManager5v5.Phase.FINISHED, "cashing out ends the sortie, home")
	_check(Profile.gold == _gold_before + _bounty_before and _manager.final_bounty == _bounty_before, "and banks the bounty: %d gold" % _bounty_before)
	_check(_manager.bounty == 0 and not _manager.can_service() and not _manager.cash_out(), "once, not twice")
	_check((_hud.get_node("%ResultTitle") as Label).text == "HOME SAFE", "the screen says HOME SAFE")
	_check((_hud.get_node("%RewardLabel") as Label).text.contains("+%d" % _bounty_before), "and what was banked")
	# Next: a Spitfire, uninsured.
	Profile.gold = 5000
	_check(Profile.try_buy_plane(&"spitfire"), "the pilot buys a Spitfire")
	Profile.equip_card(2, &"gun_browning_303") if Profile.try_buy_card(&"gun_browning_303") else null
	Profile.set_insure_sorties(false)
	_gold_before = Profile.gold
	_start_sortie()
	_next(Step.LOSE_UNINSURED)


# ---------------------------------------------------------------------------
# Sorties 2 and 3: killed, without insurance and with it
# ---------------------------------------------------------------------------

func _run_lost(with_insurance: bool) -> void:
	var spitfire: PlaneData = GameCatalog.find_plane(&"spitfire")
	_check(_player.plane_data == spitfire, "the player is flying the Spitfire")
	if with_insurance:
		_check(_manager.insured and Profile.gold == _gold_before - Profile.insurance_cost(spitfire), "the premium (%d) was paid at take-off" % Profile.insurance_cost(spitfire))
	else:
		_check(not _manager.insured and Profile.gold == _gold_before, "nothing was paid for insurance")
	var gold_in_sortie: int = Profile.gold
	var fitted: Array[StringName] = Profile.loadout.duplicate()
	var guns: int = Profile.card_units(&"gun_browning_303")
	for slot: PilotSlot in _manager.get_roster():
		if slot.team != _player.team:
			slot.plane._die(_player)
			break
	_check(_manager.bounty == 100, "one kill: a bounty of 100")
	_player._die(null)
	_check(_manager.outcome == MatchManager5v5.Outcome.LOST and _manager.phase == MatchManager5v5.Phase.FINISHED, "killed, the sortie is over")
	_check(_manager.bounty == 0 and _manager.final_bounty == 100 and Profile.gold == gold_in_sortie, "the bounty is lost: the pilot leaves with nothing from it")
	_check(Profile.loadout == fitted and Profile.card_units(&"gun_browning_303") == guns, "what was fitted is not at risk")
	_check((_hud.get_node("%ResultTitle") as Label).text == "KILLED", "the screen says KILLED")
	var report: String = (_hud.get_node("%RewardLabel") as Label).text
	if with_insurance:
		_check(not _manager.plane_lost and Profile.owns_plane(&"spitfire"), "insured, the Spitfire is replaced")
		_check(report.contains("insurance"), "and the screen says the insurance paid")
		_finish()
		return
	_check(_manager.plane_lost and not Profile.owns_plane(&"spitfire"), "uninsured, the Spitfire is gone")
	_check(Profile.selected_plane().id == &"hurricane", "and the pilot is back in a Hurricane")
	_check(report.contains(str(spitfire.price)), "the screen says what a new one costs")
	_check(Profile.try_buy_plane(&"spitfire"), "which the pilot pays")
	Profile.set_insure_sorties(true)
	_gold_before = Profile.gold
	_start_sortie()
	_next(Step.LOSE_INSURED)


func _next(step: Step) -> void:
	_step = step
	_step_time = 0.0


func _finish() -> void:
	_step = Step.DONE
	if _failures.is_empty():
		print("%d checks passed" % _checks)
		print("SORTIE_OK")
	else:
		for failure: String in _failures:
			print("FAIL: " + failure)
		print("SORTIE_FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
