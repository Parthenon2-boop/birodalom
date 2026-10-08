class_name FelhoMentes
extends Node
## Felhő-mentés: a játék mentésmappáját a FIÓKHOZ köti, nem a géphez.
##
## KÖZÖS MODUL — ugyanez a fájl van minden ParthLauncher-játékban (Kard és Mágia, Heptarchia,
## Birodalom, Antiquitas, Saecula). Ha javítasz rajta, másold át a többibe is.
##
## Mit csinál: a megadott mappa mentésfájljait tükrözi a kiszolgáló `felho_mentes` táblájába
## (Supabase; lásd Birodalom_Godot/server/supabase/schema_felho_mentes.sql). Egy másik gépen
## belépve a mentések maguktól megjelennek a játék saját mentéslistájában — a játéknak csak
## szólnia kell, amikor ment vagy töröl:
##
##     felho.indit("kard_es_magia", "user://mentesek/", ["json"])   # induláskor
##     felho.szinkron()                                             # később bármikor (pl. a mentéslista megnyitásakor)
##     felho.feltolt("valami.json")                                 # mentés után
##     felho.torol("valami.json")                                   # törlés után
##     felho.valtozott.connect(...)                                 # ha a felhőből jött / tűnt el fájl
##
## A fiókot a ParthLauncher adja át: a játék adatmappájába írt `fiok.json`
## ({url, anon, access_token, refresh_token, ...}). Ha nincs ilyen fájl (a játék nem a
## launcherből indult, vagy nincs belépve), a modul csendben nem csinál semmit: a mentés
## helyben ugyanúgy működik. Minden hálózati hívás aszinkron, és soha nem dob hibát a játékra.
##
## Ütközés: ha ugyanaz a mentés két gépen is megváltozott, az újabb (későbbi módosítású) nyer.
## Törlés: a kiszolgálón „sírkő” marad, így a másik gépen is eltűnik, és nem töltődik vissza.

signal valtozott                 ## a szinkron letöltött vagy törölt helyi fájlt: frissítsd a listát
signal allapot_valtozott         ## az `allapot` megváltozott (felirat / ikon frissítéséhez)

const FIOK := "user://fiok.json"
const NAPLO := "user://felho_allapot.json"   # mit szinkronizáltunk utoljára (fájlonként)
const TABLA := "/rest/v1/felho_mentes"
const MAX_BAJT := 8 * 1024 * 1024            # ennél nagyobb mentést nem töltünk fel

## "ki": nincs fiók · "var": még nem futott · "megy": szinkron folyik · "kesz" · "hiba"
var allapot := "ki"
var hiba := ""                   # az utolsó hiba rövid kódja ("halozat", "belepes", "tul_sok_mentes"...)
var jatek := ""
var mappa := "user://mentesek/"
var kiterjesztesek: Array = []   # pl. ["json"]; üres = minden fájl
var kihagy: Array = []           # ezeket a fájlneveket sosem töltjük fel
var csak: Array = []             # ha nem üres: KIZÁRÓLAG ezek a fájlnevek (pl. ["save.json"])
var utolso_szinkron := 0         # unix mp
var felhoben := {}               # fájlnév -> true: ami a kiszolgálón is megvan (a listához)
## teszthez: ha igaz, nem indul valódi kérés (minden kérés "nincs hálózat" választ kap)
var offline_mod := false

var _url := ""
var _anon := ""
var _access := ""
var _refresh := ""
var _naplo := {}                 # fájlnév -> {"ido": felhő-idő, "helyi": helyi módosítási idő}
var _sor: Array = []             # várakozó műveletek: {"mit": "szinkron" | "fel" | "torol", "nev": ...}
var _dolgozik := false


