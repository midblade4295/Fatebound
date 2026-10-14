// 0.31.137: the sea round the war map's land, and its lake, river and pools (one sheet at sea level). Its colour
// from the depth under it (the land's height, assets/war_land/land_regions.png A), turquoise in the shallows, deep
// blue out at sea; waves from two drifting noise layers; foam breathing along the shore; cloud shadows like the land's.
shader_type spatial;
render_mode blend_mix, specular_schlick_ggx, cull_disabled;

uniform sampler2D region_lin : filter_linear;      // A = height (h_min .. h_max)
uniform sampler2D wave_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 map_rect;                               // x0, z0, width, depth of the land's square
uniform float h_min = -0.4;
uniform float h_max = 2.15;
uniform vec3 shallow : source_color = vec3(0.3, 0.72, 0.74);
uniform vec3 deep : source_color = vec3(0.06, 0.22, 0.42);
uniform vec3 far : source_color = vec3(0.05, 0.14, 0.3);
uniform vec2 wind = vec2(0.012, 0.006);
uniform mat4 to_map = mat4(1.0);                    // 0.31.138: as the land's (war_land.gdshader)
uniform vec2 disc = vec2(0.0);                     // (x and z radii)
uniform float glow = 0.0;
uniform float wave_scale = 1.0;                      // (Home's table: finer waves, a softer sheen)
uniform float spec = 0.55;
uniform float rough = 0.18;
varying vec3 world;

void vertex() {
	world = (to_map * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (disc.x > 0.0 && length(world.xz / disc) > 1.0) {
		discard;
	}
	vec2 muv = (world.xz - map_rect.xy) / map_rect.zw;
	float inside = step(0.0, muv.x) * step(0.0, muv.y) * step(muv.x, 1.0) * step(muv.y, 1.0);
	float ground = mix(h_min, texture(region_lin, clamp(muv, 0.0, 1.0)).a * (h_max - h_min) + h_min, inside);
	float depth = max(0.0, -ground);
	float t = TIME;
	vec2 p = world.xz * wave_scale;
	float w1 = texture(wave_tex, p * 0.22 + vec2(t * 0.025, t * 0.011)).r;
	float w2 = texture(wave_tex, p * 0.37 - vec2(t * 0.018, -t * 0.021)).r;
	float waves = w1 + w2;
	vec3 col = mix(shallow, deep, smoothstep(0.0, 0.11, depth));
	float off = length(max(abs(muv - 0.5) - 0.5, vec2(0.0)));
	col = mix(col, far, smoothstep(0.0, 0.25, off));
	col += vec3(0.025, 0.035, 0.04) * (waves - 1.0);
	// a glint where the waves catch the light
	col += vec3(0.5, 0.55, 0.5) * smoothstep(0.86, 0.95, w1 * w2 * 1.6) * 0.12;
	// foam: a band along the shore that breathes, broken up by the waves
	float shore = 1.0 - smoothstep(0.0, 0.07, depth);
	float breathe = 0.6 + 0.4 * sin(t * 1.6 + (w1 * 6.0));
	float foam = shore * smoothstep(0.45, 0.75, w2 * breathe + shore * 0.35) * inside;
	col = mix(col, vec3(0.94, 0.98, 1.0), foam * 0.85);
	float c = texture(cloud_tex, world.xz * 0.045 + t * wind).r;
	col *= 1.0 - 0.22 * smoothstep(0.52, 0.78, c);
	ALBEDO = col;
	EMISSION = col * glow;
	ROUGHNESS = rough;
	SPECULAR = spec;
	ALPHA = mix(0.72, 1.0, smoothstep(0.0, 0.2, depth));
	// gentle normals from the waves
	NORMAL_MAP = normalize(vec3(w1 - 0.5, w2 - 0.5, 2.5)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
}
