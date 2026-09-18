extends Control

# KIKÖTŐMENÜ  (index.html: portMenu, 29/D)
#
# A kalózvilág fő kezelőfelülete. A városra kattintva a jelölő köré
# kinyílik egy legyező:
#
#   ÉPÍTÉS   — a választott épület a város körül épül fel; a nép húzza
#              fel, nem kell hozzá munkást odaküldeni.
#   TOBORZÁS — a három harci hajó (szlúp, brigg, gálya) a város
#              kikötőjében áll ki.
#   BEZÁRÁS  — a menü becsukódik.
#
# Idegen város menüjében nincs parancs: ott csak az látszik, mit kell
# szétlőnöd, mielőtt partra szállhatnál.
#
# FONTOS: a menüt CSAK akkor építjük újra, ha változott a város, a
# cselekvés, a korszak vagy a nyelv. Ha minden képkockán újraépülne, a
# kattintás elveszne: az egérgomb lenyomása és felengedése között
# megsemmisülne a gomb, amire kattintottál.

const SZIN_EPITES := Color("2f7a68")
const SZIN_TOBORZAS := Color("8c2f2f")
const SZIN_BEZARAS := Color("4a4a52")
const SZIN_HAJO := Color("8a5a2a")

# A HTML legyezője: az első gyűrű sugara 74, a listáé 98 (sok elemnél 118).
# Nálunk nagyobb, mert a köröknél szélesebb táblákra írjuk ki a hozamot és
# az árat is — kisebb sugárnál egymásra csúsznának.
const R_FO := 100.0
const R_LISTA := [150.0, 190.0, 218.0]

var main: Node = null
var kulcs: String = ""
var akcio: String = ""

var _sig: String = ""

func _ready() -> void:
	name = "PortMenu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	if main == null: main = get_tree().get_first_node_in_group("main")
	set_process(true)

func is_open() -> bool:
	return kulcs != ""

func open(k: String) -> void:
	kulcs = k
	akcio = ""
	_sig = ""
	visible = true
	SFX.play("click")
	_render()

func close() -> void:
	kulcs = ""
	akcio = ""
	_sig = ""
	visible = false
	_clear()

func pick(a: String) -> void:
	if a == "close":
		SFX.play("click")
		close()
		return
	akcio = "" if akcio == a else a
	SFX.play("click")
	_render()

func _process(_delta: float) -> void:
	if not is_open(): return
	# A város elveszhet a játszma közben (vagy véget ér a játék).
	if not GameState.on or main == null or main.cities == null:
		close(); return
	_place()
	_render()

# A menü a város fölött nyílik, ezért KÉPERNYŐ-koordináta kell neki: a
# világpontot a vászon átalakításával váltjuk át.
func _place() -> void:
	var p: Vector2 = main.cities.city_pos(kulcs)
	var s := get_viewport().get_canvas_transform() * p
	for gy in get_children():
		var c := gy as Control
		if c == null: continue
		var eltol: Vector2 = c.get_meta("eltol", Vector2.ZERO)
		c.position = s + eltol - c.size * 0.5

func _clear() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()

func _render() -> void:
	var gazda: int = main.cities.owner_of(kulcs)
	var sig := "%s|%s|%d|%s|%d" % [kulcs, akcio, GameState.get_age(),
		Lang.code, gazda]
	if sig == _sig: return
	_sig = sig
	_clear()
	var mienk: bool = gazda == GameState.en_id
	if akcio == "":
		var akciok: Array = []
		if mienk:
			akciok = [["build", Lang.t("pm_epites"), SZIN_EPITES],
				["train", Lang.t("pm_toborzas"), SZIN_TOBORZAS]]
		akciok.append(["close", Lang.t("pm_bezaras"), SZIN_BEZARAS])
		for i in akciok.size():
			var a: Array = akciok[i]
			var szog := -PI * 0.92 + float(i) * PI * 0.62
			var mit := str(a[0])
			_gomb(Vector2(cos(szog), sin(szog)) * R_FO, str(a[1]),
				_fejlec(mit, mienk), a[2] as Color,
				func() -> void: pick(mit), true)
	else:
		var lista := _lista(akcio, mienk)
		var n: int = maxi(lista.size(), 1)
		var r: float = R_LISTA[0] if n <= 3 else (R_LISTA[1] if n <= 5 else R_LISTA[2])
		for i in lista.size():
			var e: Dictionary = lista[i]
			var szog := -PI * 1.02 + float(i) * (PI * 1.55 / maxf(float(n - 1), 1.0))
			var mit: String = str(e["mit"])
			_gomb(Vector2(cos(szog), sin(szog)) * r, str(e["nev"]),
				str(e["also"]), e["szin"] as Color,
				func() -> void: _valaszt(mit), false)
		# Vissza a fő legyezőhöz.
		var vissza := akcio
		_gomb(Vector2.ZERO, "←", "", SZIN_BEZARAS,
			func() -> void: pick(vissza), false, Vector2(52, 40))
	_place()

