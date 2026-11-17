class_name LevelSettingsPanel
extends PanelContainer
## The level creator's settings window (right side of the screen while editing). Tabs:
##   Enemy deck       difficulty presets, spawn rate, speed / HP scaling, enemy building, unit mix
##   Win condition    destroy all enemy bases (always) plus an optional survive-time or kill-count goal
##   Music            one track, or a playlist for "DJ death match" levels, and when it switches
##   Look             floor / wall / background / accent colors and particle amount, speed, size, lifetime
## Layout (the hex map itself) is edited with the toolbar above. Everything is stored in the LevelData
## and saved with the level. Each control is "bound" to one property of a settings resource, so adding a
## setting is one line in the matching _build_*_tab function.

const MUSIC_MODES := ["Loop the first track", "Next track every N seconds", "Next track when a base is destroyed",
		"Next track every N kills"]
const WIN_MODES := ["Destroy all enemy bases", "Also: survive for a time", "Also: defeat a number of enemies"]

var _game: Game
var _tabs: TabContainer
var _bindings: Array[Dictionary] = []       ## {kind, control, target (Callable -> Resource), prop, scale}
var _weight_spins := {}                     ## enemy type key -> SpinBox
var _track_list: ItemList
var _file_dialog: FileDialog
var _status: Label
var _syncing := false                       ## true while controls are being refreshed (ignore their signals)


func setup(game: Game) -> void:
	_game = game
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(430, 0)
	add_child(_tabs)
	_build_enemy_tab()
	_build_win_tab()
	_build_music_tab()
	_build_look_tab()
	_build_file_dialog()
	game.hud.add_child(self)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 8)


## Load the current level's settings into every control (without triggering edits).
func sync() -> void:
	_syncing = true
	for b in _bindings:
		var obj: Object = b["target"].call()
		var value = obj.get(b["prop"])
		match b["kind"]:
			"spin":
				(b["control"] as SpinBox).set_value_no_signal(float(value) * float(b["scale"]))
			"check":
				(b["control"] as CheckBox).set_pressed_no_signal(bool(value))
			"option":
				(b["control"] as OptionButton).select(int(value))
			"color":
				(b["control"] as ColorPickerButton).color = value
	var weights := _game.enemy_settings.unit_weights
	for key: String in _weight_spins:
		(_weight_spins[key] as SpinBox).set_value_no_signal(float(weights.get(key, EnemyDefs.TYPES[key]["weight"])))
	_refresh_tracks()
	_syncing = false


# ---------- Resource getters (what the bound controls edit) ----------

func _enemy() -> Object:
	return _game.board.level.enemy


func _rules() -> Object:
	return _game.board.level.rules


func _music() -> Object:
	return _game.board.level.music


func _style() -> Object:
	return _game.board.level.style


# ---------- Tabs ----------

