class_name PlayerController
extends Node
## Everything the player does while playing: action points, the card hand, selecting a card ("setting" it,
## which slows the game), and clicking a hex to build. Also draws the hover highlight and range preview.
##
## Hand slots: 0-2 are the hand, 3 (CardHand.SAVED) is the saved slot.

@export_group("Action Points")
@export var ap_max := 5.0
@export var ap_start := 3.0
@export var ap_regen := 0.4                  ## AP per second of game time (so it slows during card-setting slow-mo)
@export var shuffle_every_ap := 2.0          ## every time this much AP has been generated, the hand reshuffles

@export_group("Quick shuffle")
@export var shuffle_cooldown := 30.0         ## seconds (of game time) before the SHUFFLE button can be used again

var ap := 0.0
var ap_rate := 0.0                           ## current AP/s including farm towers
var shuffle_progress := 0.0                  ## AP generated since the last shuffle
var selected_card := -1                      ## index into TowerDefs.CARDS while a card is being set, else -1
var selected_slot := -1                      ## which slot that card came from
var deck_counts := {}                        ## the current deck: card name -> copies (see DeckStore)
var shuffle_left := 0.0                      ## seconds until the quick-shuffle button is ready
var spent_spells := {}                       ## spell card name -> copies already played this run (gone until a restart)

var _game: Game
var _hand: CardHand
var _hover_node: MeshInstance3D
var _hover_material: StandardMaterial3D
var _range_node: MeshInstance3D
var _drag_slowed := false                    ## true while a card drag is holding the slow-motion on


func setup(game: Game) -> void:
	_game = game
	_hand = game.hud.hand
	deck_counts = DeckStore.load_deck()
	_hand.setup(TowerDefs.CARDS, DeckStore.to_pool(deck_counts))
	_hand.slot_clicked.connect(_on_slot_clicked)
	_hand.slot_right_clicked.connect(store_card)
	_hand.slot_dropped_on_saved.connect(store_card)        # drag a card onto the saved slot (any AP)
	_hand.slot_drag_started.connect(_on_drag_started)
	_hand.slot_drag_ended.connect(_on_drag_ended)
	_hand.shuffle_pressed.connect(_on_shuffle_pressed)
	_make_cursor_nodes()
	reset()


func reset() -> void:
	ap = minf(ap_start, ap_max)
	shuffle_progress = 0.0
	shuffle_left = 0.0
	spent_spells.clear()                                       # spell cards come back with a new run
	cancel_card()
	Conductor.set_manual_slow(false)                           # a new run never starts slowed
	_hand.set_deck(DeckStore.to_pool(deck_counts))
	_hand.reset_hand()


## Use a new deck (card name -> copies): future draws come from it and the hand is reshuffled right away.
## Saving it to disk is DeckStore.save_deck's job (the pause menu does both). Spells already played this run stay gone.
func apply_deck(counts: Dictionary) -> void:
	deck_counts = counts
	var left := counts.duplicate()
	for card_name in spent_spells:
		left[card_name] = maxi(int(left.get(card_name, 0)) - int(spent_spells[card_name]), 0)
	_hand.set_deck(DeckStore.to_pool(left))
	_hand.shuffle(selected_slot)


## The SHUFFLE button: throw away the whole hand and deal a new one, then wait out the cooldown.
func _on_shuffle_pressed() -> void:
	if shuffle_left > 0.0 or _game.mode != Game.Mode.PLAY or _game.game_over:
		return
	cancel_card()
	_hand.shuffle()
	shuffle_left = shuffle_cooldown
	Conductor.accent(0.5)


## Show or hide the play-mode cursor visuals (hidden while editing a level).
func set_cursor_visible(on: bool) -> void:
	_hover_node.visible = on
	_range_node.visible = false


# ---------- Per-frame ----------

func tick(delta: float) -> void:
	ap_rate = ap_regen + _game.towers.ap_bonus()
	var gained := ap_rate * delta
	ap = minf(ap_max, ap + gained)
	shuffle_progress += gained
	shuffle_left = maxf(shuffle_left - delta, 0.0)
	_hand.shuffle_left = shuffle_left
	_hand.shuffle_total = shuffle_cooldown
	if shuffle_progress >= shuffle_every_ap and not _hand.is_dragging():   # every couple of AP, reshuffle the hand
		shuffle_progress = fmod(shuffle_progress, shuffle_every_ap)
		_hand.shuffle(selected_slot)                     # the saved card and the card being set stay put
		Conductor.accent(0.5)
	_update_drag_slow()
	_hand.ap = ap
	_game.hud.ap_display.value = ap
	_game.hud.ap_display.max_value = ap_max
	_update_cursor()


