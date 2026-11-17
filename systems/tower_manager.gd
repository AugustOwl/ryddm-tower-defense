class_name TowerManager
extends Node
## Owns every tower and enemy structure: placing, removing, damaging, and what each one does every frame.

@export var default_tower_hp := 50.0         ## hit points of towers whose definition has no "hp"

var towers: Dictionary = {}                  ## Vector2i -> Tower
var _game: Game


func setup(game: Game) -> void:
	_game = game


# ---------- Queries ----------

## Can the player build the card `def` on this cell right now? Normal towers need the cell to be in the player's
## turf. Command towers may go 1 hex outside it and infiltrators `infiltrate` hexes, never onto enemy turf
## (see Territory.allows).
func can_place(c: Vector2i, def := {}) -> bool:
	var board := _game.board
	if not board.is_walkable(c) or c == board.base or board.is_spawn(c) or towers.has(c) or c == _game.rally.cell:
		return false
	return _game.territory.allows(Team.PLAYER, c, def) and _game.pathing.keeps_route_open(c)


## Cell of the closest tower of `side` within `max_dist` world units of `pos`, or null.
func nearest(pos: Vector3, max_dist: float, side: int) -> Variant:
	var best = null
	var best_d := max_dist
	for c in towers:
		if towers[c].side != side:
			continue
		var d := pos.distance_to(HexGrid.to_world(c))
		if d <= best_d:
			best_d = d
			best = c
	return best


## Extra AP per second from the player's farms.
func ap_bonus() -> float:
	var total := 0.0
	for t: Tower in towers.values():
		if t.side == Team.PLAYER and t.kind == "farm":
			total += t.def["ap_bonus"]
	return total


func count_kind(side: int, kind: String) -> int:
	var n := 0
	for t: Tower in towers.values():
		if t.side == side and t.kind == kind:
			n += 1
	return n


func count_side(side: int) -> int:
	var n := 0
	for t: Tower in towers.values():
		if t.side == side:
			n += 1
	return n


# ---------- Changes ----------

## `silent` skips the placement event (used when a level builds its own structures at the start).
func place(c: Vector2i, def: Dictionary, side: int, silent := false) -> void:
	towers[c] = _build(c, def, side)
	if not silent:
		GameEvents.tower_placed.emit(HexGrid.to_world(c))
	_changed()


## Cell of the closest enemy OR neutral structure within `max_dist` of `pos`, or null (what your mobs and towers attack).
func nearest_foe(pos: Vector3, max_dist: float) -> Variant:
	var best = null
	var best_d := max_dist
	for c in towers:
		if towers[c].side == Team.PLAYER:
			continue
		var d := pos.distance_to(HexGrid.to_world(c))
		if d <= best_d:
			best_d = d
			best = c
	return best


func remove(c: Vector2i) -> void:
	if not towers.has(c):
		return
	towers[c].node.queue_free()
	towers.erase(c)
	GameEvents.tower_removed.emit(HexGrid.to_world(c))
	_changed()


## Remove everything without events (used when a level is loaded or restarted).
func clear() -> void:
	for t: Tower in towers.values():
		t.node.queue_free()
	towers.clear()


func damage(c: Vector2i, amount: float) -> void:
	if not towers.has(c):
		return
	var t: Tower = towers[c]
	t.hp -= amount
	t.bar.visible = true
	t.bar.scale.x = maxf(clampf(t.hp / t.max_hp, 0.0, 1.0), 0.01)
	if t.hp <= 0.0:
		GameEvents.tower_destroyed.emit(HexGrid.to_world(c))
		remove(c)


## Towers block paths and command towers shape territory, so refresh both whenever the set of towers changes.
func _changed() -> void:
	_game.pathing.refresh()
	_game.territory.refresh()


# ---------- Building the visuals ----------

func _build(c: Vector2i, def: Dictionary, side: int) -> Tower:
	var accent: Color = def["accent"]
	var root := Node3D.new()
	root.position = HexGrid.to_world(c)

	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.radial_segments = 6
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.7
	cyl.height = 0.5
	body.mesh = cyl
	body.material_override = Mats.make(def["color"])
	body.position.y = 0.25
	if def["kind"] == "wall":                        # a tall plain block
		cyl.top_radius = 0.7
		cyl.height = 0.9
		body.position.y = 0.45
	root.add_child(body)

	var turret := Node3D.new()
	turret.position.y = 0.65
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.28
	sphere.height = 0.56
	head.mesh = sphere
	head.material_override = Mats.make(accent)
	if def["kind"] != "wall":                        # walls have no head or barrel
		turret.add_child(head)
	else:
		head.free()
	if not ["farm", "spawner", "command", "wall"].has(def["kind"]):    # only attackers get a barrel
		var barrel := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.7, 0.12, 0.12)
		barrel.mesh = box
		barrel.material_override = Mats.make(accent.lightened(0.5))
		barrel.position.x = 0.35
		turret.add_child(barrel)
	root.add_child(turret)

	var bar := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.1)
	bar.mesh = quad
	var bar_color := Color("6fe07f")                  # player
	if side == Team.ENEMY:
		bar_color = Color("ff6b5a")
	elif side == Team.NEUTRAL:
		bar_color = Color("e8e07a")
	bar.material_override = Mats.billboard_bar(bar_color)
	bar.position.y = 1.35
	bar.visible = false
	root.add_child(bar)
	add_child(root)

	var t := Tower.new()
	t.cell = c
	t.side = side
	t.def = def
	t.kind = def["kind"]
	t.range_world = def["range"] * HexGrid.HEX_W
	t.hp = def.get("hp", default_tower_hp)
	t.max_hp = t.hp
	t.node = root
	t.turret = turret
	t.bar = bar
	return t


