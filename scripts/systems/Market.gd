extends Node

# PIAC — nyersanyagcsere aranyért  (index.html: 7/B)
#
# Az árfolyam mozog: amiből sokat adsz el, annak esik az ára; amiből sokat
# veszel, annak nő. Az árak lassan visszatérnek az alapszinthez, tehát
# türelemmel jobb üzletet köthetsz.
#
# A piac nem ingyen dolgozik: eladásnál kevesebbet kapsz, mint amennyiért
# ugyanazt megvennéd — ez a rés a haszna.
#
# Kereskedni csak annak van joga, akinek ÁLL a piaca (market épület).

const UNIT := 100.0            # ennyi nyersanyagot cserélünk egyszerre
const SELL := 55.0             # 100 egységért ennyi arany alapáron
const BUY := 95.0              # 100 egység ennyi aranyba kerül
const STEP := 0.05             # egy üzlet ennyivel mozdítja az árat
const P_MIN := 0.45
const P_MAX := 2.2
const VISSZA := 0.02           # ennyivel húz vissza az alapszinthez másodpercenként
const RES := ["wood", "stone", "food", "coal"]

# Oldalanként külön árfolyam: mindenki a maga piacán kereskedik.
var prices: Dictionary = {}

signal prices_changed

func _ready() -> void:
	name = "Market"
	reset()

func reset() -> void:
	prices.clear()
	for i in maxi(GameState.oldalak.size(), 1):
		var p := {}
		for r in RES: p[r] = 1.0
		prices[i] = p

func _process(delta: float) -> void:
	if not GameState.on or GameState.net_client: return
	for i in prices.keys():
		var p: Dictionary = prices[i]
		for r in RES:
			p[r] = float(p[r]) + (1.0 - float(p[r])) * VISSZA * delta

func price_of(owner_id: int, res: String) -> float:
	if not prices.has(owner_id): reset()
	return float((prices.get(owner_id, {}) as Dictionary).get(res, 1.0))

func sell_price(owner_id: int, res: String) -> int:
	return maxi(1, int(round(SELL * price_of(owner_id, res))))

func buy_price(owner_id: int, res: String) -> int:
	return maxi(1, int(round(BUY * price_of(owner_id, res))))

# Áll-e piaca? (A kalózvilágban a kő helyén rummal is lehet kereskedni.)
func has_market(owner_id: int) -> bool:
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b): continue
		if int(b.owner_id) != owner_id: continue
		if b.tipus != "market": continue
		if not b.is_ready(): continue
		return true
	return false

# Eladás: UNIT nyersanyag -> arany. Visszaadja a kapott aranyat (0 = nem ment).
func sell(owner_id: int, res: String) -> int:
	if not has_market(owner_id): return 0
	var keszlet := GameState.get_res(owner_id)
	if float(keszlet.get(res, 0.0)) < UNIT: return 0
	var ar := sell_price(owner_id, res)
	GameState.add_res(owner_id, res, -UNIT)
	# Az add_res a BEVÉTELT is könyveli (a hadjárat "gyűjts N aranyat" célja
	# ezt méri), ezért külön nem kell hozzáadni.
	GameState.add_res(owner_id, "gold", float(ar))
	_move_price(owner_id, res, -STEP)
	return ar

# Vétel: arany -> UNIT nyersanyag. Visszaadja a kifizetett aranyat.
func buy(owner_id: int, res: String) -> int:
	if not has_market(owner_id): return 0
	var ar := buy_price(owner_id, res)
	var keszlet := GameState.get_res(owner_id)
	if float(keszlet.get("gold", 0.0)) < float(ar): return 0
	GameState.add_res(owner_id, "gold", -float(ar))
	GameState.add_res(owner_id, res, UNIT)
	_move_price(owner_id, res, STEP)
	return ar

func _move_price(owner_id: int, res: String, delta_p: float) -> void:
	if not prices.has(owner_id): reset()
	var p: Dictionary = prices[owner_id]
	p[res] = clampf(float(p.get(res, 1.0)) * (1.0 + delta_p), P_MIN, P_MAX)
	prices_changed.emit()
