-- Kard és Mágia – napi kihívás ranglistája
-- Futtatás: Supabase → SQL Editor → New query → ezt a fájlt bemásolni → Run
--
-- Aznap mindenki ugyanazt a pályát kapja (a játék a dátumból számolja a magot). A játék a kaland
-- végén beküldi a pontszámot; fiókonként és naponként a LEGJOBB marad meg. A listát bármely
-- belépett játékos lekérheti: fióknév, pontszám, hős, meddig jutott — e-mail-cím soha.
--
-- A táblához közvetlenül senki nem fér hozzá: írni és olvasni csak a két függvényen át lehet.
-- A pontszámot a játék számolja (a kliens mondja be), tehát ez barátságos ranglista, nem
-- csalásbiztos verseny — a függvény csak a nyilvánvaló képtelenségeket szűri ki.

create table if not exists public.kem_napi (
	user_id uuid not null references auth.users (id) on delete cascade,
	nap date not null,
	pont integer not null,
	kaszt text not null default '',
	zona integer not null default 1,
	olesek integer not null default 0,
	gyozelem boolean not null default false,
	frissitve timestamptz not null default now(),
	primary key (user_id, nap)
);
create index if not exists kem_napi_nap_pont_idx on public.kem_napi (nap, pont desc);

alter table public.kem_napi enable row level security;
revoke all on public.kem_napi from anon, authenticated;

-- ── beküldés: a nap legjobbja marad meg ──
create or replace function public.kem_napi_bekuld(p_nap date, p_pont integer, p_kaszt text, p_zona integer,
	p_olesek integer, p_gyozelem boolean)
returns integer language plpgsql security definer set search_path = public as $$
declare
	legjobb integer;
begin
	if auth.uid() is null then
		raise exception 'not_logged_in';
	end if;
	-- csak a mai nap (egy nap tűréssel az időzónák miatt), és csak értelmes számok
	if p_nap < (now() at time zone 'utc')::date - 1 or p_nap > (now() at time zone 'utc')::date + 1 then
		raise exception 'rossz_nap';
	end if;
	if p_pont < 0 or p_pont > 200000 or p_zona < 1 or p_zona > 4 or p_olesek < 0 or p_olesek > 5000 then
		raise exception 'rossz_ertek';
	end if;
	insert into public.kem_napi as k (user_id, nap, pont, kaszt, zona, olesek, gyozelem)
	values (auth.uid(), p_nap, p_pont, left(coalesce(p_kaszt, ''), 20), p_zona, p_olesek, coalesce(p_gyozelem, false))
	on conflict (user_id, nap) do update
		set pont = excluded.pont, kaszt = excluded.kaszt, zona = excluded.zona, olesek = excluded.olesek,
			gyozelem = excluded.gyozelem, frissitve = now()
		where excluded.pont > k.pont
	returning pont into legjobb;
	if legjobb is null then
		select pont into legjobb from public.kem_napi where user_id = auth.uid() and nap = p_nap;
	end if;
	return legjobb;
end $$;

-- ── a nap ranglistája: a legjobb 20 (fióknévvel; akinek nincs neve, "névtelen") ──
create or replace function public.kem_napi_lista(p_nap date)
returns table (nev text, pont integer, kaszt text, zona integer, gyozelem boolean, en boolean)
language sql security definer set search_path = public stable as $$
	select coalesce(nullif(p.username, ''), 'névtelen') as nev, k.pont, k.kaszt, k.zona, k.gyozelem,
		(k.user_id = auth.uid()) as en
	from public.kem_napi k
	left join public.profiles p on p.user_id = k.user_id
	where k.nap = p_nap and auth.uid() is not null
	order by k.pont desc, k.frissitve asc
	limit 20;
$$;

revoke all on function public.kem_napi_bekuld(date, integer, text, integer, integer, boolean) from public, anon;
revoke all on function public.kem_napi_lista(date) from public, anon;
grant execute on function public.kem_napi_bekuld(date, integer, text, integer, integer, boolean) to authenticated;
grant execute on function public.kem_napi_lista(date) to authenticated;

-- Régi napok takarítása (kézzel, ha kell):
--   delete from public.kem_napi where nap < current_date - 60;