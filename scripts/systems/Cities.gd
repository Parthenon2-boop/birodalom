extends Node2D

# A KARIB-TENGER VÁROSAI ÉS AZ OSTROM  (index.html: 29/D–29/E)
#
# A kalózvilág kikötővárosai nem díszletek: mindegyiknek van LAKOSSÁGA és
# VÉDELME, és el lehet foglalni őket.
#
#   LAKOSSÁG  — játszmánként más (250–900 fő). Ez a város ellenállása:
#               amíg áll, a partraszállás visszaverhető.
#   TORONY    — legfeljebb négy. Amíg torony áll, a hajókra tüzel, és a
#               lakosságot védi a sortűztől.
#   FAL       — a lakosság fogyását lassítja, amíg le nem törik.
#
# Az ostrom menete:
#   1. Ágyúval szét kell lőni a tornyokat — addig a lakosság védve van.
#   2. A sortűz ezután a lakosságot fogyasztja.
#   3. Húsz lakos alatt kiáll az utolsó helyőrség; azt legyőzve a
#      partra tett katonák elfoglalják (vagy kifosztják) a várost.
#
# A saját városodban épített LAKÓHÁZ növeli a lakosságot, a TORONY pedig a
# védművet — vagyis a várost védhetőbbé teszi.

const KIKOTOK := [
	{"kulcs": "nassau",       "nev": "NASSAU",         "feszek": true},
	{"kulcs": "tortuga",      "nev": "TORTUGA",        "feszek": true},
	{"kulcs": "portroyal",    "nev": "PORT ROYAL",     "feszek": true},
	{"kulcs": "havanna",      "nev": "HAVANNA",        "feszek": false},
	{"kulcs": "santiago",     "nev": "SANTIAGO",       "feszek": false},
	{"kulcs": "trinidad",     "nev": "TRINIDAD",       "feszek": false},
	{"kulcs": "matanzas",     "nev": "MATANZAS",       "feszek": false},
	{"kulcs": "santodomingo", "nev": "SANTO DOMINGO",  "feszek": false},
	{"kulcs": "gonaives",     "nev": "GONAÏVES",       "feszek": false},
	{"kulcs": "eleuthera",    "nev": "ELEUTHERA",      "feszek": false},
	{"kulcs": "exuma",        "nev": "EXUMA",          "feszek": false},
	{"kulcs": "crooked",      "nev": "CROOKED ISLAND", "feszek": false},
	{"kulcs": "caymanbrac",   "nev": "CAYMAN BRAC",    "feszek": false},
	{"kulcs": "campeche",     "nev": "CAMPECHE",       "feszek": false},
]

const LAKOS_MIN := 250.0
const LAKOS_MAX := 900.0
const LAKOS_FELSO := 1200.0
const TORONY_MAX := 4
const OSTROM_TAV := 300.0        # ekkora körben lő a HAJÓ a városra
const VAROS_TAV := 360.0         # és ekkorából lő vissza a VÁROS
const VAROS_TUZ_KOZ := 2.2       # ennyi másodpercenként ereszt egy sortüzet
const VAROS_TUZ_ERO := [10.0, 26.0]
const OSTROM_ERO := 0.9          # ennyi lakos vész el találatonként
const TORONY_KOPAS := 0.022      # ennyit kopik a torony találatonként
const PARTRA_LAKOS := 20.0       # ez alatt száll partra a legénység
const HELYORSEG_ALAP := 3
const ZSAKMANY_LAKOS := 2.2      # ennyi arany lakosonként kifosztáskor
const BEKE_IDO := 10.0           # ennyi nyugalom után épül újjá a város
const UJJAEPULES := 2.4          # ennyi lakos szivárog vissza másodpercenként
const TORONY_EPITES := 75.0      # ennyi idő alatt húznak fel egy tornyot
const VAROS_SUGAR := 420.0       # ekkora körben tartoznak hozzá az épületek

