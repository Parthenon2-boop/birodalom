extends Node

# GAZDASÁGI RENDSZEREK — az eredeti (index.html) három ütemezője egy helyen.
#
# 1. ÚJRANÖVEKEDÉS
#    A kitermelt erdő lassan visszanő, és időnként új kő-, arany-, szén- és
#    hallelőhely is felbukkan — enélkül hosszú játszmában kiszárad a térkép.
#
# 2. ELLÁTÁS (7/C)
#    A sereg eszik. Minden egység másodpercenként fogyaszt a készletből: a
#    munkás keveset, a hős és a hadihajó sokat. Ha elfogy az élelem, a
#    katonák lassan gyengülnek — nem halnak éhen, de harcképtelenné válnak.
#    Ettől a nagy sereg döntés lesz, nem automatizmus, és az ellenfél
#    majorságai értelmes célponttá válnak.
#
# 3. KERESKEDELMI ÚTVONAL (7/C)
#    Ha áll a kikötőd, időnként kereskedőhajó indul belőle egy távoli
#    semleges vízre, és arannyal tér vissza. Az ellenség elsüllyesztheti —
#    a jövedelem tehát sebezhető, őrizni kell.

# --- Ellátás ---
const UPKEEP := {
	"worker": 0.010, "melee": 0.036, "ranged": 0.032, "spear": 0.032,
	"priest": 0.026, "medic": 0.024, "siege": 0.055, "hero": 0.090,
	"ram": 0.050, "spy": 0.026, "cav": 0.045,
	"fisher": 0.018, "warship": 0.055, "galleon": 0.070, "transport": 0.040,
	"scout": 0.026, "fighter": 0.060, "bomber": 0.075,
}
const UPKEEP_ALAP := 0.03
const STARVE_RATE := 0.006        # éhezéskor ennyi életerő fogy másodpercenként

# --- Újranövekedés ---
const WOOD_KOZ := 13.0
const WOOD_MAX := 170
const ERC_KOZ := 46.0
const STONE_MAX := 34
const GOLD_MAX := 22
const COAL_KOZ := 55.0
const COAL_MAX := 14
const FISH_KOZ := 44.0
const FISH_MAX := 22

# --- Kereskedelmi útvonal ---
const TRADE_EVERY := 75.0
const TRADE_GOLD := [110.0, 150.0, 200.0, 260.0]
const TRADE_TAV := 900.0          # ilyen messzire megy a kereskedő

var main: Node = null
var starving: Array[bool] = []

var _wood_t := WOOD_KOZ
var _erc_t := ERC_KOZ
var _coal_t := COAL_KOZ
var _fish_t := FISH_KOZ
var _trade_t := TRADE_EVERY
var _rng := RandomNumberGenerator.new()

func _init(m: Node = null) -> void:
	main = m

func _ready() -> void:
	name = "Economy"
	if main == null: main = get_tree().get_first_node_in_group("main")
	_rng.seed = GameState.sim_mag ^ 0x0EC0
	starving.resize(maxi(GameState.oldalak.size(), 2))
	starving.fill(false)

func _process(delta: float) -> void:
	# A csatlakozó semmit nem szimulál: nála a házigazda pillanatképe dönt.
	if not GameState.on or GameState.net_client: return
	_supply(delta)
	_regrow(delta)
	_trade_route(delta)
	# A kereskedőhajók útja (oda — vissza — fizet).
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and bool(u.get_meta("trader", false)):
			trader_tick(u)

# ── 2. ELLÁTÁS ────────────────────────────────────────────────

func upkeep_of(owner_id: int) -> float:
	var n := 0.0
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u) or int(u.owner_id) != owner_id: continue
		n += float(UPKEEP.get(u.role, UPKEEP_ALAP))
		# A szállítóhajó rakománya is eszik.
		if u.has_method("can_carry") and u.can_carry():
			for c in u.cargo:
				if is_instance_valid(c): n += float(UPKEEP.get(c.role, UPKEEP_ALAP))
	return n

