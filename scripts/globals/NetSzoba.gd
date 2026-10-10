extends Node

# HARMADIK ÚT: SZOBA SZOBAKÓDDAL (WebRTC) — kapunyitás és saját közvetítő nélkül.
#
# A Heptarchia `net_szoba.gd`-jének logikája a Birodalomhoz igazítva:
#   – a házigazda szobát nyit, és kap egy HATBETŰS kódot (pl. K7P-QM4), ezt küldi el a társainak;
#   – a csatlakozó beírja a kódot; a két gép a kapcsolat felépítéséhez szükséges adatokat (SDP, ICE)
#     a Supabase Realtime „bir-<kód>” üzenetcsatornáján cseréli ki. Ez CSAK a jelzés: a játék
#     forgalma utána közvetlenül a gépek között megy (WebRTC adatcsatorna);
#   – a többi (lobbi, parancsok, pillanatkép) változatlanul a Net.gd-ben fut: a
#     WebRTCMultiplayerPeer ugyanúgy MultiplayerPeer, mint az ENet. A házigazda az 1-es
#     azonosító, a vendégek 2-től kapnak számot.
#
# MI KELL HOZZÁ
#   1. A gépen: a `webrtc-native` kiegészítő (addons/webrtc_native). Enélkül az `elerheto()`
#      hamis, és a menü a régi két utat kínálja.
#   2. A kiszolgálón: a Supabase-projekt CSAK PRIVÁT Realtime-csatornát enged, ezért a „bir-”
#      csatornákhoz külön szabály kell — lásd server/supabase/schema_birodalom_szoba.sql.
#      Amíg az nincs lefuttatva, a kiszolgáló mindenkit elutasít (szoba_nem_enged).
#   3. Belépés: ha a játék a ParthLauncherből, belépve indult (user://fiok.json), a csatornára a
#      fiók nevében lépünk be; fiók nélkül csak a nyilvános (anon) kulccsal — hogy ez elég-e,
#      azt a fenti szabály dönti el.
#
# KÖZVETÍTŐ (TURN) NINCS: csak nyilvános STUN-szervert használunk. Két szigorú hálózat
# (mobilnet–mobilnet, céges tűzfal) között ezért nem jön létre kapcsolat — nekik marad a
# Net.gd közvetítős (relay) útja.
#
# A jelzések (a csatornán JSON): {"r": "g" (házigazda) | "v" (vendég), "t": típus, "k": a vendég kulcsa, …}
#   v → g  "join" {v: protokoll}     csatlakozni szeretne (2 mp-enként ismétli, amíg választ nem kap)
#   g → v  "ok"   {id}               befogadva, ez lesz az azonosítója; utána jön az ajánlat
#   g → v  "nem"  {ok: nyelvi kulcs}  elutasítva (megtelt, más verzió, már fut a játék)
#   g ↔ v  "sdp"  {tipus, sdp}       a kapcsolat leírása (ajánlat / válasz)
#   g ↔ v  "ice"  {m, i, n}          kapcsolódási jelölt
#   g → g  "van" / "foglalt"         új szoba: foglalt-e már a kód (ritka egyezés esetén új kód)

signal kesz(kod: String)        # a házigazda szobája megnyílt / új kódot kapott
signal hiba(kulcs: String)      # a szoba vagy a csatlakozás nem sikerült (nyelvi kulcs)
signal vendeg_peer(peer: WebRTCMultiplayerPeer)   # a vendég azonosítót kapott: ez lesz a multiplayer_peer

