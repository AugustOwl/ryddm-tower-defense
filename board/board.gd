class_name Board
extends Node3D
## The playing field: indexes the current LevelData for fast lookups and builds the 3D tiles, walls,
## base / spawn markers and the pulsing background. Call refresh() after the LevelData is modified.

const TILE_H := 0.3                    ## thickness of a floor tile (its top sits at y = 0)
const WALL_TOP := 0.6                  ## height of the top of a wall tile
const LEVEL_SHADER := preload("res://shaders/level_pulse.gdshader")

var level: LevelData
var tiles: Dictionary = {}             ## Vector2i -> true (floor and walls)
var walls: Dictionary = {}             ## Vector2i -> true
var base := HexGrid.NO_CELL
var spawns: Array[Vector2i] = []

var _labels := {}                      ## base / spawn cell -> its floating Label3D
var _visuals: Node3D                   ## container for everything built from the level (rebuilt on refresh)
var _hex_mesh: CylinderMesh
var _wall_mesh: CylinderMesh
var _floor_a: ShaderMaterial
var _floor_b: ShaderMaterial
var _wall_material: ShaderMaterial
var _background_material: ShaderMaterial


func _ready() -> void:
	# A 6-sided cylinder has a vertex pointing along +Z, which is exactly a pointy-top hex on the XZ plane.
	_hex_mesh = _make_hex_mesh(Board.TILE_H)
	_wall_mesh = _make_hex_mesh(Board.TILE_H + Board.WALL_TOP)


func load_level(data: LevelData) -> void:
	level = data
	refresh()


## Re-read the LevelData and rebuild all visuals.
func refresh() -> void:
	tiles.clear()
	walls.clear()
	for t in level.tiles:
		tiles[t] = true
	for w in level.walls:
		walls[w] = true
	base = level.base
	spawns = level.spawns.duplicate()
	_floor_a = level_material(level.style.floor_color_a, 0.10, 0.25, 0.15)
	_floor_b = level_material(level.style.floor_color_b, 0.10, 0.25, 0.15)
	_wall_material = level_material(level.style.wall_color, 0.25, 0.0, 0.1)
	_background_material = level_material(level.style.background_color, 0.25, 1.2, 0.9)
	_rebuild_visuals()


## An enemy base was destroyed during play: it stops being a spawn (the level data itself is untouched).
func destroy_spawn(c: Vector2i) -> void:
	spawns.erase(c)
	_rebuild_visuals()


## An enemy base moved to another hex during play (the level data itself is untouched).
func move_spawn(from: Vector2i, to: Vector2i) -> void:
	var i := spawns.find(from)
	if i >= 0:
		spawns[i] = to
		_rebuild_visuals()


## Change the floating text above the base or an enemy base (used to show hit points).
func set_label(c: Vector2i, text: String) -> void:
	if _labels.has(c):
		(_labels[c] as Label3D).text = text


## The level's colors changed (live edit in the level creator): recolor without rebuilding anything.
func apply_style() -> void:
	var style := level.style
	_floor_a.set_shader_parameter("base_color", style.floor_color_a)
	_floor_b.set_shader_parameter("base_color", style.floor_color_b)
	_wall_material.set_shader_parameter("base_color", style.wall_color)
	_background_material.set_shader_parameter("base_color", style.background_color)


func bounds() -> Rect2:
	return level.bounds()


func has_tile(c: Vector2i) -> bool:
	return tiles.has(c)


func is_wall(c: Vector2i) -> bool:
	return walls.has(c)


## A floor tile that is not a wall: units can stand here and towers can be built here.
func is_walkable(c: Vector2i) -> bool:
	return tiles.has(c) and not walls.has(c)


func is_spawn(c: Vector2i) -> bool:
	return spawns.has(c)


# ---------- Visuals ----------

func _rebuild_visuals() -> void:
	if _visuals != null:
		_visuals.queue_free()
	_labels.clear()
	_visuals = Node3D.new()
	add_child(_visuals)

	_make_background()
	for c in tiles:
		_make_tile(c)
	_make_marker(base, Color("2a6df4"), "BASE", 1.2)
	for s in spawns:
		_make_marker(s, Color("d9423b"), "ENEMY BASE", 0.8)


func _make_hex_mesh(height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.radial_segments = 6
	m.rings = 1
	m.top_radius = HexGrid.SIZE * 0.96
	m.bottom_radius = HexGrid.SIZE * 0.96
	m.height = height
	return m


## Surface shader that pulses with the music (see shaders/level_pulse.gdshader).
func level_material(base_color: Color, pulse_strength: float, ring_strength: float, sparkle_strength := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LEVEL_SHADER
	m.set_shader_parameter("base_color", base_color)
	m.set_shader_parameter("pulse_strength", pulse_strength)
	m.set_shader_parameter("ring_strength", ring_strength)
	m.set_shader_parameter("sparkle_strength", sparkle_strength)
	return m


func _make_tile(c: Vector2i) -> void:
	var m := MeshInstance3D.new()
	if walls.has(c):
		m.mesh = _wall_mesh
		m.material_override = _wall_material
		m.position = HexGrid.to_world(c) + Vector3(0, WALL_TOP - (TILE_H + WALL_TOP) / 2.0, 0)
	else:
		m.mesh = _hex_mesh
		m.material_override = _floor_a if (c.x - c.y) % 3 != 0 else _floor_b
		m.position = HexGrid.to_world(c) + Vector3(0, -TILE_H / 2.0, 0)
	_visuals.add_child(m)


## Large plane under the board whose rings travel outward on every beat.
func _make_background() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	var m := MeshInstance3D.new()
	m.mesh = plane
	m.material_override = _background_material
	m.position.y = -TILE_H - 0.1
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visuals.add_child(m)


## A colored pad, a pillar and a floating label on a special tile (the base or a spawn point).
func _make_marker(c: Vector2i, color: Color, text: String, pillar_height: float) -> void:
	var pos := HexGrid.to_world(c)

	var pad := MeshInstance3D.new()
	pad.mesh = _hex_mesh
	pad.material_override = Mats.make(color.darkened(0.35))
	pad.position = pos + Vector3(0, 0.01, 0)
	pad.scale = Vector3(1, 0.1, 1)
	_visuals.add_child(pad)

	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.radial_segments = 6
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.7
	cyl.height = pillar_height
	pillar.mesh = cyl
	pillar.material_override = Mats.make(color)
	pillar.position = pos + Vector3(0, pillar_height / 2.0 + 0.05, 0)
	_visuals.add_child(pillar)

	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.01
	label.font_size = 48
	label.outline_size = 12
	label.no_depth_test = true
	label.position = pos + Vector3(0, pillar_height + 0.6, 0)
	_visuals.add_child(label)
	_labels[c] = label
