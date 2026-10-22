shader_type spatial;
// The spell effects' pillars, beams, cones and sheets (spell_fx.gd): a mesh whose UV.y runs along the effect (0 at its
// root, 1 at its far end) and UV.x across it, drawn in the spell's colour, added. Noise scrolls along it (speed) so a
// pillar of light boils upward and a cone of wind rushes out; it fades at its ends (fade_root, fade_end) and, with
// side_fade, at its sides (a flat sheet; off for a cylinder, whose UV.x wraps). grow (0..1) lights it up from the root;
// fade is the caster's hand on its brightness.
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform float energy = 1.0;
uniform float fade = 1.0;
uniform float grow = 1.0;
uniform float speed = 2.0;
uniform float scale = 3.0;
uniform float fade_root = 0.15;
uniform float fade_end = 0.4;
uniform bool side_fade = true;
uniform float core = 0.4;
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
	float y = UV.y;
	float x = UV.x;
	float n = noise(vec2(x * scale * 2.0, y * scale - TIME * speed)) * 0.6 + noise(vec2(x * scale * 4.0 + 3.0, y * scale * 2.0 - TIME * speed * 1.7)) * 0.4;
	float a = smoothstep(0.3, 0.9, n) * 0.7 + 0.05;
	a *= smoothstep(0.0, fade_root, y) * (1.0 - smoothstep(1.0 - fade_end, 1.0, y));
	if (side_fade) {
		float s = abs(x - 0.5) * 2.0;
		a *= 1.0 - smoothstep(0.55, 1.0, s);
		a += core * (1.0 - smoothstep(0.0, 0.35, s)) * smoothstep(0.0, fade_root, y) * (1.0 - smoothstep(1.0 - fade_end, 1.0, y));
	} else {
		a += core * 0.3 * smoothstep(0.0, fade_root, y) * (1.0 - smoothstep(1.0 - fade_end, 1.0, y));
	}
	a *= 1.0 - smoothstep(grow - 0.05, grow + 0.02, y);
	vec3 col = mix(color.rgb, vec3(1.0), smoothstep(0.8, 1.0, n) * 0.3);
	ALBEDO = col * energy;
	ALPHA = clamp(a * fade * color.a, 0.0, 1.0);
}
