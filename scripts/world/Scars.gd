extends Node2D

# A TÁJ EMLÉKEZETE  (index.html 13/D és 13/F)
#
# NYOMOK
#   Ahol sokat járnak, lekopik a fű, és ösvény alakul ki. A kopást
#   cellánként gyűjtjük, és lassan visszanő. Nem játékelem: nem gyorsít,
#   csak látszik — de attól él a táj, hogy meglátszik rajta a használat.
#
# PORFELHŐ
#   Száraz talajon a mozgó egység port ver fel. A lovasság messziről
#   látszik róla — ez taktikai jelzés is.
#
# HULLÁMVERÉS
#   A hajó mögött fehér barázda húzódik, és elsimul.
#
# CSATANYOMOK
#   A hullák és a roncsok eltűnnek egy idő után; a föld viszont emlékszik:
#   felperzselt fű, becsapódás krátere, elhagyott pajzs. Egy hosszú
#   játszmában így a térkép történetet mond — és taktikailag is eligazít:
#   az égett sáv megmutatja, merről jött az ellenség.
#
# Takarékos módban (Settings.detail == 0) az egész réteg kimarad.

const CELLA := 24.0               # ekkora cellákban gyűjtjük a kopást
const KOPAS_LEPES := 0.10         # ennyit kopik egy áthaladástól
const KOPAS_MAX := 1.0
const VISSZANOVES := 0.012        # ennyit nő vissza másodpercenként
const KOPAS_KOZ := 0.25           # ennyinként nézzük, ki hol jár

const POR_ELET := 1.1
const POR_MAX := 90               # ennyi porfelhőt tartunk egyszerre
const BARAZDA_ELET := 2.6
const BARAZDA_MAX := 70

const NYOM_MAX := 140             # ennyi csatanyom fér a térképre
const NYOM_HALVANY := 0.00035     # ennyivel halványul másodpercenként

var main: Node = null

# cellakulcs (Vector2i) -> kopás 0..1
var _kopas: Dictionary = {}
var _por: Array = []              # {p, t, r, szin}
var _barazda: Array = []          # {p, szog, t}
var _nyomok: Array = []           # {p, fajta, szog, ero, szin}
var _rng := RandomNumberGenerator.new()
var _t: float = 0.0
var _vissza_t: float = 0.0

func _ready() -> void:
	name = "Scars"
	z_index = -1                  # a talajon, de az épületek és egységek alatt
	if main == null: main = get_tree().get_first_node_in_group("main")
	_rng.seed = GameState.sim_mag ^ 0x0C5A
	set_process(true)

# --- Bejelentések kívülről ---

# Itt csata volt: égett folt vagy kráter marad a földön.
func add_scar(p: Vector2, fajta: String = "eges") -> void:
	if Settings.detail < 1: return
	_nyomok.append({"p": p, "fajta": fajta, "szog": _rng.randf() * TAU,
		"ero": 1.0, "meret": _rng.randf_range(0.8, 1.35)})
	if _nyomok.size() > NYOM_MAX: _nyomok.pop_front()

func add_dust(p: Vector2, ero: float = 1.0) -> void:
	if Settings.detail < 1: return
	_por.append({"p": p, "t": 0.0, "r": 5.0 + 4.0 * ero})
	if _por.size() > POR_MAX: _por.pop_front()

func _process(delta: float) -> void:
	if not GameState.on or Settings.detail < 1: return
	_t -= delta
	if _t <= 0.0:
		_t = KOPAS_KOZ
		_kopas_gyujtes()
	_vissza_t -= delta
	if _vissza_t <= 0.0:
		_vissza_t = 1.0
		_visszanoves()
	for d in _por: d["t"] = float(d["t"]) + delta
	_por = _por.filter(func(d): return float(d["t"]) < POR_ELET)
	for b in _barazda: b["t"] = float(b["t"]) + delta
	_barazda = _barazda.filter(func(b): return float(b["t"]) < BARAZDA_ELET)
	for n in _nyomok:
		n["ero"] = float(n["ero"]) - NYOM_HALVANY * delta * 60.0
	_nyomok = _nyomok.filter(func(n): return float(n["ero"]) > 0.05)
	queue_redraw()

