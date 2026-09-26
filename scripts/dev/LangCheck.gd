extends SceneTree

# NYELVI FÁJLOK ELLENŐRZÉSE — fejlesztői eszköz, a kiadásba nem kerül bele.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://scripts/dev/LangCheck.gd
#
# Megnézi, hogy
#   1. a hu/en/de fájlban pontosan ugyanazok a kulcsok vannak, és egyik
#      érték sem üres;
#   2. a formázójelek (%d, %s, %.0f, %%) nyelvenként ugyanazok — különben a
#      `Lang.t(k) % [...]` futás közben elhasal;
#   3. minden kulcs, amit a kód használ, megvan mindhárom fájlban. A kódot
#      szövegként olvassuk (nem töltjük be a szkripteket, mert az autoloadok
#      itt nem élnek): a `Lang.t("kulcs")` alakokat, a kulcsot váró
#      segédfüggvények (_mbtn, _check, _section…) szó szerinti paramétereit,
#      és a kódban összerakott kulcscsaládokat (u_<szerep>, e_<épület>,
#      r_<nemzet>_<korszak>…) az adattáblákból kinyerve.
# Kilépési kód: 0 = rendben, 1 = hiba.

const NYELVEK := ["hu", "en", "de"]
const KIHAGY := ["res://scripts/dev/", "res://launcher/", "res://.godot/"]

var _hibak: Array[String] = []
var _hasznalt_db: int = 0

func _init() -> void:
	var fajlok := {}
	for c in NYELVEK:
		fajlok[c] = _json("res://assets/lang/%s.json" % c)
		if (fajlok[c] as Dictionary).is_empty():
			_hibak.append("%s.json nem olvasható" % c)
	if _hibak.is_empty():
		_paritas(fajlok)
		_hasznalt(fajlok)
	if _hibak.is_empty():
		print("LANGCHECK OK — %d kulcs, ebből %d a kódban hivatkozott; mindhárom nyelv teljes" % [(fajlok["hu"] as Dictionary).size(), _hasznalt_db])
		quit(0)
	else:
		for h in _hibak: print("LANGCHECK HIBA: ", h)
		print("LANGCHECK: %d hiba" % _hibak.size())
		quit(1)

