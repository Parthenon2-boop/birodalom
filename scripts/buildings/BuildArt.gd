class_name BuildArt
extends RefCounted

# ============================================================================
#  ÉPÜLETGRAFIKA — EGY KÉZ, EGY STÍLUS
#
#  Miért készült ez a fájl?
#
#  Az épületek korábban az assets/sprites/buildings LPC-lapokból vágott
#  textúrafoltokat feszítettek a falra és a tetőre. Az a néhány folt egy
#  MÁSIK rajzoló másik fényviszonyai közt készült: hideg, kékesszürke
#  tetők, lapos, fehér vakolat, saját kontúrvastagság. A mellettük álló
#  LPC-katona és a saját kezűleg festett táj így két külön játékból
#  valónak látszott — "nem paszolnak bele".
#
#  A böngészős eredeti (index.html) nem ezt csinálta: ott MINDEN épület
#  vektorosan, kódból rajzolódott — közös anyagkönyvtárból (texAshlar,
#  texPlank, texThatch), közös fényirányból (faceShade/roofShade) és
#  közös vetett árnyékból (shadowShape). Ez a modul ugyanezt hozza vissza
#  Godotban, natívan.
#
#  A HÁROM SZABÁLY, amitől egy stílus lesz belőle:
#
#    1. NÉZŐPONT. Minden ház ugyanonnan látszik: szemből a homlokzat,
#       fölötte a tető síkja kissé felülről. A tető ezért mindig
#       TRAPÉZ — az ereszénél szélesebb, a gerincénél keskenyebb —, és
#       a hajlásszöge ugyanabból a képletből jön minden típusnál.
#    2. FÉNY. A nap bal felülről süt. A homlokzat bal sávja világosabb,
#       a jobb harmada sötétebb, az eresz alatt árnyék ül, a tető pedig
#       a gerinctől az eresz felé sötétedik. Kivétel nincs.
#    3. TUS. Egyetlen kontúrszín (INK) és egyetlen vastagság (1.4 px)
#       zárja le a sziluettet — ugyanaz, ami az egységrajzokon is van.
#
#  Az ANYAG mondja meg a korszakot, nem a forma:
#     15. század  — paticsfal gerendavázzal, zsúptető
#     kora újkor  — faragott kő, fazsindely és cserép
#     ipari kor   — vörös tégla, pala, kémény
#     világháborúk— beton, lapos lemeztető
#
#  TELJESÍTMÉNY. A falak ismételhető anyagmintái EGYSZER készülnek el
#  (ImageTexture, korszakonként és anyagonként), és a gyorsítótárban
#  maradnak: egy fal egyetlen draw_texture_rect. A tetőt sorokban
#  rajzoljuk, mert a trapézra textúrát feszíteni torzítana — de az is
#  tucatnyi hívás, és az épület CSAK állapotváltáskor rajzolódik újra
#  (nem képkockánként). Intel HD 630-on is elfér.
# ============================================================================

# --- Közös tus és földszínek ---
const INK      := Color(0.169, 0.114, 0.071)      # 2b1d12 — egyetlen kontúrszín
const INK_W    := 1.4                              # egyetlen kontúrvastagság
const TALAJ    := Color(0.435, 0.365, 0.251)      # letaposott föld a ház körül
const LABAZAT  := Color(0.604, 0.561, 0.475)      # kőlábazat
const GERENDA  := Color(0.353, 0.235, 0.133)      # tölgy gerendaváz
const ARNY     := Color(0.055, 0.075, 0.043)      # vetett árnyék alapszíne

# A nap iránya: bal felülről. Az árnyék tehát jobbra-le dől.
const NAP      := Vector2(0.34, 0.17)

# --- Falanyagok ---
const FAL_SZIN := {
	"patics": Color(0.867, 0.792, 0.643),   # meszelt patics (dd ca a4)
	"ko":     Color(0.753, 0.698, 0.596),   # faragott mészkő
	"tegla":  Color(0.627, 0.353, 0.235),   # vörös tégla
	"deszka": Color(0.553, 0.396, 0.224),   # tölgydeszka
	"beton":  Color(0.659, 0.643, 0.588),   # beton
}

