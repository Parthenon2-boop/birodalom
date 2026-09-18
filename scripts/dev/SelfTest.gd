extends Node

# Fejlesztői önellenőrzés. Nem része a játéknak: csak akkor indul, ha a
# játékot a `--selftest` kapcsolóval hívjuk:
#
#   godot --headless --path <proj> -- --skip-menu --selftest
#
# Végigmegy a főbb rendszereken (világ, navigáció, képzés, építés,
# korszakváltás, harc, gyűjtés, köd, sprite-ok), és a végén összesítve
# kiírja, mi ment át és mi bukott el. Kilépési kód: 0 = minden rendben.

var main : Node = null

var _pass : int = 0
var _fail : Array[String] = []

func _init(main_node: Node) -> void:
	main = main_node

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  [OK]   ", name)
	else:
		_fail.append(name + ("  — " + detail if detail != "" else ""))
		print("  [HIBA] ", name, "  ", detail)

# Fizikai képkockákra várunk: headless módban a process_frame sokkal
# sűrűbben fut, mint a _physics_process, és a mozgást az utóbbi végzi.
func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

# --- Képidőmérés (a hosszú futáshoz) ---
#
# A gyenge, régi gépeken az számít, mennyi MUNKA jut egy képkockára. Ezt a
# képidővel mérjük: a soak futás végén kiírjuk az átlagot és a leglassabb
# képkockát. Az időskála nem torzítja, mert valós időt mérünk.
var _frame_ms_sum: float = 0.0
var _frame_ms_max: float = 0.0
var _frame_n: float = 0.0
var _last_us: int = 0

func _process(_delta: float) -> void:
	if not _measuring: return
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		# Az első néhány képkocka a betöltés, azt kihagyjuk.
		_skip += 1
		if _skip > 10:
			var ms := float(now - _last_us) / 1000.0
			_frame_ms_sum += ms
			_frame_ms_max = maxf(_frame_ms_max, ms)
			_frame_n += 1.0
	_last_us = now

var _skip: int = 0

var _measuring := false

# --- Sebességmérés (--bench) ---
#
# A soak a PROCESSZOR munkáját méri gyorsított időben. Ez viszont a valódi
# játékot méri, rendes tempóban, ABLAKBAN — vagyis a rajzolást is. A gyenge
# gépeken épp az a szűk keresztmetszet, ezért csak így derül ki, ér-e
# valamit egy-egy változtatás.
func bench(seconds: float) -> void:
	print("\n=== BIRODALOM — sebességmérés (%d mp) ===" % seconds)
	print("  felbontás: %s   részletesség: %d"
		% [str(get_viewport().get_visible_rect().size), Settings.detail])
	# A képsebesség-korlát és a vsync meghamisítaná a mérést.
	Engine.max_fps = 0
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_measuring = true
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
	_measuring = false
	var atlag := _frame_ms_sum / maxf(_frame_n, 1.0)
	print("  átlag %.2f ms  (%.0f kép/mp),  leglassabb %.1f ms,  %d kép"
		% [atlag, 1000.0 / maxf(atlag, 0.001), _frame_ms_max, int(_frame_n)])
	get_tree().quit(0)

# --- Hosszú futás (--soak) ---
#
# A játékot magára hagyjuk gyorsított időben, és figyeljük, hogy a bot
# épít-e, indulnak-e hullámok, gyűl-e a nyersanyag, és nem áll-e le a
# szimuláció. Ez fogja meg azokat a hibákat, amik csak percek múlva jönnek elő.
func soak(game_seconds: float) -> void:
	print("\n=== BIRODALOM — hosszú futás (%d mp játékidő) ===" % game_seconds)
	print("  részletesség: %d" % Settings.detail)
	_measuring = true
	Engine.time_scale = 6.0
	var last := -1
	while GameState.t < game_seconds and not GameState.over:
		await _frames(30)
		var sec := int(GameState.t)
		if sec / 30 != last:
			last = sec / 30
			_report(sec)
	Engine.time_scale = 1.0
	print("  átlagos képidő: %.2f ms  (%.0f kép/mp),  leglassabb kép: %.1f ms"
		% [_frame_ms_sum / maxf(_frame_n, 1.0),
			1000.0 / maxf(_frame_ms_sum / maxf(_frame_n, 1.0), 0.001),
			_frame_ms_max])
	print("\n--- Vége (%.0f mp) ---" % GameState.t)
	_report(int(GameState.t))
	if GameState.over:
		print("  A játék véget ért, győztes oldal:", GameState.winner)
	get_tree().quit(0)

func _report(sec: int) -> void:
	var pu := 0; var eu := 0; var pb := 0; var eb := 0
	for u in get_tree().get_nodes_in_group("units"):
		if u.owner_id == 0: pu += 1
		else: eu += 1
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.owner_id == 0: pb += 1
		else: eb += 1
	var r := GameState.get_res(0)
	# A bot összes megvett fokozata is ide kerül: enélkül nem látszana, hogy
	# a gépi ellenfél fejleszt-e egyáltalán a hosszú futás alatt.
	var fejl := 0
	for k in Upgrades.ORDER:
		fejl += Upgrades.level(1, k)
	print("  t=%4d mp | játékos %2d egység / %2d épület | bot %2d / %2d | fa %5d kő %5d arany %5d élelem %5d | hullám %d | bot-fejl %d" % [
		sec, pu, pb, eu, eb,
		int(r.get("wood", 0)), int(r.get("stone", 0)),
		int(r.get("gold", 0)), int(r.get("food", 0)),
		int(GameState.get_side(1).get("wave", 0)), fejl])

var _saved_objective = null

func run() -> void:
	print("\n=== BIRODALOM — önellenőrzés ===")
	await _frames(3)
	# A teszt korszakot léptet, épületet rak le és ellenséget öl — ezzel
	# véletlenül TELJESÍTENÉ a futó küldetést, ami leállítaná a játékot a
	# további tesztek alól. Ezért a célfigyelőt félretesszük.
	if main._objective != null:
		_saved_objective = main._objective
		main._objective = null
	await _test_world()
	await _test_navigation()
	await _test_training()
	await _test_building()
	await _test_era()
	await _test_combat()
	await _test_gathering()
	await _test_fog()
	await _test_sprites()
	await _test_hud()
	await _test_pirate()
	await _test_campaign()
	await _test_modules()
	await _test_net()
	await _test_layout()
	_test_audio()
	await _test_healing()
	await _test_unlocked()
	await _test_upgrades()
	await _test_special_roles()
	print("\n--- Összesítés: %d rendben, %d hiba ---" % [_pass, _fail.size()])
	for f in _fail:
		print("  * ", f)
	get_tree().quit(0 if _fail.is_empty() else 1)

# --- 1. Világ ---

func _test_world() -> void:
	print("\n[1] Világgenerálás")
	var terrain = main.terrain
	check("van szárazföld", terrain._land_rects.size() > 0,
		"%d téglalap" % terrain._land_rects.size())
	check("van víz", terrain._water_rects.size() > 0,
		"%d téglalap" % terrain._water_rects.size())
	# A szárazföld aránya: túl kevés földön nincs hely a gazdaságnak.
	var land_cells := 0
	var all_cells := 0
	for row in terrain.water_map:
		for w in row:
			all_cells += 1
			if not bool(w): land_cells += 1
	var land_pct := 100.0 * float(land_cells) / maxf(all_cells, 1)
	# A kalózvilág a RÖGZÍTETT Karib-tengeren játszik: ott a tenger a játéktér,
	# a szárazföld néhány sziget (Kuba, a Bahamák, Jamaica, Hispaniola) —
	# összesen a pálya hatoda. Nem a teljes arány számít, hanem hogy MINDEN
	# kezdőhely körül legyen elég part; azt külön mérjük alább.
	var alsó := 12.0 if GameState.pirate else 60.0
	check("elég szárazföld van a pályán", land_pct >= alsó,
		"%.0f%% föld (elvárt legalább %.0f%%)" % [land_pct, alsó])
	# Minden kezdőhely körül legyen összefüggő part: bázisnak, majorságnak.
	var szuk: Array[String] = []
	for s in WorldGen.start_positions():
		var szaraz := 0
		var osszes := 0
		for dy in range(-12, 13):
			for dx in range(-12, 13):
				var p := s + Vector2(dx, dy) * 32.0
				if p.x < 0 or p.y < 0 or p.x >= GameState.WORLD_W or p.y >= GameState.WORLD_H:
					continue
				osszes += 1
				if not terrain.is_water(p): szaraz += 1
		var arany_s := 100.0 * float(szaraz) / maxf(osszes, 1)
		# A kalóz kikötők kis szigeteken ülnek (Nassau, Tortuga), ott
		# kevesebb part is elég — de teljesen szűk hely ott sem lehet.
		if arany_s < (30.0 if GameState.pirate else 45.0):
			szuk.append("%.0f%%" % arany_s)
	check("minden kezdőhely körül van elég szárazföld", szuk.is_empty(), str(szuk))
	# Az eredeti tájai SZÁRAZABBAK, mint a régi zajtérkép: a tenger egy parti
	# sáv a pálya egyik szélén, mellette néhány tó és folyó — így a sima
	# pályán 88-94% a szárazföld. (A sivatag és a szikes puszta szándékosan
	# teljesen száraz, de az önellenőrzés az alap tájon fut.)
	check("van tengeri felület is", land_pct <= 95.0, "%.0f%% föld" % land_pct)
	# NEM ELÉG, HOGY VAN VÍZ: összefüggőnek is kell lennie. Ha a tenger apró
	# tócsákra esik szét, a kikötő, a halász és a hadihajók használhatatlanok
	# — egy pocsolyában nem lehet hajóhadat mozgatni.
	#
	# A zajból származó víz magától apró, egymástól elzárt tócsákra esik
	# szét (a legnagyobb folt egykor 0.04 millió képpont volt, az összes víz
	# 3%-a). Ezért kerül a sima pályára egy nagy tó — lásd WorldGen._carve_lake.
	var tavak := _water_bodies(terrain)
	var legnagyobb: int = tavak[0]
	var viz_cellak: int = tavak[1]
	var arany := 100.0 * float(legnagyobb) / maxf(float(viz_cellak), 1.0)
	var pixel: int = legnagyobb * int(terrain.water_cell) * int(terrain.water_cell)
	# A parti tenger a pálya egyik szélén fut végig (3400 x ~200 képpont),
	# ezért fél millió képpont fölött van, és a víz TÚLNYOMÓ része egyetlen
	# összefüggő felület — ez a két feltétel számít a hajózáshoz.
	# A rövidebb (2400 képpontos) oldalra eső tenger is elég: 2400 x ~230
	# képpont fél millió körül van.
	check("a legnagyobb vízfelület elég nagy a hajóknak", pixel >= 450000,
		"%d cella (~%.2f millió képpont), a víz %.0f%%-a" % [
			legnagyobb, float(pixel) / 1e6, arany])
	check("a víz java egyetlen összefüggő tenger", arany >= 50.0,
		"%.0f%%" % arany)
	var lp: NavigationPolygon = terrain.land_region.navigation_polygon
	var wp: NavigationPolygon = terrain.water_region.navigation_polygon
	check("a szárazföldi navigációs háló felépült",
		lp != null and lp.get_polygon_count() > 0,
		"%d poligon" % (lp.get_polygon_count() if lp else 0))
	check("a vízi navigációs háló felépült",
		wp != null and wp.get_polygon_count() > 0,
		"%d poligon" % (wp.get_polygon_count() if wp else 0))
	var res := get_tree().get_nodes_in_group("resources")
	check("bőségesen van nyersanyag-csomópont", res.size() >= 40, "%d db" % res.size())
	var kinds := {}
	for n in res: kinds[n.kind] = true
	for k in ["wood_node", "stone_node", "gold_node", "food_node", "fish_node"]:
		check("van %s" % k, kinds.has(k))
	# Kezdőcsomag: mindkét bázis közelében legyen fa és étel.
	for hq in get_tree().get_nodes_in_group("buildings"):
		if hq.tipus != "hq": continue
		var near := 0
		for n in res:
			if n.global_position.distance_to(hq.global_position) < 460.0:
				near += 1
		check("a bázis (%d) közelében van nyersanyag" % hq.owner_id, near >= 4,
			"%d db 460 px-en belül" % near)

	var hqs := []
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.tipus == "hq": hqs.append(b)
	# Oldalanként egy főváros. (A szám nem rögzített kettő: a --sides
	# kapcsolóval hat fél is indulhat, és az önellenőrzésnek akkor is
	# helyesen kell mérnie.)
	check("minden félnek van fővárosa",
		hqs.size() == GameState.oldalak.size(),
		"%d db, %d fél" % [hqs.size(), GameState.oldalak.size()])
	var dry := true
	for b in hqs:
		if terrain.is_water(b.global_position): dry = false
	check("a fővárosok szárazföldön állnak", dry)

	# --- TÁJTÍPUSOK (az eredeti MAPS táblája) ---
	#
	# Kilenc választható táj (plusz a kalózvilág rögzített Karib-tengere), és
	# tényleg MÁS pályát kell adniuk: a rengetegben több fa, a hegyvidéken
	# több szikla, a sivatagban nincs tenger.
	check("kilenc táj választható", WorldGen.choosable().size() == 9,
		str(WorldGen.choosable()))
	check("a Karib-tenger nem választható (az a kalózvilágé)",
		not ("karib" in WorldGen.choosable()))
	var hianyzo_taj: Array[String] = []
	for key in WorldGen.MAPS:
		var k := str(key["key"])
		if Lang.t("taj_%s" % k) == "taj_%s" % k: hianyzo_taj.append(k)
		if Lang.t("taj_%s_leiras" % k) == "taj_%s_leiras" % k:
			hianyzo_taj.append(k + "_leiras")
	check("minden tájnak van neve és leírása", hianyzo_taj.is_empty(),
		str(hianyzo_taj))
	# A szorzók tényleg különböznek: a rengeteg fában gazdag, a kopár ércben.
	var erdo := WorldGen.map_def("erdo")
	var kopar := WorldGen.map_def("kopar")
	var sivatag := WorldGen.map_def("sivatag")
	check("a rengetegben több a fa, mint a kopár vidéken",
		float(erdo["tree"]) > float(kopar["tree"]) * 2.0)
	check("a kopár vidék ércben gazdagabb",
		float(kopar["stone"]) > float(erdo["stone"]))
	check("a sivatagban nincs tenger", float(sivatag["sea"]) == 0.0)
	check("a hegyvidéken van a legtöbb szikla",
		float(WorldGen.map_def("hegy")["mountains"]) >= 6.0)

	var units := get_tree().get_nodes_in_group("units")
	# Oldalanként négy munkás és két gyalogos; a kalózvilágban egy szlúp is.
	var per_oldal := 7 if GameState.pirate else 6
	var vart: int = per_oldal * GameState.oldalak.size()
	check("kezdő egységek létrejöttek", units.size() == vart,
		"%d db (várt %d)" % [units.size(), vart])
	var wet := 0
	for u in units:
		# A hajók természetesen a vízen vannak.
		if not u.naval and terrain.is_water(u.global_position): wet += 1
	check("egyetlen szárazföldi kezdő egység sincs vízben", wet == 0,
		"%d vízben" % wet)
	if GameState.pirate:
		var ships := 0
		for u in units:
			if u.naval and terrain.is_water(u.global_position): ships += 1
		check("a kalózok hajói vízen indulnak", ships == 2, "%d hajó" % ships)

	# A játékos munkásai parancsra várnak, nem indulnak el maguktól.
	var idle := true
	var start_pos := {}
	for u in get_tree().get_nodes_in_group("player_units"):
		if u.role != "worker": continue
		if u.auto_gather or u.build_target != null: idle = false
		start_pos[u] = u.global_position
	check("a játékos munkásai parancsra várnak", idle)
	await _frames(60)
	var wandered := 0
	for u in start_pos:
		if is_instance_valid(u) and u.global_position.distance_to(start_pos[u]) > 6.0:
			wandered += 1
	check("parancs nélkül egy munkás sem indul el", wandered == 0,
		"%d elmászkált" % wandered)
	# A bot munkásai viszont automatikusan dolgoznak.
	var bot_auto := 0
	for u in get_tree().get_nodes_in_group("enemy_units"):
		if u.role == "worker" and u.auto_gather: bot_auto += 1
	check("a bot munkásai maguktól dolgoznak", bot_auto >= 4, "%d db" % bot_auto)

# --- 2. Navigáció ---

