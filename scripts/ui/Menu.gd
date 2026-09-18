extends Control

# A főmenü. A nemzetek listája a Style.NATION_ORDER — pontosan azok,
# amelyekhez zászló- és uralkodókép is van az assets mappában.

var chosen_era    : int    = 0
var chosen_nation : String = "hu"
var chosen_diff   : int    = 0
var pirate_mode   : bool   = false
# 0 = helyi csata, 1 = kalózok, 2 = hadjárat
var mode          : int    = 0

@onready var era_btns   := %EraButtons    as GridContainer
@onready var era_section := %EraSection   as Control
@onready var mode_btns  := %ModeButtons   as HBoxContainer
@onready var mode_desc  := %ModeDesc      as Label
@onready var nat_btns   := %NationButtons as Container
@onready var diff_btns  := %DiffButtons   as HBoxContainer
@onready var start_btn  := %StartButton   as Button
@onready var cont_btn   := %ContinueButton as Button
@onready var ruler_img  := %RulerImage    as TextureRect
@onready var ruler_name := %RulerName     as Label
@onready var era_desc   := %EraDesc        as Label

var _nat_buttons : Array[Button] = []
var _nat_flags   : Array[TextureRect] = []
var _lang_buttons : Array[Button] = []

# --- Képernyők ---
#
# A régi HTML változat menüje nem esett rögtön a játékbeállításba: elöl a
# főmenü állt (Egy játékos / Többjátékos / Teljesítmények / Beállítások /
# Oktatómód / Kilépés), és csak két lépéssel lejjebb jött a beállítás.
# Ugyanez a felépítés itt is: a .tscn-ben lévő nagy doboz az "Új játék"
# képernyő, a másik hármat kódból építjük a CenterContainerbe.
var _setup_box    : VBoxContainer = null
var _home_box     : VBoxContainer = null
var _single_box   : VBoxContainer = null
var _settings_box : VBoxContainer = null
var _home_note    : Label  = null
var _single_note  : Label  = null
var _home_title   : Label  = null
var _home_lead    : Label  = null
var _single_title : Label  = null
var _settings_title : Label = null
var _load_btn     : Button = null
var _screen       : String = "home"

func _ready() -> void:
	_build_screens()
	for i in era_btns.get_child_count():
		var idx := i
		(era_btns.get_child(i) as Button).pressed.connect(func() -> void: _sel_era(idx))
	for i in mode_btns.get_child_count():
		var m := i
		var b := mode_btns.get_child(i) as Button
		if not b.disabled:
			b.pressed.connect(func() -> void: _sel_mode(m))
	for i in diff_btns.get_child_count():
		var idx2 := i
		(diff_btns.get_child(i) as Button).pressed.connect(func() -> void: _sel_diff(idx2))
	start_btn.pressed.connect(_on_start)
	cont_btn.pressed.connect(_on_continue)
	# A mentés betöltése egy szinttel feljebb, az Egy játékos képernyőn van.
	cont_btn.visible = false
	_build_lang_tab()
	_apply_language()
	_sel_era(0)
	_sel_diff(0)
	# Fejlesztői indítás adott módban:  godot -- --menumode=2
	# Ilyenkor rögtön az Új játék képernyő nyílik meg.
	# A fejlesztői kapcsolók a kiadott játékban nem élnek: a Main.dev_args()
	# ott üres listát ad (lásd az ottani magyarázatot).
	var kezdo := 0
	var ugras := false
	for a in Main.dev_args():
		if a.begins_with("--menumode="):
			kezdo = int(a.substr(11))
			ugras = true
	_sel_mode(clampi(kezdo, 0, 2))
	var kep := "setup" if ugras else "home"
	# Fejlesztői ellenőrzés:  godot -- --menuscreen=settings
	for a in Main.dev_args():
		if a.begins_with("--menuscreen="): kep = a.substr(13)
		if a == "--langlist": _lang_list.visible = true
	show_screen(kep)

# --- A képernyők felépítése ---

func _build_screens() -> void:
	var center := $CenterContainer as CenterContainer
	_setup_box = center.get_node("VBoxContainer") as VBoxContainer
	# Alacsony ablakban az Új játék képernyő magasabb, mint a képernyő.
	# Ezért az egész menüt görgethetővé tesszük: ha elfér, középen áll, ha
	# nem, le lehet görgetni — semmi nem lóg ki a képből.
	remove_child(center)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	scroll.add_child(center)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_build_map_section()
	_home_box = _new_screen(center)
	# A CÍM az eredeti (index.html) menüjének mintájára: nagy, ritkított,
	# csupa nagybetűs felirat, amelynek a MÁSODIK FELE arany —
	#   <h1>Biro<em>dalom</em></h1>,  letter-spacing: 10px
	_home_title = _build_title(_home_box, Lang.t("cim"), 42)
	var lead := Label.new()
	lead.text = Lang.t("evszamok")
	lead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lead.add_theme_font_override("font", Style.spaced_font(2.0))
	lead.add_theme_font_size_override("font_size", 14)
	lead.add_theme_color_override("font_color", Style.DIM)
	_home_box.add_child(lead)
	_home_lead = lead
	_home_box.add_child(HSeparator.new())
	_mbtn(_home_box, "egyjatekos", func() -> void: show_screen("single"))
	_mbtn(_home_box, "tobbjatekos", func() -> void: show_screen("mp"))
	_mbtn(_home_box, "teljesitmenyek", func() -> void: show_screen("ach"))
	_mbtn(_home_box, "beallitasok", func() -> void: show_screen("settings"))
	_mbtn(_home_box, "oktatomod", _start_tutorial)
	_mbtn(_home_box, "kilepes", func() -> void: get_tree().quit())
	_home_note = _note(_home_box, Lang.t("halozat_nincs"))

	_single_box = _new_screen(center)
	_single_title = _title_of(_single_box, Lang.t("egyjatekos"), 26)
	_mbtn(_single_box, "uj_jatek", func() -> void: show_screen("setup"))
	_load_btn = _mbtn(_single_box, "korabbi_betoltes", _on_continue)
	# Visszajátszás — ahogy az eredeti Egy játékos paneljén is ott van.
	_mbtn(_single_box, "visszajatszas_nyit", func() -> void: show_screen("replay"))
	_single_note = _note(_single_box, "")
	_single_box.add_child(HSeparator.new())
	_mbtn(_single_box, "vissza", func() -> void: show_screen("home"))

	# A beállítás-panel a saját címét hozza, ezért itt nincs külön fejléc.
	_settings_box = _new_screen(center)
	_settings_box.add_child(SettingsPanel.new())
	_mbtn(_settings_box, "vissza", func() -> void: show_screen("home"))

	_build_battle_screen(center)
	_build_replay_screen(center)
	_build_ach_screen(center)
	_build_mp_screen(center)
	_build_lobby_screen(center)
	Net.lobby_changed.connect(_refresh_lobby)
	Net.upnp_changed.connect(_refresh_lobby)
	Net.state_changed.connect(_on_net_state)
	Net.error_message.connect(_on_net_error)
	Net.match_starting.connect(_on_match_starting)

	# Az Új játék képernyő aljára is kell egy Vissza.
	var back := Button.new()
	back.name = "BackButton"
	back.custom_minimum_size = Vector2(300, 34)
	back.text = Lang.t("vissza")
	back.pressed.connect(func() -> void: show_screen("single"))
	_setup_box.add_child(back)

