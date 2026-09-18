class_name Main
extends Node2D

const UNIT_SCENE       := preload("res://scenes/units/Unit.tscn")
const BUILDING_SCENE   := preload("res://scenes/buildings/Building.tscn")
const PROJECTILE_SCENE := preload("res://scenes/units/Projectile.tscn")

# Építési költségek (a HUD BuildPanel ezt használja)
const BUILD_COST := {
	"hq":       {"wood": 400, "stone": 300},
	"barracks": {"wood": 200, "stone": 120},
	"stable":   {"wood": 180, "stone": 90,  "food": 60},
	"farm":     {"wood": 80},
	"tower":    {"wood": 90,  "stone": 140},
	"house":    {"wood": 70,  "stone": 30},
	"harbor":   {"wood": 220, "stone": 100},
	"temple":   {"wood": 160, "stone": 140, "gold": 80},
	"goldmine": {"wood": 120, "stone": 100},
	"airfield": {"wood": 400, "stone": 300, "gold": 250, "coal": 120},
	# A cukornád ára lemaradt, ezért a kalózvilágban INGYEN lehetett
	# ültetvényt húzni: a hiányzó bejegyzés üres költséget adott vissza.
	"sugar":    {"wood": 160, "gold": 60},
	"market":   {"wood": 180, "stone": 70,  "gold": 40},
	"hospital": {"wood": 160, "stone": 90,  "gold": 60},
	"smith":    {"wood": 150, "stone": 110, "gold": 60},
	"academy":  {"wood": 200, "stone": 130, "gold": 90},
}

@onready var unit_layer     := $WorldRoot/UnitLayer as Node2D
@onready var building_layer := $WorldRoot/BuildingLayer as Node2D
@onready var fog            := $FogLayer/FogOfWar as Node
@onready var hud            := $UILayer/HUD
@onready var sel_rect_ui    := $UILayer/SelectionRect as ColorRect
@onready var camera         := $Camera2D as Camera2D
@onready var terrain        := $WorldRoot/TerrainLayer/Terrain
@onready var water_sprite   := $WorldRoot/WaterLayer/WaterSprite as Sprite2D
@onready var bot_ai         := $BotAI

var selected_units : Array[Node] = []
var selected_bld   : Node        = null
var selected_res   : Node2D      = null
var _sel_start     : Vector2     = Vector2.ZERO
var _sel_screen    : Vector2     = Vector2.ZERO
var _sel_dragging  : bool        = false
var _build_mode    : String      = ""
var _rally_mode    : bool        = false
var _fog_accum     : float       = 0.0
var _ghost         : Node2D      = null
var _hq_pos        : Array[Vector2] = []
var _over_shown    : bool        = false
var _worker_seq    : Dictionary  = {}
var _objective     : Objective   = null
var _obj_accum     : float       = 0.0
var _tutorial      : Tutorial    = null
var net_sync       : Node        = null
var _net_sides     : Array       = []
# A visszajátszás felvevője/lejátszója (scripts/systems/Replay.gd).
var replay         : Node        = null
# A karibi városok és az ostrom (csak kalózvilágban).
var cities         : Node2D      = null
# A városra kattintva kinyíló kikötőmenü (scripts/ui/PortMenu.gd).
var port_menu      : Control     = null
# A piac árfolyama (scripts/systems/Market.gd).
var market         : Node        = null
# Újranövekedés, ellátás, kereskedelmi útvonal (scripts/systems/Economy.gd).
var economy        : Node        = null
# Időjárás: eső, hó, köd, tengeri vihar (scripts/systems/Weather.gd).
var weather        : Node        = null
# Sorsolt események: kereskedőhajó, roncs, zsoldosok, pestis.
var events         : Node        = null
# Diplomácia: szövetség és felmondás több fél között.
var diplomacy      : Node        = null
var _nid_seq       : int         = 0
var _forced_seed   : int         = 0

# A HUD a saját _ready-jében már keresi a "main" csoportot, ezért a
# regisztráció a gyerekek előtt, belépéskor történik.
func _enter_tree() -> void:
	add_to_group("main")

func _has_prefix(args: PackedStringArray, prefix: String) -> bool:
	for a in args:
		if a.begins_with(prefix): return true
	return false

# --- FEJLESZTŐI KAPCSOLÓK ---
#
# A projektből futtatva (Godot szerkesztő vagy a motor binárisa) minden
# fejlesztői kapcsoló él: --selftest, --soak, --skip-menu, --stress és a
# többi. A KIADOTT játékban egyik sem: ott a parancssor nem állíthatja át a
# játékot, és a `scripts/dev` mappa sincs a csomagban.
#
# A kapu EGY helyen van — a kapcsolókat mindenhol a `dev_args()`-ból
# olvassuk, sosem közvetlenül az `OS.get_cmdline_user_args()`-ból. Így nem
# maradhat véletlenül kint egy kapcsoló a kiadásban.
#
# EGYETLEN KIVÉTEL a `--relay=<kapu>`: az nem fejlesztői eszköz, hanem
# dokumentált többjátékos funkció (lásd a `net_relay_sugo` súgószöveget) —
# a közvetítő maga a játék, ezzel a kapcsolóval indítva. Azt szándékosan
# közvetlenül olvassuk.
static func dev_tools_enabled() -> bool:
	return OS.has_feature("editor") or OS.is_debug_build()

static func dev_args() -> PackedStringArray:
	return OS.get_cmdline_user_args() if dev_tools_enabled() \
		else PackedStringArray()

