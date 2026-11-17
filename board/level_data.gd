class_name LevelData
extends Resource
## A level layout: which hexes exist, which are walls, where the player's base is and where enemies spawn.
## Saved as a .tres resource in res://levels/ (you can also edit one in Godot's inspector).

@export var level_name := "Untitled"
@export var tiles: Array[Vector2i] = []      ## every hex that exists (floor and walls)
@export var walls: Array[Vector2i] = []      ## tiles that are solid: no walking, no building
@export var base := Vector2i.ZERO            ## the player's base
@export var spawns: Array[Vector2i] = []     ## enemy spawn points
## Structures placed in the level editor: {"cell": Vector2i, "type": key} (keys: see StructureDefs). Enemy ones belong
## to the enemy, neutral ones to nobody; all are built when the level starts.
@export var structures: Array[Dictionary] = []
@export var enemy: EnemySettings = EnemySettings.new()   ## enemy deck: spawn rate, unit mix, building, difficulty
@export var rules: LevelRules = LevelRules.new()          ## win condition
@export var music: MusicSettings = MusicSettings.new()    ## soundtrack / DJ playlist
@export var style: LevelStyle = LevelStyle.new()          ## colors and particles


## The classic layout: a hexagon of `radius`, base on the left corner, one spawn on the right corner.
static func make_disc(radius: int) -> LevelData:
	var data := LevelData.new()
	data.level_name = "Hex disc (radius %d)" % radius
	data.tiles = HexGrid.disc(radius)
	data.base = Vector2i(-radius, 0)
	data.spawns.append(Vector2i(radius, 0))
	return data


func copy() -> LevelData:
	var c := LevelData.new()
	c.level_name = level_name
	c.tiles = tiles.duplicate()
	c.walls = walls.duplicate()
	c.base = base
	c.spawns = spawns.duplicate()
	c.structures = structures.duplicate(true)
	c.enemy = enemy.copy() if enemy != null else EnemySettings.new()
	c.rules = rules.copy() if rules != null else LevelRules.new()
	c.music = music.copy() if music != null else MusicSettings.new()
	c.style = style.copy() if style != null else LevelStyle.new()
	return c


## Tiles that can be walked on (everything except walls), as a set.
func open_tiles() -> Dictionary:
	var open := {}
	for t in tiles:
		open[t] = true
	for w in walls:
		open.erase(w)
	return open


## Returns "" if the level is playable, otherwise a message explaining the problem.
func validate() -> String:
	var open := open_tiles()
	if not open.has(base):
		return "The base must sit on a floor tile (not a wall)."
	if spawns.is_empty():
		return "Add at least one enemy spawn."
	for s in spawns:
		if not open.has(s):
			return "Spawn %s must sit on a floor tile (not a wall)." % s
		if s == base:
			return "A spawn can't be on the base."
	var blocked := {}                               # structures are solid: nothing walks through them
	for entry in structures:
		var cell: Vector2i = entry.get("cell", Vector2i.ZERO)
		if not open.has(cell) or cell == base or spawns.has(cell):
			return "Structure %s must sit on a free floor tile (not a wall, the base or a spawn)." % cell
		blocked[cell] = true
	for cell in blocked:
		open.erase(cell)
	var reachable := flood(open, base)
	for s in spawns:
		if not reachable.has(s):
			return "Spawn %s can't reach the base." % s
	return ""


## World-space rectangle (x, z) covering every tile; used to frame the camera.
func bounds() -> Rect2:
	if tiles.is_empty():
		return Rect2(-6, -6, 12, 12)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for t in tiles:
		var w := HexGrid.to_world(t)
		lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.z))
		hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.z))
	var pad := Vector2.ONE * HexGrid.SIZE
	return Rect2(lo - pad, hi - lo + pad * 2.0)


## Every cell in `open` connected to `start` (flood fill). Returns a set.
static func flood(open: Dictionary, start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for dir in HexGrid.DIRS:
			var n := c + dir
			if open.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen
