class_name LevelLibrary
extends RefCounted
## The folder of saved levels (res://levels/*.tres) and the ordered playlist of them (res://levels/playlist.json).
## The start menu plays the playlist in order; the level creator saves new levels into the folder and appends
## them to the playlist. The first time the folder is empty, a "debug playlist" of starter levels is generated.

const DIR := "res://levels"
const PLAYLIST_PATH := "res://levels/playlist.json"


## File names (e.g. "01_tutorial.tres") of every saved level, sorted.
static func list_levels() -> Array[String]:
	var names: Array[String] = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".tres"):
			names.append(f)
	names.sort()
	return names


## A fresh, editable copy of a saved level, or null if it can't be loaded.
## A level file that can't be loaded, or whose layout is broken (see is_sound), is set aside (see _set_aside_corrupt)
## so it can't break the menu or the playlist again.
static func load_level(file_name: String) -> LevelData:
	var path := "%s/%s" % [DIR, file_name]
	if not FileAccess.file_exists(path):
		return null
	var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not (res is LevelData) or not is_sound(res):
		_set_aside_corrupt(file_name)
		return null
	return (res as LevelData).copy()


## Structural sanity only (not "is it winnable", which LevelData.validate() covers): there are tiles, and the
## base and every spawn sit on one of them.
static func is_sound(data: LevelData) -> bool:
	if data.tiles.is_empty() or not data.tiles.has(data.base):
		return false
	for s in data.spawns:
		if not data.tiles.has(s):
			return false
	return true


## Rename a corrupt level to <name>.corrupt (it no longer ends in .tres, so the library ignores it), drop it from
## the playlist and, if that leaves the folder empty, regenerate the starter levels. Falls back to deleting the file
## if it can't be renamed.
static func _set_aside_corrupt(file_name: String) -> void:
	push_warning("Level file is corrupt, setting it aside: " + file_name)
	var abs_path := ProjectSettings.globalize_path("%s/%s" % [DIR, file_name])
	var backup := abs_path + ".corrupt"
	if FileAccess.file_exists("%s/%s.corrupt" % [DIR, file_name]):
		DirAccess.remove_absolute(backup)
	if DirAccess.rename_absolute(abs_path, backup) != OK:
		DirAccess.remove_absolute(abs_path)
	if FileAccess.file_exists(PLAYLIST_PATH):
		var names := load_playlist()
		names.erase(file_name)
		save_playlist(names)
	ensure_starter_levels()


static func level_title(file_name: String) -> String:
	var data := load_level(file_name)
	return data.level_name if data != null else "(can't load)"


## The saved play order, dropping files that no longer exist. With no playlist file, every level in name order.
static func load_playlist() -> Array[String]:
	var existing := list_levels()
	if not FileAccess.file_exists(PLAYLIST_PATH):
		return existing
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PLAYLIST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("levels")) != TYPE_ARRAY:
		return existing
	var names: Array[String] = []
	for entry in parsed["levels"]:
		if existing.has(str(entry)):
			names.append(str(entry))
	return names


static func save_playlist(names: Array[String]) -> bool:
	var file := FileAccess.open(PLAYLIST_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"levels": names}, "\t"))
	return true


## Add a level to the end of the playlist if it isn't in it yet.
static func add_to_playlist(file_name: String) -> void:
	var names := load_playlist()
	if not names.has(file_name):
		names.append(file_name)
		save_playlist(names)


## If the levels folder is empty, create the debug playlist: four generated levels that ramp up in difficulty
## (each with a different win condition) so there is something to play and tune against right away.
static func ensure_starter_levels() -> void:
	if not list_levels().is_empty():
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var starters := [
		["01_tutorial.tres", "Debug 1: Tutorial", 101, 6, 0.65, 0.04, 1, "tutorial", LevelRules.BASES_ONLY],
		["02_easy.tres", "Debug 2: Easy (survive)", 202, 7, 0.70, 0.06, 1, "easy", LevelRules.SURVIVE],
		["03_normal.tres", "Debug 3: Normal (kills)", 303, 8, 0.70, 0.07, 2, "normal", LevelRules.KILLS],
		["04_hard.tres", "Debug 4: Hard", 404, 9, 0.72, 0.08, 2, "hard", LevelRules.BASES_ONLY],
	]
	var names: Array[String] = []
	for s in starters:
		var level := MapGenerator.generate(s[2], s[3], s[4], s[5], s[6])
		level.level_name = s[1]
		level.enemy = EnemySettings.preset(s[7])
		level.rules.win_mode = s[8]
		ResourceSaver.save(level, "%s/%s" % [DIR, s[0]])
		names.append(s[0])
	save_playlist(names)
