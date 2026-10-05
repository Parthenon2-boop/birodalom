# Fiókhoz kötött kiegészítők – Supabase beállítás

1. **Projekt:** supabase.com → New project (ingyenes csomag elég).
2. **Adatbázis:** SQL Editor → New query → `schema.sql` tartalma → Run.
3. **Belépés:** Authentication → Sign In / Providers → Email: bekapcsolva, „Confirm email” bekapcsolva.
4. **Függvények:** Edge Functions → Deploy a new function → Via Editor:
   - `gumroad-ping` ← `functions/gumroad-ping/index.ts`; a függvény beállításainál a **Verify JWT legyen KIKAPCSOLVA**.
   - `claim-license` ← `functions/claim-license/index.ts` (Verify JWT maradhat bekapcsolva).
   - `login-nev` ← `functions/login-nev/index.ts`; itt is **KIKAPCSOLVA** a Verify JWT (belépés előtt még nincs token).
5. **Titok:** Edge Functions → Secrets → `GUMROAD_PING_SECRET` = egy hosszú, véletlen szöveg.
6. **Gumroad:** Settings → Advanced → Ping endpoint:
   `https://<projekt>.supabase.co/functions/v1/gumroad-ping?secret=<ugyanaz a titok>`
7. **Launcher:** Project Settings → API → a projekt URL-je és az `anon` / publishable kulcs kerül a
   `launcher.gd` `ACCOUNT_URL` és `ACCOUNT_ANON_KEY` állandóiba. A `service_role` kulcs TITKOS, soha ne kerüljön a launcherbe.

## Fióknév (felhasználónév) – v1.36

Hogy a játékos ne az e-mail-címével, hanem a **fióknevével** lépjen be:

1. **Adatbázis:** SQL Editor → New query → `schema_fioknev.sql` tartalma → Run.
   Ez hozza létre a `profiles` táblát (név → fiók), a regisztrációs triggert és a
   `fioknev_szabad(nev)` függvényt (csak igen/nem választ ad, e-mail-címet nem).
2. **Függvény:** Edge Functions → `login-nev` (lásd fent) – **Verify JWT KIKAPCSOLVA**.
   A fióknévhez tartozó e-mail-címet ez keresi ki a titkos kulccsal, és csak a kész
   munkamenetet adja vissza: a cím sosem kerül ki a kliensbe.
3. **Régi fiókok:** akiknek még nincs nevük, a belépőmezőbe az e-mail-címüket írva
   ugyanúgy be tudnak lépni (a weboldalon és a launcherben is).

## Védett kiegészítők – `dlc-access` (launcher 37, Heptarchia 1.59)

A csomagok tárolója (`heptarchia-dlc-csomagok`) PRIVÁT. Letöltési linket és a játéknak szóló, aláírt
jogosultsági igazolást csak a `dlc-access` függvény ad, csak a bejelentkezett, jogosult fióknak.
A játék (DLC.gd) csak érvényes, erre a gépre szóló igazolással tölt be telepített csomagot.

1. **GitHub-token:** github.com → Settings → Developer settings → Fine-grained tokens → Generate:
   Repository access: *Only select repositories* → `heptarchia-dlc-csomagok`;
   Permissions → Repository → **Contents: Read-only**. (Semmi más.)
2. **Függvény:** Edge Functions → Deploy a new function → Via Editor → neve `dlc-access`,
   tartalma `functions/dlc-access/index.ts`. **Verify JWT: BEKAPCSOLVA.**
3. **Titkok** (Edge Functions → Secrets):
   - `DLC_SIGN_KEY` = a `TITKOS/dlc_alairo_PRIVAT_kulcs.pem` teljes tartalma (a BEGIN/END sorokkal együtt).
     A párja (nyilvános kulcs) a játék `scripts/DLC.gd`-jében van. A titkos kulcs SOHA nem kerülhet gitbe,
     a launcherbe vagy a játékba.
   - `GITHUB_TOKEN` = az 1. pont tokenje.
