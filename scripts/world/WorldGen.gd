class_name WorldGen
extends RefCounted

# VILÁGGENERÁLÁS — az eredeti (index.html) tájtípusai szerint.
#
# A régi változat egyetlen zajtérképet használt, és minden pálya ugyanúgy
# nézett ki. Az eredetiben TÍZFÉLE TÁJ van (MAPS tömb): mindegyik mást mond
# arról, mennyi a fa, a kő, az arany és a szén, hány tó és folyó van, milyen
# mély a tenger, és milyen színű a talaj. A víz is másképp készül: tenger a
# pálya egyik szélén, hullámos partvonallal, tavak korongokból, folyók a
# tengerből befelé — nem zajból.
#
# A kalózvilág térképe nem sorsolt, hanem RÖGZÍTETT Karib-tenger: Florida
# csücske, Kuba, a Bahamák, Jamaica, Hispaniola, Tortuga és a Kajmánok.
#
# A víztérkép cellákban készül (nem pixelenként), különben 3400x2400 = 8.16M
# logikai érték keletkezne generálásonként.

const WATER_CELL := 16
# A Karib-térkép a HTML-lel azonos, 32 képpontos rácson készül: a partvonal
# simító menetei ("egycellás szoros", "nyúlvány") erre a felbontásra vannak
# szabva, finomabb rácson nem ugyanazt jelentenék.
const WATER_CELL_KARIB := 32
# A HTML rácsa 32 képpont; az onnan hozott cellaszámokat ezzel váltjuk
# képpontra.
const HTML_CELL := 32.0

# --- TÁJTÍPUSOK (index.html: const MAPS) ---
#
# tree/stone/gold/coal : a lelőhelyek sűrűségének szorzója
# lakes/rivers/sea     : hány tó, hány folyó, milyen mély a tenger (0 = nincs)
# mountains            : sziklacsoportok szorzója
# ground               : a talaj színe ("" = a korszak szerinti alapszín)
# hidden               : nem választható a menüben (a kalózvilág térképe)
const MAPS := [
	{"key": "mezo", "tree": 1.0, "stone": 1.0, "gold": 1.0, "coal": 1.0,
	 "lakes": 2, "rivers": 1, "sea": 1.0, "mountains": 0.0, "ground": ""},
	{"key": "erdo", "tree": 2.2, "stone": 0.55, "gold": 0.8, "coal": 0.9,
	 "lakes": 2, "rivers": 1, "sea": 1.0, "mountains": 0.0, "ground": "3d6b2c"},
	{"key": "kopar", "tree": 0.35, "stone": 1.8, "gold": 1.5, "coal": 1.7,
	 "lakes": 1, "rivers": 1, "sea": 1.0, "mountains": 2.0, "ground": "7d8a4a"},
	{"key": "sivatag", "tree": 0.22, "stone": 1.3, "gold": 2.0, "coal": 1.3,
	 "lakes": 0, "rivers": 0, "sea": 0.0, "mountains": 2.0, "ground": "c0a468"},
	{"key": "folyok", "tree": 1.1, "stone": 0.9, "gold": 1.0, "coal": 1.0,
	 "lakes": 1, "rivers": 4, "sea": 1.0, "mountains": 0.0, "ground": ""},
	{"key": "tavak", "tree": 1.0, "stone": 0.85, "gold": 0.9, "coal": 0.9,
	 "lakes": 8, "rivers": 1, "sea": 1.0, "mountains": 0.0, "ground": "4f7d3a"},
	{"key": "hegy", "tree": 0.6, "stone": 2.3, "gold": 1.4, "coal": 1.9,
	 "lakes": 1, "rivers": 2, "sea": 1.0, "mountains": 6.0, "ground": "6e7a48"},
	{"key": "puszta", "tree": 0.45, "stone": 1.1, "gold": 1.1, "coal": 1.1,
	 "lakes": 0, "rivers": 0, "sea": 0.0, "mountains": 1.0, "ground": "93924e"},
	{"key": "szigetek", "tree": 1.9, "stone": 0.7, "gold": 0.3, "coal": 0.6,
	 "lakes": 16, "rivers": 0, "sea": 2.4, "mountains": 0.0, "ground": "41762f"},
	{"key": "karib", "tree": 1.5, "stone": 0.6, "gold": 0.5, "coal": 0.4,
	 "lakes": 0, "rivers": 0, "sea": 0.0, "mountains": 0.0, "ground": "4a7a34",
	 "hidden": true},
]