# ---------- Per-frame behavior ----------

func tick(delta: float) -> void:
	for c in towers.keys():                  # copy: towers can be destroyed while we iterate
		var t: Tower = towers.get(c)
		if t == null:
			continue
		t.cooldown -= delta
		if t.side == Team.ENEMY:
			_tick_enemy_tower(t)
		elif t.side == Team.NEUTRAL:
			_tick_neutral_tower(t)
		else:
			_tick_player_tower(t)


func _tick_player_tower(t: Tower) -> void:
	if t.kind == "farm" or t.kind == "wall":
		return                                         # farms only generate AP (see PlayerController); walls just stand
	if t.kind == "spawner":
		if t.cooldown <= 0.0:
			t.cooldown = t.def["rate"]
			if _game.units.mob_count(t.cell) < t.def["max_mobs"]:
				_game.units.spawn_mob(t.cell, t.def.get("mob", "marcher"))
		return

	var pos := HexGrid.to_world(t.cell)
	var origin := pos + Vector3(0, 0.65, 0)
	var target := _nearest_enemy(pos, t.range_world)
	if target == null:
		if t.kind == "shot" and t.cooldown <= 0.0:    # no units around: shoot enemy structures, then enemy bases, in range
			var victim = nearest_foe(pos, t.range_world)          # enemy or neutral structures
			if victim != null:
				t.cooldown = t.def["rate"]
				_aim(t, HexGrid.to_world(victim) - pos)
				damage(victim, t.def["damage"])
				_game.effects.beam(origin, HexGrid.to_world(victim) + Vector3(0, 0.4, 0), Color("ffe27a"))
				GameEvents.tower_fired.emit(pos)
			else:                                         # nothing else to shoot: hit an enemy base in range
				var enemy_base = _game.nearest_enemy_base(pos, t.range_world)
				if enemy_base != null:
					t.cooldown = t.def["rate"]
					_aim(t, HexGrid.to_world(enemy_base) - pos)
					_game.damage_enemy_base(enemy_base, t.def["damage"] * _game.tower_base_damage_scale)
					_game.effects.beam(origin, HexGrid.to_world(enemy_base) + Vector3(0, 0.5, 0), Color("ffe27a"))
					GameEvents.tower_fired.emit(pos)
		return

	var dir := target.node.position - pos
	_aim(t, dir)
	if t.cooldown > 0.0:
		return
	t.cooldown = t.def["rate"]

	var accent: Color = t.def["accent"]
	var target_point := target.node.position + Vector3(0, 0.28, 0)
	match t.kind:
		"shot":
			_game.units.hit_enemy(target, t.def["damage"])
			_game.effects.beam(origin, target_point, Color("ffe27a"))
		"slow":
			target.slow_left = t.def["slow_time"]
			target.slow_factor = t.def["slow_factor"]
			_game.units.hit_enemy(target, t.def["damage"])
			_game.effects.beam(origin, target_point, accent, 0.08)
		"nova":
			for e in _game.units.enemies:
				if not e.dead and pos.distance_to(e.node.position) <= t.range_world:
					_game.units.hit_enemy(e, t.def["damage"])
			_game.effects.ring(pos + Vector3(0, 0.05, 0), t.range_world, accent)
		"flame":
			_fire_flame(t, pos, origin, dir, accent)
	GameEvents.tower_fired.emit(pos)


## Hits every enemy inside a cone in front of the tower and draws a few flame streaks.
func _fire_flame(t: Tower, pos: Vector3, origin: Vector3, dir: Vector3, accent: Color) -> void:
	var dir_n := Vector3(dir.x, 0.0, dir.z).normalized()
	var cone := deg_to_rad(t.def["cone_deg"] as float)
	for e in _game.units.enemies:
		if e.dead:
			continue
		var to_e := e.node.position - pos
		to_e.y = 0.0
		if to_e.length() <= t.range_world and absf(dir_n.angle_to(to_e)) <= cone:
			_game.units.hit_enemy(e, t.def["damage"])
	for _k in 3:
		var spread := randf_range(-cone, cone)
		var reach := t.range_world * randf_range(0.6, 1.0)
		_game.effects.beam(origin, pos + dir_n.rotated(Vector3.UP, spread) * reach + Vector3(0, 0.3, 0), accent, 0.1, 0.12)


