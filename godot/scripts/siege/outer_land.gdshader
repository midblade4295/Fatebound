shader_type spatial;
// The land beyond the playfield (0.19.4): the terrain's grass (same texture, tint and saturation),
// its painted sweeping bands read from the mask's edge and faded to neutral over the first 12 m so
// the seam doesn't show, rock on steep or high ground, snow on the peaks. No paths out here.
render_mode specular_disabled;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D path_mask : filter_linear, repeat_disable;
uniform vec4 mask_rect;
uniform float grass_scale = 16.0;
uniform float rock_scale = 4.0;
uniform vec3 tint = vec3(1.0);
uniform float grass_sat = 1.0;
uniform float band_strength = 1.0;
// 0.31.14 (Kevin: "make the grass blend better in certain spots"): the field's look carried over, so the seam between
// the baked terrain and this land doesn't show as a straight edge -- the same drifting cloud shadows, the same rock
// (triplanar, tinted, macro-jittered, mossy on top), and the meadow variation only from 10 m out.
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform float cloud_strength = 0.0;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 rock_col = vec3(0.78, 0.80, 0.78);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 rmin = mask_rect.xy;
	vec2 q = clamp(wpos.xz, rmin, rmin + mask_rect.zw);
	float d = length(wpos.xz - q);
	float band = mix(texture(path_mask, (q - rmin) / mask_rect.zw).a, 0.5, smoothstep(0.0, 12.0, d));
	vec3 g = texture(grass_tex, wpos.xz / grass_scale).rgb;
	g *= mix(vec3(1.0) - band_strength * vec3(0.18, 0.14, 0.14), vec3(1.0) + band_strength * vec3(0.08, 0.07, 0.02), band);
	g *= mix(1.0, 0.94 + 0.06 * sin(wpos.x * 0.013 + wpos.z * 0.011), smoothstep(4.0, 14.0, d));   // broad meadow variation
	float gl = dot(g, vec3(0.299, 0.587, 0.114));
	g = mix(vec3(gl), g, grass_sat);
	vec3 col = g;
	float mn = texture(macro_tex, wpos.xz / 38.0).r;
	float steep = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	float jit = (mn - 0.5) * 0.24 + (g.g - 0.55) * 0.35;
	float rockw = clamp(smoothstep(0.30, 0.52, steep + jit) + 0.85 * smoothstep(20.0, 32.0, wpos.y + jit * 8.0), 0.0, 1.0);
	if (rockw > 0.001) {
		vec3 an = pow(abs(wnorm), vec3(4.0));
		an /= (an.x + an.y + an.z);
		vec3 r = texture(rock_tex, vec2(wpos.z, -wpos.y) / rock_scale).rgb * an.x
			+ texture(rock_tex, wpos.xz / rock_scale).rgb * an.y
			+ texture(rock_tex, vec2(wpos.x, -wpos.y) / rock_scale).rgb * an.z;
		r *= rock_col * (0.9 + 0.1 * sin(wpos.y * 2.4 + mn * 7.0));
		float moss = smoothstep(0.6, 0.9, wnorm.y) * smoothstep(0.42, 0.62, mn + (g.g - 0.55));
		r = mix(r, g * 0.9, moss * 0.65);
		col = mix(col, r, rockw);
	}
	float snow = smoothstep(38.0, 46.0, wpos.y + 3.0 * sin(wpos.x * 0.2)) * (1.0 - smoothstep(0.55, 0.8, steep));
	col = mix(col, vec3(0.93, 0.95, 0.98), snow);
	float cl = smoothstep(0.46, 0.74, texture(cloud_tex, wpos.xz / 95.0 + vec2(TIME * 0.006, TIME * 0.0035)).r);
	ALBEDO = col * tint * (1.0 - cloud_strength * cl);
	ROUGHNESS = mix(0.95, 0.88, rockw);
}
