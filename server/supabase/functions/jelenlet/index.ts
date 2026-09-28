// ParthLauncher – JÁTÉKIDŐ és JELENLÉT (Supabase Edge Function: jelenlet)
//
// A launcher a játék indításakor hívja, utána egy kis rejtett figyelő (Windows: PowerShell, macOS: /bin/sh),
// amely a launcher bezárulása után is fut, amíg a játék fut. Táblája: public.jatek_munkamenet (schema_jelenlet.sql).
//
// Kérés (POST, JSON):
//   { action:"start", game, machine? }  – a fiók tokenjével (Authorization: Bearer <access_token>)
//                                         → { sid, key }  (a kulcsot NEM tároljuk, csak az SHA-256 lenyomatát)
//   { action:"beat", sid, key }         – token nélkül; a játék még fut → last_seen = most
//                                         (60 mp-en belüli ismétlést figyelmen kívül hagy;
//                                          15 percnél nagyobb szünet – alvás, hibernálás – után a régi munkamenet
//                                          a legutolsó jelzésnél lezárul, és ugyanazzal a kulccsal újat nyitunk)
//                                         → { ok, sid }  (sid: az aktuális munkamenet – a figyelő ezt használja tovább)
//   { action:"stop", sid, key }         – a játék kilépett → last_seen = ended_at = most
//
// Egy kulcs = egy „lánc” (az alvás miatt több sor is lehet): a lánc mindig a legújabb, azonos key_hash-ű sor.
// Amíg a tábla nincs létrehozva, minden kérésre 503 { error:"nincs_tabla" } jön – a launcher ettől még elindítja a játékot.
//
// Telepítés: `--no-verify-jwt` kapcsolóval – a start maga ellenőrzi a tokent, a beat/stop pedig a kulccsal azonosít.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const GAMES = new Set(["birodalom", "heptarchia", "kard_es_magia", "antiquitas", "saecula"]);
const MIN_BEAT_MS = 60 * 1000;          // ennél sűrűbb jelzést nem írunk
const MAX_GAP_MS = 15 * 60 * 1000;      // ennél nagyobb szünet = alvás: új munkamenet
const MAX_START_PER_HOUR = 30;          // fiókonként óránként legfeljebb ennyi indítás

const json = (body: unknown, status = 200) =>
	new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });

function serviceKey(): string {
	const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
	if (legacy) return legacy;
	try {
		const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
		return String(keys.default ?? Object.values(keys)[0] ?? "");
	} catch { return ""; }
}

async function sha256(s: string): Promise<string> {
	const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
	return Array.from(new Uint8Array(d), (b) => b.toString(16).padStart(2, "0")).join("");
}

function randomKey(): string {
	const b = new Uint8Array(32);
	crypto.getRandomValues(b);
	return Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
}

// hiányzó tábla / függvény (a schema_jelenlet.sql még nem futott le)
const nincsTabla = (msg: string) => /jatek_munkamenet|does not exist|schema cache|42P01/i.test(msg);

type Row = { id: number; user_id: string; game: string; started_at: string; last_seen: string; ended_at: string | null;
	key_hash: string; machine: string | null };
const COLS = "id, user_id, game, started_at, last_seen, ended_at, key_hash, machine";

class DbHiba extends Error {}
function check<T>(r: { data: T; error: { message: string } | null }): T {
	if (r.error) throw new DbHiba(r.error.message);
	return r.data;
}

async function start(db: SupabaseClient, req: Request, body: Record<string, unknown>) {
	const game = String(body.game ?? "");
	if (!GAMES.has(game)) return json({ error: "bad_request" }, 400);
	const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
	if (!token) return json({ error: "not_logged_in" }, 401);
	const { data: u } = await db.auth.getUser(token);
	const user = u?.user;
	if (!user) return json({ error: "not_logged_in" }, 401);
	if (user.banned_until && new Date(user.banned_until).getTime() > Date.now()) return json({ error: "felfuggesztve" }, 403);

	const hourAgo = new Date(Date.now() - 3600 * 1000).toISOString();
	const { count, error: cErr } = await db.from("jatek_munkamenet").select("id", { count: "exact", head: true })
		.eq("user_id", user.id).gte("started_at", hourAgo);
	if (cErr) throw new DbHiba(cErr.message);
	if ((count ?? 0) >= MAX_START_PER_HOUR) return json({ error: "tul_sok" }, 429);

	const key = randomKey();
	const machine = String(body.machine ?? "").replace(/[^\p{L}\p{N} ._-]/gu, "").slice(0, 40) || null;
	const row = check(await db.from("jatek_munkamenet")
		.insert({ user_id: user.id, game, key_hash: await sha256(key), machine }).select("id").single()) as { id: number };
	return json({ sid: row.id, key });
}

