// Port of res://scripts/app/ui_skin.gdshader (the menu skin, skin.gd: one rounded box as a signed distance, crisp at any
// density -- outline, gradient rim, fill gradient times an optional tiling pattern, lip, gloss, bevel, drop shadow,
// outer glow).
// canvas_item, render_mode unshaded (no 2D lights anyway), blend_mix -> Godot's canvas mix blend. source_color uniforms
// are Vector properties (Godot's 2D renderer doesn't linearise them); `pattern` is a game image (sRGB texture): its
// sample is encoded back (FB_CANVAS_SRGB), with its own sampler hints (trilinear, repeat).
// NOT AS GODOT -- VERTEX: Godot's vertex() takes VERTEX in the node's local space (`local = VERTEX`); our 2D vertices
// arrive already in canvas pixels. skin.gd draws exactly one rect, Rect2(-pad, -pad, rect_size + 2 * pad), untextured,
// whose UV runs 0..1 across it in Godot, so local = UV * (rect_size + 2 * pad) - pad (exact, also under rotation or
// scale). pad is skin.gd's `pad` (16, never changed by the game): FB_SKIN_PAD. This needs the GUI's DrawList.AddRect to
// give an untextured rect Godot's UVs (0..1 over the rect); it currently emits (0, 0) -- see the report.
Shader "Fatebound/gd/scripts/app/ui_skin"
{
    Properties
    {
        [HideInInspector] _MainTex ("Texture", 2D) = "white" {}
        [HideInInspector] _SrgbTex ("Texture is sRGB", Float) = 1
        [HideInInspector] _AlphaTex ("Texture is alpha only", Float) = 0
        rect_size ("rect_size", Vector) = (100, 50, 0, 0)
        radius ("radius", Float) = 16
        outline ("outline", Float) = 2
        outline_color ("outline_color", Vector) = (0.165, 0.086, 0.016, 1.0)
        rim ("rim", Float) = 0
        rim_a ("rim_a", Vector) = (1.0, 0.957, 0.784, 1.0)
        rim_b ("rim_b", Vector) = (0.969, 0.804, 0.333, 1.0)
        rim_c ("rim_c", Vector) = (0.725, 0.463, 0.106, 1.0)
        fill_top ("fill_top", Vector) = (0.23, 0.38, 0.84, 1.0)
        fill_bottom ("fill_bottom", Vector) = (0.03, 0.05, 0.17, 1.0)
        pattern ("pattern", 2D) = "white" {}
        pattern_px ("pattern_px", Float) = 190
        pattern_mix ("pattern_mix", Float) = 0
        pattern_gain ("pattern_gain", Float) = 1
        pattern_luma ("pattern_luma", Float) = 0
        lip ("lip", Float) = 0
        lip_color ("lip_color", Vector) = (0.0, 0.0, 0.0, 1.0)
        gloss ("gloss", Float) = 0
        bevel ("bevel", Float) = 0.18
        shadow_y ("shadow_y", Float) = 5
        shadow_alpha ("shadow_alpha", Float) = 0.5
        shadow_soft ("shadow_soft", Float) = 5
        glow ("glow", Float) = 0
        glow_color ("glow_color", Vector) = (1.0, 0.84, 0.35, 0.8)
        pressed ("pressed", Float) = 0
        dim ("dim", Float) = 0
    }
    SubShader
    {
        Tags { "Queue" = "Transparent" "IgnoreProjector" = "True" "RenderType" = "Transparent" }
        Cull Off
        Lighting Off
        ZWrite Off
        ZTest Always
        Blend SrcAlpha OneMinusSrcAlpha, One OneMinusSrcAlpha

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "../../../FateboundCanvas.hlsl"

            #define FB_SKIN_PAD 16.0     // skin.gd's pad: the quad is drawn pad px larger than the rect on every side

            float2 rect_size;
            float radius;
            float outline;
            float4 outline_color;
            float rim;
            float4 rim_a;
            float4 rim_b;
            float4 rim_c;
            float4 fill_top;
            float4 fill_bottom;
            Texture2D pattern;
            SamplerState fb_trilinear_repeat_sampler;      // (Godot's hints: filter_linear_mipmap, repeat_enable)
            float pattern_px;
            float pattern_mix;
            float pattern_gain;
            float pattern_luma;
            float lip;
            float4 lip_color;
            float gloss;
            float bevel;
            float shadow_y;
            float shadow_alpha;
            float shadow_soft;
            float glow;
            float4 glow_color;
            float pressed;
            float dim;

            float skin_sdbox(float2 p, float2 b, float r)
            {
                float2 q = abs(p) - b + r;
                return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
            }

            float4 skin_over(float4 top, float4 under)
            {
                float a = top.a + under.a * (1.0 - top.a);
                if (a <= 0.0001)
                {
                    return float4(0.0, 0.0, 0.0, 0.0);
                }
                float3 c = (top.rgb * top.a + under.rgb * under.a * (1.0 - top.a)) / a;
                return float4(c, a);
            }

            FBCanvasV2F vert(FBCanvasIn v) { return FB_CanvasVert(v); }

            float4 frag(FBCanvasV2F i) : SV_Target
            {
                FB_CanvasClip(i);
                float2 UV = FB_CanvasGodotUV(i.uv0);
                float2 local = UV * (rect_size + 2.0 * FB_SKIN_PAD) - FB_SKIN_PAD;     // Godot's VERTEX (see the header)
                float2 sz = rect_size;
                float2 lp = local - float2(0.0, pressed * 2.0);
                float2 hs = sz * 0.5;
                float2 p = lp - hs;
                float r = min(radius, min(hs.x, hs.y));
                float d = skin_sdbox(p, hs, r);
                float aa = max(fwidth(d), 0.0001);
                float4 col = float4(0.0, 0.0, 0.0, 0.0);
                if (shadow_alpha > 0.0)
                {
                    float ds = skin_sdbox(p - float2(0.0, shadow_y * (1.0 - pressed * 0.7)), hs, r);
                    float s = 1.0 - smoothstep(-shadow_soft, shadow_soft, ds);
                    col = float4(0.0, 0.0, 0.0, s * shadow_alpha);
                }
                if (glow > 0.0)
                {
                    float g = glow_color.a * exp(-max(d, 0.0) * 2.2 / glow) * step(0.0, d);
                    col = skin_over(float4(glow_color.rgb, g), col);
                }
                float t = clamp(lp.y / sz.y, 0.0, 1.0);
                float4 fill = lerp(fill_top, fill_bottom, t);
                if (pattern_mix > 0.0)
                {
                    float3 pt = FB_CANVAS_SRGB(pattern.Sample(fb_trilinear_repeat_sampler, FB_CanvasUnityUV(lp / pattern_px))).rgb;
                    pt = lerp(pt, dot(pt, float3(0.299, 0.587, 0.114)).xxx, pattern_luma) * pattern_gain;
                    fill.rgb = lerp(fill.rgb, fill.rgb * pt, pattern_mix);
                }
                float inner = -d;
                float edge = outline + rim;
                if (lip > 0.0)
                {
                    float lh = lip * (1.0 - pressed * 0.65);
                    float ly = smoothstep(sz.y - edge - lh - 0.8, sz.y - edge - lh + 0.8, lp.y);
                    fill.rgb = lerp(fill.rgb, lip_color.rgb, ly);
                }
                if (gloss > 0.0)
                {
                    float gh = (sz.y - edge * 2.0 - lip) * 0.42;
                    float2 gc = float2(hs.x, edge + 2.0 + gh * 0.5);
                    float gd = skin_sdbox(lp - gc, float2(hs.x - edge - 5.0, gh * 0.5), min(r, gh * 0.5));
                    float g = (1.0 - smoothstep(-1.5, 1.5, gd)) * (1.0 - 0.55 * clamp((lp.y - edge) / max(gh, 1.0), 0.0, 1.0));
                    fill.rgb = lerp(fill.rgb, 1.0, g * 0.32 * gloss);
                }
                // bevel: a light line just inside the top edge, a dark one inside the bottom
                float bv = 1.0 - smoothstep(0.0, 3.0, inner - edge);
                fill.rgb += bevel * bv * (0.6 - 1.2 * t);
                float3 rimc = t < 0.5 ? lerp(rim_a.rgb, rim_b.rgb, t * 2.0) : lerp(rim_b.rgb, rim_c.rgb, (t - 0.5) * 2.0);
                // a thin bright line along the inside of the rim
                float rl = 1.0 - smoothstep(0.0, 1.2, abs(inner - (outline + rim * 0.35)));
                rimc = lerp(rimc, float3(1.0, 0.98, 0.9), rl * 0.35 * (1.0 - t));
                float in_body = smoothstep(-aa, aa, inner);
                float in_rim = smoothstep(outline - aa, outline + aa, inner);
                float in_fill = smoothstep(edge - aa, edge + aa, inner);
                float4 c = float4(outline_color.rgb, outline > 0.0 ? 1.0 : 0.0);
                if (rim > 0.0)
                {
                    c = lerp(c, float4(rimc, 1.0), in_rim);
                }
                if (outline <= 0.0 && rim <= 0.0)
                {
                    c = fill;
                }
                else
                {
                    c = lerp(c, fill, in_fill);
                }
                c.rgb = lerp(c.rgb, c.rgb * 0.55, dim);
                c.a *= in_body;
                return skin_over(c, col);
            }
            ENDCG
        }
    }
}
