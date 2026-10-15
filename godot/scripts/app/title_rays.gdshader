shader_type canvas_item;
render_mode blend_add;
// 0.31.141: the light bursting out from behind the title on the title screen (title_screen.gd): soft rays turning
// slowly round the middle, fading out to the edge. `power` 0 draws nothing (the screen keeps it in from the first frame
// so it is compiled before the show starts).
uniform float spin = 0.0;
uniform float power = 0.0;
uniform vec3 tint = vec3(1.0, 0.76, 0.38);

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p) * 2.0;
	float a = atan(p.y, p.x);
	float rays = pow(0.5 + 0.5 * sin(a * 9.0 + spin), 4.0) * 0.75 + pow(0.5 + 0.5 * sin(a * 5.0 - spin * 1.6 + 1.3), 6.0) * 0.6;
	float fall = smoothstep(1.0, 0.25, r) * smoothstep(0.0, 0.18, r);
	COLOR = vec4(tint * rays * fall * power, 1.0);
}
