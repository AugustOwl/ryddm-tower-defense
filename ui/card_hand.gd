class_name CardHand
extends Control
## A hand of 3 floating cards plus one "saved" slot (grey box above the hand) in the bottom-left corner.
## Slots: 0..2 = hand, 3 (SAVED) = the saved slot. Cards in the saved slot are frozen: no animation,
## and they are never shuffled away.
## Signals only report clicks; the owner decides what they mean. Animation uses real time, so it keeps going in slow-mo.

signal slot_clicked(slot: int)
signal slot_right_clicked(slot: int)
signal slot_dropped_on_saved(slot: int)        ## a hand card was dragged onto the saved slot (works at any AP)
signal slot_drag_started(slot: int)            ## a hand card was picked up for dragging
signal slot_drag_ended(slot: int, over_field: bool)   ## released; over_field = the cursor was out over the board

const HAND_SIZE := 3
const SAVED := 3

@export_group("Layout")
@export var card_size := Vector2(118, 164)
@export var gap := 14.0                       ## space between hand cards
@export var margin := Vector2(22, 22)         ## distance from the bottom-left corner
@export_range(0.4, 1.2) var saved_scale := 0.85
@export var saved_gap := 16.0                 ## space between the hand and the saved slot

@export_group("Animation")
@export var bob_distance := 4.0
@export var bob_speed := 1.6
@export var tilt_radians := 0.03
@export var hover_lift := 14.0
@export var selected_lift := 36.0
@export var pop_time := 0.3                   ## seconds for a freshly dealt card to pop in
@export_range(0.0, 1.0) var field_drag_alpha := 0.3   ## opacity of a dragged card while it is over the board
@export var field_fade_speed := 14.0          ## how fast it fades (per real second)

@export_group("Colors")
@export var saved_box_color := Color(0.42, 0.43, 0.47, 0.55)
@export var saved_box_border := Color(0.62, 0.63, 0.68, 0.9)
@export var frozen_border := Color("9fd8ff")
@export var star_color := Color("ffd24a")
@export var unaffordable_alpha := 0.4

var selected := -1             ## slot currently being set (0..3), or -1
var ap := 0.0                  ## current action points; cards costing more are dimmed
var hand: Array[int] = []      ## type index per hand slot
var saved := -1                ## type index in the saved slot, or -1

var _types: Array = []
var _pool: Array[int] = []     ## the deck: card indices, one entry per copy
var _panels: Array = [null, null, null, null]
var _born: Array[int] = [0, 0, 0, 0]
var _lift: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _hovered := -1
const DRAG_THRESHOLD := 8.0                    ## pixels a press must move before it counts as a drag

var _saved_box: Panel
var _saved_style: StyleBoxFlat
var _saved_style_hot: StyleBoxFlat
var _press_slot := -1                          ## slot where the left button went down, or -1
var _press_pos := Vector2.ZERO
var _drag_slot := -1                           ## hand slot currently being dragged, or -1
var _drag_offset := Vector2.ZERO
var _drag_alpha := 1.0                         ## current opacity of the dragged card
var _last_ms := 0


## Replace the deck new cards are drawn from (card indices, one entry per copy). Existing cards stay until reshuffled.
func set_deck(pool: Array[int]) -> void:
	_pool = pool


## Clear the saved slot and deal a fresh hand (used when a run restarts).
func reset_hand() -> void:
	saved = -1
	var now := Time.get_ticks_msec()
	for i in HAND_SIZE:
		hand[i] = _random_type(i)
		_born[i] = now
	refresh()


## `types`: array of dictionaries with name, cost, color, accent, blurb. `pool`: the deck (see set_deck).
func setup(types: Array, pool: Array[int] = []) -> void:
	_types = types
	_pool = pool
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_saved_box = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = saved_box_color
	sb.border_color = saved_box_border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	_saved_style = sb
	_saved_style_hot = sb.duplicate() as StyleBoxFlat           # shown while a dragged card hovers the slot
	_saved_style_hot.bg_color = Color(frozen_border, 0.35)
	_saved_style_hot.border_color = frozen_border
	_saved_style_hot.set_border_width_all(4)
	_saved_box.add_theme_stylebox_override("panel", sb)
	_saved_box.gui_input.connect(_on_gui_input.bind(SAVED))
	var l := _label("SAVED  [4]\ndrop a card here", Vector2(0, 6), 12, HORIZONTAL_ALIGNMENT_CENTER, Color(1, 1, 1, 0.55), card_size.x * saved_scale)
	_saved_box.add_child(l)
	add_child(_saved_box)

	var now := Time.get_ticks_msec()
	for i in HAND_SIZE:
		hand.append(_random_type())
		_born[i] = now
	refresh()
	_last_ms = now


## True while the player is dragging a card (the hand shouldn't reshuffle under their cursor).
func is_dragging() -> bool:
	return _drag_slot >= 0


func type_at(slot: int) -> int:
	return saved if slot == SAVED else hand[slot]


