extends Node2D

# AZ ELESETT KATONA (index.html dropCorpse / drawCorpse).
#
# Az eredetiben az elesett a földre dől — a saját álló képe, oldalra
# fordítva, arra, amerre nézett —, alatta vértócsa terül szét, és a
# harmincnégy másodperc utolsó hatában elhalványul. Legfeljebb kilencven
# marad a pályán. Puszta látvány: a játékmenetet nem érinti.

const EgysegRajz := preload("res://scripts/units/UnitSprite.gd")
const ELET := 34.0
const MAX_DB := 90
const CSOPORT := "holttestek"

var _t: float = 0.0
var _dol: float = 0.0
var _r: float = 10.0
var _irany: float = 1.0
var _alak: Sprite2D = null

# Az egység helyén hagy egy holttestet (a szülője a világ, ahol az egység állt).
static func ejt(u: Node2D, role: String, age: int, owner_id: int, face: float,
		r: float) -> void:
	var szulo := u.get_parent()
	if szulo == null: return
	var fak := u.get_tree().get_nodes_in_group(CSOPORT)
	# A legrégebbi megy el először, ha már túl sok van.
	var i := 0
	while fak.size() - i >= MAX_DB:
		(fak[i] as Node).queue_free()
		i += 1
	var h: Node2D = (load("res://scripts/units/Holttest.gd") as GDScript).new()
	h.add_to_group(CSOPORT)
	h.z_index = 3
	h.global_position = u.global_position
	szulo.add_child(h)
	h.call("_indul", role, age, owner_id, face, r)

func _indul(role: String, age: int, owner_id: int, face: float, r: float) -> void:
	_r = r
	var jobbra := cos(face) >= 0.0
	_irany = 1.0 if jobbra else -1.0
	_alak = Sprite2D.new()
	_alak.set_script(EgysegRajz)
	add_child(_alak)
	_alak.setup(role, age, owner_id)
	# Oldalnézet, álló kocka — abba az irányba, amerre nézett.
	_alak.update_anim(0.0 if jobbra else PI, 0.0, false, false)
	_alak.self_modulate = Color(1, 1, 1, 0.92)
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	if _dol < 1.0:
		_dol = minf(1.0, _dol + delta * 3.4)       # eldőlés fél másodperc alatt
		if _alak != null: _alak.rotation = _irany * 1.42 * _dol
		queue_redraw()
	modulate.a = clampf((ELET - _t) / 6.0, 0.0, 1.0)
	if _t > ELET: queue_free()

func _draw() -> void:
	# vértócsa: a dőléssel együtt terül szét
	var r := (_r * 0.9 + 4.0) * _dol
	if r <= 0.1: return
	_ell(Vector2(0, 2), Vector2(r * 1.25, r * 0.55), Color8(112, 22, 20, 140))
	_ell(Vector2(-r * 0.3, 3), Vector2(r * 0.55, r * 0.26), Color8(74, 12, 12, 115))

func _ell(c: Vector2, rr: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(18):
		var a := TAU * float(i) / 18.0
		pts.append(c + Vector2(cos(a) * rr.x, sin(a) * rr.y))
	draw_colored_polygon(pts, col)
