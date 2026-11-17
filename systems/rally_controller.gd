class_name RallyController
extends Node
## The rally point: a flag the player's mobs flow toward. It starts on the enemy base (the nearest enemy spawn).
## Click your own base to enter rally mode (the game slows, like setting a card), then click where the flag should
## go. With several enemy bases, click the one you want to march on; any reachable hex works too.
## Esc or right-click cancels.

var cell := HexGrid.NO_CELL                  ## where the flag stands
var active := false                          ## true while the player is choosing a new spot

var _game: Game
var _flag: Node3D
var _hover: MeshInstance3D
var _hover_material: StandardMaterial3D
var _marks: Array[MeshInstance3D] = []       ## highlights on the base and enemy bases while choosing
var _mark_materials: Array[StandardMaterial3D] = []
var _hint: Label


func setup(game: Game) -> void:
	_game = game
	_build_flag()
	_build_hover()
	_build_hint()


## Back to the default: the enemy spawn closest to the player's base. Pathing is refreshed by the caller.
func reset() -> void:
	cancel()
	_set_cell(_default_cell(), false)


func set_flag_visible(on: bool) -> void:
	_flag.visible = on and cell != HexGrid.NO_CELL


## Enter rally mode.
func begin() -> void:
	if active:
		return
	active = true
	Conductor.set_slow(true)
	_hint.text = "Pick which enemy base to march on (or any hex).  Esc / right-click cancels." \
			if _game.board.spawns.size() > 1 else "Click a hex for the rally flag.  Esc / right-click cancels."
	_hint.visible = true
	_make_marks()


func cancel() -> void:
	if not active:
		return
	active = false
	Conductor.set_slow(false)
	_hint.visible = false
	_hover.visible = false
	for m in _marks:
		m.queue_free()
	_marks.clear()
	_mark_materials.clear()


func _default_cell() -> Vector2i:
	var best := HexGrid.NO_CELL
	var best_d := 1 << 30
	for s in _game.board.spawns:
		var d := HexGrid.distance(s, _game.board.base)
		if d < best_d:
			best_d = d
			best = s
	return best


func _valid(c: Vector2i) -> bool:
	return _game.board.is_walkable(c) and not _game.towers.towers.has(c) and _game.pathing.to_base.has(c)


func _set_cell(c: Vector2i, refresh_paths: bool) -> void:
	cell = c
	_game.pathing.rally = c
	_flag.visible = c != HexGrid.NO_CELL and _game.mode == Game.Mode.PLAY
	if c != HexGrid.NO_CELL:
		_flag.position = HexGrid.to_world(c)
	if refresh_paths:
		_game.pathing.refresh()


# ---------- Input and per-frame ----------

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancel()
			get_viewport().set_input_as_handled()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_4:
			cancel()                                  # picking a card leaves rally mode (the card key still goes through)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var c := _game.camera.cell_under_mouse()
			if _valid(c):
				_set_cell(c, true)
				GameEvents.rally_set.emit(HexGrid.to_world(c))
				cancel()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not active:
		return
	var c := _game.camera.cell_under_mouse()
	_hover.visible = _game.board.has_tile(c)
	_hover.position = HexGrid.to_world(c) + Vector3(0, 0.05, 0)
	_hover_material.albedo_color = Color(0.3, 1.0, 0.5, 0.45) if _valid(c) else Color(1.0, 0.25, 0.25, 0.45)
	for material in _mark_materials:                  # the highlights pulse with the beat
		var color := material.albedo_color
		color.a = 0.25 + 0.4 * Conductor.pulse
		material.albedo_color = color


# ---------- Visuals ----------

func _hex_mesh(height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.radial_segments = 6
	m.top_radius = HexGrid.SIZE * 0.96
	m.bottom_radius = HexGrid.SIZE * 0.96
	m.height = height
	return m


func _make_marks() -> void:
	var targets: Array = [[_game.board.base, Color("4aa8ff")]]
	for s in _game.board.spawns:
		targets.append([s, Color("ff5a4a")])
	for t in targets:
		var m := MeshInstance3D.new()
		m.mesh = _hex_mesh(0.03)
		var material := Mats.make(Color(t[1], 0.4), true)
		m.material_override = material
		m.position = HexGrid.to_world(t[0]) + Vector3(0, 0.04, 0)
		_game.add_child(m)
		_marks.append(m)
		_mark_materials.append(material)


func _build_hover() -> void:
	_hover = MeshInstance3D.new()
	_hover.mesh = _hex_mesh(0.03)
	_hover_material = Mats.make(Color(1, 1, 1, 0.4), true)
	_hover.material_override = _hover_material
	_hover.visible = false
	_game.add_child(_hover)


func _build_flag() -> void:
	_flag = Node3D.new()
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.04
	cyl.height = 1.4
	pole.mesh = cyl
	pole.material_override = Mats.make(Color("dfe6f5"))
	pole.position.y = 0.7
	_flag.add_child(pole)

	var cloth := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.45, 0.6, 0.04)
	cloth.mesh = prism
	cloth.material_override = Mats.outlined(Color("4aa8ff"))    # beat-reactive outline, like units
	cloth.rotation_degrees.z = -90.0                            # point the triangle sideways
	cloth.position = Vector3(0.3, 1.1, 0)
	_flag.add_child(cloth)

	var ring := MeshInstance3D.new()
	ring.mesh = _hex_mesh(0.02)
	ring.material_override = Mats.make(Color(0.3, 0.65, 1.0, 0.3), true)
	ring.position.y = 0.03
	_flag.add_child(ring)

	_flag.visible = false
	_game.add_child(_flag)


func _build_hint() -> void:
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 26)
	_hint.visible = false
	_hint.text = "Pick which enemy base to march on (or any hex).  Esc / right-click cancels."
	_game.hud.add_child(_hint)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 70)
