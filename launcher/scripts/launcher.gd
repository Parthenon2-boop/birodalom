extends Control

# ParthLauncher  —  Birodalom és Heptarchia egy programban
#
# Mindkét játékot a GitHubról szedi, mindig a legfrissebb változatot, majd elindítja.
# A két játék KÜLÖN tárolóból jön, külön mappába telepszik, és külön változatszáma van;
# a fenti két gombbal lehet köztük váltani.
#
# Két üzemmódot ismer, és magától választ közülük:
#   „release”  – ha a tárolóban van kiadás (Release) .zip melléklettel: az exportált játékot
#                tölti le, és a benne lévő .exe-t indítja. Ilyenkor nem kell Godot a gépre.
#   „source”   – ha nincs kiadás: a megadott ág legfrissebb állapotát tölti le (forrás),
#                és a helyben telepített Godot szerkesztővel indítja.
#
# Beállítások: user://ParthLauncher.cfg (mappák, proxy; a tárolók be vannak égetve).

const S := preload("res://scripts/style.gd")
const Backdrop := preload("res://scripts/backdrop.gd")

# ── A KÉT JÁTÉK ───────────────────────────────────────────────────
# Ide van „beégetve”, honnan tölt az indító: a többi gépen semmit nem kell
# beállítani, és bejelentkezni sem kell (nyilvános tárolóból, névtelenül).
# Felülírható az indító mellé tett repo.txt fájllal, soronként:
#     birodalom=felhasznalonev/tarolonev
#     heptarchia=felhasznalonev/tarolonev@ag
const GAMES := [
	{
		"key": "birodalom",
		"name": "BIRODALOM",
		"sub": "Valós idejű stratégia,  1400 – 1945",
		"owner": "Parthenon2-boop",
		"repo": "birodalom",
		"branch": "main",
		"dir": "Birodalom",
		"marker": "birodalom_launcher.marker",
		# Maga az indító EBBŐL a tárolóból frissíti önmagát (itt a forrása).
		"home": true,
	},
	{
		"key": "heptarchia",
		"name": "HEPTARCHIA",
		"sub": "Angolszász nagystratégia,  790-től",
		"owner": "Parthenon2-boop",
		"repo": "heptarchia",
		"branch": "main",
		"dir": "Heptarchia",
		"marker": "heptarchia_launcher.marker",
		"home": false,
	},
]

# ── MEGVÁSÁROLHATÓ KIEGÉSZÍTŐK (DLC) ─────────────────────────────
# Játékonként (a GAMES kulcsa szerint). A vevő a Gumroadon fizet, e-mailben licenckulcsot kap,
# azt itt beváltja: az indító a Gumroaddal ellenőrzi, majd letölti a kiegészítő csomagját
# (<key>.zip) a játék saját adatmappájába (…/app_userdata/<user_dir>/dlc/). A játék induláskor
# onnan tölti be – így a játék frissítése (a telepítési mappa cseréje) nem törli.
#   gumroad_product_id – a Gumroad termék azonosítója (a termék oldalán: Content → License key)
#   store_url          – a vásárlási oldal (pl. https://valaki.gumroad.com/l/skandinavia)
#   download_url       – a csomag (dlc/_csomagok/<key>.zip) letöltési címe
#   game_id            – a játék saját beállításfájljában ([dlc] szakasz) ezzel a névvel kapcsolható ki-be
#   releases_api       – a csomag-tároló kiadásai; ha újabb kiadásban van <key>.zip, az indító magától letölti
#                        (a letöltött kiadás címkéje: ParthLauncher.cfg [dlc:<key>] version)
# Amíg valamelyik üres, a kártya látszik, de a gomb jelzi, hogy a bolt még nincs beállítva.
const DLCS := {
	"heptarchia": [
		{
			"key": "skandinavia",
			"name": "Skandinávia",
			"desc": "Dánia, Norvégia, Svédek, Izland és Grönland – öt új nép, kibővített térkép, saját események.",
			"price": "4 $",
			"user_dir": "Heptarchia",
			"game_id": "scandinavia",      # a kiegészítő azonosítója a játékban (settings.cfg [dlc])
			"gumroad_product_id": "bpMjj0INnbiEv1kf1hglPg==",
			"store_url": "https://parthenon62.gumroad.com/l/ltsalt",
			"download_url": "https://github.com/Parthenon2-boop/heptarchia-dlc-csomagok/releases/latest/download/skandinavia.zip",
			# a csomag kiadásai: a legújabb olyan kiadás, amelyben <key>.zip van, az aktuális változat
			"releases_api": "https://api.github.com/repos/Parthenon2-boop/heptarchia-dlc-csomagok/releases?per_page=30",
		},
		{
			"key": "vikingek",
			"name": "A vikingek kora",
			"desc": "Vezesd a nagy portyákat: Lindisfarne, Dorestad, Sevilla, Párizs feldúlása – egészen Normandia megszerzéséig.",
			"price": "3 $",
			"user_dir": "Heptarchia",
			"game_id": "vikings",
			"gumroad_product_id": "3q90_eqTWf2lvTKEkkEr8Q==",
			"store_url": "https://parthenon62.gumroad.com/l/fxtisw",
			# a kiadása nem „latest” (az a Skandinávia csomagjáé), ezért konkrét címkével
			"download_url": "https://github.com/Parthenon2-boop/heptarchia-dlc-csomagok/releases/download/vikingek-v1/vikingek.zip",
			"releases_api": "https://api.github.com/repos/Parthenon2-boop/heptarchia-dlc-csomagok/releases?per_page=30",
		},
		{
			"key": "vallas",
			"name": "Hit és egyház",
			"desc": "Minden népnek saját vallása és tanfája: Canterbury, Szent Dávid, Columba, Patrik egyháza, Odin, Thor és Frey hite.",
			"price": "3 $",
			"user_dir": "Heptarchia",
			"game_id": "religion",
			"gumroad_product_id": "DzryuhWncOHx3Pq0IRIP8g==",
			"store_url": "https://parthenon62.gumroad.com/l/iwqkt",
			"download_url": "https://github.com/Parthenon2-boop/heptarchia-dlc-csomagok/releases/download/vallas-v1/vallas.zip",
			"releases_api": "https://api.github.com/repos/Parthenon2-boop/heptarchia-dlc-csomagok/releases?per_page=30",
		},
		{
			"key": "varegok",
			"name": "A varégok útja",
			"desc": "Keletre kibővített térkép: Novgorod, Kijev, Miklagarðr. A Rusz és Bizánc, expedíciók a Volgán és a Dnyeperen, a Varangi Gárda.",
			"price": "5 $",
			"user_dir": "Heptarchia",
			"game_id": "varangians",
			"gumroad_product_id": "lKinUakqfvjYPDG8EnuTbA==",
			"store_url": "https://parthenon62.gumroad.com/l/jrzwus",
			"download_url": "https://github.com/Parthenon2-boop/heptarchia-dlc-csomagok/releases/download/varegok-v1/varegok.zip",
			"releases_api": "https://api.github.com/repos/Parthenon2-boop/heptarchia-dlc-csomagok/releases?per_page=30",
		},
	],
}
const GUMROAD_VERIFY := "https://api.gumroad.com/v2/licenses/verify"

# ── Fiókok (Supabase) ─────────────────────────────────────────────
# Ha be van állítva, a megvásárolt kiegészítők a fiókhoz kötődnek: regisztráció / belépés után bármelyik gépen
# megjelennek. A Gumroad minden vásárlásnál értesíti a szervert (a vevő e-mail-címével), a „Van kulcsom” pedig
# a kulcsot a bejelentkezett fiókhoz köti. A szerver kódja: server/supabase (séma és két függvény).
# Üresen hagyva a launcher a régi, gépenkénti licenckulcsos módon működik.
const ACCOUNT_URL := "https://gxvepswtairfqvosdcpb.supabase.co"          # a Supabase-projekt címe, pl. https://abcdefgh.supabase.co
const ACCOUNT_ANON_KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd4dmVwc3d0YWlyZnF2b3NkY3BiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk4MzQyMzYsImV4cCI6MjEwNTQxMDIzNn0.9A86POfj49aRynE3rerz4nMbfds7xny6GLuRePpgSSI"     # a projekt nyilvános (anon / publishable) kulcsa – nem titok
const ACC_LICENSE := "account"   # a fiókból jövő jogosultság jele a ParthLauncher.cfg-ben

# Az indító saját változata. Ha a „home” tárolóban lévő launcher/VERSION.txt ennél
# nagyobb, az indító letölti és kicseréli önmagát, majd újraindul.
# Ha az indítón változtatsz: növeld itt is és a launcher/VERSION.txt fájlban is!
const LAUNCHER_BUILD := 19
const VERSION_FILE := "launcher/VERSION.txt"

const CFG_PATH := "user://ParthLauncher.cfg"
const LAUNCHER_ZIP_TMP := "user://indito_update.zip"
const LAUNCHER_STAGE := "user://uj_indito"       # ide csomagoljuk ki az új indítót
const API := "https://api.github.com"
const HEADERS := ["User-Agent: ParthLauncher", "Accept: application/vnd.github+json"]

var cfg := ConfigFile.new()
var game_idx: int = 0                # melyik játék van kiválasztva
var repo_owner: String = ""          # a KIVÁLASZTOTT játék tárolója
var repo: String = ""
var branch: String = "main"
var install_dir: String = ""
var installed_version: String = ""
var installed_mode: String = ""
var godot_exe: String = ""           # közös: forrás módhoz
var auto_update: bool = true         # induláskor magától letölti az újat
var auto_play: bool = false          # frissítés után magától el is indítja a játékot
# Iskolai / céges hálózatokhoz: proxy és a tanúsítvány-ellenőrzés kikapcsolása
var proxy_host: String = ""
var proxy_port: int = 0
var insecure_tls: bool = false

var remote := {}          # {"mode", "version", "url", "notes", "date", "size"}
var busy := false
# CSAK a „home” (Birodalom) kiadásából való indító-csomag kerülhet ide: az
# indító sosem cserélheti ki magát a másik játék saját indítójával.
var home_launcher_asset := {}
var launcher_update := 0             # az elérhető újabb indító-változat (0 = nincs)
var _home_check_running := false

# MINDKÉT JÁTÉK ELÉRHETŐ VÁLTOZATA — hogy a fülön mindig lássad, hol tart a
# másik játék is, ne csak az, amelyiket épp nézed. Induláskor a legutóbb
# látott számot mutatjuk (a beállításfájlból), és a háttérben frissítjük.
# A telepítettet is itt tartjuk számon, hogy a fülön kiderüljön, van-e újabb.
var latest_ver := {}                 # játékkulcs -> a GitHubon lévő változat
var _sweep_sor: Array = []           # a még lekérdezendő játékok kulcsai
var http_info: HTTPRequest           # a fülek verzióihoz (a letöltéstől külön)

var http: HTTPRequest
var _ui: Control                     # a bőrváltáskor újraépülő felület
var _import_thread: Thread
var _repo_file := {}                 # a repo.txt felülírásai: kulcs -> {owner, repo, branch}
var game_btns: Array[Button] = []
var lbl_game: Label
var lbl_installed: Label
var lbl_latest: Label
var lbl_status: Label
var txt_notes: RichTextLabel
var bar: ProgressBar
var lbl_bar: Label
var btn_check: Button
var btn_main: Button
var settings: PopupPanel
var set_fields := {}
var chk_auto: CheckBox
var chk_play: CheckBox
# Kiegészítők
var dlc_box: VBoxContainer           # a kiválasztott játék kiegészítő-kártyái
var dlc_scroll: ScrollContainer      # a kártyák görgethető kerete: legfeljebb DLC_MAX_H magas, hogy semmi ne lógjon ki
const DLC_MAX_H := 340.0             # a cím és öt kártya; ha több van, a lista görgethető
var http_dlc: HTTPRequest            # licencellenőrzés és a csomag letöltése (a játék letöltésétől külön)
var dlc_busy := false
var license_popup: PopupPanel
var lic_edit: LineEdit
var lic_status: Label
var lic_title: Label
var lic_dlc := {}                    # melyik kiegészítő kulcsát váltják be