const PROJEKT := "gxvepswtairfqvosdcpb.supabase.co"
const JELZO_URL := "wss://" + PROJEKT + "/realtime/v1/websocket"
## A Supabase-projekt NYILVÁNOS (anon) kulcsa — a launcher és a honlap is ezt használja, nem titok.
## (A `service_role` kulcs soha nem kerülhet ide.)
const ANON_KULCS := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd4dmVwc3d0YWlyZnF2b3NkY3BiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk4MzQyMzYsImV4cCI6MjEwNTQxMDIzNn0.9A86POfj49aRynE3rerz4nMbfds7xny6GLuRePpgSSI"
const TEMA := "bir-"
## Hat betű a Net.ALPHABET-ből (32^6 ≈ egymilliárd). A címet rejtő régi kódok 8 és 10 betűsek,
## így a hosszból egyértelmű, melyikről van szó.
const KOD_HOSSZ := 6
## Ha a pillanatkép vagy a parancsok formátuma változik, EZT növelni kell: a más verziójú
## játék így érthető üzenetet kap, nem pedig szétcsúszott világot.
const PROTOKOLL := 1
## Nyilvános STUN-szerverek: a gépek ezekből tudják meg a saját külső címüket.
const ICE_SZERVEREK := [{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302",
	"stun:stun.cloudflare.com:3478"]}]
const FIOK := "user://fiok.json"   # a ParthLauncher által írt belépés (lásd felho_mentes.gd)
const SZIVVERES_MP := 25.0      # a Realtime-kapcsolat életben tartása
const JOIN_ISMETLES_MP := 2.0
const SZOBA_KERES_MP := 15.0    # ennyi ideig keresi a vendég a szobát / vár a házigazda a jelzőcsatornára
const KAPCSOLODAS_MP := 30.0    # a befogadás után ennyi idő alatt kell felépülnie a közvetlen kapcsolatnak

enum Mod { NINCS, GAZDA, VENDEG }

var mod: int = Mod.NINCS
var kod: String = ""
var rtc: WebRTCMultiplayerPeer = null
## Fejlesztői próbához (scripts/dev/NetTest.gd) átírható egy helyi jelzőre. Ha nem a valódi
## kiszolgáló, a fiók belépőjét SOHA nem küldjük el.
var jelzo_url: String = JELZO_URL

var _ws: WebSocketPeer = null
var _topic: String = ""
var _bent: bool = false         # a csatornához csatlakozva (phx_join válasz megjött)
var _volt_bent: bool = false    # ebben a munkamenetben legalább egyszer sikerült
var _ref: int = 0
var _sziv: float = 0.0
var _ujra: float = -1.0         # házigazda: a megszakadt jelzőkapcsolat újranyitása ennyi mp múlva
var _menet: int = 0             # a folyamatban lévő nyitás sorszáma (a kései válaszok kiszűrésére)
var _token: String = ""         # a fiók belépője, ha van
var _csatlakozas_var: bool = false   # a websocket megnyílása után kell elküldeni a csatlakozást
# házigazda
var _vendegek: Dictionary = {}  # vendég kulcsa -> {"id": int, "conn": WebRTCPeerConnection, "ido": float, "kesz": bool}
var _kov_id: int = 2
var _kod_ellenorzes: float = 0.0
# vendég
var _kulcs: String = ""
var _conn: WebRTCPeerConnection = null
var _ido: float = 0.0           # mióta keresi a szobát / mióta kapcsolódik
var _join_ido: float = 0.0
var _befogadva: bool = false

## Van-e WebRTC ezen a gépen (a webrtc-native kiegészítő betöltött-e).
static func elerheto() -> bool:
	return ClassDB.class_exists("WebRTCLibPeerConnection")

## A beírt kód egységesítése (nagybetű, szóköz és kötőjel nélkül). Ha nem szobakód, üres.
func kod_tisztit(s: String) -> String:
	var r := ""
	for c in s.strip_edges().to_upper():
		if c == " " or c == "-": continue
		if Net.ALPHABET.find(c) < 0: return ""
		r += c
	return r if r.length() == KOD_HOSSZ else ""

func uj_kod() -> String:
	# A játék magja (seed) sokszor rögzített: a kódhoz külön, valódi véletlen kell.
	var b := Crypto.new().generate_random_bytes(KOD_HOSSZ)
	var r := ""
	for i in KOD_HOSSZ: r += Net.ALPHABET[b[i] % Net.ALPHABET.length()]
	return r

# ── Házigazda ──────────────────────────────────────────────────

