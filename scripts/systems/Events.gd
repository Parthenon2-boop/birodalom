extends Node

# ESEMÉNYEK  (index.html: a sorsolt események)
#
# Néhány percenként történik valami a térképen. Négyféle:
#
#   KERESKEDŐHAJÓ — semleges hajó vág át a vízen, kinccsel a fedélzetén.
#                   Aki elsüllyeszti, megkapja a rakományát.
#   PARTRA VETETT RONCS — a parton aranyat rejtő roncs bukkan fel, azt ki
#                   lehet termelni.
#   ZSOLDOSOK     — fegyveresek ajánlkoznak aranyért. Elfogadod vagy sem;
#                   az ajánlat lejár.
#   PESTIS        — egy fél fővárosa körül járvány üt ki: a közelben álló
#                   egységek lassan sorvadnak (de nem halnak bele).
#
# Melyik felet éri az esemény, azt a SZIMULÁCIÓS MAGBÓL sorsoljuk, nem a
# helyi játékosból — különben hálózaton minden gépen mást jelentene.

const EVENT_MIN := 95.0
const EVENT_MAX := 175.0
const EVENT_CHANCE := 0.55
const AJANLAT_LEJAR := 28.0
const PESTIS_SUGAR := 300.0
const PESTIS_HOSSZ := 22.0
const PESTIS_SORVAD := 0.014

var main: Node = null
# A futó zsoldos-ajánlat: {"db","ar","szerep","t"} — a HUD ebből rajzol.
var offer: Dictionary = {}
var plague: Dictionary = {}

signal offer_changed

var _t := EVENT_MIN
var _rng := RandomNumberGenerator.new()

func _init(m: Node = null) -> void:
	main = m

func _ready() -> void:
	name = "Events"
	if main == null: main = get_tree().get_first_node_in_group("main")
	_rng.seed = GameState.sim_mag ^ 0x0E4E
	_t = EVENT_MIN + _rng.randf() * (EVENT_MAX - EVENT_MIN)

func _process(delta: float) -> void:
	if not GameState.on or GameState.over or GameState.net_client: return
	_plague_tick(delta)
	# A lejáró ajánlat magától elenyészik.
	if not offer.is_empty() and GameState.t - float(offer["t"]) > AJANLAT_LEJAR:
		offer = {}
		offer_changed.emit()
	_t -= delta
	if _t > 0.0: return
	_t = EVENT_MIN + _rng.randf() * (EVENT_MAX - EVENT_MIN)
	if _rng.randf() > EVENT_CHANCE: return
	# Súlyozott sorsolás: a hajó, a roncs és a zsoldos gyakori, a pestis ritka.
	var lista := [["hajo", 3.0], ["roncs", 3.0], ["zsoldos", 3.0], ["pestis", 1.0]]
	var ossz := 0.0
	for e in lista: ossz += float(e[1])
	var r := _rng.randf() * ossz
	for e in lista:
		r -= float(e[1])
		if r <= 0.0:
			match str(e[0]):
				"hajo": _ev_merchant()
				"roncs": _ev_wreck()
				"zsoldos": _ev_mercs()
				_: _ev_plague()
			return

# --- 1. Kereskedőhajó: kinccsel a fedélzetén vág át a vízen ---
func _ev_merchant() -> void:
	if main == null: return
	var start := _random_water(400)
	if start == Vector2.INF: return
	var cel := Vector2.INF
	for _i in range(400):
		var p := _random_water(1)
		if p != Vector2.INF and p.distance_to(start) > 700.0:
			cel = p
			break
	if cel == Vector2.INF: return
	# A semleges hajó a BOT oldalán úszik: aki elsüllyeszti, zsákmányol.
	var h = main.spawn_unit("fisher", 1, start, GameState.get_age(1))
	if h == null: return
	var kincs: float = 180.0 + round(_rng.randf() * 220.0)
	h.set_meta("merchant", true)
	h.set_meta("treasure", kincs)
	h.max_hp *= 1.6
	h.hp = h.max_hp
	h.auto_gather = false
	h.move_to(cel)
	if main.hud != null:
		main.hud.show_toast(Lang.t("ev_kereskedo") % int(kincs), 4.0)

# --- 2. Partra vetett roncs: aranyat rejt ---
func _ev_wreck() -> void:
	if main == null: return
	for _i in range(500):
		var p := Vector2(_rng.randf_range(80, GameState.WORLD_W - 80),
			_rng.randf_range(80, GameState.WORLD_H - 80))
		if main.terrain.is_water(p): continue
		var partkozel := false
		for a in range(8):
			var szog := TAU * float(a) / 8.0
			if main.terrain.is_water(p + Vector2(cos(szog), sin(szog)) * 70.0):
				partkozel = true
				break
		if not partkozel: continue
		var n = main.terrain.add_resource("gold_node", p)
		if n != null:
			n.amount = 260.0 + round(_rng.randf() * 260.0)
			n.max_amount = n.amount
		if main.hud != null:
			main.hud.show_toast(Lang.t("ev_roncs"), 4.0)
		return

