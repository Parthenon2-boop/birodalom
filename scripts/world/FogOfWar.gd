extends Node2D

const FOG_CELL := 32

var fog_w   : int = 0
var fog_h   : int = 0
var fog_img : Image
var fog_tex : ImageTexture

@onready var fog_sprite := $FogSprite as Sprite2D

func init() -> void:
	fog_w = GameState.WORLD_W / FOG_CELL
	fog_h = GameState.WORLD_H / FOG_CELL
	# R = már felderített, G = éppen látható
	fog_img = Image.create(fog_w, fog_h, false, Image.FORMAT_RG8)
	fog_img.fill(Color(0, 0, 0, 1))
	fog_tex = ImageTexture.create_from_image(fog_img)
	fog_sprite.texture = fog_tex
	# A ködkép cellafelbontású (32 px). Lineáris szűrés nélkül a köd
	# széle kockás lépcső lenne; így viszont lágyan gomolyog.
	fog_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	fog_sprite.centered = false
	fog_sprite.position = Vector2.ZERO
	fog_sprite.scale = Vector2(
		float(GameState.WORLD_W) / fog_w,
		float(GameState.WORLD_H) / fog_h
	)
	var mat := fog_sprite.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("fog_tex", fog_tex)

func tick(_delta: float) -> void:
	if fog_img == null: return
	_clear_visible()
	for u in get_tree().get_nodes_in_group("player_units"):
		if not is_instance_valid(u): continue
		# Az időjárás a felderítést is szűkíti (eső, köd, vihar).
		var r: float = u.sight() if u.has_method("sight") else 120.0
		reveal_circle(u.global_position, r)
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b): continue
		if b.owner_id != GameState.en_id: continue
		reveal_circle(b.global_position, 220.0)
	fog_tex.update(fog_img)

func _clear_visible() -> void:
	for y in range(fog_h):
		for x in range(fog_w):
			var px := fog_img.get_pixel(x, y)
			if px.g > 0.0:
				fog_img.set_pixel(x, y, Color(px.r, 0, 0, 1))

func reveal_circle(world_pos: Vector2, radius: float) -> void:
	var cx := int(world_pos.x / FOG_CELL)
	var cy := int(world_pos.y / FOG_CELL)
	var cr := int(radius / FOG_CELL) + 1
	for dy in range(-cr, cr + 1):
		for dx in range(-cr, cr + 1):
			if dx * dx + dy * dy > cr * cr: continue
			var fx := cx + dx
			var fy := cy + dy
			if fx < 0 or fy < 0 or fx >= fog_w or fy >= fog_h: continue
			fog_img.set_pixel(fx, fy, Color(1, 1, 0, 1))

func is_visible_at(world_pos: Vector2) -> bool:
	if fog_img == null: return true
	var fx := int(world_pos.x / FOG_CELL)
	var fy := int(world_pos.y / FOG_CELL)
	if fx < 0 or fy < 0 or fx >= fog_w or fy >= fog_h: return false
	return fog_img.get_pixel(fx, fy).g > 0.5

func is_explored_at(world_pos: Vector2) -> bool:
	if fog_img == null: return true
	var fx := int(world_pos.x / FOG_CELL)
	var fy := int(world_pos.y / FOG_CELL)
	if fx < 0 or fy < 0 or fx >= fog_w or fy >= fog_h: return false
	return fog_img.get_pixel(fx, fy).r > 0.5

func reveal_all() -> void:
	if fog_img == null: return
	fog_img.fill(Color(1, 1, 0, 1))
	fog_tex.update(fog_img)
