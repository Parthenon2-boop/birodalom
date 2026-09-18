extends Sprite2D

# Az eredeti (index.html) rajzolási szabályai szerint.
#
#  LPC     384x256 —  6 oszlop x 4 sor, 64x64.  Sor: 0=E, 1=Ny, 2=D, 3=K
#          col 0 = álló, 1-4 = járás, 1-5 = csapás
#  Napóleon 960x256 — 15 oszlop x 4 sor.  Sor sorrend mint az LPC-nél.
#          col 0-8 = járás (9 kocka), col 9-14 = csapás (6 kocka)
#  WW2     320x256 —  5 oszlop x 4 sor.  Sor: 0=D, 1=Ny, 2=E, 3=K  <- Más!
#          col 0 = álló, 1-4 = járás
#  LO      320x256 —  5 oszlop x 4 sor.  Sor sorrend mint az LPC-nél.
#
#  Rajzolás: UX.drawImage(img, ..., -FW*0.5, -FH*0.82, FW, FH)
#  vagyis a talp a keret 82%-ánál van — középezett Sprite2D-nél ez
#  offset.y = 32 - 64*0.82 = -20.48

const FW := 64
const FH := 64
const FOOT_OFFSET := Vector2(0, 32.0 - 64.0 * 0.82)

# Irány -> sor. Index: 0=Kelet, 1=Dél, 2=Nyugat, 3=Észak
const ROWS_LPC := [3, 2, 1, 0]
const ROWS_WW2 := [3, 0, 1, 2]
# A ló lapján NINCS négy irány: két oldalnézet van (2 = balra, 3 = jobbra),
# a 0-1. sor ugyanezek vágtában. Ezért minden irányt a két oldalnézetre
# képezünk le — így sosem néz rossz felé.
const ROWS_HORSE := [3, 3, 2, 2]

# Melyik LPC lap illik a szerephez (a többi ezekre esik vissza)
const LPC_FOR := {
	"worker": "worker", "melee": "melee", "ranged": "ranged", "spear": "spear",
	"priest": "priest", "spy": "spy", "hero": "melee", "medic": "priest",
	"cav": "melee", "ram": "melee", "siege": "ranged",
}
# A napóleoni készlet három lapból áll
const NAP_FOR := {
	"ranged": "ranged", "siege": "ranged", "spear": "spear",
}
const NAVAL_ROLES := ["fisher", "warship", "galleon", "transport"]
const AIR_ROLES := ["fighter", "bomber"]

# --- MÉRETEGYSÉGESÍTÉS ---
#
# A lapok különböző méretű alakokat tartalmaznak: az LPC munkás 47, a
# napóleoni katona 55, a WW2 gyalogos 61 képpont magas — egymás mellett
# ez szemet szúr. Ezért minden lapot ugyanarra a testmagasságra nagyítunk
# vagy kicsinyítünk, és a talpát a csomópont origójába tesszük.
#
# lapkulcs -> [az alak magassága a kockán, a talp sora a kockán]
# (mindkettő mérve: az átlátszatlan képpontok a 64x64-es kockán belül)
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
	# A ló oldalnézeti kockái: a teljes magasság (a felkapott fejjel együtt)
	# 30 képpont, a patája a kocka 46. sorában van.
	"horse":          [30.0, 46.0],
}

# Minden gyalogos ekkora lesz világképpontban.
const TARGET_H := 46.0
# A ló a fejtetőig ekkora. Egy ló marmagassága kb. 1,6 m, a fejtetője 2,1 m,
# az ember 1,75 m — az ember 46 képpontjához mérve a ló 54, a marja 36.
# Ennél kisebbre véve az emberke ülne nagyobbnak, mint a hátasa.
const HORSE_H := 54.0

# A hajók hossza a gyalogos magasságához mérve. Egy szlúp nem lehet
# akkora, mint egy ember, és egy gálya sem akkora, mint egy csónak.
const SHIP_LENGTH := {
	"fisher": 1.5, "transport": 1.9, "warship": 2.4, "galleon": 2.9,
}

# A hajólapok OLDALNÉZETIEK (mint az eredeti játékban): a hajótest a kép
# alján ül, az árbocok fölfelé állnak, az orr BALRA néz. Egy ilyen képet
# NEM szabad a menetirányba forgatni — észak felé haladva a hajó az
# oldalára dőlne, az árbocai vízszintesen állnának. Ezért az eredeti
# póz-rendszerét használjuk:
#   Kelet / Nyugat → teljes oldalnézet, az orr a menetirányba tükrözve
#   Dél / Észak    → szemből, illetve hátulról: keskeny test, álló árboc
const SHIP_NARROW := 0.34
# A hajó ringatózása a vízen (radián): állva alig, menet közben jobban.
const SHIP_ROLL_IDLE := 0.028
const SHIP_ROLL_MOVE := 0.052

# --- A HAJÓK KORSZAKONKÉNT ---
#
# 0. korszak (15. sz.) — fakó, festetlen tölgy: kogge és karakk.
# 1. korszak (17. sz.) — ugyanaz a hajótest, de kifestve, fényezve.
# 2. korszak (19. sz.) — GŐZ ÉS VITORLA: fekete testű csavargőzös, a fedélzet
#                        közepén kéménnyel. A vitorla még rajta van, ahogy a
#                        század hajóin is.
# 3. korszak (20. sz.) — ACÉLHAJÓ, vitorla nélkül: szürke test, felépítmény,
#                        lövegtornyok. Ezt már nem lapról vesszük, hanem
#                        rajzoljuk (a vitorlást nem lehet géphajóvá alakítani).
const SHIP_TINT := {
	0: Color(0.86, 0.84, 0.78),
	1: Color(1.00, 1.00, 1.00),
	2: Color(0.55, 0.59, 0.66),
}
# Hova kerüljön a kémény a lapon (a kép közepéhez mért hányad, + = a tat felé).
# A lapokon LEMÉRVE: a legszélesebb hézag az árbocok között — így a kémény
# nem az árbocra csúszik, hanem a szabad fedélzetre.
const FUNNEL_X := {
	"fisher": 0.245, "transport": 0.216, "warship": 0.080, "galleon": -0.022,
}
# A rajzolt acélhajó helyi tere: a test hossza ennyi egység, a vízvonal y = 0,
# az orr BALRA néz (mint a lapokon), a felépítmény fölfelé.
const STEEL_LEN := 64.0

# A gépek hossza ugyanígy a gyalogoshoz mérve: egy vadász kb. két ember
# hosszú, a kétmotoros bombázó közel három.
const PLANE_LENGTH := {"fighter": 2.1, "bomber": 3.0}

enum Kind { LPC, NAPOLEON, WW2, HORSE, SHIP, AIR, NONE }

var _kind : int   = Kind.NONE
var _cols : int   = 6
var _rows : Array = ROWS_LPC
var _walk_frames : int = 4     # hany kockas a járás ciklus
var _walk_base   : int = 1     # a járás első oszlopa
var _atk_frames  : int = 5
var _atk_base    : int = 1
# Melyik kocka az "áll" póz. A lónál a 0. kocka ELÖLNÉZET, a járás viszont
# oldalnézet — ha megállna a 0-ra, hirtelen szembefordulna a kamerával.
var _idle_col    : int = 0
var _role : String = ""
var _age  : int    = 0
var _dir  : int    = 0
var _att  : bool   = false
var _phase: int    = -1     # a járásciklus kockája (-1 = áll vagy csap)
var _col  : int    = 0      # a most mutatott kocka oszlopa
var _row  : int    = -1     # és a sora
var _cycle: float  = 0.0    # hol tartunk a ciklusban (0..1)
var _rider_tex  : Texture2D = null   # a nyeregbe ültetett alak lapja
var _rider_cols : int = 6
var _rider_rows : Array = ROWS_LPC   # a lovas lapjának sorrendje
var _sheet_key  : String = ""        # melyik laphoz tartoznak a méretek
var _foot       : Vector2 = FOOT_OFFSET   # a talp eltolása a kockán belül
var _ship_scale : float = 1.0        # a hajókép nagyítása (a tükrözés előtt)
var _ship_phase : float = 0.0        # hogy ne egyszerre billegjen az egész flotta
# "sail" = vitorlás lapról, "steam" = vitorlás + kémény, "steel" = rajzolt acélhajó
var _ship_style : String = "sail"
var _ship_size  : Vector2 = Vector2.ZERO   # a hajólap mérete képpontban