# --- Csata több féllel (a régi "szoba" képernyő) ---
#
# Helyben egy ember és legfeljebb öt bot fér el egy pályán. Az azonos
# csapatszámú felek szövetségesek; külön számmal mindenki mindenki ellen.
const MAX_SIDES := 6

var _battle_box   : VBoxContainer = null
var _battle_list  : VBoxContainer = null
var _battle_add   : Button = null
var _battle_sides : Array[Dictionary] = []
# A szoba a KALÓZVILÁGBAN is játszható (az eredeti szobaMod kapcsolója).
var battle_pirate : bool = false
var _battle_mode_row : HBoxContainer = null
var _battle_map      : OptionButton = null
var _battle_map_row  : HBoxContainer = null

# Világváltás a szobában: a nemzetek a másik világban nem léteznek, ezért
# mindenki új, érvényes nemzetet kap (ugyanígy csinálja az eredeti is).
func _sel_battle_world(pirate: bool) -> void:
	if battle_pirate == pirate: return
	battle_pirate = pirate
	var lista := Style.order_for(pirate)
	for i in _battle_sides.size():
		_battle_sides[i]["nemzet"] = str(lista[i % lista.size()])
	# A kalózvilág térképe rögzített (Karib-tenger), ott nincs tájválasztás.
	if _battle_map_row != null: _battle_map_row.visible = not pirate
	_refresh_battle_list()
	SFX.play("click")

func _build_battle_screen(center: CenterContainer) -> void:
	_battle_box = _new_screen(center)
	_battle_box.custom_minimum_size = Vector2(560, 0)
	_battle_title = _title_of(_battle_box, Lang.t("csata_tobb_fel"), 26)
	_battle_help = _note(_battle_box, Lang.t("csata_sugo"))
	# VILÁG: birodalmak vagy kalózok. Az eredetiben ez a szoba tetején álló
	# kapcsoló (szobaMod) — a kalózvilág nem csak egyjátékosban játszható.
	_battle_mode_row = _pick_row(_battle_box, "szoba_vilag",
		["mod_csata", "mod_kaloz"],
		func(i: int) -> void: _sel_battle_world(i == 1),
		func() -> int: return 1 if battle_pirate else 0)
	_battle_list = VBoxContainer.new()
	_battle_list.add_theme_constant_override("separation", 4)
	_battle_box.add_child(_battle_list)
	_battle_add = _mbtn(_battle_box, "bot_hozzaad", _add_bot)
	_battle_box.add_child(HSeparator.new())
	_battle_diff_row = _pick_row(_battle_box, "nehezseg",
		["konnyu", "kozepes", "nehez"],
		func(i: int) -> void: _sel_diff(i), func() -> int: return chosen_diff)
	_battle_era_row = _pick_row(_battle_box, "valassz_korszakot",
		["kor_nev_0", "kor_nev_1", "kor_nev_2", "kor_nev_3"],
		func(i: int) -> void: _sel_era(i), func() -> int: return chosen_era)
	# TÁJ — ahogy az eredeti szobájában is választható (szobaMap).
	var taj_sor := HBoxContainer.new()
	taj_sor.add_theme_constant_override("separation", 10)
	var tl := Label.new()
	tl.text = Lang.t("valassz_tajat")
	tl.custom_minimum_size = Vector2(150, 0)
	taj_sor.add_child(tl)
	_battle_map = OptionButton.new()
	_battle_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in WorldGen.choosable():
		_battle_map.add_item(Lang.t("taj_%s" % str(key)))
	_battle_map.item_selected.connect(func(i: int) -> void:
		var lista := WorldGen.choosable()
		_sel_map(str(lista[clampi(i, 0, lista.size() - 1)])))
	taj_sor.add_child(_battle_map)
	_battle_box.add_child(taj_sor)
	_battle_map_row = taj_sor
	_battle_box.add_child(HSeparator.new())
	_mbtn(_battle_box, "kezdes", _on_battle_start)
	_mbtn(_battle_box, "vissza", func() -> void: show_screen("home"))
	_reset_battle_sides()

var _battle_title : Label = null
var _battle_help  : Label = null
var _battle_diff_row : HBoxContainer = null
var _battle_era_row  : HBoxContainer = null

# Feliratos gombsor: a kiválasztott elem aranykeretet kap.
func _pick_row(box: VBoxContainer, cim: String, keys: Array,
		on_pick: Callable, get_idx: Callable) -> HBoxContainer:
	var l := Label.new()
	l.text = Lang.t(cim)
	box.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	for i in keys.size():
		var idx := i
		var b := Button.new()
		b.text = Lang.t(str(keys[i]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 30)
		b.pressed.connect(func() -> void:
			on_pick.call(idx)
			_mark_row(row, get_idx.call()))
		row.add_child(b)
	_mark_row(row, get_idx.call())
	return row

func _mark_row(row: HBoxContainer, idx: int) -> void:
	for i in row.get_child_count():
		_mark(row.get_child(i) as Button, i == idx)

func _reset_battle_sides() -> void:
	var lista := Style.order_for(battle_pirate)
	_battle_sides = [
		{"tipus": "ember", "nemzet": str(lista[0]), "csapat": 0},
		{"tipus": "bot",   "nemzet": str(lista[1 % lista.size()]), "csapat": 1},
	]
	_refresh_battle_list()

func _add_bot() -> void:
	if _battle_sides.size() >= MAX_SIDES: return
	var used: Array = []
	for d in _battle_sides: used.append(str(d["nemzet"]))
	var free := "de"
	for k in Style.order_for(battle_pirate):
		if not (str(k) in used):
			free = str(k)
			break
	_battle_sides.append({"tipus": "bot", "nemzet": free,
		"csapat": _battle_sides.size()})
	_refresh_battle_list()

func _refresh_battle_list() -> void:
	if _battle_list == null: return
	for c in _battle_list.get_children():
		_battle_list.remove_child(c)
		c.queue_free()
	var lista := Style.order_for(battle_pirate)
	for i in _battle_sides.size():
		var idx := i
		var d: Dictionary = _battle_sides[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var who := Label.new()
		who.text = Lang.t("te") if idx == 0 else "%s %d" % [Lang.t("bot"), idx]
		who.custom_minimum_size = Vector2(84, 0)
		row.add_child(who)
		# Nemzet: körbeforgó választó
		var nb := Button.new()
		nb.text = Style.nation_name(str(d["nemzet"]))
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.custom_minimum_size = Vector2(0, 30)
		nb.pressed.connect(func() -> void:
			var j := lista.find(str(_battle_sides[idx]["nemzet"]))
			_battle_sides[idx]["nemzet"] = str(lista[(j + 1) % lista.size()])
			_refresh_battle_list()
			SFX.play("click"))
		row.add_child(nb)
		# Csapat: az azonos számú felek szövetségesek
		var tb := Button.new()
		tb.text = "%s %d" % [Lang.t("csapat"), int(d["csapat"]) + 1]
		tb.custom_minimum_size = Vector2(96, 30)
		tb.pressed.connect(func() -> void:
			_battle_sides[idx]["csapat"] = (int(_battle_sides[idx]["csapat"]) + 1) % MAX_SIDES
			_refresh_battle_list()
			SFX.play("click"))
		row.add_child(tb)
		# A botok kivehetők, a játékos nem
		var xb := Button.new()
		xb.text = "X"
		xb.custom_minimum_size = Vector2(32, 30)
		xb.disabled = idx == 0 or _battle_sides.size() <= 2
		xb.pressed.connect(func() -> void:
			_battle_sides.remove_at(idx)
			_refresh_battle_list()
			SFX.play("click"))
		row.add_child(xb)
		_battle_list.add_child(row)
	if _battle_add != null:
		_battle_add.disabled = _battle_sides.size() >= MAX_SIDES

func _on_battle_start() -> void:
	Campaign.stop()
	GameState.new_battle(_battle_sides, chosen_era, battle_pirate, 0, 0, chosen_map)
	GameState.diff = chosen_diff
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

# --- VISSZAJÁTSZÁS ---
#
# Az egyjátékos játszmákról felvétel készül (scripts/systems/Replay.gd);
# ez a képernyő listázza őket, és visszanézhetővé teszi. A listában a
# felvétel dátuma, a táj/világ és a hossza áll.
const ReplayScript = preload("res://scripts/systems/Replay.gd")

var _replay_box  : VBoxContainer = null
var _replay_list : VBoxContainer = null
var _replay_title: Label = null
var _replay_note : Label = null

func _build_replay_screen(center: CenterContainer) -> void:
	_replay_box = _new_screen(center)
	_replay_box.custom_minimum_size = Vector2(560, 0)
	_replay_title = _title_of(_replay_box, Lang.t("visszajatszas_nyit"), 26)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_replay_list = VBoxContainer.new()
	_replay_list.add_theme_constant_override("separation", 6)
	_replay_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_replay_list)
	_replay_box.add_child(scroll)
	_replay_note = _note(_replay_box, "")
	_replay_box.add_child(HSeparator.new())
	_mbtn(_replay_box, "vissza", func() -> void: show_screen("single"))

func _refresh_replay_list() -> void:
	if _replay_list == null: return
	for c in _replay_list.get_children():
		_replay_list.remove_child(c)
		c.queue_free()
	var fajlok := ReplayScript.list_files()
	_replay_note.text = "" if not fajlok.is_empty() else Lang.t("nincs_visszajatszas")
	for path in fajlok:
		var m: Dictionary = ReplayScript.peek(str(path))
		if m.is_empty(): continue
		var vilag := Lang.t("mod_kaloz") if bool(m.get("kaloz", false)) \
			else Lang.t("taj_%s" % str(m.get("taj", "mezo")))
		var felek := int((m.get("oldalak", []) as Array).size())
		var b := Button.new()
		b.text = "%s   ·   %s   ·   %d %s" % [str(m.get("datum", "?")), vilag,
			felek, Lang.t("fel")]
		b.custom_minimum_size = Vector2(0, 34)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			SFX.play("click")
			_start_replay(str(path), m))
		_replay_list.add_child(b)

