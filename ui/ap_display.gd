class_name ApDisplay
extends Control
## Action-point readout: a row of slightly overlapping stars that gently sway.
## A partially built-up star fills from left to right. Everything is tweakable in the inspector
## (select the ApDisplay node under HUD in main.tscn). Animation uses real time, so it keeps swaying in slow-mo.

@export_group("Value")
@export var value := 0.0
@export var max_value := 5.0

@export_group("Shape")
@export var star_size := 44.0                       ## star diameter in pixels
@export_range(0.2, 0.9) var inner_ratio := 0.45     ## inner/outer radius: lower = pointier star
@export_range(0.3, 1.2) var spacing := 0.72         ## distance between stars as a fraction of star_size (< 1 = overlap)
@export var padding := Vector2(8, 8)                ## space around the stars, so sway isn't clipped by the edge

@export_group("Colors")
@export var filled_color := Color("ffd24a")
@export var empty_color := Color(0.16, 0.17, 0.22, 0.85)
@export var outline_color := Color(0.05, 0.05, 0.08, 1.0)
@export var outline_width := 2.0

@export_group("Sway")
@export var sway_enabled := true
@export var sway_distance := 3.5                    ## vertical bob, pixels
@export var sway_sideways := 1.5                    ## horizontal drift, pixels
@export var sway_rotation_deg := 5.0                ## rock back and forth, degrees
@export var sway_speed := 1.4                       ## cycles per ~6 seconds (radians/sec multiplier)
@export var sway_phase_offset := 0.8                ## phase difference between neighbouring stars (radians)


func _process(_delta: float) -> void:
	var count := ceili(max_value)
	custom_minimum_size = Vector2(star_size * (1.0 + spacing * (count - 1)), star_size) + padding * 2.0
	queue_redraw()


func _draw() -> void:
	var count := ceili(max_value)
	var t := Time.get_ticks_msec() / 1000.0
	var outer := star_size / 2.0
	var shape := _star(outer, outer * inner_ratio)
	var outline := shape.duplicate()
	outline.append(shape[0])

	for i in count:
		var phase := t * sway_speed + i * sway_phase_offset
		var offset := Vector2.ZERO
		var rot := 0.0
		if sway_enabled:
			offset = Vector2(sin(phase * 0.7) * sway_sideways, sin(phase) * sway_distance)
			rot = deg_to_rad(sin(phase * 0.8 + 1.0) * sway_rotation_deg)
		var center := padding + Vector2(outer + i * star_size * spacing, outer) + offset
		draw_set_transform(center, rot, Vector2.ONE)

		draw_colored_polygon(shape, empty_color)
		var frac := clampf(value - i, 0.0, 1.0)
		if frac >= 1.0:
			draw_colored_polygon(shape, filled_color)
		elif frac > 0.0:
			# Fill from the left: intersect the star with a rectangle covering `frac` of its width.
			var cut := -outer + 2.0 * outer * frac
			var rect := PackedVector2Array([Vector2(-outer, -outer), Vector2(cut, -outer), Vector2(cut, outer), Vector2(-outer, outer)])
			for part in Geometry2D.intersect_polygons(shape, rect):
				draw_colored_polygon(part, filled_color)
		draw_polyline(outline, outline_color, outline_width, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _star(outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 10:
		var r := outer if k % 2 == 0 else inner
		var a := -PI / 2.0 + k * PI / 5.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts
