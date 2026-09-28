-- ParthLauncher – JÁTÉKIDŐ és JELENLÉT (ki játszik most, ki mennyit játszott)
-- Futtatás: Supabase → SQL Editor → New query → ezt a fájlt bemásolni → Run
-- (Többször is lefuttatható: minden „if not exists” / „create or replace”.)
--
-- Hogyan működik?
--   A launcher a játék indításakor a `jelenlet` szerverfüggvénnyel nyit egy munkamenetet (a fiók tokenjével),
--   és kap egy véletlen kulcsot. A launcher ezután bezárul, de egy kis rejtett figyelő (Windows: PowerShell,
--   macOS: /bin/sh) 2 percenként jelez („beat”), amíg a játék fut, a végén pedig lezárja („stop”).
--   Játékidő = last_seen − started_at munkamenetenként. Alvó / hibernált gépnél (15 percnél nagyobb szünet)
--   a régi munkamenet a legutolsó jelzésnél lezárul, és újat nyitunk – így az alvás nem számít játékidőnek.
--   Online: van nyitott munkamenete, és 4 percen belül jelzett.
--
--   jatek_munkamenet   – a munkamenetek (csak a szerverfüggvények látják: RLS be, szabály nincs)
--   admin_jatekido     – az admin felülethez: fiókonként és játékonként az összes idő, utolsó jelzés, online-e
-- A kulcsot NEM tároljuk, csak az SHA-256 lenyomatát (key_hash).

create table if not exists public.jatek_munkamenet (
	id bigserial primary key,
	user_id uuid not null references auth.users (id) on delete cascade,
	game text not null,
	started_at timestamptz not null default now(),
	last_seen timestamptz not null default now(),
	ended_at timestamptz null,
	key_hash text not null,
	machine text null
);
create index if not exists jatek_munkamenet_user_idx on public.jatek_munkamenet (user_id);
create index if not exists jatek_munkamenet_last_seen_idx on public.jatek_munkamenet (last_seen desc);
create index if not exists jatek_munkamenet_key_idx on public.jatek_munkamenet (key_hash, id desc);

alter table public.jatek_munkamenet enable row level security;
-- (nincs szabály → a Data API-n át senki sem látja, csak a szerverfüggvények a service_role kulccsal)
revoke all on public.jatek_munkamenet from public, anon, authenticated;
revoke all on sequence public.jatek_munkamenet_id_seq from public, anon, authenticated;
grant all on public.jatek_munkamenet to service_role;
grant usage, select on sequence public.jatek_munkamenet_id_seq to service_role;

-- ── összesítő az admin felülethez ──
-- p_users: ezeknek a fiókoknak (null = mindenkinek). Soronként egy fiók + egy játék:
--   seconds    – az összes játékidő másodpercben
--   last_seen  – a legutolsó jelzés
--   online     – most is fut (nyitott munkamenet, 4 percen belüli jelzéssel)
create or replace function public.admin_jatekido(p_users uuid[])
returns table (user_id uuid, game text, seconds bigint, last_seen timestamptz, online boolean)
language sql
security definer
set search_path = public
stable
as $$
	select
		m.user_id,
		m.game,
		coalesce(sum(greatest(0, extract(epoch from
			(least(m.last_seen, coalesce(m.ended_at, m.last_seen)) - m.started_at)))), 0)::bigint,
		max(m.last_seen),
		bool_or(m.ended_at is null and m.last_seen > now() - interval '4 minutes')
	from public.jatek_munkamenet m
	where p_users is null or m.user_id = any (p_users)
	group by m.user_id, m.game;
$$;

-- CSAK a szerveroldali kulcs hívhatja. FONTOS: a PUBLIC-tól is el kell venni a jogot (lásd schema_admin.sql).
revoke all on function public.admin_jatekido(uuid[]) from public, anon, authenticated;
grant execute on function public.admin_jatekido(uuid[]) to service_role;