func setup(role: String, age: int, owner_id: int) -> void:
	centered = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_role = role
	_age = age
	# A NEMZETI JEGYHEZ tudni kell, ki a gazda és melyik nemzet: a jegy
	# formája a nemzeté, a színe a félé (lásd _draw_nemzeti_jelleg).
	_owner_id = owner_id
	_nemzet = str(GameState.get_side(owner_id).get("nemzet", "hu"))
	# Az LPC/napóleoni készletből csak egy változat van, ezért az ellenséges
	# egységeket enyhe színezéssel választjuk el. (A talpgyűrű önmagában
	# tömegben nehezen olvasható.)
	if owner_id != GameState.en_id:
		# Több fél esetén oldalanként más az árnyalat, hogy tömegben is
		# el lehessen választani őket.
		self_modulate = Color.WHITE.lerp(Style.side_color(owner_id), 0.42)
	if role in NAVAL_ROLES:
		_setup_ship(role)
		return
	# A repülők a hajókhoz hasonlóan EGYETLEN képből állnak, amit a haladás
	# irányába forgatunk. (Korábban gyalogos lapra estek vissza: a repülőtér
	# olyan vadászt épített, ami katonaként nézett ki és gyalogolt.)
	if role in AIR_ROLES:
		_setup_air(role)
		return
	if role == "cav" and _try_load("res://assets/sprites/horse.png"):
		_kind = Kind.HORSE
		_sheet_key = "horse"
		_fit(_sheet_key, HORSE_H)
		_cols = 5; _rows = ROWS_HORSE
		_walk_base = 1; _walk_frames = 4
		_atk_base = 1;  _atk_frames = 4
		_idle_col = 1
		# A ló lapján CSAK a ló van — lovas nélkül. A nyeregbe a korszak
		# gyalogosának alakját ültetjük, hogy a lovas is korhű legyen:
		# 15. sz. vitéz, 17-19. sz. vonalgyalogos, 20. sz. katona.
		var side := "ally" if owner_id == GameState.en_id else "axis"
		var rp := "res://assets/sprites/lpc/melee.png"
		var rkey := "lpc/melee"
		var rcols := 6
		var rrows: Array = ROWS_LPC
		if age >= 3 and ResourceLoader.exists("res://assets/sprites/ww2/%s.png" % side):
			rp = "res://assets/sprites/ww2/%s.png" % side
			rkey = "ww2"; rcols = 5; rrows = ROWS_WW2
		elif age >= 1 and ResourceLoader.exists("res://assets/sprites/napoleon/melee.png"):
			rp = "res://assets/sprites/napoleon/melee.png"
			rkey = "napoleon/melee"; rcols = 15
		if ResourceLoader.exists(rp):
			_rider_tex = load(rp)
			_rider_cols = rcols
			_rider_rows = rrows
			_fit_rider(rkey)
		_apply_frame(0, 0)
		_apply_era_tint()
		return
	# KORSZAK -> LAPKÉSZLET.
	#   0 = 15. század   LPC vitézek
	#   1 = 17. század   napóleoni vonalgyalogság
	#   2 = 19. század   UGYANAZ a vonalgyalogság, tompább egyenruhában —
	#                    a 19. század nem a világháborúk kora, rohamsisakos
	#                    katona ott még nem járt
	#   3 = 20. század   WW2 lapok
	match age:
		0:    _setup_lpc(role)
		1, 2: _setup_napoleon(role)
		_:    _setup_ww2(owner_id)
	_apply_era_tint()
	if _kind == Kind.NONE:
		_setup_lpc(role)          # a napóleoni/ww2 lap hianyaban az LPC az alap
	if _kind == Kind.NONE:
		_make_placeholder(role, owner_id)

# A 17. és a 19. század ugyanarról a lapról dolgozik, ezért a 19. századi
# alakok hűvösebb, sötétebb egyenruhát kapnak: a napóleoni élénk kék-fehér
# helyett a század második felének tompább, sötétkék-szürke viselete.
const ERA_TINT := {
	2: Color(0.74, 0.79, 0.90),
}

func _apply_era_tint() -> void:
	if not ERA_TINT.has(_age): return
	var t: Color = ERA_TINT[_age]
	self_modulate = Color(self_modulate.r * t.r, self_modulate.g * t.g,
		self_modulate.b * t.b, self_modulate.a)

func _try_load(path: String) -> bool:
	if not ResourceLoader.exists(path): return false
	texture = load(path)
	return texture != null

# A lap alakját közös testmagasságra igazítja, és a talpát a csomópont
# origójába teszi. Az `offset` a nagyítás ELŐTT hat, ezért a kockán belüli
# képpontokban számolunk — a rajzolt fegyver és a lovas így vele együtt
# nagyítódik, nem csúszik el.
func _fit(sheet_key: String, target: float) -> void:
	var m: Array = SHEET_METRICS.get(sheet_key, [TARGET_H, 61.0])
	var s: float = target / maxf(float(m[0]), 1.0)
	scale = Vector2(s, s)
	_foot = Vector2(0.0, 32.0 - float(m[1]))
	offset = _foot

func figure_height() -> float:
	var m: Array = SHEET_METRICS.get(_sheet_key, [TARGET_H, 61.0])
	return float(m[0]) * scale.y

func _setup_lpc(role: String) -> void:
	var sheet: String = LPC_FOR.get(role, "melee")
	if not _try_load("res://assets/sprites/lpc/%s.png" % sheet): return
	_kind = Kind.LPC
	_sheet_key = "lpc/" + sheet
	_fit(_sheet_key, TARGET_H)
	# A hat kockából 0 = álló, 1-3 = járás, 4-5 = csapás. A járásba korábban
	# a 4. kocka is beleszámított, ott viszont a kar FÖL van emelve — a
	# kézbe rajzolt fegyver ilyenkor leszakadt az alakról.
	_cols = 6; _rows = ROWS_LPC
	_walk_base = 1; _walk_frames = 3
	_atk_base  = 4; _atk_frames  = 2
	_apply_frame(0, 0)

func _setup_napoleon(role: String) -> void:
	var sheet: String = NAP_FOR.get(role, "melee")
	if not _try_load("res://assets/sprites/napoleon/%s.png" % sheet): return
	_kind = Kind.NAPOLEON
	_sheet_key = "napoleon/" + sheet
	_fit(_sheet_key, TARGET_H)
	_cols = 15; _rows = ROWS_LPC
	_walk_base = 0; _walk_frames = 9
	_atk_base  = 9; _atk_frames  = 6
	_apply_frame(0, 0)

func _setup_ww2(owner_id: int) -> void:
	var side := "ally" if owner_id == GameState.en_id else "axis"
	if not _try_load("res://assets/sprites/ww2/%s.png" % side): return
	_kind = Kind.WW2
	_sheet_key = "ww2"
	_fit(_sheet_key, TARGET_H)
	_cols = 5; _rows = ROWS_WW2
	_walk_base = 1; _walk_frames = 4
	_atk_base  = 1; _atk_frames  = 4
	_apply_frame(0, 0)

# A repülő is egyetlen kép: a rajz orra FELFELE néz, ezért a forgatásnál
# ugyanaz a +90 fok jár neki, mint a hajóknak.
func _setup_air(role: String) -> void:
	if not _try_load("res://assets/sprites/air/%s.png" % role):
		_make_placeholder(role, 0)
		return
	_kind = Kind.AIR
	region_enabled = false
	offset = Vector2.ZERO
	_foot = Vector2.ZERO
	var img := texture.get_size()
	var want: float = TARGET_H * float(PLANE_LENGTH.get(role, 2.0))
	var s: float = want / maxf(maxf(img.x, img.y), 1.0)
	scale = Vector2(s, s)

# A hajók egyetlen, OLDALNÉZETI képből állnak, nem lapból: a képet nem
# forgatjuk, hanem tükrözzük és keskenyítjük (lásd SHIP_NARROW).
# A 20. századi acélhajónak nincs lapja — azt rajzoljuk.
func _setup_ship(role: String) -> void:
	_kind = Kind.SHIP
	region_enabled = false
	_foot = Vector2.ZERO
	_ship_phase = randf() * TAU
	# A hajókat is a gyalogoshoz mérjük: a hosszukat a hajótípus adja meg
	# (csónak < szlúp < gálya).
	var want: float = TARGET_H * float(SHIP_LENGTH.get(role, 2.0))
	if _age >= 3:
		_ship_style = "steel"
		texture = null
		offset = Vector2.ZERO
		_ship_size = Vector2(STEEL_LEN, STEEL_LEN)
		_ship_scale = want / STEEL_LEN
		scale = Vector2(_ship_scale, _ship_scale)
		_pose_ship(0.0, false)
		queue_redraw()
		return
	if not _try_load("res://assets/sprites/ship/%s.png" % role):
		_make_placeholder(role, 0)
		return
	_ship_style = "steam" if _age == 2 else "sail"
	# A HOSSZ a kép szélessége — korábban a képmagasság (az árbocok!)
	# döntött, ezért a nagy vitorlájú halászbárka rövidebb lett a kelleténél.
	var img := texture.get_size()
	_ship_size = img
	_ship_scale = want / maxf(img.x, 1.0)
	scale = Vector2(_ship_scale, _ship_scale)
	# A vízvonal a kép ALJA: a hajótest a csomópont köré üljön, ne lógjon
	# a fele a víz alá. (A képen a test alul van, fölötte az árbocok.)
	offset = Vector2(0.0, -img.y * 0.5)
	_apply_ship_tint()
	_pose_ship(0.0, false)
	queue_redraw()

# A korszak színe a hajón: fakó fa → festett fa → fekete gőzös.
func _apply_ship_tint() -> void:
	if not SHIP_TINT.has(_age): return
	var t: Color = SHIP_TINT[_age]
	self_modulate = Color(self_modulate.r * t.r, self_modulate.g * t.g,
		self_modulate.b * t.b, self_modulate.a)

# Önellenőrzéshez: melyik korszak hajóját állítottuk be, és rajzolt-e.
func ship_style() -> String:
	return _ship_style if _kind == Kind.SHIP else ""

func is_drawn_ship() -> bool:
	return _kind == Kind.SHIP and _ship_style == "steel"

func _apply_frame(col: int, row: int) -> void:
	region_enabled = true
	region_rect = Rect2(col * FW, row * FH, FW, FH)
	offset = _foot

