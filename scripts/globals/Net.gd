extends Node

# Hálózati többjátékos — LEGFELJEBB 8 FÉL.
#
# A logika ugyanaz, mint a régi HTML változatban: a játszma a HÁZIGAZDA
# gépén fut. A csatlakozók nem szimulálnak semmit, csak
#   - parancsot küldenek a házigazdának (mozgás, támadás, építés, képzés),
#   - és megkapják tőle a világ állapotát (pillanatkép), amit kirajzolnak.
# Így nem kell tökéletesen determinisztikus szimuláció: egyetlen igazság
# van, a házigazdáé.
#
# KÉTFÉLE ÚTON lehet összejönni:
#
# 1. KÖZVETLEN (direkt). A házigazda gépe nyit kaput, a többiek oda
#    csatlakoznak. Gyors, de a házigazda routerén ki kell nyitni a kaput
#    (UPnP vagy kézi átirányítás), és mobilneten/CGNAT mögött nem megy.
#
# 2. KÖZVETÍTŐN ÁT (relay). MINDENKI — a házigazda is — KIFELÉ csatlakozik
#    egy közvetítő géphez, és az továbbítja a csomagokat. Így egyetlen
#    játékosnak sem kell kaput nyitnia: bárki játszhat bárkivel, más-más
#    wifiről, mobilnetről is. Csak a közvetítőnek kell elérhetőnek lennie.
#    A közvetítő UGYANEZ a játék, `--relay=27020` kapcsolóval indítva.
#
# A játszma mindkét esetben a HÁZIGAZDA gépén fut: a közvetítő csak postás,
# nem számol semmit.

signal lobby_changed              # a résztvevők listája vagy a beállítás változott
signal state_changed(state: String)
signal error_message(text: String)
signal match_starting(payload: Dictionary)

const PORT_BASE := 27015
const MAX_PLAYERS := 8
# Összetéveszthető betűk (0/O, 1/I/L) nélkül.
const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

# "ki" | "hazigazda" | "csatlakozo"
var role: String = "ki"
# "lobbi" | "jatek"
var phase: String = "lobbi"
var room_code: String = ""
var port: int = PORT_BASE

# --- Interneten át való játék ---
#
# Két kód készül: a HELYI (ugyanaz a wifi) és az INTERNETES. Az utóbbihoz
# ki kell nyitni a kaput a routeren; ezt a Godot beépített UPnP-je magától
# megteszi, ha a router engedi. Ha nem megy, a felület megmondja, mit kell
# kézzel beállítani — külső szerverre így sincs szükség.
# "nincs" | "keres" | "kesz" | "sikertelen"
var upnp_state: String = "nincs"
var lan_code: String = ""
var public_code: String = ""
var public_ip: String = ""
# A HÁZIGAZDA CÍME sima alakban ("192.168.0.12"). A szobakód ugyanezt rejti
# betűkbe, de a legtöbben egyszerűbben boldogulnak a címmel és a kapuval —
# ezért a felület mindkettőt kiírja, és a csatlakozó mező is elfogadja.
var lan_ip: String = ""

signal upnp_changed

var _upnp: UPNP = null
var _upnp_thread: Thread = null

# hely -> {"nev","nemzet","csapat","hazigazda"}. A kulcs a peer azonosító.
var players: Dictionary = {}
var my_id: int = 0
# MELYIK GÉPEN FUT A JÁTSZMA. Közvetlen módban ez mindig 1 (a kaput nyitó
# gép), közvetítőn át viszont a szobát nyitó játékos rendes peer-száma —
# ezért sehol nem szabad "1"-et írni a házigazda helyett.
var host_peer: int = 1
# "direkt" | "relay"
var transport: String = "direkt"
# Közvetítő üzemmódban maga a közvetítő gép: csak postás, nem játszik.
var relay_mode: bool = false
const RELAY_PORT := 27020

# A játszma beállításai (a házigazda állítja).
var setup: Dictionary = {"age": 0, "diff": 1, "pirate": false}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)

func active() -> bool:
	return role != "ki"

func is_host() -> bool:
	return role == "hazigazda"

func is_client() -> bool:
	return role == "csatlakozo"

