class_name Terrain
extends Node2D

# A Terrain a WorldGen által generált világot tárolja és rajzolja ki:
#  - víztérkép (cellarács), ebből készül a szárazföldi és vízi navigáció
#  - dekoráció (fák, sziklák)
#  - kitermelhető erőforrás-csomópontok (ResNode)
#
# A WorldGen ezt az API-t használja:
#   apply_water_map(map, cell) / add_rock(pos) / add_tree(pos)
#   add_resource(kind, pos) / rebuild()

# Korszakonkénti talajszínek (az eredeti AGES[].style.ground / ground2).
# 0 = tavasz, 1 = nyár, 2 = ősz, 3 = tél.
const LAND_COLORS := [
	Color("5a8c3c"), Color("3f6b30"), Color("7a6a34"), Color("77807e"),
]
const LAND_ALTS := [
	Color("679a45"), Color("4a7a38"), Color("8a7a3c"), Color("848d8a"),
]

const SHORE_COLOR  := Color(0.76, 0.71, 0.48, 1.0)
const TREE_TRUNK   := Color(0.32, 0.22, 0.13, 1.0)
const TREE_LEAF    := Color(0.16, 0.36, 0.16, 1.0)
const ROCK_COLOR   := Color(0.45, 0.45, 0.48, 1.0)
const ROCK_SHADE   := Color(0.32, 0.32, 0.35, 1.0)

# Az eredeti fűcsempéje 384px; itt 192 is elég, mert a mintát a
# draw_texture_rect ismétli.
const GRASS_TILE := 192

const RES_COLORS := {
	"wood_node":  Color(0.42, 0.28, 0.15, 1.0),
	"stone_node": Color(0.55, 0.55, 0.58, 1.0),
	"gold_node":  Color(0.86, 0.71, 0.20, 1.0),
	"food_node":  Color(0.80, 0.30, 0.32, 1.0),
	"fish_node":  Color(0.45, 0.78, 0.86, 1.0),
}