func _ready() -> void:
	if _relaunch_without_console(): return
	_repo_file = _read_repo_file()
	cfg.load(CFG_PATH)
	_load_common()
	game_idx = clampi(int(cfg.get_value("state", "game", 0)), 0, GAMES.size() - 1)
	_load_game(game_idx)
	_apply_skin()                 # a kiválasztott játék stílusa + felület
	http = HTTPRequest.new()
	http.timeout = 60.0
	add_child(http)
	http_info = HTTPRequest.new()
	http_info.timeout = 30.0
	add_child(http_info)
	http_dlc = HTTPRequest.new()
	http_dlc.timeout = 120.0
	add_child(http_dlc)
	_apply_net_settings()
	_refresh_dlc()
	_restore_owned_dlcs()
	if _acc_enabled(): _acc_refresh()
	_refresh_labels()
	_show_notes(str(game()["key"]))   # a legutóbb látott leírás azonnal
	check_latest()
	_sweep_versions()             # mindkét játék változata a fülre
	# Ellenőrzéshez:  ParthLauncher -- --shot=<utvonal.png>
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): _capture_after(a.substr(7))

# Ha az indító parancssorból indult – főleg egy régebbi frissítő szkriptből, amely „start”-tal futott, ezért
# az ablaka a szkript után is nyitva marad –, a játék kimenete is oda kerülne. Ilyenkor bezárjuk a
# frissítő ablakát, és az Intézővel újraindítjuk magunkat ablak nélkül.
# (Jelek: a frissítő szkript még megvan, vagy a parancssor PROMPT változója öröklődött.)
func _relaunch_without_console() -> bool:
	if OS.get_name() != "Windows" or OS.has_feature("editor"): return false
	var swap_bat := ProjectSettings.globalize_path("user://frissites.bat").replace("/", "\\")
	# A régi frissítő parancssora (cmd /K) magától sosem zárulna be, és a szkriptfájl addigra már törölve
	# lehet – ezért MINDEN indításkor megkeressük a parancssorát (benne van a „frissites.bat” név), és
	# rejtve leállítjuk. Kódolva adjuk át (UTF-16LE, base64), így az idézőjelek nem sérülnek.
	var ps := "Start-Sleep -Seconds 1; Get-CimInstance Win32_Process -Filter \"Name='cmd.exe'\" | " \
		+ "Where-Object { $_.CommandLine -like '*frissites.bat*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }; " \
		+ "Remove-Item -LiteralPath '" + swap_bat + "' -Force -ErrorAction SilentlyContinue"
	var encoded := Marshalls.raw_to_base64(ps.to_utf16_buffer())
	OS.create_process("powershell.exe", ["-NoProfile", "-WindowStyle", "Hidden", "-EncodedCommand", encoded], false)
	if not OS.has_environment("PROMPT"): return false
	if "--no-relaunch" in OS.get_cmdline_user_args(): return false
	# biztosíték: ha az imént már újraindultunk (és a PROMPT mégis megvan), nem próbáljuk újra
	var mark := "user://ujraindulas.txt"
	var now := int(Time.get_unix_time_from_system())
	if FileAccess.file_exists(mark) and now - int(FileAccess.get_file_as_string(mark)) < 20:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(mark))
		return false
	_write_text(mark, str(now))
	OS.create_process("explorer.exe", [OS.get_executable_path().replace("/", "\\")])
	get_tree().quit()
	return true

func _capture_after(path: String) -> void:
	for _i in range(180):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("képernyőkép:", path)
	get_tree().quit()
	# Az indító a saját frissítését a játéktól függetlenül nézi meg, hogy
	# akkor is naprakész legyen, ha épp a másik játék fülén állunk.
	_check_home_launcher()

# A felület a KIVÁLASZTOTT JÁTÉK stílusát veszi föl: a Birodalom sötétbarna-
# arany felületét, a Heptarchia pergamen-bőr indítóját. A bőr színei és betűi
# a témába és a rajzolt háttérbe is beépülnek, ezért váltáskor a felületet
# újra kell építeni.
func _apply_skin() -> void:
	S.set_skin(str(game()["key"]))
	theme = S.build_theme()
	if _ui != null and is_instance_valid(_ui):
		_ui.queue_free()
		_ui = null
	_build_ui()

func game() -> Dictionary:
	return GAMES[clampi(game_idx, 0, GAMES.size() - 1)]

# ── Beállítások ───────────────────────────────────────────────

func _load_common() -> void:
	# A legutóbb LÁTOTT változatok: így a fülön rögtön ott a szám, még mielőtt
	# a GitHub válaszolna (és akkor is, ha épp nincs hálózat).
	latest_ver.clear()
	for g in GAMES:
		var k := str(g["key"])
		var v := str(cfg.get_value("latest", k, ""))
		if v != "": latest_ver[k] = v
	auto_update = bool(cfg.get_value("state", "auto_update", true))
	auto_play = bool(cfg.get_value("state", "auto_play", false))
	insecure_tls = bool(cfg.get_value("net", "insecure_tls", false))
	var proxy := str(cfg.get_value("net", "proxy", ""))
	if proxy == "": proxy = _detect_system_proxy()
	_set_proxy(proxy)
	godot_exe = str(cfg.get_value("paths", "godot_exe", ""))
	if godot_exe == "" or not FileAccess.file_exists(godot_exe):
		godot_exe = _find_godot()

# Egy játék tárolója: 1. beégetett alapérték, 2. repo.txt, 3. mentett beállítás.
func _repo_of(g: Dictionary) -> Array:
	var key := str(g["key"])
	var built_in := {"owner": str(g["owner"]), "repo": str(g["repo"]), "branch": str(g["branch"])}
	if _repo_file.has(key):
		built_in.merge(_repo_file[key] as Dictionary, true)
	return [
		str(cfg.get_value("repo:" + key, "owner", built_in["owner"])),
		str(cfg.get_value("repo:" + key, "name", built_in["repo"])),
		str(cfg.get_value("repo:" + key, "branch", built_in["branch"])),
	]

# A kiválasztott játék saját adatai (tároló, mappa, telepített változat).
func _load_game(idx: int) -> void:
	game_idx = clampi(idx, 0, GAMES.size() - 1)
	var g := game()
	var key := str(g["key"])
	var rr := _repo_of(g)
	repo_owner = str(rr[0])
	repo = str(rr[1])
	branch = str(rr[2])
	install_dir = str(cfg.get_value("paths:" + key, "install_dir", _default_install_dir()))
	installed_version = str(cfg.get_value("state:" + key, "version", ""))
	installed_mode = str(cfg.get_value("state:" + key, "mode", ""))
	remote = {}
	# A launcher_update NEM nullázódik: az indító frissítése a játéktól
	# független, és váltás után is érvényes marad.

func _save_cfg() -> void:
	var key := str(game()["key"])
	cfg.set_value("state", "game", game_idx)
	cfg.set_value("repo:" + key, "owner", repo_owner)
	cfg.set_value("repo:" + key, "name", repo)
	cfg.set_value("repo:" + key, "branch", branch)
	cfg.set_value("paths:" + key, "install_dir", install_dir)
	cfg.set_value("state:" + key, "version", installed_version)
	cfg.set_value("state:" + key, "mode", installed_mode)
	cfg.set_value("paths", "godot_exe", godot_exe)
	cfg.set_value("state", "auto_update", auto_update)
	cfg.set_value("state", "auto_play", auto_play)
	cfg.set_value("net", "proxy", proxy_text())
	cfg.set_value("net", "insecure_tls", insecure_tls)
	for k in latest_ver:
		cfg.set_value("latest", str(k), str(latest_ver[k]))
	cfg.save(CFG_PATH)

# ── Hálózati beállítások (proxy, tanúsítvány) ─────────────────

func proxy_text() -> String:
	return "%s:%d" % [proxy_host, proxy_port] if proxy_host != "" else ""

func _set_proxy(text: String) -> void:
	proxy_host = ""
	proxy_port = 0
	var t := text.strip_edges().trim_prefix("http://").trim_prefix("https://").trim_suffix("/")
	if t == "": return
	var parts := t.split(":")
	proxy_host = parts[0]
	proxy_port = int(parts[1]) if parts.size() > 1 else 8080

# A Windows / a környezeti változók proxybeállítása (iskolai hálózatokon gyakori)
func _detect_system_proxy() -> String:
	for env_name in ["HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy"]:
		var v := OS.get_environment(env_name)
		if v.strip_edges() != "": return v
	var out: Array = []
	var code := OS.execute("reg", ["query", "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings",
		"/v", "ProxyServer"], out, true)
	if code == 0 and not out.is_empty():
		var text: String = str(out[0])
		var idx := text.find("REG_SZ")
		if idx >= 0:
			var value := text.substr(idx + 6).strip_edges().split("\n")[0].strip_edges()
			# lehet "gép:port" vagy "http=gép:port;https=gép:port"
			if value.contains("https="):
				value = value.split("https=")[1].split(";")[0]
			elif value.contains("="):
				value = value.split("=")[1].split(";")[0]
			return value.strip_edges()
	return ""

func _apply_net_settings() -> void:
	if http == null: return
	http.set_https_proxy(proxy_host, proxy_port)
	http.set_http_proxy(proxy_host, proxy_port)
	http.set_tls_options(TLSOptions.client_unsafe() if insecure_tls else TLSOptions.client())
	if http_dlc != null:
		http_dlc.set_https_proxy(proxy_host, proxy_port)
		http_dlc.set_http_proxy(proxy_host, proxy_port)
		http_dlc.set_tls_options(TLSOptions.client_unsafe() if insecure_tls else TLSOptions.client())

# Az indító melletti repo.txt. Soronként:
#     birodalom=felhasznalonev/tarolonev[@ag]
# Egyetlen, kulcs nélküli "felhasznalonev/tarolonev" sor az ELSŐ játékra vonatkozik.
func _read_repo_file() -> Dictionary:
	var out := {}
	var places: Array[String] = [OS.get_executable_path().get_base_dir(),
		ProjectSettings.globalize_path("res://")]
	for dir_path in places:
		var path: String = dir_path.path_join("repo.txt")
		if not FileAccess.file_exists(path): continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null: continue
		while not f.eof_reached():
			var line := f.get_line().strip_edges()
			if line == "" or line.begins_with("#"): continue
			var key := str(GAMES[0]["key"])
			if line.contains("="):
				var kv := line.split("=", true, 1)
				key = str(kv[0]).strip_edges().to_lower()
				line = str(kv[1]).strip_edges()
			var at := line.split("@")
			var parts: PackedStringArray = at[0].split("/")
			if parts.size() >= 2:
				out[key] = {"owner": parts[0].strip_edges(), "repo": parts[1].strip_edges(),
					"branch": at[1].strip_edges() if at.size() > 1 else "main"}
		if not out.is_empty(): return out
	return out

func _default_install_dir() -> String:
	var folder := str(game()["dir"])
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("user://").path_join(folder)
	if _is_mac():
		# Macen a program egy .app csomagban van, abba nem telepítünk: a felhasználó mappájába tesszük
		var home := OS.get_environment("HOME")
		return (home if home != "" else ProjectSettings.globalize_path("user://")).path_join(folder)
	return OS.get_executable_path().get_base_dir().path_join(folder)

# Godot szerkesztő keresése a szokásos helyeken (forrás módban ezzel indul a játék)
func _find_godot() -> String:
	if _is_mac():
		for p in ["/Applications/Godot.app/Contents/MacOS/Godot",
				OS.get_environment("HOME").path_join("Applications/Godot.app/Contents/MacOS/Godot")]:
			if FileAccess.file_exists(p): return p
		return ""
	var roots: Array = [OS.get_executable_path().get_base_dir(),
		OS.get_environment("USERPROFILE").path_join("Downloads"),
		OS.get_environment("USERPROFILE").path_join("Desktop"),
		"C:/Program Files/Godot"]
	for root in roots:
		var found := _scan_for_godot(root, 2)
		if found != "": return found
	return ""

func _scan_for_godot(dir_path: String, depth: int) -> String:
	var d := DirAccess.open(dir_path)
	if d == null: return ""
	for f in d.get_files():
		if f.to_lower().begins_with("godot") and f.ends_with(".exe") and not f.to_lower().contains("console"):
			return dir_path.path_join(f)
	if depth <= 0: return ""
	for sub in d.get_directories():
		if not sub.to_lower().contains("godot"): continue
		var found := _scan_for_godot(dir_path.path_join(sub), depth - 1)
		if found != "": return found
	return ""

# ── Felület ───────────────────────────────────────────────────

