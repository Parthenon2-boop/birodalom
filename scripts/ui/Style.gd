class_name Style
extends RefCounted

# Az eredeti (index.html) "hadi térkép" esztétikája. A CSS :root változói
# és az AGES[].ui korszakpalettái innen kerülnek át.
#
#   --panel  #1a1410   --panel2 #241c15   --ink  #e8dcc0
#   --dim    #9c8d72   --gold   #c9a227   --line #4a3c2c

const PANEL  := Color("1a1410")
const PANEL2 := Color("241c15")
const INK    := Color("e8dcc0")
const DIM    := Color("9c8d72")
const GOLD   := Color("c9a227")
const LINE   := Color("4a3c2c")
const BAD    := Color("c0392b")
const OK     := Color("5c9e4a")
const BG     := Color("0c0a08")
const HOVER  := Color("33281a")

# Korszakonkénti felület-színek (AGES[].ui)
const AGE_UI := [
	{"gold": "c9a227", "panel": "1a1410", "panel2": "241c15", "line": "4a3c2c", "ink": "e8dcc0"},
	{"gold": "c98b3a", "panel": "191512", "panel2": "241d17", "line": "4c3b2b", "ink": "e9dcc6"},
	{"gold": "b07a52", "panel": "161513", "panel2": "211f1c", "line": "443f38", "ink": "e6e1d6"},
	{"gold": "8d9a6b", "panel": "131513", "panel2": "1c1f1b", "line": "3b4038", "ink": "dfe3d6"},
]

# Korszakonkénti tájszínek (AGES[].style)
const AGE_STYLE := [
	{"evszak": "tavasz", "ground": "5a8c3c", "ground2": "679a45", "path": "8a7550",
	 "wall": "9a9186", "wallDark": "6d6459", "roof": "6d3f26", "wood": "7a5230", "metal": "b9bcc0"},
	{"evszak": "nyár",   "ground": "3f6b30", "ground2": "4a7a38", "path": "7d6a45",
	 "wall": "a89e8c", "wallDark": "786e5d", "roof": "7b4b2f", "wood": "835a34", "metal": "c2c6ca"},
	{"evszak": "ősz",    "ground": "7a6a34", "ground2": "8a7a3c", "path": "6f6152",
	 "wall": "a4523f", "wallDark": "733a2c", "roof": "57575f", "wood": "6f5238", "metal": "9aa1a8"},
	{"evszak": "tél",    "ground": "77807e", "ground2": "848d8a", "path": "6e6a5c",
	 "wall": "8e8e86", "wallDark": "63635c", "roof": "4a4f45", "wood": "5f5645", "metal": "8a9198"},
]

const ERA_NAME := ["15. század", "17. század", "19. század", "20. század"]
const ERA_SUB  := ["Késő középkor", "Kora újkor", "Ipari forradalom", "Világháborús kor"]
const ERA_COST := [
	{"food": 760, "gold": 520},
	{"food": 1250, "gold": 980},
	{"food": 1900, "gold": 1550},
	{},
]