# Egy kitermelhető erőforrás-csomópont. Belső osztály, hogy a
# CLAUDE.md mappastruktúrája változatlan maradjon.
class ResNode extends Node2D:
	var kind: String = "wood_node"
	var amount: float = 900.0
	var max_amount: float = 900.0
	var color: Color = Color.WHITE
	var radius: float = 15.0
	var selected: bool = false
	# Hálózati azonosító. A pálya minden gépen ugyanabból a magból készül,
	# ezért a lelőhelyek KELETKEZÉSI SORRENDJE is azonos — így a sorszám
	# külön egyeztetés nélkül ugyanarra a foltra mutat mindenkinél.
	var nid: int = 0
	# A mennyiség-címke külön csomóponton ül, magas z-vel: így a mellette
	# dolgozó munkások nem takarják el. (A lelőhely maga a terep rétegében
	# marad, tehát az egységek átsétálnak előtte.)
	var _label: Node2D = null
	# A halraj él: a halak körbe-körbe úsznak a folton. Az idő itt gyűlik,
	# és ebből számoljuk a helyüket — csak a halrajnál kell _process.
	var _t: float = 0.0
	var _redraw_t: float = 0.0

	func _ready() -> void:
		add_to_group("resources")
		z_index = 1
		_label = Node2D.new()
		_label.z_index = 60
		_label.visible = false
		_label.draw.connect(_draw_label)
		add_child(_label)
		# A halak csak akkor úsznak, ha LÁTSZANAK is. A pályán tucatnyi
		# halraj van, de egyszerre legfeljebb egy-kettő van a képernyőn —
		# a többi mozgatása tiszta veszteség a gyenge gépeken. Alacsony
		# részletességen egyáltalán nem mozognak.
		set_process(kind == "fish_node" and Settings.lively()
			and not Settings.cull_offscreen)
		if kind == "fish_node" and Settings.lively() and Settings.cull_offscreen:
			var vis := VisibleOnScreenNotifier2D.new()
			vis.rect = Rect2(-radius * 2.0, -radius * 2.0,
				radius * 4.0, radius * 4.0)
			vis.screen_entered.connect(func() -> void: set_process(true))
			vis.screen_exited.connect(func() -> void: set_process(false))
			add_child(vis)

	# A halak mozgása. Nem képkockánként rajzolunk újra, hanem ~14-szer
	# másodpercenként: a mozgás így is folyamatos, a terhelés viszont nem nő.
	func _process(delta: float) -> void:
		_t += delta
		_redraw_t += delta
		if _redraw_t < 0.07: return
		_redraw_t = 0.0
		queue_redraw()

	func harvest(want: float) -> float:
		var got := minf(want, amount)
		amount -= got
		if amount <= 0.0:
			queue_free()
		else:
			queue_redraw()
			if selected and _label != null: _label.queue_redraw()
		return got

	func set_selected(val: bool) -> void:
		selected = val
		queue_redraw()
		if _label != null:
			_label.visible = val
			_label.queue_redraw()

	# Hány munkás dolgozik éppen rajta — a becsült kimerülési időhöz.
	func worker_count() -> int:
		var n := 0
		for u in get_tree().get_nodes_in_group("units"):
			if is_instance_valid(u) and u.gather_node() == self:
				n += 1
		return n

	# A lelőhelyek nem egyszínű körök: erdőfolt, sziklacsoport, ércadag,
	# bogyós bokor, illetve halraj — hogy ránézésre megkülönböztethetőek
	# legyenek a térképen.
	func _draw() -> void:
		var frac := clampf(amount / maxf(max_amount, 1.0), 0.22, 1.0)
		var r := radius * frac
		match kind:
			"wood_node":  _draw_trees(r)
			"stone_node": _draw_rocks(r, ROCK_BASE, false)
			"gold_node":  _draw_rocks(r, ORE_BASE, true)
			"food_node":  _draw_bush(r)
			"fish_node":  _draw_fish(r)
			_:            draw_circle(Vector2.ZERO, r, color)
		if selected: _draw_selection()

	# --- Rajzsegédek ---
	#
	# Minden lelőhely ugyanúgy néz ki minden újrarajzoláskor, de a foltok
	# egymástól különböznek: a véletlent a csomópont helyéből vetjük el.
	func _rng() -> RandomNumberGenerator:
		var g := RandomNumberGenerator.new()
		g.seed = hash(Vector2i(int(position.x), int(position.y)))
		return g

	# Lapos, elnyújtott földi árnyék (a fény felülről-balról jön).
	func _shadow(c: Vector2, rx: float, ry: float, a: float = 0.20) -> void:
		draw_colored_polygon(_ellipse_pts(c, Vector2(rx, ry), 16),
			Color(0.05, 0.06, 0.03, a))

	func _ellipse_pts(c: Vector2, rad: Vector2, seg: int) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in range(seg):
			var a := TAU * float(i) / float(seg)
			pts.append(c + Vector2(cos(a) * rad.x, sin(a) * rad.y))
		return pts

	# Szabálytalan, sokszögű kő: a sugár körönként ingadozik.
	func _rock_pts(c: Vector2, rad: float, g: RandomNumberGenerator,
			squash: float = 0.78) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var n := 7
		var off := g.randf_range(0.0, TAU)
		for i in range(n):
			var a := off + TAU * float(i) / float(n)
			var d := rad * g.randf_range(0.72, 1.0)
			pts.append(c + Vector2(cos(a) * d, sin(a) * d * squash))
		return pts

	# Kijelölve: gyűrű a földön a folt körül.
	func _draw_selection() -> void:
		var rr := radius + 6.0
		var pts := PackedVector2Array()
		for i in range(25):
			var a := TAU * float(i) / 24.0
			pts.append(Vector2(cos(a) * rr, sin(a) * rr * 0.62))
		draw_polyline(pts, Color(0.98, 0.88, 0.45, 0.95), 2.0)

	# A kijelölt lelőhely fölött a még kitermelhető mennyiség.
	func _draw_label() -> void:
		if not selected: return
		var font := ThemeDB.fallback_font
		if font == null: return
		var frac := clampf(amount / maxf(max_amount, 1.0), 0.0, 1.0)
		var txt := "%d" % int(ceil(amount))
		const FS := 11
		var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
		var box := Rect2(-tw * 0.5 - 5.0, -radius - 40.0, tw + 10.0, 15.0)
		_label.draw_rect(box, Color(0, 0, 0, 0.6), true)
		# A készlet fogyását vékony sáv is mutatja a doboz alján.
		var bar_col: Color = Terrain.RES_COLORS.get(kind, Color.WHITE)
		_label.draw_rect(Rect2(box.position.x, box.end.y - 2.0,
			box.size.x * frac, 2.0), bar_col, true)
		_label.draw_string(font, box.position + Vector2(5.0, 11.0), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Color(0.98, 0.94, 0.82))

	# --- Erdőfolt ---
	#
	# Nem három egyforma zöld pötty, hanem egy kis liget: eltérő magasságú
	# fák, barna törzzsel, három árnyalatú lombbal. A hátsó fák előbb
	# kerülnek fel, így a ligetnek mélysége lesz.
	const TRUNK      := Color(0.30, 0.21, 0.13)
	const TRUNK_LIT  := Color(0.40, 0.29, 0.18)
	const LEAF_DARK  := Color(0.10, 0.24, 0.11)
	const LEAF_MID   := Color(0.16, 0.37, 0.16)
	const LEAF_LIT   := Color(0.30, 0.53, 0.24)

	func _draw_trees(r: float) -> void:
		var g := _rng()
		var db := 5 + (g.randi() % 2)
		var spots: Array = []
		for i in range(db):
			var a := TAU * float(i) / float(db) + g.randf_range(-0.35, 0.35)
			var d := r * g.randf_range(0.12, 0.58)
			spots.append([Vector2(cos(a) * d, sin(a) * d * 0.72),
				g.randf_range(0.80, 1.20)])
		# Hátulról előre: a lentebb álló fa takarja a fentebbit.
		spots.sort_custom(func(x, y): return x[0].y < y[0].y)
		for s in spots:
			var p: Vector2 = s[0]
			var k: float = s[1]
			var h := r * 0.66 * k               # a fa magassága
			var cr := r * 0.46 * k              # a lomb sugara
			_shadow(p + Vector2(cr * 0.3, 1.5), cr * 0.95, cr * 0.34, 0.22)
			# Törzs: lefelé szélesedő.
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(-cr * 0.16, 0.0), p + Vector2(cr * 0.16, 0.0),
				p + Vector2(cr * 0.10, -h),   p + Vector2(-cr * 0.10, -h)]),
				TRUNK)
			draw_line(p + Vector2(-cr * 0.10, 0.0), p + Vector2(-cr * 0.06, -h),
				TRUNK_LIT, 1.0)
			# Lomb: sötét alap, középső tömeg, megvilágított bal felső folt.
			var top := p + Vector2(0.0, -h)
			draw_colored_polygon(_ellipse_pts(top + Vector2(0.0, cr * 0.18),
				Vector2(cr * 1.05, cr * 0.90), 14), LEAF_DARK)
			draw_colored_polygon(_ellipse_pts(top + Vector2(cr * 0.10, -cr * 0.10),
				Vector2(cr * 0.82, cr * 0.72), 14), LEAF_MID)
			draw_colored_polygon(_ellipse_pts(top + Vector2(-cr * 0.28, -cr * 0.34),
				Vector2(cr * 0.46, cr * 0.40), 12), LEAF_LIT)

	# --- Kőfejtő / érclelőhely ---
	#
	# Szögletes sziklatömbök: sötét alap, világos felső lap és éles perem —
	# a kerek foltok műanyagnak néztek ki.
	const ROCK_BASE := Color(0.47, 0.47, 0.50)
	const ORE_BASE  := Color(0.40, 0.38, 0.35)
	const GOLD_VEIN := Color(0.90, 0.74, 0.22)
	const GOLD_LIT  := Color(1.00, 0.92, 0.55)

	func _draw_rocks(r: float, base: Color, ore: bool) -> void:
		var g := _rng()
		var db := 3 + (g.randi() % 3)
		var spots: Array = []
		for i in range(db):
			var a := TAU * float(i) / float(db) + g.randf_range(-0.4, 0.4)
			var d := r * g.randf_range(0.05, 0.52)
			spots.append([Vector2(cos(a) * d, sin(a) * d * 0.66),
				g.randf_range(0.55, 1.0)])
		spots.sort_custom(func(x, y): return x[0].y < y[0].y)
		_shadow(Vector2(1.0, r * 0.26), r * 0.92, r * 0.34, 0.20)
		for s in spots:
			var p: Vector2 = s[0]
			var rad: float = r * 0.46 * float(s[1])
			var body := _rock_pts(p, rad, g)
			draw_colored_polygon(body, base.darkened(0.22))
			# Felső lap: ugyanaz a forma összenyomva, feljebb tolva.
			var topf := PackedVector2Array()
			for v in body:
				topf.append(Vector2(p.x + (v.x - p.x) * 0.78,
					p.y + (v.y - p.y) * 0.52 - rad * 0.30))
			draw_colored_polygon(topf, base.lightened(0.16))
			draw_colored_polygon(_rock_pts(p + Vector2(-rad * 0.22, -rad * 0.50),
				rad * 0.34, g, 0.62), base.lightened(0.38))
			var edge := body
			edge.append(body[0])
			draw_polyline(edge, base.darkened(0.5), 1.0)
			if ore:
				# Aranyerek: rövid, vastag vonalak a tömb oldalán, meg egy-két
				# kibukkanó rög.
				for _j in range(2):
					var a2 := g.randf_range(0.0, TAU)
					var q := p + Vector2(cos(a2), sin(a2) * 0.6) * rad * 0.42
					draw_line(q, q + Vector2(cos(a2 + 1.2), sin(a2 + 1.2)) * rad * 0.34,
						GOLD_VEIN, maxf(1.5, rad * 0.13))
				var n := p + Vector2(rad * 0.16, -rad * 0.16)
				draw_colored_polygon(_rock_pts(n, rad * 0.22, g, 0.8), GOLD_VEIN)
				draw_circle(n + Vector2(-rad * 0.06, -rad * 0.07), rad * 0.08, GOLD_LIT)

	# --- Bogyós bokor ---
	const BUSH_DARK := Color(0.11, 0.26, 0.12)
	const BUSH_MID  := Color(0.19, 0.40, 0.18)
	const BUSH_LIT  := Color(0.31, 0.54, 0.25)
	const BERRY     := Color(0.74, 0.14, 0.18)
	const BERRY_LIT := Color(0.95, 0.45, 0.42)

	func _draw_bush(r: float) -> void:
		var g := _rng()
		_shadow(Vector2(1.0, r * 0.42), r * 0.86, r * 0.30, 0.22)
		# Több egymásba érő levélcsomó, nem egy nagy kör.
		draw_colored_polygon(_ellipse_pts(Vector2(0, r * 0.06),
			Vector2(r * 0.88, r * 0.66), 16), BUSH_DARK)
		for i in range(5):
			var a := TAU * float(i) / 5.0 + g.randf_range(-0.3, 0.3)
			var p := Vector2(cos(a) * r * 0.40, sin(a) * r * 0.26 - r * 0.10)
			draw_colored_polygon(_ellipse_pts(p,
				Vector2(r * g.randf_range(0.30, 0.44),
					r * g.randf_range(0.24, 0.34)), 12), BUSH_MID)
		draw_colored_polygon(_ellipse_pts(Vector2(-r * 0.24, -r * 0.30),
			Vector2(r * 0.34, r * 0.24), 12), BUSH_LIT)
		# Bogyók: fürtökben, nem egyenletesen szétszórva.
		for i in range(9):
			var a2 := g.randf_range(0.0, TAU)
			var d := g.randf_range(0.15, 0.70)
			var q := Vector2(cos(a2) * r * 0.72 * d, sin(a2) * r * 0.52 * d - r * 0.06)
			var br := r * 0.095
			draw_circle(q, br, BERRY)
			draw_circle(q + Vector2(-br * 0.32, -br * 0.34), br * 0.34, BERRY_LIT)

	# --- Halraj ---
	const FISH_BACK  := Color(0.26, 0.42, 0.55, 0.92)
	const FISH_BELLY := Color(0.68, 0.84, 0.90, 0.92)

	# A raj ÉL: minden hal a saját ellipszisén köröz, kicsit más ütemben és
	# irányban, közben oldalra billen a farkával. A pálya és az ütem a
	# csomópont helyéből jön, tehát mentés/betöltés után is ugyanaz.
	# A halak pályája NEM változik, csak a helyük a pályán. Ezért a
	# paramétereket egyszer számoljuk ki, és nem minden rajzoláskor
	# vetünk új véletlent — másodpercenként tizennégyszer újraépíteni egy
	# véletlenszám-generátort a gyenge gépeken fölösleges teher.
	var _fish: Array = []

	func _make_fish(r: float) -> void:
		var g := _rng()
		_fish.clear()
		for i in range(5):
			var seb: float = g.randf_range(0.28, 0.62) \
				* (-1.0 if g.randf() < 0.5 else 1.0)
			var rx: float = r * g.randf_range(0.22, 0.60)
			_fish.append({
				"fazis": g.randf_range(0.0, TAU),
				"seb": seb,
				"rx": rx,
				"ry": rx * g.randf_range(0.35, 0.60),
				"kozep": Vector2(g.randf_range(-0.18, 0.18) * r,
					g.randf_range(-0.14, 0.14) * r),
				"s": g.randf_range(0.8, 1.15) * r * 0.30,
			})

	func _draw_fish(r: float) -> void:
		if _fish.is_empty(): _make_fish(r)
		# Fodrozódás a víz színén — lassan tágul, mint a gyűrűző hullám.
		for i in range(2):
			var puls := 1.0 + 0.06 * sin(_t * 1.1 + float(i) * 1.7)
			var rr := r * (0.62 + 0.28 * float(i)) * puls
			var ring := _ellipse_pts(Vector2.ZERO, Vector2(rr, rr * 0.55), 20)
			ring.append(ring[0])
			draw_polyline(ring, Color(0.85, 0.95, 1.0, 0.22 - 0.08 * float(i)), 1.0)
		for f in _fish:
			var fazis: float = f["fazis"]
			var seb: float = f["seb"]
			var rx: float = f["rx"]
			var ry: float = f["ry"]
			var kozep: Vector2 = f["kozep"]
			var s: float = f["s"]
			var szog := fazis + _t * seb
			var p := kozep + Vector2(cos(szog) * rx, sin(szog) * ry)
			# Az orra a mozgás irányába néz; oldalnézetben ebből csak az
			# számít, merre úszik vízszintesen.
			var vx := -sin(szog) * rx * seb
			var dir := 1.0 if vx >= 0.0 else -1.0
			# Farokcsapás: a test hátulja ide-oda leng.
			var csap := sin(_t * 6.0 + fazis) * s * 0.28
			# Test: megnyújtott ellipszis, farok: háromszög.
			draw_colored_polygon(_ellipse_pts(p, Vector2(s, s * 0.42), 12), FISH_BACK)
			draw_colored_polygon(_ellipse_pts(p + Vector2(0, s * 0.12),
				Vector2(s * 0.72, s * 0.22), 10), FISH_BELLY)
			var farok := p + Vector2(-dir * s * 0.92, 0.0)
			draw_colored_polygon(PackedVector2Array([
				farok,
				farok + Vector2(-dir * s * 0.46, -s * 0.34 + csap),
				farok + Vector2(-dir * s * 0.46, s * 0.34 + csap)]), FISH_BACK)
			draw_circle(p + Vector2(dir * s * 0.58, -s * 0.10), s * 0.09,
				Color(0.06, 0.10, 0.14, 0.9))

