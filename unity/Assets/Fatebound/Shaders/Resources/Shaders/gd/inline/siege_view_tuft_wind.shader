// Port of the inline shader siege_view.gd's _tuft_material builds for High-quality graphics (the grass tufts swaying in
// rolling gusts: tips move, roots stay).
// render_mode cull_disabled, vertex_lighting, specular_disabled -> opaque, lit, both faces.
// As Godot: the sway is computed in Godot's object space (VERTEX.x / .z) with wp in Godot's world; the shadow and depth
// passes sway the same way; Godot's DO_SIDE_CHECK turns NORMAL round on back faces.
// APPROXIMATED: vertex_lighting. Godot's Mobile renderer lights these per vertex (Lambert -- vertex lighting ignores
// diffuse_burley -- with the first directional light's shadow still sampled per pixel); here the same Lambert terms
// are evaluated per pixel (FB_Shade, Burley off). On these tiny triangles the two match; it costs a little more.
Shader "Fatebound/gd/inline/siege_view_tuft_wind"
{
    Properties
    {
        albedo_tex ("albedo_tex", 2D) = "white" {}
        albedo_col ("albedo_col", Color) = (1, 1, 1, 1)
        use_tex ("use_tex", Float) = 0
    }

    HLSLINCLUDE
    #include "../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float4 albedo_col;
        float use_tex;
    CBUFFER_END

    TEXTURE2D(albedo_tex);

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

    // Godot's vertex(): VERTEX in Godot's object space
    float3 TuftVertex(float3 positionOS)
    {
        float3 V = FB_Mirror(positionOS);
        float3 wp = FB_Mirror(TransformObjectToWorld(positionOS));      // (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz
        float TIME = _FB_Time;
        float h = clamp(V.y / 0.5, 0.0, 1.0);
        float gust = sin(TIME * 1.3 + wp.x * 0.18 + wp.z * 0.11) * 0.5 + 0.5;
        float flutter = sin(TIME * 4.2 + wp.x * 1.3 + wp.z * 0.9);
        float sway = (gust * 0.10 + flutter * 0.025) * h;
        V.x += sway;
        V.z += sway * 0.5;
        return FB_Mirror(V);
    }

    Varyings TuftVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        o.positionWS = TransformObjectToWorld(TuftVertex(v.positionOS.xyz));
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
            Cull Off
            ZWrite On
            ZTest LEqual
            Blend Off

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex TuftVert
            #pragma fragment TuftFrag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            float4 TuftFrag(Varyings i, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float3 c = albedo_col.rgb;
                if (use_tex > 0.5)
                {
                    c *= FB_SAMPLE(albedo_tex, sampler_TrilinearRepeat, i.uv).rgb;
                }
                FBSurface s = FB_GodotSurface(i.positionWS, FB_SideNormal(normalize(i.normalWS), IS_FRONT_VFACE(frontFace, 1.0, -1.0)));
                s.albedo = FB_ApplyDecals(c, i.positionWS, s.normalWS);
                s.diffuseBurley = 0.0;          // (vertex lighting is Lambert)
                s.specularOn = 0.0;
                float3 col = FB_Shade(s, GetNormalizedScreenSpaceUV(i.positionCS));
                col = FB_MixFog(col, i.positionWS);
                return float4(col, 1.0);
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
            Cull Off

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex TuftShadowVert
            #pragma fragment TuftShadowFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            Varyings TuftShadowVert(Attributes v)
            {
                Varyings o = TuftVert(v);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - o.positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif
                o.positionCS = ApplyShadowClamping(TransformWorldToHClip(ApplyShadowBias(o.positionWS, o.normalWS, lightDirectionWS)));
                return o;
            }

            float4 TuftShadowFrag(Varyings i) : SV_Target
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
            Cull Off

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex TuftVert
            #pragma fragment TuftDepthFrag
            #pragma multi_compile_instancing

            float4 TuftDepthFrag(Varyings i) : SV_Target
            {
                return i.positionCS.z;
            }
            ENDHLSL
        }
    }
    FallBack Off
}
