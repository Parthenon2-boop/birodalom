extends Control

@onready var wood_label    := %WoodLabel      as Label
@onready var stone_label   := %StoneLabel     as Label
@onready var gold_label    := %GoldLabel      as Label
@onready var food_label    := %FoodLabel      as Label
@onready var coal_label    := %CoalLabel      as Label
@onready var army_label    := %ArmyLabel      as Label
@onready var minimap       := %Overlay        as Control
@onready var fame_panel    := %FamePanel      as PanelContainer
@onready var fame_label    := %FameLabel      as Label
@onready var fame_bar      := %FameBar        as ProgressBar
@onready var era_bar       := %EraBar         as Label
@onready var sel_panel     := %SelectionPanel as PanelContainer
@onready var sel_title     := %SelTitle       as Label
@onready var sel_hp        := %SelHPBar       as ProgressBar
@onready var sel_info      := %SelInfo        as Label
@onready var action_btns   := %ActionButtons  as HBoxContainer
@onready var build_panel   := %BuildPanel     as VBoxContainer
@onready var pause_overlay := %PauseOverlay   as ColorRect
@onready var move_btn      := %MoveBtn        as Button
@onready var attack_btn    := %AttackBtn      as Button
@onready var stop_btn      := %StopBtn        as Button
@onready var flag_icon     := %FlagIcon       as TextureRect
@onready var era_btn       := %EraButton      as Button
@onready var train_panel   := %TrainPanel     as PanelContainer
@onready var train_title   := %TrainTitle     as Label
@onready var bld_hp        := %BldHPBar       as ProgressBar
@onready var train_btns    := %TrainButtons   as GridContainer
@onready var queue_label   := %QueueLabel     as Label
@onready var rally_row     := %RallyRow       as HBoxContainer
@onready var rally_btn     := %RallyBtn       as Button
@onready var rally_clear   := %RallyClearBtn  as Button
@onready var rally_hint    := %RallyHint      as Label
@onready var over_overlay  := %GameOverOverlay as ColorRect
@onready var over_label    := %OverLabel      as Label
@onready var over_menu_btn := %MenuBtn        as Button
@onready var over_next_btn := %NextBtn        as Button
@onready var over_brief    := %OverBrief      as Label
@onready var mission_panel := %MissionPanel   as PanelContainer
@onready var mission_title := %MissionTitle   as Label
@onready var objective_lbl := %ObjectiveLabel as Label
@onready var menu_btn      := %TopMenuBtn     as Button
@onready var game_menu     := %GameMenu       as ColorRect
@onready var menu_panel_ui := %MenuPanel      as PanelContainer
@onready var menu_title    := %MenuTitle      as Label
@onready var resume_btn    := %ResumeBtn      as Button
@onready var save_btn      := %SaveBtn        as Button
@onready var settings_btn  := %SettingsBtn    as Button
@onready var to_menu_btn   := %ToMenuBtn      as Button
@onready var quit_btn      := %QuitBtn        as Button
@onready var menu_note     := %MenuNote       as Label
@onready var settings_host := %SettingsHost   as VBoxContainer
@onready var settings_back := %SettingsBack   as Button

# A megjeleníthető szövegek az assets/lang/*.json fájlokban vannak, itt
# csak a kulcsok szerepelnek. Így egy új nyelvhez nem kell kódot írni.
const BUILDABLE := ["farm", "house", "barracks", "stable", "smith", "academy",
	"tower", "temple", "hospital", "market", "harbor", "goldmine",
	"airfield", "sugar"]

func era_label(age: int) -> String:
	return Lang.t("kor_%d" % clampi(age, 0, 3))

func unit_name(role: String) -> String:
	return Lang.t("u_" + role)

func build_name(t: String) -> String:
	return Lang.t("e_" + t)

const RES_KEY := {
	"wood": "fa", "stone": "ko", "gold": "arany", "food": "elelem",
	"coal": "szen", "rum": "rum",
}

var _selected : Array = []
var _bld      : Node  = null
var _res      : Node  = null
var _hud_t    : float = 0.0

func _ready() -> void:
	GameState.resources_changed.connect(_update_resources)
	GameState.era_changed.connect(_update_era)
	sel_panel.visible = false
	build_panel.visible = false
	train_panel.visible = false
	pause_overlay.visible = false
	over_overlay.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_icons()
	_build_build_panel()
	move_btn.pressed.connect(_on_move_pressed)
	attack_btn.pressed.connect(_on_attack_pressed)
	stop_btn.pressed.connect(_on_stop_pressed)
	era_btn.pressed.connect(_on_era_pressed)
	over_menu_btn.pressed.connect(_on_back_to_menu)
	over_next_btn.pressed.connect(_on_next_mission)
	rally_btn.pressed.connect(_on_rally_pressed)
	rally_clear.pressed.connect(_on_rally_clear)
	_setup_game_menu()
	Achievements.unlocked_one.connect(_on_achievement)
	mission_panel.visible = false
	fame_panel.visible = GameState.pirate
	GameState.fame_changed.connect(_update_fame)
	_apply_language()
	_update_fame(GameState.fame)
	_update_resources()
	_update_era(0, GameState.get_age())

# A jelenetben magyar alapszövegek állnak; a tényleges nyelvet innen
# írjuk rájuk, hogy a .tscn ne duplázza a fordításokat.
func _apply_language() -> void:
	move_btn.text = Lang.t("mozgas")
	attack_btn.text = Lang.t("tamadas")
	stop_btn.text = Lang.t("megall")
	over_menu_btn.text = Lang.t("vissza_fomenube")
	era_btn.text = Lang.t("korszakvaltas")
	var pl := get_node_or_null("PauseOverlay/PauseLabel") as Label
	if pl: pl.text = Lang.t("szunet")

func _process(_delta: float) -> void:
	# A hadsereg létszám és a kijelölt egység élete folyamatosan változik.
	_tick_toast(_delta)
	# A hadsereglétszám és a korszakgomb végigjárja az egységeket és az
	# épületeket — képkockánként fölösleges, negyedmásodpercenként elég.
	_hud_t -= _delta
	if _hud_t <= 0.0:
		_hud_t = 0.25
		_update_army()
		_update_era_button()
		_update_offer()
		_fleet_tick()
		if not _selected.is_empty(): _update_cry_button(_selected)
	if _selected.size() == 1 and is_instance_valid(_selected[0]):
		sel_hp.value = _selected[0].hp
		_update_carry(_selected[0])
	if is_instance_valid(_res):
		_refresh_resource()
	elif _res != null:
		# A lelőhely kimerült: a panel eltűnik.
		select_resource(null)
	if is_instance_valid(_bld):
		bld_hp.value = _bld.hp
		_update_queue_label()
		if rally_row.visible: _update_rally_hint()
	elif _bld != null:
		select_building(null)

