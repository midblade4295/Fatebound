// Port of the inline canvas shader siege_view.gd's _build_ripples builds (one step of the river's wave equation, drawn
// by a ColorRect into one of two ping-ponging SubViewports: R = height now, G = height a step ago; wading units and
// blasts push on it through drops[]).
// canvas_item, render_mode blend_disabled -> Blend Off. prev (filter_nearest, repeat_disable) is read as stored: it is
// the other SubViewport's float field, not an image (no sRGB re-encoding). COLOR is written outright.
// NEEDS from the renderer (see the report): 2D SubViewports rendered into textures (prev / the water's rip_tex), with a
// float target (Godot: use_hdr_2d) -- the heights are signed; and the ColorRect's UV 0..1 across it (Godot's UV for an
// untextured rect). drops[16] is a uniform array (SetVectorArray); drop_count is a float.
Shader "Fatebound/gd/inline/siege_view_ripples"
{
    Properties
    {
        [HideInInspector] _MainTex ("Texture", 2D) = "white" {}
        [HideInInspector] _SrgbTex ("Texture is sRGB", Float) = 1
        [HideInInspector] _AlphaTex ("Texture is alpha only", Float) = 0
        prev ("prev", 2D) = "black" {}
        texel ("texel", Vector) = (0, 0, 0, 0)
        cell_m ("cell_m", Vector) = (0, 0, 0, 0)
        drop_count ("drop_count", Float) = 0
        damping ("damping", Float) = 0.989
    }
    SubShader
    {
        Tags { "Queue" = "Transparent" "IgnoreProjector" = "True" "RenderType" = "Transparent" }
        Cull Off
        Lighting Off
        ZWrite Off
        ZTest Always
        Blend Off

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "../../FateboundCanvas.hlsl"

            Texture2D prev;
            SamplerState fb_point_clamp_sampler;       // (Godot's hints: filter_nearest, repeat_disable)
            float2 texel;
            float2 cell_m;
            float4 drops[16];
            float drop_count;
            float damping;

            float4 ripple_prev(float2 godotUV)
            {
                return prev.SampleLevel(fb_point_clamp_sampler, FB_CanvasUnityUV(godotUV), 0.0);
            }

            float ripple_bad(float x)
            {
                return (isnan(x) || isinf(x)) ? 1.0 : 0.0;
            }

            FBCanvasV2F vert(FBCanvasIn v) { return FB_CanvasVert(v); }

            float4 frag(FBCanvasV2F i) : SV_Target
            {
                FB_CanvasClip(i);
                float2 UV = FB_CanvasGodotUV(i.uv0);
                float4 p = ripple_prev(UV);
                float n = ripple_prev(UV + float2(texel.x, 0.0)).r + ripple_prev(UV - float2(texel.x, 0.0)).r
                    + ripple_prev(UV + float2(0.0, texel.y)).r + ripple_prev(UV - float2(0.0, texel.y)).r;
                float h = (n * 0.5 - p.g) * damping;
                int count = (int)drop_count;
                for (int k = 0; k < 16; k++)
                {
                    if (k >= count) { break; }
                    float2 d = (UV - drops[k].xy) / texel * cell_m;
                    float r = drops[k].z;
                    h += drops[k].w * exp(-dot(d, d) / (r * r));
                }
                h *= smoothstep(0.0, 0.03, UV.y) * smoothstep(1.0, 0.97, UV.y);
                // A bad cell (NaN/inf) would spread: clamp and scrub every step.
                h = ripple_bad(h) > 0.5 ? 0.0 : clamp(h, -0.6, 0.6);
                float pr = ripple_bad(p.r) > 0.5 ? 0.0 : clamp(p.r, -0.6, 0.6);
                return float4(h, pr, 0.0, 1.0);
            }
            ENDCG
        }
    }
}
