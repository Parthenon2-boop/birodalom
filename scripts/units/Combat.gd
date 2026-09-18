class_name Combat
extends RefCounted

# Harci segédfüggvények: hatótáv, látótáv, újratöltés, célpontkeresés.

const MELEE_RANGE := 32.0

# Az eredeti UNITS tábla `range` és `r` értékei.
const RANGE := {
	"worker":    16.0,
	"melee":     [18.0, 18.0, 18.0, 34.0],
	"ranged":    [115.0, 135.0, 165.0, 155.0],
	"spear":     [26.0, 28.0, 28.0, 130.0],
	"cav":       20.0,
	# A papnál ez nem ütéstáv, hanem a SZÓ hatótávja: ennyiről tudja
	# megszólítani az ellenség katonáját. (Nulla volt, ezért a térítés
	# sosem indult volna el: a pap örökké közeledett volna.)
	"priest":    [95.0, 105.0, 115.0, 125.0],
	"spy":       18.0,
	"ram":       26.0,
	"hero":      20.0,
	"siege":     [190.0, 220.0, 260.0, 300.0],
	"medic":     0.0,
	"fisher":    40.0,
	"warship":   [130.0, 155.0, 185.0, 210.0],
	"galleon":   [160.0, 190.0, 225.0, 255.0],
	"transport": 60.0,
	"fighter":   [0.0, 0.0, 0.0, 90.0],
	"bomber":    [0.0, 0.0, 0.0, 70.0],
}

# Testsugár — az egység alatti gyűrű és a kikerülés mérete (UNITS.r).
const RADIUS := {
	"worker": 8.0, "melee": [11.0, 11.0, 11.0, 15.0], "ranged": 9.0, "spear": 10.0,
	"cav": 15.0, "priest": 9.0, "spy": 9.0, "ram": 14.0, "hero": 12.0,
	"siege": 13.0, "medic": 9.0, "fisher": 13.0, "warship": 17.0,
	"galleon": 20.0, "transport": 15.0, "fighter": 12.0, "bomber": 15.0,
}

static func radius_for(role: String, age: int) -> float:
	var v: Variant = RADIUS.get(role, 9.0)
	if v is Array: return float(v[clampi(age, 0, 3)])
	return float(v)

const VISION := {
	"worker": 110.0, "melee": 130.0, "ranged": 190.0, "spear": 125.0,
	"cav": 165.0, "priest": 140.0, "spy": 240.0, "ram": 110.0,
	"hero": 175.0, "siege": 230.0, "medic": 140.0, "fisher": 150.0,
	"warship": 210.0, "galleon": 240.0, "transport": 160.0,
	"fighter": 300.0, "bomber": 260.0,
}

const COOLDOWN := {
	"worker": 1.6, "melee": 1.2, "ranged": 1.6, "spear": 1.4,
	"cav": 1.1, "priest": 2.4, "spy": 1.0, "ram": 3.0,
	"hero": 1.0, "siege": 3.4, "medic": 2.0, "fisher": 1.8,
	"warship": 2.2, "galleon": 2.8, "transport": 2.0,
	"fighter": 0.8, "bomber": 2.6,
}

static func range_for(role: String, age: int) -> float:
	var v: Variant = RANGE.get(role, MELEE_RANGE)
	if v is Array: return float(v[clampi(age, 0, 3)])
	return float(v)

# --- Gyógyítás ---
#
# Két szerepkör állítja talpra a sebesülteket, más-más módon:
#
#   PAP     — nem célzottan dolgozik: aki a közelében van, az lassan
#             felépül. Cserébe a hatósugara nagy.
#   FELCSER — egyesével kezel, viszont sokkal gyorsabban. Magától megkeresi
#             a legsúlyosabb sebesültet és odamegy hozzá.
#
# Az érték életerő MÁSODPERCENKÉNT, korszakonként.
const HEAL := {
	"priest": [2.4, 2.8, 3.2, 3.6],
	"medic":  [5.0, 6.5, 8.0, 10.0],
}

const HEAL_RANGE := {"priest": 150.0, "medic": 60.0}

# A felcser ekkora körben keres magának sebesültet (a hatótávon túl is,
# hiszen oda tud menni).
const MEDIC_SEARCH := 220.0

# Frissen kapott seb nem kötözhető: aki ennyi másodpercen belül találatot
# kapott, még a tűzvonalban áll. Enélkül a harcoló egységek életereje
# folyamatosan visszatöltődne, és a csata sosem dőlne el.
const HEAL_COMBAT_DELAY := 3.0

# Térítés: ennyi másodperc egyhuzamban tartott ráhatás kell hozzá,
# korszakonként. A későbbi korok szónokai gyorsabban dolgoznak.
const CONVERT_TIME := [8.0, 7.5, 7.0, 6.5]

# A saját bázisuk közelében nehezebb meggyőzni az embereket: ennyiszeres
# tempóval halad a térítés, ha a célpont menedéket adó épület mellett áll.
const CONVERT_RESIST := 0.5
const CONVERT_SHELTER_R := 330.0

