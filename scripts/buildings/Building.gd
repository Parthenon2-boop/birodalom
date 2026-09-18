class_name Building
extends StaticBody2D

@export var tipus    : String = "hq"
@export var owner_id : int    = 0
@export var age      : int    = 0

const BUILD_STATS := {
	"hq":       {"hp": [1600, 1950, 2400, 2900], "trains": ["worker"], "drop": true},
	"barracks": {"hp": [820, 980, 1180, 1450],   "trains": ["melee", "ranged", "spear", "hero"]},
	"stable":   {"hp": [620, 720, 860, 1050],    "trains": ["cav"]},
	"farm":     {"hp": [300, 340, 400, 470],     "food": [0.85, 1.05, 1.35, 1.75]},
	"tower":    {"hp": [540, 680, 850, 1050],    "dmg": [14, 20, 27, 28], "range": [155, 180, 205, 200]},
	"house":    {"hp": [320, 420, 520, 700],     "pop": 5, "max": 10},
	"harbor":   {"hp": [540, 660, 800, 960],     "trains": ["fisher", "warship", "galleon", "transport"], "shore": true, "drop": true},
	"temple":   {"hp": [560, 690, 830, 990],     "trains": ["priest"]},
	"goldmine": {"hp": [420, 520, 640, 780],     "gold": 0.8},
	"airfield": {"hp": [1, 1, 1, 1150],          "trains": ["fighter", "bomber"], "minAge": 3},
	# Cukornád-ültetvény: ebből lesz a rum, a kalózok fizetsége. A magyar
	# alföldön semmi keresnivalója, ezért csak a kalózvilágban építhető.
	"sugar":    {"hp": [380, 470, 580, 700],     "rum": 0.9, "pirateOnly": true},
	# Piac: a kereskedő álruhája a legrégibb fedősztori — itt toborozható
	# a kém. (A nyersanyagcsere még nincs meg, az a piac másik fele.)
	"market":   {"hp": [480, 600, 740, 900],     "trains": ["spy"]},
	# Ispotály: a köré gyűlt sebesülteket magától talpra állítja, és itt
	# képezhető a tábori sebész, aki a fronton gyógyít.
	"hospital": {"hp": [520, 660, 820, 1000],    "trains": ["medic"],
				 "heal": [2.2, 2.8, 3.4, 4.2], "healR": 150.0},
	# Kovácsműhely: itt erősítjük a katonát — fegyver, páncél, ellátmány —,
	# és innen kerülnek ki az ostromszerszámok is.
	"smith":    {"hp": [560, 700, 860, 1040],    "trains": ["siege", "ram"]},
	# Akadémia: a birodalom működését javító kutatások háza. Nem képez
	# egységet: itt nem katonát csinálnak, hanem döntést hoznak.
	"academy":  {"hp": [620, 760, 920, 1100]},
}

# A méretek az EGYSÉG magasságához igazodnak (UnitSprite.TARGET_H = 46 px):
# egy ház nagyjából másfélszer, egy laktanya kétszer, a főváros közel
# háromszor akkora, mint egy katona — ez a szokásos RTS-arány.
const BUILD_SIZE := {
	"hq":       Vector2(108, 106),
	"barracks": Vector2(86, 82),
	"stable":   Vector2(82, 70),
	"farm":     Vector2(66, 62),
	"tower":    Vector2(54, 52),
	"house":    Vector2(66, 52),
	"harbor":   Vector2(86, 62),
	"temple":   Vector2(78, 68),
	"airfield": Vector2(112, 78),
	"goldmine": Vector2(70, 58),
	"sugar":    Vector2(74, 60),
	"market":   Vector2(80, 62),
	"hospital": Vector2(78, 64),
	"smith":    Vector2(74, 62),
	"academy":  Vector2(86, 72),
}

# Látszólagos magasság korszakonként (az eredeti BH táblája). A lábnyom
# csak a talpát adja meg; a sprite ennyivel nyúlik fölé.
const BUILD_HEIGHT := {
	"hq":       [64, 58, 62, 44],
	"barracks": [42, 40, 44, 38],
	"stable":   [36, 34, 38, 34],
	"farm":     [16, 18, 18, 16],
	"temple":   [58, 62, 56, 46],
	"harbor":   [40, 44, 46, 38],
	"airfield": [10, 10, 10, 26],
	"house":    [38, 40, 42, 38],
	"goldmine": [30, 32, 34, 32],
	"tower":    [72, 60, 68, 56],
	"sugar":    [18, 20, 20, 18],
	# A piac nyitott csarnok: alacsonyabb, mint a laktanya. Az ispotály
	# emeletes, a kovácsműhely zömök, de magas kéménnyel.
	"market":   [34, 36, 38, 34],
	"hospital": [46, 48, 50, 44],
	"smith":    [38, 40, 44, 40],
	# Az akadémia a templom után a legtekintélyesebb ház a bázison.
	"academy":  [54, 58, 60, 50],
}

static func height_of(t: String, age: int) -> float:
	var v: Array = BUILD_HEIGHT.get(t, [28, 28, 28, 28])
	return float(v[clampi(age, 0, 3)])

static func size_of(t: String) -> Vector2:
	return BUILD_SIZE.get(t, Vector2(64, 64))

# --- Anyagminták ---
#
# Az assets/sprites/buildings lapok NEM kész épületek, hanem LPC
# elemtárak: fal-, tető- és ablakdarabok egy 128x128 lapon. Egészben
# kirajzolva értelmetlen foltot adnak, ezért innen csak TEXTÚRÁT veszünk:
# minden bejegyzés egy lap + egy tiszta, ismételhető részlet.
const TEX_LIB := {
	"cream":     ["hq_1",       Rect2(2, 98, 44, 28)],
	"stone":     ["barracks_1", Rect2(0, 0, 58, 30)],
	"brick":     ["house_1",    Rect2(0, 0, 54, 50)],
	# A kivágásoknak TÖMÖRNEK kell lenniük: ahol a forráskép átlátszó,
	# ott a fal foltokban tűnt el. Ezeket lemértük és kicseréltük.
	"planks":    ["harbor_1",   Rect2(68, 4, 40, 72)],
	"shingle":   ["hq_1",       Rect2(56, 12, 40, 26)],
	"slate":     ["barracks_1", Rect2(76, 106, 40, 20)],
	"blue":      ["barracks_2", Rect2(2, 2, 52, 34)],
	"blueroof":  ["barracks_2", Rect2(80, 72, 36, 28)],
	"paleblue":  ["house_2",    Rect2(0, 2, 56, 26)],
	"green":     ["tower_2",    Rect2(8, 40, 28, 18)],
	"creamroof": ["market_2",   Rect2(0, 0, 30, 24)],
	"darkred":   ["market_2",   Rect2(0, 98, 60, 28)],
	"darkroof":  ["market_1",   Rect2(0, 86, 30, 26)],
}

# típus -> [fal, tető] korszakcsoportonként:
#   0 = 15-17. század  fa, kő, zsindely
#   1 = 19. század     tégla és pala — az ipari forradalom városa; NEM a
#                      20. század hidegkék betonja
#   2 = 20. század     modern, hűvös falak és lapos, sötét tetők
const MATERIALS := {
	"hq":       [["cream", "shingle"],  ["brick", "slate"],   ["paleblue", "blueroof"]],
	"barracks": [["stone", "slate"],    ["brick", "darkroof"], ["blue", "blueroof"]],
	"stable":   [["planks", "shingle"], ["brick", "shingle"], ["darkred", "creamroof"]],
	"farm":     [["planks", "shingle"], ["planks", "shingle"], ["darkred", "creamroof"]],
	"house":    [["brick", "shingle"],  ["brick", "slate"],   ["paleblue", "creamroof"]],
	"tower":    [["stone", "slate"],    ["stone", "darkroof"], ["green", "darkroof"]],
	"temple":   [["cream", "slate"],    ["cream", "darkroof"], ["paleblue", "darkroof"]],
	"harbor":   [["planks", "shingle"], ["planks", "slate"],  ["planks", "blueroof"]],
	"goldmine": [["stone", "slate"],    ["brick", "darkroof"], ["darkred", "darkroof"]],
	"airfield": [["stone", "slate"],    ["stone", "slate"],   ["paleblue", "darkroof"]],
	"sugar":    [["planks", "shingle"], ["planks", "shingle"], ["planks", "shingle"]],
	"market":   [["planks", "creamroof"], ["brick", "creamroof"], ["darkred", "creamroof"]],
	"hospital": [["cream", "shingle"],  ["cream", "slate"],   ["paleblue", "slate"]],
	"smith":    [["stone", "darkroof"], ["brick", "darkroof"], ["blue", "darkroof"]],
	"academy":  [["cream", "slate"],   ["cream", "shingle"], ["paleblue", "blueroof"]],
}

# Melyik anyagcsoport tartozik a korszakhoz.
static func era_group(a: int) -> int:
	if a <= 1: return 0
	return 1 if a == 2 else 2

# Ezeknek nincs teteje: föld- illetve betonfelület, saját mintázattal.
const FLAT_TYPES := ["farm", "airfield", "sugar"]

const BUILD_COLOR := {
	"hq":       Color(0.62, 0.52, 0.36),
	"barracks": Color(0.55, 0.36, 0.28),
	"stable":   Color(0.48, 0.38, 0.26),
	"farm":     Color(0.72, 0.64, 0.30),
	"tower":    Color(0.52, 0.52, 0.56),
	"house":    Color(0.66, 0.56, 0.44),
	"harbor":   Color(0.38, 0.46, 0.58),
	"temple":   Color(0.72, 0.70, 0.62),
	"goldmine": Color(0.60, 0.52, 0.24),
	"airfield": Color(0.44, 0.46, 0.44),
	"sugar":    Color(0.68, 0.72, 0.34),
	"market":   Color(0.70, 0.58, 0.34),
	"hospital": Color(0.80, 0.78, 0.74),
	"smith":    Color(0.44, 0.42, 0.44),
	"academy":  Color(0.76, 0.74, 0.66),
}