static func map_def(key: String) -> Dictionary:
	for m in MAPS:
		if str(m["key"]) == key: return m
	return MAPS[0]

# A menüben felkínált tájak (a kalózvilág rögzített térképe nélkül).
static func choosable() -> Array:
	var out: Array = []
	for m in MAPS:
		if not bool(m.get("hidden", false)): out.append(str(m["key"]))
	return out

var rng := RandomNumberGenerator.new()
var cell : int = WATER_CELL
var _def : Dictionary = {}

func seed_rng(seed_value: int) -> void:
	rng.seed = seed_value

func srange_int(lo: int, hi: int) -> int:
	return rng.randi_range(lo, hi)

func srange(lo: float, hi: float) -> float:
	return rng.randf_range(lo, hi)

func generate(seed_value: int, terrain_node: Node) -> void:
	seed_rng(seed_value)
	# A kalózvilág mindig a Karib-tengeren játszik (index.html: G.mapType =
	# G.pirate ? 'karib' : ...).
	var key := "karib" if GameState.pirate else GameState.map_type
	_def = map_def(key)
	var karib := str(_def["key"]) == "karib"
	cell = WATER_CELL_KARIB if karib else WATER_CELL
	var water_map := _gen_karib() if karib else _gen_water()
	# A bázisok környéke szárazon marad. A Karib-térképen kisebb sugárral,
	# mert ott a szigetek szűkek (index.html: szarazR = karib ? 185 : 300).
	for s in start_positions():
		_clear_water_around(water_map, s, 185.0 if karib else 300.0)
	# A Karib-tengeren NINCS szárazföldi átjárás: a felek szigeteken ülnek.
	if not karib:
		_ensure_land_path(water_map)
	terrain_node.apply_water_map(water_map, cell)
	terrain_node.set_ground_override(str(_def.get("ground", "")))
	_gen_mountains(terrain_node, water_map)
	_gen_forests(terrain_node, water_map)
	_gen_resources(terrain_node, water_map)
	terrain_node.rebuild()

# --- VÍZ: tenger, tavak, folyók (index.html: genWater) ---

func _empty_map() -> Array:
	var W := int(ceil(float(GameState.WORLD_W) / cell))
	var H := int(ceil(float(GameState.WORLD_H) / cell))
	var map: Array = []
	map.resize(H)
	for y in range(H):
		var row: Array = []
		row.resize(W)
		row.fill(false)
		map[y] = row
	return map

func _cols(map: Array) -> int:
	return (map[0] as Array).size()

func _set_cell(map: Array, cx: int, cy: int) -> void:
	if cy < 0 or cy >= map.size(): return
	var row: Array = map[cy]
	if cx < 0 or cx >= row.size(): return
	row[cx] = true

# Korong vízzel, képpontban megadva.
func _disc(map: Array, center: Vector2, radius: float) -> void:
	var r := maxf(radius, float(cell) * 0.5)
	var cx0 := int((center.x - r) / cell)
	var cx1 := int((center.x + r) / cell)
	var cy0 := int((center.y - r) / cell)
	var cy1 := int((center.y + r) / cell)
	var r2 := r * r
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var p := Vector2((cx + 0.5) * cell, (cy + 0.5) * cell)
			if p.distance_squared_to(center) <= r2:
				_set_cell(map, cx, cy)