# --- Tetőanyagok ---
const TETO_SZIN := {
	# A tető LEGYEN sötétebb a falnál: ha a kettő azonos értékű, a ház egy
	# formátlan folttá olvad össze. A zsúp ezért mézbarna, nem szalmasárga.
	"zsup":     Color(0.694, 0.502, 0.247),  # zsúp (szalma)
	"zsindely": Color(0.478, 0.329, 0.176),  # fazsindely
	"cserep":   Color(0.620, 0.286, 0.161),  # égetett cserép
	"pala":     Color(0.396, 0.376, 0.357),  # pala — meleg szürke, nem kék
	"lemez":    Color(0.306, 0.314, 0.286),  # kátrány/lemez
}

# Sormagasság a tetőn: ettől lesz zsúp a zsúp és pala a pala.
const TETO_SOR := {
	"zsup": 7.0, "zsindely": 5.0, "cserep": 5.0, "pala": 4.0, "lemez": 6.5,
}

# Korszaktónus: az évszakkal együtt hűl a kép (tavasz → tél), de a
# palettát végig melegen tartjuk — ez a játék hangulata.
const KOR_TONUS := [
	Color(1.04, 1.00, 0.94),
	Color(1.00, 0.98, 0.93),
	Color(0.98, 0.95, 0.92),
	Color(0.93, 0.94, 0.93),
]

# Melyik épület miből épül, korszakonként: [falanyag, tetőanyag].
# A sor MINDIG négy hosszú (0..3 korszak).
const ANYAG := {
	"hq":       [["patics", "zsup"],   ["ko", "cserep"],      ["tegla", "pala"],   ["beton", "lemez"]],
	"barracks": [["deszka", "zsup"],   ["ko", "zsindely"],    ["tegla", "pala"],   ["beton", "lemez"]],
	"stable":   [["deszka", "zsup"],   ["deszka", "zsindely"], ["tegla", "cserep"], ["beton", "lemez"]],
	"tower":    [["ko", "zsindely"],   ["ko", "cserep"],      ["ko", "pala"],      ["beton", "lemez"]],
	"house":    [["patics", "zsup"],   ["patics", "zsindely"], ["tegla", "cserep"], ["beton", "lemez"]],
	"harbor":   [["deszka", "zsup"],   ["deszka", "zsindely"], ["deszka", "pala"],  ["beton", "lemez"]],
	"temple":   [["ko", "zsindely"],   ["ko", "cserep"],      ["ko", "pala"],      ["beton", "lemez"]],
	"goldmine": [["deszka", "zsup"],   ["ko", "zsindely"],    ["tegla", "pala"],   ["beton", "lemez"]],
	"market":   [["deszka", "zsup"],   ["patics", "zsindely"], ["tegla", "cserep"], ["beton", "lemez"]],
	"hospital": [["patics", "zsup"],   ["ko", "cserep"],      ["tegla", "pala"],   ["beton", "lemez"]],
	"smith":    [["ko", "zsindely"],   ["ko", "zsindely"],    ["tegla", "pala"],   ["beton", "lemez"]],
	"academy":  [["ko", "zsindely"],   ["ko", "cserep"],      ["ko", "pala"],      ["beton", "lemez"]],
	# A tetőtlen telkek anyaga a kerítéshez és a burkolathoz kell.
	"farm":     [["deszka", "zsup"],   ["deszka", "zsindely"], ["deszka", "cserep"], ["beton", "lemez"]],
	"sugar":    [["deszka", "zsup"],   ["deszka", "zsindely"], ["deszka", "cserep"], ["deszka", "zsindely"]],
	"airfield": [["beton", "lemez"],   ["beton", "lemez"],    ["beton", "lemez"],  ["beton", "lemez"]],
}

static func _par(tipus: String, age: int) -> Array:
	var sor: Array = ANYAG.get(tipus, ANYAG["house"])
	return sor[clampi(age, 0, 3)]

static func fal_anyag(tipus: String, age: int) -> String:
	return String(_par(tipus, age)[0])

static func teto_anyag(tipus: String, age: int) -> String:
	return String(_par(tipus, age)[1])

