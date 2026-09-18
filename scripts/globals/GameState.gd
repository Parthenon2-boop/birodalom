extends Node

# === Világ ===
#
# A pálya mérete játszmánként változik: a kalózvilág jóval nagyobb, mert
# ott a tenger a játéktér. Ezért ezek NEM állandók — mindig a
# set_world_size() állítja őket, sosem kézzel.
const WORLD_BASE := Vector2i(3400, 2400)
const WORLD_PIRATE := Vector2i(5780, 4080)

var WORLD_W: int = WORLD_BASE.x
var WORLD_H: int = WORLD_BASE.y
const FOG_CELL: int = 32

func set_world_size(w: int, h: int) -> void:
	WORLD_W = w
	WORLD_H = h

# === Játékállapot ===
var start_age: int = 0
var nation: String = "hu"
var on: bool = false
var over: bool = false
var t: float = 0.0
var sim_mag: int = 0
var diff: int = 0
var pirate: bool = false
var winner: int = -1        # a gyoztes oldal indexe, -1 = meg tart a játék
# Oktatómód: a bot nem támad, és a HUD lépésről lépésre vezet végig.
var tutorial: bool = false
# Hálózati játszma: a szimuláció a HÁZIGAZDA gépén fut. A csatlakozó
# semmit nem szimulál, csak a kapott pillanatképet rajzolja ki.
var net_client: bool = false

# === TÁJ (pályatípus) ===
#
# Az eredeti tízféle tája közül melyiken játszunk: "mezo", "erdo", "kopar",
# "sivatag", "folyok", "tavak", "hegy", "puszta", "szigetek". A kalózvilág
# mindig a rögzített "karib" térképet kapja, a hadjárat küldetései pedig
# megmondhatják a magukét. A leírásuk a WorldGen.MAPS táblában áll.
var map_type: String = "mezo"

# === VISSZAJÁTSZÁS ===
# Ha ki van töltve, a Main nem játszmát indít, hanem lejátssza ezt a
# felvételt (user://replays/*.brep). A menü tölti ki indítás előtt.
var replay_path: String = ""

# === Küldetésmérők (a hadjárat céljaihoz) ===
# `earned`: mennyit termelt ki ÖSSZESEN a játékos — nem a raktárkészlet,
# hanem a bevétel, különben a költekezés visszavenné a haladást.
# `kills`: hány ellenséges egységet/épületet semmisített meg.
var earned: Dictionary = {}
var kills: int = 0
# A küldetés tilthat épületeket, és átteheti a képzést a fővárosba.
var banned_buildings: Array = []
var hq_trains: Array = []

# === Hírnév (csak a kalózvilágban) ===
#
# A zsákmány hírnevet hoz, a hírnév viszont a nyakadra hozza a királyi
# hajóhadat. Ha eléri a maximumot, kifut a flotta, és a mérő visszaesik.
const FAME_MAX: float = 100.0
const FAME_DECAY: float = 0.35      # ennyivel csillapodik percenként
var fame: float = 0.0

signal fame_changed(value: float)
signal royal_fleet                 # a királyi hajóhad kifutott

func add_fame(amount: float) -> void:
	if not pirate or not on: return
	fame = clampf(fame + amount, 0.0, FAME_MAX * 1.4)
	fame_changed.emit(fame)
	if fame >= FAME_MAX:
		fame = FAME_MAX * 0.55
		royal_fleet.emit()
		fame_changed.emit(fame)

func fame_tick(delta: float) -> void:
	if not pirate or fame <= 0.0: return
	fame = maxf(0.0, fame - FAME_DECAY * delta / 60.0)
	fame_changed.emit(fame)

# === OLDALAK ===
var oldalak: Array[Dictionary] = []
var en_id: int = 0

signal resources_changed
signal era_changed(owner_id: int, new_age: int)

const RES_MUL: Array[float] = [1.0, 1.9, 3.1, 4.6]

