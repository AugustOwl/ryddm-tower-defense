class_name MapGenerator
extends RefCounted
## Random level generator. Steps:
##   1. Grow an organic blob of hexes outward from the center (stretched left-to-right).
##   2. Smooth it: fill small holes, trim one-tile spurs.
##   3. Put the base at the far-left tile and the first spawn at the far-right tile; extra spawns go as far
##      from everything else as possible.
##   4. Scatter clusters of wall tiles, never walling anything off from the base.
## The same seed always gives the same map. seed 0 means "pick a random seed".


static func generate(seed_value := 0, radius := 8, fill := 0.7, wall_density := 0.07, spawn_count := 1) -> LevelData:
	var rng := RandomNumberGenerator.new()
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value

	var tiles := _grow_blob(rng, radius, clampf(fill, 0.3, 0.8))
	_smooth(tiles)

	var data := LevelData.new()
	data.level_name = "Random %d" % (rng.seed % 100000)
	data.tiles.assign(tiles.keys())
	data.base = _extreme_tile(tiles, -1)
	data.spawns.append(_extreme_tile(tiles, 1))
	for i in maxi(spawn_count - 1, 0):
		_add_far_spawn(rng, tiles, data)
	_add_walls(rng, tiles, data, wall_density)

	if data.validate() != "":                       # should never happen; fall back to the classic map
		return LevelData.make_disc(radius)
	return data


# ---------- 1 & 2: the shape ----------

static func _grow_blob(rng: RandomNumberGenerator, radius: int, fill: float) -> Dictionary:
	var target := int((3 * radius * (radius + 1) + 1) * fill)
	var tiles := {Vector2i.ZERO: true}
	var list: Array[Vector2i] = [Vector2i.ZERO]
	var attempts := 0
	while list.size() < target and attempts < target * 60:
		attempts += 1
		var n: Vector2i = list[rng.randi() % list.size()] + HexGrid.DIRS[rng.randi() % 6]
		if tiles.has(n) or not _in_ellipse(n, radius):
			continue
		tiles[n] = true
		list.append(n)
	return tiles


## Keeps the blob wider than it is tall, so base and spawn end up far apart.
static func _in_ellipse(c: Vector2i, radius: int) -> bool:
	var w := HexGrid.to_world(c)
	var ex := w.x / (radius * HexGrid.HEX_W)
	var ez := w.z / (radius * 1.5 * 0.85)
	return ex * ex + ez * ez <= 1.0


static func _smooth(tiles: Dictionary) -> void:
	for _pass in 2:
		var holes: Array[Vector2i] = []
		for t in tiles:
			for dir in HexGrid.DIRS:
				var n: Vector2i = t + dir
				if not tiles.has(n) and _neighbor_count(tiles, n) >= 5:
					holes.append(n)
		for h in holes:
			tiles[h] = true
		var spurs: Array[Vector2i] = []
		for t in tiles:
			if _neighbor_count(tiles, t) <= 1:
				spurs.append(t)
		for s in spurs:
			tiles.erase(s)


static func _neighbor_count(tiles: Dictionary, c: Vector2i) -> int:
	var count := 0
	for dir in HexGrid.DIRS:
		if tiles.has(c + dir):
			count += 1
	return count


# ---------- 3: base and spawns ----------

## The left-most (sign -1) or right-most (sign +1) tile, preferring ones near the middle line.
static func _extreme_tile(tiles: Dictionary, sign_x: int) -> Vector2i:
	var best := HexGrid.NO_CELL
	var best_score := -INF
	for t in tiles:
		var w := HexGrid.to_world(t)
		var score := w.x * sign_x * 100.0 - absf(w.z)
		if score > best_score:
			best_score = score
			best = t
	return best


static func _add_far_spawn(rng: RandomNumberGenerator, tiles: Dictionary, data: LevelData) -> void:
	var anchors: Array[Vector2i] = [data.base]
	anchors.append_array(data.spawns)
	var best := HexGrid.NO_CELL
	var best_score := -INF
	for t in tiles:
		if anchors.has(t):
			continue
		var nearest := 1 << 30
		for a in anchors:
			nearest = mini(nearest, HexGrid.distance(t, a))
		var score := nearest + rng.randf() * 0.9           # random tie-break
		if score > best_score:
			best_score = score
			best = t
	if best != HexGrid.NO_CELL:
		data.spawns.append(best)


# ---------- 4: walls ----------

static func _add_walls(rng: RandomNumberGenerator, tiles: Dictionary, data: LevelData, density: float) -> void:
	var forbidden := {}                                    # keep the area around base and spawns clear
	for t in tiles:
		if HexGrid.distance(t, data.base) <= 2:
			forbidden[t] = true
		for s in data.spawns:
			if HexGrid.distance(t, s) <= 2:
				forbidden[t] = true

	var candidates: Array[Vector2i] = []
	for t in tiles:
		if not forbidden.has(t):
			candidates.append(t)
	for i in range(candidates.size() - 1, 0, -1):          # Fisher-Yates shuffle using our seeded rng
		var j := rng.randi() % (i + 1)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	var target := int(tiles.size() * density)
	var walls := {}
	for seed_cell in candidates:
		if walls.size() >= target:
			break
		if walls.has(seed_cell) or not _try_wall(tiles, walls, data.base, seed_cell):
			continue
		var cell := seed_cell                               # grow a small cluster from the seed
		for _step in 2:
			if rng.randf() < 0.55:
				var n: Vector2i = cell + HexGrid.DIRS[rng.randi() % 6]
				if tiles.has(n) and not forbidden.has(n) and not walls.has(n) and _try_wall(tiles, walls, data.base, n):
					cell = n
	data.walls.assign(walls.keys())


## Adds a wall at `c` only if every remaining open tile is still reachable from the base.
static func _try_wall(tiles: Dictionary, walls: Dictionary, base: Vector2i, c: Vector2i) -> bool:
	walls[c] = true
	var open := {}
	for t in tiles:
		if not walls.has(t):
			open[t] = true
	if LevelData.flood(open, base).size() == open.size():
		return true
	walls.erase(c)
	return false