func _gen_water() -> Array:
	var map := _empty_map()
	var W := _cols(map)
	var H := map.size()
	# --- tenger a térkép egyik szélén, hullámos partvonallal ---
	var side := srange_int(0, 3)
	var sea: float = float(_def.get("sea", 1.0))
	# A HTML-ben a tenger 4-7 cella (128-224 képpont) mély. A mi hajóink
	# nagyobbak (a gálya maga 133 képpont hosszú), ezért a legkisebb mélység
	# hat cella — enélkül a gálya nem tudna megfordulni a parti sávban.
	var depth_html := 0.0
	if sea > 0.0:
		depth_html = maxf(7.0, float(4 + srange_int(0, 3)) * sea)
	var depth_c := depth_html * (HTML_CELL / float(cell))
	if sea > 0.0:
		var hossz: int = W if side < 2 else H
		var ph := srange(0.0, TAU)
		# A hullámzás a HTML 32 képpontos rácsára van szabva; finomabb
		# rácson arányosan lassabban fut.
		var k := float(cell) / HTML_CELL
		for i in range(hossz):
			var d := int(round(maxf(1.0, depth_c
				+ sin(i * 0.17 * k + ph) * 2.4 * (HTML_CELL / float(cell))
				+ sin(i * 0.061 * k) * 2.0 * (HTML_CELL / float(cell)))))
			for j in range(d):
				match side:
					0: _set_cell(map, i, j)
					1: _set_cell(map, i, H - 1 - j)
					2: _set_cell(map, j, i)
					_: _set_cell(map, W - 1 - j, i)
	# --- tavak ---
	for _k in range(int(_def.get("lakes", 0))):
		var c := Vector2(srange(14.0 * HTML_CELL, GameState.WORLD_W - 15.0 * HTML_CELL),
			srange(10.0 * HTML_CELL, GameState.WORLD_H - 11.0 * HTML_CELL))
		var r := float(3 + srange_int(0, 2)) * HTML_CELL
		_disc(map, c, r)
		for _m in range(5):
			_disc(map, c + Vector2(srange(-r, r), srange(-r, r)), maxf(r - HTML_CELL, HTML_CELL))
	# --- folyók: a tengerből vagy a szélről indulva befelé ---
	for _riv in range(int(_def.get("rivers", 0))):
		_make_river(map, side, depth_c)
	return map

func _make_river(map: Array, side: int, depth_c: float) -> void:
	var W := float(GameState.WORLD_W)
	var H := float(GameState.WORLD_H)
	var depth_px := depth_c * float(cell)
	var p := Vector2.ZERO
	var dir := Vector2.ZERO
	match side:
		0:
			p = Vector2(srange(10.0 * HTML_CELL, W - 11.0 * HTML_CELL), depth_px)
			dir = Vector2(0, 1)
		1:
			p = Vector2(srange(10.0 * HTML_CELL, W - 11.0 * HTML_CELL), H - depth_px)
			dir = Vector2(0, -1)
		2:
			p = Vector2(depth_px, srange(8.0 * HTML_CELL, H - 9.0 * HTML_CELL))
			dir = Vector2(1, 0)
		_:
			p = Vector2(W - depth_px, srange(8.0 * HTML_CELL, H - 9.0 * HTML_CELL))
			dir = Vector2(-1, 0)
	var hossz := (H if side < 2 else W) * srange(0.35, 0.55)
	var lepes := float(cell)
	var n := int(hossz / lepes)
	var wob := srange(0.0, TAU)
	for i in range(n):
		# A folyó a torkolatnál a legszélesebb, fölfelé elkeskenyedik.
		var szeles := maxf(float(cell) * 0.6,
			(2.6 - 2.2 * float(i) / float(maxi(n, 1))) * HTML_CELL * 0.5)
		_disc(map, p, szeles)
		wob += srange(-0.35, 0.35)
		var oldal := Vector2(dir.y, dir.x) * sin(wob) * 1.1
		p += dir * lepes + oldal * lepes

# --- A KARIB-TENGER (index.html: 6/C) ---
#
# Rögzített szárazföld: sokszögek és ellipszisek a pálya arányában (0..1),
# utána szaggatott partvonal, végül két simító menet, hogy a hajók
# elférjenek a szorosokban.

