extends Node

# Hadjárat: nemzetenként egy küldetéssorozat. Az adatok az
# assets/campaign/campaigns.json-ban vannak (az eredeti index.html-ből
# kinyerve), a küldetésnevek és eligazítások angol/német fordítása pedig
# a kampany_<kód>.json fájlokban.
#
# A haladás a user://campaign.json-ba mentődik: nemzetenként hány
# küldetést vittél végig.

const DATA := "res://assets/campaign/campaigns.json"
const TEXT := "res://assets/campaign/kampany_%s.json"
const SAVE := "user://campaign.json"

# Melyik hadjáratok jelenjenek meg a menüben és milyen sorrendben.
const ORDER := ["hu", "at", "pl", "de", "es", "fr", "gb", "ru",
	"kaloz_ns", "kaloz_bb", "kaloz_sb"]

var data : Dictionary = {}      # nemzet -> küldetések tömbje
var _text : Dictionary = {}     # id -> {name, brief} a jelenlegi nyelven
var _done : Dictionary = {}     # nemzet -> hány küldetés kész

# A folyamatban lévő küldetés
var active : bool = false
var nation : String = ""
var index  : int = 0

func _ready() -> void:
	data = _read(DATA)
	_load_progress()
	_load_text()
	Lang.language_changed.connect(func(_c: String) -> void: _load_text())

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}

# A magyar szöveg magában az adatfájlban áll, a többi nyelv külön fájlban.
func _load_text() -> void:
	_text = {} if Lang.code == "hu" else _read(TEXT % Lang.code)

# --- Lekérdezések ---

func campaigns() -> Array:
	var out: Array = []
	for n in ORDER:
		if data.has(n) and (data[n] as Array).size() > 0:
			out.append(n)
	return out

func is_pirate(n: String) -> bool:
	return n.begins_with("kaloz_")

# A hadjárathoz tartozó nemzet kódja (a zászlóhoz és a nevekhez).
func nation_key(n: String) -> String:
	return n.substr(6) if is_pirate(n) else n

func missions(n: String) -> Array:
	return data.get(n, [])

func mission(n: String, i: int) -> Dictionary:
	var ms := missions(n)
	return ms[i] if i >= 0 and i < ms.size() else {}

func current() -> Dictionary:
	return mission(nation, index) if active else {}

func count(n: String) -> int:
	return missions(n).size()

func done(n: String) -> int:
	return int(_done.get(n, 0))

# Hány hadjáratot vitt végig a játékos (a teljesítményekhez).
func total_done() -> int:
	var n := 0
	for key in campaigns():
		if done(str(key)) >= count(str(key)): n += 1
	return n

# A soron következő küldetés sorszáma (a végigjátszott hadjárat elölről kezdhető).
func next_index(n: String) -> int:
	var d := done(n)
	return 0 if d >= count(n) else d

# --- Szövegek ---

func name_of(m: Dictionary) -> String:
	var t: Dictionary = _text.get(str(m.get("id", "")), {})
	return str(t.get("name", m.get("name", "")))

func brief_of(m: Dictionary) -> String:
	var t: Dictionary = _text.get(str(m.get("id", "")), {})
	return str(t.get("brief", m.get("brief", "")))

# A cél emberi nyelven, a jelenlegi állással együtt.
func objective_text(m: Dictionary, progress: int = -1) -> String:
	var o: Dictionary = m.get("obj", {})
	var t := str(o.get("type", ""))
	var s := ""
	match t:
		"build":
			s = Lang.t("cel_build") % [int(o.get("n", 0)),
				Lang.t("e_" + str(o.get("b", "")))]
		"buildAny": s = Lang.t("cel_buildany") % int(o.get("n", 0))
		"gather":
			s = Lang.t("cel_gather") % [int(o.get("amount", 0)),
				Lang.t(HUD_RES.get(str(o.get("res", "gold")), "arany"))]
		"kill":     s = Lang.t("cel_kill") % int(o.get("n", 0))
		"survive":  s = Lang.t("cel_survive") % int(o.get("sec", 0))
		"destroy":  s = Lang.t("cel_destroy")
		"age":      s = Lang.t("cel_age") % Lang.t("kor_nev_%d" % int(o.get("age", 1)))
		_:          s = t
	if progress >= 0 and t != "destroy":
		s += "   (%d/%d)" % [progress, target_of(m)]
	return s

const HUD_RES := {
	"wood": "fa", "stone": "ko", "gold": "arany", "food": "elelem",
	"coal": "szen", "rum": "rum",
}

func target_of(m: Dictionary) -> int:
	var o: Dictionary = m.get("obj", {})
	match str(o.get("type", "")):
		"build", "buildAny", "kill": return int(o.get("n", 0))
		"gather": return int(o.get("amount", 0))
		"survive": return int(o.get("sec", 0))
		"age": return int(o.get("age", 1))
	return 1

# --- Indítás és haladás ---

func start(n: String, i: int) -> void:
	nation = n
	index = clampi(i, 0, maxi(count(n) - 1, 0))
	active = data.has(n)

func stop() -> void:
	active = false
	nation = ""
	index = 0

func has_next() -> bool:
	return active and index + 1 < count(nation)

# A teljesített küldetés után lépünk, és mentjük a haladást.
func complete() -> void:
	if not active: return
	_done[nation] = maxi(done(nation), index + 1)
	_save_progress()

func advance() -> bool:
	if not has_next(): return false
	index += 1
	return true

# --- Mentés ---

func _load_progress() -> void:
	var d := _read(SAVE)
	_done = d.get("done", {}) if d.has("done") else {}

func _save_progress() -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify({"done": _done}, "\t"))
	f.close()

func reset_progress() -> void:
	_done = {}
	_save_progress()
