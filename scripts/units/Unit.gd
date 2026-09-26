class_name Unit
extends CharacterBody2D

const EgysegRajz := preload("res://scripts/units/UnitSprite.gd")
const Holttest := preload("res://scripts/units/Holttest.gd")

@export var role      : String  = "melee"
@export var owner_id  : int     = 0
@export var age       : int     = 0
@export var max_hp    : float   = 100.0
@export var dmg       : float   = 12.0
@export var spd       : float   = 72.0
@export var radius    : float   = 9.0
@export var vision_r  : float   = 120.0
@export var naval     : bool    = false
@export var atk_range : float   = 32.0
# Páncél: ennyit vesz le minden találatból. Alapból nulla — a kovácsműhely
# páncélműhelye emeli. (Lásd take_damage és Upgrades.ARMOR_PER.)
var armor     : float   = 0.0

var hp       : float   = 100.0
var face     : float   = 0.0
var walk     : float   = 0.0
var target   : Node2D  = null
var _sel     : bool    = false
var _fired   : float   = 0.0
var _carry   : float   = 0.0
var _carry_kind : String = ""
# Gyűjtés: hányadik ütésnél tart, mikor jöhet a következő, és hogy épp a
# megtelt rakománnyal tart-e vissza a leadóhelyre.
var _swings  : int     = 0
var _swing_t : float   = 0.0
var _hauling : bool    = false
var _gather_node : Node2D = null
var _drop_node   : Node2D = null
# A JÁTÉKOS munkásai nem indulnak el maguktól: várnak, amíg parancsot
# kapnak (gyűjtés egy lelőhelyre, vagy építés). A bot munkásai viszont
# automatikusan dolgoznak, különben az ellenfélnek nem lenne gazdasága.
var auto_gather  : bool   = false
# Építési megbízás: ehhez az épülethez megy, és amíg ott áll, épül.
var build_target : Node2D = null
# Melyik nyersanyagra áll rá a munkás. Üres = a legközelebbit választja.
# Enélkül minden munkás ugyanarra a legközelebbi lelőhelyre megy, és a
# gazdaság fél lábon áll: fa gyűl, kő és étel viszont sosem.
var gather_pref  : String = ""
var team_color   : Color  = Color.WHITE
var team_accent  : Color  = Color.WHITE
# A csapatszám MAGÁN az egységen: az ellenségkeresés ezt olvassa, és így
# nem kell képpontonként a GameState szótáraiban keresgélni.
var team         : int    = 0

# Egység statisztikák korszakonként [age0,age1,age2,age3]
const UNIT_STATS := {
	"worker":   {"hp": [45, 50, 58, 66],      "dmg": [3, 3, 4, 4],       "speed": [64, 66, 70, 76]},
	"melee":    {"hp": [95, 125, 160, 340],   "dmg": [11, 15, 20, 38],   "speed": [72, 74, 76, 60]},
	"ranged":   {"hp": [55, 70, 88, 105],     "dmg": [8, 14, 19, 7],     "speed": [62, 62, 64, 62]},
	"spear":    {"hp": [78, 98, 118, 124],    "dmg": [9, 13, 17, 30],    "speed": [58, 60, 62, 56]},
	"cav":      {"hp": [80, 100, 120, 190],   "dmg": [10, 14, 18, 26],   "speed": [118, 124, 132, 150]},
	"priest":   {"hp": [55, 70, 85, 100],     "dmg": [0, 0, 0, 0],       "speed": [60, 62, 64, 66]},
	"spy":      {"hp": [40, 50, 60, 70],      "dmg": [15, 22, 30, 40],   "speed": [90, 95, 100, 110]},
	"ram":      {"hp": [340, 420, 520, 620],  "dmg": [30, 42, 56, 72],   "speed": [26, 28, 32, 36]},
	"hero":     {"hp": [420, 520, 640, 780],  "dmg": [34, 46, 60, 78],   "speed": [86, 88, 92, 96]},
	"siege":    {"hp": [110, 130, 155, 180],  "dmg": [26, 38, 52, 68],   "speed": [30, 32, 36, 40]},
	"medic":    {"hp": [60, 75, 90, 110],     "dmg": [0, 0, 0, 0],       "speed": [68, 70, 72, 74]},
	"fisher":   {"hp": [80, 100, 125, 155],   "dmg": [6, 9, 13, 18],     "speed": [54, 58, 64, 70]},
	"warship":  {"hp": [190, 250, 330, 430],  "dmg": [16, 26, 38, 54],   "speed": [58, 62, 68, 74]},
	"galleon":  {"hp": [340, 420, 520, 640],  "dmg": [26, 38, 52, 68],   "speed": [46, 50, 54, 58]},
	"transport": {"hp": [150, 190, 240, 300], "dmg": [10, 14, 19, 25],   "speed": [54, 58, 64, 70]},
	"fighter":  {"hp": [1, 1, 1, 140],        "dmg": [0, 0, 0, 26],      "speed": [0, 0, 0, 132]},
	"bomber":   {"hp": [1, 1, 1, 230],        "dmg": [0, 0, 0, 64],      "speed": [0, 0, 0, 86]},
}

# Vízen mozgó egységek (2-es navigációs réteg)
const NAVAL_ROLES := ["fisher", "warship", "galleon", "transport"]

# LÉGI EGYSÉGEK. Nem az úthálózaton mennek: egyenesen repülnek a cél felé,
# a tereptől és a többiektől függetlenül. Korábban a szárazföldi navigációs
# rétegen jártak — a repülőtér olyan gépeket épített, amiket megállított a
# víz és kikerültek egy sziklát.
const AIR_ROLES := ["fighter", "bomber"]
var air: bool = false
# Mennyivel rajzoljuk a gépet a talajárnyéka fölé.
const AIR_HEIGHT := 26.0

# A hálózati pillanatképben a szerepkör SORSZÁMKÉNT utazik, nem szövegként.
# A sorrend nem változtatható, mert a régi mentések és a társak is ezt
# használják.
const ROLE_ORDER := ["worker", "melee", "ranged", "spear", "cav", "priest",
	"spy", "ram", "hero", "siege", "medic", "fisher", "warship", "galleon",
	"transport", "fighter", "bomber"]

# --- VETERÁNSÁG ÉS HARCI ÁLLÁS  (index.html 8/B) ---
#
# VETERÁNSÁG
#   Minden egység gyűjti az öléseit: három után veterán, hat után elit.
#   Fokozatonként +10% sebzés és +10% életerő. Egy megélt csapat többet ér,
#   mint egy friss — érdemes vigyázni rájuk.
#
# HARCI ÁLLÁS (egységenként)
#   Támadó      — magától célt fog és üldözi
#   Tartsd      — nem mozdul, csak arra lő, ami hatótávba ér
#   Visszavonul — ha az életereje 40% alá esik, elhátrál a harcból
const VET_KILLS := [0, 3, 6]
const VET_BONUS := 0.10
const VET_KULCS := ["vet_ujonc", "vet_veteran", "vet_elit"]

var kills   : int   = 0
var vet     : int   = 0
var _vet_at : float = -99.0

const STANCE_AGGRO := "aggro"
const STANCE_HOLD  := "hold"
const STANCE_FLEE  := "flee"
const STANCES := [STANCE_AGGRO, STANCE_HOLD, STANCE_FLEE]

var stance: String = STANCE_AGGRO
# Meddig fut a megtört morálú egység (lásd _moral_tick, index.html 9/E).
var _moral_futas_ig: float = -99.0

# --- ALAKZATOK  (index.html 8/B) ---
#
# Nem csak a felállás más: mindegyik ad valamit, és elvesz valamit.
#   VONAL    — széles tűzvonal: a lövészek 10%-kal messzebbre lőnek
#   ÉK       — roham: 12%-kal gyorsabb és 12%-kal nagyobbat üt
#   NÉGYSZÖG — tömör védelem: +2 páncél, de 15%-kal lassabb menet
#
# Az alakzat FÉLENKÉNT él (a gazdáé számít, nem a helyi játékosé),
# különben hálózaton más erővel harcolna ugyanaz a katona a két gépen.
const FORMATIONS := ["line", "wedge", "square"]
const FORM_ARMOR := 2.0

static func formation_of(owner_id: int) -> String:
	var f := str(GameState.get_side(owner_id).get("formation", "line"))
	return f if f in FORMATIONS else "line"

