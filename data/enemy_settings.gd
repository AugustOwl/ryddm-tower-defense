class_name EnemySettings
extends Resource
## How aggressive the enemy is on one level. Stored inside the LevelData (so every level can differ) and edited in
## the level editor's "Enemy behavior" panel. Presets make it easy to build gentler onboarding levels.

@export var spawn_interval := 1.0            ## seconds between enemy units
@export var speed_scale := 1.0               ## multiplies every enemy's speed
@export var hp_scale := 1.0                  ## multiplies every enemy's hit points
@export var base_hp := 10                    ## hit points of each enemy base (mobs that reach it hurt it)
@export var ai_enabled := true              ## does the enemy build structures at all?
@export var ai_first_build_delay := 8.0      ## seconds before its first structure
@export var ai_build_interval := 12.0        ## seconds between structures after that
@export var ai_max_posts := 4                ## max command posts
@export var ai_max_turrets := 10             ## max turrets (slow towers and barracks count toward this too)
@export var ai_max_barracks := 2             ## max enemy barracks (they spawn units from the unit mix)
@export var ai_threat_tracking := true       ## the commander remembers where your units pass and builds turrets to cover those hexes
## Desperation is ON whenever this has a value (1 or more) and OFF at 0: a base at or below this many HP unleashes its
## burst (shockwave + summon), and at half HP it retreats (see EnemyAI).
@export_range(0, 100) var ai_desperation_hp := 0
## Spawn weight per enemy type key (see EnemyDefs.TYPES). A missing key uses the type's default weight; 0 = never.
@export var unit_weights := {}

const PRESETS := ["tutorial", "easy", "normal", "hard"]


func desperation_on() -> bool:
	return ai_desperation_hp > 0


static func preset(preset_name: String) -> EnemySettings:
	var s := EnemySettings.new()
	match preset_name:
		"tutorial":      # a trickle of slow, weak grunts and no enemy building
			s.spawn_interval = 4.0
			s.speed_scale = 0.7
			s.hp_scale = 0.6
			s.base_hp = 4
			s.ai_enabled = false
			s.unit_weights = _weights(1.0, 0.0, 0.0, 0.0, 0.0, 0.0)
		"easy":          # slower waves, no suicide units, the enemy builds rarely
			s.spawn_interval = 2.5
			s.speed_scale = 0.85
			s.hp_scale = 0.8
			s.base_hp = 6
			s.ai_first_build_delay = 25.0
			s.ai_build_interval = 20.0
			s.ai_max_posts = 1
			s.ai_max_turrets = 3
			s.ai_max_barracks = 0
			s.unit_weights = _weights(5.0, 2.0, 0.5, 1.5, 0.0, 0.0)
		"hard":          # fast and frequent, more raiders and kamikazes, the enemy expands quickly
			s.spawn_interval = 0.7
			s.speed_scale = 1.15
			s.hp_scale = 1.3
			s.base_hp = 14
			s.ai_first_build_delay = 4.0
			s.ai_build_interval = 7.0
			s.ai_max_posts = 6
			s.ai_max_turrets = 14
			s.ai_max_barracks = 4
			s.ai_desperation_hp = 3
			s.unit_weights = _weights(4.0, 3.0, 2.0, 2.0, 3.0, 3.0)
		_:               # "normal": the defaults above, with each type's default weight
			pass
	return s


static func _weights(grunt: float, runner: float, brute: float, wanderer: float, raider: float, kamikaze: float) -> Dictionary:
	return {"grunt": grunt, "runner": runner, "brute": brute, "wanderer": wanderer, "raider": raider, "kamikaze": kamikaze}


func copy() -> EnemySettings:
	var c := EnemySettings.new()
	c.spawn_interval = spawn_interval
	c.speed_scale = speed_scale
	c.hp_scale = hp_scale
	c.base_hp = base_hp
	c.ai_enabled = ai_enabled
	c.ai_first_build_delay = ai_first_build_delay
	c.ai_build_interval = ai_build_interval
	c.ai_max_posts = ai_max_posts
	c.ai_max_turrets = ai_max_turrets
	c.ai_max_barracks = ai_max_barracks
	c.ai_threat_tracking = ai_threat_tracking
	c.ai_desperation_hp = ai_desperation_hp
	c.unit_weights = unit_weights.duplicate()
	return c
