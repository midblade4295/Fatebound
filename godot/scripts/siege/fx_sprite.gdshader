shader_type spatial;
// The weapon effects' sprites (0.31.100): a grayscale painted sprite (assets/vfx/weapon: brightness in R) added in the
// particle's colour, its brightest part going white-hot (core). Billboarded like BaseMaterial3D's particle billboard
// (the particle's spin in INSTANCE_CUSTOM.x), or laid flat in its own plane (lie_flat: a halo). A grid x grid atlas gives a
// variant per particle by its animation offset (INSTANCE_CUSTOM.z). A static sprite (a mesh, not a particle) turns
// (spin, rad/s) and pulses.
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D tex : filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float grid = 1.0;
uniform float core = 0.6;
uniform float energy = 1.0;
uniform float spin = 0.0;
uniform float pulse = 0.0;
uniform bool lie_flat = false;

void vertex() {
	float a = INSTANCE_CUSTOM.x + TIME * spin;
	mat4 rot = mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	if (lie_flat) {
		VERTEX = (rot * vec4(VERTEX, 1.0)).xyz;
	} else {
		mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
		mat4 sc = mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * mw * rot * sc;
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
	if (grid > 1.5) {
		float n = grid * grid;
		float f = min(floor(INSTANCE_CUSTOM.z * n), n - 1.0);
		UV = (UV + vec2(mod(f, grid), floor(f / grid))) / grid;
	}
}

void fragment() {
	float l = texture(tex, UV).r;
	float p = 1.0 - pulse + pulse * (0.5 + 0.5 * sin(TIME * 2.6));
	vec3 c = mix(COLOR.rgb * tint.rgb, vec3(1.0), smoothstep(0.55, 1.0, l) * core);
	// the colour goes in ALBEDO and the strength in ALPHA (blend_add adds ALBEDO * ALPHA): a transparent viewport (the
	// Locker's showcase) then gets alpha only where the sprite is, not a black square
	ALBEDO = c * energy;
	ALPHA = clamp(l * COLOR.a * tint.a * p, 0.0, 1.0);
}