static func _tonus(c: Color, age: int) -> Color:
	var t: Color = KOR_TONUS[clampi(age, 0, 3)]
	return Color(clampf(c.r * t.r, 0.0, 1.0), clampf(c.g * t.g, 0.0, 1.0),
		clampf(c.b * t.b, 0.0, 1.0), c.a)

static func fal_szin(mat: String, age: int) -> Color:
	var c: Color = FAL_SZIN.get(mat, FAL_SZIN["patics"])
	return _tonus(c, age)

static func teto_szin(mat: String, age: int) -> Color:
	var c: Color = TETO_SZIN.get(mat, TETO_SZIN["zsup"])
	return _tonus(c, age)

# ============================================================================
#  ANYAGMINTÁK — kódból rajzolt, ISMÉTELHETŐ textúrák
#
#  Egy minta EGYSZER készül el, és onnantól a gyorsítótárból jön. Minden
#  minta hézagmentesen ismételhető: a modul (kőtömb, tégla, deszka) osztója
#  a csempe méretének.
# ============================================================================
static var _tex_cache: Dictionary = {}

static func anyag_tex(mat: String, age: int) -> Texture2D:
	var kulcs := "%s|%d" % [mat, clampi(age, 0, 3)]
	if _tex_cache.has(kulcs):
		return _tex_cache[kulcs]
	var t := _keszit(mat, clampi(age, 0, 3))
	_tex_cache[kulcs] = t
	return t

static func _keszit(mat: String, age: int) -> Texture2D:
	var alap := fal_szin(mat, age)
	var rng := RandomNumberGenerator.new()
	# Rögzített mag: minden gépen ugyanaz a minta (hálózati játszmában is).
	rng.seed = hash(mat) * 31 + age
	match mat:
		"ko":     return _tex_kvader(alap, rng, 16, 10, 64, 40)
		"tegla":  return _tex_kvader(alap, rng, 12, 6, 48, 24)
		"deszka": return _tex_deszka(alap, rng)
		"beton":  return _tex_beton(alap, rng)
		_:        return _tex_vakolat(alap, rng)

# Kőtömb és tégla: eltolt sorok, habarcshézaggal.
static func _tex_kvader(alap: Color, rng: RandomNumberGenerator,
		bw: int, bh: int, w: int, h: int) -> Texture2D:
	var habarcs := alap.darkened(0.30).lerp(Color(0.75, 0.72, 0.66), 0.25)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(habarcs)
	var sorok := h / bh
	for sy in range(sorok):
		var eltol := (bw / 2) if sy % 2 == 1 else 0
		var bx := -bw
		while bx < w:
			var vil := rng.randf_range(-0.10, 0.10)
			var c := alap.lightened(vil) if vil > 0.0 else alap.darkened(-vil)
			# A tömb felső éle kap egy kis fényt, az alja árnyékot: így a
			# fal nem sík folt, hanem kirakott felület.
			for y in range(bh - 1):
				var yy := sy * bh + y
				if yy >= h: break
				var sor_c := c
				if y == 0: sor_c = c.lightened(0.10)
				elif y == bh - 2: sor_c = c.darkened(0.14)
				for x in range(bw - 1):
					var xx := bx + eltol + x
					if xx < 0 or xx >= w: continue
					img.set_pixel(xx, yy, sor_c)
			bx += bw
	return ImageTexture.create_from_image(img)

# Függőleges deszkázat: hézag, erezet.
static func _tex_deszka(alap: Color, rng: RandomNumberGenerator) -> Texture2D:
	const W := 48
	const H := 64
	const PW := 8
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(alap.darkened(0.42))
	for p in range(W / PW):
		var vil := rng.randf_range(-0.12, 0.12)
		var c := alap.lightened(vil) if vil > 0.0 else alap.darkened(-vil)
		for x in range(PW - 1):
			var xx := p * PW + x
			var sav := c
			if x == 0: sav = c.lightened(0.12)
			elif x == PW - 2: sav = c.darkened(0.18)
			for y in range(H):
				img.set_pixel(xx, y, sav)
		# Erezet: néhány hosszú, halvány csík a deszkán.
		for _i in range(3):
			var gx: int = p * PW + rng.randi_range(1, PW - 3)
			var gy: int = rng.randi_range(0, H - 14)
			var gc := c.darkened(0.16)
			for y in range(gy, mini(gy + 12, H)):
				img.set_pixel(gx, y, gc)
	return ImageTexture.create_from_image(img)