func _page(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = title
	box.add_theme_constant_override("separation", 4)
	_tabs.add_child(box)
	return box


func _build_enemy_tab() -> void:
	var box := _page("Enemy deck")
	var presets := HBoxContainer.new()
	presets.add_child(_text("Preset:"))
	for preset_name: String in EnemySettings.PRESETS:
		var b := Button.new()
		b.text = preset_name.capitalize()
		b.pressed.connect(func() -> void:
			_game.board.level.enemy = EnemySettings.preset(preset_name)
			sync())
		presets.add_child(b)
	box.add_child(presets)

	_check(box, "Enemy builds structures", _enemy, "ai_enabled")
	_spin(box, "Spawn every (s)", _enemy, "spawn_interval", 0.3, 10.0, 0.1)
	_spin(box, "Enemy speed %", _enemy, "speed_scale", 30, 200, 5, 100.0)
	_spin(box, "Enemy HP %", _enemy, "hp_scale", 20, 300, 10, 100.0)
	_spin(box, "Enemy base HP", _enemy, "base_hp", 1, 100, 1)
	_spin(box, "First build (s)", _enemy, "ai_first_build_delay", 0, 120, 1)
	_spin(box, "Build every (s)", _enemy, "ai_build_interval", 2, 90, 1)
	_spin(box, "Max command posts", _enemy, "ai_max_posts", 0, 10, 1)
	_spin(box, "Max turrets / slow / barracks", _enemy, "ai_max_turrets", 0, 30, 1)
	_spin(box, "Max enemy barracks", _enemy, "ai_max_barracks", 0, 10, 1)
	_check(box, "Turrets cover busy hexes", _enemy, "ai_threat_tracking")
	_spin(box, "Desperation at base HP <= (0 = off)", _enemy, "ai_desperation_hp", 0, 50, 1)

	box.add_child(_text("Enemy deck: spawn weight per unit (0 = never)"))
	for key: String in EnemyDefs.TYPES:
		var spin := _make_spin(0, 10, 0.5)
		spin.value_changed.connect(func(v: float) -> void:
			if not _syncing:
				_game.enemy_settings.unit_weights[key] = v)
		_row(box, EnemyDefs.TYPES[key]["name"], spin)
		_weight_spins[key] = spin


func _build_win_tab() -> void:
	var box := _page("Win condition")
	box.add_child(_text("Destroying every enemy base always wins.\nYou lose when your base is destroyed."))
	_option(box, "Extra way to win", WIN_MODES, _rules, "win_mode")
	_spin(box, "Survive for (s)", _rules, "survive_seconds", 5, 1800, 5)
	_spin(box, "Defeat this many enemies", _rules, "kill_target", 1, 500, 1)


func _build_music_tab() -> void:
	var box := _page("Music")
	box.add_child(_text("Add several tracks for a DJ death match:\nthe music changes as the fight goes on."))
	_track_list = ItemList.new()
	_track_list.custom_minimum_size = Vector2(0, 130)
	box.add_child(_track_list)

	var buttons := HBoxContainer.new()
	buttons.add_child(_button("Add track...", func() -> void: _file_dialog.popup_centered()))
	buttons.add_child(_button("Remove", func() -> void: _edit_tracks("remove")))
	buttons.add_child(_button("Up", func() -> void: _edit_tracks("up")))
	buttons.add_child(_button("Down", func() -> void: _edit_tracks("down")))
	buttons.add_child(_button("Preview", _preview_track))
	box.add_child(buttons)

	_option(box, "Switch tracks", MUSIC_MODES, _music, "mode")
	_spin(box, "...every (s)", _music, "switch_seconds", 5, 600, 5)
	_spin(box, "...every (kills)", _music, "kills_per_switch", 1, 200, 1)
	_status = _text("")
	box.add_child(_status)


func _build_look_tab() -> void:
	var box := _page("Look")
	_color(box, "Floor tile A", _style, "floor_color_a")
	_color(box, "Floor tile B", _style, "floor_color_b")
	_color(box, "Walls", _style, "wall_color")
	_color(box, "Background", _style, "background_color")
	_color(box, "Accent glow / particles", _style, "accent_color")
	box.add_child(_text("Particles (percent of normal)"))
	_spin(box, "Amount %", _style, "particle_amount", 20, 300, 10, 100.0)
	_spin(box, "Speed %", _style, "particle_speed", 40, 250, 10, 100.0)
	_spin(box, "Size %", _style, "particle_size", 40, 300, 10, 100.0)
	_spin(box, "Lifetime %", _style, "particle_lifetime", 30, 250, 10, 100.0)
	box.add_child(_button("Reset look to default", func() -> void:
		_game.board.level.style = LevelStyle.new()
		_game.apply_style()
		sync()))


# ---------- Music helpers ----------

func _build_file_dialog() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.title = "Add a music track"
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_file_dialog.filters = PackedStringArray(["*.mp3, *.ogg, *.wav ; Audio files"])
	_file_dialog.size = Vector2i(800, 520)
	_file_dialog.file_selected.connect(func(path: String) -> void:
		var stream := load(path) as AudioStream
		if stream == null:
			_status.text = "Couldn't load " + path
			return
		_game.board.level.music.tracks.append(stream)
		_refresh_tracks()
		_status.text = "Added " + path.get_file())
	add_child(_file_dialog)


func _refresh_tracks() -> void:
	_track_list.clear()
	for track in _game.board.level.music.tracks:
		_track_list.add_item("%d.  %s" % [_track_list.item_count + 1, track.resource_path.get_file()])


func _edit_tracks(action: String) -> void:
	var selected := _track_list.get_selected_items()
	if selected.is_empty():
		return
	var tracks := _game.board.level.music.tracks
	var i: int = selected[0]
	match action:
		"remove":
			tracks.remove_at(i)
		"up":
			if i > 0:
				var above := tracks[i - 1]
				tracks[i - 1] = tracks[i]
				tracks[i] = above
				i -= 1
		"down":
			if i < tracks.size() - 1:
				var below := tracks[i + 1]
				tracks[i + 1] = tracks[i]
				tracks[i] = below
				i += 1
	_refresh_tracks()
	if i < _track_list.item_count:
		_track_list.select(i)


## Listen to the selected track (or the first) right now.
func _preview_track() -> void:
	var tracks := _game.board.level.music.tracks
	if tracks.is_empty():
		_status.text = "Add a track first."
		return
	var selected := _track_list.get_selected_items()
	Conductor.play_track(tracks[selected[0] if not selected.is_empty() else 0], true)
	_status.text = "Previewing. Press Play (F2) to hear the level's real playlist."


# ---------- Control builders (each binds a control to one property of a settings resource) ----------

func _text(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	return b


func _row(parent: Control, text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var label := _text(text)
	label.custom_minimum_size.x = 210
	row.add_child(label)
	row.add_child(control)
	parent.add_child(row)


func _make_spin(min_value: float, max_value: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_value
	s.max_value = max_value
	s.step = step
	return s


## `display_scale` converts a stored fraction to what is shown, e.g. 0.85 -> 85 (%).
func _spin(parent: Control, text: String, target: Callable, prop: String, min_value: float, max_value: float,
		step: float, display_scale := 1.0) -> void:
	var spin := _make_spin(min_value, max_value, step)
	spin.value_changed.connect(func(v: float) -> void:
		if _syncing:
			return
		var obj: Object = target.call()
		var value := v / display_scale
		obj.set(prop, int(round(value)) if typeof(obj.get(prop)) == TYPE_INT else value))
	_row(parent, text, spin)
	_bindings.append({"kind": "spin", "control": spin, "target": target, "prop": prop, "scale": display_scale})


func _check(parent: Control, text: String, target: Callable, prop: String) -> void:
	var check := CheckBox.new()
	check.text = text
	check.toggled.connect(func(on: bool) -> void:
		if not _syncing:
			(target.call() as Object).set(prop, on))
	parent.add_child(check)
	_bindings.append({"kind": "check", "control": check, "target": target, "prop": prop, "scale": 1.0})


func _option(parent: Control, text: String, items: Array, target: Callable, prop: String) -> void:
	var option := OptionButton.new()
	for item in items:
		option.add_item(item)
	option.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			(target.call() as Object).set(prop, index))
	_row(parent, text, option)
	_bindings.append({"kind": "option", "control": option, "target": target, "prop": prop, "scale": 1.0})


func _color(parent: Control, text: String, target: Callable, prop: String) -> void:
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(90, 28)
	picker.edit_alpha = false
	picker.color_changed.connect(func(c: Color) -> void:
		if _syncing:
			return
		(target.call() as Object).set(prop, c)
		_game.apply_style())                         # recolors the board live
	_row(parent, text, picker)
	_bindings.append({"kind": "color", "control": picker, "target": target, "prop": prop, "scale": 1.0})