# Az alakzat szorzói. A terep és a hős aurája ezekre rakódik rá.
func form_mul(mit: String) -> float:
	if naval or air or role == "worker": return 1.0
	match formation_of(owner_id):
		"line":   return 1.10 if mit == "range" and role == "ranged" else 1.0
		"wedge":  return 1.12 if mit == "dmg" or mit == "speed" else 1.0
		"square": return 0.85 if mit == "speed" else 1.0
	return 1.0

func form_armor() -> float:
	if naval or air or role == "worker": return 0.0
	return FORM_ARMOR if formation_of(owner_id) == "square" else 0.0

# --- A TEREP HATÁSA  (index.html 9/D) ---
#
#   ERDŐ  — fák között +2 páncél: a fedezék véd a nyilaktól és a golyóktól
#   HEGY  — sziklás magaslaton +15% lőtáv: aki a dombot tartja, messzebbre lő
#   PART  — a sekély vízparti homokban 20%-kal lassabb a menet
#
# Félmásodpercenként számoljuk újra, nem képkockánként — a talaj nem
# változik olyan gyorsan, a lekérdezés viszont sok egységnél sokba kerül.
const TEREP_KOZ := 0.5
const TEREP_PANCEL := 2.0
const TEREP_LOTAV := 1.15
const TEREP_TEMPO := 0.80

var terep_pancel : float = 0.0
var terep_lotav  : float = 1.0
var terep_tempo  : float = 1.0
var _terep_t     : float = 0.0

# Hálózati azonosító: a házigazda osztja, a csatlakozó ebből ismeri fel,
# melyik bábut kell mozgatnia.
var nid: int = 0
# Csatlakozónál a pillanatképből kapott hely, ahová simán odacsúszunk.
var _net_pos: Vector2 = Vector2.ZERO
var _net_have: bool = false
# Az ellenségkeresés üteme (mp) és a hátralévő idő. Lásd a _think-ben.
const SCAN_PERIOD := 0.4
var _scan_t: float = 0.0

# --- Gyógyítás és térítés ---
# A felcser épp kit lát el (a rajzoláshoz is kell), a pap kit térít, és
# mennyi ideje tartja rajta a szót. A két időbélyeg a rajzé: mikor kapott
# az egység gyógyítást, illetve mikor érte utoljára találat.
var _heal_target   : Node2D = null
var convert_target : Node2D = null
var _chan          : float  = 0.0
var _healed_at     : float  = -99.0
var _hit_at        : float  = -99.0

# Meddig tart a hős bátorítása ezen az egységen. A hős osztja szét
# (lásd _hero_aura), nem az egységek keresgélik.
var _aura_until    : float  = -99.0
var _aura_t        : float  = 0.0

func inspired() -> bool:
	return GameState.t < _aura_until

# Meddig van leleplezve a kém (lásd _spy_tick).
var _exposed_until : float = -99.0
var _spy_t         : float = 0.0

# Álruhában van-e? Az álruhás kémre nem lőnek: az ellenség a sajátjának
# nézi. Az őrtorony viszont leleplezi.
func disguised() -> bool:
	return role == "spy" and GameState.t >= _exposed_until

# --- Csapatszállítás ---
#
# A szállítóhajó eddig csak egy gyenge bárka volt: a NEVÉN kívül semmi nem
# utalt arra, hogy szállít. Mostantól szárazföldi egységeket vesz fel, és a
# túlparton kirakja őket — enélkül a vízen túli föld elérhetetlen marad
# annak, akinek nincs hídja.
const CARGO_CAP := 8
# Kit visz éppen. A fedélzeten lévő egység kikerül a világból: nem lehet
# rálőni, nem ütközik, és a hajóval együtt mozog.
var cargo: Array[Node] = []
# Melyik hajó fedélzetén vagyunk (null = a szárazon).
var carrier: Node = null

func can_carry() -> bool:
	return role == "transport"

func cargo_free() -> int:
	_prune_cargo()
	return CARGO_CAP - cargo.size()

func _prune_cargo() -> void:
	var elo: Array[Node] = []
	for u in cargo:
		if is_instance_valid(u): elo.append(u)
	cargo = elo

# Beszáll a hajóba. A szárazföldi egységek férnek rá; hajó hajóra nem.
func board(ship: Node) -> bool:
	if ship == null or not is_instance_valid(ship): return false
	if not ship.can_carry() or naval or air: return false
	if int(ship.owner_id) != owner_id: return false
	if ship.cargo_free() <= 0: return false
	stop()
	carrier = ship
	ship.cargo.append(self)
	visible = false
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	return true

# A fedélzeten van-e? Ilyenkor nem célpont és nem is parancsolható — de a
# CSOPORTJAIBAN benne marad, hogy a népesség tovább számolja. (Ha kivennénk
# a „units" csoportból, a hajóra pakolással ingyen férőhelyet lehetne
# nyerni.)
func aboard() -> bool:
	return carrier != null and is_instance_valid(carrier)

# Kiszállás a parton. A hajó adja ki a parancsot (unload_at).
func disembark(pos: Vector2) -> void:
	carrier = null
	global_position = pos
	visible = true
	set_physics_process(true)
	collision_layer = 1
	collision_mask = 1
	nav.target_position = pos
	queue_redraw()

# PARANCS: eredj a hajóhoz és szállj be. A tényleges beszállás akkor
# történik, amikor odaért (lásd _board_tick) — a pálya túlvégéről nem lehet
# felugrani a fedélzetre.
var board_target : Node2D = null
# PARANCS a hajónak: menj a partra és tedd ki a csapatot.
var unload_at_pos : Vector2 = Vector2.INF

func board_order(ship: Node2D) -> void:
	stop()
	board_target = ship
	nav.target_position = ship.global_position

func unload_order(pos: Vector2) -> void:
	target = null
	unload_at_pos = pos
	# A hajó a part LEGKÖZELEBBI vízi pontjára áll be; a csapat onnan lép
	# ki a szárazra.
	var main := get_tree().get_first_node_in_group("main")
	var meddig := pos
	if main != null:
		meddig = main.find_land_near(pos, 30.0, true)
	nav.target_position = meddig

# A beszállás közeli munkája: ha odaért a hajóhoz, felszáll rá.
func _board_tick() -> void:
	if not is_instance_valid(board_target):
		board_target = null
		return
	var d := global_position.distance_to(board_target.global_position)
	if d > radius + float(board_target.radius) + 26.0:
		_set_nav_target(board_target.global_position)
		return
	var hajo := board_target
	board_target = null
	if not board(hajo):
		# Megtelt: a parton marad, és szólunk róla.
		var main := get_tree().get_first_node_in_group("main")
		if main != null and main.hud != null and owner_id == GameState.en_id:
			main.hud.show_toast(Lang.t("uz_hajo_tele"), 2.5)

# A hajó kirakodása, ha odaért a partra.
func _unload_tick() -> void:
	if unload_at_pos == Vector2.INF: return
	if global_position.distance_to(nav.target_position) > radius + 40.0: return
	var n := unload_at(unload_at_pos)
	unload_at_pos = Vector2.INF
	var main := get_tree().get_first_node_in_group("main")
	if n > 0 and main != null and main.hud != null and owner_id == GameState.en_id:
		main.hud.show_toast(Lang.t("uz_partra"), 2.5)

# A hajó partra teszi a rakományát a megadott pont körül.
func unload_at(pos: Vector2) -> int:
	_prune_cargo()
	if cargo.is_empty(): return 0
	var main := get_tree().get_first_node_in_group("main")
	var n := cargo.size()
	for i in range(n):
		var a := TAU * float(i) / float(maxi(n, 1))
		var p := pos + Vector2(cos(a), sin(a)) * (26.0 + 5.0 * i)
		if main != null:
			p = main.find_land_near(p, 20.0)
		(cargo[i] as Node).disembark(p)
	cargo.clear()
	return n

@onready var sprite    := $Sprite2D
@onready var nav       := $NavigationAgent2D as NavigationAgent2D
@onready var hp_bar    := $HPBar/ProgressBar as ProgressBar
@onready var sel_ring  := $SelectionRing as Node2D
@onready var atk_timer := $AttackTimer as Timer