# A hálózati pillanatképben az épülettípus SORSZÁMKÉNT utazik. A sorrend
# NEM változtatható és nem rendezhető át: az új típusok a VÉGÉRE kerülnek,
# különben a régi mentések és a társ gépe másik épületet olvasna ki.
const TIPUS_ORDER := ["hq", "barracks", "stable", "farm", "tower", "house",
	"harbor", "temple", "goldmine", "airfield", "sugar",
	"market", "hospital", "smith", "academy"]

# MENEDÉK. Aki a saját főépülete, laktanyája vagy őrtornya közelében áll,
# nehezebben téríthető át: ott a tisztjei és a bajtársai is ott vannak.
# (Lásd Unit._sheltered és Combat.CONVERT_RESIST.)
const SHELTER := {"hq": true, "barracks": true, "tower": true}

# Hálózati azonosító — a házigazda osztja.
var nid: int = 0

const TRAIN_TIME := {
	"worker": 8.0, "melee": 8.0, "ranged": 10.0, "spear": 9.0, "cav": 14.0,
	"priest": 16.0, "hero": 20.0, "fisher": 20.0, "warship": 30.0,
	"galleon": 40.0, "transport": 25.0, "fighter": 14.0, "bomber": 18.0,
	# Kém, felcser, ostromgép, faltörő kos: statisztikájuk rég megvolt,
	# csak épp egyetlen épület sem képezte ki őket. Az idők az eredetiből.
	"spy": 14.0, "medic": 10.0, "siege": 20.0, "ram": 22.0,
}

const TRAIN_COST := {
	"worker":    {"wood": 30, "food": 40},
	"melee":     {"wood": 50, "food": 30},
	"ranged":    {"wood": 40, "stone": 20, "food": 25},
	"spear":     {"wood": 45, "food": 28},
	"cav":       {"wood": 80, "food": 60, "gold": 20},
	"priest":    {"wood": 60, "gold": 80, "food": 30},
	"hero":      {"wood": 120, "gold": 150, "food": 80},
	"fisher":    {"wood": 90, "stone": 30},
	"warship":   {"wood": 200, "stone": 80, "gold": 60},
	"galleon":   {"wood": 320, "stone": 130, "gold": 100},
	"transport": {"wood": 150, "stone": 60},
	"fighter":   {"gold": 120, "wood": 90, "coal": 40},
	"bomber":    {"gold": 180, "wood": 140, "coal": 60},
	"spy":       {"gold": 120, "food": 40},
	"medic":     {"food": 60, "gold": 40},
	"siege":     {"wood": 140, "gold": 90},
	"ram":       {"wood": 170, "gold": 60},
}

var hp           : float = 1000.0
var max_hp       : float = 1000.0
var train_queue  : Array = []

var _size        : Vector2 = Vector2(64, 64)
var _height      : float   = 30.0
var _color       : Color   = Color(0.6, 0.5, 0.4)
var _tower_cd    : float   = 0.0
var _wall_tex    : Texture2D = null
var _wall_src    : Rect2     = Rect2()
var _roof_tex    : Texture2D = null
var _roof_src    : Rect2     = Rect2()
var _flag_tex    : Texture2D = null
var team_color   : Color   = Color.WHITE
var team_accent  : Color   = Color.WHITE
# Csapatszám az épületen — az ellenségkeresés ezt olvassa (lásd Combat).
var team         : int     = 0

# Építkezés: 0..1. A játék elején letett bázisok készen állnak.
var prog         : float   = 1.0
var build_time   : float   = 12.0
# A kikötőmenüből rendelt épületet a város NÉPE húzza fel: nem kell hozzá
# odaküldeni munkást (index.html: b.remote). Enélkül a kalózvilágban sosem
# készülne el semmi, hiszen ott nincs munkásod.
var maga_epul    : bool    = false
var _selected    : bool    = false
# Gyülekezőpont: a frissen kiképzett egységek ide indulnak. Ha a játékos
# nyersanyagra vagy ellenségre tette, a parancs is átszáll az új egységre.
var rally_set    : bool    = false
var rally_node   : Node2D  = null
var rally_foe    : Node    = null
# Kéményfüst: az eltelt idő és a következő újrarajzolásig hátralévő idő.
var _smoke_t      : float  = 0.0
var _smoke_redraw : float  = 0.0

@onready var sprite   := $Sprite2D as Sprite2D
@onready var col      := $CollisionShape2D as CollisionShape2D
@onready var hp_bar   := $HPBar/ProgressBar as ProgressBar
@onready var prod_tmr := $ProductionTimer as Timer
@onready var rally    := $RallyPoint as Marker2D

func _ready() -> void:
	max_hp = _base_hp() * Upgrades.building_hp_mul(owner_id)
	hp = max_hp
	# Az életsávot és az épületet magunk rajzoljuk (_draw), mint az eredeti.
	hp_bar.visible = false
	team        = GameState.team_of(owner_id)
	team_color  = Style.side_color(owner_id)
	team_accent = Style.side_accent(owner_id)

	_size   = BUILD_SIZE.get(tipus, Vector2(64, 64))
	_height = height_of(tipus, age)
	_color  = BUILD_COLOR.get(tipus, Color(0.6, 0.5, 0.4))
	_load_sprite()
	var shape := RectangleShape2D.new()
	shape.size = _size
	col.shape = shape
	rally.position = Vector2(0, _size.y * 0.5 + 34.0)

	prod_tmr.timeout.connect(_produce)
	add_to_group("buildings")
	if owner_id == GameState.en_id:
		add_to_group("player_buildings")
	else:
		add_to_group("enemy_buildings")
	if BUILD_STATS.get(tipus, {}).get("drop", false):
		add_to_group("dropoff")
	sprite.visible = false
	queue_redraw()

func _base_hp() -> float:
	var hps: Array = BUILD_STATS.get(tipus, {}).get("hp", [500, 600, 700, 800])
	return float(hps[clampi(age, 0, 3)])

# Friss kőművesség-fokozat után a MÁR ÁLLÓ házak is szívósabbak lesznek.
# Az életerőt arányosan visszük át, hogy a sérült ház ne gyógyuljon meg a
# kutatástól, de a teljes se maradjon félig sebzettnek.
func refresh_stats() -> void:
	var arany := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	max_hp = _base_hp() * Upgrades.building_hp_mul(owner_id)
	hp = maxf(1.0, max_hp * arany)
	queue_redraw()

func _process(delta: float) -> void:
	# Hálózati játszmában a csatlakozó nem termel, nem képez és nem épít:
	# mindezt a házigazda számolja, ide csak a kész állapot érkezik.
	if GameState.net_client:
		if tipus in CHIMNEY and prog >= 1.0 and Settings.lively():
			_smoke_t += delta
			_smoke_redraw += delta
			if _smoke_redraw >= 0.16:
				_smoke_redraw = 0.0
				queue_redraw()
		return
	if not GameState.on or GameState.over: return
	if prog < 1.0:
		# Az épület magától NEM nő ki a földből: annyival halad, ahány
		# munkás dolgozik rajta. Több munkás gyorsabban végez.
		var builders := _count_builders()
		if maga_epul: builders = maxi(builders, 1)
		if builders > 0:
			prog = minf(1.0, prog + delta * float(builders)
				* Upgrades.build_mul(owner_id) / maxf(build_time, 0.1))
			queue_redraw()
			if prog >= 1.0:
				SFX.play("build", -4.0)
		return                      # felépülés közben nem termel és nem képez
	_tick_resources(delta)
	_tick_tower(delta)
	_tick_heal(delta)
	# A kéményfüst mozgásához ritka újrarajzolás elég.
	if tipus in CHIMNEY and Settings.lively():
		_smoke_t += delta
		_smoke_redraw += delta
		if _smoke_redraw >= 0.16:
			_smoke_redraw = 0.0
			if _smoke_node != null and _on_screen: _smoke_node.queue_redraw()

func is_ready() -> bool:
	return prog >= 1.0

# --- Az ispotály aurája ---
#
# A kórház köré húzódó sebesültek maguktól felépülnek. A pap ütemétől két
# dologban tér el: az ARÁNYOS életerőt adja vissza (a nehézpáncélos is
# ugyanannyi idő alatt gyógyul meg, mint a parittyás), és nem kell hozzá
# senkit odaküldeni — csak a bázisra hátravonulni.
func _tick_heal(delta: float) -> void:
	var st: Dictionary = BUILD_STATS.get(tipus, {})
	if not st.has("heal"): return
	var r: float = float(st.get("healR", 150.0))
	var ero: float = float(st["heal"][clampi(age, 0, 3)]) * delta \
		* Upgrades.heal_mul(owner_id)
	var r2 := r * r
	for u in get_tree().get_nodes_in_group("units"):
		if int(u.owner_id) != owner_id or u.hp >= u.max_hp: continue
		if u.global_position.distance_squared_to(global_position) > r2: continue
		u.heal(u.max_hp * 0.01 * ero)

# A házigazda pillanatképe: élet és építési készültség.
func net_apply(new_hp: float, new_prog: float) -> void:
	if is_equal_approx(new_hp, hp) and is_equal_approx(new_prog, prog): return
	hp = new_hp
	prog = new_prog
	queue_redraw()

# Hány saját munkás áll az építkezésen.
func _count_builders() -> int:
	var n := 0
	var reach := hit_radius() + 40.0
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u): continue
		if u.owner_id != owner_id or u.build_target != self: continue
		if u.global_position.distance_to(global_position) <= reach + u.radius:
			n += 1
	return n

# A lábnyom "sugara" — a támadók ehhez mérik a hatótávot.
func hit_radius() -> float:
	return maxf(_size.x, _size.y) * 0.5

func _tick_resources(delta: float) -> void:
	var st: Dictionary = BUILD_STATS.get(tipus, {})
	var a := clampi(age, 0, 3)
	if st.has("food"):
		GameState.add_res(owner_id, "food", float(st["food"][a]) * delta)
	if st.has("gold"):
		GameState.add_res(owner_id, "gold", float(st["gold"]) * delta)
	if st.has("rum"):
		GameState.add_res(owner_id, "rum", float(st["rum"]) * delta)