# Az idegen város menüjében a "Bezárás" alá odaírjuk, mi vár rád: hány
# lakos és hány torony. Ez mondja meg, mennyi munka lesz elvenni.
func _fejlec(mit: String, mienk: bool) -> String:
	if mienk or mit != "close": return ""
	var a: Dictionary = main.cities.varosok.get(kulcs, {})
	if a.is_empty(): return ""
	return "%d %s · %d %s" % [int(round(float(a.get("lakos", 0.0)))),
		Lang.t("v_lakos"), int(a.get("torony", 0)), Lang.t("pm_torony")]

func _valaszt(mit: String) -> void:
	if main == null: return
	if akcio == "build":
		main.send_cmd("pbuild", [kulcs, mit])
	else:
		main.send_cmd("ptrain", [kulcs, mit])
	_sig = ""                     # az árak és a sorok változnak
	_render()

# --- A választható tételek ---

func _lista(mi: String, mienk: bool) -> Array:
	var ki: Array = []
	if not mienk: return ki           # más fél városa: nincs parancs
	if mi == "build":
		for t in main.PORT_BUILDS:
			var tipus: String = t
			var d: Dictionary = Building.BUILD_STATS.get(tipus, {})
			if d.is_empty(): continue
			if bool(d.get("pirateOnly", false)) and not GameState.pirate: continue
			if tipus in GameState.banned_buildings: continue
			if ki.size() >= 7: break
			ki.append({
				"nev": main.hud.build_name(tipus),
				"also": "%s\n%s" % [_hozam(d), main.hud._cost_text(
					main.build_cost(GameState.en_id, tipus))],
				"szin": SZIN_EPITES, "mit": tipus,
			})
	else:
		for r in main.PORT_SHIPS:
			var role: String = r
			ki.append({
				"nev": Lang.t("pm_hajo_" + role),
				"also": "%s · %s" % [Lang.t("pm_hajo_%s_al" % role),
					main.hud._cost_text(Building.train_cost(GameState.en_id, role))],
				"szin": SZIN_HAJO, "mit": role,
			})
	return ki

# Mit ad az épület? Elöl a termelés, mert a városban az számít.
func _hozam(d: Dictionary) -> String:
	var age := GameState.get_age()
	if d.has("food"):
		return "+%.1f %s" % [float(d["food"][age]), Lang.t("elelem")]
	if d.has("gold"):
		return "+%.1f %s" % [float(d["gold"]), Lang.t("arany")]
	if d.has("rum"):
		return "+%.1f %s" % [float(d["rum"]), Lang.t("rum")]
	if d.has("pop"):
		return "+%d %s" % [int(d["pop"]), Lang.t("pm_keret")]
	if d.has("heal"):
		return Lang.t("pm_gyogyitas")
	if d.has("dmg"):
		return Lang.t("pm_vedi_partot")
	if d.has("trains"):
		return Lang.t("pm_kikepzes")
	return Lang.t("pm_kutatas")

# --- Egy gomb a legyezőben ---

func _gomb(eltol: Vector2, cim: String, also: String, szin: Color,
		   fn: Callable, nagy: bool, meret: Vector2 = Vector2.ZERO) -> Button:
	var b := Button.new()
	b.text = cim if also == "" else "%s\n%s" % [cim, also]
	b.autowrap_mode = TextServer.AUTOWRAP_OFF
	b.clip_text = false
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var m := meret
	if m == Vector2.ZERO:
		m = Vector2(152, 54) if nagy else Vector2(164, 74)
	b.custom_minimum_size = m
	b.add_theme_font_size_override("font_size", 14 if nagy else 11)
	b.add_theme_color_override("font_color", Color("f2efe6"))
	var alap := Style.button_box(Color(szin.r, szin.g, szin.b, 0.88),
		szin.lightened(0.35))
	_kerekit(alap)
	alap.shadow_color = Color(0, 0, 0, 0.5)
	alap.shadow_size = 6
	var rajta := Style.button_box(szin.lightened(0.18), Color("f0e6c8"))
	_kerekit(rajta)
	b.add_theme_stylebox_override("normal", alap)
	b.add_theme_stylebox_override("hover", rajta)
	b.add_theme_stylebox_override("pressed", rajta)
	b.pressed.connect(fn)
	add_child(b)
	# A tábla a SZÖVEGÉHEZ nő (a hosszú ár nem lóghat ki belőle), ezért a
	# helyét csak most tudjuk kiszámolni. A legyező tábláit kifelé toljuk a
	# saját félszélességükkel, különben a belső végük egymásra és a középső
	# "vissza" gombra csúszna.
	b.reset_size()
	var hely := eltol
	if eltol != Vector2.ZERO:
		var irany := eltol.normalized()
		hely += Vector2(irany.x * b.size.x * 0.5 * absf(irany.x),
			irany.y * b.size.y * 0.5 * absf(irany.y))
	b.set_meta("eltol", hely)
	b.set_meta("nagy", nagy)
	return b

# Kerek, legyezőbe való gomb: a szűk belső margó azért kell, hogy a három
# sor (név, hozam, ár) kiférjen, és ne vágódjon le az ára.
func _kerekit(sb: StyleBoxFlat) -> void:
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