# --- 2. ÚT: KÖZVETÍTŐ (relay) ---
#
# A közvetítő nem játszik: szobákat tart nyilván, és a Godot magától
# továbbítja a játékosok egymásnak szóló üzeneteit rajta keresztül.
# Indítás:  godot --headless --path <projekt> -- --relay=27020
var _rooms: Dictionary = {}       # kód -> {"host": peer, "tagok": [peer...]}
var _peer_room: Dictionary = {}   # peer -> kód

func start_relay(p: int = RELAY_PORT) -> bool:
	close()
	var peer := ENetMultiplayerPeer.new()
	# Nyolc szoba, nyolc fővel: hatvannégy kapcsolat bőven elég.
	if peer.create_server(p, 64) != OK:
		push_error("[relay] a kapu foglalt: %d" % p)
		return false
	multiplayer.multiplayer_peer = peer
	relay_mode = true
	port = p
	role = "kozvetito"
	print("[relay] fut a(z) %d kapun, cím: %s" % [p, _local_ipv4()])
	print("[relay] szobakód-előtag ehhez a géphez: %s"
		% pretty(make_code(_local_ipv4(), p, 0)))
	return true

# Szoba nyitása a közvetítőn. A hívó lesz a házigazda.
@rpc("any_peer", "call_remote", "reliable")
func _relay_create(nev: String) -> void:
	if not relay_mode: return
	var id := multiplayer.get_remote_sender_id()
	var szoba := -1
	for i in range(256):
		if not _rooms.has(i):
			szoba = i
			break
	if szoba < 0:
		rpc_id(id, "_relay_error", "net_relay_tele")
		return
	_rooms[szoba] = {"host": id, "tagok": [id], "nevek": {id: nev}}
	_peer_room[id] = szoba
	print("[relay] %d. szoba nyitva, házigazda %d" % [szoba, id])
	_relay_push(szoba)

@rpc("any_peer", "call_remote", "reliable")
func _relay_join(szoba: int, nev: String) -> void:
	if not relay_mode: return
	var id := multiplayer.get_remote_sender_id()
	if not _rooms.has(szoba):
		rpc_id(id, "_relay_error", "net_relay_nincs_szoba")
		return
	var r: Dictionary = _rooms[szoba]
	if (r["tagok"] as Array).size() >= MAX_PLAYERS:
		rpc_id(id, "_relay_error", "net_relay_tele_szoba")
		return
	(r["tagok"] as Array).append(id)
	(r["nevek"] as Dictionary)[id] = nev
	_peer_room[id] = szoba
	_relay_push(szoba)

# A szoba összetételét mindenkinek elküldjük: kik vannak bent, ki a gazda.
func _relay_push(szoba: int) -> void:
	if not _rooms.has(szoba): return
	var r: Dictionary = _rooms[szoba]
	for peer in (r["tagok"] as Array):
		rpc_id(int(peer), "_relay_room", szoba, r["host"], r["tagok"],
			r["nevek"])

func _relay_drop(id: int) -> void:
	if not _peer_room.has(id): return
	var szoba: int = _peer_room[id]
	_peer_room.erase(id)
	if not _rooms.has(szoba): return
	var r: Dictionary = _rooms[szoba]
	(r["tagok"] as Array).erase(id)
	(r["nevek"] as Dictionary).erase(id)
	# Ha a házigazda ment el, a szoba megszűnik.
	if int(r["host"]) == id or (r["tagok"] as Array).is_empty():
		for peer in (r["tagok"] as Array):
			rpc_id(int(peer), "_relay_error", "net_hazigazda_elment")
			_peer_room.erase(int(peer))
		_rooms.erase(szoba)
		print("[relay] %d. szoba bezárt" % szoba)
		return
	_relay_push(szoba)

# --- A JÁTÉKOS OLDALA a közvetítőn ---

