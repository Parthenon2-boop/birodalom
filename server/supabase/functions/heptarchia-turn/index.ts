// Heptarchia a böngészőben – közvetítő (TURN) szerver a többjátékos szobákhoz (Supabase Edge Function: heptarchia-turn)
//
// A böngészős többjátékos mód WebRTC-vel megy: a két gép közvetlenül kapcsolódik egymáshoz. Szigorú hálózatok
// (mobilnet, iskolai / céges hálózat) között ez közvetlenül nem jön létre – ilyenkor a forgalom egy közvetítő
// (TURN) szerveren megy át. A közvetítő a Cloudflare Realtime TURN szolgáltatása; a hozzá való belépőadat titkos
// kulcsból készül, ezért azt nem a játék, hanem ez a függvény kéri, és csak rövid életű belépőt ad tovább.
//
//   Játékos (POST, a fiók tokenjével, a böngészőből):  {}  →  { iceServers: [ … ] }
//     – a WebRTC-nek átadható szerverlista (STUN + TURN, a belépő TTL_MP másodpercig érvényes).
//     Csak az kap, aki be van jelentkezve, nincs felfüggesztve, a hivatalos oldalról jön, ÉS az online játékra
//     meg van hívva (heptarchia_online_engedely – schema_heptarchia_online.sql).
//     Ha a TURN nincs beállítva (hiányzó titkok) vagy a Cloudflare nem válaszol: { iceServers: [] } – a játék
//     ilyenkor a nyilvános STUN-szerverekkel próbálkozik (közvetítő nélkül).
//     Hibák: not_logged_in (401), felfuggesztve (403), rossz_oldal (403), nincs_meghivva (403).
//
// Titkok (Edge Functions → Secrets): CF_TURN_KEY_ID és CF_TURN_API_TOKEN – a Cloudflare-fiókban:
// Realtime → TURN Server → Create („Turn Token ID” és „API Token”). Telepítés: --no-verify-jwt (a függvény maga
// ellenőrzi a tokent; a böngésző CORS-előkérése token nélkül jön).

import { createClient } from "npm:@supabase/supabase-js@2";

const TTL_MP = 86400;              // a belépő ennyi másodpercig érvényes (egy hosszú játék is beleférjen)
const ENGEDETT_OLDALAK = new Set([
	"https://parthenon2-boop.github.io",
	...(Deno.env.get("HEP_WEB_ORIGINS") ?? "").split(",").map((s) => s.trim()).filter(Boolean),
]);
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

type IceSzerver = { urls: string[]; username?: string; credential?: string };

// A Cloudflare válasza -> a böngészőnek átadható lista. (Az 53-as portot a böngészők tiltják: azok a címek
// csak lassítanák a kapcsolódást, ezért kimaradnak.)
function szerverek(valasz: unknown): IceSzerver[] {
	const nyers = (valasz as { iceServers?: unknown })?.iceServers;
	const lista = Array.isArray(nyers) ? nyers : (nyers ? [nyers] : []);
	const ki: IceSzerver[] = [];
	for (const s of lista as Record<string, unknown>[]) {
		const urls = (Array.isArray(s.urls) ? s.urls : [s.urls]).map((u) => String(u ?? ""))
			.filter((u) => /^(stun|turn|turns):/.test(u) && !/:53(\?|$)/.test(u));
		if (urls.length === 0) continue;
		const sz: IceSzerver = { urls };
		if (typeof s.username === "string" && typeof s.credential === "string") {
			sz.username = s.username;
			sz.credential = s.credential;
		}
		ki.push(sz);
	}
	return ki;
}

Deno.serve(async (req: Request) => {
	const origin = req.headers.get("Origin") ?? "";
	const h = cors(origin);
	const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: h });
	if (req.method === "OPTIONS") return new Response("ok", { headers: h });
	if (req.method !== "POST") return json({ error: "bad_request" }, 405);
	if (!ENGEDETT_OLDALAK.has(origin) && !helyi(origin)) return json({ error: "rossz_oldal" }, 403);

	const db = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey(), {
		auth: { persistSession: false, autoRefreshToken: false },
	});
	const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
	const { data: u } = await db.auth.getUser(token);
	const user = u?.user;
	if (!user) return json({ error: "not_logged_in" }, 401);
	if (user.banned_until && new Date(user.banned_until).getTime() > Date.now()) return json({ error: "felfuggesztve" }, 403);

	// csak az online játékra meghívott fiók (a lista kisbetűs, NFC-alakú neveihez mérve)
	const { data: prof } = await db.from("profiles").select("username").eq("user_id", user.id).maybeSingle();
	const nev = String((prof as { username?: string } | null)?.username ?? "").normalize("NFC").toLowerCase();
	if (nev === "") return json({ error: "nincs_meghivva" }, 403);
	const { data: eng } = await db.from("heptarchia_online_engedely").select("username").eq("username", nev).maybeSingle();
	if (!eng) return json({ error: "nincs_meghivva" }, 403);

	const kulcs = Deno.env.get("CF_TURN_KEY_ID") ?? "";
	const cfToken = Deno.env.get("CF_TURN_API_TOKEN") ?? "";
	if (kulcs === "" || cfToken === "") return json({ iceServers: [], info: "nincs_turn" });
	try {
		const r = await fetch(`https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(kulcs)}/credentials/generate-ice-servers`, {
			method: "POST",
			headers: { "Authorization": `Bearer ${cfToken}`, "Content-Type": "application/json" },
			body: JSON.stringify({ ttl: TTL_MP }),
			signal: AbortSignal.timeout(6000),
		});
		if (!r.ok) return json({ iceServers: [], info: "turn_hiba", kod: r.status });
		return json({ iceServers: szerverek(await r.json()) });
	} catch {
		return json({ iceServers: [], info: "turn_hiba" });
	}
});
