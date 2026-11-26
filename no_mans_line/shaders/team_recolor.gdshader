shader_type canvas_item;
// Repaints the horizon-blue uniform as field grey-green.
//
// The unit sheet has no Red walk cycle and no Red Trench Raiders, so Red
// borrows the Blue frames for those and Unit.gd turns this shader on while a
// borrowed animation is playing (strength 1) and off for real Red art (0).

uniform float strength : hint_range(0.0, 1.0) = 1.0;

// In fragment() COLOR already contains the texture sample, so the node's own
// tint is carried over from vertex() to re-apply it to the repainted pixel.
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	// The "horizon blue" in the art is a very soft blue-grey, so the test is
	// simply "is blue a little stronger than red?". Coats and helmets pass.
	// Skin, khaki trousers, leather and wood are redder than blue: untouched.
	float blueness = smoothstep(0.004, 0.035, pixel.b - pixel.r);
	// Keep the painted shading (luminance) and swap the hue for olive green.
	float luma = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
	vec3 field_grey = luma * vec3(0.95, 1.03, 0.76);
	pixel.rgb = mix(pixel.rgb, field_grey, blueness * strength);
	COLOR = pixel * tint;
}