var water_cell : int   = 16
var water_map  : Array = []
var grid_w     : int   = 0
var grid_h     : int   = 0

var trees      : PackedVector2Array = PackedVector2Array()
var rocks      : PackedVector2Array = PackedVector2Array()

var _land_rects  : Array[Rect2] = []
var _water_rects : Array[Rect2] = []
var _shore_lines : Array = []

var land_region  : NavigationRegion2D
var water_region : NavigationRegion2D
var grass_tex    : Texture2D = null
# A szárazföld-maszk a talajshadernek ÉS a kistérképnek is kell.
var land_mask_tex: Texture2D = null
var _age         : int = 0

@onready var land_sprite := $LandSprite as Sprite2D

func _ready() -> void:
	z_index = 0
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_age = GameState.get_age()
	_make_grass_tex()
	_setup_land_sprite()
	GameState.era_changed.connect(_on_era_changed)
	# Az aljnövényzet csak a látómezőben készül el, ezért a kamera mozgását
	# figyelni kell (lásd `_process`). Alacsony részletességen nincs dísz,
	# tehát figyelni sincs mit.
	set_process(Settings.detail >= 1)
	Settings.changed.connect(_on_settings_changed)
	land_region = NavigationRegion2D.new()
	land_region.name = "LandNav"
	land_region.navigation_layers = 1
	add_child(land_region)
	water_region = NavigationRegion2D.new()
	water_region.name = "WaterNav"
	water_region.navigation_layers = 2
	add_child(water_region)
	# A szomszédos navigációs téglalapok élei csak akkor kapcsolódnak össze,
	# ha van elég nagy összekötési távolság.
	var map := get_world_2d().navigation_map
	NavigationServer2D.map_set_edge_connection_margin(map, 8.0)
	NavigationServer2D.map_set_cell_size(map, 1.0)

# --- WorldGen API ---

# A tájtípus talajszíne ("" = a korszak szerinti alapszín).
var _ground_override: String = ""

func set_ground_override(hex: String) -> void:
	_ground_override = hex

func apply_water_map(map: Array, cell: int = 16) -> void:
	water_map  = map
	water_cell = cell
	grid_h = map.size()
	grid_w = (map[0] as Array).size() if grid_h > 0 else 0
	_land_rects  = _extract_rects(false)
	_water_rects = _extract_rects(true)
	_shore_lines = _extract_shore()
	_upload_land_mask()

