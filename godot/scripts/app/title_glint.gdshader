shader_type canvas_item;
// 0.31.141: a gold glint sweeping across the title's lettering (title_screen.gd sets it on title_logo.gd's base layer).
// `sweep` is the bright band's place along the diagonal: below 0 or above 1 it is off the letters.
uniform float sweep = -1.0;

void fragment() {
	float d = (UV.x + UV.y * 0.5) / 1.5;
	float band = smoothstep(0.075, 0.0, abs(d - sweep));
	COLOR.rgb += vec3(1.0, 0.95, 0.78) * band * 0.8 * COLOR.a;
}
