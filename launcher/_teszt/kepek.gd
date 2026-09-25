extends "res://_teszt/_alap.gd"

# Képek és kilógás: a főablak (mindhárom játék bőrével), a fiókablak mindhárom állapota és a
# belépett nézet, a kiegészítők, a kódbeváltás és a beállítások ablaka. Minden állapotban
# megnézzük, hogy semmi ne lógjon ki az ablakból, és a szövegek elférjenek a helyükön.
# --mac-proba: a macOS-nagyítás (2,5×, legfeljebb a képernyő 94%-a) is.
# Ablakkal fut, de a képernyőn kívül (--position 20000,20000); a képek: --kepek=<mappa>.

var L = null
var mappa := ""
var mac := false

func _initialize() -> void:
	_orszem(120.0)
	_run.call_deferred()

func _kep(nev: String) -> void:
	await _kockak(6)
	await RenderingServer.frame_post_draw
	if mappa == "": return
	var ut := mappa.path_join(("mac_" if mac else "") + nev + ".png")
	root.get_viewport().get_texture().get_image().save_png(ut)

# A szöveg szélessége egy vezérlő saját betűjével
func _szel(c: Control, szoveg: String) -> float:
	var f: Font = c.get_theme_font("font")
	var m: int = c.get_theme_font_size("font_size")
	var w := 0.0
	for sor in szoveg.split("\n"):
		w = maxf(w, f.get_string_size(sor, HORIZONTAL_ALIGNMENT_LEFT, -1, m).x)
	return w

# A kilógó elemek egy ablakban (w: a fő ablak vagy egy felugró ablak)
func _kilogok(alap: Node, keret: Rect2) -> Array[String]:
	var r: Array[String] = []
	for n: Node in alap.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree() or c.size.x < 1.0: continue
		var gorget := false
		var p := c.get_parent()
		while p != null and p != alap:
			if p is ScrollContainer: gorget = true
			p = p.get_parent()
		if gorget: continue
		var gr := c.get_global_rect()
		if gr.position.x < keret.position.x - 1.0 or gr.position.y < keret.position.y - 1.0 \
				or gr.end.x > keret.end.x + 1.0 or gr.end.y > keret.end.y + 1.0:
			r.append("%s kívül (%s)" % [_nevvel(c), str(gr)])
			continue
		if c is Label:
			var l := c as Label
			if l.autowrap_mode == TextServer.AUTOWRAP_OFF and not l.clip_text and l.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING \
					and l.text != "" and _szel(l, l.text) > l.size.x + 1.0:
				r.append("%s szövege nem fér el (%d > %d)" % [_nevvel(c), int(_szel(l, l.text)), int(l.size.x)])
		elif c is Button:
			var b := c as Button
			if not b.clip_text and b.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and b.text != "":
				var kell := _szel(b, b.text) + 16.0 + (float(b.icon.get_width()) + 8.0 if b.icon != null else 0.0)
				if b is CheckBox or b is CheckButton: kell += 28.0
				if kell > b.size.x + 1.0: r.append("%s felirata nem fér el (%d > %d)" % [_nevvel(c), int(kell), int(b.size.x)])
	return r

func _nevvel(c: Control) -> String:
	var t := ""
	if c is Label: t = (c as Label).text
	elif c is Button: t = (c as Button).text
	return "%s „%s”" % [c.get_class(), t.left(30).replace("\n", " ")]

func _ablak_ell(nev: String, w: Window) -> void:
	var vp: Rect2 = root.get_visible_rect()
	if w == null:
		var k := _kilogok(L, vp)
		_ell(k.is_empty(), "%s: semmi sem lóg ki %s" % [nev, str(k.slice(0, 5))])
		return
	var wr := Rect2(Vector2(w.position), Vector2(w.size))
	_ell(vp.grow(1.0).encloses(wr), "%s: az ablak (%s) a főablakon belül van (%s)" % [nev, str(wr), str(vp.size)])
	var k2 := _kilogok(w, Rect2(Vector2.ZERO, Vector2(w.size)))
	_ell(k2.is_empty(), "%s: semmi sem lóg ki %s" % [nev, str(k2.slice(0, 5))])