# A felvétel visszanézése: a világ ugyanabból a magból készül, a bábukat
# viszont a felvett pillanatképek rakják ki (mint a hálózati társnál).
func _start_replay(path: String, m: Dictionary) -> void:
	Campaign.stop()
	var sides: Array = m.get("oldalak", [])
	if sides.is_empty():
		sides = [{"tipus": "ember", "nemzet": "hu", "csapat": 0},
			{"tipus": "bot", "nemzet": "de", "csapat": 1}]
	GameState.new_battle(sides, int(m.get("kor", 0)), bool(m.get("kaloz", false)),
		int(m.get("en_id", 0)), int(m.get("mag", 0)), str(m.get("taj", "mezo")))
	GameState.diff = int(m.get("diff", 1))
	GameState.net_client = true          # semmit nem szimulálunk helyben
	GameState.replay_path = path
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

# --- Többjátékos: helyi csata vagy hálózat ---

var _mp_box    : VBoxContainer = null
var _mp_title  : Label = null
var _mp_code   : LineEdit = null
var _mp_note   : Label = null
var _mp_note2  : Label = null
var _name_edit : LineEdit = null
var _relay_edit: LineEdit = null
var _host_port : SpinBox = null
var _join_port : SpinBox = null
var _mp_sections : Array = []       # [felirat, nyelvi kulcs] párok

# A TÖBBJÁTÉKOS KÉPERNYŐ — a Heptarchia lobbijának felépítésével:
# legfelül a név, alatta keretezett szakaszokban a két (nálunk három) út:
# szoba nyitása kapuval, csatlakozás címmel és kapuval, végül a közvetítő.
func _build_mp_screen(center: CenterContainer) -> void:
	_mp_box = _new_screen(center)
	_mp_box.custom_minimum_size = Vector2(540, 0)
	_mp_title = _title_of(_mp_box, Lang.t("tobbjatekos"), 26)

	# Név, amivel a lobbiban látszol.
	var nev_sor := HBoxContainer.new()
	nev_sor.add_theme_constant_override("separation", 10)
	var nl := Label.new()
	nl.text = Lang.t("jatekos_nev")
	nl.custom_minimum_size = Vector2(120, 0)
	nev_sor.add_child(nl)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = 18
	_name_edit.text = Settings.player_name if Settings.player_name != "" else Lang.t("jatekos")
	_name_edit.text_changed.connect(func(t: String) -> void: Settings.set_player_name(t))
	nev_sor.add_child(_name_edit)
	_mp_box.add_child(nev_sor)

	# --- HELYI (hálózat nélkül) ---
	var helyi := _mp_section("net_helyi_cim", "net_helyi_leiras")
	_mbtn(helyi, "helyi_csata", func() -> void: show_screen("battle"))

	# --- SZOBA NYITÁSA (házigazda) ---
	var gazda := _mp_section("net_gazda_cim", "net_gazda_leiras")
	var gazda_sor := HBoxContainer.new()
	gazda_sor.add_theme_constant_override("separation", 10)
	var pl := Label.new()
	pl.text = Lang.t("net_kapu")
	pl.custom_minimum_size = Vector2(120, 0)
	gazda_sor.add_child(pl)
	_host_port = _port_box(gazda_sor, Settings.net_port)
	gazda.add_child(gazda_sor)
	_mbtn(gazda, "szoba_nyitas", func() -> void:
		Settings.set_net_port(int(_host_port.value))
		if Net.host_game(_name_edit.text, int(_host_port.value)):
			show_screen("lobby"))

	# --- CSATLAKOZÁS (cím + kapu) ---
	var vendeg := _mp_section("net_vendeg_cim", "net_vendeg_leiras")
	var cim_sor := HBoxContainer.new()
	cim_sor.add_theme_constant_override("separation", 10)
	var kl := Label.new()
	kl.text = Lang.t("net_hazigazda_cime")
	kl.custom_minimum_size = Vector2(120, 0)
	cim_sor.add_child(kl)
	_mp_code = LineEdit.new()
	_mp_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Elfér benne egy teljes cím ("192.168.0.12") és a közvetítős,
	# tízbetűs szobakód is ("R6AAA-AJGAA").
	_mp_code.max_length = 40
	_mp_code.placeholder_text = "192.168.0.12"
	_mp_code.text = Settings.last_address
	_mp_code.text_changed.connect(func(t: String) -> void: Settings.set_last_address(t))
	cim_sor.add_child(_mp_code)
	_join_port = _port_box(cim_sor, Settings.net_port)
	vendeg.add_child(cim_sor)
	# A csatlakozás magától eldönti, mit kapott: címet, közvetlen kódot vagy
	# közvetítős kódot (abban a szoba sorszáma is benne van).
	_mbtn(vendeg, "csatlakozas", func() -> void:
		Settings.set_net_port(int(_join_port.value))
		var szoveg := _mp_code.text.strip_edges()
		var cim := Net.parse_code(szoveg)
		if cim.size() >= 3:
			if Net.join_via_relay("%s:%d" % [cim[0], cim[1]], int(cim[2]),
					_name_edit.text):
				show_screen("lobby")
			return
		if cim.is_empty() and not szoveg.contains(":") and szoveg != "":
			# Sima cím kapu nélkül: a mellette álló kaput használjuk.
			szoveg = "%s:%d" % [szoveg, int(_join_port.value)]
		if Net.join_game(szoveg, _name_edit.text):
			show_screen("lobby"))
	_mp_note = _note(vendeg, Lang.t("net_sugo"))

	# --- KÖZVETÍTŐN ÁT (senkinek nem kell kaput nyitnia) ---
	var relay := _mp_section("net_relay_szakasz", "net_relay_sugo")
	var relay_sor := HBoxContainer.new()
	relay_sor.add_theme_constant_override("separation", 10)
	var rl := Label.new()
	rl.text = Lang.t("net_relay_cim")
	rl.custom_minimum_size = Vector2(120, 0)
	relay_sor.add_child(rl)
	_relay_edit = LineEdit.new()
	_relay_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_relay_edit.max_length = 40
	_relay_edit.placeholder_text = "kozvetito.gep.hu:27020"
	_relay_edit.text = Settings.relay_address
	_relay_edit.text_changed.connect(func(t: String) -> void:
		Settings.set_relay_address(t))
	relay_sor.add_child(_relay_edit)
	relay.add_child(relay_sor)
	_mbtn(relay, "szoba_nyitas_relay", func() -> void:
		if Net.host_via_relay(_relay_edit.text, _name_edit.text):
			show_screen("lobby"))

	_mp_note2 = _note(_mp_box, "")
	_mp_note2.add_theme_color_override("font_color", Style.GOLD)
	_mp_box.add_child(HSeparator.new())
	_mbtn(_mp_box, "vissza", func() -> void: show_screen("home"))

