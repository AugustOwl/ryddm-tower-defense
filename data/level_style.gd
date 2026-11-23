class_name LevelStyle
extends Resource
## How one level looks: its colors and how its particles behave. Edited in the level creator's "Look" tab and
## saved with the level.

@export var floor_color_a := Color("1b2030")        ## floor tile colors: each tile gets one of these at random
@export var floor_color_b := Color("181c28")        ## (muted and plain on purpose, so units and towers stand out)
@export var floor_color_c := Color("1f2124")
@export var floor_color_d := Color("192222")
@export var floor_color_e := Color("231f2a")
@export_range(0.0, 1.5) var floor_reactivity := 0.15   ## how much the floor pulses with the music (walls too)
@export_range(0.0, 2.0) var visualizer_brightness := 0.5   ## brightness of the ground visualizer (floor + layers below)
## The ground is 5 layers: 16-bit waves on top, three visualizers (types below), the disco floor at the bottom.
## The first visualizer also drives the floor tiles' own glow.
@export_enum("Rings", "Waves", "Cells", "Sparkle", "Off") var visualizer_type := 0
@export_enum("Rings", "Waves", "Cells", "Sparkle", "Off") var visualizer_type_2 := 2
@export_enum("Rings", "Waves", "Cells", "Sparkle", "Off") var visualizer_type_3 := 3
@export_range(0.0, 1.0) var disco_saturation := 0.8     ## how far the disco floor pushes the floor colors toward vivid
@export var wall_color := Color("3a3f4e")
@export var background_color := Color("05060a")
@export var accent_color := Color(0.35, 0.85, 1.0)   ## the music-reactive glow: outlines, rings, particles
@export_range(0.2, 3.0) var particle_amount := 1.0   ## multipliers on every particle burst
@export_range(0.4, 2.5) var particle_speed := 1.0
@export_range(0.4, 3.0) var particle_size := 1.0
@export_range(0.3, 2.5) var particle_lifetime := 1.0


func copy() -> LevelStyle:
	var c := LevelStyle.new()
	c.floor_color_a = floor_color_a
	c.floor_color_b = floor_color_b
	c.floor_color_c = floor_color_c
	c.floor_color_d = floor_color_d
	c.floor_color_e = floor_color_e
	c.floor_reactivity = floor_reactivity
	c.visualizer_brightness = visualizer_brightness
	c.visualizer_type = visualizer_type
	c.visualizer_type_2 = visualizer_type_2
	c.visualizer_type_3 = visualizer_type_3
	c.disco_saturation = disco_saturation
	c.wall_color = wall_color
	c.background_color = background_color
	c.accent_color = accent_color
	c.particle_amount = particle_amount
	c.particle_speed = particle_speed
	c.particle_size = particle_size
	c.particle_lifetime = particle_lifetime
	return c
