shader_type canvas_item;
// 0.31.194: Home's camp painting (bg_camp.webp; camp_scene.gd lays it out and runs `clock`), alive:
//  - the campfire's light flickers over everything near it -- the champions' faces, the stones, the ground -- with the
//    flames camp_scene.gd draws over the painted fire (fire_flick is theirs, so light and flame move together); the
//    lanterns and torches do the same, each a little, each in its own time;
//  - the two big banners ripple (the cloth only moves away from its edges: they hang still where they're held);
//  - the pennants on the towers flutter, out from their poles.
// All in the painting's px. motion 0 (Reduce Motion): still.
uniform vec2 paint_size = vec2(1024.0, 2048.0);
uniform float motion = 1.0;
uniform float clock = 0.0;
uniform vec3 fire = vec3(497.0, 880.0, 360.0);    // x, y, reach
uniform float fire_flick = 0.0;                   // -1..1
uniform vec4 lamps[6];                            // x, y, reach, phase
uniform int lamp_n = 0;
uniform vec4 cloth[2];                            // the banners: x0, y0, x1, y1 (held along the top)
uniform int cloth_n = 0;
uniform vec4 pennants[6];                         // x0 (the pole), y0, x1, y1
uniform int pennant_n = 0;

// (fragment()'s COLOR comes in already multiplied by the texture at UV -- the modulate alone is the vertex's)
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 p = UV * paint_size;
	vec2 q = p;
	for (int i = 0; i < 2; i++) {
		if (i >= cloth_n) {
			break;
		}
		vec4 r = cloth[i];
		if (p.x > r.x && p.x < r.z && p.y > r.y && p.y < r.w) {
			vec2 f = (p - r.xy) / (r.zw - r.xy);
			float hold = smoothstep(0.0, 0.18, f.x) * smoothstep(0.0, 0.18, 1.0 - f.x) * smoothstep(0.0, 0.25, f.y)
				* smoothstep(0.0, 0.06, 1.0 - f.y);
			float w = sin(clock * 1.5 + p.y * 0.028 + float(i) * 2.1) + 0.45 * sin(clock * 2.7 + p.y * 0.05 + float(i));
			q.x += motion * 2.6 * hold * f.y * w;
			q.y += motion * 1.2 * hold * f.y * sin(clock * 1.9 + p.x * 0.06 + float(i));
		}
	}
	for (int i = 0; i < 6; i++) {
		if (i >= pennant_n) {
			break;
		}
		vec4 r = pennants[i];
		if (p.x > r.x && p.x < r.z && p.y > r.y && p.y < r.w) {
			float u = (p.x - r.x) / (r.z - r.x);
			float v = (p.y - r.y) / (r.w - r.y);
			float edge = smoothstep(0.0, 0.2, v) * smoothstep(0.0, 0.2, 1.0 - v);
			q.y += motion * 2.2 * u * edge * sin(clock * 7.0 - p.x * 0.3 + float(i) * 1.3);
		}
	}
	vec4 c = texture(TEXTURE, q / paint_size);
	float warm = clamp((c.r - c.b) * 1.6 + 0.3, 0.0, 1.0);
	float d = length(p - fire.xy) / fire.z;
	float lit = 0.17 * fire_flick * exp(-d * d * 1.6);
	for (int i = 0; i < 6; i++) {
		if (i >= lamp_n) {
			break;
		}
		vec4 l = lamps[i];
		float dl = length(p - l.xy) / l.z;
		float fl = sin(clock * 9.3 + l.w) * 0.6 + sin(clock * 15.1 + l.w * 1.7) * 0.4;
		lit += 0.12 * fl * exp(-dl * dl * 2.0);
	}
	c.rgb *= 1.0 + motion * lit * warm;
	COLOR = c * tint;
}