# --- A hős aurája ---
#
# A hős nemcsak erős harcos: a körülötte küzdők NAGYOBBAT ÜTNEK és jobban
# bírják. Az eredeti `auraR / auraDmg / auraArmor` mezői.
const AURA_RANGE := 170.0
const AURA_DAMAGE := 0.15    # +15% sebzés a hős közelében
const AURA_ARMOR := 1.0      # +1 páncél
# A hős ennyi másodpercenként osztja szét a bátorítást, és ennyi ideig tart.
# Így nem minden egység keresgél hőst minden ütésnél — egy hős jár körbe,
# nem kétszáz katona kérdezget.
const AURA_PERIOD := 0.4
const AURA_HOLD := 0.7

# --- A kém álruhája ---
#
# A kém fegyvertelen és törékeny, viszont az ellenség színeit viseli: nem
# lőnek rá, be lehet vele sétálni az idegen földre. Az ŐRTORONY leplezi le:
# ha a kém a tornya látókörébe ér, onnantól ő is célpont.
const SPY_EXPOSE_HOLD := 12.0     # ennyi ideig marad leleplezve
const SPY_CHECK_PERIOD := 0.5

static func can_heal(role: String) -> bool:
	return HEAL.has(role)

static func heal_for(role: String, age: int) -> float:
	var v: Array = HEAL.get(role, [])
	return 0.0 if v.is_empty() else float(v[clampi(age, 0, 3)])

static func heal_range_for(role: String) -> float:
	return float(HEAL_RANGE.get(role, 0.0))

static func convert_time_for(age: int) -> float:
	return CONVERT_TIME[clampi(age, 0, 3)]

static func vision_for(role: String, _age: int) -> float:
	return float(VISION.get(role, 120.0))

static func cooldown_for(role: String) -> float:
	return float(COOLDOWN.get(role, 1.2))

static func sound_for(role: String, age: int) -> String:
	if role == "ranged": return "arrow" if age <= 0 else "cannon"
	if role in ["siege", "warship", "galleon", "bomber", "fighter"]: return "cannon"
	return "sword"

# A megadott egységhez legközelebbi ellenséges egységet vagy épületet adja
# vissza a sugáron belül. Elsőbbséget kapnak az egységek.
# Ez a játék legforgalmasabb ciklusa: minden katona végigméri a pályát.
# Ezért itt minden fölösleges munkát kerülünk:
#   - a csapatszámot az egység MAGÁN tartja (`team`), így nincs szótár-
#     keresés a GameState-ben képpontonként,
#   - négyzetes távolsággal mérünk, tehát nincs gyökvonás,
#   - és először egy olcsó doboz-szűrés dobja ki a messzi célpontokat.
static func find_enemy(from: Node2D, radius: float) -> Node2D:
	var tree := from.get_tree()
	if tree == null: return null
	var my_team: int = from.team
	var p := from.global_position
	var best: Node2D = null
	var best_d := radius * radius
	for u in tree.get_nodes_in_group("units"):
		if u == from: continue
		if u.team == my_team: continue
		var q: Vector2 = u.global_position
		var dx := q.x - p.x
		if absf(dx) > radius: continue
		var dy := q.y - p.y
		if absf(dy) > radius: continue
		var d := dx * dx + dy * dy
		if d >= best_d: continue
		# Az álruhás kémre nem lőnek (az ellenség sajátjának nézi), a hajó
		# gyomrában utazóra pedig nem lehet — a hajót kell elsüllyeszteni.
		#
		# EZ A KÉT KÉRDÉS A DOBOZ-SZŰRÉS UTÁN ÁLL, nem előtte: metódushívás,
		# és a közeli célpontokra kell csak feltenni. Előrébb téve minden
		# egység MINDEN másikra meghívná — háromszáz katonánál ez önmagában
		# megfelezte a képsebességet.
		if u.disguised() or u.aboard(): continue
		best_d = d
		best = u
	if best != null: return best
	for b in tree.get_nodes_in_group("buildings"):
		if b.team == my_team: continue
		var q2: Vector2 = b.global_position
		var dx2 := q2.x - p.x
		if absf(dx2) > radius: continue
		var dy2 := q2.y - p.y
		if absf(dy2) > radius: continue
		var d2 := dx2 * dx2 + dy2 * dy2
		if d2 < best_d:
			best_d = d2
			best = b
	return best

# Sebzés módosító: az első típus a második ellen.
const COUNTERS := {
	"spear": {"cav": 1.85},
	"cav":   {"ranged": 1.55, "siege": 1.6},
	"ranged": {"spear": 1.25},
	"ram":   {"building": 3.0},
	"siege": {"building": 2.6},
}

static func damage_mult(attacker_role: String, defender_role: String) -> float:
	var t: Dictionary = COUNTERS.get(attacker_role, {})
	return float(t.get(defender_role, 1.0))
