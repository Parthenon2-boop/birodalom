extends CanvasLayer

# IDŐJÁRÁS — szárazföldi és tengeri  (index.html: 17/C és a tengeri idő)
#
# SZÁRAZFÖLDI
#   Néhány percenként fordul az idő. Nem díszlet:
#     ESŐ  — ferde csíkok; a látótáv 12%-kal csökken, és a föld FELÁZIK.
#     HÓ   — lassan hulló pelyhek; a menet 10%-kal lassabb. Csak a 20.
#            században, illetve hegyvidéken és pusztán esik.
#     KÖD  — fátyol a tájon; a látótáv erősen csökken.
#   A SÁR az eső után is megmarad: lassan gyűlik és még lassabban szárad,
#   tehát egy zápor a csata közben is megfordíthatja az erőviszonyokat.
#
# TENGERI
#   VIHAR    — a hajók folyamatosan sérülnek a nyílt vízen, időnként villám
#              csap egybe (a nagyobb árboc vonzza), a sebesség és a látás romlik.
#   SZÉLCSEND— a vitorlák lógnak: a hajók lassabbak.
#   Szárazföldi pályán mindkettő szelídebb.
#
# A számokat a szimulációs magból húzzuk, hogy hálózaton minden gépen
# ugyanaz az idő járjon.

enum { TISZTA, ESO, HO, KOD }
enum { SEA_RENDES, SEA_SZELCSEND, SEA_VIHAR }

const W_MIN := 110.0
const W_MAX := 210.0
const W_ESELY := 0.45
const SAR_NO := 0.11
const SAR_SZARAD := 0.017
const SAR_LASSU := 0.26          # teljes sárban ennyivel lassabb a menet
const ESO_LATAS := 0.12          # esőben ennyivel rosszabb a látás
const KOD_LATAS := 0.45
const HO_LASSU := 0.10

const SEA_MIN := 70.0
const SEA_MAX := 160.0
const SZELCSEND_SEB := 0.62      # teljes szélcsendben ennyi a hajó sebessége
const VIHAR_LATO := 0.55
const VIHAR_HULLAM := 1.6        # másodpercenkénti sebzés teljes viharban
const VILLAM_KAR := [16.0, 30.0]

var fajta: int = TISZTA
var ero: float = 0.0
var sar: float = 0.0
var sea_fajta: int = SEA_RENDES
var sea_ero: float = 0.0

var main: Node = null
var _cel: float = 0.0
var _t: float = 0.0
var _sea_cel: float = 0.0
var _sea_t: float = 0.0
var _villam_t: float = 0.0
var _villam: Vector2 = Vector2.INF
var _villam_eltunik: float = 0.0
var _rng := RandomNumberGenerator.new()
var _cseppek: Array = []          # eső/hó szemcsék a képernyőn
var _anim: float = 0.0

func _init(m: Node = null) -> void:
	main = m

func _ready() -> void:
	name = "Weather"
	layer = 4                      # a világ fölött, a HUD alatt
	if main == null: main = get_tree().get_first_node_in_group("main")
	_rng.seed = GameState.sim_mag ^ 0x0A1D0
	_t = W_MIN + _rng.randf() * (W_MAX - W_MIN)
	_sea_t = 60.0 + _rng.randf() * 70.0
	var r := Control.new()
	r.name = "Rajz"
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.draw.connect(_draw_weather.bind(r))
	add_child(r)
	_rajz = r

var _rajz: Control = null

# --- A szimulációra ható szorzók (a Unit ezeket kérdezi) ---

# Mennyivel lassabb a menet: hó és sár.
func speed_mul(naval: bool) -> float:
	if naval: return sea_speed_mul()
	var m := 1.0
	if fajta == HO: m -= HO_LASSU * ero
	m -= SAR_LASSU * sar
	return maxf(0.45, m)

func sight_mul() -> float:
	var m := 1.0
	if fajta == ESO: m -= ESO_LATAS * ero
	elif fajta == KOD: m -= KOD_LATAS * ero
	return maxf(0.4, m)

func sea_speed_mul() -> float:
	if sea_fajta == SEA_SZELCSEND: return 1.0 - (1.0 - SZELCSEND_SEB) * sea_ero
	if sea_fajta == SEA_VIHAR: return 1.0 - 0.18 * sea_ero
	return 1.0