# A TopBar ikonjai: az assets mappában nincs hozzájuk kép, ezért rajzolt
# ikonokat teszünk a helyükre — farakás, kőrakás, aranyrúd, kenyér,
# széntömb és sisak. A TextureRect-eket ezekre cseréljük.
const ICON_BOXES := ["WoodBox", "StoneBox", "GoldBox", "FoodBox",
	"CoalBox", "ArmyBox"]

func _setup_icons() -> void:
	var bar := get_node_or_null("TopBar/HBoxContainer")
	if bar == null: return
	_style_top_bar()
	for box_name in ICON_BOXES:
		var box := bar.get_node_or_null(box_name)
		if box == null: continue
		var old := box.get_node_or_null("Icon")
		if old == null: continue
		var icon := ResIcon.new()
		icon.kind = String(box_name).replace("Box", "").to_lower()
		icon.custom_minimum_size = Vector2(26, 26)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)
		box.move_child(icon, old.get_index())
		box.remove_child(old)
		old.queue_free()

# A felső sáv nem sima fekete csík: sötétből világosabb felé futó
# faragott panel, alul aranyszínű hajszálvonallal, a nyersanyagok között
# függőleges elválasztóval. Így a HUD is a játék világához tartozik.
func _style_top_bar() -> void:
	var bar := get_node_or_null("TopBar") as PanelContainer
	if bar == null: return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1c1610")
	sb.set_border_width(SIDE_BOTTOM, 2)
	sb.border_color = Style.age_gold(GameState.get_age()).darkened(0.25)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	bar.add_theme_stylebox_override("panel", sb)
	# Elválasztó a nyersanyagcsoportok között.
	var box := bar.get_node_or_null("HBoxContainer") as HBoxContainer
	if box == null: return
	box.add_theme_constant_override("separation", 10)
	for name2 in ICON_BOXES:
		var group := box.get_node_or_null(name2) as Control
		if group == null: continue
		if group.get_index() == 0: continue
		var sep := VSeparator.new()
		sep.add_theme_constant_override("separation", 10)
		box.add_child(sep)
		box.move_child(sep, group.get_index())