# Játszható nemzetek — azok, amelyekhez zászló- és uralkodókép is van.
const NATIONS := {
	"hu": {"name": "Magyarország", "color": "C8102E", "accent": "1E7A3C",
		"rulers": ["Hunyadi Mátyás", "II. Rákóczi Ferenc", "Kossuth Lajos", "Horthy Miklós"],
		"eras": ["Magyar Királyság", "Magyar Királyság", "Magyarország", "Magyarország"],
		"titles": ["király", "fejedelem", "kormányzó", "kormányzó"]},
	"es": {"name": "Spanyolország", "color": "AA151B", "accent": "F1BF00",
		"rulers": ["Aragóniai Ferdinánd", "II. Fülöp", "III. Károly", "Francisco Franco"],
		"eras": ["Kasztília és Aragónia", "Spanyol Birodalom", "Spanyol Királyság", "Spanyolország"],
		"titles": ["király", "király", "király", "államfő"]},
	"at": {"name": "Ausztria", "color": "E2E2E2", "accent": "B8121B",
		"rulers": ["III. Frigyes", "I. Lipót", "I. Ferenc József", "I. Károly"],
		"eras": ["Osztrák Hercegség", "Habsburg Birodalom", "Osztrák–Magyar Monarchia", "Ausztria"],
		"titles": ["császár", "császár", "császár", "császár"]},
	"pl": {"name": "Lengyelország", "color": "E03A4E", "accent": "F2F2F2",
		"rulers": ["IV. Kázmér", "III. (Sobieski) János", "Kościuszko Tádé", "Piłsudski József"],
		"eras": ["Lengyel Királyság", "Lengyel–Litván Unió", "Lengyelország", "Lengyel Köztársaság"],
		"titles": ["király", "király", "hadvezér", "marsall"]},
	"de": {"name": "Németország", "color": "2C2C2C", "accent": "E0B400",
		"rulers": ["I. Miksa", "Frigyes Vilmos", "Bismarck Ottó", "Paul von Hindenburg"],
		"eras": ["Német-római Birodalom", "Brandenburg-Poroszország", "Német Birodalom", "Németország"],
		"titles": ["császár", "választófejedelem", "kancellár", "elnök"]},
	"fr": {"name": "Franciaország", "color": "2B4C9B", "accent": "EFEFEF",
		"rulers": ["XI. Lajos", "XIV. Lajos", "Napóleon Bonaparte", "Charles de Gaulle"],
		"eras": ["Francia Királyság", "Francia Királyság", "Francia Császárság", "Francia Köztársaság"],
		"titles": ["király", "király", "császár", "tábornok"]},
	"gb": {"name": "Nagy-Britannia", "color": "B01B2E", "accent": "0A2B5C",
		"rulers": ["VII. Henrik", "Oliver Cromwell", "Viktória királynő", "Winston Churchill"],
		"eras": ["Anglia", "Anglia", "Nagy-Britannia", "Nagy-Britannia"],
		"titles": ["király", "lordprotektor", "királynő", "miniszterelnök"]},
	"ru": {"name": "Oroszország", "color": "2F5FA8", "accent": "D62828",
		"rulers": ["III. Iván", "I. (Nagy) Péter", "I. Sándor", "II. Miklós"],
		"eras": ["Moszkvai Nagyfejedelemség", "Orosz Cárság", "Orosz Birodalom", "Orosz Birodalom"],
		"titles": ["nagyfejedelem", "cár", "cár", "cár"]},
}

const NATION_ORDER := ["hu", "es", "at", "pl", "de", "fr", "gb", "ru"]

# --- Kalózvilág ---
#
# Rejtett frakciók: a rendes nemzetválasztóban nem jelennek meg, csak a
# kalóz játékmódban. Nem lépnek korszakot — végig a vitorlások korában
# játszanak, ezért mind a négy korszakhoz ugyanaz a név és uralkodó.
const PIRATES := {
	"ns": {"name": "Nassau", "color": "2B2B2B", "accent": "E8E4D8",
		"rulers": ["Benjamin Hornigold", "Charles Vane", "Jack Rackham", "Anne Bonny"],
		"eras": ["A kalózköztársaság", "A kalózköztársaság",
			"A kalózköztársaság", "A kalózköztársaság"],
		"titles": ["kapitány", "kapitány", "kapitány", "kapitány"]},
	"bb": {"name": "Fekete Szakáll", "color": "1A1A1A", "accent": "B01B1B",
		"rulers": ["Edward Teach", "Edward Teach", "Edward Teach", "Edward Teach"],
		"eras": ["A Queen Anne bosszúja", "A Queen Anne bosszúja",
			"A Queen Anne bosszúja", "A Queen Anne bosszúja"],
		"titles": ["rettegett kapitány", "rettegett kapitány",
			"rettegett kapitány", "rettegett kapitány"]},
	"sb": {"name": "Stede Bonnet", "color": "2F3D5C", "accent": "C8102E",
		"rulers": ["Stede Bonnet", "Stede Bonnet", "Stede Bonnet", "Stede Bonnet"],
		"eras": ["Az úri kalóz", "Az úri kalóz", "Az úri kalóz", "Az úri kalóz"],
		"titles": ["őrnagy", "őrnagy", "őrnagy", "őrnagy"]},
}

const PIRATE_ORDER := ["ns", "bb", "sb"]

static func is_pirate(key: String) -> bool:
	return PIRATES.has(key)