func _ready() -> void:
	# Szünet alatt is kapjon bemenetet, különben nem lehetne feloldani.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Fejlesztői nyelvváltás:  godot -- --lang=en
	# Részletesség méréshez:   godot -- --detail=0
	for arg in dev_args():
		if arg.begins_with("--lang="):
			Lang.set_language(arg.substr(7))
		if arg.begins_with("--detail="):
			Settings.detail = clampi(int(arg.substr(9)), 0, 2)
		# Rögzített világ a méréshez: enélkül minden futás más pályán mér.
		if arg.begins_with("--seed="):
			_forced_seed = absi(int(arg.substr(7)))
		if arg == "--nocull":
			Settings.cull_offscreen = false
	# Hálózati próba két folyamattal:  -- --nethost  /  -- --netjoin=KOD
	var uargs := dev_args()
	if ("--nethost" in uargs or _has_prefix(uargs, "--netjoin=")
			or _has_prefix(uargs, "--netrelayhost=")
			or _has_prefix(uargs, "--netrelayjoin=")) \
			and get_tree().root.get_node_or_null("NetTest") == null:
		var nt: Node = (load("res://scripts/dev/NetTest.gd") as GDScript).new()
		get_tree().root.call_deferred("add_child", nt)
	# KÖZVETÍTŐ ÜZEMMÓD: ez a példány nem játszik, csak továbbítja a
	# csomagokat.  Birodalom.exe -- --relay=27020
	#
	# Ez NEM fejlesztői kapcsoló, hanem a többjátékos rész dokumentált
	# funkciója (lásd `net_relay_sugo`), ezért a KIADOTT játékban is él —
	# vagyis szándékosan a valódi parancssort olvassa, nem a dev_args()-ot.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--relay="):
			if Net.start_relay(int(a.substr(8))):
				hud.visible = false
				set_process(false)
				return
	hud.theme = Style.make_theme(GameState.get_age())
	GameState.era_changed.connect(_on_era_changed)
	GameState.royal_fleet.connect(_on_royal_fleet)
	# A projekt főjelenete a Main.tscn; ha még nem indult játék, a főmenü
	# jelenik meg fölötte, és az indítja újra ezt a jelenetet.
	# Fejlesztői indulás menü nélkül:  godot -- --skip-menu
	# Visszajátszás fejlesztői indítása:  -- --replay        (a legfrissebb)
	#                                     -- --replay=<fájl>
	if not GameState.on:
		for a in dev_args():
			if a == "--replay" or a.begins_with("--replay="):
				var utvonal := a.substr(9) if a.length() > 9 else ""
				if utvonal == "":
					var lista: Array = (load("res://scripts/systems/Replay.gd")
						as GDScript).list_files()
					if not lista.is_empty(): utvonal = str(lista[0])
				if utvonal != "" and _setup_replay(utvonal): break
	if not GameState.on and "--skip-menu" in dev_args():
		# `--pirate`: kalózvilág. `--campaign=hu:2`: hadjárat, adott
		# nemzet adott küldetésével (a sorszám 1-től).
		var pir := "--pirate" in dev_args()
		var camp := ""
		for a in dev_args():
			if a.begins_with("--campaign="): camp = a.substr(11)
		if camp != "":
			var parts := camp.split(":")
			var cn := parts[0]
			var ci := (int(parts[1]) - 1) if parts.size() > 1 else 0
			Campaign.start(cn, maxi(ci, 0))
			var key := Campaign.nation_key(cn)
			GameState.new_game(key, 0, Style.is_pirate(key))
		else:
			# `--age=2`: adott korszakban indul (grafikai ellenőrzéshez).
			# `--sides=4`: csata több féllel (te + botok, mindenki külön csapat).
			# `--map=hegy`: adott tájon indul (a tájtípusok a WorldGen.MAPS-ban).
			var kor := GameState.start_age
			var felek := 0
			var taj := ""
			for a in dev_args():
				if a.begins_with("--age="): kor = clampi(int(a.substr(6)), 0, 3)
				if a.begins_with("--sides="): felek = clampi(int(a.substr(8)), 2, 6)
				if a.begins_with("--map="): taj = a.substr(6)
			if taj != "": GameState.map_type = taj
			if felek > 0:
				var lista: Array = [{"tipus": "ember", "nemzet": GameState.nation,
					"csapat": 0}]
				var nemzetek := Style.order_for(pir)
				for i in range(1, felek):
					lista.append({"tipus": "bot",
						"nemzet": str(nemzetek[i % nemzetek.size()]), "csapat": i})
				GameState.new_battle(lista, kor, pir, 0, 0, taj)
			else:
				GameState.new_game("ns" if pir else GameState.nation, kor, pir, taj)
			if "--tutorial" in dev_args():
				GameState.tutorial = true
	if not GameState.on:
		_show_menu()
		for arg in dev_args():
			if arg.begins_with("--shot="):
				_capture_after(arg.substr(7))
		return
	if GameState.oldalak.is_empty():
		GameState.new_game(GameState.nation, GameState.start_age)
	_start_world()
	# Fejlesztői ellenőrzés:
	#   godot -- --skip-menu --selftest      egyszeri átvizsgálás
	#   godot -- --skip-menu --soak=300      300 mp játékidő gyorsítva
	var args := dev_args()
	if "--selftest" in args:
		var t: Node = (load("res://scripts/dev/SelfTest.gd") as GDScript).new(self)
		add_child(t)
		t.run()
	# Fegyverpróba:  godot -- --skip-menu --weapontest --shot=out.png
	if "--weapontest" in args:
		var wt: Node = (load("res://scripts/dev/SelfTest.gd") as GDScript).new(self)
		add_child(wt)
		var kor := 0
		for a in args:
			if a.begins_with("--age="): kor = clampi(int(a.substr(6)), 0, 3)
		wt.weapon_test(kor)
	# Hajópróba:  godot -- --skip-menu --shiptest --shot=out.png
	if "--shiptest" in args:
		var ht: Node = (load("res://scripts/dev/SelfTest.gd") as GDScript).new(self)
		add_child(ht)
		var hkor := 0
		for a in args:
			if a.begins_with("--age="): hkor = clampi(int(a.substr(6)), 0, 3)
		ht.ship_test(hkor)
	if "--showcase" in args:
		var c: Node = (load("res://scripts/dev/SelfTest.gd") as GDScript).new(self)
		add_child(c)
		c.showcase()
	# Sebességmérés rendes tempóban, ablakban:  -- --bench=20
	for arg in args:
		if arg.begins_with("--bench="):
			var bt: Node = (load("res://scripts/dev/SelfTest.gd") as GDScript).new(self)
			add_child(bt)
			bt.bench(float(arg.substr(8)))
	for arg in args:
		if arg.begins_with("--soak="):
			var s: Node = (load("res://scripts/dev/SelfTest.gd") as GDScript).new(self)
			add_child(s)
			s.soak(float(arg.substr(7)))
	# A játék közbeni menü megnyitása ellenőrzéshez:  -- --gamemenu
	if "--gamemenu" in args:
		hud.open_game_menu(true)
		if "--gamemenu-settings" in args:
			hud._show_settings(true)
	# Terhelésmérés:  -- --stress=300  (ennyi extra katona kerül a pályára)
	for arg in args:
		if arg == "--portmenu" or arg.begins_with("--portmenu="):
			_open_nearest_port(arg.substr(11) if arg.length() > 11 else "")
		if arg.begins_with("--stress="):
			var n := clampi(int(arg.substr(9)), 0, 2000)
			var felek := maxi(GameState.oldalak.size(), 2)
			for i in range(n):
				var oldal := i % felek
				var a := TAU * float(i) / 24.0
				var d := 140.0 + 6.0 * float(i / felek)
				spawn_unit(["melee", "ranged", "spear"][i % 3], oldal,
					find_land_near(_hq_pos[oldal] + Vector2(cos(a), sin(a)) * d,
						30.0), GameState.start_age)
			print("[terheles] %d extra egyseg" % n)
	# Tájkép ellenőrzéshez:  -- --reveal --zoom=0.4
	if "--reveal" in args:
		fog.reveal_all()
		fog.visible = false          # a tájat fátyol nélkül nézzük
	for arg in args:
		if arg.begins_with("--zoom="):
			var z := clampf(float(arg.substr(7)), 0.1, 4.0)
			camera.zoom = Vector2(z, z)
			camera.position = Vector2(GameState.WORLD_W, GameState.WORLD_H) * 0.5
			camera.reset_smoothing()
	# Képernyőkép a játékról:  godot -- --skip-menu --shot=<útvonal>
	for arg in dev_args():
		if arg.begins_with("--shot="):
			_capture_after(arg.substr(7))

