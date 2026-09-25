extends "res://_teszt/_alap.gd"

# Kiegészítők: a kártyák (megvan / nincs meg), a ki-be kapcsoló, a változatsor, a csomagok
# félretétele, a dlc-access igazolás mentése, a letöltés (helyi próbaszerverről) és a hibái,
# a kódbeváltás, és a játékletöltés elakadásfigyelője. A fiókszerver válaszai előre megírtak.

var L = null

func _initialize() -> void:
	_orszem(150.0)
	_run.call_deferred()

func _kartya(nev: String) -> Control:
	for c: Node in L.dlc_box.get_children():
		for l: Node in c.find_children("*", "Label", true, false):
			if str((l as Label).text).begins_with(nev + "  –"): return c as Control
	return null

func _szovegek(c: Control) -> Array[String]:
	var r: Array[String] = []
	if c == null: return r
	for n: Node in c.find_children("*", "", true, false):
		if n is Label: r.append(str((n as Label).text))
		elif n is Button: r.append("[%s]" % str((n as Button).text))
	return r

func _kapcsolo(c: Control) -> CheckButton:
	if c == null: return null
	var t: Array[Node] = c.find_children("*", "CheckButton", true, false)
	return t[0] as CheckButton if not t.is_empty() else null

func _d(kulcs: String) -> Dictionary:
	for d: Dictionary in L.DLCS["heptarchia"]:
		if str(d["key"]) == kulcs: return d
	return {}

func _statusz() -> String:
	return str(L.lbl_status.text)