var main: Node = null
var varosok: Dictionary = {}     # kulcs -> adatok
var _pos: Dictionary = {}        # kulcs -> világkoordináta
var _rng := RandomNumberGenerator.new()

func _init(m: Node = null) -> void:
	main = m

func _ready() -> void:
	name = "Cities"
	z_index = 3
	if main == null: main = get_tree().get_first_node_in_group("main")
	# A városok adatai a játszma magjából jönnek: minden gépen ugyanazok.
	_rng.seed = GameState.sim_mag ^ 0x5EA0C17
	_init_cities()
	set_process(true)

# A városok a Karib-térkép nevezetes kikötőibe kerülnek, a partra igazítva.
func _init_cities() -> void:
	var gen := WorldGen.new()
	for v in KIKOTOK:
		var kulcs := str(v["kulcs"])
		var p: Array = WorldGen.KARIB_HELY.get(kulcs, [0.5, 0.5])
		_pos[kulcs] = Vector2(float(p[0]) * GameState.WORLD_W,
			float(p[1]) * GameState.WORLD_H)
		var sajat := false
		varosok[kulcs] = {
			"lakos": LAKOS_MIN + _rng.randf() * (LAKOS_MAX - LAKOS_MIN),
			"lakos_max": LAKOS_FELSO,
			"lakos_bonusz": 0.0,
			"torony": _rng.randi_range(0, TORONY_MAX),
			"torony_eredeti": 0,
			"torony_hp": 1.0,
			"torony_epit": 0.0,
			"fal": _rng.randf() < 0.5,
			"tuz_t": 0.0,
			"vissza_t": 0.0,
			"beke_t": 0.0,
			"helyorseg": false,
			"gazda": -1,
		}
		varosok[kulcs]["torony_eredeti"] = int(varosok[kulcs]["torony"])
	# A kezdőhelyeken álló városok a feleké: ott kevesebb védmű van.
	var starts := WorldGen.start_positions()
	for i in starts.size():
		var k := _nearest_key(starts[i], 500.0)
		if k == "": continue
		varosok[k]["lakos"] = 400.0
		varosok[k]["torony"] = 1
		varosok[k]["torony_eredeti"] = 1
		varosok[k]["fal"] = false

func city_pos(kulcs: String) -> Vector2:
	return _pos.get(kulcs, Vector2.ZERO)

# Melyik városra kattintottak? ("" = egyikre sem)
func city_at(p: Vector2, tav: float = 70.0) -> String:
	var best := ""
	var bd := tav
	for kulcs in _pos:
		var d: float = (_pos[kulcs] as Vector2).distance_to(p)
		if d < bd:
			bd = d
			best = str(kulcs)
	return best

func city_name(kulcs: String) -> String:
	return _name_of(kulcs)

# A városhoz tartozó SAJÁT épületek — ezek termelnek neki, és ezekben lehet
# toborozni (index.html: portBuilds).
func city_buildings(kulcs: String, owner_id: int) -> Array:
	var out: Array = []
	var p := city_pos(kulcs)
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or int(b.owner_id) != owner_id: continue
		if b.global_position.distance_to(p) > VAROS_SUGAR: continue
		out.append(b)
	return out

func _nearest_key(p: Vector2, max_d: float) -> String:
	var best := ""
	var bd := max_d
	for kulcs in _pos:
		var d: float = (_pos[kulcs] as Vector2).distance_to(p)
		if d < bd:
			bd = d
			best = str(kulcs)
	return best

# A város kié? A legközelebbi főváros dönti el (index.html: portOwner).
func owner_of(kulcs: String) -> int:
	var p := city_pos(kulcs)
	var o := -1
	var bd := VAROS_SUGAR
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or b.tipus != "hq": continue
		var d: float = b.global_position.distance_to(p)
		if d < bd:
			bd = d
			o = int(b.owner_id)
	return o

