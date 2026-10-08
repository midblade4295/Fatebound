shader_type canvas_item;
render_mode unshaded;
// 0.31.79 menu skin: one rounded box drawn as a signed distance, so it stays crisp at any phone density.
// Dark outline, a gold (or other) rim with a top-to-bottom gradient, a fill gradient optionally multiplied by a tiling
// pattern (damask, parchment, wood, stone), a button lip, gloss, bevel, a soft drop shadow and an outer glow.
// The quad is drawn `pad` px larger than the rect on every side (skin.gd), so the shadow and glow fit around it.

uniform vec2 rect_size = vec2(100.0, 50.0);
uniform float radius = 16.0;
uniform float outline = 2.0;
uniform vec4 outline_color : source_color = vec4(0.165, 0.086, 0.016, 1.0);
uniform float rim = 0.0;
uniform vec4 rim_a : source_color = vec4(1.0, 0.957, 0.784, 1.0);
uniform vec4 rim_b : source_color = vec4(0.969, 0.804, 0.333, 1.0);
uniform vec4 rim_c : source_color = vec4(0.725, 0.463, 0.106, 1.0);
uniform vec4 fill_top : source_color = vec4(0.23, 0.38, 0.84, 1.0);
uniform vec4 fill_bottom : source_color = vec4(0.03, 0.05, 0.17, 1.0);
uniform sampler2D pattern : source_color, repeat_enable, filter_linear_mipmap;
uniform float pattern_px = 190.0;
uniform float pattern_mix = 0.0;
uniform float pattern_gain = 1.0;
uniform float pattern_luma = 0.0;
uniform float lip = 0.0;
uniform vec4 lip_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float gloss = 0.0;
uniform float bevel = 0.18;
uniform float shadow_y = 5.0;
uniform float shadow_alpha = 0.5;
uniform float shadow_soft = 5.0;
uniform float glow = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.84, 0.35, 0.8);
uniform float pressed = 0.0;
uniform float dim = 0.0;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

float sdbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec4 over(vec4 top, vec4 under) {
	float a = top.a + under.a * (1.0 - top.a);
	if (a <= 0.0001) {
		return vec4(0.0);
	}
	vec3 c = (top.rgb * top.a + under.rgb * under.a * (1.0 - top.a)) / a;
	return vec4(c, a);
}

void fragment() {
	vec2 sz = rect_size;
	vec2 lp = local - vec2(0.0, pressed * 2.0);
	vec2 hs = sz * 0.5;
	vec2 p = lp - hs;
	float r = min(radius, min(hs.x, hs.y));
	float d = sdbox(p, hs, r);
	float aa = max(fwidth(d), 0.0001);
	vec4 col = vec4(0.0);
	if (shadow_alpha > 0.0) {
		float ds = sdbox(p - vec2(0.0, shadow_y * (1.0 - pressed * 0.7)), hs, r);
		float s = 1.0 - smoothstep(-shadow_soft, shadow_soft, ds);
		col = vec4(0.0, 0.0, 0.0, s * shadow_alpha);
	}
	if (glow > 0.0) {
		float g = glow_color.a * exp(-max(d, 0.0) * 2.2 / glow) * step(0.0, d);
		col = over(vec4(glow_color.rgb, g), col);
	}
	float t = clamp(lp.y / sz.y, 0.0, 1.0);
	vec4 fill = mix(fill_top, fill_bottom, t);
	if (pattern_mix > 0.0) {
		vec3 pt = texture(pattern, lp / pattern_px).rgb;
		pt = mix(pt, vec3(dot(pt, vec3(0.299, 0.587, 0.114))), pattern_luma) * pattern_gain;
		fill.rgb = mix(fill.rgb, fill.rgb * pt, pattern_mix);
	}
	float inner = -d;
	float edge = outline + rim;
	if (lip > 0.0) {
		float lh = lip * (1.0 - pressed * 0.65);
		float ly = smoothstep(sz.y - edge - lh - 0.8, sz.y - edge - lh + 0.8, lp.y);
		fill.rgb = mix(fill.rgb, lip_color.rgb, ly);
	}
	if (gloss > 0.0) {
		float gh = (sz.y - edge * 2.0 - lip) * 0.42;
		vec2 gc = vec2(hs.x, edge + 2.0 + gh * 0.5);
		float gd = sdbox(lp - gc, vec2(hs.x - edge - 5.0, gh * 0.5), min(r, gh * 0.5));
		float g = (1.0 - smoothstep(-1.5, 1.5, gd)) * (1.0 - 0.55 * clamp((lp.y - edge) / max(gh, 1.0), 0.0, 1.0));
		fill.rgb = mix(fill.rgb, vec3(1.0), g * 0.32 * gloss);
	}
	// bevel: a light line just inside the top edge, a dark one inside the bottom
	float bv = 1.0 - smoothstep(0.0, 3.0, inner - edge);
	fill.rgb += bevel * bv * (0.6 - 1.2 * t);
	vec3 rimc = t < 0.5 ? mix(rim_a.rgb, rim_b.rgb, t * 2.0) : mix(rim_b.rgb, rim_c.rgb, (t - 0.5) * 2.0);
	// a thin bright line along the inside of the rim
	float rl = 1.0 - smoothstep(0.0, 1.2, abs(inner - (outline + rim * 0.35)));
	rimc = mix(rimc, vec3(1.0, 0.98, 0.9), rl * 0.35 * (1.0 - t));
	float in_body = smoothstep(-aa, aa, inner);
	float in_rim = smoothstep(outline - aa, outline + aa, inner);
	float in_fill = smoothstep(edge - aa, edge + aa, inner);
	vec4 c = vec4(outline_color.rgb, outline > 0.0 ? 1.0 : 0.0);
	if (rim > 0.0) {
		c = mix(c, vec4(rimc, 1.0), in_rim);
	}
	if (outline <= 0.0 && rim <= 0.0) {
		c = fill;
	} else {
		c = mix(c, fill, in_fill);
	}
	c.rgb = mix(c.rgb, c.rgb * 0.55, dim);
	c.a *= in_body;
	COLOR = over(c, col);
}
