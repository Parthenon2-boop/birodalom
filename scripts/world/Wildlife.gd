extends Node2D

# ÉLŐVILÁG  (index.html 13/C)
#
# A táj eddig üres díszlet volt: fák, fű, semmi mozgás. Most él.
#
#   MADARAK  — csapatban húznak át az égen, magasan, árnyékkal a földön
#   ŐZEK     — erdőszélen legelnek, és szétugranak, ha katona közelít
#   SIRÁLYOK — a part fölött köröznek
#   HALAK    — a vízben időnként kiugranak, gyűrűt vetve
#
# Egyik sem játékelem: nem lehet őket megölni, nem takarnak, nem lassítanak.
# Takarékos módban (Settings.detail == 0) kimaradnak, és a képernyőn kívül
# semmit nem számolunk.

const MADAR_CSAPAT := 3           # ennyi csapat húz át egyszerre
const MADAR_DB := 7               # egy csapatban ennyi madár
const OZ_DB := 8
const SIRALY_DB := 6
const HAL_KOZ := 1.6              # ennyinként ugrik ki egy hal
const OZ_RIADAS := 150.0          # ekkora körben ijed meg a katonától
const OZ_LEGELES := 26.0          # ilyen messze kóborol a helyétől

var main: Node = null

var _madarak: Array = []          # {p, v, faz, arny}
var _ozek: Array = []             # {p, cel, ijedt, faz}
var _siralyok: Array = []         # {kozep, r, szog, seb}
var _halak: Array = []            # {p, t, elet}
var _rng := RandomNumberGenerator.new()
var _t: float = 0.0
var _oz_t: float = 0.0

func _ready() -> void:
	name = "Wildlife"
	z_index = 7                   # az egységek fölött húznak el a madarak
	if main == null: main = get_tree().get_first_node_in_group("main")
	# A mag a játszmából jön: minden gépen ugyanott legelnek az őzek.
	_rng.seed = GameState.sim_mag ^ 0x0E10
	_init_allatok()
	set_process(Settings.detail >= 1)

func _init_allatok() -> void:
	var W := float(GameState.WORLD_W)
	var H := float(GameState.WORLD_H)
	for i in range(MADAR_CSAPAT):
		var kezd := Vector2(_rng.randf() * W, _rng.randf() * H)
		var irany := Vector2(cos(_rng.randf() * TAU), sin(_rng.randf() * TAU)).normalized()
		for j in range(MADAR_DB):
			_madarak.append({
				"p": kezd + irany.orthogonal() * float(j - MADAR_DB / 2) * 16.0
					- irany * absf(float(j - MADAR_DB / 2)) * 12.0,
				"v": irany * _rng.randf_range(38.0, 52.0),
				"faz": _rng.randf() * TAU,
			})
	# Az őzek erdőszélre kerülnek: ahol fa van, de nem a sűrűjében.
	var ter: Node = main.terrain if main != null else null
	for i in range(OZ_DB):
		var p := _erdo_szel(ter)
		_ozek.append({"p": p, "otthon": p, "cel": p, "ijedt": 0.0,
			"faz": _rng.randf() * TAU})
	# A sirályok a part fölött köröznek.
	for i in range(SIRALY_DB):
		var c := _part_kozel(ter)
		_siralyok.append({"kozep": c, "r": _rng.randf_range(40.0, 90.0),
			"szog": _rng.randf() * TAU, "seb": _rng.randf_range(0.5, 0.9)})

func _erdo_szel(ter: Node) -> Vector2:
	if ter != null and ter.trees.size() > 0:
		var fa: Vector2 = ter.trees[_rng.randi() % ter.trees.size()]
		var a := _rng.randf() * TAU
		return fa + Vector2(cos(a), sin(a)) * _rng.randf_range(40.0, 90.0)
	return Vector2(_rng.randf() * GameState.WORLD_W, _rng.randf() * GameState.WORLD_H)

func _part_kozel(ter: Node) -> Vector2:
	for _i in range(40):
		var p := Vector2(_rng.randf() * GameState.WORLD_W,
			_rng.randf() * GameState.WORLD_H)
		if ter != null and ter.has_method("on_shore") and ter.on_shore(p): return p
	return Vector2(GameState.WORLD_W * 0.5, GameState.WORLD_H * 0.5)

func _process(delta: float) -> void:
	if not GameState.on or Settings.detail < 1:
		return
	_t += delta
	_madar_lep(delta)
	_oz_lep(delta)
	_siraly_lep(delta)
	_hal_lep(delta)
	# A képernyőn kívül semmit nem kell újrarajzolni.
	if _lathato(): queue_redraw()

func _lathato() -> bool:
	if main == null or main.camera == null: return true
	return true

func _kamera_doboz() -> Rect2:
	if main == null or main.camera == null:
		return Rect2(Vector2.ZERO, Vector2(GameState.WORLD_W, GameState.WORLD_H))
	var meret := get_viewport_rect().size / maxf(main.camera.zoom.x, 0.05)
	return Rect2(main.camera.global_position - meret * 0.5, meret).grow(80.0)

