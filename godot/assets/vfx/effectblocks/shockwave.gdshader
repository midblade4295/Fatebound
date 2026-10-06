//shockwave.gdshader -- from the EffectBlocks pack (PolyBlocks), adapted for Fatebound (0.31.56):
// the pack's version bends the screen outward from the SCREEN's centre, which only looks right when the blast is in
// the middle of the view; this one bends it outward from the ring's own centre on screen, so a blast anywhere ripples
// the scene round itself. The bend is strongest across the middle of the ring's band and fades as the ring grows.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float distortion_intensity : hint_range(0.0, 1.0) = 0.1;
uniform float noise_influence : hint_range(0.0, 1.0) = 0.273;
instance uniform float fade = 1.0;

varying vec4 center_clip;
varying vec4 frag_clip;

float random(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453123);
}

void vertex() {
	center_clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0));
	frag_clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	// the ring's centre and this fragment, both in the same screen space; their difference is "outward"
	vec2 c = center_clip.xy / center_clip.w;
	vec2 f = frag_clip.xy / frag_clip.w;
	vec2 out_dir = f - c;
	float len_d = length(out_dir);
	out_dir = len_d > 0.0001 ? out_dir / len_d : vec2(0.0);
	out_dir.y = -out_dir.y;                       // clip space y is up, screen UV y is down
	float noise = 1.0 + (random(SCREEN_UV) * 2.0 - 1.0) * noise_influence;
	float band = pow(clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 0.6);   // strongest mid-band
	vec2 offset = out_dir * distortion_intensity * 0.55 * noise * band * fade;
	vec3 col = textureLod(screen_texture, SCREEN_UV + offset, 0.0).rgb;
	ALBEDO = col;
	ALPHA = clamp(band * fade * 1.4, 0.0, 1.0);
}
