// The shaders the game builds from code at run time (Shader.new() + code), registered with the code text the GDScript
// produces (ShaderRegistry normalises whitespace): each maps to its port, Shaders/Resources/Shaders/gd/inline/<name>.shader
// ("Fatebound/gd/inline/<name>"). Every code string here is a constant in its script (no formatting or concatenation),
// copied verbatim (GDScript escapes resolved) -- generated from the GDScript sources; keep them in step with the game.
namespace Fatebound.Client
{
    public static class InlineShaders
    {
        public static void Register()
        {
            // gpu_probe.gd: _plain (the "terrain_plain" probe) (godot/scripts/siege/gpu_probe.gd:168)
            ShaderRegistry.RegisterInline(CODE_GPU_PROBE_PLAIN, "Fatebound/gd/inline/gpu_probe_plain");
            // wyrm_body.gd: SHADER (the Grave Wyrm's body) (godot/scripts/siege/wyrm_body.gd:22)
            ShaderRegistry.RegisterInline(CODE_WYRM_BODY_WYRM, "Fatebound/gd/inline/wyrm_body_wyrm");
            // siege_view.gd: _cloud_floor_material (godot/scripts/siege/siege_view.gd:284)
            ShaderRegistry.RegisterInline(CODE_SIEGE_VIEW_CLOUD_FLOOR, "Fatebound/gd/inline/siege_view_cloud_floor");
            // siege_view.gd: _water_hq_material (High-quality river) (godot/scripts/siege/siege_view.gd:451)
            ShaderRegistry.RegisterInline(CODE_SIEGE_VIEW_WATER_HQ, "Fatebound/gd/inline/siege_view_water_hq");
            // siege_view.gd: _build_ripples (canvas_item: the wave-field step) (godot/scripts/siege/siege_view.gd:547)
            ShaderRegistry.RegisterInline(CODE_SIEGE_VIEW_RIPPLES, "Fatebound/gd/inline/siege_view_ripples");
            // siege_view.gd: _build_water (the plain river) (godot/scripts/siege/siege_view.gd:1245)
            ShaderRegistry.RegisterInline(CODE_SIEGE_VIEW_WATER, "Fatebound/gd/inline/siege_view_water");
            // siege_view.gd: _tuft_material (High-quality swaying tufts) (godot/scripts/siege/siege_view.gd:1459)
            ShaderRegistry.RegisterInline(CODE_SIEGE_VIEW_TUFT_WIND, "Fatebound/gd/inline/siege_view_tuft_wind");
            // siege_view.gd: CAPE_SHADER (cloth capes) (godot/scripts/siege/siege_view.gd:5209)
            ShaderRegistry.RegisterInline(CODE_SIEGE_VIEW_CAPE, "Fatebound/gd/inline/siege_view_cape");
            // kill_banner.gd: SHINE_CODE (canvas_item) (godot/scripts/siege/kill_banner.gd:31)
            ShaderRegistry.RegisterInline(CODE_KILL_BANNER_SHINE, "Fatebound/gd/inline/kill_banner_shine");
            // ground_cards.gd: DECAL_SHADER (godot/scripts/siege/ground_cards.gd:82)
            ShaderRegistry.RegisterInline(CODE_GROUND_CARDS_DECAL, "Fatebound/gd/inline/ground_cards_decal");
            // herald_intro.gd: SHADE_CODE (canvas_item) (godot/scripts/app/herald_intro.gd:66)
            ShaderRegistry.RegisterInline(CODE_HERALD_INTRO_SHADE, "Fatebound/gd/inline/herald_intro_shade");
            // champion_fx.gd: LAID_SHADER (canvas_item) (godot/scripts/app/champion_fx.gd:22)
            ShaderRegistry.RegisterInline(CODE_CHAMPION_FX_LAID, "Fatebound/gd/inline/champion_fx_laid");
        }

        const string CODE_GPU_PROBE_PLAIN = @"shader_type spatial;
render_mode specular_disabled;
void fragment() { ALBEDO = vec3(0.24, 0.36, 0.2); ROUGHNESS = 0.95; }
";

