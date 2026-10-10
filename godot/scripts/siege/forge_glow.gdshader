shader_type spatial;
// The Forge's stars on a weapon (0.31.93): an additive pass over the weapon's own material (next_pass), so the model,
// its texture and its shadows are untouched. One material per (stars, colour), shared by every piece that wears it.
//   stars 1 Polished: a sheen in the rarity's colour that sweeps up the weapon, a bright rim
//   stars 2 Runed:    + glowing rune bands that drift along it and pulse
//   stars 3 Ascended: everything brighter, in the element's colour (the aura and trail are particles, siege_view.gd)
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.75, 0.3, 1.0);
uniform float sheen = 0.6;
uniform float runes = 0.0;
uniform float boost = 1.0;
uniform float span = 2.0;          // the piece's length (model units), so the bands keep their size on any weapon

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, 4.0);
	float y = lp.y / max(span, 0.01);
	// a soft band sweeping up the weapon every 2.6 s
	float sweep = smoothstep(0.09, 0.0, abs(fract(y * 0.8 - TIME * 0.38) - 0.5));
	float glow = sheen * (rim * 0.6 + sweep * 0.5);
	if (runes > 0.0) {
		// rune bands: thin bright lines, broken into glyph-like dashes, drifting slowly, pulsing
		float bands = fract(y * 9.0 + TIME * 0.12);
		float line = smoothstep(0.08, 0.0, abs(bands - 0.5) - 0.02);
		float dash = step(0.45, fract(sin(floor(y * 9.0 + TIME * 0.12) * 12.9898 + floor(lp.x * 14.0 + lp.z * 14.0) * 78.233) * 43758.5453));
		float pulse = 0.65 + 0.35 * sin(TIME * 2.4 + y * 6.0);
		glow += runes * 0.45 * line * dash * pulse * (0.4 + 0.6 * facing);
	}
	ALBEDO = tint.rgb * glow * boost * 0.5;       // (the scene's exposure lifts an unshaded add a lot)
	ALPHA = 1.0;
}
