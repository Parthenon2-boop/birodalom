extends RefCounted

# AZ ÉPÜLETEK RAJZA A BÖNGÉSZŐS EREDETI SZERINT (index.html drawBuild).
#
# Az eredetiben minden épület egyszer rajzolódott ki egy rejtett vászonra
# (getSprite: PAINT[type] + natOverlay), utána képként másolódott a
# képernyőre. (A 17. századtól a hat alapépületre az eredeti az LPC
# "gyarmati/viktoriánus" képeket tette — assets/sprites/buildings —, de azok
# csak csempékből álló anyaglapok, nem egész házak: épületnek rajzolva
# szétesett foltokként látszottak. Ezért minden korszakban a PAINT-rajz kell,
# amelyet az eredeti az építkezés alatt ezeknél is mutatott.)
#
# Ezt a képet vesszük át SZÓ SZERINT: a PAINT-rajzokat fej nélküli böngészőben
# lefuttattuk és kimentettük (assets/buildings_html, 2x felbontás). A képekbe
# nincs belesütve a csapatszín: minden képhez tartozik egy MASZK (_m.png),
# amelynek vörös csatornája megmondja, mennyi csapatszín, a zöld, hogy mennyi
# kiemelőszín került az adott képpontra. (A vászon színkeverése lineáris a
# csapatszínben, így a kép = alap + maszk.r·csapatszín + maszk.g·kiemelő —
# ezt az árnyaló számolja ki, lásd CSAPAT_ARNYALO.)
#
# Minden más — vetett árnyék, kitűzött telek, állvány, sérülés, kellékek,
# lobogó zászló, kéményfüst, életcsík — élőben rajzolódik, ugyanúgy, mint az
# eredetiben (shadowShape, markedSite, buildSite, damageOverlay, drawDamage,
# drawProps, drawWavingFlag, chimneySmoke, drawHpBar, drawRally).

const MAPPA := "res://assets/buildings_html/"

# Az eredeti épületméretei (BUILDS.w/h) — a rajzok ehhez készültek.
const MERET := {
	"hq": Vector2(104, 104), "barracks": Vector2(80, 80), "stable": Vector2(76, 68),
	"farm": Vector2(56, 56), "tower": Vector2(50, 50), "house": Vector2(56, 44),
	"airfield": Vector2(104, 74), "harbor": Vector2(74, 54), "temple": Vector2(70, 60),
	"goldmine": Vector2(62, 52), "sugar": Vector2(66, 54), "market": Vector2(72, 56),
	"hospital": Vector2(70, 58), "smith": Vector2(66, 56), "academy": Vector2(76, 64),
}
# Az eredeti látszólagos magasságai korszakonként (BH).
const BH := {
	"hq": [58, 52, 56, 38], "barracks": [34, 32, 36, 30], "farm": [16, 18, 18, 16],
	"academy": [46, 48, 50, 36], "temple": [50, 54, 48, 38], "harbor": [34, 38, 40, 32],
	"airfield": [10, 10, 10, 26], "house": [30, 32, 34, 30], "smith": [32, 34, 36, 34],
	"hospital": [30, 32, 34, 32], "market": [26, 28, 30, 28], "goldmine": [24, 26, 28, 26],
	"sugar": [20, 22, 24, 22], "tower": [66, 44, 60, 26], "stable": [30, 28, 32, 28],
}

const CSAPAT_ARNYALO := """
shader_type canvas_item;
uniform sampler2D maszk : filter_linear_mipmap;
uniform vec4 csapat = vec4(1.0);
uniform vec4 kiemelo = vec4(1.0);
varying vec4 v_mod;
void vertex() { v_mod = COLOR; }
void fragment() {
	vec4 b = texture(TEXTURE, UV);
	vec4 m = texture(maszk, UV);
	COLOR = vec4(clamp(b.rgb + m.r * csapat.rgb + m.g * kiemelo.rgb, 0.0, 1.0), b.a) * v_mod;
}
"""

static var _manifest: Dictionary = {}
static var _arnyalo: Shader = null

static func meret(tipus: String) -> Vector2:
	return MERET.get(tipus, Vector2(64, 64))

static func magassag(tipus: String, age: int) -> float:
	var t: Array = BH.get(tipus, [28, 28, 28, 28])
	return float(t[clampi(age, 0, 3)])

