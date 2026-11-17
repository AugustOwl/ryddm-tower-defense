class_name MobDefs
extends RefCounted
## Definitions of the player's mobs (what spawner towers produce). A spawner card picks its mob with a "mob" key
## (see data/tower_defs.gd). Add a new mob here; a new behavior also needs a case in UnitManager._update_mob.
##
## speed_mult / hp_mult scale UnitManager's base mob_speed / mob_hp.
## Optional keys:
##   pairs_up  true = when it passes a free enemy it pairs with it: the two stop and fight only each other until one
##             dies. A paired unit ignores everyone else. Enemies with "elusive": true (enemy_defs.gd) can't be paired.
##   elusive   true = this mob can't be paired by an enemy.
## behavior:
##   "marcher"   flows straight to the rally flag
##   "wanderer"  takes random steps for `wander_time` seconds (probing around), then flows to the rally flag

const TYPES := {
	"marcher": {"name": "Marcher", "speed_mult": 1.0, "hp_mult": 1.0,
		"color": Color("4aa8ff"), "behavior": "marcher", "pairs_up": true},
	"wanderer": {"name": "Wanderer", "speed_mult": 1.25, "hp_mult": 0.7,
		"color": Color("5fe0b8"), "behavior": "wanderer", "wander_time": 7.0},
}
