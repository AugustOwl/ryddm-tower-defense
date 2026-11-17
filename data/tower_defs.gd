class_name TowerDefs
extends RefCounted
## The player's card pool. Every card dealt is a random entry from CARDS; playing it builds that tower.
##
## Keys:  name, kind, cost (AP / stars), color + accent (look), blurb (text on the card),
##        range (hexes), rate (seconds between attacks), damage, and optional extras:
##        hp (default comes from TowerManager), command_radius (makes it a command tower: extends territory).
##
## kind:
##   "shot"     hits its nearest enemy; with no enemy around it hits enemy structures in range
##   "nova"     hits every enemy in range at once
##   "slow"     hits its nearest enemy and slows it (slow_time seconds, to slow_factor of normal speed)
##   "flame"    hits every enemy in a short cone in front of it (cone_deg is the half-angle)
##   "farm"     never attacks; adds ap_bonus AP per second while it stands
##   "wall"     does nothing; it just stands in the way (towers block paths) and soaks up damage
##   "spell"    not a tower: a one-shot effect cast when the card is played (key `spell`: "summon" or "haste")
##   "spawner"  every `rate` seconds spawns a mob (the `mob` key picks its type from data/mob_defs.gd;
##              at most max_mobs alive per spawner)
##
## Optional key `infiltrate` (hexes): the tower may be built that far outside your turf, as long as the
## hex isn't on enemy turf. Cards with it are "infiltrators".

const CARDS: Array[Dictionary] = [
	{"name": "Pulse", "kind": "shot", "cost": 2, "color": Color("3b8f5c"), "accent": Color("7be0a0"),
		"range": 3.2, "rate": 0.6, "damage": 8.0, "blurb": "Reliable single\ntarget shot"},
	{"name": "Rapid", "kind": "shot", "cost": 1, "color": Color("b8932f"), "accent": Color("ffe27a"),
		"range": 2.4, "rate": 0.2, "damage": 3.0, "blurb": "Fast, weak shots"},
	{"name": "Sniper", "kind": "shot", "cost": 4, "color": Color("6b4bb8"), "accent": Color("c3a8ff"),
		"range": 5.5, "rate": 1.5, "damage": 25.0, "blurb": "Long range,\nheavy hit"},
	{"name": "Cannon", "kind": "shot", "cost": 3, "color": Color("b8573b"), "accent": Color("ffa98a"),
		"range": 2.8, "rate": 1.0, "damage": 16.0, "blurb": "Short range,\nstrong hit"},
	{"name": "Nova", "kind": "nova", "cost": 3, "color": Color("2f7fb8"), "accent": Color("8fd6ff"),
		"range": 2.0, "rate": 1.4, "damage": 9.0, "blurb": "AOE pulse hits\nall nearby"},
	{"name": "Chill", "kind": "slow", "cost": 2, "color": Color("2fb8b0"), "accent": Color("a8fff5"),
		"range": 3.0, "rate": 0.25, "damage": 1.0, "slow_time": 0.6, "slow_factor": 0.4,
		"blurb": "Slow beam: target\nat 40% speed"},
	{"name": "Flame", "kind": "flame", "cost": 3, "color": Color("c4561f"), "accent": Color("ffb347"),
		"range": 1.9, "rate": 0.15, "damage": 4.0, "cone_deg": 40.0, "blurb": "Burns everything\nin a short cone"},
	{"name": "Farm", "kind": "farm", "cost": 2, "color": Color("a88a1f"), "accent": Color("ffd24a"),
		"range": 0.0, "rate": 0.0, "damage": 0.0, "ap_bonus": 0.1, "command_radius": 2,
		"blurb": "+0.1 AP/s. Command\ntower: extends turf"},
	{"name": "Barracks", "kind": "spawner", "cost": 3, "color": Color("3b5fb8"), "accent": Color("8fb0ff"),
		"range": 0.0, "rate": 4.0, "damage": 0.0, "max_mobs": 3, "mob": "marcher",
		"blurb": "Spawns mobs that\nmarch on the spawn"},
	# Infiltrators: may be built up to `infiltrate` hexes beyond your turf (never on enemy turf).
	{"name": "Infiltrator", "kind": "shot", "cost": 3, "color": Color("5a5f78"), "accent": Color("b9c2ff"),
		"range": 2.2, "rate": 0.8, "damage": 6.0, "hp": 30.0, "infiltrate": 3,
		"blurb": "Build up to 3 hexes\npast your turf"},
	{"name": "Camp", "kind": "spawner", "cost": 2, "color": Color("5f7a3b"), "accent": Color("b6e07a"),
		"range": 0.0, "rate": 5.0, "damage": 0.0, "hp": 30.0, "max_mobs": 3, "mob": "wanderer", "infiltrate": 2,
		"blurb": "Infiltrator (2 out).\nSpawns wanderers"},
	# Spell cards ("kind": "spell"): no tower. Playing one casts it at once and it is GONE for the rest of the run.
	# They have their own deck limit (DeckStore.spell_limit). "spell" picks the effect (see PlayerController).
	{"name": "Summon", "kind": "spell", "spell": "summon", "cost": 2, "color": Color("3b8fb8"), "accent": Color("a8e4ff"),
		"range": 0.0, "rate": 0.0, "damage": 0.0, "min": 3, "max": 5,
		"blurb": "3-5 mobs appear at\nrandom spawn points"},
	{"name": "Haste", "kind": "spell", "spell": "haste", "cost": 2, "color": Color("b8a02f"), "accent": Color("fff0a0"),
		"range": 0.0, "rate": 0.0, "damage": 0.0, "min": 2, "max": 3, "speed_mult": 2.0, "duration": 8.0,
		"blurb": "2-3 of your mobs\nrun 2x faster, 8s"},
	{"name": "Wall", "kind": "wall", "cost": 2, "color": Color("7a7468"), "accent": Color("cfc7b4"),
		"range": 0.0, "rate": 0.0, "damage": 0.0, "hp": 120.0, "infiltrate": 2,
		"blurb": "Blocks the path.\nBuild up to 2 out"},
]