# Meszelt patics: sima alap, alig észrevehető szemcsével.
static func _tex_vakolat(alap: Color, rng: RandomNumberGenerator) -> Texture2D:
	const S := 32
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in range(S):
		for x in range(S):
			var d := rng.randf_range(-0.045, 0.045)
			img.set_pixel(x, y, alap.lightened(d) if d > 0.0 else alap.darkened(-d))
	return ImageTexture.create_from_image(img)

# Beton: sima felület, táblahatárokkal.
static func _tex_beton(alap: Color, rng: RandomNumberGenerator) -> Texture2D:
	const S := 32
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in range(S):
		for x in range(S):
			var d := rng.randf_range(-0.035, 0.035)
			var c := alap.lightened(d) if d > 0.0 else alap.darkened(-d)
			if x == 0 or y == 0:
				c = alap.darkened(0.16)          # táblahatár
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

# ============================================================================
#  RAJZOLÓ ELEMEK
# ============================================================================

# Vetett árnyék: a ház talpából jobbra-le dőlő test, alatta lágy folt.
# A sprite-ba SOHA nem sül bele — a talajra kerül, az épület alá.
static func vetett_arnyek(ci: CanvasItem, foot: Rect2, magas: float) -> void:
	var ox := magas * NAP.x
	var oy := magas * NAP.y
	# Letaposott föld a ház körül: enélkül a ház a fű tetején lebeg.
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(foot.position.x - 5.0, foot.end.y),
		Vector2(foot.end.x + 5.0, foot.end.y),
		Vector2(foot.end.x + 2.0, foot.end.y + 5.0),
		Vector2(foot.position.x - 2.0, foot.end.y + 5.0)]),
		Color(TALAJ.r, TALAJ.g, TALAJ.b, 0.22))
	# A test árnyéka. Két rétegben és halványan: egy tömör, éles paralel-
	# ogramma késpengeként vágott bele a fűbe és a vízbe.
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(foot.position.x - 2.0, foot.position.y - 2.0),
		Vector2(foot.end.x + 2.0, foot.position.y - 2.0),
		Vector2(foot.end.x + ox + 3.0, foot.end.y + oy + 3.0),
		Vector2(foot.position.x + ox - 3.0, foot.end.y + oy + 3.0)]),
		Color(ARNY.r, ARNY.g, ARNY.b, 0.10))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(foot.position.x, foot.position.y),
		Vector2(foot.end.x, foot.position.y),
		Vector2(foot.end.x + ox, foot.end.y + oy),
		Vector2(foot.position.x + ox, foot.end.y + oy)]),
		Color(ARNY.r, ARNY.g, ARNY.b, 0.16))
	# Érintkezési árnyék: a talp alatti keskeny, sötétebb sáv. Ez az, ami
	# TÉNYLEG leülteti a házat a földre.
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(foot.position.x + 1.0, foot.end.y - 3.0),
		Vector2(foot.end.x + 3.0, foot.end.y - 3.0),
		Vector2(foot.end.x + 5.0, foot.end.y + 4.0),
		Vector2(foot.position.x + 3.0, foot.end.y + 4.0)]),
		Color(ARNY.r, ARNY.g, ARNY.b, 0.22))

# Homlokzat: tömör alapszín, rá az ismételhető anyagminta, végül a fény.
static func homlokzat(ci: CanvasItem, r: Rect2, mat: String, age: int) -> void:
	if r.size.x <= 0.0 or r.size.y <= 0.0: return
	var alap := fal_szin(mat, age)
	ci.draw_rect(r, alap, true)
	var t := anyag_tex(mat, age)
	if t != null:
		ci.draw_texture_rect(t, r, true)
	# 2. SZABÁLY — a fény bal felülről jön.
	ci.draw_rect(Rect2(r.position.x, r.position.y, r.size.x * 0.13, r.size.y),
		Color(1.0, 0.96, 0.86, 0.11), true)
	ci.draw_rect(Rect2(r.end.x - r.size.x * 0.26, r.position.y,
		r.size.x * 0.26, r.size.y), Color(0.09, 0.06, 0.04, 0.20), true)
	# Az eresz árnyéka a fal tetején: ettől ül rá a tető a falra.
	ci.draw_rect(Rect2(r.position.x, r.position.y, r.size.x,
		minf(6.0, r.size.y * 0.32)), Color(0.09, 0.06, 0.04, 0.26), true)