const KARIB_FOLD := [
	# Florida csücske
	{"p": [[0.24, -0.05], [0.40, -0.05], [0.42, 0.05], [0.40, 0.12], [0.35, 0.17],
		[0.31, 0.15], [0.28, 0.08], [0.24, 0.03]]},
	# Kuba
	{"p": [[0.10, 0.44], [0.20, 0.41], [0.30, 0.42], [0.40, 0.45], [0.50, 0.49],
		[0.58, 0.53], [0.66, 0.58], [0.70, 0.63], [0.68, 0.67], [0.60, 0.64],
		[0.50, 0.60], [0.40, 0.56], [0.30, 0.53], [0.20, 0.50], [0.11, 0.50]]},
	# Isla de la Juventud
	{"e": [0.245, 0.575, 0.045, 0.028, 0.0]},
	# Bahama-szigetek
	{"e": [0.575, 0.07, 0.018, 0.075, 0.2]},
	{"e": [0.615, 0.135, 0.014, 0.055, 0.35]},
	{"e": [0.566, 0.205, 0.052, 0.072, 0.12]},
	{"e": [0.635, 0.235, 0.013, 0.062, 0.25]},
	{"e": [0.700, 0.30, 0.016, 0.050, 0.30]},
	{"e": [0.745, 0.375, 0.014, 0.045, 0.20]},
	{"e": [0.800, 0.42, 0.017, 0.038, 0.45]},
	{"e": [0.845, 0.30, 0.013, 0.035, 0.10]},
	# Kajmán-szigetek
	{"e": [0.335, 0.745, 0.028, 0.016, 0.1]},
	# Jamaica
	{"e": [0.545, 0.855, 0.082, 0.050, 0.06]},
	# Hispaniola
	{"p": [[0.78, 0.80], [0.88, 0.78], [0.97, 0.80], [1.02, 0.86], [1.00, 0.94],
		[0.90, 0.96], [0.80, 0.93], [0.76, 0.86]]},
	# Tortuga
	{"e": [0.885, 0.695, 0.030, 0.016, 0.0]},
	# Yucatán és a szárazföld pereme
	{"p": [[-0.05, 0.40], [0.05, 0.42], [0.07, 0.52], [0.05, 0.62], [-0.05, 0.66]]},
	{"p": [[-0.05, 0.86], [0.06, 0.88], [0.08, 0.96], [-0.05, 1.05]]},
]

# Nevezetes kikötők (a felek innen indulnak). Arányos koordináták.
const KARIB_HELY := {
	"nassau": [0.566, 0.235], "havanna": [0.150, 0.437],
	"santiago": [0.545, 0.585], "trinidad": [0.330, 0.520],
	"matanzas": [0.250, 0.430], "portroyal": [0.545, 0.878],
	"tortuga": [0.885, 0.712], "santodomingo": [0.930, 0.905],
	"gonaives": [0.795, 0.812], "eleuthera": [0.640, 0.150],
	"exuma": [0.700, 0.318], "crooked": [0.800, 0.432],
	"caymanbrac": [0.335, 0.760], "campeche": [0.030, 0.520],
}

static func _in_polygon(px: float, py: float, pts: Array) -> bool:
	var benn := false
	var j := pts.size() - 1
	for i in range(pts.size()):
		var xi: float = float(pts[i][0])
		var yi: float = float(pts[i][1])
		var xj: float = float(pts[j][0])
		var yj: float = float(pts[j][1])
		if ((yi > py) != (yj > py)) \
				and (px < (xj - xi) * (py - yi) / ((yj - yi) if absf(yj - yi) > 1e-9 else 1e-9) + xi):
			benn = not benn
		j = i
	return benn

func _gen_karib() -> Array:
	var map := _empty_map()
	var W := _cols(map)
	var H := map.size()
	# Mindent víz borít, ebből vágjuk ki a szárazföldet.
	for cy in range(H):
		(map[cy] as Array).fill(true)
	for cy in range(H):
		var py := (cy + 0.5) / float(H)
		var row: Array = map[cy]
		for cx in range(W):
			var px := (cx + 0.5) / float(W)
			for f in KARIB_FOLD:
				var szaraz := false
				if f.has("p"):
					szaraz = _in_polygon(px, py, f["p"])
				else:
					var e: Array = f["e"]
					var dx := px - float(e[0])
					var dy := py - float(e[1])
					var c := cos(-float(e[4]))
					var s := sin(-float(e[4]))
					var ux := (dx * c - dy * s) / float(e[2])
					var uy := (dx * s + dy * c) / float(e[3])
					szaraz = ux * ux + uy * uy <= 1.0
				if szaraz:
					row[cx] = false
					break
	# A partvonal legyen kissé szaggatott, hogy ne látszódjon a mértani forma.
	var masol := _copy(map)
	for cy in range(1, H - 1):
		for cx in range(1, W - 1):
			var szaraz_szomszed := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if not bool((masol[cy + dy] as Array)[cx + dx]): szaraz_szomszed += 1
			if szaraz_szomszed > 0 and szaraz_szomszed < 9 and srange(0.0, 1.0) < 0.28:
				(map[cy] as Array)[cx] = not bool((masol[cy] as Array)[cx])
	# HAJÓZHATÓSÁG: a tüskéket és a szűkületeket elhordjuk, különben a hajók
	# beszorulnak. Három menet, ahogy az eredetiben.
	for _menet in range(3):
		var m2 := _copy(map)
		for cy in range(1, H - 1):
			for cx in range(1, W - 1):
				if bool((m2[cy] as Array)[cx]): continue
				var viz := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0: continue
						if bool((m2[cy + dy] as Array)[cx + dx]): viz += 1
				if viz >= 5: (map[cy] as Array)[cx] = true
	# Egycellás gát két öböl között: azt is áttörjük.
	var m3 := _copy(map)
	for cy in range(1, H - 1):
		for cx in range(1, W - 1):
			if bool((m3[cy] as Array)[cx]): continue
			var bal: bool = bool((m3[cy] as Array)[cx - 1])
			var jobb: bool = bool((m3[cy] as Array)[cx + 1])
			var fent: bool = bool((m3[cy - 1] as Array)[cx])
			var lent: bool = bool((m3[cy + 1] as Array)[cx])
			if (bal and jobb) or (fent and lent):
				(map[cy] as Array)[cx] = true
	return map

