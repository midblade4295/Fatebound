// Puffy toon clouds built from sphere clusters. Unshaded so they stay bright
// and cost almost nothing: brightness comes from the normal alone
// (white tops, cool undersides, warm sun-facing side, soft white rim).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform vec4 top_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 shade_color : source_color = vec4(0.62, 0.76, 0.95, 1.0);
uniform vec4 sun_tint : source_color = vec4(1.0, 0.95, 0.82, 1.0);
uniform vec3 sun_direction = vec3(0.4, 0.8, 0.3);

varying vec3 world_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	float top = smoothstep(-0.55, 0.45, n.y);
	// Two soft steps instead of a smooth gradient keeps the painted look.
	top = floor(top * 3.0 + 0.5) / 3.0;
	vec3 color = mix(shade_color.rgb, top_color.rgb, top);
	float sun = smoothstep(0.35, 0.8, dot(n, normalize(sun_direction)));
	color = mix(color, sun_tint.rgb, sun * 0.5);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	ALBEDO = mix(color, vec3(1.0), rim * 0.35);
}
