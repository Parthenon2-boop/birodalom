// Tétlenség utáni kiléptetés: ha a belépett látogató 45 percig semmit nem csinál a honlapon (nem kattint,
// nem gépel, nem görget, nem mozgatja az egeret), kiléptetjük. Az utolsó tevékenység idejét a localStorage
// tárolja, így minden oldal és minden nyitott fül közösen számol.
(() => {
	const MUNKAMENET = "sb-gxvepswtairfqvosdcpb-auth-token";   // a supabase-js itt tartja a belépést
	const AKTIV = "parth_utolso_aktiv";
	const TETLEN = 45 * 60 * 1000;
	const olvas = k => { try { return localStorage.getItem(k); } catch (e) { return null; } };
	const ir = (k, v) => { try { localStorage.setItem(k, v); } catch (e) {} };
	const torol = k => { try { localStorage.removeItem(k); } catch (e) {} };
	const belepve = () => !!olvas(MUNKAMENET);

	function ellenoriz() {
		// kijelentkezve nincs mit számolni; a régi időpontot töröljük, hogy a következő belépést ne dobja ki rögtön
		if (!belepve()) { torol(AKTIV); return; }
		const utolso = Number(olvas(AKTIV) || 0);
		if (!utolso) { ir(AKTIV, String(Date.now())); return; }   // most lépett be
		if (Date.now() - utolso > TETLEN) {
			torol(MUNKAMENET);
			torol(AKTIV);
			location.reload();
		}
	}

	let jelzett = 0;
	function aktiv() {
		const t = Date.now();
		if (t - jelzett < 15000) return;   // 15 másodpercenként elég egyszer felírni
		jelzett = t;
		if (belepve()) ir(AKTIV, String(t));
	}

	// számláló a fejlécben (a név mellett): mennyi idő van még a kiléptetésig; az utolsó 5 percben piros
	let szamlalo = null;
	function szamlaloKell() {
		if (szamlalo && document.contains(szamlalo)) return szamlalo;
		const hely = document.getElementById("who") || document.querySelector('header a[href="fiok.html"]');
		if (!hely) return null;
		szamlalo = document.createElement("span");
		szamlalo.className = "kilep-szamlalo";
		szamlalo.style.cssText = "font: 15px 'EB Garamond', Georgia, serif; color: #b7a37f; white-space: nowrap; margin-right: 10px; font-variant-numeric: tabular-nums;";
		szamlalo.title = "Ennyi idő múlva léptet ki a honlap, ha nem csinálsz semmit.";
		hely.parentNode.insertBefore(szamlalo, hely);
		return szamlalo;
	}
	function frissit() {
		const el = szamlaloKell();
		if (!el) return;
		const utolso = Number(olvas(AKTIV) || 0);
		const lathato = belepve() && !!utolso && !(document.getElementById("who") || {}).hidden;
		el.hidden = !lathato;
		el.style.display = lathato ? "" : "none";
		if (!lathato) return;
		const marad = Math.max(0, TETLEN - (Date.now() - utolso));
		const p = Math.floor(marad / 60000), mp = Math.floor(marad / 1000) % 60;
		el.textContent = "⏳ " + p + ":" + String(mp).padStart(2, "0");
		el.style.color = marad < 5 * 60000 ? "#f08a74" : "#b7a37f";
		if (marad === 0) ellenoriz();
	}

	ellenoriz();
	["click", "keydown", "scroll", "mousemove", "touchstart"].forEach(e => addEventListener(e, aktiv, { passive: true }));
	setInterval(ellenoriz, 30000);
	setInterval(frissit, 1000);
	frissit();
	document.addEventListener("visibilitychange", () => { if (!document.hidden) ellenoriz(); });
})();
