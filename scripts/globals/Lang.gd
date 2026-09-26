extends Node

# Nyelvkezelő. A szövegek az assets/lang/<kód>.json fájlokban vannak,
# nem a kódban — új nyelvhez elég egy új JSON-t bemásolni és felvenni a
# CODES listába. A választás a user://settings.json-ba mentődik, így a
# következő indításkor megmarad.
#
# Használat:  Lang.t("fa")            -> "Fa" / "Wood" / "Holz"
#             Lang.t("sor_db") % [..] -> formázható sztringek

const DIR := "res://assets/lang/%s.json"
const SETTINGS := "user://settings.json"
const CODES := ["hu", "en", "de"]
const DEFAULT := "hu"

var code: String = DEFAULT
var _strings: Dictionary = {}
# Nyelvenként a zászlókód (a menü ebből rakja ki a lobogót).
var _flags: Dictionary = {}
var _names: Dictionary = {}

signal language_changed(new_code: String)

func _ready() -> void:
	_scan()
	set_language(_load_setting())

# Minden nyelvhez kiolvassuk a nevét és a zászlóját, hogy a menü fel
# tudja sorolni őket a szövegek betöltése nélkül is.
func _scan() -> void:
	for c in CODES:
		var d := _read(c)
		if d.is_empty(): continue
		_names[c] = str(d.get("_nyelv", c.to_upper()))
		_flags[c] = str(d.get("_zaszlo", c))

func _read(c: String) -> Dictionary:
	var path := DIR % c
	if not FileAccess.file_exists(path): return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}

# persist = false: csak erre a futásra (a fejlesztői --lang= kapcsoló ne írja
# felül a játékos mentett nyelvét).
func set_language(c: String, persist: bool = true) -> void:
	if not c in CODES: c = DEFAULT
	var d := _read(c)
	if d.is_empty() and c != DEFAULT:
		c = DEFAULT
		d = _read(c)
	code = c
	_strings = d
	if persist: _save_setting()
	language_changed.emit(code)

# A kulcs fordítása. Ismeretlen kulcsnál magát a kulcsot adja vissza —
# így a hiányzó fordítás rögtön látszik, de nem dől el a felület.
func t(key: String) -> String:
	return str(_strings.get(key, key))

func codes() -> Array:
	return CODES

func language_name(c: String) -> String:
	return str(_names.get(c, c.to_upper()))

func flag_of(c: String) -> String:
	return str(_flags.get(c, c))

# --- Beállítás mentése ---

func _load_setting() -> String:
	if not FileAccess.file_exists(SETTINGS): return DEFAULT
	var f := FileAccess.open(SETTINGS, FileAccess.READ)
	if f == null: return DEFAULT
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary: return str(d.get("lang", DEFAULT))
	return DEFAULT

func _save_setting() -> void:
	var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify({"lang": code}, "\t"))
	f.close()
