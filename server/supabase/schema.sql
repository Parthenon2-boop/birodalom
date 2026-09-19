-- ParthLauncher – fiókhoz kötött kiegészítők (DLC)
-- Futtatás: Supabase → SQL Editor → New query → ezt a fájlt bemásolni → Run
--
-- entitlements: ki mit vett meg. Két úton kerül bele sor:
--   1. a Gumroad minden vásárláskor értesíti a gumroad-ping függvényt (a vevő e-mail-címével);
--   2. a launcher „Van kulcsom” gombja a claim-license függvénnyel köti a kulcsot a bejelentkezett fiókhoz.
-- Írni csak a szerverfüggvények tudnak (service role); a felhasználó csak a saját sorait olvashatja.

create table if not exists public.entitlements (
	id bigserial primary key,
	email text not null,                                           -- a vevő (vagy a beváltó) e-mail-címe
	user_id uuid references auth.users (id) on delete set null,   -- a fiók, amelyhez a kulcsot beváltották
	dlc_key text not null,                                         -- skandinavia, vikingek, vallas, varegok …
	license_key text unique,                                       -- egy kulcs csak egy sorban (egy fiókban) lehet
	sale_id text unique,
	source text not null default 'gumroad',
	revoked boolean not null default false,                        -- visszatérített vásárlás
	created_at timestamptz not null default now()
);

create index if not exists entitlements_email_idx on public.entitlements (lower(email));
create index if not exists entitlements_user_idx on public.entitlements (user_id);

alter table public.entitlements enable row level security;

-- a Data API-n át csak olvasni lehet (a sorokat a szabály szűri); írni csak a szerverfüggvények írnak
revoke all on public.entitlements from anon, authenticated;
grant select on public.entitlements to authenticated;

-- A bejelentkezett felhasználó a saját fiókjához kötött sorokat látja, és azokat a még senkihez nem kötött
-- vásárlásokat, amelyeket az ő (megerősített) e-mail-címével vettek.
drop policy if exists "sajat jogosultsagok" on public.entitlements;
create policy "sajat jogosultsagok" on public.entitlements
	for select to authenticated
	using (
		not revoked and (
			user_id = auth.uid()
			or (user_id is null and lower(email) = lower(auth.jwt() ->> 'email'))
		)
	);
