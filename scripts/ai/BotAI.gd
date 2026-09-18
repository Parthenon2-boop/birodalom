extends Node

# Egy gépi ellenfél. Több fél is lehet a pályán, ezért NEM egy rögzített
# oldalt vezet: a `bot_id`-t a Main adja meg induláskor, és minden bot
# oldalhoz külön ilyen csomópont készül.

var bot_id: int = 1

# A nehézség a hullámok gyakoriságát és méretét skálázza (GameState.diff).
const DIFF_RATE := [0.75, 1.0, 1.35]

var wave_timer  : float = 60.0
var build_timer : float = 25.0
var seen := {"melee": 0, "ranged": 0, "spear": 0, "cav": 0, "warship": 0}
var _seen_t: float = 0.0

func start(id: int = 1) -> void:
	bot_id = id
	var side := GameState.get_side(bot_id)
	if side.is_empty(): return
	side["rate"] = DIFF_RATE[clampi(GameState.diff, 0, 2)]
	# A hullámok ne egyszerre érkezzenek minden bottól: oldalanként eltolva.
	wave_timer = float(side.get("waveT", 115.0)) * (0.5 + 0.12 * float(id))
	build_timer = 25.0 + 4.0 * float(id)
	_era_ready_t = ERA_MIN_T / maxf(float(side["rate"]), 0.1)

func _process(delta: float) -> void:
	if not GameState.on or GameState.over: return
	if GameState.get_side(bot_id).is_empty(): return
	wave_timer  -= delta
	build_timer -= delta
	if wave_timer  <= 0: _send_wave()
	if build_timer <= 0: _build_tick()
	# A felderítés végigjárja az összes egységet; képkockánként megtenni
	# pazarlás — a hullámok amúgy is percenként indulnak.
	_seen_t -= delta
	if _seen_t <= 0.0:
		_seen_t = 2.0
		_update_seen()

func _send_wave() -> void:
	var side := GameState.get_side(bot_id)
	if side.is_empty():
		wave_timer = 60.0
		return
	# OKTATÓMÓDBAN NINCS TÁMADÁS. A Main a hullámidőt is kikapcsolja, de a
	# tiltás ITT is ott van: ha a bot előbb indulna el, mint a beállítás,
	# az első hullám még kifutna — pontosan ez történt korábban.
	if GameState.tutorial:
		wave_timer = 99999.0
		return
	wave_timer = float(side.get("waveT", 115.0)) / maxf(float(side.get("rate", 1.0)), 0.1)
	side["wave"] = int(side.get("wave", 0)) + 1
	var age: int = int(side.get("age", 0))
	var main := get_tree().get_first_node_in_group("main")
	if not main: return
	var origin := _own_hq_pos()
	var cel := _target_hq_pos(origin)
	var i := 0
	for role in _choose_composition(age):
		var a := TAU * float(i) / 8.0
		var pos: Vector2 = main.find_land_near(
			origin + Vector2(cos(a), sin(a)) * (120.0 + 8.0 * i), 40.0)
		var u: Node = main.spawn_unit(role, bot_id, pos, age)
		if u and u.has_method("move_to"):
			u.move_to(cel)
		i += 1

func _choose_composition(age: int) -> Array:
	var result: Array = []
	var count := 3 + age * 2 + int(GameState.diff)
	for _i in range(count):
		var r := randf()
		if int(seen.get("cav", 0)) > 2 and r < 0.4:
			result.append("spear")
		elif int(seen.get("ranged", 0)) > 3 and r < 0.5:
			result.append("melee")
		elif r < 0.55:  result.append("melee")
		elif r < 0.82:  result.append("ranged")
		else:           result.append("spear")
	return result

# Mit lát az ELLENSÉGES oldalakon — ebből állítja össze a következő hullámot.
func _update_seen() -> void:
	seen = {"melee": 0, "ranged": 0, "spear": 0, "cav": 0, "warship": 0}
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u): continue
		if not GameState.hostile(bot_id, int(u.owner_id)): continue
		if seen.has(u.role):
			seen[u.role] += 1