# A kikötőmenü ellenőrzése képernyőképpel:
#   -- --skip-menu --pirate --portmenu=build --shot=...
# A saját fővárosodhoz legközelebbi várost nyitja meg, és a kamerát is
# odaviszi, hogy a legyező a képen legyen.
func _open_nearest_port(mit: String) -> void:
	if port_menu == null or cities == null: return
	var hq: Vector2 = _hq_pos[clampi(GameState.en_id, 0, _hq_pos.size() - 1)]
	var best := ""
	var bd := 1e12
	for k in cities.varosok:
		var d: float = cities.city_pos(str(k)).distance_to(hq)
		if d < bd:
			bd = d
			best = str(k)
	if best == "": return
	camera.position = cities.city_pos(best)
	camera.reset_smoothing()
	port_menu.open(best)
	if mit != "": port_menu.pick(mit)
	print("[kikotomenu] %s (%s)" % [cities.city_name(best),
		"sajat" if cities.owner_of(best) == GameState.en_id else "idegen"])

# Néhány képkocka után menti a viewport tartalmát, majd kilép.
func _capture_after(path: String) -> void:
	# `--shotwait=600`: később készül a kép (pl. a router válaszára várva).
	var frames := 90
	for a in dev_args():
		if a.begins_with("--shotwait="): frames = clampi(int(a.substr(11)), 1, 20000)
	for _i in range(frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("képernyőkép:", path)
	get_tree().quit()

func _show_menu() -> void:
	hud.visible = false
	var menu := preload("res://scenes/ui/Menu.tscn").instantiate()
	menu.theme = Style.make_theme(0)
	$UILayer.add_child(menu)
	SFX.play_menu_music()

# Korszakváltáskor a felület palettája és a ZENE is átáll: minden korszaknak
# saját dallama van.
func _on_era_changed(owner_id: int, new_age: int) -> void:
	if owner_id != GameState.en_id: return
	hud.theme = Style.make_theme(new_age)
	SFX.play("age")
	SFX.play_era_music(new_age)

func _setup_water() -> void:
	# A víz egyetlen, a világot lefedő sprite, saját shaderrel.
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	water_sprite.texture = ImageTexture.create_from_image(img)
	water_sprite.centered = false
	water_sprite.scale = Vector2(GameState.WORLD_W / 8.0, GameState.WORLD_H / 8.0)
	var mat := water_sprite.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("world_size",
			Vector2(GameState.WORLD_W, GameState.WORLD_H))

func _start_world() -> void:
	# A vizet és a felületet CSAK a pályaméret ismeretében állíthatjuk be:
	# a kalózvilág pályája nagyobb, és a new_game állítja a méretet.
	_setup_water()
	# A kamera határai a jelenetben a rendes pályaméretre vannak állítva.
	# A kalózvilág nagyobb, ezért itt igazítjuk őket — enélkül a kamera a
	# bázistól messze, felderítetlen (fekete) területre szorulna.
	camera.limit_right = GameState.WORLD_W
	camera.limit_bottom = GameState.WORLD_H
	hud.refresh_mode()
	if Campaign.active:
		_objective = Objective.new(Campaign.current())
		hud.show_mission(Campaign.current(), _objective.text(get_tree()))
	var gen := WorldGen.new()
	if _forced_seed != 0: GameState.sim_mag = _forced_seed
	gen.generate(GameState.sim_mag, terrain)
	fog.init()
	# HÁLÓZATI JÁTSZMA: a világ mindenkinél ugyanabból a magból generálódik,
	# de a bábukat CSAK a házigazda teremti — a csatlakozó a pillanatképből
	# kapja meg őket. Enélkül minden egység duplán jönne létre.
	_hq_pos.clear()
	for p in WorldGen.start_positions():
		_hq_pos.append(find_land_near(p, 100.0))
	# Oktatómódban a bot nem küld hullámokat: nyugodtan végig lehet menni a
	# lépéseken. Ezt a BOTOK INDÍTÁSA ELŐTT kell megtenni — a BotAI.start()
	# ekkor olvassa ki a hullámidőt, és ha utána írjuk át, az első hullám
	# (a régi 115 mp-es értékkel) még kifut az oktatómód ellenére is.
	if GameState.tutorial:
		for i in range(1, GameState.oldalak.size()):
			GameState.get_side(i)["waveT"] = 99999.0
	if not GameState.net_client:
		_spawn_headquarters()
		_spawn_starting_units()
		_start_bots()
	if Net.active():
		_net_sides = Net.last_payload.get("sides", [])
		net_sync = (load("res://scripts/systems/NetSync.gd") as GDScript).new(self)
		add_child(net_sync)
		net_sync.set_peer_sides(_net_sides)
	# PIAC: nyersanyagcsere aranyért, mozgó árfolyammal. A piac épület
	# adja hozzá a jogot; az árfolyamot ez a csomópont vezeti.
	market = (load("res://scripts/systems/Market.gd") as GDScript).new()
	add_child(market)
	# GAZDASÁG: újranövekedés, ellátás (a sereg eszik) és kereskedelmi
	# útvonal a kikötőből.
	economy = (load("res://scripts/systems/Economy.gd") as GDScript).new(self)
	add_child(economy)
	# IDŐJÁRÁS: a szárazföldi idő és a tenger állapota.
	weather = (load("res://scripts/systems/Weather.gd") as GDScript).new(self)
	add_child(weather)
	# ESEMÉNYEK: néhány percenként történik valami a térképen.
	events = (load("res://scripts/systems/Events.gd") as GDScript).new(self)
	add_child(events)
	# DIPLOMÁCIA: szövetségek a felek között (a GameState.hostile ezt kérdezi).
	diplomacy = (load("res://scripts/systems/Diplomacy.gd") as GDScript).new(self)
	add_child(diplomacy)
	GameState.diplomacy = diplomacy
	# A KARIB-TENGER VÁROSAI — csak a kalózvilágban. A kikötők lakossággal,
	# tornyokkal és fallal állnak; ágyúval lehet őket megtörni, katonával
	# elfoglalni (scripts/systems/Cities.gd).
	if GameState.pirate:
		cities = (load("res://scripts/systems/Cities.gd") as GDScript).new(self)
		$WorldRoot/BuildingLayer.add_child(cities)
		# A városra kattintva ez a legyező nyílik ki: építés és toborzás.
		port_menu = (load("res://scripts/ui/PortMenu.gd") as GDScript).new()
		port_menu.main = self
		$UILayer.add_child(port_menu)
	# VISSZAJÁTSZÁS. Lejátszásnál a világ ugyanabból a magból készül, a
	# bábukat viszont nem mi teremtjük: a felvett pillanatképek rakják ki
	# őket (ugyanúgy, ahogy a hálózati társnál). Egyjátékos játszmában
	# viszont FELVESZÜNK, hogy utólag vissza lehessen nézni.
	replay = (load("res://scripts/systems/Replay.gd") as GDScript).new()
	replay.name = "Replay"
	add_child(replay)
	if GameState.replay_path != "":
		if replay.start_playback(GameState.replay_path, self):
			hud.show_toast(Lang.t("visszajatszas"), 5.0)
			replay.playback_finished.connect(func() -> void:
				hud.show_toast(Lang.t("visszajatszas_vege"), 6.0))
		else:
			hud.show_toast(Lang.t("visszajatszas_hibas"), 4.0)
	elif not Net.active() and not GameState.net_client:
		replay.start_recording()
	camera.position = _hq_pos[clampi(GameState.en_id, 0, _hq_pos.size() - 1)]
	if GameState.tutorial:
		_tutorial = Tutorial.new(self)
		add_child(_tutorial)
	# A korszak zenéje. A kalózvilágban nincs korszakváltás, ott végig a
	# vitorlások korának dallama szól.
	SFX.play_era_music(GameState.get_age())

# Minden gépi oldal saját BotAI csomópontot kap. A jelenetben egy van; a
# többit itt hozzuk létre ugyanabból a szkriptből.
# A felvétel fejléce alapján ugyanúgy állítjuk be a játszmát, mint a menü.
func _setup_replay(path: String) -> bool:
	var rs := load("res://scripts/systems/Replay.gd") as GDScript
	var m: Dictionary = rs.peek(path)
	if m.is_empty(): return false
	var sides: Array = m.get("oldalak", [])
	if sides.is_empty(): return false
	Campaign.stop()
	GameState.new_battle(sides, int(m.get("kor", 0)), bool(m.get("kaloz", false)),
		int(m.get("en_id", 0)), int(m.get("mag", 0)), str(m.get("taj", "mezo")))
	GameState.diff = int(m.get("diff", 1))
	GameState.net_client = true
	GameState.replay_path = path
	print("[replay] lejátszás: ", path, "  (", m.get("datum", "?"), ")")
	return true

func _start_bots() -> void:
	bot_ai.start(1)
	for i in range(2, GameState.oldalak.size()):
		var side := GameState.get_side(i)
		if side.get("tipus", "bot") == "ember": continue
		var b: Node = (load("res://scripts/ai/BotAI.gd") as GDScript).new()
		b.name = "BotAI%d" % i
		add_child(b)
		b.start(i)

func _spawn_headquarters() -> void:
	# A generált víztérkép bárhol lehet, ezért a bázisokat a kívánt hely
	# körüli legközelebbi szárazföldre tesszük. Több félnél a kezdőhelyek
	# körben oszlanak el a pálya szélén, hogy senki ne induljon a másik
	# ölében. A képlet a WorldGen-ben van, mert a kezdő nyersanyagokat is
	# oda kell tenni — így a kettő nem csúszhat szét.
	for i in range(GameState.oldalak.size()):
		spawn_building("hq", i, _hq_pos[i])

func _spawn_starting_units() -> void:
	var age := GameState.start_age
	for side in range(GameState.oldalak.size()):
		for i in range(4):
			var a := TAU * float(i) / 4.0
			spawn_unit("worker", side,
				find_land_near(_hq_pos[side] + Vector2(cos(a), sin(a)) * 110.0, 60.0), age)
		for i in range(2):
			spawn_unit("melee", side,
				find_land_near(_hq_pos[side] + Vector2(-40.0 + 80.0 * i, -130.0), 60.0), age)
		# A kalózvilágban a hajó a mindened: mindenki kap egy szlúpot.
		if GameState.pirate:
			spawn_unit("transport", side,
				find_land_near(_hq_pos[side] + Vector2(0, 160.0), 40.0, true), age)

# A királyi hajóhad: ha a hírnév a tetőre ér, a korona hadihajókat küld a
# bázisod partjaihoz. A hírnév ilyenkor visszaesik — a rablás ára.
func _on_royal_fleet() -> void:
	if _hq_pos.is_empty(): return
	var sea := find_land_near(_hq_pos[0] + Vector2(0, 260.0), 60.0, true)
	var n := 3 + int(GameState.diff)
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var p := find_land_near(sea + Vector2(cos(a), sin(a)) * (90.0 + 30.0 * i),
			40.0, true)
		var u := spawn_unit("warship" if i % 3 else "galleon", 1, p,
			GameState.start_age)
		if u and u.has_method("move_to"):
			u.move_to(_hq_pos[0])
	SFX.play("cannon", -4.0)
	hud.show_toast(Lang.t("kiralyi_hajohad"))

# A megadott pont körüli legközelebbi szárazföldi (vagy vízi) hely.
func find_land_near(pos: Vector2, clearance: float, want_water: bool = false) -> Vector2:
	var margin := clearance + 20.0
	var p := Vector2(
		clampf(pos.x, margin, GameState.WORLD_W - margin),
		clampf(pos.y, margin, GameState.WORLD_H - margin))
	if _ground_ok(p, clearance, want_water): return p
	for ring in range(1, 40):
		var rad := float(ring) * 40.0
		for i in range(12):
			var a := TAU * float(i) / 12.0 + float(ring) * 0.3
			var q := p + Vector2(cos(a), sin(a)) * rad
			q.x = clampf(q.x, margin, GameState.WORLD_W - margin)
			q.y = clampf(q.y, margin, GameState.WORLD_H - margin)
			if _ground_ok(q, clearance, want_water): return q
	return p

# Nem elég a középpontot vizsgálni: egy pont a cellahatáron meg szárazföld,
# de az egység első lépése már vízbe viszi. Ezért kis kört mintavételezünk.
func _ground_ok(p: Vector2, clearance: float, want_water: bool) -> bool:
	if terrain.is_water(p) != want_water: return false
	var r := minf(clearance, 20.0)
	for i in range(8):
		var a := TAU * float(i) / 8.0
		if terrain.is_water(p + Vector2(cos(a), sin(a)) * r) != want_water:
			return false
	return true

# A megadott pont körüli legközelebbi hely, ahova az adott épület TÉNYLEG
# lerakható (a teljes lábnyom számít, nem csak a középpont).
# Vector2.INF, ha nincs ilyen a közelben.
func find_build_spot(tipus: String, near: Vector2) -> Vector2:
	if can_place(tipus, near): return near
	for ring in range(1, 16):
		var rad := float(ring) * 36.0
		var steps := 8 + ring * 2
		for i in range(steps):
			var a := TAU * float(i) / steps + float(ring) * 0.4
			var q := near + Vector2(cos(a), sin(a)) * rad
			if can_place(tipus, q): return q
	return Vector2.INF

func _process(delta: float) -> void:
	if GameState.over:
		if not _over_shown:
			_over_shown = true
			set_build_mode("")
			var gyozott := GameState.winner == GameState.en_id
			if gyozott:
				Achievements.bump("wins")
				if GameState.pirate: Achievements.bump("pirate_wins")
			# A VISSZAJÁTSZÁS lezárása: a játszma végén mentjük a felvételt.
			if replay != null and is_instance_valid(replay) and replay.recording:
				var utvonal: String = replay.stop_recording()
				if utvonal != "":
					hud.show_toast(Lang.t("visszajatszas_mentve"), 4.0)
			hud.show_game_over(gyozott)
		return
	if not GameState.on: return
	# A csatlakozónál az időt és a küldetést a házigazda számolja.
	if not GameState.net_client:
		GameState.t += delta
		GameState.fame_tick(delta)
		_tick_objective(delta)
	# A megsemmisült — és a paptól ÁTÁLLÍTOTT — egységek kiesnek a
	# kijelölésből: az utóbbiak már nem a mieink, nem parancsolhatunk nekik.
	if not selected_units.is_empty():
		var live: Array[Node] = []
		for u in selected_units:
			# A hajó gyomrába szállt egységnek sem lehet parancsolni:
			# a hajót kell irányítani helyette.
			if is_instance_valid(u) and int(u.owner_id) == GameState.en_id \
					and not u.aboard():
				live.append(u)
		if live.size() != selected_units.size():
			selected_units = live
			hud.update_selection(selected_units)
	if selected_bld != null and not is_instance_valid(selected_bld):
		selected_bld = null
		hud.select_building(null)
	# A fog of war újraszámolása drága, ezért ~10 Hz-en fut.
	_fog_accum += delta
	if _fog_accum >= Settings.fog_interval():
		fog.tick(_fog_accum)
		_fog_accum = 0.0
	if _sel_dragging:
		_update_sel_rect()

func spawn_unit(role: String, owner_id: int,
				pos: Vector2, age: int) -> Node:
	var u := UNIT_SCENE.instantiate()
	u.role     = role
	u.owner_id = owner_id
	u.age      = age
	if role == "worker":
		# Oldalanként körbeosztjuk a nyersanyagokat, különben minden
		# munkás ugyanarra a legközelebbi lelőhelyre menne.
		var i: int = _worker_seq.get(owner_id, 0)
		u.gather_pref = ResourceSystem.PREF_CYCLE[i % ResourceSystem.PREF_CYCLE.size()]
		_worker_seq[owner_id] = i + 1
	# Hálózati azonosító: a HÁZIGAZDA osztja, a csatlakozó a pillanatképből
	# kapja (ott a NetSync írja felül).
	if not GameState.net_client:
		_nid_seq += 1
		u.nid = _nid_seq
	unit_layer.add_child(u)
	u.global_position = pos
	return u

func spawn_building(tipus: String, owner_id: int, pos: Vector2,
					instant: bool = true) -> Node:
	var b := BUILDING_SCENE.instantiate()
	b.tipus    = tipus
	b.owner_id = owner_id
	b.age      = GameState.get_age(owner_id)
	if not instant:
		b.prog = 0.0
		b.build_time = BUILD_TIME.get(tipus, 12.0)
	if not GameState.net_client:
		_nid_seq += 1
		b.nid = _nid_seq
	building_layer.add_child(b)
	b.global_position = pos
	return b

# A küldetés célját másodpercenként ötször nézzük meg — a folyamatos
# számlálás (épületek, egységek végigjárása) minden képkockán pazarlás.
func _tick_objective(delta: float) -> void:
	if _objective == null: return
	_obj_accum += delta
	if _obj_accum < 0.2: return
	_obj_accum = 0.0
	_objective.check(get_tree())
	hud.update_objective(_objective.text(get_tree()))
	if _objective.done:
		Campaign.complete()
		Achievements.reach("missions", float(Campaign.total_done()))
		GameState.on = false
		GameState.over = true
		GameState.winner = GameState.en_id
		_over_shown = true
		hud.show_mission_complete(Campaign.has_next())
	elif _objective.failed:
		_over_shown = true
		hud.show_game_over(false)

func spawn_projectile(from: Vector2, to_node: Node2D, damage: float,
					  owner_id: int) -> Node:
	var p := PROJECTILE_SCENE.instantiate()
	unit_layer.add_child(p)
	p.setup(from, to_node, damage, owner_id)
	return p

# --- Építés a HUD BuildPanel-ról ---

const BUILD_TIME := {
	"hq": 30.0, "barracks": 16.0, "stable": 14.0, "farm": 8.0, "tower": 12.0,
	"house": 8.0, "harbor": 16.0, "temple": 18.0, "goldmine": 12.0,
	"airfield": 26.0, "sugar": 14.0,
	"market": 14.0, "hospital": 15.0, "smith": 15.0, "academy": 17.0,
}

func set_build_mode(tipus: String) -> void:
	_build_mode = tipus
	_clear_ghost()
	if tipus == "": return
	_ghost = BuildGhost.new()
	_ghost.tipus = tipus
	_ghost.foot  = Building.size_of(tipus)
	_ghost.high  = Building.height_of(tipus, GameState.get_age())
	_ghost.z_index = 9
	building_layer.add_child(_ghost)

func _clear_ghost() -> void:
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null

# Az építés helye akkor jó, ha a lábnyom szárazföldön van (a kikötőnek
# viszont partot kell érintenie), nem lóg ki a világból, és nem fedi
# egyetlen már álló épület lábnyomát sem.
func can_place(tipus: String, pos: Vector2) -> bool:
	if tipus in GameState.banned_buildings: return false
	var foot: Vector2 = Building.size_of(tipus)
	var half := foot * 0.5
	if pos.x - half.x < 8.0 or pos.y - half.y < 8.0: return false
	if pos.x + half.x > GameState.WORLD_W - 8.0: return false
	if pos.y + half.y > GameState.WORLD_H - 8.0: return false
	var shore: bool = bool(Building.BUILD_STATS.get(tipus, {}).get("shore", false))
	var water_seen := false
	var land_seen  := false
	for dx in [-half.x, 0.0, half.x]:
		for dy in [-half.y, 0.0, half.y]:
			if terrain.is_water(pos + Vector2(dx, dy)):
				water_seen = true
			else:
				land_seen = true
	if shore:
		if not (water_seen and land_seen): return false
	elif water_seen:
		return false
	var mine := Rect2(pos - half, foot).grow(6.0)
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b): continue
		var bh: Vector2 = Building.size_of(b.tipus) * 0.5
		if mine.intersects(Rect2(b.global_position - bh, bh * 2.0)):
			return false
	return true

