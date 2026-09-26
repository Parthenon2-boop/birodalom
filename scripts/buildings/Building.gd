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
	"house":    {"hp": [320, 420, 520, 700],     "pop": 5, "max": 10, "gold": [0.10, 0.16, 0.24, 0.32]},
	"harbor":   {"hp": [540, 660, 800, 960],     "trains": ["fisher", "warship", "galleon", "transport"], "shore": true, "drop": true},
	"temple":   {"hp": [560, 690, 830, 990],     "trains": ["priest"]},
	"goldmine": {"hp": [420, 520, 640, 780],     "gold": [0.8, 1.15, 1.6, 2.1]},
	"airfield": {"hp": [1, 1, 1, 1150],          "trains": ["fighter", "bomber"], "minAge": 3},
	# Cukornád-ültetvény: ebből lesz a rum, a kalózok fizetsége. A magyar
	# alföldön semmi keresnivalója, ezért csak a kalózvilágban építhető.
	"sugar":    {"hp": [380, 470, 580, 700],     "rum": [0.9, 1.2, 1.55, 1.9], "pirateOnly": true},
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

# A lábnyom (ütközés, építési hely). A rajz az eredeti méreteivel készül
# (HtmlEpulet.MERET), ez pár képponttal nagyobb.
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

# --- Kinézet ---
#
# Az épületek képe a böngészős eredetiből jön (lásd HtmlEpulet.gd és a fájl
# végén a rajzolást): a középkorban és a többi épületnél az eredeti
# PAINT-rajzok kisütött képe, a 17. századtól a hat alapépületnél az LPC
# gyarmati és viktoriánus rajz (assets/sprites/buildings).

# Korszakcsoport (régi hívók kedvéért marad meg).
static func era_group(a: int) -> int:
	if a <= 1: return 0
	return 1 if a == 2 else 2

# Típusszín. A RAJZ nem ebből dolgozik, de a minikártya, a kampányszerkesztő és a mentés-
# olvasó ebből mutatja meg egy pillantásra, miféle épület áll ott.
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
# A gazdája nemzete — ebből jön az építészet (a kép és a zászló).
var _nemzet      : String    = ""
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
		_elo_tick(delta)
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
	# A zászló lobogásához és a kéményfüsthöz ritka újrarajzolás elég.
	_elo_tick(delta)

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
	# A hozam KORSZAKONKÉNT nő. Korábban a bánya és a cukornád fix ütemben
	# termelt, ezért a késői játék gazdasága elsorvadt: a 20. századi tárna
	# ugyanannyit adott, mint egy 15. századi kézi vájat.
	for kulcs in ["food", "gold", "rum"]:
		if not st.has(kulcs):
			continue
		var m = st[kulcs]
		var ertek: float = float(m[a]) if m is Array else float(m)
		GameState.add_res(owner_id, kulcs, ertek * delta)

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

# --- RAJZ: A BÖNGÉSZŐS EREDETI SZERINT (index.html drawBuild) ---
#
# Az épület képe az eredeti PAINT-rajzaiból kisütött kép (a 17. századtól a
# hat alapépületnél az LPC gyarmati/viktoriánus rajz) — lásd HtmlEpulet.gd.
# A kép a Sprite2D gyerekcsomóponton ül (csapatszín-maszkkal), alatta a
# vetett árnyék és a hátsó állvány (ez a csomópont), fölötte az élő réteg
# (_felso): az első állvány, a lobogó zászló, a kéményfüst, a sérülés, a
# kellékek, az életcsík, a kijelölés és a gyülekezőpont.
#
# Méretek: az eredeti BUILDS.w/h és BH táblája (HtmlEpulet.MERET, .BH) — a
# rajzok ezekhez készültek. A kattintható lábnyom (BUILD_SIZE) ettől pár
# képponttal eltérhet, a játékszabály azt használja.
const HtmlEpulet := preload("res://scripts/buildings/HtmlEpulet.gd")

var _kep: Dictionary = {}
var _hw: Vector2 = Vector2(64, 64)
var _hh: float = 28.0
var _felso: Node2D = null
var _on_screen: bool = true
var _elo_redraw: float = 0.0

