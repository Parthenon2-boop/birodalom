extends Node

# A hálózati játszma motorja. A logika a régi HTML változatét követi
# annyiban, hogy EGYETLEN gép számol: a HÁZIGAZDÁÉ.
#
#   Házigazda:  fut a teljes szimuláció, és másodpercenként tízszer
#               elküldi a világ állapotát mindenkinek.
#   Csatlakozó: semmit nem szimulál. A kapott pillanatképből felépíti és
#               mozgatja a bábukat, a parancsait pedig elküldi a
#               házigazdának, aki végrehajtja őket.
#
# Így nincs szükség tökéletesen determinisztikus szimulációra: egyetlen
# igazság van, és az mindig a házigazdáé.

const SEND_HZ := 10.0

# A pillanatképben ennyi szám ír le egy egységet, illetve egy épületet.
const U_STRIDE := 8      # nid, owner, role, age, x, y, hp, jelzők
const B_STRIDE := 8      # nid, owner, tipus, age, x, y, hp, prog

var main: Node = null
var _accum: float = 0.0
# A csatlakozónál nid -> csomópont, hogy a következő pillanatképnél ne
# újat hozzunk létre, hanem a meglévőt mozgassuk.
var _units: Dictionary = {}
var _builds: Dictionary = {}

func _init(m: Node = null) -> void:
	main = m

func _ready() -> void:
	if main == null:
		main = get_tree().get_first_node_in_group("main")
	name = "NetSync"
	Net.sync = self

func _exit_tree() -> void:
	if Net.sync == self: Net.sync = null

func _process(delta: float) -> void:
	if not Net.active(): return
	if not Net.is_host(): return
	if not GameState.on and not GameState.over: return
	_accum += delta
	if _accum < 1.0 / SEND_HZ: return
	_accum = 0.0
	_broadcast()

# --- Pillanatkép (házigazda -> mindenki) ---

# A pillanatkép két számtömbje. Statikus, mert a VISSZAJÁTSZÁS felvétele
# is ezt használja (scripts/systems/Replay.gd) — így a hálózati és a
# felvett pillanatkép mindig ugyanaz a formátum.
static func snapshot_units(tree: SceneTree) -> PackedFloat32Array:
	var u := PackedFloat32Array()
	for n in tree.get_nodes_in_group("units"):
		if not is_instance_valid(n): continue
		u.append(float(n.nid))
		u.append(float(n.owner_id))
		u.append(float(Unit.ROLE_ORDER.find(n.role)))
		u.append(float(n.age))
		u.append(n.global_position.x)
		u.append(n.global_position.y)
		u.append(n.hp)
		# Jelzők egy számban: irány (radián) és a mozgás/csapás állapota.
		var f: float = n.face
		if n.velocity.length() > 2.0: f += 100.0
		if n._fired > 0.0: f += 1000.0
		u.append(f)
	return u

static func snapshot_builds(tree: SceneTree) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	for n in tree.get_nodes_in_group("buildings"):
		if not is_instance_valid(n): continue
		b.append(float(n.nid))
		b.append(float(n.owner_id))
		b.append(float(Building.TIPUS_ORDER.find(n.tipus)))
		b.append(float(n.age))
		b.append(n.global_position.x)
		b.append(n.global_position.y)
		b.append(n.hp)
		b.append(n.prog)
	return b

func _broadcast() -> void:
	var u := snapshot_units(get_tree())
	var b := snapshot_builds(get_tree())
	# Az oldalak készlete és korszaka — ebből él a HUD a csatlakozónál.
	var sides: Array = []
	for s in GameState.oldalak:
		sides.append({"res": s.get("res", {}), "age": int(s.get("age", 0))})
	# Közvetítőn át más szobák is lehetnek ugyanazon a gépen, ezért nem
	# "mindenkinek" küldünk, hanem a szobánk tagjainak. Az üzenetet a Net
	# autoload küldi — lásd az ottani magyarázatot a csomópont-útvonalról.
	for peer in Net.players.keys():
		if int(peer) == Net.my_id: continue
		Net.rpc_id(int(peer), "_cli_snapshot", u, b, sides, GameState.t,
			GameState.over, GameState.winner)

func apply_snapshot(u: PackedFloat32Array, b: PackedFloat32Array,
		sides: Array, t: float, over: bool, winner: int) -> void:
	if main == null or not is_instance_valid(main): return
	GameState.t = t
	for i in mini(sides.size(), GameState.oldalak.size()):
		var s: Dictionary = sides[i]
		GameState.oldalak[i]["res"] = s.get("res", {})
		GameState.oldalak[i]["age"] = int(s.get("age", 0))
	GameState.resources_changed.emit()
	_apply_units(u)
	_apply_builds(b)
	if over and not GameState.over:
		GameState.over = true
		GameState.winner = winner
		GameState.on = false