        const string CODE_WYRM_BODY_WYRM = @"
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 wing_l;
uniform vec3 wing_r;
uniform vec3 neck_root;
uniform vec3 tail_root;
uniform float mid_x;
uniform float rest_yaw;
uniform float flap = 0.0;      // the wings: + raised (radians)
uniform float sweep = 0.0;     // the wings: + swept forward
uniform float pitch = 0.0;     // the neck: + head down
uniform float yaw = 0.0;       // the neck: + toward +x
uniform float reach = 0.0;     // the head thrust forward (m)
uniform float stride = 0.0;    // the legs: 1 walking
uniform float alive = 1.0;     // the idle stirring (0 once it has fallen)
uniform float glow = 1.0;      // the soul-fire in its ribs
mat3 rx(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c)); }
mat3 ry(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0.0, -s), vec3(0.0, 1.0, 0.0), vec3(s, 0.0, c)); }
mat3 rz(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, s, 0.0), vec3(-s, c, 0.0), vec3(0.0, 0.0, 1.0)); }
void vertex() {
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	float t = TIME;
	float ww = COLOR.r;
	float nk = COLOR.g;
	float tl = COLOR.b;
	float lg = (COLOR.a * 255.0 - 128.0) / 127.0;
	// breathing: the ribs rise and swell
	float core = (1.0 - ww) * (1.0 - nk) * (1.0 - tl) * (1.0 - abs(lg));
	float br = (0.5 + 0.5 * sin(t * 1.25)) * alive * core * smoothstep(0.9, 1.8, v.y) * (1.0 - smoothstep(2.6, 3.2, v.y));
	v.x += (v.x - mid_x) * 0.035 * br;
	v.y += 0.05 * br;
	if (ww > 0.0) {
		float side = v.x > mid_x ? 1.0 : -1.0;
		vec3 root = side > 0.0 ? wing_r : wing_l;
		float a = (flap + alive * (0.05 + 0.06 * sin(t * 1.25 + 0.5))) * ww * side;
		mat3 r = rz(a) * ry(-sweep * ww * side);
		v = root + r * (v - root);
		n = r * n;
	}
	if (nk > 0.0) {
		float p = pitch + alive * 0.07 * sin(t * 0.8);
		float y = rest_yaw + yaw + alive * 0.12 * sin(t * 0.45 + 1.0);
		mat3 r = ry(y * nk) * rx(p * nk);
		v = neck_root + r * (v - neck_root) + vec3(0.0, -0.25 * reach, reach) * nk;
		n = r * n;
	}
	if (tl > 0.0) {
		float d = length((v - tail_root).xz);
		float a = (0.06 + 0.1 * alive) * sin(t * 1.5 - d * 1.2) * tl;
		mat3 r = ry(a);
		v = tail_root + r * (v - tail_root);
		n = r * n;
	}
	if (lg != 0.0 && stride > 0.0) {
		float s = sin(t * 7.0) * sign(lg);
		float k = stride * abs(lg);
		v.y += k * max(0.0, s) * 0.3;
		v.z += k * s * 0.22;
	}
	VERTEX = v;
	NORMAL = normalize(n);
}
void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb;
	ROUGHNESS = 0.8;
	// the cyan in its bones burns: soul-fire
	float soul = smoothstep(0.08, 0.22, min(c.g, c.b) - c.r);
	EMISSION = c.rgb * soul * glow * (2.0 + 0.8 * sin(TIME * 2.6));
}
";

        const string CODE_SIEGE_VIEW_CLOUD_FLOOR = @"
