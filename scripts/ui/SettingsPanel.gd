class_name SettingsPanel
extends PanelContainer

# Beállítások — grafika és hang. Ugyanez a panel jelenik meg a főmenüben
# és a játék közbeni menüben is, hogy a két helyen ne kelljen két külön
# felületet karbantartani. Minden változás azonnal érvényes és mentődik
# (Settings autoload -> user://options.json).

const FPS_CHOICES := [30, 60, 120, 0]      # 0 = korlátlan

var _rows: Array[Control] = []
var _title: Label = null

func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	# A panel a saját címét hozza, hogy bárhová beilleszthető legyen.
	_title = _section(box, "beallitasok")
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(HSeparator.new())
	_section(box, "beall_grafika")
	_detail_row(box)
	_check(box, "beall_teljes_kepernyo", Settings.fullscreen,
		func(v: bool) -> void: Settings.set_fullscreen(v))
	_check(box, "beall_vsync", Settings.vsync,
		func(v: bool) -> void: Settings.set_vsync(v))
	_fps_row(box)
	# A VILÁG két ideje: az időjárás (eső, hó, köd, tengeri vihar) és a
	# nappal-éjszaka ciklus. Mindkettő a látványt ÉS a szimulációt érinti
	# (tempó, látótáv), ezért kapcsolható — gyenge gépen vagy ha zavar.
	_check(box, "beall_idojaras", Settings.weather_on,
		func(v: bool) -> void:
			Settings.weather_on = v
			Settings.save_options())
	_check(box, "beall_nappal_ejszaka", Settings.day_night,
		func(v: bool) -> void:
			Settings.day_night = v
			Settings.save_options())
	# RAGYOGÁS: a láng, a torkolattűz és a lámpák túlcsordulása. Teljes
	# képernyős utómunka — gyenge gépen ezt érdemes először levenni.
	_check(box, "beall_ragyogas", Settings.bloom,
		func(v: bool) -> void:
			Settings.bloom = v
			Settings.save_options())

	box.add_child(HSeparator.new())
	_section(box, "beall_hang")
	_check(box, "beall_zene", Settings.music_on,
		func(v: bool) -> void: Settings.set_music_on(v))
	_slider(box, "beall_zene_hangero", Settings.music_vol,
		func(v: float) -> void: Settings.set_music_vol(v))
	_check(box, "beall_hangok", Settings.sfx_on,
		func(v: bool) -> void: Settings.set_sfx_on(v))
	_slider(box, "beall_hangok_hangero", Settings.sfx_vol,
		func(v: float) -> void: Settings.set_sfx_vol(v))

	custom_minimum_size = Vector2(340, 0)

func _section(box: VBoxContainer, key: String) -> Label:
	var l := Label.new()
	l.text = Lang.t(key)
	l.add_theme_font_size_override("font_size", 15)
	box.add_child(l)
	return l

# Be/ki kapcsoló: felirat balra, gomb jobbra.
func _check(box: VBoxContainer, key: String, value: bool,
		on_change: Callable) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = Lang.t(key)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = value
	b.custom_minimum_size = Vector2(72, 26)
	b.text = Lang.t("be") if value else Lang.t("ki")
	b.toggled.connect(func(v: bool) -> void:
		b.text = Lang.t("be") if v else Lang.t("ki")
		on_change.call(v)
		SFX.play("click"))
	row.add_child(b)
	box.add_child(row)
	_rows.append(row)

func _slider(box: VBoxContainer, key: String, value: float,
		on_change: Callable) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = Lang.t(key)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(140, 20)
	var num := Label.new()
	num.custom_minimum_size = Vector2(38, 0)
	num.text = "%d%%" % int(round(value * 100.0))
	s.value_changed.connect(func(v: float) -> void:
		num.text = "%d%%" % int(round(v * 100.0))
		on_change.call(v))
	row.add_child(s)
	row.add_child(num)
	box.add_child(row)
	_rows.append(row)

# Részletesség: gyenge, régi gépen az "alacsony" lekapcsolja a folyamatosan
# mozgó apróságokat, és ritkítja a köd meg a minimap frissítését.
const DETAIL_KEYS := ["beall_alacsony", "beall_kozepes", "beall_magas"]

func _detail_row(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = Lang.t("beall_reszletesseg")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var b := Button.new()
	b.custom_minimum_size = Vector2(110, 26)
	b.text = Lang.t(DETAIL_KEYS[clampi(Settings.detail, 0, 2)])
	b.pressed.connect(func() -> void:
		Settings.set_detail((Settings.detail + 1) % 3)
		b.text = Lang.t(DETAIL_KEYS[Settings.detail])
		SFX.play("click"))
	row.add_child(b)
	box.add_child(row)
	_rows.append(row)
	var sugo := Label.new()
	sugo.text = Lang.t("beall_reszletesseg_sugo")
	sugo.add_theme_font_size_override("font_size", 11)
	sugo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sugo.modulate = Color(1, 1, 1, 0.62)
	box.add_child(sugo)

# Képsebesség-korlát: körbeforgó választó.
func _fps_row(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = Lang.t("beall_fps")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var b := Button.new()
	b.custom_minimum_size = Vector2(96, 26)
	b.text = _fps_text(Settings.fps_limit)
	b.pressed.connect(func() -> void:
		var i := FPS_CHOICES.find(Settings.fps_limit)
		var nxt: int = FPS_CHOICES[(i + 1) % FPS_CHOICES.size()]
		Settings.set_fps_limit(nxt)
		b.text = _fps_text(nxt)
		SFX.play("click"))
	row.add_child(b)
	box.add_child(row)
	_rows.append(row)

func _fps_text(v: int) -> String:
	return Lang.t("beall_korlatlan") if v <= 0 else str(v)
