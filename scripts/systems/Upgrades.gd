class_name Upgrades
extends RefCounted

# FEJLESZTÉSEK
#
# A `GameState.oldalak[i].upg` szótár régóta megvolt, és a Unit már szorzott
# is vele — csak épp SEMMI nem tudta megnövelni, így örökre nulla maradt.
# Ez a fájl adja hozzá a kutatást, és köti be a hatásokat.
#
# Két ház osztozik rajta:
#
#   KOVÁCSMŰHELY — ami a KATONÁT erősíti: fegyver, páncél, ellátmány.
#   AKADÉMIA     — ami a BIRODALMAT: termelés, építés, kiképzés, gyógyítás,
#                  látótáv, teherbírás, falak, kincstár.
#
# A korszakváltás nem teszi feleslegessé: a késői játék így sem áll meg ott,
# hogy mindenki elérte a 20. századot.

# A `per_age` ágakból annyi fokozat vehető meg, ahány korszakot elértél
# (15. században egy, 17.-ben kettő, és így tovább). Enélkül az első
# percben meg lehetne venni az egész ágat.
const UPG := {
	# --- Kovácsműhely ---
	"weapon":   {"hol": "smith",   "max": 3, "cost": {"gold": 120, "wood": 70}},
	"armor":    {"hol": "smith",   "max": 3, "cost": {"gold": 110, "stone": 100}},
	"supply":   {"hol": "smith",   "max": 3, "cost": {"food": 200, "gold": 70}},
	# --- Akadémia ---
	"yield":    {"hol": "academy", "max": 4, "per_age": true,
				 "cost": {"gold": 90, "wood": 120}},
	"labor":    {"hol": "academy", "max": 4, "per_age": true,
				 "cost": {"wood": 150, "stone": 90}},
	"drill":    {"hol": "academy", "max": 4, "per_age": true,
				 "cost": {"gold": 110, "food": 140}},
	"medicine": {"hol": "academy", "max": 3, "cost": {"gold": 140, "food": 180}},
	"optics":   {"hol": "academy", "max": 2, "cost": {"gold": 160, "stone": 90}},
	"storage":  {"hol": "academy", "max": 3, "cost": {"wood": 160, "stone": 110}},
	"masonry":  {"hol": "academy", "max": 3, "cost": {"stone": 200, "gold": 80}},
	"ledger":   {"hol": "academy", "max": 3, "cost": {"gold": 200, "wood": 100}},
}

# Ez a sorrend a felületen is, ÉS a hálózati parancsban is: ott a fejlesztés
# SORSZÁMKÉNT utazik, ezért a lista nem rendezhető át, csak bővíthető.
const ORDER := ["weapon", "armor", "supply",
	"yield", "labor", "drill", "medicine", "optics", "storage",
	"masonry", "ledger"]

# --- A hatások mértéke fokozatonként ---
const WEAPON_PER   := 0.12   # +12% sebzés
const ARMOR_PER    := 2.0    # +2 páncél: ennyit vesz le minden találatból
const SUPPLY_PER   := 0.12   # +12% életerő
const YIELD_PER    := 0.05   # +5% kitermelés
const LABOR_PER    := 0.05   # 5%-kal gyorsabb építkezés
const DRILL_PER    := 0.05   # 5%-kal gyorsabb kiképzés
const MEDICINE_PER := 0.20   # +20% gyógyítás
const OPTICS_PER   := 0.12   # +12% látótáv
const STORAGE_PER  := 0.20   # +20% rakomány
const MASONRY_PER  := 0.12   # +12% épület-életerő
const LEDGER_PER   := 0.04   # 4%-kal olcsóbb minden

# A páncél sosem nyeli el a teljes ütést: ennyi mindig átmegy rajta.
# Enélkül a késői páncél ellen a korai gyalogos ÁRTALMATLAN lenne, és az
# első korszakban indított játszma menthetetlenül elakadna.
const MIN_DAMAGE := 1.0

# A kincstár sem viheti nullába az árakat.
const LEDGER_FLOOR := 0.6

# Minden következő fokozat közel kétszer annyiba kerül, mint az előző.
const COST_STEP := 0.9

# --- Lekérdezések ---

static func list_for(tipus: String) -> Array:
	var out: Array = []
	for k in ORDER:
		if str((UPG[k] as Dictionary)["hol"]) == tipus: out.append(k)
	return out

static func researches(tipus: String) -> bool:
	return not list_for(tipus).is_empty()