func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)

	var bg := Backdrop.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_ui.add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	box.offset_left = 40; box.offset_right = -40; box.offset_top = 20; box.offset_bottom = -34
	box.add_theme_constant_override("separation", 6)
	_ui.add_child(box)

	# A Heptarchia indítóján rúnasor áll a cím fölött — itt is az van, ha az
	# a játék van kiválasztva.
	if S.skin == "heptarchia":
		var runes := Label.new()
		runes.text = "ᚻᛖᛈᛏᚪᚱᚳᚻᛁᚪ"
		var rf := S.font_runes()
		if rf != null: runes.add_theme_font_override("font", rf)
		runes.add_theme_font_size_override("font_size", 19)
		runes.add_theme_color_override("font_color", Color(S.BORDER, 0.9))
		runes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(runes)
		box.add_child(S.make_title("ParthLauncher", 34, S.RED))
	else:
		box.add_child(S.make_title("ParthLauncher", 34, S.GOLD_LIGHT))

	# A két játék: fent két gomb, a kiválasztott ki van emelve.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	box.add_child(tabs)
	game_btns.clear()
	for i in GAMES.size():
		var idx := i
		var b := _button(tabs, str(GAMES[i]["name"]), func(): _switch_game(idx))
		# Két sor fér rá: a játék neve, alatta a változat — ezért magasabb és
		# valamivel kisebb betűs, mint egy sima gomb.
		b.custom_minimum_size = Vector2(0, 52)
		b.add_theme_font_size_override("font_size", 17)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		game_btns.append(b)

	lbl_game = Label.new()
	lbl_game.add_theme_font_size_override("font_size", 16)
	var itf := S.font_italic()
	if itf != null: lbl_game.add_theme_font_override("font", itf)
	lbl_game.add_theme_color_override("font_color",
		S.GOLD if S.skin == "birodalom" else S.TEXT_DIM)
	lbl_game.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl_game)
	box.add_child(_divider())

	lbl_installed = _info_label(box)
	lbl_installed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_latest = _info_label(box)
	lbl_latest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_latest.add_theme_font_size_override("font_size", 20)
	lbl_status = _info_label(box)
	lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_status.add_theme_font_size_override("font_size", 17)

	# A kiadási jegyzetek panelje nincs a felületen (a felhasználó kérésére): a szövegét a kód továbbra is
	# kitöltheti, de rejtve marad. Helyette rugalmas térköz tartja lent a gombokat.
	txt_notes = RichTextLabel.new()
	txt_notes.bbcode_enabled = true
	txt_notes.visible = false
	_ui.add_child(txt_notes)
	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	box.add_child(spacer)
	# A kiválasztott játék megvásárolható kiegészítői (lakattal, amíg nincs meg)
	dlc_scroll = ScrollContainer.new()
	dlc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(dlc_scroll)
	dlc_box = VBoxContainer.new()
	dlc_box.size_flags_horizontal = SIZE_EXPAND_FILL
	dlc_box.add_theme_constant_override("separation", 4)
	dlc_scroll.add_child(dlc_box)

	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 10)
	box.add_child(bar_row)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 22)
	bar.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.value = 0
	bar_row.add_child(bar)
	lbl_bar = Label.new()
	lbl_bar.custom_minimum_size = Vector2(120, 0)
	lbl_bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar_row.add_child(lbl_bar)

	# Egyetlen nagy gomb: „Frissítés”, majd ha naprakész, „Indítás”
	btn_main = _button(box, "Indítás", _on_main_button)
	btn_main.custom_minimum_size = Vector2(0, 48)
	btn_main.add_theme_font_size_override("font_size", 24)
	btn_main.add_theme_color_override("font_color", S.GOLD_LIGHT)

	var opts := HBoxContainer.new()
	opts.alignment = BoxContainer.ALIGNMENT_CENTER
	opts.add_theme_constant_override("separation", 18)
	box.add_child(opts)
	chk_play = _checkbox(opts, "Frissítés után induljon automatikusan", auto_play, _set_auto_play)
	chk_auto = _checkbox(opts, "Frissítés keresése induláskor", auto_update, _set_auto_update)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	box.add_child(row2)
	btn_check = _button(row2, "Frissítés keresése", check_latest)
	btn_check.size_flags_horizontal = SIZE_EXPAND_FILL
	_button(row2, "Beállítások", func(): _open_settings()).size_flags_horizontal = SIZE_EXPAND_FILL
	_button(row2, "Kilépés", func(): get_tree().quit()).size_flags_horizontal = SIZE_EXPAND_FILL

	_build_settings()
	_build_license_popup()

# Váltás a két játék között: a mostani állapotot elmentjük, a másikét betöltjük.
func _switch_game(idx: int) -> void:
	if idx == game_idx: return
	if busy:
		http.cancel_request()
		http.download_file = ""
		set_process(false)
		busy = false
	_save_cfg()
	_load_game(idx)
	cfg.set_value("state", "game", game_idx)
	cfg.save(CFG_PATH)
	# A felület a másik játék stílusát veszi föl (szín, betű, háttér).
	_apply_skin()
	_progress(0, "")
	_status("")
	_refresh_labels()
	_refresh_dlc()
	_show_notes(str(game()["key"]))   # a másik játék leírása azonnal látszik
	check_latest()

func _divider() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 12)
	c.draw.connect(_draw_divider.bind(c))
	return c

func _draw_divider(c: Control) -> void:
	var w := c.size.x
	var y := 6.0
	c.draw_line(Vector2(0, y), Vector2(w, y), Color(S.BORDER, 0.7), 1.0)
	c.draw_circle(Vector2(w * 0.5, y), 3.5, S.GOLD)
	c.draw_circle(Vector2(w * 0.5 - 14.0, y), 2.0, Color(S.GOLD, 0.7))
	c.draw_circle(Vector2(w * 0.5 + 14.0, y), 2.0, Color(S.GOLD, 0.7))

func _info_label(parent: Node) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 17)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l

func _button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	b.pressed.connect(action)
	parent.add_child(b)
	return b

# A nagy gomb: ha van frissítés, letölti; ha nincs, indítja a játékot
func _on_main_button() -> void:
	if launcher_update > 0:
		start_launcher_update()
	elif _needs_download():
		start_update()
	else:
		play()

# Akkor is tölteni kell, ha a változatszám stimmel, de a játék hiányzik
# (pl. félbemaradt vagy hibás korábbi telepítés után).
func _needs_download() -> bool:
	var latest: String = str(remote.get("version", ""))
	if latest == "": return false
	return latest != installed_version or not _game_installed()

