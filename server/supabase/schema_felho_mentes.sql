-- Felhő-mentés: a játékok mentései a FIÓKHOZ kötve (nem a géphez)
-- Futtatás: Supabase → SQL Editor → New query → ezt a fájlt bemásolni → Run
--
-- Minden ParthLauncher-játék ugyanazt a táblát használja (a `jatek` oszlop választja szét őket).
-- A játék a saját mentésmappáját tükrözi ide: egy sor = egy mentésfájl (gzip + base64 az `adat`-ban).
-- Törléskor a sor megmarad `torolt = true` jelzéssel (sírkő), hogy a többi gép is tudja: ott is
-- törölni kell, és ne töltse vissza a régi példányát.
--
-- A játékos CSAK a saját sorait látja és írja (RLS). Szerverfüggvény nem kell hozzá: a játék
-- a fiók tokenjével közvetlenül a REST-felületet hívja (/rest/v1/felho_mentes).

create table if not exists public.felho_mentes (
	user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
	jatek text not null,                           -- 'kard_es_magia', 'heptarchia', 'birodalom', 'antiquitas', 'saecula'
	nev text not null,                             -- a mentésfájl neve a játék mentésmappájában
	ido bigint not null default 0,                 -- a fájl utolsó módosítása (unix mp, a mentő gép órája szerint)
	meret integer not null default 0,              -- a tömörítetlen fájl mérete (bájt)
	torolt boolean not null default false,
	adat text not null default '',                 -- gzip + base64
	frissitve timestamptz not null default now(),
	primary key (user_id, jatek, nev),
	constraint felho_mentes_jatek_hossz check (char_length(jatek) between 1 and 40),
	constraint felho_mentes_nev_hossz check (char_length(nev) between 1 and 160),
	constraint felho_mentes_adat_hossz check (char_length(adat) <= 12000000)   -- ~9 MB tömörítve
);

alter table public.felho_mentes enable row level security;

drop policy if exists "sajat mentesek olvasasa" on public.felho_mentes;
create policy "sajat mentesek olvasasa" on public.felho_mentes
	for select to authenticated using (user_id = auth.uid());

drop policy if exists "sajat mentesek irasa" on public.felho_mentes;
create policy "sajat mentesek irasa" on public.felho_mentes
	for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "sajat mentesek modositasa" on public.felho_mentes;
create policy "sajat mentesek modositasa" on public.felho_mentes
	for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

revoke all on public.felho_mentes from anon, authenticated;
grant select, insert, update on public.felho_mentes to authenticated;

-- ── korlát: fiókonként és játékonként legfeljebb 80 élő mentés és 60 MB (az ingyenes adatbázis védelme) ──
create or replace function public.felho_mentes_korlat() returns trigger
language plpgsql security definer set search_path = public as $$
declare
	db integer;
	ossz bigint;
begin
	new.frissitve := now();
	if new.torolt then
		new.adat := '';
		new.meret := 0;
		return new;
	end if;
	select count(*), coalesce(sum(char_length(adat)), 0) into db, ossz
	from public.felho_mentes
	where user_id = new.user_id and jatek = new.jatek and not torolt and nev <> new.nev;
	if db >= 80 then
		raise exception 'tul_sok_mentes' using errcode = 'P0001';
	end if;
	if ossz + char_length(new.adat) > 60000000 then
		raise exception 'betelt_a_tarhely' using errcode = 'P0001';
	end if;
	return new;
end $$;

drop trigger if exists felho_mentes_korlat on public.felho_mentes;
create trigger felho_mentes_korlat before insert or update on public.felho_mentes
	for each row execute function public.felho_mentes_korlat();

-- A 30 napnál régebbi sírkövek kitakarítása (kézzel vagy ütemezve futtatható):
--   delete from public.felho_mentes where torolt and frissitve < now() - interval '30 days';