# ══════════ INDÍTÁS ══════════
## Beállítás és az első szinkron. Bármikor újra hívható (pl. más mappával).
func indit(jatek_id: String, mentes_mappa: String, kit: Array = [], kihagyando: Array = [], csak_ezek: Array = []) -> void:
	jatek = jatek_id
	csak = csak_ezek
	mappa = mentes_mappa if mentes_mappa.ends_with("/") else mentes_mappa + "/"
	kiterjesztesek = kit
	kihagy = kihagyando
	_naplo = _olvas_json(NAPLO).get(jatek, {}) if _olvas_json(NAPLO).get(jatek, {}) is Dictionary else {}
	if _fiok_olvas():
		_allapot("var")
		szinkron()
	else:
		_allapot("ki")


func be_van_lepve() -> bool:
	return _url != "" and _access != ""


func _allapot(a: String, h := "") -> void:
	if allapot == a and hiba == h:
		return
	allapot = a
	hiba = h
	allapot_valtozott.emit()


# ══════════ A JÁTÉK HÍVJA ══════════
## Teljes szinkron: letölti, ami a felhőben újabb, feltölti, ami itt újabb.
func szinkron() -> void:
	if not _fiok_olvas():
		_allapot("ki")
		return
	for m in _sor:
		if m["mit"] == "szinkron":
			return
	_sor.append({"mit": "szinkron"})
	_kovetkezo()


## Egy mentés most készült el (vagy felülíródott): menjen fel a felhőbe.
func feltolt(nev: String) -> void:
	if jatek == "" or not _ide_tartozik(nev) or not _fiok_olvas():
		return
	for m in _sor:
		if m["mit"] == "fel" and m["nev"] == nev:
			return
	_sor.append({"mit": "fel", "nev": nev})
	_kovetkezo()


## Egy mentést a játékos törölt: a felhőből (és így a többi gépről) is tűnjön el.
func torol(nev: String) -> void:
	if jatek == "" or not _ide_tartozik(nev):
		return
	felhoben.erase(nev)
	if not _fiok_olvas():
		return   # belépés nélkül a napló megmarad: a következő szinkron észreveszi a hiányt
	_sor.append({"mit": "torol", "nev": nev})
	_kovetkezo()


## Van-e ennek a fájlnak példánya a felhőben (a mentéslista kis felhő-jeléhez).
func felhoben_van(nev: String) -> bool:
	return felhoben.has(nev)


# ══════════ FÁJLOK ══════════
func _ide_tartozik(nev: String) -> bool:
	if nev == "" or nev.begins_with(".") or nev in kihagy or nev.contains("/") or nev.contains("\\"):
		return false
	if not csak.is_empty():
		return nev in csak
	if nev.ends_with(".letoltes") or nev.ends_with(".tmp"):
		return false
	if kiterjesztesek.is_empty():
		return true
	return nev.get_extension().to_lower() in kiterjesztesek


## a mappa mentésfájljai: fájlnév -> módosítási idő (unix mp)
func helyi_fajlok() -> Dictionary:
	var out := {}
	var d := DirAccess.open(mappa)
	if d == null:
		return out
	for f in d.get_files():
		if _ide_tartozik(f):
			out[f] = int(FileAccess.get_modified_time(mappa + f))
	return out


static func _olvas_json(ut: String) -> Dictionary:
	if not FileAccess.file_exists(ut):
		return {}
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(ut)) != OK or not (j.data is Dictionary):
		return {}
	return j.data


func _naplo_ment() -> void:
	var mind := _olvas_json(NAPLO)
	mind[jatek] = _naplo
	var f := FileAccess.open(NAPLO, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(mind))
		f.close()


## fájl -> gzip + base64 ("" ha nincs, vagy túl nagy)
static func csomagol(ut: String) -> String:
	var b := FileAccess.get_file_as_bytes(ut)
	if b.is_empty() or b.size() > MAX_BAJT:
		return ""
	return Marshalls.raw_to_base64(b.compress(FileAccess.COMPRESSION_GZIP))