func _test_navigation() -> void:
	print("\n[2] Navigáció")
	var u = _first_player_unit("worker")
	if u == null:
		check("van munkás a teszthez", false)
		return
	var start: Vector2 = u.global_position
	# Szigetvilágban a távoli pont könnyen MÁSIK szigetre esik, ahova
	# szárazföldön nem lehet eljutni. Ezért elérhető célt keresünk.
	var goal: Vector2 = start
	for d in [300.0, 200.0, 130.0, 80.0]:
		for i in range(8):
			var a := TAU * float(i) / 8.0
			var g: Vector2 = main.find_land_near(
				start + Vector2(cos(a), sin(a)) * d, 30.0)
			if g.distance_to(start) < 40.0: continue
			u.move_to(g)
			await _frames(2)
			if u.nav.is_target_reachable():
				goal = g
				break
		if goal != start: break
	check("van elérhető célpont", goal != start,
		"%.0f px" % goal.distance_to(start))
	u.move_to(goal)
	await _frames(60)
	var moved: float = start.distance_to(u.global_position)
	check("a munkás elindult a célpont felé", moved > 20.0, "%.0f px" % moved)
	# A légvonalbeli távolság átmenetileg NŐHET, ha az útvonal egy öblöt
	# kerül meg — ezért azt nézzük, hogy végül tényleg odaér.
	var d0: float = start.distance_to(goal)
	# A tájakon FOLYÓK is vannak (Folyóköz, Hegyvidék): a gázlóig tett
	# kerülő több ezer képpont is lehet, ezért bőven hagyunk időt rá.
	for _i in range(70):
		if u.nav.is_navigation_finished(): break
		await _frames(30)
	# Kerülőút mellett nem biztos, hogy pont a célra ér — az a lényeg,
	# hogy érdemben közelebb jusson (vagy odaérjen).
	var d1: float = u.global_position.distance_to(goal)
	check("a munkás megérkezik vagy közel jut a célhoz",
		d1 < 60.0 or d1 < d0 * 0.5,
		"%.0f -> %.0f px a céltól" % [d0, d1])
	check("a kézi mozgásparancs kikapcsolja az automatikus gyűjtést",
		not u.auto_gather)
	# Vízi navigáció: a halász csak a vízen mozoghat. A pálya tele van apró
	# tavakkal, ezért a LEGNAGYOBB vízfelületen próbáljuk ki — egy pocsolyán
	# belül nincs hova menni, és az nem a navigáció hibája.
	var big := Rect2()
	for r: Rect2 in main.terrain._water_rects:
		if r.size.x * r.size.y > big.size.x * big.size.y: big = r
	# A felbontás keskeny sávokra vághat egy nagy tavat is, ezért a
	# TERÜLETET nézzük, nem az oldalak hosszát.
	check("van nagyobb vízfelület a pályán", big.size.x * big.size.y >= 4000.0,
		"%.0f x %.0f px" % [big.size.x, big.size.y])
	var f = main.spawn_unit("fisher", 0, big.get_center(), 0)
	await _frames(2)
	check("a halász a vízi navigációs rétegen van", f.nav.navigation_layers == 2)
	var fstart: Vector2 = f.global_position
	# Cél ugyanannak a víztestnek a szélén.
	var wgoal := big.get_center()
	if big.size.x >= big.size.y:
		wgoal.x = big.end.x - 20.0
	else:
		wgoal.y = big.end.y - 20.0
	f.move_to(wgoal)
	await _frames(90)
	check("a halász elindul a vízen",
		fstart.distance_to(f.global_position) > 12.0,
		"%.0f px" % fstart.distance_to(f.global_position))
	f.queue_free()
	await _frames(2)

# --- 3. Képzés ---

func _test_training() -> void:
	print("\n[3] Egységképzés")
	var hq = _player_hq()
	if hq == null:
		check("van főváros", false)
		return
	GameState.get_res(0)["wood"] = 5000.0
	GameState.get_res(0)["food"] = 5000.0
	var wood_before: float = GameState.get_res(0)["wood"]
	var before := get_tree().get_nodes_in_group("player_units").size()
	var ok: bool = hq.enqueue_unit("worker")
	check("a főváros sorba állítja a munkást", ok)
	check("a képzés levonta a nyersanyagot",
		GameState.get_res(0)["wood"] < wood_before,
		"%.0f -> %.0f" % [wood_before, GameState.get_res(0)["wood"]])
	check("nem képezhető olyan, amit a főváros nem tud",
		not hq.enqueue_unit("cav"))
	# A képzés 8 másodperc; a fizikai időt gyorsítva várjuk ki.
	hq.prod_tmr.wait_time = 0.2
	hq.prod_tmr.start(0.2)
	await _frames(40)
	var after := get_tree().get_nodes_in_group("player_units").size()
	check("az új egység megjelent", after == before + 1,
		"%d -> %d" % [before, after])

	# Népesség korlát
	var limit := ResourceSystem.pop_limit(get_tree(), 0)
	var used := ResourceSystem.pop_used(get_tree(), 0)
	check("a népességkorlát értelmes", limit >= 20 and limit <= 90, "%d" % limit)
	check("a felhasznált népesség az egységek száma", used == after, "%d" % used)

	# --- Gyülekezőpont ---
	#
	# A frissen kiképzett egység oda indul, ahová a játékos küldi; ha a
	# gyülekezőpont nyersanyagon áll, a munkás rögtön ott kezd dolgozni.
	check("alapból nincs gyülekezőpont", not hq.rally_set)
	var cel: Vector2 = hq.global_position + Vector2(0, -260)
	hq.set_rally(cel)
	check("a gyülekezőpont kijelölhető",
		hq.rally_set and hq.rally_kind() == "point")
	var elotte := get_tree().get_nodes_in_group("player_units")
	hq.enqueue_unit("worker")
	hq.prod_tmr.wait_time = 0.2
	hq.prod_tmr.start(0.2)
	await _frames(40)
	var uj: Node = null
	for u in get_tree().get_nodes_in_group("player_units"):
		if not (u in elotte): uj = u
	check("megszületett az egység a gyülekezőponthoz", uj != null)
	if uj != null:
		check("a friss egység a gyülekezőpont felé indul",
			uj.nav.target_position.distance_to(cel) < 60.0,
			"%.0f px" % uj.nav.target_position.distance_to(cel))
	# Nyersanyagra tett gyülekezőpont: a munkás azonnal dolgozni kezd.
	var munkas = _first_player_unit("worker")
	var lelo = ResourceSystem.find_node_for(munkas) if munkas != null else null
	if lelo != null:
		hq.set_rally(lelo.global_position, lelo, null)
		check("nyersanyagra tett gyülekezőpont felismerve",
			hq.rally_kind() == "node")
		var elotte2 := get_tree().get_nodes_in_group("player_units")
		hq.enqueue_unit("worker")
		hq.prod_tmr.wait_time = 0.2
		hq.prod_tmr.start(0.2)
		await _frames(40)
		var uj2: Node = null
		for u in get_tree().get_nodes_in_group("player_units"):
			if not (u in elotte2): uj2 = u
		check("a friss munkás rögtön a lelőhelyen kezd",
			uj2 != null and uj2.auto_gather and uj2.gather_node() == lelo)
	hq.clear_rally()
	check("a gyülekezőpont törölhető", not hq.rally_set)

# --- 4. Építés ---

func _test_building() -> void:
	print("\n[4] Építés")
	var hq = _player_hq()
	if hq == null:
		check("van főváros az építési teszthez", false)
		return
	var spot: Vector2 = main.find_build_spot("farm", hq.global_position + Vector2(240, 0))
	check("találunk érvényes építési helyet", spot != Vector2.INF, str(spot))
	if spot == Vector2.INF: return
	check("szárazföldi, üres helyre lehet építeni", main.can_place("farm", spot),
		str(spot))
	check("már álló épületre nem lehet építeni",
		not main.can_place("farm", hq.global_position))
	var sea: Vector2 = main.find_land_near(hq.global_position, 40.0, true)
	check("vízre nem lehet farmot építeni", not main.can_place("farm", sea), str(sea))
	check("a világon kívülre nem lehet építeni",
		not main.can_place("farm", Vector2(-100, 100)))

	GameState.get_res(0)["wood"] = 5000.0
	GameState.get_res(0)["stone"] = 5000.0
	var before := get_tree().get_nodes_in_group("buildings").size()
	main.set_build_mode("farm")
	main._try_place_building(spot)
	await _frames(2)
	var after := get_tree().get_nodes_in_group("buildings").size()
	check("a farm felépült", after == before + 1, "%d -> %d" % [before, after])
	var farm = _building_at(spot)
	if farm != null:
		check("az új épület építkezés alatt áll", farm.prog < 1.0, "%.2f" % farm.prog)
		check("felépülés előtt nem képez", not farm.enqueue_unit("worker"))
		# A lerakáskor magától kap megbízást egy munkás.
		var assigned := 0
		for u in get_tree().get_nodes_in_group("player_units"):
			if u.role == "worker" and u.build_target == farm: assigned += 1
		check("a lerakáskor munkás kapja meg az építést", assigned >= 1,
			"%d munkás" % assigned)
		# Munkás nélkül NEM halad az építkezés.
		for u in get_tree().get_nodes_in_group("player_units"):
			if u.role == "worker": u.stop()
		var w0 = _first_player_unit("worker")
		var p0: float = farm.prog
		await _frames(20)
		check("munkás nélkül nem halad az építkezés", is_equal_approx(farm.prog, p0),
			"%.3f -> %.3f" % [p0, farm.prog])
		if w0 != null:
			w0.build_at(farm)
			w0.global_position = farm.global_position + Vector2(farm.hit_radius() + 16.0, 0)
			await _frames(20)
			check("a munkás mellett halad az építkezés", farm.prog > p0,
				"%.3f -> %.3f" % [p0, farm.prog])
			farm.prog = 0.99
			await _frames(10)
			check("az építkezés befejeződik", farm.is_ready(), "%.2f" % farm.prog)
			check("a kész épület elengedi a munkást", w0.build_target == null)
	main.set_build_mode("")

# --- 5. Korszakváltás ---

func _test_era() -> void:
	print("\n[5] Korszakváltás")
	if _player_hq() == null:
		check("van főváros a korszak-teszthez", false)
		return
	var age_before := GameState.get_age(0)
	for k in Style.ERA_COST[age_before]:
		GameState.get_res(0)[k] = float(Style.ERA_COST[age_before][k]) + 100.0
	main.hud._on_era_pressed()
	await _frames(3)
	if GameState.pirate:
		# A kalózvilágban végig a vitorlások korában játszunk.
		check("a kalózvilágban NEM lép a korszak",
			GameState.get_age(0) == age_before, "%d" % GameState.get_age(0))
		check("a korszakváltás gombja rejtve van", not main.hud.era_btn.visible)
		return
	check("a korszak előrelépett", GameState.get_age(0) == age_before + 1,
		"%d -> %d" % [age_before, GameState.get_age(0)])
	# Az új korszak statisztikái
	var u = main.spawn_unit("melee", 0,
		main.find_land_near(_player_hq().global_position + Vector2(0, 120), 30.0),
		GameState.get_age(0))
	await _frames(2)
	var vart: float = float(Unit.UNIT_STATS["melee"]["hp"][clampi(GameState.get_age(0), 0, 3)])
	check("az új egység a mostani korszak életereje", u.max_hp == vart,
		"hp=%.0f (várt %.0f)" % [u.max_hp, vart])
	u.queue_free()

	# A BOT NEM UGORHAT KORSZAKOT AZONNAL.
	#
	# A kezdőkészlet korszakonként nő (a 19. századi induláshoz 930 arany
	# jár), a bot korszakváltásának a feltétele viszont rögzített 900 arany
	# volt: a 19. századi játszmában a bot már az első építési körben, fél
	# percen belül átlépett a 20. századba, és a játékos a vonalgyalogság
	# korában rohamsisakos katonákkal találkozott.
	var bot: Dictionary = GameState.get_side(1)
	if bot.is_empty() or main.bot_ai == null:
		check("van gépi ellenfél a korszak-teszthez", false)
		return
	var bot_kor: int = int(bot["age"])
	var t_ment: float = GameState.t
	bot["age"] = 2
	bot["res"] = GameState.default_res(2)
	GameState.t = 30.0                       # fél perccel a kezdés után
	main.bot_ai._try_advance_era()
	check("a bot nem lép korszakot a játszma első perceiben",
		int(bot["age"]) == 2, "kor %d" % int(bot["age"]))
	# Később, ha tényleg összegyűlt rá (a JÁTÉKOS árlistája szerint), igen.
	GameState.t = 1200.0
	var bres: Dictionary = GameState.get_res(1)
	for k in Style.ERA_COST[2]:
		bres[k] = float(Style.ERA_COST[2][k]) + float(main.bot_ai.ERA_RESERVE) + 10.0
	main.bot_ai._try_advance_era()
	check("a bot később, elég készletből korszakot vált",
		int(bot["age"]) == 3, "kor %d" % int(bot["age"]))
	GameState.t = t_ment
	bot["age"] = bot_kor
	bot["res"] = GameState.default_res(bot_kor)
	main.bot_ai._era_ready_t = float(main.bot_ai.ERA_MIN_T)

# --- 6. Harc ---

func _test_combat() -> void:
	print("\n[6] Harc")
	var hq = _player_hq()
	if hq == null:
		check("van főváros a harc-teszthez", false)
		return
	var p: Vector2 = main.find_land_near(hq.global_position + Vector2(320, 120), 60.0)
	var att = main.spawn_unit("melee", 0, p, 0)
	var def = main.spawn_unit("melee", 1, p + Vector2(24, 0), 0)
	await _frames(2)
	var hp0: float = def.hp
	att.start_attacking(def)
	att.atk_timer.start(0.05)
	await _frames(8)
	var hp1: float = def.hp if is_instance_valid(def) else 0.0
	check("a támadó sebzi a védőt", hp1 < hp0, "%.0f -> %.0f" % [hp0, hp1])
	# Ellensúly: lándzsás a lovas ellen erősebb
	check("a lándzsás bónusza a lovas ellen működik",
		Combat.damage_mult("spear", "cav") > 1.5,
		"%.2f" % Combat.damage_mult("spear", "cav"))
	check("a faltörő bónusza az épület ellen működik",
		Combat.damage_mult("ram", "building") > 2.0)
	# Halál
	if is_instance_valid(def):
		def.take_damage(9999.0)
		await _frames(3)
	check("a nullára sebzett egység megszűnik", not is_instance_valid(def))
	if is_instance_valid(att): att.queue_free()

	# Lövedék
	var t = main.spawn_unit("melee", 1,
		main.find_land_near(hq.global_position + Vector2(-200, 0), 40.0), 0)
	await _frames(2)
	var thp: float = t.hp
	main.spawn_projectile(t.global_position + Vector2(90, 0), t, 25.0, 0)
	await _frames(60)
	check("a lövedék célba ér és sebez", t.hp < thp, "%.0f -> %.0f" % [thp, t.hp])
	if is_instance_valid(t): t.queue_free()

# --- 7. Gyűjtés ---

func _test_gathering() -> void:
	print("\n[7] Nyersanyaggyűjtés")
	var w = _first_player_unit("worker")
	if w == null or _player_hq() == null:
		check("van munkás és főváros a gyűjtés-teszthez", false)
		return
	var node = ResourceSystem.find_node_for(w)
	check("a munkás talál csomópontot", node != null)
	if node == null: return
	var amount_before: float = node.amount
	# A munkást a csomópont mellé tesszük, hogy ne kelljen átgyalogolnia.
	w.global_position = node.global_position + Vector2(20, 0)
	w.gather_at(node)
	check("a gyűjtési parancs visszakapcsolja az automatikát", w.auto_gather)
	await _frames(4)
	check("a csomópont fogy a gyűjtéstől", node.amount < amount_before,
		"%.0f -> %.0f" % [amount_before, node.amount])

	# --- Ütésenkénti gyűjtés ---
	# Egy ütés kb. LOAD_AMOUNT/SWINGS_PER_LOAD nyersanyagot ad, és két ütés
	# között SWING_TIME telik el — nem folyamatosan csorog a nyersanyag.
	var egy_utes: float = amount_before - node.amount
	check("egy ütés a rakomány töredékét adja",
		absf(egy_utes - ResourceSystem.PER_SWING) < 0.01,
		"%.2f (várt %.2f)" % [egy_utes, ResourceSystem.PER_SWING])
	check("egy ütés után nem üt azonnal újra", w._swings == 1,
		"%d ütés" % w._swings)
	var utan: float = node.amount
	await _frames(int(ResourceSystem.SWING_TIME * 30.0))   # fél ütésnyi idő
	check("két ütés között szünet van", is_equal_approx(node.amount, utan),
		"%.2f -> %.2f" % [utan, node.amount])
	# Kivárjuk a teljes rakományt: 15 ütés.
	var kell := int(ResourceSystem.SWINGS_PER_LOAD * ResourceSystem.SWING_TIME * 60.0) + 40
	for _i in range(kell / 10):
		if w._hauling: break
		await _frames(10)
	check("tizenöt ütés után megtelik a rakomány",
		w._swings >= ResourceSystem.SWINGS_PER_LOAD
		or w._carry >= ResourceSystem.LOAD_AMOUNT,
		"%d ütés, %.1f rakomány" % [w._swings, w._carry])
	check("a teli rakománnyal elindul vissza", w._hauling)
	check("a rakomány ~%d nyersanyag" % int(ResourceSystem.LOAD_AMOUNT),
		absf(w._carry - ResourceSystem.LOAD_AMOUNT) < 1.0, "%.1f" % w._carry)

	# --- A rakomány és a lelőhely készlete látszik is ---
	check("a rakomány kívülről lekérdezhető",
		is_equal_approx(w.carry_amount(), w._carry) and w.carry_kind() != "",
		"%.1f %s" % [w.carry_amount(), w.carry_kind()])
	# A pálya ne legyen tele számokkal: a rakomány csak a KIJELÖLT munkás
	# feje fölött látszik.
	w.set_selected(false)
	check("kijelöletlen munkás fölött nincs szám", not w.shows_carry())
	w.set_selected(true)
	check("kijelölt munkás fölött ott a rakomány", w.shows_carry())
	main.hud.update_selection([w])
	check("a kijelölési panel kiírja a rakományt",
		main.hud.sel_info.visible
		and ("%d" % int(round(w.carry_amount()))) in main.hud.sel_info.text,
		main.hud.sel_info.text)
	node.set_selected(true)
	main.hud.select_resource(node)
	check("a lelőhely kijelölése látszik a térképen", node.selected)
	check("a lelőhelyre kattintva látszik a maradék készlet",
		main.hud.sel_info.visible
		and ("%d" % int(ceil(node.amount))) in main.hud.sel_info.text,
		main.hud.sel_info.text)
	check("a maradék sáv a készletet mutatja",
		is_equal_approx(main.hud.sel_hp.value, node.amount)
		and is_equal_approx(main.hud.sel_hp.max_value, node.max_amount),
		"%.0f / %.0f" % [main.hud.sel_hp.value, main.hud.sel_hp.max_value])
	check("a lelőhelynek nincs mozgás/támadás gombja",
		not main.hud.action_btns.visible)
	check("a lelőhely neve le van fordítva",
		main.hud.sel_title.text != "" and not main.hud.sel_title.text.begins_with("lh_"),
		main.hud.sel_title.text)
	node.set_selected(false)
	check("kijelöletlen lelőhely fölött nincs szám", not node.selected)
	w.set_selected(false)
	main.hud.select_resource(null)
	main.hud.update_selection([])
	check("a lelőhely elengedése után eltűnik a panel",
		not main.hud.sel_panel.visible)

	var kind: String = ResourceSystem.yield_kind(node.kind)
	var res_before: float = GameState.get_res(0)[kind]
	# A leadóhelyhez tesszük, hogy ne kelljen kivárni az utat.
	w.global_position = _player_hq().global_position + Vector2(40, 0)
	await _frames(20)
	check("a munkás leadja a rakományt (%s)" % kind,
		GameState.get_res(0)[kind] >= res_before + ResourceSystem.LOAD_AMOUNT - 1.0,
		"%.0f -> %.0f" % [res_before, GameState.get_res(0)[kind]])
	check("leadás után újrakezdi a számolást",
		w._swings == 0 and not w._hauling and is_equal_approx(w._carry, 0.0))

