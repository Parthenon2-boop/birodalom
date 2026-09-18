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

	_home_box = _new_screen(center)
	_home_title = _title_of(_home_box, Lang.t("cim"), 42)
	var lead := Label.new()
	lead.text = Lang.t("evszamok")
	lead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	_single_note = _note(_single_box, "")
	_single_box.add_child(HSeparator.new())
	_mbtn(_single_box, "vissza", func() -> void: show_screen("home"))

	# A beállítás-panel a saját címét hozza, ezért itt nincs külön fejléc.
	_settings_box = _new_screen(center)
	_settings_box.add_child(SettingsPanel.new())
	_mbtn(_settings_box, "vissza", func() -> void: show_screen("home"))

	_build_battle_screen(center)
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

func _build_battle_screen(center: CenterContainer) -> void:
	_battle_box = _new_screen(center)
	_battle_box.custom_minimum_size = Vector2(560, 0)
	_battle_title = _title_of(_battle_box, Lang.t("csata_tobb_fel"), 26)
	_battle_help = _note(_battle_box, Lang.t("csata_sugo"))
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
	_battle_sides = [
		{"tipus": "ember", "nemzet": "hu", "csapat": 0},
		{"tipus": "bot",   "nemzet": "de", "csapat": 1},
	]
	_refresh_battle_list()

func _add_bot() -> void:
	if _battle_sides.size() >= MAX_SIDES: return
	var used: Array = []
	for d in _battle_sides: used.append(str(d["nemzet"]))
	var free := "de"
	for k in Style.order_for(false):
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
	var lista := Style.order_for(false)
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
	GameState.new_battle(_battle_sides, chosen_era, false)
	GameState.diff = chosen_diff
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

# --- Többjátékos: helyi csata vagy hálózat ---

var _mp_box    : VBoxContainer = null
var _mp_title  : Label = null
var _mp_code   : LineEdit = null
var _mp_note   : Label = null
var _mp_note2  : Label = null
var _name_edit : LineEdit = null
var _relay_edit: LineEdit = null

func _build_mp_screen(center: CenterContainer) -> void:
	_mp_box = _new_screen(center)
	_mp_box.custom_minimum_size = Vector2(480, 0)
	_mp_title = _title_of(_mp_box, Lang.t("tobbjatekos"), 26)
	_mbtn(_mp_box, "helyi_csata", func() -> void: show_screen("battle"))
	_mp_box.add_child(HSeparator.new())
	# Név, amivel a lobbiban látszol.
	var nev_sor := HBoxContainer.new()
	var nl := Label.new()
	nl.text = Lang.t("jatekos_nev")
	nl.custom_minimum_size = Vector2(110, 0)
	nev_sor.add_child(nl)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = 18
	_name_edit.text = Lang.t("jatekos")
	nev_sor.add_child(_name_edit)
	_mp_box.add_child(nev_sor)
	# --- Közvetítőn át: bárki, bárhonnan ---
	_mp_box.add_child(HSeparator.new())
	var relay_sor := HBoxContainer.new()
	var rl := Label.new()
	rl.text = Lang.t("net_relay_cim")
	rl.custom_minimum_size = Vector2(110, 0)
	relay_sor.add_child(rl)
	_relay_edit = LineEdit.new()
	_relay_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_relay_edit.max_length = 40
	_relay_edit.placeholder_text = "kozvetito.gep.hu:27020"
	_relay_edit.text = Settings.relay_address
	_relay_edit.text_changed.connect(func(t: String) -> void:
		Settings.set_relay_address(t))
	relay_sor.add_child(_relay_edit)
	_mp_box.add_child(relay_sor)
	_mbtn(_mp_box, "szoba_nyitas_relay", func() -> void:
		if Net.host_via_relay(_relay_edit.text, _name_edit.text):
			show_screen("lobby"))
	_mp_note2 = _note(_mp_box, Lang.t("net_relay_sugo"))
	_mp_box.add_child(HSeparator.new())
	_mbtn(_mp_box, "szoba_nyitas", func() -> void:
		if Net.host_game(_name_edit.text): show_screen("lobby"))
	# Csatlakozás a HÁZIGAZDA CÍMÉVEL (vagy szobakóddal).
	#
	# A mező elsősorban címet vár — ezt írja ki a házigazdának a lobbi, és ez
	# az az út, amit mindenki ismer: "cím:kapu". A szobakódot is elfogadja,
	# az ugyanezt a címet rejti betűkbe.
	var kod_sor := HBoxContainer.new()
	var kl := Label.new()
	kl.text = Lang.t("net_hazigazda_cime")
	kl.custom_minimum_size = Vector2(110, 0)
	kod_sor.add_child(kl)
	_mp_code = LineEdit.new()
	_mp_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Elfér benne egy teljes cím ("192.168.0.12:27015") és a közvetítős,
	# tízbetűs szobakód is ("R6AAA-AJGAA").
	_mp_code.max_length = 40
	_mp_code.placeholder_text = "192.168.0.12:27015   vagy   ABCD-EFGH"
	kod_sor.add_child(_mp_code)
	_mp_box.add_child(kod_sor)
	# A csatlakozás magától eldönti, közvetlen vagy közvetítős kódot kapott:
	# a tízbetűs kódban benne van a szoba sorszáma is.
	_mbtn(_mp_box, "csatlakozas", func() -> void:
		var cim := Net.parse_code(_mp_code.text)
		if cim.size() >= 3:
			if Net.join_via_relay("%s:%d" % [cim[0], cim[1]], int(cim[2]),
					_name_edit.text):
				show_screen("lobby")
		elif Net.join_game(_mp_code.text, _name_edit.text):
			show_screen("lobby"))
	_mp_note = _note(_mp_box, Lang.t("net_sugo"))
	_mp_box.add_child(HSeparator.new())
	_mbtn(_mp_box, "vissza", func() -> void: show_screen("home"))

