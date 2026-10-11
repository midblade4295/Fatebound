shader_type spatial;
// A weapon's glow (0.31.93, redone 0.31.100): an additive pass over the weapon's own material (next_pass), so the
// model, its texture and its shadows are untouched. Shared by every piece that wears the same settings.
//   rim    a fresnel edge in the tint
//   sweep  a glint that runs up the piece every ~2 s, white-hot in its middle
//   veins  glowing cracks in the metal (a 3D cell pattern in the piece's own space), a pulse flowing up them
//   key    a legendary's gems / lava / eye lit from its own texture: the texels near a hue (key.x, 0-1, +- key.y),
//          at least key.z saturated and key.w bright, glow in their own colour (key_amt), breathing
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.75, 0.3, 1.0);
uniform float rim = 0.3;
uniform float sweep = 0.6;
uniform float veins = 0.0;
uniform float boost = 1.0;
uniform float span = 2.0;          // the piece's length (model units), so the patterns keep their size on any weapon
uniform sampler2D albedo_tex : filter_linear_mipmap, repeat_enable;   // raw (sRGB) values: the key reads them as painted
uniform vec4 key = vec4(0.0, 0.05, 0.5, 0.5);
uniform float key_amt = 0.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}

float cracks(vec3 p) {
	// distance to the nearest edge between cells (F2 - F1): small on the cracks
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				float d = length(g + hash3(i + g) - f);
				if (d < d1) {
					d2 = d1;
					d1 = d;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return d2 - d1;
}

vec3 hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
}

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - facing, 3.0);
	float y = lp.y / max(span, 0.01);
	vec3 hot = mix(tint.rgb, vec3(1.0), 0.65);
	vec3 c = tint.rgb * fres * rim;
	// the glint: a narrow band, its core white
	float band = abs(fract(y * 0.75 - TIME * 0.42) - 0.5);
	c += hot * smoothstep(0.045, 0.0, band) * sweep * (0.4 + 0.6 * facing);
	c += tint.rgb * smoothstep(0.12, 0.0, band) * sweep * 0.25;
	if (veins > 0.0) {
		float v = smoothstep(0.06, 0.0, cracks(lp / max(span, 0.01) * 12.0));
		float flow = 0.25 + 0.75 * pow(0.5 + 0.5 * sin(y * 11.0 - TIME * 3.2), 3.0);
		c += mix(tint.rgb, vec3(1.0), 0.35 * flow) * v * flow * veins;
	}
	if (key_amt > 0.0) {
		vec3 a = texture(albedo_tex, UV).rgb;
		vec3 h = hsv(a);
		float dh = abs(fract(h.x - key.x + 0.5) - 0.5);
		float m = smoothstep(key.y, key.y * 0.4, dh) * smoothstep(key.z, key.z + 0.15, h.y) * smoothstep(key.w, key.w + 0.15, h.z);
		float breathe = 0.7 + 0.3 * sin(TIME * 2.2);
		c += pow(a, vec3(2.2)) * m * key_amt * breathe;
	}
	ALBEDO = c * boost * 0.5;       // (the scene's exposure lifts an unshaded add a lot)
	ALPHA = 1.0;
}
