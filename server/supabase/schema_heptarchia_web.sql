-- Heptarchia a böngészőben – csak bejelentkezett (regisztrált) fiókkal
-- Futtatás: Supabase → SQL Editor → New query → ezt a fájlt bemásolni → Run
-- (Többször is lefuttatható.)
--
-- 1) A PRIVÁT „heptarchia-web” tároló: itt van a játékcsomag (<verzió>/index.pck) és az aktuális verzió (aktualis.json).
--    Nyilvános olvasás nincs; letöltési linket csak a heptarchia-web szerverfüggvény ad, bejelentkezett fióknak.
--    (Az ingyenes csomagban egy fájl legfeljebb 50 MB lehet – a csomag most kb. 40 MB.)
insert into storage.buckets (id, name, public, file_size_limit)
values ('heptarchia-web', 'heptarchia-web', false, 52428800)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit;

-- 2) Napló: ki, mikor, honnan kért játékcsomagot (a függvény ebből számolja az óránkénti korlátot is)
create table if not exists public.heptarchia_web_log (
	id bigserial primary key,
	user_id uuid not null references auth.users (id) on delete cascade,
	ido timestamptz not null default now(),
	oldal text null,
	verzio text null
);
create index if not exists heptarchia_web_log_user_idx on public.heptarchia_web_log (user_id, ido desc);
alter table public.heptarchia_web_log enable row level security;
-- (nincs szabály → a Data API-n át senki sem látja, csak a szerverfüggvény a szerveroldali kulccsal)
revoke all on public.heptarchia_web_log from public, anon, authenticated;
revoke all on sequence public.heptarchia_web_log_id_seq from public, anon, authenticated;
grant all on public.heptarchia_web_log to service_role;
grant usage, select on sequence public.heptarchia_web_log_id_seq to service_role;

-- 3) A többjátékos szobák jelzőcsatornái (Realtime Broadcast, PRIVÁT csatorna „hep-<szobakód>”):
--    csak bejelentkezett fiók olvashatja és írhatja – névtelenül (csak az anon kulccsal) nem lehet belépni.
drop policy if exists "heptarchia_szoba_olvas" on realtime.messages;
create policy "heptarchia_szoba_olvas" on realtime.messages for select to authenticated
	using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) like 'hep-%');
drop policy if exists "heptarchia_szoba_ir" on realtime.messages;
create policy "heptarchia_szoba_ir" on realtime.messages for insert to authenticated
	with check (realtime.messages.extension = 'broadcast' and (select realtime.topic()) like 'hep-%');

-- Utána (egyszer, a felületen): Realtime → Settings → „Allow public access” KIKAPCSOLNI, hogy csak privát
-- csatorna legyen. (A honlap és a launcher mást nem használ a Realtime-ból.)

-- Ellenőrzés (az utolsó 20 kiadás):
-- select l.ido, p.username, l.oldal, l.verzio from public.heptarchia_web_log l
--   left join public.profiles p using (user_id) order by l.ido desc limit 20;