func _copy(map: Array) -> Array:
	var out: Array = []
	out.resize(map.size())
	for y in range(map.size()):
		out[y] = (map[y] as Array).duplicate()
	return out

# A kalóz kikötők világkoordinátában, a legközelebbi PARTRA igazítva — hogy
# egyik város se kerüljön a sziget közepébe (index.html: karibShoreSnap).
func karib_point(kulcs: String, map: Array) -> Vector2:
	var p: Array = KARIB_HELY.get(kulcs, KARIB_HELY["nassau"])
	var W := _cols(map)
	var H := map.size()
	var cx0 := int(round(float(p[0]) * W))
	var cy0 := int(round(float(p[1]) * H))
	for r in range(0, 27):
		var best := Vector2.INF
		var best_d := 1e9
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r: continue
				var cx := cx0 + dx
				var cy := cy0 + dy
				if cx < 1 or cy < 1 or cx >= W - 1 or cy >= H - 1: continue
				if bool((map[cy] as Array)[cx]): continue        # szárazföld kell
				var part := false
				for k in range(8):
					var nx: int = cx + int([1, -1, 0, 0, 1, 1, -1, -1][k])
					var ny: int = cy + int([0, 0, 1, -1, 1, -1, 1, -1][k])
					if bool((map[ny] as Array)[nx]): part = true
				if not part: continue
				var d := float(dx * dx + dy * dy)
				if d < best_d:
					best_d = d
					best = Vector2((cx + 0.5) * cell, (cy + 0.5) * cell)
		if best != Vector2.INF: return best
	return Vector2(float(p[0]) * GameState.WORLD_W, float(p[1]) * GameState.WORLD_H)

# --- Szárazföldi átjárás ---
#
# A folyók és a tenger elvághatják a bázisok közti utat. Ha nincs
# szárazföldi összeköttetés, gázlót vágunk: a víz sosem zárhatja el a
# játékot önmagától (index.html: ensureLandPath).
func _ensure_land_path(map: Array) -> void:
	var starts := start_positions()
	if starts.size() < 2: return
	for i in range(1, starts.size()):
		if not _land_connected(map, starts[0], starts[i]):
			_carve_ford(map, starts[0], starts[i])

func _land_connected(map: Array, a: Vector2, b: Vector2) -> bool:
	var W := _cols(map)
	var H := map.size()
	var start := Vector2i(int(a.x / cell), int(a.y / cell))
	var cel := Vector2i(int(b.x / cell), int(b.y / cell))
	if start == cel: return true
	var latott := {}
	var sor: Array[Vector2i] = [start]
	latott[start] = true
	while not sor.is_empty():
		var p: Vector2i = sor.pop_front()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + d
			if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H: continue
			if latott.has(n): continue
			if bool((map[n.y] as Array)[n.x]): continue
			if n == cel: return true
			latott[n] = true
			sor.append(n)
	return false

# Gázló: keskeny szárazföldi átkelő a két pont között. Csak ott látszik,
# ahol vizet keresztez — szárazon nem változtat semmin.
func _carve_ford(map: Array, a: Vector2, b: Vector2) -> void:
	var n := int(a.distance_to(b) / (cell * 0.5)) + 1
	for i in range(n + 1):
		var p := a.lerp(b, float(i) / float(n))
		var cx := int(p.x / cell)
		var cy := int(p.y / cell)
		for dy in range(0, 2):
			for dx in range(0, 2):
				var yy := cy + dy
				var xx := cx + dx
				if yy < 0 or yy >= map.size(): continue
				var row: Array = map[yy]
				if xx < 0 or xx >= row.size(): continue
				row[xx] = false

