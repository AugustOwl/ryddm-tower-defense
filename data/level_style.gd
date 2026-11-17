class_name LevelStyle
extends Resource
## How one level looks: its colors and how its particles behave. Edited in the level creator's "Look" tab and
## saved with the level.

@export var floor_color_a := Color("2a3142")        ## the two alternating floor tile colors
@export var floor_color_b := Color("262d3d")
@export var wall_color := Color("4a4f60")
@export var background_color := Color("0d1018")
@export var accent_color := Color(0.35, 0.85, 1.0)   ## the music-reactive glow: outlines, rings, particles
@export_range(0.2, 3.0) var particle_amount := 1.0   ## multipliers on every particle burst
@export_range(0.4, 2.5) var particle_speed := 1.0
@export_range(0.4, 3.0) var particle_size := 1.0
@export_range(0.3, 2.5) var particle_lifetime := 1.0


func copy() -> LevelStyle:
	var c := LevelStyle.new()
	c.floor_color_a = floor_color_a
	c.floor_color_b = floor_color_b
	c.wall_color = wall_color
	c.background_color = background_color
	c.accent_color = accent_color
	c.particle_amount = particle_amount
	c.particle_speed = particle_speed
	c.particle_size = particle_size
	c.particle_lifetime = particle_lifetime
	return c
