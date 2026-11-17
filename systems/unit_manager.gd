class_name UnitManager
extends Node
## Owns the moving units: enemies (spawned forever at the enemy spawn points) and the player's mobs
## (spawned by Barracks). Enemy stats and behaviors come from data/enemy_defs.gd.

## How often enemies spawn, which types, and how tough they are comes from the level's EnemySettings
## (edit it in the level editor's "Enemy behavior" panel).

@export_group("Mobs")
@export var mob_speed := 1.1                 ## hexes per second
@export var mob_hp := 20.0
@export var mob_dps := 8.0                   ## damage a mob deals per second to what it is fighting
@export var enemy_melee_dps := 5.0           ## damage an enemy deals per second to the mob fighting it
@export var mob_melee_range := 0.9           ## world units
@export var mob_base_damage := 1             ## hit points an enemy base loses when a mob reaches it
## (mob types, their colors and behaviors: data/mob_defs.gd)

@export_group("Base minions")
@export var base_minion_interval := 6.0      ## seconds between minions spawned by your own base
@export var base_max_minions := 3            ## how many base minions may be alive at once
@export var base_minion_type := "marcher"    ## mob type from data/mob_defs.gd

var enemies: Array[Enemy] = []
var mobs: Array[Mob] = []

var _game: Game
var _spawn_timer := 0.0
var _base_timer := 0.0


func setup(game: Game) -> void:
	_game = game


func clear() -> void:
	for e in enemies:
		e.node.queue_free()
		e.partner = null                           # break the enemy <-> mob reference cycle so both can be freed
	for m in mobs:
		m.node.queue_free()
		m.partner = null
	enemies.clear()
	mobs.clear()
	_spawn_timer = 0.0
	_base_timer = base_minion_interval


func tick(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		var settings := _game.enemy_settings
		_spawn_timer = settings.spawn_interval
		spawn_enemy(EnemyDefs.pick_weighted(settings.unit_weights))
	_base_timer -= delta                           # the player's base spawns its own minions
	if _base_timer <= 0.0:
		_base_timer = base_minion_interval
		if mob_count(_game.board.base) < base_max_minions:
			spawn_mob(_game.board.base, base_minion_type)
	for e in enemies:
		_update_enemy(e, delta)
	for m in mobs:
		_update_mob(m, delta)


## Free the nodes of dead units and drop them from the lists. Called once per frame after everything has acted.
func cull() -> void:
	var live_enemies: Array[Enemy] = []
	for e in enemies:
		if e.dead:
			e.node.queue_free()
			e.partner = null
		else:
			live_enemies.append(e)
	enemies = live_enemies
	var live_mobs: Array[Mob] = []
	for m in mobs:
		if m.dead:
			m.node.queue_free()
			m.partner = null
		else:
			live_mobs.append(m)
	mobs = live_mobs


# ---------- Damage ----------

## Safe to call on an already-dead enemy.
func hit_enemy(e: Enemy, damage: float) -> void:
	if e.dead:
		return
	e.hp -= damage
	e.bar.scale.x = maxf(clampf(e.hp / e.max_hp, 0.0, 1.0), 0.01)
	GameEvents.enemy_hit.emit(e.node.position, damage)
	if e.hp <= 0.0:
		e.dead = true
		if not e.neutral:                              # neutral units don't count toward "defeat N enemies"
			_game.kills += 1
		GameEvents.enemy_died.emit(e.node.position)


func hit_mob(m: Mob, damage: float) -> void:
	if m.dead:
		return
	m.hp -= damage
	if m.hp <= 0.0:
		m.dead = true
		GameEvents.mob_died.emit(m.node.position)


# ---------- Enemies ----------

## Spawn an enemy at a random living enemy base, or at `at` if given (desperation summons use their own base).
## `home` marks units made by a barracks / den (see units_from); neutral defs (NeutralDefs.UNITS) make neutral units.
func spawn_enemy(def: Dictionary, at := HexGrid.NO_CELL, home := HexGrid.NO_CELL) -> void:
	var spawns := _game.board.spawns
	if spawns.is_empty() and at == HexGrid.NO_CELL:
		return
	var cell := at if at != HexGrid.NO_CELL else spawns[randi() % spawns.size()]
	var size: float = def["size"]

	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.28
	sphere.height = 0.56
	body.mesh = sphere
	body.material_override = Mats.outlined(def["color"])    # beat-reactive outline
	body.scale = Vector3.ONE * size
	body.position.y = 0.28 * size
	root.add_child(body)

	var bar := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.09)
	bar.mesh = quad
	bar.material_override = Mats.billboard_bar(Color("6fe07f"))
	bar.position.y = 0.6 + 0.4 * size
	root.add_child(bar)

	root.position = HexGrid.to_world(cell)
	add_child(root)

	var e := Enemy.new()
	e.def = def
	e.node = root
	e.bar = bar
	e.cell = cell
	e.prev = cell
	var settings := _game.enemy_settings
	e.neutral = def.get("neutral", false)
	e.home = home
	e.speed_scale = 1.0 if e.neutral else settings.speed_scale     # level difficulty only scales the enemy's own units
	e.hp = def["hp"] * (1.0 if e.neutral else settings.hp_scale)
	e.max_hp = e.hp
	e.wander_left = def.get("wander_time", 0.0)
	enemies.append(e)
	GameEvents.enemy_spawned.emit(root.position)


