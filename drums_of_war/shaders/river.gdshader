// The creek: scrolling normal-map ripples, depth colour, painted swirl lines, and white foam where
// the water runs thin: along both banks, over the fords, and around the stone bridge.
//
// The depth of water at any point is worked out from the same channel shape the ground mesh
// uses (see arena.gd height()), so no depth texture is needed and it runs on the mobile renderer.
shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_col : source_color;
uniform vec3 deep_col : source_color;
uniform vec3 sky_col : source_color;
uniform vec3 swirl_col : source_color = vec3(0.72, 0.9, 1.0);
uniform float surface;
uniform float deep;
uniform float shallow;
uniform float bridge_half = 1.7;      // half the bridge's width, in world units
varying vec3 wp;
float bed(vec2 p) {
	float ford = max(1.0 - smoothstep(1.3, 2.0, abs(p.x + 6.0)), 1.0 - smoothstep(1.3, 2.0, abs(p.x - 6.0)));
	return mix(deep, shallow, ford) * (1.0 - smoothstep(0.55, 1.3, abs(p.y)));
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float depth = max(0.0, bed(wp.xz) + surface);
	float d01 = clamp(depth / 0.95, 0.0, 1.0);
	vec2 flow = vec2(TIME * 0.2, 0.0);
	vec3 na = texture(wave_a, wp.xz * 0.21 - flow * 0.55 + vec2(0.0, TIME * 0.025)).rgb;
	vec3 nb = texture(wave_b, wp.xz * 0.46 - flow).rgb;
	NORMAL_MAP = mix(na, nb, 0.5);
	NORMAL_MAP_DEPTH = 0.22 + 0.3 * (1.0 - d01);      // gentle; choppier over the shallows
	vec3 col = mix(shallow_col, deep_col, smoothstep(0.0, 1.0, d01));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, sky_col, fres * 0.35);
	// Painted swirls: pale curling lines carried along by the current. They are the contour
	// lines of two drifting noise fields, so they bend, join and part like brush strokes.
	float s1 = texture(foam_noise, wp.xz * vec2(0.03, 0.1) - flow * 0.09).r;
	float s2 = texture(foam_noise, wp.xz * vec2(0.055, 0.16) - flow * 0.15 + vec2(0.31, 0.63)).r;
	float line1 = 1.0 - smoothstep(0.04, 0.085, abs(fract(s1 * 5.0) - 0.5));
	float line2 = 1.0 - smoothstep(0.008, 0.02, abs(fract(s2 * 3.0) - 0.5) / 3.0);
	float swirl = clamp(line1 * 0.8 + line2 * 0.55, 0.0, 1.0) * smoothstep(0.15, 0.5, depth);
	col = mix(col, swirl_col, swirl * 0.85);
	// Foam where the water runs thin: a crisp white line along each bank, and the riffles over
	// the fords.
	float fn = texture(foam_noise, wp.xz * 0.55 - flow * 1.6).r;
	float fn2 = texture(foam_noise, wp.xz * 1.3 - flow * 2.4 + vec2(0.4, 0.2)).r;
	float edge = 1.0 - smoothstep(0.1, 0.16 + 0.12 * fn, depth);
	float riffle = (1.0 - smoothstep(0.24, 0.46, depth)) * smoothstep(0.6, 0.72, fn) * smoothstep(0.45, 0.62, fn2);
	// The bridge: a collar of foam where the current meets its stonework on the upstream face
	// and along both sides of the arch, and a broken wake trailing away downstream (+X).
	float to_pier = abs(abs(wp.x) - bridge_half);
	float collar = (1.0 - smoothstep(0.0, 0.34, to_pier)) * smoothstep(0.3, 0.58, fn + 0.22);
	float behind = wp.x - bridge_half;
	float wake = step(0.0, behind) * (1.0 - smoothstep(0.0, 3.2, behind))
			* smoothstep(0.52, 0.7, texture(foam_noise, vec2(wp.x * 0.22 - TIME * 0.5, wp.z * 1.1)).r) * 0.75;
	float in_channel = 1.0 - smoothstep(0.9, 1.25, abs(wp.z));
	float foam = clamp(edge + riffle * 0.8 + (collar + wake) * in_channel, 0.0, 1.0);
	ALBEDO = mix(col, vec3(1.0), foam);
	ALPHA = clamp(mix(0.8, 0.96, d01) + foam * 0.5, 0.0, 1.0) * smoothstep(0.0, 0.035, depth);
	ROUGHNESS = mix(0.42, 0.6, foam);
	SPECULAR = 0.3;
	METALLIC = 0.0;
}
