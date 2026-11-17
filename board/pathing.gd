class_name Pathing
extends RefCounted
## Walking-distance fields over the board. Walls and towers block movement.
##   to_base    steps from every reachable cell to the player's base (enemies follow it downhill)
##   to_spawns  steps from every reachable cell to the nearest enemy spawn (mobs follow it downhill)
## Call refresh() whenever towers or the level change.

var to_base: Dictionary = {}
var to_spawns: Dictionary = {}
var to_rally: Dictionary = {}                ## steps to the player's rally point (mobs follow it downhill)
var rally := HexGrid.NO_CELL                 ## set by RallyController

var _board: Board
var _towers: Dictionary          ## the TowerManager's cell -> Tower dictionary (read-only here)


func setup(board: Board, towers: Dictionary) -> void:
	_board = board
	_towers = towers


func refresh() -> void:
	to_base = field([_board.base])
	to_spawns = field(_board.spawns)
	to_rally = field([rally]) if rally != HexGrid.NO_CELL else to_spawns


## Breadth-first distances from `origins`, optionally pretending `extra_block` is occupied too.
func field(origins: Array[Vector2i], extra_block := HexGrid.NO_CELL) -> Dictionary:
	var dist := {}
	var queue: Array[Vector2i] = []
	for o in origins:
		dist[o] = 0
		queue.append(o)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for dir in HexGrid.DIRS:
			var n := c + dir
			if dist.has(n) or not _board.is_walkable(n) or _towers.has(n) or n == extra_block:
				continue
			dist[n] = dist[c] + 1
			queue.append(n)
	return dist


## True if every spawn can still reach the base after a tower is built on `cell`.
func keeps_route_open(cell: Vector2i) -> bool:
	var f := field([_board.base], cell)
	for s in _board.spawns:
		if not f.has(s):
			return false
	return true