## Szobát nyit: a WebRTC-házigazda (ezt a Net teszi multiplayer_peer-ré); a kód a `kesz` jelzéssel jön.
func gazda_nyit() -> WebRTCMultiplayerPeer:
	bezar()
	if not elerheto(): return null
	rtc = WebRTCMultiplayerPeer.new()
	if rtc.create_server() != OK:
		rtc = null
		return null
	mod = Mod.GAZDA
	kod = uj_kod()
	_ido = 0.0
	_jelzo_nyit()
	return rtc

# ── Vendég ─────────────────────────────────────────────────────

func vendeg_belep(szoba_kod: String) -> bool:
	bezar()
	if not elerheto() or kod_tisztit(szoba_kod) == "": return false
	mod = Mod.VENDEG
	kod = kod_tisztit(szoba_kod)
	_kulcs = Crypto.new().generate_random_bytes(8).hex_encode()
	_ido = 0.0
	_join_ido = JOIN_ISMETLES_MP
	_befogadva = false
	_jelzo_nyit()
	return true

# ── Közös ──────────────────────────────────────────────────────

## Minden lezárása (a Net.close hívja); a multiplayer_peer-t a Net zárja.
func bezar() -> void:
	_jelzo_zar()
	for k in _vendegek:
		var c: WebRTCPeerConnection = _vendegek[k]["conn"]
		if c != null and not bool(_vendegek[k]["kesz"]): c.close()
	_vendegek.clear()
	_conn = null
	rtc = null
	mod = Mod.NINCS
	kod = ""
	_kov_id = 2
	_ujra = -1.0
	_befogadva = false
	_volt_bent = false
	_token = ""

func _uj_kapcsolat(vendeg_kulcs: String) -> WebRTCPeerConnection:
	var c := WebRTCPeerConnection.new()
	if c.initialize({"iceServers": ICE_SZERVEREK}) != OK: return null
	# (Kötött függvény, nem névtelen: az a kapcsolatot magát fogná meg, és sosem szabadulna fel.)
	c.session_description_created.connect(_sdp_keszult.bind(vendeg_kulcs))
	c.ice_candidate_created.connect(_ice_keszult.bind(vendeg_kulcs))
	return c

func _kapcsolat(vendeg_kulcs: String) -> WebRTCPeerConnection:
	if mod == Mod.GAZDA:
		var v: Dictionary = _vendegek.get(vendeg_kulcs, {})
		return v.get("conn") as WebRTCPeerConnection
	return _conn

func _sdp_keszult(tipus: String, sdp: String, vendeg_kulcs: String) -> void:
	var c := _kapcsolat(vendeg_kulcs)
	if c == null: return
	c.set_local_description(tipus, sdp)
	_kuld({"t": "sdp", "k": vendeg_kulcs, "tipus": tipus, "sdp": sdp})

func _ice_keszult(m: String, i: int, n: String, vendeg_kulcs: String) -> void:
	_kuld({"t": "ice", "k": vendeg_kulcs, "m": m, "i": i, "n": n})

func _process(delta: float) -> void:
	if mod == Mod.NINCS: return
	if _ws != null:
		_ws.poll()
		match _ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				if _csatlakozas_var: _csatorna_be()
				while _ws != null and _ws.get_available_packet_count() > 0:
					_fogad(_ws.get_packet().get_string_from_utf8())
				_sziv += delta
				if _sziv >= SZIVVERES_MP:
					_sziv = 0.0
					_ws_kuld({"topic": "phoenix", "event": "heartbeat", "payload": {}, "ref": _uj_ref()})
			WebSocketPeer.STATE_CLOSED:
				_ws = null
				_bent = false
				if mod == Mod.GAZDA:
					_ujra = 3.0
				elif not _befogadva:
					_hiba("szoba_jelzes_hiba")
					return
	elif _ujra >= 0.0:
		_ujra -= delta
		if _ujra < 0.0: _jelzo_nyit()
	if mod == Mod.GAZDA: _gazda_lepes(delta)
	elif mod == Mod.VENDEG: _vendeg_lepes(delta)

