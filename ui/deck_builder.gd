class_name DeckBuilder
extends VBoxContainer
## The deck builder panel, used by both the main menu and the pause menu. Choose how many copies of each card go
## in your deck, up to DeckStore.limit cards in total (4 to begin with). "Save deck" writes it to disk, so it is
## loaded automatically next time, and applies it to the hand straight away.

signal back_pressed

var _game: Game
var _spins := {}                               ## card name -> SpinBox
var _total_label: Label
var _status: Label


func setup(game: Game) -> void:
	_game = game
	custom_minimum_size.x = 560
	add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "DECK BUILDER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	add_child(title)

	var hint := Label.new()
	hint.text = "Pick up to %d cards and %d spells (copies count). More copies = drawn more often. A spell is gone for the run once played." % [DeckStore.limit, DeckStore.spell_limit]
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)

	for card in TowerDefs.CARDS:
		add_child(_card_row(card))

	_total_label = Label.new()
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total_label.add_theme_font_size_override("font_size", 20)
	add_child(_total_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_child(_button("Save deck", _save))
	buttons.add_child(_button("Starter deck", _use_starter))
	buttons.add_child(_button("Clear", _clear))
	buttons.add_child(_button("Back", func() -> void: back_pressed.emit()))
	add_child(buttons)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status)


## Show the player's current deck (call when the panel is opened).
func open() -> void:
	_show_counts(_game.player.deck_counts)
	_status.text = ""


# ---------- Reading and writing the spin boxes ----------

func _show_counts(counts: Dictionary) -> void:
	for card in TowerDefs.CARDS:
		(_spins[card["name"]] as SpinBox).set_value_no_signal(int(counts.get(card["name"], 0)))
	_update_total()


func _read_counts() -> Dictionary:
	var counts := {}
	for card in TowerDefs.CARDS:
		counts[card["name"]] = int((_spins[card["name"]] as SpinBox).value)
	return counts


func _update_total() -> void:
	var counts := _read_counts()
	_total_label.text = "%d / %d cards     %d / %d spells" % [DeckStore.total(counts), DeckStore.limit,
			DeckStore.spell_total(counts), DeckStore.spell_limit]


## A box changed: refuse to go past the card limit (or, for a spell card, the separate spell limit).
func _on_count_changed(card_name: String) -> void:
	var counts := _read_counts()
	var is_spell := false
	for card in TowerDefs.CARDS:
		if card["name"] == card_name:
			is_spell = DeckStore.is_spell(card)
	var over := (DeckStore.spell_total(counts) - DeckStore.spell_limit) if is_spell \
			else (DeckStore.total(counts) - DeckStore.limit)
	if over > 0:
		var spin := _spins[card_name] as SpinBox
		spin.set_value_no_signal(spin.value - over)
		_status.text = ("You can only carry %d spell cards." % DeckStore.spell_limit) if is_spell \
				else ("The deck is full (%d cards). Remove one first." % DeckStore.limit)
	else:
		_status.text = ""
	_update_total()


func _save() -> void:
	var counts := _read_counts()
	if DeckStore.total(counts) == 0:
		_status.text = "The deck needs at least one card."
		return
	_game.player.apply_deck(counts)
	if DeckStore.save_deck(counts):
		_status.text = "Saved. It loads automatically next time."
	else:
		_status.text = "Applied, but couldn't write %s." % DeckStore.PATH


func _use_starter() -> void:
	_show_counts(DeckStore.starter_deck())
	_status.text = "Starter deck filled in. Press Save to keep it."


func _clear() -> void:
	_show_counts({})
	_status.text = "Cleared. Pick up to %d cards, then Save." % DeckStore.limit


# ---------- Building the rows ----------

func _card_row(card: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	var swatch := ColorRect.new()                  # the card's color
	swatch.color = card["color"]
	swatch.custom_minimum_size = Vector2(14, 14)
	row.add_child(swatch)

	var name_label := Label.new()
	name_label.text = "  %s%s" % [card["name"], "  (spell)" if DeckStore.is_spell(card) else ""]
	name_label.custom_minimum_size.x = 170
	row.add_child(name_label)

	var cost := Label.new()
	cost.text = "%d AP" % card["cost"]
	cost.custom_minimum_size.x = 56
	row.add_child(cost)

	var blurb := Label.new()
	blurb.text = String(card["blurb"]).replace("\n", " ")
	blurb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blurb.modulate = Color(1, 1, 1, 0.6)
	row.add_child(blurb)

	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = DeckStore.MAX_COPIES
	spin.step = 1
	var card_name: String = card["name"]
	spin.value_changed.connect(func(_v: float) -> void: _on_count_changed(card_name))
	row.add_child(spin)
	_spins[card_name] = spin
	return row


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(handler)
	return b
