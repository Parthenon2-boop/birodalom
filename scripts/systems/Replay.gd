extends Node

# VISSZAJÁTSZÁS
#
# Az eredeti (index.html) a PARANCSOKAT naplózta, és a visszajátszás
# ugyanabból a magból, lépésről lépésre újraszámolta a játszmát. Ott ez
# működik: a szimuláció fix lépésközű, és minden véletlen a magból jön.
#
# A Godot-változat szimulációja NEM ilyen: a fizika és a navigáció
# képkockaidő-függő, a bot pedig a rendszer véletlenjéből dolgozik. Egy
# parancsnapló itt óhatatlanul szétcsúszna. Ezért a visszajátszás nem
# újraszámol, hanem FELVESZI, ami történt: másodpercenként nyolcszor
# elteszi a világ pillanatképét — pontosan azt a két számtömböt, amit a
# hálózati játszma is küld —, és lejátszáskor ugyanazzal a kóddal rakja
# vissza, amivel a hálózati társ rajzolja a világot.
#
# Fájl: user://replays/<idő>.brep — tömörítve (Zstd).
#   1. érték:  fejléc (dátum, mag, oldalak, korszak, nehézség, táj, hossz)
#   2. -tól:   képkockák [t, egységek, épületek, oldalak, vége, győztes]

const NetSyncScript = preload("res://scripts/systems/NetSync.gd")

const VERSION := 1
const HZ := 8.0                      # ennyi pillanatkép másodpercenként
const DIR := "user://replays"
const EXT := ".brep"

# --- Felvétel ---
var recording: bool = false
var _f: FileAccess = null
var _accum: float = 0.0
var _frames: int = 0
var _path: String = ""

# --- Lejátszás ---
var playing: bool = false
var speed: float = 1.0
var meta: Dictionary = {}
var _t: float = 0.0
var _next: Array = []                # a következő, még ki nem rakott képkocka
var _sync: Node = null               # a pillanatképeket ez rakja ki (NetSync)
var _finished: bool = false

signal playback_finished

static func dir_path() -> String:
	return DIR

static func list_files() -> Array:
	var out: Array = []
	DirAccess.make_dir_recursive_absolute(DIR)
	var d := DirAccess.open(DIR)
	if d == null: return out
	for f in d.get_files():
		if f.ends_with(EXT): out.append(DIR + "/" + f)
	out.sort()
	out.reverse()                     # a legfrissebb elöl
	return out

# A fájl fejléce felolvasás nélkül, a listához.
static func peek(path: String) -> Dictionary:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null: return {}
	var m = f.get_var()
	f.close()
	return m if m is Dictionary else {}

# ── FELVÉTEL ──────────────────────────────────────────────────

func start_recording() -> void:
	if recording: return
	DirAccess.make_dir_recursive_absolute(DIR)
	var ido := Time.get_datetime_dict_from_system()
	_path = "%s/%04d%02d%02d-%02d%02d%02d%s" % [DIR, ido["year"], ido["month"],
		ido["day"], ido["hour"], ido["minute"], ido["second"], EXT]
	_f = FileAccess.open_compressed(_path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if _f == null: return
	var oldalak: Array = []
	for s in GameState.oldalak:
		oldalak.append({"tipus": str(s.get("tipus", "bot")),
			"nemzet": str(s.get("nemzet", "hu")), "csapat": int(s.get("csapat", 0))})
	_f.store_var({
		"v": VERSION,
		"datum": Time.get_datetime_string_from_system(false, true),
		"mag": GameState.sim_mag,
		"oldalak": oldalak,
		"en_id": GameState.en_id,
		"kor": GameState.start_age,
		"diff": GameState.diff,
		"kaloz": GameState.pirate,
		"taj": GameState.map_type,
		"vilag": [GameState.WORLD_W, GameState.WORLD_H],
		"hz": HZ,
	}, true)
	recording = true
	_frames = 0
	_accum = 0.0

func _process(delta: float) -> void:
	if recording: _record_tick(delta)
	elif playing: _play_tick(delta)

func _record_tick(delta: float) -> void:
	if _f == null: return
	if not GameState.on and not GameState.over: return
	_accum += delta
	if _accum < 1.0 / HZ: return
	_accum = 0.0
	var sides: Array = []
	for s in GameState.oldalak:
		sides.append({"res": s.get("res", {}), "age": int(s.get("age", 0))})
	_f.store_var([GameState.t,
		NetSyncScript.snapshot_units(get_tree()),
		NetSyncScript.snapshot_builds(get_tree()),
		sides, GameState.over, GameState.winner], true)
	_frames += 1

# A felvétel lezárása. Visszaadja a fájl nevét ("" = nem volt felvétel).
func stop_recording() -> String:
	if not recording: return ""
	recording = false
	if _f != null:
		_f.close()
		_f = null
	# A pár képkockás felvétel semmit nem ér: azt eldobjuk.
	if _frames < int(HZ * 5.0):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
		return ""
	return _path

# ── LEJÁTSZÁS ─────────────────────────────────────────────────

func start_playback(path: String, main: Node) -> bool:
	_f = FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if _f == null: return false
	var m = _f.get_var()
	if not (m is Dictionary) or int((m as Dictionary).get("v", 0)) != VERSION:
		_f.close()
		_f = null
		return false
	meta = m
	# A pillanatképeket ugyanaz a kód rakja ki, mint a hálózati társnál.
	_sync = NetSyncScript.new(main)
	main.add_child(_sync)
	playing = true
	_finished = false
	_t = 0.0
	_next = _read_frame()
	return true

func _read_frame() -> Array:
	if _f == null or _f.eof_reached(): return []
	var v = _f.get_var()
	return v if v is Array and v.size() >= 6 else []

func _play_tick(delta: float) -> void:
	if _finished: return
	_t += delta * speed
	var kirakva := false
	while not _next.is_empty() and float(_next[0]) <= _t:
		_apply(_next)
		kirakva = true
		_next = _read_frame()
	if _next.is_empty() and kirakva:
		_end()

func _apply(frame: Array) -> void:
	if _sync == null or not is_instance_valid(_sync): return
	_sync.apply_snapshot(frame[1], frame[2], frame[3], float(frame[0]),
		bool(frame[4]), int(frame[5]))

func _end() -> void:
	_finished = true
	playing = false
	if _f != null:
		_f.close()
		_f = null
	playback_finished.emit()

func _exit_tree() -> void:
	if _f != null:
		_f.close()
		_f = null
