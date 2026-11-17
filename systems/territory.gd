class_name Territory
extends Node3D
## Each side may only build near its command towers. The player's base and the enemy spawns are command
## towers, and any tower with a "command_radius" in its definition (farms, enemy command posts) is one too.
## This node computes both territories and draws a glowing, music-reactive outline around each.

@export var base_command_radius := 3         ## hexes around the base where the player may build
@export var enemy_command_radius := 3        ## hexes around each enemy spawn
@export var outline_width := 0.16
@export var player_outline_color := Color("4aa8ff")
@export var enemy_outline_color := Color("ff5a4a")
@export var outline_base_intensity := 0.7    ## glow between beats
@export var outline_setting_intensity := 1.5 ## glow while the player is setting a card

const OUTLINE_SHADER := preload("res://shaders/territory_outline.gdshader")

var _game: Game
var _areas := {Team.PLAYER: {}, Team.ENEMY: {}}          ## side -> set of cells
var _outlines := {Team.PLAYER: null, Team.ENEMY: null}   ## side -> MeshInstance3D
var _materials := {}                                     ## side -> ShaderMaterial
var _reach_def := {}                                     ## the selected card whose build area is outlined, if any
var _reach_outline: MeshInstance3D
var _reach_material: ShaderMaterial


func setup(game: Game) -> void:
	_game = game
	for entry in [[Team.PLAYER, player_outline_color], [Team.ENEMY, enemy_outline_color]]:
		var m := ShaderMaterial.new()
		m.shader = OUTLINE_SHADER
		m.set_shader_parameter("tint", entry[1])
		_materials[entry[0]] = m
	_reach_material = ShaderMaterial.new()
	_reach_material.shader = OUTLINE_SHADER
	_reach_material.set_shader_parameter("base_intensity", 1.2)


func contains(side: int, cell: Vector2i) -> bool:
	return _areas[side].has(cell)


## How many hexes outside its turf a card may be built: infiltrators use their `infiltrate` number, and every
## command tower (anything with a command_radius) may go 1 hex out.
static func reach_for(def: Dictionary) -> int:
	var command_reach := 1 if int(def.get("command_radius", 0)) > 0 else 0
	return maxi(int(def.get("infiltrate", 0)), command_reach)


## May `side` build the card `def` on `cell`, as far as territory goes? Inside its own turf always; outside it only
## within the card's reach, and never on the other side's turf.
func allows(side: int, cell: Vector2i, def: Dictionary) -> bool:
	if contains(side, cell):
		return true
	var reach := reach_for(def)
	if reach <= 0:
		return false
	var other := Team.ENEMY if side == Team.PLAYER else Team.PLAYER
	return distance_outside(side, cell) <= reach and not contains(other, cell)


## While a card with reach is selected, draw a second outline around everywhere it could be built.
func show_reach(def: Dictionary) -> void:
	_reach_def = def
	_rebuild_reach()


func hide_reach() -> void:
	_reach_def = {}
	_rebuild_reach()


func _rebuild_reach() -> void:
	if _reach_outline != null:
		_reach_outline.queue_free()
		_reach_outline = null
	if _reach_def.is_empty() or reach_for(_reach_def) <= 0:
		return
	var area := {}
	for c in _game.board.tiles:
		if allows(Team.PLAYER, c, _reach_def):
			area[c] = true
	_reach_material.set_shader_parameter("tint", _reach_def["accent"])
	_reach_outline = _build_outline(area, _reach_material, 0.07)
	if _reach_outline != null:
		add_child(_reach_outline)


## Steps from `cell` to the nearest cell of the side's territory (0 if inside it).
func distance_outside(side: int, cell: Vector2i) -> int:
	if _areas[side].has(cell):
		return 0
	var best := 1 << 30
	for c in _areas[side]:
		best = mini(best, HexGrid.distance(cell, c))
	return best


## Recompute both territories and rebuild the outline meshes.
func refresh() -> void:
	for side in [Team.PLAYER, Team.ENEMY]:
		_areas[side] = _compute(side)
		if _outlines[side] != null:
			_outlines[side].queue_free()
			_outlines[side] = null
		var outline := _build_outline(_areas[side], _materials[side])
		if outline != null:
			add_child(outline)
			_outlines[side] = outline
	_rebuild_reach()                                         # a command tower may have changed the player's turf


## Outlines glow brighter while the player is setting a card (and always pulse with the beat).
func set_glow(setting_amount: float) -> void:
	var glow := lerpf(outline_base_intensity, outline_setting_intensity, setting_amount)
	for m in _materials.values():
		m.set_shader_parameter("base_intensity", glow)


func _compute(side: int) -> Dictionary:
	var sources: Array = []                      # [cell, radius]
	if side == Team.PLAYER:
		sources.append([_game.board.base, base_command_radius])
	else:
		for s in _game.board.spawns:
			sources.append([s, enemy_command_radius])
	for t: Tower in _game.towers.towers.values():
		if t.side == side and t.command_radius() > 0:
			sources.append([t.cell, t.command_radius()])

	var area := {}
	for c in _game.board.tiles:
		for s in sources:
			if HexGrid.distance(c, s[0]) <= s[1]:
				area[c] = true
				break
	return area


## Glowing strips along every edge between a territory tile and a non-territory tile
## (edges on the board's own border are skipped).
func _build_outline(area: Dictionary, material: Material, height := 0.05) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var half := outline_width / 2.0
	for c in area:
		var center := HexGrid.to_world(c)
		for dir in HexGrid.DIRS:
			var neighbor: Vector2i = c + dir
			if area.has(neighbor) or not _game.board.has_tile(neighbor):
				continue
			var n := (HexGrid.to_world(neighbor) - center).normalized()
			var ang := atan2(n.z, n.x)
			var p1 := center + Vector3(cos(ang - PI / 6.0), 0, sin(ang - PI / 6.0)) * HexGrid.SIZE * 0.98
			var p2 := center + Vector3(cos(ang + PI / 6.0), 0, sin(ang + PI / 6.0)) * HexGrid.SIZE * 0.98
			var along := (p2 - p1).normalized() * half     # extend a little so strips join at corners
			p1 -= along
			p2 += along
			var across := n * half
			var first := verts.size()
			for corner in [p1 - across, p2 - across, p2 + across, p1 + across]:
				verts.push_back(corner)
			for uv in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				uvs.push_back(uv)
			for i in [0, 1, 2, 0, 2, 3]:
				idx.push_back(first + i)
	if verts.is_empty():
		return null

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	m.position.y = height
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m
