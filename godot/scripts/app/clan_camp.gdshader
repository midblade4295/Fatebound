shader_type canvas_item;
// 0.31.196: the clan camp's painting (assets/ui/clans/camp_<stage>.webp; scripts/app/clan_camp.gd lays it out and runs
// `clock`), alive and in the clan's colours:
//  - the banners' blue cloth takes the crest's field colour, keeping its folds and shading (the swallowtails too), and
//    ripples a little (still where the cloth hangs from its bar);
//  - the campfire's light flickers over everything near it, in time with the flames clan_camp.gd draws.
// All in the painting's px. motion 0 (Reduce Motion): still.
uniform vec2 paint_size = vec2(1024.0, 2048.0);
uniform float motion = 1.0;
uniform float clock = 0.0;
uniform vec3 fire = vec3(500.0, 560.0, 300.0);    // x, y, reach
uniform float fire_flick = 0.0;                   // -1..1
uniform vec4 cloth[5];                            // the banners: x0, y0, x1, y1 (the cloth, its tails below y1)
uniform int cloth_n = 0;
uniform vec3 field_col = vec3(0.17, 0.35, 0.76);
uniform float recolor = 1.0;

// (fragment()'s COLOR comes in already multiplied by the texture at UV -- the modulate alone is the vertex's)
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 p = UV * paint_size;
	vec2 q = p;
	float on_cloth = 0.0;
	for (int i = 0; i < 5; i++) {
		if (i >= cloth_n) {
			break;
		}
		vec4 r = cloth[i];
		float tail = (r.w - r.y) * 0.3;
		if (p.x > r.x - 6.0 && p.x < r.z + 6.0 && p.y > r.y - 4.0 && p.y < r.w + tail) {
			on_cloth = 1.0;
			vec2 f = (p - r.xy) / (r.zw - r.xy);
			float hold = smoothstep(0.0, 0.3, f.y);
			float w = sin(clock * 1.7 + p.y * 0.05 + float(i) * 2.3) + 0.4 * sin(clock * 2.9 + p.y * 0.09 + float(i));
			q.x += motion * 1.6 * hold * clamp(f.y, 0.0, 1.3) * w;
		}
	}
	vec4 c = texture(TEXTURE, q / paint_size);
	if (on_cloth > 0.5) {
		// the painted cloth is a deep blue (about 0.12, 0.15, 0.38): that blue becomes the field's colour at the same light
		// (0.31.197: and not the purple-blue sky behind the swallowtails -- the cloth is far bluer than it is red or green)
		float blue = smoothstep(0.04, 0.12, c.b - max(c.r, c.g)) * smoothstep(1.9, 2.4, c.b / max(0.01, max(c.r, c.g)));
		float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
		vec3 rec = field_col * clamp(lum / 0.17, 0.0, 2.2) * 0.92;
		c.rgb = mix(c.rgb, rec, blue * recolor);
	}
	float warm = clamp((c.r - c.b) * 1.6 + 0.3, 0.0, 1.0);
	float d = length(p - fire.xy) / fire.z;
	float lit = 0.16 * fire_flick * exp(-d * d * 1.6);
	c.rgb *= 1.0 + motion * lit * warm;
	COLOR = c * tint;
}