static func level(owner_id: int, key: String) -> int:
	var side := GameState.get_side(owner_id)
	if side.is_empty(): return 0
	return int((side.get("upg", {}) as Dictionary).get(key, 0))

# Hány fokozat vehető meg MOST. A korszakhoz kötött ágaknál a korszak szab
# határt, a többinél a fokozatok száma.
static func cap(owner_id: int, key: String) -> int:
	var d: Dictionary = UPG.get(key, {})
	if d.is_empty(): return 0
	var m := int(d["max"])
	if not bool(d.get("per_age", false)): return m
	return mini(m, GameState.get_age(owner_id) + 1)

static func max_level(key: String) -> int:
	return int((UPG.get(key, {}) as Dictionary).get("max", 0))

static func cost(owner_id: int, key: String) -> Dictionary:
	var d: Dictionary = UPG.get(key, {})
	if d.is_empty(): return {}
	var mul := 1.0 + float(level(owner_id, key)) * COST_STEP
	var raw := {}
	for k in d["cost"]:
		raw[k] = int(round(float((d["cost"] as Dictionary)[k]) * mul))
	return scale_cost(owner_id, raw)

static func available(owner_id: int, key: String) -> bool:
	return UPG.has(key) and level(owner_id, key) < cap(owner_id, key)

# A kutatás AZONNALI: nincs sor, mint a kiképzésnél. A birodalmi döntés egy
# tollvonás — a fék az ára, nem az ideje.
static func research(owner_id: int, key: String) -> bool:
	if not available(owner_id, key): return false
	if not GameState.pay(owner_id, cost(owner_id, key)): return false
	var side := GameState.get_side(owner_id)
	var upg: Dictionary = side.get("upg", {})
	upg[key] = level(owner_id, key) + 1
	side["upg"] = upg
	reapply(owner_id)
	return true

# A PÁLYÁN LÉVŐ egységekre és épületekre is vonatkozik a friss fokozat, nem
# csak az ezután születőkre — különben a fejlesztés az első percekben semmit
# sem érne, és a játékos azt hinné, elvesztette a nyersanyagát.
static func reapply(owner_id: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return
	for u in tree.get_nodes_in_group("units"):
		if is_instance_valid(u) and int(u.owner_id) == owner_id:
			u.refresh_stats()
	for b in tree.get_nodes_in_group("buildings"):
		if is_instance_valid(b) and int(b.owner_id) == owner_id:
			b.refresh_stats()

# --- A hatások, ahogy a többi rendszer kéri őket ---

static func gather_mul(owner_id: int) -> float:
	return 1.0 + YIELD_PER * level(owner_id, "yield")

static func build_mul(owner_id: int) -> float:
	return 1.0 + LABOR_PER * level(owner_id, "labor")

# Kiképzési IDŐ szorzója: a gyorsabb kiképzés rövidebb időt jelent.
static func train_time_mul(owner_id: int) -> float:
	return 1.0 / (1.0 + DRILL_PER * level(owner_id, "drill"))

static func heal_mul(owner_id: int) -> float:
	return 1.0 + MEDICINE_PER * level(owner_id, "medicine")

static func vision_mul(owner_id: int) -> float:
	return 1.0 + OPTICS_PER * level(owner_id, "optics")

static func carry_mul(owner_id: int) -> float:
	return 1.0 + STORAGE_PER * level(owner_id, "storage")

static func building_hp_mul(owner_id: int) -> float:
	return 1.0 + MASONRY_PER * level(owner_id, "masonry")

static func damage_mul(owner_id: int) -> float:
	return 1.0 + WEAPON_PER * level(owner_id, "weapon")

static func hp_mul(owner_id: int) -> float:
	return 1.0 + SUPPLY_PER * level(owner_id, "supply")

static func armor_of(owner_id: int) -> float:
	return ARMOR_PER * float(level(owner_id, "armor"))

# Számvitel: minden egység és épület olcsóbb. Fölfelé kerekítünk, hogy a
# kedvezmény sose csináljon ingyen épületet egy egyforintos tételből.
static func scale_cost(owner_id: int, c: Dictionary) -> Dictionary:
	var lv := level(owner_id, "ledger")
	if lv <= 0: return c
	var f := maxf(LEDGER_FLOOR, 1.0 - LEDGER_PER * float(lv))
	var out := {}
	for k in c:
		out[k] = int(ceil(float(c[k]) * f))
	return out

# Minden fejlesztés nullára állítva — ezzel indul minden oldal.
static func fresh() -> Dictionary:
	var d := {}
	for k in ORDER:
		d[k] = 0
	return d
