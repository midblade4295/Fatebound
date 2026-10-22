shader_type spatial;
// The spell effects' ground discs (spell_fx.gd): a flat mesh over the ground, drawn in the spell's colour, added. UV runs
// 0..1 over the disc (its centre at 0.5, 0.5). style: 0 a soft disc with a bright rim; 1 a sprite (tex: runes, cracks,
// rays, a swirl) turning at spin; 2 fire -- noise flames boiling, brightest at the rim; 3 electric -- jagged arcs
// flickering across it; 4 nature -- soft dappled light with a pulsing rim; 5 a thin rim only. fade (0..1) is the
// caster's hand on its brightness; grow (0..1) how much of the radius is lit (a wave running out).
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform int style = 0;
uniform sampler2D tex : filter_linear_mipmap, repeat_disable;
uniform float fade = 1.0;
uniform float grow = 1.0;
uniform float spin = 0.0;
uniform float energy = 1.0;
uniform float rim = 0.8;
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
	vec2 c = UV - vec2(0.5);
	float r = length(c) * 2.0;
	float ang = atan(c.y, c.x);
	float edge = 1.0 - smoothstep(0.92, 1.0, r);
	float wave = 1.0 - smoothstep(grow - 0.08, grow + 0.02, r);
	float a = 0.0;
	vec3 col = color.rgb;
	if (style == 0) {
		a = 0.2 * (1.0 - r * 0.5) + rim * 0.7 * exp(-pow((r - 0.9) / 0.07, 2.0));
		a *= 0.85 + 0.15 * sin(TIME * 5.0 + r * 6.0);
	} else if (style == 1) {
		float s = TIME * spin;
		mat2 rot = mat2(vec2(cos(s), -sin(s)), vec2(sin(s), cos(s)));
		vec2 uv = rot * c + vec2(0.5);
		float l = texture(tex, uv).r;
		a = l * 0.8 * (0.9 + 0.1 * sin(TIME * 4.0)) + rim * 0.45 * exp(-pow((r - 0.9) / 0.06, 2.0));
		col = mix(col, vec3(1.0), smoothstep(0.75, 1.0, l) * 0.3);
	} else if (style == 2) {
		vec2 p = c * 7.0;
		float n = noise(p + vec2(0.0, -TIME * 2.5)) * 0.6 + noise(p * 2.3 + vec2(TIME * 1.3, -TIME * 4.0)) * 0.4;
		float flame = smoothstep(0.4, 0.95, n + r * 0.3);
		a = flame * (0.3 + 0.35 * r) + rim * 0.5 * exp(-pow((r - 0.92) / 0.08, 2.0)) * (0.7 + 0.3 * noise(vec2(ang * 3.0, TIME * 6.0)));
		col = mix(col, vec3(1.0, 0.9, 0.6), flame * flame * 0.3);
	} else if (style == 3) {
		vec2 p = vec2(ang * 2.5, r * 4.0 - TIME * 3.0);
		float n = noise(p * 2.0 + TIME * 7.0);
		float arc = smoothstep(0.62, 0.68, n) * (1.0 - smoothstep(0.72, 0.8, n));
		float flick = step(0.35, hash(vec2(floor(TIME * 18.0), floor(ang * 3.0))));
		a = arc * 1.2 * flick + 0.08 + rim * 0.6 * exp(-pow((r - 0.9) / 0.06, 2.0)) * (0.5 + 0.5 * flick);
		col = mix(col, vec3(1.0), arc * 0.5);
	} else if (style == 4) {
		float n = noise(c * 5.0 + TIME * 0.4) * 0.6 + noise(c * 11.0 - TIME * 0.6) * 0.4;
		a = smoothstep(0.35, 0.8, n) * 0.4 * (1.0 - r * 0.4) + rim * 0.7 * exp(-pow((r - 0.9) / 0.07, 2.0)) * (0.8 + 0.2 * sin(TIME * 3.0));
	} else {
		a = rim * exp(-pow((r - 0.9) / 0.05, 2.0)) + 0.03;
	}
	ALBEDO = col * energy;
	ALPHA = clamp(a * edge * wave * fade * color.a, 0.0, 1.0);
}