func _try_place_building(pos: Vector2) -> void:
	if not can_place(_build_mode, pos):
		return                                   # rossz hely: maradunk építő módban
	if not GameState.can_pay(GameState.en_id, build_cost(GameState.en_id, _build_mode)):
		set_build_mode("")
		return
	send_cmd("build", [_build_mode, pos])
	if not Input.is_key_pressed(KEY_SHIFT):      # Shift: sorozatban építhetünk
		set_build_mode("")

# Az alapkő letétele után a munkásoknak oda kell menniük — magától
# semmi nem épül fel. A kijelölt munkások indulnak; ha egy sincs
# kijelölve, a legközelebbi munkás vállalja el.
func _send_builders(b: Node, owner: int = -1) -> void:
	if owner < 0: owner = GameState.en_id
	var sent := 0
	# A kijelölés a KÉPERNYŐHÖZ tartozik, ezért csak a saját parancsunknál
	# nézzük; a társ parancsánál a legközelebbi munkása vállalja el.
	if owner == GameState.en_id:
		for u in selected_units:
			if is_instance_valid(u) and u.has_method("build_at") and u.role == "worker":
				u.build_at(b)
				sent += 1
	if sent > 0: return
	var best: Node = null
	var best_d := INF
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u) or u.role != "worker": continue
		if int(u.owner_id) != owner: continue
		var d: float = u.global_position.distance_to(b.global_position)
		if d < best_d:
			best_d = d
			best = u
	if best != null:
		best.build_at(b)

