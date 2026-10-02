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
uniform float grass_scale = 16.0;  // metres per grass tile (painted cells ~1.6 m)
uniform float path_scale = 3.2;    // metres per herringbone period (4 bricks -> 0.8 m bricks)
uniform float rock_scale = 4.0;
uniform vec3 tint = vec3(1.0);     // brightness balance vs. the Vulkan exposure compensation
uniform float grass_sat = 1.0;     // saturation of the grass only
uniform float band_strength = 1.0; // contrast of the painted sweeping bands

uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform float cloud_strength = 0.0;  // High-quality graphics: drifting cloud shadows (Round 32)

uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 rock_col = vec3(0.78, 0.80, 0.78);
// Outpost capture rings, painted on the ground (0.30.3): xy centre, z radius, w |capture progress|;
// post_ring rgb + strength; post_cap rgb + strength of the capture fill (0 when nothing is being captured).
uniform vec4 posts[6];
uniform vec4 post_ring[6];
uniform vec4 post_cap[6];
varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 mk = texture(path_mask, (wpos.xz - mask_rect.xy) / mask_rect.zw);
	vec3 g = texture(grass_tex, wpos.xz / grass_scale).rgb;
	// Painted sweeping bands (baked in the mask's alpha): lighter/warmer vs darker/cooler arcs.
	g *= mix(vec3(1.0) - band_strength * vec3(0.18, 0.14, 0.14), vec3(1.0) + band_strength * vec3(0.08, 0.07, 0.02), mk.a);
	float gl = dot(g, vec3(0.299, 0.587, 0.114));
	g = mix(vec3(gl), g, grass_sat);
	vec3 col = g;
	// Brick path (only where the mask has one).
	if (mk.r > 0.02) {
		vec3 p = texture(path_tex, wpos.xz / path_scale).rgb;
		float edge = mk.r + (g.g - 0.55) * 0.9;           // ragged grassy border
		col = mix(g, p, smoothstep(0.42, 0.58, edge));
		col *= 1.0 - 0.18 * (smoothstep(0.25, 0.5, mk.r) * (1.0 - smoothstep(0.5, 0.75, mk.r)));
	}
	// Rock (0.30.1, Kevin: "look more natural like actual stone, and blend"): grey layered stone, sampled
	// triplanar so angled faces don't stretch, a ragged noisy edge against the grass, faint strata, and moss
	// where a face turns up. The rock texture is read only where there is rock.
	float mn = texture(macro_tex, wpos.xz / 38.0).r;
	float steep = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	float jit = (mn - 0.5) * 0.24 + (g.g - 0.55) * 0.35;
	float rockw = smoothstep(0.30, 0.52, steep + jit);
	float rimw = mk.g > 0.15 ? smoothstep(0.25, 0.8, mk.g + jit) : 0.0;
	float rw = max(rockw, rimw);
	if (rw > 0.001) {
		vec3 an = pow(abs(wnorm), vec3(4.0));
		an /= (an.x + an.y + an.z);
		vec3 r = texture(rock_tex, vec2(wpos.z, -wpos.y) / rock_scale).rgb * an.x
			+ texture(rock_tex, wpos.xz / rock_scale).rgb * an.y
			+ texture(rock_tex, vec2(wpos.x, -wpos.y) / rock_scale).rgb * an.z;
		r *= rock_col * (0.9 + 0.1 * sin(wpos.y * 2.4 + mn * 7.0));
		float moss = smoothstep(0.6, 0.9, wnorm.y) * smoothstep(0.42, 0.62, mn + (g.g - 0.55));
		r = mix(r, g * 0.9, moss * 0.65);
		col = mix(col, r, rw);
	}
	col *= 1.0 - 0.38 * mk.b;
	for (int i = 0; i < 6; i++) {
		float rr = posts[i].z;
		if (rr <= 0.0) { continue; }
		float d = distance(wpos.xz, posts[i].xy);
		if (d > rr + 0.6) { continue; }
		float line = 1.0 - smoothstep(0.12, 0.26, abs(d - rr));
		float dash = 0.75 + 0.25 * step(0.5, fract(atan(wpos.z - posts[i].y, wpos.x - posts[i].x) * 5.0));
		col = mix(col, post_ring[i].rgb, line * post_ring[i].a * dash);
		col = mix(col, post_ring[i].rgb, (1.0 - smoothstep(rr - 1.2, rr, d)) * step(d, rr) * 0.10 * post_ring[i].a);
		float fill = (1.0 - smoothstep(rr * posts[i].w - 0.08, rr * posts[i].w + 0.08, d)) * post_cap[i].a;
		col = mix(col, post_cap[i].rgb, fill);
	}                            // shadow at the cliff foot
	float cl = smoothstep(0.46, 0.74, texture(cloud_tex, wpos.xz / 95.0 + vec2(TIME * 0.006, TIME * 0.0035)).r);
	ALBEDO = col * tint * (1.0 - cloud_strength * cl);
	ROUGHNESS = mix(0.95, 0.88, rw);
}
