extends Node

# Játékbeállítások: grafika és hang. A user://options.json-ba mentődnek,
# tehát a következő indításkor megmaradnak. (A nyelv külön fájlban van,
# a Lang autoloadnál — így a kettő nem írja felül egymást.)
#
# Használat:  Settings.set_music_on(false)   Settings.fullscreen  stb.

const PATH := "user://options.json"

# --- Hang ---
var music_on  : bool  = true
var sfx_on    : bool  = true
var music_vol : float = 0.6
var sfx_vol   : float = 0.8
# --- Grafika ---
var fullscreen : bool = false
var vsync      : bool = true
var fps_limit  : int  = 60      # 0 = korlátlan
# Részletesség: 0 = alacsony (régi, gyenge gépre), 1 = közepes, 2 = magas.
# A KÖZEPES az eddigi kinézet, ezért az az alapérték. Az alacsony lekapcsolja
# a folyamatosan mozgó apróságokat (kéményfüst, úszó halak), ritkítja a köd
# és a minimap frissítését, és egyszerűbb talajrajzot kér.
# FONTOS: a beállítás sosem érinti a VILÁG tartalmát (fák, lelőhelyek
# száma), különben hálózati játékban szétcsúsznának a gépek.
var detail : int = 1
# Jár-e az idő (eső, hó, köd, tengeri vihar). A látvány és a szimuláció is
# ezen múlik; gyenge gépen vagy zavaró látványnál kikapcsolható.
var weather_on : bool = true
# Nappal-éjszaka ciklus (index.html 17/B). Kikapcsolva örök délelőtt van.
var day_night  : bool = true
# RAGYOGÁS (bloom): a tűz, a torkolattűz és a lámpák túlcsordulnak
# (index.html 16/D). Teljes képernyős utómunka, ezért gyenge gépen
# kikapcsolható — a takarékos fokozat magától le is veszi.
var bloom      : bool = true

# --- BILLENTYŰKIOSZTÁS  (index.html 26/C) ---
#
# A gyorsbillentyűk nem lehetnek beégetve: ami magyar kiosztáson kényelmes,
# az németen (y/z csere) vagy francia AZERTY-n használhatatlan. Ezért
# TÁBLÁZAT dönti el, és a táblázat a beállításokban átírható.
#
# Mi NEM állítható, és miért:
#   Esc, Tab, Enter, szóköz, nyilak — a felület szerkezetéhez tartoznak
#   W A S D                        — a kamera mozgatása
#   F11, F12                       — a rendszer is ismeri őket
#
# A választás a JÁTÉKOSHOZ tartozik, nem a világhoz: hálózaton nem megy át,
# és játszmánként sem változik.
const KEY_ACTIONS := [
	{"k": "ep_farm",     "alap": KEY_F, "csoport": "kb_epites"},
	{"k": "ep_house",    "alap": KEY_L, "csoport": "kb_epites"},
	{"k": "ep_barracks", "alap": KEY_K, "csoport": "kb_epites"},
	{"k": "ep_stable",   "alap": KEY_G, "csoport": "kb_epites"},
	{"k": "ep_tower",    "alap": KEY_T, "csoport": "kb_epites"},
	{"k": "ep_harbor",   "alap": KEY_Y, "csoport": "kb_epites"},
	{"k": "ep_temple",   "alap": KEY_M, "csoport": "kb_epites"},
	{"k": "ep_market",   "alap": KEY_R, "csoport": "kb_epites"},
	{"k": "ep_goldmine", "alap": KEY_B, "csoport": "kb_epites"},
	{"k": "ep_smith",    "alap": KEY_V, "csoport": "kb_epites"},
	{"k": "ep_academy",  "alap": KEY_U, "csoport": "kb_epites"},
	{"k": "ep_hospital", "alap": KEY_J, "csoport": "kb_epites"},
	{"k": "allas_aggro", "alap": KEY_1, "csoport": "kb_harc"},
	{"k": "allas_hold",  "alap": KEY_2, "csoport": "kb_harc"},
	{"k": "allas_flee",  "alap": KEY_3, "csoport": "kb_harc"},
	{"k": "toltet_golyo",   "alap": KEY_4, "csoport": "kb_harc"},
	{"k": "toltet_lancos",  "alap": KEY_5, "csoport": "kb_harc"},
	{"k": "toltet_kartacs", "alap": KEY_6, "csoport": "kb_harc"},
	{"k": "alakzat_line",   "alap": KEY_7, "csoport": "kb_harc"},
	{"k": "alakzat_wedge",  "alap": KEY_8, "csoport": "kb_harc"},
	{"k": "alakzat_square", "alap": KEY_9, "csoport": "kb_harc"},
	{"k": "megall",    "alap": KEY_X,      "csoport": "kb_parancs"},
	{"k": "korszak",   "alap": KEY_E,      "csoport": "kb_parancs"},
	{"k": "tetlen",    "alap": KEY_PERIOD, "csoport": "kb_parancs"},
	{"k": "csatakialtas", "alap": KEY_Q,   "csoport": "kb_parancs"},
	{"k": "fotomod",   "alap": KEY_O,      "csoport": "kb_parancs"},
]

# Amit nem engedünk hozzárendelni: a felület és a kamera billentyűi.
const KEY_TILTOTT := [KEY_ESCAPE, KEY_TAB, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE,
	KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_A, KEY_S, KEY_D,
	KEY_F11, KEY_F12]

# akció -> billentyűkód. Csak az ALAPTÓL ELTÉRŐ választások kerülnek bele.
var keys: Dictionary = {}

func key_of(action: String) -> int:
	if keys.has(action): return int(keys[action])
	for a in KEY_ACTIONS:
		if str(a["k"]) == action: return int(a["alap"])
	return 0

