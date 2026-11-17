class_name LevelEditor
extends Node
## The level creator: an in-game editor used straight in the 3D view (F2 toggles it).
## The toolbar edits the layout; the tabbed panel on the right (ui/level_settings_panel.gd) edits the
## enemy deck, win condition, music and look.
## Paint hexes with the mouse (left button = current brush, right button = erase, drag to paint), generate a
## random map, save / load levels as .tres files in res://levels/, then press Play to try the level.
## The toolbar is built in code at the top of the screen.

enum Brush { FLOOR, ERASE, WALL, BASE, SPAWN }

const LEVEL_DIR := "res://levels"

var brush: int = Brush.FLOOR

var _game: Game
var _panel: PanelContainer
var _status: Label
var _name_edit: LineEdit
var _seed_edit: LineEdit
var _picker: OptionButton
var _radius: SpinBox
var _fill: SpinBox
var _walls: SpinBox
var _spawns: SpinBox
var _settings: LevelSettingsPanel            ## tabs: enemy deck, win condition, music, look
var _hover_node: MeshInstance3D
var _hover_material: StandardMaterial3D

var _drag_button := 0                        ## mouse button currently painting, or 0
var _drag_wall_value := true                 ## wall brush: are we adding (true) or removing walls this stroke?
var _last_cell := HexGrid.NO_CELL


func setup(game: Game) -> void:
	_game = game
	_build_toolbar()
	_settings = LevelSettingsPanel.new()
	_settings.setup(game)
	_make_hover_node()
	exit()


## Show the toolbar (called when the editor opens).
func enter() -> void:
	_panel.visible = true
	_settings.visible = true
	_hover_node.visible = true
	_name_edit.text = _game.board.level.level_name
	_refresh_level_list()
	_settings.sync()
	say("Left-drag: paint with the brush.  Right-drag: erase.  WASD / wheel: move the view.")


func exit() -> void:
	_panel.visible = false
	_settings.visible = false
	_hover_node.visible = false
	_drag_button = 0


# ---------- Toolbar ----------

func _build_toolbar() -> void:
	_panel = PanelContainer.new()
	var box := VBoxContainer.new()
	_panel.add_child(box)

	# Row 1: brushes
	var brushes := HBoxContainer.new()
	brushes.add_child(_label("Brush:"))
	var group := ButtonGroup.new()
	for entry in [["Floor", Brush.FLOOR], ["Erase", Brush.ERASE], ["Wall", Brush.WALL],
			["Base", Brush.BASE], ["Spawn", Brush.SPAWN]]:
		var b := Button.new()
		b.text = entry[0]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = entry[1] == brush
		var which: int = entry[1]
		b.pressed.connect(func() -> void: brush = which)
		brushes.add_child(b)
	box.add_child(brushes)

	# Row 2: random generation
	var gen := HBoxContainer.new()
	gen.add_child(_label("Generate:  radius"))
	_radius = _spin(4, 14, 1, _game.random_radius)
	gen.add_child(_radius)
	gen.add_child(_label("fill %"))
	_fill = _spin(30, 80, 5, _game.random_fill * 100.0)
	gen.add_child(_fill)
	gen.add_child(_label("walls %"))
	_walls = _spin(0, 25, 1, _game.random_walls * 100.0)
	gen.add_child(_walls)
	gen.add_child(_label("spawns"))
	_spawns = _spin(1, 4, 1, _game.random_spawns)
	gen.add_child(_spawns)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "seed (blank = random)"
	_seed_edit.custom_minimum_size.x = 150
	gen.add_child(_seed_edit)
	gen.add_child(_button("Random map", _on_random))
	gen.add_child(_button("Classic disc", _on_disc))
	box.add_child(gen)

	# Row 3: files and play
	var files := HBoxContainer.new()
	files.add_child(_label("Name:"))
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size.x = 160
	files.add_child(_name_edit)
	files.add_child(_button("Save", _on_save))
	_picker = OptionButton.new()
	_picker.custom_minimum_size.x = 160
	files.add_child(_picker)
	files.add_child(_button("Load", _on_load))
	files.add_child(_button("Play  (F2)", _on_play))
	files.add_child(_button("Main menu", func() -> void: _game.enter_menu()))
	box.add_child(files)

	_status = _label("")
	box.add_child(_status)

	_game.hud.add_child(_panel)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 8)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	return b