@rpc("any_peer", "call_remote", "reliable")
func _relay_room(szoba: int, gazda: int, tagok: Array, nevek: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != 1: return
	host_peer = gazda
	role = "hazigazda" if my_id == gazda else "csatlakozo"
	transport = "relay"
	_room_no = szoba
	room_code = make_code(_relay_ip, _relay_port, szoba)
	# A résztvevők listáját a HÁZIGAZDA vezeti (nemzet, csapat); a
	# közvetítő csak a névsort ismeri.
	if is_host():
		for peer in tagok:
			if not players.has(int(peer)):
				players[int(peer)] = _new_player(str(nevek.get(peer, "")),
					players.size(), int(peer) == gazda)
		for kulcs in players.keys():
			if not (kulcs in tagok): players.erase(kulcs)
		_push_lobby()
	state_changed.emit("lobbi")
	lobby_changed.emit()

@rpc("any_peer", "call_remote", "reliable")
func _relay_error(kulcs: String) -> void:
	if multiplayer.get_remote_sender_id() != 1: return
	error_message.emit(Lang.t(kulcs))
	close()

# --- A JÁTSZMA PILLANATKÉPE ÉS A PARANCSOK ---
#
# Ezek is ITT, a Net autoloadon ülnek, nem a jelenetben lévő NetSync-en.
# Ok: a Godot az üzeneteket CSOMÓPONT-ÚTVONAL szerint kézbesíti, és a
# közvetítő gépen nincs `Main/NetSync` — az útvonalat ott nem lehetne
# feloldani, és a továbbítás elakadna. A `/root/Net` viszont minden
# példányban létezik, a közvetítőn is.
var sync: Node = null                # a jelenetbeli NetSync, ha fut

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _cli_snapshot(u: PackedFloat32Array, b: PackedFloat32Array,
		sides: Array, t: float, over: bool, winner: int) -> void:
	if not _from_host(): return
	if sync != null and is_instance_valid(sync):
		sync.apply_snapshot(u, b, sides, t, over, winner)

@rpc("any_peer", "call_remote", "reliable")
func _srv_cmd(kind: String, args: Array) -> void:
	if not is_host(): return
	if sync != null and is_instance_valid(sync):
		sync.handle_cmd(multiplayer.get_remote_sender_id(), kind, args)

var _room_no: int = -1
var _relay_ip: String = ""
var _relay_port: int = RELAY_PORT
var _pending_room: int = -1

# Szoba nyitása KÖZVETÍTŐN át: a saját gépünkön semmit nem kell kinyitni.
func host_via_relay(relay_addr: String, player_name: String = "") -> bool:
	if not _connect_relay(relay_addr, player_name): return false
	_pending_room = -1
	return true

func join_via_relay(relay_addr: String, szoba: int, player_name: String = "") -> bool:
	if not _connect_relay(relay_addr, player_name): return false
	_pending_room = szoba
	return true

func _connect_relay(relay_addr: String, player_name: String) -> bool:
	var cim := parse_address(relay_addr)
	if cim.is_empty():
		error_message.emit(Lang.t("net_relay_rossz_cim"))
		return false
	close()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(str(cim[0]), int(cim[1])) != OK:
		error_message.emit(Lang.t("net_relay_nem_ert_el"))
		return false
	multiplayer.multiplayer_peer = peer
	transport = "relay"
	role = "csatlakozo"
	phase = "lobbi"
	_relay_ip = str(cim[0])
	_relay_port = int(cim[1])
	_pending_name = player_name
	state_changed.emit("csatlakozas")
	return true

# --- Szobakód ---
#
# 4 bájt IP-cím + 1 bájt kapueltolás = 40 bit = 8 betű.

func _local_ipv4() -> String:
	var best := "127.0.0.1"
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.count(".") != 3: continue          # IPv6 kihagyva
		if s.begins_with("127."): continue
		# A magánhálózati címek a jók: ezeken érik el egymást a gépek.
		if s.begins_with("192.168.") or s.begins_with("10.") \
				or s.begins_with("172."):
			return s
		best = s
	return best

# A kód a CÍMET, a KAPUT és — közvetítőnél — a SZOBA sorszámát is elbírja.
# Négy bájt cím + egy bájt kapueltolás + egy bájt szoba = 48 bit = 10 betű.
# Közvetlen módban a szoba 255 (nincs szoba), olyankor nyolc betű elég.
func make_code(ip: String, p: int, szoba: int = -1) -> String:
	var parts := ip.split(".")
	if parts.size() != 4: return ""
	var bits := 0
	var value := 0
	var out := ""
	var bytes: Array[int] = []
	for s in parts: bytes.append(clampi(int(s), 0, 255))
	bytes.append(clampi(p - PORT_BASE, 0, 255))
	if szoba >= 0: bytes.append(clampi(szoba, 0, 255))
	for b in bytes:
		value = (value << 8) | b
		bits += 8
		while bits >= 5:
			bits -= 5
			out += ALPHABET[(value >> bits) & 31]
	if bits > 0:
		out += ALPHABET[(value << (5 - bits)) & 31]
	return out

# A kódból cím, kapu és (tíz betűnél) szobaszám. Üres tömb = hibás kód.
func parse_code(code: String) -> Array:
	var s := code.to_upper().replace("-", "").replace(" ", "")
	if s.length() != 8 and s.length() != 10: return []
	var value := 0
	var bits := 0
	var bytes: Array[int] = []
	for ch in s:
		var i := ALPHABET.find(ch)
		if i < 0: return []
		value = (value << 5) | i
		bits += 5
		if bits >= 8:
			bits -= 8
			bytes.append((value >> bits) & 255)
	if bytes.size() < 5: return []
	var out: Array = ["%d.%d.%d.%d" % [bytes[0], bytes[1], bytes[2], bytes[3]],
		PORT_BASE + bytes[4]]
	if bytes.size() >= 6: out.append(bytes[5])
	return out

# A házigazda címe "cím:kapu" alakban — ezt kell beírnia a vendégnek.
# Üres, ha még nem vagyunk házigazdák (a nyilvános cím csak akkor, ha a
# router kaput nyitott).
func lan_address() -> String:
	return "%s:%d" % [lan_ip, port] if lan_ip != "" else ""

func public_address() -> String:
	return "%s:%d" % [public_ip, port] if public_ip != "" else ""

func pretty_code() -> String:
	return pretty(room_code)

func pretty(code: String) -> String:
	if code.length() == 8: return code.substr(0, 4) + "-" + code.substr(4, 4)
	if code.length() == 10: return code.substr(0, 5) + "-" + code.substr(5, 5)
	return code

# "cím" vagy "cím:kapu" alak. Üres tömb = nem cím.
func parse_address(text: String) -> Array:
	var s := text.strip_edges()
	if s == "": return []
	var p := PORT_BASE
	if s.count(":") == 1:
		var parts := s.split(":")
		s = str(parts[0]).strip_edges()
		p = int(str(parts[1]))
		if p <= 0 or p > 65535: return []
	# Csak akkor fogadjuk el címnek, ha van benne pont vagy betű — a
	# nyolcbetűs kódot már korábban megpróbáltuk.
	if s.length() < 4 or not (s.contains(".") or s.contains("-")): return []
	return [s, p]

# --- Szoba nyitása és csatlakozás ---

func host_game(player_name: String = "") -> bool:
	close()
	var peer := ENetMultiplayerPeer.new()
	# Ha a kapu foglalt, próbálkozunk a következővel.
	var err := ERR_CANT_CREATE
	for offset in range(0, 16):
		port = PORT_BASE + offset
		err = peer.create_server(port, MAX_PLAYERS - 1)
		if err == OK: break
	if err != OK:
		error_message.emit(Lang.t("net_nem_nyilt"))
		return false
	multiplayer.multiplayer_peer = peer
	role = "hazigazda"
	transport = "direkt"
	host_peer = 1
	phase = "lobbi"
	my_id = 1
	lan_ip = _local_ipv4()
	lan_code = make_code(lan_ip, port)
	room_code = lan_code
	players = {1: _new_player(player_name, 0, true)}
	_start_upnp()
	state_changed.emit("lobbi")
	lobby_changed.emit()
	return true

# --- UPnP: a kapu kinyitása a routeren ---
#
# A keresés másodpercekig tart, ezért külön szálon fut — enélkül a menü
# megállna. A végeredményt a főszálra tesszük vissza.
func _start_upnp() -> void:
	if OS.has_feature("headless") and not _upnp_in_headless: return
	upnp_state = "keres"
	upnp_changed.emit()
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_worker.bind(port))