4. Ha a függvény él, és a launcher 37 + Heptarchia 1.59 kint van: a `heptarchia-dlc-csomagok` tárolót
   **privátra** kell állítani (Settings → General → Danger Zone → Change visibility → Private).

## Belépés a weboldalon + admin felület (`fiok.html`, `admin.html`, `admin` függvény)

**Mit tud?** A `fiok.html`-en bárki beléphet a fiókjával (fióknévvel vagy e-mail-címmel): látja a
fióknevét, a játékokat, a Heptarchia-kiegészítőket (melyik van meg, melyiket lehet megvenni) és a
Kard és Mágia érmeegyenlegét. Ha a fiók **admin**, megjelenik egy „Admin felület” link → `admin.html`:
fiókok száma, fióklista kereséssel (fióknév, kitakart e-mail, regisztráció, utolsó belépés, érme,
kiegészítők), kiegészítő ajándékba adása / visszavonása, érme jóváírása / levonása indoklással, és a
napló. Az admin-jogot minden kérésnél a szerver ellenőrzi (`public.admins` tábla); a weboldalon nincs
semmi titok, a `service_role` kulcs csak a függvényben van.

Hol vannak az adatok: kiegészítők → `entitlements` (aktív = `revoked = false`, a fiókhoz `user_id`-vel
vagy még csak a vásárlási e-mail-címmel kötve); érme → `coin_tx` (az egyenleg a sorok összege, a
játék a `my_coins` nézetből olvassa); admin-napló → `admin_log`.

### Telepítés (egyszer)

1. **Adatbázis:** SQL Editor → New query → `schema_admin.sql` tartalma → Run.
   (Ez egyben a `buy_cosmetic` jogosultsági hibáját is javítja – lásd a fájl alját.)
2. **Tedd magad adminná** (SQL Editor, a fióknevet írd át):
   ```sql
   insert into public.admins (user_id)
   select user_id from public.profiles where username = 'IDE_A_FIOKNEVED'
   on conflict do nothing;
   -- ellenőrzés:
   select a.user_id, p.username from public.admins a left join public.profiles p using (user_id);
   ```
   Admin elvétele: `delete from public.admins where user_id = '<uuid>';`
3. **Függvények** (PowerShell, a `Birodalom_Godot\server` mappából; a token: supabase.com → Account →
   Access Tokens):
   ```powershell
   $env:SUPABASE_ACCESS_TOKEN = Get-Content "<a token fájlja>" -Raw
   $env:SUPABASE_ACCESS_TOKEN = $env:SUPABASE_ACCESS_TOKEN.Trim()
   npx --yes supabase@latest functions deploy admin --project-ref gxvepswtairfqvosdcpb --use-api --no-verify-jwt
   npx --yes supabase@latest functions deploy login-nev --project-ref gxvepswtairfqvosdcpb --use-api --no-verify-jwt
   ```
   - `admin`: a `--no-verify-jwt` szándékos – a függvény minden kérésnél maga ellenőrzi a tokent és az
     admin-jogot (a böngésző token nélküli CORS-előkérése így nem akad el a kapun).
   - `login-nev`: CORS-fejlécet kapott, hogy a weboldal is fióknévvel léptethessen be. **A
     `--no-verify-jwt` itt KÖTELEZŐ**, különben a launcher belépése elromlik.
   - Új titok nem kell: a `SUPABASE_URL`, `SUPABASE_ANON_KEY` és a szerveroldali kulcs magától ott van.
     Ha a weboldalt más címről is el akarod érni (pl. helyi teszt), az `ADMIN_ORIGINS` titokba vesszővel
     elválasztva írhatsz további címeket (alapból csak `https://parthenon2-boop.github.io`).
4. **Weboldal:** a `docs/` változásai (fiok.html, admin.html, a menü) a szokásos pusholással kerülnek ki.
   Az `admin.html` nincs a menüben és a sitemapben, `noindex` – de a védelmet nem ez adja, hanem a szerver.

