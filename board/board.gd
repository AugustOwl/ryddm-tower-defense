class_name Board
extends Node3D
## The playing field: indexes the current LevelData for fast lookups and builds the 3D tiles, walls,
## base / spawn markers and the pulsing background. Call refresh() after the LevelData is modified.

const TILE_H := 1.2                    ## thickness of a floor tile (its top sits at y = 0): the platforms stand this tall
const WALL_TOP := 0.6                  ## height of the top of a wall tile
const LEVEL_SHADER := preload("res://shaders/level_pulse.gdshader")
const GROUND_SHADER := preload("res://shaders/ground_layer.gdshader")
const FLOOR_PICK := [35, 65, 80, 92]   ## cumulative % chance of floor colors A, B, C, D (the rest is E)
## The ground under the platforms is 5 visual layers, top to bottom, over a solid backing plane. The top layer is the
## most transparent and each one below is more opaque:
##   "waves"  16-bit style color waves (pixelated, few colors)
##   "viz1/2/3"  the three ground visualizers; their types are chosen in the Look tab
##   "disco"  the disco floor, at the very bottom
## depth = distance below the platforms' underside. drift must keep drift * Conductor.FLOW_PERIOD a whole number.
const GROUND_LAYERS := [
	{"kind": "waves", "depth": 0.15, "alpha": 0.08, "lighten": 0.30, "scale": 1.0, "drift": 1.0, "phase": 0.0},
	{"kind": "viz1", "depth": 0.45, "alpha": 0.16, "lighten": 0.24, "scale": 1.0, "drift": 1.0, "phase": 0.0},
	{"kind": "viz2", "depth": 0.75, "alpha": 0.26, "lighten": 0.18, "scale": 0.75, "drift": 0.75, "phase": 0.33},
	{"kind": "viz3", "depth": 1.05, "alpha": 0.38, "lighten": 0.12, "scale": 0.55, "drift": 0.5, "phase": 0.66},
	{"kind": "disco", "depth": 1.35, "alpha": 0.60, "lighten": 0.0, "scale": 1.0, "drift": 1.0, "phase": 0.0},
]
const LAYER_PRIORITY := -50            ## render priority of the top ground layer (deeper ones are lower)
const LABEL_PRIORITY := 20             ## render priority of the base / enemy base name tags (always on top)
const GROUND_BOTTOM_DEPTH := 1.7      ## the solid backing plane under all the layers

var level: LevelData
var tiles: Dictionary = {}             ## Vector2i -> true (floor and walls)
var walls: Dictionary = {}             ## Vector2i -> true
var base := HexGrid.NO_CELL
var spawns: Array[Vector2i] = []

