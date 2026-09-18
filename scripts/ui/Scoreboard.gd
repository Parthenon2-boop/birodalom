extends PanelContainer

# PONTTÁBLA ÉS KIESÉS  (index.html 23/B)
#
# Kettőnél több félnél nem elég a „te és az ellenség” kép: tudni kell, ki
# él még, ki a szövetséges, és ki esett ki. A tábla a képernyő jobb felső
# sarkában áll, és összecsukható — csata közben ne foglaljon helyet.
#
# A KIESÉST nem itt döntjük el: a GameState.side_alive() a mérce (nincs se
# fővárosa, se kaszárnyája, se munkása), ugyanaz, amit a vereség is használ.
# Itt csak kihirdetjük és kijelezzük.
#
# A soronkénti apró gomb a DIPLOMÁCIA: a többieket úgyis itt látod, tehát
# itt a helye a döntésnek is — szövetséget ajánl, vagy felmond.

const SOR_MAGAS := 22.0
const ELLENORZES := 0.5          # ennyinként nézzük meg, ki esett ki

var main: Node = null
var zart: bool = false

var _sorok: VBoxContainer = null
var _fejlec: Button = null
var _sig: String = ""
var _t: float = 0.0

func _ready() -> void:
	name = "Scoreboard"
	if main == null: main = get_tree().get_first_node_in_group("main")
	# A jobb felső sarokba, a felső sáv alá. (Az eltolás a JOBB szélhez
	# képest negatív — a `position` itt a szülő bal felső sarkához mérne.)
	set_anchors_preset(Control.PRESET_TOP_RIGHT, true)
	offset_left = -236.0
	offset_right = -12.0
	offset_top = 54.0
	offset_bottom = 54.0
	custom_minimum_size = Vector2(224, 0)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var doboz := VBoxContainer.new()
	doboz.add_theme_constant_override("separation", 2)
	add_child(doboz)
	_fejlec = Button.new()
	_fejlec.flat = true
	_fejlec.focus_mode = Control.FOCUS_NONE
	_fejlec.add_theme_font_size_override("font_size", 12)
	_fejlec.pressed.connect(func() -> void:
		zart = not zart
		_sig = ""
		_frissit())
	doboz.add_child(_fejlec)
	_sorok = VBoxContainer.new()
	_sorok.add_theme_constant_override("separation", 2)
	doboz.add_child(_sorok)
	visible = false
	set_process(true)

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0: return
	_t = ELLENORZES
	_kieses_ellenorzes()
	_frissit()

# Ki esett ki azóta? Egyszer hirdetjük ki, félenként.
func _kieses_ellenorzes() -> void:
	if not GameState.on or GameState.net_client: return
	for i in range(GameState.oldalak.size()):
		if GameState.is_out(i): continue
		if GameState.side_alive(get_tree(), i): continue
		GameState.mark_out(i)
		_sig = ""
		if main != null and main.hud != null:
			main.hud.show_toast(Lang.t("pt_kiesett_uzenet") % _nev(i), 5.0)
			SFX.play("age", -8.0)

func _nev(i: int) -> String:
	var o := GameState.get_side(i)
	if i == GameState.en_id: return Lang.t("pt_te")
	var nemzet := str(o.get("nemzet", "de"))
	var nev := Style.nation_name(nemzet)
	if str(o.get("tipus", "bot")) == "ember":
		return "%s (%s)" % [nev, Lang.t("pt_ember")]
	return nev

