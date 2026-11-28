// The toon surface (see toon_plane.gdshader, which this follows line for line
// in its lighting) for the parts of an aeroplane, which can be shot up.
//
// Every piece of the model is told how badly its part is hurt:
//   damage       0 untouched .. 1 destroyed (PlaneActor.part_damage)
//   damage_seed  any number: makes each piece wear its damage differently
//   skin         1 for thin surfaces (wings, tail, control surfaces), which
//                tear right through; 0 for the fuselage and engine
// As the damage grows, streaks of soot and oil spread back along the piece,
// with specks of bare metal where the paint has chipped off round them; and
// past about a third, thin skin starts to go in ragged holes that can be
// seen through. It is
// all worked out from where on the piece each point is, so the marks stay
// put on the surface, and no textures are needed.
//
// Back faces are drawn (and drawn dark) so that the inside of the far skin
// shows through the holes rather than nothing at all.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float bands : hint_range(1.0, 6.0, 1.0) = 3.0;
uniform float band_softness : hint_range(0.005, 0.5) = 0.06;
uniform float wrap : hint_range(0.0, 1.0) = 0.2;
uniform vec4 rim_color : source_color = vec4(0.78, 0.92, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.7;
uniform float ambient_rim : hint_range(0.0, 1.0) = 0.12;
uniform float spec_size : hint_range(0.0, 0.5) = 0.06;
uniform float spec_strength : hint_range(0.0, 2.0) = 0.45;
uniform float emission_strength : hint_range(0.0, 8.0) = 0.0;

instance uniform float damage : hint_range(0.0, 1.0) = 0.0;
instance uniform float damage_seed = 0.0;
instance uniform float skin : hint_range(0.0, 1.0) = 0.0;

const vec3 SOOT = vec3(0.06, 0.055, 0.05);
const vec3 BARE_METAL = vec3(0.62, 0.64, 0.66);
const vec3 INSIDE = vec3(0.035, 0.035, 0.04);

varying vec3 on_piece;
varying float shine;

void vertex() {
	on_piece = VERTEX;
}

float scatter(vec3 cell) {
	return fract(sin(dot(cell, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

// Smooth random blotches, 0..1, about one unit across.
float blotches(vec3 p) {
	vec3 cell = floor(p);
	vec3 t = fract(p);
	t = t * t * (3.0 - 2.0 * t);
	float near = mix(mix(scatter(cell), scatter(cell + vec3(1.0, 0.0, 0.0)), t.x),
			mix(scatter(cell + vec3(0.0, 1.0, 0.0)), scatter(cell + vec3(1.0, 1.0, 0.0)), t.x), t.y);
	float far = mix(mix(scatter(cell + vec3(0.0, 0.0, 1.0)), scatter(cell + vec3(1.0, 0.0, 1.0)), t.x),
			mix(scatter(cell + vec3(0.0, 1.0, 1.0)), scatter(cell + vec3(1.0, 1.0, 1.0)), t.x), t.y);
	return mix(near, far, t.z);
}

void fragment() {
	vec3 colour = albedo.rgb;
	shine = 1.0;
	if (damage > 0.02) {
		vec3 p = on_piece * 3.4 + vec3(damage_seed * 17.0, damage_seed * 5.0, -damage_seed * 11.0);
		// Soot and oil are carried back by the airflow, so the stains are
		// streaks along the piece (z runs nose to tail), not round blots.
		vec3 streaked = vec3(p.x, p.y, p.z * 0.28);
		float stain = blotches(streaked) * 0.7 + blotches(streaked * 2.3) * 0.3;
		// More of the piece is stained the worse it is hurt: a few streaks
		// when it is first damaged, about half of it by the time it is done for.
		float stained_above = mix(0.90, 0.52, damage);
		float soot = smoothstep(stained_above, stained_above + 0.17, stain);
		// Round the stains the paint is chipped off in specks, down to the metal.
		float near_stain = smoothstep(stained_above - 0.14, stained_above, stain) * (1.0 - soot);
		float chipped = step(0.74, blotches(p * 7.5)) * near_stain;
		colour = mix(colour, BARE_METAL, chipped * 0.8);
		colour = mix(colour, SOOT, soot * 0.9);
		shine = 1.0 - soot;
		if (skin > 0.5 && damage > 0.33) {
			// Thin skin goes in ragged holes, small and few at first.
			float torn_above = mix(0.90, 0.66, smoothstep(0.33, 1.0, damage));
			if (blotches(p * 1.9 + vec3(7.3, 1.9, 4.1)) > torn_above) {
				discard;
			}
		}
	}
	if (!FRONT_FACING) {
		colour = INSIDE;
		shine = 0.0;
	}
	ALBEDO = colour;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = colour * emission_strength + rim_color.rgb * fresnel * ambient_rim * shine;
}

void light() {
	float n_dot_l = dot(NORMAL, LIGHT);
	// A little wrap keeps the terminator soft without flattening the shape.
	float lit = clamp((n_dot_l + wrap) / (1.0 + wrap), 0.0, 1.0) * ATTENUATION;
	float scaled = lit * bands;
	float stepped = (floor(scaled) + smoothstep(0.5 - band_softness, 0.5 + band_softness, fract(scaled))) / bands;
	// LIGHT_COLOR already includes energy * PI; divide to match built-in Lambert.
	vec3 light_energy = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += stepped * light_energy;

	// Hard-edged toon highlight.
	vec3 half_dir = normalize(LIGHT + VIEW);
	float spec = smoothstep(1.0 - spec_size - 0.01, 1.0 - spec_size + 0.01, dot(NORMAL, half_dir));
	SPECULAR_LIGHT += spec * spec_strength * shine * ATTENUATION * light_energy;

	// Light-aware rim: fresnel edge, only on the side the light actually hits.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float rim = fresnel * smoothstep(-0.1, 0.4, n_dot_l) * ATTENUATION;
	SPECULAR_LIGHT += rim_color.rgb * rim * rim_strength * shine * light_energy;
}