static func _man() -> Dictionary:
	if _manifest.is_empty():
		var f := FileAccess.open(MAPPA + "manifest.json", FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary: _manifest = d
	return _manifest

# A kép, a maszk és a hely (a talp közepéhez mérve), amit az épülethez
# rajzolni kell. Üres szótár, ha nincs képünk.
static func kep(tipus: String, age: int, nemzet: String) -> Dictionary:
	var a := clampi(age, 0, 3)
	var man := _man()
	var kulcs := ""
	# A kalózfrakciók csak a vitorlások korában játszanak; minden más esetben
	# a legközelebbi meglévő rajzra esünk vissza (végül a magyarra).
	for jelolt in ["%s_%d_%s" % [tipus, a, nemzet], "%s_%d_%s" % [tipus, 1, nemzet],
			"%s_%d_hu" % [tipus, a], "%s_0_%s" % [tipus, nemzet], "%s_0_hu" % tipus]:
		if man.has(jelolt) and ResourceLoader.exists(MAPPA + jelolt + ".png"):
			kulcs = jelolt
			break
	if kulcs == "": return {}
	var info: Dictionary = man[kulcs]
	var tex: Texture2D = load(MAPPA + kulcs + ".png")
	if tex == null: return {}
	var s: float = float(info.get("s", 2.0))
	var mask: Texture2D = null
	if bool(info.get("m", false)) and ResourceLoader.exists(MAPPA + kulcs + "_m.png"):
		mask = load(MAPPA + kulcs + "_m.png")
	var ox: float = float(info.get("ox", 0.0)) / s
	var oy: float = float(info.get("oy", 0.0)) / s
	return {"tex": tex, "mask": mask,
		"rect": Rect2(-ox, -oy, float(tex.get_width()) / s, float(tex.get_height()) / s)}

# Csapatszín-anyag a maszkos képhez.
static func anyag(mask: Texture2D, csapat: Color, kiemelo: Color) -> ShaderMaterial:
	if _arnyalo == null:
		_arnyalo = Shader.new()
		_arnyalo.code = CSAPAT_ARNYALO
	var mat := ShaderMaterial.new()
	mat.shader = _arnyalo
	mat.set_shader_parameter("maszk", mask)
	mat.set_shader_parameter("csapat", csapat)
	mat.set_shader_parameter("kiemelo", kiemelo)
	return mat

# Kis ikon az építési menübe: ugyanaz a kép, mint a pályán.
static func ikon(ci: CanvasItem, tipus: String, age: int, nemzet: String, hely: Rect2) -> bool:
	var k := kep(tipus, age, nemzet)
	if k.is_empty(): return false
	var r: Rect2 = k["rect"]
	var sc := minf(hely.size.x / r.size.x, hely.size.y / r.size.y)
	var sz := r.size * sc
	ci.draw_texture_rect(k["tex"], Rect2(hely.position + (hely.size - sz) * 0.5, sz), false)
	return true

# --- ÉLŐ RÉTEGEK ---

static func _c(r: int, g: int, b: int, a: float = 1.0) -> Color:
	return Color8(r, g, b, int(round(a * 255.0)))

static func _rand(kulcs: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kulcs)
	return rng

static func _ell(ci: CanvasItem, c: Vector2, r: Vector2, col: Color, rot: float = 0.0) -> void:
	var pts := PackedVector2Array()
	for i in range(20):
		var a := TAU * float(i) / 20.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y).rotated(rot))
	ci.draw_colored_polygon(pts, col)