func update_anim(face: float, walk: float, moving: bool, fired: bool) -> void:
	if _kind == Kind.SHIP:
		_pose_ship(face, moving)
		return
	if texture == null: return
	if _kind == Kind.AIR:
		# A repülőgép FELÜLNÉZETI képe orral fölfelé néz, ezért +90 fok az
		# elfordítás. (A hajóké oldalnézeti, azt nem forgatjuk.)
		rotation = face + PI * 0.5
		return
	if _kind == Kind.NONE: return
	var d := _dir_index(face)
	var row: int = _rows[d]
	var col := _frame_col(walk, moving, fired)
	# A kivágás beállítása újrarajzolást vált ki, ezért CSAK akkor nyúlunk
	# hozzá, ha tényleg más kockára váltottunk. Sok egységnél ez sokat
	# számít: enélkül minden egység minden fizikai lépésben újrarajzolódna.
	if col != _col or row != _row:
		_row = row
		region_rect = Rect2(col * FW, row * FH, FW, FH)
	# A fegyver a karral együtt mozog, ezért MINDEN kockaváltáskor újra kell
	# rajzolni — a csapás kockái is cserélődnek, nem csak a járáséi.
	if d != _dir or fired != _att or col != _col:
		_dir = d
		_att = fired
		_col = col
		queue_redraw()

# A hajó beállítása a menetirányhoz. Négy póz, ahogy az eredeti játékban:
# oldalnézet jobbra, oldalnézet balra, szemből (orr felénk) és hátulról.
# A képen az orr BALRA néz, ezért a keletnek tartó hajót tükrözzük.
func _pose_ship(face: float, moving: bool) -> void:
	var d := _dir_index(face)      # 0 = Kelet, 1 = Dél, 2 = Nyugat, 3 = Észak
	var sx := _ship_scale
	match d:
		0: sx = -_ship_scale                      # Kelet: orr jobbra
		2: sx =  _ship_scale                      # Nyugat: ahogy a lapon van
		1: sx =  _ship_scale * SHIP_NARROW        # Dél: orr felénk
		_: sx = -_ship_scale * SHIP_NARROW        # Észak: a tat felénk
	scale = Vector2(sx, _ship_scale)
	# Ringatózás a hullámokon. A test alja (a vízvonal) a csomópont
	# origójában van, tehát a hajó a vízvonala körül billeg.
	var amp := SHIP_ROLL_MOVE if moving else SHIP_ROLL_IDLE
	var spd := 2.6 if moving else 1.1
	rotation = sin(_ship_phase + float(Time.get_ticks_msec()) * 0.001 * spd) * amp
	_dir = d

func _dir_index(face: float) -> int:
	var deg := fmod(rad_to_deg(face) + 360.0, 360.0)
	if   deg > 315.0 or deg <= 45.0:  return 0  # Kelet
	elif deg <= 135.0:                return 1  # Dél
	elif deg <= 225.0:                return 2  # Nyugat
	else:                             return 3  # Észak

func _frame_col(walk: float, moving: bool, fired: bool) -> int:
	if fired:
		# az eredeti a rendszeridőből pergeti a csapást
		_phase = -1
		var k := int(Time.get_ticks_msec() / 80.0) % _atk_frames
		# Hol tartunk a csapásban (0 = lendület, 1 = a vágás vége). Ebből
		# jön a fegyver szöge, hogy a KOCKÁVAL együtt mozogjon.
		_cycle = (float(k) + 0.5) / float(maxi(_atk_frames, 1))
		return _atk_base + k
	if moving:
		_phase = int(walk * 2.5) % _walk_frames
		_cycle = float(_phase) / float(maxi(_walk_frames, 1))
		return _walk_base + _phase
	_phase = -1
	_cycle = 0.0
	return _idle_col

# ---------------------------------------------------------------------
#  FEGYVEREK
#
#  Az LPC és a napóleoni lapokon a katonák ÜRES KÉZZEL állnak — a
#  készletben nincs kirajzolt fegyver (az íjásznak is csak a hátán lóg
#  az íj). Ezért a fegyvert magunk rajzoljuk a sprite fölé. A WW2 lapon
#  már van puska, oda nem kell.
# ---------------------------------------------------------------------

const WEAPON_FOR := {
	"melee": "sword", "hero": "sword", "spy": "dagger", "cav": "sabre",
	"spear": "spear", "ranged": "bow", "priest": "staff", "medic": "staff",
	"worker": "axe", "fisher": "axe", "siege": "", "ram": "",
}

const STEEL      := Color(0.78, 0.80, 0.85)
const STEEL_DARK := Color(0.42, 0.44, 0.50)
const WOOD       := Color(0.45, 0.31, 0.17)
const WOOD_DARK  := Color(0.28, 0.19, 0.10)
const GOLD_TRIM  := Color(0.82, 0.68, 0.24)

# A kéz helye a 64x64-es kockán belül, a kocka KÖZEPÉHEZ képest, irányonként
# [Kelet, Dél, Nyugat, Észak]. A lapokon lemérve: az LPC vitéznél a kesztyű
# a 40. sorban, a napóleoni katonánál a 47.-ben van, és oldalnézetben a kar
# közelebb esik a testhez. A textúrát a FOOT_OFFSET tolja el, a rajz-
# parancsainkat viszont nem — ezért azt itt hozzáadjuk.
# Csak a TÁVOLSÁG a törzs középvonalától; az oldalt a SWING_SIDE adja.
const HAND_LPC := [
	Vector2(9.0, 9.0), Vector2(10.0, 9.0), Vector2(9.0, 9.0), Vector2(8.0, 8.0),
]
const HAND_NAP := [
	Vector2(9.0, 14.0), Vector2(11.0, 14.0), Vector2(9.0, 14.0), Vector2(8.0, 13.0),
]

# MELYIK KÉZBEN van a szerszám. Ez nem választás kérdése: a lapon a csapás
# animációja adott irányba lendíti a kart, és a rajzolt fegyvernek ugyanoda
# kell kerülnie. Mind a négy lapkészletet lemérve (az álló és a csapás
# kocka szélső oszlopait összevetve) a SOR dönti el, nem az irány:
#   sor 0 (Észak, háttal) = jobbra   sor 1 (Nyugat) = balra
#   sor 2 (Dél, szemből)  = jobbra   sor 3 (Kelet)  = jobbra
# Korábban az északi nézetnél balra raktuk a szerszámot, miközben az alak
# a jobb karjával dolgozott.
const SWING_SIDE := [1.0, -1.0, 1.0, 1.0]

# A szerszám oldala a jelenlegi irányban (+1 = jobbra, -1 = balra).
func weapon_side() -> float:
	return SWING_SIDE[clampi(int(_rows[clampi(_dir, 0, 3)]), 0, 3)]

# A lovas billenése a ló járásciklusában. Kockánként [előre, le].
const WALK_SWING := [
	Vector2(0.0, 0.0), Vector2(1.6, -1.0), Vector2(-1.2, 0.5),
]

# --- A KÉZ HELYE KOCKÁNKÉNT ---
#
# A szerszám nem egy „átlagos” helyen áll a törzs mellett: a lapon minden
# kockában máshol van a kar, és a fegyvernek oda kell kerülnie. Ezért a
# lapról MEGMÉRJÜK, hol ér véget a kar a szerszám oldalán — kockánként,
# első használatkor, és az eredményt minden egység közösen használja.
#
# A mérés csak a kar magasságában futó sávot nézi (a testmagasság 20-58%-a
# a talptól), és kívülről befelé keres, tehát kockánként pár száz képpont.
static var _hand_cache: Dictionary = {}
static var _img_cache: Dictionary = {}

static func _sheet_image(key: String, tex: Texture2D) -> Image:
	if _img_cache.has(key): return _img_cache[key]
	var im: Image = tex.get_image() if tex != null else null
	_img_cache[key] = im
	return im

# A KÉZ helye a kockán belül, a kocka közepéhez képest. Nem a sziluett
# szélét keressük (az a váll, a köpeny vagy a láb is lehet), hanem magát a
# csupasz kezet: a lapokon a kéz BŐRSZÍNŰ, és a törzs középvonalától
# oldalt esik. Így a szerszám kockáról kockára pontosan a markolatban ül.
func _hand_at(row: int, col: int, side: float) -> Vector2:
	var k := "%s|%d|%d|%d" % [_sheet_key, row, col, 1 if side > 0.0 else 0]
	if _hand_cache.has(k): return _hand_cache[k]
	var res := _measure_hand(row, col, side)
	_hand_cache[k] = res
	return res

# Bőrszín: narancsos árnyalat, közepes telítettséggel és világosan. A haj
# sötétebb, az ing telítetlen, a nadrág kék — egyik sem esik bele.
static func _is_skin(c: Color) -> bool:
	if c.a < 0.5: return false
	var h := c.h * 360.0
	return h >= 10.0 and h <= 45.0 and c.s >= 0.25 and c.s <= 0.72 \
		and c.v >= 0.55

func _measure_hand(row: int, col: int, side: float) -> Vector2:
	var table: Array = HAND_NAP if _kind == Kind.NAPOLEON else HAND_LPC
	var fb: Vector2 = table[clampi(_dir, 0, 3)]
	var fallback := Vector2(absf(fb.x) * side, fb.y)
	var img := _sheet_image(_sheet_key, texture)
	if img == null: return fallback
	var m: Array = SHEET_METRICS.get(_sheet_key, [TARGET_H, 61.0])
	var fig: float = float(m[0])
	var foot: float = float(m[1])
	# A fej alatt kezdünk (különben az arc bőre jönne ki), és a térd fölött
	# hagyjuk abba.
	var top := clampi(int(foot - fig * 0.62), 0, FH - 1)
	var bot := clampi(int(foot - fig * 0.12), 0, FH - 1)
	var ox := col * FW
	var oy := row * FH
	if ox + FW > img.get_width() or oy + FH > img.get_height(): return fallback
	# A fej magasságában az ARC is bőrszínű, ezért ott csak a törzstől jóval
	# távolabbi képpont lehet kéz; lejjebb elég a törzs sávját kihagyni.
	var head_bot := foot - fig * 0.50
	var bx := -999
	var by := 0
	for y in range(top, bot + 1):
		var min_dx := 10 if float(y) < head_bot else 5
		for x in range(FW):
			if absi(x - 32) < min_dx: continue
			if not _is_skin(img.get_pixel(ox + x, oy + y)): continue
			if side > 0.0:
				if x > bx:
					bx = x
					by = y
			else:
				if bx == -999 or x < bx:
					bx = x
					by = y
	if bx == -999:
		# Nincs csupasz kéz a lapon (kesztyű, egyenruha): a sziluett szélét
		# vesszük, a magasságot a laphoz mért táblázatból.
		return Vector2(_silhouette_x(img, row, col, side, top, bot,
			fallback.x), fallback.y)
	return Vector2(float(bx) - 32.0, float(by) - 32.0)

