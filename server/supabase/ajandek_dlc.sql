-- ParthLauncher – kiegészítők ajándékba egy fióknak (teszteléshez, díjazáshoz, kárpótlásnak)
-- Futtatás: Supabase → SQL Editor → New query → bemásol → Run
-- Az e-mail-címet írd át, és a listából hagyd benne, amit adni szeretnél.
--
-- A launcher a fiók jogosultságait indításkor (és belépéskor) kérdezi le, tehát a futtatás után
-- elég újraindítani az indítót: a kiegészítők megvásároltként jelennek meg és letölthetők.

insert into public.entitlements (email, user_id, dlc_key, source)
select u.email, u.id, d.k, 'ajandek'
from auth.users u
cross join (values ('skandinavia'), ('vikingek'), ('vallas'), ('varegok')) as d(k)
where lower(u.email) = 'parthlauncher@gmail.com'
  and not exists (
    select 1 from public.entitlements e
    where e.user_id = u.id and e.dlc_key = d.k and not e.revoked
  );

-- ellenőrzés: ki mit kapott
select email, dlc_key, source, revoked, created_at
from public.entitlements
order by created_at desc;

-- ── Visszavonás (ha mégsem kell) ──
-- update public.entitlements set revoked = true
-- where source = 'ajandek' and lower(email) = 'parthlauncher@gmail.com';

-- ── Érme ajándékba (Kard és Mágia bolt) ──
-- insert into public.coin_tx (user_id, email, amount, reason)
-- select id, email, 100, 'ajandek' from auth.users where lower(email) = 'parthlauncher@gmail.com';
