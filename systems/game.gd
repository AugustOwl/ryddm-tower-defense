class_name Game
extends Node3D
## The root of the game. It owns no gameplay rules itself; it wires the systems together, switches between
## playing and the level editor, and ticks the systems each frame in a fixed order.
##
## Systems (child nodes, see main.tscn):
##   Board            the level's tiles, walls and markers          (board/board.gd)
##   Territory        who may build where + the glowing outlines    (systems/territory.gd)
##   TowerManager     towers: placing, damage, attacks              (systems/tower_manager.gd)
##   UnitManager      enemies and the player's mobs                 (systems/unit_manager.gd)
##   EnemyAI          the enemy's structure building                (systems/enemy_ai.gd)
##   PlayerController AP, the card hand, placing towers             (systems/player_controller.gd)
##   LevelEditor      in-game level editor                          (systems/level_editor.gd)
##   CameraRig        isometric camera, pan and zoom                (systems/camera_rig.gd)
##   Effects          particles and other music-synced visuals      (fx/effects.gd)
##   Hud              cards, AP stars, debug text                   (ui/hud.gd)
## Pathing (board/pathing.gd) is a plain object owned here. Singletons: Conductor (music clock) and
## GameEvents (event bus) are autoloads.

enum Mode { PLAY, EDIT, MENU }

@export_group("Bases")
@export var base_max_hp := 20                     ## your base's hit points (enemy bases: see the level's EnemySettings)
@export var tower_base_damage_scale := 0.1        ## towers hurt enemy bases for this fraction of their normal damage

@export_group("Starting level")
@export var show_menu_on_start := true            ## open the start menu first (off = jump straight into the level below)
@export var level: LevelData                      ## drag a saved level from res://levels here (blank = classic disc)
@export var random_map_on_start := false          ## start on a freshly generated map instead
@export var random_seed := 0                      ## 0 = a different map every time
@export_group("Music")
@export var music: AudioStream                    ## your own track (.mp3 / .ogg / .wav in the project); blank = the generated drum loop
@export_group("Random map defaults")              ## also the editor toolbar's starting values
@export var random_radius := 8
@export_range(0.3, 0.8) var random_fill := 0.7
@export_range(0.0, 0.25) var random_walls := 0.07
@export_range(1, 4) var random_spawns := 1

var mode: int = Mode.PLAY                          ## PLAY, EDIT (level creator) or MENU (start menu)
var base_hp := 0
var enemy_base_hp := {}                           ## enemy base cell -> hit points left
var kills := 0
var game_over := false
var play_time := 0.0                              ## seconds of game time since the run started
var pathing := Pathing.new()

## The current level's settings (all edited in the level creator, saved with the level).
var enemy_settings: EnemySettings:
	get:
		return board.level.enemy
var rules: LevelRules:
	get:
		return board.level.rules

@onready var board: Board = $Board
@onready var territory: Territory = $Territory
@onready var towers: TowerManager = $TowerManager
@onready var units: UnitManager = $UnitManager
@onready var ai: EnemyAI = $EnemyAI
@onready var player: PlayerController = $PlayerController
@onready var rally: RallyController = $RallyController
@onready var director: MusicDirector = $MusicDirector
@onready var campaign: Campaign = $Campaign
@onready var menu: MainMenu = $MainMenu
@onready var editor: LevelEditor = $LevelEditor
@onready var camera: CameraRig = $Camera3D
@onready var effects: Effects = $Effects
@onready var hud: Hud = $HUD
@onready var popup: GameOverPopup = $GameOverPopup


func _ready() -> void:
	_setup_environment()
	pathing.setup(board, towers.towers)
	for system in [territory, towers, units, ai, player, rally, director, campaign, editor]:
		system.setup(self)
	load_level(_starting_level())
	if show_menu_on_start:
		enter_menu()


func _starting_level() -> LevelData:
	if level != null:
		return level.copy()
	if random_map_on_start:
		return MapGenerator.generate(random_seed, random_radius, random_fill, random_walls, random_spawns)
	return LevelData.make_disc(7)


# ---------- Levels and modes ----------

## Replace the current level and start fresh on it.
func load_level(data: LevelData) -> void:
	board.level = data
	camera.fit(data.bounds())
	reset_state()                                 # also builds the board from the level


## Throw away everything that happened (towers, units, AP...) but keep the level.
func reset_state() -> void:
	board.refresh()                               # rebuilds from the level, so destroyed enemy bases come back
	units.clear()
	towers.clear()
	ai.reset()
	player.reset()
	base_hp = base_max_hp
	enemy_base_hp.clear()
	for spawn in board.spawns:
		enemy_base_hp[spawn] = float(enemy_settings.base_hp)
	kills = 0
	play_time = 0.0
	game_over = false
	apply_style()
	director.reset()
	rally.reset()
	pathing.refresh()
	territory.refresh()
	_refresh_base_labels()


