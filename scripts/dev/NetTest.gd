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
	for a in args:
		if a.begins_with("--netjoin="):
			var code := a.substr(10)
			print("[net] csatlakozás: ", code)
			Net.join_game(code, "Tars")
			Net.state_changed.connect(func(s: String) -> void:
				print("[net] állapot: ", s))
	Net.match_starting.connect(_on_start)
	Net.error_message.connect(func(t: String) -> void: print("[net] HIBA: ", t))

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
			"  parancs-elmozdulas=", int(mozgott))
		get_tree().quit(0)