func _tick_tower(delta: float) -> void:
	var st: Dictionary = BUILD_STATS.get(tipus, {})
	if not st.has("dmg"): return
	_tower_cd -= delta
	if _tower_cd > 0.0: return
	_tower_cd = 1.5
	var a := clampi(age, 0, 3)
	# A messzelátó az ÉPÜLETRE is hat: a jobb távcsővel a torony messzebbre lő.
	var rng: float = float(st["range"][a]) * Upgrades.vision_mul(owner_id)
	var best: Node2D = null
	var best_d := rng
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u): continue
		if not GameState.hostile(owner_id, int(u.owner_id)): continue
		# Az álruhás kémre a torony sem lő — előbb le kell lepleznie.
		# (A leleplezést maga a kém veszi észre: lásd Unit._spy_tick.)
		if u.disguised() or u.aboard(): continue
		var d: float = u.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = u
	if best != null and best.has_method("take_damage"):
		var main := get_tree().get_first_node_in_group("main")
		var from := global_position + Vector2(0, -_size.y * 0.5 - _height * 0.6)
		if main and main.has_method("spawn_projectile"):
			main.spawn_projectile(from, best, float(st["dmg"][a]), owner_id)
		else:
			best.take_damage(float(st["dmg"][a]))
		SFX.play("arrow" if age <= 1 else "cannon", -10.0)

# --- Képzés ---

func trainable() -> Array:
	# Egyes küldetéseknél nincs kaszárnya: ilyenkor a főváros toboroz
	# (pl. Mátyás fekete serege vagy Kościuszko kaszásai).
	if tipus == "hq" and not GameState.hq_trains.is_empty():
		return GameState.hq_trains
	var st: Dictionary = BUILD_STATS.get(tipus, {})
	return st.get("trains", [])

func enqueue_unit(role: String) -> bool:
	if not (role in trainable()): return false
	if not is_ready(): return false
	var st: Dictionary = BUILD_STATS.get(tipus, {})
	if age < int(st.get("minAge", 0)): return false
	# Népesség: a sorban álló egységek is foglalnak helyet.
	if ResourceSystem.pop_used(get_tree(), owner_id) >= ResourceSystem.pop_limit(get_tree(), owner_id):
		return false
	# HŐSBŐL EGYSZERRE CSAK EGY vezetheti a sereget (index.html 9/E). Ha
	# elesik, újra ki lehet állítani — a hőst nem lehet végleg elveszíteni,
	# csak drágán pótolni.
	if role == "hero" and hero_busy(get_tree(), owner_id):
		if owner_id == GameState.en_id:
			var fo := get_tree().get_first_node_in_group("main")
			if fo != null and fo.hud != null:
				fo.hud.show_toast(Lang.t("uz_egy_hos"), 3.0)
			SFX.play("deny")
		return false
	if not GameState.pay(owner_id, train_cost(owner_id, role)): return false
	train_queue.append(role)
	if prod_tmr.is_stopped():
		prod_tmr.wait_time = train_time(owner_id, role)
		prod_tmr.start()
	return true

# A képzés ára és ideje a fejlesztésektől is függ: a Számvitel olcsóbbá, a
# Kiképzőtábor gyorsabbá teszi. Egy helyen számoljuk, hogy a felület
# ugyanazt a számot mutassa, amit a kassza levon.
# Van-e már hőse ennek a félnek — akár a pályán, akár a képzési sorban?
static func hero_busy(tree: SceneTree, owner: int) -> bool:
	for u in tree.get_nodes_in_group("units"):
		if is_instance_valid(u) and int(u.owner_id) == owner and u.role == "hero":
			return true
	for b in tree.get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or int(b.owner_id) != owner: continue
		if "hero" in b.train_queue: return true
	return false

static func train_cost(owner: int, role: String) -> Dictionary:
	return Upgrades.scale_cost(owner, TRAIN_COST.get(role, {}))

static func train_time(owner: int, role: String) -> float:
	return float(TRAIN_TIME.get(role, 10.0)) * Upgrades.train_time_mul(owner)

func _produce() -> void:
	if train_queue.is_empty():
		prod_tmr.stop()
		return
	var role: String = train_queue.pop_front()
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("spawn_unit"):
		# A hajók vízre, a szárazföldiek partra kerülnek — a gyülekezőhely
		# könnyen a rossz oldalon lehet.
		var naval: bool = role in Unit.NAVAL_ROLES
		var pos: Vector2 = main.find_land_near(rally.global_position, 24.0, naval)
		var u: Node = main.spawn_unit(role, owner_id, pos, age)
		_apply_rally(u)
		if owner_id == GameState.en_id:
			Achievements.bump("trained")
			if role in Unit.NAVAL_ROLES: Achievements.bump("ships")
	if not train_queue.is_empty():
		prod_tmr.wait_time = train_time(owner_id, str(train_queue[0]))
		prod_tmr.start()
	else:
		prod_tmr.stop()

# --- Gyülekezőpont ---
#
# A frissen kiképzett egység ide indul. Háromféle lehet, mint az eredetiben:
#   sima pont      -> odamegy
#   nyersanyagra   -> a munkás rögtön ott kezd dolgozni
#   ellenségre     -> a katona rögtön megtámadja
func set_rally(world_pos: Vector2, node: Node2D = null, foe: Node = null) -> void:
	rally.global_position = world_pos
	rally_set  = true
	rally_node = node
	rally_foe  = foe
	queue_redraw()

func clear_rally() -> void:
	rally.position = Vector2(0, _size.y * 0.5 + 34.0)
	rally_set  = false
	rally_node = null
	rally_foe  = null
	queue_redraw()

# Milyen parancsot ad a gyülekezőpont — a HUD ebből írja ki az üzenetet.
func rally_kind() -> String:
	if not rally_set: return ""
	if is_instance_valid(rally_foe):  return "foe"
	if is_instance_valid(rally_node): return "node"
	return "point"

func _apply_rally(u: Node) -> void:
	if u == null or not is_instance_valid(u): return
	if not rally_set: return
	var worker: bool = u.role in ["worker", "fisher"]
	if is_instance_valid(rally_foe) and not worker and u.has_method("start_attacking"):
		u.start_attacking(rally_foe)
	elif is_instance_valid(rally_node) and worker and u.has_method("gather_at"):
		u.gather_at(rally_node)
	elif u.has_method("move_to"):
		u.move_to(rally.global_position)

# A gyülekezőpont jelzése: szaggatott vonal az épülettől, a végén zászló.
func _draw_rally(strong: bool) -> void:
	if not rally_set: return
	var to := rally.position
	var a := 0.85 if strong else 0.35
	var col := team_accent
	match rally_kind():
		"node": col = Color("8a6234")
		"foe":  col = Color("c0392b")
	col.a = a
	# szaggatott vezetővonal a talptól a zászlóig
	var from := Vector2(0, _size.y * 0.5 - 2.0)
	var d := to - from
	var steps := maxi(2, int(d.length() / 11.0))
	var line_c := Color(col.r, col.g, col.b, a * 0.75)
	for i in range(0, steps, 2):
		var p0 := from + d * (float(i) / float(steps))
		var p1 := from + d * (float(mini(i + 1, steps)) / float(steps))
		draw_line(p0, p1, Color(0, 0, 0, a * 0.35), 3.5)
		draw_line(p0, p1, line_c, 2.0)
	# talpgyűrű + rúd + lobogó — sötét kontúrral, hogy a füvön is olvasható
	draw_arc(to, 7.0, 0.0, TAU, 18, Color(0, 0, 0, a * 0.45), 3.5)
	draw_arc(to, 7.0, 0.0, TAU, 18, Color(col.r, col.g, col.b, a), 2.0)
	var top := to + Vector2(0, -26.0)
	draw_line(to, top, Color(0, 0, 0, a * 0.5), 4.0)
	draw_line(to, top, Color(0.30, 0.24, 0.16, a), 2.0)
	var flag := PackedVector2Array([top, top + Vector2(15.0, 5.0),
		top + Vector2(0.0, 10.0)])
	var outline := PackedVector2Array([top + Vector2(-1.5, -1.5),
		top + Vector2(17.0, 5.0), top + Vector2(-1.5, 11.5)])
	draw_colored_polygon(outline, Color(0, 0, 0, a * 0.5))
	draw_colored_polygon(flag, col)

# --- Sebzés ---

# A `tamado` az egységeknél a veteránsághoz kell; az épület nem gyűjt
# fokozatot, de a hívás alakja legyen ugyanaz.
func take_damage(amount: float, _tamado: Node = null) -> void:
	hp -= amount
	queue_redraw()
	if hp <= 0:
		if tipus == "hq":
			_on_hq_destroyed()
		# A ledőlt épület helyén kráter és felperzselt föld marad.
		var fo := get_tree().get_first_node_in_group("main")
		if fo != null and fo.scars != null and is_instance_valid(fo.scars):
			fo.scars.add_scar(global_position, "krater")
			fo.scars.add_scar(global_position + Vector2(_size.x * 0.3,
				_size.y * 0.25), "eges")
		if GameState.hostile(GameState.en_id, owner_id):
			GameState.kills += 1
			Achievements.bump("kills")
			GameState.add_fame(4.0)      # kifosztott telep: nő a hírnév
		queue_free()

func _on_hq_destroyed() -> void:
	# Több fél is lehet a pályán: akkor van vége, ha már csak EGY csapatnak
	# maradt fővárosa. (Ez a mostani épület még a fában van, ezért kivesszük.)
	var teams: Array = []
	for b in get_tree().get_nodes_in_group("buildings"):
		if b == self or not is_instance_valid(b) or b.tipus != "hq": continue
		var t := GameState.team_of(int(b.owner_id))
		if not (t in teams): teams.append(t)
	if teams.size() > 1: return
	GameState.over = true
	if teams.is_empty():
		GameState.winner = -1
		return
	# A győztes csapat egyik oldalának indexe (a játékosé, ha ő az).
	var win_team: int = teams[0]
	GameState.winner = GameState.en_id if GameState.team_of(GameState.en_id) == win_team else -1
	for s in GameState.oldalak:
		if int(s.get("csapat", -99)) == win_team:
			if GameState.winner == -1: GameState.winner = int(s["i"])
			if int(s["i"]) == GameState.en_id:
				GameState.winner = GameState.en_id
				break

