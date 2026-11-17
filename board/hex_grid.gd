class_name HexGrid
extends RefCounted
## Pure hex-grid math. Cells are axial coordinates stored in a Vector2i (x = q, y = r), pointy-top,
## and laid out on the world's XZ plane (y is up). Nothing here holds state.

const SIZE := 1.0                      ## hex corner radius in world units
const HEX_W := SIZE * 1.7320508        ## distance between the centers of two adjacent hexes
const NO_CELL := Vector2i(999, 999)    ## "no cell" sentinel

## The six neighbours, in order: east, north-east, north-west, west, south-west, south-east.
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


static func to_world(c: Vector2i) -> Vector3:
	return Vector3(HEX_W * (c.x + c.y / 2.0), 0.0, SIZE * 1.5 * c.y)


static func from_world(p: Vector3) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * p.x - p.z / 3.0) / SIZE
	var r := (2.0 / 3.0 * p.z) / SIZE
	var s := -q - r
	var rq := roundf(q)
	var rr := roundf(r)
	var rs := roundf(s)
	var dq := absf(rq - q)
	var dr := absf(rr - r)
	var ds := absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))


## Number of steps between two cells.
static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2


## Every cell within `radius` steps of (0, 0): a hexagon-shaped disc.
static func disc(radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(-radius, radius + 1):
			if absi(q + r) <= radius:
				cells.append(Vector2i(q, r))
	return cells
