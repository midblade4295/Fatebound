shader_type spatial;
// Fatebound's plasma beam (0.31.50, Kevin: a plasma beam for the Necromancer's siphon). Written for this game.
// Drawn on a unit cylinder stretched between the two ends: UV.x runs round it, UV.y along it. Two twisting wave
// trains and a scrolling value noise make the plasma; bright pulses run along the beam from the victim to the
// Necromancer; the sides fade softly (view-facing), and both ends fade out.
// (blend_mix, not add: an additive beam over the sunlit field washed out to white under the HQ glow)
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 plasma_color : source_color = vec3(0.22, 0.95, 0.35);
uniform vec3 deep_color : source_color = vec3(0.26, 0.02, 0.48);
uniform vec3 hot_color : source_color = vec3(0.86, 1.0, 0.74);
uniform float flow_speed = 1.0;
uniform float flow_dir = 1.0;          // +1: the pulses run toward the UV.y = 0 end, -1: toward 1 (the siphon uses -1:
                                       // the cylinder's UV.y = 1 end sits at the Necromancer)
uniform float twist = 2.0;             // wave turns round the beam
uniform float intensity = 1.5;
uniform float softness = 1.4;          // how quickly the sides fade
uniform float core = 0.0;              // 1 = the thin bright core instead of the sheath
instance uniform float beam_len = 5.0; // metres, so the waves keep their size on any length

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	float t = TIME * flow_speed;
	float along = UV.y * beam_len;
	float around = UV.x * 6.2831853;
	float s = along * flow_dir;

	// two wave trains twisting round the beam in opposite senses, warped by each other
	float w1 = sin(s * 2.6 + t * 5.0 + around * twist);
	float w2 = sin(s * 4.3 + t * 7.5 - around * (twist + 1.0) + 1.4 * sin(s * 1.1 + t * 2.0));
	float n = vnoise(vec2(s * 1.8 + t * 4.0, UV.x * 7.0)) * 0.7 + vnoise(vec2(s * 5.0 + t * 9.0, UV.x * 15.0)) * 0.3;
	float plasma = clamp(0.5 + 0.22 * w1 + 0.22 * w2 + 0.45 * (n - 0.5), 0.0, 1.0);
	float filaments = smoothstep(0.5, 0.78, plasma);

	// pulses running down the beam
	float pulse = pow(0.5 + 0.5 * sin(s * 1.35 + t * 9.0), 8.0);

	// troughs: dark violet; crests: bright green filaments with hot cores -- contrast reads as plasma
	vec3 col = mix(deep_color, plasma_color, smoothstep(0.3, 0.62, plasma));
	col = mix(col, hot_color, smoothstep(0.7, 0.95, plasma) * 0.6 + pulse * 0.5);

	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float side_fade = pow(facing, softness);
	float ends = smoothstep(0.0, 0.05, UV.y) * smoothstep(1.0, 0.95, UV.y);
	float a = (0.5 + 0.45 * filaments + 0.3 * pulse) * side_fade * ends;

	if (core > 0.5) {
		// the core: a steady hot line with a flicker
		col = mix(plasma_color, hot_color, 0.45 + 0.35 * pulse);
		a = (0.85 + 0.15 * sin(t * 40.0 + s * 3.0)) * pow(facing, 0.6) * ends;
	}
	ALBEDO = col * intensity;
	ALPHA = clamp(a, 0.0, 1.0);
}