func _ready() -> void:
	naval = role in NAVAL_ROLES
	air   = role in AIR_ROLES
	_apply_stats()
	atk_range = Combat.range_for(role, age)
	vision_r  = Combat.vision_for(role, age) * Upgrades.vision_mul(owner_id)
	radius    = Combat.radius_for(role, age)
	hp = max_hp
	# A talpgyűrűt, az árnyékot és az életsávot magunk rajzoljuk (_draw),
	# ahogy az eredeti is teszi — a jelenetbeli csomópontok rejtve maradnak.
	hp_bar.visible = false
	sel_ring.visible = false
	team        = GameState.team_of(owner_id)
	team_color  = Style.side_color(owner_id)
	team_accent = Style.side_accent(owner_id)
	atk_timer.wait_time = Combat.cooldown_for(role)
	atk_timer.timeout.connect(_on_attack)
	add_to_group("units")
	if owner_id == GameState.en_id:
		add_to_group("player_units")
	else:
		add_to_group("enemy_units")
		auto_gather = true
	nav.navigation_layers = 2 if naval else 1
	nav.radius = radius
	if air:
		# A gép a fejek FÖLÖTT húz el, és nem ütközik senkivel: sem a
		# terephez, sem a földi egységekhez nincs köze.
		z_index = 5
		collision_layer = 0
		collision_mask = 0
		sprite.position = Vector2(0, -AIR_HEIGHT)
	_scan_t = randf() * SCAN_PERIOD      # szétszórva, ne egyszerre keressenek
	# Sprite setup
	if sprite.has_method("setup"):
		sprite.setup(role, age, owner_id)

# Az egység alatti jelzések, pontosan az eredeti arányaival:
#   kontaktárnyék  ellipszis (2s, 3.4s) sugár (r*0.7, r*0.3) fekete .14
#   csapatgyűrű    ellipszis (0, 3.4s)  sugár (r*0.95, r*0.42), ellenségnél szaggatott
#   kijelölő gyűrű ellipszis (0, 3.4s)  sugár (r+3.5, (r+3.5)*0.45) kiemelő színnel
func _draw() -> void:
	var s := radius / 9.2
	var cy := 3.4 * s
	if not naval:
		# KONTAKTÁRNYÉK a figura alatt, a NAP ÁLLÁSA szerint dőlve: reggel
		# hosszan nyugatra, délben rövid, este keletre (index.html 16/D).
		var nap := _nap_arnyek()
		_ellipse(Vector2(radius * float(nap["dx"]), cy + radius * 0.06),
			Vector2(radius * 0.7 * float(nap["len"]), radius * 0.3),
			Color(0, 0, 0, 0.14), true)
	var ring := _ring_color()
	ring.a = 0.6
	_ellipse(Vector2(0, cy), Vector2(radius * 0.95, radius * 0.42), ring, false,
		2.0, owner_id != GameState.en_id)
	if _sel:
		_ellipse(Vector2(0, cy), Vector2(radius + 3.5, (radius + 3.5) * 0.45),
			team_accent, false, 1.8)
		_ellipse(Vector2(0, cy + 1.0), Vector2(radius + 3.5, (radius + 3.5) * 0.45),
			Color(0, 0, 0, 0.35), false, 0.8)
	_draw_hp_bar()
	_draw_carry()
	_draw_heal_fx()
	_draw_vet()

# VETERÁN JELZÉS: egy-két apró arany ék a talpvonalnál. Épp csak annyi,
# hogy egy pillantásra látszódjon, melyik csapat megélt már valamit —
# és előléptetéskor felvillan egy gyűrű.
# A nap állása az árnyékhoz. Ha nincs nap-éjszaka (vagy még nem áll a
# csomópont), marad az eddigi, rögzített dőlés.
func _nap_arnyek() -> Dictionary:
	var d := _daynight()
	if d == null: return {"dx": 0.22, "dy": 0.17, "len": 1.0}
	return d.sun_shadow()

func _draw_vet() -> void:
	if vet <= 0: return
	var arany := Color("e8c96a")
	var y := -_head_y() * 0.0 + 3.4 * (radius / 9.2) + 3.0
	for i in range(vet):
		var x := -3.0 + float(i) * 6.0
		draw_polyline([Vector2(x - 2.4, y + 2.2), Vector2(x, y - 0.6),
			Vector2(x + 2.4, y + 2.2)], arany, 1.4, true)
	var kor := GameState.t - _vet_at
	if kor >= 0.0 and kor < 0.9:
		var a := 1.0 - kor / 0.9
		_ellipse(Vector2(0, 3.4 * (radius / 9.2)),
			Vector2(radius + 4.0 + kor * 14.0, (radius + 4.0 + kor * 14.0) * 0.45),
			Color(arany.r, arany.g, arany.b, a * 0.8), false, 2.0)

# A KIJELÖLT munkás feje fölött látszik, mennyi nyersanyag van nála és
# miből: egy színes pötty (fa / kő / arany / élelem) és a "meglévő / teli
# rakomány" szám. Csak kijelölve, hogy ne legyen tele a pálya számokkal.
func shows_carry() -> bool:
	return _sel and _carry > 0.0 and _carry_kind != ""

func _draw_carry() -> void:
	if not shows_carry(): return
	var font := ThemeDB.fallback_font
	if font == null: return
	var txt := "%d/%d" % [int(round(_carry)), int(load_cap())]
	const FS := 10
	var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
	var w := tw + 16.0
	# A címke a fej FÖLÖTT áll: a szülő rajza a gyerek sprite alá kerül,
	# ezért a figurán belül nem látszana.
	var top := _head_y() - (20.0 if hp < max_hp else 6.0) - 13.0
	var box := Rect2(-w * 0.5, top, w, 13.0)
	draw_rect(box, Color(0, 0, 0, 0.58), true)
	# Teli rakománynál aranykeret: ez a jel, hogy elindul leadni.
	if _hauling or _carry >= load_cap():
		draw_rect(box, Color(0.85, 0.72, 0.30, 0.9), false, 1.0)
	draw_circle(box.position + Vector2(6.0, 6.5), 3.2,
		ResourceSystem.res_color(_carry_kind))
	draw_string(font, box.position + Vector2(11.0, 10.0), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Color(0.96, 0.94, 0.88))

# Az álruhás kém AZ ELLENSÉG SZÍNEIT viseli — ettől nem lőnek rá. A
# leleplezés után visszatér a saját jelzőszíne, és onnantól célpont.
func _ring_color() -> Color:
	if not disguised(): return team_color
	for s in GameState.oldalak:
		if GameState.hostile(owner_id, int(s["i"])):
			return Style.side_color(int(s["i"]))
	return team_color

# Meddig látszik a gyógyulás jele az utolsó adag után.
const HEAL_FX_TIME := 0.6

# Két jelzés, mert enélkül a gyógyítás és a térítés láthatatlan munka lenne:
#
#   zöld kereszt a fej fölött — ez az egység épp most kapott ellátást,
#   körív a célpont alatt      — ennyire jutott a pap a meggyőzéssel.
func _draw_heal_fx() -> void:
	var el := GameState.t - _healed_at
	if el >= 0.0 and el < HEAL_FX_TIME:
		var a := 1.0 - el / HEAL_FX_TIME
		var c := Color(0.42, 0.88, 0.45, a)
		# Fölfelé szálló kereszt: a mozgás teszi észrevehetővé.
		var p := Vector2(0.0, _head_y() - 16.0 - el * 10.0)
		draw_line(p + Vector2(-4, 0), p + Vector2(4, 0), c, 2.0)
		draw_line(p + Vector2(0, -4), p + Vector2(0, 4), c, 2.0)
	if _chan <= 0.0 or not is_instance_valid(convert_target): return
	var frac := clampf(_chan / maxf(Combat.convert_time_for(age), 0.01), 0.0, 1.0)
	var to := to_local(convert_target.global_position)
	draw_line(Vector2(0.0, _head_y() * 0.45), to, Color(0.95, 0.85, 0.45, 0.4), 1.5)
	var pts := PackedVector2Array()
	for i in range(17):
		var ang := -PI * 0.5 + TAU * frac * float(i) / 16.0
		pts.append(to + Vector2(cos(ang) * 15.0, sin(ang) * 7.0 + 4.0))
	if pts.size() > 1:
		draw_polyline(pts, Color(0.95, 0.85, 0.45, 0.9), 2.0)

# A figura feje hozzávetőleges magassága. A gyalogosokat egységesen 46 px
# magasra méretezzük, a hajók ennél nagyobbak — a sugarukhoz mérjük.
func _head_y() -> float:
	# A gép a talajárnyéka FÖLÖTT repül, ezért az életsávja is följebb kell
	# hogy kerüljön — különben a szárnyára esne.
	if air: return -(AIR_HEIGHT + 20.0)
	# Az eredeti arányai (drawUnit): a gyalogos életsávja 25·s-sel a talp
	# fölött, a hajóé a vitorlák fölött (s = r / 9.2).
	if naval: return -(EgysegRajz.ship_bar_height(role) - 6.0)
	return -19.0 * radius / 9.2

