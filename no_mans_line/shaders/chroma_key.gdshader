shader_type canvas_item;
// Quick background removal for a sheet that still has its flat backdrop.
// Assign a ShaderMaterial with this shader to any Sprite2D / AnimatedSprite2D /
// TextureRect / TextureButton that draws the raw sheet.
//
// The project does NOT use this shader: its sheets were cleaned once with
// tools/strip_background.gd instead, because a colour key also deletes every
// pixel INSIDE a sprite that happens to match the backdrop (coat shading,
// bunker timber, the mud in the background banner).

// Measured backdrop of the two sheets is #323232, not #373737.
uniform vec3 key_color : source_color = vec3(0.196, 0.196, 0.196);
// Pixels closer than this to key_color become fully transparent.
uniform float threshold : hint_range(0.0, 1.0) = 0.05;
// Width of the fade from transparent to opaque (hides JPEG fringes).
uniform float softness : hint_range(0.0, 0.5) = 0.05;

void fragment() {
	// COLOR already holds the texture sample (times the node's tint), so only
	// its alpha needs changing.
	float color_distance = distance(texture(TEXTURE, UV).rgb, key_color);
	COLOR.a *= smoothstep(threshold, threshold + softness, color_distance);
}
