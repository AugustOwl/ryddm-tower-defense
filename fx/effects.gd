class_name Effects
extends Node3D
## Music-synced visuals. Listens to GameEvents and turns them into particle bursts and Conductor accents,
## and offers helpers for the simple one-off visuals gameplay code needs (beams and expanding rings).
## All particles share one material (pulse_particle.gdshader) so they pulse in step with the outlines and the level.
## To react to a new event: connect another handler in _ready().

const PARTICLE_SHADER := preload("res://shaders/pulse_particle.gdshader")

var _material: ShaderMaterial
var _mesh: SphereMesh
var _fade: Gradient


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = PARTICLE_SHADER
	_mesh = SphereMesh.new()
	_mesh.radius = 0.07
	_mesh.height = 0.14
	_mesh.radial_segments = 8
	_mesh.rings = 4
	_fade = Gradient.new()
	_fade.set_color(0, Color(1, 1, 1, 1))
	_fade.set_color(1, Color(1, 1, 1, 0))

	# event -> [particle count, speed, height above the ground, Conductor accent]
	_react(GameEvents.enemy_died, 24, 4.0, 0.3, 0.8)
	_react(GameEvents.enemy_reached_base, 14, 3.0, 0.5, 1.0)
	_react(GameEvents.tower_placed, 10, 2.5, 0.1, 0.4)
	_react(GameEvents.tower_destroyed, 32, 4.5, 0.4, 1.0)
	_react(GameEvents.explosion, 40, 6.0, 0.3, 1.0)
	_react(GameEvents.base_destroyed, 60, 7.0, 0.6, 1.0)
	_react(GameEvents.rally_set, 12, 3.0, 0.2, 0.5)
	_react(GameEvents.mob_died, 14, 3.0, 0.3, 0.4)
	_react(GameEvents.mob_reached_spawn, 20, 3.5, 0.4, 0.7)


func _react(event: Signal, amount: int, speed: float, height: float, accent: float) -> void:
	event.connect(func(pos: Vector3) -> void:
		burst(pos + Vector3(0, height, 0), amount, speed)
		Conductor.accent(accent))


## One-shot particle burst at a world position.
func burst(pos: Vector3, amount: int, speed: float) -> void:
	var style := _style()                              # per-level particle settings (LevelStyle)
	amount = maxi(1, int(round(amount * style.particle_amount)))
	speed *= style.particle_speed
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.9 * style.particle_lifetime
	p.explosiveness = 1.0
	p.mesh = _mesh
	p.material_override = _material
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.15
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -7.0, 0)
	p.scale_amount_min = 0.6 * style.particle_size
	p.scale_amount_max = 1.5 * style.particle_size
	p.color_ramp = _fade
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)


func _style() -> LevelStyle:
	var game := get_parent() as Game
	if game != null and game.board.level != null:
		return game.board.level.style
	return LevelStyle.new()


## A short straight beam between two points (tower shots, flame streaks).
func beam(from: Vector3, to: Vector3, color := Color("ffe27a"), width := 0.05, life := 0.1) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, width, from.distance_to(to))
	m.mesh = box
	m.material_override = Mats.make(color, true)
	add_child(m)
	m.position = (from + to) / 2.0
	m.look_at(to)
	get_tree().create_timer(life).timeout.connect(m.queue_free)


## An expanding, fading disc (area-of-effect towers).
func ring(pos: Vector3, radius: float, color: Color) -> void:
	var m := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.04
	disc.radial_segments = 48
	m.mesh = disc
	var material := Mats.make(Color(color, 0.45), true)
	m.material_override = material
	m.position = pos
	m.scale = Vector3(0.1, 1.0, 0.1)
	add_child(m)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(m, "scale", Vector3(radius, 1.0, radius), 0.35)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.35)
	tween.finished.connect(m.queue_free)