# Fejlesztői próbákhoz kikapcsolható (a headless futás ne várjon a routerre).
var _upnp_in_headless := false

func _upnp_worker(p: int) -> void:
	var u := UPNP.new()
	var res := {"ok": false, "ip": ""}
	if u.discover() == UPNP.UPNP_RESULT_SUCCESS:
		var gw := u.get_gateway()
		if gw != null and gw.is_valid_gateway():
			# Az ENet UDP-t használ; a TCP-s szabályra nincs szükség.
			var m := u.add_port_mapping(p, p, "Birodalom", "UDP", 0)
			if m == UPNP.UPNP_RESULT_SUCCESS:
				var ip := u.query_external_address()
				if ip != "" and ip.count(".") == 3:
					res = {"ok": true, "ip": ip}
	call_deferred("_upnp_done", u, res)

func _upnp_done(u: UPNP, res: Dictionary) -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if not is_host():
		return
	if bool(res.get("ok", false)):
		_upnp = u
		public_ip = str(res["ip"])
		public_code = make_code(public_ip, port)
		room_code = public_code
		upnp_state = "kesz"
		print("[net] UPnP: kapu nyitva, nyilvános cím ", public_ip, ":", port,
			"  kód ", pretty(public_code))
	else:
		upnp_state = "sikertelen"
		print("[net] UPnP: a router nem nyitott kaput (kézi átirányítás vagy VPN kell)")
	upnp_changed.emit()
	lobby_changed.emit()