func _checkbox(parent: Node, text: String, value: bool, action: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.add_theme_font_size_override("font_size", 15)
	c.toggled.connect(action)
	parent.add_child(c)
	return c

func _set_auto_update(value: bool) -> void:
	auto_update = value
	_save_cfg()

func _set_auto_play(value: bool) -> void:
	auto_play = value
	_save_cfg()

func _build_settings() -> void:
	settings = PopupPanel.new()
	add_child(settings)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(580, 0)
	v.add_theme_constant_override("separation", 8)
	settings.add_child(v)
	v.add_child(S.make_title("Beállítások", 26, S.GOLD_LIGHT))
	# A letöltés forrása szándékosan nem jelenik meg: az indítóba van építve
	# (szükség esetén a program mellé tett repo.txt fájllal írható felül).
	var fields := [
		["install", "A kiválasztott játék telepítési mappája", ""],
		["godot", "Godot szerkesztő (.exe) – forrás módhoz", ""],
		["proxy", "Proxy (gép:port) – csak ha a hálózat megköveteli", ""]
	]
	for f in fields:
		var l := Label.new()
		l.text = f[1]
		l.add_theme_color_override("font_color", S.TEXT)
		l.add_theme_font_size_override("font_size", 15)
		v.add_child(l)
		var e := LineEdit.new()
		e.custom_minimum_size = Vector2(0, 34)
		v.add_child(e)
		set_fields[f[0]] = e
	var chk := CheckBox.new()
	chk.text = "Iskolai / céges hálózat: tanúsítvány-ellenőrzés kikapcsolása"
	chk.add_theme_color_override("font_color", S.TEXT)
	chk.add_theme_font_size_override("font_size", 15)
	v.add_child(chk)
	set_fields["insecure"] = chk

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_button(row, "Mentés", _apply_settings).size_flags_horizontal = SIZE_EXPAND_FILL
	_button(row, "Hálózati vizsgálat", _diagnostics_from_settings).size_flags_horizontal = SIZE_EXPAND_FILL
	_button(row, "Mégse", func(): settings.hide()).size_flags_horizontal = SIZE_EXPAND_FILL

func _open_settings() -> void:
	set_fields["install"].text = install_dir
	set_fields["godot"].text = godot_exe
	set_fields["proxy"].text = proxy_text()
	set_fields["insecure"].button_pressed = insecure_tls
	settings.popup_centered()

func _diagnostics_from_settings() -> void:
	settings.hide()
	run_diagnostics()

func _apply_settings() -> void:
	# ha épp fut egy lekérdezés a régi beállításokkal, azt eldobjuk
	if busy:
		http.cancel_request()
		http.download_file = ""
		set_process(false)
		busy = false
	install_dir = set_fields["install"].text.strip_edges()
	godot_exe = set_fields["godot"].text.strip_edges()
	_set_proxy(set_fields["proxy"].text)
	insecure_tls = set_fields["insecure"].button_pressed
	if branch == "": branch = "main"
	_apply_net_settings()
	_save_cfg()
	settings.hide()
	_refresh_labels()
	check_latest()

func _refresh_labels() -> void:
	var g := game()
	lbl_game.text = str(g["sub"])
	for i in game_btns.size():
		var b := game_btns[i]
		b.flat = (i != game_idx)
		b.add_theme_color_override("font_color",
			S.GOLD_LIGHT if i == game_idx else S.TEXT)
		# A fülön MINDIG ott a szám: mi van fent a GitHubon, és — ha más —
		# mi van telepítve. Így a másik játékról is látszik, van-e újabb.
		var k := str(GAMES[i]["key"])
		var fent := str(latest_ver.get(k, ""))
		var itt := _installed_of(k)
		var also := ""
		if fent == "" and itt == "":
			also = "változat: ?"
		elif fent == "" :
			also = "telepítve: %s" % itt
		elif itt == "" :
			also = "%s (nincs telepítve)" % fent
		elif itt == fent:
			also = "%s – naprakész" % fent
		else:
			also = "%s → %s" % [itt, fent]
		b.text = "%s\n%s" % [str(GAMES[i]["name"]), also]
	# Csak a változatokat mutatjuk – sem a tároló, sem a letöltési cím nem látszik
	lbl_installed.text = "%s – telepített változat: %s" % [str(g["name"]).capitalize(),
		installed_version if installed_version != "" else "még nincs telepítve"]
	var latest: String = str(remote.get("version", ""))
	var up_to_date: bool = latest != "" and latest == installed_version
	if remote.is_empty():
		lbl_latest.text = ""
	elif up_to_date:
		lbl_latest.text = "Naprakész (%s)" % latest
	else:
		lbl_latest.text = "Elérhető frissítés: %s" % latest
	lbl_latest.add_theme_color_override("font_color", S.GREEN if up_to_date else S.GOLD_LIGHT)
	var installed: bool = _game_installed()
	var can_update: bool = _needs_download()
	# Egyetlen nagy gomb: előbb frissít, utána indít
	btn_main.disabled = busy or (launcher_update == 0 and not can_update and not installed)
	if launcher_update > 0:
		btn_main.text = "Indító frissítése"
		btn_main.tooltip_text = "Lecseréli az indítót az újabb változatra, és újraindul"
	elif can_update:
		btn_main.text = "Újratöltés" if up_to_date else "Frissítés"
		btn_main.tooltip_text = "Letölti a legújabb változatot"
	else:
		btn_main.text = "Indítás"
		btn_main.tooltip_text = "Elindítja a játékot"
	btn_check.disabled = busy

func _status(text: String, color: Color = S.TEXT) -> void:
	lbl_status.text = text
	lbl_status.add_theme_color_override("font_color", color)

func _progress(value: float, text: String) -> void:
	bar.value = clampf(value, 0.0, 100.0)
	lbl_bar.text = text

# ── Kiegészítők (DLC): vásárlás, kulcs beváltása, letöltés ────────

func _dlcs() -> Array:
	return DLCS.get(str(game()["key"]), [])

func _dlc_license(d: Dictionary) -> String:
	return str(cfg.get_value("dlc:" + str(d["key"]), "license", ""))

# A játék saját adatmappája (Godot: …/app_userdata/<név>), ide kerül a kiegészítő csomagja
func _dlc_zip_path(d: Dictionary) -> String:
	return OS.get_user_data_dir().get_base_dir().path_join(str(d["user_dir"])).path_join("dlc").path_join(str(d["key"]) + ".zip")

func _dlc_installed(d: Dictionary) -> bool:
	return FileAccess.file_exists(_dlc_zip_path(d))

# Ki- és bekapcsolás: ugyanaz a beállítás, amit a játék Beállítások → Kiegészítők füle ír
# (…/app_userdata/<user_dir>/settings.cfg, [dlc] <game_id> = true/false; alapból bekapcsolva)
func _game_settings_path(d: Dictionary) -> String:
	return OS.get_user_data_dir().get_base_dir().path_join(str(d["user_dir"])).path_join("settings.cfg")

func _dlc_enabled(d: Dictionary) -> bool:
	var gc := ConfigFile.new()
	gc.load(_game_settings_path(d))
	return bool(gc.get_value("dlc", str(d["game_id"]), true))

func _set_dlc_enabled(d: Dictionary, on: bool) -> void:
	var gc := ConfigFile.new()
	gc.load(_game_settings_path(d))
	gc.set_value("dlc", str(d["game_id"]), on)
	DirAccess.make_dir_recursive_absolute(_game_settings_path(d).get_base_dir())
	gc.save(_game_settings_path(d))
	_status("A(z) %s %s. A játék következő indításakor érvényes." % [str(d["name"]), "bekapcsolva" if on else "kikapcsolva"],
		S.GREEN if on else S.TEXT)

# A kártyák újraépítése: név, leírás, és lakat + „Megvásárlás” vagy pipa + állapot
func _refresh_dlc() -> void:
	if dlc_box == null or not is_instance_valid(dlc_box): return
	for c in dlc_box.get_children():
		dlc_box.remove_child(c)
		c.queue_free()
	var list := _dlcs()
	dlc_scroll.visible = not list.is_empty()
	if list.is_empty(): return
	var head := Label.new()
	head.text = "Kiegészítők"
	var tf := S.font_title()
	if tf != null: head.add_theme_font_override("font", tf)
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", S.RED if S.skin == "heptarchia" else S.GOLD_LIGHT)
	if _acc_enabled():
		# a fejléc sorában jobbra: belépés / a fiók
		var hrow := HBoxContainer.new()
		dlc_box.add_child(hrow)
		head.size_flags_horizontal = SIZE_EXPAND_FILL
		hrow.add_child(head)
		var acc := _button(hrow, ("👤 " + _acc_email()) if _acc_logged_in() else "Bejelentkezés / Regisztráció", _open_account)
		acc.custom_minimum_size = Vector2(0, 30)
		acc.add_theme_font_size_override("font_size", 14)
		acc.clip_text = true
		acc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		acc.custom_minimum_size.x = 220
	else:
		dlc_box.add_child(head)
	for d in list:
		dlc_box.add_child(_dlc_card(d))
	_fit_dlc.call_deferred()

# A kártyák kerete akkora, mint a tartalma, de legfeljebb DLC_MAX_H (a többi görgethető)
func _fit_dlc() -> void:
	if dlc_scroll == null or not is_instance_valid(dlc_scroll): return
	dlc_scroll.custom_minimum_size.y = minf(dlc_box.get_combined_minimum_size().y, DLC_MAX_H)

func _dlc_card(d: Dictionary) -> Control:
	var owned := _dlc_license(d) != ""
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = S.NOTES_BG
	sb.border_color = S.GOLD if owned else Color(S.BORDER, 0.9)
	sb.set_border_width_all(2 if owned else 1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(4)
	card.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	# lakat (nincs meg) vagy pecsét pipával (megvásárolva)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(34, 38)
	icon.draw.connect(_draw_dlc_icon.bind(icon, owned))
	row.add_child(icon)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	row.add_child(texts)
	var name_l := Label.new()
	name_l.text = "%s  –  %s" % [str(d["name"]), "megvásárolva" if owned else str(d["price"])]
	name_l.add_theme_font_size_override("font_size", 17)
	name_l.add_theme_color_override("font_color", S.GREEN if owned else S.TEXT)
	texts.add_child(name_l)
	var desc := Label.new()
	desc.text = str(d["desc"])
	# egy sorban (több kiegészítő is elférjen); a teljes leírás a kártya súgójában
	desc.clip_text = true
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc.add_theme_font_size_override("font_size", 13)
	card.tooltip_text = str(d["desc"])
	desc.mouse_filter = Control.MOUSE_FILTER_PASS
	desc.add_theme_color_override("font_color", S.TEXT_DIM)
	texts.add_child(desc)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	btns.alignment = BoxContainer.ALIGNMENT_END
	btns.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(btns)
	if owned:
		if _dlc_installed(d):
			# ki-be kapcsoló (a játékban is ugyanez: Beállítások → Kiegészítők)
			var sw := CheckButton.new()
			sw.text = "Bekapcsolva"
			sw.button_pressed = _dlc_enabled(d)
			sw.add_theme_font_size_override("font_size", 15)
			sw.add_theme_color_override("font_color", S.TEXT)
			sw.add_theme_color_override("font_pressed_color", S.GREEN)
			sw.add_theme_color_override("font_hover_pressed_color", S.GREEN)
			sw.tooltip_text = "Ki- vagy bekapcsolja a kiegészítőt a játékban (a következő indítástól)"
			sw.toggled.connect(func(on: bool): _set_dlc_enabled(d, on))
			btns.add_child(sw)
		else:
			var state := Label.new()
			state.text = "Nincs letöltve"
			state.add_theme_color_override("font_color", S.TEXT_DIM)
			btns.add_child(state)
		var dl := _button(btns, "Újratöltés" if _dlc_installed(d) else "Letöltés", func(): _download_dlc(d))
		dl.disabled = dlc_busy
		dl.add_theme_font_size_override("font_size", 15)
	else:
		var buy := _button(btns, "Megvásárlás – %s" % str(d["price"]), func(): _buy_dlc(d))
		buy.add_theme_font_size_override("font_size", 16)
		buy.add_theme_color_override("font_color", S.GOLD_LIGHT)
		buy.tooltip_text = "Megnyitja a vásárlási oldalt. Fizetés után e-mailben kapod a licenckulcsot."
		var key_btn := _button(btns, "Van kulcsom", func(): _open_license(d))
		key_btn.add_theme_font_size_override("font_size", 14)
	return card

func _draw_dlc_icon(c: Control, owned: bool) -> void:
	var cx := c.size.x / 2.0
	if owned:
		# arany pecsét pipával
		c.draw_circle(Vector2(cx, 20), 14, S.GOLD)
		c.draw_arc(Vector2(cx, 20), 14, 0, TAU, 32, S.BORDER, 1.5, true)
		c.draw_polyline(PackedVector2Array([Vector2(cx - 7, 20), Vector2(cx - 2, 26), Vector2(cx + 8, 13)]),
			S.PANEL_LT if S.skin == "heptarchia" else S.BG, 3.0, true)
		return
	# lakat: kengyel és test kulcslyukkal
	var ink := S.GOLD
	c.draw_arc(Vector2(cx, 16), 8, PI, TAU, 16, ink, 3.5, true)
	c.draw_line(Vector2(cx - 8, 16), Vector2(cx - 8, 21), ink, 3.5)
	c.draw_line(Vector2(cx + 8, 16), Vector2(cx + 8, 21), ink, 3.5)
	c.draw_rect(Rect2(cx - 13, 20, 26, 19), ink)
	c.draw_rect(Rect2(cx - 13, 20, 26, 19), S.BORDER, false, 1.5)
	var hole := S.PANEL_LT if S.skin == "heptarchia" else S.BG
	c.draw_circle(Vector2(cx, 27), 3.2, hole)
	c.draw_rect(Rect2(cx - 1.5, 28, 3, 7), hole)

# ── Fiók: regisztráció, belépés, a jogosultságok betöltése ───────

var acc_token := ""              # a belépés rövid életű tokenje (csak memóriában)
var acc_popup: PopupPanel
var acc_email_edit: LineEdit
var acc_pass_edit: LineEdit
var acc_status: Label
var acc_login_box: Control
var acc_out_box: Control
var acc_who: Label

func _acc_enabled() -> bool:
	return ACCOUNT_URL != "" and ACCOUNT_ANON_KEY != ""

func _acc_email() -> String:
	return str(cfg.get_value("account", "email", ""))

func _acc_logged_in() -> bool:
	return _acc_enabled() and str(cfg.get_value("account", "refresh_token", "")) != ""

# Egy kérés a fiókszerverhez: [HTTP-kód (0 = nem sikerült elérni), válasz (Dictionary / Array)]
func _acc_call(method: int, path: String, body = null, token: String = "") -> Array:
	var req := HTTPRequest.new()
	req.timeout = 30.0
	add_child(req)
	req.set_https_proxy(proxy_host, proxy_port)
	req.set_http_proxy(proxy_host, proxy_port)
	req.set_tls_options(TLSOptions.client_unsafe() if insecure_tls else TLSOptions.client())
	var headers := ["apikey: " + ACCOUNT_ANON_KEY, "Content-Type: application/json", "User-Agent: ParthLauncher"]
	if token != "": headers.append("Authorization: Bearer " + token)
	var err := req.request(ACCOUNT_URL + path, headers, method, "" if body == null else JSON.stringify(body))
	if err != OK:
		req.queue_free()
		return [0, {}]
	var res: Array = await req.request_completed
	req.queue_free()
	var data = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	var code: int = int(res[1]) if int(res[0]) == HTTPRequest.RESULT_SUCCESS else 0
	return [code, data if data != null else {}]

func _acc_store_session(data: Dictionary) -> void:
	acc_token = str(data.get("access_token", ""))
	cfg.set_value("account", "refresh_token", str(data.get("refresh_token", "")))
	var user: Dictionary = data.get("user", {}) if data.get("user") is Dictionary else {}
	if user.has("email"): cfg.set_value("account", "email", str(user["email"]))
	cfg.save(CFG_PATH)

# Induláskor: a mentett munkamenet frissítése, és a fiók kiegészítőinek betöltése
func _acc_refresh() -> void:
	if not _acc_logged_in(): return
	var r := await _acc_call(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=refresh_token",
		{"refresh_token": str(cfg.get_value("account", "refresh_token", ""))})
	if int(r[0]) == 200 and r[1] is Dictionary:
		_acc_store_session(r[1])
		await _acc_sync()
	elif int(r[0]) >= 400:
		_acc_logout(true)      # lejárt vagy visszavont munkamenet: újra be kell lépni
	_refresh_account_ui()

# A fiók kiegészítői: ezek „megvásároltak” lesznek (a ParthLauncher.cfg-ben ACC_LICENSE jellel)
func _acc_sync() -> void:
	if acc_token == "": return
	var r := await _acc_call(HTTPClient.METHOD_GET, "/rest/v1/entitlements?select=dlc_key", null, acc_token)
	if int(r[0]) != 200 or not r[1] is Array: return
	var owned := {}
	for row in r[1]:
		if row is Dictionary: owned[str(row.get("dlc_key", ""))] = true
	for game_key in DLCS:
		for d in DLCS[game_key]:
			var sect := "dlc:" + str(d["key"])
			var have := str(cfg.get_value(sect, "license", ""))
			if owned.has(str(d["key"])):
				if have == "": cfg.set_value(sect, "license", ACC_LICENSE)
			elif have == ACC_LICENSE:
				cfg.set_value(sect, "license", "")
	cfg.save(CFG_PATH)
	_refresh_dlc()
	_check_dlc_updates()

func _acc_login(signup: bool) -> void:
	var email := acc_email_edit.text.strip_edges()
	var pw := acc_pass_edit.text
	if email == "" or pw == "":
		acc_status.text = "Add meg az e-mail-címet és a jelszót."
		return
	if signup and pw.length() < 8:
		acc_status.text = "A jelszó legalább 8 karakter legyen."
		return
	acc_status.text = "Regisztráció…" if signup else "Belépés…"
	var path := "/auth/v1/signup" if signup else "/auth/v1/token?grant_type=password"
	var r := await _acc_call(HTTPClient.METHOD_POST, path, {"email": email, "password": pw})
	var code := int(r[0])
	var data: Dictionary = r[1] if r[1] is Dictionary else {}
	acc_pass_edit.text = ""
	if code == 0:
		acc_status.text = "Nem sikerült elérni a szervert. Van internet?"
		return
	if code >= 400:
		var msg := str(data.get("msg", data.get("error_description", data.get("message", ""))))
		if msg.to_lower().contains("confirm"):
			acc_status.text = "Előbb erősítsd meg az e-mail-címedet (nézd meg a leveleidet)."
		elif msg.to_lower().contains("already"):
			acc_status.text = "Ezzel az e-mail-címmel már van fiók – lépj be."
		else:
			acc_status.text = "Nem sikerült: hibás e-mail-cím vagy jelszó."
		return
	if data.has("access_token"):
		_acc_store_session(data)
		acc_status.text = ""
		acc_popup.hide()
		_status("Belépve: %s. A fiókodhoz tartozó kiegészítők betöltése…" % _acc_email(), S.GREEN)
		await _acc_sync()
		_refresh_account_ui()
	else:
		# regisztráció e-mail-megerősítéssel
		acc_status.text = "Elküldtük a megerősítő levelet a(z) %s címre. Kattints a benne lévő linkre, aztán lépj be." % email

func _acc_logout(silent: bool = false) -> void:
	acc_token = ""
	cfg.set_value("account", "refresh_token", "")
	for game_key in DLCS:
		for d in DLCS[game_key]:
			if str(cfg.get_value("dlc:" + str(d["key"]), "license", "")) == ACC_LICENSE:
				cfg.set_value("dlc:" + str(d["key"]), "license", "")
	cfg.save(CFG_PATH)
	_refresh_dlc()
	_refresh_account_ui()
	if not silent: _status("Kijelentkeztél.", S.TEXT)

func _build_account_popup() -> void:
	acc_popup = PopupPanel.new()
	add_child(acc_popup)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(520, 0)
	v.add_theme_constant_override("separation", 8)
	acc_popup.add_child(v)
	v.add_child(S.make_title("Fiók", 24, S.GOLD_LIGHT))
	var info := Label.new()
	info.text = "A megvásárolt kiegészítők a fiókodhoz kötődnek: bármelyik gépen belépve megjelennek. Vásárláskor ugyanazt az e-mail-címet add meg a Gumroadon."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(520, 0)
	info.add_theme_color_override("font_color", S.GOLD_LIGHT if S.skin == "heptarchia" else S.TEXT)
	v.add_child(info)
	var login := VBoxContainer.new()
	login.add_theme_constant_override("separation", 6)
	v.add_child(login)
	acc_login_box = login
	acc_email_edit = LineEdit.new()
	acc_email_edit.placeholder_text = "e-mail-cím"
	acc_email_edit.custom_minimum_size = Vector2(0, 36)
	acc_email_edit.add_theme_color_override("font_placeholder_color", Color(0.42, 0.32, 0.22))
	login.add_child(acc_email_edit)
	acc_pass_edit = LineEdit.new()
	acc_pass_edit.placeholder_text = "jelszó (legalább 8 karakter)"
	acc_pass_edit.secret = true
	acc_pass_edit.custom_minimum_size = Vector2(0, 36)
	acc_pass_edit.add_theme_color_override("font_placeholder_color", Color(0.42, 0.32, 0.22))
	acc_pass_edit.text_submitted.connect(func(_t): _acc_login(false))
	login.add_child(acc_pass_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	login.add_child(row)
	_button(row, "Belépés", func(): _acc_login(false)).size_flags_horizontal = SIZE_EXPAND_FILL
	_button(row, "Regisztráció", func(): _acc_login(true)).size_flags_horizontal = SIZE_EXPAND_FILL
	var out := VBoxContainer.new()
	out.add_theme_constant_override("separation", 6)
	v.add_child(out)
	acc_out_box = out
	acc_who = Label.new()
	acc_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	acc_who.add_theme_color_override("font_color", S.GREEN)
	out.add_child(acc_who)
	_button(out, "Kijelentkezés", func():
		_acc_logout()
		acc_popup.hide())
	acc_status = Label.new()
	acc_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	acc_status.custom_minimum_size = Vector2(520, 0)
	acc_status.add_theme_color_override("font_color", S.GOLD_LIGHT if S.skin == "heptarchia" else S.TEXT)
	v.add_child(acc_status)
	_button(v, "Bezárás", func(): acc_popup.hide())

func _open_account() -> void:
	if acc_popup == null: _build_account_popup()
	acc_status.text = ""
	acc_email_edit.text = _acc_email()
	_refresh_account_ui()
	# a tartalomhoz igazodó méret (a rejtett rész ne hagyjon üres helyet)
	acc_popup.size = Vector2i(560, 0)
	acc_popup.reset_size()
	acc_popup.popup_centered()
	if not _acc_logged_in(): acc_email_edit.grab_focus()

func _refresh_account_ui() -> void:
	if acc_popup != null:
		acc_login_box.visible = not _acc_logged_in()
		acc_out_box.visible = _acc_logged_in()
		acc_who.text = "Belépve: " + _acc_email()
	_refresh_dlc()

# A kulcs beváltása a bejelentkezett fiókba (a szerver ellenőrzi a Gumroadnál, és a fiókhoz köti)
func _acc_claim(key: String) -> void:
	if not _acc_logged_in() or acc_token == "":
		lic_status.text = "A kulcsot a fiókodhoz kötjük: előbb jelentkezz be (vagy regisztrálj)."
		license_popup.hide()
		_open_account()
		return
	dlc_busy = true
	lic_status.text = "Ellenőrzés…"
	var r := await _acc_call(HTTPClient.METHOD_POST, "/functions/v1/claim-license",
		{"dlc": str(lic_dlc["key"]), "license_key": key}, acc_token)
	dlc_busy = false
	var data: Dictionary = r[1] if r[1] is Dictionary else {}
	match int(r[0]):
		200:
			license_popup.hide()
			_status("Köszönjük! A(z) %s a fiókodhoz került (%s)." % [str(lic_dlc["name"]), _acc_email()], S.GREEN)
			await _acc_sync()
		0:
			lic_status.text = "Nem sikerült elérni a szervert. Van internet?"
		_:
			match str(data.get("error", "")):
				"key_taken": lic_status.text = "Ezt a kulcsot már egy másik fiókhoz kötötték."
				"not_logged_in": lic_status.text = "A belépés lejárt – jelentkezz be újra."
				_: lic_status.text = "Ez a kulcs nem érvényes ehhez a kiegészítőhöz. Ellenőrizd, hogy pontosan másoltad-e."

func _buy_dlc(d: Dictionary) -> void:
	var url := str(d["store_url"])
	if url == "":
		_status("A(z) %s még nem kapható – a bolt hamarosan megnyílik." % str(d["name"]), S.GOLD_LIGHT)
		return
	OS.shell_open(url)
	_status("A vásárlási oldal megnyílt a böngészőben. Fizetés után add meg a kapott kulcsot („Van kulcsom”).", S.GOLD_LIGHT)

func _build_license_popup() -> void:
	if license_popup != null and is_instance_valid(license_popup): license_popup.queue_free()
	license_popup = PopupPanel.new()
	add_child(license_popup)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(560, 0)
	v.add_theme_constant_override("separation", 8)
	license_popup.add_child(v)
	lic_title = S.make_title("Licenckulcs beváltása", 24, S.GOLD_LIGHT)
	v.add_child(lic_title)
	var l := Label.new()
	l.text = "Írd be (vagy másold be) a vásárlás után e-mailben kapott licenckulcsot:"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", S.GOLD_LIGHT if S.skin == "heptarchia" else S.TEXT)
	v.add_child(l)
	lic_edit = LineEdit.new()
	lic_edit.placeholder_text = "XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX"
	lic_edit.custom_minimum_size = Vector2(0, 36)
	lic_edit.text_submitted.connect(func(_t): _redeem_license())
	v.add_child(lic_edit)
	lic_status = Label.new()
	lic_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lic_status.add_theme_color_override("font_color", S.GOLD_LIGHT if S.skin == "heptarchia" else S.TEXT)
	v.add_child(lic_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_button(row, "Beváltás", _redeem_license).size_flags_horizontal = SIZE_EXPAND_FILL
	_button(row, "Mégse", func(): license_popup.hide()).size_flags_horizontal = SIZE_EXPAND_FILL

func _open_license(d: Dictionary) -> void:
	lic_dlc = d
	lic_title.text = "%s – licenckulcs" % str(d["name"])
	lic_edit.text = ""
	lic_status.text = ""
	license_popup.popup_centered()
	lic_edit.grab_focus()

# A kulcs ellenőrzése a Gumroad nyilvános licenc-szolgáltatásával (nem kell hozzá fiók vagy titkos kulcs)
func _redeem_license() -> void:
	var key := lic_edit.text.strip_edges()
	if key == "" or dlc_busy: return
	if _acc_enabled():
		_acc_claim(key)
		return
	var pid := str(lic_dlc.get("gumroad_product_id", ""))
	if pid == "":
		lic_status.text = "A bolt még nincs beállítva, ezért most nem lehet kulcsot beváltani."
		return
	dlc_busy = true
	lic_status.text = "Ellenőrzés…"
	# a beváltás számít: a Gumroad számolja, hányszor használták a kulcsot (egy kulcs csak egyszer váltható be)
	var body := "product_id=%s&license_key=%s&increment_uses_count=true" % [pid.uri_encode(), key.uri_encode()]
	for c in http_dlc.request_completed.get_connections():
		http_dlc.request_completed.disconnect(c["callable"])
	http_dlc.request_completed.connect(_on_license_checked.bind(key), CONNECT_ONE_SHOT)
	http_dlc.download_file = ""
	var err := http_dlc.request(GUMROAD_VERIFY, ["User-Agent: ParthLauncher", "Content-Type: application/x-www-form-urlencoded"],
		HTTPClient.METHOD_POST, body)
	if err != OK:
		dlc_busy = false
		lic_status.text = "Nem sikerült kapcsolódni (%d). Van internet?" % err

func _on_license_checked(result: int, code: int, _h: PackedStringArray, body: PackedByteArray, key: String) -> void:
	dlc_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		lic_status.text = "Nem sikerült elérni az ellenőrző szervert (%s)." % _result_text(result)
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	var purchase: Dictionary = data.get("purchase", {}) if data is Dictionary else {}
	var ok: bool = data is Dictionary and bool(data.get("success", false)) and code < 400 \
		and not bool(purchase.get("refunded", false)) and not bool(purchase.get("chargebacked", false)) \
		and not bool(purchase.get("disputed", false))
	if not ok:
		lic_status.text = "Ez a kulcs nem érvényes ehhez a kiegészítőhöz. Ellenőrizd, hogy pontosan másoltad-e."
		return
	# (a Gumroad próbavásárlásának kulcsa – csak az eladó saját fiókjából – is beváltható, a teszteléshez)
	# egy licenckulcs csak egyszer használható: ha ez már nem az első beváltás, elutasítjuk
	if int(data.get("uses", 1)) > 1:
		lic_status.text = "Ezt a kulcsot már beváltották. Egy licenckulcs csak egyszer használható – ha a tiéd, és új gépre telepítesz, írj nekünk."
		return
	cfg.set_value("dlc:" + str(lic_dlc["key"]), "license", key)
	cfg.save(CFG_PATH)
	license_popup.hide()
	_status("Köszönjük a vásárlást! A(z) %s feloldva." % str(lic_dlc["name"]), S.GREEN)
	_refresh_dlc()
	_check_dlc_updates()

# A csomag letöltése a játék adatmappájába (a játék a következő indításkor betölti).
# url / version: egy konkrét kiadás csomagja (a frissítés-ellenőrzés adja); üresen a legújabb.
func _download_dlc(d: Dictionary, url: String = "", version: String = "") -> void:
	if dlc_busy or _dlc_license(d) == "": return
	if url == "": url = str(d["download_url"])
	if url == "":
		_status("A(z) %s letöltése hamarosan elérhető lesz – a kulcsod el van mentve." % str(d["name"]), S.GOLD_LIGHT)
		return
	var dest := _dlc_zip_path(d)
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	dlc_busy = true
	_refresh_dlc()
	_status("A(z) %s letöltése…" % str(d["name"]))
	for c in http_dlc.request_completed.get_connections():
		http_dlc.request_completed.disconnect(c["callable"])
	http_dlc.request_completed.connect(_on_dlc_downloaded.bind(d, dest, version), CONNECT_ONE_SHOT)
	http_dlc.download_file = dest + ".tmp"
	if http_dlc.request(url, ["User-Agent: ParthLauncher"]) != OK:
		dlc_busy = false
		http_dlc.download_file = ""
		_status("A letöltést nem sikerült elindítani.", S.RED)
		_refresh_dlc()

func _on_dlc_downloaded(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray, d: Dictionary, dest: String,
		version: String) -> void:
	dlc_busy = false
	http_dlc.download_file = ""
	var tmp := dest + ".tmp"
	var zr := ZIPReader.new()
	var valid := result == HTTPRequest.RESULT_SUCCESS and code < 400 and zr.open(tmp) == OK
	if valid: zr.close()
	if not valid:
		DirAccess.remove_absolute(tmp)
		_status("A(z) %s letöltése nem sikerült (HTTP %d)." % [str(d["name"]), code], S.RED)
	else:
		DirAccess.remove_absolute(dest)
		DirAccess.rename_absolute(tmp, dest)
		var was := str(cfg.get_value("dlc:" + str(d["key"]), "version", ""))
		if version != "":
			cfg.set_value("dlc:" + str(d["key"]), "version", version)
			cfg.save(CFG_PATH)
		_refresh_dlc()
		_check_dlc_updates.call_deferred()      # ha több kiegészítőnek is van újabb változata
		_status(("A(z) %s frissítve (%s)." if was != "" else "A(z) %s telepítve (%s).") % [str(d["name"]), version]
			+ " A játék következő indításakor érvényes.", S.GREEN)
	_refresh_dlc()

# Induláskor és a „Frissítés keresése” gombra: a megvásárolt kiegészítők csomagja hiányzik-e
# (pl. új gépen), vagy van-e újabb kiadása – ha igen, magától letölti. Az összes játék
# kiegészítőjét nézi, nem csak a kiválasztottét (a csomag a játék adatmappájába kerül).
var _dlc_check_running := false

func _restore_owned_dlcs() -> void:
	_check_dlc_updates()

func _check_dlc_updates() -> void:
	if _dlc_check_running or dlc_busy: return
	_dlc_check_running = true
	for game_key in DLCS:
		for d in DLCS[game_key]:
			if _dlc_license(d) == "": continue
			var have := str(cfg.get_value("dlc:" + str(d["key"]), "version", ""))
			var latest := await _latest_dlc_release(d)      # [címke, letöltési cím] vagy []
			if latest.is_empty():
				# a kiadások nem érhetők el: legalább a hiányzó csomagot pótoljuk
				if not _dlc_installed(d) and str(d["download_url"]) != "":
					_dlc_check_running = false
					_download_dlc(d)
					return
				continue
			if _dlc_installed(d) and have == str(latest[0]): continue
			_dlc_check_running = false
			_status("A(z) %s új változata letöltés alatt (%s)…" % [str(d["name"]), str(latest[0])], S.GOLD_LIGHT)
			_download_dlc(d, str(latest[1]), str(latest[0]))
			return
	_dlc_check_running = false

# A csomag legújabb kiadása: [címke, letöltési cím], vagy [] ha nem sikerült lekérdezni
func _latest_dlc_release(d: Dictionary) -> Array:
	var api := str(d.get("releases_api", ""))
	if api == "": return []
	var body := await _fetch_text(api)
	var data = JSON.parse_string(body) if body != "" else null
	if not data is Array: return []
	var want := str(d["key"]) + ".zip"
	for rel in data:
		if not rel is Dictionary or bool(rel.get("draft", false)) or bool(rel.get("prerelease", false)): continue
		for a in rel.get("assets", []):
			if str(a.get("name", "")) == want:
				return [str(rel.get("tag_name", "")), str(a.get("browser_download_url", ""))]
	return []

# ── Frissítés keresése ────────────────────────────────────────

func check_latest() -> void:
	if busy or repo_owner == "": return
	busy = true
	remote = {}
	_refresh_labels()
	_status("Frissítés keresése…")
	_progress(0, "")
	_request("%s/repos/%s/%s/releases/latest" % [API, repo_owner, repo], _on_release_checked)
	# A gombnyomásra az indító a saját változatát és a kiegészítőket is újranézi.
	_check_home_launcher()
	_check_dlc_updates()

# ── Mindkét játék változata (a füleken) ───────────────────────
#
# Egyetlen könnyű kérdés játékonként: mi a legfrissebb kiadás címkéje.
# Külön HTTPRequest végzi, hogy ne akassza meg a letöltést, és sorban
# halad, mert egy csomópont egyszerre egy kérést tud.
func _sweep_versions() -> void:
	_sweep_sor.clear()
	for g in GAMES:
		_sweep_sor.append(str(g["key"]))
	_sweep_next()

func _sweep_next() -> void:
	if _sweep_sor.is_empty(): return
	var key := str(_sweep_sor.pop_front())
	var g := _game_by_key(key)
	if g.is_empty():
		_sweep_next()
		return
	var rr := _repo_of(g)
	for c in http_info.request_completed.get_connections():
		http_info.request_completed.disconnect(c["callable"])
	http_info.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			_on_version_answer(key, result, code, body),
		CONNECT_ONE_SHOT)
	var err := http_info.request("%s/repos/%s/%s/releases/latest" % [API, rr[0], rr[1]],
		HEADERS)
	if err != OK: _sweep_next()

func _on_version_answer(key: String, result: int, code: int,
		body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) == TYPE_DICTIONARY:
			var v := str(data.get("tag_name", ""))
			if v != "":
				latest_ver[key] = v
				cfg.set_value("latest", key, v)
				# A leírást is eltesszük: így a MÁSIK játék fülén is rögtön
				# ott van, mit hoz az ő legfrissebb változata.
				_remember_notes(key, v, str(data.get("published_at", "")).substr(0, 10),
					str(data.get("body", "")).strip_edges())
				_refresh_labels()
				if key == str(game()["key"]) and remote.is_empty(): _show_notes(key)
	_sweep_next()

func _game_by_key(key: String) -> Dictionary:
	for g in GAMES:
		if str(g["key"]) == key: return g
	return {}

# Egy játék telepített változata (akkor is, ha épp nem az van kiválasztva).
func _installed_of(key: String) -> String:
	if key == str(game()["key"]): return installed_version
	return str(cfg.get_value("state:" + key, "version", ""))

func _request(url: String, handler: Callable, to_file: String = "") -> void:
	for c in http.request_completed.get_connections():
		http.request_completed.disconnect(c["callable"])
	http.request_completed.connect(handler, CONNECT_ONE_SHOT)
	http.download_file = to_file
	var err := http.request(url, HEADERS)
	if err != OK:
		busy = false
		_status("Nem sikerült elindítani a letöltést (hiba %d)." % err, S.RED)
		_refresh_labels()

func _on_release_checked(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		# Sok iskolai hálózat épp az api.github.com címet tiltja: próbáljuk a github.com-ot
		_status("A frissítési szolgáltatás nem válaszol (%s) – másik úton próbálom…" % _result_text(result))
		_check_via_atom()
		return
	if code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) == TYPE_DICTIONARY:
			var asset := _pick_asset(data.get("assets", []))
			if not asset.is_empty():
				latest_ver[str(game()["key"])] = str(data.get("tag_name", "?"))
				remote = {"mode": "release", "version": str(data.get("tag_name", "?")),
					"url": str(asset.get("browser_download_url", "")), "size": int(asset.get("size", 0)),
					"notes": str(data.get("body", "")), "date": str(data.get("published_at", ""))}
				busy = false
				_after_check()
				return
	# nincs használható kiadás: a fő ág legfrissebb állapota jön
	_status("Nincs kiadás; a(z) „%s” ág legfrissebb változatát nézem…" % branch)
	_request("%s/repos/%s/%s/commits/%s" % [API, repo_owner, repo, branch], _on_commit_checked)

# A kiadás mellékletei közül a MOSTANI rendszerre való JÁTÉK csomagját választjuk
# (az indító saját csomagját és a más rendszerekre valókat kihagyjuk).
func _pick_asset(assets: Array) -> Dictionary:
	var mac := _is_mac()
	var game_key := str(game()["key"]).to_lower()
	var best := {}
	var best_score := -999
	for a in assets:
		var n: String = str(a.get("name", "")).to_lower()
		if not n.ends_with(".zip"): continue
		var score := 0
		if n.contains("launcher") or n.contains("indito"): score -= 20
		if n.contains(game_key): score += 4
		if n.contains("source"): score -= 3
		if mac:
			if n.contains("mac") or n.contains("osx") or n.contains("darwin"): score += 6
			if n.contains("windows") or n.contains("win") or n.contains("linux"): score -= 8
		else:
			if n.contains("windows") or n.contains("win"): score += 6
			if n.contains("mac") or n.contains("osx") or n.contains("linux") or n.contains("darwin"): score -= 8
			if n.contains("x86_64") or n.contains("x64") or n.contains("amd64"): score += 1
			if n.contains("aarch64") or n.contains("arm"): score -= 6
		if score > best_score:
			best_score = score
			best = a
	return best if best_score > -10 else {}

# A kiadás mellékletei közül a MOSTANI rendszerre való INDÍTÓ csomagja
func _pick_launcher_asset(assets: Array) -> Dictionary:
	var mac := _is_mac()
	for a in assets:
		var n: String = str(a.get("name", "")).to_lower()
		if not n.ends_with(".zip"): continue
		if not (n.contains("launcher") or n.contains("indito")): continue
		var is_mac_asset: bool = n.contains("mac") or n.contains("osx") or n.contains("darwin")
		if is_mac_asset == mac: return a
	return {}

static func _is_mac() -> bool:
	return OS.get_name() == "macOS"

func _on_commit_checked(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_check_via_atom()
		return
	busy = false
	if code == 409:
		# a GitHub ezt adja, ha a tároló még üres (nincs benne feltöltés)
		_status("Ehhez a játékhoz még nincs kiadott változat.", S.RED)
		_refresh_labels()
		return
	if code == 404:
		# A játék még nem érhető el a frissítési szolgáltatásban. A felület
		# SEMMILYEN belső részletet nem mutat (címek, fióknevek): a játékosra
		# ezek nem tartoznak.
		_status("Ez a játék még nem érhető el. Próbáld később, vagy nézd meg a másik fület.", S.RED)
		txt_notes.text = "[b]Ez a játék most nem érhető el.[/b]\n\n"\
			+ "Vagy még nincs kiadott változata, vagy a hálózat nem engedi a "\
			+ "letöltést. A másik játék füle addig is működik.\n\n"\
			+ "Szűrt hálózaton segíthet a Beállítások → Hálózati vizsgálat."
		_refresh_labels()
		return
	if code != 200:
		_status("A frissítés most nem érhető el (HTTP %d)." % code, S.RED)
		_refresh_labels()
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		_status("Váratlan válasz a frissítési szolgáltatástól.", S.RED)
		_refresh_labels()
		return
	var sha := str(data.get("sha", "")).substr(0, 7)
	var commit: Dictionary = data.get("commit", {})
	remote = {"mode": "source", "version": sha,
		"url": "https://codeload.github.com/%s/%s/zip/refs/heads/%s" % [repo_owner, repo, branch],
		"size": 0, "notes": str(commit.get("message", "")),
		"date": str(commit.get("author", {}).get("date", ""))}
	_after_check()

# Tartalék: a github.com/…/commits/<ág>.atom hírcsatornából is kiderül a legfrissebb változat
func _check_via_atom() -> void:
	_request("https://github.com/%s/%s/commits/%s.atom" % [repo_owner, repo, branch], _on_atom_checked)

func _on_atom_checked(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_status("A frissítés nem érhető el erről a hálózatról (%s, HTTP %d). Nyomd meg a „Hálózati vizsgálat” gombot!"
			% [_result_text(result), code], S.RED)
		_refresh_labels()
		return
	var text := body.get_string_from_utf8()
	var marker := "Grit::Commit/"
	var idx := text.find(marker)
	if idx < 0:
		_status("Nem sikerült kiolvasni a változat azonosítóját.", S.RED)
		_refresh_labels()
		return
	var sha := text.substr(idx + marker.length(), 40)
	var title := ""
	var t_idx := text.find("<title>", idx)
	if t_idx >= 0:
		title = text.substr(t_idx + 7, maxi(0, text.find("</title>", t_idx) - t_idx - 7)).strip_edges()
	remote = {"mode": "source", "version": sha.substr(0, 7),
		"url": "https://codeload.github.com/%s/%s/zip/refs/heads/%s" % [repo_owner, repo, branch],
		"size": 0, "notes": title, "date": ""}
	_after_check()

func _result_text(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT: return "nem tud csatlakozni"
		HTTPRequest.RESULT_CANT_RESOLVE: return "a címet nem találja (DNS)"
		HTTPRequest.RESULT_CONNECTION_ERROR: return "kapcsolati hiba"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: return "tanúsítvány-hiba (szűrt hálózat?)"
		HTTPRequest.RESULT_TIMEOUT: return "időtúllépés"
		HTTPRequest.RESULT_SUCCESS: return "rendben"
	return "hibakód %d" % result

func _after_check() -> void:
	var v: String = str(remote["version"])
	var date := str(remote.get("date", "")).substr(0, 10)
	var notes := str(remote.get("notes", "")).strip_edges()
	_remember_notes(str(game()["key"]), v, date, notes)
	_show_notes(str(game()["key"]))
	var up_to_date: bool = v == installed_version
	if up_to_date and _game_installed():
		_status("A játék készen áll.", S.GREEN)
		if auto_play: _auto_launch()
	elif up_to_date:
		_status("A %s változat hiányos – letöltöm újra." % v, S.RED)
	elif installed_version == "":
		_status("Nyomd meg a Frissítés gombot a letöltéshez.", S.GOLD_LIGHT)
	else:
		_status("Új változat érhető el.", S.GOLD_LIGHT)
	_refresh_labels()
	# Ha magának az indítónak van új változata, AZ élvez elsőbbséget: kicseréli
	# magát, újraindul, és utána az új indító tölti le a játékot.
	if launcher_update > 0 and auto_update:
		return
	# magától letölti az újat (ha a felhasználó nem kapcsolta ki)
	if auto_update and _needs_download():
		start_update()

# ── „Mi van a mostani változatban?” ───────────────────────────
#
# A leírásmezőben MINDIG ott áll, mit hoz a legfrissebb változat — akkor is,
# ha épp most indult a program, ha a másik játék fülén állunk, és akkor is,
# ha nincs hálózat: a legutóbb látott szöveget eltesszük a beállításfájlba.
func _remember_notes(key: String, v: String, date: String, notes: String) -> void:
	cfg.set_value("notes:" + key, "version", v)
	cfg.set_value("notes:" + key, "date", date)
	cfg.set_value("notes:" + key, "text", notes)
	cfg.save(CFG_PATH)

func _show_notes(key: String) -> void:
	if txt_notes == null: return
	var g := _game_by_key(key)
	var v := str(cfg.get_value("notes:" + key, "version", str(latest_ver.get(key, ""))))
	var date := str(cfg.get_value("notes:" + key, "date", ""))
	var notes := str(cfg.get_value("notes:" + key, "text", "")).strip_edges()
	var nev := str(g.get("name", key)).capitalize()
	if v == "":
		txt_notes.text = "[b]%s[/b]\n\nA változat adatait még töltöm…" % nev
		return
	var fej := "[b]%s %s[/b]%s" % [nev, v, ("   (%s)" % date) if date != "" else ""]
	var itt := _installed_of(key)
	var allapot := ""
	if itt == "":
		allapot = "Még nincs telepítve."
	elif itt == v:
		allapot = "Ez a változat van telepítve."
	else:
		allapot = "Telepítve: %s — ez a frissítés újabb." % itt
	txt_notes.text = "%s\n[i]%s[/i]\n\n%s" % [fej, allapot,
		notes if notes != "" else "(ehhez a változathoz nincs leírás)"]

# ── Az indító önfrissítése ────────────────────────────────────
#
# A „home” tárolóban (Birodalom) lévő launcher/VERSION.txt mondja meg, mikor
# változott maga az indító. Ha újabb, MAGÁTÓL letölti onnan a saját csomagját,
# kicseréli magát, és újraindul — nem kell hozzá gombot nyomni. (Kikapcsolható:
# „Frissítés keresése induláskor”; olyankor a nagy gomb kínálja fel.)
#
# Ezt a játéktól FÜGGETLENÜL nézzük meg: akkor is fut, ha épp a Heptarchia
# fülén állunk. A csomag mindig a Birodalom kiadásából jön — a másik játék
# saját (régi, egyjátékos) indítójával sosem cserélnénk ki magunkat.

func _check_home_launcher() -> void:
	if _home_check_running or OS.has_feature("editor"): return
	_home_check_running = true
	launcher_update = 0
	home_launcher_asset = {}
	var home := {}
	for g in GAMES:
		if bool(g.get("home", false)): home = g
	if home.is_empty():
		_home_check_running = false
		return
	var rr := _repo_of(home)
	var body := await _fetch_text("%s/repos/%s/%s/releases/latest" % [API, rr[0], rr[1]])
	var data = JSON.parse_string(body) if body != "" else null
	if typeof(data) != TYPE_DICTIONARY:
		_home_check_running = false
		return
	var asset := _pick_launcher_asset((data as Dictionary).get("assets", []))
	var tag := str((data as Dictionary).get("tag_name", ""))
	if asset.is_empty() or tag == "":
		_home_check_running = false
		return
	# FONTOS: a változatfájlt annak a kiadásnak a címkéjéről olvassuk, amelyikből a
	# csomag jön — így a letöltött indító azt a számot hozza, amit itt látunk
	# (nincs körbe-frissítés).
	var text := await _fetch_text("https://raw.githubusercontent.com/%s/%s/%s/%s"
		% [rr[0], rr[1], tag, VERSION_FILE])
	var build := int(text.strip_edges())
	_home_check_running = false
	if build <= LAUNCHER_BUILD: return
	home_launcher_asset = asset
	launcher_update = build
	_refresh_labels()
	if not auto_update:
		_status("Az indítónak új változata van – nyomd meg a gombot!", S.GOLD_LIGHT)
		return
	_status("Az indítónak új változata van – frissítem magamat…", S.GOLD_LIGHT)
	# Ha épp tölt valamit, megvárjuk: két letöltés nem futhat egyszerre.
	var vart := 0.0
	while busy and vart < 180.0:
		await get_tree().create_timer(0.5).timeout
		vart += 0.5
	if busy: return
	start_launcher_update()

func _fetch_text(url: String) -> String:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)
	req.set_https_proxy(proxy_host, proxy_port)
	req.set_http_proxy(proxy_host, proxy_port)
	req.set_tls_options(TLSOptions.client_unsafe() if insecure_tls else TLSOptions.client())
	if req.request(url, HEADERS) != OK:
		req.queue_free()
		return ""
	var r: Array = await req.request_completed
	req.queue_free()
	if int(r[0]) != HTTPRequest.RESULT_SUCCESS or int(r[1]) != 200: return ""
	return (r[3] as PackedByteArray).get_string_from_utf8()

func start_launcher_update() -> void:
	if busy or home_launcher_asset.is_empty(): return
	busy = true
	_refresh_labels()
	_status("Az indító frissítése – letöltés…")
	_progress(0, "0%")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LAUNCHER_ZIP_TMP))
	_request(str(home_launcher_asset.get("browser_download_url", "")),
		_on_launcher_downloaded, LAUNCHER_ZIP_TMP)
	set_process(true)

func _on_launcher_downloaded(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	set_process(false)
	http.download_file = ""
	busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
		_status("Az indító letöltése nem sikerült (HTTP %d)." % code, S.RED)
		_refresh_labels()
		return
	_status("Kicsomagolás…")
	_progress(100, "kicsomagolás…")
	await get_tree().process_frame
	var stage := ProjectSettings.globalize_path(LAUNCHER_STAGE)
	if DirAccess.dir_exists_absolute(stage): _rm_tree(stage)
	var err := _extract_zip(ProjectSettings.globalize_path(LAUNCHER_ZIP_TMP), stage)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LAUNCHER_ZIP_TMP))
	if err != "":
		_status(err, S.RED)
		_refresh_labels()
		return
	err = _swap_launcher(stage)
	if err != "":
		_status(err, S.RED)
		_refresh_labels()
		return
	_status("Az indító frissül és újraindul…", S.GREEN)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()

# Kicseréli a futó indítót az újra: egy kis segédszkript megvárja, míg kilépünk,
# átmásolja az újat a régi helyére, majd elindítja. Windowson és Macen is működik.
func _swap_launcher(stage: String) -> String:
	var target := OS.get_executable_path()
	if _is_mac():
		var idx := target.find(".app/")
		if idx < 0: return "Nem találom az indító csomagját."
		target = target.substr(0, idx + 4)                      # …/ParthLauncher.app
		var new_app := _find_any_app(stage)
		if new_app == "": return "A letöltött csomagban nincs indító."
		var sh := ProjectSettings.globalize_path("user://frissites.sh")
		if not _write_text(sh, mac_swap_script(target, new_app, stage, OS.get_process_id())):
			return "Nem sikerült megírni a frissítő szkriptet."
		OS.create_process("/bin/sh", [sh])
		return ""
	var new_exe := _find_file(stage, func(f: String): return f.ends_with(".exe") and not f.to_lower().contains("console"))
	if new_exe == "": return "A letöltött csomagban nincs indító."
	var bat := ProjectSettings.globalize_path("user://frissites.bat").replace("/", "\\")
	if not _write_text(bat, windows_swap_script(target, new_exe, stage)):
		return "Nem sikerült megírni a frissítő szkriptet."
	# rejtve (ablak nélkül) futtatjuk: a „start” parancssor-ablakot nyitna, ami a szkript után is nyitva maradna
	OS.create_process("cmd.exe", ["/c", bat], false)
	return ""

# A csereszkriptek szövege (külön, hogy ellenőrizhető legyen).
# Windows: a futó .exe-t nem lehet felülírni, ezért addig próbálkozik, míg ki nem léptünk.
# Az új indítót az Intéző indítja (explorer.exe), hogy ne kötődjön a szkript parancssor-ablakához,
# a szkript pedig hibaüzenet nélkül törli magát („(goto) & del”).
static func windows_swap_script(target: String, new_exe: String, stage: String) -> String:
	var t := target.replace("/", "\\")
	var n := new_exe.replace("/", "\\")
	var s := stage.replace("/", "\\")
	return "@echo off\r\n" \
		+ "setlocal enabledelayedexpansion\r\n" \
		+ "set /a tries=0\r\n" \
		+ ":loop\r\n" \
		+ "copy /y \"" + n + "\" \"" + t + "\" >nul 2>&1\r\n" \
		+ "if not errorlevel 1 goto done\r\n" \
		+ "set /a tries+=1\r\n" \
		+ "if !tries! geq 60 goto done\r\n" \
		+ "ping -n 2 127.0.0.1 >nul\r\n" \
		+ "goto loop\r\n" \
		+ ":done\r\n" \
		+ "rmdir /s /q \"" + s + "\" >nul 2>&1\r\n" \
		+ "explorer.exe \"" + t + "\"\r\n" \
		+ "(goto) 2>nul & del \"%~f0\"\r\n"

# macOS: megvárja, míg a futó indító kilép, majd kicseréli a .app csomagot
static func mac_swap_script(target: String, new_app: String, stage: String, pid: int) -> String:
	return "#!/bin/sh\n" \
		+ "i=0\n" \
		+ "while [ $i -lt 60 ] && kill -0 " + str(pid) + " 2>/dev/null; do sleep 0.5; i=$((i+1)); done\n" \
		+ "rm -rf \"" + target + "\"\n" \
		+ "cp -R \"" + new_app + "\" \"" + target + "\"\n" \
		+ "chmod -R +x \"" + target + "/Contents/MacOS\"\n" \
		+ "xattr -dr com.apple.quarantine \"" + target + "\" 2>/dev/null\n" \
		+ "open \"" + target + "\"\n" \
		+ "rm -rf \"" + stage + "\"\n" \
		+ "rm -f \"$0\"\n"

func _write_text(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return false
	f.store_string(text)
	f.close()
	return true

func _find_any_app(dir_path: String, depth: int = 3) -> String:
	var d := DirAccess.open(dir_path)
	if d == null: return ""
	for sub in d.get_directories():
		if sub.ends_with(".app"): return dir_path.path_join(sub)
	if depth <= 0: return ""
	for sub in d.get_directories():
		var found := _find_any_app(dir_path.path_join(sub), depth - 1)
		if found != "": return found
	return ""

# Rövid várakozás után indítja a játékot, hogy a felhasználó lássa, mi történt
func _auto_launch() -> void:
	await get_tree().create_timer(1.5).timeout
	if not busy and _game_installed(): play()

# ── Diagnosztika: melyik cím érhető el a hálózatról? ──────────

func run_diagnostics() -> void:
	if busy: return
	busy = true
	_refresh_labels()
	_status("Hálózati vizsgálat…")
	var lines: PackedStringArray = ["[b]Hálózati vizsgálat[/b]", ""]
	lines.append("Proxy: %s" % (proxy_text() if proxy_text() != "" else "nincs beállítva"))
	lines.append("Tanúsítvány-ellenőrzés: %s" % ("KIKAPCSOLVA" if insecure_tls else "bekapcsolva"))
	lines.append("")
	# A vizsgálat NEM írja ki a címeket és a fiókneveket — csak azt, hogy az
	# egyes útvonalak működnek-e. A hibakeresésnek ennyi elég.
	var targets := [
		["1. kapcsolat", "%s/rate_limit" % API, HTTPClient.METHOD_GET],
		["2. kapcsolat", "https://github.com/%s/%s/commits/%s.atom" % [repo_owner, repo, branch], HTTPClient.METHOD_GET],
		["3. letöltés", "https://codeload.github.com/%s/%s/zip/refs/heads/%s" % [repo_owner, repo, branch], HTTPClient.METHOD_HEAD],
		["4. adatlap", "https://raw.githubusercontent.com/%s/%s/%s/README.md" % [repo_owner, repo, branch], HTTPClient.METHOD_HEAD]
	]
	for t in targets:
		var res := await _probe(t[1], t[2])
		lines.append("%-26s %s" % [t[0], res])
		txt_notes.text = "\n".join(lines)
	lines.append("")
	lines.append("Ha mind hibás: a hálózat tiltja a frissítést, vagy proxy kell (Beállítások).")
	lines.append("Ha „tanúsítvány-hiba” látszik: kapcsold be a Beállításokban az iskolai hálózat módot.")
	txt_notes.text = "\n".join(lines)
	busy = false
	_status("A vizsgálat kész – az eredmény a mezőben.", S.TEXT)
	_refresh_labels()

func _probe(url: String, method: int = HTTPClient.METHOD_HEAD) -> String:
	var probe := HTTPRequest.new()
	probe.timeout = 12.0
	add_child(probe)
	probe.set_https_proxy(proxy_host, proxy_port)
	probe.set_http_proxy(proxy_host, proxy_port)
	probe.set_tls_options(TLSOptions.client_unsafe() if insecure_tls else TLSOptions.client())
	var err := probe.request(url, HEADERS, method)
	if err != OK:
		probe.queue_free()
		return "indítási hiba (%d)" % err
	var r: Array = await probe.request_completed
	probe.queue_free()
	var result: int = r[0]
	var code: int = r[1]
	if result != HTTPRequest.RESULT_SUCCESS: return "NEM ÉRHETŐ EL – " + _result_text(result)
	if code >= 400: return "elérhető, de HTTP %d" % code
	return "rendben (HTTP %d)" % code

# ── Letöltés és telepítés ─────────────────────────────────────

func _zip_tmp() -> String:
	return "user://%s_update.zip" % str(game()["key"])

func start_update() -> void:
	if busy or remote.is_empty(): return
	if remote["mode"] == "source" and godot_exe == "":
		_status("Forrás módhoz add meg a Godot .exe útvonalát a Beállításokban!", S.RED)
		return
	busy = true
	_refresh_labels()
	_status("Letöltés…")
	_progress(0, "0%")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_zip_tmp()))
	_request(str(remote["url"]), _on_downloaded, _zip_tmp())
	set_process(true)

func _process(_delta: float) -> void:
	if not busy or http == null or http.download_file == "": return
	var total: int = http.get_body_size()
	var got: int = http.get_downloaded_bytes()
	if total > 0:
		_progress(got * 100.0 / total, "%.1f / %.1f MB" % [got / 1048576.0, total / 1048576.0])
	elif got > 0:
		_progress(0, "%.1f MB" % (got / 1048576.0))

func _on_downloaded(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	set_process(false)
	http.download_file = ""
	if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
		busy = false
		_status("A letöltés nem sikerült (HTTP %d)." % code, S.RED)
		_refresh_labels()
		return
	_progress(100, "kicsomagolás…")
	_status("Kicsomagolás…")
	await get_tree().process_frame
	var err := _install(ProjectSettings.globalize_path(_zip_tmp()))
	busy = false
	if err != "":
		_status(err, S.RED)
	else:
		installed_version = str(remote["version"])
		installed_mode = str(remote["mode"])
		_fix_mac_permissions()
		_save_cfg()
		_status("Kész: a %s változat telepítve. Indíthatod a játékot!" % installed_version, S.GREEN)
		_progress(100, "kész")
		if installed_mode == "source":
			_start_import()      # forrásból letöltve elő kell készíteni az erőforrásokat
		elif auto_play:
			_auto_launch()
	_refresh_labels()

# ── Erőforrások előkészítése (csak forrás mód) ────────────────
# A tárolóban nincs benne a Godot .godot/ mappája, ezért az első indítás előtt
# egyszer le kell futtatni az importálást, különben hiányoznak a képek és a hangok.

func _needs_import() -> bool:
	var project := _game_project()
	return project != "" and not DirAccess.dir_exists_absolute(project.path_join(".godot/imported"))

func _start_import() -> void:
	if godot_exe == "" or not FileAccess.file_exists(godot_exe) or not _needs_import():
		if auto_play: _auto_launch()
		return
	busy = true
	_refresh_labels()
	_status("Első indítás előtt: az erőforrások előkészítése (fél perc is lehet)…")
	_progress(0, "előkészítés")
	_import_thread = Thread.new()
	_import_thread.start(_import_work.bind(_game_project()))

func _import_work(project: String) -> void:
	OS.execute(godot_exe, ["--headless", "--path", project, "--import"])
	call_deferred("_import_done")

func _import_done() -> void:
	if _import_thread: _import_thread.wait_to_finish()
	_import_thread = null
	busy = false
	_progress(100, "kész")
	_status("Kész: a %s változat telepítve és előkészítve." % installed_version, S.GREEN)
	_refresh_labels()
	if auto_play: _auto_launch()

# A csomag kibontása a telepítési mappába. Hibaüzenetet ad vissza ("" = rendben).
func _install(zip_path: String) -> String:
	var marker := str(game()["marker"])
	# a korábbi telepítés törlése (csak ha az indító hozta létre)
	if DirAccess.dir_exists_absolute(install_dir):
		if FileAccess.file_exists(install_dir.path_join(marker)):
			_rm_tree(install_dir)
		elif not _dir_empty(install_dir):
			return "A telepítési mappa nem üres, és nem az indító hozta létre: %s" % install_dir
	var err := _extract_zip(zip_path, install_dir)
	if err != "": return err
	var m := FileAccess.open(install_dir.path_join(marker), FileAccess.WRITE)
	if m: m.store_string("ParthLauncher – ezt a mappát az indító kezeli.\n")
	DirAccess.remove_absolute(zip_path)
	return ""

# Egy zip kibontása a megadott mappába ("" = rendben)
func _extract_zip(zip_path: String, dest: String) -> String:
	var zr := ZIPReader.new()
	if zr.open(zip_path) != OK: return "A letöltött csomagot nem sikerült megnyitni."
	var files := zr.get_files()
	if files.is_empty(): return "A letöltött csomag üres."
	var strip := _common_prefix(files)
	DirAccess.make_dir_recursive_absolute(dest)
	for f in files:
		if f.ends_with("/"): continue
		var rel: String = f.substr(strip.length())
		if rel == "": continue
		var target := dest.path_join(rel)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var out := FileAccess.open(target, FileAccess.WRITE)
		if out == null:
			zr.close()
			return "Nem sikerült írni: %s" % target
		out.store_buffer(zr.read_file(f))
		out.close()
	zr.close()
	return ""

# A GitHub zip-jei egy közös mappával kezdődnek (pl. "birodalom-abc1234/") – ezt vágjuk le.
# FONTOS: a macOS-csomagban minden fájl a „…app/” mappában van – az a program maga,
# azt nem szabad levágni, különben szétesik az alkalmazás.
func _common_prefix(files: PackedStringArray) -> String:
	var first: String = files[0]
	var slash := first.find("/")
	if slash < 0: return ""
	var prefix := first.substr(0, slash + 1)
	if prefix.to_lower().ends_with(".app/"): return ""
	for f in files:
		if not f.begins_with(prefix): return ""
	return prefix

func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null: return
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		_rm_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)

func _dir_empty(path: String) -> bool:
	var d := DirAccess.open(path)
	return d != null and d.get_files().is_empty() and d.get_directories().is_empty()

# ── Indítás ───────────────────────────────────────────────────

func _find_file(dir_path: String, matcher: Callable, depth: int = 3) -> String:
	var d := DirAccess.open(dir_path)
	if d == null: return ""
	for f in d.get_files():
		if matcher.call(f): return dir_path.path_join(f)
	if depth <= 0: return ""
	for sub in d.get_directories():
		var found := _find_file(dir_path.path_join(sub), matcher, depth - 1)
		if found != "": return found
	return ""

func _game_exe() -> String:
	if _is_mac():
		var app := _find_app(install_dir)
		return app.path_join("Contents/MacOS").path_join(_mac_binary(app)) if app != "" else ""
	# A konzolos segédprogram (…console.exe) mellette van, azt nem indítjuk.
	return _find_file(install_dir, func(f: String):
		return f.ends_with(".exe") and not f.to_lower().contains("unins") \
			and not f.to_lower().contains("console"))

# macOS: a letöltött csomagban egy .app "mappa" van
func _find_app(dir_path: String, depth: int = 3) -> String:
	var d := DirAccess.open(dir_path)
	if d == null: return ""
	for sub in d.get_directories():
		if sub.ends_with(".app") and not sub.to_lower().contains("indito") \
				and not sub.to_lower().contains("launcher"):
			return dir_path.path_join(sub)
	if depth <= 0: return ""
	for sub in d.get_directories():
		var found := _find_app(dir_path.path_join(sub), depth - 1)
		if found != "": return found
	return ""

func _mac_binary(app_path: String) -> String:
	var d := DirAccess.open(app_path.path_join("Contents/MacOS"))
	if d == null: return ""
	var files := d.get_files()
	return files[0] if not files.is_empty() else ""

# A ZIP-ből kicsomagolt fájlok elvesztik a futtatási jogot, a Mac pedig „karanténba” teszi
# a letöltött programokat – ezt kell rendbe tenni, különben nem indul el.
func _fix_mac_permissions() -> void:
	if not _is_mac(): return
	var app := _find_app(install_dir)
	if app == "": return
	OS.execute("/bin/chmod", ["-R", "+x", app.path_join("Contents/MacOS")])
	OS.execute("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app])

func _game_project() -> String:
	var p := _find_file(install_dir, func(f: String): return f == "project.godot")
	return p.get_base_dir() if p != "" else ""

func _game_installed() -> bool:
	if not DirAccess.dir_exists_absolute(install_dir): return false
	return _game_exe() != "" or _game_project() != ""

func play() -> void:
	var exe := _game_exe()
	if exe != "":
		if _is_mac():
			_fix_mac_permissions()
			OS.create_process("/usr/bin/open", ["-a", _find_app(install_dir)])
		else:
			OS.create_process(exe, [])
		_status("A játék elindult.", S.GREEN)
		await get_tree().create_timer(1.5).timeout
		get_tree().quit()
		return
	var project := _game_project()
	if project == "":
		_status("Nem találom a telepített játékot. Tölts le egy változatot!", S.RED)
		return
	if godot_exe == "" or not FileAccess.file_exists(godot_exe):
		_status("Ehhez a változathoz Godot kell. Add meg az elérési útját a Beállításokban!", S.RED)
		return
	if _needs_import():
		_start_import()          # ha még nem futott le, most pótoljuk
		return
	OS.create_process(godot_exe, ["--path", project])
	_status("A játék elindult (Godot).", S.GREEN)
	await get_tree().create_timer(1.5).timeout
	get_tree().quit()