# Kis rajzolt ikonok a nyersanyagokhoz.
class ResIcon extends Control:
	var kind: String = "wood"

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var o := Vector2((size.x - s) * 0.5, (size.y - s) * 0.5)
		match kind:
			"wood":  _wood(o, s)
			"stone": _stone(o, s)
			"gold":  _gold(o, s)
			"food":  _food(o, s)
			"coal":  _coal(o, s)
			_:       _army(o, s)

	# Farakás: három rönk a végével felénk — kéreg, világos bél, évgyűrűk.
	func _wood(o: Vector2, s: float) -> void:
		var bark := Color(0.34, 0.22, 0.12)
		var core := Color(0.78, 0.60, 0.36)
		for p in [Vector2(0.30, 0.30), Vector2(0.28, 0.70), Vector2(0.70, 0.70)]:
			var pv: Vector2 = p
			var c := o + pv * s
			var r := 0.24 * s
			draw_circle(c + Vector2(0.02, 0.03) * s, r, Color(0, 0, 0, 0.25))
			draw_circle(c, r, bark)
			draw_circle(c, r * 0.74, core)
			draw_arc(c, r * 0.48, 0.0, TAU, 14, core.darkened(0.28), 1.0)
			draw_arc(c, r * 0.24, 0.0, TAU, 10, core.darkened(0.28), 1.0)
			draw_arc(c, r, 0.0, TAU, 18, bark.darkened(0.35), 1.0)

	# Kőrakás: szögletes tömbök, felül megvilágított lappal.
	func _stone(o: Vector2, s: float) -> void:
		var c := Color(0.60, 0.61, 0.65)
		for p in [Vector2(0.32, 0.32), Vector2(0.26, 0.70), Vector2(0.70, 0.68)]:
			var pv: Vector2 = p
			var m := o + pv * s
			var r := 0.24 * s
			var body := PackedVector2Array([
				m + Vector2(-r, r * 0.35), m + Vector2(-r * 0.72, -r * 0.7),
				m + Vector2(r * 0.5, -r), m + Vector2(r, -r * 0.1),
				m + Vector2(r * 0.62, r * 0.85), m + Vector2(-r * 0.4, r)])
			draw_colored_polygon(body, c.darkened(0.24))
			var top := PackedVector2Array()
			for v in body:
				top.append(Vector2(m.x + (v.x - m.x) * 0.8,
					m.y + (v.y - m.y) * 0.5 - r * 0.32))
			draw_colored_polygon(top, c.lightened(0.18))
			var edge := body
			edge.append(body[0])
			draw_polyline(edge, Color(0.26, 0.27, 0.31), 1.0)

	# Aranyrúd: lapos, ferde oldalú tömb, tetején világos lappal.
	func _gold(o: Vector2, s: float) -> void:
		var g := Color(0.86, 0.66, 0.14)
		# oldalfal
		draw_colored_polygon(PackedVector2Array([
			o + Vector2(0.06, 0.74) * s, o + Vector2(0.94, 0.74) * s,
			o + Vector2(0.86, 0.52) * s, o + Vector2(0.14, 0.52) * s]),
			g.darkened(0.22))
		# tetőlap
		draw_colored_polygon(PackedVector2Array([
			o + Vector2(0.14, 0.52) * s, o + Vector2(0.86, 0.52) * s,
			o + Vector2(0.74, 0.32) * s, o + Vector2(0.26, 0.32) * s]),
			g.lightened(0.30))
		draw_polyline(PackedVector2Array([
			o + Vector2(0.06, 0.74) * s, o + Vector2(0.94, 0.74) * s,
			o + Vector2(0.86, 0.52) * s, o + Vector2(0.74, 0.32) * s,
			o + Vector2(0.26, 0.32) * s, o + Vector2(0.14, 0.52) * s,
			o + Vector2(0.06, 0.74) * s]), Color(0.42, 0.30, 0.04), 1.0)
		draw_line(o + Vector2(0.14, 0.52) * s, o + Vector2(0.86, 0.52) * s,
			Color(0.42, 0.30, 0.04), 1.0)

	# Élelem: domború cipó kenyér, bevágásokkal és fénnyel a hátán.
	func _food(o: Vector2, s: float) -> void:
		var b := Color(0.76, 0.52, 0.26)
		var c := o + Vector2(0.50, 0.56) * s
		draw_colored_polygon(_dome(c + Vector2(0.02, 0.03) * s, 0.40 * s,
			0.30 * s), Color(0, 0, 0, 0.22))
		draw_colored_polygon(_dome(c, 0.40 * s, 0.30 * s), b)
		draw_colored_polygon(_dome(c - Vector2(0.03, 0.06) * s, 0.30 * s,
			0.20 * s), b.lightened(0.20))
		for i in range(3):
			var x := 0.32 + 0.18 * float(i)
			draw_line(o + Vector2(x + 0.05, 0.40) * s,
				o + Vector2(x - 0.03, 0.60) * s, b.darkened(0.38), 1.6)
		draw_line(o + Vector2(0.10, 0.74) * s, o + Vector2(0.90, 0.74) * s,
			b.darkened(0.48), 1.6)

	# Fél ellipszis (kupola): a lapos alján ül.
	func _dome(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in range(13):
			var a := PI + PI * float(i) / 12.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		return pts

	# Széntömb: sötét, szögletes darab csillanással.
	func _coal(o: Vector2, s: float) -> void:
		var c := Color(0.16, 0.16, 0.19)
		draw_colored_polygon(PackedVector2Array([
			o + Vector2(0.14, 0.56) * s, o + Vector2(0.34, 0.22) * s,
			o + Vector2(0.72, 0.20) * s, o + Vector2(0.90, 0.54) * s,
			o + Vector2(0.66, 0.82) * s, o + Vector2(0.26, 0.80) * s]), c)
		draw_colored_polygon(PackedVector2Array([
			o + Vector2(0.36, 0.30) * s, o + Vector2(0.62, 0.28) * s,
			o + Vector2(0.52, 0.48) * s]), Color(0.42, 0.44, 0.50))
		draw_polyline(PackedVector2Array([
			o + Vector2(0.14, 0.56) * s, o + Vector2(0.34, 0.22) * s,
			o + Vector2(0.72, 0.20) * s, o + Vector2(0.90, 0.54) * s,
			o + Vector2(0.66, 0.82) * s, o + Vector2(0.26, 0.80) * s,
			o + Vector2(0.14, 0.56) * s]), Color(0.05, 0.05, 0.07), 1.0)

	# Hadsereg: KATONA, nem üres sisak. Lándzsa a háta mögött, pajzs a
	# karján, sisak a fején — kicsiben is fölismerhető emberalak.
	func _army(o: Vector2, s: float) -> void:
		var steel  := Color(0.70, 0.73, 0.79)
		var shade  := Color(0.40, 0.43, 0.49)
		var skin   := Color(0.83, 0.66, 0.50)
		var cloth  := Color(0.55, 0.20, 0.19)
		var wood   := Color(0.42, 0.29, 0.16)
		# lándzsa: átlósan a válla mögött
		draw_line(o + Vector2(0.80, 0.06) * s, o + Vector2(0.56, 0.96) * s,
			wood, maxf(1.5, s * 0.07))
		draw_colored_polygon(PackedVector2Array([
			o + Vector2(0.80, 0.02) * s, o + Vector2(0.87, 0.16) * s,
			o + Vector2(0.74, 0.16) * s]), steel)
		# törzs: vállban széles, derékban keskeny köpeny
		draw_colored_polygon(PackedVector2Array([
			o + Vector2(0.24, 0.52) * s, o + Vector2(0.72, 0.52) * s,
			o + Vector2(0.66, 0.96) * s, o + Vector2(0.30, 0.96) * s]), cloth)
		draw_colored_polygon(PackedVector2Array([
			o + Vector2(0.24, 0.52) * s, o + Vector2(0.44, 0.52) * s,
			o + Vector2(0.40, 0.96) * s, o + Vector2(0.30, 0.96) * s]),
			cloth.lightened(0.12))
		# vállvért
		draw_colored_polygon(PackedVector2Array([
			o + Vector2(0.22, 0.56) * s, o + Vector2(0.48, 0.50) * s,
			o + Vector2(0.74, 0.56) * s, o + Vector2(0.74, 0.62) * s,
			o + Vector2(0.22, 0.62) * s]), steel)
		# fej és sisak
		draw_circle(o + Vector2(0.48, 0.36) * s, 0.15 * s, skin)
		draw_colored_polygon(PackedVector2Array([
			o + Vector2(0.32, 0.36) * s, o + Vector2(0.34, 0.24) * s,
			o + Vector2(0.48, 0.17) * s, o + Vector2(0.62, 0.24) * s,
			o + Vector2(0.64, 0.36) * s]), steel)
		draw_rect(Rect2(o + Vector2(0.32, 0.33) * s, Vector2(0.32, 0.05) * s),
			shade, true)                                   # sisakperem
		# pajzs a bal karján
		draw_colored_polygon(PackedVector2Array([
			o + Vector2(0.10, 0.56) * s, o + Vector2(0.34, 0.56) * s,
			o + Vector2(0.34, 0.80) * s, o + Vector2(0.22, 0.92) * s,
			o + Vector2(0.10, 0.80) * s]), cloth.darkened(0.25))
		draw_polyline(PackedVector2Array([
			o + Vector2(0.10, 0.56) * s, o + Vector2(0.34, 0.56) * s,
			o + Vector2(0.34, 0.80) * s, o + Vector2(0.22, 0.92) * s,
			o + Vector2(0.10, 0.80) * s, o + Vector2(0.10, 0.56) * s]),
			steel.darkened(0.15), 1.0)
		draw_line(o + Vector2(0.22, 0.58) * s, o + Vector2(0.22, 0.88) * s,
			steel, 1.0)

func _build_build_panel() -> void:
	for c in build_panel.get_children():
		build_panel.remove_child(c)
		c.queue_free()
	var main := get_tree().get_first_node_in_group("main")
	var age := GameState.get_age()
	for entry in BUILDABLE:
		var t: String = entry
		var st: Dictionary = Building.BUILD_STATS.get(t, {})
		if age < int(st.get("minAge", 0)):
			continue                       # a repülőtér csak a modern korban áll
		# A cukornád csak a kalózvilágban építhető.
		if bool(st.get("pirateOnly", false)) and not GameState.pirate:
			continue
		# A küldetés tilthat épületeket (pl. kaszárnya nélküli hadjárat).
		if t in GameState.banned_buildings:
			continue
		var btn := Button.new()
		btn.text = build_name(t)
		btn.custom_minimum_size = Vector2(150, 30)
		if main != null:
			btn.tooltip_text = _cost_text(main.build_cost(GameState.en_id, t))
		btn.pressed.connect(func() -> void: _on_build_pressed(t))
		build_panel.add_child(btn)

func _on_build_pressed(tipus: String) -> void:
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("set_build_mode"):
		main.set_build_mode(tipus)
	SFX.play("click")

func _update_resources() -> void:
	var res := GameState.get_res()
	wood_label.text  = "%s %d" % [Lang.t("fa"), int(res.get("wood", 0))]
	stone_label.text = "%s %d" % [Lang.t("ko"), int(res.get("stone", 0))]
	gold_label.text  = "%s %d" % [Lang.t("arany"), int(res.get("gold", 0))]
	food_label.text  = "%s %d" % [Lang.t("elelem"), int(res.get("food", 0))]
	# A kalózvilágban nincs szén, viszont van rum — ugyanaz a sor mutatja.
	if GameState.pirate:
		coal_label.text = "%s %d" % [Lang.t("rum"), int(res.get("rum", 0))]
	else:
		coal_label.text = "%s %d" % [Lang.t("szen"), int(res.get("coal", 0))]
	_update_army()

func _update_army() -> void:
	var tree := get_tree()
	if tree == null: return
	army_label.text = "%s %d / %d" % [Lang.t("hadsereg"),
		ResourceSystem.pop_used(tree, GameState.en_id),
		ResourceSystem.pop_limit(tree, GameState.en_id)]

func _update_era(_owner_id: int, new_age: int) -> void:
	if GameState.pirate:
		# A kalózfrakcióknál nincs korszak: a frakció neve áll a helyén.
		var nat: Dictionary = Style.nation(GameState.nation)
		var eras: Array = nat.get("eras", [])
		era_bar.text = str(eras[0]) if not eras.is_empty() else str(nat.get("name", ""))
	else:
		era_bar.text = era_label(new_age)
	_update_flag()
	_build_build_panel()
	if is_instance_valid(_bld): select_building(_bld)

# A játszma indulásakor a mód (kalóz vagy sem) még nem volt ismert, amikor
# a HUD felépült — a Main ezzel frissíti a feliratokat és a paneleket.
func refresh_mode() -> void:
	fame_panel.visible = GameState.pirate
	minimap.queue_redraw()
	_update_fame(GameState.fame)
	_update_era(0, GameState.get_age())
	_update_resources()

# --- Korszakváltás ---

func _update_era_button() -> void:
	# A kalózvilágban nincs korszakváltás — ott a gomb helyén a hírnévmérő áll.
	if GameState.pirate:
		era_btn.visible = false
		return
	var age := GameState.get_age()
	if age >= 3:
		era_btn.disabled = true
		era_btn.text = Lang.t("legmagasabb_korszak")
		return
	var cost: Dictionary = Style.ERA_COST[age]
	era_btn.disabled = not GameState.can_pay(GameState.en_id, cost)
	era_btn.text = "%s  (%d %s, %d %s)" % [
		Lang.t("kor_alcim_%d" % (age + 1)),
		int(cost.get("food", 0)), Lang.t("elelem"),
		int(cost.get("gold", 0)), Lang.t("arany")]

func _on_era_pressed() -> void:
	var age := GameState.get_age()
	if age >= 3: return
	if not GameState.can_pay(GameState.en_id, Style.ERA_COST[age]): return
	_send("era", [])

# --- Játék közbeni menü (jobb felső sarok) ---
#
# Mentés, beállítások és kilépés. Amíg nyitva van, a játék áll — a régi
# HTML változat ☰ menüje ugyanígy működött.

var _settings_ui: SettingsPanel = null
var _was_running := false

func _setup_game_menu() -> void:
	game_menu.visible = false
	settings_host.visible = false
	menu_btn.tooltip_text = Lang.t("menu")
	menu_btn.pressed.connect(func() -> void: open_game_menu(true))
	resume_btn.pressed.connect(func() -> void: open_game_menu(false))
	save_btn.pressed.connect(_on_save_pressed)
	settings_btn.pressed.connect(func() -> void: _show_settings(true))
	settings_back.pressed.connect(func() -> void: _show_settings(false))
	to_menu_btn.pressed.connect(_on_back_to_menu)
	quit_btn.pressed.connect(_on_quit_game)
	# A beállítások panelt itt hozzuk létre, hogy a főmenüével azonos
	# legyen — a SettingsHost első helyére, a Vissza gomb elé.
	_settings_ui = SettingsPanel.new()
	settings_host.add_child(_settings_ui)
	settings_host.move_child(_settings_ui, 0)
	_apply_menu_language()

func _apply_menu_language() -> void:
	menu_title.text = Lang.t("menu")
	resume_btn.text = Lang.t("folytatas_jatek")
	save_btn.text = Lang.t("mentes")
	settings_btn.text = Lang.t("beallitasok")
	to_menu_btn.text = Lang.t("vissza_fomenube")
	quit_btn.text = Lang.t("kilepes_jatekbol")
	settings_back.text = Lang.t("vissza")

func open_game_menu(on: bool) -> void:
	SFX.play("click")
	if on:
		_was_running = GameState.on
		GameState.on = false
		get_tree().paused = true
		menu_note.text = ""
		_show_settings(false)
		_refresh_diplomacy()
	else:
		get_tree().paused = false
		GameState.on = _was_running
	game_menu.visible = on

func game_menu_open() -> bool:
	return game_menu.visible

# --- DIPLOMÁCIA a játék menüjében ---
#
# Több fél esetén itt lehet szövetséget ajánlani és felmondani. Kettőnél
# nincs mit tárgyalni, ezért a rész ilyenkor meg sem jelenik.
var _dipl_box: VBoxContainer = null

func _refresh_diplomacy() -> void:
	var main := get_tree().get_first_node_in_group("main")
	var d: Node = main.diplomacy if main != null else null
	if _dipl_box == null:
		_dipl_box = VBoxContainer.new()
		_dipl_box.name = "DiplBox"
		_dipl_box.add_theme_constant_override("separation", 4)
		menu_note.get_parent().add_child(_dipl_box)
	for c in _dipl_box.get_children():
		_dipl_box.remove_child(c)
		c.queue_free()
	_dipl_box.visible = d != null and GameState.oldalak.size() > 2
	if not _dipl_box.visible: return
	var cim := Label.new()
	cim.text = Lang.t("dipl_cim")
	cim.add_theme_color_override("font_color", Style.GOLD)
	_dipl_box.add_child(cim)
	for i in range(GameState.oldalak.size()):
		if i == GameState.en_id: continue
		var masik := i
		var sor := HBoxContainer.new()
		sor.add_theme_constant_override("separation", 6)
		var nev := Label.new()
		nev.text = Style.nation_name(str(GameState.get_side(masik).get("nemzet", "de")))
		nev.custom_minimum_size = Vector2(150, 0)
		nev.add_theme_color_override("font_color", Style.side_color(masik))
		sor.add_child(nev)
		var allapot := Label.new()
		allapot.custom_minimum_size = Vector2(90, 0)
		allapot.text = Lang.t("dipl_szovetseges") if d.allied(GameState.en_id, masik) else ""
		sor.add_child(allapot)
		var gomb := Button.new()
		gomb.custom_minimum_size = Vector2(150, 26)
		if d.allied(GameState.en_id, masik):
			gomb.text = Lang.t("dipl_felmond")
			gomb.pressed.connect(func() -> void:
				d.denounce(GameState.en_id, masik)
				_refresh_diplomacy())
		else:
			gomb.text = Lang.t("dipl_ajanl")
			gomb.pressed.connect(func() -> void:
				d.offer(GameState.en_id, masik)
				_refresh_diplomacy())
		sor.add_child(gomb)
		_dipl_box.add_child(sor)

func _show_settings(on: bool) -> void:
	menu_panel_ui.visible = not on
	settings_host.visible = on

func _on_save_pressed() -> void:
	SaveManager.save_game()
	menu_note.text = Lang.t("mentve")
	SFX.play("click")

func _on_quit_game() -> void:
	get_tree().paused = false
	get_tree().quit()

# Új teljesítmény: rövid üzenet, hogy tudd, mit értél el.
func _on_achievement(id: String) -> void:
	show_toast("%s — %s" % [Lang.t("teljesitmeny_uj"),
		Achievements.title_of(id)], 5.0)
	SFX.play("age", -5.0)

# --- Rövid üzenet a képernyő közepén ---

var _toast: Label = null
var _toast_t: float = 0.0

func show_toast(text: String, seconds: float = 4.0) -> void:
	if _toast == null:
		_toast = Label.new()
		_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_toast.anchor_left = 0.5
		_toast.anchor_right = 0.5
		_toast.offset_left = -300.0
		_toast.offset_right = 300.0
		_toast.offset_top = 118.0
		_toast.offset_bottom = 214.0
		# Hosszú üzenet (küldetés-eligazítás, súgó) is elfér: tördelünk,
		# és a doboz elég magas hozzá.
		_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_toast.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_toast.add_theme_font_size_override("font_size", 17)
		_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_toast)
	_toast.text = text
	_toast.visible = true
	_toast_t = seconds