func _load_sprite() -> void:
	# A gazdája nemzete adja az építészetet (az eredeti stFor + natOverlay):
	# a magyar árkádos, a német favázas, az orosz hagymakupolás.
	_nemzet = GameState.nation_of(owner_id)
	_hw = HtmlEpulet.meret(tipus)
	_hh = HtmlEpulet.magassag(tipus, age)
	_kep = HtmlEpulet.kep(tipus, age, _nemzet)
	_flag_tex = null
	if tipus == "hq" or tipus == "barracks":
		var fp := Style.flag_path(_nemzet, age)
		if ResourceLoader.exists(fp):
			_flag_tex = load(fp)
	if sprite != null:
		sprite.material = null
		var mask: Variant = _kep.get("mask", null)
		if mask is Texture2D:
			sprite.material = HtmlEpulet.anyag(mask as Texture2D, team_color, team_accent)
	_ensure_felso()
	_frissit_kep()
	queue_redraw()

# Az élő réteg a kép FÖLÉ kerül (a gyerekek a szülő rajza után jönnek, és ez
# a csomópont a Sprite2D után áll a fában).
func _ensure_felso() -> void:
	if _felso != null: return
	_felso = Node2D.new()
	_felso.name = "Felso"
	_felso.draw.connect(_draw_felso)
	add_child(_felso)
	# Csak a képernyőn lévő épületek zászlaja lobog és kéménye füstöl.
	if not Settings.cull_offscreen: return
	var vis := VisibleOnScreenNotifier2D.new()
	vis.rect = Rect2(-_hw.x, -_hw.y - _hh - 60.0, _hw.x * 2.0, _hw.y * 2.0 + _hh + 60.0)
	vis.screen_entered.connect(func() -> void: _on_screen = true)
	vis.screen_exited.connect(func() -> void: _on_screen = false)
	add_child(vis)

# A kép beállítása: építés közben alulról felfelé nő ki (az eredeti a
# vásznat vágta: a talptól prog·(h+H) magasan látszik).
func _frissit_kep() -> void:
	if sprite == null: return
	if _kep.is_empty() or prog <= 0.0:
		sprite.visible = false
		return
	var tex: Texture2D = _kep["tex"]
	var r: Rect2 = _kep["rect"]
	var ts := Vector2(float(tex.get_width()), float(tex.get_height()))
	var sc := r.size / ts
	var ty0 := 0.0
	if prog < 1.0:
		var shown := (_hw.y + _hh) * clampf(prog, 0.0, 1.0)
		ty0 = clampf((_hw.y * 0.5 - shown - r.position.y) / sc.y, 0.0, ts.y)
	sprite.texture = tex
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.scale = sc
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0.0, ty0, ts.x, ts.y - ty0)
	sprite.position = r.position + Vector2(0.0, ty0 * sc.y)
	sprite.visible = ty0 < ts.y - 0.5

func _draw() -> void:
	# A rajz állapota (építés, kép) innen frissül: sok helyről csak a
	# queue_redraw() jön (sérülés, kijelölés, építés), a kép és az élő réteg
	# ehhez igazodik.
	call_deferred("_frissit_kep")
	if _felso != null: _felso.queue_redraw()
	HtmlEpulet.arnyek(self, _hw.x, _hw.y, _hh)
	if prog <= 0.0:
		HtmlEpulet.kituzott_telek(self, _hw.x, _hw.y)
	elif prog < 1.0:
		HtmlEpulet.allvany(self, _hw.x, _hw.y, _hh, false)

func _ido() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

