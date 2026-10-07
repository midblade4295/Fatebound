shader_type spatial;
// A Meshy building in its owner's colours from ONE texture (0.31.73, the outposts): the model's texture is the blue
// team's; for the red team its saturated blues turn deep red (the same rule as tools/meshy_building_tex.py's
// _red.png, so the shops and the outposts match), and while nobody holds it they go to plain grey-white cloth.
// One texture per model instead of three keeps the download and the phone's memory down. Lit like a
// StandardMaterial3D (roughness 0.75, specular 0.45, as the shops), plus an emission mask (the glow) whose colour
// the view sets per owner.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D glow_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform int team = 0;                              // -1 neutral (grey), 0 blue (as painted), 1 red
uniform vec2 hue_range = vec2(195.0, 258.0);      // the blues that are team colour (degrees)
uniform vec2 sat_range = vec2(0.42, 0.58);        // ... from this saturation up (bluish-grey stone and iron stay)
uniform vec3 glow_color : source_color = vec3(1.0);
uniform float glow_energy = 0.0;
uniform float roughness_v = 0.75;
uniform float specular_v = 0.45;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 col = texture(albedo_tex, UV).rgb;
	if (team != 0) {
		vec3 s = pow(max(col, vec3(0.0)), vec3(1.0 / 2.2));      // the swap rule works on the painted (sRGB) colours
		vec3 h = rgb2hsv(s);
		float deg = h.x * 360.0;
		float w = smoothstep(hue_range.x - 8.0, hue_range.x + 4.0, deg) * (1.0 - smoothstep(hue_range.y - 4.0, hue_range.y + 8.0, deg));
		w *= smoothstep(sat_range.x, sat_range.y, h.y);
		vec3 swapped = team == 1
			? hsv2rgb(vec3(358.0 / 360.0, min(h.y * 1.05, 1.0), h.z * 0.95))
			: hsv2rgb(vec3(h.x, h.y * 0.08, min(h.z * 1.12 + 0.1, 0.92)));
		col = pow(mix(s, swapped, w), vec3(2.2));
	}
	ALBEDO = col;
	ROUGHNESS = roughness_v;
	SPECULAR = specular_v;
	EMISSION = glow_color * texture(glow_tex, UV).r * glow_energy;
}
