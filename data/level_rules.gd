class_name LevelRules
extends Resource
## How a level is won. Destroying every enemy base ALWAYS wins; the other modes add a second way to win.
## Losing is always "your base is destroyed". Edited in the level creator's "Win condition" tab.

const BASES_ONLY := 0
const SURVIVE := 1
const KILLS := 2

@export_enum("Destroy all enemy bases", "Also: survive for a time", "Also: defeat a number of enemies") var win_mode := 0
@export var survive_seconds := 90.0                ## for the survive mode
@export var kill_target := 30                      ## for the defeat-enemies mode


## The one-line objective shown at the top of the screen.
func objective_text(play_time: float, kills: int) -> String:
	match win_mode:
		SURVIVE:
			return "Survive  %d / %d s   (or destroy all enemy bases)" % [int(play_time), int(survive_seconds)]
		KILLS:
			return "Defeat enemies  %d / %d   (or destroy all enemy bases)" % [kills, kill_target]
	return "Destroy all enemy bases"


func copy() -> LevelRules:
	var c := LevelRules.new()
	c.win_mode = win_mode
	c.survive_seconds = survive_seconds
	c.kill_target = kill_target
	return c