# Élő réteg: ami a kép előtt van, és ami időben változik.
func _draw_felso() -> void:
	var ci := _felso
	var w := _hw.x
	var h := _hw.y
	var t := _ido()
	var p := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	if prog > 0.0 and prog < 1.0:
		HtmlEpulet.allvany(ci, w, h, _hh, true)
		# Építési csík: ugyanott és ugyanakkora, mint az életcsík.
		var cs := w * 0.8
		HtmlEpulet._rect(ci, -cs / 2, -h / 2 - _hh - 12, cs, 4, Color(0, 0, 0, 0.6))
		HtmlEpulet._rect(ci, -cs / 2 + 0.5, -h / 2 - _hh - 11.5,
			(cs - 1.0) * clampf(prog, 0.0, 1.0), 3, Color("d8b34a"))
	elif prog >= 1.0:
		if Settings.lively():
			for k in HtmlEpulet.kemenyek(tipus, age, w, h, _hh):
				var kk: Array = k
				HtmlEpulet.fust(ci, float(kk[0]), float(kk[1]), float(kk[2]), float(kk[3]), t)
		if (tipus == "hq" or tipus == "barracks") and _flag_tex != null:
			_draw_zaszlo(ci, t)
		HtmlEpulet.serules(ci, w, h, _hh, p, str(nid))
		HtmlEpulet.eges(ci, w, h, p, str(nid), t, global_position.x)
		HtmlEpulet.kellekek(ci, tipus, w, h)
		if p < 1.0:
			HtmlEpulet.eletcsik(ci, -h / 2 - _hh - 12, w * 0.8, p)
	if _selected:
		HtmlEpulet._szaggatott_teglalap(ci, Rect2(-w / 2 - 5, -h / 2 - 5, w + 10, h + 10),
			team_accent, 2.0, 6.0, 4.0)
	if owner_id == GameState.en_id and rally_set:
		_draw_rally(_selected)
	if not train_queue.is_empty() and prog >= 1.0:
		var left := prod_tmr.time_left
		var total := maxf(prod_tmr.wait_time, 0.001)
		var k2 := clampf(1.0 - left / total, 0.0, 1.0)
		HtmlEpulet._rect(ci, -21, h / 2 + 5, 42, 6, Color(0, 0, 0, 0.55))
		HtmlEpulet._rect(ci, -20, h / 2 + 6, 40.0 * k2, 4, team_accent)
		if train_queue.size() > 1:
			ci.draw_circle(Vector2(27, h / 2 + 8), 7.0, Color(0, 0, 0, 0.6))
			var font := ThemeDB.fallback_font
			if font != null:
				ci.draw_string(font, Vector2(20, h / 2 + 11.5), str(train_queue.size()),
					HORIZONTAL_ALIGNMENT_CENTER, 14.0, 9, Color("e8dcc0"))

# Zászló a tetőn (a főváros bal, a kaszárnya jobb sarkán): rövid rúd,
# lobogó nemzeti zászló, a rúd mentén a csapatszín.
func _draw_zaszlo(ci: Node2D, t: float) -> void:
	var fx := (-_hw.x / 2 + 9.0) if tipus == "hq" else (_hw.x / 2 - 9.0)
	var fy := -_hw.y / 2 - _hh - (12.0 if age == 0 else 4.0)
	ci.draw_line(Vector2(fx, fy + 4), Vector2(fx, fy - 15), Color("3a3128"), 2.0)
	ci.draw_circle(Vector2(fx, fy - 16), 2.0, Color("c9b27a"))
	var fazis := 0.0 if not Settings.lively() else t * 2.6 + float(nid) * 0.9
	HtmlEpulet.zaszlo(ci, _flag_tex, fx + 1.5, fy - 15, 26.0, fazis)
	HtmlEpulet._rect(ci, fx - 2.5, fy - 12, 5, 12, team_color)
	HtmlEpulet._rect(ci, fx - 2.5, fy - 12, 5, 2, Color(0, 0, 0, 0.3))

# Mozog-e valami a képen (zászló, füst, égés, képzés) — ekkor a _process
# ritkítva újrarajzolja az élő réteget.
func _elo_kell() -> bool:
	if prog < 1.0: return false
	if not train_queue.is_empty(): return true
	if not Settings.lively(): return false
	if (tipus == "hq" or tipus == "barracks") and _flag_tex != null: return true
	if hp < max_hp * 0.34: return true
	return not HtmlEpulet.kemenyek(tipus, age, _hw.x, _hw.y, _hh).is_empty()

func _elo_tick(delta: float) -> void:
	if _felso == null or not _on_screen: return
	if not _elo_kell(): return
	_elo_redraw += delta
	if _elo_redraw >= 0.1:
		_elo_redraw = 0.0
		_felso.queue_redraw()

# A gyülekezőpont zászlócskája (drawRally): halványan mindig látszik,
# kijelöléskor vonallal is.
func _draw_rally(strong: bool) -> void:
	var ci := _felso
	var to := rally.position
	var a := 0.75 if strong else 0.32
	if strong:
		HtmlEpulet._szaggatott(ci, Vector2.ZERO, to, Color(230.0 / 255.0, 215.0 / 255.0,
			160.0 / 255.0, 0.7 * a), 1.4, 4.0, 5.0)
	ci.draw_line(to, to + Vector2(0, -15), Color(0.227, 0.192, 0.157, a), 1.6)
	var c := team_accent
	match rally_kind():
		"node": c = Color("8a6234")
		"foe":  c = Color("c0392b")
	c.a = a
	ci.draw_colored_polygon(PackedVector2Array([to + Vector2(0, -15), to + Vector2(10, -11.5),
		to + Vector2(0, -8)]), c)

func set_selected(val: bool) -> void:
	_selected = val
	queue_redraw()

func is_selected() -> bool:
	return _selected
