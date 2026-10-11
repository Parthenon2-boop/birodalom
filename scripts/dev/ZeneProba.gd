extends SceneTree

# ZENEPRÓBA — fejlesztői eszköz, a kiadásba nem kerül bele.
#
# Az önteszt hangkimenet nélkül (headless) fut, ott az SFX szándékosan nem
# játszik le semmit. Ez a próba ABLAKKAL indul, így a zenelejátszó tényleg
# dolgozik, és a keverő kimenetén mérhető, hogy szól-e:
#
#   Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path . --script res://scripts/dev/ZeneProba.gd
#
# (Az `--audio-driver Dummy` miatt a hangszóróból semmi nem szól, a keverő
# viszont ugyanúgy számol. Elhagyva a zene közben hallható is.)
#
# Mit néz:
#   1. mind a négy korszakzene elindul, a lejátszó `playing`, a szám hossza
#      több mint egy perc, és a zenebusz kimenetén van jel;
#   2. korszakváltáskor a lejátszó másik számra vált (áttűnéssel);
#   3. a némítás elnémítja, a hangerő-csúszka halkítja a zenebuszt;
#   4. a szám végén megszakítás nélkül elölről folytatódik (hurok).
# Kilépési kód: 0 = rendben, 1 = hiba.
#
# Az autoloadok `--script` futásnál nem élnek, ezért az SFX-et magunk
# példányosítjuk — ugyanazt a szkriptet, amit a játék használ.

var _hibak: int = 0
var _sfx: Node = null

func _init() -> void:
	_fut.call_deferred()

func _ell(nev: String, ok: bool, reszlet: String = "") -> void:
	print("  [%s] %s%s" % ["OK" if ok else "HIBA", nev, "" if reszlet == "" else "  (" + reszlet + ")"])
	if not ok: _hibak += 1

func _var(mp: float) -> void:
	await create_timer(mp).timeout

# A zenebusz kimenetének csúcsa egy rövid ideig figyelve (dB).
func _busz_csucs(mp: float = 0.6) -> float:
	var idx := AudioServer.get_bus_index("Music")
	var csucs := -200.0
	var veg := Time.get_ticks_msec() + int(mp * 1000.0)
	while Time.get_ticks_msec() < veg:
		csucs = maxf(csucs, maxf(AudioServer.get_bus_peak_volume_left_db(idx, 0),
			AudioServer.get_bus_peak_volume_right_db(idx, 0)))
		await process_frame
	return csucs

func _fut() -> void:
	if DisplayServer.get_name() == "headless":
		print("A zenepróbát ablakkal kell futtatni (ne --headless): headless módban az SFX nem játszik.")
		quit(1)
		return
	_sfx = (load("res://scripts/globals/SFX.gd") as GDScript).new()
	_sfx.name = "SFX"
	root.add_child(_sfx)
	await process_frame
	var zene: AudioStreamPlayer = _sfx._music
	_sfx.set_music_on(true)
	_sfx.set_music_volume(1.0)
	print("Zenepróba — hangmeghajtó: %s, keverési ütem: %d Hz" % [AudioServer.get_driver_name(), int(AudioServer.get_mix_rate())])

	# 1–2. Minden korszak zenéje megszólal, és a váltás tényleg vált.
	var elozo: AudioStream = null
	for kor in range(4):
		_sfx.play_era_music(kor)
		await _var(_sfx.MUSIC_FADE * 2.0 + 0.4)
		var hossz: float = zene.stream.get_length() if zene.stream != null else 0.0
		var hely0 := zene.get_playback_position()
		var csucs := await _busz_csucs()
		_ell("%d. korszak: a lejátszó játszik, a szám %.1f mp, a busz csúcsa %.1f dB" % [kor, hossz, csucs],
			zene.playing and hossz > 60.0 and csucs > -50.0 and zene.get_playback_position() > hely0,
			zene.stream.resource_path if zene.stream != null else "nincs stream")
		_ell("%d. korszak: a hangerő visszaállt az áttűnés után" % kor,
			absf(zene.volume_db - _sfx.MUSIC_DB) < 0.5, "%.1f dB" % zene.volume_db)
		if kor > 0:
			_ell("%d. korszak: a korszakváltás másik számra váltott" % kor, zene.stream != elozo)
		elozo = zene.stream

	# Ugyanarra a számra váltva nem kezdi elölről.
	var hely := zene.get_playback_position()
	_sfx.play_era_music(3)
	await _var(0.3)
	_ell("ugyanaz a szám nem indul újra", zene.get_playback_position() > hely)

	# 3. Némítás és hangerő.
	var hangos := await _busz_csucs()
	_sfx.set_music_on(false)
	await _var(0.3)
	var nema := await _busz_csucs()
	_ell("a némítás elnémítja a zenét (%.1f dB -> %.1f dB)" % [hangos, nema], nema < hangos - 40.0)
	_sfx.set_music_on(true)
	await _var(0.3)
	var vissza := await _busz_csucs(1.0)
	_ell("a visszakapcsolás után újra szól (%.1f dB)" % vissza, vissza > -50.0)
	_sfx.set_music_volume(0.1)
	await _var(0.3)
	var halk := await _busz_csucs(1.0)
	_ell("a hangerő-csúszka halkít: 10%%-on %.1f dB (teljes hangerőn %.1f dB)" % [halk, vissza],
		halk < vissza - 12.0 and halk > -80.0)
	_sfx.set_music_volume(1.0)

	# 4. Hurok: a vége elé ugrunk, és megnézzük, hogy megszakítás nélkül
	# átfordul-e az elejére.
	var teljes: float = zene.stream.get_length()
	zene.seek(teljes - 1.2)
	await _var(0.4)
	var vegen := zene.get_playback_position()
	var legcsendesebb := 0.0
	var veg_ms := Time.get_ticks_msec() + 2200
	while Time.get_ticks_msec() < veg_ms:
		# 0,2 mp-es szakaszonként nézzük a busz csúcsát: ha a hurokpontnál
		# szünet volna, az egyik szakasz elnémulna.
		legcsendesebb = minf(legcsendesebb, await _busz_csucs(0.2))
	var utana := zene.get_playback_position()
	_ell("a szám végén elölről folytatódik (%.2f mp -> %.2f mp)" % [vegen, utana],
		zene.playing and vegen > teljes - 1.2 and utana < 5.0)
	_ell("a hurokpontnál nincs szünet (a legcsendesebb 0,2 mp csúcsa %.1f dB)" % legcsendesebb,
		legcsendesebb > -45.0)

	_sfx.stop_music()
	await _var(0.2)
	_ell("a leállítás után nem játszik", not zene.playing)
	print("\n--- Zenepróba: %s ---" % ("minden rendben" if _hibak == 0 else "%d hiba" % _hibak))
	_sfx.queue_free()
	await process_frame
	quit(1 if _hibak > 0 else 0)
