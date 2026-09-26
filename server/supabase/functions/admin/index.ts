// ParthLauncher – ADMIN felület kiszolgálója (Supabase Edge Function: admin)
//
// A docs/admin.html (és a docs/fiok.html az Admin link miatt) hívja, a weboldal közös belépésével kapott
// tokennel. Minden kérés POST, JSON-törzzsel: { "action": "…", … }
//   whoami   {}                           – admin-e a fiók (200 = igen, 403 = nem)
//   me       {}                           – ki vagyok, a kiegészítők listája, összesítők
//   accounts { search?, page? }           – fióklista (50/oldal), keresés fióknévre / e-mailre
//   user     { id }                       – egy fiók részletei: jogosultság-sorok, érmetörténet
//   dlc      { id, dlc, grant, note? }    – kiegészítő adása (grant=true) / visszavonása (false)
//   coins    { id, amount, note }         – érme jóváírása (+) / levonása (−); indoklás kötelező
//   log      { page? }                    – az admin-napló (50/oldal)
// Mindegyikhez a fiók tokenje kell (Authorization: Bearer <access_token>), és a fióknak benne kell
// lennie a public.admins táblában (lásd schema_admin.sql). Minden módosítás naplózódik (public.admin_log).
//
// Biztonság:
//   • A szerveroldali (service_role) kulcs csak itt, a függvényben van – a weboldalon SOHA.
//   • A jogosultságot minden kérésnél újra ellenőrizzük (token → fiók → admins tábla).
//   • CORS: csak a GitHub Pages oldalról (ALLOWED_ORIGINS; bővíthető az ADMIN_ORIGINS titokkal, vesszővel).
//
// Beállítás: telepítés `--no-verify-jwt` kapcsolóval – a függvény MAGA ellenőrzi a tokent minden kérésnél
// (mint a buy-cosmetic), így a böngésző CORS-előkérése (OPTIONS, token nélkül) sem akad el a kapun.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

function serviceKey(): string {
	const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
	if (legacy) return legacy;
	try {
		const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
		return String(keys.default ?? Object.values(keys)[0] ?? "");
	} catch { return ""; }
}

// a kiegészítők, amelyeket a rendszer ismer (a launcher DLCS táblája és a dlc-access szerint)
const DLCS = [
	{ key: "skandinavia", name: "Skandinávia", game: "heptarchia" },
	{ key: "vikingek", name: "A vikingek kora", game: "heptarchia" },
	{ key: "vallas", name: "Hit és egyház", game: "heptarchia" },
	{ key: "varegok", name: "A varégok útja", game: "heptarchia" },
];
const DLC_KEYS = new Set(DLCS.map((d) => d.key));
const PAGE = 50;
// true: a fióklistában a teljes e-mail-cím látszik; false: csak kitakarva (pl. pa•••@gmail.com)
const SHOW_FULL_EMAIL = false;

const ALLOWED_ORIGINS = new Set([
	"https://parthenon2-boop.github.io",
	...(Deno.env.get("ADMIN_ORIGINS") ?? "").split(",").map((s) => s.trim()).filter(Boolean),
]);

function cors(req: Request): Record<string, string> {
	const origin = req.headers.get("Origin") ?? "";
	const h: Record<string, string> = {
		"Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
		"Access-Control-Allow-Methods": "POST, OPTIONS",
		"Access-Control-Max-Age": "600",
		"Vary": "Origin",
		"Cache-Control": "no-store",
	};
	if (ALLOWED_ORIGINS.has(origin)) h["Access-Control-Allow-Origin"] = origin;
	return h;
}

