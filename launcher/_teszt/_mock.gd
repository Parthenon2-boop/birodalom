extends "res://scripts/launcher.gd"

# A launcher tesztváltozata: a fiókszerverhez (Supabase) menő kéréseket NEM küldi el,
# hanem előre megadott válaszokat ad vissza. Így a belépés, a regisztráció, a jelszó-
# emlékeztető és a dlc-access kezelése valódi szerver és valódi fiók nélkül próbálható.
#
#   valaszok: [[útvonal-részlet, HTTP-kód, válasz], …] – sorban fogynak; az első olyan
#             elem felel, amelynek útvonal-részlete benne van a kérés útvonalában
#   hivasok:  a beérkezett kérések: [{"path", "body", "token"}, …]
#   kesleltetes: ennyi másodpercig „tart” egy kérés (a dupla beküldés próbájához)

var valaszok: Array = []
var hivasok: Array = []
var kesleltetes: float = 0.0
var varatlan: Array[String] = []       # olyan kérések, amelyekre nem volt előre megadott válasz

func _acc_call(method: int, path: String, body: Variant = null, token: String = "") -> Array:
	hivasok.append({"method": method, "path": path, "body": body, "token": token})
	if kesleltetes > 0.0:
		await get_tree().create_timer(kesleltetes).timeout
	else:
		await get_tree().process_frame
	for i in valaszok.size():
		var v: Array = valaszok[i]
		if path.contains(str(v[0])):
			valaszok.remove_at(i)
			return [int(v[1]), v[2]]
	varatlan.append(path)
	return [0, {}]

# a valódi hálózatot (GitHub) a fiókpróbák nem használják
func check_latest() -> void:
	pass

func _sweep_versions() -> void:
	pass

func _fetch_news() -> void:
	pass

func hivott(resz: String) -> int:
	var n := 0
	for h: Dictionary in hivasok:
		if str(h["path"]).contains(resz): n += 1
	return n