func _close_upnp() -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _upnp != null:
		_upnp.delete_port_mapping(port, "UDP")
		_upnp = null
	upnp_state = "nincs"
	public_code = ""
	public_ip = ""
	lan_ip = ""

func join_game(code: String, player_name: String = "") -> bool:
	var addr := parse_code(code)
	# Kód helyett cím is megadható: "12.34.56.78:27015" vagy "gep.local".
	# Ez kell a kézzel átirányított kapuhoz és a VPN-es (Tailscale,
	# ZeroTier, Hamachi) megoldásokhoz.
	if addr.is_empty(): addr = parse_address(code)
	if addr.is_empty():
		error_message.emit(Lang.t("net_rossz_kod"))
		return false
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(str(addr[0]), int(addr[1]))
	if err != OK:
		error_message.emit(Lang.t("net_nem_ert_el"))
		return false
	multiplayer.multiplayer_peer = peer
	role = "csatlakozo"
	transport = "direkt"
	host_peer = 1
	phase = "lobbi"
	# A lobbi ezt írja ki: ha kódot kaptunk, a kódot; ha címet, magát a címet.
	if parse_code(code).is_empty():
		room_code = "%s:%d" % [str(addr[0]), int(addr[1])]
	else:
		room_code = code.to_upper().replace("-", "")
	_pending_name = player_name
	state_changed.emit("csatlakozas")
	return true

var _pending_name: String = ""

func close() -> void:
	_close_upnp()
	if multiplayer.multiplayer_peer != null \
			and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	role = "ki"
	phase = "lobbi"
	transport = "direkt"
	relay_mode = false
	host_peer = 1
	players.clear()
	_rooms.clear()
	_peer_room.clear()
	_room_no = -1
	_pending_room = -1
	my_id = 0
	room_code = ""
	lan_code = ""
	state_changed.emit("ki")

func _exit_tree() -> void:
	_close_upnp()

func _new_player(nev: String, index: int, host: bool) -> Dictionary:
	var lista := Style.order_for(false)
	return {
		"nev": nev if nev != "" else "%s %d" % [Lang.t("jatekos"), index + 1],
		"nemzet": str(lista[index % lista.size()]),
		"csapat": index,
		"hazigazda": host,
	}

# --- Kapcsolat-események ---

func _on_peer_connected(id: int) -> void:
	if relay_mode: return                     # a közvetítő a szobákat várja
	if not is_host() or transport != "direkt": return
	if players.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	players[id] = _new_player("", players.size(), false)
	_push_lobby()

func _on_peer_disconnected(id: int) -> void:
	if relay_mode:
		_relay_drop(id)
		return
	if not is_host(): return
	players.erase(id)
	_push_lobby()

func _on_connected() -> void:
	my_id = multiplayer.get_unique_id()
	if transport == "relay":
		# Most derül ki a saját peer-számunk; ezzel kérünk szobát.
		if _pending_room < 0:
			rpc_id(1, "_relay_create", _pending_name)
		else:
			rpc_id(1, "_relay_join", _pending_room, _pending_name)
		return
	state_changed.emit("lobbi")
	if _pending_name != "":
		rpc_id(host_peer, "_srv_set_name", _pending_name)

