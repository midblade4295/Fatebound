// Trees: soft toon shading with the sun glowing warmly through the leaves.
//
// One material does the whole tree. The mesh's vertex colours (painted by
// tools/blender/coast_world.py) say what each part is:
//   COLOR.r  how high up the canopy (0 at the bottom, 1 at the top)
//   COLOR.g  a different number for each puff of leaves
//   COLOR.b  1 for leaves, 0 for bark
// Trees are drawn in MultiMeshes, so each also gets a shade of its own from
// its instance number.
//
// Leaves are lit softly from all round (a wide wrap), and where the sun is
// behind them, seen from the camera, they pick up a warm glow: light
// scattered through the canopy rather than off it.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 leaf_dark : source_color = vec4(0.10, 0.42, 0.14, 1.0);
uniform vec4 leaf_light : source_color = vec4(0.42, 0.78, 0.22, 1.0);
uniform vec4 bark_color : source_color = vec4(0.40, 0.25, 0.14, 1.0);
uniform vec4 scatter_color : source_color = vec4(1.0, 0.86, 0.36, 1.0);
uniform float scatter_strength : hint_range(0.0, 2.0) = 0.7;
uniform float wrap : hint_range(0.0, 1.0) = 0.55;
uniform float bands : hint_range(1.0, 6.0, 1.0) = 3.0;
uniform float band_softness : hint_range(0.005, 0.5) = 0.2;

varying float tree_shade;
varying float leafy;

void vertex() {
	tree_shade = fract(float(INSTANCE_ID) * 0.6180339);
}

void fragment() {
	leafy = COLOR.b;
	float sunlit = clamp(COLOR.r * 0.8 + COLOR.g * 0.25, 0.0, 1.0);
	vec3 leaves = mix(leaf_dark.rgb, leaf_light.rgb, sunlit) * (0.86 + 0.28 * tree_shade);
	ALBEDO = mix(bark_color.rgb, leaves, leafy);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}

void light() {
	float n_dot_l = dot(NORMAL, LIGHT);
	float soft = mix(0.2, wrap, leafy);
	float lit = clamp((n_dot_l + soft) / (1.0 + soft), 0.0, 1.0) * ATTENUATION;
	float scaled = lit * bands;
	float stepped = (floor(scaled) + smoothstep(0.5 - band_softness, 0.5 + band_softness, fract(scaled))) / bands;
	vec3 energy = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += stepped * energy;
	// Looking toward the light through the canopy: the shaded side glows.
	float through = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 2.5) * (1.0 - clamp(n_dot_l, 0.0, 1.0) * 0.6);
	DIFFUSE_LIGHT += scatter_color.rgb * through * scatter_strength * leafy * ATTENUATION * energy;
}
