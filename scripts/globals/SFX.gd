extends Node

# Hangkezelő autoload.
#
# Három dolgot old meg, amit egyetlen AudioStreamPlayer nem tudna:
#
#  1. TÖBBSZÓLAMÚSÁG. Egy lejátszóból csak EGY hang szólhat: ha újra
#     elindítod, a régi elvágódik. Egy húszfős csatában így a kardcsattanás
#     folyamatos kattogássá silányul. Ezért szerepkörönként több lejátszót
#     tartunk (hangszálak), és körbejárva adjuk ki őket.
#
#  2. ÜTEMKORLÁT. Ha kétszáz katona egyszerre üt, kétszáz hang indulna egy
#     képkockán belül — ez nem csata, hanem zörej, és a keverő is beleremeg.
#     Hangonként megszabjuk, legfeljebb milyen sűrűn szólalhat meg.
#
#  3. HANGMAGASSÁG-SZÓRÁS. Ugyanaz a minta századszor is pontosan ugyanúgy
#     szólva gépfegyvernek hangzik. Az ismétlődő harci hangokat ezért
#     apró véletlen hangmagasság-eltéréssel indítjuk.

var _voices: Dictionary = {}        # hangnév -> AudioStreamPlayer tömb
var _next: Dictionary = {}          # hangnév -> a következő szál sorszáma
var _last_ms: Dictionary = {}       # hangnév -> mikor szólalt meg utoljára
var _have: Dictionary = {}          # hangnév -> van-e hozzá fájl
var _music: AudioStreamPlayer = null

# Fejlesztői (headless) futásnál nincs hangkimenet: a mintákat be sem
# töltjük. Egyrészt fölösleges memória és betöltési idő a méréseknél,
# másrészt a Dummy keverő sosem engedi el a lejátszás-objektumokat, és a
# motor kilépéskor „elszivárgott erőforrást” jelentene miattuk.
# A KÖNYVELÉS (ütemkorlát, szálválasztás) ilyenkor is fut, hogy az
# önellenőrzés érdemben mérhesse.
var _silent: bool = false

# A fájlok kiterjesztése vegyes: a szintetizált effektek .wav-ok, a felvett
# haláljajok .mp3-ak. Ezért nem a nevéhez kötjük a kiterjesztést, hanem
# megkeressük, melyik létezik.
const EXTS := [".wav", ".ogg", ".mp3"]

const SOUNDS := [
	"click", "age", "attack", "build", "death", "cannon", "sword", "arrow",
	# Felvett hangok. A halál háromféle, hogy ne ugyanaz a jaj ismétlődjön;
	# a becsapódás a lövedék célba érésekor szól.
	"halal1", "halal2", "halal3", "becsapodas",
]

# Hány egyszerre szóló szál jusson egy hangra. A harci hangok torlódnak,
# a felületi kattanás nem.
const VOICES := {
	"sword": 5, "arrow": 5, "cannon": 4, "attack": 4, "becsapodas": 4,
	"death": 3, "halal1": 2, "halal2": 2, "halal3": 2,
	"build": 3, "click": 2, "age": 1,
}
const DEFAULT_VOICES := 2

# Legalább ennyi másodperc teljen el két megszólalás között (0 = nincs korlát).
const MIN_GAP := {
	"sword": 0.045, "arrow": 0.05, "attack": 0.05, "cannon": 0.08,
	"becsapodas": 0.05, "build": 0.06,
	"death": 0.09, "halal1": 0.09, "halal2": 0.09, "halal3": 0.09,
}

# Hangmagasság-szórás (± arány).
const PITCH_VAR := {
	"sword": 0.14, "arrow": 0.13, "attack": 0.12, "cannon": 0.07,
	"becsapodas": 0.10, "build": 0.10,
	"death": 0.08, "halal1": 0.08, "halal2": 0.08, "halal3": 0.08,
}

func _ready() -> void:
	_silent = DisplayServer.get_name() == "headless"
	_ensure_bus("SFX")
	_ensure_bus("Music")
	for s in SOUNDS:
		var path := _find_file(s)
		_have[s] = path != ""
		var n: int = int(VOICES.get(s, DEFAULT_VOICES))
		var arr: Array[AudioStreamPlayer] = []
		for i in range(n):
			var p := AudioStreamPlayer.new()
			p.bus = "SFX"
			if not _silent and path != "":
				p.stream = load(path)
			add_child(p)
			arr.append(p)
		_voices[s] = arr
		_next[s] = 0
		_last_ms[s] = -100000
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)

# Megkeresi, melyik kiterjesztéssel van meg a hang. Üres szöveg = egyik sem;
# a játék ettől még elindul, csak néma marad az a hatás.
func _find_file(sound: String) -> String:
	for ext in EXTS:
		var path := "res://assets/audio/%s%s" % [sound, ext]
		if ResourceLoader.exists(path):
			return path
	return ""

# A projekt üres audio busokkal indul: ha nincs SFX/Music bus, létrehozzuk.
func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1: return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")