func _draw_hp_bar() -> void:
	if hp >= max_hp: return
	var frac := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	var w := maxf(18.0, radius * 2.0)
	var top := _head_y() - 6.0
	draw_rect(Rect2(-w * 0.5 - 1.0, top - 1.0, w + 2.0, 5.0), Color(0, 0, 0, 0.55), true)
	var c := Color("6fae52")
	if frac < 0.55: c = Color("c98b3a")
	if frac < 0.28: c = Color("c04a3a")
	draw_rect(Rect2(-w * 0.5, top, w * frac, 3.0), c, true)

func _ellipse(c: Vector2, r: Vector2, col: Color, filled: bool,
			  width: float = 1.0, dashed: bool = false) -> void:
	const SEG := 24
	var pts := PackedVector2Array()
	for i in range(SEG + 1):
		var a := TAU * float(i) / SEG
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	if filled:
		draw_colored_polygon(pts, col)
	elif dashed:
		# szaggatott: minden második szakasz marad ki
		for i in range(0, SEG, 2):
			draw_line(pts[i], pts[i + 1], col, width)
	else:
		draw_polyline(pts, col, width)

func _apply_stats() -> void:
	var st: Dictionary = UNIT_STATS.get(role, {})
	var a := clampi(age, 0, 3)
	if not st.is_empty():
		max_hp = float(st["hp"][a])
		dmg    = float(st["dmg"][a])
		spd    = float(st["speed"][a])
	# A kovácsműhely három ága: fegyver (sebzés), ellátmány (életerő) és
	# páncél (a találatból levont érték — lásd take_damage).
	dmg    *= Upgrades.damage_mul(owner_id)
	max_hp *= Upgrades.hp_mul(owner_id)
	armor   = Upgrades.armor_of(owner_id)
	# A VETERÁN nagyobbat üt és többet bír (fokozatonként +10%).
	var vm := 1.0 + float(vet) * VET_BONUS
	dmg    *= vm
	max_hp *= vm
	# Az ALAKZAT az egész félre hat: az ék üt nagyobbat, a négyszög véd.
	dmg   *= form_mul("dmg")
	armor += form_armor()

# --- Előléptetés ---
#
# Egy ölés jóváírása annak, aki elejtette. Az előléptetés a sebesülés
# ARÁNYÁT megtartja (nem gyógyít teljesen), de egy kis erőt ad hozzá.
func credit_kill() -> void:
	kills += 1
	promote()

func vet_rank() -> int:
	if kills >= VET_KILLS[2]: return 2
	if kills >= VET_KILLS[1]: return 1
	return 0

func promote() -> bool:
	var uj := vet_rank()
	if uj == vet: return false
	var arany := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	vet = uj
	_apply_stats()
	hp = clampf(max_hp * (arany + 0.08), 1.0, max_hp)
	_vet_at = GameState.t
	queue_redraw()
	if owner_id == GameState.en_id:
		SFX.play("age", -10.0)
		var fo := get_tree().get_first_node_in_group("main")
		if fo != null and fo.hud != null:
			fo.hud.show_toast("%s %s: %s" % [Lang.t("u_" + role),
				Lang.t("eloleptetve"), Lang.t(VET_KULCS[vet])], 3.0)
	return true

# Meneküljön-e? A Visszavonulás állásban megsérülve, vagy ha a morál
# megtört (lásd _moral_tick).
func should_flee() -> bool:
	if role == "worker" or naval or air: return false
	if GameState.t < _moral_futas_ig: return true
	return stance == STANCE_FLEE and hp < max_hp * 0.4

# A menekülés iránya: el a legközelebbi ellenségtől, ha nincs, a bázis felé.
func _flee_move() -> void:
	target = null
	if not atk_timer.is_stopped(): atk_timer.stop()
	var e := Combat.find_enemy(self, 320.0)
	var cel: Vector2
	if e != null:
		cel = global_position + (global_position - e.global_position)
	else:
		var hq := _own_hq()
		if hq == null: return
		cel = hq.global_position
	_set_nav_target(Vector2(
		clampf(cel.x, 40.0, float(GameState.WORLD_W) - 40.0),
		clampf(cel.y, 40.0, float(GameState.WORLD_H) - 40.0)))

func _own_hq() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and int(b.owner_id) == owner_id and b.tipus == "hq":
			return b
	return null

# Minden olyan érték újraszámolása, amit a gazda fejlesztései befolyásolnak.
# A friss fokozat a MÁR PÁLYÁN LÉVŐ katonákra is vonatkozik; az életerőt
# arányosan visszük át, hogy a kutatás se ne gyógyítson, se ne sebezzen.
func refresh_stats() -> void:
	var arany := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	_apply_stats()
	atk_range = Combat.range_for(role, age)
	vision_r  = Combat.vision_for(role, age) * Upgrades.vision_mul(owner_id)
	radius    = Combat.radius_for(role, age)
	hp = maxf(1.0, max_hp * arany)
	queue_redraw()

func _physics_process(delta: float) -> void:
	# HÁLÓZATI JÁTSZMA: a csatlakozó nem szimulál, csak a házigazdától
	# kapott helyre csúsztatja a bábut. Enélkül két külön világ futna.
	if GameState.net_client:
		_net_step(delta)
		return
	if not GameState.on: return
	_fired = maxf(0.0, _fired - delta)
	_tick_buffs(delta)
	_think(delta)
	_move(delta)
	# A gyógyulásjel felszálló mozgásához képkockánként újra kell rajzolni.
	# Csak a nemrég ellátott egységekre vonatkozik, nem az egész pályára.
	if GameState.t - _healed_at < HEAL_FX_TIME + 0.1:
		queue_redraw()
	if sprite.has_method("update_anim"):
		sprite.update_anim(face, walk, velocity.length() > 2.0, _fired > 0.0)

# --- Hálózat ---

# A házigazda pillanatképe: hely, élet, irány és póz.
func net_apply(pos: Vector2, new_hp: float, new_face: float,
		moving: bool, attacking: bool) -> void:
	_net_pos = pos
	_net_have = true
	face = new_face
	_net_moving = moving
	_fired = 0.25 if attacking else 0.0
	if not is_equal_approx(new_hp, hp):
		hp = new_hp
		queue_redraw()

var _net_moving: bool = false

# A csatlakozó bábuja: a kapott hely felé simán csúszik, hogy a
# tíz-hertzes pillanatképből folyamatos mozgás legyen.
func _net_step(delta: float) -> void:
	if not _net_have: return
	var d := _net_pos - global_position
	if d.length() > 260.0:
		global_position = _net_pos          # nagy ugrás: azonnal odarakjuk
	else:
		global_position += d * minf(1.0, delta * 12.0)
	velocity = d / maxf(delta, 0.001)
	if _net_moving: walk += delta * spd * 0.09
	if sprite.has_method("update_anim"):
		sprite.update_anim(face, walk, _net_moving, _fired > 0.0)

# ÚTVONAL ÚJRASZÁMOLÁS CSAK HA KELL.
#
# A NavigationAgent2D minden `target_position` beállításnál új utat számol.
# Az üldöző katona és a gyűjtő munkás eddig KÉPKOCKÁNKÉNT állította be
# ugyanazt a célt — háromszáz egységnél ez volt a legdrágább művelet a
# játékban. Ha a cél alig mozdult, nincs értelme újratervezni.
const NAV_EPS := 26.0

func _set_nav_target(pos: Vector2) -> void:
	if nav.target_position.distance_squared_to(pos) < NAV_EPS * NAV_EPS: return
	nav.target_position = pos

func _move(delta: float) -> void:
	if air:
		_fly(delta)
		return
	if nav.is_navigation_finished():
		velocity = Vector2.ZERO
	else:
		var next := nav.get_next_path_position()
		var dir  := (next - global_position).normalized()
		if dir != Vector2.ZERO:
			face = dir.angle()
		# AZ IDŐJÁRÁS a menetre is hat: a hó és a felázott föld lassít, a
		# szélcsend a vitorlát ejti össze (scripts/systems/Weather.gd).
		var v := spd * _weather_speed() * form_mul("speed") * terep_tempo
		velocity = dir * v
		walk += delta * v * 0.09
	move_and_slide()

# Az időjárás sebesség-szorzója. A Weather csomópont a Main alatt ül; ha
# nincs (pl. oktatómód előtti pillanat), az idő nem számít.
func _weather_speed() -> float:
	var w := _weather()
	var m: float = w.speed_mul(naval) if w != null else 1.0
	# A csatakiáltás gyorsít, a sérült vitorla lassít.
	return m * kialtas_speed_mul() * (sail_mul() if naval else 1.0)

