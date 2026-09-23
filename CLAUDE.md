# Birodalom – útmutató Claude-nak

Valós idejű stratégiai játék 1400–1945 között, **Godot 4.7.2, GDScript, GL Compatibility**.
A projekt egy HTML5/Canvas játék (`index.html`) portjaként indult, de mára jóval túlnőtte az
eredeti tervet. Az első, „építsd fel elölről” specifikáció a `docs/eredeti_port_terv.md` fájlban
van — **csak történeti anyag**, a benne lévő kód és táblák elavultak. Mindig a valódi forrás a mérvadó.

## Fő jellemzők

- Négy korszak (`age` 0–3), tizenegy nemzet (zászlók és uralkodóképek: `assets/flags`, `assets/rulers`).
- Pályatípusok (`GameState.map_type`, leírásuk a `WorldGen.MAPS` táblában), kalózvilág
  (`GameState.pirate`, nagyobb pálya, hírnév, karibi városok), hadjárat (`Campaign` autoload,
  `assets/campaign`), oktatómód, visszajátszás (`user://replays/*.brep`).
- Hálózati többjátékos mód: a szimuláció a **házigazdán** fut, a kliens (`GameState.net_client`)
  csak a pillanatképet rajzolja ki (`Net` autoload, `scripts/systems/NetSync.gd`).
- Magyar, angol és német nyelv: `assets/lang/*`, a `Lang` autoload.

## Felépítés

| Hely | Tartalom |
|---|---|
| `Main.gd`, `scenes/Main.tscn` | a játszma gyökere: építési költségek, kijelölés, a rendszerek példányosítása, parancssori kapcsolók |
| `scripts/globals/` | autoloadok: `Lang`, `Campaign`, `GameState`, `SFX`, `SaveManager`, `Settings`, `Achievements`, `Net` |
| `scripts/units/` | `Unit.gd`, `UnitSprite.gd` (rajzolás korszakonként), `Combat.gd` |
| `scripts/buildings/` | `Building.gd`, `BuildArt.gd` (épületrajzok) |
| `scripts/world/` | `WorldGen`, `Terrain`, `FogOfWar`, `Wildlife`, `Scars` (csatanyomok), `Broadside` |
| `scripts/systems/` | gazdaság, piac, városok, diplomácia, események, időjárás, napszak, fejlesztések, küldetéscél, oktató, visszajátszás, hálózati szinkron, utófeldolgozás |
| `scripts/ai/BotAI.gd` | a gépi ellenfél |
| `scripts/ui/` | `HUD`, `Menu`, `MiniMap`, `PortMenu`, `Scoreboard`, `SettingsPanel`, `Style` |
| `scripts/dev/` | `SelfTest.gd`, `NetTest.gd` — önteszt, a kiadásba nem kerül bele |
| `assets/shaders/` | víz, köd és utófeldolgozás shaderek |
| `launcher/` | **ParthLauncher**: önálló Godot-projekt, közös indító és frissítő a Birodalomhoz, a Heptarchiához és a Kard és Mágiához (fiók, vásárolt DLC-k letöltése) |
| `server/supabase/` | a fiókrendszer (Supabase adatbázis + Edge Functions, Gumroad-ping) beállítása |
| `docs/` | `hirek.json` (a launcher hírfolyama), promóciós szövegek, az eredeti terv |
| `.github/workflows/` | `kiadas.yml` (`v*` címkére Windows + macOS build és GitHub-kiadás), `boritok.yml` |

## Szabályok és buktatók

- A pálya mérete **nem állandó**: `GameState.WORLD_W/H` értékét mindig a `set_world_size()` állítja
  (a kalózvilág nagyobb). Ne kódolj be 3400×2400-at.
- A költségtáblákban (pl. `Main.BUILD_COST`) minden épületnek legyen bejegyzése — a hiányzó
  kulcs üres költséget ad, vagyis ingyen építhető lesz.
- Hálózati játékban a játékszabály csak a házigazdán futhat; új rendszernél ügyelj rá, hogy a
  kliensen ne szimuláljon.
- A megjegyzések és a felhasználói szövegek magyarul, ékezetekkel íródnak; a felületi szöveg a
  nyelvi fájlokba kerüljön, ne a kódba.
- A `service_role` Supabase-kulcs soha nem kerülhet a launcherbe vagy a játékba.
- Mentések: `%APPDATA%\Godot\app_userdata\Birodalom` (`user://`), frissítéskor megmaradnak.

## Futtatás és ellenőrzés

```
Godot_v4.7.2-stable_win64.exe --path .                 # játék
Godot_v4.7.2-stable_win64.exe --path launcher          # indító
Godot_v4.7.2-stable_win64_console.exe --headless --path . --quit-after 8000 -- --skip-menu --selftest
```

A selftest kilépési kódja 0, ha minden rendben. Változtatás után ezt futtasd.
További kapcsolók (`Main.gd`): `--pirate`, `--tutorial`, `--replay`, `--nethost`, `--reveal`,
`--nocull`, `--nobloom`, valamint képernyőképes nézetek: `--showcase`, `--shiptest`,
`--weapontest`, `--jellegtest`, `--bloomtest`, `--portmenu`, `--gamemenu`, `--gamemenu-settings`
(a `SelfTest.gd`-ben még: `--epuletmenu`, `--tisztakep`).

## Kiadás

Commit + push után `git tag vX.Y` és `git push origin vX.Y`: a GitHub Actions elkészíti a
Windows .exe-t és az univerzális macOS .app-ot, a launcher pedig innen tölti le.
A `Feltoltes GitHubra.bat` egy lépésben commitol és pushol.
