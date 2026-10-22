shader_type spatial;
// The spell effects' shells (spell_fx.gd): a shield's bubble, a dome, a stone or bark skin, the fury's halo -- a sphere
// round a hero, a rim of light where it faces away (fresnel), bands of noise drifting over it, a pulse. style: 0 glass
// (a clear bubble, bright rim); 1 crust (a solid, slowly crawling skin -- stone, bark); 2 energy (boiling, bright);
// 3 dome (a thin rim, dim face, for a big ground dome).
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform int style = 0;
uniform float energy = 1.0;
uniform float fade = 1.0;
uniform float speed = 1.0;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.5);
	float n = noise(UV * vec2(6.0, 3.0) + vec2(TIME * 0.3 * speed, -TIME * 0.7 * speed)) * 0.6 + noise(UV * vec2(13.0, 7.0) - TIME * 0.5 * speed) * 0.4;
	float a = 0.0;
	vec3 col = color.rgb;
	if (style == 0) {
		a = fres * 1.1 + 0.07 + smoothstep(0.6, 0.9, n) * 0.18;
	} else if (style == 1) {
		a = 0.35 + smoothstep(0.3, 0.8, n) * 0.5 + fres * 0.5;
		col = mix(col * 0.6, col, smoothstep(0.3, 0.8, n));
	} else if (style == 2) {
		a = fres * 0.9 + smoothstep(0.45, 0.85, n) * 0.7 + 0.1;
		col = mix(col, vec3(1.0), smoothstep(0.75, 1.0, n) * 0.5);
	} else {
		a = fres * 1.3 + 0.03 + smoothstep(0.7, 0.95, n) * 0.12;
	}
	a *= 0.9 + 0.1 * sin(TIME * 4.0 * speed);
	ALBEDO = col * energy;
	ALPHA = clamp(a * fade * color.a, 0.0, 1.0);
}