# --- A FEJTETŐ helye a kockán belül ---
#
# A nemzeti jegy (sisak, kalpag, csákó) a fejre kerül, tehát pontosan
# tudnunk kell, hol ér véget felül az alak — és ez kockáról kockára
# változik, mert a járásciklusban bólint a fej. A lapról mérjük meg: a
# legfelső nem átlátszó képpont a fejtető, a hozzá tartozó sáv közepe
# pedig a fej középvonala. Kockánként egyszer, utána mindenki ugyanazt
# használja.
# A visszaadott érték: x, y = a fej KÖZEPE a kocka közepéhez képest,
# z = a fej sugara képpontban. A jegy mérete ebből jön, így a lapok
# méretkülönbsége nem számít: a sisak mindig a fejre való.
static var _head_cache: Dictionary = {}

func _head_at(row: int, col: int) -> Vector3:
	var k := "%s|%d|%d" % [_sheet_key, row, col]
	if _head_cache.has(k): return _head_cache[k]
	var res := _measure_head(row, col)
	_head_cache[k] = res
	return res

func _measure_head(row: int, col: int) -> Vector3:
	var m: Array = SHEET_METRICS.get(_sheet_key, [TARGET_H, 61.0])
	var fig: float = float(m[0])
	var foot: float = float(m[1])
	var fallback := Vector3(0.0, foot - fig * 0.90 - 32.0, fig * 0.11)
	var img := _sheet_image(_sheet_key, texture)
	if img == null: return fallback
	var ox := col * FW
	var oy := row * FH
	if ox + FW > img.get_width() or oy + FH > img.get_height(): return fallback
	# Felülről lefelé keressük az első nem átlátszó sort: az a fejtető. A
	# fegyver és a köpeny lejjebb kezdődik, tehát ami legfelül van, az a fej.
	var also := clampi(int(foot - fig * 0.55), 0, FH - 1)
	var teto := -1
	var kozep_x := 0.0
	for y in range(0, also):
		var bal := 999
		var jobb := -999
		for x in range(FW):
			if img.get_pixel(ox + x, oy + y).a < 0.5: continue
			bal = mini(bal, x)
			jobb = maxi(jobb, x)
		if jobb < 0: continue
		teto = y
		kozep_x = (float(bal + jobb) * 0.5) - 32.0
		break
	if teto < 0: return fallback
	# A fej SZÉLESSÉGE: a fejtető alatti néhány sor közül a legszélesebb —
	# a koponya legszélesebb pontja. Ebből lesz a sugár.
	var szeles := 0
	for y in range(teto, mini(teto + 8, also)):
		var b2 := 999
		var j2 := -999
		for x in range(FW):
			if img.get_pixel(ox + x, oy + y).a < 0.5: continue
			b2 = mini(b2, x)
			j2 = maxi(j2, x)
		if j2 >= 0: szeles = maxi(szeles, j2 - b2 + 1)
	var r := maxf(float(szeles) * 0.5, fig * 0.07)
	return Vector3(kozep_x, float(teto) - 32.0 + r, r)

func _silhouette_x(img: Image, row: int, col: int, side: float,
		top: int, bot: int, fallback: float) -> float:
	var ox := col * FW
	var oy := row * FH
	var bx := -999
	for y in range(top, bot + 1):
		var found := -1
		if side > 0.0:
			for x in range(FW - 1, -1, -1):
				if img.get_pixel(ox + x, oy + y).a > 0.4:
					found = x
					break
			if found > bx: bx = found
		else:
			for x in range(FW):
				if img.get_pixel(ox + x, oy + y).a > 0.4:
					found = x
					break
			if found >= 0 and (bx == -999 or found < bx): bx = found
	if bx == -999: return fallback
	return float(bx) - 32.0 - 1.5 * side

# Nyugalmi tartás (radián, pozitív = lefelé). Csapáskor felülíródik.
# A lándzsa és a bot majdnem függőleges, hogy ne feküdjön rá a törzsre.
const IDLE_TILT := {
	"sword": 0.72, "dagger": 0.85, "sabre": 0.62, "axe": 0.85,
	"spear": -1.32, "bow": 0.0, "musket": -0.30, "staff": -1.45,
}

# Amivel csapnak — ezeknél a csapás íve a kockához van kötve. A muskéta és
# az íj nem lendül: azok előre néznek és visszarúgnak.
const SWING_WEAPONS := ["sword", "dagger", "sabre", "axe", "spear"]
const ATK_ANG_START := -1.20     # hátralendítve, a fej fölött
const ATK_ANG_END   :=  0.80     # a vágás vége, előre-le

# AMELYIK LAPON MÁR VAN FEGYVER, oda nem rajzolunk másikat.
#
# A készletek vegyesek: az íjász lapján ott a saját íja, a napóleoni
# lövészén a szablya, a világháborús katonán a puska — ezeken eddig egy
# MÁSODIK, rajzolt fegyver is megjelent. A vitéz, a lándzsás, a munkás, a
# pap és a kém keze viszont üres a lapon, nekik marad a rajzolt szerszám.
# (Lemérve: a lapok D-sorának kockáit végignézve.)
const SHEET_HAS_WEAPON := ["lpc/ranged", "napoleon/ranged", "ww2"]

func sheet_has_weapon() -> bool:
	return _sheet_key in SHEET_HAS_WEAPON

func _draw() -> void:
	if _kind == Kind.HORSE:
		_draw_rider()
		_draw_rider_jelleg()
		return
	if _kind == Kind.SHIP:
		match _ship_style:
			"steam": _draw_funnel()
			"steel": _draw_steel_ship()
		return
	if _kind == Kind.NONE: return
	# A NEMZETI JEGY a fejre kerül — akkor is, ha a laphoz fegyver is
	# tartozik, tehát a fegyverrajz kihagyása előtt.
	_draw_gyalog_jelleg()
	if sheet_has_weapon(): return
	var kind: String = WEAPON_FOR.get(_role, "")
	if kind == "": return
	# Az íjászé a napóleoni korban már muskéta.
	if kind == "bow" and _age >= 1: kind = "musket"

	# A szerszám abba a kézbe kerül, amelyikkel az alak ténylegesen dolgozik,
	# és PONTOSAN oda, ahol a kar a mostani kockán véget ér — így a kapa, a
	# balta és a kard együtt mozog a kézzel, nem lóg külön életet.
	var s := weapon_side()
	var row: int = _rows[clampi(_dir, 0, 3)]
	# A markolat pontosan a kimért kézben ül — kockáról kockára.
	var hand := _hand_at(row, _col, s) + _foot
	# Nyugalomban a fegyvert nem vízszintesen tartja a kéz: a kard és a
	# bárd lefelé lóg, a lándzsát és a botot majdnem függőlegesen fogja.
	var ang: float = IDLE_TILT.get(kind, 0.0)
	if _att and kind in SWING_WEAPONS:
		# A csapás íve a KOCKÁHOZ kötve: hátulról indul, előre-le vág.
		ang = lerpf(ATK_ANG_START, ATK_ANG_END, _cycle)
	var d := Vector2(s, 0.0).rotated(ang * s)
	var n := Vector2(-d.y, d.x)        # merőleges
	# Háttal állva a szerszám a test túloldalán van, ezért halványabb —
	# csapás közben viszont kilendül a kar, ott teljes fényben látszik.
	var fade := 1.0
	if _dir == 3 and not _att: fade = 0.6

	match kind:
		"sword":  _draw_sword(hand, d, n, 17.0, fade)
		"dagger": _draw_sword(hand, d, n, 10.0, fade)
		"sabre":  _draw_sabre(hand, d, n, fade)
		"spear":  _draw_spear(hand, d, n, fade)
		"bow":    _draw_bow(hand, d, n, fade)
		"musket": _draw_musket(hand, d, n, fade)
		"staff":  _draw_staff(hand, d, n, fade)
		"axe":    _draw_axe(hand, d, n, fade)

# A lovas: az alak felsőteste (fej + törzs + kar) a nyeregben, plusz a
# szablya. A lába nem látszik, az a ló oldalán lógna.
#
# A lovas NEM a ló nagyításával készül, hanem ugyanakkora világméretben,
# mint egy gyalogos — különben az emberke nagyobb lenne, mint a ló alatta.
# A kivágást a lap méreteiből számoljuk: a fej teteje a talp fölött a
# testmagassággal, a csípő a testmagasság 45%-ánál van.
const RIDER_HIP_FRAC := 0.55     # fejtetőtől a csípőig ennyi a testmagasság
# A lovas TELJES alakja látszik — törzs és láb is —, a lába a ló oldalán
# lóg le, ahogy a kengyelben ülő emberé. Kicsivel kisebb a gyalogosnál:
# a nyeregben ülő ember össze van húzva, és így nem nyomja agyon a lovat.
const RIDER_H := 42.0
const RIDER_SEAT_Y   := 26.0     # a ló hátának vonala a LÓ kockáján belül
# A nyereg nem a ló közepén, hanem a marja mögött van — a kocka közepétől
# ennyivel a FEJ felé. (A ló teste a kockán x 19..44, a feje 39..50.)
const RIDER_SADDLE_DX := 2.5