# Az építés előtti áttetsző előnézet: zöld, ha a hely jó, piros, ha nem.
class BuildGhost extends Node2D:
	var tipus : String  = "farm"
	var foot  : Vector2 = Vector2(64, 64)
	var high  : float   = 30.0
	var ok    : bool    = true

	func _process(_delta: float) -> void:
		var main := get_tree().get_first_node_in_group("main")
		if main == null: return
		global_position = get_global_mouse_position()
		var was := ok
		ok = main.can_place(tipus, global_position)
		if was != ok: queue_redraw()
		queue_redraw()

	func _draw() -> void:
		var c := Color(0.35, 0.85, 0.4, 0.35) if ok else Color(0.9, 0.25, 0.2, 0.35)
		var r := Rect2(-foot * 0.5, foot)
		draw_rect(r, c, true)
		draw_rect(r, Color(c.r, c.g, c.b, 0.9), false, 2.0)
		draw_rect(Rect2(r.position.x, r.position.y - high, foot.x, high),
			Color(c.r, c.g, c.b, 0.18), true)

# --- Bemenet ---

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
		return
	if event.is_action_pressed("deselect"):
		_clear_selection()
		set_build_mode("")
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _build_mode != "":
			set_build_mode("")
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _rally_mode:
			_rally_mode = false
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _rally_mode:
					set_rally_at(get_global_mouse_position())
					return
				if _build_mode != "":
					_try_place_building(get_global_mouse_position())
					return
				# A kalózvilágban a városjelölő kattintható: rajta nyílik a
				# kikötőmenü. Máshová kattintva becsukódik.
				if _port_click(get_global_mouse_position()): return
				_sel_start    = get_global_mouse_position()
				_sel_screen   = mb.position
				_sel_dragging = true
				sel_rect_ui.visible = true
			elif _sel_dragging:
				_finish_sel(get_global_mouse_position())
				_sel_dragging = false
				sel_rect_ui.visible = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_issue_order(get_global_mouse_position())