func cost_at(slot: int) -> int:
	var t := type_at(slot)
	return _types[t]["cost"] if t >= 0 else 0


## Replace every hand card (except `except_slot`, e.g. the one being set) with random new ones.
func shuffle(except_slot := -1) -> void:
	var now := Time.get_ticks_msec()
	for i in HAND_SIZE:
		if i != except_slot and i != _drag_slot:          # never swap out the card being dragged
			hand[i] = _random_type(i)
			_born[i] = now
	refresh()


## Move hand card `slot` into the saved slot (frozen). The previously saved card, if any, takes its place;
## otherwise the hand slot gets a random new card.
func store(slot: int) -> void:
	var old := saved
	saved = hand[slot]
	hand[slot] = old if old >= 0 else _random_type(slot)
	_born[slot] = Time.get_ticks_msec()
	refresh()


## A card was played: remove it. Hand slots refill with a random card; the saved slot becomes empty.
func consume(slot: int) -> void:
	if slot == SAVED:
		saved = -1
	else:
		hand[slot] = _random_type(slot)
		_born[slot] = Time.get_ticks_msec()
	refresh()


func _random_type(for_slot := -1) -> int:
	var avoid: Array = [saved]
	for i in hand.size():
		if i != for_slot:
			avoid.append(hand[i])
	var pick := _draw_card()
	for _try in 12:                                   # prefer a card we don't already hold
		if not avoid.has(pick):
			break
		pick = _draw_card()
	return pick


## One random card index from the deck (cards with more copies come up more often).
func _draw_card() -> int:
	if _pool.is_empty():
		return randi() % _types.size()
	return _pool[randi() % _pool.size()]


func refresh() -> void:
	for i in _panels.size():
		if _panels[i] != null:
			_panels[i].queue_free()
			_panels[i] = null
		var t := type_at(i)
		if t < 0:
			continue
		var card := _build_card(t, i)
		add_child(card)
		_panels[i] = card
	_hovered = -1
	_press_slot = -1                                  # the panels a press / drag belonged to are gone
	_drag_slot = -1


func _build_card(type_index: int, slot: int) -> Panel:
	var t: Dictionary = _types[type_index]
	var card := Panel.new()
	card.size = card_size
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.09, 0.11, 0.17, 0.94)
	normal.set_border_width_all(2)
	normal.border_color = frozen_border if slot == SAVED else (t["color"] as Color).darkened(0.1)
	normal.set_corner_radius_all(10)
	var chosen := normal.duplicate() as StyleBoxFlat
	chosen.set_border_width_all(4)
	chosen.border_color = t["accent"]
	chosen.bg_color = Color(0.14, 0.17, 0.25, 0.98)
	card.set_meta("normal", normal)
	card.set_meta("chosen", chosen)
	card.add_theme_stylebox_override("panel", normal)

	var emblem := ColorRect.new()
	emblem.color = t["color"]
	emblem.position = Vector2(14, 30)
	emblem.size = Vector2(card_size.x - 28, 58)
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(emblem)
	var dot := ColorRect.new()
	dot.color = t["accent"]
	dot.size = Vector2(22, 22)
	dot.position = emblem.position + (emblem.size - dot.size) / 2.0
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(dot)

	var cost: int = t["cost"]
	for s in cost:                  # star level = AP cost, drawn as polygons (no font dependency)
		var star := Polygon2D.new()
		star.polygon = _star_points(8.0, 3.4)
		star.color = star_color
		star.position = Vector2(card_size.x - 15 - (cost - 1 - s) * 17, 14)
		card.add_child(star)

	card.add_child(_label("[%d]" % (slot + 1), Vector2(8, 5), 12, HORIZONTAL_ALIGNMENT_LEFT, Color(1, 1, 1, 0.55)))
	card.add_child(_label(t["name"], Vector2(0, 94), 17, HORIZONTAL_ALIGNMENT_CENTER, Color.WHITE))
	card.add_child(_label(t["blurb"], Vector2(0, 122), 11, HORIZONTAL_ALIGNMENT_CENTER, Color(1, 1, 1, 0.7)))

	card.gui_input.connect(_on_gui_input.bind(slot))
	card.mouse_entered.connect(func() -> void: _hovered = slot)
	card.mouse_exited.connect(func() -> void:
		if _hovered == slot:
			_hovered = -1)
	return card


## Left button: a press that doesn't move is a click (reported on release); moving more than DRAG_THRESHOLD
## pixels turns a hand card into a drag, and releasing over the saved slot freezes it there.
## Right button: freeze the card directly.
func _on_gui_input(ev: InputEvent, slot: int) -> void:
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_press_slot = slot
				_press_pos = get_global_mouse_position()
			else:
				_release(slot)
			accept_event()
		elif ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
			slot_right_clicked.emit(slot)
			accept_event()
	elif ev is InputEventMouseMotion and _press_slot == slot and _drag_slot < 0 and slot < HAND_SIZE:
		if get_global_mouse_position().distance_to(_press_pos) > DRAG_THRESHOLD and _panels[slot] != null:
			_drag_slot = slot
			_drag_alpha = 1.0
			_drag_offset = (_panels[slot] as Panel).position - get_local_mouse_position()
			slot_drag_started.emit(slot)
			accept_event()


