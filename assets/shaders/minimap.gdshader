shader_type canvas_item;

// A kistérkép alapja: a szárazföld-maszk (Terrain) és a ködkép (FogOfWar).
// Mindkettő cellafelbontású kis textúra, ezért egyetlen rajzparancsból
// kijön a teljes terep — nem kell több ezer téglalapot rajzolni.

uniform sampler2D land_mask : filter_nearest, repeat_disable;
uniform sampler2D fog_tex   : filter_nearest, repeat_disable;
uniform vec4 land_color  : source_color = vec4(0.30, 0.48, 0.22, 1.0);
uniform vec4 water_color : source_color = vec4(0.12, 0.26, 0.46, 1.0);
uniform vec4 dark_color  : source_color = vec4(0.04, 0.04, 0.06, 1.0);
uniform bool use_fog = true;

void fragment() {
	float land = texture(land_mask, UV).r;
	vec4 c = mix(water_color, land_color, step(0.5, land));
	if (use_fog) {
		vec4 f = texture(fog_tex, UV);
		if (f.g > 0.5) {
			// éppen látható terület: teljes fényben
		} else if (f.r > 0.5) {
			c = mix(c, dark_color, 0.45);   // felderített, de most nem látszik
		} else {
			c = mix(c, dark_color, 0.88);   // felderítetlen: alig sejlik át
		}
	}
	COLOR = c;
}