# Melyik akcióhoz tartozik ez a billentyű? (Egy billentyű több akciót is
# vihet — az építés és a harci állás sosem ütközik, mert más helyzetben
# érvényes —, ezért listát adunk vissza.)
func actions_of(keycode: int) -> Array:
	var ki: Array = []
	for a in KEY_ACTIONS:
		if key_of(str(a["k"])) == keycode: ki.append(str(a["k"]))
	return ki

func set_key(action: String, keycode: int) -> bool:
	if keycode in KEY_TILTOTT: return false
	keys[action] = keycode
	save_options()
	changed.emit()
	return true

func reset_keys() -> void:
	keys.clear()
	save_options()
	changed.emit()

# Ahogy a gombon megjelenik.
static func key_label(keycode: int) -> String:
	if keycode == 0: return "—"
	return OS.get_keycode_string(keycode)

signal changed

func _ready() -> void:
	load_options()
	apply_all()

# --- Alkalmazás ---

func apply_all() -> void:
	apply_audio()
	apply_video()

func apply_audio() -> void:
	SFX.set_music_on(music_on)
	SFX.set_sfx_on(sfx_on)
	SFX.set_music_volume(music_vol)
	SFX.set_sfx_volume(sfx_vol)

func apply_video() -> void:
	# Fejlesztői (headless) futásnál nincs ablak, amit állítani lehetne,
	# és a képsebesség-korlát is csak lassítaná az ellenőrzést.
	if DisplayServer.get_name() == "headless": return
	Engine.max_fps = maxi(0, fps_limit)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN \
		if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED \
		if vsync else DisplayServer.VSYNC_DISABLED)

# --- Egy-egy beállítás ---

func set_music_on(on: bool) -> void:
	music_on = on
	SFX.set_music_on(on)
	_done()

func set_sfx_on(on: bool) -> void:
	sfx_on = on
	SFX.set_sfx_on(on)
	_done()

func set_music_vol(v: float) -> void:
	music_vol = clampf(v, 0.0, 1.0)
	SFX.set_music_volume(music_vol)
	_done()

func set_sfx_vol(v: float) -> void:
	sfx_vol = clampf(v, 0.0, 1.0)
	SFX.set_sfx_volume(sfx_vol)
	_done()

func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply_video()
	_done()

func set_vsync(on: bool) -> void:
	vsync = on
	apply_video()
	_done()

func set_fps_limit(v: int) -> void:
	fps_limit = maxi(0, v)
	apply_video()
	_done()

func set_detail(v: int) -> void:
	detail = clampi(v, 0, 2)
	_done()

# Mozognak-e a folyamatos apróságok (füst, halraj)?
func lively() -> bool:
	return detail >= 1

# A képernyőn kívüli apróságok (füst, halraj) nem mozognak. Méréshez
# kikapcsolható a `--nocull` kapcsolóval — így látszik, mennyit ér.
var cull_offscreen: bool = true

# A közvetítő gép címe a hálózati játékhoz (pl. "kozvetito.gep.hu:27020").
# Egyszer beírod, és megmarad.
var relay_address: String = ""

func set_relay_address(s: String) -> void:
	relay_address = s.strip_edges().substr(0, 60)
	save_options()

# --- A többjátékos lobbi mezői (a Heptarchia lobbijához hasonlóan
# megjegyezzük őket: a nevet, a kaput és a legutóbbi címet) ---
var player_name: String = ""
var net_port: int = 27015
var last_address: String = ""

func set_player_name(s: String) -> void:
	player_name = s.strip_edges().substr(0, 18)
	save_options()

func set_net_port(v: int) -> void:
	net_port = clampi(v, 1024, 65535)
	save_options()

func set_last_address(s: String) -> void:
	last_address = s.strip_edges().substr(0, 60)
	save_options()

# Hány másodpercenként számoljuk újra a ködöt.
func fog_interval() -> float:
	return 0.1 if detail >= 1 else 0.22

func _done() -> void:
	save_options()
	changed.emit()

# --- Mentés / betöltés ---

func save_options() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify({
		"music_on": music_on, "sfx_on": sfx_on,
		"music_vol": music_vol, "sfx_vol": sfx_vol,
		"fullscreen": fullscreen, "vsync": vsync, "fps_limit": fps_limit,
		"detail": detail, "relay": relay_address,
		"weather": weather_on, "day_night": day_night, "bloom": bloom,
		"keys": keys,
		"player_name": player_name, "net_port": net_port,
		"last_address": last_address,
	}, "\t"))
	f.close()

func load_options() -> void:
	if not FileAccess.file_exists(PATH): return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null: return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if not d is Dictionary: return
	music_on   = bool(d.get("music_on", music_on))
	sfx_on     = bool(d.get("sfx_on", sfx_on))
	music_vol  = float(d.get("music_vol", music_vol))
	sfx_vol    = float(d.get("sfx_vol", sfx_vol))
	fullscreen = bool(d.get("fullscreen", fullscreen))
	vsync      = bool(d.get("vsync", vsync))
	fps_limit  = int(d.get("fps_limit", fps_limit))
	detail     = clampi(int(d.get("detail", detail)), 0, 2)
	weather_on = bool(d.get("weather", weather_on))
	day_night  = bool(d.get("day_night", day_night))
	bloom      = bool(d.get("bloom", bloom))
	# A billentyűkiosztás: csak az alaptól eltérő választások vannak benne.
	keys = {}
	var mentett = d.get("keys", {})
	if mentett is Dictionary:
		for k in mentett: keys[str(k)] = int(mentett[k])
	relay_address = str(d.get("relay", relay_address))
	player_name  = str(d.get("player_name", player_name))
	net_port     = clampi(int(d.get("net_port", net_port)), 1024, 65535)
	last_address = str(d.get("last_address", last_address))