// a lánc legújabb sora (ha a sid és a kulcs összetartozik)
async function lanc(db: SupabaseClient, body: Record<string, unknown>): Promise<Row | null> {
	const sid = Number(body.sid);
	const key = String(body.key ?? "");
	if (!Number.isSafeInteger(sid) || sid <= 0 || !/^[0-9a-f]{64}$/.test(key)) return null;
	const hash = await sha256(key);
	const sajat = check(await db.from("jatek_munkamenet").select("id").eq("id", sid).eq("key_hash", hash).maybeSingle());
	if (!sajat) return null;
	return check(await db.from("jatek_munkamenet").select(COLS).eq("key_hash", hash)
		.order("id", { ascending: false }).limit(1).maybeSingle()) as Row | null;
}

async function beat(db: SupabaseClient, body: Record<string, unknown>) {
	const r = await lanc(db, body);
	if (!r) return json({ error: "ismeretlen" }, 404);
	if (r.ended_at) return json({ ok: false, error: "lezarva", sid: r.id });
	const now = Date.now();
	const gap = now - new Date(r.last_seen).getTime();
	if (gap < MIN_BEAT_MS) return json({ ok: true, sid: r.id, skipped: true });
	if (gap <= MAX_GAP_MS) {
		check(await db.from("jatek_munkamenet").update({ last_seen: new Date(now).toISOString() }).eq("id", r.id).is("ended_at", null));
		return json({ ok: true, sid: r.id });
	}
	// alvás / hibernálás: a régi munkamenet a legutolsó jelzésnél véget ért, újat nyitunk ugyanazzal a kulccsal
	check(await db.from("jatek_munkamenet").update({ ended_at: r.last_seen }).eq("id", r.id).is("ended_at", null));
	const uj = check(await db.from("jatek_munkamenet")
		.insert({ user_id: r.user_id, game: r.game, key_hash: r.key_hash, machine: r.machine }).select("id").single()) as { id: number };
	return json({ ok: true, sid: uj.id, new_session: true });
}

async function stop(db: SupabaseClient, body: Record<string, unknown>) {
	const r = await lanc(db, body);
	if (!r) return json({ error: "ismeretlen" }, 404);
	if (r.ended_at) return json({ ok: true, sid: r.id });
	// ha a játék alvás közben ért véget, a szünet nem számít játékidőnek
	const now = Date.now();
	const gap = now - new Date(r.last_seen).getTime();
	const veg = gap <= MAX_GAP_MS ? new Date(now).toISOString() : r.last_seen;
	check(await db.from("jatek_munkamenet").update({ last_seen: veg, ended_at: veg }).eq("id", r.id).is("ended_at", null));
	return json({ ok: true, sid: r.id });
}

Deno.serve(async (req: Request) => {
	if (req.method !== "POST") return json({ error: "bad_method" }, 405);
	let body: Record<string, unknown>;
	try { body = await req.json(); } catch { return json({ error: "bad_request" }, 400); }
	if (!body || typeof body !== "object") return json({ error: "bad_request" }, 400);
	const db = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey(), {
		auth: { persistSession: false, autoRefreshToken: false },
	});
	try {
		switch (String(body.action ?? "")) {
			case "start": return await start(db, req, body);
			case "beat": return await beat(db, body);
			case "stop": return await stop(db, body);
		}
		return json({ error: "unknown_action" }, 400);
	} catch (e) {
		const msg = e instanceof Error ? e.message : String(e);
		if (nincsTabla(msg)) return json({ error: "nincs_tabla" }, 503);
		console.error("jelenlet hiba:", msg);
		return json({ error: "server_error" }, 500);
	}
});
