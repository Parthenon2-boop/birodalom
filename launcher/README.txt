ParthLauncher  —  Birodalom és Heptarchia egy programban
======================================================

Önálló Godot-projekt (nem része a játéknak). Két játékot kezel: fent a két gombbal
lehet köztük váltani. Mindkettőt a saját GitHub-tárolójából tölti le, külön mappába,
külön változatszámmal, majd elindítja.

  Birodalom    Parthenon2-boop/birodalom    ->  <indító melletti>\Birodalom
  Heptarchia   Parthenon2-boop/heptarchia   ->  <indító melletti>\Heptarchia

Indítás fejlesztéshez:
  Godot_v4.7.2-stable_win64.exe --path launcher

Beállítások a programban (Beállítások gomb), mentve ide:
  %APPDATA%\Godot\app_userdata\ParthLauncher\ParthLauncher.cfg
  - a KIVÁLASZTOTT játék telepítési mappája (az indító csak az általa létrehozott
    mappát üríti; ezt a <jatek>_launcher.marker fájl jelzi)
  - Godot .exe útvonala (csak forrás módhoz)
  - proxy / tanúsítvány-ellenőrzés (iskolai hálózathoz)

A tárolók BE VANNAK ÉGETVE, ezért a többi gépen semmit nem kell beállítani.
Felülírni az indító mellé tett repo.txt fájllal lehet, soronként:
  birodalom=felhasznalonev/tarolonev
  heptarchia=felhasznalonev/tarolonev@ag

Két üzemmód, magától választ:
  release – ha a tárolóban van kiadás .zip melléklettel: a kész játékot tölti le és
            indítja (nem kell Godot a gépre). A JÁTÉK csomagját választja, nem az indítóét.
  source  – ha nincs kiadás: a megadott ág legfrissebb állapotát tölti le, és a helyi
            Godottal indítja.

Kinézet: az indító annak a játéknak a stílusát veszi föl, amelyik ki van választva —
a Birodalom sötétbarna-arany felületét, a Heptarchia pergamen-bőr indítóját (Uncial
címbetű, rúnasor, EB Garamond szöveg). A betűk az assets/fonts mappában vannak.

Önfrissítés: MAGÁTÓL megy. Az indító induláskor (és a „Frissítés keresése” gombra)
megnézi a BIRODALOM tárolójának legutóbbi kiadását — függetlenül attól, melyik fülön
állsz —, és ha a launcher/VERSION.txt nagyobb, mint a programba épített LAUNCHER_BUILD,
letölti a saját csomagját, kicseréli magát, és újraindul. Gombot nem kell nyomni hozzá;
a „Frissítés keresése induláskor” kikapcsolásával lehet kézire váltani. A Heptarchia
kiadásában lévő (régi, egyjátékos) indítóval SOHA nem cseréli ki magát.
Ha az indítón változtatsz, MINDKETTŐT növeld:
  launcher/scripts/launcher.gd -> LAUNCHER_BUILD
  launcher/VERSION.txt

Exportálás Windowsra (export sablonok kellenek hozzá):
  godot --headless --path launcher --export-release "Windows Desktop" build/launcher/ParthLauncher.exe