## Enemy structures: turrets shoot player mobs first, otherwise batter player towers in range; slow towers chill
## the nearest player mob; barracks keep a few enemy units walking out of them.
func _tick_enemy_tower(t: Tower) -> void:
	if t.cooldown > 0.0:
		return
	if t.kind == "spawner":
		t.cooldown = t.def["rate"]
		if _game.units.units_from(t.cell) < t.def["max_units"]:
			var unit: Dictionary = EnemyDefs.pick_weighted(_game.enemy_settings.unit_weights)
			_game.units.spawn_enemy(unit, t.cell, t.cell)
		return
	if t.kind == "slow":
		var at := HexGrid.to_world(t.cell)
		var mob := _nearest_mob(at, t.range_world)
		if mob != null:
			t.cooldown = t.def["rate"]
			mob.slow_left = t.def["slow_time"]
			mob.slow_factor = t.def["slow_factor"]
			_aim(t, mob.node.position - at)
			_game.units.hit_mob(mob, t.def["damage"])
			_game.effects.beam(at + Vector3(0, 0.65, 0), mob.node.position + Vector3(0, 0.22, 0), t.def["accent"], 0.08)
			GameEvents.tower_fired.emit(at)
		return
	if t.kind != "shot":
		return
	var pos := HexGrid.to_world(t.cell)
	var origin := pos + Vector3(0, 0.65, 0)

	var mob_target: Mob = null
	var best := t.range_world
	for m in _game.units.mobs:
		if m.dead:
			continue
		var d := pos.distance_to(m.node.position)
		if d <= best:
			best = d
			mob_target = m
	if mob_target != null:
		t.cooldown = t.def["rate"]
		_aim(t, mob_target.node.position - pos)
		_game.units.hit_mob(mob_target, t.def["damage"])
		_game.effects.beam(origin, mob_target.node.position + Vector3(0, 0.22, 0), Color("ff6b5a"))
		GameEvents.tower_fired.emit(pos)
		return

	var victim = nearest(pos, t.range_world, Team.PLAYER)
	if victim != null:
		t.cooldown = t.def["rate"]
		_aim(t, HexGrid.to_world(victim) - pos)
		damage(victim, t.def["damage"])
		_game.effects.beam(origin, HexGrid.to_world(victim) + Vector3(0, 0.4, 0), Color("ff6b5a"))
		GameEvents.tower_fired.emit(pos)


## Neutral structures are hostile to everyone: wild turrets shoot the nearest enemy unit or player mob in range,
## and dens keep a few neutral units (critters) around.
func _tick_neutral_tower(t: Tower) -> void:
	if t.cooldown > 0.0:
		return
	if t.kind == "spawner":
		t.cooldown = t.def["rate"]
		if _game.units.units_from(t.cell) < t.def["max_units"]:
			_game.units.spawn_enemy(NeutralDefs.UNITS[t.def["unit"]], t.cell, t.cell)
		return
	if t.kind != "shot":
		return
	var pos := HexGrid.to_world(t.cell)
	var target_pos := Vector3.ZERO
	var found := false
	var best := t.range_world
	var enemy_target: Enemy = null
	var mob_target: Mob = null
	for e in _game.units.enemies:
		if e.dead or e.neutral:
			continue
		var d := pos.distance_to(e.node.position)
		if d <= best:
			best = d
			enemy_target = e
			mob_target = null
			found = true
	for m in _game.units.mobs:
		if m.dead:
			continue
		var d := pos.distance_to(m.node.position)
		if d <= best:
			best = d
			mob_target = m
			enemy_target = null
			found = true
	if not found:
		return
	t.cooldown = t.def["rate"]
	if enemy_target != null:
		target_pos = enemy_target.node.position
		_game.units.hit_enemy(enemy_target, t.def["damage"])
	else:
		target_pos = mob_target.node.position
		_game.units.hit_mob(mob_target, t.def["damage"])
	_aim(t, target_pos - pos)
	_game.effects.beam(pos + Vector3(0, 0.65, 0), target_pos + Vector3(0, 0.25, 0), t.def["accent"])
	GameEvents.tower_fired.emit(pos)


func _nearest_mob(pos: Vector3, max_dist: float) -> Mob:
	var best: Mob = null
	var best_d := max_dist
	for m in _game.units.mobs:
		if m.dead:
			continue
		var d := pos.distance_to(m.node.position)
		if d <= best_d:
			best_d = d
			best = m
	return best


func _nearest_enemy(pos: Vector3, max_dist: float) -> Enemy:
	var best: Enemy = null
	var best_d := max_dist
	for e in _game.units.enemies:
		if e.dead:
			continue
		var d := pos.distance_to(e.node.position)
		if d <= best_d:
			best_d = d
			best = e
	return best


func _aim(t: Tower, dir: Vector3) -> void:
	t.turret.rotation.y = atan2(-dir.z, dir.x)
