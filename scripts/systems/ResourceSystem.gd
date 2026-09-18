class_name ResourceSystem
extends RefCounted

# Nyersanyag-csomópontok és a munkások gyűjtési logikája.

# A munkás nem szemenként hordja a nyersanyagot: RÁÜT a lelőhelyre
# néhányszor, és a megtelt rakománnyal indul vissza a leadóhelyre.
const SWINGS_PER_LOAD := 15     # ennyit üt egy rakományért
const LOAD_AMOUNT := 20.0       # ennyit ér a teli rakomány
const SWING_TIME := 0.45        # ennyi idő két ütés között (mp)
const PER_SWING := LOAD_AMOUNT / float(SWINGS_PER_LOAD)

# Csomópont típus -> a raktárba kerülő erőforrás
const YIELD := {
	"wood_node":  "wood",
	"stone_node": "stone",
	"gold_node":  "gold",
	"food_node":  "food",
	"fish_node":  "food",
}

const AMOUNT := {
	"wood_node":  1400.0,
	"stone_node": 1100.0,
	"gold_node":  800.0,
	"food_node":  1000.0,
	"fish_node":  1200.0,
}

# A lelőhelyek a térképen jól láthatóak: egy erdőfolt vagy egy sziklacsoport
# nagyobb, mint egy egység, különben elvesznek a fűben.
const RADIUS := {
	"wood_node":  30.0,
	"stone_node": 26.0,
	"gold_node":  24.0,
	"food_node":  24.0,
	"fish_node":  25.0,
}

# A raktári nyersanyagok jelzőszínei (a munkás fölötti rakomány-címkéhez
# és a lelőhely kijelöléséhez).
const RES_COLOR := {
	"wood":  Color(0.58, 0.38, 0.19),
	"stone": Color(0.66, 0.66, 0.70),
	"gold":  Color(0.88, 0.73, 0.22),
	"food":  Color(0.83, 0.35, 0.31),
	"coal":  Color(0.26, 0.26, 0.29),
	"rum":   Color(0.74, 0.44, 0.18),
}

static func res_color(res_key: String) -> Color:
	var c: Color = RES_COLOR.get(res_key, Color(0.85, 0.85, 0.85))
	return c

static func yield_kind(node_kind: String) -> String:
	return YIELD.get(node_kind, "wood")

static func node_amount(node_kind: String) -> float:
	return float(AMOUNT.get(node_kind, 900.0))

static func node_radius(node_kind: String) -> float:
	return float(RADIUS.get(node_kind, 14.0))

# Munkásonként szétosztott nyersanyagok. A kezdő munkások körben kapják
# meg őket, így mind a négy készlet gyűl.
const PREF_CYCLE := ["wood_node", "food_node", "stone_node", "gold_node"]

# A munkás először a saját nyersanyagából keresi a legközelebbi lelőhelyet;
# ha az elfogyott a térképről, bármelyik szárazföldit elvállalja.
# A halász csak a vízi csomópontokat.
static func find_node_for(unit: Node2D) -> Node2D:
	var tree := unit.get_tree()
	if tree == null: return null
	if unit.role == "fisher":
		return _nearest(tree, unit.global_position, "fish_node")
	var pref: String = unit.gather_pref
	if pref != "" and pref != "fish_node":
		var n := _nearest(tree, unit.global_position, pref)
		if n != null: return n
	return _nearest(tree, unit.global_position, "")

static func _nearest(tree: SceneTree, from: Vector2, kind: String) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for n in tree.get_nodes_in_group("resources"):
		if not is_instance_valid(n): continue
		if kind != "":
			if n.kind != kind: continue
		elif n.kind == "fish_node":
			continue
		var d: float = n.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = n
	return best

# A legközelebbi saját leadóhely. A halász csak a kikötőbe tud bemenni,
# a szárazföldi munkás viszont bármelyik leadóhelyre.
static func find_dropoff(unit: Node2D) -> Node2D:
	var tree := unit.get_tree()
	if tree == null: return null
	var naval: bool = unit.naval
	var best: Node2D = null
	var best_d := INF
	for b in tree.get_nodes_in_group("dropoff"):
		if not is_instance_valid(b): continue
		if b.owner_id != unit.owner_id: continue
		if not b.is_ready(): continue
		if naval and b.tipus != "harbor": continue
		var d: float = b.global_position.distance_to(unit.global_position)
		if d < best_d:
			best_d = d
			best = b
	return best

const POP_BASE := 20
const POP_MAX  := 90

# Egy oldal összes népesség-korlátja (alap + házak).
static func pop_limit(tree: SceneTree, owner_id: int) -> int:
	var limit := POP_BASE
	for b in tree.get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.owner_id == owner_id and b.is_ready():
			limit += Building.pop_bonus(b.tipus)
	return mini(limit, POP_MAX)

# Élő egységek + a képzési sorokban állók.
static func pop_used(tree: SceneTree, owner_id: int) -> int:
	var used := 0
	for u in tree.get_nodes_in_group("units"):
		if is_instance_valid(u) and u.owner_id == owner_id:
			used += 1
	for b in tree.get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.owner_id == owner_id:
			used += b.train_queue.size()
	return used