func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func _szoveg(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""

# --- 1–2. Egyezés a nyelvek között ---

func _paritas(fajlok: Dictionary) -> void:
	var hu: Dictionary = fajlok["hu"]
	var jel := RegEx.create_from_string("%[-+0-9.]*[dsfxX%]")
	for c in NYELVEK:
		var d: Dictionary = fajlok[c]
		for k in hu:
			if not d.has(k): _hibak.append("%s.json: hiányzik a(z) %s" % [c, k])
		for k in d:
			if not hu.has(k): _hibak.append("%s.json: fölösleges kulcs %s (a hu.json-ban nincs)" % [c, k])
			elif str(d[k]).strip_edges() == "": _hibak.append("%s.json: üres érték %s" % [c, k])
	for k in hu:
		var minta := _jelek(jel, str(hu[k]))
		for c in ["en", "de"]:
			var d2: Dictionary = fajlok[c]
			if d2.has(k) and _jelek(jel, str(d2[k])) != minta:
				_hibak.append("%s.json: %s formázójelei eltérnek (%s ≠ hu %s)" %
					[c, k, str(_jelek(jel, str(d2[k]))), str(minta)])

func _jelek(re: RegEx, s: String) -> Array:
	var out: Array = []
	for m in re.search_all(s): out.append(m.get_string().replace(".0", "").replace(".1", ""))
	return out

# --- 3. A kódban használt kulcsok ---

func _hasznalt(fajlok: Dictionary) -> void:
	var kulcsok := {}
	var forras := ""
	for p in _gd_fajlok("res://"):
		forras += _szoveg(p) + "\n"
	# a) Lang.t("kulcs") — a formázott ("kor_%d") alakot a családok fedik le.
	for m in RegEx.create_from_string("Lang\\.t\\(\"([a-z][a-z0-9_]*)\"\\)").search_all(forras):
		kulcsok[m.get_string(1)] = "Lang.t"
	# b) Kulcsot váró segédfüggvények szó szerinti paramétere.
	var seged := RegEx.create_from_string(
		"(?:_mbtn|_section|_check|_slider|_mp_section|_pick_row|_kulcs)\\([^\\n\"]*?\"([a-z][a-z0-9_]*)\"")
	for m in seged.search_all(forras):
		kulcsok[m.get_string(1)] = "segédfüggvény"
	# A _pick_row gombsorai és a _mp_section leírása: minden kulcs a sorban.
	for m in RegEx.create_from_string("(?:_pick_row|_mp_section)\\(([^\\n]*)").search_all(forras):
		for s in RegEx.create_from_string("\"([a-z][a-z0-9_]*)\"").search_all(m.get_string(1)):
			kulcsok[s.get_string(1)] = "segédfüggvény"
	# c) Kulcslisták a kódban (…_KEYS / *_keys / VET_KULCS / HAJO_NEV / RES_KEY).
	for m in RegEx.create_from_string("(?:_KEYS|_keys|VET_KULCS)\\s*:?=\\s*\\[([^\\]]*)\\]").search_all(forras):
		for s in RegEx.create_from_string("\"([a-z][a-z0-9_]*)\"").search_all(m.get_string(1)):
			kulcsok[s.get_string(1)] = "kulcslista"
	for m in RegEx.create_from_string("(?:HAJO_NEV|RES_KEY|HUD_RES)\\s*:?=\\s*\\{([^}]*)\\}").search_all(forras):
		for s in RegEx.create_from_string(":\\s*\"([a-z][a-z0-9_]*)\"").search_all(m.get_string(1)):
			kulcsok[s.get_string(1)] = "kulcstábla"
	# d) Összerakott kulcscsaládok az adattáblákból.
	for k in _csaladok(): kulcsok[k] = "kulcscsalád"
	_hasznalt_db = kulcsok.size()
	for k in kulcsok:
		for c in NYELVEK:
			if not (fajlok[c] as Dictionary).has(k):
				_hibak.append("%s.json: a kód használja (%s), de hiányzik: %s" % [c, kulcsok[k], k])

func _gd_fajlok(dir: String) -> Array[String]:
	var out: Array[String] = []
	for kihagy in KIHAGY:
		if dir.begins_with(kihagy): return out
	var d := DirAccess.open(dir)
	if d == null: return out
	for f in d.get_files():
		if f.ends_with(".gd"): out.append(dir.path_join(f))
	for sub in d.get_directories():
		if sub.begins_with("."): continue
		out.append_array(_gd_fajlok(dir.path_join(sub) + "/"))
	return out

func _lista(fajl: String, minta: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.create_from_string(minta)
	for m in re.search_all(_szoveg(fajl)):
		out.append(m.get_string(1))
	return out

# Egy `const NEV := [ ... ]` tömb szövegelemei.
func _const_tomb(fajl: String, nev: String) -> Array[String]:
	var out: Array[String] = []
	var m := RegEx.create_from_string("const " + nev + "\\s*:?=\\s*\\[([^\\]]*)\\]").search(_szoveg(fajl))
	if m == null:
		_hibak.append("%s: nem találom a %s tömböt" % [fajl, nev])
		return out
	for s in RegEx.create_from_string("\"([^\"]+)\"").search_all(m.get_string(1)):
		out.append(s.get_string(1))
	return out

func _csaladok() -> Array[String]:
	var k: Array[String] = []
	for a in range(4):
		k.append_array(["kor_%d" % a, "kor_nev_%d" % a, "kor_alcim_%d" % a])
	# Nemzetek: név, állam- és uralkodónév korszakonként, rangok.
	var style := "res://scripts/ui/Style.gd"
	var nemzetek := _const_tomb(style, "NATION_ORDER") + _const_tomb(style, "PIRATE_ORDER")
	for n in nemzetek:
		k.append("n_" + n)
		for a in range(4):
			k.append("r_%s_%d" % [n, a])
			k.append("allam_%s_%d" % [n, a])
	for blokk in _lista(style, "\"titles\":\\s*\\[([^\\]]*)\\]"):
		for s in RegEx.create_from_string("\"([^\"]+)\"").search_all(blokk):
			k.append(_rang_kulcs(s.get_string(1)))
	# Épületek és egységek.
	var bld := "res://scripts/buildings/Building.gd"
	for t in _lista(bld, "(?m)^\\s*\"([a-z_]+)\":\\s*\\{\"hp\""):
		k.append("e_" + t)
	for blokk in _lista(bld, "\"trains\":\\s*\\[([^\\]]*)\\]"):
		for s in RegEx.create_from_string("\"([a-z_]+)\"").search_all(blokk):
			k.append("u_" + s.get_string(1))
	for t in _const_tomb("res://scripts/ui/HUD.gd", "BUILDABLE"): k.append("e_" + t)
	# Fejlesztések, teljesítmények, oktató, billentyűk, harci gombok.
	for u in _const_tomb("res://scripts/systems/Upgrades.gd", "ORDER"):
		k.append_array(["upg_" + u, "upg_leiras_" + u])
	for id in _lista("res://scripts/globals/Achievements.gd", "\\{\"id\":\\s*\"([a-z_]+)\""):
		k.append_array(["ach_" + id, "ach_" + id + "_d"])
	for s in _const_tomb("res://scripts/systems/Tutorial.gd", "STEPS"): k.append("okt_" + s)
	k.append("okt_kesz")
	var sett := "res://scripts/globals/Settings.gd"
	for a in _lista(sett, "\\{\"k\":\\s*\"([a-z_]+)\""): k.append("kb_" + a)
	for cs in _lista(sett, "\"csoport\":\\s*\"([a-z_]+)\""): k.append(cs)
	var unit := "res://scripts/units/Unit.gd"
	for f in _const_tomb(unit, "FORMATIONS"): k.append_array(["alakzat_" + f, "alakzat_%s_al" % f])
	for t in _const_tomb(unit, "TOLTET_SORREND"): k.append_array(["toltet_" + t, "toltet_%s_al" % t])
	for a in ["aggro", "hold", "flee"]: k.append_array(["allas_" + a, "allas_%s_al" % a])
	# Tájak, kikötővárosok, lelőhelyek, kikötői hajók.
	for t in _lista("res://scripts/world/WorldGen.gd", "\\{\"key\":\\s*\"([a-z_]+)\""):
		k.append_array(["taj_" + t, "taj_%s_leiras" % t])
	for v in _lista("res://scripts/systems/Cities.gd", "\\{\"kulcs\":\\s*\"([a-z_]+)\""):
		k.append("varos_" + v)
	for r in ["transport", "warship", "galleon"]:
		k.append_array(["pm_hajo_" + r, "pm_hajo_%s_al" % r])
	for n in ["wood", "stone", "gold", "food", "fish"]: k.append("lh_%s_node" % n)
	for g in ["point", "node", "foe", "nincs"]: k.append("gyulekezo_" + g)
	return k

# Ugyanaz az átírás, mint a Style.title_name()-ben.
func _rang_kulcs(hu: String) -> String:
	var s := hu.to_lower().replace(" ", "_")
	for par in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ö", "o"], ["ő", "o"],
			["ú", "u"], ["ü", "u"], ["ű", "u"]]:
		s = s.replace(par[0], par[1])
	return "t_" + s
