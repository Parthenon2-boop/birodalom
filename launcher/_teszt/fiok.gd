extends "res://_teszt/_alap.gd"

# A fiókablak: a három állapot (belépés, regisztráció, elfelejtett jelszó) mezői, a Tab-sorrend,
# az Enter, az ellenőrzések, és a szerver válaszainak kezelése – a szerver HELYETT előre megírt
# válaszokkal (_mock.gd). Valódi fiók, valódi jelszó, valódi kérés NINCS.
# Futtatás: _teszt/futtat.ps1 (a próbamappa miatt), parancssori kapcsoló: -- --halozat-nelkul

const SESSION := {"access_token": "AT-proba", "refresh_token": "RT-proba", "token_type": "bearer",
	"user": {"email": "proba@pelda.hu", "user_metadata": {"username": "Probaelek"}}}

var L = null

func _initialize() -> void:
	_orszem(150.0)
	_run.call_deferred()

func _fokusz() -> Control:
	return L.acc_popup.gui_get_focus_owner()

func _nev(c: Control) -> String:
	if c == null: return "semmi"
	for p: Array in [[L.acc_user_edit, "fióknév"], [L.acc_email_edit, "e-mail"], [L.acc_pass_edit, "jelszó"],
			[L.acc_fo_gomb, "fő gomb"], [L.acc_stay, "pipa"], [L.acc_link1, "link1"], [L.acc_link2, "link2"]]:
		if p[0] == c: return str(p[1])
	return str(c.name)

func _tab_sor(elso: Control, hossz: int, shift: bool = false) -> String:
	elso.grab_focus()
	await process_frame
	var nevek: Array[String] = [_nev(_fokusz())]
	for i in hossz:
		await _billentyu(KEY_TAB, shift)
		nevek.append(_nev(_fokusz()))
	return " → ".join(nevek)

func _kitolt(nev: String, email: String, jelszo: String) -> void:
	L.acc_user_edit.text = nev
	L.acc_email_edit.text = email
	L.acc_pass_edit.text = jelszo

func _allapot() -> String:
	return str(L.acc_status.text)

# egy kérés-válasz kör: vár, amíg a kérés(ek) lefutnak
func _kuld_es_var(max_mp: float = 5.0) -> void:
	L._acc_kuld()
	await _var(func() -> bool: return not (_allapot().ends_with("…")), max_mp)
	await _kockak(3)

