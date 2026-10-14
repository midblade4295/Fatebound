// 0.31.138: Home's war table (war_room.gd) -- its oak: grain running round the table (UV.x goes round it, UV.y along
// its edge's profile), darker in the grooves, a soft sheen; `trim` > 0 makes it the gilt band instead.
shader_type spatial;

uniform sampler2D grain_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 dark : source_color = vec3(0.17, 0.085, 0.045);
uniform vec3 light : source_color = vec3(0.47, 0.27, 0.13);
uniform float rounds = 10.0;     // how many times the grain texture goes round
uniform float trim = 0.0;

void fragment() {
	float n = texture(grain_tex, vec2(UV.x * rounds, UV.y * 1.6)).r;
	float fine = texture(grain_tex, vec2(UV.x * rounds * 5.0, UV.y * 9.0)).r;
	float lines = 0.5 + 0.5 * sin(UV.y * 260.0 + n * 14.0 + fine * 3.0);
	vec3 wood = mix(dark, light, clamp(n * 1.25 - 0.15, 0.0, 1.0));
	wood *= 0.82 + 0.28 * lines;
	vec3 gold = mix(vec3(0.55, 0.36, 0.1), vec3(1.0, 0.8, 0.38), clamp(fine * 1.4 - 0.2, 0.0, 1.0));
	ALBEDO = mix(wood, gold, trim);
	ROUGHNESS = mix(0.62 - 0.12 * lines, 0.3, trim);
	METALLIC = trim * 0.85;
	SPECULAR = mix(0.22, 0.6, trim);
}