## The editor changed the LevelData: rebuild everything derived from it.
func level_edited() -> void:
	board.refresh()
	apply_style()
	rally.reset()
	pathing.refresh()
	territory.refresh()


## The start menu: shown over the board; nothing runs until a level is chosen.
func enter_menu() -> void:
	mode = Mode.MENU
	campaign.stop()
	reset_state()
	hud.set_play_ui_visible(false)
	player.set_cursor_visible(false)
	rally.set_flag_visible(false)
	editor.exit()
	menu.open()


func enter_edit() -> void:
	mode = Mode.EDIT
	campaign.stop()
	reset_state()
	hud.set_play_ui_visible(false)
	player.set_cursor_visible(false)
	rally.set_flag_visible(false)
	editor.enter()


func start_play() -> void:
	mode = Mode.PLAY
	reset_state()
	hud.set_play_ui_visible(true)
	rally.set_flag_visible(true)
	editor.exit()


## Push the level's look to the board and to every music-reactive shader (the accent color).
func apply_style() -> void:
	board.apply_style()
	RenderingServer.global_shader_parameter_set(&"beat_color", board.level.style.accent_color)


## An enemy reached the player's base. When it falls, the game is lost.
func damage_base(amount: int) -> void:
	if game_over:
		return
	base_hp = maxi(base_hp - amount, 0)
	_refresh_base_labels()
	if base_hp <= 0:
		end_game(false)


## A mob reached an enemy base, or a tower shot it. A base at 0 HP is destroyed; when the last one falls, the game is won.
func damage_enemy_base(cell: Vector2i, amount: float) -> void:
	if game_over or not enemy_base_hp.has(cell) or ai.is_invulnerable(cell):
		return
	enemy_base_hp[cell] -= amount
	if enemy_base_hp[cell] > 0:
		# May trigger desperation abilities, which can even move this base to another hex (so `cell` is stale after).
		ai.on_base_hurt(cell, enemy_base_hp[cell], float(enemy_settings.base_hp))
	else:
		enemy_base_hp.erase(cell)
		GameEvents.base_destroyed.emit(HexGrid.to_world(cell))
		board.destroy_spawn(cell)
		if rally.cell == cell:
			rally.reset()                         # the flag was on the destroyed base: pick another
		pathing.refresh()
		territory.refresh()
		if board.spawns.is_empty():
			end_game(true, "All enemy bases destroyed!")
	_refresh_base_labels()


## An enemy base picks itself up and moves to `to` (keeping its HP). The rally flag resets if it was on the old hex.
func relocate_enemy_base(from: Vector2i, to: Vector2i) -> void:
	if not enemy_base_hp.has(from):
		return
	enemy_base_hp[to] = enemy_base_hp[from]
	enemy_base_hp.erase(from)
	board.move_spawn(from, to)
	if rally.cell == from:
		rally.reset()
	pathing.refresh()
	territory.refresh()
	_refresh_base_labels()


## Show the result and offer a restart of the current level. Ignored outside play mode.
func end_game(victory: bool, reason := "") -> void:
	if game_over or mode != Mode.PLAY:
		return
	game_over = true
	player.cancel_card()
	rally.cancel()
	popup.show_result(victory, kills, reason)


## Cell of the closest living enemy base within `max_dist` world units of `pos`, or null.
func nearest_enemy_base(pos: Vector3, max_dist: float) -> Variant:
	var best = null
	var best_d := max_dist
	for cell in enemy_base_hp:
		var d := pos.distance_to(HexGrid.to_world(cell))
		if d <= best_d:
			best_d = d
			best = cell
	return best


func _refresh_base_labels() -> void:
	board.set_label(board.base, "BASE  %d" % base_hp)
	for spawn in board.spawns:
		board.set_label(spawn, "ENEMY BASE  %d" % ceili(enemy_base_hp.get(spawn, 0.0)))


# ---------- Per-frame ----------

func _process(delta: float) -> void:
	if mode == Mode.PLAY and not game_over:
		player.tick(delta)
		units.tick(delta)
		ai.tick(delta)
		towers.tick(delta)
		units.cull()
		director.tick(delta)
		play_time += delta
		_check_win_condition()
	territory.set_glow(Conductor.slow_amount)
	hud.update_debug(self)
	hud.update_objective(self)


## The level's extra win condition (destroying all enemy bases is always a win and is handled elsewhere).
func _check_win_condition() -> void:
	match rules.win_mode:
		LevelRules.SURVIVE:
			if play_time >= rules.survive_seconds:
				end_game(true, "You survived!")
		LevelRules.KILLS:
			if kills >= rules.kill_target:
				end_game(true, "Enemy quota defeated!")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2 and mode != Mode.MENU:        # the start menu has its own Level creator button
			if mode == Mode.PLAY:
				enter_edit()
			elif board.level.validate() == "":
				start_play()
			else:
				editor.say("Can't play yet: " + board.level.validate())
		elif event.keycode == KEY_F3:
			hud.toggle_debug()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("12151c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8a96b0")
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