# A saját városban a lakóház embert ad, a torony védművet.
func _refresh_own(kulcs: String, a: Dictionary) -> void:
	var p := city_pos(kulcs)
	var hazak := 0
	var tornyok := 0
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or int(b.owner_id) != int(a["gazda"]): continue
		if b.global_position.distance_to(p) > VAROS_SUGAR: continue
		if not b.is_ready(): continue
		if b.tipus == "house": hazak += 1
		elif b.tipus == "tower": tornyok += 1
	a["lakos_bonusz"] = float(hazak) * 60.0
	a["torony"] = mini(TORONY_MAX, maxi(int(a["torony"]), tornyok))

func _process(delta: float) -> void:
	if not GameState.pirate or not GameState.on: return
	if GameState.net_client: return          # a házigazda számol
	_siege_tick(delta)
	queue_redraw()

func _siege_tick(delta: float) -> void:
	for v in KIKOTOK:
		var kulcs := str(v["kulcs"])
		var a: Dictionary = varosok[kulcs]
		var p := city_pos(kulcs)
		var gazda := owner_of(kulcs)
		a["gazda"] = gazda
		if gazda >= 0: _refresh_own(kulcs, a)

		# Ki lövi? A MÁSIK fél ágyús hajói a lőtávon belül.
		var tamado := 0.0
		var tamado_owner := -1
		for u in get_tree().get_nodes_in_group("units"):
			if not is_instance_valid(u) or not u.naval or u.dmg <= 0.0: continue
			if gazda >= 0 and int(u.owner_id) == gazda: continue
			if gazda >= 0 and GameState.allied(int(u.owner_id), gazda): continue
			if u.global_position.distance_to(p) > OSTROM_TAV: continue
			tamado += 1.0 + u.dmg / 40.0
			tamado_owner = int(u.owner_id)

		# A VÁROS VISSZALŐ: a parti üteg minden közeledő ellenséges hajóra
		# tüzel, nem csak arra, amelyik már lövi.
		if int(a["torony"]) > 0:
			a["vissza_t"] = float(a["vissza_t"]) + delta
			if float(a["vissza_t"]) >= VAROS_TUZ_KOZ:
				a["vissza_t"] = 0.0
				_city_fire(kulcs, a, p, gazda)

		if tamado <= 0.0:
			# ÚJJÁÉPÜLÉS: az idegen város nem marad örökre romokban.
			if gazda >= 0: continue
			a["beke_t"] = float(a["beke_t"]) + delta
			if float(a["beke_t"]) > BEKE_IDO:
				a["lakos"] = minf(float(a["lakos_max"]),
					float(a["lakos"]) + delta * UJJAEPULES)
				if int(a["torony"]) < int(a["torony_eredeti"]) \
						and float(a["lakos"]) > float(a["lakos_max"]) * 0.35:
					a["torony_epit"] = float(a["torony_epit"]) + delta
					if float(a["torony_epit"]) > TORONY_EPITES:
						a["torony"] = int(a["torony"]) + 1
						a["torony_epit"] = 0.0
						a["torony_hp"] = 1.0
				if float(a["lakos"]) >= PARTRA_LAKOS: a["helyorseg"] = false
			continue

		a["beke_t"] = 0.0
		# Előbb a tornyok dőlnek, utána fogy a lakosság.
		if int(a["torony"]) > 0:
			a["torony_hp"] = float(a["torony_hp"]) - tamado * delta * TORONY_KOPAS
			if float(a["torony_hp"]) <= 0.0:
				a["torony"] = int(a["torony"]) - 1
				a["torony_hp"] = 1.0
				if tamado_owner == GameState.en_id and main != null:
					main.hud.show_toast(Lang.t("v_torony_ledolt") % int(a["torony"]), 2.5)
				SFX.play("cannon", -4.0)
			continue
		var vedelem: float = 0.55 if bool(a["fal"]) else 1.0
		a["lakos"] = maxf(0.0, float(a["lakos"]) - tamado * delta * OSTROM_ERO * vedelem)
		if bool(a["fal"]) and float(a["lakos"]) < float(a["lakos_max"]) * 0.35:
			a["fal"] = false
			if tamado_owner == GameState.en_id and main != null:
				main.hud.show_toast(Lang.t("v_falak_leomlottak"), 2.5)
		# A küszöb alatt kiáll az utolsó helyőrség.
		if _open(kulcs): _garrison(kulcs, a, p, gazda)
		# Nincs több védő és partra ért a legénység: a város elesik.
		_landing(kulcs, a, p, gazda)

