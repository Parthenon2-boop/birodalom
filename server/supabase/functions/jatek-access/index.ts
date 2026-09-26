// ParthLauncher – fejlesztés alatt álló, TITKOS játékok (Supabase Edge Function: jatek-access)
//
// Az Antiquitas és a Saecula még nem nyilvános: a kiadásaik PRIVÁT GitHub-tárolóban vannak, és csak
// admin fiók láthatja / töltheti le őket. A launcher ezzel kérdezi meg, mely titkos játékok érhetők el,
// és ettől kap néhány percig érvényes letöltési linket.
//
// Kérés (POST, a fiók tokenjével):  { "game"?: "antiquitas" }
// Válasz:
//   games: { kulcs: címke } – a fiók számára elérhető titkos játékok legújabb kiadása ("" ha még nincs kiadás)
//   url, tag, size: ha "game" meg volt adva és van kiadás: a <Név>-windows.zip letöltési linkje
// Nem adminnak: { games: {} } (200) – a launcher ilyenkor egyszerűen nem mutatja őket; nem árulunk el semmit.
//
// Titkok: GITHUB_TOKEN (ugyanaz, mint a dlc-access-nél; a tokennek olvasnia kell az antiquitas és a saecula
// tárolót is – Contents: Read-only). Verify JWT: BEKAPCSOLVA.

import { createClient } from "npm:@supabase/supabase-js@2";

const OWNER = "Parthenon2-boop";
// kulcs → tároló és a Windows-csomag neve
const GAMES: Record<string, { repo: string; asset: string }> = {
	antiquitas: { repo: "antiquitas", asset: "Antiquitas-windows.zip" },
	saecula: { repo: "saecula", asset: "Saecula-windows.zip" },
};

const json = (body: unknown, status = 200) =>
	new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

function serviceKey(): string {
	const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
	if (legacy) return legacy;
	try {
		const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
		return String(keys.default ?? Object.values(keys)[0] ?? "");
	} catch { return ""; }
}

const gh = (repo: string, path: string, extra: Record<string, string> = {}) =>
	fetch(`https://api.github.com/repos/${OWNER}/${repo}${path}`, {
		headers: { Authorization: `Bearer ${Deno.env.get("GITHUB_TOKEN") ?? ""}`, "User-Agent": "parthlauncher",
			"X-GitHub-Api-Version": "2022-11-28", ...extra },
		redirect: "manual",
	});

// a legújabb (nem vázlat) kiadás, amelyben a Windows-csomag benne van
async function legujabb(key: string): Promise<{ tag: string; asset: number; size: number } | null> {
	const g = GAMES[key];
	const res = await gh(g.repo, "/releases?per_page=20", { Accept: "application/vnd.github+json" });
	if (!res.ok) return null;
	for (const r of await res.json()) {
		if (r.draft) continue;
		for (const a of r.assets ?? []) {
			if (String(a.name) === g.asset) return { tag: String(r.tag_name), asset: Number(a.id), size: Number(a.size) };
		}
	}
	return null;
}

Deno.serve(async (req: Request) => {
	const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
	const db = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey(), {
		auth: { persistSession: false, autoRefreshToken: false },
	});
	const { data: u } = await db.auth.getUser(token);
	const user = u?.user;
	if (!user) return json({ error: "not_logged_in" }, 401);
	if (user.banned_until && new Date(user.banned_until).getTime() > Date.now()) return json({ error: "felfuggesztve" }, 403);

	// csak admin: mindenki másnak üres lista
	const { data: adm } = await db.from("admins").select("user_id").eq("user_id", user.id).maybeSingle();
	if (!adm) return json({ games: {} });

	let body: { game?: string } = {};
	try { body = await req.json(); } catch { /* üres kérés: csak a lista */ }

	const keys = Object.keys(GAMES);
	const rel = await Promise.all(keys.map((k) => legujabb(k)));
	const games: Record<string, string> = {};
	keys.forEach((k, i) => games[k] = rel[i]?.tag ?? "");
	const resp: Record<string, unknown> = { games };

	const game = String(body.game ?? "");
	if (game !== "") {
		const i = keys.indexOf(game);
		if (i < 0) return json({ error: "bad_request" }, 400);
		const r = rel[i];
		if (!r) return json({ error: "no_release" }, 404);
		// a GitHub egy néhány percig érvényes, aláírt címre irányít át: azt adjuk tovább
		const a = await gh(GAMES[game].repo, `/releases/assets/${r.asset}`, { Accept: "application/octet-stream" });
		const loc = a.headers.get("location");
		if (!loc) return json({ error: "github_error", status: a.status }, 502);
		resp.url = loc;
		resp.tag = r.tag;
		resp.size = r.size;
	}
	return json(resp);
});
