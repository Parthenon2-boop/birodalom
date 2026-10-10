extends Node

# ELŐZETES-FELVEVŐ. Nem része a játéknak (a `scripts/dev` mappa nem kerül a
# kiadásba): a honlap előzetes videójának jeleneteit rendezi meg.
#
#   godot --path . --write-movie ki.avi --fixed-fps 30 --resolution 1280x720 \
#       --quit-after 420 -- --skip-menu --lang=hu --detail=2 --reveal \
#       --age=0 --nemzet=hu --ellenfel=at --felvetel=ostrom
#
# Egy jelenet = egy futás. A felvevő seregeket és épületeket rak le, a gépi
# katonák maguktól harcolnak (ugyanazzal a kóddal, mint a játékban), a
# kamerát pedig kulcskockák között vezeti. A felvételt a Godot beépített
# `--write-movie` módja készíti; a jelenetek összevágása a Blender dolga.
#
# Jelenetek: nyitany, ostrom, mezo, tenger, ejszaka, modern
# A korszakot, a tájat, a napszakot és a nemzeteket a szokásos kapcsolók
# adják: --age, --map, --seed, --tod, --reveal, --pirate, --nemzet, --ellenfel.

var main: Node = null
var jelenet: String = ""

var _t: float = 0.0
# Kamerapálya: [idő (mp), hely, nagyítás] — a kockák között lágyan úszik.
var _kam: Array = []
# Időzített lépések: [idő (mp), Callable]
var _lepesek: Array = []
# Akiket a kamera követ (a súlypontjukat); üresen a pálya számít.
var _kovet: Array = []
var _kovet_eltol: Vector2 = Vector2.ZERO
var _kovet_zoom: Array = []          # [idő, nagyítás] párok

var _ki_mappa: String = ""
var _kocka: int = 0

func _init(m: Node = null) -> void:
	main = m

func _kocka_ment() -> void:
	var kep := get_viewport().get_texture().get_image()
	kep.convert(Image.FORMAT_RGB8)
	kep.save_jpg("%s/k%05d.jpg" % [_ki_mappa, _kocka], 0.93)
	_kocka += 1

func indit(nev: String) -> void:
	jelenet = nev
	# A kép mindig 1280×720-ban készüljön, akkor is, ha az ablak nem fér ki a
	# kijelzőre (kis monitoron a Windows összenyomja): a gyökér-nézet a
	# felvétel méretében rajzol, az ablak csak kicsinyítve mutatja.
	var ablak := get_window()
	ablak.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	ablak.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	ablak.content_scale_size = Vector2i(1280, 720)
	# `--felvetel-ki=<mappa>`: a képkockákat magunk mentjük JPG-sorozatba.
	# (A Godot `--write-movie` módja ezzel a megjelenítővel fakó, kétszer
	# gamma-javított képet ad, ezért nem azt használjuk; az egyenletes
	# 30 kép/mp-et a `--fixed-fps 30` adja.)
	for a in Main.dev_args():
		if a.begins_with("--felvetel-ki="):
			_ki_mappa = a.substr(14)
			DirAccess.make_dir_recursive_absolute(_ki_mappa)
			RenderingServer.frame_post_draw.connect(_kocka_ment)
	# A kamerát mi vezetjük: az egér a képernyő szélén ne görgessen bele.
	main.camera.set_process(false)
	main.camera.position_smoothing_enabled = false
	# A felvétel ne hagyjon visszajátszás-fájlt a játékos mappájában.
	if main.replay != null and main.replay.recording:
		main.replay._frames = 0
		main.replay.stop_recording()
	# A gépi ellenfél hulláma ne vágjon bele a megrendezett jelenetbe, a
	# sorsolt események és az időjárás-váltás pedig ne írjon a képre.
	for i in range(1, GameState.oldalak.size()):
		GameState.get_side(i)["waveT"] = 99999.0
	if main.events != null: main.events.set_process(false)
	main.weather._t = 99999.0
	main.weather._sea_t = 99999.0
	# Bőven legyen nyersanyag: a felület ne pirosan mutassa a készletet.
	for k in ["wood", "stone", "gold", "food"]:
		GameState.add_res(0, k, 1500.0)
	await get_tree().process_frame
	match nev:
		"nyitany": _nyitany()
		"ostrom": _ostrom()
		"mezo": _mezo()
		"tenger": _tenger()
		"ejszaka": _ejszaka()
		"modern": _modern()
		_: print("[felvevo] ismeretlen jelenet: ", nev)
	print("[felvevo] jelenet: %s  kor: %d  táj: %s  mag: %d" % [nev,
		GameState.get_age(), GameState.map_type, GameState.sim_mag])