# Mennyi élelem folyik be másodpercenként (ebből látszik, jó úton jársz-e).
func food_income(owner_id: int) -> float:
	var n := 0.0
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or int(b.owner_id) != owner_id: continue
		if not b.is_ready(): continue
		var st: Dictionary = Building.BUILD_STATS.get(b.tipus, {})
		if st.has("food"):
			n += float((st["food"] as Array)[clampi(int(b.age), 0, 3)])
	return n

# A mérleg: mennyi élelem folyik be, és mennyit eszik a sereg.
func food_balance(owner_id: int) -> float:
	return food_income(owner_id) - upkeep_of(owner_id)

func _supply(delta: float) -> void:
	if starving.size() < GameState.oldalak.size():
		starving.resize(GameState.oldalak.size())
	for owner in range(GameState.oldalak.size()):
		var res := GameState.get_res(owner)
		if res.is_empty(): continue
		var kell := upkeep_of(owner) * delta
		if float(res.get("food", 0.0)) >= kell:
			res["food"] = float(res["food"]) - kell
			if owner < starving.size() and starving[owner]:
				starving[owner] = false
			continue
		# Nincs elég: ami van, elfogy, a többiek éheznek.
		res["food"] = 0.0
		if owner < starving.size() and not starving[owner]:
			starving[owner] = true
			if owner == GameState.en_id and main != null and main.hud != null:
				main.hud.show_toast(Lang.t("ehezes"), 4.0)
		for u in get_tree().get_nodes_in_group("units"):
			if not is_instance_valid(u) or int(u.owner_id) != owner: continue
			if u.role == "worker": continue
			u.hp = maxf(1.0, u.hp - u.max_hp * STARVE_RATE * delta)
	GameState.resources_changed.emit()

# ── 1. ÚJRANÖVEKEDÉS ──────────────────────────────────────────

func _count_nodes(kind: String) -> int:
	var n := 0
	for r in get_tree().get_nodes_in_group("resources"):
		if is_instance_valid(r) and r.kind == kind: n += 1
	return n

func _far_from_nodes(p: Vector2, tav: float, kind: String = "") -> bool:
	for r in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(r): continue
		if kind != "" and r.kind != kind: continue
		if r.global_position.distance_to(p) < tav: return false
	return true

func _far_from_buildings(p: Vector2, tav: float) -> bool:
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b): continue
		if b.global_position.distance_to(p) < tav: return false
	return true

func _regrow(delta: float) -> void:
	var terrain = main.terrain if main != null else null
	if terrain == null: return
	# Erdő: egy meglévő folt mellé nő az új.
	_wood_t -= delta
	if _wood_t <= 0.0:
		_wood_t = WOOD_KOZ
		if _count_nodes("wood_node") < WOOD_MAX:
			var magok: Array = []
			for r in get_tree().get_nodes_in_group("resources"):
				if is_instance_valid(r) and r.kind == "wood_node": magok.append(r)
			for _i in range(24):
				var p: Vector2
				if magok.is_empty():
					p = Vector2(_rng.randf_range(200, GameState.WORLD_W - 200),
						_rng.randf_range(200, GameState.WORLD_H - 200))
				else:
					var mag = magok[_rng.randi_range(0, magok.size() - 1)]
					var a := _rng.randf_range(0.0, TAU)
					var d := _rng.randf_range(30.0, 110.0)
					p = mag.global_position + Vector2(cos(a), sin(a)) * d
					p.x = clampf(p.x, 60.0, GameState.WORLD_W - 60.0)
					p.y = clampf(p.y, 60.0, GameState.WORLD_H - 60.0)
				if terrain.is_water(p): continue
				if not _far_from_nodes(p, 26.0): continue
				if not _far_from_buildings(p, 130.0): continue
				terrain.add_resource("wood_node", p)
				break
	# Kő és arany: új telér bukkan fel.
	_erc_t -= delta
	if _erc_t <= 0.0:
		_erc_t = ERC_KOZ
		for kind in ["stone_node", "gold_node"]:
			var hatar: int = STONE_MAX if kind == "stone_node" else GOLD_MAX
			if _count_nodes(kind) >= hatar: continue
			for _i in range(30):
				var p := Vector2(_rng.randf_range(160, GameState.WORLD_W - 160),
					_rng.randf_range(160, GameState.WORLD_H - 160))
				if terrain.is_water(p): continue
				if not _far_from_nodes(p, 30.0): continue
				if not _far_from_buildings(p, 150.0): continue
				terrain.add_resource(kind, p)
				break
	# (Szén: a portban nincs szénlelőhely — a szenet a bánya és a korszak
	# adja —, ezért abból nincs mit visszanövesztni.)
	# Halraj a vízen.
	_fish_t -= delta
	if _fish_t <= 0.0:
		_fish_t = FISH_KOZ
		if _count_nodes("fish_node") < FISH_MAX:
			for _i in range(200):
				var p := Vector2(_rng.randf_range(60, GameState.WORLD_W - 60),
					_rng.randf_range(60, GameState.WORLD_H - 60))
				if not terrain.is_water(p): continue
				if not _far_from_nodes(p, 110.0, "fish_node"): continue
				terrain.add_resource("fish_node", p)
				break

