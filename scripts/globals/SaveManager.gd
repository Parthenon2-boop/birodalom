extends Node

# Mentés és betöltés.
#
# A mentés NEM a pálya pillanatképe: a világot a MAGBÓL állítjuk vissza
# (ugyanaz a mag ugyanazt a tájat adja), a felépített házak és a kiképzett
# sereg viszont nem őrződik meg. Ami megmarad: a játszma FAJTÁJA, az
# oldalak állapota (készlet, korszak, fejlesztések) és a küldetésmérők.
#
# Korábban ennél is kevesebb: a fajta sem. Egy kalózmentés folytatáskor
# sima csataként indult — rossz (kisebb) pályamérettel, hírnév nélkül —, a
# hadjárat-mentésből pedig eltűntek a tiltott épületek és a küldetésmérők.

const SAVE_PATH := "user://save.json"
const VERSION := "1.1"

func save_game() -> void:
	var data := {
		"version": VERSION,
		"start_age": GameState.start_age,
		"nation": GameState.nation,
		"diff": GameState.diff,
		"oldalak": GameState.oldalak,
		"t": GameState.t,
		"sim_mag": GameState.sim_mag,
		"en_id": GameState.en_id,
		# A JÁTSZMA FAJTÁJA. Enélkül a folytatás más játékot indít, mint
		# amit elmentettünk.
		"pirate": GameState.pirate,
		"tutorial": GameState.tutorial,
		"world_w": GameState.WORLD_W,
		"world_h": GameState.WORLD_H,
		"fame": GameState.fame,
		# Küldetésmérők és korlátozások — a hadjárat ezekből tudja, hol tart.
		"earned": GameState.earned,
		"kills": GameState.kills,
		"banned_buildings": GameState.banned_buildings,
		"hq_trains": GameState.hq_trains,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH): return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f: return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary): return false
	var d: Dictionary = data
	GameState.start_age = int(d.get("start_age", 0))
	GameState.nation    = str(d.get("nation", "hu"))
	GameState.diff      = int(d.get("diff", 0))
	GameState.t         = float(d.get("t", 0.0))
	GameState.sim_mag   = int(d.get("sim_mag", 0))
	GameState.pirate    = bool(d.get("pirate", false))
	GameState.tutorial  = bool(d.get("tutorial", false))
	GameState.fame      = float(d.get("fame", 0.0))
	GameState.kills     = int(d.get("kills", 0))
	GameState.earned    = _to_floats(d.get("earned", {}))
	GameState.banned_buildings = d.get("banned_buildings", [])
	GameState.hq_trains        = d.get("hq_trains", [])
	GameState.net_client = false
	# A pályaméret a fajtából következik. A régi (1.0-s) mentésekben nincs
	# benne, ezért onnan a kalóz-jelölőből számoljuk ki.
	var alap := GameState.WORLD_PIRATE if GameState.pirate else GameState.WORLD_BASE
	GameState.set_world_size(int(d.get("world_w", alap.x)),
		int(d.get("world_h", alap.y)))
	# A JSON sima Array-t ad vissza; a GameState.oldalak Array[Dictionary],
	# ezért elemenként kell átmásolni, különben típushiba lesz.
	GameState.oldalak.clear()
	for entry in d.get("oldalak", []):
		if entry is Dictionary:
			GameState.oldalak.append(_normalize_side(entry))
	GameState.en_id = clampi(int(d.get("en_id", 0)), 0,
		maxi(GameState.oldalak.size() - 1, 0))
	return true

# A JSON minden számot float-ként olvas vissza, az indexeket int-té alakítjuk.
func _normalize_side(entry: Dictionary) -> Dictionary:
	var o := entry.duplicate(true)
	for key in ["i", "csapat", "age", "wave"]:
		if o.has(key): o[key] = int(o[key])
	for key in ["waveT", "rate"]:
		if o.has(key): o[key] = float(o[key])
	# A fejlesztések: a régi mentésekben csak három kulcs volt, azóta több
	# van. A hiányzókat nullára pótoljuk, hogy a régi mentés is betöltsön.
	var upg: Dictionary = Upgrades.fresh()
	if o.has("upg") and o["upg"] is Dictionary:
		for key in o["upg"]:
			upg[key] = int(o["upg"][key])
	o["upg"] = upg
	if o.has("res") and o["res"] is Dictionary:
		for key in o["res"]:
			o["res"][key] = float(o["res"][key])
	return o

func _to_floats(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k in v: out[k] = float(v[k])
	return out

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func delete_save() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
