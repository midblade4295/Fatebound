shader_type spatial;
// Fatebound terrain (Round 7): lush grass, herringbone brick paths from the baked mask, rock on
// steep faces and ledge rims. Optimised in 0.14.2 (Kevin: fps dropped): a plain grass pixel
// reads 2 textures (grass + mask; was 7), the brick/rock textures are read only where the mask
// or the slope needs them, large-scale variation is arithmetic, no anisotropic filtering.
// Nothing here changes per frame.
render_mode specular_disabled;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D path_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D path_mask : filter_linear, repeat_disable;
uniform vec4 mask_rect;            // x0, z0, width, depth of the mask in world metres
uniform float grass_scale = 9.0;   // metres per grass tile
uniform float path_scale = 3.2;    // metres per herringbone period (4 bricks -> 0.8 m bricks)
uniform float rock_scale = 4.0;
uniform vec3 tint = vec3(1.0);     // brightness balance vs. the Vulkan exposure compensation
uniform float grass_sat = 1.0;     // saturation of the grass only

varying vec3 wpos;
varying vec3 wnorm;
varying float macro;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Large sunlit/shaded areas: smooth enough to compute per vertex (0.5 m apart).
	macro = clamp(0.5 + 0.28 * sin(wpos.x * 0.083 + 1.3) * sin(wpos.z * 0.071)
		+ 0.22 * sin(wpos.x * 0.041 - wpos.z * 0.057 + 0.7), 0.0, 1.0);
}

void fragment() {
	vec3 g = texture(grass_tex, wpos.xz / grass_scale).rgb;
	g *= mix(vec3(0.70, 0.80, 0.80), vec3(1.16, 1.12, 0.88), smoothstep(0.2, 0.8, macro));
	float gl = dot(g, vec3(0.299, 0.587, 0.114));
	g = mix(vec3(gl), g, grass_sat);
	vec3 mk = texture(path_mask, (wpos.xz - mask_rect.xy) / mask_rect.zw).rgb;
	vec3 col = g;
	// Brick path (only where the mask has one).
	if (mk.r > 0.02) {
		vec3 p = texture(path_tex, wpos.xz / path_scale).rgb;
		float edge = mk.r + (g.g - 0.55) * 0.9;           // ragged grassy border
		col = mix(g, p, smoothstep(0.42, 0.58, edge));
		col *= 1.0 - 0.18 * (smoothstep(0.25, 0.5, mk.r) * (1.0 - smoothstep(0.5, 0.75, mk.r)));
	}
	// Rock: steep faces (mapped on the face) and ledge rims seen from above.
	float steep = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	float rockw = smoothstep(0.32, 0.5, steep);
	if (rockw > 0.001) {
		vec2 ruv = abs(wnorm.x) > abs(wnorm.z) ? vec2(wpos.z, -wpos.y) : vec2(wpos.x, -wpos.y);
		col = mix(col, texture(rock_tex, ruv / rock_scale).rgb, rockw);
	} else if (mk.g > 0.2) {
		col = mix(col, texture(rock_tex, wpos.xz / rock_scale).rgb, smoothstep(0.2, 0.8, mk.g));
	}
	col *= 1.0 - 0.38 * mk.b;                            // shadow at the cliff foot
	ALBEDO = col * tint;
	ROUGHNESS = mix(0.95, 0.85, rockw);
}