func new_game(nation_key: String, chosen_age: int,
			  pirate_mode: bool = false, taj: String = "") -> void:
	sim_mag = (Time.get_ticks_msec() ^ randi()) & 0x7FFFFFFF
	pirate = pirate_mode
	nation = nation_key
	# A táj: amit a menüben választottak; a kalózvilág mindig a Karib-tenger.
	map_type = "karib" if pirate_mode else (taj if taj != "" else map_type)
	# A kalózvilágban nincs korszakváltás: végig a vitorlások korában
	# játszunk, és a pálya is jóval nagyobb, mert a tenger a játéktér.
	start_age = 1 if pirate else chosen_age
	if pirate:
		set_world_size(WORLD_PIRATE.x, WORLD_PIRATE.y)
	else:
		set_world_size(WORLD_BASE.x, WORLD_BASE.y)
	fame = 0.0
	tutorial = false
	net_client = false
	replay_path = ""
	on = true
	over = false
	winner = -1
	t = 0.0
	earned = {}
	kills = 0
	banned_buildings = []
	hq_trains = []
	oldalak.clear()
	en_id = 0
	add_oldal("ember", true, nation_key, 0, start_age)
	add_oldal("bot", false, _rival_of(nation_key), 1, start_age)
	if Campaign.active:
		_apply_mission(Campaign.current())

# A küldetés felülírja a kezdőállást: korszak, készletek, ellenfél, a bot
# erőssége, illetve a tiltott épületek és a fővárosi képzés.
func _apply_mission(m: Dictionary) -> void:
	if m.is_empty(): return
	var age := int(m.get("age", start_age))
	start_age = age
	var me := get_side(0)
	me["age"] = age
	var res: Dictionary = m.get("res", {})
	if not res.is_empty():
		var r := default_res(age)
		for k in res: r[k] = float(res[k])
		me["res"] = r
	var bot := get_side(1)
	bot["age"] = int(m.get("aiAge", age))
	bot["rate"] = float(m.get("aiRate", 1.0))
	bot["waveT"] = float(m.get("aiWave", 115.0))
	bot["res"] = default_res(int(bot["age"]))
	if m.has("enemy"): bot["nemzet"] = str(m["enemy"])
	# A küldetés megmondhatja a tájat is (a kalóz hadjáratok a Karib-tengeren).
	if m.has("map"): map_type = str(m["map"])
	banned_buildings = m.get("ban", [])
	hq_trains = m.get("hqTrains", [])

# A kalózvilágban egy másik kalózfrakció az ellenfél, egyébként a német bot.
func _rival_of(nation_key: String) -> String:
	if not pirate: return "de"
	for k in Style.PIRATE_ORDER:
		if k != nation_key: return k
	return "bb"

func add_oldal(tipus: String, helyi: bool, nemzet: String,
			   csapat: int, age: int) -> Dictionary:
	var o := {
		"i": oldalak.size(),
		"tipus": tipus,
		"helyi": helyi,
		"nemzet": nemzet,
		"csapat": csapat,
		"age": age,
		"res": default_res(age),
		"upg": Upgrades.fresh(),
		"wave": 0,
		"waveT": 115.0,
		"rate": 1.0,
		# Az alakzat félenként él: a gazdájáé számít, nem a helyi játékosé
		# (vonal / ék / négyszög — lásd Unit.form_mul).
		"formation": "line",
		# A hajóhad töltete: golyó / láncos / kartács (index.html 09/G).
		"toltet": "golyo",
	}
	oldalak.append(o)
	return o

func get_side(id: int = -1) -> Dictionary:
	var idx := en_id if id < 0 else id
	return oldalak[idx] if idx >= 0 and idx < oldalak.size() else {}

# --- Több fél egy pályán ---
#
# Az azonos csapatszámú oldalak SZÖVETSÉGESEK: nem támadják egymást, és
# együtt nyernek. Külön csapatszámmal mindenki mindenki ellen játszik.
func team_of(owner_id: int) -> int:
	var s := get_side(owner_id)
	return int(s.get("csapat", owner_id)) if not s.is_empty() else owner_id

# A DIPLOMÁCIA felülírja a csapatszámot: a menet közben kötött szövetség
# ugyanúgy véd, mint a közös csapat (scripts/systems/Diplomacy.gd).
var diplomacy: Node = null

func hostile(a: int, b: int) -> bool:
	if a == b: return false
	if diplomacy != null and is_instance_valid(diplomacy) and diplomacy.allied(a, b):
		return false
	return team_of(a) != team_of(b)

func allied(a: int, b: int) -> bool:
	return not hostile(a, b)

