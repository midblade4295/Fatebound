// 0.31.138: Home's war room painting (bg_war_room.webp), drawn twice by home_scene.gd: first whole, its water
// glimmering (the river, the lake and the sea in the view: bg_war_room_mask.png G) -- then, over the sun's glow, the
// clouds and the birds, the room alone (`room_only`: the window's opening, mask R, cut out), so those are only seen
// through the window.
shader_type canvas_item;

uniform sampler2D mask : filter_linear;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform bool room_only = false;
uniform float motion = 1.0;                       // 0: reduce motion (the water holds still)
uniform vec2 paint_size = vec2(1152.0, 2560.0);
uniform vec2 sun = vec2(247.0, 469.0);            // where the sun sets (painting px)

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 m = texture(mask, UV).rg;
	if (room_only) {
		c.a *= 1.0 - m.r;
	} else if (m.g > 0.004) {
		float t = TIME * motion;
		vec2 p = UV * paint_size;
		// a slow swell of light over the water, stronger in the sun's path on the sea
		float swell = texture(noise_tex, p / 140.0 + vec2(t * 0.02, t * 0.008)).r;
		float path = exp(-abs(p.x - sun.x) / 26.0) * step(sun.y, p.y);
		float shimmer = (swell - 0.5) * (0.22 + 0.5 * path);
		// glints: where two fine drifting ripples both peak, a point of light comes and goes
		float r1 = texture(noise_tex, p / 9.0 + vec2(t * 0.05, -t * 0.013)).r;
		float r2 = texture(noise_tex, p / 13.0 - vec2(t * 0.031, t * 0.04)).r;
		float glint = smoothstep(0.5, 0.66, r1 * r2 * (1.0 + 0.6 * path));
		vec3 lit = c.rgb * (1.0 + shimmer) + vec3(1.0, 0.88, 0.78) * glint * (0.55 + 0.6 * path);
		c.rgb = mix(c.rgb, lit, m.g);
	}
	COLOR = c;
}
