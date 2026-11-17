class_name EnemyAI
extends Node
## The enemy's builder brain. Every few seconds it places either a command post (pushing its territory
## toward the player's base) or a turret near its frontier. It only builds inside its own territory,
## never inside the player's, and never walls off the route between a spawn and the base.
## Timings and limits come from the level's EnemySettings; structure definitions live in data/enemy_defs.gd.
##
## Threat map: every time one of your mobs steps onto a hex, that hex's threat goes up; threat fades over time.
## Turrets are placed where they cover the most threat (hexes already covered by enemy turrets count for less), so
## the commander reinforces the routes you actually use. Command posts still push toward your base.
##
## Desperation (on for a level whenever EnemySettings.ai_desperation_hp is 1 or more). Each enemy base can use two
## abilities, once each:
##   Retreat  at half HP the base relocates to a safer hex (behind its own lines, out of your turf) and the commander
##            builds two structures right away, ignoring the turret cap.
##   Burst    at EnemySettings.ai_desperation_hp the base unleashes a shockwave that destroys every one of
##            your mobs near it, becomes invincible for a few seconds, and spawns a burst of units.

@export_group("Threat")
@export var threat_half_life := 25.0         ## seconds for the remembered threat of a hex to halve
@export var threat_react_level := 2.0        ## covered threat needed before a turret is aimed at it (about 2 recent passes)

@export_group("Desperation")
@export_range(0.1, 0.9) var retreat_hp_fraction := 0.5   ## the base relocates once its HP falls to this fraction of its max
@export var retreat_builds := 2              ## structures placed when it relocates
@export var shockwave_radius := 3.0          ## hexes: every mob of yours this close to the base is destroyed by the burst
@export var invulnerable_time := 3.0         ## seconds the base cannot be damaged after the burst
@export var summon_count := 4                ## units spawned by the burst

var threat: Dictionary = {}                  ## Vector2i -> remembered number of your units that passed over it

var _game: Game
var _timer := 0.0
var _retreated: Dictionary = {}              ## enemy base cell -> true once it has used its retreat
var _burst: Dictionary = {}                  ## enemy base cell -> true once it has used its burst
var _invulnerable: Dictionary = {}           ## enemy base cell -> seconds of invincibility left


func setup(game: Game) -> void:
	_game = game


func reset() -> void:
	_timer = _game.enemy_settings.ai_first_build_delay
	threat.clear()
	_retreated.clear()
	_burst.clear()
	_invulnerable.clear()


func tick(delta: float) -> void:
	for c in _invulnerable.keys():                 # invincibility wears off even if the commander can't build
		_invulnerable[c] -= delta
		if _invulnerable[c] <= 0.0:
			_invulnerable.erase(c)
	var settings := _game.enemy_settings
	if not settings.ai_enabled:
		return
	_decay_threat(delta)
	_timer -= delta
	if _timer <= 0.0:
		_timer = settings.ai_build_interval
		_build_something(settings, false)


# ---------- Threat map ----------

## One of the player's units stepped onto `c` (called by UnitManager).
func note_pass(c: Vector2i) -> void:
	var settings := _game.enemy_settings
	if settings.ai_enabled and settings.ai_threat_tracking:
		threat[c] = float(threat.get(c, 0.0)) + 1.0


func _decay_threat(delta: float) -> void:
	var keep := pow(0.5, delta / maxf(threat_half_life, 0.1))
	for c in threat.keys():
		var v: float = threat[c] * keep
		if v < 0.05:
			threat.erase(c)
		else:
			threat[c] = v


func _total_threat() -> float:
	var total := 0.0
	for v in threat.values():
		total += v
	return total


## The threat on `c`, divided by one more for each enemy turret already covering it: covered ground worries the
## commander less, which stops it stacking every turret on the same hex.
func _effective_threat(c: Vector2i) -> float:
	var covering := 0
	for t: Tower in _game.towers.towers.values():
		if t.side == Team.ENEMY and t.kind == "shot" and HexGrid.distance(t.cell, c) <= t.def["range"]:
			covering += 1
	return float(threat[c]) / (1.0 + covering)


## The best turret cell among `candidates` (closest-to-base order is kept as a tie-break): the one covering the most
## effective threat, as long as that reaches threat_react_level and the cell keeps the route open. NO_CELL if none.
func _pick_threat_cell(candidates: Array[Vector2i], def: Dictionary) -> Vector2i:
	if threat.is_empty():
		return HexGrid.NO_CELL
	var hot := {}                                             # threatened hex -> effective threat
	for c in threat:
		hot[c] = _effective_threat(c)
	var scored: Array = []
	for cand in candidates:
		var score := 0.0
		for c in hot:
			if HexGrid.distance(cand, c) <= def["range"]:
				score += hot[c]
		if score >= threat_react_level:
			scored.append([score, cand])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])   # stable enough: ties keep base order
	for entry in scored:
		if _game.pathing.keeps_route_open(entry[1]):
			return entry[1]
	return HexGrid.NO_CELL


# ---------- Building ----------

