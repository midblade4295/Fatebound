// Port of the inline shader siege_view.gd's _cloud_floor_material builds (the castle floor with the terrain's drifting
// cloud shadows): its texture (uv_scale) times tint_col, darkened under the clouds.
// render_mode specular_disabled (diffuse_burley, cull_back by default) -> opaque, lit.
// As Godot: wpos is Godot's world position (the clouds drift where they do over the terrain). cloud_tex has no
// source_color: read raw (FB_Raw). tint_col (source_color, no default) defaults to Godot's black.
Shader "Fatebound/gd/inline/siege_view_cloud_floor"
{
    Properties
    {
        tex ("tex", 2D) = "white" {}
        cloud_tex ("cloud_tex", 2D) = "white" {}
        tint_col ("tint_col", Color) = (0, 0, 0, 1)
        cloud_strength ("cloud_strength", Float) = 0.2
        uv_scale ("uv_scale", Float) = 1
    }

    HLSLINCLUDE
    #include "../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float4 tint_col;
        float cloud_strength;
        float uv_scale;
    CBUFFER_END

    TEXTURE2D(tex);
    TEXTURE2D(cloud_tex);

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

    Varyings FloorVert(Attributes v)
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
            #pragma vertex FloorVert
            #pragma fragment FloorFrag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            float4 FloorFrag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float TIME = _FB_Time;
                float3 wpos = FB_Mirror(i.positionWS);
                float cl = smoothstep(0.46, 0.74, FB_Raw(FB_SAMPLE(cloud_tex, sampler_TrilinearRepeat, wpos.xz / 95.0 + float2(TIME * 0.006, TIME * 0.0035))).r);
                float3 albedo = FB_SAMPLE(tex, sampler_TrilinearRepeat, i.uv * uv_scale).rgb * tint_col.rgb * (1.0 - cloud_strength * cl);
                FBSurface s = FB_GodotSurface(i.positionWS, normalize(i.normalWS));
                s.albedo = FB_ApplyDecals(albedo, i.positionWS, s.normalWS);
                s.roughness = 0.95;
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
            #pragma vertex FloorShadowVert
            #pragma fragment FloorShadowFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            Varyings FloorShadowVert(Attributes v)
            {
                Varyings o = FloorVert(v);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - o.positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif
                o.positionCS = ApplyShadowClamping(TransformWorldToHClip(ApplyShadowBias(o.positionWS, o.normalWS, lightDirectionWS)));
                return o;
            }

            float4 FloorShadowFrag(Varyings i) : SV_Target
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
            #pragma vertex FloorVert
            #pragma fragment FloorDepthFrag
            #pragma multi_compile_instancing

            float4 FloorDepthFrag(Varyings i) : SV_Target
            {
                return i.positionCS.z;
            }
            ENDHLSL
        }
    }
    FallBack Off
}
