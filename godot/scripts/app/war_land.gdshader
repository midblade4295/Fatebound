// 0.31.137 (Kevin: "a real natural land mass but in map form"): the war map's land. Its painted colours
// (assets/war_land/land_color.jpg, tools/war_land.py), and over them the war: each place's land tinted with the colour
// of the house that holds it, the borders drawn between places (a white line; none where a ridge stands -- no link
// there), the place picked lit and outlined, a battle's land pulsing orange, and cloud shadows drifting over it all.
shader_type spatial;
render_mode specular_disabled;

uniform sampler2D color_tex : source_color, filter_linear_mipmap;
uniform sampler2D region_id : filter_nearest;        // R = place index (255 = sea)
uniform sampler2D region_lin : filter_linear;        // G = distance to a border, B = a border with no link
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 holder[18];                             // the colour of the house holding each place (a = 0: nobody)
uniform float battle[18];                            // 1: a battle is on there
uniform int picked = -1;
uniform vec2 wind = vec2(0.012, 0.006);
uniform float cloud_strength = 0.28;
// 0.31.138 (Home's war table, scripts/app/war_room.gd): the land stands in a scene of its own there, smaller, on an oval
// table -- `to_map` takes the world back to the map's own space (identity on the war map), `disc` cuts it to an oval
// (its radii; 0: not cut), `glow` lights it a little from within (the map glowing on the table), `tint` (below) is how
// strongly the houses' colours show
uniform mat4 to_map = mat4(1.0);
uniform vec2 disc = vec2(0.0);                     // (x and z radii)
uniform float glow = 0.0;
uniform float tint = 0.16;                          // how strongly a place takes its holder's colour
varying vec3 world;

void vertex() {
	world = (to_map * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (disc.x > 0.0 && length(world.xz / disc) > 1.0) {
		discard;
	}
	vec3 col = texture(color_tex, UV).rgb;
	int id = int(texture(region_id, UV).r * 255.0 + 0.5);
	vec4 lin = texture(region_lin, UV);
	float edge = lin.g * 0.4;                         // table units to the nearest border
	float ridge = lin.b;
	if (id < 18) {
		vec4 hc = holder[id];
		col = mix(col, hc.rgb * 0.9 + col * 0.25, hc.a * tint);
		// the border: a soft white line with the holder's colour along its inside
		float line = (1.0 - smoothstep(0.008, 0.022, edge)) * (1.0 - ridge);
		float inner = (1.0 - smoothstep(0.03, 0.14, edge)) * hc.a;
		col = mix(col, hc.rgb * 1.15, inner * 0.7);
		col = mix(col, vec3(0.97, 0.95, 0.88), line * 0.7);
		float pulse = 0.5 + 0.5 * sin(TIME * 4.0);
		if (battle[id] > 0.5) {
			col = mix(col, vec3(1.0, 0.45, 0.12), 0.16 + 0.14 * pulse);
			col = mix(col, vec3(1.0, 0.62, 0.2), (1.0 - smoothstep(0.03, 0.12, edge)) * (0.5 + 0.4 * pulse));
		}
		if (id == picked) {
			col *= 1.16;
			col = mix(col, vec3(1.0, 1.0, 0.92), (1.0 - smoothstep(0.02, 0.09, edge)) * (0.65 + 0.3 * pulse));
		}
	}
	// clouds passing over
	float c = texture(cloud_tex, world.xz * 0.045 + TIME * wind).r;
	col *= 1.0 - cloud_strength * smoothstep(0.52, 0.78, c);
	ALBEDO = col;
	EMISSION = col * glow;
	ROUGHNESS = 0.95;
}
