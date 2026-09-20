// ParthLauncher – Gumroad „Ping” fogadása (Supabase Edge Function: gumroad-ping)
// Minden Gumroad-vásárláskor a Gumroad ide küldi az adatokat (form-urlencoded). A vásárlás a vevő
// e-mail-címéhez kerül: ha ezzel a címmel regisztrál (vagy már regisztrált) a launcherben, a kiegészítő
// magától megjelenik nála. Visszatérítéskor a jogosultság megszűnik.
//
// Beállítás: a függvénynél a „Verify JWT” (Enforce JWT verification) legyen KIKAPCSOLVA (a Gumroad nem küld
// tokent); védelem helyett a titkos kulcs: GUMROAD_PING_SECRET (Edge Functions → Secrets), és a Gumroad
// Ping URL-je: https://<projekt>.supabase.co/functions/v1/gumroad-ping?secret=<ugyanaz a titok>

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

// Gumroad-termék (azonosító vagy rövid link) → a kiegészítő kulcsa a launcherben
const PRODUCTS: Record<string, string> = {
	"bpMjj0INnbiEv1kf1hglPg==": "skandinavia", "ltsalt": "skandinavia",
	"3q90_eqTWf2lvTKEkkEr8Q==": "vikingek", "fxtisw": "vikingek",
	"DzryuhWncOHx3Pq0IRIP8g==": "vallas", "iwqkt": "vallas",
	"lKinUakqfvjYPDG8EnuTbA==": "varegok", "jrzwus": "varegok",
};

// Érmecsomagok (Kard és Mágia bolt): Gumroad-termék → jóváírt érme.
// 100 érme = 1 $, így a boltban egy megjelenés-rész 10–20 érme, vagyis 10–20 cent.
const COIN_PACKS: Record<string, number> = {
	"iszcby": 100,   // Kard és Mágia – 100 érme (0,99 $)
	"zwaqr": 220,    // Kard és Mágia – 220 érme (1,99 $)
	"bnjaw": 600,    // Kard és Mágia – 600 érme (4,99 $)
};

Deno.serve(async (req: Request) => {
	const url = new URL(req.url);
	const secret = (Deno.env.get("GUMROAD_PING_SECRET") ?? "").trim();   // bemásoláskor a végére kerülhet sortörés
	if (secret === "" || (url.searchParams.get("secret") ?? "").trim() !== secret) {
		return new Response("forbidden", { status: 403 });
	}
	// a valódi értesítés űrlapadat, a „Send test ping” JSON-t küld
	let data: Record<string, unknown> = {};
	try {
		if ((req.headers.get("content-type") ?? "").includes("json")) data = await req.json();
		else data = Object.fromEntries((await req.formData()).entries());
	} catch { return new Response("bad request", { status: 400 }); }
	const get = (k: string) => String(data[k] ?? "");
	const permalink = (get("permalink") || get("product_permalink")).split("/").pop() ?? "";
	const dlc = PRODUCTS[get("product_id")] ?? PRODUCTS[permalink];
	const coins = COIN_PACKS[get("product_id")] ?? COIN_PACKS[permalink] ?? 0;
	if (!dlc && !coins) return new Response("unknown product", { status: 200 });

	const email = get("email").trim().toLowerCase();
	const saleId = get("sale_id");
	const licenseKey = get("license_key") || null;
	const cancelled = ["refunded", "disputed", "chargebacked"].some((k) => get(k) === "true");
	if (email === "" || saleId === "") return new Response("missing data", { status: 400 });

	const db = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey());

	// ── érmecsomag: jóváírás a vevő e-mail-címére (a fiókhoz a játék első vásárlásakor kötjük) ──
	if (coins) {
		// hány darabot vett egyszerre
		const qty = Math.max(1, parseInt(get("quantity") || "1", 10) || 1);
		if (cancelled) {
			// visszatérítés: az egészet levonjuk (egyszer)
			const { data: back } = await db.from("coin_tx").select("id").eq("sale_id", saleId + "-vissza").maybeSingle();
			if (back) return new Response("ok");
			const { data: orig } = await db.from("coin_tx").select("amount, user_id, email").eq("sale_id", saleId).maybeSingle();
			if (!orig) return new Response("ok");
			await db.from("coin_tx").insert({
				user_id: orig.user_id, email: orig.email, amount: -orig.amount,
				reason: "visszateritve", sale_id: saleId + "-vissza",
			});
			return new Response("refunded");
		}
		const { error } = await db.from("coin_tx").upsert(
			{ email, amount: coins * qty, reason: "gumroad", sale_id: saleId },
			{ onConflict: "sale_id" },
		);
		if (error) return new Response("db error: " + error.message, { status: 500 });
		return new Response("coins ok");
	}

	if (cancelled) {
		await db.from("entitlements").update({ revoked: true }).eq("sale_id", saleId);
		return new Response("revoked");
	}

	// ha a kulcsot már beváltották egy fiókban (claim-license), csak a vásárlás adatait egészítjük ki
	if (licenseKey) {
		const { data: byKey } = await db.from("entitlements").select("id").eq("license_key", licenseKey).maybeSingle();
		if (byKey) {
			await db.from("entitlements").update({ sale_id: saleId, dlc_key: dlc }).eq("id", byKey.id);
			return new Response("ok");
		}
	}
	const { error } = await db.from("entitlements").upsert(
		{ email, dlc_key: dlc, sale_id: saleId, license_key: licenseKey, source: "gumroad" },
		{ onConflict: "sale_id" },
	);
	if (error) return new Response("db error: " + error.message, { status: 500 });
	return new Response("ok");
});