var _rider_src_top : float = 13.0
var _rider_src_h   : float = 27.5
var _rider_scale   : float = 0.5

# A lovas kivágásának és nagyításának kiszámítása a lovas lapjából.
var _rider_armed: bool = false

func _fit_rider(rider_key: String) -> void:
	# Ha a lovas lapján már van fegyver (világháborús katona puskával),
	# nem rajzolunk mellé szablyát.
	_rider_armed = rider_key in SHEET_HAS_WEAPON
	var rm: Array = SHEET_METRICS.get(rider_key, [50.0, 63.0])
	var fig: float = float(rm[0])
	var foot: float = float(rm[1])
	_rider_src_top = foot - fig                     # a fej teteje
	_rider_src_h   = fig                            # a TELJES alak, lábbal
	# A rajzolás a ló már felnagyított terében történik, ezért osztunk a
	# ló nagyításával — így a lovas mérete független a ló méretétől.
	_rider_scale = (RIDER_H / fig) / maxf(scale.x, 0.001)

# Önellenőrzéshez: a ló és a lovas tényleges magassága világképpontban.
func horse_world_h() -> float:
	var m: Array = SHEET_METRICS.get("horse", [30.0, 46.0])
	return float(m[0]) * scale.x

func rider_world_h() -> float:
	return _rider_src_h * _rider_scale * scale.x

# A nyereg fölött látszó rész (fej + törzs) — ehhez mérjük a lovat.
func rider_torso_h() -> float:
	return rider_world_h() * RIDER_HIP_FRAC

func _draw_rider() -> void:
	if _rider_tex == null: return
	# A ló csak oldalra néz, a lovas viszont a tényleges irányba fordul.
	var s := -1.0 if _rows[clampi(_dir, 0, 3)] == 2 else 1.0
	var row: int = _rider_rows[clampi(_dir, 0, 3)]
	var col := mini(_rider_cols - 1, 4) if _att else 0
	var src := Rect2(col * FW, row * FH + _rider_src_top, FW, _rider_src_h)
	var bob := 0.0
	if _phase >= 0 and _phase < WALK_SWING.size():
		bob = WALK_SWING[_phase].y * 0.6           # a ló járásával billen
	# A nyereg helye a sprite helyi terében (a ló talpa a 0-ban van).
	var seat := RIDER_SEAT_Y - 32.0 + _foot.y + bob
	var w := FW * _rider_scale
	var h := _rider_src_h * _rider_scale
	# A CSÍPŐ kerül a nyeregbe, a láb onnan lóg le a ló oldalán.
	var dst := Rect2(Vector2(-w * 0.5 + RIDER_SADDLE_DX * s,
		seat - h * RIDER_HIP_FRAC), Vector2(w, h))
	draw_texture_rect_region(_rider_tex, dst, src)
	if _rider_armed: return
	# Szablya a kézben, a nyereg fölött. A fegyverrajzoló képpontban dolgozik,
	# ezért a ló nagyítását ideiglenesen visszaszorítjuk a gyalogosokéra —
	# különben a szablya is 1,8-szeres lenne.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_rider_scale, _rider_scale))
	# Nyugalomban a szablya FÖLFELÉ áll (így nem fekszik rá a ló nyakára),
	# csapáskor előre-le vág.
	var hand := Vector2(s * (RIDER_SADDLE_DX / _rider_scale + 5.0),
		(seat - h * RIDER_HIP_FRAC * 0.62) / _rider_scale)
	var ang := -1.25
	if _att: ang = -0.5 + 0.4 * sin(Time.get_ticks_msec() / 90.0)
	var d := Vector2(s, 0.0).rotated(ang * s)
	var n := Vector2(-d.y, d.x)
	_draw_sabre(hand, d, n, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# --- NEMZETI JELLEG  (index.html 15/D) ---
#
# Eddig a nemzetek csak SZÍNBEN különböztek: ránézésre minden sereg
# ugyanúgy nézett ki. Ez a réteg a KÖRVONALAT bontja meg — nem új
# egységfajtákat vezet be (azzal a játékmenet is változna), hanem ráfest
# egy nemzeti jegyet a meglévő katonára: sisakforma, tollforgó, kalpag,
# a lengyel huszár szárnya.
#
# Miért így? Mert a sziluett az, amit a játékos a csata zűrzavarában
# valóban lát. A színt elnyeli az éjszaka, a por és a köd; egy kalpag
# vagy egy szárnypár viszont messziről is felismerhető.
#
# A jegy a FEJ FÖLÉ kerül (a fejtetőt kockánként mérjük), és kizárólag
# látvány: a szimulációt nem érinti.
const JELLEG_SZEREPEK := ["melee", "ranged", "spear", "cav", "hero"]

const NEMZETI_JELLEG := {
	"hu": ["kalpag", "kalpag", "huszarcsako", "sisakM"],      # huszárhagyomány
	"pl": ["szarny", "szarny", "rogatywka", "sisakM"],        # szárnyas huszár
	"gb": ["csobor", "tricorn", "medvebor", "brodie"],        # vöröskabátos
	"es": ["morion", "morion", "csako", "oldalsapka"],        # konkvisztádor
	"fr": ["csobor", "tricorn", "csako", "adrian"],           # muskétás
	"de": ["csobor", "szeleskarima", "tuskes", "stahl"],      # porosz tüskés sisak
	"at": ["csobor", "szeleskarima", "csako", "sisakM"],
	"ru": ["prilbica", "szeleskarima", "csako", "budjonnij"],
	"ns": ["kendo", "kendo", "kendo", "kendo"],               # kalózok
	"bb": ["kendo", "kendo", "kendo", "kendo"],
	"sb": ["tricorn", "tricorn", "tricorn", "tricorn"],
}

const ACEL_J := Color(0.55, 0.58, 0.63)
const ACEL_S := Color(0.35, 0.39, 0.44)

var _owner_id: int = 0
var _nemzet: String = "hu"

func _jelleg() -> String:
	var t: Array = NEMZETI_JELLEG.get(_nemzet, [])
	if t.is_empty(): return ""
	return str(t[clampi(_age, 0, 3)])

# A jegy kirajzolása a fej fölé. A `col` a csapatszín, az `acc` a kiemelés —
# ezekkel marad felismerhető, ki kicsoda, miközben a FORMA a nemzeté.
func _draw_nemzeti_jelleg(fej: Vector2, k: float, hatulrol: bool,
		oldalt: bool) -> void:
	if not (_role in JELLEG_SZEREPEK): return
	var jegy := _jelleg()
	if jegy == "": return
	var col := Style.side_color(_owner_id)
	var acc := Style.side_accent(_owner_id)
	# Az origó a FEJ KÖZEPE — az eredeti rajzok is ehhez a ponthoz mérnek.
	var o := fej
	match jegy:
		"kalpag":       _j_kalpag(o, k, col, acc)
		"szarny":       _j_szarny(o, k, hatulrol, oldalt)
		"morion":       _j_morion(o, k, acc)
		"csobor":       _j_csobor(o, k, acc, hatulrol)
		"tricorn":      _j_tricorn(o, k, acc)
		"csako":        _j_csako(o, k, col, acc, false)
		"huszarcsako":  _j_csako(o, k, col, acc, true)
		"rogatywka":    _j_rogatywka(o, k, col)
		"oldalsapka":   _j_oldalsapka(o, k, col, acc)
		"medvebor":     _j_medvebor(o, k)
		"szeleskarima": _j_szeleskarima(o, k, acc)
		"tuskes":       _j_tuskes(o, k)
		"prilbica":     _j_prilbica(o, k)
		"budjonnij":    _j_budjonnij(o, k, col, acc)
		"brodie":       _j_brodie(o, k)
		"adrian":       _j_adrian(o, k)
		"stahl":        _j_stahl(o, k)
		"sisakM":       _j_sisak_modern(o, k)
		"kendo":        _j_kendo(o, k, col)

# A gyalogos jegye: a mért fejtető fölé, a kocka szerinti bólintással.
func _draw_gyalog_jelleg() -> void:
	if not (_role in JELLEG_SZEREPEK): return
	if _jelleg() == "": return
	var row: int = _rows[clampi(_dir, 0, 3)]
	var h := _head_at(row, _col)
	var fej := Vector2(h.x, h.y) + _foot
	# Az eredeti rajzok egy 4,3 képpont sugarú fejhez készültek: ebből jön
	# a méretarány, bármekkora is a lap.
	_draw_nemzeti_jelleg(fej, h.z / 4.9, _dir == 3, _dir == 0 or _dir == 2)

# A LOVAS jegye: a nyeregben ülő alak feje a rajzolt kép tetején van.
func _draw_rider_jelleg() -> void:
	if _rider_tex == null or not (_role in JELLEG_SZEREPEK): return
	if _jelleg() == "": return
	var s := -1.0 if _rows[clampi(_dir, 0, 3)] == 2 else 1.0
	var bob := 0.0
	if _phase >= 0 and _phase < WALK_SWING.size():
		bob = WALK_SWING[_phase].y * 0.6
	var seat := RIDER_SEAT_Y - 32.0 + _foot.y + bob
	var h := _rider_src_h * _rider_scale
	# A lovas feje a rajzolt kép tetején ül; a fej sugara a kép magasságának
	# nagyjából a tizede.
	var r := h * 0.085
	var fej := Vector2(RIDER_SADDLE_DX * s,
		seat - h * RIDER_HIP_FRAC + h * 0.06 + r)
	_draw_nemzeti_jelleg(fej, r / 4.9, _dir == 3, _dir == 0 or _dir == 2)

# Segédek: a HTML ív- és ellipszisrajzait apró sokszögekkel adjuk vissza.
func _ellipszis(c: Vector2, r: Vector2, szin: Color, szog: float = 0.0) -> void:
	var pts := PackedVector2Array()
	for i in range(16):
		var a := TAU * float(i) / 16.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y).rotated(szog))
	draw_colored_polygon(pts, szin)

