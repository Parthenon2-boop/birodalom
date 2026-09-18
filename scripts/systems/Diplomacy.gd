extends Node

# DIPLOMÁCIA  (index.html: 29/F)
#
# Több fél esetén szövetséget lehet ajánlani és felmondani:
#
#   AJÁNLAT     — elküldöd; ha a másik VISSZAAJÁNL, megköttetik a szövetség.
#                 Az ajánlat egy idő után lejár.
#   FELMONDÁS   — nem azonnali: visszaszámlálás indul, és csak annak
#                 leteltével lesz újra ellenség a másik. Így nem lehet
#                 orvul, egy kattintással hátba támadni.
#   A BOTOK     — nem tárgyalnak hosszan: ha szorongatják őket (kevesebb
#                 katonájuk van az átlagnál), elfogadják a segítséget.
#
# A szövetség a csapatszámot írja felül: a GameState.hostile() ezt kérdezi.

const AJANLAT_IDO := 45.0        # ennyi ideig él egy ajánlat
const FELMONDAS_IDO := 20.0      # ennyi múlva szűnik meg a szövetség
const BOT_KOZ := 6.0             # a bot ennyi másodpercenként válaszol

var main: Node = null
# kulcs ("a-b", a<b) -> igaz, ha szövetségesek
var szovetseg: Dictionary = {}
# kulcs -> {"tol": fél, "t": hátralévő idő}
var ajanlat: Dictionary = {}
# kulcs -> hátralévő idő a felmondásig
var felmondas: Dictionary = {}

signal changed

var _bot_t := BOT_KOZ

func _init(m: Node = null) -> void:
	main = m

func _ready() -> void:
	name = "Diplomacy"
	if main == null: main = get_tree().get_first_node_in_group("main")

static func kulcs(a: int, b: int) -> String:
	return "%d-%d" % [mini(a, b), maxi(a, b)]

# Szövetségesek-e (a csapatszámon FELÜL kötött szövetség miatt)?
func allied(a: int, b: int) -> bool:
	return bool(szovetseg.get(kulcs(a, b), false))

func _valid(fel: int) -> bool:
	return fel >= 0 and fel < GameState.oldalak.size()

# --- Ajánlat ---
func offer(tol: int, kinek: int) -> void:
	if tol == kinek or not _valid(tol) or not _valid(kinek): return
	var k := kulcs(tol, kinek)
	# Ha a MÁSIK már ajánlott nekünk, ez az elfogadás.
	var a: Dictionary = ajanlat.get(k, {})
	if not a.is_empty() and int(a.get("tol", -1)) == kinek:
		ajanlat.erase(k)
		felmondas.erase(k)
		szovetseg[k] = true
		_uzen(tol, kinek, "dipl_szovetseg_kotve")
		changed.emit()
		return
	ajanlat[k] = {"tol": tol, "t": AJANLAT_IDO}
	_uzen(tol, kinek, "dipl_ajanlva")
	changed.emit()

# --- Felmondás ---
func denounce(tol: int, kinek: int) -> void:
	if tol == kinek or not _valid(tol) or not _valid(kinek): return
	var k := kulcs(tol, kinek)
	ajanlat.erase(k)
	if felmondas.has(k): return              # már fut a visszaszámlálás
	if not allied(tol, kinek): return        # nem is voltunk szövetségesek
	felmondas[k] = FELMONDAS_IDO
	_uzen(tol, kinek, "dipl_felmondva")
	changed.emit()

func _uzen(a: int, b: int, kulcs_szoveg: String) -> void:
	var en := GameState.en_id
	if a != en and b != en: return
	if main == null or main.hud == null: return
	var masik := b if a == en else a
	main.hud.show_toast("%s — %s" % [Lang.t(kulcs_szoveg),
		Style.nation_name(str(GameState.get_side(masik).get("nemzet", "de")))], 4.0)

func _process(delta: float) -> void:
	if not GameState.on or GameState.net_client: return
	# Az ajánlatok lejárnak.
	for k in ajanlat.keys():
		var a: Dictionary = ajanlat[k]
		a["t"] = float(a["t"]) - delta
		if float(a["t"]) <= 0.0:
			ajanlat.erase(k)
			changed.emit()
	# A felmondás beérik.
	for k in felmondas.keys():
		felmondas[k] = float(felmondas[k]) - delta
		if float(felmondas[k]) <= 0.0:
			felmondas.erase(k)
			szovetseg[k] = false
			var r: PackedStringArray = str(k).split("-")
			if r.size() == 2:
				_uzen(int(r[0]), int(r[1]), "dipl_szovetseg_vege")
			changed.emit()
	_bot_tick(delta)

# A BOTOK VÁLASZA: a szorongatott bot elfogadja a segítséget.
func _bot_tick(delta: float) -> void:
	_bot_t -= delta
	if _bot_t > 0.0: return
	_bot_t = BOT_KOZ
	for k in ajanlat.keys():
		var a: Dictionary = ajanlat[k]
		var r: PackedStringArray = str(k).split("-")
		if r.size() != 2: continue
		var tol := int(a.get("tol", -1))
		var masik := int(r[0]) if int(r[0]) != tol else int(r[1])
		var o := GameState.get_side(masik)
		if o.is_empty() or str(o.get("tipus", "bot")) != "bot": continue
		# Mennyi katonája van az átlaghoz képest?
		var sajat := 0
		var ossz := 0
		var felek := 0
		for i in range(GameState.oldalak.size()):
			var n := 0
			for u in get_tree().get_nodes_in_group("units"):
				if is_instance_valid(u) and int(u.owner_id) == i and u.role != "worker":
					n += 1
			ossz += n
			felek += 1
			if i == masik: sajat = n
		var atlag := float(ossz) / maxf(float(felek), 1.0)
		if float(sajat) < atlag * 0.8:
			offer(masik, tol)                # a bot nevében válaszolunk
