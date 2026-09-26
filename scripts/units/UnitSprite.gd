extends Sprite2D

# AZ EGYSÉGEK RAJZA — a böngészős eredeti (index.html drawUnit, drawLPC,
# drawNapoleon, drawNapRole, drawWW2, paintCav, paintSiege, paintRam,
# paintMedic, paintTank, paintPlane, paintShip) pontos átirata.
#
# A Godot-port korábban saját utat járt: 46 képpontra nagyított, éles
# (legközelebbi szomszéd) szűrésű alakok, rájuk rajzolt fegyverek, nemzeti
# fejfedők és csapatszínű átfestés. Az eredetiben ezek közül egyik sem volt:
# ott a lapról vett alak KICSI (a 64x64-es kocka 0,38-szorosa, a test
# sugarához mérve), SIMÍTOTT, és semmi nem kerül rá — a csapatot a talp alatti
# gyűrű mutatja (ezt a Unit.gd rajzolja). Ez a fájl ezt a képet adja vissza.
#
# LAPOK (mind 64x64-es kockák):
#   LPC       384x256 —  6 oszlop x 4 sor.  Sor: 0=É, 1=Ny, 2=D, 3=K
#             col 0 = álló, 1-4 = járás, 1-5 = csapás
#   Napóleon  960x256 — 15 oszlop x 4 sor.  Sorrend mint az LPC-nél
#             col 0-8 = járás (9 kocka), col 9-14 = csapás (6 kocka)
#   WW2       320x256 —  5 oszlop x 4 sor.  Sor: 0=D, 1=Ny, 2=É, 3=K  <- Más!
#             col 0 = álló, 1-4 = járás (csapás nincs)
#   Ló        320x256 —  5 oszlop x 4 sor (lásd HORSE_ROWS)
#
# KORSZAK -> LAP (drawLPC):
#   0 = LPC lap a szerep szerint (munkás, vitéz, íjász, pikás, pap, kém)
#   1 = napóleoni lap: a lövész és a pikás a sajátját kapja, mindenki más a
#       napóleoni gyalogosét (drawNapRole -> drawNapoleon)
#   2-3 = világháborús lap: saját/szövetséges = "ally", ellenség = "axis"
#   A 20. századi "közelharcos" harckocsi (paintTank).
#
# Rajzolás: drawImage(img, ..., -FW*0.5, -FH*0.82, FW, FH), a vászon előtte
# s*0.38-ra kicsinyítve, ahol s = r / 9.2 (r = a test sugara). A talp tehát
# a kocka 82%-ánál van.

const FW := 64
const FH := 64
const LAP_K := 0.38            # a lap kicsinyítése (HTML: lpcScale = s*0.38)
const TALP := 0.82             # a talp a kocka magasságának ennyiszeresénél

# Irány -> sor. Index: 0=Kelet, 1=Dél, 2=Nyugat, 3=Észak
const ROWS_LPC := [3, 2, 1, 0]
const ROWS_WW2 := [3, 0, 1, 2]
# A ló lapja (lemérve): 0. sor vágta BALRA, 1. sor vágta JOBBRA,
# 2. sor lépés BALRA (0. kocka: szemből), 3. sor lépés JOBBRA (0. kocka:
# hátulról). Az eredeti az LPC-sorrendet használta, amitől nyugatnak menet
# a ló jobbra nézett — itt a lépő sorokat vesszük, a szemből/hátulról álló
# kockával délre és északra.
const HORSE_ROWS := [3, 2, 2, 3]

# Melyik LPC lap illik a szerephez (a HUD ikonjai is ebből dolgoznak).
const LPC_FOR := {
	"worker": "worker", "melee": "melee", "ranged": "ranged", "spear": "spear",
	"priest": "priest", "spy": "spy", "hero": "melee",
}
# A napóleoni készlet: csak a lövésznek és a pikásnak van saját lapja.
const NAP_FOR := {"ranged": "ranged", "spear": "spear"}
# A lapokról lemért alakméret [az alak magassága, a talp sora] a kockán —
# a HUD ikonja ebből vág szorosan az alak köré.
const SHEET_METRICS := {
	"lpc/worker":     [47.0, 61.0],
	"lpc/spy":        [47.0, 61.0],
	"lpc/priest":     [48.0, 61.0],
	"lpc/melee":      [50.0, 63.0],
	"lpc/spear":      [51.0, 63.0],
	"lpc/ranged":     [54.0, 61.0],
	"napoleon/melee": [55.0, 61.0],
	"napoleon/ranged":[55.0, 61.0],
	"napoleon/spear": [55.0, 61.0],
	"ww2":            [61.0, 61.0],
	"horse":          [30.0, 46.0],
}
const NAVAL_ROLES := ["fisher", "warship", "galleon", "transport"]
const AIR_ROLES := ["fighter", "bomber"]
# Akiket az eredeti lapról rajzolt (drawUnit: lpcRoles). A hős rajzolója
# (paintHero) az eredetiből hiányzott — ő a vitéz lapját kapja.
const LAP_SZEREPEK := ["worker", "melee", "ranged", "spear", "priest", "spy", "hero"]
# A hajók hossza az eredetiből (paintShip L0).
const SHIP_L0 := {"galleon": 46.0, "warship": 38.0, "transport": 34.0, "fisher": 26.0}

enum Kind { LAP, LO, HAJO, GEP, TANK, RAJZ, NONE }