var _labels := {}                      ## base / spawn cell -> its floating Label3D
var _visuals: Node3D                   ## container for everything built from the level (rebuilt on refresh)
var _hex_mesh: CylinderMesh
var _wall_mesh: CylinderMesh
var _floors: Array[ShaderMaterial] = []   ## one material per floor color (A..E)
var _wall_material: ShaderMaterial
var _background_material: ShaderMaterial  ## the solid bottom of the ground
var _ground_layers: Array[ShaderMaterial] = []   ## the translucent layers above it (same order as GROUND_LAYERS)


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
	_floors.clear()
	for i in 5:
		_floors.append(level_material(Color.WHITE, 0.10, 0.25, 0.15))
	_wall_material = level_material(level.style.wall_color, 0.25, 0.0, 0.1)
	_background_material = level_material(level.style.background_color, 0.10, 0.4, 0.0)
	_ground_layers.clear()
	for i in GROUND_LAYERS.size():
		var layer: Dictionary = GROUND_LAYERS[i]
		var g := ShaderMaterial.new()
		g.shader = GROUND_SHADER
		# Transparent surfaces are otherwise sorted by distance, which can draw these huge planes over labels and
		# effects. A low fixed priority keeps them behind everything (the top layer drawn last of the layers).
		g.render_priority = LAYER_PRIORITY - i
		g.set_shader_parameter("layer_alpha", layer.alpha)
		g.set_shader_parameter("pattern_scale", layer.scale)
		g.set_shader_parameter("drift", layer.drift)
		g.set_shader_parameter("phase_offset", layer.phase)
		_ground_layers.append(g)
	apply_style()
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
	var colors := [style.floor_color_a, style.floor_color_b, style.floor_color_c, style.floor_color_d, style.floor_color_e]
	for i in _floors.size():
		var f := _floors[i]
		f.set_shader_parameter("base_color", colors[i])
		f.set_shader_parameter("pulse_strength", 0.10 * style.floor_reactivity)
		f.set_shader_parameter("ring_strength", 0.10 * style.visualizer_brightness)
		f.set_shader_parameter("sparkle_strength", 0.05 * style.visualizer_brightness)
		f.set_shader_parameter("viz_type", style.visualizer_type)
	_wall_material.set_shader_parameter("base_color", style.wall_color)
	_wall_material.set_shader_parameter("pulse_strength", 0.25 * style.floor_reactivity)
	_wall_material.set_shader_parameter("sparkle_strength", 0.1 * style.floor_reactivity)
	_background_material.set_shader_parameter("base_color", style.background_color)
	_background_material.set_shader_parameter("ring_strength", 0.0)
	_background_material.set_shader_parameter("viz_type", 4)       # the backing is a plain solid color
	for i in _ground_layers.size():
		var g := _ground_layers[i]
		var viz := 0
		match GROUND_LAYERS[i].kind:
			"waves": viz = 6
			"viz1": viz = style.visualizer_type
			"viz2": viz = style.visualizer_type_2
			"viz3": viz = style.visualizer_type_3
			"disco": viz = 5
		for k in colors.size():
			g.set_shader_parameter("disco_" + "abcde"[k], _disco_color(colors[k], style.disco_saturation))
		g.set_shader_parameter("base_color", style.background_color.lightened(GROUND_LAYERS[i].lighten))
		g.set_shader_parameter("brightness", style.visualizer_brightness)
		g.set_shader_parameter("viz_type", viz)


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
		m.material_override = _floors[_floor_variant(c)]
		m.position = HexGrid.to_world(c) + Vector3(0, -TILE_H / 2.0, 0)
	_visuals.add_child(m)


## A floor color pushed toward vivid for the disco floor: same hue, much more saturation and value.
func _disco_color(c: Color, amount: float) -> Color:
	return Color.from_hsv(c.h, lerpf(c.s, 1.0, amount), lerpf(c.v, 1.0, amount * 0.9))


## Which floor color (index 0..4) a tile gets: a fixed pseudo-random pick, so it is the same every time.
func _floor_variant(c: Vector2i) -> int:
	var roll := posmod(hash(c), 100)
	for i in FLOOR_PICK.size():
		if roll < FLOOR_PICK[i]:
			return i
	return FLOOR_PICK.size()


## The ground under the platforms: a solid plane at the bottom and translucent visualizer layers above it
## (the top layer is the most transparent), so the beat animation has depth.
func _make_background() -> void:
	_make_ground_plane(_background_material, TILE_H + GROUND_BOTTOM_DEPTH)
	for i in range(_ground_layers.size() - 1, -1, -1):     # deepest layer first
		_make_ground_plane(_ground_layers[i], TILE_H + GROUND_LAYERS[i].depth)


func _make_ground_plane(material: Material, depth: float) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	var m := MeshInstance3D.new()
	m.mesh = plane
	m.material_override = material
	m.position.y = -depth
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visuals.add_child(m)


## A colored pad, a pillar and a floating label on a special tile (the base or a spawn point).
func _make_marker(c: Vector2i, color: Color, text: String, pillar_height: float) -> void:
	var pos := HexGrid.to_world(c)

	var pad := MeshInstance3D.new()
	pad.mesh = _hex_mesh
	pad.material_override = Mats.make(color.darkened(0.35))
	pad.position = pos + Vector3(0, 0.01, 0)
	pad.scale = Vector3(1, 0.03 / TILE_H, 1)      # a thin pad (3 cm) whatever the tile thickness
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
	label.render_priority = LABEL_PRIORITY            # drawn after the translucent ground layers
	label.outline_render_priority = LABEL_PRIORITY - 1
	label.position = pos + Vector3(0, pillar_height + 0.6, 0)
	_visuals.add_child(label)
	_labels[c] = label
