extends Node
## The game around the battle: a menu, a deck builder, and the battle itself.
##
## The battlefield is built once, at the start, and stays alive behind everything: the menu
## floats over it while it idles, and a battle is the same field with the armies let loose. So
## going from the menu into a fight costs nothing to load.

const Sim = preload("res://scripts/sim/battle_sim.gd")
const Bot = preload("res://scripts/sim/bot.gd")
const Battle = preload("res://scripts/view/battle_screen.gd")
const Menu = preload("res://scripts/app/menu.gd")
const DeckScreen = preload("res://scripts/app/deck_screen.gd")
const Profile = preload("res://scripts/app/profile.gd")
const Kit = preload("res://scripts/view/ui_kit.gd")

var cards: Dictionary
var profile: Profile
var kit: Kit
var battle: Battle
var menu: Menu
var deck_screen: DeckScreen
var match_seed: int = 0           # tests set this for a repeatable first battle
var use_saved_profile: bool = true
var where: String = "menu"        # "menu", "deck" or "battle"


func _ready() -> void:
	get_tree().set_auto_accept_quit(true)
	cards = Sim.load_cards()
	kit = Kit.new()
	profile = Profile.new()
	if use_saved_profile and DisplayServer.get_name() != "headless":
		profile.load_from_disk(cards)
	else:
		profile.persist = false
	battle = Battle.new()
	battle.hosted = true
	battle.backdrop = true
	battle.match_seed = match_seed
	battle.deck = profile.deck.duplicate()
	battle.show_fps = profile.show_fps
	add_child(battle)
	battle.battle_over.connect(_on_battle_over)
	battle.rematch_requested.connect(start_battle)
	battle.leave_requested.connect(show_menu)
	menu = Menu.new()
	menu.app = self
	add_child(menu)
	deck_screen = DeckScreen.new()
	deck_screen.app = self
	deck_screen.visible = false
	add_child(deck_screen)
	_apply_sound()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Android's back gesture: out of the deck builder or the battle to the menu, and out of
		# the menu to the home screen.
		match where:
			"deck":
				deck_screen.close()
			"battle":
				battle.toggle_pause()
			_:
				get_tree().quit()


func _apply_sound() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), not profile.sound)


func set_sound(on: bool) -> void:
	profile.sound = on
	profile.save()
	_apply_sound()


func set_show_fps(on: bool) -> void:
	profile.show_fps = on
	battle.show_fps = on
	profile.save()


func set_level(level: int) -> void:
	profile.level = clampi(level, 0, 2)
	profile.save()


func set_deck(deck: Array) -> void:
	if Profile.is_valid_deck(deck, cards):
		profile.deck = deck.duplicate()
		profile.save()


func show_menu() -> void:
	where = "menu"
	battle.set_backdrop(true)
	battle.world.visible = true
	deck_screen.visible = false
	menu.visible = true
	menu.queue_redraw()


func show_deck() -> void:
	where = "deck"
	menu.visible = false
	battle.world.visible = false      # nothing of the field shows through the deck builder
	deck_screen.open(profile.deck)


func start_battle() -> void:
	where = "battle"
	menu.visible = false
	deck_screen.visible = false
	battle.world.visible = true
	if match_seed == 0:
		battle.match_seed = int(Time.get_unix_time_from_system()) % 1000000 + 1
	else:
		match_seed += 1
		battle.match_seed = match_seed
	battle.deck = profile.deck.duplicate()
	battle.enemy_deck = Bot.pick_deck(cards, battle.match_seed)
	battle.level = profile.level
	battle.set_backdrop(false)
	battle.start_match(battle.match_seed)


func _on_battle_over(winner: int) -> void:
	if winner == battle.local_side:
		profile.wins += 1
	elif winner == 1 - battle.local_side:
		profile.losses += 1
	else:
		profile.draws += 1
	profile.save()