func sea_sight_mul() -> float:
	return 1.0 - (1.0 - VIHAR_LATO) * sea_ero if sea_fajta == SEA_VIHAR else 1.0

func nev() -> String:
	if sea_fajta == SEA_VIHAR and sea_ero > 0.25: return Lang.t("ido_vihar")
	if sea_fajta == SEA_SZELCSEND and sea_ero > 0.25: return Lang.t("ido_szelcsend")
	if ero < 0.08: return Lang.t("ido_saros") if sar > 0.25 else Lang.t("ido_derult")
	match fajta:
		ESO: return Lang.t("ido_eso")
		KOD: return Lang.t("ido_kod")
		HO:  return Lang.t("ido_ho")
	return Lang.t("ido_derult")

# --- Ütem ---

func _process(delta: float) -> void:
	_anim += delta
	if not GameState.on: return
	if GameState.net_client:
		# A csatlakozónál csak a látvány fut; az időt a házigazda vezeti.
		_rajz.queue_redraw()
		return
	if Settings.weather_on:
		_land_tick(delta)
		_sea_tick(delta)
	else:
		ero = maxf(0.0, ero - delta)
		sea_ero = maxf(0.0, sea_ero - delta)
	_rajz.queue_redraw()

func _land_tick(delta: float) -> void:
	ero += (_cel - ero) * minf(1.0, delta * 0.25)
	_t -= delta
	if _t <= 0.0:
		_t = W_MIN + _rng.randf() * (W_MAX - W_MIN)
		if _cel > 0.1:
			_cel = 0.0                       # ami esett, most eláll
		elif _rng.randf() < W_ESELY:
			var r := _rng.randf()
			if _ho_lehet() and r < 0.42: fajta = HO
			elif r < 0.66: fajta = KOD
			else: fajta = ESO
			_cel = 0.55 + _rng.randf() * 0.45
			if main != null and main.hud != null:
				var kulcs := "ido_eso_jon"
				if fajta == HO: kulcs = "ido_ho_jon"
				elif fajta == KOD: kulcs = "ido_kod_jon"
				main.hud.show_toast(Lang.t(kulcs), 3.5)
	# A sár gyűlik az esőben és lassan szárad (a hó harmadannyit áztat).
	var eso: float = ero if fajta == ESO else (ero * 0.34 if fajta == HO else 0.0)
	if eso > 0.2: sar = minf(1.0, sar + SAR_NO * eso * delta)
	else: sar = maxf(0.0, sar - SAR_SZARAD * delta)

# A hó a modern korhoz és a hegyekhez tartozik.
func _ho_lehet() -> bool:
	return GameState.get_age() >= 3 or GameState.map_type == "hegy" \
		or GameState.map_type == "puszta"

func _sea_tick(delta: float) -> void:
	sea_ero += clampf(_sea_cel - sea_ero, -delta * 0.09, delta * 0.09)
	_sea_t -= delta
	if _sea_t <= 0.0:
		_sea_t = SEA_MIN + _rng.randf() * (SEA_MAX - SEA_MIN)
		var r := _rng.randf()
		if r < 0.22:
			sea_fajta = SEA_VIHAR
			_sea_cel = 0.55 + _rng.randf() * 0.3
		elif r < 0.55:
			sea_fajta = SEA_SZELCSEND
			_sea_cel = 0.6 + _rng.randf() * 0.4
		else:
			sea_fajta = SEA_RENDES
			_sea_cel = 0.0
		# Szárazföldi pályán szelídebb a tenger.
		if sea_fajta != SEA_RENDES and not GameState.pirate: _sea_cel *= 0.5
		if _sea_cel > 0.3 and main != null and main.hud != null:
			main.hud.show_toast(Lang.t("ido_vihar_jon" if sea_fajta == SEA_VIHAR
				else "ido_szelcsend_jon"), 3.5)
	if sea_fajta != SEA_VIHAR or sea_ero < 0.3:
		_villam = Vector2.INF
		return
	# NAGY HULLÁM: folyamatos sebzés a hajókon.
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u) or not u.naval: continue
		u.take_damage(VIHAR_HULLAM * sea_ero * delta)
	# VILLÁM: időnként lecsap egy hajóra — a magasabb árboc vonzza.
	_villam_t -= delta
	if _villam_t <= 0.0:
		_villam_t = 22.0 + _rng.randf() * 30.0 / maxf(0.4, sea_ero)
		var hajok: Array = []
		var sulyok: Array = []
		for u in get_tree().get_nodes_in_group("units"):
			if not is_instance_valid(u) or not u.naval: continue
			hajok.append(u)
			sulyok.append(3.0 if u.role == "galleon" else (2.0 if u.role == "warship" else 1.0))
		if not hajok.is_empty():
			var ossz := 0.0
			for w in sulyok: ossz += float(w)
			var r2 := _rng.randf() * ossz
			var k := 0
			while k < hajok.size() - 1:
				r2 -= float(sulyok[k])
				if r2 <= 0.0: break
				k += 1
			var cel = hajok[k]
			_villam = cel.global_position
			_villam_eltunik = 0.45
			cel.take_damage(VILLAM_KAR[0] + _rng.randf() * (VILLAM_KAR[1] - VILLAM_KAR[0]))
			SFX.play("cannon", -2.0)
	if _villam_eltunik > 0.0:
		_villam_eltunik -= delta
		if _villam_eltunik <= 0.0: _villam = Vector2.INF