# Kattintás egy városjelölőre. A célpontot a KÉPERNYŐN mérjük, nem
# világkoordinátában: kinagyított térképen ugyanakkora legyen a jelölő
# találati sávja, mint kicsinyítve. A névtábla a jelölő ALATT van, ezért
# lefelé nyújtjuk a sávot (index.html: portHit).
func _port_click(wp: Vector2) -> bool:
	if port_menu == null or cities == null: return false
	var z: float = maxf(camera.zoom.x, 0.05)
	# A névtábla a jelölő FÖLÖTT van (lásd Cities._draw), ezért felfelé
	# nyújtjuk a találati sávot.
	var kulcs: String = cities.city_at(wp + Vector2(0.0, 22.0 / z), 64.0 / z)
	if kulcs == "":
		if port_menu.is_open():
			port_menu.close()
			return true
		return false
	_clear_selection()
	port_menu.open(kulcs)
	return true

# --- PARANCSOK ---
#
# Hálózati játszmában a kattintásból ÜZENET lesz: a csatlakozó elküldi a
# házigazdának, aki végrehajtja. Egyjátékos módban ugyanezek a függvények
# futnak, csak helyben. A `do_*` mindig a HÁZIGAZDA gépén hajtódik végre.

func send_cmd(kind: String, args: Array) -> void:
	if net_sync != null and is_instance_valid(net_sync):
		net_sync.send_cmd(kind, args)
		return
	_local_cmd(kind, args)

func _local_cmd(kind: String, args: Array) -> void:
	var me := GameState.en_id
	match kind:
		"move":   do_move(args[0], args[1], me)
		"attack": do_attack(args[0], int(args[1]), me)
		"gather": do_gather(args[0], int(args[1]), me)
		"stop":   do_stop(args[0], me)
		"build":  do_build(str(args[0]), args[1], me)
		"train":  do_train(int(args[0]), str(args[1]), me)
		"rally":  do_rally(int(args[0]), args[1], int(args[2]), int(args[3]), me)
		"era":    do_era(me)
		"upg":    do_research(int(args[0]), me)
		"board":  do_board(args[0], int(args[1]), me)
		"unload": do_unload(args[0], args[1], me)
		"pbuild": do_port_build(str(args[0]), str(args[1]), me)
		"ptrain": do_port_train(str(args[0]), str(args[1]), me)

# Az azonosítók hálózaton is átvihetők, ezért minden parancs nid-ekkel
# dolgozik, nem csomópont-hivatkozásokkal.
func nid_of(n: Node) -> int:
	return int(n.nid) if n != null and is_instance_valid(n) else 0

func unit_by_nid(id: int) -> Node:
	if id <= 0: return null
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and int(u.nid) == id: return u
	return null

func building_by_nid(id: int) -> Node:
	if id <= 0: return null
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and int(b.nid) == id: return b
	return null

func node_by_nid(id: int) -> Node:
	if id <= 0: return null
	for n in get_tree().get_nodes_in_group("resources"):
		if is_instance_valid(n) and int(n.nid) == id: return n
	return null

# Csak a SAJÁT egységeire adhat parancsot bárki.
func _own_units(ids: Array, owner: int) -> Array:
	var out: Array = []
	for id in ids:
		var u := unit_by_nid(int(id))
		if u != null and int(u.owner_id) == owner: out.append(u)
	return out

func do_move(ids: Array, pos: Vector2, owner: int) -> void:
	var lista := _own_units(ids, owner)
	var offsets := NavSystem.formation_offsets(lista.size(), 30.0)
	for i in lista.size():
		if lista[i].has_method("move_to"): lista[i].move_to(pos + offsets[i])

func do_attack(ids: Array, target: int, owner: int) -> void:
	var t: Node = unit_by_nid(target)
	if t == null: t = building_by_nid(target)
	if t == null: return
	for u in _own_units(ids, owner):
		if u.has_method("start_attacking"): u.start_attacking(t)

func do_gather(ids: Array, node_id: int, owner: int) -> void:
	var n := node_by_nid(node_id)
	if n == null: return
	for u in _own_units(ids, owner):
		if u.role in ["worker", "fisher"] and u.has_method("gather_at"):
			u.gather_at(n)

func do_stop(ids: Array, owner: int) -> void:
	for u in _own_units(ids, owner):
		if u.has_method("stop"): u.stop()

# Az építés ára a Számvitel-fokozattal csökken. Egy helyen számoljuk, hogy
# a felület ugyanazt az árat mutassa, amit a kassza levon.
static func build_cost(owner: int, tipus: String) -> Dictionary:
	return Upgrades.scale_cost(owner, BUILD_COST.get(tipus, {}))