# Egy nagyon egyszerű helyi HTTP-szerver: egyetlen kérésre egyetlen választ ad.
func _kiszolgal(szerver: TCPServer, fej: String, test: PackedByteArray, amig: Callable, max_mp: float = 10.0) -> bool:
	var conn: StreamPeerTCP = null
	var keres := ""
	var kuldve := false
	var t0 := Time.get_ticks_msec()
	while bool(amig.call()):
		if Time.get_ticks_msec() - t0 > int(max_mp * 1000.0): return false
		if conn == null and szerver.is_connection_available(): conn = szerver.take_connection()
		if conn != null:
			conn.poll()
			var n := conn.get_available_bytes()
			if n > 0: keres += (conn.get_data(n)[1] as PackedByteArray).get_string_from_utf8()
			if not kuldve and keres.contains("\r\n\r\n"):
				var valasz := ("%s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [fej, test.size()]).to_utf8_buffer()
				valasz.append_array(test)
				conn.put_data(valasz)
				kuldve = true
		await process_frame
	if conn != null: conn.disconnect_from_host()
	return kuldve

func _run() -> void:
	if not _homokozo_rendben():
		_vege()
		return
	L = _uj_launcher()
	await _kockak(4)
	var hep: String = _alap_mappa().path_join("Heptarchia")

	_fej("1. A kiegészítők gombja játékonként")
	_ell(int(L.game_idx) == 0 and not L.btn_dlc.visible and L.btn_code.visible, "Birodalom: nincs kiegészítő-gomb, a kódbeváltás látszik")
	L._switch_game(1)
	await _kockak(3)
	_ell(str(L.game()["key"]) == "heptarchia" and L.btn_dlc.visible, "Heptarchia: a kiegészítő-gomb látszik")
	_ell(str(L.btn_dlc.text) == "Kiegészítők  0/4", "felirat: „%s”" % str(L.btn_dlc.text))

	_fej("2. Egyik sincs meg")
	L._open_dlc_popup()
	await _kockak(4)
	_ell(L.dlc_popup.visible and L.dlc_box.get_child_count() == 4, "az ablak 4 kártyával nyílik (%d)" % L.dlc_box.get_child_count())
	for d: Dictionary in L.DLCS["heptarchia"]:
		var sz := _szovegek(_kartya(str(d["name"])))
		_ell(sz.has("%s  –  %s" % [d["name"], d["price"]]) and sz.has("[Megvásárlás – %s]" % d["price"]) and sz.has("[Van kulcsom]")
			and _kapcsolo(_kartya(str(d["name"]))) == null, "%s: ár, Megvásárlás, Van kulcsom, nincs kapcsoló" % d["name"])
	_ell(str(L.dlc_pop_title.text) == "Kiegészítők – Heptarchia", "az ablak címe: %s" % str(L.dlc_pop_title.text))
	# az ablak férjen ki a launcher ablakába
	var vp: Vector2 = L.get_viewport().get_visible_rect().size
	_ell(float(L.dlc_popup.size.x) <= vp.x and float(L.dlc_popup.size.y) <= vp.y, "az ablak (%s) kifér a képernyőre (%s)" % [str(L.dlc_popup.size), str(vp)])

	_fej("3. Megvan: a fiókból (telepítve) és helyi kulccsal (még nincs letöltve)")
	L.cfg.set_value("dlc:vikingek", "license", "account")
	L.cfg.set_value("dlc:skandinavia", "license", "HELYI-KULCS")
	_zip_ir(hep.path_join("dlc/vikingek.zip"))
	L._refresh_dlc()
	await _kockak(2)
	var vk := _kartya("A vikingek kora")
	var sz := _szovegek(vk)
	_ell(sz.has("A vikingek kora  –  megvásárolva") and sz.has("[Újratöltés]") and _kapcsolo(vk) != null and _kapcsolo(vk).button_pressed,
		"vikingek: megvásárolva, bekapcsolva, Újratöltés – %s" % str(sz))
	_ell(sz.has("Változat: ismeretlen"), "változatsor, ha nem tudjuk: „Változat: ismeretlen”")
	var sk := _szovegek(_kartya("Skandinávia"))
	_ell(sk.has("Nincs letöltve") and sk.has("[Letöltés]") and sk.has("Még nincs letöltve"), "Skandinávia: nincs letöltve – %s" % str(sk))
	_ell(str(L.btn_dlc.text) == "Kiegészítők  2/4", "felirat: „%s”" % str(L.btn_dlc.text))
	L.cfg.set_value("dlc:vikingek", "version", "vikingek-v8")
	L.dlc_latest["vikingek"] = ["vikingek-v9", ""]
	_ell(str(L._dlc_version_text(_d("vikingek"))) == "Változat: vikingek-v8 · új változat: vikingek-v9", "elavult: %s" % L._dlc_version_text(_d("vikingek")))
	L.dlc_latest["vikingek"] = ["vikingek-v8", ""]
	_ell(str(L._dlc_version_text(_d("vikingek"))) == "Változat: vikingek-v8 · naprakész", "naprakész: %s" % L._dlc_version_text(_d("vikingek")))

	_fej("4. Ki- és bekapcsolás (a játék settings.cfg-je)")
	vk = _kartya("A vikingek kora")
	_kapcsolo(vk).button_pressed = false
	await _kockak(1)
	var gc := ConfigFile.new()
	gc.load(hep.path_join("settings.cfg"))
	_ell(gc.get_value("dlc", "vikings", true) == false and _statusz().contains("kikapcsolva"), "kikapcsolva mentve: [dlc] vikings=false, „%s”" % _statusz())
	L._refresh_dlc()
	await _kockak(1)
	_ell(not _kapcsolo(_kartya("A vikingek kora")).button_pressed, "újranyitáskor is kikapcsolt")
	_kapcsolo(_kartya("A vikingek kora")).button_pressed = true
	gc.load(hep.path_join("settings.cfg"))
	_ell(gc.get_value("dlc", "vikings", false) == true, "visszakapcsolva")

	_fej("5. Jog nélkül a csomag félrekerül, joggal visszajön")
	L.cfg.set_value("dlc:vikingek", "license", "")
	L._dlc_egyeztet()
	_ell(not FileAccess.file_exists(hep.path_join("dlc/vikingek.zip")) and FileAccess.file_exists(hep.path_join("dlc_zarolt/vikingek.zip")), "jog nélkül: dlc_zarolt")
	L.cfg.set_value("dlc:vikingek", "license", "account")
	L._dlc_egyeztet()
	_ell(FileAccess.file_exists(hep.path_join("dlc/vikingek.zip")) and not FileAccess.file_exists(hep.path_join("dlc_zarolt/vikingek.zip")), "joggal: vissza a dlc mappába")

	_fej("6. A dlc-access igazolása")
	# az igazolás egy IDEGEN kulccsal aláírt minta: a launcher dolga csak a változatlan továbbítás
	# (az aláírást a játék ellenőrzi – a Heptarchia _test/dlc_vedelem.gd próbája)
	var c := Crypto.new()
	var kulcs := c.generate_rsa(1024)
	var p := JSON.stringify({"v": 1, "u": "proba", "g": "heptarchia", "d": ["vikingek"], "m": OS.get_unique_id(),
		"iat": int(Time.get_unix_time_from_system()), "exp": int(Time.get_unix_time_from_system()) + 3600}).to_utf8_buffer()
	var hc := HashingContext.new(); hc.start(HashingContext.HASH_SHA256); hc.update(p)
	var jog := {"p": Marshalls.raw_to_base64(p), "s": Marshalls.raw_to_base64(c.sign(HashingContext.HASH_SHA256, hc.finish(), kulcs))}
	var jog_ut := hep.path_join("dlc_jog.json")
	L.acc_token = ""
	L.hivasok.clear()
	await L._dlc_jog_frissit()
	_ell(L.hivasok.is_empty() and not FileAccess.file_exists(jog_ut), "belépés nélkül nem kérdez, nem ír")
	L.acc_token = "AT-proba"
	L.valaszok = [["dlc-access", 200, {"token": jog, "owned": ["vikingek"], "latest": {"vikingek": "vikingek-v9"}}]]
	await L._dlc_jog_frissit()
	var h: Dictionary = L.hivasok[-1]
	_ell((h["body"] as Dictionary).get("game") == "heptarchia" and (h["body"] as Dictionary).get("machine") == OS.get_unique_id()
		and str(h["token"]) == "AT-proba", "a kérés: játék, gépazonosító, a fiók tokenje")
	_ell(JSON.parse_string(_fajl_szoveg(jog_ut)) == jog, "az igazolás változatlanul a Heptarchia adatmappájába került")
	for hibas: Array in [[401, {"error": "not_logged_in"}], [500, {"error": "db_error"}], [0, {}], [200, {"owned": []}]]:
		L.valaszok = [["dlc-access", hibas[0], hibas[1]]]
		await L._dlc_jog_frissit()
		_ell(JSON.parse_string(_fajl_szoveg(jog_ut)) == jog, "hibás válasz (%d %s) után a meglévő igazolás megmarad" % [int(hibas[0]), str(hibas[1])])

	_fej("7. Letöltés: a szerver elutasítja / nem érhető el")
	var vd := _d("vikingek")
	var esetek: Array = [[0, {}, "a letöltési szerver nem érhető el"], [401, {"error": "not_logged_in"}, "a belépésed lejárt"],
		[403, {"error": "not_owned"}, "ez a fiók nem jogosult rá (not_owned)"],
		[502, {"error": "github_error", "github": 404}, "hiba 502 (github_error, GitHub 404)"]]
	for e: Array in esetek:
		L.valaszok = [["dlc-access", e[0], e[1]]]
		await L._download_dlc(vd)
		_ell(_statusz().contains(str(e[2])) and not L.dlc_busy, "%d: „%s”" % [int(e[0]), _statusz().left(90)])
	L.acc_token = ""
	await L._download_dlc(vd)
	_ell(_statusz().contains("a belépésed lejárt"), "belépés nélkül: „%s”" % _statusz().left(80))
	L.acc_token = "AT-proba"
	L.hivasok.clear()
	await L._download_dlc(_d("vallas"))
	_ell(L.hivasok.is_empty(), "meg nem vásárolt kiegészítőt nem is próbál letölteni")

	_fej("8. Letöltés helyi próbaszerverről")
	L.cfg.set_value("dlc:skandinavia", "license", "")     # csak a vikingekkel foglalkozzon
	var szerver := TCPServer.new()
	var port := 0
	for pp in range(47910, 47990):
		if szerver.listen(pp, "127.0.0.1") == OK:
			port = pp
			break
	var zip_ut := hep.path_join("dlc/vikingek.zip")
	var regi := FileAccess.get_file_as_bytes(zip_ut)
	var uj_zip := _alap_mappa().path_join("uj.zip")
	var z := ZIPPacker.new(); z.open(uj_zip); z.start_file("uj.txt"); z.write_file("uj".to_utf8_buffer()); z.close_file(); z.close()
	var uj := FileAccess.get_file_as_bytes(uj_zip)
	var url := "http://127.0.0.1:%d/vikingek.zip" % port
	# rossz csomag (nem zip) – a régi marad
	L.valaszok = [["dlc-access", 200, {"url": url, "tag": "vikingek-v9"}]]
	L._download_dlc(vd)
	await _kiszolgal(szerver, "HTTP/1.1 200 OK", "ez nem zip".to_utf8_buffer(), func() -> bool: return L.dlc_busy or L.hivasok.is_empty())
	await _kockak(2)
	_ell(_statusz().contains("letöltése nem sikerült (HTTP 200)") and FileAccess.get_file_as_bytes(zip_ut) == regi
		and not FileAccess.file_exists(zip_ut + ".tmp"), "hibás csomag: elutasítva, a régi megmaradt, „%s”" % _statusz())
	L.valaszok = [["dlc-access", 200, {"url": url, "tag": "vikingek-v9"}]]
	L._download_dlc(vd)
	await _kiszolgal(szerver, "HTTP/1.1 404 Not Found", PackedByteArray(), func() -> bool: return L.dlc_busy)
	await _kockak(2)
	_ell(_statusz().contains("(HTTP 404)") and FileAccess.get_file_as_bytes(zip_ut) == regi, "404: „%s”" % _statusz())
	L.dlc_latest.clear()
	L._vedett_latest.clear()
	L.valaszok = [["dlc-access", 200, {"url": url, "tag": "vikingek-v9"}]]
	L._download_dlc(vd)
	var kiszolgalva: bool = await _kiszolgal(szerver, "HTTP/1.1 200 OK", uj, func() -> bool: return L.dlc_busy)
	await _kockak(3)
	_ell(kiszolgalva and FileAccess.get_file_as_bytes(zip_ut) == uj, "a letöltött csomag a helyére került")
	_ell(str(L.cfg.get_value("dlc:vikingek", "version", "")) == "vikingek-v9" and _cfg_lemezen().get_value("dlc:vikingek", "version", "") == "vikingek-v9",
		"a változat mentve: vikingek-v9")
	_ell(_statusz().begins_with("A(z) A vikingek kora frissítve (vikingek-v9)"), "„%s”" % _statusz())
	szerver.stop()

	_fej("9. Kódbeváltás")
	L.acc_token = ""
	L.cfg.set_value("account", "refresh_token", "")
	L._open_license({})
	await _kockak(2)
	_ell(L.license_popup.visible and str(L.lic_title.text) == "Kód beváltása", "a kódbeváltó ablak megnyílik")
	L.lic_edit.text = "ABCD-1234"
	L.lic_edit.text_submitted.emit("ABCD-1234")
	await _kockak(3)
	_ell(not L.license_popup.visible and L.acc_popup.visible, "belépés nélkül a fiókablakra irányít")
	L.acc_popup.hide()
	L.acc_token = "AT-proba"
	L.cfg.set_value("account", "refresh_token", "RT-proba")
	L._open_license(_d("varegok"))
	await _kockak(2)
	_ell(str(L.lic_title.text) == "A varégok útja – licenckulcs", "kártyáról nyitva a kiegészítő neve a cím")
	var jelolt: Array = L._license_candidates()
	_ell(str(jelolt[0]["key"]) == "varegok" and jelolt.size() == 4, "a kártya kiegészítőjével kezdi a próbát")
	L.lic_edit.text = "ROSSZ-KULCS"
	L.hivasok.clear()
	L.valaszok = [["claim-license", 400, {"error": "invalid_key"}], ["claim-license", 400, {"error": "invalid_key"}],
		["claim-license", 400, {"error": "invalid_key"}], ["claim-license", 400, {"error": "invalid_key"}]]
	await L._redeem_license()
	_ell(L.hivott("claim-license") == 4 and str(L.lic_status.text).begins_with("Ez a kulcs egyik kiegészítőhöz sem érvényes"),
		"érvénytelen kulcs: mind a 4-et kipróbálja, „%s”" % str(L.lic_status.text).left(50))
	L.valaszok = [["claim-license", 409, {"error": "key_taken"}]]
	await L._redeem_license()
	_ell(str(L.lic_status.text).contains("már egy másik fiókhoz kötötték"), "foglalt kulcs: „%s”" % str(L.lic_status.text).left(70))
	L.valaszok = [["claim-license", 0, {}]]
	await L._redeem_license()
	_ell(str(L.lic_status.text).begins_with("Nem sikerült elérni"), "hálózat nélkül")
	L.valaszok = [["claim-license", 200, {"ok": true}], ["/rest/v1/entitlements", 200, [{"dlc_key": "varegok"}, {"dlc_key": "vikingek"}]],
		["dlc-access", 200, {"token": jog, "owned": ["varegok", "vikingek"], "latest": {}}], ["dlc-access", 403, {"error": "not_owned"}]]
	L.lic_edit.text = "JO-KULCS"
	await L._redeem_license()
	await _kockak(4)
	_ell(not L.license_popup.visible and str(L.cfg.get_value("dlc:varegok", "license", "")) == "account", "jó kulcs: aktiválva, a fiókból megvásárolt")
	print("       (állapotsor: %s)" % _statusz().left(100))

	_fej("10. A játék letöltésének elakadásfigyelője")
	L.set_process(false)
	L.busy = true
	L.http.download_file = "user://proba_update.zip"
	for kapcs: Dictionary in L.http.request_completed.get_connections():
		L.http.request_completed.disconnect(kapcs["callable"])
	L.http.request_completed.connect(L._on_downloaded, CONNECT_ONE_SHOT)
	L._process(0.1)
	L._process(float(L.LETOLTES_ELAKAD) - 1.0)
	_ell(L.busy, "44 mp adat nélkül még vár")
	L._process(2.0)
	await _kockak(1)
	_ell(not L.busy and _statusz().contains("időtúllépés"), "45 mp után megszakítja: „%s”" % _statusz().left(70))
	_ell(L.varatlan.is_empty(), "minden fiókkérésre volt előre megírt válasz (%s)" % str(L.varatlan))
	_vege()
