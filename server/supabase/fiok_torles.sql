-- ParthLauncher – egy fiók és minden hozzá tartozó adat törlése
--
-- MIRE VALÓ? Ha egy próbafiókot (vagy egy kérésre törlendő fiókot) teljesen ki
-- akarsz venni a rendszerből. A Supabase felületén a felhasználó törlése csak
-- az auth.users sort viszi el; az e-mail-cím alapján összekötött sorok
-- (jogosultságok, érmék, üzenetek) ott maradnának.
--
-- FIGYELEM: EZ VISSZAFORDÍTHATATLAN. Előbb FUTTASD LE AZ 1. LÉPÉST, nézd meg,
-- mit találna, és csak utána a 2.-at. Mentés nincs: ami elmegy, elment.
--
-- Használat: Supabase → SQL Editor → New query → bemásol → az e-mail-címet
-- átírod → Run.

-- ══════════════════════════════════════════════════════════════
-- 1. LÉPÉS – MIT TALÁLNA? (csak olvas, semmit nem töröl)
-- ══════════════════════════════════════════════════════════════

with cel as (select 'parthenon841@gmail.com'::text as email)
select 'auth.users' as tabla, count(*) as sorok from auth.users, cel
	where lower(auth.users.email) = lower(cel.email)
union all
select 'profiles', count(*) from public.profiles p
	join auth.users u on u.id = p.user_id, cel
	where lower(u.email) = lower(cel.email)
union all
select 'entitlements', count(*) from public.entitlements e, cel
	where lower(e.email) = lower(cel.email)
union all
select 'coin_tx', count(*) from public.coin_tx c, cel
	where lower(coalesce(c.email, '')) = lower(cel.email)
union all
select 'support_uzenet', count(*) from public.support_uzenet s, cel
	where lower(s.email) = lower(cel.email);

-- A fiók(ok) részletei, hogy lásd, tényleg azt törlöd, amit akarsz:
select id, email, created_at, last_sign_in_at, email_confirmed_at
from auth.users
where lower(email) = lower('parthenon841@gmail.com');


-- ══════════════════════════════════════════════════════════════
-- 2. LÉPÉS – A TÖRLÉS (csak az 1. lépés átnézése után!)
-- ══════════════════════════════════════════════════════════════
-- Vedd ki a kommentjelet a blokk elől, és futtasd.
--
-- A sorrend számít: előbb az e-mail alapján kötött sorok, utána a fiók.
-- A profiles és a cosmetics maguktól törlődnek (on delete cascade), az
-- entitlements user_id-je null-ra vált (on delete set null) – ezért kell
-- külön is kitörölni őket az e-mail alapján.

/*
begin;

delete from public.entitlements
where lower(email) = lower('parthenon841@gmail.com');

delete from public.coin_tx
where lower(coalesce(email, '')) = lower('parthenon841@gmail.com');

delete from public.support_uzenet
where lower(email) = lower('parthenon841@gmail.com');

delete from auth.users
where lower(email) = lower('parthenon841@gmail.com');

-- Nézd meg a fenti sorok darabszámát. Ha stimmel:   commit;
-- Ha bármi gyanús:                                  rollback;
commit;
*/


-- ══════════════════════════════════════════════════════════════
-- 3. LÉPÉS – ELLENŐRZÉS (a törlés után)
-- ══════════════════════════════════════════════════════════════

-- select count(*) from auth.users where lower(email) = lower('parthenon841@gmail.com');
-- 0-t kell adnia.
