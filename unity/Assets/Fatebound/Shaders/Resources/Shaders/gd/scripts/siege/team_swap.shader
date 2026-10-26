// Port of res://scripts/siege/team_swap.gdshader (a Meshy building in its owner's colours from one texture, the
// castle kits): the blue team's texture as painted; for red its saturated blues turn deep red, while nobody holds it
// they go grey-white; lit like a StandardMaterial3D (roughness_v, specular_v) with an emission mask in glow_color.
// render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx -> opaque, lit.
// Nothing differs from Godot (glow_tex is source_color: decoded like Godot's; glow_color is a Color property, linearised
// like Godot's source_color).
Shader "Fatebound/gd/scripts/siege/team_swap"
{
    Properties
    {
        albedo_tex ("albedo_tex", 2D) = "white" {}
        glow_tex ("glow_tex", 2D) = "black" {}
        team ("team", Float) = 0
        hue_range ("hue_range", Vector) = (195.0, 258.0, 0, 0)
        sat_range ("sat_range", Vector) = (0.42, 0.58, 0, 0)
        glow_color ("glow_color", Color) = (1, 1, 1, 1)
        glow_energy ("glow_energy", Float) = 0
        roughness_v ("roughness_v", Float) = 0.75
        specular_v ("specular_v", Float) = 0.45
    }

    HLSLINCLUDE
    #include "../../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float team;
        float4 hue_range;
        float4 sat_range;
        float4 glow_color;
        float glow_energy;
        float roughness_v;
        float specular_v;
    CBUFFER_END

    TEXTURE2D(albedo_tex);
    TEXTURE2D(glow_tex);

    struct Attributes
    {
        float4 positionOS : POSITION;
        float3 normalOS : NORMAL;
        float2 uv : TEXCOORD0;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float3 positionWS : TEXCOORD0;
        float3 normalWS : TEXCOORD1;
        float2 uv : TEXCOORD2;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    float3 swap_rgb2hsv(float3 c)
    {
        float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
        float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
        float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
        float d = q.x - min(q.w, q.y);
        return float3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
    }

    float3 swap_hsv2rgb(float3 c)
    {
        float3 p = abs(frac(c.xxx + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
        return c.z * lerp(1.0, clamp(p - 1.0, 0.0, 1.0), c.y);
    }

    Varyings SwapVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
        o.positionCS = TransformWorldToHClip(o.positionWS);
        o.normalWS = TransformObjectToWorldNormal(v.normalOS);
        o.uv = v.uv;
        return o;
    }
    ENDHLSL

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" "Queue" = "Geometry" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            Cull Back
            ZWrite On
            ZTest LEqual
            Blend Off

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex SwapVert
            #pragma fragment SwapFrag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            float4 SwapFrag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float3 col = FB_SAMPLE(albedo_tex, sampler_TrilinearRepeat, i.uv).rgb;
                int tm = (int)team;
                if (tm != 0)
                {
                    float3 s = pow(max(col, 0.0), 1.0 / 2.2);      // the swap rule works on the painted (sRGB) colours
                    float3 h = swap_rgb2hsv(s);
                    float deg = h.x * 360.0;
                    float w = smoothstep(hue_range.x - 8.0, hue_range.x + 4.0, deg) * (1.0 - smoothstep(hue_range.y - 4.0, hue_range.y + 8.0, deg));
                    w *= smoothstep(sat_range.x, sat_range.y, h.y);
                    float3 swapped;
                    if (tm == 1) swapped = swap_hsv2rgb(float3(358.0 / 360.0, min(h.y * 1.05, 1.0), h.z * 0.95));
                    else swapped = swap_hsv2rgb(float3(h.x, h.y * 0.08, min(h.z * 1.12 + 0.1, 0.92)));
                    col = pow(lerp(s, swapped, w), 2.2);
                }
                FBSurface surf = FB_GodotSurface(i.positionWS, normalize(i.normalWS));
                surf.albedo = FB_ApplyDecals(col, i.positionWS, surf.normalWS);
                surf.roughness = roughness_v;
                surf.specular = specular_v;
                surf.emission = glow_color.rgb * FB_SAMPLE(glow_tex, sampler_TrilinearRepeat, i.uv).r * glow_energy;
                float3 c = FB_Shade(surf, GetNormalizedScreenSpaceUV(i.positionCS));
                c = FB_MixFog(c, i.positionWS);
                return float4(c, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex SwapShadowVert
            #pragma fragment SwapShadowFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            Varyings SwapShadowVert(Attributes v)
            {
                Varyings o = SwapVert(v);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - o.positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif
                o.positionCS = ApplyShadowClamping(TransformWorldToHClip(ApplyShadowBias(o.positionWS, o.normalWS, lightDirectionWS)));
                return o;
            }

            float4 SwapShadowFrag(Varyings i) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On
            ColorMask R
            Cull Back

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex SwapVert
            #pragma fragment SwapDepthFrag
            #pragma multi_compile_instancing

            float4 SwapDepthFrag(Varyings i) : SV_Target
            {
                return i.positionCS.z;
            }
            ENDHLSL
        }
    }
    FallBack Off
}
