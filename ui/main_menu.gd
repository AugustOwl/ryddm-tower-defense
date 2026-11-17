class_name MainMenu
extends CanvasLayer
## The start menu, shown over the board when the game launches (and when you pick "Main menu").
##   Play playlist    the saved levels in order (the debug playlist the first time)
##   Choose a level   play any single level from res://levels/
##   Edit playlist    add / remove / reorder the playlist; changes save automatically
##   Deck builder     choose your cards (up to DeckStore.limit, 4 to begin with); saved for next time
##   Level creator    paint, generate and save levels
## Levels are .tres files in res://levels/ and the order is res://levels/playlist.json (see LevelLibrary).

var _game: Game
var _root: Control
var _main_box: VBoxContainer
var _picker_box: VBoxContainer
var _playlist_box: VBoxContainer
var _deck: DeckBuilder
var _play_button: Button
var _picker_list: ItemList
var _playlist_list: ItemList
var _available_list: ItemList
var _status: Label
var _playlist: Array[String] = []        ## the playlist being shown / edited
var _available: Array[String] = []       ## every level file in the folder


func _ready() -> void:
	_game = get_parent() as Game
	layer = 15
	_build_ui()
	_root.visible = false


func open() -> void:
	LevelLibrary.ensure_starter_levels()
	_reload()
	_root.visible = true
	_show(_main_box)


func close() -> void:
	_root.visible = false


func _show(box: Control) -> void:
	for b in [_main_box, _picker_box, _playlist_box, _deck]:
		b.visible = b == box
	_status.text = ""


func _reload() -> void:
	_available = LevelLibrary.list_levels()
	_playlist = LevelLibrary.load_playlist()
	_play_button.text = "Play playlist  (%d levels)" % _playlist.size()
	_play_button.disabled = _playlist.is_empty()


# ---------- Actions ----------

func _play_playlist(from := 0) -> void:
	if _playlist.is_empty():
		return
	close()
	_game.campaign.start(_playlist, from)


func _play_single(file_name: String) -> void:
	close()
	_game.campaign.start_single(file_name)


func _open_picker() -> void:
	_picker_list.clear()
	for f in _available:
		_picker_list.add_item("%s     %s" % [f.get_basename(), LevelLibrary.level_title(f)])
	_show(_picker_box)


func _open_playlist_editor() -> void:
	_refresh_playlist_lists()
	_show(_playlist_box)


func _refresh_playlist_lists() -> void:
	_playlist_list.clear()
	for i in _playlist.size():
		_playlist_list.add_item("%d.  %s     %s" % [i + 1, _playlist[i].get_basename(), LevelLibrary.level_title(_playlist[i])])
	_available_list.clear()
	for f in _available:
		_available_list.add_item("%s     %s" % [f.get_basename(), LevelLibrary.level_title(f)])
	_play_button.text = "Play playlist  (%d levels)" % _playlist.size()
	_play_button.disabled = _playlist.is_empty()


func _save_playlist(message: String) -> void:
	_status.text = message if LevelLibrary.save_playlist(_playlist) else "Couldn't write the playlist file."
	_refresh_playlist_lists()


func _add_to_playlist() -> void:
	var selected := _available_list.get_selected_items()
	if selected.is_empty():
		return
	_playlist.append(_available[selected[0]])
	_save_playlist("Added. Playlist saved.")


func _remove_from_playlist() -> void:
	var selected := _playlist_list.get_selected_items()
	if selected.is_empty():
		return
	_playlist.remove_at(selected[0])
	_save_playlist("Removed. Playlist saved.")


func _move_in_playlist(offset: int) -> void:
	var selected := _playlist_list.get_selected_items()
	if selected.is_empty():
		return
	var i: int = selected[0]
	var j := i + offset
	if j < 0 or j >= _playlist.size():
		return
	var moved := _playlist[i]
	_playlist[i] = _playlist[j]
	_playlist[j] = moved
	_save_playlist("Reordered. Playlist saved.")
	_playlist_list.select(j)


