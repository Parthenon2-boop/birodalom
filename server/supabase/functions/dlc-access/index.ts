// ParthLauncher – védett kiegészítők (Supabase Edge Function: dlc-access)
//
// A kiegészítők csomagjai egy PRIVÁT GitHub-tárolóban vannak; letöltési linket és a játéknak szóló
// jogosultsági igazolást csak ez a függvény ad, és csak a bejelentkezett, jogosult fióknak.
//
// Kérés (POST, a fiók tokenjével):  { "game": "heptarchia", "machine": "<a gép azonosítója>", "download": "vikingek"? }
// Válasz:
//   token:   { p, s } – aláírt igazolás a játéknak. p = base64(JSON), s = base64(RSA-SHA256 aláírás p bájtjain).
//            A JSON: { v, u (fiók), g (játék), d (kiegészítők), m (gép), iat, exp }.
//            A játék a beépített NYILVÁNOS kulccsal ellenőrzi, és csak az itt felsorolt csomagokat tölti be,
//            csak ezen a gépen, csak lejáratig. Hamisítani nem lehet: a titkos kulcs csak itt van.
//   latest:  { kulcs: címke } – a kiegészítők legújabb kiadása (a frissítéshez)
//   url:     ha "download" meg volt adva és a fióknak joga van hozzá: néhány percig érvényes letöltési link
//
// Titkok (Edge Functions → Secrets):
//   DLC_SIGN_KEY  – az aláíró RSA titkos kulcs (PEM, "BEGIN PRIVATE KEY")
//   GITHUB_TOKEN  – csak olvasási jogú token a privát csomagtárolóhoz (Contents: Read-only)
// Verify JWT: BEKAPCSOLVA.

import { createClient } from "npm:@supabase/supabase-js@2";

const OWNER = "Parthenon2-boop";
const REPO = "heptarchia-dlc-csomagok";
const GAME_DLCS: Record<string, string[]> = {
	heptarchia: ["skandinavia", "vikingek", "vallas", "varegok"],
};
const TOKEN_DAYS = 30;          // ennyi napig érvényes az igazolás (a launcher minden indításkor megújítja)

const json = (body: unknown, status = 200) =>
	new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const b64 = (buf: ArrayBuffer | Uint8Array) => {
	const u = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
	let s = "";
	for (const x of u) s += String.fromCharCode(x);
	return btoa(s);
};

let signKey: CryptoKey | null = null;
async function key(): Promise<CryptoKey> {
	if (signKey) return signKey;
	const pem = (Deno.env.get("DLC_SIGN_KEY") ?? "").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
	const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
	signKey = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
	return signKey;
}

const gh = (path: string, extra: Record<string, string> = {}) =>
	fetch(`https://api.github.com/repos/${OWNER}/${REPO}${path}`, {
		headers: { Authorization: `Bearer ${Deno.env.get("GITHUB_TOKEN") ?? ""}`, "User-Agent": "parthlauncher",
			"X-GitHub-Api-Version": "2022-11-28", ...extra },
		redirect: "manual",
	});

// kiegészítőnként a legújabb (nem vázlat) kiadás, amelyben <kulcs>.zip van: { kulcs: { tag, asset } }
let ghStatus = 0;          // a GitHub legutóbbi válaszkódja (hibakereséshez a válaszban)
async function latest(keys: string[]): Promise<Record<string, { tag: string; asset: number }>> {
	const res = await gh("/releases?per_page=50", { Accept: "application/vnd.github+json" });
	ghStatus = res.status;
	if (!res.ok) return {};
	const rels = await res.json();
	const out: Record<string, { tag: string; asset: number }> = {};
	for (const r of rels) {
		if (r.draft || r.prerelease) continue;
		for (const a of r.assets ?? []) {
			const k = String(a.name).replace(/\.zip$/, "");
			if (keys.includes(k) && !out[k]) out[k] = { tag: String(r.tag_name), asset: Number(a.id) };
		}
	}
	return out;
}

Deno.serve(async (req: Request) => {
	const auth = req.headers.get("Authorization") ?? "";
	const url = Deno.env.get("SUPABASE_URL")!;
	// a felhasználó saját jogaival olvasunk: ugyanaz a szabály (RLS) dönt, mint a launcher listájánál
	const db = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
	const { data: u } = await db.auth.getUser(auth.replace(/^Bearer\s+/i, ""));
	const user = u?.user;
	if (!user) return json({ error: "not_logged_in" }, 401);
	// felfüggesztett fiók (admin) nem tölthet le és nem kap igazolást
	if (user.banned_until && new Date(user.banned_until).getTime() > Date.now()) return json({ error: "felfuggesztve" }, 403);

	let body: { game?: string; machine?: string; download?: string };
	try { body = await req.json(); } catch { return json({ error: "bad_request" }, 400); }
	const game = String(body.game ?? "");
	const machine = String(body.machine ?? "").trim();
	const all = GAME_DLCS[game];
	if (!all || machine === "" || machine.length > 200) return json({ error: "bad_request" }, 400);

	const { data: rows, error } = await db.from("entitlements").select("dlc_key");
	if (error) return json({ error: "db_error" }, 500);
	const owned = [...new Set((rows ?? []).map((r: { dlc_key: string }) => String(r.dlc_key)))].filter((k) => all.includes(k)).sort();

	const now = Math.floor(Date.now() / 1000);
	const payload = new TextEncoder().encode(JSON.stringify({
		v: 1, u: user.id, g: game, d: owned, m: machine, iat: now, exp: now + TOKEN_DAYS * 86400,
	}));
	const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", await key(), payload);
	const resp: Record<string, unknown> = { token: { p: b64(payload), s: b64(sig) }, owned };

	const rel = await latest(all);
	const tags: Record<string, string> = {};
	for (const k of owned) if (rel[k]) tags[k] = rel[k].tag;
	resp.latest = tags;

	const dl = String(body.download ?? "");
	if (dl !== "") {
		if (!owned.includes(dl)) return json({ error: "not_owned" }, 403);
		if (!rel[dl]) return json({ error: ghStatus === 200 ? "no_release" : "github_error", github: ghStatus }, ghStatus === 200 ? 404 : 502);
		// a GitHub egy néhány percig érvényes, aláírt címre irányít át: azt adjuk tovább
		const a = await gh(`/releases/assets/${rel[dl].asset}`, { Accept: "application/octet-stream" });
		const loc = a.headers.get("location");
		if (!loc) return json({ error: "github_error", status: a.status }, 502);
		resp.url = loc;
		resp.tag = rel[dl].tag;
	}
	return json(resp);
});
