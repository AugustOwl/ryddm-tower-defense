class_name GameOverPopup
extends CanvasLayer
## Short "VICTORY" / "DEFEAT" popup shown when a side runs out of bases (or a level goal is met). The game pauses
## behind it. The main button (also Enter / R) is "Next level" after a win in a playlist, otherwise it restarts the
## current level; the second button goes back to the main menu.

var _game: Game
var _root: Control
var _title: Label
var _detail: Label
var _primary: Button
var _primary_action: Callable


func _ready() -> void:
	_game = get_parent() as Game
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	_build_ui()
	_root.visible = false


func show_result(victory: bool, kills: int, reason := "") -> void:
	_title.text = "VICTORY" if victory else "DEFEAT"
	_title.add_theme_color_override("font_color", Color("7be0a0") if victory else Color("ff6b5a"))
	var headline := reason if reason != "" else ("All enemy bases destroyed!" if victory else "Your base was destroyed.")

	var campaign := _game.campaign
	if victory and campaign.has_next():
		_primary.text = "Next level   (Enter)"
		_primary_action = campaign.next
	elif victory and campaign.active and campaign.names.size() > 1:
		headline += "\nPlaylist complete!"
		_primary.text = "Main menu   (Enter)"
		_primary_action = _game.enter_menu
	else:
		_primary.text = "Restart level   (Enter)"
		_primary_action = _game.start_play

	var where := campaign.position_text()
	_detail.text = (where + "\n" if where != "" else "") + headline + "\nEnemies defeated: %d" % kills
	_root.visible = true
	get_tree().paused = true


func _choose(action: Callable) -> void:
	_root.visible = false
	get_tree().paused = false
	action.call()


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_R:
			_choose(_primary_action)
		get_viewport().set_input_as_handled()         # nothing else (pause menu, hotkeys) while this is up


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 56)
	box.add_child(_title)

	_detail = Label.new()
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_theme_font_size_override("font_size", 20)
	box.add_child(_detail)

	_primary = Button.new()
	_primary.custom_minimum_size.y = 52
	_primary.add_theme_font_size_override("font_size", 22)
	_primary.pressed.connect(func() -> void: _choose(_primary_action))
	box.add_child(_primary)

	var menu_button := Button.new()
	menu_button.text = "Main menu"
	menu_button.custom_minimum_size.y = 44
	menu_button.add_theme_font_size_override("font_size", 18)
	menu_button.pressed.connect(func() -> void: _choose(_game.enter_menu))
	box.add_child(menu_button)
