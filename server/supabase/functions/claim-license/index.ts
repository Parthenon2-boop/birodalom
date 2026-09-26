// ParthLauncher – licenckulcs beváltása a bejelentkezett fiókba (Supabase Edge Function: claim-license)
// A launcher „Van kulcsom” gombja hívja: { "dlc": "varegok", "license_key": "XXXXXXXX-…" }, a fiók tokenjével.
// A kulcsot a Gumroaddal ellenőrizzük, és a fiókhoz kötjük. Egy kulcs csak egy fiókhoz tartozhat; ugyanazzal a
// fiókkal viszont bármelyik gépen újra beváltható (a kiegészítő újra letölthető).
//
// Beállítás: a „Verify JWT” maradhat BEKAPCSOLVA (a launcher a fiók tokenjével hívja).

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

// a kiegészítő kulcsa a launcherben → a Gumroad-termék azonosítója
const PRODUCTS: Record<string, string> = {
	skandinavia: "bpMjj0INnbiEv1kf1hglPg==",
	vikingek: "3q90_eqTWf2lvTKEkkEr8Q==",
	vallas: "DzryuhWncOHx3Pq0IRIP8g==",
	varegok: "lKinUakqfvjYPDG8EnuTbA==",
};

const json = (body: unknown, status = 200) =>
	new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
	const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
	const db = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey());
	const { data: auth } = await db.auth.getUser(token);
	const user = auth?.user;
	if (!user || !user.email) return json({ error: "not_logged_in" }, 401);
	// felfüggesztett fiók (admin) nem válthat be kulcsot
	if (user.banned_until && new Date(user.banned_until).getTime() > Date.now()) return json({ error: "felfuggesztve" }, 403);

	let body: { dlc?: string; license_key?: string };
	try { body = await req.json(); } catch { return json({ error: "bad_request" }, 400); }
	const dlc = String(body.dlc ?? "");
	const key = String(body.license_key ?? "").trim();
	const productId = PRODUCTS[dlc];
	if (!productId || key === "") return json({ error: "bad_request" }, 400);

	// a kulcs ellenőrzése a Gumroadnál (a használatszámot nem növeljük: a fiókhoz kötés számít)
	const res = await fetch("https://api.gumroad.com/v2/licenses/verify", {
		method: "POST",
		body: new URLSearchParams({ product_id: productId, license_key: key, increment_uses_count: "false" }),
	});
	const v = await res.json().catch(() => ({}));
	const p = v?.purchase ?? {};
	if (!v?.success || p.refunded || p.chargebacked || p.disputed) return json({ error: "invalid_key" }, 400);

	const { data: existing } = await db.from("entitlements").select("id, user_id").eq("license_key", key).maybeSingle();
	if (existing) {
		if (existing.user_id && existing.user_id !== user.id) return json({ error: "key_taken" }, 409);
		await db.from("entitlements").update({ user_id: user.id, dlc_key: dlc, revoked: false }).eq("id", existing.id);
		return json({ ok: true, dlc });
	}
	const row = {
		email: user.email.toLowerCase(), user_id: user.id, dlc_key: dlc, license_key: key,
		sale_id: p.sale_id ? String(p.sale_id) : null, source: "license",
	};
	const { error } = await db.from("entitlements").insert(row);
	if (error) {
		// ugyanez a vásárlás már bent van (a Gumroad értesítéséből) – kulcs nélkül: hozzákötjük a fiókhoz
		if (row.sale_id) {
			const { data: bySale } = await db.from("entitlements").select("id, user_id").eq("sale_id", row.sale_id).maybeSingle();
			if (bySale && (!bySale.user_id || bySale.user_id === user.id)) {
				await db.from("entitlements").update({ user_id: user.id, license_key: key }).eq("id", bySale.id);
				return json({ ok: true, dlc });
			}
			if (bySale) return json({ error: "key_taken" }, 409);
		}
		return json({ error: "db_error" }, 500);
	}
	return json({ ok: true, dlc });
});
