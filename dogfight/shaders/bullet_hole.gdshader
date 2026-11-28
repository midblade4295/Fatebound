// A bullet hole, drawn on a small square laid flat on whatever was hit: a
// ragged black hole, a ring of bare metal where the paint has been knocked
// off round it, and a smudge of soot fading out.
//
// Per instance (INSTANCE_CUSTOM): r = a random number that makes each hole a
// different shape, g = how much bare metal shows (1 on an aeroplane, 0 for a
// mark in the ground), b = how dark the smudge round it is.
shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled;

varying float shape;
varying float metal;
varying float smudge;

void vertex() {
	shape = INSTANCE_CUSTOM.r * 6.2832;
	metal = INSTANCE_CUSTOM.g;
	smudge = INSTANCE_CUSTOM.b;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float angle = atan(p.y, p.x);
	// Torn, not drilled: the edge wanders in and out round the hole.
	float ragged = length(p) + 0.07 * sin(angle * 5.0 + shape) + 0.045 * sin(angle * 9.0 - shape * 2.3);
	float hole = 1.0 - smoothstep(0.34, 0.40, ragged);
	float rim = (1.0 - smoothstep(0.50, 0.58, ragged)) * (1.0 - hole) * metal;
	float soot = (1.0 - smoothstep(0.40, 1.0, ragged)) * smudge;
	vec3 colour = mix(vec3(0.07, 0.065, 0.06), vec3(0.66, 0.68, 0.70), rim);
	colour = mix(colour, vec3(0.012, 0.012, 0.015), hole);
	ALBEDO = colour;
	ALPHA = max(max(hole, rim * 0.9), soot * 0.7);
}
