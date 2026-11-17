class_name PauseMenu
extends CanvasLayer
## Esc opens the pause menu: Resume, Restart, Deck builder, Level creator, Main menu, Quit. While it is open the
## whole scene tree is paused (game logic, music clock and audio); this node keeps running because its process
## mode is "always". Esc still cancels a card you are setting (or rally mode) before it opens the menu.
## The deck builder is the shared DeckBuilder panel (ui/deck_builder.gd), also used by the main menu.

var _game: Game
var _root: Control
var _menu_box: VBoxContainer
var _deck: DeckBuilder


func _ready() -> void:
	_game = get_parent() as Game
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build_ui()
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _game.mode == Game.Mode.MENU:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _root.visible:
			resume()
		elif _game.player.selected_card < 0 and not _game.rally.active:   # otherwise Esc just cancels that
			_open()
		else:
			return
		get_viewport().set_input_as_handled()


func resume() -> void:
	_root.visible = false
	get_tree().paused = false


func restart() -> void:
	resume()
	_game.start_play()                             # fresh run on the current level


func _open() -> void:
	_show_menu()
	_root.visible = true
	get_tree().paused = true


func _show_menu() -> void:
	_menu_box.visible = true
	_deck.visible = false


func _show_deck() -> void:
	_deck.open()
	_menu_box.visible = false
	_deck.visible = true


# ---------- Building the UI ----------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()                     # darkens the game behind the menu (and blocks clicks to it)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	_menu_box = VBoxContainer.new()
	_menu_box.custom_minimum_size.x = 260
	_menu_box.add_theme_constant_override("separation", 12)
	center.add_child(_menu_box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	_menu_box.add_child(title)
	_menu_box.add_child(_button("Resume", resume))
	_menu_box.add_child(_button("Restart", restart))
	_menu_box.add_child(_button("Deck builder", _show_deck))
	_menu_box.add_child(_button("Level creator", func() -> void:
		resume()
		_game.enter_edit()))
	_menu_box.add_child(_button("Main menu", func() -> void:
		resume()
		_game.enter_menu()))
	_menu_box.add_child(_button("Quit", func() -> void: get_tree().quit()))

	_deck = DeckBuilder.new()
	_deck.setup(_game)
	_deck.back_pressed.connect(_show_menu)
	_deck.visible = false
	center.add_child(_deck)


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 48
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(handler)
	return b
