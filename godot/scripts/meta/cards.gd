extends RefCounted
# 0.31.153 COMMANDER (prototype). Kevin: "a clash royale style system with the heroes ... 1v1 real player and 30 bots
# 15 on each side. The bots will be each players army and the player will need to unlock heros (cards) to be able to
# have more variety of troops (hats) on the field"; then "Yes" to the test: a mode next to the 16v16, you against an AI
# commander on the phone, the troops we already have as the first cards.
# In the match (siege_sim.gd, commander = true): each side has its hero (you; the enemy commander's) and 15 soldiers
# waiting in the barracks. Command points fill up over the match; a card from your hand (4 of your deck of 8, the next
# one waiting) sends a squad of its troop out of your castle, wearing its hat. A soldier who falls drops his hat (Fat
# Princess) and is back in the barracks a few seconds later, ready for the next card.
# All numbers here are first guesses to play with.

# id -> {name, cls, up, rarity, cost (command points), squad (soldiers sent), role (what the bots do: raid -- go for the
# King; escort -- take outposts, back the raid; defend -- hold the walls; gather -- wood and stone), look (portrait)}
const CARDS := {
	"peasants":    {"name":"Peasants", "cls":"villager", "up":false, "rarity":"common", "cost":1, "squad":3, "role":"raid", "look":"villager",
		"text":"Three angry Villagers. Cheap, brave, mostly in the way."},
	"workers":     {"name":"Workers", "cls":"worker", "up":false, "rarity":"common", "cost":2, "squad":2, "role":"gather", "look":"worker",
		"text":"Chop wood, mine stone, mend the gates. The workshop's upgrades run on them."},
	"knights":     {"name":"Knights", "cls":"knight", "up":false, "rarity":"common", "cost":3, "squad":2, "role":"escort", "look":"knight",
		"text":"Shields up. They take outposts and hunt archers."},
	"archers":     {"name":"Archers", "cls":"ranger", "up":false, "rarity":"common", "cost":3, "squad":2, "role":"defend", "look":"ranger",
		"text":"Man the ramparts and rain arrows on anyone at your gates."},
	"barbarians":  {"name":"Barbarians", "cls":"barbarian", "up":false, "rarity":"common", "cost":3, "squad":2, "role":"raid", "look":"barbarian",
		"text":"Gate-breakers. They go straight for the enemy's King."},
	"rogues":      {"name":"Rogues", "cls":"rogue", "up":false, "rarity":"rare", "cost":3, "squad":2, "role":"raid", "look":"rogue",
		"text":"Fast and sneaky. First into the enemy castle."},
	"mages":       {"name":"Mages", "cls":"mage", "up":false, "rarity":"rare", "cost":4, "squad":2, "role":"defend", "look":"mage",
		"text":"Fireballs from the walls. Crowds hate them."},
	"priests":     {"name":"Priest", "cls":"priest", "up":false, "rarity":"rare", "cost":3, "squad":1, "role":"escort", "look":"priest",
		"text":"Heals whoever he follows. Keeps a raid alive."},
	"crusader":    {"name":"Crusader", "cls":"knight", "up":true, "rarity":"epic", "cost":4, "squad":1, "role":"escort", "look":"crusader",
		"text":"A Knight with a throwing hammer, and a lot more of him."},
	"berserker":   {"name":"Berserker", "cls":"barbarian", "up":true, "rarity":"epic", "cost":4, "squad":1, "role":"raid", "look":"berserker",
		"text":"Spins through crowds. Points himself at the King."},
	"assassin":    {"name":"Assassin", "cls":"rogue", "up":true, "rarity":"epic", "cost":4, "squad":1, "role":"raid", "look":"assassin",
		"text":"Vanishes, strikes, gone. Murder on archers."},
	"ranger":      {"name":"Ranger", "cls":"ranger", "up":true, "rarity":"epic", "cost":4, "squad":1, "role":"defend", "look":"sniper",
		"text":"The best bow in the realm, on your walls."},
	"archmage":    {"name":"Archmage", "cls":"mage", "up":true, "rarity":"legendary", "cost":5, "squad":1, "role":"defend", "look":"archmage",
		"text":"Calls down meteors on whoever comes near your gates."},
	"necromancer": {"name":"Necromancer", "cls":"priest", "up":true, "rarity":"legendary", "cost":5, "squad":1, "role":"escort", "look":"necromancer",
		"text":"Drains enemies, heals friends, raises the fallen."},
}
const ORDER := ["peasants", "workers", "knights", "archers", "barbarians", "rogues", "mages", "priests", "crusader", "berserker",
	"assassin", "ranger", "archmage", "necromancer"]
const DECK_SIZE := 8
const HAND := 4
const DEFAULT_DECK := ["knights", "archers", "barbarians", "workers", "rogues", "mages", "priests", "crusader"]
const RARITY_COLOR := {"common":"#b8c4c9", "rare":"#5fb6ff", "epic":"#c47bff", "legendary":"#ffb13d"}

static func card(id: String) -> Dictionary:
	return CARDS.get(id, {})

static func portrait(id: String) -> String:
	return "res://assets/ui/skins/default_%s.png" % str(card(id).get("look", "villager"))

static func valid_deck(deck: Array) -> bool:
	if deck.size() != DECK_SIZE:
		return false
	var seen := {}
	for id in deck:
		if not CARDS.has(str(id)) or seen.has(str(id)):
			return false
		seen[str(id)] = true
	return true

static func deck_cost(deck: Array) -> float:
	# the average cost (Clash Royale shows it on the deck)
	var s := 0.0
	for id in deck:
		s += float(card(str(id)).get("cost", 0))
	return s / maxf(1.0, float(deck.size()))

static func ai_deck(seed_value: int) -> Array:
	# the AI commander's deck: Workers and Knights always (or it never builds anything and never holds a wall), six more
	# at random
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rest: Array = ORDER.duplicate()
	rest.erase("workers")
	rest.erase("knights")
	var out := ["workers", "knights"]
	while out.size() < DECK_SIZE:
		out.append(rest.pop_at(rng.randi_range(0, rest.size() - 1)))
	return out