# ── 3. KERESKEDELMI ÚTVONAL ───────────────────────────────────

func _trade_route(delta: float) -> void:
	_trade_t -= delta
	if _trade_t > 0.0: return
	_trade_t = TRADE_EVERY
	if main == null: return
	var kikotok: Array = []
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.tipus == "harbor" and b.is_ready():
			kikotok.append(b)
	if kikotok.is_empty(): return
	# Egyszerre egy hajó van úton.
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and u.get_meta("trader", false): return
	var h = kikotok[_rng.randi_range(0, kikotok.size() - 1)]
	# A cél: távoli nyílt víz.
	var cel := Vector2.INF
	for _i in range(500):
		var p := Vector2(_rng.randf_range(60, GameState.WORLD_W - 60),
			_rng.randf_range(60, GameState.WORLD_H - 60))
		if main.terrain.is_water(p) and p.distance_to(h.global_position) > TRADE_TAV:
			cel = p
			break
	if cel == Vector2.INF: return
	# Indulás a kikötő melletti vízről.
	var start: Vector2 = main.find_land_near(h.global_position, 24.0, true)
	if start == Vector2.INF: return
	var t = main.spawn_unit("fisher", int(h.owner_id), start, GameState.get_age(int(h.owner_id)))
	if t == null: return
	t.set_meta("trader", true)
	t.set_meta("home", h.global_position)
	t.set_meta("gold", float(TRADE_GOLD[clampi(GameState.get_age(int(h.owner_id)), 0, 3)]))
	t.set_meta("phase", "oda")
	t.max_hp *= 1.5
	t.hp = t.max_hp
	t.auto_gather = false
	t.move_to(cel)
	if int(h.owner_id) == GameState.en_id and main.hud != null:
		main.hud.show_toast(Lang.t("kereskedo_indult") % int(t.get_meta("gold")), 3.5)

# A kereskedőhajó útja: oda, majd vissza. Ha hazaér, fizet.
# (A Unit hívja minden lépésben, ha a "trader" jelölő rajta van.)
func trader_tick(u: Node) -> bool:
	if not u.get_meta("trader", false): return false
	var home: Vector2 = u.get_meta("home", Vector2.ZERO)
	if str(u.get_meta("phase", "oda")) == "oda":
		if u.nav.is_navigation_finished():
			u.set_meta("phase", "vissza")
			u.move_to(home)
			u.auto_gather = false
		return false
	if u.global_position.distance_to(home) < 110.0:
		var arany: float = float(u.get_meta("gold", 120.0))
		GameState.add_res(int(u.owner_id), "gold", arany)
		if int(u.owner_id) == GameState.en_id and main != null and main.hud != null:
			main.hud.show_toast(Lang.t("kereskedo_beert") % int(arany), 3.5)
		u.queue_free()
		return true
	return false
