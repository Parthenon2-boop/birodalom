-- ParthLauncher – ADMIN felület (docs/admin.html + az `admin` szerverfüggvény)
-- Futtatás: Supabase → SQL Editor → New query → ezt a fájlt bemásolni → Run
-- (Többször is lefuttatható: minden „if not exists” / „create or replace”.)
--
-- Mit hoz létre?
--   admins          – kik az adminok (fiók-azonosító). CSAK itt lehet valakit adminná tenni, SQL-ből.
--   admin_log       – napló: minden admin-művelet (ki, mit, kinek, mikor, miért).
--   admin_accounts  – fióklista kereséssel, lapozással (fióknév, regisztráció, utolsó belépés, DLC-k, érme).
--   admin_dlc       – kiegészítő adása / visszavonása + naplózás egy lépésben.
--   admin_coins     – érme jóváírása / levonása + naplózás egy lépésben.
-- A függvényeket CSAK a szerveroldali kulcs (service_role) hívhatja – a böngésző (anon) és a belépett
-- felhasználó (authenticated) nem. Az `admin` Edge Function előbb ellenőrzi, hogy a hívó benne van-e az
-- admins táblában, és csak utána hívja ezeket.
--
-- ══ A SAJÁT FIÓKOD ADMINNÁ TÉTELE (a fájl lefuttatása után, külön) ══
--   insert into public.admins (user_id)
--   select user_id from public.profiles where username = 'IDE_A_FIOKNEVED'
--   on conflict do nothing;
-- vagy e-mail-cím alapján:
--   insert into public.admins (user_id)
--   select id from auth.users where lower(email) = lower('parthlauncher@gmail.com')
--   on conflict do nothing;
-- Admin elvétele:  delete from public.admins where user_id = '<uuid>';
-- Ellenőrzés:      select a.user_id, p.username, a.created_at from public.admins a
--                  left join public.profiles p using (user_id);

-- ── adminok ──
create table if not exists public.admins (
	user_id uuid primary key references auth.users (id) on delete cascade,
	created_at timestamptz not null default now()
);
alter table public.admins enable row level security;
revoke all on public.admins from anon, authenticated;
-- (nincs szabály → a Data API-n át senki sem látja, csak a szerverfüggvény)

-- ── napló ──
create table if not exists public.admin_log (
	id bigserial primary key,
	admin_id uuid references auth.users (id) on delete set null,
	admin_name text,
	action text not null,                  -- 'dlc_ad', 'dlc_elvesz', 'erme'
	target_id uuid references auth.users (id) on delete set null,
	target_name text,
	details jsonb not null default '{}'::jsonb,
	created_at timestamptz not null default now()
);
create index if not exists admin_log_created_idx on public.admin_log (created_at desc);
create index if not exists admin_log_target_idx on public.admin_log (target_id);
alter table public.admin_log enable row level security;
revoke all on public.admin_log from anon, authenticated;

-- ── fióklista ──
-- p_search: fióknév vagy e-mail részlete (üres = mind). Rendezés: legújabb fiók elöl.
-- total: a szűrésnek megfelelő fiókok száma (a lapozáshoz).
create or replace function public.admin_accounts(p_search text, p_limit int, p_offset int)
returns table (
	user_id uuid, username text, email text, created_at timestamptz, last_sign_in_at timestamptz,
	confirmed boolean, coins int, dlcs text[], total bigint
)
language sql
security definer
set search_path = public
stable
as $$
	with u as (
		select au.id, au.email, au.created_at, au.last_sign_in_at, au.email_confirmed_at, p.username::text as username
		from auth.users au
		left join public.profiles p on p.user_id = au.id
		where coalesce(p_search, '') = ''
		   or p.username::text ilike '%' || p_search || '%'
		   or au.email ilike '%' || p_search || '%'
	)
	select
		u.id, u.username, u.email::text, u.created_at, u.last_sign_in_at, u.email_confirmed_at is not null,
		(select coalesce(sum(c.amount), 0)::int from public.coin_tx c
			where c.user_id = u.id or (c.user_id is null and lower(c.email) = lower(u.email))),
		(select coalesce(array_agg(distinct e.dlc_key order by e.dlc_key), '{}') from public.entitlements e
			where not e.revoked and (e.user_id = u.id or (e.user_id is null and lower(e.email) = lower(u.email)))),
		count(*) over ()
	from u
	order by u.created_at desc
	limit greatest(1, least(coalesce(p_limit, 50), 200))
	offset greatest(0, coalesce(p_offset, 0));
$$;

-- ── kiegészítő adása / visszavonása ──
-- p_grant = true: ad (ha már megvan, nem csinál semmit), false: minden aktív sorát visszavonja.
-- Visszaad: ok, valtozott (történt-e bármi), hiba.
create or replace function public.admin_dlc(p_admin uuid, p_admin_name text, p_target uuid, p_dlc text,
	p_grant boolean, p_note text)
returns table (ok boolean, valtozott boolean, hiba text)
language plpgsql
security definer
set search_path = public
as $$
declare
	v_email text;
	v_name text;
	v_n int;
