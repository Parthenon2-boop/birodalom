-- Kard és Mágia – érmék és megjelenés-részek (mikrotranzakció)
-- Futtatás: Supabase → SQL Editor → New query → ezt a fájlt bemásolni → Run
--
-- A játékos a Gumroadon érmecsomagot vesz; a gumroad-ping függvény jóváírja az érmét.
-- A boltban érméért vásárol megjelenés-részeket (fej, test, láb, fegyver) – ezek csak külsőségek.
-- Írni csak a szerverfüggvények tudnak; a felhasználó a sajátját olvashatja.

-- ── érme-tranzakciók: minden jóváírás és levonás külön sor (így ellenőrizhető) ──
create table if not exists public.coin_tx (
	id bigserial primary key,
	user_id uuid references auth.users (id) on delete cascade,
	email text,                                    -- ha a vásárláskor még nincs fiók, e-mail alapján kötjük össze
	amount integer not null,                       -- + jóváírás, − levonás
	reason text not null,                          -- 'gumroad', 'vasarlas', 'ajandek'
	sale_id text unique,                           -- Gumroad-vásárlás (egy vásárlás csak egyszer írható jóvá)
	item_key text,                                 -- levonásnál: melyik részt vette meg
	created_at timestamptz not null default now()
);
create index if not exists coin_tx_user_idx on public.coin_tx (user_id);
create index if not exists coin_tx_email_idx on public.coin_tx (lower(email));

-- ── megvásárolt megjelenés-részek ──
create table if not exists public.cosmetics (
	id bigserial primary key,
	user_id uuid not null references auth.users (id) on delete cascade,
	item_key text not null,                        -- pl. 'lovag_fej_sisak_arany'
	created_at timestamptz not null default now(),
	unique (user_id, item_key)
);
create index if not exists cosmetics_user_idx on public.cosmetics (user_id);

-- ── az egyenleg: a saját tranzakciók összege ──
create or replace view public.my_coins as
	select coalesce(sum(amount), 0)::int as coins
	from public.coin_tx
	where user_id = auth.uid()
	   or (user_id is null and lower(email) = lower(auth.jwt() ->> 'email'));

alter table public.coin_tx enable row level security;
alter table public.cosmetics enable row level security;

drop policy if exists "sajat ermek" on public.coin_tx;
create policy "sajat ermek" on public.coin_tx
	for select to authenticated
	using (user_id = auth.uid() or (user_id is null and lower(email) = lower(auth.jwt() ->> 'email')));

drop policy if exists "sajat reszek" on public.cosmetics;
create policy "sajat reszek" on public.cosmetics
	for select to authenticated
	using (user_id = auth.uid());

revoke all on public.coin_tx, public.cosmetics from anon, authenticated;
grant select on public.coin_tx, public.cosmetics to authenticated;
grant select on public.my_coins to authenticated;

-- ── vásárlás egy lépésben: levonás és a rész jóváírása csak együtt sikerül ──
-- A szerverfüggvény (buy-cosmetic) hívja a service kulccsal.
create or replace function public.buy_cosmetic(p_user uuid, p_email text, p_item text, p_price int)
returns table (ok boolean, coins int, hiba text)
language plpgsql security definer as $$
declare
	v_coins int;
begin
	if p_price <= 0 then
		return query select false, 0, 'rossz_ar'; return;
	end if;
	-- a korábbi, e-mail alapján jóváírt érméket a fiókhoz kötjük
	update public.coin_tx set user_id = p_user
	where user_id is null and lower(email) = lower(p_email);

	select coalesce(sum(amount), 0)::int into v_coins from public.coin_tx where user_id = p_user;

	if exists (select 1 from public.cosmetics where user_id = p_user and item_key = p_item) then
		return query select false, v_coins, 'mar_megvan'; return;
	end if;
	if v_coins < p_price then
		return query select false, v_coins, 'keves_erme'; return;
	end if;

	insert into public.cosmetics (user_id, item_key) values (p_user, p_item);
	insert into public.coin_tx (user_id, email, amount, reason, item_key)
		values (p_user, p_email, -p_price, 'vasarlas', p_item);
	return query select true, v_coins - p_price, ''::text;
end;
$$;

-- a PUBLIC-tól is el kell venni: a Postgres alapból mindenkinek ad futtatási jogot, és az anon azt örökli
revoke all on function public.buy_cosmetic(uuid, text, text, int) from public, anon, authenticated;
grant execute on function public.buy_cosmetic(uuid, text, text, int) to service_role;