# --- Népesség ---

static func pop_bonus(t: String) -> int:
	var st: Dictionary = BUILD_STATS.get(t, {})
	return int(st.get("pop", 0))

func _load_sprite() -> void:
	var set: Array = MATERIALS.get(tipus,
		[["stone", "slate"], ["brick", "slate"], ["blue", "blueroof"]])
	var pair: Array = set[clampi(era_group(age), 0, set.size() - 1)]
	var w := _load_material(pair[0])
	var r := _load_material(pair[1])
	_wall_tex = w[0]; _wall_src = w[1]
	_roof_tex = r[0]; _roof_src = r[1]
	if tipus == "hq":
		var fp := Style.flag_path(
			GameState.nation if owner_id == GameState.en_id else "de", age)
		if ResourceLoader.exists(fp):
			_flag_tex = load(fp)

func _load_material(key: String) -> Array:
	var e: Array = TEX_LIB.get(key, [])
	if e.is_empty(): return [null, Rect2()]
	var path: String = "res://assets/sprites/buildings/%s.png" % e[0]
	if not ResourceLoader.exists(path): return [null, Rect2()]
	return [load(path), e[1]]

# Egy téglalap kitöltése a textúrarészlettel. A mintát NEM csempézzük,
# hanem egyben ráfeszítjük: az ismétlés varratai miatt nézett ki az épület
# különálló panelekből összerakottnak.
func _fill(dst: Rect2, tex: Texture2D, src: Rect2, tint: Color = Color.WHITE) -> void:
	if dst.size.x <= 0.0 or dst.size.y <= 0.0: return
	# A kivágott textúrafolt helyenként ÁTLÁTSZÓ (a forrás egy épület-
	# sprite, nem tömör anyagminta). Ezért előbb tömör vakolatot festünk
	# alá — enélkül a ház fala helyenként a füvet mutatta.
	var a := clampi(age, 0, 3)
	var base := Color(str(Style.AGE_STYLE[a]["wall"]))
	draw_rect(dst, base.lerp(_color, 0.45), true)
	if tex == null:
		draw_rect(dst, _color, true)
		return
	draw_texture_rect_region(tex, dst, src, tint)

# Trapéz alakú tetőfelület vízszintes sávokból. Így a minta követi a
# tető formáját, és a sávok hézagmentesen érnek össze — egy tető lesz
# belőle, nem néhány egymásra dobott téglalap.
func _fill_roof(top_c: Vector2, top_w: float, bot_c: Vector2, bot_w: float,
				tex: Texture2D, src: Rect2) -> void:
	const N := 14
	var h := bot_c.y - top_c.y
	if h <= 0.0: return
	for i in range(N):
		var t0 := float(i) / N
		var t1 := float(i + 1) / N
		var y0 := top_c.y + h * t0
		var y1 := top_c.y + h * t1
		var w0 := lerpf(top_w, bot_w, t0)
		var w1 := lerpf(top_w, bot_w, t1)
		var w := maxf(w0, w1)
		var cx := lerpf(top_c.x, bot_c.x, (t0 + t1) * 0.5)
		var dst := Rect2(cx - w * 0.5, y0, w, y1 - y0 + 0.75)
		# Tömör cserépszín a folt alá: a kivágott minta helyenként átlátszó.
		draw_rect(dst, _roof_base(), true)
		if tex == null:
			continue
		var s := Rect2(src.position.x, src.position.y + src.size.y * t0,
			src.size.x, maxf(1.0, src.size.y * (t1 - t0)))
		draw_texture_rect_region(tex, dst, s)
		# A tető lejtője lefelé sötétedik — ettől lesz térbeli.
		draw_rect(dst, Color(0, 0, 0, 0.30 * t1), true)

# A korszakhoz illő tetőszín — ez fedi az átlátszó helyeket.
func _roof_base() -> Color:
	return Color(str(Style.AGE_STYLE[clampi(age, 0, 3)]["roof"]))

# A tető sziluettje (a körberajzoláshoz és az árnyékhoz).
func _roof_outline(top_c: Vector2, top_w: float, bot_c: Vector2,
				   bot_w: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(top_c.x - top_w * 0.5, top_c.y),
		Vector2(top_c.x + top_w * 0.5, top_c.y),
		Vector2(bot_c.x + bot_w * 0.5, bot_c.y),
		Vector2(bot_c.x - bot_w * 0.5, bot_c.y),
		Vector2(top_c.x - top_w * 0.5, top_c.y),
	])

# Az épület 2.5D-ben: felülről látszik a tető, elölről a homlokzat. A két
# felület együtt pont a lábnyomot fedi le, így a csapatsáv, az árnyék és a
# kijelölő keret is pontosan illeszkedik.
#   lift     — ennyivel emelkedik a tető a lábnyom fölé (magasság érzet)
#   wall_h   — a látható homlokzat magassága
func _wall_height() -> float:
	return maxf(_height * 0.85, 14.0)

# A tető magassága a lábnyom mélységéből adódik (felülnézet), plusz egy
# kis emelés. A homlokzat viszont a BUILD_HEIGHT-ból — így a torony
# tényleg magas és keskeny lesz, nem pedig egy házikó.
func _roof_height() -> float:
	return _size.y * 0.55 + _height * 0.36

func _roof_rect() -> Rect2:
	var base := _size.y * 0.5 - _wall_height()
	return Rect2(-_size.x * 0.5 - 4.0, base - _roof_height(),
		_size.x + 8.0, _roof_height())

func _wall_rect() -> Rect2:
	var wh := _wall_height()
	return Rect2(-_size.x * 0.5, _size.y * 0.5 - wh, _size.x, wh)

func _sprite_rect() -> Rect2:
	return _roof_rect().merge(_wall_rect())

func _draw() -> void:
	var foot := Rect2(-_size * 0.5, _size)
	var box := _sprite_rect()
	# Vetett árnyék: a fény balról-fentről jön, ezért az árnyék jobbra-le
	# dől. Két rétegben, hogy lágy pereme legyen, ne éles téglalap.
	var sh := _wall_height() * 0.5
	draw_rect(Rect2(foot.position.x + 3.0, foot.end.y - sh + 2.0,
		_size.x + 10.0, sh + 6.0), Color(0, 0, 0, 0.10), true)
	draw_rect(Rect2(foot.position.x + 6.0, foot.end.y - sh + 4.0,
		_size.x + 2.0, sh), Color(0, 0, 0, 0.20), true)
	# Építkezés alatt csak alulról látható annyi, amennyi már áll.
	var reveal := box.end.y - box.size.y * clampf(prog, 0.0, 1.0)
	if tipus in FLAT_TYPES:
		_draw_flat(foot, reveal)
	else:
		_draw_house(foot, reveal)
	if prog < 1.0:
		_draw_scaffold(box)
	# Csapatszín: keskeny sáv az épület talpánál, mint az eredeti zászlósáv.
	draw_rect(Rect2(foot.position.x, foot.end.y - 3.0, foot.size.x, 3.0), team_color, true)
	if _selected:
		draw_rect(foot, team_accent, false, 2.0)
	# A gyülekezőpont a kijelölt épületnél erősen, a többinél halványan
	# látszik — így nem vész el, de nem is nyomja agyon a képet.
	if owner_id == GameState.en_id:
		_draw_rally(_selected)
	# Sérülés: sötétedő fátyol
	var frac := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	if frac < 0.6:
		draw_rect(box, Color(0.1, 0.05, 0.0, (0.6 - frac) * 0.5), true)
	var bar_w := _size.x
	var bar_top := box.position.y - 12.0
	if prog < 1.0:
		_draw_bar(bar_w, bar_top, prog, Color("d8b34a"))
	elif frac < 1.0:
		var c := Color("6fae52")
		if frac < 0.55: c = Color("c98b3a")
		if frac < 0.28: c = Color("c04a3a")
		_draw_bar(bar_w, bar_top, frac, c)
	elif not train_queue.is_empty():
		var left := prod_tmr.time_left
		var total := maxf(prod_tmr.wait_time, 0.001)
		_draw_bar(bar_w, bar_top, 1.0 - left / total, Color("6f8fae"))

func _draw_bar(w: float, top: float, frac: float, c: Color) -> void:
	draw_rect(Rect2(-w * 0.5 - 1.0, top - 1.0, w + 2.0, 7.0), Color(0, 0, 0, 0.55), true)
	draw_rect(Rect2(-w * 0.5, top, w * clampf(frac, 0.0, 1.0), 5.0), c, true)

# A téglalap azon része, ami a megadott vonal ALATT van (építkezés).
func _below(r: Rect2, y: float) -> Rect2:
	if r.end.y <= y: return Rect2()
	var top := maxf(r.position.y, y)
	return Rect2(r.position.x, top, r.size.x, r.end.y - top)

# Mennyire keskenyedik a tető a gerinc felé. 0 = csúcsos (sátortető),
# 1 = lapos. A torony hegyes, a csarnokok laposabbak.
const ROOF_TAPER := {
	"tower": 0.12, "temple": 0.22, "hq": 0.34, "house": 0.26,
	"barracks": 0.40, "stable": 0.46, "harbor": 0.42, "goldmine": 0.30,
}