# Felső félkör (sisakkupak).
func _kupak(c: Vector2, r: Vector2, szin: Color) -> void:
	var pts := PackedVector2Array()
	pts.append(c + Vector2(-r.x, 0))
	for i in range(13):
		var a := PI + PI * float(i) / 12.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	pts.append(c + Vector2(r.x, 0))
	draw_colored_polygon(pts, szin)

# MAGYAR KALPAG: prémes kalpag csapatszínű posztóval és tollforgóval.
func _j_kalpag(o: Vector2, k: float, col: Color, acc: Color) -> void:
	_ellipszis(o + Vector2(0, -3.2 * k), Vector2(4.4, 3.4) * k,
		Color(0.23, 0.16, 0.12))
	_ellipszis(o + Vector2(0, -5.2 * k), Vector2(3.2, 2.2) * k, col.darkened(0.15))
	draw_line(o + Vector2(1.4, -5.6) * k, o + Vector2(3.6, -10.4) * k, acc, 1.1 * k)

# LENGYEL SZÁRNYAS HUSZÁR: a szárny a hátra van szíjazva, ezért hátulról
# és oldalról a legfeltűnőbb; szemből keskenyebb, hogy ne takarja az arcot.
func _j_szarny(o: Vector2, k: float, hatulrol: bool, oldalt: bool) -> void:
	var sz := 0.55 if (not hatulrol and not oldalt) else 1.0
	var toll := Color(0.94, 0.91, 0.86, 0.92)
	for oldal in [-1.0, 1.0]:
		if oldalt and oldal < 0.0: continue        # oldalról csak a közelebbi
		var pts := PackedVector2Array([
			o + Vector2(oldal * 2.6 * sz, 4.4) * k,
			o + Vector2(oldal * 8.4 * sz, -3.6) * k,
			o + Vector2(oldal * 5.4 * sz, -11.1) * k,
			o + Vector2(oldal * 3.6 * sz, -4.1) * k,
			o + Vector2(oldal * 1.8 * sz, 3.9) * k,
		])
		draw_colored_polygon(pts, toll)
		for i in range(1, 4):
			var t := float(i) / 4.0
			draw_line(o + Vector2(oldal * (2.4 + t * 1.2) * sz, 3.4 - t * 5.0) * k,
				o + Vector2(oldal * (5.6 + t * 1.4) * sz, 0.4 - t * 6.5) * k,
				Color(0.35, 0.31, 0.27, 0.45), 0.7 * k)
	_kupak(o + Vector2(0, -1.2 * k), Vector2(4.2, 4.2) * k, ACEL_S)

# SPANYOL MORION: taréjos konkvisztádor-sisak tollal.
func _j_morion(o: Vector2, k: float, acc: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		o + Vector2(-5.2, -1.6) * k, o + Vector2(-2.6, -7.2) * k,
		o + Vector2(0, -9.0) * k, o + Vector2(2.6, -7.2) * k,
		o + Vector2(5.2, -1.6) * k, o + Vector2(0, -3.4) * k,
	]), ACEL_J)
	draw_rect(Rect2(o + Vector2(-0.6, -9.2) * k, Vector2(1.2, 6.2) * k), ACEL_S, true)
	_ellipszis(o + Vector2(-3.4, -7.4) * k, Vector2(1.1, 2.6) * k, acc, -0.5)

# KÖZÉPKORI CSÖBÖRSISAK: szemréssel és kis forgóval.
func _j_csobor(o: Vector2, k: float, acc: Color, hatulrol: bool) -> void:
	draw_rect(Rect2(o + Vector2(-4.2, -5.4) * k, Vector2(8.4, 6.6) * k), ACEL_J, true)
	if not hatulrol:
		draw_rect(Rect2(o + Vector2(-3.2, -2.6) * k, Vector2(6.4, 1.1) * k),
			Color(0.16, 0.16, 0.16), true)
	draw_rect(Rect2(o + Vector2(-0.7, -8.4) * k, Vector2(1.4, 3.2) * k), acc, true)

# HÁROMSZÖGLETŰ KALAP kokárdával.
func _j_tricorn(o: Vector2, k: float, acc: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		o + Vector2(-6.4, -3.2) * k, o + Vector2(0, -8.4) * k,
		o + Vector2(6.4, -3.2) * k, o + Vector2(3.0, -1.6) * k,
		o + Vector2(-3.0, -1.6) * k,
	]), Color(0.17, 0.15, 0.13))
	draw_circle(o + Vector2(3.6, -4.4) * k, 1.2 * k, acc)

# CSÁKÓ: 19. századi, ellenzővel és rózsával; a huszárcsákón zsinór és forgó.
func _j_csako(o: Vector2, k: float, col: Color, acc: Color, huszar: bool) -> void:
	draw_rect(Rect2(o + Vector2(-3.6, -10.2) * k, Vector2(7.2, 8.0) * k),
		col.darkened(0.35), true)
	draw_rect(Rect2(o + Vector2(-4.4, -3.2) * k, Vector2(8.8, 1.5) * k),
		Color(0.12, 0.10, 0.09), true)
	if huszar:
		draw_line(o + Vector2(-3.4, -9.0) * k, o + Vector2(3.4, -5.4) * k, acc, 0.8 * k)
		draw_line(o + Vector2(3.4, -9.0) * k, o + Vector2(-3.4, -5.4) * k, acc, 0.8 * k)
		_ellipszis(o + Vector2(0, -13.4) * k, Vector2(1.3, 3.4) * k, acc)
	else:
		draw_circle(o + Vector2(0, -8.6) * k, 1.3 * k, acc)

# LENGYEL ROGATYWKA: négyszögletes czapka.
func _j_rogatywka(o: Vector2, k: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		o + Vector2(-5.4, -8.4) * k, o + Vector2(5.4, -8.4) * k,
		o + Vector2(3.8, -2.2) * k, o + Vector2(-3.8, -2.2) * k,
	]), col.darkened(0.30))
	draw_colored_polygon(PackedVector2Array([
		o + Vector2(-5.4, -8.4) * k, o + Vector2(0, -10.2) * k,
		o + Vector2(5.4, -8.4) * k, o + Vector2(0, -7.0) * k,
	]), col.darkened(0.12))
	draw_rect(Rect2(o + Vector2(-4.4, -2.4) * k, Vector2(8.8, 1.4) * k),
		Color(0.12, 0.10, 0.09), true)

# LAPOS OLDALSAPKA.
func _j_oldalsapka(o: Vector2, k: float, col: Color, acc: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		o + Vector2(-4.6, -2.2) * k, o + Vector2(-2.4, -6.4) * k,
		o + Vector2(0, -7.2) * k, o + Vector2(2.4, -6.4) * k,
		o + Vector2(4.6, -2.2) * k, o + Vector2(0, -4.0) * k,
	]), col.darkened(0.30))
	draw_rect(Rect2(o + Vector2(-3.4, -4.6) * k, Vector2(1.6, 1.2) * k), acc, true)

# BRIT GÁRDA MEDVEBŐR KUCSMA.
func _j_medvebor(o: Vector2, k: float) -> void:
	_ellipszis(o + Vector2(0, -8.4) * k, Vector2(4.2, 7.4) * k,
		Color(0.145, 0.13, 0.115))
	_ellipszis(o + Vector2(-1.4, -9.6) * k, Vector2(1.8, 4.4) * k,
		Color(1, 1, 1, 0.07), 0.2)

# SZÉLES KARIMÁJÚ, TOLLAS KALAP (harmincéves háború).
func _j_szeleskarima(o: Vector2, k: float, acc: Color) -> void:
	_ellipszis(o + Vector2(0, -3.4) * k, Vector2(7.0, 2.1) * k,
		Color(0.23, 0.19, 0.16))
	_ellipszis(o + Vector2(0, -6.0) * k, Vector2(3.4, 3.0) * k,
		Color(0.23, 0.19, 0.16))
	draw_polyline(PackedVector2Array([
		o + Vector2(-2.0, -6.4) * k, o + Vector2(-5.6, -9.2) * k,
		o + Vector2(-9.5, -7.5) * k,
	]), acc, 1.2 * k)

# PORISZ TÜSKÉS SISAK.
func _j_tuskes(o: Vector2, k: float) -> void:
	_kupak(o + Vector2(0, -2.4 * k), Vector2(4.4, 4.4) * k, Color(0.23, 0.20, 0.17))
	draw_rect(Rect2(o + Vector2(-4.6, -2.6) * k, Vector2(9.2, 1.3) * k),
		Color(0.23, 0.20, 0.17), true)
	draw_colored_polygon(PackedVector2Array([
		o + Vector2(-0.9, -6.4) * k, o + Vector2(0, -11.4) * k,
		o + Vector2(0.9, -6.4) * k,
	]), ACEL_J)

# OROSZ CSÚCSOS SISAK.
func _j_prilbica(o: Vector2, k: float) -> void:
	draw_colored_polygon(PackedVector2Array([
		o + Vector2(-4.2, -1.4) * k, o + Vector2(0, -10.6) * k,
		o + Vector2(4.2, -1.4) * k,
	]), ACEL_J)
	draw_rect(Rect2(o + Vector2(-4.4, -2.0) * k, Vector2(8.8, 1.2) * k), ACEL_S, true)