begin
	select au.email, p.username::text into v_email, v_name
	from auth.users au left join public.profiles p on p.user_id = au.id
	where au.id = p_target;
	if v_email is null then
		return query select false, false, 'nincs_fiok'::text; return;
	end if;

	if p_grant then
		if exists (select 1 from public.entitlements e where not e.revoked and e.dlc_key = p_dlc
			and (e.user_id = p_target or (e.user_id is null and lower(e.email) = lower(v_email)))) then
			return query select true, false, 'mar_megvan'::text; return;
		end if;
		insert into public.entitlements (email, user_id, dlc_key, source)
		values (lower(v_email), p_target, p_dlc, 'admin');
		v_n := 1;
	else
		update public.entitlements e set revoked = true
		where not e.revoked and e.dlc_key = p_dlc
		  and (e.user_id = p_target or (e.user_id is null and lower(e.email) = lower(v_email)));
		get diagnostics v_n = row_count;
		if v_n = 0 then
			return query select true, false, 'nincs_meg'::text; return;
		end if;
	end if;

	insert into public.admin_log (admin_id, admin_name, action, target_id, target_name, details)
	values (p_admin, p_admin_name, case when p_grant then 'dlc_ad' else 'dlc_elvesz' end, p_target,
		coalesce(v_name, v_email), jsonb_build_object('dlc', p_dlc, 'sorok', v_n, 'megjegyzes', coalesce(p_note, '')));
	return query select true, true, ''::text;
end;
$$;

-- ── érme jóváírása (+) / levonása (−) ──
-- Az egyenleg nem mehet 0 alá. A fiókhoz még nem kötött (e-mail alapján jóváírt) érméket előbb a fiókhoz köti,
-- ugyanúgy, ahogy a buy_cosmetic is. Visszaad: ok, az új egyenleg, hiba.
create or replace function public.admin_coins(p_admin uuid, p_admin_name text, p_target uuid, p_amount int,
	p_note text)
returns table (ok boolean, coins int, hiba text)
language plpgsql
security definer
set search_path = public
as $$
declare
	v_email text;
	v_name text;
	v_coins int;
begin
	if p_amount = 0 or abs(p_amount) > 1000000 then
		return query select false, 0, 'rossz_osszeg'::text; return;
	end if;
	-- egyszerre csak egy módosítás ugyanazon a fiókon (két gyors kattintás se vigye 0 alá)
	perform pg_advisory_xact_lock(hashtext('admin_coins:' || p_target::text));

	select au.email, p.username::text into v_email, v_name
	from auth.users au left join public.profiles p on p.user_id = au.id
	where au.id = p_target;
	if v_email is null then
		return query select false, 0, 'nincs_fiok'::text; return;
	end if;

	update public.coin_tx set user_id = p_target
	where user_id is null and lower(email) = lower(v_email);
	select coalesce(sum(amount), 0)::int into v_coins from public.coin_tx where user_id = p_target;

	if v_coins + p_amount < 0 then
		return query select false, v_coins, 'keves_erme'::text; return;
	end if;

	insert into public.coin_tx (user_id, email, amount, reason)
	values (p_target, lower(v_email), p_amount, 'admin');

	insert into public.admin_log (admin_id, admin_name, action, target_id, target_name, details)
	values (p_admin, p_admin_name, 'erme', p_target, coalesce(v_name, v_email),
		jsonb_build_object('osszeg', p_amount, 'elotte', v_coins, 'utana', v_coins + p_amount,
			'megjegyzes', coalesce(p_note, '')));
	return query select true, v_coins + p_amount, ''::text;
end;
$$;

-- A függvényeket csak a szerveroldali kulcs hívhatja. FONTOS: a PUBLIC-tól is el kell venni a jogot –
-- a Postgres alapból mindenkinek (PUBLIC) ad futtatási jogot, és az anon szerep azt örökli.
revoke all on function public.admin_accounts(text, int, int) from public, anon, authenticated;
revoke all on function public.admin_dlc(uuid, text, uuid, text, boolean, text) from public, anon, authenticated;
revoke all on function public.admin_coins(uuid, text, uuid, int, text) from public, anon, authenticated;
grant execute on function public.admin_accounts(text, int, int) to service_role;
grant execute on function public.admin_dlc(uuid, text, uuid, text, boolean, text) to service_role;
grant execute on function public.admin_coins(uuid, text, uuid, int, text) to service_role;

-- ── JAVÍTÁS: buy_cosmetic ──
-- A schema_erme.sql csak az anon/authenticated szereptől vette el a jogot, a PUBLIC-tól nem, így a böngészőből
-- (a nyilvános kulccsal) bárki meghívhatta a /rest/v1/rpc/buy_cosmetic-et tetszőleges fiókra és árra
-- (pl. 1 érmés árral). Ezt zárja le:
revoke all on function public.buy_cosmetic(uuid, text, text, int) from public, anon, authenticated;
grant execute on function public.buy_cosmetic(uuid, text, text, int) to service_role;