# Ki hol jár? A gyalogos koptatja a füvet, a lovas port ver, a hajó
# barázdát húz.
func _kopas_gyujtes() -> void:
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u) or u.air: continue
		if u.velocity.length() < 6.0: continue
		var p: Vector2 = u.global_position
		if u.naval:
			if _barazda.size() < BARAZDA_MAX:
				_barazda.append({"p": p, "szog": float(u.face), "t": 0.0})
			continue
		var c := Vector2i(int(p.x / CELLA), int(p.y / CELLA))
		_kopas[c] = minf(KOPAS_MAX, float(_kopas.get(c, 0.0)) + KOPAS_LEPES)
		# A lovasság port ver — messziről látszik.
		if u.role == "cav" and _rng.randf() < 0.5:
			add_dust(p + Vector2(0, 4), 1.3)
		elif u.role == "ram" or u.role == "siege":
			if _rng.randf() < 0.25: add_dust(p + Vector2(0, 4), 1.6)

func _visszanoves() -> void:
	for c in _kopas.keys():
		var v := float(_kopas[c]) - VISSZANOVES
		if v <= 0.01: _kopas.erase(c)
		else: _kopas[c] = v

func _kamera_doboz() -> Rect2:
	if main == null or main.camera == null:
		return Rect2(Vector2.ZERO, Vector2(GameState.WORLD_W, GameState.WORLD_H))
	var meret := get_viewport_rect().size / maxf(main.camera.zoom.x, 0.05)
	return Rect2(main.camera.global_position - meret * 0.5, meret).grow(60.0)

func _draw() -> void:
	if Settings.detail < 1: return
	var doboz := _kamera_doboz()
	# ÖSVÉNYEK: a lekopott fű földes foltja.
	for c in _kopas:
		var cell: Vector2i = c
		var p := Vector2(float(cell.x) * CELLA + CELLA * 0.5,
			float(cell.y) * CELLA + CELLA * 0.5)
		if not doboz.has_point(p): continue
		var a := float(_kopas[c]) * 0.30
		draw_circle(p, CELLA * 0.62, Color(0.42, 0.34, 0.22, a))
	# CSATANYOMOK: égett folt, kráter, elhagyott pajzs.
	for n in _nyomok:
		var p: Vector2 = n["p"]
		if not doboz.has_point(p): continue
		var e := float(n["ero"])
		var m := float(n["meret"])
		match str(n["fajta"]):
			"krater":
				draw_circle(p, 13.0 * m, Color(0.24, 0.20, 0.15, 0.5 * e))
				draw_circle(p, 8.0 * m, Color(0.15, 0.12, 0.09, 0.55 * e))
				draw_arc(p, 13.0 * m, 0.0, TAU, 20,
					Color(0.52, 0.46, 0.36, 0.35 * e), 1.6, true)
			"fegyver":
				# elhagyott pajzs a fűben
				var sz := float(n["szog"])
				var v := Vector2(cos(sz), sin(sz)) * 5.0 * m
				draw_circle(p, 4.4 * m, Color(0.30, 0.26, 0.20, 0.55 * e))
				draw_line(p - v, p + v, Color(0.62, 0.56, 0.42, 0.5 * e), 1.6)
			_:
				# felperzselt fű
				draw_circle(p, 16.0 * m, Color(0.16, 0.13, 0.10, 0.34 * e))
				draw_circle(p + Vector2(6.0, -3.0) * m, 9.0 * m,
					Color(0.20, 0.16, 0.11, 0.26 * e))
	# HULLÁMVERÉS: a hajó mögötti barázda.
	for b in _barazda:
		var p: Vector2 = b["p"]
		if not doboz.has_point(p): continue
		var t := float(b["t"]) / BARAZDA_ELET
		var sz := float(b["szog"])
		var v := Vector2(cos(sz), sin(sz))
		var h := 10.0 + 16.0 * t
		draw_line(p - v * h, p - v * h * 0.2,
			Color(1, 1, 1, 0.22 * (1.0 - t)), 2.6 - 1.4 * t)
	# PORFELHŐ: a mozgó csapat mögött.
	for d in _por:
		var p: Vector2 = d["p"]
		if not doboz.has_point(p): continue
		var t := float(d["t"]) / POR_ELET
		draw_circle(p + Vector2(0, -6.0 * t), float(d["r"]) * (1.0 + t * 1.6),
			Color(0.72, 0.66, 0.52, 0.22 * (1.0 - t)))
