// Stylized ocean: flat mesh, all motion in the fragment shader (no vertex
// waves, no depth/screen texture reads, so it stays cheap on mobile GPUs).
// Two scrolling value-noise layers pick between deep and shallow blues and
// carve bright "sparkle" streaks; the pattern fades out with distance to stop
// it shimmering near the horizon.
shader_type spatial;
render_mode cull_back;

uniform vec4 deep_color : source_color = vec4(0.03, 0.30, 0.72, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.10, 0.62, 0.92, 1.0);
uniform vec4 sparkle_color : source_color = vec4(0.85, 0.97, 1.0, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.55, 0.82, 1.0, 1.0);
uniform float pattern_scale = 0.006;
uniform float scroll_speed = 0.035;
uniform float sparkle_threshold : hint_range(0.0, 1.0) = 0.69;
uniform float fade_start = 600.0;
uniform float fade_end = 3200.0;

varying vec3 world_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * pattern_scale;
	float t = TIME * scroll_speed;
	float broad = value_noise(uv * 0.35 + vec2(t, t * 0.6));
	float fine = value_noise(uv * 2.3 + vec2(-t * 2.0, t * 1.4));
	float streak = value_noise(vec2(uv.x * 5.0 + t * 3.0, uv.y * 1.6 - t));

	float dist = length(VERTEX);
	float detail = 1.0 - smoothstep(fade_start, fade_end, dist);

	vec3 water = mix(deep_color.rgb, shallow_color.rgb, broad * 0.75 + fine * 0.25 * detail);
	float sparkle = smoothstep(sparkle_threshold, sparkle_threshold + 0.04, fine * 0.6 + streak * 0.4) * detail;
	water = mix(water, sparkle_color.rgb, sparkle * 0.55);

	// Grazing angles pick up the sky: blends the far water into the horizon.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(water, horizon_color.rgb, fresnel * 0.65);
	ROUGHNESS = 0.55;
	SPECULAR = 0.3;
	METALLIC = 0.0;
}
