// Chunky "Clash" toon surface for planes, props and islands.
//
// - Diffuse is a lightly wrapped Lambert snapped into a few soft-edged bands
//   (cel shading). Shadowed bands receive only ambient sky light, which tints
//   them blue for free. The wrap is kept small on purpose: with two
//   directional lights a full half-Lambert lights every face from both sides
//   and washes the paint out to pastel.
// - A hard toon specular blob sells the glossy toy-plastic look.
// - Rim light has two parts: a light-aware rim (strongest on the edge facing a
//   light, so the scene's cool back "RimLight" outlines silhouettes) and a small
//   constant ambient rim so shapes still read when fully in shadow.
// Costs one custom light() per light: cheap enough for the Mobile renderer.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float bands : hint_range(1.0, 6.0, 1.0) = 3.0;
uniform float band_softness : hint_range(0.005, 0.5) = 0.06;
uniform float wrap : hint_range(0.0, 1.0) = 0.2;
uniform vec4 rim_color : source_color = vec4(0.78, 0.92, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.7;
uniform float ambient_rim : hint_range(0.0, 1.0) = 0.12;
uniform float spec_size : hint_range(0.0, 0.5) = 0.06;
uniform float spec_strength : hint_range(0.0, 2.0) = 0.45;
uniform float emission_strength : hint_range(0.0, 8.0) = 0.0;

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = albedo.rgb * emission_strength + rim_color.rgb * fresnel * ambient_rim;
}

void light() {
	float n_dot_l = dot(NORMAL, LIGHT);
	// A little wrap keeps the terminator soft without flattening the shape.
	float lit = clamp((n_dot_l + wrap) / (1.0 + wrap), 0.0, 1.0) * ATTENUATION;
	float scaled = lit * bands;
	float stepped = (floor(scaled) + smoothstep(0.5 - band_softness, 0.5 + band_softness, fract(scaled))) / bands;
	// LIGHT_COLOR already includes energy * PI; divide to match built-in Lambert.
	vec3 light_energy = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += stepped * light_energy;

	// Hard-edged toon highlight.
	vec3 half_dir = normalize(LIGHT + VIEW);
	float spec = smoothstep(1.0 - spec_size - 0.01, 1.0 - spec_size + 0.01, dot(NORMAL, half_dir));
	SPECULAR_LIGHT += spec * spec_strength * ATTENUATION * light_energy;

	// Light-aware rim: fresnel edge, only on the side the light actually hits.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float rim = fresnel * smoothstep(-0.1, 0.4, n_dot_l) * ATTENUATION;
	SPECULAR_LIGHT += rim_color.rgb * rim * rim_strength * light_energy;
}
