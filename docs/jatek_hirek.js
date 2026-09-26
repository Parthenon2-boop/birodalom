// Egy játék saját hírei a játékoldalakon (heptarchia.html, birodalom.html, kard-es-magia.html).
// Forrás: hirek.json (ugyanaz, amit a főoldal #hirek része mutat).
// Használat: jatekHirek(dobozElem, "heptarchia" | "birodalom" | "kard", "hu" | "en" | "de")
// Nyelvváltáskor elég újra meghívni: a hirek.json csak egyszer töltődik le.
(() => {
	const JATEKOK = {
		heptarchia: /heptarchia|vikingek kora|viking age|zeitalter der wikinger|varégok útja|varangian road|warägerweg/i,
		birodalom: /birodalom/i,
		kard: /kard\s+és\s+mágia|sword\s+and\s+(sorcery|magic)|schwert\s+und\s+magie/i,
	};
	const SZOVEG = {
		hu: { none: "Ehhez a játékhoz még nincs friss hír.", all: "Minden hír a főoldalon →", err: "A híreket most nem sikerült betölteni.", tag: "Hír" },
		en: { none: "No news for this game yet.", all: "All news on the main page →", err: "The news could not be loaded right now.", tag: "News" },
		de: { none: "Zu diesem Spiel gibt es noch keine Neuigkeiten.", all: "Alle Neuigkeiten auf der Startseite →", err: "Die Neuigkeiten konnten gerade nicht geladen werden.", tag: "Neuigkeit" },
	};
	const LOCALE = { hu: "hu-HU", en: "en-GB", de: "de-DE" };
	const MAX = 5;
	let adat = null;

	const esc = s => String(s == null ? "" : s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
	const nyelvi = (h, mezo, lang) => (lang !== "hu" && h[mezo + "_" + lang]) || h[mezo] || "";
	const datum = (d, lang) => {
		const x = new Date(d + "T12:00:00");
		return isNaN(x) ? d : x.toLocaleDateString(LOCALE[lang] || "hu-HU", { year: "numeric", month: "long", day: "numeric" });
	};

	// Az esti összesítők („A nap frissítései: …”) több játékot írnak le egy szövegben,
	// „▸ ” kezdetű címsorokkal elválasztva. Visszaadja a szakaszokat: [{cim, szoveg}].
	function szakaszok(szoveg) {
		const sorok = String(szoveg || "").split(/\r?\n/);
		if (!sorok.some(s => s.startsWith("▸ "))) return null;
		const ki = [];
		let akt = null;
		for (const s of sorok) {
			if (s.startsWith("▸ ")) { akt = { cim: s.slice(2).trim(), sorok: [] }; ki.push(akt); }
			else if (akt) akt.sorok.push(s);
		}
		return ki.map(a => ({ cim: a.cim, szoveg: a.sorok.join("\n").trim() }));
	}

	// Melyik játékról szól egy címsor: ha egy játék nevével kezdődik, az; különben
	// amelyiknek a neve bárhol szerepel benne.
	function jatekaCimsor(cim, kulcs) {
		const kezdo = Object.keys(JATEKOK).find(k => new RegExp("^(?:" + JATEKOK[k].source + ")", "i").test(cim));
		if (kezdo) return kezdo === kulcs;
		return JATEKOK[kulcs].test(cim);
	}

	// Egy sima (nem összesítő) hír a játékhoz tartozik-e. Elsőként a címke dönt: ha az
	// egy másik játéké (pl. „Heptarchia 1.39 – a birodalom belső élete”), akkor nem.
	function tartozik(h, kulcs) {
		const cimkek = [h.cimke, h.cimke_en, h.cimke_de].filter(Boolean).join(" | ");
		if (JATEKOK[kulcs].test(cimkek)) return true;
		if (Object.keys(JATEKOK).some(k => k !== kulcs && JATEKOK[k].test(cimkek))) return false;
		return JATEKOK[kulcs].test([h.cim, h.cim_en, h.cim_de].filter(Boolean).join(" | "));
	}

	function valogat(lista, kulcs, lang) {
		const ki = [];
		for (const h of lista) {
			const cimke = nyelvi(h, "cimke", lang) || SZOVEG[lang].tag;
			let reszek = szakaszok(nyelvi(h, "szoveg", lang));
			if (!reszek && lang !== "hu") reszek = szakaszok(h.szoveg);   // nincs lefordítva
			if (reszek) {
				for (const r of reszek) if (jatekaCimsor(r.cim, kulcs)) ki.push({ datum: h.datum, cimke, cim: r.cim, szoveg: r.szoveg });
			} else if (tartozik(h, kulcs)) {
				ki.push({ datum: h.datum, cimke, cim: nyelvi(h, "cim", lang), szoveg: nyelvi(h, "szoveg", lang) });
			}
		}
		// a hirek.json újabb elemei vannak elöl; azonos napon a sorrend marad
		return ki.map((x, i) => [x, i]).sort((a, b) => (b[0].datum || "").localeCompare(a[0].datum || "") || a[1] - b[1]).map(p => p[0]).slice(0, MAX);
	}

	function rajzol(doboz, kulcs, lang) {
		const t = SZOVEG[lang] || SZOVEG.hu;
		const link = `<p class="hir-mind"><a href="./#hirek">${esc(t.all)}</a></p>`;
		if (adat === "hiba") { doboz.innerHTML = `<p class="hir-ures">${esc(t.err)}</p>` + link; return; }
		const lista = valogat(adat, kulcs, SZOVEG[lang] ? lang : "hu");
		doboz.innerHTML = (lista.length ? lista.map(n => `
			<article class="hir">
				<div class="meta"><span>${esc(datum(n.datum, lang))}</span><span class="pill">${esc(n.cimke)}</span></div>
				<h3>${esc(n.cim)}</h3>
				${n.szoveg ? `<p>${esc(n.szoveg).replace(/\n/g, "<br>")}</p>` : ""}
			</article>`).join("") : `<p class="hir-ures">${esc(t.none)}</p>`) + link;
	}

	let betoltes = null;
	window.jatekHirek = function (doboz, kulcs, lang) {
		if (!doboz || !JATEKOK[kulcs]) return;
		doboz.dataset.lang = lang;
		if (adat) return rajzol(doboz, kulcs, lang);
		if (!betoltes) betoltes = fetch("hirek.json?t=" + Date.now(), { cache: "no-store" })
			.then(r => { if (!r.ok) throw new Error(r.status); return r.json(); })
			.then(j => { adat = Array.isArray(j) ? j : []; })
			.catch(() => { adat = "hiba"; });
		// a letöltés végén mindig az akkor érvényes nyelven rajzolunk
		betoltes.then(() => rajzol(doboz, kulcs, doboz.dataset.lang || lang));
	};
})();
