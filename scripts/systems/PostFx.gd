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
#
# A KONTAKTÁRNYÉK az egységek alatt már a figurák rajzában benne van
# (Unit._draw), a TORKOLATTŰZ fényes magja pedig a sortűznél (Broadside).
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

var main: Node = null

var _rect: ColorRect = null
var _mat: ShaderMaterial = null
var _t: float = 0.0

func _ready() -> void:
	name = "PostFx"
	layer = 4                      # a világ fölött, a köd és a HUD alatt
	if main == null: main = get_tree().get_first_node_in_group("main")
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

func _process(delta: float) -> void:
	# Takarékos módban nincs utómunka. FOTÓMÓDBAN marad: épp attól szép a kép.
	var kell: bool = Settings.detail >= 1
	_rect.visible = kell
	if not kell: return
	_t -= delta
	if _t > 0.0: return
	_t = 0.25
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