static func _ell_vonal(ci: CanvasItem, c: Vector2, r: Vector2, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in range(21):
		var a := TAU * float(i) / 20.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	ci.draw_polyline(pts, col, w)

static func _rect(ci: CanvasItem, x: float, y: float, w: float, h: float, col: Color) -> void:
	ci.draw_rect(Rect2(x, y, w, h).abs(), col, true)

static func _szaggatott(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float,
		be: float, ki: float) -> void:
	var hossz := a.distance_to(b)
	if hossz <= 0.0: return
	var d := (b - a) / hossz
	var t := 0.0
	while t < hossz:
		ci.draw_line(a + d * t, a + d * minf(t + be, hossz), col, w)
		t += be + ki

static func _szaggatott_teglalap(ci: CanvasItem, r: Rect2, col: Color, w: float,
		be: float, ki: float) -> void:
	_szaggatott(ci, r.position, Vector2(r.end.x, r.position.y), col, w, be, ki)
	_szaggatott(ci, Vector2(r.end.x, r.position.y), r.end, col, w, be, ki)
	_szaggatott(ci, r.end, Vector2(r.position.x, r.end.y), col, w, be, ki)
	_szaggatott(ci, Vector2(r.position.x, r.end.y), r.position, col, w, be, ki)

# Vetett árnyék (shadowShape) — a kép alá, a nap állása szerint.
static func arnyek(ci: CanvasItem, w: float, h: float, hh: float, dx: float = 0.34,
		dy: float = 0.17) -> void:
	var ox := hh * dx
	var oy := hh * dy
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-w / 2, -h / 2), Vector2(w / 2, -h / 2),
		Vector2(w / 2 + ox, h / 2 + oy), Vector2(-w / 2 + ox, h / 2 + oy)]), _c(12, 20, 10, 0.30))
	_ell(ci, Vector2(ox * 0.4, h / 2 + 2), Vector2(w * 0.56, h * 0.2), _c(12, 20, 10, 0.22))

# Kitűzött telek (markedSite): cövekek, zsinór, felásott föld, tervrajz.
static func kituzott_telek(ci: CanvasItem, w: float, h: float) -> void:
	_ell(ci, Vector2(0, 2), Vector2(w * 0.56, h * 0.36), _c(96, 78, 50, 0.42))
	_szaggatott_teglalap(ci, Rect2(-w / 2, -h / 2, w, h), _c(120, 98, 62, 0.5), 1.0, 5.0, 4.0)
	var cs := [Vector2(-w / 2, -h / 2), Vector2(w / 2, -h / 2), Vector2(w / 2, h / 2),
		Vector2(-w / 2, h / 2)]
	for i in range(4):
		var a: Vector2 = cs[i]
		var c: Vector2 = cs[(i + 1) % 4]
		ci.draw_line(a + Vector2(0, -9), c + Vector2(0, -9), Color("d8c89a"), 1.2)
	for cv in cs:
		var c2: Vector2 = cv
		_rect(ci, c2.x - 1.6, c2.y - 12, 3.2, 12, Color("7a5a30"))
		_rect(ci, c2.x - 1.6, c2.y - 12, 1.4, 12, _c(255, 240, 205, 0.25))
		_rect(ci, c2.x - 2.4, c2.y - 13, 4.8, 2, Color("5e4423"))
	var tr := Transform2D(-0.2, Vector2(-w * 0.2, h / 2 - 4))
	ci.draw_set_transform_matrix(tr)
	_rect(ci, -7, -5, 14, 10, Color("e8dfc4"))
	ci.draw_rect(Rect2(-4.5, -3, 9, 6), _c(90, 70, 45, 0.55), false, 0.8)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	ci.draw_line(Vector2(w * 0.18, h / 2 - 2), Vector2(w * 0.3, h / 2 - 12), Color("6b4a2c"), 1.8)
	_rect(ci, w * 0.28, h / 2 - 15, 5, 4, Color("9aa1a8"))

static func _oszlop(ci: CanvasItem, x: float, base_y: float, top_y: float, wd: float) -> void:
	_rect(ci, x - wd / 2, top_y, wd, base_y - top_y, Color("7a5a30"))
	_rect(ci, x - wd / 2, top_y, wd * 0.4, base_y - top_y, _c(255, 240, 205, 0.20))
	_rect(ci, x + wd * 0.15, top_y, wd * 0.35, base_y - top_y, _c(0, 0, 0, 0.28))
	_rect(ci, x - wd / 2 - 1, top_y, wd + 2, 2.4, Color("5e4423"))

static func _gerenda(ci: CanvasItem, x0: float, y0: float, x1: float, y1: float, wd: float) -> void:
	ci.draw_line(Vector2(x0, y0), Vector2(x1, y1), Color("8a6534"), wd)
	ci.draw_line(Vector2(x0, y0 - wd * 0.28), Vector2(x1, y1 - wd * 0.28),
		_c(255, 240, 205, 0.18), wd * 0.4)

