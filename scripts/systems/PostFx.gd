extends CanvasLayer

# UTÓMUNKA ÉS FÉNY  (index.html 16/D)
#
# Néhány olcsó réteg, ami a rajzolt képet modernné teszi. Mindegyik
# egyetlen teljes képernyős művelet:
#
#   SZÍNHANGOLÁS  — a napszak festi át a képet: hajnalban hideg kék,
#                   délelőtt arany, délben semleges, alkonyatkor borostyán
#   PEREMSÖTÉTÍTÉS— a kép széle felé halkan sötétedik, így a közép kiemelkedik
#   FÉNYIRÁNY     — a nap állása szerint dől az árnyék (lásd sun_shadow)
#   RAGYOGÁS      — a tűz, a torkolattűz és a lámpák TÚLCSORDULNAK: a
#                   legvilágosabb foltok fénye szétsugárzik a környezetükre
#
# A KONTAKTÁRNYÉK az egységek alatt már a figurák rajzában benne van
# (Unit._draw), a TORKOLATTŰZ fényes magja pedig a sortűznél (Broadside).
#
# A RAGYOGÁS a motor saját utómunkája (Environment.glow), nem kézzel rajzolt
# fénykorong: a kész képből szedi ki a küszöb fölötti világos pontokat, és
# azokat kenné szét. Ehhez kell a 2D nagy dinamikájú (HDR) puffer is,
# különben a fehérnél nem lehet fényesebb folt, és nem volna mit kiemelni.
# Teljes képernyős művelet, ezért kapcsolható (Beállítások > Ragyogás), és
# takarékos fokozaton magától kimarad.
#
# A réteg a világ FÖLÖTT, de a felület ALATT ül, hogy a HUD tiszta maradjon.
# Takarékos módban (Settings.detail == 0) kimarad.

const SHADER := """
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float vignette : hint_range(0.0, 1.0) = 0.22;

void fragment() {
	// A napszak színe: halvány fátyol az egész kép fölött.
	vec4 c = vec4(tint.rgb, tint.a);
	// Peremsötétítés: a sarkok felé erősödik.
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 1.42;
	float v = smoothstep(0.55, 1.0, r) * vignette;
	// A kettőt egy rétegben keverjük ki: a szélen a sötét nyer.
	vec3 szin = mix(c.rgb, vec3(0.0), v / max(c.a + v, 0.001));
	COLOR = vec4(szin, min(c.a + v, 1.0));
}
"""

# A napszakhoz tartozó fátyol: [ciklushatár, szín, erősség]
const HANGOLAS := [
	[0.10, Color(0.47, 0.59, 0.82), 0.16],   # hajnali kék
	[0.30, Color(1.00, 0.82, 0.51), 0.13],   # délelőtti arany
	[0.46, Color(1.00, 0.99, 0.96), 0.05],   # déli fehér
	[0.62, Color(0.97, 0.66, 0.34), 0.22],   # alkonyi borostyán
]

# --- A ragyogás beállításai ---
#
# A küszöb magas: CSAK a tényleg világító dolgok ragyognak (torkolattűz,
# lámpafény, robbanás), a fehér falak és a hó nem. A sugár kicsi, mert ez
# nem álomszerű elmosás, hanem az, amikor a láng túlcsordul a szemben.
const GLOW_KUSZOB := 1.0          # e fölött kezd ragyogni (HDR-ben >1 is lehet)
const GLOW_ERO := 1.45            # mennyire erős a szétsugárzás
const GLOW_HATOTAV := 1.2         # a holdudvar mérete
const GLOW_KEVERES := 0.08        # ennyi szűrődik az egész képre

var main: Node = null

var _rect: ColorRect = null
var _mat: ShaderMaterial = null
var _world: WorldEnvironment = null
var _env: Environment = null
var _glow_be: bool = false
var _t: float = 0.0

func _ready() -> void:
	name = "PostFx"
	layer = 4                      # a világ fölött, a köd és a HUD alatt
	if main == null: main = get_tree().get_first_node_in_group("main")
	_setup_glow()
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	_rect.color = Color.WHITE
	add_child(_rect)
	set_process(true)

# --- RAGYOGÁS ---
#
# A motor utómunkája végzi: az Environment a küszöb fölötti fényes pontokat
# szedi ki a kész képből. A 2D nagy dinamikájú pufferét is bekapcsoljuk,
# különben a fehér a plafon, és a láng nem tudna "túlcsordulni".
func _setup_glow() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_CANVAS
	_env.glow_enabled = true
	_env.glow_intensity = GLOW_ERO
	_env.glow_strength = GLOW_HATOTAV
	_env.glow_bloom = GLOW_KEVERES
	_env.glow_hdr_threshold = GLOW_KUSZOB
	_env.glow_hdr_scale = 2.0
	_env.glow_hdr_luminance_cap = 12.0
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# A kisebb szintek adják a szoros, magas fényt; a nagyobbak az elmosódó
	# holdudvart. Kell mindkettő: a láng magja éles, a fénye szétterül.
	_env.set_glow_level(0, 0.8)
	_env.set_glow_level(1, 1.0)
	_env.set_glow_level(2, 0.85)
	_env.set_glow_level(3, 0.45)
	_env.set_glow_level(4, 0.15)
	_env.set_glow_level(5, 0.0)
	_env.set_glow_level(6, 0.0)
	_world = WorldEnvironment.new()
	_world.name = "Ragyogas"
	_world.environment = _env
	add_child(_world)
	_glow_frissit()

func glow_aktiv() -> bool:
	return _glow_be

func _glow_frissit() -> void:
	var kell: bool = Settings.bloom and Settings.detail >= 1
	if kell == _glow_be: return
	_glow_be = kell
	_env.glow_enabled = kell
	# A 2D HDR puffer csak a ragyogáshoz kell; enélkül minden pont a fehérnél
	# megáll. Ha nincs ragyogás, ki is kapcsoljuk — memória és sávszélesség.
	var vp := get_viewport()
	if vp != null: vp.use_hdr_2d = kell

func _process(delta: float) -> void:
	# Takarékos módban nincs utómunka. FOTÓMÓDBAN marad: épp attól szép a kép.
	var kell: bool = Settings.detail >= 1
	_rect.visible = kell
	_t -= delta
	if _t > 0.0: return
	_t = 0.25
	_glow_frissit()
	if not kell: return
	_mat.set_shader_parameter("tint", _tint())
	_mat.set_shader_parameter("vignette", 0.22)

# A napszak fátyla. Éjjel nincs: ott a sötét réteg (DayNight) dolgozik.
func _tint() -> Color:
	var dn: Node = main.day_night if main != null else null
	if dn == null or not is_instance_valid(dn):
		return Color(1, 1, 1, 0)
	var t: float = dn.time_of_day()
	var elozo := 0.0
	for h in HANGOLAS:
		var hatar := float(h[0])
		if t < hatar:
			var szin: Color = h[1]
			var ero := float(h[2])
			# A szakaszon belül elhalványul (a következő felé tartva).
			var arany := (t - elozo) / maxf(hatar - elozo, 0.001)
			if hatar >= 0.62:
				ero = 0.06 + (ero - 0.06) * arany      # alkonyatkor erősödik
			else:
				ero = ero * (1.0 - arany * 0.6)
			return Color(szin.r, szin.g, szin.b, ero)
		elozo = hatar
	return Color(1, 1, 1, 0)