func _on_connect_failed() -> void:
	close()
	error_message.emit(Lang.t("net_nem_ert_el"))

func _on_server_gone() -> void:
	close()
	error_message.emit(Lang.t("net_hazigazda_elment"))

# --- Lobbi állapot ---

# A lobbi állapotát a HÁZIGAZDA küldi szét — közvetítőn át is, csak ott
# nem "mindenkinek", hanem a szoba tagjainak egyesével (a közvetítőn más
# szobák is lehetnek).
func _push_lobby() -> void:
	if not is_host(): return
	for peer in players.keys():
		if int(peer) == my_id: continue
		rpc_id(int(peer), "_cli_lobby", players, setup)
	lobby_changed.emit()

@rpc("any_peer", "call_remote", "reliable")
func _cli_lobby(list: Dictionary, s: Dictionary) -> void:
	# Közvetítőn át a házigazda nem az 1-es peer, ezért az "authority"
	# jogosultság nem használható: kézzel ellenőrizzük a feladót.
	if not _from_host(): return
	players = list
	setup = s
	lobby_changed.emit()

# Csak a HÁZIGAZDÁTÓL (közvetítőnél a közvetítőtől) fogadunk el utasítást.
func _from_host() -> bool:
	var s := multiplayer.get_remote_sender_id()
	return s == host_peer or s == 1

@rpc("any_peer", "call_remote", "reliable")
func _srv_set_name(nev: String) -> void:
	if not is_host(): return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id]["nev"] = nev.substr(0, 18)
		_push_lobby()

@rpc("any_peer", "call_remote", "reliable")
func _srv_set_setup(nemzet: String, csapat: int) -> void:
	if not is_host(): return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id]["nemzet"] = nemzet
		players[id]["csapat"] = clampi(csapat, 0, MAX_PLAYERS - 1)
		_push_lobby()

# A saját nemzet/csapat állítása — a házigazdánál helyben, másnál üzenetben.
func set_my_setup(nemzet: String, csapat: int) -> void:
	if is_host():
		if players.has(1):
			players[1]["nemzet"] = nemzet
			players[1]["csapat"] = clampi(csapat, 0, MAX_PLAYERS - 1)
			_push_lobby()
	else:
		rpc_id(host_peer, "_srv_set_setup", nemzet, csapat)

func set_match_setup(age: int, diff: int, pirate: bool) -> void:
	if not is_host(): return
	setup = {"age": clampi(age, 0, 3), "diff": clampi(diff, 0, 2),
		"pirate": pirate}
	_push_lobby()

# --- Indítás ---
#
# A házigazda összeállítja az oldalak listáját (a lobbi sorrendjében), és
# mindenkinek elküldi a MAGOT is: a világ így minden gépen ugyanúgy néz ki,
# noha a szimulációt csak a házigazda futtatja.
func start_match() -> void:
	if not is_host(): return
	var ids := players.keys()
	ids.sort()
	var sides: Array = []
	for id in ids:
		var p: Dictionary = players[id]
		sides.append({"tipus": "ember", "nemzet": str(p["nemzet"]),
			"csapat": int(p["csapat"]), "peer": int(id)})
	var payload := {
		"seed": (Time.get_ticks_msec() ^ randi()) & 0x7FFFFFFF,
		"sides": sides,
		"age": int(setup.get("age", 0)),
		"diff": int(setup.get("diff", 1)),
		"pirate": bool(setup.get("pirate", false)),
	}
	for peer in players.keys():
		if int(peer) == my_id: continue
		rpc_id(int(peer), "_cli_begin", payload)
	_begin(payload)

@rpc("any_peer", "call_remote", "reliable")
func _cli_begin(payload: Dictionary) -> void:
	if not _from_host(): return
	_begin(payload)

var last_payload: Dictionary = {}

func _begin(payload: Dictionary) -> void:
	phase = "jatek"
	last_payload = payload
	match_starting.emit(payload)

# Melyik oldal (index) a miénk a kiosztott listában.
func side_index_of(sides: Array, peer: int) -> int:
	for i in sides.size():
		if int((sides[i] as Dictionary).get("peer", -1)) == peer: return i
	return 0
