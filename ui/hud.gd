class_name Hud
extends CanvasLayer
## The on-screen layer: the card hand and AP stars (bottom-left / top-left) and the debug text (bottom-right).
## F3 toggles the debug text.

@onready var hand: CardHand = $Hand
@onready var ap_display: ApDisplay = $ApDisplay
@onready var debug_label: Label = $Label

var _objective: Label


func _ready() -> void:
	_objective = Label.new()
	_objective.add_theme_font_size_override("font_size", 24)
	_objective.add_theme_color_override("font_outline_color", Color.BLACK)
	_objective.add_theme_constant_override("outline_size", 8)
	add_child(_objective)


## The one-line objective at the top of the screen (hidden in the level creator).
func update_objective(game: Game) -> void:
	_objective.visible = game.mode == Game.Mode.PLAY
	if _objective.visible:
		var level_line := game.campaign.position_text()
		_objective.text = (level_line + "\n" if level_line != "" else "") + game.rules.objective_text(game.play_time, game.kills)
		_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_objective.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_objective.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 10)


## Show the card hand and AP stars only while playing (the level editor has its own toolbar).
func set_play_ui_visible(on: bool) -> void:
	hand.visible = on
	ap_display.visible = on


func toggle_debug() -> void:
	debug_label.visible = not debug_label.visible


func update_debug(game: Game) -> void:
	if not debug_label.visible:
		return
	if game.mode == Game.Mode.MENU:
		debug_label.text = ""
		return
	if game.mode == Game.Mode.EDIT:
		debug_label.text = "LEVEL EDITOR  (F2: back to the game)\nWASD pan   wheel zoom   F3 hide this"
		return
	var p := game.player
	var enemy_bases: Array[String] = []
	for spawn in game.board.spawns:
		enemy_bases.append(str(ceili(game.enemy_base_hp.get(spawn, 0.0))))
	var enemy_base_text := " / ".join(enemy_bases) if not enemy_bases.is_empty() else "none"
	debug_label.text = "Hex Tower Defense 3D (debug)\n" \
			+ "Base HP: %d   Enemy base HP: %s\n" % [game.base_hp, enemy_base_text] \
			+ "Kills: %d   Enemies: %d   Mobs: %d\n" % [game.kills, game.units.enemies.size(), game.units.mobs.size()] \
			+ "1-3: hand card, 4: saved card, click hex to place\n" \
			+ "RMB on hand card: save it (or click the saved slot while setting)\n" \
			+ "Esc / RMB: cancel    RMB on tower: remove    Click your base: rally flag\n" \
			+ "M: mute    F2: level editor    F3: hide this\n" \
			+ "AP +%.2f/s   Shuffle in %.1f AP\n" % [p.ap_rate, p.shuffle_every_ap - p.shuffle_progress] \
			+ "Music  bass %.2f  mid %.2f  treble %.2f  texture %.2f" % [Conductor.bass, Conductor.mid, Conductor.treble, Conductor.texture]