# A talajsprite egyetlen rajzparanccsal fedi le a világot: a maszk mondja
# meg, hol van föld, a shader oda csempézi a fűmintát.
func _setup_land_sprite() -> void:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	land_sprite.texture = ImageTexture.create_from_image(img)
	land_sprite.centered = false
	land_sprite.scale = Vector2(GameState.WORLD_W / 2.0, GameState.WORLD_H / 2.0)
	var mat := land_sprite.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("grass_tex", grass_tex)
		mat.set_shader_parameter("world_size",
			Vector2(GameState.WORLD_W, GameState.WORLD_H))
		mat.set_shader_parameter("tile_px", float(GRASS_TILE))
		mat.set_shader_parameter("noise_tex", _noise_texture())
		mat.set_shader_parameter("noise_px", float(NOISE_TILE))
		mat.set_shader_parameter("detail", Settings.detail)

# --- Zajtextúra ---
#
# A talaj- és a vízshader eddig KÉPPONTONKÉNT számolta a zajt (szinuszokból),
# nyolcszor-tízszer. Egy gyenge, integrált videokártyán ez volt a játék
# legdrágább művelete. Ugyanaz a minta egy 256x256-os, ismétlődő
# textúrából egyetlen olvasással megvan — a kép ugyanolyan marad.
const NOISE_TILE := 256
static var _noise_tex: Texture2D = null

