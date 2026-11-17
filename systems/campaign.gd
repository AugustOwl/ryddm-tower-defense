class_name Campaign
extends Node
## Plays saved levels in order (the playlist) or a single level picked from the menu. Winning a level moves on to
## the next one; the game-over popup asks for it. Levels come from LevelLibrary (res://levels/).

var active := false
var names: Array[String] = []          ## level file names in play order
var index := 0

var _game: Game


func setup(game: Game) -> void:
	_game = game


## Play `level_names` in order, starting at `from`.
func start(level_names: Array[String], from := 0) -> void:
	if level_names.is_empty():
		return
	names = level_names.duplicate()
	index = clampi(from, 0, names.size() - 1)
	active = true
	_load_current()


func start_single(file_name: String) -> void:
	start([file_name] as Array[String])


func stop() -> void:
	active = false


func has_next() -> bool:
	return active and index + 1 < names.size()


func next() -> void:
	if has_next():
		index += 1
		_load_current()


## "Level 2 / 5: name" while a playlist is running, otherwise "".
func position_text() -> String:
	if not active:
		return ""
	return "Level %d / %d: %s" % [index + 1, names.size(), _game.board.level.level_name]


func _load_current() -> void:
	var data := LevelLibrary.load_level(names[index])
	if data == null:
		push_warning("Couldn't load level " + names[index])
		_game.enter_menu()
		return
	_game.load_level(data)
	_game.start_play()