func _tick_toast(delta: float) -> void:
	if _toast == null or not _toast.visible: return
	_toast_t -= delta
	_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	if _toast_t <= 0.0:
		_toast.visible = false

# --- Hírnév (kalózvilág) ---
#
# A zsákmány hírnevet hoz, a hírnév viszont a királyi hajóhadat.
func _update_fame(value: float) -> void:
	if not GameState.pirate: return
	fame_bar.max_value = GameState.FAME_MAX
	fame_bar.value = minf(value, GameState.FAME_MAX)
	var szint := Lang.t("hirnev_csend")
	if value >= 90.0:   szint = Lang.t("hirnev_kiraly")
	elif value >= 70.0: szint = Lang.t("hirnev_kormanyzo")
	elif value >= 40.0: szint = Lang.t("hirnev_terjed")
	fame_label.text = "%s %d — %s" % [Lang.t("hirnev"), int(value), szint]

# --- Zászló ---

func _update_flag() -> void:
	# A kalózfrakciók nem lépnek korszakot: mindig az első lapjuk kell.
	var tex := Style.flag_texture(GameState.nation,
		0 if GameState.pirate else GameState.get_age())
	flag_icon.texture = tex
	if tex != null:
		flag_icon.tooltip_text = str(Style.nation(GameState.nation)["name"])