var _kind : int = Kind.NONE
var _role : String = ""
var _age  : int = 0
var _owner_id : int = 0
var _nemzet : String = "hu"      # a jelleg-próba (SelfTest) még írja
var _s : float = 1.0             # r / 9.2
var _tex : Texture2D = null      # a lap (vagy a hajó képe)
var _sheet_key : String = ""
var _rows : Array = ROWS_LPC
var _lap : String = "lpc"        # "lpc" | "nap" | "ww2"
var _col  : int = 0
var _row  : int = 0
var _dir  : int = 1
var _pose : String = "front"     # side | front | back (poseOf)
var _pf   : float = 1.0          # a póz tükrözése
var _flip : float = 0.0          # oldalnézet iránya (sideFlip), 0 = még nincs
var _moving : bool = false
var _fired : bool = false
var _walk : float = 0.0
var _col_c : Color = Color.WHITE  # csapatszín (ownerColor)
var _acc_c : Color = Color.WHITE  # kiemelőszín (ownerAccent)
var _fust_t0 : float = -99.0      # az utolsó lövés ideje (lőporfüst)
var _anim_t : float = 0.0         # a folyamatos mozgások (hajó, gép) üteme
var _last_redraw : int = 0

func setup(role: String, age: int, owner_id: int) -> void:
	centered = true
	texture = null
	region_enabled = false
	offset = Vector2.ZERO
	rotation = 0.0
	self_modulate = Color.WHITE
	# Az eredeti vászonra simítva rajzolt: a kicsinyített képpontlap így lesz
	# tiszta kis figura (legközelebbi szomszéddal fogazott és vibrál).
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_role = role
	_age = clampi(age, 0, 3)
	_owner_id = owner_id
	_nemzet = str(GameState.get_side(owner_id).get("nemzet", GameState.nation))
	_col_c = Style.side_color(owner_id)
	_acc_c = Style.side_accent(owner_id)
	_s = Combat.radius_for(role, _age) / 9.2
	_tex = null
	_kind = Kind.NONE
	_flip = 0.0
	if role in NAVAL_ROLES:
		_kind = Kind.HAJO
		_tex = _load("res://assets/sprites/ship/%s.png" % role)
		scale = Vector2.ONE
	elif role in AIR_ROLES:
		_kind = Kind.GEP
		scale = Vector2.ONE
	elif role == "melee" and _age == 3:
		_kind = Kind.TANK
		scale = Vector2(_s * 0.62, _s * 0.62)
	elif role == "cav":
		_kind = Kind.LO
		_tex = _load("res://assets/sprites/horse.png")
		_sheet_key = "horse"
		scale = Vector2(_s, _s)
	elif role in LAP_SZEREPEK:
		_setup_lap(role)
		scale = Vector2(_s, _s)
	else:
		# ostromgép, faltörő kos, felcser: rajzolt alakok
		_kind = Kind.RAJZ
		scale = Vector2(_s, _s)
	# Kezdő póz: szemből, állva (az első update_anim előtt is értelmes kép).
	_dir = 1
	_pose = "front"
	_pf = 1.0
	_col = 1 if _kind == Kind.LO else 0
	_row = int(HORSE_ROWS[1]) if _kind == Kind.LO else int(_rows[1])
	queue_redraw()

func _load(path: String) -> Texture2D:
	if not ResourceLoader.exists(path): return null
	return load(path) as Texture2D

func _setup_lap(role: String) -> void:
	var r2: String = "melee" if role == "hero" else role
	if _age >= 2:
		var side := "ally" if GameState.en_id == _owner_id \
			or not GameState.hostile(GameState.en_id, _owner_id) else "axis"
		_tex = _load("res://assets/sprites/ww2/%s.png" % side)
		_lap = "ww2"
		_sheet_key = "ww2"
		_rows = ROWS_WW2
	elif _age == 1:
		var lap: String = str(NAP_FOR.get(r2, "melee"))
		_tex = _load("res://assets/sprites/napoleon/%s.png" % lap)
		_lap = "nap"
		_sheet_key = "napoleon/" + lap
		_rows = ROWS_LPC
	if _tex == null:
		var lap2: String = str(LPC_FOR.get(r2, "melee"))
		_tex = _load("res://assets/sprites/lpc/%s.png" % lap2)
		_lap = "lpc"
		_sheet_key = "lpc/" + lap2
		_rows = ROWS_LPC
	_kind = Kind.LAP if _tex != null else Kind.NONE

# A lap a helyén van-e (az önteszt kérdezi).
func has_sheet() -> bool:
	return _tex != null or _kind in [Kind.TANK, Kind.GEP, Kind.RAJZ]

func sheet_key() -> String:
	return _sheet_key

# Az alak magassága világképpontban (az önteszthez és a HUD-hoz).
func figure_height() -> float:
	var m: Array = SHEET_METRICS.get(_sheet_key, [50.0, 61.0])
	return float(m[0]) * LAP_K * _s

# --- IRÁNY ---

func _dir_index(face: float) -> int:
	var deg := fmod(rad_to_deg(face) + 360.0, 360.0)
	if   deg > 315.0 or deg <= 45.0:  return 0  # Kelet
	elif deg <= 135.0:                return 1  # Dél
	elif deg <= 225.0:                return 2  # Nyugat
	else:                             return 3  # Észak

