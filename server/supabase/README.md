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