func _clear_water_around(map: Array, center: Vector2, radius: float) -> void:
	var r2 := radius * radius
	var cx0 := int((center.x - radius) / cell)
	var cx1 := int((center.x + radius) / cell)
	var cy0 := int((center.y - radius) / cell)
	var cy1 := int((center.y + radius) / cell)
	for cy in range(maxi(cy0, 0), mini(cy1 + 1, map.size())):
		var row: Array = map[cy]
		for cx in range(maxi(cx0, 0), mini(cx1 + 1, row.size())):
			var p := Vector2((cx + 0.5) * cell, (cy + 0.5) * cell)
			if p.distance_squared_to(center) <= r2:
				row[cx] = false

# Világkoordinátát vár, cellára vált.
func _is_water(map: Array, x: int, y: int) -> bool:
	var cy := int(y / cell)
	var cx := int(x / cell)
	if cy < 0 or cy >= map.size(): return true
	var row: Array = map[cy]
	if cx < 0 or cx >= row.size(): return true
	return row[cx]

# --- Hegyek, erdők, lelőhelyek (a tájtípus szorzóival) ---

func _gen_mountains(terrain: Node, wmap: Array) -> void:
	# A sziklák a köves felföldre valók; a réten legfeljebb elszórtan. A
	# tájtípus "mountains" értéke ehhez ad hozzá (hegyvidéken hatszoros).
	var mul: float = 1.0 + float(_def.get("mountains", 0.0)) * 0.5
	var count := int(srange_int(10, 16) * mul)
	for _i in range(count):
		var cx := srange(140, GameState.WORLD_W - 140)
		var cy := srange(140, GameState.WORLD_H - 140)
		var hegyes: bool = float(_def.get("mountains", 0.0)) >= 2.0
		if terrain.biome_kind(Vector2(cx, cy)) < 2 and srange(0.0, 1.0) < (0.35 if hegyes else 0.75):
			continue
		if not _is_water(wmap, int(cx), int(cy)):
			var n := srange_int(3, 8)
			for _j in range(n):
				var angle := srange(0.0, TAU)
				var dist  := srange(20.0, 65.0)
				var rx := clampf(cx + cos(angle) * dist, 40, GameState.WORLD_W - 40)
				var ry := clampf(cy + sin(angle) * dist, 40, GameState.WORLD_H - 40)
				if _is_water(wmap, int(rx), int(ry)): continue
				terrain.add_rock(Vector2(rx, ry))

func _gen_forests(terrain: Node, wmap: Array) -> void:
	# Erdő a dús réten sűrűn, a pusztán ritkásan, a sziklás felföldön alig —
	# az egészet a tájtípus fa-szorzója skálázza (rengetegben 2,2-szeres,
	# sivatagban alig ötöde).
	var count := int(srange_int(20, 30) * float(_def.get("tree", 1.0)))
	for _i in range(count):
		var cx := srange(120, GameState.WORLD_W - 120)
		var cy := srange(120, GameState.WORLD_H - 120)
		var b: int = terrain.biome_kind(Vector2(cx, cy))
		var esely: float = [1.0, 0.45, 0.12][clampi(b, 0, 2)]
		if srange(0.0, 1.0) > esely: continue
		if not _is_water(wmap, int(cx), int(cy)):
			for _j in range(srange_int(3, 9)):
				var a := srange(0.0, TAU)
				var d := srange(10.0, 45.0)
				var tx := clampf(cx + cos(a) * d, 30, GameState.WORLD_W - 30)
				var ty := clampf(cy + sin(a) * d, 30, GameState.WORLD_H - 30)
				if _is_water(wmap, int(tx), int(ty)): continue
				terrain.add_tree(Vector2(tx, ty))