shader_type spatial;
render_mode specular_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 tint_col : source_color;
uniform float cloud_strength = 0.2;
uniform float uv_scale = 1.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float cl = smoothstep(0.46, 0.74, texture(cloud_tex, wpos.xz / 95.0 + vec2(TIME * 0.006, TIME * 0.0035)).r);
	ALBEDO = texture(tex, UV * uv_scale).rgb * tint_col.rgb * (1.0 - cloud_strength * cl);
	ROUGHNESS = 0.95;
}
";

        const string CODE_SIEGE_VIEW_WATER_HQ = @"
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque;
uniform sampler2D ripples : filter_linear_mipmap, repeat_enable;
uniform sampler2D rip_tex : filter_linear, repeat_disable;
uniform float rip_half = 34.0;
uniform vec2 rip_texel = vec2(0.001953, 0.019231);
uniform float rip_strength = 28.0;
uniform float wake_tint = 4.5;            // crests lighter, troughs darker: how the wakes show without foam
uniform vec3 deep_col : source_color = vec3(0.05, 0.33, 0.40);
uniform vec3 shallow_col : source_color = vec3(0.26, 0.66, 0.62);
uniform vec3 sky_col : source_color = vec3(0.62, 0.80, 0.95);
uniform float glint = 0.0;
uniform float wave_height = 1.5;          // 0.31.21: the surface rises and falls with the simulated waves
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 ruv = vec2((wpos.x + rip_half) / (2.0 * rip_half), UV.y);
	float inside = step(0.0, ruv.x) * step(ruv.x, 1.0);
	float h = textureLod(rip_tex, ruv, 0.0).r * inside;
	h = (isnan(h) || isinf(h)) ? 0.0 : h;
	float edge = smoothstep(0.0, 0.1, UV2.y) * smoothstep(1.0, 0.9, UV2.y);     // held at the banks
	VERTEX.y += h * wave_height * edge;
	wpos.y += h * wave_height * edge;
}
float detail(vec2 p) {
	return texture(ripples, p * 0.11 + vec2(-TIME * 0.035, 0.0)).r * 0.6
		+ texture(ripples, p * 0.23 + vec2(-TIME * 0.05, TIME * 0.02)).r * 0.4;
}
void fragment() {
	// Flowing detail (the river runs toward -x) from finite differences of two scrolling layers.
	float e = 0.2;
	float d0 = detail(wpos.xz);
	vec2 slope = vec2(detail(wpos.xz + vec2(e, 0.0)) - d0, detail(wpos.xz + vec2(0.0, e)) - d0) / e * 0.22;
	// The simulated waves.
	vec2 ruv = vec2((wpos.x + rip_half) / (2.0 * rip_half), UV.y);
	float inside = step(0.0, ruv.x) * step(ruv.x, 1.0);
	float h = texture(rip_tex, ruv).r * inside;
	float hx = (texture(rip_tex, ruv + vec2(rip_texel.x, 0.0)).r - texture(rip_tex, ruv - vec2(rip_texel.x, 0.0)).r) * inside;
	float hz = (texture(rip_tex, ruv + vec2(0.0, rip_texel.y)).r - texture(rip_tex, ruv - vec2(0.0, rip_texel.y)).r) * inside;
	if (isnan(h + hx + hz) || isinf(h + hx + hz)) { h = 0.0; hx = 0.0; hz = 0.0; }
	slope += clamp(vec2(hx, hz) * rip_strength, vec2(-1.5), vec2(1.5));
	vec3 wn = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float edge = min(UV2.y, 1.0 - UV2.y);
	float depth = smoothstep(0.02, 0.4, edge);
	vec3 col = mix(shallow_col, deep_col, depth);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	col = mix(col, sky_col, clamp(fres * 0.3, 0.0, 0.25));     // (0.31.216: 0.5 -- the river bed shows through now)
	// No foam (Round 34, Kevin). The wakes read as light crests and dark troughs instead.
	col *= 1.0 + clamp(h, -0.12, 0.12) * wake_tint;
	ALBEDO = col;
	ALPHA = mix(0.38, 0.66, depth);              // (0.31.216: 0.58 .. 0.86: the painted river bed shows through)
	ROUGHNESS = 0.16;                 // 0.30.11: was 0.05 / 0.75 -- the sun's glare spread white over the wide lake
	SPECULAR = 0.35;
	float sg = texture(ripples, wpos.xz * 0.19 + vec2(-TIME * 0.09, TIME * 0.05)).r * texture(ripples, wpos.xz * 0.13 + vec2(TIME * 0.07, -TIME * 0.04)).r;
	EMISSION = vec3(1.0, 0.97, 0.88) * smoothstep(0.58, 0.64, sg) * glint;
}
";

        const string CODE_SIEGE_VIEW_RIPPLES = @"