func play(sound: String, vol_db: float = 0.0) -> void:
	if not _voices.has(sound) or not bool(_have.get(sound, false)): return
	var arr: Array = _voices[sound]
	if arr.is_empty(): return

	var now := Time.get_ticks_msec()
	var gap: float = float(MIN_GAP.get(sound, 0.0))
	if gap > 0.0 and now - int(_last_ms[sound]) < int(gap * 1000.0):
		return
	_last_ms[sound] = now

	# Körbejárva adjuk ki a szálakat, de ha épp akad szabad, azt választjuk:
	# így egy hosszú hang (ágyú) nem vágja el önmagát idő előtt.
	var n: int = arr.size()
	var start: int = int(_next[sound])
	var pick: AudioStreamPlayer = arr[start]
	for i in range(n):
		var p: AudioStreamPlayer = arr[(start + i) % n]
		if not p.playing:
			pick = p
			start = (start + i) % n
			break
	_next[sound] = (start + 1) % n

	if _silent: return
	pick.volume_db = vol_db
	var var_amt: float = float(PITCH_VAR.get(sound, 0.0))
	pick.pitch_scale = 1.0 if var_amt <= 0.0 else randf_range(1.0 - var_amt, 1.0 + var_amt)
	pick.play()

# Egy hang a három haláljaj közül. Így a hívónak nem kell tudnia, hányféle van.
func play_death() -> void:
	play("halal%d" % (randi() % 3 + 1), -8.0)

# --- Zene ---
#
# A beállításokban mindig ott volt a „Zene be/ki" kapcsoló és a hangerő-
# csúszka, csak éppen a play_music() SEHONNAN nem hívódott meg, és
# zenefájl sem létezett — a kapcsoló semmit nem csinált.
#
# A hurkolást magunk intézzük: a szám végén újraindítjuk. (A WAV
# hurokjelölőjét az importbeállítás adná, ezt viszont a hangfájl mellett
# külön karban kellene tartani.)
var _music_path: String = ""

const MUSIC_MENU := "res://assets/audio/music_age0.wav"

func play_music(path: String, vol_db: float = -10.0) -> void:
	if _music == null: return
	# Ha már ez szól, nem kezdjük elölről: a korszakváltás és a jelenetváltás
	# különben minden alkalommal visszaugratná a zenét az elejére.
	if _music_path == path and _music.playing: return
	_music_path = path
	if _silent or not ResourceLoader.exists(path):
		_music.stop()
		return
	_music.stream = load(path)
	_music.volume_db = vol_db
	if not _music.finished.is_connected(_loop_music):
		_music.finished.connect(_loop_music)
	_music.play()

func _loop_music() -> void:
	if _music != null and _music.stream != null and not _silent:
		_music.play()

# A korszak zenéje. A menü a legkorábbi korszak dallamával szól.
func play_era_music(age: int) -> void:
	play_music("res://assets/audio/music_age%d.wav" % clampi(age, 0, 3))

func play_menu_music() -> void:
	play_music(MUSIC_MENU)

func stop_music() -> void:
	_music_path = ""
	if _music: _music.stop()

# Kilépéskor mindent elhallgattatunk, és elengedjük a hangmintákat. A
# keverő addig fogja a lejátszást, amíg a lejátszó a mintára hivatkozik;
# enélkül a motor „még használatban lévő erőforrást" jelent kilépéskor.
func _exit_tree() -> void:
	stop_all()
	stop_music()
	for arr in _voices.values():
		for p in arr:
			p.stream = null
	if _music: _music.stream = null

# Minden épp szóló hatás elnémítása — játszma végén, menübe lépéskor.
func stop_all() -> void:
	for arr in _voices.values():
		for p in arr:
			if p.playing: p.stop()


func set_sfx_on(on: bool) -> void:
	var idx := AudioServer.get_bus_index("SFX")
	if idx != -1: AudioServer.set_bus_mute(idx, not on)

func set_music_on(on: bool) -> void:
	var idx := AudioServer.get_bus_index("Music")
	if idx != -1: AudioServer.set_bus_mute(idx, not on)

# Hangerő 0..1 arányban; a busz decibelben dolgozik, ezért átváltjuk.
# A néma (0) állásnál -60 dB-t adunk, mert a linear2db a nullánál -inf.
func set_bus_volume(bus_name: String, value: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1: return
	var v := clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, -60.0 if v <= 0.001 else linear_to_db(v))

func set_sfx_volume(value: float) -> void:
	set_bus_volume("SFX", value)

func set_music_volume(value: float) -> void:
	set_bus_volume("Music", value)

# Van-e hangja ennek a hatásnak? (Az önteszt ezt kérdezi.) Fájl megléte
# alapján felel, nem a betöltött minta alapján — headless futásnál ugyanis
# szándékosan nem töltünk be semmit.
func has_sound(sound: String) -> bool:
	return bool(_have.get(sound, false))