static func _noise_texture() -> Texture2D:
	if _noise_tex != null: return _noise_tex
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_VALUE
	nz.seed = 20240913
	nz.frequency = 1.0 / 16.0
	# Ismétlődő textúra: a szélek illeszkednek, így nincs látható varrat.
	nz.domain_warp_enabled = false
	var img := Image.create(NOISE_TILE, NOISE_TILE, false, Image.FORMAT_L8)
	for y in range(NOISE_TILE):
		for x in range(NOISE_TILE):
			# Két zajérték keverése a széleken: ettől lesz körbeérő a minta.
			var a := (nz.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var b := (nz.get_noise_2d(float(x - NOISE_TILE), float(y)) + 1.0) * 0.5
			var c := (nz.get_noise_2d(float(x), float(y - NOISE_TILE)) + 1.0) * 0.5
			var d := (nz.get_noise_2d(float(x - NOISE_TILE),
				float(y - NOISE_TILE)) + 1.0) * 0.5
			var fx := float(x) / float(NOISE_TILE)
			var fy := float(y) / float(NOISE_TILE)
			var v := lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	_noise_tex = ImageTexture.create_from_image(img)
	return _noise_tex

func _upload_land_mask() -> void:
	if grid_h == 0: return
	# A pályaméret játszmánként változik (kalózvilág), ezért a sprite
	# nyújtását itt állítjuk be újra, amikor a víztérkép megérkezett.
	land_sprite.scale = Vector2(GameState.WORLD_W / 2.0, GameState.WORLD_H / 2.0)
	var mat_ws := land_sprite.material as ShaderMaterial
	if mat_ws:
		mat_ws.set_shader_parameter("world_size",
			Vector2(GameState.WORLD_W, GameState.WORLD_H))
	# A maszk három adatot visz a shadereknek:
	#   R = szárazföld (1) vagy víz (0)
	#   G = mennyire van BELJEBB a parttól (0 = partvonal, 1 = belföld)
	#   B = mennyire MÉLY a víz (0 = sekély part, 1 = nyílt víz)
	# Ebből lesz a homokos part és a sekély vizű zátony — enélkül a
	# szárazföld és a tenger éles, rajzolt vonallal ütközik.
	var land_d := _distance_field(false)
	var water_d := _distance_field(true)
	_init_biome()
	var mask := Image.create(grid_w, grid_h, false, Image.FORMAT_RGBA8)
	var c := float(water_cell)
	for y in range(grid_h):
		var row: Array = water_map[y]
		for x in range(grid_w):
			var i := y * grid_w + x
			var land := 0.0 if bool(row[x]) else 1.0
			# Az A csatorna a BIOM: 0 = dús rét, 0.5 = száraz puszta,
			# 1 = sziklás felföld. A shader ebből keveri a talaj színét.
			mask.set_pixel(x, y, Color(land,
				clampf(float(land_d[i]) / SHORE_CELLS, 0.0, 1.0),
				clampf(float(water_d[i]) / SHALLOW_CELLS, 0.0, 1.0),
				biome_at(Vector2((float(x) + 0.5) * c, (float(y) + 0.5) * c))))
	land_mask_tex = ImageTexture.create_from_image(mask)
	var mat := land_sprite.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("land_mask", land_mask_tex)
	# A vízfelület ugyanebből a maszkból rajzolja a sekélyt és a hab-
	# csíkot, ezért oda is át kell adni.
	var main := get_tree().get_first_node_in_group("main")
	if main and main.water_sprite:
		var wm := main.water_sprite.material as ShaderMaterial
		if wm:
			wm.set_shader_parameter("land_mask", land_mask_tex)
			wm.set_shader_parameter("use_mask", true)
			wm.set_shader_parameter("world_size",
				Vector2(GameState.WORLD_W, GameState.WORLD_H))
			wm.set_shader_parameter("noise_tex", _noise_texture())
			wm.set_shader_parameter("noise_px", float(NOISE_TILE))
			wm.set_shader_parameter("detail", Settings.detail)

# Hány cella széles a homokos part, illetve a sekély víz sávja.
const SHORE_CELLS := 1.6
const SHALLOW_CELLS := 4.0

# --- Biomok ---
#
# A pálya nem egyetlen egyforma zöld szőnyeg: nagy léptékű zaj osztja
# tájakra. 0 körül dús rét, 0.5 körül száraz puszta, 1 felé sziklás
# felföld. Ugyanezt az értéket használja a talajshader (a maszk A
# csatornája) és a díszítés-kirakás is, ezért egy helyen áll a képlet.
var _biome_noise: FastNoiseLite = null

func _init_biome() -> void:
	if _biome_noise != null: return
	_biome_noise = FastNoiseLite.new()
	_biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_biome_noise.seed = GameState.sim_mag & 0xFFFF
	# Nagy foltok: a pálya 3-5 tájra bomlik, nem szemcsés mozaikra.
	_biome_noise.frequency = 0.00085
	_biome_noise.fractal_octaves = 3

func biome_at(world_pos: Vector2) -> float:
	_init_biome()
	var n := (_biome_noise.get_noise_2d(world_pos.x, world_pos.y) + 1.0) * 0.5
	# A simplex zaj ritkán éri el a szélsőértékeket, ezért kifeszítjük:
	# enélkül a pálya végig a középső (fakó) tájba esne.
	return clampf((n - 0.5) * 1.9 + 0.5, 0.0, 1.0)

# Melyik tájra való: 0 = rét (fák), 1 = puszta, 2 = felföld (sziklák).
func biome_kind(world_pos: Vector2) -> int:
	var b := biome_at(world_pos)
	if b < 0.42: return 0
	return 1 if b < 0.68 else 2

# Távolság a legközelebbi ellentétes típusú cellától, cellákban mérve.
# Egyszerű, néhány menetes terjesztés — a rács kicsi, ez bőven elég.
func _distance_field(for_water: bool) -> PackedInt32Array:
	var n := grid_w * grid_h
	var d := PackedInt32Array()
	d.resize(n)
	var maxd := int(ceil(maxf(SHORE_CELLS, SHALLOW_CELLS))) + 1
	for y in range(grid_h):
		var row: Array = water_map[y]
		for x in range(grid_w):
			var i := y * grid_w + x
			# Csak a saját típusú cellák kapnak távolságot, a többi 0.
			if bool(row[x]) != for_water:
				d[i] = 0
				continue
			d[i] = 0 if _touches_other(x, y, for_water) else maxd
	for _pass in range(maxd):
		for y in range(grid_h):
			for x in range(grid_w):
				var i := y * grid_w + x
				if d[i] == 0: continue
				var best := d[i]
				if x > 0:            best = mini(best, d[i - 1] + 1)
				if x < grid_w - 1:   best = mini(best, d[i + 1] + 1)
				if y > 0:            best = mini(best, d[i - grid_w] + 1)
				if y < grid_h - 1:   best = mini(best, d[i + grid_w] + 1)
				d[i] = best
	return d

func _touches_other(x: int, y: int, mine_is_water: bool) -> bool:
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _cell_water(x + o.x, y + o.y) != mine_is_water: return true
	return false

# A partvonal szakaszai: minden szárazföldi cella azon élei, ahol vízzel
# határos. Így a homoksáv csak a tényleges parton jelenik meg.
func _extract_shore() -> Array:
	var out: Array = []
	var c := float(water_cell)
	for y in range(grid_h):
		var row: Array = water_map[y]
		for x in range(grid_w):
			if bool(row[x]): continue
			var px := float(x) * c
			var py := float(y) * c
			if _cell_water(x, y - 1): out.append([Vector2(px, py), Vector2(px + c, py)])
			if _cell_water(x, y + 1): out.append([Vector2(px, py + c), Vector2(px + c, py + c)])
			if _cell_water(x - 1, y): out.append([Vector2(px, py), Vector2(px, py + c)])
			if _cell_water(x + 1, y): out.append([Vector2(px + c, py), Vector2(px + c, py + c)])
	return out

func _cell_water(x: int, y: int) -> bool:
	if y < 0 or y >= grid_h: return true
	var row: Array = water_map[y]
	if x < 0 or x >= row.size(): return true
	return bool(row[x])

func add_tree(pos: Vector2) -> void:
	trees.append(pos)
	_deco_kesz = false

func add_rock(pos: Vector2) -> void:
	rocks.append(pos)
	_deco_kesz = false

# --- A TEREP HATÁSA  (index.html 9/D) ---
#
# A tájtípusok nemcsak látványban különböznek: az erdő fedez, a sziklás
# magaslatról messzebbre látni, a parti homokban pedig nehéz a menet.
# Az egységek másodpercenként kétszer kérdezik meg — ezért a fákat és a
# sziklákat EGYSZER egy durva rácsba soroljuk be, és utána csak a rács
# egy-egy celláját nézzük meg. Enélkül kétszáz katona × ezer fa lenne
# minden lekérdezés.
const DECO_CELL := 64
const DECO_FA := 1
const DECO_SZIKLA := 2

var _deco: PackedByteArray = PackedByteArray()
var _deco_w: int = 0
var _deco_h: int = 0
var _deco_kesz: bool = false

func _build_deco_index() -> void:
	_deco_w = int(ceil(float(GameState.WORLD_W) / float(DECO_CELL))) + 1
	_deco_h = int(ceil(float(GameState.WORLD_H) / float(DECO_CELL))) + 1
	_deco = PackedByteArray()
	_deco.resize(_deco_w * _deco_h)
	_deco.fill(0)
	for p in trees: _deco_set(p, DECO_FA)
	for p in rocks: _deco_set(p, DECO_SZIKLA)
	_deco_kesz = true

func _deco_set(p: Vector2, jel: int) -> void:
	var x := int(p.x / DECO_CELL)
	var y := int(p.y / DECO_CELL)
	if x < 0 or y < 0 or x >= _deco_w or y >= _deco_h: return
	_deco[y * _deco_w + x] = _deco[y * _deco_w + x] | jel

func _deco_at(p: Vector2, jel: int) -> bool:
	if not _deco_kesz: _build_deco_index()
	var x := int(p.x / DECO_CELL)
	var y := int(p.y / DECO_CELL)
	# A szomszédos cellákat is nézzük: a fa a cella szélén is fedezéket ad.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cx := x + dx
			var cy := y + dy
			if cx < 0 or cy < 0 or cx >= _deco_w or cy >= _deco_h: continue
			if (_deco[cy * _deco_w + cx] & jel) != 0: return true
	return false

# Fák között áll? (fedezék a nyilak és a golyók ellen)
func in_forest(p: Vector2) -> bool:
	return _deco_at(p, DECO_FA)

# Sziklás magaslaton áll? (messzebbre lát és messzebbre lő)
func on_rocks(p: Vector2) -> bool:
	return _deco_at(p, DECO_SZIKLA)

# Vízparti homokban áll? (nehéz menet, a védőnek előnye van)
func on_shore(p: Vector2) -> bool:
	if is_water(p): return false
	var d := float(water_cell) * SHORE_CELLS * 1.5
	for i in range(4):
		var a := float(i) * TAU / 4.0
		if is_water(p + Vector2(cos(a), sin(a)) * d): return true
	return false

var _res_seq: int = 0

func add_resource(kind: String, pos: Vector2) -> void:
	var n := ResNode.new()
	_res_seq += 1
	n.nid = _res_seq
	n.kind = kind
	n.color = RES_COLORS.get(kind, Color.WHITE)
	n.max_amount = ResourceSystem.node_amount(kind)
	n.amount = n.max_amount
	n.radius = ResourceSystem.node_radius(kind)
	n.position = pos
	add_child(n)

# Csak a helyi játékos korszakváltása színezi át a tájat.
func _on_era_changed(owner_id: int, new_age: int) -> void:
	if owner_id != GameState.en_id: return
	_age = clampi(new_age, 0, 3)
	_make_grass_tex()
	var mat := land_sprite.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("grass_tex", grass_tex)
	queue_redraw()

# Ismétlődő fűcsempe: a két talajszín között zajjal keveredik, plusz néhány
# sötétebb fűcsomó. Így a hatalmas földfelület nem lesz egyszínű folt.
func _make_grass_tex() -> void:
	var a := clampi(_age, 0, 3)
	var base: Color = LAND_COLORS[a]
	var alt: Color = LAND_ALTS[a]
	# A TÁJTÍPUS talajszíne felülírja a korszakét: a rengeteg sötétzöld, a
	# sivatag homokszín, a puszta szikes (index.html: MAPS[].ground). A
	# második árnyalatot ebből keverjük, hogy a fűcsempe mintája megmaradjon.
	if _ground_override != "":
		base = Color(_ground_override)
		alt = base.lightened(0.10)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = 1337 + a
	noise.frequency = 0.06
	var detail := FastNoiseLite.new()
	detail.noise_type = FastNoiseLite.TYPE_VALUE
	detail.seed = 4711 + a
	detail.frequency = 0.35
	var img := Image.create(GRASS_TILE, GRASS_TILE, false, Image.FORMAT_RGBA8)
	for y in range(GRASS_TILE):
		for x in range(GRASS_TILE):
			# A csempe széleit átlagoljuk, hogy ismétlődve ne legyen varrat.
			var t := (noise.get_noise_2d(x, y) + 1.0) * 0.5
			var d := (detail.get_noise_2d(x, y) + 1.0) * 0.5
			var c := base.lerp(alt, clampf(t * 0.85 + d * 0.15, 0.0, 1.0))
			# Erősebb szórás: közelről fűcsomók, távolról foltos rét.
			c = c.darkened((0.5 - t) * 0.22) if t < 0.5 else c.lightened((t - 0.5) * 0.20)
			if d > 0.80:
				c = c.darkened(0.22)
			elif d < 0.18:
				c = c.lightened(0.14)
			img.set_pixel(x, y, c)
	grass_tex = ImageTexture.create_from_image(img)

func rebuild() -> void:
	_bake_navigation()
	queue_redraw()

# --- Lekérdezések ---

func is_water(world_pos: Vector2) -> bool:
	if grid_h == 0: return false
	var cx := int(world_pos.x) / water_cell
	var cy := int(world_pos.y) / water_cell
	if cy < 0 or cy >= grid_h: return true
	var row: Array = water_map[cy]
	if cx < 0 or cx >= row.size(): return true
	return row[cx]

func find_nearest_resource(kind: String, from: Vector2, max_dist: float = 1e9) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist
	for n in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(n): continue
		if kind != "" and n.kind != kind: continue
		var d: float = n.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = n
	return best

# --- Navigáció ---

func _bake_navigation() -> void:
	land_region.navigation_polygon  = _rects_to_navpoly(_land_rects)
	water_region.navigation_polygon = _rects_to_navpoly(_water_rects)

# A téglalapokat NEM tehetjük közvetlenül a navigációs poligonba: a
# szomszédos téglalapok csúcsai nem esnek egybe, így a járófelület szét-
# esne, és a kereső nem találna átjárót közöttük. Ehelyett körvonalként
# adjuk át őket a beépített bake-előnek, ami összevonja és háromszögeli
# őket — így egyetlen összefüggő háló keletkezik.
func _rects_to_navpoly(rects: Array[Rect2]) -> NavigationPolygon:
	var poly := NavigationPolygon.new()
	poly.cell_size = 1.0
	poly.agent_radius = 4.0
	if rects.is_empty():
		return poly
	var src := NavigationMeshSourceGeometryData2D.new()
	for r in rects:
		src.add_traversable_outline(PackedVector2Array([
			r.position,
			Vector2(r.end.x, r.position.y),
			r.end,
			Vector2(r.position.x, r.end.y),
		]))
	NavigationServer2D.bake_from_source_geometry_data(poly, src)
	return poly

# Mohó maximális-téglalap felbontás a boolean rácsra. A kapott téglalapok
# hézagmentesen lefedik a keresett típusú cellákat.
func _extract_rects(want: bool) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if grid_h == 0: return out
	var used: Array = []
	used.resize(grid_h)
	for y in range(grid_h):
		var row := PackedByteArray()
		row.resize(grid_w)
		used[y] = row
	for y in range(grid_h):
		var row_used: PackedByteArray = used[y]
		var row_map: Array = water_map[y]
		for x in range(grid_w):
			if row_used[x] == 1 or bool(row_map[x]) != want:
				continue
			# Szélesség
			var w := 0
			while x + w < grid_w and row_used[x + w] == 0 and bool(row_map[x + w]) == want:
				w += 1
			# Magasság: csak teljes szélességben egyező sorokat veszünk hozzá
			var h := 1
			while y + h < grid_h:
				var ny_used: PackedByteArray = used[y + h]
				var ny_map: Array = water_map[y + h]
				var ok := true
				for dx in range(w):
					if ny_used[x + dx] == 1 or bool(ny_map[x + dx]) != want:
						ok = false
						break
				if not ok: break
				h += 1
			for dy in range(h):
				var u: PackedByteArray = used[y + dy]
				for dx in range(w):
					u[x + dx] = 1
				used[y + dy] = u
			row_used = used[y]
			out.append(Rect2(
				float(x * water_cell), float(y * water_cell),
				float(w * water_cell), float(h * water_cell)))
	return out

# --- Rajzolás ---
#
# EGY KÉZ, EGY STÍLUS. A táj ugyanabból a szabálykönyvből rajzolódik, mint
# az épületek (BuildArt): a nap BAL FELÜLRŐL süt (BuildArt.NAP), tehát az
# árnyék jobbra-le dől, a bal felső foltok világosabbak, a sziluettet
# pedig a tus felé sötétített alapszín zárja le (BuildArt.INK).
#
# NEM MÁSOLT-BEILLESZTETT. Minden fa és minden szikla a SAJÁT HELYÉBŐL
# vetett véletlent kap — pontosan úgy, ahogy a lelőhelyek (`ResNode._rng`).
# Ettől mind más, de mentés/betöltés után és a hálózat másik gépén is
# ugyanaz marad, mert a hely nem változik.

# Korszakonkénti LOMBSZÍN. Két árnyalat: fánként keverünk közöttük, ettől
# lesz egy erdőfolt tarka. 0 = tavasz, 1 = nyár, 2 = ősz, 3 = tél.
const LOMB_SZIN := [
	Color(0.30, 0.53, 0.21),   # tavasz — friss, sárgás zöld
	TREE_LEAF,                 # nyár   — mély zöld
	Color(0.66, 0.45, 0.13),   # ősz    — arany
	Color(0.34, 0.38, 0.35),   # tél    — fakó (csak a hóhoz kell)
]
const LOMB_ALT := [
	Color(0.45, 0.63, 0.25),   # tavasz — halvány rügyzöld
	Color(0.21, 0.42, 0.17),   # nyár   — árnyékos zöld
	Color(0.72, 0.28, 0.12),   # ősz    — rozsdavörös
	Color(0.43, 0.45, 0.41),   # tél
]
const HO := Color(0.93, 0.95, 0.97, 0.78)

# A korszak vadvirágai: két-két szín, a fű mellé egy-egy pötty.
const VIRAG_SZIN := [
	[Color(0.96, 0.94, 0.86), Color(0.96, 0.82, 0.28)],   # tavasz: fehér, sárga
	[Color(0.52, 0.56, 0.86), Color(0.86, 0.40, 0.52)],   # nyár:   kék, rózsa
	[Color(0.84, 0.46, 0.16), Color(0.74, 0.28, 0.18)],   # ősz:    rozsda
	[Color(0.90, 0.92, 0.95), Color(0.78, 0.80, 0.84)],   # tél:    dér
]

func _draw() -> void:
	# A vizet és a talajt (a homokos parttal együtt) a két shader rajzolja
	# alattunk — ide csak a dekoráció kerül. Rajzolt partvonalra nincs
	# szükség: a homoksáv maga a part.
	var a := clampi(_age, 0, 3)
	var winter := a == 3
	var leaf: Color = LOMB_SZIN[a]
	var leaf2: Color = LOMB_ALT[a]
	# Az aljnövényzet megy LEGALULRA, hogy a fák és a sziklák ráüljenek.
	_draw_aljnovenyzet(a)
	for p in rocks:
		_draw_rock(p, winter)
	for p in trees:
		_draw_tree(p, leaf, leaf2, winter)

# --- Egyetlen fa ---
#
# A szikla és a fa a KATONÁHOZ mérve: egy fa magasabb egy embernél
# (~46 px), egy szikla nagyjából derékig ér. Ettől a mérettől tér el
# fánként a helyből vetett véletlen.
func _draw_tree(p: Vector2, leaf: Color, leaf2: Color, winter: bool) -> void:
	var g := RandomNumberGenerator.new()
	g.seed = hash(Vector2i(int(p.x), int(p.y)))
	# A fák zöme átlagos termetű, de az erdő nem faiskola: ~12% facsemete,
	# ~8% öreg, terebélyes óriás.
	var m := g.randf_range(0.88, 1.12)
	var sors := g.randf()
	if sors < 0.12:      m *= 0.60          # facsemete
	elif sors < 0.20:    m *= 1.30          # öreg fa
	var h := 16.0 * m                        # törzsmagasság
	var vast := g.randf_range(2.3, 3.7) * m  # a törzs fél vastagsága
	var dol := g.randf_range(-0.18, 0.18)    # enyhe dőlés
	var cr := 15.0 * m * g.randf_range(0.82, 1.18)   # lombsugár, ±18%
	# Fánként más árnyalat: ősszel az arany és a rozsdavörös között.
	var sz := leaf.lerp(leaf2, g.randf())
	var vil := g.randf_range(-0.13, 0.13)
	sz = sz.lightened(vil) if vil > 0.0 else sz.darkened(-vil)
	# 1) Vetett árnyék: a nap bal felülről süt, az árnyék jobbra-le dől.
	draw_circle(p + BuildArt.NAP * (h + cr) * 0.55,
		cr * g.randf_range(0.68, 0.92), Color(0, 0, 0, 0.20))
	# 2) Törzs: lefelé szélesedő, a korona felé dőlő.
	var csucs := p + Vector2(dol * h, -h)    # a törzs teteje
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-vast, 2.0), p + Vector2(vast, 2.0),
		csucs + Vector2(vast * 0.60, 0.0), csucs + Vector2(-vast * 0.60, 0.0)]),
		TREE_TRUNK)
	# A bal oldalára esik a fény (2. szabály).
	draw_line(p + Vector2(-vast * 0.55, 0.0), csucs + Vector2(-vast * 0.34, 0.0),
		TREE_TRUNK.lightened(0.22), 1.0)
	if winter:
		_draw_teli_ag(csucs, cr, vast, g)
		return
	# 3) Lomb: 3–5 gömb, szabálytalan koszorúban. A legalsó, legsötétebb
	#    gömb zárja le a sziluettet — ez a "tus" a körvonalon (3. szabály).
	var kp := csucs + Vector2(0.0, -cr * 0.52)
	draw_circle(kp + Vector2(0.0, cr * 0.32), cr * 1.02,
		sz.darkened(0.34).lerp(BuildArt.INK, 0.14))
	var db := 3 + (g.randi() % 3)
	for i in range(db):
		var a := TAU * float(i) / float(db) + g.randf_range(-0.40, 0.40)
		var d := cr * g.randf_range(0.16, 0.46)
		var q := kp + Vector2(cos(a) * d, sin(a) * d * 0.72)
		# Minél inkább bal felül van a gömb, annál világosabb.
		var t := clampf(0.5 - (q.x - kp.x + q.y - kp.y) / (cr * 1.6), 0.0, 1.0)
		draw_circle(q, cr * g.randf_range(0.50, 0.80),
			sz.darkened(0.16).lerp(sz.lightened(0.24), t))
	# 4) Fénypötty bal felül: egyetlen hívás, de ettől lesz gömbölyű.
	draw_circle(kp + Vector2(-cr * 0.36, -cr * 0.40), cr * 0.32, sz.lightened(0.28))

