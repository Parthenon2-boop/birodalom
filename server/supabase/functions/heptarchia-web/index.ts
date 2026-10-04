// Heptarchia a böngészőben – a játékcsomag (.pck) kiadása csak bejelentkezett fióknak (Supabase Edge Function: heptarchia-web)
//
// A böngészős Heptarchia oldalán (honlap: docs/jatek/heptarchia/) csak a betöltő van (index.html, a Godot-motor
// index.js/index.wasm-ja); maga a játék (index.pck) a PRIVÁT „heptarchia-web” Storage-tárolóban van. Ez a függvény:
//
//   1) Játékos (POST, a fiók tokenjével, a böngészőből):  {}  →
//        { ver, size, url }  – a legújabb csomag verziója, mérete és egy 5 percig érvényes, aláírt letöltési link.
//      Ellenőrzi: érvényes-e a token (bejelentkezett fiók), nincs-e felfüggesztve, a hivatalos oldalról jön-e a kérés
//      (Origin), és hogy egy fiók óránként legfeljebb ORANKENT_MAX linket kérhet. Minden kiadást naplóz
//      (heptarchia_web_log: fiók, idő, oldal, verzió) – az admin így látja, ki és mikor játszott a böngészőben.
//      Hibák: not_logged_in (401), felfuggesztve (403), rossz_oldal (403), tul_sok (429), nincs_csomag (404).
//
//   2) Feltöltés (a heptarchia tároló GitHub Actions-e, web.yml):  { "feltoltes": "<verzió>", "meret": <bájt> }
//      és az x-feltolto-kulcs fejlécben a HEP_WEB_FELTOLTO_KULCS titok  →  { path, token, signedUrl }:
//      egy aláírt FELTÖLTÉSI link a <verzió>/index.pck helyre. A feltöltés után a CI { "kesz": "<verzió>", "meret": n }
//      kéréssel állítja át az aktuális verziót (aktualis.json a tárolóban). A szerveroldali kulcs így sosem hagyja el a
//      Supabase-t; a GitHubon csak ez a szűk, csak feltöltésre jó kulcs van.
//
// Titkok (Edge Functions → Secrets): HEP_WEB_FELTOLTO_KULCS (hosszú, véletlen szöveg – ugyanaz, mint a heptarchia
// tároló GitHub-titka). Telepítés: --no-verify-jwt (a függvény maga ellenőrzi a tokent; a böngésző CORS-előkérése
// token nélkül jön). A tároló és a napló: schema_heptarchia_web.sql.

import { createClient } from "npm:@supabase/supabase-js@2";

const TAROLO = "heptarchia-web";
const AKTUALIS = "aktualis.json";
const LINK_MP = 300;               // a letöltési link ennyi másodpercig érvényes
const ORANKENT_MAX = 30;           // ennyi link kérhető fiókonként óránként
const ENGEDETT_OLDALAK = new Set([
	"https://parthenon2-boop.github.io",
	...(Deno.env.get("HEP_WEB_ORIGINS") ?? "").split(",").map((s) => s.trim()).filter(Boolean),
]);
// fejlesztéskor a saját gépről (http://localhost:<port>, http://127.0.0.1:<port>) is – fiók itt is kell
const helyi = (o: string) => /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(o);

function serviceKey(): string {
	const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
	if (legacy) return legacy;
	try {
		const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
		return String(keys.default ?? Object.values(keys)[0] ?? "");
	} catch { return ""; }
}

function cors(origin: string): Record<string, string> {
	const h: Record<string, string> = {
		"Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
		"Access-Control-Allow-Methods": "POST, OPTIONS",
		"Access-Control-Max-Age": "600",
		"Vary": "Origin",
		"Cache-Control": "no-store",
		"Content-Type": "application/json",
	};
	if (ENGEDETT_OLDALAK.has(origin) || helyi(origin)) h["Access-Control-Allow-Origin"] = origin;
	return h;
}

// állandó idejű összehasonlítás (a feltöltési kulcshoz)
function egyezik(a: string, b: string): boolean {
	if (a.length !== b.length || a.length === 0) return false;
	let d = 0;
	for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
	return d === 0;
}

