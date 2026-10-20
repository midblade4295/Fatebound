shader_type canvas_item;
// 0.31.193 (Kevin: "make the flags on side blow around"): one of the title's two flags (title_logo.gd), waving. The
// cloth is moved by its distance from its pole (the pole and where the cloth meets it hold still): a wave running out to
// the cloth's free edge, up and down, a little pull toward the pole on each crest, and the folds lit and shaded with it.
// All in the texture's own px: pole is the pole's line as (y, x) points by y (tools/build_title_logo.py prints them).
uniform vec2 tex_px = vec2(160.0, 370.0);
uniform vec2 pole[10];
uniform int pole_n = 2;
uniform float side = 1.0;      // 1: the cloth lies to the left of its pole; -1: to the right
uniform float amp = 6.0;       // px of swing at the cloth's far edge (0: still)
uniform float wave = 95.0;     // px from crest to crest
uniform float speed = 1.1;     // waves a second
uniform float reach = 140.0;   // px from the pole to the full swing
uniform float t = 0.0;         // the clock (title_logo.gd runs it; held for Reduce Motion)

float pole_x(float y) {
	float x = pole[0].y;
	for (int i = 0; i < 9; i++) {
		if (i + 1 < pole_n && y >= pole[i].x) {
			float k = clamp((y - pole[i].x) / max(pole[i + 1].x - pole[i].x, 0.001), 0.0, 1.0);
			x = mix(pole[i].y, pole[i + 1].y, k);
		}
	}
	return x;
}

// (fragment()'s COLOR comes in already multiplied by the texture at UV -- the modulate alone is the vertex's; 0.31.194:
// the flag used to multiply by the former, darkening it and ghosting its undisplaced self through it)
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 p = UV * tex_px;
	float d = (pole_x(p.y) - p.x) * side;
	float w = smoothstep(6.0, 40.0, d) * (0.3 + 0.7 * clamp(d / reach, 0.0, 1.0));
	float ph = 6.2831853 * (d / wave - speed * t);
	float gust = 0.8 + 0.2 * sin(t * 0.9);
	float a = amp * gust * w;
	vec2 disp = vec2(side * a * 0.3 * (1.0 - cos(ph)), a * sin(ph));
	vec4 c = texture(TEXTURE, (p - disp) / tex_px);
	c.rgb *= 1.0 + 0.03 * a * cos(ph);
	COLOR = c * tint;
}