func do_build(tipus: String, pos: Vector2, owner: int) -> void:
	if not can_place(tipus, pos): return
	if not GameState.pay(owner, build_cost(owner, tipus)): return
	var b := spawn_building(tipus, owner, pos, false)
	_send_builders(b, owner)
	if owner == GameState.en_id:
		Achievements.bump("builds")
		SFX.play("build")

# Kutatás. A parancsban a fejlesztés SORSZÁMA utazik, nem a neve — ugyanaz
# a megfontolás, mint a szerepköröknél és az épülettípusoknál.
func do_research(upg_index: int, owner: int) -> void:
	if upg_index < 0 or upg_index >= Upgrades.ORDER.size(): return
	var key: String = Upgrades.ORDER[upg_index]
	if not Upgrades.research(owner, key): return
	if owner == GameState.en_id:
		SFX.play("age", -6.0)
		hud.show_toast(Lang.t("uz_kutatas") % [
			Lang.t("upg_" + key), Upgrades.level(owner, key)])
		hud.refresh_building_panel()

# --- Csapatszállítás ---
#
# A szárazföldiek felszállnak a hajóra, a hajó átviszi őket, és a túlparton
# kirakja. A távoli egységek előbb odamennek a hajóhoz — a beszállás a
# hajó mellett történik (lásd Unit._think), nem a pálya túlvégéről.
func do_board(ids: Array, ship_id: int, owner: int) -> void:
	var hajo := unit_by_nid(ship_id)
	if hajo == null or int(hajo.owner_id) != owner or not hajo.can_carry(): return
	var n := 0
	for u in _own_units(ids, owner):
		if u == hajo or u.naval or u.air: continue
		if hajo.cargo_free() <= 0: break
		u.board_order(hajo)
		n += 1
	if owner == GameState.en_id and n > 0:
		hud.show_toast(Lang.t("uz_beszallt") % n, 2.5)

func do_unload(ids: Array, pos: Vector2, owner: int) -> void:
	for u in _own_units(ids, owner):
		if not u.can_carry() or u.cargo.is_empty(): continue
		# A hajó előbb odamegy a partra, és ott teszi ki a csapatot.
		u.unload_order(pos)

func do_train(building_id: int, role: String, owner: int) -> void:
	var b := building_by_nid(building_id)
	if b == null or int(b.owner_id) != owner: return
	if not (role in b.trainable()): return
	b.enqueue_unit(role)

# --- KIKÖTŐMENÜ (kalózvilág, index.html 29/D) ---
#
# A saját karibi városodból építhetsz és toborozhatsz anélkül, hogy
# odaküldenél egy munkást: a város NÉPE húzza fel az épületet, a hajót
# pedig a kikötő állítja ki. Idegen városban ez nem megy — Nassauból nem
# lehet Santiagót igazgatni.
#
# A városban építhető épületek sorrendje: elöl a termelés, mert a
# városban az számít. Fal, kaszárnya, kikötő és repülőtér ide nem való.
const PORT_BUILDS := ["farm", "goldmine", "sugar", "house", "market",
	"tower", "hospital", "academy", "smith"]
# A kalózvárosban CSAK hajót lehet toborozni — gyalogost nem.
const PORT_SHIPS := ["transport", "warship", "galleon"]

func _port_ok(kulcs: String, owner: int) -> bool:
	if cities == null or not is_instance_valid(cities): return false
	if not cities.varosok.has(kulcs): return false
	return cities.owner_of(kulcs) == owner

func _port_deny(owner: int, kulcs_szoveg: String) -> void:
	if owner != GameState.en_id: return
	hud.show_toast(Lang.t(kulcs_szoveg), 2.5)
	SFX.play("deny")

func do_port_build(kulcs: String, tipus: String, owner: int) -> void:
	if not (tipus in PORT_BUILDS): return
	if not _port_ok(kulcs, owner):
		_port_deny(owner, "pm_nem_epithetsz"); return
	var cost := build_cost(owner, tipus)
	if not GameState.can_pay(owner, cost):
		_port_deny(owner, "pm_nincs_anyag"); return
	# Helyet a város körül keresünk, kifelé haladó gyűrűkben.
	var p: Vector2 = cities.city_pos(kulcs)
	var hely := Vector2.ZERO
	var megvan := false
	var r := 70.0
	while r <= 320.0 and not megvan:
		for i in range(20):
			var a := float(i) * TAU / 20.0
			var q := p + Vector2(cos(a), sin(a)) * r
			if not can_place(tipus, q): continue
			hely = q
			megvan = true
			break
		r += 26.0
	if not megvan:
		_port_deny(owner, "pm_nincs_hely"); return
	if not GameState.pay(owner, cost): return
	var b := spawn_building(tipus, owner, hely, false)
	b.maga_epul = true               # a város népe húzza fel
	if owner == GameState.en_id:
		Achievements.bump("builds")
		SFX.play("build")
		hud.show_toast(Lang.t("pm_epul") % [hud.build_name(tipus),
			cities.city_name(kulcs)], 3.0)

func do_port_train(kulcs: String, role: String, owner: int) -> void:
	if not (role in PORT_SHIPS): return
	if not _port_ok(kulcs, owner):
		_port_deny(owner, "pm_nem_epithetsz"); return
	# Ahol a legrövidebb a sor, ott áll ki a hajó. Elsőbbsége a VÁROS
	# kikötőinek van; ha ott nincs, bárhol jó a birodalomban.
	var b := _shortest_yard(role, owner, cities.city_buildings(kulcs, owner))
	if b == null:
		b = _shortest_yard(role, owner,
			get_tree().get_nodes_in_group("buildings"))
	if b == null:
		_port_deny(owner, "pm_nincs_kikoto"); return
	if not GameState.can_pay(owner, Building.train_cost(owner, role)):
		_port_deny(owner, "pm_nincs_anyag"); return
	b.enqueue_unit(role)
	if owner == GameState.en_id: SFX.play("click")

func _shortest_yard(role: String, owner: int, jeloltek: Array) -> Node:
	var best: Node = null
	var bq := 99
	for b in jeloltek:
		if not is_instance_valid(b) or int(b.owner_id) != owner: continue
		if not b.is_ready() or not (role in b.trainable()): continue
		var q: int = b.train_queue.size()
		if q < bq:
			bq = q
			best = b
	return best

func do_rally(building_id: int, pos: Vector2, node_id: int,
			  foe_id: int, owner: int) -> void:
	var b := building_by_nid(building_id)
	if b == null or int(b.owner_id) != owner: return
	var n := node_by_nid(node_id)
	var f: Node = unit_by_nid(foe_id)
	if f == null: f = building_by_nid(foe_id)
	b.set_rally(pos, n, f)

func do_era(owner: int) -> void:
	var age := GameState.get_age(owner)
	if age >= 3: return
	if not GameState.pay(owner, Style.ERA_COST[age]): return
	GameState.advance_era(owner)

