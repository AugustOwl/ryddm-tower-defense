class_name Mob
extends RefCounted
## A player unit spawned by a Barracks. Behavior lives in UnitManager.

var def: Dictionary                ## its entry in data/mob_defs.gd
var node: Node3D
var owner_cell: Vector2i           ## the spawner tower that made it
var cell: Vector2i
var prev := HexGrid.NO_CELL        ## the cell before `cell` (wanderers avoid U-turns)
var next := HexGrid.NO_CELL
var wander_left := 0.0             ## seconds of random wandering remaining
var hp := 0.0
var partner: Enemy = null          ## the enemy it is locked in a duel with (see UnitManager._duel), or null
var dead := false