func _madar_lep(delta: float) -> void:
	var W := float(GameState.WORLD_W)
	var H := float(GameState.WORLD_H)
	for m in _madarak:
		m["p"] = (m["p"] as Vector2) + (m["v"] as Vector2) * delta
		m["faz"] = float(m["faz"]) + delta * 9.0
		var p: Vector2 = m["p"]
		# A pálya szélén túlhúzva a másik oldalon jönnek vissza.
		if p.x < -60.0: p.x = W + 40.0
		if p.x > W + 60.0: p.x = -40.0
		if p.y < -60.0: p.y = H + 40.0
		if p.y > H + 60.0: p.y = -40.0
		m["p"] = p

func _oz_lep(delta: float) -> void:
	_oz_t -= delta
	var nezes := _oz_t <= 0.0
	if nezes: _oz_t = 0.4
	for o in _ozek:
		var p: Vector2 = o["p"]
		if nezes:
			# Megijed-e? Katona közelít.
			var ijedt := false
			for u in get_tree().get_nodes_in_group("units"):
				if not is_instance_valid(u) or u.naval or u.air: continue
				if u.global_position.distance_to(p) < OZ_RIADAS:
					ijedt = true
					o["cel"] = p + (p - u.global_position).normalized() * 220.0
					break
			o["ijedt"] = 2.5 if ijedt else maxf(0.0, float(o["ijedt"]) - 0.4)
			if not ijedt and p.distance_to(o["cel"]) < 12.0:
				var a := _rng.randf() * TAU
				o["cel"] = (o["otthon"] as Vector2) \
					+ Vector2(cos(a), sin(a)) * _rng.randf_range(10.0, OZ_LEGELES)
		var seb := 150.0 if float(o["ijedt"]) > 0.0 else 16.0
		var d: Vector2 = (o["cel"] as Vector2) - p
		if d.length() > 2.0:
			o["p"] = p + d.normalized() * seb * delta
		o["faz"] = float(o["faz"]) + delta * (6.0 if float(o["ijedt"]) > 0.0 else 1.4)

func _siraly_lep(delta: float) -> void:
	for s in _siralyok:
		s["szog"] = float(s["szog"]) + delta * float(s["seb"])

func _hal_lep(delta: float) -> void:
	for h in _halak:
		h["t"] = float(h["t"]) + delta
	_halak = _halak.filter(func(h): return float(h["t"]) < float(h["elet"]))
	if _t < HAL_KOZ: return
	_t = 0.0
	# Egy hal a LÁTHATÓ vízfelületen ugrik ki — máshol kárba veszne.
	var doboz := _kamera_doboz()
	var ter: Node = main.terrain if main != null else null
	if ter == null: return
	for _i in range(8):
		var p := doboz.position + Vector2(_rng.randf() * doboz.size.x,
			_rng.randf() * doboz.size.y)
		if not ter.is_water(p): continue
		_halak.append({"p": p, "t": 0.0, "elet": 0.9})
		return

func _draw() -> void:
	if Settings.detail < 1: return
	var doboz := _kamera_doboz()
	# HALAK: kiugranak és gyűrűt vetnek.
	for h in _halak:
		var p: Vector2 = h["p"]
		if not doboz.has_point(p): continue
		var t := float(h["t"]) / maxf(float(h["elet"]), 0.01)
		var ivy := -18.0 * sin(t * PI)
		draw_circle(p, 6.0 + 16.0 * t, Color(1, 1, 1, 0.16 * (1.0 - t)))
		if t < 0.85:
			draw_circle(p + Vector2(0, ivy), 2.2, Color(0.82, 0.86, 0.9, 0.9))
	# ŐZEK: apró barna test, futáskor megnyúlva.
	for o in _ozek:
		var p: Vector2 = o["p"]
		if not doboz.has_point(p): continue
		var fut := float(o["ijedt"]) > 0.0
		var l := 0.6 + 0.25 * sin(float(o["faz"]))
		draw_circle(p + Vector2(1.5, 2.0), 4.0, Color(0, 0, 0, 0.18))
		_teglalap(p, Vector2(9.0, 5.0), Color(0.52, 0.36, 0.22))
		# fej: legeléskor lehajtva, futáskor előrenyújtva
		var fej := p + (Vector2(6.0, -3.0) if fut else Vector2(5.0, 1.0 + l))
		draw_circle(fej, 2.2, Color(0.56, 0.4, 0.25))
	# SIRÁLYOK: fehér "v" betűk a part fölött.
	for s in _siralyok:
		var c: Vector2 = s["kozep"]
		var p := c + Vector2(cos(float(s["szog"])), sin(float(s["szog"])) * 0.6) \
			* float(s["r"])
		if not doboz.has_point(p): continue
		_szarny(p, 3.4, Color(0.95, 0.96, 0.98, 0.9), float(s["szog"]) * 3.0)
	# MADARAK: magasan húznak, alattuk halvány árnyék a földön.
	for m in _madarak:
		var p: Vector2 = m["p"]
		if not doboz.has_point(p): continue
		draw_circle(p + Vector2(10.0, 26.0), 2.4, Color(0, 0, 0, 0.10))
		_szarny(p, 4.2, Color(0.16, 0.16, 0.2, 0.85), float(m["faz"]))

func _teglalap(kozep: Vector2, meret: Vector2, szin: Color) -> void:
	draw_rect(Rect2(kozep - meret * 0.5, meret), szin, true)

# Egy madár: két szárnyvonal, amely a fázistól csapkod.
func _szarny(p: Vector2, r: float, szin: Color, faz: float) -> void:
	var y := sin(faz) * r * 0.5
	draw_polyline([p + Vector2(-r, y), p, p + Vector2(r, y)], szin, 1.3, true)
