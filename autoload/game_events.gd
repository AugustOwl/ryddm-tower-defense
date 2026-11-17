extends Node
## Autoload "GameEvents": a global event bus. Gameplay code EMITS here; visual/audio systems LISTEN.
## Gameplay never needs to know who reacts, and reactive systems never touch gameplay state.
## To add a new reaction: connect to one of these signals (see effects.gd). To add a new event: add a signal here
## and emit it from the gameplay code.

@warning_ignore_start("unused_signal")
signal enemy_spawned(world_pos: Vector3)
signal enemy_hit(world_pos: Vector3, damage: float)
signal enemy_died(world_pos: Vector3)
signal enemy_reached_base(world_pos: Vector3)
signal tower_placed(world_pos: Vector3)
signal tower_removed(world_pos: Vector3)
signal tower_fired(world_pos: Vector3)
signal tower_destroyed(world_pos: Vector3)
signal explosion(world_pos: Vector3)
signal base_destroyed(world_pos: Vector3)
signal rally_set(world_pos: Vector3)
signal mob_spawned(world_pos: Vector3)
signal mob_died(world_pos: Vector3)
signal mob_reached_spawn(world_pos: Vector3)
@warning_ignore_restore("unused_signal")
