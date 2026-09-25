extends SceneTree

# A launcher-tesztek közös része. A tesztek a _teszt/futtat.ps1-gyel futnak: az a projekt
# mellé egy override.cfg-t tesz, amely a user:// mappát egy KÜLÖN próbamappába irányítja
# (%APPDATA%\ParthTeszt\ParthLauncher), így a felhasználó valódi beállításai, belépése és a
# játékok adatmappái (Heptarchia, Kard és Mágia) érintetlenek maradnak.

var hiba := 0

func _ell(felt: bool, szoveg: String) -> void:
	if felt: print("  OK   ", szoveg)
	else:
		print("  HIBA ", szoveg)
		hiba += 1

func _fej(szoveg: String) -> void:
	print("══════ %s ══════" % szoveg)

func _vege() -> void:
	print("══════ %d hiba ══════" % hiba)
	quit(1 if hiba > 0 else 0)

# Biztosíték: ha valami beakad, ne fusson örökké
func _orszem(mp: float) -> void:
	create_timer(mp).timeout.connect(func() -> void:
		print("  HIBA időtúllépés (%d mp) – a teszt beakadt" % int(mp))
		quit(1))

# Csak a próbamappában futhatunk: ha az override.cfg hiányzik, a valódi beállításokat írnánk
func _homokozo_rendben() -> bool:
	var ud := OS.get_user_data_dir().replace("\\", "/")
	var jo := ud.contains("/ParthTeszt/")
	if not jo:
		print("  HIBA a user:// nem a próbamappa (%s) – a tesztet a _teszt/futtat.ps1-gyel futtasd!" % ud)
		hiba += 1
	return jo

# A játékok adatmappáinak közös szülője (a próbamappában)
func _alap_mappa() -> String:
	return OS.get_user_data_dir().get_base_dir()

func _uj_launcher(mock: bool = true) -> Control:
	var L: Control = load("res://_teszt/_mock.gd" if mock else "res://scripts/launcher.gd").new()
	L.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(L)
	return L

func _kockak(n: int) -> void:
	for i in n: await process_frame

# vár, amíg a feltétel igaz lesz (legfeljebb max_mp másodpercig); igazat ad, ha teljesült
func _var(felt: Callable, max_mp: float = 5.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not bool(felt.call()):
		if Time.get_ticks_msec() - t0 > int(max_mp * 1000.0): return false
		await process_frame
	return true

func _billentyu(kod: Key, shift: bool = false) -> void:
	for le: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = kod
		e.physical_keycode = kod
		e.pressed = le
		e.shift_pressed = shift
		root.push_input(e)
	await process_frame

func _fajl_szoveg(ut: String) -> String:
	return FileAccess.get_file_as_string(ut) if FileAccess.file_exists(ut) else ""

func _cfg_lemezen() -> ConfigFile:
	var c := ConfigFile.new()
	c.load("user://ParthLauncher.cfg")
	return c

func _zip_ir(ut: String) -> void:
	DirAccess.make_dir_recursive_absolute(ut.get_base_dir())
	var z := ZIPPacker.new()
	z.open(ut)
	z.start_file("proba.txt")
	z.write_file("proba".to_utf8_buffer())
	z.close_file()
	z.close()