func _process(delta: float) -> void:
	_t += delta
	while not _lepesek.is_empty() and float(_lepesek[0][0]) <= _t:
		var l: Array = _lepesek.pop_front()
		(l[1] as Callable).call()
	_kamera(delta)

# --- Kamera ---

func _kamera(delta: float) -> void:
	var cam: Camera2D = main.camera
	if not _kovet.is_empty():
		var kp := _sulypont(_kovet)
		if kp != Vector2.INF:
			var cel := kp + _kovet_eltol
			cam.position = cam.position.lerp(cel, minf(1.0, delta * 1.6))
		if not _kovet_zoom.is_empty():
			var z := _gorbe(_kovet_zoom)
			cam.zoom = Vector2(z, z)
	elif not _kam.is_empty():
		var a: Array = _kam[0]
		var b: Array = _kam[_kam.size() - 1]
		for i in range(_kam.size() - 1):
			if _t >= float(_kam[i][0]) and _t <= float(_kam[i + 1][0]):
				a = _kam[i]
				b = _kam[i + 1]
				break
		if _t <= float(_kam[0][0]): b = a
		elif _t >= float(b[0]): a = b
		var h := maxf(0.001, float(b[0]) - float(a[0]))
		var s := smoothstep(0.0, 1.0, clampf((_t - float(a[0])) / h, 0.0, 1.0))
		cam.position = (a[1] as Vector2).lerp(b[1] as Vector2, s)
		# A nagyítást mértani úton visszük át: így egyenletesnek látszik.
		var z := float(a[2]) * pow(float(b[2]) / float(a[2]), s)
		cam.zoom = Vector2(z, z)
	cam._clamp()
	cam._shake_tick(delta)

func _gorbe(pontok: Array) -> float:
	if _t <= float(pontok[0][0]): return float(pontok[0][1])
	for i in range(pontok.size() - 1):
		if _t <= float(pontok[i + 1][0]):
			var s := (_t - float(pontok[i][0])) / maxf(0.001, float(pontok[i + 1][0]) - float(pontok[i][0]))
			return lerpf(float(pontok[i][1]), float(pontok[i + 1][1]), smoothstep(0.0, 1.0, s))
	return float(pontok[pontok.size() - 1][1])

func _sulypont(lista: Array) -> Vector2:
	var s := Vector2.ZERO
	var n := 0
	for u in lista:
		if is_instance_valid(u):
			s += (u as Node2D).global_position
			n += 1
	return s / float(n) if n > 0 else Vector2.INF

func _kam_ide(pos: Vector2, zoom: float) -> void:
	main.camera.position = pos
	main.camera.zoom = Vector2(zoom, zoom)
	main.camera._clamp()

# --- Segédek ---

func _hq(oldal: int) -> Vector2:
	return main._hq_pos[clampi(oldal, 0, main._hq_pos.size() - 1)]

# Sereg sorokba rendezve: `szerepek` = [[szerep, darab], ...], soronként egy
# fegyvernem; az első sor néz az `irany` felé.
func _sereg(oldal: int, kozep: Vector2, irany: Vector2, szerepek: Array,
		age: int, koz: float = 30.0) -> Array:
	var ki: Array = []
	var elore := irany.normalized()
	var oldalra := Vector2(-elore.y, elore.x)
	for sor in szerepek.size():
		var szerep := str(szerepek[sor][0])
		var db := int(szerepek[sor][1])
		for i in db:
			var p := kozep - elore * (float(sor) * koz * 1.25) \
				+ oldalra * ((float(i) - float(db - 1) * 0.5) * koz)
			var viz: bool = szerep in Unit.NAVAL_ROLES
			var u: Node = main.spawn_unit(szerep, oldal,
				main.find_land_near(p, 14.0, viz), age)
			if u != null:
				u.face = elore.angle()
				ki.append(u)
	return ki

func _indul(lista: Array, cel: Vector2) -> void:
	for u in lista:
		if is_instance_valid(u): u.move_to(cel + Vector2(randf_range(-40, 40), randf_range(-40, 40)))

func _kijelol(lista: Array) -> void:
	var el: Array[Node] = []
	for u in lista:
		if is_instance_valid(u) and int(u.owner_id) == GameState.en_id:
			u.set_selected(true)
			el.append(u)
	main.selected_units = el
	main.hud.update_selection(el)