func _update_enemy(e: Enemy, delta: float) -> void:
	if e.dead:
		return
	if e.partner != null:
		if e.partner.dead or e.partner.partner != e:
			e.partner = null                           # the duel is over: carry on
		else:
			return                                     # locked in a duel: stand and fight (the mob deals the blows)
	var speed_mul := 1.0
	if e.slow_left > 0.0:                          # slowed by a Chill tower (or held up by a mob)
		e.slow_left -= delta
		speed_mul = e.slow_factor
	if e.neutral:
		_update_critter(e, speed_mul, delta)
		return

	# Behaviors that replace normal movement. To add a behavior, add a case here and to enemy_defs.gd.
	match e.def["behavior"]:
		"raider":
			var victim = _game.towers.nearest(e.node.position, HexGrid.HEX_W * 1.05, Team.PLAYER)
			if victim != null:                     # stop beside the tower and chew on it
				_game.towers.damage(victim, e.def["attack_dps"] * delta)
				return
		"kamikaze":
			var target = _game.towers.nearest(e.node.position, e.def["aggro_range"] * HexGrid.HEX_W, Team.PLAYER)
			if target != null:
				_charge(e, target, speed_mul, delta)
				return
	_follow_path(e, speed_mul, delta)


func _follow_path(e: Enemy, speed_mul: float, delta: float) -> void:
	if e.next == HexGrid.NO_CELL:
		e.next = _choose_next_cell(e)
		if e.next == HexGrid.NO_CELL:
			return
	if e.wander_left > 0.0:
		e.wander_left -= delta

	var target := HexGrid.to_world(e.next)
	var to_target := target - e.node.position
	var step: float = e.def["speed"] * e.speed_scale * HexGrid.HEX_W * speed_mul * delta
	if to_target.length() <= step:
		e.node.position = target
		e.prev = e.cell
		e.cell = e.next
		e.next = HexGrid.NO_CELL
		if e.cell == _game.board.base:
			e.dead = true
			GameEvents.enemy_reached_base.emit(e.node.position)
			_game.damage_base(1)
	else:
		e.node.position += to_target.normalized() * step


## Wanderers take random steps (avoiding an immediate U-turn) until their wander time runs out;
## everyone else steps to the neighbour closest to the base.
func _choose_next_cell(e: Enemy) -> Vector2i:
	var to_base := _game.pathing.to_base
	if e.wander_left > 0.0:
		var options: Array[Vector2i] = []
		for dir in HexGrid.DIRS:
			var n: Vector2i = e.cell + dir
			if to_base.has(n) and n != e.prev:
				options.append(n)
		if not options.is_empty():
			return options[randi() % options.size()]
	var best := HexGrid.NO_CELL
	var best_d := 1 << 30
	for dir in HexGrid.DIRS:
		var n: Vector2i = e.cell + dir
		if to_base.has(n) and to_base[n] < best_d:
			best_d = to_base[n]
			best = n
	return best