# --- CSATAKIÁLTÁS (index.html 9/E) ---
#
# A HŐS kiálthat: a körülötte állók nyolc másodpercig többet sebeznek és
# gyorsabban mozognak, aki pedig futott, megáll. A hatás a kiáltás
# PILLANATÁBAN közel állókra érvényes — aki később fut oda, lemaradt róla.
const KIALTAS_HATOTAV := 240.0
const KIALTAS_HOSSZ := 8.0
const KIALTAS_VARAKOZAS := 90.0
const KIALTAS_SEBZES := 0.35
const KIALTAS_SEBESSEG := 0.25

var kialtas_el: float = 0.0       # eddig tart rajta a hatás
var kialtas_t: float = 0.0        # a hős újratöltése

# A VITORLA sérülése (0..1): a találat rongálja, és kb. fél perc alatt
# javítják ki. Amíg sérült, a hajó lassabb.
var sail_dmg: float = 0.0

# --- TÖLTETEK  (index.html 09/G) ---
#
# Ugyanabból az ágyúból három félét lehet lőni. A választás a hajóhad
# egészére vonatkozik, és menet közben váltható:
#
#   GOLYÓ   — a hajótestet töri; ezzel lehet elsüllyeszteni
#   LÁNCOS  — az árbocot és a kötélzetet tépi: a testet alig sebzi,
#             viszont a megsérült vitorlázat LASSÍTJA a hajót
#   KARTÁCS — a fedélzeten söpör végig: a testet szinte nem bántja, a
#             partra szálló csapatot viszont sokszorosan fogyasztja
const TOLTETEK := {
	"golyo":   {"test": 1.00, "legeny": 1.0, "vitorla": 0.0},
	"lancos":  {"test": 0.35, "legeny": 0.5, "vitorla": 1.0},
	"kartacs": {"test": 0.25, "legeny": 3.5, "vitorla": 0.0},
}
const TOLTET_SORREND := ["golyo", "lancos", "kartacs"]
# Ágyús hajó: csak ezeknél van értelme a töltetváltásnak.
const AGYUS_HAJOK := ["warship", "galleon"]

static func toltet_of(owner_id: int) -> String:
	var t := str(GameState.get_side(owner_id).get("toltet", "golyo"))
	return t if TOLTETEK.has(t) else "golyo"

func agyus() -> bool:
	return role in AGYUS_HAJOK

# Hány ágyúja van? Ebből lesz a sortűz torkolatainak száma (16/C).
const AGYU_DB := {"transport": 10, "warship": 17, "galleon": 50}

func gun_count() -> int:
	return int(AGYU_DB.get(role, 0))

# A lövedék becsapódása a TÖLTET szerint: mi sérül, a test, a vitorla vagy
# a fedélzeten álló csapat. Szárazföldi célnál a töltet nem számít.
func hit_toltet(amount: float, toltet: String, tamado: Node = null) -> void:
	if not naval:
		take_damage(amount, tamado)
		return
	var t: Dictionary = TOLTETEK.get(toltet, TOLTETEK["golyo"])
	if float(t["vitorla"]) > 0.0:
		sail_dmg = minf(1.0, sail_dmg + float(t["vitorla"]) * 0.09)
	# A kartács a fedélzeten söpör: a szállított csapatot tizedeli. Egy
	# szétlőtt hajóról kevesebben érnek partot.
	var legeny := float(t["legeny"])
	if legeny > 1.0 and not cargo.is_empty():
		for u in cargo.duplicate():
			if is_instance_valid(u): u.take_damage(amount * 0.45 * legeny, tamado)
		_prune_cargo()
	take_damage(amount * float(t["test"]), tamado)

func kialtas_kesz() -> bool:
	return role == "hero" and kialtas_t <= 0.0

# A hős kiált: a közelben állók megkapják a hatást.
func kialtas() -> int:
	if not kialtas_kesz(): return 0
	kialtas_t = KIALTAS_VARAKOZAS
	kialtas_el = KIALTAS_HOSSZ
	var db := 0
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u) or int(u.owner_id) != owner_id: continue
		if u.role == "worker": continue
		if u.global_position.distance_to(global_position) > KIALTAS_HATOTAV: continue
		u.kialtas_el = KIALTAS_HOSSZ
		db += 1
	SFX.play("attack", -2.0)
	return db

func kialtas_dmg_mul() -> float:
	return 1.0 + KIALTAS_SEBZES if kialtas_el > 0.0 else 1.0

func kialtas_speed_mul() -> float:
	return 1.0 + KIALTAS_SEBESSEG if kialtas_el > 0.0 else 1.0

# A sérült vitorla lassít; a legénység menet közben javítja.
func sail_mul() -> float:
	return maxf(0.35, 1.0 - sail_dmg * 0.6) if sail_dmg > 0.0 else 1.0

func _tick_buffs(delta: float) -> void:
	if kialtas_t > 0.0: kialtas_t = maxf(0.0, kialtas_t - delta)
	if kialtas_el > 0.0: kialtas_el = maxf(0.0, kialtas_el - delta)
	if sail_dmg > 0.0: sail_dmg = maxf(0.0, sail_dmg - delta * 0.035)
	_terep_tick(delta)
	_moral_tick(delta)

# --- MORÁL  (index.html 9/E) ---
#
# Egy csapat nem harcol az utolsó emberig. Ha a közelben kétszeres túlerő
# van, és az egység már megsérült, megfutamodik: hat másodpercre kivonja
# magát a harcból, majd összeszedi magát.
#
# A HŐS AURÁJA véd ettől: aki a hős közelében küzd, nem futamodik meg.
# Maga a hős pedig sosem hátrál.
const MORAL_KOZ := 0.7            # ennyinként nézzük meg
const MORAL_SUGAR := 200.0        # ekkora körben számoljuk a túlerőt
const MORAL_TULERO := 2.0         # ennyiszeres ellenfél töri meg
const MORAL_SERULES := 0.6        # eddig az életerőig még kitart
const MORAL_FUTAS := 6.0          # ennyi ideig fut

var _moral_t: float = 0.0

func _moral_tick(delta: float) -> void:
	if role == "worker" or role == "hero" or naval or air: return
	if Combat.can_heal(role): return
	_moral_t -= delta
	if _moral_t > 0.0: return
	_moral_t = MORAL_KOZ
	if GameState.t < _moral_futas_ig: return
	if hp >= max_hp * MORAL_SERULES: return
	if inspired(): return                    # a hős mellett nincs futás
	var baratok := 1.0
	var ellen := 0.0
	var r2 := MORAL_SUGAR * MORAL_SUGAR
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u): continue
		if u.role == "worker" or u.aboard(): continue
		if global_position.distance_squared_to(u.global_position) > r2: continue
		if GameState.hostile(owner_id, int(u.owner_id)): ellen += 1.0
		else: baratok += 1.0
	if ellen >= baratok * MORAL_TULERO and ellen > 0.0:
		_moral_futas_ig = GameState.t + MORAL_FUTAS
		queue_redraw()

# Min áll az egység? A fedezék, a magaslat és a homok hatása.
func _terep_tick(delta: float) -> void:
	if naval or air: return
	_terep_t -= delta
	if _terep_t > 0.0: return
	_terep_t = TEREP_KOZ
	var t := _terrain()
	if t == null: return
	terep_pancel = TEREP_PANCEL if t.in_forest(global_position) else 0.0
	terep_lotav  = TEREP_LOTAV  if t.on_rocks(global_position) else 1.0
	terep_tempo  = TEREP_TEMPO  if t.on_shore(global_position) else 1.0

# A tájat is egyszer keressük meg, mint az időjárást.
static var _terrain_cache: Node = null

func _terrain() -> Node:
	if _terrain_cache != null and is_instance_valid(_terrain_cache):
		return _terrain_cache
	var m := get_tree().get_first_node_in_group("main")
	_terrain_cache = m.terrain if m != null and is_instance_valid(m) else null
	return _terrain_cache

# A csomópontot egyszer keressük meg, és minden egység közösen használja —
# képkockánként több száz keresés fölösleges volna.
static var _weather_cache: Node = null

func _weather() -> Node:
	if _weather_cache != null and is_instance_valid(_weather_cache):
		return _weather_cache
	var m := get_tree().get_first_node_in_group("main")
	_weather_cache = m.weather if m != null and is_instance_valid(m) else null
	return _weather_cache