Beállítás a függvényben: `SHOW_FULL_EMAIL` (alapból `false` → a listában csak `pa•••@gmail.com` látszik).

## Játékidő és „most online” (launcher 45, `jelenlet` függvény)

A launcher a játék indításakor munkamenetet nyit (`jelenlet` → `start`, a fiók tokenjével), majd bezárul;
egy rejtett figyelő (Windows: PowerShell a játék folyamatazonosítójával, macOS: `/bin/sh` a `.app` futó
programjának keresésével) 2 percenként jelez (`beat`), a játék kilépésekor lezárja (`stop`). Alvás /
hibernálás (15 percnél nagyobb szünet) nem számít játékidőnek. Az admin felület ebből mutatja a
fiókonkénti (és játékonkénti) játékidőt, és zöld pöttyel, ki játszik most (4 percen belüli jelzés).

1. **Adatbázis:** SQL Editor → `schema_jelenlet.sql` tartalma → Run (a `jatek_munkamenet` tábla és az
   `admin_jatekido` összesítő; csak a szerverfüggvények érik el).
2. **Függvények** (a `server` mappából, mint fent):
   ```powershell
   npx --yes supabase@latest functions deploy jelenlet --project-ref gxvepswtairfqvosdcpb --use-api --no-verify-jwt
   npx --yes supabase@latest functions deploy admin --project-ref gxvepswtairfqvosdcpb --use-api --no-verify-jwt
   ```
   Amíg a tábla nincs meg, a `jelenlet` 503-at ad (`nincs_tabla`) – a launcher ettől még elindítja a játékot,
   az admin oldalon pedig „–” látszik.

Korlát: csak a launcherből, belépve indított játék számít. macOS-en a figyelő a futó program elérési útját
keresi (`ps`); ha nem találja 90 mp-en belül, a munkamenet lezárul (rövid, legfeljebb néhány perces idő).

## Heptarchia a böngészőben (`heptarchia-web` függvény, privát `heptarchia-web` tároló)

A böngészős Heptarchiát csak bejelentkezett (regisztrált) fiók játszhatja. A honlapon (`docs/jatek/heptarchia/`)
csak a betöltő van (`index.html`, a Godot-motor `index.js` / `index.wasm`-ja); maga a játék (`index.pck`) a PRIVÁT
`heptarchia-web` tárolóban. Belépés után az oldal a `heptarchia-web` függvénytől kér linket: a függvény ellenőrzi a
tokent, a felfüggesztést, az oldalt (Origin: csak `https://parthenon2-boop.github.io` és fejlesztéshez
`http://localhost:*`), a korlátot (fiókonként óránként 30 link), naplóz (`heptarchia_web_log`), és 5 percig érvényes,
aláírt letöltési linket ad. A csomagot a heptarchia tároló CI-je (`.github/workflows/web.yml`) tölti fel minden
`v*` címkénél, egy csak feltöltésre jó kulccsal. A többjátékos szobák jelzőcsatornái (Realtime, `hep-<kód>`) privátak:
csak bejelentkezett fiók léphet be.

### Telepítés (egyszer)

1. **Adatbázis:** SQL Editor → `schema_heptarchia_web.sql` tartalma → Run (a tároló, a napló, a Realtime-szabályok).
2. **Realtime:** Project Settings → Realtime (vagy Realtime → Settings) → **Allow public access: KI** (csak privát csatorna).
3. **Titok** (Edge Functions → Secrets): `HEP_WEB_FELTOLTO_KULCS` = egy hosszú, véletlen szöveg, pl. PowerShellben:
   `-join ((48..57)+(65..90)+(97..122) | Get-Random -Count 48 | % {[char]$_})`
