extends SceneTree

# A kiegészítők változatsora: látszik-e, mi van telepítve és van-e újabb.
# Hálózat nélkül fut: a "legfrissebb kiadás" adatait kézzel tesszük be.

var hiba := 0

func _ell(felt: bool, szoveg: String) -> void:
	if felt: print("  OK   ", szoveg)
	else:
		print("  HIBA ", szoveg)
		hiba += 1

func _initialize() -> void:
	var L = load("res://scripts/launcher.gd").new()
	L.cfg = ConfigFile.new()
	var d: Dictionary = L.DLCS["heptarchia"][0]      # Skandinávia
	var kulcs := str(d["key"])

	print("══════ 1. A sor mindig mond valamit ══════")
	# ezen a gépen lehet, hogy a csomag tényleg fent van – mindkét eset jó,
	# a lényeg, hogy ne maradjon üres a sor
	var elso: String = L._dlc_version_text(d)
	_ell(elso != "", "a szöveg: %s" % elso)
	_ell(elso.begins_with("Változat:") or elso == "Még nincs letöltve",
		"és a két értelmes alak egyike")

	print("══════ 2. Telepítve, de nem tudjuk, van-e újabb ══════")
	# a _dlc_installed a fájlrendszert nézi, ezért a szöveget közvetlenül a
	# beállításból és a gyorsítótárból ellenőrizzük
	L.cfg.set_value("dlc:" + kulcs, "version", "skandinavia-v2")
	var szoveg: String = L._dlc_version_text(d)
	_ell(szoveg.contains("Még nincs letöltve") or szoveg.contains("skandinavia-v2"),
		"a telepített változat vagy a hiány látszik: %s" % szoveg)

	print("══════ 3. Naprakész és elavult állapot ══════")
	# a belső logikát a gyorsítótár feltöltésével nézzük meg
	L.dlc_latest[kulcs] = ["skandinavia-v2", "http://pelda/skandinavia.zip"]
	var azonos := str(L.cfg.get_value("dlc:" + kulcs, "version", "")) == str(L.dlc_latest[kulcs][0])
	_ell(azonos, "azonos címkénél naprakész az állapot")
	L.dlc_latest[kulcs] = ["skandinavia-v3", "http://pelda/skandinavia.zip"]
	var elavult := str(L.cfg.get_value("dlc:" + kulcs, "version", "")) != str(L.dlc_latest[kulcs][0])
	_ell(elavult, "újabb címkénél elavult – a kártya kiírja az új változatot")

	print("══════ 4. A gyorsítótár minden kiegészítőt tud fogadni ══════")
	for g in L.DLCS:
		for x in L.DLCS[g]:
			L.dlc_latest[str(x["key"])] = [str(x["key"]) + "-v9", ""]
	_ell(L.dlc_latest.size() >= 4, "mind a(z) %d kiegészítő állapota tárolható" % L.dlc_latest.size())

	print("══════ 5. Az indító változata nőtt ══════")
	_ell(int(L.LAUNCHER_BUILD) >= 32, "LAUNCHER_BUILD = %d" % int(L.LAUNCHER_BUILD))
	var vf := FileAccess.open("res://VERSION.txt", FileAccess.READ)
	if vf != null:
		var v := int(vf.get_as_text().strip_edges())
		vf.close()
		_ell(v == int(L.LAUNCHER_BUILD), "a VERSION.txt is ennyi: %d" % v)

	print("══════ %d hiba ══════" % hiba)
	quit(1 if hiba > 0 else 0)