# --- Kijelölés ---

func update_selection(units: Array) -> void:
	_selected = units
	if not units.is_empty():
		select_building(null)
		select_resource(null)
	sel_panel.visible = not units.is_empty()
	build_panel.visible = _has_worker(units)
	if units.is_empty(): return
	sel_hp.visible = true
	action_btns.visible = true
	sel_info.visible = false
	if units.size() == 1:
		var u = units[0]
		var r: String = u.role if "role" in u else "?"
		sel_title.text = unit_name(r)
		# A VETERÁN fokozat a név mellé kerül: "Kardos — veterán (4 ölés)".
		if "vet" in u and int(u.vet) > 0:
			sel_title.text += " — %s (%d)" % [
				Lang.t(Unit.VET_KULCS[int(u.vet)]), int(u.kills)]
		sel_hp.max_value = u.max_hp
		sel_hp.value = u.hp
		_update_carry(u)
	else:
		sel_title.text = Lang.t("egyseg_tobb") % units.size()
		sel_hp.visible = false
	_update_cry_button(units)
	_update_tactics(units)

# --- HARCI ÁLLÁS ÉS ALAKZAT  (index.html 8/B) ---
#
# Két sor a parancsgombok alatt: fent az ÁLLÁS (csak a kijelölt egységekre),
# lent az ALAKZAT (az egész seregre). A kiválasztott gomb ki van emelve.
var _stance_row: HBoxContainer = null
var _form_row: HBoxContainer = null
var _stance_btns := {}
var _form_btns := {}

func _build_tactics() -> void:
	var szulo := action_btns.get_parent()
	_stance_row = HBoxContainer.new()
	_stance_row.name = "StanceRow"
	_stance_row.add_theme_constant_override("separation", 4)
	szulo.add_child(_stance_row)
	for a in ["aggro", "hold", "flee"]:
		var allas: String = a
		var b := Button.new()
		b.custom_minimum_size = Vector2(84, 24)
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(func() -> void: _on_stance(allas))
		_stance_row.add_child(b)
		_stance_btns[allas] = b
	_form_row = HBoxContainer.new()
	_form_row.name = "FormRow"
	_form_row.add_theme_constant_override("separation", 4)
	szulo.add_child(_form_row)
	for f in Unit.FORMATIONS:
		var alak: String = f
		var b2 := Button.new()
		b2.custom_minimum_size = Vector2(84, 24)
		b2.add_theme_font_size_override("font_size", 11)
		b2.pressed.connect(func() -> void: _send("form", [alak]))
		_form_row.add_child(b2)
		_form_btns[alak] = b2

func _on_stance(allas: String) -> void:
	var ids: Array = []
	for u in _selected:
		if is_instance_valid(u) and u.role != "worker": ids.append(int(u.nid))
	if ids.is_empty(): return
	_send("stance", [ids, allas])

func _update_tactics(units: Array) -> void:
	if _stance_row == null: _build_tactics()
	# Munkásokra nincs értelme: az ő kijelölésüknél nem is látszik.
	var harcos := false
	for u in units:
		if is_instance_valid(u) and u.role != "worker" and int(u.owner_id) == GameState.en_id:
			harcos = true
			break
	_stance_row.visible = harcos
	_form_row.visible = harcos
	if not harcos: return
	# Melyik állás van a kijelölésen? (Ha vegyes, egyik sincs kiemelve.)
	var kozos := ""
	for u in units:
		if not is_instance_valid(u) or u.role == "worker": continue
		if kozos == "": kozos = str(u.stance)
		elif kozos != str(u.stance): kozos = "?"
	for a in _stance_btns:
		var b: Button = _stance_btns[a]
		b.text = Lang.t("allas_" + str(a))
		b.tooltip_text = Lang.t("allas_%s_al" % str(a))
		b.flat = str(a) != kozos
	var most := Unit.formation_of(GameState.en_id)
	for f in _form_btns:
		var b3: Button = _form_btns[f]
		b3.text = Lang.t("alakzat_" + str(f))
		b3.tooltip_text = Lang.t("alakzat_%s_al" % str(f))
		b3.flat = str(f) != most