# Az építkezés állványa (buildSite): a hátsó rész a kép mögé, az első elé.
static func allvany(ci: CanvasItem, w: float, h: float, hh: float, elol: bool) -> void:
	var top := -hh - 16.0
	var back_y := -h / 2
	var front_y := h / 2
	var bx := w / 2 + 5
	if not elol:
		_oszlop(ci, -bx, back_y, back_y + top, 4.6)
		_oszlop(ci, bx, back_y, back_y + top, 4.6)
		for i in range(1, 3):
			var y := back_y + top * float(i) / 2.4
			_gerenda(ci, -bx, y, bx, y, 2.6)
		_gerenda(ci, -bx, back_y + top, bx, back_y + top, 3.4)
		_ell(ci, Vector2(0, front_y - 2), Vector2(w * 0.62, h * 0.34), _c(92, 74, 48, 0.55))
		return
	_oszlop(ci, -bx, front_y, front_y + top, 5.2)
	_oszlop(ci, bx, front_y, front_y + top, 5.2)
	for i in range(1, 3):
		var y := front_y + top * float(i) / 2.4
		_gerenda(ci, -bx, y, bx, y, 3.0)
		var x := -bx + 4.0
		while x < bx - 6.0:
			_rect(ci, x, y - 2.6, 9, 2.4, _c(120, 95, 55, 0.75))
			x += 11.0
	_gerenda(ci, -bx, front_y + top, bx, front_y + top, 3.8)
	var mer := _c(122, 90, 48, 0.85)
	ci.draw_line(Vector2(-bx, front_y), Vector2(-bx + w * 0.34, front_y + top * 0.55), mer, 2.0)
	ci.draw_line(Vector2(bx, front_y), Vector2(bx - w * 0.34, front_y + top * 0.55), mer, 2.0)
	var osz := _c(110, 84, 45, 0.7)
	ci.draw_line(Vector2(-bx, front_y + top), Vector2(-bx, back_y + top), osz, 2.2)
	ci.draw_line(Vector2(bx, front_y + top), Vector2(bx, back_y + top), osz, 2.2)
	# létra
	var lx := -w * 0.18
	var ly0 := front_y + 2.0
	var ly1 := front_y + top * 0.92
	var lc := Color("6e5028")
	ci.draw_line(Vector2(lx - 3.5, ly0), Vector2(lx - 3.5, ly1), lc, 1.6)
	ci.draw_line(Vector2(lx + 3.5, ly0), Vector2(lx + 3.5, ly1), lc, 1.6)
	var n := maxi(2, int(floor(absf(ly1 - ly0) / 6.0)))
	for i in range(1, n):
		var yy := ly0 + (ly1 - ly0) * float(i) / float(n)
		ci.draw_line(Vector2(lx - 3.5, yy), Vector2(lx + 3.5, yy), lc, 1.2)
	# kifaragott kőtömbök
	var kx := -w * 0.46
	var ky := front_y + 4.0
	for i in range(5):
		var px := kx + float(i % 3) * 8.0
		var py := ky - float(i / 3) * 5.0
		_rect(ci, px, py - 5, 7.5, 5, Color("c9c4b8") if i % 2 == 1 else Color("b5b0a4"))
		_rect(ci, px, py - 5, 7.5, 1.4, _c(255, 255, 255, 0.25))
		_rect(ci, px, py - 1.4, 7.5, 1.4, _c(0, 0, 0, 0.22))
	# gerendarakás
	for i in range(3):
		var py2 := front_y + 5.0 - float(i) * 4.0
		_rect(ci, w * 0.16, py2 - 4, 26, 3.6, Color("8a6534") if i % 2 == 1 else Color("7a5a30"))
		_rect(ci, w * 0.16 + 24, py2 - 4, 2.4, 3.6, Color("5e4423"))
	# kötélcsomók
	for kv in [[w * 0.44, front_y + 2.0, 4.4], [-w * 0.06, front_y + 7.0, 3.6]]:
		var kk: Array = kv
		for i in range(3):
			var r: float = float(kk[2]) - float(i) * 1.7
			_ell_vonal(ci, Vector2(float(kk[0]), float(kk[1])), Vector2(r, r * 0.45),
				Color("b79a5e"), 1.5)

# Kéményfüst (chimneySmoke) — időfüggő, ezért az élő rétegen.
static func fust(ci: CanvasItem, sx: float, sy: float, seed: float, sc: float, t: float) -> void:
	for i in range(4):
		var u := fmod(t * 0.35 + float(i) * 0.25 + seed, 1.0)
		var a := (1.0 - u) * 0.30
		if a <= 0.0: continue
		ci.draw_circle(Vector2(sx + sin(u * 5.0 + seed * 6.0) * 7.0 * u, sy - u * 34.0 * sc),
			(3.0 + u * 9.0) * sc, _c(190, 190, 185, a))

