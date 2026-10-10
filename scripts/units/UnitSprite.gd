class_name UnitSprite
extends Sprite2D

# AZ EGYSÉGEK RAJZA — Blenderben modellezett, 3D-ből renderelt lapok.
#
# A lapokat a tools/blender/render_egyseg.py készíti (lásd ott a leírást):
# szerepenként és korszakonként EGY lap (assets/art3d/units/<szerep>_<kor>.png)
# és egy ugyanolyan elrendezésű MASZKLAP (_m.png).
#   sor    = irány, 8 db: 0 = Kelet, 1 = DK, 2 = Dél, ..., 6 = Észak, 7 = ÉK
#            (a játék szögei szerint: y lefelé, az óramutató járásával)
#   oszlop = pihenő | járás | támadás | halál — a kockaszámok a manifestben
# A kockák közös befoglaló téglalapra vannak vágva; a talppont a kockán
# belül (ox, oy) képpontnál van, a lap felbontása "s" képpont / világképpont.
#
# CSAPATSZÍN: a renderen a csapatszínű posztó semleges világosszürke; a
# maszk R csatornája mondja meg, mennyi csapatszín, a G, mennyi kiemelőszín
# kerül a képpontra. Az árnyaló szoroz: rgb = mix(rgb, rgb * szín * k, m).
# Az anyag (ShaderMaterial) lapra és gazdára közös, így az azonos csapat
# azonos egységei egy rajzhívásba kerülhetnek.
#
# Minden irány külön renderelt kép — tükrözni nem szabad, mert a fény
# mindig balról-elölről jön.
#
# TARTALÉK: ha egy szerepnek egyik korszakban sincs lapja (ma a hajók és a
# repülők), a régi rajz (UnitSpriteRegi.gd) dolgozik egy gyerek-sprite-ban,
# az új alakok méretére kicsinyítve. Üres vagy hiányzó kép így sosem lesz.

const MAPPA := "res://assets/art3d/units/"
const REGI := preload("res://scripts/units/UnitSpriteRegi.gd")
# TARTALÉK rokon alak: a felcsernek, az ostromgépnek és a faltörő kosnak ma
# már saját lapja van mind a négy korszakban (medic_N, siege_N, ram_N). Ez a
# tábla csak akkor lép életbe, ha egy szerep saját lapja egyik korszakban
# sem található (pl. hiányos telepítés): a felcser papi ruhában, az
# ostromgép kezelője lövész, a kos vivője közelharcos. A sheet_key() előbb
# a saját szerep MINDEN korszakát végignézi, csak utána a rokonét.
const LAP_ALIAS := {"medic": "priest", "siege": "ranged", "ram": "melee"}
# A régi rajz gyalogosa 46 képpont magas, az új 20–23: a tartalékot ennyire
# kicsinyítjük. A hajó és a repülő kicsit nagyobb arányt kap, hogy a
# gyalogos mellett ne legyen csónaknyi.
const TARTALEK_MERET := {"ember": 0.47, "hajo": 0.52, "repulo": 0.45}
const NAVAL_ROLES := ["fisher", "warship", "galleon", "transport"]
const AIR_ROLES := ["fighter", "bomber"]
const WALK_RATE := 2.0          # járáskocka / "walk" egység (Unit.walk)
const ATK_FRAME := 0.06         # a támadás egy kockája (mp)

const ARNYALO := """
shader_type canvas_item;
uniform sampler2D maszk : filter_linear_mipmap;
uniform vec4 csapat = vec4(1.0);
uniform vec4 kiemelo = vec4(1.0);
uniform vec4 teto = vec4(0.5);
void fragment() {
	vec4 b = texture(TEXTURE, UV);
	vec3 m = texture(maszk, UV).rgb;
	vec3 c = b.rgb;
	c = mix(c, c * csapat.rgb * 1.6, m.r);
	c = mix(c, c * kiemelo.rgb * 1.5, m.g);
	c = mix(c, c * teto.rgb * 2.0, m.b);
	COLOR = vec4(clamp(c, 0.0, 1.0), b.a) * COLOR;
}
"""

static var _manifest: Dictionary = {}
static var _shader: Shader = null
static var _anyagok: Dictionary = {}     # "kulcs|gazda" -> ShaderMaterial
static var _maszkok: Dictionary = {}     # kulcs -> Texture2D

var _role: String = ""
var _age: int = 0
var _owner_id: int = 0
var _nemzet: String = "hu"
var _key: String = ""
var _m: Dictionary = {}
var _cw: float = 0.0
var _ch: float = 0.0
var _dir: int = 2
var _state: String = "idle"
var _frame: int = 0
var _atk_t0: int = -100000
var _was_fired: bool = false
var _base_offset: Vector2 = Vector2.ZERO
var _bob_phase: float = 0.0