## gzip + base64 -> bájtok (üres, ha sérült)
static func kicsomagol(adat: String) -> PackedByteArray:
	if adat == "" or adat.length() % 4 != 0:
		return PackedByteArray()
	for i in mini(adat.length(), 64):   # gyors ellenőrzés: tényleg base64-nek látszik-e
		var ch := adat.unicode_at(i)
		if not ((ch >= 48 and ch <= 57) or (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) or ch == 43 or ch == 47 or ch == 61):
			return PackedByteArray()
	var z := Marshalls.base64_to_raw(adat)
	if z.is_empty():
		return PackedByteArray()
	return z.decompress_dynamic(MAX_BAJT * 2, FileAccess.COMPRESSION_GZIP)


# ══════════ DÖNTÉS: mi történjen egy fájllal? ══════════
## Tiszta függvény (hálózat nélkül tesztelhető).
##   helyi: a helyi fájl módosítási ideje, vagy -1, ha nincs
##   napl:  {"ido", "helyi"} — amit utoljára szinkronizáltunk, vagy {} ha még soha
##   felho: {"ido", "torolt"} — a kiszolgáló sora, vagy {} ha nincs
## Válasz: "" (semmi) | "fel" | "le" | "torol_helyi" | "torol_felho" | "felejt"
static func dont(helyi: int, napl: Dictionary, felho: Dictionary) -> String:
	var van_helyi := helyi >= 0
	var volt := not napl.is_empty()
	var helyi_valtozott := van_helyi and (not volt or helyi != int(napl.get("helyi", -1)))
	var helyi_torolve := not van_helyi and volt
	if felho.is_empty():
		if van_helyi:
			return "fel"
		return "felejt" if volt else ""
	var f_ido := int(felho.get("ido", 0))
	var felho_valtozott := not volt or f_ido != int(napl.get("ido", -1))
	if bool(felho.get("torolt", false)):
		if van_helyi and helyi_valtozott and helyi > f_ido:
			return "fel"            # a törlés UTÁN újra mentették: éljen tovább
		if van_helyi:
			return "torol_helyi"
		return "felejt" if volt else ""
	if helyi_torolve:
		return "le" if felho_valtozott else "torol_felho"
	if not van_helyi:
		return "le"
	if helyi_valtozott and felho_valtozott:
		return "fel" if helyi > f_ido else ("le" if f_ido > helyi else "")
	if helyi_valtozott:
		return "fel"
	if felho_valtozott:
		return "le"
	return ""


# ══════════ A VÁRÓSOR ══════════
func _kovetkezo() -> void:
	if _dolgozik or _sor.is_empty():
		return
	_dolgozik = true
	var m: Dictionary = _sor.pop_front()
	match m["mit"]:
		"szinkron": _szinkron_fut()
		"fel": _fel(str(m["nev"]), _kesz)
		"torol": _sirko(str(m["nev"]), _kesz)


func _kesz(_ok := true) -> void:
	_dolgozik = false
	_kovetkezo()


func _szinkron_fut() -> void:
	_allapot("megy")
	_leker(TABLA + "?select=nev,ido,torolt&jatek=eq." + jatek.uri_encode(), func(kod: int, t: String) -> void:
		var j: Variant = JSON.parse_string(t) if kod == 200 else null
		if not (j is Array):
			_allapot("hiba", "halozat" if kod == 0 else ("belepes" if kod == 401 or kod == 403 else "szerver"))
			_kesz()
			return
		var felho := {}
		for e in (j as Array):
			if e is Dictionary and _ide_tartozik(str(e.get("nev", ""))):
				felho[str(e["nev"])] = {"ido": int(e.get("ido", 0)), "torolt": bool(e.get("torolt", false))}
		var helyi := helyi_fajlok()
		var nevek := {}
		for n in helyi: nevek[n] = true
		for n in felho: nevek[n] = true
		for n in _naplo: nevek[n] = true
		var teendo: Array = []
		felhoben = {}
		for n in nevek:
			var mit := dont(int(helyi.get(n, -1)), _naplo.get(n, {}), felho.get(n, {}))
			if felho.has(n) and not felho[n]["torolt"] and mit != "torol_felho":
				felhoben[n] = true
			if mit != "":
				teendo.append([n, mit, felho.get(n, {})])
		_teendok(teendo, 0, false))