const maskEmail = (e: string) => {
	if (SHOW_FULL_EMAIL) return e;
	const [name, dom] = e.split("@");
	if (!dom) return "•••";
	return name.slice(0, 2) + "•••@" + dom;
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type Body = Record<string, unknown>;
type Admin = { id: string; name: string };

// a bejelentkezett hívó, ha admin; különben null
async function whoIsAdmin(db: SupabaseClient, token: string): Promise<Admin | "no_login" | "no_admin"> {
	if (!token) return "no_login";
	const { data: auth } = await db.auth.getUser(token);
	const user = auth?.user;
	if (!user) return "no_login";
	const { data: adm } = await db.from("admins").select("user_id").eq("user_id", user.id).maybeSingle();
	if (!adm) return "no_admin";
	const { data: prof } = await db.from("profiles").select("username").eq("user_id", user.id).maybeSingle();
	return { id: user.id, name: String(prof?.username ?? user.email ?? user.id) };
}

async function accountsPage(db: SupabaseClient, search: string, page: number) {
	const { data, error } = await db.rpc("admin_accounts", {
		p_search: search, p_limit: PAGE, p_offset: page * PAGE,
	});
	if (error) throw new Error(error.message);
	const rows = (data ?? []) as Record<string, unknown>[];
	return {
		total: rows.length ? Number(rows[0].total) : 0,
		rows: rows.map((r) => ({
			id: r.user_id, username: r.username ?? null, email: maskEmail(String(r.email ?? "")),
			created_at: r.created_at, last_sign_in_at: r.last_sign_in_at, confirmed: r.confirmed,
			coins: r.coins, dlcs: r.dlcs ?? [],
		})),
	};
}

async function handle(db: SupabaseClient, admin: Admin, action: string, body: Body): Promise<[unknown, number]> {
	switch (action) {
		case "whoami":
			// a fiók oldal ezzel kérdezi meg, mutassa-e az „Admin” linket (nem adminnak 403 jön)
			return [{ admin: true, name: admin.name }, 200];
		case "me": {
			const all = await accountsPage(db, "", 0);
			const { count: named } = await db.from("profiles").select("user_id", { count: "exact", head: true });
			return [{ admin, dlcs: DLCS, stats: { accounts: all.total, with_username: named ?? 0 } }, 200];
		}
		case "accounts": {
			const search = String(body.search ?? "").trim().slice(0, 100);
			const page = Math.max(0, Math.floor(Number(body.page ?? 0)) || 0);
			return [{ ...(await accountsPage(db, search, page)), page, page_size: PAGE }, 200];
		}
		case "user": {
			const id = String(body.id ?? "");
			if (!UUID_RE.test(id)) return [{ error: "bad_request" }, 400];
			const { data: u } = await db.auth.admin.getUserById(id);
			if (!u?.user) return [{ error: "nincs_fiok" }, 404];
			const email = String(u.user.email ?? "").toLowerCase();
			// a fiókhoz kötött sorok + a még csak e-mail-címmel jóváírtak (a vásárlások kisbetűs címmel kerülnek be)
			const q = (table: string, cols: string) => Promise.all([
				db.from(table).select(cols).eq("user_id", id).order("created_at", { ascending: false }).limit(100),
				email
					? db.from(table).select(cols).is("user_id", null).eq("email", email).order("created_at", { ascending: false }).limit(100)
					: Promise.resolve({ data: [] }),
			]).then(([a, b]) => [...((a.data ?? []) as unknown as Record<string, string>[]), ...((b.data ?? []) as unknown as Record<string, string>[])]
				.sort((x, y) => String(y.created_at).localeCompare(String(x.created_at))));
			const [ent, tx] = await Promise.all([
				q("entitlements", "dlc_key, source, revoked, created_at"),
				q("coin_tx", "amount, reason, item_key, created_at"),
			]);
			return [{ entitlements: ent, coin_tx: tx }, 200];
		}
		case "dlc": {
			const id = String(body.id ?? "");
			const dlc = String(body.dlc ?? "");
			if (!UUID_RE.test(id) || !DLC_KEYS.has(dlc) || typeof body.grant !== "boolean") return [{ error: "bad_request" }, 400];
			const { data, error } = await db.rpc("admin_dlc", {
				p_admin: admin.id, p_admin_name: admin.name, p_target: id, p_dlc: dlc, p_grant: body.grant,
				p_note: String(body.note ?? "").slice(0, 300),
			});
			if (error) return [{ error: "db_error", message: error.message }, 500];
			const row = Array.isArray(data) ? data[0] : data;
			if (!row?.ok) return [{ error: row?.hiba || "hiba" }, 400];
			return [{ ok: true, changed: row.valtozott, info: row.hiba }, 200];
		}
		case "coins": {
			const id = String(body.id ?? "");
			const amount = Number(body.amount);
			const note = String(body.note ?? "").trim().slice(0, 300);
			if (!UUID_RE.test(id) || !Number.isInteger(amount) || amount === 0 || Math.abs(amount) > 1000000) {
				return [{ error: "bad_request" }, 400];
			}
			if (note.length < 3) return [{ error: "kell_indoklas" }, 400];
			const { data, error } = await db.rpc("admin_coins", {
				p_admin: admin.id, p_admin_name: admin.name, p_target: id, p_amount: amount, p_note: note,
			});
			if (error) return [{ error: "db_error", message: error.message }, 500];
			const row = Array.isArray(data) ? data[0] : data;
			if (!row?.ok) return [{ error: row?.hiba || "hiba", coins: row?.coins ?? null }, 400];
			return [{ ok: true, coins: row.coins }, 200];
		}
		case "log": {
			const page = Math.max(0, Math.floor(Number(body.page ?? 0)) || 0);
			const { data, error, count } = await db.from("admin_log")
				.select("id, admin_name, action, target_id, target_name, details, created_at", { count: "exact" })
				.order("created_at", { ascending: false }).range(page * PAGE, page * PAGE + PAGE - 1);
			if (error) return [{ error: "db_error", message: error.message }, 500];
			return [{ rows: data ?? [], total: count ?? 0, page, page_size: PAGE }, 200];
		}
	}
	return [{ error: "unknown_action" }, 400];
}

Deno.serve(async (req: Request) => {
	const h = cors(req);
	const reply = (body: unknown, status = 200) =>
		new Response(JSON.stringify(body), { status, headers: { ...h, "Content-Type": "application/json" } });
	if (req.method === "OPTIONS") return new Response("ok", { headers: h });
	if (req.method !== "POST") return reply({ error: "bad_method" }, 405);
	// böngészőből csak az engedélyezett oldalról (más oldal a CORS miatt amúgy sem olvashatná a választ)
	const origin = req.headers.get("Origin");
	if (origin && !ALLOWED_ORIGINS.has(origin)) return reply({ error: "forbidden_origin" }, 403);

	let body: Body;
	try { body = await req.json(); } catch { return reply({ error: "bad_request" }, 400); }
	if (!body || typeof body !== "object") return reply({ error: "bad_request" }, 400);
	const action = String(body.action ?? "");

	const db = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey(), {
		auth: { persistSession: false, autoRefreshToken: false },
	});
	try {
		const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
		const admin = await whoIsAdmin(db, token);
		if (admin === "no_login") return reply({ error: "not_logged_in" }, 401);
		if (admin === "no_admin") return reply({ error: "nincs_jog" }, 403);
		const [b, s] = await handle(db, admin, action, body);
		return reply(b, s);
	} catch (e) {
		console.error("admin hiba:", e);
		return reply({ error: "server_error" }, 500);
	}
});
