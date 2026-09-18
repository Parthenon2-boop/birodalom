shader_type canvas_item;

// A szárazföld egyetlen, a világot lefedő sprite-on jelenik meg.
//   land_mask.r = szárazföld/víz
//   land_mask.g = távolság a parttól befelé (0 = partvonal)
//   land_mask.a = BIOM (0 = dús rét, 0.5 = száraz puszta, 1 = felföld)
// A csempézett fűminta mellé ebből rajzoljuk a homokos partot és a tájak
// eltérő talaját. A maszkot enyhén elhangolt koordinátán olvassuk, hogy a
// partvonal ne a cellarács kockás lépcsője legyen, hanem szabálytalan él.

uniform sampler2D land_mask : filter_linear, repeat_disable;
uniform sampler2D grass_tex : filter_nearest, repeat_enable;
uniform vec2 world_size = vec2(3400.0, 2400.0);
uniform float tile_px = 192.0;
uniform vec4 sand_color : source_color = vec4(0.84, 0.76, 0.54, 1.0);
uniform vec4 sand_wet   : source_color = vec4(0.66, 0.58, 0.41, 1.0);
uniform float edge_jitter = 10.0;   // ennyi képpontnyit hullámzik a part

// A három táj szorzószíne a fűcsempére. A rét marad, ahogy van; a puszta
// megsárgul és kifakul, a felföld hűvös szürkésbarna lesz.
uniform vec3 biome_meadow = vec3(0.92, 1.06, 0.88);
uniform vec3 biome_dry    = vec3(1.30, 1.08, 0.52);
uniform vec3 biome_rock   = vec3(0.66, 0.70, 0.66);

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			   mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// A ZAJ NEM SZÁMÍTOTT, HANEM KIOLVASOTT.
//
// A vnoise() négy szinuszt és ugyanannyi törtrész-számítást jelent, és
// képpontonként nyolcszor kellett. Egy gyenge, integrált videokártyán
// ettől esett húsz kép/mp alá a játék. Ugyanaz a minta egy kis, ismétlődő
// textúrából EGY olvasással megvan.
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float noise_px = 256.0;
// 0 = alacsony (csak fű + part), 1 = közepes, 2 = magas
uniform int detail = 1;

float n(vec2 p) {
	return texture(noise_tex, p / noise_px).r;
}

void fragment() {
	vec2 p = UV * world_size;
	vec2 uv2 = UV;
	// A part szabálytalanná tétele. EZ A LEGDRÁGÁBB MŰVELET a shaderben:
	// nem a zaj kiolvasása miatt, hanem mert a maszkot ezután SZÁMÍTOTT
	// koordinátán kell olvasni. A régi, integrált videokártyák ilyenkor
	// nem tudnak előre olvasni, és a képidő a duplájára ugrik (mérve:
	// 14 ms -> 34 ms). Ezért csak MAGAS fokozaton kapcsoljuk be; alatta a
	// partvonalat a maszk lineáris szűrése és a homoksáv lágyítja.
	if (detail > 1) {
		vec2 j = vec2(n(p * 0.035), n(p * 0.035 + 41.0)) - 0.5;
		j += (vec2(n(p * 0.11), n(p * 0.11 + 17.0)) - 0.5) * 0.5;
		uv2 = UV + j * edge_jitter / world_size;
	}

	vec4 m = texture(land_mask, uv2);
	if (m.r < 0.5) {
		COLOR = vec4(0.0);
	} else {
		vec4 grass = texture(grass_tex, UV * world_size / tile_px);

		// EGY zajolvasás szolgál két célt: a tájhatár hullámoztatását és a
		// nagy léptékű fény-árnyékot. Két külön olvasás alig látszana
		// jobban, viszont kétszer annyiba kerül.
		float big = (detail > 0) ? n(p * 0.012) : 0.5;

		// --- Táj (biom) ---
		float b = clamp(m.a + (big - 0.5) * 0.10, 0.0, 1.0);
		vec3 tint = mix(biome_meadow, biome_dry, smoothstep(0.28, 0.50, b));
		tint = mix(tint, biome_rock, smoothstep(0.56, 0.80, b));
		grass.rgb *= tint * (0.94 + 0.12 * big);

		if (detail > 1) {
			// A pusztán kopár, világosabb foltok ütnek át; a felföldön
			// sötét kőmorzsalék pettyezi a talajt.
			float dryw = smoothstep(0.36, 0.60, b) * (1.0 - smoothstep(0.66, 0.86, b));
			float patch = smoothstep(0.62, 0.90, n(p * 0.055));
			grass.rgb = mix(grass.rgb, grass.rgb * vec3(1.18, 1.12, 0.92),
				patch * dryw * 0.85);
			float rockw = smoothstep(0.62, 0.86, b);
			float grit = smoothstep(0.70, 0.95, n(p * 0.42));
			grass.rgb = mix(grass.rgb, grass.rgb * vec3(0.70, 0.72, 0.74),
				grit * rockw * 0.9);
		}

		// A parti sáv csak ott számít, ahol tényleg part van — beljebb a
		// homok úgysem látszik, ott a homokszemcse is fölösleges munka.
		float shore = smoothstep(0.20, 0.70, m.g);
		if (shore >= 0.999) {
			COLOR = grass;
		} else {
			vec4 sand = mix(sand_wet, sand_color, smoothstep(0.0, 0.40, m.g));
			if (detail > 1) sand.rgb *= 0.94 + 0.12 * n(p * 0.9);
			COLOR = mix(sand, grass, shore);
		}
	}
}
