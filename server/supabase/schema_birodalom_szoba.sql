-- BIRODALOM – többjátékos szoba SZOBAKÓDDAL (WebRTC): a jelzőcsatornák szabályai
--
-- Mire való? A Birodalom szobakódos útja (scripts/globals/NetSzoba.gd) a kapcsolat felépítéséhez
-- szükséges jelzést (SDP, ICE) a Realtime „bir-<szobakód>” üzenetcsatornáján cseréli ki. A projekt
-- CSAK PRIVÁT csatornát enged (Realtime → Settings → „Allow public access” ki van kapcsolva, lásd
-- schema_heptarchia_web.sql), privát csatornára pedig csak az léphet be, akit egy szabály beenged.
-- A meglévő szabályok csak a Heptarchia „hep-” csatornáira szólnak — AMÍG EZ A FÁJL NINCS
-- LEFUTTATVA, a Birodalom szobakódos útja mindenkit elutasít („Unauthorized: You do not have
-- permissions to read from this Channel topic”).
--
-- Futtatás: Supabase → SQL Editor → beilleszteni → Run. Többször is lefuttatható.
--
-- A csatornán csak a kapcsolat felépítése megy át (néhány rövid üzenet szobánként); a játék
-- forgalma utána közvetlenül a gépek között megy, a Supabase-en nem.

-- ── A) AJÁNLOTT: csak BEJELENTKEZETT fiók (a ParthLauncherből, belépve indított játék) ──
-- Így a csatornákat nem lehet névtelenül, csak a nyilvános kulccsal használni (se szobát keresni,
-- se a kiszolgálót terhelni).
drop policy if exists "birodalom_szoba_olvas" on realtime.messages;
create policy "birodalom_szoba_olvas" on realtime.messages for select to authenticated
	using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) like 'bir-%');
drop policy if exists "birodalom_szoba_ir" on realtime.messages;
create policy "birodalom_szoba_ir" on realtime.messages for insert to authenticated
	with check (realtime.messages.extension = 'broadcast' and (select realtime.topic()) like 'bir-%');

-- ── B) VÁLASZTHATÓ: fiók NÉLKÜL is (a játék a launcher nélkül, kilépve indítva is tud szobát nyitni) ──
-- Kényelmesebb, de ekkor BÁRKI, aki ismeri a projekt nyilvános kulcsát (az a játékban és a honlapon
-- is ott van), beléphet bármelyik „bir-” csatornára: végigpróbálhatja a kódokat, és a Realtime
-- üzenetkeretét is fogyaszthatja. Csak akkor kapcsold be, ha ezt vállalod — ehhez vedd ki a
-- megjegyzésjeleket az alábbi négy sor elől:
-- drop policy if exists "birodalom_szoba_olvas_anon" on realtime.messages;
-- create policy "birodalom_szoba_olvas_anon" on realtime.messages for select to anon
-- 	using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) like 'bir-%');
-- drop policy if exists "birodalom_szoba_ir_anon" on realtime.messages;
-- create policy "birodalom_szoba_ir_anon" on realtime.messages for insert to anon
-- 	with check (realtime.messages.extension = 'broadcast' and (select realtime.topic()) like 'bir-%');

-- Visszavonás (a szobakódos út kikapcsolása a kiszolgálón):
-- drop policy if exists "birodalom_szoba_olvas" on realtime.messages;
-- drop policy if exists "birodalom_szoba_ir" on realtime.messages;
-- drop policy if exists "birodalom_szoba_olvas_anon" on realtime.messages;
-- drop policy if exists "birodalom_szoba_ir_anon" on realtime.messages;
