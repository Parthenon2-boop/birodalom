extends Camera2D

const PAN_SPEED   := 500.0
const ZOOM_MIN    := 0.25
const ZOOM_MAX    := 3.0
const ZOOM_STEP   := 0.12
const EDGE_PAN_PX := 20

var _drag_active : bool    = false
var _drag_start  : Vector2 = Vector2.ZERO
var _cam_start   : Vector2 = Vector2.ZERO

func _ready() -> void:
	make_current()
	limit_left   = 0
	limit_top    = 0
	limit_right  = GameState.WORLD_W
	limit_bottom = GameState.WORLD_H
	position_smoothing_enabled = true
	position_smoothing_speed   = 5.0

func _process(delta: float) -> void:
	if not GameState.on: return
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_left"):  dir.x -= 1
	if Input.is_action_pressed("move_right"): dir.x += 1
	if Input.is_action_pressed("move_up"):    dir.y -= 1
	if Input.is_action_pressed("move_down"):  dir.y += 1
	if dir != Vector2.ZERO:
		position += dir.normalized() * PAN_SPEED * delta / zoom.x
	var mp  := get_viewport().get_mouse_position()
	var vps := get_viewport().get_visible_rect().size
	var ep  := Vector2.ZERO
	if mp.x < EDGE_PAN_PX:           ep.x -= 1
	if mp.x > vps.x - EDGE_PAN_PX:   ep.x += 1
	if mp.y < EDGE_PAN_PX:           ep.y -= 1
	if mp.y > vps.y - EDGE_PAN_PX:   ep.y += 1
	# Csak akkor toljuk a kamerát a képernyő szélén, ha az egér az ablakon belül van.
	if ep != Vector2.ZERO and Rect2(Vector2.ZERO, vps).has_point(mp):
		position += ep.normalized() * PAN_SPEED * 0.5 * delta / zoom.x
	_clamp()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed: _zoom_at_mouse(1.0 + ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed: _zoom_at_mouse(1.0 - ZOOM_STEP)
			MOUSE_BUTTON_MIDDLE:
				_drag_active = mb.pressed
				if mb.pressed:
					_drag_start = mb.position
					_cam_start  = position
	elif event is InputEventMouseMotion and _drag_active:
		position = _cam_start - ((event as InputEventMouseMotion).position - _drag_start) / zoom.x
		_clamp()

func _zoom_at_mouse(factor: float) -> void:
	var mw := get_global_mouse_position()
	var nz := clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(nz, zoom.x): return
	position = mw - (mw - position) / (nz / zoom.x)
	zoom = Vector2(nz, nz)
	_clamp()

func _clamp() -> void:
	var half := get_viewport().get_visible_rect().size * 0.5 / zoom.x
	# Ha a képernyő szélesebb a világnál, a világ közepére állunk.
	if half.x * 2.0 >= GameState.WORLD_W:
		position.x = GameState.WORLD_W * 0.5
	else:
		position.x = clampf(position.x, half.x, GameState.WORLD_W - half.x)
	if half.y * 2.0 >= GameState.WORLD_H:
		position.y = GameState.WORLD_H * 0.5
	else:
		position.y = clampf(position.y, half.y, GameState.WORLD_H - half.y)
