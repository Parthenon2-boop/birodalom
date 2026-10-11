# Korszakzenék – előállítás kódból

A Birodalom négy háttérzenéje (`assets/audio/music_age0.ogg … music_age3.ogg`)
nem felvétel: ez a mappa szintetizálja őket, mintafájlok és letöltés nélkül.
A kotta adatként van leírva, így a zene később átírható és újra előállítható.

| Fájl | Mi van benne |
|---|---|
| `darabok.py` | a négy darab **kottája**: forma, akkordmenet, dallamok, kíséretminták, hangszerelés, szólamok erőssége |
| `kotta.py` | a kottajelölés értelmezője, akkordok, és a zenei önellenőrzés (hangkészlet, súrlódó hangközök) |
| `hang.py` | a hangszerek (vonós, réz, furulya, nádsíp, lant, hárfa, csembaló, dobok), a zengető és a körkörös keverő |
| `general.py` | a fő szkript: szintetizál, hangosságra állít, Ogg Vorbis fájlt ír és visszaellenőrzi |
| `ellenor.py` | a kész fájlok mérése (csúcs, hangosság, hurokpont, spektrum) és spektrogramok |

A mappában `.gdignore` van: a Godot nem néz bele.

## Futtatás

A Blender saját Pythonja kell hozzá (benne van a numpy és az `aud` modul, amely
az Ogg Vorbis kódolást adja). A projekt gyökeréből:

```
blender.exe -b --factory-startup --python tools/zene/general.py                 # mind a négy darab
blender.exe -b --factory-startup --python tools/zene/general.py -- --csak 2     # csak a 2. korszak
blender.exe -b --factory-startup --python tools/zene/general.py -- --kotta      # csak a zenei önellenőrzés
blender.exe -b --factory-startup --python tools/zene/ellenor.py -- --kep C:\temp\kepek
```

Utána a Godotnak újra kell importálnia: `Godot… --headless --path . --import`,
majd az önteszt (`-- --skip-menu --selftest`), és ha hallani/mérni is akarod a
lejátszást: `Godot… --audio-driver Dummy --path . --script res://scripts/dev/ZeneProba.gd`.

Belehallgatáshoz WAV is kérhető – **ne** az `assets/audio` mappába:

```
blender.exe -b --factory-startup --python tools/zene/general.py -- --wav --ki C:\temp\zene
```

Egy teljes futás nagyjából egy perc. Ugyanabból a kottából mindig ugyanaz a
hang lesz (a véletlenek rögzített magról indulnak) – az Ogg fájl néhány száz
bájtja viszont futásonként más (a folyam sorszáma véletlen, vele az oldalak
ellenőrzőösszegei is), ezért a git újrageneráláskor akkor is módosultnak
mutatja a fájlokat, ha a zene nem változott. Csak azt a darabot generáld újra
(`--csak N`), amelyikhez hozzányúltál.

## Amire figyelni kell

- **Varratmentes hurok.** A keverőpuffer pontosan egy ismétlésnyi hosszú, és
  minden, ami a végén túllógna (lecsengés, zengés), az elejére fordul vissza;
  a zengető is körkörös konvolúció. A hurkolást a `.ogg.import` fájl
  `loop=true` beállítása adja – ha a Godot újra létrehozza az importfájlt,
  ezt ellenőrizd (az önteszt szól, ha hiányzik).
- **A hossz 4096 minta többszöröse** (a `general.py` erre kerekít, a tempó
  ettől ezrelékekkel tér el). A Blender Vorbis-írója a fájl utolsó töredék-
  keretét torzan zárja le, ami a hurokpontnál kattanna; a `general.py` minden
  írás után visszaolvassa a fájlt, és hibával megáll, ha a vége torzabb, mint
  a közepe.
- **Hangosság.** Minden darab −20 dBFS átlagos (RMS) szintre és legfeljebb
  −3 dBFS csúcsra van állítva (`CEL_RMS_DB`, `CSUCS_DB` a `general.py`-ban),
  hogy korszakváltáskor ne ugorjon a hangerő, és az effektek alatt maradjon.
- **Új dallam írásakor** futtasd a `--kotta` módot: kiírja szólamonként a
  hangkészletet, és `!` jellel megjelöli a 0,4 mp-nél tovább együtt szóló kis
  szekundot, nagy szeptimet és tritónuszt. Az elírt ritmust az ütemvonalak
  (`|`) ellenőrzése fogja meg.
- A szólamok egymáshoz mért szintjét a `darabok.py` szólamtáblái adják
  (`sz(típus, hangszer, erősség, panoráma, zengetés, …)`); a `general.py`
  futáskor kiírja a szólamszinteket.

## A darabok

| Fájl | Cím | Hangnem, ütem, tempó | Hangszerelés | Forma |
|---|---|---|---|---|
| `music_age0` | Udvari tánc | d-dór, 3/4, ♩=96 | furulya, nádsíp, lant, hárfa, burdon, kézidob | bevezetés – A – A' – B – A'' – C – átvezetés (48 ütem) |
| `music_age1` | Palotabeli muzsika | G-dúr / e-moll, 4/4, ♩=84 | szólóhegedű, fuvola, csembaló, járó basszus, vonós continuo | A – A' – B – A'' (32 ütem) |
| `music_age2` | Díszszemle | Esz-dúr / Asz-dúr trió, 4/4, ♩=100 | hegedűk, kürtök, klarinét, harsona, pizzicato, pergődob, nagydob | bevezetés – A – A' – trió – A'' – zárórész (40 ütem) |
| `music_age3` | Hosszú menet | c-moll, 4/4, ♩=75 | kürtök, harsonák, hegedűk, nádsíp, mélyvonós ostinato, tompított dob, üstdob | bevezetés – A – B – A' – átvezetés (32 ütem) |

Mind a négy saját szerzemény; nem idéz meglévő művet vagy népdalt. A főmenü a
0. korszak zenéjével szól (`SFX.MUSIC_MENU`).