# Tetős épület EGY sziluettként: homlokzat + fölötte nyeregtető, közös
# körvonallal. Korábban két külön téglalap volt, ezért tűnt szétesettnek.
func _draw_house(foot: Rect2, reveal: float) -> void:
	var wall := _below(_wall_rect(), reveal)
	var rr := _roof_rect()
	var taper: float = ROOF_TAPER.get(tipus, 0.32)
	var bot_w := rr.size.x                 # ereszszélesség (a talpnál szélesebb)
	var top_w := rr.size.x * taper         # gerinc
	var top_c := Vector2(0.0, rr.position.y)
	var bot_c := Vector2(0.0, rr.end.y)

	# 1. Homlokzat
	if wall.size.y > 0.0:
		_fill(wall, _wall_tex, _wall_src)
		# Sarokárnyék: a jobb oldal elfordul a fénytől.
		draw_rect(Rect2(wall.end.x - wall.size.x * 0.16, wall.position.y,
			wall.size.x * 0.16, wall.size.y), Color(0, 0, 0, 0.18), true)
		# A bal oldal viszont kap egy kis fényt.
		draw_rect(Rect2(wall.position.x, wall.position.y,
			wall.size.x * 0.10, wall.size.y), Color(1, 1, 1, 0.07), true)
		# Az eresz árnyéka a fal tetején — ettől ül rá a tető a falra.
		draw_rect(Rect2(wall.position.x, wall.position.y,
			wall.size.x, minf(5.0, wall.size.y)), Color(0, 0, 0, 0.26), true)
		# Lábazat és a tövében felverődő por-sáv.
		draw_rect(Rect2(wall.position.x, wall.end.y - 7.0, wall.size.x, 3.0),
			Color(0.30, 0.24, 0.16, 0.18), true)
		draw_rect(Rect2(wall.position.x, wall.end.y - 4.0, wall.size.x, 4.0),
			Color(0, 0, 0, 0.28), true)

	# 2. Tető — csak az épülés során látható részig
	if rr.end.y > reveal:
		var vis_top := maxf(rr.position.y, reveal)
		var t := (vis_top - rr.position.y) / maxf(rr.size.y, 0.001)
		var vis_w := lerpf(top_w, bot_w, t)
		_fill_roof(Vector2(0.0, vis_top), vis_w, bot_c, bot_w, _roof_tex, _roof_src)
		# Eresz: vastag sötét vonal, ez zárja le a tetőt a fal fölött.
		draw_line(Vector2(-bot_w * 0.5, bot_c.y), Vector2(bot_w * 0.5, bot_c.y),
			Color(0.16, 0.12, 0.09), 3.0)
		# Gerincdeszka
		if t < 0.2:
			draw_line(Vector2(-top_w * 0.5 - 1.0, rr.position.y),
				Vector2(top_w * 0.5 + 1.0, rr.position.y),
				Color(0.90, 0.88, 0.80, 0.85), 2.5)
		# Oromfal-élek: a tető két ferde széle
		draw_polyline(_roof_outline(Vector2(0.0, vis_top), vis_w, bot_c, bot_w),
			Color(0.14, 0.11, 0.08, 0.9), 1.5)

	# 3. Közös körvonal: a fal és a tető egy testként olvasódik.
	if wall.size.y > 0.0:
		draw_line(Vector2(wall.position.x, wall.position.y),
			Vector2(wall.position.x, wall.end.y), Color(0.14, 0.11, 0.08, 0.9), 1.5)
		draw_line(Vector2(wall.end.x, wall.position.y),
			Vector2(wall.end.x, wall.end.y), Color(0.14, 0.11, 0.08, 0.9), 1.5)
	if prog < 1.0: return
	if tipus in CHIMNEY: _draw_chimney(rr)
	_draw_openings(foot)
	_draw_signature(foot, wall, rr)

# A FÜST KÜLÖN CSOMÓPONTON.
#
# A füst mozog, tehát újra kell rajzolni — de ha ezt az ÉPÜLET csinálja,
# akkor a fal, a tető, az ablakok és az ajtó is újraépül minden alkalommal.
# Mérve ez volt a legdrágább művelet a gyenge gépen (18 ms/kép). Így
# viszont csak három pamacs rajzolódik újra.
var _smoke_node: Node2D = null

func _ensure_smoke() -> void:
	if _smoke_node != null or not (tipus in CHIMNEY): return
	_smoke_node = Node2D.new()
	_smoke_node.z_index = 1
	_smoke_node.draw.connect(_draw_smoke)
	add_child(_smoke_node)
	# Csak a képernyőn lévő kémények füstölnek: a pálya túloldalán álló
	# házak füstjét úgysem látja senki.
	if not Settings.cull_offscreen: return
	var vis := VisibleOnScreenNotifier2D.new()
	vis.rect = Rect2(-_size.x, -_size.y * 2.0, _size.x * 2.0, _size.y * 3.0)
	vis.screen_entered.connect(func() -> void: _on_screen = true)
	vis.screen_exited.connect(func() -> void: _on_screen = false)
	add_child(vis)

var _on_screen: bool = true

func _draw_smoke() -> void:
	if prog < 1.0 or not Settings.lively(): return
	var rr := _roof_rect()
	var cw := clampf(rr.size.x * 0.10, 5.0, 11.0)
	var ch := clampf(rr.size.y * 0.36, 8.0, 17.0)
	var cx := -rr.size.x * 0.24
	var top_y := rr.position.y + rr.size.y * 0.20 - ch
	for i in range(3):
		var u := fmod(_smoke_t * 0.35 + float(i) / 3.0, 1.0)
		var p := Vector2(cx + u * cw * 1.3 + sin(u * 6.0) * 1.5,
			top_y - 2.0 - u * 26.0)
		_smoke_node.draw_circle(p, 2.0 + u * 5.0,
			Color(0.86, 0.86, 0.88, (1.0 - u) * 0.32))

# Kémény és füst. Ettől lakott a település: a ház nem csak áll, hanem
# fűtenek benne. A füst lassan száll, ezért az épület ritkán (6 Hz)
# rajzolódik újra — ennyi elég a folyamatos mozgáshoz.
const CHIMNEY := ["hq", "house", "barracks", "stable", "goldmine"]

# Melyik változat ez a ház? A hálózati azonosító sorsolja, tehát minden
# gépen ugyanaz — és egy utcányi lakóház nem lesz egyforma másolat.
func _valtozat() -> int:
	return absi(nid * 2654435761) % 3

func _draw_chimney(rr: Rect2) -> void:
	var cw := clampf(rr.size.x * 0.10, 5.0, 11.0)
	var ch := clampf(rr.size.y * 0.36, 8.0, 17.0)
	# A lakóháznál a kémény hol a bal, hol a jobb oldalon áll.
	var oldal := 1.0 if (tipus == "house" and _valtozat() == 1) else -1.0
	var cx := oldal * rr.size.x * 0.24
	# A kémény a tető ferde oldalán ül, ezért a gerinctől kissé lejjebb.
	var top_y := rr.position.y + rr.size.y * 0.20
	var r := Rect2(cx - cw * 0.5, top_y - ch, cw, ch)
	draw_rect(r, Color(0.44, 0.29, 0.22), true)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x * 0.35, r.size.y),
		Color(1, 1, 1, 0.10), true)
	draw_rect(Rect2(r.position.x - 1.5, r.position.y, r.size.x + 3.0, 3.0),
		Color(0.28, 0.19, 0.14), true)
	draw_rect(r, Color(0.14, 0.10, 0.07, 0.85), false, 1.0)
	# A füstpamacsokat a _smoke_node rajzolja: azok mozognak, a kémény nem.
	_ensure_smoke()

# Ajtó és ablakok a homlokzaton; a fővároson ezen felül zászló is van.
func _draw_openings(foot: Rect2) -> void:
	var wall := _wall_rect()
	if wall.size.y >= 14.0:
		var dw := clampf(_size.x * 0.16, 8.0, 18.0)
		var dh := wall.size.y * 0.62
		var door := Rect2(-dw * 0.5, wall.end.y - dh, dw, dh)
		# Kőkeret az ajtó körül, deszkás ajtólap, kilincs és küszöb.
		draw_rect(Rect2(door.position - Vector2(2, 2), door.size + Vector2(4, 2)),
			Color(0.52, 0.48, 0.42, 0.85), true)
		draw_rect(door, Color(0.22, 0.14, 0.09), true)
		for i in range(3):
			var lx := door.position.x + door.size.x * (0.25 + 0.25 * float(i))
			draw_line(Vector2(lx, door.position.y + 2.0),
				Vector2(lx, door.end.y - 1.0), Color(0.14, 0.09, 0.05, 0.7), 1.0)
		draw_circle(Vector2(door.end.x - 3.0, door.position.y + dh * 0.55), 1.4,
			Color(0.78, 0.66, 0.30))
		draw_rect(Rect2(door.position.x - 3.0, door.end.y - 2.0,
			door.size.x + 6.0, 2.0), Color(0.46, 0.43, 0.38), true)
		draw_rect(door, Color(0, 0, 0, 0.45), false, 1.0)
		# Ablakok az ajtó két oldalán: keret, keresztfa, párkány és a
		# bentről kiszűrődő fény.
		var n := int(_size.x / 34.0)
		for i in range(n):
			var wx := -_size.x * 0.5 + 10.0 + i * 34.0
			if absf(wx + 5.0) < dw * 0.7: continue
			var win := Rect2(wx, wall.position.y + wall.size.y * 0.22, 11.0, 10.0)
			if win.end.x > _size.x * 0.5 - 4.0: continue
			draw_rect(Rect2(win.position - Vector2(1.5, 1.5),
				win.size + Vector2(3, 3)), Color(0.50, 0.46, 0.40, 0.9), true)
			draw_rect(win, Color(0.30, 0.26, 0.18), true)
			draw_rect(Rect2(win.position, win.size * Vector2(1.0, 0.5)),
				Color(0.90, 0.85, 0.56, 0.92), true)
			draw_rect(Rect2(win.position.x, win.position.y + win.size.y * 0.5,
				win.size.x, win.size.y * 0.5), Color(0.72, 0.66, 0.42, 0.85), true)
			draw_line(Vector2(win.position.x + win.size.x * 0.5, win.position.y),
				Vector2(win.position.x + win.size.x * 0.5, win.end.y),
				Color(0.20, 0.16, 0.11), 1.0)
			draw_line(Vector2(win.position.x, win.position.y + win.size.y * 0.5),
				Vector2(win.end.x, win.position.y + win.size.y * 0.5),
				Color(0.20, 0.16, 0.11), 1.0)
			draw_rect(Rect2(win.position.x - 2.5, win.end.y + 1.0,
				win.size.x + 5.0, 2.0), Color(0.56, 0.52, 0.45), true)
	if tipus == "tower":
		# Pártázat a fal tetején, a torony sisakja alatt.
		var i := 0
		var x := wall.position.x
		while x < wall.end.x - 4.0:
			if i % 2 == 0:
				draw_rect(Rect2(x, wall.position.y - 5.0, 6.0, 6.0),
					Color(0.35, 0.33, 0.30), true)
				draw_rect(Rect2(x, wall.position.y - 5.0, 6.0, 6.0),
					Color(0, 0, 0, 0.45), false, 1.0)
			x += 8.0
			i += 1
	if tipus == "hq" and _flag_tex != null:
		# Zászlórúd a tetőgerincen, rajta a nemzet korszakhoz illő lobogója.
		var roof2 := _roof_rect()
		var px := roof2.size.x * 0.10
		var base_y := roof2.position.y + 2.0
		var top_y := roof2.position.y - 34.0
		draw_line(Vector2(px, base_y), Vector2(px, top_y),
			Color(0.26, 0.20, 0.13), 2.0)
		var fr := Rect2(px + 1.5, top_y, 30.0, 20.0)
		draw_rect(Rect2(fr.position + Vector2(1, 2), fr.size), Color(0, 0, 0, 0.35), true)
		draw_texture_rect(_flag_tex, fr, false)
		draw_rect(fr, Color(0.12, 0.10, 0.07, 0.8), false, 1.0)