# A LÁTÓTÁV az időjárással romlik: esőben, ködben és viharban kevesebbet
# látni. A felderítés és a köd is ezt használja, nem a nyers vision_r-t.
func sight() -> float:
	var r := vision_r
	var w := _weather()
	if w != null:
		r *= w.sea_sight_mul() if naval else w.sight_mul()
	# ÉJJEL a fele: ezért van értelme az éjszakai rajtaütésnek.
	var d := _daynight()
	if d != null: r *= d.sight_mul()
	return r

# A nap-éjszaka csomópontot is egyszer keressük meg, mint az időjárást.
static var _daynight_cache: Node = null

func _daynight() -> Node:
	if _daynight_cache != null and is_instance_valid(_daynight_cache):
		return _daynight_cache
	var m := get_tree().get_first_node_in_group("main")
	_daynight_cache = m.day_night if m != null and is_instance_valid(m) else null
	return _daynight_cache

# A repülő nem az úthálózaton megy: egyenesen húz a cél felé, és nem
# ütközik. A `nav.target_position`-t célként ugyanúgy használjuk, mint a
# földi egységeknél — így a parancsok (mozgás, támadás) változatlanok.
func _fly(delta: float) -> void:
	var cel := nav.target_position
	var d := cel - global_position
	if d.length() <= 6.0:
		velocity = Vector2.ZERO
		return
	var dir := d.normalized()
	face = dir.angle()
	velocity = dir * spd
	global_position += velocity * delta
	walk += delta * spd * 0.09

# Egyszerű döntési logika: harc, gyűjtés, különben semmi.
func _think(_delta: float) -> void:
	_swing_t = maxf(0.0, _swing_t - _delta)
	if target != null and not is_instance_valid(target):
		target = null
		atk_timer.stop()
	# A hős a harca MELLETT bátorít is: a körülötte küzdők nagyobbat ütnek
	# és jobban bírják.
	if role == "hero":
		_aura_t -= _delta
		if _aura_t <= 0.0:
			_aura_t = Combat.AURA_PERIOD
			_hero_aura()
	# Csapatszállítás: a beszállás és a kirakodás megelőz minden mást.
	if board_target != null:
		_board_tick()
		return
	if unload_at_pos != Vector2.INF:
		_unload_tick()
		return
	if role == "spy":
		_spy_t -= _delta
		if _spy_t <= 0.0:
			_spy_t = Combat.SPY_CHECK_PERIOD
			_spy_tick()
	# A gyógyítók sosem harcolnak, ezért náluk a harci ág fel sem merül.
	if Combat.can_heal(role):
		_healer_tick(_delta)
		return
	# HARCI ÁLLÁS: aki visszavonul (vagy akinek megtört a morálja), kilép a
	# harcból, és csak akkor fordul vissza, ha összeszedte magát.
	if should_flee():
		_flee_move()
		return
	if target != null:
		var d := global_position.distance_to(target.global_position)
		if d > _effective_range(target):
			# "Tartsd a vonalat": nem üldözünk, elengedjük a célt.
			if stance == STANCE_HOLD:
				target = null
				if not atk_timer.is_stopped(): atk_timer.stop()
				return
			_set_nav_target(target.global_position)
			if not atk_timer.is_stopped(): atk_timer.stop()
		else:
			nav.target_position = global_position
			face = (target.global_position - global_position).angle()
			if atk_timer.is_stopped(): atk_timer.start()
		return
	if role == "worker" or role == "fisher":
		if build_target != null:
			_build_tick()
		elif auto_gather:
			_gather_tick(_delta)
		return
	# ELLENSÉGKERESÉS RITKÁBBAN.
	#
	# A keresés végigjárja az összes egységet és épületet. Ha ezt minden
	# egység MINDEN képkockán megteszi, kétszáz katonánál már negyvenezer
	# távolságszámítás jut egy képkockára — ettől akadt meg a játék a
	# gyengébb gépeken. Másodpercenként két-három keresés bőven elég: az
	# ellenség nem tűnik el két tizedmásodperc alatt. A kezdőértéket
	# szétszórjuk, hogy ne egyszerre keressen mindenki.
	if dmg > 0.0:
		_scan_t -= _delta
		if _scan_t <= 0.0:
			_scan_t = SCAN_PERIOD
			# "Tartsd a vonalat" állásban csak arra lövünk, ami hatótávba ér.
			var kereses: float = sight() if stance != STANCE_HOLD \
				else atk_range * form_mul("range") + radius + 18.0
			var e := Combat.find_enemy(self, kereses)
			if e != null: start_attacking(e)

# AZ ŐRTORONY LEPLEZI LE A KÉMET. Amíg nincs ellenséges torony a közelben,
# az álruha tart, és nem lőnek rá. A torony látókörébe érve viszont
# felismerik — és onnantól egy ideig célpont marad, akkor is, ha kilép a
# torony alól.
func _spy_tick() -> void:
	if GameState.t < _exposed_until: return
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.tipus != "tower" or not b.is_ready(): continue
		if not GameState.hostile(owner_id, int(b.owner_id)): continue
		var st: Dictionary = Building.BUILD_STATS["tower"]
		var rng: float = float(st["range"][clampi(int(b.age), 0, 3)]) \
			* Upgrades.vision_mul(int(b.owner_id))
		if global_position.distance_to(b.global_position) > rng: continue
		_exposed_until = GameState.t + Combat.SPY_EXPOSE_HOLD
		queue_redraw()
		# Csak arról szólunk, ami a játékost érinti.
		var main := get_tree().get_first_node_in_group("main")
		if main != null and main.hud != null:
			if owner_id == GameState.en_id:
				main.hud.show_toast(Lang.t("uz_kem_leleplezve"))
			elif int(b.owner_id) == GameState.en_id:
				main.hud.show_toast(Lang.t("uz_torony_kemet_fogott"))
		return

# A hős bátorítása. A HŐS osztja szét, nem az egységek keresgélik: így egy
# hős jár körbe, nem kétszáz katona kérdezgeti minden ütésnél, van-e hős a
# közelben. A jelölés rövid ideig él, ezért ha a hős elesik vagy továbbmegy,
# a bónusz magától elmúlik.
func _hero_aura() -> void:
	var r := Combat.AURA_RANGE
	var ig := GameState.t + Combat.AURA_HOLD
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or int(u.owner_id) != owner_id: continue
		if absf(u.global_position.x - global_position.x) > r: continue
		if absf(u.global_position.y - global_position.y) > r: continue
		u._aura_until = ig

# --- Gyógyítók: a pap és a felcser ---
#
# Egyik sem üt. A PAP körül magától felépülnek a sajátjai, és parancsra
# átállítja az ellenség katonáit; a FELCSER egyesével keresi meg a
# legsúlyosabb sebesültet, odamegy hozzá, és sokkal gyorsabban dolgozik.
func _healer_tick(delta: float) -> void:
	if role == "priest":
		_aura_heal(delta)
		_convert_tick(delta)
	else:
		_medic_tick(delta)

# A pap körüli gyógyulás. A FRISS sebet nem kötözi be: aki három
# másodpercen belül találatot kapott, még a tűzvonalban áll. Enélkül a
# harcoló csapat életereje folyamatosan visszatöltődne, és a csata sosem
# dőlne el.
func _aura_heal(delta: float) -> void:
	var r := Combat.heal_range_for(role)
	var ero := Combat.heal_for(role, age) * delta * Upgrades.heal_mul(owner_id)
	if ero <= 0.0: return
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or int(u.owner_id) != owner_id: continue
		if u.hp >= u.max_hp or u.in_combat(): continue
		# Olcsó doboz-szűrés előbb, ahogy az ellenségkeresésnél is.
		if absf(u.global_position.x - global_position.x) > r: continue
		if absf(u.global_position.y - global_position.y) > r: continue
		u.heal(ero)

# A felcser munkája. A súlyosabb sebesült előbbre való, de a távolság is
# számít — a fél pálya túloldalán haldoklóhoz nincs értelme elindulni.
func _medic_tick(delta: float) -> void:
	var r := Combat.heal_range_for(role)
	var cel := _find_wounded(r + Combat.MEDIC_SEARCH)
	_heal_target = cel
	if cel == null: return
	if global_position.distance_to(cel.global_position) > r:
		# Csak akkor indul el magától, ha nincs jobb dolga: a játékos által
		# odaküldött sebész nem szalad el egy karcolás miatt.
		if nav.is_navigation_finished():
			_set_nav_target(cel.global_position)
		return
	nav.target_position = global_position
	face = (cel.global_position - global_position).angle()
	cel.heal(Combat.heal_for(role, age) * delta * Upgrades.heal_mul(owner_id))