# Időközönként épít egy épületet a bázisa köré, és korszakot vált,
# ha elég erőforrása gyűlt össze.
func _build_tick() -> void:
	build_timer = 35.0
	var main := get_tree().get_first_node_in_group("main")
	if not main: return
	var counts := {}
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.owner_id == bot_id:
			counts[b.tipus] = int(counts.get(b.tipus, 0)) + 1
	# A kovácsműhely és az akadémia nélkül a bot nem tudna fejleszteni, és a
	# késői játékban a játékos fokozatai mellett esélye sem maradna.
	var want := ""
	if int(counts.get("farm", 0)) < 3:            want = "farm"
	elif int(counts.get("barracks", 0)) < 2:      want = "barracks"
	elif int(counts.get("smith", 0)) < 1:         want = "smith"
	elif int(counts.get("house", 0)) < 4:         want = "house"
	elif int(counts.get("tower", 0)) < 3:         want = "tower"
	elif int(counts.get("goldmine", 0)) < 2:      want = "goldmine"
	elif int(counts.get("academy", 0)) < 1:       want = "academy"
	elif int(counts.get("stable", 0)) < 1:        want = "stable"
	elif int(counts.get("hospital", 0)) < 1:      want = "hospital"
	# A kutatás nem VÁR a teljes bázisra: amint áll a kovácsműhely, és marad
	# tartalék a katonákra, a bot fejleszt. (Korábban csak akkor jutott
	# volna ide, ha a fenti lista mind a tizennyolc háza felépült — az a
	# gyakorlatban sosem következett be, és a bot sosem fejlesztett.)
	_try_research(counts)
	if want == "": return
	if not GameState.can_pay(bot_id, main.build_cost(bot_id, want)): return
	# A bázis köré keresünk szabad, szárazföldi helyet; ha 12 próbálkozásból
	# sincs, kihagyjuk ezt a kört.
	var origin := _own_hq_pos()
	var a := randf() * TAU
	var d := randf_range(150.0, 320.0)
	var pos: Vector2 = main.find_build_spot(want, origin + Vector2(cos(a), sin(a)) * d)
	if pos == Vector2.INF: return
	if not GameState.pay(bot_id, main.build_cost(bot_id, want)): return
	main.spawn_building(want, bot_id, pos)
	_try_advance_era()

# Ha már minden ház áll, a felesleg kutatásra megy. A bot csak akkor vesz
# fokozatot, ha marad tartaléka: enélkül minden aranyat elköltene, és nem
# maradna katonára. Mindig a legolcsóbb elérhető ágat választja, tehát a
# fejlesztései egyenletesen nőnek, nem egyetlen ág szalad el.
const RESEARCH_RESERVE := 300.0

func _try_research(counts: Dictionary) -> void:
	var res := GameState.get_res(bot_id)
	var legjobb := ""
	var legolcsobb := INF
	for key in Upgrades.ORDER:
		var hol := str((Upgrades.UPG[key] as Dictionary)["hol"])
		if int(counts.get(hol, 0)) < 1: continue     # nincs hozzá épület
		if not Upgrades.available(bot_id, key): continue
		var cost: Dictionary = Upgrades.cost(bot_id, key)
		var ossz := 0.0
		var telik := true
		for k in cost:
			ossz += float(cost[k])
			if float(res.get(k, 0.0)) < float(cost[k]) + RESEARCH_RESERVE:
				telik = false
		if telik and ossz < legolcsobb:
			legolcsobb = ossz
			legjobb = key
	if legjobb != "":
		Upgrades.research(bot_id, legjobb)

# A KORSZAKVÁLTÁS ÁRA A BOTNAK IS ANNYI, MINT A JÁTÉKOSNAK.
#
# Korábban rögzített összeg (900 arany + 700 kő) volt a feltétel, a KEZDŐ
# készlet viszont korszakonként nő: a 19. századi játszmában a bot már az
# első építési körben, fél percen belül ki tudta fizetni — a játékos tehát
# a 19. században azonnal világháborús katonákkal találkozott. Innentől a
# bot a játékos árlistájából fizet, tartalékot hagy a hadseregre, és két
# váltás között el kell telnie egy kis időnek.
const ERA_RESERVE := 400.0
const ERA_MIN_T := 300.0        # legalább ennyi másodperc két váltás között

var _era_ready_t: float = ERA_MIN_T

func _try_advance_era() -> void:
	var side := GameState.get_side(bot_id)
	if side.is_empty(): return
	var age: int = int(side.get("age", 0))
	if age >= 3: return
	if GameState.t < _era_ready_t: return
	var cost: Dictionary = Style.ERA_COST[clampi(age, 0, 3)]
	if cost.is_empty(): return
	var res := GameState.get_res(bot_id)
	for k in cost:
		if float(res.get(k, 0.0)) < float(cost[k]) + ERA_RESERVE: return
	if not GameState.pay(bot_id, cost): return
	GameState.advance_era(bot_id)
	# A következő váltás nem jöhet közvetlenül utána: nehéz fokozaton
	# hamarabb, könnyűn később.
	_era_ready_t = GameState.t + ERA_MIN_T / maxf(float(side.get("rate", 1.0)), 0.1)

func _own_hq_pos() -> Vector2:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Building and b.owner_id == bot_id and b.tipus == "hq":
			return b.global_position
	return Vector2(GameState.WORLD_W - 300, 300)

# A LEGKÖZELEBBI ellenséges főváros — több fél esetén nem mindig a játékosé.
func _target_hq_pos(from: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for b in get_tree().get_nodes_in_group("buildings"):
		if not (b is Building) or b.tipus != "hq": continue
		if not GameState.hostile(bot_id, int(b.owner_id)): continue
		var d: float = b.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = b.global_position
	if best == Vector2.INF:
		return Vector2(300, GameState.WORLD_H - 300)
	return best