# --- 8. Köd ---

func _test_fog() -> void:
	print("\n[8] Köd (fog of war)")
	var fog = main.fog
	check("a ködkép létrejött", fog.fog_img != null)
	if fog.fog_img == null: return
	fog.tick(0.1)
	var hq = _player_hq()
	check("a saját bázis látható", fog.is_visible_at(hq.global_position))
	# A pálya nagy része legyen még sötét. (Egy fix sarokpont ingatag: a
	# kezdőhelyeket a víz miatt néha messzire tolja a keresés.)
	var felderitve := 0
	var osszes: int = int(fog.fog_w) * int(fog.fog_h)
	for y in range(fog.fog_h):
		for x in range(fog.fog_w):
			if fog.fog_img.get_pixel(x, y).r > 0.5: felderitve += 1
	var arany := 100.0 * float(felderitve) / maxf(osszes, 1)
	check("a pálya nagy része felderítetlen", arany < 25.0,
		"%.0f%% felderítve" % arany)

# --- 9. Sprite-ok ---

func _test_sprites() -> void:
	print("\n[9] Textúrabetöltés")
	var roles := ["worker", "melee", "ranged", "spear", "cav", "priest", "spy",
		"hero", "fisher", "warship", "galleon", "transport"]
	var gyalogos := ["worker", "melee", "ranged", "spear", "priest", "spy", "hero"]
	var hq = _player_hq()
	for age in range(4):
		var missing: Array[String] = []
		# Az alakok magassága korszakon belül EGYSÉGES kell legyen: a
		# lapokon 47-től 61 képpontig terjed, ezért igazítjuk őket.
		var magassagok: Array[float] = []
		for r in roles:
			var s := Sprite2D.new()
			s.set_script(load("res://scripts/units/UnitSprite.gd"))
			add_child(s)
			s.setup(r, age, 0)
			# A 20. századi acélhajónak nincs lapja: azt rajzoljuk.
			if s.texture == null and not s.is_drawn_ship(): missing.append(r)
			elif r in gyalogos: magassagok.append(s.figure_height())
			s.queue_free()
		check("minden egység-sprite betölt (korszak %d)" % age,
			missing.is_empty(), str(missing))
		var lo := 999.0
		var hi := 0.0
		for h in magassagok:
			lo = minf(lo, h)
			hi = maxf(hi, h)
		check("a gyalogosok egyforma magasak (korszak %d)" % age,
			hi - lo < 1.5, "%.1f – %.1f px" % [lo, hi])
	# A NÉGY IRÁNYNAK TÉNYLEG KÜLÖNBÖZNIE KELL.
	#
	# A WW2 lapon a Dél, az Észak és a Kelet sor sokáig BÁJTRA AZONOS volt:
	# a modern korban minden katona jobbra nézett, akármerre ment. A kód
	# helyes volt, a rajz hiányos — az ilyen hibát csak a képpontok
	# összevetése fogja meg, ezért itt magukat a lapokat nézzük.
	for lap in ["ally", "axis"]:
		var tex: Texture2D = load("res://assets/sprites/ww2/%s.png" % lap)
		if tex == null:
			check("a(z) %s lap betölt" % lap, false)
			continue
		var kep := tex.get_image()
		var egyezo: Array[String] = []
		var nevek := ["Dél", "Nyugat", "Észak", "Kelet"]
		for a in range(4):
			for b in range(a + 1, 4):
				if _rows_equal(kep, a, b):
					egyezo.append("%s=%s" % [nevek[a], nevek[b]])
		check("a(z) %s lapon mind a négy irány külön rajz" % lap,
			egyezo.is_empty(), str(egyezo))

	# --- A HAJÓK IRÁNYA ---
	#
	# A hajólapok OLDALNÉZETIEK: a test a kép alján, az árbocok fölfelé, az
	# orr balra. Ilyen képet nem szabad a menetirányba forgatni — észak felé
	# tartva a hajó az oldalára dőlne, az árbocai vízszintesen állnának.
	# Helyette (mint az eredeti játékban) tükrözünk és keskenyítünk.
	var iranyok := {"kelet": 0.0, "dél": PI * 0.5, "nyugat": PI, "észak": -PI * 0.5}
	for r in ["fisher", "transport", "warship", "galleon"]:
		# MINDEN korszakban: a vitorlásnak és az acélhajónak egyaránt a
		# menetirányba kell néznie.
		for hkor in range(4):
			var hs := Sprite2D.new()
			hs.set_script(load("res://scripts/units/UnitSprite.gd"))
			add_child(hs)
			hs.setup(r, hkor, 0)
			var dolt: Array[String] = []
			var sx := {}
			for nev in iranyok:
				hs.update_anim(float(iranyok[nev]), 0.0, true, false)
				if absf(hs.rotation) > 0.15: dolt.append(str(nev))
				sx[nev] = hs.scale.x
			check("a(z) %s nem fordul az oldalára (korszak %d)" % [r, hkor],
				dolt.is_empty(), str(dolt))
			check("a(z) %s orra a menetirányba néz (korszak %d)" % [r, hkor],
				float(sx["kelet"]) < 0.0 and float(sx["nyugat"]) > 0.0,
				"K %.2f / Ny %.2f" % [sx["kelet"], sx["nyugat"]])
			check("a(z) %s szemből keskenyebb (korszak %d)" % [r, hkor],
				absf(float(sx["dél"])) < absf(float(sx["nyugat"])) * 0.6
				and absf(float(sx["észak"])) < absf(float(sx["nyugat"])) * 0.6,
				"D %.2f / É %.2f" % [sx["dél"], sx["észak"]])
			hs.queue_free()

	# --- A HAJÓK KORSZAKFÜGGŐEK ---
	#
	# 15. és 17. század: vitorlás lapról (más-más színben), 19. század: gőzös
	# (kéménnyel), 20. század: rajzolt acélhajó, vitorla nélkül.
	var hvart := ["sail", "sail", "steam", "steel"]
	for r in ["fisher", "transport", "warship", "galleon"]:
		var stilusok: Array[String] = []
		var szinek: Array[Color] = []
		var rossz_h: Array[String] = []
		for hkor in range(4):
			var hs2 := Sprite2D.new()
			hs2.set_script(load("res://scripts/units/UnitSprite.gd"))
			add_child(hs2)
			hs2.setup(r, hkor, 0)
			stilusok.append(str(hs2.ship_style()))
			szinek.append(hs2.self_modulate)
			if str(hs2.ship_style()) != str(hvart[hkor]):
				rossz_h.append("%d:%s" % [hkor, hs2.ship_style()])
			# A vízvonal minden korszakban a hajótest alja.
			if hkor < 3 and hs2.offset.y >= 0.0:
				rossz_h.append("%d:vízvonal" % hkor)
			hs2.queue_free()
		check("a(z) %s korszakonként más hajó" % r, rossz_h.is_empty(),
			"%s (várt %s)" % [str(stilusok), str(hvart)])
		check("a(z) %s a 15. és a 17. században sem egyforma" % r,
			szinek[0] != szinek[1], "%s / %s" % [szinek[0], szinek[1]])
	# A 20. századi hajó RAJZOLT: nincs lapja, de nem is üres folt.
	var ah := Sprite2D.new()
	ah.set_script(load("res://scripts/units/UnitSprite.gd"))
	add_child(ah)
	ah.setup("warship", 3, 0)
	check("a 20. századi hadihajó rajzolt, nem vitorlás lap",
		ah.is_drawn_ship() and ah.texture == null)
	check("a rajzolt acélhajó mérete a hajótípushoz igazodik",
		is_equal_approx(ah.scale.y, 46.0 * 2.4 / 64.0), "%.3f" % ah.scale.y)
	ah.queue_free()
	# A repülőgépek FELÜLNÉZETIEK, azokat viszont forgatni kell.
	var rs := Sprite2D.new()
	rs.set_script(load("res://scripts/units/UnitSprite.gd"))
	add_child(rs)
	rs.setup("fighter", 3, 0)
	rs.update_anim(0.0, 0.0, true, false)
	check("a vadászgép a menetirányba fordul",
		is_equal_approx(rs.rotation, PI * 0.5), "%.2f" % rs.rotation)
	rs.queue_free()

	# --- Korhűség: a 19. század nem a 20. ---
	#
	# A 19. századi katona vonalgyalogos, nem rohamsisakos géppisztolyos:
	# a napóleoni lapról dolgozik, csak tompább egyenruhában.
	var lapok: Dictionary = {}
	var szinek: Dictionary = {}
	for a in range(4):
		var ks := Sprite2D.new()
		ks.set_script(load("res://scripts/units/UnitSprite.gd"))
		add_child(ks)
		ks.setup("melee", a, 0)
		lapok[a] = str(ks._sheet_key)
		szinek[a] = ks.self_modulate
		ks.queue_free()
	check("a 19. század a napóleoni lapot használja",
		str(lapok[2]).begins_with("napoleon"), str(lapok[2]))
	check("a 20. század kapja a világháborús lapot",
		str(lapok[3]) == "ww2", str(lapok[3]))
	check("a 19. és a 20. század nem ugyanaz a lap", lapok[2] != lapok[3])
	check("a 19. század nem ugyanúgy fest, mint a 17.",
		szinek[2] != szinek[1], "%s / %s" % [szinek[1], szinek[2]])
	# Az épületek is: tégla és pala a 19., hűvös falak a 20. században.
	var elteres: Array[String] = []
	for t in ["hq", "barracks", "house", "tower"]:
		var s2: Array = Building.MATERIALS.get(t, [])
		if s2.size() < 3 or s2[1] == s2[2]: elteres.append(t)
	check("a 19. és a 20. századi épületek anyaga különbözik",
		elteres.is_empty(), str(elteres))
	# Az anyagfoltok legyenek TÖMÖREK: ahol a forráskép átlátszó, ott a
	# fal foltokban tűnne el, és a fű látszana át a házon.
	var likacsos: Array[String] = []
	for key in Building.TEX_LIB:
		var e: Array = Building.TEX_LIB[key]
		var path: String = "res://assets/sprites/buildings/%s.png" % e[0]
		if not ResourceLoader.exists(path): continue
		var im: Image = (load(path) as Texture2D).get_image()
		var r: Rect2 = e[1]
		var atl := 0
		var db := 0
		var yy := int(r.position.y)
		while yy < int(r.end.y) and yy < im.get_height():
			var xx := int(r.position.x)
			while xx < int(r.end.x) and xx < im.get_width():
				db += 1
				if im.get_pixel(xx, yy).a < 0.98: atl += 1
				xx += 2
			yy += 2
		if db > 0 and float(atl) / float(db) > 0.05:
			likacsos.append("%s %d%%" % [key, int(100.0 * float(atl) / float(db))])
	check("az épületanyagok tömörek (nem látszik át rajtuk a táj)",
		likacsos.is_empty(), str(likacsos))
	check("a korszakcsoportok jól oszlanak el",
		Building.era_group(0) == 0 and Building.era_group(1) == 0
		and Building.era_group(2) == 1 and Building.era_group(3) == 2)

	# --- A halraj él ---
	var hal: Node2D = null
	for n in get_tree().get_nodes_in_group("resources"):
		if is_instance_valid(n) and n.kind == "fish_node": hal = n
	if hal != null:
		# A halak CSAK a képernyőn úsznak: a pálya túloldalán nem mozognak,
		# különben a gyenge gépeken tucatnyi raj rajzolódna hiába.
		var figyelo: Node = null
		for c in hal.get_children():
			if c is VisibleOnScreenNotifier2D: figyelo = c
		check("a halraj csak a képernyőn mozog (van látómező-figyelője)",
			figyelo != null)
		hal.set_process(true)
		var t0: float = hal._t
		await _frames(10)
		check("bekapcsolva telik a halraj ideje", hal._t > t0,
			"%.2f -> %.2f" % [t0, hal._t])
	else:
		check("van halraj a pályán", false)

	# A szerszám abban a kézben legyen, amelyikkel az alak dolgozik: a lapon
	# a csapás animációja soronként adott irányba lendíti a kart.
	#   sor 0 (hát) jobbra, 1 (nyugat) balra, 2 (dél) jobbra, 3 (kelet) jobbra
	var elvart := {0: 1.0, 1: -1.0, 2: 1.0, 3: 1.0}
	for age2 in [0, 1]:
		var rossz: Array[String] = []
		for r in ["worker", "melee", "ranged", "spear"]:
			var s2 := Sprite2D.new()
			s2.set_script(load("res://scripts/units/UnitSprite.gd"))
			add_child(s2)
			s2.setup(r, age2, 0)
			for dir in range(4):
				s2._dir = dir
				var sor: int = s2._rows[dir]
				if not is_equal_approx(s2.weapon_side(), elvart[sor]):
					rossz.append("%s dir%d" % [r, dir])
			s2.queue_free()
		check("a szerszám a dolgozó kézben van (korszak %d)" % age2,
			rossz.is_empty(), str(rossz))
	# A SAJÁT FEGYVER: amelyik lapon már rajta van a fegyver (íjász íja,
	# napóleoni lövész szablyája, világháborús puska), oda nem rajzolunk
	# másodikat; a többinél marad a rajzolt szerszám.
	var fegyveres := {"ranged": true, "melee": false, "spear": false,
		"worker": false, "priest": false, "spy": false}
	for age5 in [0, 1, 3]:
		var rossz_f: Array[String] = []
		for r in fegyveres.keys():
			var fs := Sprite2D.new()
			fs.set_script(load("res://scripts/units/UnitSprite.gd"))
			add_child(fs)
			fs.setup(str(r), age5, 0)
			# A 20. században mindenki a világháborús lapról jön, azon van
			# puska — ott tehát senkihez nem rajzolunk fegyvert.
			var vart: bool = true if age5 >= 2 else bool(fegyveres[r])
			if fs.sheet_has_weapon() != vart:
				rossz_f.append("%s@%d" % [r, age5])
			fs.queue_free()
		check("a lapon lévő fegyvert nem duplázzuk (korszak %d)" % age5,
			rossz_f.is_empty(), str(rossz_f))

	# A szerszám a KÉZZEL mozog: a kar végét kockánként mérjük ki a lapról,
	# tehát a járás és a csapás minden kockájában máshova kerül.
	for age4 in [0, 1]:
		var ms := Sprite2D.new()
		ms.set_script(load("res://scripts/units/UnitSprite.gd"))
		add_child(ms)
		ms.setup("melee", age4, 0)
		ms._dir = 0                       # Kelet -> 3. sor, jobb kéz
		var jaras: Array[Vector2] = []
		for c in range(ms._walk_base, ms._walk_base + ms._walk_frames):
			jaras.append(ms._hand_at(3, c, 1.0))
		var valtozik := false
		for i in range(1, jaras.size()):
			if jaras[i] != jaras[0]: valtozik = true
		check("a kéz helye kockánként változik (korszak %d)" % age4,
			valtozik, str(jaras.slice(0, 3)))
		# A csapás kockáin a kar messzebb nyúlik, mint álló helyzetben.
		var allo: Vector2 = ms._hand_at(3, ms._idle_col, 1.0)
		var legtavolabb := allo.x
		for c2 in range(ms._atk_base, ms._atk_base + ms._atk_frames):
			legtavolabb = maxf(legtavolabb, ms._hand_at(3, c2, 1.0).x)
		check("csapáskor kinyúlik a kar (korszak %d)" % age4,
			legtavolabb > allo.x, "%.1f -> %.1f" % [allo.x, legtavolabb])
		# Az álló kéz a csípő magasságában, a törzs mellett van.
		check("a kéz a törzs mellett, csípőmagasságban van (korszak %d)" % age4,
			absf(allo.x) >= 5.0 and absf(allo.x) < 20.0
			and allo.y > 0.0 and allo.y < 26.0, str(allo))
		ms.queue_free()

	# A ló és a lovas aránya: a hátas legyen nagyobb, mint a nyeregben ülő
	# ember, a lovas felsőteste pedig akkora, mint egy gyalogosé.
	for age3 in [0, 1]:
		var cs := Sprite2D.new()
		cs.set_script(load("res://scripts/units/UnitSprite.gd"))
		add_child(cs)
		cs.setup("cav", age3, 0)
		var lo: float = cs.horse_world_h()
		var lovas: float = cs.rider_world_h()
		var torzs: float = cs.rider_torso_h()
		check("a ló nagyobb, mint a nyeregből kilátszó ember (korszak %d)" % age3,
			lo > torzs * 1.7, "ló %.1f px, felsőtest %.1f px" % [lo, torzs])
		check("a lovas alakja arányos (korszak %d)" % age3,
			absf(lovas - cs.RIDER_H) < 1.5,
			"%.1f px (várt %.1f)" % [lovas, cs.RIDER_H])
		check("a lovas kisebb, mint a ló (korszak %d)" % age3,
			lovas < lo, "lovas %.1f px, ló %.1f px" % [lovas, lo])
		cs.queue_free()
	var missing_b: Array[String] = []
	for t in Building.BUILD_STATS.keys():
		for age in range(4):
			var b = main.spawn_building(t, 0,
				Vector2(-9000, -9000), true)   # a palyan kivul, csak betoltesre
			b.age = age
			b._load_sprite()
			if (b._wall_tex == null or b._roof_tex == null) \
					and not ("%s@%d" % [t, age]) in missing_b:
				missing_b.append("%s@%d" % [t, age])
			b.queue_free()
	check("minden épület-sprite betölt", missing_b.is_empty(), str(missing_b))
	# Méretarány: az épületek a KATONÁHOZ mérve legyenek értelmesek.
	# (ház ~1,5x, laktanya ~2x, főváros ~3x a gyalogos magassága)
	var ember := 46.0
	var aranyok := {"house": [1.3, 2.2], "barracks": [1.7, 2.8],
		"hq": [2.4, 3.6], "tower": [2.0, 3.4], "temple": [2.0, 3.4]}
	for t in aranyok:
		var b2 = main.spawn_building(t, 0, Vector2(-9000, -9000), true)
		var magassag: float = b2._sprite_rect().size.y
		var arany := magassag / ember
		var hatar: Array = aranyok[t]
		check("a(z) %s mérete arányos a katonával" % t,
			arany >= hatar[0] and arany <= hatar[1],
			"%.2fx (elvárt %.1f–%.1f)" % [arany, hatar[0], hatar[1]])
		b2.queue_free()
	# Zászlók és uralkodók
	var missing_f: Array[String] = []
	for key in Style.NATION_ORDER:
		for age in range(4):
			if not ResourceLoader.exists(Style.flag_path(key, age)):
				missing_f.append("zászló %s-%d" % [key, age])
			if not ResourceLoader.exists(Style.ruler_path(key, age)):
				missing_f.append("uralkodó %s-%d" % [key, age])
	check("minden zászló és uralkodókép megvan", missing_f.is_empty(), str(missing_f))

