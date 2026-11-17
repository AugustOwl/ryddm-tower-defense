class_name MusicSettings
extends Resource
## A level's soundtrack: one track, or a playlist for "DJ death match" levels where the music changes as the
## fight goes on. Edited in the level creator's "Music" tab. With no tracks, the Main node's Music (or the
## built-in drum loop) plays.

const LOOP_FIRST := 0
const CYCLE_TIMED := 1
const ON_BASE_DESTROYED := 2
const EVERY_N_KILLS := 3

@export var tracks: Array[AudioStream] = []
@export_enum("Loop the first track", "Next track every N seconds", "Next track when a base is destroyed",
		"Next track every N kills") var mode := 0
@export var switch_seconds := 45.0                 ## for "every N seconds"
@export var kills_per_switch := 10                 ## for "every N kills"


func copy() -> MusicSettings:
	var c := MusicSettings.new()
	c.tracks = tracks.duplicate()
	c.mode = mode
	c.switch_seconds = switch_seconds
	c.kills_per_switch = kills_per_switch
	return c