# A parti üteg a LEGKÖZELEBBI ellenséges hajóra tüzel.
func _city_fire(kulcs: String, a: Dictionary, p: Vector2, gazda: int) -> void:
	var cel: Node = null
	var cd := VAROS_TAV * VAROS_TAV
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u) or not u.naval: continue
		if gazda >= 0 and int(u.owner_id) == gazda: continue
		if gazda >= 0 and GameState.allied(int(u.owner_id), gazda): continue
		var d: float = u.global_position.distance_squared_to(p)
		if d < cd:
			cd = d
			cel = u
	if cel == null: return
	var ero: float = VAROS_TUZ_ERO[0] + (VAROS_TUZ_ERO[1] - VAROS_TUZ_ERO[0]) \
		* (float(a["torony"]) / float(TORONY_MAX))
	if cel.has_method("take_damage"):
		cel.take_damage(ero)
	SFX.play("cannon", -6.0)

# Nyitva áll-e a város a partraszállásra?
func _open(kulcs: String) -> bool:
	var a: Dictionary = varosok[kulcs]
	return int(a["torony"]) <= 0 and float(a["lakos"]) < PARTRA_LAKOS

# Az utolsó helyőrség: a maradék férfinép fegyvert fog. Városonként egyszer.
func _garrison(kulcs: String, a: Dictionary, p: Vector2, gazda: int) -> void:
	if bool(a["helyorseg"]): return
	a["helyorseg"] = true
	if main == null: return
	var db := HELYORSEG_ALAP + int(round(float(GameState.diff) * 1.5))
	for i in range(db):
		var szog := TAU * float(i) / float(db)
		var hely: Vector2 = main.find_land_near(p + Vector2(cos(szog), sin(szog)) * 70.0, 40.0)
		if hely == Vector2.INF: continue
		main.spawn_unit("ranged" if i % 3 == 0 else "spear",
			maxi(gazda, 1), hely, GameState.get_age(maxi(gazda, 1)))
	if main.hud != null:
		main.hud.show_toast(Lang.t("v_helyorseg") % str(_name_of(kulcs)), 3.0)

# A város élő védői a kikötő körül (a támadó szemszögéből).
func _defenders(p: Vector2, tamado: int) -> int:
	var n := 0
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u) or u.naval or u.air: continue
		if int(u.owner_id) == tamado: continue
		if GameState.allied(int(u.owner_id), tamado): continue
		if u.global_position.distance_to(p) < 300.0: n += 1
	return n

# PARTRASZÁLLÁS: a sortűz kiüríti a várost, elfoglalni csak katonával lehet.
func _landing(kulcs: String, a: Dictionary, p: Vector2, gazda: int) -> void:
	if not _open(kulcs): return
	for fel in range(GameState.oldalak.size()):
		if fel == gazda: continue
		var katona := 0
		for u in get_tree().get_nodes_in_group("units"):
			if not is_instance_valid(u) or int(u.owner_id) != fel: continue
			if u.air or u.role == "worker": continue
			var hatar := 320.0 if u.naval else 200.0
			if u.global_position.distance_to(p) < hatar: katona += 1
		if katona <= 0: continue
		if _defenders(p, fel) > 0: continue
		_capture(kulcs, a, fel, gazda)
		return