# Melyik épület füstöl (az eredeti szerint csak ezek).
static func kemenyek(tipus: String, age: int, w: float, h: float, hh: float) -> Array:
	var ki: Array = []
	if tipus == "hq" and age == 2:
		ki.append([-w * 0.36, -h / 2 - hh - 26, 0.1, 1.0])
		ki.append([w * 0.36, -h / 2 - hh - 26, 0.6, 1.0])
	elif tipus == "barracks" and age == 2:
		ki.append([w * 0.3 + 5, -h / 2 - hh - 16, 0.3, 0.8])
	elif tipus == "barracks" and age == 3:
		ki.append([-w * 0.36 + 6, -h / 2 - hh - 20, 0.45, 0.9])
	elif tipus == "farm" and age == 2:
		ki.append([w / 2 - 10, -h / 2 - 22, 0.8, 0.6])
	return ki

# Sérülés (damageOverlay + drawDamage): repedések, korom, hiányzó cserép —
# a rajz az épület azonosítójából sorsolódik, nem villódzik.
static func serules(ci: CanvasItem, w: float, h: float, hh: float, p: float, kulcs: String) -> void:
	if p <= 0.62:
		var r := _rand("dmg" + kulcs)
		var n := int(round((1.0 - p) * 7.0))
		var col := _c(20, 16, 12, 0.55 * (1.0 - p))
		for i in range(n):
			var x := (r.randf() - 0.5) * w * 0.8
			var y := (r.randf() - 0.4) * h * 0.8
			var pts := PackedVector2Array([Vector2(x, y)])
			for j in range(4):
				x += (r.randf() - 0.5) * 11.0
				y += r.randf() * 8.0
				pts.append(Vector2(x, y))
			ci.draw_polyline(pts, col, 1.6)
		if p < 0.34:
			_ell(ci, Vector2.ZERO, Vector2(w * 0.4, h * 0.34), _c(60, 50, 45, 0.18))
	if p > 0.85: return
	var rr := _rand("dmgb" + kulcs)
	var suly := 1.0 - p
	var db := int(round(2.0 + suly * 5.0))
	var rc := _c(28, 22, 16, 0.5 * suly)
	for i in range(db):
		var x0 := (rr.randf() - 0.5) * w * 0.8
		var y0 := -hh * rr.randf() * 0.9
		var pts2 := PackedVector2Array([Vector2(x0, y0)])
		for s in range(3):
			x0 += (rr.randf() - 0.5) * 9.0
			y0 += 4.0 + rr.randf() * 7.0
			pts2.append(Vector2(x0, y0))
		ci.draw_polyline(pts2, rc, 1.2)
	if suly > 0.35:
		for i in range(int(round(suly * 4.0))):
			var x := (rr.randf() - 0.5) * w * 0.9
			var y := -hh * (0.2 + rr.randf() * 0.7)
			_ell(ci, Vector2(x, y), Vector2(5.0 + rr.randf() * 8.0, 4.0 + rr.randf() * 6.0),
				_c(24, 20, 16, 0.3 * suly), rr.randf() * TAU)
	if suly > 0.5:
		for i in range(int(round((suly - 0.5) * 8.0))):
			var x := (rr.randf() - 0.5) * w * 0.7
			var y := -hh + rr.randf() * 8.0
			_rect(ci, x, y, 3.0 + rr.randf() * 4.0, 2.4 + rr.randf() * 2.0, _c(20, 16, 12, 0.5))

# Égés a súlyosan sérült épületen (damageOverlay, p < 0.34) — időfüggő.
static func eges(ci: CanvasItem, w: float, h: float, p: float, kulcs: String, t: float,
		fazis: float) -> void:
	if p >= 0.34: return
	var r := _rand("dmg" + kulcs)
	fust(ci, (r.randf() - 0.5) * w * 0.4, -h * 0.2, r.randf(), 1.3, t)
	var f := 0.5 + sin(t * 9.0 + fazis) * 0.5
	_ell(ci, Vector2(w * 0.16, -h * 0.1), Vector2(4.0 + f * 3.0, 7.0 + f * 4.0),
		_c(228, 140, 50, 0.35 + f * 0.3))