func _issue_order(wp: Vector2) -> void:
	# Kijelölt saját épületnél a jobb gomb a gyülekezőhelyet állítja.
	if selected_units.is_empty():
		if is_instance_valid(selected_bld) and selected_bld.has_method("set_rally"):
			set_rally_at(wp)
		return
	var enemy := _enemy_at(wp)
	var node := _resource_at(wp)
	var site := _site_at(wp)
	var hajo := _own_transport_at(wp)
	# A parancs azonosítókkal utazik, hogy hálózaton is átvihető legyen.
	var ids: Array = []
	for u in selected_units:
		if is_instance_valid(u): ids.append(int(u.nid))
	if ids.is_empty(): return
	# SAJÁT SZÁLLÍTÓHAJÓRA kattintva a kijelölt szárazföldiek beszállnak.
	if hajo != null and not selected_units.has(hajo):
		send_cmd("board", [ids, nid_of(hajo)])
		SFX.play("click")
		return
	# Rakománnyal teli hajó + szárazföldi kattintás = partra szállás.
	if _has_loaded_transport():
		send_cmd("unload", [ids, wp])
		SFX.play("click")
		return
	if enemy != null:
		send_cmd("attack", [ids, nid_of(enemy)])
	elif site != null:
		# Az építkezésre küldés helyi ügy: a munkás a saját épületéhez megy.
		for u in selected_units:
			if is_instance_valid(u) and u.role in ["worker", "fisher"] \
					and u.has_method("build_at"):
				u.build_at(site)
	elif node != null:
		send_cmd("gather", [ids, nid_of(node)])
	else:
		send_cmd("move", [ids, wp])
	SFX.play("click")

# --- Gyülekezőpont ---
#
# A kijelölt épület gyülekezőpontja: ide indulnak a frissen kiképzett
# egységek. Jobb gombbal bárhová, vagy a képzési panel "Gyülekező"
# gombjával fegyverezve, bal gombbal.
func set_rally_at(wp: Vector2) -> void:
	if not is_instance_valid(selected_bld): return
	if not selected_bld.has_method("set_rally"): return
	send_cmd("rally", [nid_of(selected_bld), wp,
		nid_of(_resource_at(wp)), nid_of(_enemy_at(wp))])
	_rally_mode = false
	SFX.play("click")
	var k: String = selected_bld.rally_kind()
	if k == "": k = "point"          # hálózaton a jelzés a válasszal jön
	hud.show_toast(Lang.t("gyulekezo_" + k), 3.5)

func set_rally_mode(on: bool) -> void:
	_rally_mode = on and is_instance_valid(selected_bld)
	if _rally_mode:
		set_build_mode("")
		hud.show_toast(Lang.t("gyulekezo_kijelol"), 4.0)

func rally_mode() -> bool:
	return _rally_mode

# Befejezetlen saját épület a kattintás helyén — ide építeni lehet küldeni.
func _site_at(wp: Vector2) -> Node:
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if not is_instance_valid(b) or b.is_ready(): continue
		var half: Vector2 = Building.size_of(b.tipus) * 0.5
		if Rect2(b.global_position - half, half * 2.0).grow(16.0).has_point(wp):
			return b
	return null

func _resource_at(wp: Vector2) -> Node2D:
	for n in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(n): continue
		if n.global_position.distance_to(wp) < n.radius + 12.0:
			return n
	return null

func _enemy_at(wp: Vector2) -> Node:
	# Szövetséges (azonos csapatszámú) félre nem támadunk rá.
	for n in get_tree().get_nodes_in_group("units"):
		if not GameState.hostile(GameState.en_id, int(n.owner_id)): continue
		if n.global_position.distance_to(wp) < 22.0:
			return n
	for b in get_tree().get_nodes_in_group("buildings"):
		if not GameState.hostile(GameState.en_id, int(b.owner_id)): continue
		var half: Vector2 = Building.size_of(b.tipus) * 0.5
		if Rect2(b.global_position - half, half * 2.0).has_point(wp):
			return b
	return null

# Saját szállítóhajó a kattintás alatt. Erre kattintva szállnak be a
# kijelölt szárazföldi egységek.
# Van-e a kijelölésben megrakott szállítóhajó? Ilyenkor a szárazföldre
# kattintás partra szállást jelent, nem egyszerű mozgást.
func _has_loaded_transport() -> bool:
	for u in selected_units:
		if is_instance_valid(u) and u.can_carry() and not u.cargo.is_empty():
			return true
	return false

func _own_transport_at(wp: Vector2) -> Node:
	for n in get_tree().get_nodes_in_group("player_units"):
		if not is_instance_valid(n) or not n.can_carry(): continue
		if n.global_position.distance_to(wp) < n.radius + 20.0:
			return n
	return null

func _own_building_at(wp: Vector2) -> Node:
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if not is_instance_valid(b): continue
		var half: Vector2 = Building.size_of(b.tipus) * 0.5
		# A talp mellett a fölé magasodó sprite is fogadja a kattintást.
		var r := Rect2(b.global_position - half - Vector2(0, b.hit_radius()),
			Vector2(half.x * 2.0, half.y * 2.0 + b.hit_radius()))
		if r.has_point(wp):
			return b
	return null

func _update_sel_rect() -> void:
	var cur := get_viewport().get_mouse_position()
	var r := Rect2(_sel_screen, cur - _sel_screen).abs()
	sel_rect_ui.position = r.position
	sel_rect_ui.size     = r.size

func _finish_sel(end_pos: Vector2) -> void:
	var rect := Rect2(_sel_start, end_pos - _sel_start).abs()
	var click := rect.size.length() < 6.0
	# Egyetlen kattintásnál adjunk némi toleranciát.
	if click:
		rect = Rect2(end_pos - Vector2(14, 14), Vector2(28, 28))
	_clear_selection()
	for u in get_tree().get_nodes_in_group("player_units"):
		if rect.has_point(u.global_position):
			selected_units.append(u)
			if u.has_method("set_selected"): u.set_selected(true)
	# Ha nem fogtunk egységet, saját épületet is kijelölhetünk.
	if selected_units.is_empty() and click:
		var b := _own_building_at(end_pos)
		if b != null:
			selected_bld = b
			b.set_selected(true)
			hud.select_building(b)
			return
		# Nyersanyag-lelőhelyre kattintva látszik, mennyi van még benne.
		var n := _resource_at(end_pos)
		if n != null:
			selected_res = n
			n.set_selected(true)
			hud.select_resource(n)
			return
	hud.update_selection(selected_units)

# Egyetlen egység kijelölése kívülről (a flottasáv kattintása).
func select_only(u: Node) -> void:
	if not is_instance_valid(u): return
	_clear_selection()
	selected_units.append(u)
	if u.has_method("set_selected"): u.set_selected(true)
	hud.update_selection(selected_units)

func _clear_selection() -> void:
	_rally_mode = false
	for u in selected_units:
		if is_instance_valid(u) and u.has_method("set_selected"):
			u.set_selected(false)
	selected_units.clear()
	if is_instance_valid(selected_bld):
		selected_bld.set_selected(false)
	selected_bld = null
	if is_instance_valid(selected_res):
		selected_res.set_selected(false)
	selected_res = null
	hud.select_building(null)
	hud.select_resource(null)
	hud.update_selection(selected_units)

func _toggle_pause() -> void:
	GameState.on = not GameState.on
	get_tree().paused = not GameState.on
	hud.set_paused(not GameState.on)