func _apply_units(u: PackedFloat32Array) -> void:
	var seen := {}
	var i := 0
	while i + U_STRIDE <= u.size():
		var nid := int(u[i])
		var owner := int(u[i + 1])
		var role_i := int(u[i + 2])
		var age := int(u[i + 3])
		var pos := Vector2(u[i + 4], u[i + 5])
		var hp := u[i + 6]
		var f := u[i + 7]
		seen[nid] = true
		var n: Node = _units.get(nid)
		if n == null or not is_instance_valid(n):
			var role: String = Unit.ROLE_ORDER[clampi(role_i, 0,
				Unit.ROLE_ORDER.size() - 1)]
			n = main.spawn_unit(role, owner, pos, age)
			n.nid = nid
			_units[nid] = n
		var att := f >= 1000.0
		if att: f -= 1000.0
		var moving := f >= 100.0
		if moving: f -= 100.0
		n.net_apply(pos, hp, f, moving, att)
		i += U_STRIDE
	for nid in _units.keys():
		if seen.has(nid): continue
		var n: Node = _units[nid]
		if is_instance_valid(n): n.queue_free()
		_units.erase(nid)

func _apply_builds(b: PackedFloat32Array) -> void:
	var seen := {}
	var i := 0
	while i + B_STRIDE <= b.size():
		var nid := int(b[i])
		var owner := int(b[i + 1])
		var t_i := int(b[i + 2])
		var age := int(b[i + 3])
		var pos := Vector2(b[i + 4], b[i + 5])
		var hp := b[i + 6]
		var prog := b[i + 7]
		seen[nid] = true
		var n: Node = _builds.get(nid)
		if n == null or not is_instance_valid(n):
			var tipus: String = Building.TIPUS_ORDER[clampi(t_i, 0,
				Building.TIPUS_ORDER.size() - 1)]
			n = main.spawn_building(tipus, owner, pos, prog >= 1.0)
			n.nid = nid
			n.age = age
			_builds[nid] = n
		n.net_apply(hp, prog)
		i += B_STRIDE
	for nid in _builds.keys():
		if seen.has(nid): continue
		var n: Node = _builds[nid]
		if is_instance_valid(n): n.queue_free()
		_builds.erase(nid)

# --- Parancsok (csatlakozó -> házigazda) ---
#
# A csatlakozó SEMMIT nem hajt végre magától: a kattintásából üzenet lesz,
# és a házigazda dönt. Így nem csúszhat szét a két világ.

func send_cmd(kind: String, args: Array) -> void:
	if Net.is_host():
		_run_cmd(GameState.en_id, kind, args)
	else:
		Net.rpc_id(Net.host_peer, "_srv_cmd", kind, args)

# A Net autoload adja tovább: a feladó peer-számából lesz az oldal.
func handle_cmd(peer: int, kind: String, args: Array) -> void:
	var owner := _side_of_peer(peer)
	if owner < 0: return
	_run_cmd(owner, kind, args)

var _peer_side: Dictionary = {}

func set_peer_sides(sides: Array) -> void:
	_peer_side.clear()
	for i in sides.size():
		var d: Dictionary = sides[i]
		if d.has("peer"): _peer_side[int(d["peer"])] = i

func _side_of_peer(peer: int) -> int:
	return int(_peer_side.get(peer, -1))

func _run_cmd(owner: int, kind: String, args: Array) -> void:
	if main == null or not is_instance_valid(main): return
	match kind:
		"move":   main.do_move(args[0], args[1], owner)
		"attack": main.do_attack(args[0], int(args[1]), owner)
		"gather": main.do_gather(args[0], int(args[1]), owner)
		"stop":   main.do_stop(args[0], owner)
		"build":  main.do_build(str(args[0]), args[1], owner)
		"train":  main.do_train(int(args[0]), str(args[1]), owner)
		"rally":  main.do_rally(int(args[0]), args[1], int(args[2]),
					int(args[3]), owner)
		"era":    main.do_era(owner)
		"pbuild": main.do_port_build(str(args[0]), str(args[1]), owner)
		"ptrain": main.do_port_train(str(args[0]), str(args[1]), owner)
		"stance": main.do_stance(args[0], str(args[1]), owner)
		"form":   main.do_formation(str(args[0]), owner)
		"upg":    main.do_research(int(args[0]), owner)
