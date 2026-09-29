shader_type spatial;
// Fatebound terrain (Round 7): lush grass, herringbone brick paths from the baked mask, rock on
// steep faces (ledges, river banks). All textures are the seamless Blender renders in
// assets/terrain. Nothing here changes per frame.

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_mask : filter_linear, repeat_disable;
uniform vec4 mask_rect;            // x0, z0, width, depth of the mask in world metres
uniform float grass_scale = 9.0;   // metres per grass tile
uniform float path_scale = 3.2;    // metres per herringbone period (4 bricks -> 0.8 m bricks)
uniform float rock_scale = 4.0;
uniform vec3 tint = vec3(1.0);     // brightness balance vs. the Vulkan exposure compensation

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 g = texture(grass_tex, wpos.xz / grass_scale).rgb;
	// Break up the grass tiling with a second, rotated, larger sample.
	vec2 r2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * wpos.xz / (grass_scale * 2.7);
	g = mix(g, texture(grass_tex, r2).rgb, 0.35);
	vec3 p = texture(path_tex, wpos.xz / path_scale).rgb;
	vec3 mk = texture(path_mask, (wpos.xz - mask_rect.xy) / mask_rect.zw).rgb;
	float m = mk.r;
	// Ragged edge: grass cells creep over the border, like the reference.
	float edge = m + (g.g - 0.55) * 0.9;
	vec3 col = mix(g, p, smoothstep(0.42, 0.58, edge));
	// Darker grout-ish rim where path meets grass.
	col *= 1.0 - 0.18 * (smoothstep(0.25, 0.5, m) * (1.0 - smoothstep(0.5, 0.75, m)));
	// Rock on steep faces, mapped on the face (x/z by dominant normal) so it doesn't stretch.
	float steep = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	vec2 ruv = abs(wnorm.x) > abs(wnorm.z) ? vec2(wpos.z, -wpos.y) : vec2(wpos.x, -wpos.y);
	vec3 rk = texture(rock_tex, ruv / rock_scale).rgb;
	float rockw = smoothstep(0.32, 0.5, steep);
	// A lighter grassy lip on top of each cliff, darker grass at its foot.
	col = mix(col, rk, rockw);
	// Ledges read from any camera angle: a rocky rim seen from above (top-down rock sample) and a
	// soft shadow on the ground at the cliff foot.
	vec3 rk_top = texture(rock_tex, wpos.xz / rock_scale).rgb;
	col = mix(col, rk_top, smoothstep(0.2, 0.8, mk.g) * (1.0 - rockw));
	col *= 1.0 - 0.38 * mk.b;
	ALBEDO = col * tint;
	ROUGHNESS = mix(0.95, 0.85, rockw);
	SPECULAR = 0.2;
}
