class_name EnemyDefs
## Data-driven definitions for enemy units and enemy structures. To add a new unit, add an entry to TYPES:
## give it stats and one of the behaviors below (or add a new behavior in main.gd's _move_enemy).
##
## Common keys:   name, weight (how often it spawns relative to others), speed (hexes/sec), hp, size (visual scale), color
## Optional key `elusive` (true): mobs that pair up with passing enemies (see mob_defs.gd) can't pair with this one,
## so it slips past them.
## behavior:
##   "walker"    follows the shortest path to the player's base
##   "wanderer"  takes random steps for `wander_time` seconds, then heads for the base      (wander_time)
##   "raider"    follows the path but stops to attack any player tower it passes next to    (attack_dps)
##   "kamikaze"  charges straight at a player tower within `aggro_range` hexes and explodes (charge_speed, aggro_range,
##               blast_damage, blast_radius in hexes); otherwise walks like a walker

const TYPES := {
	"grunt": {"name": "Grunt", "weight": 5.0, "speed": 1.4, "hp": 30.0, "size": 1.0,
		"color": Color("e8574f"), "behavior": "walker"},
	"runner": {"name": "Runner", "weight": 3.0, "speed": 2.8, "hp": 14.0, "size": 0.7,
		"color": Color("ff9a3a"), "behavior": "walker", "elusive": true},
	"brute": {"name": "Brute", "weight": 1.5, "speed": 0.75, "hp": 100.0, "size": 1.5,
		"color": Color("8c2f2f"), "behavior": "walker"},
	"wanderer": {"name": "Wanderer", "weight": 2.0, "speed": 1.6, "hp": 30.0, "size": 1.0,
		"color": Color("c46bff"), "behavior": "wanderer", "wander_time": 4.0},
	"raider": {"name": "Raider", "weight": 2.0, "speed": 1.2, "hp": 45.0, "size": 1.15,
		"color": Color("e0c040"), "behavior": "raider", "attack_dps": 14.0},
	"kamikaze": {"name": "Kamikaze", "weight": 1.5, "speed": 1.6, "hp": 12.0, "size": 0.8,
		"color": Color("ff2a6d"), "behavior": "kamikaze", "charge_speed": 3.6, "aggro_range": 4.0,
		"blast_damage": 60.0, "blast_radius": 1.1},
}

## Structures the enemy AI builds. Same keys as the player's TOWER_TYPES (see main.gd), plus hp.
## kind "command" = a command post: it does nothing but extend enemy territory (command_radius, in hexes).
const STRUCTURES := {
	"turret": {"name": "Enemy Turret", "kind": "shot", "color": Color("8a2f2f"), "accent": Color("ff6b5a"),
		"range": 2.6, "rate": 1.0, "damage": 5.0, "hp": 40.0},
	"post": {"name": "Command Post", "kind": "command", "color": Color("6b2f4a"), "accent": Color("ff7ab8"),
		"range": 0.0, "rate": 0.0, "damage": 0.0, "command_radius": 2, "hp": 80.0},
	## Long range, slow and heavy: one-shots most of your mobs from far away. Fragile up close.
	"sniper": {"name": "Enemy Sniper", "kind": "shot", "color": Color("5a2f6b"), "accent": Color("d89aff"),
		"range": 5.0, "rate": 2.0, "damage": 15.0, "hp": 30.0},
	## Slows your nearest mob in range (slow_time seconds, to slow_factor of its speed) with a little damage.
	"slow": {"name": "Enemy Chiller", "kind": "slow", "color": Color("2f5a6b"), "accent": Color("7ad8ff"),
		"range": 2.6, "rate": 0.5, "damage": 0.5, "slow_time": 0.8, "slow_factor": 0.4, "hp": 40.0},
	## Spawns enemy units (picked from the level's unit mix) right at the structure, at most max_units alive at once.
	"barracks": {"name": "Enemy Barracks", "kind": "spawner", "color": Color("7a2f3f"), "accent": Color("ff8a7a"),
		"range": 0.0, "rate": 6.0, "damage": 0.0, "hp": 60.0, "max_units": 3},
}


## Random enemy type. `weights` (type key -> weight) overrides each type's default weight; used by per-level settings.
static func pick_weighted(weights := {}) -> Dictionary:
	var total := 0.0
	for k in TYPES:
		total += float(weights.get(k, TYPES[k]["weight"]))
	if total <= 0.0:
		return TYPES["grunt"]
	var roll := randf() * total
	for k in TYPES:
		roll -= float(weights.get(k, TYPES[k]["weight"]))
		if roll <= 0.0:
			return TYPES[k]
	return TYPES["grunt"]