# Gerendaváz a paticsfalon — ez teszi félreismerhetetlenül középkorivá.
static func gerendavaz(ci: CanvasItem, r: Rect2) -> void:
	if r.size.y < 16.0: return
	var v := clampf(r.size.x * 0.045, 2.4, 4.0)
	var gc := GERENDA
	# Talpgerenda, koszorú, sarokoszlopok
	ci.draw_rect(Rect2(r.position.x, r.position.y + 2.0, r.size.x, v), gc, true)
	ci.draw_rect(Rect2(r.position.x, r.end.y - v - 1.0, r.size.x, v), gc, true)
	ci.draw_rect(Rect2(r.position.x, r.position.y, v, r.size.y), gc, true)
	ci.draw_rect(Rect2(r.end.x - v, r.position.y, v, r.size.y), gc, true)
	# Középoszlopok és két andráskereszt
	var db := maxi(1, int(r.size.x / 30.0))
	for i in range(1, db + 1):
		var x := r.position.x + r.size.x * float(i) / float(db + 1)
		ci.draw_rect(Rect2(x - v * 0.5, r.position.y, v, r.size.y), gc, true)
	if r.size.y > 26.0:
		var y0 := r.position.y + r.size.y * 0.30
		var y1 := r.end.y - v - 1.0
		var bx := r.position.x + r.size.x * 0.5 / float(db + 1)
		ci.draw_line(Vector2(r.position.x + v, y1), Vector2(bx + 2.0, y0), gc, v * 0.8)
		ci.draw_line(Vector2(r.end.x - v, y1),
			Vector2(r.end.x - r.size.x * 0.5 / float(db + 1) - 2.0, y0), gc, v * 0.8)

# Kőlábazat: a ház talpa. Enélkül a fal a semmiből nő ki.
static func labazat(ci: CanvasItem, r: Rect2, age: int) -> void:
	if r.size.y < 10.0: return
	var m := clampf(r.size.y * 0.16, 4.0, 8.0)
	var lr := Rect2(r.position.x - 1.5, r.end.y - m, r.size.x + 3.0, m)
	ci.draw_rect(lr, _tonus(LABAZAT, age), true)
	ci.draw_rect(Rect2(lr.position.x, lr.position.y, lr.size.x, 1.5),
		Color(1, 0.98, 0.9, 0.18), true)
	ci.draw_rect(Rect2(lr.position.x, lr.end.y - 2.0, lr.size.x, 2.0),
		Color(0, 0, 0, 0.30), true)
	ci.draw_rect(lr, Color(INK.r, INK.g, INK.b, 0.75), false, 1.0)