func _gazda_lepes(delta: float) -> void:
	if not _volt_bent:
		# A szoba még meg sem nyílt: ha a jelzőcsatorna nem áll fel időben, nem várunk a végtelenségig.
		_ido += delta
		if _ido > SZOBA_KERES_MP:
			_hiba("szoba_jelzes_hiba")
			return
	if _kod_ellenorzes > 0.0:
		_kod_ellenorzes -= delta
	# A félbemaradt kapcsolódások takarítása; a felépülteket a WebRTCMultiplayerPeer viszi tovább.
	for k in _vendegek.keys():
		var v: Dictionary = _vendegek[k]
		if bool(v["kesz"]): continue
		var id := int(v["id"])
		if rtc != null and rtc.has_peer(id) and bool(rtc.get_peer(id).get("connected", false)):
			v["kesz"] = true
			continue
		v["ido"] = float(v["ido"]) + delta
		if float(v["ido"]) > KAPCSOLODAS_MP:
			if rtc != null and rtc.has_peer(id): rtc.remove_peer(id)
			_vendegek.erase(k)

## Hány vendég kapcsolódása van még folyamatban (a „megtelt” számításához).
func _fuggoben() -> int:
	var n := 0
	for k in _vendegek:
		if not bool(_vendegek[k]["kesz"]): n += 1
	return n

func _vendeg_lepes(delta: float) -> void:
	_ido += delta
	if not _befogadva:
		if _bent:
			_join_ido += delta
			if _join_ido >= JOIN_ISMETLES_MP:
				_join_ido = 0.0
				_kuld({"t": "join", "k": _kulcs, "v": PROTOKOLL})
		if _ido > SZOBA_KERES_MP:
			_hiba("szoba_nincs_ilyen")
		return
	if rtc == null: return
	if rtc.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		# A közvetlen kapcsolat él: a jelzőcsatornára nincs többé szükség.
		if _ws != null: _jelzo_zar()
	elif _ido > KAPCSOLODAS_MP:
		_hiba("szoba_nincs_kapcsolat")

func _hiba(kulcs: String) -> void:
	bezar()
	hiba.emit(kulcs)

# ── Jelzések fogadása ──────────────────────────────────────────

func _fogad(szoveg: String) -> void:
	var m: Variant = JSON.parse_string(szoveg)
	if typeof(m) != TYPE_DICTIONARY: return
	var ev := str(m.get("event", ""))
	if ev == "phx_reply" and str(m.get("topic", "")) == _topic and not _bent:
		var p: Dictionary = m.get("payload", {}) if typeof(m.get("payload")) == TYPE_DICTIONARY else {}
		if str(p.get("status", "")) != "ok":
			# A csatorna PRIVÁT: a kiszolgáló szabálya (RLS) dönti el, ki léphet be.
			var r := JSON.stringify(p).to_lower()
			if "authoriz" in r or "permission" in r or "privateonly" in r:
				_hiba("szoba_belepes_kell" if _token == "" else "szoba_nem_enged")
			else:
				_hiba("szoba_jelzes_hiba")
			return
		_bent = true
		_volt_bent = true
		if mod == Mod.GAZDA:
			# A kód foglaltságának ellenőrzése: ha egy másik házigazda válaszol, új kódot választunk.
			_kod_ellenorzes = 2.0
			_kuld({"t": "van"})
			kesz.emit(kod)
		return
	if (ev == "phx_error" or ev == "phx_close") and str(m.get("topic", "")) == _topic:
		# A kiszolgáló bezárta a csatornát (pl. lejárt belépő): a házigazda újra belép, a még
		# várakozó vendég feladja.
		_jelzo_zar()
		if mod == Mod.GAZDA: _ujra = 3.0
		elif not _befogadva: _hiba("szoba_jelzes_hiba")
		return
	if ev != "broadcast": return
	var b: Variant = m.get("payload", {})
	if typeof(b) != TYPE_DICTIONARY or typeof(b.get("payload")) != TYPE_DICTIONARY: return
	var j: Dictionary = b["payload"]
	if mod == Mod.GAZDA: _gazda_fogad(j)
	elif mod == Mod.VENDEG and str(j.get("r", "")) == "g": _vendeg_fogad(j)