func _epit(tipus: String, oldal: int, kozel: Vector2) -> Node:
	var p: Vector2 = main.find_build_spot(tipus, kozel)
	if p == Vector2.INF: return null
	return main.spawn_building(tipus, oldal, p, true)

func _varos(oldal: int, tipusok: Array, sugar: float = 190.0, kezd: float = 0.0) -> Array:
	var ki: Array = []
	var hq := _hq(oldal)
	for i in tipusok.size():
		var a := kezd + TAU * float(i) / float(tipusok.size())
		var r := sugar + (70.0 if i % 2 == 1 else 0.0)
		var b := _epit(str(tipusok[i]), oldal, hq + Vector2(cos(a), sin(a) * 0.8) * r)
		if b != null: ki.append(b)
	return ki

# Elég szállás a megrendezett seregnek: a felületen a létszám ne lépje túl a
# keretet (házanként öt fő).
func _szallas(oldal: int, db: int) -> void:
	var hq := _hq(oldal)
	var hatra := (hq - _hq(1 - oldal)).normalized() if oldal < 2 else Vector2.DOWN
	for i in db:
		var a := hatra.angle() + (float(i) - float(db - 1) * 0.5) * 0.42
		_epit("house", oldal, hq + Vector2(cos(a), sin(a)) * (210.0 + 60.0 * float(i % 2)))

# Merre van egybefüggő szárazföld a ponttól? A kívánt irányhoz legközelebbit
# adja, amerre hossz távolságig nincs víz (tavas pályán különben a támadók
# a tó túlpartján ragadnak).
func _szabad_irany(kozep: Vector2, kivant: Vector2, hossz: float) -> Vector2:
	var legjobb := kivant.normalized()
	var pont := -1.0
	for i in 16:
		var ir := Vector2.RIGHT.rotated(TAU * float(i) / 16.0)
		var jo := true
		var d := 60.0
		while d <= hossz:
			if not main._ground_ok(kozep + ir * d, 20.0, false):
				jo = false
				break
			d += 40.0
		if not jo: continue
		var p := ir.dot(kivant.normalized()) + 2.0
		if p > pont:
			pont = p
			legjobb = ir
	return legjobb

func _munkasok_dolgoznak(oldal: int) -> void:
	for u in get_tree().get_nodes_in_group("units"):
		if int(u.owner_id) == oldal and u.role == "worker": u.auto_gather = true

func _idojaras(fajta: int, ero: float, sar: float = 0.0) -> void:
	main.weather.fajta = fajta
	main.weather.ero = ero
	main.weather._cel = ero
	main.weather.sar = sar

# --- 1. NYITÁNY: a térképről leereszkedünk egy élő városra ---
func _nyitany() -> void:
	var age := GameState.get_age()
	var hq := _hq(0)
	_varos(0, ["barracks", "house", "market", "temple", "house", "smith",
		"stable", "farm", "academy", "house", "tower", "farm", "hospital", "goldmine"], 185.0, 0.3)
	_varos(1, ["barracks", "house", "tower", "stable", "house", "farm"], 180.0)
	for i in 8:
		var a := TAU * float(i) / 8.0
		main.spawn_unit("worker", 0, main.find_land_near(hq + Vector2(cos(a), sin(a)) * 130.0, 14.0), age)
	_munkasok_dolgoznak(0)
	# Egy lovascsapat és egy gyalogos őrjárat vonul át a városon.
	var lovasok := _sereg(0, hq + Vector2(-330, 60), Vector2(1, 0), [["cav", 5]], age, 34.0)
	var gyalog := _sereg(0, hq + Vector2(60, 300), Vector2(0, -1), [["melee", 6], ["ranged", 6]], age)
	_lepesek.append([3.0, func() -> void:
		_indul(lovasok, hq + Vector2(360, 40))
		_indul(gyalog, hq + Vector2(40, -260))])
	var kozep := Vector2(GameState.WORLD_W, GameState.WORLD_H) * 0.5
	_kam = [[0.0, kozep.lerp(hq, 0.35), 0.42], [1.0, kozep.lerp(hq, 0.4), 0.44],
		[6.5, hq + Vector2(10, 10), 1.15], [12.0, hq + Vector2(60, -10), 1.3]]
	_kam_ide(_kam[0][1], 0.42)

