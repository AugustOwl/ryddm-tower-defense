class_name StructureDefs
extends RefCounted
## Every structure the level editor can place on the map (enemy ones and neutral ones). A level stores them as
## LevelData.structures entries {"cell": Vector2i, "type": key}. This class turns a key into its definition and side.

## Editor order and button labels: [key, label].
const PLACEABLE := [
	["turret", "Enemy turret"], ["sniper", "Enemy sniper"], ["slow", "Enemy slow"], ["barracks", "Enemy barracks"], ["post", "Enemy post"],
	["wild_turret", "Wild turret"], ["wild_den", "Wild den"],
]


## {"def": Dictionary, "side": int} for a structure key, or {} if the key is unknown (an old or edited level).
static func find(key: String) -> Dictionary:
	if EnemyDefs.STRUCTURES.has(key):
		return {"def": EnemyDefs.STRUCTURES[key], "side": Team.ENEMY}
	if NeutralDefs.STRUCTURES.has(key):
		return {"def": NeutralDefs.STRUCTURES[key], "side": Team.NEUTRAL}
	return {}
