extends Control

# Kistérkép. A terepet és a ködöt a testvér `Ground` TextureRect shadere
# rajzolja (egyetlen rajzparancs), ide csak a mozgó jelek kerülnek:
# épületek, egységek és a kamera látómezeje. Kattintásra/húzásra a kamera
# a megfelelő helyre ugrik.

const REFRESH := 0.1          # a jelek frissítési ideje (mp)

var main   : Node = null
var ground : TextureRect = null

var _accum : float = 0.0
var _ready_ok : bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	ground = get_parent().get_node_or_null("Ground") as TextureRect
	set_process(true)

func _process(delta: float) -> void:
	if not _ready_ok:
		_try_bind()
		return
	_accum += delta
	# Alacsony részletességen ritkábban rajzoljuk újra: a minimap minden
	# egységet és épületet végigjár.
	if _accum >= (REFRESH if Settings.lively() else REFRESH * 3.0):
		_accum = 0.0
		queue_redraw()

# A terep- és ködtextúra csak a világ felépítése után létezik, ezért
# minden képkockán megpróbáljuk bekötni, amíg sikerül.
func _try_bind() -> void:
	if main == null:
		main = get_tree().get_first_node_in_group("main")
		if main == null: return
	if ground == null: return
	var mat := ground.material as ShaderMaterial
	if mat == null: return
	var terrain = main.terrain
	var fog = main.fog
	if terrain == null or fog == null: return
	if terrain.land_mask_tex == null or fog.fog_tex == null: return
	# Egy 2x2-es fehér kép: a shader a maszkból és a ködből dolgozik.
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	ground.texture = ImageTexture.create_from_image(img)
	mat.set_shader_parameter("land_mask", terrain.land_mask_tex)
	mat.set_shader_parameter("fog_tex", fog.fog_tex)
	_ready_ok = true
	queue_redraw()

func _world_to_map(p: Vector2) -> Vector2:
	return Vector2(p.x / GameState.WORLD_W, p.y / GameState.WORLD_H) * size

func _map_to_world(p: Vector2) -> Vector2:
	return Vector2(
		clampf(p.x / maxf(size.x, 1.0), 0.0, 1.0) * GameState.WORLD_W,
		clampf(p.y / maxf(size.y, 1.0), 0.0, 1.0) * GameState.WORLD_H)

func _draw() -> void:
	if not _ready_ok: return
	var fog = main.fog
	# Épületek: nagyobb négyzet, egységek: kis pont. Az ellenfelet csak
	# akkor mutatjuk, ahol éppen látunk.
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b): continue
		var mine: bool = b.owner_id == GameState.en_id
		if not mine and not fog.is_visible_at(b.global_position): continue
		var p := _world_to_map(b.global_position)
		draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)),
			Color(0, 0, 0, 0.6), true)
		draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), b.team_color, true)
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u): continue
		var mine2: bool = u.owner_id == GameState.en_id
		if not mine2 and not fog.is_visible_at(u.global_position): continue
		draw_rect(Rect2(_world_to_map(u.global_position) - Vector2(1.5, 1.5),
			Vector2(3, 3)), u.team_color, true)
	# Kamera látómezeje
	var cam: Camera2D = main.camera
	if cam != null:
		var half := get_viewport().get_visible_rect().size * 0.5 / cam.zoom.x
		var r := Rect2(_world_to_map(cam.position - half),
			_world_to_map(cam.position + half) - _world_to_map(cam.position - half))
		draw_rect(r, Color(1, 1, 1, 0.85), false, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.7), false, 1.0)

func _gui_input(event: InputEvent) -> void:
	if main == null: return
	var jump := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		jump = true
		pos = event.position
	elif event is InputEventMouseMotion \
			and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		jump = true
		pos = event.position
	if jump:
		var cam: Camera2D = main.camera
		if cam != null:
			cam.position = _map_to_world(pos)
		accept_event()
