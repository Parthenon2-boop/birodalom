# Fiókhoz kötött kiegészítők – Supabase beállítás

1. **Projekt:** supabase.com → New project (ingyenes csomag elég).
2. **Adatbázis:** SQL Editor → New query → `schema.sql` tartalma → Run.
3. **Belépés:** Authentication → Sign In / Providers → Email: bekapcsolva, „Confirm email” bekapcsolva.
4. **Függvények:** Edge Functions → Deploy a new function → Via Editor:
   - `gumroad-ping` ← `functions/gumroad-ping/index.ts`; a függvény beállításainál a **Verify JWT legyen KIKAPCSOLVA**.
   - `claim-license` ← `functions/claim-license/index.ts` (Verify JWT maradhat bekapcsolva).
5. **Titok:** Edge Functions → Secrets → `GUMROAD_PING_SECRET` = egy hosszú, véletlen szöveg.
6. **Gumroad:** Settings → Advanced → Ping endpoint:
   `https://<projekt>.supabase.co/functions/v1/gumroad-ping?secret=<ugyanaz a titok>`
7. **Launcher:** Project Settings → API → a projekt URL-je és az `anon` / publishable kulcs kerül a
   `launcher.gd` `ACCOUNT_URL` és `ACCOUNT_ANON_KEY` állandóiba. A `service_role` kulcs TITKOS, soha ne kerüljön a launcherbe.