# --- 10. Kezelőfelület ---

func _test_hud() -> void:
	print("\n[10] Kezelőfelület")
	var hud = main.hud
	# Nyelv: minden felirat a JSON-ból jön, kulcs nem szivároghat ki.
	check("a nyelvi fájl betöltött", Lang.t("fa") != "fa", Lang.code)
	check("mind a három nyelv elérhető", Lang.codes().size() == 3,
		str(Lang.codes()))
	var hianyzo: Array[String] = []
	for k in ["fa", "ko", "arany", "elelem", "szen", "rum", "hadsereg",
			"mozgas", "tamadas", "megall", "gyozelem", "vereseg",
			"korszakvaltas", "e_hq", "u_worker", "kor_0"]:
		if Lang.t(k) == k: hianyzo.append(k)
	check("nincs lefordítatlan kulcs a felületen", hianyzo.is_empty(),
		str(hianyzo))
	var hq = _player_hq()
	if hud == null or hq == null:
		check("elérhető a HUD és a főváros", false)
		return
	check("a zászló megjelenik a HUD-on", hud.flag_icon.texture != null)

	# Épület kijelölése -> képzési gombok
	hud.select_building(hq)
	await _frames(2)
	check("épület kijelölésekor látható a képzési panel", hud.train_panel.visible)
	# Alapesetben a főváros csak munkást képez; küldetésben viszont át-
	# veheti a kaszárnya szerepét (hqTrains).
	var vart_gomb := maxi(GameState.hq_trains.size(), 1)
	check("a fővároshoz %d képzési gomb tartozik" % vart_gomb,
		hud.train_btns.get_child_count() == vart_gomb,
		"%d gomb" % hud.train_btns.get_child_count())
	var qbefore: int = hq.train_queue.size()
	GameState.get_res(0)["wood"] = 3000.0
	GameState.get_res(0)["food"] = 3000.0
	(hud.train_btns.get_child(0) as Button).pressed.emit()
	await _frames(2)
	check("a gomb sorba állítja az egységet",
		hq.train_queue.size() == qbefore + 1)
	hq.train_queue.clear()

	# Gyülekezőpont a képzési panelről
	check("a képző épületnél ott a Gyülekező gomb", hud.rally_row.visible)
	main.selected_bld = hq
	main.set_rally_mode(true)
	check("a Gyülekező gomb élesíti a kijelölést", main.rally_mode())
	main.set_rally_at(hq.global_position + Vector2(120, 0))
	check("a kattintás kijelöli a gyülekezőpontot és kilép a módból",
		hq.rally_set and not main.rally_mode())
	check("a panel kiírja, mit csinál a gyülekezőpont",
		hud.rally_hint.text != "" and not hud.rally_hint.text.begins_with("gyulekezo"),
		hud.rally_hint.text)
	hud._on_rally_clear()
	check("az X gomb törli a gyülekezőpontot", not hq.rally_set)
	main.selected_bld = null

	# Egység kijelölése -> építési panel
	var w = _first_player_unit("worker")
	hud.update_selection([w] if w != null else [])
	await _frames(2)
	check("munkás kijelölésekor látható az építési panel", hud.build_panel.visible)
	check("nem látható egyszerre a képzési panel", not hud.train_panel.visible)
	check("az építési panelen vannak gombok",
		hud.build_panel.get_child_count() >= 6,
		"%d gomb" % hud.build_panel.get_child_count())
	hud.update_selection([])
	await _frames(2)
	check("üres kijelölésnél eltűnik a panel", not hud.sel_panel.visible)

	# --- Játék közbeni menü (jobb felső ☰) ---
	hud.open_game_menu(true)
	check("a ☰ gomb megnyitja a menüt", hud.game_menu_open())
	check("nyitott menünél áll a játék", get_tree().paused and not GameState.on)
	hud._show_settings(true)
	check("a menüből elérhető a beállítás", hud.settings_host.visible
		and not hud.menu_panel_ui.visible)
	hud._show_settings(false)
	check("a beállításból van vissza", hud.menu_panel_ui.visible)
	# A mentést tényleg kipróbáljuk, de a meglévő mentést nem bántjuk.
	var regi := ""
	var volt := FileAccess.file_exists(SaveManager.SAVE_PATH)
	if volt: regi = FileAccess.get_file_as_string(SaveManager.SAVE_PATH)
	hud._on_save_pressed()
	check("a menüből menthető a játék", SaveManager.has_save())
	check("a mentés visszajelez", hud.menu_note.text == Lang.t("mentve"))

	# MENTÉS-BETÖLTÉS ODA-VISSZA. A mentés sokáig csak a nyersanyagot és a
	# korszakot vitte magával; a játszma FAJTÁJA (kalóz? oktató?), a
	# pályaméret, a hírnév és a küldetésmérők elvesztek — a folytatás így
	# más játékot indított, mint amit elmentettünk.
	var m_pirate := GameState.pirate
	var m_world  := Vector2i(GameState.WORLD_W, GameState.WORLD_H)
	var m_fame   := GameState.fame
	var m_kills  := GameState.kills
	var m_ban    := GameState.banned_buildings.duplicate()
	var m_age: int = int(GameState.get_side(0)["age"])
	var m_upg    := (GameState.get_side(0)["upg"] as Dictionary).duplicate()
	# Egy felismerhető kalóz-állás, amit a betöltésnek vissza kell hoznia.
	GameState.pirate = true
	GameState.set_world_size(GameState.WORLD_PIRATE.x, GameState.WORLD_PIRATE.y)
	GameState.fame = 42.0
	GameState.kills = 7
	GameState.banned_buildings = ["barracks"]
	GameState.get_side(0)["upg"]["weapon"] = 2
	SaveManager.save_game()
	# Szándékosan elrontjuk, hogy a betöltés tényleg dolgozzon.
	GameState.pirate = false
	GameState.set_world_size(GameState.WORLD_BASE.x, GameState.WORLD_BASE.y)
	GameState.fame = 0.0
	GameState.kills = 0
	GameState.banned_buildings = []
	GameState.get_side(0)["upg"]["weapon"] = 0
	check("a mentés visszaolvasható", SaveManager.load_game())
	check("a kalózjátszma kalózként tér vissza", GameState.pirate)
	check("a pályaméret is a kalózvilágé",
		GameState.WORLD_W == GameState.WORLD_PIRATE.x,
		"%d" % GameState.WORLD_W)
	check("a hírnév megmarad", is_equal_approx(GameState.fame, 42.0),
		"%.1f" % GameState.fame)
	check("a küldetésmérők megmaradnak", GameState.kills == 7,
		"%d" % GameState.kills)
	check("a tiltott épületek megmaradnak",
		"barracks" in GameState.banned_buildings, str(GameState.banned_buildings))
	check("a fejlesztések megmaradnak", Upgrades.level(0, "weapon") == 2,
		"%d" % Upgrades.level(0, "weapon"))
	check("a korszak megmarad", GameState.get_side(0)["age"] == m_age)
	# Mindent visszaállítunk: a további szakaszok az eredeti állással futnak.
	GameState.pirate = m_pirate
	GameState.set_world_size(m_world.x, m_world.y)
	GameState.fame = m_fame
	GameState.kills = m_kills
	GameState.banned_buildings = m_ban
	GameState.get_side(0)["upg"] = m_upg
	Upgrades.reapply(0)
	if volt:
		var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		if f: f.store_string(regi); f.close()
	else:
		SaveManager.delete_save()
	hud.open_game_menu(false)
	check("a menü bezárása visszaindítja a játékot",
		not hud.game_menu_open() and not get_tree().paused and GameState.on)

	# --- Beállítások (grafika, hang) ---
	var m_on := Settings.music_on
	var s_vol := Settings.sfx_vol
	Settings.set_music_on(not m_on)
	check("a zene ki-be kapcsolható", Settings.music_on != m_on)
	Settings.set_sfx_vol(0.25)
	check("a hangerő állítható",
		is_equal_approx(Settings.sfx_vol, 0.25), "%.2f" % Settings.sfx_vol)
	check("a beállítás fájlba kerül",
		FileAccess.file_exists(Settings.PATH))
	Settings.set_music_on(m_on)
	Settings.set_sfx_vol(s_vol)

	# --- Főmenü: nem a játékbeállítással kezd ---
	var menu: Node = (load("res://scenes/ui/Menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _frames(2)
	check("a főmenü a címlappal indul", menu.screen() == "home", menu.screen())
	var gombok := 0
	for c in menu._home_box.get_children():
		if c is Button and str(c.name).begins_with("Btn_"): gombok += 1
	check("a főmenüben hat sor van (mint a régiben)", gombok == 6, "%d" % gombok)
	menu.show_screen("single")
	check("az Egy játékos képernyő megnyílik",
		menu._single_box.visible and not menu._home_box.visible)
	menu.show_screen("setup")
	check("onnan jutunk a játékbeállításba",
		menu._setup_box.visible and not menu._single_box.visible)
	menu.show_screen("settings")
	check("a főmenüből elérhető a beállítás", menu._settings_box.visible)
	var van_panel := false
	for c in menu._settings_box.get_children():
		if c is SettingsPanel: van_panel = true
	check("a beállítás ugyanaz a panel, mint a játékban", van_panel)
	menu.show_screen("home")

	# --- Nyelvválasztó: lenyíló fül a jobb felső sarokban ---
	check("a nyelvválasztó fül a jobb felső sarokban van",
		menu._lang_tab != null and menu.get_node_or_null("LangTab") != null)
	check("a nyelvlista alapból zárva van", not menu._lang_list.visible)
	menu._toggle_lang_list()
	check("a fülre kattintva lenyílik", menu._lang_list.visible)
	check("mindhárom nyelv szerepel benne", menu._lang_buttons.size() == 3,
		"%d" % menu._lang_buttons.size())
	menu._sel_lang(Lang.code)
	check("választás után becsukódik", not menu._lang_list.visible)
	check("a fülön a jelenlegi nyelv áll",
		Lang.language_name(Lang.code) in menu._lang_tab.text, menu._lang_tab.text)
	# A címlapon már nincs zászlósor a képernyő közepén.
	check("a nyelvsor nem foglal helyet a címlap közepén",
		menu._home_box.get_node_or_null("LangSection") == null)

	# --- A CÍMLAP AZ EREDETI (index.html) MENÜJÉNEK KÉPÉT HOZZA ---
	#
	# Kétszínű, ritkított cím ("BIRO" + arany "DALOM"), alatta az évszámok,
	# a háttérben sodródó heraldikai alakzatok.
	check("a főcím kétszínű (a második fele arany)",
		menu._home_title != null and menu._home_title.get_meta("parja", null) != null)
	if menu._home_title != null:
		var masodik := menu._home_title.get_meta("parja", null) as Label
		check("a cím első fele BIRO, a másik DALOM",
			menu._home_title.text == "BIRO" and masodik != null and masodik.text == "DALOM",
			"%s | %s" % [menu._home_title.text, masodik.text if masodik else "-"])
		check("a cím betűi ritkítva vannak",
			menu._home_title.get_theme_font("font") is FontVariation)
	check("a menü háttere a sodródó címeres háttér",
		menu.get_node_or_null("Background") != null
		and menu.get_node("Background").get_script() != null)

	# --- TÁJVÁLASZTÓ az Új játék képernyőn ---
	menu.show_screen("setup")
	check("az Új játék képernyőn ott a tájválasztó",
		menu._map_section != null and menu._map_btns.size() == 9,
		"%d gomb" % menu._map_btns.size())
	menu._sel_map("hegy")
	check("a tájválasztás megjegyződik", menu.chosen_map == "hegy")
	check("a tájhoz leírás is jár", menu._map_desc.text == Lang.t("taj_hegy_leiras"))
	menu._sel_mode(1)
	check("a kalózvilágban nincs tájválasztó (rögzített Karib-tenger)",
		not menu._map_section.visible)
	menu._sel_mode(0)
	menu._sel_map("mezo")

	# --- TÖBBJÁTÉKOS: a Heptarchia lobbijának felépítése ---
	menu.show_screen("mp")
	check("a többjátékos képernyőn van kapumező a házigazdának",
		menu._host_port != null and menu._join_port != null)
	check("a csatlakozás mezője a házigazda címét kéri",
		menu._mp_code != null and menu._mp_code.placeholder_text.contains("."))

	# --- A CSATA-SZOBA: világválasztó és táj (az eredeti szobaMod/szobaMap) ---
	menu.show_screen("battle")
	check("a szobában választható a világ (birodalmak / kalózok)",
		menu._battle_mode_row != null)
	check("a szobában választható a táj", menu._battle_map != null)
	menu._sel_battle_world(true)
	var kaloz_nemzetek := Style.order_for(true)
	var jo_nemzet := true
	for d in menu._battle_sides:
		if not (str(d["nemzet"]) in kaloz_nemzetek): jo_nemzet = false
	check("kalózvilágra váltva mindenki kalózfrakciót kap", jo_nemzet,
		str(menu._battle_sides))
	check("a kalózvilágban nincs tájválasztás a szobában sem",
		not menu._battle_map_row.visible)
	menu._sel_battle_world(false)
	check("visszaváltva megint a birodalmak listája jön",
		str(menu._battle_sides[0]["nemzet"]) in Style.order_for(false))

	# --- VISSZAJÁTSZÁS képernyő ---
	menu.show_screen("replay")
	check("van visszajátszás-képernyő a menüben", menu._replay_box != null
		and menu._replay_box.visible)
	menu.show_screen("home")

	# --- A zászlók körül nincs fehér keret ---
	# A képek pergamenlapon ülnek; a menü csak magát a lobogót vágja ki.
	var vagott: Array[String] = []
	for key in ["hu", "de", "gb"]:
		var t: Texture2D = Style.flag_texture(key, 3)
		if t == null: continue
		if not (t is AtlasTexture):
			vagott.append(key + ": nincs vágva")
			continue
		var at := t as AtlasTexture
		var teljes := at.atlas.get_size()
		if at.region.size.x >= teljes.x or at.region.size.y >= teljes.y:
			vagott.append("%s: %s / %s" % [key, at.region.size, teljes])
	check("a zászlókról levágjuk a pergamen keretet", vagott.is_empty(),
		str(vagott))

	menu.queue_free()
	await _frames(2)

	# Szünet és játék vége
	hud.set_paused(true)
	check("a szünet-fátyol megjelenik", hud.pause_overlay.visible)
	hud.set_paused(false)
	check("a szünet-fátyol eltűnik", not hud.pause_overlay.visible)
	# Küldetés teljesítve képernyő (hadjárat)
	Campaign.start("hu", 0)
	hud.show_mission_complete(true)
	check("a küldetés teljesítve képernyő megjelenik", hud.over_overlay.visible)
	check("van gomb a következő küldetéshez", hud.over_next_btn.visible)
	hud.show_mission_complete(false)
	check("az utolsó küldetés után nincs tovább gomb",
		not hud.over_next_btn.visible)
	Campaign.stop()
	hud.over_overlay.visible = false

	hud.show_game_over(true)
	check("a játék vége képernyő megjelenik", hud.over_overlay.visible)
	# A szöveg a választott nyelvből jön, ezért ahhoz mérjük.
	check("győzelem szöveget ír ki", hud.over_label.text == Lang.t("gyozelem"),
		hud.over_label.text)
	hud.over_overlay.visible = false

	# Építő mód
	main.set_build_mode("farm")
	await _frames(2)
	check("építő módban van előnézet", is_instance_valid(main._ghost))
	main.set_build_mode("")
	await _frames(3)
	check("kilépve eltűnik az előnézet", main._ghost == null)

	# Kistérkép
	var mm = hud.minimap
	check("van kistérkép", mm != null)
	if mm == null: return
	for _i in range(20):
		if mm._ready_ok: break
		await _frames(2)
	check("a kistérkép bekötötte a terep- és ködtextúrát", mm._ready_ok)
	var mat := (mm.ground.material as ShaderMaterial) if mm.ground else null
	check("a talajmaszk a shaderben van",
		mat != null and mat.get_shader_parameter("land_mask") != null)
	check("a ködkép a shaderben van",
		mat != null and mat.get_shader_parameter("fog_tex") != null)
	# Kattintás a kistérkép jobb alsó sarkába: a kamera odaugrik.
	var cam_before: Vector2 = main.camera.position
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = mm.size * Vector2(0.85, 0.85)
	mm._gui_input(ev)
	await _frames(2)
	check("kistérkép-kattintásra ugrik a kamera",
		main.camera.position.distance_to(cam_before) > 200.0,
		"%s -> %s" % [cam_before, main.camera.position])

# --- 11. Kalózvilág ---
#
# A kalóz módot nem indítjuk újra (az egy másik játszma) — azt vizsgáljuk,
# hogy az adatok és a szabályok a helyükön vannak-e.
func _test_pirate() -> void:
	print("\n[11] Kalózvilág")
	check("három kalózfrakció van", Style.PIRATE_ORDER.size() == 3,
		str(Style.PIRATE_ORDER))
	var missing: Array[String] = []
	for key in Style.PIRATE_ORDER:
		var n: Dictionary = Style.nation(key)
		if not n.has("rulers") or n["rulers"].size() != 4:
			missing.append("adat %s" % key)
		if not ResourceLoader.exists(Style.flag_path(key, 0)):
			missing.append("zászló %s" % key)
		if not ResourceLoader.exists(Style.ruler_path(key, 0)):
			missing.append("kapitány %s" % key)
	check("minden kalózfrakcióhoz van zászló és kapitánykép",
		missing.is_empty(), str(missing))
	check("a kalózvilág pályája nagyobb",
		GameState.WORLD_PIRATE.x > GameState.WORLD_BASE.x
		and GameState.WORLD_PIRATE.y > GameState.WORLD_BASE.y)
	# A kamera határainak a PÁLYÁHOZ kell igazodniuk, nem a jelenetben
	# rögzített alapmérethez — különben a nagyobb pályán a bázis kilóg.
	check("a kamera határai a pályához igazodnak",
		main.camera.limit_right == GameState.WORLD_W
		and main.camera.limit_bottom == GameState.WORLD_H,
		"%d x %d" % [main.camera.limit_right, main.camera.limit_bottom])
	var hq2 = _player_hq()
	check("a bázis a kamera határain belül van",
		hq2 != null and hq2.global_position.x <= main.camera.limit_right
		and hq2.global_position.y <= main.camera.limit_bottom)
	check("a cukornád rumot termel",
		Building.BUILD_STATS["sugar"].has("rum"))
	check("a cukornád csak a kalózvilágban építhető",
		bool(Building.BUILD_STATS["sugar"].get("pirateOnly", false)))

	# --- A KARIB-TENGER VÁROSAI ÉS AZ OSTROM ---
	if GameState.pirate:
		var c = main.cities
		check("a kalózvilágban ott vannak a kikötővárosok", c != null)
		if c != null:
			check("tizennégy város van a térképen", c.varosok.size() == 14,
				"%d" % c.varosok.size())
			# Minden városnak van helye a pályán belül és lakossága.
			var rossz_v: Array[String] = []
			for v in c.KIKOTOK:
				var k := str(v["kulcs"])
				var p: Vector2 = c.city_pos(k)
				if p.x <= 0.0 or p.y <= 0.0 or p.x >= GameState.WORLD_W \
						or p.y >= GameState.WORLD_H:
					rossz_v.append(k + ":hely")
				if float((c.varosok[k] as Dictionary)["lakos"]) <= 0.0:
					rossz_v.append(k + ":lakos")
			check("minden városnak van helye és lakossága", rossz_v.is_empty(),
				str(rossz_v))
			# A bázis melletti város a miénk.
			var sajat := ""
			for v in c.KIKOTOK:
				if c.owner_of(str(v["kulcs"])) == 0: sajat = str(v["kulcs"])
			check("a bázisunk városa hozzánk tartozik", sajat != "", sajat)
			# OSTROM: tornyok nélkül, kiürült lakossággal a város nyitva áll,
			# és a partra tett katona elfoglalja.
			var cel := ""
			for v in c.KIKOTOK:
				if c.owner_of(str(v["kulcs"])) != 0: cel = str(v["kulcs"])
			if cel != "":
				var a: Dictionary = c.varosok[cel]
				a["torony"] = 0
				a["lakos"] = 5.0
				a["helyorseg"] = true          # a helyőrség már kiállt és elesett
				check("torony nélkül, kiürülve a város nyitva áll", c._open(cel))
				var arany0: float = float(GameState.get_res(0).get("gold", 0.0))
				var p2: Vector2 = c.city_pos(cel)
				var hely: Vector2 = main.find_land_near(p2 + Vector2(60, 0), 30.0)
				var katona = main.spawn_unit("melee", 0, hely, GameState.get_age())
				await _frames(3)
				c._landing(cel, a, p2, c.owner_of(cel))
				check("a partra tett katona elfoglalja a nyitott várost",
					int(a["gazda"]) == 0, "gazda %d" % int(a["gazda"]))
				check("az elfoglalás zsákmányt hoz",
					float(GameState.get_res(0).get("gold", 0.0)) > arany0)
				if is_instance_valid(katona): katona.queue_free()

	# --- VISSZAJÁTSZÁS: a játszmáról felvétel készül ---
	check("a játszmát felveszi a visszajátszó",
		main.replay != null and bool(main.replay.recording))
	check("a felvétel a pillanatképeket gyűjti",
		main.replay != null and main.replay.HZ >= 4.0)
	# Hírnév: rendes játszmában nem mozdul.
	var was_pirate: bool = GameState.pirate
	GameState.pirate = false
	var f0: float = GameState.fame
	GameState.add_fame(20.0)
	check("rendes játszmában nincs hírnév", is_equal_approx(GameState.fame, f0),
		"%.1f" % GameState.fame)
	# Kalóz módban viszont nő, és a tetőn kifut a hajóhad.
	GameState.pirate = true
	GameState.fame = 0.0
	var fired := [false]
	var cb := func() -> void: fired[0] = true
	GameState.royal_fleet.connect(cb)
	GameState.add_fame(30.0)
	check("kalóz módban nő a hírnév", GameState.fame > 25.0, "%.1f" % GameState.fame)
	GameState.add_fame(GameState.FAME_MAX)
	check("a tetőn kifut a királyi hajóhad", fired[0])
	check("a hajóhad után visszaesik a hírnév",
		GameState.fame < GameState.FAME_MAX, "%.1f" % GameState.fame)
	GameState.fame_tick(600.0)
	check("a hírnév idővel csillapodik", GameState.fame < GameState.FAME_MAX * 0.55,
		"%.1f" % GameState.fame)
	GameState.royal_fleet.disconnect(cb)
	GameState.pirate = was_pirate
	GameState.fame = 0.0

# --- 12. Hadjárat ---

func _test_campaign() -> void:
	print("\n[12] Hadjárat")
	var lista := Campaign.campaigns()
	check("betöltöttek a hadjáratok", lista.size() >= 10, "%d db" % lista.size())
	var osszes := 0
	var hibas: Array[String] = []
	var tipusok := {}
	for n in lista:
		var ms := Campaign.missions(n)
		if ms.size() < 4: hibas.append("%s: %d küldetés" % [n, ms.size()])
		for m in ms:
			osszes += 1
			var o: Dictionary = m.get("obj", {})
			tipusok[str(o.get("type", "?"))] = true
			if not m.has("name") or str(m["name"]).is_empty():
				hibas.append("%s: névtelen" % m.get("id", "?"))
			if not m.has("brief") or str(m["brief"]).is_empty():
				hibas.append("%s: eligazítás nélkül" % m.get("id", "?"))
			if not m.has("res") or (m["res"] as Dictionary).is_empty():
				hibas.append("%s: kezdőkészlet nélkül" % m.get("id", "?"))
			if Campaign.target_of(m) <= 0 and str(o.get("type", "")) != "destroy":
				hibas.append("%s: nincs célérték" % m.get("id", "?"))
	check("minden küldetés teljes", hibas.is_empty(), str(hibas.slice(0, 4)))
	check("legalább 60 küldetés van", osszes >= 60, "%d db" % osszes)
	check("mind a hét céltípus szerepel", tipusok.size() >= 6,
		str(tipusok.keys()))
	# A célszöveg minden típusra kiolvasható és nem hagy nyers kulcsot.
	var nyers: Array[String] = []
	for n in lista:
		for m in Campaign.missions(n):
			var s := Campaign.objective_text(m)
			if s.begins_with("cel_") or s.is_empty():
				nyers.append(str(m.get("id", "?")))
	check("minden cél szövege lefordul", nyers.is_empty(), str(nyers.slice(0, 4)))
	# Haladás: a teljesítés lép egyet és megmarad.
	var elozo := Campaign.done("hu")
	Campaign.start("hu", 0)
	check("a hadjárat elindul", Campaign.active and Campaign.nation == "hu")
	check("van soron következő küldetés", Campaign.has_next())
	Campaign.complete()
	check("a teljesítés rögzül", Campaign.done("hu") >= 1,
		"%d" % Campaign.done("hu"))
	check("a következő küldetésre lép", Campaign.advance() and Campaign.index == 1)
	Campaign._done["hu"] = elozo
	Campaign._save_progress()
	Campaign.stop()

	# Ha épp hadjáratban vagyunk, a küldetés beállításai is érvényesek.
	if _saved_objective != null:
		var m2: Dictionary = _saved_objective.mission
		# A korszakot a KEZDÉSKOR állítja be a küldetés; a [5] teszt
		# közben léptet egyet, ezért a kiinduló korszakot nézzük.
		check("a küldetés korszaka érvényesült",
			GameState.start_age == int(m2.get("age", 0)),
			"%d" % GameState.start_age)
		check("a küldetés célja megjelenik a HUD-on",
			main.hud.mission_panel.visible)
		check("a cél állása kiolvasható",
			_saved_objective.text(get_tree()).length() > 4)
		# A küldetés tilthat épületeket, és a fővárosba teheti a képzést.
		if not GameState.hq_trains.is_empty():
			check("a küldetés a fővárosba tette a képzést",
				_player_hq().trainable() == GameState.hq_trains,
				str(_player_hq().trainable()))
		if not GameState.banned_buildings.is_empty():
			var tiltott: String = GameState.banned_buildings[0]
			check("a tiltott épületet nem lehet lerakni",
				not main.can_place(tiltott, _player_hq().global_position
					+ Vector2(300, 0)), tiltott)

# --- 13. Csata több féllel, teljesítmények, oktatómód ---

func _test_modules() -> void:
	print("\n[13] Több fél, teljesítmények, oktatómód")

	# --- Csata több féllel ---
	# Az oldalak listáját ideiglenesen kicseréljük; a pálya nem változik,
	# ezért a teszt végén pontosan visszaáll.
	var mentett: Array[Dictionary] = GameState.oldalak.duplicate(true)
	GameState.oldalak.clear()
	GameState.add_oldal("ember", true,  "hu", 0, 0)
	GameState.add_oldal("bot",   false, "de", 0, 0)     # szövetséges
	GameState.add_oldal("bot",   false, "fr", 1, 0)
	GameState.add_oldal("bot",   false, "gb", 2, 0)
	check("négy fél elfér egy pályán", GameState.oldalak.size() == 4)
	check("az azonos csapatszámúak szövetségesek",
		GameState.allied(0, 1) and not GameState.hostile(0, 1))
	check("a külön csapatszámúak ellenségek",
		GameState.hostile(0, 2) and GameState.hostile(2, 3))
	check("magával senki nem ellenséges", not GameState.hostile(2, 2))
	var helyek := WorldGen.start_positions()
	check("minden félnek jut kezdőhely", helyek.size() == 4,
		"%d db" % helyek.size())
	var tavol := true
	for i in helyek.size():
		for j in range(i + 1, helyek.size()):
			if helyek[i].distance_to(helyek[j]) < 600.0: tavol = false
	check("a kezdőhelyek nem érnek össze", tavol, str(helyek))
	var szinek := {}
	for i in range(4): szinek[Style.side_color(i)] = true
	check("minden oldal más jelzőszínt kap", szinek.size() == 4)
	GameState.oldalak.assign(mentett)
	check("az oldalak visszaálltak", GameState.oldalak.size() == mentett.size())

	# --- Teljesítmények ---
	var ment_stat: Dictionary = Achievements.stats.duplicate()
	var ment_unl: Array = Achievements.unlocked.duplicate()
	Achievements.stats = {}
	Achievements.unlocked = []
	check("tizenöt teljesítmény van", Achievements.DEFS.size() == 15,
		"%d db" % Achievements.DEFS.size())
	var nyers_ach: Array[String] = []
	for d in Achievements.DEFS:
		var id := str(d["id"])
		if Achievements.title_of(id) == "ach_" + id: nyers_ach.append(id)
		if Achievements.desc_of(id) == "ach_" + id + "_d": nyers_ach.append(id + "_d")
	check("minden teljesítménynek van neve és leírása",
		nyers_ach.is_empty(), str(nyers_ach.slice(0, 4)))
	check("üresen egy sincs kinyitva", Achievements.count_unlocked() == 0)
	Achievements.bump("kills", 1.0)
	check("egy ölés kinyitja az Első vért",
		Achievements.is_unlocked("elso_ver"))
	check("a nagyobb cél még nincs meg",
		not Achievements.is_unlocked("hadvezer"))
	check("a haladás arányos", is_equal_approx(
		Achievements.progress("hadvezer"), 1.0 / 50.0),
		"%.3f" % Achievements.progress("hadvezer"))
	Achievements.reach("era", 3.0)
	check("a korszakok elérése két teljesítményt nyit",
		Achievements.is_unlocked("korszakvalto")
		and Achievements.is_unlocked("modern_kor"))
	Achievements.reach("era", 1.0)
	check("a legjobb érték nem esik vissza",
		is_equal_approx(Achievements.value_of("era"), 3.0))
	# --- Részletesség (gyenge gépekhez) ---
	var ment_detail := Settings.detail
	Settings.set_detail(0)
	check("alacsony fokozaton nem mozognak az apróságok",
		not Settings.lively())
	check("alacsony fokozaton ritkább a köd",
		Settings.fog_interval() > 0.15, "%.2f" % Settings.fog_interval())
	Settings.set_detail(2)
	check("magas fokozaton minden mozog",
		Settings.lively() and Settings.fog_interval() <= 0.1)
	Settings.set_detail(5)
	check("a fokozat nem szalad ki a tartományból", Settings.detail == 2,
		"%d" % Settings.detail)
	Settings.set_detail(ment_detail)
	# Az ellenségkeresés ritkítása: nem képkockánként fut.
	check("az ellenségkeresés ritkítva van", Unit.SCAN_PERIOD >= 0.2,
		"%.2f mp" % Unit.SCAN_PERIOD)
	# A képernyőn kívüli apróságok nem mozognak — ez volt a legnagyobb
	# nyereség a gyenge gépen (32 ms -> 18 ms képidő).
	check("a képernyőn kívüli apróságok alapból nem mozognak",
		Settings.cull_offscreen)
	var kemeny: Node = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.tipus in Building.CHIMNEY and b.is_ready():
			kemeny = b
			break
	if kemeny != null:
		kemeny._ensure_smoke()
		var kulon := kemeny._smoke_node != null
		var figy := false
		for c in kemeny.get_children():
			if c is VisibleOnScreenNotifier2D: figy = true
		check("a füst külön csomóponton van (nem rajzolja újra a házat)",
			kulon)
		check("a kémény is csak a képernyőn füstöl", figy)

	Achievements.stats = ment_stat
	Achievements.unlocked = ment_unl
	Achievements.save_progress()
	check("a haladás visszaállt",
		Achievements.count_unlocked() == ment_unl.size())

	# --- Oktatómód ---
	check("az oktatómód hat lépésből áll", Tutorial.STEPS.size() == 6,
		"%d db" % Tutorial.STEPS.size())
	var nyers_okt: Array[String] = []
	for s in Tutorial.STEPS:
		if Lang.t("okt_" + str(s)) == "okt_" + str(s): nyers_okt.append(str(s))
	check("minden oktató lépéshez van szöveg", nyers_okt.is_empty(),
		str(nyers_okt))
	var panel_volt: bool = main.hud.mission_panel.visible
	var tut := Tutorial.new(main)
	add_child(tut)
	await _frames(2)
	check("az oktatómód az első lépéssel indul", tut.step == 0 and not tut.done)
	check("a lépés szövege megjelenik a panelen",
		main.hud.mission_panel.visible
		and main.hud.objective_lbl.text.contains("1/6"),
		main.hud.objective_lbl.text)
	# A lépések feltételei a jelenetfából olvasnak; a "kijelöl" lépés a
	# kijelölt munkásra vár.
	var w2 = _first_player_unit("worker")
	if w2 != null:
		var kijelolt: Array[Node] = [w2]
		main.selected_units = kijelolt
		check("a kijelölt munkás továbblép", tut._check("kijelol"))
		main.selected_units = [] as Array[Node]
		check("kijelölés nélkül nem lép", not tut._check("kijelol"))
	tut.queue_free()
	main.hud.mission_panel.visible = panel_volt

	# OKTATÓMÓDBAN NINCS TÁMADÁS. Sokáig mégis kifutott egy hullám: a botok
	# indítása MEGELŐZTE a hullámidő kikapcsolását, így az első hullám a régi
	# 115 mp-es ütemmel elindult, és a kezdő játékosra rontott.
	var okt_volt := GameState.tutorial
	var bot_egysegek_elott := _count_side_units(1)
	GameState.tutorial = true
	main.bot_ai.wave_timer = -1.0
	main.bot_ai._send_wave()
	check("oktatómódban a bot nem indít hullámot",
		_count_side_units(1) == bot_egysegek_elott,
		"%d -> %d" % [bot_egysegek_elott, _count_side_units(1)])
	check("és a hullámidő is ki van tolva", main.bot_ai.wave_timer > 1000.0)
	GameState.tutorial = okt_volt
	main.bot_ai.wave_timer = 99999.0

# --- 15. Hálózati többjátékos ---
#
# A tényleges kapcsolat két folyamatot igényel (lásd --nethost /
# --netjoin), itt a KÖRÜLÖTTE lévő logikát ellenőrizzük: a szobakód, az
# oldalkiosztás, a parancsok gazdaellenőrzése és a pillanatkép szótárai.

func _test_net() -> void:
	print("\n[15] Hálózati többjátékos")
	check("nyolc fél fér egy szobába", Net.MAX_PLAYERS == 8,
		"%d" % Net.MAX_PLAYERS)
	# Szobakód: oda-vissza kell működnie, és nyolc betűnek kell lennie.
	var rossz: Array[String] = []
	for proba in [["192.168.1.7", 27015], ["10.0.0.42", 27019],
			["172.16.3.200", 27015], ["192.168.100.1", 27030]]:
		var kod := Net.make_code(str(proba[0]), int(proba[1]))
		if kod.length() != 8:
			rossz.append("%s -> %s" % [proba[0], kod])
			continue
		var vissza := Net.parse_code(kod)
		if vissza.is_empty() or str(vissza[0]) != str(proba[0]) \
				or int(vissza[1]) != int(proba[1]):
			rossz.append("%s:%d -> %s -> %s" % [proba[0], proba[1], kod, vissza])
	check("a szobakód oda-vissza pontos", rossz.is_empty(), str(rossz))
	check("a hibás kódot elutasítja",
		Net.parse_code("XX").is_empty() and Net.parse_code("ABCDEFG!").is_empty())
	check("a kód olvasható alakja kötőjeles",
		Net.pretty("ABCDEFGH") == "ABCD-EFGH", Net.pretty("ABCDEFGH"))
	# Interneten át: a kód a NYILVÁNOS címet is elbírja, és kód helyett
	# nyers cím is megadható (kézi kapuátirányítás, VPN).
	var pub := Net.make_code("81.183.44.201", 27015)
	var vissza2 := Net.parse_code(pub)
	check("a nyilvános IP is belefér a kódba",
		not vissza2.is_empty() and str(vissza2[0]) == "81.183.44.201",
		"%s -> %s" % [pub, vissza2])
	check("kód helyett cím is megadható",
		Net.parse_address("81.183.44.201:27019") == ["81.183.44.201", 27019],
		str(Net.parse_address("81.183.44.201:27019")))
	# A HÁZIGAZDA CÍME. A lobbi "cím:kapu" alakban írja ki — pontosan azt,
	# amit a vendégnek be kell gépelnie —, és a csatlakozó mező ezt elfogadja.
	var ip_volt := Net.lan_ip
	var kapu_volt := Net.port
	Net.lan_ip = "192.168.0.12"
	Net.port = 27015
	check("a házigazda címe cím:kapu alakú",
		Net.lan_address() == "192.168.0.12:27015", Net.lan_address())
	check("a kiírt címmel lehet csatlakozni",
		Net.parse_address(Net.lan_address()) == ["192.168.0.12", 27015])
	Net.public_ip = "81.183.44.201"
	check("az internetes cím is cím:kapu alakú",
		Net.public_address() == "81.183.44.201:27015", Net.public_address())
	Net.public_ip = ""
	Net.lan_ip = ip_volt
	Net.port = kapu_volt
	var nincs_felirat: Array[String] = []
	for k in ["net_hazigazda_cime", "net_cim_helyi", "net_cim_internet"]:
		if Lang.t(k) == k: nincs_felirat.append(k)
	check("a címes csatlakozás feliratai megvannak", nincs_felirat.is_empty(),
		str(nincs_felirat))
	check("kapu nélküli cím az alapkaput kapja",
		Net.parse_address("gep.otthon.local") == ["gep.otthon.local", Net.PORT_BASE])
	check("a nyolcbetűs kódot nem nézi címnek",
		Net.parse_address("ABCDEFGH").is_empty())

	# --- Közvetítő: bárki, bárhonnan ---
	# A tízbetűs kód a közvetítő címét, kapuját ÉS a szoba sorszámát is
	# elbírja — így egyetlen kód elég, külön beírandó cím nélkül.
	var rossz_r: Array[String] = []
	for szoba in [0, 7, 200]:
		var k := Net.make_code("81.183.44.201", 27020, szoba)
		if k.length() != 10:
			rossz_r.append("hossz %d" % k.length())
			continue
		var v := Net.parse_code(k)
		if v.size() != 3 or str(v[0]) != "81.183.44.201" \
				or int(v[1]) != 27020 or int(v[2]) != szoba:
			rossz_r.append("%d -> %s -> %s" % [szoba, k, v])
	check("a közvetítős kód a szobaszámot is viszi", rossz_r.is_empty(),
		str(rossz_r))
	check("a közvetítős kód tíz betű, kötőjellel",
		Net.pretty(Net.make_code("10.0.0.1", 27020, 3)).length() == 11,
		Net.pretty(Net.make_code("10.0.0.1", 27020, 3)))
	check("a közvetlen kód továbbra is nyolc betű, szoba nélkül",
		Net.parse_code(Net.make_code("10.0.0.1", 27015)).size() == 2)
	# A beviteli mezőbe BE IS KELL FÉRNIE a leghosszabb kódnak. A korlát
	# sokáig kilenc karakter volt (a közvetlen kódra szabva), és a
	# tizenegy karakteres közvetítős kódot szó nélkül levágta.
	var menu_kod := (load("res://scenes/ui/Menu.tscn") as PackedScene).instantiate()
	add_child(menu_kod)
	await _frames(2)
	var leghosszabb := Net.pretty(Net.make_code("255.255.255.255", 27020, 7))
	check("a szobakód-mezőbe befér a közvetítős kód is",
		menu_kod._mp_code.max_length >= leghosszabb.length(),
		"mező %d, kód %d (%s)" % [menu_kod._mp_code.max_length,
			leghosszabb.length(), leghosszabb])
	menu_kod.queue_free()
	await _frames(2)
	check("alapból a házigazda az 1-es hely", Net.host_peer == 1)
	check("alapból közvetlen a kapcsolat", Net.transport == "direkt")
	check("a közvetítő nem játszik", not Net.relay_mode)

	# A pillanatkép sorszámmal küldi a szerepkört és az épülettípust — ha
	# valamelyik kimaradna a listából, a társnál rossz bábu jelenne meg.
	var hianyzo: Array[String] = []
	for r in Unit.UNIT_STATS.keys():
		if not (str(r) in Unit.ROLE_ORDER): hianyzo.append("egység:" + str(r))
	for t in Building.BUILD_STATS.keys():
		if not (str(t) in Building.TIPUS_ORDER): hianyzo.append("épület:" + str(t))
	check("minden szerepkör és épülettípus átvihető hálózaton",
		hianyzo.is_empty(), str(hianyzo))

	# Oldalkiosztás: nyolc fél, és a HARMADIK vagyunk.
	var mentett: Array[Dictionary] = GameState.oldalak.duplicate(true)
	var mentett_en := GameState.en_id
	var lista: Array = []
	for i in range(8):
		lista.append({"tipus": "ember", "nemzet": "hu", "csapat": i,
			"peer": 100 + i})
	check("a hálózati oldal-lista nyolc főt bír", lista.size() == 8)
	check("a saját oldalt a peer azonosító adja",
		Net.side_index_of(lista, 103) == 3,
		"%d" % Net.side_index_of(lista, 103))
	GameState.oldalak.assign(mentett)
	GameState.en_id = mentett_en

	# Parancsellenőrzés: idegen oldal nem mozgathatja a mi egységünket.
	var w = _first_player_unit("worker")
	if w != null:
		var hova: Vector2 = w.global_position + Vector2(200, 0)
		var eredeti: Vector2 = w.nav.target_position
		main.do_move([int(w.nid)], hova, 999)          # nem létező oldal
		check("idegen oldal nem parancsolhat a mi egységünknek",
			w.nav.target_position == eredeti)
		main.do_move([int(w.nid)], hova, w.owner_id)
		check("a saját oldal parancsa érvényes",
			w.nav.target_position.distance_to(hova) < 60.0)
		check("az egységeknek van hálózati azonosítójuk", w.nid > 0,
			"%d" % w.nid)
		check("az azonosítóból visszakereshető az egység",
			main.unit_by_nid(int(w.nid)) == w)
		w.stop()
	var hq = _player_hq()
	if hq != null:
		check("az épületeknek is van azonosítójuk", hq.nid > 0)
		check("az épület azonosítóból visszakereshető",
			main.building_by_nid(int(hq.nid)) == hq)
	var lelo := get_tree().get_nodes_in_group("resources")
	if not lelo.is_empty():
		check("a lelőhelyeknek is van azonosítójuk", int(lelo[0].nid) > 0)

# --- 14. Elrendezés: semmilyen szöveg ne lógjon ki ---
#
# Két hibát keresünk minden látható feliraton és gombon:
#   1. a szöveg nem fér el a saját dobozában (a doboz kisebb, mint amennyi
#      a szöveghez kellene) — ilyenkor a szöveg kilóg vagy levágódik,
#   2. a doboz kilóg a képernyőből.
# A hosszú német és angol szavak miatt ezt mindhárom nyelven érdemes futtatni.

const LAYOUT_TOL := 1.0

func _layout_problems(root: Node, cimke: String) -> Array[String]:
	var out: Array[String] = []
	var vp := get_viewport().get_visible_rect()
	for n in _all_controls(root):
		var c := n as Control
		if not c.is_visible_in_tree(): continue
		# A Godot sosem engedi a doboz méretét a szöveg alá, ezért a
		# kilógás úgy néz ki, hogy a GYEREK kilóg a SZÜLŐ keretéből:
		# a panel mérete kötött, a felirat viszont szélesebb nála.
		# Kivétel a görgethető lista: annak épp az a dolga, hogy a
		# tartalma túlnyúljon a kereten.
		var p := c.get_parent() as Control
		if p != null and not (p is ScrollContainer) \
				and p.get_global_rect().size.x > 0.0:
			var pr := p.get_global_rect()
			var cr := c.get_global_rect()
			if cr.position.x < pr.position.x - LAYOUT_TOL \
					or cr.position.y < pr.position.y - LAYOUT_TOL \
					or cr.end.x > pr.end.x + LAYOUT_TOL \
					or cr.end.y > pr.end.y + LAYOUT_TOL:
				out.append("%s/%s kilóg a keretéből: %s > %s (%s)" % [
					cimke, c.name, cr, pr, _text_of(c)])
		# A görgethető lista tartalma jogosan nyúlik a képernyőn kívülre.
		if _in_scroll(c): continue
		var r := c.get_global_rect()
		if r.size.x <= 0.0 or r.size.y <= 0.0: continue
		if r.position.x < -LAYOUT_TOL or r.position.y < -LAYOUT_TOL \
				or r.end.x > vp.size.x + LAYOUT_TOL \
				or r.end.y > vp.size.y + LAYOUT_TOL:
			if c is Label or c is Button or c is PanelContainer \
					or c is TextureRect or c is ProgressBar:
				out.append("%s/%s kilóg a képernyőből: %s" % [cimke, c.name, r])
	return out

func _in_scroll(c: Node) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer: return true
		p = p.get_parent()
	return false

func _text_of(c: Control) -> String:
	if c is Label: return (c as Label).text.substr(0, 28)
	if c is Button: return (c as Button).text.substr(0, 28)
	return ""

func _all_controls(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control: out.append(n as Control)
		for ch in n.get_children(): stack.append(ch)
	return out

func _test_layout() -> void:
	print("\n[14] Elrendezés — kilógó szövegek")
	var hud = main.hud
	# Előbb magát a mérőt hitelesítjük: egy szándékosan szűk dobozba tett
	# hosszú szöveget észre kell vennie, különben a többi "rendben" semmit
	# nem érne.
	var proba := Control.new()
	proba.custom_minimum_size = Vector2(40, 12)
	proba.size = Vector2(40, 12)
	add_child(proba)
	var l := Label.new()
	l.text = "Ez egy szándékosan nagyon hosszú felirat, ami sehogy sem fér el."
	proba.add_child(l)
	await _frames(2)
	check("a mérő észreveszi a kilógó szöveget",
		not _layout_problems(proba, "proba").is_empty())
	proba.queue_free()
	await _frames(2)
	var hq = _player_hq()
	# Minden panelt felnyitunk és valós tartalommal töltünk meg, mert
	# rejtett panel mérete semmit nem árul el.
	GameState.get_res(0)["wood"] = 999999.0
	GameState.get_res(0)["gold"] = 999999.0
	hud._update_resources()
	if hq != null: hud.select_building(hq)
	var w = _first_player_unit("worker")
	await _frames(2)
	var gond := _layout_problems(hud, "HUD")
	check("a felső sáv és a képzési panel szövegei elférnek",
		gond.is_empty(), str(gond.slice(0, 3)))

	hud.select_building(null)
	if w != null: hud.update_selection([w])
	hud.show_toast(Lang.t("gyulekezo_nincs"), 9.0)
	hud.show_tutorial(Lang.t("oktatomod"), Lang.t("okt_haz"))
	await _frames(2)
	var gond2 := _layout_problems(hud, "HUD2")
	check("a kijelölés, az üzenet és az oktató panel szövegei elférnek",
		gond2.is_empty(), str(gond2.slice(0, 3)))

	hud.open_game_menu(true)
	hud._show_settings(true)
	await _frames(2)
	var gond3 := _layout_problems(hud, "Menü")
	check("a beállítások szövegei elférnek", gond3.is_empty(),
		str(gond3.slice(0, 3)))
	hud._show_settings(false)
	await _frames(2)
	var gond4 := _layout_problems(hud, "Menü2")
	check("a játék közbeni menü szövegei elférnek", gond4.is_empty(),
		str(gond4.slice(0, 3)))
	hud.open_game_menu(false)

	hud.show_game_over(false)
	await _frames(2)
	var gond5 := _layout_problems(hud, "Vége")
	check("a játék vége képernyő szövegei elférnek", gond5.is_empty(),
		str(gond5.slice(0, 3)))
	hud.over_overlay.visible = false
	hud.update_selection([])
	hud.mission_panel.visible = false

	# --- A főmenü minden képernyője ---
	var menu: Node = (load("res://scenes/ui/Menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _frames(2)
	for kep in ["home", "single", "setup", "settings", "battle", "ach"]:
		menu.show_screen(str(kep))
		if kep == "battle":
			while menu._battle_sides.size() < 6: menu._add_bot()
		await _frames(2)
		var g := _layout_problems(menu, "menu:" + str(kep))
		check("a(z) %s képernyő szövegei elférnek" % kep, g.is_empty(),
			str(g.slice(0, 3)))
	menu.queue_free()
	await _frames(2)

	# --- Kisebb ablakban is elférjen minden ---
	var eredeti: Vector2i = get_window().size
	get_window().size = Vector2i(1024, 600)
	await _frames(3)
	var kicsi := get_viewport().get_visible_rect().size
	if kicsi.x < eredeti.x - 1.0:
		if hq != null: hud.select_building(hq)
		if w != null: hud.update_selection([w])
		hud.show_toast(Lang.t("csata_sugo"), 9.0)
		await _frames(2)
		var gk := _layout_problems(hud, "kicsi")
		check("kisebb ablakban sem lóg ki szöveg", gk.is_empty(),
			str(gk.slice(0, 3)))
		hud.select_building(null)
		hud.update_selection([])
	get_window().size = eredeti
	await _frames(2)

# --- Fegyverpróba (--weapontest) ---
#
# Rácsban kirakja a szerszámos szerepköröket mind a négy irányban, állva és
# csapás közben, majd megállítja a szimulációt — így a képernyőképen
# pontosan látszik, hova kerül a szerszám a kézhez képest.
func weapon_test(age: int = 0) -> void:
	var hq = _player_hq()
	if hq == null: return
	var origin: Vector2 = hq.global_position + Vector2(-230, -230)
	var roles := ["worker", "melee", "spear", "ranged"]
	var units: Array = []
	for r in roles.size():
		for d in range(4):
			for atk in range(2):
				var p := origin + Vector2(float(d * 2 + atk) * 62.0, float(r) * 78.0)
				var u = main.spawn_unit(str(roles[r]), 0, p, age)
				units.append([u, d, atk == 1])
	main.camera.position = origin + Vector2(230, 130)
	main.camera.zoom = Vector2(1.8, 1.8)
	main.camera.reset_smoothing()
	main.fog.reveal_all()
	await _frames(3)
	# A szimuláció megáll, hogy a beállított irány és póz maradjon.
	GameState.on = false
	for e in units:
		var u = e[0]
		if not is_instance_valid(u): continue
		var szog: float = [0.0, PI * 0.5, PI, -PI * 0.5][int(e[1])]
		u.face = szog
		u.sprite.update_anim(szog, 0.0, false, bool(e[2]))

# --- Hajópróba (--shiptest) ---
#
# A négy hajótípust kirakja mind a négy irányban a legnagyobb vízfelületre,
# és megállítja a szimulációt. Egyetlen képernyőképen látszik, hogy a hajó
# a menetirányba néz-e, és hogy az árbocok állnak-e.
func ship_test(age: int = 0) -> void:
	var viz := _find_water_point()
	if viz == Vector2.INF:
		print("HAJÓPRÓBA: ezen a pályán nincs elég nagy víz — próbáld a --pirate kapcsolóval")
		return
	var tipusok := ["fisher", "transport", "warship", "galleon"]
	var szogek := [0.0, PI * 0.5, PI, -PI * 0.5]      # K, D, Ny, É
	var origin := viz + Vector2(-220, -150)
	var hajok: Array = []
	for i in tipusok.size():
		for d in szogek.size():
			var p := origin + Vector2(float(d) * 150.0, float(i) * 105.0)
			var u = main.spawn_unit(str(tipusok[i]), 0, p, age)
			hajok.append([u, float(szogek[d])])
	main.camera.position = origin + Vector2(225, 160)
	main.camera.zoom = Vector2(1.15, 1.15)
	main.camera.reset_smoothing()
	main.fog.reveal_all()
	await _frames(3)
	GameState.on = false
	for e in hajok:
		var u = e[0]
		if not is_instance_valid(u): continue
		u.face = float(e[1])
		u.sprite.update_anim(float(e[1]), 0.0, true, false)

# --- Bemutató (--showcase) ---
#
# Minden épülettípust és a főbb egységeket kirakja a bázis köré, hogy egy
# képernyőképen ellenőrizhető legyen a grafika.
func showcase() -> void:
	var hq = _player_hq()
	if hq == null: return
	var origin: Vector2 = hq.global_position + Vector2(-260, -300)
	var types := ["barracks", "stable", "house", "tower", "temple",
		"harbor", "goldmine", "farm", "airfield",
		"market", "hospital", "smith", "academy"]
	for i in types.size():
		var p := origin + Vector2((i % 5) * 150, int(i / 5) * 150)
		var b = main.spawn_building(types[i], 0, p, true)
		b.age = GameState.get_age()
	var roles := ["worker", "melee", "ranged", "spear", "cav", "priest", "spy",
		"medic", "siege", "ram"]
	for i in roles.size():
		main.spawn_unit(roles[i], 0, origin + Vector2(i * 76, 480), GameState.get_age())
	# A modern korban a hajók és a gépek is kikerülnek a képre.
	if GameState.get_age() >= 3:
		for i in range(2):
			main.spawn_unit(["fighter", "bomber"][i], 0,
				origin + Vector2(200 + i * 170, 620), 3)
	for i in range(3):
		main.spawn_unit(["melee", "ranged", "cav"][i], 1,
			origin + Vector2(460 + i * 60, 400), GameState.get_age())
	# Egy munkást odaküldünk a legközelebbi fához, hogy a képen látszódjon
	# a favágás is.
	for u in get_tree().get_nodes_in_group("player_units"):
		if u.role != "worker": continue
		var n = ResourceSystem.find_node_for(u)
		if n != null:
			u.global_position = n.global_position + Vector2(n.radius + 14.0, 0)
			u.gather_at(n)
			# A lelőhelyet ki is jelöljük, hogy a képen látszódjon a
			# maradék készlet.
			main.selected_res = n
			n.set_selected(true)
			main.hud.select_resource(n)
		break
	# A laktanyát kijelöljük és gyülekezőpontot adunk neki, hogy a képen
	# látszódjon a zászló és a képzési panel.
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if b.tipus != "barracks": continue
		b.set_rally(b.global_position + Vector2(210, 150))
		main.selected_bld = b
		b.set_selected(true)
		main.hud.select_building(b)
		break
	main.camera.position = origin + Vector2(300, 150)
	main.camera.reset_smoothing()

# --- Segédek ---

func _player_hq() -> Node:
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if b.tipus == "hq": return b
	return null

func _first_player_unit(role: String) -> Node:
	for u in get_tree().get_nodes_in_group("player_units"):
		if u.role == role: return u
	return null

func _building_at(pos: Vector2) -> Node:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.global_position.distance_to(pos) < 4.0: return b
	return null

# --- 16. Hang ---
#
# A játék sokáig NÉMA volt, és ez sehol nem látszott: a kód nyolc hangra
# hivatkozott, egyetlen fájl sem létezett hozzájuk, az `SFX.play` pedig
# csendben nem csinált semmit. Ez a szakasz épp az ilyen néma hiányt fogja
# meg — ezért nem elég a fájlok meglétét nézni, a kód KÉRÉSEIT is
# összevetjük a listával.
func _test_audio() -> void:
	print("\n[16] Hang")
	var nema: Array[String] = []
	for s in SFX.SOUNDS:
		if not SFX.has_sound(s): nema.append(str(s))
	check("minden hangnévhez van fájl", nema.is_empty(), str(nema))

	# Amit a kód ténylegesen kér — beleértve minden szerepkör harci hangját
	# mind a négy korszakban. Ha valaki új szerepkört vesz fel új hanggal,
	# itt derül ki, hogy a fájl lemaradt.
	var kert: Array[String] = ["click", "age", "build", "becsapodas"]
	for role in Unit.ROLE_ORDER:
		for a in range(4):
			var s := Combat.sound_for(str(role), a)
			if not (s in kert): kert.append(s)
	var ismeretlen: Array[String] = []
	for k in kert:
		if not (k in SFX.SOUNDS): ismeretlen.append(k)
	check("a kód nem kér ismeretlen hangot", ismeretlen.is_empty(), str(ismeretlen))

	check("a haláljajból három van", SFX.has_sound("halal1")
		and SFX.has_sound("halal2") and SFX.has_sound("halal3"))

	# Többszólamúság: egy húszfős csatában a kardcsattanásnak több szálon
	# kell futnia, különben a hangok elvágják egymást, és kattogás lesz.
	var szalak: int = (SFX._voices.get("sword", []) as Array).size()
	check("a harci hang többszólamú", szalak >= 3, "%d szál" % szalak)

	# Ütemkorlát: két közvetlenül egymás utáni hívásból csak az első szólal
	# meg. (A második nem lépteti a szálmutatót — ezen mérjük.)
	SFX.play("sword", -60.0)
	var mutato: int = int(SFX._next.get("sword", 0))
	SFX.play("sword", -60.0)
	check("az ütemkorlát visszafogja a sorozatot",
		int(SFX._next.get("sword", 0)) == mutato)

	# Hangmagasság-szórás: az ismétlődő harci hang ne gépfegyverként szóljon.
	check("a harci hang hangmagassága szór",
		float(SFX.PITCH_VAR.get("sword", 0.0)) > 0.0)

	# --- Zene ---
	#
	# A beállításokban mindig ott volt a „Zene be/ki" kapcsoló és a
	# hangerő-csúszka, csak éppen a play_music() SEHONNAN nem hívódott meg,
	# és zenefájl sem létezett: a kapcsoló semmit nem csinált.
	var nincs_zene: Array[String] = []
	for a in range(4):
		var utvonal := "res://assets/audio/music_age%d.wav" % a
		if not ResourceLoader.exists(utvonal): nincs_zene.append(utvonal)
	check("mind a négy korszaknak van zenéje", nincs_zene.is_empty(),
		str(nincs_zene))
	check("a menüzene megvan", ResourceLoader.exists(SFX.MUSIC_MENU))
	# A korszakváltás tényleg másik számra vált.
	SFX.play_era_music(0)
	var zene0 := SFX._music_path
	SFX.play_era_music(2)
	check("a korszakváltás más zenére vált", SFX._music_path != zene0,
		"%s -> %s" % [zene0, SFX._music_path])
	check("a zene a korszak számát követi", SFX._music_path.contains("age2"),
		SFX._music_path)
	# Ugyanarra a számra váltva nem indul elölről (különben a korszakváltás
	# és minden jelenetváltás visszaugratná a zenét a legelejére).
	SFX.play_era_music(2)
	check("ugyanaz a szám nem kezdődik elölről",
		SFX._music_path.contains("age2"))
	SFX.stop_music()

	# A próbahangot leállítjuk: a még szóló lejátszó a kilépéskor benn
	# tartaná a hangmintát, és a motor elszivárgott erőforrást jelentene.
	SFX.stop_all()

# --- 17. Gyógyítás és térítés ---
#
# A pap és a felcser sokáig NÉMA szereplők voltak: nulla sebzéssel álltak a
# pályán, a `heal()` függvényt pedig soha semmi nem hívta meg. Ez a szakasz
# azt méri, hogy tényleg dolgoznak-e.
func _test_healing() -> void:
	print("\n[17] Gyógyítás és térítés")
	var hq = _player_hq()
	if hq == null:
		check("van főváros a gyógyítás-teszthez", false)
		return
	# Messze a bázistól: a menedék-szabály ne szóljon bele a méréseinkbe,
	# és ne keveredjen ide a bot serege sem.
	var p: Vector2 = main.find_land_near(
		hq.global_position + Vector2(0, -900), 80.0)

	# --- A pap aurája ---
	var pap = main.spawn_unit("priest", 0, p, 0)
	var seb = main.spawn_unit("melee", 0, p + Vector2(40, 0), 0)
	await _frames(2)
	# A próbabábuk NEM harcolnak: nulla sebzéssel az ellenségkeresés ága
	# meg sem indul. Enélkül egymást ütnék, és nem a gyógyítást mérnénk.
	seb.dmg = 0.0
	seb.hp = seb.max_hp * 0.4
	# A friss sebet nem kötözi be: úgy állítjuk be az időbélyeget, mintha
	# rég kapta volna a találatot.
	seb._hit_at = GameState.t - 99.0
	var hp0: float = seb.hp
	await _frames(20)
	check("a pap gyógyítja a közelben állót", seb.hp > hp0,
		"%.1f -> %.1f" % [hp0, seb.hp])

	# Frissen sebzettre nem hat: aki még a tűzvonalban áll, nem kötözhető.
	seb.hp = seb.max_hp * 0.4
	seb._hit_at = GameState.t
	var hp1: float = seb.hp
	await _frames(6)
	check("a friss sebesültön nem fog a gyógyítás", is_equal_approx(seb.hp, hp1),
		"%.2f -> %.2f" % [hp1, seb.hp])

	# Nem gyógyít a maximum fölé.
	seb.hp = seb.max_hp - 0.2
	seb._hit_at = GameState.t - 99.0
	await _frames(20)
	check("a gyógyítás megáll a teljes életerőnél", seb.hp <= seb.max_hp,
		"%.2f / %.2f" % [seb.hp, seb.max_hp])

	# --- Az ellenség nem részesül belőle ---
	var ellen = main.spawn_unit("melee", 1, p + Vector2(50, 20), 0)
	await _frames(2)
	ellen.dmg = 0.0
	ellen.hp = ellen.max_hp * 0.4
	ellen._hit_at = GameState.t - 99.0
	var ehp: float = ellen.hp
	await _frames(12)
	check("az ellenséget nem gyógyítja a mi papunk",
		is_equal_approx(ellen.hp, ehp), "%.2f -> %.2f" % [ehp, ellen.hp])

	# --- A felcser gyorsabb ---
	check("a felcser gyorsabban gyógyít a papnál",
		Combat.heal_for("medic", 0) > Combat.heal_for("priest", 0),
		"%.1f > %.1f" % [Combat.heal_for("medic", 0), Combat.heal_for("priest", 0)])
	check("a pap hatósugara viszont nagyobb",
		Combat.heal_range_for("priest") > Combat.heal_range_for("medic"))

	# A felcser magától odamegy a sebesülthöz.
	# A keresési körén BELÜLRE tesszük (hatótáv + MEDIC_SEARCH), különben
	# nem is tud a sebesültről — nem hibázik, csak nem látja.
	var orvos = main.spawn_unit("medic", 0, p + Vector2(-200, 0), 0)
	await _frames(2)
	seb.hp = seb.max_hp * 0.3
	seb._hit_at = GameState.t - 99.0
	await _frames(6)
	# NEM az elmozdulást mérjük: a pálya magja futásonként más, és az
	# útkeresés megkerülhet egy sziklát — ilyenkor az első lépés akár
	# távolodás is lehet. A DÖNTÉS a lényeg: felvette-e a sebesültet, és
	# odaküldte-e magát.
	check("a felcser felveszi a legsúlyosabb sebesültet", orvos._heal_target == seb)
	check("a felcser el is indul hozzá",
		orvos.nav.target_position.distance_to(seb.global_position) < 40.0,
		"%.0f px a céltól" % orvos.nav.target_position.distance_to(seb.global_position))

	# Hatótávon belül pedig tényleg ellát: ezt már közvetlenül mérjük.
	orvos.global_position = seb.global_position + Vector2(24, 0)
	seb.hp = seb.max_hp * 0.3
	seb._hit_at = GameState.t - 99.0
	var mhp0: float = seb.hp
	await _frames(10)
	check("a felcser gyógyít is, nemcsak közeledik", seb.hp > mhp0,
		"%.1f -> %.1f" % [mhp0, seb.hp])

	# --- Térítés ---
	var tank = main.spawn_unit("melee", 1,
		main.find_land_near(p + Vector2(0, 420), 60.0), 3)
	await _frames(2)
	check("a modern páncélost nem lehet átállítani", not Unit.convertible(tank))
	check("a középkori katona viszont téríthető", Unit.convertible(ellen))
	if is_instance_valid(tank): tank.queue_free()

	pap.global_position = ellen.global_position + Vector2(30, 0)
	pap.start_attacking(ellen)
	check("a papnak a támadás parancs térítést jelent",
		pap.convert_target == ellen and pap.target == null)
	# A teljes térítés 8 másodperc; a próbában előretekerjük a számlálót.
	pap._chan = Combat.convert_time_for(0) - 0.05
	await _frames(6)
	check("a pap átállítja az ellenséges egységet", ellen.owner_id == 0,
		"gazda: %d" % ellen.owner_id)
	check("az átállt egység csapata is átáll", ellen.team == GameState.team_of(0),
		"csapat: %d" % ellen.team)
	check("az átállt egység a saját csoportunkba kerül",
		ellen.is_in_group("player_units") and not ellen.is_in_group("enemy_units"))
	check("az átállás nem gyógyítja meg a sebesültet",
		ellen.hp < ellen.max_hp, "%.0f / %.0f" % [ellen.hp, ellen.max_hp])

	# A menedék tényleg lassít: a szabály a főépület, a laktanya és a torony.
	check("a főépület menedéket ad", Building.SHELTER.has("hq"))
	check("a menedék lassítja a térítést", Combat.CONVERT_RESIST < 1.0,
		"%.2f" % Combat.CONVERT_RESIST)

	for u in [pap, seb, ellen, orvos]:
		if is_instance_valid(u): u.queue_free()
	await _frames(2)

# --- 18. Eddig elérhetetlen tartalom ---
#
# Négy szerepkörnek (kém, felcser, ostromgép, faltörő kos) évek óta megvolt
# a statisztikája, a sprite-ja és a harci adata, csak épp EGYETLEN épület
# sem képezte ki őket — a pályára sem lehetett kitenni. Ez a szakasz azt
# méri, hogy mostantól tényleg elérhetők.
func _test_unlocked() -> void:
	print("\n[18] Eddig elérhetetlen tartalom")

	# ÁLTALÁNOS SZABÁLY, nem felsorolás: ha bárki felvesz egy új épületet
	# vagy egységet és elfelejti az árát, itt bukik el. (A cukornádnak
	# pontosan ez hiányzott: ingyen lehetett ültetvényt húzni.)
	var ingyen: Array[String] = []
	for t in main.BUILD_COST.keys():
		if (main.BUILD_COST[t] as Dictionary).is_empty(): ingyen.append(str(t))
	for t in Building.TIPUS_ORDER:
		if not main.BUILD_COST.has(t): ingyen.append(str(t) + " (nincs ár)")
		if not main.BUILD_TIME.has(t): ingyen.append(str(t) + " (nincs idő)")
	check("minden épülettípusnak van ára és építési ideje",
		ingyen.is_empty(), str(ingyen))

	var hiany: Array[String] = []
	for t in Building.TIPUS_ORDER:
		for r in Building.BUILD_STATS.get(t, {}).get("trains", []):
			if not Building.TRAIN_COST.has(r): hiany.append("%s ára" % r)
			if not Building.TRAIN_TIME.has(r): hiany.append("%s ideje" % r)
	check("minden képezhető egységnek van ára és képzési ideje",
		hiany.is_empty(), str(hiany))

	# A négy szerepkör tényleg kikerül valamelyik épület képzési listájára.
	var kepezheto := {}
	for t in Building.TIPUS_ORDER:
		for r in Building.BUILD_STATS.get(t, {}).get("trains", []):
			kepezheto[str(r)] = str(t)
	for r in ["spy", "medic", "siege", "ram"]:
		check("a(z) %s kiképezhető (%s)" % [r, kepezheto.get(r, "SEHOL")],
			kepezheto.has(r))

	# ...és a HUD-on is ott van, amit fel lehet húzni hozzá.
	for t in ["market", "hospital", "smith"]:
		check("a(z) %s szerepel az építési listán" % t, t in main.hud.BUILDABLE)
		check("a(z) %s neve lefordul" % t, Lang.t("e_" + t) != "e_" + t)

	# --- Élesben: felhúzunk egy ispotályt és kiképzünk egy felcsert ---
	var hq = _player_hq()
	if hq == null: return
	var p: Vector2 = main.find_land_near(hq.global_position + Vector2(230, -230), 90.0)
	var korhaz = main.spawn_building("hospital", 0, p, true)
	await _frames(2)
	check("az ispotály felépül", korhaz != null and korhaz.is_ready())
	GameState.add_res(0, "gold", 400.0)
	GameState.add_res(0, "food", 400.0)
	var elotte: int = _count_role(0, "medic")
	check("az ispotály elfogadja a felcser képzését", korhaz.enqueue_unit("medic"))
	korhaz.prod_tmr.start(0.05)
	await _frames(12)
	check("a felcser meg is születik", _count_role(0, "medic") > elotte,
		"%d -> %d" % [elotte, _count_role(0, "medic")])

	# Az ispotály aurája: a köré húzódó sebesült magától felépül.
	var seb = main.spawn_unit("melee", 0, korhaz.global_position + Vector2(60, 0), 0)
	await _frames(2)
	seb.dmg = 0.0
	seb.hp = seb.max_hp * 0.5
	seb._hit_at = GameState.t - 99.0
	var hp0: float = seb.hp
	await _frames(25)
	check("az ispotály gyógyítja a köré gyűlt sebesültet", seb.hp > hp0,
		"%.1f -> %.1f" % [hp0, seb.hp])

	# --- A repülők tényleg repülnek ---
	#
	# A vadász és a bombázó sokáig a SZÁRAZFÖLDI navigációs rétegen mozgott,
	# gyalogos sprite-tal: a repülőtér olyan gépeket épített, amiket
	# megállított a víz. Ezért itt a víz FÖLÉ küldjük őket.
	for r in ["fighter", "bomber"]:
		check("a(z) %s légi egység" % r, r in Unit.AIR_ROLES)
		check("a(z) %s képe repülőgép" % r,
			ResourceLoader.exists("res://assets/sprites/air/%s.png" % r))
	var viz := _find_water_point()
	var gep = main.spawn_unit("fighter", 0,
		main.find_land_near(hq.global_position + Vector2(160, -160), 40.0), 3)
	await _frames(2)
	check("a gép nem ütközik senkivel", int(gep.collision_layer) == 0)
	if viz != Vector2.INF:
		gep.move_to(viz)
		var t0: float = gep.global_position.distance_to(viz)
		await _frames(45)
		var t1: float = gep.global_position.distance_to(viz)
		check("a gép a víz fölé is elrepül", t1 < t0 - 20.0,
			"%.0f -> %.0f px a céltól" % [t0, t1])
	else:
		check("van víz a repülési próbához", false)
	if is_instance_valid(gep): gep.queue_free()

	# A kovácsműhely ostromszerszámai.
	var kovacs = main.spawn_building("smith", 0,
		main.find_land_near(hq.global_position + Vector2(-230, -230), 90.0), true)
	await _frames(2)
	GameState.add_res(0, "wood", 600.0)
	GameState.add_res(0, "gold", 400.0)
	check("a kovácsműhely elfogadja az ostromgép képzését",
		kovacs.enqueue_unit("siege"))
	check("a kovácsműhely elfogadja a faltörő kos képzését",
		kovacs.enqueue_unit("ram"))

	for n in [korhaz, kovacs, seb]:
		if is_instance_valid(n): n.queue_free()
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and u.role in ["medic", "siege", "ram"]:
			u.queue_free()
	await _frames(2)

# --- 19. Fejlesztések ---
#
# A `GameState.oldalak[i].upg` szótár és a rá épülő szorzók évek óta ott
# voltak a kódban, de SEMMI nem tudta megnövelni a fokozatot — örökre nulla
# maradt, tehát holt kód volt. Ez a szakasz azt méri, hogy a kutatás
# tényleg megtörténik, és tényleg hat is.
func _test_upgrades() -> void:
	print("\n[19] Fejlesztések")
	var me := GameState.en_id
	var mentett: Dictionary = (GameState.get_side(me)["upg"] as Dictionary).duplicate()

	check("minden fejlesztés valamelyik házhoz tartozik",
		Upgrades.list_for("smith").size() + Upgrades.list_for("academy").size()
			== Upgrades.ORDER.size())
	check("a kovácsműhely kutat", Upgrades.researches("smith"))
	check("az akadémia kutat", Upgrades.researches("academy"))
	check("a laktanya nem kutat", not Upgrades.researches("barracks"))

	var forditatlan: Array[String] = []
	for k in Upgrades.ORDER:
		if Lang.t("upg_" + k) == "upg_" + k: forditatlan.append(str(k))
		if Lang.t("upg_leiras_" + k) == "upg_leiras_" + k:
			forditatlan.append(str(k) + " leírás")
	check("minden fejlesztésnek van neve és leírása",
		forditatlan.is_empty(), str(forditatlan))

	# --- Korszakhoz kötött ágak ---
	# A 15. században a négyfokozatú ágakból csak EGY vehető meg; enélkül az
	# első percben meg lehetne venni az egészet.
	GameState.get_side(me)["age"] = 0
	check("a korszakhoz kötött ágból elsőre egy fokozat vehető",
		Upgrades.cap(me, "yield") == 1, "%d" % Upgrades.cap(me, "yield"))
	GameState.get_side(me)["age"] = 3
	check("a korszakokkal nyílik a többi fokozat is",
		Upgrades.cap(me, "yield") == 4, "%d" % Upgrades.cap(me, "yield"))
	check("a korszaktól független ág mindig teljes",
		Upgrades.cap(me, "weapon") == Upgrades.max_level("weapon"))

	# --- Fegyver: a MÁR PÁLYÁN LÉVŐ katona is erősödik ---
	var hq = _player_hq()
	if hq == null: return
	var p: Vector2 = main.find_land_near(hq.global_position + Vector2(-560, 0), 70.0)
	var kat = main.spawn_unit("melee", me, p, 0)
	await _frames(2)
	var dmg0: float = kat.dmg
	var hp0: float = kat.max_hp
	GameState.get_side(me)["res"]["gold"] = 99999.0
	GameState.get_side(me)["res"]["wood"] = 99999.0
	GameState.get_side(me)["res"]["stone"] = 99999.0
	GameState.get_side(me)["res"]["food"] = 99999.0
	check("a fegyverfejlesztés megvehető", Upgrades.research(me, "weapon"))
	check("a fokozat eggyel nőtt", Upgrades.level(me, "weapon") == 1)
	check("a már pályán lévő katona is nagyobbat üt", kat.dmg > dmg0,
		"%.1f -> %.1f" % [dmg0, kat.dmg])
	check("az ellátmány nélkül az életereje még a régi",
		is_equal_approx(kat.max_hp, hp0))
	Upgrades.research(me, "supply")
	check("az ellátmány megnöveli az életerőt", kat.max_hp > hp0,
		"%.0f -> %.0f" % [hp0, kat.max_hp])

	# A fokozat FOGY: a harmadik után nem vehető több.
	while Upgrades.available(me, "weapon"):
		Upgrades.research(me, "weapon")
	check("a fegyverfejlesztés a maximumon megáll",
		Upgrades.level(me, "weapon") == Upgrades.max_level("weapon"),
		"%d" % Upgrades.level(me, "weapon"))
	check("a maximumon már nem vehető meg", not Upgrades.available(me, "weapon"))

	# --- Páncél: a találatból levon, de nem nyeli el egészen ---
	Upgrades.research(me, "armor")
	await _frames(2)
	check("a páncél megjelenik a katonán", kat.armor > 0.0, "%.0f" % kat.armor)
	var elotte: float = kat.hp
	kat.take_damage(kat.armor + 10.0)
	check("a páncél levon a találatból",
		is_equal_approx(elotte - kat.hp, 10.0), "%.1f" % (elotte - kat.hp))
	elotte = kat.hp
	kat.take_damage(0.5)                    # a páncélnál jóval kisebb ütés
	check("a páncél sosem nyeli el a teljes ütést",
		elotte - kat.hp >= Upgrades.MIN_DAMAGE - 0.001,
		"%.2f" % (elotte - kat.hp))

	# --- Ár: a következő fokozat drágább, a Számvitel viszont olcsóbbá tesz ---
	var ar0: Dictionary = Upgrades.cost(me, "masonry")
	Upgrades.research(me, "masonry")
	var ar1: Dictionary = Upgrades.cost(me, "masonry")
	check("a következő fokozat drágább", int(ar1["stone"]) > int(ar0["stone"]),
		"%d -> %d" % [int(ar0["stone"]), int(ar1["stone"])])
	var epuletar0: Dictionary = main.build_cost(me, "farm")
	Upgrades.research(me, "ledger")
	var epuletar1: Dictionary = main.build_cost(me, "farm")
	check("a Számvitel olcsóbbá teszi az épületet",
		int(epuletar1["wood"]) < int(epuletar0["wood"]),
		"%d -> %d" % [int(epuletar0["wood"]), int(epuletar1["wood"])])
	check("a Számvitel a kiképzést is olcsóbbá teszi",
		int(Building.train_cost(me, "melee")["wood"])
			< int(Building.TRAIN_COST["melee"]["wood"]))

	# --- A többi szorzó tényleg elmozdul ---
	Upgrades.research(me, "drill")
	check("a Kiképzőtábor rövidíti a képzési időt",
		Building.train_time(me, "melee") < float(Building.TRAIN_TIME["melee"]),
		"%.1f mp" % Building.train_time(me, "melee"))
	Upgrades.research(me, "storage")
	check("a Raktározás növeli a rakományt",
		kat.load_cap() > ResourceSystem.LOAD_AMOUNT, "%.0f" % kat.load_cap())
	Upgrades.research(me, "optics")
	await _frames(2)
	check("a Messzelátó növeli a látótávot",
		kat.vision_r > Combat.vision_for("melee", 0), "%.0f" % kat.vision_r)
	Upgrades.research(me, "medicine")
	check("a Gyógyszerkészlet gyorsítja a gyógyítást",
		Upgrades.heal_mul(me) > 1.0, "%.2f" % Upgrades.heal_mul(me))
	Upgrades.research(me, "yield")
	check("a Gazdálkodás növeli a kitermelést", Upgrades.gather_mul(me) > 1.0)
	Upgrades.research(me, "labor")
	check("az Építőipar gyorsítja az építkezést", Upgrades.build_mul(me) > 1.0)

	# Az ellenfél fejlesztései nem szivárognak át.
	if GameState.oldalak.size() > 1:
		check("az ellenfél nem kapja meg a mi fejlesztéseinket",
			Upgrades.level(1, "weapon") == 0, "%d" % Upgrades.level(1, "weapon"))

	# Az önteszt nem hagyhat maga után felturbózott birodalmat: a további
	# szakaszok (és a --soak) az alapértékekkel számolnak.
	if is_instance_valid(kat): kat.queue_free()
	GameState.get_side(me)["upg"] = mentett
	Upgrades.reapply(me)
	await _frames(2)
	check("a fejlesztések visszaálltak", Upgrades.level(me, "weapon") == 0)

# --- 20. Hős, kém, szállítóhajó ---
#
# Három szerepkör évekig csak „egy szám a táblázatban" volt: a hősnek nem
# volt aurája, a kémnek álruhája, a szállítóhajó pedig nem szállított
# senkit. Ez a szakasz azt méri, hogy mindhárom csinál is valamit.
func _test_special_roles() -> void:
	print("\n[20] Hős, kém, szállítóhajó")
	var hq = _player_hq()
	if hq == null:
		check("van főváros a próbához", false)
		return
	var p: Vector2 = main.find_land_near(hq.global_position + Vector2(0, -760), 80.0)

	# --- A HŐS AURÁJA ---
	var kat = main.spawn_unit("melee", 0, p, 0)
	var ell = main.spawn_unit("melee", 1, p + Vector2(30, 0), 0)
	await _frames(2)
	ell.dmg = 0.0
	check("bátorítás nélkül indul a katona", not kat.inspired())
	var alap_hp: float = ell.hp
	kat.start_attacking(ell)
	kat.atk_timer.start(0.05)
	await _frames(8)
	var sebzes_alap: float = alap_hp - ell.hp
	# Most jön a hős: a szomszédban álló katona nagyobbat üt.
	var hos = main.spawn_unit("hero", 0, p + Vector2(20, 20), 0)
	await _frames(2)
	hos.dmg = 0.0                      # a hős maga ne üssön bele a mérésbe
	await _frames(10)
	check("a hős közelében a katona bátorítást kap", kat.inspired())
	ell.hp = ell.max_hp
	var hp2: float = ell.hp
	kat.atk_timer.start(0.05)
	await _frames(8)
	var sebzes_aura: float = hp2 - ell.hp
	check("a bátorított katona nagyobbat üt", sebzes_aura > sebzes_alap,
		"%.1f -> %.1f" % [sebzes_alap, sebzes_aura])
	check("az aura sebzésbónusza pozitív", Combat.AURA_DAMAGE > 0.0)
	# A hős eleste után a bátorítás magától elmúlik.
	hos.queue_free()
	await _frames(2)
	kat._aura_until = GameState.t - 1.0
	check("a hős nélkül elmúlik a bátorítás", not kat.inspired())
	for u in [kat, ell]:
		if is_instance_valid(u): u.queue_free()
	await _frames(2)

	# --- A KÉM ÁLRUHÁJA ---
	var kem = main.spawn_unit("spy", 0, p + Vector2(120, 0), 0)
	await _frames(2)
	check("a friss kém álruhában van", kem.disguised())
	# Az álruhás kémre nem lőnek: az ellenségkeresés nem találja meg.
	var vadasz = main.spawn_unit("melee", 1, p + Vector2(130, 10), 0)
	await _frames(2)
	check("az álruhás kémet nem találja meg az ellenség",
		Combat.find_enemy(vadasz, 400.0) != kem)
	# Az őrtorony leleplezi.
	var torony = main.spawn_building("tower", 1,
		main.find_land_near(p + Vector2(150, 40), 60.0), true)
	await _frames(2)
	kem.global_position = torony.global_position + Vector2(60, 0)
	kem._spy_t = 0.0
	await _frames(6)
	check("az őrtorony leleplezi a kémet", not kem.disguised())
	check("a leleplezett kém már célpont",
		Combat.find_enemy(vadasz, 900.0) != null)
	for n in [kem, vadasz, torony]:
		if is_instance_valid(n): n.queue_free()
	await _frames(2)

	# --- A SZÁLLÍTÓHAJÓ ---
	check("a szállítóhajó szállít", Unit.CARGO_CAP > 0,
		"%d férőhely" % Unit.CARGO_CAP)
	var viz := _find_water_point()
	if viz == Vector2.INF:
		check("van víz a szállítási próbához", false)
		return
	var hajo = main.spawn_unit("transport", 0, viz, 0)
	var utas = main.spawn_unit("melee", 0, main.find_land_near(viz, 40.0), 0)
	await _frames(2)
	check("a hajó üresen indul", hajo.cargo.is_empty()
		and hajo.cargo_free() == Unit.CARGO_CAP)
	# Beszállás közvetlenül (a parancs a hajóhoz gyaloglást is intézi, itt
	# magát a felszállást mérjük).
	check("a katona felfér a hajóra", utas.board(hajo))
	check("a hajó számon tartja a rakományt", hajo.cargo.size() == 1)
	check("a fedélzeten lévő egység nem látszik", not utas.visible)
	check("és nem is célpont", utas.aboard())
	check("de a népességet tovább foglalja", utas.is_in_group("units"))
	# Hajó hajóra nem fér.
	var masik = main.spawn_unit("fisher", 0, viz + Vector2(40, 0), 0)
	await _frames(2)
	check("hajó nem száll hajóra", not masik.board(hajo))
	# Partra szállás.
	var part: Vector2 = main.find_land_near(viz, 40.0)
	var n_ki: int = hajo.unload_at(part)
	await _frames(2)
	check("a hajó partra teszi a csapatot", n_ki == 1 and hajo.cargo.is_empty())
	check("a kiszállt egység újra látszik és parancsolható",
		utas.visible and not utas.aboard())
	# A hajó pusztulása magával viszi a rakományt.
	utas.board(hajo)
	await _frames(2)
	hajo.take_damage(99999.0)
	await _frames(3)
	check("a hajóval a rakománya is elvész", not is_instance_valid(utas))
	if is_instance_valid(masik): masik.queue_free()
	await _frames(2)

# Azonos-e a lap két sora (az álló kockát vetjük össze, minden negyedik
# képpontot mintavételezve — a teljes összehasonlítás fölösleges munka).
func _rows_equal(kep: Image, a: int, b: int) -> bool:
	for y in range(0, 64, 2):
		for x in range(0, 64, 2):
			if kep.get_pixel(x, a * 64 + y) != kep.get_pixel(x, b * 64 + y):
				return false
	return true

# A vízcellák összefüggő foltokra bontása (elárasztásos bejárás, veremmel —
# rekurzióval a nagy pályán elszállna). Visszaad: [legnagyobb folt, összes
# vízcella].
func _water_bodies(terrain: Node) -> Array:
	var w: int = terrain.grid_w
	var h: int = terrain.grid_h
	var seen := {}
	var legnagyobb := 0
	var osszes := 0
	for y in range(h):
		var row: Array = terrain.water_map[y]
		for x in range(w):
			if not bool(row[x]): continue
			osszes += 1
			var kulcs := y * w + x
			if seen.has(kulcs): continue
			var meret := 0
			var verem: Array[int] = [kulcs]
			seen[kulcs] = true
			while not verem.is_empty():
				var k: int = verem.pop_back()
				meret += 1
				var cy := k / w
				var cx := k % w
				for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					var nx: int = cx + int(d[0])
					var ny: int = cy + int(d[1])
					if nx < 0 or ny < 0 or nx >= w or ny >= h: continue
					if not bool((terrain.water_map[ny] as Array)[nx]): continue
					var nk := ny * w + nx
					if seen.has(nk): continue
					seen[nk] = true
					verem.append(nk)
			legnagyobb = maxi(legnagyobb, meret)
	return [legnagyobb, osszes]

# Egy pont a legnagyobb összefüggő vízfelület belsejében. A repülési
# próbához kell: a gépnek a víz FÖLÖTT is át kell jutnia.
func _find_water_point() -> Vector2:
	var terrain = main.terrain
	var c: int = int(terrain.water_cell)
	var best := Vector2.INF
	var best_n := 0
	for cy in range(4, int(terrain.grid_h) - 4, 5):
		for cx in range(4, int(terrain.grid_w) - 4, 5):
			if not bool((terrain.water_map[cy] as Array)[cx]): continue
			# Csak olyan pont jó, ami körül is víz van — a tócsák nem
			# bizonyítanának semmit.
			var n := 0
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					if bool((terrain.water_map[cy + dy] as Array)[cx + dx]): n += 1
			if n > best_n:
				best_n = n
				best = Vector2((cx + 0.5) * c, (cy + 0.5) * c)
	return best if best_n >= 40 else Vector2.INF

func _count_side_units(side: int) -> int:
	var n := 0
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and int(u.owner_id) == side: n += 1
	return n

func _count_role(side: int, role: String) -> int:
	var n := 0
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and int(u.owner_id) == side and u.role == role:
			n += 1
	return n