# --- JELLEGZETESSÉG: miről ismerni meg az épületet? ---
#
# A közös váz (fal + nyeregtető + ajtó + ablakok) jó alap, de önmagában
# minden ház egyforma kis házikó. Erre a vázra fest rá ez a réteg egy-egy
# ELÁRULÓ JEGYET, amit a játékos messziről is felismer:
#
#   templom    — harangtorony, rózsaablak, íves kapu
#   aranybánya — bányaállvány csigával, sötét táró, ércrakás, csille
#   piactér    — csíkos ponyva, hordók és ládák, cégér
#   ispotály   — keresztes tábla, lámpás a bejárat fölött
#   kovács     — izzó kohónyílás, üllő, vizesdézsa
#   akadémia   — oszlopos előcsarnok oromzattal, lépcső
#   kaszárnya  — zászlórúd, lándzsaállvány, palánk
#   istálló    — széles kapu patkóval, szénabálák, karám
#   kikötő     — móló cölöpökkel, daru, ládák
#   torony     — lőrések
#   főváros    — saroktornyok (a zászló már megvan)
#
# A LAKÓHÁZ marad ház — de három változatban (tető árnyalata, kémény
# oldala, ablakszám), hogy egy utcányi ház ne tűnjön másolatnak. A
# változatot az épület hálózati azonosítója sorsolja, tehát minden gépen
# ugyanaz.
func _draw_signature(foot: Rect2, wall: Rect2, rr: Rect2) -> void:
	match tipus:
		"temple":   _sig_temple(foot, wall, rr)
		"goldmine": _sig_mine(foot, wall, rr)
		"market":   _sig_market(foot, wall)
		"hospital": _sig_hospital(foot, wall)
		"smith":    _sig_smith(foot, wall, rr)
		"academy":  _sig_academy(foot, wall)
		"barracks": _sig_barracks(foot, wall)
		"stable":   _sig_stable(foot, wall)
		"harbor":   _sig_harbor(foot, wall)
		"tower":    _sig_tower(wall)
		"hq":       _sig_hq(wall, rr)
		"house":    _sig_house(foot, wall, rr)

# LAKÓHÁZ: marad ház, de három arca van, hogy egy utcányi ne legyen
# egyforma. A kémény oldalát a _draw_chimney intézi; itt a tetőablak, a
# toldalék és a kerti apróságok jönnek.
func _sig_house(foot: Rect2, wall: Rect2, rr: Rect2) -> void:
	match _valtozat():
		0:
			# Kerti pad és egy dézsa a fal mellett.
			draw_rect(Rect2(wall.end.x - 18.0, wall.end.y - 8.0, 14.0, 3.0),
				SIG_FA.lightened(0.1), true)
			draw_rect(Rect2(wall.end.x - 17.0, wall.end.y - 5.0, 2.0, 4.0), SIG_FA, true)
			draw_rect(Rect2(wall.end.x - 7.0, wall.end.y - 5.0, 2.0, 4.0), SIG_FA, true)
		1:
			# Oldalsó toldalék (fáskamra) lapos tetővel.
			var t := Rect2(wall.position.x - 12.0, wall.position.y + wall.size.y * 0.42,
				14.0, wall.size.y * 0.58)
			draw_rect(t, _roof_base().lightened(0.55), true)
			draw_rect(Rect2(t.position.x - 2.0, t.position.y - 3.0, t.size.x + 4.0, 4.0),
				_roof_base().darkened(0.1), true)
			draw_rect(t, Color(0.14, 0.11, 0.08, 0.8), false, 1.2)
			# Felaprított tűzifa a toldalék előtt.
			for i in range(3):
				draw_circle(Vector2(t.position.x + 3.0 + float(i) * 4.0,
					t.end.y - 3.0), 2.0, SIG_FA.lightened(0.2))
		_:
			# Tetőablak a nyeregtetőn.
			var a := Rect2(-6.0, rr.position.y + rr.size.y * 0.45, 12.0, 9.0)
			draw_rect(a, _roof_base().lightened(0.45), true)
			draw_rect(Rect2(a.position.x + 2.0, a.position.y + 2.0, 8.0, 5.0),
				Color(0.88, 0.80, 0.48, 0.9), true)
			draw_colored_polygon([a.position + Vector2(-2.0, 0),
				Vector2(0.0, a.position.y - 5.0), a.position + Vector2(14.0, 0)],
				_roof_base().darkened(0.15))
			draw_rect(a, Color(0.16, 0.12, 0.09, 0.8), false, 1.0)

const SIG_FA := Color(0.36, 0.25, 0.15)
const SIG_KO := Color(0.56, 0.53, 0.47)
const SIG_ARANY := Color(0.82, 0.68, 0.28)
const SIG_VAS := Color(0.28, 0.28, 0.31)

# TEMPLOM: harangtorony a homlokzat bal oldalán, hegyes sisakkal és
# toronygombbal; a kapu íves, fölötte rózsaablak.
func _sig_temple(foot: Rect2, wall: Rect2, rr: Rect2) -> void:
	var tw := clampf(_size.x * 0.24, 14.0, 24.0)
	var tx := wall.position.x + _size.x * 0.06
	var torony := Rect2(tx, rr.position.y - _size.y * 0.42, tw, 0.0)
	torony.size.y = wall.end.y - torony.position.y
	draw_rect(torony, _roof_base().lightened(0.42), true)
	draw_rect(torony, Color(0.14, 0.11, 0.08, 0.85), false, 1.5)
	# Harangablak: sötét, íves nyílás a torony tetején.
	var ha := Rect2(torony.position.x + tw * 0.28, torony.position.y + 8.0,
		tw * 0.44, 10.0)
	draw_rect(ha, Color(0.10, 0.08, 0.06), true)
	# Sisak és toronygomb.
	var csucs := Vector2(torony.position.x + tw * 0.5, torony.position.y - tw * 1.15)
	draw_colored_polygon([Vector2(torony.position.x - 2.0, torony.position.y),
		csucs, Vector2(torony.end.x + 2.0, torony.position.y)],
		_roof_base().darkened(0.18))
	draw_polyline([Vector2(torony.position.x - 2.0, torony.position.y), csucs,
		Vector2(torony.end.x + 2.0, torony.position.y)],
		Color(0.14, 0.11, 0.08, 0.9), 1.5)
	draw_circle(csucs - Vector2(0, 2.0), 2.6, SIG_ARANY)
	# Rózsaablak a homlokzat közepén, fölötte íves kapukeret.
	var kozep := Vector2(_size.x * 0.10, wall.position.y + wall.size.y * 0.34)
	draw_circle(kozep, 7.0, Color(0.42, 0.38, 0.30))
	draw_circle(kozep, 5.2, Color(0.86, 0.76, 0.42, 0.92))
	for i in range(6):
		var a := float(i) * PI / 3.0
		draw_line(kozep, kozep + Vector2(cos(a), sin(a)) * 5.2,
			Color(0.35, 0.30, 0.22), 1.0)
	draw_arc(Vector2(0.0, wall.end.y - wall.size.y * 0.62), _size.x * 0.10,
		PI, TAU, 14, Color(0.52, 0.48, 0.42), 3.0)

# ARANYBÁNYA: bányaállvány (két ferde gerenda + csiga) a tető fölött,
# gerendázott sötét táró a ház oldalában, ércrakás és csille a talpnál.
func _sig_mine(foot: Rect2, wall: Rect2, rr: Rect2) -> void:
	var cx := _size.x * 0.22
	var teto := rr.position.y - _size.y * 0.34
	draw_line(Vector2(cx - 13.0, wall.end.y - 4.0), Vector2(cx, teto), SIG_FA, 3.0)
	draw_line(Vector2(cx + 13.0, wall.end.y - 4.0), Vector2(cx, teto), SIG_FA, 3.0)
	draw_line(Vector2(cx - 9.0, teto + 16.0), Vector2(cx + 9.0, teto + 16.0),
		SIG_FA.darkened(0.2), 2.0)
	# Csiga és kötél: ezen jár le a kas a tárnába.
	draw_circle(Vector2(cx, teto + 1.0), 4.4, SIG_VAS)
	draw_circle(Vector2(cx, teto + 1.0), 1.6, SIG_ARANY)
	draw_line(Vector2(cx, teto + 5.0), Vector2(cx, wall.end.y - 10.0),
		Color(0.20, 0.17, 0.12), 1.2)
	# Táró: gerendakeret, mögötte a sötét.
	var taro := Rect2(-_size.x * 0.44, wall.end.y - 20.0, 22.0, 18.0)
	draw_rect(taro, Color(0.06, 0.05, 0.04), true)
	draw_rect(taro.grow(2.0), SIG_FA, false, 3.0)
	draw_line(Vector2(taro.position.x - 2.0, taro.position.y - 2.0),
		Vector2(taro.end.x + 2.0, taro.position.y - 2.0), SIG_FA.lightened(0.15), 3.0)
	# Ércrakás: sötét kőhalom, benne aranyszemcsék.
	for i in range(3):
		var p := Vector2(_size.x * 0.30 + float(i) * 7.0 - 7.0, wall.end.y - 4.0)
		draw_circle(p, 5.0 - float(i), Color(0.32, 0.28, 0.22))
		draw_circle(p + Vector2(1.0, -1.5), 1.2, SIG_ARANY)

