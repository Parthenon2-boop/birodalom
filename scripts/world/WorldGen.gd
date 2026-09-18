class_name WorldGen
extends RefCounted

# A víztérkép cellákban készül (nem pixelenként), különben 3400x2400 = 8.16M
# logikai érték keletkezne generálásonként. A kalózvilág pályája jóval
# nagyobb, ezért ott durvább a rács — így a cellák száma kezelhető marad.
const WATER_CELL := 16
const WATER_CELL_PIRATE := 24

var rng := RandomNumberGenerator.new()
var cell : int = WATER_CELL
# A zajküszöb dönti el a víz arányát; a kalózvilág szigetvilág.
var water_level : float = -0.36
# A zaj léptéke: kisebb érték = nagyobb, összefüggőbb földdarabok.
var noise_scale : float = 0.0035

func seed_rng(seed_value: int) -> void:
	rng.seed = seed_value

func srange_int(lo: int, hi: int) -> int:
	return rng.randi_range(lo, hi)

func srange(lo: float, hi: float) -> float:
	return rng.randf_range(lo, hi)

func generate(seed_value: int, terrain_node: Node) -> void:
	seed_rng(seed_value)
	if GameState.pirate:
		cell = WATER_CELL_PIRATE
		# Szigetvilág, de JÁTSZHATÓ szigetekkel: ha túl sok a víz, alig
		# marad hely bázisnak és gazdaságnak. Alacsonyabb zajfrekvencia =
		# nagyobb, összefüggőbb földdarabok.
		water_level = -0.10
		noise_scale = 0.0020
	else:
		cell = WATER_CELL
		water_level = -0.36
		noise_scale = 0.0035
	var water_map := _gen_water_map()
	if not GameState.pirate:
		_carve_lake(water_map)
	terrain_node.apply_water_map(water_map, cell)
	_gen_mountains(terrain_node, water_map)
	_gen_forests(terrain_node, water_map)
	_gen_resources(terrain_node, water_map)
	terrain_node.rebuild()

func _gen_water_map() -> Array:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = rng.randi()
	noise.frequency = noise_scale * float(cell)
	noise.fractal_octaves = 4
	var W := int(ceil(float(GameState.WORLD_W) / cell))
	var H := int(ceil(float(GameState.WORLD_H) / cell))
	var map: Array = []
	map.resize(H)
	for y in range(H):
		var row: Array = []
		row.resize(W)
		for x in range(W):
			# A küszöb dönti el a víz arányát. -0.05-nél a térkép fele víz
			# lett, ami egy szárazföldi RTS-hez sok; -0.22 mellett tavak és
			# öblök maradnak, de a szárazföld összefüggő. A kalózvilágban
			# viszont a tenger a játéktér: ott szigetek kellenek.
			row[x] = noise.get_noise_2d(float(x), float(y)) < water_level
		map[y] = row
	return map

# --- A NAGY TÓ ---
#
# A zajból származó víz apró, EGYMÁSTÓL ELZÁRT tócsákra esik szét: a
# legnagyobb összefüggő folt alig 200x200 képpont volt, az összes víz 3%-a.
# Ettől a kikötő, a halász és mind a négy hajótípus halott tartalom lett a
# sima pályán — egy pocsolyában nem lehet hajót mozgatni.
#
# Ezért a tavak mellé teszünk EGY nagy, összefüggő tavat. Három szabály
# köti:
#
#   1. A bázisoktól a lehető legtávolabb kerül (a legkevésbé zsúfolt
#      helyre), és mindegyik kezdőhely körül marad szárazföldi mozgástér.
#   2. NEM ér a pálya széléig: így nem vág le sarkot, a szárazföldi út
#      körbe mindig megmarad, és a csata nem kényszerül vízi hadviselésre.
#   3. A partvonala szabálytalan — nem korong, hanem tó.
const LAKE_CLEARANCE := 360.0     # ennyi szárazföld marad a bázisok körül
const LAKE_RADIUS_MUL := 0.27     # a pálya rövidebb oldalához mérve
const LAKE_RADIUS_MIN := 260.0

func _carve_lake(map: Array) -> void:
	var starts := start_positions()
	var hely := _lake_spot(starts)
	var center: Vector2 = hely[0]
	var r: float = hely[1]
	if r < LAKE_RADIUS_MIN: return       # nincs hely rá: marad a régi kép

	# A partvonal szabálytalanná tétele: szög szerinti zaj.
	var part := FastNoiseLite.new()
	part.noise_type = FastNoiseLite.TYPE_SIMPLEX
	part.seed = rng.randi()
	part.frequency = 0.9

	var W: int = (map[0] as Array).size()
	var H: int = map.size()
	for cy in range(H):
		var row: Array = map[cy]
		for cx in range(W):
			var p := Vector2((cx + 0.5) * cell, (cy + 0.5) * cell)
			var d := p - center
			var tav := d.length()
			if tav > r * 1.4: continue
			var szog := d.angle()
			# A 0.78..1.18 közti szorzó öblöket és félszigeteket ad.
			var hatar := r * (0.98 + 0.20 * part.get_noise_2d(cos(szog) * 2.0,
				sin(szog) * 2.0))
			if tav <= hatar:
				row[cx] = true

	# A bázisok körüli szárazföldet visszaadjuk: a tó szabálytalan széle
	# nem szoríthatja vízbe a kezdőhelyet.
	for s in starts:
		_clear_water_around(map, s, LAKE_CLEARANCE * 0.8)