# Csata több féllel: a lista elemei {"tipus","nemzet","csapat"} szótárak,
# az első a helyi játékos. Innen épül fel az oldalak tömbje.
func new_battle(sides: Array, chosen_age: int,
				pirate_mode: bool = false, me: int = 0,
				seed_value: int = 0, taj: String = "") -> void:
	if sides.is_empty(): return
	me = clampi(me, 0, sides.size() - 1)
	var mine: Dictionary = sides[me]
	new_game(str(mine.get("nemzet", "hu")), chosen_age, pirate_mode, taj)
	# Hálózati játszmában a világnak minden gépen ugyanolyannak kell
	# lennie, ezért a magot a házigazda adja.
	if seed_value != 0: sim_mag = seed_value
	# A new_game két oldalt rak be (ember + bot); itt felülírjuk a listával.
	oldalak.clear()
	en_id = me
	for i in sides.size():
		var d: Dictionary = sides[i]
		add_oldal(str(d.get("tipus", "bot")), i == me,
			str(d.get("nemzet", "de")), int(d.get("csapat", i)), start_age)

# --- KIESÉS  (index.html 23/B) ---
#
# Egy fél akkor él még, ha van fővárosa, kaszárnyája VAGY munkása: amíg
# bármelyik megvan, van miből újraépítenie. Ugyanezt a mércét használja a
# ponttábla és a vereség is, hogy ne mondhasson kétfélét.
func side_alive(tree: SceneTree, i: int) -> bool:
	for b in tree.get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or int(b.owner_id) != i: continue
		if b.tipus == "hq" or b.tipus == "barracks": return true
	for u in tree.get_nodes_in_group("units"):
		if is_instance_valid(u) and int(u.owner_id) == i and u.role == "worker":
			return true
	return false

# A kiesetteket megjegyezzük: a ponttábla ebből tudja, kit húzzon át, és
# a kihirdetés is egyszer fut le félenként.
func mark_out(i: int) -> void:
	var s := get_side(i)
	if not s.is_empty(): s["kiesett"] = true

func is_out(i: int) -> bool:
	return bool(get_side(i).get("kiesett", false))

# Hány csapatnak van még fővárosa. Ebből dől el, vége van-e a játszmának.
func teams_with_hq(tree: SceneTree) -> Array:
	var out: Array = []
	for b in tree.get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or b.tipus != "hq": continue
		var t := team_of(int(b.owner_id))
		if not (t in out): out.append(t)
	return out

func get_age(owner_id: int = -1) -> int:
	return int(get_side(owner_id).get("age", 0))

func advance_era(owner_id: int) -> void:
	if pirate: return          # a kalózvilágban nincs korszakváltás
	var side := get_side(owner_id)
	if side.is_empty() or int(side["age"]) >= 3: return
	side["age"] = int(side["age"]) + 1
	if owner_id == en_id:
		Achievements.reach("era", float(side["age"]))
	era_changed.emit(owner_id, int(side["age"]))

func get_res(owner_id: int = -1) -> Dictionary:
	var side := get_side(owner_id)
	if side.is_empty(): return default_res(0)
	return side.get("res", default_res(0))

func add_res(owner_id: int, resource: String, amount: float) -> void:
	var res := get_res(owner_id)
	res[resource] = maxf(0.0, float(res.get(resource, 0.0)) + amount)
	# A hadjárat "gyűjts N aranyat" célja a BEVÉTELT méri, nem a készletet.
	if amount > 0.0 and owner_id == en_id:
		earned[resource] = float(earned.get(resource, 0.0)) + amount
		Achievements.bump(resource, amount)
	resources_changed.emit()

func pay(owner_id: int, costs: Dictionary) -> bool:
	var res := get_res(owner_id)
	for key in costs:
		if float(res.get(key, 0.0)) < float(costs[key]): return false
	for key in costs:
		res[key] = float(res[key]) - float(costs[key])
	resources_changed.emit()
	return true

func can_pay(owner_id: int, costs: Dictionary) -> bool:
	var res := get_res(owner_id)
	for key in costs:
		if float(res.get(key, 0.0)) < float(costs[key]): return false
	return true

func default_res(age: int) -> Dictionary:
	var mul: float = RES_MUL[clampi(age, 0, 3)]
	return {
		"wood":  float(int(500 * mul)),
		"stone": float(int(380 * mul)),
		"gold":  float(int(300 * mul)),
		"food":  float(int(420 * mul)),
		"coal":  float(int(150 * mul)) if age >= 2 and not pirate else 0.0,
		"rum":   80.0 if pirate else 0.0,
	}