func _gazda_fogad(j: Dictionary) -> void:
	var t := str(j.get("t", ""))
	if str(j.get("r", "")) == "g":
		if t == "van": _kuld({"t": "foglalt"})
		elif t == "foglalt" and _kod_ellenorzes > 0.0:
			# (ritka) a kód már egy másik szobáé: új kód, új csatorna
			kod = uj_kod()
			_jelzo_nyit()
		return
	var k := str(j.get("k", ""))
	if k == "" or k.length() > 32: return
	match t:
		"join":
			if _vendegek.has(k):
				# Ismételt kérés (a válaszunk még úton volt): ugyanaz az azonosító.
				_kuld({"t": "ok", "k": k, "id": int(_vendegek[k]["id"])})
				return
			if int(j.get("v", -1)) != PROTOKOLL:
				_kuld({"t": "nem", "k": k, "ok": "szoba_verzio"})
				return
			if Net.phase == "jatek":
				_kuld({"t": "nem", "k": k, "ok": "szoba_fut"})
				return
			if Net.players.size() + _fuggoben() >= Net.MAX_PLAYERS:
				_kuld({"t": "nem", "k": k, "ok": "szoba_tele"})
				return
			var id := _kov_id
			_kov_id += 1
			var c := _uj_kapcsolat(k)
			if c == null or rtc == null or rtc.add_peer(c, id) != OK:
				_kuld({"t": "nem", "k": k, "ok": "szoba_nincs_kapcsolat"})
				return
			_vendegek[k] = {"id": id, "conn": c, "ido": 0.0, "kesz": false}
			_kuld({"t": "ok", "k": k, "id": id})
			c.create_offer()
		"sdp":
			var v: Dictionary = _vendegek.get(k, {})
			if not v.is_empty() and not bool(v["kesz"]):
				(v["conn"] as WebRTCPeerConnection).set_remote_description(
					str(j.get("tipus", "")), str(j.get("sdp", "")))
		"ice":
			var v: Dictionary = _vendegek.get(k, {})
			if not v.is_empty() and not bool(v["kesz"]):
				(v["conn"] as WebRTCPeerConnection).add_ice_candidate(
					str(j.get("m", "")), int(j.get("i", 0)), str(j.get("n", "")))

func _vendeg_fogad(j: Dictionary) -> void:
	if str(j.get("k", "")) != _kulcs: return
	match str(j.get("t", "")):
		"ok":
			if _befogadva: return
			var id := int(j.get("id", 0))
			if id < 2: return
			rtc = WebRTCMultiplayerPeer.new()
			if rtc.create_client(id) != OK:
				_hiba("szoba_nincs_kapcsolat")
				return
			_conn = _uj_kapcsolat(_kulcs)
			if _conn == null or rtc.add_peer(_conn, 1) != OK:
				_hiba("szoba_nincs_kapcsolat")
				return
			_befogadva = true
			_ido = 0.0
			vendeg_peer.emit(rtc)
		"nem":
			if _befogadva: return
			var ok := str(j.get("ok", ""))
			_hiba(ok if ok in ELUTASITAS_KEYS else "szoba_nincs_kapcsolat")
		"sdp":
			# A házigazda ajánlata: a válasz magától elkészül (session_description_created).
			if _conn != null: _conn.set_remote_description(str(j.get("tipus", "")), str(j.get("sdp", "")))
		"ice":
			if _conn != null: _conn.add_ice_candidate(str(j.get("m", "")), int(j.get("i", 0)), str(j.get("n", "")))

## Amit a házigazda elutasításként küldhet. (A csatornán bárki írhat: idegen szöveget nem
## fogadunk el nyelvi kulcsnak.)
const ELUTASITAS_KEYS := ["szoba_verzio", "szoba_fut", "szoba_tele", "szoba_nincs_kapcsolat"]
## Minden hiba, amit ez a modul a `hiba` jelzéssel ad (a LangCheck innen tudja, hogy használjuk őket).
const HIBA_KEYS := ["szoba_nincs_ilyen", "szoba_jelzes_hiba", "szoba_belepes_kell", "szoba_nem_enged"]

# ── A jelzőcsatorna (Supabase Realtime, Phoenix-protokoll) ─────

