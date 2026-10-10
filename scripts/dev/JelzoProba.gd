extends SceneTree

# HELYI JELZŐ a szobakódos (WebRTC) út próbájához — fejlesztői eszköz, a kiadásba nem kerül.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://scripts/dev/JelzoProba.gd
#
# A Supabase Realtime-ból annyit utánoz, amennyit a NetSzoba.gd használ (Phoenix-üzenetek):
# belépés a csatornára (phx_join → phx_reply ok), és a „broadcast” továbbítása a csatorna
# többi tagjának. Így a két játékpéldány közti WebRTC-kapcsolat a kiszolgáló beállítása
# nélkül is kipróbálható:
#   -- --szobahost --szobajelzo=ws://127.0.0.1:27031
#   -- --szobajoin=KOD --szobajelzo=ws://127.0.0.1:27031
# Csak a saját gépről érhető el (127.0.0.1), és két perc után magától kilép.

const KAPU := 27031
const ELET_MP := 120.0

var _szerver := TCPServer.new()
var _tagok: Array = []          # {"ws": WebSocketPeer, "tema": String}
var _t: float = 0.0

func _initialize() -> void:
	if _szerver.listen(KAPU, "127.0.0.1") != OK:
		print("[jelzo] a kapu foglalt: ", KAPU)
		quit(1)
		return
	print("[jelzo] fut: ws://127.0.0.1:", KAPU)

func _process(delta: float) -> bool:
	_t += delta
	if _t > ELET_MP:
		print("[jelzo] vége")
		return true
	while _szerver.is_connection_available():
		var ws := WebSocketPeer.new()
		if ws.accept_stream(_szerver.take_connection()) == OK:
			_tagok.append({"ws": ws, "tema": ""})
	for tag in _tagok.duplicate():
		var ws: WebSocketPeer = tag["ws"]
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_tagok.erase(tag)
			continue
		while ws.get_ready_state() == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
			_uzenet(tag, ws.get_packet().get_string_from_utf8())
	return false

func _uzenet(tag: Dictionary, szoveg: String) -> void:
	var m: Variant = JSON.parse_string(szoveg)
	if not (m is Dictionary): return
	var tema := str(m.get("topic", ""))
	match str(m.get("event", "")):
		"phx_join":
			tag["tema"] = tema
			print("[jelzo] belépett: ", tema)
			(tag["ws"] as WebSocketPeer).send_text(JSON.stringify({"event": "phx_reply", "topic": tema,
				"ref": m.get("ref"), "payload": {"status": "ok", "response": {}}}))
		"phx_leave":
			tag["tema"] = ""
		"broadcast":
			var p: Variant = m.get("payload", {})
			if p is Dictionary and (p as Dictionary).get("payload") is Dictionary:
				print("[jelzo] ", tema, "  ", ((p as Dictionary)["payload"] as Dictionary).get("r", "?"),
					" ", ((p as Dictionary)["payload"] as Dictionary).get("t", "?"))
			for masik in _tagok:
				if masik == tag or str(masik["tema"]) != tema: continue
				var w: WebSocketPeer = masik["ws"]
				if w.get_ready_state() == WebSocketPeer.STATE_OPEN:
					w.send_text(JSON.stringify({"event": "broadcast", "topic": tema, "ref": null,
						"payload": p}))