# CSATAKIÁLTÁS: a hős kijelölésekor megjelenik egy gomb. Nyolc másodpercig
# a körülötte állók többet sebeznek és gyorsabban mozognak; kilencven
# másodpercenként egyszer lehet.
func _update_cry_button(units: Array) -> void:
	var hos: Node = null
	for u in units:
		if is_instance_valid(u) and u.role == "hero" and int(u.owner_id) == GameState.en_id:
			hos = u
			break
	if hos == null:
		if _cry_btn != null: _cry_btn.visible = false
		return
	if _cry_btn == null:
		_cry_btn = Button.new()
		_cry_btn.name = "CryBtn"
		_cry_btn.custom_minimum_size = Vector2(120, 28)
		action_btns.add_child(_cry_btn)
	_cry_btn.visible = true
	_cry_btn.text = Lang.t("csatakialtas")
	_cry_btn.disabled = not hos.kialtas_kesz()
	_cry_btn.tooltip_text = Lang.t("csatakialtas_sugo") if hos.kialtas_kesz() \
		else Lang.t("csatakialtas_var") % int(ceil(hos.kialtas_t))
	for c in _cry_btn.pressed.get_connections():
		_cry_btn.pressed.disconnect(c["callable"])
	_cry_btn.pressed.connect(func() -> void:
		var db: int = hos.kialtas()
		if db > 0:
			show_toast(Lang.t("csatakialtas_uzenet") % db, 3.0)
		_update_cry_button(_selected))

var _cry_btn: Button = null

# --- ZSOLDOS-AJÁNLAT (esemény) ---
#
# Amikor zsoldosok ajánlkoznak, a képernyő tetején megjelenik egy panel az
# ajánlattal: hányan, mennyiért, és hogy elfogadod-e. Az ajánlat lejár.
var _offer_panel : PanelContainer = null
var _offer_label : Label = null

func _build_offer_panel() -> void:
	_offer_panel = PanelContainer.new()
	_offer_panel.name = "OfferPanel"
	_offer_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_offer_panel.position = Vector2(-190, 74)
	_offer_panel.custom_minimum_size = Vector2(380, 0)
	_offer_panel.visible = false
	add_child(_offer_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_offer_panel.add_child(box)
	_offer_label = Label.new()
	_offer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_offer_label)
	var sor := HBoxContainer.new()
	sor.alignment = BoxContainer.ALIGNMENT_CENTER
	sor.add_theme_constant_override("separation", 8)
	box.add_child(sor)
	var igen := Button.new()
	igen.text = Lang.t("ev_elfogad")
	igen.custom_minimum_size = Vector2(150, 30)
	igen.pressed.connect(func() -> void:
		var m := get_tree().get_first_node_in_group("main")
		if m != null and m.events != null: m.events.accept_offer()
		_update_offer())
	sor.add_child(igen)
	var nem := Button.new()
	nem.text = Lang.t("ev_elutasit")
	nem.custom_minimum_size = Vector2(150, 30)
	nem.pressed.connect(func() -> void:
		var m := get_tree().get_first_node_in_group("main")
		if m != null and m.events != null: m.events.decline_offer()
		_update_offer())
	sor.add_child(nem)

func _update_offer() -> void:
	if _offer_panel == null: _build_offer_panel()
	var m := get_tree().get_first_node_in_group("main")
	if m == null or m.events == null:
		_offer_panel.visible = false
		return
	var o: Dictionary = m.events.offer
	_offer_panel.visible = not o.is_empty()
	if o.is_empty(): return
	var hatra := int(ceil(m.events.AJANLAT_LEJAR - (GameState.t - float(o["t"]))))
	_offer_label.text = "%s  (%d s)" % [
		Lang.t("ev_zsoldos") % [int(o["db"]), int(o["ar"])], maxi(hatra, 0)]

# --- FLOTTASÁV  (index.html: fleetBar) ---
#
# A kalózvilágban a hajóid a mindened, de a stratégiai nézetben aprók és
# szétszórtak. Ez a sáv mindegyiket felsorolja — osztály, sérülés, hány fő
# van a fedélzeten —, és kattintásra odaviszi a kamerát.
#
# Csak akkor épül újra, ha VÁLTOZOTT valami: különben a kattintás elveszne
# a folyamatos újraépítésben (ugyanaz a buktató, mint a kikötőmenünél).
var _fleet_box: VBoxContainer = null
var _fleet_sig: String = ""

const HAJO_NEV := {
	"transport": "pm_hajo_transport", "warship": "pm_hajo_warship",
	"galleon": "pm_hajo_galleon", "fisher": "u_fisher",
}

