-- ParthLauncher – támogatási üzenetek (a weboldal űrlapjáról)
-- Futtatás: Supabase → SQL Editor → New query → Run

create table if not exists public.support_uzenet (
	id bigserial primary key,
	email text not null,
	nev text,
	targy text,
	uzenet text not null,
	hova text default 'weboldal',      -- weboldal, launcher, játék
	valaszolva boolean not null default false,
	created_at timestamptz not null default now()
);
create index if not exists support_email_idx on public.support_uzenet (email, created_at desc);

alter table public.support_uzenet enable row level security;
-- Olvasni és írni csak a szerverfüggvény tud (service kulccsal); a látogatóknak nincs hozzáférése.
revoke all on public.support_uzenet from anon, authenticated;
