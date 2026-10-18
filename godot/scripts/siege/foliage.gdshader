shader_type spatial;
// The Rift's trees and bushes (0.31.173, Kevin: "I want better trees and bush models"): Meshy models
// (tools/foliage_prep.py) drawn as MultiMeshes. One painted texture each; the canopy sways in the breeze -- nothing
// below sway_from of the model's height moves, the top the most, each plant on its own beat (from where it stands);
// a glow mask (the glowing fruits, the blue flowers) shines in the texture's own colour.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D glow_tex : hint_default_black, filter_linear_mipmap;
uniform float glow_energy = 0.0;
uniform float height = 4.0;           // the model's height (its own units: metres before the instance's scale)
uniform float sway = 0.12;            // how far the top moves (model units)
uniform float sway_from = 0.35;       // the share of the height that stays still (the trunk)
uniform float speed = 1.2;

void vertex() {
	float k = clamp((VERTEX.y / height - sway_from) / (1.0 - sway_from), 0.0, 1.0);
	k *= k;
	vec3 at = MODEL_MATRIX[3].xyz;                    // (a MultiMesh instance's own place)
	float t = TIME * speed + at.x * 0.37 + at.z * 0.23;
	VERTEX.x += (sin(t) + 0.35 * sin(t * 2.3 + 1.1)) * sway * k;
	VERTEX.z += cos(t * 0.8 + 1.7) * sway * 0.6 * k;
}

void fragment() {
	vec3 col = texture(albedo_tex, UV).rgb;
	ALBEDO = col;
	ROUGHNESS = 0.9;
	EMISSION = col * texture(glow_tex, UV).r * glow_energy;
}
