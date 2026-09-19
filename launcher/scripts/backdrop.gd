extends Control

# JÁTÉKINDÍTÓ – háttér, a kiválasztott játék stílusában.
#
#   Birodalom  – sötét, barnás alap, halvány térképrács, aranykeretes lap.
#   Heptarchia – bőrháttér, rajta pergamenlap: foltok, aranyszegély, fonatos
#                sarokdíszek (a Heptarchia saját indítójának hangulata).

const S = preload("res://scripts/style.gd")

var _noise := FastNoiseLite.new()

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_noise.seed = 1444
	_noise.frequency = 0.012
	resized.connect(queue_redraw)

func _draw() -> void:
	if S.skin == "heptarchia":
		_draw_parchment()
	elif S.skin == "kard_es_magia":
		_draw_dungeon()
	else:
		_draw_night()

# --- KARD ÉS MÁGIA ---
# Katakomba: kőtéglás fal, a két felső sarokban fáklyafény, vasalt keret szegecsekkel.
func _draw_dungeon() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), S.BG)
	var page := Rect2(16, 16, size.x - 32, size.y - 32)
	draw_rect(page.grow(4), Color(0, 0, 0, 0.45))
	draw_rect(page, S.PANEL)
	# kőtéglák (soronként eltolva), a fugák sötétebbek
	var bw := 54.0
	var bh := 26.0
	var row := 0
	var y := page.position.y
	while y < page.end.y:
		var off := 0.0 if row % 2 == 0 else bw * 0.5
		var x := page.position.x - off
		while x < page.end.x:
			var r := Rect2(maxf(x, page.position.x), y, minf(x + bw, page.end.x) - maxf(x, page.position.x), minf(bh, page.end.y - y))
			var v := _noise.get_noise_2d(x * 0.7, y * 0.9)
			draw_rect(r.grow(-1.0), Color(S.PANEL_LT, 0.28 + v * 0.22))
			x += bw
		draw_line(Vector2(page.position.x, y), Vector2(page.end.x, y), Color(0, 0, 0, 0.35), 1.0)
		y += bh
		row += 1
	# fáklyafény a felső sarkokban
	for c in [Vector2(page.position.x + 90, page.position.y + 60), Vector2(page.end.x - 90, page.position.y + 60)]:
		for k in 9:
			var t := float(k) / 9.0
			draw_circle(c, 260.0 * (1.0 - t) + 20.0, Color(0.85, 0.45, 0.12, 0.018 + t * 0.012))
	# alul sötétedés
	for i in 16:
		var t := float(i) / 16.0
		draw_rect(Rect2(page.position.x, page.end.y - (i + 1) * 6.0, page.size.x, 6.0), Color(0, 0, 0, 0.03 * (1.0 - t)))
	draw_rect(page, S.BORDER, false, 3.0)
	draw_rect(page.grow(-6), Color(S.GOLD, 0.45), false, 1.0)
	for c in [page.position, Vector2(page.end.x, page.position.y), Vector2(page.position.x, page.end.y), page.end]:
		var sx := 1.0 if c.x < size.x * 0.5 else -1.0
		var sy := 1.0 if c.y < size.y * 0.5 else -1.0
		var o: Vector2 = c + Vector2(12 * sx, 12 * sy)
		draw_circle(o, 5.0, Color(S.BORDER.lightened(0.2), 0.95))
		draw_circle(o, 2.2, Color("6aa8ff"))

# --- BIRODALOM ---
func _draw_night() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), S.BG)
	var step := 38.0
	var x := step
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(S.BORDER, 0.35), 1.0)
		x += step
	var y := step
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(S.BORDER, 0.35), 1.0)
		y += step

	var page := Rect2(16, 16, size.x - 32, size.y - 32)
	draw_rect(page.grow(4), Color(0, 0, 0, 0.35))
	draw_rect(page, S.PANEL)
	for i in 110:
		var p := Vector2(page.position.x + randf_range(0, page.size.x),
			page.position.y + randf_range(0, page.size.y))
		var v := _noise.get_noise_2dv(p)
		draw_circle(p, 8.0 + absf(v) * 26.0, Color(S.PANEL_LT, 0.30 + absf(v) * 0.25))
	for i in 18:
		var t := float(i) / 18.0
		draw_rect(Rect2(page.position.x, page.position.y + i * 3.0, page.size.x, 3.0),
			Color(S.PANEL_LT, 0.28 * (1.0 - t)))
	draw_rect(page, S.BORDER, false, 3.0)
	draw_rect(page.grow(-6), Color(S.GOLD, 0.45), false, 1.0)
	for c in [page.position, Vector2(page.end.x, page.position.y),
			Vector2(page.position.x, page.end.y), page.end]:
		var sx := 1.0 if c.x < size.x * 0.5 else -1.0
		var sy := 1.0 if c.y < size.y * 0.5 else -1.0
		_corner_lines(c, sx, sy)

func _corner_lines(c: Vector2, sx: float, sy: float) -> void:
	var o := c + Vector2(13.0 * sx, 13.0 * sy)
	draw_line(o, o + Vector2(26.0 * sx, 0), Color(S.GOLD, 0.8), 2.0)
	draw_line(o, o + Vector2(0, 26.0 * sy), Color(S.GOLD, 0.8), 2.0)
	draw_circle(o, 3.0, S.RED)

# --- HEPTARCHIA ---
func _draw_parchment() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), S.BG)
	for i in 26:
		var y := size.y * i / 26.0
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.05), 1.0)

	var page := Rect2(18, 18, size.x - 36, size.y - 36)
	draw_rect(page.grow(4), Color(0, 0, 0, 0.25))
	draw_rect(page, S.PANEL)
	for i in 120:
		var p := Vector2(page.position.x + randf_range(0, page.size.x),
			page.position.y + randf_range(0, page.size.y))
		var v := _noise.get_noise_2dv(p)
		draw_circle(p, 6.0 + absf(v) * 22.0,
			Color(S.PANEL.darkened(0.12), 0.05 + absf(v) * 0.06))
	for i in 14:
		var t := i / 14.0
		draw_rect(page.grow(-float(i)), Color(0.55, 0.42, 0.26, 0.05 * (1.0 - t)), false, 1.0)

	draw_rect(page, S.BORDER, false, 3.0)
	draw_rect(page.grow(-6), Color(S.GOLD, 0.7), false, 1.0)
	for c in [page.position, Vector2(page.end.x, page.position.y),
			Vector2(page.position.x, page.end.y), page.end]:
		var sx := 1.0 if c.x < size.x * 0.5 else -1.0
		var sy := 1.0 if c.y < size.y * 0.5 else -1.0
		_corner_knot(c, sx, sy)

func _corner_knot(c: Vector2, sx: float, sy: float) -> void:
	var o := c + Vector2(10 * sx, 10 * sy)
	for k in 3:
		var r := 4.0 + k * 4.0
		draw_arc(o, r, 0.0, TAU, 24, Color(S.BORDER, 0.85 - k * 0.2), 1.6, true)
	draw_circle(o, 2.4, S.RED)
