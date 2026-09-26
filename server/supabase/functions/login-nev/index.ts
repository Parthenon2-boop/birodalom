// ParthLauncher – belépés FIÓKNÉVVEL (Supabase Edge Function: login-nev)
//
// A launcher ezt hívja: { "nev": "bence", "password": "…" }
// A `nev` lehet fióknév VAGY e-mail-cím – a régi fiókoknak még nincs nevük,
// azok így továbbra is be tudnak lépni.
//
// Miért kell szerveroldal? Mert a Supabase belépése e-mail-címmel megy. A
// fióknévhez tartozó címet csak a titkos kulccsal lehet kikeresni, és azt SOHA
// nem adjuk vissza a kliensnek – csak a kész munkamenetet.
//
// Beállítás: a „Verify JWT" legyen KIKAPCSOLVA (belépés előtt még nincs token).

import { createClient } from "npm:@supabase/supabase-js@2";

function serviceKey(): string {
	const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
	if (legacy) return legacy;
	try {
		const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
		return String(keys.default ?? Object.values(keys)[0] ?? "");
	} catch { return ""; }
}

// A weboldal (docs/fiok.html) is ezzel lép be: a böngészőnek CORS-fejléc kell, de csak a saját oldalunkról.
// (A launcher nem böngésző, neki ez közömbös.)
const WEB_ORIGIN = "https://parthenon2-boop.github.io";

Deno.serve(async (req: Request) => {
	// kérésenként számoljuk (a függvény egyszerre több kérést is kiszolgálhat)
	const CORS: Record<string, string> = req.headers.get("Origin") === WEB_ORIGIN ? {
		"Access-Control-Allow-Origin": WEB_ORIGIN, "Vary": "Origin",
		"Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
		"Access-Control-Allow-Methods": "POST, OPTIONS",
	} : { "Vary": "Origin" };
	const json = (body: unknown, status = 200) =>
		new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
	if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
	let body: { nev?: string; password?: string };
	try { body = await req.json(); } catch { return json({ error: "bad_request" }, 400); }

	const nev = String(body.nev ?? "").trim();
	const password = String(body.password ?? "");
	if (nev === "" || password === "") return json({ error: "bad_request" }, 400);

	const url = Deno.env.get("SUPABASE_URL")!;
	const db = createClient(url, serviceKey());

	// Fióknév vagy e-mail? Ha van benne @, e-mailnek vesszük.
	let email = nev;
	if (!nev.includes("@")) {
		const { data, error } = await db
			.from("profiles")
			.select("user_id")
			.eq("username", nev)
			.maybeSingle();
		// Szándékosan ugyanazt a hibát adjuk, mint rossz jelszónál: ne lehessen
		// kitalálni belőle, melyik fióknév létezik.
		if (error || !data) return json({ error: "rossz_belepes" }, 400);
		const { data: user } = await db.auth.admin.getUserById(String(data.user_id));
		if (!user?.user?.email) return json({ error: "rossz_belepes" }, 400);
		email = user.user.email;
	}

	// A jelszó ellenőrzése a rendes belépési végponton, a NYILVÁNOS kulccsal:
	// így pontosan azt a munkamenetet kapjuk vissza, amit a kliens vár.
	const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
	const res = await fetch(`${url}/auth/v1/token?grant_type=password`, {
		method: "POST",
		headers: { "Content-Type": "application/json", apikey: anon, Authorization: `Bearer ${anon}` },
		body: JSON.stringify({ email, password }),
	});
	const data = await res.json().catch(() => ({}));
	if (!res.ok) {
		const msg = String(data?.msg ?? data?.error_description ?? "").toLowerCase();
		if (msg.includes("confirm")) return json({ error: "nincs_megerositve" }, 400);
		return json({ error: "rossz_belepes" }, 400);
	}
	return json(data, 200);
});