# TÉL: a lombhullató fa KOPÁR. Néhány szétágazó ág, a tetejükön hóval —
# ez a leglátványosabb különbség a korszakváltáskor.
func _draw_teli_ag(csucs: Vector2, cr: float, vast: float,
		g: RandomNumberGenerator) -> void:
	var agak := 3 + (g.randi() % 2)
	for i in range(agak):
		var a := -PI * 0.5 + (float(i) - float(agak - 1) * 0.5) * 0.66 \
			+ g.randf_range(-0.14, 0.14)
		var vege := csucs + Vector2(cos(a), sin(a)) * cr * g.randf_range(0.70, 1.05)
		draw_line(csucs, vege, TREE_TRUNK.darkened(0.08), maxf(1.0, vast * 0.50))
		# Hó ül az ág tetején.
		draw_line(csucs + Vector2(0.0, -1.2), vege + Vector2(0.0, -1.2),
			Color(HO.r, HO.g, HO.b, 0.50), 1.0)
	draw_circle(csucs + Vector2(-cr * 0.12, -cr * 0.30), cr * 0.34, HO)

# --- Egyetlen szikla ---
#
# Nem négy egyforma kör: 2–5 kőtömb, tömbönként más mérettel, hidegebb
# (kékes) vagy melegebb (barnás) szürkével, néhánynál kaviccsal a tövében.
func _draw_rock(p: Vector2, winter: bool) -> void:
	var g := RandomNumberGenerator.new()
	g.seed = hash(Vector2i(int(p.x), int(p.y)))
	var m := g.randf_range(0.76, 1.24)
	# A szürke sosem semleges: a kőzet vagy kékesen hideg, vagy barnásan meleg.
	var meleg := g.randf_range(-1.0, 1.0)
	var alap := ROCK_COLOR.lerp(
		Color(0.53, 0.48, 0.41) if meleg > 0.0 else Color(0.40, 0.43, 0.51),
		absf(meleg) * 0.55)
	var sotet := ROCK_SHADE.lerp(alap.darkened(0.30), 0.5)
	# Vetett árnyék — jobbra-le, mint minden másé.
	draw_circle(p + BuildArt.NAP * 18.0 * m, 12.5 * m, Color(0, 0, 0, 0.22))
	# A hátsó tömbök: a fő tömb köré szórva, sötétebben.
	var db := 2 + (g.randi() % 4)
	for i in range(db):
		var a := TAU * float(i) / float(db) + g.randf_range(-0.45, 0.45)
		var d := 8.0 * m * g.randf_range(0.20, 1.0)
		draw_circle(p + Vector2(cos(a) * d, sin(a) * d * 0.62),
			13.0 * m * g.randf_range(0.42, 0.78), sotet)
	# A fő tömb és a megvilágított lapja.
	draw_circle(p, 13.0 * m * g.randf_range(0.86, 1.0), alap)
	draw_circle(p + Vector2(-3.4, -4.2) * m, 6.5 * m, alap.lightened(0.24))
	# Kavicsok a kő tövében — csak minden második-harmadik sziklánál.
	if g.randf() < 0.55:
		for _i in range(1 + (g.randi() % 2)):
			var a2 := g.randf_range(0.0, PI)     # előre, a kő elé
			draw_circle(p + Vector2(cos(a2) * 15.0 * m, 4.0 + sin(a2) * 6.0 * m),
				g.randf_range(1.6, 3.0) * m, sotet)
	if winter:
		draw_circle(p + Vector2(-2.0, -5.0) * m, 5.5 * m, HO)

