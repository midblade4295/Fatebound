// Port of res://scripts/siege/outer_land.gdshader (the land beyond the playfield): the terrain's painted lawn with a
// broad meadow variation from 10 m out of the baked rect, triplanar rock on steep or high ground (mossy on top), snow
// on the peaks, the drifting cloud shadows.
// render_mode specular_disabled (diffuse_burley, cull_back by default) -> opaque, lit.
// As Godot: wpos / wnorm are Godot's world-space position and (model-matrix) normal -- the mask rect, the meadow and
// snow waves and the triplanar planes use Godot's x. macro_tex and cloud_tex have no source_color: read raw (FB_Raw).
// path_mask is declared (the material sets it) but, as in Godot, not read.
Shader "Fatebound/gd/scripts/siege/outer_land"
{
    Properties
    {
        grass_tex ("grass_tex", 2D) = "white" {}
        rock_tex ("rock_tex", 2D) = "white" {}
        path_mask ("path_mask", 2D) = "white" {}
        mask_rect ("mask_rect", Vector) = (0, 0, 0, 0)
        grass_scale ("grass_scale", Float) = 9
        rock_scale ("rock_scale", Float) = 4
        tint ("tint", Vector) = (1, 1, 1, 0)
        grass_sat ("grass_sat", Float) = 1
        cloud_tex ("cloud_tex", 2D) = "white" {}
        cloud_strength ("cloud_strength", Float) = 0
        macro_tex ("macro_tex", 2D) = "white" {}
        rock_col ("rock_col", Vector) = (1, 1, 1, 0)
    }

    HLSLINCLUDE
    #include "../../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float4 mask_rect;
        float grass_scale;
        float rock_scale;
        float4 tint;
        float grass_sat;
        float cloud_strength;
        float4 rock_col;
    CBUFFER_END

    TEXTURE2D(grass_tex);
    TEXTURE2D(rock_tex);
    TEXTURE2D(path_mask);
    TEXTURE2D(cloud_tex);
    TEXTURE2D(macro_tex);

    struct Attributes
    {
        float4 positionOS : POSITION;
        float3 normalOS : NORMAL;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float3 positionWS : TEXCOORD0;
        float3 normalWS : TEXCOORD1;
        float3 wpos : TEXCOORD2;       // Godot's world position
        float3 wnorm : TEXCOORD3;      // Godot's world normal (MODEL_MATRIX * NORMAL, normalised per vertex)
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    Varyings OuterVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
        o.positionCS = TransformWorldToHClip(o.positionWS);
        o.normalWS = TransformObjectToWorldNormal(v.normalOS);
        o.wpos = FB_Mirror(o.positionWS);
        o.wnorm = normalize(FB_Mirror(TransformObjectToWorldDir(v.normalOS, false)));
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
            #pragma vertex OuterVert
            #pragma fragment OuterFrag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            float4 OuterFrag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float TIME = _FB_Time;
                float3 wpos = i.wpos;
                float3 wnorm = i.wnorm;
                float2 rmin = mask_rect.xy;
                float2 q = clamp(wpos.xz, rmin, rmin + mask_rect.zw);
                float d = length(wpos.xz - q);
                float3 g = FB_SAMPLE(grass_tex, sampler_TrilinearRepeat, wpos.xz / grass_scale).rgb;
                g *= lerp(1.0, 0.94 + 0.06 * sin(wpos.x * 0.013 + wpos.z * 0.011), smoothstep(4.0, 14.0, d));   // broad meadow variation
                float gl = dot(g, float3(0.299, 0.587, 0.114));
                g = lerp(gl.xxx, g, grass_sat);
                float3 col = g;
                float mn = FB_Raw(FB_SAMPLE(macro_tex, sampler_TrilinearRepeat, wpos.xz / 38.0)).r;
                float steep = 1.0 - clamp(wnorm.y, 0.0, 1.0);
                float jit = (mn - 0.5) * 0.24 + (g.g - 0.55) * 0.35;
                float rockw = clamp(smoothstep(0.30, 0.52, steep + jit) + 0.85 * smoothstep(20.0, 32.0, wpos.y + jit * 8.0), 0.0, 1.0);
                if (rockw > 0.001)
                {
                    float3 an = pow(abs(wnorm), 4.0);
                    an /= (an.x + an.y + an.z);
                    float3 r = FB_SAMPLE(rock_tex, sampler_TrilinearRepeat, float2(wpos.z, -wpos.y) / rock_scale).rgb * an.x
                        + FB_SAMPLE(rock_tex, sampler_TrilinearRepeat, wpos.xz / rock_scale).rgb * an.y
                        + FB_SAMPLE(rock_tex, sampler_TrilinearRepeat, float2(wpos.x, -wpos.y) / rock_scale).rgb * an.z;
                    r *= rock_col.rgb * (0.9 + 0.1 * sin(wpos.y * 2.4 + mn * 7.0));
                    float moss = smoothstep(0.6, 0.9, wnorm.y) * smoothstep(0.42, 0.62, mn + (g.g - 0.55));
                    r = lerp(r, g * 0.9, moss * 0.65);
                    col = lerp(col, r, rockw);
                }
                float snow = smoothstep(38.0, 46.0, wpos.y + 3.0 * sin(wpos.x * 0.2)) * (1.0 - smoothstep(0.55, 0.8, steep));
                col = lerp(col, float3(0.93, 0.95, 0.98), snow);
                float cl = smoothstep(0.46, 0.74, FB_Raw(FB_SAMPLE(cloud_tex, sampler_TrilinearRepeat, wpos.xz / 95.0 + float2(TIME * 0.006, TIME * 0.0035))).r);

                FBSurface s = FB_GodotSurface(i.positionWS, normalize(i.normalWS));
                s.albedo = FB_ApplyDecals(col * tint.rgb * (1.0 - cloud_strength * cl), i.positionWS, s.normalWS);
                s.roughness = lerp(0.95, 0.88, rockw);
                s.specularOn = 0.0;
                float3 c = FB_Shade(s, GetNormalizedScreenSpaceUV(i.positionCS));
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
            #pragma vertex OuterShadowVert
            #pragma fragment OuterShadowFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            Varyings OuterShadowVert(Attributes v)
            {
                Varyings o = OuterVert(v);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - o.positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif
                o.positionCS = ApplyShadowClamping(TransformWorldToHClip(ApplyShadowBias(o.positionWS, o.normalWS, lightDirectionWS)));
                return o;
            }

            float4 OuterShadowFrag(Varyings i) : SV_Target
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
            #pragma vertex OuterVert
            #pragma fragment OuterDepthFrag
            #pragma multi_compile_instancing

            float4 OuterDepthFrag(Varyings i) : SV_Target
            {
                return i.positionCS.z;
            }
            ENDHLSL
        }
    }
    FallBack Off
}
