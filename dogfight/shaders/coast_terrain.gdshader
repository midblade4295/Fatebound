// The coastal countryside: rolling grass, a patchwork of fields, white chalk
// cliffs. It reads the mesh's vertex colours (painted by
// tools/blender/coast_world.py):
//   COLOR.r  grass          COLOR.g  wheat          COLOR.b  chalk
//   COLOR.a  farmland: where fields may be (the shader draws the fields
//            themselves, hedge by hedge, so their edges are crisp however
//            coarse the mesh is)
// and adds what vertex colours cannot: the exact outline of every field with
// a hedge round it, wheat, plough and pasture in different fields, furrows,
// two-tone turf, strata in the chalk. All of it is worked out from where the
// point is in the world, with no textures. The fields are the same grid, and
// the same hash, that the Blender script used to decide which are wheat, so
// what is drawn agrees with what was painted.
//
// Lighting is the game's toon lighting (see toon_plane.gdshader), without the
// rim: seen from an aeroplane the ground is all grazing angles.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 grass_light : source_color = vec4(0.47, 0.80, 0.25, 1.0);
uniform vec4 grass_dark : source_color = vec4(0.25, 0.62, 0.20, 1.0);
uniform vec4 hedge_color : source_color = vec4(0.12, 0.40, 0.14, 1.0);
uniform vec4 wheat_light : source_color = vec4(0.98, 0.82, 0.32, 1.0);
uniform vec4 wheat_dark : source_color = vec4(0.90, 0.64, 0.18, 1.0);
uniform vec4 plough_color : source_color = vec4(0.62, 0.42, 0.24, 1.0);
uniform vec4 pasture_color : source_color = vec4(0.62, 0.86, 0.30, 1.0);
uniform vec4 chalk_light : source_color = vec4(0.97, 0.97, 0.94, 1.0);
uniform vec4 chalk_shade : source_color = vec4(0.78, 0.82, 0.84, 1.0);
uniform vec4 seabed_color : source_color = vec4(0.82, 0.90, 0.84, 1.0);
// The field grid, as in coast_world.py: cells this many metres by this many,
// turned this far off north, and the seed of the hash that sorts them.
uniform vec2 field_size = vec2(190.0, 150.0);
uniform float field_turn = 0.41887902;
uniform int field_seed = 12;
uniform float hedge_width = 6.0;
// Fine detail fades out between these distances, so it does not shimmer.
uniform float detail_near = 250.0;
uniform float detail_far = 1600.0;
uniform float bands : hint_range(1.0, 6.0, 1.0) = 3.0;
uniform float band_softness : hint_range(0.005, 0.5) = 0.12;
uniform float wrap : hint_range(0.0, 1.0) = 0.25;

varying vec3 world_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// The same repeatable number per grid cell that coast_world.py's _lattice() gives.
float lattice(ivec2 cell, int seed) {
	uint n = uint(cell.x) * 374761393u + uint(cell.y) * 668265263u + uint(seed) * 1442695041u;
	n = (n ^ (n >> 13u)) * 1274126177u;
	n = n ^ (n >> 16u);
	return float(n) / 4294967295.0;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float detail = 1.0 - smoothstep(detail_near, detail_far, length(VERTEX));
	float broad = value_noise(world_pos.xz * 0.0035);
	float middling = value_noise(world_pos.xz * 0.028 + vec2(17.0, 5.0));
	float fine = value_noise(world_pos.xz * 0.45);

	// Turf: light on the open ground, darker in the hollows and in patches.
	vec3 ground = mix(grass_dark.rgb, grass_light.rgb, clamp(broad * 0.65 + middling * 0.45, 0.0, 1.0));
	ground *= 1.0 - 0.07 * (fine - 0.5) * detail;

	// Fields. Blender's y is -z here.
	float turn_cos = cos(field_turn);
	float turn_sin = sin(field_turn);
	vec2 across = vec2(world_pos.x * turn_cos - world_pos.z * turn_sin, -world_pos.x * turn_sin - world_pos.z * turn_cos) / field_size;
	ivec2 cell = ivec2(floor(across));
	vec2 within = fract(across);
	float kind = lattice(cell, field_seed);
	float shade = lattice(cell, field_seed + 1);
	float to_hedge = min(min(within.x, 1.0 - within.x) * field_size.x, min(within.y, 1.0 - within.y) * field_size.y);
	float farmland = smoothstep(0.35, 0.65, COLOR.a);
	// Rows run along the long side of the field.
	float rows = 0.5 + 0.5 * sin(within.y * field_size.y * 1.6);
	vec3 crop = ground;
	if (kind < 0.36) {
		crop = mix(wheat_dark.rgb, wheat_light.rgb, shade) * (1.0 - 0.10 * rows * detail);
	} else if (kind < 0.47) {
		crop = plough_color.rgb * (0.86 + 0.2 * shade) * (1.0 - 0.22 * rows * detail);
	} else if (kind < 0.62) {
		crop = mix(pasture_color.rgb, grass_light.rgb, shade);
	}
	float in_field = farmland * smoothstep(hedge_width, hedge_width + 2.0, to_hedge);
	ground = mix(ground, crop, in_field);
	// Every field has its hedge, a little ragged.
	float hedge = farmland * (1.0 - smoothstep(hedge_width * (0.55 + 0.5 * middling), hedge_width * (0.9 + 0.5 * middling), to_hedge));
	ground = mix(ground, hedge_color.rgb * (0.85 + 0.3 * fine), hedge);

	// Chalk wherever the ground itself is steep, read from the surface, not
	// from the smoothed normals: white right up to the lip, turf right up to
	// the edge.
	vec3 face = normalize(cross(dFdy(world_pos), dFdx(world_pos)));
	float steep = max(COLOR.b, 1.0 - smoothstep(0.55, 0.72, abs(face.y)));
	// Beds in the chalk, and streaks down it.
	float beds = value_noise(vec2(world_pos.y * 0.16, (world_pos.x + world_pos.z) * 0.004));
	float streaks = value_noise(vec2((world_pos.x + world_pos.z) * 0.07, world_pos.y * 0.012));
	vec3 chalk = mix(chalk_shade.rgb, chalk_light.rgb, clamp(0.35 + beds * 0.5 + streaks * 0.35, 0.0, 1.0));
	ground = mix(ground, chalk, steep);
	// Under the water: pale sand and chalk rubble.
	ground = mix(ground, seabed_color.rgb, step(world_pos.y, -0.5));

	ALBEDO = ground;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}

void light() {
	float n_dot_l = dot(NORMAL, LIGHT);
	float lit = clamp((n_dot_l + wrap) / (1.0 + wrap), 0.0, 1.0) * ATTENUATION;
	float scaled = lit * bands;
	float stepped = (floor(scaled) + smoothstep(0.5 - band_softness, 0.5 + band_softness, fract(scaled))) / bands;
	DIFFUSE_LIGHT += stepped * LIGHT_COLOR / PI;
}
