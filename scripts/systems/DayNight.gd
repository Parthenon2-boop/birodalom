class_name DayNight
extends Node2D

# NAPPAL ÉS ÉJSZAKA  (index.html 17/B)
#
# A világ órája hat perc alatt fordul egyet: négy perc nappal, kettő
# éjszaka, közte hajnal és alkony. Éjjel a látótáv a felére csökken —
# ezért az éjszakai rajtaütés valódi taktika: közelebb juthatsz észrevétlen.
#
# A sötétséget NEM a ködre rajzoljuk, hanem a motor saját eszközeivel: egy
# CanvasModulate sötétíti a világot (a felületet nem, az külön rétegen ül),
# a fényforrások pedig PointLight2D-k, amelyek kilyukasztják belőle a maguk
# körét. Így meleg fénykörök úsznak a kék éjszakában, és a rajzolás a
# videokártyán fut, nem képpontonként a processzoron.
#
# A beállításokban kikapcsolható; olyankor örök délelőtt van.

const NAP_HOSSZ := 360.0          # egy teljes kör másodpercben
const EJ_TOL := 0.62              # a ciklus melyik szakasza az éjszaka
const EJ_IG := 0.94
const SZURKULET := 0.07           # ilyen hosszan úszik át hajnal és alkony
const EJ_LATOTAV := 0.55          # éjjel ennyiszeres a látótáv
const EJ_SZIN := Color(0.12, 0.17, 0.42)     # hideg kék éjszaka
const ALKONY_SZIN := Color(0.34, 0.20, 0.36) # alkonyatkor bíborba hajlik
const EJ_ERO := 0.62              # ennyire sötétedik be a legmélyebb éjjel

# Ennyi fényforrást kezelünk egyszerre: a kamerához legközelebbieket. Több
# fény a képen úgysem látszana, viszont minden lámpa a videokártyán is
# költség.
const MAX_FENY := 40
const FENY_KOZ := 0.2             # ennyinként rendezzük újra a lámpákat

# Melyik épület mekkora körben világít, és milyen erősen.
const EPULET_FENY := {
	"hq": [132.0, 0.82], "tower": [104.0, 0.78], "harbor": [92.0, 0.72],
	"smith": [84.0, 0.86], "market": [80.0, 0.66], "hospital": [80.0, 0.66],
	"temple": [80.0, 0.66],
}
const EPULET_ALAP := [58.0, 0.52]

var main: Node = null

var _modulate: CanvasModulate = null
var _lampak: Array[PointLight2D] = []
var _tex: Texture2D = null
var _t: float = 0.0

func _ready() -> void:
	name = "DayNight"
	if main == null: main = get_tree().get_first_node_in_group("main")
	_modulate = CanvasModulate.new()
	_modulate.color = Color.WHITE
	add_child(_modulate)
	_tex = _feny_textura()
	for i in range(MAX_FENY):
		var l := PointLight2D.new()
		l.texture = _tex
		l.enabled = false
		l.energy = 0.0
		l.blend_mode = Light2D.BLEND_MODE_ADD
		l.color = Color(1.0, 0.82, 0.55)      # meleg lámpafény
		add_child(l)
		_lampak.append(l)
	set_process(true)

