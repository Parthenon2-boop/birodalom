shader_type canvas_item;

// A víz egyetlen, a teljes világot lefedő sprite-on fut. Az UV így 0..1
// a térképen — a mintát ezért világkoordinátákra váltjuk, különben a
// hullámok kilométeresre nyúlnak.
//
// A `land_mask.b` megmondja, milyen MÉLY a víz (0 = part, 1 = nyílt).
// Ettől lesz türkiz zátony a partnál és sötétkék a mély víz, a parton
// pedig mozgó habcsík — enélkül a tenger egyenletes kék folt.

uniform float time_scale = 0.4;
uniform vec4 water_deep    : source_color = vec4(0.05, 0.18, 0.42, 1.0);
uniform vec4 water_mid     : source_color = vec4(0.13, 0.38, 0.66, 1.0);
uniform vec4 water_shallow : source_color = vec4(0.32, 0.66, 0.74, 1.0);
uniform vec4 foam_color    : source_color = vec4(0.92, 0.97, 1.0,  1.0);
uniform vec2 world_size = vec2(3400.0, 2400.0);
uniform sampler2D land_mask : filter_linear, repeat_disable;
uniform bool use_mask = false;

// A zaj kis, ismétlődő textúrából jön, nem szinuszokból — lásd a
// land.gdshader magyarázatát.
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float noise_px = 256.0;
// 0 = alacsony (két hullám, nincs habcsík-zaj), 1-2 = teljes
uniform int detail = 1;

float n(vec2 p) {
	return texture(noise_tex, p / noise_px).r;
}

float waves(vec2 p, float t) {
	float w = sin(p.x * 0.055 + t * 1.10) * 0.50
			+ sin(p.y * 0.043 - t * 0.80) * 0.35;
	if (detail > 0) {
		w += sin((p.x + p.y) * 0.031 + t * 0.60) * 0.30
		   + sin((p.x * 1.3 - p.y * 0.7) * 0.088 - t * 1.40) * 0.18;
	}
	return w;
}

void fragment() {
	vec2 p = UV * world_size;
	// A víz a TELJES világot lefedi, a szárazföld csak rárajzolódik. A
	// szárazföld alatti képpontokra semmi értelme kiszámolni a hullámokat
	// és a habcsíkot — a képernyő nagyobbik fele ilyen. Egyetlen korai
	// kiolvasás dönti el. (A shaderben nincs `return`, ezért elágazás.)
	float land = use_mask ? texture(land_mask, UV).r : 0.0;
	if (land > 0.9) {
		COLOR = water_deep;
	} else {
		float t = TIME * time_scale;
		float w = waves(p, t);

		// Mélység: a maszkból, ha van; enélkül nagy léptékű zajfoltokból.
		float depth = 0.5 + 0.5 * sin(p.x * 0.0042 + p.y * 0.0055);
		float shore = 1.0;
		if (use_mask) {
			// Ugyanaz, mint a talajnál: a számított koordinátájú maszk-
			// olvasás a drága, ezért csak magas fokozaton hullámoztatjuk
			// a partot.
			vec2 j = vec2(0.0);
			if (detail > 1) {
				j = (vec2(n(p * 0.035), n(p * 0.035 + 41.0)) - 0.5) * 13.0;
			}
			vec4 m = texture(land_mask, UV + j / world_size);
			depth = m.b;
			shore = m.b;                   // 0 a parton, 1 a nyílt vízen
		}
		// Sekély türkiz -> közép -> mély kék
		vec4 base = mix(water_shallow, water_mid, smoothstep(0.0, 0.55, depth));
		base = mix(base, water_deep, smoothstep(0.5, 1.0, depth));
		base.rgb *= 0.97 + 0.06 * w;       // enyhe hullámárnyék

		// Parti habcsík: KESKENY sáv a víz szélén.
		float surf = (1.0 - smoothstep(0.0, 0.28, shore))
			* smoothstep(0.25, 0.85,
				0.5 + 0.5 * sin(shore * 26.0 - t * 2.4 + w * 2.0));
		base = mix(base, foam_color, surf * 0.45);

		// Csillanás a hullámhegyeken.
		float crest = smoothstep(0.94, 1.22, w);
		COLOR = mix(base, foam_color, crest * 0.35);
	}
}
