extends Node2D

# SORTŰZ  (index.html 16/C)
#
# A hajóágyú nem egyetlen villanás: a célpont felőli oldalon egyszerre
# dörren el a fedélzeti sor. Amennyi ágyúja van a hajónak, annyi torkolat
# villan — a szlúp nyolca alig füstöl, a gálya negyvenöt ágyúja
# elsötétíti maga körül a vizet.
#
# Három réteg egymáson:
#   TORKOLATTŰZ — rövid, éles villanás az ágyúnyílásnál
#   FÜST        — sűrű, lassan táguló és sodródó gomoly
#   REMEGÉS     — a sortűz a kamerát is megrázza
#
# A torkolattűz MINDIG megjelenik (olcsó, és enélkül nem látni, lőtt-e a
# hajó); a füst takarékos módban kimarad — az a drágább rész.

const FUST_MAX := 260             # ennyi füstgomoly lehet egyszerre

var main: Node = null

var _fx: Array = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	name = "Broadside"
	z_index = 8
	if main == null: main = get_tree().get_first_node_in_group("main")
	_rng.randomize()
	set_process(true)

# Egy hajó oldalsortüze a cél felé.
func fire(hajo: Node2D, cel: Node2D) -> void:
	if hajo == null or cel == null: return
	var agyuk: int = int(hajo.gun_count()) if hajo.has_method("gun_count") else 8
	var db := clampi(int(round(float(agyuk) / 2.0)), 2, 24)   # fél oldal dörren
	var szog := (cel.global_position - hajo.global_position).angle()
	# A hajó hossztengelye merőleges a lövés irányára: az ágyúk e mentén állnak.
	var hossz := szog + PI * 0.5
	var galleon: bool = str(hajo.role) == "galleon"
	var L := 24.0 if galleon else (19.0 if str(hajo.role) == "warship" else 16.0)
	var ki: float = float(hajo.radius) * 0.75
	var fust_ok := Settings.detail >= 1
	for i in range(db):
		var t := 0.0 if db == 1 else (float(i) / float(db - 1) - 0.5) * 2.0
		var p := hajo.global_position \
			+ Vector2(cos(hossz), sin(hossz)) * t * L \
			+ Vector2(cos(szog), sin(szog)) * ki
		# Középről kifelé gördül a dörej: a szélső ágyúk később szólalnak meg.
		var kesés := absf(t) * 0.05 + _rng.randf() * 0.04
		_fx.append({"p": p, "t": -kesés, "elet": 0.34, "fajta": "agyu",
			"szog": szog, "ero": 1.25 if galleon else 1.0})
		if fust_ok and _fx.size() < FUST_MAX:
			_fx.append({"p": p + Vector2(cos(szog), sin(szog)) * 6.0,
				"t": -kesés, "elet": 1.5 + _rng.randf() * 0.7, "fajta": "fust",
				"v": Vector2(cos(szog), sin(szog)) * 16.0
					+ Vector2(_rng.randf_range(-5, 5), _rng.randf_range(-5, 5)),
				"r": 9.0 if galleon else 7.0})
	# A sortűz a kamerát is megrázza.
	if main != null and main.camera != null and main.camera.has_method("shake"):
		main.camera.shake(0.30 if galleon else 0.14)
	SFX.play("cannon", -4.0 if galleon else -7.0)

func _process(delta: float) -> void:
	if _fx.is_empty(): return
	for f in _fx: f["t"] = float(f["t"]) + delta
	_fx = _fx.filter(func(f): return float(f["t"]) < float(f["elet"]))
	queue_redraw()

func _draw() -> void:
	for f in _fx:
		var t := float(f["t"])
		if t < 0.0: continue                  # még nem dörrent el
		var k := t / maxf(float(f["elet"]), 0.01)
		var p: Vector2 = f["p"]
		if str(f["fajta"]) == "agyu":
			# Torkolattűz: fényes mag, előtte sárga nyelv. A színe SZÁNDÉKOSAN
			# egynél nagyobb — így csordul túl a ragyogásban (PostFx). Ha a
			# ragyogás ki van kapcsolva, a motor visszavágja fehérre, és
			# pontosan a régi képet kapjuk.
			var e := (1.0 - k) * float(f["ero"])
			draw_circle(p, 3.4 + k * 5.0, Color(2.6, 2.45, 2.05, 0.95 * e))
			var sz := float(f["szog"])
			var elore := Vector2(cos(sz), sin(sz))
			var oldal := elore.orthogonal() * (3.4 + k * 3.0)
			draw_colored_polygon([p - oldal, p + elore * (13.0 + k * 16.0),
				p + oldal], Color(2.1, 1.45, 0.52, 0.7 * e))
		else:
			# lőporfüst: tágul, sodródik, világosból szürkébe fordul
			var r := float(f["r"]) * (0.6 + k * 2.6)
			var a := 0.55 * (1.0 - k) * (1.0 - k)
			var szurke := 0.90 - 0.27 * k
			var v: Vector2 = f["v"]
			draw_circle(p + v * k * 0.9 - Vector2(0, k * 5.0), r,
				Color(szurke, szurke, szurke - 0.03, a))