# Kellékek az épület körül (drawProps).
static func kellekek(ci: CanvasItem, tipus: String, w: float, h: float) -> void:
	match tipus:
		"farm":
			var kc := _c(122, 96, 58, 0.85)
			var kw := w * 0.62
			var kh := h * 0.5
			for i in range(-3, 4):
				var x := float(i) * (kw / 3.0)
				ci.draw_line(Vector2(x, kh), Vector2(x, kh - 6), kc, 1.6)
			ci.draw_line(Vector2(-kw, kh - 3.4), Vector2(kw, kh - 3.4), kc, 1.6)
			_ell(ci, Vector2(w * 0.42, h * 0.28), Vector2(7, 5), Color("c8a44e"))
			_ell(ci, Vector2(w * 0.42, h * 0.34), Vector2(7, 2.6), Color("b08c38"))
		"barracks", "smith", "stable":
			for i in range(3):
				for j in range(2 - i / 2):
					_rect(ci, -w * 0.5 - 10 + float(i) * 5, h * 0.2 - float(j) * 4.4, 4.4, 4,
						Color("6a4a2c"))
			for i in range(3):
				_rect(ci, -w * 0.5 - 10 + float(i) * 5, h * 0.2 - 4.4 * float(2 - i / 2) + 1,
					4.4, 1.4, Color("8a6a44"))
		"house", "hq":
			var wx := w * 0.5 + 9
			var wy := h * 0.24
			_ell(ci, Vector2(wx, wy), Vector2(6, 3.4), Color("8a8a84"))
			_ell(ci, Vector2(wx, wy - 0.6), Vector2(4, 2.2), Color("2a2a26"))
			ci.draw_line(Vector2(wx - 4, wy - 2), Vector2(wx - 4, wy - 11), Color("6a4a2c"), 1.4)
			ci.draw_line(Vector2(wx + 4, wy - 2), Vector2(wx + 4, wy - 11), Color("6a4a2c"), 1.4)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(wx - 6, wy - 10),
				Vector2(wx, wy - 15), Vector2(wx + 6, wy - 10)]), Color("7a5a34"))
		"harbor":
			for i in range(3):
				var x := -w * 0.4 + float(i) * 11.0
				var y := h * 0.26 + float(i % 2) * 3.0
				_ell(ci, Vector2(x, y), Vector2(4, 5), Color("7a5a34"))
				ci.draw_line(Vector2(x - 4, y), Vector2(x + 4, y), Color("5a4028"), 0.9)
		"market":
			_rect(ci, w * 0.36, h * 0.14, 9, 7, Color("8a6a42"))
			_ell(ci, Vector2(w * 0.36 + 14, h * 0.24), Vector2(4.4, 5.4), Color("c8b487"), 0.1)

# Lobogó zászló a rúdon (drawWavingFlag): keskeny csíkokból, két eltérő
# ütemű hullám összegéből; a rúdnál nyugodt, a végén erős.
static func zaszlo(ci: CanvasItem, tex: Texture2D, x: float, y: float, w: float,
		fazis: float) -> void:
	if tex == null: return
	var iw := float(tex.get_width())
	var ih := float(tex.get_height())
	var h := w * ih / maxf(iw, 1.0)
	var n := 16
	var sw := w / float(n)
	var sh := iw / float(n)
	var amp := h * 0.26
	for i in range(n):
		var t := float(i) / float(n - 1)
		var wv := (sin(fazis + t * 3.6) * 0.62 + sin(fazis * 1.43 + t * 6.1) * 0.38) * 0.72
		var off := wv * amp * t * t * (1.6 - t * 0.6)
		var sc := 1.0 - absf(wv) * 0.07 * t
		ci.draw_texture_rect_region(tex, Rect2(x + float(i) * sw, y + off, sw + 0.7, h * sc),
			Rect2(float(i) * sh, 0.0, sh, ih))
		if wv < -0.12:
			_rect(ci, x + float(i) * sw, y + off, sw + 0.7, h * sc, _c(0, 0, 0, 0.15))

# Életcsík (drawHpBar) — csak ha sérült.
static func eletcsik(ci: CanvasItem, y: float, w: float, p: float) -> void:
	_rect(ci, -w / 2, y, w, 4, _c(0, 0, 0, 0.6))
	var c := Color("5c9e4a") if p > 0.5 else (Color("c9a227") if p > 0.25 else Color("c0392b"))
	_rect(ci, -w / 2 + 0.5, y + 0.5, (w - 1.0) * clampf(p, 0.0, 1.0), 3, c)