func _find_wounded(radius: float) -> Node2D:
	var best: Node2D = null
	var best_w := INF
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or int(u.owner_id) != owner_id: continue
		if u.hp >= u.max_hp - 0.5: continue
		var d := global_position.distance_to(u.global_position)
		if d > radius: continue
		# A súly a hiányzó életerő arányában húzza előre a célpontot.
		var w: float = d * (0.4 + 0.6 * (u.hp / maxf(u.max_hp, 1.0)))
		if w < best_w:
			best_w = w
			best = u
	return best

# --- Térítés ---
#
# A pap nem lelövi az ellenséget, hanem átbeszéli a saját oldalára. Ehhez
# egyhuzamban rajta kell tartania a szót; ha közben elszakad tőle, a
# megkezdett munka visszapereg.
func _convert_tick(delta: float) -> void:
	# A gépi oldal papjai maguktól keresnek célpontot.
	if convert_target == null and owner_id != GameState.en_id:
		convert_target = _find_convertible(atk_range * 2.0)
	if not Unit.convertible(convert_target) \
			or int(convert_target.owner_id) == owner_id:
		if convert_target != null:
			convert_target = null
			queue_redraw()
		# A félbehagyott térítés kétszeres tempóban felejtődik el.
		if _chan > 0.0:
			_chan = maxf(0.0, _chan - delta * 2.0)
		return
	var t: Node2D = convert_target
	if global_position.distance_to(t.global_position) > atk_range:
		_chan = maxf(0.0, _chan - delta)
		_set_nav_target(t.global_position)
		return
	nav.target_position = global_position
	face = (t.global_position - global_position).angle()
	_chan += delta * (Combat.CONVERT_RESIST if _sheltered(t) else 1.0)
	queue_redraw()
	if _chan >= Combat.convert_time_for(age):
		var regi := int(t.owner_id)
		t.convert_to(owner_id)
		_chan = 0.0
		convert_target = null
		_announce_convert(t, regi)

