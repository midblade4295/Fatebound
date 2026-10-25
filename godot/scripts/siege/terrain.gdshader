shader_type spatial;
// Fatebound terrain. 0.31.216 (Kevin: "use eleven to draw detailed paint on ground"): the ground ElevenLabs painted
// (tools/ground_paint.py) -- two hand-painted lawns, each laid at its own angle and scale and blended by a slow noise so
// neither repeats, flagstone lanes (Honor of Kings' grey-blue slabs with grass in the joints), worn earth for the jungle
// trails and the lanes' fringes, the painted cliff rock on steep faces and ledge rims, the pebbled river bed under the
// water. From the baked mask (tools/bake_land.gd): R = how far into a lane or trail (1 in the middle, 0.5 at its edge),
// G = rock rim, B = shadow at a cliff's foot, A = how far into a lane's paving (lanes only: 0.5 at its edge).
// (Round 7 .. 0.31.215: the Fat Princess painted grass with sweeping bands, the dirt-track lanes.) Optimised as before
// (0.14.2): a plain grass pixel reads 4 textures (two lawns, the mask, the macro noise); the lane, dirt, rock and bed
// textures only where the mask, the slope or the height needs them; no anisotropic filtering. Nothing changes per frame
// but the clouds.
render_mode specular_disabled;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass2_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D lane_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D path_tex : source_color, filter_linear_mipmap, repeat_enable;      // the worn earth
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bed_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D path_mask : filter_linear, repeat_disable;
uniform vec4 mask_rect;            // x0, z0, width, depth of the mask in world metres
uniform float grass_scale = 9.0;   // metres per lawn tile
uniform float lane_scale = 7.5;    // metres per flagstone tile (a big slab ~1.5 m)
uniform float path_scale = 6.0;    // metres per earth tile
uniform float rock_scale = 5.0;
uniform float bed_scale = 4.5;
uniform vec3 tint = vec3(1.0);     // brightness balance vs. the Vulkan exposure compensation
uniform float grass_sat = 1.0;

uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform float cloud_strength = 0.0;  // High-quality graphics: drifting cloud shadows (Round 32)

uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 rock_col = vec3(1.0);
// Outpost capture rings, painted on the ground (0.30.3): xy centre, z radius, w |capture progress|;
// post_ring rgb + strength; post_cap rgb + strength of the capture fill (0 when nothing is being captured).
uniform vec4 posts[6];
uniform vec4 post_ring[6];
uniform vec4 post_cap[6];
varying vec3 wpos;
varying vec3 wnorm;

const mat2 TURN = mat2(vec2(0.4536, 0.8912), vec2(-0.8912, 0.4536));   // the second lawn laid 63 degrees round

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 mk = texture(path_mask, (wpos.xz - mask_rect.xy) / mask_rect.zw);
	float m1 = texture(macro_tex, wpos.xz / 31.0).r;
	float m2 = texture(macro_tex, wpos.xz / 83.0 + vec2(0.31, 0.17)).r;
	vec3 g1 = texture(grass_tex, wpos.xz / grass_scale).rgb;
	vec3 g2 = texture(grass2_tex, TURN * wpos.xz / (grass_scale * 1.17)).rgb;
	vec3 g = mix(g1, g2, smoothstep(0.38, 0.62, m1));
	g = mix(vec3(0.30, 0.52, 0.25), g, 0.72);           // the painting's strokes a little softer at this distance
	// broad painted light: sunlit yellow-green meadows and cooler blue-green hollows
	g *= mix(vec3(0.88, 0.95, 1.02), vec3(1.08, 1.05, 0.92), smoothstep(0.3, 0.72, m2));
	float gl = dot(g, vec3(0.299, 0.587, 0.114));
	g = mix(vec3(gl), g, grass_sat);
	vec3 col = g;
	float n2 = texture(macro_tex, wpos.xz / 2.3 + vec2(0.37, 0.71)).r;
	if (mk.r > 0.02) {
		// earth: the jungle trails and the pits' trodden arenas
		vec3 p = texture(path_tex, wpos.xz / path_scale).rgb;
		p = mix(vec3(dot(p, vec3(0.299, 0.587, 0.114))), p, 0.72) * vec3(0.96, 0.95, 1.0);   // earthier, less orange
		p *= 0.92 + 0.16 * m1;
		float edge = mk.r + (g.g - 0.5) * 0.22 + (n2 - 0.5) * 0.3;
		float dirt = smoothstep(0.47, 0.53, edge);
		float inner = smoothstep(0.5, 0.9, mk.r);
		p *= mix(0.86, 1.04, inner);                       // damp, darker earth by the grass; dusty middle
		col = mix(g * (1.0 - 0.12 * smoothstep(0.25, 0.47, edge)), p, dirt);
	}
	if (mk.a > 0.05) {
		// a lane's flagstones: whole slabs at its edge (the stone shows where a slab is, the joints stay grass); the
		// joints' grass and the slabs' grey both from the painting, the grass round them a little trodden
		vec3 s = texture(lane_tex, wpos.xz / lane_scale).rgb;
		float slab = 1.0 - clamp((s.g - max(s.r, s.b)) * 9.0, 0.0, 1.0);    // grey slab 1, green joint 0
		float e = mk.a + 0.16 * slab - 0.08 + (n2 - 0.5) * 0.12;
		float stone = smoothstep(0.5, 0.56, e);
		s *= 0.94 + 0.12 * m1;
		col *= 1.0 - 0.1 * smoothstep(0.3, 0.5, e);
		col = mix(col, s, stone);
	}
	// Rock: the painted cliff stone, triplanar, on steep faces and the ledge rims, moss where a face turns up.
	float steep = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	float jit = (m1 - 0.5) * 0.24 + (g.g - 0.5) * 0.3;
	float rockw = smoothstep(0.30, 0.52, steep + jit);
	float rimw = mk.g > 0.15 ? smoothstep(0.44, 0.58, mk.g + jit * 1.2) : 0.0;
	float rw = max(rockw, rimw);
	if (rw > 0.001) {
		vec3 an = pow(abs(wnorm), vec3(4.0));
		an /= (an.x + an.y + an.z);
		vec3 r = texture(rock_tex, vec2(wpos.z, -wpos.y) / rock_scale).rgb * an.x
			+ texture(rock_tex, wpos.xz / rock_scale).rgb * an.y
			+ texture(rock_tex, vec2(wpos.x, -wpos.y) / rock_scale).rgb * an.z;
		r *= rock_col;
		float moss = smoothstep(0.6, 0.9, wnorm.y) * smoothstep(0.42, 0.62, m1 + (g.g - 0.5));
		r = mix(r, g * 0.9, moss * 0.65);
		col = mix(col, r, rw);
	}
	// the river bed under the water (the river runs along z = 0 -- siege_land.gd; not the paving of a lane's ford)
	if (wpos.y < -0.04 && abs(wpos.z) < 15.0 && mk.a < 0.5) {
		vec3 b = texture(bed_tex, wpos.xz / bed_scale).rgb;
		col = mix(col, b, smoothstep(-0.04, -0.22, wpos.y));
	}
	col *= 1.0 - 0.38 * mk.b;                          // shadow at the cliff foot
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
	}
	float cl = smoothstep(0.46, 0.74, texture(cloud_tex, wpos.xz / 95.0 + vec2(TIME * 0.006, TIME * 0.0035)).r);
	ALBEDO = col * tint * (1.0 - cloud_strength * cl);
	ROUGHNESS = mix(0.95, 0.88, rw);
}