func _frissit() -> void:
	# Két félnél a tábla csak zavarna: ott a régi kép marad.
	var kell: bool = GameState.on and GameState.oldalak.size() > 2
	visible = kell
	if not kell: return
	# Ujjlenyomat: csak akkor rajzolunk újra, ha tényleg változott valami.
	var sig := "%s|%s|" % [Lang.code, str(zart)]
	var adat: Array = []
	for i in range(GameState.oldalak.size()):
		var ep := 0
		var eg := 0
		for b in get_tree().get_nodes_in_group("buildings"):
			if is_instance_valid(b) and int(b.owner_id) == i: ep += 1
		for u in get_tree().get_nodes_in_group("units"):
			if is_instance_valid(u) and int(u.owner_id) == i: eg += 1
		var elo := not GameState.is_out(i)
		var tars := GameState.allied(GameState.en_id, i)
		adat.append({"i": i, "ep": ep, "eg": eg, "elo": elo, "tars": tars})
		sig += "%d:%d:%d:%s:%s;" % [i, ep, eg, "x" if not elo else "-",
			"sz" if tars else "e"]
	# A felmondás visszaszámlálása másodpercenként változik: bele kell venni,
	# különben állna a szám a gombon.
	var d: Node = main.diplomacy if main != null else null
	if d != null and is_instance_valid(d):
		for k in d.felmondas: sig += "f%s%d" % [str(k), int(ceil(float(d.felmondas[k])))]
		for k in d.ajanlat: sig += "a%s" % str(k)
	if sig == _sig: return
	_sig = sig
	_fejlec.text = "%s  %s" % [Lang.t("pt_cim"), "▸" if zart else "▾"]
	for c in _sorok.get_children():
		_sorok.remove_child(c)
		c.queue_free()
	_sorok.visible = not zart
	if zart: return
	var elok := 0
	for a in adat:
		if bool(a["elo"]): elok += 1
	for a in adat:
		_sorok.add_child(_sor(a, elok))

func _sor(a: Dictionary, elok: int) -> Control:
	var i := int(a["i"])
	var elo := bool(a["elo"])
	var sor := HBoxContainer.new()
	sor.add_theme_constant_override("separation", 6)
	sor.custom_minimum_size = Vector2(0, SOR_MAGAS)
	# Színfolt: a fél színe.
	var szin := ColorRect.new()
	szin.color = Style.side_color(i)
	if not elo: szin.color = Color(szin.color, 0.35)
	szin.custom_minimum_size = Vector2(10, 10)
	szin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sor.add_child(szin)
	var nev := Label.new()
	nev.text = _nev(i)
	nev.add_theme_font_size_override("font_size", 12)
	nev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if i == GameState.en_id:
		nev.add_theme_color_override("font_color", Style.side_accent(i))
	elif not elo:
		nev.add_theme_color_override("font_color", Color(0.6, 0.58, 0.54))
	elif bool(a["tars"]):
		nev.add_theme_color_override("font_color", Color(0.62, 0.82, 0.62))
	sor.add_child(nev)
	var szam := Label.new()
	szam.text = Lang.t("pt_kiesett") if not elo else "%d · %d" % [int(a["ep"]), int(a["eg"])]
	szam.add_theme_font_size_override("font_size", 11)
	szam.add_theme_color_override("font_color", Color(0.72, 0.70, 0.64))
	sor.add_child(szam)
	# DIPLOMÁCIA: csak élő, nem saját félnél, és csak ha van kivel — két
	# élő félnél a szövetség azonnali döntetlen lenne.
	var d: Node = main.diplomacy if main != null else null
	if elo and i != GameState.en_id and elok > 2 and d != null and is_instance_valid(d):
		var en := GameState.en_id
		var tars: bool = d.allied(en, i)
		var g := Button.new()
		g.custom_minimum_size = Vector2(66, 18)
		g.add_theme_font_size_override("font_size", 10)
		g.focus_mode = Control.FOCUS_NONE
		var kulcs := "%d-%d" % [mini(en, i), maxi(en, i)]
		if d.felmondas.has(kulcs):
			g.text = "%d s" % int(ceil(float(d.felmondas[kulcs])))
			g.disabled = true
		elif tars:
			g.text = Lang.t("dipl_felmond")
			g.pressed.connect(func() -> void: d.denounce(en, i))
		else:
			g.text = Lang.t("dipl_ajanl")
			g.pressed.connect(func() -> void: d.offer(en, i))
			if d.ajanlat.has(kulcs): g.disabled = true
		sor.add_child(g)
	return sor