# A tető TRAPÉZ: az ereszénél szélesebb, a gerincénél keskenyebb — ugyanaz
# a nézőpont minden típusnál (1. SZABÁLY). Sorokban rajzoljuk, mert a
# trapézra feszített textúra torzulna; a sorok viszont maguktól követik a
# lejtést, és ettől lesz cserép a cserép, zsúp a zsúp.
#
#   felso_y / felso_w — a gerinc
#   also_y  / also_w  — az eresz
#   vagas             — efölött még nem áll a tető (építkezés)
static func teto(ci: CanvasItem, felso_y: float, felso_w: float,
		also_y: float, also_w: float, mat: String, age: int) -> void:
	var h := also_y - felso_y
	if h <= 0.5 or also_w <= 0.0: return
	var alap := teto_szin(mat, age)
	var sotet := alap.darkened(0.40)
	var rh: float = TETO_SOR.get(mat, 5.0)
	var n := clampi(int(ceil(h / rh)), 2, 22)
	var fuge := mat == "zsindely" or mat == "cserep" or mat == "pala"
	for i in range(n):
		var t0 := float(i) / float(n)
		var t1 := float(i + 1) / float(n)
		var y0 := felso_y + h * t0
		var y1 := felso_y + h * t1
		var w0 := lerpf(felso_w, also_w, t0)
		var w1 := lerpf(felso_w, also_w, t1)
		# A gerinctől az eresz felé sötétedik (2. SZABÁLY).
		var c := alap.lerp(sotet, t1 * 0.55)
		if i % 2 == 1: c = c.darkened(0.045)
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(-w0 * 0.5, y0), Vector2(w0 * 0.5, y0),
			Vector2(w1 * 0.5, y1 + 0.8), Vector2(-w1 * 0.5, y1 + 0.8)]), c)
		# Sorárnyék: a cserép/zsindely alsó éle
		ci.draw_line(Vector2(-w1 * 0.5, y1), Vector2(w1 * 0.5, y1),
			Color(sotet.r, sotet.g, sotet.b, 0.55), 1.0)
		# Függőleges hézagok — csak minden második soron, hogy olcsó maradjon.
		if fuge and i % 2 == 0 and w1 > 16.0:
			var lep := 9.0 if mat == "pala" else 7.0
			var x := -w1 * 0.5 + lep * 0.5
			while x < w1 * 0.5:
				ci.draw_line(Vector2(x, y0 + 0.5), Vector2(x, y1),
					Color(sotet.r, sotet.g, sotet.b, 0.40), 1.0)
				x += lep
		elif mat == "zsup" and w1 > 14.0:
			# Zsúp: a nád "fésült" — a sorok alja világos perem, és néhány
			# szálköteg végigfut a soron. Ettől nem deszkázatnak látszik.
			var vil := alap.lightened(0.20)
			ci.draw_line(Vector2(-w1 * 0.5, y1 - 0.8), Vector2(w1 * 0.5, y1 - 0.8),
				Color(vil.r, vil.g, vil.b, 0.32), 1.6)
			if i % 2 == 0:
				var sx := -w1 * 0.5 + 5.0
				while sx < w1 * 0.5 - 2.0:
					ci.draw_line(Vector2(sx, y0 + 1.0), Vector2(sx + 1.5, y1 - 1.0),
						Color(sotet.r, sotet.g, sotet.b, 0.22), 1.0)
					sx += 11.0
		elif mat == "lemez" and i % 2 == 0 and w1 > 16.0:
			var x2 := -w1 * 0.5 + 6.0
			while x2 < w1 * 0.5:
				ci.draw_line(Vector2(x2, y0), Vector2(x2, y1),
					Color(1, 1, 1, 0.07), 1.2)
				x2 += 12.0
	# Oldalirányú fény a tetősíkon. LÉPCSŐZVE, nem egyetlen ugrással: egy
	# éles szélű sötét sáv facettákra vágta szét a tetőt, mintha origamiból
	# hajtogatták volna.
	for s in [[-0.50, -0.34, 0.05], [-0.34, -0.20, 0.03]]:
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(felso_w * s[0], felso_y), Vector2(felso_w * s[1], felso_y),
			Vector2(also_w * s[1], also_y), Vector2(also_w * s[0], also_y)]),
			Color(1.0, 0.96, 0.84, s[2]))
	for s2 in [[0.14, 0.30, 0.04], [0.30, 0.40, 0.05], [0.40, 0.50, 0.06]]:
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(felso_w * s2[0], felso_y), Vector2(felso_w * s2[1], felso_y),
			Vector2(also_w * s2[1], also_y), Vector2(also_w * s2[0], also_y)]),
			Color(0.08, 0.05, 0.03, s2[2]))
	# Gerincdeszka / kúpcserép
	var gc := alap.lightened(0.22) if mat == "zsup" else alap.lightened(0.14)
	ci.draw_rect(Rect2(-felso_w * 0.5 - 1.5, felso_y - 2.0, felso_w + 3.0, 3.2),
		gc, true)
	ci.draw_line(Vector2(-felso_w * 0.5 - 1.5, felso_y - 2.0),
		Vector2(felso_w * 0.5 + 1.5, felso_y - 2.0), Color(1, 0.97, 0.88, 0.35), 1.0)
	# Eresz: világos perem + vastag tus. A világos csík az, ami elválasztja
	# a tetőt a homlokzattól, ha a kettő értéke közel esik.
	ci.draw_line(Vector2(-also_w * 0.5, also_y - 2.0),
		Vector2(also_w * 0.5, also_y - 2.0), alap.lightened(0.20), 1.6)
	ci.draw_line(Vector2(-also_w * 0.5, also_y), Vector2(also_w * 0.5, also_y),
		INK, 2.6)
	# 3. SZABÁLY — a trapéz két ferde éle tussal.
	ci.draw_polyline(PackedVector2Array([
		Vector2(-felso_w * 0.5 - 1.5, felso_y - 2.0),
		Vector2(felso_w * 0.5 + 1.5, felso_y - 2.0),
		Vector2(also_w * 0.5, also_y), Vector2(-also_w * 0.5, also_y),
		Vector2(-felso_w * 0.5 - 1.5, felso_y - 2.0)]), INK, INK_W)