## Slow the game while a hand card is being dragged; when the drag ends, go back to whatever else wants slow-mo
## (a card being set, or the rally flag).
func _update_drag_slow() -> void:
	var dragging := _hand.is_dragging()
	if dragging == _drag_slowed:
		return
	_drag_slowed = dragging
	Conductor.set_slow(dragging or selected_card >= 0 or _game.rally.active)


func _update_cursor() -> void:
	var cell := _game.camera.cell_under_mouse()
	var over := _game.board.has_tile(cell)
	_hover_node.visible = over
	_range_node.visible = over and selected_card >= 0
	if not over:
		return
	_hover_node.position = HexGrid.to_world(cell) + Vector3(0, 0.02, 0)
	_range_node.position = HexGrid.to_world(cell) + Vector3(0, 0.03, 0)
	if selected_card >= 0:
		var ok := _game.towers.can_place(cell, TowerDefs.CARDS[selected_card])
		_hover_material.albedo_color = Color(0.3, 1.0, 0.5, 0.35) if ok else Color(1.0, 0.25, 0.25, 0.35)
		var radius: float = TowerDefs.CARDS[selected_card]["range"] * HexGrid.HEX_W
		_range_node.scale = Vector3(radius, 1.0, radius)       # the range mesh has radius 1
	else:
		_hover_material.albedo_color = Color(1, 1, 1, 0.2)


func _make_cursor_nodes() -> void:
	_hover_node = MeshInstance3D.new()
	var hex := CylinderMesh.new()
	hex.radial_segments = 6
	hex.top_radius = HexGrid.SIZE * 0.96
	hex.bottom_radius = HexGrid.SIZE * 0.96
	hex.height = 0.02
	_hover_node.mesh = hex
	_hover_material = Mats.make(Color(1, 1, 1, 0.2), true)
	_hover_node.material_override = _hover_material
	_hover_node.visible = false
	_game.add_child(_hover_node)

	_range_node = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 64
	_range_node.mesh = disc
	_range_node.material_override = Mats.make(Color(1, 1, 1, 0.08), true)
	_range_node.visible = false
	_game.add_child(_range_node)


# ---------- Selecting and playing cards ----------

func _on_slot_clicked(slot: int) -> void:
	if slot == selected_slot:
		cancel_card()
	elif slot == CardHand.SAVED and selected_slot >= 0:
		store_card(selected_slot)                      # clicking the saved slot while setting a card freezes it
	else:
		var card := _hand.type_at(slot)
		if card >= 0 and ap >= TowerDefs.CARDS[card]["cost"]:     # not enough AP: it can't be played
			if _is_spell(card):
				_cast_spell(slot)                      # spells need no target: they go off at once
			else:
				select_card(slot)


## Picking a card up to drag it sets it (range preview, hover colors) if you can afford it.
func _on_drag_started(slot: int) -> void:
	var card := _hand.type_at(slot)
	if card >= 0 and ap >= TowerDefs.CARDS[card]["cost"] and not _is_spell(card):    # a dragged spell has nothing to aim
		select_card(slot)


## Dropping on the board builds the tower on the hex under the cursor; anywhere else the card snaps back.
func _on_drag_ended(slot: int, over_field: bool) -> void:
	var dropped := _hand.type_at(slot)                 # (over_field means it wasn't dropped on the saved slot)
	if over_field and dropped >= 0 and _is_spell(dropped) and ap >= TowerDefs.CARDS[dropped]["cost"]:
		_cast_spell(slot)                              # a spell dropped on the board is cast
		return
	if selected_slot != slot:                     # not set (can't afford it) or already frozen into the saved slot
		return
	if over_field:
		_try_play_selected_card()
	if selected_slot == slot:                      # nothing was built
		cancel_card()


func _is_spell(card_index: int) -> bool:
	return TowerDefs.CARDS[card_index]["kind"] == "spell"