# BUGYONNIJ-SAPKA csillaggal.
func _j_budjonnij(o: Vector2, k: float, col: Color, acc: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		o + Vector2(-4.0, -1.6) * k, o + Vector2(0, -9.8) * k,
		o + Vector2(4.0, -1.6) * k,
	]), col.darkened(0.28))
	draw_circle(o + Vector2(0, -4.6) * k, 1.5 * k, acc)

# BRIT LAPOS ROHAMSISAK.
func _j_brodie(o: Vector2, k: float) -> void:
	_ellipszis(o + Vector2(0, -4.4) * k, Vector2(6.2, 2.4) * k,
		Color(0.36, 0.39, 0.31))
	_kupak(o + Vector2(0, -4.4 * k), Vector2(3.8, 3.8) * k, Color(0.36, 0.39, 0.31))

# FRANCIA ADRIAN-SISAK, tarajjal.
func _j_adrian(o: Vector2, k: float) -> void:
	var sz := Color(0.42, 0.45, 0.35)
	_kupak(o + Vector2(0, -3.4 * k), Vector2(4.4, 4.4) * k, sz)
	draw_rect(Rect2(o + Vector2(-5.0, -3.6) * k, Vector2(10.0, 1.2) * k), sz, true)
	draw_rect(Rect2(o + Vector2(-0.7, -8.0) * k, Vector2(1.4, 4.6) * k),
		sz.darkened(0.25), true)

# NÉMET ACÉLSISAK, széles tarkóval.
func _j_stahl(o: Vector2, k: float) -> void:
	var sz := Color(0.31, 0.34, 0.28)
	_kupak(o + Vector2(0, -3.0 * k), Vector2(4.6, 4.6) * k, sz)
	_ellipszis(o + Vector2(0, -2.4) * k, Vector2(5.6, 2.2) * k, sz)

# EGYSZERŰ MODERN SISAK.
func _j_sisak_modern(o: Vector2, k: float) -> void:
	var sz := Color(0.345, 0.37, 0.305)
	_kupak(o + Vector2(0, -2.8 * k), Vector2(4.4, 4.4) * k, sz)
	draw_rect(Rect2(o + Vector2(-4.6, -3.0) * k, Vector2(9.2, 1.4) * k), sz, true)

# KALÓZ FEJKENDŐ, hátracsapott csücsökkel.
func _j_kendo(o: Vector2, k: float, col: Color) -> void:
	_kupak(o + Vector2(0, -1.6 * k), Vector2(4.3, 4.3) * k, col.darkened(0.10))
	draw_rect(Rect2(o + Vector2(-4.3, -1.8) * k, Vector2(8.6, 1.6) * k),
		col.darkened(0.10), true)
	draw_colored_polygon(PackedVector2Array([
		o + Vector2(-3.8, -1.4) * k, o + Vector2(-8.2, 2.6) * k,
		o + Vector2(-3.8, 1.2) * k,
	]), col.darkened(0.30))

func _c(col: Color, fade: float) -> Color:
	return Color(col.r, col.g, col.b, col.a * fade)

func _draw_sword(h: Vector2, d: Vector2, n: Vector2, blade: float, f: float) -> void:
	draw_line(h - d * 4.0, h + d * 2.0, _c(WOOD_DARK, f), 3.0)          # markolat
	draw_line(h + d * 2.0 - n * 4.0, h + d * 2.0 + n * 4.0,
		_c(GOLD_TRIM, f), 2.0)                                          # keresztvas
	draw_line(h + d * 3.0, h + d * blade, _c(STEEL_DARK, f), 4.0)       # penge
	draw_line(h + d * 3.0, h + d * (blade - 2.0), _c(STEEL, f), 2.0)    # él

func _draw_sabre(h: Vector2, d: Vector2, n: Vector2, f: float) -> void:
	draw_line(h - d * 4.0, h + d * 2.0, _c(WOOD_DARK, f), 3.0)
	var pts := PackedVector2Array()
	for i in range(7):
		var t := float(i) / 6.0
		pts.append(h + d * (3.0 + 19.0 * t) + n * (4.0 * t * t))
	draw_polyline(pts, _c(STEEL_DARK, f), 4.0)
	draw_polyline(pts, _c(STEEL, f), 2.0)

func _draw_spear(h: Vector2, d: Vector2, n: Vector2, f: float) -> void:
	draw_line(h - d * 10.0, h + d * 20.0, _c(WOOD, f), 2.5)             # nyél
	var tip := h + d * 20.0
	draw_colored_polygon(PackedVector2Array([
		tip + n * 2.5, tip - n * 2.5, tip + d * 7.0]), _c(STEEL, f))
	draw_line(h + d * 17.0 - n * 2.5, h + d * 17.0 + n * 2.5,
		_c(STEEL_DARK, f), 2.0)

func _draw_bow(h: Vector2, d: Vector2, n: Vector2, f: float) -> void:
	var c := h + d * 5.0
	var pts := PackedVector2Array()
	for i in range(11):
		var a := PI * (float(i) / 10.0 - 0.5)
		pts.append(c + d * (cos(a) * 4.5) + n * (sin(a) * 11.0))
	draw_polyline(pts, _c(WOOD, f), 2.5)
	draw_line(pts[0], pts[10], _c(Color(0.85, 0.82, 0.72), f), 1.0)     # ideg
	if _att:
		draw_line(c - d * 4.0, c + d * 14.0, _c(WOOD_DARK, f), 1.5)     # vessző
		draw_colored_polygon(PackedVector2Array([
			c + d * 14.0 + n * 2.0, c + d * 14.0 - n * 2.0,
			c + d * 19.0]), _c(STEEL, f))

func _draw_musket(h: Vector2, d: Vector2, n: Vector2, f: float) -> void:
	draw_line(h - d * 9.0 + n * 2.0, h + d * 3.0, _c(WOOD, f), 5.0)     # tus
	draw_line(h - d * 2.0, h + d * 22.0, _c(STEEL_DARK, f), 3.0)        # cső
	draw_line(h + d * 22.0, h + d * 27.0, _c(STEEL, f), 2.0)            # szurony
	if _att:
		draw_circle(h + d * 28.0, 3.5, _c(Color(1.0, 0.85, 0.45, 0.8), f))

func _draw_staff(h: Vector2, d: Vector2, _n: Vector2, f: float) -> void:
	# Majdnem függőleges bot: a kéznél fogja, alul a földig ér.
	draw_line(h - d * 9.0, h + d * 19.0, _c(WOOD, f), 2.5)
	var top := h + d * 19.0
	draw_circle(top, 3.5, _c(GOLD_TRIM, f))
	draw_circle(top + Vector2(-0.8, -0.8), 1.8, _c(Color(1.0, 0.95, 0.7), f))

func _draw_axe(h: Vector2, d: Vector2, n: Vector2, f: float) -> void:
	# Rövid nyél, a végén ívelt bárdfej — kifelé néz, nem a testre.
	draw_line(h - d * 3.0, h + d * 11.0, _c(WOOD, f), 2.0)
	var e := h + d * 10.0
	var blade := PackedVector2Array([
		e - n * 1.5,
		e + d * 2.5 - n * 4.5,
		e + d * 5.5 - n * 3.0,
		e + d * 5.5 + n * 1.0,
		e + d * 2.0 + n * 2.0,
	])
	draw_colored_polygon(blade, _c(STEEL, f))
	var outline := blade.duplicate()
	outline.append(blade[0])
	draw_polyline(outline, _c(STEEL_DARK, f), 1.0)

# ---------------------------------------------------------------------
#  KORSZAKFÜGGŐ HAJÓK
# ---------------------------------------------------------------------

# 19. SZÁZAD: gőz és vitorla. A vitorlás lapra a fedélzet közepe mögé egy
# kéményt rajzolunk, füsttel — ettől lesz a század hajója gőzös, nem karakk.
# A rajz a lap KÉPPONTJAIBAN dolgozik: az origó a hajótest alja (a vízvonal),
# a kép a -h..0 sávban van.
func _draw_funnel() -> void:
	var w: float = _ship_size.x
	var h: float = _ship_size.y
	if w <= 0.0 or h <= 0.0: return
	var deck := -h * 0.30                     # a fedélzet vonala
	var fw := maxf(w * 0.090, 3.2)            # a kémény vastagsága
	var fh := maxf(h * 0.20, 6.0)             # és magassága
	var fx := w * float(FUNNEL_X.get(_role, 0.08))   # árbocok közti hézagba
	var top := deck - fh
	draw_rect(Rect2(fx - fw * 0.5, top, fw, fh), Color(0.13, 0.13, 0.15))
	# Sárgaréz gyűrű a kémény tetején (a század hajóinak szokott jegye)
	draw_rect(Rect2(fx - fw * 0.5, top, fw, fh * 0.22), Color(0.70, 0.56, 0.22))
	draw_rect(Rect2(fx - fw * 0.6, top - fh * 0.10, fw * 1.2, fh * 0.12),
		Color(0.09, 0.09, 0.10))
	# Füst: hátrafelé és fölfelé sodródó pamacsok, egyre halványabban.
	for i in range(4):
		var t := float(i) + 1.0
		draw_circle(Vector2(fx + t * fw * 0.55, top - t * fh * 0.34),
			fw * (0.45 + t * 0.16), Color(0.32, 0.32, 0.34, 0.34 - t * 0.06))

