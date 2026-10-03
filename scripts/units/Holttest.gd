class_name Holttest
extends Sprite2D

# ELESETT EGYSÉG. A halál négy kockáját (a Blender-lap "death" oszlopai) egyszer
# lejátssza, aztán az utolsó kockán fekve marad egy ideig, végül elhalványul.
# A hajó elsüllyed (az utolsó kocka után eltűnik), a repülő lezuhan.
#
# A holttest díszlet: nem ütközik, nem célpont, a hálózati pillanatképbe sem
# kerül — mindkét gép a saját egységének halálakor maga teszi le.

const KOCKA := 0.11           # egy halálkocka ideje (mp)
const FEKSZIK := 22.0         # meddig marad a földön (mp)
const HALVANYUL := 3.0        # a végén ennyi idő alatt tűnik el

var _frames: Array = []
var _t: float = 0.0
var _hossz: float = FEKSZIK
var _zuhan: float = 0.0       # repülő: ennyi képponttal feljebb kezd

static func letesz(layer: Node, sp: Sprite2D, pos: Vector2, naval: bool, air_h: float) -> void:
	if layer == null or sp == null or not sp.has_method("death_frames"): return
	var fr: Array = sp.death_frames()
	if fr.is_empty(): return
	var h := Sprite2D.new()
	h.set_script(load("res://scripts/units/Holttest.gd"))
	h.texture = sp.texture
	h.material = sp.material
	h.centered = false
	h.region_enabled = true
	h.scale = sp.scale
	h.offset = sp.offset
	h.texture_filter = sp.texture_filter
	h._frames = fr
	h._hossz = 4.0 if naval else FEKSZIK
	h._zuhan = air_h
	h.region_rect = fr[0]
	layer.add_child(h)
	h.global_position = pos

func _ready() -> void:
	z_index = -1
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	var n := _frames.size()
	var k := mini(int(_t / KOCKA), n - 1)
	region_rect = _frames[k]
	if _zuhan > 0.0:
		# a repülő a magasból zuhan le a talajra (a hely a talaj, a kép följebb indul)
		var f := clampf(_t / (KOCKA * float(n)), 0.0, 1.0)
		global_position.y = _base_y() - _zuhan * (1.0 - f * f)
	var vege := KOCKA * float(n) + _hossz
	if _t > vege:
		modulate.a = clampf(1.0 - (_t - vege) / HALVANYUL, 0.0, 1.0)
		if _t > vege + HALVANYUL: queue_free()

var _y0: float = INF

func _base_y() -> float:
	if _y0 == INF: _y0 = global_position.y
	return _y0