func _play_from_selected() -> void:
	var selected := _playlist_list.get_selected_items()
	_play_playlist(selected[0] if not selected.is_empty() else 0)


# ---------- Building the UI ----------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()                       # lets the board show through, darkened
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.06, 0.8)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)

	var title := Label.new()
	title.text = "RYDDM TOWER DEFENSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	column.add_child(title)

	_main_box = VBoxContainer.new()
	_main_box.custom_minimum_size.x = 380
	_main_box.add_theme_constant_override("separation", 10)
	column.add_child(_main_box)
	_play_button = _button("Play playlist", _play_playlist)
	_main_box.add_child(_play_button)
	_main_box.add_child(_button("Choose a level", _open_picker))
	_main_box.add_child(_button("Edit playlist", _open_playlist_editor))
	_main_box.add_child(_button("Deck builder", func() -> void:
		_deck.open()
		_show(_deck)))
	_main_box.add_child(_button("Level creator", func() -> void:
		close()
		_game.enter_edit()))
	_main_box.add_child(_button("Quit", func() -> void: get_tree().quit()))

	_picker_box = VBoxContainer.new()
	_picker_box.custom_minimum_size = Vector2(640, 0)
	_picker_box.add_theme_constant_override("separation", 8)
	column.add_child(_picker_box)
	_picker_box.add_child(_heading("Choose a level"))
	_picker_list = ItemList.new()
	_picker_list.custom_minimum_size = Vector2(0, 300)
	_picker_list.item_activated.connect(func(i: int) -> void: _play_single(_available[i]))
	_picker_box.add_child(_picker_list)
	var picker_buttons := HBoxContainer.new()
	picker_buttons.add_child(_button("Play selected", func() -> void:
		var selected := _picker_list.get_selected_items()
		if not selected.is_empty():
			_play_single(_available[selected[0]])))
	picker_buttons.add_child(_button("Back", func() -> void: _show(_main_box)))
	_picker_box.add_child(picker_buttons)

	_playlist_box = VBoxContainer.new()
	_playlist_box.custom_minimum_size = Vector2(900, 0)
	_playlist_box.add_theme_constant_override("separation", 8)
	column.add_child(_playlist_box)
	_playlist_box.add_child(_heading("Edit playlist  (saved automatically)"))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	_playlist_box.add_child(columns)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_label("Playlist: played in this order"))
	_playlist_list = ItemList.new()
	_playlist_list.custom_minimum_size = Vector2(0, 280)
	left.add_child(_playlist_list)
	var left_buttons := HBoxContainer.new()
	left_buttons.add_child(_button("Up", func() -> void: _move_in_playlist(-1)))
	left_buttons.add_child(_button("Down", func() -> void: _move_in_playlist(1)))
	left_buttons.add_child(_button("Remove", _remove_from_playlist))
	left.add_child(left_buttons)
	columns.add_child(left)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_label("Levels in %s" % LevelLibrary.DIR))
	_available_list = ItemList.new()
	_available_list.custom_minimum_size = Vector2(0, 280)
	_available_list.item_activated.connect(func(_i: int) -> void: _add_to_playlist())
	right.add_child(_available_list)
	right.add_child(_button("Add to playlist", _add_to_playlist))
	columns.add_child(right)

	var bottom := HBoxContainer.new()
	bottom.add_child(_button("Play from selected", _play_from_selected))
	bottom.add_child(_button("Back", func() -> void:
		_reload()
		_show(_main_box)))
	_playlist_box.add_child(bottom)

	_deck = DeckBuilder.new()
	_deck.setup(_game)
	_deck.back_pressed.connect(func() -> void: _show(_main_box))
	column.add_child(_deck)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 46
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(handler)
	return b


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _heading(text: String) -> Label:
	var l := _label(text)
	l.add_theme_font_size_override("font_size", 28)
	return l
