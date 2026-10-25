shader_type spatial;
// The Rift's painted plants (0.31.216, Kevin: "need new models for grass"): cards cut from ElevenLabs' painted sheets
// (tools/ground_paint.py) -- the grass clumps in the fields, the brush you hide in, the flower patches lying on the
// grass. A MultiMesh; each instance picks its picture from the sheet (INSTANCE_CUSTOM.x: the cell, counted across
// then down), its shade (.y) and its beat in the breeze (.z). Lit as the ground is (straight up), so a card's back
// is never dark; cut out at the picture's edge (alpha scissor: no sorting).
render_mode cull_disabled, diffuse_burley, specular_disabled;

uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 cells = vec2(4.0, 2.0);       // the sheet's grid (across, down)
uniform float sway = 0.12;                 // how far a card's top moves (its own units: a card is 1 tall)
uniform float speed = 1.4;
uniform vec3 tint = vec3(1.0);
uniform float cut = 0.45;

varying float shade;

void vertex() {
	float cell = INSTANCE_CUSTOM.x;
	vec2 c = vec2(mod(cell, cells.x), floor(cell / cells.x));
	UV = (c + UV) / cells;
	shade = 0.86 + 0.28 * INSTANCE_CUSTOM.y;
	float k = (1.0 - (UV.y * cells.y - c.y));            // 0 at the card's foot .. 1 at its top
	k = k * k;
	vec3 at = MODEL_MATRIX[3].xyz;
	float t = TIME * speed + INSTANCE_CUSTOM.z * 6.283 + at.x * 0.21 + at.z * 0.17;
	float gust = 0.6 + 0.4 * sin(TIME * 0.7 + at.x * 0.05 + at.z * 0.04);
	VERTEX.x += (sin(t) + 0.3 * sin(t * 2.7 + 1.3)) * sway * k * gust;
	VERTEX.z += cos(t * 0.9 + 0.7) * sway * 0.5 * k * gust;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec4 s = texture(sheet, UV);
	if (s.a < cut) {
		discard;
	}
	ALBEDO = s.rgb * shade * tint;
	ROUGHNESS = 0.95;
}