static func order_for(pirate_mode: bool) -> Array:
	return PIRATE_ORDER if pirate_mode else NATION_ORDER

# Az ellenséges koalíció (ENEMY az eredetiben)
const ENEMY_COLOR  := Color("6B4A9E")
const ENEMY_ACCENT := Color("D9C27A")

static func nation(key: String) -> Dictionary:
	if PIRATES.has(key): return PIRATES[key]
	return NATIONS.get(key, NATIONS["hu"])

# A nemzet neve a választott nyelven (assets/lang/*.json).
static func nation_name(key: String) -> String:
	var k := "n_" + key
	var s := Lang.t(k)
	return str(nation(key).get("name", key)) if s == k else s

# A rang (király, császár, kapitány…) a választott nyelven. Az adattábla
# magyarul tárolja, ezért a magyar szóból képezünk kulcsot.
static func title_name(hu_title: String) -> String:
	var k := "t_" + hu_title.to_lower().replace(" ", "_") \
		.replace("á", "a").replace("é", "e").replace("í", "i") \
		.replace("ó", "o").replace("ö", "o").replace("ő", "o") \
		.replace("ú", "u").replace("ü", "u").replace("ű", "u")
	var s := Lang.t(k)
	return hu_title if s == k else s

# Több fél is lehet egy pályán, ezért nem elég a „mi / ők” két szín: minden
# oldal saját jelzőszínt kap. A 0. a helyi játékos — az az ő nemzetéé.
const SIDE_COLORS := [
	Color("6B4A9E"), Color("C0392B"), Color("2E8B57"),
	Color("D08A1E"), Color("2A6FB5"), Color("8E5A3C"),
]
const SIDE_ACCENTS := [
	Color("D9C27A"), Color("F0B7B0"), Color("A8E6BE"),
	Color("F5DFA6"), Color("A9D0F5"), Color("E2BFA5"),
]

static func side_color(owner_id: int) -> Color:
	if owner_id == GameState.en_id:
		return nation_color(GameState.nation)
	var i := owner_id - 1 if owner_id > GameState.en_id else owner_id
	return SIDE_COLORS[posmod(i, SIDE_COLORS.size())]

static func side_accent(owner_id: int) -> Color:
	if owner_id == GameState.en_id:
		return nation_accent(GameState.nation)
	var i := owner_id - 1 if owner_id > GameState.en_id else owner_id
	return SIDE_ACCENTS[posmod(i, SIDE_ACCENTS.size())]

static func nation_color(key: String) -> Color:
	return Color(str(nation(key)["color"]))

static func nation_accent(key: String) -> Color:
	return Color(str(nation(key)["accent"]))

static func age_gold(age: int) -> Color:
	return Color(str(AGE_UI[clampi(age, 0, 3)]["gold"]))

static func ground(age: int) -> Color:
	return Color(str(AGE_STYLE[clampi(age, 0, 3)]["ground"]))

static func ground2(age: int) -> Color:
	return Color(str(AGE_STYLE[clampi(age, 0, 3)]["ground2"]))

static func flag_path(key: String, age: int) -> String:
	return "res://assets/flags/%s-%d.png" % [key, clampi(age, 0, 3)]

# A zászlóképek nem csupasz lobogók: pergamenlapon ülnek, világos
# szegéllyel — a felületen ebből fehér keret lett a zászló körül. Itt
# megkeressük magát a lobogót (a színes, illetve sötét képpontok határát),
# és AtlasTexture-rel csak azt a részt vágjuk ki.
static var _flag_cache: Dictionary = {}

static func flag_texture(key: String, age: int) -> Texture2D:
	var path := flag_path(key, age)
	if _flag_cache.has(path): return _flag_cache[path]
	if not ResourceLoader.exists(path):
		_flag_cache[path] = null
		return null
	var tex: Texture2D = load(path)
	var img := tex.get_image()
	var rect := _content_rect(img)
	var out: Texture2D = tex
	if rect.size.x > 4.0 and rect.size.y > 4.0:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = rect
		out = at
	_flag_cache[path] = out
	return out

