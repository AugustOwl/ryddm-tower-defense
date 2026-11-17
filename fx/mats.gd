class_name Mats
extends RefCounted
## Small helpers for building the simple materials used throughout the game.

const OUTLINE_SHADER := preload("res://shaders/enemy_outline.gdshader")


## A plain colored material. Colors with alpha < 1 become transparent.
static func make(color: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## A colored body with the beat-reactive outline pass (used by enemies and mobs).
static func outlined(color: Color) -> StandardMaterial3D:
	var m := make(color)
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE_SHADER
	m.next_pass = outline
	return m


## An unlit bar that always faces the camera; scale its x to show a fraction.
static func billboard_bar(color: Color) -> StandardMaterial3D:
	var m := make(color, true)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true     # otherwise billboarding discards the node's scale and the bar never shrinks
	return m