# --- 2. OSTROM (középkor): a sereg megrohanja az ellenség megerősített városát ---
func _ostrom() -> void:
	var age := GameState.get_age()
	var ehq := _hq(1)
	var felol := _szabad_irany(ehq, _hq(0) - ehq, 640.0)
	var oldalra := Vector2(-felol.y, felol.x)
	_epit("tower", 1, ehq + felol * 190.0 + oldalra * 120.0)
	_epit("tower", 1, ehq + felol * 190.0 - oldalra * 120.0)
	_epit("barracks", 1, ehq - felol * 60.0 + oldalra * 190.0)
	_epit("house", 1, ehq - felol * 150.0 - oldalra * 120.0)
	_epit("house", 1, ehq - felol * 170.0 + oldalra * 40.0)
	var vedok := _sereg(1, ehq + felol * 150.0, felol,
		[["spear", 8], ["melee", 6], ["ranged", 8]], age)
	_szallas(0, 6)
	var start := main.find_land_near(ehq + felol * 560.0, 40.0) as Vector2
	var sereg := _sereg(0, start, -felol,
		[["cav", 7], ["melee", 9], ["spear", 7], ["ranged", 9], ["siege", 3], ["ram", 2], ["hero", 1]], age)
	_kijelol(sereg)
	_lepesek.append([0.6, func() -> void: _indul(sereg, ehq + felol * 120.0)])
	_lepesek.append([2.5, func() -> void: _indul(vedok, ehq + felol * 260.0)])
	_kovet = sereg
	_kovet_eltol = -felol * 120.0
	_kovet_zoom = [[0.0, 1.05], [5.0, 1.3], [14.0, 1.4]]
	_kam_ide(start - felol * 60.0, 1.05)

# --- 3. NYÍLT CSATA (kora újkor): két sorba állt had, ágyúkkal, esőben ---
func _mezo() -> void:
	var age := GameState.get_age()
	var a0 := _hq(0)
	var a1 := _hq(1)
	var kozep := main.find_land_near(a0.lerp(a1, 0.5), 120.0) as Vector2
	var ir := (a1 - a0).normalized()
	var mi := _sereg(0, main.find_land_near(kozep - ir * 270.0, 40.0), ir,
		[["melee", 10], ["ranged", 12], ["spear", 8], ["siege", 4], ["hero", 1]], age, 28.0)
	var ok := _sereg(1, main.find_land_near(kozep + ir * 270.0, 40.0), -ir,
		[["melee", 10], ["ranged", 11], ["spear", 8], ["siege", 3]], age, 28.0)
	var lovas := _sereg(0, main.find_land_near(kozep - ir * 330.0 + Vector2(-ir.y, ir.x) * 300.0, 40.0), ir,
		[["cav", 8]], age, 34.0)
	_szallas(0, 7)
	_kijelol(mi + lovas)
	_idojaras(main.weather.ESO, 0.85, 0.3)
	_lepesek.append([0.6, func() -> void:
		_indul(mi, kozep - ir * 40.0)
		_indul(ok, kozep + ir * 40.0)])
	_lepesek.append([4.0, func() -> void: _indul(lovas, kozep + ir * 220.0)])
	_kam = [[0.0, kozep - ir * 140.0, 1.0], [5.0, kozep, 1.25], [14.0, kozep + ir * 40.0, 1.45]]
	_kam_ide(_kam[0][1], 1.0)

# --- 4. TENGER (kalózvilág): a kikötő előtt két hajóhad sortüze alkonyatkor ---
func _tenger() -> void:
	var age := GameState.get_age()
	var hq := _hq(0)
	var viz := main.find_land_near(hq + Vector2(0, 240.0), 45.0, true) as Vector2
	# A nyílt víz felé nézünk: arra, amerre a bázistól távolodunk.
	var ki := (viz - hq).normalized()
	var oldalra := Vector2(-ki.y, ki.x)
	_varos(0, ["house", "sugar", "market", "house", "tower", "barracks"], 150.0, ki.angle() + 1.2)
	_epit("harbor", 0, hq + ki * 150.0)
	_sereg(0, hq + ki * 90.0, ki, [["melee", 5], ["ranged", 4]], age)
	_munkasok_dolgoznak(0)
	var mi: Array = []
	var ok: Array = []
	for i in 4:
		var szerep := "galleon" if i % 2 == 0 else "warship"
		var p := viz + oldalra * (float(i) - 1.5) * 125.0
		var u: Node = main.spawn_unit(szerep, 0, main.find_land_near(p + ki * 30.0, 26.0, true), age)
		var e: Node = main.spawn_unit("warship" if i % 2 == 0 else "galleon", 1,
			main.find_land_near(p + ki * 470.0, 26.0, true), age)
		if u != null:
			u.face = ki.angle()
			mi.append(u)
		if e != null:
			e.face = (-ki).angle()
			ok.append(e)
	_kijelol(mi)
	GameState.get_side(0)["toltet"] = "golyo"
	_lepesek.append([0.5, func() -> void:
		for j in mi.size():
			if is_instance_valid(mi[j]): mi[j].move_to(viz + ki * 150.0 + oldalra * (float(j) - 1.5) * 125.0)
		for j in ok.size():
			if is_instance_valid(ok[j]): ok[j].move_to(viz + ki * 260.0 + oldalra * (float(j) - 1.5) * 125.0)])
	_kam = [[0.0, hq.lerp(viz, 0.75), 0.82], [6.0, viz + ki * 150.0, 1.1], [14.0, viz + ki * 190.0, 1.25]]
	_kam_ide(_kam[0][1], 0.82)