func _release(slot: int) -> void:
	if _drag_slot >= 0:
		var dragged := _drag_slot
		_drag_slot = -1
		_press_slot = -1
		if _saved_drop_area().has_point(get_global_mouse_position()):
			slot_dropped_on_saved.emit(dragged)
		slot_drag_ended.emit(dragged, _is_over_field())   # the owner plays it on the board, or lets it snap back
	elif _press_slot == slot:
		_press_slot = -1
		slot_clicked.emit(slot)
	else:
		_press_slot = -1


## True when the cursor is out over the board: above the hand strip and not on the saved slot.
func _is_over_field() -> bool:
	var mouse := get_global_mouse_position()
	if _saved_box != null and _saved_drop_area().has_point(mouse):
		return false
	var vp := get_viewport_rect().size
	var hand_top := vp.y - margin.y - card_size.y - hover_lift
	return mouse.y < hand_top


## The saved slot's screen rectangle, a little generous so the drop is forgiving.
func _saved_drop_area() -> Rect2:
	return _saved_box.get_global_rect().grow(16.0)


func _star_points(outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 10:
		var r := outer if k % 2 == 0 else inner
		var a := -PI / 2.0 + k * PI / 5.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


func _label(text: String, pos: Vector2, font_size: int, align: HorizontalAlignment, color: Color, width := -1.0) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = Vector2(card_size.x if width < 0.0 else width, 20)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(_delta: float) -> void:
	if _saved_box == null:
		return
	var now := Time.get_ticks_msec()
	var dt := (now - _last_ms) / 1000.0     # real time, unaffected by Engine.time_scale
	_last_ms = now
	var t := now / 1000.0
	var vp := get_viewport_rect().size
	var hand_top := vp.y - margin.y - card_size.y

	for i in HAND_SIZE:
		var card: Panel = _panels[i]
		if card == null:
			continue
		if i == _drag_slot:                                # being dragged: follows the mouse at full brightness
			card.pivot_offset = card_size / 2.0
			card.position = get_local_mouse_position() + _drag_offset
			card.rotation = 0.0
			card.scale = Vector2.ONE * 1.06
			card.z_index = 20
			card.add_theme_stylebox_override("panel", card.get_meta("chosen"))
			var goal_alpha := field_drag_alpha if _is_over_field() else 1.0    # fade over the board to show the tile
			_drag_alpha = lerpf(_drag_alpha, goal_alpha, clampf(dt * field_fade_speed, 0.0, 1.0))
			card.modulate = Color(1, 1, 1, _drag_alpha)
			continue
		card.z_index = 0
		var goal :=-selected_lift if i == selected else (-hover_lift if i == _hovered else 0.0)
		_lift[i] = lerpf(_lift[i], goal, clampf(dt * 12.0, 0.0, 1.0))
		var bob := sin(t * bob_speed + i * 0.9) * bob_distance
		var k := clampf((now - _born[i]) / 1000.0 / maxf(pop_time, 0.001), 0.0, 1.0)
		var pop := 1.0 + 2.70158 * pow(k - 1.0, 3.0) + 1.70158 * pow(k - 1.0, 2.0)   # ease-out-back
		card.pivot_offset = card_size / 2.0
		card.position = Vector2(margin.x + i * (card_size.x + gap), hand_top + _lift[i] + bob)
		card.rotation = sin(t * 1.1 + i * 1.7) * tilt_radians
		card.scale = Vector2.ONE * pop
		_style_card(card, i == selected)

	# Saved slot: static box; a card inside is frozen (no bob, tilt or lift).
	var box_size := card_size * saved_scale
	_saved_box.size = box_size
	_saved_box.position = Vector2(margin.x, hand_top - saved_gap - box_size.y)
	var hot := _drag_slot >= 0 and _saved_drop_area().has_point(get_global_mouse_position())
	_saved_box.add_theme_stylebox_override("panel", _saved_style_hot if hot else _saved_style)
	var saved_card: Panel = _panels[SAVED]
	if saved_card != null:
		saved_card.pivot_offset = Vector2.ZERO
		saved_card.position = _saved_box.position
		saved_card.rotation = 0.0
		saved_card.scale = Vector2.ONE * saved_scale
		_style_card(saved_card, selected == SAVED)


func _style_card(card: Panel, is_selected: bool) -> void:
	var slot := _panels.find(card)
	card.add_theme_stylebox_override("panel", card.get_meta("chosen") if is_selected else card.get_meta("normal"))
	card.modulate = Color.WHITE if ap >= cost_at(slot) else Color(1, 1, 1, unaffordable_alpha)