## Cast the spell card in `slot`. If it has nothing to act on it isn't spent. A cast spell is gone for the rest of
## the run: its AP is paid, the hand refills, and that copy is taken out of the deck until a restart.
func _cast_spell(slot: int) -> void:
	var card_index := _hand.type_at(slot)
	var def: Dictionary = TowerDefs.CARDS[card_index]
	var cast := false
	match def["spell"]:
		"summon":
			cast = _spell_summon(def)
		"haste":
			cast = _spell_haste(def)
	if not cast:
		return
	ap -= def["cost"]
	spent_spells[def["name"]] = int(spent_spells.get(def["name"], 0)) + 1
	_hand.remove_from_pool(card_index)                 # before consume(), so the refill can't draw it again
	_hand.consume(slot)
	Conductor.accent(0.6)


## Group random spawn: min..max mobs in total, each at a random one of your spawn points (your base and every
## spawner tower you own, using the mob type each one makes). They don't count toward those spawners' caps.
func _spell_summon(def: Dictionary) -> bool:
	var points: Array = [[_game.board.base, _game.units.base_minion_type]]
	for t: Tower in _game.towers.towers.values():
		if t.side == Team.PLAYER and t.kind == "spawner":
			points.append([t.cell, t.def.get("mob", "marcher")])
	for _i in randi_range(def["min"], def["max"]):
		var point: Array = points[randi() % points.size()]
		_game.units.spawn_mob(point[0], point[1], false)
		_game.effects.ring(HexGrid.to_world(point[0]) + Vector3(0, 0.05, 0), 0.9, def["accent"])
	return true


## Speed up min..max random mobs of yours for a few seconds. With no mobs out there is nothing to cast on.
func _spell_haste(def: Dictionary) -> bool:
	var live: Array[Mob] = []
	for m in _game.units.mobs:
		if not m.dead:
			live.append(m)
	if live.is_empty():
		return false
	live.shuffle()
	for m in live.slice(0, mini(randi_range(def["min"], def["max"]), live.size())):
		m.haste_left = def["duration"]
		m.haste_mult = def["speed_mult"]
		_game.effects.ring(m.node.position + Vector3(0, 0.05, 0), 0.7, def["accent"])
	return true


## Start "setting" a card: the game slows and the music muffles until the card is played or cancelled.
func select_card(slot: int) -> void:
	_game.rally.cancel()
	selected_slot = slot
	selected_card = _hand.type_at(slot)
	_hand.selected = slot
	_game.territory.show_reach(TowerDefs.CARDS[selected_card])    # outline where this card can go (if it has reach)
	Conductor.set_slow(true)


func cancel_card() -> void:
	selected_card = -1
	selected_slot = -1
	if _hand != null:
		_hand.selected = -1
	_game.territory.hide_reach()
	Conductor.set_slow(false)


## Freeze a hand card in the saved slot (swapping with the card already there, if any).
func store_card(slot: int) -> void:
	if slot == CardHand.SAVED:
		return
	cancel_card()
	_hand.store(slot)


# ---------- Input ----------

func _unhandled_input(event: InputEvent) -> void:
	if _game == null or _game.mode != Game.Mode.PLAY:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_4:
			_on_slot_clicked(event.keycode - KEY_1)             # 1-3 hand, 4 saved slot
		elif event.keycode == KEY_ESCAPE and selected_card >= 0:
			cancel_card()
		elif event.keycode == KEY_SPACE:
			Conductor.toggle_manual_slow()                     # Space: slow-motion on / off
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if selected_card >= 0:
				_try_play_selected_card()
			elif _game.camera.cell_under_mouse() == _game.board.base:
				_game.rally.begin()                    # clicking your base lets you move the rally flag
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if selected_card >= 0:
				cancel_card()
			else:
				_remove_tower_under_mouse()


func _try_play_selected_card() -> void:
	var cell := _game.camera.cell_under_mouse()
	if not _game.towers.can_place(cell, TowerDefs.CARDS[selected_card]):
		return
	ap -= TowerDefs.CARDS[selected_card]["cost"]
	_game.towers.place(cell, TowerDefs.CARDS[selected_card], Team.PLAYER)
	_hand.consume(selected_slot)                 # the card is spent; the hand refills with a random card
	cancel_card()                                # back to normal speed


func _remove_tower_under_mouse() -> void:
	var cell := _game.camera.cell_under_mouse()
	var t: Tower = _game.towers.towers.get(cell)
	if t != null and t.side == Team.PLAYER:      # enemy structures can't be dismantled, only destroyed
		_game.towers.remove(cell)
