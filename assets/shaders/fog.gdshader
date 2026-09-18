shader_type canvas_item;

// Köd. A ködkép cellafelbontású (32 px), ezért NEM éles küszöbökkel
// dolgozunk: lineáris szűréssel és lágy átmenettel a köd széle nem
// kockás lépcső lesz, hanem puha, gomolygó perem — ahogy egy felderítet-
// len terület széle kinéz.
//
//   fog.r = már felderített terület
//   fog.g = éppen látható terület

uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec4 unseen  : source_color = vec4(0.02, 0.02, 0.04, 1.0);
uniform vec4 explored: source_color = vec4(0.02, 0.03, 0.09, 0.62);
uniform float softness = 0.35;

void fragment() {
	vec4 fog = texture(fog_tex, UV);
	// A látható terület felé fokozatosan tisztul.
	float vis = smoothstep(0.5 - softness, 0.5 + softness, fog.g);
	float exp = smoothstep(0.5 - softness, 0.5 + softness, fog.r);
	// felderítetlen -> felderített (félhomály) -> látható (tiszta)
	vec4 c = mix(unseen, explored, exp);
	COLOR = mix(c, vec4(0.0), vis);
}
