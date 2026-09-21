-- ParthLauncher – FIÓKNÉV (felhasználónév) a fiókokhoz
-- Futtatás: Supabase → SQL Editor → New query → ezt a fájlt bemásolni → Run
--
-- Miért kell külön tábla?
--   A Supabase fiók e-mail-címmel és jelszóval működik. Ahhoz, hogy a játékos a
--   FIÓKNEVÉVEL is be tudjon lépni, kell egy név → fiók megfeleltetés. Az
--   e-mail-címet SOHA nem adjuk ki: a belépés a `login-nev` függvényen megy át,
--   az keresi ki szerveroldalon a címet, és az adja vissza a munkamenetet.
--
--   A nevek kis-nagybetűtől függetlenül egyediek (citext), hogy a „Bence" és a
--   „bence" ne lehessen két külön fiók.

create extension if not exists citext;

create table if not exists public.profiles (
	user_id uuid primary key references auth.users (id) on delete cascade,
	username citext not null unique,
	created_at timestamptz not null default now(),
	constraint username_hossz check (char_length(username) between 3 and 20),
	-- betű, szám, aláhúzás és kötőjel; ékezetes betű is mehet
	constraint username_alak check (username ~ '^[[:alnum:]_-]+$')
);

create index if not exists profiles_user_idx on public.profiles (user_id);

alter table public.profiles enable row level security;

-- Az asztalt csak a szerverfüggvények írják (service role). A bejelentkezett
-- felhasználó a SAJÁT sorát olvashatja – így látja, mi a fiókneve.
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;

drop policy if exists "sajat fioknev" on public.profiles;
create policy "sajat fioknev" on public.profiles
	for select to authenticated
	using (user_id = auth.uid());

-- ── A fióknév a regisztrációkor érkezik (user_metadata.username) ──────────────
-- A trigger írja be a profiles-ba. Ha a név foglalt, a beszúrás elbukik, és vele
-- a regisztráció is – ezért a weboldal előbb megkérdezi, szabad-e a név.

create or replace function public.profil_letrehoz()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
	if new.raw_user_meta_data ? 'username' then
		insert into public.profiles (user_id, username)
		values (new.id, trim(new.raw_user_meta_data ->> 'username'));
	end if;
	return new;
end;
$$;

drop trigger if exists profil_letrehoz_trigger on auth.users;
create trigger profil_letrehoz_trigger
	after insert on auth.users
	for each row execute function public.profil_letrehoz();

-- ── Szabad-e a fióknév? ──────────────────────────────────────────────────────
-- Bárki hívhatja (a regisztrációs űrlap is), de CSAK igen/nem választ ad:
-- se e-mail-cím, se más adat nem szivárog ki belőle.

create or replace function public.fioknev_szabad(nev text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
	select not exists (select 1 from public.profiles p where p.username = trim(nev)::citext);
$$;

grant execute on function public.fioknev_szabad(text) to anon, authenticated;