4. **Függvény** (a `server` mappából, mint fent):
   ```powershell
   npx --yes supabase@latest functions deploy heptarchia-web --project-ref gxvepswtairfqvosdcpb --use-api --no-verify-jwt
   ```
   A `--no-verify-jwt` szándékos: a függvény maga ellenőrzi a tokent (a böngésző CORS-előkérése token nélkül jön).
5. **GitHub:** a `Parthenon2-boop/heptarchia` tároló → Settings → Secrets and variables → Actions → New repository
   secret: `HEP_WEB_FELTOLTO_KULCS` = ugyanaz, mint a 3. pontban.
6. **Első csomag:** heptarchia tároló → Actions → „Heptarchia böngészős változat” → Run workflow (vagy a következő
   `v*` címke). Ellenőrzés: Storage → `heptarchia-web` → `aktualis.json` és `<verzió>/index.pck`.

Korlátok (ingyenes csomag): egy fájl legfeljebb 50 MB (a csomag most ~40 MB); a Storage-forgalom havi 5 GB – a
böngésző verziónként egyszer tölti le a csomagot (gyorsítótár), utána nem; sok új játékos esetén ez elfogyhat.

### Online játék csak meghívottaknak (`schema_heptarchia_online.sql`, Heptarchia 1.86.4-től)

A böngészős Heptarchia többjátékos szobáiba csak a `heptarchia_online_engedely` listán lévő fióknevek léphetnek
be (kisbetűsen, Unicode NFC-alakban tárolva: a kis-nagybetű és az ékezet kódolása nem számít). A védelem a
szerveren van: a `hep-%` Realtime-csatornák szabályai a `heptarchia_online_engedelyes()` függvénnyel ellenőrzik a
belépett fiókot. A játék ugyanezt a függvényt kérdezi (`/rest/v1/rpc/heptarchia_online_engedelyes`), és aki nincs a
listán, annak a Többjátékos gombja le van tiltva (magyarázattal); az egyjátékos mód mindenkinek megmarad.
Az asztali (letölthető) változat helyi hálózati játékát (ENet, fiók nélkül) ez nem érinti.

1. **Adatbázis:** SQL Editor → `schema_heptarchia_online.sql` tartalma → Run (a `schema_heptarchia_web.sql` után;
   annak a két szobaszabályát cseréli le). Az első három meghívott: `tojasosnokedli`, `OlivérVető`, `parthenon2`.
2. **Admin felület** (nem kötelező): `npx --yes supabase@latest functions deploy admin --project-ref gxvepswtairfqvosdcpb --use-api --no-verify-jwt`
   – utána az `admin.html` „Online játék” fülén lehet meghívni / elvenni (naplózva). Enélkül SQL-ből (lásd a fájl elejét).

### Közvetítő (TURN) szerver a többjátékos szobákhoz (`heptarchia-turn`, Heptarchia 1.86.6-tól)

A böngészős többjátékos mód WebRTC: a gépek közvetlenül kapcsolódnak. Mobilnet és iskolai / céges hálózat között
ez nem jön létre („A szoba megvan, de a közvetlen kapcsolat nem jött létre”) – ilyenkor a forgalom egy közvetítőn
megy át (Cloudflare Realtime TURN, havi 1000 GB-ig ingyenes). A játék a szobanyitáskor / csatlakozáskor a
`heptarchia-turn` függvénytől kér rövid életű belépőt (csak bejelentkezett, meghívott fiók kap); ha a függvény
vagy a titkok hiányoznak, a játék közvetítő nélkül próbálkozik (mint eddig).

1. **Cloudflare:** dash.cloudflare.com (ingyenes fiók) → Realtime → TURN Server → Create. Két érték kell:
   „Turn Token ID” és „API Token”.
2. **Titkok:** Supabase → Edge Functions → Secrets: `CF_TURN_KEY_ID` (a Turn Token ID) és `CF_TURN_API_TOKEN`.
3. **Függvény:** `npx --yes supabase@latest functions deploy heptarchia-turn --project-ref gxvepswtairfqvosdcpb --use-api --no-verify-jwt`