## Kamikaze: run straight at the tower (ignoring the path), then explode, hurting every player tower nearby.
func _charge(e: Enemy, target_cell: Vector2i, speed_mul: float, delta: float) -> void:
	var to_target := HexGrid.to_world(target_cell) - e.node.position
	to_target.y = 0.0
	if to_target.length() <= 0.7:
		var reach: float = HexGrid.HEX_W * 0.5 + e.def["blast_radius"] * HexGrid.HEX_W
		for c in _game.towers.towers.keys():
			var t: Tower = _game.towers.towers[c]
			if t.side == Team.PLAYER and e.node.position.distance_to(HexGrid.to_world(c)) <= reach:
				_game.towers.damage(c, e.def["blast_damage"])
		e.dead = true
		GameEvents.explosion.emit(e.node.position)
		return
	e.node.position += to_target.normalized() * e.def["charge_speed"] * e.speed_scale * HexGrid.HEX_W * speed_mul * delta
	e.cell = HexGrid.from_world(e.node.position)     # a charger that survives resumes the path from here
	e.next = HexGrid.NO_CELL


## Neutral units (see NeutralDefs): wander near their den and fight whatever comes close, enemy units and your mobs
## alike. Units already locked in a duel are left alone. Your towers and mobs fight them like any enemy.
func _update_critter(e: Enemy, speed_mul: float, delta: float) -> void:
	var dps: float = e.def["melee_dps"]
	var foe_enemy: Enemy = null
	var foe_mob: Mob = null
	var best := mob_melee_range
	for other in enemies:
		if other.dead or other.neutral or other.partner != null:
			continue
		var d := e.node.position.distance_to(other.node.position)
		if d <= best:
			best = d
			foe_enemy = other
			foe_mob = null
	for m in mobs:
		if m.dead or m.partner != null:
			continue
		var d := e.node.position.distance_to(m.node.position)
		if d <= best:
			best = d
			foe_mob = m
			foe_enemy = null
	if foe_enemy != null:
		hit_enemy(foe_enemy, dps * delta)
		hit_enemy(e, enemy_melee_dps * delta)          # it hits back
		return
	if foe_mob != null:
		hit_mob(foe_mob, dps * delta)
		hit_enemy(e, mob_dps * delta)
		return

	if e.next == HexGrid.NO_CELL:
		e.next = _critter_next_cell(e)
		if e.next == HexGrid.NO_CELL:
			return
	var target := HexGrid.to_world(e.next)
	var to_target := target - e.node.position
	var step: float = e.def["speed"] * HexGrid.HEX_W * speed_mul * delta
	if to_target.length() <= step:
		e.node.position = target
		e.prev = e.cell
		e.cell = e.next
		e.next = HexGrid.NO_CELL
	else:
		e.node.position += to_target.normalized() * step


## A random free neighbour hex within the unit's leash of its den (avoiding an immediate U-turn).
func _critter_next_cell(e: Enemy) -> Vector2i:
	var anchor := e.home if e.home != HexGrid.NO_CELL else e.cell
	var options: Array[Vector2i] = []
	for dir in HexGrid.DIRS:
		var n: Vector2i = e.cell + dir
		if _game.board.is_walkable(n) and n != _game.board.base and not _game.board.is_spawn(n) \
				and not _game.towers.towers.has(n) and HexGrid.distance(anchor, n) <= e.def["leash"]:
			options.append(n)
	if options.size() > 1:
		options.erase(e.prev)
	if options.is_empty():
		return HexGrid.NO_CELL
	return options[randi() % options.size()]


## How many living units were made by the barracks / den on `cell`.
func units_from(cell: Vector2i) -> int:
	var n := 0
	for e in enemies:
		if not e.dead and e.home == cell:
			n += 1
	return n


# ---------- Mobs ----------

func mob_count(owner_cell: Vector2i) -> int:
	var n := 0
	for m in mobs:
		if not m.dead and m.owner_cell == owner_cell:
			n += 1
	return n


## `mob_key` picks the mob type from data/mob_defs.gd.
## `tracked` = false makes a mob that doesn't count toward its spawner's cap (spell-summoned mobs).
func spawn_mob(owner_cell: Vector2i, mob_key := "marcher", tracked := true) -> void:
	var def: Dictionary = MobDefs.TYPES[mob_key]
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	body.mesh = box
	body.material_override = Mats.outlined(def["color"])     # same beat-reactive outline as enemies
	body.position.y = 0.22
	root.add_child(body)
	root.position = HexGrid.to_world(owner_cell)
	add_child(root)

	var m := Mob.new()
	m.def = def
	m.node = root
	m.owner_cell = owner_cell if tracked else HexGrid.NO_CELL
	m.cell = owner_cell
	m.prev = owner_cell
	m.hp = mob_hp * def["hp_mult"]
	m.wander_left = def.get("wander_time", 0.0)
	mobs.append(m)
	GameEvents.mob_spawned.emit(root.position)


