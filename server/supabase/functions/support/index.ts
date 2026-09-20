// ParthLauncher – támogatás: a weboldalról érkező üzenet mentése és továbbítása e-mailben
// (Supabase Edge Function: support)
//
// A weboldal űrlapja hívja: { "email": "...", "uzenet": "...", "targy": "Heptarchia", "hova": "weboldal" }
// Az üzenet bekerül a support_uzenet táblába, és e-mailben is megérkezik a fejlesztőnek.
//
// Beállítás:
//   • „Verify JWT” KIKAPCSOLVA (bárki írhat, belépés nélkül is)
//   • Secrets: GMAIL_USER (pl. parthenon841@gmail.com), GMAIL_APP_PASSWORD (Google alkalmazásjelszó),
//     SUPPORT_TO (ide érkezzen a levél; ha nincs, akkor a GMAIL_USER címére megy)

import { createClient } from "npm:@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

function serviceKey(): string {
	const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
	if (legacy) return legacy;
	try {
		const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
		return String(keys.default ?? Object.values(keys)[0] ?? "");
	} catch { return ""; }
}

const CORS = {
	"Access-Control-Allow-Origin": "*",
	"Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
	"Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
	new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
	if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
	if (req.method !== "POST") return json({ error: "bad_method" }, 405);

	let body: { email?: string; uzenet?: string; targy?: string; hova?: string; nev?: string };
	try { body = await req.json(); } catch { return json({ error: "bad_request" }, 400); }

	const email = String(body.email ?? "").trim().slice(0, 200);
	const uzenet = String(body.uzenet ?? "").trim().slice(0, 4000);
	const targy = String(body.targy ?? "Általános").slice(0, 80);
	const nev = String(body.nev ?? "").trim().slice(0, 120);
	const hova = String(body.hova ?? "weboldal").slice(0, 40);
	if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "rossz_email" }, 400);
	if (uzenet.length < 10) return json({ error: "rovid_uzenet" }, 400);

	const db = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey());

	// egyszerű védelem: ugyanarról a címről 5 percen belül legfeljebb 3 üzenet
	const ota = new Date(Date.now() - 5 * 60 * 1000).toISOString();
	const { count } = await db.from("support_uzenet").select("id", { count: "exact", head: true })
		.eq("email", email).gt("created_at", ota);
	if ((count ?? 0) >= 3) return json({ error: "tul_sok" }, 429);

	const { error } = await db.from("support_uzenet").insert({ email, nev, targy, uzenet, hova });
	if (error) return json({ error: "db_error" }, 500);

	// továbbítás e-mailben (ha nincs beállítva a levelezés, az üzenet akkor is megmarad a táblában)
	const user = Deno.env.get("GMAIL_USER") ?? "";
	const pass = Deno.env.get("GMAIL_APP_PASSWORD") ?? "";
	const to = Deno.env.get("SUPPORT_TO") || user;
	if (user && pass && to) {
		try {
			const client = new SMTPClient({
				connection: { hostname: "smtp.gmail.com", port: 465, tls: true, auth: { username: user, password: pass } },
			});
			await client.send({
				from: "ParthLauncher <" + user + ">",
				to,
				replyTo: email,
				subject: "[ParthLauncher] " + targy + " – " + (nev || email),
				content: "Feladó: " + (nev || "(nincs név)") + " <" + email + ">\n" + "Honnan: " + hova + "\n" + "Tárgy: " + targy + "\n\n" + uzenet + "\n",
			});
			await client.close();
		} catch (e) {
			// a levél nem ment el, de az üzenet a táblában megvan
			console.error("mail hiba:", e);
			return json({ ok: true, mail: false });
		}
	}
	return json({ ok: true, mail: Boolean(user && pass) });
});