# --- ALJNÖVÉNYZET ---
#
# A talaj nem csupasz szőnyeg: fűcsomók, apró bokrok és elvétve vadvirág
# tarkítja. A díszeket NEM tároljuk — egy képzeletbeli RÁCS adja őket,
# cellánként legfeljebb egyet, a cella koordinátájából vetett véletlennel.
# Így minden újraindításkor (és minden gépen) ugyanott állnak, memóriát
# viszont nem visznek.
#
# TELJESÍTMÉNY (Intel HD 630!):
#   - csak a kamera dobozában lévő cellákat járjuk be,
#   - egy dísz legfeljebb 2-3 rajzhívás,
#   - a sűrűség a részletességhez kötött: 0-n egyáltalán nincs,
#   - kizoomolva elmarad (úgysem látszana, viszont ezrével kellene).
const ALJ_CELLA := 46                        # ekkora rácsban áll egy dísz
const ALJ_SURUSEG := [0.0, 0.16, 0.34]       # Settings.detail szerinti esély
const ALJ_LEPES := 64.0                      # ennyi kameramozgás után újrarajz
const ALJ_PEREM := 80.0                      # ennyivel rajzolunk a kép mellé
const ALJ_ZOOM_MIN := 0.55                   # ez alatt nincs aljnövényzet