func _spin(min_value: float, max_value: float, step: float, value: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_value
	s.max_value = max_value
	s.step = step
	s.value = value
	return s


func say(text: String) -> void:
	_status.text = text


func _refresh_level_list() -> void:
	_picker.clear()
	for f in DirAccess.get_files_at(LEVEL_DIR):
		if f.ends_with(".tres"):
			_picker.add_item(f.get_basename())


# ---------- Toolbar actions ----------

func _on_random() -> void:
	var seed_value := int(_seed_edit.text) if _seed_edit.text.is_valid_int() else 0
	var data := MapGenerator.generate(seed_value, int(_radius.value), _fill.value / 100.0,
			_walls.value / 100.0, int(_spawns.value))
	_game.load_level(data)
	_name_edit.text = data.level_name
	_settings.sync()
	say("Generated \"%s\" (%d tiles, %d walls, %d spawn(s))." % [data.level_name, data.tiles.size(), data.walls.size(), data.spawns.size()])


func _on_disc() -> void:
	var data := LevelData.make_disc(int(_radius.value))
	_game.load_level(data)
	_name_edit.text = data.level_name
	_settings.sync()
	say("Loaded the classic hex disc.")


func _on_save() -> void:
	var level := _game.board.level
	var problem := level.validate()
	if problem != "":
		say("Can't save: " + problem)
		return
	var file_name := _name_edit.text.strip_edges().validate_filename()
	if file_name == "":
		file_name = "custom"
	level.level_name = _name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else file_name
	DirAccess.make_dir_recursive_absolute(LEVEL_DIR)
	var path := "%s/%s.tres" % [LEVEL_DIR, file_name]
	if ResourceSaver.save(level, path) == OK:
		LevelLibrary.add_to_playlist("%s.tres" % file_name)         # new levels join the end of the playlist
		say("Saved " + path + "  (added to the playlist)")
		_refresh_level_list()
	else:
		say("Couldn't save to " + path)


func _on_load() -> void:
	if _picker.item_count == 0:
		say("No saved levels in " + LEVEL_DIR)
		return
	var path := "%s/%s.tres" % [LEVEL_DIR, _picker.get_item_text(_picker.selected)]
	var data := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	if data == null:
		say("Couldn't load " + path)
		return
	_game.load_level(data.copy())
	_name_edit.text = data.level_name
	_settings.sync()
	say("Loaded " + path)


func _on_play() -> void:
	var problem := _game.board.level.validate()
	if problem != "":
		say("Can't play yet: " + problem)
		return
	_game.start_play()


# ---------- Painting ----------

func _unhandled_input(event: InputEvent) -> void:
	if _game == null or _game.mode != Game.Mode.EDIT:
		return
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		if event.pressed:
			_drag_button = event.button_index
			_last_cell = HexGrid.NO_CELL
			var cell := _game.camera.cell_under_mouse()
			_drag_wall_value = not _game.board.level.walls.has(cell)   # first click decides add vs remove
			_paint(cell, true)
		else:
			_drag_button = 0
	elif event is InputEventMouseMotion and _drag_button != 0:
		var cell := _game.camera.cell_under_mouse()
		if cell != _last_cell:
			_paint(cell, false)


func _paint(cell: Vector2i, is_click: bool) -> void:
	if cell == HexGrid.NO_CELL:
		return
	_last_cell = cell
	var active: int = Brush.ERASE if _drag_button == MOUSE_BUTTON_RIGHT else brush
	var changed := false
	match active:
		Brush.FLOOR:
			changed = _add_floor(cell)
		Brush.ERASE:
			changed = _erase(cell)
		Brush.WALL:
			changed = _set_wall(cell, _drag_wall_value)
		Brush.BASE:
			changed = is_click and _set_base(cell)
		Brush.SPAWN:
			changed = is_click and _toggle_spawn(cell)
	if changed:
		_game.level_edited()


func _add_floor(c: Vector2i) -> bool:
	var level := _game.board.level
	if level.tiles.has(c):
		return false
	level.tiles.append(c)
	return true


func _erase(c: Vector2i) -> bool:
	var level := _game.board.level
	if not level.tiles.has(c):
		return false
	if c == level.base:
		say("The base can't be erased - move it with the Base brush first.")
		return false
	level.tiles.erase(c)
	level.walls.erase(c)
	level.spawns.erase(c)
	return true


func _set_wall(c: Vector2i, want_wall: bool) -> bool:
	var level := _game.board.level
	if not level.tiles.has(c) or level.walls.has(c) == want_wall:
		return false
	if want_wall:
		if c == level.base or level.spawns.has(c):
			say("Can't put a wall on the base or a spawn.")
			return false
		level.walls.append(c)
	else:
		level.walls.erase(c)
	return true


func _set_base(c: Vector2i) -> bool:
	var level := _game.board.level
	if not level.tiles.has(c) or level.walls.has(c) or level.base == c:
		return false
	level.spawns.erase(c)
	level.base = c
	return true


func _toggle_spawn(c: Vector2i) -> bool:
	var level := _game.board.level
	if not level.tiles.has(c) or level.walls.has(c) or c == level.base:
		return false
	if level.spawns.has(c):
		level.spawns.erase(c)
	else:
		level.spawns.append(c)
	return true


# ---------- Hover highlight ----------

func _make_hover_node() -> void:
	_hover_node = MeshInstance3D.new()
	var hex := CylinderMesh.new()
	hex.radial_segments = 6
	hex.top_radius = HexGrid.SIZE * 0.96
	hex.bottom_radius = HexGrid.SIZE * 0.96
	hex.height = 0.04
	_hover_node.mesh = hex
	_hover_material = Mats.make(Color(1, 1, 1, 0.3), true)
	_hover_node.material_override = _hover_material
	_game.add_child(_hover_node)


func _process(_delta: float) -> void:
	if _game == null or _game.mode != Game.Mode.EDIT:
		return
	var cell := _game.camera.cell_under_mouse()
	_hover_node.visible = cell != HexGrid.NO_CELL
	_hover_node.position = HexGrid.to_world(cell) + Vector3(0, 0.06, 0)
	var colors := {
		Brush.FLOOR: Color(0.4, 0.8, 1.0, 0.35), Brush.ERASE: Color(1.0, 0.3, 0.3, 0.35),
		Brush.WALL: Color(0.8, 0.8, 0.8, 0.35), Brush.BASE: Color(0.2, 0.5, 1.0, 0.45),
		Brush.SPAWN: Color(1.0, 0.3, 0.2, 0.45),
	}
	_hover_material.albedo_color = colors[Brush.ERASE if _drag_button == MOUSE_BUTTON_RIGHT else brush]