# ============================================================================
#  KIS IKON — a HUD építési gombjaira és a kijelölő panelre.
#  Ugyanaz a nézőpont, ugyanaz a paletta, ugyanaz a tus — csak textúra
#  nélkül, mert 22 pixelen úgyis eltűnne.
# ============================================================================
static func ikon(ci: CanvasItem, tipus: String, age: int, r: Rect2) -> void:
	var fal_m := fal_anyag(tipus, age)
	var teto_m := teto_anyag(tipus, age)
	var fc := fal_szin(fal_m, age)
	var tc := teto_szin(teto_m, age)
	var w := r.size.x * 0.76
	var cx := r.position.x + r.size.x * 0.5
	var also := r.end.y - r.size.y * 0.10
	# Lapos telkek: szántó / betonpálya
	if tipus == "farm" or tipus == "sugar" or tipus == "airfield":
		var p := Rect2(cx - w * 0.5, r.position.y + r.size.y * 0.30, w, r.size.y * 0.52)
		ci.draw_rect(p, Color(0.353, 0.271, 0.161) if tipus != "airfield"
			else fal_szin("beton", age), true)
		for i in range(3):
			var y := p.position.y + p.size.y * (float(i) + 0.5) / 3.0
			ci.draw_line(Vector2(p.position.x + 1.0, y), Vector2(p.end.x - 1.0, y),
				Color(0.35, 0.55, 0.20) if tipus == "farm"
				else (Color(0.42, 0.62, 0.24) if tipus == "sugar"
				else Color(0.92, 0.92, 0.86)), 1.6)
		ci.draw_rect(p, INK, false, INK_W)
		return
	# Talpárnyék
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(cx - w * 0.5, also), Vector2(cx + w * 0.5, also),
		Vector2(cx + w * 0.5 + 3.0, also + 2.5),
		Vector2(cx - w * 0.5 + 3.0, also + 2.5)]),
		Color(ARNY.r, ARNY.g, ARNY.b, 0.30))
	var fh := r.size.y * 0.36
	var fal := Rect2(cx - w * 0.5, also - fh, w, fh)
	ci.draw_rect(fal, fc, true)
	ci.draw_rect(Rect2(fal.end.x - w * 0.26, fal.position.y, w * 0.26, fh),
		Color(0.09, 0.06, 0.04, 0.22), true)
	ci.draw_rect(Rect2(fal.position.x, fal.end.y - 2.0, fal.size.x, 2.0),
		_tonus(LABAZAT, age), true)
	if fal_m == "patics":
		ci.draw_rect(Rect2(fal.position.x + w * 0.46, fal.position.y, w * 0.08, fh),
			GERENDA, true)
	# Ajtó
	ci.draw_rect(Rect2(cx - w * 0.09, fal.end.y - fh * 0.55, w * 0.18, fh * 0.53),
		Color(0.192, 0.122, 0.078), true)
	# Tető
	var th := r.size.y * (0.42 if tipus == "tower" or tipus == "temple" else 0.30)
	var also_w := w + r.size.x * 0.12
	var felso_w := also_w * (0.12 if tipus == "tower" else 0.36)
	var ty := fal.position.y
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(cx - felso_w * 0.5, ty - th), Vector2(cx + felso_w * 0.5, ty - th),
		Vector2(cx + also_w * 0.5, ty), Vector2(cx - also_w * 0.5, ty)]), tc)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(cx + felso_w * 0.1, ty - th), Vector2(cx + felso_w * 0.5, ty - th),
		Vector2(cx + also_w * 0.5, ty), Vector2(cx + also_w * 0.1, ty)]),
		Color(0.08, 0.05, 0.03, 0.18))
	ci.draw_polyline(PackedVector2Array([
		Vector2(cx - felso_w * 0.5, ty - th), Vector2(cx + felso_w * 0.5, ty - th),
		Vector2(cx + also_w * 0.5, ty), Vector2(cx - also_w * 0.5, ty),
		Vector2(cx - felso_w * 0.5, ty - th)]), INK, 1.2)
	ci.draw_line(Vector2(fal.position.x, fal.position.y),
		Vector2(fal.position.x, fal.end.y), INK, 1.2)
	ci.draw_line(Vector2(fal.end.x, fal.position.y),
		Vector2(fal.end.x, fal.end.y), INK, 1.2)
	ci.draw_line(Vector2(fal.position.x, fal.end.y),
		Vector2(fal.end.x, fal.end.y), INK, 1.2)
	_ikon_jegy(ci, tipus, cx, fal, ty - th, also_w)

