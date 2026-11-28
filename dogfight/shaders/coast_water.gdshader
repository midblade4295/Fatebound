// The sea off the chalk coast: turquoise in the shallows under the cliffs,
// deepening to blue offshore, with drifting ripples, glints, and white foam
// where it meets the land.
//
// The usual way to get depth and a shoreline is to read the depth buffer,
// which makes the whole sea a transparent surface: expensive on a phone.
// Here the sea knows its own depth instead. ArenaBuilder builds the sea
// mesh along the coast and stores at every vertex (COLOR):
//   r  how deep the water is there, as a share of `deepest`
//   g  how far it is from the foot of the cliffs, as a share of `shore_reach`
// So the surface stays opaque and reads no screen or depth textures.
shader_type spatial;
render_mode cull_back;

uniform vec4 shallow_color : source_color = vec4(0.20, 0.84, 0.80, 1.0);
uniform vec4 mid_color : source_color = vec4(0.06, 0.55, 0.88, 1.0);
uniform vec4 deep_color : source_color = vec4(0.03, 0.27, 0.68, 1.0);
uniform vec4 sparkle_color : source_color = vec4(0.85, 0.97, 1.0, 1.0);
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.55, 0.82, 1.0, 1.0);
// What the vertex colours are shares of, metres.
uniform float deepest = 70.0;
uniform float shore_reach = 200.0;
uniform float pattern_scale = 0.006;
uniform float scroll_speed = 0.035;
uniform float sparkle_threshold : hint_range(0.0, 1.0) = 0.69;
uniform float fade_start = 600.0;
uniform float fade_end = 3200.0;
// Foam: solid within this of the cliffs, and in lines rolling in from this far out.
uniform float foam_edge = 9.0;
uniform float foam_reach = 95.0;

varying vec3 world_pos;
varying float depth_share;
varying float shore_share;

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
	depth_share = COLOR.r;
	shore_share = COLOR.g;
}

void fragment() {
	vec2 uv = world_pos.xz * pattern_scale;
	float t = TIME * scroll_speed;
	float broad = value_noise(uv * 0.35 + vec2(t, t * 0.6));
	float fine = value_noise(uv * 2.3 + vec2(-t * 2.0, t * 1.4));
	float streak = value_noise(vec2(uv.x * 5.0 + t * 3.0, uv.y * 1.6 - t));
	float detail = 1.0 - smoothstep(fade_start, fade_end, length(VERTEX));

	// Colour by depth: the pale sea bed shows through the shallows.
	vec3 water = mix(shallow_color.rgb, mid_color.rgb, smoothstep(0.07, 0.30, depth_share));
	water = mix(water, deep_color.rgb, smoothstep(0.28, 0.95, depth_share));
	water = mix(water, water * 1.18 + vec3(0.02), (broad * 0.7 + fine * 0.3 * detail) * 0.55);
	float sparkle = smoothstep(sparkle_threshold, sparkle_threshold + 0.04, fine * 0.6 + streak * 0.4) * detail;
	water = mix(water, sparkle_color.rgb, sparkle * 0.5);

	// Foam: a ragged white band at the foot of the cliffs, and lines of it
	// rolling in, breaking up as they come.
	float from_shore = shore_share * shore_reach;
	float churn = value_noise(world_pos.xz * 0.11 + vec2(t * 6.0, -t * 4.0));
	float band = 1.0 - smoothstep(foam_edge * (0.5 + churn), foam_edge * (1.1 + churn), from_shore);
	float swell = sin(from_shore * 0.21 + TIME * 0.9 + churn * 3.0);
	float lines = smoothstep(0.82, 0.96, swell) * (1.0 - smoothstep(foam_reach * 0.3, foam_reach, from_shore)) * smoothstep(0.35, 0.6, churn + fine * 0.3);
	float foam = max(band, lines * 0.85) * step(0.0005, shore_share + depth_share);
	water = mix(water, foam_color.rgb, foam);

	// Grazing angles pick up the sky: blends the far water into the horizon.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(water, horizon_color.rgb, fresnel * 0.65 * (1.0 - foam));
	ROUGHNESS = mix(0.55, 0.9, foam);
	SPECULAR = 0.3;
	METALLIC = 0.0;
}
