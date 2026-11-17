class_name CameraRig
extends Camera3D
## Isometric orthographic camera. WASD pans, the mouse wheel zooms. It frames the current level
## (see fit()) and stops panning once you reach the edge of the board.

@export var distance := 40.0                 ## how far back along the view direction the camera sits
@export var pan_speed := 0.7                 ## WASD speed, in screen-heights per second
@export var pan_range := 0.28                ## how far from the board's center you may pan (fraction of its size)
@export var zoom_min := 0.3                  ## closest zoom (fraction of the "fit the whole board" view)
@export var zoom_max := 1.2                  ## farthest zoom
@export var zoom_step := 1.1                 ## multiplier per wheel notch
@export var rotate_speed := 90.0             ## Q / E turn speed, degrees per second

var _zoom := 1.0
var _yaw := 45.0                             ## which way the camera looks around the board (degrees)
var _focus := Vector3.ZERO                   ## ground point the camera looks at
var _bounds := Rect2(-12, -10, 24, 20)       ## world (x, z) rectangle of the level


func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	rotation_degrees = Vector3(-35.264, 45, 0)           # true isometric angle
	current = true
	_apply()


## Frame a level: center on it and size the view so the whole board fits.
func fit(bounds: Rect2) -> void:
	_bounds = bounds
	var center := bounds.get_center()
	_focus = Vector3(center.x, 0.0, center.y)
	_zoom = 1.0
	_apply()


## The hex under the mouse cursor, or NO_CELL if the ray misses the ground.
func cell_under_mouse() -> Vector2i:
	var mouse := get_viewport().get_mouse_position()
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(project_ray_origin(mouse), project_ray_normal(mouse))
	return HexGrid.NO_CELL if hit == null else HexGrid.from_world(hit)


func _process(delta: float) -> void:
	_apply()
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	var move := Vector2.ZERO
	if not typing:
		var turn := float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
		_yaw = fposmod(_yaw + turn * rotate_speed * delta / maxf(Engine.time_scale, 0.01), 360.0)   # Q / E rotate
		move = Vector2(
			float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)))
	if move != Vector2.ZERO:
		var real_delta := delta / maxf(Engine.time_scale, 0.01)    # panning ignores slow-motion
		_pan(move.normalized() * pan_speed * size * real_delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom / zoom_step, zoom_min, zoom_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom * zoom_step, zoom_min, zoom_max)


## `screen_dir` is (right, up) in screen terms, converted to movement on the ground relative to the camera.
func _pan(screen_dir: Vector2) -> void:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	var right := global_transform.basis.x
	right.y = 0.0
	_focus += right.normalized() * screen_dir.x + forward.normalized() * screen_dir.y
	_apply()


func _apply() -> void:
	var center := _bounds.get_center()
	var limit := Vector2(maxf(_bounds.size.x * pan_range, 2.0), maxf(_bounds.size.y * pan_range, 2.0))
	_focus.x = clampf(_focus.x, center.x - limit.x, center.x + limit.x)
	_focus.z = clampf(_focus.z, center.y - limit.y, center.y + limit.y)
	rotation_degrees = Vector3(-35.264, _yaw, 0)         # isometric tilt, turned by Q / E
	position = _focus + basis.z * distance

	# Size the view from the board's footprint as seen at the isometric angle.
	var span := _bounds.size.x + _bounds.size.y
	var aspect := get_viewport().get_visible_rect().size.aspect()
	var fit_size := maxf(0.408 * span * 1.1, 0.707 * span * 1.08 / aspect)
	size = fit_size * _zoom