func _run() -> void:
	if not _homokozo_rendben():
		_vege()
		return
	L = _uj_launcher()
	await _kockak(5)

	_fej("1. A fiókablak megnyílik, belépés állapot")
	_ell(not L._acc_logged_in(), "friss próbamappában nincs belépés")
	_ell(str(L.btn_main.text) == "Bejelentkezés" or str(L.btn_main.text) in ["Frissítés", "Indítás"], "a nagy gomb felirata: %s" % str(L.btn_main.text))
	_ell(str(L.acc_top_btn.text) == "Bejelentkezés / Regisztráció", "a fejléc gombja: %s" % str(L.acc_top_btn.text))
	L.acc_top_btn.pressed.emit()
	await _kockak(4)
	_ell(L.acc_popup.visible, "a fejléc gombjára megnyílik az ablak")
	_ell(L.acc_login_box.visible and not L.acc_out_box.visible, "a belépő rész látszik, a kijelentkező nem")
	_ell(str(L.acc_mod) == "belepes" and str(L.acc_mod_cim.text) == "Belépés", "állapot: Belépés")
	_ell(L.acc_user_edit.visible and not L.acc_email_edit.visible and L.acc_pass_edit.visible, "mezők: fióknév + jelszó (e-mail rejtve)")
	_ell(str(L.acc_user_edit.placeholder_text) == "fióknév" and str(L.acc_pass_edit.placeholder_text) == "jelszó",
		"helykitöltők: „%s”, „%s”" % [L.acc_user_edit.placeholder_text, L.acc_pass_edit.placeholder_text])
	_ell(L.acc_pass_edit.secret, "a jelszó rejtve gépelődik")
	_ell(str(L.acc_fo_gomb.text) == "Belépés" and L.acc_stay.visible and L.acc_stay.button_pressed, "fő gomb: Belépés; „Bejelentkezve maradok” látszik és alapból be van kapcsolva")
	_ell(str(L.acc_link1.text).contains("regisztráció") and L.acc_link2.visible, "linkek: regisztráció + elfelejtett jelszó")
	_ell(_fokusz() == L.acc_user_edit, "a fókusz a fióknév mezőn (%s)" % _nev(_fokusz()))
	var sor: String = await _tab_sor(L.acc_user_edit, 3)
	_ell(sor == "fióknév → jelszó → fő gomb → fióknév", "Tab: %s" % sor)
	sor = await _tab_sor(L.acc_user_edit, 3, true)
	_ell(sor == "fióknév → fő gomb → jelszó → fióknév", "Shift+Tab: %s" % sor)

	_fej("2. Regisztráció állapot")
	L.acc_link1.pressed.emit()
	await _kockak(3)
	_ell(str(L.acc_mod) == "regisztracio" and str(L.acc_mod_cim.text) == "Új fiók", "állapot: Új fiók")
	_ell(L.acc_user_edit.visible and L.acc_email_edit.visible and L.acc_pass_edit.visible, "mezők: fióknév + e-mail + jelszó")
	_ell(str(L.acc_user_edit.placeholder_text) == "fióknév (3–20 karakter)"
		and str(L.acc_email_edit.placeholder_text) == "e-mail-cím (ide küldjük a megerősítő levelet)"
		and str(L.acc_pass_edit.placeholder_text) == "jelszó (legalább 8 karakter)", "helykitöltők a szabályokkal")
	_ell(str(L.acc_fo_gomb.text) == "Regisztráció" and not L.acc_link2.visible and str(L.acc_link1.text).contains("belépés"),
		"fő gomb: Regisztráció; link vissza a belépéshez; nincs elfelejtett jelszó")
	_ell(_fokusz() == L.acc_user_edit, "váltás után a fókusz a fióknéven (%s)" % _nev(_fokusz()))
	sor = await _tab_sor(L.acc_user_edit, 4)
	_ell(sor == "fióknév → e-mail → jelszó → fő gomb → fióknév", "Tab: %s" % sor)

	_fej("3. Elfelejtett jelszó állapot")
	L._acc_mod_valt("belepes")
	L.acc_link2.pressed.emit()
	await _kockak(3)
	_ell(str(L.acc_mod) == "jelszo" and str(L.acc_mod_cim.text) == "Elfelejtett jelszó", "állapot: Elfelejtett jelszó")
	_ell(not L.acc_user_edit.visible and L.acc_email_edit.visible and not L.acc_pass_edit.visible and not L.acc_stay.visible,
		"csak az e-mail mező (és a pipa sincs)")
	_ell(str(L.acc_email_edit.placeholder_text) == "a fiókod e-mail-címe" and str(L.acc_fo_gomb.text) == "Levél küldése", "helykitöltő és gomb")
	_ell(_fokusz() == L.acc_email_edit, "a fókusz az e-mail mezőn (%s)" % _nev(_fokusz()))
	sor = await _tab_sor(L.acc_email_edit, 2)
	_ell(sor == "e-mail → fő gomb → e-mail", "Tab: %s" % sor)

	_fej("4. Ellenőrzés a gépen (kérés nélkül)")
	L.hivasok.clear()
	L._acc_mod_valt("belepes")
	_kitolt("", "", "")
	L.acc_user_edit.grab_focus()
	await _billentyu(KEY_ENTER)
	_ell(_allapot() == "Add meg a fióknevedet és a jelszavadat.", "belépés üresen, Enterre: „%s”" % _allapot())
	_kitolt("Probaelek", "", "")
	L.acc_user_edit.grab_focus()
	await _billentyu(KEY_ENTER)
	_ell(_allapot() == "Add meg a fióknevedet és a jelszavadat.", "jelszó nélkül: ugyanez")
	L._acc_mod_valt("regisztracio")
	var esetek: Array = [
		["", "a@b.hu", "12345678", "mindhárom mező"],
		["ab", "a@b.hu", "12345678", "3–20 karakter"],
		["a".repeat(21), "a@b.hu", "12345678", "3–20 karakter"],
		["szó köz", "a@b.hu", "12345678", "3–20 karakter"],
		["rossz!", "a@b.hu", "12345678", "3–20 karakter"],
		["Árvíztűrő", "rossz", "12345678", "e-mail-cím nem jónak"],
		["Árvíztűrő", "rossz@", "12345678", "e-mail-cím nem jónak"],
		["Árvíztűrő", "a@b.hu", "1234567", "legalább 8"],
	]
	for e: Array in esetek:
		_kitolt(str(e[0]), str(e[1]), str(e[2]))
		L.acc_pass_edit.grab_focus()
		await _billentyu(KEY_ENTER)
		_ell(_allapot().contains(str(e[3])), "regisztráció „%s” / „%s” / %d karakteres jelszó → „%s”"
			% [str(e[0]).left(12), e[1], str(e[2]).length(), _allapot().left(60)])
	# gyenge pont: pont a @ ELŐTT is elég
	_kitolt("Árvíztűrő", "x.y@z", "12345678")
	_ell(not L._acc_user_ok("") and L._acc_user_ok("Árvíztűrő") and L._acc_user_ok("a_b-c") and L._acc_user_ok("x".repeat(20)),
		"a fióknév-szabály ékezettel, aláhúzással, kötőjellel, 20 karakterig jó")
	L._acc_mod_valt("jelszo")
	L.acc_email_edit.text = "nem-email"
	L.acc_email_edit.grab_focus()
	await _billentyu(KEY_ENTER)
	_ell(_allapot().begins_with("Írd be a fiókod e-mail-címét"), "elfelejtett jelszó rossz címmel: „%s”" % _allapot())
	await _kockak(2)
	_ell(L.hivasok.is_empty(), "egyik ellenőrzési hiba sem küldött kérést (%d kérés)" % L.hivasok.size())

	_fej("5. Belépés – a szerver válaszai (előre megírva)")
	L._acc_mod_valt("belepes")
	L.valaszok = [["login-nev", 400, {"error": "rossz_belepes"}]]
	_kitolt("Probaelek", "", "rossz-jelszo")
	await _kuld_es_var()
	_ell(_allapot().begins_with("Nem sikerült: hibás fióknév vagy jelszó"), "rossz jelszó: „%s”" % _allapot().left(60))
	_ell(str(L.acc_pass_edit.text) == "" and str(L.acc_user_edit.text) == "Probaelek", "a jelszó mező kiürül, a név marad")
	var h: Dictionary = L.hivasok[-1]
	_ell(str(h["path"]) == "/functions/v1/login-nev" and (h["body"] as Dictionary).get("nev") == "Probaelek",
		"a kérés a login-nev függvénynek ment, a fióknévvel")
	_ell(not L._acc_logged_in(), "nincs belépve")
	L.valaszok = [["login-nev", 400, {"error": "nincs_megerositve"}]]
	_kitolt("Probaelek", "", "jelszo123")
	await _kuld_es_var()
	_ell(_allapot().begins_with("Előbb erősítsd meg az e-mail-címedet"), "megerősítetlen e-mail: „%s”" % _allapot().left(50))
	L.valaszok = [["login-nev", 0, {}]]
	_kitolt("Probaelek", "", "jelszo123")
	await _kuld_es_var()
	_ell(_allapot() == "Nem sikerült elérni a szervert. Van internet?", "nincs hálózat: „%s”" % _allapot())
	L.valaszok = [["login-nev", 500, {"message": "Internal"}]]
	_kitolt("Probaelek", "", "jelszo123")
	await _kuld_es_var()
	# szerverhibánál nem a jelszót hibáztatjuk
	_ell(_allapot().contains("500") and not _allapot().contains("jelszó"), "szerverhiba (500): „%s”" % _allapot().left(50))
	# a fióknévvel belépő függvény hiányzik (404): e-mail-címmel a régi úton
	L.valaszok = [["login-nev", 404, {}]]
	_kitolt("Probaelek", "", "jelszo123")
	await _kuld_es_var()
	_ell(_allapot().begins_with("A fióknévvel belépés most nem érhető el"), "404 fióknévvel: „%s”" % _allapot().left(50))
	L.hivasok.clear()
	L.valaszok = [["login-nev", 404, {}], ["grant_type=password", 400, {"error": "invalid_grant", "error_description": "Invalid login credentials"}]]
	_kitolt("proba@pelda.hu", "", "jelszo123")
	await _kuld_es_var()
	_ell(L.hivott("grant_type=password") == 1 and ((L.hivasok[-1]["body"] as Dictionary).get("email") == "proba@pelda.hu"),
		"404 e-mail-címmel: a régi (e-mail + jelszó) úton próbálja")
	_ell(_allapot().begins_with("Nem sikerült: hibás"), "…és a rossz jelszót jól jelzi")

	_fej("6. Dupla beküldés (Enter + kattintás egy lassú kérés alatt)")
	L.hivasok.clear()
	L.kesleltetes = 0.6
	L.valaszok = [["login-nev", 400, {"error": "rossz_belepes"}], ["login-nev", 400, {"error": "rossz_belepes"}]]
	_kitolt("Probaelek", "", "jelszo123")
	L.acc_pass_edit.grab_focus()
	await _billentyu(KEY_ENTER)
	L.acc_fo_gomb.pressed.emit()
	await create_timer(1.6).timeout
	_ell(L.hivott("login-nev") == 1, "egy beküldés alatt csak EGY kérés megy ki (%d ment)" % L.hivott("login-nev"))
	L.kesleltetes = 0.0
	L.valaszok.clear()

	_fej("7. Regisztráció – a szerver válaszai")
	L._acc_mod_valt("regisztracio")
	L.hivasok.clear()
	L.valaszok = [["fioknev_szabad", 200, false]]
	_kitolt("Foglalt", "uj@pelda.hu", "jelszo1234")
	await _kuld_es_var()
	_ell(_allapot() == "Ezt a fióknevet már valaki használja. Válassz másikat.", "foglalt fióknév: „%s”" % _allapot())
	_ell(L.hivott("/auth/v1/signup") == 0, "foglalt névvel el sem küldi a regisztrációt (nincs fölösleges levél)")
	L.valaszok = [["fioknev_szabad", 200, true], ["/auth/v1/signup", 422, {"code": "user_already_exists", "msg": "User already registered"}]]
	_kitolt("Szabad", "van@pelda.hu", "jelszo1234")
	await _kuld_es_var()
	_ell(_allapot().begins_with("Ezzel az e-mail-címmel már van fiók"), "létező e-mail: „%s”" % _allapot().left(50))
	L.valaszok = [["fioknev_szabad", 200, true], ["/auth/v1/signup", 500, {"msg": "Database error saving new user"}]]
	_kitolt("Versenyzo", "uj2@pelda.hu", "jelszo1234")
	await _kuld_es_var()
	print("       (közben foglalt név – az adatbázis hibája: „%s”)" % _allapot().left(70))
	L.valaszok = [["fioknev_szabad", 200, true], ["/auth/v1/signup", 429, {"msg": "email rate limit exceeded"}]]
	_kitolt("Szabad", "uj3@pelda.hu", "jelszo1234")
	await _kuld_es_var()
	print("       (túl sok regisztráció – 429: „%s”)" % _allapot().left(70))
	L.valaszok = [["fioknev_szabad", 200, true], ["/auth/v1/signup", 0, {}]]
	_kitolt("Szabad", "uj4@pelda.hu", "jelszo1234")
	await _kuld_es_var()
	_ell(_allapot() == "Nem sikerült elérni a szervert. Van internet?", "regisztráció hálózat nélkül")
	L.hivasok.clear()
	L.valaszok = [["fioknev_szabad", 200, true], ["/auth/v1/signup", 200, {"id": "u1", "email": "uj@pelda.hu", "user_metadata": {"username": "Ujfiok"}}]]
	_kitolt("Ujfiok", "uj@pelda.hu", "jelszo1234")
	await _kuld_es_var()
	var sb: Dictionary = L.hivasok[-1]["body"]
	_ell(sb.get("email") == "uj@pelda.hu" and (sb.get("data", {}) as Dictionary).get("username") == "Ujfiok", "a regisztráció a nevet a data.username-ben küldi")
	_ell(str(L.acc_mod) == "belepes" and _allapot().begins_with("Kész: a fiókneved „Ujfiok”"), "megerősítő levél: vissza a belépéshez, „%s”" % _allapot().left(40))
	_ell(str(L.acc_user_edit.text) == "Ujfiok", "a fióknév mező már ki van töltve a belépéshez")
	_ell(not L._acc_logged_in() and _cfg_lemezen().get_value("account", "fioknev", "") == "Ujfiok", "nincs belépve, de a fióknevet megjegyezte")

	_fej("8. Elfelejtett jelszó – a szerver válaszai")
	L._acc_mod_valt("jelszo")
	L.hivasok.clear()
	L.valaszok = [["/auth/v1/recover", 200, {}]]
	L.acc_email_edit.text = "proba@pelda.hu"
	await _kuld_es_var()
	_ell(_allapot().begins_with("Ha van fiók ezzel a címmel, elküldtük"), "sikeres kérés: „%s”" % _allapot().left(45))
	_ell(str(L.hivasok[-1]["path"]).contains("redirect_to=https%3A%2F%2Fparthenon2-boop.github.io%2Fbirodalom%2Ffiok.html"),
		"a levél linkje a fiók weboldalára visz: %s" % str(L.hivasok[-1]["path"]).left(90))
	L.valaszok = [["/auth/v1/recover", 429, {}]]
	await _kuld_es_var()
	_ell(_allapot().begins_with("Túl sok kérés"), "429: „%s”" % _allapot())
	L.valaszok = [["/auth/v1/recover", 0, {}]]
	await _kuld_es_var()
	_ell(_allapot().begins_with("Nem sikerült elérni"), "hálózat nélkül")
	L.hivasok.clear()
	L.kesleltetes = 0.6
	L.valaszok = [["/auth/v1/recover", 200, {}], ["/auth/v1/recover", 429, {}]]
	L.acc_email_edit.grab_focus()
	await _billentyu(KEY_ENTER)
	L.acc_fo_gomb.pressed.emit()
	await create_timer(1.6).timeout
	_ell(L.hivott("/auth/v1/recover") == 1 and _allapot().begins_with("Ha van fiók"),
		"dupla beküldésre is csak EGY levelet kér (%d kérés), és a sikert írja ki" % L.hivott("/auth/v1/recover"))
	L.kesleltetes = 0.0
	L.valaszok.clear()

	_fej("9. Sikeres belépés, „Bejelentkezve maradok” BEKAPCSOLVA")
	L._acc_mod_valt("belepes")
	L.hivasok.clear()
	var jog := {"p": Marshalls.utf8_to_base64("{\"g\":\"heptarchia\"}"), "s": Marshalls.utf8_to_base64("alairas")}
	L.valaszok = [
		["login-nev", 200, SESSION],
		["/rest/v1/entitlements", 200, [{"dlc_key": "vikingek"}]],
		["dlc-access", 200, {"token": jog, "owned": ["vikingek"], "latest": {"vikingek": "vikingek-v9"}}],
		["dlc-access", 403, {"error": "not_owned"}],        # a letöltés linkjét már nem adja
	]
	_kitolt("Probaelek", "", "jelszo123")
	L._acc_kuld()
	await _var(func() -> bool: return not L.acc_popup.visible, 5.0)
	await _var(func() -> bool: return L.hivott("dlc-access") >= 2, 5.0)
	await _kockak(4)
	_ell(not L.acc_popup.visible, "sikeres belépés után az ablak bezárul")
	_ell(L._acc_logged_in() and str(L.acc_token) == "AT-proba", "belépve, a token a memóriában")
	var c := _cfg_lemezen()
	_ell(str(c.get_value("account", "refresh_token", "")) == "RT-proba", "a munkamenet kulcsa a beállításfájlba került")
	_ell(str(c.get_value("account", "fioknev", "")) == "Probaelek" and str(c.get_value("account", "email", "")) == "proba@pelda.hu", "fióknév és e-mail mentve")
	_ell(str(L.acc_top_btn.text).contains("Probaelek"), "a fejléc gombján a fióknév: %s" % str(L.acc_top_btn.text))
	_ell(str(c.get_value("dlc:vikingek", "license", "")) == "account", "a fiók kiegészítője megvásároltként jelenik meg")
	var jog_ut: String = _alap_mappa().path_join("Heptarchia/dlc_jog.json")
	var irt: Variant = JSON.parse_string(_fajl_szoveg(jog_ut))
	_ell(irt is Dictionary and irt == jog, "a dlc-access igazolása változatlanul a játék adatmappájába került")
	_ell((L._vedett_latest as Dictionary).get("vikingek", []) == ["vikingek-v9", ""], "a legújabb kiadás címkéje megjegyezve")
	var dl_hivas: Dictionary = {}
	for x: Dictionary in L.hivasok:
		if str(x["path"]).contains("dlc-access") and (x["body"] as Dictionary).has("download"): dl_hivas = x
	_ell(not dl_hivas.is_empty() and (dl_hivas["body"] as Dictionary)["download"] == "vikingek" and str(dl_hivas["token"]) == "AT-proba",
		"a hiányzó csomagot a fiók tokenjével kéri le")
	_ell(str(L.lbl_status.text).contains("nem jogosult"), "az elutasított letöltés oka kiíródik: „%s”" % str(L.lbl_status.text).left(80))
	var km: String = _alap_mappa().path_join("Kard és Mágia/fiok.json")
	var kmj: Variant = JSON.parse_string(_fajl_szoveg(km))
	_ell(kmj is Dictionary and str(kmj.get("refresh_token", "")) == "RT-proba", "a Kard és Mágia megkapta a munkamenetet")
	_ell(L.varatlan.is_empty(), "minden kérésre volt előre megírt válasz (%s)" % str(L.varatlan))
	L._open_account()
	await _kockak(3)
	_ell(not L.acc_login_box.visible and L.acc_out_box.visible and str(L.acc_who.text) == "Belépve: Probaelek", "belépve az ablak: „%s”" % str(L.acc_who.text))
	L.acc_popup.hide()

	_fej("10. Kijelentkezés")
	# egy fiókból jött, telepített csomag: kijelentkezéskor félre kell kerülnie
	var zip_ut: String = _alap_mappa().path_join("Heptarchia/dlc/vikingek.zip")
	var zar_ut: String = _alap_mappa().path_join("Heptarchia/dlc_zarolt/vikingek.zip")
	_zip_ir(zip_ut)
	L._acc_logout()
	await _kockak(3)
	c = _cfg_lemezen()
	_ell(not L._acc_logged_in() and str(L.acc_token) == "" and str(c.get_value("account", "refresh_token", "x")) == "", "a munkamenet törölve (memória + fájl)")
	_ell(str(c.get_value("dlc:vikingek", "license", "x")) == "", "a fiókból jött jog megszűnt")
	_ell(not FileAccess.file_exists(jog_ut), "a játék igazolása (dlc_jog.json) törölve")
	_ell((L._vedett_latest as Dictionary).is_empty(), "a kiadások listája is ürült")
	_ell(not FileAccess.file_exists(km), "a Kard és Mágia munkamenet-fájlja törölve")
	_ell(not FileAccess.file_exists(zip_ut) and FileAccess.file_exists(zar_ut), "a csomag a dlc_zarolt mappába került")
	_ell(str(L.acc_top_btn.text) == "Bejelentkezés / Regisztráció" and str(L.lbl_status.text) == "Kijelentkeztél.", "felület: kijelentkezve")
	_ell(str(c.get_value("account", "fioknev", "")) == "Probaelek", "a fióknevet megjegyzi a következő belépéshez")

	_fej("11. Sikeres belépés, „Bejelentkezve maradok” KIKAPCSOLVA")
	L._open_account()
	await _kockak(3)
	_ell(str(L.acc_user_edit.text) == "Probaelek", "az ablak a legutóbbi fióknévvel nyílik")
	L.acc_stay.button_pressed = false
	await _kockak(1)
	_ell(_cfg_lemezen().get_value("account", "maradjak", true) == false, "a kapcsoló állása mentve")
	L.valaszok = [["login-nev", 200, SESSION], ["/rest/v1/entitlements", 200, []], ["dlc-access", 200, {"token": jog, "owned": [], "latest": {}}]]
	L.acc_pass_edit.text = "jelszo123"
	L._acc_kuld()
	await _var(func() -> bool: return not L.acc_popup.visible, 5.0)
	await _kockak(6)
	c = _cfg_lemezen()
	_ell(L._acc_logged_in(), "most be van lépve")
	_ell(str(c.get_value("account", "refresh_token", "x")) == "", "a munkamenet kulcsa NEM került a beállításfájlba")
	kmj = JSON.parse_string(_fajl_szoveg(km))
	# Szándékos: a Kard és Mágiának a launcher kilépése után is kell a munkamenet (a launcher
	# indítás után bezárul), ezért a kulcs a játék fiok.json-jában a „maradjak” nélkül is ott marad.
	if kmj is Dictionary and str(kmj.get("refresh_token", "")) != "":
		print("  FIGYELEM a „Bejelentkezve maradok” kikapcsolva is a lemezen marad a munkamenet kulcsa: Kard és Mágia/fiok.json")
	var L2 = _uj_launcher()
	await _kockak(3)
	_ell(not L2._acc_logged_in(), "újraindítás után (új példány) nincs belépve")
	L2.queue_free()
	L._acc_logout(true)

	_fej("12. Induláskori megújítás (refresh)")
	c = ConfigFile.new()
	L.cfg.set_value("account", "refresh_token", "RT-regi")
	L.cfg.set_value("account", "maradjak", true)
	L.cfg.save("user://ParthLauncher.cfg")
	L.hivasok.clear()
	L.valaszok = [["grant_type=refresh_token", 400, {"error": "invalid_grant"}]]
	await L._acc_refresh()
	_ell(not L._acc_logged_in() and str(L.lbl_status.text).begins_with("A belépésed lejárt"), "lejárt kulcs: kijelentkezett állapot, „%s”" % str(L.lbl_status.text).left(40))
	_ell(((L.hivasok[0]["body"]) as Dictionary).get("refresh_token") == "RT-regi", "a mentett kulccsal próbálta")
	# a játék (Kard és Mágia) közben megújította: a fájljában frissebb kulcs van
	L.cfg.set_value("account", "refresh_token", "RT-regi")
	var f := FileAccess.open(km, FileAccess.WRITE)
	f.store_string(JSON.stringify({"refresh_token": "RT-jatektol"}))
	f.close()
	L.hivasok.clear()
	L.valaszok = [["grant_type=refresh_token", 400, {"error": "invalid_grant"}], ["grant_type=refresh_token", 200, SESSION],
		["/rest/v1/entitlements", 200, []], ["dlc-access", 200, {"token": jog, "owned": [], "latest": {}}]]
	await L._acc_refresh()
	_ell(L.hivott("grant_type=refresh_token") == 2 and ((L.hivasok[1]["body"]) as Dictionary).get("refresh_token") == "RT-jatektol",
		"elavult saját kulcs után a játék frissebb kulcsával próbálja")
	_ell(L._acc_logged_in() and str(L.cfg.get_value("account", "refresh_token", "")) == "RT-proba", "és azzal belép")
	L.valaszok = [["grant_type=refresh_token", 0, {}]]
	L.acc_token = ""
	await L._acc_refresh()
	_ell(str(L.cfg.get_value("account", "refresh_token", "")) == "RT-proba", "hálózat nélkül a mentett belépés megmarad")
	L._acc_logout(true)

	_fej("13. Valódi időtúllépés (helyi, soha nem válaszoló „proxy” – a kérés ki sem jut a gépről)")
	var szerver := TCPServer.new()
	var port := 0
	for p in range(47810, 47900):
		if szerver.listen(p, "127.0.0.1") == OK:
			port = p
			break
	var V = _uj_launcher(false)       # a valódi _acc_call
	await _kockak(2)
	V.proxy_host = "127.0.0.1"
	V.proxy_port = port
	var t0 := Time.get_ticks_msec()
	var r: Array = await V._acc_call(HTTPClient.METHOD_POST, "/functions/v1/login-nev", {"nev": "nincs", "password": "nincs"})
	var mp := (Time.get_ticks_msec() - t0) / 1000.0
	_ell(int(r[0]) == 0, "a válasz nélküli kérés hibaként tér vissza (kód %d, %.1f mp)" % [int(r[0]), mp])
	_ell(mp >= 25.0 and mp <= 40.0, "a 30 mp-es időkorlát működik (%.1f mp)" % mp)
	szerver.stop()
	V.proxy_port = port        # most már senki sem figyel: azonnali kapcsolódási hiba
	t0 = Time.get_ticks_msec()
	r = await V._acc_call(HTTPClient.METHOD_POST, "/functions/v1/login-nev", {"nev": "nincs", "password": "nincs"})
	_ell(int(r[0]) == 0, "elérhetetlen szerver: hibaként tér vissza (%d ms)" % (Time.get_ticks_msec() - t0))
	V.queue_free()
	_vege()
