class_name DeckStore
extends RefCounted
## The player's deck: how many copies of each card (by card name) can be dealt. Saved to user://deck.json so you
## don't have to rebuild it every run. The deck holds at most `limit` cards in total (copies count); it starts at
## STARTING_LIMIT and can be raised later (for example by an unlock) by setting DeckStore.limit.
## (user:// on Windows is %APPDATA%\Godot\app_userdata\<project name>\.)

const PATH := "user://deck.json"
const MAX_COPIES := 2                  ## copies of a single card
const STARTING_LIMIT := 8              ## cards allowed in the deck at the start

const STARTING_SPELL_LIMIT := 2        ## spell cards allowed in the deck at the start (a separate limit)

static var limit := STARTING_LIMIT     ## cards allowed in the deck right now
static var spell_limit := STARTING_SPELL_LIMIT   ## spell cards allowed in the deck right now


## The default deck: a mix of damage, a cheap shooter, turf / economy and mobs (one copy each).
static func starter_deck() -> Dictionary:
	var counts := {}
	for card in TowerDefs.CARDS:
		counts[card["name"]] = 0
	for card_name in ["Pulse", "Rapid", "Farm", "Barracks", "Summon"]:       # Summon is a spell card
		if counts.has(card_name):
			counts[card_name] = 1
	return counts


## The saved deck, trimmed to the current limit, or the starter deck if nothing valid is saved.
static func load_deck() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return starter_deck()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("cards")) != TYPE_DICTIONARY:
		_set_aside_corrupt()                         # unreadable or wrong shape: fall back to the starter deck
		return starter_deck()
	var counts := {}
	for card in TowerDefs.CARDS:                     # cards missing from the file count as 0 copies
		counts[card["name"]] = clampi(int(parsed["cards"].get(card["name"], 0)), 0, MAX_COPIES)
	counts = fit_to_limit(counts)
	if total(counts) <= 0:                           # a deck with no usable cards is as good as corrupt
		_set_aside_corrupt()
		return starter_deck()
	return counts


## Move a corrupt deck file out of the way (to deck.json.corrupt, replacing an older one) so it is never loaded
## again but can still be inspected. If it can't be moved, delete it. Never touches anything but the deck file.
static func _set_aside_corrupt() -> void:
	push_warning("Deck file is corrupt, using the starter deck: " + PATH)
	var abs_path := ProjectSettings.globalize_path(PATH)
	var backup := abs_path + ".corrupt"
	if FileAccess.file_exists(PATH + ".corrupt"):
		DirAccess.remove_absolute(backup)
	if DirAccess.rename_absolute(abs_path, backup) != OK:
		DirAccess.remove_absolute(abs_path)


static func save_deck(counts: Dictionary) -> bool:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"cards": counts}, "\t"))
	return true


static func is_spell(card: Dictionary) -> bool:
	return card["kind"] == "spell"


## Tower / mob cards in the deck (copies count). Spell cards have their own count: see spell_total.
static func total(counts: Dictionary) -> int:
	var n := 0
	for card in TowerDefs.CARDS:
		if not is_spell(card):
			n += int(counts.get(card["name"], 0))
	return n


## Spell cards in the deck (copies count). They have their own separate limit, `spell_limit`.
static func spell_total(counts: Dictionary) -> int:
	var n := 0
	for card in TowerDefs.CARDS:
		if is_spell(card):
			n += int(counts.get(card["name"], 0))
	return n


## Drop copies (later cards first) until the deck fits both limits (cards and spells are counted separately).
static func fit_to_limit(counts: Dictionary) -> Dictionary:
	var fitted := {}
	var room := limit
	var spell_room := spell_limit
	for card in TowerDefs.CARDS:
		var want := int(counts.get(card["name"], 0))
		var keep := 0
		if is_spell(card):
			keep = mini(want, spell_room)
			spell_room -= keep
		else:
			keep = mini(want, room)
			room -= keep
		fitted[card["name"]] = keep
	return fitted


## Card indices (into TowerDefs.CARDS) repeated once per copy: the pool the hand draws from.
static func to_pool(counts: Dictionary) -> Array[int]:
	var pool: Array[int] = []
	for i in TowerDefs.CARDS.size():
		for _copy in int(counts.get(TowerDefs.CARDS[i]["name"], 0)):
			pool.append(i)
	if pool.is_empty():                              # never leave the player without cards
		for i in TowerDefs.CARDS.size():
			if not is_spell(TowerDefs.CARDS[i]):
				pool.append(i)
	return pool