func _jelzo_nyit() -> void:
	_jelzo_zar()
	_topic = "realtime:" + TEMA + kod
	_menet += 1
	var m := _menet
	# Előbb a fiók belépője (ha lejárt, megújítjuk) — utána nyílik a websocket.
	_fiok_token(func(tok: String) -> void:
		if m != _menet or mod == Mod.NINCS: return
		_token = tok
		_ws_nyit())

func _ws_nyit() -> void:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 256 * 1024
	_ws.outbound_buffer_size = 256 * 1024
	if _ws.connect_to_url(jelzo_url + "?apikey=" + ANON_KULCS + "&vsn=1.0.0") != OK:
		_ws = null
		if mod == Mod.GAZDA: _ujra = 5.0
		else: _hiba.call_deferred("szoba_jelzes_hiba")
		return
	_bent = false
	_sziv = 0.0
	_csatlakozas_var = true

## Csatlakozás a csatornához (a websocket megnyílásakor egyszer). A csatorna PRIVÁT; ha van
## fiók, annak a belépőjével megyünk, különben a nyilvános kulcs (anon szerep) számít.
func _csatorna_be() -> void:
	_csatlakozas_var = false
	var payload := {"config": {"broadcast": {"self": false, "ack": false},
		"presence": {"key": ""}, "private": true}}
	if _token != "": payload["access_token"] = _token
	_ws_kuld({"topic": _topic, "event": "phx_join", "ref": _uj_ref(), "join_ref": "1", "payload": payload})

func _jelzo_zar() -> void:
	_menet += 1
	_csatlakozas_var = false
	if _ws != null:
		if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN and _bent:
			_ws_kuld({"topic": _topic, "event": "phx_leave", "payload": {}, "ref": _uj_ref(), "join_ref": "1"})
		_ws.close()
	_ws = null
	_bent = false

func _kuld(j: Dictionary) -> void:
	if _ws == null or not _bent: return
	j["r"] = "g" if mod == Mod.GAZDA else "v"
	_ws_kuld({"topic": _topic, "event": "broadcast", "ref": _uj_ref(), "join_ref": "1",
		"payload": {"type": "broadcast", "event": "sig", "payload": j}})

func _ws_kuld(m: Dictionary) -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(m))

func _uj_ref() -> String:
	_ref += 1
	return str(_ref)

# ── A fiók belépője (a ParthLauncher adja: user://fiok.json) ───

func _fiok() -> Dictionary:
	var f := FileAccess.open(FIOK, FileAccess.READ)
	if f == null: return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

## A belépő lejárati ideje (unix mp) a JWT közepéből; 0, ha nem olvasható.
static func _lejarat(tok: String) -> int:
	var r := tok.split(".")
	if r.size() != 3: return 0
	var b := str(r[1]).replace("-", "+").replace("_", "/")
	while b.length() % 4 != 0: b += "="
	var d: Variant = JSON.parse_string(Marshalls.base64_to_utf8(b))
	return int((d as Dictionary).get("exp", 0)) if d is Dictionary else 0

## A fiók érvényes belépője a `kesz(tok)` hívással; "" ha nincs fiók. A lejártat a felhő-mentés
## modulja újítja meg (az írja vissza a fiok.json-ba is, így a launcher és a mentés sem esik ki).
func _fiok_token(kesz_hivas: Callable) -> void:
	var d := _fiok()
	var tok := str(d.get("access_token", ""))
	# Csak a SAJÁT kiszolgálónknak adjuk oda — a fejlesztői helyi jelzőnek soha.
	if tok == "" or jelzo_url != JELZO_URL or not str(d.get("url", "")).contains(PROJEKT):
		kesz_hivas.call("")
		return
	if _lejarat(tok) > int(Time.get_unix_time_from_system()) + 120:
		kesz_hivas.call(tok)
		return
	var felho: Node = SaveManager.felho
	if felho == null or not felho.has_method("_ujit"):
		kesz_hivas.call(tok)
		return
	felho.call("_ujit", func(_ok: bool) -> void:
		kesz_hivas.call(str(_fiok().get("access_token", ""))))