func _build_fleet_bar() -> void:
	var panel := PanelContainer.new()
	panel.name = "FleetBar"
	panel.position = Vector2(12, 132)
	panel.custom_minimum_size = Vector2(150, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(panel)
	_fleet_box = VBoxContainer.new()
	_fleet_box.add_theme_constant_override("separation", 4)
	panel.add_child(_fleet_box)
	panel.visible = false

func _fleet_tick() -> void:
	if not GameState.pirate: return
	if _fleet_box == null: _build_fleet_bar()
	var panel := _fleet_box.get_parent() as Control
	var hajok: Array = []
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and int(u.owner_id) == GameState.en_id and u.naval:
			hajok.append(u)
	panel.visible = not hajok.is_empty() and GameState.on and not game_menu_open()
	if not panel.visible: return
	var sig := ""
	for u in hajok:
		sig += "%d:%d:%d|" % [int(u.nid), int(u.hp), u.cargo.size()]
	if sig == _fleet_sig: return
	_fleet_sig = sig
	for c in _fleet_box.get_children():
		_fleet_box.remove_child(c)
		c.queue_free()
	for h in hajok:
		_fleet_box.add_child(_fleet_row(h))

func _fleet_row(u: Node) -> Control:
	var sor := Button.new()
	sor.custom_minimum_size = Vector2(134, 24)
	sor.focus_mode = Control.FOCUS_NONE
	sor.flat = true
	sor.pressed.connect(func() -> void: _fleet_jump(u))
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sor.add_child(box)
	var nev := Label.new()
	nev.text = Lang.t(str(HAJO_NEV.get(str(u.role), "u_" + str(u.role))))
	nev.add_theme_font_size_override("font_size", 11)
	nev.custom_minimum_size = Vector2(52, 0)
	box.add_child(nev)
	var arany: float = clampf(float(u.hp) / maxf(float(u.max_hp), 1.0), 0.0, 1.0)
	var sav := ProgressBar.new()
	sav.custom_minimum_size = Vector2(34, 6)
	sav.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sav.show_percentage = false
	sav.max_value = 1.0
	sav.value = arany
	var kitolt := StyleBoxFlat.new()
	# zöld -> sárga -> vörös, ahogy fogy az élet
	kitolt.bg_color = Color("6fae52") if arany >= 0.7 \
		else (Color("c98b3a") if arany >= 0.35 else Color("c04a3a"))
	sav.add_theme_stylebox_override("fill", kitolt)
	box.add_child(sav)
	var fo := Label.new()
	fo.text = "%d %s" % [u.cargo.size(), Lang.t("pm_fo")]
	fo.add_theme_font_size_override("font_size", 10)
	fo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(fo)
	return sor

func _fleet_jump(u: Node) -> void:
	if not is_instance_valid(u): return
	var main := get_tree().get_first_node_in_group("main")
	if main == null: return
	main.select_only(u)
	main.camera.position = u.global_position
	SFX.play("click")

# Egyetlen munkás kijelölésekor a panelen is látszik a rakománya.
func _update_carry(u: Node) -> void:
	if not u.has_method("carry_amount"): return
	var amount: float = u.carry_amount()
	if amount <= 0.0:
		sel_info.visible = false
		return
	var key: String = u.carry_kind()
	sel_info.visible = true
	sel_info.add_theme_color_override("font_color",
		ResourceSystem.res_color(key))
	var res_name: String = RES_KEY.get(key, key)
	sel_info.text = "%s: %s %d / %d" % [Lang.t("rakomany"),
		Lang.t(res_name), int(round(amount)), int(u.load_cap())]

# Nyersanyag-lelőhely kijelölése: mennyi termelhető ki még belőle.
func select_resource(node: Node) -> void:
	_res = node
	if node == null or not is_instance_valid(node):
		_res = null
		if _selected.is_empty() and _bld == null:
			sel_panel.visible = false
		return
	_selected = []
	select_building(null)
	build_panel.visible = false
	action_btns.visible = false      # lelőhelynek nincs parancsa
	sel_panel.visible = true
	sel_hp.visible = true
	sel_info.visible = true
	sel_info.remove_theme_color_override("font_color")
	sel_title.text = node_name(str(node.kind))
	_refresh_resource()

func node_name(kind: String) -> String:
	return Lang.t("lh_" + kind)

func _refresh_resource() -> void:
	if not is_instance_valid(_res): return
	var left: float = _res.amount
	var full: float = maxf(_res.max_amount, 1.0)
	sel_hp.max_value = full
	sel_hp.value = left
	var key: String = ResourceSystem.yield_kind(str(_res.kind))
	var res_name: String = RES_KEY.get(key, key)
	var txt := "%s: %d / %d %s" % [Lang.t("kitermelheto"), int(ceil(left)),
		int(full), Lang.t(res_name)]
	# Ha dolgoznak rajta, azt is megmutatjuk, meddig tart még.
	var n: int = _res.worker_count()
	if n > 0:
		var per_sec := float(n) * ResourceSystem.PER_SWING / ResourceSystem.SWING_TIME
		txt += "\n" + Lang.t("kimerul") % [n, int(left / maxf(per_sec, 0.01))]
	sel_info.text = txt

# Saját épület kijelölése: a képezhető egységek gombjai jelennek meg.
func select_building(b: Node) -> void:
	_bld = b
	if b == null or not is_instance_valid(b):
		_bld = null
		train_panel.visible = false
		if _selected.is_empty() and _res == null:
			sel_panel.visible = false
		return
	_selected = []
	_res = null
	build_panel.visible = false
	# Épületnek nincs értelme a Mozgás/Támadás/Megáll gomb, ezért az
	# egység-panel nem jelenik meg. Az életerő oda kerül, ahol toborzol:
	# a képzési panel tetejére.
	sel_panel.visible = false
	var name: String = build_name(b.tipus)
	bld_hp.max_value = b.max_hp
	bld_hp.value = b.hp
	var roles: Array = b.trainable()
	var fejleszt := Upgrades.researches(b.tipus)
	if not roles.is_empty():
		train_title.text = "%s — %s" % [name, Lang.t("kepzes")]
	elif fejleszt:
		train_title.text = "%s — %s" % [name, Lang.t("kutatas")]
	else:
		train_title.text = name
	for c in train_btns.get_children():
		train_btns.remove_child(c)
		c.queue_free()
	for role in roles:
		var r: String = role
		var btn := Button.new()
		btn.text = unit_name(r)
		btn.tooltip_text = _cost_text(Building.train_cost(GameState.en_id, r))
		btn.custom_minimum_size = Vector2(120, 28)
		btn.pressed.connect(func() -> void: _on_train_pressed(r))
		train_btns.add_child(btn)
	# A kovácsműhely és az akadémia nemcsak (vagy egyáltalán nem) képez,
	# hanem KUTAT: ugyanide kerülnek a fejlesztés-gombok.
	_add_research_buttons(b.tipus)
	_add_market_buttons(b)
	# A gyülekezőpont csak ott értelmes, ahol tényleg képeznek egységet.
	rally_row.visible = not roles.is_empty()
	rally_hint.visible = not roles.is_empty()
	_update_rally_hint()
	# A panel akkor is látszik, ha az épület nem képez semmit — az
	# életereje és az állapota így is olvasható.
	train_panel.visible = true
	_update_queue_label()

# --- Gyülekezőpont ---

func _on_rally_pressed() -> void:
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("set_rally_mode"):
		main.set_rally_mode(true)
		SFX.play("click")

func _on_rally_clear() -> void:
	if not is_instance_valid(_bld): return
	if _bld.has_method("clear_rally"):
		_bld.clear_rally()
		SFX.play("click")
		_update_rally_hint()

func _update_rally_hint() -> void:
	if not is_instance_valid(_bld): return
	rally_btn.text = Lang.t("gyulekezo")
	rally_clear.tooltip_text = Lang.t("gyulekezo_torol")
	var k: String = _bld.rally_kind() if _bld.has_method("rally_kind") else ""
	rally_hint.text = Lang.t("gyulekezo_" + k) if k != "" \
		else Lang.t("gyulekezo_nincs")

func _on_train_pressed(role: String) -> void:
	if not is_instance_valid(_bld): return
	if not GameState.can_pay(GameState.en_id,
			Building.train_cost(GameState.en_id, role)): return
	_send("train", [int(_bld.nid), role])
	SFX.play("click")

# --- Fejlesztések ---
#
# A gomb felirata a rövid név és a fokozat: "Fegyver 1/3". Ami már kifutott
# vagy a korszak miatt még nem elérhető, az kikapcsolva marad — így látszik,
# hogy LÉTEZIK, csak nem most.
# A PIAC: nyersanyagcsere aranyért, mozgó árfolyammal (index.html 7/B).
# Minden sor egy nyersanyag: balra az eladás, jobbra a vétel, a gombokon
# a PILLANATNYI árral. Eladásnál kevesebbet kapsz, mint amennyiért
# megvennéd — ez a piac haszna.
func _add_market_buttons(b: Node) -> void:
	if b == null or b.tipus != "market": return
	if int(b.owner_id) != GameState.en_id: return
	var main := get_tree().get_first_node_in_group("main")
	if main == null or main.market == null: return
	var m = main.market
	var fejlec := Label.new()
	fejlec.text = Lang.t("piac_cim")
	fejlec.add_theme_color_override("font_color", Style.GOLD)
	train_btns.add_child(fejlec)
	for res in m.RES:
		var r := str(res)
		# A kalózvilágban a kő helyett rummal kereskedünk.
		if GameState.pirate and r == "stone": r = "rum"
		var sor := HBoxContainer.new()
		sor.add_theme_constant_override("separation", 4)
		var nev := Label.new()
		nev.text = Lang.t(RES_KEY.get(r, r))
		nev.custom_minimum_size = Vector2(70, 0)
		sor.add_child(nev)
		var elad := Button.new()
		elad.text = "%s %d ⇒ %d" % [Lang.t("piac_elad"), int(m.UNIT),
			m.sell_price(GameState.en_id, str(res))]
		elad.tooltip_text = Lang.t("piac_elad_sugo")
		elad.custom_minimum_size = Vector2(120, 26)
		elad.pressed.connect(func() -> void:
			var ar: int = m.sell(GameState.en_id, str(res))
			if ar <= 0:
				show_toast(Lang.t("piac_nincs_eleg"), 2.0)
				return
			SFX.play("click")
			select_building(_bld))
		sor.add_child(elad)
		var vesz := Button.new()
		vesz.text = "%s %d ⇐ %d" % [Lang.t("piac_vesz"), int(m.UNIT),
			m.buy_price(GameState.en_id, str(res))]
		vesz.tooltip_text = Lang.t("piac_vesz_sugo")
		vesz.custom_minimum_size = Vector2(120, 26)
		vesz.pressed.connect(func() -> void:
			var ar: int = m.buy(GameState.en_id, str(res))
			if ar <= 0:
				show_toast(Lang.t("piac_nincs_arany"), 2.0)
				return
			SFX.play("click")
			select_building(_bld))
		sor.add_child(vesz)
		train_btns.add_child(sor)

func _add_research_buttons(tipus: String) -> void:
	var me := GameState.en_id
	for key in Upgrades.list_for(tipus):
		var k: String = key
		var lv := Upgrades.level(me, k)
		var btn := Button.new()
		btn.text = "%s %d/%d" % [Lang.t("upg_" + k), lv, Upgrades.max_level(k)]
		btn.custom_minimum_size = Vector2(120, 28)
		if not Upgrades.available(me, k):
			btn.disabled = true
			# Két külön ok, és a játékosnak tudnia kell, melyikről van szó.
			btn.tooltip_text = Lang.t("upg_kesz") if lv >= Upgrades.max_level(k) \
				else Lang.t("upg_korszak")
		else:
			btn.tooltip_text = "%s\n%s" % [Lang.t("upg_leiras_" + k),
				_cost_text(Upgrades.cost(me, k))]
			btn.pressed.connect(func() -> void: _on_research_pressed(k))
		train_btns.add_child(btn)

func _on_research_pressed(key: String) -> void:
	var me := GameState.en_id
	if not Upgrades.available(me, key): return
	if not GameState.can_pay(me, Upgrades.cost(me, key)): return
	_send("upg", [Upgrades.ORDER.find(key)])
	SFX.play("click")

# A kutatás után a panel elavul: más a fokozat és más az ár.
func refresh_building_panel() -> void:
	if is_instance_valid(_bld): select_building(_bld)

# Hálózati játszmában a parancs a házigazdához megy; egyjátékosban helyben
# fut le. A HUD sosem nyúl közvetlenül a világhoz.
func _send(kind: String, args: Array) -> void:
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("send_cmd"): main.send_cmd(kind, args)

func _update_queue_label() -> void:
	if not is_instance_valid(_bld): return
	if not _bld.is_ready():
		queue_label.text = Lang.t("epul") % int(_bld.prog * 100.0)
	elif _bld.train_queue.is_empty():
		queue_label.text = Lang.t("sor_ures")
	else:
		queue_label.text = Lang.t("sor_db") % [
			_bld.train_queue.size(), _bld.prod_tmr.time_left]

func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for k in cost:
		parts.append("%s %d" % [Lang.t(str(RES_KEY.get(k, k))), int(cost[k])])
	return ", ".join(parts)

# --- Játék vége ---

func show_game_over(won: bool) -> void:
	over_overlay.visible = true
	over_label.text = Lang.t("gyozelem") if won else Lang.t("vereseg")
	over_brief.visible = false
	over_next_btn.visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

# --- Hadjárat ---

func show_mission(m: Dictionary, objective: String) -> void:
	mission_panel.visible = true
	mission_title.text = "%d. %s" % [Campaign.index + 1, Campaign.name_of(m)]
	objective_lbl.text = objective
	show_toast(Campaign.brief_of(m), 9.0)

# Oktatómód: ugyanaz a panel, csak a cím és a lépés jön kívülről.
func show_tutorial(cim: String, szoveg: String) -> void:
	mission_panel.visible = true
	mission_title.text = cim
	objective_lbl.text = szoveg

func update_objective(text: String) -> void:
	if mission_panel.visible:
		objective_lbl.text = text

func show_mission_complete(has_next: bool) -> void:
	over_overlay.visible = true
	over_label.text = Lang.t("kuldetes_teljesitve")
	over_brief.visible = true
	over_brief.text = Lang.t("hadjarat_vege") if not has_next \
		else "%s: %s" % [Lang.t("kovetkezo_kuldetes"),
			Campaign.name_of(Campaign.mission(Campaign.nation, Campaign.index + 1))]
	over_next_btn.visible = has_next
	over_next_btn.text = Lang.t("kovetkezo_kuldetes")
	mouse_filter = Control.MOUSE_FILTER_STOP

func _on_next_mission() -> void:
	if not Campaign.advance(): return
	GameState.new_game(GameState.nation, GameState.start_age, GameState.pirate)
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_back_to_menu() -> void:
	GameState.on = false
	GameState.over = false
	Campaign.stop()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _has_worker(units: Array) -> bool:
	for u in units:
		if is_instance_valid(u) and "role" in u and u.role == "worker":
			return true
	return false

func set_paused(paused: bool) -> void:
	pause_overlay.visible = paused

func _on_move_pressed() -> void:
	SFX.play("click")

func _on_attack_pressed() -> void:
	for u in _selected:
		if not is_instance_valid(u): continue
		var e := Combat.find_enemy(u, 900.0)
		if e != null and u.has_method("start_attacking"):
			u.start_attacking(e)
	SFX.play("click")

func _on_stop_pressed() -> void:
	for u in _selected:
		if is_instance_valid(u) and u.has_method("stop"):
			u.stop()
	SFX.play("click")