# --- 3. Zsoldosok: fegyveresek ajánlkoznak aranyért ---
func _ev_mercs() -> void:
	var db := 2 + int(_rng.randf() * 3.0)
	var ar := int(round((90.0 + _rng.randf() * 80.0) * float(db) / 2.0))
	var szerep: String = ["melee", "ranged", "spear"][int(_rng.randf() * 3.0)]
	offer = {"db": db, "ar": ar, "szerep": szerep, "t": GameState.t}
	offer_changed.emit()
	if main != null and main.hud != null:
		main.hud.show_toast(Lang.t("ev_zsoldos") % [db, ar], 6.0)

# Az ajánlat elfogadása (a HUD gombja hívja).
func accept_offer() -> bool:
	if offer.is_empty() or main == null: return false
	var ar := int(offer["ar"])
	if float(GameState.get_res(GameState.en_id).get("gold", 0.0)) < float(ar):
		if main.hud != null: main.hud.show_toast(Lang.t("ev_nincs_arany"), 2.5)
		return false
	GameState.add_res(GameState.en_id, "gold", -float(ar))
	var hq: Node = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.tipus == "hq" and int(b.owner_id) == GameState.en_id:
			hq = b
			break
	var kozep: Vector2 = hq.global_position if hq != null \
		else Vector2(GameState.WORLD_W, GameState.WORLD_H) * 0.5
	for i in range(int(offer["db"])):
		var szog := TAU * float(i) / float(maxi(int(offer["db"]), 1))
		var p: Vector2 = main.find_land_near(kozep + Vector2(cos(szog), sin(szog)) * 120.0, 30.0)
		if p == Vector2.INF: continue
		main.spawn_unit(str(offer["szerep"]), GameState.en_id, p,
			GameState.get_age(GameState.en_id))
	if main.hud != null:
		main.hud.show_toast(Lang.t("ev_zsoldos_jott") % int(offer["db"]), 3.0)
	SFX.play("build")
	offer = {}
	offer_changed.emit()
	return true

func decline_offer() -> void:
	offer = {}
	offer_changed.emit()
	SFX.play("click")

# --- 4. Pestis: járvány az egyik fél fővárosa körül ---
func _ev_plague() -> void:
	var fel := _rng.randi_range(0, maxi(GameState.oldalak.size() - 1, 0))
	var hq: Node = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.tipus == "hq" and int(b.owner_id) == fel:
			hq = b
			break
	if hq == null: return
	plague = {"hely": hq.global_position, "t": 0.0, "fel": fel}
	if fel == GameState.en_id and main != null and main.hud != null:
		main.hud.show_toast(Lang.t("ev_pestis"), 5.0)

func _plague_tick(delta: float) -> void:
	if plague.is_empty(): return
	plague["t"] = float(plague["t"]) + delta
	var kozep: Vector2 = plague["hely"]
	var fel := int(plague["fel"])
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u) or int(u.owner_id) != fel: continue
		if u.global_position.distance_to(kozep) > PESTIS_SUGAR: continue
		# A pestis sorvaszt, de önmagában nem öl meg senkit.
		u.hp = maxf(1.0, u.hp - u.max_hp * PESTIS_SORVAD * delta)
	if float(plague["t"]) >= PESTIS_HOSSZ:
		plague = {}
		if fel == GameState.en_id and main != null and main.hud != null:
			main.hud.show_toast(Lang.t("ev_jarvany_vege"), 3.0)

func _random_water(probak: int) -> Vector2:
	if main == null: return Vector2.INF
	for _i in range(maxi(probak, 1)):
		var p := Vector2(_rng.randf_range(60, GameState.WORLD_W - 60),
			_rng.randf_range(60, GameState.WORLD_H - 60))
		if main.terrain.is_water(p): return p
	return Vector2.INF

# A semleges kereskedőhajó zsákmánya, ha elsüllyesztik.
func merchant_loot(u: Node, killer_owner: int) -> void:
	if u == null or not bool(u.get_meta("merchant", false)): return
	var kincs := float(u.get_meta("treasure", 0.0))
	if kincs <= 0.0: return
	GameState.add_res(killer_owner, "gold", kincs)
	if killer_owner == GameState.en_id and main != null and main.hud != null:
		main.hud.show_toast(Lang.t("ev_zsakmany") % int(kincs), 3.5)
	u.set_meta("treasure", 0.0)
