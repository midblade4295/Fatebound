shader_type spatial;
// The ribbon a weapon leaves in a swing (0.31.100, weapon_fx_root.gd): UV.x is its age (0 = the blade now, 1 = the
// end), UV.y runs from the base of the blade (0) to the tip (1); the vertex alpha is how fast the blade moved there.
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform float energy = 1.0;

void fragment() {
	float age = clamp(UV.x, 0.0, 1.0);
	float across = clamp(UV.y, 0.0, 1.0);
	float fade = pow(1.0 - age, 2.5);
	float edge = pow(smoothstep(0.0, 1.0, across), 1.6);       // a crescent: bright along the tip's path
	vec3 c = mix(tint.rgb, vec3(1.0), 0.6 * (1.0 - age) * across * across * across);
	ALBEDO = c;
	ALPHA = clamp(fade * edge * COLOR.a * energy * 0.7, 0.0, 1.0);
}