# A felek kezdőhelyei. Kettőnél a két átellenes sarok (így a legnagyobb a
# távolság), háromtól viszont körben oszlanak el, hogy senki ne kerüljön a
# másik ölébe. UGYANEZT használja a Main a fővárosok kirakásához — ezért
# statikus, és nem két helyen áll a képlet.
#
# A KALÓZVILÁGBAN a bázisok a nevezetes kikötőkbe kerülnek (Nassau, Havanna,
# Port Royal, Tortuga…), nem a sarkokba: a Karib-tengeren a sarkok nyílt víz.
const KARIB_START := ["nassau", "havanna", "portroyal", "tortuga",
	"santodomingo", "santiago", "exuma", "campeche"]

static func start_positions() -> Array[Vector2]:
	var n := maxi(GameState.oldalak.size(), 2)
	if GameState.pirate:
		var out_k: Array[Vector2] = []
		for i in range(n):
			var kulcs: String = KARIB_START[i % KARIB_START.size()]
			var p: Array = KARIB_HELY[kulcs]
			out_k.append(Vector2(float(p[0]) * GameState.WORLD_W,
				float(p[1]) * GameState.WORLD_H))
		return out_k
	if n == 2:
		return [
			Vector2(380.0, GameState.WORLD_H - 380.0),
			Vector2(GameState.WORLD_W - 380.0, 380.0),
		]
	var out: Array[Vector2] = []
	var cx := float(GameState.WORLD_W) * 0.5
	var cy := float(GameState.WORLD_H) * 0.5
	var rx := float(GameState.WORLD_W) * 0.38
	var ry := float(GameState.WORLD_H) * 0.38
	for i in range(n):
		# A 0. oldal bal alul, a többi onnan körben.
		var a := PI * 0.75 + TAU * float(i) / float(n)
		out.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return out

# A nagyobb pályára arányosan több lelőhely kell.
func _area_scale() -> float:
	var base := float(GameState.WORLD_BASE.x * GameState.WORLD_BASE.y)
	return sqrt(float(GameState.WORLD_W * GameState.WORLD_H) / base)

# Melyik lelőhelyre melyik szorzó vonatkozik.
const RES_MUL := {
	"wood_node": "tree", "stone_node": "stone", "gold_node": "gold",
	"food_node": "tree",
}

func _gen_resources(terrain: Node, wmap: Array) -> void:
	var scale := _area_scale()
	# Kezdőcsomag mindkét bázis köré: fa, kő, arany, étel. Ez MINDEN tájon
	# jár, különben a sivatagban indulni sem lehetne.
	for base: Vector2 in start_positions():
		var i := 0
		for kind in ["wood_node", "wood_node", "food_node", "food_node",
					 "stone_node", "gold_node"]:
			var placed := false
			for _try in range(40):
				var a := srange(0.0, TAU)
				var d := srange(150.0, 420.0)
				var p := base + Vector2(cos(a), sin(a)) * d
				if _valid_land(wmap, p):
					terrain.add_resource(kind, p)
					placed = true
					break
			if not placed:
				terrain.add_resource(kind, base + Vector2(90 + 40 * i, -60))
			i += 1
	# A térkép többi része. A darabszámot a tájtípus szorzója adja: a
	# rengetegben sok a fa, a kopár vidéken az érc.
	for kind in ["wood_node", "stone_node", "gold_node", "food_node"]:
		var mul: float = float(_def.get(str(RES_MUL[kind]), 1.0))
		var db := int(srange_int(7, 11) * scale * mul)
		for _i in range(db):
			for _try in range(60):
				var p := Vector2(srange(80, GameState.WORLD_W - 80),
					srange(80, GameState.WORLD_H - 80))
				if _valid_land(wmap, p):
					terrain.add_resource(kind, p)
					break
	# Halászhelyek a vízen — enélkül a halásznak nincs mit kitermelnie.
	var vizes: float = 2.0 if GameState.pirate else maxf(float(_def.get("sea", 1.0)), 0.4)
	for _i in range(int(srange_int(8, 14) * scale * vizes)):
		for _try in range(60):
			var p := Vector2(srange(80, GameState.WORLD_W - 80),
				srange(80, GameState.WORLD_H - 80))
			if _is_water(wmap, int(p.x), int(p.y)):
				terrain.add_resource("fish_node", p)
				break

func _valid_land(wmap: Array, p: Vector2) -> bool:
	if p.x < 80.0 or p.y < 80.0: return false
	if p.x > GameState.WORLD_W - 80.0 or p.y > GameState.WORLD_H - 80.0: return false
	return not _is_water(wmap, int(p.x), int(p.y))
