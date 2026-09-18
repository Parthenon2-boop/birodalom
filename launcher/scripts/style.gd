extends RefCounted

# JÁTÉKINDÍTÓ – KÉT BŐR (skin)
#
# Az indító annak a játéknak a stílusát veszi föl, amelyik ki van választva:
#   "birodalom"  – a Birodalom felülete: sötétbarna panelek, arany keret,
#                  krémszínű szöveg (ugyanaz a paletta, mint a játékban:
#                  scripts/ui/Style.gd — panel #1a1410, arany #c9a227).
#   "heptarchia" – a Heptarchia saját indítója: bőr és pergamen, aranyszegély,
#                  Uncial címbetű, rúnasor, EB Garamond szöveg.
#
# A színek STATIKUS VÁLTOZÓK, nem konstansok: a `set_skin()` írja át őket,
# és utána a felület újraépül, hogy minden felirat az új palettát kapja.

static var skin: String = "birodalom"

# --- Szerepek szerinti színek (mindkét bőr ugyanezeket tölti ki) ---
static var BG         := Color("0c0a08")     # a legkülső háttér
static var PANEL      := Color("1a1410")     # a lap / panel háttere
static var PANEL_LT   := Color("241c15")     # gombok, kiemelt sávok
static var PANEL_HOVER:= Color("33281a")
static var NOTES_BG   := Color("140f0b")     # a leírás doboza
static var BORDER     := Color("4a3c2c")     # keretvonal
static var GOLD       := Color("c9a227")
static var GOLD_LIGHT := Color("f0d98a")
static var RED        := Color("c0392b")
static var GREEN      := Color("5c9e4a")
static var TEXT       := Color("e8dcc0")     # fő szöveg
static var TEXT_DIM   := Color("9c8d72")     # halványabb szöveg

const FONT_DIR := "res://assets/fonts/"

static func set_skin(key: String) -> void:
	skin = key
	if key == "heptarchia":
		BG          = Color(0.21, 0.135, 0.08)        # bőr
		PANEL       = Color(0.89, 0.81, 0.63)         # pergamen
		PANEL_LT    = Color(0.37, 0.25, 0.14)
		PANEL_HOVER = Color(0.48, 0.33, 0.17)
		NOTES_BG    = Color(0.85, 0.77, 0.58)
		BORDER      = Color(0.52, 0.38, 0.17)
		GOLD        = Color(0.80, 0.61, 0.29)
		GOLD_LIGHT  = Color(0.97, 0.85, 0.53)
		RED         = Color(0.60, 0.15, 0.09)
		GREEN       = Color(0.30, 0.45, 0.20)
		TEXT        = Color(0.22, 0.13, 0.06)         # tinta a pergamenen
		TEXT_DIM    = Color(0.36, 0.25, 0.14)
	else:
		BG          = Color("0c0a08")
		PANEL       = Color("1a1410")
		PANEL_LT    = Color("241c15")
		PANEL_HOVER = Color("33281a")
		NOTES_BG    = Color("140f0b")
		BORDER      = Color("4a3c2c")
		GOLD        = Color("c9a227")
		GOLD_LIGHT  = Color("f0d98a")
		RED         = Color("c0392b")
		GREEN       = Color("5c9e4a")
		TEXT        = Color("e8dcc0")
		TEXT_DIM    = Color("9c8d72")

# --- Betűk ---
# A Heptarchia a saját betűivel ír; a Birodalom a beépített betűt használja,
# ahogy maga a játék is.

static func _font(file: String) -> FontFile:
	var path := FONT_DIR + file
	return load(path) if ResourceLoader.exists(path) else null

static func font_text() -> FontFile:
	return _font("EBGaramond.ttf") if skin == "heptarchia" else null

static func font_italic() -> FontFile:
	return _font("EBGaramond-Italic.ttf") if skin == "heptarchia" else null

static func font_title() -> FontFile:
	return _font("UncialAntiqua-Regular.ttf") if skin == "heptarchia" else null

static func font_runes() -> FontFile:
	return _font("NotoSansRunic-Regular.ttf")

static func _box(bg: Color, border: Color, width: int = 2, radius: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14; s.content_margin_right = 14
	s.content_margin_top = 8;   s.content_margin_bottom = 8
	return s

static func build_theme() -> Theme:
	var t := Theme.new()
	var text_font := font_text()
	if text_font != null: t.default_font = text_font
	t.default_font_size = 17

	# Gombok
	t.set_stylebox("normal", "Button", _box(PANEL_LT, BORDER))
	t.set_stylebox("hover", "Button", _box(PANEL_HOVER, GOLD_LIGHT))
	t.set_stylebox("pressed", "Button", _box(BG, GOLD))
	t.set_stylebox("disabled", "Button", _box(PANEL_LT.lerp(Color(0.5, 0.5, 0.5), 0.25),
		BORDER.lerp(Color(0.5, 0.5, 0.5), 0.3)))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	var btn_text := TEXT if skin == "birodalom" else Color(0.94, 0.88, 0.73)
	t.set_color("font_color", "Button", btn_text)
	t.set_color("font_hover_color", "Button", GOLD_LIGHT)
	t.set_color("font_pressed_color", "Button", GOLD_LIGHT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_font_size("font_size", "Button", 18)

	t.set_stylebox("panel", "Panel", _box(PANEL, BORDER, 2, 4))
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, BORDER, 2, 4))

	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("normal", "RichTextLabel", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))

	var edit_bg := Color("120d09") if skin == "birodalom" else Color(0.96, 0.92, 0.82)
	t.set_stylebox("normal", "LineEdit", _box(edit_bg, BORDER, 1, 3))
	t.set_stylebox("focus", "LineEdit", _box(edit_bg.lightened(0.06), GOLD, 2, 3))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", GOLD)

	var pb_bg := _box(BG, BORDER, 1, 3)
	pb_bg.content_margin_left = 0; pb_bg.content_margin_right = 0
	var pb_fg := _box(GOLD.darkened(0.25), GOLD_LIGHT, 1, 3)
	pb_fg.content_margin_left = 0; pb_fg.content_margin_right = 0
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fg)
	t.set_color("font_color", "ProgressBar", TEXT)

	t.set_color("font_color", "CheckBox", TEXT)
	t.set_stylebox("panel", "PopupPanel", _box(PANEL_LT if skin == "heptarchia" else PANEL,
		GOLD, 3, 6))
	return t

# Címfelirat a bőr saját címbetűjével.
static func make_title(text_value: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text_value
	var f := font_title()
	if f != null: l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
