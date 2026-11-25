// The battlefield's ground: a striped green lawn inside a darker meadow, never one flat colour.
//
// Colour comes from a single tiling noise texture sampled at three scales (macro patches,
// mottling, fine speckle), plus clear mowing stripes on the field, worn earth on the road, at
// the fords and around the works, sand and pebbles on the creek's banks, drifting cloud shadow
// and dappled light at the wood's edge. Colours are written as seen on screen and converted to
// linear at the end.
shader_type spatial;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec2 worn[6];
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float n1 = texture(noise, wp.xz * 0.035).r;
	float n2 = texture(noise, wp.xz * 0.21 + vec2(0.37, 0.11)).r;
	float n3 = texture(noise, wp.xz * 0.9).r;
	float in_field = smoothstep(0.0, 0.7, 9.0 - abs(wp.x)) * smoothstep(0.0, 0.7, 18.0 - abs(wp.z));
	// The field: a mown lawn in clear alternating bands, mottled just enough not to be flat.
	float stripe = smoothstep(0.44, 0.56, abs(fract(wp.z * 0.23 + 0.25) - 0.5) * 2.0);
	vec3 field = mix(vec3(0.40, 0.58, 0.19), vec3(0.50, 0.67, 0.24), stripe);
	field *= 0.94 + 0.12 * n2;
	field = mix(field, vec3(0.55, 0.68, 0.26), smoothstep(0.6, 0.9, n1) * 0.25);     // sunnier patches
	// The meadow around it: deeper greens, patchy.
	vec3 meadow = mix(vec3(0.27, 0.42, 0.15), vec3(0.42, 0.53, 0.2), n1) * (0.88 + 0.24 * n2);
	// Leaf litter under the trees: drifts of orange, red and gold.
	float litter = smoothstep(0.52, 0.7, n3) * (1.0 - in_field);
	vec3 leaf = mix(vec3(0.85, 0.36, 0.1), vec3(0.95, 0.72, 0.2), n2);
	leaf = mix(leaf, vec3(0.72, 0.18, 0.1), smoothstep(0.6, 0.8, n1));
	meadow = mix(meadow, leaf, litter * 0.6);
	vec3 col = mix(meadow, field, in_field);
	// Worn earth: the road over the bridge, the approaches to the fords, around the works.
	float path = (1.0 - smoothstep(0.6, 1.3, abs(wp.x))) * (1.0 - smoothstep(11.0, 15.5, abs(wp.z))) * 0.75;
	path = max(path, (1.0 - smoothstep(0.9, 1.9, abs(abs(wp.x) - 6.0))) * (1.0 - smoothstep(1.6, 3.6, abs(wp.z))) * 0.85);
	for (int i = 0; i < 6; i++) {
		path = max(path, (1.0 - smoothstep(1.5, 2.9, distance(wp.xz, worn[i]))) * 0.8);
	}
	// Break the wear up with noise so its edges are ragged, then lay dry earth with darker,
	// damper mud where the traffic is heaviest.
	path = clamp(path * (0.3 + 1.25 * n2), 0.0, 1.0);
	path = smoothstep(0.18, 0.62, path);
	vec3 earth = mix(vec3(0.7, 0.6, 0.42), vec3(0.6, 0.5, 0.34), n3);
	earth = mix(earth, vec3(0.44, 0.35, 0.24), smoothstep(0.75, 1.0, path) * smoothstep(0.45, 0.7, n1) * 0.7);
	col = mix(col, earth, path * 0.92);
	// Banks of sand and gravel, then the darker bed under the water.
	// The bank: grass thins to sand before the ground even drops, then sand and pebbles down
	// to the waterline, so the meadow and the creek blend instead of meeting at a line.
	float n4 = texture(noise, wp.xz * 2.3).r;
	float near_water = 1.0 - smoothstep(1.25, 2.1 + (n2 - 0.5) * 0.7, abs(wp.z));
	col = mix(col, vec3(0.74, 0.67, 0.47), near_water * 0.55);
	float bank = smoothstep(-0.01, -0.2, wp.y);
	vec3 sand = vec3(0.8, 0.73, 0.53) * (0.85 + 0.3 * n3);
	sand = mix(sand, vec3(0.6, 0.6, 0.58), smoothstep(0.6, 0.66, n4));       // pebbles
	sand = mix(sand, vec3(0.93, 0.9, 0.82), smoothstep(0.74, 0.78, n4));     // pale stones
	col = mix(col, sand, bank);
	col = mix(col, vec3(0.3, 0.33, 0.27) * (0.8 + 0.4 * n3), smoothstep(-0.55, -1.05, wp.y));
	// Slow cloud shadow across everything, and dappled sun where the woods overhang the edges.
	float cloud = texture(noise, wp.xz * 0.011 + TIME * vec2(0.008, 0.004)).r;
	col *= mix(0.9, 1.04, smoothstep(0.34, 0.66, cloud));
	float dapple = texture(noise, wp.xz * 0.5 + TIME * vec2(0.012, 0.007)).r;
	float shade_edge = clamp(smoothstep(6.6, 10.0, abs(wp.x)) + smoothstep(15.0, 19.0, abs(wp.z)), 0.0, 1.0);
	col *= mix(1.0, mix(0.72, 1.16, smoothstep(0.42, 0.6, dapple)), shade_edge);
	// The colours above are written as seen on screen. Flat ground takes the full sun, the fill
	// and the sky at once, so it is laid in a little under and the lighting brings it back up.
	ALBEDO = pow(col, vec3(2.2)) * 0.66;
	ROUGHNESS = 0.95;
}