# Kifelé halványuló korong — ez a lámpa fénye. Egyszer készül el, és
# minden fényforrás ugyanezt használja.
static func _feny_textura() -> Texture2D:
	var grad := Gradient.new()
	grad.set_offset(0, 0.0)
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_offset(1, 1.0)
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.55, Color(1, 1, 1, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex

# Hol tartunk a napban? 0 = hajnal előtt, 0.5 = dél, 0.8 = éjfél
func time_of_day() -> float:
	if not Settings.day_night: return 0.25         # kikapcsolva: örök délelőtt
	return fmod(GameState.t + NAP_HOSSZ * 0.18, NAP_HOSSZ) / NAP_HOSSZ

# Mennyire sötét van? 0 = teljes nappal, 1 = mély éjszaka
func night() -> float:
	if not Settings.day_night: return 0.0
	var t := time_of_day()
	if t < EJ_TOL - SZURKULET: return 0.0
	if t < EJ_TOL: return (t - (EJ_TOL - SZURKULET)) / SZURKULET   # alkony
	if t < EJ_IG: return 1.0                                        # éjszaka
	if t < EJ_IG + SZURKULET: return 1.0 - (t - EJ_IG) / SZURKULET  # hajnal
	return 0.0

# A látótáv szorzója — a ködszámítás és az ellenségkeresés ezt kérdezi.
func sight_mul() -> float:
	return 1.0 - (1.0 - EJ_LATOTAV) * night()

# A NAP ÁLLÁSA  (index.html 16/D)
#
# Reggel keleten alacsonyan áll, ezért az árnyék hosszan nyugatra nyúlik;
# délben magasan, rövid árnyékkal; este fordítva. A visszaadott érték az
# árnyék iránya és hosszszorzója — a figurák rajza ezt használja.
func sun_shadow() -> Dictionary:
	if not Settings.day_night:
		return {"dx": 0.34, "dy": 0.17, "len": 1.0}
	var t := time_of_day()
	var nap := clampf(t / EJ_TOL, 0.0, 1.0)
	var szog := (nap - 0.5) * 2.0            # -1 reggel, 0 dél, +1 este
	var magas := cos(szog * 1.15)            # délben a legmagasabb
	var hossz := 1.0 / maxf(0.42, magas)     # alacsony nap: hosszú árnyék
	return {
		"dx": 0.34 * hossz * szog * 1.9,     # reggel nyugatra, este keletre
		"dy": 0.17 * maxf(0.5, hossz * 0.8),
		"len": hossz,
	}

func napszak() -> String:
	var n := night()
	if n <= 0.02: return "nappal"
	if n >= 0.98: return "ejszaka"
	return "alkony" if time_of_day() < EJ_TOL + 0.1 else "hajnal"

func _process(delta: float) -> void:
	var n := night()
	# A világ színe: éjjel hideg kék, alkonyatkor bíbor. A felületre ez nem
	# hat, mert az külön rétegen (CanvasLayer) ül.
	if n <= 0.01:
		_modulate.color = Color.WHITE
	else:
		var szin := ALKONY_SZIN if napszak() == "alkony" else EJ_SZIN
		_modulate.color = Color.WHITE.lerp(szin, n * EJ_ERO)
	_t -= delta
	if _t > 0.0: return
	_t = FENY_KOZ
	_lampak_rendez(n)

# A lámpákat a KAMERÁHOZ legközelebbi fényforrásokra ültetjük át. Ami a
# képen kívül esik, annak úgysem látszana a fénye.
func _lampak_rendez(n: float) -> void:
	if n <= 0.01:
		for l in _lampak: l.enabled = false
		return
	var kozep: Vector2 = main.camera.global_position if main != null else Vector2.ZERO
	var forras: Array = []
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or not b.is_ready(): continue
		# Csak arról tudunk, amit látunk: a saját és a szövetséges épületek,
		# illetve a már felderített idegenek világítanak.
		if GameState.hostile(GameState.en_id, int(b.owner_id)): continue
		var d: Array = EPULET_FENY.get(b.tipus, EPULET_ALAP)
		forras.append([b.global_position, float(d[0]), float(d[1]),
			b.global_position.distance_squared_to(kozep)])
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u) or int(u.owner_id) != GameState.en_id: continue
		if u.aboard(): continue
		var hos: bool = u.role == "hero"
		forras.append([u.global_position, 76.0 if hos else 40.0,
			0.7 if hos else 0.4,
			u.global_position.distance_squared_to(kozep)])
	# A kalózvilágban a városok is égnek: a sajátod erősen, a többi halványan.
	if main != null and main.cities != null and is_instance_valid(main.cities):
		for k in main.cities.varosok:
			var p: Vector2 = main.cities.city_pos(str(k))
			var mienk: bool = main.cities.owner_of(str(k)) == GameState.en_id
			forras.append([p, 110.0 if mienk else 70.0, 0.78 if mienk else 0.55,
				p.distance_squared_to(kozep)])
	forras.sort_custom(func(a, b): return float(a[3]) < float(b[3]))
	for i in range(_lampak.size()):
		var l := _lampak[i]
		if i >= forras.size():
			l.enabled = false
			continue
		var f: Array = forras[i]
		l.position = f[0] as Vector2
		# A korong 128 képpont széles: ekkora sugárhoz ennyi a nagyítás.
		var r := float(f[1])
		l.texture_scale = r / 64.0
		# Ragyogás mellett a lámpák magja túlcsordul (a fény egynél
		# fényesebb lesz a közepén), enélkül marad a régi erősség.
		var tulcsordul := 1.35 if (Settings.bloom and Settings.detail >= 1) else 1.0
		l.energy = float(f[2]) * n * tulcsordul
		l.enabled = true