## Flow toward the player's rally point (an enemy spawn by default): only step to a cell closer to it.
## Wanderers instead take random steps (avoiding a U-turn) until their wander time runs out.
func _choose_mob_cell(m: Mob) -> Vector2i:
	var to_rally := _game.pathing.to_rally
	if m.wander_left > 0.0:
		var options: Array[Vector2i] = []
		for dir in HexGrid.DIRS:
			var n: Vector2i = m.cell + dir
			if to_rally.has(n) and n != m.prev:
				options.append(n)
		if not options.is_empty():
			return options[randi() % options.size()]
	var best := HexGrid.NO_CELL
	var best_d: int = to_rally.get(m.cell, 1 << 30)
	for dir in HexGrid.DIRS:
		var n: Vector2i = m.cell + dir
		if to_rally.has(n) and to_rally[n] < best_d:
			best_d = to_rally[n]
			best = n
	return best


## One-on-one fights. A free mob that passes within melee range of a free, non-elusive enemy pairs with it; from then
## on the two ignore everyone else, stand still and trade blows until one dies. Returns true while the mob is paired
## (it has done its fighting for this frame), false if it is free to move on.
func _duel(m: Mob, delta: float) -> bool:
	if m.partner != null and (m.partner.dead or m.partner.partner != m):
		m.partner = null
	if m.partner == null and not m.def.get("elusive", false):
		var best := mob_melee_range
		for e in enemies:
			if e.dead or e.def.get("elusive", false):
				continue
			if e.partner != null and not e.partner.dead:
				continue                               # already paired up with someone
			var d := m.node.position.distance_to(e.node.position)
			if d <= best:
				best = d
				m.partner = e
		if m.partner != null:
			m.partner.partner = m
	if m.partner == null:
		return false
	hit_enemy(m.partner, mob_dps * delta)
	hit_mob(m, enemy_melee_dps * delta)
	return true


## Mobs follow their behavior (see _choose_mob_cell), brawl with any enemy they bump into, and tear down
## enemy structures they pass beside.
func _update_mob(m: Mob, delta: float) -> void:
	if m.dead:
		return
	var slow_mul := 1.0
	if m.slow_left > 0.0:                              # chilled by an enemy slow tower
		m.slow_left -= delta
		slow_mul = m.slow_factor
	if m.haste_left > 0.0:                             # sped up by the Haste spell
		m.haste_left -= delta
		slow_mul *= m.haste_mult
	if m.def.get("pairs_up", false) and _duel(m, delta):
		return
	var foe: Enemy = null
	var best := mob_melee_range
	for e in enemies:
		if e.dead:
			continue
		var d := m.node.position.distance_to(e.node.position)
		if d <= best:
			best = d
			foe = e
	if foe != null:
		hit_enemy(foe, mob_dps * delta)
		foe.slow_left = maxf(foe.slow_left, 0.15)            # the mob holds the enemy up
		foe.slow_factor = minf(foe.slow_factor, 0.1)
		hit_mob(m, enemy_melee_dps * delta)
		return

	var structure = _game.towers.nearest_foe(m.node.position, HexGrid.HEX_W * 1.05)    # enemy or neutral structures
	if structure != null:
		_game.towers.damage(structure, mob_dps * delta)
		return

	if m.next == HexGrid.NO_CELL:
		m.next = _choose_mob_cell(m)
		if m.next == HexGrid.NO_CELL:
			return                                    # already at the rally point: stand guard
	if m.wander_left > 0.0:
		m.wander_left -= delta
	var target := HexGrid.to_world(m.next)
	var to_target := target - m.node.position
	var step: float = mob_speed * m.def["speed_mult"] * HexGrid.HEX_W * slow_mul * delta
	if to_target.length() <= step:
		m.node.position = target
		m.prev = m.cell
		m.cell = m.next
		m.next = HexGrid.NO_CELL
		_game.ai.note_pass(m.cell)                    # the enemy commander tracks where your units walk
		if m.cell == _game.rally.cell and _game.board.is_spawn(m.cell):     # marched on an enemy base
			m.dead = true
			GameEvents.mob_reached_spawn.emit(m.node.position)
			_game.damage_enemy_base(m.cell, mob_base_damage)
	else:
		m.node.position += to_target.normalized() * step
