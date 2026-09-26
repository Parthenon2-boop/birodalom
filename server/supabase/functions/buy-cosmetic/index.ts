// Kard és Mágia – megjelenés-rész vásárlása érméért (Supabase Edge Function: buy-cosmetic)
// A játék hívja a belépett fiók tokenjével: { "item": "lovag_fej_sisak_arany" }
// Az árat a SZERVER dönti el (a katalógus itt van), hogy a játékból ne lehessen átírni.
//
// Beállítás: a „Verify JWT” legyen KIKAPCSOLVA (a függvény maga ellenőrzi a belépést).

import { createClient } from "npm:@supabase/supabase-js@2";

// a szerveroldali (titkos) kulcs: a régi service_role, vagy az új sb_secret_… formátum
function serviceKey(): string {
	const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
	if (legacy) return legacy;
	try {
		const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
		return String(keys.default ?? Object.values(keys)[0] ?? "");
	} catch { return ""; }
}

// ── A BOLT KATALÓGUSA ──
// kulcs: <kaszt>_<hely>_<név>, ár érmében (100 érme = 1 $, tehát 10–20 érme = 10–20 cent)
// hely: fej, test, lab, fegyver
const PRICES: Record<string, number> = {};
for (const [cls, parts] of Object.entries({
	lovag: {
		fej: ["sisak_arany", "sisak_szarv", "csuklya"],
		test: ["pancel_arany", "pancel_sotet", "koponyas_vert"],
		lab: ["vaslabvert", "bor_labvert"],
		fegyver: ["kard_lang", "kard_jeg", "csatabard"],
	},
	magus: {
		fej: ["kalap_csillag", "kalap_sotet", "korona"],
		test: ["kontos_kek", "kontos_bibor", "kontos_arany"],
		lab: ["csizma_kek", "csizma_arany"],
		fegyver: ["bot_kristaly", "bot_koponya", "bot_fa"],
	},
	ijasz: {
		fej: ["csuklya_zold", "csuklya_szurke", "tollas_kalap"],
		test: ["bor_vert", "koppeny_zold", "vadasz_mellény"],
		lab: ["csizma_bor", "csizma_magas"],
		fegyver: ["ij_tiszafa", "ij_csont", "szamszerij"],
	},
})) {
	for (const [slot, names] of Object.entries(parts)) {
		for (const n of names) {
			// fegyver és test: 20 érme, fej: 15, láb: 10
			PRICES[`${cls}_${slot}_${n}`] = slot === "fegyver" || slot === "test" ? 20 : slot === "fej" ? 15 : 10;
		}
	}
}

const json = (body: unknown, status = 200) =>
	new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
	const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
	const db = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey());
	const { data: auth } = await db.auth.getUser(token);
	const user = auth?.user;
	if (!user || !user.email) return json({ error: "not_logged_in" }, 401);
	// felfüggesztett fiók (admin) nem vásárolhat
	if (user.banned_until && new Date(user.banned_until).getTime() > Date.now()) return json({ error: "felfuggesztve" }, 403);

	let body: { item?: string };
	try { body = await req.json(); } catch { return json({ error: "bad_request" }, 400); }
	const item = String(body.item ?? "");
	const price = PRICES[item];
	if (!price) return json({ error: "unknown_item" }, 400);

	const { data, error } = await db.rpc("buy_cosmetic", {
		p_user: user.id, p_email: user.email.toLowerCase(), p_item: item, p_price: price,
	});
	if (error) return json({ error: "db_error", message: error.message }, 500);
	const row = Array.isArray(data) ? data[0] : data;
	if (!row?.ok) return json({ error: row?.hiba ?? "hiba", coins: row?.coins ?? 0 }, 400);
	return json({ ok: true, item, price, coins: row.coins });
});