shader_type canvas_item;
render_mode blend_disabled;
uniform sampler2D prev : filter_nearest, repeat_disable;
uniform vec2 texel;
uniform vec2 cell_m;
uniform vec4 drops[16];
uniform int drop_count = 0;
uniform float damping = 0.989;            // wakes trail longer (Round 34)
void fragment() {
	vec4 p = texture(prev, UV);
	float n = texture(prev, UV + vec2(texel.x, 0.0)).r + texture(prev, UV - vec2(texel.x, 0.0)).r
		+ texture(prev, UV + vec2(0.0, texel.y)).r + texture(prev, UV - vec2(0.0, texel.y)).r;
	float h = (n * 0.5 - p.g) * damping;
	for (int i = 0; i < 16; i++) {
		if (i >= drop_count) { break; }
		vec2 d = (UV - drops[i].xy) / texel * cell_m;
		float r = drops[i].z;
		h += drops[i].w * exp(-dot(d, d) / (r * r));
	}
	h *= smoothstep(0.0, 0.03, UV.y) * smoothstep(1.0, 0.97, UV.y);
	// 0.30.11: the lake made the simulated patch 5x bigger. A bad cell (NaN/inf) would spread and the water would
	// render white (Kevin's screenshot): clamp and scrub every step.
	h = (isnan(h) || isinf(h)) ? 0.0 : clamp(h, -0.6, 0.6);
	float pr = (isnan(p.r) || isinf(p.r)) ? 0.0 : clamp(p.r, -0.6, 0.6);
	COLOR = vec4(h, pr, 0.0, 1.0);
}
";

        const string CODE_SIEGE_VIEW_WATER = @"
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque;
uniform sampler2D ripples : filter_linear_mipmap, repeat_enable;
uniform float glint = 0.0;
void fragment() {
	vec2 w = UV * vec2(18.0, 1.0);
	float a = texture(ripples, w * 0.35 + vec2(TIME * 0.05, TIME * 0.02)).r;
	float b = texture(ripples, w * 0.21 - vec2(TIME * 0.03, 0.0)).r;
	float n = a * 0.6 + b * 0.4;
	float shore = 1.0 - smoothstep(0.0, 0.16, min(UV2.y, 1.0 - UV2.y));
	vec3 deep = vec3(0.06, 0.36, 0.44);            // (0.31.216: teal over the painted bed; was a solid blue)
	vec3 shallow = vec3(0.24, 0.64, 0.62);
	vec3 col = mix(deep, shallow, smoothstep(0.35, 0.75, n));
	col *= 1.0 - shore * 0.18;                     // no foam (Round 34): the banks just shade a little
	ALBEDO = col;
	ALPHA = mix(0.5, 0.72, smoothstep(0.0, 0.4, min(UV2.y, 1.0 - UV2.y)));
	ROUGHNESS = 0.18;
	SPECULAR = 0.35;                  // 0.30.11: was 0.6 (see the high-quality water)
	// Sun glints (High-quality graphics): sparse sparkles where two scrolling layers line up; bright enough to glow.
	float sg = texture(ripples, w * 1.3 + vec2(-TIME * 0.09, TIME * 0.05)).r * texture(ripples, w * 0.9 + vec2(TIME * 0.07, -TIME * 0.04)).r;
	EMISSION = vec3(1.0, 0.97, 0.88) * smoothstep(0.58, 0.64, sg) * glint;      // sparse: only the brightest crossings
}
";

        const string CODE_SIEGE_VIEW_TUFT_WIND = @"