# --- Lobbi ---

var _lobby_box   : VBoxContainer = null
var _lobby_title : Label = null
var _lobby_code  : Label = null
var _lobby_list  : VBoxContainer = null
var _lobby_note  : Label = null
var _lobby_lan   : Label = null
var _lobby_net   : Label = null
var _lobby_start : Button = null
var _lobby_age_row : HBoxContainer = null

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
	_lobby_age_row = _pick_row(_lobby_box, "valassz_korszakot",
		["kor_nev_0", "kor_nev_1", "kor_nev_2", "kor_nev_3"],
		func(i: int) -> void:
			_sel_era(i)
			Net.set_match_setup(i, chosen_diff, false),
		func() -> int: return chosen_era)
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
		# A CÍM az első: ezt írja be a vendég. A szobakód ugyanez betűkkel,
		# másodsorban — aki inkább azt másolja át, annak is jó.
		if Net.public_code != "":
			_lobby_code.text = "%s:  %s" % [Lang.t("net_cim_internet"),
				Net.public_address()]
			_lobby_lan.text = "%s:  %s        %s:  %s / %s" % [
				Lang.t("net_cim_helyi"), Net.lan_address(),
				Lang.t("szobakod"), Net.pretty(Net.public_code),
				Net.pretty(Net.lan_code)]
			_lobby_lan.visible = true
		else:
			_lobby_code.text = "%s:  %s" % [Lang.t("net_cim_helyi"),
				Net.lan_address()]
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
	_lobby_age_row.visible = Net.is_host()
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
		nev.text = "%d. %s%s" % [i + 1, str(p.get("nev", "?")),
			"  ★" if bool(p.get("hazigazda", false)) else ""]
		nev.custom_minimum_size = Vector2(180, 0)
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
	if _mp_note != null: _mp_note.text = text
	show_screen("mp")

# A házigazda elindította a játszmát: mindenki ugyanabból a magból és
# ugyanazzal az oldal-listával kezd.
func _on_match_starting(payload: Dictionary) -> void:
	Campaign.stop()
	var sides: Array = payload.get("sides", [])
	var me := Net.side_index_of(sides, Net.my_id)
	GameState.new_battle(sides, int(payload.get("age", 0)),
		bool(payload.get("pirate", false)), me, int(payload.get("seed", 0)))
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
		for c in box.get_children():
			if not (c is Button): continue
			var b := c as Button
			if b.name == "BackButton":
				b.text = Lang.t("vissza")
			elif str(b.name).begins_with("Btn_"):
				b.text = Lang.t(str(b.name).substr(4))
				if b.disabled: b.tooltip_text = Lang.t("hamarosan")
	if _home_note != null: _home_note.text = Lang.t("halozat_nincs")
	if _battle_title != null: _battle_title.text = Lang.t("csata_tobb_fel")
	if _battle_help != null: _battle_help.text = Lang.t("csata_sugo")
	if _screen == "battle": _refresh_battle_list()
	if _screen == "ach": _refresh_ach_list()
	if _home_title != null: _home_title.text = Lang.t("cim")
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
	if _screen == "single": show_screen("single")

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
		GameState.new_game(key, chosen_era, Style.is_pirate(key))
	else:
		Campaign.stop()
		GameState.new_game(chosen_nation, chosen_era, pirate_mode)
	GameState.diff = chosen_diff
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_continue() -> void:
	if not SaveManager.load_game(): return
	GameState.on = true
	GameState.over = false
	GameState.winner = -1
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
