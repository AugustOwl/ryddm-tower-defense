class_name Tower
extends RefCounted
## One placed tower or enemy structure. Behavior lives in TowerManager; this just holds state.

var cell: Vector2i
var side: int                  ## Team.PLAYER or Team.ENEMY
var def: Dictionary            ## the card / structure definition it was built from
var kind: String
var range_world := 0.0         ## attack range in world units
var cooldown := 0.0
var hp := 0.0
var max_hp := 0.0

var node: Node3D               ## root of its visuals
var turret: Node3D             ## the part that rotates toward targets
var bar: MeshInstance3D        ## health bar (hidden until damaged)


func command_radius() -> int:
	return def.get("command_radius", 0)
