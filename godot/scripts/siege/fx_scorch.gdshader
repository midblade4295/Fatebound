shader_type spatial;
// The dark under a spell's ground (spell_fx.gd disc, o.scorch): scorched earth under fire, shadow under a curse -- a
// soft dark disc mixed (not added) over the ground, so the light over it has something to stand out from.
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.05, 0.02, 0.0, 1.0);
uniform float fade = 1.0;
uniform float grow = 1.0;
uniform float strength = 0.5;
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
	float n = noise(c * 6.0) * 0.5 + noise(c * 13.0) * 0.5;
	float a = (1.0 - smoothstep(0.45, 1.0, r + (n - 0.5) * 0.3)) * strength;
	a *= 1.0 - smoothstep(grow - 0.08, grow + 0.02, r);
	ALBEDO = color.rgb;
	ALPHA = clamp(a * fade * color.a, 0.0, 1.0);
}