# Egy áruló jegy, hogy a gombon is megkülönböztethető legyen.
static func _ikon_jegy(ci: CanvasItem, tipus: String, cx: float,
		fal: Rect2, teto_y: float, tw: float) -> void:
	match tipus:
		"hq":
			ci.draw_line(Vector2(cx - tw * 0.22, teto_y),
				Vector2(cx - tw * 0.22, teto_y - 7.0), Color(0.26, 0.20, 0.13), 1.6)
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(cx - tw * 0.22, teto_y - 7.0),
				Vector2(cx - tw * 0.22 + 7.0, teto_y - 5.0),
				Vector2(cx - tw * 0.22, teto_y - 3.0)]), Color(0.784, 0.639, 0.169))
		"temple", "academy":
			ci.draw_line(Vector2(cx, teto_y), Vector2(cx, teto_y - 6.0),
				Color(0.784, 0.639, 0.169), 1.8)
		"tower":
			ci.draw_rect(Rect2(cx - 1.5, fal.position.y + 3.0, 3.0, 5.0),
				Color(0.09, 0.08, 0.07), true)
		"barracks":
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(fal.position.x + 3.0, fal.end.y - 2.0),
				Vector2(fal.position.x + 6.0, fal.end.y - 8.0),
				Vector2(fal.position.x + 9.0, fal.end.y - 2.0)]),
				Color(0.36, 0.25, 0.15))
		"hospital":
			var k := Color(0.76, 0.18, 0.16)
			ci.draw_rect(Rect2(cx + fal.size.x * 0.22, fal.position.y + 3.0, 2.0, 7.0), k, true)
			ci.draw_rect(Rect2(cx + fal.size.x * 0.22 - 2.5, fal.position.y + 5.5, 7.0, 2.0), k, true)
		"smith":
			ci.draw_rect(Rect2(fal.position.x + 3.0, fal.end.y - 8.0, 6.0, 6.0),
				Color(1.6, 0.8, 0.25), true)
		"goldmine":
			ci.draw_circle(Vector2(fal.end.x - 5.0, fal.end.y - 5.0), 2.4,
				Color(0.82, 0.68, 0.28))
		"market":
			ci.draw_rect(Rect2(fal.position.x, fal.position.y + fal.size.y * 0.42,
				fal.size.x, 3.0), Color(0.78, 0.26, 0.22), true)
		"harbor":
			ci.draw_rect(Rect2(fal.position.x - 2.0, fal.end.y, fal.size.x + 4.0, 3.0),
				Color(0.48, 0.36, 0.22), true)
		"stable":
			ci.draw_rect(Rect2(cx - fal.size.x * 0.2, fal.end.y - fal.size.y * 0.6,
				fal.size.x * 0.4, fal.size.y * 0.58), Color(0.34, 0.22, 0.13), true)
		_:
			pass