const VERZIO = /^[A-Za-z0-9._-]{1,40}$/;

Deno.serve(async (req: Request) => {
	const origin = req.headers.get("Origin") ?? "";
	const h = cors(origin);
	const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: h });
	if (req.method === "OPTIONS") return new Response("ok", { headers: h });
	if (req.method !== "POST") return json({ error: "bad_request" }, 405);

	const db = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey(), {
		auth: { persistSession: false, autoRefreshToken: false },
	});
	let body: Record<string, unknown> = {};
	try { body = await req.json(); } catch { /* üres kérés */ }

	// ── 2) a CI feltöltése ──
	const feltoltoKulcs = req.headers.get("x-feltolto-kulcs") ?? "";
	if (feltoltoKulcs !== "") {
		if (!egyezik(feltoltoKulcs, Deno.env.get("HEP_WEB_FELTOLTO_KULCS") ?? "")) return json({ error: "forbidden" }, 403);
		if (typeof body.feltoltes === "string") {
			const ver = body.feltoltes;
			if (!VERZIO.test(ver)) return json({ error: "bad_request" }, 400);
			const { data, error } = await db.storage.from(TAROLO).createSignedUploadUrl(`${ver}/index.pck`, { upsert: true });
			if (error || !data) return json({ error: "storage", message: error?.message }, 500);
			return json(data);
		}
		if (typeof body.kesz === "string") {
			const ver = body.kesz;
			if (!VERZIO.test(ver)) return json({ error: "bad_request" }, 400);
			const meret = Number(body.meret ?? 0);
			const tartalom = new Blob([JSON.stringify({ ver, size: meret, ido: new Date().toISOString() })], { type: "application/json" });
			const { error } = await db.storage.from(TAROLO).upload(AKTUALIS, tartalom, { upsert: true, contentType: "application/json" });
			if (error) return json({ error: "storage", message: error.message }, 500);
			// a régi verziók törlése (az aktuálison kívül)
			const { data: lista } = await db.storage.from(TAROLO).list("", { limit: 100 });
			const regiek: string[] = [];
			for (const e of lista ?? []) {
				if (e.name !== AKTUALIS && e.name !== ver && !e.name.includes(".")) regiek.push(`${e.name}/index.pck`);
			}
			if (regiek.length > 0) await db.storage.from(TAROLO).remove(regiek);
			return json({ ok: true, ver, torolve: regiek.length });
		}
		return json({ error: "bad_request" }, 400);
	}

	// ── 1) a játékos ──
	if (!ENGEDETT_OLDALAK.has(origin) && !helyi(origin)) return json({ error: "rossz_oldal" }, 403);
	const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
	const { data: u } = await db.auth.getUser(token);
	const user = u?.user;
	if (!user) return json({ error: "not_logged_in" }, 401);
	if (user.banned_until && new Date(user.banned_until).getTime() > Date.now()) return json({ error: "felfuggesztve" }, 403);

	const egyOraja = new Date(Date.now() - 3600 * 1000).toISOString();
	const { count } = await db.from("heptarchia_web_log").select("id", { count: "exact", head: true })
		.eq("user_id", user.id).gte("ido", egyOraja);
	if ((count ?? 0) >= ORANKENT_MAX) return json({ error: "tul_sok" }, 429);

	const { data: akt } = await db.storage.from(TAROLO).download(AKTUALIS);
	let ver = "", size = 0;
	try { const j = JSON.parse(await akt!.text()); ver = String(j.ver ?? ""); size = Number(j.size ?? 0); } catch { /* nincs még csomag */ }
	if (!VERZIO.test(ver)) return json({ error: "nincs_csomag" }, 404);
	const { data: link, error } = await db.storage.from(TAROLO).createSignedUrl(`${ver}/index.pck`, LINK_MP);
	if (error || !link) return json({ error: "nincs_csomag" }, 404);

	await db.from("heptarchia_web_log").insert({ user_id: user.id, oldal: origin.slice(0, 100), verzio: ver });
	return json({ ver, size, url: link.signedUrl });
});
