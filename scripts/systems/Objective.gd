class_name Objective
extends RefCounted

# A hadjárat-küldetések célfigyelője. Minden képkockán megnézi, hogy a
# jelenlegi cél teljesült-e, és megadja az aktuális állást a HUD-nak.
#
# Céltípusok (az eredeti index.html `obj` mezője szerint):
#   build     b, n     — n darab adott típusú épület álljon készen
#   buildAny  n        — összesen n épület álljon készen
#   gather    res, amount — ennyit termelj ki összesen az adott nyersanyagból
#   kill      n        — n ellenséges egységet/épületet semmisíts meg
#   survive   sec      — tarts ki ennyi másodpercig
#   destroy            — az ellenfélnek ne maradjon épülete
#   age       age      — érd el ezt a korszakot

var mission : Dictionary = {}
var done    : bool = false
var failed  : bool = false

func _init(m: Dictionary) -> void:
	mission = m

func obj() -> Dictionary:
	return mission.get("obj", {})

func target() -> int:
	return Campaign.target_of(mission)

# Az aktuális állás — ugyanabban a mértékegységben, mint a cél.
func progress(tree: SceneTree) -> int:
	var o := obj()
	match str(o.get("type", "")):
		"build":
			var t := str(o.get("b", ""))
			var n := 0
			for b in tree.get_nodes_in_group("player_buildings"):
				if is_instance_valid(b) and b.tipus == t and b.is_ready(): n += 1
			return n
		"buildAny":
			var n2 := 0
			for b in tree.get_nodes_in_group("player_buildings"):
				if is_instance_valid(b) and b.is_ready(): n2 += 1
			return n2
		"gather":
			return int(GameState.earned.get(str(o.get("res", "gold")), 0.0))
		"kill":
			return GameState.kills
		"survive":
			return int(GameState.t)
		"age":
			return GameState.get_age(GameState.en_id)
		"destroy":
			return 0
	return 0

func check(tree: SceneTree) -> void:
	if done or failed: return
	# A saját főváros elvesztése bukás — ezt a GameState jelzi.
	if GameState.over and GameState.winner != GameState.en_id:
		failed = true
		return
	var o := obj()
	var t := str(o.get("type", ""))
	if t == "destroy":
		if GameState.over and GameState.winner == GameState.en_id:
			done = true
		return
	if t == "age":
		done = GameState.get_age(GameState.en_id) >= int(o.get("age", 1))
		return
	done = progress(tree) >= target()

func text(tree: SceneTree) -> String:
	var t := str(obj().get("type", ""))
	if t == "destroy":
		return Campaign.objective_text(mission)
	return Campaign.objective_text(mission, progress(tree))
