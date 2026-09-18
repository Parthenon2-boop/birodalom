# Birodalom

Valós idejű stratégiai játék 1400-tól 1945-ig (Godot 4.7.2, GL Compatibility).
Négy korszak (15. század, 17. század, 19. század, 20. század), tizenegy nemzet,
hadjárat, kalózvilág és hálózati többjátékos mód. Magyar, angol és német nyelven.

## Indítás

- **Játék:** nyisd meg a mappát a Godot 4.7.2-vel, vagy futtasd:
  `Godot_v4.7.2-stable_win64.exe --path .`
- **Indító (ajánlott):** a `launcher` mappa önálló Godot-projekt — **egy indító két játékhoz**
  (Birodalom és Heptarchia). Mindig letölti a GitHubról a legfrissebb változatot, majd elindítja:
  `Godot_v4.7.2-stable_win64.exe --path launcher`

## Mindig a legfrissebb változat minden gépen

1. A saját gépeden a változtatás után: `Feltoltes GitHubra.bat` (vagy `git add -A`,
   `git commit -m "…"`, `git push`).
2. A többi gépen csak az **indítót** kell elindítani: megnézi a GitHubot, letölti az újat, és indít.
3. Ha a többi gépre nem akarsz Godotot telepíteni, készíts kiadást: `git tag v1.0` és
   `git push origin v1.0`. A GitHub Actions (`.github/workflows/kiadas.yml`) elkészíti a Windows
   .exe-t és a macOS .app-ot, az indító pedig azt tölti le.

## Mac (MacBook) – első indítás

A kiadásban a `ParthLauncher-macos.zip` (és a `Birodalom-macos.zip`) univerzális
(Intel + Apple Silicon) csomag, ad-hoc aláírással. Mivel nincs Apple fejlesztői tanúsítvány,
a macOS az első indításkor tiltakozhat:

1. Csomagold ki a zipet (dupla kattintás), és húzd az `.app`-ot az **Alkalmazások** mappába.
2. **Jobb klikk (vagy Ctrl + kattintás) az ikonra → Megnyitás**, majd a párbeszédben ismét *Megnyitás*.
3. Ha „sérült, a Lomtárba kellene helyezni” üzenet jön, a letöltési karantént kell levenni.
   Terminál (Alkalmazások → Segédprogramok → Terminál):
   ```
   xattr -dr com.apple.quarantine "/Applications/ParthLauncher.app"
   xattr -dr com.apple.quarantine "/Applications/Birodalom.app"
   ```
4. Újabb macOS-en (Sequoia) a 2. lépés helyett: **Rendszerbeállítások → Adatvédelem és biztonság**,
   görgess le, és a Birodalomnál nyomd meg a **Mégis megnyitom** gombot.

Ezt elég egyszer megcsinálni; az indító a későbbi frissítéseket már magától kezeli
(a letöltött játékról maga veszi le a karantént és állítja be a futtatási jogot).

## Mappák

| Mappa | Mi van benne |
|---|---|
| `scripts/` | játéklogika, egységek, épületek, bot, világ, hálózat (Net), felület |
| `scenes/` | főmenü, játék, egység, épület, felület |
| `assets/` | sprite-ok, hangok, zászlók, uralkodóképek, nyelvi fájlok, shaderek |
| `scripts/dev/` | önteszt és fejlesztői eszközök (a kiadásba nem kerül bele) |
| `launcher/` | a közös indító és frissítő (önálló Godot-projekt): Birodalom + Heptarchia |

A mentések a felhasználói mappába kerülnek
(`%APPDATA%\Godot\app_userdata\Birodalom`), ezért frissítéskor megmaradnak.

## Önellenőrzés

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --quit-after 8000 -- --skip-menu --selftest
```

Kilépési kód 0 = minden rendben. A `--shiptest`, `--weapontest` és `--showcase`
kapcsolókkal a grafika nézhető át egy képernyőképen.