# --- Látvány ---

func _draw_weather(c: Control) -> void:
	var meret := c.size
	if ero > 0.05 and Settings.detail >= 1:
		match fajta:
			ESO: _draw_rain(c, meret)
			HO:  _draw_snow(c, meret)
			KOD: _draw_fog(c, meret)
	# Viharban a tenger fölött is sötétebb az ég.
	if sea_ero > 0.25 and sea_fajta == SEA_VIHAR:
		c.draw_rect(Rect2(Vector2.ZERO, meret), Color(0.06, 0.08, 0.14, 0.18 * sea_ero))
		if _villam != Vector2.INF and main != null:
			var kepen := _to_screen(_villam)
			# A villám a képen a legfényesebb pont: egynél nagyobb színnel
			# rajzoljuk, hogy a ragyogás (PostFx) szét tudja sugározni.
			c.draw_line(Vector2(kepen.x, 0), kepen, Color(3.0, 3.0, 2.6, 0.85), 2.5)
			c.draw_circle(kepen, 26.0, Color(2.4, 2.4, 2.1, 0.35))

func _to_screen(world: Vector2) -> Vector2:
	var cam := main.camera as Camera2D
	if cam == null: return world
	var kozep := get_viewport().get_visible_rect().size * 0.5
	return (world - cam.global_position) * cam.zoom.x + kozep

func _draw_rain(c: Control, meret: Vector2) -> void:
	var db := int(160 * ero)
	var szin := Color(0.72, 0.80, 0.92, 0.30 * ero)
	for i in range(db):
		var x := fmod(float(i) * 97.3 + _anim * 420.0, meret.x)
		var y := fmod(float(i) * 53.7 + _anim * 900.0, meret.y)
		c.draw_line(Vector2(x, y), Vector2(x - 7.0, y + 18.0), szin, 1.2)
	c.draw_rect(Rect2(Vector2.ZERO, meret), Color(0.10, 0.12, 0.16, 0.12 * ero))

func _draw_snow(c: Control, meret: Vector2) -> void:
	var db := int(130 * ero)
	var szin := Color(1, 1, 1, 0.55 * ero)
	for i in range(db):
		var x := fmod(float(i) * 131.7 + sin(_anim * 0.6 + float(i)) * 22.0, meret.x)
		var y := fmod(float(i) * 61.3 + _anim * 70.0, meret.y)
		c.draw_circle(Vector2(x, y), 1.6 + fmod(float(i), 3.0) * 0.5, szin)
	c.draw_rect(Rect2(Vector2.ZERO, meret), Color(0.85, 0.90, 0.98, 0.10 * ero))

func _draw_fog(c: Control, meret: Vector2) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, meret), Color(0.72, 0.74, 0.78, 0.33 * ero))
	for i in range(6):
		var y := fmod(float(i) * 140.0 + _anim * 9.0, meret.y + 200.0) - 100.0
		c.draw_rect(Rect2(Vector2(0, y), Vector2(meret.x, 70)),
			Color(0.80, 0.82, 0.86, 0.10 * ero))
