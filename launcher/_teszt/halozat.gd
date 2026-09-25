extends "res://_teszt/_alap.gd"

# Nyilvános hálózati adatok (csak olvasás): a hírfolyam (docs/hirek.json) és a három játék
# GitHub-kiadása; a változatok összevetése, a melléklet kiválasztása, az indító saját
# változatszáma. A fiókszervert ez a teszt nem éri el.

var L = null

func _initialize() -> void:
	_orszem(120.0)
	_run.call_deferred()

func _gomb_also(i: int) -> String:
	return str(L.game_btns[i].text).get_slice("\n", 1)

func _run() -> void:
	if not _homokozo_rendben():
		_vege()
		return
	L = _uj_launcher()
	await _kockak(3)

	_fej("1. A hírfolyam (a weboldal docs/hirek.json-ja, élőben)")
	var home: Dictionary = L.GAMES[0]
	var rr: Array = L._repo_of(home)
	var url := "https://raw.githubusercontent.com/%s/%s/%s/%s" % [rr[0], rr[1], rr[2], L.NEWS_FILE]
	var szoveg: String = await L._fetch_text(url)
	var hirek: Variant = JSON.parse_string(szoveg) if szoveg != "" else null
	_ell(hirek is Array and not (hirek as Array).is_empty(), "letöltve és tömb (%d bájt, %d hír)" % [szoveg.length(), (hirek as Array).size() if hirek is Array else 0])
	if hirek is Array:
		var re := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$")
		var rossz: Array[String] = []
		for h: Variant in hirek:
			if not h is Dictionary or re.search(str((h as Dictionary).get("datum", ""))) == null or str((h as Dictionary).get("cim", "")) == "":
				rossz.append(str(h).left(60))
		_ell(rossz.is_empty(), "minden hírnek van dátuma (ÉÉÉÉ-HH-NN) és címe %s" % str(rossz))
		var cimkek := {}
		for h: Variant in hirek:
			if h is Dictionary: cimkek[str((h as Dictionary).get("cimke", ""))] = true
		print("       címkék: %s" % ", ".join(PackedStringArray(cimkek.keys())))
		var nincs_gazda: Array[String] = []
		for h: Variant in hirek:
			if not h is Dictionary: continue
			var van := false
			for g: Dictionary in L.GAMES:
				if L._news_of_game(h, g): van = true
			if not van: nincs_gazda.append(str((h as Dictionary).get("cimke", "")) + ": " + str((h as Dictionary).get("cim", "")).left(40))
		if not nincs_gazda.is_empty():
			print("       (egyik játékhoz sem sorolt hírek: %d – %s)" % [nincs_gazda.size(), str(nincs_gazda.slice(0, 4))])
		L._news = hirek
		for i in (L.GAMES as Array).size():
			L._load_game(i)
			L._show_news()
			await _kockak(1)
			var db := 0
			for h: Variant in hirek:
				if h is Dictionary and L._news_of_game(h, L.GAMES[i]): db += 1
			var sorok := 0
			var kartya_szoveg: Array[String] = []
			for n: Node in L.news_box.find_children("*", "HBoxContainer", true, false): sorok += 1
			for n: Node in L.news_box.find_children("*", "Label", true, false): kartya_szoveg.append(str((n as Label).text))
			_ell(sorok == mini(db, int(L.NEWS_MAX)) and L.news_box.visible == (db > 0),
				"%s: %d hír, ebből %d sor látszik" % [L._label_of(L.GAMES[i]), db, sorok])
			if db > 0:
				var datum_re := RegEx.create_from_string("^\\d{2}\\. \\d{2}\\.$")
				_ell(datum_re.search(kartya_szoveg[1]) != null, "   a dátum rövid alakja: „%s”" % kartya_szoveg[1])
		var hosszu := "Első mondat. " + "x".repeat(300)
		_ell(L._news_excerpt(hosszu) == "Első mondat.", "kivonat: az első mondat")
		var hosszu2: String = L._news_excerpt("y".repeat(300))
		_ell(hosszu2.length() <= 170 and hosszu2.ends_with("…"), "kivonat: 170 betűnél elvágja (%d)" % hosszu2.length())

	_fej("2. A játékok GitHub-kiadásai (élőben)")
	L.auto_update = false
	for i in (L.GAMES as Array).size():
		var g: Dictionary = L.GAMES[i]
		var r: Array = L._repo_of(g)
		var tx: String = await L._fetch_text("%s/repos/%s/%s/releases/latest" % [L.API, r[0], r[1]])
		var d: Variant = JSON.parse_string(tx) if tx != "" else null
		if not d is Dictionary:
			_ell(false, "%s: a legújabb kiadás lekérdezése (üres válasz – korlát vagy hálózat?)" % L._label_of(g))
			continue
		var tag := str((d as Dictionary).get("tag_name", ""))
		var assets: Array = (d as Dictionary).get("assets", [])
		var nevek: Array[String] = []
		for a: Dictionary in assets: nevek.append(str(a.get("name", "")))
		var valasztott: Dictionary = L._pick_asset(assets)
		L._load_game(i)
		var jatek_zip := str(valasztott.get("name", ""))
		_ell(tag != "" and jatek_zip.ends_with(".zip") and not jatek_zip.to_lower().contains("launcher") and not jatek_zip.to_lower().contains("mac"),
			"%s %s: a Windows-csomag „%s” (mellékletek: %s)" % [L._label_of(g), tag, jatek_zip, ", ".join(nevek)])
		# a launcher a kiadást ugyanígy dolgozza fel
		L.busy = true
		L.remote = {}
		L._on_release_checked(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), tx.to_utf8_buffer())
		_ell(str(L.remote.get("version", "")) == tag and str(L.remote.get("mode", "")) == "release" and not L.busy,
			"   feldolgozva: %s, %d MB" % [str(L.remote.get("version", "")), int(L.remote.get("size", 0)) / 1048576])
		if bool(g.get("home", false)):
			var ind: Dictionary = L._pick_launcher_asset(assets)
			_ell(not ind.is_empty(), "   az indító csomagja is megvan: %s" % str(ind.get("name", "")))
			var vtx: String = await L._fetch_text("https://raw.githubusercontent.com/%s/%s/%s/%s" % [r[0], r[1], tag, L.VERSION_FILE])
			var build := int(vtx.strip_edges())
			_ell(build > 0, "   a kiadott indító változata (launcher/VERSION.txt @ %s): %d" % [tag, build])
			var itt := int(L.LAUNCHER_BUILD)
			if build > itt: print("       FIGYELEM a kiadott indító (%d) újabb, mint ez a forrás (%d)" % [build, itt])
			elif build < itt: print("       (ez a forrás (%d) még nincs kiadva: a kiadott %d – a telepített indítók a következő címkéig nem frissülnek)" % [itt, build])
			else: print("       (a forrás és a kiadás egyforma: %d)" % itt)

	_fej("3. Változatok összevetése a listában és a nagy gombon")
	L._load_game(1)
	var kulcs := "heptarchia"
	L.remote = {}
	L.latest_ver = {}
	L.installed_version = ""
	L._refresh_labels()
	_ell(_gomb_also(1) == "változat: ?", "semmi sem ismert: „%s”" % _gomb_also(1))
	L.latest_ver[kulcs] = "v1.66"
	L._refresh_labels()
	_ell(_gomb_also(1) == "v1.66 – letölthető", "nincs telepítve: „%s”" % _gomb_also(1))
	L.installed_version = "v1.65"
	L._refresh_labels()
	_ell(_gomb_also(1) == "v1.65 → v1.66", "elavult: „%s”" % _gomb_also(1))
	L.installed_version = "v1.66"
	L._refresh_labels()
	_ell(_gomb_also(1) == "v1.66 – naprakész", "naprakész: „%s”" % _gomb_also(1))
	L.latest_ver.erase(kulcs)
	L._refresh_labels()
	_ell(_gomb_also(1) == "telepítve: v1.66", "csak a telepített ismert: „%s”" % _gomb_also(1))
	# a másik játék sora a beállításból
	L.cfg.set_value("state:birodalom", "version", "v1.36")
	L.latest_ver["birodalom"] = "v1.43"
	L._refresh_labels()
	_ell(_gomb_also(0) == "v1.36 → v1.43", "a nem kiválasztott játék sora is: „%s”" % _gomb_also(0))
	# a nagy gomb
	L.remote = {"mode": "release", "version": "v1.67", "url": "", "size": 0}
	L.installed_version = "v1.66"
	L._refresh_labels()
	_ell(str(L.lbl_latest.text) == "Elérhető frissítés: v1.67" and str(L.btn_main.text) == "Frissítés" and not L.btn_main.disabled,
		"újabb változat: „%s”, gomb: %s" % [L.lbl_latest.text, L.btn_main.text])
	L.installed_version = "v1.67"
	L._refresh_labels()
	_ell(str(L.lbl_latest.text) == "Naprakész (v1.67)" and str(L.btn_main.text) == "Újratöltés", "azonos, de nincs telepítve: „%s”, gomb: %s" % [L.lbl_latest.text, L.btn_main.text])
	L.installed_version = "v1.68"
	L._refresh_labels()
	print("       (a telepített v1.68 újabb, mint a kiadott v1.67: „%s”, gomb: %s)" % [L.lbl_latest.text, L.btn_main.text])
	L.launcher_update = 41
	L._refresh_labels()
	_ell(str(L.btn_main.text) == "Indító frissítése", "ha az indítónak van újabb változata, az az első")
	L.launcher_update = 0
	L.remote = {}
	L._refresh_labels()
	_ell(str(L.btn_main.text) == "Bejelentkezés" and not L.btn_main.disabled, "belépés nélkül, nincs mit tölteni: Bejelentkezés (%s)" % str(L.btn_main.text))

	_fej("4. Melléklet-választás, proxy, zip-előtag, csereszkript")
	var minta := [{"name": "ParthLauncher-windows.zip"}, {"name": "Heptarchia-macOS.zip"}, {"name": "Heptarchia-windows.zip"},
		{"name": "Source code.zip"}, {"name": "ParthLauncher-macOS.zip"}]
	_ell(str(L._pick_asset(minta).get("name", "")) == "Heptarchia-windows.zip", "a játék Windows-csomagja: %s" % str(L._pick_asset(minta).get("name", "")))
	_ell(str(L._pick_launcher_asset(minta).get("name", "")) == "ParthLauncher-windows.zip", "az indító Windows-csomagja")
	_ell((L._pick_asset([{"name": "ParthLauncher-windows.zip"}]) as Dictionary).is_empty(), "csak indító-csomagnál nincs játék")
	L._set_proxy("http://proxy.iskola.hu:3128/")
	_ell(str(L.proxy_host) == "proxy.iskola.hu" and int(L.proxy_port) == 3128, "proxy: %s:%d" % [L.proxy_host, L.proxy_port])
	L._set_proxy("proxy")
	_ell(int(L.proxy_port) == 8080, "port nélkül 8080")
	L._set_proxy("")
	_ell(str(L.proxy_text()) == "", "üres proxy")
	_ell(str(L._common_prefix(PackedStringArray(["abc-123/a.txt", "abc-123/b/c.txt"]))) == "abc-123/", "GitHub-zip: a közös mappa levágva")
	_ell(str(L._common_prefix(PackedStringArray(["Heptarchia.app/Contents/x", "Heptarchia.app/Contents/y"]))) == "", "macOS .app: nem vágja le")
	var bat: String = L.windows_swap_script("C:/a b/ParthLauncher.exe", "C:/t/uj.exe", "C:/t")
	_ell(bat.contains("copy /y \"C:\\t\\uj.exe\" \"C:\\a b\\ParthLauncher.exe\"") and bat.contains("explorer.exe \"C:\\a b\\ParthLauncher.exe\""),
		"a csereszkript idézőjelezi a szóközös útvonalat")
	_vege()