# Egy keretezett szakasz címmel és rövid magyarázattal (netDoboz / MP_*_HEADER).
func _mp_section(cim_kulcs: String, leiras_kulcs: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	_mp_box.add_child(panel)
	var c := Label.new()
	c.text = Lang.t(cim_kulcs)
	c.add_theme_color_override("font_color", Style.GOLD)
	c.add_theme_font_override("font", Style.spaced_font(2.0))
	box.add_child(c)
	_mp_sections.append([c, cim_kulcs])
	if leiras_kulcs != "":
		var l := _note(box, Lang.t(leiras_kulcs))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_mp_sections.append([l, leiras_kulcs])
	return box

func _port_box(parent: Control, ertek: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 1024
	s.max_value = 65535
	s.step = 1
	s.value = ertek if ertek >= 1024 else Net.PORT_BASE
	s.custom_minimum_size = Vector2(110, 0)
	parent.add_child(s)
	return s

# --- Lobbi ---

var _lobby_box   : VBoxContainer = null
var _lobby_title : Label = null
var _lobby_code  : Label = null
var _lobby_list  : VBoxContainer = null
var _lobby_note  : Label = null
var _lobby_lan   : Label = null
var _lobby_net   : Label = null
var _lobby_start : Button = null
var _lobby_ready : CheckButton = null
var _lobby_age_row : HBoxContainer = null
var _lobby_map     : OptionButton = null
var _lobby_map_row : HBoxContainer = null
var _lobby_mode_row : HBoxContainer = null

func _build_lobby_screen(center: CenterContainer) -> void:
	_lobby_box = _new_screen(center)
	_lobby_box.custom_minimum_size = Vector2(560, 0)
	_lobby_title = _title_of(_lobby_box, Lang.t("lobbi"), 26)
	_lobby_code = Label.new()
	_lobby_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_code.add_theme_font_size_override("font_size", 22)
	_lobby_box.add_child(_lobby_code)
	_lobby_lan = Label.new()
	_lobby_lan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_lan.add_theme_font_size_override("font_size", 14)
	_lobby_box.add_child(_lobby_lan)
	_lobby_net = _note(_lobby_box, "")
	_lobby_note = _note(_lobby_box, "")
	_lobby_list = VBoxContainer.new()
	_lobby_list.add_theme_constant_override("separation", 4)
	_lobby_box.add_child(_lobby_list)
	_lobby_box.add_child(HSeparator.new())
	# VILÁG: a hálózati szoba is indulhat a kalózvilágban (az eredeti
	# szobájában is ott a Birodalmak / Kalózok kapcsoló).
	_lobby_mode_row = _pick_row(_lobby_box, "szoba_vilag",
		["mod_csata", "mod_kaloz"],
		func(i: int) -> void:
			_sel_battle_world(i == 1)
			Net.set_match_setup(chosen_era, chosen_diff, battle_pirate, chosen_map),
		func() -> int: return 1 if battle_pirate else 0)
	_lobby_age_row = _pick_row(_lobby_box, "valassz_korszakot",
		["kor_nev_0", "kor_nev_1", "kor_nev_2", "kor_nev_3"],
		func(i: int) -> void:
			_sel_era(i)
			Net.set_match_setup(i, chosen_diff, battle_pirate, chosen_map),
		func() -> int: return chosen_era)
	# A TÁJ is a házigazdáé — mindenki ugyanazon a térképen játszik.
	var taj_sor := HBoxContainer.new()
	taj_sor.add_theme_constant_override("separation", 10)
	var tl := Label.new()
	tl.text = Lang.t("valassz_tajat")
	tl.custom_minimum_size = Vector2(150, 0)
	taj_sor.add_child(tl)
	_lobby_map = OptionButton.new()
	_lobby_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in WorldGen.choosable():
		_lobby_map.add_item(Lang.t("taj_%s" % str(key)))
	_lobby_map.item_selected.connect(func(i: int) -> void:
		var lista := WorldGen.choosable()
		_sel_map(str(lista[clampi(i, 0, lista.size() - 1)]))
		Net.set_match_setup(chosen_era, chosen_diff, battle_pirate, chosen_map))
	taj_sor.add_child(_lobby_map)
	_lobby_box.add_child(taj_sor)
	_lobby_map_row = taj_sor
	# KÉSZ-JELÖLÉS (Heptarchia-módra): a házigazda csak akkor indíthat, ha
	# mindenki bejelölte magát.
	_lobby_ready = CheckButton.new()
	_lobby_ready.text = Lang.t("net_kesz")
	_lobby_ready.toggled.connect(func(on: bool) -> void:
		Net.set_my_ready(on)
		SFX.play("click"))
	_lobby_box.add_child(_lobby_ready)
	_lobby_start = _mbtn(_lobby_box, "kezdes", func() -> void: Net.start_match())
	_mbtn(_lobby_box, "kilepes_szobabol", func() -> void:
		Net.close()
		show_screen("mp"))

func _refresh_lobby() -> void:
	if _lobby_box == null or not _lobby_box.visible: return
	# A HÁZIGAZDÁNÁL két kód van: az internetes (ezt kapja a külföldi
	# barát) és a helyi (ugyanaz a wifi). A csatlakozónál csak az van, amit
	# beírt.
	if Net.transport == "relay":
		# Közvetítőn át egyetlen kód van, és az mindenkinek ugyanaz.
		_lobby_code.text = "%s:  %s" % [Lang.t("net_kod_relay"),
			Net.pretty(Net.room_code)]
		_lobby_lan.visible = false
		_lobby_net.text = Lang.t("net_relay_sugo")
	elif Net.is_host():
		# A CÍM az első: ezt írja be a vendég. Mellette a gép ÖSSZES helyi
		# címe és a kapu (mint a Heptarchia lobbijában), másodsorban a
		# szobakód — aki inkább azt másolja át, annak is jó.
		if Net.public_code != "":
			_lobby_code.text = "%s:  %s" % [Lang.t("net_cim_internet"),
				Net.public_address()]
			_lobby_lan.text = "%s:  %s        %s:  %s / %s" % [
				Lang.t("net_cim_helyi"), _lan_list(),
				Lang.t("szobakod"), Net.pretty(Net.public_code),
				Net.pretty(Net.lan_code)]
			_lobby_lan.visible = true
		else:
			_lobby_code.text = "%s:  %s" % [Lang.t("net_cim_helyi"), _lan_list()]
			_lobby_lan.text = "%s:  %s" % [Lang.t("szobakod"),
				Net.pretty(Net.lan_code)]
			_lobby_lan.visible = true
		match Net.upnp_state:
			"keres": _lobby_net.text = Lang.t("net_upnp_keres")
			"kesz":  _lobby_net.text = Lang.t("net_upnp_kesz")
			"sikertelen": _lobby_net.text = Lang.t("net_upnp_nem") % Net.port
			_: _lobby_net.text = ""
	else:
		# A csatlakozónál az van kiírva, amit beírt: cím vagy szobakód.
		var cimmel: bool = Net.room_code.contains(":")
		_lobby_code.text = "%s:  %s" % [
			Lang.t("net_hazigazda_cime") if cimmel else Lang.t("szobakod"),
			Net.pretty_code()]
		_lobby_lan.visible = false
		_lobby_net.text = ""
	_lobby_note.text = Lang.t("net_hazigazda_indit") if not Net.is_host() \
		else Lang.t("net_te_vagy_hazigazda")
	_lobby_start.visible = Net.is_host()
	# Csak akkor indítható, ha MINDENKI kész (Heptarchia-módra).
	_lobby_start.disabled = not Net.all_ready()
	_lobby_start.tooltip_text = "" if Net.all_ready() else Lang.t("net_varj_keszre")
	_lobby_age_row.visible = Net.is_host()
	# A világ (birodalmak / kalózok) és a táj a házigazdáé; a többiek csak
	# látják, mit választott.
	if _lobby_mode_row != null:
		_lobby_mode_row.visible = Net.is_host()
		if not Net.is_host():
			battle_pirate = bool(Net.setup.get("pirate", false))
	var kaloz_e: bool = bool(Net.setup.get("pirate", battle_pirate))
	if _lobby_map_row != null:
		_lobby_map_row.visible = not kaloz_e
	if _lobby_map != null:
		var lista := WorldGen.choosable()
		var idx := lista.find(str(Net.setup.get("map", chosen_map)))
		if idx >= 0: _lobby_map.select(idx)
		_lobby_map.disabled = not Net.is_host()
	# A korszak a kalózvilágban rögzített (vitorlások kora).
	_lobby_age_row.visible = Net.is_host() and not kaloz_e
	var enyem_p: Dictionary = Net.players.get(Net.my_id, {})
	_lobby_ready.set_pressed_no_signal(bool(enyem_p.get("kesz", false)))
	_lobby_ready.disabled = enyem_p.is_empty()
	for c in _lobby_list.get_children():
		_lobby_list.remove_child(c)
		c.queue_free()
	var ids := Net.players.keys()
	ids.sort()
	var lista := Style.order_for(false)
	for i in ids.size():
		var id: int = ids[i]
		var p: Dictionary = Net.players[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var nev := Label.new()
		# Elöl a KÉSZ-jel (✓ / …), mint a Heptarchia lobbijában.
		nev.text = "%s  %s%s%s" % [
			"✓" if bool(p.get("kesz", false)) else "…",
			str(p.get("nev", "?")),
			"  ★" if bool(p.get("hazigazda", false)) else "",
			"  (%s)" % Lang.t("net_te") if id == Net.my_id else ""]
		nev.custom_minimum_size = Vector2(190, 0)
		if bool(p.get("kesz", false)):
			nev.add_theme_color_override("font_color", Style.OK)
		row.add_child(nev)
		var enyem := id == Net.my_id
		var nb := Button.new()
		nb.text = Style.nation_name(str(p.get("nemzet", "hu")))
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.custom_minimum_size = Vector2(0, 30)
		nb.disabled = not enyem
		nb.pressed.connect(func() -> void:
			var j := lista.find(str(Net.players[id]["nemzet"]))
			Net.set_my_setup(str(lista[(j + 1) % lista.size()]),
				int(Net.players[id]["csapat"]))
			SFX.play("click"))
		row.add_child(nb)
		var tb := Button.new()
		tb.text = "%s %d" % [Lang.t("csapat"), int(p.get("csapat", i)) + 1]
		tb.custom_minimum_size = Vector2(96, 30)
		tb.disabled = not enyem
		tb.pressed.connect(func() -> void:
			Net.set_my_setup(str(Net.players[id]["nemzet"]),
				(int(Net.players[id]["csapat"]) + 1) % Net.MAX_PLAYERS)
			SFX.play("click"))
		row.add_child(tb)
		_lobby_list.add_child(row)

func _on_net_state(state: String) -> void:
	if state == "lobbi" and _screen != "lobby": show_screen("lobby")
	_refresh_lobby()

func _on_net_error(text: String) -> void:
	# A hiba a többjátékos képernyő alján, kiemelve — a Heptarchia lobbijában
	# is ott, egy helyen jelenik meg minden hálózati üzenet.
	if _mp_note2 != null: _mp_note2.text = text
	show_screen("mp")

# A gép helyi címei egy sorban: ezeket diktálhatja be a házigazda.
func _lan_list() -> String:
	var cimek := Net.lan_addresses()
	if cimek.is_empty(): return Net.lan_address()
	var out: Array[String] = []
	for c in cimek: out.append("%s:%d" % [str(c), Net.port])
	return "  /  ".join(out)

# A házigazda elindította a játszmát: mindenki ugyanabból a magból és
# ugyanazzal az oldal-listával kezd.
func _on_match_starting(payload: Dictionary) -> void:
	Campaign.stop()
	var sides: Array = payload.get("sides", [])
	var me := Net.side_index_of(sides, Net.my_id)
	GameState.new_battle(sides, int(payload.get("age", 0)),
		bool(payload.get("pirate", false)), me, int(payload.get("seed", 0)),
		str(payload.get("map", "mezo")))
	GameState.diff = int(payload.get("diff", 1))
	GameState.net_client = Net.is_client()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

# --- Teljesítmények ---

var _ach_box  : VBoxContainer = null
var _ach_list : VBoxContainer = null
var _ach_head : Label = null

func _build_ach_screen(center: CenterContainer) -> void:
	_ach_box = _new_screen(center)
	_ach_box.custom_minimum_size = Vector2(560, 0)
	_ach_head = _title_of(_ach_box, Lang.t("teljesitmenyek"), 26)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ach_list = VBoxContainer.new()
	_ach_list.add_theme_constant_override("separation", 6)
	_ach_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_ach_list)
	_ach_box.add_child(scroll)
	_mbtn(_ach_box, "vissza", func() -> void: show_screen("home"))

func _refresh_ach_list() -> void:
	if _ach_list == null: return
	for c in _ach_list.get_children():
		_ach_list.remove_child(c)
		c.queue_free()
	_ach_head.text = "%s  %d / %d" % [Lang.t("teljesitmenyek"),
		Achievements.count_unlocked(), Achievements.DEFS.size()]
	for d in Achievements.DEFS:
		var id := str(d["id"])
		var kesz := Achievements.is_unlocked(id)
		var panel := PanelContainer.new()
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		panel.add_child(box)
		var t := Label.new()
		t.text = ("✔  " if kesz else "•  ") + Achievements.title_of(id)
		box.add_child(t)
		var desc := Label.new()
		desc.text = Achievements.desc_of(id)
		desc.add_theme_font_size_override("font_size", 12)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(desc)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 12)
		bar.max_value = Achievements.goal_of(id)
		bar.value = minf(Achievements.current_of(id), bar.max_value)
		bar.show_percentage = false
		box.add_child(bar)
		var num := Label.new()
		# A számláló nem megy a cél fölé: "3 / 1" zavaró lenne.
		num.text = "%d / %d" % [int(minf(Achievements.current_of(id),
			Achievements.goal_of(id))), int(Achievements.goal_of(id))]
		num.add_theme_font_size_override("font_size", 11)
		box.add_child(num)
		panel.modulate = Color.WHITE if kesz else Color(1, 1, 1, 0.55)
		_ach_list.add_child(panel)

# --- Oktatómód ---

func _start_tutorial() -> void:
	Campaign.stop()
	GameState.new_game("hu", 0, false)
	GameState.diff = 0
	GameState.tutorial = true
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _new_screen(center: CenterContainer) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.custom_minimum_size = Vector2(420, 0)
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_theme_constant_override("separation", 8)
	b.visible = false
	center.add_child(b)
	return b

# --- TÁJ (pályatípus) ---
#
# Az eredetiben az Új játék képernyőn a korszak alatt áll a „Táj” szakasz:
# kilenc választható tájtípus, mindegyik más erőforrás-eloszlással, vízzel
# és talajszínnel (a tizedik, a Karib-tenger, a kalózvilág rögzített
# térképe, ezért nem választható).
var _map_section : VBoxContainer = null
var _map_btns    : Array[Button] = []
var _map_desc    : Label = null
var _map_title   : Label = null
var chosen_map   : String = "mezo"

func _build_map_section() -> void:
	_map_section = VBoxContainer.new()
	_map_section.name = "MapSection"
	_map_section.add_theme_constant_override("separation", 4)
	_map_title = Label.new()
	_map_title.text = Lang.t("valassz_tajat")
	_map_section.add_child(_map_title)
	var racs := GridContainer.new()
	racs.columns = 5
	racs.add_theme_constant_override("h_separation", 6)
	racs.add_theme_constant_override("v_separation", 6)
	_map_section.add_child(racs)
	_map_btns.clear()
	for key in WorldGen.choosable():
		var k := str(key)
		var b := Button.new()
		b.name = "Map_" + k
		b.text = Lang.t("taj_%s" % k)
		b.custom_minimum_size = Vector2(120, 30)
		b.pressed.connect(func() -> void:
			SFX.play("click")
			_sel_map(k))
		racs.add_child(b)
		_map_btns.append(b)
	_map_desc = Label.new()
	_map_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_desc.add_theme_font_size_override("font_size", 12)
	_map_desc.modulate = Color(1, 1, 1, 0.7)
	_map_section.add_child(_map_desc)
	# A korszak alá kerül, a nemzetválasztó fölé — mint az eredetiben.
	_setup_box.add_child(_map_section)
	var era := _setup_box.get_node_or_null("EraSection")
	if era != null:
		_setup_box.move_child(_map_section, era.get_index() + 1)
	_sel_map(chosen_map)

func _sel_map(key: String) -> void:
	chosen_map = key
	var lista := WorldGen.choosable()
	for i in _map_btns.size():
		_mark(_map_btns[i], str(lista[i]) == key)
	if _map_desc != null:
		_map_desc.text = Lang.t("taj_%s_leiras" % key)

# A kétszínű főcím: az első fele tintaszín, a második arany — pontosan úgy,
# ahogy az eredeti menü <h1>Biro<em>dalom</em></h1> felirata. A betűk közti
# rés a HTML letter-spacing:10px megfelelője (FontVariation.spacing_glyph).
func _build_title(box: VBoxContainer, text: String, size: int) -> Label:
	var sor := HBoxContainer.new()
	sor.alignment = BoxContainer.ALIGNMENT_CENTER
	sor.add_theme_constant_override("separation", 0)
	box.add_child(sor)
	var t := text.to_upper()
	var vagas := int(ceil(float(t.length()) * 0.5))
	if t == "BIRODALOM": vagas = 4          # BIRO | DALOM
	var elso := Label.new()
	var masodik := Label.new()
	for l in [elso, masodik]:
		l.add_theme_font_override("font", Style.spaced_font(10.0))
		l.add_theme_font_size_override("font_size", size)
	elso.text = t.substr(0, vagas)
	masodik.text = t.substr(vagas)
	masodik.add_theme_color_override("font_color", Style.GOLD)
	sor.add_child(elso)
	sor.add_child(masodik)
	# A hívók egy Labelt várnak vissza (nyelvváltáskor ezt írják át).
	elso.set_meta("parja", masodik)
	elso.set_meta("cim_sor", sor)
	return elso

# Nyelvváltáskor a kétszínű cím mindkét felét újra kell osztani.
func _set_title(elso: Label, text: String) -> void:
	var masodik := elso.get_meta("parja", null) as Label
	var t := text.to_upper()
	if masodik == null:
		elso.text = t
		return
	var vagas := int(ceil(float(t.length()) * 0.5))
	if t == "BIRODALOM": vagas = 4
	elso.text = t.substr(0, vagas)
	masodik.text = t.substr(vagas)

func _title_of(box: VBoxContainer, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	box.add_child(l)
	return l

func _note(box: VBoxContainer, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.modulate = Color(1, 1, 1, 0.65)
	box.add_child(l)
	return l

# Menügomb. Üres Callable = még nem elkészült rész: a gomb látszik, de
# tiltott, hogy ne keltsen hamis várakozást.
func _mbtn(box: VBoxContainer, key: String, action: Callable,
		soon: bool = false) -> Button:
	var b := Button.new()
	b.name = "Btn_" + key
	b.text = Lang.t(key)
	b.custom_minimum_size = Vector2(300, 38)
	# Az eredeti menü gombjai ritkított, nagyobb betűvel írnak
	# (.mbtn { font-size:16px; letter-spacing:2px }).
	b.add_theme_font_override("font", Style.spaced_font(2.0))
	b.add_theme_font_size_override("font_size", 16)
	if soon:
		b.disabled = true
		b.tooltip_text = Lang.t("hamarosan")
	elif action.is_valid():
		b.pressed.connect(func() -> void:
			SFX.play("click")
			action.call())
	box.add_child(b)
	return b

func show_screen(name: String) -> void:
	_screen = name
	_home_box.visible     = name == "home"
	_single_box.visible   = name == "single"
	_settings_box.visible = name == "settings"
	_setup_box.visible    = name == "setup"
	_battle_box.visible   = name == "battle"
	_ach_box.visible      = name == "ach"
	_mp_box.visible       = name == "mp"
	_lobby_box.visible    = name == "lobby"
	if _replay_box != null: _replay_box.visible = name == "replay"
	if name == "replay":
		_refresh_replay_list()
	if name == "single":
		var van := SaveManager.has_save()
		_load_btn.disabled = not van
		_single_note.text = "" if van else Lang.t("nincs_mentes")
	elif name == "battle":
		_refresh_battle_list()
	elif name == "ach":
		_refresh_ach_list()
	elif name == "lobby":
		_refresh_lobby()

func screen() -> String:
	return _screen

# --- Nyelvválasztó fül (jobb felső sarok) ---
#
# A nyelvek az assets/lang/*.json fájlokból jönnek (Lang autoload). A
# választó nem foglal helyet a címlap közepén: egy kis fül ül a jobb felső
# sarokban, és kattintásra nyílik le a lista — mint a régi HTML változat
# `langBtn` gombja.
const LANG_TAB_W := 190.0

var _lang_tab  : Button = null
var _lang_list : PanelContainer = null

func _build_lang_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "LangTab"
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -(LANG_TAB_W + 16.0)
	box.offset_right = -16.0
	box.offset_top = 16.0
	box.add_theme_constant_override("separation", 2)
	add_child(box)

	_lang_tab = Button.new()
	_lang_tab.custom_minimum_size = Vector2(LANG_TAB_W, 34)
	_lang_tab.expand_icon = true
	_lang_tab.pressed.connect(_toggle_lang_list)
	box.add_child(_lang_tab)

	_lang_list = PanelContainer.new()
	_lang_list.visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_lang_list.add_child(col)
	_lang_buttons.clear()
	for code in Lang.codes():
		var k: String = code
		var b := Button.new()
		b.name = "Lang_" + k
		b.custom_minimum_size = Vector2(LANG_TAB_W - 16.0, 30)
		b.expand_icon = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# A 3. korszak lobogója a MAI zászló — nyelvválasztóhoz ez az
		# ismerős, nem a középkori hadilobogó.
		b.icon = Style.flag_texture(Lang.flag_of(k), 3)
		b.text = "  " + Lang.language_name(k)
		b.pressed.connect(func() -> void: _sel_lang(k))
		col.add_child(b)
		_lang_buttons.append(b)
	box.add_child(_lang_list)
	_update_lang_tab()

func _toggle_lang_list() -> void:
	_lang_list.visible = not _lang_list.visible
	SFX.play("click")

func _sel_lang(code: String) -> void:
	_lang_list.visible = false
	if code == Lang.code: return
	Lang.set_language(code)
	_apply_language()
	SFX.play("click")

# A fülön a jelenlegi nyelv zászlaja és neve áll, a végén a lenyíló jele.
func _update_lang_tab() -> void:
	if _lang_tab == null: return
	_lang_tab.icon = Style.flag_texture(Lang.flag_of(Lang.code), 3)
	_lang_tab.text = "  %s  ▾" % Lang.language_name(Lang.code)
	_lang_tab.tooltip_text = Lang.t("valassz_nyelvet")
	var codes := Lang.codes()
	for i in _lang_buttons.size():
		_mark(_lang_buttons[i], codes[i] == Lang.code)

# A jelenetben magyar alapszövegek állnak; a választott nyelvet innen
# írjuk rá minden feliratra.
func _apply_language() -> void:
	_update_lang_tab()
	start_btn.text = Lang.t("jatek_inditasa")
	cont_btn.text = Lang.t("mentes_betoltese")
	# Az Új játék képernyő feliratai (a doboz a görgethető keretben ül,
	# ezért nem abszolút útvonalon keressük őket).
	_set_label("TitleLabel", Lang.t("cim"))
	_set_label("ModeSection/Label", Lang.t("jatekmod"))
	_set_label("EraSection/Label", Lang.t("valassz_korszakot"))
	_set_label("NationSection/NationCol/Label", Lang.t("valassz_nemzetet"))
	_set_label("DiffSection/Label", Lang.t("nehezseg"))
	for i in era_btns.get_child_count():
		(era_btns.get_child(i) as Button).text = Lang.t("kor_nev_%d" % i)
	var mode_keys := ["mod_csata", "mod_kaloz", "mod_hadjarat"]
	for i in mini(mode_btns.get_child_count(), mode_keys.size()):
		(mode_btns.get_child(i) as Button).text = Lang.t(mode_keys[i])
	var diff_keys := ["konnyu", "kozepes", "nehez"]
	for i in mini(diff_btns.get_child_count(), diff_keys.size()):
		(diff_btns.get_child(i) as Button).text = Lang.t(diff_keys[i])
	_sel_era(chosen_era)
	mode_desc.text = Lang.t("mod_kaloz_leiras") if pirate_mode \
		else Lang.t("mod_csata_leiras")
	_apply_screen_language()

# A kódból épített képernyők feliratai. A gombok neve "Btn_<kulcs>",
# ezért nyelvváltáskor elég végigfutni rajtuk.
func _apply_screen_language() -> void:
	for box in [_home_box, _single_box, _settings_box, _setup_box,
			_battle_box, _ach_box, _mp_box, _lobby_box]:
		if box == null: continue
		# Mélyen is keresünk: a többjátékos képernyő gombjai keretezett
		# szakaszokban ülnek, nem közvetlenül a dobozban.
		_relabel_buttons(box)
	if _home_note != null: _home_note.text = Lang.t("halozat_nincs")
	if _battle_title != null: _battle_title.text = Lang.t("csata_tobb_fel")
	if _battle_help != null: _battle_help.text = Lang.t("csata_sugo")
	if _screen == "battle": _refresh_battle_list()
	if _screen == "ach": _refresh_ach_list()
	if _home_title != null: _set_title(_home_title, Lang.t("cim"))
	if _home_lead != null: _home_lead.text = Lang.t("evszamok")
	if _single_title != null: _single_title.text = Lang.t("egyjatekos")
	if _settings_title != null: _settings_title.text = Lang.t("beallitasok")
	# A beállítás-panel feliratait a felépítéskor kapja; nyelvváltáskor
	# egyszerűbb újraépíteni, mint minden sorát külön nyilvántartani.
	if _settings_box != null:
		for c in _settings_box.get_children():
			if c is SettingsPanel:
				_settings_box.remove_child(c)
				c.queue_free()
		var sp := SettingsPanel.new()
		_settings_box.add_child(sp)
		_settings_box.move_child(sp, 0)
	# A tájválasztó feliratai
	if _map_title != null: _map_title.text = Lang.t("valassz_tajat")
	if not _map_btns.is_empty():
		var tajak := WorldGen.choosable()
		for i in mini(_map_btns.size(), tajak.size()):
			_map_btns[i].text = Lang.t("taj_%s" % str(tajak[i]))
		_sel_map(chosen_map)
	if _lobby_map != null:
		var lista2 := WorldGen.choosable()
		for i in mini(_lobby_map.item_count, lista2.size()):
			_lobby_map.set_item_text(i, Lang.t("taj_%s" % str(lista2[i])))
	# A többjátékos szakaszcímek és a kész-jelölő felirata
	for par in _mp_sections:
		var c := par[0] as Label
		if is_instance_valid(c): c.text = Lang.t(str(par[1]))
	if _lobby_ready != null: _lobby_ready.text = Lang.t("net_kesz")
	if _screen == "single": show_screen("single")

# A "Btn_<kulcs>" nevű gombok feliratát mélységben frissíti.
func _relabel_buttons(node: Node) -> void:
	for c in node.get_children():
		if c is Button:
			var b := c as Button
			if b.name == "BackButton":
				b.text = Lang.t("vissza")
			elif str(b.name).begins_with("Btn_"):
				b.text = Lang.t(str(b.name).substr(4))
				if b.disabled: b.tooltip_text = Lang.t("hamarosan")
		if c.get_child_count() > 0:
			_relabel_buttons(c)

func _set_label(path: String, text: String) -> void:
	if _setup_box == null: return
	var n := _setup_box.get_node_or_null(path) as Label
	if n: n.text = text

# Játékmód-váltás: a kalózvilágban más a nemzetlista, és nincs korszak.
func _sel_mode(m: int) -> void:
	mode = m
	pirate_mode = m == 1
	for i in mode_btns.get_child_count():
		var b := mode_btns.get_child(i) as Button
		if not b.disabled:
			_mark(b, i == m)
	mode_desc.text = [Lang.t("mod_csata_leiras"), Lang.t("mod_kaloz_leiras"),
		Lang.t("mod_hadjarat_leiras")][clampi(m, 0, 2)]
	# A hadjáratban a korszakot a küldetés adja meg.
	era_section.visible = m == 0
	# A TÁJ csak a szabad csatában választható: a kalózvilág mindig a
	# Karib-tengeren játszik, a hadjárat küldetése pedig maga mondja meg.
	if _map_section != null: _map_section.visible = m == 0
	_build_nation_buttons()
	var lista := _order()
	_sel_nation(lista[0] if not lista.is_empty() else "hu")
	SFX.play("click")

func _order() -> Array:
	# Hadjáratban csak azok a nemzetek, amelyekhez van küldetéssorozat.
	if mode == 2:
		return Campaign.campaigns()
	return Style.order_for(pirate_mode)

# A hadjárat bejegyzése lehet "kaloz_ns" is — a zászló és a név viszont
# a mögötte álló nemzeté.
func _key_of(entry: String) -> String:
	return Campaign.nation_key(entry) if mode == 2 else entry

# A nemzetgombok fölé kerül a korszakhoz tartozó zászló. A Button.icon
# nem jó erre: a szöveg mellett összemegy, és a 176x121-es zászlóból
# néhány pixel marad. Ezért külön TextureRect áll a gomb fölött.
func _build_nation_buttons() -> void:
	for c in nat_btns.get_children():
		nat_btns.remove_child(c)
		c.queue_free()
	_nat_buttons.clear()
	_nat_flags.clear()
	for key in _order():
		var k: String = key
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 2)
		var flag := TextureRect.new()
		flag.custom_minimum_size = Vector2(0, 34)
		flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(flag)
		var btn := Button.new()
		btn.name = "Btn" + k.to_upper()
		btn.text = Style.nation_name(_key_of(k))
		if mode == 2:
			# Hadjáratnál a gomb mutatja, hol tartasz.
			btn.text += "  %d/%d" % [Campaign.done(k), Campaign.count(k)]
		btn.custom_minimum_size = Vector2(0, 30)
		btn.pressed.connect(func() -> void: _sel_nation(k))
		box.add_child(btn)
		nat_btns.add_child(box)
		_nat_buttons.append(btn)
		_nat_flags.append(flag)

# A kiválasztott gomb aranykeretet kap. (A `flat` kapcsoló helyett: az
# lapos gombokat sima szöveggé alakítja, és nem látszik, hogy gombok.)
func _mark(btn: Button, on: bool) -> void:
	if on:
		btn.add_theme_stylebox_override("normal",
			Style.button_box(Style.HOVER, Style.GOLD))
		btn.add_theme_color_override("font_color", Color.WHITE)
	else:
		btn.remove_theme_stylebox_override("normal")
		btn.remove_theme_color_override("font_color")

func _sel_era(idx: int) -> void:
	chosen_era = idx
	for i in era_btns.get_child_count():
		_mark(era_btns.get_child(i) as Button, i == idx)
	era_desc.text = "%s — %s" % [Lang.t("kor_nev_%d" % idx),
		Lang.t("kor_alcim_%d" % idx)]
	_refresh_nation_art()

func _sel_nation(n: String) -> void:
	chosen_nation = n
	var ord := _order()
	for i in _nat_buttons.size():
		_mark(_nat_buttons[i], ord[i] == n)
	_refresh_nation_art()
	SFX.play("click")

# A választott nemzet/korszak zászlaja a gombokon, uralkodója a képen.
func _refresh_nation_art() -> void:
	var ord := _order()
	var key := _key_of(chosen_nation)
	# A kalózfrakciók nem lépnek korszakot: mindig az első lapjuk kell.
	var art_era := chosen_era
	if pirate_mode or Style.is_pirate(key): art_era = 0
	if mode == 2:
		# Hadjáratban a küldetés korszaka határozza meg a lobogót.
		art_era = int(Campaign.mission(chosen_nation,
			Campaign.next_index(chosen_nation)).get("age", 0))
	for i in _nat_flags.size():
		var k2 := _key_of(str(ord[i]))
		var e2 := art_era if mode != 2 else int(Campaign.mission(str(ord[i]),
			Campaign.next_index(str(ord[i]))).get("age", 0))
		if Style.is_pirate(k2): e2 = 0
		_nat_flags[i].texture = Style.flag_texture(k2, e2)
		_nat_flags[i].modulate = Color.WHITE if ord[i] == chosen_nation \
			else Color(1, 1, 1, 0.45)
	var nat: Dictionary = Style.nation(key)
	var rp := Style.ruler_path(key, art_era)
	ruler_img.texture = load(rp) if ResourceLoader.exists(rp) else null
	if mode == 2:
		_show_briefing()
		return
	var rulers: Array = nat.get("rulers", [])
	var titles: Array = nat.get("titles", [])
	var eras: Array   = nat.get("eras", [])
	var i2 := clampi(art_era, 0, 3)
	if i2 < rulers.size():
		ruler_name.text = "%s\n%s %s" % [str(eras[i2]), str(rulers[i2]),
			Style.title_name(str(titles[i2]))]
	else:
		ruler_name.text = Style.nation_name(key)

# Hadjáratban az uralkodó szövege helyén a soron következő küldetés
# eligazítása áll: sorszám, cím, történet és a cél.
func _show_briefing() -> void:
	var i := Campaign.next_index(chosen_nation)
	var m := Campaign.mission(chosen_nation, i)
	if m.is_empty():
		ruler_name.text = ""
		return
	ruler_name.text = "%d/%d — %s\n\n%s\n\n%s: %s" % [
		i + 1, Campaign.count(chosen_nation), Campaign.name_of(m),
		Campaign.brief_of(m), Lang.t("cel"), Campaign.objective_text(m)]

func _sel_diff(idx: int) -> void:
	chosen_diff = idx
	for i in diff_btns.get_child_count():
		_mark(diff_btns.get_child(i) as Button, i == idx)
	SFX.play("click")

func _on_start() -> void:
	if mode == 2:
		# Hadjárat: a küldetés adja a korszakot, az ellenfelet és a
		# kezdőkészletet — a nemzet a hadjárat mögötti frakció.
		var key := Campaign.nation_key(chosen_nation)
		Campaign.start(chosen_nation, Campaign.next_index(chosen_nation))
		GameState.new_game(key, chosen_era, Style.is_pirate(key), chosen_map)
	else:
		Campaign.stop()
		GameState.new_game(chosen_nation, chosen_era, pirate_mode, chosen_map)
	GameState.diff = chosen_diff
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_continue() -> void:
	if not SaveManager.load_game(): return
	GameState.on = true
	GameState.over = false
	GameState.winner = -1
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