# A város elesik: a zsákmány arany és hírnév, a lakosság újraindul.
func _capture(kulcs: String, a: Dictionary, uj: int, regi: int) -> void:
	var zsakmany := maxf(60.0, float(a["lakos_max"]) * 0.25 * ZSAKMANY_LAKOS)
	GameState.add_res(uj, "gold", zsakmany)
	GameState.add_res(uj, "rum", 25.0)
	if uj == GameState.en_id:
		GameState.add_fame(14.0)
		if main != null and main.hud != null:
			main.hud.show_toast(Lang.t("v_elfoglalva") % [str(_name_of(kulcs)),
				int(zsakmany)], 4.0)
	a["lakos"] = 120.0
	a["torony"] = 0
	a["torony_eredeti"] = 1
	a["helyorseg"] = false
	a["fal"] = false
	a["beke_t"] = 0.0
	a["gazda"] = uj
	SFX.play("age")

func _name_of(kulcs: String) -> String:
	for v in KIKOTOK:
		if str(v["kulcs"]) == kulcs: return str(v["nev"])
	return kulcs

# --- Kirajzolás: névtábla, lakosság, tornyok ---

func _draw() -> void:
	if not GameState.pirate: return
	var font := ThemeDB.fallback_font
	for v in KIKOTOK:
		var kulcs := str(v["kulcs"])
		var a: Dictionary = varosok.get(kulcs, {})
		if a.is_empty(): continue
		var p := city_pos(kulcs)
		var gazda := int(a.get("gazda", -1))
		var szin := Style.side_color(gazda) if gazda >= 0 else Color("c9a227")
		# A város jele: kis kör, körülötte a tornyok pontjai.
		draw_circle(p + Vector2(0, -34), 7.0, Color(0, 0, 0, 0.45))
		draw_circle(p + Vector2(0, -34), 5.0, szin)
		var tornyok := int(a.get("torony", 0))
		for i in range(tornyok):
			var szog := -PI * 0.5 + (float(i) - (tornyok - 1) * 0.5) * 0.5
			draw_circle(p + Vector2(0, -34) + Vector2(cos(szog), sin(szog)) * 13.0,
				2.6, Color("e8dcc0"))
		var nev := str(v["nev"])
		if bool(v["feszek"]): nev = "★ " + nev
		var w := font.get_string_size(nev, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, p + Vector2(-w * 0.5, -44), nev,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e8dcc0"))
		var also := "%d %s" % [int(a.get("lakos", 0)) + int(a.get("lakos_bonusz", 0)),
			Lang.t("v_lakos")]
		if _open(kulcs): also = Lang.t("v_nyitva")
		var w2 := font.get_string_size(also, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, p + Vector2(-w2 * 0.5, -18), also,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color("f0d98a") if _open(kulcs) else Color("9c8d72"))
		# LŐTÁVGYŰRŰ: az idegen város tornyainak hatósugara. Csak akkor
		# rajzoljuk, ha van a közelben hajód — különben tele lenne a térkép.
		# A belső kör a TIÉD: onnan tudod lőni a várost. A külső, halványabb
		# a városé: azon belül kezd rád tüzelni a part.
		if gazda != GameState.en_id and tornyok > 0 and _ship_near(p):
			_dashed_circle(p, VAROS_TAV, Color(0.82, 0.47, 0.35, 0.30))
			_dashed_circle(p, OSTROM_TAV, Color(0.81, 0.29, 0.23, 0.42))

func _ship_near(p: Vector2) -> bool:
	var d := OSTROM_TAV * 2.1
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u) or int(u.owner_id) != GameState.en_id: continue
		if not u.naval: continue
		if u.global_position.distance_to(p) < d: return true
	return false

# Szaggatott kör: a Godot vonalrajzolója nem tud szaggatni, ezért rövid
# íveket húzunk. A minta lassan körbefordul, hogy a gyűrű "éljen".
func _dashed_circle(kozep: Vector2, r: float, szin: Color) -> void:
	var db := 26
	var lepes := TAU / float(db)
	var forgas := fmod(GameState.t * 0.25, lepes)
	for i in range(db):
		var a0 := forgas + float(i) * lepes
		draw_arc(kozep, r, a0, a0 + lepes * 0.55, 6, szin, 2.0, true)
