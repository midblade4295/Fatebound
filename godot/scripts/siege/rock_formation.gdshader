shader_type spatial;
// The jungle's rock formations (0.31.216, rock_sculpt.gd): the painted cliff rock (ElevenLabs, tools/ground_paint.py)
// laid on triplanar so no facet stretches it, each boulder its own shade of blue-grey (COLOR.r), darker toward its
// foot where it meets the ground (COLOR.g), and the painted grass grown over every face that turns up -- a ragged
// mossy cap, as Honor of Kings' stones have. Nothing changes per frame.
render_mode cull_back, diffuse_burley, specular_disabled;

uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform float rock_scale = 3.2;
uniform float moss_scale = 6.0;
uniform vec3 tint = vec3(1.0);            // (the terrain's tint, so stone and ground sit in the same light)
uniform vec3 cool = vec3(0.86, 0.93, 1.08);
uniform vec3 warm = vec3(1.06, 1.0, 0.92);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 an = pow(abs(wnorm), vec3(3.0));
	an /= (an.x + an.y + an.z);
	vec3 r = texture(rock_tex, vec2(wpos.z, -wpos.y) / rock_scale).rgb * an.x
		+ texture(rock_tex, wpos.xz / rock_scale).rgb * an.y
		+ texture(rock_tex, vec2(wpos.x, -wpos.y) / rock_scale).rgb * an.z;
	r *= mix(cool, warm, COLOR.r);
	r *= mix(0.62, 1.04, smoothstep(0.0, 0.55, COLOR.g));          // darker at the foot
	float mn = texture(macro_tex, wpos.xz / 7.0).r;
	float up = smoothstep(0.78, 0.92, wnorm.y + (mn - 0.5) * 0.35 + COLOR.b * 0.05);
	vec3 moss = texture(moss_tex, wpos.xz / moss_scale).rgb * vec3(0.92, 1.0, 0.86);
	vec3 col = mix(r, moss, up * smoothstep(0.55, 0.85, COLOR.g + COLOR.b * 0.2) * smoothstep(0.3, 0.55, mn + 0.15));
	ALBEDO = col * tint;
	ROUGHNESS = 0.92;
}
