class_name Enemy
extends RefCounted
## One enemy unit. Behavior lives in UnitManager; the stats come from `def` (see data/enemy_defs.gd).

var def: Dictionary
var node: Node3D
var bar: MeshInstance3D

var cell := HexGrid.NO_CELL        ## the cell it last arrived at
var prev := HexGrid.NO_CELL        ## the cell before that (wanderers avoid U-turns)
var next := HexGrid.NO_CELL        ## the cell it is walking to (NO_CELL = pick one)

var hp := 0.0
var max_hp := 0.0
var speed_scale := 1.0             ## per-level speed multiplier (EnemySettings), fixed when it spawns
var wander_left := 0.0            ## seconds of erratic movement remaining
var slow_left := 0.0               ## seconds of slow remaining
var slow_factor := 1.0
var partner: Mob = null            ## the mob it is locked in a duel with (see UnitManager._duel), or null
var dead := false
