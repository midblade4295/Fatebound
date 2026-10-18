shader_type spatial;
// The 5v5's towers (0.31.172): a Meshy model (tools/tower_prep.py) in its side's colours from ONE texture, as
// team_swap.gdshader does the keep's pieces (blue as painted; red: its saturated blues turned deep red), and breaking
// as it loses health:
//  - every vertex carries UV2 = (stage, cell): the cells whose stage is at or under the tower's "broken" are hidden
//    (their triangles collapse to a point -- the view drops a copy of each as it breaks off);
//  - cracks (assets/meshy/towers/cracks.png, box-mapped in the model's own space) spread over the stone as "dmg" goes
//    from 0 to 1, darkening the texture along them;
//  - the inside of the shell, seen through a hole, is dark rubble;
//  - the brazier's fire and gem glow (the glow mask) -- in the side's colour where the texture is team blue -- while
//    "lit".
// broken, dmg and lit are per instance (one material per model and side).
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D glow_tex : hint_default_black, filter_linear_mipmap;
uniform sampler2D crack_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform int team = 0;                              // 0 blue (as painted), 1 red
uniform vec2 hue_range = vec2(195.0, 258.0);       // the blues that are team colour (degrees) -- team_swap.gdshader's
uniform vec2 sat_range = vec2(0.42, 0.58);
uniform float glow_energy = 1.8;
uniform float crack_tiles = 1.25;                  // crack texture repeats per model unit (the model is 1.0 tall)
uniform vec3 inside_color : source_color = vec3(0.42, 0.37, 0.32);
instance uniform float broken = 0.0;               // cells of stage <= this are gone (1..4; 0 = whole)
instance uniform float dmg = 0.0;                  // 0..1: how far the cracks have spread
instance uniform float lit = 1.0;                  // the brazier burning

varying vec3 obj_pos;
varying vec3 obj_nrm;

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

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
	if (UV2.x < broken + 0.5) {                     // (stages are whole numbers; the half allows for vertex compression)
		VERTEX = vec3(0.0);                        // (the whole triangle collapses: nothing drawn, no shadow)
	}
}

void fragment() {
	vec3 col = texture(albedo_tex, UV).rgb;
	if (team != 0) {
		vec3 s = pow(max(col, vec3(0.0)), vec3(1.0 / 2.2));
		vec3 h = rgb2hsv(s);
		float deg = h.x * 360.0;
		float w = smoothstep(hue_range.x - 8.0, hue_range.x + 4.0, deg) * (1.0 - smoothstep(hue_range.y - 4.0, hue_range.y + 8.0, deg));
		w *= smoothstep(sat_range.x, sat_range.y, h.y);
		vec3 swapped = hsv2rgb(vec3(358.0 / 360.0, min(h.y * 1.05, 1.0), h.z * 0.95));
		col = pow(mix(s, swapped, w), vec3(2.2));
	}
	vec3 glow = col * texture(glow_tex, UV).r * glow_energy * lit;
	if (dmg > 0.001) {
		vec3 bw = pow(abs(obj_nrm), vec3(4.0));
		bw /= (bw.x + bw.y + bw.z + 1.0e-5);
		vec3 p = obj_pos * crack_tiles;
		vec2 cx = texture(crack_tex, p.zy).rg;
		vec2 cy = texture(crack_tex, p.xz).rg;
		vec2 cz = texture(crack_tex, p.xy).rg;
		vec2 c = cx * bw.x + cy * bw.y + cz * bw.z;
		float show = smoothstep(c.y - 0.06, c.y + 0.06, dmg * 1.08);
		col *= 1.0 - 0.9 * c.x * show;
	}
	if (!FRONT_FACING) {
		col = inside_color;
		glow = vec3(0.0);
		NORMAL = -NORMAL;
	}
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.4;
	EMISSION = glow;
}