## A teendők egymás után (egyszerre egy kérés fut).
func _teendok(lista: Array, i: int, helyi_valtozas: bool) -> void:
	if i >= lista.size():
		_naplo_ment()
		utolso_szinkron = int(Time.get_unix_time_from_system())
		if allapot == "megy":
			_allapot("kesz")
		if helyi_valtozas:
			valtozott.emit()
		_kesz()
		return
	var n: String = lista[i][0]
	var tovabb := func(_ok := true) -> void: _teendok(lista, i + 1, helyi_valtozas)
	match str(lista[i][1]):
		"fel": _fel(n, tovabb)
		"torol_felho": _sirko(n, tovabb)
		"felejt":
			_naplo.erase(n)
			tovabb.call()
		"torol_helyi":
			if FileAccess.file_exists(mappa + n):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(mappa + n))
			_naplo.erase(n)
			_teendok(lista, i + 1, true)
		"le":
			_le(n, int((lista[i][2] as Dictionary).get("ido", 0)), func(ok: bool) -> void:
				_teendok(lista, i + 1, helyi_valtozas or ok))
		_: tovabb.call()


func _fel(nev: String, kesz: Callable) -> void:
	var ut := mappa + nev
	if not FileAccess.file_exists(ut):
		kesz.call(false)
		return
	var adat := csomagol(ut)
	if adat == "":
		kesz.call(false)
		return
	var ido := int(FileAccess.get_modified_time(ut))
	var test := JSON.stringify({"jatek": jatek, "nev": nev, "ido": ido, "torolt": false,
		"meret": FileAccess.get_file_as_bytes(ut).size(), "adat": adat})
	_kuld(TABLA + "?on_conflict=user_id,jatek,nev", test, func(kod: int, t: String) -> void:
		if kod >= 200 and kod < 300:
			_naplo[nev] = {"ido": ido, "helyi": ido}
			felhoben[nev] = true
			_naplo_ment()
			if allapot != "megy":
				_allapot("kesz")
			kesz.call(true)
		else:
			var h := "halozat" if kod == 0 else "szerver"
			for k in ["tul_sok_mentes", "betelt_a_tarhely"]:
				if t.contains(k):
					h = k
			_allapot("hiba", h)
			kesz.call(false))


func _sirko(nev: String, kesz: Callable) -> void:
	var test := JSON.stringify({"jatek": jatek, "nev": nev, "ido": int(Time.get_unix_time_from_system()),
		"torolt": true, "meret": 0, "adat": ""})
	_kuld(TABLA + "?on_conflict=user_id,jatek,nev", test, func(kod: int, _t: String) -> void:
		if kod >= 200 and kod < 300:
			_naplo.erase(nev)
			felhoben.erase(nev)
			_naplo_ment()
			kesz.call(true)
		else:
			kesz.call(false))   # a napló megmarad: a következő szinkron újra megpróbálja


func _le(nev: String, ido: int, kesz: Callable) -> void:
	_leker(TABLA + "?select=adat&jatek=eq.%s&nev=eq.%s" % [jatek.uri_encode(), nev.uri_encode()], func(kod: int, t: String) -> void:
		var j: Variant = JSON.parse_string(t) if kod == 200 else null
		if not (j is Array) or (j as Array).is_empty() or not ((j as Array)[0] is Dictionary):
			kesz.call(false)
			return
		var b := kicsomagol(str((j as Array)[0].get("adat", "")))
		if b.is_empty():
			kesz.call(false)
			return
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(mappa))
		# előbb ideiglenes fájlba írunk: félbeszakadt letöltés ne rontson el meglévő mentést
		var tmp := mappa + nev + ".letoltes"
		var f := FileAccess.open(tmp, FileAccess.WRITE)
		if f == null:
			kesz.call(false)
			return
		f.store_buffer(b)
		f.close()
		if FileAccess.file_exists(mappa + nev):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(mappa + nev))
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(mappa + nev)) != OK:
			kesz.call(false)
			return
		_naplo[nev] = {"ido": ido, "helyi": int(FileAccess.get_modified_time(mappa + nev))}
		felhoben[nev] = true
		kesz.call(true))