# PIACTÉR: csíkos ponyva a homlokzat előtt, alatta hordók és ládák,
# oldalt kilógó cégér.
func _sig_market(foot: Rect2, wall: Rect2) -> void:
	var y := wall.position.y + wall.size.y * 0.42
	var w := _size.x * 0.92
	var bal := -w * 0.5
	# Ponyva: váltakozó csíkok, enyhén lejtve.
	var csik := int(w / 9.0)
	for i in range(csik):
		var x := bal + float(i) * (w / float(csik))
		var c := Color(0.78, 0.26, 0.22) if i % 2 == 0 else Color(0.92, 0.88, 0.78)
		draw_colored_polygon([Vector2(x, y), Vector2(x + w / float(csik), y),
			Vector2(x + w / float(csik), y + 9.0), Vector2(x, y + 9.0)], c)
	draw_line(Vector2(bal, y + 9.0), Vector2(bal + w, y + 9.0),
		Color(0.22, 0.18, 0.14, 0.8), 1.5)
	# Tartórudak
	draw_line(Vector2(bal + 2.0, y + 9.0), Vector2(bal + 2.0, wall.end.y - 5.0), SIG_FA, 2.0)
	draw_line(Vector2(bal + w - 2.0, y + 9.0), Vector2(bal + w - 2.0, wall.end.y - 5.0),
		SIG_FA, 2.0)
	# Hordók és ládák a ponyva alatt.
	for i in range(2):
		var hx := bal + 10.0 + float(i) * 15.0
		draw_rect(Rect2(hx, wall.end.y - 14.0, 9.0, 12.0), Color(0.45, 0.31, 0.18), true)
		draw_line(Vector2(hx, wall.end.y - 10.0), Vector2(hx + 9.0, wall.end.y - 10.0),
			Color(0.30, 0.22, 0.14), 1.2)
	draw_rect(Rect2(bal + w - 22.0, wall.end.y - 12.0, 12.0, 10.0),
		Color(0.56, 0.42, 0.24), true)
	draw_rect(Rect2(bal + w - 22.0, wall.end.y - 12.0, 12.0, 10.0),
		Color(0.30, 0.22, 0.14), false, 1.0)
	# Cégér: rúd a falból, rajta tábla.
	var rud := Vector2(bal + w - 6.0, wall.position.y + 8.0)
	draw_line(rud, rud + Vector2(10.0, 0), SIG_VAS, 1.5)
	draw_rect(Rect2(rud.x + 6.0, rud.y + 1.0, 10.0, 8.0), Color(0.62, 0.48, 0.24), true)
	draw_rect(Rect2(rud.x + 6.0, rud.y + 1.0, 10.0, 8.0), Color(0.24, 0.18, 0.10), false, 1.0)

# ISPOTÁLY: fehér tábla vörös kereszttel a homlokzaton, lámpás a kapu
# fölött — messziről ez mondja meg, hol gyógyítanak.
func _sig_hospital(foot: Rect2, wall: Rect2) -> void:
	var t := Rect2(_size.x * 0.16, wall.position.y + wall.size.y * 0.26, 18.0, 18.0)
	draw_rect(t, Color(0.94, 0.93, 0.90), true)
	draw_rect(t, Color(0.30, 0.28, 0.25), false, 1.0)
	var k := Color(0.76, 0.18, 0.16)
	draw_rect(Rect2(t.position.x + 7.0, t.position.y + 2.5, 4.0, 13.0), k, true)
	draw_rect(Rect2(t.position.x + 2.5, t.position.y + 7.0, 13.0, 4.0), k, true)
	# Lámpás a bejárat fölött.
	var l := Vector2(0.0, wall.end.y - wall.size.y * 0.66)
	draw_line(l + Vector2(0, -6.0), l, SIG_VAS, 1.4)
	draw_rect(Rect2(l.x - 3.0, l.y, 6.0, 7.0), Color(0.24, 0.22, 0.18), true)
	draw_rect(Rect2(l.x - 2.0, l.y + 1.0, 4.0, 5.0), Color(1.6, 1.3, 0.7), true)

# KOVÁCSMŰHELY: izzó kohónyílás a fal tövében, előtte üllő és vizesdézsa.
# (A kéményt a közös rajz adja — ez a műhely arca.)
func _sig_smith(foot: Rect2, wall: Rect2, rr: Rect2) -> void:
	var k := Rect2(-_size.x * 0.40, wall.end.y - 18.0, 16.0, 15.0)
	draw_rect(k, Color(0.16, 0.12, 0.10), true)
	draw_rect(k.grow(2.0), SIG_KO.darkened(0.25), false, 3.0)
	# A tűz fénye: egynél világosabb szín, hogy a ragyogásban túlcsorduljon.
	draw_rect(Rect2(k.position.x + 3.0, k.position.y + 5.0, k.size.x - 6.0,
		k.size.y - 7.0), Color(2.2, 1.05, 0.30), true)
	draw_circle(k.get_center() + Vector2(0, 2.0), 4.0, Color(2.6, 1.7, 0.6, 0.75))
	# Üllő: tömb + szarv.
	var u := Vector2(_size.x * 0.26, wall.end.y - 4.0)
	draw_rect(Rect2(u.x - 7.0, u.y - 4.0, 14.0, 4.0), SIG_VAS, true)
	draw_rect(Rect2(u.x - 3.0, u.y - 8.0, 6.0, 4.0), SIG_VAS.lightened(0.15), true)
	draw_rect(Rect2(u.x - 5.0, u.y - 10.0, 12.0, 3.0), SIG_VAS.lightened(0.25), true)
	# Vizesdézsa.
	draw_rect(Rect2(u.x + 12.0, u.y - 9.0, 10.0, 9.0), Color(0.42, 0.30, 0.18), true)
	draw_rect(Rect2(u.x + 13.0, u.y - 8.0, 8.0, 3.0), Color(0.34, 0.52, 0.62), true)

# AKADÉMIA: oszlopos előcsarnok háromszögű oromzattal és lépcsővel.
func _sig_academy(foot: Rect2, wall: Rect2) -> void:
	var w := _size.x * 0.72
	var bal := -w * 0.5
	var also := wall.end.y - 6.0
	var felso := wall.position.y + wall.size.y * 0.30
	# Oromzat
	draw_colored_polygon([Vector2(bal - 4.0, felso), Vector2(0.0, felso - 14.0),
		Vector2(bal + w + 4.0, felso)], Color(0.86, 0.84, 0.78))
	draw_polyline([Vector2(bal - 4.0, felso), Vector2(0.0, felso - 14.0),
		Vector2(bal + w + 4.0, felso), Vector2(bal - 4.0, felso)],
		Color(0.30, 0.28, 0.24, 0.9), 1.5)
	# Architráv
	draw_rect(Rect2(bal - 3.0, felso, w + 6.0, 5.0), Color(0.90, 0.88, 0.82), true)
	# Oszlopok
	var db := 4
	for i in range(db):
		var x := bal + 4.0 + float(i) * (w - 8.0) / float(db - 1)
		draw_rect(Rect2(x - 3.0, felso + 5.0, 6.0, also - felso - 5.0),
			Color(0.92, 0.90, 0.85), true)
		draw_rect(Rect2(x - 4.0, felso + 5.0, 8.0, 3.0), Color(0.80, 0.78, 0.72), true)
		draw_rect(Rect2(x - 4.0, also - 3.0, 8.0, 3.0), Color(0.80, 0.78, 0.72), true)
		draw_line(Vector2(x + 2.0, felso + 8.0), Vector2(x + 2.0, also - 3.0),
			Color(0, 0, 0, 0.16), 1.0)
	# Lépcső
	for i in range(3):
		draw_rect(Rect2(bal - 5.0 - float(i) * 2.0, also + float(i) * 2.0,
			w + 10.0 + float(i) * 4.0, 2.0), Color(0.78, 0.76, 0.70), true)

# KASZÁRNYA: zászlórúd a kapu mellett, lándzsaállvány a falnál, palánk.
func _sig_barracks(foot: Rect2, wall: Rect2) -> void:
	# Zászlórúd a fél színével.
	var rx := wall.position.x + 10.0
	var teto := wall.position.y - 22.0
	draw_line(Vector2(rx, wall.end.y - 4.0), Vector2(rx, teto), SIG_FA, 2.0)
	draw_colored_polygon([Vector2(rx, teto), Vector2(rx + 16.0, teto + 5.0),
		Vector2(rx, teto + 10.0)], team_color)
	draw_polyline([Vector2(rx, teto), Vector2(rx + 16.0, teto + 5.0),
		Vector2(rx, teto + 10.0)], Color(0, 0, 0, 0.5), 1.0)
	# Lándzsaállvány: a falnak támasztott nyelek.
	var ax := _size.x * 0.20
	draw_rect(Rect2(ax - 2.0, wall.end.y - 6.0, 22.0, 3.0), SIG_FA, true)
	for i in range(4):
		var x := ax + float(i) * 5.5
		draw_line(Vector2(x, wall.end.y - 5.0), Vector2(x + 4.0, wall.end.y - 26.0),
			SIG_FA.lightened(0.1), 1.4)
		draw_circle(Vector2(x + 4.2, wall.end.y - 27.0), 1.6, SIG_VAS.lightened(0.2))
	# Palánk a talpnál: hegyezett karók.
	var px := foot.position.x + 2.0
	while px < foot.end.x - 2.0:
		draw_colored_polygon([Vector2(px, foot.end.y - 2.0),
			Vector2(px + 2.6, foot.end.y - 9.0), Vector2(px + 5.2, foot.end.y - 2.0)],
			SIG_FA.darkened(0.1))
		px += 7.0