func _find_convertible(radius: float) -> Node2D:
	var best: Node2D = null
	var best_d := radius * radius
	for u in get_tree().get_nodes_in_group("units"):
		if not GameState.hostile(owner_id, int(u.owner_id)): continue
		if not Unit.convertible(u): continue
		var d := global_position.distance_squared_to(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	return best

# A saját bázisuk közelében nehezebb meggyőzni az embereket: a főépület,
# a laktanya és az őrtorony a sajátjaira ad ilyen menedéket.
func _sheltered(t: Node2D) -> bool:
	var r2 := Combat.CONVERT_SHELTER_R * Combat.CONVERT_SHELTER_R
	for b in get_tree().get_nodes_in_group("buildings"):
		if int(b.owner_id) != int(t.owner_id): continue
		if not Building.SHELTER.has(b.tipus): continue
		if not b.is_ready(): continue
		if b.global_position.distance_squared_to(t.global_position) < r2:
			return true
	return false

# Csak arról szólunk, ami a JÁTÉKOST érinti: vagy ő nyert egy katonát,
# vagy elvesztett egyet. Két bot egymás közti térítése nem üzenet.
func _announce_convert(t: Node2D, regi_gazda: int) -> void:
	var main := get_tree().get_first_node_in_group("main")
	if main == null or main.hud == null: return
	var nev: String = main.hud.unit_name(str(t.role))
	if owner_id == GameState.en_id:
		main.hud.show_toast(Lang.t("uz_atallt") % nev)
	elif regi_gazda == GameState.en_id:
		main.hud.show_toast(Lang.t("uz_atallitotta") % nev)

# --- Építés ---
#
# Az épület csak akkor halad, ha munkás áll mellette (lásd Building._process).
# A munkás odamegy, és amíg ott dolgozik, jár a szerszám animációja.
func _build_tick() -> void:
	if not is_instance_valid(build_target) or build_target.is_ready():
		build_target = null
		return
	var reach: float = build_target.hit_radius() + radius + 26.0
	if global_position.distance_to(build_target.global_position) > reach:
		_set_nav_target(build_target.global_position)
	else:
		nav.target_position = global_position
		face = (build_target.global_position - global_position).angle()
		_fired = 0.2

# --- Nyersanyag gyűjtés (worker / fisher) ---

# A munkás ciklusa: odamegy a lelőhelyhez, RÁÜT tizenötször (közben jár a
# szerszám animációja), és a megtelt rakománnyal indul vissza a bázisra.
# Ha közben kifogy a lelőhely, azzal megy vissza, amennyi összejött.
# Mennyi fér egy fordulóba. A Raktározás növeli: ugyanannyi gyaloglásból
# több nyersanyag jön, mert ritkábban kell visszamenni.
func load_cap() -> float:
	return ResourceSystem.LOAD_AMOUNT * Upgrades.carry_mul(owner_id)

# Hány ütés fér egy fordulóba. A nagyobb puttonyt TÖBB ütéssel töltjük meg,
# nem gyorsabbal — a nyeresége a ritkább visszaút, nem a szaporább csapás.
func swings_per_load() -> int:
	return int(ceil(ResourceSystem.SWINGS_PER_LOAD * Upgrades.carry_mul(owner_id)))

func _gather_tick(delta: float) -> void:
	# 1. Teli rakománnyal a leadóhelyre.
	if _carry >= load_cap() or _hauling:
		_hauling = true
		if _drop_node == null or not is_instance_valid(_drop_node):
			_drop_node = ResourceSystem.find_dropoff(self)
		if _drop_node == null: return
		_set_nav_target(_drop_node.global_position)
		if global_position.distance_to(_drop_node.global_position) < 70.0:
			GameState.add_res(owner_id, _carry_kind, _carry)
			_carry = 0.0
			_swings = 0
			_hauling = false
			queue_redraw()      # a rakomány-címke eltűnik
			# A kimerült lelőhely helyett újat keres a következő fordulóra.
			if not is_instance_valid(_gather_node):
				_gather_node = null
		return
	# 2. Lelőhely keresése.
	if _gather_node == null or not is_instance_valid(_gather_node):
		_gather_node = ResourceSystem.find_node_for(self)
		if _gather_node == null:
			# Nincs több lelőhely: ami a kezében van, azt még leadja.
			if _carry > 0.0: _hauling = true
			return
	# 3. Odamegy, és üt.
	_set_nav_target(_gather_node.global_position)
	# A lelőhely mérete változó, ezért a hatótávot a sugarához mérjük.
	if global_position.distance_to(_gather_node.global_position) \
			>= _gather_node.radius + radius + 12.0:
		return
	nav.target_position = global_position
	face = (_gather_node.global_position - global_position).angle()
	if _swing_t > 0.0: return
	_swing_t = ResourceSystem.SWING_TIME
	_fired = ResourceSystem.SWING_TIME * 0.7      # a szerszám lendül
	_carry_kind = ResourceSystem.yield_kind(_gather_node.kind)
	# A Gazdálkodás-fokozat ugyanabból az ütésből többet hoz ki. A lelőhely
	# viszont csak annyit ad, amennyi benne van — a szorzót ezért a KIVETT
	# mennyiségre tesszük, nem a kérésre.
	var got: float = _gather_node.harvest(ResourceSystem.PER_SWING)
	_carry += got * Upgrades.gather_mul(owner_id)
	_swings += 1
	queue_redraw()              # a rakomány-címke nő
	# Tizenöt ütés után — vagy ha a lelőhely kifogyott — indul vissza.
	if _swings >= swings_per_load() \
			or _carry >= load_cap() \
			or got <= 0.0:
		if _carry > 0.0: _hauling = true

# --- Parancsok ---

func move_to(pos: Vector2) -> void:
	nav.target_position = pos
	target = null
	board_target = null
	unload_at_pos = Vector2.INF
	convert_target = null
	_chan = 0.0
	_gather_node = null
	build_target = null
	auto_gather = false
	if not atk_timer.is_stopped(): atk_timer.stop()

# Egy konkrét lelőhelyre küldött munkás újra automatikusan dolgozik.
func gather_at(node: Node2D) -> void:
	if node == null or not is_instance_valid(node): return
	target = null
	build_target = null
	auto_gather = true
	gather_pref = str(node.kind)
	_gather_node = node
	# Új parancs = új forduló: az ütésszámláló nullázódik.
	_swings = 0
	_swing_t = 0.0
	_hauling = false
	nav.target_position = node.global_position
	if not atk_timer.is_stopped(): atk_timer.stop()

func start_attacking(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy): return
	# A PAPNAK ugyanez a parancs térítést jelent: nem üt, hanem átbeszél.
	# Így a jobb gomb mindenkinél ugyanaz marad, és a parancs hálózaton is
	# változatlanul utazik.
	if role == "priest":
		convert_target = enemy as Node2D if Unit.convertible(enemy) else null
		_chan = 0.0
		queue_redraw()
		return
	if role == "medic": return           # a felcser nem harcol
	target = enemy as Node2D
	_gather_node = null
	build_target = null
	auto_gather = false
	if atk_timer.is_stopped(): atk_timer.start()

# Építési parancs: a munkás odamegy és felhúzza az épületet.
func build_at(b: Node2D) -> void:
	if b == null or not is_instance_valid(b): return
	target = null
	_gather_node = null
	auto_gather = false
	build_target = b
	nav.target_position = b.global_position

func stop() -> void:
	nav.target_position = global_position
	velocity = Vector2.ZERO
	target = null
	board_target = null
	unload_at_pos = Vector2.INF
	convert_target = null
	_chan = 0.0
	_gather_node = null
	build_target = null
	auto_gather = false
	if not atk_timer.is_stopped(): atk_timer.stop()

# Távolsági egységek lövedéket indítanak, a többi közvetlenül sebez.
const PROJECTILE_ROLES := ["ranged", "siege", "warship", "galleon", "tower"]

func _on_attack() -> void:
	if not is_instance_valid(target):
		atk_timer.stop(); target = null; return
	if global_position.distance_to(target.global_position) > _effective_range(target) * 1.25:
		# elszakadt: közeledjünk újra, ne sebezzünk távolról
		nav.target_position = target.global_position
		return
	if not target.has_method("take_damage"): return
	_fired = 0.25
	SFX.play(Combat.sound_for(role, age), -6.0)
	var amount := dmg * Combat.damage_mult(role, _target_kind(target))
	if inspired(): amount *= 1.0 + Combat.AURA_DAMAGE
	# A csatakiáltás hatása alatt nagyobbat üt a csapat.
	amount *= kialtas_dmg_mul()
	if role in PROJECTILE_ROLES:
		var main := get_tree().get_first_node_in_group("main")
		if main and main.has_method("spawn_projectile"):
			# Az ágyús hajó a HAJÓHAD töltetével lő (golyó/láncos/kartács),
			# és nem egyetlen villanással: az egész oldal dörren (16/C).
			if naval and gun_count() > 0 and main.broadside != null \
					and is_instance_valid(main.broadside):
				main.broadside.fire(self, target)
			main.spawn_projectile(global_position + Vector2(0, -12), target,
				amount, owner_id, self, toltet_of(owner_id) if agyus() else "")
			return
	target.take_damage(amount, self)

func _target_kind(t: Node) -> String:
	if t is Building: return "building"
	return str(t.role) if "role" in t else ""

# A hatótáv a két test szélei között értendő, különben a közelharci
# egységek sosem érnek egymáshoz (a kikerülés távol tartja őket).
func _effective_range(t: Node2D) -> float:
	var tr := 0.0
	if t is Building:
		tr = t.hit_radius()
	elif "radius" in t:
		tr = float(t.radius)
	# A VONAL alakzatban a lövész messzebbre lő, a sziklás magaslatról is.
	return atk_range * form_mul("range") * terep_lotav + radius + tr

# A `tamado` azért kell, hogy az ölést jóvá lehessen írni: abból lesz a
# veterán fokozat (index.html: creditKill).
func take_damage(amount: float, tamado: Node = null) -> void:
	# A páncél levon a találatból, de sosem nyeli el egészen: enélkül a
	# késői páncél ellen a korai gyalogos ártalmatlan lenne, és a játszma
	# menthetetlenül elakadna. A hős közelében állók egy kicsivel többet
	# bírnak ki.
	# A páncélhoz hozzáadódik a FEDEZÉK is: fák között nehezebb eltalálni.
	var ved := armor + terep_pancel + (Combat.AURA_ARMOR if inspired() else 0.0)
	hp -= maxf(Upgrades.MIN_DAMAGE, amount - ved)
	# A VITORLÁT a LÁNCOS golyó tépi (lásd hit_toltet) — a sima találat a
	# testet bontja. Az eredetiben is így van: a sailDmg csak a töltetből
	# jön, különben minden lövés egyformán lassítana.
	_hit_at = GameState.t
	queue_redraw()
	if hp <= 0.0:
		# Az ölés azé, aki elejtette — ebből gyűlik a veteránság.
		if tamado != null and is_instance_valid(tamado) and tamado is Unit \
				and int(tamado.owner_id) != owner_id:
			tamado.credit_kill()
		# A hajóval együtt a rakománya is odavész.
		if not cargo.is_empty():
			for u in cargo:
				if is_instance_valid(u): u.queue_free()
			cargo.clear()
		SFX.play_death()
		# A FÖLD EMLÉKSZIK: ahol elesett valaki, ott marad a nyoma
		# (elhagyott fegyver, felperzselt fű) — lásd Scars.gd.
		var fo2 := get_tree().get_first_node_in_group("main")
		if fo2 != null and fo2.scars != null and is_instance_valid(fo2.scars):
			fo2.scars.add_scar(global_position,
				"fegyver" if randf() < 0.55 else "eges")
		# Az elesett a földre dől, vértócsa marad utána (az eredeti
		# dropCorpse-a; a hajó és a gép nem hagy holttestet).
		if not naval and not air and Settings.lively():
			Holttest.ejt(self, role, age, owner_id, face, radius)
		# A kalózvilágban a zsákmány hírnevet hoz: a hajó többet ér.
		if GameState.hostile(GameState.en_id, owner_id):
			GameState.kills += 1
			Achievements.bump("kills")
			GameState.add_fame(6.0 if naval else 1.2)
			# A SEMLEGES KERESKEDŐHAJÓ rakománya azé, aki elsüllyesztette.
			if get_meta("merchant", false):
				var fo: Node = get_tree().get_first_node_in_group("main")
				if fo != null and fo.events != null:
					fo.events.merchant_loot(self, GameState.en_id)
		queue_free()

func heal(amount: float) -> void:
	if amount <= 0.0 or hp >= max_hp: return
	hp = minf(max_hp, hp + amount)
	_healed_at = GameState.t
	queue_redraw()

# Nemrég találat érte? A pap aurája nem fog azon, aki még a tűzvonalban áll.
func in_combat() -> bool:
	return GameState.t - _hit_at <= Combat.HEAL_COMBAT_DELAY

# Kit lehet meggyőzni? A huszadik századi páncélos legénysége zárt torony
# mögött ül — hozzájuk nem jut el a szó.
static func convertible(t: Node) -> bool:
	if t == null or not is_instance_valid(t) or not (t is Unit): return false
	return not (t.role == "melee" and t.age >= 3)

# ÁTÁLLÁS. Az egység új gazdát kap. Újra kell számolni mindent, amit a
# gazda határoz meg: a csapatszámot, a színeket, a csoporttagságot — és a
# statisztikákat is, mert az új gazda fejlesztései másképp szoroznak.
# Az életerőt ARÁNYOSAN visszük át, hogy a fejlettebb oldalra átállt
# sebesült ne gyógyuljon meg a puszta átállástól.
func convert_to(new_owner: int) -> void:
	if new_owner == owner_id: return
	owner_id = new_owner
	refresh_stats()
	team        = GameState.team_of(owner_id)
	team_color  = Style.side_color(owner_id)
	team_accent = Style.side_accent(owner_id)
	remove_from_group("player_units")
	remove_from_group("enemy_units")
	if owner_id == GameState.en_id:
		add_to_group("player_units")
		auto_gather = false
	else:
		add_to_group("enemy_units")
		auto_gather = role in ["worker", "fisher"]
	# Minden korábbi szándék elévül: az új gazdának nem parancsolt semmit.
	target = null
	convert_target = null
	_heal_target = null
	_gather_node = null
	build_target = null
	_chan = 0.0
	set_selected(false)
	if not atk_timer.is_stopped(): atk_timer.stop()
	nav.target_position = global_position
	if sprite.has_method("setup"):
		sprite.setup(role, age, owner_id)
	SFX.play("age", -14.0)
	queue_redraw()

func set_selected(val: bool) -> void:
	_sel = val
	queue_redraw()

func is_selected() -> bool:
	return _sel

# A kijelölési panel innen olvassa ki, mi van a munkásnál.
func carry_amount() -> float:
	return _carry

func carry_kind() -> String:
	return _carry_kind

# Melyik lelőhelyen dolgozik éppen (a lelőhely innen számolja a munkásait).
func gather_node() -> Node2D:
	return _gather_node if is_instance_valid(_gather_node) else null
