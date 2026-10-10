extends Node

# Kétgépes hálózati próba egy gépen, két folyamatban.
#
#   1. ablak:  godot --headless -- --nethost
#              kiírja a szobakódot, megvárja a társat, elindítja a
#              játszmát, majd húsz másodperc után jelent.
#   2. ablak:  godot --headless -- --netjoin=ABCDEFGH
#
# A próba akkor sikeres, ha a csatlakozónál UGYANANNYI egység és épület
# van, mint a házigazdánál — vagyis a pillanatkép rendben átér.

var _t: float = 0.0
var _kiirt: bool = false
var _started: bool = false
var _report_at: float = 0.0

func _ready() -> void:
	name = "NetTest"
	var args := OS.get_cmdline_user_args()
	if "--nethost" in args:
		if Net.host_game("Hazigazda"):
			print("[net] szoba nyitva, kód: ", Net.pretty_code(),
				"  (nyers: ", Net.room_code, ")")
		Net.lobby_changed.connect(_on_lobby)
	# Közvetítőn át:  -- --netrelayhost=cim:kapu
	for a in args:
		if a.begins_with("--netrelayhost="):
			Net.lobby_changed.connect(_on_lobby)
			Net.state_changed.connect(func(s: String) -> void:
				if s == "lobbi" and Net.room_code != "" and not _kiirt:
					_kiirt = true
					print("[net] szoba nyitva KÖZVETÍTŐN, kód: ",
						Net.pretty(Net.room_code),
						"  (nyers: ", Net.room_code, ")"))
			Net.host_via_relay(a.substr(15), "Hazigazda")
		if a.begins_with("--netrelayjoin="):
			var darab := a.substr(15).split("|")
			print("[net] csatlakozás közvetítőn: ", darab)
			Net.join_via_relay(str(darab[0]), int(darab[1]), "Tars")
	# SZOBAKÓDDAL (WebRTC):
	#   1. ablak:  -- --szobahost            kiírja a hatbetűs kódot
	#   2. ablak:  -- --szobajoin=ABCDEF
	# Kiegészítők:
	#   --szobajelzo=ws://127.0.0.1:27031    a Supabase helyett helyi jelző
	#                                        (scripts/dev/JelzoProba.gd) — a
	#                                        kiszolgáló beállítása nélkül is próbálható
	#   --snapdarab=2000                     a pillanatkép már ekkora mérettől
	#                                        darabokban megy (a darabolás próbája)
	for a in args:
		if a.begins_with("--szobajelzo="):
			Net.szoba.set("jelzo_url", a.substr(13))
			print("[net] jelző: ", a.substr(13))
		if a.begins_with("--snapdarab="):
			Net.snap_egyben_max = int(a.substr(12))
			Net.snap_darab = int(a.substr(12))
	if "--szobahost" in args:
		print("[net] WebRTC elérhető: ", Net.room_available())
		Net.lobby_changed.connect(func() -> void:
			if Net.room_code != "" and not _kiirt:
				_kiirt = true
				print("[net] szoba nyitva SZOBAKÓDDAL, kód: ", Net.pretty_code(),
					"  (nyers: ", Net.room_code, ")"))
		Net.lobby_changed.connect(_on_lobby)
		Net.host_room("Hazigazda")
	for a in args:
		if a.begins_with("--szobajoin="):
			print("[net] WebRTC elérhető: ", Net.room_available())
			print("[net] csatlakozás szobakóddal: ", a.substr(12))
			Net.state_changed.connect(func(s: String) -> void:
				print("[net] állapot: ", s))
			Net.lobby_changed.connect(func() -> void:
				print("[net] lobbi a vendégnél: ", Net.players.size(), " fél, én: ", Net.my_id))
			Net.join_room(a.substr(12), "Tars")
	for a in args:
		if a.begins_with("--netjoin="):
			var code := a.substr(10)
			print("[net] csatlakozás: ", code)
			Net.join_game(code, "Tars")
			Net.state_changed.connect(func(s: String) -> void:
				print("[net] állapot: ", s))
	Net.match_starting.connect(_on_start)
	Net.error_message.connect(func(t: String) -> void:
		print("[net] HIBA: ", t)
		# A szobakódos próbánál a hiba a végeredmény: nincs mire várni.
		if "--szobahost" in args or _van(args, "--szobajoin="):
			print("[net] JELENTES  sikertelen")
			get_tree().quit(2))

func _van(args: PackedStringArray, eleje: String) -> bool:
	for a in args:
		if a.begins_with(eleje): return true
	return false

func _on_lobby() -> void:
	print("[net] lobbi: ", Net.players.size(), " fél")
	if Net.is_host() and Net.players.size() >= 2 and not _started:
		_started = true
		print("[net] indítás")
		Net.start_match()

func _on_start(payload: Dictionary) -> void:
	print("[net] játszma indul, oldalak: ", (payload.get("sides", []) as Array).size(),
		"  mag: ", payload.get("seed", 0))
	Campaign.stop()
	var sides: Array = payload.get("sides", [])
	var me := Net.side_index_of(sides, Net.my_id)
	GameState.new_battle(sides, int(payload.get("age", 0)),
		bool(payload.get("pirate", false)), me, int(payload.get("seed", 0)))
	GameState.diff = int(payload.get("diff", 1))
	GameState.net_client = Net.is_client()
	_report_at = _t + 16.0
	if Net.is_client(): _cmd_at = _t + 6.0
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

var _cmd_at: float = 0.0
var _probe: Node = null
var _probe_from: Vector2 = Vector2.ZERO

func _process(delta: float) -> void:
	_t += delta
	# A csatlakozó félidőben parancsot ad: ebből derül ki, hogy a
	# házigazda tényleg végrehajtja-e, és a mozgás visszaér-e hozzánk.
	if _cmd_at > 0.0 and _t >= _cmd_at:
		_cmd_at = 0.0
		var main := get_tree().get_first_node_in_group("main")
		for u in get_tree().get_nodes_in_group("player_units"):
			if is_instance_valid(u) and u.role == "melee":
				_probe = u
				_probe_from = u.global_position
				main.send_cmd("move", [[int(u.nid)],
					u.global_position + Vector2(420, 0)])
				print("[net] parancs elküldve: mozgás")
				break
	if _report_at > 0.0 and _t >= _report_at:
		_report_at = 0.0
		var u := get_tree().get_nodes_in_group("units").size()
		var b := get_tree().get_nodes_in_group("buildings").size()
		var mozgott := -1.0
		if _probe != null and is_instance_valid(_probe):
			mozgott = _probe_from.distance_to(_probe.global_position)
		print("[net] JELENTES  szerep=", Net.role, "  oldal=", GameState.en_id,
			"  egyseg=", u, "  epulet=", b,
			"  fa=", int(float(GameState.get_res(GameState.en_id).get("wood", 0))),
			"  parancs-elmozdulas=", int(mozgott),
			"  ut=", Net.transport,
			"  pillanatkep-bajt=", (u + b) * 32)
		# Rendes bontás: a társ lássa, hogy elmentünk, a jelzőcsatorna is zárul.
		Net.close()
		get_tree().quit(0)