# A "tartalom" a telített VAGY sötét képpontok befoglaló téglalapja: a
# pergamen és a szürke keret halvány és világos, a lobogó színei nem.
# Kettesével mintavételezünk, hogy a menü ne akadjon meg tőle.
static func _content_rect(img: Image) -> Rect2:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var c := img.get_pixel(x, y)
			if c.a >= 0.5 and (c.s >= 0.28 or c.v <= 0.34):
				if x < x0: x0 = x
				if x > x1: x1 = x
				if y < y0: y0 = y
				if y > y1: y1 = y
			x += 2
		y += 2
	if x1 < 0: return Rect2(0, 0, w, h)
	# Nem tágítunk: a kettesével mintavételezés legfeljebb egy képpontot
	# hagy le a szélén, és épp ennyi a lobogó pergamenbe futó, kivilágosodó
	# pereme is — a kettő kioltja egymást, keret pedig nem marad.
	return Rect2(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

static func ruler_path(key: String, age: int) -> String:
	return "res://assets/rulers/%s-%d.jpg" % [key, clampi(age, 0, 3)]

# --- Panelek ---

# A .panel osztály: függőleges átmenet panel2 -> panel, 1px keret, lekerekítés 2.
static func panel_box(age: int = 0, accent_top: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var ui: Dictionary = AGE_UI[clampi(age, 0, 3)]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(str(ui["panel"]))
	sb.border_color = Color(str(ui["line"]))
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	if accent_top.a > 0.0:
		# border-top: 2px solid var(--nat)
		sb.border_width_top = 3
		sb.border_color = accent_top
	return sb

static func button_box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

# Aranyszínű, tömör gomb (#ageBtn, #startBtn): linear-gradient(gold, #8a6f18)
static func gold_button_box(age: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = age_gold(age)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.border_color = age_gold(age).darkened(0.35)
	sb.border_width_bottom = 2
	return sb

# RITKÍTOTT BETŰ — a HTML `letter-spacing` megfelelője.
#
# Az eredeti menü címe 10, a feliratai 2 képpontnyi rést hagynak a betűk
# között; Godotban ezt a FontVariation.spacing_glyph adja. A kész
# betűváltozatokat eltesszük, hogy ne készüljön minden felirathoz új.
static var _spaced: Dictionary = {}

static func spaced_font(spacing: float) -> FontVariation:
	var key := int(round(spacing))
	if _spaced.has(key): return _spaced[key]
	var fv := FontVariation.new()
	var base := ThemeDB.fallback_font
	if base != null: fv.base_font = base
	fv.spacing_glyph = key
	_spaced[key] = fv
	return fv

# A teljes felület témája. A Control-ok ezt öröklik.
static func make_theme(age: int = 0) -> Theme:
	var ui: Dictionary = AGE_UI[clampi(age, 0, 3)]
	var ink := Color(str(ui["ink"]))
	var line := Color(str(ui["line"]))
	var panel2 := Color(str(ui["panel2"]))
	var gold := Color(str(ui["gold"]))

	var th := Theme.new()
	th.default_font_size = 13

	th.set_stylebox("panel", "PanelContainer", panel_box(age))
	th.set_stylebox("panel", "Panel", panel_box(age))

	th.set_color("font_color", "Label", ink)

	# .mbtn / .btn — panel2 háttér, vonalkeret, aranyra váltó hover
	th.set_stylebox("normal", "Button", button_box(panel2, line))
	th.set_stylebox("hover", "Button", button_box(HOVER, gold))
	th.set_stylebox("pressed", "Button", button_box(gold.darkened(0.55), gold))
	th.set_stylebox("focus", "Button", button_box(Color(0, 0, 0, 0), gold))
	th.set_stylebox("disabled", "Button", button_box(Color("3a3128"), line))
	th.set_color("font_color", "Button", ink)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color("7b6d59"))
	th.set_constant("h_separation", "Button", 6)

	var fill := StyleBoxFlat.new()
	fill.bg_color = OK
	fill.set_corner_radius_all(1)
	var bgbar := StyleBoxFlat.new()
	bgbar.bg_color = Color(0, 0, 0, 0.55)
	bgbar.set_corner_radius_all(1)
	th.set_stylebox("fill", "ProgressBar", fill)
	th.set_stylebox("background", "ProgressBar", bgbar)
	th.set_color("font_color", "ProgressBar", ink)

	var sep := StyleBoxLine.new()
	sep.color = line
	th.set_stylebox("separator", "HSeparator", sep)
	return th
