extends Node

# Teljesítmények. Minden bejegyzés egy MÉRŐSZÁMHOZ és egy célértékhez
# tartozik; a mérőszámok a játszmák között összeadódnak, és a
# user://achievements.json-ba mentődnek.
#
# A feliratok az assets/lang/*.json-ban vannak: "ach_<id>" a név,
# "ach_<id>_d" a leírás.

const PATH := "user://achievements.json"

const DEFS := [
	{"id": "elso_ver",     "stat": "kills",       "goal": 1},
	{"id": "hadvezer",     "stat": "kills",       "goal": 50},
	{"id": "epitesz",      "stat": "builds",      "goal": 10},
	{"id": "varosepito",   "stat": "builds",      "goal": 30},
	{"id": "favago",       "stat": "wood",        "goal": 2000},
	{"id": "bankar",       "stat": "gold",        "goal": 2000},
	{"id": "toborzo",      "stat": "trained",     "goal": 50},
	{"id": "admiralis",    "stat": "ships",       "goal": 5},
	{"id": "korszakvalto", "stat": "era",         "goal": 1},
	{"id": "modern_kor",   "stat": "era",         "goal": 3},
	{"id": "gyoztes",      "stat": "wins",        "goal": 1},
	{"id": "hodito",       "stat": "wins",        "goal": 5},
	{"id": "kalozkiraly",  "stat": "pirate_wins", "goal": 1},
	{"id": "hadjaro",      "stat": "missions",    "goal": 1},
	{"id": "birodalom",    "stat": "missions",    "goal": 11},
]

var stats: Dictionary = {}
var unlocked: Array = []

signal unlocked_one(id: String)

func _ready() -> void:
	load_progress()

# --- Mérőszámok ---

# Növeli a mérőszámot (ölés, épület, nyersanyag…), és kinyitja, ami elkészült.
func bump(stat: String, amount: float = 1.0) -> void:
	if amount <= 0.0: return
	stats[stat] = float(stats.get(stat, 0.0)) + amount
	_check(stat)

# Olyan mérőszámhoz, ahol a LEGJOBB érték számít (elért korszak).
func reach(stat: String, value: float) -> void:
	if value <= float(stats.get(stat, 0.0)): return
	stats[stat] = value
	_check(stat)

func value_of(stat: String) -> float:
	return float(stats.get(stat, 0.0))

func _check(stat: String) -> void:
	var uj := false
	for d in DEFS:
		if str(d["stat"]) != stat: continue
		var id := str(d["id"])
		if id in unlocked: continue
		if value_of(stat) >= float(d["goal"]):
			unlocked.append(id)
			uj = true
			unlocked_one.emit(id)
	if uj: save_progress()

# --- Lekérdezés a felülethez ---

func is_unlocked(id: String) -> bool:
	return id in unlocked

func progress(id: String) -> float:
	for d in DEFS:
		if str(d["id"]) != id: continue
		return clampf(value_of(str(d["stat"])) / maxf(float(d["goal"]), 1.0), 0.0, 1.0)
	return 0.0

func goal_of(id: String) -> float:
	for d in DEFS:
		if str(d["id"]) == id: return float(d["goal"])
	return 1.0

func current_of(id: String) -> float:
	for d in DEFS:
		if str(d["id"]) == id: return value_of(str(d["stat"]))
	return 0.0

func count_unlocked() -> int:
	return unlocked.size()

func title_of(id: String) -> String:
	return Lang.t("ach_" + id)

func desc_of(id: String) -> String:
	return Lang.t("ach_" + id + "_d")

# --- Mentés ---

func save_progress() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify({"stats": stats, "unlocked": unlocked}, "\t"))
	f.close()

func load_progress() -> void:
	if not FileAccess.file_exists(PATH): return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null: return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if not d is Dictionary: return
	var s = d.get("stats", {})
	if s is Dictionary:
		stats = {}
		for k in s: stats[str(k)] = float(s[k])
	var u = d.get("unlocked", [])
	if u is Array:
		unlocked = []
		for k in u: unlocked.append(str(k))

func reset() -> void:
	stats = {}
	unlocked = []
	save_progress()