# 20. SZÁZAD: acélhajó. Nincs vitorla, ezért nem lapról jön, hanem rajzoljuk.
# Helyi tér: a test hossza STEEL_LEN (-32 .. +32), a vízvonal y = 0, az ORR
# BALRA néz — ugyanúgy, ahogy a vitorlás lapokon, így a tükrözés is stimmel.
func _draw_steel_ship() -> void:
	match _role:
		"warship":   _steel_destroyer()
		"galleon":   _steel_cruiser()
		"transport": _steel_freighter()
		_:           _steel_trawler()

const STEEL_HULL   := Color(0.33, 0.37, 0.41)
const STEEL_DECK   := Color(0.45, 0.48, 0.51)
const STEEL_LIGHT  := Color(0.56, 0.60, 0.64)
const STEEL_SHADOW := Color(0.22, 0.25, 0.28)
const BOOT_RED     := Color(0.35, 0.16, 0.14)
const GLASS        := Color(0.62, 0.74, 0.80)

# A hajótest: hegyes orr balra, tömör tat jobbra, alul vörös fenékfesték.
func _steel_body(h: float, hull: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(-32.0, -h * 0.95),
		Vector2(-24.0, -h * 0.14),
		Vector2(12.0, 0.0),
		Vector2(27.0, -h * 0.06),
		Vector2(30.0, -h),
		Vector2(-27.0, -h),
	]), hull)
	draw_line(Vector2(-24.0, -h * 0.14), Vector2(27.0, -h * 0.07), BOOT_RED, 1.8)
	draw_line(Vector2(-27.0, -h), Vector2(30.0, -h), STEEL_DECK, 2.0)
	# A test alsó harmada sötétebb: így a lapos folt is testesnek látszik.
	draw_line(Vector2(-25.0, -h * 0.42), Vector2(28.0, -h * 0.36),
		Color(0, 0, 0, 0.18), 3.0)

# Felépítmény-tömb a fedélzeten (x-től x+w-ig, a fedélzet fölött hh magasan).
func _steel_block(x: float, w: float, deck: float, hh: float,
		col: Color = STEEL_LIGHT) -> void:
	draw_rect(Rect2(x, deck - hh, w, hh), col)
	draw_rect(Rect2(x, deck - hh, w, 1.2), STEEL_LIGHT.lightened(0.2))

# Lövegtorony két csővel; a csövek ELŐRE (balra) néznek.
func _steel_turret(x: float, deck: float, s: float, barrels: int = 2) -> void:
	draw_rect(Rect2(x - 3.4 * s, deck - 3.0 * s, 6.8 * s, 3.0 * s), STEEL_LIGHT)
	draw_rect(Rect2(x - 3.4 * s, deck - 3.0 * s, 6.8 * s, 0.9 * s),
		STEEL_LIGHT.lightened(0.18))
	for i in range(barrels):
		var by := deck - 2.3 * s + float(i) * 1.2 * s
		draw_line(Vector2(x - 3.0 * s, by), Vector2(x - 9.5 * s, by),
			STEEL_SHADOW, 1.1 * s)

# Kémény füsttel.
func _steel_funnel(x: float, w: float, deck: float, hh: float) -> void:
	draw_rect(Rect2(x, deck - hh, w, hh), Color(0.26, 0.29, 0.32))
	draw_rect(Rect2(x - 0.4, deck - hh - 0.9, w + 0.8, 1.1), Color(0.12, 0.13, 0.15))
	for i in range(3):
		var t := float(i) + 1.0
		draw_circle(Vector2(x + w * 0.5 + t * 1.7, deck - hh - t * 2.6),
			1.4 + t * 0.7, Color(0.34, 0.34, 0.36, 0.30 - t * 0.07))

# Árboc keresztrúddal (radar/antenna a tetején).
func _steel_mast(x: float, top: float, hh: float) -> void:
	draw_line(Vector2(x, top), Vector2(x, top - hh), STEEL_SHADOW, 1.0)
	draw_line(Vector2(x - 2.6, top - hh * 0.62), Vector2(x + 2.6, top - hh * 0.62),
		STEEL_SHADOW, 0.9)
	draw_line(Vector2(x - 1.8, top - hh), Vector2(x + 1.8, top - hh),
		STEEL_LIGHT, 0.9)

# ROMBOLÓ: karcsú test, elöl-hátul egy-egy lövegtorony, középen híd és kémény.
func _steel_destroyer() -> void:
	var h := 8.5
	var deck := -h
	_steel_body(h, STEEL_HULL)
	_steel_turret(-17.0, deck, 1.0)
	_steel_turret(19.0, deck, 0.9)
	_steel_block(-8.0, 13.0, deck, 4.2)                 # híd alatti tömb
	_steel_block(-5.5, 6.5, deck - 4.2, 3.4)            # parancsnoki híd
	draw_rect(Rect2(-5.0, deck - 6.6, 5.5, 1.3), GLASS)  # hídablakok
	_steel_funnel(4.5, 4.0, deck, 7.5)
	_steel_mast(-2.0, deck - 7.6, 8.0)
	# Légvédelmi gépágyú a kémény mögött
	draw_circle(Vector2(11.5, deck - 1.2), 1.6, STEEL_LIGHT)
	draw_line(Vector2(11.5, deck - 1.6), Vector2(8.5, deck - 3.4), STEEL_SHADOW, 0.9)

# NEHÉZCIRKÁLÓ: hosszabb, magasabb test, három torony, két kémény, toronyhíd.
func _steel_cruiser() -> void:
	var h := 11.0
	var deck := -h
	_steel_body(h, STEEL_HULL.darkened(0.06))
	_steel_turret(-21.0, deck, 1.15, 3)
	_steel_turret(-12.5, deck - 2.6, 1.05, 3)           # emelt, lépcsős torony
	_steel_turret(21.0, deck, 1.1, 3)
	_steel_block(-7.0, 18.0, deck, 5.0)
	_steel_block(-5.0, 7.0, deck - 5.0, 6.5)            # toronyhíd
	draw_rect(Rect2(-4.5, deck - 10.6, 6.0, 1.4), GLASS)
	_steel_funnel(3.0, 4.2, deck - 5.0, 6.0)
	_steel_funnel(9.0, 4.2, deck - 5.0, 5.0)
	_steel_mast(-1.5, deck - 11.5, 9.0)
	_steel_mast(14.0, deck - 5.0, 7.0)

# TEHERHAJÓ / SZÁLLÍTÓ: alacsony, hosszú test, rakodónyílások és darupóznák,
# hátul a híd és a kémény. Fegyvere egyetlen hátsó löveg.
func _steel_freighter() -> void:
	var h := 10.0
	var deck := -h
	_steel_body(h, Color(0.30, 0.27, 0.24))
	# rakodónyílások
	for x in [-19.0, -10.0, -1.0]:
		draw_rect(Rect2(x, deck - 1.6, 7.0, 1.6), Color(0.42, 0.36, 0.28))
	# darupóznák, kinyúló gémmel
	for x in [-13.5, -4.5]:
		draw_line(Vector2(x, deck), Vector2(x, deck - 9.0), Color(0.46, 0.40, 0.31), 1.2)
		draw_line(Vector2(x, deck - 8.0), Vector2(x - 5.5, deck - 4.0),
			Color(0.46, 0.40, 0.31), 1.0)
	_steel_block(9.0, 14.0, deck, 4.6, Color(0.72, 0.71, 0.67))
	_steel_block(12.0, 7.5, deck - 4.6, 3.2, Color(0.78, 0.77, 0.73))
	draw_rect(Rect2(12.5, deck - 7.2, 6.5, 1.3), GLASS)
	_steel_funnel(18.5, 4.0, deck - 4.6, 6.0)
	draw_circle(Vector2(26.0, deck - 1.0), 1.5, STEEL_LIGHT)
	draw_line(Vector2(26.0, deck - 1.4), Vector2(22.5, deck - 3.0), STEEL_SHADOW, 0.9)

# HALÁSZHAJÓ (vonóhálós): zömök test, hátul kormányállás, elöl rakodóárboc,
# a taton hálódob és kihajló gém.
func _steel_trawler() -> void:
	var h := 9.5
	var deck := -h
	_steel_body(h, Color(0.16, 0.30, 0.26))
	_steel_block(6.0, 15.0, deck, 5.0, Color(0.80, 0.79, 0.74))
	_steel_block(9.0, 8.0, deck - 5.0, 3.6, Color(0.86, 0.85, 0.80))
	draw_rect(Rect2(9.5, deck - 8.2, 7.0, 1.5), GLASS)
	_steel_funnel(21.0, 3.2, deck - 5.0, 4.0)
	# rakodóárboc a hajóorr felé, kihajló gémmel
	draw_line(Vector2(-6.0, deck), Vector2(-6.0, deck - 12.0),
		Color(0.55, 0.45, 0.30), 1.3)
	draw_line(Vector2(-6.0, deck - 11.0), Vector2(-20.0, deck - 3.5),
		Color(0.55, 0.45, 0.30), 1.0)
	# hálódob a taton
	draw_circle(Vector2(25.0, deck - 2.0), 2.6, Color(0.44, 0.40, 0.33))
	draw_circle(Vector2(25.0, deck - 2.0), 1.2, Color(0.30, 0.27, 0.22))

# Végső tartalék, ha valamiért nincs meg a lap.
func _make_placeholder(role: String, owner_id: int) -> void:
	_kind = Kind.NONE
	region_enabled = false
	offset = Vector2(0, -10)
	var base: Color = Color("3f6b9b") if owner_id == GameState.en_id else Color("8b3a3a")
	if role == "worker": base = base.lightened(0.3)
	var size := 20
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := (size - 1) * 0.5
	for y in range(size):
		for x in range(size):
			if Vector2(x - c, y - c).length() <= c - 1.0:
				img.set_pixel(x, y, base)
	texture = ImageTexture.create_from_image(img)
