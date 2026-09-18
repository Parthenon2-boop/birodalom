extends Control

# A KEZDŐMENÜ HÁTTERE — pontosan az eredeti (index.html) menüjének mintájára.
#
#   háttér:  radial-gradient(circle at 50% 35%, #1d1712, #0a0806 70%)
#   mozgás:  tizenhat, nagyon halvány ARANY heraldikai alakzat — pajzs, ék,
#            kör, rombusz — lassan fölfelé sodródik, közben enyhén forog.
#            (index.html: "29/B. KEZDŐMENÜ HÁTTERE")
#
# Alacsony részletességi fokozaton (Settings.detail == 0) az alakzatok
# megmaradnak, de nem mozognak — ahogy az eredeti a mozgáscsökkentett módban.

const BELSO := Color("1d1712")       # a sugaras átmenet közepe
const KULSO := Color("0a0806")       # és a széle
const KOZEP := Vector2(0.5, 0.35)    # a kör helye a képernyőn
const SUGAR := 0.70                  # a külső szín ennyinél éri el a szélt

const DB := 16                       # ennyi alakzat sodródik
const FAJTAK := ["pajzs", "ek", "kor", "rombusz"]

var _alakok: Array = []
var _grad: GradientTexture2D = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_grad = _make_gradient()
	for i in DB:
		_alakok.append(_uj_alak(true))
	resized.connect(queue_redraw)

func _make_gradient() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, BELSO)
	g.set_color(1, KULSO)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = KOZEP
	# A külső szín a legtávolabbi saroktól számított 70%-nál áll be.
	t.fill_to = KOZEP + Vector2(SUGAR, 0.0)
	t.width = 256
	t.height = 256
	return t

func _uj_alak(kezdeti: bool) -> Dictionary:
	var w := maxf(size.x, 320.0)
	var h := maxf(size.y, 320.0)
	return {
		"f": FAJTAK[randi() % FAJTAK.size()],
		"x": randf() * w,
		"y": (randf() * h) if kezdeti else (h + 80.0),
		"m": 38.0 + randf() * 120.0,          # méret
		"v": 4.0 + randf() * 9.0,             # emelkedés másodpercenként
		"old": (randf() - 0.5) * 5.0,         # oldalirányú sodródás
		"sz": randf() * TAU,                  # szög
		"fs": (randf() - 0.5) * 0.14,         # forgás
		"a": 0.03 + randf() * 0.05,           # átlátszóság
	}

func _process(delta: float) -> void:
	if not visible: return
	if Settings.detail <= 0: return           # mozgáscsökkentett: állókép
	var w := size.x
	var h := size.y
	for a in _alakok:
		a["y"] = float(a["y"]) - float(a["v"]) * delta
		a["x"] = float(a["x"]) + float(a["old"]) * delta
		a["sz"] = float(a["sz"]) + float(a["fs"]) * delta
		if float(a["y"]) < -120.0:
			var uj := _uj_alak(false)
			uj["y"] = h + 80.0
			a.merge(uj, true)
		if float(a["x"]) < -140.0: a["x"] = w + 120.0
		elif float(a["x"]) > w + 140.0: a["x"] = -120.0
	queue_redraw()

func _draw() -> void:
	draw_texture_rect(_grad, Rect2(Vector2.ZERO, size), false)
	for a in _alakok:
		draw_set_transform(Vector2(float(a["x"]), float(a["y"])), float(a["sz"]), Vector2.ONE)
		_rajzol(str(a["f"]), float(a["m"]), Color(Style.GOLD, float(a["a"])))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _rajzol(fajta: String, m: float, szin: Color) -> void:
	match fajta:
		"pajzs":  _pajzs(m, szin)
		"ek":     _ek(m, szin)
		"kor":
			draw_arc(Vector2.ZERO, m * 0.42, 0.0, TAU, 32, szin, 1.6, true)
			draw_arc(Vector2.ZERO, m * 0.26, 0.0, TAU, 24, szin, 1.6, true)
		_:
			draw_polyline(PackedVector2Array([
				Vector2(0, -m * 0.5), Vector2(m * 0.36, 0),
				Vector2(0, m * 0.5), Vector2(-m * 0.36, 0),
				Vector2(0, -m * 0.5)]), szin, 1.6, true)

# Pajzs: fent enyhén domború él, oldalt egyenes, alul csúcsban fut össze.
func _pajzs(m: float, szin: Color) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(-m * 0.42, -m * 0.5))
	_gorbe(pts, Vector2(-m * 0.42, -m * 0.5), Vector2(0, -m * 0.62), Vector2(m * 0.42, -m * 0.5))
	pts.append(Vector2(m * 0.44, m * 0.02))
	_gorbe(pts, Vector2(m * 0.44, m * 0.02), Vector2(m * 0.4, m * 0.44), Vector2(0, m * 0.62))
	_gorbe(pts, Vector2(0, m * 0.62), Vector2(-m * 0.4, m * 0.44), Vector2(-m * 0.44, m * 0.02))
	pts.append(Vector2(-m * 0.42, -m * 0.5))
	draw_polyline(pts, szin, 1.6, true)

# Másodfokú Bézier-ív pontjai (a HTML quadraticCurveTo megfelelője).
func _gorbe(ki: PackedVector2Array, a: Vector2, c: Vector2, b: Vector2) -> void:
	for i in range(1, 9):
		var t := float(i) / 8.0
		var u := 1.0 - t
		ki.append(a * (u * u) + c * (2.0 * u * t) + b * (t * t))

# Három egymás alatti ék.
func _ek(m: float, szin: Color) -> void:
	for i in 3:
		var y := -m * 0.3 + float(i) * m * 0.3
		draw_polyline(PackedVector2Array([
			Vector2(-m * 0.4, y), Vector2(0, y + m * 0.22), Vector2(m * 0.4, y)]),
			szin, 1.6, true)