# poseOf: nyolc irány -> három póz (oldalt, szemből, hátulról) + tükrözés.
static func pose_of(face: float) -> Array:
	var a := fposmod(face, TAU)
	var s := int(round(a / (TAU / 8.0))) % 8
	match s:
		0: return ["side", 1.0]
		1, 2: return ["front", 1.0]
		3: return ["front", -1.0]
		4: return ["side", -1.0]
		5: return ["back", -1.0]
		_: return ["back", 1.0]

# sideFlip: a jármű mindig oldalról látszik; a tükrözés csak akkor vált, ha az
# irány egyértelműen balra vagy jobbra mutat.
func _side_flip(face: float) -> float:
	var c := cos(face)
	if _flip == 0.0: _flip = -1.0 if c < 0.0 else 1.0
	if c > 0.22: _flip = 1.0
	elif c < -0.22: _flip = -1.0
	return _flip

# --- ANIMÁCIÓ ---

func update_anim(face: float, walk: float, moving: bool, fired: bool) -> void:
	if fired and not _fired: _fust_t0 = Time.get_ticks_msec() / 1000.0
	var d := _dir_index(face)
	var po := pose_of(face)
	var col := 0
	var row := 0
	match _kind:
		Kind.LAP:
			row = int(_rows[d])
			col = _lap_col(walk, moving, fired)
		Kind.LO:
			row = int(HORSE_ROWS[d])
			# Állva is oldalnézet (1. kocka): a 0. kocka szemből/hátulról
			# mutatja a lovat, azon a lovas pálcikán ülő alaknak látszott.
			if moving: col = 1 + int(floor(walk * 2.5)) % 4
			else: col = 1
		Kind.TANK, Kind.GEP:
			_side_flip(face)
	var valtozott := col != _col or row != _row or d != _dir or fired != _fired \
		or moving != _moving or str(po[0]) != _pose or float(po[1]) != _pf
	_col = col
	_row = row
	_dir = d
	_pose = str(po[0])
	_pf = float(po[1])
	_moving = moving
	_fired = fired
	_walk = walk
	# A folyamatosan mozgó részek (hullám, légcsavar, lánctalp, kerék, lőporfüst)
	# nem kockához kötöttek: ezeknél ritkítva, de rendszeresen rajzolunk újra.
	var eleven := _kind == Kind.HAJO or _kind == Kind.GEP \
		or (_moving and (_kind == Kind.TANK or _kind == Kind.RAJZ)) or _fust_aktiv()
	var most := Time.get_ticks_msec()
	if valtozott:
		_last_redraw = most
		queue_redraw()
	elif eleven and most - _last_redraw >= 50:
		_last_redraw = most
		queue_redraw()

func _lap_col(walk: float, moving: bool, fired: bool) -> int:
	var ms := Time.get_ticks_msec()
	match _lap:
		"nap":
			if fired: return 9 + int(ms / 80) % 6
			if moving: return int(floor(walk * 2.5)) % 9
			return 0
		"ww2":
			if moving: return 1 + int(floor(walk * 2.5)) % 4
			return 0
		_:
			if fired: return 1 + int(ms / 80) % 5
			if moving: return 1 + int(floor(walk * 2.5)) % 4
			return 0

func _fust_aktiv() -> bool:
	if not (_role in ["ranged", "spear"]) or _age <= 0: return false
	return Time.get_ticks_msec() / 1000.0 - _fust_t0 < 0.44

func _t() -> float:
	return Time.get_ticks_msec() / 1000.0

# --- RAJZ ---

func _draw() -> void:
	match _kind:
		Kind.LAP:  _draw_lap()
		Kind.LO:   _draw_lovas()
		Kind.HAJO: _draw_hajo()
		Kind.GEP:  _draw_gep()
		Kind.TANK: _draw_tank()
		Kind.RAJZ: _draw_rajzolt()
		_: draw_circle(Vector2(0, -8), 6.0, _col_c)

# Egy kocka a lapról, a talp a csomópont origójában.
func _draw_lap() -> void:
	if _tex == null: return
	var w := FW * LAP_K
	var h := FH * LAP_K
	draw_texture_rect_region(_tex, Rect2(-w * 0.5, -h * TALP, w, h),
		Rect2(_col * FW, _row * FH, FW, FH))
	_draw_puttony()
	_draw_lofust()