# ══════════ FIÓK ÉS HTTP ══════════
## A launcher által írt fiok.json beolvasása. Igaz, ha van használható belépés.
func _fiok_olvas() -> bool:
	var d := _olvas_json(FIOK)
	var u := str(d.get("url", "")).strip_edges().rstrip("/")
	var a := str(d.get("anon", "")).strip_edges()
	if u == "" or a == "" or str(d.get("access_token", "")) == "":
		_url = ""
		_access = ""
		return false
	_url = u
	_anon = a
	_access = str(d["access_token"])
	_refresh = str(d.get("refresh_token", ""))
	return true


func _fejek() -> PackedStringArray:
	return PackedStringArray(["apikey: " + _anon, "Authorization: Bearer " + _access,
		"Content-Type: application/json", "Prefer: resolution=merge-duplicates,return=minimal"])


func _keres(mod: int, cim: String, fejek: PackedStringArray, test: String, kesz: Callable) -> void:
	if offline_mod or not is_inside_tree():
		kesz.call(0, "")
		return
	var r := HTTPRequest.new()
	r.timeout = 20.0
	add_child(r)
	r.request_completed.connect(func(_res: int, kod: int, _h: PackedStringArray, valasz: PackedByteArray) -> void:
		r.queue_free()
		kesz.call(kod, valasz.get_string_from_utf8()))
	if r.request(cim, fejek, mod, test) != OK:
		r.queue_free()
		kesz.call(0, "")


func _leker(ut: String, kesz: Callable, ujra := true) -> void:
	_keres(HTTPClient.METHOD_GET, _url + ut, _fejek(), "", func(kod: int, t: String) -> void:
		if (kod == 401 or kod == 403) and ujra:
			_ujit(func(ok: bool) -> void:
				if ok: _leker(ut, kesz, false)
				else: kesz.call(kod, t))
			return
		kesz.call(kod, t))


func _kuld(ut: String, test: String, kesz: Callable, ujra := true) -> void:
	_keres(HTTPClient.METHOD_POST, _url + ut, _fejek(), test, func(kod: int, t: String) -> void:
		if (kod == 401 or kod == 403) and ujra:
			_ujit(func(ok: bool) -> void:
				if ok: _kuld(ut, test, kesz, false)
				else: kesz.call(kod, t))
			return
		kesz.call(kod, t))


## Lejárt belépés. A kiszolgáló minden megújításkor ÚJ frissítő kulcsot ad, és a fiókot a
## launcher meg a játék többi része is használja — ezért előbb megnézzük, nem írt-e valaki
## már frissebb kulcsot a fiok.json-ba; csak ha nem, akkor újítunk mi (és visszaírjuk).
func _ujit(kesz: Callable) -> void:
	var regi := _access
	if _fiok_olvas() and _access != regi:
		kesz.call(true)
		return
	if _refresh == "":
		kesz.call(false)
		return
	_keres(HTTPClient.METHOD_POST, _url + "/auth/v1/token?grant_type=refresh_token",
		PackedStringArray(["apikey: " + _anon, "Content-Type: application/json"]),
		JSON.stringify({"refresh_token": _refresh}), func(kod: int, t: String) -> void:
			var j: Variant = JSON.parse_string(t) if kod == 200 else null
			if j is Dictionary and str((j as Dictionary).get("access_token", "")) != "":
				_access = str(j["access_token"])
				if str((j as Dictionary).get("refresh_token", "")) != "":
					_refresh = str(j["refresh_token"])
				var d := _olvas_json(FIOK)
				d["access_token"] = _access
				d["refresh_token"] = _refresh
				d["mentve"] = int(Time.get_unix_time_from_system())
				var f := FileAccess.open(FIOK, FileAccess.WRITE)
				if f != null:
					f.store_string(JSON.stringify(d))
					f.close()
				kesz.call(true)
			else:
				kesz.call(false))