# --- lapok ---

static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var f := FileAccess.open(MAPPA + "manifest.json", FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary: _manifest = d
	return _manifest

# A szerephez és korszakhoz tartozó lap kulcsa. A repülő csak a 20. századi
# lapon létezik; ha egy korszak lapja hiányozna, a legközelebbi korszakét
# vesszük.
static func sheet_key(role: String, age: int) -> String:
	var man := manifest()
	var a := clampi(age, 0, 3)
	for r in [role, str(LAP_ALIAS.get(role, ""))]:
		if r == "": continue
		for d in [0, -1, 1, -2, 2, -3, 3]:
			var k := "%s_%d" % [r, a + d]
			if a + d >= 0 and a + d <= 3 and man.has(k) \
					and ResourceLoader.exists(MAPPA + k + ".png"):
				return k
	return ""

static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = ARNYALO
	return _shader

static func maszk_tex(key: String) -> Texture2D:
	if not _maszkok.has(key):
		var p := MAPPA + key + "_m.png"
		_maszkok[key] = load(p) if ResourceLoader.exists(p) else null
	return _maszkok[key]

# Közös anyag lapra és színekre: a kulcs a színekből is áll, így a
# gazdaváltás (átállás) új anyagot kap, a régi csapaté érintetlen marad.
static func anyag(key: String, csapat: Color, kiemelo: Color) -> ShaderMaterial:
	var k := "%s|%s|%s" % [key, csapat.to_html(false), kiemelo.to_html(false)]
	if _anyagok.has(k): return _anyagok[k]
	var mat := ShaderMaterial.new()
	mat.shader = shader()
	mat.set_shader_parameter("maszk", maszk_tex(key))
	mat.set_shader_parameter("csapat", csapat)
	mat.set_shader_parameter("kiemelo", kiemelo)
	_anyagok[k] = mat
	return mat

# A képzési gombok kis képe: a lap D felé néző pihenő kockája, az alak köré
# vágva. (A kocka a fegyverek és a halálpóz miatt jóval nagyobb az alaknál;
# egészében a 26 képpontos gombon csak egy pötty látszana belőle.)
static func ikon(role: String, age: int) -> AtlasTexture:
	var key := sheet_key(role, age)
	if key == "": return null
	var p := MAPPA + key + ".png"
	if not ResourceLoader.exists(p): return null
	var m: Dictionary = manifest()[key]
	var at := AtlasTexture.new()
	at.atlas = load(p)
	var cw := float(m["cw"])
	var ch := float(m["ch"])
	var idle: Array = m["anim"]["idle"]
	var x0 := float(idle[0]) * cw
	var y0 := 2.0 * ch
	# Az alak magassága a lapon: világképpont * felbontás. A talppont (ox, oy).
	var s := float(m.get("s", 2.0))
	var szerep := key.substr(0, key.rfind("_"))
	var fh := float(ALAK_H.get(szerep, m.get("fh", 20.0)))
	if szerep == "melee" and age >= 3: fh = 26.0       # a harckocsi szélesebb, mint magas
	# A gépek szélesebbek az embernél (az ostromgép mellett a kezelő is áll):
	# nagyobb kivágás kell, hogy az egész ráférjen a gombra.
	if IKON_H.has(szerep): fh = float(IKON_H[szerep])
	var h := fh * s * 1.12
	var r := Rect2(float(m["ox"]) - h * 0.5, float(m["oy"]) - h * 0.95, h, h)
	r = r.intersection(Rect2(0.0, 0.0, cw, ch))
	if r.size.x < 4.0 or r.size.y < 4.0: r = Rect2(0.0, 0.0, cw, ch)
	at.region = Rect2(x0 + r.position.x, y0 + r.position.y, r.size.x, r.size.y)
	return at

# --- beállítás ---

func setup(role: String, age: int, owner_id: int) -> void:
	_role = role
	_age = clampi(age, 0, 3)
	_owner_id = owner_id
	_nemzet = str(GameState.get_side(owner_id).get("nemzet", GameState.nation))
	self_modulate = Color.WHITE
	rotation = 0.0
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_bob_phase = randf() * TAU
	_key = sheet_key(role, _age)
	if _key == "":
		_tartalek(role, age, owner_id)
		return
	_m = manifest()[_key]
	texture = load(MAPPA + _key + ".png")
	if texture == null:
		_tartalek(role, age, owner_id)
		return
	if _regi != null:
		_regi.queue_free()
		_regi = null
	_cw = float(_m["cw"])
	_ch = float(_m["ch"])
	var s := 1.0 / float(_m.get("s", 2.0))
	scale = Vector2(s, s)
	_base_offset = -Vector2(float(_m["ox"]), float(_m["oy"]))
	offset = _base_offset
	region_enabled = true
	material = anyag(_key, Style.side_color(owner_id), Style.side_accent(owner_id))
	_state = "idle"
	_frame = 0
	_dir = 2
	_apply()

# A régi rajz egy gyerek-sprite-ban; ez a csomópont maga üres marad, csak
# a kicsinyítést adja (a régi rajz a saját "scale"-jét maga állítja).
var _regi: Sprite2D = null

func _tartalek(role: String, age: int, owner_id: int) -> void:
	_key = ""
	_m = {}
	texture = null
	material = null
	region_enabled = false
	offset = Vector2.ZERO
	var fajta := "ember"
	if role in NAVAL_ROLES: fajta = "hajo"
	elif role in AIR_ROLES: fajta = "repulo"
	var k: float = float(TARTALEK_MERET[fajta])
	scale = Vector2(k, k)
	if _regi == null:
		_regi = Sprite2D.new()
		_regi.set_script(REGI)
		_regi.name = "RegiRajz"
		add_child(_regi)
	_regi.self_modulate = Color.WHITE
	_regi.rotation = 0.0
	_regi.setup(role, age, owner_id)
	# A régi rajz képpontos (NEAREST) szűrővel készült a nagy méretre;
	# kicsinyítve az lépcsőzne, ezért simítva rajzoljuk.
	_regi.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func has_art() -> bool:
	return _key != ""

# Igaz, ha a régi rajz dolgozik (nincs saját lap).
func uses_fallback() -> bool:
	return _key == "" and _regi != null

func fallback_sprite() -> Sprite2D:
	return _regi

func sheet_key_of() -> String:
	return _key

# Az alak magassága világképpontban (az életsáv és a jelzések helyéhez).
func figure_height() -> float:
	if _key == "":
		if _regi != null: return _regi.figure_height() * scale.y
		return 20.0
	if ALAK_H.has(_role) and not (_role == "melee" and _age >= 3):
		return float(ALAK_H[_role])
	return float(_m.get("fh", 20.0))

# Az emberalakok magassága (fejfedővel) — a modellek ekkorára készültek
# (tools/blender/bir_units.py, H). A kép felső széle a fegyvert is
# tartalmazza (pika, lándzsa), ezért nem abból mérünk.
const ALAK_H := {
	"worker": 19.5, "melee": 23.5, "spear": 22.5, "ranged": 21.5, "hero": 25.0,
	"priest": 20.5, "spy": 20.5, "medic": 20.5, "cav": 32.0,
}
# A képzési gomb kivágásának mérete a gépeknél (világképpont).
const IKON_H := {"siege": 30.0, "ram": 30.0}

# --- animáció ---

static func dir_of(face: float) -> int:
	return posmod(int(round(face / (PI * 0.25))), 8)

func _anim(st: String) -> Array:
	var a: Dictionary = _m.get("anim", {})
	return a.get(st, [0, 1])

func update_anim(face: float, walk: float, moving: bool, fired: bool) -> void:
	if _key == "":
		if _regi != null: _regi.update_anim(face, walk, moving, fired)
		return
	var d := dir_of(face)
	var st := "idle"
	var fr := 0
	var most := Time.get_ticks_msec()
	if fired and not _was_fired: _atk_t0 = most
	_was_fired = fired
	if fired or most - _atk_t0 < int(ATK_FRAME * 4000.0):
		st = "attack"
		var n: int = int(_anim("attack")[1])
		fr = clampi(int(float(most - _atk_t0) / (ATK_FRAME * 1000.0)), 0, n - 1)
	elif moving:
		st = "walk"
		var n2: int = int(_anim("walk")[1])
		fr = int(walk * WALK_RATE) % maxi(n2, 1)
	if d != _dir or st != _state or fr != _frame:
		_dir = d
		_state = st
		_frame = fr
		_apply()
	# A hajó a hullámokon ring, a repülő a levegőben imbolyog (csak eltolás:
	# a renderelt kép nem forgatható).
	if _role in NAVAL_ROLES or _role in AIR_ROLES:
		var t := float(most) * 0.001
		var amp := 0.9 if _role in NAVAL_ROLES else 1.4
		offset = _base_offset + Vector2(0.0, sin(t * 1.6 + _bob_phase) * amp * float(_m.get("s", 2.0)))

func _apply() -> void:
	var a := _anim(_state)
	var col := int(a[0]) + mini(_frame, int(a[1]) - 1)
	region_rect = Rect2(float(col) * _cw, float(_dir) * _ch, _cw, _ch)

# A halál kockái (a holttest ebből játssza le az elesést, és az utolsón marad).
func death_frames() -> Array:
	if _key == "": return []
	var a := _anim("death")
	var out: Array = []
	for i in range(int(a[1])):
		out.append(Rect2(float(int(a[0]) + i) * _cw, float(_dir) * _ch, _cw, _ch))
	return out