# --- 5. ÉJSZAKA (19. század): támadás a kivilágított város ellen ---
func _ejszaka() -> void:
	var age := GameState.get_age()
	var hq := _hq(0)
	var felol := _szabad_irany(hq, _hq(1) - hq, 700.0)
	var oldalra := Vector2(-felol.y, felol.x)
	_varos(0, ["barracks", "house", "smith", "house", "market", "temple", "house", "stable"], 175.0, 0.6)
	var t1 := _epit("tower", 0, hq + felol * 250.0 + oldalra * 110.0)
	_epit("tower", 0, hq + felol * 250.0 - oldalra * 110.0)
	var vedok := _sereg(0, hq + felol * 200.0, felol,
		[["ranged", 12], ["melee", 8], ["siege", 3]], age, 28.0)
	for u in vedok: u.stance = Unit.STANCE_HOLD
	_kijelol(vedok)
	var tamadok := _sereg(1, main.find_land_near(hq + felol * 560.0, 40.0), -felol,
		[["cav", 8], ["melee", 12], ["spear", 8], ["ranged", 8]], age, 28.0)
	_lepesek.append([0.5, func() -> void: _indul(tamadok, hq + felol * 200.0)])
	var eleje := hq + felol * 300.0
	if t1 != null: eleje = eleje.lerp((t1 as Node2D).global_position, 0.3)
	_kam = [[0.0, hq + felol * 120.0, 0.95], [6.0, eleje, 1.2], [14.0, eleje + felol * 20.0, 1.35]]
	_kam_ide(_kam[0][1], 0.95)

# --- 6. MODERN (1945): harckocsik és repülők a hóban ---
func _modern() -> void:
	var age := GameState.get_age()
	var ehq := _hq(1)
	var felol := _szabad_irany(ehq, _hq(0) - ehq, 680.0)
	var oldalra := Vector2(-felol.y, felol.x)
	_epit("tower", 1, ehq + felol * 200.0 + oldalra * 130.0)
	_epit("tower", 1, ehq + felol * 200.0 - oldalra * 130.0)
	_epit("barracks", 1, ehq - felol * 40.0 + oldalra * 200.0)
	_epit("airfield", 1, ehq - felol * 60.0 - oldalra * 210.0)
	_epit("house", 1, ehq - felol * 170.0)
	var vedok := _sereg(1, ehq + felol * 160.0, felol,
		[["melee", 6], ["ranged", 10], ["siege", 3]], age, 34.0)
	var start := main.find_land_near(ehq + felol * 600.0, 40.0) as Vector2
	var sereg := _sereg(0, start, -felol,
		[["melee", 8], ["cav", 6], ["ranged", 10], ["siege", 3]], age, 36.0)
	var gepek := _sereg(0, start + felol * 330.0, -felol, [["fighter", 4], ["bomber", 3]], age, 70.0)
	_szallas(0, 6)
	_kijelol(sereg)
	_idojaras(main.weather.HO, 1.0)
	_lepesek.append([0.5, func() -> void: _indul(sereg, ehq + felol * 130.0)])
	_lepesek.append([1.5, func() -> void: _indul(vedok, ehq + felol * 250.0)])
	_lepesek.append([1.0, func() -> void: _indul(gepek, ehq + felol * 60.0)])
	_kovet = sereg
	_kovet_eltol = -felol * 130.0
	_kovet_zoom = [[0.0, 0.95], [6.0, 1.15], [14.0, 1.25]]
	_kam_ide(start - felol * 80.0, 0.95)