var _main: Node = null
var _kam_volt := Vector2(-1e9, -1e9)
var _kam_zoom := -1.0
var _kam_t: float = 0.0

# A kamera látómezeje világkoordinátákban (a Scars/Wildlife mintájára).
# Üres téglalapot ad, ha nincs kamera (fejlesztői/headless futás) vagy
# túlságosan ki van zoomolva — ilyenkor dísz sem készül.
func _kamera_doboz() -> Rect2:
	if _main == null: _main = get_tree().get_first_node_in_group("main")
	if _main == null or _main.camera == null: return Rect2()
	if _main.camera.zoom.x < ALJ_ZOOM_MIN: return Rect2()
	var meret := get_viewport_rect().size / maxf(_main.camera.zoom.x, 0.05)
	return Rect2(_main.camera.global_position - meret * 0.5, meret).grow(ALJ_PEREM)

# A dísz csak a látómezőben készül el, ezért a kamera elmozdulására újra
# kell rajzolni — de NEM képkockánként: csak ha egy jókora lépésköznél
# többet haladt (a perem éppen ezt a lépésközt fedezi). Így panning közben
# sem épül fel újra és újra a teljes rajzparancs-lista.
func _process(delta: float) -> void:
	_kam_t += delta
	if _kam_t < 0.12: return
	_kam_t = 0.0
	if _main == null: _main = get_tree().get_first_node_in_group("main")
	if _main == null or _main.camera == null: return
	var p: Vector2 = _main.camera.global_position
	var z: float = _main.camera.zoom.x
	if p.distance_to(_kam_volt) < ALJ_LEPES and is_equal_approx(z, _kam_zoom):
		return
	_kam_volt = p
	_kam_zoom = z
	queue_redraw()

# A részletesség menet közben is átállítható: ilyenkor az aljnövényzet
# megjelenik vagy eltűnik.
func _on_settings_changed() -> void:
	set_process(Settings.detail >= 1)
	_kam_volt = Vector2(-1e9, -1e9)
	queue_redraw()

func _draw_aljnovenyzet(a: int) -> void:
	var esely: float = ALJ_SURUSEG[clampi(Settings.detail, 0, 2)]
	if esely <= 0.0: return
	var doboz := _kamera_doboz()
	if doboz.size.x <= 0.0: return
	# A fű színe a KORSZAK talajpalettájából jön (ugyanabból, amiből a
	# fűcsempe készül), így a korszakváltás az aljnövényzeten is látszik.
	var fu := (LAND_COLORS[a] as Color).darkened(0.20)
	var fu2 := (LAND_ALTS[a] as Color).lightened(0.08)
	var g := RandomNumberGenerator.new()     # egy darab, cellánként újravetve
	var x0 := int(floor(doboz.position.x / ALJ_CELLA))
	var y0 := int(floor(doboz.position.y / ALJ_CELLA))
	var x1 := int(ceil(doboz.end.x / ALJ_CELLA))
	var y1 := int(ceil(doboz.end.y / ALJ_CELLA))
	for cy in range(y0, y1):
		for cx in range(x0, x1):
			g.seed = hash(Vector2i(cx, cy)) ^ 0x5EED
			if g.randf() >= esely: continue
			var p := Vector2(
				(float(cx) + g.randf_range(0.15, 0.85)) * ALJ_CELLA,
				(float(cy) + g.randf_range(0.15, 0.85)) * ALJ_CELLA)
			# Vízre és a homokos partra nem nő semmi. (Az épületek úgyis
			# a terep FÖLÉ rajzolódnak, ezért azokkal nem kell törődni.)
			if is_water(p) or on_shore(p): continue
			_draw_disz(p, g, a, fu, fu2)

# Egy dísz a talajon. Mindegyik legfeljebb 3 rajzhívás.
func _draw_disz(p: Vector2, g: RandomNumberGenerator, a: int,
		fu: Color, fu2: Color) -> void:
	var fajta := g.randf()
	var m := g.randf_range(0.75, 1.25)
	if a == 3:
		# TÉL: hófoltok, köztük kilátszó, száraz fűcsomók.
		if fajta < 0.60:
			draw_circle(p, 4.2 * m, Color(HO.r, HO.g, HO.b, 0.55))
			draw_circle(p + Vector2(-1.3, -1.1) * m, 2.2 * m,
				Color(0.99, 1.0, 1.0, 0.45))
		else:
			_fucsomo(p, g, m * 0.8, Color(0.54, 0.52, 0.44))
		return
	if fajta < 0.62:
		_fucsomo(p, g, m, fu.lerp(fu2, g.randf()))
	elif fajta < 0.90:
		_bokor(p, g, m, fu.darkened(0.16))
	else:
		_vadvirag(p, g, m, fu.darkened(0.08), a)

# Fűcsomó: egyetlen elkeskenyedő szálköteg, rajta a bal oldali fénycsík.
func _fucsomo(p: Vector2, g: RandomNumberGenerator, m: float, c: Color) -> void:
	var w := 3.6 * m
	var h := 6.5 * m * g.randf_range(0.8, 1.3)
	var dol := g.randf_range(-0.35, 0.35)          # merre hajlik a szél
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-w, 0.0), p + Vector2(w, 0.0),
		p + Vector2(w * 0.45 + dol * h, -h),
		p + Vector2(-w * 0.15 + dol * h, -h * 0.72)]), c.darkened(0.18))
	draw_line(p + Vector2(-w * 0.5, 0.0),
		p + Vector2(-w * 0.1 + dol * h, -h * 0.95), c.lightened(0.28), 1.0)

# Apró bokor: tus felé sötétített alap + megvilágított folt bal felül.
func _bokor(p: Vector2, g: RandomNumberGenerator, m: float, c: Color) -> void:
	var r := 5.0 * m * g.randf_range(0.8, 1.25)
	draw_circle(p + Vector2(0.0, -r * 0.45), r, c.lerp(BuildArt.INK, 0.20))
	draw_circle(p + Vector2(-r * 0.30, -r * 0.78), r * 0.55, c.lightened(0.26))

# Vadvirág: szár és szirompötty. A szín a korszakhoz igazodik.
func _vadvirag(p: Vector2, g: RandomNumberGenerator, m: float, szar: Color,
		a: int) -> void:
	var cs := p + Vector2(g.randf_range(-1.8, 1.8) * m, -7.0 * m)
	draw_line(p, cs, szar.darkened(0.12), 1.0)
	var szirom: Color = VIRAG_SZIN[clampi(a, 0, 3)][g.randi() % 2]
	draw_circle(cs, 2.2 * m, szirom)
	draw_circle(cs + Vector2(-0.7, -0.7) * m, 1.0 * m, szirom.lightened(0.35))
