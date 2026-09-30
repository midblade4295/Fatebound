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
	g *= 0.94 + 0.06 * sin(wpos.x * 0.013 + wpos.z * 0.011);        // broad meadow variation
	float gl = dot(g, vec3(0.299, 0.587, 0.114));
	vec3 col = mix(vec3(gl), g, grass_sat);
	float steep = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	float rockw = clamp(smoothstep(0.30, 0.55, steep) + 0.85 * smoothstep(20.0, 32.0, wpos.y), 0.0, 1.0);
	if (rockw > 0.001) {
		vec2 ruv = abs(wnorm.x) > abs(wnorm.z) ? vec2(wpos.z, -wpos.y) : vec2(wpos.x, -wpos.y);
		vec3 rk = steep > 0.3 ? texture(rock_tex, ruv / rock_scale).rgb : texture(rock_tex, wpos.xz / rock_scale).rgb;
		col = mix(col, rk, rockw);
	}
	float snow = smoothstep(38.0, 46.0, wpos.y + 3.0 * sin(wpos.x * 0.2)) * (1.0 - smoothstep(0.55, 0.8, steep));
	col = mix(col, vec3(0.93, 0.95, 0.98), snow);
	ALBEDO = col * tint;
	ROUGHNESS = 0.95;
}
