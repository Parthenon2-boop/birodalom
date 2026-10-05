-- Heptarchia a böngészőben – ONLINE (többjátékos) játék csak meghívott fiókoknak
-- Futtatás: Supabase → SQL Editor → New query → ezt a fájlt bemásolni → Run
-- (Többször is lefuttatható; a schema_heptarchia_web.sql UTÁN kell futtatni – annak a két szobaszabályát cseréli le.)
--
-- Mit csinál?
--   heptarchia_online_engedely        – a meghívott fióknevek listája (kisbetűsen, Unicode NFC-alakban tárolva,
--                                       így az „OlivérVető” is egyezik, akárhogy írták be az ékezetet).
--   heptarchia_online_engedelyes()    – igaz, ha a BELÉPETT fiók fiókneve a listán van (a játék ezzel kérdezi meg,
--                                       mutassa-e a többjátékos gombot; a szobaszabályok is ezt használják).
--   realtime.messages szabályai       – a „hep-<szobakód>” csatornákra (a többjátékos szobák jelzései) csak az a
--                                       bejelentkezett fiók léphet be / írhat, aki a listán van. Ez a SZERVERES
--                                       védelem: a játék módosításával sem lehet megkerülni.
-- Az egyjátékos mód minden bejelentkezett fióknak megmarad. (Az asztali, letölthető változat helyi hálózati
-- játékát – ENet, fiók nélkül – ez nem érinti.)
--
-- Kezelés: az admin oldalon (admin.html → „Online játék” fül), vagy SQL-ből:
--   insert into public.heptarchia_online_engedely (username) values (lower(normalize('Fióknév', NFC))) on conflict do nothing;
--   delete from public.heptarchia_online_engedely where username = lower(normalize('Fióknév', NFC));
--   select * from public.heptarchia_online_engedely order by username;

-- ── a lista ──
create table if not exists public.heptarchia_online_engedely (
	username text primary key,
	megjegyzes text null,
	created_at timestamptz not null default now(),
	-- csak egységes alakban (kisbetű, NFC): így az egyezés a kis-nagybetűtől és az ékezet kódolásától független
	constraint heptarchia_online_engedely_alak check (username = lower(normalize(username, NFC)) and char_length(username) between 1 and 40)
);
alter table public.heptarchia_online_engedely enable row level security;
revoke all on public.heptarchia_online_engedely from public, anon, authenticated;
grant all on public.heptarchia_online_engedely to service_role;
-- a belépett fiók csak a SAJÁT sorát láthatja (a többi meghívott nevét nem)
grant select on public.heptarchia_online_engedely to authenticated;
drop policy if exists "heptarchia_online_sajat" on public.heptarchia_online_engedely;
create policy "heptarchia_online_sajat" on public.heptarchia_online_engedely for select to authenticated
	using (username = (select lower(normalize(p.username::text, NFC)) from public.profiles p where p.user_id = auth.uid()));

-- a három meghívott fiók
insert into public.heptarchia_online_engedely (username, megjegyzes) values
	(lower(normalize('tojasosnokedli', NFC)), 'első meghívottak'),
	(lower(normalize('OlivérVető', NFC)), 'első meghívottak'),
	(lower(normalize('parthenon2', NFC)), 'első meghívottak')
on conflict (username) do nothing;

-- ── a belépett fiók meghívott-e ──
-- security definer: a profiles és a lista olvasása a hívó jogaitól függetlenül; csak igen/nem választ ad.
create or replace function public.heptarchia_online_engedelyes()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
	select exists (
		select 1 from public.profiles p
		join public.heptarchia_online_engedely e on e.username = lower(normalize(p.username::text, NFC))
		where p.user_id = auth.uid()
	);
$$;
revoke all on function public.heptarchia_online_engedelyes() from public, anon;
grant execute on function public.heptarchia_online_engedelyes() to authenticated, service_role;

-- ── a többjátékos szobák (Realtime Broadcast, privát „hep-<szobakód>” csatornák): csak a meghívottak ──
-- (A Realtime a csatlakozáskor a belépett fiók nevében értékeli ki; a csatornán belül a jog a kapcsolat végéig érvényes.)
drop policy if exists "heptarchia_szoba_olvas" on realtime.messages;
create policy "heptarchia_szoba_olvas" on realtime.messages for select to authenticated
	using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) like 'hep-%'
		and (select public.heptarchia_online_engedelyes()));
drop policy if exists "heptarchia_szoba_ir" on realtime.messages;
create policy "heptarchia_szoba_ir" on realtime.messages for insert to authenticated
	with check (realtime.messages.extension = 'broadcast' and (select realtime.topic()) like 'hep-%'
		and (select public.heptarchia_online_engedelyes()));

-- ── admin: lista, hozzáadás, törlés (CSAK a szerveroldali kulcs – az `admin` szerverfüggvény – hívhatja) ──
create or replace function public.admin_heptarchia_online(p_admin uuid, p_admin_name text, p_username text,
	p_add boolean, p_note text)
returns table (ok boolean, valtozott boolean, hiba text)
language plpgsql
security definer
set search_path = public
as $$
declare
	v_nev text := lower(normalize(trim(coalesce(p_username, '')), NFC));
	v_n int;
begin
	if char_length(v_nev) < 1 or char_length(v_nev) > 40 then
		return query select false, false, 'rossz_nev'::text; return;
	end if;
	if p_add then
		insert into public.heptarchia_online_engedely (username, megjegyzes) values (v_nev, nullif(trim(coalesce(p_note, '')), ''))
		on conflict (username) do nothing;
	else
		delete from public.heptarchia_online_engedely where username = v_nev;
	end if;
	get diagnostics v_n = row_count;
	if v_n = 0 then
		return query select true, false, (case when p_add then 'mar_megvan' else 'nincs_meg' end)::text; return;
	end if;
	insert into public.admin_log (admin_id, admin_name, action, target_id, target_name, details)
	values (p_admin, p_admin_name, case when p_add then 'online_ad' else 'online_elvesz' end, null, v_nev,
		jsonb_build_object('megjegyzes', coalesce(p_note, '')));
	return query select true, true, ''::text;
end;
$$;
revoke all on function public.admin_heptarchia_online(uuid, text, text, boolean, text) from public, anon, authenticated;
grant execute on function public.admin_heptarchia_online(uuid, text, text, boolean, text) to service_role;

-- Ellenőrzés:
--   select e.username, e.megjegyzes, e.created_at, p.user_id is not null as van_ilyen_fiok
--   from public.heptarchia_online_engedely e
--   left join public.profiles p on lower(normalize(p.username::text, NFC)) = e.username order by e.username;