# A munkás hátizsákja, ha visz valamit (drawUnit: u.carry > 0).
func _draw_puttony() -> void:
	var u := get_parent()
	if u == null or not ("_carry" in u): return
	if float(u.get("_carry")) <= 0.0: return
	var fajta := str(u.get("_carry_kind"))
	var c2 := Color("d4af37")
	if fajta == "wood": c2 = Color("7a5230")
	elif fajta == "stone": c2 = Color("9a9ca0")
	elif fajta == "food": c2 = Color("c9a15a")
	var k := 1.0 / maxf(_s, 0.01)          # az eredeti nem nagyítva rajzolta
	var x := 0.0 if _pose == "back" else -4.4
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	_ell(Vector2(x, -9.5), Vector2(3.2, 3.8), Color("8a6a45"), 0.2)
	_ell(Vector2(x, -10.6), Vector2(2.4, 1.8), c2, 0.2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# Lőporfüst a csőnél a lövés után (drawUnit: powderSmoke).
func _draw_lofust() -> void:
	if not _fust_aktiv(): return
	var t := clampf((_t() - _fust_t0) / 0.55, 0.0, 2.0)
	var o := Vector2(19.0, -10.6)
	var ang := -0.5
	if _pose == "front":
		o = Vector2(13.0, -4.0)
		ang = 0.5
	elif _pose == "back":
		o = Vector2(13.0, -16.0)
		ang = -1.2
	var fl := -1.0 if _dir == 2 else 1.0
	var k := 1.0 / maxf(_s, 0.01)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k * fl, k))
	for i in range(3):
		var kk := t + float(i) * 0.18
		if kk > 1.0: continue
		draw_circle(Vector2(o.x + cos(ang) * (5.0 + kk * 11.0),
			o.y + sin(ang) * (5.0 + kk * 11.0) - kk * 3.0), 1.8 + kk * 4.2,
			Color(228.0 / 255.0, 226.0 / 255.0, 215.0 / 255.0, 0.5 * (1.0 - kk)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# --- LOVASSÁG (paintCav) ---
# A ló a lapról, 0,38-szoros méretben, a talpa a kocka 85%-ánál; a lovas
# egyszerű alak a hátán: csapatszínű törzs, kiemelőszínű vállszalag, fej és
# a korszak sisakja.
const SKIN := [Color("e3b78e"), Color("d3a377"), Color("c08f63"), Color("eec49f")]

func _draw_lovas() -> void:
	var sc := LAP_K
	if _tex != null:
		draw_texture_rect_region(_tex, Rect2(-FW * sc * 0.5, -FH * sc * 0.85,
			FW * sc, FH * sc), Rect2(_col * FW, _row * FH, FW, FH))
	# Az eredeti -FH*sc*0.52-re ültette a lovast, ami a ló háta fölött
	# lebegett; a lépő kockákon a hát a kocka 28. sora körül van.
	var o := Vector2(0.0, -FH * sc * 0.41)
	var hw := 4.0
	_poly([o + Vector2(-hw, -10), o + Vector2(hw, -10), o + Vector2(hw + 1, 0),
		o + Vector2(-hw - 1, 0)], _col_c)
	_rect(o.x - hw, o.y - 10.0, hw * 2.0, 2.0, _acc_c)
	draw_circle(o + Vector2(0, -13), 3.0, SKIN[_age % 3])
	var sisak := [Color("c3c8ce"), Color("8a4a2a"), _shade(_col_c, -0.4), Color("5a6152")]
	_felkor(o + Vector2(0, -14.5), 3.2, sisak[mini(_age, 3)])

# --- HAJÓK (paintShip) ---
# A képek oldalnézetiek, az orr BALRA néz. Oldalt a teljes hossz (L0*2),
# szemből és hátulról összenyomva; a hajó a vízvonala körül billeg, alatta
# hab, menet közben nyomvonal.
func _draw_hajo() -> void:
	var l0: float = SHIP_L0.get(_role, 26.0)
	var narrow := _pose != "side"
	var t := _t()
	var ph := t * (5.0 if _moving else 1.6)
	var bill := sin(ph * 0.6) * (0.05 if _moving else 0.03)
	if _moving:
		# nyomvonal a tat mögött
		var hatra := 1.0 if cos(_face_from_pose()) <= 0.0 else -1.0
		for i in range(4):
			var ox := l0 * (0.35 + float(i) * 0.28) * hatra
			var ow := l0 * (0.22 + float(i) * 0.08)
			_ell(Vector2(ox, 3.0 + float(i) * 2.0), Vector2(ow, ow * 0.3),
				Color(0.8, 0.933, 1.0, 0.22))
	var fr := l0 * (0.35 if narrow else 0.55)
	var fa := (0.42 if _moving else 0.26) * (0.7 + sin(ph) * 0.3)
	_ell(Vector2(0, 2), Vector2(fr, fr * 0.28), Color(0.867, 0.957, 1.0, fa))
	if _tex == null: return
	var aspect := float(_tex.get_height()) / maxf(float(_tex.get_width()), 1.0)
	var sx := -_pf
	var dw := l0 * 2.0
	if _pose == "front":
		sx = _pf
		dw = l0 * 0.55
	elif _pose == "back":
		dw = l0 * 0.5
	var dh := dw * aspect
	draw_set_transform(Vector2.ZERO, bill, Vector2(sx, 1.0))
	draw_texture_rect(_tex, Rect2(-dw * 0.5, -dh, dw, dh), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# A póz irányából visszaszámolt nézési szög (a nyomvonal oldalához elég).
func _face_from_pose() -> float:
	match _dir:
		0: return 0.0
		1: return PI * 0.5
		2: return PI
		_: return -PI * 0.5

# Hajó méretei a Unit.gd életsávjához (drawUnit: a hajó fölötti magasság).
static func ship_bar_height(role: String) -> float:
	match role:
		"galleon": return 100.0
		"warship": return 90.0
		"transport": return 55.0
		_: return 62.0

# --- REPÜLŐGÉP (paintPlane, oldalnézet) ---
func _draw_gep() -> void:
	var t := _t()
	var jet := _role == "fighter"
	var l := 36.0 if _role == "bomber" else 30.0
	var body := Color("5d6358") if _role == "bomber" else _col_c.lerp(Color("48545f"), 0.42)
	var dark := _shade(body, -0.34)
	var light := _shade(body, 0.24)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_flip if _flip != 0.0 else 1.0, 1.0))
	# távolabbi szárny
	_poly([Vector2(-l * 0.02, -6), Vector2(l * 0.2, -9.5), Vector2(l * 0.3, -7.5),
		Vector2(l * 0.06, -4.5)], dark)
	# törzs
	var p := PackedVector2Array([Vector2(l * 0.5, -1.5)])
	_quad(p, Vector2(l * 0.34, -7), Vector2(-l * 0.1, -6.6))
	p.append(Vector2(-l * 0.42, -4.6))
	_quad(p, Vector2(-l * 0.52, -2), Vector2(-l * 0.42, 0.6))
	p.append(Vector2(-l * 0.06, 2.6))
	_quad(p, Vector2(l * 0.3, 2.8), Vector2(l * 0.5, -1.5))
	p.remove_at(p.size() - 1)
	_poly(p, body)
	var p2 := PackedVector2Array([Vector2(l * 0.5, -1.5)])
	_quad(p2, Vector2(l * 0.34, -7), Vector2(-l * 0.1, -6.6))
	p2.append(Vector2(-l * 0.42, -4.6))
	p2.append(Vector2(-l * 0.3, -3.2))
	_quad(p2, Vector2(l * 0.1, -4.4), Vector2(l * 0.46, -1.8))
	_poly(p2, light)
	# vezérsík, felségcsík, vízszintes farokfelület
	_poly([Vector2(-l * 0.3, -5.4), Vector2(-l * 0.44, -15), Vector2(-l * 0.5, -15),
		Vector2(-l * 0.46, -4.6)], _shade(body, -0.16))
	_rect(-l * 0.5, -12.5, l * 0.13, 2.4, _acc_c)
	_poly([Vector2(-l * 0.34, -3.8), Vector2(-l * 0.56, -5.8), Vector2(-l * 0.56, -4.2),
		Vector2(-l * 0.36, -2.6)], dark)
	# közelebbi szárny
	_poly([Vector2(l * 0.02, -2.4), Vector2(l * 0.26, 3.4), Vector2(l * 0.1, 5.6),
		Vector2(-l * 0.16, 0.6)], _shade(body, 0.08))
	_poly([Vector2(l * 0.02, -2.4), Vector2(l * 0.26, 3.4), Vector2(l * 0.2, 4.2),
		Vector2(-l * 0.02, -1.6)], Color(0, 0, 0, 0.16))
	draw_circle(Vector2(l * 0.08, 1.6), 2.8, _col_c)
	draw_circle(Vector2(l * 0.08, 1.6), 1.3, _acc_c)
	# kabin
	var k := PackedVector2Array([Vector2(l * 0.06, -6.6)])
	_quad(k, Vector2(l * 0.2, -9.4), Vector2(l * 0.3, -5.6))
	_poly(k, Color("9fc4d6"))
	_ell(Vector2(l * 0.16, -7), Vector2(1.8, 1.0), Color(1, 1, 1, 0.45), 0.3)
	draw_line(Vector2(l * 0.06, -6.6), Vector2(l * 0.3, -5.6), _shade(body, -0.3), 0.9)
	if _role == "bomber":
		for q in [Vector2(l * 0.12, 1.2), Vector2(l * 0.2, 3.4)]:
			var qq: Vector2 = q
			_ell(qq, Vector2(4.4, 2.4), dark, 0.2)
			_prop_disc(qq + Vector2(5.0, -0.4), 6.0, t)
	elif jet:
		_poly([Vector2(-l * 0.46, -3.4), Vector2(-l * 0.46 - 9.0 - sin(t * 30.0) * 4.0, -1.8),
			Vector2(-l * 0.46, -0.2)], Color(1.0, 0.77, 0.376, 0.5 + sin(t * 22.0) * 0.2))
	else:
		_prop_disc(Vector2(l * 0.52, -1.6), 9.0, t)
	if _fired: _muzzle(Vector2(l * 0.56, -1.5), 3.4)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _prop_disc(c: Vector2, r: float, t: float) -> void:
	_ell(c, Vector2(r * 0.24, r), Color(210.0 / 255.0, 210.0 / 255.0, 200.0 / 255.0, 0.2))
	var a := t * 30.0
	draw_line(c + Vector2(0, -cos(a) * r), c + Vector2(0, cos(a) * r),
		Color(240.0 / 255.0, 240.0 / 255.0, 230.0 / 255.0, 0.42), 1.0)
	draw_circle(c, 1.7, Color("3a3f43"))

# --- HARCKOCSI (paintTank, oldalnézet) ---
func _draw_tank() -> void:
	var t := _t()
	var l := 34.0
	var h := 17.0
	var body := _col_c.lerp(Color("5c6148"), 0.62)
	var dark := _shade(body, -0.42)
	var light := _shade(body, 0.2)
	var ph := t * (4.0 if _moving else 0.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_flip if _flip != 0.0 else 1.0, 1.0))
	if _moving:
		for i in range(3):
			var k := fmod(t * 1.6 + float(i) * 0.33, 1.0)
			_ell(Vector2(-l * 0.5 - k * 12.0, h * 0.36), Vector2(3.0 + k * 7.0, 1.6 + k * 3.0),
				Color(150.0 / 255.0, 135.0 / 255.0, 105.0 / 255.0, 0.22))
	# lánctalp
	var tp := PackedVector2Array([Vector2(-l * 0.5, -h * 0.1), Vector2(l * 0.5, -h * 0.1)])
	_quad(tp, Vector2(l * 0.58, h * 0.22), Vector2(l * 0.46, h * 0.34))
	tp.append(Vector2(-l * 0.46, h * 0.34))
	_quad(tp, Vector2(-l * 0.58, h * 0.22), Vector2(-l * 0.5, -h * 0.1))
	tp.remove_at(tp.size() - 1)
	_poly(tp, dark)
	for i in range(-3, 4):
		draw_circle(Vector2(float(i) * l * 0.135, h * 0.2), h * 0.11, _shade(dark, 0.28))
	draw_circle(Vector2(-l * 0.44, h * 0.14), h * 0.16, _shade(dark, 0.4))
	draw_circle(Vector2(l * 0.44, h * 0.14), h * 0.16, _shade(dark, 0.4))
	var off := fmod(ph * 7.0, 6.0)
	var x := -l * 0.5 + off
	while x < l * 0.5:
		draw_line(Vector2(x, -h * 0.1), Vector2(x, h * 0.34), _shade(dark, -0.3), 1.1)
		x += 6.0
	_rect(-l * 0.5, -h * 0.1, l, 2.4, Color(1.0, 0.98, 0.92, 0.12))
	# páncéltest
	_poly([Vector2(-l * 0.46, -h * 0.12), Vector2(-l * 0.34, -h * 0.5),
		Vector2(l * 0.28, -h * 0.5), Vector2(l * 0.5, -h * 0.12)], body)
	_poly([Vector2(-l * 0.34, -h * 0.5), Vector2(l * 0.28, -h * 0.5),
		Vector2(l * 0.22, -h * 0.36), Vector2(-l * 0.3, -h * 0.36)], light)
	_rect(-l * 0.5, -h * 0.16, l, 2.2, Color(0, 0, 0, 0.2))
	draw_line(Vector2(-l * 0.1, -h * 0.5), Vector2(-l * 0.1, -h * 0.14), _shade(body, -0.3), 1.0)
	# torony
	var ty := -h * 0.5
	_poly([Vector2(-l * 0.2, ty), Vector2(-l * 0.16, ty - h * 0.42),
		Vector2(l * 0.12, ty - h * 0.42), Vector2(l * 0.2, ty)], _shade(body, 0.06))
	_poly([Vector2(-l * 0.16, ty - h * 0.42), Vector2(l * 0.12, ty - h * 0.42),
		Vector2(l * 0.08, ty - h * 0.3), Vector2(-l * 0.12, ty - h * 0.3)], light)
	_ell(Vector2(-l * 0.02, ty - h * 0.44), Vector2(l * 0.07, h * 0.09), _shade(body, -0.24))
	_ell(Vector2(-l * 0.03, ty - h * 0.47), Vector2(l * 0.05, h * 0.06), _shade(body, 0.3))
	_rect(l * 0.18, ty - h * 0.3, l * 0.42, 3.4, _shade(body, -0.14))
	_rect(l * 0.52, ty - h * 0.33, l * 0.1, 4.6, _shade(body, -0.34))
	_rect(l * 0.18, ty - h * 0.3, l * 0.42, 1.2, Color(1.0, 0.98, 0.92, 0.16))
	# felségjel, rendszám
	draw_circle(Vector2(-l * 0.26, -h * 0.3), 2.6, _col_c)
	draw_circle(Vector2(-l * 0.26, -h * 0.3), 1.2, _acc_c)
	_rect(l * 0.06, -h * 0.28, 5.0, 1.6, Color(0.94, 0.93, 0.89, 0.5))
	if _moving:
		for i in range(2):
			var k2 := fmod(t * 0.9 + float(i) * 0.5, 1.0)
			draw_circle(Vector2(-l * 0.5 - k2 * 9.0, -h * 0.34 - k2 * 7.0), 1.6 + k2 * 3.4,
				Color(110.0 / 255.0, 104.0 / 255.0, 94.0 / 255.0, 0.3 * (1.0 - k2)))
	if _fired: _muzzle(Vector2(l * 0.66, ty - h * 0.28), 4.2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# --- RAJZOLT ALAKOK: ostromgép, faltörő kos, felcser ---
func _draw_rajzolt() -> void:
	# a járás közbeni billenés (unitSprite: translate(0, -|sin(phase)|*0.9))
	var dy := 0.0
	if _moving: dy = -absf(sin(float(int(floor(_walk / (TAU / 4.0))) % 4) * TAU / 4.0)) * 0.9
	draw_set_transform(Vector2(0, dy), 0.0, Vector2(_pf, 1.0))
	match _role:
		"siege": _paint_siege()
		"ram": _paint_ram()
		"medic": _paint_medic()
		_: draw_circle(Vector2(0, -8), 6.0, _col_c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

const FA_SIEGE := ["6b4b28", "5f5348", "54585c", "4a5a4e"]
const VAS_SIEGE := ["54585c", "4a4e52", "3f4348", "3a4a40"]
const FA_RAM := ["6b4b28", "67492a", "5f5348", "54585c"]

func _paint_siege() -> void:
	var a := _age
	var narrow := _pose != "side"
	var fa := Color(str(FA_SIEGE[a]))
	var vas := Color(str(VAS_SIEGE[a]))
	var l := 18.0 if narrow else 30.0
	var t := _t()
	if a < 3:
		var xs: Array = [0.0] if narrow else [-l * 0.3, l * 0.28]
		for xv in xs:
			var xw: float = xv
			draw_circle(Vector2(xw, 0), 5.4, _shade(fa, -0.3))
			for i in range(4):
				var ang := t * (3.0 if _moving else 0.0) + float(i) * TAU / 8.0
				draw_line(Vector2(xw - cos(ang) * 4.0, -sin(ang) * 4.0),
					Vector2(xw + cos(ang) * 4.0, sin(ang) * 4.0), _shade(fa, 0.2), 1.0)
	else:
		_rect(-l * 0.5, -2, l, 6, vas)
		var x := -l * 0.5
		while x < l * 0.5:
			_rect(x, -2, 2, 6, _shade(vas, 0.2))
			x += 5.0
	# váz
	_poly([Vector2(-l * 0.5, -4), Vector2(l * 0.42, -4), Vector2(l * 0.42, -1),
		Vector2(-l * 0.5, -1)], fa)
	_rect(-l * 0.5, -4, l * 0.92, 1.2, Color(1.0, 0.98, 0.92, 0.12))
	if narrow:
		draw_circle(Vector2(0, -9), 4.2, vas)
		draw_circle(Vector2(0, -9), 2.0, Color("22261f"))
	elif a == 0:
		# katapult: vetőkar
		var feszit := -0.9 if _fired else -2.1
		var p0 := Vector2(-l * 0.06, -5)
		var dir := Vector2(cos(feszit), sin(feszit))
		draw_line(p0, p0 + dir * 20.0, fa, 3.4)
		draw_circle(p0, 1.7, fa)
		draw_circle(p0 + dir * 20.0, 1.7, fa)
		draw_circle(p0 + dir * 21.0, 3.6, _shade(fa, -0.2))
		draw_line(Vector2(-l * 0.4, -4), Vector2(-l * 0.06, -5), _shade(fa, -0.25), 1.4)
		_poly([Vector2(-l * 0.12, -4), Vector2(-l * 0.02, -15), Vector2(l * 0.06, -4)], fa)
	elif a == 1:
		# mozsár: rövid, meredek cső
		var tr := Transform2D(-0.95, Vector2(0, -6))
		_poly(_tr(tr, [Vector2(0, -4), Vector2(15, -4), Vector2(15, 4), Vector2(0, 4)]), vas)
		_poly(_tr(tr, [Vector2(0, -4), Vector2(15, -4), Vector2(15, -2), Vector2(0, -2)]),
			_shade(vas, 0.22))
		_poly(_tr(tr, [Vector2(13, -3.4), Vector2(16, -3.4), Vector2(16, 3.4), Vector2(13, 3.4)]),
			Color("22261f"))
		_poly([Vector2(-8, -4), Vector2(-5, -11), Vector2(5, -11), Vector2(8, -4)],
			_shade(fa, -0.1))
	elif a == 2:
		# tarack lövegpajzzsal
		var tr2 := Transform2D(-0.28, Vector2(1, -8))
		_poly(_tr(tr2, [Vector2(0, -2.2), Vector2(22, -2.2), Vector2(22, 2.2), Vector2(0, 2.2)]), vas)
		_poly(_tr(tr2, [Vector2(0, -2.2), Vector2(22, -2.2), Vector2(22, -1), Vector2(0, -1)]),
			_shade(vas, 0.2))
		_poly(_tr(tr2, [Vector2(20, -2.6), Vector2(23, -2.6), Vector2(23, 2.6), Vector2(20, 2.6)]),
			Color("22261f"))
		_poly([Vector2(-2, -2), Vector2(-4, -16), Vector2(6, -16), Vector2(5, -2)],
			_shade(vas, 0.1))
		_rect(-4, -16, 10, 1.6, Color(1, 1, 1, 0.1))
	else:
		# vontatott tüzérség
		var tr3 := Transform2D(-0.22, Vector2(2, -9))
		_poly(_tr(tr3, [Vector2(0, -2), Vector2(28, -2), Vector2(28, 2), Vector2(0, 2)]), vas)
		_poly(_tr(tr3, [Vector2(0, -2), Vector2(28, -2), Vector2(28, -0.9), Vector2(0, -0.9)]),
			_shade(vas, 0.24))
		_poly(_tr(tr3, [Vector2(26, -2.6), Vector2(30, -2.6), Vector2(30, 2.6), Vector2(26, 2.6)]),
			Color("22261f"))
		_poly([Vector2(-3, -3), Vector2(-5, -17), Vector2(8, -17), Vector2(6, -3)],
			_shade(vas, 0.08))
		draw_line(Vector2(-4, -2), Vector2(-l * 0.55, 4), _shade(vas, -0.2), 2.0)
	# felségjel
	draw_circle(Vector2(-l * 0.34, -6), 2.4, _col_c)
	draw_circle(Vector2(-l * 0.34, -6), 1.1, _acc_c)
	if _fired and not narrow: _muzzle(Vector2(l * 0.6, -9), 5.6)

func _paint_ram() -> void:
	var a := _age
	var narrow := _pose != "side"
	var fa := Color(str(FA_RAM[a]))
	var l := 16.0 if narrow else 32.0
	var xs: Array = [0.0] if narrow else [-l * 0.32, 0.0, l * 0.32]
	for xv in xs:
		draw_circle(Vector2(float(xv), 0), 4.6, _shade(fa, -0.35))
	_rect(-l * 0.44, -6, l * 0.88, 4, fa)
	# ponyvatető
	var p := PackedVector2Array([Vector2(-l * 0.46, -8)])
	_quad(p, Vector2(0, -19), Vector2(l * 0.46, -8))
	_poly(p, Color("8a7a5a") if a < 2 else _shade(fa, 0.1))
	var p2 := PackedVector2Array([Vector2(-l * 0.46, -8)])
	_quad(p2, Vector2(0, -19), Vector2(0, -8))
	_poly(p2, Color(0, 0, 0, 0.16))
	if not narrow:
		var ki := 7.0 if _fired else 0.0
		draw_line(Vector2(-l * 0.3 + ki, -9), Vector2(l * 0.42 + ki, -9), _shade(fa, -0.15), 4.4)
		draw_circle(Vector2(-l * 0.3 + ki, -9), 2.2, _shade(fa, -0.15))
		_ell(Vector2(l * 0.48 + ki, -9), Vector2(4.6, 3.4),
			Color("6a6e72") if a < 2 else Color("4a4e52"))
		_poly([Vector2(l * 0.44 + ki, -11.6), Vector2(l * 0.5 + ki, -13.6),
			Vector2(l * 0.52 + ki, -10.4)], _shade(Color("6a6e72"), -0.3))
		var kot := Color(70.0 / 255.0, 55.0 / 255.0, 35.0 / 255.0, 0.8)
		draw_line(Vector2(-l * 0.16, -15), Vector2(-l * 0.16 + ki, -9), kot, 1.0)
		draw_line(Vector2(l * 0.2, -15), Vector2(l * 0.2 + ki, -9), kot, 1.0)
	draw_circle(Vector2(-l * 0.36, -12), 2.2, _col_c)

func _paint_medic() -> void:
	var narrow := _pose != "side"
	_ell(Vector2(0, 1), Vector2(7, 3), Color(24.0 / 255.0, 30.0 / 255.0, 18.0 / 255.0, 0.2))
	var koveny := Color("eae6da")
	_poly([Vector2(-5.4, 0), Vector2(-4.2, -11), Vector2(4.2, -11), Vector2(5.4, 0)], koveny)
	_poly([Vector2(1, -11), Vector2(5.4, 0), Vector2(1, 0)], Color(0, 0, 0, 0.12))
	var voros := Color("c0392b")
	_rect(-2.6, -8.4, 5.2, 1.8, voros)
	_rect(-0.9, -10.1, 1.8, 5.2, voros)
	draw_circle(Vector2(0, -13.4), 3.1, Color("d8b48c"))
	_felkor(Vector2(0, -14.6), 3.2, koveny)
	_rect(-1.1, -15.6, 2.2, 1.2, voros)
	if not narrow:
		_rect(4.6, -6.4, 4.6, 4.2, Color("6a4a2c"))
		_rect(6.2, -5.4, 1.4, 2.2, voros)
		draw_line(Vector2(4.6, -6.4), Vector2(3.4, -9.6), Color("3a2a18"), 0.9)

# Torkolattűz (muzzleFlash).
func _muzzle(p: Vector2, size: float) -> void:
	_poly([p, p + Vector2(size * 1.7, -size * 0.55), p + Vector2(size * 2.4, 0),
		p + Vector2(size * 1.7, size * 0.55)], Color(1.0, 232.0 / 255.0, 150.0 / 255.0, 0.95))
	draw_circle(p + Vector2(size * 0.7, 0), size * 0.75, Color(1.0, 180.0 / 255.0, 60.0 / 255.0, 0.75))

# --- Rajzsegédek (a vászon parancsainak megfelelői) ---

# shade(): t < 0 sötétít, t > 0 világosít — ugyanaz a képlet, mint az eredetiben.
static func _shade(c: Color, t: float) -> Color:
	var k := minf(absf(t), 1.0)
	var cel := Color(0, 0, 0, c.a) if t < 0.0 else Color(1, 1, 1, c.a)
	return c.lerp(cel, k)

func _rect(x: float, y: float, w: float, h: float, c: Color) -> void:
	var r := Rect2(x, y, w, h).abs()
	draw_rect(r, c, true)

func _poly(pts: PackedVector2Array, c: Color) -> void:
	if pts.size() < 3: return
	draw_colored_polygon(pts, c)

func _ell(c: Vector2, r: Vector2, col: Color, rot: float = 0.0) -> void:
	var pts := PackedVector2Array()
	for i in range(18):
		var a := TAU * float(i) / 18.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y).rotated(rot))
	draw_colored_polygon(pts, col)

# Felső félkör (sisakkupak): arc(x, y, r, PI, TAU).
func _felkor(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(13):
		var a := PI + PI * float(i) / 12.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)

# quadraticCurveTo: a görbe pontjai (a kezdőpont nélkül) a tömb végére.
static func _quad(pts: PackedVector2Array, ctrl: Vector2, to: Vector2, n: int = 6) -> void:
	var p0: Vector2 = pts[pts.size() - 1]
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		var u := 1.0 - t
		pts.append(p0 * u * u + ctrl * 2.0 * u * t + to * t * t)

static func _tr(tr: Transform2D, pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(tr * (p as Vector2))
	return out
