class_name Tutorial
extends Node

# Oktatómód. Lépésről lépésre végigvezet a játék alapjain: kijelölés,
# gyűjtés, építés, képzés, harc. Minden lépésnek van egy feltétele; amint
# teljesül, jön a következő. A szövegek az assets/lang/*.json-ban vannak
# ("okt_<kulcs>"), a feltételek pedig itt, a jelenetfa alapján.
#
# A bot ilyenkor nem támad (a Main hosszúra állítja a hullámidejét), hogy
# nyugodtan végig lehessen menni a lépéseken.

const STEPS := [
	"kijelol", "gyujt", "haz", "laktanya", "katona", "tamad",
]

# Egy lépés akkor kész, ha ennyit ér el a hozzá tartozó mérő.
var main: Node = null
var step: int = 0
var done: bool = false
var _accum: float = 0.0
var _wood_start: float = 0.0

func _init(m: Node = null) -> void:
	main = m

func _ready() -> void:
	if main == null:
		main = get_tree().get_first_node_in_group("main")
	_wood_start = float(GameState.get_res(GameState.en_id).get("wood", 0.0))
	_show()

func _process(delta: float) -> void:
	if done or not GameState.on: return
	_accum += delta
	if _accum < 0.4: return          # elég másodpercenként párszor nézni
	_accum = 0.0
	if _check(STEPS[step]):
		step += 1
		if step >= STEPS.size():
			done = true
			_finish()
			return
		SFX.play("click")
		_show()

func title() -> String:
	return Lang.t("oktatomod")

func text() -> String:
	if done: return Lang.t("okt_kesz")
	return "%d/%d — %s" % [step + 1, STEPS.size(),
		Lang.t("okt_" + STEPS[step])]

func _show() -> void:
	if main == null or not is_instance_valid(main): return
	main.hud.show_tutorial(title(), text())
	main.hud.show_toast(text(), 6.0)

func _finish() -> void:
	if main == null or not is_instance_valid(main): return
	main.hud.update_objective(Lang.t("okt_kesz"))
	main.hud.show_toast(Lang.t("okt_kesz"), 8.0)
	Achievements.bump("tutorial")

# --- A lépések feltételei ---

func _check(key: String) -> bool:
	match key:
		"kijelol":  return _selected_worker()
		"gyujt":    return _gathering()
		"haz":      return _has_ready("house")
		"laktanya": return _has_ready("barracks")
		"katona":   return _army_size() >= 1
		"tamad":    return GameState.kills >= 1
	return true

func _selected_worker() -> bool:
	if main == null: return false
	for u in main.selected_units:
		if is_instance_valid(u) and u.role == "worker": return true
	return false

func _gathering() -> bool:
	for u in get_tree().get_nodes_in_group("player_units"):
		if not is_instance_valid(u) or u.role != "worker": continue
		if u.has_method("gather_node") and u.gather_node() != null: return true
	return false

func _has_ready(tipus: String) -> bool:
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if is_instance_valid(b) and b.tipus == tipus and b.is_ready(): return true
	return false

func _army_size() -> int:
	var n := 0
	for u in get_tree().get_nodes_in_group("player_units"):
		if is_instance_valid(u) and u.role in ["melee", "ranged", "spear", "cav"]:
			n += 1
	return n