## Choose what to build: "post", "turret", "sniper", "slow" (a slow tower) or "barracks" (or "" for nothing this round).
## Everything that isn't a post counts toward the turret cap; barracks also have their own cap. While your units are
## busy hexes the commander leans toward turrets and slow towers. `ignore_caps` (desperation) lifts the turret cap.
func _choose_kind(settings: EnemySettings, ignore_caps: bool) -> String:
	var posts := _game.towers.count_kind(Team.ENEMY, "command")
	var turrets := _game.towers.count_side(Team.ENEMY) - posts
	var busy := settings.ai_threat_tracking and _total_threat() >= threat_react_level
	# Keep roughly two turrets per post, with some randomness (less of it while there is a threat to answer).
	var want_post := posts < settings.ai_max_posts and (turrets >= posts * 2 or (not busy and randf() < 0.35))
	if want_post:
		return "post"
	if turrets >= settings.ai_max_turrets and not ignore_caps:
		return ""
	# Weighted pick. While your units are busy on a route, snipers and slow towers are favored and barracks are not.
	var weights := {"turret": 5.0, "sniper": 3.0 if busy else 1.5, "slow": 3.0 if busy else 1.5}
	if not busy and _game.towers.count_kind(Team.ENEMY, "spawner") < settings.ai_max_barracks:
		weights["barracks"] = 1.5
	var total := 0.0
	for w in weights.values():
		total += w
	var roll := randf() * total
	for kind in weights:
		roll -= weights[kind]
		if roll <= 0.0:
			return kind
	return "turret"


## Place one structure. Returns true if something was built.
func _build_something(settings: EnemySettings, ignore_caps: bool) -> bool:
	var kind := _choose_kind(settings, ignore_caps)
	if kind == "":
		return false
	var cell := _pick_cell(kind)
	if cell == HexGrid.NO_CELL:
		return false
	_game.towers.place(cell, EnemyDefs.STRUCTURES[kind], Team.ENEMY)
	return true


## A free cell in enemy territory (outside the player's) for a structure of type `kind` (a key of
## EnemyDefs.STRUCTURES). Posts take the cell closest to the player's base. Turrets and slow towers go where they
## cover the most threat; otherwise (and for barracks) they pick randomly among the best few cells closest to the base.
func _pick_cell(kind: String) -> Vector2i:
	var for_post := kind == "post"
	var board := _game.board
	var def: Dictionary = EnemyDefs.STRUCTURES[kind]
	var candidates: Array[Vector2i] = []
	for c in board.tiles:       # command posts may also go 1 hex outside enemy turf (Territory.allows)
		if board.is_walkable(c) and c != board.base and not board.is_spawn(c) and not _game.towers.towers.has(c) \
				and c != _game.rally.cell \
				and _game.territory.allows(Team.ENEMY, c, def) and not _game.territory.contains(Team.PLAYER, c):
			candidates.append(c)
	candidates.shuffle()                                      # random tie-breaks
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return HexGrid.distance(a, board.base) < HexGrid.distance(b, board.base))

	if (kind == "turret" or kind == "sniper" or kind == "slow") and _game.enemy_settings.ai_threat_tracking:
		var answer := _pick_threat_cell(candidates, def)
		if answer != HexGrid.NO_CELL:
			return answer

	var valid: Array[Vector2i] = []
	for c in candidates:
		if _game.pathing.keeps_route_open(c):
			valid.append(c)
			if for_post or valid.size() >= 5:
				break
	if valid.is_empty():
		return HexGrid.NO_CELL
	return valid[0] if for_post else valid[randi() % valid.size()]


# ---------- Desperation ----------

## True while the base on `cell` is invincible (Game ignores damage to it).
func is_invulnerable(cell: Vector2i) -> bool:
	return _invulnerable.has(cell)


## An enemy base took damage and is still standing (called by Game; the base may have moved by the time it returns).
## Each ability fires once per base: the retreat at half HP, then the burst at ai_desperation_hp.
func on_base_hurt(cell: Vector2i, hp: float, max_hp: float) -> void:
	var settings := _game.enemy_settings
	if not settings.desperation_on():
		return
	if not _retreated.has(cell) and hp <= max_hp * retreat_hp_fraction:
		_retreated[cell] = true
		cell = _retreat(cell, settings)
	if not _burst.has(cell) and hp <= float(settings.ai_desperation_hp):
		_burst[cell] = true
		_unleash_burst(cell, settings)


## Retreat: relocate the base to a safer hex (if there is one) and build structures at once. Returns the base's cell.
func _retreat(cell: Vector2i, settings: EnemySettings) -> Vector2i:
	var target := _pick_base_cell(cell)
	if target != HexGrid.NO_CELL:
		_game.relocate_enemy_base(cell, target)
		for state: Dictionary in [_retreated, _burst]:           # the base keeps its history under its new cell
			if state.has(cell):
				state.erase(cell)
				state[target] = true
		_retreated[target] = true
		cell = target
	for _i in retreat_builds:
		_build_something(settings, true)
	return cell


## A hex the base can retreat to: floor, free, outside your turf and connected to your base. It prefers the ones
## farthest (by walking distance) from your base, picking at random among the best few.
func _pick_base_cell(current: Vector2i) -> Vector2i:
	var board := _game.board
	var reach := _game.pathing.to_base
	var candidates: Array[Vector2i] = []
	for c in board.tiles:
		if c != current and c != board.base and board.is_walkable(c) and not board.is_spawn(c) \
				and not _game.towers.towers.has(c) and c != _game.rally.cell and reach.has(c) \
				and not _game.territory.contains(Team.PLAYER, c):
			candidates.append(c)
	if candidates.is_empty():
		return HexGrid.NO_CELL
	candidates.shuffle()
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return reach[a] > reach[b])
	return candidates[randi() % mini(candidates.size(), 5)]


## Burst: destroy all of your mobs near the base, become invincible for a few seconds and spawn a pack of units.
func _unleash_burst(cell: Vector2i, settings: EnemySettings) -> void:
	var origin := HexGrid.to_world(cell)
	var reach := shockwave_radius * HexGrid.HEX_W
	for m in _game.units.mobs:
		if not m.dead and m.node.position.distance_to(origin) <= reach:
			_game.units.hit_mob(m, m.hp)
	GameEvents.explosion.emit(origin)
	_invulnerable[cell] = invulnerable_time
	for _i in summon_count:
		_game.units.spawn_enemy(EnemyDefs.pick_weighted(settings.unit_weights), cell)