# ISTÁLLÓ: széles kettős kapu patkóval, szénabálák, karámrúd.
func _sig_stable(foot: Rect2, wall: Rect2) -> void:
	var kw := _size.x * 0.38
	var kapu := Rect2(-kw * 0.5, wall.end.y - wall.size.y * 0.66, kw, wall.size.y * 0.62)
	draw_rect(kapu, Color(0.34, 0.22, 0.13), true)
	draw_rect(kapu, Color(0.16, 0.10, 0.06), false, 1.5)
	draw_line(Vector2(0.0, kapu.position.y), Vector2(0.0, kapu.end.y),
		Color(0.16, 0.10, 0.06), 1.5)
	# Vasalás: két keresztpánt.
	for s in [-1.0, 1.0]:
		draw_line(Vector2(float(s) * kw * 0.5, kapu.position.y + 3.0),
			Vector2(0.0, kapu.end.y - 3.0), Color(0.24, 0.22, 0.20, 0.8), 1.4)
	# Patkó a kapu fölött.
	var pk := Vector2(0.0, kapu.position.y - 7.0)
	draw_arc(pk, 5.0, PI * 0.15, PI * 0.85, 12, SIG_VAS.lightened(0.35), 2.2)
	# Szénabálák.
	for i in range(2):
		var b := Vector2(wall.end.x - 12.0 - float(i) * 13.0, wall.end.y - 6.0)
		draw_rect(Rect2(b.x - 5.0, b.y - 8.0, 11.0, 8.0), Color(0.78, 0.66, 0.30), true)
		draw_rect(Rect2(b.x - 5.0, b.y - 8.0, 11.0, 8.0), Color(0.52, 0.42, 0.18), false, 1.0)
	# Karámrúd a bal oldalon.
	var y := foot.end.y - 6.0
	draw_line(Vector2(foot.position.x + 2.0, y), Vector2(foot.position.x + 26.0, y),
		SIG_FA, 2.0)
	draw_line(Vector2(foot.position.x + 2.0, y - 6.0),
		Vector2(foot.position.x + 26.0, y - 6.0), SIG_FA, 2.0)

# KIKÖTŐ: pallósor a víz felé, cölöpök, daru és ládák.
func _sig_harbor(foot: Rect2, wall: Rect2) -> void:
	# Móló: deszkák a talp alatt, a part felé kinyúlva.
	var molo := Rect2(-_size.x * 0.34, foot.end.y - 2.0, _size.x * 0.68, 16.0)
	draw_rect(molo, Color(0.48, 0.36, 0.22), true)
	var x := molo.position.x
	while x < molo.end.x:
		draw_line(Vector2(x, molo.position.y), Vector2(x, molo.end.y),
			Color(0.32, 0.23, 0.14, 0.8), 1.0)
		x += 7.0
	draw_rect(molo, Color(0.22, 0.16, 0.10, 0.7), false, 1.0)
	# Kikötőbakok a móló két végén.
	for s in [-1.0, 1.0]:
		var bx: float = s * (_size.x * 0.34 - 3.0)
		draw_rect(Rect2(bx - 2.5, molo.position.y - 7.0, 5.0, 8.0), SIG_FA, true)
		draw_circle(Vector2(bx, molo.position.y - 7.0), 3.0, SIG_FA.lightened(0.15))
	# Daru: ferde gém kötéllel és horoggal.
	var tx := wall.end.x - 8.0
	var ty := wall.position.y + 4.0
	draw_line(Vector2(tx, wall.end.y - 4.0), Vector2(tx, ty), SIG_FA, 3.0)
	draw_line(Vector2(tx, ty), Vector2(tx + 18.0, ty + 8.0), SIG_FA, 2.5)
	draw_line(Vector2(tx + 18.0, ty + 8.0), Vector2(tx + 18.0, ty + 20.0),
		Color(0.22, 0.19, 0.14), 1.2)
	draw_rect(Rect2(tx + 15.0, ty + 20.0, 7.0, 6.0), Color(0.55, 0.42, 0.24), true)
	# Ládák a parton.
	draw_rect(Rect2(wall.position.x + 4.0, wall.end.y - 11.0, 11.0, 9.0),
		Color(0.56, 0.42, 0.24), true)
	draw_rect(Rect2(wall.position.x + 4.0, wall.end.y - 11.0, 11.0, 9.0),
		Color(0.30, 0.22, 0.14), false, 1.0)

# TORONY: lőrések a pártázat alatt.
func _sig_tower(wall: Rect2) -> void:
	for i in range(2):
		var y := wall.position.y + 10.0 + float(i) * 14.0
		if y > wall.end.y - 8.0: break
		draw_rect(Rect2(-2.0, y, 4.0, 9.0), Color(0.10, 0.09, 0.08), true)
		draw_rect(Rect2(-3.0, y - 1.0, 6.0, 2.0), Color(0.38, 0.36, 0.33), true)

# FŐVÁROS: saroktornyok pártázattal — a zászló már a tetőgerincen áll.
func _sig_hq(wall: Rect2, rr: Rect2) -> void:
	for s in [-1.0, 1.0]:
		var w := 13.0
		var x: float = s * (_size.x * 0.5 - w * 0.6) - w * 0.5
		var t := Rect2(x, rr.position.y + rr.size.y * 0.35, w, 0.0)
		t.size.y = wall.end.y - t.position.y
		draw_rect(t, _roof_base().lightened(0.5), true)
		draw_rect(t, Color(0.14, 0.11, 0.08, 0.85), false, 1.2)
		# Pártázat a torony tetején.
		for i in range(3):
			if i % 2 == 1: continue
			draw_rect(Rect2(t.position.x + float(i) * 4.5, t.position.y - 4.0,
				4.0, 5.0), _roof_base().lightened(0.35), true)
		draw_rect(Rect2(t.position.x + 4.0, t.position.y + 10.0, 4.0, 7.0),
			Color(0.12, 0.10, 0.08), true)

# Tetőtlen telek: szántóföld vagy betonfelület.
func _draw_flat(foot: Rect2, reveal: float) -> void:
	var plot := _below(foot, reveal)
	if plot.size.y <= 0.0: return
	if tipus == "farm":
		# Felszántott föld, barázdák és zöldellő vetés. (A fa-textúra ide
		# deszkapadlónak látszana, nem szántónak.)
		var soil := Color(0.46, 0.33, 0.19)
		draw_rect(plot, soil, true)
		var inner := foot.grow(-4.0)
		var rows := maxi(3, int(inner.size.y / 8.0))
		for i in range(rows):
			var y := inner.position.y + inner.size.y * (float(i) + 0.5) / rows
			if y < plot.position.y: continue
			# barázda árnyéka
			draw_line(Vector2(inner.position.x, y + 1.5),
				Vector2(inner.end.x, y + 1.5), soil.darkened(0.32), 4.0)
			# vetés: apró zöld csomók a soron
			var x := inner.position.x + 2.0
			while x < inner.end.x - 1.0:
				draw_rect(Rect2(x, y - 2.5, 3.0, 3.0), Color(0.40, 0.60, 0.22), true)
				draw_rect(Rect2(x, y - 3.5, 2.0, 2.0), Color(0.55, 0.75, 0.30), true)
				x += 6.0
		# Kerítés: oszlopok és két rúd a telek körül
		_draw_fence(foot)
	elif tipus == "sugar":
		# Cukornád-ültetvény: magas, zöld nádsorok a barna földön.
		draw_rect(plot, Color(0.42, 0.32, 0.20), true)
		var cane := Color(0.44, 0.66, 0.26)
		var cols := maxi(4, int(foot.size.x / 8.0))
		for i in range(cols):
			var x := foot.position.x + 4.0 + i * (foot.size.x - 8.0) / (cols - 1)
			if x < plot.position.x - 1.0: continue
			var top := maxf(plot.position.y, foot.position.y + 4.0)
			draw_line(Vector2(x, foot.end.y - 4.0), Vector2(x, top), cane, 2.0)
			draw_line(Vector2(x, top), Vector2(x - 3.0, top + 5.0),
				cane.lightened(0.18), 1.5)
			draw_line(Vector2(x, top + 2.0), Vector2(x + 3.0, top + 7.0),
				cane.darkened(0.15), 1.5)
		_draw_fence(foot)
	else:
		_draw_airfield(foot, plot)
	draw_rect(foot, Color(0, 0, 0, 0.30), false, 1.0)

func _draw_fence(foot: Rect2) -> void:
	var post := Color(0.55, 0.41, 0.24)
	draw_rect(foot, post, false, 2.0)
	var px := foot.position.x
	while px <= foot.end.x:
		draw_rect(Rect2(px - 1.0, foot.position.y - 3.0, 2.5, 6.0), post, true)
		draw_rect(Rect2(px - 1.0, foot.end.y - 3.0, 2.5, 6.0), post, true)
		px += 12.0

func _draw_airfield(foot: Rect2, plot: Rect2) -> void:
	_fill(plot, _wall_tex, _wall_src, Color(0.85, 0.85, 0.80))
	var cy := foot.position.y + foot.size.y * 0.5
	if cy < plot.position.y: return
	draw_rect(Rect2(foot.position.x, cy - 9.0, foot.size.x, 18.0),
		Color(0.22, 0.22, 0.24), true)
	var x := foot.position.x + 8.0
	while x < foot.end.x - 12.0:
		draw_rect(Rect2(x, cy - 1.5, 10.0, 3.0), Color(0.92, 0.92, 0.86), true)
		x += 20.0

# Állványzat az építkezés idejére.
func _draw_scaffold(box: Rect2) -> void:
	var beam := Color(0.58, 0.42, 0.25, 0.9)
	for i in range(4):
		var x := box.position.x + box.size.x * (0.06 + 0.29 * i)
		draw_line(Vector2(x, box.end.y), Vector2(x, box.position.y + 4.0), beam, 2.0)
	draw_line(Vector2(box.position.x, box.position.y + 6.0),
		Vector2(box.end.x, box.position.y + 6.0), beam, 2.0)
	draw_line(Vector2(box.position.x, box.end.y - box.size.y * 0.45),
		Vector2(box.end.x, box.end.y - box.size.y * 0.45), beam, 2.0)

func set_selected(val: bool) -> void:
	_selected = val
	queue_redraw()

func is_selected() -> bool:
	return _selected