func _run() -> void:
	if not _homokozo_rendben():
		_vege()
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kepek="): mappa = a.substr(8)
		if a == "--mac-proba": mac = true
	var w := root.get_window()
	var elotte := w.size
	L = _uj_launcher()
	# a macOS-nagyítás középre tenné az ablakot: rögtön (még a kirajzolás előtt) vissza a képernyőn kívülre
	var utana := w.size
	w.position = Vector2i(20000, 20000)
	await _kockak(4)
	w.position = Vector2i(20000, 20000)

	if mac:
		_fej("0. macOS-nagyítás (--mac-proba)")
		var alap := Vector2(1100, 720)
		var hely := Vector2(DisplayServer.screen_get_usable_rect(w.current_screen).size)
		var k := minf(2.5, minf(hely.x * 0.94 / alap.x, hely.y * 0.94 / alap.y))
		var vart := Vector2i((alap * k).round()) if k > 1.0 else elotte
		_ell(utana == vart, "az ablak %s → %s (várt: %s, képernyő: %s, szorzó %.2f)" % [str(elotte), str(utana), str(vart), str(hely), k])
		if k > 1.0:
			_ell(float(utana.x) <= hely.x and float(utana.y) <= hely.y, "kifér a képernyőre")
			var ls := root.get_visible_rect().size
			_ell(absf(ls.x / ls.y - 1100.0 / 720.0) < 0.02, "a felület arányosan nő (logikai méret: %s)" % str(ls))
		else:
			print("       (a képernyő %s kisebb, mint 1100×720 / 0,94 – itt a nagyítás nem próbálható, a függvény helyesen nem nagyít)" % str(hely))
	var kh := Vector2(DisplayServer.screen_get_usable_rect(w.current_screen).size)
	if kh.x < 1100.0 or kh.y < 720.0:
		print("  FIGYELEM a képernyő hasznos területe (%s) kisebb, mint a launcher 1100×720-as ablaka: az ablak %s lett, a felület logikai mérete %s"
			% [str(kh), str(w.size), str(root.get_visible_rect().size)])

	_fej("1. A főablak a három játék bőrével")
	for i in (L.GAMES as Array).size():
		L._switch_game(i)
		await _kockak(3)
		var nev := "fo_%s" % str(L.GAMES[i]["key"])
		await _kep(nev)
		_ablak_ell("főablak – %s" % L._label_of(L.GAMES[i]), null)
	L._switch_game(1)
	await _kockak(3)

	_fej("2. A fiókablak")
	for mod: String in ["belepes", "regisztracio", "jelszo"]:
		L._open_account()
		L._acc_mod_valt(mod)
		L.acc_popup.reset_size()
		await _kep("fiok_" + mod)
		_ell(L.acc_popup.visible, "fiók – %s: az ablak látszik a képen" % mod)
		_ablak_ell("fiók – %s" % mod, L.acc_popup)
	# egy hosszú hibaüzenettel (két sor) is kiférjen
	L._acc_mod_valt("belepes")
	L.acc_status.text = "Nem sikerült: hibás fióknév vagy jelszó. Ha a jelszavadat elfelejtetted, kattints lent az „Elfelejtett jelszó” linkre."
	L.acc_popup.reset_size()
	await _kep("fiok_hiba")
	_ablak_ell("fiók – hibaüzenettel", L.acc_popup)
	L._acc_mod_valt("regisztracio")
	L.acc_status.text = "Kész: a fiókneved „Hosszunevu_Jatekos”. Elküldtük a megerősítő levelet a(z) nagyon.hosszu.email.cim@valami-szolgaltato.example címre – kattints a benne lévő linkre, aztán lépj be a fiókneveddel.\nHa nem látod, nézd meg a Spam / Levélszemét mappát is – a levél a ParthLaunchertől jön."
	L.acc_popup.reset_size()
	await _kep("fiok_reg_kesz")
	_ablak_ell("fiók – regisztráció utáni hosszú üzenet", L.acc_popup)
	L.acc_popup.hide()
	# belépett nézet (hosszú e-mail-címmel, fióknév nélkül)
	L.acc_token = "AT-proba"
	L.cfg.set_value("account", "fioknev", "")
	L.cfg.set_value("account", "email", "nagyon.hosszu.email.cim.teszteleshez@valami-szolgaltato.example")
	L._refresh_account_ui()
	await _kockak(2)
	L._open_account()
	await _kep("fiok_belepve")
	_ell(L.acc_popup.visible and L.acc_out_box.visible, "belépve a fiókablak a kijelentkező részt mutatja")
	_ablak_ell("fiók – belépve", L.acc_popup)
	L.acc_popup.hide()
	await _kep("fo_belepve_hosszu_email")
	_ablak_ell("főablak – belépve, hosszú e-mail-cím", null)
	_ell(L.acc_top_btn.size.x <= 262.0, "a fejléc fiókgombja nem nő meg a hosszú címtől (%d px)" % int(L.acc_top_btn.size.x))

	_fej("3. Kiegészítők, kódbeváltás, beállítások")
	L.cfg.set_value("dlc:vikingek", "license", "account")
	_zip_ir(_alap_mappa().path_join("Heptarchia/dlc/vikingek.zip"))
	await L._open_dlc_popup()
	await _kep("kiegeszitok")
	_ablak_ell("kiegészítők", L.dlc_popup)
	L.dlc_popup.hide()
	L._open_license({})
	await _kep("kodbevaltas")
	_ablak_ell("kódbeváltás", L.license_popup)
	L.license_popup.hide()
	L._open_settings()
	await _kep("beallitasok")
	_ablak_ell("beállítások", L.settings)
	L.settings.hide()
	_vege()
