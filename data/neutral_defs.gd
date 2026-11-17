class_name NeutralDefs
extends RefCounted
## Neutral structures and units: hostile to both the player and the enemy. They are placed in the level editor
## (never built by a card or by the enemy commander).
##
## STRUCTURES use the same keys as EnemyDefs.STRUCTURES (kind "shot" or "spawner", range, rate, damage, hp ...).
## A "spawner" makes units from UNITS (its "unit" key) and keeps at most "max_units" of them alive.
##
## UNITS use the same keys as enemy units (EnemyDefs.TYPES) plus: "neutral": true, "melee_dps" (damage per second to
## whatever it is fighting) and "leash" (hexes it may wander from its den). Your towers and mobs treat them like
## enemies, and the enemy's own units get attacked by them.

const STRUCTURES := {
	"wild_turret": {"name": "Wild Turret", "kind": "shot", "color": Color("6b6b3a"), "accent": Color("e8e07a"),
		"range": 2.8, "rate": 0.9, "damage": 6.0, "hp": 60.0},
	"wild_den": {"name": "Wild Den", "kind": "spawner", "color": Color("4a5a3a"), "accent": Color("a8d070"),
		"range": 0.0, "rate": 6.0, "damage": 0.0, "hp": 60.0, "max_units": 3, "unit": "critter"},
}

const UNITS := {
	"critter": {"name": "Critter", "weight": 0.0, "speed": 1.0, "hp": 24.0, "size": 0.85,
		"color": Color("d8c84a"), "behavior": "critter", "neutral": true, "melee_dps": 6.0, "leash": 3},
}