shader_type spatial;
render_mode cull_disabled, vertex_lighting, specular_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform bool use_tex = false;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y / 0.5, 0.0, 1.0);
	float gust = sin(TIME * 1.3 + wp.x * 0.18 + wp.z * 0.11) * 0.5 + 0.5;
	float flutter = sin(TIME * 4.2 + wp.x * 1.3 + wp.z * 0.9);
	float sway = (gust * 0.10 + flutter * 0.025) * h;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.5;
}
void fragment() {
	vec3 c = albedo_col.rgb;
	if (use_tex) { c *= texture(albedo_tex, UV).rgb; }
	ALBEDO = c;
}
";

        const string CODE_SIEGE_VIEW_CAPE = @"
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 0.5;
uniform vec3 offs[12];
void vertex() {
	// model-space position -> place on the 3 x 4 grid (shoulders at y 1.2, hem at 0.12, 0.94 m across)
	float u = clamp((VERTEX.x + 0.47) / 0.94, 0.0, 1.0) * 2.0;
	float v = clamp((1.2 - VERTEX.y) / 1.08, 0.0, 1.0) * 3.0;
	int c0 = int(min(floor(u), 1.0));
	int r0 = int(min(floor(v), 2.0));
	float fu = u - float(c0);
	float fv = v - float(r0);
	vec3 a = mix(offs[r0 * 3 + c0], offs[r0 * 3 + c0 + 1], fu);
	vec3 b = mix(offs[(r0 + 1) * 3 + c0], offs[(r0 + 1) * 3 + c0 + 1], fu);
	VERTEX += mix(a, b, fv);
}
void fragment() {
	vec4 t = texture(albedo_tex, UV) * albedo;
	ALBEDO = t.rgb;
	ROUGHNESS = roughness;
}
";

        const string CODE_KILL_BANNER_SHINE = @"
shader_type canvas_item;
uniform float sweep = -1.0;
uniform float width = 0.11;
uniform float strength = 0.75;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float d = (UV.x + UV.y * 0.4) / 1.4 - sweep;
	float b = smoothstep(width, 0.0, abs(d)) * strength;
	c.rgb += vec3(1.0, 0.95, 0.82) * b * c.a;
	COLOR = c;
}
";

        const string CODE_GROUND_CARDS_DECAL = @"
shader_type spatial;
// (ground_cards.gd) a painted mark laid over the ground: the picture's own alpha, lit as the ground is
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint = vec3(1.0);
uniform float spin = 0.0;
void fragment() {
	vec2 q = UV - 0.5;
	q = mat2(vec2(cos(spin), sin(spin)), vec2(-sin(spin), cos(spin))) * q + 0.5;
	vec4 c = texture(tex, q);
	ALBEDO = c.rgb * tint;
	ALPHA = c.a * step(0.0, q.x) * step(q.x, 1.0) * step(0.0, q.y) * step(q.y, 1.0);
	ROUGHNESS = 0.95;
}
";

        const string CODE_HERALD_INTRO_SHADE = @"
shader_type canvas_item;
uniform vec2 size = vec2(1.0, 1.0);
uniform vec4 hole = vec4(0.0);                 // x, y, w, h in px (w 0: none)
uniform float radius = 18.0;
uniform float soft = 8.0;
uniform vec4 shade : source_color = vec4(0.0, 0.01, 0.04, 0.6);
void fragment() {
	vec2 p = UV * size;
	float a = shade.a;
	if (hole.z > 0.5) {
		vec2 h = hole.zw * 0.5;
		float r = min(radius, min(h.x, h.y));
		vec2 q = abs(p - (hole.xy + h)) - (h - vec2(r));
		float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
		a *= smoothstep(-1.0, soft, d);
	}
	COLOR = vec4(shade.rgb, a);
}
";

        const string CODE_CHAMPION_FX_LAID = @"shader_type canvas_item;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
	float l = texture(TEXTURE, UV).r;
	COLOR = vec4(tint.rgb * (0.55 + 0.6 * l), tint.a * smoothstep(0.03, 0.45, l));
}
";
    }
}