func _clear_water_around(map: Array, center: Vector2, radius: float) -> void:
	var W: int = (map[0] as Array).size()
	var H: int = map.size()
	var r2 := radius * radius
	for cy in range(H):
		var row: Array = map[cy]
		for cx in range(W):
			var p := Vector2((cx + 0.5) * cell, (cy + 0.5) * cell)
			if p.distance_squared_to(center) <= r2:
				row[cx] = false

# Hova fér a legnagyobb tó? Rácsban végigpróbáljuk a pályát, és MINDEN
# pontra kiszámoljuk, mekkora tó férne el oda — majd a legnagyobbat
# választjuk. (A „legtávolabb a bázisoktól" önmagában félrevezet: a pálya
# szélén álló pont messze lehet minden bázistól, de a szél levágja a
# tavat. Ezért közvetlenül az elérhető SUGARAT keressük.)
# Visszaad: [középpont, sugár].
func _lake_spot(starts: Array) -> Array:
	var felso := float(mini(GameState.WORLD_W, GameState.WORLD_H)) * LAKE_RADIUS_MUL
	var best := Vector2(GameState.WORLD_W * 0.5, GameState.WORLD_H * 0.5)
	var best_r := -1.0
	for iy in range(9):
		for ix in range(9):
			var p := Vector2(
				lerpf(GameState.WORLD_W * 0.18, GameState.WORLD_W * 0.82, ix / 8.0),
				lerpf(GameState.WORLD_H * 0.18, GameState.WORLD_H * 0.82, iy / 8.0))
			var r := felso
			for s in starts:
				r = minf(r, p.distance_to(s) - LAKE_CLEARANCE)
			# A szélektől is tartunk távolságot: a tó nem vághat le sarkot,
			# különben a szárazföldi út megszakadna a pálya körül.
			r = minf(r, p.x - 120.0)
			r = minf(r, p.y - 120.0)
			r = minf(r, GameState.WORLD_W - 120.0 - p.x)
			r = minf(r, GameState.WORLD_H - 120.0 - p.y)
			if r > best_r:
				best_r = r
				best = p
	return [best, best_r]

# Világkoordinátát vár, cellára vált.
func _is_water(map: Array, x: int, y: int) -> bool:
	var cy := int(y / cell)
	var cx := int(x / cell)
	if cy < 0 or cy >= map.size(): return true
	var row: Array = map[cy]
	if cx < 0 or cx >= row.size(): return true
	return row[cx]

func _gen_mountains(terrain: Node, wmap: Array) -> void:
	# A sziklák a köves felföldre valók; a réten legfeljebb elszórtan.
	var count := srange_int(10, 16)
	for _i in range(count):
		var cx := srange(140, GameState.WORLD_W - 140)
		var cy := srange(140, GameState.WORLD_H - 140)
		if terrain.biome_kind(Vector2(cx, cy)) < 2 and srange(0.0, 1.0) < 0.75:
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
	# Erdő a dús réten sűrűn, a pusztán ritkásan, a sziklás felföldön alig.
	var count := srange_int(20, 30)
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

# A két kezdő bázis környéke — ugyanaz a képlet, mint a Main.gd-ben. A
# játék első perceiben a munkásoknak közelben kell lelőhelyet találniuk,
# különben a fél térképet átgyalogolják.
# A felek kezdőhelyei. Kettőnél a két átellenes sarok (így a legnagyobb a
# távolság), háromtól viszont körben oszlanak el, hogy senki ne kerüljön a
# másik ölébe. UGYANEZT használja a Main a fővárosok kirakásához — ezért
# statikus, és nem két helyen áll a képlet.
static func start_positions() -> Array[Vector2]:
	var n := maxi(GameState.oldalak.size(), 2)
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

func _gen_resources(terrain: Node, wmap: Array) -> void:
	var scale := _area_scale()
	# Kezdőcsomag mindkét bázis köré: fa, kő, arany, étel.
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
	# A térkép többi része. Fix darabszám, csak a helyet keressük újra, ha
	# vízre esne — így nem fordulhat elő erőforrás nélküli pálya.
	for kind in ["wood_node", "stone_node", "gold_node", "food_node"]:
		for _i in range(int(srange_int(7, 11) * scale)):
			for _try in range(60):
				var p := Vector2(srange(80, GameState.WORLD_W - 80),
					srange(80, GameState.WORLD_H - 80))
				if _valid_land(wmap, p):
					terrain.add_resource(kind, p)
					break
	# Halászhelyek a vízen — enélkül a halásznak nincs mit kitermelnie.
	for _i in range(int(srange_int(8, 14) * scale * (2.0 if GameState.pirate else 1.0))):
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


