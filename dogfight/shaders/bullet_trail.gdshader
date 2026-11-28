// The smoke a bullet leaves behind it: a thin grey ribbon from where the
// round was fired to where it is now, widening and fading as it ages.
//
// The mesh is two crossed strips one unit long (z = 0 at the gun end, z = 1
// at the bullet end, x or y = +-0.5 across). BulletSystem stretches one
// instance along each bullet's path and passes, per instance:
//   COLOR            the smoke's colour and overall opacity
//   INSTANCE_CUSTOM  r, g: width at the gun end and at the bullet end, as a
//                    share of `widest` (per-instance numbers are kept 0..1)
//                    b, a: how much smoke is left at each end (1 fresh .. 0 gone)
// The gun end is always the older, so it is wider and fainter.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Trails are not drawn nearer the camera than this (metres), and fade in
// over the next stretch.
const float NEAREST_SEEN = 5.0;
const float NEAR_FADE = 16.0;

// The widest a ribbon ever gets, metres.
uniform float widest = 2.4;

varying float left;
varying vec3 air;

void vertex() {
	float along = UV.y;
	VERTEX.xy *= mix(INSTANCE_CUSTOM.r, INSTANCE_CUSTOM.g, along) * widest;
	left = mix(INSTANCE_CUSTOM.b, INSTANCE_CUSTOM.a, along);
	air = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Soft at the edges, and uneven along its length the way smoke is: the
	// clumps stay where they are in the air while the ribbon thins out.
	float across = smoothstep(0.0, 0.75, 1.0 - abs(UV.x * 2.0 - 1.0));
	float clumps = 0.7 + 0.3 * sin(air.x * 0.83 + air.y * 1.31 + air.z * 0.57) * sin(dot(air, vec3(0.29, -0.41, 0.37)));
	// Smoke that close to the eye is a haze you look through, not a white
	// bar across the screen: it thins to nothing over the last few metres.
	float nearness = smoothstep(NEAREST_SEEN, NEAREST_SEEN + NEAR_FADE, -VERTEX.z);
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * left * across * clumps * nearness;
}
